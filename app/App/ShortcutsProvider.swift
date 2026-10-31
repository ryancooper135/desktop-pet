// «Команды» и Siri: готовые действия без настройки. В каждой фразе обязано быть имя приложения.
// Интенты — из Shared/Intents.swift; источник по умолчанию у них shortcut.
// Apple пускает не больше 10 AppShortcut на приложение: 5 ухода + 2 команды псу (волна 57 вместо 5 привычек).
// Значки и фразы — литералами: их читает сборщик метаданных App Intents, не код.

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
        AppShortcut(intent: SitIntent(),
                    phrases: ["\(.applicationName), сидеть", "Шиба, сидеть в \(.applicationName)"],
                    shortTitle: "Сидеть", systemImageName: "dog.fill")
        AppShortcut(intent: PawIntent(),
                    phrases: ["\(.applicationName), дай лапу", "Шиба, дай лапу в \(.applicationName)"],
                    shortTitle: "Дай лапу", systemImageName: "pawprint.fill")
    }
}
