// Волна 33 C: двор-тайкун — ярусы, плиты, станции, копилка на 12 ч (RESEARCH/20-tycoon-design.md §1, §2).
//
// Ярус двора = уровень линии дома `yard` (Подоконник → Дворик → Сад → Парк → Квартал). Сам ярус покупает
// HomeShop; здесь только правило «кнопка следующего яруса» (Yard.nextTier): куплены плиты прошлых ярусов,
// доступные к этому уровню, и пёс дорос. На ярусе — плиты по порядку: декор (уют) и станции (доход).
//
// Копилка `bank`: bank = min(cap, bank + rate·Δt), cap = 12 ч · rate. Перед любой покупкой — начисление по старой
// ставке (Yard.accrue), потом новая ставка. Часы назад: ничего не начисляем и метку не двигаем.
// Сбор — тап по копилке (решение владельца): в кошелёк floor(bank), дробь остаётся; чаевые по StableHash
// (≤ 2 в сутки, копилка ≥ 50 %); пищевые станции кладут порции в запас кухни (pet.pantry), лишнее ждёт в larder.
// Перерождения нет (волна 33).
//
// Уровень пса и уровни линий дома — ПАРАМЕТРЫ: DogLevel здесь не читается, связывает сливающий.
// Цифры — раздел yard в config/economy.json, без ключа — значения ниже.
//
// Волна 34 G: взрослый пёс дома стоит у самой доходной станции — +stationBonusPct % к ней (Growth.perks, YardHelper).
// Помощник — параметр чистых функций; обёртки над SaveFile берут его из сейва (Yard.helper). Упрощение: за весь
// отрезок с прошлого начисления — по тому, дома ли пёс в момент начисления (сбор, покупка, открытие экрана).

import Foundation
@preconcurrency import PetCore

// MARK: - Конфиг

/// Ярус двора: имя, с какого уровня пса открывается, цена уровня линии `yard` (её платит HomeShop).
struct YardTier: Hashable, Sendable {
    let name: String
    let level: Int
    let price: Int
}

/// Станция дохода: 🪙/ч и цены по уровням 1…5 (prices[0] — постройка), порция в кладовую.
struct YardStation: Hashable, Sendable {
    let id: String
    let name: String
    let rates: [Int]
    let prices: [Int]
    /// Пищевая: одна порция за столько часов копилки; nil — не пищевая.
    let portionHours: Double?
    /// Что за порция («каша») и сколько это запаса кухни.
    let portionName: String?
    let portionPantry: Double

    var maxLevel: Int { min(rates.count, prices.count) }

    /// Ставка на уровне (1…max), за пределами — 0.
    func rate(_ level: Int) -> Int { level >= 1 && level <= maxLevel ? rates[level - 1] : 0 }

    /// Цена перехода на уровень (1 — постройка); nil — такого уровня нет.
    func price(toLevel level: Int) -> Int? { level >= 1 && level <= maxLevel ? prices[level - 1] : nil }
}

/// Плита на земле: декор или станция (id совпадает с id станции).
struct YardPlate: Hashable, Sendable {
    let id: String
    let name: String
    let tier: Int
    let price: Int
    /// Уровень пса для покупки (не ниже уровня яруса).
    let level: Int
    /// Нужный уровень линии «Кухня» (0 — не нужна).
    let kitchen: Int
    /// Очки уюта (у станций 0).
    let cozy: Int
    let isStation: Bool
}

struct YardConfig: Hashable, Sendable {
    /// Копилка полная за столько часов и дальше не копит.
    var bankHours: Double = 12
    var tiers: [YardTier] = YardConfig.stubTiers
    var stations: [YardStation] = YardConfig.stubStations
    var plates: [YardPlate] = YardConfig.stubPlates
    // чаевые при сборе
    var tipsPerDay = 2
    var tipMinFillPct = 50
    /// Веса исходов в процентах (ничего — остаток до 100).
    var tipBonusPct = 20
    var tipIngredientPct = 8
    var tipTicketPct = 2
    /// Прибавка к сбору у исхода «бонус», %.
    var tipBonusSize = 10
    /// Сколько запаса кухни даёт ингредиент из чаевых.
    var tipIngredientPantry: Double = 5
    /// С этого уровня пса шанс чаевых ×tipLuckX (ур. 15).
    var tipLuckLevel = 15
    var tipLuckX: Double = 1.5
    /// Прибавка ко всем станциям по уровню пса: уровень → %, суммируется (ур. 25 +5, 31–34 по +2).
    var levelBoost: [Int: Int] = [25: 5, 31: 2, 32: 2, 33: 2, 34: 2]

