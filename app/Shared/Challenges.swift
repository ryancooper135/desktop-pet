// Волна 35 K (RESEARCH/20-tycoon-design.md §6): челлендж дня в мини-играх.
// Каждый день — одна игра по кругу (Мячик → Блок Дуо → Зомби); цель = max(база, 70 % личного рекорда),
// округлённая по-человечески. Открывается с ур. 11 (DogLevel «games.challenge»). Засчитывается только
// настоящий раунд (не «просто так»): 1 ✂️ и запись game.challenge в журнал — DogLevel.settle даёт +10 опыта.
// Раз в день; переигрывать можно, но без награды. Три выполненных дня за неделю (с понедельника, как сундук
// Shards.week) — ещё 3 ✂️. Цифры — раздел "challenges" в config/economy.json (нет раздела — умолчания).

import Foundation
@preconcurrency import PetCore

/// Мини-игра с рекордом — она же игра челленджа. rawValue — ключ рекордов. Это единственный список игр с рекордом:
/// Shards.recordGames и Shards.records (и цель «Все игры») берут его отсюда (волна 40 E).
enum ChallengeGame: String, Codable, CaseIterable, Hashable, Sendable {
    case ball = "catch"
    case blockduo
    case zombie

    /// Короткое имя для плашки.
    var title: String {
        switch self {
        case .ball: return "Мячик"
        case .blockduo: return "Блок Дуо"
        case .zombie: return "Зомби"
        }
    }

    /// Личный рекорд этой игры в сейве.
    func record(_ f: SaveFile) -> Int {
        switch self {
        case .ball: return f.catchBest
        case .blockduo: return f.blockduoBest
        case .zombie: return f.zombieBest
        }
    }
}

struct ChallengeConfig: Sendable {
    /// Базовые цели в очках игры. Зомби — очки, не секунды: раунд всего 50 с (см. DECISIONS, волна 35 K).
    var bases: [ChallengeGame: Int] = [.ball: 25, .blockduo: 2000, .zombie: 200]
    /// Доля рекорда в цели.
    var ratio = 0.7
    /// Награда за день.
    var shards = 1
    /// Сколько дней за неделю нужно для бонуса и сколько он даёт.
    var weekNeed = 3
    var weekShards = 3

    static let shared = ChallengeConfig(json: Catalog.economy() ?? .null)

    init() {}

    /// e — economy.json целиком (или кусок {"challenges": …}). Нет раздела — умолчания.
    init(json e: JSONValue) {
        func int(_ v: JSONValue, _ d: Int) -> Int { v.double.map { Int($0) } ?? d }
        let p = e["challenges"]
        for g in ChallengeGame.allCases {
            if let n = p["base"][g.rawValue].double { bases[g] = max(1, Int(n)) }
        }
        if let r = p["ratio"].double { ratio = min(1, max(0, r)) }
        shards = max(0, int(p["shards"], shards))
        weekNeed = max(1, int(p["week_need"], weekNeed))
        weekShards = max(0, int(p["week_shards"], weekShards))
    }

    func base(_ g: ChallengeGame) -> Int { bases[g] ?? 1 }
}

/// Последний выполненный челлендж — для всплывашки «+1 ✂️ · +10 опыта» на экране игры.
struct ChallengeWin: Codable, Hashable, Sendable {
    var game: String
    var goal: Int
    var score: Int
    var shards: Int
    /// Сколько ✂️ дал бонус недели этим же раундом (0 — не дал).
    var weekShards: Int
    var t: Double
}

/// Поле `challenge` в SaveFile. Пустое не пишется — старые сейвы читаются без него.
/// Новому щенку не переходит: челлендж — про этого пса и его рекорды (как уровень).
struct ChallengeLog: Codable, Hashable, Sendable {
    /// Сутки (DayKey) последнего выполненного челленджа; 0 — не было.
    var day = 0
    /// Неделя (Shards.week), выполнено в ней дней, оплачен ли бонус недели.
    var week = 0
    var weekDays = 0
    var weekPaid = false
    /// Выполнено всего.
    var count = 0
    var last: ChallengeWin?

    init() {}

