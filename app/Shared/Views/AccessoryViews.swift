// Виджеты экрана блокировки: circular, rectangular, inline. Один тон: цвет даёт система.

import SwiftUI
@preconcurrency import PetCore

struct AccessoryCircularView: View {
    var snap: PetSnapshot

    var body: some View {
        Gauge(value: Swift.min(snap.hearts, snap.heartsMax), in: 0...Swift.max(1, snap.heartsMax)) {
            Image(systemName: "heart.fill")
        } currentValueLabel: {
            PetFaceView(pose: snap.pose, mono: true)
                .padding(2)
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel(Text("\(snap.name): \(snap.line)"))
    }
}

struct AccessoryRectangularView: View {
    var snap: PetSnapshot

    var body: some View {
        HStack(spacing: 6) {
            PetFaceView(pose: snap.pose, mono: true)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(snap.line)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let tm = snap.timer {
                    NeedTimerView(timer: tm, showTitle: false, mono: true)
                } else {
                    HeartsView(hearts: snap.hearts, max: snap.heartsMax, size: 9, mono: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Одна строка над часами: иконка желания (или лапка) и реплика.
struct AccessoryInlineView: View {
    var snap: PetSnapshot

    var body: some View {
        Label {
            Text(snap.line)
        } icon: {
            ThoughtBubble.symbol(snap.wantIcon ?? (snap.alive ? "pawprint.fill" : "cloud"))
        }
    }
}
