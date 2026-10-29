// Волна 46 R: плавность походки (Gait.swift, IdleRoute, DogIdle.homeTrip). Шаг с разгоном без скачков скорости,
// темп клипа walk под скорость лап, поворот на месте с переступанием, перебитое дело — встать и дойти домой
// целым числом шагов, а не съехать боком за полсекунды. Гоняется и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private typealias P = RoomPlan.P
private typealias K = RoomPlan.Keep

/// Номинальные длины клипов Шибы, с (как в AutonomyTests).
private let clipLen: [String: Double] = [
    "idle": 3.33, "walk": 1.08, "sit_in": 0.75, "sit": 3.0, "sit_out": 0.58, "lie_in": 1.08, "lie": 3.0,
    "lie_out": 0.92, "shake": 0.92, "hop": 0.5, "play_bow": 1.42, "idle_wag": 2.0, "head_tilt": 1.21,
    "sniff": 1.5, "look_l": 1.58, "look_r": 1.58, "yawn": 1.79,
]
private func len(_ s: String) -> Double { clipLen[s] ?? 1 }

private func scene() -> IdleScene {
    var n: [Need: Double] = [:]
    for k in Need.allCases { n[k] = 90 }
    return IdleScene(petId: "gait-pet", name: "Шиба", pose: .idle, needs: n,
                     levels: RoomPlan.Levels(bath: 1, bed: 1, kitchen: 1), traits: [], quiet: false, alive: true,
                     tzOffsetMin: 0)
}

private func plan(_ c: IdleChore, _ s: DogIdle.Stance = .stand, weather: WeatherKind = .clear) -> IdlePlan {
    DogIdle.plan(c, scene(), stance: s, weather: weather, roll: 0.5)!
}

private func allPlans() -> [IdlePlan] {
    var out: [IdlePlan] = []
    for s in [DogIdle.Stance.stand, .sit, .lie] {
        for c in IdleChore.allCases {
            if let p = DogIdle.plan(c, scene(), stance: s, weather: .rain, roll: 0.5) { out.append(p) }
        }
    }
    return out
}

final class GaitTests: XCTestCase {
    // MARK: шаг

    func testTravelEndsAndCruise() {
        for T in [0.2, 0.7, 1.0, 3.0] {
            XCTAssertEqual(Gait.travel(0, T), 0)
            XCTAssertEqual(Gait.travel(T, T), 1)
            XCTAssertEqual(Gait.travel(-1, T), 0)
            XCTAssertEqual(Gait.travel(T + 1, T), 1)
            var prev: Float = 0, prevV: Float = 0, peak: Float = 0
            let dt = 1.0 / 240
            let r = min(Gait.ramp, T / 2)
            let cruise = Float(1 / (T - r))
            // Скорость без скачков: ускорение не больше cruise / r (равноускоренный разгон).
            let dv = cruise / Float(r) * Float(dt) * 1.2 + 1e-3
            var t = dt
            while t <= T + 1e-9 {
                let s = Gait.travel(t, T)
                XCTAssertGreaterThanOrEqual(s, prev - 1e-6, "T=\(T) t=\(t) назад")
                let v = (s - prev) / Float(dt)
                XCTAssertLessThan(abs(v - prevV), dv, "T=\(T) t=\(t) скачок скорости")
                peak = max(peak, v)
                prev = s
                prevV = v
                t += dt
            }
            XCTAssertEqual(peak, cruise, accuracy: dv, "T=\(T) ровный шаг")
        }
        XCTAssertEqual(Gait.travel(0, 0), 1, "нулевой путь — сразу на месте")
        // Ровный участок: доля линейна (лапы в такт клипу), а не smoothstep с пиком 1,5 средней.
        let T = 3.0
        let a = Gait.travel(1.0, T), b = Gait.travel(2.0, T)
        XCTAssertEqual(b - a, Float(1 / (T - Gait.ramp)), accuracy: 1e-5)
    }

