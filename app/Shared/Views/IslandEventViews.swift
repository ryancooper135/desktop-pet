// Волна 34 J: остров и экран блокировки по событиям IslandEvents (§8) — одно событие за раз.
// Вход — IslandCard (state.card / state.next): что рисовать решает логика (Shared/IslandLook), здесь только вид.
// Пиксельный пёс — клетки PixelDog. Кадры меняются по TimelineView; система острова и виджетов кадры
// не крутит — там стоит первый кадр (живут только Text/ProgressView(timerInterval:)).

import AppIntents
import SwiftUI
import WidgetKit
@preconcurrency import PetCore

// MARK: - Пиксели

/// Клетки одного цвета одной фигурой: рисуется и в виджете, и в острове (без Canvas).
struct PixelCellsShape: Shape {
    var cells: [PixelCell]
    var ink: PixelInk?
    var cols: Int
    var rows: Int

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / CGFloat(max(1, cols)), rect.height / CGFloat(max(1, rows)))
        let ox = rect.minX + (rect.width - s * CGFloat(cols)) / 2
        let oy = rect.minY + (rect.height - s * CGFloat(rows)) / 2
        var p = Path()
        for c in cells where ink == nil || c.ink == ink {
            // Чуть внахлёст — без волосяных щелей между клетками на дробном масштабе.
            p.addRect(CGRect(x: ox + CGFloat(c.x) * s, y: oy + CGFloat(c.y) * s, width: s + 0.3, height: s + 0.3))
        }
        return p
    }
}

enum PixelColors {
    static func color(_ ink: PixelInk) -> Color {
        switch ink {
        case .outline: return Color(hex: 0x3b2a22)
        case .fur: return PetPalette.fur
        case .dark: return PetPalette.furDark
        case .cream: return PetPalette.cream
        case .eye: return PetPalette.nose
        case .bowl: return Color(hex: 0x6f8fb8)
        case .zz: return Color(hex: 0x9fb4d8)
        }
    }

    /// Силуэт для одного тона (экран блокировки): контур и тёмное — полный, остальное — полупрозрачно.
    static func mono(_ ink: PixelInk) -> Double {
        switch ink {
        case .outline, .eye: return 1
        case .dark, .bowl: return 0.75
        case .fur, .zz: return 0.55
        case .cream: return 0.35
        }
    }
}

/// Пиксельный пёс. animated — кадры по кругу (в приложении); снимок (petFrozenNow) и система — один кадр.
struct PixelDogView: View {
    var pose: DogPose
    var mono = false
    var animated = true
    @Environment(\.petFrozenNow) private var frozenNow

    var body: some View {
        if animated, frozenNow == nil {
            TimelineView(.periodic(from: .now, by: PixelDog.frameS)) { tl in
                frame(PixelDog.frameIndex(pose, at: tl.date.timeIntervalSince1970))
            }
        } else {
            frame(frozenNow.map { PixelDog.frameIndex(pose, at: $0) } ?? 0)
        }
    }

    private func frame(_ i: Int) -> some View {
        let cells = PixelDog.cells(pose, frame: i)
        return ZStack {
            ForEach(PixelInk.allCases, id: \.self) { ink in
                let shape = PixelCellsShape(cells: cells, ink: ink, cols: PixelDog.width, rows: PixelDog.height)
                if mono {
                    shape.fill(HierarchicalShapeStyle.primary.opacity(PixelColors.mono(ink)))
                } else {
                    shape.fill(PixelColors.color(ink))
                }
            }
        }
        .aspectRatio(CGFloat(PixelDog.width) / CGFloat(PixelDog.height), contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text(pose.title))
    }
}

/// Свинья-копилка 12×9 — значок полной копилки (в SF Symbols свиньи нет).
struct PixelPigView: View {
    var mono = false

    static let rows = [
        "......o.o...",
        "..oooooooo..",
        ".oppyypppo..",
        "oppppppppeoo",
        "opppppppppnn",
        "opppppppppnn",
        ".oppppppppo.",
        "..oo....oo..",
        "..oo....oo..",
    ]

    private static let inks: [(Character, UInt32, Double)] = [
        ("o", 0x6b3b45, 1), ("p", 0xf4a6b4, 0.55), ("n", 0xe07a8e, 0.8), ("e", 0x3b2a22, 1), ("y", 0x8c4a58, 0.9),
    ]

    /// Клетки одной буквы (цвет клетки — по букве, ink у PixelCell тут не важен).
    static func cells(_ ch: Character) -> [PixelCell] {
        var out: [PixelCell] = []
        for (y, row) in rows.enumerated() {
            for (x, c) in row.enumerated() where c == ch { out.append(PixelCell(x: x, y: y, ink: .fur)) }
        }
        return out
    }

