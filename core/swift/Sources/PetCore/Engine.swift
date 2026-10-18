// Ядро питомца — построчный порт core/ts/src/engine.ts.
// Порядок операций с плавающей точкой совпадает с TS: общие векторы в core/vectors сверяют обе версии.
// Меняешь что-то здесь — поменяй и в TS, перегенерируй векторы (node core/ts/tools/vectors.ts).

import Foundation

public struct Owner: Equatable, Sendable {
    public var bedMin: Int       // во сколько хозяин ложится, минуты от полуночи
    public var wakeMin: Int      // во сколько встаёт
    public var tzOffsetMin: Int  // смещение местного времени от UTC
    public init(bedMin: Int, wakeMin: Int, tzOffsetMin: Int) {
        self.bedMin = bedMin; self.wakeMin = wakeMin; self.tzOffsetMin = tzOffsetMin
    }
}

public struct PetState: Equatable, Sendable {
    public var t: Double                      // unix-секунды, до которых всё посчитано
    public var needs: Vals
    public var hearts: Double                 // дробное, на экране половинки
    public var grace: [Distress: Double]      // бодрые часы хозяина подряд в беде
    public var lastChanceH: Double?
    public var napUntil: Double?
    public var bathUntil: Double?
    public var lastHeartLossT: Double?
    public var cooldowns: [String: Double]
    public var home: [HomeLine: Int]
    public var alive: Bool
    public var diedAt: Double?
    public var cause: Distress?
    public var outing: Outing? = nil          // гуляет: с какого t, до какого и что принесёт; nil — дома
    public var finds: [String: Int] = [:]     // альбом находок с прогулок: id → сколько раз приносил
    public var pantry: Double = 0             // запас еды на кухне (очки сытости) для автокормушки
}

/// Прогулка с находкой (care.walk_out).
public struct Outing: Equatable, Sendable {
    public var from: Double
    public var until: Double
    public var find: String
    public init(from: Double, until: Double, find: String) { self.from = from; self.until = until; self.find = find }
}

public enum Action: Equatable, Sendable {
    case feed(String), item(String), pet, brush, play, bath, steps(Int), wake, walk
}

public struct ActResult: Equatable, Sendable {
    public let ok: Bool
    public let reason: String?
    static let ok = ActResult(ok: true, reason: nil)
    static func no(_ r: String) -> ActResult { ActResult(ok: false, reason: r) }
}

public struct ForecastEvent: Equatable, Sendable {
    public enum Kind: String, Sendable { case low, distress, heart, last_chance, level, death, back_home, autofeed }
    public let t: Double
    public let kind: Kind
    public let key: String?
    public let value: Int?
}

public enum PetEngine {
    static let STEP: Double = 60
    /// Ключ отката расчёсывания в cooldowns: не «brush» — так зовут расчёску в shop.consumables, а ключ предмета — его id.
    public static let BRUSH_COOLDOWN = "brushing"
    /// Сколько сытости автокормушка даёт за раз (как миска корма).
    public static let AUTOFEED_PORTION: Double = 20
    static let DH: Double = 1.0 / 60.0
    static let CARE: [Need] = [.food, .clean, .fun, .love, .walk]
    static let WATCH: [Need] = [.food, .clean, .fun, .love]

    public static func defaultOwner(_ r: Rules, tzOffsetMin: Int = 0) -> Owner {
        Owner(bedMin: r.bedMin, wakeMin: r.wakeMin, tzOffsetMin: tzOffsetMin)
    }

    public static func newPet(_ r: Rules, t: Double) -> PetState {
        var needs: Vals = [:]
        for n in Need.allCases { needs[n] = r.need(n, "start") }
        var home: [HomeLine: Int] = [:]
        for l in HomeLine.allCases { home[l] = 0 }
        return PetState(t: t, needs: needs, hearts: r.heartsMax, grace: [.starve: 0, .dirty: 0, .toska: 0],
                        lastChanceH: nil, napUntil: nil, bathUntil: nil, lastHeartLossT: nil, cooldowns: [:],
                        home: home, alive: true, diedAt: nil, cause: nil, outing: nil, finds: [:], pantry: 0)
    }

    // MARK: время суток

