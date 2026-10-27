// Станции двора и подложки ярусов в 3D (волна 33 F, RESEARCH/20-tycoon-design.md §1–§2): процедурный low-poly
// без текстур, плоские нормали, как вещи комнаты (RoomDecor) — стиль A. Здесь только геометрия и описание
// движения, без RealityKit: файл собирается и на Linux, треугольники считаются чистой функцией (бюджет §2 —
// не больше 400 на станцию). В сущности RealityKit всё переводит YardStage.
//
// Имена с приставкой YardArt: Yard, YardStation, YardTier — модель агента C (Shared/Yard.swift), не путать.
// Оси как у комнаты: y вверх, +z к камере; у станции начало координат — центр пятна на земле.

import Foundation

// MARK: - Математика

enum YardArtMath {
    static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    static func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { (a * b).sum() }

    static func normalize(_ a: SIMD3<Float>) -> SIMD3<Float> {
        let l = dot(a, a).squareRoot()
        return l > 1e-9 ? a / l : .zero
    }

    /// Повороты на deg градусов по правилу правой руки: rotX(+) клонит +y к +z, rotY(+) ведёт +z к +x, rotZ(+) ведёт +x к +y.
    static func rotX(_ v: SIMD3<Float>, _ deg: Float) -> SIMD3<Float> {
        guard deg != 0 else { return v }
        let a = deg * .pi / 180, c = cos(a), s = sin(a)
        return SIMD3(v.x, v.y * c - v.z * s, v.y * s + v.z * c)
    }

    static func rotY(_ v: SIMD3<Float>, _ deg: Float) -> SIMD3<Float> {
        guard deg != 0 else { return v }
        let a = deg * .pi / 180, c = cos(a), s = sin(a)
        return SIMD3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c)
    }

    static func rotZ(_ v: SIMD3<Float>, _ deg: Float) -> SIMD3<Float> {
        guard deg != 0 else { return v }
        let a = deg * .pi / 180, c = cos(a), s = sin(a)
        return SIMD3(v.x * c - v.y * s, v.x * s + v.y * c, v.z)
    }

    static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
}

/// Место детали: масштаб, поворот (сначала z, потом x, потом y; градусы), сдвиг.
struct YardArtXform: Sendable {
    var at: SIMD3<Float> = .zero
    var rot: SIMD3<Float> = .zero
    var scale: SIMD3<Float> = .one

    func apply(_ v: SIMD3<Float>) -> SIMD3<Float> {
        YardArtMath.rotY(YardArtMath.rotX(YardArtMath.rotZ(v * scale, rot.z), rot.x), rot.y) + at
    }
}

// MARK: - Сетка

/// Сетка одного цвета: у каждой грани свои вершины (плоские нормали, ретро-грани без сглаживания).
struct YardArtMesh: Sendable {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []

    var triangles: Int { indices.count / 3 }

    /// Выпуклое тело гранями; каждая грань — выпуклый многоугольник, режется веером. Обход каждой грани
    /// выправляется наружу от центра тела (против часовой снаружи — лицевая сторона в RealityKit),
    /// поэтому порядок вершин в описании примитивов не важен. Тело должно быть выпуклым и замкнутым
    /// или открытым, но с центром внутри (корзинка без крышки).
    mutating func solid(_ faces: [[SIMD3<Float>]]) {
        var sum = SIMD3<Float>.zero
        var count = 0
        for f in faces {
            for p in f { sum += p }
            count += f.count
        }
        guard count > 0 else { return }
        let center = sum / Float(count)
        for face in faces where face.count >= 3 {
            var pts = face
            var n = YardArtMath.normalize(YardArtMath.cross(pts[1] - pts[0], pts[2] - pts[0]))
            guard n != .zero else { continue }
            var fc = SIMD3<Float>.zero
            for p in pts { fc += p }
            fc /= Float(pts.count)
            if YardArtMath.dot(n, fc - center) < 0 {
                pts.reverse()
                n = -n
            }
            let base = UInt32(positions.count)
            positions += pts
            normals += Array(repeating: n, count: pts.count)
            for k in 1..<(pts.count - 1) {
                indices += [base, base + UInt32(k), base + UInt32(k + 1)]
            }
        }
    }
}

/// Цвет детали: hex и «светится сама» (UnlitMaterial — лампочки, огонь, звёздная мука).
struct YardArtPaint: Hashable, Sendable {
    var hex: UInt32
    var glow: Bool
}

// MARK: - Движение

/// Ключ цикла: доля цикла t (0…1), сдвиг от места узла, масштаб (0 — спрятан), угол в градусах вокруг оси движения.
struct YardArtKey: Sendable {
    var t: Float
    var offset: SIMD3<Float> = .zero
    var scale: Float = 1
    var angle: Float = 0
}

/// Поза узла в момент времени: сдвиг, равномерный масштаб и поворот (ось, радианы).
struct YardArtPose: Sendable, Equatable {
    var offset: SIMD3<Float> = .zero
    var scale: Float = 1
    var axis: SIMD3<Float> = SIMD3(0, 1, 0)
    var angle: Float = 0
}

/// Как узел живёт в цикле (§2: цикл 2–6 с). Считается чистой функцией времени — без накопления ошибок.
enum YardArtMotion: Sendable {
    /// Крутится: оборотов в секунду.
    case spin(axis: SIMD3<Float>, rps: Float)
    /// Качается синусом: размах в градусах, период в секундах, фаза — доля периода.
    case swing(axis: SIMD3<Float>, deg: Float, period: Float, phase: Float)
    /// «Дышит» масштабом: 1 ± amount.
    case pulse(amount: Float, period: Float, phase: Float)
    /// Подпрыгивает по y синусом.
    case bob(height: Float, period: Float, phase: Float)
    /// Ключи по циклу с плавным ходом между ними (smoothstep); ключи от t = 0 до t = 1.
    case keys([YardArtKey], axis: SIMD3<Float>, period: Float, phase: Float)

    func pose(at time: Double) -> YardArtPose {
        func cycle(_ period: Float, _ phase: Float) -> Float {
            guard period > 0 else { return 0 }
            let u = time / Double(period) + Double(phase)
            return Float(u - u.rounded(.down))
        }
        switch self {
        case let .spin(axis, rps):
            let turns = time * Double(rps)
            return YardArtPose(axis: axis, angle: Float(turns - turns.rounded(.down)) * 2 * .pi)
        case let .swing(axis, deg, period, phase):
            let u = cycle(period, phase)
            return YardArtPose(axis: axis, angle: deg * .pi / 180 * sin(u * 2 * .pi))
        case let .pulse(amount, period, phase):
            return YardArtPose(scale: 1 + amount * sin(cycle(period, phase) * 2 * .pi))
        case let .bob(height, period, phase):
            return YardArtPose(offset: SIMD3(0, height * (0.5 + 0.5 * sin(cycle(period, phase) * 2 * .pi)), 0))
        case let .keys(keys, axis, period, phase):
            guard let first = keys.first else { return YardArtPose() }
            let u = cycle(period, phase)
            var a = first, b = first
            for k in keys {
                if k.t <= u { a = k; b = k } else { b = k; break }
            }
            var s: Float = 0
            if b.t > a.t {
                s = (u - a.t) / (b.t - a.t)
                s = s * s * (3 - 2 * s)
            }
            let off = a.offset + (b.offset - a.offset) * s
            return YardArtPose(offset: off, scale: YardArtMath.lerp(a.scale, b.scale, s), axis: axis,
                               angle: YardArtMath.lerp(a.angle, b.angle, s) * .pi / 180)
        }
    }
}

// MARK: - Модель

/// Узел модели: место в модели, движение и сетки по цветам (одна сущность на цвет, без .perFace).
struct YardArtNode: Sendable {
    var name: String
    var at: SIMD3<Float>
    var motion: YardArtMotion?
    var meshes: [YardArtPaint: YardArtMesh] = [:]

    var triangles: Int { meshes.values.reduce(0) { $0 + $1.triangles } }
}

/// Модель станции или подложки: плоский список узлов. Детали пишутся в последний открытый узел.
struct YardArtModel: Sendable {
    var name: String
    var nodes: [YardArtNode]

    init(name: String) {
        self.name = name
        nodes = [YardArtNode(name: "body", at: .zero, motion: nil)]
    }

    var triangles: Int { nodes.reduce(0) { $0 + $1.triangles } }

