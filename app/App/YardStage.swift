// Двор в 3D (волна 33 F): модели YardModels → сущности RealityKit, циклы станций — система YardArtSystem,
// и превью «Двор 3D» в каталоге (Настройки → Для разработки). К настоящему экрану не подключено: это макет
// для вкуса и бюджета (§2: ≤400 треугольников на станцию), двор как экран — волна 34.

import RealityKit
import SwiftUI
import UIKit

// MARK: - ECS

/// Узел с циклом: место в модели и движение. Поза считается от общих часов двора — все станции в такт.
struct YardArtMotionComponent: Component {
    var motion: YardArtMotion
    var base: SIMD3<Float>
}

struct YardArtSystem: System {
    private let query = EntityQuery(where: .has(YardArtMotionComponent.self))

    /// Часы двора и кадров в секунду по последней секунде (для превью и UI-теста; считаются только пока двор в сцене).
    @MainActor static var clock: Double = 0
    @MainActor static var fps = 0
    @MainActor private static var frames = 0
    @MainActor private static var window: Double = 0

    init(scene: RealityKit.Scene) {}

    @MainActor func update(context: SceneUpdateContext) {
        let raw = context.deltaTime
        guard raw > 0 else { return }
        var any = false
        let now = Self.clock + min(raw, 0.1)
        for e in context.entities(matching: query, updatingSystemWhen: .rendering) {
            guard let c = e.components[YardArtMotionComponent.self] else { continue }
            any = true
            let p = c.motion.pose(at: now)
            // Масштаб 0 — «спрятан»: выключаем сущность, а не сжимаем в точку (вырожденная матрица).
            let shown = p.scale > 0.002
            if e.isEnabled != shown { e.isEnabled = shown }
            guard shown else { continue }
            e.position = c.base + p.offset
            e.scale = SIMD3<Float>(repeating: p.scale)
            e.orientation = simd_quatf(angle: p.angle, axis: p.axis)
        }
        guard any else { return }
        Self.clock = now
        Self.frames += 1
        Self.window += raw
        if Self.window >= 1 {
            Self.fps = Int((Double(Self.frames) / Self.window).rounded())
            Self.frames = 0
            Self.window = 0
        }
    }

    @MainActor private static var registered = false

    @MainActor static func registerOnce() {
        guard !registered else { return }
        registered = true
        YardArtMotionComponent.registerComponent()
        YardArtSystem.registerSystem()
    }
}

// MARK: - Сущности

/// Что показывает превью: одна станция крупно или двор до яруса N.
enum YardArtShot: Hashable, Sendable {
    case station(YardArtStation)
    case tier(Int)
}

@MainActor
enum YardArtStage {
    /// Модель → дерево сущностей: узел — Entity (движение двигает его), цвет — ModelEntity со своим мешем.
    /// Светящееся — UnlitMaterial без тени, остальное — матовый материал комнаты (PetRoom.matteMaterial).
    static func entity(_ model: YardArtModel) -> Entity {
        let root = Entity()
        root.name = model.name
        for node in model.nodes where !node.meshes.isEmpty {
            let n = Entity()
            n.name = node.name
            n.position = node.at
            if let motion = node.motion {
                n.components.set(YardArtMotionComponent(motion: motion, base: node.at))
            }
            for (paint, mesh) in node.meshes.sorted(by: { ($0.key.hex, $0.key.glow ? 1 : 0) < ($1.key.hex, $1.key.glow ? 1 : 0) }) {
                var d = MeshDescriptor(name: node.name)
                d.positions = MeshBuffers.Positions(mesh.positions)
                d.normals = MeshBuffers.Normals(mesh.normals)
                d.primitives = .triangles(mesh.indices)
                guard let res = try? MeshResource.generate(from: [d]) else { continue }
                let e: ModelEntity
                if paint.glow {
                    e = ModelEntity(mesh: res, materials: [UnlitMaterial(color: PetRoom.color(paint.hex))])
                    PetRoom.noShadow(e)
                } else {
                    e = ModelEntity(mesh: res, materials: [PetRoom.matteMaterial(paint.hex)])
                }
                n.addChild(e)
            }
            root.addChild(n)
        }
        return root
    }

