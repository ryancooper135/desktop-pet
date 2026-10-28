// Волна 40 F: времена года в мире. Три вещи, и все — косметика или сток клочков ✂️:
// 1. Сезонный акцент в комнате и во дворе — бесплатно и сам: зимой снеговик, весной тюльпаны, летом подсолнух,
//    осенью тыква с листьями (3D — app/App/SeasonDecor.swift, матовое, ночью гаснет вместе со всем).
// 2. Сезонные вещи за ✂️ — по две на сезон (одна на пса, одна на полку). Продаются в Мастерской только в свой
//    сезон, купленное остаётся навсегда. Польза маленькая (как у редкой вещи, 5 %) и никогда не в доход.
// 3. Реплики о сезоне — редкие, свой ход PetMind после погоды (SeasonTalk).
// Сезон — тот же Season, что у погоды (Weather.swift: по месяцу, северное полушарие). Под тестами — осень,
// чтобы снимки, Мастерская и строки не зависели от даты прогона; PET_SEASON и pinned — для снимков и отладки.
// Доход, нужды и опыт не трогает. Цены — SeasonConfig (раздел seasons в config/economy.json), DECISIONS.md, волна 40 F.

import Foundation
@preconcurrency import PetCore

/// Сезонная вещь: продаётся только в свой сезон, дальше лежит в коллекции как обычная.
struct SeasonItem: Hashable, Sendable {
    let id: String
    let name: String
    let season: Season
    let emoji: String
    let perk: PerkKind
    /// true — надевается (Wear), false — на полку (ItemCatalog.decor).
    let wear: Bool

    /// Редкость в коллекции: польза как у редкой вещи (5 %) — меньше, чем у лоскутных и вещей мест (8 %).
    static let rarity = Rarity.rare

    var item: CapsuleItem { CapsuleItem(id: id, name: name, rarity: Self.rarity) }
}

/// Почему не купили.
enum SeasonRefusal: Error, Hashable, Sendable {
    case notEnough(need: Int)   // сколько клочков не хватает
    case offSeason(Season)      // продаётся только в этот сезон
    case owned                  // уже есть
    case unknown                // такой сезонной вещи нет
}

/// Цифры сезонов. Умолчания — здесь, файл (economy.json → seasons) их переопределяет; тест сверяет одно с другим.
struct SeasonConfig: Hashable, Sendable {
    /// Цена вещи на пса, ✂️. Между золотым шариком (50, случайная редкая) и эксклюзивом места (120, эпическая).
    var wearPrice = 90
    /// Цена вещи на полку, ✂️. Чуть дешевле: её видно только дома.
    var decorPrice = 70
    /// Реплика о сезоне — в одном из talkOneIn своих ходов PetMind: ход выпадает раз в 8 слотов по 2 часа,
    /// значит, в среднем раз в 8 × 3 × 2 = 48 часов.
    var talkOneIn = 3

    static let shared = SeasonConfig(json: Catalog.economy() ?? .null)

    init() {}

    init(json e: JSONValue) {
        func int(_ v: JSONValue, _ d: Int) -> Int { v.double.map { Int($0) } ?? d }
        let s = e["seasons"]
        wearPrice = max(1, int(s["price"]["wear"], wearPrice))
        decorPrice = max(1, int(s["price"]["decor"], decorPrice))
        talkOneIn = min(max(int(s["talk_one_in"], talkOneIn), 1), 24)
    }

    func price(_ it: SeasonItem) -> Int { it.wear ? wearPrice : decorPrice }
}

enum Seasons {
    // MARK: какой сейчас сезон

    /// Закреплённый сезон (для превью и снимков). В файл не пишется, живёт до перезапуска.
    nonisolated(unsafe) static var pinned: Season?

    /// PET_SEASON=<winter|spring|summer|autumn> — сезон для снимков и UI-тестов (и для отладки на телефоне).
    static let forced: Season? = Env.value("PET_SEASON").flatMap(Season.init(rawValue:))

    /// Сезон под тестами без закрепления: осень (капсула и так «осенняя», декор с тыквой проверен глазами).
    static let testSeason = Season.autumn

    /// Сезон для показа и продажи: закреплённый, из PET_SEASON, под тестами — осень, иначе по местной дате.
    static func shown(at t: Double, tzOffsetMin: Int) -> Season {
        if let p = pinned { return p }
        if let f = forced { return f }
        if Weather.underTest { return testSeason }
        return Season(day: DayKey.of(t, tzOffsetMin: tzOffsetMin))
    }

