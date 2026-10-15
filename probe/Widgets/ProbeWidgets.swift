import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

@main
struct ProbeWidgetBundle: WidgetBundle {
    var body: some Widget {
        PetWidget()
        PetLiveActivity()
        PetControl()
    }
}

// MARK: - Виджет на рабочем столе

struct PetEntry: TimelineEntry {
    let date: Date
    let state: ProbeState
}

struct PetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PetEntry { PetEntry(date: .now, state: ProbeState()) }

    func getSnapshot(in context: Context, completion: @escaping (PetEntry) -> Void) {
        completion(PetEntry(date: .now, state: SharedStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PetEntry>) -> Void) {
        // Счётчик отрисовок показывает, как часто система реально будит виджет.
        let state = SharedStore.mutate {
            $0.widgetRenders += 1
            $0.widgetRenderedAt = .now
            $0.widgetGroupID = "\(AppGroup.resolved.id) (\(SharedStore.isShared ? "ok" : "нет"))"
        }
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [PetEntry(date: .now, state: state)], policy: .after(next)))
    }
}

struct PetWidgetView: View {
    let entry: PetEntry

    var body: some View {
        VStack(spacing: 6) {
            Text(PetFace.face(for: entry.state)).font(.system(size: 44))
            Text("🍖 \(entry.state.food)  💗 \(entry.state.pets)").font(.caption.bold())
            HStack {
                Button(intent: FeedIntent(source: "widget")) { Image(systemName: "fork.knife") }
                Button(intent: PetIntent(source: "widget")) { Image(systemName: "hand.raised") }
            }
            .buttonStyle(.bordered)
            Text("#\(entry.state.widgetRenders) · \(entry.date.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct PetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PetWidget", provider: PetProvider()) { PetWidgetView(entry: $0) }
            .configurationDisplayName("Зонд питомца")
            .description("Проверка App Group и кнопок")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Live Activity и Dynamic Island

struct PetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PetAttributes.self) { context in
            HStack {
                Text(context.state.mood).font(.largeTitle)
                VStack(alignment: .leading) {
                    Text(context.attributes.petName).font(.headline)
                    Text("🍖 \(context.state.food) · \(context.state.status)").font(.caption)
                }
                Spacer()
                Button(intent: IslandFeedIntent()) { Image(systemName: "fork.knife") }
                Button(intent: IslandPetIntent()) { Image(systemName: "hand.raised") }
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(context.state.mood).font(.largeTitle) }
                DynamicIslandExpandedRegion(.trailing) { Text("🍖 \(context.state.food)") }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Button(intent: IslandFeedIntent()) { Label("Покормить", systemImage: "fork.knife") }
                        Button(intent: IslandPetIntent()) { Label("Погладить", systemImage: "hand.raised") }
                    }
                }
            } compactLeading: {
                Text(context.state.mood)
            } compactTrailing: {
                Text("\(context.state.food)")
            } minimal: {
                Text(context.state.mood)
            }
        }
    }
}

// MARK: - Кнопка в Пункте управления (iOS 18+)

struct PetControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "PetControl") {
            ControlWidgetButton(action: FeedIntent(source: "control")) {
                Label("Покормить", systemImage: "fork.knife")
            }
        }
        .displayName("Покормить питомца")
    }
}
