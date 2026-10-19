// Привычки из «Команд» (Habits.swift): раз в сутки и per_day, общий потолок с шагами, смена суток,
// часы назад, фразы пса, конфиг из economy.json, поле сейва верхним уровнем (старый сейв — пусто)
// и переход к новому щенку.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000.
private let hT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

private func hFile(at t: Double = hT0) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = "habits-pet-1"
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 70 }
    return f
}

/// Конфиг с явными цифрами — тесты не зависят от правок economy.json.
private func hCfg(cap: Int = 70) -> HabitConfig {
    var c = HabitConfig()
    c.dailyCap = cap
    c.rules[.home] = .init(coins: 8, perDay: 1)
    c.rules[.wake] = .init(coins: 8, perDay: 1)
    c.rules[.sleep] = .init(coins: 8, perDay: 1)
    c.rules[.water] = .init(coins: 2, perDay: 8)
    c.rules[.workout] = .init(coins: 10, perDay: 1)
    return c
}

final class HabitsTests: XCTestCase {

    func testOncePerDayBonus() {
        var f = hFile()
        let coins0 = f.econ.wallet.coins
        let a = Habits.checkIn(.home, in: &f, now: hT0, hCfg())
        XCTAssertTrue(a.ok)
        XCTAssertEqual(a.coins, 8)
        XCTAssertFalse(a.capped)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a.text, Habits.lines[.home]?[0])
        XCTAssertEqual(f.econ.wallet.coins, coins0 + 8)
        XCTAssertEqual(f.econ.daily.habits, 8, "в общий счётчик привычек")
        XCTAssertEqual(Habits.countToday(f, .home, now: hT0), 1)

