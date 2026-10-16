// Live Activity: остров и экран блокировки. Запускает и обновляет приложение (App/LiveActivityController),
// кнопки — LiveActivityIntent, они выполняются в процессе приложения и сразу обновляют остров.

import ActivityKit
import SwiftUI
import WidgetKit

struct PetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PetAttributes.self) { context in
            LockScreenActivityView(name: context.attributes.name, state: context.state)
                .opacity(context.isStale ? 0.6 : 1)
                .activityBackgroundTint(PetPalette.card)
                .activitySystemActionForegroundColor(PetPalette.ink)
                .widgetURL(URL(string: "pet://home"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandExpandedLeading(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandExpandedTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    IslandExpandedCenter(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(state: context.state)
                }
            } compactLeading: {
                IslandCompactLeading(state: context.state)
            } compactTrailing: {
                IslandCompactTrailing(state: context.state)
            } minimal: {
                IslandMinimal(state: context.state)
            }
            .widgetURL(URL(string: "pet://home"))
            .keylineTint(PetPalette.accent)
        }
    }
}
