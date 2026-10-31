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
                // Приложение только русское: «через 8 ч 26 мин», а не «8 hrs, 26 min» на английском телефоне.
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .onOpenURL { model.open($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.becameActive()
                GuideCenter.shared.becameActive()
                SoundKit.shared.becameActive()
                Feel.becameActive()
            case .background:
                model.wentBackground()
                GuideCenter.shared.wentBackground()
                SoundKit.shared.wentBackground()
                Feel.wentBackground()
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
        // Знакомство, подсказки «Правила» и «Виджет и остров» (GuideCenter): ждут, пока экран свободен.
        .sheet(item: $guide.sheet, onDismiss: { guide.dismissed() }) { kind in
            switch kind {
            case .intro: IntroScreen(onDone: { guide.close() }).environment(model)
            case .rules: RulesScreen(onDone: { guide.ackRules() }).environment(model)
            case .widget: WidgetGuideSheet(onDone: { guide.close() }).environment(model)
            }
        }
        .onChange(of: model.snap.level) { _, _ in guide.check() }
        .onChange(of: model.away == nil) { _, free in
            guard free else { return }
            guide.check()
            // «Доброе утро», отложенное под отчётом «Пока тебя не было».
            model.sayPending()
        }
        .onChange(of: model.anyCover) { _, busy in
            guard !busy else { return }
            guide.check()
            // Волна 35 N: сцена уровня/роста, отложенная под листом или отчётом «Пока тебя не было», — сразу, не через тикер 30 с.
            model.refresh()
        }
        .preferredColorScheme(UITestHooks.scheme)
        .task {
            // UI-тест просит сразу открыть шкалы или настройки — для скриншота без жестов.
            guard let url = UITestHooks.openURL else { return }
            try? await Task.sleep(for: .milliseconds(600))
            model.open(url)
            // Вторая ссылка поверх первого листа (как тап по виджету при открытом листе), ui-96-deeplink.
            guard let then = UITestHooks.thenURL else { return }
            try? await Task.sleep(for: .seconds(4))
            model.open(then)
        }
    }
}

/// Крючки только для UI-тестов (Env.isUITest); в обычном запуске всё nil.
/// PET_SCHEME=dark|light — тема интерфейса; PET_OPEN=needs|settings|album|capsule|house|tricks|catch|blockduo|brush|kitchen|characters|yard — открыть экран после запуска; PET_THEN — второй экран поверх через 4 с.
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
        guard Env.isUITest, let v = Env.value("PET_OPEN"), ["needs", "settings", "album", "capsule", "shop", "house", "tricks", "catch", "blockduo", "runner", "brush", "kitchen", "characters", "yard"].contains(v) else { return nil }
        return URL(string: "pet://\(v)")
    }

    /// PET_THEN=<экран> — через 4 с после PET_OPEN открыть второй (ссылка поверх открытого листа).
    static var thenURL: URL? {
        guard Env.isUITest, let v = Env.value("PET_THEN"), DeepLink.routes.contains(v) else { return nil }
        return URL(string: "pet://\(v)")
    }
}
