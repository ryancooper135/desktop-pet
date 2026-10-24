// Волна 33 A. Уровень пса 1–40 (RESEARCH/20 §3): опыт за заботу, кривая, награды и что открывает каждый уровень.
//
// Опыт (DogLevel.settle, идемпотентно по журналу, как Shards.settle): каждая запись журнала этого устройства —
// один раз. Правило — по виду записи (act.feed, ev.back_home, trick.learn, yard.collect…), у правила свой опыт и
// дневной лимит. Мини-игры в журнал не пишутся — их считаем по счётчикам партий за сутки (catchGames и т. п.).
// Общий потолок — 150 в сутки; бонус «первый раз» (+5 за каждый вид) и опыт сверх ур. 40 в потолок не входят /
// не идут. Часы назад: прошлые сутки второй раз не платят. «Хороший день» (+15) — когда сутки закрылись: был
// заход и в полночь ≥ 3 сердец (сердечки — последнее, что видели в эти сутки, с учётом потерь из журнала).
// Кривая: xp(L → L+1) = round5(20 + 4·L^1.6), ур. 10 — 715 опыта (≈ неделя активного ухода), ур. 40 — 22 570.
// Награды за уровень: 20 × L монет, каждый 5-й — 5 ✂️. Старый сейв: 60 опыта за день заботы, не выше ур. 10,
// без наград за эти уровни. Цифры — раздел dog_level (кусок лежит в config/wave33/level.json).
// Двор (C) и места (D) уровень сами не читают — им его передают параметром (DogLevel.level(f)).

import Foundation
@preconcurrency import PetCore

// MARK: - Конфиг

/// Сколько опыта даёт вид записи журнала. perDay 0 — без лимита. group — общий лимит и бонус «первый раз».
struct XpRule: Hashable, Sendable {
    var xp: Int
    var perDay = 0
    var group: String
}

/// Что открывает уровень: вид, id (для кода) и строка для экрана. value — число у прибавок (+5 % и т. п.).
enum UnlockKind: String, CaseIterable, Sendable {
    case yard, station, place, game, shop, home, room, feature, perk, item, title
}

struct LevelUnlock: Hashable, Sendable {
    let kind: UnlockKind
    let id: String
    let text: String
    var value = 0
}

struct DogLevelConfig: Hashable, Sendable {
    // кривая
    var maxLevel = 40
    var curveBase = 20.0
    var curveK = 4.0
    var curvePow = 1.6
    var curveRound = 5
    // опыт
    var dayCap = 150
    var firstBonus = 5
    var rules: [String: XpRule] = DogLevelConfig.stubRules
    var goodDayXp = 15
    var goodDayHearts = 3.0
    // награды
    var coinsPerLevel = 20
    var shardsEvery = 5
    var shardsReward = 5
    // старый сейв
    var migrateXpPerDay = 60
    var migrateMaxLevel = 10
    // открытия
    var unlocks: [Int: [LevelUnlock]] = DogLevelConfig.stubUnlocks

    /// Мини-игры: счётчики партий за сутки в SaveFile. Опыт — по правилу game.<имя>.
    static let games = ["catch", "blockduo", "zombie"]

    /// Ключ — вид записи журнала (для ev.* — без хвоста: ev.back_home.<находка> → ev.back_home).
    /// yard.*, task.done, ask.done, trip.first, game.challenge пишут будущие модули (двор, задания, места).
    static let stubRules: [String: XpRule] = [
        "act.feed": XpRule(xp: 2, group: "feed"),
        "act.pet": XpRule(xp: 1, perDay: 10, group: "pet"),
        "act.play": XpRule(xp: 3, group: "play"),
        "act.bath": XpRule(xp: 8, perDay: 1, group: "bath"),
        "ev.back_home": XpRule(xp: 10, group: "walk"),
        "trip.first": XpRule(xp: 15, group: "trip_first"),
        "yard.collect": XpRule(xp: 4, perDay: 2, group: "collect"),
        "game.catch": XpRule(xp: 5, perDay: 6, group: "game"),
        "game.blockduo": XpRule(xp: 5, perDay: 6, group: "game"),
        "game.zombie": XpRule(xp: 5, perDay: 6, group: "game"),
        "game.challenge": XpRule(xp: 10, perDay: 1, group: "challenge"),
        "task.done": XpRule(xp: 5, perDay: 3, group: "task"),
        "ask.done": XpRule(xp: 5, group: "ask"),
        "trick.learn": XpRule(xp: 20, group: "trick"),
        "yard.tier": XpRule(xp: 25, group: "yard_tier"),
    ]

