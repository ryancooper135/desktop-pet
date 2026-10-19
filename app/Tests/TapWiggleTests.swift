// Отклик на тап (волна 18, TapWiggle и SoftLook): углы в пределах, без рывка в один кадр, частые тапы
// не перезапускают и не бросают голову на другую сторону, всё возвращается в покой за ~1,3 с.

import XCTest
@testable import Pet

final class TapWiggleTests: XCTestCase {
    private let frame = 1.0 / 60
    private let deg: Float = .pi / 180

    /// Прогнать кадры по 1/60 с; taps — моменты тапов (с, вид, подсказка стороны).
    private func run(_ w: inout TapWiggle, seconds: Double, taps: [(Double, TapWiggle.Kind, Float?)] = [],
                     earsOnly: Bool = false) -> [TapWiggle.Pose] {
        var out: [TapWiggle.Pose] = []
        var pending = taps.sorted { $0.0 < $1.0 }
        let start = w.time
        let n = Int((seconds / frame).rounded())
        for _ in 0..<n {
            while let t = pending.first, t.0 <= w.time - start + 1e-9 {
                w.trigger(t.1, sideHint: t.2, earsOnly: earsOnly)
                pending.removeFirst()
            }
            out.append(w.step(dt: frame))
        }
        return out
    }

    private func assertInLimits(_ poses: [TapWiggle.Pose], file: StaticString = #filePath, line: UInt = #line) {
        for p in poses {
            XCTAssertLessThanOrEqual(abs(p.roll), TapWiggle.rollMax + 1e-6, file: file, line: line)
            XCTAssertLessThanOrEqual(p.ear, TapWiggle.earMax + 1e-6, file: file, line: line)
            XCTAssertGreaterThanOrEqual(p.ear, -TapWiggle.earBackFraction * TapWiggle.earMax - 1e-6, file: file, line: line)
            for k in 0..<3 {
                XCTAssertLessThanOrEqual(abs(p.tail[k]), TapWiggle.tailMax * TapWiggle.tailShare[k] + 1e-6,
                                         file: file, line: line)
            }
        }
    }

    /// Наибольший сдвиг за кадр: наклон, уши, хвост (Tail1).
    private func maxStep(_ poses: [TapWiggle.Pose]) -> (roll: Float, ear: Float, tail: Float) {
        var r: Float = 0, e: Float = 0, t: Float = 0
        var prev = TapWiggle.Pose.zero
        for p in poses {
            r = max(r, abs(p.roll - prev.roll))
            e = max(e, abs(p.ear - prev.ear))
            t = max(t, abs(p.tail[0] - prev.tail[0]))
            prev = p
        }
        return (r, e, t)
    }

    func testKinds() {
        XCTAssertEqual(TapWiggle.kind(of: "tap"), .tap)
        XCTAssertEqual(TapWiggle.kind(of: "tap.playful"), .tap)
        XCTAssertEqual(TapWiggle.kind(of: Traits.tapKind(SaveFile.fresh(now: 0), at: 0)), .tap)
        XCTAssertEqual(TapWiggle.kind(of: "tickle"), .tickle)
        XCTAssertNil(TapWiggle.kind(of: "pet"))
        XCTAssertNil(TapWiggle.kind(of: "tapdance"))
        XCTAssertNil(TapWiggle.kind(of: "feed"))
    }

    /// Пределы в разумных рамках: «чуть набок», без перекошенной морды.
    func testLimitsAreSmall() {
        XCTAssertLessThanOrEqual(TapWiggle.rollMax, 8 * deg)
        XCTAssertLessThanOrEqual(TapWiggle.earMax, 20 * deg)
        XCTAssertLessThanOrEqual(TapWiggle.tailMax, 25 * deg)
        XCTAssertLessThanOrEqual(SoftLook.fingerLimit, 0.4)
        XCTAssertLessThan(SoftLook.fingerLimit, PetFaceLimits.ball)
        XCTAssertLessThanOrEqual(SoftLook.bodyShare, 0.1)
    }

