// Виджеты на домашнем экране: small, medium, large. Только вид по PetSnapshot и кнопки-интенты.
// Фон (containerBackground) и widgetURL ставит расширение в Widgets/, превью — PreviewCatalog.
// Режимы отрисовки: в accented/vibrant (тонированный домашний экран, StandBy ночью) цветные пятна
// сливаются в один тон, поэтому мордочка рисуется в mono, а мелочи берут HierarchicalShapeStyle.

import AppIntents
import SwiftUI
import WidgetKit
@preconcurrency import PetCore

struct WidgetSmallView: View {
    var snap: PetSnapshot
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let tinted = renderingMode != .fullColor
        VStack(spacing: 4) {
            // Верхний ряд: сердечки и мысль по центру одной линии и фиксированной высоты — не прыгает.
            HStack(alignment: .center, spacing: 4) {
                HeartsView(hearts: snap.hearts, max: snap.heartsMax, size: 10)
                Spacer(minLength: 0)
                if let icon = snap.wantIcon {
                    ThoughtBubble(icon: icon, text: nil, urgent: snap.urgent, compact: true)
                }
            }
            .frame(height: 22)
            PetFaceView(pose: snap.pose, mono: tinted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) { RareMark(frame: snap.rare) }
            // Короткая реплика в две строки вместо обрезанной длинной.
            Text(snap.shortLine)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(PetPalette.ink))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            if snap.sleeping && snap.main == .pet && !snap.critical {
                // Ночью не предлагаем «Погладить»: питомец спит.
                SleepPill()
            } else {
                WidgetMainButton(snap: snap, compact: false)
            }
        }
    }
}

struct WidgetMediumView: View {
    var snap: PetSnapshot
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let tinted = renderingMode != .fullColor
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                PetFaceView(pose: snap.pose, mono: tinted)
                RareMark(frame: snap.rare)
            }
            .frame(maxWidth: 136, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center) {
                    Text(snap.name)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(PetPalette.ink))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    HeartsView(hearts: snap.hearts, max: snap.heartsMax, size: 11)
                }
                Text(snap.line)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(PetPalette.ink))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let icon = snap.wantIcon {
                    ThoughtBubble(icon: icon, text: snap.wantText, urgent: snap.urgent)
                } else if let tm = snap.timer {
                    NeedTimerView(timer: tm, now: snap.t)
                }
                Spacer(minLength: 0)
                // Пустая полоса снизу теперь занята шкалами: видно, что на исходе.
                if snap.alive {
                    NeedsStrip(needs: snap.needs)
                }
                WidgetButtonsRow(snap: snap)
            }
        }
    }
}

/// Метка редкого кадра, пока у пасхалок нет своих поз и клипов.
struct RareMark: View {
    var frame: String?

    var body: some View {
        if frame != nil {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(PetPalette.yellow)
                .widgetAccentable()
                .accessibilityLabel("Редкий момент")
        }
    }
}

/// Большой виджет: крупная мордочка с репликой и статусом рядом, ниже все шкалы и кнопки.
struct WidgetLargeView: View {
    var snap: PetSnapshot
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let tinted = renderingMode != .fullColor
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    PetFaceView(pose: snap.pose, mono: tinted)
                    RareMark(frame: snap.rare)
                }
                .frame(width: 150, height: 150)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center) {
                        Text(snap.name)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(PetPalette.ink))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        HeartsView(hearts: snap.hearts, max: snap.heartsMax, size: 11)
                    }
                    Text(snap.line)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(PetPalette.ink))
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                    if let icon = snap.wantIcon {
                        ThoughtBubble(icon: icon, text: snap.wantText, urgent: snap.urgent)
                    }
                    if let tm = snap.timer {
                        NeedTimerView(timer: tm, now: snap.t)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 8) {
                ForEach(VisibleNeeds.all, id: \.self) { n in
                    NeedBar(need: n, value: snap.needs[n] ?? 0)
                }
            }
            Spacer(minLength: 0)
            WidgetButtonsRow(snap: snap)
        }
    }
}

/// «Спит»: вместо кнопок, когда питомец спит ночью. Тихая плашка, не кнопка.
struct SleepPill: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let tinted = renderingMode != .fullColor
        HStack(spacing: 5) {
            Image(systemName: "moon.zzz.fill")
            Text(Presenter.sleepTitle).lineLimit(1)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(PetPalette.soft))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.12)) : AnyShapeStyle(PetPalette.soft.opacity(0.15))))
        .accessibilityElement(children: .combine)
    }
}

/// Кнопки medium/large: погладить, покормить и главное действие, если оно другое.
/// Критично — одна красная «Спасти»; ночью — «Спит» без кнопок.
struct WidgetButtonsRow: View {
    var snap: PetSnapshot

    var body: some View {
        HStack(spacing: 8) {
            if snap.critical && snap.main != .none {
                WidgetMainButton(snap: snap, compact: false)
                Spacer(minLength: 0)
            } else if snap.sleeping && snap.main == .pet {
                SleepPill()
                Spacer(minLength: 0)
            } else if snap.alive && snap.main != .none {
                Button(intent: PetIntent(.widget)) { ActChip(icon: "hand.raised.fill", tint: PetPalette.need(.love)) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Погладить"))
                Button(intent: FeedIntent(.widget)) { ActChip(icon: "fork.knife", tint: PetPalette.need(.food)) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Покормить"))
                Spacer(minLength: 0)
                if snap.main != .pet && snap.main != .feed {
                    WidgetMainButton(snap: snap, compact: true)
                }
            } else {
                WidgetMainButton(snap: snap, compact: false)
                Spacer(minLength: 0)
            }
        }
    }
}

/// Главная кнопка: интент, если действие есть; иначе просто подпись (тап по виджету откроет приложение).
struct WidgetMainButton: View {
    var snap: PetSnapshot
    var compact: Bool

    var body: some View {
        if snap.main.action != nil {
            Button(intent: MainActionIntent(.widget)) { MainActLabel(main: snap.main, compact: compact, critical: snap.critical) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(snap.critical ? "\(Presenter.rescueTitle): \(snap.main.title)" : snap.main.title))
        } else if snap.main == .none, let tm = snap.timer {
            NeedTimerView(timer: tm, now: snap.t)
        } else {
            MainActLabel(main: snap.main, compact: compact, critical: snap.critical)
        }
    }
}
