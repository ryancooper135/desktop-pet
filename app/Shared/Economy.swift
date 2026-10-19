// Экономика: кошелёк (монеты, билетики, клочки), доход за уход и шаги, дневные потолки.
// Только игровые монеты — реальных денег и покупок в приложении нет.
// Цифры из config/economy.json (currency, income.care, income.habits, capsule). Нет ключа — безопасный дефолт.
//
// Начисление идемпотентное: приложение, виджет и интенты пишут один state.json, а платим мы по журналу.
// Каждое действие act.* оплачивается один раз — по номеру записи (paidSeq), а не по факту вызова.

import Foundation
@preconcurrency import PetCore

// MARK: - Редкости

enum Rarity: String, CaseIterable, Codable, Comparable, Sendable {
    case common, rare, epic, legendary

    var rank: Int {
        switch self {
        case .common: return 0
        case .rare: return 1
        case .epic: return 2
        case .legendary: return 3
        }
    }

    static func < (a: Rarity, b: Rarity) -> Bool { a.rank < b.rank }
}

/// Имя редкости, «собачье» имя для выставки и цвет капсулы.
struct RarityInfo: Hashable, Sendable {
    var name: String
    var dogShow: String
    var color: String
}

/// Предмет из капсулы.
struct CapsuleItem: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let rarity: Rarity
}

// MARK: - Конфиг

struct CapsuleConfig: Hashable, Sendable {
    var name = "Автомат «Шарик»"
    var priceTickets = 1
    var priceCoins = 120
    /// Каждая следующая крутка за монеты в те же сутки дороже на столько.
    var coinsStep = 40
    var maxCoinPulls = 10
    var odds: [Rarity: Int] = [.common: 70, .rare: 22, .epic: 7, .legendary: 1]
    var epicEvery = 15
    var legendaryEvery = 60
    /// С какого значения стартуют счётчики гаранта (вложенный прогресс: «3/15» с первого дня).
    var pityStart = 3
    var duplicateShards: [Rarity: Int] = [.common: 5, .rare: 15, .epic: 50, .legendary: 150]
    var pools: [Rarity: [CapsuleItem]] = CapsuleConfig.stubPools

    /// Заглушки, пока в economy.json нет capsule.pools. Тема — «осень».
    /// Старые id не переименовывать: по ним лежат вещи в сейвах. Новые — только в конец списка редкости.
    /// Роль каждой вещи (надеть / на полку / играть) — ItemCatalog.
    static let stubPools: [Rarity: [CapsuleItem]] = [
        .common: [
            CapsuleItem(id: "bandana_red", name: "Красная бандана", rarity: .common),
            CapsuleItem(id: "bow_blue", name: "Синий бантик", rarity: .common),
            CapsuleItem(id: "leaf_hat", name: "Шапочка-листик", rarity: .common),
            CapsuleItem(id: "bowl_plain", name: "Простая миска", rarity: .common),
            CapsuleItem(id: "mat_check", name: "Клетчатый коврик", rarity: .common),
            // волна 11
            CapsuleItem(id: "bell_collar", name: "Ошейник с бубенчиком", rarity: .common),
            CapsuleItem(id: "pumpkin_small", name: "Тыковка", rarity: .common),
            CapsuleItem(id: "ball_tennis", name: "Теннисный мячик", rarity: .common),
        ],
        .rare: [
            CapsuleItem(id: "scarf_knit", name: "Вязаный шарф", rarity: .rare),
            CapsuleItem(id: "collar_star", name: "Ошейник со звёздами", rarity: .rare),
            CapsuleItem(id: "lamp_mushroom", name: "Лампа-грибок", rarity: .rare),
            CapsuleItem(id: "raincoat", name: "Жёлтый дождевик", rarity: .rare),
            CapsuleItem(id: "beret_red", name: "Берет художника", rarity: .rare),
            CapsuleItem(id: "bowtie_dots", name: "Бабочка в горошек", rarity: .rare),
            CapsuleItem(id: "acorn_jar", name: "Банка желудей", rarity: .rare),
            CapsuleItem(id: "ball_pumpkin", name: "Мяч-тыковка", rarity: .rare),
        ],
        .epic: [
            CapsuleItem(id: "hoodie_pumpkin", name: "Толстовка-тыква", rarity: .epic),
            CapsuleItem(id: "sofa_mini", name: "Мини-диван", rarity: .epic),
            CapsuleItem(id: "backpack_mini", name: "Рюкзачок-жёлудь", rarity: .epic),
            CapsuleItem(id: "wreath_autumn", name: "Венок из листьев", rarity: .epic),
            CapsuleItem(id: "trophy_cup", name: "Кубок выставки", rarity: .epic),
            CapsuleItem(id: "ball_star", name: "Звёздный мяч", rarity: .epic),
        ],
        .legendary: [
            CapsuleItem(id: "cape_champion", name: "Плащ чемпиона", rarity: .legendary),
            CapsuleItem(id: "kennel_castle", name: "Будка-замок", rarity: .legendary),
            CapsuleItem(id: "crown_champion", name: "Корона чемпиона", rarity: .legendary),
        ],
    ]

