// Фигуры надетого (Wear) без RealityKit: треугольники в «теле» Шибы — координатах корня shiba.usdz
// (Y вверх, морда к +Z, рост 3.09 ед.). Замер по исходнику tools/assets/source/shiba.glb: сечения шеи,
// спины и макушки в позе покоя. Каждая часть привязана к кости и потом ездит с ней (app/App/PetWear.swift).
// Плоские нормали и обе стороны у каждого треугольника: стиль A (low-poly), и неважно, куда смотрит обход.
// Здесь же — без Apple-фреймворков, чтобы геометрию проверяли тесты на Linux.

import Foundation

/// Место на собаке. rawValue — ключ в SaveFile.worn, менять нельзя.
enum WearSlot: String, Codable, CaseIterable, Hashable, Sendable, Comparable {
    case head, neck, back

    var title: String {
        switch self {
        case .head: return "голова"
        case .neck: return "шея"
        case .back: return "спина"
        }
    }

    /// Подпись в коллекции: «на шею».
    var place: String {
        switch self {
        case .head: return "на голову"
        case .neck: return "на шею"
        case .back: return "на спину"
        }
    }

    private var order: Int { WearSlot.allCases.firstIndex(of: self) ?? 0 }
    static func < (a: WearSlot, b: WearSlot) -> Bool { a.order < b.order }
}

/// Какую фигуру строить. У предметов без своей — общая для места (generic*).
enum WearShape: String, CaseIterable, Hashable, Sendable {
    case leafHat, bow                    // голова
    case bandana, collar, scarf          // шея
    case cape                            // спина
    case genericHat, genericRing, genericBlanket
    // волна 11
    case beret, wreath, crown            // голова
    case bellCollar, bowtie              // шея
    case backpack                        // спина

    var slot: WearSlot {
        switch self {
        case .leafHat, .bow, .genericHat, .beret, .wreath, .crown: return .head
        case .bandana, .collar, .scarf, .genericRing, .bellCollar, .bowtie: return .neck
        case .cape, .genericBlanket, .backpack: return .back
        }
    }
}

/// Кусок фигуры одного цвета на одной кости. accent — второй цвет предмета.
struct WearPart: Sendable {
    var joint: String
    var accent: Bool
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []

    init(_ joint: String, accent: Bool = false) {
        self.joint = joint
        self.accent = accent
    }

    var isEmpty: Bool { indices.isEmpty }

    /// Треугольник с двух сторон, у каждой своя плоская нормаль.
    mutating func tri(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
        let n = WearMath.normalize(WearMath.cross(b - a, c - a))
        guard n != .zero else { return }
        for (p, q, r, nn) in [(a, b, c, n), (a, c, b, -n)] {
            let i = UInt32(positions.count)
            positions += [p, q, r]
            normals += [nn, nn, nn]
            indices += [i, i + 1, i + 2]
        }
    }

    mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>) {
        tri(a, b, c)
        tri(a, c, d)
    }

    /// Коробка по осям: центр и полуразмеры.
    mutating func box(_ c: SIMD3<Float>, _ h: SIMD3<Float>) {
        func v(_ sx: Float, _ sy: Float, _ sz: Float) -> SIMD3<Float> { c + h * SIMD3(sx, sy, sz) }
        quad(v(-1, -1, 1), v(1, -1, 1), v(1, 1, 1), v(-1, 1, 1))       // перед
        quad(v(1, -1, -1), v(-1, -1, -1), v(-1, 1, -1), v(1, 1, -1))   // зад
        quad(v(-1, 1, 1), v(1, 1, 1), v(1, 1, -1), v(-1, 1, -1))       // верх
        quad(v(-1, -1, -1), v(1, -1, -1), v(1, -1, 1), v(-1, -1, 1))   // низ
        quad(v(1, -1, 1), v(1, -1, -1), v(1, 1, -1), v(1, 1, 1))       // право
        quad(v(-1, -1, -1), v(-1, -1, 1), v(-1, 1, 1), v(-1, 1, -1))   // лево
    }

    /// Плоская фигура толщиной t: контур в плоскости (o, ex, ey), толщина по нормали ex×ey.
    /// Контур звёздный относительно центра (веер из середины), подойдут и звезда, и лист.
    mutating func slab(_ outline: [SIMD2<Float>], o: SIMD3<Float>, ex: SIMD3<Float>, ey: SIMD3<Float>, t: Float) {
        guard outline.count >= 3 else { return }
        let n = WearMath.normalize(WearMath.cross(ex, ey)) * (t / 2)
        let pts = outline.map { o + ex * $0.x + ey * $0.y }
        let mid = pts.reduce(SIMD3<Float>.zero, +) / Float(pts.count)
        for k in pts.indices {
            let a = pts[k], b = pts[(k + 1) % pts.count]
            tri(mid + n, a + n, b + n)
            tri(mid - n, b - n, a - n)
            quad(a + n, a - n, b - n, b + n)
        }
    }
}

