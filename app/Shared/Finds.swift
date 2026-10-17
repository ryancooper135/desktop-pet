// Находки с прогулки: id из config/economy.json (care.walk_out.finds) → русское имя, падеж, значок, цвет пропа.
// Порядок — как в конфиге (тест сверяет). Альбом, лента «Пока тебя не было», уведомление и сцена берут слова отсюда.
// Тут же WalkPlan: можно ли отпустить гулять и что написать на кнопке. Без UI — гоняется на Linux (Package.swift).

import Foundation
@preconcurrency import PetCore

struct Find: Hashable, Sendable, Identifiable {
    let id: String
    /// Именительный падеж со строчной: «шишка». Подставляется в {item} (README: вещь — в именительном).
    let name: String
    /// Винительный: «Принёс шишку».
    let acc: String
    /// Значок в альбоме и всплывашке. Эмодзи, а не SF Symbol: носка и шишки в SF нет. Вкус — за Вадимом.
    let emoji: String
    /// Цвет пропа в комнате (0xRRGGBB).
    let color: UInt32

    /// С заглавной: «Шишка».
    var title: String { name.prefix(1).uppercased() + name.dropFirst() }
}

enum Finds {
    /// В конфиге «Камушек», в интерфейсе — «камешек» (так просили). Ядро имён не читает.
    static let all: [Find] = [
        Find(id: "stick", name: "палка", acc: "палку", emoji: "🪵", color: 0x8A5A32),
        Find(id: "cone", name: "шишка", acc: "шишку", emoji: "🌰", color: 0x6E4A2C),
        Find(id: "ball", name: "мячик", acc: "мячик", emoji: "🎾", color: 0xD6DD4A),
        Find(id: "sock", name: "носок", acc: "носок", emoji: "🧦", color: 0xE9E4D8),
        Find(id: "leaf", name: "листик", acc: "листик", emoji: "🍂", color: 0xD9822B),
        Find(id: "pebble", name: "камешек", acc: "камешек", emoji: "🪨", color: 0x8E8C86),
    ]

    static func find(_ id: String) -> Find? { all.first { $0.id == id } }

    /// Незнакомый id (новая находка в конфиге раньше приложения) — нейтральное «находка».
    static func name(_ id: String) -> String { find(id)?.name ?? "находка" }
    static func acc(_ id: String) -> String { find(id)?.acc ?? "находку" }

    /// Строки альбома: все известные находки по порядку и сколько каждой. Незнакомые id — в конце.
    static func album(_ finds: [String: Int]) -> [(find: Find, count: Int)] {
        var rows = all.map { (find: $0, count: max(0, finds[$0.id] ?? 0)) }
        for (id, n) in finds.sorted(by: { $0.key < $1.key }) where find(id) == nil && n > 0 {
            rows.append((Find(id: id, name: "находка", acc: "находку", emoji: "✨", color: 0xC9B27A), n))
        }
        return rows
    }

    /// Сколько всего принёс (= PetEngine.walksDone).
    static func total(_ finds: [String: Int]) -> Int { finds.values.reduce(0) { $0 + max(0, $1) } }

    /// Сколько разных находок уже есть из известных.
    static func kinds(_ finds: [String: Int]) -> Int { all.filter { (finds[$0.id] ?? 0) > 0 }.count }

    /// Подпись записки в пустой комнате: «Ушёл гулять, вернусь в 14:20».
    static func awayNote(until: Double, tzOffsetMin: Int) -> String {
        "Ушёл гулять, вернусь в \(clock(until, tzOffsetMin: tzOffsetMin))"
    }

    /// «14:20» по местному сдвигу (минуты к UTC), без DateFormatter: одинаково на Linux и в тестах.
    static func clock(_ t: Double, tzOffsetMin: Int) -> String {
        let m = Int((t / 60).rounded(.down)) + tzOffsetMin
        let day = ((m % 1440) + 1440) % 1440
        let hh = day / 60, mm = day % 60
        return "\(hh):" + (mm < 10 ? "0\(mm)" : "\(mm)")
    }

    /// Всплывашка при возвращении: «Принёс шишку!».
    static func broughtText(_ id: String) -> String { "Принёс \(acc(id))!" }

    /// Вернулся ли с прогулки между двумя взглядами на состояние: была прогулка, теперь нет, жив.
    /// Возвращает id находки (она уже в альбоме) или nil. Прогулка могла кончиться раньше until — ночью или в беде.
    static func returned(before: Outing?, after s: PetState) -> String? {
        guard let w = before, s.outing == nil, s.alive else { return nil }
        return w.find
    }
}

