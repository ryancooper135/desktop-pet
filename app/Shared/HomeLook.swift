// Волна 53 «B · Стекло»: логика нового главного экрана без вью — что подписать под кнопкой действия, какую награду
// вынести из тоста в золотую плашку, что показать в карточке «Задание дня». Тестируется в WSL (HomeLookTests).

import Foundation
@preconcurrency import PetCore

enum HomeLook {
    /// Какую шкалу поднимает кнопка панели (kind — PetAction.kind). nil — у кнопки нет шкалы («Разбудить», «Отбой»).
    static func actNeed(_ kind: String) -> Need? {
        switch kind {
        case "feed": return .food
        case "pet": return .love
        case "play": return .fun
        case "bath": return .clean
        default: return nil
        }
    }

    /// Подпись-награда под словом кнопки: «+сытость», «+любовь». Пусто — подписи нет.
    static func actReward(_ kind: String) -> String? {
        actNeed(kind).map { "+" + Catalog.needName($0).lowercased() }
    }

    /// Тост «Задание дня: Покормить · +20 🪙» → текст и награда «+20 🪙» отдельно (золотая плашка у островка).
    /// Награда — хвост после « · » или последнего пробела: начинается с «+», кончается 🪙/✂️/🎟, не длиннее 12
    /// символов. Несколько наград через « · » — берём все подряд с конца. Иначе текст как есть, награды нет.
    static func toastSplit(_ text: String) -> (text: String, reward: String?) {
        var rest = text
        var tail: [String] = []
        while let r = rest.range(of: " · ", options: .backwards), isReward(String(rest[r.upperBound...])) {
            tail.insert(String(rest[r.upperBound...]), at: 0)
            rest = String(rest[..<r.lowerBound])
        }
        if tail.isEmpty, let r = rest.range(of: " +", options: .backwards) {
            let t = String(rest[rest.index(after: r.lowerBound)...])
            if isReward(t) {
                tail = [t]
                rest = String(rest[..<r.lowerBound])
            }
        }
        guard !tail.isEmpty, !rest.isEmpty else { return (text, nil) }
        return (rest, tail.joined(separator: " "))
    }

    private static func isReward(_ s: String) -> Bool {
        guard s.hasPrefix("+"), s.count <= 12 else { return false }
        guard ["🪙", "✂️", "🎟"].contains(where: { s.hasSuffix($0) }) else { return false }
        return s.dropFirst().first?.isNumber == true
    }

    /// Карточка «Задание дня» над комнатой: первое невыполненное задание (или последнее, если все готовы).
    struct Quest: Equatable, Sendable {
        var done: Int
        var total: Int
        /// 0…1 для кольца.
        var fraction: Double
        var emoji: String
        /// «Погладить 3 раза» или «Все выполнены».
        var title: String
        /// «Задание дня · 1/3».
        var caption: String
        /// «+45 🪙» — награда за текущее задание; все готовы — награда за все (если ещё не выдана) или nil.
        var reward: String?
        /// Для VoiceOver: «Задания дня: выполнено 1 из 3. Сейчас: Погладить 3 раза, 0 / 3, награда +45 🪙».
        var a11y: String
        var allDone: Bool
    }

    static func quest(_ b: TaskBoard) -> Quest? {
        guard !b.items.isEmpty else { return nil }
        let done = b.doneCount
        let total = b.items.count
        let caption = "Задание дня · \(done)/\(total)"
        let head = "\(DailyTaskText.title): выполнено \(done) из \(total)"
        if let t = b.items.first(where: { !$0.done }) {
            let reward = DailyTaskText.reward(t)
            return Quest(done: done, total: total, fraction: Double(done) / Double(total),
                         emoji: DailyTaskText.emoji(t.id), title: DailyTaskText.name(t), caption: caption,
                         reward: reward,
                         a11y: "\(head). Сейчас: \(DailyTaskText.name(t)), \(DailyTaskText.progress(t)), награда \(reward)",
                         allDone: false)
        }
        return Quest(done: done, total: total, fraction: 1, emoji: "🏆", title: "Все выполнены", caption: caption,
                     reward: nil, a11y: "\(head). Все выполнены", allDone: true)
    }

    /// Компактное число для чипа: 999 → «999», 1 250 → «1,2к», 12 400 → «12к».
    static func short(_ n: Int) -> String {
        let a = abs(n)
        let sign = n < 0 ? "−" : ""
        if a < 1000 { return "\(sign)\(a)" }
        if a < 10_000 {
            let d = a / 100
            let whole = d / 10, frac = d % 10
            return frac == 0 ? "\(sign)\(whole)к" : "\(sign)\(whole),\(frac)к"
        }
        if a < 1_000_000 { return "\(sign)\(a / 1000)к" }
        return "\(sign)\(a / 1_000_000)м"
    }
}
