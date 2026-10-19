// Волна 17: грамматика текстов. Числа со словом в нужной форме ({times}, {days}, очки), названия после
// двоеточия со строчной (именительный падеж не ломается), тост кухни без повтора фразы пса.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

final class TextGrammarTests: XCTestCase {

    // MARK: формы чисел

    func testTimesDaysPoints() {
        let times = [1: "1 раз", 2: "2 раза", 4: "4 раза", 5: "5 раз", 11: "11 раз", 12: "12 раз",
                     21: "21 раз", 22: "22 раза", 25: "25 раз", 111: "111 раз", 122: "122 раза"]
        for (n, s) in times { XCTAssertEqual(EconText.times(n), s) }
        let days = [1: "1 день", 2: "2 дня", 5: "5 дней", 7: "7 дней", 11: "11 дней", 21: "21 день",
                    22: "22 дня", 30: "30 дней", 101: "101 день", 1000: "1000 дней"]
        for (n, s) in days { XCTAssertEqual(EconText.days(n), s) }
        let points = [0: "0 очков", 1: "1 очко", 3: "3 очка", 5: "5 очков", 13: "13 очков", 21: "21 очко",
                      104: "104 очка"]
        for (n, s) in points { XCTAssertEqual(EconText.points(n), s) }
    }

    func testLowerFirst() {
        XCTAssertEqual(EconText.lowerFirst("Морковка"), "морковка")
        XCTAssertEqual(EconText.lowerFirst("Банка желудей"), "банка желудей")
        XCTAssertEqual(EconText.lowerFirst("ёлка"), "ёлка")
        XCTAssertEqual(EconText.lowerFirst("Ёжик"), "ёжик")
        XCTAssertEqual(EconText.lowerFirst(""), "")
    }

    // MARK: кухня

    func testKitchenTextsUseColonAndLowercase() {
        let r = Cooking.BuyResult.ok(price: 4, out: ActOutcome(ok: true, reason: nil))
        XCTAssertEqual(Cooking.buyText(r, name: "Сосиска"), "Угощение: сосиска за \(EconText.coins(4))")
        XCTAssertFalse(Cooking.buyText(r, name: "Сосиска").contains("Угостили"), "не «Угостили: Сосиска»")
        let soup = CookConfig.defaultRecipes[2]
        XCTAssertEqual(Cooking.stateText(.needsItem("pumpkin_small"), soup, now: 0), "Нужна вещь из капсул: тыковка")
    }

    /// Бонус первого блюда: тост только про монеты, фразу пса не повторяет. Без монет тоста нет.
    func testCookBonusToastHasNoDishLine() {
        let base = CookOutcome(recipe: "stew_home", ok: true, reason: nil, gains: [:], coins: 15, openedTaste: nil,
                               text: Cooking.dishLine("stew_home", n: 1))
        let toast = try? XCTUnwrap(Cooking.bonusText(base))
        XCTAssertEqual(toast, "Подарок за первое блюдо дня: +\(EconText.coins(15))")
        XCTAssertFalse(toast?.contains("уплетает") ?? true)
        let none = CookOutcome(recipe: "stew_home", ok: true, reason: nil, gains: [:], coins: 0, openedTaste: nil,
                               text: base.text)
        XCTAssertNil(Cooking.bonusText(none), "без бонуса тоста нет — фраза уже в пузыре")
        let refused = CookOutcome(recipe: "stew_home", ok: false, reason: "night", gains: [:], coins: 0,
                                  openedTaste: nil, text: "Ночью кухня закрыта: Шиба спит")
        XCTAssertNil(Cooking.bonusText(refused))
    }

    func testDishFallbackHasYo() {
        XCTAssertTrue(Cooking.dishLine("nope", n: 1).contains("щёки"))
    }

    // MARK: воспоминания и открытки