    var isEmpty: Bool { self == ChallengeLog() }

    enum CodingKeys: String, CodingKey {
        case day, week, weekDays, weekPaid, count, last
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? c.decodeIfPresent(Int.self, forKey: .day)) ?? 0
        week = (try? c.decodeIfPresent(Int.self, forKey: .week)) ?? 0
        weekDays = (try? c.decodeIfPresent(Int.self, forKey: .weekDays)) ?? 0
        weekPaid = (try? c.decodeIfPresent(Bool.self, forKey: .weekPaid)) ?? false
        count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 0
        last = try? c.decodeIfPresent(ChallengeWin.self, forKey: .last)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if day != 0 { try c.encode(day, forKey: .day) }
        if week != 0 { try c.encode(week, forKey: .week) }
        if weekDays != 0 { try c.encode(weekDays, forKey: .weekDays) }
        if weekPaid { try c.encode(weekPaid, forKey: .weekPaid) }
        if count != 0 { try c.encode(count, forKey: .count) }
        try c.encodeIfPresent(last, forKey: .last)
    }
}

/// Итог раунда, который умеет проверить челлендж: очки и «просто так».
protocol ChallengeScored {
    var score: Int { get }
    var free: String? { get }
}

extension CatchResult: ChallengeScored {}
extension BlockDuoResult: ChallengeScored {}
extension ZombieResult: ChallengeScored {}

/// Что показать на плашке экрана игры.
enum ChallengeStatus: Equatable, Sendable {
    /// Сегодня челлендж в этой игре: набрать goal очков.
    case today(goal: Int)
    /// Сегодня челлендж в другой игре.
    case elsewhere(ChallengeGame)
    /// Сегодня уже выполнен.
    case done
}

enum Challenges {
    /// Id открытия в DogLevel.
    static let unlockId = "games.challenge"
    /// Вид записи журнала: по нему DogLevel даёт опыт (правило game.challenge, 10 опыта, раз в день).
    static let journalKind = "game.challenge"

    /// Открыт ли челлендж: пёс дорос до ур. 11.
    static func isOpen(_ f: SaveFile) -> Bool {
        DogLevel.isOpen(unlockId, level: DogLevel.level(f))
    }

    /// Игра челленджа в сутки day: по кругу Мячик → Блок Дуо → Зомби.
    static func game(day: Int) -> ChallengeGame {
        let all = ChallengeGame.allCases
        let i = day - DayKey.floorDiv(day, all.count) * all.count
        return all[i]
    }

    static func game(at t: Double) -> ChallengeGame { game(day: DayKey.of(t)) }

    /// Человеческое число: до 20 — как есть, до 100 — кратно 5, до 1000 — кратно 10, дальше — кратно 100.
    static func nice(_ x: Double) -> Int {
        let v = max(0, x)
        let step: Double = v < 20 ? 1 : v < 100 ? 5 : v < 1000 ? 10 : 100
        return Int((v / step).rounded() * step)
    }

    /// Цель при таком рекорде: max(база, 70 % рекорда по-человечески).
    static func goal(_ g: ChallengeGame, record: Int, _ cfg: ChallengeConfig = .shared) -> Int {
        max(cfg.base(g), nice(Double(record) * cfg.ratio))
    }

    static func goal(_ g: ChallengeGame, in f: SaveFile, _ cfg: ChallengeConfig = .shared) -> Int {
        goal(g, record: g.record(f), cfg)
    }

    /// Выполнен ли сегодняшний челлендж.
    static func doneToday(_ f: SaveFile, at t: Double) -> Bool {
        f.challenge.day != 0 && f.challenge.day == DayKey.of(t)
    }

    /// Плашка на экране игры g; nil — челлендж ещё закрыт (до ур. 11).
    static func status(_ f: SaveFile, game g: ChallengeGame, at t: Double, _ cfg: ChallengeConfig = .shared) -> ChallengeStatus? {
        guard isOpen(f) else { return nil }
        if doneToday(f, at: t) { return .done }
        let today = game(at: t)
        return today == g ? .today(goal: goal(g, in: f, cfg)) : .elsewhere(today)
    }

