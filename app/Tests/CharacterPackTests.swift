// Свой персонаж (волна 12): разбор character.json, ошибки по-русски, обязательные клипы и что отключится,
// rename и подстановки, кости и цвет, тестовый пак из таймлайна Шибы, копирование папки и файлов
// (CharacterStore), поле сейва верхним уровнем и переход к новому щенку.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Все наши клипы куском по секунде: с этим пак проходит проверку.
private func cFull() -> CharacterConfig {
    var clips: [String: CharacterConfig.Range] = [:]
    for (i, n) in CharacterPack.allClips.enumerated() {
        clips[n] = CharacterConfig.Range(start: Double(i), end: Double(i) + 1, loop: nil)
    }
    return CharacterConfig(name: "Кот", clips: clips)
}

private func cJSON(_ s: String) throws -> CharacterConfig {
    try CharacterPack.parse(Data(s.utf8))
}

/// shiba.clips.json из бандла приложения — по пути исходников.
private func shibaTimeline() throws -> CharacterPack.Timeline {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Pets/shiba.clips.json")
    guard let data = try? Data(contentsOf: url) else { throw XCTSkip("нет \(url.path)") }
    return try JSONDecoder().decode(CharacterPack.Timeline.self, from: data)
}

final class CharacterPackTests: XCTestCase {
    // MARK: разбор

