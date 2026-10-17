// Что показать и когда позвать — построчный порт core/ts/src/insights.ts.
// Желания для пузыря, одно настроение для реплик, «Пока тебя не было», «Спасти», план уведомлений.
// Баланс не меняет. Меняешь что-то здесь — поменяй и в TS, перегенерируй векторы.

import Foundation

// Ключи совпадают с content/ru/lines.json: желания — thoughts, настроения — widget/island, триггеры — notifications.
public enum WantKey: String, CaseIterable, Sendable { case food, bath, sleep, play, pet, walk }
public enum Mood: String, CaseIterable, Sendable {
    case dead, critical, bath, sleep, nap, hungry, smelly, dirty, tired, bored, wants_love, wants_walk, sulky, ok
}
public enum Daypart: String, CaseIterable, Sendable { case morning, day, evening, night }
public enum NotifyTrigger: String, CaseIterable, Sendable {
    case hungry, dirty, smelly, bored, wants_love, unwell, heart_lost, critical, last_chance, miss_you
}

public struct Want: Equatable, Sendable {
    public let key: WantKey
    public let strength: Double   // 0..1
    public let urgent: Bool       // по этой шкале идёт беда
}

public struct Rescue: Equatable, Sendable {
    public let key: String        // food | bath | play | pet | heal
    public let action: Action
    public let because: String    // беда (starve/dirty/toska), шкала или hearts
}

public struct TimedAct: Equatable, Sendable {
    public let t: Double
    public let action: Action
    public init(t: Double, action: Action) { self.t = t; self.action = action }
}

public struct AwayEvent: Equatable, Sendable {
    /// low, distress, heart, last_chance, death, sleep, wake, nap, heart_up, act
    public let kind: String
    public let t: Double
    public let key: String?
    public let value: Int?
    public let ok: Bool?
}

public struct AwaySummary: Equatable, Sendable {
    public let from: Double
    public let to: Double
    public let awayH: Double
    public let show: Bool             // показывать экран (≥ 2 ч)
    public let greet: String?         // welcome | welcome_long (≥ 24 ч); nil — не показывать или умер
    public let cta: String?           // away.cta_*: подсказка по главному желанию на now
    public let sleptH: Double         // сколько питомец спал (ночь + дрёма)
    public let heartsFrom: Double
    public let heartsTo: Double
    public let needs: Vals            // изменение шкал: было → стало
    public let events: [AwayEvent]    // по времени, без level
    public let died: Bool
    public let state: PetState        // состояние на now
}

public struct NotifyOpts: Sendable {
    public var horizonH: Double
    public var lastOpenT: Double?     // когда открывали приложение (по умолчанию now)
    public var lastSentT: Double?     // когда ушло последнее уведомление
    public var quietFromMin: Int?     // тихие часы (по умолчанию сон хозяина)
    public var quietToMin: Int?
    public init(horizonH: Double = 72, lastOpenT: Double? = nil, lastSentT: Double? = nil,
                quietFromMin: Int? = nil, quietToMin: Int? = nil) {
        self.horizonH = horizonH; self.lastOpenT = lastOpenT; self.lastSentT = lastSentT
        self.quietFromMin = quietFromMin; self.quietToMin = quietToMin
    }
}

public struct PlannedNotification: Equatable, Sendable {
    public let at: Double
    public let trigger: NotifyTrigger
    public let kind: String           // low | distress | heart | level | last_chance | absent
    public let key: String?
}