    /// Новый узел: дальше детали идут в него, координаты деталей — от точки at.
    mutating func node(_ name: String, at: SIMD3<Float>, motion: YardArtMotion? = nil) {
        nodes.append(YardArtNode(name: name, at: at, motion: motion))
    }

    /// Вернуться к неподвижному корпусу.
    mutating func body() {
        node("body\(nodes.count)", at: .zero)
    }

    private mutating func add(_ hex: UInt32, glow: Bool, _ faces: [[SIMD3<Float>]], _ xf: YardArtXform) {
        let moved = faces.map { $0.map(xf.apply) }
        let key = YardArtPaint(hex: hex, glow: glow)
        nodes[nodes.count - 1].meshes[key, default: YardArtMesh()].solid(moved)
    }

    /// Брусок: 12 треугольников.
    mutating func box(_ hex: UInt32, _ size: SIMD3<Float>, at: SIMD3<Float>, rot: SIMD3<Float> = .zero,
                      glow: Bool = false) {
        let h = size / 2
        func v(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { h * SIMD3(x, y, z) }
        let faces: [[SIMD3<Float>]] = [
            [v(-1, -1, 1), v(1, -1, 1), v(1, 1, 1), v(-1, 1, 1)],
            [v(-1, -1, -1), v(1, -1, -1), v(1, 1, -1), v(-1, 1, -1)],
            [v(-1, 1, -1), v(1, 1, -1), v(1, 1, 1), v(-1, 1, 1)],
            [v(-1, -1, -1), v(1, -1, -1), v(1, -1, 1), v(-1, -1, 1)],
            [v(1, -1, -1), v(1, 1, -1), v(1, 1, 1), v(1, -1, 1)],
            [v(-1, -1, -1), v(-1, 1, -1), v(-1, 1, 1), v(-1, -1, 1)],
        ]
        add(hex, glow: glow, faces, YardArtXform(at: at, rot: rot))
    }

    /// Призма/усечённый конус вдоль y, центр по высоте в at. top = 0 — конус. Плоская грань смотрит на +z.
    /// Треугольники: стенки 2n (у конуса n), крышки по n − 2 (bottom: false — без дна).
    mutating func prism(_ hex: UInt32, sides n: Int, r: Float, h: Float, top: Float? = nil, at: SIMD3<Float>,
                        rot: SIMD3<Float> = .zero, scale: SIMD3<Float> = .one, bottom: Bool = true,
                        glow: Bool = false) {
        let rt = top ?? r
        func ring(_ rr: Float, _ y: Float) -> [SIMD3<Float>] {
            (0..<n).map { k in
                let a = (Float(k) + 0.5) * 2 * .pi / Float(n)
                return SIMD3(rr * sin(a), y, rr * cos(a))
            }
        }
        let lo = ring(r, -h / 2), hi = ring(rt, h / 2)
        var faces: [[SIMD3<Float>]] = []
        for k in 0..<n {
            let j = (k + 1) % n
            if rt > 0 {
                faces.append([lo[k], lo[j], hi[j], hi[k]])
            } else {
                faces.append([lo[k], lo[j], SIMD3(0, h / 2, 0)])
            }
        }
        if rt > 0 { faces.append(hi) }
        if bottom { faces.append(lo) }
        add(hex, glow: glow, faces, YardArtXform(at: at, rot: rot, scale: scale))
    }

    /// Двойная пирамида: кольцо из n вершин и две верхушки. 2n треугольников; n = 4 — октаэдр.
    mutating func gem(_ hex: UInt32, sides n: Int, r: Float, h: Float, at: SIMD3<Float>,
                      rot: SIMD3<Float> = .zero, scale: SIMD3<Float> = .one, glow: Bool = false) {
        let ring: [SIMD3<Float>] = (0..<n).map { k in
            let a = (Float(k) + 0.5) * 2 * .pi / Float(n)
            return SIMD3(r * sin(a), 0, r * cos(a))
        }
        let up = SIMD3<Float>(0, h / 2, 0)
        var faces: [[SIMD3<Float>]] = []
        for k in 0..<n {
            let j = (k + 1) % n
            faces.append([ring[k], ring[j], up])
            faces.append([ring[k], ring[j], -up])
        }
        add(hex, glow: glow, faces, YardArtXform(at: at, rot: rot, scale: scale))
    }

    /// Плоская табличка w × h: 2 треугольника, видна с одной стороны — с +z (up: true — сверху, с +y).
    /// Для огней окон и бликов на воде (волна 37 B): у бруска на такой огонёк уходило 12 треугольников.
    mutating func panel(_ hex: UInt32, _ size: SIMD2<Float>, at: SIMD3<Float>, rot: SIMD3<Float> = .zero,
                        up: Bool = false, glow: Bool = false) {
        let w = size.x / 2, h = size.y / 2
        let face: [SIMD3<Float>] = up
            ? [SIMD3(-w, 0, h), SIMD3(w, 0, h), SIMD3(w, 0, -h), SIMD3(-w, 0, -h)]
            : [SIMD3(-w, -h, 0), SIMD3(w, -h, 0), SIMD3(w, h, 0), SIMD3(-w, h, 0)]
        add(hex, glow: glow, [face], YardArtXform(at: at, rot: rot))
    }
}

// MARK: - Вид по уровню

/// Три вида станции (§2): уровни 1–2 доска, 3–4 металл, 5 медь с лампочками.
enum YardArtLook: Int, CaseIterable, Sendable {
    case board, metal, copper

    static func of(level: Int) -> YardArtLook { level >= 5 ? .copper : level >= 3 ? .metal : .board }

    var title: String {
        switch self {
        case .board: return "доска"
        case .metal: return "металл"
        case .copper: return "медь"
        }
    }

    /// Основной цвет каркаса и тёмная отделка.
    var frame: UInt32 {
        switch self {
        case .board: return 0xc9a27e
        case .metal: return 0x9aa6ad
        case .copper: return 0xd08a5a
        }
    }

    var trim: UInt32 {
        switch self {
        case .board: return 0x9c6b45
        case .metal: return 0x6f7a82
        case .copper: return 0xa8643a
        }
    }

    /// Поднос с монетами: на доске — синяя жесть, дальше в цвет каркаса.
    var tray: UInt32 {
        switch self {
        case .board: return 0x7fa7c9
        case .metal: return 0xb9c3c9
        case .copper: return 0xe3a46a
        }
    }
}

// MARK: - Станции

enum YardArtStation: Int, CaseIterable, Sendable {
    case dryer = 1, bonePatch, porridge, wheel, oven, photo, conveyor, mill

    var title: String {
        switch self {
        case .dryer: return "Сушилка сухариков"
        case .bonePatch: return "Косточковая грядка"
        case .porridge: return "Котелок каши"
        case .wheel: return "Прялка из шерсти"
        case .oven: return "Пирожковая печь"
        case .photo: return "Фотобудка"
        case .conveyor: return "Сосисочный конвейер"
        case .mill: return "Лунная мельница"
        }
    }

    /// 🪙/ч по уровням 1–5 (§2) — только для подписи макета. Волна 34 возьмёт ставки из Yard (агент C).
    var rates: [Int] {
        switch self {
        case .dryer: return [4, 6, 8, 11, 14]
        case .bonePatch: return [6, 9, 13, 17, 22]
        case .porridge: return [9, 14, 19, 25, 32]
        case .wheel: return [13, 20, 27, 36, 47]
        case .oven: return [18, 27, 38, 50, 65]
        case .photo: return [24, 36, 50, 67, 86]
        case .conveyor: return [32, 48, 67, 90, 115]
        case .mill: return [42, 63, 88, 118, 151]
        }
    }