        let b = Habits.checkIn(.home, in: &f, now: hT0 + 3600, hCfg())
        XCTAssertFalse(b.ok)
        XCTAssertEqual(b.reason, Habits.enoughReason)
        XCTAssertEqual(b.coins, 0)
        XCTAssertEqual(b.text, Habits.enoughText(.home))
        XCTAssertEqual(f.econ.wallet.coins, coins0 + 8, "второй раз за сутки — без монет")
        XCTAssertEqual(f.habits.total["home"], 1, "и не считается")
        XCTAssertEqual(f.habits.last["home"], hT0)
    }

    func testEachHabitHasOwnDailyLimit() {
        var f = hFile()
        for h in [Habit.home, .wake, .sleep, .workout] {
            XCTAssertTrue(Habits.checkIn(h, in: &f, now: hT0, hCfg()).ok, "\(h) — первый раз")
        }
        XCTAssertEqual(f.econ.daily.habits, 8 + 8 + 8 + 10)
        XCTAssertFalse(Habits.checkIn(.workout, in: &f, now: hT0 + 60, hCfg()).ok)
        XCTAssertFalse(Habits.checkIn(.wake, in: &f, now: hT0 + 60, hCfg()).ok)
    }

    func testWaterSmallCoinsUpToPerDay() {
        var f = hFile()
        var got = 0
        for i in 0..<10 {
            let o = Habits.checkIn(.water, in: &f, now: hT0 + Double(i) * 600, hCfg())
            got += o.coins
            XCTAssertEqual(o.ok, i < 8, "стакан \(i + 1)")
        }
        XCTAssertEqual(got, 16, "8 стаканов по 2 монеты")
        XCTAssertEqual(Habits.countToday(f, .water, now: hT0), 8)
        XCTAssertEqual(f.habits.total["water"], 8)
    }

    func testSeveralGlassesAtOnceClampedToRest() {
        var f = hFile()
        let a = Habits.checkIn(.water, times: 3, in: &f, now: hT0, hCfg())
        XCTAssertEqual(a.coins, 6)
        XCTAssertEqual(a.count, 3)
        let b = Habits.checkIn(.water, times: 10, in: &f, now: hT0 + 60, hCfg())
        XCTAssertEqual(b.count, 8, "не больше per_day")
        XCTAssertEqual(b.coins, 10)
        let z = Habits.checkIn(.water, times: 0, in: &f, now: hT0 + 120, hCfg())
        XCTAssertEqual(z.reason, Habits.enoughReason, "0 и меньше — как один стакан")
    }

    func testCommonCapSharedWithSteps() {
        var f = hFile()
        Economy.rollDay(&f.econ, day: Economy.day(hT0))
        f.econ.daily.habits = 65  // шаги уже почти выбрали потолок
        let coins0 = f.econ.wallet.coins
        let o = Habits.checkIn(.workout, in: &f, now: hT0, hCfg(cap: 70))
        XCTAssertTrue(o.ok, "отметка засчитана")
        XCTAssertEqual(o.coins, 5, "но монет — до потолка")
        XCTAssertTrue(o.capped)
        XCTAssertEqual(f.econ.daily.habits, 70)
        XCTAssertEqual(f.econ.wallet.coins, coins0 + 5)
        let h = Habits.checkIn(.home, in: &f, now: hT0 + 60, hCfg(cap: 70))
        XCTAssertTrue(h.ok)
        XCTAssertEqual(h.coins, 0)
        XCTAssertTrue(h.capped)
        XCTAssertTrue(Habits.reply(h).contains("хватит"))
        XCTAssertEqual(Habits.coinsLeft(f, now: hT0 + 60, hCfg(cap: 70)), 0)
        XCTAssertEqual(Habits.coinsLeft(f, now: hT0 + 86400, hCfg(cap: 70)), 70, "завтра снова")
    }

    func testNewDayResetsTodayButNotTotal() {
        var f = hFile()
        Habits.checkIn(.wake, in: &f, now: hT0, hCfg())
        Habits.checkIn(.water, times: 8, in: &f, now: hT0, hCfg())
        XCTAssertEqual(Habits.countToday(f, .wake, now: hT0 + 86400), 0, "чтение без записи видит новые сутки")
        let o = Habits.checkIn(.wake, in: &f, now: hT0 + 86400, hCfg())
        XCTAssertTrue(o.ok)
        XCTAssertEqual(o.coins, 8)
        XCTAssertEqual(o.text, Habits.lines[.wake]?[1], "второй раз всего — следующая фраза")
        XCTAssertEqual(f.habits.today["water"], nil, "вчерашняя вода не тянется")
        XCTAssertEqual(f.habits.total["wake"], 2)
        XCTAssertEqual(f.habits.day, Economy.day(hT0 + 86400))
        XCTAssertTrue(Habits.everDone(f, .water))
        XCTAssertFalse(Habits.everDone(f, .home))
    }

    func testClockBackDoesNotGiveSecondDay() {
        var f = hFile()
        Habits.checkIn(.home, in: &f, now: hT0 + 86400, hCfg())
        // Часы перевели на сутки назад: «вчера» не наступает заново, отметки сегодняшние.
        let o = Habits.checkIn(.home, in: &f, now: hT0, hCfg())
        XCTAssertFalse(o.ok)
        XCTAssertEqual(f.habits.day, Economy.day(hT0 + 86400))
    }

    func testDeadPetGivesNothing() {
        var f = hFile()
        f.pet.alive = false
        let coins0 = f.econ.wallet.coins
        let o = Habits.checkIn(.home, in: &f, now: hT0, hCfg())
        XCTAssertFalse(o.ok)
        XCTAssertEqual(o.reason, "dead")
        XCTAssertEqual(f.econ.wallet.coins, coins0)
        XCTAssertTrue(f.habits.isEmpty)
    }

    func testNoJournalNoCareCoins() {
        var f = hFile()
        let n0 = f.journal.count
        let care0 = f.econ.daily.care
        Habits.checkIn(.workout, in: &f, now: hT0, hCfg())
        XCTAssertEqual(f.journal.count, n0, "журнал (шерсть, открытки) не засоряем")
        XCTAssertEqual(f.econ.daily.care, care0, "потолок ухода не трогаем")
    }

    func testTexts() {
        for h in Habit.allCases {
            let lines = Habits.lines[h] ?? []
            XCTAssertGreaterThanOrEqual(lines.count, 2, "\(h): фраз хватает")
            XCTAssertEqual(Habits.greeting(h, n: 1), lines[0])
            XCTAssertEqual(Habits.greeting(h, n: lines.count + 1), lines[0], "по кругу")
            XCTAssertFalse(h.title.isEmpty)
            XCTAssertFalse(h.trigger.isEmpty)
            XCTAssertFalse(h.symbol.isEmpty)
            XCTAssertFalse(Habits.enoughText(h).isEmpty)
        }
        XCTAssertEqual(Set(Habit.allCases.map(\.title)).count, Habit.allCases.count)
        let o = HabitOutcome(habit: .water, ok: true, reason: nil, coins: 2, capped: false, count: 1, text: "Буль")
        XCTAssertEqual(Habits.reply(o), "Буль · +2 монеты")
    }

    func testScreenTexts() {
        XCTAssertEqual(Habits.rewardText(.home, hCfg()), "+8 монет · раз в день")
        XCTAssertEqual(Habits.rewardText(.water, hCfg()), "+2 монеты · до 8 раз в день")
        var f = hFile()
        XCTAssertEqual(Habits.statusText(f, .water, now: hT0, hCfg()), "Ещё не было")
        Habits.checkIn(.water, times: 3, in: &f, now: hT0, hCfg())
        Habits.checkIn(.wake, in: &f, now: hT0, hCfg())
        XCTAssertEqual(Habits.statusText(f, .water, now: hT0, hCfg()), "Сегодня 3 из 8")
        XCTAssertEqual(Habits.statusText(f, .wake, now: hT0, hCfg()), "Сегодня ✓")
        XCTAssertEqual(Habits.statusText(f, .water, now: hT0 + 86400, hCfg()), "Было 3 раза", "назавтра — всего")
        XCTAssertEqual(Habits.statusText(f, .wake, now: hT0 + 86400, hCfg()), "Было 1 раз")
        XCTAssertEqual([1, 2, 5, 11, 12, 22, 25, 101, 104, 112].map(Habits.times),
                       ["раз", "раза", "раз", "раз", "раз", "раза", "раз", "раз", "раза", "раз"])
        for h in Habit.allCases {
            XCTAssertTrue(h.siri.hasPrefix("я "), "\(h): «Питомец, я …» как в ShortcutsProvider")
        }
    }

    func testConfigFromEconomyJSON() {
        let d = HabitConfig(json: .null)
        for h in Habit.allCases {
            XCTAssertEqual(d.rule(h).coins, h.defaults.coins)
            XCTAssertEqual(d.rule(h).perDay, h.defaults.perDay)
        }
        let s = HabitConfig.shared
        XCTAssertEqual(s.dailyCap, EconomyConfig.shared.habitsCap, "один общий потолок с шагами")
        XCTAssertEqual(s.rule(.workout).coins, 10)
        XCTAssertEqual(s.rule(.water).perDay, 8)
        for h in Habit.allCases {
            XCTAssertGreaterThan(s.rule(h).coins, 0, "\(h) в economy.json")
            XCTAssertLessThanOrEqual(s.rule(h).coins * s.rule(h).perDay, s.dailyCap)
        }
        let sum = Habit.allCases.reduce(0) { $0 + s.rule($1).coins * s.rule($1).perDay }
        XCTAssertLessThanOrEqual(sum, s.dailyCap, "все привычки за день укладываются в потолок (шаги — сверху)")
    }

    func testSaveFieldTopLevelAndOldSave() throws {
        var f = hFile()
        let plain = try JSONEncoder().encode(f)
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("\"habits\":{"), "пустое в файл не пишется")
        Habits.checkIn(.home, in: &f, now: hT0, hCfg())
        Habits.checkIn(.water, times: 2, in: &f, now: hT0, hCfg())
        let data = try JSONEncoder().encode(f)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(obj["habits"] as? [String: Any], "верхним уровнем")
        let back = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(back.habits, f.habits)
        XCTAssertEqual(back.habits.today["water"], 2)

        // Старый сейв без поля — пусто, остальное на месте.
        let old = try JSONDecoder().decode(SaveFile.self, from: plain)
        XCTAssertTrue(old.habits.isEmpty)
        XCTAssertEqual(old.petId, f.petId)
        // Битое поле — пусто, а не весь сейв.
        let text = String(decoding: plain, as: UTF8.self)
        let broken = "{\"habits\":\"много\"," + text.dropFirst()
        let b = try JSONDecoder().decode(SaveFile.self, from: Data(broken.utf8))
        XCTAssertTrue(b.habits.isEmpty)
        XCTAssertEqual(b.petId, f.petId)
        // Незнакомая привычка из будущей версии не мешает.
        let future = "{\"habits\":{\"day\":3,\"today\":{\"yoga\":1,\"home\":1}}," + text.dropFirst()
        let fu = try JSONDecoder().decode(SaveFile.self, from: Data(future.utf8))
        XCTAssertEqual(fu.habits.today["home"], 1)
    }

    func testStartOverKeepsHabits() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-habits")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: hT0)
        try store.mutate { (f: inout SaveFile) -> Void in
            Habits.checkIn(.workout, in: &f, now: hT0, hCfg())
        }
        try store.startOver(now: hT0 + 100)
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.habits.total["workout"], 1, "отметки хозяина остаются")
        XCTAssertEqual(Habits.countToday(f, .workout, now: hT0 + 200), 1, "новым щенком второй бонус не взять")
    }
}
