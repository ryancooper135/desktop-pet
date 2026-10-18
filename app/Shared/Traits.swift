// Характер питомца: три оси черт, которые медленно складываются из ухода за последние 7 местных дней.
// Игривый ↔ спокойный — доля игр и прогулок, ласковый ↔ сам по себе — доля поглаживаний,
// чистюля ↔ сорванец — доля купаний и расчёсываний. Черты меняют только реплики (PetMind) и отклик на тап
// (PetStance), на баланс — нужды, монеты, ядро — не влияют.
// Учёт ухода — CareTally в state.json: дни → виды → сколько раз, не чаще раза в полчаса на вид, чтобы серия
// поглаживаний не перевешивала всё остальное.

import Foundation
@preconcurrency import PetCore

/// Черта — полюс оси.
enum Trait: String, CaseIterable, Codable, Hashable, Sendable {
    case playful, calm, cuddly, independent, tidy, scruffy

    var title: String {
        switch self {
        case .playful: "Игривый"
        case .calm: "Спокойный"
        case .cuddly: "Ласковый"
        case .independent: "Сам по себе"
        case .tidy: "Чистюля"
        case .scruffy: "Сорванец"
        }
    }

    /// Заметно сильная черта.
    var strongTitle: String {
        switch self {
        case .playful: "Очень игривый"
        case .calm: "Очень спокойный"
        case .cuddly: "Очень ласковый"
        case .independent: "Совсем сам по себе"
        case .tidy: "Большой чистюля"
        case .scruffy: "Настоящий сорванец"
        }
    }

    /// Пояснение под осью в альбоме.
    var hint: String {
        switch self {
        case .playful: "Любит игры и прогулки"
        case .calm: "Ценит тишину и покой"
        case .cuddly: "Обожает, когда гладят"
        case .independent: "Гуляет сам по себе"
        case .tidy: "Любит ванну и щётку"
        case .scruffy: "Грязь ему нипочём"
        }
    }

    var emoji: String {
        switch self {
        case .playful: "⚡️"
        case .calm: "🍃"
        case .cuddly: "💞"
        case .independent: "🧭"
        case .tidy: "🫧"
        case .scruffy: "🐾"
        }
    }

    /// Ключ реплики в lines.json (widget/island).
    var lineKey: String { "trait_\(rawValue)" }
}

/// Ось характера: плюс — первый полюс, минус — второй.
enum TraitAxis: String, CaseIterable, Hashable, Sendable {
    case energy, affection, tidiness

    var plus: Trait {
        switch self {
        case .energy: .playful
        case .affection: .cuddly
        case .tidiness: .tidy
        }
    }

    var minus: Trait {
        switch self {
        case .energy: .calm
        case .affection: .independent
        case .tidiness: .scruffy
        }
    }

    /// Какие действия тянут ось к плюсу.
    var kinds: Set<String> {
        switch self {
        case .energy: ["play", "walk"]
        case .affection: ["pet"]
        case .tidiness: ["bath", "brush"]
        }
    }

    /// Обычная доля этих действий (точка 0 оси) и сколько доли до края шкалы. Подобраны на «обычный день»:
    /// 4 ласки, 2 игры, прогулка, ванна и щётка — все три оси около нуля.
    var mid: Double {
        switch self {
        case .energy: 0.33
        case .affection: 0.45
        case .tidiness: 0.2
        }
    }

    var spread: Double {
        switch self {
        case .energy: 0.2
        case .affection: 0.2
        case .tidiness: 0.12
        }
    }
}

/// Положение на оси: −1…1 и видимая черта (nil — посерединке).
struct TraitScore: Hashable, Sendable {
    let axis: TraitAxis
    let score: Double

    var trait: Trait? {
        if score >= Traits.visible { return axis.plus }
        if score <= -Traits.visible { return axis.minus }
        return nil
    }

    var strong: Bool { abs(score) >= Traits.strong }

    /// «Игривый» / «Очень игривый»; nil — черта не видна.
    var title: String? { trait.map { strong ? $0.strongTitle : $0.title } }
}

/// Уход по местным дням для характера. Пустое в файл не пишется, новому щенку не переходит.
struct CareTally: Codable, Hashable, Sendable {
    /// Последняя разобранная запись журнала этого устройства. nil — учёт ещё не заводился.
    var seq: Int?
    /// Местный день (строкой, для JSON) → вид действия → сколько раз.
    var days: [String: [String: Int]] = [:]
    /// Последний засчитанный раз по виду: не чаще Traits.gap.
    var last: [String: Double] = [:]

    init() {}