enum WearMath {
    static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    static func length(_ a: SIMD3<Float>) -> Float { (a * a).sum().squareRoot() }

    static func normalize(_ a: SIMD3<Float>) -> SIMD3<Float> {
        let l = length(a)
        return l > 1e-9 ? a / l : .zero
    }

    /// Поворот вокруг X на deg градусов: +Y клонится к +Z.
    static func rotX(_ v: SIMD3<Float>, _ deg: Float) -> SIMD3<Float> {
        let a = deg * .pi / 180, c = cos(a), s = sin(a)
        return SIMD3(v.x, v.y * c - v.z * s, v.y * s + v.z * c)
    }

    /// Поворот вокруг Z на deg градусов: +X клонится к +Y.
    static func rotZ(_ v: SIMD3<Float>, _ deg: Float) -> SIMD3<Float> {
        let a = deg * .pi / 180, c = cos(a), s = sin(a)
        return SIMD3(v.x * c - v.y * s, v.x * s + v.y * c, v.z)
    }

    /// Кусочно-линейно по узлам xs (по возрастанию).
    static func lerp(_ xs: [Float], _ ys: [Float], _ x: Float) -> Float {
        guard let first = xs.first, let last = xs.last, xs.count == ys.count else { return ys.first ?? 0 }
        if x <= first { return ys[0] }
        if x >= last { return ys[ys.count - 1] }
        var i = 0
        while i + 1 < xs.count && xs[i + 1] < x { i += 1 }
        let u = (x - xs[i]) / (xs[i + 1] - xs[i])
        return ys[i] + (ys[i + 1] - ys[i]) * u
    }
}

enum WearMesh {
    // MARK: замеры shiba.glb (поза покоя, координаты тела)

    /// Где кость в позе покоя: по ней PetWear проверяет, что тело модели то же, что и в замерах.
    /// Кости в позе покоя (точность ~0.02): по Body и Head подбираются масштаб и сдвиг тела модели,
    /// по остальным — проверка, что скелет тот же. Не сошлось — вещи стоят на теле без костей.
    static let bindJoints: [String: SIMD3<Float>] = [
        "Body": SIMD3(0, 0.47, 0), "Torso": SIMD3(0, 1.75, -0.17), "Torso2": SIMD3(0, 1.73, 0.33),
        "Torso3": SIMD3(0, 1.72, 0.98), "Neck2": SIMD3(0, 2.16, 1.49), "Head": SIMD3(0, 2.65, 1.82),
    ]

    /// Габариты Шибы в позе покоя: если скелета нет, тело модели сводится к ним по рамке.
    static let restMin = SIMD3<Float>(-0.536, 0, -1.669)
    static let restMax = SIMD3<Float>(0.536, 3.093, 2.496)

    /// Шея: сечение плоскостью через neckCenter, наклонённой на neckTilt° вперёд (ось шеи).
    /// Радиус до поверхности через 30° от +X к «вперёд-вниз» (+Z плоскости), 12 значений по кругу.
    static let neckCenter = SIMD3<Float>(0, 2.05, 1.5)
    static let neckTilt: Float = 45
    static let neckRadii: [Float] = [0.34, 0.35, 0.38, 0.40, 0.38, 0.35, 0.34, 0.40, 0.56, 0.60, 0.57, 0.40]

    /// Спина: сечения z = const, радиус поверхности от оси (y = backAxisY) под углом от вертикали 0…90°.
    static let backAxisY: Float = 1.75
    static let backZ: [Float] = [-0.45, -0.25, 0, 0.3, 0.6, 0.85, 1.05]
    static let backAngles: [Float] = [0, 15, 30, 45, 60, 75, 90]
    static let backRadii: [[Float]] = [
        [0.50, 0.51, 0.51, 0.47, 0.45, 0.44, 0.44],
        [0.49, 0.50, 0.49, 0.42, 0.40, 0.39, 0.39],
        [0.46, 0.47, 0.46, 0.42, 0.37, 0.36, 0.36],
        [0.45, 0.45, 0.47, 0.47, 0.48, 0.42, 0.42],
        [0.52, 0.56, 0.54, 0.50, 0.48, 0.44, 0.43],
        [0.58, 0.59, 0.58, 0.53, 0.47, 0.45, 0.43],
        [0.69, 0.70, 0.57, 0.57, 0.50, 0.46, 0.46],
    ]

