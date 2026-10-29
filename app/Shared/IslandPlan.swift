// Что предложить в острове: одна большая кнопка (самое нужное, что ядро сейчас примет) и максимум одна маленькая.
// Порядок: смерть → ванна → прогулка → спасение → ночь → дрёма → желания → «погладить» → «всё хорошо».
// Ядро решает само (rescue, wants, act); здесь только выбор и проверка, что действие не откажут.

import Foundation
@preconcurrency import PetCore

/// Кнопка или статус в острове. Статусы (sleep, wait, walk, open, rest) — без действия.
enum IslandAct: String, Codable, CaseIterable, Hashable, Sendable {
    case feed, bath, play, pet, heal, wake
    case sleep, wait, walk, open, rest

    var title: String {
        switch self {
        case .feed: return "Покормить"
        case .bath: return "Помыть"
        case .play: return "Поиграть"
        case .pet: return "Погладить"
        case .heal: return "Витаминка"
        case .wake: return "Разбудить"
        case .sleep: return "Спит"
        case .wait: return "Моется"
        case .walk: return "Гуляет"
        case .open: return "Открыть"
        case .rest: return "Всё хорошо"
        }
    }

    var icon: String {
        switch self {
        case .feed: return "fork.knife"
        case .bath: return "bathtub.fill"
        case .play: return "tennisball.fill"
        case .pet: return "hand.raised.fill"
        case .heal: return "cross.case.fill"
        case .wake: return "sun.max.fill"
        case .sleep: return "moon.zzz.fill"
        case .wait: return "drop.fill"
        case .walk: return "figure.walk"
        case .open: return "arrow.up.forward.app.fill"
        case .rest: return "heart.fill"
        }
    }

    var action: PetAction? {
        switch self {
        case .feed: return .feed(Catalog.mainFood)
        case .bath: return .bath
        case .play: return .play
        case .pet: return .pet
        case .heal: return .item(Catalog.healItem)
        case .wake: return .wake
        case .sleep, .wait, .walk, .open, .rest: return nil
        }
    }

    /// Главная кнопка приложения → кнопка острова (для старых снимков и превью).
    static func from(_ m: MainAct) -> IslandAct {
        switch m {
        case .feed: return .feed
        case .bath: return .bath
        case .pet: return .pet
        case .play: return .play
        case .heal: return .heal
        case .wake: return .wake
        case .open: return .open
        case .none: return .wait
        }
    }

    /// Ключ спасения ядра: food | bath | play | pet | heal.
    init?(rescueKey k: String) {
        switch k {
        case "food": self = .feed
        case "bath": self = .bath
        case "play": self = .play
        case "pet": self = .pet
        case "heal": self = .heal
        default: return nil
        }
    }

    /// Желание из пузыря → кнопка. sleep и walk с острова не исполнить.
    init?(want k: WantKey) {
        switch k {
        case .food: self = .feed
        case .bath: self = .bath
        case .play: self = .play
        case .pet: self = .pet
        case .sleep, .walk: return nil
        }
    }
}

struct IslandPick: Hashable, Sendable {
    var primary: IslandAct
    var secondary: IslandAct?
    /// Волна 45 O: действия (feed, bath, play, pet), которые ядро примет прямо сейчас, не будя пса.
    /// Ночью, в дрёме, на прогулке и в ванне — пусто: кнопка просьбы тогда «Открыть».
    var calm: Set<IslandAct> = []
}

enum IslandPlan {
    /// Сколько секунд мордочка в острове радуется после действия. Решает Вадим.
    static let reactionHold: Double = 15
    /// «Погладить» — запасная большая кнопка, когда больше ничего не нужно, и маленькая рядом. Решает Вадим.
    static let petAsFallback = true
    /// Играть прямо из острова, не открывая приложение. Решает Вадим.
    static let playFromIsland = true

    static func pick(_ f: SaveFile, at t: Double) -> IslandPick {
        pick(PetRunner.peek(f, at: t), Catalog.rules, PetRunner.owner(f, at: t))
    }

    /// s — стейт, уже досчитанный до нужного момента (s.t).
    static func pick(_ s: PetState, _ r: Rules, _ o: Owner) -> IslandPick {
        guard s.alive else { return IslandPick(primary: .open, secondary: nil) }
        if s.bathUntil != nil { return IslandPick(primary: .wait, secondary: nil) }
        // Гуляет: ядро откажет всем действиям («away»), остаётся статус с таймером до возвращения.
        if s.outing != nil { return IslandPick(primary: .walk, secondary: nil) }

        func accepted(_ a: IslandAct) -> Bool {
            guard let pa = a.action else { return false }
            if a == .play && !playFromIsland { return false }
            var c = s
            return PetEngine.act(&c, r, o, pa.core).ok
        }
        let wanted: [IslandAct] = PetEngine.wants(s, r, o, now: s.t).compactMap { IslandAct(want: $0.key) }

        let primary: IslandAct
        if let rs = PetEngine.rescue(s, r, o, now: s.t, food: Catalog.mainFood, heal: Catalog.healItem),
           let a = IslandAct(rescueKey: rs.key), accepted(a) {
            primary = a
        } else if PetEngine.petNight(s.t, r, o) {
            // Ночью без беды не будим: только статус.
            return IslandPick(primary: .sleep, secondary: nil)
        } else if s.napUntil != nil {
            primary = .wake
        } else if let a = wanted.first(where: accepted) {
            primary = a
        } else if petAsFallback && accepted(.pet) {
            primary = .pet
        } else {
            primary = .rest
        }

        var rest = wanted
        if petAsFallback { rest.append(.pet) }
        let secondary = rest.first { $0 != primary && accepted($0) }
        let calm: Set<IslandAct> = s.napUntil != nil ? [] : Set([IslandAct.feed, .bath, .play, .pet].filter(accepted))
        return IslandPick(primary: primary, secondary: secondary, calm: calm)
    }

    /// Волна 33 E: кнопка развёрнутого островка для события (IslandEvents). pick — что ядро примет сейчас:
    /// на «последнем сердечке» нужна та кнопка, что спасает; без неё — «Открыть».
    /// Волна 45 O: просьба — кнопкой та, что выполняет просьбу (ask: "pet" → «Погладить»), если ядро примет её
    /// сейчас и пса не надо будить (pick.calm); расчесать и гулять — только в приложении; иначе «Открыть».
    static func act(for kind: IslandEvent.Kind, pick: IslandPick? = nil, ask: String? = nil) -> IslandAct {
        switch kind {
        case .ask:
            let a: IslandAct?
            switch ask {
            case "feed"?: a = .feed
            case "bath"?: a = .bath
            case "pet"?: a = .pet
            case "play"?: a = .play
            default: a = nil
            }
            if let a, pick?.calm.contains(a) == true { return a }
            return .open
        case .lastChance:
            if let p = pick?.primary, p.action != nil { return p }
            return .open
        case .hungry: return .feed
        case .trip: return .walk
        case .home: return .pet
        case .runaway, .bank, .levelUp: return .open
        }
    }

    /// Ключ события прогноза (шкала или беда) → шкала для иконки таймера.
    static func timerNeed(key: String?) -> Need? {
        guard let key else { return nil }
        switch key {
        case "food", "starve": return .food
        case "clean", "dirty": return .clean
        case "love", "toska": return .love
        default: return Need(rawValue: key)
        }
    }
}
