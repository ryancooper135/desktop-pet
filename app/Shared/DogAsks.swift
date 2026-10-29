// Волна 43 K (RESEARCH/04-game-design.md п.4, TZ_v2): просьбы пса.
// Иногда пёс просит конкретное: «хочу кушать», «погуляем?», «почеши за ушком», «поиграем в мячик», «помой меня».
// Только то, что правда можно сделать сейчас и что пишется в журнал (act.feed/pet/play/brush/bath/walk).
//
// Когда: по часам дня, детерминированно по (petId, сутки, час) — приложение, виджет и остров видят одно и то же.
// Час «выпадает» с шансом chance, минута старта — 0…44; между стартами не меньше minGap, не больше perDay в сутки.
// Ночью нет: всё окно просьбы — вне сна хозяина и ночи пса, и не раньше чем через wakeGap после подъёма хозяина.
// Что: решается в момент старта по стейту пса на этот момент (PetRunner.peek): голодный — еда, грязный — помыть,
// заскучал — поиграть/погладить, засиделся — гулять. Всё хорошо — что-то из (погладить, поиграть, расчесать, гулять)
// по хешу, не то же, что прошлая просьба. Нельзя сделать (гуляет, моется, спит, откат надолго) — просьбы нет.
// Выполнено в окне (window) — немного монет и запись ask.done (опыт DogLevel). Не выполнено — просто уходит,
// без наказания. Сутки не откатываются: часы назад и перелёт на запад не дают второй набор и второй оплаты.
// Цифры — раздел "asks" в config/economy.json (нет раздела — умолчания ниже). Решения — DECISIONS.md, «Волна 43 K».

import Foundation
@preconcurrency import PetCore

struct DogAskConfig: Sendable {
    /// Просьб в сутки не больше.
    var perDay = 5
    /// Шанс, что час дня даст просьбу, %.
    var chancePct = 40
    /// Не чаще: между стартами, минут.
    var minGapMin = 120
    /// Окно просьбы, минут.
    var windowMin = 60
    /// Не раньше, чем через столько минут после подъёма хозяина.
    var wakeGapMin = 30
    /// Монеты: base + perLevel × уровень, к ближайшему кратному round.
    var coinBase = 5
    var coinPerLevel = 1
    var coinRound = 5
    /// Порог шкалы, ниже которого пёс просит именно это (порядок — DogAsks.needOrder).
    var below: [String: Double] = DogAsks.defaultBelow

    static let shared = DogAskConfig(json: Catalog.economy() ?? .null)

    init() {}

    /// e — economy.json целиком (или кусок {"asks": …}). Нет раздела — умолчания.
    init(json e: JSONValue) {
        func int(_ v: JSONValue, _ d: Int) -> Int { v.double.map { Int($0) } ?? d }
        let p = e["asks"]
        perDay = max(0, int(p["per_day"], perDay))
        chancePct = min(100, max(0, int(p["chance_pct"], chancePct)))
        minGapMin = max(0, int(p["min_gap_min"], minGapMin))
        windowMin = max(1, int(p["window_min"], windowMin))
        wakeGapMin = max(0, int(p["wake_gap_min"], wakeGapMin))
        coinBase = max(0, int(p["coins"]["base"], coinBase))
        coinPerLevel = max(0, int(p["coins"]["per_level"], coinPerLevel))
        coinRound = max(1, int(p["coins"]["round"], coinRound))
        for (k, v) in p["below"].object {
            if let n = v.double { below[k] = n }
        }
    }

    var window: Double { Double(windowMin) * 60 }

    /// Монеты за просьбу на уровне пса l.
    func coins(level l: Int) -> Int {
        let raw = coinBase + coinPerLevel * max(1, l)
        guard coinRound > 1 else { return raw }
        return max(coinRound, (raw + coinRound / 2) / coinRound * coinRound)
    }
}

/// Просьба: старт, что просит (nil — ещё не решено, skip — в этот раз не просит), когда выполнена, награда.
struct DogAsk: Codable, Hashable, Sendable {
    var start: Double
    var kind: String?
    var coins = 0
    var doneT: Double?

