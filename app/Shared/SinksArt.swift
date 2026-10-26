// Волна 35 L: иконки вещей из ScrapSinks (находки мест и эксклюзивы мест) в стиле ItemArt — плоские фигуры
// в квадрате 0…1, y вниз. ItemArt.layers ищет здесь, если своей строки нет. Тут же 3D-фигура шапки-дуршлага.

import Foundation

enum SinksArt {
    // MARK: построители (как в ItemArt — там они private)

    private static func L(_ s: ArtShape, _ c: UInt32) -> ArtLayer { ArtLayer(shape: s, color: c) }
    private static func p(_ pts: [(Double, Double)]) -> ArtShape { .poly(pts.map { SIMD2($0.0, $0.1) }) }
    private static func c(_ x: Double, _ y: Double, _ r: Double) -> ArtShape { .circle(SIMD2(x, y), r) }
    private static func e(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> ArtShape {
        .ellipse(SIMD2(x, y), rx: rx, ry: ry)
    }
    private static func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ k: Double = 0) -> ArtShape {
        .rect(x, y, w, h, corner: k)
    }
    /// Звезда из n лучей, первый вверх.
    private static func star(_ x: Double, _ y: Double, _ r1: Double, _ r2: Double, n: Int = 5) -> ArtShape {
        .poly((0..<(2 * n)).map { k in
            let a = Double(k) * .pi / Double(n) - .pi / 2
            let rr = k % 2 == 0 ? r1 : r2
            return SIMD2(x + rr * cos(a), y + rr * sin(a))
        })
    }
    /// Верхняя половина эллипса.
    private static func dome(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> ArtShape {
        .poly((0...12).map { k in
            let a = Double.pi + Double.pi * Double(k) / 12
            return SIMD2(x + rx * cos(a), y + ry * sin(a))
        })
    }

    // MARK: иконки

    static let table: [String: [ArtLayer]] = {
        var t: [String: [ArtLayer]] = [:]

        // Находки мест
        t["found_key"] = [
            L(c(0.3, 0.38, 0.17), 0xD9A43A),
            L(c(0.3, 0.38, 0.07), 0x7A5A1E),
            L(r(0.44, 0.34, 0.46, 0.08, 0.02), 0xD9A43A),
            L(r(0.72, 0.42, 0.06, 0.12), 0xD9A43A),
            L(r(0.83, 0.42, 0.06, 0.17), 0xD9A43A),
        ]
        t["found_twin_sock"] = [
            L(p([(0.16, 0.12), (0.36, 0.12), (0.36, 0.6), (0.48, 0.72), (0.42, 0.84), (0.18, 0.76), (0.16, 0.6)]), 0xF4F1EA),
            L(p([(0.5, 0.12), (0.7, 0.12), (0.7, 0.6), (0.82, 0.72), (0.76, 0.84), (0.52, 0.76), (0.5, 0.6)]), 0xF4F1EA),
            L(r(0.16, 0.12, 0.2, 0.08), 0xE2554B),
            L(r(0.5, 0.12, 0.2, 0.08), 0xE2554B),
        ]
        t["found_cat_dream"] = [
            L(r(0.3, 0.72, 0.4, 0.14, 0.03), 0x6B4428),
            L(c(0.5, 0.44, 0.3), 0x8E6BBF),
            L(c(0.4, 0.34, 0.07), 0xD8C8F0),
            L(star(0.6, 0.5, 0.08, 0.035), 0xF2C14E),
        ]
        t["found_pixel_ball"] = [
            L(c(0.5, 0.5, 0.38), 0xF2C94C),
            L(r(0.3, 0.32, 0.1, 0.1), 0x3D6FD1),
            L(r(0.55, 0.26, 0.1, 0.1), 0x3D6FD1),
            L(r(0.43, 0.5, 0.1, 0.1), 0x3D6FD1),
            L(r(0.64, 0.56, 0.1, 0.1), 0x3D6FD1),
            L(r(0.27, 0.6, 0.1, 0.1), 0x3D6FD1),
        ]
        t["found_static_jar"] = [
            L(r(0.25, 0.24, 0.5, 0.62, 0.08), 0xBFD9E0),
            L(r(0.3, 0.14, 0.4, 0.1, 0.02), 0x8A5A3B),
            L(r(0.32, 0.4, 0.18, 0.04), 0x6E7681),
            L(r(0.45, 0.5, 0.22, 0.04), 0x6E7681),
            L(r(0.33, 0.6, 0.26, 0.04), 0x6E7681),
            L(r(0.5, 0.7, 0.15, 0.04), 0x6E7681),
        ]
        t["found_light"] = [
            L(star(0.46, 0.54, 0.38, 0.13, n: 4), 0xFFD36B),
            L(c(0.46, 0.54, 0.08), 0xFFF6D8),
            L(star(0.78, 0.2, 0.12, 0.045, n: 4), 0xFFE9A8),
        ]
        t["found_letter"] = [
            L(r(0.12, 0.25, 0.76, 0.5, 0.04), 0xF6E7D2),
            L(p([(0.12, 0.25), (0.88, 0.25), (0.5, 0.55)]), 0xE3D2B6),
            L(c(0.5, 0.53, 0.07), 0xC2433A),
        ]
        t["found_moon_stone"] = [
            L(e(0.5, 0.55, 0.36, 0.3), 0x5C6370),
            L(c(0.4, 0.5, 0.07), 0x454B55),
            L(c(0.63, 0.6, 0.05), 0x454B55),
            L(c(0.5, 0.7, 0.04), 0x454B55),
            L(e(0.38, 0.4, 0.08, 0.04), 0x9AA3B0),
        ]

        // Эксклюзивы мест
        t["place_route_sign"] = [
            L(r(0.46, 0.35, 0.08, 0.53), 0x6E7681),
            L(r(0.36, 0.84, 0.28, 0.07, 0.02), 0x4A4F57),
            L(c(0.5, 0.3, 0.24), 0x3D6FD1),
            L(c(0.5, 0.3, 0.17), 0xF6F2E6),
            L(e(0.5, 0.3, 0.07, 0.1), 0x3D6FD1),
            L(e(0.5, 0.3, 0.035, 0.065), 0xF6F2E6),
        ]
        t["place_towel_scarf"] = [
            L(r(0.12, 0.24, 0.76, 0.18, 0.06), 0xF4F1EA),
            L(r(0.58, 0.34, 0.18, 0.52, 0.04), 0xF4F1EA),
            L(r(0.12, 0.3, 0.76, 0.05), 0x5B8FE0),
            L(r(0.58, 0.74, 0.18, 0.05), 0x5B8FE0),
        ]
        t["place_cat_pillow"] = [
            L(p([(0.2, 0.44), (0.26, 0.16), (0.44, 0.36)]), 0xF0A35E),
            L(p([(0.56, 0.36), (0.74, 0.16), (0.8, 0.44)]), 0xF0A35E),
            L(r(0.14, 0.34, 0.72, 0.46, 0.14), 0xF0A35E),
            L(c(0.38, 0.55, 0.04), 0x3A2A22),
            L(c(0.62, 0.55, 0.04), 0x3A2A22),
            L(p([(0.46, 0.62), (0.54, 0.62), (0.5, 0.67)]), 0xC2433A),
        ]
        t["place_mini_arcade"] = [
            L(r(0.25, 0.1, 0.5, 0.82, 0.05), 0x8E6BBF),
            L(r(0.32, 0.18, 0.36, 0.28, 0.03), 0x1F2A44),
            L(r(0.45, 0.28, 0.1, 0.08), 0xF2C94C),
            L(r(0.28, 0.52, 0.44, 0.11, 0.02), 0x5A3F86),
            L(c(0.4, 0.575, 0.035), 0xE2554B),
            L(c(0.6, 0.575, 0.03), 0xF2C14E),
        ]
        t["place_tv_lamp"] = [
            L(p([(0.47, 0.23), (0.3, 0.07), (0.33, 0.05), (0.5, 0.21)]), 0x3A2A22),
            L(p([(0.53, 0.23), (0.7, 0.07), (0.67, 0.05), (0.5, 0.21)]), 0x3A2A22),
            L(r(0.24, 0.72, 0.06, 0.12), 0x3A2A22),
            L(r(0.7, 0.72, 0.06, 0.12), 0x3A2A22),
            L(r(0.15, 0.22, 0.7, 0.52, 0.08), 0x8A5A3B),
            L(r(0.22, 0.3, 0.42, 0.36, 0.06), 0xFFD36B),
            L(c(0.74, 0.38, 0.04), 0x3A2A22),
            L(c(0.74, 0.54, 0.04), 0x3A2A22),
        ]
        t["place_beacon_lamp"] = [
            L(p([(0.36, 0.88), (0.64, 0.88), (0.58, 0.34), (0.42, 0.34)]), 0xF4F1EA),
            L(p([(0.38, 0.7), (0.62, 0.7), (0.609, 0.6), (0.391, 0.6)]), 0xD24B45),
            L(p([(0.402, 0.5), (0.598, 0.5), (0.589, 0.42), (0.411, 0.42)]), 0xD24B45),
            L(r(0.4, 0.2, 0.2, 0.14, 0.02), 0xFFD36B),
            L(p([(0.36, 0.21), (0.64, 0.21), (0.5, 0.08)]), 0xD24B45),
        ]
        t["place_well_bank"] = [
            L(r(0.24, 0.2, 0.06, 0.32), 0x8A5A3B),
            L(r(0.7, 0.2, 0.06, 0.32), 0x8A5A3B),
            L(p([(0.16, 0.24), (0.84, 0.24), (0.5, 0.08)]), 0xC2433A),
            L(r(0.2, 0.5, 0.6, 0.38, 0.05), 0x9AA3B0),
            L(r(0.2, 0.63, 0.6, 0.03), 0x7A828E),
            L(r(0.2, 0.76, 0.6, 0.03), 0x7A828E),
            L(r(0.42, 0.54, 0.16, 0.04, 0.02), 0x3A2A22),
            L(c(0.5, 0.42, 0.07), 0xF2C14E),
        ]
        t["place_colander"] = [
            L(dome(0.5, 0.62, 0.34, 0.4), 0xB9C2CC),
            L(c(0.38, 0.48, 0.03), 0x6E7681),
            L(c(0.5, 0.42, 0.03), 0x6E7681),
            L(c(0.62, 0.48, 0.03), 0x6E7681),
            L(c(0.44, 0.33, 0.03), 0x6E7681),
            L(c(0.56, 0.33, 0.03), 0x6E7681),
            L(r(0.1, 0.6, 0.8, 0.08, 0.03), 0x9AA3B0),
            L(r(0.03, 0.58, 0.1, 0.06, 0.03), 0xE2554B),
            L(r(0.87, 0.58, 0.1, 0.06, 0.03), 0xE2554B),
        ]
        return t
    }()
}

extension WearMesh {
    /// Шапка-дуршлаг (волна 35 L, эксклюзив ракеты): железный купол на макушке, спереди и сзади красные ручки,
    /// сверху красное колечко-донце. Ручки не по бокам — там уши.
    static func colander() -> [WearPart] {
        var bowl = WearPart(headJoint)
        var trim = WearPart(headJoint, accent: true)
        let base = crown + SIMD3(0, 0.02, -0.02)
        let n = 10
        func ring(_ r: Float, _ y: Float) -> [SIMD3<Float>] {
            (0..<n).map { k in
                let a = (Float(k) + 0.5) / Float(n) * 2 * .pi
                return base + SIMD3(r * cos(a), y, r * sin(a))
            }
        }
        let rim = ring(0.32, 0), mid = ring(0.29, 0.12), top = ring(0.19, 0.22)
        let peak = base + SIMD3(0, 0.25, 0)
        for k in 0..<n {
            let j = (k + 1) % n
            bowl.quad(rim[k], rim[j], mid[j], mid[k])
            bowl.quad(mid[k], mid[j], top[j], top[k])
            bowl.tri(top[k], top[j], peak)
            bowl.tri(rim[j], rim[k], base)
        }
        for s: Float in [-1, 1] {
            trim.box(base + SIMD3(0, 0.05, s * 0.37), SIMD3(0.06, 0.025, 0.06))
        }
        trim.box(peak + SIMD3(0, 0.01, 0), SIMD3(0.07, 0.02, 0.07))
        return [bowl, trim]
    }
}
