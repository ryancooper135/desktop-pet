// Режим сна владельца (OwnerSleep): ночи через полночь, часовые пояса и переезд, выбросы, 14 дней и 5 ночей,
// ручное окно, тихие часы с пределом (последний шанс раньше смерти), «Доброе утро» и «Отбой?» по разу, сейв.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Полночь UTC, день 20 000 (2024-10-04): от неё считаем местные дни.
private let sDay0 = 20_000

/// Момент «местный день d, hh:mm» при сдвиге tz.
private func sT(_ d: Int, _ h: Int, _ m: Int, tz: Int = 0) -> Double {
    Double((sDay0 + d) * 1440 + h * 60 + m - tz) * 60
}

/// Ночь: заход вечером в eh:em дня d и первый заход утром mh:mm дня d+1 (eh < 12 — уже после полуночи).
private func sNight(_ log: inout SleepLog, _ d: Int, eve: (Int, Int), morn: (Int, Int), tz: Int = 0) {
    let ed = eve.0 < 12 ? d + 1 : d
    OwnerSleep.note(&log, t: sT(ed, eve.0, eve.1, tz: tz), tzOffsetMin: tz)
    OwnerSleep.note(&log, t: sT(d + 1, morn.0, morn.1, tz: tz), tzOffsetMin: tz)
}

private func sLog(_ nights: [((Int, Int), (Int, Int))], from d0: Int = 0, tz: Int = 0) -> SleepLog {
    var log = SleepLog()
    for (i, n) in nights.enumerated() { sNight(&log, d0 + i, eve: n.0, morn: n.1, tz: tz) }
    return log
}

final class OwnerSleepTests: XCTestCase {

    // MARK: координаты

    func testNoonRelativeMinutes() {
        XCTAssertEqual(OwnerSleep.noonRel(18 * 60), 360)
        XCTAssertEqual(OwnerSleep.noonRel(0), 720)
        XCTAssertEqual(OwnerSleep.noonRel(40), 760)
        XCTAssertEqual(OwnerSleep.noonRel(8 * 60 + 10), 1210)
        for m in stride(from: 0, to: 1440, by: 5) {
            XCTAssertEqual(OwnerSleep.clock(OwnerSleep.noonRel(m)), m)
        }
        XCTAssertEqual(OwnerSleep.circDiff(23 * 60 + 50, 10), 20)
        XCTAssertEqual(OwnerSleep.circDiff(10, 23 * 60 + 50), 20)
        XCTAssertTrue(OwnerSleep.inWindow(30, 23 * 60, 8 * 60))
        XCTAssertFalse(OwnerSleep.inWindow(8 * 60, 23 * 60, 8 * 60), "конец окна — уже не тихо")
        XCTAssertEqual(OwnerSleep.text(SleepWindow(bed: 40, wake: 490)), "00:40–08:10")
    }

    func testLocalDayWithNegativeOffset() {
        // 02:00 UTC при −5 ч — это 21:00 предыдущего местного дня.
        let t = sT(3, 2, 0)
        let l = OwnerSleep.local(t, tzOffsetMin: -300)
        XCTAssertEqual(l.day, sDay0 + 2)
        XCTAssertEqual(l.min, 21 * 60)
    }

    // MARK: запись

    func testEveningIsLastTouchMorningIsFirst() {
        var log = SleepLog()
        OwnerSleep.note(&log, t: sT(0, 21, 0), tzOffsetMin: 0)
        OwnerSleep.note(&log, t: sT(0, 23, 30), tzOffsetMin: 0)
        OwnerSleep.note(&log, t: sT(1, 0, 40), tzOffsetMin: 0)
        OwnerSleep.note(&log, t: sT(1, 8, 10), tzOffsetMin: 0)
        OwnerSleep.note(&log, t: sT(1, 9, 0), tzOffsetMin: 0)
        OwnerSleep.note(&log, t: sT(1, 15, 0), tzOffsetMin: 0)
        XCTAssertEqual(log.nights.count, 1, "день 14:00–18:00 о сне ничего не говорит")
        XCTAssertEqual(log.nights[0].n, sDay0)
        XCTAssertEqual(log.nights[0].eve, 760, "вечер — последний заход, после полуночи тоже")
        XCTAssertEqual(log.nights[0].morn, 1210, "утро — первый заход")
    }

