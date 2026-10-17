// Что показать: одна плоская структура PetSnapshot для приложения, виджетов, острова и превью.
// Всё считается из ядра (mood, wants, rescue, level) на момент t; вьюхи ничего не решают сами.

import Foundation
@preconcurrency import PetCore

/// Поза и выражение мордочки.
enum Pose: String, Codable, CaseIterable, Hashable, Sendable {
    case happy, idle, eating, loved, sleep, nap, bath, hungry, dirty, tired, bored, lonely, sulky, critical, dead
    /// Ушёл гулять: в комнате пусто, мордочка — значок прогулки.
    case away
}

/// Главная кнопка: одно самое полезное действие сейчас.
enum MainAct: String, Codable, CaseIterable, Hashable, Sendable {
    case feed, bath, pet, play, heal, wake, open, none

    var title: String {
        switch self {
        case .feed: return "Покормить"
        case .bath: return "Помыть"
        case .pet: return "Погладить"
        case .play: return "Поиграть"
        case .heal: return "Витаминка"
        case .wake: return "Разбудить"
        case .open: return "Открыть"
        case .none: return "Моется"
        }
    }

    var icon: String {
        switch self {
        case .feed: return "fork.knife"
        case .bath: return "bathtub"
        case .pet: return "hand.raised"
        case .play: return "tennisball"
        case .heal: return "cross.case"
        case .wake: return "sun.max"
        case .open: return "arrow.up.forward.app"
        case .none: return "drop"
        }
    }

    var action: PetAction? {
        switch self {
        case .feed: return .feed(Catalog.mainFood)
        case .bath: return .bath
        case .pet: return .pet
        case .play: return .play
        case .heal: return .item(Catalog.healItem)
        case .wake: return .wake
        case .open, .none: return nil
        }
    }
}

/// Таймер под питомцем: ванна, дрёма или «проголодается через…».
struct NeedTimer: Codable, Hashable, Sendable {
    let kind: String     // bath | nap | walk | low
    let start: Double
    let end: Double
    let title: String
}

struct PetSnapshot: Hashable, Sendable {
    var t: Double
    var name: String
    var pose: Pose
    var mood: String
    var want: String?
    var wantIcon: String?
    var wantText: String?
    var urgent: Bool
    var line: String
    var islandLine: String
    var hearts: Double
    var heartsMax: Double
    var level: Int
    var main: MainAct
    var timer: NeedTimer?
    var needs: [Need: Double]
    var alive: Bool
    var buildDaysLeft: Int?
    var shared: Bool
    /// Редкий кадр-пасхалка в этом получасе: ключ кадра (frame из lines.json) или nil.
    var rare: String? = nil

    var date: Date { Date(timeIntervalSince1970: t) }

    /// Критично и ещё жив: виджеты и остров красят главную кнопку в красный «Спасти».
    var critical: Bool { Presenter.isCritical(level: level, alive: alive) }

    /// Спит ночью (не дрёма): гладить и кормить с виджета не предлагаем.
    var sleeping: Bool { alive && mood == "sleep" }

    /// Реплика для тесных мест (маленький виджет): своя, если короткая, иначе короткая островная.
    var shortLine: String { Presenter.shortLine(line, island: islandLine) }

    var levelTitle: String {
        switch level {
        case 0: return "Всё хорошо"
        case 1: return "Просит"
        case 2: return "Плохо"
        default: return alive ? "Критично" : "Нет с нами"
        }
    }
}

enum Presenter {
    /// Реакция на действие держится 90 секунд (виджеты и остров). Приложение передаёт своё окно, короче.
    static let reactionWindow: Double = 90
    /// В каких настроениях можно показать пасхалку (сырые значения Mood). Вкус — за Вадимом.
    static let rareMoods: Set<String> = ["ok", "sleep", "nap"]

    /// Снимок из файла на момент t. upcoming — прогноз от этого же стейта (если уже посчитан для timeline).
    static func make(_ f: SaveFile, at t: Double, upcoming: [ForecastEvent]? = nil,
                     reactionWindow: Double = Presenter.reactionWindow) -> PetSnapshot {
        let o = PetRunner.owner(f, at: t)
        let s = PetRunner.peek(f, at: t)
        return make(file: f, pet: s, owner: o, at: t, upcoming: upcoming, reactionWindow: reactionWindow)
    }