    var body: some View {
        ZStack {
            ForEach(Self.inks.indices, id: \.self) { i in
                let ink = Self.inks[i]
                let shape = PixelCellsShape(cells: Self.cells(ink.0), ink: nil, cols: 12, rows: 9)
                if mono {
                    shape.fill(HierarchicalShapeStyle.primary.opacity(ink.2))
                } else {
                    shape.fill(Color(hex: ink.1))
                }
            }
        }
        .aspectRatio(12.0 / 9.0, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Мелочи карточки

extension IslandGlyph {
    var tint: Color {
        switch self {
        case .tracks, .heart: return PetPalette.red
        case .bowl: return PetPalette.need(.food)
        case .trip, .home: return PetPalette.green
        case .piggy: return Color(hex: 0xf4a6b4)
        case .star: return PetPalette.yellow
        case .calm: return PetPalette.soft
        }
    }
}

extension IslandCard {
    /// Кнопка карточки: голод — «Покормить», дома — «Погладить», сердечко — спасающая; остальное — «Открыть».
    var buttonAct: IslandAct { actsInPlace ? act : .open }
    var critical: Bool { kind == .lastChance }
}

/// Значок события: копилка — свинья, остальное — символ.
struct IslandGlyphView: View {
    var card: IslandCard
    var size: CGFloat = 14

    var body: some View {
        if card.glyph == .piggy {
            PixelPigView().frame(width: size * 1.3, height: size)
        } else {
            Image(systemName: card.glyph.symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(card.glyph.tint)
        }
    }
}

/// Отсчёт до конца карточки; в снимке (petFrozenNow) — стоит на месте.
struct IslandCountdown: View {
    var card: IslandCard
    var size: CGFloat = 12
    @Environment(\.petFrozenNow) private var frozenNow

    var body: some View {
        if let end = card.timerEnd {
            let start = min(card.progressFrom ?? card.from, end)
            Group {
                if let t = frozenNow {
                    // Снимок: остаток текстом — таймер на паузе показал бы прошедшее.
                    Text(IslandLook.countdown(end - t))
                } else {
                    Text(timerInterval: Date(timeIntervalSince1970: start - Clock.offset)...Date(timeIntervalSince1970: end - Clock.offset),
                         countsDown: true)
                }
            }
                .monospacedDigit()
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundStyle(card.glyph.tint)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Кольцо копилки 0…1 (статично: копилку пересчитывает приложение).
struct IslandRing: View {
    var value: Double
    var line: CGFloat = 3
    var tint: Color = Color(hex: 0xf4a6b4)

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: line)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, value))))
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(line / 2)
        .accessibilityElement()
        .accessibilityLabel(Text("Копилка"))
        .accessibilityValue(Text("\(Int((min(1, max(0, value)) * 100).rounded())) %"))
    }
}

/// Полоса похода: идёт сама (ProgressView(timerInterval:)), сверху пёс-точка, справа домик.
/// Точка стоит там, где была на момент обновления: системе её не сдвинуть — двигается заливка.
struct IslandTripBar: View {
    var card: IslandCard
    var now: Double = Clock.now()
    @Environment(\.petFrozenNow) private var frozenNow

    var body: some View {
        if card.hasProgress, let from = card.progressFrom, let end = card.timerEnd {
            let t = frozenNow ?? now
            let p = card.progress(at: t)
            HStack(spacing: 6) {
                Image(systemName: "house.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(PetPalette.soft)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        if frozenNow != nil {
                            // Снимок: полоса фигурами. ProgressView — системный UIProgressView, ImageRenderer
                            // его не рисует и ставит на его месте красный значок-«запрет».
                            Capsule().fill(PetPalette.soft.opacity(0.3)).frame(height: 4)
                            Capsule().fill(PetPalette.green).frame(width: max(4, geo.size.width * CGFloat(p)), height: 4)
                        } else {
                            ProgressView(timerInterval: Date(timeIntervalSince1970: from - Clock.offset)...Date(timeIntervalSince1970: end - Clock.offset),
                                         countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                                .progressViewStyle(.linear)
                                .tint(PetPalette.green)
                        }
                        Circle()
                            .fill(PetPalette.fur)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                            .frame(width: 10, height: 10)
                            .offset(x: max(0, min(geo.size.width - 10, geo.size.width * CGFloat(p) - 5)))
                    }
                    .frame(height: geo.size.height)
                }
                .frame(height: 12)
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(PetPalette.green)
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Поход"))
            .accessibilityValue(Text("\(Int((p * 100).rounded())) %"))
            .accessibilityIdentifier("w34j.island.tripBar")
        }
    }
}

/// Кнопка карточки: интент на месте или ссылка «Открыть».
struct IslandCardButton: View {
    var card: IslandCard
    var compact = false