    func testWalkTimeMatchesSpeed() {
        XCTAssertEqual(Gait.walkTime(0, speed: 0.4), 0)
        // На ровном участке скорость тела ровно speed.
        let d: Float = 1.2, v: Float = 0.4
        let T = Gait.walkTime(d, speed: v)
        XCTAssertEqual(Float(1 / (T - Gait.ramp)) * d, v, accuracy: 1e-5)
    }

    func testSpeedAndRateUnderSize() {
        XCTAssertEqual(Gait.speed(size: 1), Gait.nominal)
        XCTAssertEqual(Gait.speed(size: 0.3), Gait.nominal * 0.55, accuracy: 1e-6, "крошка не ползёт")
        XCTAssertEqual(Gait.speed(size: 2), Gait.nominal * 1.25, accuracy: 1e-6)
        XCTAssertEqual(Gait.rate(foot: Gait.nominal, size: 1), 1, accuracy: 1e-6)
        XCTAssertEqual(Gait.rate(foot: Gait.speed(size: 0.7), size: 0.7), 1, accuracy: 1e-6)
        XCTAssertEqual(Gait.rate(foot: 0, size: 1), Gait.minRate)
        XCTAssertEqual(Gait.rate(foot: 10, size: 1), Gait.maxRate)
        XCTAssertEqual(Gait.pivotTime(0.005), 0)
        XCTAssertEqual(Gait.pivotTime(0.3), Gait.minPivot)
        XCTAssertEqual(Gait.pivotTime(3), 1.5, accuracy: 1e-6)
    }

    // MARK: положение

    func testBackClipsReachTarget() {
        let all: [DogIdle.Stance] = [.stand, .sit, .lie]
        for a in all {
            for b in all {
                let clips = Gait.backClips(from: a, to: b)
                let end = clips.reduce(a) { Gait.stance(after: $1, from: $0) }
                XCTAssertEqual(end, b, "\(a)→\(b): \(clips)")
                if a == b { XCTAssertEqual(clips, []) }
                XCTAssertTrue(clips.allSatisfy { clipLen[$0] != nil }, "только существующие клипы")
            }
        }
    }

    func testScratchSitInterruptedSitsBack() {
        let p = plan(.scratch, .sit)
        XCTAssertEqual(p.home, .sit)
        let r = IdleRoute.make(p, act: p.act(len))
        let c = DogIdle.cues(p, r, homeLoop: "sit", len: len)
        // Посреди отряхивания пёс стоит — раньше перебой оставлял его стоять в позе «сидит».
        let mid = len("sit_out") + len("shake") / 2
        let s = DogIdle.stance(at: mid, c, home: p.home, len: len)
        XCTAssertEqual(s, .stand)
        XCTAssertEqual(Gait.backClips(from: s, to: p.home), ["sit_in"])
        XCTAssertEqual(DogIdle.stance(at: 0.1, c, home: p.home, len: len), .sit)
        XCTAssertEqual(DogIdle.stance(at: r.homeAt, c, home: p.home, len: len), .sit)
    }

    func testYawnStandsUntilLying() {
        let p = plan(.yawn)
        let r = IdleRoute.make(p, act: p.act(len))
        let c = DogIdle.cues(p, r, homeLoop: "idle", len: len)
        XCTAssertEqual(DogIdle.stance(at: 0.5, c, home: .stand, len: len), .stand, "зевает стоя — вставать не из чего")
        let lying = len("yawn") + len("lie_in") * 0.6
        XCTAssertEqual(DogIdle.stance(at: lying, c, home: .stand, len: len), .lie)
        XCTAssertEqual(DogIdle.stance(at: r.homeAt + 0.1, c, home: .stand, len: len), .stand, "встал после lie_out")
    }

    // MARK: повороты на месте

