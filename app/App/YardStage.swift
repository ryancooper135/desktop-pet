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
    /// Светящееся помечено RoomGlow: ночной тинт двора (YardLight, волна 38 B) его не трогает.
    static func entity(_ model: YardArtModel) -> Entity {
        RoomLighting.registerOnce()
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
                    e.components.set(RoomGlow())
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
    /// weather (волна 39 D) — погода превью: свет приглушён, капли или хлопья перед камерой; calm — Reduce Motion.
    /// season (волна 40 F) — сезонный акцент на подоконнике у вида яруса (SeasonDecor); под тестами — осень.
    static func scene(_ shot: YardArtShot, level: Int, fill: Float, night: Bool, progress: Int,
                      district: YardDistrict = .street, weather: WeatherKind = .clear, calm: Bool = false,
                      season: Season = Seasons.now()) -> Entity {
        let world = Entity()
        world.name = "yardArt"
        // Купленные плиты по слоям — для ночных огней (у .station их нет: фонаря двора в кадре нет).
        var lit: [Int] = []
        // Камера кадра: в неё смотрит и коробка с дождём (WeatherFx.yard).
        let cam: (target: SIMD3<Float>, eye: SIMD3<Float>, fov: Float)
        // Корень тоже «живёт» (нулевой пульс): часы и счётчик кадров идут, даже если на подложке ни одной станции.
        world.components.set(YardArtMotionComponent(motion: .pulse(amount: 0, period: 1, phase: 0), base: .zero))
        switch shot {
        case .station(let s):
            let ground = ModelEntity(mesh: .generatePlane(width: 1.6, depth: 1.4),
                                     materials: [PetRoom.matteMaterial(YardArtColors.grass)])
            ground.position = SIMD3<Float>(0, -0.001, -0.05)
            PetRoom.noShadow(ground)
            world.addChild(ground)
            world.addChild(entity(YardArt.station(s, level: level, fill: fill, night: night, brushed: night,
                                                            district: district)))
            cam = (SIMD3(0, 0.19, -0.03), SIMD3(0.45, 0.55, 1.1), 36)
            world.addChild(camera(target: cam.target, eye: cam.eye, fov: cam.fov))
        case .tier(let shown):
            // Ярус 0 — подоконник, а за ним пустырь: слой 1 без купленных плит.
            let plates = (0..<YardArtTier.plates.count).map { YardArtTier.bought($0, shown: shown, progress: progress) }
            lit = plates
            if !district.decor.isEmpty {
                world.addChild(entity(YardArtTier.decor(district, top: max(shown, 1), bought: plates, night: night)))
            }
            for k in 0...max(shown, 1) {
                let b = plates[k]
                world.addChild(entity(YardArtTier.layer(k, bought: b, district: district)))
                guard k <= shown else { continue }
                for slot in YardArtTier.slots[k] where b > slot.plate {
                    let st = entity(YardArt.station(slot.station, level: level, fill: fill, night: night,
                                                         district: district))
                    st.position = slot.at
                    st.scale = SIMD3<Float>(repeating: slot.scale)
                    world.addChild(st)
                }
            }
            world.addChild(SeasonDecor.yard(season))
            switch shown {
            case 0: cam = (SIMD3(0, 0.55, -1.5), SIMD3(0, 1.05, 0.15), 40)
            case 1: cam = (SIMD3(0, 0.15, -0.8), SIMD3(0, 1.7, 1.6), 44)
            case 2: cam = (SIMD3(0, 0.1, -0.4), SIMD3(0, 2.1, 2.5), 46)
            default: cam = (SIMD3(0, 0, -0.35), SIMD3(0, 3.3, 3.9), 50)
            }
            world.addChild(camera(target: cam.target, eye: cam.eye, fov: cam.fov))
        }
        world.addChild(PetRoom.lights())
        // Ночью — лунный свет, тинт и тёплые огни (волна 38 B). Станция крупно — без огней: фонаря и района рядом нет.
        let lamps: [YardNightLamp]
        if case .tier(let shown) = shot {
            lamps = YardLight.lamps(district, top: max(shown, 1), bought: lit, night: night)
        } else {
            lamps = []
        }
        YardLight.apply(night: night, gloom: WeatherConfig.shared.gloom(of: weather), lamps: lamps, to: world)
        if let fx = WeatherFx.yard(weather, target: cam.target, eye: cam.eye, fov: cam.fov, night: night, calm: calm) {
            world.addChild(fx)
        }
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
/// Чипы погоды yard.weather.<kind> (волна 39 D): ясно, пасмурно, дождь, снег — и в превью, и в переезде.
struct YardArtDemoScreen: View {
    @State private var shot: YardArtShot = .station(.dryer)
    @State private var level = 1
    @State private var fillStep = 2
    @State private var night = false
    @State private var progress = 0
    @State private var district: YardDistrict = YardDistrict.forced ?? .street
    @State private var moving = false
    @State private var weather: WeatherKind = .clear
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Экран въехал (навигация закончила анимацию) — только тогда создаём RealityView.
    @State private var onScreen = false

    private var fill: Float { Float(fillStep) / 2 }

    var body: some View {
        let shot = self.shot, level = self.level, fill = self.fill, night = self.night, progress = self.progress
        let district = self.district, weather = self.weather, calm = reduceMotion
        let worst = Self.worst
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Как на экране двора (волна 35 N): один RealityView, мир меняется в держателе по ключу, без .id.
                // И рождается он уже на виду — после въезда экрана: вид, созданный за краем, на CI оставался пустым.
                let key = "\(shot)#\(level)#\(fill)#\(night)#\(progress)#\(district)#\(weather)#\(calm)"
                let build: @MainActor @Sendable () -> Entity = {
                    YardArtStage.scene(shot, level: level, fill: fill, night: night, progress: progress, district: district,
                                       weather: weather, calm: calm)
                }
                Group {
                    // Под экраном переезда двор не рисуем: на CI два RealityView сразу — 2 кадра/с, фургон не появлялся.
                    if onScreen && !moving {
                        RealityView { content in
                            content.camera = .virtual
                            YardArtSystem.registerOnce()
                            let holder = Entity()
                            YardLive.swap(in: holder, key: key, probe: "yard.demo", build: build)
                            content.add(holder)
                        } update: { content in
                            guard let holder = content.entities.first(where: { YardLive.isHolder($0) }) else { return }
                            YardLive.swap(in: holder, key: key, probe: "yard.demo", build: build)
                        }
                        .onDisappear { YardFrame.gone("yard.demo") }
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 330)
                .background((district == .street ? (night ? Color(hex: 0x2a3350) : PetPalette.stageBg)
                             : district.skyColor(night: night)).overlay(WeatherVeil(kind: weather)))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                // UI-тест (волна 41 H): что показано и нарисован ли уже этот мир — «shot=st.3,lv=2,district=street,frame=ready».
                // Волна 45 P: ещё плиты и ночь — тест ждёт, что «− плита»/«+ плита»/«ночь» приняты, а не паузу после тапа.
                .accessibilityElement(children: .ignore)
                .modifier(YardFrameProbe(probe: "yard.demo", key: key,
                                         tag: "shot=\(Self.tag(shot)),lv=\(level),district=\(district.rawValue),"
                                            + "plates=\(progress),night=\(night ? 1 : 0),"))
                .accessibilityIdentifier("yard.scene")

                caption(worst: worst)
                controls
            }
            .padding(16)
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .navigationTitle("Двор 3D")
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            onScreen = true
        }
        // Переезд — переходом, как само превью: на CI RealityView под fullScreenCover так и не нарисовал ни кадра
        // (три прогона), а в экране, въехавшем переходом, с задержкой рисует.
        .navigationDestination(isPresented: $moving) {
            YardMoveView(from: district, to: district.next, night: night, weather: weather)
                .toolbar(.hidden, for: .navigationBar)
                .overlay(alignment: .topTrailing) {
                    Button("Закрыть") { moving = false }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(16)
                        .accessibilityIdentifier("yard.move.close")
                }
        }
    }

    /// Вид для UI-теста: «st.<номер станции>» или «tier.<ярус>».
    private static func tag(_ shot: YardArtShot) -> String {
        switch shot {
        case .station(let s): return "st.\(s.rawValue)"
        case .tier(let n): return "tier.\(n)"
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
                let tris = YardArt.station(s, level: level, fill: fill, night: night, brushed: night,
                                           district: district).triangles
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
            row {
                ForEach(Self.weathers, id: \.self) { w in
                    chip(Self.short(w), on: weather == w, id: "yard.weather.\(w.rawValue)") { weather = w }
                }
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

    /// Погода превью: гроза — тот же дождь, только гуще и косее, отдельного чипа не нужно.
    static let weathers: [WeatherKind] = [.clear, .cloudy, .rain, .snow]

    private static func short(_ w: WeatherKind) -> String {
        switch w {
        case .clear: return "ясно"
        case .cloudy: return "пасмурно"
        case .rain, .storm: return "дождь"
        case .snow: return "снег"
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
