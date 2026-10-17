// Облик шерсти от ухода (RESEARCH/06 #15): колтуны → лохматый → обычный → гладкий.
// Чистая функция от (SaveFile, now), ничего не хранит. Ухоженность — экспоненциальное сглаживание чистоты
// за последние 7 суток (полураспад 30 ч): одно мытьё после недели грязи не делает шерсть гладкой сразу,
// а пара пропусков не губит её. Поглаживания и конец ванны дают небольшие толчки, шкала look — бонус сверху.
// Чистоту в прошлом восстанавливаем по журналу без симуляции ядра: якоря (конец ванны = 100, ev.low.clean = warnLow,
// ev.distress.dirty = 10, конец = шкала из peek), между ними — убыль по правилам ядра (день/ночь питомца,
// clean_decay_x). Дрёма, прогулка (×2 грязи) и еда, что трогает чистоту, не учитываются: расхождение со следующим
// якорем размазывается линейно. Стадии — с гистерезисом, автомат прогоняется по той же траектории.
// Только Foundation и PetCore: гоняется на Linux (app/Package.swift).

import Foundation
@preconcurrency import PetCore

enum CoatStage: String, CaseIterable, Sendable {
    case matted, shaggy, normal, sleek

    var title: String {
        switch self {
        case .matted: "Колтуны"
        case .shaggy: "Лохматый"
        case .normal: "Обычный"
        case .sleek: "Гладкий"
        }
    }

    /// Ключ реплик в lines.json (widget и island).
    var lineKey: String { "coat_" + rawValue }

    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// Параметры для рендера, все 0..1.
struct CoatLook: Equatable, Sendable {
    /// Ухоженность с инерцией (плюс бонус шкалы look) — от неё стадия, fluff и mats.
    var groom: Double
    /// Распушённость: торчащие пряди, шум шерсти.
    var fluff: Double
    /// Грязь сейчас, без инерции: появляется и смывается вместе со шкалой чистоты.
    var dirt: Double
    /// Блеск: ухоженная шерсть и свежая ванна; грязь гасит.
    var shine: Double
    /// Колтуны: комки только у самой запущенной шерсти.
    var mats: Double
    var stage: CoatStage

    var hintKey: String { stage.lineKey }

    /// Реплика о шерсти для виджета (запасная — общая «ok»).
    func line(seed: String, at t: Double, tzOffsetMin: Int = 0, lines: Lines = .shared) -> String {
        lines.widget([hintKey], seed: seed, at: t, tzOffsetMin: tzOffsetMin)
    }

    func islandLine(seed: String, at t: Double, tzOffsetMin: Int = 0, lines: Lines = .shared) -> String {
        lines.island([hintKey], seed: seed, at: t, tzOffsetMin: tzOffsetMin)
    }
}

enum Coat {
    /// Окно истории и запас до него, где ищем якоря чистоты.
    static let windowH: Double = 7 * 24
    static let leadH: Double = 48
    /// Шаг сетки (кратные шага по абсолютному времени — результат не дрожит, когда now сдвигается).
    static let stepS: Double = 900
    static let halfLifeH: Double = 30
    /// Щенок стартует «рваным» (config: look.stages[0]).
    static let newborn: Double = 0.15
    /// Чистота → сигнал: ниже 10 — 0, от 70 — 1.
    static let cleanZero: Double = 10
    static let cleanFull: Double = 70
    /// Чистота перед первой ванной окна, если раньше якорей нет.
    static let beforeBath: Double = 30
    /// Толчки: поглаживание (не чаще раза в час) и конец ванны — доля от остатка до 1.
    static let petNudge: Double = 0.01
    static let petGapS: Double = 3600
    static let bathNudge: Double = 0.08
    /// Шкала look (стрижка, Спа) — бонус к ухоженности, до +0.3.
    static let lookWeight: Double = 0.3
    /// Границы стадий matted|shaggy|normal|sleek и полуширина гистерезиса.
    static let edges: [Double] = [0.2, 0.45, 0.7]
    static let hysteresis: Double = 0.04
    /// Блёстки после ванны: полные 30 мин, потом гаснут за 2.5 ч.
    static let sparkleS: Double = 1800
    static let sparkleFadeS: Double = 9000

