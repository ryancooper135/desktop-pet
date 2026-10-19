// Маленький программный растеризатор под стиль C (волна 13, «Щенок против зомби»): PS1-вид без ассетов и без GPU.
// • Низкое разрешение (≈176 точек в ширину), экран растягивает картинку без сглаживания — пиксели видно.
// • Вершины после проекции прилипают к целым пикселям (дрожание PS1), текстурные координаты и туман
//   тянутся по треугольнику аффинно, без перспективной поправки — пол «плывёт», как на PS1.
// • Освещение плоское (на треугольник), туман по вершинам, z-буфер по 1/z.
// • Выход — RGBA 8 бит после байеровского дизеринга 4×4 и обрезки до levels уровней на канал.
// Чистый Swift без simd и без UIKit: собирается и на Linux (WSL-тесты рисуют кадр и проверяют пиксели).

import Foundation

// MARK: - Вектор

struct RVec: Hashable, Sendable {
    var x: Double
    var y: Double
    var z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    static let zero = RVec(0, 0, 0)
    static let one = RVec(1, 1, 1)

    static func + (a: RVec, b: RVec) -> RVec { RVec(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: RVec, b: RVec) -> RVec { RVec(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: RVec, k: Double) -> RVec { RVec(a.x * k, a.y * k, a.z * k) }
    static func * (a: RVec, b: RVec) -> RVec { RVec(a.x * b.x, a.y * b.y, a.z * b.z) }

    func dot(_ b: RVec) -> Double { x * b.x + y * b.y + z * b.z }
    func cross(_ b: RVec) -> RVec { RVec(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x) }
    var length: Double { dot(self).squareRoot() }
    var normalized: RVec {
        let l = length
        return l > 1e-12 ? self * (1 / l) : self
    }

    func mix(_ b: RVec, _ k: Double) -> RVec { self + (b - self) * k }

    /// Цвет из 0xRRGGBB.
    static func hex(_ v: UInt32) -> RVec {
        RVec(Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}

// MARK: - Сетка

enum RetroPattern: UInt8, Sendable {
    case solid
    /// Шахматка по целым u, v.
    case checker
    /// Полосы по целому u.
    case stripes
}

struct RetroTri: Sendable {
    var a: RVec
    var b: RVec
    var c: RVec
    var color: RVec
    /// Второй цвет узора (шахматка, полосы).
    var color2: RVec
    var pattern: RetroPattern = .solid
    /// Текстурные координаты вершин (x = u, y = v).
    var ua = RVec.zero
    var ub = RVec.zero
    var uc = RVec.zero
    /// Светится сам: без освещения (лампы, сердечки), туман всё равно ложится.
    var unlit = false
}

struct RetroMesh: Sendable {
    var tris: [RetroTri] = []

    init(_ tris: [RetroTri] = []) { self.tris = tris }

    static func + (a: RetroMesh, b: RetroMesh) -> RetroMesh { RetroMesh(a.tris + b.tris) }

    mutating func add(_ m: RetroMesh) { tris += m.tris }

    /// Треугольник лицом от точки away (выпуклые части: нормаль наружу от центра).
    mutating func tri(_ a: RVec, _ b: RVec, _ c: RVec, away: RVec, _ color: RVec, unlit: Bool = false) {
        let n = (b - a).cross(c - a)
        let mid = (a + b + c) * (1.0 / 3)
        if n.dot(mid - away) >= 0 {
            tris.append(RetroTri(a: a, b: b, c: c, color: color, color2: color, unlit: unlit))
        } else {
            tris.append(RetroTri(a: a, b: c, c: b, color: color, color2: color, unlit: unlit))
        }
    }

    /// Четырёхугольник p0…p3 по кругу, лицом в сторону normal. uv — координаты углов для узора.
    mutating func quad(_ p0: RVec, _ p1: RVec, _ p2: RVec, _ p3: RVec, normal: RVec, _ color: RVec,
                       color2: RVec? = nil, pattern: RetroPattern = .solid,
                       uv: (RVec, RVec, RVec, RVec) = (.zero, .zero, .zero, .zero), unlit: Bool = false) {
        var p = [p0, p1, p2, p3]
        var t = [uv.0, uv.1, uv.2, uv.3]
        if (p[1] - p[0]).cross(p[2] - p[0]).dot(normal) < 0 {
            p = [p[0], p[3], p[2], p[1]]
            t = [t[0], t[3], t[2], t[1]]
        }
        let c2 = color2 ?? color
        tris.append(RetroTri(a: p[0], b: p[1], c: p[2], color: color, color2: c2, pattern: pattern,
                             ua: t[0], ub: t[1], uc: t[2], unlit: unlit))
        tris.append(RetroTri(a: p[0], b: p[2], c: p[3], color: color, color2: c2, pattern: pattern,
                             ua: t[0], ub: t[2], uc: t[3], unlit: unlit))
    }

    /// Коробка с центром center и размерами size. top — свой цвет верха (у собаки светлая спина и т. п.).
    static func box(_ size: RVec, at center: RVec = .zero, _ color: RVec, top: RVec? = nil, front: RVec? = nil,
                    unlit: Bool = false) -> RetroMesh {
        let h = size * 0.5
        func p(_ sx: Double, _ sy: Double, _ sz: Double) -> RVec { center + RVec(sx * h.x, sy * h.y, sz * h.z) }
        var m = RetroMesh()
        m.quad(p(1, -1, -1), p(1, 1, -1), p(1, 1, 1), p(1, -1, 1), normal: RVec(1, 0, 0), color, unlit: unlit)
        m.quad(p(-1, -1, -1), p(-1, 1, -1), p(-1, 1, 1), p(-1, -1, 1), normal: RVec(-1, 0, 0), color, unlit: unlit)
        m.quad(p(-1, 1, -1), p(1, 1, -1), p(1, 1, 1), p(-1, 1, 1), normal: RVec(0, 1, 0), top ?? color, unlit: unlit)
        m.quad(p(-1, -1, -1), p(1, -1, -1), p(1, -1, 1), p(-1, -1, 1), normal: RVec(0, -1, 0), color, unlit: unlit)
        m.quad(p(-1, -1, 1), p(1, -1, 1), p(1, 1, 1), p(-1, 1, 1), normal: RVec(0, 0, 1), front ?? color, unlit: unlit)
        m.quad(p(-1, -1, -1), p(1, -1, -1), p(1, 1, -1), p(-1, 1, -1), normal: RVec(0, 0, -1), color, unlit: unlit)
        return m
    }

    /// Четырёхгранная пирамидка: основание size.x × size.z в y = 0, вершина на высоте size.y (уши, колпак).
    static func pyramid(_ size: RVec, at base: RVec = .zero, _ color: RVec, tip: RVec = .zero) -> RetroMesh {
        let hx = size.x / 2, hz = size.z / 2
        let corners = [RVec(-hx, 0, -hz), RVec(hx, 0, -hz), RVec(hx, 0, hz), RVec(-hx, 0, hz)].map { $0 + base }
        let apex = base + RVec(tip.x, size.y, tip.z)
        let mid = base + RVec(0, size.y * 0.3, 0)
        var m = RetroMesh()
        for i in 0..<4 { m.tri(corners[i], corners[(i + 1) % 4], apex, away: mid, color) }
        m.quad(corners[0], corners[1], corners[2], corners[3], normal: RVec(0, -1, 0), color)
        return m
    }

    /// Гранёный шарик (октаэдр, разбитый один раз: 32 грани).
    static func ball(_ r: Double, at center: RVec = .zero, _ color: RVec, stripe: RVec? = nil) -> RetroMesh {
        let ax = [RVec(1, 0, 0), RVec(0, 1, 0), RVec(-1, 0, 0), RVec(0, -1, 0)]
        var m = RetroMesh()
        for pole in [RVec(0, 0, 1), RVec(0, 0, -1)] {
            for i in 0..<4 {
                let a = ax[i], b = ax[(i + 1) % 4], c = pole
                let ab = (a + b).normalized, bc = (b + c).normalized, ca = (c + a).normalized
                for (k, t) in [(a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)].enumerated() {
                    let col = (stripe != nil && k == 3) ? stripe! : color
                    m.tri(center + t.0 * r, center + t.1 * r, center + t.2 * r, away: center, col)
                }
            }
        }
        return m
    }

    /// Плоское сердечко в плоскости xy (смотрит на −z и +z: рисовать без отсечения задних граней).
    static func heart(_ size: Double, _ color: RVec) -> RetroMesh {
        let pts: [(Double, Double)] = [(0, -0.9), (0.55, -0.3), (0.85, 0.15), (0.75, 0.55), (0.45, 0.7),
                                       (0.15, 0.55), (0, 0.35), (-0.15, 0.55), (-0.45, 0.7), (-0.75, 0.55),
                                       (-0.85, 0.15), (-0.55, -0.3)]
        let c = RVec(0, 0.1 * size, 0)
        var m = RetroMesh()
        for i in 0..<pts.count {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            m.tris.append(RetroTri(a: c, b: RVec(a.0 * size, a.1 * size, 0), c: RVec(b.0 * size, b.1 * size, 0),
                                   color: color, color2: color, unlit: true))
        }
        return m
    }

    /// Плоский многоугольник на полу (тень), смотрит вверх.
    static func disc(_ rx: Double, _ rz: Double, y: Double = 0.012, _ color: RVec, sides: Int = 8) -> RetroMesh {
        var m = RetroMesh()
        let c = RVec(0, y, 0)
        for i in 0..<sides {
            let a0 = Double(i) / Double(sides) * 2 * .pi, a1 = Double(i + 1) / Double(sides) * 2 * .pi
            m.tri(c, RVec(cos(a0) * rx, y, sin(a0) * rz), RVec(cos(a1) * rx, y, sin(a1) * rz),
                  away: RVec(0, y - 1, 0), color, unlit: true)
        }
        return m
    }
}

// MARK: - Положение части

/// Масштаб → наклон вперёд (pitch, вокруг x) → крен (roll, вокруг z) → поворот (yaw, вокруг y) → сдвиг.
struct RetroPose: Sendable {
    var pos = RVec.zero
    var yaw = 0.0
    var pitch = 0.0
    var roll = 0.0
    var scale = RVec.one

    init(_ pos: RVec = .zero, yaw: Double = 0, pitch: Double = 0, roll: Double = 0, scale: RVec = .one) {
        self.pos = pos
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
        self.scale = scale
    }

    init(_ pos: RVec, yaw: Double = 0, pitch: Double = 0, roll: Double = 0, size: Double) {
        self.init(pos, yaw: yaw, pitch: pitch, roll: roll, scale: RVec(size, size, size))
    }

    func apply(_ p0: RVec) -> RVec {
        var p = p0 * scale
        if pitch != 0 {
            let c = cos(pitch), s = sin(pitch)
            p = RVec(p.x, p.y * c - p.z * s, p.y * s + p.z * c)
        }
        if roll != 0 {
            let c = cos(roll), s = sin(roll)
            p = RVec(p.x * c - p.y * s, p.x * s + p.y * c, p.z)
        }
        if yaw != 0 {
            let c = cos(yaw), s = sin(yaw)
            p = RVec(p.x * c + p.z * s, p.y, -p.x * s + p.z * c)
        }
        return p + pos
    }
}

// MARK: - Камера, свет, туман

struct RetroCamera: Sendable {
    var eye: RVec
    var target: RVec
    var up = RVec(0, 1, 0)
    /// Вертикальный угол обзора, радианы.
    var fovY = 1.2
    var near = 0.15
}

struct RetroFog: Sendable {
    var color: RVec
    var start: Double
    var end: Double
}

struct RetroLight: Sendable {
    /// Направление НА свет.
    var dir = RVec(-0.35, 1, -0.55).normalized
    var ambient = 0.55
    var diffuse = 0.5
}

// MARK: - Холст

struct RetroCanvas: Sendable {
    let w: Int
    let h: Int
    /// r, g, b подряд, 0…1.
    private(set) var rgb: [Double]
    /// 1/z ближайшего: больше — ближе; 0 — пусто.
    private(set) var depth: [Double]
    var fog = RetroFog(color: RVec(0, 0, 0), start: 1e9, end: 2e9)
    var light = RetroLight()
    /// Вершины к целым пикселям (PS1). Выключается в тестах точной геометрии.
    var jitter = true

    private var eye = RVec.zero
    private var right = RVec(1, 0, 0)
    private var up = RVec(0, 1, 0)
    private var fwd = RVec(0, 0, 1)
    private var focal = 1.0
    private var near = 0.15

    /// Сколько треугольников дошло до растеризации в этом кадре (для тестов и замеров).
    private(set) var drawn = 0

    init(w: Int, h: Int) {
        self.w = Swift.max(1, w)
        self.h = Swift.max(1, h)
        rgb = [Double](repeating: 0, count: self.w * self.h * 3)
        depth = [Double](repeating: 0, count: self.w * self.h)
    }

    /// Новый кадр: камера и фон — вертикальный градиент top → bottom.
    mutating func begin(_ cam: RetroCamera, top: RVec, bottom: RVec) {
        eye = cam.eye
        fwd = (cam.target - cam.eye).normalized
        right = fwd.cross(cam.up).normalized
        up = right.cross(fwd)
        focal = Double(h) * 0.5 / tan(cam.fovY / 2)
        near = cam.near
        drawn = 0
        let w = self.w, h = self.h
        rgb.withUnsafeMutableBufferPointer { px in
            for y in 0..<h {
                let c = top.mix(bottom, h > 1 ? Double(y) / Double(h - 1) : 0)
                var i = y * w * 3
                for _ in 0..<w {
                    px[i] = c.x
                    px[i + 1] = c.y
                    px[i + 2] = c.z
                    i += 3
                }
            }
        }
        depth.withUnsafeMutableBufferPointer { d in
            for i in 0..<d.count { d[i] = 0 }
        }
    }

    /// Где на холсте точка мира (nil — за камерой). Для подписей поверх картинки.
    func project(_ p: RVec) -> (x: Double, y: Double)? {
        let v = p - eye
        let z = v.dot(fwd)
        guard z > near else { return nil }
        return (Double(w) / 2 + v.dot(right) / z * focal, Double(h) / 2 - v.dot(up) / z * focal)
    }

    /// Нарисовать сетку: позы применяются по порядку (часть → тело → мир). tint — подмешать цвет (вспышка удара).
    mutating func draw(_ mesh: RetroMesh, _ poses: [RetroPose] = [], tint: RVec? = nil, tintK: Double = 0,
                       cull: Bool = true) {
        for t in mesh.tris {
            var a = t.a, b = t.b, c = t.c
            for p in poses {
                a = p.apply(a)
                b = p.apply(b)
                c = p.apply(c)
            }
            let n = (b - a).cross(c - a).normalized
            let facing = n.dot(a - eye)
            if cull && facing >= 0 { continue }
            var k = 1.0
            if !t.unlit {
                var d = n.dot(light.dir)
                if !cull && facing > 0 { d = -d }
                k = light.ambient + light.diffuse * Swift.max(0, d)
            }
            var c1 = t.color, c2 = t.color2
            if let tint, tintK > 0 {
                c1 = c1.mix(tint, tintK)
                c2 = c2.mix(tint, tintK)
            }
            triangle(a, b, c, t.ua, t.ub, t.uc, c1 * k, c2 * k, t.pattern)
        }
    }

    // MARK: растеризация

    private struct V {
        var x: Double
        var y: Double
        var z: Double
        var u: Double
        var v: Double
    }

    private mutating func triangle(_ a: RVec, _ b: RVec, _ c: RVec, _ ta: RVec, _ tb: RVec, _ tc: RVec,
                                   _ c1: RVec, _ c2: RVec, _ pattern: RetroPattern) {
        func view(_ p: RVec, _ t: RVec) -> V {
            let d = p - eye
            return V(x: d.dot(right), y: d.dot(up), z: d.dot(fwd), u: t.x, v: t.y)
        }
        var poly = [view(a, ta), view(b, tb), view(c, tc)]
        if poly.allSatisfy({ $0.z < near }) { return }
        if poly.contains(where: { $0.z < near }) {
            // Отрезать всё ближе near (Сазерленд — Ходжман по одной плоскости).
            var out: [V] = []
            for i in 0..<poly.count {
                let p = poly[i], q = poly[(i + 1) % poly.count]
                if p.z >= near { out.append(p) }
                if (p.z >= near) != (q.z >= near) {
                    let k = (near - p.z) / (q.z - p.z)
                    out.append(V(x: p.x + (q.x - p.x) * k, y: p.y + (q.y - p.y) * k, z: near,
                                 u: p.u + (q.u - p.u) * k, v: p.v + (q.v - p.v) * k))
                }
            }
            poly = out
            guard poly.count >= 3 else { return }
        }
        let cx = Double(w) / 2, cy = Double(h) / 2
        let span = Swift.max(1e-9, fog.end - fog.start)
        let screen: [S] = poly.map { p in
            var sx = cx + p.x / p.z * focal
            var sy = cy - p.y / p.z * focal
            if jitter {
                sx = sx.rounded()
                sy = sy.rounded()
            }
            let f = Swift.min(1, Swift.max(0, (p.z - fog.start) / span))
            return S(x: sx, y: sy, inv: 1 / p.z, fog: f, u: p.u, v: p.v)
        }
        for i in 1..<(screen.count - 1) {
            raster(screen[0], screen[i], screen[i + 1], c1, c2, pattern)
        }
    }

    private struct S {
        var x: Double
        var y: Double
        var inv: Double
        var fog: Double
        var u: Double
        var v: Double
    }

    private mutating func raster(_ p0: S, _ p1In: S, _ p2In: S, _ c1: RVec, _ c2: RVec, _ pattern: RetroPattern) {
        var p1 = p1In, p2 = p2In
        var area = (p1.x - p0.x) * (p2.y - p0.y) - (p2.x - p0.x) * (p1.y - p0.y)
        if abs(area) < 1e-9 { return }
        if area < 0 {
            swap(&p1, &p2)
            area = -area
        }
        let minX = Swift.max(0, Int(Swift.min(p0.x, p1.x, p2.x).rounded(.down)))
        let maxX = Swift.min(w - 1, Int(Swift.max(p0.x, p1.x, p2.x).rounded(.up)))
        let minY = Swift.max(0, Int(Swift.min(p0.y, p1.y, p2.y).rounded(.down)))
        let maxY = Swift.min(h - 1, Int(Swift.max(p0.y, p1.y, p2.y).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return }
        drawn += 1
        let inv = 1 / area
        // edge(a, b, p) = (b.x − a.x)(p.y − a.y) − (b.y − a.y)(p.x − a.x): вес вершины против ребра.
        let e0dx = -(p2.y - p1.y), e0dy = p2.x - p1.x
        let e1dx = -(p0.y - p2.y), e1dy = p0.x - p2.x
        let e2dx = -(p1.y - p0.y), e2dy = p1.x - p0.x
        let fogC = fog.color
        let w = self.w
        let s0 = p0, s1 = p1, s2 = p2
        // Буферы — во временные переменные: два withUnsafe… по свойствам self сразу компилятор не пустит.
        var colors = rgb
        var depths = depth
        rgb = []
        depth = []
        defer {
            rgb = colors
            depth = depths
        }
        colors.withUnsafeMutableBufferPointer { px in
            depths.withUnsafeMutableBufferPointer { dz in
                for y in minY...maxY {
                    let fy = Double(y) + 0.5
                    let fx0 = Double(minX) + 0.5
                    var w0 = e0dy * (fy - s1.y) + e0dx * (fx0 - s1.x)
                    var w1 = e1dy * (fy - s2.y) + e1dx * (fx0 - s2.x)
                    var w2 = e2dy * (fy - s0.y) + e2dx * (fx0 - s0.x)
                    var i = y * w + minX
                    for _ in minX...maxX {
                        if w0 >= 0 && w1 >= 0 && w2 >= 0 {
                            let l0 = w0 * inv, l1 = w1 * inv, l2 = w2 * inv
                            let d = l0 * s0.inv + l1 * s1.inv + l2 * s2.inv
                            if d > dz[i] {
                                dz[i] = d
                                var col = c1
                                if pattern != .solid {
                                    let u = l0 * s0.u + l1 * s1.u + l2 * s2.u
                                    let v = l0 * s0.v + l1 * s1.v + l2 * s2.v
                                    let cell: Int
                                    if pattern == .checker {
                                        cell = Int(u.rounded(.down)) &+ Int(v.rounded(.down))
                                    } else {
                                        cell = Int(u.rounded(.down))
                                    }
                                    if cell & 1 != 0 { col = c2 }
                                }
                                let f = l0 * s0.fog + l1 * s1.fog + l2 * s2.fog
                                let j = i * 3
                                px[j] = col.x + (fogC.x - col.x) * f
                                px[j + 1] = col.y + (fogC.y - col.y) * f
                                px[j + 2] = col.z + (fogC.z - col.z) * f
                            }
                        }
                        w0 += e0dx
                        w1 += e1dx
                        w2 += e2dx
                        i += 1
                    }
                }
            }
        }
    }

    // MARK: выход

    /// Байер 4×4 (0…15).
    static let bayer: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

    /// Цвет точки до дизеринга (тесты).
    func color(x: Int, y: Int) -> RVec {
        let i = (y * w + x) * 3
        return RVec(rgb[i], rgb[i + 1], rgb[i + 2])
    }

    /// Было ли что-то нарисовано в точке (не фон).
    func covered(x: Int, y: Int) -> Bool { depth[y * w + x] > 0 }

    /// RGBA по 8 бит построчно сверху вниз: дизеринг Байера ±½ ступени и levels уровней на канал (PS1 — 32, тут грубее).
    func rgba(levels: Int = 24, dither: Bool = true) -> [UInt8] {
        let n = Double(Swift.max(2, levels) - 1)
        var out = [UInt8](repeating: 255, count: w * h * 4)
        let w = self.w, h = self.h
        rgb.withUnsafeBufferPointer { px in
            out.withUnsafeMutableBufferPointer { o in
                for y in 0..<h {
                    for x in 0..<w {
                        let t = dither ? (Self.bayer[(y & 3) * 4 + (x & 3)] + 0.5) / 16 - 0.5 : 0
                        let i = y * w + x
                        for ch in 0..<3 {
                            let v = Swift.min(n, Swift.max(0, (px[i * 3 + ch] * n + t).rounded()))
                            o[i * 4 + ch] = UInt8((v / n * 255).rounded())
                        }
                    }
                }
            }
        }
        return out
    }

    /// Картинка PPM (P6) — посмотреть кадр из тестов без телефона.
    func ppm(levels: Int = 24, dither: Bool = true) -> Data {
        let px = rgba(levels: levels, dither: dither)
        var d = Data("P6\n\(w) \(h)\n255\n".utf8)
        d.reserveCapacity(d.count + w * h * 3)
        for i in 0..<(w * h) {
            d.append(px[i * 4])
            d.append(px[i * 4 + 1])
            d.append(px[i * 4 + 2])
        }
        return d
    }
}
