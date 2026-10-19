// Память питомца: яркие события из журнала — первая прогулка и находки, трюки, рекорд «Лови мячик»,
// первая вещь из автомата, уровни дома, дни вместе и любимые вкусы. Одна запись на событие (id без дублей), с датой.
// Обновляется в PetStore после каждой записи сейва: новые записи журнала разбираются один раз (по seq, как Economy.settle).
// Новому щенку память не переходит: она про этого пса. Реплики-воспоминания — PetMind (Traits.swift), альбом — «Помню».

import Foundation
@preconcurrency import PetCore

/// Одно воспоминание. id — вид и предмет: «walk.first», «find.cone», «trick.sit», «home.bed», «days.30».
struct Memory: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var t: Double
    /// Предмет: находка, трюк, вещь, вкус («food.carrot»).
    var key: String?
    /// Число: рекорд, уровень дома, дни.
    var value: Int?

    /// Вид: часть id до первой точки («find», «trick», …).
    var kind: String { String(id.split(separator: ".", maxSplits: 1).first ?? "") }
}

/// Память в state.json. Пустое в файл не пишется.
struct MemoryBook: Codable, Hashable, Sendable {
    var items: [Memory] = []
    /// Последняя разобранная запись журнала этого устройства. nil — книга ещё не заводилась (новый или старый сейв).
    var seq: Int?
    /// Рекорд «Лови мячик», с которого началась книга: рекорд, перешедший от прошлого щенка, — не воспоминание.
    var catchBase: Int?

    init() {}

    var isEmpty: Bool { items.isEmpty && seq == nil && catchBase == nil }

    subscript(_ id: String) -> Memory? { items.first { $0.id == id } }

    /// Добавить или (если такое уже есть) поправить на месте: одна запись на id.
    mutating func put(_ m: Memory) {
        if let i = items.firstIndex(where: { $0.id == m.id }) { items[i] = m } else { items.append(m) }
    }

    /// Добавить, только если такого ещё нет.
    mutating func add(_ m: Memory) {
        if self[m.id] == nil { items.append(m) }
    }

    enum CodingKeys: String, CodingKey { case items, seq, catchBase }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([Memory].self, forKey: .items)) ?? []
        seq = try? c.decodeIfPresent(Int.self, forKey: .seq)
        catchBase = try? c.decodeIfPresent(Int.self, forKey: .catchBase)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !items.isEmpty { try c.encode(items, forKey: .items) }
        try c.encodeIfPresent(seq, forKey: .seq)
        try c.encodeIfPresent(catchBase, forKey: .catchBase)
    }
}

/// Строка раздела «Помню» в альбоме.
struct MemoryRow: Hashable, Sendable, Identifiable {
    let id: String
    let t: Double
    let emoji: String
    let text: String
    /// «17 октября».
    let date: String
}

enum Memories {
    /// Самое раннее, что можно вспомнить в репликах, — не моложе суток: вчерашний трюк ещё не «помнишь, как…».
    static let recallAge: Double = 86400

    // MARK: обновление

    /// Разобрать новые записи журнала и состояние (трюки, вкусы, рекорд, дни). Вызывает PetStore после каждой записи.
    /// Первая встреча с книгой (новый или старый сейв) разбирает весь журнал и outbox, дальше — только новые записи.
    static func update(_ f: inout SaveFile) {
        let first = f.memories.seq == nil
        var book = f.memories
        let tz = f.owner.tzOffsetMin

        // Знакомство — с первой минуты.
        book.add(Memory(id: "met", t: f.createdT))

        // Новые записи журнала этого устройства (в первый раз — всё, что осталось в журнале и outbox).
        let batch: [JournalEntry]
        if first {
            batch = Postcards.entries(f)
        } else {
            let from = book.seq ?? 0
            let prefix = "\(f.deviceId):"
            var seen = Set<String>()
            batch = (f.outbox + f.journal).filter { e in
                guard e.id.hasPrefix(prefix), let s = Int(e.id.dropFirst(prefix.count)), s > from else { return false }
                return seen.insert(e.id).inserted
            }.sorted { $0.t != $1.t ? $0.t < $1.t : $0.id < $1.id }
        }
        if !batch.isEmpty { take(batch, into: &book, f) }
        book.seq = f.seq

        // Трюки: дата выучивания живёт в f.tricks.
        for t in Trick.allCases {
            if let at = f.tricks[t].learned { book.add(Memory(id: "trick.\(t.rawValue)", t: at, key: t.rawValue)) }
        }
        // Любимые вкусы: открытые love.
        for (k, v) in f.tastes.opened where v.r == Taste.love.rawValue {
            book.add(Memory(id: "taste.\(k)", t: v.t, key: k))
        }
        // Рекорд «Лови мячик»: только побитый при этой книге (перешедший от прошлого щенка — база).
        if book.catchBase == nil { book.catchBase = f.catchBest }
        if f.catchBest > (book.catchBase ?? 0), f.catchBest > (book["catch.record"]?.value ?? 0) {
            book.put(Memory(id: "catch.record", t: f.pet.t, value: f.catchBest))
        }
        // Дни вместе: вехи открыток (7, 30, 50…) и дни рождения — пока пёс жив.
        if f.pet.alive {
            let born = DayKey.of(f.createdT, tzOffsetMin: tz)
            let today = DayKey.of(f.pet.t, tzOffsetMin: tz)
            let n = today - born
            if n > 0 {
                for d in milestones(upTo: n) {
                    book.add(Memory(id: "days.\(d)", t: DayKey.start(born + d, tzOffsetMin: tz), value: d))
                }
            }
        }
        if book != f.memories { f.memories = book }
    }