    static let stubTiers: [YardTier] = [
        YardTier(name: "Подоконник", level: 1, price: 0),
        YardTier(name: "Дворик", level: 4, price: 700),
        YardTier(name: "Сад", level: 9, price: 1700),
        YardTier(name: "Парк", level: 12, price: 3500),
        YardTier(name: "Квартал", level: 20, price: 9000),
    ]

    static let stubStations: [YardStation] = [
        YardStation(id: "dryer", name: "Сушилка сухариков", rates: [4, 6, 8, 11, 14],
                    prices: [40, 60, 100, 140, 210], portionHours: nil, portionName: nil, portionPantry: 0),
        YardStation(id: "bones", name: "Косточковая грядка", rates: [6, 9, 13, 17, 22],
                    prices: [250, 400, 600, 900, 1300], portionHours: nil, portionName: nil, portionPantry: 0),
        YardStation(id: "porridge", name: "Котелок каши", rates: [9, 14, 19, 25, 32],
                    prices: [900, 1450, 2150, 3250, 4700], portionHours: 6, portionName: "каша", portionPantry: 5),
        YardStation(id: "spinner", name: "Прялка из шерсти", rates: [13, 20, 27, 36, 47],
                    prices: [2200, 3500, 5300, 7900, 11400], portionHours: nil, portionName: nil, portionPantry: 0),
        YardStation(id: "pies", name: "Пирожковая печь", rates: [18, 27, 38, 50, 65],
                    prices: [4500, 7200, 10800, 16200, 23400], portionHours: 6, portionName: "пирожок", portionPantry: 8),
        YardStation(id: "photo", name: "Фотобудка", rates: [24, 36, 50, 67, 86],
                    prices: [8500, 13600, 20400, 30600, 41000], portionHours: nil, portionName: nil, portionPantry: 0),
        YardStation(id: "sausage", name: "Сосисочный конвейер", rates: [32, 48, 67, 90, 115],
                    prices: [15000, 24000, 36000, 49500, 54000], portionHours: 4, portionName: "сосиска", portionPantry: 10),
        YardStation(id: "mill", name: "Лунная мельница", rates: [42, 63, 88, 118, 151],
                    prices: [26000, 41600, 54000, 64500, 71000], portionHours: nil, portionName: nil, portionPantry: 0),
    ]

    /// Плиты по ярусам в порядке покупки. Цена станции-плиты = постройка станции.
    static let stubPlates: [YardPlate] = {
        func d(_ id: String, _ name: String, _ tier: Int, _ price: Int, _ cozy: Int) -> YardPlate {
            YardPlate(id: id, name: name, tier: tier, price: price, level: stubTiers[tier].level, kitchen: 0,
                      cozy: cozy, isStation: false)
        }
        func s(_ id: String, _ tier: Int, level: Int, kitchen: Int = 0) -> YardPlate {
            let st = stubStations.first { $0.id == id }!
            return YardPlate(id: id, name: st.name, tier: tier, price: st.prices[0], level: level, kitchen: kitchen,
                             cozy: 0, isStation: true)
        }
        return [
            d("window", "Протереть окно", 0, 10, 3), d("daisy", "Горшок с ромашкой", 0, 30, 3), s("dryer", 0, level: 2),
            d("trash", "Убрать мусор", 1, 60, 4), d("fence", "Починить забор", 1, 150, 4),
            d("path", "Тропинка из плитки", 1, 200, 5), d("lamp", "Фонарь", 1, 300, 5),
            s("bones", 1, level: 4), s("porridge", 1, level: 7, kitchen: 1),
            d("mailbox", "Почтовый ящик", 2, 400, 5), d("apple", "Яблоня", 2, 500, 6),
            d("bench", "Скамейка", 2, 600, 6), d("pond", "Пруд с лягушкой", 2, 1200, 8),
            s("spinner", 2, level: 10), s("pies", 2, level: 14, kitchen: 2),
            d("nameplate", "Табличка с именем пса", 3, 1000, 6), d("garland", "Гирлянда", 3, 1500, 7),
            d("vane", "Флюгер-кость", 3, 1800, 7), d("fountain", "Фонтан-миска", 3, 3000, 10),
            s("photo", 3, level: 18),
            d("sign", "Вывеска «‹Имя› и Ко»", 4, 5000, 10), d("telescope", "Телескоп", 4, 6000, 8),
            s("sausage", 4, level: 23), s("mill", 4, level: 28),
        ]
    }()

