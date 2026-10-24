// Волна 33 B: рост щенок → подросток → взрослый (RESEARCH/20-tycoon-design.md, раздел 4).
//
// Раз в местные сутки (DayKey, один раз) пёс получает очки роста:
//   g = base + span·q,  q = 0,5·H + 0,3·N + 0,2·V   (+0,05 за уют ≥ 45, не выше 1)
//   H — сердца в полночь / 4; N — доля бодрых часов хозяина без беды (голод, грязь, тоска); V — был заход.
// Пёс в побеге (Runaway) не дома: g умножается на долю суток дома, весь день в побеге — 0.
// Пропущенные сутки досчитываются при следующем заходе по копии ядра (V = 0); дальше replayMaxH — без данных, g = base.
// Часы назад ничего не дают: сутки ≤ log.day второй раз не платят, курсор назад не идёт.
// Пороги: подросток 10 очков, взрослый 35 (идеальный уход — день 10 и 35, забытый — около сотого дня),
// седая морда 365 — только вид. Вид (look) плавный по очкам, механика (mods, perks) — по стадии.
// Вызов: Growth.observe в PetRunner.catchUp до advance — тогда пропущенное время повторяется по ядру точно.
// Цифры — раздел growth в config/economy.json.

import Foundation
@preconcurrency import PetCore

// MARK: - Конфиг

/// Стадия роста. Не Stage: так зовут тип SwiftUI в соседних модулях.
enum GrowthPhase: String, CaseIterable, Codable, Sendable {
    case puppy, teen, adult

    var title: String {
        switch self {
        case .puppy: return "Щенок"
        case .teen: return "Подросток"
        case .adult: return "Взрослый"
        }
    }
}

/// Вид пса для рига и голоса: множители к взрослому (1 — как у взрослого).
struct GrowthLook: Hashable, Sendable {
    /// Размер всего пса.
    var scale: Double
    /// Голова к телу.
    var head: Double
    /// Длина лап (щенок — короткие, подросток — длинные, нескладные).
    var legs: Double
    /// Насколько висят уши: 0 — стоят, 1 — висят целиком.
    var earDroop: Double
    /// Завиток хвоста: 0 — болтается прямо, 1 — пышное кольцо.
    var tailCurl: Double
    /// Высота голоса (Synth).
    var voicePitch: Double
    /// Голос ломается: доля «то высоко, то низко» (подросток).
    var voiceCrack: Double = 0
    /// Седая морда: 0 — нет, 1 — совсем седая. Только вид.
    var grey: Double = 0

    static func lerp(_ a: GrowthLook, _ b: GrowthLook, _ k: Double) -> GrowthLook {
        func l(_ x: Double, _ y: Double) -> Double { x + (y - x) * k }
        return GrowthLook(scale: l(a.scale, b.scale), head: l(a.head, b.head), legs: l(a.legs, b.legs),
                          earDroop: l(a.earDroop, b.earDroop), tailCurl: l(a.tailCurl, b.tailCurl),
                          voicePitch: l(a.voicePitch, b.voicePitch), voiceCrack: l(a.voiceCrack, b.voiceCrack),
                          grey: l(a.grey, b.grey))
    }
}

/// Не модификаторы ядра, а правила надстроек: находки, трюки, двор.
struct GrowthPerks: Hashable, Sendable {
    /// Шанс принести две находки вместо одной, %.
    var findDoublePct = 0
    /// Сколько простых трюков доступно (nil — все).
    var trickLimit: Int?
    /// Шанс «не хочу» на трюк без штрафа, %.
    var trickRefusePct = 0
    /// Пёс дома рядом со станцией двора — +% к её доходу.
    var stationBonusPct = 0
}

