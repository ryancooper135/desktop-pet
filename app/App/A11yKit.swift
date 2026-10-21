// Волна 31 «для всех»: общие модификаторы доступности для вью. Слова и правила без SwiftUI — Shared/A11y.swift
// (там же тесты). Что и где применено, почему так — RESEARCH/17-a11y.md, решения — DECISIONS «Волна 31».
//
// petFont — кегль листов под Dynamic Type: на обычном размере ровно .system(size:weight:design:), как было;
//           с крупным шрифтом растёт за близким системным стилем, не больше A11y.fontCap раз.
// AXRow   — строка карточки «значок · текст · кнопка»: на accessibility-размерах шрифта стопкой, иначе как было.
// axLines — лимит строк, который на accessibility-размерах снимается (текст переносится, а не режется и не ужимается).
// Motion  — Reduce Motion для пружин и выпрыгиваний: спокойное появление вместо подскока.

import SwiftUI
import UIKit

private struct PetFont: ViewModifier {
    @ScaledMetric private var scaled: CGFloat
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        self.size = size
        self.weight = weight
        self.design = design
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: Self.style(size))
    }

    static func style(_ size: CGFloat) -> Font.TextStyle {
        switch A11y.styleRank(size: Double(size)) {
        case 0: return .caption2
        case 1: return .caption
        case 2: return .footnote
        case 3: return .subheadline
        case 4: return .body
        case 5: return .title3
        default: return .title2
        }
    }

    func body(content: Content) -> some View {
        let s = CGFloat(A11y.scaled(base: Double(size), scaled: Double(scaled)))
        content.font(.system(size: s, weight: weight, design: design))
    }
}

private struct AXLines: ViewModifier {
    @Environment(\.dynamicTypeSize) private var type
    let limit: Int

    func body(content: Content) -> some View {
        let ax = type.isAccessibilitySize
        content
            .lineLimit(ax ? nil : limit)
            .fixedSize(horizontal: false, vertical: ax)
            // Текст переносится — ужимать по ширине (minimumScaleFactor снаружи) незачем, аудит зовёт это обрезкой.
            .transformEnvironment(\.minimumScaleFactor) { f in
                if ax { f = 1 }
            }
    }
}

extension View {
    /// `.font(.system(size:weight:design:))`, который растёт с Dynamic Type (с потолком).
    func petFont(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .rounded) -> some View {
        modifier(PetFont(size: size, weight: weight, design: design))
    }

    /// `.lineLimit(n)` на обычных размерах; на accessibility-размерах без лимита.
    func axLines(_ limit: Int) -> some View {
        modifier(AXLines(limit: limit))
    }
}

/// Строка карточки: HStack как было; на accessibility-размерах шрифта — VStack по левому краю,
/// чтобы цена и кнопка не сжимали название до многоточия.
struct AXRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var type
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        let layout = type.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout { content }
    }
}

/// Reduce Motion для больших необязательных движений. Живость пса (PetStage, хореография) сюда не ходит —
/// там своё правило (DECISIONS, волна 18); тут пружины листов, выпрыгивания карточек и тряски.
@MainActor
enum Motion {
    static var reduce: Bool { UIAccessibility.isReduceMotionEnabled }

    /// Пружина с подскоком → короткое плавное изменение без перелёта.
    static func calm(_ a: Animation) -> Animation {
        reduce ? .easeInOut(duration: 0.2) : a
    }

    /// Выпрыгивание (scale/move) → просто проявиться.
    static func pop(_ t: AnyTransition) -> AnyTransition {
        reduce ? .opacity : t
    }
}

/// Поле касания 44 pt у маленьких кнопок (рекомендация Apple), а нарисованы они как были. Внутри label —
/// `.modifier(HitPad())`, снаружи кнопки — `.padding(-HitPad.pad)`: рамка кнопки (и VoiceOver) 44 pt,
/// а место в вёрстке прежнее, кружок 32 pt стоит там же.
struct HitPad: ViewModifier {
    static let pad: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .padding(Self.pad)
            .contentShape(Rectangle())
    }
}

/// Тряска отказа «не-а» (карточка, кнопка): шаги 0 → −6 → 6 → −3 → 0 pt. С Reduce Motion не качается —
/// отказ и так слышно и видно: щелчок Feel.denied, бейдж или строка с причиной.
struct RefuseShake<Trigger: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trigger: Trigger

    func body(content: Content) -> some View {
        content.phaseAnimator(A11y.steps(A11y.refuseShake, reduce: reduceMotion), trigger: trigger, content: { view, x in
            view.offset(x: CGFloat(x))
        }, animation: { _ in
            .linear(duration: 0.06)
        })
    }
}

extension AccessibilityAdjustmentDirection {
    /// Смахивание вверх (increment) — вправо по полю мини-игры.
    var isUp: Bool {
        if case .increment = self { return true }
        return false
    }
}