    static let shared = YardConfig(json: Catalog.economy() ?? .null)

    init() {}

    init(json e: JSONValue) {
        func int(_ v: JSONValue, _ d: Int) -> Int { v.double.map { Int($0) } ?? d }
        func ints(_ v: JSONValue) -> [Int] { v.array.compactMap { $0.double.map { Int($0) } } }
        let y = e["yard"]
        if let h = y["bank_hours"].double, h > 0 { bankHours = h }

        let tr = y["tiers"].array.compactMap { (t: JSONValue) -> YardTier? in
            guard let name = t["name"].string else { return nil }
            return YardTier(name: name, level: max(1, int(t["level"], 1)), price: max(0, int(t["price"], 0)))
        }
        if !tr.isEmpty { tiers = tr }

        let st = y["stations"].array.compactMap { (s: JSONValue) -> YardStation? in
            guard let id = s["id"].string else { return nil }
            let rates = ints(s["rates"]), prices = ints(s["prices"])
            guard !rates.isEmpty, rates.count == prices.count else { return nil }
            let p = s["portion"]
            return YardStation(id: id, name: s["name"].string ?? id, rates: rates.map { max(0, $0) },
                               prices: prices.map { max(0, $0) }, portionHours: p["hours"].double.flatMap { $0 > 0 ? $0 : nil },
                               portionName: p["name"].string, portionPantry: max(0, p["pantry"].double ?? 0))
        }
        if !st.isEmpty { stations = st }

        let tiersNow = tiers, stationsNow = stations
        let pl = y["plates"].array.compactMap { (p: JSONValue) -> YardPlate? in
            guard let id = p["id"].string else { return nil }
            let tier = min(max(0, int(p["tier"], 0)), tiersNow.count - 1)
            let station = stationsNow.first { $0.id == id }
            guard let price = station?.prices.first ?? p["price"].double.map({ Int($0) }) else { return nil }
            return YardPlate(id: id, name: p["name"].string ?? station?.name ?? id, tier: tier, price: max(0, price),
                             level: max(tiersNow[tier].level, int(p["level"], 1)), kitchen: max(0, int(p["kitchen"], 0)),
                             cozy: station == nil ? max(0, int(p["cozy"], 0)) : 0, isStation: station != nil)
        }
        if !pl.isEmpty { plates = pl }

        let tp = y["tips"]
        tipsPerDay = max(0, int(tp["per_day"], tipsPerDay))
        tipMinFillPct = min(100, max(0, int(tp["min_fill_pct"], tipMinFillPct)))
        tipBonusPct = max(0, int(tp["bonus_pct"], tipBonusPct))
        tipIngredientPct = max(0, int(tp["ingredient_pct"], tipIngredientPct))
        tipTicketPct = max(0, int(tp["ticket_pct"], tipTicketPct))
        tipBonusSize = max(0, int(tp["bonus_size_pct"], tipBonusSize))
        tipIngredientPantry = max(0, tp["ingredient_pantry"].double ?? tipIngredientPantry)
        tipLuckLevel = max(1, int(tp["luck_level"], tipLuckLevel))
        tipLuckX = max(0, tp["luck_x"].double ?? tipLuckX)

        let lb = y["level_boost_pct"].object
        if !lb.isEmpty {
            var m: [Int: Int] = [:]
            for (k, v) in lb { if let l = Int(k), let n = v.double { m[l] = max(0, Int(n)) } }
            levelBoost = m
        }
    }

    func station(_ id: String) -> YardStation? { stations.first { $0.id == id } }
    func plate(_ id: String) -> YardPlate? { plates.first { $0.id == id } }
    func plates(tier: Int) -> [YardPlate] { plates.filter { $0.tier == tier } }
    var maxTier: Int { tiers.count - 1 }

