// Волна 15: сборки ставятся поверх старых (iloader, v0.7 → v0.14), поэтому сейв любой эпохи обязан открыться.
// Fixtures/save-v<версия>.json — синтетический сейв (без личных данных), записанный кодировщиком той сборки:
// один и тот же «богатый» JSON декодирован и закодирован SaveFile из коммита эпохи (git archive + swift test в WSL).
// Здесь каждая эпоха грузится текущим кодом: тот же щенок, монеты, предметы, трюки, рекорды; ни одно поле не пропало.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let fixturesDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

/// Эпохи по порядку и что в них уже было.
private let epochs: [(v: String, tricks: Bool, catchGame: Bool, life: Bool, blockduo: Bool, zombie: Bool, charName: Bool)] = [
    ("0.7", false, false, false, false, false, false),
    ("0.8", true, false, false, false, false, false),
    ("0.9", true, true, false, false, false, false),
    ("0.10", true, true, false, false, false, false),
    ("0.11", true, true, true, false, false, false),
    ("0.12", true, true, true, true, false, false),
    ("0.13", true, true, true, true, true, false),
    ("0.14", true, true, true, true, true, true),
]

private func fixture(_ v: String) throws -> Data {
    try Data(contentsOf: fixturesDir.appendingPathComponent("save-v\(v).json"))
}

/// Всё, что есть в `old`, есть и в `new` с тем же значением (новые поля в `new` разрешены).
private func missing(_ old: Any, in new: Any?, at path: String = "") -> [String] {
    guard let new else { return [path] }
    if let o = old as? [String: Any] {
        guard let n = new as? [String: Any] else { return [path] }
        return o.keys.sorted().flatMap { missing(o[$0]!, in: n[$0], at: path + "." + $0) }
    }
    if let o = old as? [Any] {
        guard let n = new as? [Any], n.count == o.count else { return [path + "[]"] }
        return o.indices.flatMap { missing(o[$0], in: n[$0], at: path + "[\($0)]") }
    }
    if let o = old as? String { return (new as? String) == o ? [] : [path] }
    if let o = old as? NSNumber, let n = new as? NSNumber {
        return abs(o.doubleValue - n.doubleValue) < 1e-9 ? [] : [path]
    }
    return "\(old)" == "\(new)" ? [] : [path]
}

final class SaveMigrationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: Paths.mirror)
    }

    func testEveryEpochFixtureExists() throws {
        for e in epochs {
            let raw = try fixture(e.v)
            XCTAssertFalse(raw.isEmpty, e.v)
            let s = String(decoding: raw, as: UTF8.self)
            XCTAssertTrue(s.contains("\"fixture-pet\""), "\(e.v): синтетический щенок, без личных данных")
        }
    }

    func testEveryEpochDecodesWithoutLosingAnything() throws {
        for e in epochs {
            let raw = try fixture(e.v)
            let f = try JSONDecoder().decode(SaveFile.self, from: raw)
            let v = e.v
            XCTAssertEqual(f.petId, "fixture-pet", v)
            XCTAssertEqual(f.rev, 321, v)
            XCTAssertEqual(f.name, "Шиба", v)
            XCTAssertEqual(f.createdT, 1_759_136_000, v)
            XCTAssertTrue(f.pet.alive, "\(v): щенок жив")
            XCTAssertEqual(f.pet.hearts, 4, v)
            XCTAssertEqual(f.pet.finds["stick"], 3, v)
            XCTAssertEqual(f.pet.pantry, 2, v)
            XCTAssertEqual(f.econ.wallet.coins, 1234, "\(v): монеты")
            XCTAssertEqual(f.econ.wallet.tickets, 3, v)
            XCTAssertEqual(f.econ.wallet.shards, 17, v)
            XCTAssertEqual(f.econ.paidSeq, 40, v)
            XCTAssertEqual(f.econ.items, ["scarf_knit": 1, "bandana_red": 2, "kennel_castle": 1, "ball_tennis": 1], "\(v): предметы")
            XCTAssertEqual(f.cards.album.map(\.id), ["20369-feed"], "\(v): открытки")
            XCTAssertEqual(f.journal.count, 2, v)
            if e.tricks {
                XCTAssertEqual(f.tricks.items["sit"]?.learned, 1_759_950_000, "\(v): выученный трюк")
                XCTAssertEqual(f.tricks.items["lie"]?.n, 2, v)
            }
            if e.catchGame {
                XCTAssertEqual(f.catchBest, 42, "\(v): рекорд мячика")
                XCTAssertEqual(f.catchGames, 2, v)
            }
            if e.life {
                XCTAssertEqual(f.memories.items.count, 2, "\(v): воспоминания")
                XCTAssertEqual(f.shelf, "kennel_castle", v)
                XCTAssertEqual(f.toy, "ball_tennis", v)
                XCTAssertEqual(f.worn["neck"], "scarf_knit", v)
            }
            if e.blockduo { XCTAssertEqual(f.blockduoBest, 1500, "\(v): рекорд Блок Дуо") }
            if e.zombie { XCTAssertEqual(f.zombieBest, 77, "\(v): рекорд зомби") }
            if e.charName { XCTAssertEqual(f.characterName, "Тестик", v) }

            // Ни одно поле старого файла не теряется при перезаписи текущей версией.
            let again = try JSONEncoder().encode(f)
            let old = try JSONSerialization.jsonObject(with: raw)
            let new = try JSONSerialization.jsonObject(with: again)
            XCTAssertEqual(missing(old, in: new), [], "\(v): поля пропали при перезаписи")
        }
    }

    func testEveryEpochSurvivesStoreRoundTrip() throws {
        for e in epochs {
            let dir = StoreHooks.makeTempStoreDir("pet-migrate")
            defer { StoreHooks.removeTempStore(dir) }
            let store = PetStore(dir: dir)
            try fixture(e.v).write(to: store.stateURL)
            // Сейв пролежал: первая правка новой сборки двигает время и пишет файл.
            try store.mutate { (f: inout SaveFile) -> Void in f.econ.wallet.coins += 1 }
            let f = try XCTUnwrap(store.read(), e.v)
            XCTAssertEqual(f.petId, "fixture-pet", "\(e.v): тот же щенок")
            XCTAssertEqual(f.rev, 322, e.v)
            XCTAssertTrue(f.pet.alive, "\(e.v): щенок жив")
            XCTAssertEqual(f.econ.wallet.coins, 1235, e.v)
            XCTAssertEqual(f.econ.items.count, 4, e.v)
            if e.tricks { XCTAssertNotNil(f.tricks.items["sit"]?.learned, e.v) }
            if e.catchGame { XCTAssertEqual(f.catchBest, 42, e.v) }
            XCTAssertFalse(f.journal.contains { $0.kind.hasPrefix("save_") }, "\(e.v): старый сейв — не авария")
            let bak = try JSONDecoder().decode(SaveFile.self, from: Data(contentsOf: store.bakURL))
            XCTAssertEqual(bak.rev, 321, "\(e.v): копия — исходный файл эпохи")
        }
    }
}

