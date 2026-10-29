// Волна 44 M: пёс сам по себе (DogIdle.swift). Выбор дела детерминирован по (petId, слот), тихо ночью и пока
// хозяин спит, поза ограничивает дела, веса двигают нужды, купленное, погода, характер и экономия заряда;
// путь начинается и кончается дома ровно в 3/4, непрерывен, в кадре, не задевает миску и мяч, морда у вещи.
// Гоняется и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private typealias P = RoomPlan.P
private typealias K = RoomPlan.Keep

/// Утро буднего дня по UTC (пояс сцены — 0): 08:53.
private let iT0: Double = 1_760_000_000

/// Номинальные длины клипов Шибы, с.
private let clipLen: [String: Double] = [
    "idle": 3.33, "idle_2": 3.33, "idle_headlow": 4.0, "walk": 1.08, "sit_in": 0.75, "sit": 3.0, "sit_out": 0.58,
    "lie_in": 1.08, "lie": 3.0, "lie_out": 0.92, "shake": 0.92, "hop": 0.5, "play_bow": 1.42, "idle_wag": 2.0,
    "head_tilt": 1.21, "ear_flick": 0.42, "sniff": 1.5, "look_l": 1.58, "look_r": 1.58, "yawn": 1.79,
    "happy_wag": 1.5, "pant": 3.0,
]
private func len(_ s: String) -> Double { clipLen[s] ?? 1 }

private func scene(pose: Pose = .idle, needs: [Need: Double] = [:], levels: RoomPlan.Levels = .init(),
                   traits: [Trait] = [], name: String = "Шиба", id: String = "idle-pet-1") -> IdleScene {
    var n: [Need: Double] = [:]
    for k in Need.allCases { n[k] = 90 }
    for (k, v) in needs { n[k] = v }
    return IdleScene(petId: id, name: name, pose: pose, needs: n, levels: levels, traits: traits,
                     quiet: false, alive: true, tzOffsetMin: 0)
}

/// Дела за count слотов подряд (nil — слот пустой).
private func slots(_ s: IdleScene, count: Int = 2000, weather: WeatherKind = .clear, season: Season = .autumn,
                 lowPower: Bool = false, from t0: Double = iT0) -> [IdlePlan?] {
    (0..<count).map { DogIdle.decide(s, at: t0 + Double($0) * DogIdle.slotSec, weather: weather, season: season,
                                     lowPower: lowPower) }
}

private func tally(_ plans: [IdlePlan?]) -> [IdleChore: Int] {
    var out: [IdleChore: Int] = [:]
    for p in plans.compactMap({ $0 }) { out[p.chore, default: 0] += 1 }
    return out
}

/// Все дела, какие бывают: каждая поза-стойка, кухня и ванна, дождь и снег.
private func allPlans() -> [IdlePlan] {
    var out: [IdlePlan] = []
    let lv = RoomPlan.Levels(bath: 1, bed: 1, kitchen: 1)
    for weather in [WeatherKind.clear, .rain, .snow] {
        for stance in [DogIdle.Stance.stand, .sit, .lie] {
            for c in IdleChore.allCases {
                for (food, clean) in [(90.0, 90.0), (30.0, 90.0), (90.0, 30.0)] {
                    let s = scene(needs: [.food: food, .clean: clean], levels: lv)
                    for roll in [0.0, 0.7, 1.0] {
                        if let p = DogIdle.plan(c, s, stance: stance, weather: weather, roll: roll) { out.append(p) }
                    }
                }
            }
        }
    }
    return out
}

/// Пятно пса размера size: содержит ли точку q с запасом pad (как RoomPlan.petCovers, но под размер).
private func covers(_ p: P, _ yaw: Float, size: Float, _ q: P, pad: Float) -> Bool {
    let d = q - p
    let along = d.x * sin(yaw) + d.z * cos(yaw)
    let across = d.x * cos(yaw) - d.z * sin(yaw)
    return abs(along) <= K.petHalfLength * size + pad && abs(across) <= K.petHalfWidth * size + pad
}

