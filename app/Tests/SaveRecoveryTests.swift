// Волна 15: щенок умирает только от забвения, а не от сбоя сохранения.
// Обрезанный JSON, нули, пустой файл — продолжаем с state.bak.json; испорчено всё — файлы в corrupt-<дата>,
// новый щенок с записью в журнале; файл есть, но не читается — ошибка, ничего не трогаем; расширение щенка не заводит.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let svT0: Double = 1_760_000_000

private func svNames(_ dir: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
}

/// В приложении (APP_TARGET, Xcode CI) каждая запись обновляет зеркало в Documents — последнюю копию.
/// Тесты «испорчено всё» убирают и его.
private func svDropMirror() { try? FileManager.default.removeItem(at: Paths.mirror) }

/// Стор с щенком, у которого есть монеты и пара записей (bak уже есть).
private func svStore(_ dir: URL, mayCreate: Bool = true) throws -> (PetStore, SaveFile) {
    let store = PetStore(dir: dir, mayCreate: mayCreate)
    try store.startOver(now: svT0)
    for i in 1...3 { try store.mutate { (f: inout SaveFile) -> Void in f.econ.wallet.coins = 1000 + i } }
    return (store, try XCTUnwrap(store.read()))
}

final class SaveRecoveryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Зеркало приложения (APP_TARGET) — отдельная копия; эти тесты про файлы в папке стора.
        try? FileManager.default.removeItem(at: Paths.mirror)
    }

    // MARK: state.bak.json

    func testBakIsPreviousValidState() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-save")
        defer { StoreHooks.removeTempStore(dir) }
        let (store, good) = try svStore(dir)
        let bak = try JSONDecoder().decode(SaveFile.self, from: Data(contentsOf: store.bakURL))
        XCTAssertEqual(bak.rev, good.rev - 1, "bak — ровно прошлая запись")
        XCTAssertEqual(bak.econ.wallet.coins, 1002)
        XCTAssertEqual(bak.petId, good.petId)
    }

    func testBrokenStateVariantsRecoverFromBak() throws {
        let cases: [(String, Data)] = [
            ("обрезанный JSON", Data("{\"v\":1,\"rev\":3,\"pet\":{\"t\":17600".utf8)),
            ("нули", Data(repeating: 0, count: 4096)),
            ("пустой файл", Data()),
            ("не JSON", Data("мусор".utf8)),
            ("JSON без питомца", Data("{\"v\":1,\"rev\":3}".utf8)),
        ]
        for (name, junk) in cases {
            let dir = StoreHooks.makeTempStoreDir("pet-save")
            defer { StoreHooks.removeTempStore(dir) }
            let (store, good) = try svStore(dir)
            // Обрезать настоящий файл посередине — самый частый вид порчи.
            let data = name == "обрезанный JSON" ? try Data(contentsOf: store.stateURL).prefix(200) : junk
            try data.write(to: store.stateURL)

            let seen = try XCTUnwrap(store.read(), name)
            XCTAssertEqual(seen.petId, good.petId, "\(name): читатель видит копию")
            XCTAssertEqual(seen.econ.wallet.coins, 1002, name)
            XCTAssertEqual(try Data(contentsOf: store.stateURL), Data(data), "\(name): читатель файл не трогает")

            try store.mutate { (f: inout SaveFile) -> Void in f.econ.wallet.coins += 10 }
            let f = try XCTUnwrap(store.read())
            XCTAssertEqual(f.petId, good.petId, "\(name): тот же щенок")
            XCTAssertEqual(f.econ.wallet.coins, 1012, "\(name): монеты из bak + новая правка")
            XCTAssertTrue(f.pet.alive, name)
            XCTAssertEqual(svNames(dir).filter { $0.hasPrefix("state.broken-") }.count, 1, "\(name): испорченный отложен")
            XCTAssertFalse(svNames(dir).contains { $0.hasPrefix("corrupt-") }, name)
        }
    }

    func testBrokenStateAndBakFallBackToPrev() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-save")
        defer { StoreHooks.removeTempStore(dir) }
        let (store, good) = try svStore(dir)
        try Data("{".utf8).write(to: store.stateURL)
        try Data(count: 64).write(to: store.bakURL)
        try store.mutate { (f: inout SaveFile) -> Void in f.debugMarker = 5 }
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.petId, good.petId, "prev спасает того же щенка")
        XCTAssertEqual(f.journal.last?.key, "state.prev.json")
        XCTAssertEqual(f.debugMarker, 5)
    }

    // MARK: испорчено всё

    func testAllBrokenQuarantinesAndStartsFreshWithJournalLine() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-save")
        defer { StoreHooks.removeTempStore(dir) }
        let (store, good) = try svStore(dir)
        try Data("{\"pet\":".utf8).write(to: store.stateURL)
        try Data(count: 10).write(to: store.bakURL)
        try Data().write(to: store.prevURL)
        svDropMirror()

        XCTAssertThrowsError(try store.read(), "читатель: ошибка, а не «первый запуск»")
        XCTAssertEqual(svNames(dir).filter { $0.hasPrefix("corrupt-") }, [], "читатель ничего не двигает")

        try store.mutate { (_: inout SaveFile) -> Void in }
        let f = try XCTUnwrap(store.read())
        XCTAssertNotEqual(f.petId, good.petId, "новый щенок — только когда спасать нечего")
        let folders = svNames(dir).filter { $0.hasPrefix("corrupt-") }
        XCTAssertEqual(folders.count, 1, "\(svNames(dir))")
        let folder = try XCTUnwrap(folders.first)
        let inside = svNames(dir.appendingPathComponent(folder))
        XCTAssertEqual(inside, ["state.bak.json", "state.json", "state.prev.json"], "ничего не стёрто")
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(folder).appendingPathComponent("state.json")),
                       Data("{\"pet\":".utf8), "испорченный файл лежит как был")

        let line = try XCTUnwrap(f.journal.first { $0.kind == "save_corrupt" }, "понятная строка в журнале")
        XCTAssertEqual(line.key, folder)
        XCTAssertEqual(line.ok, false)
        XCTAssertTrue(line.reason?.contains("заведён новый щенок") == true, line.reason ?? "")
        XCTAssertEqual(f.outbox.first { $0.kind == "save_corrupt" }?.key, folder, "outbox — с тем же ключом")
        XCTAssertEqual(store.takeRecovery(), .quarantined(folder: folder))
        XCTAssertTrue(folder.hasPrefix("corrupt-20"), folder)
    }

    func testMissingStateWithBrokenCopiesIsCorruptNotFirstRun() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-save")
        defer { StoreHooks.removeTempStore(dir) }
        let (store, _) = try svStore(dir)
        try FileManager.default.removeItem(at: store.stateURL)
        try Data("x".utf8).write(to: store.bakURL)
        try Data("y".utf8).write(to: store.prevURL)
        svDropMirror()
        XCTAssertThrowsError(try store.read())
        try store.mutate { (_: inout SaveFile) -> Void in }
        let folder = try XCTUnwrap(svNames(dir).first { $0.hasPrefix("corrupt-") })
        XCTAssertEqual(svNames(dir.appendingPathComponent(folder)), ["state.bak.json", "state.prev.json"])
    }

    func testThrowingBodyLeavesBrokenFilesInPlace() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-save")
        defer { StoreHooks.removeTempStore(dir) }
        let (store, _) = try svStore(dir)
        try Data("{".utf8).write(to: store.stateURL)
        struct Boom: Error {}
        XCTAssertThrowsError(try store.mutate { (_: inout SaveFile) -> Void in throw Boom() })
        XCTAssertEqual(try Data(contentsOf: store.stateURL), Data("{".utf8), "тело бросило — диск как был")
        XCTAssertFalse(svNames(dir).contains { $0.hasPrefix("state.broken-") })
    }

    // MARK: расширение и недоступный файл

    func testExtensionNeverCreatesPuppy() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-save")
        defer { StoreHooks.removeTempStore(dir) }
        let widget = PetStore(dir: dir, mayCreate: false)
        XCTAssertThrowsError(try widget.mutate { (_: inout SaveFile) -> Void in }) { err in
            guard let se = err as? StoreError, case .noSave = se else { return XCTFail("\(err)") }
        }
        XCTAssertEqual(svNames(dir).filter { $0.hasPrefix("state") }, [], "пустая папка (новый контейнер) — ничего не пишем")

        let (app, good) = try svStore(dir)
        try Data("{".utf8).write(to: app.stateURL)
        try FileManager.default.removeItem(at: app.bakURL)
        try FileManager.default.removeItem(at: app.prevURL)
        svDropMirror()
        XCTAssertThrowsError(try widget.mutate { (_: inout SaveFile) -> Void in }) { err in
            guard let se = err as? StoreError, case .corrupted = se else { return XCTFail("\(err)") }
        }
        XCTAssertEqual(try Data(contentsOf: app.stateURL), Data("{".utf8), "расширение испорченное не двигает")
        XCTAssertFalse(svNames(dir).contains { $0.hasPrefix("corrupt-") })
        _ = good
    }

    func testExtensionMayRepairFromCopy() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-save")
        defer { StoreHooks.removeTempStore(dir) }
        let (_, good) = try svStore(dir)
        let widget = PetStore(dir: dir, mayCreate: false)
        try Data("{".utf8).write(to: widget.stateURL)
        try widget.mutate { (f: inout SaveFile) -> Void in f.debugMarker = 9 }
        let f = try XCTUnwrap(widget.read())
        XCTAssertEqual(f.petId, good.petId, "копия — тот же щенок, чинить можно и из виджета")
        XCTAssertEqual(f.debugMarker, 9)
    }

    func testUnreadableStateIsErrorAndUntouched() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-save")
        defer { StoreHooks.removeTempStore(dir) }
        let (store, _) = try svStore(dir)
        // «Есть, но не читается» (защита до первой разблокировки) — моделируем папкой на месте файла.
        try FileManager.default.removeItem(at: store.stateURL)
        try FileManager.default.createDirectory(at: store.stateURL, withIntermediateDirectories: false)
        for op in ["read", "mutate"] {
            XCTAssertThrowsError(op == "read" ? _ = try store.read() : try store.mutate { (_: inout SaveFile) -> Void in }) { err in
                guard let se = err as? StoreError, case .unavailable = se else { return XCTFail("\(op): \(err)") }
            }
        }
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.stateURL.path, isDirectory: &isDir) && isDir.boolValue)
        XCTAssertFalse(svNames(dir).contains { $0.hasPrefix("corrupt-") || $0.hasPrefix("state.broken-") })
    }

    // MARK: запись не удалась

    func testFailedWriteKeepsOldFile() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-save")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            StoreHooks.removeTempStore(dir)
        }
        let (store, good) = try svStore(dir)
        let before = try Data(contentsOf: store.stateURL)
        // Нет места или нет прав — атомарная запись не может создать временный файл.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        if FileManager.default.isWritableFile(atPath: dir.path) {
            throw XCTSkip("процесс пишет и в папку без прав (root) — не смоделировать")
        }
        XCTAssertThrowsError(try store.mutate { (f: inout SaveFile) -> Void in f.econ.wallet.coins = 1 }) { err in
            guard let se = err as? StoreError, case .writeFailed = se else { return XCTFail("\(err)") }
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        XCTAssertEqual(try Data(contentsOf: store.stateURL), before, "прежний файл цел")
        XCTAssertEqual(try XCTUnwrap(store.read()).econ.wallet.coins, good.econ.wallet.coins)
    }

    // MARK: разное

    func testStartOverRefreshesBak() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-save")
        defer { StoreHooks.removeTempStore(dir) }
        let (store, old) = try svStore(dir)
        try store.startOver(now: svT0 + 100)
        let fresh = try XCTUnwrap(store.read())
        XCTAssertNotEqual(fresh.petId, old.petId)
        try Data("{".utf8).write(to: store.stateURL)
        XCTAssertEqual(try XCTUnwrap(store.read()).petId, fresh.petId, "копия — уже нового щенка, не умершего")
    }

    func testStampIsUTCDate() {
        XCTAssertEqual(PetStore.stamp(1_760_000_000), "2025-10-09-0853")
        XCTAssertEqual(PetStore.stamp(0), "1970-01-01-0000")
    }
}