extension PetEngine {
    // Пороги показа (не баланс): from — с какого значения шкалы питомец хочет,
    // mood — ниже какого значения желание становится настроением, w — вес при сортировке.
    struct WantSpec {
        let key: WantKey
        let need: Need
        let from: Double
        let mood: Double
        let w: Double
        let moodKey: Mood?
    }
    static let wantSpecs: [WantSpec] = [
        WantSpec(key: .food, need: .food, from: 50, mood: 25, w: 1, moodKey: .hungry),
        WantSpec(key: .bath, need: .clean, from: 50, mood: 25, w: 0.8, moodKey: .dirty), // ниже smellyBelow — smelly
        WantSpec(key: .sleep, need: .energy, from: 30, mood: 20, w: 0.6, moodKey: .tired),
        WantSpec(key: .play, need: .fun, from: 50, mood: 30, w: 0.7, moodKey: .bored),
        WantSpec(key: .pet, need: .love, from: 50, mood: 35, w: 0.7, moodKey: .wants_love),
        WantSpec(key: .walk, need: .walk, from: 30, mood: 15, w: 0.4, moodKey: .wants_walk),
    ]
    static let smellyBelow: Double = 10   // как в moods(): чистота ниже — smelly
    static let partMin = 180
    static let awayShowH: Double = 2
    static let awayLongH: Double = 24
    static let nCareDays: Double = 3
    static let nMissEveryDays: Double = 3
    static let nStopDays: Double = 14
    static let nLeadMin: Double = 60

    static func wantDistress(_ d: Distress) -> [WantKey] {
        switch d {
        case .starve: return [.food]
        case .dirty: return [.bath]
        case .toska: return [.play, .pet]
        }
    }

    static func needTrigger(_ n: Need) -> NotifyTrigger? {
        switch n {
        case .food: return .hungry
        case .clean: return .dirty
        case .fun: return .bored
        case .love: return .wants_love
        default: return nil
        }
    }

    static func distressTrigger(_ d: Distress) -> NotifyTrigger {
        switch d {
        case .starve: return .hungry
        case .dirty: return .smelly
        case .toska: return .unwell
        }
    }

    static func spec(_ k: WantKey) -> WantSpec { wantSpecs.first { $0.key == k }! }

    static func at(_ s: PetState, _ r: Rules, _ o: Owner, _ now: Double?) -> PetState {
        if let now = now, now > s.t { return advance(s, r, o, now) }
        return s
    }

    static func sleepingNow(_ s: PetState, _ r: Rules, _ o: Owner) -> Bool {
        petNight(s.t, r, o) || s.napUntil != nil
    }

    // MARK: желания

    /// Желания для пузыря мысли: срочные (идёт беда) первыми, дальше по силе 0..1. Пусто — ничего не хочет.
    public static func wants(_ s0: PetState, _ r: Rules, _ o: Owner, now: Double? = nil) -> [Want] {
        let s = at(s0, r, o, now)
        if !s.alive { return [] }
        let bathing = s.bathUntil != nil, sleeping = sleepingNow(s, r, o)
        let tired = mods(s, r)["refuses_games"] == .flag(true)
        var urgent: [WantKey] = []
        for d in Distress.allCases where r.distress[d]!.cond(s.needs) { urgent.append(contentsOf: wantDistress(d)) }
        var out: [(w: Want, i: Int)] = []
        for (i, w) in wantSpecs.enumerated() {
            if bathing && (w.key == .food || w.key == .bath || w.key == .play) { continue }
            if sleeping && (w.key == .sleep || w.key == .play) { continue }
            if tired && w.key == .play { continue }
            let v = s.needs[w.need]!
            if v >= w.from { continue }
            let strength = min(1, w.w * (w.from - v) / w.from)
            out.append((Want(key: w.key, strength: strength, urgent: urgent.contains(w.key)), i))
        }
        out.sort { a, b in
            if a.w.urgent != b.w.urgent { return a.w.urgent }
            if a.w.strength != b.w.strength { return a.w.strength > b.w.strength }
            return a.i < b.i
        }
        return out.map { $0.w }
    }

    // MARK: настроение

