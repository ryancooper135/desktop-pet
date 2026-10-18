// «Расчесать» (волна 9): ведёшь пальцем по спине Шибы от головы к хвосту — мазок засчитан, колтуны уходят.
// Против шерсти — пёс морщится, мазок не в счёт. Набрал needed мазков — отряхивается, шерсть на стадию лучше.
// Чистая логика без UI: разбор жеста (BrushTracker), прогресс сеанса (BrushSession), доступность, кулдаун,
// итог для шерсти и настроения (Brush.finish).
// С волны 10 итог — ядерное действие brush через PetRunner.apply (как «Погладить»): ядро даёт половину ласки
// «Погладить» и держит откат 6 ч (care.actions.brush, care.cooldowns_min.brush), в журнале «act.brush» —
// его читает Coat.trace (Brush.lift), «Пока тебя не было» и открытки. Монет за расчёсывание нет (economy.care.coins).
// Старые сейвы: откат жил только в BrushLog (f.brush.t) — Brush.adopt переносит его в ядро, BrushLog пишется как раньше.
// Решения (Вадим может поменять): 8 мазков, не чаще раза в 6 ч, +1 стадия шерсти и полдоли любви от «Погладить», без монет.
// Только Foundation и PetCore: гоняется на Linux (app/Package.swift).

import Foundation
@preconcurrency import PetCore

// MARK: жест

enum BrushEvent: Equatable, Sendable {
    /// Мазок по шерсти (от головы к хвосту) засчитан.
    case stroke
    /// Против шерсти — пёс морщится.
    case against
}

/// Разбор одного касания по спине. Координаты экрана (pt), ось — единичный вектор «голова → хвост» на экране.
/// Мазки считаются отрезками («прогонами»): сдвиг вдоль оси ≥ strokeLen — мазок, назад ≥ againstLen — против шерсти.
/// В одном жесте можно провести несколько мазков туда-обратно: разворот начинает новый прогон.
struct BrushTracker: Sendable {
    static let strokeLen: Double = 110
    static let againstLen: Double = 70
    /// Разворот: откат от дальней точки прогона больше этого — прогон начинается с дальней точки.
    static let reverseSlack: Double = 40
    /// Увело поперёк оси больше max(driftMin, |вдоль| × driftRatio) — прогон заново с этой точки.
    static let driftMin: Double = 60
    static let driftRatio: Double = 1.2
    /// «Против шерсти» не чаще, чем раз в againstGap с — одно морщенье на одно движение.
    static let againstGap: Double = 0.8

    private(set) var axisX: Double
    private(set) var axisY: Double
    private(set) var active = false
    private(set) var runX: Double = 0
    private(set) var runY: Double = 0
    /// Дальняя точка прогона вдоль оси (для разворота).
    private(set) var best: Double = 0
    private(set) var bestX: Double = 0
    private(set) var bestY: Double = 0
    private(set) var lastAgainst = -Double.infinity

    /// Ось «голова → хвост» на экране. Нулевая — вправо.
    init(axisX: Double = 1, axisY: Double = 0) {
        let len = (axisX * axisX + axisY * axisY).squareRoot()
        if len > 0.0001 {
            self.axisX = axisX / len
            self.axisY = axisY / len
        } else {
            self.axisX = 1
            self.axisY = 0
        }
    }

    mutating func begin(x: Double, y: Double, time: Double) {
        active = true
        restart(x, y)
    }

    mutating func move(x: Double, y: Double, time: Double) -> [BrushEvent] {
        guard active else {
            begin(x: x, y: y, time: time)
            return []
        }
        let dx = x - runX, dy = y - runY
        let along = dx * axisX + dy * axisY
        let across = abs(dx * axisY - dy * axisX)
        if across > max(Self.driftMin, abs(along) * Self.driftRatio) {
            restart(x, y)
            return []
        }
        if along >= Self.strokeLen {
            restart(x, y)
            return [.stroke]
        }
        if along > best {
            best = along
            bestX = x
            bestY = y
        } else if best > 0, along < best - Self.reverseSlack {
            // Развернулись: новый прогон от дальней точки, назад теперь считается от неё.
            runX = bestX
            runY = bestY
            best = 0
            return move(x: x, y: y, time: time)
        }
        if along <= -Self.againstLen {
            restart(x, y)
            guard time - lastAgainst >= Self.againstGap || time < lastAgainst else { return [] }
            lastAgainst = time
            return [.against]
        }
        return []
    }

