// Вкусы раскрываются со временем (RESEARCH/06 #11). У каждого питомца скрыто: любимая и нелюбимая еда,
// игрушка и находка с прогулки, остальное — без разницы. Выбор детерминирован от petId (StableHash),
// хозяин угадывает по реакциям: дал одно и то же K раз с одной реакцией — вкус «открыт» и лёг в альбом.
// Ядро не трогаем: бонус к шкалам — множитель к тому, что ядро уже прибавило (только к плюсам).
// Без экрана (Foundation + PetCore) — гоняется на Linux (app/Package.swift).

import Foundation
@preconcurrency import PetCore

enum TasteCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case food, toy, find
}

/// Как питомец относится к вещи.
enum Taste: String, Codable, CaseIterable, Hashable, Sendable {
    case love, like, neutral, dislike
}

/// Реакция на вещь: что сыграть, насколько сильно, какой множитель к шкалам и какая реплика.
struct TasteReaction: Hashable, Sendable {
    let category: TasteCategory
    let item: String
    let taste: Taste
    /// Сила для хореографии 0…1: love 1, dislike 0.75, like 0.55, neutral 0.25.
    let strength: Double
    /// Множитель к прибавке шкал от действия (только к плюсам, минусы ядра не трогаем).
    let needX: Double
    /// Ключ реплики в lines.json (widget/island) или nil — реакция без слов.
    let lineKey: String?
    /// Подсказка хореографии: клипы shiba.clips.json по порядку. Пусто — обычная анимация действия.
    let clips: [String]
    /// Вкус уже открыт (в альбоме).
    let known: Bool
}

/// Открытый вкус — запись альбома: «Обожает морковку».
struct TasteFact: Hashable, Sendable, Identifiable {
    let category: TasteCategory
    let item: String
    let taste: Taste
    let openedT: Double
    /// Строка альбома.
    let text: String
    /// Значок вещи (эмодзи, как у находок).
    let emoji: String

    var id: String { Tastes.key(category, item) }
}

/// Итог одного наблюдения: реакция, засчитано ли (не чаще gap), сколько согласованных подряд и открылся ли вкус.
struct TasteObservation: Hashable, Sendable {
    let reaction: TasteReaction
    let counted: Bool
    let count: Int
    let opened: TasteFact?

    /// Реплика: открытие важнее самой реакции.
    var lineKey: String? { opened != nil ? Tastes.openLineKey : reaction.lineKey }
}

/// Что хозяин уже видел. Компактно: ключ «food.carrot».
struct TasteLog: Codable, Hashable, Sendable {
    /// n — сколько согласованных наблюдений подряд, t — последнее засчитанное, r — реакция (Taste.rawValue).
    struct Seen: Codable, Hashable, Sendable {
        var n: Int
        var t: Double
        var r: String
    }

    /// Открытый вкус: реакция и когда открылся. Открытое не пересчитывается (даже если поменяли конфиг).
    struct Fact: Codable, Hashable, Sendable {
        var r: String
        var t: Double
    }

    var seen: [String: Seen] = [:]
    var opened: [String: Fact] = [:]

    init() {}

    var isEmpty: Bool { seen.isEmpty && opened.isEmpty }

    enum CodingKeys: String, CodingKey { case seen, opened }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seen = (try? c.decodeIfPresent([String: Seen].self, forKey: .seen)) ?? [:]
        opened = (try? c.decodeIfPresent([String: Fact].self, forKey: .opened)) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !seen.isEmpty { try c.encode(seen, forKey: .seen) }
        if !opened.isEmpty { try c.encode(opened, forKey: .opened) }
    }
}

enum Tastes {
    /// Сколько согласованных наблюдений открывает вкус. Находка бывает раз в прогулку — ей хватит двух.
    static let neededBy: [TasteCategory: Int] = [.food: 3, .toy: 3, .find: 2]
    /// Наблюдения чаще раза в 20 минут не считаются: повтор того же действия и спам кнопкой ничего не открывают.
    static let gap: Double = 20 * 60
    /// Игра в комнате — мячиком (ядро .play без игрушки). Когда появится выбор игрушки — передавать её id.
    static let playToy = "ball"
    /// Можно любить, нельзя не любить: главная еда и мячик комнаты, иначе базовый уход станет хуже.
    static let staples: Set<String> = ["food.kibble", "toy.ball"]
    /// Редкость, которая нравится всем, если вещь не любимая и не нелюбимая.
    static let treatRarity: Set<String> = ["epic", "legendary"]

