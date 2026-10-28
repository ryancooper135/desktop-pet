// Трюки в духе Nintendogs: «Сидеть», «Лежать», «Поклон»… Пёс учится повторением: новый трюк выходит
// примерно в трети попыток, с каждым засчитанным разом чаще, выученный — почти всегда.
// Засчитывается удача не чаще раза в gap: спам кнопкой не учит. Следующий трюк открывается, когда выучен предыдущий.
// Ядро не трогаем: настроение — та же «Погладить» ядра на копии, доля прибавки ласки; журнал act.* не пишем
// (его читают монеты, открытки и «Пока тебя не было»), только trick.learn один раз на трюк.
// Без экрана (Foundation + PetCore) — гоняется на Linux (app/Package.swift).

import Foundation
@preconcurrency import PetCore

/// Порядок кейсов — порядок открытия.
enum Trick: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case sit, lie, bow, jump, shake, speak

    var id: String { rawValue }

    /// Вид реакции сцены: «trick.sit». Отличает трюк от действий ядра (PetStance, PetStage).
    var kind: String { "trick.\(rawValue)" }

    init?(kind: String) {
        guard kind.hasPrefix("trick.") else { return nil }
        self.init(rawValue: String(kind.dropFirst(6)))
    }

    /// Название команды на кнопке.
    var title: String {
        switch self {
        case .sit: return "Сидеть"
        case .lie: return "Лежать"
        case .bow: return "Поклон"
        case .jump: return "Прыжок"
        case .shake: return "Отряхнись"
        case .speak: return "Голос"
        }
    }

    /// Тост удачи.
    var done: String {
        switch self {
        case .sit: return "Сидит!"
        case .lie: return "Лежит!"
        case .bow: return "Поклон!"
        case .jump: return "Прыг!"
        case .shake: return "Отряхнулся!"
        case .speak: return "Гав!"
        }
    }

    /// SF Symbol карточки.
    var symbol: String {
        switch self {
        case .sit: return "chair.lounge.fill"
        case .lie: return "bed.double.fill"
        case .bow: return "sparkles"
        case .jump: return "hare.fill"
        case .shake: return "drop.fill"
        case .speak: return "speaker.wave.2.fill"
        }
    }

    /// Клипы shiba.clips.json по порядку — из стойки «стоит». «Голос» — лает (bark, тявк SoundKit на каждое «гав»),
    /// без клипа bark — тявк на прыжке.
    var clips: [String] {
        switch self {
        case .sit: return ["sit_in", "sit", "sit_out"]
        case .lie: return ["lie_in", "lie", "lie_out"]
        case .bow: return ["play_bow"]
        case .jump: return ["hop", "gallop_jump"]
        case .shake: return ["shake"]
        case .speak: return ["head_tilt", "bark", "hop"]
        }
    }

    /// Предыдущий в порядке открытия; у первого — nil.
    var previous: Trick? {
        let all = Trick.allCases
        guard let i = all.firstIndex(of: self), i > 0 else { return nil }
        return all[i - 1]
    }
}

/// Прогресс в state.json. Компактно: ключ — Trick.rawValue. Пустое в файл не пишется.
struct TrickLog: Codable, Hashable, Sendable {
    /// n — засчитанные удачи, t — последняя засчитанная, tries — все попытки (зерно броска), learned — когда выучен.
    struct Entry: Codable, Hashable, Sendable {
        var n = 0
        var t: Double = 0
        var tries = 0
        var learned: Double?

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            n = (try? c.decodeIfPresent(Int.self, forKey: .n)) ?? 0
            t = (try? c.decodeIfPresent(Double.self, forKey: .t)) ?? 0
            tries = (try? c.decodeIfPresent(Int.self, forKey: .tries)) ?? 0
            learned = try? c.decodeIfPresent(Double.self, forKey: .learned)
        }
    }

    var items: [String: Entry] = [:]
    /// Последняя прибавка настроения от трюка (одна на все трюки, см. Tricks.joyGap).
    var joyT: Double?

    init() {}

    var isEmpty: Bool { items.isEmpty && joyT == nil }

    subscript(_ t: Trick) -> Entry {
        get { items[t.rawValue] ?? Entry() }
        set { items[t.rawValue] = newValue }
    }

    enum CodingKeys: String, CodingKey { case items, joyT }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([String: Entry].self, forKey: .items)) ?? [:]
        joyT = try? c.decodeIfPresent(Double.self, forKey: .joyT)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !items.isEmpty { try c.encode(items, forKey: .items) }
        try c.encodeIfPresent(joyT, forKey: .joyT)
    }
}

