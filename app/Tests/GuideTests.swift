// Подсказки «Правила» и «Виджет и остров»: когда показывать и что написать (Guides).
// Без экрана и без стора: только чистые функции и правила из economy.json.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// 10.10.2025 00:00 UTC: от полуночи удобно считать местные дни.
private let midnight: Double = 1_760_054_400

private func flags(rules: Bool = false, count: Int = 0, lastT: Double? = nil) -> SaveFile.Flags {
    var f = SaveFile.Flags()
    f.rulesShown = rules
    f.widgetHintCount = count
    f.widgetHintT = lastT
    return f
}

final class GuideTests: XCTestCase {

    // MARK: правила — когда

    func testRulesWaitForThirdDay() {
        let born = midnight + 23 * 3600            // появился в 23:00, это день 1
        let day2 = midnight + 86_400 + 20 * 3600   // день 2, вечер
        let day3 = midnight + 2 * 86_400 + 600     // день 3, 00:10
        XCTAssertEqual(Guides.dayOfLife(createdT: born, now: born, tzOffsetMin: 0), 1)
        XCTAssertFalse(Guides.shouldShowRules(flags: flags(), createdT: born, now: day2, tzOffsetMin: 0, level: 1, alive: true))
        XCTAssertTrue(Guides.shouldShowRules(flags: flags(), createdT: born, now: day3, tzOffsetMin: 0, level: 0, alive: true))
    }

    func testRulesDayFollowsOwnerTimezone() {
        // 22:00 UTC = 01:00 по Москве (+180): по местному времени это уже следующий день.
        let born = midnight + 10 * 3600
        let t = midnight + 86_400 + 22 * 3600
        XCTAssertEqual(Guides.dayOfLife(createdT: born, now: t, tzOffsetMin: 0), 2)
        XCTAssertEqual(Guides.dayOfLife(createdT: born, now: t, tzOffsetMin: 180), 3)
    }

    func testRulesOnFirstBadLevel() {
        let born = midnight + 9 * 3600
        let now = born + 5 * 3600
        XCTAssertFalse(Guides.shouldShowRules(flags: flags(), createdT: born, now: now, tzOffsetMin: 0, level: Guides.rulesLevel - 1, alive: true))
        XCTAssertTrue(Guides.shouldShowRules(flags: flags(), createdT: born, now: now, tzOffsetMin: 0, level: Guides.rulesLevel, alive: true))
        XCTAssertTrue(Guides.shouldShowRules(flags: flags(), createdT: born, now: now, tzOffsetMin: 0, level: 3, alive: true))
    }

    func testRulesOnlyOnceAndOnlyAlive() {
        let born = midnight
        let late = midnight + 5 * 86_400
        XCTAssertFalse(Guides.shouldShowRules(flags: flags(rules: true), createdT: born, now: late, tzOffsetMin: 0, level: 3, alive: true))
        XCTAssertFalse(Guides.shouldShowRules(flags: flags(), createdT: born, now: late, tzOffsetMin: 0, level: 3, alive: false))
    }

    // MARK: виджет и остров — когда

    func testWidgetGuideFirstTime() {
        XCTAssertTrue(Guides.shouldShowWidgetGuide(flags: flags(), now: midnight, alive: true, hasWidget: false, islandOn: false))
        XCTAssertTrue(Guides.shouldShowWidgetGuide(flags: flags(), now: midnight, alive: true, hasWidget: true, islandOn: false))
        XCTAssertTrue(Guides.shouldShowWidgetGuide(flags: flags(), now: midnight, alive: true, hasWidget: false, islandOn: true))
        XCTAssertFalse(Guides.shouldShowWidgetGuide(flags: flags(), now: midnight, alive: true, hasWidget: true, islandOn: true))
        XCTAssertFalse(Guides.shouldShowWidgetGuide(flags: flags(), now: midnight, alive: false, hasWidget: false, islandOn: false))
    }

    func testWidgetGuideRepeatsAfterWeekAtMostTwice() {
        let shown = flags(count: 1, lastT: midnight)
        let almost = midnight + Guides.widgetRepeatS - 60
        let week = midnight + Guides.widgetRepeatS
        XCTAssertFalse(Guides.shouldShowWidgetGuide(flags: shown, now: almost, alive: true, hasWidget: false, islandOn: false))
        XCTAssertTrue(Guides.shouldShowWidgetGuide(flags: shown, now: week, alive: true, hasWidget: false, islandOn: false))
        let twice = flags(count: Guides.widgetMaxShows, lastT: midnight)
        XCTAssertFalse(Guides.shouldShowWidgetGuide(flags: twice, now: midnight + 60 * 86_400, alive: true, hasWidget: false, islandOn: false))
    }

    // MARK: правила — текст

