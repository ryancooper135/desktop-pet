// Декор районов двора (волна 36 Q): то, что стоит в квартале кроме станций и плит. Тот же плоский low-poly, что
// у подложек ярусов (YardModels.swift), только Foundation — треугольники считаются чистой функцией.
// Декор зависит от верхнего нарисованного слоя (сад, парк и квартал раздвигают края) и от купленных плит
// (шапка снега на скамейке есть, только если скамейка стоит). Места выбраны мимо станций (YardArtTier.slots)
// и предметов плит, чтобы ничего не стояло друг в друге.

import Foundation

/// Цвета декора, которых нет в палитре района.
enum YardDecorColors {
    static let snow: UInt32 = 0xf7fafc
    static let ice: UInt32 = 0xdceff8
    static let flake: UInt32 = 0xffffff
    static let bulbs: [UInt32] = [0xffd36b, 0xe86a6a, 0x6aa5e8, 0x8fe388]
    static let plank: UInt32 = 0xb07a4e
    static let plankDark: UInt32 = 0x8a5a3c
    static let ripple: UInt32 = 0xe6f5fb
    static let reed: UInt32 = 0x6f9a4a
    static let cattail: UInt32 = 0x6b4a2e
    static let duck: UInt32 = 0xf7f3ea
    static let duckHead: UInt32 = 0x3f7a5a
    static let beak: UInt32 = 0xf0a04b
    static let buoyRed: UInt32 = 0xe05a4a
    static let brick: UInt32 = 0xa0523d
    static let coping: UInt32 = 0xd3cec3
    static let metal: UInt32 = 0x9aa6ad
    static let metalDark: UInt32 = 0x6f7a82
    static let tin: UInt32 = 0xc3ccd2
    static let beacon: UInt32 = 0xff4a3a
    static let tank: UInt32 = 0x8a6a52
    static let city: UInt32 = 0xd8b6a6
    static let cityNight: UInt32 = 0x3a3352
}

extension YardArtTier {
    /// Декор района при виде до слоя top (как в сцене: слои 0…max(ярус, 1)). bought — купленные плиты по слоям
    /// (YardArtTier.bought / YardLive.bought), нужны только для шапок снега на вещах плит. У улицы декора нет.
    static func decor(_ district: YardDistrict, top: Int, bought: [Int] = [], night: Bool = false) -> YardArtModel {
        var m = YardArtModel(name: "decor.\(district.rawValue)")
        let ctx = YardDecorCtx(top: min(max(top, 1), plates.count - 1), bought: bought, night: night,
                               palette: district.palette)
        for item in district.decor {
            switch item {
            case .snowdrifts: YardDecorArt.snowdrifts(&m, ctx)
            case .firTree: YardDecorArt.firTree(&m, ctx)
            case .garland: YardDecorArt.garland(&m, ctx)
            case .snowCaps: YardDecorArt.snowCaps(&m, ctx)
            case .snowfall: YardDecorArt.snowfall(&m, ctx)
            case .river: YardDecorArt.river(&m, ctx)
            case .bridge: YardDecorArt.bridge(&m, ctx)
            case .reeds: YardDecorArt.reeds(&m, ctx)
            case .duck: YardDecorArt.duck(&m, ctx)
            case .lifebuoy: YardDecorArt.lifebuoy(&m, ctx)
            case .parapet: YardDecorArt.parapet(&m, ctx)
            case .antennas: YardDecorArt.antennas(&m, ctx)
            case .vents: YardDecorArt.vents(&m, ctx)
            case .waterTank: YardDecorArt.waterTank(&m, ctx)
            case .skyline: YardDecorArt.skyline(&m, ctx)
            }
            m.body()
        }
        return m
    }

    /// Худший декор по всем районам, слоям и ночи — для бюджета (тест и подпись превью).
    static func worstDecorTriangles() -> (district: YardDistrict, top: Int, triangles: Int) {
        var worst: (YardDistrict, Int, Int) = (.street, 1, 0)
        let full = plates.map(\.count)
        for d in YardDistrict.allCases {
            for top in 1..<plates.count {
                for night in [false, true] {
                    let t = decor(d, top: top, bought: full, night: night).triangles
                    if t > worst.2 { worst = (d, top, t) }
                }
            }
        }
        return worst
    }
}