/// Итог попытки: вышло ли, засчитано ли, сколько набрано и что за это дали.
struct TrickOutcome: Hashable, Sendable {
    let trick: Trick
    let ok: Bool
    /// Почему попытки не было (dead, away, asleep, locked…). nil — пёс пробовал.
    let reason: String?
    /// Удача пошла в счёт (не чаще gap).
    let counted: Bool
    /// Засчитанных удач после попытки (0…needed).
    let progress: Int
    /// Трюк выучен именно сейчас.
    let learnedNow: Bool
    /// Монеты за первый раз (learnCoins, иначе 0).
    let coins: Int
    /// Прибавка ласки.
    let love: Double
    /// Подросток не захотел (Growth.perks.trickRefusePct): попытка была, без штрафа и без зачёта.
    var refused = false

    var tried: Bool { reason == nil }
}

/// Строка листа «Трюки».
struct TrickRow: Hashable, Sendable, Identifiable {
    let trick: Trick
    let progress: Int
    let learned: Bool
    let locked: Bool
    /// Щенку рано (Growth.perks.trickLimit): «подрастёт — научится». Важнее замка.
    var young = false

    var id: String { trick.rawValue }
}

enum Tricks {
    /// Столько засчитанных удач — и трюк выучен.
    static let needed = 5
    /// Удачи чаще раза в минуту не засчитываются: «тыкать без остановки» ничему не учит.
    static let gap: Double = 60
    /// Шанс нового трюка; с каждым засчитанным разом +span/needed. Выученный — learnedChance.
    static let baseChance = 0.3
    static let span = 0.5
    static let learnedChance = 0.95
    /// Доля ласки от «Погладить» ядра за удачный трюк.
    static let loveShare = 0.25
    /// Настроение от трюков — не чаще перезарядки «Погладить» (3 минуты), иначе шесть трюков подряд
    /// дают больше ласки, чем сама ласка.
    static let joyGap: Double = 180
    /// Монеты за первый раз — разово, мимо дневного потолка ухода.
    static let learnCoins = 5

    static let lockedReason = "locked"
    /// Щенок мал для этого трюка (Growth.perks.trickLimit).
    static let growReason = "grow"
    static let growText = "Подрастёт — научится"
    /// Подросток упёрся (Growth.perks.trickRefusePct).
    static let refuseText = "Не хочет. Подросток!"
    /// Стор ещё не прочитан (model.file == nil): не «не получилось сохранить», а подождать.
    static let loadingReason = "loading"
    static let failText = "Не понял…"
    /// Клипы промаха: склонил голову, понюхал — «а что надо-то?».
    static let failClips = ["head_tilt", "sniff"]

    // MARK: доступность

    /// Почему трюки сейчас нельзя (общая причина для всех). nil — можно.
    /// Порядок как у ядра: нет пса → гуляет → моется → спит → плохо.
    static func gate(_ f: SaveFile, at t: Double) -> String? {
        let s = PetRunner.peek(f, at: t)
        let o = PetRunner.owner(f, at: t)
        if !s.alive { return "dead" }
        if s.outing != nil { return "away" }
        if s.bathUntil != nil { return "bathing" }
        if s.napUntil != nil || PetEngine.petNight(t, Catalog.rules, o) { return "asleep" }
        if Presenter.isCritical(level: PetEngine.level(s, Catalog.rules), alive: s.alive) { return "unwell" }
        return nil
    }

    static func learned(_ t: Trick, in f: SaveFile) -> Bool { f.tricks[t].learned != nil }

    static func unlocked(_ t: Trick, in f: SaveFile) -> Bool {
        guard let p = t.previous else { return true }
        return learned(p, in: f)
    }

    static func progress(_ t: Trick, in f: SaveFile) -> Int { min(needed, f.tricks[t].n) }

    /// Щенку рано: трюк дальше первых trickLimit и ещё не выучен (выученное раньше не отнимаем).
    static func young(_ t: Trick, in f: SaveFile, _ cfg: GrowthConfig = .shared) -> Bool {
        guard let limit = Growth.perks(f, cfg).trickLimit, !learned(t, in: f),
              let i = Trick.allCases.firstIndex(of: t) else { return false }
        return i >= limit
    }

    /// Текст отказа: общий из RefuseText, для замка — какой трюк выучить раньше.
    static func reasonText(_ reason: String?, for t: Trick? = nil) -> String {
        if reason == lockedReason, let p = t?.previous { return "Сначала выучи «\(p.title)»" }
        if reason == growReason { return growText }
        if reason == loadingReason { return "Секунду…" }
        return RefuseText.text(reason)
    }

    static func rows(_ f: SaveFile) -> [TrickRow] {
        Trick.allCases.map { t in
            TrickRow(trick: t, progress: progress(t, in: f), learned: learned(t, in: f), locked: !unlocked(t, in: f),
                     young: young(t, in: f))
        }
    }

    /// Выучено трюков всего.
    static func learnedCount(_ f: SaveFile) -> Int { Trick.allCases.filter { learned($0, in: f) }.count }

    // MARK: попытка

    /// Шанс удачи сейчас.
    static func chance(_ t: Trick, in f: SaveFile) -> Double {
        let e = f.tricks[t]
        if e.learned != nil { return learnedChance }
        return min(learnedChance, baseChance + span * Double(min(e.n, needed)) / Double(needed))
    }