    func rate(level: Int) -> Int { rates[max(1, min(5, level)) - 1] }
}

/// Цвета двора, которых нет в DecorColors (RoomDecor): там комната, здесь улица.
enum YardArtColors {
    static let rope: UInt32 = 0xf6ead6
    static let pin: UInt32 = 0xe8c9a0
    static let rusk: UInt32 = 0xd9a066
    static let wicker: UInt32 = 0xd6a86a
    static let soil: UInt32 = 0x7a5236
    static let soilDark: UInt32 = 0x6a452c
    static let bone: UInt32 = 0xf6ead6
    static let signBoard: UInt32 = 0xf6ead6
    static let stone: UInt32 = 0x9a9a92
    static let flame: UInt32 = 0xf0a04b
    static let iron: UInt32 = 0x4a4f57
    static let porridge: UInt32 = 0xf1ebe0
    static let steam: UInt32 = 0xf2f2f2
    static let wool: UInt32 = 0xe39a55
    static let clay: UInt32 = 0xd98a5a
    static let chimney: UInt32 = 0xa65a48
    static let soot: UInt32 = 0x3d2a20
    static let ember: UInt32 = 0xffb347
    static let pie: UInt32 = 0xe0a060
    static let booth: UInt32 = 0x5fb3a8
    static let roof: UInt32 = 0xc8553d
    static let curtain: UInt32 = 0xd96a5a
    static let lens: UInt32 = 0x3d4b66
    static let lamp: UInt32 = 0xffd36b
    static let flash: UInt32 = 0xfff8e6
    static let paper: UInt32 = 0xfdfbf7
    static let belt: UInt32 = 0x3a3f4a
    static let steel: UInt32 = 0x9aa6ad
    static let sausage: UInt32 = 0xd96a5a
    static let knob: UInt32 = 0xe86a6a
    static let tower: UInt32 = 0xead0ae
    static let door: UInt32 = 0x5a3a28
    static let moon: UInt32 = 0xfff4d2
    static let flour: UInt32 = 0xfff8e6
    static let sack: UInt32 = 0xd6a86a
    static let coin: UInt32 = 0xe3c46a
    // подложки ярусов
    static let wall: UInt32 = 0xead0ae
    static let windowFrame: UInt32 = 0xd9bfa3
    static let glassDirty: UInt32 = 0x9fa8a6
    static let glass: UInt32 = 0xcfe9f7
    static let dirt: UInt32 = 0xa07850
    static let puddle: UInt32 = 0x8fa6ad
    static let trash: UInt32 = 0x3a3f4a
    static let litter: UInt32 = 0xc9c4bc
    static let fenceOld: UInt32 = 0xb3a088
    static let fence: UInt32 = 0xf6ead6
    static let tile: UInt32 = 0xd9cfc0
    static let grass: UInt32 = 0xa6d48f
    static let park: UInt32 = 0x8cc77a
    static let paving: UInt32 = 0xc9c4bc
    static let trunk: UInt32 = 0x9c6b45
    static let crown: UInt32 = 0x5fa860
    static let apple: UInt32 = 0xe05a4a
    static let water: UInt32 = 0xa9d8f0
    static let frog: UInt32 = 0x77b864
    static let mailbox: UInt32 = 0x6aa5e8
    static let flowerWhite: UInt32 = 0xffffff
    static let flowerYellow: UInt32 = 0xf6d34a
    static let leaf: UInt32 = 0x77b864
    static let pole: UInt32 = 0x4a4f57
    static let bench: UInt32 = 0xc9a27e
    static let sign: UInt32 = 0xf2a65a
}

enum YardArt {
    /// Бюджет §2: не больше 400 треугольников на станцию (с подносом и лампочками).
    static let stationBudget = 400

    /// Станция целиком: корпус, циклы, вид по уровню, поднос с 0–5 стопками по заполнению копилки (fill 0…1).
    /// night — мельница крутится быстрее и мука светится; brushed — Шибу расчесали, прялка вдвое быстрее.
    /// district (волна 37 B) — мелочь в духе района поверх станции (YardArt.accent): силуэт и вывески те же.
    static func station(_ s: YardArtStation, level: Int, fill: Float, night: Bool = false,
                        brushed: Bool = false, district: YardDistrict = .street) -> YardArtModel {
        let look = YardArtLook.of(level: level)
        var m = YardArtModel(name: "station\(s.rawValue)")
        // Плита-основание: в цвет вида — сразу видно, доска это, металл или медь.
        m.box(look.frame, SIMD3(0.5, 0.03, 0.45), at: SIMD3(0, 0.015, -0.025))
        let bulbs: [SIMD3<Float>]
        switch s {
        case .dryer: bulbs = dryer(&m, look)
        case .bonePatch: bulbs = bonePatch(&m, look)
        case .porridge: bulbs = porridge(&m, look)
        case .wheel: bulbs = wheel(&m, look, brushed: brushed)
        case .oven: bulbs = oven(&m, look)
        case .photo: bulbs = photo(&m, look)
        case .conveyor: bulbs = conveyor(&m, look)
        case .mill: bulbs = mill(&m, look, night: night)
        }
        m.body()
        tray(&m, look, fill: fill)
        if look == .copper {
            for b in bulbs { m.gem(YardArtColors.lamp, sides: 4, r: 0.014, h: 0.022, at: b, glow: true) }
        }
        accent(&m, s, district: district)
        return m
    }

    /// Поднос с монетами справа спереди на плите; стопок round(fill · 5).
    static func tray(_ m: inout YardArtModel, _ look: YardArtLook, fill: Float) {
        let c = SIMD3<Float>(0.155, 0.036, 0.13)
        m.box(look.tray, SIMD3(0.15, 0.012, 0.1), at: c)
        let spots: [SIMD2<Float>] = [SIMD2(-0.05, -0.025), SIMD2(0, -0.025), SIMD2(0.05, -0.025),
                                     SIMD2(-0.025, 0.025), SIMD2(0.025, 0.025)]
        let stacks = Int((max(0, min(1, fill)) * 5).rounded())
        for k in 0..<stacks {
            let p = spots[k]
            m.prism(YardArtColors.coin, sides: 6, r: 0.018, h: 0.024, at: SIMD3(c.x + p.x, 0.054, c.z + p.y),
                    bottom: false)
        }
    }

    // 1. Верёвка с прищепками: сухарики качаются, раз в 6 с один падает в корзинку.
    private static func dryer(_ m: inout YardArtModel, _ look: YardArtLook) -> [SIMD3<Float>] {
        let z: Float = -0.06, ropeY: Float = 0.34
        m.box(look.trim, SIMD3(0.03, 0.34, 0.03), at: SIMD3(-0.2, 0.2, z))
        m.box(look.trim, SIMD3(0.03, 0.34, 0.03), at: SIMD3(0.2, 0.2, z))
        m.box(YardArtColors.rope, SIMD3(0.43, 0.012, 0.012), at: SIMD3(0, ropeY, z))
        m.prism(YardArtColors.wicker, sides: 6, r: 0.07, h: 0.07, top: 0.085, at: SIMD3(-0.05, 0.065, 0.04))
        for (i, x) in [Float(-0.15), -0.08, 0.08, 0.15].enumerated() {
            m.node("rusk\(i)", at: SIMD3(x, ropeY, z),
                   motion: .swing(axis: SIMD3(1, 0, 0), deg: 14, period: 2.4, phase: Float(i) * 0.23))
            m.box(YardArtColors.pin, SIMD3(0.012, 0.03, 0.016), at: SIMD3(0, -0.008, 0))
            m.box(YardArtColors.rusk, SIMD3(0.045, 0.06, 0.018), at: SIMD3(0, -0.055, 0), rot: SIMD3(0, 0, i % 2 == 0 ? 8 : -8))
        }
        // Пятый сухарик: висит посередине, падает в корзинку, лежит и пропадает — и вешается новый.
        let basket = SIMD3<Float>(-0.05, 0.16 - ropeY + 0.05, 0.04 - z)
        m.node("ruskDrop", at: SIMD3(0, ropeY, z), motion: .keys([
            YardArtKey(t: 0, scale: 0),
            YardArtKey(t: 0.1),
            YardArtKey(t: 0.6),
            YardArtKey(t: 0.72, offset: basket, angle: 90),
            YardArtKey(t: 0.92, offset: basket, angle: 90),
            YardArtKey(t: 0.97, offset: basket, scale: 0, angle: 90),
            YardArtKey(t: 1, scale: 0),
        ], axis: SIMD3(0, 0, 1), period: 6, phase: 0))
        m.box(YardArtColors.rusk, SIMD3(0.045, 0.06, 0.018), at: SIMD3(0, -0.05, 0))
        return [SIMD3(-0.2, 0.39, z), SIMD3(0.2, 0.39, z), SIMD3(-0.115, 0.36, z), SIMD3(0.115, 0.36, z)]
    }