    static func look(_ f: SaveFile, now: Double) -> CoatLook {
        let tr = trace(f, now: now)
        let v = tr.points.last?.groom ?? newborn
        let dirt = clamp((55 - tr.cleanNow) / 45)
        var fresh: Double = 0
        if let b = tr.lastBathEnd {
            let age = tr.end - b
            fresh = age <= sparkleS ? 1 : clamp(1 - (age - sparkleS) / sparkleFadeS)
        }
        return CoatLook(groom: v,
                        fluff: clamp((0.8 - v) / 0.6),
                        dirt: dirt,
                        shine: clamp((0.7 * clamp((v - 0.55) / 0.35) + 0.3 * fresh) * (1 - dirt)),
                        mats: clamp((0.3 - v) / 0.25),
                        stage: tr.stage)
    }

    /// Следующая стадия по значению: вверх — только за границу + h, вниз — только ниже границы − h.
    static func stage(for v: Double, from prev: CoatStage) -> CoatStage {
        let up = edges.filter { v >= $0 + hysteresis }.count
        let down = edges.filter { v >= $0 - hysteresis }.count
        let i = prev.rank < up ? up : (prev.rank > down ? down : prev.rank)
        return CoatStage.allCases[i]
    }

    /// Стадия без памяти — для первой точки траектории.
    static func stage(for v: Double) -> CoatStage {
        CoatStage.allCases[edges.filter { v >= $0 }.count]
    }

    // MARK: траектория

    struct Point: Equatable, Sendable {
        let t: Double
        let clean: Double
        let groom: Double
    }

    struct Trace: Sendable {
        let end: Double
        let cleanNow: Double
        let lastBathEnd: Double?
        let points: [Point]
        let stage: CoatStage
    }

    private struct Anchor {
        let t: Double
        let v: Double
        let bath: Bool
        let order: Int
    }