    var done: Bool { doneT != nil }
    /// Просьба есть (решена и не пропущена).
    var real: Bool { kind != nil && kind != DogAsks.skip }

    func open(at t: Double, window: Double) -> Bool { real && !done && t >= start && t < start + window }
}

/// Последняя выполненная — для тоста.
struct AskWin: Codable, Hashable, Sendable {
    var kind: String
    var coins: Int
    var t: Double
}

/// Поле `asks` в SaveFile. Пустое не пишется — старые сейвы читаются без него.
struct DogAsksLog: Codable, Hashable, Sendable {
    var started = false
    /// Курсор журнала: записи со своим deviceId и seq не больше этого уже учтены.
    var seenSeq = 0
    /// Сутки (DayKey) расписания items. Назад не откатываются.
    var day = 0
    var items: [DogAsk] = []
    /// Выполнено просьб всего.
    var total = 0
    var last: AskWin?

    init() {}

    var isEmpty: Bool { self == DogAsksLog() }

    enum CodingKeys: String, CodingKey {
        case started, seenSeq, day, items, total, last
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        started = (try? c.decodeIfPresent(Bool.self, forKey: .started)) ?? false
        seenSeq = (try? c.decodeIfPresent(Int.self, forKey: .seenSeq)) ?? 0
        day = (try? c.decodeIfPresent(Int.self, forKey: .day)) ?? 0
        items = (try? c.decodeIfPresent([DogAsk].self, forKey: .items)) ?? []
        total = (try? c.decodeIfPresent(Int.self, forKey: .total)) ?? 0
        last = try? c.decodeIfPresent(AskWin.self, forKey: .last)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if started { try c.encode(started, forKey: .started) }
        if seenSeq != 0 { try c.encode(seenSeq, forKey: .seenSeq) }
        if day != 0 { try c.encode(day, forKey: .day) }
        if !items.isEmpty { try c.encode(items, forKey: .items) }
        if total != 0 { try c.encode(total, forKey: .total) }
        try c.encodeIfPresent(last, forKey: .last)
    }

    /// Новому щенку: тот же день и те же просьбы с оплатами (иначе «начать заново» давало бы второй набор),
    /// курсор — с нуля (журнал у щенка новый), тост — нет. Как DailyTasksLog.carriedOver.
    func carriedOver() -> DogAsksLog {
        guard started else { return DogAsksLog() }
        var s = self
        s.seenSeq = 0
        s.last = nil
        return s
    }
}

enum DogAsks {
    /// Что пёс может попросить и какая запись журнала это выполняет (только удачные act.*).
    static let kinds: [(id: String, kind: String)] = [
        ("feed", "act.feed"), ("bath", "act.bath"), ("pet", "act.pet"), ("play", "act.play"),
        ("brush", Brush.actKind), ("walk", "act.walk"),
    ]
    /// Порядок «по нужде»: шкала → просьба. Первая шкала ниже порога решает.
    static let needOrder: [(need: Need, ask: String)] = [
        (.food, "feed"), (.clean, "bath"), (.love, "pet"), (.fun, "play"), (.walk, "walk"),
    ]
    static let defaultBelow: [String: Double] = ["food": 45, "clean": 35, "love": 45, "fun": 45, "walk": 40]
    /// Всё хорошо — просьба «для души» из этого пула (порядок не переставлять: от него зависит выбор).
    static let funPool = ["pet", "play", "brush", "walk"]
    /// Запись журнала за выполненную просьбу (DogLevel: правило ask.done).
    static let doneKind = "ask.done"
    static let skip = "skip"
    /// Откат, который пройдёт за столько секунд от старта, просьбе не мешает.
    static let cooldownGrace: Double = 15 * 60

    /// Просьбы включены. В UI-тестах — только с сидом asks*: иначе монеты и тосты просьб меняли бы чужие проверки
    /// кошелька и тостов. Юнит-тесты могут переключать.
    nonisolated(unsafe) static var enabled: Bool = !Env.isUITest || (Env.value("PET_SEED")?.hasPrefix("asks") ?? false)

    static func hash(_ key: String) -> UInt64 { StableRandom.mix(StableHash.fnv1a(key)) }

    // MARK: расписание