struct YardDecorCtx {
    var top: Int
    var bought: [Int]
    var night: Bool
    var palette: YardDistrictPalette

    /// Куплена ли плита: в слое layer куплено не меньше count плит.
    func has(_ layer: Int, _ count: Int) -> Bool { layer < bought.count && bought[layer] >= count }

    /// Края нарисованной земли: парк слева с яруса 3, квартал справа с яруса 4, сад спереди с яруса 2.
    var left: Float { top >= 3 ? -2.2 : -1.2 }
    var right: Float { top >= 4 ? 2.2 : 1.2 }
    var front: Float { top >= 2 ? 1.0 : 0 }
    var width: Float { right - left }
    var midX: Float { (left + right) / 2 }
}

enum YardDecorArt {
    static let wallZ: Float = -1.8

    /// Детерминированный «случай» 0…1 по номеру и каналу — снежинки и дома города всегда на тех же местах.
    static func rnd(_ i: Int, _ k: Int) -> Float {
        let v = sin(Float(i) * 12.9898 + Float(k) * 78.233) * 43758.5453
        return v - v.rounded(.down)
    }

    // MARK: Зимний квартал

    static func snowdrifts(_ m: inout YardArtModel, _ c: YardDecorCtx) {
        var spots: [(SIMD3<Float>, Float)] = [
            (SIMD3(-1.02, 0, -1.5), 0.22), (SIMD3(1.04, 0, -1.48), 0.2), (SIMD3(-0.95, 0, -0.1), 0.15),
            (SIMD3(0.98, 0, -0.12), 0.14), (SIMD3(-0.32, 0, -1.64), 0.12),
        ]
        if c.top >= 2 { spots += [(SIMD3(-0.34, 0, 0.14), 0.12), (SIMD3(-0.55, 0, 0.93), 0.12), (SIMD3(0.45, 0, 0.95), 0.13)] }
        if c.top >= 3 { spots += [(SIMD3(-2.0, 0, -0.15), 0.2), (SIMD3(-1.4, 0, -1.15), 0.15), (SIMD3(-2.05, 0, 0.9), 0.14)] }
        if c.top >= 4 { spots += [(SIMD3(2.05, 0, -0.2), 0.18), (SIMD3(1.35, 0, -1.2), 0.14), (SIMD3(1.4, 0, 0.9), 0.13)] }
        for (i, s) in spots.enumerated() {
            m.gem(YardDecorColors.snow, sides: 5, r: s.1, h: s.1 * 0.9, at: s.0, rot: SIMD3(0, Float(i) * 23, 0),
                  scale: SIMD3(1.35, 1, 1))
        }
    }

    static let firAt = SIMD3<Float>(-1.0, 0, -0.5)
    /// Ярусы ёлки: центр по высоте, радиус низа, высота.
    static let firTiers: [(y: Float, r: Float, h: Float)] = [(0.25, 0.27, 0.3), (0.43, 0.21, 0.27), (0.6, 0.15, 0.24)]

    static func firTree(_ m: inout YardArtModel, _ c: YardDecorCtx) {
        let f = firAt
        m.prism(YardArtColors.soil, sides: 5, r: 0.04, h: 0.12, at: f + SIMD3(0, 0.06, 0))
        for t in firTiers {
            m.prism(c.palette.crown, sides: 7, r: t.r, h: t.h, top: 0, at: f + SIMD3(0, t.y, 0))
        }
        // Снег на лапах — светлое кольцо у низа каждого яруса.
        for t in firTiers.dropFirst() {
            m.prism(YardDecorColors.snow, sides: 7, r: t.r * 0.55, h: 0.03, top: t.r * 0.35,
                    at: f + SIMD3(0, t.y + t.h * 0.2, 0), bottom: false)
        }
        m.gem(YardArtColors.lamp, sides: 4, r: 0.045, h: 0.08, at: f + SIMD3(0, 0.77, 0), glow: true)
    }

