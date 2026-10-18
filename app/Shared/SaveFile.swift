// Файл сохранения state.json: питомец, хозяин, журнал и служебные флаги.
// Читают и пишут приложение, виджеты и интенты, поэтому все поля декодируются через decodeIfPresent:
// новая версия не должна ломаться на старом файле и наоборот.

import Foundation
@preconcurrency import PetCore

struct SaveFile: Codable, Sendable {
    static let version = 1
    static let journalMax = 200
    static let outboxMax = 500

    struct LastAction: Codable, Hashable, Sendable {
        var kind: String
        var source: ActionSource
        var t: Double
        var ok: Bool
        var reason: String?
    }

    /// Срок подписи (build_age). seenT — когда приложение последний раз видело эту сборку.
    struct BuildInfo: Codable, Hashable, Sendable {
        var expiresT: Double
        var seenT: Double
    }

    struct IslandInfo: Codable, Hashable, Sendable {
        var enabled = true
        var startedT: Double?
        var activityId: String?
    }

    struct Flags: Codable, Hashable, Sendable {
        var rulesShown = false
        var widgetHintCount = 0
        var widgetHintT: Double?
        var notifAsked = false
    }

    struct NotifInfo: Codable, Hashable, Sendable {
        var lastSentT: Double?
        /// Времена запланированных уведомлений: по ним считаем, когда ушло последнее.
        var scheduled: [Double] = []
    }

    var v = SaveFile.version
    var rev = 0
    var petId: String
    var deviceId: String
    var seq = 0
    var name = "Шиба"
    var createdT: Double
    var owner: Owner
    var pet: PetState
    /// Состояние, которое хозяин последний раз видел в приложении: от него считается «Пока тебя не было».
    var seen: PetState?
    var lastSeenT: Double?
    var lastStepsT: Double?
    var lastAction: LastAction?
    var journal: [JournalEntry] = []
    /// Для будущей синхронизации и бэкапа: то же, что журнал, но длиннее и чистится после отправки.
    var outbox: [JournalEntry] = []
    var build: BuildInfo?
    var island = IslandInfo()
    var flags = Flags()
    var notif = NotifInfo()
    /// Кошелёк, дневные потолки, капсула и предметы (Economy.swift). Старый файл без поля — стартовый кошелёк.
    var econ = Econ.start(paidSeq: 0)
    /// Открытки дня: ждущие решения и альбом (Postcards.swift).
    var cards = PostcardBook()
    /// Метка для теста «записал приложением — прочитал как виджет».
    var debugMarker: Double?
    /// Вкусы: что хозяин уже видел и что открыто (Tastes.swift). Пустое в файл не пишется.
    var tastes = TasteLog()
    /// Трюки: засчитанные удачи и выученное (Tricks.swift). Пустое в файл не пишется, новому щенку не переходит.
    var tricks = TrickLog()
    /// «Лови мячик» (CatchGame.swift): рекорд и счётчики местных суток для дневного потолка монет.
    /// Простые числа верхним уровнем: старый сейв без них — нули, нули в файл не пишутся.
    var catchBest = 0
    var catchDay = 0
    var catchCoins = 0
    var catchGames = 0
    /// Расчёсывание: когда последний раз и сколько всего (Brush.swift). Пустое в файл не пишется.
    var brush = BrushLog()
    /// Настройка «Комната вечером» (RoomEveningMode.rawValue). nil — по умолчанию (RoomEveningMode.standard);
    /// верхним уровнем: старый сейв без поля читается как раньше, nil в файл не пишется.
    var roomEvening: String?

    init(petId: String, deviceId: String, createdT: Double, owner: Owner, pet: PetState) {
        self.petId = petId
        self.deviceId = deviceId
        self.createdT = createdT
        self.owner = owner
        self.pet = pet
    }

    /// Новый щенок на момент now. Хозяин — со сном по умолчанию и текущим часовым поясом.
    static func fresh(now: Double) -> SaveFile {
        let r = Catalog.rules
        let owner = PetEngine.defaultOwner(r, tzOffsetMin: Clock.tzOffsetMin(at: now))
        var f = SaveFile(petId: UUID().uuidString, deviceId: UUID().uuidString, createdT: now,
                         owner: owner, pet: PetEngine.newPet(r, t: now))
        f.seen = f.pet
        f.lastSeenT = now
        return f
    }

    // MARK: журнал

    mutating func log(_ kind: String, t: Double, source: ActionSource? = nil, ok: Bool? = nil, reason: String? = nil,
                      key: String? = nil, value: Int? = nil) {
        seq += 1
        let e = JournalEntry(id: "\(deviceId):\(seq)", t: t, kind: kind, source: source, ok: ok, reason: reason,
                             key: key, value: value)
        journal.append(e)
        if journal.count > Self.journalMax { journal.removeFirst(journal.count - Self.journalMax) }
        outbox.append(e)
        if outbox.count > Self.outboxMax { outbox.removeFirst(outbox.count - Self.outboxMax) }
    }