    public static func localMin(_ t: Double, _ o: Owner) -> Int {
        let m = Int((t / 60).rounded(.down))
        return (((m + o.tzOffsetMin) % 1440) + 1440) % 1440
    }

    static func inWindow(_ m: Int, _ from: Int, _ to: Int) -> Bool {
        let a = ((from % 1440) + 1440) % 1440, b = ((to % 1440) + 1440) % 1440
        return a <= b ? (m >= a && m < b) : (m >= a || m < b)
    }

    public static func ownerAsleep(_ t: Double, _ o: Owner) -> Bool {
        inWindow(localMin(t, o), o.bedMin, o.wakeMin)
    }

    public static func petNight(_ t: Double, _ r: Rules, _ o: Owner) -> Bool {
        inWindow(localMin(t, o), o.bedMin + r.afterBedMin, o.wakeMin + r.afterWakeMin)
    }

    // MARK: множители

    static func clamp(_ v: Double) -> Double { v < 0 ? 0 : (v > 100 ? 100 : v) }

    static func homeBuff(_ s: PetState, _ r: Rules, _ line: HomeLine) -> Effect {
        let lv = r.home[line] ?? []
        let i = s.home[line] ?? 0
        return i < lv.count ? lv[i] : [:]
    }

    /// Улучшения дома (по линиям в порядке HomeLine), затем перекрёстные эффекты в порядке конфига.
    public static func mods(_ s: PetState, _ r: Rules) -> Effect {
        var m: Effect = [:]
        func add(_ e: Effect) {
            for (k, v) in e {
                if case .number(let n) = v, k.hasSuffix("_x") {
                    if case .number(let cur)? = m[k] { m[k] = .number(cur * n) } else { m[k] = .number(1 * n) }
                } else { m[k] = v }
            }
        }
        for l in HomeLine.allCases { add(homeBuff(s, r, l)) }
        for c in r.cross where c.cond(s.needs) { add(c.then) }
        return m
    }

    static func x(_ m: Effect, _ k: String) -> Double { if case .number(let n)? = m[k] { return n }; return 1 }
    static func num(_ m: Effect, _ k: String) -> Double { if case .number(let n)? = m[k] { return n }; return 0 }

    public static func maxHearts(_ s: PetState, _ r: Rules) -> Double {
        if case .number(let n)? = homeBuff(s, r, .kennel)["max_hearts"] { return n }
        return r.heartsMax
    }

    // MARK: шаг

    static func finishBath(_ s: inout PetState, _ r: Rules) {
        let b = homeBuff(s, r, .bath)
        s.needs[.clean] = 100
        s.needs[.fun] = clamp(s.needs[.fun]! + num(b, "fun_after_bath"))
        s.needs[.look] = clamp(s.needs[.look]! + num(b, "look_after_bath"))
        s.bathUntil = nil
    }

    // MARK: прогулка

    /// FNV-1a 32 бит по ASCII-строке: одинаково в TS и Swift, без случайности.
    static func fnv32(_ str: String) -> UInt32 {
        var h: UInt32 = 0x811c9dc5
        for c in str.utf8 {
            h ^= UInt32(c)
            h = h &* 0x01000193
        }
        return h
    }

    /// Сколько прогулок уже было: сумма альбома находок.
    public static func walksDone(_ s: PetState) -> Int {
        s.finds.values.reduce(0, +)
    }

    /// Вернуться с прогулки: прибавка шкал и находка в альбом.
    static func finishWalk(_ s: inout PetState, _ r: Rules) {
        guard let w = s.outing else { return }
        if let wo = r.walkOut { applyEffect(&s, wo.onReturn, maxHearts(s, r)) }
        s.finds[w.find, default: 0] += 1
        s.outing = nil
    }

    /// Автокормушка кухни (бафф autofeed_below): дома и не в ванне, сытость ниже порога — порция из запаса.
    static func autofeed(_ s: inout PetState, _ r: Rules) {
        let below = num(homeBuff(s, r, .kitchen), "autofeed_below")
        let left = s.pantry
        if below <= 0 || left <= 0 || s.outing != nil || s.bathUntil != nil || s.needs[.food]! >= below { return }
        let p = min(left, AUTOFEED_PORTION)
        s.needs[.food] = clamp(s.needs[.food]! + p)
        s.pantry = left - p
    }

