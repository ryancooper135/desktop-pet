// Волна 35 L: миниатюры вещей мест на полке и узор «пиксель» у мячика из аркады.
// Свой файл, чтобы не раздувать RoomDecor: детали без кэша мешей — на полке одна вещь за раз.

import RealityKit
import UIKit

extension RoomDecor {
    /// Цвета вещей мест. Свечение — тот же DecorColors.lamp: вечером его не гасит свет комнаты.
    private enum SinkColors {
        static let brass: UInt32 = 0xd9b45a
        static let sock: UInt32 = 0xf4f1ea
        static let sockStripe: UInt32 = 0x5b8fe0
        static let dream: UInt32 = 0xb7a4f0
        static let dreamBase: UInt32 = 0x6b5a9e
        static let glass: UInt32 = 0xe3eef2
        static let staticGrey: UInt32 = 0x9aa3ad
        static let paper: UInt32 = 0xf5ecd8
        static let seal: UInt32 = 0xd9534f
        static let moonStone: UInt32 = 0x4a4f63
        static let moonDot: UInt32 = 0xc9cfdd
        static let signGreen: UInt32 = 0x3f8f5a
        static let pole: UInt32 = 0x8c96a0
        static let catOrange: UInt32 = 0xf2a65a
        static let catDark: UInt32 = 0x5a3a28
        static let arcade: UInt32 = 0x3d6fd1
        static let screen: UInt32 = 0x1d2433
        static let tv: UInt32 = 0x8c6a4a
        static let beaconRed: UInt32 = 0xe2554b
        static let stone: UInt32 = 0xa9a39a
        static let coin: UInt32 = 0xf2c94c
    }

    /// Деталь на полке. Свечение по DecorColors.glows, как у остальных вещей комнаты.
    @discardableResult
    private static func sinkPart(_ mesh: MeshResource, _ hex: UInt32, _ pos: SIMD3<Float>, in parent: Entity,
                                 scale: SIMD3<Float> = .one, shade: CGFloat = 1) -> ModelEntity {
        let e = ModelEntity(mesh: mesh, materials: [PetRoom.matteMaterial(hex, shade: shade)])
        e.position = pos
        e.scale = scale
        if DecorColors.glows.contains(hex) { e.components.set(RoomGlow()) }
        parent.addChild(e)
        return e
    }

    private static func sBox(_ x: Float, _ y: Float, _ z: Float) -> MeshResource { .generateBox(size: [x, y, z]) }
    private static func sCyl(_ h: Float, _ r: Float) -> MeshResource { .generateCylinder(height: h, radius: r) }
    private static func sBall(_ r: Float) -> MeshResource { .generateSphere(radius: r) }
    private static func sCone(_ h: Float, _ r: Float) -> MeshResource { .generateCone(height: h, radius: r) }

