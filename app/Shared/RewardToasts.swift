// Волна 43 L: очередь тостов наград. Раньше каждый тост заменял прошлый, и из одной записи, где разом выпали
// задание дня, достижение, день заботы (и сундук недели), уровень с «Открылось: …», был виден только последний.
// Теперь награды встают в очередь и показываются по одной (каждая — ToastQueue.hold секунд), у каждой ключ:
// повторный settle или refresh ту же награду второй раз не покажет. Обычные тосты (отказ, монеты действия,
// подсказки) — как раньше, сразу поверх; награду, которую они перебили, очередь покажет снова следом.
// Чистая логика — здесь (тесты в WSL), таймер и показ — AppModel.show / AppModel.reward.

import Foundation
@preconcurrency import PetCore

/// Один тост: текст, «ок/отказ», значок. key — у награды (одна награда — один тост), у обычного — nil.
struct ToastNote: Hashable, Sendable {
    var text: String
    var ok = true
    var emoji: String? = nil
    var key: String? = nil
}

struct ToastQueue: Sendable {
    /// Сколько висит тост, с.
    static let hold: Double = 2.5
    /// Больше наград в очереди не держим: такая лавина — сбой, а не игра (обычно их 1–3).
    static let maxPending = 6
    /// Сколько ключей показанных наград помнить (награда свежая 10 с, ключей за это время — единицы).
    static let keepKeys = 64

    /// На экране сейчас.
    private(set) var current: ToastNote?
    /// Ждут своей очереди — только награды.
    private(set) var pending: [ToastNote] = []
    /// Ключи наград, уже принятых в очередь (показанных или ждущих), — от старых к новым.
    private(set) var seen: [String] = []

    init() {}

    /// Награда: нет тоста — сразу на экран, иначе в конец очереди. Уже принятая (тот же key) — ничего.
    /// true — сменился тост на экране (запустить таймер).
    @discardableResult
    mutating func reward(_ n: ToastNote) -> Bool {
        if let k = n.key {
            guard !seen.contains(k) else { return false }
            seen.append(k)
            if seen.count > Self.keepKeys { seen.removeFirst(seen.count - Self.keepKeys) }
        }
        if current == nil {
            current = n
            return true
        }
        if current?.text == n.text || pending.contains(where: { $0.text == n.text }) { return false }
        guard pending.count < Self.maxPending else { return false }
        pending.append(n)
        return false
    }

    /// Обычный тост: сразу на экран. Если перебил награду — та встаёт первой в очередь и покажется следом.
    mutating func plain(_ n: ToastNote) {
        if let c = current, c.key != nil, c != n {
            pending.insert(c, at: 0)
            if pending.count > Self.maxPending { pending.removeLast(pending.count - Self.maxPending) }
        }
        current = n
    }

    /// Время тоста на экране вышло: следующий из очереди или пусто. Возвращает новый current.
    @discardableResult
    mutating func next() -> ToastNote? {
        current = pending.isEmpty ? nil : pending.removeFirst()
        return current
    }

    /// Всё убрать (экран сменился, «начать заново»). Ключи показанных помним: награды не вернутся.
    mutating func clear() {
        current = nil
        pending = []
    }
}

/// Свежие награды из сейва для тостов: задание дня, достижения (одной строкой на запись), клочки ✂️.
/// Свежие — не старше `fresh` секунд. Порядок — порядок показа.
enum RewardToasts {
    static let fresh: Double = 10

    /// tasks / achievements — включены ли эти тосты (в UI-тестах без своего сида они молчат).
    static func collect(_ f: SaveFile, now: Double, tasks: Bool = true, achievements: Bool = true) -> [ToastNote] {
        var out: [ToastNote] = []
        func isFresh(_ t: Double) -> Bool { now - t < fresh && t <= now + 1 }

        // 1. Задание дня (с монетами задания, за последнее — и ✂️ «все задания»).
        if tasks, DailyTasks.enabled, let w = f.tasks.last, isFresh(w.t) {
            out.append(ToastNote(text: DailyTaskText.toast(w, f), emoji: w.shards > 0 ? "✂️" : DailyTaskText.emoji(w.task),
                                 key: "task:\(w.task)@\(w.t)"))
        }

        // 2. Достижения: все, полученные в одну запись (одно t), — одной строкой с суммой ✂️.
        if achievements {
            var byT: [Double: [String]] = [:]
            for (id, t) in f.shardLog.achT where isFresh(t) { byT[t, default: []].append(id) }
            for t in byT.keys.sorted() {
                let got = Set(byT[t] ?? [])
                let ids = Achievements.all.map(\.id).filter { got.contains($0) }
                if let text = Achievements.toast(ids) {
                    out.append(ToastNote(text: text, emoji: "🏆", key: "ach@\(t)"))
                }
            }
        }

        // 3. Клочки ✂️ не за достижения: день заботы, сундук недели, рекорд, находки, места.
        for g in Shards.freshGains(f, now: now, within: fresh) where !g.reason.hasPrefix("ach.") {
            out.append(ToastNote(text: Shards.toastText(g), emoji: "✂️", key: "shard:\(g.reason)@\(g.t)"))
        }
        return out
    }
}
