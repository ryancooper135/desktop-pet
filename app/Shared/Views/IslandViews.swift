// Остров (Dynamic Island) и Live Activity на экране блокировки. Вход — ContentState, без ядра.
// Регионы острова собирает Widgets/PetLiveActivity; здесь их содержимое.

import AppIntents
import SwiftUI

typealias IslandState = PetAttributes.ContentState

struct IslandCompactLeading: View {
    var state: IslandState

    var body: some View {
        PetFaceView(pose: state.pose)
            .frame(width: 24, height: 24)
    }
}

struct IslandCompactTrailing: View {
    var state: IslandState

    var body: some View {
        if let icon = state.wantIcon {
            ThoughtBubble.symbol(icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(state.level >= 2 ? PetPalette.red : PetPalette.accent)
        } else if let tm = state.timer {
            Text(timerInterval: Date(timeIntervalSince1970: min(tm.start, tm.end))...Date(timeIntervalSince1970: tm.end),
                 countsDown: true)
                .monospacedDigit()
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalette.accent)
                .frame(maxWidth: 44)
        } else {
            Image(systemName: "heart.fill")
                .font(.system(size: 12))
                .foregroundStyle(PetPalette.red)
        }
    }
}

struct IslandMinimal: View {
    var state: IslandState

    var body: some View {
        PetFaceView(pose: state.pose)
            .frame(width: 22, height: 22)
    }
}

struct IslandExpandedLeading: View {
    var state: IslandState

    var body: some View {
        PetFaceView(pose: state.pose)
            .frame(width: 56, height: 56)
    }
}

struct IslandExpandedTrailing: View {
    var state: IslandState

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HeartsView(hearts: state.hearts, max: state.heartsMax, size: 10)
            if let icon = state.wantIcon {
                ThoughtBubble.symbol(icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PetPalette.accent)
            }
        }
    }
}

struct IslandExpandedCenter: View {
    var state: IslandState

    var body: some View {
        Text(state.line)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// Низ острова: таймер и кнопки. Главная — самое нужное, рядом «погладить», если главное другое.
struct IslandExpandedBottom: View {
    var state: IslandState

    var body: some View {
        HStack(spacing: 10) {
            if let tm = state.timer {
                NeedTimerView(timer: NeedTimer(kind: tm.kind, start: tm.start, end: tm.end, title: ""), showTitle: false)
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            Spacer(minLength: 0)
            if state.main.action != nil {
                if state.main != .pet {
                    Button(intent: PetIntent(.island)) { ActChip(icon: "hand.raised.fill", tint: PetPalette.need(.love)) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Погладить"))
                }
                Button(intent: MainActionIntent(.island)) { MainActLabel(main: state.main) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(state.main.title))
            } else {
                MainActLabel(main: state.main)
            }
        }
    }
}

/// Live Activity на экране блокировки и в баннере.
struct LockScreenActivityView: View {
    var name: String
    var state: IslandState

    var body: some View {
        HStack(spacing: 12) {
            PetFaceView(pose: state.pose)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                    Spacer(minLength: 0)
                    HeartsView(hearts: state.hearts, max: state.heartsMax, size: 10)
                }
                Text(state.line)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let tm = state.timer {
                        NeedTimerView(timer: tm, showTitle: false)
                    }
                    Spacer(minLength: 0)
                    if state.main.action != nil {
                        Button(intent: MainActionIntent(.island)) { MainActLabel(main: state.main, compact: true) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(state.main.title))
                    }
                }
            }
        }
        .padding(14)
    }
}

/// Развёрнутый остров целиком — только для превью и снимков (на устройстве регионы раскладывает система).
struct IslandExpandedPreview: View {
    var state: IslandState

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                IslandExpandedLeading(state: state)
                Spacer()
                IslandExpandedCenter(state: state)
                Spacer()
                IslandExpandedTrailing(state: state)
            }
            IslandExpandedBottom(state: state)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 40, style: .continuous).fill(Color.black))
    }
}

/// Свёрнутый остров — для превью.
struct IslandCompactPreview: View {
    var state: IslandState

    var body: some View {
        HStack {
            IslandCompactLeading(state: state)
            Spacer(minLength: 120)
            IslandCompactTrailing(state: state)
        }
        .padding(.horizontal, 10)
        .frame(height: 37)
        .background(Capsule().fill(Color.black))
    }
}
