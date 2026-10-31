// Волна 57: «Команды» — дрессировка в духе Nintendogs вместо листа «Привычки». 8 команд: Сидеть, Лапу, Лежать,
// Голос, Кружись, Дай пять, Притворись спящим, Ползи. Тап по иконке — пёс выполняет клип; новая команда выходит
// примерно в трети попыток («Не понял…» — склонил голову), с каждым засчитанным разом чаще, выученная — почти всегда.
// Учится за 3–5 засчитанных удач (Trick.needed); засчитывается не чаще раза в gap — спам кнопкой не учит.
// Команды открываются уровнем пса (Trick.level), щенку — только первые trickLimit (Growth).
// Награды: за выучку — монеты и ласка один раз; выученная команда — настроение с перерывом joyGap и пара монет
// в сутки (showCoins до showDaily) внутри общего потолка привычек/шагов (EconomyConfig.habitsCap).
// Голодный или грустный пёс слушается хуже (distracted). Засчитанная удача пишет trick.show — задание дня «Покажи трюки».
// Ядро не трогаем: настроение — та же «Погладить» ядра на копии, доля прибавки ласки; журнал act.* не пишем
// (его читают монеты, открытки и «Пока тебя не было»).
// Без экрана (Foundation + PetCore) — гоняется на Linux (app/Package.swift).

import Foundation
@preconcurrency import PetCore

/// Порядок кейсов — порядок в сетке и открытия. Старые трюки волны 8 (bow, jump, shake) остаются в сейве
/// (TrickLog.items по rawValue) и в «Воспоминаниях», но в сетке их нет.
enum Trick: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case sit, paw, lie, speak, spin, five, playDead = "play_dead", crawl

    var id: String { rawValue }

    /// Вид реакции сцены: «trick.sit». Отличает трюк от действий ядра (PetStance, PetStage).
    var kind: String { "trick.\(rawValue)" }

    init?(kind: String) {
        guard kind.hasPrefix("trick.") else { return nil }
        self.init(rawValue: String(kind.dropFirst(6)))
    }

    /// Название команды.
    var title: String {
        switch self {
        case .sit: return "Сидеть"
        case .paw: return "Лапу"
        case .lie: return "Лежать"
        case .speak: return "Голос"
        case .spin: return "Кружись"
        case .five: return "Дай пять"
        case .playDead: return "Притворись спящим"
        case .crawl: return "Ползи"
        }
    }

    /// Подпись под иконкой — одно-два слова.
    var short: String { self == .playDead ? "Притворись" : title }

    /// Тост удачи.
    var done: String {
        switch self {
        case .sit: return "Сидит!"
        case .paw: return "Даёт лапу!"
        case .lie: return "Лежит!"
        case .speak: return "Гав!"
        case .spin: return "Кружится!"
        case .five: return "Пять!"
        case .playDead: return "Спит… понарошку"
        case .crawl: return "Ползёт!"
        }
    }

    /// SF Symbol иконки (рекомендация волны 52: SF Symbols, без своих рисунков).
    var symbol: String {
        switch self {
        case .sit: return "dog.fill"
        case .paw: return "pawprint.fill"
        case .lie: return "bed.double.fill"
        case .speak: return "speaker.wave.2.fill"
        case .spin: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .five: return "hand.raised.fill"
        case .playDead: return "powersleep"
        case .crawl: return "tortoise.fill"
        }
    }

    /// Клипы shiba.clips.json по порядку — из стойки «стоит» и обратно в неё (волна 58: paw/high_five — сидя,
    /// crawl — лёжа, play_dead_out — подъём из позы death). «Голос» — лает (bark, тявк SoundKit на каждое «гав»).
    var clips: [String] {
        switch self {
        case .sit: return ["sit_in", "sit", "sit_out"]
        case .paw: return ["sit_in", "paw", "sit_out"]
        case .lie: return ["lie_in", "lie", "lie_out"]
        case .speak: return ["head_tilt", "bark", "hop"]
        case .spin: return ["spin"]
        case .five: return ["sit_in", "high_five", "sit_out"]
        case .playDead: return ["death", "play_dead_out"]
        case .crawl: return ["lie_in", "crawl", "crawl", "lie_out"]
        }
    }

    /// Засчитанных удач до «выучено»: первые — 3, дальше дольше.
    var needed: Int {
        switch self {
        case .sit, .paw: return 3
        case .lie, .speak, .spin: return 4
        case .five, .playDead, .crawl: return 5
        }
    }

    /// С какого уровня пса открыта.
    var level: Int {
        switch self {
        case .sit, .paw: return 1
        case .lie: return 2
        case .speak: return 3
        case .spin: return 5
        case .five: return 7
        case .playDead: return 9
        case .crawl: return 12
        }
    }

    /// Название трюка по ключу сейва, включая старые трюки волны 8 (их нет в сетке, но выученное помним).
    static func title(raw: String) -> String? {
        if let t = Trick(rawValue: raw) { return t.title }
        switch raw {
        case "bow": return "Поклон"
        case "jump": return "Прыжок"
        case "shake": return "Отряхнись"
        default: return nil
        }
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
    /// Волна 57: монеты за показ выученных команд за сутки day (DayKey). 0 — не пишется.
    var day = 0
    var showCoins = 0

    init() {}

    var isEmpty: Bool { items.isEmpty && joyT == nil && day == 0 && showCoins == 0 }

    subscript(_ t: Trick) -> Entry {
        get { items[t.rawValue] ?? Entry() }
        set { items[t.rawValue] = newValue }
    }

    enum CodingKeys: String, CodingKey { case items, joyT, day, showCoins }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([String: Entry].self, forKey: .items)) ?? [:]
        joyT = try? c.decodeIfPresent(Double.self, forKey: .joyT)
        day = (try? c.decodeIfPresent(Int.self, forKey: .day)) ?? 0
        showCoins = (try? c.decodeIfPresent(Int.self, forKey: .showCoins)) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !items.isEmpty { try c.encode(items, forKey: .items) }
        try c.encodeIfPresent(joyT, forKey: .joyT)
        if day != 0 { try c.encode(day, forKey: .day) }
        if showCoins != 0 { try c.encode(showCoins, forKey: .showCoins) }
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
    /// Монеты: за выучку (learnCoins) или за показ выученной (showCoins), иначе 0.
    let coins: Int
    /// Прибавка ласки.
    let love: Double
    /// Подросток не захотел (Growth.perks.trickRefusePct): попытка была, без штрафа и без зачёта.
    var refused = false

    var tried: Bool { reason == nil }
}

