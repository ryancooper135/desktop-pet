// Мелкие общие куски: сердечки, пузырь мысли, таймер, шкала, главная кнопка.
// Работают и в приложении, и в виджетах (без RealityKit и без состояния).

import SwiftUI
import UIKit
import WidgetKit
@preconcurrency import PetCore

/// Прямоугольник на долю ширины слева: для половинок сердечек.
struct LeadingFraction: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width * CGFloat(min(1, max(0, fraction))), height: rect.height))
    }
}

/// «Сейчас» для снимков: каталог превью ставит время фикстуры, и таймеры рисуются
/// статичным текстом из Presenter, а не тикают от настоящих часов. В приложении и виджетах — nil.
private struct PetFrozenNowKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    var petFrozenNow: Double? {
        get { self[PetFrozenNowKey.self] }
        set { self[PetFrozenNowKey.self] = newValue }
    }

    /// Снимок живого отсчёта: таймер рисуется как в виджете («через 40:00»), но стоит на этом моменте.
    /// Нужен, чтобы глазами проверить, влезает ли приставка рядом с отсчётом. В приложении — nil.
    var petPausedNow: Double? {
        get { self[PetPausedNowKey.self] }
        set { self[PetPausedNowKey.self] = newValue }
    }
}

private struct PetPausedNowKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

struct HeartsView: View {
    var hearts: Double
    var max: Double
    var size: CGFloat = 14
    var mono = false
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let count = Swift.max(1, Int(max.rounded()))
        let tinted = mono || renderingMode != .fullColor
        HStack(spacing: size * 0.2) {
            ForEach(0..<count, id: \.self) { i in
                // Половинки: дробь округляем до 0.5, как в макетах.
                let fill = Swift.min(1, Swift.max(0, ((hearts - Double(i)) * 2).rounded(.down) / 2))
                ZStack {
                    // Пустое сердечко: лёгкая заливка + контур, чтобы читалось и на чёрном острове, и на светлом.
                    Image(systemName: "heart.fill")
                        .foregroundStyle(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.2)) : AnyShapeStyle(PetPalette.soft.opacity(0.18)))
                    Image(systemName: "heart")
                        .foregroundStyle(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.6)) : AnyShapeStyle(PetPalette.soft.opacity(0.6)))
                    Image(systemName: "heart.fill")
                        .foregroundStyle(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(PetPalette.red))
                        .clipShape(LeadingFraction(fraction: fill))
                        .widgetAccentable()
                }
                .font(.system(size: size))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Сердечки: \(Presenter.heartsSpoken(hearts, of: max))"))
    }
}

/// Пузырь мысли над питомцем: иконка SF Symbols и короткий текст.
struct ThoughtBubble: View {
    var icon: String
    var text: String?
    var urgent = false
    var compact = false
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        // В тонированных режимах (accented/vibrant) сплошная карточка становится пятном — берём полупрозрачную.
        let tinted = renderingMode != .fullColor
        HStack(spacing: 4) {
            Self.symbol(icon)
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .foregroundStyle(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(urgent ? PetPalette.red : PetPalette.accent))
                .widgetAccentable()
            if let text, !compact {
                Text(text)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(PetPalette.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, compact ? 6 : 9)
        .padding(.vertical, compact ? 4 : 5)
        .background(Capsule().fill(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.12)) : AnyShapeStyle(PetPalette.card)))
        .overlay(Capsule().stroke(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(urgent ? 0.6 : 0.25))
                                         : AnyShapeStyle(urgent ? PetPalette.red.opacity(0.6) : PetPalette.soft.opacity(0.25)), lineWidth: 1))
        // VoiceOver (волна 15): один элемент «Хочет: …», значок не читается своим именем символа.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text.map { "Хочет: \($0)" } ?? (urgent ? "Срочно что-то нужно" : "Что-то хочет")))
    }

    /// Неизвестное имя символа даёт пустую картинку — проверяем и подставляем лапку.
    static func symbol(_ name: String) -> Image {
        UIImage(systemName: name) != nil ? Image(systemName: name) : Image(systemName: "pawprint.fill")
    }
}

/// Сколько осталось: ванна, дрёма, «проголодается через…». Сам тикает в виджетах и острове.
/// Больше часа — «через 9 ч 25 мин» (не путается со временем на часах), меньше — живой отсчёт «25:13».
struct NeedTimerView: View {
    var timer: NeedTimer
    var showTitle = true
    var mono = false
    /// Момент, от которого считать остаток (время снимка или состояния). nil — timer.start.
    var now: Double? = nil
    /// Заголовок вместо timer.title (у острова title пустой — его даёт Presenter.timerTitle).
    var title: String? = nil
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.petFrozenNow) private var frozenNow
    @Environment(\.petPausedNow) private var pausedNow

    var body: some View {
        let start = Date(timeIntervalSince1970: Swift.min(timer.start, timer.end))
        let end = Date(timeIntervalSince1970: timer.end)
        let remaining = timer.end - (frozenNow ?? pausedNow ?? now ?? timer.start)
        let name = showTitle ? (title ?? timer.title) : ""
        let prefix = Presenter.timerPrefix(kind: timer.kind)
        let tinted = mono || renderingMode != .fullColor
        HStack(spacing: 4) {
            // Иконка — украшение: VoiceOver читает фразу, а не «Часы».
            Image(systemName: Self.icon(timer.kind))
                .accessibilityHidden(true)
            if frozenNow != nil {
                Text(Presenter.timerPhrase(kind: timer.kind, title: name, remaining: remaining))
            } else if Presenter.timerIsLive(remaining: remaining) {
                // Те же слова, что у снимка и длинного таймера: «Затоскует через 49:12», «ещё 4:12».
                // Отсчёт жадный и забирает всю ширину — слова получают место первыми, иначе их режет.
                Text(name.isEmpty ? prefix : "\(name) \(prefix)")
                    .layoutPriority(1)
                Text(timerInterval: start...end,
                     pauseTime: pausedNow.map { Date(timeIntervalSince1970: $0) },
                     countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.leading)
            } else if name.isEmpty {
                Text("\(prefix) \(Text(end, style: .relative))")
            } else {
                Text("\(name) \(prefix) \(Text(end, style: .relative))")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(PetPalette.soft))
        .accessibilityElement(children: .combine)
    }

    static func icon(_ kind: String) -> String {
        switch kind {
        case "bath": return "drop.fill"
        case "nap": return "moon.zzz.fill"
        case "walk": return "figure.walk"
        default: return "clock"
        }
    }
}