    func testConditionText() {
        XCTAssertEqual(Guides.condText("food == 0"), "сытость на нуле")
        XCTAssertEqual(Guides.condText("clean < 10"), "чистота ниже 10")
        XCTAssertEqual(Guides.condText("fun < 10 && love < 10"), "настроение ниже 10 и ласка ниже 10")
    }

    func testRulesTextUsesCoreNumbers() throws {
        let r = Catalog.rules
        let owner = PetEngine.defaultOwner(r)
        let items = Guides.rulesItems(name: "Шиба", owner: owner)
        func text(_ id: String) -> String { items.first(where: { $0.id == id }).map { $0.title + " " + $0.text } ?? "" }

        XCTAssertTrue(text("hearts").contains("\(Int(r.heartsMax.rounded()))"))
        for d in Distress.allCases {
            let rule = try XCTUnwrap(r.distress[d])
            let line = text("distress.\(d.rawValue)")
            XCTAssertTrue(line.contains(Guides.hours(rule.graceH)), line)
            XCTAssertTrue(line.contains(Guides.hours(rule.hoursPerHeart)), line)
            XCTAssertFalse(line.contains("=="), "условие должно быть словами: \(line)")
        }
        XCTAssertTrue(text("last").contains(Guides.hours(r.lastChanceH)))
        XCTAssertTrue(text("last").contains(Guides.hours(r.noDeathAfterWakeH)))
        XCTAssertTrue(text("night").contains(Guides.hm(owner.bedMin)))
        XCTAssertTrue(text("regen").contains(Guides.num(r.regenAllGe)))
        XCTAssertTrue(text("help").contains("«Спасти»"))
        XCTAssertFalse(text("ignore").isEmpty)
    }

    func testIgnoreForecastIsSane() throws {
        let r = Catalog.rules
        let h = try XCTUnwrap(Guides.ignoreDeathH(r, owner: PetEngine.defaultOwner(r)))
        // Смерть не раньше последнего шанса и в пределах недели.
        XCTAssertGreaterThan(h, r.lastChanceH)
        XCTAssertLessThan(h, 168)
    }

    func testFormatting() {
        XCTAssertEqual(Guides.num(2), "2")
        XCTAssertEqual(Guides.num(0.5), "0,5")
        XCTAssertEqual(Guides.num(1 / 0.0833), "12")
        XCTAssertEqual(Guides.roughly(59.3), "около 2,5 суток")
        XCTAssertEqual(Guides.roughly(20), "около 20 ч")
        XCTAssertEqual(Guides.hm(23 * 60 + 30), "23:30")
        XCTAssertEqual(Guides.plural(1, "сердечко", "сердечка", "сердечек"), "сердечко")
        XCTAssertEqual(Guides.plural(3, "сердечко", "сердечка", "сердечек"), "сердечка")
        XCTAssertEqual(Guides.plural(5, "сердечко", "сердечка", "сердечек"), "сердечек")
        XCTAssertEqual(Guides.plural(11, "сердечко", "сердечка", "сердечек"), "сердечек")
        XCTAssertEqual(Guides.joinRu(["а", "б", "в"]), "а, б и в")
    }

    /// Склонение по числу одно на всё приложение (EconText.plural): копии в Guides, Memories, Cooking,
    /// Habits и Postcards отвечают так же на любых числах, и на отрицательных тоже.
    func testPluralHelpersAgreeWithEconText() {
        for n in -130...230 {
            let want = EconText.plural(n, "a", "b", "c")
            XCTAssertEqual(Guides.plural(n, "a", "b", "c"), want, "Guides \(n)")
            XCTAssertEqual(Memories.plural(n, "a", "b", "c"), want, "Memories \(n)")
            XCTAssertEqual(Cooking.dishes(n), EconText.plural(n, "блюдо", "блюда", "блюд"), "Cooking \(n)")
            XCTAssertEqual(Habits.times(n), EconText.plural(n, "раз", "раза", "раз"), "Habits \(n)")
            XCTAssertEqual(Postcards.daysWord(n), EconText.plural(n, "день", "дня", "дней"), "Postcards \(n)")
        }
        XCTAssertEqual([1, 2, 5, 11, 12, 21, 22, 25, 101, 111, 112, -1, -2, -11].map { EconText.plural($0, "a", "b", "c") },
                       ["a", "b", "c", "c", "c", "a", "b", "c", "a", "c", "c", "a", "b", "c"])
    }

    // MARK: флаги в файле

    func testFlagsSurviveRoundTrip() throws {
        var f = SaveFile.fresh(now: midnight)
        f.flags.rulesShown = true
        f.flags.widgetHintCount = 1
        f.flags.widgetHintT = midnight + 100
        let back = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back.flags, f.flags)
    }
}
