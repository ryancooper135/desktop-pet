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
            case .active: model.becameActive()
            case .background: model.wentBackground()
            default: break
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

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
    }
}