    func testSingleTapIsVisibleSmoothAndSettles() {
        var w = TapWiggle()
        let poses = run(&w, seconds: 2, taps: [(0, .tap, 0.5)])
        assertInLimits(poses)
        // Наклон в сторону тапа и заметный.
        let peak = poses.map(\.roll).max() ?? 0
        XCTAssertGreaterThan(peak, 0.6 * TapWiggle.rollMax)
        XCTAssertGreaterThanOrEqual(poses.map(\.roll).min() ?? 0, -1e-6, "в другую сторону не перелетает")
        // Плавный вход: до половины наклона не меньше 0,1 с (не щелчком за кадр), до пика — меньше 0,6 с.
        let half = poses.firstIndex { $0.roll >= 0.5 * TapWiggle.rollMax } ?? 0
        XCTAssertGreaterThanOrEqual(Double(half) * frame, 0.1)
        XCTAssertLessThan(Double(half) * frame, 0.6)
        // Уши дёрнулись, хвост вильнул.
        XCTAssertGreaterThan(poses.map(\.ear).max() ?? 0, 0.5 * TapWiggle.earMax)
        XCTAssertGreaterThan(poses.map { abs($0.tail[0]) }.max() ?? 0, 0.5 * TapWiggle.tailMax)
        // Всё в покое к 1,3 с, ровно ноль — сцена перестаёт писать кости.
        let settled = Int(1.3 / frame)
        for p in poses[settled...] {
            XCTAssertLessThan(abs(p.roll), 0.05 * deg)
            XCTAssertLessThan(abs(p.ear), 0.05 * deg)
            XCTAssertLessThan(abs(p.tail[0]), 0.05 * deg)
        }
        XCTAssertEqual(poses.last, .zero)
        XCTAssertTrue(w.idle)
    }

    /// Ни одного рывка: первый кадр почти на месте, дальше шаги за кадр малы (60 к/с).
    func testNoOneFrameJerk() {
        var w = TapWiggle()
        let poses = run(&w, seconds: 2, taps: [(0, .tap, 1)])
        let first = poses[0]
        XCTAssertLessThan(abs(first.roll), 0.1 * deg)
        XCTAssertLessThan(abs(first.ear), 1.5 * deg)
        XCTAssertLessThan(abs(first.tail[0]), 0.5 * deg)
        let s = maxStep(poses)
        XCTAssertLessThan(s.roll, 0.5 * deg, "наклон")
        XCTAssertLessThan(s.ear, 4 * deg, "уши")
        XCTAssertLessThan(s.tail, 8 * deg, "хвост")
    }

    /// Частые тапы: тап чаще minGap проглочен, наклон не перезапускается и не меняет сторону, без рывков.
    func testRapidTapsExtendWithoutJerk() {
        var w = TapWiggle()
        XCTAssertTrue(w.trigger(.tap, sideHint: 1))
        _ = w.step(dt: frame)
        XCTAssertFalse(w.trigger(.tap, sideHint: -1), "тап через кадр — та же реакция")
        w = TapWiggle()
        var taps: [(Double, TapWiggle.Kind, Float?)] = []
        for k in 0..<10 { taps.append((Double(k) * 0.12, .tap, k % 2 == 0 ? 1 : -1)) }
        let poses = run(&w, seconds: 3, taps: taps)
        assertInLimits(poses)
        XCTAssertGreaterThanOrEqual(poses.map(\.roll).min() ?? 0, -1e-6, "голову через центр не бросает")
        let s = maxStep(poses)
        XCTAssertLessThan(s.roll, 0.5 * deg)
        XCTAssertLessThan(s.ear, 5 * deg, "ухо при повторе дёргается чуть резче одиночного — это и есть «уши прикольно»")
        XCTAssertLessThan(s.tail, 8 * deg)
        // Последний тап на 1,08 с — к 2,5 с снова покой.
        XCTAssertEqual(poses.last, .zero)
    }

    /// Сторона — по тапу (lookX), без подсказки — по очереди; новая сторона только после покоя.
    func testSideFollowsTapThenAlternates() {
        var w = TapWiggle()
        let left = run(&w, seconds: 1.5, taps: [(0, .tap, -0.4)])
        XCTAssertLessThan(left.map(\.roll).min() ?? 0, -0.6 * TapWiggle.rollMax)
        let a = run(&w, seconds: 1.5, taps: [(0, .tap, nil)])
        let b = run(&w, seconds: 1.5, taps: [(0, .tap, 0)])
        let sa = (a.map(\.roll).max() ?? 0) > 0.01 ? 1 : -1
        let sb = (b.map(\.roll).max() ?? 0) > 0.01 ? 1 : -1
        XCTAssertNotEqual(sa, sb)
    }