struct GrowthConfig: Hashable, Sendable {
    // очки за сутки
    var base = 0.25
    var span = 0.75
    var wHearts = 0.5
    var wCalm = 0.3
    var wVisit = 0.2
    var heartsFull = 4.0
    var cozyMin = 45
    var cozyBonus = 0.05
    /// Потолок очков за сутки: с уютом идеальный день всё равно 1 — взрослый не раньше 35-го дня.
    var maxPerDay = 1.0
    /// Сейв старше роста: дни с рождения до первого взгляда засчитываются как обычный уход.
    var legacyPerDay = 0.85
    /// Сколько пропущенных часов повторять по ядру; дальше — сутки без данных, g = base.
    var replayMaxH = 336.0
    /// Шаг выборки при повторе, минуты (полночь шаг не пересекает).
    var sampleMin = 10.0
    // пороги
    var teen = 10.0
    var adult = 35.0
    /// Седина начинает проступать с greyFrom и полная к grey.
    var greyFrom = 335.0
    var grey = 365.0
    // вид на старте стадии; между стадиями — линейно по очкам
    var look: [GrowthPhase: GrowthLook] = [
        .puppy: GrowthLook(scale: 0.65, head: 1.25, legs: 0.8, earDroop: 0.7, tailCurl: 0.35, voicePitch: 1.35),
        .teen: GrowthLook(scale: 0.85, head: 1.08, legs: 1.1, earDroop: 0.25, tailCurl: 0.15, voicePitch: 1.12,
                          voiceCrack: 0.3),
        .adult: GrowthLook(scale: 1.0, head: 1.0, legs: 1.0, earDroop: 0, tailCurl: 1.0, voicePitch: 0.92),
    ]
    // модификаторы ядра (_x) по стадии; 1 не пишется
    var mods: [GrowthPhase: [String: Double]] = [
        .puppy: ["food_decay_x": 1.15, "energy_decay_x": 1.2, "sleep_regen_x": 1.2, "trip_time_x": 1.3],
        .teen: ["fun_decay_x": 1.15],
        .adult: ["food_decay_x": 0.95, "fun_decay_x": 0.9, "trip_time_x": 0.85],
    ]
    var perks: [GrowthPhase: GrowthPerks] = [
        .puppy: GrowthPerks(trickLimit: 2),
        .teen: GrowthPerks(trickRefusePct: 15),
        .adult: GrowthPerks(findDoublePct: 10, stationBonusPct: 5),
    ]

    static let shared = GrowthConfig(json: Catalog.economy() ?? .null)

    init() {}

    init(json e: JSONValue) {
        func num(_ v: JSONValue, _ d: Double) -> Double { v.double ?? d }
        func int(_ v: JSONValue, _ d: Int) -> Int { v.double.map { Int($0) } ?? d }
        let g = e["growth"]
        let p = g["points"]
        base = max(0, num(p["base"], base))
        span = max(0, num(p["span"], span))
        wHearts = max(0, num(p["w_hearts"], wHearts))
        wCalm = max(0, num(p["w_calm"], wCalm))
        wVisit = max(0, num(p["w_visit"], wVisit))
        heartsFull = max(0.5, num(p["hearts_full"], heartsFull))
        cozyMin = int(p["cozy_min"], cozyMin)
        cozyBonus = max(0, num(p["cozy_bonus"], cozyBonus))
        maxPerDay = max(base, num(p["max_per_day"], maxPerDay))
        legacyPerDay = max(0, num(p["legacy_per_day"], legacyPerDay))
        replayMaxH = max(24, num(p["replay_max_h"], replayMaxH))
        sampleMin = min(60, max(1, num(p["sample_min"], sampleMin)))

        let ph = g["phases"]
        teen = max(1, num(ph["teen"], teen))
        adult = max(teen + 1, num(ph["adult"], adult))
        grey = max(adult, num(ph["grey"], grey))
        greyFrom = min(grey, max(adult, num(ph["grey_from"], greyFrom)))

        for k in GrowthPhase.allCases {
            let l = g["look"][k.rawValue]
            if case .object = l, var v = look[k] {
                v.scale = max(0.1, num(l["scale"], v.scale))
                v.head = max(0.1, num(l["head"], v.head))
                v.legs = max(0.1, num(l["legs"], v.legs))
                v.earDroop = min(1, max(0, num(l["ear_droop"], v.earDroop)))
                v.tailCurl = min(1, max(0, num(l["tail_curl"], v.tailCurl)))
                v.voicePitch = max(0.1, num(l["voice_pitch"], v.voicePitch))
                v.voiceCrack = min(1, max(0, num(l["voice_crack"], v.voiceCrack)))
                look[k] = v
            }
            let m = g["mods"][k.rawValue]
            if case .object(let o) = m {
                var out: [String: Double] = [:]
                for (key, v) in o where key.hasSuffix("_x") {
                    if let n = v.double, n > 0, n != 1 { out[key] = n }
                }
                mods[k] = out
            }
            let pk = g["perks"][k.rawValue]
            if case .object = pk {
                var v = GrowthPerks()
                v.findDoublePct = min(100, max(0, int(pk["find_double_pct"], 0)))
                v.trickLimit = pk["trick_limit"].double.map { max(0, Int($0)) }
                v.trickRefusePct = min(100, max(0, int(pk["trick_refuse_pct"], 0)))
                v.stationBonusPct = max(0, int(pk["station_bonus_pct"], 0))
                perks[k] = v
            }
        }
    }
}