    /// Ухоженность по точкам окна. Мёртвый — на момент смерти.
    static func trace(_ f: SaveFile, now: Double) -> Trace {
        let r = Catalog.rules
        let end = f.pet.alive ? now : min(now, f.pet.diedAt ?? f.pet.t)
        let s = PetRunner.peek(f, at: end)
        let o = PetRunner.owner(f, at: end)
        let cleanNow = s.needs[.clean] ?? 0
        let bonus = lookWeight * (s.needs[.look] ?? 0) / 100
        let isNew = f.createdT >= end - windowH * 3600
        let start = isNew ? min(f.createdT, end) : end - windowH * 3600
        let lead = start - leadH * 3600

        // Накопленная убыль чистоты от g0: день/ночь питомца, множитель из текущих улучшений и баффов.
        var k: Double = 1
        if case .number(let x)? = PetEngine.mods(s, r)["clean_decay_x"] { k = x }
        let dayH = r.need(.clean, "day_per_h"), nightH = r.need(.clean, "night_per_h")
        let g0 = (lead / stepS).rounded(.down) * stepS
        let n = max(1, Int(((end - g0) / stepS).rounded(.up)))
        var cum = [Double](repeating: 0, count: n + 1)
        for i in 0..<n {
            let t = g0 + Double(i) * stepS
            cum[i + 1] = cum[i] + (PetEngine.petNight(t, r, o) ? nightH : dayH) * k * stepS / 3600
        }
        func used(_ t: Double) -> Double {
            let x = min(max((t - g0) / stepS, 0), Double(n))
            let i = min(Int(x), n - 1)
            return cum[i] + (cum[i + 1] - cum[i]) * (x - Double(i))
        }

        // Якоря и толчки из журнала.
        let lv = s.home[.bath] ?? 0
        let bathMin = r.bathMinutes.isEmpty ? 60 : r.bathMinutes[min(max(lv, 0), r.bathMinutes.count - 1)]
        var anchors: [Anchor] = []
        var pets: [Double] = []
        var bathEnds: [Double] = []
        for e in f.journal where e.t >= lead && e.t <= end {
            switch e.kind {
            case "act.bath" where e.ok == true:
                let b = e.t + bathMin * 60
                if b <= end {
                    anchors.append(Anchor(t: b, v: 100, bath: true, order: anchors.count))
                    bathEnds.append(b)
                }
            case "ev.low.clean":
                anchors.append(Anchor(t: e.t, v: r.warnLow, bath: false, order: anchors.count))
            case "ev.distress.dirty":
                anchors.append(Anchor(t: e.t, v: cleanZero, bath: false, order: anchors.count))
            case "act.pet" where e.ok == true:
                pets.append(e.t)
            default:
                break
            }
        }
        anchors.append(Anchor(t: end, v: cleanNow, bath: false, order: anchors.count))
        if f.createdT >= lead, f.createdT <= end {
            anchors.append(Anchor(t: f.createdT, v: PetEngine.newPet(r, t: f.createdT).needs[.clean] ?? r.warnLow,
                                  bath: false, order: -1))
        }
        anchors.sort { ($0.t, $0.order) < ($1.t, $1.order) }
        // Первый якорь — ванна или чистота ниже warnLow, а ev.low.clean раньше нет: значит, порог пройден
        // до начала известной истории, и тогда было не выше warnLow. Иначе назад от якоря вышла бы чистая шерсть.
        if let a0 = anchors.first, a0.bath || a0.v < r.warnLow {
            let known = f.journal.count >= SaveFile.journalMax ? max(lead, f.journal.first?.t ?? lead) : lead
            if known < a0.t { anchors.insert(Anchor(t: known, v: r.warnLow, bath: false, order: -2), at: 0) }
        }
        pets.sort()
        bathEnds.sort()

        func clean(_ t: Double) -> Double {
            let j = anchors.firstIndex { $0.t > t }
            let a = (j ?? anchors.count) > 0 ? anchors[(j ?? anchors.count) - 1] : nil
            let b = j.map { anchors[$0] }
            if let a {
                var v = max(0, a.v - (used(t) - used(a.t)))
                if let b, !b.bath, b.t > a.t {
                    let miss = b.v - max(0, a.v - (used(b.t) - used(a.t)))
                    v += miss * (t - a.t) / (b.t - a.t)
                }
                return min(100, max(0, v))
            }
            guard let b else { return cleanNow }
            return min(100, max(0, (b.bath ? beforeBath : b.v) + used(b.t) - used(t)))
        }
        func signal(_ c: Double) -> Double { clamp((c - cleanZero) / (cleanFull - cleanZero)) }

        // Точки: start, кратные шага внутри окна, end.
        var ts: [Double] = [start]
        var t = (start / stepS).rounded(.down) * stepS + stepS
        while t < end {
            ts.append(t)
            t += stepS
        }
        if end > start { ts.append(end) }

        let c0 = clean(start)
        var raw = isNew ? newborn : signal(c0)
        var stage = Self.stage(for: clamp(raw + bonus))
        var points = [Point(t: start, clean: c0, groom: clamp(raw + bonus))]
        var pi = pets.firstIndex { $0 > start } ?? pets.count
        var bi = bathEnds.firstIndex { $0 > start } ?? bathEnds.count
        var lastPet = -Double.infinity
        for i in 1..<ts.count {
            let (p, q) = (ts[i - 1], ts[i])
            let c = clean(q)
            raw += (1 - pow(2, -(q - p) / (halfLifeH * 3600))) * (signal(c) - raw)
            while pi < pets.count, pets[pi] <= q {
                if pets[pi] - lastPet >= petGapS {
                    raw += petNudge * (1 - raw)
                    lastPet = pets[pi]
                }
                pi += 1
            }
            while bi < bathEnds.count, bathEnds[bi] <= q {
                raw += bathNudge * (1 - raw)
                bi += 1
            }
            raw = clamp(raw)
            let v = clamp(raw + bonus)
            stage = Self.stage(for: v, from: stage)
            points.append(Point(t: q, clean: c, groom: v))
        }
        return Trace(end: end, cleanNow: cleanNow, lastBathEnd: bathEnds.last, points: points, stage: stage)
    }

    static func clamp(_ v: Double) -> Double { v.isNaN ? 0 : min(1, max(0, v)) }
}
