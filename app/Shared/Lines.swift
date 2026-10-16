// Реплики из content/ru/lines.json. Правила выбора — content/README.md:
// кандидаты текущего tier плюс строки без tier; строки с подстановкой, для которой нет значения, пропускаются;
// выбор стабильный: (FNV-1a(seed:раздел:ключ) + слот) mod число строк. Слот — полчаса для виджета, день для уведомлений.

import Foundation
@preconcurrency import PetCore

struct LineItem: Hashable, Sendable {
    let id: String
    let text: String          // для уведомлений — body
    let title: String?
    let tier: Int?
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
                                    tier: it["tier"].double.map { Int($0) })
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

    /// Одна строка или nil, если подходящих нет. vars — значения для {item}, {count}, {steps}, {friend}.
    func pick(_ section: String, _ key: String, seed: String, slot: Int, tier: Int? = nil,
              vars: [String: String] = [:], maxLen: Int? = nil) -> LineItem? {
        guard let all = sections[section]?[key], !all.isEmpty else { return nil }
        var cands = all
        if let tier {
            let byTier = all.filter { $0.tier == nil || $0.tier == tier }
            if !byTier.isEmpty { cands = byTier }
        }
        // Подстановки: убрать строки, где нечем заполнить.
        let fillable = cands.filter { Self.placeholders($0.text + ($0.title ?? "")).allSatisfy { vars[$0] != nil } }
        cands = fillable.isEmpty ? cands.filter { Self.placeholders($0.text + ($0.title ?? "")).isEmpty } : fillable
        if cands.isEmpty { return nil }
        if let maxLen {
            let short = cands.filter { Self.fill($0.text, vars).count <= maxLen }
            if !short.isEmpty { cands = short }
        }
        let h = StableHash.fnv1a("\(seed):\(section):\(key)")
        let idx = Int((h &+ UInt64(max(0, slot))) % UInt64(cands.count))
        let it = cands[idx]
        return LineItem(id: it.id, text: Self.fill(it.text, vars), title: it.title.map { Self.fill($0, vars) }, tier: it.tier)
    }

    /// Первая строка из списка ключей (например, react_feed → hungry → ok).
    func first(_ section: String, _ keys: [String], seed: String, slot: Int, tier: Int? = nil,
               vars: [String: String] = [:], maxLen: Int? = nil) -> LineItem? {
        for k in keys {
            if let it = pick(section, k, seed: seed, slot: slot, tier: tier, vars: vars, maxLen: maxLen) { return it }
        }
        return nil
    }

    // MARK: обёртки с запасными текстами

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
