// Глаза держатся головы (волна 32, EyePin): у глаз и шерсти рядом нет веса ушей, сумма весов та же,
// переход к шерсти дальше — плавный; уши двигаются — глаз на голове стоит на месте.

import XCTest
@testable import Pet

final class EyePinTests: XCTestCase {
    // Кости: 0 — голова, 1 и 2 — уши, 3 — шея.
    private let head = 0
    private let ears: Set<Int> = [1, 2]
    private let eyes = EyePin.Eyes(centers: [SIMD3(-2, 0, 0), SIMD3(2, 0, 0)], size: 1)

    private func sum(_ w: [BoneWeight]) -> Float { w.reduce(0) { $0 + $1.weight } }
    private func earWeight(_ w: [BoneWeight]) -> Float { w.filter { ears.contains($0.joint) }.reduce(0) { $0 + $1.weight } }

    func testKeepIsZeroNearOneFarAndMonotone() {
        XCTAssertEqual(EyePin.keep(distance: 0), 0)
        XCTAssertEqual(EyePin.keep(distance: EyePin.inner), 0)
        XCTAssertEqual(EyePin.keep(distance: EyePin.outer), 1)
        XCTAssertEqual(EyePin.keep(distance: 10), 1)
        XCTAssertEqual(EyePin.keep(distance: .infinity), 1)
        XCTAssertEqual(EyePin.keep(distance: .nan), 1)
        var prev: Float = 0
        for k in 0...300 {
            let d = Float(k) * 0.01
            let v = EyePin.keep(distance: d)
            XCTAssertGreaterThanOrEqual(v, prev, "монотонно при d = \(d)")
            // Без ступенек: на шаге 0,01 размера глаза доля меняется меньше чем на 3%.
            XCTAssertLessThan(v - prev, 0.03, "плавно при d = \(d)")
            XCTAssert((0...1).contains(v))
            prev = v
        }
    }

    func testReweightKeepsSumAndMovesEarsToHead() {
        let w = [BoneWeight(joint: 0, weight: 0.4), BoneWeight(joint: 1, weight: 0.35),
                 BoneWeight(joint: 2, weight: 0.15), BoneWeight(joint: 3, weight: 0.1)]
        for keep: Float in [0, 0.25, 0.5, 0.99] {
            let out = EyePin.reweight(w, keep: keep, moving: ears, anchor: head)
            XCTAssertEqual(out.count, w.count)
            XCTAssertEqual(sum(out), sum(w), accuracy: 1e-6)
            XCTAssertEqual(earWeight(out), earWeight(w) * keep, accuracy: 1e-6)
            XCTAssert(out.allSatisfy { $0.weight >= 0 })
            // Шея не тронута.
            XCTAssertEqual(out[3], w[3])
        }
        XCTAssertEqual(EyePin.reweight(w, keep: 1, moving: ears, anchor: head), w)
    }

    func testReweightWithoutHeadSlot() {
        // Есть пустой слот — голова встаёт в него.
        let free = [BoneWeight(joint: 1, weight: 0.7), BoneWeight(joint: 3, weight: 0.3), BoneWeight(joint: 0, weight: 0)]
        let a = EyePin.reweight(free, keep: 0, moving: ears, anchor: head)
        XCTAssertEqual(sum(a), 1, accuracy: 1e-6)
        XCTAssertEqual(earWeight(a), 0)
        XCTAssertEqual(a.filter { $0.joint == head }.reduce(0) { $0 + $1.weight }, 0.7, accuracy: 1e-6)
        XCTAssertEqual(a.first { $0.joint == 3 }?.weight ?? 0, 0.3, accuracy: 1e-6)
        // Головы нет совсем: слот обнулённого уха отдаётся голове.
        let none = [BoneWeight(joint: 1, weight: 0.6), BoneWeight(joint: 3, weight: 0.4)]
        let b = EyePin.reweight(none, keep: 0, moving: ears, anchor: head)
        XCTAssertEqual(sum(b), 1, accuracy: 1e-6)
        XCTAssertEqual(earWeight(b), 0)
        XCTAssertEqual(b.first { $0.joint == 3 }?.weight ?? 0, 0.4, accuracy: 1e-6)
        // Якорь среди «двигающихся» — ничего не делаем (защита от путаницы костей).
        XCTAssertEqual(EyePin.reweight(none, keep: 0, moving: [0, 1], anchor: 0), none)
    }

