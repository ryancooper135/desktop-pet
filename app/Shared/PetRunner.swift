// Время и действия поверх ядра. «Сейчас» всегда считается от часов: стейт на диске — это момент pet.t,
// любой читатель догоняет его до now сам (peek), а писатель — через catchUp внутри mutate.

import Foundation
@preconcurrency import PetCore

enum PetRunner {
    /// Догнать питомца до now: события по дороге — в журнал (ev.*), потом stepTo.
    /// Часы назад больше чем на 5 минут — не считаем, пишем clock_back (ядро не умеет назад).
    static func catchUp(_ f: inout SaveFile, now: Double) {
        let r = Catalog.rules
        if f.pet.t - now > 300 {
            if f.journal.last?.kind != "clock_back" { f.log("clock_back", t: now, value: Int(f.pet.t - now)) }
            return
        }
        if now - f.pet.t >= 60 && f.pet.alive {
            let horizon = (now - f.pet.t) / 3600
            for e in PetEngine.forecast(f.pet, r, f.owner, horizonH: horizon) where e.t <= now && e.kind != .level {
                let tail = e.key ?? e.value.map { String($0) } ?? ""
                f.log(tail.isEmpty ? "ev.\(e.kind.rawValue)" : "ev.\(e.kind.rawValue).\(tail)", t: e.t, key: e.key, value: e.value)
            }
            PetEngine.stepTo(&f.pet, r, f.owner, now)
        }
        // Часовой пояс обновляем после догона: прошлое считалось по старому поясу.
        f.owner.tzOffsetMin = Clock.tzOffsetMin(at: now)
    }

    /// Срок подписи (build_age). Если прошлая сборка истекла и приложение какое-то время не открывалось,
    /// это время питомцу прощается (sign_pause): хозяин не виноват, что подпись кончилась.
    static func applyBuild(_ f: inout SaveFile, expires: Date?, now: Double) {
        if let old = f.build, old.expiresT < now, f.pet.t < now, f.pet.alive {
            let r = Catalog.rules
            if f.pet.t < old.expiresT { PetEngine.stepTo(&f.pet, r, f.owner, old.expiresT) }
            let pauseH = (now - f.pet.t) / 3600
            if pauseH > 1 {
                f.pet.t = now
                if let b = f.pet.bathUntil, b < now { f.pet.bathUntil = nil }
                if let n = f.pet.napUntil, n < now { f.pet.napUntil = nil }
                f.log("sign_pause", t: now, value: Int(pauseH.rounded()))
            }
        }
        if let exp = expires?.timeIntervalSince1970 {
            f.build = SaveFile.BuildInfo(expiresT: exp, seenT: now)
        } else if var b = f.build {
            b.seenT = now
            f.build = b
        }
    }

    /// Действие хозяина: догнать, применить в момент pet.t, записать в журнал.
    @discardableResult
    static func perform(_ a: PetAction, source: ActionSource, store: PetStore = .shared,
                        now: Double = Clock.now()) throws -> ActOutcome {
        try store.mutate { f in apply(a, source: source, to: &f, now: now) }
    }

    /// То же без диска: для превью и тестов.
    static func apply(_ a: PetAction, source: ActionSource, to f: inout SaveFile, now: Double) -> ActOutcome {
        catchUp(&f, now: now)
        let res = PetEngine.act(&f.pet, Catalog.rules, f.owner, a.core)
        f.log("act.\(a.kind)", t: f.pet.t, source: source, ok: res.ok, reason: res.reason, key: a.key, value: a.value)
        f.lastAction = SaveFile.LastAction(kind: a.kind, source: source, t: now, ok: res.ok, reason: res.reason)
        if case .steps = a, res.ok { f.lastStepsT = now }
        return ActOutcome(ok: res.ok, reason: res.reason)
    }

    /// Лампа: во сколько хозяин ложится. Кратно 5 минутам, 20:00–02:00.
    static func setBedtime(minute: Int, store: PetStore = .shared, now: Double = Clock.now()) throws {
        let m = ((Int((Double(minute) / 5).rounded()) * 5) % 1440 + 1440) % 1440
        try store.mutate { f in
            catchUp(&f, now: now)
            f.owner.bedMin = m
            f.log("set_bed", t: now, value: m)
        }
    }

    /// Стейт на момент t без записи. Назад не считаем.
    static func peek(_ f: SaveFile, at t: Double) -> PetState {
        guard t > f.pet.t else { return f.pet }
        return PetEngine.advance(f.pet, Catalog.rules, f.owner, t)
    }

    /// Владелец с поясом на момент t (виджет может прочитать файл в другом поясе).
    static func owner(_ f: SaveFile, at t: Double) -> Owner {
        var o = f.owner
        o.tzOffsetMin = Clock.tzOffsetMin(at: t)
        return o
    }
}
