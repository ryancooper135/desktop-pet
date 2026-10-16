// Прогноз «если никто не придёт»: точки для timeline виджета, ближайший таймер, staleDate острова.

import Foundation
@preconcurrency import PetCore

enum ForecastTools {
    /// События прогноза от стейта, досчитанного до t.
    static func upcoming(_ s: PetState, at t: Double, horizonH: Double = 24, owner: Owner? = nil) -> [ForecastEvent] {
        let r = Catalog.rules
        let o = owner ?? PetEngine.defaultOwner(r, tzOffsetMin: Clock.tzOffsetMin(at: t))
        let s0 = t > s.t ? PetEngine.advance(s, r, o, t) : s
        return PetEngine.forecast(s0, r, o, horizonH: horizonH)
    }

    static func upcoming(_ f: SaveFile, at t: Double, horizonH: Double = 24) -> [ForecastEvent] {
        upcoming(f.pet, at: t, horizonH: horizonH, owner: PetRunner.owner(f, at: t))
    }

    /// Ближайшее событие, которое стоит показать таймером.
    static func nextLow(_ ev: [ForecastEvent], after t: Double) -> ForecastEvent? {
        ev.first { e in
            e.t > t && (e.kind == .low || e.kind == .distress || e.kind == .last_chance || e.kind == .death)
        }
    }

    static func title(_ e: ForecastEvent) -> String {
        switch e.kind {
        case .low, .distress:
            switch e.key {
            case "food", "starve": return "Проголодается"
            case "clean", "dirty": return "Испачкается"
            case "fun": return "Заскучает"
            case "love", "toska": return "Затоскует"
            default: return "Попросит"
            }
        case .last_chance: return "Последний шанс"
        case .death: return "Может не дождаться"
        default: return "Попросит"
        }
    }

    /// Моменты, когда картинка виджета меняется: сейчас, каждые 30 минут на 24 ч, события прогноза,
    /// конец ванны и дрёмы, смена ночи, конец реакции на действие. Точки ближе минуты склеиваются, не больше 64.
    static func timelineDates(_ f: SaveFile, now: Double, events: [ForecastEvent]) -> [Double] {
        let r = Catalog.rules
        let o = PetRunner.owner(f, at: now)
        let s = PetRunner.peek(f, at: now)
        let end = now + 24 * 3600
        var pts: [Double] = [now]
        var k = 1.0
        while now + k * 1800 <= end { pts.append(now + k * 1800); k += 1 }
        for e in events where e.t > now && e.t <= end { pts.append(e.t + 1) }
        if let b = s.bathUntil, b > now { pts.append(b + 1) }
        if let n = s.napUntil, n > now { pts.append(n + 1) }
        if let la = f.lastAction, la.t + Presenter.reactionWindow > now { pts.append(la.t + Presenter.reactionWindow + 1) }
        // Смены ночи с шагом 5 минут.
        var night = PetEngine.petNight(now, r, o)
        var x = now + 300
        while x <= end {
            let n = PetEngine.petNight(x, r, o)
            if n != night { pts.append(x); night = n }
            x += 300
        }
        pts.sort()
        var out: [Double] = []
        for p in pts {
            if let last = out.last, p - last < 60 { continue }
            out.append(p)
            if out.count >= 64 { break }
        }
        return out
    }

    /// Когда содержимое острова устареет: ближайшее из конца ванны, следующего события прогноза, startedT + 8 ч.
    static func staleDate(_ s: PetState, events: [ForecastEvent], now: Double, startedT: Double?) -> Date {
        var c: [Double] = [now + 8 * 3600]
        if let b = s.bathUntil, b > now { c.append(b) }
        if let e = events.first(where: { $0.t > now }) { c.append(e.t) }
        if let st = startedT { c.append(st + 8 * 3600) }
        return Date(timeIntervalSince1970: c.min() ?? now + 3600)
    }
}