final class AutonomyTests: XCTestCase {

    override func setUp() {
        super.setUp()
        DogIdle.enabled = true
    }

    override func tearDown() {
        Clock.zoneOverride = nil
        DogIdle.enabled = true
        super.tearDown()
    }

    // MARK: выбор

    func testSameSlotSameChoice() {
        let s = scene()
        let a = slots(s, count: 300), b = slots(s, count: 300)
        XCTAssertEqual(a, b)
        let other = slots(scene(id: "idle-pet-2"), count: 300)
        XCTAssertNotEqual(a, other, "у другого пса своя жизнь")
        // Внутри слота решение одно и то же.
        let t = iT0 + 17 * DogIdle.slotSec
        XCTAssertEqual(DogIdle.decide(s, at: t + 1, weather: .clear, season: .autumn),
                       DogIdle.decide(s, at: t + DogIdle.slotSec - 1, weather: .clear, season: .autumn))
    }

    func testAboutHalfOfSlots() {
        let n = slots(scene()).compactMap { $0 }.count
        XCTAssertGreaterThan(n, 800)
        XCTAssertLessThan(n, 1200)
        XCTAssertEqual(Set(tally(slots(scene())).keys), Set(IdleChore.allCases).subtracting([.sniff]),
                       "без кухни и ванны обнюхивать нечего, остальное бывает")
    }

    func testQuietDeadDisabled() {
        var s = scene()
        s.quiet = true
        XCTAssertTrue(slots(s, count: 300).allSatisfy { $0 == nil }, "ночью и пока хозяин спит — тихо")
        s = scene()
        s.alive = false
        XCTAssertTrue(slots(s, count: 300).allSatisfy { $0 == nil })
        DogIdle.enabled = false
        XCTAssertTrue(slots(scene(), count: 300).allSatisfy { $0 == nil })
    }

    func testPoseLimits() {
        for pose in [Pose.eating, .loved, .sleep, .nap, .bath, .critical, .dead, .away] {
            XCTAssertTrue(slots(scene(pose: pose), count: 300).allSatisfy { $0 == nil }, "\(pose)")
        }
        XCTAssertEqual(Set(tally(slots(scene(pose: .dirty))).keys), [.scratch])
        XCTAssertEqual(Set(tally(slots(scene(pose: .tired))).keys), [.yawn])
        XCTAssertEqual(Set(tally(slots(scene(pose: .lonely))).keys), [.window])
        XCTAssertTrue(Set(tally(slots(scene(pose: .hungry))).keys).isSubset(of: [.bowl, .window, .sniff]))
        // Грязный сидит: отряхивается, встав и сев обратно; устал лежит: зевает лёжа.
        let dirty = slots(scene(pose: .dirty)).compactMap { $0 }
        XCTAssertTrue(dirty.allSatisfy { $0.steps == ["sit_out", "shake", "sit_in"] })
        let tired = slots(scene(pose: .tired)).compactMap { $0 }
        XCTAssertTrue(tired.allSatisfy { $0.steps == ["yawn"] && $0.hold == nil })
        // Поза сцены может отставать от снимка: решает то, что играет.
        let t = (0..<500).map { iT0 + Double($0) * DogIdle.slotSec }
        XCTAssertTrue(t.compactMap { DogIdle.decide(scene(), pose: .dirty, at: $0, weather: .clear, season: .autumn) }
            .allSatisfy { $0.chore == .scratch })
    }

