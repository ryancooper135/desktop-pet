// Волна 32. ✂️ клочки — редкая игровая валюта, и польза покупок.
// Только игровое: клочки не покупаются за деньги и не меняются на монеты — их зарабатывают заботой.
// Главное правило владельца — дефицит: клочков мало (≈45 в неделю у активного, ≈15 у ленивого, ECONOMY.md).
//
// Источники (Shards.settle, идемпотентно, как Economy.settle):
//   повторки из капсулы (как раньше, Capsule.swift); день заботы — N удачных дел за сутки; сундук недели —
//   M дней заботы с понедельника; рекорд в мини-игре — не чаще раза в сутки; клочок в находке с прогулки;
//   достижения по разу (дни заботы 7/30/100, первое блюдо, первый трюк, новая находка в альбом).
// Стоки: «Ателье» — вещь выбранной редкости, которой ещё нет; лоскутные эксклюзивы (одежда и мебель),
//   которых нет в капсуле и лавке; возврат пса (Shards.reviveCost — цену подключает зона смерти).
// Польза вещей (ItemPerks): маленький бонус у каждой вещи, надетое — пока надето, мебель и игрушки — всегда;
//   сумма по виду с потолком. Сердечки вещи не трогают. Цифры — раздел premium в config/economy.json.

import Foundation
@preconcurrency import PetCore

// MARK: - Конфиг

/// Вид пользы вещи: какую шкалу или доход она трогает.
enum PerkKind: String, CaseIterable, Codable, Sendable {
    case food, clean, fun, love, sleep, coins

    /// Ключ модификатора ядра (_x) или мини-игр.
    var key: String {
        switch self {
        case .food: return "food_decay_x"
        case .clean: return "clean_decay_x"
        case .fun: return "fun_decay_x"
        case .love: return "love_decay_x"
        case .sleep: return "sleep_regen_x"
        case .coins: return CatchGame.buffKey
        }
    }

    /// true — множитель растёт (быстрее, больше), false — шкала тает медленнее.
    var grows: Bool { self == .sleep || self == .coins }

    /// Одна строка пользы: «Голодает на 5% медленнее».
    func text(_ pct: Int) -> String {
        switch self {
        case .food: return "Голодает на \(pct)% медленнее"
        case .clean: return "Пачкается на \(pct)% медленнее"
        case .fun: return "Скучает на \(pct)% медленнее"
        case .love: return "Ласка тает на \(pct)% медленнее"
        case .sleep: return "Высыпается на \(pct)% быстрее"
        case .coins: return "Монет за мини-игры на \(pct)% больше"
        }
    }
}

/// Лоскутная вещь только за клочки: id, имя, цена.
struct ShardExclusive: Hashable, Sendable {
    let id: String
    let name: String
    let price: Int
}

struct PremiumConfig: Hashable, Sendable {
    // источники
    var goalActs = 5
    var goalShards = 3
    var chestDays = 5
    var chestShards = 10
    var recordShards = 2
    var findChancePct = 10
    var findMin = 1
    var findMax = 2
    var newFindKind = 2
    var achievements: [String: Int] = [
        "good_days_7": 5, "good_days_30": 10, "good_days_100": 25, "first_dish": 3, "first_trick": 3,
    ]
    // стоки
    var atelier: [Rarity: Int] = [.rare: 70, .epic: 180, .legendary: 450]
    var exclusives: [ShardExclusive] = PremiumConfig.stubExclusives
    var reviveBase = 30
    var reviveStep = 15
    var reviveMax = 90
    // польза
    var perkPct: [Rarity: Int] = [.common: 3, .rare: 5, .epic: 8, .legendary: 12]
    var perkCapPct = 20
    var perks: [String: PerkKind] = PremiumConfig.stubPerks

    /// Редкость эксклюзивов: польза как у эпической вещи.
    static let exclusiveRarity = Rarity.epic

