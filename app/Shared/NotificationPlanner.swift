// План локальных уведомлений: ядро (notificationPlan) решает когда и о чём, здесь — тексты из lines.json
// и напоминание о конце подписи. Ставит план приложение (App/NotificationScheduler).

import Foundation
@preconcurrency import PetCore

struct PlannedNote: Hashable, Sendable {
    let id: String
    let date: Date
    let title: String
    let body: String
    let category: String   // pet.need | pet.miss | pet.build
    let priority: Int      // 1..6, больше — важнее
    let trigger: String
}

enum NotificationPlanner {
    static let prefix = "pet."
    static let maxNotes = 50
    /// Горизонт 14 дней: иначе «скучаю» на 3/6/9/12-й день не попадёт в план.
    static let horizonH: Double = 336

    static func plan(_ f: SaveFile, now: Double) -> [PlannedNote] {
        let r = Catalog.rules
        let o = PetRunner.owner(f, at: now)
        // Уже сработавшее из плана свежее старого lastSentT: берём самое позднее, иначе два в один день.
        let fired = f.notif.scheduled.filter { $0 <= now }.max()
        let lastSent = [f.notif.lastSentT, fired].compactMap { $0 }.max()
        let opts = NotifyOpts(horizonH: horizonH, lastOpenT: f.lastSeenT ?? now, lastSentT: lastSent)
        var out: [PlannedNote] = []
        for p in PetEngine.notificationPlan(f.pet, r, o, now: now, opts: opts) where p.at > now {
            let day = Int((p.at + Double(o.tzOffsetMin) * 60) / 86400)
            var vars: [String: String] = ["item": Catalog.name(Catalog.mainFood)]
            if p.trigger == .miss_you { vars["count"] = "\(max(1, Int(((p.at - (f.lastSeenT ?? now)) / 86400).rounded())))" }
            let text = Lines.shared.notification(p.trigger.rawValue, seed: f.petId, slot: day, vars: vars)
            out.append(PlannedNote(
                id: "\(prefix)\(p.trigger.rawValue).\(Int(p.at))", date: Date(timeIntervalSince1970: p.at),
                title: String(text.title.prefix(LineLimit.notifTitle)), body: text.body,
                category: p.trigger == .miss_you ? "pet.miss" : "pet.need",
                priority: priority(p.trigger), trigger: p.trigger.rawValue))
        }
        out.append(contentsOf: buildNotes(f, now: now))
        out.sort { $0.date < $1.date }
        return Array(out.prefix(maxNotes))
    }

    static func priority(_ t: NotifyTrigger) -> Int {
        switch t {
        case .last_chance, .critical: return 5
        case .heart_lost: return 4
        case .smelly, .unwell: return 3
        case .miss_you: return 1
        default: return 2
        }
    }

    /// За 48 и 24 часа до конца подписи. Текстов build_expiring в lines.json пока нет — встроенные.
    static func buildNotes(_ f: SaveFile, now: Double) -> [PlannedNote] {
        guard let exp = f.build?.expiresT else { return [] }
        let items: [(h: Double, title: String, body: String)] = [
            (48, "Подпись кончается", "Через 2 дня приложение перестанет открываться. Переустанови его, \(f.name) подождёт."),
            (24, "Остался день", "Завтра подпись кончится. Переустанови приложение, чтобы не потерять \(f.name)."),
        ]
        return items.compactMap { (it: (h: Double, title: String, body: String)) -> PlannedNote? in
            let at = exp - it.h * 3600
            guard at > now else { return nil }
            return PlannedNote(id: "\(prefix)build.\(Int(it.h))", date: Date(timeIntervalSince1970: at),
                               title: it.title, body: it.body, category: "pet.build", priority: 6, trigger: "build_expiring")
        }
    }
}