    func testSniffOnlyBought() {
        let none = tally(slots(scene()))
        XCTAssertNil(none[.sniff])
        let k = slots(scene(levels: .init(kitchen: 1))).compactMap { $0 }.filter { $0.chore == .sniff }
        XCTAssertFalse(k.isEmpty)
        XCTAssertTrue(k.allSatisfy { $0.line.hasSuffix("кухню") })
        let b = slots(scene(levels: .init(bath: 2))).compactMap { $0 }.filter { $0.chore == .sniff }
        XCTAssertFalse(b.isEmpty)
        XCTAssertTrue(b.allSatisfy { $0.line.hasSuffix("ванную") })
        // Голоден — к кухне, грязный — к ванне.
        let both = RoomPlan.Levels(bath: 1, kitchen: 1)
        let hungry = slots(scene(needs: [.food: 30], levels: both)).compactMap { $0 }.filter { $0.chore == .sniff }
        XCTAssertTrue(hungry.allSatisfy { $0.line.hasSuffix("кухню") })
        let dirty = slots(scene(needs: [.clean: 30], levels: both)).compactMap { $0 }.filter { $0.chore == .sniff }
        XCTAssertTrue(dirty.allSatisfy { $0.line.hasSuffix("ванную") })
    }

    func testWeightsFollowNeedsWeatherTraits() {
        let base = tally(slots(scene()))
        XCTAssertGreaterThan(tally(slots(scene(needs: [.food: 30])))[.bowl, default: 0], base[.bowl, default: 0] * 3 / 2)
        XCTAssertGreaterThan(tally(slots(scene(needs: [.energy: 20])))[.yawn, default: 0], base[.yawn, default: 0] * 2)
        XCTAssertGreaterThan(tally(slots(scene(needs: [.clean: 30])))[.scratch, default: 0], base[.scratch, default: 0] * 3 / 2)
        XCTAssertGreaterThan(tally(slots(scene(), weather: .rain))[.window, default: 0], base[.window, default: 0] * 3 / 2)
        XCTAssertGreaterThan(tally(slots(scene(traits: [.playful])))[.toy, default: 0], base[.toy, default: 0] * 3 / 2)
        XCTAssertGreaterThan(tally(slots(scene(traits: [.calm])))[.rug, default: 0], base[.rug, default: 0] * 3 / 2)
        XCTAssertGreaterThan(tally(slots(scene(traits: [.independent])))[.window, default: 0], base[.window, default: 0])
        // Вечером зевает чаще.
        let evening = iT0 + 12 * 3600 - 53 * 60   // 20:00 UTC
        XCTAssertGreaterThan(tally(slots(scene(), count: 300, from: evening))[.yawn, default: 0],
                             tally(slots(scene(), count: 300))[.yawn, default: 0])
        // Прошлое дело — реже.
        let s = scene()
        var same = 0, sameAfter = 0
        for i in 0..<2000 {
            let t = iT0 + Double(i) * DogIdle.slotSec
            if DogIdle.decide(s, at: t, weather: .clear, season: .autumn)?.chore == .window { same += 1 }
            if DogIdle.decide(s, at: t, weather: .clear, season: .autumn, last: .window)?.chore == .window { sameAfter += 1 }
        }
        XCTAssertLessThan(sameAfter, same)
    }

    func testLowPowerInPlaceAndRarer() {
        let plans = slots(scene(), lowPower: true).compactMap { $0 }
        XCTAssertTrue(plans.allSatisfy { $0.chore.inPlace && $0.spot == P(0, 0) })
        XCTAssertLessThan(plans.count, 700)
        XCTAssertFalse(plans.isEmpty)
        XCTAssertTrue(slots(scene(pose: .lonely), count: 300, lowPower: true).allSatisfy { $0 == nil })
    }

    func testLinesShortWithName() {
        for p in allPlans() {
            XCTAssertTrue(p.line.hasPrefix("Шиба "), p.line)
            XCTAssertLessThanOrEqual(p.line.count, 48, p.line)
        }
        let p = DogIdle.plan(.yawn, scene(name: ""), stance: .stand, weather: .clear, roll: 0)
        XCTAssertEqual(p?.line, "Пёс зевает")
        XCTAssertEqual(DogIdle.plan(.window, scene(), stance: .stand, weather: .rain, roll: 0)?.line,
                       "Шиба смотрит в окно — там дождь")
        XCTAssertEqual(DogIdle.plan(.rug, scene(levels: .init(bed: 1)), stance: .stand, weather: .clear, roll: 0)?.line,
                       "Шиба валяется на лежанке")
    }