    // 2. Холмик с табличкой «копать тут»: земля вспучивается, косточка подпрыгивает и ложится в ящик.
    private static func bonePatch(_ m: inout YardArtModel, _ look: YardArtLook) -> [SIMD3<Float>] {
        let mound = SIMD3<Float>(-0.05, 0.065, -0.06)
        m.prism(YardArtColors.soil, sides: 8, r: 0.17, h: 0.07, top: 0.11, at: mound)
        m.box(look.trim, SIMD3(0.02, 0.2, 0.02), at: SIMD3(-0.19, 0.13, -0.17))
        m.box(YardArtColors.signBoard, SIMD3(0.12, 0.06, 0.012), at: SIMD3(-0.19, 0.2, -0.155), rot: SIMD3(0, 0, -6))
        let crate = SIMD3<Float>(0.15, 0.065, -0.1)
        m.box(look.frame, SIMD3(0.12, 0.07, 0.09), at: crate)
        m.box(look.trim, SIMD3(0.1, 0.006, 0.07), at: SIMD3(crate.x, 0.102, crate.z))
        let top = SIMD3<Float>(mound.x, 0.1, mound.z)
        m.node("bump", at: top, motion: .keys([
            YardArtKey(t: 0, scale: 1), YardArtKey(t: 0.12, scale: 1.6), YardArtKey(t: 0.25, scale: 1),
            YardArtKey(t: 1, scale: 1),
        ], axis: SIMD3(0, 1, 0), period: 4, phase: 0))
        m.gem(YardArtColors.soilDark, sides: 6, r: 0.06, h: 0.05, at: .zero)
        let inCrate = SIMD3<Float>(crate.x - top.x, 0.112 - top.y, crate.z - top.z)
        m.node("bone", at: top, motion: .keys([
            YardArtKey(t: 0, offset: SIMD3(0, -0.03, 0), scale: 0),
            YardArtKey(t: 0.2, offset: SIMD3(0, -0.03, 0), scale: 0),
            YardArtKey(t: 0.28, offset: SIMD3(0, 0.03, 0)),
            YardArtKey(t: 0.4, offset: SIMD3(0.02, 0.17, 0)),
            YardArtKey(t: 0.5, offset: SIMD3(inCrate.x * 0.55, 0.22, inCrate.z * 0.5), angle: 180),
            YardArtKey(t: 0.62, offset: inCrate, angle: 360),
            YardArtKey(t: 0.9, offset: inCrate, angle: 360),
            YardArtKey(t: 0.96, offset: inCrate, scale: 0, angle: 360),
            YardArtKey(t: 1, offset: SIMD3(0, -0.03, 0), scale: 0),
        ], axis: SIMD3(0, 0, 1), period: 4, phase: 0))
        boneShape(&m, at: .zero)
        return [SIMD3(crate.x - 0.06, 0.11, crate.z + 0.045), SIMD3(crate.x + 0.06, 0.11, crate.z + 0.045),
                SIMD3(-0.25, 0.235, -0.155), SIMD3(-0.13, 0.235, -0.155)]
    }

    /// Косточка: перекладина и четыре шишки. 44 треугольника.
    static func boneShape(_ m: inout YardArtModel, at c: SIMD3<Float>, scale s: Float = 1) {
        m.box(YardArtColors.bone, SIMD3(0.07, 0.018, 0.018) * s, at: c)
        for x in [Float(-0.038), 0.038] {
            for y in [Float(-0.01), 0.01] {
                m.gem(YardArtColors.bone, sides: 4, r: 0.016 * s, h: 0.026 * s, at: c + SIMD3(x, y, 0) * s)
            }
        }
    }

    // 3. Котёл на трёх камнях: пар кольцами, ложка мешает сама.
    private static func porridge(_ m: inout YardArtModel, _ look: YardArtLook) -> [SIMD3<Float>] {
        let c = SIMD3<Float>(-0.03, 0, -0.06)
        for a in [Float(90), 210, 330] {
            let p = YardArtMath.rotY(SIMD3(0, 0, 0.12), a)
            m.gem(YardArtColors.stone, sides: 4, r: 0.05, h: 0.06, at: c + SIMD3(p.x, 0.06, p.z))
        }
        let pot: UInt32 = look == .board ? YardArtColors.iron : look.frame
        m.prism(pot, sides: 8, r: 0.13, h: 0.13, top: 0.15, at: c + SIMD3(0, 0.17, 0))
        m.prism(look.trim, sides: 8, r: 0.158, h: 0.022, at: c + SIMD3(0, 0.24, 0), bottom: false)
        m.gem(YardArtColors.porridge, sides: 8, r: 0.14, h: 0.035, at: c + SIMD3(0, 0.245, 0))
        m.node("fire", at: c + SIMD3(0, 0.075, 0), motion: .pulse(amount: 0.18, period: 0.5, phase: 0))
        m.prism(YardArtColors.flame, sides: 5, r: 0.05, h: 0.09, top: 0, at: .zero, glow: true)
        m.node("spoon", at: c + SIMD3(0, 0.25, 0), motion: .spin(axis: SIMD3(0, 1, 0), rps: 0.4))
        m.box(look.trim == YardArtLook.board.trim ? YardArtLook.board.frame : look.trim, SIMD3(0.014, 0.2, 0.014),
              at: SIMD3(0.07, 0.07, 0), rot: SIMD3(0, 0, -20))
        m.gem(YardArtLook.board.frame, sides: 4, r: 0.026, h: 0.02, at: SIMD3(0.04, -0.015, 0))
        for i in 0..<3 {
            m.node("steam\(i)", at: c + SIMD3(0, 0.29, 0), motion: .keys([
                YardArtKey(t: 0, scale: 0),
                YardArtKey(t: 0.1, scale: 0.5),
                YardArtKey(t: 0.8, offset: SIMD3(0.02, 0.24, 0), scale: 1.4),
                YardArtKey(t: 1, offset: SIMD3(0.03, 0.3, 0), scale: 0),
            ], axis: SIMD3(0, 1, 0), period: 3, phase: Float(i) / 3))
            m.prism(YardArtColors.steam, sides: 6, r: 0.05, h: 0.012, at: .zero)
        }
        return [SIMD3(-0.2, 0.05, 0.15), SIMD3(0.18, 0.05, -0.2), SIMD3(-0.2, 0.05, -0.2),
                SIMD3(c.x, 0.27, c.z - 0.16)]
    }

    // 4. Деревянное колесо: крутится, клубок растёт и скатывается в корзину; расчесали — вдвое быстрее.
    private static func wheel(_ m: inout YardArtModel, _ look: YardArtLook, brushed: Bool) -> [SIMD3<Float>] {
        let speed: Float = brushed ? 2 : 1
        let hub = SIMD3<Float>(-0.06, 0.25, -0.1)
        m.box(look.frame, SIMD3(0.2, 0.03, 0.08), at: SIMD3(hub.x, 0.045, -0.13))
        m.box(look.trim, SIMD3(0.03, 0.24, 0.02), at: SIMD3(hub.x, 0.165, -0.14))
        let spindle = SIMD3<Float>(0.13, 0.17, -0.06)
        m.box(look.trim, SIMD3(0.015, 0.12, 0.015), at: SIMD3(spindle.x, 0.09, spindle.z))
        let basket = SIMD3<Float>(0.0, 0.06, 0.08)
        m.prism(YardArtColors.wicker, sides: 6, r: 0.06, h: 0.06, top: 0.07, at: basket)
        m.node("wheel", at: hub, motion: .spin(axis: SIMD3(0, 0, 1), rps: 0.5 * speed))
        m.prism(look.trim, sides: 6, r: 0.025, h: 0.03, at: .zero, rot: SIMD3(90, 0, 0))
        for a in [Float(0), 60, 120] {
            m.box(look.trim, SIMD3(0.27, 0.012, 0.008), at: .zero, rot: SIMD3(0, 0, a))
        }
        let apothem: Float = 0.14 * 0.866
        for k in 0..<6 {
            let a = Float(k) * 60 + 30
            let p = YardArtMath.rotZ(SIMD3(apothem, 0, 0), a)
            m.box(look.frame, SIMD3(0.025, 0.15, 0.02), at: p, rot: SIMD3(0, 0, a))
        }
        let drop = SIMD3<Float>(0, -0.1, 0.05)
        let inBasket = SIMD3<Float>(basket.x - spindle.x, basket.y + 0.06 - spindle.y, basket.z - spindle.z)
        m.node("ball", at: spindle, motion: .keys([
            YardArtKey(t: 0, scale: 0),
            YardArtKey(t: 0.05, scale: 0.3),
            YardArtKey(t: 0.62, scale: 1),
            YardArtKey(t: 0.72, offset: drop, angle: 180),
            YardArtKey(t: 0.85, offset: inBasket, angle: 400),
            YardArtKey(t: 0.95, offset: inBasket, scale: 0.9, angle: 400),
            YardArtKey(t: 1, offset: inBasket, scale: 0, angle: 400),
        ], axis: SIMD3(1, 0, 0), period: 6 / speed, phase: 0))
        m.gem(YardArtColors.wool, sides: 6, r: 0.04, h: 0.07, at: .zero)
        return [SIMD3(-0.24, 0.05, -0.2), SIMD3(0.24, 0.05, -0.2), SIMD3(-0.24, 0.05, 0.17),
                SIMD3(spindle.x, 0.16, spindle.z)]
    }