    static let stubExclusives: [ShardExclusive] = [
        ShardExclusive(id: "pillow_patch", name: "Лоскутная подушка", price: 60),
        ShardExclusive(id: "scarf_patch", name: "Лоскутный шарф", price: 90),
        ShardExclusive(id: "hat_patch", name: "Лоскутная шапочка", price: 120),
        ShardExclusive(id: "armchair_patch", name: "Лоскутное кресло", price: 160),
        ShardExclusive(id: "blanket_patch", name: "Лоскутная попонка", price: 200),
    ]

    /// Вещь → вид пользы. Тест сверяет с premium.perks.items в economy.json.
    static let stubPerks: [String: PerkKind] = [
        "bandana_red": .fun, "bow_blue": .love, "leaf_hat": .clean, "bowl_plain": .food, "mat_check": .clean,
        "bell_collar": .coins, "pumpkin_small": .food, "ball_tennis": .fun,
        "scarf_knit": .love, "collar_star": .coins, "lamp_mushroom": .sleep, "raincoat": .clean,
        "beret_red": .fun, "bowtie_dots": .love, "acorn_jar": .food, "ball_pumpkin": .fun,
        "hoodie_pumpkin": .sleep, "sofa_mini": .sleep, "backpack_mini": .food, "wreath_autumn": .love,
        "trophy_cup": .coins, "ball_star": .fun,
        "cape_champion": .coins, "kennel_castle": .sleep, "crown_champion": .love,
        "pillow_patch": .love, "scarf_patch": .fun, "hat_patch": .clean, "armchair_patch": .food,
        "blanket_patch": .sleep,
    ]

    static let shared = PremiumConfig(json: Catalog.economy() ?? .null)

    init() {}

    init(json e: JSONValue) {
        func int(_ v: JSONValue, _ d: Int) -> Int { v.double.map { Int($0) } ?? d }
        let p = e["premium"]
        let s = p["sources"]
        goalActs = max(1, int(s["care_day"]["acts"], goalActs))
        goalShards = max(0, int(s["care_day"]["shards"], goalShards))
        chestDays = max(1, int(s["week_chest"]["days"], chestDays))
        chestShards = max(0, int(s["week_chest"]["shards"], chestShards))
        recordShards = max(0, int(s["record"]["shards"], recordShards))
        findChancePct = min(100, max(0, int(s["walk_find"]["chance_pct"], findChancePct)))
        findMin = max(0, int(s["walk_find"]["min"], findMin))
        findMax = max(findMin, int(s["walk_find"]["max"], findMax))
        newFindKind = max(0, int(s["new_find_kind"], newFindKind))
        for (k, v) in s["achievements"].object { if let n = v.double { achievements[k] = max(0, Int(n)) } }

        // Ателье — по ценам capsule.atelier_price_shards; обычных там нет: за клочками идут за редким.
        let ap = e["capsule"]["atelier_price_shards"]
        for r in [Rarity.rare, .epic, .legendary] { if let n = ap[r.rawValue].double { atelier[r] = max(1, Int(n)) } }
        let ex = p["sinks"]["exclusives"].array.compactMap { (it: JSONValue) -> ShardExclusive? in
            guard let id = it["id"].string, let price = it["price"].double else { return nil }
            return ShardExclusive(id: id, name: it["name"].string ?? id, price: max(1, Int(price)))
        }
        if !ex.isEmpty { exclusives = ex }
        let rv = p["sinks"]["revive"]
        reviveBase = max(0, int(rv["base"], reviveBase))
        reviveStep = max(0, int(rv["step"], reviveStep))
        reviveMax = max(reviveBase, int(rv["max"], reviveMax))

        let pk = p["perks"]
        for r in Rarity.allCases { if let n = pk["pct"][r.rawValue].double { perkPct[r] = max(0, Int(n)) } }
        perkCapPct = max(0, int(pk["cap_pct"], perkCapPct))
        for (id, v) in pk["items"].object { if let k = v.string.flatMap(PerkKind.init(rawValue:)) { perks[id] = k } }
    }

