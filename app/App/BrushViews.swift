// «Расчесать» (волна 9): вид. Логика — Brush (Shared), тут жест, полоса прогресса, карточка в листе «Трюки» и
// шерстинки на спине в 3D (BrushFx). Колтуны и клочки — геометрия шерсти на костях (PetWear.applyTufts, волна 11).
// Пока чешем: поверх сцены — площадка жеста (BrushLayer), вместо ряда кнопок — полоса «Расчёсано N%» (BrushPanel).
// Мазок по шерсти: лёгкая хаптика, «шорх», шерстинки и искры над спиной, колтун пропадает (сначала у головы).
// Против шерсти: пёс дёргается, «😖», мазок не в счёт. Дочесали — отряхнулся, шерсть на стадию лучше.
// VoiceOver: у площадки действие «Расчесать один раз», в полосе — такая же кнопка.

import SwiftUI
import UIKit
@preconcurrency import RealityKit
@preconcurrency import PetCore

// MARK: жест

/// Площадка жеста поверх сцены на время расчёсывания. Голова Шибы слева, хвост справа: по шерсти — слева направо.
struct BrushLayer: View {
    @Environment(AppModel.self) private var model
    @State private var box = BrushBox()

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in moved(g) }
                    .onEnded { g in ended(g) }
            )
            .accessibilityElement()
            .accessibilityLabel(Text(PetNames.adapt("Спина Шибы", name: model.snap.name)))
            .accessibilityValue(Text(model.brush?.text ?? ""))
            .accessibilityHint(Text("Веди пальцем от головы к хвосту"))
            .accessibilityAddTraits(.allowsDirectInteraction)
            .accessibilityAction { model.brushStroke() }
            .accessibilityAction(named: Text("Расчесать один раз")) { model.brushStroke() }
            .accessibilityIdentifier("brush.pad")
    }

    private func moved(_ g: DragGesture.Value) {
        let t = g.time.timeIntervalSinceReferenceDate
        if !box.tracker.active || box.start != g.startLocation {
            box.tracker.begin(x: g.startLocation.x, y: g.startLocation.y, time: t)
            box.start = g.startLocation
        }
        handle(box.tracker.move(x: g.location.x, y: g.location.y, time: t), at: g.location)
        model.touch(at: g.location)
    }

    private func ended(_ g: DragGesture.Value) {
        let t = g.time.timeIntervalSinceReferenceDate
        let events = box.tracker.end(x: g.location.x, y: g.location.y, time: t)
        box.start = nil
        handle(events, at: g.location)
        model.touchEnded()
    }

    private func handle(_ events: [BrushEvent], at p: CGPoint) {
        for e in events {
            switch e {
            case .stroke: model.brushStroke(at: p)
            case .against: model.brushAgainst(at: p)
            }
        }
    }
}

/// Состояние жеста (не @Observable: экран его не читает).
final class BrushBox {
    var tracker = BrushTracker(axisX: 1, axisY: 0)
    var start: CGPoint? = nil
}

// MARK: полоса прогресса

/// Вместо ряда кнопок, пока чешем: кольцо, «Расчёсано N%», подсказка и «Готово»/крестик.
struct BrushPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        let s = model.brush ?? BrushSession()
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                BrushRing(progress: s.progress)
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.text)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("brush.progress")
                    Text(hint(s))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalette.soft)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                if s.done {
                    Button {
                        Feel.tap()
                        model.endBrush()
                    } label: {
                        Text("Готово")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .frame(minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PetPalette.accent)
                    .accessibilityIdentifier("brush.done")
                } else {
                    Button {
                        model.endBrush()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(PetPalette.soft)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(PetPalette.soft.opacity(0.14)))
                    }
                    .buttonStyle(SquishStyle())
                    .accessibilityLabel(Text("Хватит чесать"))
                    .accessibilityIdentifier("brush.close")
                }
            }
            if voiceOver && !s.done {
                Button {
                    model.brushStroke()
                } label: {
                    Text("Расчесать один раз")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(PetPalette.accent)
                .accessibilityIdentifier("brush.once")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 22).fill(PetPalette.card))
        .animation(.snappy, value: s.counted)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brush.panel")
    }

    private func hint(_ s: BrushSession) -> String {
        // Не «Пёс отряхнулся»: это же говорит тост в конце, а «пёс» вместо имени звучит чуждо.
        if s.done { return "Блестит! Шерсть как шёлк" }
        if s.against > 0 && s.counted == 0 { return "Не против шерсти — от головы к хвосту" }
        return "Веди пальцем по спине от головы к хвосту"
    }
}