    func testOnlyKnownClips() {
        for p in allPlans() {
            for c in p.clips { XCTAssertNotNil(clipLen[c], "\(p.chore): \(c)") }
        }
    }

    func testSceneQuietAtNight() {
        Clock.zoneOverride = TimeZone(identifier: "UTC")
        let noon = (iT0 / 86400).rounded(.down) * 86400 + 12 * 3600
        var f = SaveFile.fresh(now: noon)
        f.petId = "idle-pet-1"
        let day = DogIdle.scene(f, name: "Шиба", pose: .idle, needs: [:], alive: true, levels: .init(), traits: [],
                                at: noon)
        XCTAssertFalse(day.quiet)
        let night = DogIdle.scene(f, name: "Шиба", pose: .idle, needs: [:], alive: true, levels: .init(), traits: [],
                                  at: noon + 15 * 3600)
        XCTAssertTrue(night.quiet, "в 3 часа ночи хозяин спит")
        XCTAssertTrue(slots(night, count: 200, from: noon + 15 * 3600).allSatisfy { $0 == nil })
    }

    // MARK: путь

    func testRouteHomeToHome() {
        for size: Float in [1, 0.7, 0.45] {
            for p in allPlans() {
                let r = IdleRoute.make(p, act: p.act(len), size: size)
                let a = r.pose(at: 0), z = r.pose(at: r.homeAt), after = r.pose(at: r.homeAt + 5)
                XCTAssertEqual(a.p, P(0, 0), "\(p.chore)")
                XCTAssertEqual(a.yaw, K.yaw3q, accuracy: 1e-5, "\(p.chore)")
                XCTAssertEqual(z.p, P(0, 0), "\(p.chore)")
                // Дома ровно в 3/4 — с точностью до полного оборота (сцена видит тот же поворот).
                for y in [z.yaw, after.yaw] {
                    XCTAssertEqual(sin(y), sin(K.yaw3q), accuracy: 1e-5, "\(p.chore) дома ровно в 3/4")
                    XCTAssertEqual(cos(y), cos(K.yaw3q), accuracy: 1e-5, "\(p.chore) дома ровно в 3/4")
                    XCTAssertLessThan(abs(y - K.yaw3q), 2 * .pi + 0.01, "\(p.chore) лишний оборот")
                }
                XCTAssertEqual(r.moves, !p.chore.inPlace && p.chore != .toy && p.chore != .rug, "\(p.chore)")
                XCTAssertLessThan(r.homeAt, 40, "дело короче слота")
                if r.moves {
                    // Пока идёт — на месте ровно spot, мордой к делу.
                    let at = r.pose(at: r.arriveAt + 0.01)
                    XCTAssertEqual(at.p.x, r.spot.x, accuracy: 1e-3)
                    XCTAssertEqual(at.p.z, r.spot.z, accuracy: 1e-3)
                    XCTAssertEqual(at.yaw, r.yFace, accuracy: 1e-4)
                    XCTAssertEqual(sin(r.yFace), sin(p.face), accuracy: 1e-4)
                    XCTAssertEqual(cos(r.yFace), cos(p.face), accuracy: 1e-4)
                }
            }
        }
    }

    func testRouteSmoothAndInFrame() {
        let a = RoomPlan.playArea
        for size: Float in [1, 0.7, 0.45] {
            for p in allPlans() {
                let r = IdleRoute.make(p, act: p.act(len), size: size)
                var prev = r.pose(at: 0)
                var u = 0.0
                while u <= r.homeAt + 0.5 {
                    let c = r.pose(at: u)
                    XCTAssertLessThan((c.p - prev.p).length, 0.02, "\(p.chore) u=\(u) скачок")
                    XCTAssertLessThan(abs(c.yaw - prev.yaw), 0.12, "\(p.chore) u=\(u) рывок поворота")
                    XCTAssertGreaterThanOrEqual(c.p.z, a.farZ - 1e-4)
                    XCTAssertLessThanOrEqual(c.p.z, a.nearZ + 1e-4)
                    let x = a.xRange(c.p.z), reach = IdleRoute.reach(c.yaw, size: size)
                    XCTAssertGreaterThanOrEqual(c.p.x - reach, x.min - 0.03, "\(p.chore) u=\(u) за левым краем")
                    XCTAssertLessThanOrEqual(c.p.x + reach, x.max + 0.03, "\(p.chore) u=\(u) за правым краем")
                    prev = c
                    u += 1.0 / 60
                }
            }
        }
    }

