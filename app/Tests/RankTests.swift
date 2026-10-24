// Волна 32 «из грязи в князи»: звание от ступенек дома и шерсти (Rank).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let t0: Double = 1_760_054_400 + 9 * 3600

final class RankTests: XCTestCase {

    func testConfigFromEconomy() {
        let c = RankConfig.shared
        XCTAssertEqual(c.titles.first, "Бродяжка")
        XCTAssertEqual(c.titles.last, "Князь")
        XCTAssertEqual(c.at.first, 0)
        XCTAssertEqual(c.at.count, c.titles.count)
        XCTAssertEqual(c.at, c.at.sorted())
        XCTAssertEqual(c.coatPoints.count, CoatStage.allCases.count)
    }

    func testBadConfigFallsBack() throws {
        let bad = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"rank":{"titles":["A","B"],"at":[1,2],"coat_points":[1]}}"#.utf8))
        XCTAssertEqual(RankConfig(json: bad), RankConfig())
    }

    /// Новый щенок — бродяжка: колтуны, стартовый дом, до первого звания пара ступенек.
    func testFreshPuppyIsAStray() {
        let f = SaveFile.fresh(now: t0)
        XCTAssertEqual(Rank.homePoints(f), 0)
        XCTAssertEqual(Coat.look(f, now: t0).stage, .matted)
        let i = Rank.of(f, now: t0)
        XCTAssertEqual(i.index, 0)
        XCTAssertEqual(i.title, "Бродяжка")
        XCTAssertEqual(i.next, "Найдёныш")
        XCTAssertEqual(i.toNext, 2)
        XCTAssertEqual(i.progress, 0)
        XCTAssertFalse(i.isTop)
    }

    func testHomeLevelsCount() {
        var f = SaveFile.fresh(now: t0)
        f.pet.home[.bath] = 2
        f.pet.home[.bed] = 1
        XCTAssertEqual(Rank.homePoints(f), 3)
        XCTAssertEqual(Rank.of(f, now: t0).title, "Найдёныш")
    }

    /// Первое звание достижимо одним уходом за шерстью, без монет.
    func testCoatAloneLiftsFirstRank() {
        XCTAssertEqual(Rank.info(home: 0, coat: .shaggy).title, "Бродяжка")
        XCTAssertEqual(Rank.info(home: 0, coat: .shaggy).progress, 0.5, accuracy: 1e-9)
        XCTAssertEqual(Rank.info(home: 0, coat: .normal).title, "Найдёныш")
        XCTAssertEqual(Rank.info(home: 0, coat: .sleek).title, "Найдёныш")
    }

    func testLadder() {
        XCTAssertEqual(Rank.info(home: 3, coat: .normal).title, "Домашний")
        XCTAssertEqual(Rank.info(home: 7, coat: .normal).title, "Любимец")
        XCTAssertEqual(Rank.info(home: 12, coat: .normal).title, "Барин")
        XCTAssertEqual(Rank.info(home: 16, coat: .normal).title, "Барин")
        XCTAssertEqual(Rank.info(home: 16, coat: .sleek).title, "Барин")
        XCTAssertEqual(Rank.info(home: 17, coat: .sleek).title, "Князь")
        // Ступенька вверх по дому никогда не опускает звание.
        for coat in CoatStage.allCases {
            var prev = -1
            for h in 0...18 {
                let i = Rank.info(home: h, coat: coat).index
                XCTAssertGreaterThanOrEqual(i, prev)
                prev = i
            }
        }
    }

    /// Князь — почти полный дом и шерсть не хуже «Обычной»; лохматый в полном доме — ещё Барин.
    func testPrinceNeedsHouseAndCoat() {
        let maxHome = HomeShop.shared.reduce(0) { $0 + $1.levels.count - 1 }
        XCTAssertEqual(maxHome, 18)
        let top = Rank.info(home: maxHome, coat: .sleek)
        XCTAssertTrue(top.isTop)
        XCTAssertEqual(top.title, "Князь")
        XCTAssertEqual(top.toNext, 0)
        XCTAssertEqual(top.progress, 1)
        XCTAssertTrue(Rank.info(home: maxHome, coat: .normal).isTop)
        XCTAssertFalse(Rank.info(home: maxHome, coat: .shaggy).isTop)
        XCTAssertFalse(Rank.info(home: maxHome - 1, coat: .normal).isTop)
    }

    func testTexts() {
        XCTAssertEqual(Rank.title(Rank.info(home: 0, coat: .matted)), "Звание: Бродяжка")
        XCTAssertEqual(Rank.nextLine(Rank.info(home: 0, coat: .matted)), "До «Найдёныш» — ещё 2 ступеньки")
        XCTAssertEqual(Rank.nextLine(Rank.info(home: 0, coat: .shaggy)), "До «Найдёныш» — ещё 1 ступенька")
        XCTAssertEqual(Rank.nextLine(Rank.info(home: 9, coat: .matted)), "До «Барин» — ещё 5 ступенек")
        XCTAssertEqual(Rank.nextLine(Rank.info(home: 18, coat: .sleek)), "Выше некуда — настоящий князь!")
    }
}