/// Кольцо прогресса: серая дорожка, оранжевая дуга, к концу — зелёная с галочкой.
struct BrushRing: View {
    let progress: Double

    var body: some View {
        let done = progress >= 1
        ZStack {
            Circle()
                .stroke(PetPalette.soft.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(done ? PetPalette.green : PetPalette.accent,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(PetPalette.green)
            } else {
                CombGlyph(color: PetPalette.accent)
                    .frame(width: 24, height: 16)
            }
        }
        .animation(.snappy, value: progress)
        .accessibilityHidden(true)
    }
}

/// Расчёска из фигур: спинка и зубья (своя, чтобы не зависеть от набора SF Symbols).
struct CombGlyph: View {
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let teeth = 6
            let gap = w / CGFloat(teeth * 2 - 1)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: h * 0.2)
                    .fill(color)
                    .frame(width: w, height: h * 0.4)
                ForEach(0..<teeth, id: \.self) { i in
                    RoundedRectangle(cornerRadius: gap / 2)
                        .fill(color)
                        .frame(width: gap, height: h * 0.75)
                        .offset(x: CGFloat(i) * gap * 2, y: h * 0.25)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: вход в листе «Трюки»

/// Строка «Расчесать» под командами в листе с лапой. Нельзя (спит, гуляет, недавно чесали) — серая с причиной.
struct BrushCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let now = model.snap.t
        let gate = model.file.map { Brush.gate($0, at: now) } ?? Tricks.loadingReason
        let remaining = model.file.map { Brush.remaining($0, at: now) } ?? 0
        let stage = model.file.map { Coat.look($0, now: now).stage }
        let status = gate.map { Brush.reasonText($0, remaining: remaining) }
            // «Шерсть: «Колтуны» · колтунов 6» повторяло слово; теперь стадия и сколько клочков на спине.
            ?? stage.map { "\($0.title) · клочков шерсти: \(Brush.tufts($0))" } ?? ""
        Button {
            // Отклик один: нельзя — «не-а» из startBrush, можно — щелчок здесь (волна 29).
            if gate == nil { Feel.tap(.button) }
            model.startBrush()
        } label: {
            HStack(spacing: 10) {
                CombGlyph(color: PetPalette.accent)
                    .frame(width: 22, height: 15)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(PetPalette.accent.opacity(0.16)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Расчесать")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                    Text(status)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalette.soft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PetPalette.soft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 18).fill(PetPalette.card))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(SquishStyle())
        .disabled(gate != nil)
        .deniedTap(when: gate != nil)
        .opacity(gate == nil ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Расчесать"))
        .accessibilityValue(Text(status))
        .accessibilityHint(Text("Проведи по спине от головы к хвосту"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("open.brush")
    }
}

// MARK: 3D: шерстинки

/// Шерстинки и искры — на каждый мазок. Сами колтуны и клочки — геометрия на костях спины (PetWear.applyTufts,
/// CoatFur.tuft): шерстинки летят оттуда, где только что сняли клочок. Живут в контейнере под petJuice: дышат
/// и пружинят вместе с питомцем.
@MainActor
enum BrushFx {
    static let containerName = "brushFx"
    /// Линия спины по высоте рамки: верх рамки дают уши и хвост, спина — около 0,68 (подобрано по ui-59: 0,55 — внутри, 0,79 — висят).
    static let backRatio: Float = 0.68
    /// Последний показанный мазок (AppModel.brushPuff): новые — шерстинки.
    private static var lastPuff = 0

    /// При сборке сцены: старые мазки не повторяем.
    static func prime(puff: Int) {
        lastPuff = puff
    }

    /// left — клочков осталось, total — было в начале, puff — счётчик мазков. Звать после PetWear.applyTufts.
    static func apply(left: Int, total: Int, puff: Int, reduceMotion: Bool, to pet: Entity) {
        let removed = PetWear.takeTuftSpot(pet)
        defer { lastPuff = puff }
        guard puff > lastPuff, !reduceMotion else { return }
        let pivot = pet.children.first { $0.name == PetModel.pivotName } ?? pet
        let box: Entity
        if let found = pivot.children.first(where: { $0.name == containerName }) {
            box = found
        } else {
            box = Entity()
            box.name = containerName
            pivot.addChild(box)
        }
        // Шерстинки летят оттуда, где только что был клочок; не нашли его — с линии спины, клочков нет — с середины.
        let n = max(total, left)
        let i = n - left - 1
        let at = removed ?? (i >= 0 && i < n ? spots(count: n, in: pivot)[i] : backPoint(in: pivot))
        burst(at: at, in: box, big: left == 0 && total > 0)
    }

    /// Точки вдоль спины: от холки к хвосту, чуть вразброс по бокам.
    private static func spots(count n: Int, in pivot: Entity) -> [SIMD3<Float>] {
        let b = bounds(in: pivot)
        let y = b.min.y + b.extents.y * backRatio
        let zHead = b.center.z + b.extents.z * 0.10
        let zTail = b.center.z - b.extents.z * 0.30
        return (0..<n).map { i in
            let k = (Float(i) + 0.5) / Float(n)
            let x: Float = i % 2 == 0 ? -0.018 : 0.018
            return SIMD3<Float>(x, y, zHead + (zTail - zHead) * k)
        }
    }

    private static func backPoint(in pivot: Entity) -> SIMD3<Float> {
        let b = bounds(in: pivot)
        return SIMD3<Float>(0, b.min.y + b.extents.y * backRatio, b.center.z - b.extents.z * 0.1)
    }

    private static func bounds(in pivot: Entity) -> BoundingBox {
        let body = pivot.children.first { $0.name == PetModel.bodyName }
        let b = (body ?? pivot).visualBounds(relativeTo: pivot)
        if b.extents.y > 0 { return b }
        return BoundingBox(min: SIMD3<Float>(-0.1, 0, -0.22), max: SIMD3<Float>(0.1, 0.45, 0.3))
    }

    /// Три шерстинки и пара искр вверх и в стороны; через 0,7 с исчезают. big — финал: искр больше.
    private static func burst(at p: SIMD3<Float>, in box: Entity, big: Bool) {
        var parts: [Entity] = []
        let hair = SimpleMaterial(color: PetRoom.color(0xe39a55), roughness: 0.9, isMetallic: false)
        for _ in 0..<3 {
            let e = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.003, 0.003, 0.03)), materials: [hair])
            e.orientation = simd_quatf(angle: Float.random(in: 0...(2 * .pi)), axis: SIMD3<Float>(0, 1, 0))
            parts.append(e)
        }
        let spark = UnlitMaterial(color: PetRoom.color(0xfff3c4))
        // Волна 31: с Reduce Motion искры не летят — шерстинки остаются, клочок снят видно и так.
        for _ in 0..<(UIAccessibility.isReduceMotionEnabled ? 0 : (big ? 6 : 2)) {
            parts.append(ModelEntity(mesh: .generateSphere(radius: 0.007), materials: [spark]))
        }
        for e in parts {
            e.position = p + SIMD3<Float>(0, 0.01, 0)
            box.addChild(e)
            var to = e.transform
            to.translation = p + SIMD3<Float>(Float.random(in: -0.07...0.07),
                                              Float.random(in: 0.07...0.15),
                                              Float.random(in: -0.05...0.05))
            to.rotation = simd_quatf(angle: Float.random(in: -1.5...1.5), axis: SIMD3<Float>(1, 0, 0)) * e.orientation
            to.scale = SIMD3<Float>(repeating: 0.3)
            _ = e.move(to: to, relativeTo: box, duration: 0.65, timingFunction: .easeOut)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            for e in parts { e.removeFromParent() }
        }
    }
}