    /// Таблица RESEARCH/20 §3. id станций и мест — черновые, сливающий сверяет их с Yard и Places.
    static let stubUnlocks: [Int: [LevelUnlock]] = {
        func u(_ k: UnlockKind, _ id: String, _ text: String, _ v: Int = 0) -> LevelUnlock {
            LevelUnlock(kind: k, id: id, text: text, value: v)
        }
        var t: [Int: [LevelUnlock]] = [
            1: [u(.yard, "yard.0", "Подоконник"), u(.game, "game.catch", "Лови мячик"), u(.feature, "capsule", "Капсула")],
            2: [u(.station, "dryer", "Сушилка сухариков"), u(.place, "bus_stop", "Остановка без автобуса")],
            3: [u(.game, "game.blockduo", "Блок Дуо"), u(.shop, "shop.rare", "В лавке редкие вещи")],
            4: [u(.yard, "yard.1", "Дворик"), u(.station, "bone_bed", "Косточковая грядка")],
            5: [u(.place, "laundromat", "Прачечная 24/7"), u(.home, "home.2", "2-й уровень линий дома", 2)],
            6: [u(.game, "game.zombie", "Щенок против зомби")],
            7: [u(.station, "porridge", "Котелок каши"), u(.feature, "tasks.3", "Третье задание дня", 3)],
            8: [u(.place, "cat_hill", "Холм-кот")],
            9: [u(.yard, "yard.2", "Сад")],
            10: [u(.station, "spinner", "Прялка из шерсти"), u(.shop, "shop.slots", "В лавке 4 места", 4)],
            11: [u(.place, "arcade", "Аркада «Пиксель»"), u(.feature, "games.challenge", "Челлендж дня в играх")],
            12: [u(.yard, "yard.3", "Парк"), u(.home, "home.3", "3-й уровень линий дома", 3),
                 u(.room, "room.second", "Вторая комната")],
            13: [u(.shop, "shop.epic", "В лавке эпические вещи")],
            14: [u(.station, "pie_oven", "Пирожковая печь")],
            15: [u(.place, "forest_tv", "Телевизор в лесу"), u(.perk, "tips_chance_pct", "Чаевые при сборе чаще", 150)],
            16: [u(.room, "room.guest", "Гостевая комната"), u(.feature, "capsule.gold", "Золотой шарик за ✂️")],
            17: [u(.game, "game.hide", "Прятки (скоро)"), u(.shop, "shop.slot_day", "+1 место в лавке на сутки", 1)],
            18: [u(.station, "photo_booth", "Фотобудка")],
            19: [u(.place, "lighthouse", "Маяк в поле")],
            20: [u(.yard, "yard.4", "Квартал"), u(.perk, "walk_time_pct", "Прогулки на 10% короче", -10)],
            21: [u(.shop, "shop.seasonal", "В лавке вещи по сезону")],
            22: [u(.perk, "chef_dishes", "Кухня шефа: +1 блюдо в день", 1)],
            23: [u(.station, "sausage_line", "Сосисочный конвейер")],
            24: [u(.place, "echo_well", "Колодец эха")],
            25: [u(.perk, "stations_pct", "Все станции +5%", 5)],
            26: [u(.shop, "shop.slots", "В лавке 5 мест", 5)],
            27: [u(.game, "game.rhythm", "Ритм-тявк (скоро)"), u(.shop, "shop.slot_day", "+1 место в лавке на сутки", 1)],
            28: [u(.station, "moon_mill", "Лунная мельница")],
            29: [u(.feature, "stations.gold_look", "Золотые таблички станций")],
            30: [u(.place, "rocket", "Картонная ракета")],
            35: [u(.item, "collar_35", "Ошейник «35»")],
            40: [u(.title, "title.prince", "Князь двора")],
        ]
        for l in 31...34 { t[l] = [u(.perk, "stations_pct", "Все станции +2%", 2)] }
        for l in 36...39 { t[l] = [u(.perk, "yard_decor_slots", "+1 место для мебели на дворе", 1)] }
        return t
    }()