    func exclusive(_ id: String) -> ShardExclusive? { exclusives.first { $0.id == id } }
}

// MARK: - Польза вещей

enum ItemPerks {
    /// Сила одной вещи в процентах (по редкости).
    static func pct(_ id: String, _ cfg: PremiumConfig = .shared,
                    items: [String: CapsuleItem] = EconomyConfig.shared.capsule.itemsById) -> Int {
        guard cfg.perks[id] != nil, let it = items[id] else { return 0 }
        return cfg.perkPct[it.rarity] ?? 0
    }

    /// Что сейчас работает: надетое — пока надето, остальное своё (мебель, игрушки) — всегда.
    static func activeIds(_ f: SaveFile) -> [String] {
        let worn = Set(Wear.worn(f).values)
        return f.econ.items.keys.filter { Wear.canWear($0) ? worn.contains($0) : true }.sorted()
    }

    /// Сумма по видам в процентах, уже с потолком.
    static func totals(_ f: SaveFile, _ cfg: PremiumConfig = .shared,
                       items: [String: CapsuleItem] = EconomyConfig.shared.capsule.itemsById) -> [PerkKind: Int] {
        var out: [PerkKind: Int] = [:]
        for id in activeIds(f) {
            guard let k = cfg.perks[id] else { continue }
            let p = pct(id, cfg, items: items)
            if p > 0 { out[k, default: 0] += p }
        }
        for (k, v) in out { out[k] = min(v, cfg.perkCapPct) }
        return out
    }

    /// Множитель для ключа ядра: 0,95 — тает на 5% медленнее, 1,05 — на 5% больше.
    static func factor(_ kind: PerkKind, pct: Int) -> Double {
        kind.grows ? 1 + Double(pct) / 100 : 1 - Double(pct) / 100
    }

    /// Строка на карточке вещи: «Скучает на 5% медленнее · пока надето». nil — пользы нет.
    static func line(_ id: String, _ cfg: PremiumConfig = .shared,
                     items: [String: CapsuleItem] = EconomyConfig.shared.capsule.itemsById) -> String? {
        guard let k = cfg.perks[id] else { return nil }
        let p = pct(id, cfg, items: items)
        guard p > 0 else { return nil }
        return Wear.canWear(id) ? "\(k.text(p)) · пока надето" : k.text(p)
    }

    /// Сводка для коллекции: что дают вещи сейчас, «· предел» у упёршихся в потолок.
    static func summary(_ f: SaveFile, _ cfg: PremiumConfig = .shared) -> [String] {
        let t = totals(f, cfg)
        return PerkKind.allCases.compactMap { k in
            guard let p = t[k], p > 0 else { return nil }
            return p >= cfg.perkCapPct ? "\(k.text(p)) · предел" : k.text(p)
        }
    }

    /// Множитель монет мини-игр от вещей (бафф дома — отдельно, CatchGame.coinsX).
    static func coinsX(_ f: SaveFile, _ cfg: PremiumConfig = .shared) -> Double {
        factor(.coins, pct: totals(f, cfg)[.coins] ?? 0)
    }

    /// Модификаторы ядра от вещей (без монет — их читают мини-игры).
    static func mods(_ f: SaveFile, _ cfg: PremiumConfig = .shared) -> [String: Double] {
        var out: [String: Double] = [:]
        for (k, p) in totals(f, cfg) where k != .coins && p > 0 { out[k.key] = factor(k, pct: p) }
        return out
    }

    /// Всё, что меняет ядро: польза вещей × стадия роста (волна 33). trip_time_x — не ядро, его читают походы.
    static func coreMods(_ f: SaveFile) -> [String: Double] {
        var out = mods(f)
        for (k, x) in Growth.mods(f) where k != "trip_time_x" && x != 1 { out[k] = (out[k] ?? 1) * x }
        return out
    }