    /// Все предметы пулов по id — для инвентаря.
    var itemsById: [String: CapsuleItem] {
        var out: [String: CapsuleItem] = [:]
        for list in pools.values { for it in list { out[it.id] = it } }
        return out
    }
}

struct EconomyConfig: Hashable, Sendable {
    var coinsStart = 150
    var ticketsStart = 1
    var shardsStart = 0
    var rarities: [Rarity: RarityInfo] = [
        .common: RarityInfo(name: "Обычная", dogShow: "Дворовая", color: "#9AA0A6"),
        .rare: RarityInfo(name: "Редкая", dogShow: "Породистая", color: "#3D8BEA"),
        .epic: RarityInfo(name: "Эпическая", dogShow: "Выставочная", color: "#A35BE0"),
        .legendary: RarityInfo(name: "Легендарная", dogShow: "Чемпионская", color: "#F2B01E"),
    ]
    /// Монеты за удачное действие ухода: тип act.* → монеты. Нет типа — 0.
    var careCoins: [String: Int] = [:]
    /// Потолок монет за уход в местные сутки.
    var careDailyCap = 0
    var stepsPerCoin = 250
    var stepsCap = 40
    /// Общий потолок привычек в сутки (шаги и будущие duolingo/сон/тренировка).
    var habitsCap = 70
    var capsule = CapsuleConfig()

    static let shared = EconomyConfig(json: Catalog.economy() ?? .null)

    init() {}

    init(json e: JSONValue) {
        func int(_ v: JSONValue, _ d: Int) -> Int { v.double.map { Int($0) } ?? d }
        let cur = e["currency"]
        coinsStart = int(cur["coins"]["start"], coinsStart)
        ticketsStart = int(cur["tickets"]["start"], ticketsStart)
        shardsStart = int(cur["shards"]["start"], shardsStart)

        for it in e["rarities"].array {
            guard let id = it["id"].string, let r = Rarity(rawValue: id) else { continue }
            let old = rarities[r]
            rarities[r] = RarityInfo(name: it["name"].string ?? old?.name ?? id,
                                     dogShow: it["dog_show"].string ?? old?.dogShow ?? id,
                                     color: it["color"].string ?? old?.color ?? "#9AA0A6")
        }

        let care = e["income"]["care"]
        for (k, v) in care["coins"].object { if let n = v.double { careCoins[k] = Int(n) } }
        careDailyCap = int(care["daily_cap"], careDailyCap)

        let habits = e["income"]["habits"]
        habitsCap = int(habits["daily_cap"], habitsCap)
        stepsPerCoin = max(1, int(habits["steps"]["coins_per_steps"], stepsPerCoin))
        stepsCap = int(habits["steps"]["cap"], stepsCap)

        let c = e["capsule"]
        if let n = c["name"].string { capsule.name = n }
        capsule.priceTickets = int(c["price"]["tickets"], capsule.priceTickets)
        capsule.priceCoins = int(c["price"]["or_coins"], capsule.priceCoins)
        capsule.coinsStep = int(c["price"]["coins_step_per_pull_today"], capsule.coinsStep)
        capsule.maxCoinPulls = int(c["price"]["max_coin_pulls_per_day"], capsule.maxCoinPulls)
        for r in Rarity.allCases {
            if let w = c["odds"][r.rawValue].double { capsule.odds[r] = Int(w) }
            if let s = c["duplicate_to_shards"][r.rawValue].double { capsule.duplicateShards[r] = Int(s) }
            let pool = c["pools"][r.rawValue].array.compactMap { (it: JSONValue) -> CapsuleItem? in
                guard let id = it["id"].string else { return nil }
                return CapsuleItem(id: id, name: it["name"].string ?? id, rarity: r)
            }
            if !pool.isEmpty { capsule.pools[r] = pool }
        }
        capsule.epicEvery = max(1, int(c["pity"]["epic_every"], capsule.epicEvery))
        capsule.legendaryEvery = max(1, int(c["pity"]["legendary_every"], capsule.legendaryEvery))
        capsule.pityStart = max(0, int(c["pity"]["start_counter"], capsule.pityStart))
    }

