// Остров (Dynamic Island) и Live Activity на экране блокировки. Вход — ContentState (ядро только ради Need).
// Регионы острова собирает Widgets/PetLiveActivity; здесь их содержимое.
// stale — система пометила содержимое устаревшим (staleDate): реакция на действие кончилась.

import AppIntents
import SwiftUI
@preconcurrency import PetCore

typealias IslandState = PetAttributes.ContentState

extension IslandAct {
    var tint: Color {
        switch self {
        case .feed: return PetPalette.need(.food)
        case .bath: return PetPalette.need(.clean)
        case .play: return PetPalette.need(.fun)
        case .pet: return PetPalette.need(.love)
        case .heal: return PetPalette.red
        case .wake: return PetPalette.yellow
        case .sleep, .wait, .open, .rest: return PetPalette.soft
        }
    }
}

/// Слева в свёрнутом острове: мордочка, после действия — короткая реакция.
struct IslandCompactLeading: View {
    var state: IslandState
    var stale = false

    var body: some View {
        PetFaceView(pose: state.shownPose(stale: stale))
            .frame(width: 24, height: 24)
    }
}

/// Справа в свёрнутом острове: таймер самой срочной нужды, иначе желание, иначе сердечко.
struct IslandCompactTrailing: View {
    var state: IslandState

    var body: some View {
        if let tm = state.timer {
            HStack(spacing: 3) {
                Image(systemName: timerIcon(tm))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(timerTint(tm))
                Text(timerInterval: Date(timeIntervalSince1970: min(tm.start, tm.end))...Date(timeIntervalSince1970: tm.end),
                     countsDown: true)
                    .monospacedDigit()
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(state.level >= 2 ? PetPalette.red : PetPalette.accent)
                    .frame(maxWidth: 44)
            }
        } else if let icon = state.wantIcon {
            ThoughtBubble.symbol(icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(state.level >= 2 ? PetPalette.red : PetPalette.accent)
        } else {
            Image(systemName: "heart.fill")
                .font(.system(size: 12))
                .foregroundStyle(PetPalette.red)
        }
    }

    private var timerNeed: Need? { state.timerNeed.flatMap { Need(rawValue: $0) } }

    private func timerIcon(_ tm: NeedTimer) -> String {
        if tm.kind != "low" { return NeedTimerView.icon(tm.kind) }
        return timerNeed.map { PetPalette.needIcon($0) } ?? "heart.fill"
    }

    private func timerTint(_ tm: NeedTimer) -> Color {
        if tm.kind != "low" { return PetPalette.soft }
        return timerNeed.map { PetPalette.need($0) } ?? PetPalette.red
    }
}

struct IslandMinimal: View {
    var state: IslandState
    var stale = false

    var body: some View {
        PetFaceView(pose: state.shownPose(stale: stale))
            .frame(width: 22, height: 22)
    }
}

struct IslandExpandedLeading: View {
    var state: IslandState
    var stale = false

    var body: some View {
        PetFaceView(pose: state.shownPose(stale: stale))
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

/// Центр: реплика и таймер под ней.
struct IslandExpandedCenter: View {
    var state: IslandState
    var stale = false

    var body: some View {
        VStack(spacing: 3) {
            Text(state.shownLine(stale: stale))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let tm = state.timer {
                NeedTimerView(timer: tm, showTitle: false)
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        }
    }
}

/// Вид большой кнопки острова. Статус (спит, моется, всё хорошо) — та же форма, но приглушённая.
struct IslandActLabel: View {
    var act: IslandAct
    var compact = false

    var body: some View {
        let live = act.action != nil
        HStack(spacing: 6) {
            Image(systemName: act.icon)
            Text(act.title).lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(.system(size: compact ? 13 : 16, weight: .bold, design: .rounded))
        .foregroundStyle(live ? Color.white : Color.white.opacity(0.8))
        .padding(.horizontal, compact ? 12 : 16)
        .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 30 : 44)
        .background(Capsule().fill(live ? PetPalette.accent : PetPalette.soft.opacity(0.35)))
    }
}

/// Большая кнопка: действие — интентом, «Открыть» — ссылкой, статус — просто плашкой.
struct IslandPrimaryButton: View {
    var act: IslandAct
    var compact = false

    var body: some View {
        if act.action != nil {
            Button(intent: IslandActIntent(act, .island)) { IslandActLabel(act: act, compact: compact) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(act.title))
        } else if act == .open, let url = URL(string: "pet://home") {
            Link(destination: url) { IslandActLabel(act: act, compact: compact) }
        } else {
            IslandActLabel(act: act, compact: compact)
        }
    }
}

/// Маленькая круглая кнопка рядом с большой.
struct IslandSecondaryButton: View {
    var act: IslandAct

    var body: some View {
        Button(intent: IslandActIntent(act, .island)) { ActChip(icon: act.icon, tint: act.tint) }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(act.title))
    }
}

/// Низ острова: одна большая кнопка — самое нужное сейчас, рядом максимум одна маленькая.
struct IslandExpandedBottom: View {
    var state: IslandState

    var body: some View {
        HStack(spacing: 10) {
            IslandPrimaryButton(act: state.bigAct)
            if let small = state.smallAct {
                IslandSecondaryButton(act: small)
            }
        }
    }
}

/// Live Activity на экране блокировки и в баннере.
struct LockScreenActivityView: View {
    var name: String
    var state: IslandState
    var stale = false

    var body: some View {
        HStack(spacing: 12) {
            PetFaceView(pose: state.shownPose(stale: stale))
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                    Spacer(minLength: 0)
                    HeartsView(hearts: state.hearts, max: state.heartsMax, size: 10)
                }
                Text(state.shownLine(stale: stale))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let tm = state.timer {
                        NeedTimerView(timer: tm, showTitle: false)
                    }
                    Spacer(minLength: 0)
                    if let small = state.smallAct {
                        IslandSecondaryButton(act: small)
                    }
                    if state.bigAct.action != nil {
                        IslandPrimaryButton(act: state.bigAct, compact: true)
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