    func testWidgetCountsStepsAndShortcutsDont() {
        XCTAssertTrue(OwnerSleep.counts(.app))
        XCTAssertTrue(OwnerSleep.counts(.widget))
        XCTAssertTrue(OwnerSleep.counts(.island))
        XCTAssertTrue(OwnerSleep.counts(.control))
        XCTAssertTrue(OwnerSleep.counts(.notification))
        XCTAssertFalse(OwnerSleep.counts(.steps), "шаги приходят сами")
        XCTAssertFalse(OwnerSleep.counts(.shortcut), "команду может запустить автоматизация")
    }

    func testRunnerNotesWidgetTapButNotSteps() throws {
        var f = SaveFile.fresh(now: sT(0, 12, 0))
        let tz = f.owner.tzOffsetMin
        let late = Double(sDay0 * 1440 + 23 * 60 + 50 - tz) * 60
        _ = PetRunner.apply(.pet, source: .widget, to: &f, now: late)
        XCTAssertEqual(f.sleep.nights.last?.eve, OwnerSleep.noonRel(23 * 60 + 50))
        let later = late + 1800
        _ = PetRunner.apply(.steps(500), source: .steps, to: &f, now: later)
        XCTAssertEqual(f.sleep.lastT, late, "шаги — не касание")
    }

    // MARK: оценка

    func testDefaultUntilFiveNights() {
        let n = ((0, 40), (8, 10))
        var log = sLog(Array(repeating: n, count: 4))
        var est = OwnerSleep.estimate(log, now: sT(5, 12, 0), tzOffsetMin: 0)
        XCTAssertEqual(est.window, OwnerSleep.defaultWindow)
        XCTAssertEqual(est.source, .learning(4))
        XCTAssertTrue(est.isLearning)
        XCTAssertEqual(OwnerSleep.status(est), "пока учусь: 4 из 5 ночей")
        sNight(&log, 4, eve: n.0, morn: n.1)
        est = OwnerSleep.estimate(log, now: sT(6, 12, 0), tzOffsetMin: 0)
        XCTAssertEqual(est.source, .learned)
        XCTAssertEqual(est.window, SleepWindow(bed: 40, wake: 490))
        XCTAssertEqual(OwnerSleep.status(est), "учится сам")
    }

    func testMedianAcrossMidnight() {
        // 23:40, 23:50, 00:00, 00:10, 00:20 — медиана полночь, а не полдень.
        let log = sLog([((23, 40), (7, 50)), ((0, 10), (8, 0)), ((23, 50), (8, 10)), ((0, 20), (8, 0)), ((0, 0), (7, 55))])
        let est = OwnerSleep.estimate(log, now: sT(6, 12, 0), tzOffsetMin: 0)
        XCTAssertEqual(est.window, SleepWindow(bed: 0, wake: 8 * 60))
    }

    func testOutliersDropped() {
        // Четыре обычные ночи около 00:30 и два вечера, когда «уснул» в 19:00 (просто не заходил): медиана без них.
        let log = sLog([((0, 30), (8, 0)), ((19, 0), (8, 0)), ((0, 40), (8, 10)), ((0, 20), (7, 50)),
                        ((19, 30), (8, 0)), ((0, 50), (8, 0))])
        let est = OwnerSleep.estimate(log, now: sT(7, 12, 0), tzOffsetMin: 0)
        XCTAssertEqual(est.window.bed, 35, "(00:30 + 00:40) / 2 после отброса 19:00 и 19:30")
        XCTAssertEqual(est.window.wake, 8 * 60)
    }

    func testImplausibleNightsSkipped() {
        // Шесть ночей: одна — «лёг в 03:30, встал в 05:00» (1,5 ч), одна без утра — в оценку не идут.
        var log = sLog(Array(repeating: ((1, 0), (9, 0)), count: 5))
        sNight(&log, 5, eve: (3, 30), morn: (5, 0))
        OwnerSleep.note(&log, t: sT(6, 23, 0), tzOffsetMin: 0)
        XCTAssertEqual(OwnerSleep.usableNights(log, now: sT(8, 12, 0), tzOffsetMin: 0).count, 5)
        let est = OwnerSleep.estimate(log, now: sT(8, 12, 0), tzOffsetMin: 0)
        XCTAssertEqual(est.window, SleepWindow(bed: 60, wake: 9 * 60))
    }

