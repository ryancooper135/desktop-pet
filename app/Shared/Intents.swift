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
        ControlCenter.shared.reloadAllControls()
        return out
        #endif
    }

    /// Главное действие: то, что сейчас на большой кнопке (rescue → разбудить → погладить).
    @MainActor
    static func runMain(source: ActionSource) async -> ActOutcome {
        let snap = Presenter.current()
        guard let a = snap.main.action else {
            return ActOutcome(ok: false, reason: !snap.alive ? "dead" : (snap.pose == .away ? "away" : "bathing"))
        }
        return await run(a, source: source)
    }

    /// Волна 57: команда голосом («Шиба, сидеть»). Интент открывает приложение; пёс выполняет, когда комната
    /// уже на экране (пауза на запуск/переход), исход — как с листа «Команды» (Tricks.attempt).
    @MainActor
    static func trick(_ t: Trick) async {
        #if APP_TARGET
        try? await Task.sleep(for: .milliseconds(Tricks.siriDelayMs))
        AppModel.shared.doTrick(t)
        #endif
    }

    /// Волна 34 J: «Собрать» копилку двора без открытия приложения. Запись — через стор (замки AppGroup),
    /// опыт пса — по журналу yard.collect. Пустая копилка — ничего не меняется.
    @MainActor
    @discardableResult
    static func collectYard(source: ActionSource) async -> YardHarvest? {
        let now = Clock.now()
        let h = try? PetStore.shared.mutate { WidgetLook.collect(in: &$0, now: now) }
        #if APP_TARGET
        AppModel.shared.refresh()
        await AppActions.shared.afterChange()
        #else
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        #endif
        return h
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

/// Кнопки острова: ровно то действие, что было на кнопке (план острова, IslandPlan). В «Командах» не показываем.
struct IslandActIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Помочь Шибе из острова"
    static let isDiscoverable: Bool = false

    @Parameter(title: "Действие", default: "pet")
    var act: String

    @Parameter(title: "Откуда", default: "island")
    var source: String

    init() {}
    init(_ a: IslandAct, _ src: ActionSource) {
        act = a.rawValue
        source = src.rawValue
    }

    func perform() async throws -> some IntentResult {
        let src = ActionSource(rawValue: source) ?? .island
        if let a = IslandAct(rawValue: act)?.action {
            _ = await IntentBridge.run(a, source: src)
        }
        return .result()
    }
}

/// Волна 51: кнопка контрола «Шиба сейчас». Шаблон контрола не умеет if/else, поэтому один тип интента на оба
/// случая: действие доступно (`act` с действием ядра) — делаем его в фоне; нет (моется, спит, всё хорошо) —
/// просто открываем приложение (`continueInForeground`, iOS 26).
struct ShibaNowIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Шиба сейчас"
    static let isDiscoverable: Bool = false
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "Действие", default: "open")
    var act: String

    init() {}
    init(_ a: IslandAct) { act = a.rawValue }

    func perform() async throws -> some IntentResult {
        if let a = IslandAct(rawValue: act)?.action {
            _ = await IntentBridge.run(a, source: .control)
        } else {
            try await continueInForeground(alwaysConfirm: false)
        }
        return .result()
    }
}

/// Волна 34 J: кнопка «Собрать» в виджете — копилка двора в кошелёк, приложение не открывается.
/// В «Командах» не показываем: лимит App Shortcuts (10) занят, а без кнопки собирать вслепую незачем.
struct CollectIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Собрать копилку"
    static let isDiscoverable: Bool = false

    @Parameter(title: "Откуда", default: "widget")
    var source: String

    init() {}
    init(_ src: ActionSource) { source = src.rawValue }

    func perform() async throws -> some IntentResult {
        let src = ActionSource(rawValue: source) ?? .widget
        await IntentBridge.collectYard(source: src)
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
    static let title: LocalizedStringResource = "Показать Шибу на острове"

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

// MARK: - Команды голосом (волна 57)
// Вместо пяти привычек (волна 11) — две команды псу. Открывают приложение: трюк надо видеть.

/// «Шиба, сидеть».
struct SitIntent: AppIntent {
    static let title: LocalizedStringResource = "Шиба, сидеть"
    static let description = IntentDescription("Шиба садится по команде.")
    static let openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        await IntentBridge.trick(.sit)
        return .result()
    }
}

/// «Шиба, дай лапу».
struct PawIntent: AppIntent {
    static let title: LocalizedStringResource = "Шиба, дай лапу"
    static let description = IntentDescription("Шиба даёт лапу по команде.")
    static let openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        await IntentBridge.trick(.paw)
        return .result()
    }
}
