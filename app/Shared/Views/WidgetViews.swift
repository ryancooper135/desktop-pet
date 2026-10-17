// Виджеты на домашнем экране: small, medium, large. Только вид по PetSnapshot и кнопки-интенты.
// Фон (containerBackground) и widgetURL ставит расширение в Widgets/, превью — PreviewCatalog.

import AppIntents
import SwiftUI
@preconcurrency import PetCore

struct WidgetSmallView: View {
    var snap: PetSnapshot

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top) {
                HeartsView(hearts: snap.hearts, max: snap.heartsMax, size: 10)
                Spacer(minLength: 0)
                if let icon = snap.wantIcon {
                    ThoughtBubble(icon: icon, text: nil, urgent: snap.urgent, compact: true)
                }
            }
            PetFaceView(pose: snap.pose)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) { RareMark(frame: snap.rare) }
            Text(snap.line)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            WidgetMainButton(snap: snap, compact: false)
        }
    }
}

struct WidgetMediumView: View {
    var snap: PetSnapshot

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                PetFaceView(pose: snap.pose)
                    .padding(.top, 8)
                RareMark(frame: snap.rare)
            }
            .frame(maxWidth: 130, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(snap.name)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                    Spacer(minLength: 0)
                    HeartsView(hearts: snap.hearts, max: snap.heartsMax, size: 11)
                }
                Text(snap.line)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let icon = snap.wantIcon {
                    ThoughtBubble(icon: icon, text: snap.wantText, urgent: snap.urgent)
                } else if let tm = snap.timer {
                    NeedTimerView(timer: tm)
                }
                Spacer(minLength: 0)
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
                .accessibilityLabel("Редкий момент")
        }
    }
}

/// Большой виджет: то же, что medium, плюс шкалы.
struct WidgetLargeView: View {
    var snap: PetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetMediumView(snap: snap)
                .frame(maxHeight: 150)
            if let tm = snap.timer, snap.wantIcon != nil {
                NeedTimerView(timer: tm)
            }
            VStack(spacing: 7) {
                ForEach(VisibleNeeds.all, id: \.self) { n in
                    NeedBar(need: n, value: snap.needs[n] ?? 0)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Кнопки medium/large: погладить, покормить и главное действие, если оно другое.
struct WidgetButtonsRow: View {
    var snap: PetSnapshot

    var body: some View {
        HStack(spacing: 8) {
            if snap.alive && snap.main != .none {
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
            Button(intent: MainActionIntent(.widget)) { MainActLabel(main: snap.main, compact: compact) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(snap.main.title))
        } else if snap.main == .none, let tm = snap.timer {
            NeedTimerView(timer: tm)
        } else {
            MainActLabel(main: snap.main, compact: compact)
        }
    }
}
