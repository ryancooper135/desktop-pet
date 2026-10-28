// Волна 41 G: интерьер комнаты пса — обои (стены), пол и ковёр на выбор.
// Чистая косметика: на доход, потолки и экономику не влияет. Первый вариант каждой части бесплатный и стоит по
// умолчанию (это прежняя комната), остальные — за монеты, два эксклюзива — за клочки ✂️ (как сезонные вещи).
// Цены — economy.json → interior, умолчания — InteriorConfig; узоры — плоские цвета геометрией (InteriorArt),
// без картинок-текстур: сцена (App/InteriorDecor.swift) только собирает из них сущности.

import Foundation
@preconcurrency import PetCore

/// Что в комнате можно сменить.
enum InteriorPart: String, CaseIterable, Codable, Hashable, Sendable {
    case walls, floor, rug
}

/// Чем платят за вариант.
enum InteriorCurrency: Hashable, Sendable {
    case free, coins, shards
}

/// Обои: фон и простой узор поверх (полоски, панель, ромбики, звёзды).
enum WallLook: Hashable, Sendable {
    case plain(UInt32)
    case stripes(UInt32, stripe: UInt32)
    case panel(UInt32, lower: UInt32, rail: UInt32)
    case diamonds(UInt32, dot: UInt32)
    case stars(UInt32, star: UInt32, dot: UInt32)

    /// Фон стены — цвет самой плоскости.
    var base: UInt32 {
        switch self {
        case .plain(let b), .stripes(let b, _), .panel(let b, _, _), .diamonds(let b, _), .stars(let b, _, _): return b
        }
    }

    /// Все цвета, фон первым: образец в листе и проверка яркости под статус-баром.
    var colors: [UInt32] {
        switch self {
        case .plain(let b): return [b]
        case .stripes(let b, let s): return [b, s]
        case .panel(let b, let l, let r): return [b, l, r]
        case .diamonds(let b, let d): return [b, d]
        case .stars(let b, let s, let d): return [b, s, d]
        }
    }
}

/// Пол: узор рисуется в текстуру по пикселям (InteriorArt.floorPixels).
enum FloorLook: Hashable, Sendable {
    case checker(UInt32, UInt32)
    case planks(UInt32, UInt32, seam: UInt32)
    case zigzag(UInt32, UInt32)

    var colors: [UInt32] {
        switch self {
        case .checker(let a, let b), .zigzag(let a, let b): return [a, b]
        case .planks(let a, let b, let s): return [a, b, s]
        }
    }
}

/// Ковёр под собакой: круг, кольца, овал или квадрат с каймой, полосатый.
enum RugLook: Hashable, Sendable {
    case round(UInt32)
    case rings([UInt32])                 // снаружи внутрь
    case oval(UInt32, border: UInt32)
    case square(UInt32, border: UInt32)
    case stripes([UInt32])               // поперёк, слева направо

    var colors: [UInt32] {
        switch self {
        case .round(let c): return [c]
        case .rings(let cs), .stripes(let cs): return cs
        case .oval(let c, let b), .square(let c, let b): return [b, c]
        }
    }
}

enum InteriorLook: Hashable, Sendable {
    case walls(WallLook)
    case floor(FloorLook)
    case rug(RugLook)

    var colors: [UInt32] {
        switch self {
        case .walls(let w): return w.colors
        case .floor(let f): return f.colors
        case .rug(let r): return r.colors
        }
    }
}

/// Вариант интерьера. id не переименовывать: они в сейвах и в economy.json.
struct InteriorStyle: Hashable, Sendable, Identifiable {
    let id: String
    let part: InteriorPart
    let name: String
    let currency: InteriorCurrency
    let look: InteriorLook

    var isFree: Bool { currency == .free }
    /// Эксклюзив за клочки.
    var isExclusive: Bool { currency == .shards }
}

