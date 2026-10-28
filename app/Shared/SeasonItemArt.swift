// Волна 40 F: иконки сезонных вещей (Seasons) в стиле ItemArt — плоские фигуры в квадрате 0…1, y вниз.
// ItemArt.layers ищет здесь, если своей строки и строки SinksArt нет.

import Foundation

enum SeasonItemArt {
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
    /// Верхняя половина эллипса.
    private static func dome(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> ArtShape {
        .poly((0...12).map { k in
            let a = Double.pi + Double.pi * Double(k) / 12
            return SIMD2(x + rx * cos(a), y + ry * sin(a))
        })
    }
    /// Кленовый лист: пять лопастей вокруг центра.
    private static func leaf(_ x: Double, _ y: Double, _ s: Double) -> ArtShape {
        .poly((0..<10).map { k in
            let a = Double(k) * .pi / 5 - .pi / 2
            let rr = k % 2 == 0 ? s : s * 0.45
            return SIMD2(x + rr * cos(a), y + rr * sin(a))
        })
    }

    // MARK: иконки

    static let table: [String: [ArtLayer]] = {
        var t: [String: [ArtLayer]] = [:]

        // Зима
        t["season_pompom_hat"] = [
            L(dome(0.5, 0.7, 0.32, 0.4), 0xF2EEE6),
            L(r(0.14, 0.62, 0.72, 0.16, 0.05), 0xD9483F),
            L(r(0.3, 0.42, 0.4, 0.06), 0xD9483F),
            L(c(0.5, 0.22, 0.11), 0xD9483F),
        ]
        t["season_snow_globe"] = [
            L(p([(0.22, 0.86), (0.78, 0.86), (0.7, 0.7), (0.3, 0.7)]), 0x7A5A3A),
            L(c(0.5, 0.44, 0.3), 0xBFE3F2),
            L(p([(0.36, 0.62), (0.5, 0.36), (0.64, 0.62)]), 0x4E8A5A),
            L(c(0.36, 0.3, 0.03), 0xFFFFFF),
            L(c(0.62, 0.26, 0.03), 0xFFFFFF),
            L(c(0.68, 0.46, 0.03), 0xFFFFFF),
        ]

        // Весна
        t["season_dandelion_wreath"] = [
            L(c(0.5, 0.5, 0.34), 0x6FAE4E),
            L(c(0.5, 0.5, 0.22), 0xF7F3EA),
            L(c(0.5, 0.17, 0.08), 0xF2CF3A),
            L(c(0.2, 0.62, 0.08), 0xF2CF3A),
            L(c(0.8, 0.62, 0.08), 0xF2CF3A),
            L(c(0.5, 0.84, 0.08), 0xF2CF3A),
        ]
        t["season_tulip_pot"] = [
            L(p([(0.28, 0.62), (0.72, 0.62), (0.66, 0.9), (0.34, 0.9)]), 0xC0643A),
            L(r(0.36, 0.34, 0.04, 0.3), 0x5E9E46),
            L(r(0.6, 0.38, 0.04, 0.26), 0x5E9E46),
            L(p([(0.28, 0.36), (0.32, 0.16), (0.38, 0.26), (0.44, 0.16), (0.48, 0.36)]), 0xE2554B),
            L(p([(0.52, 0.4), (0.56, 0.2), (0.62, 0.3), (0.68, 0.2), (0.72, 0.4)]), 0xF2B8C6),
        ]

        // Лето
        t["season_sun_bandana"] = [
            L(p([(0.12, 0.3), (0.88, 0.3), (0.5, 0.86)]), 0x3FA7D6),
            L(c(0.5, 0.46, 0.11), 0xF5C542),
            L(r(0.12, 0.26, 0.76, 0.08, 0.03), 0x2E86B0),
        ]
        t["season_sand_bucket"] = [
            L(p([(0.24, 0.36), (0.76, 0.36), (0.68, 0.86), (0.32, 0.86)]), 0x3FA7D6),
            L(r(0.22, 0.32, 0.56, 0.08, 0.03), 0x2E86B0),
            L(dome(0.5, 0.34, 0.22, 0.16), 0xE9CF94),
            L(p([(0.5, 0.52), (0.4, 0.72), (0.6, 0.72)]), 0xF6C7B6),
        ]

        // Осень
        t["season_leaf_scarf"] = [
            L(r(0.16, 0.3, 0.68, 0.16, 0.06), 0xD9772E),
            L(r(0.56, 0.4, 0.16, 0.44, 0.04), 0xD9772E),
            L(leaf(0.34, 0.38, 0.09), 0x9C3B2A),
            L(leaf(0.64, 0.7, 0.08), 0xF2B01E),
        ]
        t["season_mushroom_basket"] = [
            L(p([(0.16, 0.54), (0.84, 0.54), (0.74, 0.88), (0.26, 0.88)]), 0xB07A3E),
            L(r(0.36, 0.42, 0.06, 0.14), 0xF4ECD8),
            L(dome(0.39, 0.44, 0.14, 0.14), 0xC8323C),
            L(r(0.58, 0.44, 0.06, 0.12), 0xF4ECD8),
            L(dome(0.61, 0.46, 0.12, 0.12), 0x8A5A2E),
            L(r(0.16, 0.54, 0.68, 0.05), 0x8A5A2E),
        ]
        return t
    }()
}