    // MARK: правила ядра с пользой вещей

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Rules] = [:]

    /// Правила ядра для этого сейва: base, а польза вещей вплетена в баффы кухни (ядро перемножает
    /// все _x по линиям дома, а у кухни бафф есть на каждом уровне, включая нулевой). Без пользы — base.
    static func rules(_ f: SaveFile, base: Rules = Catalog.rules) -> Rules {
        let m = coreMods(f)
        guard !m.isEmpty else { return base }
        let sig = (base.preset ?? "-") + "|" + m.keys.sorted().map { "\($0)=\(m[$0]!)" }.joined(separator: ",")
        lock.lock(); defer { lock.unlock() }
        if let r = cache[sig] { return r }
        guard let raw = Catalog.economy(),
              let r = try? Rules(json: patched(raw, m), preset: base.preset) else { return base }
        if cache.count > 64 { cache.removeAll() }
        cache[sig] = r
        return r
    }

    /// economy.json с модификаторами, домноженными в home_upgrades.kitchen.levels[*].buff.
    static func patched(_ raw: JSONValue, _ m: [String: Double]) -> JSONValue {
        var root = raw.object
        var hu = raw["home_upgrades"].object
        var kitchen = raw["home_upgrades"]["kitchen"].object
        let levels = raw["home_upgrades"]["kitchen"]["levels"].array.map { lv -> JSONValue in
            var o = lv.object
            var buff = lv["buff"].object
            for (k, x) in m { buff[k] = .number((buff[k]?.double ?? 1) * x) }
            o["buff"] = .object(buff)
            return .object(o)
        }
        guard !levels.isEmpty else { return raw }
        kitchen["levels"] = .array(levels)
        hu["kitchen"] = .object(kitchen)
        root["home_upgrades"] = .object(hu)
        return .object(root)
    }
}

// MARK: - Учёт клочков в SaveFile

/// Последнее начисление клочков — для строки «+3 ✂️ за день заботы».
struct ShardGain: Codable, Hashable, Sendable {
    let reason: String   // care_day, week_chest, record, find, new_find, ach.<id>
    let shards: Int
    let t: Double
}

/// Поле shardLog в state.json. Пустое не пишется. Новому щенку переходит (carriedOver): клочки — хозяина.
struct ShardLog: Codable, Hashable, Sendable {
    /// Последний учтённый номер записи журнала этого устройства (-1 — старый сейв: подставится seq).
    var seenSeq = 0
    /// Сутки заботы: номер суток, удачных дел за них, оплачен ли день.
    var day = 0
    var dayActs = 0
    var dayPaid = false
    /// Неделя (с понедельника): номер, дней заботы в ней, оплачен ли сундук.
    var week = 0
    var weekDays = 0
    var chestPaid = false
    /// Дней заботы всего — для достижений.
    var goodDays = 0
    /// Рекорды мини-игр, от которых считаем следующий; nil — ещё не видели (ставится без оплаты).
    var best: [String: Int] = [:]
    /// Сутки, за которые рекорд уже оплачен.
    var recordDay = 0
    /// Находок у этого пса, от которых считаем следующую; -1 — ещё не видели.
    var finds = -1
    /// Разовые награды: ach.<id>, find:<id>.
    var once: [String] = []
    /// Сколько раз было «Ателье» — номер броска.
    var atelier = 0
    /// Всего заработано клочков этими источниками (без повторок) — для статистики.
    var earned = 0
    var last: ShardGain?

    init() {}

    var isEmpty: Bool { self == ShardLog() }

    /// Новый щенок: журнал заново, находки — у нового пса свои. Разовое, рекорды и счётчики остаются.
    func carriedOver() -> ShardLog {
        var s = self
        s.seenSeq = 0
        s.finds = -1
        s.last = nil
        return s
    }

