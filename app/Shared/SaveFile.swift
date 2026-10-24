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
    /// Кадры 3D для открыток ещё не разобранных дней (PostcardPhotos.swift). Пустое в файл не пишется.
    var shots = ShotBook()
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
    /// «Блок Дуо» (BlockDuo.swift, волна 12): то же самое — рекорд и счётчики суток. Нули в файл не пишутся.
    var blockduoBest = 0
    var blockduoDay = 0
    var blockduoCoins = 0
    var blockduoGames = 0
    /// «Щенок против зомби» (ZombieRun.swift, волна 13): рекорд и счётчики суток. Нули в файл не пишутся.
    var zombieBest = 0
    var zombieDay = 0
    var zombieCoins = 0
    var zombieGames = 0
    /// Расчёсывание: когда последний раз и сколько всего (Brush.swift). Пустое в файл не пишется.
    var brush = BrushLog()
    /// Настройка «Комната вечером» (RoomEveningMode.rawValue). nil — по умолчанию (RoomEveningMode.standard);
    /// верхним уровнем: старый сейв без поля читается как раньше, nil в файл не пишется.
    var roomEvening: String?
    /// Надето (Wear.swift): место (head/neck/back) → id предмета из капсулы. Пустое в файл не пишется,
    /// новому щенку переходит вместе с предметами.
    var worn: [String: String] = [:]
    /// Сон хозяина (OwnerSleep.swift): касания по ночам, ручное окно, «Доброе утро» и «Отбой» по разу.
    /// Пустое в файл не пишется, новому щенку переходит: это привычки хозяина, не собаки.
    var sleep = SleepLog()
    /// Память питомца (Memories.swift): яркие события с датой. Пустое в файл не пишется, новому щенку не переходит.
    var memories = MemoryBook()
    /// Уход по дням для характера (Traits.swift). Пустое в файл не пишется, новому щенку не переходит.
    var care = CareTally()
    /// Волна 11. Что стоит на полке в комнате (ItemCatalog.decor), nil — пусто. nil в файл не пишется.
    var shelf: String?
    /// Чем играем в «Поиграть» (ItemCatalog.toys), nil — обычный мячик. nil в файл не пишется.
    var toy: String?
    /// Лавка дня (ShopDaily): что на витрине и что уже куплено сегодня. nil — лавку ещё не открывали.
    var shop: ShopDay?
    /// Привычки хозяина из «Команд» (Habits.swift): сегодня, последний раз и всего. Пустое в файл не пишется,
    /// новому щенку переходит — это отметки хозяина, не пса.
    var habits = HabitLog()
    /// Кухня шефа (Cooking.swift): сколько блюд сегодня, когда последнее, всего, день бонуса. Пустое не пишется,
    /// новому щенку переходит — кухня остаётся вместе с домом.
    var cooking = CookLog()
    /// Волна 32. Мягкая смерть (Runaway.swift): поиски сбежавшего пса и его возвращения. Пустое не пишется,
    /// новому щенку не переходит — это история того пса.
    var runaway = Runaway.Log()
    /// Волна 12. Свой персонаж вместо Шибы (CharacterStore, id папки), nil — Шиба. nil в файл не пишется,
    /// новому щенку переходит: это выбор хозяина, как вещи.
    var character: String?
    /// Волна 14. Имя своего персонажа из его character.json — для шапки, виджета, острова и реплик, когда
    /// character задан. Пишется при выборе и переустановке пака (виджет пак не читает: модель ему не нужна).
    /// nil в файл не пишется, переходит щенку вместе с character.
    var characterName: String?
    /// Волна 15. Пояс рождения (минуты к востоку от UTC). День рождения — календарная дата появления щенка
    /// там, где он родился: перелёт и смена пояса его не сдвигают. nil — сейв старше волны 15: PetStore при
    /// первой записи ставит пояс телефона на момент рождения. Новому щенку — свой, не переходит.
    var birthTz: Int?
    /// Волна 18. Чему хозяин уже научился (NeedHint.swift, Tips): поглаживания пальцем и разовые подсказки жестов.
    /// Пустое в файл не пишется, новому щенку переходит: это знание хозяина, а не собаки.
    var tips = TipLog()
    /// Волна 32: учёт клочков ✂️ — дни заботы, сундук недели, рекорды, находки, разовые награды (Premium.swift).
    var shardLog = ShardLog()

    /// Местные сутки рождения (номер DayKey) — в поясе рождения. Отсюда считаются дни вместе и дни рождения.
    var bornDay: Int { DayKey.of(createdT, tzOffsetMin: birthTz ?? Clock.tzOffsetMin(at: createdT)) }

    /// Как зовут того, кто в комнате: имя своего персонажа, если он выбран, иначе name («Шиба»).
    var petName: String {
        guard character != nil,
              let n = characterName.map(PetNames.clean), !n.isEmpty else { return name }
        return n
    }

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
        f.birthTz = owner.tzOffsetMin
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
        case cards, shots
        case catchBest, catchDay, catchCoins, catchGames
        case blockduoBest, blockduoDay, blockduoCoins, blockduoGames
        case zombieBest, zombieDay, zombieCoins, zombieGames
        case roomEvening
        case worn
        case sleep
        case memories, care
        case shelf, toy, shop
        case habits
        case cooking
        case runaway
        case character, characterName
        case birthTz
        case tips
        case shardLog
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
        // Поштучно: одна непрочитанная запись (новый источник из будущей сборки) не обнуляет весь журнал и outbox.
        journal = ((try? c.decodeIfPresent([LossyEntry].self, forKey: .journal)) ?? []).compactMap(\.value)
        outbox = ((try? c.decodeIfPresent([LossyEntry].self, forKey: .outbox)) ?? []).compactMap(\.value)
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
        shots = (try? c.decodeIfPresent(ShotBook.self, forKey: .shots)) ?? ShotBook()
        catchBest = (try? c.decodeIfPresent(Int.self, forKey: .catchBest)) ?? 0
        catchDay = (try? c.decodeIfPresent(Int.self, forKey: .catchDay)) ?? 0
        catchCoins = (try? c.decodeIfPresent(Int.self, forKey: .catchCoins)) ?? 0
        catchGames = (try? c.decodeIfPresent(Int.self, forKey: .catchGames)) ?? 0
        blockduoBest = (try? c.decodeIfPresent(Int.self, forKey: .blockduoBest)) ?? 0
        blockduoDay = (try? c.decodeIfPresent(Int.self, forKey: .blockduoDay)) ?? 0
        blockduoCoins = (try? c.decodeIfPresent(Int.self, forKey: .blockduoCoins)) ?? 0
        blockduoGames = (try? c.decodeIfPresent(Int.self, forKey: .blockduoGames)) ?? 0
        zombieBest = (try? c.decodeIfPresent(Int.self, forKey: .zombieBest)) ?? 0
        zombieDay = (try? c.decodeIfPresent(Int.self, forKey: .zombieDay)) ?? 0
        zombieCoins = (try? c.decodeIfPresent(Int.self, forKey: .zombieCoins)) ?? 0
        zombieGames = (try? c.decodeIfPresent(Int.self, forKey: .zombieGames)) ?? 0
        roomEvening = try? c.decodeIfPresent(String.self, forKey: .roomEvening)
        worn = (try? c.decodeIfPresent([String: String].self, forKey: .worn)) ?? [:]
        sleep = (try? c.decodeIfPresent(SleepLog.self, forKey: .sleep)) ?? SleepLog()
        memories = (try? c.decodeIfPresent(MemoryBook.self, forKey: .memories)) ?? MemoryBook()
        care = (try? c.decodeIfPresent(CareTally.self, forKey: .care)) ?? CareTally()
        shelf = try? c.decodeIfPresent(String.self, forKey: .shelf)
        toy = try? c.decodeIfPresent(String.self, forKey: .toy)
        shop = try? c.decodeIfPresent(ShopDay.self, forKey: .shop)
        habits = (try? c.decodeIfPresent(HabitLog.self, forKey: .habits)) ?? HabitLog()
        cooking = (try? c.decodeIfPresent(CookLog.self, forKey: .cooking)) ?? CookLog()
        runaway = (try? c.decodeIfPresent(Runaway.Log.self, forKey: .runaway)) ?? Runaway.Log()
        character = try? c.decodeIfPresent(String.self, forKey: .character)
        characterName = try? c.decodeIfPresent(String.self, forKey: .characterName)
        birthTz = try? c.decodeIfPresent(Int.self, forKey: .birthTz)
        tips = (try? c.decodeIfPresent(TipLog.self, forKey: .tips)) ?? TipLog()
        shardLog = (try? c.decodeIfPresent(ShardLog.self, forKey: .shardLog)) ?? ShardLog()
        // Старый сейв без учёта: прошлый журнал клочками не платит — считаем с текущей записи.
        if shardLog.seenSeq < 0 || shardLog.isEmpty { shardLog.seenSeq = seq }
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
        if !shots.isEmpty { try c.encode(shots, forKey: .shots) }
        if catchBest != 0 { try c.encode(catchBest, forKey: .catchBest) }
        if catchDay != 0 { try c.encode(catchDay, forKey: .catchDay) }
        if catchCoins != 0 { try c.encode(catchCoins, forKey: .catchCoins) }
        if catchGames != 0 { try c.encode(catchGames, forKey: .catchGames) }
        if blockduoBest != 0 { try c.encode(blockduoBest, forKey: .blockduoBest) }
        if blockduoDay != 0 { try c.encode(blockduoDay, forKey: .blockduoDay) }
        if blockduoCoins != 0 { try c.encode(blockduoCoins, forKey: .blockduoCoins) }
        if blockduoGames != 0 { try c.encode(blockduoGames, forKey: .blockduoGames) }
        if zombieBest != 0 { try c.encode(zombieBest, forKey: .zombieBest) }
        if zombieDay != 0 { try c.encode(zombieDay, forKey: .zombieDay) }
        if zombieCoins != 0 { try c.encode(zombieCoins, forKey: .zombieCoins) }
        if zombieGames != 0 { try c.encode(zombieGames, forKey: .zombieGames) }
        try c.encodeIfPresent(roomEvening, forKey: .roomEvening)
        if !worn.isEmpty { try c.encode(worn, forKey: .worn) }
        if !sleep.isEmpty { try c.encode(sleep, forKey: .sleep) }
        if !memories.isEmpty { try c.encode(memories, forKey: .memories) }
        if !care.isEmpty { try c.encode(care, forKey: .care) }
        try c.encodeIfPresent(shelf, forKey: .shelf)
        try c.encodeIfPresent(toy, forKey: .toy)
        try c.encodeIfPresent(shop, forKey: .shop)
        if !habits.isEmpty { try c.encode(habits, forKey: .habits) }
        if !cooking.isEmpty { try c.encode(cooking, forKey: .cooking) }
        if !runaway.isEmpty { try c.encode(runaway, forKey: .runaway) }
        try c.encodeIfPresent(character, forKey: .character)
        try c.encodeIfPresent(characterName, forKey: .characterName)
        try c.encodeIfPresent(birthTz, forKey: .birthTz)
        if !tips.isEmpty { try c.encode(tips, forKey: .tips) }
        if !shardLog.isEmpty { try c.encode(shardLog, forKey: .shardLog) }
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

extension JournalEntry {
    enum CodingKeys: String, CodingKey { case id, t, kind, source, ok, reason, key, value }

    /// id, t и kind обязательны; незнакомый источник или кривое поле — nil, запись остаётся.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        t = try c.decode(Double.self, forKey: .t)
        kind = try c.decode(String.self, forKey: .kind)
        source = try? c.decodeIfPresent(ActionSource.self, forKey: .source)
        ok = try? c.decodeIfPresent(Bool.self, forKey: .ok)
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
        key = try? c.decodeIfPresent(String.self, forKey: .key)
        value = try? c.decodeIfPresent(Int.self, forKey: .value)
    }
}

/// Запись журнала, которая не валит весь массив, если сама не разобралась.
private struct LossyEntry: Decodable {
    let value: JournalEntry?
    init(from decoder: Decoder) throws { value = try? JournalEntry(from: decoder) }
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