    /// Макушка: плоская y ≈ 3.0 на z 1.6…2.0, уши с |x| ≥ 0.35.
    static let crown = SIMD3<Float>(0, 3.0, 1.82)

    // MARK: кости

    static let headJoint = "Head"
    static let neckJoint = "Neck2"
    /// Спина режется на три куска по z, каждый на своей кости: спина гнётся (сидеть, лежать) — плащ тоже.
    static let backJoints: [(z0: Float, z1: Float, joint: String)] = [
        (-0.6, 0.05, "Torso"), (0.0, 0.62, "Torso2"), (0.57, 1.2, "Torso3"),
    ]

    // MARK: фигуры

    static func parts(_ shape: WearShape) -> [WearPart] {
        let out: [WearPart]
        switch shape {
        case .leafHat: out = leafHat()
        case .bow: out = bow()
        case .genericHat: out = cone()
        case .bandana: out = bandana()
        case .collar: out = collar(star: true)
        case .genericRing: out = collar(star: false)
        case .scarf: out = scarf()
        case .cape: out = cape()
        case .genericBlanket: out = blanket()
        case .beret: out = beret()
        case .wreath: out = wreath()
        case .crown: out = crownShape()
        case .bellCollar: out = bellCollar()
        case .bowtie: out = bowtie()
        case .backpack: out = backpack()
        }
        return out.filter { !$0.isEmpty }
    }

    /// Точка кольца вокруг шеи: угол phi (° от +X к «вперёд-вниз»), отступ от поверхности out,
    /// сдвиг вдоль оси шеи up.
    static func neckPoint(_ phi: Float, out: Float, up: Float = 0) -> SIMD3<Float> {
        let r = ringRadius(phi) + out
        let a = phi * .pi / 180
        let local = SIMD3<Float>(r * cos(a), up, r * sin(a))
        return neckCenter + WearMath.rotX(local, neckTilt)
    }

    static func ringRadius(_ phi: Float) -> Float {
        let n = neckRadii.count
        var p = phi.truncatingRemainder(dividingBy: 360)
        if p < 0 { p += 360 }
        let x = p / (360 / Float(n))
        let i = Int(x) % n, j = (i + 1) % n
        let u = x - Float(Int(x))
        return neckRadii[i] + (neckRadii[j] - neckRadii[i]) * u
    }

    /// Направление «вперёд-вниз» в плоскости шеи (к груди) и ось шеи.
    static var neckFront: SIMD3<Float> { WearMath.rotX(SIMD3(0, 0, 1), neckTilt) }
    static var neckAxis: SIMD3<Float> { WearMath.rotX(SIMD3(0, 1, 0), neckTilt) }

    /// Лента вокруг шеи: отступ gap от поверхности, толщина thick наружу, ширина вдоль шеи 2·half.
    /// accentEvery > 0 — каждый такой сегмент вторым цветом (полоски шарфа).
    static func band(gap: Float, thick: Float, half: Float, segs: Int = 24, shift: Float = 0,
                     accentEvery: Int = 0) -> [WearPart] {
        var main = WearPart(neckJoint)
        var acc = WearPart(neckJoint, accent: true)
        for k in 0..<segs {
            let p0 = Float(k) * 360 / Float(segs), p1 = Float(k + 1) * 360 / Float(segs)
            let i0 = neckPoint(p0, out: gap, up: shift), i1 = neckPoint(p1, out: gap, up: shift)
            let o0 = neckPoint(p0, out: gap + thick, up: shift), o1 = neckPoint(p1, out: gap + thick, up: shift)
            let h = neckAxis * half
            let useAccent = accentEvery > 0 && k % accentEvery == 0
            var part = useAccent ? acc : main
            part.quad(o0 - h, o1 - h, o1 + h, o0 + h)      // снаружи
            part.quad(i0 + h, i1 + h, i1 - h, i0 - h)      // изнутри
            part.quad(i0 + h, o0 + h, o1 + h, i1 + h)      // верх
            part.quad(i0 - h, i1 - h, o1 - h, o0 - h)      // низ
            if useAccent { acc = part } else { main = part }
        }
        return [main, acc]
    }

