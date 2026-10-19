// Экран «Привычки» (волна 11): готовые действия для «Команд» и как поставить их на автомат.
// Строка на привычку: значок, название, фраза Siri («Питомец, я дома»), чем запускать в «Автоматизации»,
// награда из economy.json и отметка «Сегодня ✓» / «Сегодня 3 из 8» / «Было 5 раз» / «Ещё не было».
// Ниже — шаги «Команды» → «Автоматизация» → «+» и кнопка «Открыть «Команды»» (shortcuts://).
// Логика и тексты — Habits (Shared), тут только вид. Открывается из настроек и по pet://habits.
// Решения (Вадим может поменять): кнопки «отметить» тут нет — привычку отмечает автоматизация или Siri,
// иначе это была бы ещё одна кнопка «дай монет»; ответ пса виден в комнате, а не под листом.

import SwiftUI
@preconcurrency import PetCore

struct HabitsScreen: View {
    @Environment(AppModel.self) private var model

    /// Как приложение зовут на экране и в Siri (CFBundleDisplayName): «Питомец».
    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Питомец"
    }

    /// Шаги «Автоматизации» одинаковы для всех привычек — отличается только первый пункт (триггер, в строке).
    static let steps = [
        "Открой «Команды» → вкладка «Автоматизация» → «+».",
        "Выбери, когда запускать: «Время суток», «Будильник», «Прибытие» (дом) или «NFC» (метка на двери, бутылке).",
        "«Новая пустая автоматизация» → «Добавить действие» → найди «\(appName)» и выбери привычку.",
        "Включи «Запускать сразу» — тогда спрашивать каждый раз не будет.",
    ]

    var body: some View {
        let now = Clock.now()
        Form {
            Section {
                ForEach(Habit.allCases, id: \.self) { h in
                    HabitRow(habit: h, status: model.file.map { Habits.statusText($0, h, now: now) } ?? "",
                             doneToday: model.file.map { Habits.countToday($0, h, now: now) > 0 } ?? false)
                        .listRowBackground(PetPalette.card)
                }
            } header: {
                Text("Готовые действия")
            } footer: {
                Text(footer(now: now))
            }

            Section {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i + 1)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(PetPalette.accent))
                        Text(s)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(PetPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(PetPalette.card)
                }
                if let url = URL(string: "shortcuts://") {
                    Link(destination: url) {
                        Label("Открыть «Команды»", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .listRowBackground(PetPalette.card)
                    .accessibilityIdentifier("habits.openShortcuts")
                }
            } header: {
                Text("Как поставить на автомат")
            } footer: {
                Text("Без автоматизации тоже можно: скажи Siri «\(Self.appName), \(Habit.water.siri)» или добавь действие на экран «Домой».")
            }
        }
        .scrollContentBackground(.hidden)
        .background(PetPalette.bg.ignoresSafeArea())
        .tint(PetPalette.accent)
        .toolbarBackground(PetPalette.bg, for: .navigationBar)
        .navigationTitle("Привычки")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("habits.screen")
    }

    /// Сколько ещё монет можно получить сегодня: потолок общий с шагами.
    private func footer(now: Double) -> String {
        let name = model.snap.name
        guard let f = model.file else { return "\(name) отвечает на каждую отметку." }
        let left = Habits.coinsLeft(f, now: now)
        let money = left > 0 ? "За привычки и шаги сегодня ещё можно получить \(EconText.coins(left))."
                             : "Монет за привычки и шаги на сегодня хватит — \(name) всё равно ответит."
        return "\(name) отвечает на каждую отметку. \(money)"
    }
}

/// Одна привычка: значок, название и фраза Siri, чем запускать, награда и отметка справа.
private struct HabitRow: View {
    let habit: Habit
    let status: String
    let doneToday: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: habit.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(doneToday ? .white : PetPalette.accent)
                .frame(width: 36, height: 36)
                .background(Circle().fill(doneToday ? PetPalette.green : PetPalette.accent.opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(habit.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                    Spacer(minLength: 6)
                    Text(status)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(doneToday ? PetPalette.green : PetPalette.soft)
                        .accessibilityIdentifier("habits.status.\(habit.rawValue)")
                }
                Text("«\(HabitsScreen.appName), \(habit.siri)»")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.ink.opacity(0.8))
                Text(habit.trigger)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Habits.rewardText(habit))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(PetPalette.furDark)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("habits.row.\(habit.rawValue)")
    }
}

/// Лист по pet://habits: тот же экран со своей шапкой и «Закрыть» (из настроек он открывается внутри их стека).
struct HabitsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HabitsScreen()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Закрыть") { dismiss() }
                    }
                }
        }
    }
}