    static func step(_ s: inout PetState, _ r: Rules, _ o: Owner) {
        let t = s.t
        if let n = s.napUntil, t >= n { s.napUntil = nil }
        if let b = s.bathUntil, t >= b { finishBath(&s, r) }
        // прогулка кончается в until; раньше — если наступила ночь питомца или вдруг беда
        if let w = s.outing, t >= w.until || r.walkOut == nil || petNight(t, r, o)
            || Distress.allCases.contains(where: { r.distress[$0]!.cond(s.needs) }) {
            finishWalk(&s, r)
        }
        let wo = s.outing != nil ? r.walkOut : nil // гуляет: шкалы по своим множителям, урона и смерти нет
        autofeed(&s, r)

        let asleep = ownerAsleep(t, o)
        let night = petNight(t, r, o)
        if !night && petNight(t - STEP, r, o) {
            s.needs[.love] = clamp(s.needs[.love]! + num(homeBuff(s, r, .bed), "love_on_wake"))
        }
        if !night && wo == nil && s.napUntil == nil && s.bathUntil == nil && s.needs[.energy]! < r.need(.energy, "nap_below") {
            s.napUntil = t + r.need(.energy, "nap_minutes") * 60
        }
        let sleeping = night || s.napUntil != nil
        let md = mods(s, r)
        let active = Distress.allCases.map { r.distress[$0]!.cond(s.needs) }
        let ge = r.regenAllGe
        let regenOk = WATCH.allSatisfy { s.needs[$0]! >= ge }

        // шкалы
        for n in CARE {
            let rate = sleeping ? r.need(n, "night_per_h") : r.need(n, "day_per_h")
            var k = x(md, n.rawValue + "_decay_x")
            if n == .food && night { k = k * x(md, "night_food_decay_x") }
            if let wo { k = k * (wo.decayX[n.rawValue] ?? 1) }
            s.needs[n] = clamp(s.needs[n]! - rate * k * DH)
        }
        if night {
            s.needs[.energy] = clamp(s.needs[.energy]! + r.need(.energy, "night_regen_per_h") * x(md, "night_energy_regen_x") * x(md, "sleep_regen_x") * DH)
        } else if s.napUntil != nil {
            s.needs[.energy] = clamp(s.needs[.energy]! + r.need(.energy, "nap_regen_per_h") * DH)
        } else {
            s.needs[.energy] = clamp(s.needs[.energy]! - r.need(.energy, "day_per_h") * x(md, "energy_decay_x") * (wo?.energyX ?? 1) * DH)
        }
        s.needs[.look] = clamp(s.needs[.look]! - r.need(.look, "per_day") / 24 * DH)

        // сердца: урон и «льготы» копятся только в бодрые часы хозяина
        var dmg: Double = 0
        var anyActive = false
        for (i, d) in Distress.allCases.enumerated() {
            if !active[i] { s.grace[d] = 0; continue }
            anyActive = true
            if asleep || wo != nil { continue }
            s.grace[d] = s.grace[d]! + DH
            let rd = r.distress[d]!
            if s.grace[d]! > rd.graceH { dmg = dmg + DH / rd.hoursPerHeart }
        }
        if dmg > 0 && s.hearts > 1 {
            let before = s.hearts
            s.hearts = max(1, s.hearts - dmg * x(md, "heart_damage_x"))
            if (s.hearts - 1e-9).rounded(.up) < (before - 1e-9).rounded(.up) { s.lastHeartLossT = t }
        }
        let maxH = maxHearts(s, r)
        if !anyActive && regenOk && s.hearts < maxH {
            s.hearts = min(maxH, s.hearts + r.regenPerH * (asleep ? r.regenNightX : 1) * x(md, "heart_regen_x") * DH)
        }

        // последнее сердце: таймер на бодрые часы, смерть не раньше чем через 3 ч после подъёма
        if s.hearts > 1 { s.lastChanceH = nil }
        else {
            if s.lastChanceH == nil { s.lastChanceH = r.lastChanceH }
            if !asleep && wo == nil && anyActive {
                s.lastChanceH = s.lastChanceH! - DH
                let sinceWake = (localMin(t, o) - o.wakeMin + 1440) % 1440
                if s.lastChanceH! <= 0 && Double(sinceWake) >= r.noDeathAfterWakeH * 60 {
                    s.alive = false
                    s.diedAt = t + STEP
                    s.cause = Distress.allCases[active.firstIndex(of: true)!]
                }
            }
        }
        s.t = t + STEP
    }