    // Голова

    static func leafHat() -> [WearPart] {
        var leaf = WearPart(headJoint)
        var stem = WearPart(headJoint, accent: true)
        // Лист лежит на макушке вдоль морды, кончик к носу; края чуть приподняты (жилка ниже краёв).
        let o = crown + SIMD3(0, 0.05, 0)
        let ex = SIMD3<Float>(1, 0, 0)
        let ez = WearMath.normalize(SIMD3<Float>(0, -0.18, 1))
        let len: Float = 0.74, w: Float = 0.27
        let outline: [SIMD2<Float>] = [
            SIMD2(0, -len / 2), SIMD2(w * 0.7, -len * 0.3), SIMD2(w, 0), SIMD2(w * 0.75, len * 0.25),
            SIMD2(0, len / 2), SIMD2(-w * 0.75, len * 0.25), SIMD2(-w, 0), SIMD2(-w * 0.7, -len * 0.3),
        ]
        // Две половинки с изломом по жилке: левая и правая приподняты.
        for side in [Float(1), -1] {
            let lift = SIMD3<Float>(0, 0.06, 0)
            let half = outline.filter { $0.x * side >= 0 }
            let pts = half.map { o + ex * $0.x + ez * $0.y + (abs($0.x) > 0.01 ? lift * abs($0.x) / w : .zero) }
            let mid = o + ez * 0.0
            for k in 0..<(pts.count - 1) {
                leaf.tri(mid, pts[k], pts[k + 1])
                leaf.tri(mid - SIMD3(0, 0.035, 0), pts[k + 1] - SIMD3(0, 0.035, 0), pts[k] - SIMD3(0, 0.035, 0))
            }
            leaf.tri(mid, pts[pts.count - 1], pts[0])
        }
        // Черенок: брусок от заднего края листа вверх-назад.
        let a = o + ez * (-len / 2) + SIMD3(0, 0.02, 0.04)
        let b = a + SIMD3(0, 0.16, -0.12)
        stem.slab([SIMD2(-0.03, 0), SIMD2(0.03, 0), SIMD2(0.025, 1), SIMD2(-0.025, 1)],
                  o: a, ex: SIMD3(1, 0, 0), ey: b - a, t: 0.05)
        return [leaf, stem]
    }

    static func bow() -> [WearPart] {
        var wings = WearPart(headJoint)
        var knot = WearPart(headJoint, accent: true)
        let o = crown + SIMD3(0, 0.08, 0.02)
        let ey = WearMath.normalize(SIMD3<Float>(0, 1, 0.25))
        let ex = SIMD3<Float>(1, 0, 0)
        // Крылышки — трапеции от узла в стороны, толщиной 0.07.
        for side in [Float(1), -1] {
            let pts: [SIMD2<Float>] = [SIMD2(0.04 * side, -0.04), SIMD2(0.24 * side, -0.12),
                                       SIMD2(0.26 * side, 0.0), SIMD2(0.24 * side, 0.12), SIMD2(0.04 * side, 0.04)]
            wings.slab(side > 0 ? pts : pts.reversed(), o: o, ex: ex, ey: ey, t: 0.08)
        }
        knot.slab([SIMD2(-0.06, -0.06), SIMD2(0.06, -0.06), SIMD2(0.06, 0.06), SIMD2(-0.06, 0.06)],
                  o: o, ex: ex, ey: ey, t: 0.11)
        return [wings, knot]
    }

    /// Общая шапка: шестигранный колпачок с помпоном.
    static func cone() -> [WearPart] {
        var hat = WearPart(headJoint)
        var top = WearPart(headJoint, accent: true)
        let base = crown + SIMD3(0, 0.02, 0)
        let tip = base + SIMD3(0, 0.36, -0.06)
        let n = 6
        let ring = (0..<n).map { k -> SIMD3<Float> in
            let a = Float(k) / Float(n) * 2 * .pi
            return base + SIMD3(0.2 * cos(a), 0, 0.2 * sin(a))
        }
        for k in 0..<n {
            hat.tri(ring[k], ring[(k + 1) % n], tip)
            hat.tri(ring[k], base, ring[(k + 1) % n])
        }
        top.slab([SIMD2(-0.05, -0.05), SIMD2(0.05, -0.05), SIMD2(0.05, 0.05), SIMD2(-0.05, 0.05)],
                 o: tip, ex: SIMD3(1, 0, 0), ey: SIMD3(0, 1, 0), t: 0.1)
        return [hat, top]
    }

