import SwiftUI
import ActivityKit
import CoreMotion
import UserNotifications
import WidgetKit

@main
struct PetProbeApp: App {
    var body: some Scene {
        WindowGroup { ProbeView() }
    }
}

/// Запуск и обновление Live Activity без пушей: только из процесса приложения
/// (в том числе когда его будит LiveActivityIntent).
enum PetActivityController {
    static func contentState() -> PetAttributes.ContentState {
        let state = SharedStore.load()
        return .init(mood: PetFace.face(for: state), food: state.food,
                     status: PetFace.status(for: state), updatedAt: .now)
    }

    static func start() throws {
        let content = ActivityContent(state: contentState(), staleDate: Date().addingTimeInterval(8 * 3600))
        _ = try Activity.request(attributes: PetAttributes(petName: "Зонд"), content: content, pushType: nil)
    }

    static func updateAll() async {
        let content = ActivityContent(state: contentState(), staleDate: Date().addingTimeInterval(8 * 3600))
        for activity in Activity<PetAttributes>.activities {
            await activity.update(content)
        }
    }

    static func endAll() async {
        for activity in Activity<PetAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

struct ProbeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var state = SharedStore.load()
    @State private var log: [String] = []
    @State private var steps: String = "—"
    private let pedometer = CMPedometer()

    var body: some View {
        NavigationStack {
            List {
                Section("Питомец") {
                    HStack {
                        Text(PetFace.face(for: state)).font(.system(size: 56))
                        VStack(alignment: .leading) {
                            Text("Еда: \(state.food) · Ласка: \(state.pets)")
                            Text(PetFace.status(for: state)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button("Покормить") { act { $0.food += 1; $0.lastAction = "feed" } }
                    Button("Погладить") { act { $0.pets += 1; $0.lastAction = "pet" } }
                    Button("Обнулить еду") { act { $0.food = 0; $0.lastAction = "—" } }
                }

                Section("1. App Group") {
                    ForEach(SharedStore.diagnostics(), id: \.0) { row in
                        VStack(alignment: .leading) {
                            Text(row.0).font(.caption).foregroundStyle(.secondary)
                            Text(row.1).font(.footnote.monospaced()).textSelection(.enabled)
                        }
                    }
                    Text(SharedStore.isShared ? "✅ общая папка есть" : "❌ общей папки нет")
                }

                Section("2. Виджет") {
                    Text("Отрисовок виджета: \(state.widgetRenders)")
                    Text("Последняя: \(state.widgetRenderedAt.map(Self.time) ?? "ещё не было")")
                    Text("Виджет видит группу: \(state.widgetGroupID ?? "—")").font(.footnote)
                    Button("Перерисовать виджеты") { WidgetCenter.shared.reloadAllTimelines(); note("reloadAllTimelines") }
                }

                Section("3. Live Activity / остров") {
                    Text("Разрешены: \(ActivityAuthorizationInfo().areActivitiesEnabled ? "да" : "нет")")
                    Button("Запустить") {
                        do { try PetActivityController.start(); note("LA запущена") }
                        catch { note("LA ошибка: \(error.localizedDescription)") }
                    }
                    Button("Обновить") { Task { await PetActivityController.updateAll(); note("LA обновлена") } }
                    Button("Завершить") { Task { await PetActivityController.endAll(); note("LA завершена") } }
                }

                Section("4. Шаги") {
                    Text("За сегодня: \(steps)")
                    Button("Запросить шаги") { loadSteps() }
                }

                Section("5. Уведомления") {
                    Button("Разрешить уведомления") {
                        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, err in
                            note("уведомления: \(ok ? "да" : "нет") \(err?.localizedDescription ?? "")")
                        }
                    }
                    Button("Уведомление через 10 сек") { scheduleNotification() }
                }

                Section("6. «Команды»") {
                    Text("Открой «Команды» → Автоматизация → например «Зарядное устройство подключено» → действие «Покормить питомца» (Зонд). Потом проверь, что еда выросла и источник — shortcuts.")
                        .font(.footnote)
                    ForEach(state.shortcutEvents.suffix(5), id: \.self) { Text($0).font(.caption.monospaced()) }
                }

                Section("Журнал") {
                    ForEach(log.reversed(), id: \.self) { Text($0).font(.caption.monospaced()) }
                }
            }
            .navigationTitle("Зонд питомца")
            .refreshable { state = SharedStore.load() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { state = SharedStore.load() }
        }
    }

    private func act(_ change: @escaping (inout ProbeState) -> Void) {
        state = SharedStore.mutate {
            change(&$0)
            $0.lastActionBy = "app"
            $0.lastActionAt = .now
        }
        WidgetCenter.shared.reloadAllTimelines()
        Task { await PetActivityController.updateAll() }
    }

    private func note(_ text: String) {
        DispatchQueue.main.async { log.append("\(Self.time(.now)) \(text)") }
    }

    private func loadSteps() {
        guard CMPedometer.isStepCountingAvailable() else { steps = "недоступно"; return }
        let start = Calendar.current.startOfDay(for: .now)
        pedometer.queryPedometerData(from: start, to: .now) { data, error in
            DispatchQueue.main.async {
                if let data { steps = "\(data.numberOfSteps)" }
                else { steps = "ошибка: \(error?.localizedDescription ?? "?")" }
            }
        }
    }

    private func scheduleNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Зонд проголодался"
        content.body = "Локальное уведомление без сервера работает 🐶"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)) { err in
            note(err == nil ? "уведомление запланировано" : "ошибка: \(err!.localizedDescription)")
        }
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }
}