    /// Досчитать состояние до момента T (на месте). Остаток меньше минуты ждёт следующего вызова.
    public static func stepTo(_ s: inout PetState, _ r: Rules, _ o: Owner, _ T: Double) {
        while s.alive && s.t + STEP <= T { step(&s, r, o) }
    }

    public static func advance(_ s: PetState, _ r: Rules, _ o: Owner, _ T: Double) -> PetState {
        var c = s
        stepTo(&c, r, o, T)
        return c
    }

    // MARK: действия

    static func applyEffect(_ s: inout PetState, _ e: Effect, _ maxH: Double) {
        for n in Need.allCases { if case .number(let v)? = e[n.rawValue] { s.needs[n] = clamp(s.needs[n]! + v) } }
        if case .number(let h)? = e["hearts"] { s.hearts = min(maxH, s.hearts + h) }
    }

    /// Действие в момент s.t (сначала досчитай stepTo).
    public static func act(_ s: inout PetState, _ r: Rules, _ o: Owner, _ a: Action) -> ActResult {
        if !s.alive { return .no("dead") }
        // гуляет: дома никого, принимаются только шаги хозяина
        if s.outing != nil { if case .steps = a {} else { return .no("away") } }
        let t = s.t
        let md = mods(s, r)
        func cooling(_ k: String) -> Bool { if let c = s.cooldowns[k] { return c > t }; return false }
        switch a {
        case .feed(let id), .item(let id):
            let isFeed: Bool
            if case .feed = a { isFeed = true } else { isFeed = false }
            guard let e = isFeed ? r.food[id] : r.items[id] else { return .no("unknown_item") }
            if s.bathUntil != nil { return .no("bathing") }
            if cooling(id) { return .no("cooldown") }
            if isFeed {
                s.napUntil = nil
                s.pantry = num(homeBuff(s, r, .kitchen), "storage") // покормил — заодно пополнил запас на кухне
            }
            applyEffect(&s, e, maxHearts(s, r))
            if case .number(let cd)? = e["cooldown_h"] { s.cooldowns[id] = t + cd * 3600 }
            return .ok
        case .pet:
            if cooling("pet") { return .no("cooldown") }
            s.needs[.love] = clamp(s.needs[.love]! + r.petLove * x(md, "love_gain_x"))
            s.cooldowns["pet"] = t + r.petCooldownMin * 60
            return .ok
        case .brush:
            // расчесать: доля ласки «Погладить» (с теми же множителями и потолком 100), откат свой, монет ядро не знает
            guard let b = r.brush else { return .no("unavailable") }
            if s.bathUntil != nil { return .no("bathing") }
            if s.napUntil != nil || petNight(t, r, o) { return .no("asleep") }
            if level(s, r) == 3 { return .no("unwell") }
            if cooling(BRUSH_COOLDOWN) { return .no("cooldown") }
            let before = s.needs[.love]!
            let petted = clamp(before + r.petLove * x(md, "love_gain_x"))
            s.needs[.love] = clamp(before + (petted - before) * b.loveShare)
            s.cooldowns[BRUSH_COOLDOWN] = t + b.cooldownMin * 60
            return .ok
        case .play:
            if s.bathUntil != nil { return .no("bathing") }
            if s.napUntil != nil || petNight(t, r, o) { return .no("asleep") }
            if md["refuses_games"] == .flag(true) { return .no("tired") }
            s.needs[.fun] = clamp(s.needs[.fun]! + r.funGain * x(md, "fun_gain_x"))
            s.needs[.energy] = clamp(s.needs[.energy]! - r.energyCost)
            return .ok
        case .bath:
            if s.bathUntil != nil { return .no("bathing") }
            s.napUntil = nil
            s.bathUntil = t + r.bathMinutes[s.home[.bath] ?? 0] * 60
            return .ok
        case .steps(let count):
            s.needs[.walk] = clamp(s.needs[.walk]! + Double(count) / r.need(.walk, "steps_per_point"))
            return .ok
        case .wake:
            if s.napUntil == nil { return .no("not_napping") }
            s.napUntil = nil
            return .ok
        case .walk:
            guard let w = r.walkOut else { return .no("unavailable") }
            if s.bathUntil != nil { return .no("bathing") }
            if s.napUntil != nil || petNight(t, r, o) { return .no("asleep") }
            if level(s, r) == 3 || Distress.allCases.contains(where: { r.distress[$0]!.cond(s.needs) }) { return .no("unwell") }
            if !w.requires(s.needs) { return .no("not_ready") }
            // длительность и находка — от минуты старта и числа прошлых прогулок
            let m = Int((t / 60).rounded(.down)), n = walksDone(s)
            var dur = w.minMin + Int(fnv32("walk:\(m):\(n)") % UInt32(w.maxMin - w.minMin + 1))
            if dur >= 1 {
                for k in 1...dur where petNight(t + Double(k) * 60, r, o) { dur = k; break }
            }
            if dur < w.minMin { return .no("too_late") }
            s.outing = Outing(from: t, until: t + Double(dur) * 60, find: w.finds[Int(fnv32("find:\(m):\(n)") % UInt32(w.finds.count))])
            return .ok
        }
    }