    func testRouteMissesBowlAndBall() {
        for size: Float in [1, 0.7, 0.45] {
            for p in allPlans() {
                let r = IdleRoute.make(p, act: p.act(len), size: size)
                var u = 0.0
                while u <= r.homeAt {
                    let c = r.pose(at: u)
                    if p.chore != .bowl {
                        XCTAssertFalse(covers(c.p, c.yaw, size: size, K.bowlHome, pad: K.bowlRadius),
                                       "\(p.chore) size=\(size) u=\(u) наступил на миску")
                    }
                    if p.chore != .toy {
                        XCTAssertFalse(covers(c.p, c.yaw, size: size, K.ballHome, pad: K.ballRadius),
                                       "\(p.chore) size=\(size) u=\(u) задел мяч")
                    }
                    u += 1.0 / 30
                }
            }
        }
    }

    func testSnoutAtThing() {
        for size: Float in [1, 0.7, 0.45] {
            for p in allPlans() where p.aimed {
                let r = IdleRoute.make(p, act: p.act(len), size: size)
                let at = r.pose(at: r.arriveAt)
                let snout = at.p + P(sin(at.yaw), cos(at.yaw)) * (K.petHalfLength * size)
                switch p.chore {
                case .bowl:
                    let d = (snout - K.bowlHome).length
                    XCTAssertGreaterThan(d, K.bowlRadius, "size=\(size) морда в миске")
                    XCTAssertLessThan(d, K.bowlRadius + 0.08, "size=\(size) далеко от миски")
                case .sniff:
                    let rect = p.line.hasSuffix("кухню") ? RoomPlan.kitchen : RoomPlan.bath
                    let d = rect.distance(to: snout)
                    XCTAssertGreaterThan(d, 0.005, "\(p.line) size=\(size) морда в мебели")
                    XCTAssertLessThan(d, 0.12, "\(p.line) size=\(size) далеко")
                default:
                    XCTFail("\(p.chore) не целится")
                }
            }
        }
    }

    func testCuesInOrder() {
        for p in allPlans() {
            let r = IdleRoute.make(p, act: p.act(len))
            let c = DogIdle.cues(p, r, homeLoop: "idle", len: len)
            XCTAssertFalse(c.isEmpty)
            XCTAssertEqual(zip(c, c.dropFirst()).filter { $0.at > $1.at }.count, 0, "\(p.chore)")
            XCTAssertEqual(c.last?.loop, "idle", "\(p.chore) дома — свой цикл")
            XCTAssertLessThanOrEqual(c.last?.at ?? 0, r.homeAt + 1e-9)
            if r.moves {
                XCTAssertEqual(c.first?.loop, "walk")
                XCTAssertEqual(c.first?.at, 0)
            }
            // Лёжа перебили — встать.
            if p.lies {
                let mid = r.arriveAt + p.steps.reduce(0.0) { $0 + len($1) } + p.holdSec / 2
                let s = DogIdle.stance(at: mid, c, home: p.home, len: len)
                XCTAssertEqual(s, .lie, "\(p.chore)")
                XCTAssertEqual(Gait.backClips(from: s, to: p.home).first, "lie_out", "\(p.chore)")
            }
            // Шаг кончается тогда же, когда дело на месте.
            if p.hold != nil, !p.out.isEmpty {
                let out = c.first { $0.steps == p.out }
                XCTAssertEqual(out?.at ?? 0, r.arriveAt + p.act(len) - p.out.reduce(0.0) { $0 + len($1) },
                               accuracy: 1e-9)
            }
        }
    }
}
