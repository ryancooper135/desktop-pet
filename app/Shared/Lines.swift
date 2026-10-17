// Реплики из content/ru/lines.json. Правила выбора — content/README.md:
// кандидаты текущего tier плюс строки без tier; строки с подстановкой, для которой нет значения, пропускаются;
// выбор стабильный и без истории: ротация пула по LineRotation (seed:раздел:ключ), без повторов 7 дней.
// Виджет и остров — по времени (ход 4–24 ч от размера пула), уведомления — по дню, лента — по часу.

import Foundation
@preconcurrency import PetCore

struct LineItem: Hashable, Sendable {
    let id: String
    let text: String          // для уведомлений — body
    let title: String?
    let tier: Int?
    var frame: String? = nil  // редкий кадр: ключ позы/клипа пасхалки
}

struct Thought: Hashable, Sendable {
    let icon: String
    let text: String
}

/// Лимиты длины из content/README.md.
enum LineLimit {
    static let widget = 40
    static let island = 20
    static let thought = 24
    static let away = 70
    static let notifTitle = 30
    static let notifBody = 90
}

struct Lines: Sendable {
    /// раздел → ключ → строки
    let sections: [String: [String: [LineItem]]]
    let thoughts: [String: Thought]

    static let shared: Lines = load()

    static let empty = Lines(sections: [:], thoughts: [:])