    /// Берет: плоский восьмигранный «блин», к затылку чуть ниже, хвостик сверху.
    static func beret() -> [WearPart] {
        var cap = WearPart(headJoint)
        var tail = WearPart(headJoint, accent: true)
        let base = crown + SIMD3(0, 0.03, -0.04)
        let n = 8
        func ring(_ r: Float, _ y: Float) -> [SIMD3<Float>] {
            (0..<n).map { k in
                let a = (Float(k) + 0.5) / Float(n) * 2 * .pi
                // К затылку (−z) край ниже: берет сдвинут назад, как его носят.
                return base + SIMD3(r * cos(a), y - 0.03 * max(0, -sin(a)), r * sin(a))
            }
        }
        let low = ring(0.24, 0), rim = ring(0.31, 0.06), top = ring(0.22, 0.12)
        let peak = base + SIMD3(0, 0.13, 0)
        for k in 0..<n {
            let j = (k + 1) % n
            cap.quad(low[k], low[j], rim[j], rim[k])
            cap.quad(rim[k], rim[j], top[j], top[k])
            cap.tri(top[k], top[j], peak)
            cap.tri(low[j], low[k], base)
        }
        tail.slab([SIMD2(-0.025, 0), SIMD2(0.025, 0), SIMD2(0.02, 1), SIMD2(-0.02, 1)],
                  o: peak, ex: SIMD3(1, 0, 0), ey: SIMD3(0, 0.08, -0.03), t: 0.04)
        return [cap, tail]
    }

    /// Венок: восемь листьев по кругу вокруг макушки, между ними ягодки вторым цветом.
    static func wreath() -> [WearPart] {
        var leaves = WearPart(headJoint)
        var berries = WearPart(headJoint, accent: true)
        let c = crown + SIMD3(0, 0.04, 0)
        let n = 8
        let r: Float = 0.26
        for k in 0..<n {
            let a = Float(k) / Float(n) * 2 * .pi
            let radial = SIMD3<Float>(cos(a), 0, sin(a))
            let tangent = SIMD3<Float>(-sin(a), 0, cos(a))
            // Лист вдоль круга, чуть отогнут наружу.
            let o = c + radial * r
            let ey = WearMath.normalize(radial * 0.3 + SIMD3(0, 1, 0))
            leaves.slab([SIMD2(-0.13, 0), SIMD2(0, -0.06), SIMD2(0.13, 0), SIMD2(0, 0.07)],
                        o: o, ex: tangent, ey: ey, t: 0.03)
            let b2 = a + .pi / Float(n)
            let b = c + SIMD3(cos(b2), 0, sin(b2)) * (r + 0.02) + SIMD3(0, 0.04, 0)
            berries.box(b, SIMD3(repeating: 0.035))
        }
        return [leaves, berries]
    }

    /// Корона: зубчатый обод (высокий зубец через один), шарики на зубцах, камень спереди.
    static func crownShape() -> [WearPart] {
        var gold = WearPart(headJoint)
        var gem = WearPart(headJoint, accent: true)
        let base = crown + SIMD3(0, 0.02, 0)
        let n = 10
        let r: Float = 0.22
        var lo: [SIMD3<Float>] = []
        var hi: [SIMD3<Float>] = []
        for k in 0..<n {
            let a = Float(k) / Float(n) * 2 * .pi + .pi / 2
            let p = base + SIMD3(r * cos(a), 0, r * sin(a))
            let h: Float = k % 2 == 0 ? 0.26 : 0.13
            lo.append(p)
            hi.append(p + SIMD3(0.06 * cos(a), h, 0.06 * sin(a)))
        }
        for k in 0..<n {
            let j = (k + 1) % n
            gold.quad(lo[k], lo[j], hi[j], hi[k])
        }
        for k in stride(from: 0, to: n, by: 2) { gold.box(hi[k] + SIMD3(0, 0.02, 0), SIMD3(repeating: 0.03)) }
        // Камень спереди (+z), ромбом.
        let front = base + SIMD3(0, 0.08, r + 0.04)
        gem.slab([SIMD2(0, -0.06), SIMD2(0.05, 0), SIMD2(0, 0.06), SIMD2(-0.05, 0)],
                 o: front, ex: SIMD3(1, 0, 0), ey: SIMD3(0, 1, 0), t: 0.03)
        return [gold, gem]
    }

    // Шея