/// Что выбрано и что куплено. Пустое в файл не пишется (SaveFile), новому щенку переходит (PetStore.startOver).
struct InteriorState: Codable, Hashable, Sendable {
    /// Купленные варианты (бесплатные сюда не пишутся — они есть у всех).
    var owned: [String] = []
    /// Выбранное по частям; nil — вариант по умолчанию.
    var walls: String?
    var floor: String?
    var rug: String?

    init() {}

    var isEmpty: Bool { owned.isEmpty && walls == nil && floor == nil && rug == nil }

    subscript(part: InteriorPart) -> String? {
        get {
            switch part {
            case .walls: return walls
            case .floor: return floor
            case .rug: return rug
            }
        }
        set {
            switch part {
            case .walls: walls = newValue
            case .floor: floor = newValue
            case .rug: rug = newValue
            }
        }
    }

    enum CodingKeys: String, CodingKey { case owned, walls, floor, rug }

    /// Терпимо к мусору: битое поле — как будто его нет, а не весь сейв.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        owned = (try? c.decodeIfPresent([String].self, forKey: .owned)) ?? []
        walls = try? c.decodeIfPresent(String.self, forKey: .walls)
        floor = try? c.decodeIfPresent(String.self, forKey: .floor)
        rug = try? c.decodeIfPresent(String.self, forKey: .rug)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !owned.isEmpty { try c.encode(owned, forKey: .owned) }
        try c.encodeIfPresent(walls, forKey: .walls)
        try c.encodeIfPresent(floor, forKey: .floor)
        try c.encodeIfPresent(rug, forKey: .rug)
    }
}

/// Что показывать в комнате: id по частям (всегда валидные — Interior.shown). Для сцены и AppModel.
struct InteriorShown: Hashable, Sendable {
    var walls: String
    var floor: String
    var rug: String

    static let standard = InteriorShown(walls: Interior.standard(.walls).id, floor: Interior.standard(.floor).id,
                                        rug: Interior.standard(.rug).id)

    subscript(part: InteriorPart) -> String {
        switch part {
        case .walls: return walls
        case .floor: return floor
        case .rug: return rug
        }
    }
}

enum InteriorRefusal: Error, Hashable, Sendable {
    case notEnoughCoins(need: Int)
    case notEnoughShards(need: Int)
    case owned          // уже куплено
    case notOwned       // выбрать можно только своё
    case unknown        // такого варианта нет
}

/// Цены. Умолчания — здесь, файл (economy.json → interior) их переопределяет; тест сверяет одно с другим.
/// Монеты — уровня игрушек лавки (30–600): обои и пол — чуть дороже ковра, их видно на весь экран.
/// Клочки — между сезонной вещью на полку (70) и эксклюзивом места (120).
struct InteriorConfig: Hashable, Sendable {
    var coins: [String: Int] = [
        "wall_stripes": 300, "wall_mint": 450, "wall_diamonds": 600,
        "floor_mint": 300, "floor_planks": 450, "floor_zigzag": 600,
        "rug_rings": 200, "rug_oval": 250, "rug_square": 300,
    ]
    var shards: [String: Int] = ["wall_stars": 120, "rug_stripes": 90]

    static let shared = InteriorConfig(json: Catalog.economy() ?? .null)

    init() {}

    init(json e: JSONValue) {
        let s = e["interior"]
        for st in Interior.all {
            switch st.currency {
            case .free: continue
            case .coins:
                if let v = s["coins"][st.id].double { coins[st.id] = max(1, Int(v)) }
            case .shards:
                if let v = s["shards"][st.id].double { shards[st.id] = max(1, Int(v)) }
            }
        }
    }

    /// Цена варианта в его валюте; бесплатный и неизвестный — 0.
    func price(_ st: InteriorStyle) -> Int {
        switch st.currency {
        case .free: return 0
        case .coins: return coins[st.id] ?? 1
        case .shards: return shards[st.id] ?? 1
        }
    }
}

