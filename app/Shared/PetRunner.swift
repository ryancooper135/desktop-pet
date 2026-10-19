// Время и действия поверх ядра. «Сейчас» всегда считается от часов: стейт на диске — это момент pet.t,
// любой читатель догоняет его до now сам (peek), а писатель — через catchUp внутри mutate.

import Foundation
@preconcurrency import PetCore

enum PetRunner {
    /// Одинаковый отказ чаще раза в 10 минут в журнал не пишется.
    static let refusalGap: Double = 600

    /// Догнать питомца до now: события по дороге — в журнал (ev.*), потом stepTo.
    /// Часы назад больше чем на 5 минут — не считаем, пишем clock_back (ядро не умеет назад).
    static func catchUp(_ f: inout SaveFile, now: Double) {
        if f.pet.t - now > 300 {
            if f.journal.last?.kind != "clock_back" { f.log("clock_back", t: now, value: Int(f.pet.t - now)) }
            return
        }
        // Меньше минуты не догоняем (журнал и ядро не дёргаются на каждое нажатие), но через полночь — всегда:
        // действие пишется временем питомца, и иначе первая минута суток засчитывалась бы во вчерашние.
        let newDay = now > f.pet.t && Economy.day(now) > Economy.day(f.pet.t)
        if (now - f.pet.t >= 60 || newDay) && f.pet.alive { advance(&f, to: now) }
        // Часовой пояс обновляем после догона: прошлое считалось по старому поясу.
        f.owner.tzOffsetMin = Clock.tzOffsetMin(at: now)
        // Открытки дня: после местной полуночи разобрать вчерашний журнал, пока он не вытеснен.
        Postcards.refresh(&f, now: now)
    }

    /// Шаг ядра до t с записью событий по дороге (ev.*) и наблюдением вкуса, если пёс вернулся с находкой.
    /// Общий для catchUp и applyBuild: иначе прогулка, закончившаяся до конца подписи, терялась для Tastes/Postcards.
    private static func advance(_ f: inout SaveFile, to t: Double) {
        let r = Catalog.rules
        let horizon = (t - f.pet.t) / 3600
        for e in PetEngine.forecast(f.pet, r, f.owner, horizonH: horizon) where e.t <= t && e.kind != .level {
            let tail = e.key ?? e.value.map { String($0) } ?? ""
            f.log(tail.isEmpty ? "ev.\(e.kind.rawValue)" : "ev.\(e.kind.rawValue).\(tail)", t: e.t, key: e.key, value: e.value)
        }
        let out = f.pet.outing
        PetEngine.stepTo(&f.pet, r, f.owner, t)
        // Вернулся с находкой — наблюдение вкуса (Tastes).
        if let w = out, Finds.returned(before: w, after: f.pet) != nil { Tastes.afterWalk(w, at: t, in: &f) }
    }

    /// Срок подписи (build_age). Если прошлая сборка истекла и приложение какое-то время не открывалось,
    /// это время питомцу прощается (sign_pause): хозяин не виноват, что подпись кончилась.
    static func applyBuild(_ f: inout SaveFile, expires: Date?, now: Double) {
        if let old = f.build, old.expiresT < now, f.pet.t < now, f.pet.alive {
            // До конца подписи — обычный догон (события, возвращение с прогулки, вкус), а не голый stepTo.
            if f.pet.t < old.expiresT { advance(&f, to: old.expiresT) }
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
        let before = f.pet.needs
        let res = PetEngine.act(&f.pet, Catalog.rules, f.owner, a.core)
        // Тот же отказ подряд (жмут «Погладить» на перезарядке) не пишем: иначе 200 записей журнала
        // вытесняют неделю ухода, по которой считаются шерсть и открытки.
        let repeatRefusal = !res.ok && f.journal.last.map {
            $0.kind == "act.\(a.kind)" && $0.ok == false && $0.reason == res.reason && f.pet.t - $0.t < refusalGap
        } == true
        if !repeatRefusal {
            f.log("act.\(a.kind)", t: f.pet.t, source: source, ok: res.ok, reason: res.reason, key: a.key, value: a.value)
        }
        // Вкусы: множитель к прибавке шкал и наблюдение (любимое/нелюбимое открывается за K раз).
        if res.ok { Tastes.afterAction(a, before: before, at: f.pet.t, in: &f) }
        f.lastAction = SaveFile.LastAction(kind: a.kind, source: source, t: now, ok: res.ok, reason: res.reason)
        if case .steps = a, res.ok { f.lastStepsT = now }
        // Сон хозяина: нажатие — знак, что хозяин не спит. Шаги и «Команды» не считаем: шаги приходят сами,
        // а команду может запустить автоматизация по расписанию (кормить в 7:00), пока хозяин спит.
        if OwnerSleep.counts(source) { OwnerSleep.note(&f.sleep, t: now, tzOffsetMin: f.owner.tzOffsetMin) }
        // Монеты за уход и шаги — по журналу, один раз на запись (Economy.settle).
        let coins = Economy.settle(&f).reduce(0) { $0 + $1.coins }
        return ActOutcome(ok: res.ok, reason: res.reason, coins: coins)
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