    static let openLineKey = "taste_open"

    static func needed(_ c: TasteCategory) -> Int { neededBy[c] ?? 3 }
    static func key(_ c: TasteCategory, _ item: String) -> String { "\(c.rawValue).\(item)" }

    // MARK: каталог

    private struct Pool: Sendable {
        let items: [TasteCategory: [String]]
        let rarity: [String: String]
    }

    private static let pool: Pool = loadPool()

    /// Кандидаты в любимое/нелюбимое: еда из shop.food без легендарной (её любят все), игрушки shop.toys,
    /// находки care.walk_out.finds. Порядок — как в конфиге.
    static func candidates(_ c: TasteCategory) -> [String] { pool.items[c] ?? [] }

    private static func loadPool() -> Pool {
        var items: [TasteCategory: [String]] = [:]
        var rarity: [String: String] = [:]
        if let data = Catalog.resource("economy", "json"), let e = try? JSONDecoder().decode(JSONValue.self, from: data) {
            for (section, cat) in [("food", TasteCategory.food), ("toys", .toy)] {
                var ids: [String] = []
                for it in e["shop"][section].array {
                    guard let id = it["id"].string else { continue }
                    let r = it["rarity"].string ?? "common"
                    rarity[key(cat, id)] = r
                    if r != "legendary" { ids.append(id) }
                }
                items[cat] = ids
            }
            items[.find] = e["care"]["walk_out"]["finds"].array.compactMap { $0["id"].string ?? $0.string }
        }
        if (items[.find] ?? []).isEmpty { items[.find] = Finds.all.map(\.id) }
        return Pool(items: items, rarity: rarity)
    }

    // MARK: скрытые вкусы

    /// Любимое и нелюбимое в категории от petId. Рандеву-хеш: у каждой вещи свой балл, побеждает максимум —
    /// новая вещь в конфиге меняет вкус, только если сама выиграла. Открытые вкусы закреплены.
    static func hidden(petId: String, _ c: TasteCategory, log: TasteLog = TasteLog()) -> (love: String?, dislike: String?) {
        let items = candidates(c)
        var love = pinned(log, c, .love)
        var dislike = pinned(log, c, .dislike)
        if love == nil {
            love = best(items.filter { $0 != dislike }, petId, c, "love")
        }
        if dislike == nil {
            dislike = best(items.filter { $0 != love && !staples.contains(key(c, $0)) }, petId, c, "dislike")
        }
        return (love, dislike)
    }

    private static func pinned(_ log: TasteLog, _ c: TasteCategory, _ t: Taste) -> String? {
        let prefix = "\(c.rawValue)."
        return log.opened.filter { $0.key.hasPrefix(prefix) && $0.value.r == t.rawValue }
            .min { $0.value.t < $1.value.t }.map { String($0.key.dropFirst(prefix.count)) }
    }

    private static func best(_ items: [String], _ petId: String, _ c: TasteCategory, _ role: String) -> String? {
        var top: (id: String, score: UInt64)?
        for id in items {
            let s = StableRandom.mix(StableHash.fnv1a("\(petId):taste:\(c.rawValue):\(role):\(id)"))
            if top == nil || s > top!.score || (s == top!.score && id < top!.id) { top = (id, s) }
        }
        return top?.id
    }

    /// Отношение к вещи. Открытое — как записано; иначе любимое/нелюбимое; редкое лакомство — like.
    static func taste(_ c: TasteCategory, _ item: String, petId: String, log: TasteLog = TasteLog()) -> Taste {
        if let f = log.opened[key(c, item)], let t = Taste(rawValue: f.r) { return t }
        let h = hidden(petId: petId, c, log: log)
        if item == h.love { return .love }
        if item == h.dislike { return .dislike }
        if let r = pool.rarity[key(c, item)], treatRarity.contains(r) { return .like }
        return .neutral
    }

    // MARK: реакция