/// Строка листа «Интерьер» для экрана.
struct InteriorOffer: Hashable, Sendable, Identifiable {
    enum State: Hashable, Sendable {
        case chosen             // стоит в комнате
        case owned              // своё, можно поставить
        case buy(need: Int)     // купить; need > 0 — не хватает
    }

    let style: InteriorStyle
    let price: Int
    let state: State

    var id: String { style.id }
}

enum Interior {
    // MARK: каталог

    /// Все варианты: первый в каждой части — бесплатный и по умолчанию (прежняя комната, цвета RoomColors).
    static let all: [InteriorStyle] = [
        InteriorStyle(id: "wall_cream", part: .walls, name: "Сливочные", currency: .free,
                      look: .walls(.plain(0xfbefe4))),
        InteriorStyle(id: "wall_stripes", part: .walls, name: "Персиковая полоска", currency: .coins,
                      look: .walls(.stripes(0xfbefe4, stripe: 0xf3d9c6))),
        InteriorStyle(id: "wall_mint", part: .walls, name: "Мятная панель", currency: .coins,
                      look: .walls(.panel(0xeef6ef, lower: 0xb4d8c2, rail: 0xf8f5ee))),
        InteriorStyle(id: "wall_diamonds", part: .walls, name: "Голубые ромбики", currency: .coins,
                      look: .walls(.diamonds(0xf0f4fa, dot: 0xc8d8ef))),
        InteriorStyle(id: "wall_stars", part: .walls, name: "Звёздные", currency: .shards,
                      look: .walls(.stars(0xf5effa, star: 0xf0d27e, dot: 0xd8c4ee))),

        InteriorStyle(id: "floor_checker", part: .floor, name: "Голубая клетка", currency: .free,
                      look: .floor(.checker(0xbcd3ee, 0xf4f1ea))),
        InteriorStyle(id: "floor_mint", part: .floor, name: "Мятная клетка", currency: .coins,
                      look: .floor(.checker(0xbfe2cf, 0xf4f1ea))),
        InteriorStyle(id: "floor_planks", part: .floor, name: "Доски", currency: .coins,
                      look: .floor(.planks(0xe2c39c, 0xd8b58c, seam: 0xb99470))),
        InteriorStyle(id: "floor_zigzag", part: .floor, name: "Ёлочка", currency: .coins,
                      look: .floor(.zigzag(0xead2b0, 0xd6b28a))),

        InteriorStyle(id: "rug_round", part: .rug, name: "Круглый", currency: .free,
                      look: .rug(.round(0xe9b8a8))),
        InteriorStyle(id: "rug_rings", part: .rug, name: "Мишень", currency: .coins,
                      look: .rug(.rings([0xe9b8a8, 0xf6e3c8, 0xd98f7e]))),
        InteriorStyle(id: "rug_oval", part: .rug, name: "Овальный", currency: .coins,
                      look: .rug(.oval(0xc9dcef, border: 0x8fb0d6))),
        InteriorStyle(id: "rug_square", part: .rug, name: "С каймой", currency: .coins,
                      look: .rug(.square(0xf3e6c9, border: 0xc98f6b))),
        InteriorStyle(id: "rug_stripes", part: .rug, name: "Радуга", currency: .shards,
                      look: .rug(.stripes([0xe9a0a0, 0xf2c38f, 0xf2e19a, 0xb6dcae, 0xa9c8ea, 0xc8b4e6]))),
    ]

    private static let byId: [String: InteriorStyle] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func style(_ id: String) -> InteriorStyle? { byId[id] }

    static func styles(_ part: InteriorPart) -> [InteriorStyle] { all.filter { $0.part == part } }

    /// Вариант по умолчанию — первый в части (бесплатный).
    static func standard(_ part: InteriorPart) -> InteriorStyle {
        all.first { $0.part == part }!
    }

    // MARK: что есть и что стоит

