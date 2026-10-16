// Интенты: кнопки виджета, острова, Пункта управления и «Команд».
// LiveActivityIntent система выполняет в процессе приложения (при надобности будит его в фоне),
// поэтому там же обновляется остров. Если всё же выполнилось в расширении — пишем в стор сами.
//
// source: виджет, остров и контрол передают его явно; из «Команд» приходит значение по умолчанию.

import AppIntents
import Foundation
import WidgetKit

enum IntentBridge {
    @MainActor
    static func run(_ a: PetAction, source: ActionSource) async -> ActOutcome {
        #if APP_TARGET
        return await AppActions.shared.perform(a, source: source)
        #else
        let out = (try? PetRunner.perform(a, source: source)) ?? .storeFailed
        WidgetCenter.shared.reloadAllTimelines()
        return out
        #endif
    }

    /// Главное действие: то, что сейчас на большой кнопке (rescue → разбудить → погладить).
    @MainActor
    static func runMain(source: ActionSource) async -> ActOutcome {
        let snap = Presenter.current()
        guard let a = snap.main.action else { return ActOutcome(ok: false, reason: snap.alive ? "bathing" : "dead") }
        return await run(a, source: source)
    }

    @MainActor
    static func startIsland(source: ActionSource) async {
        #if APP_TARGET
        await AppActions.shared.setIsland(enabled: true)
        #else
        _ = try? PetStore.shared.mutate { $0.island.enabled = true }
        #endif
    }
}

struct FeedIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Покормить Шибу"

    @Parameter(title: "Откуда", default: "shortcut")
    var source: String

    init() {}
    init(_ src: ActionSource) { source = src.rawValue }

    func perform() async throws -> some IntentResult {
        let src = ActionSource(rawValue: source) ?? .shortcut
        _ = await IntentBridge.run(.feed(Catalog.mainFood), source: src)
        return .result()
    }
}

struct PetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Погладить Шибу"

    @Parameter(title: "Откуда", default: "shortcut")
    var source: String

    init() {}
    init(_ src: ActionSource) { source = src.rawValue }

    func perform() async throws -> some IntentResult {
        let src = ActionSource(rawValue: source) ?? .shortcut
        _ = await IntentBridge.run(.pet, source: src)
        return .result()
    }
}

struct BathIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Помыть Шибу"

    @Parameter(title: "Откуда", default: "shortcut")
    var source: String

    init() {}
    init(_ src: ActionSource) { source = src.rawValue }

    func perform() async throws -> some IntentResult {
        let src = ActionSource(rawValue: source) ?? .shortcut
        _ = await IntentBridge.run(.bath, source: src)
        return .result()
    }
}

struct WakeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Разбудить Шибу"

    @Parameter(title: "Откуда", default: "shortcut")
    var source: String

    init() {}
    init(_ src: ActionSource) { source = src.rawValue }

    func perform() async throws -> some IntentResult {
        let src = ActionSource(rawValue: source) ?? .shortcut
        _ = await IntentBridge.run(.wake, source: src)
        return .result()
    }
}

/// Большая кнопка в острове и виджете: одно самое нужное действие.
struct MainActionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Помочь Шибе"

    @Parameter(title: "Откуда", default: "shortcut")
    var source: String

    init() {}
    init(_ src: ActionSource) { source = src.rawValue }

    func perform() async throws -> some IntentResult {
        let src = ActionSource(rawValue: source) ?? .shortcut
        _ = await IntentBridge.runMain(source: src)
        return .result()
    }
}

/// Игра открывает приложение: играть с питомцем лучше на экране, а не вслепую.
struct PlayIntent: AppIntent {
    static let title: LocalizedStringResource = "Поиграть с Шибой"
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Откуда", default: "shortcut")
    var source: String

    init() {}
    init(_ src: ActionSource) { source = src.rawValue }

    func perform() async throws -> some IntentResult {
        let src = ActionSource(rawValue: source) ?? .shortcut
        _ = await IntentBridge.run(.play, source: src)
        return .result()
    }
}

/// Включить остров (Live Activity). Из Пункта управления и «Команд».
struct StartIslandIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Показать Шибу в острове"

    @Parameter(title: "Откуда", default: "shortcut")
    var source: String

    init() {}
    init(_ src: ActionSource) { source = src.rawValue }

    func perform() async throws -> some IntentResult {
        let src = ActionSource(rawValue: source) ?? .shortcut
        await IntentBridge.startIsland(source: src)
        return .result()
    }
}

/// «Как там Шиба?» — ответ голосом и текстом, без открытия приложения.
struct StatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Как там Шиба"

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = Presenter.statusText()
        return .result(dialog: "\(text)")
    }
}
