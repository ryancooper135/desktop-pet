// Волна 35 M: Шиба во дворе — дома ли он, к какой станции идёт, где стоит; тиканье монет.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

final class YardDogTests: XCTestCase {
    private let rest = SIMD3<Float>(0, 0, -0.45)
    private let spots = [
        YardDogSpot(id: "bones", at: SIMD3(-0.62, 0, -0.95), scale: 1),
        YardDogSpot(id: "porridge", at: SIMD3(0.62, 0, -0.95), scale: 1),
        YardDogSpot(id: "mill", at: SIMD3(1.7, 0, 0.35), scale: 1),
    ]

    func testModeFromPose() {
        XCTAssertEqual(YardDogMode.of(pose: .away, alive: true), .absent, "гуляет или в походе — во дворе нет")
        XCTAssertEqual(YardDogMode.of(pose: .dead, alive: false), .absent)
        XCTAssertEqual(YardDogMode.of(pose: .happy, alive: false), .absent)
        XCTAssertEqual(YardDogMode.of(pose: .sleep, alive: true), .asleep)
        XCTAssertEqual(YardDogMode.of(pose: .nap, alive: true), .asleep)
        for p in Pose.allCases where ![.away, .dead, .sleep, .nap].contains(p) {
            XCTAssertEqual(YardDogMode.of(pose: p, alive: true), .awake, p.rawValue)
        }
    }

    func testEveryStationHasAnAct() {
        for id in YardConfig().stations.map(\.id) {
            let a = YardDogAct.of(station: id)
            XCTAssertNotNil(a, id)
            XCTAssertFalse(a?.clips.loop.isEmpty ?? true, id)
        }
        XCTAssertEqual(Set(YardConfig().stations.compactMap { YardDogAct.of(station: $0.id) }).count, 8,
                       "у каждой станции своё дело")
        XCTAssertNil(YardDogAct.of(station: "window"))
    }

    /// Клипы — только из таблицы Шибы (иначе играть нечего).
    func testClipsAreShibaClips() {
        let known: Set<String> = ["idle", "idle_2", "idle_headlow", "walk", "gallop", "eat", "sit", "lie", "sleep",
                                  "idle_wag", "gallop_jump", "jump_to_idle", "attack", "hit_left", "hit_right",
                                  "death", "sit_in", "sit_out", "lie_in", "lie_out", "sleep_in", "sleep_out",
                                  "happy_wag", "head_tilt", "shake", "hop", "play_bow", "ear_flick", "sniff",
                                  "look_l", "look_r", "yawn", "bark", "pant"]
        var all: [YardDogClips] = YardDogAct.allCases.map(\.clips)
        for ph in [YardDogPhase.rest, .sleep, .walkTo, .walkBack] {
            all.append(YardDogPose(at: .zero, yaw: 0, phase: ph, station: "porridge", act: .watch).clips)
        }
        for c in all {
            for name in c.once + c.loop { XCTAssertTrue(known.contains(name), name) }
        }
    }

    func testMillOnlyAtNight() {
        XCTAssertEqual(YardDogPlan.candidates(spots, night: false).map(\.id), ["bones", "porridge"])
        XCTAssertEqual(YardDogPlan.candidates(spots, night: true).map(\.id), ["bones", "porridge", "mill"])
    }

    /// Примерно половина окон — визит, станции все в ходу, одно и то же окно — один и тот же ответ.
    func testVisitsHalfAndDeterministic() {
        var visits = 0
        var seen: Set<String> = []
        for n in 0..<2000 {
            let v = YardDogPlan.visit(window: n, spots, night: true)
            XCTAssertEqual(v, YardDogPlan.visit(window: n, spots, night: true))
            if let v { visits += 1; seen.insert(v.id) }
        }
        XCTAssertTrue((800...1200).contains(visits), "визитов \(visits) из 2000")
        XCTAssertEqual(seen, ["bones", "porridge", "mill"])
        XCTAssertNil(YardDogPlan.visit(window: 1, [], night: true), "станций нет — отдыхает")
    }

    func testAbsentAndAsleep() {
        XCTAssertNil(YardDogPlan.pose(now: 100, mode: .absent, spots: spots, rest: rest, night: false))
        let p = YardDogPlan.pose(now: 100, mode: .asleep, spots: spots, rest: rest, night: false)
        XCTAssertEqual(p?.phase, .sleep)
        XCTAssertEqual(p?.at, rest)
        XCTAssertEqual(p?.clipKey, "sleep")
    }

    /// Визит по фазам: подход, дело у станции, обратно, отдых; одна станция за раз, без телепортов.
    func testVisitPhasesAreContinuous() throws {
        let n = try XCTUnwrap((0..<200).first { YardDogPlan.visit(window: $0, spots, night: false) != nil })
        let s = try XCTUnwrap(YardDogPlan.visit(window: n, spots, night: false))
        let start = Double(n) * YardDogPlan.slot
        var phases: [YardDogPhase] = []
        var last: SIMD3<Float>?
        var t = start
        while t < start + YardDogPlan.slot - 0.05 {
            let p = try XCTUnwrap(YardDogPlan.pose(now: t, mode: .awake, spots: spots, rest: rest, night: false))
            if phases.last != p.phase { phases.append(p.phase) }
            if p.phase != .rest { XCTAssertEqual(p.station, s.id) }
            if let l = last {
                let d = p.at - l
                XCTAssertLessThan((d.x * d.x + d.z * d.z).squareRoot(), 0.05, "шаг за 0,1 с — без прыжков")
            }
            last = p.at
            t += 0.1
        }
        XCTAssertEqual(phases, [.walkTo, .act, .walkBack, .rest])
        // К концу окна — снова на месте отдыха.
        let end = YardDogPlan.pose(now: start + YardDogPlan.slot - 0.01, mode: .awake, spots: spots, rest: rest,
                                   night: false)
        XCTAssertEqual(end?.at, rest)
    }

