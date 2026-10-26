// Волна 34 I: что показать про уровень и рост — значок в шапке, лист «Уровень», сцена нового уровня и «Подрос!».
// Только чистые функции: SwiftUI их рисует (HomeChips.LevelChip, LevelSheet, AppModel+Level).
// Без экрана (Foundation + PetCore) — гоняется на Linux (app/Package.swift).

import Foundation
@preconcurrency import PetCore

/// Новые уровни для одной сцены: несколько разом (вернулся через неделю) — одна сводка.
struct LevelSummary: Hashable, Sendable {
    /// Первый и последний новый уровень.
    let from: Int
    let to: Int
    var coins = 0
    var shards = 0
    var unlocks: [LevelUnlock] = []
}

/// Строка «за что опыт» в листе.
struct XpSource: Hashable, Sendable, Identifiable {
    let title: String
    let xp: Int
    /// Сколько раз в сутки засчитывается (0 — без лимита).
    let perDay: Int

    var id: String { title }
}

/// Уровень с открытиями — лента «что дальше».
struct LevelStep: Hashable, Sendable, Identifiable {
    let level: Int
    let unlocks: [LevelUnlock]

    var id: Int { level }
}

enum LevelInfo {
    /// Сколько уровней с открытиями показывать в ленте.
    static let feedCount = 4

    // MARK: шапка

    /// Значок в шапке: «ур. 7».
    static func chipText(_ p: LevelProgress) -> String { "ур. \(p.level)" }

    /// Подпись для VoiceOver: «Уровень 7, 320 опыта из 430».
    static func chipLabel(_ p: LevelProgress) -> String {
        p.isMax ? "Уровень \(p.level), предел" : "Уровень \(p.level), \(p.into) \(xpWord(p.into)) из \(p.need)"
    }

    // MARK: лист «Уровень»

    /// «320 / 430», на пределе — «предел».
    static func xpLine(_ p: LevelProgress) -> String { p.isMax ? "предел" : "\(p.into) / \(p.need)" }

    /// Опыт, набранный сегодня (в потолок), — если учёт уже в сегодняшних сутках.
    static func todayXp(_ f: SaveFile, now: Double) -> Int {
        f.level.day == DayKey.of(now) ? f.level.dayXp : 0
    }

    /// «Сегодня 40 из 150», при упоре — «Сегодня 150 из 150 — на сегодня всё».
    static func todayLine(_ f: SaveFile, now: Double, _ cfg: DogLevelConfig = .shared) -> String {
        let x = min(todayXp(f, now: now), cfg.dayCap)
        let s = "Сегодня \(x) из \(cfg.dayCap)"
        return x >= cfg.dayCap ? s + " — на сегодня всё" : s
    }

    /// За что опыт, по-человечески. Порядок — как заботится хозяин за день.
    static func sources(_ cfg: DogLevelConfig = .shared) -> [XpSource] {
        let rows: [(String, String)] = [
            ("Покормить", "act.feed"), ("Погладить", "act.pet"), ("Поиграть", "act.play"), ("Искупать", "act.bath"),
            ("Прогулка", "ev.back_home"), ("Мини-игра", "game.catch"), ("Новый трюк", "trick.learn"),
            ("Задание дня", "task.done"), ("Сбор копилки во дворе", "yard.collect"),
        ]
        var out = rows.compactMap { t, k in cfg.rules[k].map { XpSource(title: t, xp: $0.xp, perDay: $0.perDay) } }
        if cfg.goodDayXp > 0 { out.append(XpSource(title: "Хороший день", xp: cfg.goodDayXp, perDay: 1)) }
        return out
    }

    /// «+10», «+8, раз в день» или «+1, 10 раз в день».
    static func sourceValue(_ s: XpSource) -> String {
        if s.perDay == 1 { return "+\(s.xp), раз в день" }
        return s.perDay > 0 ? "+\(s.xp), \(EconText.times(s.perDay)) в день" : "+\(s.xp)"
    }

    /// Следующие уровни с открытиями после l (не больше count).
    static func upcoming(after l: Int, count: Int = feedCount, _ cfg: DogLevelConfig = .shared) -> [LevelStep] {
        guard l < cfg.maxLevel else { return [] }
        return ((l + 1)...cfg.maxLevel).lazy
            .map { LevelStep(level: $0, unlocks: DogLevel.unlocks($0, cfg)) }
            .filter { !$0.unlocks.isEmpty }
            .prefix(count).map { $0 }
    }

    /// Награда уровня одной строкой: «+160 🪙» или «+200 🪙 · +5 ✂️».
    static func rewardText(_ l: Int, _ cfg: DogLevelConfig = .shared) -> String {
        let r = DogLevel.reward(l, cfg)
        return rewardText(coins: r.coins, shards: r.shards)
    }

    static func rewardText(coins: Int, shards: Int) -> String {
        var s = "+\(coins) 🪙"
        if shards > 0 { s += " · +\(shards) ✂️" }
        return s
    }

    // MARK: рост

    /// Сколько очков роста в среднем за день: последние засчитанные сутки, иначе обычный уход.
    static func growthRate(_ f: SaveFile, _ cfg: GrowthConfig = .shared) -> Double {
        let g = f.growth.last?.g ?? cfg.legacyPerDay
        return min(cfg.maxPerDay, max(cfg.base, g))
    }

    /// Примерно сколько дней до следующей стадии; nil — взрослый.
    static func growthDays(_ f: SaveFile, _ cfg: GrowthConfig = .shared) -> Int? {
        guard let n = Growth.next(f.growth.points, cfg) else { return nil }
        return max(1, Int((n.left / growthRate(f, cfg)).rounded(.up)))
    }