    var isEmpty: Bool { seq == nil && days.isEmpty && last.isEmpty }

    enum CodingKeys: String, CodingKey { case seq, days, last }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seq = try? c.decodeIfPresent(Int.self, forKey: .seq)
        days = (try? c.decodeIfPresent([String: [String: Int]].self, forKey: .days)) ?? [:]
        last = (try? c.decodeIfPresent([String: Double].self, forKey: .last)) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(seq, forKey: .seq)
        if !days.isEmpty { try c.encode(days, forKey: .days) }
        if !last.isEmpty { try c.encode(last, forKey: .last) }
    }
}

enum Traits {
    /// Окно характера — местных дней (сегодня и 6 прошлых).
    static let windowDays = 7
    /// Меньше стольких засчитанных дел за окно — характер ещё складывается.
    static let minActs = 12
    /// Один вид засчитывается не чаще раза в полчаса.
    static let gap: Double = 30 * 60
    /// Черта видна от трети шкалы, «очень» — от двух третей.
    static let visible = 0.34
    static let strong = 0.67
    /// Что считаем: удачные действия ухода (еда и лекарство — забота о нуждах, не характер).
    static let counted: Set<String> = ["pet", "play", "walk", "bath", "brush"]

    // MARK: учёт

    /// Разобрать новые записи журнала (в первый раз — всё из журнала и outbox) и выкинуть дни старше окна.
    /// Вызывает PetStore после каждой записи сейва.
    static func update(_ f: inout SaveFile) {
        var tally = f.care
        let tz = f.owner.tzOffsetMin
        let batch: [JournalEntry]
        if tally.seq == nil {
            batch = Postcards.entries(f)
        } else {
            let from = tally.seq ?? 0
            let prefix = "\(f.deviceId):"
            var seen = Set<String>()
            batch = (f.outbox + f.journal).filter { e in
                guard e.id.hasPrefix(prefix), let s = Int(e.id.dropFirst(prefix.count)), s > from else { return false }
                return seen.insert(e.id).inserted
            }.sorted { $0.t != $1.t ? $0.t < $1.t : $0.id < $1.id }
        }
        for e in batch where e.ok == true && e.kind.hasPrefix("act.") {
            let kind = String(e.kind.dropFirst(4))
            guard counted.contains(kind) else { continue }
            if let prev = tally.last[kind], e.t - prev < gap, e.t >= prev { continue }
            tally.last[kind] = e.t
            let day = String(Postcards.day(e.t, tzOffsetMin: tz))
            tally.days[day, default: [:]][kind, default: 0] += 1
        }
        tally.seq = f.seq
        // Храним окно и день про запас (сегодня по часам питомца).
        let today = Postcards.day(f.pet.t, tzOffsetMin: tz)
        tally.days = tally.days.filter { (Int($0.key) ?? .min) > today - windowDays - 1 }
        if tally != f.care { f.care = tally }
    }

    /// Сколько раз каждого вида за окно до местного дня t (включительно).
    static func counts(_ f: SaveFile, at t: Double) -> [String: Int] {
        let today = Postcards.day(t, tzOffsetMin: f.owner.tzOffsetMin)
        var out: [String: Int] = [:]
        for (k, byKind) in f.care.days {
            guard let d = Int(k), d <= today, d > today - windowDays else { continue }
            for (kind, n) in byKind { out[kind, default: 0] += n }
        }
        return out
    }

    /// Засчитанных дел за окно — для «характер складывается: 5 из 12».
    static func total(_ f: SaveFile, at t: Double) -> Int {
        counts(f, at: t).values.reduce(0, +)
    }

    // MARK: черты

    /// Положение на всех осях. nil — ухода за окно мало, характер ещё складывается.
    static func scores(_ f: SaveFile, at t: Double) -> [TraitScore]? {
        let c = counts(f, at: t)
        let total = c.values.reduce(0, +)
        guard total >= minActs else { return nil }
        return TraitAxis.allCases.map { axis in
            let n = axis.kinds.reduce(0) { $0 + (c[$1] ?? 0) }
            let share = Double(n) / Double(total)
            return TraitScore(axis: axis, score: min(1, max(-1, (share - axis.mid) / axis.spread)))
        }
    }

    /// Видимые черты, сильные первыми.
    static func visibleTraits(_ f: SaveFile, at t: Double) -> [TraitScore] {
        (scores(f, at: t) ?? []).filter { $0.trait != nil }
            .sorted { abs($0.score) != abs($1.score) ? abs($0.score) > abs($1.score) : $0.axis.rawValue < $1.axis.rawValue }
    }

