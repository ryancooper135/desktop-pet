// Свой персонаж — до конца (волна 14): установка и удаление пака надёжно. Копия во временную папку и подмена
// переименованиями; сбой посреди копирования не трогает старый пак; хвосты прерванной подмены (убили приложение)
// разбирает recover; аватар пака — свой avatar.png или снимок морды. Гоняется и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

final class CharacterStoreTests: XCTestCase {
    private var tmp: URL!
    private var store: CharacterStore!

    override func setUp() {
        super.setUp()
        tmp = StoreHooks.makeTempStoreDir("pet-chars-w14")
        store = CharacterStore(root: tmp.appendingPathComponent("characters"))
    }

    override func tearDown() {
        StoreHooks.removeTempStore(tmp)
        super.tearDown()
    }

    private func config(_ name: String) -> CharacterConfig {
        var clips: [String: CharacterConfig.Range] = [:]
        for (i, n) in CharacterPack.allClips.enumerated() {
            clips[n] = CharacterConfig.Range(start: Double(i), end: Double(i) + 1, loop: nil)
        }
        return CharacterConfig(name: name, clips: clips)
    }

    /// Положить пак напрямую (как сид charpack): конфиг и «модель» с меткой.
    @discardableResult
    private func put(_ id: String, name: String, model: String = "v1") throws -> CharacterStore.Entry {
        try store.place(id: id) { dir in
            try JSONEncoder().encode(self.config(name)).write(to: dir.appendingPathComponent(CharacterPack.configName))
            try Data(model.utf8).write(to: dir.appendingPathComponent(CharacterPack.defaultModel))
        }
    }

    private func modelText(_ id: String) -> String? {
        (try? Data(contentsOf: store.root.appendingPathComponent("\(id)/\(CharacterPack.defaultModel)")))
            .flatMap { String(data: $0, encoding: .utf8) }
    }

