// Волна 51: одно «что сейчас с псом» для виджета (small, medium, экран блокировки), контрола Пункта управления
// и островка. Сначала текущее занятие (убежал, в походе, гуляет, моется, дремлет, ночь, ест, болеет), иначе —
// главная потребность. Кнопка — только то действие, что ядро примет прямо сейчас (PetEngine.act на копии),
// иначе nil: недоступное не предлагаем никогда.
// Только Foundation и PetCore: гоняется на Linux. Вью — Shared/Views/WidgetScreenViews.swift, IslandEventViews.swift
// и Widgets/PetControls.swift.

import Foundation
@preconcurrency import PetCore

/// Что сейчас с псом. Порядок case — порядок проверки.
enum PetStatusKind: String, Codable, CaseIterable, Hashable, Sendable {
    /// Убежал (умер в ядре): ищи следы.
    case gone
    /// Поход на место (Places).
    case trip
    /// Прогулка ядра (outing).
    case walk
    case bath
    /// Дрёма днём (napUntil).
    case nap
    /// Ночь пса.
    case night
    /// Только что поел (кормушка или хозяин).
    case eat
    /// Критично: сердечек мало.
    case sick
    /// Есть главная потребность.
    case need
    /// Всё хорошо.
    case fine

    /// Пёс занят делом: показываем занятие, а не потребность.
    var busy: Bool {
        switch self {
        case .trip, .walk, .bath, .nap, .night, .eat: return true
        case .gone, .sick, .need, .fine: return false
        }
    }
}

/// Готовый вид «что сейчас»: вью только рисует.
struct PetStatus: Codable, Hashable, Sendable {
    var kind: PetStatusKind
    /// «Моется», «Спит», «Хочет есть».
    var title: String
    /// Подпись без таймера: «ещё 3 мин», «вернётся в 14:20», «Сытость 18 %».
    var detail: String?
    /// Живой таймер (Text(timerInterval:)): от и до. nil — таймера нет.
    var timerFrom: Double?
    var timerEnd: Double?
    /// Прогресс 0…1: шкала потребности или доля похода. nil — полоски нет.
    var progress: Double?
    /// Шкала главной потребности (для цвета и значка шкалы).
    var need: Need?
    /// Кнопка: только действие, которое ядро примет сейчас (act.action != nil). nil — без кнопки.
    var act: IslandAct?
    /// SF Symbol для экрана блокировки, контрола и минимального острова.
    var symbol: String
    /// Кадр пиксельного пса.
    var pose: DogPose

    /// Одна строка без живого таймера: «Моется · 3 мин», «Спит», «Хочет есть». Для контрола и inline.
    var line: String { detail.map { "\(title) · \($0)" } ?? title }

    /// Пустой вид — если логика ничего не дала (превью, пустой стор).
    static let fine = PetStatus(kind: .fine, title: "Всё хорошо", detail: nil, timerFrom: nil, timerEnd: nil,
                                progress: nil, need: nil, act: nil, symbol: "pawprint.fill", pose: .sit)
}

enum PetStatusLogic {
    /// Ниже — потребность «главная» (показываем её, а не «Всё хорошо»). Как warnLow ядра.
    static func needBar(_ r: Rules) -> Double { r.warnLow }