    /// Удачные действия в окне (from, to] — для awaySummary.
    func timedActs(from: Double, to: Double) -> [TimedAct] {
        journal.compactMap { (e: JournalEntry) -> TimedAct? in
            guard e.ok == true, e.t > from, e.t <= to, let a = e.action else { return nil }
            return TimedAct(t: e.t, action: a.core)
        }
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case v, rev, petId, deviceId, seq, name, createdT, owner, pet, seen, lastSeenT, lastStepsT, lastAction
        case tastes, tricks, brush
        case journal, outbox, build, island, flags, notif, debugMarker, econ
        case cards
        case catchBest, catchDay, catchCoins, catchGames
        case roomEvening
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? Self.version
        rev = try c.decodeIfPresent(Int.self, forKey: .rev) ?? 0
        petId = try c.decodeIfPresent(String.self, forKey: .petId) ?? UUID().uuidString
        deviceId = try c.decodeIfPresent(String.self, forKey: .deviceId) ?? UUID().uuidString
        seq = try c.decodeIfPresent(Int.self, forKey: .seq) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Шиба"
        // Без питомца файл бессмысленен: пусть это будет ошибкой чтения, а не новым щенком.
        let petJSON = try c.decode(JSONValue.self, forKey: .pet)
        guard petJSON["t"].double != nil, petJSON["hearts"].double != nil, petJSON["alive"].bool != nil else {
            throw DecodingError.dataCorruptedError(forKey: .pet, in: c, debugDescription: "питомец без t/hearts/alive")
        }
        pet = PetState(json: petJSON)
        createdT = try c.decodeIfPresent(Double.self, forKey: .createdT) ?? pet.t
        if let o = try c.decodeIfPresent(JSONValue.self, forKey: .owner) {
            owner = Owner(json: o)
        } else {
            owner = PetEngine.defaultOwner(Catalog.rules, tzOffsetMin: Clock.tzOffsetMin(at: pet.t))
        }
        seen = try c.decodeIfPresent(JSONValue.self, forKey: .seen).map { PetState(json: $0) }
        lastSeenT = try c.decodeIfPresent(Double.self, forKey: .lastSeenT)
        lastStepsT = try c.decodeIfPresent(Double.self, forKey: .lastStepsT)
        lastAction = try? c.decodeIfPresent(LastAction.self, forKey: .lastAction)
        journal = (try? c.decodeIfPresent([JournalEntry].self, forKey: .journal)) ?? []
        outbox = (try? c.decodeIfPresent([JournalEntry].self, forKey: .outbox)) ?? []
        build = try? c.decodeIfPresent(BuildInfo.self, forKey: .build)
        island = (try? c.decodeIfPresent(IslandInfo.self, forKey: .island)) ?? IslandInfo()
        flags = (try? c.decodeIfPresent(Flags.self, forKey: .flags)) ?? Flags()
        notif = (try? c.decodeIfPresent(NotifInfo.self, forKey: .notif)) ?? NotifInfo()
        debugMarker = try c.decodeIfPresent(Double.self, forKey: .debugMarker)
        tastes = (try? c.decodeIfPresent(TasteLog.self, forKey: .tastes)) ?? TasteLog()
        tricks = (try? c.decodeIfPresent(TrickLog.self, forKey: .tricks)) ?? TrickLog()
        brush = (try? c.decodeIfPresent(BrushLog.self, forKey: .brush)) ?? BrushLog()
        // Сейв до экономики: стартовый кошелёк, а уже записанный журнал задним числом не оплачиваем.
        econ = (try? c.decodeIfPresent(Econ.self, forKey: .econ)) ?? Econ.start(paidSeq: seq)
        if econ.paidSeq < 0 { econ.paidSeq = seq }
        cards = (try? c.decodeIfPresent(PostcardBook.self, forKey: .cards)) ?? PostcardBook()
        catchBest = (try? c.decodeIfPresent(Int.self, forKey: .catchBest)) ?? 0
        catchDay = (try? c.decodeIfPresent(Int.self, forKey: .catchDay)) ?? 0
        catchCoins = (try? c.decodeIfPresent(Int.self, forKey: .catchCoins)) ?? 0
        catchGames = (try? c.decodeIfPresent(Int.self, forKey: .catchGames)) ?? 0
        roomEvening = try? c.decodeIfPresent(String.self, forKey: .roomEvening)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(v, forKey: .v)
        try c.encode(rev, forKey: .rev)
        try c.encode(petId, forKey: .petId)
        try c.encode(deviceId, forKey: .deviceId)
        try c.encode(seq, forKey: .seq)
        try c.encode(name, forKey: .name)
        try c.encode(createdT, forKey: .createdT)
        try c.encode(PetCodec.json(owner), forKey: .owner)
        try c.encode(PetCodec.json(pet), forKey: .pet)
        try c.encodeIfPresent(seen.map { PetCodec.json($0) }, forKey: .seen)
        try c.encodeIfPresent(lastSeenT, forKey: .lastSeenT)
        try c.encodeIfPresent(lastStepsT, forKey: .lastStepsT)
        try c.encodeIfPresent(lastAction, forKey: .lastAction)
        try c.encode(journal, forKey: .journal)
        try c.encode(outbox, forKey: .outbox)
        try c.encodeIfPresent(build, forKey: .build)
        try c.encode(island, forKey: .island)
        try c.encode(flags, forKey: .flags)
        try c.encode(notif, forKey: .notif)
        try c.encodeIfPresent(debugMarker, forKey: .debugMarker)
        if !tastes.isEmpty { try c.encode(tastes, forKey: .tastes) }
        if !tricks.isEmpty { try c.encode(tricks, forKey: .tricks) }
        if !brush.isEmpty { try c.encode(brush, forKey: .brush) }
        try c.encode(econ, forKey: .econ)
        try c.encode(cards, forKey: .cards)
        if catchBest != 0 { try c.encode(catchBest, forKey: .catchBest) }
        if catchDay != 0 { try c.encode(catchDay, forKey: .catchDay) }
        if catchCoins != 0 { try c.encode(catchCoins, forKey: .catchCoins) }
        if catchGames != 0 { try c.encode(catchGames, forKey: .catchGames) }
        try c.encodeIfPresent(roomEvening, forKey: .roomEvening)
    }
}

