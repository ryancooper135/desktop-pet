// Точка входа. Модель одна на процесс (AppModel.shared): её же трогают интенты и уведомления.
// active → догнать время, показать «Пока тебя не было», остров и шаги; background → записать lastSeenT.

import SwiftUI
@preconcurrency import PetCore

@main
struct PetApp: App {
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { model.open($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.becameActive()
                GuideCenter.shared.becameActive()
            case .background:
                model.wentBackground()
                GuideCenter.shared.wentBackground()
            default: break
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var guide = GuideCenter.shared

    var body: some View {
        @Bindable var model = model
        Group {
            if let error = model.storeError {
                StoreErrorScreen(message: error)
            } else {
                HomeScreen()
            }
        }
        .fullScreenCover(item: $model.away) { report in
            AwayScreen(report: report)
                .environment(model)
        }
        // Подсказки «Правила» и «Виджет и остров» (GuideCenter): ждут, пока экран свободен.
        .sheet(item: $guide.sheet, onDismiss: { guide.check() }) { kind in
            switch kind {
            case .rules: RulesScreen(onDone: { guide.ackRules() }).environment(model)
            case .widget: WidgetGuideSheet(onDone: { guide.close() }).environment(model)
            }
        }
        .onChange(of: model.snap.level) { _, _ in guide.check() }
        .onChange(of: model.away == nil) { _, free in if free { guide.check() } }
        .onChange(of: model.showNeeds || model.showSettings) { _, busy in if !busy { guide.check() } }
        .preferredColorScheme(UITestHooks.scheme)
        .task {
            // UI-тест просит сразу открыть шкалы или настройки — для скриншота без жестов.
            guard let url = UITestHooks.openURL else { return }
            try? await Task.sleep(for: .milliseconds(600))
            model.open(url)
        }
    }
}

/// Крючки только для UI-тестов (Env.isUITest); в обычном запуске всё nil.
/// PET_SCHEME=dark|light — тема интерфейса; PET_OPEN=needs|settings — открыть экран после запуска.
enum UITestHooks {
    static var scheme: ColorScheme? {
        guard Env.isUITest else { return nil }
        switch Env.value("PET_SCHEME") {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    static var openURL: URL? {
        guard Env.isUITest, let v = Env.value("PET_OPEN"), ["needs", "settings"].contains(v) else { return nil }
        return URL(string: "pet://\(v)")
    }
}