    /// Что сейчас с псом в момент s.t.
    /// s — стейт ядра, уже досчитанный до кадра; r — правила (с перками); eo — хозяин ядра (пояс файла: им проверяем
    /// действия), o — пояс устройства (ночь и подписи часов). trip — поход на место; ate — ел за последний шаг кадра.
    static func of(_ s: PetState, _ r: Rules, engine eo: Owner, local o: Owner, trip: IslandTrip? = nil,
                   ate: Bool = false) -> PetStatus {
        let t = s.t
        let tz = o.tzOffsetMin
        func hm(_ x: Double) -> String { IslandEvents.hm(x, tz: tz) }

        guard s.alive else {
            return PetStatus(kind: .gone, title: "Убежал", detail: "Ищи следы", timerFrom: nil, timerEnd: nil,
                             progress: nil, need: nil, act: nil, symbol: "pawprint.fill", pose: .away)
        }
        if let w = s.outing {
            return PetStatus(kind: .walk, title: "Гуляет", detail: "вернётся в \(hm(w.until))", timerFrom: w.from,
                             timerEnd: w.until, progress: frac(t, w.from, w.until), need: nil, act: nil,
                             symbol: "figure.walk", pose: .run)
        }
        if let tr = trip, t >= (tr.from ?? -.infinity), t < tr.backAt {
            let place = tr.place.isEmpty ? "В походе" : tr.place
            return PetStatus(kind: .trip, title: place, detail: "вернётся в \(hm(tr.backAt))", timerFrom: tr.from ?? t,
                             timerEnd: tr.backAt, progress: tr.from.flatMap { frac(t, $0, tr.backAt) }, need: nil, act: nil,
                             symbol: "figure.walk", pose: .run)
        }
        if let b = s.bathUntil, b > t {
            return PetStatus(kind: .bath, title: "Моется", detail: left(b - t), timerFrom: t, timerEnd: b,
                             progress: nil, need: .clean, act: nil, symbol: "bubbles.and.sparkles.fill", pose: .bath)
        }

        let pick = IslandPlan.pick(s, r, eo)
        // В дрёму и ночью — только спасающая кнопка (покормить в беде); «Разбудить» сюда не ставим: спит — пусть спит.
        let rescue = rescueAct(s, r, eo, pick)

        if let n = s.napUntil, n > t {
            return PetStatus(kind: .nap, title: "Дремлет", detail: left(n - t), timerFrom: t, timerEnd: n,
                             progress: nil, need: .energy, act: rescue, symbol: "moon.zzz.fill", pose: .sleep)
        }
        if PetEngine.petNight(t, r, o) {
            let up = nightEnd(t, r, o)
            return PetStatus(kind: .night, title: "Спит", detail: "до \(hm(up))", timerFrom: nil, timerEnd: nil,
                             progress: nil, need: nil, act: rescue, symbol: "moon.zzz.fill", pose: .sleep)
        }
        let bars = s.needs
        if ate {
            let v = bars[.food] ?? 100
            return PetStatus(kind: .eat, title: "Ест", detail: nil, timerFrom: nil, timerEnd: nil,
                             progress: min(1, max(0, v / 100)), need: .food, act: nil, symbol: "fork.knife", pose: .eat)
        }

        if PetEngine.level(s, r) >= 3 {
            // Спасающая кнопка, иначе главная кнопка острова — только если ядро примет.
            let primary: IslandAct? = pick.primary.action != nil && accepted(pick.primary, s, r, eo) ? pick.primary : nil
            let h = Int((s.hearts - 1e-9).rounded(.up))
            return PetStatus(kind: .sick, title: "Плохо себя чувствует", detail: "Сердечек: \(max(0, h))",
                             timerFrom: nil, timerEnd: nil, progress: nil, need: nil, act: rescue ?? primary,
                             symbol: "cross.case.fill", pose: .lie)
        }

        if let n = mainNeed(s, r, eo) {
            let v = bars[n] ?? 100
            // Кнопка — ровно для этой потребности, если ядро её примет; иначе nil (гулять и спать — только в приложении).
            let a = needAct(n).flatMap { accepted($0, s, r, eo) ? $0 : nil }
            return PetStatus(kind: .need, title: needTitle(n), detail: "\(Catalog.needName(n)) \(Int(v.rounded())) %",
                             timerFrom: nil, timerEnd: nil, progress: min(1, max(0, v / 100)), need: n, act: a,
                             symbol: needSymbol(n), pose: n == .food ? .bowl : .lie)
        }
        // Ничего не нужно: «Погладить», если ядро примет (как запасная кнопка острова).
        let pet: IslandAct? = IslandPlan.petAsFallback && accepted(.pet, s, r, eo) ? .pet : nil
        return PetStatus(kind: .fine, title: "Всё хорошо", detail: nil, timerFrom: nil, timerEnd: nil, progress: nil,
                         need: nil, act: pet, symbol: "pawprint.fill", pose: .sit)
    }

    /// Из сейва на now (контрол, островок).
    static func of(_ f: SaveFile, now: Double, tzOffsetMin: Int? = nil, ate: Bool = false) -> PetStatus {
        let r = ItemPerks.rules(f)
        var eo = f.owner
        if let tzOffsetMin { eo.tzOffsetMin = tzOffsetMin }
        var o = f.owner
        o.tzOffsetMin = tzOffsetMin ?? Clock.tzOffsetMin(at: now)
        var s = now > f.pet.t ? PetEngine.advance(f.pet, r, eo, now) : f.pet
        s.t = max(s.t, now)
        return of(s, r, engine: eo, local: o, trip: IslandFeed.trip(f, now: now), ate: ate)
    }

