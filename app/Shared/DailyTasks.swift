// Волна 42 J (RESEARCH/18-progression.md, RESEARCH/20-tycoon-design.md): задания дня.
// Каждые сутки — 2 задания (третье с ур. 7, открытие DogLevel «tasks.3») из пула дел, которые уже пишутся в журнал:
// покормить, погладить, поиграть, расчесать, погулять, сходить в место на карте, собрать копилку двора, приготовить.
// В пул идёт только то, что сейчас доступно (места — с ур. 2, двор — когда есть станция, кухня — с «Кухней шефа»).
// Выбор по суткам детерминирован (DayKey + StableHash): сколько ни открывай — те же задания.
// Прогресс — по журналу (f.log), один раз на запись: свой курсор seenSeq, как у DogLevel и Shards.
// Выполнено — монеты сразу и запись task.done (DogLevel даёт 5 опыта, до 3 в сутки); все задания дня — ещё 1 ✂️
// (запись task.all). Сутки не откатываются: перевод часов назад и перелёт на запад не дают второй набор.
// Раз в сутки одно невыполненное задание можно бесплатно заменить. Цифры — раздел "daily_tasks"
// в config/economy.json (нет раздела — умолчания ниже). Решения — DECISIONS.md, «Волна 42 J».

import Foundation
@preconcurrency import PetCore

struct DailyTaskConfig: Sendable {
    /// Заданий в сутки до открытия «tasks.3».
    var count = 2
    /// Монеты за задание: base + perLevel × уровень пса, к ближайшему кратному round.
    var coinBase = 15
    var coinPerLevel = 3
    var coinRound = 5
    /// За все задания дня.
    var allShards = 1
    var allCoins = 0
    /// Замен в сутки (бесплатно).
    var swaps = 1
    /// Сколько раз сделать; 0 — задания нет в пуле.
    var need: [String: Int] = DailyTasks.defaultNeed

    static let shared = DailyTaskConfig(json: Catalog.economy() ?? .null)

    init() {}

    /// e — economy.json целиком (или кусок {"daily_tasks": …}). Нет раздела — умолчания.
    init(json e: JSONValue) {
        func int(_ v: JSONValue, _ d: Int) -> Int { v.double.map { Int($0) } ?? d }
        let p = e["daily_tasks"]
        count = max(1, int(p["count"], count))
        coinBase = max(0, int(p["coins"]["base"], coinBase))
        coinPerLevel = max(0, int(p["coins"]["per_level"], coinPerLevel))
        coinRound = max(1, int(p["coins"]["round"], coinRound))
        allShards = max(0, int(p["all_done"]["shards"], allShards))
        allCoins = max(0, int(p["all_done"]["coins"], allCoins))
        swaps = max(0, int(p["swaps_per_day"], swaps))
        for (k, v) in p["need"].object {
            if let n = v.double { need[k] = max(0, Int(n)) }
        }
    }

    func need(_ id: String) -> Int { need[id] ?? 0 }

    /// Монеты за одно задание на уровне пса l.
    func coins(level l: Int) -> Int {
        let raw = coinBase + coinPerLevel * max(1, l)
        guard coinRound > 1 else { return raw }
        return max(coinRound, (raw + coinRound / 2) / coinRound * coinRound)
    }
}

/// Задание на сутки: что сделать (id из пула), сколько раз, сколько сделано, награда, когда выполнено.
struct DailyTask: Codable, Hashable, Sendable {
    var id: String
    var need: Int
    var n = 0
    var coins: Int
    var doneT: Double?

    var done: Bool { doneT != nil }
}

/// Последнее выполненное задание — для тоста. shards > 0 — этим же заданием закрыты все задания дня.
struct TaskWin: Codable, Hashable, Sendable {
    var task: String
    var coins: Int
    var shards: Int
    var allCoins: Int
    var t: Double
}

