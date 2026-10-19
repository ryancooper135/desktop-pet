// Шерсть в 3D (волна 11): текстура штрихами, развёртка под неё и клочки на спине. Стадия — Coat (CoatLook.stage).
// Текстура — плоский цвет шерсти и короткие штрихи вдоль тела, стиль A (рисованная, не реализм). Бесшовная: штрих,
// ушедший за край, продолжается с другого. Все стадии берут одни и те же штрихи одного сида, только первые N и с разной
// силой: гладкая — редкие светлые, цвет чуть светлее; обычная — светлые и тёмные поровну; лохматая — вдвое больше,
// длиннее и вразброс; колтуны — гуще, темнее и с тёмными пятнами-комками. Поэтому при смене стадии шерсть не «прыгает».
// Цвет запечён в текстуру (своя на материал Main и Main_Light), грязь и блеск по-прежнему красит PetRoom.applyCoat.
// У shiba.usdz нет развёртки (UV) — App строит её коробочной проекцией (boxUVs): грань берёт две оси рамки модели,
// кроме той, куда смотрит её нормаль; ось u всегда вдоль тела (длина), если она есть у грани, — штрихи ложатся по шерсти.
// Клочки — low-poly пучки на спине (WearPart на костях спины, как плащ, едут с ними): колтуны и лохматая стадия.
// Расчёсывание снимает их от головы к хвосту, после него (пока не прошёл откат Brush.cooldownH) их нет.
// Только Foundation: гоняется на Linux (app/Package.swift), пиксели и геометрию проверяют тесты.

import Foundation

/// Как рисовать шерсть одной стадии. Длины — в пикселях текстуры 128 (для другого размера масштабируются).
struct FurStyle: Equatable, Sendable {
    /// Сколько штрихов из общего запаса CoatFur.maxStrokes.
    var strokes: Int
    /// Доля светлых штрихов (остальные тёмные).
    var light: Double
    /// Разброс направления штриха от «вдоль тела», радианы.
    var jitter: Double
    var minLen: Double
    var maxLen: Double
    /// Насколько штрих светлее (к белому) или темнее (к чёрному) основы.
    var contrast: Double
    /// Множитель основы: гладкая чуть светлее, запущенная — темнее.
    var shade: Double
    /// Доля штрихов шириной 2 px.
    var wide: Double
    /// Тёмные пятна-комки: сколько (из CoatFur.maxBlotches) и насколько темнят середину.
    var blotches: Int
    var blotchDark: Double
}

enum CoatFur {
    /// Сторона текстуры: 128 хватает — тело делится на tiles повторов, штрих ~1 пиксель экрана.
    static let size = 128
    /// Сид штрихов. Один на все стадии и оба цвета — смена стадии только добавляет и усиливает.
    static let seed: UInt64 = 0x5EED_F0F0_2026_1019
    static let maxStrokes = 220
    static let maxBlotches = 10
    /// Повторов текстуры по длине тела.
    static let tiles: Float = 3

    static func style(_ stage: CoatStage) -> FurStyle {
        switch stage {
        case .sleek:
            FurStyle(strokes: 45, light: 0.85, jitter: 0.12, minLen: 7, maxLen: 12, contrast: 0.10, shade: 1.04,
                     wide: 0.1, blotches: 0, blotchDark: 0)
        case .normal:
            FurStyle(strokes: 80, light: 0.55, jitter: 0.25, minLen: 6, maxLen: 12, contrast: 0.12, shade: 1.0,
                     wide: 0.2, blotches: 0, blotchDark: 0)
        case .shaggy:
            FurStyle(strokes: 150, light: 0.4, jitter: 0.6, minLen: 8, maxLen: 16, contrast: 0.17, shade: 0.97,
                     wide: 0.35, blotches: 3, blotchDark: 0.18)
        case .matted:
            FurStyle(strokes: 220, light: 0.25, jitter: 1.0, minLen: 6, maxLen: 14, contrast: 0.2, shade: 0.92,
                     wide: 0.45, blotches: 9, blotchDark: 0.3)
        }
    }

    // MARK: текстура

