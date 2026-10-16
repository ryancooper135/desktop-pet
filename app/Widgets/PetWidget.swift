// Виджет «Шиба»: домашний экран (small, medium, large) и экран блокировки (circular, rectangular, inline).
// Timeline на 24 ч вперёд: картинка в каждой точке посчитана ядром заранее, приложение не нужно.
// Точки — ForecastTools.timelineDates (каждые 30 минут, события прогноза, ночь, конец ванны и реакции).

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

    /// Сам расчёт отдельно: его же зовут тесты и отладочный экран.
    static func timeline(now: Double, file: SaveFile = PetStore.load()) -> Timeline<PetEntry> {
        let events = ForecastTools.upcoming(file, at: now, horizonH: 24)
        let dates = ForecastTools.timelineDates(file, now: now, events: events)
        // Двигаем копию стейта по точкам по порядку: каждый шаг — только от прошлой точки.
        var cur = file
        var entries: [PetEntry] = []
        for t in dates {
            cur.pet = PetRunner.peek(cur, at: t)
            let snap = Presenter.make(file: cur, pet: cur.pet, owner: PetRunner.owner(cur, at: t), at: t,
                                      upcoming: events.filter { $0.t >= t })
            entries.append(PetEntry(date: Date(timeIntervalSince1970: t - Clock.offset), snap: snap,
                                    relevance: relevance(snap)))
        }
        if entries.isEmpty {
            let snap = Presenter.make(file, at: now, upcoming: events)
            entries = [PetEntry(date: Date(timeIntervalSince1970: now - Clock.offset), snap: snap, relevance: relevance(snap))]
        }
        // Через 12 ч попросим новый timeline; приложение и интенты перезагружают его раньше.
        let next = Date(timeIntervalSince1970: now - Clock.offset + 12 * 3600)
        return Timeline(entries: entries, policy: .after(next))
    }

    /// Smart Stack поднимает виджет, когда питомцу плохо.
    static func relevance(_ s: PetSnapshot) -> TimelineEntryRelevance? {
        guard s.alive else { return TimelineEntryRelevance(score: 0) }
        let score: Float
        switch s.level {
        case 0: score = s.want == nil ? 0.1 : 0.3
        case 1: score = 0.5
        case 2: score = 0.8
        default: score = 1
        }
        return TimelineEntryRelevance(score: score, duration: 1800)
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