/// Поле `tasks` в SaveFile. Пустое не пишется — старые сейвы читаются без него.
/// Новому щенку переходит текущий день как есть (без второго набора и второй оплаты) — DECISIONS, волна 42 J.
struct DailyTasksLog: Codable, Hashable, Sendable {
    var started = false
    /// Курсор журнала: записи со своим deviceId и seq не больше этого уже учтены.
    var seenSeq = 0
    /// Сутки (DayKey) набора items. Назад не откатываются.
    var day = 0
    var items: [DailyTask] = []
    /// Оплачены ли «все задания дня».
    var allPaid = false
    /// Замен за сутки и что заменено (заменённое не вернётся в тот же день).
    var swaps = 0
    var out: [String] = []
    /// Выполнено заданий всего и дней «все задания».
    var total = 0
    var allDays = 0
    var last: TaskWin?

    init() {}

    var isEmpty: Bool { self == DailyTasksLog() }

    enum CodingKeys: String, CodingKey {
        case started, seenSeq, day, items, allPaid, swaps, out, total, allDays, last
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        started = (try? c.decodeIfPresent(Bool.self, forKey: .started)) ?? false
        seenSeq = (try? c.decodeIfPresent(Int.self, forKey: .seenSeq)) ?? 0
        day = (try? c.decodeIfPresent(Int.self, forKey: .day)) ?? 0
        items = (try? c.decodeIfPresent([DailyTask].self, forKey: .items)) ?? []
        allPaid = (try? c.decodeIfPresent(Bool.self, forKey: .allPaid)) ?? false
        swaps = (try? c.decodeIfPresent(Int.self, forKey: .swaps)) ?? 0
        out = (try? c.decodeIfPresent([String].self, forKey: .out)) ?? []
        total = (try? c.decodeIfPresent(Int.self, forKey: .total)) ?? 0
        allDays = (try? c.decodeIfPresent(Int.self, forKey: .allDays)) ?? 0
        last = try? c.decodeIfPresent(TaskWin.self, forKey: .last)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if started { try c.encode(started, forKey: .started) }
        if seenSeq != 0 { try c.encode(seenSeq, forKey: .seenSeq) }
        if day != 0 { try c.encode(day, forKey: .day) }
        if !items.isEmpty { try c.encode(items, forKey: .items) }
        if allPaid { try c.encode(allPaid, forKey: .allPaid) }
        if swaps != 0 { try c.encode(swaps, forKey: .swaps) }
        if !out.isEmpty { try c.encode(out, forKey: .out) }
        if total != 0 { try c.encode(total, forKey: .total) }
        if allDays != 0 { try c.encode(allDays, forKey: .allDays) }
        try c.encodeIfPresent(last, forKey: .last)
    }

    /// Новому щенку: тот же день, те же задания и оплаты (иначе «начать заново» давало бы второй набор),
    /// курсор — с нуля (журнал у щенка новый), тост — нет.
    func carriedOver() -> DailyTasksLog {
        guard started else { return DailyTasksLog() }
        var s = self
        s.seenSeq = 0
        s.last = nil
        return s
    }
}

/// Что показать в листе «Задания дня».
struct TaskBoard: Equatable, Sendable {
    var day: Int
    var items: [DailyTask]
    var allPaid: Bool
    /// ✂️ и монеты за все задания дня.
    var allShards: Int
    var allCoins: Int
    /// Сколько замен осталось сегодня.
    var swapsLeft: Int

    var doneCount: Int { items.filter(\.done).count }
}

/// Почему заменить нельзя.
enum TaskSwapRefusal: String, Error, Sendable {
    case noSwaps, notFound, done, noOther, off
}