    /// Вехи дней до n включительно: дни дружбы и кратные 365.
    static func milestones(upTo n: Int) -> [Int] {
        guard n > 0 else { return [] }
        var out = Postcards.friendDays.filter { $0 <= n }
        var y = 365
        while y <= n { out.append(y); y += 365 }
        return out.sorted()
    }

    /// Записи журнала → воспоминания. «Первое» засчитываем, только когда до пачки такого не было ни разу:
    /// число в состоянии минус записи пачки == 0. Так старый сейв, где ранние прогулки уже ушли из журнала,
    /// не получит «первую прогулку» задним числом.
    private static func take(_ batch: [JournalEntry], into book: inout MemoryBook, _ f: SaveFile) {
        // Находки: f.pet.finds — всего по видам, уже с этой пачкой.
        let homes = batch.filter { $0.kind.hasPrefix("ev.back_home") }
        var priorWalks = f.pet.finds.values.reduce(0, +) - homes.count
        var priorById: [String: Int] = [:]
        for e in homes { if let id = findId(e) { priorById[id, default: 0] += 1 } }
        for (id, n) in priorById { priorById[id] = (f.pet.finds[id] ?? 0) - n }
        // Автомат: f.econ.capsule.pulls — всего круток, уже с этой пачкой.
        var priorPulls = f.econ.capsule.pulls - batch.filter { $0.kind == "capsule" }.count
        // Записей больше, чем знает состояние (журнал с другого сейва), — «первое» не проверить: не засчитываем.
        if priorWalks < 0 { priorWalks = 1 }
        if priorPulls < 0 { priorPulls = 1 }
        for (id, n) in priorById where n < 0 { priorById[id] = 1 }

        for e in batch {
            switch e.kind {
            case let k where k.hasPrefix("ev.back_home"):
                guard let id = findId(e) else { priorWalks += 1; continue }
                if priorWalks == 0 { book.add(Memory(id: "walk.first", t: e.t, key: id)) }
                // Первая находка этого вида; та, что пришла с первой прогулки, — уже в walk.first.
                if priorById[id] == 0, book["walk.first"]?.key != id || book["walk.first"]?.t != e.t {
                    book.add(Memory(id: "find.\(id)", t: e.t, key: id))
                }
                priorWalks += 1
                priorById[id, default: 0] += 1
            case "capsule":
                if priorPulls == 0, let item = e.key { book.add(Memory(id: "item.first", t: e.t, key: item)) }
                priorPulls += 1
            case "home.buy":
                guard let line = e.key, let lv = e.value, lv > 0 else { continue }
                // Одна запись на линию: последний купленный уровень.
                if (book["home.\(line)"]?.value ?? 0) < lv {
                    book.put(Memory(id: "home.\(line)", t: e.t, key: line, value: lv))
                }
            default:
                break
            }
        }
    }

    /// Находка записи ev.back_home: key или хвост вида («ev.back_home.cone»).
    static func findId(_ e: JournalEntry) -> String? {
        e.key ?? e.kind.split(separator: ".").dropFirst(2).first.map(String.init)
    }

    // MARK: альбом

    /// «Помню»: новые сверху, знакомство — последним.
    static func album(_ f: SaveFile) -> [MemoryRow] {
        let firstTrick = firstTrickId(f.memories)
        return f.memories.items
            .sorted { ($0.t, $0.id) > ($1.t, $1.id) }
            .compactMap { m in
                guard let text = text(m, firstTrick: firstTrick) else { return nil }
                let day = DayKey.of(m.t, tzOffsetMin: f.owner.tzOffsetMin)
                return MemoryRow(id: m.id, t: m.t, emoji: emoji(m), text: text, date: Postcards.dateLabel(day))
            }
    }

