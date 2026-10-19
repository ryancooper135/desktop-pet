// Волна 14: время и сутки. Полночь ±1 с, часы назад и вперёд, перелёт ±12 ч, летнее время.
// Пояс задаётся через Clock.zoneOverride и сбрасывается в tearDown — тесты не зависят от пояса машины.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let tdT0: Double = 1_760_000_000   // 9 октября 2025, 08:53 UTC
private let belgrade = TimeZone(identifier: "Europe/Belgrade")!
private func fixed(_ h: Int) -> TimeZone { TimeZone(secondsFromGMT: h * 3600)! }

/// Местное время в поясе z: unix-секунды.
private func local(_ z: TimeZone, _ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Double {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = z
    return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!.timeIntervalSince1970
}

/// Свежий щенок, который в момент t бодрствует и хочет ласки: «Погладить» пройдёт и в полночь.
private func tdFile(at t: Double) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.owner.bedMin = 3 * 60
    f.owner.wakeMin = 7 * 60
    f.pet.needs[.love] = 40
    return f
}

/// Записать удачную заботу прямо в журнал — так пишет PetRunner.apply.
private func tdAct(_ f: inout SaveFile, _ kind: String, t: Double) {
    f.log("act.\(kind)", t: t, source: .app, ok: true)
}

/// Выбрать дневной потолок ухода до конца в момент t (купание — 5 монет).
private func tdSpendCare(_ f: inout SaveFile, at t: Double) {
    for i in 0..<10 { tdAct(&f, "bath", t: t + Double(i)) }
    Economy.settle(&f)
}

final class TimeDayTests: XCTestCase {
    override func tearDown() {
        Clock.zoneOverride = nil
        super.tearDown()
    }

    private var cap: Int { EconomyConfig.shared.careDailyCap }

    // MARK: ключ дня

    func testDayKeyAtMidnightPlusMinusOneSecond() {
        for z in [belgrade, fixed(0), fixed(12), fixed(-12), TimeZone(identifier: "Asia/Kolkata")!] {
            Clock.zoneOverride = z
            let mid = DayKey.nextMidnight(after: tdT0)
            XCTAssertEqual(DayKey.of(mid - 1) + 1, DayKey.of(mid), z.identifier)
            XCTAssertEqual(DayKey.of(mid + 1), DayKey.of(mid), z.identifier)
            XCTAssertEqual(DayKey.start(DayKey.of(mid)), mid, z.identifier)
            // Ровно в полночь следующая полночь — через сутки, а не «сейчас».
            XCTAssertEqual(DayKey.nextMidnight(after: mid), mid + 86400, z.identifier)
            XCTAssertEqual(DayKey.nextMidnight(after: mid - 1), mid, z.identifier)
            // Счётчик «сегодня»: за секунду до полуночи — вчерашний, через секунду — с нуля.
            let yesterday = DayKey.of(mid - 1)
            XCTAssertEqual(DayKey.today(7, day: yesterday, at: mid - 1), 7)
            XCTAssertEqual(DayKey.today(7, day: yesterday, at: mid + 1), 0)
            XCTAssertNil(DayKey.newer(than: yesterday, at: mid - 1))
            XCTAssertEqual(DayKey.newer(than: yesterday, at: mid + 1), yesterday + 1)
        }
        // До 1970 — вниз, а не к нулю.
        XCTAssertEqual(DayKey.of(-1, tzOffsetMin: 0), -1)
        XCTAssertEqual(DayKey.of(-86400, tzOffsetMin: 0), -1)
        XCTAssertEqual(DayKey.of(-86401, tzOffsetMin: 0), -2)
    }

    // MARK: полночь

    /// Ядро шагает целыми минутами: через 20 с после полуночи pet.t ещё вчерашний. Действие всё равно
    /// записывается моментом нажатия и платится из нового потолка.
    func testActionInFirstMinuteOfDayCountsForNewDay() {
        Clock.zoneOverride = belgrade
        let mid = DayKey.nextMidnight(after: tdT0)
        var f = tdFile(at: mid - 30)
        tdSpendCare(&f, at: mid - 30)
        XCTAssertEqual(f.econ.daily.care, cap)
        XCTAssertEqual(f.econ.daily.day, DayKey.of(mid - 1))

        let out = PetRunner.apply(.pet, source: .app, to: &f, now: mid + 20)
        XCTAssertTrue(out.ok, out.reason ?? "")
        XCTAssertEqual(f.pet.t, mid - 30, "меньше минуты — ядро не шагает")
        let e = f.journal.last { $0.kind == "act.pet" }
        XCTAssertEqual(e?.t, mid + 20)
        XCTAssertEqual(f.econ.daily.day, DayKey.of(mid))
        XCTAssertEqual(out.coins, EconomyConfig.shared.careCoins["pet"])
        XCTAssertEqual(Economy.careLeftToday(f, at: mid + 21), cap - out.coins)
    }