    func testMemoryVarsHaveWordForms() {
        let rec = Memories.line(Memory(id: "catch.record", t: 0, value: 3))
        XCTAssertEqual(rec?.vars["count"], "3")
        XCTAssertEqual(rec?.vars["times"], "3 раза")
        XCTAssertEqual(Memories.line(Memory(id: "catch.record", t: 0, value: 21))?.vars["times"], "21 раз")
        let days = Memories.line(Memory(id: "days.101", t: 0, value: 101))
        XCTAssertEqual(days?.key, "memory_days")
        XCTAssertEqual(days?.vars["count"], "101")
        XCTAssertEqual(days?.vars["days"], "101 день")
    }

    func testPostcardVarsHaveWordForms() {
        let pets = Postcards.vars(Moment(kind: .pets, t: 0, score: 10, count: 22))
        XCTAssertEqual(pets["count"], "22")
        XCTAssertEqual(pets["times"], "22 раза")
        let days = Postcards.vars(Moment(kind: .days, t: 0, score: 10, count: 1000))
        XCTAssertEqual(days["days"], "1000 дней")
        XCTAssertNil(Postcards.vars(Moment(kind: .pets, t: 0, score: 10))["times"], "без серии — строка без {times}")
        XCTAssertNil(Postcards.vars(Moment(kind: .birthday, t: 0, score: 10, count: 2))["days"])
    }

    /// После голого {count} в строке не пишут слово, которое зависит от числа: «{count} дней» даёт «21 дней».
    func testNoCountFollowedByCountedWord() throws {
        let lines = Lines.shared
        guard !(lines.sections["widget"] ?? [:]).isEmpty else { throw XCTSkip("lines.json нет в бандле") }
        let words = ["раз", "раза", "дней", "дня", "день", "лет", "года", "год", "очков", "очка", "монет", "монеты",
                     "шагов", "блюд", "ночей"]
        for (section, keys) in lines.sections {
            for (key, pool) in keys {
                for l in pool {
                    for w in words {
                        XCTAssertFalse(l.text.contains("{count} \(w)"), "\(section).\(key): \(l.text)")
                    }
                }
            }
        }
    }

    /// Новые подстановки заполняются и не вылезают за лимит строки.
    func testTimesDaysLinesFitLimits() throws {
        let lines = Lines.shared
        guard !(lines.sections["widget"] ?? [:]).isEmpty else { throw XCTSkip("lines.json нет в бандле") }
        let vars = ["count": "1000", "times": EconText.times(1000), "days": EconText.days(1000)]
        for key in ["memory_record", "memory_days"] {
            for l in lines.sections["widget"]?[key] ?? [] {
                let s = Lines.fill(l.text, vars)
                XCTAssertFalse(s.contains("{"), s)
                XCTAssertLessThanOrEqual(s.count, LineLimit.widget, s)
            }
        }
        for key in ["card_pets", "card_days"] {
            for l in lines.sections["away"]?[key] ?? [] {
                let s = Lines.fill(l.text, vars)
                XCTAssertFalse(s.contains("{"), s)
                XCTAssertLessThanOrEqual(s.count, Postcards.captionMax, s)
            }
        }
    }

    // MARK: имя питомца

    func testDeadStatusText() {
        XCTAssertEqual("\(PetNames.gone("Шиба")). Открой приложение.", "Шибы больше нет. Открой приложение.")
        XCTAssertEqual("\(PetNames.gone("Мурка")). Открой приложение.", "Мурка больше не с нами. Открой приложение.")
    }

    func testBuildNoteNamesPetInAccusative() {
        var f = SaveFile.fresh(now: 0)
        f.build = SaveFile.BuildInfo(expiresT: 10 * 86400, seenT: 0)
        let notes = NotificationPlanner.buildNotes(f, now: 0)
        let last = notes.first { $0.id == "pet.build.24" }
        XCTAssertNotNil(last)
        XCTAssertTrue(last?.body.hasSuffix("чтобы не потерять Шибу.") ?? false, last?.body ?? "")
    }
}
