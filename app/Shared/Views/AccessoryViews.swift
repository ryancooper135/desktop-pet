// Виджеты экрана блокировки: circular, rectangular, inline. Один тон: цвет даёт система.

import SwiftUI
import WidgetKit
@preconcurrency import PetCore

/// Круглый: одно кольцо сердечек и крупная мордочка внутри. Без значка и подписи —
/// у системного Gauge они съедали место, и мордочка выходила мелкой.
struct AccessoryCircularView: View {
    var snap: PetSnapshot

    var body: some View {
        let ring: CGFloat = 5
        ZStack {
            AccessoryWidgetBackground()
            Circle()
                .strokeBorder(HierarchicalShapeStyle.primary.opacity(0.25), lineWidth: ring)
            Circle()
                .inset(by: ring / 2)
                .trim(from: 0, to: CGFloat(Self.fraction(hearts: snap.hearts, max: snap.heartsMax)))
                .stroke(HierarchicalShapeStyle.primary, style: StrokeStyle(lineWidth: ring, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            PetFaceView(pose: snap.pose, mono: true)
                .padding(ring + 4)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(snap.name): \(snap.line)"))
        .accessibilityValue(Text("Сердечки: \(Int((snap.hearts - 1e-9).rounded(.up))) из \(Int(snap.heartsMax.rounded()))"))
    }

    /// Доля кольца: сердечки из максимума, 0…1.
    nonisolated static func fraction(hearts: Double, max: Double) -> Double {
        guard max > 0 else { return 0 }
        return Swift.min(1, Swift.max(0, hearts / max))
    }
}

/// Прямоугольный: мордочка, реплика в две строки, сердечки всегда, таймер — если есть.
/// Реплика короткая (как у маленького виджета): длинная рвалась на «что-/нибудь» и обрезалась.
struct AccessoryRectangularView: View {
    var snap: PetSnapshot

    var body: some View {
        HStack(spacing: 6) {
            PetFaceView(pose: snap.pose, mono: true)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(snap.shortLine)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                HeartsView(hearts: snap.hearts, max: snap.heartsMax, size: 9, mono: true)
                if let tm = snap.timer {
                    NeedTimerView(timer: tm, showTitle: false, mono: true, now: snap.t)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Одна строка над часами: иконка желания (или лапка) и короткая реплика.
struct AccessoryInlineView: View {
    var snap: PetSnapshot

    var body: some View {
        Label {
            Text(snap.shortLine)
        } icon: {
            ThoughtBubble.symbol(snap.wantIcon ?? (snap.pose == .away ? "figure.walk" : (snap.alive ? "pawprint.fill" : "cloud")))
        }
    }
}