/// Иконка сетки «Команды».
struct TrickRow: Hashable, Sendable, Identifiable {
    let trick: Trick
    let progress: Int
    let learned: Bool
    /// Уровень пса ниже Trick.level: замок с цифрой.
    let locked: Bool
    /// Щенку рано (Growth.perks.trickLimit): «подрастёт — научится». Важнее замка.
    var young = false

    var id: String { trick.rawValue }
    var needed: Int { trick.needed }
    /// Кольцо прогресса 0…1.
    var fraction: Double { learned ? 1 : Double(min(progress, needed)) / Double(max(1, needed)) }
}

enum Tricks {
    /// Больше всего засчитанных удач у одной команды (у первых — меньше, см. Trick.needed).
    static let maxNeeded = 5
    /// Удачи чаще раза в gap не засчитываются: «тыкать без остановки» ничему не учит.
    static let gap: Double = 20
    /// Шанс новой команды; с каждым засчитанным разом +span/needed. Выученная — learnedChance.
    static let baseChance = 0.3
    static let span = 0.5
    static let learnedChance = 0.95
    /// Голодный (еда) или грустный (ласка) ниже порога — шанс × distractedFactor.
    static let distractedBelow = 30.0
    static let distractedFactor = 0.6
    /// Доля ласки от «Погладить» ядра за удачный трюк.
    static let loveShare = 0.25
    /// Настроение от трюков — не чаще перезарядки «Погладить» (3 минуты), иначе восемь команд подряд
    /// дают больше ласки, чем сама ласка.
    static let joyGap: Double = 180
    /// За выучку ласки больше (разово, мимо joyGap).
    static let learnLoveShare = 0.5
    /// Монеты за выучку — разово, мимо дневного потолка ухода.
    static let learnCoins = 5
    /// Показ выученной команды: монет за засчитанный показ и не больше showDaily в сутки,
    /// внутри общего потолка привычек и шагов (econ.daily.habits ≤ habitsCap).
    static let showCoins = 1
    static let showDaily = 5
    /// Команда голосом (SitIntent/PawIntent): пауза, пока приложение откроется и комнату станет видно, мс.
    static let siriDelayMs = 900
    /// Запись журнала засчитанной удачи — задание дня «Покажи трюки».
    static let showKind = "trick.show"
    /// Запись журнала выучки (DogLevel: опыт, «Воспоминания»).
    static let learnKind = "trick.learn"