    static func reaction(_ c: TasteCategory, _ item: String, petId: String, log: TasteLog = TasteLog()) -> TasteReaction {
        let t = taste(c, item, petId: petId, log: log)
        let line: String?
        let clips: [String]
        let strength: Double
        let x: Double
        switch t {
        case .love:
            line = c == .find ? "taste_find_love" : "taste_love"
            clips = c == .find ? ["happy_wag", "hop", "gallop_jump"] : ["happy_wag", "hop"]
            strength = 1; x = 1.25
        case .like:
            line = nil; clips = ["idle_wag"]; strength = 0.55; x = 1.1
        case .neutral:
            line = nil; clips = []; strength = 0.25; x = 1
        case .dislike:
            line = "taste_dislike"; clips = ["sniff", "head_tilt"]; strength = 0.75; x = 0.85
        }
        return TasteReaction(category: c, item: item, taste: t, strength: strength, needX: x, lineKey: line,
                             clips: clips, known: log.opened[key(c, item)] != nil)
    }

    static func reaction(_ c: TasteCategory, _ item: String, in f: SaveFile) -> TasteReaction {
        reaction(c, item, petId: f.petId, log: f.tastes)
    }

    /// О чём действие с точки зрения вкусов: кормление — еда, игра — игрушка. Остальное — без вкуса.
    static func subject(_ a: PetAction) -> (category: TasteCategory, item: String)? {
        switch a {
        case .feed(let id): return (.food, id)
        case .play: return (.toy, playToy)
        default: return nil
        }
    }

    /// Реакция на действие (для экрана сразу после тапа) или nil, если вкус ни при чём.
    static func reaction(for a: PetAction, in f: SaveFile) -> TasteReaction? {
        subject(a).map { reaction($0.category, $0.item, in: f) }
    }

    /// Находка дня: любимая — сильнее радость (taste_find_love, прыжки), нелюбимая — сдержанно.
    static func findReaction(_ findId: String, in f: SaveFile) -> TasteReaction {
        reaction(.find, findId, in: f)
    }

    // MARK: наблюдения

    /// Записать, что хозяин дал вещь в момент t. Не чаще gap; смена реакции сбрасывает счёт.
    /// K-е согласованное наблюдение love/dislike открывает вкус (журнал taste.open, ключ «food.carrot»).
    @discardableResult
    static func observe(_ c: TasteCategory, _ item: String, at t: Double, in f: inout SaveFile) -> TasteObservation {
        let r = reaction(c, item, in: f)
        let k = key(c, item)
        if r.known {
            return TasteObservation(reaction: r, counted: false, count: needed(c), opened: nil)
        }
        let prev = f.tastes.seen[k]
        if let prev, t < prev.t + gap {
            return TasteObservation(reaction: r, counted: false, count: prev.r == r.taste.rawValue ? prev.n : 0, opened: nil)
        }
        let n = (prev?.r == r.taste.rawValue ? prev?.n ?? 0 : 0) + 1
        guard (r.taste == .love || r.taste == .dislike), n >= needed(c) else {
            f.tastes.seen[k] = TasteLog.Seen(n: n, t: t, r: r.taste.rawValue)
            return TasteObservation(reaction: r, counted: true, count: n, opened: nil)
        }
        f.tastes.seen[k] = nil
        f.tastes.opened[k] = TasteLog.Fact(r: r.taste.rawValue, t: t)
        f.log("taste.open", t: t, key: k)
        let fact = Self.fact(k, f.tastes.opened[k]!)
        let opened = TasteReaction(category: c, item: item, taste: r.taste, strength: r.strength, needX: r.needX,
                                   lineKey: r.lineKey, clips: r.clips, known: true)
        return TasteObservation(reaction: opened, counted: true, count: n, opened: fact)
    }

    /// Сколько согласованных наблюдений набрано (для подсказки «ещё чуть-чуть»). Открытый — needed.
    static func progress(_ c: TasteCategory, _ item: String, in f: SaveFile) -> Int {
        let k = key(c, item)
        if f.tastes.opened[k] != nil { return needed(c) }
        return f.tastes.seen[k]?.n ?? 0
    }

    /// После удачного действия (PetRunner.apply): множитель к прибавке шкал и наблюдение.
    @discardableResult
    static func afterAction(_ a: PetAction, before: [Need: Double], at t: Double, in f: inout SaveFile) -> TasteObservation? {
        guard let s = subject(a) else { return nil }
        let r = reaction(s.category, s.item, in: f)
        if r.needX != 1 {
            for (n, v) in f.pet.needs {
                guard let b = before[n], v > b else { continue }
                f.pet.needs[n] = min(100, max(0, b + (v - b) * r.needX))
            }
        }
        return observe(s.category, s.item, at: t, in: &f)
    }

