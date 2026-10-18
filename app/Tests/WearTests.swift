// «Надето» (Wear): места, надеть/снять/заменить, чужое и мебель не надеваются, поле worn в сейве
// (старый файл без него, пустое не пишется, переживает щенка). Гоняется и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet

private let wT0: Double = 1_760_000_000

/// Щенок с предметами ids в коллекции.
private func wFile(_ ids: [String]) -> SaveFile {
    var f = SaveFile.fresh(now: wT0)
    for id in ids { f.econ.items[id] = 1 }
    return f
}

final class WearTests: XCTestCase {
    func testTableCoversWearablesAndSkipsFurniture() {
        for id in ["leaf_hat", "bow_blue", "bandana_red", "collar_star", "scarf_knit", "raincoat",
                   "hoodie_pumpkin", "cape_champion"] {
            XCTAssertTrue(Wear.canWear(id), id)
        }
        for id in ["bowl_plain", "mat_check", "lamp_mushroom", "sofa_mini", "kennel_castle", "nope"] {
            XCTAssertFalse(Wear.canWear(id), id)
        }
        // Всё надеваемое — из пулов капсулы: опечатка в id сделала бы строку мёртвой.
        let known = EconomyConfig.shared.capsule.itemsById
        for id in Wear.table.keys { XCTAssertNotNil(known[id], "\(id) нет в пулах капсулы") }
        XCTAssertEqual(Wear.info("leaf_hat")?.slot, .head)
        XCTAssertEqual(Wear.info("scarf_knit")?.slot, .neck)
        XCTAssertEqual(Wear.info("cape_champion")?.slot, .back)
        // Своих фигур не меньше пяти, остальное — общая на место.
        let own = Set(Wear.table.values.map(\.shape)).subtracting([.genericHat, .genericRing, .genericBlanket])
        XCTAssertGreaterThanOrEqual(own.count, 5)
    }

    func testPutAndTakeOff() {
        var f = wFile(["leaf_hat", "bandana_red"])
        XCTAssertTrue(Wear.worn(f).isEmpty)
        XCTAssertEqual(try Wear.put(&f, "leaf_hat").get(), .put(.head, replaced: nil))
        XCTAssertEqual(try Wear.put(&f, "bandana_red").get(), .put(.neck, replaced: nil))
        XCTAssertEqual(Wear.worn(f), [.head: "leaf_hat", .neck: "bandana_red"])
        XCTAssertTrue(Wear.isWorn(f, "leaf_hat"))

        XCTAssertEqual(Wear.takeOff(&f, "leaf_hat"), .head)
        XCTAssertFalse(Wear.isWorn(f, "leaf_hat"))
        XCTAssertNil(Wear.takeOff(&f, "leaf_hat"), "второй раз снимать нечего")
        XCTAssertEqual(Wear.worn(f), [.neck: "bandana_red"])
    }

    func testSameSlotReplaces() {
        var f = wFile(["bandana_red", "scarf_knit", "collar_star"])
        _ = Wear.put(&f, "bandana_red")
        XCTAssertEqual(try Wear.put(&f, "scarf_knit").get(), .put(.neck, replaced: "bandana_red"))
        XCTAssertEqual(Wear.worn(f), [.neck: "scarf_knit"])
        XCTAssertFalse(Wear.isWorn(f, "bandana_red"))
        // Повторно то же — без «заменил сам себя».
        XCTAssertEqual(try Wear.put(&f, "scarf_knit").get(), .put(.neck, replaced: nil))
    }

    func testToggle() {
        var f = wFile(["cape_champion"])
        XCTAssertEqual(try Wear.toggle(&f, "cape_champion").get(), .put(.back, replaced: nil))
        XCTAssertEqual(try Wear.toggle(&f, "cape_champion").get(), .tookOff(.back))
        XCTAssertTrue(f.worn.isEmpty)
    }

    func testRefusals() {
        var f = wFile(["bowl_plain"])
        XCTAssertEqual(Wear.put(&f, "bowl_plain"), .failure(.notWearable))
        XCTAssertEqual(Wear.put(&f, "leaf_hat"), .failure(.notOwned))
        XCTAssertEqual(Wear.toggle(&f, "leaf_hat"), .failure(.notOwned))
        XCTAssertTrue(f.worn.isEmpty)
    }

    func testWornIgnoresJunk() {
        var f = wFile(["leaf_hat", "scarf_knit"])
        f.worn = ["head": "leaf_hat", "neck": "leaf_hat", "back": "cape_champion", "tail": "scarf_knit",
                  "neck ": "bowl_plain"]
        // neck: шапка не на своём месте; back: плаща нет в коллекции; tail: нет такого места.
        XCTAssertEqual(Wear.worn(f), [.head: "leaf_hat"])
        // Сломанная запись не мешает надеть правильно.
        _ = Wear.put(&f, "scarf_knit")
        XCTAssertEqual(Wear.worn(f), [.head: "leaf_hat", .neck: "scarf_knit"])
    }

    func testSlotsOrdered() {
        XCTAssertEqual(WearSlot.allCases.sorted(), [.head, .neck, .back])
        XCTAssertEqual(WearSlot.back.title, "спина")
    }

    func testSaveFileRoundTripAndOldFile() throws {
        var f = wFile(["leaf_hat"])
        let empty = try JSONSerialization.jsonObject(with: JSONEncoder().encode(f)) as? [String: Any]
        XCTAssertNil(empty?["worn"], "ничего не надето — поля в файле нет")

        _ = Wear.put(&f, "leaf_hat")
        let data = try JSONEncoder().encode(f)
        let back = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(back.worn, ["head": "leaf_hat"])
        XCTAssertEqual(Wear.worn(back), [.head: "leaf_hat"])

        // Старый сейв без worn и с кривым worn читаются, остальное не сбрасывается.
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj["worn"] = nil
        let old = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertTrue(old.worn.isEmpty)
        XCTAssertEqual(old.econ.items["leaf_hat"], 1)
        obj["worn"] = ["head": 5]
        let bad = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertTrue(bad.worn.isEmpty)
        XCTAssertEqual(bad.petId, f.petId)
        XCTAssertEqual(bad.econ.items["leaf_hat"], 1)
    }

    func testStoreToggleAndStartOverKeepsWorn() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-wear")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: wT0)
        try store.mutate { (f: inout SaveFile) -> Void in f.econ.items["scarf_knit"] = 1 }
        XCTAssertEqual(try Wear.perform("scarf_knit", store: store).get(), .put(.neck, replaced: nil))
        XCTAssertEqual(Wear.worn(try XCTUnwrap(store.read())), [.neck: "scarf_knit"])

        try store.startOver(now: wT0 + 100)
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.econ.items["scarf_knit"], 1, "предметы переживают щенка")
        XCTAssertEqual(Wear.worn(f), [.neck: "scarf_knit"], "и надетое тоже")

        XCTAssertEqual(try Wear.perform("scarf_knit", store: store).get(), .tookOff(.neck))
        XCTAssertTrue(try XCTUnwrap(store.read()).worn.isEmpty)
    }
}