    func testActionOneSecondBeforeMidnightStaysInOldDay() {
        Clock.zoneOverride = belgrade
        let mid = DayKey.nextMidnight(after: tdT0)
        var f = tdFile(at: mid - 50)
        let out = PetRunner.apply(.pet, source: .app, to: &f, now: mid - 1)
        XCTAssertTrue(out.ok, out.reason ?? "")
        XCTAssertEqual(f.journal.last { $0.kind == "act.pet" }?.t, mid - 1)
        XCTAssertEqual(f.econ.daily.day, DayKey.of(mid - 1))
        XCTAssertEqual(f.econ.daily.care, out.coins)
        // Через секунду — новые сутки, потолок целый (без записи).
        XCTAssertEqual(Economy.careLeftToday(f, at: mid), cap)
        XCTAssertEqual(Economy.careLeftToday(f, at: mid - 1), cap - out.coins)
    }

    func testHabitsAndMiniGamesRollOverAtMidnight() {
        Clock.zoneOverride = belgrade
        let mid = DayKey.nextMidnight(after: tdT0)
        var f = tdFile(at: mid - 120)
        Habits.checkIn(.water, in: &f, now: mid - 1)
        XCTAssertEqual(Habits.countToday(f, .water, now: mid - 1), 1)
        XCTAssertEqual(Habits.countToday(f, .water, now: mid + 1), 0)
        Habits.checkIn(.water, in: &f, now: mid + 1)
        XCTAssertEqual(f.habits.day, DayKey.of(mid))
        XCTAssertEqual(Habits.countToday(f, .water, now: mid + 1), 1)

        // Мини-игры: потолок, выбранный за секунду до полуночи, через секунду после — снова целый.
        f.catchDay = DayKey.of(mid - 1)
        f.catchCoins = 10_000
        XCTAssertEqual(CatchGame.coinsLeft(f, now: mid - 1), 0)
        XCTAssertGreaterThan(CatchGame.coinsLeft(f, now: mid + 1), 0)
        XCTAssertEqual(MiniGames.coinsToday(f, now: mid - 1), 10_000)
        XCTAssertEqual(MiniGames.coinsToday(f, now: mid + 1), 0)
    }

    // MARK: часы назад и вперёд

    func testClockBackGivesNoSecondCapAndKeepsCounters() {
        Clock.zoneOverride = belgrade
        let noon = local(belgrade, 2026, 10, 14, 12)
        var f = tdFile(at: noon)
        tdSpendCare(&f, at: noon)
        Habits.checkIn(.water, in: &f, now: noon + 60)
        let day = f.econ.daily.day

        // Часы на сутки назад: те же счётчики, не новый день.
        let back = noon - 86400
        XCTAssertEqual(Economy.careLeftToday(f, at: back), 0)
        XCTAssertEqual(Habits.countToday(f, .water, now: back), 1)
        let out = PetRunner.apply(.feed("kibble"), source: .app, to: &f, now: back)
        XCTAssertEqual(out.coins, 0)
        XCTAssertEqual(f.econ.daily.day, day, "назад не откатываемся")
        XCTAssertEqual(f.journal.last { $0.kind == "clock_back" }?.t, back)
        // Журнал не идёт вспять: действие — временем питомца.
        XCTAssertGreaterThanOrEqual(f.journal.last { $0.kind.hasPrefix("act.") }?.t ?? 0, noon)

        // Часы вернули — следующий потолок только с настоящей полуночи.
        XCTAssertEqual(Economy.careLeftToday(f, at: noon + 3600), 0)
        XCTAssertEqual(Economy.careLeftToday(f, at: DayKey.nextMidnight(after: noon)), cap)
    }