    // MARK: - Части

    /// Главная потребность: беда ядра (rescue) → самое сильное желание → самая низкая шкала ниже warnLow.
    /// nil — всё в порядке.
    static func mainNeed(_ s: PetState, _ r: Rules, _ o: Owner) -> Need? {
        if let rs = PetEngine.rescue(s, r, o, now: s.t, food: Catalog.mainFood, heal: Catalog.healItem) {
            switch rs.key {
            case "food": return .food
            case "bath": return .clean
            case "play": return .fun
            case "pet": return .love
            default: break
            }
        }
        let bar = needBar(r)
        for w in PetEngine.wants(s, r, o, now: s.t) {
            let n = wantNeed(w.key)
            if (s.needs[n] ?? 100) < bar { return n }
        }
        return nil
    }

    static func wantNeed(_ k: WantKey) -> Need {
        switch k {
        case .food: return .food
        case .bath: return .clean
        case .sleep: return .energy
        case .play: return .fun
        case .pet: return .love
        case .walk: return .walk
        }
    }

    static func needAct(_ n: Need) -> IslandAct? {
        switch n {
        case .food: return .feed
        case .clean: return .bath
        case .fun: return IslandPlan.playFromIsland ? .play : nil
        case .love: return .pet
        case .energy, .walk, .look: return nil
        }
    }

    static func needTitle(_ n: Need) -> String {
        switch n {
        case .food: return "Хочет есть"
        case .clean: return "Пора помыться"
        case .energy: return "Устал"
        case .fun: return "Скучает"
        case .love: return "Хочет ласки"
        case .walk: return "Хочет гулять"
        case .look: return "Пора причесаться"
        }
    }

    static func needSymbol(_ n: Need) -> String {
        switch n {
        case .food: return "fork.knife"
        case .clean: return "drop.fill"
        case .energy: return "bolt.fill"
        case .fun: return "tennisball.fill"
        case .love: return "heart.fill"
        case .walk: return "figure.walk"
        case .look: return "sparkles"
        }
    }

    /// Ядро примет действие кнопки прямо сейчас.
    static func accepted(_ a: IslandAct, _ s: PetState, _ r: Rules, _ o: Owner) -> Bool {
        guard let pa = a.action else { return false }
        var c = s
        return PetEngine.act(&c, r, o, pa.core).ok
    }

    /// Спасающая кнопка во сне: только если ядро видит беду и примет действие (не «Разбудить»).
    static func rescueAct(_ s: PetState, _ r: Rules, _ o: Owner, _ pick: IslandPick) -> IslandAct? {
        guard let rs = PetEngine.rescue(s, r, o, now: s.t, food: Catalog.mainFood, heal: Catalog.healItem),
              let a = IslandAct(rescueKey: rs.key), a == pick.primary, accepted(a, s, r, o) else { return nil }
        return a
    }

    /// Когда кончится ночь пса (подъём хозяина + afterWakeMin) после t.
    static func nightEnd(_ t: Double, _ r: Rules, _ o: Owner) -> Double {
        let m = PetEngine.localMin(t, o)
        let up = ((o.wakeMin + r.afterWakeMin) % 1440 + 1440) % 1440
        let d = ((up - m) % 1440 + 1440) % 1440
        return (t / 60).rounded(.down) * 60 + Double(d == 0 ? 1440 : d) * 60
    }

    /// «ещё 3 мин», «ещё 1 ч 20 мин». Минуты вверх: «ещё 0 мин» не бывает.
    static func left(_ sec: Double) -> String {
        let m = max(1, Int((sec / 60).rounded(.up)))
        if m < 60 { return "ещё \(m) мин" }
        let h = m / 60, mm = m % 60
        return mm == 0 ? "ещё \(h) ч" : "ещё \(h) ч \(mm) мин"
    }

    static func frac(_ t: Double, _ a: Double, _ b: Double) -> Double? {
        guard b > a else { return nil }
        return min(1, max(0, (t - a) / (b - a)))
    }
}
