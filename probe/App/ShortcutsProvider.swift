import AppIntents

/// Действия, которые сразу видны в «Командах» без настройки.
struct ProbeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ShortcutFeedIntent(), phrases: ["Покормить в \(.applicationName)"],
                    shortTitle: "Покормить", systemImageName: "fork.knife")
    }
}

/// Отдельный интент для автоматизаций: пишет в журнал, чтобы было видно, что сработало без нас.
struct ShortcutFeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Покормить питомца (автоматизация)"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        SharedStore.mutate {
            $0.food += 1
            $0.lastAction = "feed"
            $0.lastActionBy = "shortcuts"
            $0.lastActionAt = .now
            $0.shortcutEvents.append("\(Date.now.formatted(date: .abbreviated, time: .standard)) feed")
        }
        await PetActivityController.updateAll()
        return .result()
    }
}