    /// «Щенок · примерно 6 дней до подростка», «Подросток · примерно 20 дней до взрослого», «Взрослый».
    static func growthLine(_ f: SaveFile, _ cfg: GrowthConfig = .shared) -> String {
        let ph = Growth.phase(f, cfg)
        guard let left = growthLeft(f, cfg) else { return ph.title }
        return "\(ph.title) · \(left)"
    }

    /// «примерно 6 дней до подростка»; nil — взрослый.
    static func growthLeft(_ f: SaveFile, _ cfg: GrowthConfig = .shared) -> String? {
        guard let n = Growth.next(f.growth.points, cfg), let d = growthDays(f, cfg) else { return nil }
        let to = n.phase == .teen ? "подростка" : "взрослого"
        return "примерно \(EconText.days(d)) до \(to)"
    }

    /// Что даёт стадия — одной строкой под ростом.
    static func perksLine(_ ph: GrowthPhase) -> String {
        switch ph {
        case .puppy: return "Учит только «Сидеть» и «Лежать», быстрее устаёт"
        case .teen: return "Иногда упрямится на трюках, нужно больше игр"
        case .adult: return "Иногда приносит две находки, меньше ест"
        }
    }

    // MARK: VoiceOver (волна 36 O)
    // Лист «Уровень» собирает строки в один элемент (.combine) — без своей подписи VoiceOver читал бы «·», «/»,
    // эмодзи 🪙 ✂️ и имя значка. Здесь те же факты словами.

    /// «Рост. Щенок, примерно 6 дней до подростка. Учит только «Сидеть» и «Лежать», быстрее устаёт».
    static func growthSpeech(_ f: SaveFile, _ cfg: GrowthConfig = .shared) -> String {
        let ph = Growth.phase(f, cfg)
        let head = growthLeft(f, cfg).map { "\(ph.title), \($0)" } ?? ph.title
        return "Рост. \(head). \(perksLine(ph))"
    }

    /// «Опыт: 320 из 430»; на пределе — как на экране.
    static func xpSpeech(_ p: LevelProgress) -> String {
        p.isMax ? "Это предел — выше уровней нет" : "Опыт: \(p.into) из \(p.need)"
    }

    /// «Награда: 160 монет» или «Награда: 200 монет и 5 клочков».
    static func rewardSpeech(coins: Int, shards: Int) -> String {
        var s = "Награда: " + EconText.coins(coins)
        if shards > 0 { s += " и " + EconText.shards(shards) }
        return s
    }

    /// Строка ленты «Дальше»: «Уровень 11: Челлендж дня. Награда: 220 монет и 5 клочков».
    static func rowSpeech(level: Int, unlocks: [LevelUnlock], _ cfg: DogLevelConfig = .shared) -> String {
        let r = DogLevel.reward(level, cfg)
        let what = unlocks.isEmpty ? "" : ": " + unlocks.map(\.text).joined(separator: ", ")
        return "Уровень \(level)\(what). " + rewardSpeech(coins: r.coins, shards: r.shards)
    }

    /// Строка «За что опыт»: «Покормить: 8 опыта, раз в день».
    static func sourceSpeech(_ s: XpSource) -> String {
        let head = "\(s.title): \(s.xp) \(xpWord(s.xp))"
        if s.perDay == 1 { return head + ", раз в день" }
        return s.perDay > 0 ? head + ", \(EconText.times(s.perDay)) в день" : head
    }

    // MARK: сцены

    /// Новые уровни после seen до paid включительно; nil — нового нет.
    static func summary(after seen: Int, upTo paid: Int, _ cfg: DogLevelConfig = .shared) -> LevelSummary? {
        guard paid > seen else { return nil }
        var s = LevelSummary(from: seen + 1, to: paid)
        for l in s.from...s.to {
            let r = DogLevel.reward(l, cfg)
            s.coins += r.coins
            s.shards += r.shards
            s.unlocks += DogLevel.unlocks(l, cfg)
        }
        return s
    }

    /// «★7» над псом.
    static func star(_ s: LevelSummary) -> String { "★\(s.to)" }

    /// Тост: «Уровень 7! +140 🪙», несколько — «Уровни 4–6! +300 🪙 · +5 ✂️».
    static func toast(_ s: LevelSummary) -> String {
        let head = s.from == s.to ? "Уровень \(s.to)!" : "Уровни \(s.from)–\(s.to)!"
        return head + " " + rewardText(coins: s.coins, shards: s.shards)
    }

    /// «Открылось: Блок Дуо, В лавке редкие вещи»; больше трёх — «и ещё 2». nil — ничего.
    static func unlockText(_ u: [LevelUnlock]) -> String? {
        guard !u.isEmpty else { return nil }
        let shown = u.prefix(3).map(\.text).joined(separator: ", ")
        return u.count > 3 ? "Открылось: \(shown) и ещё \(u.count - 3)" : "Открылось: \(shown)"
    }

    /// Поп после мини-игры: «+5 опыта».
    static func xpPop(_ xp: Int) -> String { "+\(xp) \(xpWord(xp))" }

    /// Тост смены стадии.
    static func grewText(_ ph: GrowthPhase) -> String {
        switch ph {
        case .puppy: return "Щенок"
        case .teen: return "Подрос! Теперь подросток"
        case .adult: return "Вырос! Совсем взрослый"
        }
    }

    static func xpWord(_ n: Int) -> String { EconText.plural(n, "опыт", "опыта", "опыта") }
}