    /// Своё: бесплатное или купленное.
    static func owns(_ f: SaveFile, _ id: String) -> Bool {
        guard let st = style(id) else { return false }
        return st.isFree || f.interior.owned.contains(id)
    }

    /// Что стоит в части: выбранное, если оно своё и этой части, иначе по умолчанию.
    static func chosen(_ f: SaveFile, _ part: InteriorPart) -> InteriorStyle {
        if let id = f.interior[part], let st = style(id), st.part == part, owns(f, id) { return st }
        return standard(part)
    }

    static func shown(_ f: SaveFile) -> InteriorShown {
        InteriorShown(walls: chosen(f, .walls).id, floor: chosen(f, .floor).id, rug: chosen(f, .rug).id)
    }

    // MARK: покупка и выбор

    /// Купить и сразу поставить. Порядок отказов: нет такого → уже есть → не хватает.
    /// Тратит только монеты или клочки кошелька: ни дохода, ни потолков, ни уровня не касается.
    static func buy(_ id: String, in f: inout SaveFile, now: Double,
                    _ cfg: InteriorConfig = .shared) -> Result<InteriorStyle, InteriorRefusal> {
        guard let st = style(id) else { return .failure(.unknown) }
        if owns(f, id) { return .failure(.owned) }
        let price = cfg.price(st)
        switch st.currency {
        case .free: return .failure(.owned)
        case .coins:
            guard Economy.spend(&f, coins: price) else {
                return .failure(.notEnoughCoins(need: price - f.econ.wallet.coins))
            }
        case .shards:
            guard Shards.spend(&f, price) else { return .failure(.notEnoughShards(need: price - f.econ.wallet.shards)) }
        }
        f.interior.owned.append(id)
        set(st, in: &f)
        f.log("interior.buy", t: now, key: id, value: price)
        return .success(st)
    }

    /// Поставить своё. По умолчанию — поле части очищается (nil), чтобы сейв оставался пустым.
    static func choose(_ id: String, in f: inout SaveFile) -> Result<InteriorStyle, InteriorRefusal> {
        guard let st = style(id) else { return .failure(.unknown) }
        guard owns(f, id) else { return .failure(.notOwned) }
        set(st, in: &f)
        return .success(st)
    }

    private static func set(_ st: InteriorStyle, in f: inout SaveFile) {
        f.interior[st.part] = st.id == standard(st.part).id ? nil : st.id
    }

    /// Через стор: одна запись под замком.
    static func perform(buy id: String, store: PetStore = .shared,
                        now: Double = Clock.now()) throws -> Result<InteriorStyle, InteriorRefusal> {
        try store.mutate { f in buy(id, in: &f, now: now) }
    }

    static func perform(choose id: String, store: PetStore = .shared) throws -> Result<InteriorStyle, InteriorRefusal> {
        try store.mutate { f in choose(id, in: &f) }
    }

    // MARK: лист

    /// Строки части для листа «Интерьер»: по каталогу, с ценой и состоянием.
    static func offers(_ f: SaveFile, _ part: InteriorPart, _ cfg: InteriorConfig = .shared) -> [InteriorOffer] {
        let now = chosen(f, part).id
        return styles(part).map { st in
            let price = cfg.price(st)
            let state: InteriorOffer.State
            if st.id == now { state = .chosen }
            else if owns(f, st.id) { state = .owned }
            else {
                let have = st.currency == .shards ? f.econ.wallet.shards : f.econ.wallet.coins
                state = .buy(need: max(0, price - have))
            }
            return InteriorOffer(style: st, price: price, state: state)
        }
    }
}

// MARK: - Тексты