    mutating func end(x: Double, y: Double, time: Double) -> [BrushEvent] {
        guard active else { return [] }
        let out = move(x: x, y: y, time: time)
        active = false
        return out
    }

    private mutating func restart(_ x: Double, _ y: Double) {
        runX = x
        runY = y
        best = 0
        bestX = x
        bestY = y
    }
}

// MARK: сеанс

/// Прогресс одного расчёсывания (в памяти, в файл не пишется: бросил на полпути — начнёшь заново).
struct BrushSession: Equatable, Sendable {
    var counted = 0
    var against = 0
    let needed: Int

    init(needed: Int = Brush.needed, counted: Int = 0) {
        self.needed = max(1, needed)
        self.counted = min(self.needed, max(0, counted))
    }

    var progress: Double { Double(counted) / Double(needed) }
    var percent: Int { Int((progress * 100).rounded()) }
    var done: Bool { counted >= needed }
    /// Колтунов на спине осталось из total (ровно 0 только к концу).
    func tufts(of total: Int) -> Int {
        guard total > 0, !done else { return 0 }
        return max(1, Int((Double(total) * (1 - progress)).rounded(.up)))
    }

    /// Засчитать мазок. true — только что дошли до конца.
    @discardableResult
    mutating func add() -> Bool {
        guard !done else { return false }
        counted += 1
        return done
    }

    var text: String { "Расчёсано \(percent)%" }
}

// MARK: итог

/// Что дало расчёсывание.
struct BrushOutcome: Hashable, Sendable {
    let ok: Bool
    /// Почему нельзя (dead, away, asleep, brushed…). nil — расчесали.
    let reason: String?
    let before: CoatStage
    let after: CoatStage
    /// Прибавка любви.
    let love: Double
}

/// Последнее расчёсывание в state.json. Пустое в файл не пишется.
struct BrushLog: Codable, Hashable, Sendable {
    var t: Double?
    var n = 0

    init() {}

    var isEmpty: Bool { t == nil && n == 0 }

    enum CodingKeys: String, CodingKey { case t, n }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try? c.decodeIfPresent(Double.self, forKey: .t)
        n = (try? c.decodeIfPresent(Int.self, forKey: .n)) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(t, forKey: .t)
        if n != 0 { try c.encode(n, forKey: .n) }
    }
}

enum Brush {
    /// Мазков на одно расчёсывание.
    static let needed = 8
    /// Не чаще раза в cooldownH часов — откат ядра (care.cooldowns_min.brush).
    static var cooldownH: Double { (Catalog.rules.brush?.cooldownMin ?? 0) / 60 }
    /// Отказ ядра cooldown у расчёсывания — свой текст «Шерсть уже расчёсана».
    static let cooldownReason = "brushed"
    /// Любовь — эта доля от прибавки «Погладить» (care.actions.brush.love_share, считает ядро).
    static var loveShare: Double { Catalog.rules.brush?.loveShare ?? 0 }
    /// Шерсть: небольшой толчок ухоженности (доля от остатка до 1) и подъём на стадию выше —
    /// за границу + гистерезис + margin, чтобы новая стадия не слетела на следующем шаге сетки.
    static let nudge: Double = 0.05
    static let margin: Double = 0.02
    /// Вид реакции пса и старые записи журнала (до ядерного действия). Новые записи — actKind.
    static let journalKind = "brush"
    /// Запись журнала ядерного действия (PetRunner.apply).
    static let actKind = "act.brush"