    // MARK: что показывать

    /// 0 — всё хорошо, 1 «Просит», 2 «Плохо», 3 «Критично».
    public static func level(_ s: PetState, _ r: Rules) -> Int {
        if !s.alive || s.hearts <= 2 { return 3 }
        if Distress.allCases.contains(where: { r.distress[$0]!.cond(s.needs) }) { return 2 }
        if let l = s.lastHeartLossT, s.t - l < 12 * 3600 { return 2 }
        if WATCH.contains(where: { s.needs[$0]! < r.warnLow }) { return 1 }
        return 0
    }

    /// Видимые состояния для виджета и острова.
    public static func moods(_ s: PetState, _ r: Rules, _ o: Owner) -> [String] {
        if !s.alive { return ["dead"] }
        var out: [String] = []
        if s.outing != nil { out.append("walking") }
        if s.bathUntil != nil { out.append("bath") }
        if petNight(s.t, r, o) { out.append("sleep") } else if s.napUntil != nil { out.append("nap") }
        if level(s, r) == 3 { out.append("critical") }
        let v = s.needs
        if v[.food]! < 25 { out.append("hungry") }
        if v[.clean]! < 10 { out.append("smelly") } else if v[.clean]! < 25 { out.append("dirty") }
        if v[.energy]! < 20 { out.append("tired") }
        if v[.fun]! < 30 { out.append("bored") }
        if v[.love]! < 35 { out.append("wants_love") }
        return out
    }

    /// Что уже было до начала наблюдения: от этого считаются новые события прогноза.
    struct Tracker {
        var low: Set<Need>
        var dist: Set<Distress>
        var lvl: Int
        var hc: Double
        var lc: Bool
        var out: String?
        var pantry: Double
    }

    static func tracker(_ s: PetState, _ r: Rules) -> Tracker {
        Tracker(low: Set(WATCH.filter { s.needs[$0]! < r.warnLow }),
                dist: Set(Distress.allCases.filter { r.distress[$0]!.cond(s.needs) }),
                lvl: level(s, r),
                hc: (s.hearts - 1e-9).rounded(.up),
                lc: s.lastChanceH != nil,
                out: s.outing?.find,
                pantry: s.pantry)
    }