    func testOnlyLastFourteenDays() {
        // Месяц назад ложился в 02:00, последние 6 ночей — в 23:30: старое забыто.
        var log = sLog(Array(repeating: ((2, 0), (10, 0)), count: 6))
        for d in 20..<26 { sNight(&log, d, eve: (23, 30), morn: (7, 30)) }
        let est = OwnerSleep.estimate(log, now: sT(26, 12, 0), tzOffsetMin: 0)
        XCTAssertEqual(est.window, SleepWindow(bed: 23 * 60 + 30, wake: 7 * 60 + 30))
        XCTAssertEqual(est.nights, 6)
        XCTAssertTrue(log.nights.allSatisfy { $0.n >= sDay0 + 25 - OwnerSleep.keepNights }, "старше 21 ночи не храним")
        // А через 15 дней тишины — снова учится.
        let gone = OwnerSleep.estimate(log, now: sT(41, 12, 0), tzOffsetMin: 0)
        XCTAssertTrue(gone.isLearning)
    }

    func testTimeZonesAndTravel() {
        // В Белграде (+60) и после переезда в Москву (+180) ложится в 00:30 по местному: окно не съезжает.
        var log = sLog(Array(repeating: ((0, 30), (8, 0)), count: 3), tz: 60)
        for d in 3..<6 { sNight(&log, d, eve: (0, 30), morn: (8, 0), tz: 180) }
        let est = OwnerSleep.estimate(log, now: sT(6, 12, 0, tz: 180), tzOffsetMin: 180)
        XCTAssertEqual(est.window, SleepWindow(bed: 30, wake: 8 * 60))
        // Тот же хозяин в Нью-Йорке (−300): дни считаются по местному времени, ночь через полночь UTC не рвётся.
        let ny = sLog(Array(repeating: ((23, 0), (7, 0)), count: 5), tz: -300)
        let e2 = OwnerSleep.estimate(ny, now: sT(5, 12, 0, tz: -300), tzOffsetMin: -300)
        XCTAssertEqual(e2.window, SleepWindow(bed: 23 * 60, wake: 7 * 60))
        XCTAssertEqual(ny.nights.count, 5)
    }

    func testManualWinsAndForgets() {
        var log = sLog(Array(repeating: ((0, 40), (8, 10)), count: 6))
        log.manual = SleepWindow(bed: 22 * 60, wake: 6 * 60)
        var est = OwnerSleep.estimate(log, now: sT(6, 12, 0), tzOffsetMin: 0)
        XCTAssertEqual(est.source, .manual)
        XCTAssertEqual(est.window, SleepWindow(bed: 22 * 60, wake: 6 * 60))
        XCTAssertEqual(OwnerSleep.status(est), "задано вручную")
        log.manual = nil
        est = OwnerSleep.estimate(log, now: sT(6, 12, 0), tzOffsetMin: 0)
        XCTAssertEqual(est.window, SleepWindow(bed: 40, wake: 490))
    }

    // MARK: тихие часы

    func testQuietUnionWithCap() {
        let cap = Int(Catalog.rules.noDeathAfterWakeH * 60)
        XCTAssertEqual(cap, 180)
        func q(_ b: Int, _ w: Int) -> (Int, Int) {
            let r = OwnerSleep.quiet(bedMin: 23 * 60, wakeMin: 7 * 60 + 30, est: SleepWindow(bed: b, wake: w), capMin: cap)
            return (r.from, r.to)
        }
        XCTAssertTrue(q(40, 490) == (23 * 60, 490), "питомец 23:00–07:30 и хозяин 00:40–08:10")
        XCTAssertTrue(q(0, 480) == (23 * 60, 480), "по умолчанию — до 08:00")
        XCTAssertTrue(q(2 * 60, 11 * 60 + 30) == (23 * 60, 10 * 60 + 30), "поздний подъём — не дальше 3 ч")
        XCTAssertTrue(q(19 * 60, 5 * 60) == (20 * 60, 7 * 60 + 30), "ранний отбой — не раньше 3 ч")
        XCTAssertTrue(q(22 * 60, 6 * 60) == (22 * 60, 7 * 60 + 30))
        // Питомец ложится после полуночи, хозяин раньше.
        let r = OwnerSleep.quiet(bedMin: 60, wakeMin: 7 * 60 + 30, est: SleepWindow(bed: 23 * 60, wake: 7 * 60), capMin: cap)
        XCTAssertTrue((r.from, r.to) == (23 * 60, 7 * 60 + 30))
    }