    /// Прибавка ко всем станциям от уровня пса, %.
    func boostPct(dogLevel: Int) -> Int { levelBoost.reduce(0) { $0 + ($1.key <= dogLevel ? $1.value : 0) } }
}

// MARK: - Состояние в SaveFile

/// Состояние в SaveFile. Пустое не пишется — старые сейвы читаются без этого поля.
struct YardState: Codable, Hashable, Sendable {
    /// Купленные плиты-декор и станции (id) — в порядке покупки.
    var plates: [String] = []
    /// Станция → уровень 1…5.
    var stations: [String: Int] = [:]
    /// Копилка, монеты с дробью.
    var bank: Double = 0
    /// Метка последнего начисления (unix); 0 — копить ещё нечему.
    var t: Double = 0
    /// Пищевые станции: часы копилки на порции (потолок — bankHours).
    var food: [String: Double] = [:]
    /// Запас, который не влез в кухню — ждёт следующего сбора (единицы pet.pantry).
    var larder: Double = 0
    /// Чаевые: сутки и сколько бросков было за них.
    var tipDay = 0
    var tipsToday = 0
    /// Номер сбора — бросок чаевых по StableHash.
    var collects = 0
    /// Всего собрано монет (статистика).
    var collected = 0

    init() {}

    var isEmpty: Bool { self == YardState() }

    func owns(_ plate: String) -> Bool { plates.contains(plate) || stations[plate] != nil }

    enum CodingKeys: String, CodingKey {
        case plates, stations, bank, t, food, larder, tipDay, tipsToday, collects, collected
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plates = (try? c.decodeIfPresent([String].self, forKey: .plates)) ?? []
        stations = (try? c.decodeIfPresent([String: Int].self, forKey: .stations)) ?? [:]
        bank = max(0, (try? c.decodeIfPresent(Double.self, forKey: .bank)) ?? 0)
        t = (try? c.decodeIfPresent(Double.self, forKey: .t)) ?? 0
        food = (try? c.decodeIfPresent([String: Double].self, forKey: .food)) ?? [:]
        larder = max(0, (try? c.decodeIfPresent(Double.self, forKey: .larder)) ?? 0)
        tipDay = (try? c.decodeIfPresent(Int.self, forKey: .tipDay)) ?? 0
        tipsToday = (try? c.decodeIfPresent(Int.self, forKey: .tipsToday)) ?? 0
        collects = (try? c.decodeIfPresent(Int.self, forKey: .collects)) ?? 0
        collected = (try? c.decodeIfPresent(Int.self, forKey: .collected)) ?? 0
    }
}

// MARK: - Результаты

/// Почему плиту нельзя купить сейчас.
enum YardLock: Hashable, Sendable {
    /// Ярус ещё не открыт (уровень линии `yard` ниже).
    case tier(Int)
    /// Пёс не дорос.
    case level(Int)
    /// Нужна кухня этого уровня.
    case kitchen(Int)
    /// Сначала предыдущая плита яруса.
    case order(String)
}

enum YardBuyResult: Hashable, Sendable {
    case ok(price: Int)
    /// Улучшение станции: новый уровень.
    case upgraded(level: Int, price: Int)
    case owned
    case maxed
    case notBuilt
    case locked(YardLock)
    case noCoins(need: Int)
    case unknown
}

/// Кнопка следующего яруса.
enum YardTierGate: Hashable, Sendable {
    /// Можно покупать уровень линии `yard`.
    case open(tier: Int, price: Int)
    /// Пёс не дорос.
    case level(tier: Int, need: Int)
    /// Не куплены плиты прошлых ярусов (id по порядку).
    case plates(tier: Int, left: [String])
    case maxed
}

/// Пёс-помощник у станции: +pct % к её ставке (взрослый и дома, волна 34 G).
struct YardHelper: Hashable, Sendable {
    let station: String
    let pct: Int
}

/// Исход чаевых при сборе.
enum YardTip: String, Hashable, Sendable {
    case none, bonus, ingredient, ticket
}

/// Что принёс сбор.
struct YardHarvest: Hashable, Sendable {
    var coins = 0
    /// Прибавка от чаевых «бонус» (уже в coins).
    var bonus = 0
    var tickets = 0
    /// Порции по станциям: id → штук.
    var portions: [String: Int] = [:]
    /// Запас кухни от порций и чаевых.
    var pantry: Double = 0
    var tip: YardTip = .none