    func rarity(_ r: Rarity) -> RarityInfo {
        rarities[r] ?? RarityInfo(name: r.rawValue, dogShow: r.rawValue, color: "#9AA0A6")
    }
}

// MARK: - Состояние в SaveFile

/// Одно начисление: за какую запись журнала, сколько, упёрлось ли в потолок.
struct Earning: Codable, Hashable, Sendable {
    let id: String       // id записи журнала
    let kind: String     // тип действия: feed, pet, steps…
    let coins: Int
    let capped: Bool     // хотели больше, но дневной потолок
    let t: Double
}

/// Поле econ в state.json. Все вложенные поля читаются через decodeIfPresent.
struct Econ: Codable, Hashable, Sendable {
    struct Wallet: Codable, Hashable, Sendable {
        var coins = 0
        var tickets = 0
        var shards = 0

        init(coins: Int = 0, tickets: Int = 0, shards: Int = 0) {
            self.coins = coins; self.tickets = tickets; self.shards = shards
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            coins = (try? c.decodeIfPresent(Int.self, forKey: .coins)) ?? 0
            tickets = (try? c.decodeIfPresent(Int.self, forKey: .tickets)) ?? 0
            shards = (try? c.decodeIfPresent(Int.self, forKey: .shards)) ?? 0
        }
    }

    /// Счётчики местных суток. day — номер суток (DayKey).
    struct Daily: Codable, Hashable, Sendable {
        var day = 0
        var care = 0         // монет за уход
        var steps = 0        // шагов засчитано
        var stepsCoins = 0   // монет за шаги
        var habits = 0       // монет за привычки всего (потолок habits.daily_cap)
        var coinPulls = 0    // круток капсулы за монеты

        init(day: Int = 0) { self.day = day }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            day = (try? c.decodeIfPresent(Int.self, forKey: .day)) ?? 0
            care = (try? c.decodeIfPresent(Int.self, forKey: .care)) ?? 0
            steps = (try? c.decodeIfPresent(Int.self, forKey: .steps)) ?? 0
            stepsCoins = (try? c.decodeIfPresent(Int.self, forKey: .stepsCoins)) ?? 0
            habits = (try? c.decodeIfPresent(Int.self, forKey: .habits)) ?? 0
            coinPulls = (try? c.decodeIfPresent(Int.self, forKey: .coinPulls)) ?? 0
        }
    }

    /// Капсула: всего круток и счётчики гаранта (сколько круток подряд без эпической / легендарной).
    struct CapsuleState: Codable, Hashable, Sendable {
        var pulls = 0
        var pityEpic = 0
        var pityLegendary = 0

        init(pulls: Int = 0, pityEpic: Int = 0, pityLegendary: Int = 0) {
            self.pulls = pulls; self.pityEpic = pityEpic; self.pityLegendary = pityLegendary
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pulls = (try? c.decodeIfPresent(Int.self, forKey: .pulls)) ?? 0
            pityEpic = (try? c.decodeIfPresent(Int.self, forKey: .pityEpic)) ?? 0
            pityLegendary = (try? c.decodeIfPresent(Int.self, forKey: .pityLegendary)) ?? 0
        }
    }

    var wallet = Wallet()
    /// Последний оплаченный номер записи журнала этого устройства.
    var paidSeq = 0
    var daily = Daily()
    var capsule = CapsuleState()
    /// Инвентарь: id предмета → 1. Дубликаты сразу уходят в клочки.
    var items: [String: Int] = [:]
    /// Последнее начисление — для тоста «+5 монет» в приложении.
    var lastEarn: Earning?

    init() {}

    /// Стартовый кошелёк из currency.*.start, гарант — со start_counter.
    static func start(_ cfg: EconomyConfig = .shared, paidSeq: Int) -> Econ {
        var e = Econ()
        e.wallet = Wallet(coins: cfg.coinsStart, tickets: cfg.ticketsStart, shards: cfg.shardsStart)
        e.paidSeq = paidSeq
        e.capsule = CapsuleState(pulls: 0, pityEpic: cfg.capsule.pityStart, pityLegendary: cfg.capsule.pityStart)
        return e
    }

    /// Новый щенок: кошелёк, предметы и гарант остаются (death.keep), журнал и подсказки — заново.
    func carriedOver() -> Econ {
        var e = self
        e.paidSeq = 0
        e.lastEarn = nil
        return e
    }

    enum CodingKeys: String, CodingKey { case wallet, paidSeq, daily, capsule, items, lastEarn }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let cfg = EconomyConfig.shared
        wallet = (try? c.decodeIfPresent(Wallet.self, forKey: .wallet))
            ?? Wallet(coins: cfg.coinsStart, tickets: cfg.ticketsStart, shards: cfg.shardsStart)
        // Нет номера — помечаем -1, SaveFile подставит текущий seq: битый файл не оплачивает журнал задним числом.
        paidSeq = (try? c.decodeIfPresent(Int.self, forKey: .paidSeq)) ?? -1
        daily = (try? c.decodeIfPresent(Daily.self, forKey: .daily)) ?? Daily()
        capsule = (try? c.decodeIfPresent(CapsuleState.self, forKey: .capsule))
            ?? CapsuleState(pulls: 0, pityEpic: cfg.capsule.pityStart, pityLegendary: cfg.capsule.pityStart)
        items = (try? c.decodeIfPresent([String: Int].self, forKey: .items)) ?? [:]
        lastEarn = try? c.decodeIfPresent(Earning.self, forKey: .lastEarn)
    }
}