/// Шкала нужды: иконка, имя, полоса. Пустая шкала (0) подсвечена красным.
struct NeedBar: View {
    var need: Need
    var value: Double
    var showName = true
    /// Волна 31: растёт с крупным шрифтом (лист шкал), не больше A11y.fontCap. Виджет — нет (по умолчанию false).
    var grows = false
    @ScaledMetric(relativeTo: .caption) private var scaled: CGFloat = 12

    var body: some View {
        let empty = Presenter.needEmpty(value)
        // k = 1 на обычном размере и в виджете — вёрстка ровно прежняя.
        let k = grows ? CGFloat(A11y.scaled(base: 12, scaled: Double(scaled)) / 12) : 1
        HStack(spacing: 6) {
            Image(systemName: PetPalette.needIcon(need))
                .font(.system(size: 12 * k, weight: .semibold))
                .foregroundStyle(empty ? PetPalette.red : PetPalette.need(need))
                .frame(width: 16 * k)
            if showName {
                Text(Catalog.needName(need))
                    .font(.system(size: 12 * k, weight: empty ? .bold : .medium, design: .rounded))
                    .foregroundStyle(empty ? PetPalette.red : PetPalette.ink)
                    .frame(width: 70 * k, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            NeedTrack(need: need, value: value)
                .frame(height: 7)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(Catalog.needName(need)): \(Int(value.rounded())) из 100"))
    }
}

/// Сама полоса шкалы: на нуле — красная подложка с красным контуром (статично, без анимации).
struct NeedTrack: View {
    var need: Need
    var value: Double

    var body: some View {
        let empty = Presenter.needEmpty(value)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(empty ? PetPalette.red.opacity(0.22) : PetPalette.soft.opacity(0.18))
                Capsule().fill(PetPalette.need(need))
                    .frame(width: geo.size.width * CGFloat(Swift.min(1, Swift.max(0, value / 100))))
            }
            .overlay(Capsule().stroke(PetPalette.red.opacity(empty ? 0.75 : 0), lineWidth: 1))
        }
    }
}

/// Узкая полоска шкал без подписей (средний виджет): иконка и короткая полоса на каждую.
struct NeedsStrip: View {
    var needs: [Need: Double]
    var list: [Need] = VisibleNeeds.short

    var body: some View {
        HStack(spacing: 8) {
            ForEach(list, id: \.self) { n in
                let v = needs[n] ?? 0
                HStack(spacing: 3) {
                    Image(systemName: PetPalette.needIcon(n))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Presenter.needEmpty(v) ? PetPalette.red : PetPalette.need(n))
                    NeedTrack(need: n, value: v)
                        .frame(height: 5)
                }
                .accessibilityElement()
                .accessibilityLabel(Text("\(Catalog.needName(n)): \(Int(v.rounded())) из 100"))
            }
        }
    }
}

/// Шкалы, которые видит игрок (look — внутренняя, её не показываем).
enum VisibleNeeds {
    static let all: [Need] = [.food, .clean, .energy, .fun, .love, .walk]
    static let short: [Need] = [.food, .clean, .fun, .love]
}

/// Вид главной кнопки (сама кнопка — с интентом или замыканием — снаружи).
/// critical: красная «Спасти» с иконкой нужного действия — критичное не путается с «просто голоден».
struct MainActLabel: View {
    var main: MainAct
    var compact = false
    var critical = false
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let rescue = critical && main != .none
        let tinted = renderingMode != .fullColor
        let fill: Color = rescue ? PetPalette.red : (main == .none ? PetPalette.soft : PetPalette.accent)
        HStack(spacing: 5) {
            Image(systemName: main.icon)
            if !compact { Text(rescue ? Presenter.rescueTitle : main.title).lineLimit(1).minimumScaleFactor(0.8) }
        }
        .font(.system(size: compact ? 13 : 14, weight: .bold, design: .rounded))
        .foregroundStyle(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(Color.white))
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 6 : 8)
        // Тонированные режимы: сплошная заливка становится плашкой без текста — даём прозрачную.
        .background(Capsule().fill(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(rescue ? 0.3 : 0.18)) : AnyShapeStyle(fill)))
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(rescue ? "\(Presenter.rescueTitle): \(main.title)" : main.title))
    }
}

/// Маленькая круглая кнопка действия в виджете.
struct ActChip: View {
    var icon: String
    var tint: Color
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let tinted = renderingMode != .fullColor
        Image(systemName: icon)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(tint))
            .frame(width: 34, height: 34)
            .background(Circle().fill(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.16)) : AnyShapeStyle(tint.opacity(0.16))))
            .widgetAccentable()
    }
}