    // 5. Глиняная печь с трубой: дверца откидывается, выезжает противень, пирожок прыгает на полку.
    private static func oven(_ m: inout YardArtModel, _ look: YardArtLook) -> [SIMD3<Float>] {
        let c = SIMD3<Float>(-0.05, 0, -0.08)
        m.box(YardArtColors.clay, SIMD3(0.3, 0.1, 0.26), at: c + SIMD3(0, 0.08, 0))
        m.prism(YardArtColors.clay, sides: 8, r: 0.15, h: 0.16, top: 0.07, at: c + SIMD3(0, 0.21, 0))
        m.prism(YardArtColors.chimney, sides: 6, r: 0.025, h: 0.12, at: c + SIMD3(0.07, 0.3, -0.06))
        let front = c.z + 0.13
        m.box(YardArtColors.soot, SIMD3(0.13, 0.075, 0.006), at: SIMD3(c.x, 0.08, front + 0.002))
        m.box(YardArtColors.ember, SIMD3(0.09, 0.03, 0.004), at: SIMD3(c.x, 0.06, front + 0.006), glow: true)
        let shelf = SIMD3<Float>(0.17, 0.2, -0.04)
        m.box(look.frame, SIMD3(0.13, 0.015, 0.08), at: shelf)
        m.box(look.trim, SIMD3(0.015, 0.17, 0.015), at: SIMD3(shelf.x, 0.115, shelf.z))
        m.gem(YardArtColors.pie, sides: 6, r: 0.028, h: 0.026, at: shelf + SIMD3(-0.04, 0.02, 0))
        m.gem(YardArtColors.pie, sides: 6, r: 0.028, h: 0.026, at: shelf + SIMD3(0.04, 0.02, 0))
        // Дверца на петле снизу: откидывается вперёд (rotX+ клонит верх к камере).
        m.node("door", at: SIMD3(c.x, 0.04, front + 0.012), motion: .keys([
            YardArtKey(t: 0), YardArtKey(t: 0.15), YardArtKey(t: 0.28, angle: 100),
            YardArtKey(t: 0.72, angle: 100), YardArtKey(t: 0.86), YardArtKey(t: 1),
        ], axis: SIMD3(1, 0, 0), period: 5, phase: 0))
        m.box(look.trim, SIMD3(0.14, 0.085, 0.012), at: SIMD3(0, 0.0425, 0))
        let inside = SIMD3<Float>(0, 0, -0.08), out = SIMD3<Float>(0, 0, 0.09)
        m.node("pan", at: SIMD3(c.x, 0.07, front - 0.02), motion: .keys([
            YardArtKey(t: 0, offset: inside), YardArtKey(t: 0.3, offset: inside), YardArtKey(t: 0.42, offset: out),
            YardArtKey(t: 0.56, offset: out), YardArtKey(t: 0.68, offset: inside), YardArtKey(t: 1, offset: inside),
        ], axis: SIMD3(0, 1, 0), period: 5, phase: 0))
        m.box(YardArtColors.steel, SIMD3(0.1, 0.008, 0.08), at: .zero)
        let pieStart = SIMD3<Float>(c.x, 0.088, front - 0.02)
        let onShelf = shelf + SIMD3(0, 0.02, 0.005) - pieStart
        m.node("pie", at: pieStart, motion: .keys([
            YardArtKey(t: 0, offset: inside), YardArtKey(t: 0.3, offset: inside), YardArtKey(t: 0.42, offset: out),
            YardArtKey(t: 0.48, offset: out),
            YardArtKey(t: 0.56, offset: SIMD3(onShelf.x * 0.5, onShelf.y + 0.12, (out.z + onShelf.z) * 0.5), angle: 180),
            YardArtKey(t: 0.64, offset: onShelf, angle: 360),
            YardArtKey(t: 0.92, offset: onShelf, angle: 360),
            YardArtKey(t: 0.96, offset: onShelf, scale: 0, angle: 360),
            YardArtKey(t: 0.97, offset: inside, scale: 0),
            YardArtKey(t: 1, offset: inside),
        ], axis: SIMD3(0, 0, 1), period: 5, phase: 0))
        m.gem(YardArtColors.pie, sides: 6, r: 0.03, h: 0.028, at: .zero)
        m.node("smoke", at: c + SIMD3(0.07, 0.37, -0.06), motion: .keys([
            YardArtKey(t: 0, scale: 0), YardArtKey(t: 0.1, scale: 0.6),
            YardArtKey(t: 0.9, offset: SIMD3(0.03, 0.18, 0), scale: 1.5),
            YardArtKey(t: 1, offset: SIMD3(0.035, 0.2, 0), scale: 0),
        ], axis: SIMD3(0, 1, 0), period: 2.5, phase: 0))
        m.gem(YardArtColors.steam, sides: 4, r: 0.03, h: 0.04, at: .zero)
        return [SIMD3(c.x - 0.13, 0.15, front), SIMD3(c.x + 0.13, 0.15, front), SIMD3(c.x, 0.3, c.z + 0.08),
                SIMD3(shelf.x + 0.06, 0.215, shelf.z)]
    }

    // 6. Будка со шторкой и лампой: вспышка, снизу вылезает полоска фото.
    private static func photo(_ m: inout YardArtModel, _ look: YardArtLook) -> [SIMD3<Float>] {
        let c = SIMD3<Float>(-0.06, 0, -0.1)
        m.box(YardArtColors.booth, SIMD3(0.24, 0.36, 0.2), at: c + SIMD3(0, 0.21, 0))
        m.box(look.frame, SIMD3(0.245, 0.03, 0.205), at: c + SIMD3(0, 0.33, 0))
        m.box(YardArtColors.roof, SIMD3(0.28, 0.03, 0.24), at: c + SIMD3(0, 0.405, 0))
        let front = c.z + 0.1
        m.prism(YardArtColors.lens, sides: 6, r: 0.025, h: 0.03, at: SIMD3(c.x + 0.06, 0.26, front + 0.012),
                rot: SIMD3(90, 0, 0))
        m.box(YardArtColors.soot, SIMD3(0.07, 0.012, 0.01), at: SIMD3(c.x + 0.06, 0.11, front + 0.002))
        let lamp = SIMD3<Float>(c.x + 0.06, 0.5, c.z + 0.02)
        m.box(look.trim, SIMD3(0.012, 0.08, 0.012), at: lamp - SIMD3(0, 0.05, 0))
        m.gem(YardArtColors.lamp, sides: 6, r: 0.03, h: 0.04, at: lamp, glow: true)
        m.node("curtain", at: SIMD3(c.x - 0.055, 0.37, front + 0.006),
               motion: .swing(axis: SIMD3(1, 0, 0), deg: 6, period: 2.6, phase: 0))
        m.box(YardArtColors.curtain, SIMD3(0.1, 0.26, 0.01), at: SIMD3(0, -0.13, 0))
        m.node("flash", at: lamp, motion: .keys([
            YardArtKey(t: 0, scale: 0), YardArtKey(t: 0.36, scale: 0), YardArtKey(t: 0.4, scale: 1.8),
            YardArtKey(t: 0.47, scale: 0), YardArtKey(t: 1, scale: 0),
        ], axis: SIMD3(0, 1, 0), period: 4, phase: 0))
        m.gem(YardArtColors.flash, sides: 4, r: 0.05, h: 0.07, at: .zero, glow: true)
        // Полоска фото растёт вниз из щели (масштаб к точке щели) и пропадает.
        m.node("strip", at: SIMD3(c.x + 0.06, 0.105, front + 0.008), motion: .keys([
            YardArtKey(t: 0, scale: 0), YardArtKey(t: 0.46, scale: 0), YardArtKey(t: 0.5, scale: 0.15),
            YardArtKey(t: 0.75, scale: 1), YardArtKey(t: 0.92, scale: 1), YardArtKey(t: 0.97, scale: 0),
            YardArtKey(t: 1, scale: 0),
        ], axis: SIMD3(0, 1, 0), period: 4, phase: 0))
        m.box(YardArtColors.paper, SIMD3(0.05, 0.1, 0.004), at: SIMD3(0, -0.05, 0))
        return [SIMD3(c.x - 0.14, 0.42, front + 0.02), SIMD3(c.x + 0.14, 0.42, front + 0.02),
                SIMD3(c.x - 0.14, 0.42, c.z - 0.12), SIMD3(c.x + 0.14, 0.42, c.z - 0.12)]
    }

