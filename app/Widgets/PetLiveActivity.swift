// Live Activity: остров и экран блокировки. Запускает и обновляет приложение (App/LiveActivityController),
// кнопки — LiveActivityIntent, они выполняются в процессе приложения и сразу обновляют остров.
// Реакция на действие кончается по staleDate: тогда context.isStale и вьюхи берут calmPose/calmLine.

import ActivityKit
import SwiftUI
import WidgetKit

struct PetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PetAttributes.self) { context in
            // Устаревшее из-за конца реакции не гасим: это обычная смена мордочки.
            LockScreenActivityView(name: context.attributes.name, state: context.state, stale: context.isStale)
                // Прогулка: устаревание = возвращение, вьюха сама покажет «Дома» — не глушим.
                .opacity(context.isStale && context.state.reactUntil == nil && context.state.backAt == nil ? 0.6 : 1)
                .activityBackgroundTint(PetPalette.card)
                .activitySystemActionForegroundColor(PetPalette.ink)
                .widgetURL(URL(string: "pet://home"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandExpandedLeading(state: context.state, stale: context.isStale)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandExpandedTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    IslandExpandedCenter(state: context.state, stale: context.isStale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(state: context.state, stale: context.isStale)
                }
            } compactLeading: {
                IslandCompactLeading(state: context.state, stale: context.isStale)
            } compactTrailing: {
                IslandCompactTrailing(state: context.state, stale: context.isStale)
            } minimal: {
                IslandMinimal(state: context.state, stale: context.isStale)
            }
            .widgetURL(URL(string: "pet://home"))
            .keylineTint(PetPalette.accent)
        }
    }
}