    enum CodingKeys: String, CodingKey {
        case seenSeq, day, dayActs, dayPaid, week, weekDays, chestPaid, goodDays, best, recordDay, finds, once
        case atelier, earned, last
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seenSeq = (try? c.decodeIfPresent(Int.self, forKey: .seenSeq)) ?? -1
        day = (try? c.decodeIfPresent(Int.self, forKey: .day)) ?? 0
        dayActs = (try? c.decodeIfPresent(Int.self, forKey: .dayActs)) ?? 0
        dayPaid = (try? c.decodeIfPresent(Bool.self, forKey: .dayPaid)) ?? false
        week = (try? c.decodeIfPresent(Int.self, forKey: .week)) ?? 0
        weekDays = (try? c.decodeIfPresent(Int.self, forKey: .weekDays)) ?? 0
        chestPaid = (try? c.decodeIfPresent(Bool.self, forKey: .chestPaid)) ?? false
        goodDays = (try? c.decodeIfPresent(Int.self, forKey: .goodDays)) ?? 0
        best = (try? c.decodeIfPresent([String: Int].self, forKey: .best)) ?? [:]
        recordDay = (try? c.decodeIfPresent(Int.self, forKey: .recordDay)) ?? 0
        finds = (try? c.decodeIfPresent(Int.self, forKey: .finds)) ?? -1
        once = (try? c.decodeIfPresent([String].self, forKey: .once)) ?? []
        atelier = (try? c.decodeIfPresent(Int.self, forKey: .atelier)) ?? 0
        earned = (try? c.decodeIfPresent(Int.self, forKey: .earned)) ?? 0
        last = try? c.decodeIfPresent(ShardGain.self, forKey: .last)
    }
}

// MARK: - Начисление и траты

enum ShardRefusal: Error, Hashable, Sendable {
    case notEnough(need: Int)   // сколько не хватает
    case allOwned               // все вещи этой редкости уже есть
    case owned                  // эта вещь уже есть
    case unknown                // нет такой вещи / редкости
}

enum Shards {
    /// Неделя с понедельника: DayKey 0 — четверг.
    static func week(_ day: Int) -> Int { DayKey.floorDiv(day + 3, 7) }

    /// Рекорды мини-игр: имя → поле сейва.
    static func records(_ f: SaveFile) -> [String: Int] {
        ["catch": f.catchBest, "blockduo": f.blockduoBest, "zombie": f.zombieBest]
    }