    static func now() -> Season {
        let t = Clock.now()
        return shown(at: t, tzOffsetMin: Clock.tzOffsetMin(at: t))
    }

    /// Сезон для реплик. Под тестами без закрепления — молчим (как погода: под тестами ясно и без слов),
    /// чтобы строки пузыря в старых тестах не зависели от сезона.
    static func talking(at t: Double, tzOffsetMin: Int) -> Season? {
        if pinned == nil && forced == nil && Weather.underTest { return nil }
        return shown(at: t, tzOffsetMin: tzOffsetMin)
    }

    // MARK: вещи

    /// По две вещи на сезон. Id не переименовывать: лежат в сейвах.
    static let all: [SeasonItem] = [
        SeasonItem(id: "season_pompom_hat", name: "Шапка с помпоном", season: .winter, emoji: "🧶", perk: .love, wear: true),
        SeasonItem(id: "season_snow_globe", name: "Снежный шар", season: .winter, emoji: "🔮", perk: .sleep, wear: false),
        SeasonItem(id: "season_dandelion_wreath", name: "Венок из одуванчиков", season: .spring, emoji: "🌼", perk: .fun, wear: true),
        SeasonItem(id: "season_tulip_pot", name: "Тюльпаны в горшке", season: .spring, emoji: "🌷", perk: .clean, wear: false),
        SeasonItem(id: "season_sun_bandana", name: "Бандана с солнцем", season: .summer, emoji: "☀️", perk: .clean, wear: true),
        SeasonItem(id: "season_sand_bucket", name: "Ведёрко с ракушкой", season: .summer, emoji: "🪣", perk: .fun, wear: false),
        SeasonItem(id: "season_leaf_scarf", name: "Шарф-листопад", season: .autumn, emoji: "🍁", perk: .love, wear: true),
        SeasonItem(id: "season_mushroom_basket", name: "Корзинка грибов", season: .autumn, emoji: "🍄", perk: .food, wear: false),
    ]