    /// Ошейник с бубенчиком: лента и колокольчик спереди.
    static func bellCollar() -> [WearPart] {
        var parts = band(gap: 0.01, thick: 0.05, half: 0.06, segs: 16)
        var bell = WearPart(neckJoint, accent: true)
        let top = neckPoint(90, out: 0.08)
        let c = top + SIMD3(0, -0.1, 0.02)
        // Колокольчик — восьмигранная «бочка» из двух пирамид и ушко сверху.
        let n = 8
        let r: Float = 0.08
        let ring = (0..<n).map { k -> SIMD3<Float> in
            let a = Float(k) / Float(n) * 2 * .pi
            return c + SIMD3(r * cos(a), 0, r * sin(a))
        }
        for k in 0..<n {
            let j = (k + 1) % n
            bell.tri(ring[k], ring[j], c + SIMD3(0, 0.08, 0))
            bell.tri(ring[j], ring[k], c + SIMD3(0, -0.07, 0))
        }
        bell.box(top + SIMD3(0, -0.01, 0.01), SIMD3(0.02, 0.025, 0.02))
        parts.append(bell)
        return parts
    }

    /// Бабочка: узкая лента, спереди два крыла в горошек и узелок.
    static func bowtie() -> [WearPart] {
        var parts = band(gap: 0.01, thick: 0.03, half: 0.035, segs: 16)
        var acc = WearPart(neckJoint, accent: true)
        let c = neckPoint(90, out: 0.07)
        let ex = SIMD3<Float>(1, 0, 0)
        let ey = WearMath.normalize(SIMD3<Float>(0, 1, -0.35))
        let face = WearMath.cross(ex, ey)
        for side in [Float(1), -1] {
            let wing: [SIMD2<Float>] = [SIMD2(0.03 * side, -0.03), SIMD2(0.22 * side, -0.11),
                                        SIMD2(0.24 * side, 0), SIMD2(0.22 * side, 0.11), SIMD2(0.03 * side, 0.03)]
            parts[0].slab(side > 0 ? wing : wing.reversed(), o: c, ex: ex, ey: ey, t: 0.07)
            // Горошины поверх крыла.
            for d in [SIMD2<Float>(0.12 * side, 0.04), SIMD2<Float>(0.17 * side, -0.05)] {
                acc.slab([SIMD2(0, -0.025), SIMD2(0.025, 0), SIMD2(0, 0.025), SIMD2(-0.025, 0)],
                         o: c + ex * d.x + ey * d.y + face * 0.04, ex: ex, ey: ey, t: 0.01)
            }
        }
        acc.slab([SIMD2(-0.05, -0.05), SIMD2(0.05, -0.05), SIMD2(0.05, 0.05), SIMD2(-0.05, 0.05)],
                 o: c, ex: ex, ey: ey, t: 0.1)
        parts.append(acc)
        return parts
    }

    static func bandana() -> [WearPart] {
        var cloth = band(gap: 0.01, thick: 0.035, half: 0.05, segs: 16)[0]
        var dots = WearPart(neckJoint, accent: true)
        // Треугольник спереди: от ленты вниз по груди, чуть наружу.
        let l = neckPoint(30, out: 0.05), r = neckPoint(150, out: 0.05), m = neckPoint(90, out: 0.09)
        let tip = m + SIMD3(0, -0.42, 0.02)
        cloth.tri(l, m, tip)
        cloth.tri(m, r, tip)
        // Горошек на треугольнике: три ромбика поверх ткани.
        let face = WearMath.normalize(WearMath.cross(m - l, tip - l))
        let outward: SIMD3<Float> = WearMath.length(face) > 0 && face.z < 0 ? -face : face
        // Барицентрические веса (l, r, tip) у трёх горошин.
        let weights: [SIMD3<Float>] = [SIMD3(0.5, 0.2, 0.3), SIMD3(0.2, 0.5, 0.3), SIMD3(0.2, 0.2, 0.6)]
        for w in weights {
            let base: SIMD3<Float> = l * w.x + r * w.y + tip * w.z
            let c: SIMD3<Float> = base + outward * 0.02
            dots.slab([SIMD2(0, -0.04), SIMD2(0.04, 0), SIMD2(0, 0.04), SIMD2(-0.04, 0)],
                      o: c, ex: WearMath.normalize(r - l), ey: WearMath.normalize(tip - m), t: 0.01)
        }
        // Узелок сзади.
        let k = neckPoint(270, out: 0.05)
        cloth.slab([SIMD2(-0.07, -0.05), SIMD2(0.07, -0.05), SIMD2(0.05, 0.05), SIMD2(-0.05, 0.05)],
                   o: k, ex: SIMD3(1, 0, 0), ey: neckAxis, t: 0.06)
        return [cloth, dots]
    }