/// Строки листа «Интерьер» из lines.json (раздел ui, ключи interior_*). Тест проверяет, что все есть.
enum InteriorText {
    static let keys = [
        "interior_title", "interior_note", "interior_open",
        "interior_part_walls", "interior_part_floor", "interior_part_rug",
        "interior_chosen", "interior_pick", "interior_buy_coins", "interior_buy_shards",
        "interior_need_coins", "interior_need_shards", "interior_free", "interior_exclusive",
        "interior_bought", "interior_set",
        "interior_refuse_owned", "interior_refuse_not_owned", "interior_refuse_unknown",
    ]

    static func ui(_ key: String, _ vars: [String: String] = [:], lines: Lines = .shared) -> String {
        EconText.ui(key, vars, lines: lines)
    }

    static func partName(_ p: InteriorPart) -> String { ui("interior_part_\(p.rawValue)") }

    /// Подпись кнопки строки: «Стоит», «Поставить», «300 🪙», «Не хватает 50 🪙».
    static func button(_ o: InteriorOffer) -> String {
        switch o.state {
        case .chosen: return ui("interior_chosen")
        case .owned: return ui("interior_pick")
        case .buy(let need):
            let shards = o.style.currency == .shards
            if need > 0 { return ui(shards ? "interior_need_shards" : "interior_need_coins", ["n": "\(need)"]) }
            return ui(shards ? "interior_buy_shards" : "interior_buy_coins", ["n": "\(o.price)"])
        }
    }

    static func refusal(_ r: InteriorRefusal) -> String {
        switch r {
        case .notEnoughCoins(let need): return ui("interior_need_coins", ["n": "\(need)"])
        case .notEnoughShards(let need): return ui("interior_need_shards", ["n": "\(need)"])
        case .owned: return ui("interior_refuse_owned")
        case .notOwned: return ui("interior_refuse_not_owned")
        case .unknown: return ui("interior_refuse_unknown")
        }
    }
}

// MARK: - Узоры (чистая геометрия, сцена только собирает из неё сущности)

/// Плоская фигура на стене: веер треугольников из center по rim (звезда — тоже звёздная от центра).
/// Координаты — метры стены от её левого нижнего угла.
struct WallShape: Hashable, Sendable {
    var center: SIMD2<Float>
    var rim: [SIMD2<Float>]
    var color: UInt32
}

/// Кусок ковра: диск, эллипс или брусок; центр в (x, z) от середины ковра, верх на top.
struct RugPiece: Hashable, Sendable {
    /// Не «Shape»: имя затенило бы SwiftUI.Shape в приложении (Wave5SeamTests).
    enum Cut: Hashable, Sendable {
        case disc(r: Float)
        case ellipse(rx: Float, rz: Float)
        case box(w: Float, d: Float)
    }

    var shape: Cut
    var x: Float = 0
    var z: Float = 0
    var top: Float
    var color: UInt32

    /// Полуразмеры по x и z — для проверки, что ковёр не вылезает за прежний круг.
    var halfX: Float {
        switch shape {
        case .disc(let r): return r
        case .ellipse(let rx, _): return rx
        case .box(let w, _): return w / 2
        }
    }

    var halfZ: Float {
        switch shape {
        case .disc(let r): return r
        case .ellipse(_, let rz): return rz
        case .box(_, let d): return d / 2
        }
    }
}

enum InteriorArt {
    /// Размеры, как у комнаты (PetRoom): пол 5 × 5 м, клеток 10, стена 5 × 2,2 м, ковёр r 0,45.
    static let floorSize: Float = 5
    static let floorCells = 10
    static let wallWidth: Float = 5
    static let wallHeight: Float = 2.2
    static let rugRadius: Float = 0.45
    /// Толщина ковра и шаг слоёв: каждый следующий слой выше на step, чтобы не мерцали.
    static let rugThickness: Float = 0.004
    static let rugStep: Float = 0.0008
    /// Потолок верха ковра: ниже матраса лежанки (RoomPlan.bedTop 0,01) и пятна-тени (0,013).
    static let rugMaxTop: Float = 0.007

    // MARK: стены