    /// Бросок 0..<1: детерминирован от petId, трюка и номера попытки — тот же файл даёт тот же исход.
    static func roll(petId: String, _ t: Trick, tries: Int) -> Double {
        let x = StableRandom.mix(StableHash.fnv1a("\(petId):trick:\(t.rawValue):\(tries)"))
        return Double(x >> 11) / Double(UInt64(1) << 53)
    }

    /// Бросок «не хочу» подростка — своё зерно, чтобы не сдвигать бросок удачи.
    static func refuseRoll(petId: String, _ t: Trick, tries: Int) -> Double {
        let x = StableRandom.mix(StableHash.fnv1a("\(petId):trick:\(t.rawValue):\(tries):refuse"))
        return Double(x >> 11) / Double(UInt64(1) << 53)
    }

    /// Хозяин дал команду. roll — для тестов и UI-тестов (PET_TRICK_ROLL); nil — честный бросок.
    @discardableResult
    static func attempt(_ t: Trick, in f: inout SaveFile, now: Double, roll forced: Double? = nil) -> TrickOutcome {
        PetRunner.catchUp(&f, now: now)
        func refuse(_ r: String) -> TrickOutcome {
            TrickOutcome(trick: t, ok: false, reason: r, counted: false, progress: progress(t, in: f),
                         learnedNow: false, coins: 0, love: 0)
        }
        if let r = gate(f, at: now) { return refuse(r) }
        if young(t, in: f) { return refuse(growReason) }
        guard unlocked(t, in: f) else { return refuse(lockedReason) }

        var e = f.tricks[t]
        let p = chance(t, in: f)
        e.tries += 1
        // Подросток иногда упирается: попытка ушла (tries), но ни штрафа, ни зачёта. С forced не бросаем —
        // тесты и UI-тесты задают исход сами.
        let pct = Growth.perks(f).trickRefusePct
        if forced == nil, pct > 0, refuseRoll(petId: f.petId, t, tries: e.tries) * 100 < Double(pct) {
            f.tricks[t] = e
            return TrickOutcome(trick: t, ok: false, reason: nil, counted: false, progress: min(needed, e.n),
                                learnedNow: false, coins: 0, love: 0, refused: true)
        }
        let ok = (forced ?? roll(petId: f.petId, t, tries: e.tries)) < p
        guard ok else {
            f.tricks[t] = e
            return TrickOutcome(trick: t, ok: false, reason: nil, counted: false, progress: min(needed, e.n),
                                learnedNow: false, coins: 0, love: 0)
        }

        // Метку из будущего (часы назад) catchUp уже прижал к now: перерыв идёт заново, без бесплатного зачёта.
        let counted = now >= e.t + gap
        var learnedNow = false
        if counted {
            e.t = now
            if e.learned == nil {
                e.n = min(needed, e.n + 1)
                if e.n >= needed {
                    e.learned = now
                    learnedNow = true
                }
            }
        }
        f.tricks[t] = e
        let love = counted ? cheer(&f, now: now) : 0

        var coins = 0
        if learnedNow {
            f.log("trick.learn", t: now, key: t.rawValue)
            coins = pay(&f, now: now)
            // Опыт за выучку, «Первый трюк» и «Все трюки» — в эту же запись (волна 42 I).
            PetRunner.settleRewards(&f, now: now)
        }
        return TrickOutcome(trick: t, ok: true, reason: nil, counted: counted, progress: min(needed, e.n),
                            learnedNow: learnedNow, coins: coins, love: love)
    }

    /// Настроение: «Погладить» ядра на копии без перезарядки, в питомца — loveShare прибавки.
    /// Перезарядку настоящей «Погладить» не ставим: трюк не должен запрещать ласку.
    private static func cheer(_ f: inout SaveFile, now: Double) -> Double {
        if let j = f.tricks.joyT, now < j + joyGap { return 0 }
        var s = f.pet
        s.cooldowns["pet"] = nil
        let before = f.pet.needs[.love] ?? 0
        guard PetEngine.act(&s, Catalog.rules, f.owner, .pet).ok else { return 0 }
        let gain = max(0, ((s.needs[.love] ?? before) - before) * loveShare)
        guard gain > 0 else { return 0 }
        f.pet.needs[.love] = min(100, before + gain)
        f.tricks.joyT = now
        return min(100, before + gain) - before
    }

    /// Монеты за первый раз — мимо дневного потолка ухода: награда разовая (не больше 6 × learnCoins на щенка),
    /// а выученный трюк второго шанса не даст — упрись она в вечерний потолок, сгорела бы молча.
    /// Запись в lastEarn — для тоста.
    private static func pay(_ f: inout SaveFile, now: Double) -> Int {
        f.econ.wallet.coins += learnCoins
        let id = f.journal.last?.id ?? "\(f.deviceId):\(f.seq)"
        f.econ.lastEarn = Earning(id: id, kind: "trick", coins: learnCoins, capped: false, t: now)
        return learnCoins
    }
}