    /// Оплатить всё новое. Повторный вызов ничего не добавляет. now — для рекордов и находок (их нет в журнале).
    @discardableResult
    static func settle(_ f: inout SaveFile, now: Double, _ cfg: PremiumConfig = .shared) -> [ShardGain] {
        var out: [ShardGain] = []
        var s = f.shardLog
        if s.seenSeq < 0 { s.seenSeq = f.seq }
        func pay(_ reason: String, _ n: Int, _ t: Double) {
            guard n > 0 else { return }
            f.econ.wallet.shards += n
            s.earned += n
            let g = ShardGain(reason: reason, shards: n, t: t)
            s.last = g
            out.append(g)
        }

        // 1. День заботы и сундук недели — по журналу, каждая запись один раз.
        let prefix = "\(f.deviceId):"
        for e in f.journal {
            guard e.id.hasPrefix(prefix), let q = Int(e.id.dropFirst(prefix.count)), q > s.seenSeq else { continue }
            s.seenSeq = q
            guard e.ok == true, e.kind.hasPrefix("act."), e.kind != "act.steps" else { continue }
            let d = DayKey.of(e.t)
            if d < s.day { continue }   // часы назад: прошлые сутки второй раз не платят
            if d > s.day { s.day = d; s.dayActs = 0; s.dayPaid = false }
            s.dayActs += 1
            guard s.dayActs >= cfg.goalActs, !s.dayPaid else { continue }
            s.dayPaid = true
            s.goodDays += 1
            pay("care_day", cfg.goalShards, e.t)
            let w = week(d)
            if w != s.week { s.week = w; s.weekDays = 0; s.chestPaid = false }
            s.weekDays += 1
            if s.weekDays >= cfg.chestDays, !s.chestPaid {
                s.chestPaid = true
                pay("week_chest", cfg.chestShards, e.t)
            }
        }

        // 2. Рекорд в мини-игре: побил свой прошлый (не первый раунд) — раз в сутки.
        let today = DayKey.of(now)
        for (game, v) in records(f).sorted(by: { $0.key < $1.key }) {
            guard let was = s.best[game] else { s.best[game] = v; continue }
            if v > was {
                s.best[game] = v
                if was > 0, today > s.recordDay {
                    s.recordDay = today
                    pay("record", cfg.recordShards, now)
                }
            }
        }

        // 3. Находки с прогулки: иногда в находке клочок (детерминированно по номеру), новая — в альбом.
        let total = Finds.total(f.pet.finds)
        if s.finds < 0 || total < s.finds { s.finds = total }
        while s.finds < total {
            s.finds += 1
            let u = StableRandom.mix(StableHash.fnv1a("\(f.petId):shards:find:\(s.finds)"))
            if Int(u % 100) < cfg.findChancePct {
                let span = UInt64(cfg.findMax - cfg.findMin + 1)
                pay("find", cfg.findMin + Int((u / 100) % span), now)
            }
        }
        for (id, n) in f.pet.finds.sorted(by: { $0.key < $1.key }) where n > 0 && !s.once.contains("find:\(id)") {
            s.once.append("find:\(id)")
            pay("new_find", cfg.newFindKind, now)
        }

        // 4. Достижения по разу.
        var got: [String] = []
        for (n, id) in [(7, "good_days_7"), (30, "good_days_30"), (100, "good_days_100")] where s.goodDays >= n {
            got.append(id)
        }
        if f.cooking.total.values.contains(where: { $0 > 0 }) { got.append("first_dish") }
        if f.tricks.items.values.contains(where: { $0.learned != nil }) { got.append("first_trick") }
        for id in got where !s.once.contains("ach.\(id)") {
            s.once.append("ach.\(id)")
            pay("ach.\(id)", cfg.achievements[id] ?? 0, now)
        }

        if s != f.shardLog { f.shardLog = s }
        return out
    }

    static func canAfford(_ f: SaveFile, _ n: Int) -> Bool { f.econ.wallet.shards >= max(0, n) }

    /// Списать клочки. Не хватает — ничего не меняет, false.
    @discardableResult
    static func spend(_ f: inout SaveFile, _ n: Int) -> Bool {
        guard n >= 0, f.econ.wallet.shards >= n else { return false }
        f.econ.wallet.shards -= n
        return true
    }

    /// Цена возврата пса в клочках: base + step за каждый прошлый возврат, не выше max.
    /// Для зоны смерти: revivesBefore — сколько раз этого (или прошлых) псов уже возвращали.
    static func reviveCost(revivesBefore: Int, _ cfg: PremiumConfig = .shared) -> Int {
        min(cfg.reviveMax, cfg.reviveBase + cfg.reviveStep * max(0, revivesBefore))
    }

    // MARK: Ателье

    static func atelierPrice(_ r: Rarity, _ cfg: PremiumConfig = .shared) -> Int? { cfg.atelier[r] }

    /// Чего этой редкости ещё нет у хозяина (только капсула, без эксклюзивов).
    static func atelierLeft(_ f: SaveFile, _ r: Rarity, _ eco: EconomyConfig = .shared) -> [CapsuleItem] {
        (eco.capsule.pools[r] ?? []).filter { f.econ.items[$0.id] == nil }
    }

