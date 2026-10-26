// Волна 34 J: виджет «экранчик». Вход — WidgetLook (Shared/IslandLook): кадр посчитан логикой заранее,
// здесь только вид. Пластиковая рамка, внутри «экран»: небо по времени суток, полоска двора по ярусу,
// пиксельная сетка 6 % и виньетка. Анимаций по секундам нет: кадр меняется только сменой записи timeline.
// Тонированные режимы (accented/vibrant): небо, сетку и виньетку не рисуем — система их всё равно съест в плашку.

import AppIntents
import SwiftUI
import WidgetKit
@preconcurrency import PetCore

// MARK: - Экран

extension SkyPhase {
    /// Верх и низ неба: светлая и тёмная тема.
    var colors: (top: Color, bottom: Color) {
        switch self {
        case .dawn: return (.dynamic(light: 0xffcfae, dark: 0x5a3f52), .dynamic(light: 0xfff0dd, dark: 0x2e2633))
        case .day: return (.dynamic(light: 0xb9e0f6, dark: 0x2b4a63), .dynamic(light: 0xeaf6ff, dark: 0x1d2c3a))
        case .dusk: return (.dynamic(light: 0xf4ac84, dark: 0x553044), .dynamic(light: 0xf9dcc4, dark: 0x2a1f2b))
        case .night: return (.dynamic(light: 0x2d3c66, dark: 0x101728), .dynamic(light: 0x4a5a88, dark: 0x1e2840))
        }
    }

    var spoken: String {
        switch self {
        case .dawn: return "Утро"
        case .day: return "День"
        case .dusk: return "Вечер"
        case .night: return "Ночь"
        }
    }
}

/// Цвет земли двора по ярусу: пустырь → газон → сад.
enum YardStripColors {
    static let ground: [Color] = [
        .dynamic(light: 0xc9a77c, dark: 0x6e5a42),
        .dynamic(light: 0xa8cf86, dark: 0x4f6b3e),
        .dynamic(light: 0x8cc46c, dark: 0x41633a),
        .dynamic(light: 0x72b66a, dark: 0x355a36),
    ]
    static let tuft: [Color] = [
        .dynamic(light: 0xa88a62, dark: 0x5a4936),
        .dynamic(light: 0x86b366, dark: 0x3f5a31),
        .dynamic(light: 0x6aa553, dark: 0x33522d),
        .dynamic(light: 0x55985a, dark: 0x2a4a2b),
    ]

    static func pick(_ list: [Color], _ tier: Int) -> Color { list[min(max(0, tier), list.count - 1)] }
}

/// Пиксельная сетка: линии через step точек.
struct PixelGridShape: Shape {
    var step: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX
        while x <= rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.minY))
            p.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += step
        }
        var y = rect.minY
        while y <= rect.maxY {
            p.move(to: CGPoint(x: rect.minX, y: y))
            p.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += step
        }
        return p
    }
}