    func testClockBackSettlesFutureMarksWithoutTouchingProgress() {
        let t = tdT0
        var f = tdFile(at: t)
        f.tricks[.sit].n = 3
        f.tricks[.sit].t = t + 3600
        f.tricks.joyT = t + 3600
        f.cooking.lastT = t + 3600
        f.cooking.today = 2
        PetRunner.catchUp(&f, now: t + 120)
        XCTAssertEqual(f.tricks[.sit].t, t + 120)
        XCTAssertEqual(f.tricks.joyT, t + 120)
        XCTAssertEqual(f.cooking.lastT, t + 120)
        XCTAssertEqual(f.tricks[.sit].n, 3, "прогресс трюка не сбрасывается")
        XCTAssertEqual(f.cooking.today, 2)
        // Прошлые метки не трогаем.
        f.tricks[.lie].t = t
        PetRunner.catchUp(&f, now: t + 180)
        XCTAssertEqual(f.tricks[.lie].t, t)
    }

    /// Вперёд на сутки, потом обратно: лишних суток нет. Потолок обновился при прыжке, но настоящая
    /// следующая полночь уже «использована» — до неё новых монет нет. Шкалы прожили прыжок как время.
    func testClockForwardThenBackIsNetZero() {
        Clock.zoneOverride = belgrade
        let noon = local(belgrade, 2026, 10, 14, 12)
        var f = tdFile(at: noon)
        tdSpendCare(&f, at: noon)
        let food0 = f.pet.needs[.food] ?? 0

        let ahead = noon + 86400
        PetRunner.catchUp(&f, now: ahead)
        XCTAssertEqual(f.pet.t, ahead, accuracy: 60)
        XCTAssertLessThan(f.pet.needs[.food] ?? 0, food0, "сутки вперёд — сутки голода")
        XCTAssertEqual(Economy.careLeftToday(f, at: ahead), cap)
        tdSpendCare(&f, at: ahead)

        // Вернули часы: питомец ждёт, пока время догонит, счётчики «завтрашние».
        let petT = f.pet.t, needs = f.pet.needs
        PetRunner.catchUp(&f, now: noon + 600)
        XCTAssertEqual(f.pet.t, petT)
        XCTAssertEqual(f.pet.needs, needs)
        XCTAssertEqual(Economy.careLeftToday(f, at: noon + 600), 0)
        let nextMid = DayKey.nextMidnight(after: noon)
        XCTAssertEqual(Economy.careLeftToday(f, at: nextMid + 60), 0, "эти сутки уже были")
        XCTAssertEqual(Economy.careLeftToday(f, at: DayKey.nextMidnight(after: nextMid)), cap)
    }

    // MARK: перелёт

    /// Смена пояса в тот же момент: ни минуты шкал не прибавилось и не пропало.
    func testZoneChangeDoesNotMoveDecay() {
        for h in [12, -12] {
            Clock.zoneOverride = fixed(0)
            let t = tdT0
            var f = tdFile(at: t)
            PetRunner.catchUp(&f, now: t + 3600)
            let petT = f.pet.t, needs = f.pet.needs
            Clock.zoneOverride = fixed(h)
            PetRunner.catchUp(&f, now: t + 3600)
            XCTAssertEqual(f.pet.t, petT, "\(h)")
            XCTAssertEqual(f.pet.needs, needs, "\(h)")
            XCTAssertEqual(f.owner.tzOffsetMin, h * 60)
            XCTAssertFalse(f.journal.contains { $0.kind == "clock_back" }, "перелёт — не перевод часов")
            // Дальше время идёт как шло: час полёта — час шкал.
            PetRunner.catchUp(&f, now: t + 7200)
            XCTAssertEqual(f.pet.t, t + 7200, accuracy: 60)
        }
    }

    /// На запад на 12 ч сразу после полуночи: календарь снова «вчера», но второго потолка нет.
    func testFlightWestGivesNoExtraCap() {
        Clock.zoneOverride = fixed(0)
        let mid = DayKey.nextMidnight(after: tdT0)
        var f = tdFile(at: mid + 3600)
        tdSpendCare(&f, at: mid + 3600)
        let day = f.econ.daily.day

        Clock.zoneOverride = fixed(-12)
        XCTAssertEqual(DayKey.of(mid + 7200), day - 1)
        XCTAssertEqual(Economy.careLeftToday(f, at: mid + 7200), 0)
        PetRunner.apply(.pet, source: .app, to: &f, now: mid + 7200)
        XCTAssertEqual(f.econ.daily.day, day)
        XCTAssertEqual(f.econ.daily.care, cap)
        // Местная полночь на западе — те же сутки по номеру: потолок не обновляется.
        let westMid = DayKey.nextMidnight(after: mid + 7200)
        XCTAssertEqual(DayKey.of(westMid), day)
        XCTAssertEqual(Economy.careLeftToday(f, at: westMid + 60), 0)
        XCTAssertEqual(Economy.careLeftToday(f, at: DayKey.nextMidnight(after: westMid)), cap)
    }

