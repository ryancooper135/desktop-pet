// Каталог из economy.json и стабильный хеш для выбора реплик.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

final class CatalogHashTests: XCTestCase {

    func testMainFoodAndHealItemExist() {
        let r = Catalog.rules
        XCTAssertNotNil(r.food[Catalog.mainFood], "главная еда есть в правилах")
        XCTAssertNotNil(r.items[Catalog.healItem], "лечебный предмет есть в правилах")
    }

    func testNames() {
        for id in Catalog.rules.food.keys {
            XCTAssertNotNil(Catalog.names[id], "у еды \(id) нет имени для кнопки")
            XCTAssertNotEqual(Catalog.name(id), id)
        }
        XCTAssertFalse(Catalog.name(Catalog.mainFood).isEmpty)
        XCTAssertEqual(Catalog.name("нет-такого"), "нет-такого", "неизвестный id показываем как есть")
    }

    func testNeedNames() {
        XCTAssertEqual(Catalog.needNames.count, Need.allCases.count)
        for n in Need.allCases {
            XCTAssertNotEqual(Catalog.needName(n), n.rawValue, "у шкалы \(n) нет имени")
            XCTAssertFalse(Catalog.needName(n).isEmpty)
        }
    }

    func testResources() {
        XCTAssertNotNil(Catalog.resource("economy", "json"))
        XCTAssertNotNil(Catalog.resource("lines", "json"))
        XCTAssertNil(Catalog.resource("nope-\(UUID().uuidString)", "json"))
    }

    func testFnvVectors() {
        XCTAssertEqual(StableHash.fnv1a(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(StableHash.fnv1a("a"), 0xaf63_dc4c_8601_ec8c)
        XCTAssertEqual(StableHash.fnv1a("foobar"), 0x8594_4171_f739_67e8)
        XCTAssertEqual(StableHash.fnv1a("Шиба"), 0xc98b_0fee_b05a_6eba, "по байтам UTF-8")
        XCTAssertEqual(StableHash.fnv1a("pet.hungry"), 0x8b31_4c5d_992b_9781)
    }

    func testFnvIsOrderSensitive() {
        XCTAssertNotEqual(StableHash.fnv1a("ab"), StableHash.fnv1a("ba"))
        XCTAssertNotEqual(StableHash.fnv1a("seed:widget:ok"), StableHash.fnv1a("seed:island:ok"))
        XCTAssertEqual(StableHash.fnv1a("seed:widget:ok"), StableHash.fnv1a("seed:widget:ok"))
    }
}