    static let shared = DogLevelConfig(json: Catalog.economy() ?? .null)

    init() {}

    /// e — economy.json целиком (или кусок {"dog_level": …}). Нет раздела — умолчания.
    init(json e: JSONValue) {
        func int(_ v: JSONValue, _ d: Int) -> Int { v.double.map { Int($0) } ?? d }
        let p = e["dog_level"]
        let c = p["curve"]
        maxLevel = max(2, int(c["max_level"], maxLevel))
        curveBase = c["base"].double ?? curveBase
        curveK = c["k"].double ?? curveK
        curvePow = c["pow"].double ?? curvePow
        curveRound = max(1, int(c["round"], curveRound))
        let x = p["xp"]
        dayCap = max(0, int(x["day_cap"], dayCap))
        firstBonus = max(0, int(x["first_bonus"], firstBonus))
        goodDayXp = max(0, int(x["good_day"]["xp"], goodDayXp))
        goodDayHearts = x["good_day"]["hearts"].double ?? goodDayHearts
        for (kind, r) in x["sources"].object {
            guard let n = r["xp"].double else { continue }
            rules[kind] = XpRule(xp: max(0, Int(n)), perDay: max(0, int(r["per_day"], 0)),
                                 group: r["group"].string ?? kind)
        }
        let rw = p["rewards"]
        coinsPerLevel = max(0, int(rw["coins_per_level"], coinsPerLevel))
        shardsEvery = max(1, int(rw["shards_every"], shardsEvery))
        shardsReward = max(0, int(rw["shards"], shardsReward))
        let m = p["migrate"]
        migrateXpPerDay = max(0, int(m["xp_per_care_day"], migrateXpPerDay))
        migrateMaxLevel = max(1, int(m["max_level"], migrateMaxLevel))
        var un: [Int: [LevelUnlock]] = [:]
        for (k, list) in p["unlocks"].object {
            guard let l = Int(k) else { continue }
            un[l] = list.array.compactMap { it in
                guard let kind = it["kind"].string.flatMap(UnlockKind.init(rawValue:)), let id = it["id"].string
                else { return nil }
                return LevelUnlock(kind: kind, id: id, text: it["text"].string ?? id, value: int(it["value"], 0))
            }
        }
        if !un.isEmpty { unlocks = un }
    }

    /// Правило для вида записи: точное или по первым двум частям (ev.back_home.bone → ev.back_home).
    func rule(_ kind: String) -> XpRule? {
        if let r = rules[kind] { return r }
        let parts = kind.split(separator: ".", maxSplits: 2)
        guard parts.count > 2 else { return nil }
        return rules["\(parts[0]).\(parts[1])"]
    }
}

// MARK: - Учёт в SaveFile

/// Начисление опыта — для строки «+10 опыта за прогулку».
struct XpGain: Codable, Hashable, Sendable {
    let reason: String   // группа правила (feed, walk, game…), good_day; first.<группа> — бонус «первый раз»
    let xp: Int
    let t: Double
}

/// Новый уровень и награда за него.
struct LevelUp: Codable, Hashable, Sendable {
    let level: Int
    let coins: Int
    let shards: Int
    let t: Double
}

/// Поле level в state.json. Пустое не пишется. Новому щенку не переходит: уровень — этого пса.
struct DogLevelLog: Codable, Hashable, Sendable {
    /// false — учёт ещё не заводился: первый settle переносит старый сейв.
    var started = false
    var xp = 0
    /// Последний учтённый номер записи журнала этого устройства.
    var seenSeq = 0
    /// Текущие сутки учёта: номер, опыт за них, засчитано по группам, был ли заход.
    var day = 0
    var dayXp = 0
    var counts: [String: Int] = [:]
    var visited = false
    /// Последние виденные в эти сутки сердечки и когда — для «хорошего дня».
    var hearts: Double?
    var heartsT: Double?
    /// Мини-игры: сутки и партий, которые уже учли.
    var gameDay: [String: Int] = [:]
    var gameSeen: [String: Int] = [:]
    /// Группы, за которые уже дан бонус «первый раз».
    var firsts: [String] = []
    /// До какого уровня награды выданы.
    var paidLevel = 1
    /// Стартовый опыт старого сейва (0 — новый пёс).
    var migrated = 0
    var last: XpGain?
    var lastUp: LevelUp?