    var isEmpty: Bool { coins == 0 && tickets == 0 && pantry == 0 }
}

// MARK: - Логика

enum Yard {
    // MARK: ставка и копилка

    /// Общая ставка 🪙/ч: сумма по станциям, с прибавкой от уровня пса и от пса-помощника.
    static func rate(_ s: YardState, dogLevel: Int, helper: YardHelper? = nil, _ cfg: YardConfig = .shared) -> Double {
        s.stations.keys.sorted().reduce(0) { sum, id in
            sum + stationRate(id, level: s.stations[id] ?? 0, dogLevel: dogLevel, helper: helper, cfg)
        }
    }

    /// Ставка одной станции для таблички «+14/ч» (с прибавкой от уровня; помощник — только своей станции).
    static func stationRate(_ id: String, level: Int, dogLevel: Int, helper: YardHelper? = nil,
                            _ cfg: YardConfig = .shared) -> Double {
        let near = helper?.station == id ? max(0, helper?.pct ?? 0) : 0
        return Double(cfg.station(id)?.rate(level) ?? 0) * (1 + Double(cfg.boostPct(dogLevel: dogLevel) + near) / 100)
    }

    /// У какой станции встанет пёс: самая доходная по базовой ставке, при равенстве — раньше в конфиге.
    static func helperStation(_ s: YardState, _ cfg: YardConfig = .shared) -> String? {
        var best: (id: String, rate: Int)?
        for st in cfg.stations {
            guard let lv = s.stations[st.id] else { continue }
            if best.map({ st.rate(lv) > $0.rate }) ?? true { best = (st.id, st.rate(lv)) }
        }
        return best?.id
    }

    /// Потолок копилки при ставке.
    static func cap(rate: Double, _ cfg: YardConfig = .shared) -> Double { rate * cfg.bankHours }

    /// Начислить до now по текущей ставке. Часы назад (now ≤ t): ничего, метку не двигаем.
    static func accrue(_ s: inout YardState, now: Double, dogLevel: Int, helper: YardHelper? = nil,
                       _ cfg: YardConfig = .shared) {
        guard !s.stations.isEmpty else { return }   // копить нечему
        guard s.t > 0 else { s.t = now; return }
        let dt = now - s.t
        guard dt > 0 else { return }
        let h = dt / 3600
        let r = rate(s, dogLevel: dogLevel, helper: helper, cfg)
        // Уже выше потолка (конфиг стал скромнее) — не отнимаем.
        s.bank = max(s.bank, min(cap(rate: r, cfg), s.bank + r * h))
        for id in s.stations.keys.sorted() where cfg.station(id)?.portionHours != nil {
            s.food[id] = min(cfg.bankHours, (s.food[id] ?? 0) + h)
        }
        s.t = now
    }

    /// Копилка на момент now без записи.
    static func peek(_ s: YardState, now: Double, dogLevel: Int, helper: YardHelper? = nil,
                     _ cfg: YardConfig = .shared) -> YardState {
        var c = s
        accrue(&c, now: now, dogLevel: dogLevel, helper: helper, cfg)
        return c
    }

    /// Заполненность копилки 0…1 на момент now.
    static func fill(_ s: YardState, now: Double, dogLevel: Int, helper: YardHelper? = nil,
                     _ cfg: YardConfig = .shared) -> Double {
        let c = peek(s, now: now, dogLevel: dogLevel, helper: helper, cfg)
        let cp = cap(rate: rate(c, dogLevel: dogLevel, helper: helper, cfg), cfg)
        return cp > 0 ? min(1, c.bank / cp) : 0
    }

    /// Когда копилка станет полной (для свинки, островка и виджета); nil — станций нет.
    /// Уже полная — now. Часы назад — от сохранённой метки (время до неё не копится).
    static func fullAt(_ s: YardState, now: Double, dogLevel: Int, helper: YardHelper? = nil,
                       _ cfg: YardConfig = .shared) -> Double? {
        let c = peek(s, now: now, dogLevel: dogLevel, helper: helper, cfg)
        let r = rate(c, dogLevel: dogLevel, helper: helper, cfg)
        guard r > 0 else { return nil }
        let left = cap(rate: r, cfg) - c.bank
        guard left > 0 else { return now }
        return max(now, c.t) + left / r * 3600
    }