    /// Щекотка — дольше виляет и держит наклон; частая щекотка не проглатывается (её и так мало).
    func testTickleLastsLonger() {
        func wagEnd(_ kind: TapWiggle.Kind) -> Double {
            var w = TapWiggle()
            let poses = run(&w, seconds: 3, taps: [(0, kind, 1)])
            assertInLimits(poses)
            let last = poses.lastIndex { abs($0.tail[0]) > 0.5 * deg } ?? 0
            return Double(last) * frame
        }
        XCTAssertGreaterThan(wagEnd(.tickle), wagEnd(.tap) + 0.3)
        var w = TapWiggle()
        XCTAssertTrue(w.trigger(.tap))
        XCTAssertTrue(w.trigger(.tickle))
    }

    /// Спит: только ухо, голова и хвост лежат.
    func testAsleepOnlyEar() {
        var w = TapWiggle()
        let poses = run(&w, seconds: 1.5, taps: [(0, .tap, 1)], earsOnly: true)
        XCTAssertEqual(poses.map(\.roll).max() ?? 1, 0)
        XCTAssertEqual(poses.map { abs($0.tail[0]) }.max() ?? 1, 0)
        XCTAssertGreaterThan(poses.map(\.ear).max() ?? 0, 0.3 * TapWiggle.earMax)
    }

    /// Неровные кадры (от 0 до 0,1 с) и тапы вперемешку: всё конечно и в пределах.
    func testUnevenFramesStayInLimits() {
        var rng = SplitMix(seed: 18)
        var w = TapWiggle()
        var poses: [TapWiggle.Pose] = []
        for _ in 0..<2000 {
            if rng.next() % 9 == 0 { w.trigger(rng.next() % 5 == 0 ? .tickle : .tap, sideHint: rng.next() % 2 == 0 ? -1 : 1) }
            let dt = Double(rng.next() % 1000) / 10000
            let p = w.step(dt: dt)
            XCTAssertTrue(p.roll.isFinite && p.ear.isFinite && p.tail.allSatisfy(\.isFinite))
            poses.append(p)
        }
        assertInLimits(poses)
        _ = w.step(dt: -1)
        XCTAssertTrue(w.time.isFinite)
    }

    /// Взгляд на палец: пружина без перелёта, с разгоном, ~0,3–0,7 с до 90%.
    func testFingerLookIsSoft() {
        var x: Float = 0, v: Float = 0
        let goal = SoftLook.fingerLimit
        var reached: Double?
        var prev: Float = 0
        var maxStep: Float = 0
        for i in 0..<120 {
            (x, v) = SoftSpring.step(x: x, v: v, target: goal, omega: SoftLook.omega, zeta: SoftLook.zeta, dt: Float(frame))
            XCTAssertLessThanOrEqual(x, goal + 1e-5, "без перелёта")
            if i == 0 { XCTAssertLessThan(x, 0.3 * deg, "первый кадр почти на месте") }
            maxStep = max(maxStep, abs(x - prev))
            prev = x
            if reached == nil, x >= 0.9 * goal { reached = Double(i + 1) * frame }
        }
        let t = try? XCTUnwrap(reached)
        XCTAssertGreaterThanOrEqual(t ?? 0, 0.3)
        XCTAssertLessThanOrEqual(t ?? 9, 0.7)
        XCTAssertLessThan(maxStep, 1.5 * deg)
    }

    /// Ни один клип тапа не кладёт шею набок (head_tilt — 18°): наклон даёт только TapWiggle.
    func testTraitTapClipsHaveNoNeckRoll() {
        for t in Trait.allCases {
            XCTAssertFalse(Traits.tapClips(t).contains("head_tilt"), "\(t)")
            XCTAssertFalse(Traits.tapClips(t).isEmpty, "\(t)")
        }
    }
}

/// Предел взгляда за мячом (PetFace.limit в приложении — RealityKit, сюда не попадает).
private enum PetFaceLimits {
    static let ball: Float = 0.6
}

/// Детерминированный генератор для теста неровных кадров.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