    func testTurnInPlaceSteps() {
        for c in [IdleChore.toy, .rug] {
            let p = plan(c)
            let r = IdleRoute.make(p, act: p.act(len))
            XCTAssertFalse(r.moves)
            let cues = DogIdle.cues(p, r, homeLoop: "idle", len: len)
            XCTAssertEqual(cues.first?.loop, "walk", "\(c): поворачивается, переступая")
            XCTAssertEqual(cues.first?.at, 0)
            XCTAssertTrue(cues.contains { $0.at == r.leaveAt && $0.loop == "walk" }, "\(c): обратно тоже")
            XCTAssertEqual(cues.last?.loop, "idle")
            // Поворот на месте не быстрее Gait.pivotRate.
            XCTAssertGreaterThanOrEqual(r.turnOut, Double(abs(r.yFace - r.y0) / Gait.pivotRate) - 1e-9)
            XCTAssertGreaterThanOrEqual(r.turnOut, Gait.minPivot)
        }
        // Почесаться и зевнуть — без поворота, без шагов.
        for c in [IdleChore.scratch, .yawn] {
            let p = plan(c)
            let cues = DogIdle.cues(p, IdleRoute.make(p, act: p.act(len)), homeLoop: "idle", len: len)
            XCTAssertFalse(cues.contains { $0.loop == "walk" }, "\(c)")
        }
    }

    func testFootSpeedDrivesWalkRate() {
        for size: Float in [1, 0.7, 0.45] {
            let p = plan(.window)
            let r = IdleRoute.make(p, act: p.act(len), size: size)
            // На ровном участке лапы идут ровно со скоростью тела; у взрослого и подростка темп 1.
            let u = r.go / 2
            XCTAssertEqual(r.footSpeed(at: u), Gait.speed(size: size), accuracy: 0.01 * Gait.nominal, "size=\(size)")
            let rate = Gait.rate(foot: r.footSpeed(at: u), size: size)
            if size >= 0.55 { XCTAssertEqual(rate, 1, accuracy: 0.03, "size=\(size)") }
            XCTAssertLessThanOrEqual(rate, Gait.maxRate)
            // Поворот у мячика: лапы переступают, темп не ниже minRate.
            let toy = IdleRoute.make(plan(.toy), act: 3, size: size)
            XCTAssertGreaterThan(toy.footSpeed(at: toy.turnOut / 2), 0, "size=\(size)")
        }
    }

    // MARK: перебитое дело — домой пешком

    /// Точки, где дело могут перебить: по пути туда, у дела, по пути обратно.
    private func stops(_ r: IdleRoute) -> [Double] {
        [r.go * 0.3, r.go * 0.7, r.arriveAt + 0.2, r.leaveAt + (r.homeAt - r.leaveAt) * 0.2,
         r.leaveAt + (r.homeAt - r.leaveAt) * 0.6, r.homeAt - 0.05]
    }

