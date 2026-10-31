// Траектории хореографии: миска под мордой на время еды, мяч и пробежка в «Поиграть», взгляд за мячом,
// уход на прогулку и возвращение с находкой.
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

    func testPointsFollowCharacterBody() {
        // Волна 13: у своего персонажа миска под его мордой, находка у его пасти, пятно по его размеру.
        let shibaBowl = ChoreoPath.toStand(ChoreoPath.bowlTarget)
        let shibaReach = ChoreoPath.petReachMax
        ChoreoPath.body = PetBody(height: 0.8, length: 0.8, width: 0.8, lift: 0)
        defer { ChoreoPath.body = .shiba }
        let small = ChoreoPath.toStand(ChoreoPath.bowlTarget)
        XCTAssertEqual(small.z, shibaBowl.z * 0.8, accuracy: 1e-4)
        XCTAssertEqual(small.y, shibaBowl.y, accuracy: 1e-4, "миска на полу")
        XCTAssertEqual(ChoreoPath.Walk.carry.y, ChoreoPath.Walk.shibaCarry.y * 0.8, accuracy: 1e-4)
        XCTAssertEqual(ChoreoPath.Walk.carry.z, ChoreoPath.Walk.shibaCarry.z * 0.8, accuracy: 1e-4)
        XCTAssertEqual(ChoreoPath.petReachMax, shibaReach * 0.8, accuracy: 1e-4)
        // Перед мячом встаёт ближе: морда короче.
        let ballXZ = SIMD3<Float>(P.ballFar.x, 0, P.ballFar.z)
        XCTAssertEqual(simd_distance(P.runTo, ballXZ), 0.30 * 0.8, accuracy: 0.02)
        ChoreoPath.body = .shiba
        XCTAssertTrue(near(ChoreoPath.toStand(ChoreoPath.bowlTarget), shibaBowl))
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

    // MARK: игра в кадре

    /// Те же портретные экраны, что в HomeLayoutTests: самый узкий — 390×844.
    private static let portraitAspects: [Float] = [390.0 / 844.0, 420.0 / 912.0, 440.0 / 956.0]
    /// Высота Шибы до макушки, метры.
    private static let petHeight: Float = 0.42

    /// x в NDC (-1…1) для точки мира при камере PetRoom; FOV вертикальный.
    @MainActor
    private func ndcX(_ p: SIMD3<Float>, aspect: Float) -> Float {
        let eye = PetRoom.cameraEye
        let f = simd_normalize(PetRoom.cameraTarget - eye)
        let r = simd_normalize(simd_cross(f, SIMD3<Float>(0, 1, 0)))
        let d = p - eye
        let depth = simd_dot(d, f)
        let half = tan(PetRoom.cameraFov * .pi / 180 / 2)
        return simd_dot(d, r) / (depth * half * aspect)
    }

    /// Углы коробки собаки (длина ±petHalfLength вдоль морды, ширина ±petHalfWidth) от пола до макушки.
    private func petCorners(_ p: ChoreoPath.PetPose) -> [SIMD3<Float>] {
        let f = SIMD3<Float>(sin(p.yaw), 0, cos(p.yaw))
        let s = SIMD3<Float>(f.z, 0, -f.x)
        var out: [SIMD3<Float>] = []
        for a in [-ChoreoPath.petHalfLength, ChoreoPath.petHalfLength] {
            for b in [-ChoreoPath.petHalfWidth, ChoreoPath.petHalfWidth] {
                for y in [0, Self.petHeight] {
                    out.append(p.position + f * a + s * b + SIMD3<Float>(0, y, 0))
                }
            }
        }
        return out
    }

    private func ballCorners(_ c: SIMD3<Float>) -> [SIMD3<Float>] {
        let r = P.ballRadius
        var out: [SIMD3<Float>] = []
        for dx in [-r, r] { for dy in [-r, r] { for dz in [-r, r] { out.append(c + SIMD3<Float>(dx, dy, dz)) } } }
        return out
    }

    /// Площадка ChoreoPath.playArea сверена с камерой: её края от пола до макушки — в пределах |x| ≤ 0.95.
    /// Сменили камеру — этот тест скажет пересчитать площадку.
    @MainActor
    func testPlayAreaMatchesCamera() {
        let a = ChoreoPath.playArea
        for aspect in Self.portraitAspects {
            for z in stride(from: a.farZ, through: a.nearZ, by: 0.05) {
                let r = a.xRange(z)
                for y in [0, Self.petHeight] {
                    XCTAssertLessThanOrEqual(abs(ndcX(SIMD3<Float>(r.min, y, z), aspect: aspect)), 0.951, "z=\(z)")
                    XCTAssertLessThanOrEqual(abs(ndcX(SIMD3<Float>(r.max, y, z), aspect: aspect)), 0.951, "z=\(z)")
                }
            }
        }
        // Внутри площадки clamp ничего не меняет, снаружи — возвращает на край.
        let inside = SIMD3<Float>(0, 0, -0.3)
        XCTAssertTrue(near(a.clamp(inside, inset: 0.1), inside, 1e-6))
        let out = a.clamp(SIMD3<Float>(2, 0, -5), inset: 0.1)
        XCTAssertEqual(out.z, a.farZ, accuracy: 1e-6)
        XCTAssertEqual(out.x, a.farMaxX - 0.1, accuracy: 1e-6)
        XCTAssertTrue(near(a.clamp(out, inset: 0.1), out, 1e-6))
    }

    /// Вся игра — и собака целиком, и мяч — внутри портретного кадра на любом айфоне, с запасом до края.
    @MainActor
    func testPlayStaysInFrame() {
        for aspect in Self.portraitAspects {
            var u = 0.0
            while u <= P.length + 1e-9 {
                for p in petCorners(ChoreoPath.pet(u)) {
                    XCTAssertLessThan(abs(ndcX(p, aspect: aspect)), 0.95, "собака за краем, u=\(u), aspect=\(aspect)")
                }
                for p in ballCorners(ChoreoPath.ball(u)) {
                    XCTAssertLessThan(abs(ndcX(p, aspect: aspect)), 0.95, "мяч за краем, u=\(u), aspect=\(aspect)")
                }
                u += 0.01
            }
        }
    }

    /// Центры собаки и мяча не выходят за площадку с отступом под их размер.
    func testPlayCentersInsideArea() {
        let a = ChoreoPath.playArea
        var u = 0.0
        while u <= P.length + 1e-9 {
            let p = ChoreoPath.pet(u)
            let r = a.xRange(p.position.z)
            let reach = ChoreoPath.petReach(yaw: p.yaw)
            XCTAssertGreaterThanOrEqual(p.position.x, r.min + reach - 1e-4, "u=\(u)")
            XCTAssertLessThanOrEqual(p.position.x, r.max - reach + 1e-4, "u=\(u)")
            let b = ChoreoPath.ball(u)
            let rb = a.xRange(b.z)
            XCTAssertGreaterThanOrEqual(b.x, rb.min + P.ballRadius - 1e-4, "u=\(u)")
            XCTAssertLessThanOrEqual(b.x, rb.max - P.ballRadius + 1e-4, "u=\(u)")
            XCTAssertGreaterThanOrEqual(b.z, a.farZ - 1e-4)
            XCTAssertLessThanOrEqual(b.z, a.nearZ + 1e-4)
            u += 0.01
        }
    }

    // MARK: ласка

    func testPettingEnvelope() {
        let len = 2.7
        // Вне реакции — покой.
        XCTAssertEqual(ChoreoPath.petting(-0.1, length: len, side: 1), .rest)
        XCTAssertEqual(ChoreoPath.petting(len, length: len, side: 1), .rest)
        let start = ChoreoPath.petting(0, length: len, side: 1)
        XCTAssertEqual(start.lean, 0, accuracy: 1e-6)
        XCTAssertEqual(start.wiggle, 0, accuracy: 1e-6)
        XCTAssertFalse(start.eyesClosed)
        // К концу всё гаснет плавно.
        let late = ChoreoPath.petting(len - 0.01, length: len, side: 1)
        XCTAssertLessThan(abs(late.lean), 0.01)
        XCTAssertFalse(late.eyesClosed)
        // В середине: клонится к руке, жмурится, виляет.
        let mid = len / 2
        let right = ChoreoPath.petting(mid, length: len, side: 1)
        let left = ChoreoPath.petting(mid, length: len, side: -1)
        XCTAssertEqual(right.lean, ChoreoPath.Petting.lean, accuracy: 1e-4)
        XCTAssertEqual(left.lean, -ChoreoPath.Petting.lean, accuracy: 1e-4)
        XCTAssertTrue(right.eyesClosed)
        XCTAssertTrue(left.eyesClosed)
        var maxWiggle: Float = 0
        var t = 0.0
        var prev = ChoreoPath.petting(0, length: len, side: 1)
        while t < len {
            let p = ChoreoPath.petting(t, length: len, side: 1)
            maxWiggle = max(maxWiggle, abs(p.wiggle))
            XCTAssertLessThanOrEqual(abs(p.lean), ChoreoPath.Petting.lean + 1e-6)
            XCTAssertLessThan(abs(p.lean - prev.lean), 0.02, "t=\(t)")
            prev = p
            t += 0.01
        }
        XCTAssertGreaterThan(maxWiggle, ChoreoPath.Petting.wiggle * 0.8)
        XCTAssertLessThanOrEqual(maxWiggle, ChoreoPath.Petting.wiggle + 1e-6)
    }

    func testPlayReactionStartsBallGame() {
        let all: Set<String> = Set(PetClipNames.required).union(["hop", "play_bow"])
        XCTAssertEqual(PetStance.reaction(kind: "play", ok: true, stance: .stand, available: all), ["play_bow"])
        let hopOnly: Set<String> = Set(PetClipNames.required).union(["hop"])
        XCTAssertEqual(PetStance.reaction(kind: "play", ok: true, stance: .stand, available: hopOnly), ["hop"])
    }

    /// Расчесали — отряхнулся, подпрыгнул, виляет (сидящий сначала встаёт); против шерсти — дёрнулся с той стороны,
    /// где палец.
    func testBrushReaction() {
        let all = Set(PetClipNames.required).union(PetClipNames.optional)
        XCTAssertEqual(PetStance.reaction(kind: "brush", ok: true, stance: .stand, available: all), ["shake", "hop", "happy_wag"])
        let sit = PetStance.reaction(kind: "brush", ok: true, stance: .sit, available: all)
        XCTAssertEqual(Array(sit.suffix(3)), ["shake", "hop", "happy_wag"])
        XCTAssertEqual(PetStance.endStance(after: sit, from: .sit), .stand)
        XCTAssertEqual(PetStance.reaction(kind: "brush", ok: false, stance: .stand, lookX: -0.5, available: all), ["hit_left"])
        XCTAssertEqual(PetStance.reaction(kind: "brush", ok: false, stance: .stand, lookX: 0.5, available: all), ["hit_right"])
        XCTAssertEqual(PetStance.reaction(kind: "brush", ok: false, stance: .lie, available: all), ["ear_flick"])
        XCTAssertEqual(PetStance.reaction(kind: "brush", ok: true, stance: .sleep, available: all), [])
        // Без shake в модели — виляние хвостом.
        let noShake = all.subtracting(["shake"])
        XCTAssertEqual(PetStance.reaction(kind: "brush", ok: true, stance: .stand, available: noShake), ["happy_wag"])
        // Без hop — отряхнулся и виляет.
        let noHop = all.subtracting(["hop"])
        XCTAssertEqual(PetStance.reaction(kind: "brush", ok: true, stance: .stand, available: noHop), ["shake", "happy_wag"])
    }

    /// После партии в Блок Дуо (бывшая реакция привычки, волна 57): стоя — подпрыгнул и виляет, сидя и лёжа — ухо,
    /// спящего не будим.
    func testJoyReaction() {
        let all = Set(PetClipNames.required).union(PetClipNames.optional)
        XCTAssertEqual(PetStance.reaction(kind: BlockDuo.reactKind, ok: true, stance: .stand, available: all), ["hop", "happy_wag"])
        XCTAssertEqual(PetStance.reaction(kind: BlockDuo.reactKind, ok: true, stance: .sit, available: all), ["ear_flick"])
        XCTAssertEqual(PetStance.endStance(after: ["ear_flick"], from: .lie), .lie, "лежащий остаётся лежать")
        XCTAssertEqual(PetStance.reaction(kind: BlockDuo.reactKind, ok: true, stance: .sleep, available: all), [])
    }

    /// Новый уровень или фаза роста (волна 57: свой вид вместо трюка «Прыжок»): встал, подпрыгнул, виляет и вернулся
    /// в позу; спящего и мёртвого не трогаем.
    func testLevelUpReaction() {
        let all = Set(PetClipNames.required).union(PetClipNames.optional)
        XCTAssertEqual(PetStance.reaction(kind: PetStance.levelUpKind, ok: true, stance: .stand, available: all), ["hop", "happy_wag"])
        let fromSit = PetStance.reaction(kind: PetStance.levelUpKind, ok: true, stance: .sit, available: all)
        XCTAssertEqual(fromSit.first, "sit_out")
        XCTAssertTrue(fromSit.contains("hop"))
        XCTAssertEqual(fromSit.last, "sit_in", "вернулся сидеть")
        XCTAssertEqual(PetStance.endStance(after: fromSit, from: .sit), .sit)
        XCTAssertEqual(PetStance.reaction(kind: PetStance.levelUpKind, ok: true, stance: .sleep, available: all), [])
        XCTAssertEqual(PetStance.reaction(kind: PetStance.levelUpKind, ok: true, stance: .dead, available: all), [])
    }

    // MARK: прогулка

    typealias W = ChoreoPath.Walk

    /// За краем Шиба весь — и мордой к краю (уходит), и мордой к дому (возвращается) — на любом айфоне.
    @MainActor
    func testWalkExitOffFrame() {
        for aspect in Self.portraitAspects {
            for yaw in [W.yawOut, W.yawIn] {
                for p in petCorners(ChoreoPath.PetPose(position: W.offstage, yaw: yaw)) {
                    XCTAssertGreaterThan(ndcX(p, aspect: aspect), 1.02, "виден у края, yaw=\(yaw), aspect=\(aspect)")
                }
            }
            // Находка в зубах тоже не торчит из-за края.
            let f = SIMD3<Float>(sin(W.yawIn), 0, cos(W.yawIn))
            let prop = W.offstage + f * W.carry.z + SIMD3<Float>(0, W.carry.y, 0)
            XCTAssertGreaterThan(ndcX(prop, aspect: aspect), 1.02)
        }
        // Точка разворота перед уходом — в кадре при любом повороте.
        let a = ChoreoPath.playArea
        XCTAssertTrue(near(a.clamp(W.turnAt, inset: ChoreoPath.petReachMax), W.turnAt, 1e-4))
    }

    /// Уход: из дома в 3/4, разворот через «лицом к камере», дальше только вправо и без рывков, в конце — за краем.
    func testWalkOutPath() {
        let start = ChoreoPath.walkOut(0)
        XCTAssertTrue(near(start.position, .zero))
        XCTAssertEqual(start.yaw, PetRoom.yaw3q, accuracy: 1e-5)
        XCTAssertLessThan(PetRoom.yaw3q, 0)
        XCTAssertGreaterThan(W.yawOut, 0, "поворот к краю — через морду к камере (yaw 0), не через спину")
        let end = ChoreoPath.walkOut(W.outLength)
        XCTAssertTrue(near(end.position, W.offstage))
        var prev = start
        var u = 0.01
        while u <= W.outLength + 1e-9 {
            let p = ChoreoPath.walkOut(u)
            XCTAssertLessThan(simd_distance(p.position, prev.position), 1.5 * W.speed * 0.01 * 1.05 + 1e-4, "рывок, u=\(u)")
            XCTAssertLessThan(abs(p.yaw - prev.yaw), 0.08, "крутанулся, u=\(u)")
            if u > W.turnOut { XCTAssertGreaterThanOrEqual(p.position.x, prev.position.x - 1e-5, "попятился, u=\(u)") }
            XCTAssertGreaterThanOrEqual(p.position.z, ChoreoPath.playArea.farZ)
            XCTAssertLessThanOrEqual(p.position.z, ChoreoPath.playArea.nearZ)
            prev = p
            u += 0.01
        }
    }

    /// Возвращение: из-за края домой с торможением, дома — снова в 3/4.
    func testWalkInPath() {
        let start = ChoreoPath.walkIn(0)
        XCTAssertTrue(near(start.position, W.offstage))
        XCTAssertEqual(start.yaw, W.yawIn, accuracy: 1e-5)
        let home = ChoreoPath.walkIn(W.inWalk + W.turnIn)
        XCTAssertTrue(near(home.position, .zero))
        XCTAssertEqual(home.yaw, PetRoom.yaw3q, accuracy: 1e-5)
        XCTAssertEqual(ChoreoPath.walkIn(W.inLength), home)
        var prev = start
        var u = 0.01
        while u <= W.inLength + 1e-9 {
            let p = ChoreoPath.walkIn(u)
            XCTAssertLessThan(simd_distance(p.position, prev.position), 1.5 * W.speed * 0.01 * 1.05 + 1e-4, "рывок, u=\(u)")
            XCTAssertLessThan(abs(p.yaw - prev.yaw), 0.08, "крутанулся, u=\(u)")
            XCTAssertLessThanOrEqual(p.position.x, prev.position.x + 1e-5, "попятился, u=\(u)")
            prev = p
            u += 0.01
        }
        // Мяч по пути не задевает: проходит позади него.
        let ball = PetRoom.ballPos
        u = 0
        while u <= W.inWalk {
            let p = ChoreoPath.walkIn(u).position
            XCTAssertGreaterThan(ball.z - p.z, ChoreoPath.petHalfWidth + ChoreoPath.Play.ballRadius, "u=\(u)")
            u += 0.05
        }
    }

    /// Прогулку отменили на полпути: возвращение начинается с той же дальности от дома.
    func testWalkInStart() {
        XCTAssertEqual(ChoreoPath.walkInStart(from: W.offstage), 0, accuracy: 1e-3)
        XCTAssertEqual(ChoreoPath.walkInStart(from: .zero), W.inWalk, accuracy: 1e-3)
        let mid = ChoreoPath.walkOut(W.turnOut + W.outWalk * 0.6).position
        let u = ChoreoPath.walkInStart(from: mid)
        XCTAssertGreaterThan(u, 0)
        XCTAssertLessThan(u, W.inWalk)
        XCTAssertEqual(simd_length(ChoreoPath.walkIn(u).position), simd_length(SIMD3<Float>(mid.x, 0, mid.z)), accuracy: 2e-3)
    }

    /// Находка: в зубах до прихода, падает перед мордой, лежит, тает и уходит; масштаб не 0 (RealityKit).
    func testWalkProp() {
        XCTAssertEqual(ChoreoPath.walkProp(0)?.position, W.carry)
        XCTAssertEqual(ChoreoPath.walkProp(W.dropAt - 0.01)?.position, W.carry)
        XCTAssertEqual(ChoreoPath.walkProp(W.dropAt + W.dropTime + 0.1)?.position, W.dropped)
        XCTAssertGreaterThan(W.dropped.z, W.carry.z - 0.01, "кладёт перед собой, а не под лапы")
        XCTAssertNil(ChoreoPath.walkProp(W.inLength + 0.01))
        var u = 0.0
        var prev = W.carry
        while u < W.inLength {
            guard let p = ChoreoPath.walkProp(u) else { return XCTFail("пропала раньше конца, u=\(u)") }
            XCTAssertGreaterThan(p.scale, 0)
            XCTAssertLessThanOrEqual(p.scale, 1)
            XCTAssertGreaterThanOrEqual(p.position.y, 0)
            XCTAssertLessThan(simd_distance(p.position, prev), 0.05, "скачок, u=\(u)")
            prev = p.position
            u += 0.01
        }
        // Дома держит позу, пока находка не ушла: режиссёр ставит следующую позу не раньше прихода.
        XCTAssertGreaterThan(W.inLength, W.inWalk + W.turnIn)
    }
}