    /// Как предметы коллекции — уходят в capsule.exclusive (не в пулы: в капсуле, лавке и ателье их нет).
    static let items: [CapsuleItem] = all.map(\.item)
    static let perks: [String: PerkKind] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.perk) })
    static let emoji: [String: String] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.emoji) })

    /// Надеваемое: шапка — на голову, венок — на голову, бандана и шарф — на шею. Фигуры — готовые.
    static let wear: [String: WearInfo] = [
        "season_pompom_hat": WearInfo(slot: .head, shape: .genericHat, color: 0xF2EEE6, accent: 0xD9483F),
        "season_dandelion_wreath": WearInfo(slot: .head, shape: .wreath, color: 0xF2CF3A, accent: 0x6FAE4E),
        "season_sun_bandana": WearInfo(slot: .neck, shape: .bandana, color: 0x3FA7D6, accent: 0xF5C542),
        "season_leaf_scarf": WearInfo(slot: .neck, shape: .scarf, color: 0xD9772E, accent: 0x9C3B2A),
    ]

    /// На полку — остальное.
    static let decor: Set<String> = Set(all.filter { !$0.wear }.map(\.id))

    static func item(_ id: String) -> SeasonItem? { all.first { $0.id == id } }
    static func items(of s: Season) -> [SeasonItem] { all.filter { $0.season == s } }

    // MARK: покупка

    /// Купить сезонную вещь в сезон season. Порядок отказов: нет такой → уже есть → не сезон → не хватает.
    /// В журнал — season.buy (key — id вещи, value — цена).
    static func buy(_ id: String, in f: inout SaveFile, season: Season, now: Double,
                    _ cfg: SeasonConfig = .shared) -> Result<CapsuleItem, SeasonRefusal> {
        guard let it = item(id) else { return .failure(.unknown) }
        if f.econ.items[id] != nil { return .failure(.owned) }
        guard it.season == season else { return .failure(.offSeason(it.season)) }
        let price = cfg.price(it)
        guard Shards.spend(&f, price) else { return .failure(.notEnough(need: price - f.econ.wallet.shards)) }
        f.econ.items[id] = 1
        f.log("season.buy", t: now, key: id, value: price)
        return .success(it.item)
    }

    /// Через стор: одна запись под замком, сезон — на момент покупки.
    static func perform(_ id: String, store: PetStore = .shared,
                        now: Double = Clock.now()) throws -> Result<CapsuleItem, SeasonRefusal> {
        let season = shown(at: now, tzOffsetMin: Clock.tzOffsetMin(at: now))
        return try store.mutate { f in buy(id, in: &f, season: season, now: now) }
    }

    // MARK: Мастерская

    /// Карточки сезона для Мастерской: вещи этого сезона, сначала на пса, потом на полку.
    static func offers(_ f: SaveFile, season: Season, _ cfg: SeasonConfig = .shared) -> [ShardOffer] {
        let have = f.econ.wallet.shards
        return items(of: season).sorted { $0.wear && !$1.wear }.map { it in
            let price = cfg.price(it)
            return ShardOffer(kind: .season(it.id), title: it.name,
                              note: ItemPerks.line(it.id) ?? "Только \(when(season))",
                              price: price, rarity: SeasonItem.rarity,
                              state: f.econ.items[it.id] != nil ? .owned : .buy(need: max(0, price - have)))
        }
    }

    // MARK: тексты

    /// «зимой», «весной», «летом», «осенью».
    static func when(_ s: Season) -> String {
        switch s {
        case .winter: return "зимой"
        case .spring: return "весной"
        case .summer: return "летом"
        case .autumn: return "осенью"
        }
    }

    /// Заголовок раздела в Мастерской: «🍂 Осеннее — только осенью».
    static func title(_ s: Season) -> String {
        switch s {
        case .winter: return "❄️ Зимнее — только зимой"
        case .spring: return "🌷 Весеннее — только весной"
        case .summer: return "☀️ Летнее — только летом"
        case .autumn: return "🍂 Осеннее — только осенью"
        }
    }

    /// Строка под разделом: купленное остаётся, следующий сезон привезёт своё.
    static func note(_ s: Season) -> String {
        "Купленное остаётся навсегда. \(next(s).title) привезёт свои вещи."
    }

    static func next(_ s: Season) -> Season {
        switch s {
        case .winter: return .spring
        case .spring: return .summer
        case .summer: return .autumn
        case .autumn: return .winter
        }
    }

    static func refusalText(_ r: SeasonRefusal) -> String {
        switch r {
        case .notEnough(let need): return "Не хватает клочков: \(need) ✂️"
        case .offSeason(let s): return "Это продают только \(when(s))"
        case .owned: return "Это уже есть в коллекции"
        case .unknown: return "Такого в мастерской нет"
        }
    }
}

/// Реплика о сезоне вместо обычной в спокойное время: свой ход PetMind сразу после погоды, и то не каждый —
/// один из SeasonConfig.talkOneIn (в среднем раз в двое суток). Ничего не даёт и не отнимает — только слова.
enum SeasonTalk {
    /// Номер хода PetMind, отданного сезону (после воспоминаний, характера и погоды).
    static let turn: UInt64 = WeatherTalk.turn + 1

    /// Ключ реплики в lines.json.
    static func lineKey(_ s: Season) -> String { "season_\(s.rawValue)" }

    /// Сезон говорит в этом слоте: его ход PetMind и свой бросок 1 из talkOneIn.
    static func speaks(_ f: SaveFile, slot: Int, _ cfg: SeasonConfig = .shared) -> Bool {
        guard PetMind.roll(f, slot: slot) == turn else { return false }
        let u = StableRandom.mix(StableHash.fnv1a("\(f.petId):season:\(slot)"))
        return u % UInt64(max(1, cfg.talkOneIn)) == 0
    }

    static func line(_ f: SaveFile, at t: Double, tzOffsetMin: Int, island: Bool = false,
                     season: Season? = nil, lines: Lines = .shared, _ cfg: SeasonConfig = .shared) -> String? {
        let slot = PetMind.slot(t, tzOffsetMin: tzOffsetMin)
        guard speaks(f, slot: slot, cfg) else { return nil }
        guard let s = season ?? Seasons.talking(at: t, tzOffsetMin: tzOffsetMin) else { return nil }
        let max = island ? LineLimit.island : LineLimit.widget
        guard let text = lines.pick(island ? "island" : "widget", lineKey(s), seed: f.petId, slot: slot, maxLen: max)?.text,
              text.count <= max, !text.contains("{") else { return nil }
        return text
    }
}