    func testPlannerSilentInOwnerSleepAndLastChanceBeforeDeath() throws {
        var checked = 0
        let windows = [SleepWindow(bed: 40, wake: 490), SleepWindow(bed: 3 * 60, wake: 13 * 60),
                       SleepWindow(bed: 18 * 60, wake: 4 * 60), SleepWindow(bed: 2 * 60, wake: 14 * 60)]
        for w in windows {
            for h in stride(from: 0, to: 24, by: 3) {
                let now = sT(0, h, 0)
                var f = SaveFile.fresh(now: now)
                for n in Need.allCases { f.pet.needs[n] = 15 }
                f.sleep.manual = w
                let o = PetRunner.owner(f, at: now)
                let q = NotificationPlanner.quietHours(f, now: now, owner: o)
                let notes = NotificationPlanner.plan(f, now: now).filter { $0.category != "pet.build" }
                for n in notes {
                    let m = PetEngine.localMin(n.date.timeIntervalSince1970, o)
                    XCTAssertFalse(OwnerSleep.inWindow(m, q.from, q.to), "\(n.trigger) в тихие часы \(w) h=\(h)")
                }
                let ev = ForecastTools.upcoming(f.pet, at: now, horizonH: NotificationPlanner.horizonH, owner: o)
                guard let death = ev.first(where: { $0.kind == .death }),
                      let lc = ev.first(where: { $0.kind == .last_chance }), lc.t > now + 3600,
                      lc.t < now + 2 * 86400 else { continue }
                let note = notes.first { $0.trigger == NotifyTrigger.last_chance.rawValue }
                let at = try XCTUnwrap(note, "последний шанс пропал: окно \(w) h=\(h)").date.timeIntervalSince1970
                XCTAssertLessThan(at, death.t, "последний шанс раньше смерти")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 8, "проверка не пустая")
    }

    // MARK: «Доброе утро» и «Отбой?»

    func testGreetingOncePerNightAndNotOnInstall() {
        var log = SleepLog()
        OwnerSleep.note(&log, t: sT(1, 8, 20), tzOffsetMin: 0)
        XCTAssertNil(OwnerSleep.greetingDue(log, now: sT(1, 8, 20), tzOffsetMin: 0), "только поставили — не здороваемся")
        OwnerSleep.note(&log, t: sT(1, 23, 50), tzOffsetMin: 0)
        OwnerSleep.note(&log, t: sT(2, 8, 10), tzOffsetMin: 0)
        let night = OwnerSleep.greetingDue(log, now: sT(2, 8, 10), tzOffsetMin: 0)
        XCTAssertEqual(night, sDay0 + 1)
        log.greeted = night
        OwnerSleep.note(&log, t: sT(2, 12, 0), tzOffsetMin: 0)
        XCTAssertNil(OwnerSleep.greetingDue(log, now: sT(2, 12, 0), tzOffsetMin: 0), "за ночь — один раз")
        // Не спал всю ночь (касания каждый час) — утро не «проснулся».
        var owl = SleepLog()
        for k in 0..<12 { OwnerSleep.note(&owl, t: sT(3, 22, 0) + Double(k) * 3600, tzOffsetMin: 0) }
        XCTAssertNil(OwnerSleep.greetingDue(owl, now: sT(4, 9, 0), tzOffsetMin: 0))
        // После обеда — уже не утро.
        var late = SleepLog()
        OwnerSleep.note(&late, t: sT(5, 0, 30), tzOffsetMin: 0)
        OwnerSleep.note(&late, t: sT(5, 13, 30), tzOffsetMin: 0)
        XCTAssertNil(OwnerSleep.greetingDue(late, now: sT(5, 13, 30), tzOffsetMin: 0))
    }

    func testBedHintNearLearnedBedtime() {
        let log = sLog(Array(repeating: ((0, 40), (8, 10)), count: 6))
        let est = OwnerSleep.estimate(log, now: sT(6, 23, 0), tzOffsetMin: 0)
        XCTAssertNil(OwnerSleep.bedHintDue(log, est: est, bedMin: 23 * 60, now: sT(6, 23, 0), tzOffsetMin: 0), "рано")
        let night = OwnerSleep.bedHintDue(log, est: est, bedMin: 23 * 60, now: sT(7, 0, 35), tzOffsetMin: 0)
        XCTAssertEqual(night, sDay0 + 6)
        var told = log
        told.hinted = night
        XCTAssertNil(OwnerSleep.bedHintDue(told, est: est, bedMin: 23 * 60, now: sT(7, 0, 50), tzOffsetMin: 0), "раз за ночь")
        XCTAssertNil(OwnerSleep.bedHintDue(log, est: est, bedMin: 40, now: sT(7, 0, 35), tzOffsetMin: 0),
                     "Шиба и так ложится вместе с хозяином")
        let learning = OwnerSleep.estimate(SleepLog(), now: sT(6, 23, 0), tzOffsetMin: 0)
        XCTAssertNil(OwnerSleep.bedHintDue(SleepLog(), est: learning, bedMin: 23 * 60, now: sT(7, 0, 5), tzOffsetMin: 0))
    }

    func testSuggestedBedClampedToSettings() {
        func est(_ b: Int) -> SleepEstimate { SleepEstimate(window: SleepWindow(bed: b, wake: 8 * 60), source: .learned, nights: 6) }
        XCTAssertEqual(OwnerSleep.suggestedBed(est(40), bedMin: 23 * 60), 40)
        XCTAssertNil(OwnerSleep.suggestedBed(est(23 * 60 + 10), bedMin: 23 * 60), "разница меньше 20 минут")
        XCTAssertEqual(OwnerSleep.suggestedBed(est(3 * 60 + 30), bedMin: 23 * 60), 2 * 60, "позже 02:00 «Ложусь в» не бывает")
        XCTAssertEqual(OwnerSleep.suggestedBed(est(19 * 60), bedMin: 23 * 60), 20 * 60)
        XCTAssertTrue(SettingsBedOptions.all.contains(OwnerSleep.suggestedBed(est(1 * 60 + 25), bedMin: 23 * 60) ?? -1))
        let learning = SleepEstimate(window: OwnerSleep.defaultWindow, source: .learning(2), nights: 2)
        XCTAssertNil(OwnerSleep.suggestedBed(learning, bedMin: 23 * 60))
    }

    // MARK: сейв

    func testSaveRoundTripAndOldSave() throws {
        var f = SaveFile.fresh(now: sT(0, 12, 0))
        let plain = try JSONEncoder().encode(f)
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("\"sleep\""), "пустое в файл не пишем")
        f.sleep = sLog(Array(repeating: ((0, 40), (8, 10)), count: 3))
        f.sleep.manual = SleepWindow(bed: 30, wake: 480)
        f.sleep.greeted = sDay0 + 2
        let data = try JSONEncoder().encode(f)
        let back = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(back.sleep, f.sleep)
        // Старый сейв без «sleep» читается, а битое поле не роняет весь файл.
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj.removeValue(forKey: "sleep")
        let old = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertTrue(old.sleep.isEmpty)
        XCTAssertEqual(old.petId, f.petId)
        obj["sleep"] = ["nights": "мусор", "manual": ["bed": 60, "wake": 420]]
        let bad = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertTrue(bad.sleep.nights.isEmpty)
        XCTAssertEqual(bad.sleep.manual, SleepWindow(bed: 60, wake: 420))
    }
}

/// «Ложусь в» в настройках — 20:00–02:00 с шагом 5 минут (копия SettingsScreen.bedOptions: экран на Linux не собирается).
private enum SettingsBedOptions {
    static let all: [Int] = Array(stride(from: 20 * 60, to: 24 * 60, by: 5)) + Array(stride(from: 0, through: 2 * 60, by: 5))
}