    /// Одно настроение для реплик виджета и острова.
    public static func mood(_ s0: PetState, _ r: Rules, _ o: Owner, now: Double? = nil) -> Mood {
        let s = at(s0, r, o, now)
        if !s.alive { return .dead }
        let lv = level(s, r)
        if lv == 3 { return .critical }
        if s.bathUntil != nil { return .bath }
        if petNight(s.t, r, o) { return .sleep }
        if s.napUntil != nil { return .nap }
        for w in wants(s, r, o) {
            let sp = spec(w.key)
            let v = s.needs[sp.need]!
            if sp.key == .bath && v < smellyBelow { return .smelly }
            if let mk = sp.moodKey, v < sp.mood { return mk }
        }
        if lv == 2 { return .sulky }
        return .ok
    }

    /// Время суток для реплик: утро — 3 ч после подъёма питомца, вечер — 3 ч до отбоя, ночь — питомец спит.
    public static func daypart(_ t: Double, _ r: Rules, _ o: Owner) -> Daypart {
        if petNight(t, r, o) { return .night }
        let m = localMin(t, o)
        let up = o.wakeMin + r.afterWakeMin
        if inWindow(m, up, up + partMin) { return .morning }
        if inWindow(m, o.bedMin - partMin, o.bedMin + r.afterBedMin) { return .evening }
        return .day
    }

    // MARK: «Спасти»

    static func actionKey(_ a: Action) -> String {
        switch a {
        case .feed: return "food"
        case .bath: return "bath"
        case .play: return "play"
        case .pet: return "pet"
        default: return "heal"
        }
    }

    static func needActions(_ n: Need, _ food: String) -> [Action] {
        switch n {
        case .food: return [.feed(food)]
        case .clean: return [.bath]
        case .fun: return [.play]
        case .love: return [.pet]
        default: return []
        }
    }

    static func distressActions(_ d: Distress, _ food: String) -> [Action] {
        switch d {
        case .starve: return [.feed(food)]
        case .dirty: return [.bath]
        case .toska: return [.play, .pet]
        }
    }

    /// Одно самое срочное действие, которое ядро примет прямо сейчас (проверяется act на копии).
    /// Порядок: беда по скорости урона → шкалы ниже порога регенерации (или warnLow при полных сердцах) в порядке wants →
    /// в критичном состоянии лечебный предмет. nil — делать нечего или сейчас ничего не поможет.
    public static func rescue(_ s0: PetState, _ r: Rules, _ o: Owner, now: Double? = nil,
                              food: String = "kibble", heal: String = "vitamin") -> Rescue? {
        let s = at(s0, r, o, now)
        if !s.alive { return nil }
        func tryAct(_ a: Action) -> PetState? {
            var c = s
            return act(&c, r, o, a).ok ? c : nil
        }

        var dist: [(d: Distress, i: Int, h: Double)] = []
        for (i, d) in Distress.allCases.enumerated() where r.distress[d]!.cond(s.needs) {
            dist.append((d, i, r.distress[d]!.hoursPerHeart))
        }
        dist.sort { a, b in a.h != b.h ? a.h < b.h : a.i < b.i }
        for x in dist {
            var first: Action? = nil
            for a in distressActions(x.d, food) {
                guard let c = tryAct(a) else { continue }
                if first == nil { first = a }
                if a == .bath || !r.distress[x.d]!.cond(c.needs) {
                    return Rescue(key: actionKey(a), action: a, because: x.d.rawValue)
                }
            }
            if let a = first { return Rescue(key: actionKey(a), action: a, because: x.d.rawValue) }
        }

        let maxH = maxHearts(s, r)
        let bar = s.hearts < maxH ? r.regenAllGe : r.warnLow
        for w in wants(s, r, o) {
            let n = spec(w.key).need
            if !WATCH.contains(n) || s.needs[n]! >= bar { continue }
            for a in needActions(n, food) where tryAct(a) != nil {
                return Rescue(key: actionKey(a), action: a, because: n.rawValue)
            }
        }

        if level(s, r) == 3 && s.hearts < maxH {
            let a = Action.item(heal)
            if tryAct(a) != nil { return Rescue(key: "heal", action: a, because: "hearts") }
        }
        return nil
    }

    // MARK: «Пока тебя не было»