    func testEyesSplitIntoTwo() {
        var pts: [SIMD3<Float>] = []
        for x in stride(from: Float(-2.5), through: -1.5, by: 0.25) { pts.append(SIMD3(x, 0.2, 1)); pts.append(SIMD3(x, -0.2, 1)) }
        for x in stride(from: Float(1.5), through: 2.5, by: 0.25) { pts.append(SIMD3(x, 0.2, 1)); pts.append(SIMD3(x, -0.2, 1)) }
        let e = EyePin.eyes(pts)
        XCTAssertEqual(e?.centers.count, 2)
        XCTAssertEqual(e?.size ?? 0, 1, accuracy: 1e-5)
        XCTAssertEqual(e?.centers.first?.x ?? 0, -2, accuracy: 1e-5)
        XCTAssertEqual(e?.centers.last?.x ?? 0, 2, accuracy: 1e-5)
        XCTAssertNil(EyePin.eyes([]))
        XCTAssertNil(EyePin.eyes([SIMD3(1, 1, 1), SIMD3(1, 1, 1)]))
    }

    /// Буфер: по 4 влияния на вершину, у всех половина веса на ухе.
    private func buffer(_ n: Int) -> [BoneWeight] {
        (0..<n).flatMap { _ in
            [BoneWeight(joint: 0, weight: 0.3), BoneWeight(joint: 1, weight: 0.4),
             BoneWeight(joint: 2, weight: 0.1), BoneWeight(joint: 3, weight: 0.2)]
        }
    }

    func testPinEyePartLosesAllEarWeight() {
        let pos: [SIMD3<Float>] = [SIMD3(-2, 0, 0), SIMD3(2, 0.3, 0), SIMD3(-2, 9, 0)]
        let out = EyePin.pin(buffer(3), perVertex: 4, positions: pos, eye: true, eyes: eyes, moving: ears, anchor: head)
        XCTAssertNotNil(out)
        for v in 0..<3 {
            let w = Array(out![v * 4 ..< v * 4 + 4])
            XCTAssertEqual(earWeight(w), 0, "вершина глаза \(v)")
            XCTAssertEqual(sum(w), 1, accuracy: 1e-6)
        }
        XCTAssertFalse(EyePin.needed(eyeInfluences: out!, moving: ears), "второй раз не правим")
        XCTAssertTrue(EyePin.needed(eyeInfluences: buffer(1), moving: ears))
    }