/// Волна 15: день рождения — дата в поясе рождения, перелёт её не сдвигает.
final class BirthTzTests: XCTestCase {
    private let belgrade = TimeZone(identifier: "Europe/Belgrade")!
    private let newYork = TimeZone(identifier: "America/New_York")!
    /// 10.10.2025 00:30 в Белграде (+2) — в Нью-Йорке это ещё 9.10.
    private let bornT: Double = 1_760_049_000

    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: Paths.mirror)
    }

    override func tearDown() {
        Clock.zoneOverride = nil
        super.tearDown()
    }

    func testFreshPuppyRemembersBirthZone() {
        Clock.zoneOverride = belgrade
        let f = SaveFile.fresh(now: bornT)
        XCTAssertEqual(f.birthTz, 120)
        Clock.zoneOverride = newYork
        XCTAssertEqual(f.bornDay, DayKey.of(bornT, tzOffsetMin: 120), "перелёт: дата рождения та же")
        XCTAssertNotEqual(f.bornDay, DayKey.of(bornT), "без пояса рождения дата уехала бы на день назад")
    }

    func testBirthTzRoundTripsAndIsOptional() throws {
        var f = SaveFile.fresh(now: bornT)
        f.birthTz = 330
        let back = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back.birthTz, 330)
        f.birthTz = nil
        let data = try JSONEncoder().encode(f)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("birthTz"), "nil в файл не пишется")
        XCTAssertNil(try JSONDecoder().decode(SaveFile.self, from: data).birthTz)
    }

    func testOldSaveGetsZoneOnFirstWriteAndKeepsIt() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-birth")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        let raw = try Data(contentsOf: fixturesDir.appendingPathComponent("save-v0.14.json"))
        try raw.write(to: store.stateURL)
        XCTAssertNil(try XCTUnwrap(store.read()).birthTz, "старый сейв — без пояса рождения")

        Clock.zoneOverride = belgrade
        try store.mutate { (_: inout SaveFile) -> Void in }
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.birthTz, 120, "пояс телефона на момент рождения (29.09.2025, летнее время)")
        let born = f.bornDay

        Clock.zoneOverride = newYork
        try store.mutate { (g: inout SaveFile) -> Void in g.owner.tzOffsetMin = -240 }
        let g = try XCTUnwrap(store.read())
        XCTAssertEqual(g.birthTz, 120, "записан один раз, перелёт не перезаписывает")
        XCTAssertEqual(g.bornDay, born)
    }

    func testBirthdayMemoryDoesNotMoveAfterFlight() {
        Clock.zoneOverride = belgrade
        var f = SaveFile.fresh(now: bornT)
        Clock.zoneOverride = newYork
        f.owner.tzOffsetMin = -240
        // 9.10.2026 20:00 в Нью-Йорке: год ещё не прошёл — дня рождения нет.
        f.pet.t = 1_791_590_400
        Memories.update(&f)
        XCTAssertNil(f.memories["days.365"], "день рождения не наступает на день раньше")
        // 10.10.2026 12:00 в Нью-Йорке — день рождения.
        f.pet.t = 1_791_590_400 + 16 * 3600
        Memories.update(&f)
        let m = f.memories["days.365"]
        XCTAssertEqual(m?.value, 365)
        XCTAssertEqual(m?.t, DayKey.start(f.bornDay + 365, tzOffsetMin: -240))
    }

    func testStartOverGivesNewPuppyItsOwnZone() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-birth")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        Clock.zoneOverride = belgrade
        try store.startOver(now: bornT)
        try store.mutate { (f: inout SaveFile) -> Void in f.birthTz = 540 }
        Clock.zoneOverride = newYork
        try store.startOver(now: bornT + 86400)
        XCTAssertEqual(try XCTUnwrap(store.read()).birthTz, -240)
    }
}