    static func make(file f: SaveFile, pet s: PetState, owner o: Owner, at t: Double,
                     upcoming: [ForecastEvent]? = nil,
                     reactionWindow: Double = Presenter.reactionWindow) -> PetSnapshot {
        let r = Catalog.rules
        let mood = PetEngine.mood(s, r, o, now: t)
        let level = PetEngine.level(s, r)
        let lines = Lines.shared

        // Реакция на свежее действие (кроме смерти и ванны).
        var reaction: String? = nil
        if let la = f.lastAction, la.ok, t - la.t >= 0, t - la.t < reactionWindow, s.alive, mood != .bath {
            reaction = la.kind
        }

        let pose = self.pose(mood: mood, reaction: reaction, needs: s.needs)

        // Желание в пузыре: срочное или достаточно сильное.
        var want: String? = nil
        var urgent = false
        if let w = PetEngine.wants(s, r, o, now: t).first, w.urgent || w.strength >= 0.25 {
            want = w.key.rawValue
            urgent = w.urgent
        }
        let thought = want.map { lines.thought($0) }

        // Реплика.
        let tier = self.tier(t, o)
        let tz = o.tzOffsetMin
        var keys: [String] = []
        if let reaction { keys.append("react_\(reaction)") }
        if mood == .ok {
            switch PetEngine.daypart(t, r, o) {
            case .morning: keys.append("morning")
            case .evening: keys.append("evening")
            default: break
            }
        }
        keys.append(mood.rawValue)
        // Пасхалка: ~1 получас из 20, только без реакции и в спокойном настроении.
        let sleeping = mood == .sleep || mood == .nap
        let rare: LineItem? = reaction == nil && rareMoods.contains(mood.rawValue)
            ? lines.rare(sleeping: sleeping, seed: f.petId, at: t, tzOffsetMin: tz) : nil
        let line = rare?.text ?? lines.widget(keys, seed: f.petId, at: t, tzOffsetMin: tz, tier: tier)
        let islandLine = rare.flatMap { lines.rareIsland($0, sleeping: sleeping, seed: f.petId, at: t, tzOffsetMin: tz) }
            ?? lines.island(keys, seed: f.petId, at: t, tzOffsetMin: tz, tier: tier)

        // Главное действие.
        let main: MainAct
        if !s.alive {
            main = .open
        } else if s.bathUntil != nil {
            main = .none
        } else if s.outing != nil {
            main = .open        // гуляет: действия не принимаются, только открыть приложение
        } else if let rs = PetEngine.rescue(s, r, o, now: t, food: Catalog.mainFood, heal: Catalog.healItem) {
            main = MainAct(rawValue: rs.key == "food" ? "feed" : rs.key) ?? .pet
        } else if s.napUntil != nil {
            main = .wake
        } else {
            main = .pet
        }

        return PetSnapshot(
            t: t, name: f.name, pose: pose, mood: mood.rawValue,
            want: want, wantIcon: thought?.icon, wantText: thought?.text, urgent: urgent,
            line: line, islandLine: islandLine,
            hearts: s.hearts, heartsMax: PetEngine.maxHearts(s, r), level: level, main: main,
            timer: timer(s, r, o, at: t, upcoming: upcoming), needs: s.needs, alive: s.alive,
            buildDaysLeft: f.build.map { Int(((($0.expiresT - t) / 86400)).rounded(.up)) },
            shared: Paths.isShared,
            rare: rare.map { $0.frame ?? "rare" })
    }

    static func pose(mood: Mood, reaction: String?, needs: [Need: Double]) -> Pose {
        switch reaction {
        case "feed", "item": return .eating
        case "pet": return .loved
        case "play", "wake": return .happy
        default: break
        }
        switch mood {
        case .dead: return .dead
        // Гуляет: Шибы дома нет. Сцена уводит его за край, виджет и остров показывают «Гуляет» с таймером.
        case .walking: return .away
        case .critical: return .critical
        case .bath: return .bath
        case .sleep: return .sleep
        case .nap: return .nap
        case .hungry: return .hungry
        case .smelly, .dirty: return .dirty
        case .tired: return .tired
        case .bored, .wants_walk: return .bored
        case .wants_love: return .lonely
        case .sulky: return .sulky
        case .ok:
            let watch: [Need] = [.food, .clean, .fun, .love]
            return watch.allSatisfy { (needs[$0] ?? 0) >= 60 } ? .happy : .idle
        }
    }

    /// tier реплик: 1 — день, 2 — за 3 ч до отбоя хозяина, 3 — последний час.
    static func tier(_ t: Double, _ o: Owner) -> Int {
        let m = PetEngine.localMin(t, o)
        let toBed = ((o.bedMin - m) % 1440 + 1440) % 1440
        if toBed <= 60 { return 3 }
        if toBed <= 180 { return 2 }
        return 1
    }

