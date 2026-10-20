// Волна 26, плавность: стор не разбирает один и тот же JSON по пять раз на тап, сцена не ищет комнату
// по всему дереву на каждом кадре. Кэш не должен менять поведение: чужая запись (виджет, интент), порча
// файла, стирание — всё видно сразу, как и без кэша.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore
#if canImport(UIKit) && canImport(RealityKit)
import RealityKit
#endif

private let sT0: Double = 1_760_000_000

/// Байты файла как их пишет стор (sortedKeys): так сравниваем «то же самое», не требуя Equatable от SaveFile.
private func sJSON(_ f: SaveFile?) throws -> Data {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    return try enc.encode(f)
}

final class SmoothTests: XCTestCase {

    // MARK: стор

    /// Тап в приложении: read → mutate → refresh → afterChange (load) → уведомления (load). Было ~5 разборов, стало 1:
    /// правка берёт уже разобранное чтением перед ней, первое чтение после записи разбирает, дальше из памяти.
    func testOneMutateManyReadsDecodesOnce() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-smooth")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: sT0)
        _ = try store.read()
        let before = store.decodes
        _ = try store.read()
        _ = try store.read()
        XCTAssertEqual(store.decodes, before, "файл не менялся — чтение из памяти")

        try store.mutate { (f: inout SaveFile) -> Void in f.debugMarker = 42 }
        var markers: [Double] = []
        for _ in 0..<5 { markers.append(try store.read()?.debugMarker ?? .nan) }
        XCTAssertEqual(markers, Array(repeating: 42, count: 5))
        XCTAssertEqual(store.decodes - before, 1, "правка — из памяти, первое чтение после записи — единственный разбор")
    }

    /// Из памяти — ровно то, что прочёл бы свежий стор с диска (кэш не подменяет файл своим представлением).
    func testCachedReadMatchesFreshRead() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-smooth")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: sT0)
        for i in 1...3 {
            try store.mutate { (f: inout SaveFile) -> Void in
                f.debugMarker = Double(i)
                f.log("smooth_test", t: sT0 + Double(i), ok: true)
            }
        }
        _ = try store.read()
        let cached = try sJSON(try store.read())
        let fresh = try sJSON(try PetStore(dir: dir).read())
        XCTAssertEqual(cached, fresh)
    }

    /// Виджет или интент (другой процесс — здесь другой экземпляр стора) записал: приложение видит новое сразу.
    func testOtherWriterInvalidates() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-smooth")
        defer { StoreHooks.removeTempStore(dir) }
        let app = PetStore(dir: dir)
        try app.startOver(now: sT0)
        try app.mutate { (f: inout SaveFile) -> Void in f.debugMarker = 1 }
        XCTAssertEqual(try app.read()?.debugMarker, 1)

        let widget = PetStore(dir: dir)
        try widget.mutate { (f: inout SaveFile) -> Void in f.debugMarker = 7 }
        XCTAssertEqual(try app.read()?.debugMarker, 7, "чужая атомарная запись — новый отпечаток файла")

        // И правка приложения поверх — от чужой записи, а не от своей старой копии.
        try app.mutate { (f: inout SaveFile) -> Void in f.debugMarker = (f.debugMarker ?? 0) + 1 }
        XCTAssertEqual(try widget.read()?.debugMarker, 8)
    }

    /// Запись в файл на месте (не атомарно, тот же inode): размер и время другие — кэш мимо.
    func testInPlaceWriteInvalidates() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-smooth")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: sT0)
        try store.mutate { (f: inout SaveFile) -> Void in f.debugMarker = 3 }
        _ = try store.read()

        let other = PetStore(dir: dir)
        guard var f = try other.read() else { return XCTFail("нет сохранения") }
        f.debugMarker = 123_456
        try sJSON(f).write(to: store.stateURL)
        XCTAssertEqual(try store.read()?.debugMarker, 123_456)
    }

    /// Файл испортили после чтения: ошибка или копия, как без кэша, а не старое из памяти.
    func testCorruptionAfterCacheIsSeen() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-smooth")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: sT0)
        try store.mutate { (f: inout SaveFile) -> Void in f.debugMarker = 5 }
        try store.mutate { (f: inout SaveFile) -> Void in f.debugMarker = 6 }
        XCTAssertEqual(try store.read()?.debugMarker, 6)
        try Data("{ \"pet\": ".utf8).write(to: store.stateURL)
        // Копия (state.bak.json) — прошлая запись: читатель восстанавливает в памяти.
        XCTAssertEqual(try store.read()?.debugMarker, 5, "испорченный файл не прикрыт кэшем")
    }

    /// Стёрли (PET_RESET) — первого запуска не скрыть кэшем.
    func testWipeForgetsCache() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-smooth")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir, mayCreate: true)
        try store.startOver(now: sT0)
        XCTAssertNotNil(try store.read())
        store.wipe()
        XCTAssertNil(try store.read(), "после стирания — первый запуск")
    }

    /// Начать заново: новый щенок, а не прежний из памяти.
    func testStartOverReplacesCache() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-smooth")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: sT0)
        try store.mutate { (f: inout SaveFile) -> Void in f.debugMarker = 9 }
        XCTAssertEqual(try store.read()?.debugMarker, 9)
        try store.startOver(now: sT0 + 100)
        XCTAssertNotEqual(try store.read()?.debugMarker, 9)
    }

    func testFileStampFollowsAtomicRewrite() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-smooth")
        defer { StoreHooks.removeTempStore(dir) }
        let url = dir.appendingPathComponent("stamp.json")
        try Data("abc".utf8).write(to: url, options: .atomic)
        let a = PetStore.FileStamp.of(url.path)
        XCTAssertNotNil(a)
        XCTAssertEqual(a, PetStore.FileStamp.of(url.path), "тот же файл — тот же отпечаток")
        try Data("abc".utf8).write(to: url, options: .atomic)
        XCTAssertNotEqual(a, PetStore.FileStamp.of(url.path), "атомарная запись тех же байтов — новый файл")
        XCTAssertNil(PetStore.FileStamp.of(dir.appendingPathComponent("нет.json").path))
    }

    // MARK: сцена (только в Xcode: RealityKit)

    #if canImport(UIKit) && canImport(RealityKit)
    @MainActor
    func testRoomPartsFoundOnceAndRefound() {
        let room = Entity()
        room.name = "room"
        let bowl = Entity()
        bowl.name = "bowl"
        let food = Entity()
        food.name = "food"
        bowl.addChild(food)
        room.addChild(bowl)
        XCTAssertTrue(PetChoreo.roomPart(room, "bowl") === bowl)
        XCTAssertTrue(PetChoreo.roomPart(bowl, "food") === food)
        XCTAssertTrue(PetChoreo.roomPart(room, "food") === food, "и глубже, как findEntity")
        XCTAssertNil(PetChoreo.roomPart(room, "ball"))

        // Миску сняли и поставили новую — находим новую, а не держим старую.
        bowl.removeFromParent()
        XCTAssertNil(PetChoreo.roomPart(room, "bowl"))
        let bowl2 = Entity()
        bowl2.name = "bowl"
        room.addChild(bowl2)
        XCTAssertTrue(PetChoreo.roomPart(room, "bowl") === bowl2)
        // Переименовали — тоже мимо кэша.
        bowl2.name = "plate"
        XCTAssertNil(PetChoreo.roomPart(room, "bowl"))
    }

    @MainActor
    func testClipNamesFollowTable() {
        let saved = ClipTable.shared
        defer { ClipTable.shared = saved }
        ClipTable.shared = ClipTable(fps: 24, clips: ["idle": .init(start: 0, end: 1, loop: true)])
        XCTAssertEqual(ClipTable.sharedNames, ["idle"])
        XCTAssertEqual(PetChoreo.availableClips(), ["idle"])
        ClipTable.shared = ClipTable(fps: 24, clips: ["idle": .init(start: 0, end: 1, loop: true),
                                                      "hop": .init(start: 1, end: 2, loop: false)])
        XCTAssertEqual(ClipTable.sharedNames, ["idle", "hop"], "новая таблица (свой персонаж) — новый набор")
        ClipTable.shared = nil
        XCTAssertEqual(ClipTable.sharedNames, [])
    }
    #endif
}