    /// Вещь места на полке: sx — середина, y — верх доски, z — глубина. false — id не наш.
    static func sinksShelf(_ id: String, sx: Float, y: Float, z: Float, in g: Entity) -> Bool {
        typealias C = SinkColors
        let lamp = DecorColors.lamp
        let side = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        switch id {
        case "found_key":
            // Ключ лёжа: кольцо-ушко, стержень и бородка.
            sinkPart(sCyl(0.006, 0.013), C.brass, [sx - 0.02, y + 0.003, z], in: g)
            sinkPart(sCyl(0.007, 0.006), DecorColors.wood, [sx - 0.02, y + 0.004, z], in: g)
            sinkPart(sBox(0.04, 0.006, 0.007), C.brass, [sx + 0.01, y + 0.003, z], in: g)
            sinkPart(sBox(0.006, 0.006, 0.014), C.brass, [sx + 0.026, y + 0.003, z + 0.008], in: g, shade: 0.9)
        case "found_twin_sock":
            // Носок стоя: голенище, пятка-стопа и полоски.
            sinkPart(sBox(0.022, 0.042, 0.016), C.sock, [sx, y + 0.021, z], in: g)
            sinkPart(sBox(0.034, 0.014, 0.016), C.sock, [sx + 0.006, y + 0.007, z], in: g, shade: 0.95)
            for dy: Float in [0.032, 0.04] {
                sinkPart(sBox(0.023, 0.004, 0.017), C.sockStripe, [sx, y + dy, z], in: g)
            }
        case "found_cat_dream":
            // Шар сна на подставке, внутри огонёк.
            sinkPart(sCyl(0.008, 0.016), C.dreamBase, [sx, y + 0.004, z], in: g)
            sinkPart(sBall(0.022), C.dream, [sx, y + 0.028, z], in: g)
            sinkPart(sBall(0.006), lamp, [sx + 0.006, y + 0.032, z + 0.018], in: g)
        case "found_static_jar":
            // Банка с «помехой»: серые полосы внутри и крышка.
            sinkPart(sCyl(0.044, 0.018), C.glass, [sx, y + 0.022, z], in: g)
            for (dy, dx) in [(0.012, -0.004), (0.022, 0.003), (0.032, -0.002)] as [(Float, Float)] {
                sinkPart(sBox(0.026, 0.004, 0.002), C.staticGrey, [sx + dx, y + dy, z + 0.018], in: g)
            }
            sinkPart(sCyl(0.008, 0.019), DecorColors.jarLidGreen, [sx, y + 0.048, z], in: g)
        case "found_light":
            // Кусочек света: светящийся кристалл-ромб на подставке.
            sinkPart(sCyl(0.008, 0.016), DecorColors.wood, [sx, y + 0.004, z], in: g)
            let gem = sinkPart(sBox(0.024, 0.024, 0.024), lamp, [sx, y + 0.03, z], in: g)
            gem.orientation = simd_quatf(angle: .pi / 4, axis: [0, 0, 1]) * simd_quatf(angle: .pi / 4, axis: [0, 1, 0])
        case "found_letter":
            // Конверт стоя, прислонён к стене, с сургучом.
            let env = sinkPart(sBox(0.05, 0.034, 0.004), C.paper, [sx, y + 0.017, z - 0.01], in: g)
            env.orientation = simd_quatf(angle: -0.18, axis: [1, 0, 0])
            sinkPart(sCyl(0.003, 0.006), C.seal, [sx, y + 0.02, z - 0.005], in: g).orientation =
                simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        case "found_moon_stone":
            // Тёмный камень с лунными кратерами.
            sinkPart(sBall(0.022), C.moonStone, [sx, y + 0.017, z], in: g, scale: [1.2, 0.8, 1])
            for d: SIMD3<Float> in [[-0.01, 0.026, 0.012], [0.012, 0.022, 0.014], [0.002, 0.03, 0.002]] {
                sinkPart(sBall(0.005), C.moonDot, [sx + d.x, y + d.y, z + d.z], in: g, scale: [1, 0.5, 1])
            }
        case "place_route_sign":
            // Табличка остановки на ножке.
            sinkPart(sBox(0.024, 0.004, 0.016), C.pole, [sx, y + 0.002, z], in: g)
            sinkPart(sCyl(0.05, 0.002), C.pole, [sx, y + 0.025, z], in: g)
            sinkPart(sBox(0.04, 0.024, 0.004), C.signGreen, [sx, y + 0.05, z + 0.003], in: g)
            sinkPart(sBox(0.012, 0.012, 0.001), DecorColors.white, [sx, y + 0.05, z + 0.0055], in: g)
        case "place_cat_pillow":
            // Подушка-котик: валик, ушки и полоски.
            sinkPart(sBox(0.06, 0.024, 0.034), C.catOrange, [sx, y + 0.012, z], in: g)
            for dx: Float in [-0.02, 0.02] {
                sinkPart(sCone(0.014, 0.008), C.catOrange, [sx + dx, y + 0.031, z], in: g, shade: 0.9)
            }
            for dx: Float in [-0.012, 0, 0.012] {
                sinkPart(sBox(0.004, 0.025, 0.035), C.catDark, [sx + dx, y + 0.012, z], in: g, shade: 1.1)
            }
        case "place_mini_arcade":
            // Мини-автомат: корпус, экран со светом и две кнопки.
            sinkPart(sBox(0.036, 0.06, 0.03), C.arcade, [sx, y + 0.03, z], in: g)
            sinkPart(sBox(0.026, 0.02, 0.002), C.screen, [sx, y + 0.044, z + 0.016], in: g)
            sinkPart(sBox(0.014, 0.008, 0.001), lamp, [sx, y + 0.044, z + 0.0175], in: g)
            for dx: Float in [-0.007, 0.007] {
                sinkPart(sBall(0.003), DecorColors.roof, [sx + dx, y + 0.026, z + 0.016], in: g)
            }
        case "place_tv_lamp":
            // Пузатый телевизор, светящийся экран и рожки.
            sinkPart(sBox(0.05, 0.04, 0.03), C.tv, [sx, y + 0.02, z], in: g)
            sinkPart(sBox(0.034, 0.026, 0.002), lamp, [sx - 0.004, y + 0.021, z + 0.016], in: g)
            for a: Float in [-0.5, 0.5] {
                let ant = sinkPart(sCyl(0.026, 0.0015), C.pole, [sx + a * 0.02, y + 0.05, z], in: g)
                ant.orientation = simd_quatf(angle: -a, axis: [0, 0, 1])
            }
        case "place_beacon_lamp":
            // Маяк-лампа: полосатая башенка и светящаяся верхушка.
            for (k, c) in [DecorColors.white, C.beaconRed, DecorColors.white].enumerated() {
                sinkPart(sCyl(0.014, 0.014 - Float(k) * 0.002), c, [sx, y + 0.007 + Float(k) * 0.014, z], in: g)
            }
            sinkPart(sCyl(0.012, 0.009), lamp, [sx, y + 0.048, z], in: g)
            sinkPart(sCone(0.012, 0.012), C.beaconRed, [sx, y + 0.06, z], in: g)
        case "place_well_bank":
            // Колодец-копилка: каменный сруб, крыша на стойках и монетка.
            sinkPart(sCyl(0.022, 0.02), C.stone, [sx, y + 0.011, z], in: g)
            sinkPart(sCyl(0.002, 0.016), C.screen, [sx, y + 0.0225, z], in: g)
            for dx: Float in [-0.017, 0.017] {
                sinkPart(sBox(0.004, 0.026, 0.004), DecorColors.wood, [sx + dx, y + 0.035, z], in: g)
            }
            let roof = sinkPart(sBox(0.046, 0.004, 0.03), DecorColors.roof, [sx, y + 0.05, z], in: g)
            roof.orientation = simd_quatf(angle: 0.05, axis: [0, 0, 1])
            sinkPart(sCyl(0.002, 0.005), C.coin, [sx + 0.006, y + 0.032, z], in: g).orientation = side
        default:
            return false
        }
        return true
    }

    /// Мячик-пиксель: кубики второго цвета по сфере, как пиксели старой игры.
    static func sinksPixelSkin(_ toy: ToyInfo, r: Float, in skin: Entity) {
        let dirs: [SIMD3<Float>] = [[0, 1, 0], [0.7, 0.5, 0.5], [-0.7, 0.45, 0.55], [0.15, 0.3, 0.95],
                                    [0.6, -0.2, -0.75], [-0.55, 0.1, -0.8], [0.95, -0.25, 0.15], [-0.9, -0.3, 0.2],
                                    [0, -0.6, 0.8], [0.2, 0.75, -0.6]]
        for d in dirs {
            let v = simd_normalize(d)
            let e = sinkPart(sBox(0.016, 0.016, 0.016), toy.accent, v * r, in: skin)
            e.orientation = simd_quatf(from: [0, 1, 0], to: v)
        }
    }
}
