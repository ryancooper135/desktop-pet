// Виджет «Шиба»: домашний экран (small, medium, large) и экран блокировки (circular, rectangular, inline).
// Timeline на 24 ч вперёд: картинка в каждой точке посчитана ядром заранее, приложение не нужно.
// Точки — ForecastTools.timeline: сетка 30 мин / 1 ч / ночью 2 ч, события прогноза и точные минуты смены позы.

import SwiftUI
import WidgetKit
@preconcurrency import PetCore

struct PetEntry: TimelineEntry {
    let date: Date
    let snap: PetSnapshot
    let relevance: TimelineEntryRelevance?
}

struct PetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PetEntry {
        let s = PreviewFixtures.snapshot("fed")
        return PetEntry(date: Date(), snap: s, relevance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PetEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let now = Clock.now()
        let snap = Presenter.make(PetStore.load(), at: now)
        completion(PetEntry(date: Date(), snap: snap, relevance: Self.relevance(snap)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PetEntry>) -> Void) {
        completion(Self.timeline(now: Clock.now()))
    }

    /// Сам расчёт — ForecastTools.timeline (в Shared, его зовут тесты). Здесь только даты и relevance.
    static func timeline(now: Double, file: SaveFile = PetStore.load()) -> Timeline<PetEntry> {
        let snaps = ForecastTools.timeline(file, now: now)
        var entries: [PetEntry] = []
        for (i, snap) in snaps.enumerated() {
            // Relevance держится до следующей точки: ночью точки реже.
            let next = i + 1 < snaps.count ? snaps[i + 1].t : snap.t + 1800
            entries.append(PetEntry(date: Date(timeIntervalSince1970: snap.t - Clock.offset), snap: snap,
                                    relevance: relevance(snap, duration: max(60, next - snap.t))))
        }
        if entries.isEmpty {
            let snap = Presenter.make(file, at: now)
            entries = [PetEntry(date: Date(timeIntervalSince1970: now - Clock.offset), snap: snap, relevance: relevance(snap))]
        }
        // Новый timeline — когда точки кончатся, но не позже 12 ч; приложение и интенты перезагружают его раньше.
        let next = Date(timeIntervalSince1970: ForecastTools.reloadT(snaps, now: now) - Clock.offset)
        return Timeline(entries: entries, policy: .after(next))
    }

    /// Smart Stack поднимает виджет, когда питомцу плохо.
    static func relevance(_ s: PetSnapshot, duration: Double = 1800) -> TimelineEntryRelevance? {
        guard s.alive else { return TimelineEntryRelevance(score: 0) }
        let score: Float
        switch s.level {
        case 0: score = s.want == nil ? 0.1 : 0.3
        case 1: score = 0.5
        case 2: score = 0.8
        default: score = 1
        }
        return TimelineEntryRelevance(score: score, duration: duration)
    }
}

struct PetWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PetEntry

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if isAccessory {
                    Color.clear
                } else {
                    PetPalette.card
                }
            }
            .widgetURL(URL(string: "pet://home"))
    }

    private var isAccessory: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
        default: return false
        }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .systemSmall: WidgetSmallView(snap: entry.snap)
        case .systemMedium: WidgetMediumView(snap: entry.snap)
        case .systemLarge: WidgetLargeView(snap: entry.snap)
        case .accessoryCircular: AccessoryCircularView(snap: entry.snap)
        case .accessoryRectangular: AccessoryRectangularView(snap: entry.snap)
        case .accessoryInline: AccessoryInlineView(snap: entry.snap)
        default: WidgetSmallView(snap: entry.snap)
        }
    }
}

struct PetWidget: Widget {
    static let kind = "pet.main"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: PetTimelineProvider()) { entry in
            PetWidgetView(entry: entry)
        }
        .configurationDisplayName("Шиба")
        .description("Как он там и что хочет. Покормить и погладить — прямо отсюда.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
