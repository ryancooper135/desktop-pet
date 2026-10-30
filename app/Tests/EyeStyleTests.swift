// Живые глаза (волна 50, EyeStyle): варианты бликов, где встаёт блик и шов закрытого глаза.

import XCTest
@testable import Pet

final class EyeStyleTests: XCTestCase {
    private func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { (a * b).sum() }
    private func len(_ a: SIMD3<Float>) -> Float { dot(a, a).squareRoot() }

    // Глаз смотрит на -z (вперёд у Шибы в системе меша), «вверх» сцены — -y.
    private let n = SIMD3<Float>(0, 0, -1)
    private let sceneUp = SIMD3<Float>(0, -1, 0)

    func testDefaultVariantAndSpots() {
        XCTAssertEqual(EyeStyle.variant, .a)
        XCTAssertEqual(EyeStyle.spots(.a).count, 1)
        XCTAssertEqual(EyeStyle.spots(.b).count, 2)
        for v in EyeStyle.Variant.allCases {
            for s in EyeStyle.spots(v) {
                XCTAssertGreaterThan(s.scale, 0)
                XCTAssertLessThan(s.scale, 0.5, "блик меньше половины глаза")
                // Блик внутри глаза: центр пятна + радиус не дальше края.
                XCTAssertLessThanOrEqual((s.up * s.up + s.left * s.left).squareRoot() + s.scale / 2, 0.5 + 1e-4)
            }
        }
        // Б: второй блик мельче первого и с другой стороны.
        let b = EyeStyle.spots(.b)
        XCTAssertLessThan(b[1].scale, b[0].scale)
        XCTAssertLessThan(b[1].up * b[0].up, 0)
    }

    func testAxesAreOrthonormal() throws {
        let ax = try XCTUnwrap(EyeStyle.axes(normal: n, sceneUp: sceneUp))
        XCTAssertEqual(len(ax.up), 1, accuracy: 1e-5)
        XCTAssertEqual(len(ax.left), 1, accuracy: 1e-5)
        XCTAssertEqual(dot(ax.up, n), 0, accuracy: 1e-5)
        XCTAssertEqual(dot(ax.left, n), 0, accuracy: 1e-5)
        XCTAssertEqual(dot(ax.up, ax.left), 0, accuracy: 1e-5)
        XCTAssertEqual(dot(ax.up, sceneUp), 1, accuracy: 1e-5)
        // Наклонная нормаль — up всё равно в плоскости глаза.
        let tilted = SIMD3<Float>(0.3, -0.2, -0.9) / len(SIMD3<Float>(0.3, -0.2, -0.9))
        let t = try XCTUnwrap(EyeStyle.axes(normal: tilted, sceneUp: sceneUp))
        XCTAssertEqual(dot(t.up, tilted), 0, accuracy: 1e-5)
        XCTAssertGreaterThan(dot(t.up, sceneUp), 0)
        // Глаз смотрит вверх — плоскости нет.
        XCTAssertNil(EyeStyle.axes(normal: sceneUp, sceneUp: sceneUp))
    }

    func testPlaceSitsInFrontAndOffset() throws {
        let ax = try XCTUnwrap(EyeStyle.axes(normal: n, sceneUp: sceneUp))
        let c = SIMD3<Float>(0.0022, -0.0271, -0.0203)
        let size: Float = 0.0012, top: Float = 0.0002
        let spot = EyeStyle.spots(.a)[0]
        // Диск-источник радиусом 0,3 размера вокруг src, немного выпуклый.
        let src = c + n * 0.0001
        let r = 0.3 * size
        var out: [SIMD3<Float>] = []
        for k in 0..<12 {
            let a = Float(k) / 12 * 2 * .pi
            let p = src + ax.left * (cos(a) * r) + ax.up * (sin(a) * r) + n * (0.00003 * Float(k % 2))
            out.append(EyeStyle.place(p, source: src, sourceSize: 2 * r, center: c, normal: n, up: ax.up,
                                      left: ax.left, size: size, top: top, spot: spot))
        }
        for q in out {
            // Плоско и впереди самой выпуклой точки глаза.
            XCTAssertEqual(dot(q - c, n), top + EyeStyle.lift * size, accuracy: 1e-7)
        }
        let mid = out.reduce(SIMD3<Float>.zero, +) / Float(out.count)
        XCTAssertEqual(dot(mid - c, ax.up), spot.up * size, accuracy: 1e-7)
        XCTAssertEqual(dot(mid - c, ax.left), spot.left * size, accuracy: 1e-7)
        // Диаметр — доля размера глаза.
        let width = out.map { dot($0 - mid, ax.left) }
        XCTAssertEqual((width.max() ?? 0) - (width.min() ?? 0), spot.scale * size, accuracy: 1e-7)
    }

    func testCreaseIsThinArcBelowCenter() throws {
        let ax = try XCTUnwrap(EyeStyle.axes(normal: n, sceneUp: sceneUp))
        let c = SIMD3<Float>(0, 0, 0)
        let size: Float = 1
        let front: Float = 0.2
        var ys: [Float] = [], xs: [Float] = []
        for k in 0..<24 {
            let a = Float(k) / 24 * 2 * .pi
            let p = ax.left * (cos(a) * 0.5) + ax.up * (sin(a) * 0.5)
            let q = EyeStyle.creasePoint(p, source: .zero, sourceSize: 1, center: c, normal: n, up: ax.up,
                                         left: ax.left, size: size, front: front)
            XCTAssertEqual(dot(q - c, n), front, accuracy: 1e-6)
            ys.append(dot(q - c, ax.up))
            xs.append(dot(q - c, ax.left))
        }
        XCTAssertEqual((xs.max() ?? 0) - (xs.min() ?? 0), EyeStyle.creaseWidth * size, accuracy: 1e-4)
        // Тонкая: по высоте не больше шва и изгиба.
        XCTAssertLessThanOrEqual((ys.max() ?? 0) - (ys.min() ?? 0), (EyeStyle.creaseHeight + 0.1) * size + 1e-4)
        // Середина ниже центра глаза.
        let midY = ys.reduce(0, +) / Float(ys.count)
        XCTAssertLessThan(midY, 0.05 * size)
    }

    func testColorsReadAsEyes() {
        func bright(_ hex: UInt32) -> Int { Int(hex >> 16 & 0xFF) + Int(hex >> 8 & 0xFF) + Int(hex & 0xFF) }
        // Зрачок темнее радужки, ободок темнее радужки, блик — самый светлый.
        XCTAssertLessThan(bright(EyeStyle.pupil), bright(EyeStyle.iris))
        XCTAssertLessThan(bright(EyeStyle.rim), bright(EyeStyle.iris))
        XCTAssertGreaterThan(bright(EyeStyle.glint), 700)
        // Радужка тёплая: красного больше синего.
        XCTAssertGreaterThan(EyeStyle.iris >> 16 & 0xFF, EyeStyle.iris & 0xFF)
    }
}