    static func collar(star: Bool) -> [WearPart] {
        var parts = band(gap: 0.01, thick: 0.05, half: 0.06, segs: 16)
        guard star else { return parts }
        var gold = WearPart(neckJoint, accent: true)
        // Медалька-звезда висит спереди, смотрит вперёд.
        let c = neckPoint(90, out: 0.08) + SIMD3(0, -0.13, 0)
        var outline: [SIMD2<Float>] = []
        for k in 0..<10 {
            let a = Float(k) / 10 * 2 * .pi + .pi / 2
            let r: Float = k % 2 == 0 ? 0.13 : 0.055
            outline.append(SIMD2(r * cos(a), r * sin(a)))
        }
        gold.slab(outline, o: c, ex: SIMD3(1, 0, 0), ey: WearMath.normalize(SIMD3(0, 1, -0.25)), t: 0.04)
        // Колечко между ошейником и звездой.
        gold.slab([SIMD2(-0.02, 0), SIMD2(0.02, 0), SIMD2(0.02, 1), SIMD2(-0.02, 1)],
                  o: neckPoint(90, out: 0.06), ex: SIMD3(1, 0, 0), ey: c + SIMD3(0, 0.1, 0) - neckPoint(90, out: 0.06),
                  t: 0.03)
        parts.append(gold)
        return parts
    }

    static func scarf() -> [WearPart] {
        var parts = band(gap: 0.02, thick: 0.1, half: 0.11, segs: 16, accentEvery: 4)
        // Хвост шарфа: свисает спереди сбоку, на конце полоска.
        let top = neckPoint(55, out: 0.12)
        let dir = WearMath.normalize(SIMD3<Float>(0.15, -1, 0.15))
        let side = SIMD3<Float>(1, 0, -0.2)
        parts[0].slab([SIMD2(-0.1, 0), SIMD2(0.1, 0), SIMD2(0.1, 0.36), SIMD2(-0.1, 0.36)],
                      o: top, ex: WearMath.normalize(side), ey: dir, t: 0.06)
        parts[1].slab([SIMD2(-0.1, 0.36), SIMD2(0.1, 0.36), SIMD2(0.1, 0.46), SIMD2(-0.1, 0.46)],
                      o: top, ex: WearMath.normalize(side), ey: dir, t: 0.065)
        return parts
    }

    // Спина

    /// Радиус спины в сечении z под углом a (° от вертикали, знак — сторона).
    static func backRadius(z: Float, a: Float) -> Float {
        let col = backAngles.map { ang -> Float in
            let i = backAngles.firstIndex(of: ang) ?? 0
            return WearMath.lerp(backZ, backRadii.map { $0[i] }, z)
        }
        return WearMath.lerp(backAngles, col, min(abs(a), 90))
    }

    static func backPoint(z: Float, a: Float, out: Float) -> SIMD3<Float> {
        let r = backRadius(z: z, a: a) + out
        let rad = a * .pi / 180
        return SIMD3(r * sin(rad), backAxisY + r * cos(rad), z)
    }