    /// Старты просьб суток day: по часам, детерминированно по (petId, day, час). Ночь и сон хозяина — мимо.
    static func schedule(_ f: SaveFile, day: Int, _ cfg: DogAskConfig = .shared) -> [Double] {
        guard cfg.perDay > 0, cfg.chancePct > 0 else { return [] }
        let r = ItemPerks.rules(f)
        let midnight = DayKey.start(day)
        var out: [Double] = []
        for h in 0..<24 {
            guard out.count < cfg.perDay else { break }
            let hv = hash("asks:\(f.petId):\(day):\(h)")
            guard Int(hv % 100) < cfg.chancePct else { continue }
            let start = midnight + Double(h) * 3600 + Double((hv >> 16) % 45) * 60
            guard DayKey.of(start) == day else { continue }   // сутки перевода часов: час за пределами суток
            // Волна 44 N: окно целиком в своих сутках — в полночь расписание сменяется, и просьба 23:30 у хозяина,
            // который ложится в 2:00, пропадала с плашкой «ещё 20 мин» невыполнимой.
            guard DayKey.of(start + cfg.window - 60) == day else { continue }
            if let p = out.last, start - p < Double(cfg.minGapMin) * 60 { continue }
            guard awake(f, r, start, cfg) else { continue }
            out.append(start)
        }
        return out
    }

    /// Всё окно — днём: хозяин не спит (и встал не меньше wakeGap назад), у пса не ночь.
    static func awake(_ f: SaveFile, _ r: Rules, _ start: Double, _ cfg: DogAskConfig) -> Bool {
        let end = start + cfg.window - 60
        let early = start - Double(cfg.wakeGapMin) * 60
        for t in [early, start, start + cfg.window / 2, end] {
            let o = PetRunner.owner(f, at: t)
            if PetEngine.ownerAsleep(t, o) { return false }
            if t >= start, PetEngine.petNight(t, r, o) { return false }
        }
        return true
    }

    // MARK: что просит

    /// Можно ли сделать k около момента t (откат, который скоро пройдёт, не мешает).
    static func doable(_ k: String, _ s0: PetState, _ f: SaveFile, at t: Double) -> Bool {
        var s = s0
        let r = ItemPerks.rules(f)
        let o = PetRunner.owner(f, at: t)
        let a: Action
        let cd: String
        switch k {
        case "feed": a = .feed(Catalog.mainFood); cd = Catalog.mainFood
        case "bath": a = .bath; cd = ""
        case "pet": a = .pet; cd = "pet"
        case "play": a = .play; cd = ""
        case "brush":
            Brush.adopt(&s, f.brush, at: t)
            a = .brush; cd = PetEngine.BRUSH_COOLDOWN
        case "walk": a = .walk; cd = ""
        default: return false
        }
        var probe = s
        let res = PetEngine.act(&probe, r, o, a)
        if res.ok { return true }
        if res.reason == "cooldown", let end = s.cooldowns[cd], end - t <= cooldownGrace { return true }
        return false
    }

    /// Что пёс просит в момент start, или skip. prev — прошлая просьба суток (не повторять «для души»).
    static func choose(_ f: SaveFile, at start: Double, prev: String?, _ cfg: DogAskConfig = .shared) -> String {
        let s = PetRunner.peek(f, at: start)
        // Гуляет, моется, спит, нет пса — не просит.
        guard s.alive, s.outing == nil, s.bathUntil == nil, s.napUntil == nil else { return skip }
        for (n, k) in needOrder {
            guard let lim = cfg.below[n.rawValue], let v = s.needs[n], v < lim else { continue }
            if doable(k, s, f, at: start) { return k }
        }
        let rest = funPool.filter { $0 != prev }
        guard !rest.isEmpty else { return skip }
        let k0 = Int(hash("asks:\(f.petId):\(Int(start / 60)):kind") % UInt64(rest.count))
        for i in 0..<rest.count {
            let k = rest[(k0 + i) % rest.count]
            if doable(k, s, f, at: start) { return k }
        }
        return skip
    }

    /// Просьба, которую выполняет запись журнала. act.* — только удачные.
    static func askKind(for e: JournalEntry) -> String? {
        guard e.ok == true, let id = kinds.first(where: { $0.kind == e.kind })?.id else { return nil }
        return id
    }