// MARK: - Кнопка «Гулять»

/// Можно ли сейчас отпустить гулять и что написать на кнопке. Решает ядро (PetEngine.act на копии),
/// здесь только слова: подпись под кнопкой (до 24 знаков) и тост по тапу на неактивную кнопку.
struct WalkGate: Equatable, Sendable {
    /// Ядро примет .walk.
    var ok: Bool
    /// Причина отказа ядра: away, bathing, asleep, unwell, not_ready, too_late, unavailable, dead.
    var reason: String?
    /// Подпись под кнопкой: «1–3 ч, с находкой», «вернётся в 14:20», «сначала покормить».
    var hint: String
    /// Тост по тапу на неактивную кнопку (почему нельзя и что сделать).
    var toast: String
    /// Конец прогулки, пока гуляет.
    var until: Double?
}

enum WalkPlan {
    static func gate(_ f: SaveFile, at t: Double) -> WalkGate {
        gate(PetRunner.peek(f, at: t), Catalog.rules, PetRunner.owner(f, at: t))
    }

    /// s — стейт, уже досчитанный до нужного момента (s.t).
    static func gate(_ s: PetState, _ r: Rules, _ o: Owner) -> WalkGate {
        if let w = s.outing, s.alive {
            let at = Finds.clock(w.until, tzOffsetMin: o.tzOffsetMin)
            return WalkGate(ok: false, reason: "away", hint: "вернётся в \(at)",
                            toast: Finds.awayNote(until: w.until, tzOffsetMin: o.tzOffsetMin), until: w.until)
        }
        var c = s
        let res = PetEngine.act(&c, r, o, .walk)
        if res.ok, let w = r.walkOut {
            let a = w.minMin / 60, b = (w.maxMin + 59) / 60
            let span = a == b ? "\(a) ч" : "\(max(1, a))–\(b) ч"
            return WalkGate(ok: true, reason: nil, hint: "\(span), с находкой", toast: "", until: nil)
        }
        let reason = res.reason ?? "unavailable"
        switch reason {
        case "not_ready":
            let todo = lacking(s, r).map(todoWord)
            let list = todo.isEmpty ? "покормить и почистить" : joined(todo)
            return WalkGate(ok: false, reason: reason, hint: "сначала \(list)",
                            toast: "Для прогулки сначала \(list)", until: nil)
        case "asleep":
            return WalkGate(ok: false, reason: reason, hint: "спит", toast: RefuseText.text(reason), until: nil)
        case "too_late":
            return WalkGate(ok: false, reason: reason, hint: "поздно, завтра", toast: RefuseText.text(reason), until: nil)
        case "bathing":
            return WalkGate(ok: false, reason: reason, hint: "моется", toast: RefuseText.text(reason), until: nil)
        case "unwell":
            return WalkGate(ok: false, reason: reason, hint: "сначала помоги", toast: RefuseText.text(reason), until: nil)
        case "dead":
            return WalkGate(ok: false, reason: reason, hint: "", toast: RefuseText.text(reason), until: nil)
        default:
            return WalkGate(ok: false, reason: reason, hint: "пока нельзя", toast: RefuseText.text(reason), until: nil)
        }
    }

    /// Каких шкал не хватает для прогулки: шкала, которая и при остальных на 100 не пускает.
    /// Условие в конфиге — «a >= x && b >= y», поэтому так находятся ровно виноватые.
    static func lacking(_ s: PetState, _ r: Rules) -> [Need] {
        guard let w = r.walkOut else { return [] }
        return [Need.food, .clean, .energy, .fun, .love, .walk].filter { n in
            var v: [Need: Double] = [:]
            for k in Need.allCases { v[k] = 100 }
            v[n] = s.needs[n] ?? 0
            return !w.requires(v)
        }
    }

    static func todoWord(_ n: Need) -> String {
        switch n {
        case .food: return "покормить"
        case .clean: return "помыть"
        case .energy: return "дать отдохнуть"
        case .fun: return "поиграть"
        case .love: return "погладить"
        default: return "позаботиться"
        }
    }

    /// «покормить», «покормить и помыть», «покормить, помыть и дать отдохнуть».
    static func joined(_ w: [String]) -> String {
        guard w.count > 1 else { return w.first ?? "" }
        return w.dropLast().joined(separator: ", ") + " и " + w[w.count - 1]
    }
}