    /// Раунд игры с проверкой челленджа: цель считается от рекорда ДО раунда, потом — сам раунд, потом — проверка.
    /// Экран игры зовёт это вместо голого finish: Challenges.play(.blockduo, in: &f, now: t) { BlockDuo.finish(g, in: &$0, now: $1) }.
    @discardableResult
    static func play<R: ChallengeScored>(_ g: ChallengeGame, in f: inout SaveFile, now: Double,
                                         _ cfg: ChallengeConfig = .shared,
                                         _ round: (inout SaveFile, Double) -> R) -> R {
        let target = goal(g, in: f, cfg)
        let r = round(&f, now)
        settle(g, score: r.score, free: r.free, goal: target, in: &f, now: now, cfg)
        // Опыт за челлендж и достижения («Первый челлендж», «Все игры» — и за партию «просто так») — в эту запись.
        PetRunner.settleRewards(&f, now: now)
        return r
    }

    /// Засчитать челлендж, если раунд его выполнил. Возвращает выигрыш или nil.
    @discardableResult
    static func settle(_ g: ChallengeGame, score: Int, free: String?, goal target: Int, in f: inout SaveFile,
                       now: Double, _ cfg: ChallengeConfig = .shared) -> ChallengeWin? {
        let day = DayKey.of(now)
        guard isOpen(f), free == nil, f.pet.alive, game(day: day) == g,
              f.challenge.day != day, score >= target else { return nil }
        var log = f.challenge
        log.day = day
        log.count += 1
        let week = Shards.week(day)
        if log.week != week {
            log.week = week
            log.weekDays = 0
            log.weekPaid = false
        }
        log.weekDays += 1
        var bonus = 0
        if log.weekDays >= cfg.weekNeed, !log.weekPaid {
            bonus = cfg.weekShards
            log.weekPaid = true
        }
        let paid = cfg.shards + bonus
        Economy.grant(&f, shards: paid)
        f.shardLog.earned += paid
        let win = ChallengeWin(game: g.rawValue, goal: target, score: score, shards: cfg.shards, weekShards: bonus, t: now)
        log.last = win
        f.challenge = log
        // Опыт — через журнал: DogLevel.settle даст 10 (правило game.challenge, раз в день) и разовые +5 за первый.
        f.log(journalKind, t: now, key: g.rawValue, value: score)
        return win
    }

    // MARK: тексты

    /// «2 000» — разряды через неразрывный пробел.
    static func number(_ n: Int) -> String {
        let s = String(abs(n))
        guard s.count > 3 else { return n < 0 ? "-" + s : s }
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0, (s.count - i) % 3 == 0 { out.append("\u{00A0}") }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }

    /// Текст плашки: «Челлендж: 2 000 · сегодня», «Челлендж дня — в «Блок Дуо»», «✓ Челлендж выполнен».
    static func badgeText(_ s: ChallengeStatus) -> String {
        switch s {
        case .today(let goal): return "Челлендж: \(number(goal)) · сегодня"
        case .elsewhere(let g): return "Челлендж дня — в «\(g.title)»"
        case .done: return "✓ Челлендж выполнен"
        }
    }

    /// Для VoiceOver: цель словами.
    static func badgeA11y(_ s: ChallengeStatus) -> String {
        switch s {
        case .today(let goal):
            return "Челлендж дня: набери \(number(goal)) \(EconText.plural(goal, "очко", "очка", "очков"))"
        case .elsewhere(let g): return "Челлендж дня сегодня в игре «\(g.title)»"
        case .done: return "Челлендж дня выполнен"
        }
    }

    /// Всплывашка после выполненного: «+1 ✂️ · +10 опыта» (и «+3 ✂️ за неделю»).
    static func rewardText(_ w: ChallengeWin, _ level: DogLevelConfig = .shared) -> String {
        var parts = ["+\(w.shards) ✂️"]
        let xp = level.rule(journalKind)?.xp ?? 0
        if xp > 0 { parts.append("+\(xp) опыта") }
        if w.weekShards > 0 { parts.append("+\(w.weekShards) ✂️ за неделю") }
        return parts.joined(separator: " · ")
    }
}