enum DailyTasks {
    /// Порядок пула (от него зависит выбор по суткам — не переставлять) и вид записи журнала для каждого задания.
    static let pool: [(id: String, kind: String)] = [
        ("feed", "act.feed"), ("pet", "act.pet"), ("play", "act.play"), ("brush", Brush.actKind),
        ("walk", "act.walk"), ("trip", "place.go"), ("collect", "yard.collect"), ("cook", Cooking.reactKind),
    ]
    static let defaultNeed: [String: Int] = [
        "feed": 2, "pet": 3, "play": 2, "brush": 1, "walk": 1, "trip": 1, "collect": 1, "cook": 1,
    ]
    /// Записи журнала: опыт за задание (DogLevel, правило task.done), все задания дня, замена.
    static let doneKind = "task.done"
    static let allKind = "task.all"
    static let swapKind = "task.swap"
    /// Открытие третьего задания в DogLevel.
    static let thirdId = "tasks.3"

    /// Задания включены. В UI-тестах — только с сидом tasks*: иначе монеты и тосты заданий меняли бы чужие проверки
    /// кошелька и тостов. Юнит-тесты могут переключать.
    nonisolated(unsafe) static var enabled: Bool = !Env.isUITest || (Env.value("PET_SEED")?.hasPrefix("tasks") ?? false)

    // MARK: пул и выбор

    /// Сколько заданий в сутки на уровне l.
    static func slots(level l: Int, _ cfg: DailyTaskConfig = .shared) -> Int {
        max(cfg.count, DogLevel.maxValue(thirdId, level: l) ?? 0)
    }

    /// Дело доступно сейчас: места открыты уровнем, во дворе есть станция, у дома есть «Кухня шефа».
    static func available(_ id: String, _ f: SaveFile, level l: Int) -> Bool {
        switch id {
        case "trip": return !Places.unlocked(dogLevel: l).isEmpty
        case "collect": return !f.yard.stations.isEmpty
        case "cook": return Cooking.canCook(f.pet)
        default: return true
        }
    }

    /// Пул на сейчас: задания с need > 0 и доступные, в порядке pool.
    static func candidates(_ f: SaveFile, level l: Int, _ cfg: DailyTaskConfig = .shared) -> [String] {
        pool.map(\.id).filter { cfg.need($0) > 0 && available($0, f, level: l) }
    }

    /// Индекс из n по ключу: один и тот же на одних и тех же сутках.
    static func index(_ key: String, _ n: Int) -> Int {
        Int(StableRandom.mix(StableHash.fnv1a(key)) % UInt64(max(1, n)))
    }

    static func make(_ id: String, level l: Int, _ cfg: DailyTaskConfig) -> DailyTask {
        DailyTask(id: id, need: max(1, cfg.need(id)), coins: cfg.coins(level: l))
    }

    /// Добрать задания суток day до slots: место k — по ключу "tasks:<day>:<k>" из того, чего ещё нет.
    static func fill(_ items: [DailyTask], day: Int, _ f: SaveFile, level l: Int, exclude: [String] = [],
                     _ cfg: DailyTaskConfig = .shared) -> [DailyTask] {
        var out = items
        var cand = candidates(f, level: l, cfg).filter { id in !out.contains { $0.id == id } && !exclude.contains(id) }
        let want = slots(level: l, cfg)
        while out.count < want, !cand.isEmpty {
            let k = index("tasks:\(day):\(out.count)", cand.count)
            out.append(make(cand.remove(at: k), level: l, cfg))
        }
        return out
    }

    /// Задание, которое двигает запись журнала. act.* — только удачные, остальное — если не отказ.
    static func taskId(for e: JournalEntry) -> String? {
        guard let id = pool.first(where: { $0.kind == e.kind })?.id else { return nil }
        if e.kind.hasPrefix("act.") ? e.ok != true : e.ok == false { return nil }
        return id
    }

    // MARK: начисление