    /// Узор поверх фона стены. Шаг мелкий: окно 0,45 м, в кадре видно около метра стены.
    static func wallShapes(_ look: WallLook, width: Float = wallWidth, height: Float = wallHeight) -> [WallShape] {
        switch look {
        case .plain:
            return []
        case .stripes(_, let c):
            // Вертикальные полосы 0,04 м через 0,12 м, первая — с отступом полшага.
            var out: [WallShape] = []
            var x: Float = 0.04
            while x + 0.04 <= width {
                out.append(rect(x, 0, x + 0.04, height, c))
                x += 0.12
            }
            return out
        case .panel(_, let lower, let rail):
            // Панель до 0,16 м (ниже окна 0,21 и полотенца 0,22) и рейка над ней.
            return [rect(0, 0, width, 0.16, lower), rect(0, 0.16, width, 0.175, rail)]
        case .diamonds(_, let c):
            // Ромбики 0,05 × 0,07 в шахматном порядке через 0,15 м.
            return grid(width: width, height: height, step: 0.15) { p, _ in diamond(p, 0.025, 0.035, c) }
        case .stars(_, let star, let dot):
            // Звёздочки и точки по очереди, шаг 0,16 м.
            return grid(width: width, height: height, step: 0.16) { p, odd in
                odd ? diamond(p, 0.012, 0.012, dot) : starShape(p, 0.03, 0.011, star)
            }
        }
    }

    private static func rect(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ c: UInt32) -> WallShape {
        WallShape(center: SIMD2((x0 + x1) / 2, (y0 + y1) / 2),
                  rim: [SIMD2(x0, y0), SIMD2(x1, y0), SIMD2(x1, y1), SIMD2(x0, y1)], color: c)
    }

    private static func diamond(_ p: SIMD2<Float>, _ hx: Float, _ hy: Float, _ c: UInt32) -> WallShape {
        WallShape(center: p, rim: [p + SIMD2(0, -hy), p + SIMD2(hx, 0), p + SIMD2(0, hy), p + SIMD2(-hx, 0)], color: c)
    }

    /// Четырёхлучевая звёздочка: лучи r, впадины r2 (против часовой, как у ромба).
    private static func starShape(_ p: SIMD2<Float>, _ r: Float, _ r2: Float, _ c: UInt32) -> WallShape {
        var rim: [SIMD2<Float>] = []
        for i in 0..<8 {
            let a = Float(i) * .pi / 4 - .pi / 2
            let d = i % 2 == 0 ? r : r2
            rim.append(p + SIMD2(Float(cos(Double(a))) * d, Float(sin(Double(a))) * d))
        }
        return WallShape(center: p, rim: rim, color: c)
    }

    /// Шахматная сетка точек: ряды через step, каждый второй ряд сдвинут на полшага; odd — чередование в ряду.
    private static func grid(width: Float, height: Float, step: Float,
                             _ make: (SIMD2<Float>, Bool) -> WallShape) -> [WallShape] {
        var out: [WallShape] = []
        var row = 0
        var y = step / 2
        while y + step / 4 <= height {
            var x = row % 2 == 0 ? step / 2 : step
            var col = 0
            while x + step / 4 <= width {
                out.append(make(SIMD2(x, y), (row + col) % 2 == 1))
                x += step
                col += 1
            }
            y += step
            row += 1
        }
        return out
    }

    // MARK: пол