    private func names() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: store.root.path)) ?? []).sorted()
    }

    struct Boom: Error {}

    // MARK: установка

    func testFailureMidCopyKeepsOldPack() throws {
        try put("cat", name: "Кот", model: "old")
        XCTAssertThrowsError(try store.place(id: "cat") { dir in
            // Половина файлов уже легла — и тут кончилось место.
            try Data("new".utf8).write(to: dir.appendingPathComponent(CharacterPack.defaultModel))
            throw Boom()
        }) { e in
            XCTAssertTrue((e as? CharacterPackError)?.message.hasPrefix("Не скопировалось") == true, "\(e)")
        }
        XCTAssertEqual(modelText("cat"), "old", "старый пак не тронут")
        XCTAssertEqual(store.entry("cat")?.name, "Кот")
        XCTAssertEqual(names(), ["cat"], "временная папка стёрта, бэкапа нет")
    }

    func testFailureOnFirstInstallLeavesNothing() {
        XCTAssertThrowsError(try store.place(id: "new") { _ in throw CharacterPackError("нет места") }) { e in
            XCTAssertEqual((e as? CharacterPackError)?.message, "нет места", "своя ошибка — как есть")
        }
        XCTAssertNil(store.entry("new"))
        XCTAssertEqual(store.list(), [])
        XCTAssertEqual(names(), [])
    }

    func testReplaceSwapsWholeFolder() throws {
        try put("cat", name: "Кот", model: "old")
        // Старый лишний файл не должен пережить замену: пак ставится целиком, а не поверх.
        try Data("x".utf8).write(to: store.root.appendingPathComponent("cat/leftover.txt"))
        let e = try put("cat", name: "Кот 2", model: "new")
        XCTAssertEqual(e.name, "Кот 2")
        XCTAssertEqual(modelText("cat"), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("cat/leftover.txt").path))
        XCTAssertEqual(names(), ["cat"], "ни .incoming, ни .old не осталось")
    }

    func testPlaceRefusesServiceNames() {
        for bad in ["", ".old-x.cat", "../cat", "a/b"] {
            XCTAssertThrowsError(try store.place(id: bad) { _ in }, "«\(bad)»")
        }
        XCTAssertEqual(names(), [])
    }

    // MARK: хвосты

    func testRecoverRestoresInterruptedSwap() throws {
        try put("cat", name: "Кот", model: "old")
        let fm = FileManager.default
        // Убили между переименованиями: старый уже в .old, новый ещё в .incoming.
        try fm.moveItem(at: store.root.appendingPathComponent("cat"),
                        to: store.root.appendingPathComponent(".old-1234.cat"))
        try fm.createDirectory(at: store.root.appendingPathComponent(".incoming-5678"), withIntermediateDirectories: true)
        try fm.createDirectory(at: store.root.appendingPathComponent(".trash-9"), withIntermediateDirectories: true)
        XCTAssertEqual(store.list(), [], "посреди подмены пака не видно")
        XCTAssertEqual(store.recover(), 3)
        XCTAssertEqual(modelText("cat"), "old", "старый вернулся")
        XCTAssertEqual(names(), ["cat"])
        XCTAssertEqual(store.recover(), 0, "второй раз разбирать нечего")
    }

    func testRecoverDropsBackupWhenNewPackStands() throws {
        try put("cat", name: "Кот", model: "new")
        let old = store.root.appendingPathComponent(".old-1.cat")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        // Бэкап с хитрым именем не выводит из папки.
        try FileManager.default.createDirectory(at: store.root.appendingPathComponent(".old-2..."),
                                                withIntermediateDirectories: true)
        store.recover()
        XCTAssertEqual(modelText("cat"), "new", "новый пак на месте, бэкап не поверх")
        XCTAssertEqual(names(), ["cat"])
    }

    func testPlaceCleansOldTailsFirst() throws {
        try FileManager.default.createDirectory(at: store.root.appendingPathComponent(".incoming-dead"),
                                                withIntermediateDirectories: true)
        try put("cat", name: "Кот")
        XCTAssertEqual(names(), ["cat"])
    }

    // MARK: удаление

    func testDeleteIsWholeAndQuiet() throws {
        try put("cat", name: "Кот")
        try put("dog", name: "Пёс")
        try store.delete("cat")
        XCTAssertNil(store.entry("cat"))
        XCTAssertEqual(store.list().map(\.id), ["dog"])
        XCTAssertEqual(names(), ["dog"], "корзина стёрта")
        // Нет такого или служебное имя — ничего не делаем и не падаем.
        XCTAssertNoThrow(try store.delete("cat"))
        XCTAssertNoThrow(try store.delete(".."))
        XCTAssertNoThrow(try store.delete(".trash-x"))
        XCTAssertEqual(store.list().map(\.id), ["dog"])
    }

    // MARK: аватар

    func testAvatarOwnThenSnapshot() throws {
        let e = try put("cat", name: "Кот")
        XCTAssertNil(e.avatarURL, "ни картинки, ни снимка")
        XCTAssertFalse(e.hasOwnAvatar)
        XCTAssertTrue(e.avatarCacheURL.lastPathComponent.hasPrefix("."), "снимок скрытый — install его не копирует")
        try Data("png".utf8).write(to: e.avatarCacheURL)
        XCTAssertEqual(e.avatarURL, e.avatarCacheURL)
        try Data("png".utf8).write(to: e.folder.appendingPathComponent(CharacterStore.avatarName))
        XCTAssertTrue(e.hasOwnAvatar)
        XCTAssertEqual(e.avatarURL?.lastPathComponent, "avatar.png", "свой важнее снимка")
    }

    func testReinstallDropsSnapshot() throws {
        let e = try put("cat", name: "Кот", model: "old")
        try Data("png".utf8).write(to: e.avatarCacheURL)
        let src = tmp.appendingPathComponent("inbox/cat")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try JSONEncoder().encode(config("Кот")).write(to: src.appendingPathComponent(CharacterPack.configName))
        try Data("new".utf8).write(to: src.appendingPathComponent(CharacterPack.defaultModel))
        try Data("stale".utf8).write(to: src.appendingPathComponent(CharacterStore.avatarCacheName))
        let again = try store.install(folder: src)
        XCTAssertNil(again.avatarURL, "новая модель — снимок снимется заново, чужой скрытый файл не скопирован")
    }

    /// Волна 15: переустановка в ту же папку — новая метка, по ней шапка сбрасывает аватар без перезапуска.
    func testReinstallSameFolderChangesStamp() throws {
        let first = try put("cat", name: "Кот", model: "old")
        XCTAssertFalse(first.stamp.isEmpty, "у установки есть метка")
        XCTAssertEqual(store.entry("cat")?.stamp, first.stamp, "метка читается та же, пока пак не трогали")
        XCTAssertEqual(store.list().map(\.id), ["cat"], "метка скрытая — в список не попадает")
        let again = try put("cat", name: "Кот", model: "new")
        XCTAssertEqual(again.folder, first.folder, "папка та же")
        XCTAssertNotEqual(again.stamp, first.stamp, "а метка новая")
        XCTAssertNotEqual(again, first, "запись другая — шапка видит смену")
        XCTAssertEqual(CharacterStore.stamp(of: again.folder), again.stamp)
    }

    func testStampFromSourceIsNotCopied() throws {
        let src = tmp.appendingPathComponent("inbox/dog")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try JSONEncoder().encode(config("Пёс")).write(to: src.appendingPathComponent(CharacterPack.configName))
        try Data("m".utf8).write(to: src.appendingPathComponent(CharacterPack.defaultModel))
        try Data("fixed".utf8).write(to: src.appendingPathComponent(CharacterStore.stampName))
        let e = try store.install(folder: src)
        XCTAssertNotEqual(e.stamp, "fixed", "чужая метка не копируется — своя на каждую установку")
        XCTAssertFalse(e.stamp.isEmpty)
    }
}
