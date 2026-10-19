// Действие хозяина в виде, который можно сохранить и передать между процессами.
// Action ядра не Codable и не Hashable, поэтому своя обёртка.

import Foundation
@preconcurrency import PetCore

enum PetAction: Codable, Hashable, Sendable {
    case feed(String)
    case item(String)
    case pet
    case brush          // расчесать: половина ласки «Погладить», откат 6 ч (Brush.swift)
    case play
    case bath
    case wake
    case steps(Int)
    case walk           // прогулка с находкой: уходит на 1–3 ч

    var core: Action {
        switch self {
        case .feed(let id): return .feed(id)
        case .item(let id): return .item(id)
        case .pet: return .pet
        case .brush: return .brush
        case .play: return .play
        case .bath: return .bath
        case .wake: return .wake
        case .steps(let n): return .steps(n)
        case .walk: return .walk
        }
    }

    init(_ a: Action) {
        switch a {
        case .feed(let id): self = .feed(id)
        case .item(let id): self = .item(id)
        case .pet: self = .pet
        case .brush: self = .brush
        case .play: self = .play
        case .bath: self = .bath
        case .wake: self = .wake
        case .steps(let n): self = .steps(n)
        case .walk: self = .walk
        }
    }

    /// Тип как в JSON ядра: feed, item, pet, brush, play, bath, steps, wake, walk.
    var kind: String { PetEngine.actionType(core) }

    /// Предмет для feed/item.
    var key: String? {
        switch self {
        case .feed(let id), .item(let id): return id
        default: return nil
        }
    }

    /// Число шагов для steps.
    var value: Int? {
        if case .steps(let n) = self { return n }
        return nil
    }

    init?(kind: String, key: String?, value: Int?) {
        switch kind {
        case "feed": self = .feed(key ?? Catalog.mainFood)
        case "item": self = .item(key ?? Catalog.healItem)
        case "pet": self = .pet
        case "brush": self = .brush
        case "play": self = .play
        case "bath": self = .bath
        case "wake": self = .wake
        case "steps": self = .steps(value ?? 0)
        case "walk": self = .walk
        default: return nil
        }
    }
}

/// Откуда пришло действие. Пишется в журнал и в lastAction.
enum ActionSource: String, Codable, CaseIterable, Sendable {
    case app, widget, island, control, shortcut, notification, steps
}

/// Итог действия для интентов и UI. reason — код отказа ядра (cooldown, bathing, asleep…) или store.
struct ActOutcome: Hashable, Sendable {
    let ok: Bool
    let reason: String?
    /// Сколько монет начислено этим действием (0 — не за что или дневной потолок).
    var coins = 0

    static let storeFailed = ActOutcome(ok: false, reason: "store")
}

/// Тексты отказов. В lines.json своих refuse_* пока нет.
enum RefuseText {
    /// name — кто в комнате (SaveFile.petName): «Мурка больше не с нами» вместо «Шибы больше нет».
    static func text(_ reason: String?, name: String) -> String {
        PetNames.adapt(text(reason), name: name)
    }

    static func text(_ reason: String?) -> String {
        switch reason {
        case "dead": return "Шибы больше нет"
        case "bathing": return "Сначала домоемся"
        case "cooldown": return "Чуть позже, только что было"
        case "asleep": return "Спит. Пусть поспит"
        case "tired": return "Сил нет играть, пусть отдохнёт"
        case "not_napping": return "Он и так не спит"
        case "unknown_item": return "Такого у нас нет"
        case "away": return "Гуляет, скоро вернётся"
        case "unwell": return "Ему плохо, сначала помоги"
        case "not_ready": return "Сначала покорми и почисти, сил на прогулку мало"
        case "too_late": return "Поздно, скоро спать"
        case "unavailable": return "Гулять пока нельзя"
        case "store": return "Не получилось сохранить"
        default: return "Не вышло"
        }
    }
}