    var body: some View {
        IslandPrimaryButton(act: card.buttonAct, compact: compact, critical: card.critical)
            .accessibilityIdentifier("w34j.island.button")
    }
}

// MARK: - Регионы острова

/// Слева в свёрнутом: значок события.
struct IslandCardCompactLeading: View {
    var card: IslandCard

    var body: some View {
        IslandGlyphView(card: card, size: 14)
            .frame(minWidth: 20)
            .accessibilityIdentifier("w34j.island.compactLeading")
    }
}

/// Справа в свёрнутом: таймер, кольцо копилки или короткая подпись («★14», «Дома»).
struct IslandCardCompactTrailing: View {
    var card: IslandCard

    var body: some View {
        Group {
            switch card.trailing {
            case .timer:
                IslandCountdown(card: card).frame(width: 44, alignment: .trailing)
            case .ring:
                IslandRing(value: card.ring ?? 0, line: 2.5).frame(width: 18, height: 18)
            case .text:
                Text(card.compact)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(card.glyph.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityIdentifier("w34j.island.compactTrailing")
    }
}

/// Минимальный (рядом чужая активность): кольцо копилки или значок.
struct IslandCardMinimal: View {
    var card: IslandCard

    var body: some View {
        if card.trailing == .ring {
            ZStack {
                IslandRing(value: card.ring ?? 0, line: 2)
                PixelPigView().padding(5)
            }
        } else {
            IslandGlyphView(card: card, size: 12)
        }
    }
}

struct IslandCardExpandedLeading: View {
    var card: IslandCard

    var body: some View {
        PixelDogView(pose: card.pose, animated: false)
            .frame(width: 64, height: 48)
            .accessibilityIdentifier("w34j.island.dog")
    }
}

/// Справа в развёрнутом: таймер / кольцо с процентом / «★14».
struct IslandCardExpandedTrailing: View {
    var card: IslandCard

    var body: some View {
        switch card.trailing {
        case .timer:
            IslandCountdown(card: card, size: 17).frame(width: 64, alignment: .trailing)
        case .ring:
            ZStack {
                IslandRing(value: card.ring ?? 0, line: 4)
                PixelPigView().padding(10)
            }
            .frame(width: 44, height: 44)
        case .text:
            Text(card.compact)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(card.glyph.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

struct IslandCardExpandedCenter: View {
    var card: IslandCard

    var body: some View {
        VStack(spacing: 2) {
            Text(card.title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let d = card.detail {
                Text(d)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("w34j.island.title")
    }
}

/// Низ: полоса похода (если есть) и одна кнопка.
struct IslandCardExpandedBottom: View {
    var card: IslandCard

    var body: some View {
        VStack(spacing: 8) {
            if card.hasProgress { IslandTripBar(card: card) }
            IslandCardButton(card: card)
        }
    }
}

/// Экран блокировки: пёс слева, событие и кнопка справа.
struct LockScreenCardView: View {
    var name: String
    var card: IslandCard

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PixelDogView(pose: card.pose, animated: false)
                .frame(width: 64, height: 48)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    IslandGlyphView(card: card, size: 12)
                    Text(name)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(PetPalette.soft)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    switch card.trailing {
                    case .timer: IslandCountdown(card: card, size: 14).frame(maxWidth: 70, alignment: .trailing)
                    case .ring: IslandRing(value: card.ring ?? 0, line: 3).frame(width: 22, height: 22)
                    case .text: EmptyView()
                    }
                }
                Text(card.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let d = card.detail {
                    Text(d)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalette.soft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                if card.hasProgress { IslandTripBar(card: card) }
                HStack {
                    Spacer(minLength: 0)
                    IslandCardButton(card: card, compact: true)
                }
            }
        }
        .padding(14)
        .accessibilityIdentifier("w34j.island.lock")
    }
}

/// Развёрнутый остров карточкой целиком — превью и снимки.
struct IslandCardExpandedPreview: View {
    var card: IslandCard

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                IslandCardExpandedLeading(card: card)
                IslandCardExpandedCenter(card: card)
                IslandCardExpandedTrailing(card: card)
            }
            IslandCardExpandedBottom(card: card)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 40, style: .continuous).fill(Color.black))
    }
}

/// Свёрнутый остров карточкой — превью и снимки.
struct IslandCardCompactPreview: View {
    var card: IslandCard

    var body: some View {
        HStack {
            IslandCardCompactLeading(card: card)
            Spacer(minLength: 120)
            IslandCardCompactTrailing(card: card)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Capsule().fill(Color.black))
    }
}