    // 7. Лента с роликами и рычагом: сосиски едут и падают в ящик, рычаг «чух».
    private static func conveyor(_ m: inout YardArtModel, _ look: YardArtLook) -> [SIMD3<Float>] {
        let z: Float = -0.08, beltY: Float = 0.16
        m.box(look.trim, SIMD3(0.03, 0.12, 0.13), at: SIMD3(-0.14, 0.09, z))
        m.box(look.trim, SIMD3(0.03, 0.12, 0.13), at: SIMD3(0.1, 0.09, z))
        m.box(YardArtColors.belt, SIMD3(0.32, 0.02, 0.12), at: SIMD3(-0.02, beltY, z))
        let machine = SIMD3<Float>(-0.2, 0.23, z)
        m.box(look.frame, SIMD3(0.1, 0.14, 0.14), at: machine)
        let crate = SIMD3<Float>(0.2, 0.07, z)
        m.box(look.frame, SIMD3(0.09, 0.08, 0.12), at: crate)
        m.box(look.trim, SIMD3(0.075, 0.006, 0.1), at: SIMD3(crate.x, 0.11, crate.z))
        for (i, x) in [Float(-0.14), -0.02, 0.1].enumerated() {
            m.node("roller\(i)", at: SIMD3(x, beltY - 0.012, z), motion: .spin(axis: SIMD3(0, 0, 1), rps: -1.2))
            m.prism(YardArtColors.steel, sides: 5, r: 0.014, h: 0.14, at: .zero, rot: SIMD3(90, 0, 0))
        }
        let start = SIMD3<Float>(-0.14, beltY + 0.026, z)
        let end = SIMD3<Float>(0.24, 0, 0), fall = SIMD3<Float>(crate.x - start.x, 0.125 - start.y, 0)
        for i in 0..<3 {
            m.node("sausage\(i)", at: start, motion: .keys([
                YardArtKey(t: 0, scale: 0), YardArtKey(t: 0.06),
                YardArtKey(t: 0.7, offset: end),
                YardArtKey(t: 0.8, offset: fall, angle: -60),
                YardArtKey(t: 0.92, offset: fall, angle: -60),
                YardArtKey(t: 0.97, offset: fall, scale: 0, angle: -60),
                YardArtKey(t: 1, offset: fall, scale: 0),
            ], axis: SIMD3(0, 0, 1), period: 3, phase: Float(i) / 3))
            m.prism(YardArtColors.sausage, sides: 5, r: 0.016, h: 0.07, at: .zero, rot: SIMD3(0, 0, 90))
        }
        // Рычаг на боку машины: «чух» на каждую сосиску (период — треть цикла ленты).
        m.node("lever", at: SIMD3(machine.x, 0.25, z + 0.075), motion: .keys([
            YardArtKey(t: 0), YardArtKey(t: 0.1, angle: -40), YardArtKey(t: 0.3), YardArtKey(t: 1),
        ], axis: SIMD3(0, 0, 1), period: 1, phase: 0))
        m.box(look.trim, SIMD3(0.012, 0.08, 0.012), at: SIMD3(0, 0.04, 0))
        m.gem(YardArtColors.knob, sides: 4, r: 0.018, h: 0.026, at: SIMD3(0, 0.085, 0))
        return [SIMD3(machine.x - 0.04, 0.31, z + 0.06), SIMD3(machine.x + 0.04, 0.31, z - 0.06),
                SIMD3(crate.x - 0.035, 0.12, z + 0.055), SIMD3(crate.x + 0.035, 0.12, z + 0.055)]
    }

    // 8. Мельница с крыльями-ложками: днём медленно, ночью быстрее и сыплет светящуюся «звёздную муку».
    private static func mill(_ m: inout YardArtModel, _ look: YardArtLook, night: Bool) -> [SIMD3<Float>] {
        let c = SIMD3<Float>(-0.04, 0, -0.1)
        m.prism(YardArtColors.tower, sides: 6, r: 0.11, h: 0.3, top: 0.075, at: c + SIMD3(0, 0.18, 0))
        m.prism(YardArtColors.roof, sides: 6, r: 0.09, h: 0.1, top: 0, at: c + SIMD3(0, 0.38, 0))
        m.box(YardArtColors.door, SIMD3(0.05, 0.08, 0.01), at: SIMD3(c.x, 0.07, c.z + 0.095), rot: SIMD3(-8, 0, 0))
        m.gem(YardArtColors.moon, sides: 4, r: 0.026, h: 0.03, at: SIMD3(c.x, 0.2, c.z + 0.085), rot: SIMD3(90, 0, 0),
              glow: true)
        let sack = SIMD3<Float>(0.12, 0.075, 0.02)
        m.gem(YardArtColors.sack, sides: 6, r: 0.05, h: 0.09, at: sack)
        let hub = SIMD3<Float>(c.x, 0.32, c.z + 0.1)
        m.node("sails", at: hub, motion: .spin(axis: SIMD3(0, 0, 1), rps: night ? 0.35 : 0.1))
        m.gem(look.trim, sides: 6, r: 0.025, h: 0.03, at: .zero, rot: SIMD3(90, 0, 0))
        for k in 0..<4 {
            let a = Float(k) * 90
            m.box(look.frame, SIMD3(0.012, 0.15, 0.008), at: YardArtMath.rotZ(SIMD3(0, 0.09, 0), a), rot: SIMD3(0, 0, a))
            m.gem(look.frame, sides: 6, r: 0.032, h: 0.016, at: YardArtMath.rotZ(SIMD3(0, 0.18, 0), a),
                  rot: SIMD3(90, 0, a))
        }
        let into = SIMD3<Float>(sack.x - hub.x, sack.y + 0.05 - hub.y, sack.z - hub.z)
        for i in 0..<3 {
            let dx = Float(i - 1) * 0.02
            m.node("flour\(i)", at: hub + SIMD3(dx, -0.03, 0.01), motion: .keys([
                YardArtKey(t: 0, scale: 0), YardArtKey(t: 0.1),
                YardArtKey(t: 0.8, offset: into - SIMD3(dx, 0, 0)),
                YardArtKey(t: 0.9, offset: into - SIMD3(dx, 0, 0), scale: 0),
                YardArtKey(t: 1, scale: 0),
            ], axis: SIMD3(0, 1, 0), period: night ? 2 : 4, phase: Float(i) / 3))
            m.gem(YardArtColors.flour, sides: 4, r: 0.013, h: 0.018, at: .zero, glow: night)
        }
        return [SIMD3(c.x - 0.07, 0.34, c.z + 0.06), SIMD3(c.x + 0.07, 0.34, c.z + 0.06),
                SIMD3(sack.x - 0.03, 0.13, sack.z + 0.03), SIMD3(c.x, 0.44, c.z)]
    }