    /// Ателье: вещь выбранной редкости, которой ещё нет. Гарант капсулы не трогает. В журнал — atelier.
    static func atelier(_ f: inout SaveFile, rarity r: Rarity, now: Double, _ cfg: PremiumConfig = .shared,
                        _ eco: EconomyConfig = .shared) -> Result<CapsuleItem, ShardRefusal> {
        guard let price = cfg.atelier[r] else { return .failure(.unknown) }
        let left = atelierLeft(f, r, eco)
        guard !left.isEmpty else { return .failure(.allOwned) }
        guard spend(&f, price) else { return .failure(.notEnough(need: price - f.econ.wallet.shards)) }
        let u = StableRandom.mix(StableHash.fnv1a("\(f.petId):atelier:\(f.shardLog.atelier)"))
        let it = left[Int(u % UInt64(left.count))]
        f.shardLog.atelier += 1
        f.econ.items[it.id] = 1
        f.log("atelier", t: now, key: it.id, value: price)
        return .success(it)
    }

    // MARK: Эксклюзивы

    /// Лоскутные вещи как предметы коллекции (редкость — эпическая).
    static func exclusiveItems(_ cfg: PremiumConfig = .shared) -> [CapsuleItem] {
        cfg.exclusives.map { CapsuleItem(id: $0.id, name: $0.name, rarity: PremiumConfig.exclusiveRarity) }
    }

    /// Купить лоскутную вещь за клочки. В журнал — shards.buy (key — id, value — цена).
    static func buyExclusive(_ id: String, in f: inout SaveFile, now: Double,
                             _ cfg: PremiumConfig = .shared) -> Result<CapsuleItem, ShardRefusal> {
        guard let ex = cfg.exclusive(id) else { return .failure(.unknown) }
        if f.econ.items[id] != nil { return .failure(.owned) }
        guard spend(&f, ex.price) else { return .failure(.notEnough(need: ex.price - f.econ.wallet.shards)) }
        f.econ.items[id] = 1
        f.log("shards.buy", t: now, key: id, value: ex.price)
        return .success(CapsuleItem(id: ex.id, name: ex.name, rarity: PremiumConfig.exclusiveRarity))
    }

    /// Через стор: одна запись под замком.
    static func performAtelier(_ r: Rarity, store: PetStore = .shared,
                               now: Double = Clock.now()) throws -> Result<CapsuleItem, ShardRefusal> {
        try store.mutate { f in atelier(&f, rarity: r, now: now) }
    }

    static func performBuy(_ id: String, store: PetStore = .shared,
                           now: Double = Clock.now()) throws -> Result<CapsuleItem, ShardRefusal> {
        try store.mutate { f in buyExclusive(id, in: &f, now: now) }
    }

    // MARK: Тексты

    /// Подпись начисления: «за день заботы».
    static func reasonText(_ reason: String) -> String {
        if let t = Places.reasonText(reason) { return t }
        switch reason {
        case "care_day": return "за день заботы"
        case "week_chest": return "сундук недели"
        case "record": return "за рекорд"
        case "find": return "нашёлся на прогулке"
        case "new_find": return "за новую находку"
        case "ach.good_days_7": return "7 дней заботы"
        case "ach.good_days_30": return "30 дней заботы"
        case "ach.good_days_100": return "100 дней заботы"
        case "ach.first_dish": return "первое блюдо"
        case "ach.first_trick": return "первый трюк"
        default: return "награда"
        }
    }

    /// «+3 ✂️ за день заботы».
    static func gainText(_ g: ShardGain) -> String { "+\(g.shards) ✂️ \(reasonText(g.reason))" }

    /// Тост (значок ✂️ рисует сам тост): «+3 клочка за день заботы».
    static func toastText(_ g: ShardGain) -> String { "+\(EconText.shards(g.shards)) \(reasonText(g.reason))" }

