// Траектории хореографии: миска под мордой на время еды, мяч и пробежка в «Поиграть», взгляд за мячом.
// Чистая математика ChoreoPath, без сцены.

import Foundation
import simd
import XCTest
@testable import Pet

final class PetChoreoTests: XCTestCase {
    typealias P = ChoreoPath.Play

    private func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ eps: Float = 1e-3) -> Bool { simd_distance(a, b) < eps }

    // MARK: еда

    func testEatWindow() {
        let d: (String) -> Double = { ["lie_out": 0.92, "eat": 2.67, "happy_wag": 1.5][$0] ?? 0 }
        let w = ChoreoPath.eatWindow(["lie_out", "eat", "eat", "eat", "happy_wag"], duration: d)
        XCTAssertEqual(w?.start ?? -1, 0.92, accuracy: 1e-9)
        XCTAssertEqual(w?.end ?? -1, 0.92 + 3 * 2.67, accuracy: 1e-9)
        XCTAssertNil(ChoreoPath.eatWindow(["hop", "happy_wag"], duration: d))
        let first = ChoreoPath.eatWindow(["eat"], duration: d)
        XCTAssertEqual(first?.start ?? -1, 0)
    }

    func testEatWindowWithParts() {
        let down = 17.0 / 24, up = 23.0 / 24
        let d: (String) -> Double = { [EatClip.down: down, EatClip.chew: 1.0, EatClip.up: up, "lie_out": 0.92][$0] ?? 0 }
        let meal = EatClip.meal(chews: EatClip.feedChews, available: PetStance.defaultClips)
        let w = ChoreoPath.eatWindow(["lie_out"] + meal + ["idle_2"], duration: d)
        XCTAssertEqual(w?.start ?? -1, 0.92, accuracy: 1e-9)
        XCTAssertEqual(w?.end ?? -1, 0.92 + down + Double(EatClip.feedChews) + up, accuracy: 1e-9)
    }

    func testOneFeedingEmptiesBowlOnce() throws {
        // «Покормить» стоя: опустил голову, жуёт, поднял. Корм от горки до нуля один раз и не досыпается,
        // к подъёму головы миска уже пустая, потом уходит домой.
        let up = 23.0 / 24
        let d: (String) -> Double = { [EatClip.down: 17.0 / 24, EatClip.chew: 1.0, EatClip.up: up][$0] ?? 0 }
        let meal = PetStance.reaction(kind: "feed", ok: true, stance: .stand)
        let w = try XCTUnwrap(ChoreoPath.eatWindow(meal, duration: d))
        let leave = w.end + 0.5
        func food(_ t: Double) -> Float { ChoreoPath.bowl(t, eatStart: w.start, eatEnd: w.end, leave: leave).food }

        var last = food(0.4)
        XCTAssertGreaterThan(last, 0.99)
        var emptied = 0
        var t = 0.45
        while t < leave + 0.5 {
            let f = food(t)
            XCTAssertLessThanOrEqual(f, last + 1e-6, "корм прибавился на t=\(t)")
            if last > 0.01 && f <= 0.01 { emptied += 1 }
            last = f
            t += 0.05
        }
        XCTAssertEqual(emptied, 1)
        XCTAssertLessThanOrEqual(ChoreoPath.foodDoneBeforeEnd, up, "корм должен кончиться до подъёма головы")
        XCTAssertLessThan(food(w.end - up), 0.01)
        XCTAssertGreaterThan(food(w.start + (w.end - w.start) / 2), 0.2, "ест, а не стоит над пустой миской")
    }

    func testBowlTargetUnderSnout() {
        // Под мордой: по оси морды впереди, на полу.
        let s = ChoreoPath.toStand(ChoreoPath.bowlTarget)
        XCTAssertEqual(s.x, 0, accuracy: 1e-4)
        XCTAssertGreaterThan(s.z, 0.2)
        XCTAssertLessThan(s.y, 0.05)
        XCTAssertTrue(near(ChoreoPath.toStand(ChoreoPath.toWorld([0.3, 0.1, -0.2])), [0.3, 0.1, -0.2]))
    }

    func testBowlDuringFeed() {
        let eatStart = 0.0, eatEnd = 3 * 2.67, leave = eatEnd + 0.5
        func at(_ t: Double) -> ChoreoPath.BowlPose {
            ChoreoPath.bowl(t, eatStart: eatStart, eatEnd: eatEnd, leave: leave)
        }
        // Еда с первого шага: миска под мордой уже через 0.4 с и до конца еды.
        var t = 0.5
        while t < eatEnd {
            let b = at(t)
            XCTAssertTrue(near(b.position, ChoreoPath.bowlTarget), "t=\(t)")
            XCTAssertGreaterThan(b.scale.y, 0.7, "t=\(t)")
            t += 0.1
        }
        // Корм только убывает и к концу съеден.
        var last: Float = 2
        t = 0.4
        while t < leave {
            let f = at(t).food
            XCTAssertLessThanOrEqual(f, last + 1e-6, "t=\(t)")
            last = f
            t += 0.05
        }
        XCTAssertGreaterThan(at(0.4).food, 0.99)
        XCTAssertLessThan(at(eatEnd).food, 0.01)
        // После ухода — дома и в полный размер.
        let gone = at(leave + 0.4)
        XCTAssertTrue(near(gone.position, PetRoom.bowlPos))
        XCTAssertEqual(gone.scale.y, 1, accuracy: 1e-3)
        XCTAssertEqual(gone.food, 0)
    }

    func testBowlWaitsForTransition() {
        // Сначала встаёт (lie_out), миска ждёт дома.
        let eatStart = 0.92, eatEnd = eatStart + 2.67
        let early = ChoreoPath.bowl(0.1, eatStart: eatStart, eatEnd: eatEnd, leave: eatEnd + 0.5)
        XCTAssertTrue(near(early.position, PetRoom.bowlPos))
        XCTAssertEqual(early.scale, .one)
        let ready = ChoreoPath.bowl(eatStart, eatStart: eatStart, eatEnd: eatEnd, leave: eatEnd + 0.5)
        XCTAssertTrue(near(ready.position, ChoreoPath.bowlTarget))
        // Уже стоит под мордой — не прыгает заново.
        let again = ChoreoPath.bowl(0, eatStart: 0, eatEnd: 2.67, leave: 3.2, present: true)
        XCTAssertTrue(near(again.position, ChoreoPath.bowlTarget))
        XCTAssertEqual(again.scale, .one)
    }

    func testBowlScaleNeverZero() {
        var t = 0.0
        while t < 5 {
            let b = ChoreoPath.bowl(t, eatStart: 0.6, eatEnd: 3.3, leave: 3.8)
            XCTAssertGreaterThan(min(b.scale.x, b.scale.y, b.scale.z), 0, "t=\(t)")
            XCTAssertTrue(b.position.x.isFinite && b.position.y.isFinite && b.position.z.isFinite)
            t += 0.01
        }
    }

    // MARK: игра

    func testBallMoves() {
        XCTAssertTrue(near(ChoreoPath.ball(0), P.ballHome))
        XCTAssertTrue(near(ChoreoPath.ball(P.kick - 0.01), P.ballHome))
        XCTAssertGreaterThan(simd_distance(ChoreoPath.ball(P.kick + P.fly * 0.6), P.ballHome), 0.3)
        XCTAssertTrue(near(ChoreoPath.ball(P.length), P.ballHome))
        var u = 0.0
        var seen: [SIMD3<Float>] = []
        var prev = ChoreoPath.ball(0)
        while u <= P.length {
            let b = ChoreoPath.ball(u)
            XCTAssertGreaterThanOrEqual(b.y, P.ballRadius - 1e-5, "мяч под полом, u=\(u)")
            XCTAssertLessThan(simd_distance(b, prev), 0.06, "мяч прыгнул, u=\(u)")
            if !seen.contains(where: { near($0, b, 0.05) }) { seen.append(b) }
            prev = b
            u += 0.01
        }
        // Мяч реально катается, а не стоит в двух точках.
        XCTAssertGreaterThan(seen.count, 8)
    }

    func testPetPathSmoothAndReturns() {
        let home = ChoreoPath.pet(0)
        XCTAssertTrue(near(home.position, .zero))
        XCTAssertEqual(home.yaw, PetRoom.yaw3q, accuracy: 1e-5)
        let end = ChoreoPath.pet(P.length)
        XCTAssertTrue(near(end.position, .zero))
        XCTAssertEqual(end.yaw, PetRoom.yaw3q, accuracy: 1e-5)
        // В середине — у мяча.
        XCTAssertGreaterThan(simd_length(ChoreoPath.pet(P.pounce1).position), 0.15)
        var u = 0.0
        var prev = home
        while u <= P.length {
            let p = ChoreoPath.pet(u)
            XCTAssertLessThan(simd_distance(p.position, prev.position), 0.05, "u=\(u)")
            XCTAssertLessThan(abs(p.yaw - prev.yaw), 0.12, "u=\(u)")
            XCTAssertEqual(p.position.y, 0, accuracy: 1e-6)
            prev = p
            u += 0.01
        }
    }

    /// Тело — отрезок вдоль морды ±0.22 м с радиусом 0.08; мяч его не протыкает, кроме прыжка на мяч.
    func testBallMissesBody() {
        func gap(_ u: Double) -> Float {
            let p = ChoreoPath.pet(u)
            let f = SIMD3<Float>(sin(p.yaw), 0, cos(p.yaw))
            let a = p.position - f * 0.22, b = p.position + f * 0.22
            var c = ChoreoPath.ball(u)
            c.y = 0
            let t = min(max(simd_dot(c - a, b - a) / simd_dot(b - a, b - a), 0), 1)
            return simd_distance(c, a + (b - a) * t)
        }
        var u = 0.0
        while u <= P.length {
            if u < P.run1 - 0.3 || u > P.pounce1 {
                XCTAssertGreaterThan(gap(u), 0.13, "u=\(u)")
            }
            u += 0.01
        }
    }

    func testLookFollowsBall() {
        XCTAssertNil(ChoreoPath.look(-0.1, limit: 0.6))
        XCTAssertNil(ChoreoPath.look(P.walk1 + 0.1, limit: 0.6))
        // Мяч улетел вправо-назад от морды: голова до упора вправо.
        XCTAssertEqual(ChoreoPath.look(P.kick + 0.5, limit: 0.6) ?? 0, 0.6, accuracy: 1e-5)
        var u = 0.0
        while u < P.walk1 {
            let l = ChoreoPath.look(u, limit: 0.6)
            XCTAssertNotNil(l)
            XCTAssertLessThanOrEqual(abs(l ?? 9), 0.6 + 1e-6)
            u += 0.05
        }
    }

    func testCuesOrdered() {
        let cues = P.cues
        XCTAssertFalse(cues.isEmpty)
        for i in 1..<cues.count {
            XCTAssertLessThan(cues[i - 1].at, cues[i].at)
        }
        XCTAssertGreaterThan(cues.first?.at ?? 0, P.kick)
        XCTAssertLessThan(cues.last?.at ?? 99, P.length)
        // Последний шаг возвращает основной цикл позы.
        XCTAssertNil(cues.last?.loop)
    }

    func testPlayReactionStartsBallGame() {
        let all: Set<String> = Set(PetClipNames.required).union(["hop", "play_bow"])
        XCTAssertEqual(PetStance.reaction(kind: "play", ok: true, stance: .stand, available: all), ["play_bow"])
        let hopOnly: Set<String> = Set(PetClipNames.required).union(["hop"])
        XCTAssertEqual(PetStance.reaction(kind: "play", ok: true, stance: .stand, available: hopOnly), ["hop"])
    }
}