    /// Сцена превью целиком: модели, земля под станцией, свет комнаты и камера под кадр.
    /// district (волна 36 Q) — квартал двора: подложки в его цветах и его декор.
    static func scene(_ shot: YardArtShot, level: Int, fill: Float, night: Bool, progress: Int,
                      district: YardDistrict = .street) -> Entity {
        let world = Entity()
        world.name = "yardArt"
        // Корень тоже «живёт» (нулевой пульс): часы и счётчик кадров идут, даже если на подложке ни одной станции.
        world.components.set(YardArtMotionComponent(motion: .pulse(amount: 0, period: 1, phase: 0), base: .zero))
        switch shot {
        case .station(let s):
            let ground = ModelEntity(mesh: .generatePlane(width: 1.6, depth: 1.4),
                                     materials: [PetRoom.matteMaterial(YardArtColors.grass)])
            ground.position = SIMD3<Float>(0, -0.001, -0.05)
            PetRoom.noShadow(ground)
            world.addChild(ground)
            world.addChild(entity(YardArt.station(s, level: level, fill: fill, night: night, brushed: night)))
            world.addChild(camera(target: SIMD3(0, 0.19, -0.03), eye: SIMD3(0.45, 0.55, 1.1), fov: 36))
        case .tier(let shown):
            // Ярус 0 — подоконник, а за ним пустырь: слой 1 без купленных плит.
            let plates = (0..<YardArtTier.plates.count).map { YardArtTier.bought($0, shown: shown, progress: progress) }
            if !district.decor.isEmpty {
                world.addChild(entity(YardArtTier.decor(district, top: max(shown, 1), bought: plates, night: night)))
            }
            for k in 0...max(shown, 1) {
                let b = plates[k]
                world.addChild(entity(YardArtTier.layer(k, bought: b, district: district)))
                guard k <= shown else { continue }
                for slot in YardArtTier.slots[k] where b > slot.plate {
                    let st = entity(YardArt.station(slot.station, level: level, fill: fill, night: night))
                    st.position = slot.at
                    st.scale = SIMD3<Float>(repeating: slot.scale)
                    world.addChild(st)
                }
            }
            let cam: (target: SIMD3<Float>, eye: SIMD3<Float>, fov: Float)
            switch shown {
            case 0: cam = (SIMD3(0, 0.55, -1.5), SIMD3(0, 1.05, 0.15), 40)
            case 1: cam = (SIMD3(0, 0.15, -0.8), SIMD3(0, 1.7, 1.6), 44)
            case 2: cam = (SIMD3(0, 0.1, -0.4), SIMD3(0, 2.1, 2.5), 46)
            default: cam = (SIMD3(0, 0, -0.35), SIMD3(0, 3.3, 3.9), 50)
            }
            world.addChild(camera(target: cam.target, eye: cam.eye, fov: cam.fov))
        }
        world.addChild(PetRoom.lights())
        return world
    }

    static func camera(target: SIMD3<Float>, eye: SIMD3<Float>, fov: Float) -> Entity {
        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = fov
        cam.look(at: target, from: eye, relativeTo: nil)
        return cam
    }
}

// MARK: - Превью

/// «Двор 3D»: восемь станций и пять ярусов, вид по уровню, копилка, ночь, плиты яруса.
/// Подписи — для UI-теста: yard.tris (треугольники станции), yard.maxTris (худшая станция), yard.fps.
struct YardArtDemoScreen: View {
    @State private var shot: YardArtShot = .station(.dryer)
    @State private var level = 1
    @State private var fillStep = 2
    @State private var night = false
    @State private var progress = 0
    @State private var district: YardDistrict = YardDistrict.forced ?? .street
    @State private var moving = false

    private var fill: Float { Float(fillStep) / 2 }

