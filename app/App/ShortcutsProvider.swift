// «Команды» и Siri: готовые действия без настройки. В каждой фразе обязано быть имя приложения.
// Интенты — из Shared/Intents.swift; источник по умолчанию у них shortcut.

import AppIntents

struct PetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FeedIntent(),
                    phrases: ["Покормить Шибу в \(.applicationName)", "Покорми питомца в \(.applicationName)"],
                    shortTitle: "Покормить", systemImageName: "fork.knife")
        AppShortcut(intent: PetIntent(),
                    phrases: ["Погладить Шибу в \(.applicationName)", "Погладь питомца в \(.applicationName)"],
                    shortTitle: "Погладить", systemImageName: "hand.raised")
        AppShortcut(intent: PlayIntent(),
                    phrases: ["Поиграть с Шибой в \(.applicationName)"],
                    shortTitle: "Поиграть", systemImageName: "tennisball")
        AppShortcut(intent: StatusIntent(),
                    phrases: ["Как там Шиба в \(.applicationName)", "Как дела у питомца в \(.applicationName)"],
                    shortTitle: "Как он там", systemImageName: "pawprint")
        AppShortcut(intent: StartIslandIntent(),
                    phrases: ["Шиба на острове \(.applicationName)", "Покажи питомца в \(.applicationName)"],
                    shortTitle: "В остров", systemImageName: "capsule")
    }
}