    /// Гирлянда: огоньки по спирали на ёлке и нитка над окном дома (её видно уже с подоконника).
    /// Две группы мигают по очереди.
    static func garland(_ m: inout YardArtModel, _ c: YardDecorCtx) {
        var tree: [[SIMD3<Float>]] = [[], []]
        var k = 0
        for (level, t) in firTiers.enumerated() {
            let count = 6 - level
            let y = t.y - t.h / 2 + t.h * 0.22
            let r = t.r * 0.78 + 0.012
            for j in 0..<count {
                let a = Float(j) * 360 / Float(count) + Float(level) * 30
                let q = YardArtMath.rotY(SIMD3(0, 0, r), a)
                tree[k % 2].append(SIMD3(q.x, y, q.z))
                k += 1
            }
        }
        let w = SIMD3<Float>(0, 1.15, wallZ + 0.1)
        var window: [[SIMD3<Float>]] = [[], []]
        for j in 0..<6 {
            let x = -0.4 + Float(j) * 0.16
            let sag = 0.035 * sin(Float(j % 3) / 2 * .pi)
            window[j % 2].append(SIMD3(x, -sag, 0))
        }
        m.box(YardArtColors.pole, SIMD3(0.9, 0.006, 0.006), at: w + SIMD3(0, -0.012, -0.004))
        for g in 0..<2 {
            let blink = YardArtMotion.keys([YardArtKey(t: 0), YardArtKey(t: 0.42), YardArtKey(t: 0.5, scale: 0),
                                            YardArtKey(t: 0.92, scale: 0), YardArtKey(t: 1)],
                                           axis: SIMD3(0, 1, 0), period: 1.8, phase: Float(g) * 0.5)
            m.node("garland.tree\(g)", at: firAt, motion: blink)
            for (i, p) in tree[g].enumerated() {
                m.gem(YardDecorColors.bulbs[(i * 2 + g) % 4], sides: 4, r: 0.02, h: 0.03, at: p, glow: true)
            }
            m.node("garland.window\(g)", at: w, motion: blink)
            for (i, p) in window[g].enumerated() {
                m.gem(YardDecorColors.bulbs[(i * 2 + g + 1) % 4], sides: 4, r: 0.02, h: 0.032, at: p, glow: true)
            }
        }
    }

    static func snowCaps(_ m: inout YardArtModel, _ c: YardDecorCtx) {
        let snow = YardDecorColors.snow
        m.box(snow, SIMD3(2.62, 0.035, 0.32), at: SIMD3(0, 1.4975, wallZ + 0.05))
        m.box(snow, SIMD3(0.8, 0.022, 0.05), at: SIMD3(0, 1.152, wallZ + 0.075))
        // Подоконник: снег по краям (в середине сушилка и горшок) и сосульки снизу.
        for x in [Float(-0.43), 0.42] {
            m.box(snow, SIMD3(0.08, 0.02, 0.3), at: SIMD3(x, 0.51, wallZ + 0.22))
        }
        for (i, x) in [Float(-0.4), -0.22, -0.05, 0.14, 0.33].enumerated() {
            let h: Float = i % 2 == 0 ? 0.07 : 0.045
            m.prism(YardDecorColors.ice, sides: 4, r: 0.014, h: h, top: 0, at: SIMD3(x, 0.46 - h / 2, wallZ + 0.385),
                    rot: SIMD3(180, 0, 0))
        }
        if c.has(1, 2) {
            for side in [Float(-1), 1] {
                m.box(snow, SIMD3(0.9, 0.014, 0.034), at: SIMD3(0.73 * side, 0.247, 0.025))
                for x in [Float(0.3), 1.15] {
                    m.box(snow, SIMD3(0.062, 0.02, 0.052), at: SIMD3(x * side, 0.33, 0))
                }
            }
        }
        if c.top >= 2 {
            if c.has(2, 1) { m.box(snow, SIMD3(0.17, 0.016, 0.11), at: SIMD3(1.0, 0.458, 0.15)) }
            if c.has(2, 2) { m.gem(snow, sides: 7, r: 0.19, h: 0.16, at: SIMD3(-1.0, 0.86, 0.75)) }
            if c.has(2, 3) { m.box(snow, SIMD3(0.48, 0.016, 0.13), at: SIMD3(0, 0.183, 0.85)) }
        }
    }

