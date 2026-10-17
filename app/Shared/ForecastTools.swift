// Прогноз «если никто не придёт»: кадры timeline виджета, ближайший таймер, staleDate острова.

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
        case .back_home: return "Вернётся"
        default: return "Попросит"
        }
    }

    // MARK: timeline виджета

    /// Сколько точек и как часто. Сетка идёт по стенным часам: смена реплики (слот 30 мин) совпадает с точкой.
    enum Budget {
        static let horizonH: Double = 24      // на сколько вперёд
        static let nearH: Double = 12         // первые 12 ч — каждые 30 минут
        static let nearStep: Double = 1800
        static let farStep: Double = 3600     // дальше — раз в час
        static let nightStep: Double = 7200   // питомец спит — раз в 2 ч
        static let maxEntries = 64
        static let minGap: Double = 60        // точки ближе склеиваются в более позднюю
        static let reloadH: Double = 12       // новый timeline не позже чем через 12 ч
        static let minReload: Double = 15 * 60
    }

    /// Шаг ядра — минута: точнее искать смену картинки незачем.
    private static let coreStep: Double = 60

    /// Всё, что видно на виджете, кроме самой реплики (она крутится по слотам сама).
    /// Смена этого между соседними точками — повод найти точную минуту и поставить туда точку.
    private struct Look: Equatable {
        let pose: Pose
        let mood: String
        let want: String?
        let urgent: Bool
        let level: Int
        let main: MainAct
        let alive: Bool
        let timerKind: String?
        let timerEnd: Double?
        let halfHearts: Int
        let tier: Int
        let daypart: Daypart
    }

    private struct Probe {
        let t: Double
        let pet: PetState
        let snap: PetSnapshot
        let look: Look
    }

    private static func look(_ s: PetSnapshot, _ o: Owner, _ r: Rules) -> Look {
        Look(pose: s.pose, mood: s.mood, want: s.want, urgent: s.urgent, level: s.level, main: s.main, alive: s.alive,
             timerKind: s.timer?.kind, timerEnd: s.timer?.end, halfHearts: Int((s.hearts * 2 - 1e-9).rounded(.up)),
             tier: Presenter.tier(s.t, o), daypart: PetEngine.daypart(s.t, r, o))
    }

    /// Кадры виджета на horizonH часов вперёд, если никто не придёт: ядро крутится без действий,
    /// в каждой точке — поза, шкалы, пузырь мысли, реплика и таймер. Точки: сейчас, сетка Budget,
    /// события прогноза, конец реакции на действие; между соседними точками с разной картинкой
    /// бисекцией ищется минута смены (сон, дрёма, ванна, голод, пороги шкал). После смерти точек нет.
    /// tzOffsetMin — закрепить пояс (тесты); nil — пояс устройства на момент каждой точки.
    static func timeline(_ f: SaveFile, now: Double, horizonH: Double = Budget.horizonH,
                         tzOffsetMin: Int? = nil) -> [PetSnapshot] {
        let r = Catalog.rules
        func ownerAt(_ t: Double) -> Owner {
            var o = f.owner
            o.tzOffsetMin = tzOffsetMin ?? Clock.tzOffsetMin(at: t)
            return o
        }
        // Ядро крутится с поясом из файла, как PetRunner.peek в приложении; Presenter — с поясом точки.
        var eo = f.owner
        if let tzOffsetMin { eo.tzOffsetMin = tzOffsetMin }
        let o = eo
        let s0 = PetEngine.advance(f.pet, r, o, now)
        let end = now + horizonH * 3600
        // Прогноз с запасом: таймер «проголодается через…» смотрит на 12 ч вперёд и в конце timeline.
        let events = PetEngine.forecast(s0, r, o, horizonH: horizonH + 12)

        func probe(_ s: PetState, _ t: Double) -> Probe {
            let ot = ownerAt(t)
            let snap = Presenter.make(file: f, pet: s, owner: ot, at: t, upcoming: events)
            return Probe(t: t, pet: s, snap: snap, look: look(snap, ot, r))
        }

        /// Первая минута между a и bT, где картинка уже не как в a; nil — смена только в самой bT.
        func firstChange(_ a: Probe, _ bT: Double) -> Probe? {
            var lo = a
            var hi: Probe? = nil
            var hiT = bT
            while hiT - lo.t > coreStep {
                let mid = ((lo.t + hiT) / 2).rounded(.down)
                let m = probe(PetEngine.advance(lo.pet, r, o, mid), mid)
                if m.look == a.look { lo = m } else { hi = m; hiT = mid }
            }
            return hi
        }

        // Точки: сетка по стенным часам, ночью реже, дальше 12 ч — раз в час.
        var pts: [Double] = []
        var p = ((now / Budget.nearStep).rounded(.down) + 1) * Budget.nearStep
        while p <= end {
            let every = PetEngine.petNight(p, r, ownerAt(p)) ? Budget.nightStep
                : (p - now < Budget.nearH * 3600 ? Budget.nearStep : Budget.farStep)
            if p.truncatingRemainder(dividingBy: every) == 0 { pts.append(p) }
            p += Budget.nearStep
        }
        for e in events where e.t > now && e.t + 1 <= end { pts.append(e.t + 1) }
        if let la = f.lastAction, la.ok, la.t + Presenter.reactionWindow > now, la.t + Presenter.reactionWindow <= end {
            pts.append(la.t + Presenter.reactionWindow)
        }
        pts.sort()
        var times: [Double] = [now]
        for x in pts where x > now {
            if times.count > 1, let last = times.last, x - last < Budget.minGap { times[times.count - 1] = x } else { times.append(x) }
        }

        // Двигаем стейт по точкам по порядку: каждый шаг — только от прошлой точки.
        var out: [Probe] = []
        // Точки ближе minGap склеиваются в более позднюю; «сейчас» не трогаем.
        func push(_ x: Probe) {
            if out.count > 1, let last = out.last, x.t - last.t < Budget.minGap { out[out.count - 1] = x } else { out.append(x) }
        }
        var cur = s0
        for t in times {
            cur = PetEngine.advance(cur, r, o, t)
            let b = probe(cur, t)
            var died = false
            if let a = out.last, a.look != b.look {
                // Несколько смен в одном промежутке (например, проснулся и сразу проголодался) — до 4 подряд.
                var left = a
                for _ in 0..<4 {
                    guard let c = firstChange(left, t) else { break }
                    // Та же картинка, что в b, меньше чем за минуту до неё — b и так её покажет.
                    if c.look == b.look && t - c.t < Budget.minGap { break }
                    push(c)
                    // Смерть нашлась бисекцией — это последняя точка, b (тоже мёртвый) не нужен.
                    if !c.snap.alive { died = true; break }
                    if c.look == b.look { break }
                    left = c
                }
            }
            if died { break }
            push(b)
            if !cur.alive { break }
        }
        if out.count > Budget.maxEntries { out.removeLast(out.count - Budget.maxEntries) }
        return out.map { $0.snap }
    }

    /// Когда просить новый timeline: через 12 ч или раньше, если точки кончились; после смерти — через 12 ч,
    /// дальше картинка не меняется, а приложение само перезагрузит виджет.
    static func reloadT(_ snaps: [PetSnapshot], now: Double) -> Double {
        let cap = now + Budget.reloadH * 3600
        guard let last = snaps.last, last.alive else { return cap }
        return min(cap, max(now + Budget.minReload, last.t))
    }

    /// Когда содержимое острова устареет: ближайшее из конца ванны или прогулки, следующего события прогноза, startedT + 8 ч.
    static func staleDate(_ s: PetState, events: [ForecastEvent], now: Double, startedT: Double?) -> Date {
        var c: [Double] = [now + 8 * 3600]
        if let b = s.bathUntil, b > now { c.append(b) }
        if let w = s.outing?.until, w > now { c.append(w) }
        if let e = events.first(where: { $0.t > now }) { c.append(e.t) }
        if let st = startedT { c.append(st + 8 * 3600) }
        return Date(timeIntervalSince1970: c.min() ?? now + 3600)
    }
}
