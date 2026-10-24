// Отклик на действие (волна 32, ReactBeat): длительности реакций по настоящим клипам Шибы, присед без желе
// и без наложения, возврат в покой, без пружинного прыжка поверх клипов, на закрытую кнопку — сразу отказ.
// Гоняется и на Linux (app/Package.swift): только Shared и PetCore, клипы — из shiba.clips.json по пути.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

final class ReactBeatTests: XCTestCase {
    // MARK: клипы из бандла

    private struct Table: Decodable {
        struct Clip: Decodable { var start: Double; var end: Double }
        var fps: Double
        var clips: [String: Clip]
    }

    /// Части eat, как их режет сцена (EatClip в PetClips.swift: кадры 17 и 41).
    private static let chewFrom = 17.0, chewTo = 41.0

    private func durations() throws -> [String: Double] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Pets/shiba.clips.json")
        let t = try JSONDecoder().decode(Table.self, from: Data(contentsOf: url))
        var d = t.clips.mapValues { $0.end - $0.start }
        let eat = try XCTUnwrap(d["eat"])
        d["eat_down"] = Self.chewFrom / t.fps
        d["eat_chew"] = (Self.chewTo - Self.chewFrom) / t.fps
        d["eat_up"] = eat - Self.chewTo / t.fps
        return d
    }

    private func meal(_ chews: Int) -> [String] {
        ["eat_down"] + Array(repeating: "eat_chew", count: chews) + ["eat_up"]
    }

    func testPlansUseOnlyBundledClips() throws {
        let d = try durations()
        let plans = [ReactBeat.pet, ReactBeat.refuse, ReactBeat.wakeFromSleep, ReactBeat.afterMeal,
                     ReactBeat.bathSitting, ReactBeat.afterBath] + Trait.allCases.map(Traits.tapClips)
        for plan in plans {
            for clip in plan { XCTAssertNotNil(d[clip], "нет клипа \(clip)") }
        }
    }

    func testFlashReactionsFitHalfToOneAndHalfSeconds() throws {
        let d = try durations()
        let dur: (String) -> Double = { d[$0] ?? 0 }
        // Приоритет ТЗ: гладить, тап, отказ, ванна сидя — короткий отклик.
        var flash: [(String, [String])] = [("pet", ReactBeat.pet), ("refuse", ReactBeat.refuse),
                                           ("bath сидя", ReactBeat.bathSitting)]
        for t in Trait.allCases { flash.append(("tap.\(t.rawValue)", Traits.tapClips(t))) }
        for (name, plan) in flash {
            XCTAssertFalse(plan.isEmpty, name)
            XCTAssertTrue(ReactBeat.fits(plan, weight: .flash, duration: dur),
                          "\(name): \(ReactBeat.length(plan, duration: dur)) с")
        }
        XCTAssertEqual(ReactBeat.weight(of: "pet"), .flash)
        XCTAssertEqual(ReactBeat.weight(of: "tap.calm"), .flash)
        XCTAssertEqual(ReactBeat.weight(of: "feed", ok: false), .flash, "отказ — всегда короткий")
        // Ласка теперь не дольше полутора секунд (была 2,7 с) и не короче минимума наклона к руке (ChoreoPath 1,5 с).
        XCTAssertLessThanOrEqual(ReactBeat.length(ReactBeat.pet, duration: dur), 1.5 + 1e-6)
        XCTAssertGreaterThanOrEqual(ReactBeat.length(ReactBeat.pet, duration: dur), 1.5 - 1e-6)
    }

    func testActivitiesHaveAnEndAndStayShort() throws {
        let d = try durations()
        let dur: (String) -> Double = { d[$0] ?? 0 }
        let feed = meal(ReactBeat.mealChews) + ReactBeat.afterMeal
        let wake = ReactBeat.wakeFromSleep
        let bathOut = ["sit_out"] + ReactBeat.afterBath
        for (kind, plan) in [("feed", feed), ("wake", wake), (Cooking.reactKind, feed)] {
            XCTAssertEqual(ReactBeat.weight(of: kind), .activity, kind)
            XCTAssertTrue(ReactBeat.fits(plan, weight: .activity, duration: dur),
                          "\(kind): \(ReactBeat.length(plan, duration: dur)) с")
        }
        // Еда стала короче прежних 7,7 с, но жуёт больше одного раза — видно, что ест.
        XCTAssertGreaterThan(ReactBeat.mealChews, 1)
        XCTAssertLessThan(ReactBeat.length(meal(ReactBeat.mealChews), duration: dur),
                          ReactBeat.length(meal(6), duration: dur) - 2)
        // Еда кончается эмоцией, а не поднятой головой.
        XCTAssertFalse(ReactBeat.afterMeal.isEmpty)
        XCTAssertEqual(feed.last, ReactBeat.afterMeal.last)
        // Выход из ванны — короткий: встал и отряхнулся.
        XCTAssertTrue(ReactBeat.fits(bathOut, weight: .flash, duration: dur), "\(ReactBeat.length(bathOut, duration: dur))")
        // Окно занятия не короче игры с мячом (ChoreoPath.Play: 6,2 с) — иначе правило врёт про игру.
        XCTAssertGreaterThanOrEqual(ReactBeat.activityMax, 6.2)
    }

    func testReactionsReturnToRest() {
        // Короткий отклик и эмоции после занятия не меняют положения тела — пёс возвращается туда же, где был.
        for plan in [ReactBeat.pet, ReactBeat.refuse, ReactBeat.afterMeal, ReactBeat.bathSitting, ReactBeat.afterBath]
            + Trait.allCases.map(Traits.tapClips) {
            XCTAssertTrue(ReactBeat.stanceClips.isDisjoint(with: plan), "\(plan)")
        }
        // Разбудили: из сна — встал (последним клипом), зевает лёжа, а не стоя посреди подъёма.
        XCTAssertEqual(ReactBeat.wakeFromSleep.first, "sleep_out")
        XCTAssertEqual(ReactBeat.wakeFromSleep.last, "lie_out")
        XCTAssertEqual(ReactBeat.wakeFromSleep.filter { ReactBeat.stanceClips.contains($0) }, ["sleep_out", "lie_out"])
    }

    // MARK: присед и прыжок

    func testNoSpringHopOverSkeletonClips() {
        let kinds = ["play", Habits.reactKind, BlockDuo.reactKind, "tap.playful", "trick.sit", "trick.speak",
                     "pet", "feed", "item", Brush.journalKind, Cooking.reactKind, "wake", "bath", "tap", "tickle"]
        for k in kinds {
            let a = ReactBeat.accent(kind: k, ok: true, skeleton: true)
            XCTAssertEqual(a.hop, 0, "\(k): прыгает клип, не пружина")
            XCTAssertLessThanOrEqual(abs(a.squash), 0.05, "\(k): присед, а не желе")
        }
        XCTAssertEqual(ReactBeat.accent(kind: "pet", ok: true, skeleton: true).squash, ReactBeat.skeletonSquash)
        // Отказ — без толчка у всех.
        for k in kinds {
            XCTAssertEqual(ReactBeat.accent(kind: k, ok: false, skeleton: true), .none, k)
            XCTAssertEqual(ReactBeat.accent(kind: k, ok: false, skeleton: false), .none, k)
        }
        // Заглушка без клипов — как раньше: толчок и есть весь отклик.
        XCTAssertEqual(ReactBeat.accent(kind: "play", ok: true, skeleton: false).hop, ReactBeat.stubHop)
        XCTAssertEqual(ReactBeat.accent(kind: "trick.sit", ok: true, skeleton: false).hop, ReactBeat.stubHopTrick)
        XCTAssertEqual(ReactBeat.accent(kind: "feed", ok: true, skeleton: false).squash, ReactBeat.stubSquash)
    }

    /// Пружина тела после толчков в моменты kicks (с), шаг 1/120 с, 2 с.
    private func run(peak: Float, kicks: [Double]) -> [Float] {
        let dt: Float = 1.0 / 120.0
        var x: Float = 0, v: Float = 0
        var out: [Float] = []
        var pending = kicks
        for i in 0..<240 {
            let t = Double(i) * Double(dt)
            if let k = pending.first, t >= k - 1e-9 {
                pending.removeFirst()
                v = ReactBeat.kick(x: x, v: v, peak: peak)
            }
            (x, v) = SoftSpring.step(x: x, v: v, target: 0, omega: ReactBeat.springOmega, zeta: ReactBeat.springZeta, dt: dt)
            out.append(x)
        }
        return out
    }

    func testSquashIsPrepNotJelly() {
        let p = ReactBeat.skeletonSquash
        let xs = run(peak: p, kicks: [0])
        let lowest = xs.min() ?? 0
        // Доходит до пика быстро (подготовка до 0,15 с) и не дальше пика.
        XCTAssertEqual(lowest, p, accuracy: abs(p) * 0.05)
        let peakAt = Double(xs.firstIndex(of: lowest) ?? 0) / 120
        XCTAssertLessThanOrEqual(peakAt, 0.15)
        // Перелёт вверх — меньше полпроцента роста: глазом не виден, «желе» нет.
        XCTAssertLessThan(xs.max() ?? 0, 0.005)
        // Возврат в покой: к 0,8 с — ноль.
        XCTAssertLessThan(abs(xs[Int(0.8 * 120)]), abs(p) * 0.01)
        XCTAssertLessThan(abs(xs.last ?? 1), 1e-5)
    }

    func testRepeatedTapsDoNotStack() {
        for p in [ReactBeat.skeletonSquash, ReactBeat.stubSquash] {
            // Три нажатия подряд и «барабанная дробь» (каждые 0,03 с полсекунды): пёс не плющится вдвое и втрое
            // и не дёргается — положение непрерывно, глубже одного толчка не уходит.
            let drum = (0..<17).map { Double($0) * 0.03 }
            for kicks in [[0, 0.05, 0.12], [0, 0.3, 0.31], drum] {
                let xs = run(peak: p, kicks: kicks)
                // Запас 3%: толчок на обратном качке пружины (тело чуть выше покоя).
                XCTAssertGreaterThanOrEqual(xs.min() ?? 0, p * 1.03, "наложение толчков \(kicks)")
                var prev: Float = 0
                for x in xs {
                    XCTAssertLessThan(abs(x - prev), abs(p) * 0.4, "рывок между кадрами")
                    prev = x
                }
                XCTAssertLessThan(abs(xs.last ?? 1), abs(p) * 0.01, "вернулся в покой \(kicks)")
            }
        }
        // Правило kick: уже на пике или глубже — скорость не трогаем; в покое — полный толчок;
        // уже идущий более сильный толчок не ослабляем.
        let full = ReactBeat.impulse(peak: -0.1)
        XCTAssertEqual(ReactBeat.kick(x: 0, v: 0, peak: -0.1), full)
        XCTAssertEqual(ReactBeat.kick(x: -0.1, v: 0.3, peak: -0.1), 0.3)
        XCTAssertEqual(ReactBeat.kick(x: -0.12, v: -0.2, peak: -0.1), -0.2)
        XCTAssertEqual(ReactBeat.kick(x: 0, v: full * 2, peak: -0.1), full * 2)
        XCTAssertEqual(ReactBeat.kick(x: -0.05, v: 0, peak: -0.1), ReactBeat.impulse(peak: -0.05), accuracy: 1e-6)
        XCTAssertEqual(ReactBeat.kick(x: 0, v: 0.7, peak: 0), 0.7)
        XCTAssertEqual(ReactBeat.kick(x: 0.01, v: 0, peak: -0.1), full, "с обратного качка — как из покоя")
    }

    func testImpulseReachesPeakForAnyDamping() {
        for zeta: Float in [0.3, 0.55, 0.8, 1] {
            let dt: Float = 1.0 / 480.0
            var x: Float = 0
            var v = ReactBeat.impulse(peak: -0.1, zeta: zeta)
            var lowest: Float = 0
            for _ in 0..<480 {
                (x, v) = SoftSpring.step(x: x, v: v, target: 0, omega: ReactBeat.springOmega, zeta: zeta, dt: dt)
                lowest = min(lowest, x)
            }
            XCTAssertEqual(lowest, -0.1, accuracy: 0.002, "ζ \(zeta)")
        }
        XCTAssertEqual(ReactBeat.impulse(peak: 0), 0)
    }

    // MARK: закрытая кнопка

    func testClosedButtonWaitsForCoreAnswer() {
        XCTAssertTrue(ReactBeat.showsAtOnce(nil), "про действие ничего не известно — показываем сразу")
        XCTAssertTrue(ReactBeat.showsAtOnce(.open))
        for reason in ["cooldown", "asleep", "tired", "bathing", "away", "unwell"] {
            XCTAssertFalse(ReactBeat.showsAtOnce(ActGate(ok: false, reason: reason)), reason)
        }
        // Настоящие кнопки: днём ласка открыта — реакция сразу, как раньше; ночью пёс спит — ждём ядро (отказ).
        let r = Catalog.rules
        let t0: Double = 1_760_000_000
        let probe = SaveFile.fresh(now: t0)
        var day = t0, night = t0
        while PetEngine.petNight(day, r, PetRunner.owner(probe, at: day)) { day += 1800 }
        while !PetEngine.petNight(night, r, PetRunner.owner(probe, at: night)) { night += 1800 }
        func file(_ t: Double) -> SaveFile {
            var f = SaveFile.fresh(now: t)
            for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 60 }
            f.lastSeenT = t
            return f
        }
        let dayGates = NeedHints.gates(file(day), at: day)
        XCTAssertEqual(Set(dayGates.keys), Set(NeedHints.kinds))
        XCTAssertTrue(ReactBeat.showsAtOnce(dayGates["pet"]), "\(String(describing: dayGates["pet"]))")
        for k in NeedHints.kinds {
            XCTAssertEqual(ReactBeat.showsAtOnce(dayGates[k]), dayGates[k]?.ok, k)
        }
        let nightGates = NeedHints.gates(file(night), at: night)
        let closed = NeedHints.kinds.filter { !ReactBeat.showsAtOnce(nightGates[$0]) }
        XCTAssertFalse(closed.isEmpty, "ночью хоть одна кнопка ждёт ядро: \(nightGates)")
    }
}
