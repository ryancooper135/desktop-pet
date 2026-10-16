// Мелкие общие куски: сердечки, пузырь мысли, таймер, шкала, главная кнопка.
// Работают и в приложении, и в виджетах (без RealityKit и без состояния).

import SwiftUI
import UIKit
@preconcurrency import PetCore

/// Прямоугольник на долю ширины слева: для половинок сердечек.
struct LeadingFraction: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width * CGFloat(min(1, max(0, fraction))), height: rect.height))
    }
}

struct HeartsView: View {
    var hearts: Double
    var max: Double
    var size: CGFloat = 14
    var mono = false

    var body: some View {
        let count = Swift.max(1, Int(max.rounded()))
        HStack(spacing: size * 0.2) {
            ForEach(0..<count, id: \.self) { i in
                // Половинки: дробь округляем до 0.5, как в макетах.
                let fill = Swift.min(1, Swift.max(0, ((hearts - Double(i)) * 2).rounded(.down) / 2))
                ZStack {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(mono ? AnyShapeStyle(ForegroundStyle().opacity(0.25)) : AnyShapeStyle(PetPalette.soft.opacity(0.25)))
                    Image(systemName: "heart.fill")
                        .foregroundStyle(mono ? AnyShapeStyle(ForegroundStyle()) : AnyShapeStyle(PetPalette.red))
                        .clipShape(LeadingFraction(fraction: fill))
                }
                .font(.system(size: size))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Сердечки: \(Int((hearts - 1e-9).rounded(.up))) из \(count)"))
    }
}

/// Пузырь мысли над питомцем: иконка SF Symbols и короткий текст.
struct ThoughtBubble: View {
    var icon: String
    var text: String?
    var urgent = false
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Self.symbol(icon)
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .foregroundStyle(urgent ? PetPalette.red : PetPalette.accent)
            if let text, !compact {
                Text(text)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, compact ? 6 : 9)
        .padding(.vertical, compact ? 4 : 5)
        .background(Capsule().fill(PetPalette.card))
        .overlay(Capsule().stroke(urgent ? PetPalette.red.opacity(0.6) : PetPalette.soft.opacity(0.25), lineWidth: 1))
    }

    /// Неизвестное имя символа даёт пустую картинку — проверяем и подставляем лапку.
    static func symbol(_ name: String) -> Image {
        UIImage(systemName: name) != nil ? Image(systemName: name) : Image(systemName: "pawprint.fill")
    }
}

/// Сколько осталось: ванна, дрёма, «проголодается через…». Сам тикает в виджетах и острове.
struct NeedTimerView: View {
    var timer: NeedTimer
    var showTitle = true
    var mono = false

    var body: some View {
        let start = Date(timeIntervalSince1970: Swift.min(timer.start, timer.end))
        let end = Date(timeIntervalSince1970: timer.end)
        HStack(spacing: 4) {
            Image(systemName: Self.icon(timer.kind))
            if showTitle && !timer.title.isEmpty {
                Text(timer.title)
            }
            Text(timerInterval: start...end, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.leading)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(mono ? AnyShapeStyle(ForegroundStyle()) : AnyShapeStyle(PetPalette.soft))
    }

    static func icon(_ kind: String) -> String {
        switch kind {
        case "bath": return "drop.fill"
        case "nap": return "moon.zzz.fill"
        default: return "clock"
        }
    }
}

/// Шкала нужды: иконка, имя, полоса.
struct NeedBar: View {
    var need: Need
    var value: Double
    var showName = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: PetPalette.needIcon(need))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PetPalette.need(need))
                .frame(width: 16)
            if showName {
                Text(Catalog.needName(need))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                    .frame(width: 70, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(PetPalette.soft.opacity(0.18))
                    Capsule().fill(PetPalette.need(need))
                        .frame(width: geo.size.width * CGFloat(Swift.min(1, Swift.max(0, value / 100))))
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(Catalog.needName(need)): \(Int(value.rounded())) из 100"))
    }
}

/// Шкалы, которые видит игрок (look — внутренняя, её не показываем).
enum VisibleNeeds {
    static let all: [Need] = [.food, .clean, .energy, .fun, .love, .walk]
    static let short: [Need] = [.food, .clean, .fun, .love]
}

/// Вид главной кнопки (сама кнопка — с интентом или замыканием — снаружи).
struct MainActLabel: View {
    var main: MainAct
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: main.icon)
            if !compact { Text(main.title).lineLimit(1).minimumScaleFactor(0.8) }
        }
        .font(.system(size: compact ? 13 : 14, weight: .bold, design: .rounded))
        .foregroundStyle(Color.white)
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 6 : 8)
        .background(Capsule().fill(main == .none ? PetPalette.soft : PetPalette.accent))
    }
}

/// Маленькая круглая кнопка действия в виджете.
struct ActChip: View {
    var icon: String
    var tint: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(Circle().fill(tint.opacity(0.16)))
    }
}
