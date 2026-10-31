// Привычки хозяина убраны в волне 57 (вместо них «Команды», Tricks.swift). Что осталось и проверяется:
// поле сейва habits читается из старого сейва и пишется верхним уровнем (пустое — не пишется), битое или
// из будущей версии не ломает сейв, переходит к новому щенку, а монет за отметки больше нет.
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

/// Отметки, какие оставляла волна 11: «Я дома» и два стакана воды сегодня.
private func oldLog(day: Int) -> HabitLog {
    var h = HabitLog()
    h.day = day
    h.today = ["home": 1, "water": 2]
    h.last = ["home": hT0, "water": hT0]
    h.total = ["home": 5, "water": 12, "workout": 3]
    return h
}

final class HabitsTests: XCTestCase {

    func testSaveFieldTopLevelAndOldSave() throws {
        var f = hFile()
        let plain = try JSONEncoder().encode(f)
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("\"habits\":{"), "пустое в файл не пишется")
        f.habits = oldLog(day: DayKey.of(hT0))
        let data = try JSONEncoder().encode(f)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(obj["habits"] as? [String: Any], "верхним уровнем, как до волны 57")
        let back = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(back.habits, f.habits, "старые отметки не теряются при пересохранении")
        XCTAssertEqual(back.habits.today["water"], 2)
        XCTAssertEqual(back.habits.total["workout"], 3)

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
        // Незнакомый ключ (из будущей версии или чужой) не мешает.
        let future = "{\"habits\":{\"day\":3,\"today\":{\"yoga\":1,\"home\":1}}," + text.dropFirst()
        let fu = try JSONDecoder().decode(SaveFile.self, from: Data(future.utf8))
        XCTAssertEqual(fu.habits.today["home"], 1)
        XCTAssertEqual(fu.habits.today["yoga"], 1)
        XCTAssertEqual(fu.habits.day, 3)
    }

    /// Монеты за привычки не идут: ни старые отметки, ни запись «habit» в журнале не дают ничего
    /// при догонялке — кошелёк и общий дневной счётчик как у такого же сейва без привычек.
    func testOldHabitsGiveNoCoins() throws {
        var with = hFile()
        with.habits = oldLog(day: DayKey.of(hT0))
        with.log("habit", t: hT0, key: "home")
        with.log("habit", t: hT0 + 60, key: "water")
        var without = hFile()
        without.log("habit-free", t: hT0, key: nil)
        without.log("habit-free", t: hT0 + 60, key: nil)
        XCTAssertEqual(with.econ.wallet.coins, without.econ.wallet.coins)

        for t in [hT0 + 600, hT0 + 3600, hT0 + 86400 + 600] {
            PetRunner.catchUp(&with, now: t)
            PetRunner.catchUp(&without, now: t)
            XCTAssertEqual(with.econ.wallet.coins, without.econ.wallet.coins, "за привычки монет нет (t+\(t - hT0))")
            XCTAssertEqual(with.econ.daily.habits, without.econ.daily.habits, "и общий дневной потолок они не трогают")
            XCTAssertNotEqual(with.econ.lastEarn?.kind, "habit")
        }
        XCTAssertEqual(with.habits.total["water"], 12, "отметки лежат как были")
        XCTAssertEqual(with.habits.today["home"], 1)
    }

    /// Общий дневной потолок econ.daily.habits остался — его теперь делят шаги и показ выученных команд.
    func testSharedCapNowStepsAndTricks() {
        var f = hFile()
        let cfg = EconomyConfig()
        XCTAssertGreaterThan(cfg.habitsCap, Tricks.showDaily)
        Economy.rollDay(&f.econ, day: DayKey.of(hT0))
        f.econ.daily.habits = cfg.habitsCap
        XCTAssertEqual(Tricks.showCoinsLeft(f, at: hT0, cfg), 0, "упёрлись шагами — за показ команд уже ничего")
        f.econ.daily.habits = cfg.habitsCap - 2
        XCTAssertEqual(Tricks.showCoinsLeft(f, at: hT0, cfg), 2)
        f.econ.daily.habits = 0
        XCTAssertEqual(Tricks.showCoinsLeft(f, at: hT0, cfg), Tricks.showDaily, "своя норма показа меньше общего потолка")
    }

    func testStartOverKeepsHabits() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-habits")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: hT0)
        try store.mutate { (f: inout SaveFile) -> Void in
            f.habits = oldLog(day: DayKey.of(hT0))
        }
        try store.startOver(now: hT0 + 100)
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.habits.total["workout"], 3, "старые отметки хозяина остаются и у нового щенка")
        XCTAssertEqual(f.habits.today["water"], 2)
    }
}