    /// После шага: дописать в ev новые события (back_home, autofeed, low, distress, heart, last_chance, level).
    static func observe(_ tr: inout Tracker, _ s: PetState, _ r: Rules, _ ev: inout [ForecastEvent]) {
        // вернулся с прогулки в начале этого шага: время — начало шага (= until), key — находка
        if let f = tr.out, s.outing == nil { ev.append(ForecastEvent(t: s.t - STEP, kind: .back_home, key: f, value: nil)) }
        tr.out = s.outing?.find
        // поел из автокормушки в начале этого шага: value — сколько сытости
        if s.pantry < tr.pantry { ev.append(ForecastEvent(t: s.t - STEP, kind: .autofeed, key: nil, value: Int(tr.pantry - s.pantry))) }
        tr.pantry = s.pantry
        for n in WATCH where s.needs[n]! < r.warnLow && !tr.low.contains(n) {
            tr.low.insert(n); ev.append(ForecastEvent(t: s.t, kind: .low, key: n.rawValue, value: nil))
        }
        for d in Distress.allCases {
            let on = r.distress[d]!.cond(s.needs)
            if on && !tr.dist.contains(d) { tr.dist.insert(d); ev.append(ForecastEvent(t: s.t, kind: .distress, key: d.rawValue, value: nil)) }
            if !on { tr.dist.remove(d) }
        }
        let c = (s.hearts - 1e-9).rounded(.up)
        if c < tr.hc { ev.append(ForecastEvent(t: s.t, kind: .heart, key: nil, value: Int(c))) }
        tr.hc = c
        if s.lastChanceH != nil && !tr.lc { ev.append(ForecastEvent(t: s.t, kind: .last_chance, key: nil, value: nil)) }
        tr.lc = s.lastChanceH != nil
        let l = level(s, r)
        if l != tr.lvl { ev.append(ForecastEvent(t: s.t, kind: .level, key: nil, value: l)); tr.lvl = l }
    }

    /// Что случится, если никто не придёт: для локальных уведомлений и «умрёт в чт ~15:00».
    public static func forecast(_ s0: PetState, _ r: Rules, _ o: Owner, horizonH: Double = 72) -> [ForecastEvent] {
        var s = s0
        let end = s.t + horizonH * 3600
        var ev: [ForecastEvent] = []
        var tr = tracker(s, r)
        while s.alive && s.t + STEP <= end {
            step(&s, r, o)
            observe(&tr, s, r, &ev)
        }
        if !s.alive { ev.append(ForecastEvent(t: s.diedAt ?? s.t, kind: .death, key: s.cause?.rawValue, value: nil)) }
        return ev
    }
}

// MARK: JSON (формат core/vectors и сохранений)

extension Owner {
    public init(json j: JSONValue) {
        self.init(bedMin: Int(j["bedMin"].double ?? 0), wakeMin: Int(j["wakeMin"].double ?? 0), tzOffsetMin: Int(j["tzOffsetMin"].double ?? 0))
    }
}

extension PetState {
    public init(json j: JSONValue) {
        var needs: Vals = [:]
        for n in Need.allCases { needs[n] = j["needs"][n.rawValue].double ?? 0 }
        var grace: [Distress: Double] = [:]
        for d in Distress.allCases { grace[d] = j["grace"][d.rawValue].double ?? 0 }
        var home: [HomeLine: Int] = [:]
        for l in HomeLine.allCases { home[l] = Int(j["home"][l.rawValue].double ?? 0) }
        self.init(t: j["t"].double ?? 0, needs: needs, hearts: j["hearts"].double ?? 0, grace: grace,
                  lastChanceH: j["lastChanceH"].double, napUntil: j["napUntil"].double, bathUntil: j["bathUntil"].double,
                  lastHeartLossT: j["lastHeartLossT"].double, cooldowns: j["cooldowns"].object.compactMapValues(\.double),
                  home: home, alive: j["alive"].bool ?? false, diedAt: j["diedAt"].double,
                  cause: j["cause"].string.flatMap(Distress.init(rawValue:)),
                  // старые сохранения без прогулки: дома, альбом пуст
                  outing: Self.outingFrom(json: j["outing"]),
                  finds: j["finds"].object.compactMapValues { $0.double.map { Int($0) } },
                  pantry: j["pantry"].double ?? 0)
    }

    static func outingFrom(json o: JSONValue) -> Outing? {
        guard let from = o["from"].double, let until = o["until"].double, let find = o["find"].string else { return nil }
        return Outing(from: from, until: until, find: find)
    }
}

extension Action {
    public init?(json j: JSONValue) {
        switch j["type"].string {
        case "feed": self = .feed(j["item"].string ?? "")
        case "item": self = .item(j["item"].string ?? "")
        case "pet": self = .pet
        case "brush": self = .brush
        case "play": self = .play
        case "bath": self = .bath
        case "steps": self = .steps(Int(j["count"].double ?? 0))
        case "wake": self = .wake
        case "walk": self = .walk
        default: return nil
        }
    }
}