    init() {}

    var isEmpty: Bool { self == DogLevelLog() }

    enum CodingKeys: String, CodingKey {
        case started, xp, seenSeq, day, dayXp, counts, visited, hearts, heartsT, gameDay, gameSeen, firsts
        case paidLevel, migrated, last, lastUp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        started = (try? c.decodeIfPresent(Bool.self, forKey: .started)) ?? false
        xp = (try? c.decodeIfPresent(Int.self, forKey: .xp)) ?? 0
        seenSeq = (try? c.decodeIfPresent(Int.self, forKey: .seenSeq)) ?? 0
        day = (try? c.decodeIfPresent(Int.self, forKey: .day)) ?? 0
        dayXp = (try? c.decodeIfPresent(Int.self, forKey: .dayXp)) ?? 0
        counts = (try? c.decodeIfPresent([String: Int].self, forKey: .counts)) ?? [:]
        visited = (try? c.decodeIfPresent(Bool.self, forKey: .visited)) ?? false
        hearts = try? c.decodeIfPresent(Double.self, forKey: .hearts)
        heartsT = try? c.decodeIfPresent(Double.self, forKey: .heartsT)
        gameDay = (try? c.decodeIfPresent([String: Int].self, forKey: .gameDay)) ?? [:]
        gameSeen = (try? c.decodeIfPresent([String: Int].self, forKey: .gameSeen)) ?? [:]
        firsts = (try? c.decodeIfPresent([String].self, forKey: .firsts)) ?? []
        paidLevel = (try? c.decodeIfPresent(Int.self, forKey: .paidLevel)) ?? 1
        migrated = (try? c.decodeIfPresent(Int.self, forKey: .migrated)) ?? 0
        last = try? c.decodeIfPresent(XpGain.self, forKey: .last)
        lastUp = try? c.decodeIfPresent(LevelUp.self, forKey: .lastUp)
    }
}

/// Итог settle: сколько опыта, за что и какие уровни взяты.
struct LevelOutcome: Hashable, Sendable {
    var xp = 0
    var gains: [XpGain] = []
    var ups: [LevelUp] = []
}

/// Уровень, опыт внутри него и сколько до следующего — для полоски в шапке.
struct LevelProgress: Hashable, Sendable {
    let level: Int
    let xp: Int
    /// Опыта набрано внутри уровня и нужно на весь уровень (на пределе — 0 из 0).
    let into: Int
    let need: Int
    var isMax: Bool { need == 0 }
    var fraction: Double { need > 0 ? Double(into) / Double(need) : 1 }
}

// MARK: - Кривая, начисление, награды

enum DogLevel {
    /// Опыт на шаг L → L+1: round5(20 + 4·L^1.6).
    static func xpStep(_ l: Int, _ cfg: DogLevelConfig = .shared) -> Int {
        let raw = cfg.curveBase + cfg.curveK * pow(Double(max(1, l)), cfg.curvePow)
        let r = Double(cfg.curveRound)
        return Int((raw / r).rounded(.toNearestOrAwayFromZero) * r)
    }

    /// Всего опыта до уровня L (ур. 1 — 0).
    static func xpTo(_ l: Int, _ cfg: DogLevelConfig = .shared) -> Int {
        let top = min(max(1, l), cfg.maxLevel)
        guard top > 1 else { return 0 }
        return (1..<top).reduce(0) { $0 + xpStep($1, cfg) }
    }

    /// Уровень по опыту, не выше предела.
    static func level(xp: Int, _ cfg: DogLevelConfig = .shared) -> Int {
        var l = 1
        var need = 0
        while l < cfg.maxLevel {
            need += xpStep(l, cfg)
            if xp < need { break }
            l += 1
        }
        return l
    }

    static func level(_ f: SaveFile, _ cfg: DogLevelConfig = .shared) -> Int { level(xp: f.level.xp, cfg) }

    static func progress(_ f: SaveFile, _ cfg: DogLevelConfig = .shared) -> LevelProgress {
        let xp = f.level.xp
        let l = level(xp: xp, cfg)
        guard l < cfg.maxLevel else { return LevelProgress(level: l, xp: xp, into: 0, need: 0) }
        return LevelProgress(level: l, xp: xp, into: xp - xpTo(l, cfg), need: xpStep(l, cfg))
    }

