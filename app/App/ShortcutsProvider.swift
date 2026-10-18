// «Команды» и Siri: готовые действия без настройки. В каждой фразе обязано быть имя приложения.
// Интенты — из Shared/Intents.swift; источник по умолчанию у них shortcut.
// Apple пускает не больше 10 AppShortcut на приложение: 5 ухода + 5 привычек — ровно лимит.
// Значки и фразы — литералами: их читает сборщик метаданных App Intents, не код.
// Привычки (волна 11) удобнее всего ставить в «Командах» → «Автоматизация» (экран «Привычки» объясняет как).

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
        AppShortcut(intent: HabitHomeIntent(),
                    phrases: ["\(.applicationName), я дома", "Я пришёл домой в \(.applicationName)"],
                    shortTitle: "Я дома", systemImageName: "house.fill")
        AppShortcut(intent: HabitWakeIntent(),
                    phrases: ["\(.applicationName), я проснулся", "Доброе утро, \(.applicationName)"],
                    shortTitle: "Я проснулся", systemImageName: "sun.horizon.fill")
        AppShortcut(intent: HabitSleepIntent(),
                    phrases: ["\(.applicationName), я ложусь спать", "Спокойной ночи, \(.applicationName)"],
                    shortTitle: "Ложусь спать", systemImageName: "moon.zzz.fill")
        AppShortcut(intent: HabitWaterIntent(),
                    phrases: ["\(.applicationName), я выпил воды", "Выпил воды в \(.applicationName)"],
                    shortTitle: "Выпил воды", systemImageName: "drop.fill")
        AppShortcut(intent: HabitWorkoutIntent(),
                    phrases: ["\(.applicationName), я сделал зарядку", "Сделал зарядку в \(.applicationName)"],
                    shortTitle: "Зарядка", systemImageName: "figure.strengthtraining.functional")
    }
}