/// Полоска двора: земля и пиксельные кочки (больше ярус — гуще кочки).
struct YardStripView: View {
    var tier: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let n = 4 + min(max(0, tier), 3) * 3
            ZStack(alignment: .topLeading) {
                Rectangle().fill(YardStripColors.pick(YardStripColors.ground, tier))
                ForEach(0..<n, id: \.self) { i in
                    // Место кочки — детерминированно от номера, не от случайности: снимки стабильны.
                    let x = (CGFloat((i * 37) % 97) / 97) * max(0, w - 6)
                    let y = (CGFloat((i * 53) % 61) / 61) * max(0, h - 4)
                    Rectangle()
                        .fill(YardStripColors.pick(YardStripColors.tuft, tier))
                        .frame(width: 4, height: 2)
                        .offset(x: x, y: y)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// «Экран» виджета: небо, двор, содержимое, сетка, виньетка, скругление и блик пластика.
struct WidgetScreen<Content: View>: View {
    var look: WidgetLook
    var corner: CGFloat = 14
    var strip: CGFloat = 0.24
    @ViewBuilder var content: Content
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let full = renderingMode == .fullColor
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        ZStack {
            if full {
                LinearGradient(colors: [look.sky.colors.top, look.sky.colors.bottom], startPoint: .top, endPoint: .bottom)
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        YardStripView(tier: look.tier).frame(height: geo.size.height * strip)
                    }
                }
            }
            content
            if full {
                PixelGridShape(step: 3)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                    .allowsHitTesting(false)
                RadialGradient(colors: [.clear, Color.black.opacity(0.22)], center: .center, startRadius: 20, endRadius: 140)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                LinearGradient(colors: [Color.black.opacity(0.28), Color.white.opacity(0.45)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("w34j.widget.screen")
    }
}

/// Корпус виджета: светлый/тёмный пластик с бликом сверху.
struct WidgetPlastic: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.dynamic(light: 0xf6ece0, dark: 0x40352f), .dynamic(light: 0xe4d4c2, dark: 0x2a221e)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [Color.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)
        }
    }
}

// MARK: - Мелочи

/// Пёс на экране: стоит на дворе, щенок мельче. Кадр один — анимаций в виджете нет.
struct WidgetScreenDog: View {
    var look: WidgetLook
    var height: CGFloat
    var strip: CGFloat = 0.24

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                PixelDogView(pose: look.alive ? look.pose : .sleep, animated: false)
                    .frame(height: height * CGFloat(look.dogScale))
                    .opacity(look.alive ? 1 : 0.4)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, geo.size.height * strip * 0.45)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(look.caption))
        .accessibilityIdentifier("w34j.widget.dog")
    }
}

/// Кольцо копилки со свиньёй — в углу экрана.
struct WidgetBankRing: View {
    var look: WidgetLook
    var size: CGFloat = 30

    var body: some View {
        if let r = look.ring {
            ZStack {
                Circle().fill(Color.black.opacity(0.18))
                IslandRing(value: r, line: size / 10, tint: look.bankFull ? PetPalette.yellow : Color(hex: 0xf4a6b4))
                PixelPigView().padding(size * 0.24)
            }
            .frame(width: size, height: size)
            .widgetAccentable()
            .accessibilityElement()
            .accessibilityLabel(Text("Копилка"))
            .accessibilityValue(Text(look.bankLine ?? ""))
            .accessibilityIdentifier("w34j.widget.ring")
        }
    }
}

/// Полоска похода с пёсиком-точкой (статично на момент записи: записи — каждые 30 минут).
struct WidgetTripDot: View {
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(PetPalette.soft.opacity(0.22))
                Capsule().fill(PetPalette.green).frame(width: max(6, w * CGFloat(progress)))
                Circle()
                    .fill(PetPalette.fur)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .frame(width: 10, height: 10)
                    .offset(x: max(0, min(w - 10, w * CGFloat(progress) - 5)))
            }
        }
        .frame(height: 10)
        .widgetAccentable()
        .accessibilityElement()
        .accessibilityLabel(Text("Поход"))
        .accessibilityValue(Text("\(Int((progress * 100).rounded())) %"))
        .accessibilityIdentifier("w34j.widget.trip")
    }
}

/// Шкала одной строкой: иконка и полоса (имя — только если просили).
struct WidgetBarRow: View {
    var bar: WidgetBar
    var showName = false

    var body: some View {
        NeedBar(need: bar.need, value: Double(bar.value), showName: showName)
    }
}

/// Кнопка «Собрать»: копилка в кошелёк без открытия приложения.
struct WidgetCollectButton: View {
    var compact = false
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let tinted = renderingMode != .fullColor
        Button(intent: CollectIntent(.widget)) {
            HStack(spacing: 4) {
                Image(systemName: "hand.tap.fill")
                if !compact { Text("Собрать").lineLimit(1) }
            }
            .fixedSize()
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(Color.white))
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tinted ? AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.18)) : AnyShapeStyle(PetPalette.accent)))
        }
        .buttonStyle(.plain)
        .widgetAccentable()
        .accessibilityLabel(Text("Собрать копилку"))
        .accessibilityIdentifier("w34j.widget.collect")
    }
}