    /// Учесть новые записи журнала: прогресс, монеты, task.done, ✂️ за все. Повторный вызов ничего не добавляет.
    /// Звать из PetRunner.settleRewards (первым: task.done в той же записи даёт опыт).
    static func settle(_ f: inout SaveFile, now: Double, _ cfg: DailyTaskConfig = .shared) {
        guard enabled else { return }
        var s = f.tasks
        let today = DayKey.of(now)
        let lvl = DogLevel.level(f)

        func roll(to d: Int) {
            s.day = d
            s.items = []
            s.allPaid = false
            s.swaps = 0
            s.out = []
            s.items = fill([], day: d, f, level: lvl, cfg)
        }
        // Первый раз (и старый сейв): сутки — сегодня; сегодняшние записи журнала засчитываются, прошлые — нет.
        if !s.started {
            s.started = true
            roll(to: today)
        }

        // 1. Новые записи журнала этого устройства.
        var fresh: [(id: String, t: Double, day: Int)] = []
        let prefix = "\(f.deviceId):"
        for e in f.journal {
            guard e.id.hasPrefix(prefix), let q = Int(e.id.dropFirst(prefix.count)), q > s.seenSeq else { continue }
            s.seenSeq = q
            if let id = taskId(for: e) { fresh.append((id, e.t, DayKey.of(e.t))) }
        }

        // 2. По порядку суток: прошлые сутки (часы назад, перелёт на запад) не засчитываются, новые — новый набор.
        let ordered = fresh.enumerated().sorted { ($0.element.day, $0.offset) < ($1.element.day, $1.offset) }
        for it in ordered.map(\.element) {
            if it.day < s.day { continue }
            if it.day > s.day { roll(to: it.day) }
            guard let i = s.items.firstIndex(where: { $0.id == it.id && !$0.done }) else { continue }
            s.items[i].n += 1
            guard s.items[i].n >= s.items[i].need else { continue }
            s.items[i].doneT = it.t
            let task = s.items[i]
            Economy.grant(&f, coins: task.coins)
            f.log(doneKind, t: it.t, key: task.id, value: task.coins)
            s.total += 1
            var win = TaskWin(task: task.id, coins: task.coins, shards: 0, allCoins: 0, t: now)
            if !s.allPaid, s.items.allSatisfy(\.done) {
                s.allPaid = true
                s.allDays += 1
                Economy.grant(&f, coins: cfg.allCoins, shards: cfg.allShards)
                f.shardLog.earned += cfg.allShards
                f.log(allKind, t: it.t, value: cfg.allShards)
                win.shards = cfg.allShards
                win.allCoins = cfg.allCoins
            }
            s.last = win
        }

        // 3. Сутки сменились без записей — новый набор; уровень дорос до третьего задания — добрать.
        if today > s.day { roll(to: today) }
        if !s.allPaid { s.items = fill(s.items, day: s.day, f, level: lvl, exclude: s.out, cfg) }
        f.tasks = s
    }

    /// Для листа: задания на сейчас без записи в сейв (settle на копии).
    static func board(_ f: SaveFile, now: Double, _ cfg: DailyTaskConfig = .shared) -> TaskBoard {
        var c = f
        settle(&c, now: now, cfg)
        let s = c.tasks
        return TaskBoard(day: s.day, items: s.items, allPaid: s.allPaid, allShards: cfg.allShards,
                         allCoins: cfg.allCoins, swapsLeft: max(0, cfg.swaps - s.swaps))
    }

    // MARK: замена

    /// Заменить невыполненное задание id другим из пула (раз в сутки, бесплатно). Прогресс заменённого пропадает.
    static func swap(_ id: String, in f: inout SaveFile, now: Double,
                     _ cfg: DailyTaskConfig = .shared) -> Result<DailyTask, TaskSwapRefusal> {
        guard enabled else { return .failure(.off) }
        PetRunner.catchUp(&f, now: now)
        settle(&f, now: now, cfg)   // catchUp при часах назад возвращается рано — сутки догоняем сами
        var s = f.tasks
        guard s.swaps < cfg.swaps else { return .failure(.noSwaps) }
        guard let i = s.items.firstIndex(where: { $0.id == id }) else { return .failure(.notFound) }
        guard !s.items[i].done else { return .failure(.done) }
        let lvl = DogLevel.level(f)
        let cand = candidates(f, level: lvl, cfg).filter { c in !s.items.contains { $0.id == c } && !s.out.contains(c) }
        guard !cand.isEmpty else { return .failure(.noOther) }
        let task = make(cand[index("tasks:\(s.day):swap:\(s.swaps)", cand.count)], level: lvl, cfg)
        s.items[i] = task
        s.out.append(id)
        s.swaps += 1
        f.tasks = s
        f.log(swapKind, t: max(now, f.pet.t), key: id)
        PetRunner.settleRewards(&f, now: now)
        return .success(task)
    }