    func testPinFurByDistance() {
        // Рядом с глазом, в переходе, далеко.
        let pos: [SIMD3<Float>] = [SIMD3(-2, 1, 0), SIMD3(-2, 1.6, 0), SIMD3(-2, 5, 0)]
        guard let out = EyePin.pin(buffer(3), perVertex: 4, positions: pos, eye: false, eyes: eyes,
                                   moving: ears, anchor: head) else { return XCTFail("рядом с глазом есть что править") }
        let near = earWeight(Array(out[0..<4])), mid = earWeight(Array(out[4..<8])), far = earWeight(Array(out[8..<12]))
        XCTAssertEqual(near, 0)
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, 0.5)
        XCTAssertEqual(far, 0.5, accuracy: 1e-6)
        // Далеко от глаз — нечего менять.
        XCTAssertNil(EyePin.pin(buffer(1), perVertex: 4, positions: [SIMD3(0, 9, 0)], eye: false, eyes: eyes,
                                moving: ears, anchor: head))
        // Размеры не сходятся — не трогаем.
        XCTAssertNil(EyePin.pin(buffer(2), perVertex: 4, positions: [SIMD3(-2, 0, 0)], eye: true, eyes: eyes,
                                moving: ears, anchor: head))
    }

    // MARK: инвариант на скине

    /// Линейный скин: вершина = сумма весов × матрица кости. Голова на месте, уши повёрнуты вокруг своего корня.
    private func skin(_ p: SIMD3<Float>, _ w: [BoneWeight], ear angle: Float) -> SIMD3<Float> {
        // Ухо: поворот вокруг оси X через корень уха (0, 3, 0).
        let pivot = SIMD3<Float>(0, 3, 0)
        let r = p - pivot
        let c = cos(angle), s = sin(angle)
        let onEar = pivot + SIMD3(r.x, c * r.y - s * r.z, s * r.y + c * r.z)
        var out = SIMD3<Float>(repeating: 0)
        let total = max(sum(w), 1e-9)
        for b in w where b.weight > 0 {
            out += (ears.contains(b.joint) ? onEar : p) * (b.weight / total)
        }
        return out
    }

    private func length(_ v: SIMD3<Float>) -> Float { (v * v).sum().squareRoot() }

    func testEyeStaysOnHeadWhenEarsMove() {
        let eyePts: [SIMD3<Float>] = [SIMD3(-2, 0, 0), SIMD3(-2, 0.4, 0.2), SIMD3(2, -0.3, 0.1)]
        let furPts: [SIMD3<Float>] = [SIMD3(-2, 0.9, 0), SIMD3(2, -1, 0)]
        let eyeW = EyePin.pin(buffer(eyePts.count), perVertex: 4, positions: eyePts, eye: true, eyes: eyes,
                              moving: ears, anchor: head)!
        let furW = EyePin.pin(buffer(furPts.count), perVertex: 4, positions: furPts, eye: false, eyes: eyes,
                              moving: ears, anchor: head)!
        // Уши назад и вперёд — с запасом сверх отклика на тап.
        for angle: Float in [-2 * TapWiggle.earMax, -TapWiggle.earMax, TapWiggle.earMax, 0.6] {
            for (v, p) in eyePts.enumerated() {
                let before = length(skin(p, Array(buffer(1)), ear: angle) - p)
                let after = length(skin(p, Array(eyeW[v * 4 ..< v * 4 + 4]), ear: angle) - p)
                XCTAssertGreaterThan(before, 0.05, "без правки ухо тянуло глаз (проверка теста)")
                XCTAssertLessThan(after, 1e-5, "глаз \(v) не уезжает при ушах \(angle)")
            }
            for (v, p) in furPts.enumerated() {
                let after = length(skin(p, Array(furW[v * 4 ..< v * 4 + 4]), ear: angle) - p)
                XCTAssertLessThan(after, 1e-5, "шерсть у глаза \(v) стоит вместе с глазом")
            }
        }
    }

    // MARK: любая модель (волна 50)

    func testPlausibleByShape() {
        // Шиба: глаза 0,0012 в 0,0044 друг от друга, модель ~0,05.
        let shiba = EyePin.Eyes(centers: [SIMD3(-0.0022, -0.0271, -0.0203), SIMD3(0.0022, -0.0271, -0.0203)],
                                size: 0.0012)
        XCTAssertTrue(EyePin.plausible(shiba, extent: 0.05))
        // Один «глаз», огромный, слипшиеся, разнесённые на всю модель — не глаза.
        XCTAssertFalse(EyePin.plausible(EyePin.Eyes(centers: [.zero], size: 0.001), extent: 0.05))
        XCTAssertFalse(EyePin.plausible(EyePin.Eyes(centers: shiba.centers, size: 0.02), extent: 0.05))
        XCTAssertFalse(EyePin.plausible(EyePin.Eyes(centers: [.zero, SIMD3(0.0005, 0, 0)], size: 0.001), extent: 0.05))
        XCTAssertFalse(EyePin.plausible(EyePin.Eyes(centers: [.zero, SIMD3(0.04, 0, 0)], size: 0.001), extent: 0.05))
        XCTAssertFalse(EyePin.plausible(shiba, extent: 0))
    }

    func testMovingBonesShibaAndOthers() throws {
        // Шиба: уши под Neck3, под Head — только челюсть и язык (лицо, не трогаем).
        let shiba = [
            "Body/Neck3", "Body/Neck3/Head", "Body/Neck3/Head/Jaw", "Body/Neck3/Head/Jaw/Tongue",
            "Body/Neck3/Head/Jaw/Tongue/TongueTip", "Body/Neck3/Ear1_L", "Body/Neck3/Ear1_L/Ear2_L",
            "Body/Neck3/Ear1_R", "Body/Neck3/Ear1_R/Ear2_R", "Body/Tail1",
        ]
        XCTAssertEqual(EyePin.movingBones(shiba, head: 1), [5, 6, 7, 8])
        // Другая модель: уши под головой с другим регистром и кончиком, рог, глаз-кость.
        let other = ["Root", "Root/head", "Root/head/EarLeft", "Root/head/EarLeft/tip", "Root/head/horn",
                     "Root/head/eye.L", "Root/head/jaw_lower"]
        XCTAssertEqual(EyePin.movingBones(other, head: 1), [2, 3, 4])
        XCTAssertNil(EyePin.movingBones(["Root", "Root/Head"], head: 1))
        XCTAssertNil(EyePin.movingBones(shiba, head: 99))
    }
}