    /// Самый ранний выученный трюк — он «первый».
    static func firstTrickId(_ book: MemoryBook) -> String? {
        book.items.filter { $0.kind == "trick" }.min { ($0.t, $0.id) < ($1.t, $1.id) }?.id
    }

    /// Строка альбома. nil — не знаем, как сказать (незнакомый вид из будущей версии).
    static func text(_ m: Memory, firstTrick: String? = nil) -> String? {
        let key = m.key ?? ""
        switch m.kind {
        case "met": return "Познакомились"
        case "walk": return "Первая прогулка — принёс \(Finds.acc(key))"
        case "find": return "Впервые нашёл \(Finds.acc(key))"
        case "trick":
            let title = Trick(rawValue: key)?.title ?? key
            return m.id == firstTrick ? "Первый трюк — «\(title)»" : "Выучил «\(title)»"
        case "catch": return "Рекорд в «Лови мячик» — \(m.value ?? 0)"
        case "item": return "Первая вещь из автомата — \(itemName(key))"
        case "home":
            guard let line = HomeLine(rawValue: key), let l = HomeShop.line(line) else { return nil }
            let lv = m.value ?? 0
            let name = lv < l.levels.count ? l.levels[lv].name : ""
            return name.isEmpty ? l.name : "\(l.name): \(name)"
        case "days":
            let d = m.value ?? 0
            return d % 365 == 0 ? "День рождения — \(years(d / 365))" : "\(d) \(dayWord(d)) вместе"
        case "taste":
            guard let fact = Tastes.album(fact: key, t: m.t) else { return nil }
            return fact.text
        default: return nil
        }
    }

    static func emoji(_ m: Memory) -> String {
        let key = m.key ?? ""
        switch m.kind {
        case "met": return "🐶"
        case "walk", "find": return Finds.find(key)?.emoji ?? "✨"
        case "trick": return "🎓"
        case "catch": return "🏆"
        case "item": return "🎁"
        case "home": return "🏠"
        case "days": return (m.value ?? 0) % 365 == 0 ? "🎂" : "💛"
        case "taste": return Tastes.album(fact: key, t: m.t)?.emoji ?? "✨"
        default: return "✨"
        }
    }

    /// Имя вещи капсулы с заглавной («Шапочка-листик»).
    static func itemName(_ id: String) -> String {
        EconomyConfig.shared.capsule.itemsById[id]?.name ?? Catalog.name(id)
    }

    /// «1 год», «2 года», «5 лет».
    static func years(_ n: Int) -> String {
        "\(n) \(plural(n, "год", "года", "лет"))"
    }

    static func dayWord(_ n: Int) -> String { plural(n, "день", "дня", "дней") }

    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        EconText.plural(n, one, few, many)
    }

    // MARK: реплики

    /// Что из памяти можно вспомнить вслух на момент t: не моложе суток, по времени (старые первыми).
    static func recallable(_ f: SaveFile, at t: Double) -> [Memory] {
        f.memories.items.filter { t - $0.t >= recallAge && line($0) != nil }
            .sorted { ($0.t, $0.id) < ($1.t, $1.id) }
    }

    /// Ключ реплики (widget/island) и подстановки для воспоминания. nil — вспомнить нечего.
    static func line(_ m: Memory) -> (key: String, vars: [String: String])? {
        let key = m.key ?? ""
        switch m.kind {
        case "met": return ("memory_met", [:])
        case "walk": return ("memory_walk", ["item": Finds.acc(key)])
        case "find": return ("memory_find", ["item": Finds.acc(key)])
        case "trick":
            guard let tr = Trick(rawValue: key) else { return nil }
            return ("memory_trick", ["item": tr.title])
        case "catch": return ("memory_record", ["count": "\(m.value ?? 0)"])
        case "item":
            let n = itemName(key)
            return ("memory_item", ["item": n.prefix(1).lowercased() + n.dropFirst()])
        case "home": return ("memory_home", [:])
        case "days":
            let d = m.value ?? 0
            return d % 365 == 0 ? ("memory_birthday", ["count": years(d / 365)]) : ("memory_days", ["count": "\(d)"])
        case "taste":
            guard let fact = Tastes.album(fact: key, t: m.t) else { return nil }
            let item = fact.category == .find ? Finds.acc(fact.item) : Tastes.acc(fact.item)
            return ("memory_taste", ["item": item])
        default: return nil
        }
    }
}

extension Tastes {
    /// Запись альбома вкусов по ключу «food.carrot» (реакция love) — для памяти.
    static func album(fact key: String, t: Double) -> TasteFact? {
        let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, let c = TasteCategory(rawValue: parts[0]) else { return nil }
        return TasteFact(category: c, item: parts[1], taste: .love, openedT: t,
                         text: text(c, parts[1], .love), emoji: emoji(c, parts[1]))
    }
}