    /// Вернулся с прогулки (PetRunner.catchUp): находка — тоже наблюдение. Шкал не трогает.
    @discardableResult
    static func afterWalk(_ w: Outing, at t: Double, in f: inout SaveFile) -> TasteObservation {
        observe(.find, w.find, at: min(w.until, t), in: &f)
    }

    // MARK: альбом

    /// Открытые вкусы по времени открытия.
    static func album(_ f: SaveFile) -> [TasteFact] {
        f.tastes.opened.map { fact($0.key, $0.value) }.sorted { ($0.openedT, $0.id) < ($1.openedT, $1.id) }
    }

    /// Открытые после since (для всплывашки «Открыл вкус!» и ленты «Пока тебя не было»).
    static func opened(_ f: SaveFile, since: Double) -> [TasteFact] {
        album(f).filter { $0.openedT > since }
    }

    private static func fact(_ k: String, _ v: TasteLog.Fact) -> TasteFact {
        let parts = k.split(separator: ".", maxSplits: 1).map(String.init)
        let c = TasteCategory(rawValue: parts.first ?? "") ?? .food
        let item = parts.count > 1 ? parts[1] : k
        let t = Taste(rawValue: v.r) ?? .neutral
        return TasteFact(category: c, item: item, taste: t, openedT: v.t, text: text(c, item, t), emoji: emoji(c, item))
    }

    /// «Обожает морковку», «Не любит брокколи», «Любимая находка — шишка», «Не в восторге, когда находит носок».
    static func text(_ c: TasteCategory, _ item: String, _ t: Taste) -> String {
        switch (c, t) {
        case (.find, .love): return "Любимая находка — \(Finds.name(item))"
        case (.find, .dislike): return "Не в восторге, когда находит \(Finds.acc(item))"
        case (.find, _): return "Находит \(Finds.acc(item))"
        case (_, .love): return "Обожает \(acc(item))"
        case (_, .dislike): return "Не любит \(acc(item))"
        case (_, .like): return "Любит \(acc(item))"
        case (_, .neutral): return "\(Catalog.name(item)) — без разницы"
        }
    }

    /// Винительный падеж со строчной для еды и игрушек. Незнакомое — имя из каталога со строчной.
    static let accusative: [String: String] = [
        "kibble": "хрустики", "carrot": "морковку", "broccoli": "брокколи", "milk": "тёплое молоко",
        "sausage": "сосиску", "stew": "мясное рагу", "fish": "рыбку", "pizza": "пиццу", "cake": "тортик",
        "gold_bone": "золотую косточку",
        "ball": "мячик", "squeaky": "пищалку", "rope": "канат", "laser": "лазерную указку", "robot": "робо-мышь",
    ]

    static func acc(_ item: String) -> String {
        if let a = accusative[item] { return a }
        let n = Catalog.name(item)
        return n.prefix(1).lowercased() + n.dropFirst()
    }

    static let emojis: [String: String] = [
        "kibble": "🥣", "carrot": "🥕", "broccoli": "🥦", "milk": "🥛", "sausage": "🌭", "stew": "🍲",
        "fish": "🐟", "pizza": "🍕", "cake": "🍰", "gold_bone": "🦴",
        "ball": "🎾", "squeaky": "🐤", "rope": "🪢", "laser": "🔴", "robot": "🐭",
    ]

    static func emoji(_ c: TasteCategory, _ item: String) -> String {
        if c == .find { return Finds.find(item)?.emoji ?? "✨" }
        return emojis[item] ?? "✨"
    }

    // MARK: реплики

    /// Реплика по ключу taste_* для виджета (до 40) или острова (до 20). nil — строк нет.
    static func line(_ key: String, island: Bool = false, seed: String, at t: Double, tzOffsetMin: Int = 0,
                     lines: Lines = .shared) -> String? {
        let section = island ? "island" : "widget"
        return lines.pick(section, key, seed: seed, at: t, tzOffsetMin: tzOffsetMin,
                          maxLen: island ? LineLimit.island : LineLimit.widget)?.text
    }
}
