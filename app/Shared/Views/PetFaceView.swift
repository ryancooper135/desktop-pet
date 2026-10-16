// 2D-мордочка Шибы для виджетов, острова и запасного режима приложения.
// Стиль A «Nintendogs»: круглая голова, крупные мягкие глаза, румянец, никаких острых углов.
// Рисуется фигурами в сетке 100×100 и масштабируется под любой размер.

import SwiftUI

/// Путь в координатах 0…100, вписанный по центру в квадрат.
struct UnitPath: Shape {
    var unit: Path

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        let t = CGAffineTransform(translationX: rect.midX - 50 * s, y: rect.midY - 50 * s).scaledBy(x: s, y: s)
        return unit.applying(t)
    }
}

struct FaceExpression: Hashable, Sendable {
    enum Eyes: Hashable, Sendable { case open, wide, happy, closed, sleepy, sad, aside }
    enum Mouth: Hashable, Sendable { case smile, open, tongue, flat, frown, small }
    enum Extra: Hashable, Sendable { case none, zzz, heart, bubbles, dirt, sweat, halo, crumbs, cloud }

    var eyes: Eyes
    var mouth: Mouth
    var blush: Bool
    var extra: Extra
    var brows: Bool = false

    static func of(_ pose: Pose) -> FaceExpression {
        switch pose {
        case .happy: return .init(eyes: .happy, mouth: .tongue, blush: true, extra: .none)
        case .idle: return .init(eyes: .open, mouth: .smile, blush: true, extra: .none)
        case .eating: return .init(eyes: .happy, mouth: .open, blush: true, extra: .crumbs)
        case .loved: return .init(eyes: .happy, mouth: .smile, blush: true, extra: .heart)
        case .sleep: return .init(eyes: .closed, mouth: .small, blush: true, extra: .zzz)
        case .nap: return .init(eyes: .closed, mouth: .smile, blush: true, extra: .zzz)
        case .bath: return .init(eyes: .happy, mouth: .smile, blush: true, extra: .bubbles)
        case .hungry: return .init(eyes: .wide, mouth: .open, blush: false, extra: .none)
        case .dirty: return .init(eyes: .open, mouth: .flat, blush: false, extra: .dirt)
        case .tired: return .init(eyes: .sleepy, mouth: .small, blush: false, extra: .none)
        case .bored: return .init(eyes: .aside, mouth: .flat, blush: false, extra: .none)
        case .lonely: return .init(eyes: .sad, mouth: .small, blush: false, extra: .none, brows: true)
        case .sulky: return .init(eyes: .aside, mouth: .frown, blush: false, extra: .cloud, brows: true)
        case .critical: return .init(eyes: .sad, mouth: .frown, blush: false, extra: .sweat, brows: true)
        case .dead: return .init(eyes: .closed, mouth: .small, blush: false, extra: .halo)
        }
    }
}

struct PetFaceView: View {
    var pose: Pose
    /// Для экрана блокировки: без цветных пятен, система сама красит в один тон.
    var mono: Bool = false