    /// На восток и сразу назад: новые сутки на востоке настоящие, но туда-обратно — ноль лишних потолков.
    func testFlightEastAndBackIsNetZero() {
        Clock.zoneOverride = fixed(0)
        let noon = local(fixed(0), 2026, 10, 14, 12)
        var f = tdFile(at: noon)
        tdSpendCare(&f, at: noon)
        let day = f.econ.daily.day

        Clock.zoneOverride = fixed(12)
        XCTAssertEqual(DayKey.of(noon + 60), day + 1)
        XCTAssertEqual(Economy.careLeftToday(f, at: noon + 60), cap)
        tdSpendCare(&f, at: noon + 60)
        XCTAssertEqual(f.econ.daily.day, day + 1)

        Clock.zoneOverride = fixed(0)
        XCTAssertEqual(Economy.careLeftToday(f, at: noon + 120), 0)
        // Дома настоящая полночь — сутки day + 1 уже выбраны на востоке.
        let mid = DayKey.nextMidnight(after: noon)
        XCTAssertEqual(Economy.careLeftToday(f, at: mid + 60), 0)
        XCTAssertEqual(Economy.careLeftToday(f, at: mid + 86400), cap)
    }

    // MARK: летнее время

    func testDSTDaysAre23And25Hours() {
        Clock.zoneOverride = belgrade
        // Весна: 29 марта 2026, 02:00 → 03:00. Осень: 25 октября 2026, 03:00 → 02:00.
        let spring = local(belgrade, 2026, 3, 29)
        let fall = local(belgrade, 2026, 10, 25)
        XCTAssertEqual(DayKey.nextMidnight(after: spring) - spring, 23 * 3600)
        XCTAssertEqual(DayKey.nextMidnight(after: fall) - fall, 25 * 3600)
        XCTAssertEqual(DayKey.start(DayKey.of(spring + 3600)), spring)
        XCTAssertEqual(DayKey.start(DayKey.of(fall + 3600)), fall)
        for mid in [spring, fall, spring + 23 * 3600, fall + 25 * 3600] {
            XCTAssertEqual(DayKey.of(mid - 1) + 1, DayKey.of(mid))
            XCTAssertEqual(DayKey.of(mid + 1), DayKey.of(mid))
            XCTAssertEqual(DayKey.start(DayKey.of(mid)), mid)
        }
        // Витрина лавки обновляется в местную полночь и в день перевода часов.
        XCTAssertEqual(ShopDaily.secondsToNext(now: fall + 3600), 24 * 3600)
        XCTAssertEqual(ShopDaily.secondsToNext(now: spring + 3600), 22 * 3600)
    }

    /// Осенью стрелки идут с 03:00 на 02:00 — это не «часы назад»: unix-время идёт вперёд, шкалы тоже.
    func testFallBackHourIsNotClockBack() {
        Clock.zoneOverride = belgrade
        let start = local(belgrade, 2026, 10, 25, 1, 30)
        var f = tdFile(at: start)
        var last = f.pet.t
        for k in 1...24 {
            let now = start + Double(k) * 600
            PetRunner.catchUp(&f, now: now)
            XCTAssertGreaterThanOrEqual(f.pet.t, last)
            XCTAssertEqual(f.pet.t, now, accuracy: 60)
            last = f.pet.t
        }
        XCTAssertFalse(f.journal.contains { $0.kind == "clock_back" })
        XCTAssertEqual(f.owner.tzOffsetMin, 60, "после перевода — зимнее время")
        // Четыре часа шкал за четыре часа, хотя на стенных часах прошло три.
        XCTAssertEqual(f.pet.t - start, 4 * 3600, accuracy: 60)
    }

    /// Потолок в день перевода часов сменяется в местную полночь, а не на час раньше или позже.
    func testCapRollsAtLocalMidnightAcrossDST() {
        Clock.zoneOverride = belgrade
        for mid in [local(belgrade, 2026, 3, 30), local(belgrade, 2026, 10, 26)] {
            var f = tdFile(at: mid - 3 * 3600)
            tdSpendCare(&f, at: mid - 3 * 3600)
            XCTAssertEqual(Economy.careLeftToday(f, at: mid - 1), 0)
            XCTAssertEqual(Economy.careLeftToday(f, at: mid), cap)
            XCTAssertEqual(Economy.careLeftToday(f, at: mid - 3601), 0)
        }
    }
}