    /// Колтунов на спине до начала по стадии шерсти.
    static func tufts(_ stage: CoatStage) -> Int {
        switch stage {
        case .matted: 6
        case .shaggy: 4
        case .normal: 2
        case .sleek: 1
        }
    }

    // MARK: доступность

    /// Почему расчесать нельзя. nil — можно. Спрашиваем ядро на копии (как CatchGame.gate для play):
    /// порядок ядра — нет пса → гуляет → моется → спит → беда → откат, как раньше у Tricks.gate + кулдаун.
    static func gate(_ f: SaveFile, at t: Double) -> String? {
        var s = PetRunner.peek(f, at: t)
        adopt(&s, f.brush, at: t)
        let res = PetEngine.act(&s, Catalog.rules, PetRunner.owner(f, at: t), .brush)
        if res.ok { return nil }
        return res.reason == "cooldown" ? cooldownReason : (res.reason ?? "unavailable")
    }

    /// Секунд до следующего раза (0 — можно) по откату ядра. Часы перевели назад — не больше одного отката.
    static func remaining(_ f: SaveFile, at t: Double) -> Double {
        var s = f.pet
        adopt(&s, f.brush, at: t)
        guard let end = s.cooldowns[PetEngine.BRUSH_COOLDOWN] else { return 0 }
        return min(cooldownH * 3600, max(0, end - t))
    }

    /// Старый сейв: расчёсывали до волны 10, откат был только в BrushLog. Если у ядра своего отката нет —
    /// берём last + cooldownH. Метка из будущего (часы перевели назад) не держит — как было в BrushLog.
    static func adopt(_ s: inout PetState, _ log: BrushLog, at t: Double) {
        guard s.cooldowns[PetEngine.BRUSH_COOLDOWN] == nil, let last = log.t, last <= t else { return }
        s.cooldowns[PetEngine.BRUSH_COOLDOWN] = last + cooldownH * 3600
    }

    static func reasonText(_ reason: String?, remaining: Double = 0) -> String {
        if reason == cooldownReason {
            let h = Int((remaining / 3600).rounded(.up))
            return h <= 1 ? "Шерсть уже расчёсана · через час" : "Шерсть уже расчёсана · через \(h) ч"
        }
        return Tricks.reasonText(reason)
    }

    // MARK: итог

    /// Дочесали: ядерное действие brush (журнал act.brush — его читает Coat, ласка и откат — ядро), BrushLog.
    static func finish(_ f: inout SaveFile, now: Double) -> BrushOutcome {
        PetRunner.catchUp(&f, now: now)
        let before = Coat.look(f, now: now).stage
        // Отказ — заранее, без записи в журнал: экран и так не даёт дочесать, когда нельзя.
        if let r = gate(f, at: now) {
            return BrushOutcome(ok: false, reason: r, before: before, after: before, love: 0)
        }
        adopt(&f.pet, f.brush, at: now)
        let love0 = f.pet.needs[.love] ?? 0
        let out = PetRunner.apply(.brush, source: .app, to: &f, now: now)
        guard out.ok else {
            let r = out.reason == "cooldown" ? cooldownReason : out.reason
            return BrushOutcome(ok: false, reason: r, before: before, after: before, love: 0)
        }
        f.brush.t = now
        f.brush.n += 1
        let love = (f.pet.needs[.love] ?? love0) - love0
        let after = Coat.look(f, now: now).stage
        return BrushOutcome(ok: true, reason: nil, before: before, after: after, love: love)
    }

    /// Ухоженность после расчёсывания: толчок и подъём на стадию выше (у гладкой — только толчок).
    /// raw — без бонуса шкалы look, стадия — та, что была до мазков.
    static func lift(raw: Double, bonus: Double, stage: CoatStage) -> Double {
        var r = raw + nudge * (1 - raw)
        if stage.rank < Coat.edges.count {
            r = max(r, Coat.edges[stage.rank] + Coat.hysteresis + margin - bonus)
        }
        return Coat.clamp(r)
    }
}