    /// Через стор: одна запись под замком.
    static func performSwap(_ id: String, store: PetStore = .shared,
                            now: Double = Clock.now()) throws -> Result<DailyTask, TaskSwapRefusal> {
        try store.mutate { f in swap(id, in: &f, now: now) }
    }
}

// MARK: - Тексты

enum DailyTaskText {
    static let title = "Задания дня"

    static func emoji(_ id: String) -> String {
        switch id {
        case "feed": return "🍖"
        case "pet": return "🤲"
        case "play": return "🎾"
        case "brush": return "🪮"
        case "walk": return "🦮"
        case "trip": return "🗺️"
        case "collect": return "🏡"
        case "cook": return "🍳"
        default: return "⭐"
        }
    }

    /// «Покормить 2 раза», «Расчесать».
    static func name(_ t: DailyTask) -> String {
        let base: String
        switch t.id {
        case "feed": base = "Покормить"
        case "pet": base = "Погладить"
        case "play": base = "Поиграть"
        case "brush": base = "Расчесать"
        case "walk": base = "Сходить погулять"
        case "trip": base = "Сходить в место на карте"
        case "collect": base = "Собрать копилку во дворе"
        case "cook": base = "Приготовить блюдо"
        default: base = t.id
        }
        guard t.need > 1 else { return base }
        return "\(base) \(t.need) \(EconText.plural(t.need, "раз", "раза", "раз"))"
    }

    /// «1 / 3» или «Готово».
    static func progress(_ t: DailyTask) -> String {
        t.done ? "Готово" : "\(min(t.n, t.need)) / \(t.need)"
    }

    /// «+20 🪙».
    static func reward(_ t: DailyTask) -> String { "+\(t.coins) 🪙" }

    /// Строка «за все задания»: «Все задания: +1 ✂️».
    static func allReward(_ b: TaskBoard) -> String {
        var parts: [String] = []
        if b.allShards > 0 { parts.append("+\(b.allShards) ✂️") }
        if b.allCoins > 0 { parts.append("+\(b.allCoins) 🪙") }
        return parts.isEmpty ? "Все задания" : "Все задания: " + parts.joined(separator: " · ")
    }

    /// Счёт на кнопке: «Задания дня · 1 / 2».
    static func badge(_ b: TaskBoard) -> String { "\(title) · \(b.doneCount) / \(b.items.count)" }

    /// Тост: «Задание дня: Покормить 2 раза · +20 🪙» или «Все задания дня! … · +1 ✂️».
    static func toast(_ w: TaskWin, _ f: SaveFile) -> String {
        let t = f.tasks.items.first { $0.id == w.task } ?? DailyTask(id: w.task, need: 1, coins: w.coins)
        var parts = ["+\(w.coins) 🪙"]
        if w.allCoins > 0 { parts.append("+\(w.allCoins) 🪙") }
        if w.shards > 0 {
            parts.append("+\(w.shards) ✂️")
            return "Все задания дня! \(name(t)) · " + parts.joined(separator: " · ")
        }
        return "Задание дня: \(name(t)) · " + parts.joined(separator: " · ")
    }

    static func swapRefusal(_ r: TaskSwapRefusal) -> String {
        switch r {
        case .noSwaps: return "Заменить можно раз в день"
        case .done: return "Это задание уже выполнено"
        case .noOther: return "Пока нечем заменить"
        case .notFound, .off: return "Не получилось заменить"
        }
    }
}