// MARK: - Сейв

/// Итог одних засчитанных суток (для открытки и отладки).
struct GrowthDay: Codable, Hashable, Sendable {
    /// DayKey суток.
    var d: Int
    /// Очки, что дали эти сутки.
    var g: Double
    var h: Double
    var n: Double
    var v: Bool
    /// Доля суток дома (побег — 0).
    var home: Double
}

/// Копилка открытых суток: минуты бодрствования хозяина, из них в беде; минуты дома и не дома.
struct GrowthTally: Codable, Hashable, Sendable {
    var d: Int
    var awake: Double = 0
    var bad: Double = 0
    var home: Double = 0
    var away: Double = 0
    var visit = false
    /// Сутки за пределом повтора: данных нет.
    var noData = false

    init(d: Int) { self.d = d }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        d = try c.decode(Int.self, forKey: .d)
        awake = (try? c.decodeIfPresent(Double.self, forKey: .awake)) ?? 0
        bad = (try? c.decodeIfPresent(Double.self, forKey: .bad)) ?? 0
        home = (try? c.decodeIfPresent(Double.self, forKey: .home)) ?? 0
        away = (try? c.decodeIfPresent(Double.self, forKey: .away)) ?? 0
        visit = (try? c.decodeIfPresent(Bool.self, forKey: .visit)) ?? false
        noData = (try? c.decodeIfPresent(Bool.self, forKey: .noData)) ?? false
    }
}

/// Состояние в SaveFile. Пустое не пишется — старые сейвы читаются без этого поля.
struct GrowthLog: Codable, Hashable, Sendable {
    /// Накопленные очки роста.
    var points: Double = 0
    /// Последние засчитанные сутки (DayKey): эти и раньше второй раз не платят.
    var day: Int?
    /// До какого момента досмотрено.
    var t: Double?
    /// Копилка текущих суток.
    var open: GrowthTally?
    /// Последние засчитанные сутки целиком.
    var last: GrowthDay?

    var isEmpty: Bool { points == 0 && day == nil && t == nil && open == nil && last == nil }

    init() {}

    private enum CodingKeys: String, CodingKey { case points, day, t, open, last }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = max(0, (try? c.decodeIfPresent(Double.self, forKey: .points)) ?? 0)
        day = try? c.decodeIfPresent(Int.self, forKey: .day)
        t = try? c.decodeIfPresent(Double.self, forKey: .t)
        open = try? c.decodeIfPresent(GrowthTally.self, forKey: .open)
        last = try? c.decodeIfPresent(GrowthDay.self, forKey: .last)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(points, forKey: .points)
        try c.encodeIfPresent(day, forKey: .day)
        try c.encodeIfPresent(t, forKey: .t)
        try c.encodeIfPresent(open, forKey: .open)
        try c.encodeIfPresent(last, forKey: .last)
    }
}

// MARK: - Рост

enum Growth {
    /// Что принёс один observe: закрытые сутки и стадии, в которые пёс перешёл (по порядку).
    struct Report: Hashable, Sendable {
        var days: [GrowthDay] = []
        var phases: [GrowthPhase] = []
    }

    // MARK: формула

    /// Очки за сутки по §4. hearts — сердца в полночь, calm — N, home — доля суток дома.
    static func dayPoints(hearts: Double, calm: Double, visit: Bool, cozy: Int = 0, home: Double = 1,
                          _ cfg: GrowthConfig = .shared) -> Double {
        let h = min(1, max(0, hearts / cfg.heartsFull))
        let n = min(1, max(0, calm))
        let q = cfg.wHearts * h + cfg.wCalm * n + cfg.wVisit * (visit ? 1 : 0)
        var g = cfg.base + cfg.span * q
        if cozy >= cfg.cozyMin { g += cfg.cozyBonus }
        return min(cfg.maxPerDay, g) * min(1, max(0, home))
    }

    /// Засчитать сутки day один раз. false — уже засчитаны (или раньше засчитанных).
    @discardableResult
    static func credit(_ log: inout GrowthLog, day: Int, g: Double) -> Bool {
        if let done = log.day, day <= done { return false }
        log.points += max(0, g)
        log.day = day
        return true
    }

    // MARK: стадии

    static func phase(_ points: Double, _ cfg: GrowthConfig = .shared) -> GrowthPhase {
        points >= cfg.adult ? .adult : (points >= cfg.teen ? .teen : .puppy)
    }

