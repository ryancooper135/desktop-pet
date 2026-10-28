// «Расчесать» (Brush): разбор мазков по спине, прогресс сеанса, кулдаун, итог для шерсти и любви,
// запись в журнал и чтение её шерстью (Coat.trace), сохранение BrushLog. Гоняется и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let bT0: Double = 1_760_000_000

/// Начало дня питомца: t и t + 2 ч не ночь.
private func bDay(_ owner: Owner, from t0: Double) -> Double {
    var t = t0
    while PetEngine.petNight(t, Catalog.rules, owner) || PetEngine.petNight(t + 7200, Catalog.rules, owner) {
        t += 1800
    }
    return t
}

/// Щенок час от роду, днём: шкалы на 80, сердца полные, шкала look на 0 — шерсть «колтуны» (как LaunchSeed brush).
private func bDull(clean: Double = 80) -> (SaveFile, Double) {
    let probe = SaveFile.fresh(now: bT0)
    let t0 = bDay(probe.owner, from: bT0)
    var f = SaveFile.fresh(now: t0)
    let t = t0 + 3600
    PetRunner.catchUp(&f, now: t)
    for n in [Need.food, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
    f.pet.needs[.love] = 40
    f.pet.needs[.clean] = clean
    f.pet.needs[.look] = 0
    f.pet.hearts = PetEngine.maxHearts(f.pet, Catalog.rules)
    return (f, t)
}

/// Ведение пальцем из (x0, y0) на (dx, dy) шагами по 8 pt.
private func bDrag(_ s: inout BrushTracker, x0: Double = 100, y0: Double = 300, dx: Double, dy: Double = 0,
                   t0: Double = 0) -> [BrushEvent] {
    s.begin(x: x0, y: y0, time: t0)
    let len = (dx * dx + dy * dy).squareRoot()
    let n = max(1, Int((len / 8).rounded(.up)))
    var out: [BrushEvent] = []
    for i in 1...n {
        let k = Double(i) / Double(n)
        out += s.move(x: x0 + dx * k, y: y0 + dy * k, time: t0 + 0.016 * Double(i))
    }
    out += s.end(x: x0 + dx, y: y0 + dy, time: t0 + 0.016 * Double(n + 1))
    return out
}

final class BrushTests: XCTestCase {

    // MARK: жест

    func testThresholdsAreStatic() {
        XCTAssertEqual(BrushTracker.strokeLen, 110)
        XCTAssertEqual(BrushTracker.againstLen, 70)
        XCTAssertEqual(Brush.needed, 8)
        XCTAssertEqual(Brush.cooldownH, 6)
    }

    func testHeadToTailIsStroke() {
        var s = BrushTracker()
        XCTAssertEqual(bDrag(&s, dx: 130), [.stroke])
        XCTAssertFalse(s.active)
    }

    func testShortStrokeDoesNotCount() {
        var s = BrushTracker()
        XCTAssertEqual(bDrag(&s, dx: 90), [])
    }

    func testLongStrokeCountsSeveralTimes() {
        var s = BrushTracker()
        XCTAssertEqual(bDrag(&s, x0: 10, dx: 340), [.stroke, .stroke, .stroke])
    }

    func testAgainstTheFurWinces() {
        var s = BrushTracker()
        XCTAssertEqual(bDrag(&s, x0: 300, dx: -100), [.against])
    }

    func testAgainstThrottledInOneMove() {
        var s = BrushTracker()
        // 300 pt назад за полсекунды — одно морщенье, а не четыре.
        XCTAssertEqual(bDrag(&s, x0: 340, dx: -300), [.against])
        // Новое движение через секунду — снова морщится.
        XCTAssertEqual(bDrag(&s, x0: 340, dx: -100, t0: 2), [.against])
    }

    func testBackAndForth() {
        var s = BrushTracker()
        s.begin(x: 0, y: 0, time: 0)
        var out: [BrushEvent] = []
        var t = 0.0
        for x in stride(from: 8.0, through: 120, by: 8) { t += 0.016; out += s.move(x: x, y: 0, time: t) }
        XCTAssertEqual(out, [.stroke], "туда — мазок")
        out = []
        for x in stride(from: 112.0, through: 20, by: -8) { t += 0.016; out += s.move(x: x, y: 0, time: t) }
        XCTAssertEqual(out, [.against], "обратно — против шерсти")
    }

    func testTurnBackAfterPartialRunStartsFromFarPoint() {
        var s = BrushTracker()
        s.begin(x: 0, y: 0, time: 0)
        // 100 pt вправо (не мазок), потом назад: «против» считается от дальней точки, а не от начала.
        for x in stride(from: 10.0, through: 100, by: 10) { XCTAssertEqual(s.move(x: x, y: 0, time: x / 1000), []) }
        XCTAssertEqual(s.move(x: 50, y: 0, time: 0.2), [], "откат 50 — ещё нет")
        XCTAssertEqual(s.move(x: 25, y: 0, time: 0.3), [.against], "откат 75 от дальней точки")
    }

    func testSidewaysIsNothing() {
        var s = BrushTracker()
        XCTAssertEqual(bDrag(&s, dx: 0, dy: 300), [], "вдоль тела вниз — не мазок")
        XCTAssertEqual(bDrag(&s, dx: 20, dy: -250), [])
    }

    func testDriftResetsRun() {
        var s = BrushTracker()
        s.begin(x: 0, y: 0, time: 0)
        XCTAssertEqual(s.move(x: 60, y: 0, time: 0.1), [])
        XCTAssertEqual(s.move(x: 60, y: 120, time: 0.2), [], "увело поперёк — прогон заново")
        XCTAssertEqual(s.move(x: 160, y: 120, time: 0.3), [], "от новой точки только 100")
        XCTAssertEqual(s.move(x: 175, y: 120, time: 0.4), [.stroke])
    }

    func testCustomAxis() {
        var s = BrushTracker(axisX: 1, axisY: 1)
        XCTAssertEqual(bDrag(&s, dx: 85, dy: 85), [.stroke], "по диагонали 120 pt")
        XCTAssertEqual(bDrag(&s, x0: 300, dx: -60, dy: -60), [.against])
        var z = BrushTracker(axisX: 0, axisY: 0)
        XCTAssertEqual(z.axisX, 1)
        XCTAssertEqual(bDrag(&z, dx: 120), [.stroke], "нулевая ось — вправо")
    }

    func testMoveWithoutBeginStarts() {
        var s = BrushTracker()
        XCTAssertEqual(s.move(x: 0, y: 0, time: 0), [])
        XCTAssertTrue(s.active)
        XCTAssertEqual(s.end(x: 120, y: 0, time: 0.2), [.stroke])
        XCTAssertEqual(s.end(x: 300, y: 0, time: 0.3), [], "после конца — тишина")
    }

    // MARK: сеанс

    func testSessionProgress() {
        var b = BrushSession()
        XCTAssertEqual(b.percent, 0)
        XCTAssertEqual(b.text, "Расчёсано 0%")
        XCTAssertEqual(b.tufts(of: 6), 6)
        for i in 1..<Brush.needed { XCTAssertFalse(b.add(), "\(i)") }
        XCTAssertEqual(b.percent, 88)
        XCTAssertEqual(b.tufts(of: 6), 1, "до конца хоть один колтун")
        XCTAssertTrue(b.add(), "последний мазок — конец")
        XCTAssertTrue(b.done)
        XCTAssertEqual(b.percent, 100)
        XCTAssertEqual(b.tufts(of: 6), 0)
        XCTAssertFalse(b.add(), "дальше не считает")
        XCTAssertEqual(b.counted, Brush.needed)
        XCTAssertEqual(BrushSession(counted: 4).text, "Расчёсано 50%")
        XCTAssertEqual(BrushSession(counted: 99).counted, Brush.needed)
        XCTAssertEqual(BrushSession(needed: 0).needed, 1)
    }

    func testTuftsByStage() {
        let n = CoatStage.allCases.map(Brush.tufts)
        XCTAssertEqual(n, [6, 4, 2, 1])
    }

    // MARK: шерсть

    func testLiftRaisesExactlyOneStage() {
        for stage in CoatStage.allCases {
            for bonus in [0.0, 0.1, 0.3] {
                for raw in stride(from: 0.0, through: 1, by: 0.05) {
                    let v = Coat.clamp(raw + bonus)
                    guard Coat.stage(for: v, from: stage) == stage else { continue }
                    let lifted = Brush.lift(raw: raw, bonus: bonus, stage: stage)
                    XCTAssertGreaterThanOrEqual(lifted, raw)
                    let next = Coat.stage(for: Coat.clamp(lifted + bonus), from: stage)
                    let want = CoatStage.allCases[min(stage.rank + 1, 3)]
                    XCTAssertEqual(next, want, "\(stage) raw \(raw) bonus \(bonus)")
                }
            }
        }
    }

    func testDullSeedIsMatted() {
        let (f, t) = bDull()
        XCTAssertEqual(Coat.look(f, now: t).stage, .matted, "щенок без look — колтуны (сид brush)")
        XCTAssertNil(Brush.gate(f, at: t))
    }

    func testFinishLiftsCoatAndLove() throws {
        var (f, t) = bDull()
        let love0 = f.pet.needs[.love] ?? 0
        let coins0 = f.econ.wallet.coins
        let out = Brush.finish(&f, now: t)
        XCTAssertTrue(out.ok)
        XCTAssertNil(out.reason)
        XCTAssertEqual(out.before, .matted)
        XCTAssertEqual(out.after, .shaggy, "колтуны → лохматый")
        XCTAssertGreaterThan(out.love, 0)
        XCTAssertEqual(f.pet.needs[.love] ?? 0, love0 + out.love, accuracy: 1e-9)
        XCTAssertEqual(f.econ.wallet.coins, coins0, "монет не даёт")
        // С волны 10 — действие ядра: запись act.brush, как у «Погладить» (источник — приложение).
        let e = try XCTUnwrap(f.journal.last { $0.kind == Brush.actKind })
        XCTAssertEqual(e.ok, true)
        XCTAssertEqual(e.source, .app)
        XCTAssertEqual(e.t, f.pet.t)
        XCTAssertFalse(f.journal.contains { $0.kind == Brush.journalKind }, "старая запись «brush» больше не пишется")
        XCTAssertEqual(f.pet.cooldowns[PetEngine.BRUSH_COOLDOWN], t + 6 * 3600, "откат держит ядро")
        XCTAssertEqual(f.lastAction?.kind, "brush")
        XCTAssertEqual(f.brush.t, t)
        XCTAssertEqual(f.brush.n, 1)
        XCTAssertEqual(Coat.look(f, now: t).stage, .shaggy)
    }

    func testLiftHoldsForHoursEvenIfDirty() {
        var (f, t) = bDull(clean: 15)
        let out = Brush.finish(&f, now: t)
        XCTAssertTrue(out.ok)
        XCTAssertEqual(out.after, .shaggy)
        XCTAssertEqual(Coat.look(f, now: t + 3 * 3600).stage, .shaggy, "три часа спустя не слетает")
    }

    func testCooldown() {
        var (f, t) = bDull()
        XCTAssertTrue(Brush.finish(&f, now: t).ok)
        XCTAssertEqual(Brush.gate(f, at: t + 60), Brush.cooldownReason)
        XCTAssertEqual(Brush.remaining(f, at: t + 3600), 5 * 3600, accuracy: 1e-6)
        XCTAssertEqual(Brush.reasonText(Brush.cooldownReason, remaining: Brush.remaining(f, at: t + 3600)),
                       "Шерсть уже расчёсана · через 5 ч")
        XCTAssertEqual(Brush.reasonText(Brush.cooldownReason, remaining: 1200), "Шерсть уже расчёсана · через час")
        let again = Brush.finish(&f, now: t + 60)
        XCTAssertFalse(again.ok)
        XCTAssertEqual(again.reason, Brush.cooldownReason)
        XCTAssertEqual(again.before, again.after)
        XCTAssertEqual(f.brush.n, 1, "отказ не считается")
        XCTAssertEqual(f.journal.filter { $0.kind == Brush.actKind && $0.ok == true }.count, 1)
        XCTAssertFalse(f.journal.contains { $0.kind == Brush.actKind && $0.ok == false }, "отказ по откату в журнал не идёт")
        // Часы назад: ядро ждёт, пока pet.t не пройдёт откат (как у «Погладить»); остаток не больше 6 ч.
        XCTAssertEqual(Brush.remaining(f, at: t - 3600), 6 * 3600, accuracy: 1e-6)
        XCTAssertEqual(Brush.remaining(f, at: t + 6 * 3600), 0)
        XCTAssertNil(Brush.gate(f, at: t + 6 * 3600))
        XCTAssertTrue(Brush.finish(&f, now: t + 6 * 3600).ok)
        XCTAssertEqual(f.brush.n, 2)
    }

    /// Сейв до волны 10: откат жил только в BrushLog.t, в ядре его нет — подхватываем.
    func testLegacySaveKeepsCooldown() {
        var (f, t) = bDull()
        f.brush.t = t - 3600
        f.brush.n = 3
        XCTAssertNil(f.pet.cooldowns[PetEngine.BRUSH_COOLDOWN])
        XCTAssertEqual(Brush.gate(f, at: t), Brush.cooldownReason)
        XCTAssertEqual(Brush.remaining(f, at: t), 5 * 3600, accuracy: 1e-6)
        let no = Brush.finish(&f, now: t)
        XCTAssertFalse(no.ok)
        XCTAssertEqual(no.reason, Brush.cooldownReason)
        XCTAssertEqual(f.brush.n, 3)
        let later = t + 5 * 3600
        XCTAssertNil(Brush.gate(f, at: later))
        XCTAssertTrue(Brush.finish(&f, now: later).ok)
        XCTAssertEqual(f.brush.n, 4)
        XCTAssertEqual(f.brush.t, later)
        // Метка из будущего (часы переводили назад) больше 6 ч не держит.
        var g = bDull().0
        g.brush.t = t + 10 * 3600
        g.brush.n = 1
        XCTAssertNil(Brush.gate(g, at: t))
    }

    /// Ласка — ровно половина «Погладить» в том же состоянии; монет нет и в Economy.settle.
    func testLoveIsHalfOfPetAndNoCoins() {
        var (f, t) = bDull()
        var p = f
        XCTAssertTrue(PetRunner.apply(.pet, source: .app, to: &p, now: t).ok)
        let petGain = (p.pet.needs[.love] ?? 0) - (f.pet.needs[.love] ?? 0)
        let coins0 = f.econ.wallet.coins
        let out = Brush.finish(&f, now: t)
        XCTAssertEqual(out.love, petGain / 2, accuracy: 1e-9)
        XCTAssertEqual(f.econ.wallet.coins, coins0)
        XCTAssertTrue(Economy.settle(&f).isEmpty, "запись act.brush уже разобрана и без монет")
    }

    /// Шерсть читает и новые записи act.brush, и старые «brush» из сейвов до волны 10.
    func testCoatReadsLegacyJournal() {
        var (f, t) = bDull()
        var legacy = f
        _ = Brush.finish(&f, now: t)
        legacy.log(Brush.journalKind, t: t, value: CoatStage.matted.rank)
        XCTAssertEqual(Coat.look(legacy, now: t + 60).stage, Coat.look(f, now: t + 60).stage)
        XCTAssertEqual(Coat.look(legacy, now: t + 60).stage, .shaggy)
    }

    func testGateFollowsTricks() {
        var (f, t) = bDull()
        f.pet.napUntil = t + 600
        XCTAssertEqual(Brush.gate(f, at: t), "asleep")
        XCTAssertEqual(Brush.reasonText("asleep"), RefuseText.text("asleep"))
        let out = Brush.finish(&f, now: t)
        XCTAssertFalse(out.ok)
        XCTAssertEqual(out.reason, "asleep")
        XCTAssertTrue(f.brush.isEmpty)
        f.pet.napUntil = nil
        f.pet.alive = false
        XCTAssertEqual(Brush.gate(f, at: t), "dead")
    }

    func testCoatIsDeterministicWithBrush() {
        var (f, t) = bDull()
        _ = Brush.finish(&f, now: t)
        XCTAssertEqual(Coat.look(f, now: t + 1800), Coat.look(f, now: t + 1800))
        XCTAssertGreaterThanOrEqual(Coat.look(f, now: t + 1800).groom, Coat.look(f, now: t - 60).groom)
    }

    // MARK: файл

    func testBrushLogRoundTrip() throws {
        var (f, t) = bDull()
        let plain = try JSONEncoder().encode(f)
        // Ищем ключ поля, а не слово: просьба пса (волна 43 K) может хранить вид "brush" как значение.
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("\"brush\":"), "пустое в файл не пишется")
        _ = Brush.finish(&f, now: t)
        let data = try JSONEncoder().encode(f)
        let back = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(back.brush, f.brush)
        XCTAssertEqual(back.brush.n, 1)
        XCTAssertEqual(back.brush.t, t)
        // Старый сейв без поля и битое поле — пустой журнал расчёсок, а не ошибка.
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj["brush"] = nil
        XCTAssertTrue(try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj)).brush.isEmpty)
        obj["brush"] = "мусор"
        XCTAssertTrue(try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj)).brush.isEmpty)
    }
    /// Волна 11: в конце своя довольная фраза по кругу; подъём стадии дописывается к ней.
    func testDoneTextRotatesAndMentionsStage() {
        var (f, t) = bDull()
        let first = Brush.finish(&f, now: t)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(Brush.doneText(first), "\(Brush.doneLines[0]) · шерсть «Лохматый»")
        XCTAssertGreaterThanOrEqual(Brush.doneLines.count, 3)
        XCTAssertEqual(Set(Brush.doneLines).count, Brush.doneLines.count, "фразы разные")
        // Стадия та же (уже гладкий) — только фраза; по кругу от числа расчёсываний.
        func same(_ n: Int) -> BrushOutcome {
            BrushOutcome(ok: true, reason: nil, before: .sleek, after: .sleek, love: 1, count: n)
        }
        XCTAssertEqual(Brush.doneText(same(1)), Brush.doneLines[0])
        XCTAssertEqual(Brush.doneText(same(2)), Brush.doneLines[1])
        XCTAssertEqual(Brush.doneText(same(Brush.doneLines.count + 1)), Brush.doneLines[0])
        XCTAssertNotEqual(Brush.doneText(same(2)), Brush.doneText(same(3)), "подряд не повторяется")
        XCTAssertEqual(Brush.doneText(same(0)), Brush.doneLines[0], "старый исход без счётчика — первая фраза")
    }
}
