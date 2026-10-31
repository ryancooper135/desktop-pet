// Привычки хозяина (волна 11) убраны в волне 57: вместо листа «Привычки» и пяти ярлыков «Я дома», «Я проснулся»,
// «Ложусь спать», «Выпил воды», «Сделал зарядку» — «Команды» псу (Tricks.swift) и ярлыки «Шиба, сидеть» / «дай лапу».
// Монеты за привычки больше не начисляются; общий дневной потолок econ.daily.habits остался шагам и показу команд.
// Поле сейва habits осталось как было: старые отметки читаются, пустое не пишется, новому щенку переходит
// (PetStore.startOver) — чтобы ни старый сейв, ни откат на прошлую версию ничего не теряли.
// Только Foundation: гоняется на Linux (app/Package.swift).

import Foundation

/// Что хозяин отмечал до волны 57. day — номер местных суток (DayKey), today — сколько раз в тот день по каждой,
/// last — когда последний раз, total — сколько раз всего. Ключи — бывшие Habit.rawValue: незнакомые не ломают чтение.
struct HabitLog: Codable, Hashable, Sendable {
    var day = 0
    var today: [String: Int] = [:]
    var last: [String: Double] = [:]
    var total: [String: Int] = [:]

    init() {}

    var isEmpty: Bool { day == 0 && today.isEmpty && last.isEmpty && total.isEmpty }

    enum CodingKeys: String, CodingKey { case day, today, last, total }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? c.decodeIfPresent(Int.self, forKey: .day)) ?? 0
        today = (try? c.decodeIfPresent([String: Int].self, forKey: .today)) ?? [:]
        last = (try? c.decodeIfPresent([String: Double].self, forKey: .last)) ?? [:]
        total = (try? c.decodeIfPresent([String: Int].self, forKey: .total)) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if day != 0 { try c.encode(day, forKey: .day) }
        if !today.isEmpty { try c.encode(today, forKey: .today) }
        if !last.isEmpty { try c.encode(last, forKey: .last) }
        if !total.isEmpty { try c.encode(total, forKey: .total) }
    }
}