    /// Накидка по спине от z0 до z1 и от −amax до amax; flare — на сколько расширяется к хвосту.
    /// Режется по кускам backJoints, accent — полоса вдоль хребта шириной stripe°.
    static func shell(z0: Float, z1: Float, amax: Float, out: Float, flare: Float, stripe: Float,
                      hemAccent: Bool) -> [WearPart] {
        let zs = stride(from: z0, through: z1 + 1e-4, by: (z1 - z0) / 6).map { $0 }
        let angs = stride(from: -amax, through: amax + 1e-4, by: amax / 4).map { $0 }
        func p(_ z: Float, _ a: Float) -> SIMD3<Float> {
            let u = (z1 - z) / (z1 - z0)   // 0 спереди, 1 сзади
            let aa = a * (1 + flare * 0.25 * u)
            return backPoint(z: z, a: aa, out: out + flare * 0.1 * u * abs(a) / amax)
        }
        var parts: [WearPart] = []
        for seg in backJoints {
            var main = WearPart(seg.joint)
            var acc = WearPart(seg.joint, accent: true)
            for i in 0..<(zs.count - 1) {
                let za = zs[i], zb = zs[i + 1]
                let mid = (za + zb) / 2
                guard mid >= seg.z0, mid < seg.z1 else { continue }
                for j in 0..<(angs.count - 1) {
                    let a0 = angs[j], a1 = angs[j + 1]
                    let isStripe = stripe > 0 && abs((a0 + a1) / 2) < stripe
                    let quad = (p(za, a0), p(zb, a0), p(zb, a1), p(za, a1))
                    if isStripe {
                        acc.quad(quad.0 + SIMD3(0, 0.012, 0), quad.1 + SIMD3(0, 0.012, 0),
                                 quad.2 + SIMD3(0, 0.012, 0), quad.3 + SIMD3(0, 0.012, 0))
                    } else {
                        main.quad(quad.0, quad.1, quad.2, quad.3)
                    }
                }
                // Кайма по нижним краям.
                if hemAccent {
                    for a in [-amax, amax] {
                        let s: Float = a > 0 ? 1 : -1
                        let e0 = p(za, a), e1 = p(zb, a)
                        let d = SIMD3<Float>(0, -0.07, 0) + SIMD3(0.02 * s, 0, 0)
                        acc.quad(e0, e1, e1 + d, e0 + d)
                    }
                }
            }
            parts += [main, acc]
        }
        // Передний кант: полоса поперёк у шеи.
        if hemAccent, let front = backJoints.last {
            var trim = WearPart(front.joint, accent: true)
            for j in 0..<(angs.count - 1) {
                let a0 = angs[j], a1 = angs[j + 1]
                let q0 = p(z1, a0), q1 = p(z1, a1)
                let back = SIMD3<Float>(0, 0, -0.09), lift = SIMD3<Float>(0, 0.015, 0)
                trim.quad(q0 + lift, q1 + lift, q1 + back + lift, q0 + back + lift)
            }
            parts.append(trim)
        }
        return parts
    }

    static func cape() -> [WearPart] {
        shell(z0: -0.5, z1: 1.08, amax: 95, out: 0.05, flare: 1, stripe: 0, hemAccent: true)
    }

    static func blanket() -> [WearPart] {
        shell(z0: -0.3, z1: 0.9, amax: 85, out: 0.07, flare: 0.2, stripe: 12, hemAccent: false)
    }

    /// Рюкзачок-жёлудь: коробка на середине спины, сверху «шляпка» вторым цветом с хвостиком,
    /// лямки по бокам. Весь на Torso2 — середина спины гнётся мало.
    static func backpack() -> [WearPart] {
        var body = WearPart("Torso2")
        var cap = WearPart("Torso2", accent: true)
        let top = backPoint(z: 0.15, a: 0, out: 0).y
        body.box(SIMD3(0, top + 0.13, 0.15), SIMD3(0.22, 0.17, 0.26))
        body.box(SIMD3(0, top + 0.1, 0.43), SIMD3(0.14, 0.09, 0.04))      // карман спереди
        cap.box(SIMD3(0, top + 0.33, 0.15), SIMD3(0.25, 0.04, 0.29))
        cap.box(SIMD3(0, top + 0.41, 0.15), SIMD3(0.03, 0.05, 0.03))
        // Лямки: по две полосы с боков, от края рюкзака вниз по поверхности.
        for z in [Float(0.0), 0.32] {
            for side in [Float(1), -1] {
                for k in 0..<5 {
                    let a0 = side * (30 + Float(k) * 12)
                    let a1 = side * (30 + Float(k + 1) * 12)
                    let p0 = backPoint(z: z, a: a0, out: 0.02)
                    let p1 = backPoint(z: z, a: a1, out: 0.02)
                    let w = SIMD3<Float>(0, 0, 0.04)
                    cap.quad(p0 - w, p0 + w, p1 + w, p1 - w)
                }
            }
        }
        return [body, cap]
    }

    // MARK: заглушка без модели

    /// Перенос из тела Шибы на собачку из коробок (StubDog, метры): масштаб и точки «откуда → куда».
    static func stubMap(_ slot: WearSlot) -> (scale: Float, from: SIMD3<Float>, to: SIMD3<Float>) {
        switch slot {
        case .head: return (0.2, crown, SIMD3(0, 0.39, 0.15))
        case .neck: return (0.3, neckCenter, SIMD3(0, 0.235, 0.12))
        case .back: return (0.22, SIMD3(0, 2.22, 0.3), SIMD3(0, 0.245, 0))
        }
    }
}