    /// Прогресс на сегодня и неделю для экрана: «Сегодня: дел 3 из 5 · Неделя: дней 2 из 5».
    static func progress(_ f: SaveFile, now: Double, _ cfg: PremiumConfig = .shared) -> String {
        let s = f.shardLog
        let d = DayKey.of(now)
        let acts = s.day == d ? min(s.dayActs, cfg.goalActs) : 0
        let days = s.week == week(d) ? min(s.weekDays, cfg.chestDays) : 0
        let today = s.day == d && s.dayPaid ? "Сегодня: день заботы засчитан" : "Сегодня: дел \(acts) из \(cfg.goalActs)"
        let wk = s.week == week(d) && s.chestPaid ? "сундук недели открыт" : "неделя: дней \(days) из \(cfg.chestDays)"
        return "\(today) · \(wk)"
    }
}

// MARK: - Мастерская ✂️ для экрана автомата

/// Карточка мастерской: «Ателье» одной редкости или лоскутная вещь.
struct ShardOffer: Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        case atelier(Rarity)
        case exclusive(String)
    }
    enum State: Hashable, Sendable {
        /// Можно взять; need > 0 — не хватает клочков.
        case buy(need: Int)
        /// Лоскутная вещь уже есть.
        case owned
        /// Все вещи этой редкости уже собраны.
        case allOwned
    }

    let kind: Kind
    let title: String
    /// Одна строка под названием: что это или какая польза.
    let note: String
    let price: Int
    let rarity: Rarity
    let state: State

    var id: String {
        switch kind {
        case .atelier(let r): return "atelier.\(r.rawValue)"
        case .exclusive(let id): return "shards.\(id)"
        }
    }
    /// Иконка: у лоскутной — сама вещь, у ателье — nil (экран рисует ножницы).
    var itemId: String? {
        if case .exclusive(let id) = kind { return id }
        return nil
    }
}

extension Shards {
    /// Ателье по редкостям (дешёвое первым), потом лоскутные вещи по цене.
    static func offers(_ f: SaveFile, _ cfg: PremiumConfig = .shared,
                       _ eco: EconomyConfig = .shared) -> [ShardOffer] {
        let have = f.econ.wallet.shards
        let atelier = cfg.atelier.sorted { $0.value < $1.value }.map { (r, price) -> ShardOffer in
            let left = atelierLeft(f, r, eco).count
            let name = EconText.rarityName(r).lowercased()
            return ShardOffer(kind: .atelier(r), title: "Ателье: \(name) вещь",
                              note: left == 0 ? "Все вещи этой редкости уже есть" : "Новая, без повторок: ещё \(left)",
                              price: price, rarity: r,
                              state: left == 0 ? .allOwned : .buy(need: max(0, price - have)))
        }
        let exclusives = cfg.exclusives.sorted { $0.price < $1.price }.map { ex -> ShardOffer in
            ShardOffer(kind: .exclusive(ex.id), title: ex.name,
                       note: ItemPerks.line(ex.id, cfg) ?? "Только за клочки",
                       price: ex.price, rarity: PremiumConfig.exclusiveRarity,
                       state: f.econ.items[ex.id] != nil ? .owned : .buy(need: max(0, ex.price - have)))
        }
        return atelier + exclusives
    }

    /// Подпись на кнопке карточки.
    static func buttonTitle(_ o: ShardOffer) -> String {
        switch o.state {
        case .owned: return "Уже есть"
        case .allOwned: return "Всё собрано"
        case .buy(let need): return need > 0 ? "Не хватает \(need)" : "Взять"
        }
    }

    /// Отказ после нажатия.
    static func refusalText(_ r: ShardRefusal) -> String {
        switch r {
        case .notEnough(let need): return "Не хватает клочков: \(need) ✂️"
        case .allOwned: return "Все вещи этой редкости уже есть"
        case .owned: return "Это уже есть в коллекции"
        case .unknown: return "Такого в мастерской нет"
        }
    }

    /// Свежая награда для тоста: последняя, не старше 10 с и ещё не показанная (shownT — время показанной).
    static func freshGain(_ f: SaveFile, now: Double, shownT: Double?) -> ShardGain? {
        guard let g = f.shardLog.last, g.shards > 0, now - g.t < 10, g.t != shownT else { return nil }
        return g
    }
}