// MARK: - Начисление и траты

enum Economy {
    /// Сменились сутки — дневные счётчики с нуля. Назад не откатываемся (переведённые часы не дают второй потолок).
    static func rollDay(_ e: inout Econ, day: Int) {
        guard day > e.daily.day else { return }
        e.daily = Econ.Daily(day: day)
    }

    /// Оплатить все ещё не оплаченные записи журнала этого устройства. Повторный вызов ничего не добавляет.
    @discardableResult
    static func settle(_ f: inout SaveFile, _ cfg: EconomyConfig = .shared) -> [Earning] {
        let prefix = "\(f.deviceId):"
        var out: [Earning] = []
        for e in f.journal {
            guard e.id.hasPrefix(prefix), let s = Int(e.id.dropFirst(prefix.count)), s > f.econ.paidSeq else { continue }
            f.econ.paidSeq = s
            guard e.ok == true, e.kind.hasPrefix("act.") else { continue }
            rollDay(&f.econ, day: DayKey.of(e.t))
            if let earn = pay(&f.econ, entry: e, kind: String(e.kind.dropFirst(4)), cfg) { out.append(earn) }
        }
        if let last = out.last { f.econ.lastEarn = last }
        return out
    }

    private static func pay(_ econ: inout Econ, entry e: JournalEntry, kind: String, _ cfg: EconomyConfig) -> Earning? {
        if kind == "steps" {
            econ.daily.steps += max(0, e.value ?? 0)
            let total = min(cfg.stepsCap, econ.daily.steps / cfg.stepsPerCoin)
            let want = max(0, total - econ.daily.stepsCoins)
            guard want > 0 else { return nil }
            let got = min(want, max(0, cfg.habitsCap - econ.daily.habits))
            econ.daily.stepsCoins += got
            econ.daily.habits += got
            econ.wallet.coins += got
            return Earning(id: e.id, kind: kind, coins: got, capped: got < want, t: e.t)
        }
        let want = cfg.careCoins[kind] ?? 0
        guard want > 0 else { return nil }
        let got = min(want, max(0, cfg.careDailyCap - econ.daily.care))
        econ.daily.care += got
        econ.wallet.coins += got
        return Earning(id: e.id, kind: kind, coins: got, capped: got < want, t: e.t)
    }

    /// Сколько монет за уход ещё можно получить сегодня.
    static func careLeftToday(_ f: SaveFile, at t: Double, _ cfg: EconomyConfig = .shared) -> Int {
        let used = DayKey.today(f.econ.daily.care, day: f.econ.daily.day, at: t)
        return max(0, cfg.careDailyCap - used)
    }

    static func canAfford(_ f: SaveFile, coins: Int) -> Bool { f.econ.wallet.coins >= max(0, coins) }

    /// Списать монеты. Не хватает — ничего не меняет и возвращает false.
    @discardableResult
    static func spend(_ f: inout SaveFile, coins: Int) -> Bool {
        guard coins >= 0, f.econ.wallet.coins >= coins else { return false }
        f.econ.wallet.coins -= coins
        return true
    }

    /// Подарок: награды квестов, вех, отладка.
    static func grant(_ f: inout SaveFile, coins: Int = 0, tickets: Int = 0, shards: Int = 0) {
        f.econ.wallet.coins += max(0, coins)
        f.econ.wallet.tickets += max(0, tickets)
        f.econ.wallet.shards += max(0, shards)
    }
}