    static func timer(_ s: PetState, _ r: Rules, _ o: Owner, at t: Double, upcoming: [ForecastEvent]?) -> NeedTimer? {
        if let b = s.bathUntil, b > t {
            let i = min(max(0, s.home[.bath] ?? 0), max(0, r.bathMinutes.count - 1))
            let dur = r.bathMinutes.isEmpty ? 0 : r.bathMinutes[i] * 60
            return NeedTimer(kind: "bath", start: min(t, b - dur), end: b, title: "Моется")
        }
        if let n = s.napUntil, n > t {
            return NeedTimer(kind: "nap", start: t, end: n, title: "Дремлет")
        }
        // until уже прошёл, а ядро снимет прогулку только на следующем шаге — до него тоже «Гуляет»,
        // иначе на минуту выскакивает таймер голода при пустой комнате.
        if let w = s.outing {
            let end = w.until > t ? w.until : Finds.backAt(w, stateT: s.t)
            if end > t { return NeedTimer(kind: "walk", start: w.from, end: end, title: "Гуляет") }
        }
        guard s.alive, let e = ForecastTools.nextLow(upcoming ?? ForecastTools.upcoming(s, at: t, horizonH: 12, owner: o), after: t),
              e.t - t <= 12 * 3600 else { return nil }
        return NeedTimer(kind: "low", start: t, end: e.t, title: ForecastTools.title(e))
    }

    // MARK: общие подписи для виджетов, острова и Siri (одно состояние — одни слова везде)

    /// Подпись красной кнопки в критичном состоянии. Вкус — за Вадимом.
    static let rescueTitle = "Спасти"
    /// Статус спящего питомца — как у острова (IslandAct.sleep).
    static let sleepTitle = "Спит"
    /// Меньше этого таймер тикает секундами («25:13»), больше — «через 9 ч 25 мин».
    static let liveCountdownBelow: Double = 3600
    /// Реплика длиннее — маленький виджет берёт короткую островную.
    static let shortLineMax = 24

    static func isCritical(level: Int, alive: Bool) -> Bool { alive && level >= 3 }

    static func shortLine(_ line: String, island: String) -> String {
        line.count <= shortLineMax || island.isEmpty ? line : island
    }

    /// Секунды до конца → «9 ч 25 мин», «40 мин», «2 ч». Минуты вниз, но меньше минуты — «1 мин».
    static func remainingText(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0 мин" }
        let total = seconds < 60 ? 1 : Int((seconds / 60).rounded(.down))
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m) мин" }
        if m == 0 { return "\(h) ч" }
        return "\(h) ч \(m) мин"
    }

    /// Нужда наступит («через») или занятие кончится («ещё»: ванна, дрёма, прогулка).
    static func timerPrefix(kind: String) -> String { kind == "low" ? "через" : "ещё" }

    /// Тикать секундами или писать часы и минуты.
    static func timerIsLive(remaining: Double) -> Bool { remaining < liveCountdownBelow }

    /// Таймер одной строкой: «Испачкается через 9 ч 25 мин», «Моется ещё 4 мин». Пустой title — без него.
    static func timerPhrase(kind: String, title: String, remaining: Double) -> String {
        let tail = "\(timerPrefix(kind: kind)) \(remainingText(remaining))"
        return title.isEmpty ? tail : "\(title) \(tail)"
    }

    /// Заголовок таймера, когда известна только шкала (остров: в ContentState нет title).
    /// Те же слова, что ForecastTools.title для событий low/distress.
    static func timerTitle(kind: String, need: String?) -> String {
        switch kind {
        case "bath": return "Моется"
        case "nap": return "Дремлет"
        case "walk": return "Гуляет"
        default:
            switch need {
            case "food": return "Проголодается"
            case "clean": return "Испачкается"
            case "fun": return "Заскучает"
            case "love": return "Затоскует"
            default: return "Попросит"
            }
        }
    }

    /// Шкала на нуле: её подсвечиваем красным.
    static func needEmpty(_ value: Double) -> Bool { value < 1 }

    // MARK: для «Команд» и Siri

    static func statusText(at t: Double = Clock.now()) -> String {
        let f = PetStore.load()
        let snap = make(f, at: t)
        if !snap.alive { return "\(snap.name) больше нет с нами. Открой приложение." }
        var parts = ["\(snap.name): \(snap.line)"]
        let h = Int((snap.hearts - 1e-9).rounded(.up))
        parts.append("Сердечки: \(h) из \(Int(snap.heartsMax)).")
        if let w = snap.wantText { parts.append("Хочет: \(w).") }
        if let tm = snap.timer, tm.end > t {
            parts.append(timerPhrase(kind: tm.kind, title: tm.title, remaining: tm.end - t) + ".")
        }
        return parts.joined(separator: " ")
    }

    /// Снимок «сейчас» прямо из стора.
    static func current(at t: Double = Clock.now()) -> PetSnapshot {
        make(PetStore.load(), at: t)
    }
}