    /// Снежинки падают сверху до земли и исчезают; у каждой свой период и фаза.
    static func snowfall(_ m: inout YardArtModel, _ c: YardDecorCtx) {
        let n = c.top <= 1 ? 12 : c.top == 2 ? 15 : 18
        let y0: Float = c.top >= 3 ? 2.0 : 1.5
        let zLo: Float = -1.6, zHi = c.front - 0.1
        for i in 0..<n {
            let x = c.left + 0.1 + (c.width - 0.2) * rnd(i, 1)
            let z = zLo + (zHi - zLo) * rnd(i, 2)
            let y = y0 * (0.8 + 0.2 * rnd(i, 3))
            let drift = SIMD3<Float>((rnd(i, 4) - 0.5) * 0.25, -y, 0)
            let fall = YardArtMotion.keys([YardArtKey(t: 0), YardArtKey(t: 0.9, offset: drift),
                                           YardArtKey(t: 0.92, offset: drift, scale: 0),
                                           YardArtKey(t: 1, offset: .zero, scale: 0)],
                                          axis: SIMD3(0, 1, 0), period: 5 + 2 * rnd(i, 5), phase: Float(i) / Float(n))
            m.node("flake\(i)", at: SIMD3(x, y, z), motion: fall)
            m.gem(YardDecorColors.flake, sides: 4, r: 0.02, h: 0.032, at: .zero)
        }
    }

    // MARK: У реки

    /// Река вдоль передней кромки: перед забором, пока сада нет, а с яруса 2 — перед садом.
    static func riverBand(_ c: YardDecorCtx) -> (near: Float, far: Float) {
        c.top >= 2 ? (1.0, 1.42) : (0.08, 0.5)
    }

    static func river(_ m: inout YardArtModel, _ c: YardDecorCtx) {
        let (near, far) = riverBand(c)
        let p = c.palette
        if c.top < 2 {
            m.box(p.ground, SIMD3(2.4, 0.04, near), at: SIMD3(0, -0.02, near / 2))
        }
        m.box(p.water, SIMD3(c.width, 0.03, far - near), at: SIMD3(c.midX, -0.027, (near + far) / 2))
        m.box(p.garden, SIMD3(c.width, 0.04, 0.24), at: SIMD3(c.midX, -0.02, far + 0.12))
        // Блики бегут по течению.
        for i in 0..<4 {
            let x = c.left + 0.2 + (c.width - 0.9) * Float(i) / 3
            let z = near + (far - near) * (0.25 + 0.5 * rnd(i, 7))
            let flow = YardArtMotion.keys([YardArtKey(t: 0, scale: 0), YardArtKey(t: 0.2, offset: SIMD3(0.12, 0, 0)),
                                           YardArtKey(t: 0.8, offset: SIMD3(0.48, 0, 0)),
                                           YardArtKey(t: 1, offset: SIMD3(0.6, 0, 0), scale: 0)],
                                          axis: SIMD3(0, 1, 0), period: 4, phase: Float(i) * 0.27)
            m.node("ripple\(i)", at: SIMD3(x, -0.009, z), motion: flow)
            m.box(YardDecorColors.ripple, SIMD3(0.16, 0.004, 0.014), at: .zero)
        }
    }

    /// Мостик напротив калитки (x = 0), доски поперёк и перила.
    static func bridge(_ m: inout YardArtModel, _ c: YardDecorCtx) {
        let (near, far) = riverBand(c)
        let z0 = (c.top >= 2 ? near : 0) - 0.04, z1 = far + 0.06
        let len = z1 - z0, zc = (z0 + z1) / 2
        m.box(YardDecorColors.plank, SIMD3(0.34, 0.03, len), at: SIMD3(0, 0.012, zc))
        for k in 1...3 {
            let z = z0 + len * Float(k) / 4
            m.box(YardDecorColors.plankDark, SIMD3(0.342, 0.006, 0.012), at: SIMD3(0, 0.029, z))
        }
        for side in [Float(-1), 1] {
            for z in [z0 + 0.03, zc, z1 - 0.03] {
                m.box(YardDecorColors.plankDark, SIMD3(0.03, 0.16, 0.03), at: SIMD3(0.16 * side, 0.09, z))
            }
            m.box(YardDecorColors.plankDark, SIMD3(0.026, 0.026, len - 0.02), at: SIMD3(0.16 * side, 0.17, zc))
        }
    }

