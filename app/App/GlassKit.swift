// Волна 53 «B · Стекло»: одна библиотека компонентов для всех экранов — стекло, карточка, кнопка-круг, шкала-кольцо,
// пункт таб-бара, тост из островка и плашка-чип с числом. Цвета — PetPalette (токены макета design/wave53/b*.html).
// Стекло — Liquid Glass (iOS 26, glassEffect); при «Понижении прозрачности» — плотная карточка с тонкой обводкой,
// как в макете: белое .46, обводка белым .75, мягкая сиреневая тень.

import SwiftUI
@preconcurrency import PetCore

// MARK: - Стекло

/// Стеклянная подложка любой формы. tint — цветное стекло (кнопки действий), interactive — пружинит под пальцем.
struct BGlass<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var solid
    let shape: S
    var tint: Color?
    var interactive = false

    func body(content: Content) -> some View {
        if solid {
            content
                .background(shape.fill(tint ?? PetPalette.card))
                .overlay(shape.stroke(PetPalette.ink.opacity(0.12), lineWidth: 1))
        } else {
            content.glassEffect(glass, in: shape)
        }
    }

    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}

extension View {
    /// Стекло стиля B: `.bGlass(Capsule())`, `.bGlass(Circle(), tint: PetPalette.food, interactive: true)`.
    func bGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(BGlass(shape: shape, tint: tint, interactive: interactive))
    }

    /// Стеклянная карточка: скругление 22, поля 14.
    func bCard(padding: CGFloat = 14, corner: CGFloat = 22) -> some View {
        self.padding(padding)
            .bGlass(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

/// Размеры макета B (pt).
enum BMetrics {
    /// Круг действия в полосе над таб-баром.
    static let actCircle: CGFloat = 54
    /// Высота таб-бара и круг «Гулять» рядом.
    static let tabBar: CGFloat = 66
    /// Пункт таб-бара: высота и наименьшая ширина (доступность: цель не меньше 44).
    static let tabItem: CGFloat = 56
    static let tabMin: CGFloat = 44
    /// Колечко шкалы справа и кольцо уровня на аватаре.
    static let needRing: CGFloat = 36
    static let levelRing: CGFloat = 44
}

// MARK: - Кольцо-шкала

/// Кольцо 0…1 с содержимым в центре (значок, цифра уровня, аватар). Без анимации при Reduce Motion — значение и так видно.
struct RingGauge<Center: View>: View {
    let value: Double
    let color: Color
    var size: CGFloat = BMetrics.needRing
    var line: CGFloat = 4
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: line)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .padding(line / 2)
        .frame(width: size, height: size)
    }
}

// MARK: - Круг-иконка

/// Цветной круг с белым значком SF Symbols — кнопки действий, тост, задание дня.
struct BIconCircle: View {
    let icon: String
    let color: Color
    var size: CGFloat = 44
    var bounce = 0

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .symbolEffect(.bounce, value: bounce)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(LinearGradient(colors: [color.opacity(0.92), color],
                                                     startPoint: .top, endPoint: .bottom)))
            .accessibilityHidden(true)
    }
}

// MARK: - Пункт таб-бара

/// Значок и слово под ним. Активный — сиреневый на светло-сиреневой капсуле (макет B). badge — точка «есть что сделать».
struct BTabItem: View {
    let icon: String
    let title: String
    var active = false
    var badge = false
    var dim = false
    var bounce = 0

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .symbolEffect(.bounce, value: bounce)
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle()
                            .fill(PetPalette.love)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            .offset(x: 6, y: -3)
                    }
                }
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(active ? PetPalette.vio : PetPalette.ink.opacity(dim ? 0.45 : 0.85))
        .frame(maxWidth: .infinity, minHeight: BMetrics.tabItem)
        .frame(minWidth: BMetrics.tabMin)
        .background {
            if active { Capsule().fill(PetPalette.vio.opacity(0.13)) }
        }
        .contentShape(Capsule())
    }
}

// MARK: - Чип с числом

/// Капсула «значок + число» (кошелёк, доход двора, уют). Числа вместо фраз — волна 53.
struct BChip: View {
    let icon: String
    let text: String
    var color: Color = PetPalette.ink
    /// Эмодзи вместо SF Symbols (🪙 — своя монета игры).
    var emoji = false

    var body: some View {
        HStack(spacing: 5) {
            if emoji {
                Text(icon).font(.system(size: 13))
            } else {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
            }
            Text(text)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PetPalette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .bGlass(Capsule())
    }
}

// MARK: - Тост из островка

/// Тост сверху, у Dynamic Island: чёрная капсула, слева цветной круг, текст белым, награда «+5 🪙» — золотой плашкой
/// справа (HomeLook.toastSplit). Касаний не ловит. Id «toast», подпись — весь текст (тесты и VoiceOver).
struct IslandToast: View {
    let toast: Toast
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 15

    var body: some View {
        let parts = HomeLook.toastSplit(toast.text)
        HStack(spacing: 10) {
            Group {
                if let e = toast.emoji {
                    Text(e)
                        .font(.system(size: 22))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(LinearGradient(colors: [PetPalette.vio, PetPalette.love],
                                                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
                } else {
                    BIconCircle(icon: toast.ok ? "checkmark" : "exclamationmark",
                                color: toast.ok ? PetPalette.play : PetPalette.food, size: 44)
                }
            }
            .accessibilityHidden(true)
            Text(parts.text)
                .font(.system(size: min(size, 19), weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let reward = parts.reward {
                Text(reward)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Capsule().fill(PetPalette.gold))
                    .fixedSize()
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(minHeight: 60)
        .background(Capsule().fill(PetPalette.island))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(toast.text))
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("toast")
    }
}