    /// Пиксели RGBA (непрозрачные, sRGB, строки сверху вниз) size × size для основы base (0xRRGGBB).
    static func pixels(stage: CoatStage, base: UInt32, size: Int = CoatFur.size, seed: UInt64 = CoatFur.seed) -> [UInt8] {
        let n = max(1, size)
        let st = style(stage)
        let k = Double(n) / 128
        let b0 = SIMD3<Double>(Double((base >> 16) & 0xff), Double((base >> 8) & 0xff), Double(base & 0xff)) / 255
        let b = simd3Clamp(b0 * st.shade)
        var img = [SIMD3<Double>](repeating: b, count: n * n)
        var rng = CatchRandom(seed: seed)

        func wrap(_ v: Int) -> Int { ((v % n) + n) % n }
        func blend(_ x: Int, _ y: Int, _ c: SIMD3<Double>, _ a: Double) {
            guard a > 0 else { return }
            let i = wrap(y) * n + wrap(x)
            img[i] += (c - img[i]) * min(1, a)
        }

        // Пятна-комки: мягкий тёмный круг. Случайные числа тянем всегда — у всех стадий одна раскладка.
        let dark = b * 0.72
        for i in 0..<maxBlotches {
            let cx = rng.unit() * Double(n), cy = rng.unit() * Double(n)
            let r = (6 + rng.unit() * 6) * k
            guard i < st.blotches else { continue }
            let ri = Int(r.rounded(.up))
            for dy in -ri...ri {
                for dx in -ri...ri {
                    let d = (Double(dx * dx + dy * dy)).squareRoot() / r
                    guard d < 1 else { continue }
                    blend(Int(cx) + dx, Int(cy) + dy, dark, st.blotchDark * 2.5 * pow(1 - d, 0.7))
                }
            }
        }

        // Штрихи: короткие отрезки вдоль u (длины тела), к концам гаснут.
        let lightC = b + (SIMD3<Double>(repeating: 1) - b) * st.contrast
        // На светлой основе (белые лапы, грудь) тёмный штрих мягче и теплее: серые царапины на белом читаются как грязь.
        let pale = (b.x + b.y + b.z) / 3 > 0.75
        let darkC = pale ? b * (1 - st.contrast * 0.8) * SIMD3<Double>(1, 0.97, 0.92) : b * (1 - st.contrast * 1.4)
        for i in 0..<maxStrokes {
            let x0 = rng.unit() * Double(n), y0 = rng.unit() * Double(n)
            let lenU = rng.unit(), angU = rng.unit(), kindU = rng.unit(), wideU = rng.unit()
            guard i < st.strokes else { continue }
            let len = (st.minLen + (st.maxLen - st.minLen) * lenU) * k
            let ang = (angU * 2 - 1) * st.jitter
            let dx = cos(ang), dy = sin(ang)
            let c = kindU < st.light ? lightC : darkC
            let w = wideU < st.wide ? 2 : 1
            let steps = max(2, Int(len * 2))
            for s in 0...steps {
                let t = Double(s) / Double(steps)
                let a = 0.85 * sin(Double.pi * t).squareRoot()
                let px = x0 + dx * len * t, py = y0 + dy * len * t
                let ix = Int(px.rounded(.down)), iy = Int(py.rounded(.down))
                blend(ix, iy, c, a / 2)
                if w == 2 {
                    // Вторая колонка — поперёк штриха.
                    if abs(dy) > abs(dx) { blend(ix + 1, iy, c, a / 2) } else { blend(ix, iy + 1, c, a / 2) }
                }
            }
        }

        var out = [UInt8](repeating: 255, count: n * n * 4)
        for i in 0..<(n * n) {
            let c = simd3Clamp(img[i])
            out[i * 4] = UInt8((c.x * 255).rounded())
            out[i * 4 + 1] = UInt8((c.y * 255).rounded())
            out[i * 4 + 2] = UInt8((c.z * 255).rounded())
        }
        return out
    }

    /// Средний цвет пикселей (для тестов и подбора): 0…1.
    static func mean(_ px: [UInt8]) -> SIMD3<Double> {
        let n = px.count / 4
        guard n > 0 else { return .zero }
        var s = SIMD3<Double>.zero
        for i in 0..<n { s += SIMD3(Double(px[i * 4]), Double(px[i * 4 + 1]), Double(px[i * 4 + 2])) }
        return s / Double(n) / 255
    }

    /// Разброс яркости (стандартное отклонение суммы каналов, 0…1) — насколько «шумная» шерсть.
    static func roughness(_ px: [UInt8]) -> Double {
        let n = px.count / 4
        guard n > 0 else { return 0 }
        let v = (0..<n).map { (Double(px[$0 * 4]) + Double(px[$0 * 4 + 1]) + Double(px[$0 * 4 + 2])) / 765 }
        let m = v.reduce(0, +) / Double(n)
        return (v.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(n)).squareRoot()
    }