    private var ex: FaceExpression { FaceExpression.of(pose) }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                // В mono черты лица вырезаны из головы: один тон, но глаза и нос читаются.
                ZStack {
                    head
                    ZStack {
                        eyes
                        nose
                        mouth
                        if ex.brows { brows }
                    }
                    .compositingGroup()
                    .blendMode(mono ? .destinationOut : .normal)
                }
                .compositingGroup()
                if ex.blush && !mono { blush }
                extra(side: side)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .saturation(pose == .dead ? 0.25 : 1)
        .accessibilityElement()
        .accessibilityLabel(Text(Self.accessibilityText(pose)))
    }

    // MARK: голова

    /// В mono — текущий цвет переднего плана (его задаёт система), а не Color.primary:
    /// тот зависит только от темы и на экране блокировки может выйти чёрным по чёрному.
    private var furColor: AnyShapeStyle { mono ? AnyShapeStyle(ForegroundStyle()) : AnyShapeStyle(PetPalette.fur) }
    /// В mono маска не красится, а наполовину вырезается из меха.
    private var creamColor: Color { mono ? .black.opacity(0.45) : PetPalette.cream }
    private var creamBlend: BlendMode { mono ? .destinationOut : .normal }
    /// В mono ink — это «ножницы»: всё, что им нарисовано, станет дыркой.
    private var inkColor: Color { mono ? .black : PetPalette.nose }

    private var head: some View {
        ZStack {
            UnitPath(unit: Self.ear(left: true)).fill(furColor)
            UnitPath(unit: Self.ear(left: false)).fill(furColor)
            UnitPath(unit: Self.innerEar(left: true)).fill(creamColor).blendMode(creamBlend)
            UnitPath(unit: Self.innerEar(left: false)).fill(creamColor).blendMode(creamBlend)
            UnitPath(unit: Path(ellipseIn: CGRect(x: 10, y: 20, width: 80, height: 70))).fill(furColor)
            // Светлая маска Шибы: щёки и подбородок, «бровки» над глазами.
            UnitPath(unit: Path(ellipseIn: CGRect(x: 20, y: 52, width: 60, height: 36))).fill(creamColor).blendMode(creamBlend)
            UnitPath(unit: Path(ellipseIn: CGRect(x: 29, y: 37, width: 11, height: 6))).fill(creamColor).blendMode(creamBlend)
            UnitPath(unit: Path(ellipseIn: CGRect(x: 60, y: 37, width: 11, height: 6))).fill(creamColor).blendMode(creamBlend)
        }
    }

    private static func ear(left: Bool) -> Path {
        var p = Path()
        let m: (CGFloat) -> CGFloat = { left ? $0 : 100 - $0 }
        p.move(to: CGPoint(x: m(14), y: 44))
        p.addQuadCurve(to: CGPoint(x: m(24), y: 8), control: CGPoint(x: m(12), y: 18))
        p.addQuadCurve(to: CGPoint(x: m(46), y: 26), control: CGPoint(x: m(34), y: 12))
        p.closeSubpath()
        return p
    }

    private static func innerEar(left: Bool) -> Path {
        var p = Path()
        let m: (CGFloat) -> CGFloat = { left ? $0 : 100 - $0 }
        p.move(to: CGPoint(x: m(20), y: 38))
        p.addQuadCurve(to: CGPoint(x: m(25), y: 16), control: CGPoint(x: m(19), y: 22))
        p.addQuadCurve(to: CGPoint(x: m(39), y: 28), control: CGPoint(x: m(32), y: 18))
        p.closeSubpath()
        return p
    }

    // MARK: глаза

    @ViewBuilder private var eyes: some View {
        ForEach([36.0, 64.0], id: \.self) { x in
            eye(x: x)
        }
    }

    @ViewBuilder private func eye(x: Double) -> some View {
        let y = 54.0
        switch ex.eyes {
        case .open, .wide, .sad, .aside:
            let r: Double = ex.eyes == .wide ? 7 : (ex.eyes == .sad ? 5 : 6)
            let dx: Double = ex.eyes == .aside ? 2.5 : 0
            UnitPath(unit: Path(ellipseIn: CGRect(x: x - r + dx, y: y - r, width: r * 2, height: r * 2 * 1.08))).fill(inkColor)
            if !mono {
                UnitPath(unit: Path(ellipseIn: CGRect(x: x - r * 0.45 + dx, y: y - r * 0.6, width: r * 0.6, height: r * 0.6)))
                    .fill(Color.white)
                if ex.eyes == .wide || ex.eyes == .sad {
                    UnitPath(unit: Path(ellipseIn: CGRect(x: x + r * 0.2 + dx, y: y + r * 0.25, width: r * 0.35, height: r * 0.35)))
                        .fill(Color.white.opacity(0.9))
                }
            }
        case .happy:
            UnitPath(unit: Self.arc(from: CGPoint(x: x - 5.5, y: y + 1.5), to: CGPoint(x: x + 5.5, y: y + 1.5),
                                    control: CGPoint(x: x, y: y - 7)))
                .stroke(inkColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        case .closed:
            UnitPath(unit: Self.arc(from: CGPoint(x: x - 5.5, y: y), to: CGPoint(x: x + 5.5, y: y),
                                    control: CGPoint(x: x, y: y + 5.5)))
                .stroke(inkColor, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        case .sleepy:
            UnitPath(unit: Path(ellipseIn: CGRect(x: x - 5, y: y - 1, width: 10, height: 6))).fill(inkColor)
            UnitPath(unit: Self.line(CGPoint(x: x - 6.5, y: y - 1), CGPoint(x: x + 6.5, y: y - 1)))
                .stroke(mono ? AnyShapeStyle(Color.black) : furColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .blendMode(mono ? .destinationOut : .normal)
        }
    }

    private var brows: some View {
        ZStack {
            UnitPath(unit: Self.line(CGPoint(x: 30, y: 42), CGPoint(x: 40, y: 45)))
                .stroke(inkColor.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            UnitPath(unit: Self.line(CGPoint(x: 70, y: 42), CGPoint(x: 60, y: 45)))
                .stroke(inkColor.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    // MARK: нос и рот

    private var nose: some View {
        UnitPath(unit: Path(roundedRect: CGRect(x: 44.5, y: 61, width: 11, height: 7.5), cornerRadius: 3.6)).fill(inkColor)
    }

    @ViewBuilder private var mouth: some View {
        let stroke = StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
        switch ex.mouth {
        case .smile, .tongue:
            if ex.mouth == .tongue && !mono {
                UnitPath(unit: Path(roundedRect: CGRect(x: 46, y: 70, width: 8, height: 9), cornerRadius: 4)).fill(PetPalette.tongue)
            }
            UnitPath(unit: Self.smile()).stroke(inkColor, style: stroke)
        case .open:
            UnitPath(unit: Path(ellipseIn: CGRect(x: 44, y: 69, width: 12, height: 10))).fill(mono ? inkColor : PetPalette.mouth)
            if !mono {
                UnitPath(unit: Path(ellipseIn: CGRect(x: 46.5, y: 74, width: 7, height: 4.5))).fill(PetPalette.tongue)
            }
        case .flat:
            UnitPath(unit: Self.line(CGPoint(x: 45, y: 73), CGPoint(x: 55, y: 73))).stroke(inkColor, style: stroke)
        case .frown:
            UnitPath(unit: Self.arc(from: CGPoint(x: 44, y: 76), to: CGPoint(x: 56, y: 76), control: CGPoint(x: 50, y: 69)))
                .stroke(inkColor, style: stroke)
        case .small:
            UnitPath(unit: Self.arc(from: CGPoint(x: 46.5, y: 71.5), to: CGPoint(x: 53.5, y: 71.5), control: CGPoint(x: 50, y: 75)))
                .stroke(inkColor, style: stroke)
        }
    }

    private static func smile() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 50, y: 68))
        p.addLine(to: CGPoint(x: 50, y: 70.5))
        p.addQuadCurve(to: CGPoint(x: 42, y: 71), control: CGPoint(x: 46, y: 76))
        p.move(to: CGPoint(x: 50, y: 70.5))
        p.addQuadCurve(to: CGPoint(x: 58, y: 71), control: CGPoint(x: 54, y: 76))
        return p
    }

    private var blush: some View {
        ZStack {
            UnitPath(unit: Path(ellipseIn: CGRect(x: 20, y: 62, width: 12, height: 7))).fill(PetPalette.blush.opacity(0.7))
            UnitPath(unit: Path(ellipseIn: CGRect(x: 68, y: 62, width: 12, height: 7))).fill(PetPalette.blush.opacity(0.7))
        }
    }

    // MARK: добавки

    @ViewBuilder private func extra(side: CGFloat) -> some View {
        let u = side / 100
        switch ex.extra {
        case .none:
            EmptyView()
        case .zzz:
            ZStack {
                Text("z").font(.system(size: 11 * u, weight: .bold, design: .rounded)).offset(x: 30 * u, y: -30 * u)
                Text("z").font(.system(size: 15 * u, weight: .bold, design: .rounded)).offset(x: 38 * u, y: -40 * u)
            }
            .foregroundStyle(mono ? AnyShapeStyle(ForegroundStyle()) : AnyShapeStyle(PetPalette.soft))
        case .heart:
            Image(systemName: "heart.fill")
                .font(.system(size: 16 * u))
                .foregroundStyle(mono ? AnyShapeStyle(ForegroundStyle()) : AnyShapeStyle(PetPalette.red))
                .offset(x: 34 * u, y: -36 * u)
        case .bubbles:
            ZStack {
                Circle().stroke(Color(hex: 0x6f9fd8), lineWidth: 1.5 * u).frame(width: 10 * u).offset(x: -34 * u, y: -34 * u)
                Circle().stroke(Color(hex: 0x6f9fd8), lineWidth: 1.5 * u).frame(width: 14 * u).offset(x: 36 * u, y: -38 * u)
                Circle().stroke(Color(hex: 0x6f9fd8), lineWidth: 1.5 * u).frame(width: 7 * u).offset(x: 42 * u, y: -22 * u)
            }
            .opacity(mono ? 0.6 : 1)
        case .dirt:
            ZStack {
                Ellipse().fill(Color(hex: 0x8a6a4a).opacity(0.55)).frame(width: 9 * u, height: 6 * u).offset(x: -22 * u, y: -18 * u)
                Ellipse().fill(Color(hex: 0x8a6a4a).opacity(0.5)).frame(width: 6 * u, height: 4 * u).offset(x: 26 * u, y: 20 * u)
                Ellipse().fill(Color(hex: 0x8a6a4a).opacity(0.45)).frame(width: 5 * u, height: 4 * u).offset(x: 18 * u, y: -22 * u)
            }
            .opacity(mono ? 0 : 1)
        case .sweat:
            Image(systemName: "drop.fill")
                .font(.system(size: 11 * u))
                .foregroundStyle(mono ? AnyShapeStyle(ForegroundStyle()) : AnyShapeStyle(Color(hex: 0x6f9fd8)))
                .offset(x: 36 * u, y: -14 * u)
        case .halo:
            Ellipse()
                .stroke(mono ? AnyShapeStyle(ForegroundStyle()) : AnyShapeStyle(PetPalette.yellow), lineWidth: 2.5 * u)
                .frame(width: 34 * u, height: 9 * u)
                .offset(y: -44 * u)
        case .crumbs:
            ZStack {
                Circle().fill(Color(hex: 0xb07a45)).frame(width: 4 * u).offset(x: -8 * u, y: 34 * u)
                Circle().fill(Color(hex: 0xb07a45)).frame(width: 3 * u).offset(x: 9 * u, y: 36 * u)
                Circle().fill(Color(hex: 0xb07a45)).frame(width: 3.5 * u).offset(x: 2 * u, y: 40 * u)
            }
            .opacity(mono ? 0 : 1)
        case .cloud:
            Image(systemName: "cloud.fill")
                .font(.system(size: 14 * u))
                .foregroundStyle(mono ? AnyShapeStyle(ForegroundStyle()) : AnyShapeStyle(PetPalette.soft.opacity(0.8)))
                .offset(x: 36 * u, y: -38 * u)
        }
    }

    // MARK: геометрия

    private static func arc(from a: CGPoint, to b: CGPoint, control c: CGPoint) -> Path {
        var p = Path()
        p.move(to: a)
        p.addQuadCurve(to: b, control: c)
        return p
    }

    private static func line(_ a: CGPoint, _ b: CGPoint) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        return p
    }

    static func accessibilityText(_ pose: Pose) -> String {
        switch pose {
        case .happy: return "Шиба радуется"
        case .idle: return "Шиба спокоен"
        case .eating: return "Шиба ест"
        case .loved: return "Шибе приятно"
        case .sleep: return "Шиба спит"
        case .nap: return "Шиба дремлет"
        case .bath: return "Шиба моется"
        case .hungry: return "Шиба голодный"
        case .dirty: return "Шиба испачкался"
        case .tired: return "Шиба устал"
        case .bored: return "Шибе скучно"
        case .lonely: return "Шиба скучает по тебе"
        case .sulky: return "Шиба обиделся"
        case .critical: return "Шибе очень плохо"
        case .dead: return "Шибы больше нет"
        }
    }
}
