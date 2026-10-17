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
        case .sleep, .wait, .walk, .open, .rest: return PetPalette.soft
        }
    }
}

extension PetAttributes.ContentState {
    /// Критично и ещё жив — та же граница, что у виджетов (Presenter.isCritical).
    var islandCritical: Bool { Presenter.isCritical(level: level, alive: pose != .dead) }

    /// Заголовок таймера: в ContentState его нет, берём по виду и шкале.
    var islandTimerTitle: String { Presenter.timerTitle(kind: timerKind ?? "", need: timerNeed) }
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
/// Таймер дольше часа («9:25:13») идёт без иконки и цветом шкалы — иначе не влезает и обрезается.
struct IslandCompactTrailing: View {
    var state: IslandState
    @Environment(\.petFrozenNow) private var frozenNow

    var body: some View {
        if let tm = state.timer {
            let long = !Presenter.timerIsLive(remaining: tm.end - (frozenNow ?? state.updatedAt))
            HStack(spacing: 3) {
                if !long {
                    Image(systemName: timerIcon(tm))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(timerTint(tm))
                }
                Text(timerInterval: Date(timeIntervalSince1970: min(tm.start, tm.end))...Date(timeIntervalSince1970: tm.end),
                     pauseTime: frozenNow.map { Date(timeIntervalSince1970: $0) },
                     countsDown: true)
                    .monospacedDigit()
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(state.level >= 2 ? PetPalette.red : (long ? timerTint(tm) : PetPalette.accent))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: long ? 52 : 36, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
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
            .frame(width: 64, height: 64)
    }
}

/// Справа: сердечки, при критичном — красная метка.
struct IslandExpandedTrailing: View {
    var state: IslandState

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HeartsView(hearts: state.hearts, max: state.heartsMax, size: 11)
            if state.islandCritical {
                Text("Критично")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(PetPalette.red))
            }
        }
    }
}

/// Центр: реплика в две строки (таймер и желание — строкой статуса внизу).
struct IslandExpandedCenter: View {
    var state: IslandState
    var stale = false

    var body: some View {
        Text(state.shownLine(stale: stale))
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
    }
}

/// Строка статуса острова: чего хочет (иконка и слово) и сколько осталось («Испачкается через 9 ч 25 мин»).
struct IslandStatusRow: View {
    var state: IslandState

    var hasContent: Bool { state.wantIcon != nil || state.timer != nil }

    var body: some View {
        HStack(spacing: 8) {
            if let icon = state.wantIcon {
                HStack(spacing: 4) {
                    ThoughtBubble.symbol(icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(state.level >= 2 ? PetPalette.red : PetPalette.accent)
                    if let want = state.want {
                        Text(Lines.shared.thought(want).text)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            if let tm = state.timer {
                NeedTimerView(timer: tm, showTitle: state.wantIcon == nil, now: state.updatedAt, title: state.islandTimerTitle)
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
    }
}

/// Вид большой кнопки острова. Статус (спит, моется, всё хорошо) — та же форма, но приглушённая.
/// critical: красная «Спасти» с иконкой действия.
struct IslandActLabel: View {
    var act: IslandAct
    var compact = false
    var critical = false

    var body: some View {
        let live = act.action != nil
        let rescue = critical && live
        HStack(spacing: 6) {
            Image(systemName: act.icon)
            Text(rescue ? Presenter.rescueTitle : act.title).lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(.system(size: compact ? 13 : 16, weight: .bold, design: .rounded))
        .foregroundStyle(live ? Color.white : Color.white.opacity(0.8))
        .padding(.horizontal, compact ? 12 : 16)
        .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 30 : 44)
        .background(Capsule().fill(rescue ? PetPalette.red : (live ? PetPalette.accent : PetPalette.soft.opacity(0.35))))
    }
}

/// Большая кнопка: действие — интентом, «Открыть» — ссылкой, статус — просто плашкой.
struct IslandPrimaryButton: View {
    var act: IslandAct
    var compact = false
    var critical = false

    var body: some View {
        if act.action != nil {
            Button(intent: IslandActIntent(act, .island)) { IslandActLabel(act: act, compact: compact, critical: critical) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(critical ? "\(Presenter.rescueTitle): \(act.title)" : act.title))
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

/// Низ острова: строка статуса, под ней одна большая кнопка — самое нужное сейчас, рядом максимум одна маленькая.
struct IslandExpandedBottom: View {
    var state: IslandState

    var body: some View {
        let status = IslandStatusRow(state: state)
        VStack(spacing: 8) {
            if status.hasContent { status }
            HStack(spacing: 10) {
                IslandPrimaryButton(act: state.bigAct, critical: state.islandCritical)
                if let small = state.smallAct {
                    IslandSecondaryButton(act: small)
                }
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
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 8) {
                    if let tm = state.timer {
                        NeedTimerView(timer: tm, now: state.updatedAt, title: state.islandTimerTitle)
                    }
                    Spacer(minLength: 0)
                    if let small = state.smallAct {
                        IslandSecondaryButton(act: small)
                    }
                    if state.bigAct.action != nil {
                        IslandPrimaryButton(act: state.bigAct, compact: true, critical: state.islandCritical)
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
            HStack(alignment: .top, spacing: 8) {
                IslandExpandedLeading(state: state)
                IslandExpandedCenter(state: state)
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