    private static func simd3Clamp(_ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(min(1, max(0, v.x)), min(1, max(0, v.y)), min(1, max(0, v.z)))
    }

    // MARK: развёртка

    /// Оси рамки модели: ширина — самая короткая сторона, длина — длиннейшая из остальных, третья — высота.
    static func axes(lo: SIMD3<Float>, hi: SIMD3<Float>) -> (width: Int, length: Int, up: Int) {
        let e = hi - lo
        let w = e.x <= e.y && e.x <= e.z ? 0 : (e.y <= e.z ? 1 : 2)
        let rest = [0, 1, 2].filter { $0 != w }
        let l = e[rest[0]] >= e[rest[1]] ? rest[0] : rest[1]
        return (w, l, rest.first { $0 != l } ?? rest[1])
    }

    /// UV коробочной проекцией по вершинам. Нормали есть — ось по нормали вершины (у low-poly вершины свои у каждой
    /// плоской грани), нет — по нормали треугольника из indices. Масштаб: tiles повторов по длине рамки.
    static func boxUVs(positions: [SIMD3<Float>], normals: [SIMD3<Float>]?, indices: [UInt32],
                       lo: SIMD3<Float>, hi: SIMD3<Float>, tiles: Float = CoatFur.tiles) -> [SIMD2<Float>] {
        let ax = axes(lo: lo, hi: hi)
        let span = max(1e-9, (hi - lo)[ax.length])
        let scale = tiles / span
        var nrm = normals ?? []
        if nrm.count != positions.count {
            nrm = [SIMD3<Float>](repeating: SIMD3(0, 0, 0), count: positions.count)
            var i = 0
            while i + 2 < indices.count {
                let a = Int(indices[i]), b = Int(indices[i + 1]), c = Int(indices[i + 2])
                i += 3
                guard a < positions.count, b < positions.count, c < positions.count else { continue }
                let fn = WearMath.cross(positions[b] - positions[a], positions[c] - positions[a])
                for v in [a, b, c] { nrm[v] += fn }
            }
        }
        return positions.indices.map { i in
            let p = (positions[i] - lo) * scale
            let n = nrm[i]
            let aw = abs(n[ax.width]), al = abs(n[ax.length]), au = abs(n[ax.up])
            if aw >= al && aw >= au { return SIMD2(p[ax.length], p[ax.up]) }      // бок
            if au >= al { return SIMD2(p[ax.length], p[ax.width]) }               // спина и живот
            return SIMD2(p[ax.width], p[ax.up])                                    // грудь и зад
        }
    }

    // MARK: клочки

    /// Клочков на спине без расчёсывания: колтуны и лохматая стадия, столько же, сколько потом расчёсывать
    /// (Brush.tufts), — начало сеанса ничего не добавляет. Только что расчесали (меньше cooldownH назад) — ни одного.
    static func restTufts(_ stage: CoatStage, brushedAgo: Double?, cooldownH: Double) -> Int {
        if let ago = brushedAgo, ago >= 0, ago < (cooldownH > 0 ? cooldownH : 6) * 3600 { return 0 }
        switch stage {
        case .matted, .shaggy: return Brush.tufts(stage)
        case .normal, .sleek: return 0
        }
    }

    /// Цвета клочка (основной, кончики) по стадии: колтун — бурый комок, лохматый — рыжий пучок, у ухоженной —
    /// светлый пух (его видно, только пока чешем: Brush.tufts даёт 1–2).
    static func tuftColors(_ stage: CoatStage) -> (main: UInt32, tip: UInt32) {
        switch stage {
        case .matted: (0x9c5f2e, 0xc27a3c)
        case .shaggy: (0xd08440, 0xf0b070)
        case .normal, .sleek: (0xf3c08a, 0xfff1de)
        }
    }

    /// Где клочок i из n: от холки (i = 0) к хвосту, больше на левом боку (к камере), чуть вразброс.
    /// z — сечение спины (WearMesh.backZ), a — угол от вертикали, градусы.
    static func tuftSpot(_ i: Int, of n: Int) -> (z: Float, a: Float) {
        guard n > 0 else { return (0.3, 0) }
        let k = (Float(i) + 0.5) / Float(n)
        let z = 0.95 - 1.3 * k
        let h = Float(StableHash.fnv1a("tuft\(i)") % 1000) / 1000
        let a: Float = n == 1 ? 8 : (i % 3 == 1 ? -(14 + 10 * h) : 18 + 16 * h)
        return (z, a)
    }