/// Строка копилки: «+214 · полная в 21:10» и «Собрать», если есть что.
struct WidgetBankRow: View {
    var look: WidgetLook

    var body: some View {
        if let line = look.bankLine {
            HStack(spacing: 6) {
                PixelPigView().frame(width: 16, height: 12)
                Text(line)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(look.bankFull ? PetPalette.accent : PetPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                if look.canCollect { WidgetCollectButton() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("w34j.widget.bank")
        }
    }
}

struct WidgetCaption: View {
    var look: WidgetLook
    var size: CGFloat = 13

    var body: some View {
        Text(look.caption)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(PetPalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityIdentifier("w34j.widget.caption")
    }
}

// MARK: - Домашний экран

/// Small: экран с псом и кольцом копилки, подпись, главная шкала. Полная копилка — кнопка «Собрать» в углу.
struct WidgetScreenSmallView: View {
    var look: WidgetLook

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetScreen(look: look) {
                WidgetScreenDog(look: look, height: 46)
            }
            .overlay(alignment: .topTrailing) { WidgetBankRing(look: look, size: 28).padding(5) }
            .overlay(alignment: .bottomTrailing) {
                if look.bankFull && look.canCollect { WidgetCollectButton(compact: true).padding(4) }
            }
            WidgetCaption(look: look, size: 12)
            if let tp = look.tripProgress {
                WidgetTripDot(progress: tp)
            } else if let m = look.main {
                WidgetBarRow(bar: m)
                    .frame(height: 12)
            }
        }
    }
}

/// Medium: экран с псом слева; справа подпись, три самые низкие шкалы, копилка «+214 · полная в 21:10», поход.
struct WidgetScreenMediumView: View {
    var look: WidgetLook

    var body: some View {
        HStack(spacing: 12) {
            WidgetScreen(look: look) {
                WidgetScreenDog(look: look, height: 64)
            }
            .overlay(alignment: .topTrailing) { WidgetBankRing(look: look, size: 30).padding(5) }
            .frame(width: 128)
            VStack(alignment: .leading, spacing: 5) {
                WidgetCaption(look: look, size: 14)
                if let tp = look.tripProgress {
                    WidgetTripDot(progress: tp)
                }
                ForEach(look.bars, id: \.need) { b in
                    WidgetBarRow(bar: b, showName: true)
                }
                Spacer(minLength: 0)
                WidgetBankRow(look: look)
            }
        }
    }
}

/// Large: большой экран, под ним то же, что в medium.
struct WidgetScreenLargeView: View {
    var look: WidgetLook

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetScreen(look: look, corner: 18) {
                WidgetScreenDog(look: look, height: 96)
            }
            .overlay(alignment: .topTrailing) { WidgetBankRing(look: look, size: 38).padding(8) }
            .overlay(alignment: .topLeading) {
                if !look.tierName.isEmpty {
                    Text(look.tierName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.28)))
                        .padding(8)
                }
            }
            WidgetCaption(look: look, size: 15)
            if let tp = look.tripProgress {
                WidgetTripDot(progress: tp)
            }
            ForEach(look.bars, id: \.need) { b in
                WidgetBarRow(bar: b, showName: true)
            }
            WidgetBankRow(look: look)
        }
    }
}

// MARK: - Экран блокировки

/// Таймер до возвращения из похода: тикает сам (система), в снимках стоит на petFrozenNow.
struct WidgetTripTimer: View {
    var from: Double
    var until: Double
    var size: CGFloat = 12
    @Environment(\.petFrozenNow) private var frozenNow

