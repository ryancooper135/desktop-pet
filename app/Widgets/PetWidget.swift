// Виджет «Шиба»: домашний экран (small, medium, large) и экран блокировки (circular, rectangular, inline).
// Волна 34 J: «экранчик» в пластиковой рамке. Timeline — WidgetLook.looks (Shared/IslandLook, сверху IslandEvents):
// 24 кадра — сейчас и дальше по :00/:30 на 12 ч; каждый кадр посчитан логикой заранее, приложение не нужно.
// Волна 45 O: в окне просьбы пса — ещё кадры раз в 5 мин (подпись «Почеши за ушком? · ещё N мин», как дома).
// Анимаций по секундам нет: живут только системные таймеры (поход на экране блокировки).
// Кнопка «Собрать» (CollectIntent) собирает копилку прямо отсюда и перезагружает timeline.

import SwiftUI
import WidgetKit
@preconcurrency import PetCore

struct PetEntry: TimelineEntry {
    let date: Date
    let look: WidgetLook
    let relevance: TimelineEntryRelevance?
}

struct PetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PetEntry {
        let look = PreviewFixtures.widgetLook("fed", bank: 0.6)
        return PetEntry(date: Date(), look: look, relevance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PetEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let now = Clock.now()
        let look = WidgetFallback.looks(PetStore.loadIfAny(), now: now).first ?? WidgetLook.empty(t: now)
        completion(PetEntry(date: Date(), look: look, relevance: TimelineEntryRelevance(score: look.relevance)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PetEntry>) -> Void) {
        completion(Self.timeline(now: Clock.now()))
    }

    /// Сам расчёт — WidgetLook.looks (в Shared, его зовут тесты). Здесь только даты и relevance.
    /// Сейва нет (первый запуск, общая папка не подключилась под чужой подписью) — кадр-заглушка (волна 59).
    static func timeline(now: Double, file: SaveFile? = PetStore.loadIfAny()) -> Timeline<PetEntry> {
        let looks = WidgetFallback.looks(file, now: now)
        var entries: [PetEntry] = []
        for (i, look) in looks.enumerated() {
            // Relevance держится до следующего кадра.
            let next = i + 1 < looks.count ? looks[i + 1].t : look.t + 1800
            entries.append(PetEntry(date: Date(timeIntervalSince1970: look.t - Clock.offset), look: look,
                                    relevance: TimelineEntryRelevance(score: look.relevance, duration: max(60, next - look.t))))
        }
        if entries.isEmpty {
            let look = WidgetLook.empty(t: now)
            entries = [PetEntry(date: Date(timeIntervalSince1970: now - Clock.offset), look: look, relevance: nil)]
        }
        // Новый timeline — когда кадры кончатся; приложение и интенты перезагружают его раньше.
        let next = Date(timeIntervalSince1970: WidgetLook.reloadT(looks, now: now) - Clock.offset)
        return Timeline(entries: entries, policy: .after(next))
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
                    WidgetPlastic()
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
        case .systemSmall: WidgetScreenSmallView(look: entry.look)
        case .systemMedium: WidgetScreenMediumView(look: entry.look)
        case .systemLarge: WidgetScreenLargeView(look: entry.look)
        case .accessoryCircular: WidgetLockCircularView(look: entry.look)
        case .accessoryRectangular: WidgetLockRectangularView(look: entry.look)
        case .accessoryInline: WidgetLockInlineView(look: entry.look)
        default: WidgetScreenSmallView(look: entry.look)
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
        .description("Как он там, что хочет и сколько в копилке. Собрать — прямо отсюда.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
