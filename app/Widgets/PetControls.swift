// Пункт управления (iOS 18+): включить остров и покормить, не открывая приложение.

import AppIntents
import SwiftUI
import WidgetKit

struct PetIslandControl: ControlWidget {
    static let kind = "pet.control.island"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartIslandIntent(.control)) {
                Label("Шиба в острове", systemImage: "pawprint.fill")
            }
        }
        .displayName("Шиба в острове")
        .description("Показать Шибу в Dynamic Island.")
    }
}

struct PetFeedControl: ControlWidget {
    static let kind = "pet.control.feed"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: FeedIntent(.control)) {
                Label("Покормить Шибу", systemImage: "fork.knife")
            }
        }
        .displayName("Покормить Шибу")
        .description("Одна миска корма.")
    }
}