    static func load() -> Lines {
        guard let data = Catalog.resource("lines", "json"),
              let j = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .empty }
        var sections: [String: [String: [LineItem]]] = [:]
        for name in ["notifications", "widget", "island", "away"] {
            var byKey: [String: [LineItem]] = [:]
            for (key, arr) in j[name].object {
                byKey[key] = arr.array.compactMap { (it: JSONValue) -> LineItem? in
                    guard let text = it["text"].string ?? it["body"].string else { return nil }
                    return LineItem(id: it["id"].string ?? key, text: text, title: it["title"].string,
                                    tier: it["tier"].double.map { Int($0) }, frame: it["frame"].string)
                }
            }
            sections[name] = byKey
        }
        var thoughts: [String: Thought] = [:]
        for (key, it) in j["thoughts"].object {
            if let icon = it["icon"].string, let text = it["text"].string { thoughts[key] = Thought(icon: icon, text: text) }
        }
        return Lines(sections: sections, thoughts: thoughts)
    }

    // MARK: выбор

    /// Одна строка на момент t или nil, если подходящих нет. Строка держится весь ход (4–24 ч — по размеру пула)
    /// и не повторяется 7 дней. vars — значения для {item}, {count}, {steps}, {friend}.
    func pick(_ section: String, _ key: String, seed: String, at t: Double, tzOffsetMin: Int = 0, tier: Int? = nil,
              vars: [String: String] = [:], maxLen: Int? = nil) -> LineItem? {
        guard let all = sections[section]?[key], !all.isEmpty else { return nil }
        let plan = LineRotation.plan(count: all.count, slack: Self.slack(all))
        let pos = LineRotation.slot(t, tzOffsetMin: tzOffsetMin, periodHours: plan.periodHours)
        // Недоступная на этом ходу строка уступает ход предыдущей доступной: строку видно подряд, а не вразнобой.
        let ok = eligible(all, tier: tier, vars: vars, maxLen: maxLen)
        guard let i = LineRotation.walk(count: all.count, seed: Self.rotationSeed(seed, section, key), position: pos,
                                        block: plan.block, eligible: ok) else { return nil }
        return Self.filled(all[i], vars)
    }

    /// То же по номеру слота (уведомления — день, лента — час). События дискретные, удерживать строку нельзя,
    /// поэтому крутим только доступные: повтор не раньше чем через min(gap, их число) слотов.
    func pick(_ section: String, _ key: String, seed: String, slot: Int, gap: Int = LineRotation.slotGap,
              tier: Int? = nil, vars: [String: String] = [:], maxLen: Int? = nil) -> LineItem? {
        guard let all = sections[section]?[key], !all.isEmpty else { return nil }
        let ok = eligible(all, tier: tier, vars: vars, maxLen: maxLen)
        let idx = all.indices.filter { ok[$0] }
        guard !idx.isEmpty else { return nil }
        let k = LineRotation.at(count: idx.count, seed: Self.rotationSeed(seed, section, key), position: slot,
                                block: LineRotation.block(count: idx.count, gap: gap))
        return Self.filled(all[idx[k]], vars)
    }

    /// Первая строка из списка ключей (например, react_feed → hungry → ok).
    func first(_ section: String, _ keys: [String], seed: String, at t: Double, tzOffsetMin: Int = 0, tier: Int? = nil,
               vars: [String: String] = [:], maxLen: Int? = nil) -> LineItem? {
        for k in keys {
            if let it = pick(section, k, seed: seed, at: t, tzOffsetMin: tzOffsetMin, tier: tier, vars: vars, maxLen: maxLen) {
                return it
            }
        }
        return nil
    }

    func first(_ section: String, _ keys: [String], seed: String, slot: Int, tier: Int? = nil,
               vars: [String: String] = [:], maxLen: Int? = nil) -> LineItem? {
        for k in keys {
            if let it = pick(section, k, seed: seed, slot: slot, tier: tier, vars: vars, maxLen: maxLen) { return it }
        }
        return nil
    }

    /// Доступность строк пула с прежними откатами: нет строк этого tier — берём все; нечем заполнить
    /// подстановки — только строки без подстановок; длиннее maxLen — только если коротких нет.
    func eligible(_ all: [LineItem], tier: Int?, vars: [String: String], maxLen: Int?) -> [Bool] {
        var ok = [Bool](repeating: true, count: all.count)
        if let tier {
            let byTier = all.map { $0.tier == nil || $0.tier == tier }
            if byTier.contains(true) { ok = byTier }
        }
        let holes = all.map { Self.placeholders($0.text + ($0.title ?? "")) }
        let fillable = all.indices.map { i in ok[i] && holes[i].allSatisfy { vars[$0] != nil } }
        ok = fillable.contains(true) ? fillable : all.indices.map { i in ok[i] && holes[i].isEmpty }
        if let maxLen {
            let short = all.indices.map { i in ok[i] && Self.fill(all[i].text, vars).count <= maxLen }
            if short.contains(true) { ok = short }
        }
        return ok
    }

    /// Сколько строк пула могут оказаться недоступны (tier или подстановки) — запас в плане ротации.
    static func slack(_ all: [LineItem]) -> Int {
        all.filter { $0.tier != nil || !placeholders($0.text + ($0.title ?? "")).isEmpty }.count
    }

    static func rotationSeed(_ seed: String, _ section: String, _ key: String) -> UInt64 {
        StableRandom.mix(StableHash.fnv1a("\(seed):\(section):\(key)"))
    }

    private static func filled(_ it: LineItem, _ vars: [String: String]) -> LineItem {
        LineItem(id: it.id, text: fill(it.text, vars), title: it.title.map { fill($0, vars) }, tier: it.tier, frame: it.frame)
    }

    // MARK: редкие кадры

    /// Пасхалка виджета, если момент t попал в редкий слот: строка из rare / rare_sleep, frame — ключ кадра.
    func rare(sleeping: Bool, seed: String, at t: Double, tzOffsetMin: Int = 0) -> LineItem? {
        guard let b = LineRotation.rareBlock(seed: seed, at: t, tzOffsetMin: tzOffsetMin) else { return nil }
        return pick("widget", sleeping ? "rare_sleep" : "rare", seed: seed, slot: b, gap: LineRotation.rareGap,
                    maxLen: LineLimit.widget)
    }

    /// Та же пасхалка для острова: строка с тем же frame, иначе любая из пула острова.
    func rareIsland(_ w: LineItem, sleeping: Bool, seed: String, at t: Double, tzOffsetMin: Int = 0) -> String? {
        let key = sleeping ? "rare_sleep" : "rare"
        if let f = w.frame, let it = sections["island"]?[key]?.first(where: { $0.frame == f }),
           it.text.count <= LineLimit.island {
            return it.text
        }
        guard let b = LineRotation.rareBlock(seed: seed, at: t, tzOffsetMin: tzOffsetMin) else { return nil }
        return pick("island", key, seed: seed, slot: b, gap: LineRotation.rareGap, maxLen: LineLimit.island)?.text
    }

    // MARK: обёртки с запасными текстами

    func widget(_ keys: [String], seed: String, at t: Double, tzOffsetMin: Int = 0, tier: Int? = nil) -> String {
        first("widget", keys + ["ok"], seed: seed, at: t, tzOffsetMin: tzOffsetMin, tier: tier,
              maxLen: LineLimit.widget)?.text ?? "Я тут"
    }

    func island(_ keys: [String], seed: String, at t: Double, tzOffsetMin: Int = 0, tier: Int? = nil) -> String {
        first("island", keys + ["ok"], seed: seed, at: t, tzOffsetMin: tzOffsetMin, tier: tier,
              maxLen: LineLimit.island)?.text ?? "Я тут"
    }

    func widget(_ keys: [String], seed: String, slot: Int, tier: Int? = nil) -> String {
        first("widget", keys + ["ok"], seed: seed, slot: slot, tier: tier, maxLen: LineLimit.widget)?.text ?? "Я тут"
    }

    func island(_ keys: [String], seed: String, slot: Int, tier: Int? = nil) -> String {
        first("island", keys + ["ok"], seed: seed, slot: slot, tier: tier, maxLen: LineLimit.island)?.text ?? "Я тут"
    }

    func thought(_ key: String) -> Thought {
        thoughts[key] ?? Thought(icon: "pawprint", text: "…")
    }

    func notification(_ key: String, seed: String, slot: Int, vars: [String: String] = [:]) -> (title: String, body: String) {
        if let it = pick("notifications", key, seed: seed, slot: slot, vars: vars, maxLen: LineLimit.notifBody) {
            return (it.title ?? "Шиба", it.text)
        }
        return ("Шиба", "Загляни ко мне")
    }

    /// Для ленты «Пока тебя не было»: nil — пункт пропустить.
    func away(_ key: String, seed: String, slot: Int, vars: [String: String] = [:]) -> String? {
        pick("away", key, seed: seed, slot: slot, vars: vars, maxLen: LineLimit.away)?.text
    }

    // MARK: подстановки

    static func placeholders(_ s: String) -> [String] {
        var out: [String] = []
        var rest = Substring(s)
        while let open = rest.firstIndex(of: "{") {
            let after = rest[rest.index(after: open)...]
            guard let close = after.firstIndex(of: "}") else { break }
            out.append(String(after[..<close]))
            rest = after[after.index(after: close)...]
        }
        return out
    }

    static func fill(_ s: String, _ vars: [String: String]) -> String {
        var out = s
        for (k, v) in vars { out = out.replacingOccurrences(of: "{\(k)}", with: v) }
        return out
    }
}