    /// Кость спины по сечению z (WearMesh.backJoints).
    static func joint(z: Float) -> String {
        WearMesh.backJoints.first { z >= $0.z0 && z < $0.z1 }?.joint
            ?? (z < 0 ? WearMesh.backJoints.first?.joint : WearMesh.backJoints.last?.joint) ?? "Torso2"
    }

    /// Фигура клочка i из n в координатах тела (как вещи WearMesh). Части: основной цвет и кончики (accent).
    static func tuft(_ i: Int, of n: Int, stage: CoatStage) -> [WearPart] {
        let spot = tuftSpot(i, of: n)
        let jn = joint(z: spot.z)
        let rad = spot.a * .pi / 180
        // Рамка на поверхности: n — наружу от оси спины, t — к хвосту, s — вбок.
        let nrm = SIMD3<Float>(sin(rad), cos(rad), 0)
        let t = SIMD3<Float>(0, 0, -1)
        let s = WearMath.normalize(WearMath.cross(nrm, t))
        let c = WearMesh.backPoint(z: spot.z, a: spot.a, out: 0)
        let h = Float(StableHash.fnv1a("tuftShape\(i)") % 1000) / 1000
        var main = WearPart(jn)
        var tip = WearPart(jn, accent: true)

        /// Пирамидка-пучок: треугольное основание радиуса r вокруг base, вершина — наружу и к хвосту.
        func spike(_ part: inout WearPart, base: SIMD3<Float>, r: Float, len: Float, lean: Float, side: Float, turn: Float) {
            let top = base + nrm * len + t * lean + s * side
            var ring: [SIMD3<Float>] = []
            for j in 0..<3 {
                let ang = turn + Float(j) * 2 * .pi / 3
                ring.append(base + (s * cos(ang) + t * sin(ang)) * r - nrm * 0.03)
            }
            for j in 0..<3 { part.tri(ring[j], ring[(j + 1) % 3], top) }
        }

        switch stage {
        case .matted:
            // Колтун: приплюснутый неровный комок (шестиугольник с верхушкой) и пара коротких прядей.
            let r: Float = 0.17 + 0.04 * h
            var ring: [SIMD3<Float>] = []
            for j in 0..<6 {
                let ang = Float(j) * .pi / 3 + h
                let rr = r * (0.8 + 0.4 * Float((j * 7 + i * 3) % 5) / 4)
                ring.append(c + (s * cos(ang) + t * sin(ang) * 1.25) * rr + nrm * 0.03)
            }
            let top = c + nrm * (0.13 + 0.03 * h) + t * 0.04
            let bottom = c - nrm * 0.06
            for j in 0..<6 {
                main.tri(ring[j], ring[(j + 1) % 6], top)
                main.tri(ring[(j + 1) % 6], ring[j], bottom)
            }
            spike(&tip, base: c + t * 0.12 + nrm * 0.05, r: 0.05, len: 0.12, lean: 0.12, side: 0.03, turn: h)
            spike(&tip, base: c - t * 0.06 + s * 0.08 + nrm * 0.05, r: 0.04, len: 0.1, lean: 0.08, side: 0.05,
                  turn: h + 1)
        case .shaggy:
            // Лохматый пучок: три пряди лежат к хвосту и топорщатся (не иголки — по ui-71 высокие читались ежом),
            // средняя длиннее, кончики светлее.
            spike(&main, base: c, r: 0.1, len: 0.15 + 0.03 * h, lean: 0.24, side: 0, turn: h)
            spike(&main, base: c + s * 0.09 + t * 0.03, r: 0.08, len: 0.11, lean: 0.18, side: 0.07, turn: h + 0.7)
            spike(&tip, base: c - s * 0.08 - t * 0.04, r: 0.08, len: 0.12, lean: 0.18, side: -0.08, turn: h + 1.4)
        case .normal, .sleek:
            // Пушинка: две короткие светлые пряди.
            spike(&main, base: c, r: 0.06, len: 0.16, lean: 0.1, side: 0.02, turn: h)
            spike(&tip, base: c + s * 0.06, r: 0.045, len: 0.12, lean: 0.08, side: 0.05, turn: h + 1)
        }
        return [main, tip].filter { !$0.isEmpty }
    }
}