    /// Самая тяжёлая станция по всем видам, заполнениям, флагам и районам — для проверки бюджета.
    static func worstTriangles() -> (station: YardArtStation, level: Int, triangles: Int) {
        var worst = (station: YardArtStation.dryer, level: 1, triangles: 0)
        for s in YardArtStation.allCases {
            for level in 1...5 {
                for night in [false, true] {
                    for d in YardDistrict.allCases {
                        let t = station(s, level: level, fill: 1, night: night, brushed: night, district: d).triangles
                        if t > worst.triangles { worst = (s, level, t) }
                    }
                }
            }
        }
        return worst
    }
}

// MARK: - Ярусы

/// Станция на подложке: какая, где, с какой плиты яруса появляется и масштаб (на подоконнике — меньше).
struct YardArtSlot: Sendable {
    var station: YardArtStation
    var at: SIMD3<Float>
    var plate: Int
    var scale: Float = 1
}

/// Пять ярусов двора (§1): подложка растёт слоями. Вид «ярус N» показывает слои 0…N; в ярусе N куплено
/// progress плит по порядку §1, ниже — все. Стартовый вид (§1): за окном пустырь — грязь, лужа, кривой забор, мешок.
enum YardArtTier {
    static let names = ["Подоконник", "Дворик", "Сад", "Парк", "Квартал"]

    static let plates: [[String]] = [
        ["Протереть окно", "Горшок с ромашкой", "Сушилка"],
        ["Убрать мусор", "Починить забор", "Тропинка из плитки", "Фонарь", "Грядка", "Котелок"],
        ["Почтовый ящик", "Яблоня", "Скамейка", "Пруд с лягушкой", "Прялка", "Печь"],
        ["Табличка с именем", "Гирлянда", "Флюгер-кость", "Фонтан-миска", "Фотобудка"],
        ["Вывеска «‹Имя› и Ко»", "Телескоп", "Конвейер", "Мельница"],
    ]

    static let slots: [[YardArtSlot]] = [
        [YardArtSlot(station: .dryer, at: SIMD3(0.12, 0.5, -1.56), plate: 2, scale: 0.6)],
        [YardArtSlot(station: .bonePatch, at: SIMD3(-0.62, 0, -0.95), plate: 4),
         YardArtSlot(station: .porridge, at: SIMD3(0.62, 0, -0.95), plate: 5)],
        [YardArtSlot(station: .wheel, at: SIMD3(-0.6, 0, 0.45), plate: 4),
         YardArtSlot(station: .oven, at: SIMD3(0.6, 0, 0.45), plate: 5)],
        [YardArtSlot(station: .photo, at: SIMD3(-1.7, 0, -0.6), plate: 4)],
        [YardArtSlot(station: .conveyor, at: SIMD3(1.7, 0, -0.75), plate: 2),
         YardArtSlot(station: .mill, at: SIMD3(1.7, 0, 0.35), plate: 3)],
    ]

    /// Сколько плит куплено в ярусе n при виде «ярус shown, progress в нём».
    static func bought(_ n: Int, shown: Int, progress: Int) -> Int {
        n < shown ? plates[n].count : n == shown ? max(0, min(plates[n].count, progress)) : 0
    }

    /// Подложка слоя n при bought купленных плитах (станции — отдельно, по slots).
    /// Слой 1 нужен и для яруса 0: пустырь за окном.
    /// district (волна 36 Q) меняет только цвета земли, плит, забора и дома; декор района — `decor(...)`.
    static func layer(_ n: Int, bought b: Int, district: YardDistrict = .street) -> YardArtModel {
        var m = YardArtModel(name: "tier\(n)")
        let c = district.palette
        switch n {
        case 0: sill(&m, b, c)
        case 1: yard(&m, b, c)
        case 2: garden(&m, b, c)
        case 3: park(&m, b, c)
        default: block(&m, b, c)
        }
        return m
    }

    // Слой 0: стена дома, окно, подоконник.
    private static func sill(_ m: inout YardArtModel, _ b: Int, _ c: YardDistrictPalette) {
        let wz: Float = -1.8
        m.box(c.wall, SIMD3(2.5, 1.4, 0.12), at: SIMD3(0, 0.7, wz))
        m.box(c.houseRoof, SIMD3(2.6, 0.1, 0.3), at: SIMD3(0, 1.43, wz + 0.05))
        let w = SIMD3<Float>(0, 0.82, wz + 0.065)
        m.box(b >= 1 ? YardArtColors.glass : YardArtColors.glassDirty, SIMD3(0.7, 0.56, 0.01), at: w)
        m.box(YardArtColors.windowFrame, SIMD3(0.78, 0.05, 0.04), at: w + SIMD3(0, 0.3, 0.01))
        m.box(YardArtColors.windowFrame, SIMD3(0.78, 0.05, 0.04), at: w + SIMD3(0, -0.3, 0.01))
        m.box(YardArtColors.windowFrame, SIMD3(0.05, 0.56, 0.04), at: w + SIMD3(-0.37, 0, 0.01))
        m.box(YardArtColors.windowFrame, SIMD3(0.05, 0.56, 0.04), at: w + SIMD3(0.37, 0, 0.01))
        m.box(YardArtColors.windowFrame, SIMD3(0.03, 0.56, 0.02), at: w + SIMD3(0, 0, 0.01))
        // Подоконник: на нём горшок и сушилка (станция 1, масштаб 0.6).
        m.box(YardArtColors.windowFrame, SIMD3(0.95, 0.04, 0.34), at: SIMD3(0, 0.48, wz + 0.22))
        if b >= 2 {
            let pot = SIMD3<Float>(-0.33, 0.55, wz + 0.24)
            m.prism(YardArtColors.roof, sides: 6, r: 0.05, h: 0.09, top: 0.065, at: pot)
            m.box(YardArtColors.leaf, SIMD3(0.012, 0.12, 0.012), at: pot + SIMD3(0, 0.1, 0))
            m.gem(YardArtColors.flowerWhite, sides: 6, r: 0.05, h: 0.02, at: pot + SIMD3(0, 0.17, 0.005),
                  rot: SIMD3(70, 0, 0))
            m.gem(YardArtColors.flowerYellow, sides: 4, r: 0.02, h: 0.02, at: pot + SIMD3(0, 0.172, 0.018),
                  rot: SIMD3(70, 0, 0))
        }
    }

    // Слой 1: дворик перед домом — пока ничего не куплено, это пустырь.
    private static func yard(_ m: inout YardArtModel, _ b: Int, _ c: YardDistrictPalette) {
        m.box(c.ground, SIMD3(2.4, 0.04, 1.7), at: SIMD3(0, -0.02, -0.85))
        if b < 1 {
            m.prism(c.puddle, sides: 8, r: 0.22, h: 0.01, at: SIMD3(0.5, 0.004, -0.4), scale: SIMD3(1.5, 1, 1))
            m.gem(YardArtColors.trash, sides: 6, r: 0.15, h: 0.24, at: SIMD3(-0.55, 0.11, -0.35))
            m.gem(YardArtColors.trash, sides: 4, r: 0.03, h: 0.06, at: SIMD3(-0.55, 0.24, -0.35))
            m.box(YardArtColors.litter, SIMD3(0.1, 0.03, 0.07), at: SIMD3(-0.25, 0.015, -0.6), rot: SIMD3(0, 30, 0))
            m.box(YardArtColors.litter, SIMD3(0.06, 0.04, 0.06), at: SIMD3(0.15, 0.02, -1.1), rot: SIMD3(0, 50, 12))
        }
        // Забор вдоль передней кромки с калиткой посередине: до «Починить забор» — серый и кривой, одной перекладины нет.
        let fixed = b >= 2
        let color = fixed ? c.fence : c.fenceOld
        for side in [Float(-1), 1] {
            for (i, x) in [Float(0.3), 0.6, 0.9, 1.15].enumerated() {
                let tilt: Float = fixed ? 0 : (i % 2 == 0 ? 10 : -8) * side
                m.box(color, SIMD3(0.05, 0.32, 0.04), at: SIMD3(x * side, 0.16, 0), rot: SIMD3(0, 0, tilt))
            }
            m.box(color, SIMD3(0.9, 0.04, 0.025), at: SIMD3(0.73 * side, 0.22, 0.025),
                  rot: SIMD3(0, 0, fixed ? 0 : 4 * side))
            if fixed || side > 0 {
                m.box(color, SIMD3(0.9, 0.04, 0.025), at: SIMD3(0.73 * side, 0.1, 0.025),
                      rot: SIMD3(0, 0, fixed ? 0 : -3 * side))
            }
        }
        if b >= 3 {
            for (i, z) in [Float(-0.2), -0.5, -0.8, -1.1, -1.4].enumerated() {
                m.box(c.tile, SIMD3(0.26, 0.02, 0.22), at: SIMD3(i % 2 == 0 ? -0.03 : 0.03, 0.01, z))
            }
        }
        if b >= 4 {
            let lamp = SIMD3<Float>(0.3, 0, -0.18)
            m.prism(YardArtColors.pole, sides: 6, r: 0.025, h: 0.9, at: lamp + SIMD3(0, 0.45, 0))
            m.box(YardArtColors.pole, SIMD3(0.12, 0.03, 0.12), at: lamp + SIMD3(0, 0.92, 0))
            m.gem(YardArtColors.lamp, sides: 6, r: 0.06, h: 0.1, at: lamp + SIMD3(0, 0.86, 0), glow: true)
        }
    }