    func testStandNextToStationFacingIt() {
        let s = spots[0]
        let p = YardDogPlan.stand(s, rest: rest, dogScale: 0.75)
        let d = SIMD2(p.x - s.at.x, p.z - s.at.z)
        let dist = (d.x * d.x + d.y * d.y).squareRoot()
        XCTAssertEqual(dist, 0.25 + 0.15, accuracy: 1e-4)
        let yaw = YardDogPlan.actYaw(.dig, s, p, t: 0)
        // Смотрит на станцию: из точки p в сторону центра.
        XCTAssertEqual(sin(yaw), (s.at.x - p.x) / dist, accuracy: 1e-4)
        XCTAssertEqual(cos(yaw), (s.at.z - p.z) / dist, accuracy: 1e-4)
        // Сушилка на подоконнике, пёс на земле — встаёт под окном.
        let sill = YardDogSpot(id: "dryer", at: SIMD3(0.12, 0.5, -1.56), scale: 0.6)
        XCTAssertEqual(YardDogPlan.stand(sill, rest: rest, dogScale: 0.75), SIMD3(0.12, 0, -1.26))
    }

    func testForcedStaysAtStation() {
        for t in [0.0, 13, 27.5, 39.9] {
            let p = YardDogPlan.pose(now: t, mode: .awake, spots: spots, rest: rest, night: false, forced: "porridge")
            XCTAssertEqual(p?.phase, .act)
            XCTAssertEqual(p?.station, "porridge")
            XCTAssertEqual(p?.clipKey, "act.porridge")
        }
        // Неизвестная или не поставленная станция — обычный план.
        let p = YardDogPlan.pose(now: 5, mode: .awake, spots: spots, rest: rest, night: false, forced: "pies")
        XCTAssertNotEqual(p?.station, "pies")
    }

    func testRunGoesAlongTheBelt() {
        let s = YardDogSpot(id: "sausage", at: SIMD3(1.7, 0, -0.75), scale: 1)
        let p = YardDogPlan.stand(s, rest: rest, dogScale: 1)
        XCTAssertEqual(YardDogPlan.actSpot(.run, s, p, t: 0, dogScale: 1), p, "начинает из точки у станции")
        let a = YardDogPlan.actSpot(.run, s, p, t: 1.2, dogScale: 1)
        let b = YardDogPlan.actSpot(.run, s, p, t: 3.6, dogScale: 1)
        XCTAssertEqual(a.x, p.x + 0.22, accuracy: 1e-4)
        XCTAssertEqual(b.x, p.x - 0.22, accuracy: 1e-4)
        XCTAssertEqual(a.z, b.z)
        XCTAssertEqual(YardDogPlan.actYaw(.run, s, p, t: 1), .pi / 2)
        XCTAssertEqual(YardDogPlan.actYaw(.run, s, p, t: 3), -.pi / 2)
    }

    // MARK: тиканье

    func testAudibleAtMostTwo() {
        let rates: [(id: String, rate: Double)] = [("dryer", 8), ("bones", 13), ("porridge", 9)]
        XCTAssertEqual(YardTick.audible(rates, dogAt: nil), ["bones", "porridge"])
        XCTAssertEqual(YardTick.audible(rates, dogAt: "dryer"), ["dryer", "bones"], "пёс у станции — её слышно")
        XCTAssertEqual(YardTick.audible(rates, dogAt: "bones"), ["bones", "porridge"])
        XCTAssertEqual(YardTick.audible(rates, dogAt: "mill"), ["bones", "porridge"], "станции нет — не считаем")
        XCTAssertEqual(YardTick.audible([("dryer", 4)], dogAt: nil), ["dryer"])
        XCTAssertEqual(YardTick.audible([], dogAt: nil), [])
    }

    func testTickCountsOncePerCycle() {
        for id in YardConfig().stations.map(\.id) {
            let c = YardTick.cycle(id, night: false, brushed: false)
            XCTAssertNotNil(c, id)
        }
        // Сушилка: цикл 6 с, сухарик в корзинке на 0,72 цикла (4,32 с).
        XCTAssertEqual(YardTick.count("dryer", clock: 4.3, night: false, brushed: false), -1)
        XCTAssertEqual(YardTick.count("dryer", clock: 4.33, night: false, brushed: false), 0)
        XCTAssertEqual(YardTick.count("dryer", clock: 10.33, night: false, brushed: false), 1)
        XCTAssertEqual(YardTick.cycle("mill", night: true, brushed: false)?.period, 2)
        XCTAssertEqual(YardTick.cycle("spinner", night: false, brushed: true)?.period, 3)
        XCTAssertNil(YardTick.count("window", clock: 3, night: false, brushed: false))
    }
}