    /// Цвет пола в точке (u, v) метров от левого нижнего угла текстуры.
    static func floorColor(_ look: FloorLook, u: Float, v: Float) -> UInt32 {
        switch look {
        case .checker(let a, let b):
            let cell = floorSize / Float(floorCells)
            let col = Int(u / cell), row = Int(v / cell)
            return (row + col) % 2 == 0 ? a : b
        case .planks(let a, let b, let seam):
            // Доски 0,2 × 0,8 м вдоль x, ряды вразбежку на полдоски; шов — 1,5 см.
            let w: Float = 0.2, len: Float = 0.8, gap: Float = 0.015
            let row = Int(v / w)
            let shifted = u + (row % 2 == 0 ? 0 : len / 2)
            let inRow = v - Float(row) * w, inPlank = shifted.truncatingRemainder(dividingBy: len)
            if inRow < gap || inPlank < gap { return seam }
            let plank = Int(shifted / len)
            return (row + plank) % 2 == 0 ? a : b
        case .zigzag(let a, let b):
            // Ёлочка: полосы 0,2 м, изломанные зубцами шириной 0,4 м.
            let tooth: Float = 0.4, band: Float = 0.2
            let t = u.truncatingRemainder(dividingBy: tooth)
            let lift = abs(t - tooth / 2)
            return Int((v + lift) / band) % 2 == 0 ? a : b
        }
    }

    /// Пиксели текстуры пола RGBX сверху вниз (как ждёт CGImage). Ряд 0 — верх картинки, v считается снизу:
    /// так клетка по умолчанию совпадает с прежней PetRoom.checkerImage (CGContext рисует от левого нижнего угла).
    static func floorPixels(_ look: FloorLook, size: Int) -> [UInt8] {
        guard size > 0 else { return [] }
        var out = [UInt8](repeating: 255, count: size * size * 4)
        let px = floorSize / Float(size)
        for yTop in 0..<size {
            let v = (Float(size - 1 - yTop) + 0.5) * px
            for x in 0..<size {
                let c = floorColor(look, u: (Float(x) + 0.5) * px, v: v)
                let i = (yTop * size + x) * 4
                out[i] = UInt8((c >> 16) & 0xff)
                out[i + 1] = UInt8((c >> 8) & 0xff)
                out[i + 2] = UInt8(c & 0xff)
            }
        }
        return out
    }

    // MARK: ковёр

    /// Куски ковра снизу вверх. По умолчанию — один диск, как прежний ковёр PetRoom.
    static func rugPieces(_ look: RugLook) -> [RugPiece] {
        let r = rugRadius, h = rugThickness, s = rugStep
        switch look {
        case .round(let c):
            return [RugPiece(shape: .disc(r: r), top: h, color: c)]
        case .rings(let cs):
            // Кольца — диски поменьше друг на друге.
            return cs.prefix(4).enumerated().map { i, c in
                RugPiece(shape: .disc(r: r * (1 - Float(i) * 0.27)), top: h + Float(i) * s, color: c)
            }
        case .oval(let c, let border):
            return [RugPiece(shape: .ellipse(rx: r, rz: 0.32), top: h, color: border),
                    RugPiece(shape: .ellipse(rx: r - 0.05, rz: 0.27), top: h + s, color: c)]
        case .square(let c, let border):
            return [RugPiece(shape: .box(w: 0.78, d: 0.62), top: h, color: border),
                    RugPiece(shape: .box(w: 0.68, d: 0.52), top: h + s, color: c)]
        case .stripes(let cs):
            // Полосы поперёк на светлой основе: основа, сверху ровные бруски.
            let w: Float = 0.80, d: Float = 0.60
            let n = max(1, cs.count)
            let sw = (w - 0.06) / Float(n)
            var out = [RugPiece(shape: .box(w: w, d: d), top: h, color: 0xf6efe2)]
            for (i, c) in cs.enumerated() {
                let x = -w / 2 + 0.03 + sw * (Float(i) + 0.5)
                out.append(RugPiece(shape: .box(w: sw, d: d - 0.06), x: x, top: h + s, color: c))
            }
            return out
        }
    }
}

extension RoomLight {
    /// Яркость цвета стены под этим светом — как wallLuminance, но для любого фона (обои, волна 41 G).
    func wallLuminance(_ hex: UInt32) -> Double { (RoomRGB(hex: hex) * tint).luminance }
}