    static let lockedReason = "locked"
    /// Щенок мал для этой команды (Growth.perks.trickLimit).
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

    /// Почему команды сейчас нельзя (общая причина для всех). nil — можно.
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

    /// SF Symbol значка причины на серой иконке: спит — луна, моется — пузыри, гуляет — человечек.
    static func gateSymbol(_ reason: String?) -> String? {
        switch reason {
        case nil: return nil
        case "asleep": return "moon.zzz.fill"
        case "bathing": return "bubbles.and.sparkles.fill"
        case "away": return "figure.walk"
        case "dead": return "heart.slash.fill"
        case loadingReason: return "hourglass"
        default: return "bandage.fill"
        }
    }

    /// Голодный или грустный — слушается хуже (значок миски/сердца на иконках).
    static func distracted(_ f: SaveFile, at t: Double) -> Need? {
        let s = PetRunner.peek(f, at: t)
        if (s.needs[.food] ?? 100) < distractedBelow { return .food }
        if (s.needs[.love] ?? 100) < distractedBelow { return .love }
        return nil
    }

    static func learned(_ t: Trick, in f: SaveFile) -> Bool { f.tricks[t].learned != nil }

    /// Открыта уровнем пса (выученное раньше не отнимаем).
    static func unlocked(_ t: Trick, in f: SaveFile) -> Bool {
        learned(t, in: f) || DogLevel.level(f) >= t.level
    }

    static func progress(_ t: Trick, in f: SaveFile) -> Int { min(t.needed, f.tricks[t].n) }

    /// Щенку рано: команда дальше первых trickLimit и ещё не выучена (выученное раньше не отнимаем).
    static func young(_ t: Trick, in f: SaveFile, _ cfg: GrowthConfig = .shared) -> Bool {
        guard let limit = Growth.perks(f, cfg).trickLimit, !learned(t, in: f),
              let i = Trick.allCases.firstIndex(of: t) else { return false }
        return i >= limit
    }

    /// Текст отказа (для VoiceOver и тоста): общий из RefuseText, для замка — с какого уровня.
    static func reasonText(_ reason: String?, for t: Trick? = nil) -> String {
        if reason == lockedReason, let t { return "С уровня \(t.level)" }
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

    /// Выучено команд из сетки.
    static func learnedCount(_ f: SaveFile) -> Int { Trick.allCases.filter { learned($0, in: f) }.count }

    /// Монет за показ сегодня ещё можно (своя суточная норма и общий потолок).
    static func showCoinsLeft(_ f: SaveFile, at now: Double, _ cfg: EconomyConfig = .shared) -> Int {
        let mine = DayKey.today(f.tricks.showCoins, day: f.tricks.day, at: now)
        let common = DayKey.today(f.econ.daily.habits, day: f.econ.daily.day, at: now)
        return max(0, min(showDaily - mine, cfg.habitsCap - common))
    }

    // MARK: попытка

    /// Шанс удачи сейчас: выученная — почти всегда, новая — растёт с каждым засчитанным разом;
    /// голодный или грустный — хуже.
    static func chance(_ t: Trick, in f: SaveFile, at now: Double? = nil) -> Double {
        let e = f.tricks[t]
        let base: Double
        if e.learned != nil {
            base = learnedChance
        } else {
            base = min(learnedChance, baseChance + span * Double(min(e.n, t.needed)) / Double(t.needed))
        }
        guard let now, distracted(f, at: now) != nil else { return base }
        return base * distractedFactor
    }

    /// Бросок 0..<1: детерминирован от petId, команды и номера попытки — тот же файл даёт тот же исход.
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
        let p = chance(t, in: f, at: now)
        e.tries += 1
        // Подросток иногда упирается: попытка ушла (tries), но ни штрафа, ни зачёта. С forced не бросаем —
        // тесты и UI-тесты задают исход сами.
        let pct = Growth.perks(f).trickRefusePct
        if forced == nil, pct > 0, refuseRoll(petId: f.petId, t, tries: e.tries) * 100 < Double(pct) {
            f.tricks[t] = e
            return TrickOutcome(trick: t, ok: false, reason: nil, counted: false, progress: min(t.needed, e.n),
                                learnedNow: false, coins: 0, love: 0, refused: true)
        }
        let ok = (forced ?? roll(petId: f.petId, t, tries: e.tries)) < p
        guard ok else {
            f.tricks[t] = e
            return TrickOutcome(trick: t, ok: false, reason: nil, counted: false, progress: min(t.needed, e.n),
                                learnedNow: false, coins: 0, love: 0)
        }

        // Метку из будущего (часы назад) catchUp уже прижал к now: перерыв идёт заново, без бесплатного зачёта.
        let counted = now >= e.t + gap
        let wasLearned = e.learned != nil
        var learnedNow = false
        if counted {
            e.t = now
            if !wasLearned {
                e.n = min(t.needed, e.n + 1)
                if e.n >= t.needed {
                    e.learned = now
                    learnedNow = true
                }
            }
        }
        f.tricks[t] = e
        let love = learnedNow ? cheer(&f, now: now, share: learnLoveShare, force: true)
            : counted ? cheer(&f, now: now, share: loveShare, force: false) : 0

        var coins = 0
        if counted {
            // Сначала показ: задание дня «Покажи трюки» и опыт выучки — в одну запись (волна 42 I).
            f.log(showKind, t: now, key: t.rawValue)
            if learnedNow {
                f.log(learnKind, t: now, key: t.rawValue)
                coins = payLearn(&f, now: now)
            } else if wasLearned {
                coins = payShow(&f, now: now)
            }
            PetRunner.settleRewards(&f, now: now)
        }
        return TrickOutcome(trick: t, ok: true, reason: nil, counted: counted, progress: min(t.needed, e.n),
                            learnedNow: learnedNow, coins: coins, love: love)
    }