    func testMinimalJSONHasShibaDefaults() throws {
        let c = try cJSON(#"{"name": "Дух", "clips": {"idle": {"start": 0, "end": 1}}}"#)
        XCTAssertEqual(c.name, "Дух")
        XCTAssertEqual(CharacterPack.modelName(c), "model.usdz")
        XCTAssertEqual(CharacterPack.height(c, base: 0.42), 0.42, accuracy: 1e-9)
        XCTAssertNil(c.color)
    }

    func testParseErrorsAreRussianAndNameTheField() {
        func err(_ s: String) -> String {
            do { _ = try cJSON(s); return "" } catch { return (error as? CharacterPackError)?.message ?? "\(error)" }
        }
        XCTAssertEqual(err(#"{"clips": {}}"#), "нет поля name — как зовут персонажа?")
        XCTAssertEqual(err(#"{"name": "А"}"#), "нет поля clips — где в модели какие клипы?")
        XCTAssertEqual(err(#"{"name": "А", "clips": {}, "scale": "большой"}"#), "поле scale — не того вида, нужно: число")
        XCTAssertEqual(err(#"{"name": "А", "clips": {"idle": {"start": 0}}}"#), "нет поля clips.idle.end")
        XCTAssertEqual(err(#"{"name": "А" "clips": {}}"#), "character.json — не JSON (проверь запятые и кавычки)")
    }

    // MARK: клипы

    func testFullPackIsOkWithNothingOff() {
        let r = CharacterPack.check(cFull())
        XCTAssertTrue(r.ok, "\(r.errors)")
        XCTAssertEqual(r.off, [])
        XCTAssertEqual(Set(r.clips.keys), Set(CharacterPack.allClips))
    }

    func testMissingRequiredClipIsAnErrorWithReason() {
        var c = cFull()
        c.clips["idle"] = nil
        c.clips["sleep"] = nil
        let r = CharacterPack.check(c)
        XCTAssertFalse(r.ok)
        XCTAssertTrue(r.errors.contains("нет клипа idle — без него пёс не стоит"), "\(r.errors)")
        XCTAssertTrue(r.errors.contains("нет клипа sleep — без него не спит"))
    }

    func testMissingOptionalOnlyTurnsFeaturesOff() {
        var c = cFull()
        for n in ["happy_wag", "sit_in", "idle_2", "gallop"] { c.clips[n] = nil }
        let r = CharacterPack.check(c)
        XCTAssertTrue(r.ok, "\(r.errors)")
        XCTAssertEqual(r.off, ["нет idle_2 — радуется в обычной стойке idle",
                               "нет gallop — на прогулке не бегает, только идёт",
                               "нет sit_in — садится рывком, без перехода",
                               "нет happy_wag — не виляет от радости"])
        // Циклы поз подставляются: радость стоит в idle, бег — шагом. Переход просто пропадает.
        XCTAssertEqual(r.clips["idle_2"], r.clips["idle"])
        XCTAssertEqual(r.clips["gallop"], r.clips["walk"])
        XCTAssertNil(r.clips["sit_in"])
        XCTAssertNil(r.clips["happy_wag"])
    }

    func testRenameMapsOurClipToFileClip() {
        var c = cFull()
        c.clips["Idle_Breath"] = CharacterConfig.Range(start: 40, end: 42, loop: nil)
        c.clips["idle"] = nil
        c.rename = ["idle": "Idle_Breath", "dance": "Dance"]
        let r = CharacterPack.check(c)
        XCTAssertTrue(r.ok, "\(r.errors)")
        XCTAssertEqual(r.clips["idle"], CharacterConfig.Range(start: 40, end: 42, loop: true), "idle — цикл и без loop")
        XCTAssertEqual(r.notes, ["rename: «dance» — такого нашего клипа нет, пропускаю"])
    }

    func testRenameToMissingClipIsAnError() {
        var c = cFull()
        c.rename = ["walk": "Walking"]
        let r = CharacterPack.check(c)
        XCTAssertTrue(r.errors.contains("rename: walk → Walking, а клипа Walking в clips нет"), "\(r.errors)")
        XCTAssertTrue(r.errors.contains("нет клипа walk — без него не уходит гулять"))
    }

    func testBrokenRangeAndExplicitLoop() {
        var c = cFull()
        c.clips["eat"] = CharacterConfig.Range(start: 3, end: 2, loop: nil)
        c.clips["death"] = CharacterConfig.Range(start: 5, end: 6, loop: false)
        let r = CharacterPack.check(c)
        XCTAssertTrue(r.errors.contains("клип eat: конец 2 не позже начала 3"), "\(r.errors)")
        XCTAssertTrue(r.errors.contains("нет клипа eat — без него не ест из миски"))
        XCTAssertEqual(r.clips["death"]?.loop, false)
        XCTAssertEqual(r.clips["sit_in"]?.loop, false, "переходы — не циклы")
    }

    // MARK: остальные поля

    func testFieldLimits() {
        var c = cFull()
        c.format = 2
        c.name = "  "
        c.scale = 5
        c.lift = -1
        c.fps = 0
        c.color = "рыжий"
        c.model = "../shiba.usdz"
        let e = CharacterPack.check(c).errors
        XCTAssertTrue(e.contains("формат 2 — это приложение знает только 1, обнови его"), "\(e)")
        XCTAssertTrue(e.contains("пустое name — как зовут персонажа?"))
        XCTAssertTrue(e.contains("scale 5 — можно от 0,25 до 3"))
        XCTAssertTrue(e.contains("lift -1 м — можно от -0,30 до 0,30"))
        XCTAssertTrue(e.contains("fps 0 — нужно больше нуля"))
        XCTAssertTrue(e.contains("color «рыжий» — нужен вид #RRGGBB"))
        XCTAssertTrue(e.contains("model «../shiba.usdz» — нужно имя файла рядом с character.json, без папок"))
    }

    func testModelFileAndExtension() {
        var c = cFull()
        XCTAssertTrue(CharacterPack.check(c, modelExists: false).errors.contains("нет файла model.usdz рядом с character.json"))
        c.model = "cat.fbx"
        XCTAssertTrue(CharacterPack.check(c).errors.contains("model «cat.fbx» — нужен .usdz (или .usdc, .usda, .reality)"))
        c.model = "Cat.USDZ"
        XCTAssertTrue(CharacterPack.check(c).ok)
    }

    func testColor() {
        XCTAssertEqual(CharacterPack.rgb("#8B8F99"), 0x8B8F99)
        XCTAssertEqual(CharacterPack.rgb("e39a55"), 0xE39A55)
        XCTAssertNil(CharacterPack.rgb("#fff"))
        XCTAssertNil(CharacterPack.rgb("#zzzzzz"))
    }

    func testBoneAliases() {
        XCTAssertEqual(CharacterPack.boneAliases(nil), [:])
        let b = CharacterConfig.Bones(body: "Hips", head: "head", neck: "neck_01", back: ["spine_01", "spine_02"])
        XCTAssertEqual(CharacterPack.boneAliases(b), [
            "Body": "Hips", "Head": "head", "Neck2": "neck_01", "Neck3": "neck_01",
            "Torso": "spine_01", "Torso2": "spine_02", "Torso3": "spine_02",
        ])
        // Совпадает с Шибой — не пишем.
        XCTAssertEqual(CharacterPack.boneAliases(.init(head: "Head", back: [" "])), [:])
    }

    // MARK: тестовый пак из Шибы

    func testSampleFromShibaTimelinePasses() throws {
        let t = try shibaTimeline()
        let c = CharacterPack.sample(t)
        XCTAssertEqual(c.clips["SitIn"], t.clips["sit_in"])
        XCTAssertNil(c.clips["sit_in"], "в файле клипы под другими именами")
        XCTAssertEqual(c.rename?["sit_in"], "SitIn")
        XCTAssertEqual(c.scale, 0.8)
        let r = CharacterPack.check(c)
        XCTAssertTrue(r.ok, "\(r.errors)")
        // Шиба собрана со всеми клипами контракта — ни одной ошибки, ни одного обязательного не хватает.
        for (clip, _) in CharacterPack.required { XCTAssertNotNil(r.clips[clip], clip) }
        XCTAssertEqual(r.clips["walk"], t.clips["walk"])
        // Пак переживает JSON туда-обратно.
        let back = try CharacterPack.parse(JSONEncoder().encode(c))
        XCTAssertEqual(back, c)
    }

    func testBrokenSampleExplainsWhy() throws {
        let c = CharacterPack.sample(try shibaTimeline(), name: "Без стойки", without: ["idle", "happy_wag"])
        let r = CharacterPack.check(c)
        XCTAssertEqual(r.errors, ["нет клипа idle — без него пёс не стоит"])
        XCTAssertTrue(r.off.contains("нет happy_wag — не виляет от радости"))
    }

    func testCamel() {
        XCTAssertEqual(CharacterPack.camel("sit_in"), "SitIn")
        XCTAssertEqual(CharacterPack.camel("idle"), "Idle")
        XCTAssertEqual(CharacterPack.camel("idle_2"), "Idle2")
    }

    // MARK: на диске

    private func packFolder(_ parent: URL, _ name: String, config: CharacterConfig?, model: Bool = true) throws -> URL {
        let dir = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let config { try JSONEncoder().encode(config).write(to: dir.appendingPathComponent("character.json")) }
        if model { try Data("usdz".utf8).write(to: dir.appendingPathComponent("model.usdz")) }
        return dir
    }

    func testInstallFolderListReplaceDelete() throws {
        let tmp = StoreHooks.makeTempStoreDir("pet-chars")
        defer { StoreHooks.removeTempStore(tmp) }
        let store = CharacterStore(root: tmp.appendingPathComponent("characters"))
        let src = tmp.appendingPathComponent("inbox")
        XCTAssertEqual(store.list(), [])

        let good = try packFolder(src, "Мой кот", config: cFull())
        let e = try store.install(folder: good)
        XCTAssertEqual(e.id, "Мой_кот")
        XCTAssertTrue(e.ok, "\(e.check.errors)")
        XCTAssertEqual(e.modelURL?.lastPathComponent, "model.usdz")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("Мой_кот/model.usdz").path))

        // Пак с ошибкой ставится: в списке видно, что поправить.
        var bad = cFull()
        bad.clips["idle"] = nil
        bad.name = "Аист"
        try store.install(folder: try packFolder(src, "aist", config: bad))
        let list = store.list()
        XCTAssertEqual(list.map(\.name), ["Аист", "Кот"])
        XCTAssertEqual(list[0].check.errors, ["нет клипа idle — без него пёс не стоит"])

        // Та же папка ещё раз — замена, а не второй пак.
        var renamed = cFull()
        renamed.name = "Кот 2"
        try store.install(folder: try packFolder(src, "Мой кот 2", config: renamed))
        try JSONEncoder().encode(renamed).write(to: good.appendingPathComponent("character.json"))
        try store.install(folder: good)
        XCTAssertEqual(store.entry("Мой_кот")?.name, "Кот 2")
        XCTAssertEqual(store.list().count, 3)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: store.root.path).contains { $0.hasPrefix(".") },
                       "временные папки убраны")

        try store.delete("Мой_кот")
        XCTAssertNil(store.entry("Мой_кот"))
        XCTAssertNil(store.entry("../characters"), "id только именем папки")
    }

    func testInstallRefusesFolderWithoutConfig() throws {
        let tmp = StoreHooks.makeTempStoreDir("pet-chars-noconf")
        defer { StoreHooks.removeTempStore(tmp) }
        let store = CharacterStore(root: tmp.appendingPathComponent("characters"))
        let src = try packFolder(tmp.appendingPathComponent("inbox"), "pile", config: nil)
        XCTAssertThrowsError(try store.install(folder: src)) { e in
            XCTAssertEqual((e as? CharacterPackError)?.message, "В папке «pile» нет character.json")
        }
        XCTAssertEqual(store.list(), [])
    }

    func testInstallFilesUsesConfigName() throws {
        let tmp = StoreHooks.makeTempStoreDir("pet-chars-files")
        defer { StoreHooks.removeTempStore(tmp) }
        let store = CharacterStore(root: tmp.appendingPathComponent("characters"))
        let src = try packFolder(tmp.appendingPathComponent("inbox"), "loose", config: cFull())
        let e = try store.install(files: [src.appendingPathComponent("model.usdz"), src.appendingPathComponent("character.json")])
        XCTAssertEqual(e.id, "Кот")
        XCTAssertTrue(e.ok)
        XCTAssertThrowsError(try store.install(files: [src.appendingPathComponent("model.usdz")]))
    }

    func testMissingModelAndBadJSONOnDisk() throws {
        let tmp = StoreHooks.makeTempStoreDir("pet-chars-bad")
        defer { StoreHooks.removeTempStore(tmp) }
        let store = CharacterStore(root: tmp.appendingPathComponent("characters"))
        let src = tmp.appendingPathComponent("inbox")
        try store.install(folder: try packFolder(src, "nomodel", config: cFull(), model: false))
        XCTAssertEqual(store.entry("nomodel")?.check.errors, ["нет файла model.usdz рядом с character.json"])
        let broken = try packFolder(src, "broken", config: nil)
        try Data("{name".utf8).write(to: broken.appendingPathComponent("character.json"))
        let e = try store.install(folder: broken)
        XCTAssertNil(e.config)
        XCTAssertFalse(e.ok)
        XCTAssertEqual(e.name, "broken")
        XCTAssertEqual(e.check.errors, ["character.json — не JSON (проверь запятые и кавычки)"])
    }

    func testId() {
        XCTAssertEqual(CharacterStore.id(for: "Серый Шиба"), "Серый_Шиба")
        XCTAssertEqual(CharacterStore.id(for: "../.hidden"), "hidden")
        XCTAssertEqual(CharacterStore.id(for: "   "), "character")
        XCTAssertEqual(CharacterStore.id(for: String(repeating: "a", count: 60)).count, 40)
    }

    // MARK: сейв

    func testSaveFieldTopLevelAndCarriedToNewPuppy() throws {
        var f = SaveFile.fresh(now: 1_760_000_000)
        let plain = String(decoding: try JSONEncoder().encode(f), as: UTF8.self)
        XCTAssertFalse(plain.contains("\"character\""), "nil в файл не пишется")
        f.character = "Серый_Шиба"
        let back = try JSONDecoder().decode(SaveFile.self, from: try JSONEncoder().encode(f))
        XCTAssertEqual(back.character, "Серый_Шиба")

        let dir = StoreHooks.makeTempStoreDir("pet-chars-save")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: 1_760_000_000)
        try store.mutate { (f: inout SaveFile) -> Void in f.character = "Серый_Шиба" }
        try store.startOver(now: 1_760_000_100)
        XCTAssertEqual(try XCTUnwrap(store.read()).character, "Серый_Шиба", "облик — выбор хозяина, переходит")
    }

    #if canImport(UIKit)
    /// В Xcode видно контракт клипов приложения: у каждого клипа Шибы есть причина или «что отключится».
    func testEveryShibaClipHasAText() {
        let known = Set(CharacterPack.allClips)
        for n in PetClipNames.required + PetClipNames.optional {
            XCTAssertTrue(known.contains(n), "у клипа \(n) нет текста в CharacterPack")
        }
    }
    #endif
}