    // MARK: подготовка и начисление

    /// Сутки и решения на now без журнала: новый день — новое расписание, наступившие старты — решить, что просит.
    /// Звать в начале PetRunner.catchUp (до догона): пока pet.t ещё до старта, peek на старт — тот же стейт, что
    /// видели виджет и остров. settle делает это и сам (на случай записи мимо catchUp).
    static func observe(_ f: inout SaveFile, now: Double, _ cfg: DogAskConfig = .shared) {
        guard enabled else { return }
        var s = f.asks
        prepare(&s, f, now: now, cfg)
        f.asks = s
    }

    static func prepare(_ s: inout DogAsksLog, _ f: SaveFile, now: Double, _ cfg: DogAskConfig) {
        let today = DayKey.of(now)
        if !s.started || today > s.day {
            // Волна 44 N: первый раз (старый сейв до волны 43 K) — записи журнала до этого момента сделаны без
            // просьб, плашки никто не видел: курсор сразу на конец журнала, иначе первая запись после обновления
            // платила за сегодняшние ласки и кормёжки, попавшие в окна задним числом. Новый щенок приходит
            // с started (carriedOver) и курсором с нуля — его это не касается.
            if !s.started { s.seenSeq = f.seq }
            s.started = true
            s.day = today
            s.items = schedule(f, day: today, cfg).map { DogAsk(start: $0) }
        }
        // Часы назад (today < s.day): расписание прежнее, новые старты «из будущего» не наступают.
        let lvl = DogLevel.level(f)
        var prev: String?
        for i in s.items.indices {
            if s.items[i].kind == nil, s.items[i].start <= now {
                s.items[i].kind = choose(f, at: s.items[i].start, prev: prev, cfg)
                s.items[i].coins = s.items[i].real ? cfg.coins(level: lvl) : 0
            }
            if s.items[i].real { prev = s.items[i].kind }
        }
    }

    /// Учесть новые записи журнала: просьба выполнена в окне — монеты и ask.done. Повторный вызов ничего не добавляет.
    /// Звать из PetRunner.settleRewards после DailyTasks и до DogLevel (ask.done даёт опыт этой же записью).
    static func settle(_ f: inout SaveFile, now: Double, _ cfg: DogAskConfig = .shared) {
        guard enabled else { return }
        var s = f.asks
        prepare(&s, f, now: now, cfg)
        let prefix = "\(f.deviceId):"
        var hits: [(kind: String, t: Double)] = []
        for e in f.journal {
            guard e.id.hasPrefix(prefix), let q = Int(e.id.dropFirst(prefix.count)), q > s.seenSeq else { continue }
            s.seenSeq = q
            if let k = askKind(for: e) { hits.append((k, e.t)) }
        }
        for h in hits {
            guard let i = s.items.firstIndex(where: { $0.kind == h.kind && $0.open(at: h.t, window: cfg.window) })
            else { continue }
            s.items[i].doneT = h.t
            let a = s.items[i]
            Economy.grant(&f, coins: a.coins)
            f.log(doneKind, t: h.t, key: h.kind, value: a.coins)
            s.total += 1
            s.last = AskWin(kind: h.kind, coins: a.coins, t: now)
        }
        f.asks = s
    }

    /// Открытая просьба на now без записи в сейв (prepare и settle на копии) — для дома, виджета и острова.
    static func current(_ f: SaveFile, now: Double, _ cfg: DogAskConfig = .shared) -> DogAsk? {
        guard enabled else { return nil }
        var c = f
        settle(&c, now: now, cfg)
        return c.asks.items.first { $0.open(at: now, window: cfg.window) }
    }