    static func heartsCeil(_ s: PetState) -> Int { Int((s.hearts - 1e-9).rounded(.up)) }

    /// Пересчитать отсутствие от prev до now. journal — действия без приложения (виджет, остров, шаги),
    /// применяются в своё время, как в векторах (act в момент s.t после stepTo).
    public static func awaySummary(_ prev: PetState, _ r: Rules, _ o: Owner, now: Double,
                                   journal: [TimedAct] = []) -> AwaySummary {
        var s = prev
        var ev: [AwayEvent] = []
        var tr = tracker(s, r)
        var wasNight = petNight(s.t, r, o)
        var sleptMin = 0

        func run(_ T: Double) {
            while s.alive && s.t + STEP <= T {
                let t0 = s.t, h0 = heartsCeil(s), nap0 = s.napUntil
                step(&s, r, o)
                let night = petNight(t0, r, o)
                if night != wasNight {
                    ev.append(AwayEvent(kind: night ? "sleep" : "wake", t: t0, key: nil, value: nil, ok: nil))
                    wasNight = night
                }
                if !night, let nap = s.napUntil, nap != nap0 {
                    ev.append(AwayEvent(kind: "nap", t: s.t, key: nil, value: nil, ok: nil))
                }
                if night || s.napUntil != nil { sleptMin += 1 }
                if heartsCeil(s) > h0 { ev.append(AwayEvent(kind: "heart_up", t: s.t, key: nil, value: heartsCeil(s), ok: nil)) }
                var fe: [ForecastEvent] = []
                observe(&tr, s, r, &fe)
                for e in fe where e.kind != .level {
                    ev.append(AwayEvent(kind: e.kind.rawValue, t: e.t, key: e.key, value: e.value, ok: nil))
                }
                if !s.alive { ev.append(AwayEvent(kind: "death", t: s.diedAt ?? s.t, key: s.cause?.rawValue, value: nil, ok: nil)) }
            }
        }

        var acts: [(a: TimedAct, i: Int)] = []
        for (i, a) in journal.enumerated() where a.t >= prev.t && a.t <= now { acts.append((a, i)) }
        acts.sort { x, y in x.a.t != y.a.t ? x.a.t < y.a.t : x.i < y.i }
        for x in acts {
            run(x.a.t)
            if !s.alive { break }
            let h0 = heartsCeil(s)
            let res = act(&s, r, o, x.a.action)
            ev.append(AwayEvent(kind: "act", t: s.t, key: actionType(x.a.action), value: nil, ok: res.ok))
            if heartsCeil(s) > h0 { ev.append(AwayEvent(kind: "heart_up", t: s.t, key: nil, value: heartsCeil(s), ok: nil)) }
            tr = tracker(s, r)
        }
        run(now)

        var needs: Vals = [:]
        for n in Need.allCases { needs[n] = s.needs[n]! - prev.needs[n]! }
        let awayH = (now - prev.t) / 3600
        let show = awayH >= awayShowH
        let live = show && s.alive
        var cta: String? = nil
        if live { cta = wants(s, r, o).first.map { wantCta($0.key) } ?? "cta_ok" }
        return AwaySummary(from: prev.t, to: now, awayH: awayH, show: show,
                           greet: live ? (awayH >= awayLongH ? "welcome_long" : "welcome") : nil, cta: cta,
                           sleptH: Double(sleptMin) / 60, heartsFrom: prev.hearts, heartsTo: s.hearts, needs: needs,
                           events: ev, died: prev.alive && !s.alive, state: s)
    }

    static func wantCta(_ k: WantKey) -> String {
        switch k {
        case .food: return "cta_hungry"
        case .bath: return "cta_dirty"
        case .play: return "cta_bored"
        case .pet: return "cta_love"
        case .sleep: return "cta_tired"
        case .walk: return "cta_ok"
        }
    }