    /// Настроение: «Погладить» ядра на копии без перезарядки, в питомца — share прибавки.
    /// Перезарядку настоящей «Погладить» не ставим: трюк не должен запрещать ласку. force — мимо joyGap (выучка).
    private static func cheer(_ f: inout SaveFile, now: Double, share: Double, force: Bool) -> Double {
        if !force, let j = f.tricks.joyT, now < j + joyGap { return 0 }
        var s = f.pet
        s.cooldowns["pet"] = nil
        let before = f.pet.needs[.love] ?? 0
        guard PetEngine.act(&s, Catalog.rules, f.owner, .pet).ok else { return 0 }
        let gain = max(0, ((s.needs[.love] ?? before) - before) * share)
        guard gain > 0 else { return 0 }
        f.pet.needs[.love] = min(100, before + gain)
        f.tricks.joyT = now
        return min(100, before + gain) - before
    }

    /// Монеты за выучку — мимо дневного потолка ухода: награда разовая (не больше 8 × learnCoins на пса),
    /// а выученная команда второго шанса не даст — упрись она в вечерний потолок, сгорела бы молча.
    /// Запись в lastEarn — для тоста.
    private static func payLearn(_ f: inout SaveFile, now: Double) -> Int {
        f.econ.wallet.coins += learnCoins
        let id = f.journal.last?.id ?? "\(f.deviceId):\(f.seq)"
        f.econ.lastEarn = Earning(id: id, kind: "trick", coins: learnCoins, capped: false, t: now)
        return learnCoins
    }

    /// Показ выученной: showCoins, пока не исчерпаны своя суточная норма и общий потолок привычек и шагов.
    private static func payShow(_ f: inout SaveFile, now: Double) -> Int {
        let today = DayKey.of(now)
        if let d = DayKey.newer(than: f.tricks.day, at: now) {
            f.tricks.day = d
            f.tricks.showCoins = 0
        }
        Economy.rollDay(&f.econ, day: today)
        let got = min(showCoins, showCoinsLeft(f, at: now))
        guard got > 0 else { return 0 }
        f.tricks.showCoins += got
        f.econ.daily.habits += got
        f.econ.wallet.coins += got
        let id = f.journal.last?.id ?? "\(f.deviceId):\(f.seq)"
        f.econ.lastEarn = Earning(id: id, kind: "trick", coins: got, capped: false, t: now)
        return got
    }
}