    /// Ведущая черта — самая заметная. nil — черт нет.
    static func lead(_ f: SaveFile, at t: Double) -> Trait? {
        visibleTraits(f, at: t).first?.trait
    }

    /// «Игривый и ласковый» — коротко о характере для альбома. nil — черт пока нет.
    static func summary(_ f: SaveFile, at t: Double) -> String? {
        let titles = visibleTraits(f, at: t).compactMap(\.title)
        guard let first = titles.first else { return nil }
        let rest = titles.dropFirst().map { $0.lowercased() }
        switch rest.count {
        case 0: return first
        case 1: return "\(first) и \(rest[0])"
        default: return "\(first), \(rest.dropLast().joined(separator: ", ")) и \(rest.last ?? "")"
        }
    }

    // MARK: отклик на тап

    /// Вид реакции на тап: «tap.playful» при ведущей черте, иначе просто «tap».
    static func tapKind(_ f: SaveFile, at t: Double) -> String {
        lead(f, at: t).map { "tap.\($0.rawValue)" } ?? "tap"
    }

    /// Черта из вида реакции «tap.<черта>».
    static func tapTrait(_ kind: String) -> Trait? {
        guard kind.hasPrefix("tap.") else { return nil }
        return Trait(rawValue: String(kind.dropFirst(4)))
    }

    /// Клипы отклика на тап стоя: игривый подпрыгнул, спокойный повёл ухом, ласковый склонил голову и вильнул,
    /// сам по себе оглянулся, чистюля отряхнулся, сорванец что-то унюхал.
    static func tapClips(_ t: Trait) -> [String] {
        switch t {
        case .playful: ["hop"]
        case .calm: ["ear_flick"]
        case .cuddly: ["head_tilt", "happy_wag"]
        case .independent: ["look_l"]
        case .tidy: ["shake"]
        case .scruffy: ["sniff"]
        }
    }
}

// MARK: - Мысли вслух

/// Реплика «из головы» вместо обычной в спокойное время: воспоминание или черта характера.
/// Ход — 2 часа; из 8 ходов 2 отданы воспоминаниям, 1 — характеру, остальные — обычным строкам. Какой ход чей —
/// хеш petId и номера хода, воспоминание крутится LineRotation без повторов подряд, строка — Lines.pick по слоту.
enum PetMind {
    enum Pick: Hashable, Sendable {
        case memory(Memory)
        case trait(Trait)
    }

    static let periodHours = 2
    static let turns: UInt64 = 8
    static let memoryTurns: UInt64 = 2
    static let traitTurns: UInt64 = 1

    static func slot(_ t: Double, tzOffsetMin: Int) -> Int {
        LineRotation.slot(t, tzOffsetMin: tzOffsetMin, periodHours: periodHours)
    }

    /// Чей ход на момент t. nil — обычная реплика (или вспомнить и сказать нечего).
    static func pick(_ f: SaveFile, at t: Double, tzOffsetMin: Int) -> Pick? {
        let s = slot(t, tzOffsetMin: tzOffsetMin)
        let roll = StableRandom.mix(StableHash.fnv1a("\(f.petId):mind:\(s)")) % turns
        if roll < memoryTurns {
            let all = Memories.recallable(f, at: t)
            guard !all.isEmpty else { return nil }
            let i = LineRotation.at(count: all.count, seed: StableHash.fnv1a("\(f.petId):recall"), position: s,
                                    block: LineRotation.block(count: all.count, gap: LineRotation.slotGap))
            return .memory(all[i])
        }
        if roll < memoryTurns + traitTurns {
            return Traits.lead(f, at: t).map { .trait($0) }
        }
        return nil
    }

    /// Строка для пузыря (island: false, до 40 знаков) или острова (до 20). nil — сказать нечего, обычная реплика.
    static func line(_ f: SaveFile, at t: Double, tzOffsetMin: Int, island: Bool = false,
                     lines: Lines = .shared) -> String? {
        guard let p = pick(f, at: t, tzOffsetMin: tzOffsetMin) else { return nil }
        let said: (key: String, vars: [String: String])?
        switch p {
        case .memory(let m): said = Memories.line(m)
        case .trait(let tr): said = (tr.lineKey, [:])
        }
        guard let said else { return nil }
        let (key, vars) = said
        let max = island ? LineLimit.island : LineLimit.widget
        guard let text = lines.pick(island ? "island" : "widget", key, seed: f.petId, slot: slot(t, tzOffsetMin: tzOffsetMin),
                                    vars: vars, maxLen: max)?.text,
              text.count <= max, !text.contains("{") else { return nil }
        return text
    }
}