    static func phase(_ f: SaveFile, _ cfg: GrowthConfig = .shared) -> GrowthPhase { phase(f.growth.points, cfg) }

    /// Доля пройденной стадии 0…1 (взрослый — к седине).
    static func progress(_ points: Double, _ cfg: GrowthConfig = .shared) -> Double {
        let (a, b): (Double, Double)
        switch phase(points, cfg) {
        case .puppy: (a, b) = (0, cfg.teen)
        case .teen: (a, b) = (cfg.teen, cfg.adult)
        case .adult: (a, b) = (cfg.adult, cfg.grey)
        }
        return min(1, max(0, (points - a) / (b - a)))
    }

    /// Следующая стадия и сколько очков до неё; nil — взрослый.
    static func next(_ points: Double, _ cfg: GrowthConfig = .shared) -> (phase: GrowthPhase, left: Double)? {
        switch phase(points, cfg) {
        case .puppy: return (.teen, cfg.teen - points)
        case .teen: return (.adult, cfg.adult - points)
        case .adult: return nil
        }
    }

    // MARK: вид

    /// Вид по очкам: линейно между стартами стадий, после взрослого — как взрослый, плюс седина. Без скачков.
    static func look(points: Double, _ cfg: GrowthConfig = .shared) -> GrowthLook {
        let p = max(0, points)
        let pup = cfg.look[.puppy]!, teen = cfg.look[.teen]!, adult = cfg.look[.adult]!
        var l: GrowthLook
        if p < cfg.teen { l = GrowthLook.lerp(pup, teen, p / cfg.teen) }
        else if p < cfg.adult { l = GrowthLook.lerp(teen, adult, (p - cfg.teen) / (cfg.adult - cfg.teen)) }
        else { l = adult }
        if cfg.grey > cfg.greyFrom { l.grey = min(1, max(0, (p - cfg.greyFrom) / (cfg.grey - cfg.greyFrom))) }
        else { l.grey = p >= cfg.grey ? 1 : 0 }
        return l
    }

    static func look(_ f: SaveFile, _ cfg: GrowthConfig = .shared) -> GrowthLook { look(points: f.growth.points, cfg) }

    // MARK: механика

    /// Модификаторы ядра от стадии (ключи _x, как ItemPerks.mods). Ступенькой: стадия сменилась — сменились.
    /// trip_time_x — не ядро, а время похода на место карты (Places).
    static func mods(_ f: SaveFile, _ cfg: GrowthConfig = .shared) -> [String: Double] {
        cfg.mods[phase(f, cfg)] ?? [:]
    }

    static func perks(_ f: SaveFile, _ cfg: GrowthConfig = .shared) -> GrowthPerks {
        cfg.perks[phase(f, cfg)] ?? GrowthPerks()
    }

    // MARK: наблюдение

    /// Беда по ядру: голод, грязь или тоска (условия distress из правил).
    static func inDistress(_ s: PetState, _ r: Rules) -> Bool {
        Distress.allCases.contains { r.distress[$0]?.cond(s.needs) ?? false }
    }