    static func reeds(_ m: inout YardArtModel, _ c: YardDecorCtx) {
        let (near, far) = riverBand(c)
        var spots: [SIMD3<Float>] = [SIMD3(-0.95, 0, near + 0.04), SIMD3(-0.48, 0, near + 0.03),
                                     SIMD3(0.55, 0, near + 0.04), SIMD3(1.02, 0, near + 0.03),
                                     SIMD3(-0.75, 0, far - 0.03), SIMD3(0.8, 0, far - 0.03)]
        if c.top >= 3 { spots[4] = SIMD3(-1.8, 0, near + 0.04) }
        if c.top >= 4 { spots[5] = SIMD3(1.8, 0, near + 0.04) }
        for (i, s) in spots.enumerated() {
            m.node("reeds\(i)", at: s, motion: .swing(axis: SIMD3(0, 0, 1), deg: 6, period: 3.2, phase: rnd(i, 9)))
            for (j, d) in [SIMD3<Float>(-0.03, 0.2, 0), SIMD3(0.01, 0.26, 0.02), SIMD3(0.035, 0.17, -0.015)].enumerated() {
                let tilt: Float = (Float(j) - 1) * 7
                // Стебель — трёхгранная палочка без дна, початок — вытянутый ромбик: камыш дешёвый по треугольникам.
                m.prism(YardDecorColors.reed, sides: 3, r: 0.008, h: d.y, at: SIMD3(d.x, d.y / 2 - 0.02, d.z),
                        rot: SIMD3(0, 0, tilt), bottom: false)
                if j < 2 {
                    let top = YardArtMath.rotZ(SIMD3(0, d.y / 2, 0), tilt) + SIMD3(d.x, d.y / 2 - 0.02, d.z)
                    m.gem(YardDecorColors.cattail, sides: 4, r: 0.014, h: 0.08, at: top, rot: SIMD3(0, 0, tilt))
                }
            }
        }
        m.body()
    }

    /// Утка плавает справа от мостика туда и обратно.
    static func duck(_ m: inout YardArtModel, _ c: YardDecorCtx) {
        let (near, far) = riverBand(c)
        let swim = YardArtMotion.keys([YardArtKey(t: 0), YardArtKey(t: 0.45, offset: SIMD3(0.65, 0, 0)),
                                       YardArtKey(t: 0.5, offset: SIMD3(0.65, 0, 0), angle: 180),
                                       YardArtKey(t: 0.95, offset: .zero, angle: 180),
                                       YardArtKey(t: 1, offset: .zero, angle: 360)],
                                      axis: SIMD3(0, 1, 0), period: 14, phase: 0.1)
        m.node("duck", at: SIMD3(0.32, -0.012, (near + far) / 2), motion: swim)
        m.gem(YardDecorColors.duck, sides: 6, r: 0.05, h: 0.05, at: SIMD3(0, 0.02, 0), scale: SIMD3(1.4, 1, 1))
        m.gem(YardDecorColors.duckHead, sides: 5, r: 0.024, h: 0.042, at: SIMD3(0.06, 0.065, 0))
        m.box(YardDecorColors.beak, SIMD3(0.032, 0.01, 0.018), at: SIMD3(0.09, 0.06, 0))
        m.body()
    }

    /// Спасательный круг на стене справа от окна — река видна уже с подоконника.
    static func lifebuoy(_ m: inout YardArtModel, _ c: YardDecorCtx) {
        let center = SIMD3<Float>(0.72, 0.8, wallZ + 0.085)
        m.box(YardArtColors.pole, SIMD3(0.02, 0.02, 0.05), at: center + SIMD3(0, 0.15, -0.015))
        for k in 0..<8 {
            let a = Float(k) * 45
            let p = YardArtMath.rotZ(SIMD3(0, 0.12, 0), a)
            m.box(k % 2 == 0 ? YardDecorColors.buoyRed : YardDecorColors.duck, SIMD3(0.1, 0.05, 0.045),
                  at: center + p, rot: SIMD3(0, 0, a))
        }
    }