    var body: some View {
        Text(timerInterval: Date(timeIntervalSince1970: min(from, until) - Clock.offset)...Date(timeIntervalSince1970: until - Clock.offset),
             pauseTime: frozenNow.map { Date(timeIntervalSince1970: $0 - Clock.offset) },
             countsDown: true)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
    }
}

/// Круглый: поход — таймер до возвращения; копилка — кольцо со свиньёй; иначе силуэт пса.
struct WidgetLockCircularView: View {
    var look: WidgetLook

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            switch look.lock {
            case .trip:
                if let until = look.tripUntil {
                    VStack(spacing: 1) {
                        Image(systemName: "figure.walk").font(.system(size: 12, weight: .bold))
                        WidgetTripTimer(from: look.tripFrom ?? look.t, until: until, size: 11)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6)
                    }
                    .padding(4)
                }
            case .ring:
                Circle()
                    .inset(by: 2.5)
                    .stroke(HierarchicalShapeStyle.primary.opacity(0.25), lineWidth: 5)
                Circle()
                    .inset(by: 2.5)
                    .trim(from: 0, to: CGFloat(min(1, max(0, look.ring ?? 0))))
                    .stroke(HierarchicalShapeStyle.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
                PixelDogView(pose: look.pose, mono: true, animated: false).padding(11)
            case .pose:
                PixelDogView(pose: look.pose, mono: true, animated: false).padding(6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(look.caption))
        .accessibilityIdentifier("w34j.widget.circular")
    }
}

/// Прямоугольный: силуэт и подпись; поход — таймер, копилка — строка «+214 · полная в 21:10».
struct WidgetLockRectangularView: View {
    var look: WidgetLook

    var body: some View {
        HStack(spacing: 6) {
            PixelDogView(pose: look.pose, mono: true, animated: false)
                .frame(width: 44, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(look.caption)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                if look.lock == .trip, let until = look.tripUntil {
                    WidgetTripTimer(from: look.tripFrom ?? look.t, until: until, size: 12)
                } else if let line = look.bankLine {
                    Text(line)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("w34j.widget.rectangular")
    }
}

struct WidgetLockInlineView: View {
    var look: WidgetLook

    var body: some View {
        Text("\(Image(systemName: look.lock == .trip ? "figure.walk" : "pawprint.fill")) \(look.caption)")
    }
}

// MARK: - Фикстуры

extension PreviewFixtures {
    /// Кадр виджета для каталога и снимков: настроение + копилка (доля 0…1, nil — без двора).
    static func widgetLook(_ mood: String, bank: Double? = nil, tier: Int = 1) -> WidgetLook {
        let r = file(mood)
        var f = r.file
        let t = r.t
        f.pet.home[.yard] = tier
        if let b = bank {
            // Сушилка на 3 — копилка есть; время двора сдвигаем так, чтобы набралась нужная доля.
            f.yard.stations = ["dryer": 3]
            f.yard.bank = 0
            f.yard.t = t - b * YardConfig.shared.bankHours * 3600
        }
        let looks = WidgetLook.looks(f, now: t, tzOffsetMin: 0)
        var l = looks.first ?? WidgetLook.empty(t: t)
        switch mood {
        case "hungry": l.pose = .bowl
        case "asleep": l.pose = .sleep
        case "walking": l.pose = .away
        default: break
        }
        return l
    }
}

extension WidgetLook {
    /// Пустой кадр — на случай, если логика ничего не вернула.
    static func empty(t: Double) -> WidgetLook {
        WidgetLook(t: t, pose: .sit, alive: true, caption: "Всё хорошо", main: nil, bars: [], ring: nil, coins: nil,
                   coinsFull: nil, bankLine: nil, bankFull: false, tripFrom: nil, tripUntil: nil, sky: .day,
                   tier: 0, tierName: "", lock: .pose, dogScale: 1)
    }
}
