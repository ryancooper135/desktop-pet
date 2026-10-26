// Live Activity: остров и экран блокировки. Запускает и обновляет приложение (App/LiveActivityController),
// кнопки — LiveActivityIntent, они выполняются в процессе приложения и сразу обновляют остров.
// Волна 34 J: есть карточка события (state.card) — рисуем её; после staleDate (context.isStale) — следующую
// (state.next). Старое состояние без карточек — прежний вид: реакция кончается по staleDate, calmPose/calmLine.

import ActivityKit
import SwiftUI
import WidgetKit

struct PetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PetAttributes.self) { context in
            Group {
                if let card = IslandLook.shown(context.state.card, next: context.state.next, stale: context.isStale) {
                    LockScreenCardView(name: context.attributes.name, card: card)
                } else {
                    // Устаревшее из-за конца реакции не гасим: это обычная смена мордочки.
                    LockScreenActivityView(name: context.attributes.name, state: context.state, stale: context.isStale)
                        // Прогулка: устаревание = возвращение, вьюха сама покажет «Дома» — не глушим.
                        .opacity(context.isStale && context.state.reactUntil == nil && context.state.backAt == nil ? 0.6 : 1)
                }
            }
            .activityBackgroundTint(PetPalette.card)
            .activitySystemActionForegroundColor(PetPalette.ink)
            .widgetURL(URL(string: "pet://home"))
        } dynamicIsland: { context in
            let card = IslandLook.shown(context.state.card, next: context.state.next, stale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let card {
                        IslandCardExpandedLeading(card: card)
                    } else {
                        IslandExpandedLeading(state: context.state, stale: context.isStale)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let card {
                        IslandCardExpandedTrailing(card: card)
                    } else {
                        IslandExpandedTrailing(state: context.state)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if let card {
                        IslandCardExpandedCenter(card: card)
                    } else {
                        IslandExpandedCenter(state: context.state, stale: context.isStale)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let card {
                        IslandCardExpandedBottom(card: card)
                    } else {
                        IslandExpandedBottom(state: context.state, stale: context.isStale)
                    }
                }
            } compactLeading: {
                if let card {
                    IslandCardCompactLeading(card: card)
                } else {
                    IslandCompactLeading(state: context.state, stale: context.isStale)
                }
            } compactTrailing: {
                if let card {
                    IslandCardCompactTrailing(card: card)
                } else {
                    IslandCompactTrailing(state: context.state, stale: context.isStale)
                }
            } minimal: {
                if let card {
                    IslandCardMinimal(card: card)
                } else {
                    IslandMinimal(state: context.state, stale: context.isStale)
                }
            }
            .widgetURL(URL(string: "pet://home"))
            .keylineTint(PetPalette.accent)
        }
    }
}