    /// Досмотреть время с прошлого вызова до now и засчитать закрытые сутки. Идемпотентно: повтор с тем же now
    /// и часы назад ничего не дают. cozy — уют двора и дома на сейчас (применяется к закрытым в этот раз суткам).
    /// rules — правила ядра этого сейва (по умолчанию ItemPerks.rules), как у PetRunner.advance.
    @discardableResult
    static func observe(_ f: inout SaveFile, now: Double, cozy: Int = 0, rules: Rules? = nil,
                        _ cfg: GrowthConfig = .shared) -> Report {
        var rep = Report()
        var g = f.growth
        let today = DayKey.of(now)

        // Первый взгляд: сейв старше роста получает дни с рождения как обычный уход, считать начинаем отсюда.
        guard let t0 = g.t else {
            let born = f.bornDay
            if today > born {
                g.points += Double(today - born) * cfg.legacyPerDay
                g.day = today - 1
            }
            g.t = now
            g.open = GrowthTally(d: today)
            f.growth = g
            return rep
        }
        guard now > t0 else { return rep }   // часы назад или тот же момент

        let r = rules ?? ItemPerks.rules(f)
        let o = f.owner
        let touched = touchDays(f, from: t0, to: now)
        let before = g.points
        var open = g.open ?? GrowthTally(d: DayKey.of(t0))
        if open.d < DayKey.of(t0) { open = GrowthTally(d: DayKey.of(t0)) }

        func close(_ tl: GrowthTally, hearts: Double, alive: Bool) {
            let home = tl.home + tl.away > 0 ? tl.home / (tl.home + tl.away) : (alive ? 1 : 0)
            let n = tl.awake > 0 ? max(0, 1 - tl.bad / tl.awake) : 1
            let v = tl.visit || touched.contains(tl.d)
            let pts: Double
            if tl.noData { pts = alive ? min(cfg.maxPerDay, cfg.base) : 0 }
            else { pts = dayPoints(hearts: hearts, calm: n, visit: v, cozy: cozy, home: home, cfg) }
            if credit(&g, day: tl.d, g: pts) {
                let day = GrowthDay(d: tl.d, g: pts, h: min(1, max(0, hearts / cfg.heartsFull)), n: n, v: v, home: home)
                g.last = day
                rep.days.append(day)
            }
        }

        // Отрезок [a, b) внутри одних суток: в копилку по состоянию s.
        func add(_ a: Double, _ b: Double, _ s: PetState, away: Bool) {
            let dt = (b - a) / 60
            guard dt > 0 else { return }
            if away || !s.alive { open.away += dt; return }
            open.home += dt
            if !PetEngine.ownerAsleep((a + b) / 2, o) {
                open.awake += dt
                if inDistress(s, r) { open.bad += dt }
            }
        }

        func walk(to end: Double, _ s: inout PetState, replay: Bool, away: Bool, noData: Bool = false,
                  cur: inout Double) {
            let step = cfg.sampleMin * 60
            if noData { open.noData = true }
            while cur < end {
                let mid = DayKey.nextMidnight(after: cur)
                let next = min(end, mid, replay ? cur + step : end)
                if replay && s.alive { PetEngine.stepTo(&s, r, o, next) }
                if !open.noData { add(cur, next, s, away: away) }
                cur = next
                if next >= mid {
                    close(open, hearts: s.alive && !away ? s.hearts : 0, alive: s.alive && !away)
                    open = GrowthTally(d: DayKey.of(next))
                    open.noData = noData
                }
            }
        }

        var cur = t0
        var s = f.pet
        // Мост: пёс уже посчитан дальше курсора (догон до observe, пауза подписи, возвращение из побега).
        // Само ядро это время не повторить — берём нынешнее состояние; до возвращения из побега — не дома.
        let bridge = min(now, s.t)
        if bridge > cur + 60 {
            let back = f.runaway.comebacks.last { $0 > t0 && $0 <= bridge }
            if let b = back { walk(to: b, &s, replay: false, away: true, cur: &cur) }
            walk(to: bridge, &s, replay: false, away: !s.alive, cur: &cur)
        }
        // Повтор по ядру: копия пса шагает по времени, что ещё не досчитано.
        if s.t < cur && s.alive { PetEngine.stepTo(&s, r, o, cur) }
        let limit = cur + cfg.replayMaxH * 3600
        walk(to: min(now, limit), &s, replay: true, away: false, cur: &cur)
        if cur < now {
            // Без данных: пёс жив в конце повтора — сутки по base, нет — ноль.
            walk(to: now, &s, replay: false, away: !s.alive, noData: true, cur: &cur)
        }

        if touched.contains(open.d) { open.visit = true }
        g.open = open
        g.t = now
        f.growth = g

        // Переходы стадий: запись в журнал на каждый порог (открытка «Подрос!», Memories).
        for k in GrowthPhase.allCases where k != .puppy {
            let at = k == .teen ? cfg.teen : cfg.adult
            if before < at && g.points >= at {
                rep.phases.append(k)
                f.log("growth.phase", t: now, key: k.rawValue)
            }
        }
        return rep
    }

    /// Местные сутки, в которые хозяин касался пса (заход, виджет, остров, уведомление) в окне [from, to).
    /// Шаги и «Команды» не касание (OwnerSleep.counts).
    static func touchDays(_ f: SaveFile, from: Double, to: Double) -> Set<Int> {
        var out: Set<Int> = []
        func mark(_ t: Double?) { if let t, t >= from, t < to { out.insert(DayKey.of(t)) } }
        for e in f.journal {
            if let src = e.source, OwnerSleep.counts(src) { mark(e.t) }
        }
        if let a = f.lastAction, OwnerSleep.counts(a.source) { mark(a.t) }
        mark(f.sleep.lastT)
        mark(f.sleep.wokeT)
        return out
    }
}