    /// Награда за взятый уровень: 20 × L монет, каждый 5-й — ✂️.
    static func reward(_ l: Int, _ cfg: DogLevelConfig = .shared) -> (coins: Int, shards: Int) {
        (cfg.coinsPerLevel * l, l % cfg.shardsEvery == 0 ? cfg.shardsReward : 0)
    }

    /// Сколько дней заботы видно у старого сейва до суток today: дни ухода из CareTally (окно характера)
    /// или дни заботы из учёта клочков — что больше.
    static func careDays(_ f: SaveFile, before today: Int) -> Int {
        let tally = f.care.days.filter { k, v in (Int(k) ?? today) < today && v.values.contains { $0 > 0 } }.count
        return max(tally, f.shardLog.goodDays)
    }

    /// Мини-игра: сутки и партий с наградой за них (партии «просто так» счётчик не трогают).
    static func games(_ f: SaveFile) -> [String: (day: Int, n: Int)] {
        ["catch": (f.catchDay, f.catchGames), "blockduo": (f.blockduoDay, f.blockduoGames),
         "zombie": (f.zombieDay, f.zombieGames)]
    }

    /// Что надо учесть: запись журнала или партии мини-игры.
    private struct Item {
        let t: Double
        let day: Int
        let rule: XpRule?
        let visit: Bool
        let hearts: Double?
    }

    /// Начислить весь новый опыт и награды за уровни. Повторный вызов ничего не добавляет.
    /// now — сутки для партий мини-игр и закрытие прошедших суток («хороший день»).
    @discardableResult
    static func settle(_ f: inout SaveFile, now: Double, _ cfg: DogLevelConfig = .shared) -> LevelOutcome {
        var s = f.level
        var out = LevelOutcome()
        let today = DayKey.of(now)
        let cap = xpTo(cfg.maxLevel, cfg)

        // 0. Первый раз: старый сейв получает опыт за прошлые дни заботы (не выше ур. migrateMaxLevel),
        // журнал прошлых суток уже не платит — платят только сегодняшние записи.
        if !s.started {
            s.started = true
            s.day = today
            let start = min(careDays(f, before: today) * cfg.migrateXpPerDay, xpTo(cfg.migrateMaxLevel, cfg))
            if start > 0 {
                s.xp = start
                s.migrated = start
                s.paidLevel = level(xp: start, cfg)
            }
        }

        func add(_ n: Int, _ reason: String, _ t: Double) {
            let got = min(n, cap - s.xp)
            guard got > 0 else { return }
            s.xp += got
            out.xp += got
            let g = XpGain(reason: reason, xp: got, t: t)
            s.last = g
            out.gains.append(g)
        }
        // Сутки s.day кончились: «хороший день», если был заход и в полночь ≥ 3 сердец. Дальше — новые сутки.
        func close(to d: Int) {
            if s.visited, (s.hearts ?? 0) >= cfg.goodDayHearts {
                add(min(cfg.goodDayXp, max(0, cfg.dayCap - s.dayXp)), "good_day", DayKey.start(s.day + 1))
            }
            s.day = d
            s.dayXp = 0
            s.counts = [:]
            s.visited = false
        }

        // 1. Новые записи журнала: опыт, заходы, потери сердечек.
        var items: [Item] = []
        let prefix = "\(f.deviceId):"
        for e in f.journal {
            guard e.id.hasPrefix(prefix), let q = Int(e.id.dropFirst(prefix.count)), q > s.seenSeq else { continue }
            s.seenSeq = q
            let d = DayKey.of(e.t)
            if e.kind == "ev.heart" || e.kind == "ev.death" {
                items.append(Item(t: e.t, day: d, rule: nil, visit: false,
                                  hearts: e.kind == "ev.death" ? 0 : Double(e.value ?? 0)))
                continue
            }
            let isAct = e.kind.hasPrefix("act.")
            if isAct ? e.ok != true : e.ok == false { continue }
            let visit = isAct && e.kind != "act.steps"
            let r = cfg.rule(e.kind)
            if r != nil || visit { items.append(Item(t: e.t, day: d, rule: r, visit: visit, hearts: nil)) }
        }
        // 2. Партии мини-игр по счётчикам суток: новые с прошлого раза.
        for (game, g) in games(f).sorted(by: { $0.key < $1.key }) {
            let seenDay = s.gameDay[game] ?? Int.min
            guard g.day >= seenDay else { continue }
            let fresh = g.day > seenDay ? g.n : max(0, g.n - (s.gameSeen[game] ?? 0))
            s.gameDay[game] = g.day
            s.gameSeen[game] = g.n
            guard fresh > 0 else { continue }
            let t = g.day >= today ? now : DayKey.start(g.day + 1) - 1
            for _ in 0..<fresh { items.append(Item(t: t, day: g.day, rule: cfg.rule("game.\(game)"), visit: true, hearts: nil)) }
        }

        // 3. По порядку суток: прошлые сутки (часы назад) не платят, лимиты и потолок — на сутки.
        for it in items.enumerated().sorted(by: { ($0.element.day, $0.offset) < ($1.element.day, $1.offset) }).map(\.element) {
            if it.day < s.day { continue }
            if it.day > s.day { close(to: it.day) }
            if let h = it.hearts {
                if it.t >= (s.heartsT ?? -.infinity) { s.hearts = h; s.heartsT = it.t }
                continue
            }
            if it.visit { s.visited = true }
            guard let r = it.rule else { continue }
            let used = s.counts[r.group] ?? 0
            if r.perDay > 0, used >= r.perDay { continue }
            s.counts[r.group] = used + 1
            let got = min(r.xp, max(0, cfg.dayCap - s.dayXp))
            s.dayXp += got
            add(got, r.group, it.t)
            if cfg.firstBonus > 0, !s.firsts.contains(r.group) {
                s.firsts.append(r.group)
                add(cfg.firstBonus, "first.\(r.group)", it.t)
            }
        }
        if today > s.day { close(to: today) }

        // 4. Сердечки сейчас — если пёс в тех же сутках учёта.
        if DayKey.of(f.pet.t) == s.day, f.pet.t >= (s.heartsT ?? -.infinity) {
            s.hearts = f.pet.alive ? f.pet.hearts : 0
            s.heartsT = f.pet.t
        }

        // 5. Награды за новые уровни — по одному разу.
        let l = level(xp: s.xp, cfg)
        while s.paidLevel < l {
            s.paidLevel += 1
            let r = reward(s.paidLevel, cfg)
            Economy.grant(&f, coins: r.coins, shards: r.shards)
            let up = LevelUp(level: s.paidLevel, coins: r.coins, shards: r.shards, t: now)
            s.lastUp = up
            out.ups.append(up)
        }

        if s != f.level { f.level = s }
        return out
    }