// MARK: - Тексты

/// Строки экономики из lines.json (раздел ui, ключи econ_* и capsule_*) и формы слов.
enum EconText {
    /// Все ключи, которые читает код, — тест проверяет, что они есть в lines.json.
    static let keys = [
        "econ_coin_one", "econ_coin_few", "econ_coin_many",
        "econ_ticket_one", "econ_ticket_few", "econ_ticket_many",
        "econ_shard_one", "econ_shard_few", "econ_shard_many",
        "econ_earned", "econ_cap_reached", "econ_not_enough", "econ_no_tickets",
        "capsule_pull", "capsule_price_coins", "capsule_price_ticket", "capsule_limit",
        "capsule_pity", "capsule_pity_ready", "capsule_got", "capsule_new", "capsule_duplicate", "capsule_tap",
    ] + Rarity.allCases.flatMap { ["capsule_rarity_\($0.rawValue)", "capsule_show_\($0.rawValue)"] }

    /// Строка раздела ui с подстановками. Нет строки — сам ключ (тест этого не допускает).
    static func ui(_ key: String, _ vars: [String: String] = [:], lines: Lines = .shared) -> String {
        let raw = lines.sections["ui"]?[key]?.first?.text ?? key
        return Lines.fill(raw, vars)
    }

    /// Русская форма по числу: 1 монета, 2 монеты, 5 монет, 11 монет, 21 монета.
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let a = abs(n) % 100, b = a % 10
        if (11...14).contains(a) { return many }
        if b == 1 { return one }
        if (2...4).contains(b) { return few }
        return many
    }

    /// «3 раза», «5 раз», «21 раз» — для {times} в строках («Поймал {times} подряд!»).
    static func times(_ n: Int) -> String { "\(n) \(plural(n, "раз", "раза", "раз"))" }
    /// «1 день», «3 дня», «21 день» — для {days} в строках («Мы вместе уже {days}.»).
    static func days(_ n: Int) -> String { "\(n) \(plural(n, "день", "дня", "дней"))" }
    /// «1 очко», «3 очка», «5 очков».
    static func points(_ n: Int) -> String { "\(n) \(plural(n, "очко", "очка", "очков"))" }

    /// Название после двоеточия с маленькой буквы: «Угощение: морковка». Имя в именительном падеже
    /// после двоеточия читается естественно, а склонять названия из данных не нужно (волна 17).
    static func lowerFirst(_ s: String) -> String {
        guard let c = s.first else { return s }
        return c.lowercased() + s.dropFirst()
    }

    static func word(_ base: String, _ n: Int, lines: Lines = .shared) -> String {
        plural(n, ui("\(base)_one", lines: lines), ui("\(base)_few", lines: lines), ui("\(base)_many", lines: lines))
    }

    /// «5 монет», «1 билетик», «22 клочка».
    static func coins(_ n: Int, lines: Lines = .shared) -> String { "\(n) \(word("econ_coin", n, lines: lines))" }
    static func tickets(_ n: Int, lines: Lines = .shared) -> String { "\(n) \(word("econ_ticket", n, lines: lines))" }
    static func shards(_ n: Int, lines: Lines = .shared) -> String { "\(n) \(word("econ_shard", n, lines: lines))" }
    /// Кошелёк одной фразой для VoiceOver: «150 монет, 1 билетик».
    static func wallet(coins c: Int, tickets t: Int, lines: Lines = .shared) -> String {
        "\(coins(c, lines: lines)), \(tickets(t, lines: lines))"
    }

    /// Тост после действия: «+5 монет» или «На сегодня монет за заботу хватит». nil — показывать нечего.
    static func toast(_ e: Earning, lines: Lines = .shared) -> String? {
        if e.coins > 0 {
            return ui("econ_earned", ["count": "\(e.coins)", "coins": word("econ_coin", e.coins, lines: lines)], lines: lines)
        }
        return e.capped ? ui("econ_cap_reached", lines: lines) : nil
    }

    /// «Не хватает монет: 35».
    static func notEnough(need: Int, lines: Lines = .shared) -> String {
        ui("econ_not_enough", ["count": "\(need)"], lines: lines)
    }

    static func rarityName(_ r: Rarity, lines: Lines = .shared) -> String { ui("capsule_rarity_\(r.rawValue)", lines: lines) }
    static func rarityShowName(_ r: Rarity, lines: Lines = .shared) -> String { ui("capsule_show_\(r.rawValue)", lines: lines) }
}
