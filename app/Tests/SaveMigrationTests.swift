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