    /// Тип действия как в JSON: feed, item, pet, play, bath, steps, wake.
    public static func actionType(_ a: Action) -> String {
        switch a {
        case .feed: return "feed"
        case .item: return "item"
        case .pet: return "pet"
        case .play: return "play"
        case .bath: return "bath"
        case .steps: return "steps"
        case .wake: return "wake"
        }
    }

    // MARK: план уведомлений

    static func localDay(_ t: Double, _ o: Owner) -> Int {
        let m = Int((t / 60).rounded(.down)) + o.tzOffsetMin
        return Int((Double(m) / 1440).rounded(.down))
    }

    /// Локальные уведомления по прогнозу без ухода (RESEARCH/07 #6): не больше 1 в местный день
    /// (самое серьёзное, при равенстве — раньшее), тихие часы переносят на их конец; первые 3 дня после
    /// открытия — по событиям прогноза, с 3-го по 14-й — только «скучаю» раз в 3 дня, дальше тишина.
    public static func notificationPlan(_ s0: PetState, _ r: Rules, _ o: Owner, now: Double,
                                        opts: NotifyOpts = NotifyOpts()) -> [PlannedNotification] {
        let s = at(s0, r, o, now)
        if !s.alive { return [] }
        let lastOpen = opts.lastOpenT ?? now
        let qFrom = opts.quietFromMin ?? o.bedMin, qTo = opts.quietToMin ?? o.wakeMin
        let end = now + opts.horizonH * 3600
        let careUntil = lastOpen + nCareDays * 86400, stopAt = lastOpen + nStopDays * 86400
        func quiet(_ t: Double) -> Double {
            let m = localMin(t, o)
            if !inWindow(m, qFrom, qTo) { return t }
            return t + Double((((qTo - m) % 1440) + 1440) % 1440) * 60
        }
        let ev = forecast(s, r, o, horizonH: opts.horizonH)
        let deathT = ev.first(where: { $0.kind == .death })?.t ?? Double.infinity

        var cands: [(p: PlannedNotification, sev: Int)] = []
        for e in ev {
            var trigger: NotifyTrigger? = nil
            var sev = 0
            if e.kind == .low {
                trigger = e.key.flatMap { Need(rawValue: $0) }.flatMap { needTrigger($0) }; sev = 1
            } else if e.kind == .distress {
                trigger = e.key.flatMap { Distress(rawValue: $0) }.map { distressTrigger($0) }; sev = 2
            } else if e.kind == .heart {
                trigger = .heart_lost; sev = 2
            } else if e.kind == .level && e.value == 3 {
                trigger = .critical; sev = 3
            } else if e.kind == .last_chance {
                trigger = .last_chance; sev = 4
            }
            guard let tg = trigger else { continue }
            let t = quiet(e.t)
            if t >= careUntil { continue }
            cands.append((PlannedNotification(at: t, trigger: tg, kind: e.kind.rawValue, key: e.key), sev))
        }
        var k = 1.0
        while lastOpen + k * nMissEveryDays * 86400 < stopAt {
            let t = quiet(lastOpen + k * nMissEveryDays * 86400)
            if t < stopAt { cands.append((PlannedNotification(at: t, trigger: .miss_you, kind: "absent", key: nil), 0)) }
            k += 1
        }

        let sentDay = opts.lastSentT.map { localDay($0, o) }
        var kept: [(c: (p: PlannedNotification, sev: Int), i: Int)] = []
        for (i, c) in cands.enumerated()
        where c.p.at >= now + nLeadMin * 60 && c.p.at <= end && c.p.at < deathT && localDay(c.p.at, o) != sentDay {
            kept.append((c, i))
        }
        kept.sort { a, b in a.c.p.at != b.c.p.at ? a.c.p.at < b.c.p.at : a.i < b.i }
        var byDay: [Int: (p: PlannedNotification, sev: Int)] = [:]
        for x in kept {
            let d = localDay(x.c.p.at, o)
            if let cur = byDay[d], x.c.sev <= cur.sev { continue }
            byDay[d] = x.c
        }
        return byDay.values.map { $0.p }.sorted { $0.at < $1.at }
    }
}