    // MARK: На крыше

    /// Кирпичный парапет по краям крыши с бетонным отливом. Пока сада нет — край прямо перед перилами.
    static func parapet(_ m: inout YardArtModel, _ c: YardDecorCtx) {
        let h: Float = 0.16, t: Float = 0.07
        let back: Float = -1.7
        let frontZ: Float = c.top >= 2 ? c.front - t / 2 : 0.13 - t / 2
        if c.top < 2 {
            m.box(c.palette.ground, SIMD3(2.4, 0.04, 0.13), at: SIMD3(0, -0.02, 0.065))
        }
        func wall(_ size: SIMD3<Float>, _ at: SIMD3<Float>) {
            m.box(YardDecorColors.brick, size, at: at)
            m.box(YardDecorColors.coping, SIMD3(size.x + 0.02, 0.025, size.z + 0.02), at: at + SIMD3(0, size.y / 2 + 0.012, 0))
        }
        let sideLen = frontZ + t / 2 - back
        wall(SIMD3(t, h, sideLen), SIMD3(c.left + t / 2, h / 2, back + sideLen / 2))
        wall(SIMD3(t, h, sideLen), SIMD3(c.right - t / 2, h / 2, back + sideLen / 2))
        wall(SIMD3(c.width, h, t), SIMD3(c.midX, h / 2, frontZ))
    }

    static func antenna(_ m: inout YardArtModel, at p: SIMD3<Float>, height: Float, phase: Float, name: String) {
        m.box(YardArtColors.pole, SIMD3(0.08, 0.03, 0.08), at: p + SIMD3(0, 0.015, 0))
        m.box(YardDecorColors.metal, SIMD3(0.022, height, 0.022), at: p + SIMD3(0, height / 2, 0))
        for (k, w) in [Float(0.3), 0.2].enumerated() {
            m.box(YardDecorColors.metal, SIMD3(w, 0.012, 0.012), at: p + SIMD3(0, height * (0.72 + 0.14 * Float(k)), 0),
                  rot: SIMD3(0, 25, 0))
        }
        let blink = YardArtMotion.keys([YardArtKey(t: 0), YardArtKey(t: 0.45), YardArtKey(t: 0.5, scale: 0),
                                        YardArtKey(t: 0.95, scale: 0), YardArtKey(t: 1)],
                                       axis: SIMD3(0, 1, 0), period: 1.6, phase: phase)
        m.node(name, at: p + SIMD3(0, height + 0.03, 0), motion: blink)
        m.gem(YardDecorColors.beacon, sides: 4, r: 0.026, h: 0.04, at: .zero, glow: true)
        m.body()
    }

    static func antennas(_ m: inout YardArtModel, _ c: YardDecorCtx) {
        antenna(&m, at: SIMD3(-0.74, 0, -1.6), height: 0.95, phase: 0, name: "beacon0")
        antenna(&m, at: SIMD3(1.02, 0, -1.5), height: 0.7, phase: 0.5, name: "beacon1")
    }