    // MARK: ярусы

    /// Кнопка следующего яруса: пёс дорос и куплены плиты прошлых ярусов, доступные к уровню этого яруса.
    /// Пищевые станции с кухней ярус не держат: двор не ждёт покупки в другой линии дома.
    static func nextTier(_ s: YardState, yardLevel: Int, dogLevel: Int, _ cfg: YardConfig = .shared) -> YardTierGate {
        let n = max(0, yardLevel) + 1
        guard n <= cfg.maxTier else { return .maxed }
        let tier = cfg.tiers[n]
        let left = cfg.plates.filter { $0.tier < n && $0.level <= tier.level && $0.kitchen == 0 && !s.owns($0.id) }
        if !left.isEmpty { return .plates(tier: n, left: left.map(\.id)) }
        guard dogLevel >= tier.level else { return .level(tier: n, need: tier.level) }
        return .open(tier: n, price: tier.price)
    }

    // MARK: плиты

    /// Почему плиту нельзя купить; nil — можно (если хватит монет).
    static func lock(_ id: String, _ s: YardState, yardLevel: Int, dogLevel: Int, kitchenLevel: Int,
                     _ cfg: YardConfig = .shared) -> YardLock? {
        guard let p = cfg.plate(id) else { return nil }
        if yardLevel < p.tier { return .tier(p.tier) }
        if let prev = cfg.plates(tier: p.tier).prefix(while: { $0.id != id }).first(where: { !s.owns($0.id) }) {
            return .order(prev.id)
        }
        if dogLevel < p.level { return .level(p.level) }
        if kitchenLevel < p.kitchen { return .kitchen(p.kitchen) }
        return nil
    }

    /// Следующая плита для полоски «ещё 340 🪙»: первая некупленная на открытых ярусах; nil — всё куплено.
    static func nextPlate(_ s: YardState, yardLevel: Int, _ cfg: YardConfig = .shared) -> YardPlate? {
        cfg.plates.first { $0.tier <= yardLevel && !s.owns($0.id) }
    }

    /// Купить плиту: начислить по старой ставке, списать, поставить. Станция встаёт на уровень 1.
    @discardableResult
    static func buyPlate(_ id: String, _ s: inout YardState, coins: inout Int, now: Double, yardLevel: Int,
                         dogLevel: Int, kitchenLevel: Int, helper: YardHelper? = nil,
                         _ cfg: YardConfig = .shared) -> YardBuyResult {
        guard let p = cfg.plate(id) else { return .unknown }
        guard !s.owns(id) else { return .owned }
        if let l = lock(id, s, yardLevel: yardLevel, dogLevel: dogLevel, kitchenLevel: kitchenLevel, cfg) {
            return .locked(l)
        }
        accrue(&s, now: now, dogLevel: dogLevel, helper: helper, cfg)
        guard coins >= p.price else { return .noCoins(need: p.price - coins) }
        coins -= p.price
        if p.isStation {
            s.stations[id] = 1
            if s.t == 0 { s.t = now }   // первая станция: копилка пошла с этой минуты
        } else {
            s.plates.append(id)
        }
        return .ok(price: p.price)
    }

    /// Улучшить станцию на уровень: начислить по старой ставке, потом новая (потолок растёт вместе с ней).
    @discardableResult
    static func upgrade(_ id: String, _ s: inout YardState, coins: inout Int, now: Double, dogLevel: Int,
                        helper: YardHelper? = nil, _ cfg: YardConfig = .shared) -> YardBuyResult {
        guard let st = cfg.station(id) else { return .unknown }
        guard let lv = s.stations[id] else { return .notBuilt }
        guard let price = st.price(toLevel: lv + 1) else { return .maxed }
        accrue(&s, now: now, dogLevel: dogLevel, helper: helper, cfg)
        guard coins >= price else { return .noCoins(need: price - coins) }
        coins -= price
        s.stations[id] = lv + 1
        return .upgraded(level: lv + 1, price: price)
    }

    // MARK: сбор