    // MARK: Открытия

    /// Что открывается ровно на уровне l.
    static func unlocks(_ l: Int, _ cfg: DogLevelConfig = .shared) -> [LevelUnlock] { cfg.unlocks[l] ?? [] }

    /// Всё открытое к уровню l, по порядку уровней.
    static func unlocked(upTo l: Int, _ cfg: DogLevelConfig = .shared) -> [LevelUnlock] {
        (1...max(1, min(l, cfg.maxLevel))).flatMap { unlocks($0, cfg) }
    }

    /// С какого уровня открыт id (первое упоминание); nil — такого нет в таблице.
    static func needLevel(_ id: String, _ cfg: DogLevelConfig = .shared) -> Int? {
        cfg.unlocks.keys.sorted().first { l in cfg.unlocks[l]!.contains { $0.id == id } }
    }

    /// Открыт ли id на уровне l. Неизвестное — открыто (уровень его не держит).
    static func isOpen(_ id: String, level l: Int, _ cfg: DogLevelConfig = .shared) -> Bool {
        l >= (needLevel(id, cfg) ?? 1)
    }

    /// Мини-игра (catch, blockduo, zombie) открыта: по уровню или в неё уже играли — у старых сейвов не закрываем.
    static func gameOpen(_ game: String, _ f: SaveFile, _ cfg: DogLevelConfig = .shared) -> Bool {
        let played: Int
        switch game {
        case "catch": played = f.catchBest + f.catchGames
        case "blockduo": played = f.blockduoBest + f.blockduoGames
        case "zombie": played = f.zombieBest + f.zombieGames
        default: played = 0
        }
        return played > 0 || isOpen("game.\(game)", level: level(f, cfg), cfg)
    }