    var body: some View {
        let shot = self.shot, level = self.level, fill = self.fill, night = self.night, progress = self.progress
        let district = self.district
        let worst = Self.worst
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                RealityView { content in
                    content.camera = .virtual
                    YardArtSystem.registerOnce()
                    content.add(YardArtStage.scene(shot, level: level, fill: fill, night: night, progress: progress,
                                                   district: district))
                }
                .id("\(shot)#\(level)#\(fill)#\(night)#\(progress)#\(district)")
                .frame(height: 330)
                .background(district == .street ? (night ? Color(hex: 0x2a3350) : PetPalette.stageBg)
                            : district.skyColor(night: night))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("yard.scene")

                caption(worst: worst)
                controls
            }
            .padding(16)
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .navigationTitle("Двор 3D")
        .fullScreenCover(isPresented: $moving) {
            YardMoveView(from: district, to: district.next)
                .overlay(alignment: .topTrailing) {
                    Button("Закрыть") { moving = false }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(16)
                        .accessibilityIdentifier("yard.move.close")
                }
        }
    }

    /// Худший декор района — один раз на экран.
    private static let worstDecor = YardArtTier.worstDecorTriangles()

    /// Худшая станция по всем видам — одна на экран, считается один раз.
    private static let worst = YardArt.worstTriangles()

    @ViewBuilder private func caption(worst: (station: YardArtStation, level: Int, triangles: Int)) -> some View {
        let mono = Font.system(size: 13, weight: .semibold, design: .monospaced)
        VStack(alignment: .leading, spacing: 4) {
            switch shot {
            case .station(let s):
                let tris = YardArt.station(s, level: level, fill: fill, night: night, brushed: night).triangles
                Text("\(s.rawValue). \(s.title)").font(.headline).foregroundStyle(PetPalette.ink)
                Text("ур. \(level) · \(YardArtLook.of(level: level).title) · +\(s.rate(level: level))/ч")
                    .font(mono).foregroundStyle(PetPalette.soft)
                Text("треугольников \(tris) из \(YardArt.stationBudget)")
                    .font(mono).foregroundStyle(PetPalette.soft)
                    .accessibilityIdentifier("yard.tris")
            case .tier(let n):
                let plates = YardArtTier.plates[n]
                let shown = max(0, min(plates.count, progress))
                Text("Ярус \(n) · \(YardArtTier.names[n])").font(.headline).foregroundStyle(PetPalette.ink)
                Text(shown < plates.count ? "плит \(shown)/\(plates.count), дальше: \(plates[shown])"
                     : "плит \(shown)/\(plates.count), ярус собран")
                    .font(mono).foregroundStyle(PetPalette.soft)
                let bought = (0..<YardArtTier.plates.count).map { YardArtTier.bought($0, shown: n, progress: progress) }
                let decor = YardArtTier.decor(district, top: max(n, 1), bought: bought, night: night).triangles
                let worstDecor = Self.worstDecor
                Text("\(district.title) · декор \(decor), худший \(worstDecor.triangles) (\(worstDecor.district.rawValue))")
                    .font(mono).foregroundStyle(PetPalette.soft)
                    .accessibilityIdentifier("yard.districtTris")
            }
            Text("худшая станция \(worst.triangles) (\(worst.station.rawValue), ур. \(worst.level))")
                .font(mono).foregroundStyle(PetPalette.soft)
                .accessibilityIdentifier("yard.maxTris")
            TimelineView(.periodic(from: .now, by: 1)) { ctx in YardArtFpsLabel(tick: ctx.date) }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            row {
                ForEach(YardArtStation.allCases, id: \.self) { s in
                    chip("\(s.rawValue)", on: shot == .station(s), id: "yard.st.\(s.rawValue)") { shot = .station(s) }
                }
            }
            row {
                ForEach(0..<5, id: \.self) { n in
                    chip("Я\(n)", on: shot == .tier(n), id: "yard.tier.\(n)") {
                        shot = .tier(n)
                        progress = YardArtTier.plates[n].count
                    }
                }
            }
            row {
                ForEach(1...5, id: \.self) { l in
                    chip("ур\(l)", on: level == l, id: "yard.lv.\(l)") { level = l }
                }
            }
            row {
                ForEach(0..<3, id: \.self) { f in
                    chip(["пусто", "½", "полно"][f], on: fillStep == f, id: "yard.fill.\(f)") { fillStep = f }
                }
                chip("ночь", on: night, id: "yard.night") { night.toggle() }
            }
            row {
                ForEach(YardDistrict.allCases, id: \.self) { d in
                    chip(Self.short(d), on: district == d, id: "yard.district.\(d.rawValue)") { district = d }
                }
                chip("Переезд", on: false, id: "yard.move") { moving = true }
            }
            if case .tier(let n) = shot {
                row {
                    chip("− плита", on: false, id: "yard.plate.minus") { progress = max(0, progress - 1) }
                    chip("+ плита", on: false, id: "yard.plate.plus") {
                        progress = min(YardArtTier.plates[n].count, progress + 1)
                    }
                }
            }
        }
    }

    /// Короткое имя района для чипа (в ряд помещаются четыре района и «Переезд»).
    private static func short(_ d: YardDistrict) -> String {
        switch d {
        case .street: return "улица"
        case .winter: return "зима"
        case .river: return "река"
        case .roof: return "крыша"
        }
    }

    private func row<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 6) { content() }
    }

    private func chip(_ title: String, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8)
                .frame(minWidth: 34, minHeight: 32)
                .background(on ? PetPalette.accent : PetPalette.card, in: Capsule())
                .foregroundStyle(on ? Color.white : PetPalette.ink)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// Кадров в секунду по часам двора (YardArtSystem.fps), перечитывается раз в секунду из TimelineView.
/// tick — дата тика: без входа SwiftUI считает метку той же и тело не пересчитывает (было «fps 0» навсегда).
private struct YardArtFpsLabel: View {
    let tick: Date

    var body: some View {
        Text("fps \(YardArtSystem.fps)")
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(PetPalette.soft)
            .accessibilityIdentifier("yard.fps")
    }
}