    /// Сбор — тап по копилке. В кошелёк floor(bank), дробь остаётся; порции целыми, остаток часов остаётся.
    /// Чаевые: не чаще tipsPerDay бросков в сутки и только при копилке ≥ tipMinFillPct.
    static func collect(_ s: inout YardState, now: Double, dogLevel: Int, helper: YardHelper? = nil,
                        _ cfg: YardConfig = .shared) -> YardHarvest {
        accrue(&s, now: now, dogLevel: dogLevel, helper: helper, cfg)
        var h = YardHarvest()
        let r = rate(s, dogLevel: dogLevel, helper: helper, cfg)
        let cp = cap(rate: r, cfg)
        let fullPct = cp > 0 ? s.bank / cp * 100 : 0
        h.coins = Int(s.bank.rounded(.down))
        for id in s.food.keys.sorted() {
            guard let st = cfg.station(id), let per = st.portionHours, let have = s.food[id] else { continue }
            let n = Int((have / per + 1e-9).rounded(.down))
            guard n > 0 else { continue }
            h.portions[id] = n
            h.pantry += Double(n) * st.portionPantry
            s.food[id] = max(0, have - Double(n) * per)
        }
        guard h.coins > 0 || !h.portions.isEmpty else { return h }
        s.bank -= Double(h.coins)
        s.collects += 1

        // Чаевые: сутки — по DayKey, часы назад сутки не откатывают.
        if let d = DayKey.newer(than: s.tipDay, at: now) { s.tipDay = d; s.tipsToday = 0 }
        if s.tipsToday < cfg.tipsPerDay && fullPct + 1e-9 >= Double(cfg.tipMinFillPct) {
            s.tipsToday += 1
            h.tip = tip(day: s.tipDay, n: s.collects, dogLevel: dogLevel, cfg)
            switch h.tip {
            case .bonus: h.bonus = Int((Double(h.coins) * Double(cfg.tipBonusSize) / 100).rounded())
            case .ingredient: h.pantry += cfg.tipIngredientPantry
            case .ticket: h.tickets = 1
            case .none: break
            }
            h.coins += h.bonus
        }
        s.collected += h.coins
        return h
    }

    /// Бросок чаевых: детерминирован по суткам и номеру сбора. С ур. tipLuckLevel шансы ×tipLuckX.
    static func tip(day: Int, n: Int, dogLevel: Int, _ cfg: YardConfig = .shared) -> YardTip {
        let x = dogLevel >= cfg.tipLuckLevel ? cfg.tipLuckX : 1
        let roll = Double(StableHash.fnv1a("yard.tip|\(day)|\(n)") % 10_000) / 100   // 0…99,99
        var edge = Double(cfg.tipTicketPct) * x
        if roll < edge { return .ticket }
        edge += Double(cfg.tipIngredientPct) * x
        if roll < edge { return .ingredient }
        edge += Double(cfg.tipBonusPct) * x
        if roll < edge { return .bonus }
        return .none
    }

    // MARK: уют и подсказки

    /// Уют двора: сумма по купленным плитам-декору.
    static func cozy(_ s: YardState, _ cfg: YardConfig = .shared) -> Int {
        s.plates.reduce(0) { $0 + (cfg.plate($1)?.cozy ?? 0) }
    }

    /// Сколько сборов (полных копилок) копить на цену при этой ставке; 0 — уже хватает, nil — дохода нет.
    static func collectsToAfford(_ price: Int, coins: Int, rate: Double, _ cfg: YardConfig = .shared) -> Int? {
        let need = price - coins
        guard need > 0 else { return 0 }
        let full = cap(rate: rate, cfg)
        guard full > 0 else { return nil }
        return Int((Double(need) / full).rounded(.up))
    }

    /// Окупаемость улучшения в днях: цена / прибавка ставки / 24. nil — максимум или станции нет.
    static func paybackDays(_ id: String, level: Int, _ cfg: YardConfig = .shared) -> Double? {
        guard let st = cfg.station(id), let price = st.price(toLevel: level + 1) else { return nil }
        let gain = st.rate(level + 1) - st.rate(level)
        return gain > 0 ? Double(price) / Double(gain) / 24 : nil
    }

    /// Все станции на максимуме: стоимость (постройка + улучшения) и ставка.
    static func totalStationCost(_ cfg: YardConfig = .shared) -> Int { cfg.stations.reduce(0) { $0 + $1.prices.reduce(0, +) } }
    static func maxRate(_ cfg: YardConfig = .shared) -> Int { cfg.stations.reduce(0) { $0 + ($1.rates.last ?? 0) } }