    // Слой 2: сад перед забором.
    private static func garden(_ m: inout YardArtModel, _ b: Int, _ c: YardDistrictPalette) {
        m.box(c.garden, SIMD3(2.4, 0.04, 1.0), at: SIMD3(0, -0.02, 0.5))
        if b >= 1 {
            let p = SIMD3<Float>(1.0, 0, 0.15)
            m.box(YardArtColors.trunk, SIMD3(0.03, 0.36, 0.03), at: p + SIMD3(0, 0.18, 0))
            m.box(YardArtColors.mailbox, SIMD3(0.16, 0.1, 0.1), at: p + SIMD3(0, 0.4, 0))
            m.box(YardArtColors.knob, SIMD3(0.01, 0.06, 0.02), at: p + SIMD3(0.085, 0.44, 0))
        }
        if b >= 2 {
            let p = SIMD3<Float>(-1.0, 0, 0.75)
            m.prism(YardArtColors.trunk, sides: 6, r: 0.05, h: 0.5, top: 0.035, at: p + SIMD3(0, 0.25, 0))
            m.gem(c.crown, sides: 7, r: 0.3, h: 0.5, at: p + SIMD3(0, 0.68, 0))
            for (i, a) in [Float(20), 140, 260].enumerated() {
                let q = YardArtMath.rotY(SIMD3(0, 0, 0.26), a)
                m.gem(YardArtColors.apple, sides: 4, r: 0.035, h: 0.05, at: p + SIMD3(q.x, 0.62 + Float(i) * 0.05, q.z))
            }
        }
        if b >= 3 {
            let p = SIMD3<Float>(0, 0, 0.85)
            m.box(YardArtColors.bench, SIMD3(0.5, 0.03, 0.14), at: p + SIMD3(0, 0.16, 0))
            m.box(YardArtColors.bench, SIMD3(0.5, 0.12, 0.03), at: p + SIMD3(0, 0.25, -0.07), rot: SIMD3(-10, 0, 0))
            m.box(YardArtColors.trunk, SIMD3(0.04, 0.15, 0.12), at: p + SIMD3(-0.21, 0.075, 0))
            m.box(YardArtColors.trunk, SIMD3(0.04, 0.15, 0.12), at: p + SIMD3(0.21, 0.075, 0))
        }
        if b >= 4 {
            let p = SIMD3<Float>(0.98, 0, 0.75)
            m.prism(c.water, sides: 8, r: 0.18, h: 0.012, at: p + SIMD3(0, 0.006, 0), scale: SIMD3(1.2, 1, 1))
            m.node("frog", at: p + SIMD3(-0.05, 0.035, 0.03), motion: .bob(height: 0.03, period: 2.2, phase: 0))
            m.gem(YardArtColors.frog, sides: 5, r: 0.045, h: 0.05, at: .zero)
            m.gem(YardArtColors.frog, sides: 4, r: 0.014, h: 0.02, at: SIMD3(-0.02, 0.028, 0.02))
            m.gem(YardArtColors.frog, sides: 4, r: 0.014, h: 0.02, at: SIMD3(0.02, 0.028, 0.02))
            m.body()
        }
    }

    // Слой 3: парк слева от дома.
    private static func park(_ m: inout YardArtModel, _ b: Int, _ c: YardDistrictPalette) {
        m.box(c.park, SIMD3(1.0, 0.04, 2.7), at: SIMD3(-1.7, -0.02, -0.35))
        if b >= 1 {
            let p = SIMD3<Float>(-1.3, 0, 0.85)
            m.box(YardArtColors.trunk, SIMD3(0.03, 0.3, 0.03), at: p + SIMD3(0, 0.15, 0))
            m.box(YardArtColors.sign, SIMD3(0.26, 0.1, 0.02), at: p + SIMD3(0, 0.32, 0.01))
        }
        if b >= 2 {
            let l = SIMD3<Float>(-2.1, 0, -1.45), r = SIMD3<Float>(-1.3, 0, -1.45)
            m.box(YardArtColors.pole, SIMD3(0.03, 0.8, 0.03), at: l + SIMD3(0, 0.4, 0))
            m.box(YardArtColors.pole, SIMD3(0.03, 0.8, 0.03), at: r + SIMD3(0, 0.4, 0))
            m.box(YardArtColors.rope, SIMD3(0.8, 0.008, 0.008), at: (l + r) / 2 + SIMD3(0, 0.76, 0))
            let colors = [YardArtColors.lamp, YardArtColors.knob, YardArtColors.water, YardArtColors.flowerYellow, YardArtColors.frog]
            for k in 0..<7 {
                let t = Float(k + 1) / 8
                let x = l.x + (r.x - l.x) * t
                m.gem(colors[k % colors.count], sides: 4, r: 0.02, h: 0.035, at: SIMD3(x, 0.72, l.z + 0.01), glow: true)
            }
        }
        if b >= 3 {
            let p = SIMD3<Float>(-2.05, 0, 0.55)
            m.box(YardArtColors.pole, SIMD3(0.025, 0.7, 0.025), at: p + SIMD3(0, 0.35, 0))
            m.node("vane", at: p + SIMD3(0, 0.72, 0), motion: .spin(axis: SIMD3(0, 1, 0), rps: 0.2))
            YardArt.boneShape(&m, at: SIMD3(0, 0.02, 0), scale: 2.2)
            m.body()
        }
        if b >= 4 {
            let p = SIMD3<Float>(-1.6, 0, 0.45)
            m.prism(YardArtColors.pole, sides: 6, r: 0.04, h: 0.2, at: p + SIMD3(0, 0.1, 0))
            m.prism(YardArtColors.mailbox, sides: 8, r: 0.12, h: 0.06, top: 0.2, at: p + SIMD3(0, 0.23, 0))
            m.node("fountain", at: p + SIMD3(0, 0.27, 0), motion: .bob(height: 0.06, period: 1.4, phase: 0))
            m.gem(YardArtColors.water, sides: 6, r: 0.06, h: 0.12, at: .zero)
            m.body()
        }
    }

    // Слой 4: квартал справа от дома.
    private static func block(_ m: inout YardArtModel, _ b: Int, _ c: YardDistrictPalette) {
        m.box(c.paving, SIMD3(1.0, 0.04, 2.7), at: SIMD3(1.7, -0.02, -0.35))
        if b >= 1 {
            let p = SIMD3<Float>(1.7, 0, -1.5)
            m.box(YardArtColors.pole, SIMD3(0.04, 0.9, 0.04), at: p + SIMD3(-0.38, 0.45, 0))
            m.box(YardArtColors.pole, SIMD3(0.04, 0.9, 0.04), at: p + SIMD3(0.38, 0.45, 0))
            m.box(YardArtColors.sign, SIMD3(0.86, 0.26, 0.04), at: p + SIMD3(0, 0.78, 0.02))
            for k in 0..<5 {
                m.gem(YardArtColors.lamp, sides: 4, r: 0.018, h: 0.03, at: p + SIMD3(-0.34 + Float(k) * 0.17, 0.93, 0.04),
                      glow: true)
            }
        }
        if b >= 2 {
            let p = SIMD3<Float>(2.05, 0, 0.9)
            for a in [Float(0), 120, 240] {
                let q = YardArtMath.rotY(SIMD3(0, 0, 0.07), a)
                m.box(YardArtColors.pole, SIMD3(0.015, 0.36, 0.015), at: p + SIMD3(q.x, 0.17, q.z),
                      rot: SIMD3(q.z > 0 ? 10 : -10, 0, q.x > 0 ? -10 : 10))
            }
            m.prism(YardArtColors.mailbox, sides: 6, r: 0.035, h: 0.3, top: 0.05, at: p + SIMD3(0, 0.4, 0),
                    rot: SIMD3(-60, 30, 0))
        }
    }
}