/// Запись журнала. kind: act.<тип>, ev.<событие>.<ключ>, clock_back, sign_pause, set_bed.
struct JournalEntry: Codable, Hashable, Sendable {
    let id: String
    let t: Double
    let kind: String
    var source: ActionSource?
    var ok: Bool?
    var reason: String?
    var key: String?
    var value: Int?

    /// Действие для awaySummary (только act.*).
    var action: PetAction? {
        guard kind.hasPrefix("act.") else { return nil }
        return PetAction(kind: String(kind.dropFirst(4)), key: key, value: value)
    }
}

/// PetState и Owner ↔ JSONValue в формате core/vectors. Опционалы пишутся как null.
enum PetCodec {
    static func json(_ s: PetState) -> JSONValue {
        func num(_ d: Double?) -> JSONValue { d.map { .number($0) } ?? .null }
        var needs: [String: JSONValue] = [:]
        for (n, v) in s.needs { needs[n.rawValue] = .number(v) }
        var grace: [String: JSONValue] = [:]
        for (d, v) in s.grace { grace[d.rawValue] = .number(v) }
        var home: [String: JSONValue] = [:]
        for (l, v) in s.home { home[l.rawValue] = .number(Double(v)) }
        var cooldowns: [String: JSONValue] = [:]
        for (k, v) in s.cooldowns { cooldowns[k] = .number(v) }
        var finds: [String: JSONValue] = [:]
        for (k, v) in s.finds { finds[k] = .number(Double(v)) }
        let outing: JSONValue = s.outing.map {
            .object(["from": .number($0.from), "until": .number($0.until), "find": .string($0.find)])
        } ?? .null
        return .object([
            "t": .number(s.t),
            "needs": .object(needs),
            "hearts": .number(s.hearts),
            "grace": .object(grace),
            "lastChanceH": num(s.lastChanceH),
            "napUntil": num(s.napUntil),
            "bathUntil": num(s.bathUntil),
            "lastHeartLossT": num(s.lastHeartLossT),
            "cooldowns": .object(cooldowns),
            "home": .object(home),
            "alive": .bool(s.alive),
            "diedAt": num(s.diedAt),
            "cause": s.cause.map { .string($0.rawValue) } ?? .null,
            // прогулка; в старых сохранениях полей нет — PetState(json:) читает их как «дома, альбом пуст»
            "outing": outing,
            "finds": .object(finds),
            "pantry": .number(s.pantry),   // запас кухни; в старых сохранениях нет — пусто
        ])
    }

    static func json(_ o: Owner) -> JSONValue {
        .object([
            "bedMin": .number(Double(o.bedMin)),
            "wakeMin": .number(Double(o.wakeMin)),
            "tzOffsetMin": .number(Double(o.tzOffsetMin)),
        ])
    }
}