    /// Самое большое value среди открытого к уровню l с этим id (слоты лавки, уровень линий дома); nil — не открыто.
    static func maxValue(_ id: String, level l: Int, _ cfg: DogLevelConfig = .shared) -> Int? {
        unlocked(upTo: l, cfg).filter { $0.id == id }.map(\.value).max()
    }

    /// Сумма value по открытому к уровню l (прибавки станциям, места для мебели).
    static func sumValue(_ id: String, level l: Int, _ cfg: DogLevelConfig = .shared) -> Int {
        unlocked(upTo: l, cfg).filter { $0.id == id }.reduce(0) { $0 + $1.value }
    }

    /// Какой ярус двора разрешён уровнем (0 — Подоконник … 4 — Квартал).
    static func yardTierMax(level l: Int, _ cfg: DogLevelConfig = .shared) -> Int {
        unlocked(upTo: l, cfg).filter { $0.kind == .yard }.compactMap { Int($0.id.dropFirst("yard.".count)) }.max() ?? 0
    }

    /// Какой уровень линий дома разрешён уровнем пса: 1, со ур. 5 — 2, со ур. 12 — 3.
    static func homeLineMax(level l: Int, _ cfg: DogLevelConfig = .shared) -> Int {
        max(1, unlocked(upTo: l, cfg).filter { $0.kind == .home }.map(\.value).max() ?? 1)
    }

    /// Мест в лавке дня: 3, с ур. 10 — 4, с ур. 26 — 5 (+1 на сутки на ур. 17 и 27 даёт лавка сама).
    static func shopSlots(level l: Int, _ cfg: DogLevelConfig = .shared) -> Int {
        maxValue("shop.slots", level: l, cfg) ?? 3
    }

    /// Прибавка ко всем станциям в процентах: ур. 25 +5, ур. 31–34 по +2.
    static func stationsPct(level l: Int, _ cfg: DogLevelConfig = .shared) -> Int {
        sumValue("stations_pct", level: l, cfg)
    }

    /// Множитель времени похода: с ур. 20 — 0,9.
    static func walkTimeX(level l: Int, _ cfg: DogLevelConfig = .shared) -> Double {
        1 + Double(sumValue("walk_time_pct", level: l, cfg)) / 100
    }

    // MARK: Тексты

    /// Подпись начисления: «за прогулку».
    static func reasonText(_ reason: String) -> String {
        if reason.hasPrefix("first.") { return "за первый раз" }
        switch reason {
        case "feed": return "за еду"
        case "pet": return "за ласку"
        case "play": return "за игру"
        case "bath": return "за купание"
        case "walk": return "за прогулку"
        case "trip_first": return "за новое место"
        case "collect": return "за сбор копилки"
        case "game": return "за мини-игру"
        case "challenge": return "за челлендж"
        case "task": return "за задание дня"
        case "ask": return "за просьбу пса"
        case "trick": return "за новый трюк"
        case "yard_tier": return "за новый ярус двора"
        case "good_day": return "за хороший день"
        default: return "за заботу"
        }
    }

    /// «+10 опыта за прогулку».
    static func gainText(_ g: XpGain) -> String {
        "+\(g.xp) \(EconText.plural(g.xp, "опыт", "опыта", "опыта")) \(reasonText(g.reason))"
    }

    /// «Уровень 5! +100 монет · +5 клочков».
    static func upText(_ u: LevelUp) -> String {
        var s = "Уровень \(u.level)! +\(EconText.coins(u.coins))"
        if u.shards > 0 { s += " · +\(EconText.shards(u.shards))" }
        return s
    }

    /// Шапка: «Ур. 7 · 40 из 90» или «Ур. 40 · предел».
    static func headerText(_ p: LevelProgress) -> String {
        p.isMax ? "Ур. \(p.level) · предел" : "Ур. \(p.level) · \(p.into) из \(p.need)"
    }

    /// Свежий новый уровень для сцены: не старше 10 с и ещё не показанный (shownT — время показанного).
    static func freshUp(_ f: SaveFile, now: Double, shownT: Double?) -> LevelUp? {
        guard let u = f.level.lastUp, now - u.t < 10, u.t != shownT else { return nil }
        return u
    }
}