    func testHomeTripFromAnywhere() {
        let walk = len("walk")
        for size: Float in [1, 0.7, 0.45] {
            for p in allPlans() {
                let r = IdleRoute.make(p, act: p.act(len), size: size)
                let cues = DogIdle.cues(p, r, homeLoop: "idle", len: len)
                for u in stops(r) where u > 0 {
                    let at = r.pose(at: u)
                    let stance = DogIdle.stance(at: u, cues, home: p.home, len: len)
                    let trip = DogIdle.homeTrip(from: at.p, yaw: at.yaw, stance: stance, home: p.home, size: size,
                                                chore: p.chore, len: len)
                    let h = trip.route
                    let tag = "\(p.chore) size=\(size) u=\(u)"
                    // Начинает там же, где стоит, и в том же повороте — без скачка.
                    let a = h.pose(at: 0)
                    XCTAssertLessThan((a.p - at.p).length, 0.005, tag)
                    XCTAssertEqual(a.yaw, at.yaw, accuracy: 1e-4, tag)
                    // Дома ровно в 3/4.
                    let z = h.pose(at: h.homeAt)
                    XCTAssertEqual(z.p, P(0, 0), tag)
                    XCTAssertEqual(sin(z.yaw), sin(K.yaw3q), accuracy: 1e-4, tag)
                    XCTAssertEqual(cos(z.yaw), cos(K.yaw3q), accuracy: 1e-4, tag)
                    // Клипы по разу совпадают с путём: встать — шаги целыми циклами — сесть/лечь, как стоял.
                    let toStand = Gait.backClips(from: stance, to: .stand)
                    if trip.cycles > 0 {
                        XCTAssertEqual(trip.steps, toStand + Array(repeating: "walk", count: trip.cycles)
                                       + Gait.backClips(from: .stand, to: p.home), tag)
                        XCTAssertEqual(h.act, toStand.reduce(0.0) { $0 + len($1) }, accuracy: 1e-9, tag)
                        XCTAssertEqual(h.back, Double(trip.cycles) * walk, accuracy: 0.011 * walk, tag)
                    } else {
                        XCTAssertEqual(trip.steps, Gait.backClips(from: stance, to: p.home), tag)
                        XCTAssertLessThan((at.p).length, Gait.stepMin + 1e-4, tag)
                    }
                    var prev = a
                    var v = 0.0
                    let step = 1.0 / 60
                    while v <= h.homeAt + 0.2 {
                        let c = h.pose(at: v)
                        XCTAssertLessThan((c.p - prev.p).length, 0.02, "\(tag) v=\(v) скачок")
                        XCTAssertLessThan(abs(c.yaw - prev.yaw), 0.12, "\(tag) v=\(v) рывок поворота")
                        // Не быстрее шага клипа при темпе 1 (лапы не скользят): разгон, ровный шаг, торможение.
                        // В развороте у края площадки центр сдвигается под поворот (clamp) — там предел темпа
                        // клипа (Gait.maxRate): сцена подгоняет его по footSpeed.
                        let cap: Float = v < h.turnBack ? Gait.maxRate : 1.1
                        XCTAssertLessThanOrEqual((c.p - prev.p).length / Float(step),
                                                 Gait.nominal * size * cap + 0.01, "\(tag) v=\(v) скользит")
                        if p.chore != .bowl {
                            XCTAssertFalse(IdleRoute.covers(c.p, c.yaw, size: size, K.bowlHome, pad: K.bowlRadius),
                                           "\(tag) v=\(v) наступил на миску")
                        }
                        if p.chore != .toy {
                            XCTAssertFalse(IdleRoute.covers(c.p, c.yaw, size: size, K.ballHome, pad: K.ballRadius),
                                           "\(tag) v=\(v) задел мяч")
                        }
                        prev = c
                        v += step
                    }
                }
            }
        }
    }

    func testHomeTripAtHomeIsJustStance() {
        let t = DogIdle.homeTrip(from: P(0, 0), yaw: K.yaw3q, stance: .lie, home: .stand, size: 1, chore: .rug,
                                 len: len)
        XCTAssertEqual(t.steps, ["lie_out"])
        XCTAssertEqual(t.cycles, 0)
        XCTAssertEqual(t.route.homeAt, 0)
        let same = DogIdle.homeTrip(from: P(0, 0), yaw: K.yaw3q, stance: .stand, home: .stand, size: 1, chore: .toy,
                                    len: len)
        XCTAssertEqual(same.steps, [])
        // Чуть сдвинут — доезжает за полсекунды, а не за кадр.
        let nudge = DogIdle.homeTrip(from: P(0.02, 0), yaw: K.yaw3q + 0.05, stance: .stand, home: .stand, size: 1,
                                     chore: .toy, len: len)
        XCTAssertEqual(nudge.cycles, 0)
        XCTAssertGreaterThanOrEqual(nudge.route.homeAt, Gait.minPivot)
    }

    func testFittedKeepsEnds() {
        let p = plan(.window)
        let r = IdleRoute.make(p, act: p.act(len))
        let h = IdleRoute.home(from: r.spot, yaw: r.yFace, hold: 0.5, size: 1, chore: .window)
        let f = h.fitted(back: h.back + 0.4)
        XCTAssertEqual(f.back, h.back + 0.4, accuracy: 1e-9)
        XCTAssertEqual(f.pose(at: 0).p, h.pose(at: 0).p)
        XCTAssertEqual(f.pose(at: f.homeAt).p, P(0, 0))
        XCTAssertEqual(h.fitted(back: h.back - 1), h, "короче не ужимает")
    }
}