    // MARK: SaveFile

    /// Пёс-помощник по сейву: взрослый (Growth.perks), жив, дома (не в походе и не сбежал), станции есть.
    static func helper(_ f: SaveFile, _ cfg: YardConfig = .shared) -> YardHelper? {
        let pct = Growth.perks(f).stationBonusPct
        guard pct > 0, f.pet.alive, f.pet.outing == nil, let id = helperStation(f.yard, cfg) else { return nil }
        return YardHelper(station: id, pct: pct)
    }

    /// Ставка, заполненность и «полная к» по сейву — для экрана двора и бейджа (с помощником).
    static func rate(_ f: SaveFile, dogLevel: Int, _ cfg: YardConfig = .shared) -> Double {
        rate(f.yard, dogLevel: dogLevel, helper: helper(f, cfg), cfg)
    }
    static func fill(_ f: SaveFile, now: Double, dogLevel: Int, _ cfg: YardConfig = .shared) -> Double {
        fill(f.yard, now: now, dogLevel: dogLevel, helper: helper(f, cfg), cfg)
    }
    static func fullAt(_ f: SaveFile, now: Double, dogLevel: Int, _ cfg: YardConfig = .shared) -> Double? {
        fullAt(f.yard, now: now, dogLevel: dogLevel, helper: helper(f, cfg), cfg)
    }
    static func peek(_ f: SaveFile, now: Double, dogLevel: Int, _ cfg: YardConfig = .shared) -> YardState {
        peek(f.yard, now: now, dogLevel: dogLevel, helper: helper(f, cfg), cfg)
    }

    /// Купить плиту из кошелька: уровни линий дома — из сейва, уровень пса — параметром.
    @discardableResult
    static func buyPlate(_ id: String, in f: inout SaveFile, now: Double, dogLevel: Int,
                         _ cfg: YardConfig = .shared) -> YardBuyResult {
        var coins = f.econ.wallet.coins
        let r = buyPlate(id, &f.yard, coins: &coins, now: now, yardLevel: HomeShop.level(f, .yard),
                         dogLevel: dogLevel, kitchenLevel: HomeShop.level(f, .kitchen), helper: helper(f, cfg), cfg)
        if case .ok(let price) = r {
            f.econ.wallet.coins = coins
            f.log("yard.buy", t: now, key: id, value: price)
        }
        return r
    }

    /// Улучшить станцию из кошелька.
    @discardableResult
    static func upgrade(_ id: String, in f: inout SaveFile, now: Double, dogLevel: Int,
                        _ cfg: YardConfig = .shared) -> YardBuyResult {
        var coins = f.econ.wallet.coins
        let r = upgrade(id, &f.yard, coins: &coins, now: now, dogLevel: dogLevel, helper: helper(f, cfg), cfg)
        if case .upgraded(let lv, _) = r {
            f.econ.wallet.coins = coins
            f.log("yard.up", t: now, key: id, value: lv)
        }
        return r
    }

    /// Собрать копилку в кошелёк; порции — в запас кухни до её вместимости, лишнее ждёт в larder.
    /// Журнал yard.collect (value — монеты) — по нему уровень пса даёт опыт за сбор.
    @discardableResult
    static func collect(in f: inout SaveFile, now: Double, dogLevel: Int, _ cfg: YardConfig = .shared) -> YardHarvest {
        let h = collect(&f.yard, now: now, dogLevel: dogLevel, helper: helper(f, cfg), cfg)
        f.yard.larder += h.pantry
        if f.yard.larder > 0 {
            // Запас кладём в «сейчас»: прошлое ядро досчитает по старому запасу (как покупка дома).
            PetRunner.catchUp(&f, now: now)
            let room = max(0, Double(Cooking.pantryCap(f.pet)) - f.pet.pantry)
            let put = min(room, f.yard.larder)
            f.pet.pantry += put
            f.yard.larder -= put
        }
        guard !h.isEmpty else { return h }
        Economy.grant(&f, coins: h.coins, tickets: h.tickets)
        f.log("yard.collect", t: now, key: h.tip == .none ? nil : h.tip.rawValue, value: h.coins)
        return h
    }
}