    /// Волна 46 Q: просьба, которую видно хозяину на now — общая для дома (AppModel.dogAsk) и островка
    /// (IslandFeed.ask), как кадр виджета (IslandEvents.frames): пса нет дома (гуляет, в походе), дремлет, моется,
    /// ночь пса или пса нет — просьбы не видно. Окно при этом не закрывается: вернулся в окне — плашка снова.
    /// Раньше дом проверял только «жив», и плашка «Почеши за ушком?» висела, пока пёс гулял.
    static func shown(_ f: SaveFile, now: Double, _ cfg: DogAskConfig = .shared) -> DogAsk? {
        guard let a = current(f, now: now, cfg) else { return nil }
        if let tr = f.trip.active, now < tr.until { return nil }
        let s = PetRunner.peek(f, at: now)
        guard s.alive, s.napUntil == nil, s.outing == nil, s.bathUntil == nil else { return nil }
        if PetEngine.petNight(now, ItemPerks.rules(f), PetRunner.owner(f, at: now)) { return nil }
        return a
    }

    /// Волна 45 O: просьбы, открытые хоть часть отрезка [now, until) — для кадров виджета. Сейв не пишется.
    /// Уже наступившие — как в current (журнал учтён, выполненные мимо). Будущие — прогноз: что пёс попросит,
    /// решается так же, как решит приложение (choose по peek на старт), пока хозяин ничего не сделал.
    /// Сделает — приложение перезагрузит таймлайн виджета, и прогноз пересчитается.
    static func upcoming(_ f: SaveFile, now: Double, until: Double, _ cfg: DogAskConfig = .shared) -> [DogAsk] {
        guard enabled, until > now else { return [] }
        var c = f
        settle(&c, now: now, cfg)
        var log = c.asks
        var out: [DogAsk] = []
        var cursor = now
        for _ in 0..<3 {   // виджет смотрит на ~12 ч вперёд: больше двух суток не бывает
            let dayEnd = DayKey.nextMidnight(after: cursor)
            // Новые сутки prepare начнёт сам (today > day): расписание того дня, решения — на его старты.
            prepare(&log, c, now: max(cursor, min(until, dayEnd - 1)), cfg)
            for a in log.items where a.real && !a.done && a.start < until && a.start + cfg.window > now {
                if !out.contains(where: { $0.start == a.start }) { out.append(a) }
            }
            guard until > dayEnd else { break }
            cursor = dayEnd
        }
        return out.sorted { $0.start < $1.start }
    }

    /// Минут до конца окна (не меньше 1).
    static func minutesLeft(_ a: DogAsk, now: Double, _ cfg: DogAskConfig = .shared) -> Int {
        max(1, Int(((a.start + cfg.window - now) / 60).rounded(.up)))
    }
}

// MARK: - Тексты

enum DogAskText {
    static func emoji(_ k: String) -> String {
        switch k {
        case "feed": return "🍖"
        case "bath": return "🛁"
        case "pet": return "🤲"
        case "play": return "🎾"
        case "brush": return "🪮"
        case "walk": return "🦮"
        default: return "🐾"
        }
    }

    /// Слова пса: «Хочу кушать!».
    static func line(_ k: String) -> String {
        switch k {
        case "feed": return "Хочу кушать!"
        case "bath": return "Помой меня?"
        case "pet": return "Почеши за ушком?"
        case "play": return "Поиграем в мячик?"
        case "brush": return "Расчешешь меня?"
        case "walk": return "Погуляем?"
        default: return "Побудь со мной?"
        }
    }

    /// Кнопка, которую нажать.
    static func button(_ k: String) -> String {
        switch k {
        case "feed": return "Покормить"
        case "bath": return "Помыть"
        case "pet": return "Погладить"
        case "play": return "Поиграть"
        case "brush": return "Расчесать"
        case "walk": return "Гулять"
        default: return "Погладить"
        }
    }

    /// Плашка: «Хочу кушать! · ещё 40 мин».
    static func plate(_ a: DogAsk, now: Double) -> String {
        "\(line(a.kind ?? "")) · ещё \(DogAsks.minutesLeft(a, now: now)) мин"
    }

    /// Подсказка по нажатию: «Просит: нажми «Покормить» — +10 🪙».
    static func hint(_ a: DogAsk) -> String {
        "Нажми «\(button(a.kind ?? ""))» — +\(a.coins) 🪙"
    }

    /// Тост: «Просьба выполнена! · +10 🪙».
    static func toast(_ w: AskWin) -> String { "Просьба выполнена! \(button(w.kind)) · +\(w.coins) 🪙" }
}