    static func vents(_ m: inout YardArtModel, _ c: YardDecorCtx) {
        // Турбина-дефлектор: крутится, лопасти видно.
        let t = SIMD3<Float>(0.98, 0, -0.48)
        m.box(YardDecorColors.metal, SIMD3(0.14, 0.16, 0.14), at: t + SIMD3(0, 0.08, 0))
        m.prism(YardDecorColors.tin, sides: 6, r: 0.045, h: 0.08, at: t + SIMD3(0, 0.2, 0))
        m.node("turbine", at: t + SIMD3(0, 0.29, 0), motion: .spin(axis: SIMD3(0, 1, 0), rps: 0.6))
        m.prism(YardDecorColors.tin, sides: 8, r: 0.085, h: 0.1, top: 0.06, at: .zero)
        for k in 0..<4 {
            let q = YardArtMath.rotY(SIMD3(0, 0, 0.085), Float(k) * 90)
            m.box(YardDecorColors.metalDark, SIMD3(0.012, 0.1, 0.05), at: q, rot: SIMD3(0, Float(k) * 90 + 30, 0))
        }
        m.gem(YardDecorColors.metal, sides: 4, r: 0.05, h: 0.06, at: SIMD3(0, 0.07, 0))
        m.body()
        // Трубы с колпаками у стены (видно и с подоконника) и в «саду».
        var pipes: [SIMD3<Float>] = [SIMD3(0.62, 0, -1.62)]
        if c.top >= 2 { pipes.append(SIMD3(0.32, 0, 0.12)) }
        for p in pipes {
            m.prism(YardDecorColors.metal, sides: 6, r: 0.035, h: 0.22, at: p + SIMD3(0, 0.11, 0))
            m.prism(YardDecorColors.metalDark, sides: 6, r: 0.06, h: 0.03, top: 0.02, at: p + SIMD3(0, 0.235, 0))
        }
        // Кондиционеры на дальних крышах (парк, квартал): короб и крутящийся вентилятор спереди.
        var units: [SIMD3<Float>] = []
        if c.top >= 3 { units.append(SIMD3(-2.0, 0, -0.1)) }
        if c.top >= 4 { units.append(SIMD3(2.05, 0, -0.2)) }
        for (i, u) in units.enumerated() {
            m.box(YardDecorColors.coping, SIMD3(0.3, 0.22, 0.18), at: u + SIMD3(0, 0.11, 0))
            m.node("fan\(i)", at: u + SIMD3(0, 0.11, 0.1), motion: .spin(axis: SIMD3(0, 0, 1), rps: 1.2))
            m.box(YardDecorColors.metalDark, SIMD3(0.15, 0.03, 0.006), at: .zero)
            m.box(YardDecorColors.metalDark, SIMD3(0.03, 0.15, 0.006), at: .zero)
            m.body()
        }
    }

    /// Водонапорный бак на ножках, деревянный, с обручами и конусной крышей.
    static func waterTank(_ m: inout YardArtModel, _ c: YardDecorCtx) {
        let t = SIMD3<Float>(-0.98, 0, -0.45)
        for x in [Float(-0.1), 0.1] {
            for z in [Float(-0.1), 0.1] {
                m.box(YardArtColors.pole, SIMD3(0.025, 0.26, 0.025), at: t + SIMD3(x, 0.13, z))
            }
        }
        m.box(YardArtColors.pole, SIMD3(0.28, 0.025, 0.28), at: t + SIMD3(0, 0.27, 0))
        m.prism(YardDecorColors.tank, sides: 8, r: 0.15, h: 0.28, at: t + SIMD3(0, 0.42, 0))
        m.prism(YardArtColors.pole, sides: 8, r: 0.156, h: 0.025, at: t + SIMD3(0, 0.46, 0), bottom: false)
        m.prism(YardDecorColors.metalDark, sides: 8, r: 0.17, h: 0.1, top: 0, at: t + SIMD3(0, 0.61, 0))
    }

    /// Город за будкой выхода: крыши домов разной высоты. Видно с яруса 3, когда камера выше.
    static func skyline(_ m: inout YardArtModel, _ c: YardDecorCtx) {
        guard c.top >= 3 else { return }
        let color = c.night ? YardDecorColors.cityNight : YardDecorColors.city
        let n = 8
        for i in 0..<n {
            let w: Float = 0.52 + 0.16 * rnd(i, 11)
            let x = -2.6 + 5.2 * (Float(i) + 0.5) / Float(n)
            let h: Float = 1.55 + 0.5 * rnd(i, 12)
            let z: Float = -2.15 - 0.2 * rnd(i, 13)
            m.box(color, SIMD3(w, h, 0.3), at: SIMD3(x, h / 2, z))
            if c.night, i % 2 == 0 {
                m.box(YardArtColors.lamp, SIMD3(0.07, 0.09, 0.006), at: SIMD3(x + (rnd(i, 14) - 0.5) * w * 0.5, h - 0.14, z + 0.153),
                      glow: true)
            }
        }
    }
}
