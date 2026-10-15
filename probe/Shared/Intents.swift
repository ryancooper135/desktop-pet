import AppIntents
import WidgetKit

/// Кнопка «покормить» в виджете, Пункте управления и «Командах».
struct FeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Покормить питомца"

    @Parameter(title: "Откуда")
    var source: String

    init() {}
    init(source: String) { self.source = source }

    func perform() async throws -> some IntentResult {
        let by = source
        SharedStore.mutate {
            $0.food += 1
            $0.lastAction = "feed"
            $0.lastActionBy = by
            $0.lastActionAt = .now
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct PetIntent: AppIntent {
    static let title: LocalizedStringResource = "Погладить питомца"

    @Parameter(title: "Откуда")
    var source: String

    init() {}
    init(source: String) { self.source = source }

    func perform() async throws -> some IntentResult {
        let by = source
        SharedStore.mutate {
            $0.pets += 1
            $0.lastAction = "pet"
            $0.lastActionBy = by
            $0.lastActionAt = .now
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Кнопки внутри Live Activity: LiveActivityIntent выполняется в процессе приложения,
/// поэтому там можно обновить саму активность без пушей.
struct IslandFeedIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Покормить из острова"

    init() {}

    func perform() async throws -> some IntentResult {
        SharedStore.mutate {
            $0.food += 1
            $0.lastAction = "feed"
            $0.lastActionBy = "island"
            $0.lastActionAt = .now
        }
        #if APP_TARGET
        await PetActivityController.updateAll()
        #endif
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct IslandPetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Погладить из острова"

    init() {}

    func perform() async throws -> some IntentResult {
        SharedStore.mutate {
            $0.pets += 1
            $0.lastAction = "pet"
            $0.lastActionBy = "island"
            $0.lastActionAt = .now
        }
        #if APP_TARGET
        await PetActivityController.updateAll()
        #endif
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
