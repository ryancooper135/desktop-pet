// Волна 34 G: настоящий двор в 3D — сцена экрана «Двор» из сейва, а не из ползунков превью (YardStage).
// Слои яруса — по купленным плитам (порядок конфига = порядок YardArtTier.plates), станции — по f.yard.stations
// на своём уровне. Волна 35 M: таблички «+N/ч» — в самой сцене (YardPlate3D), золотая табличка станции — рамка
// и плашка из золота на плите-основании, пёс и тиканье монет — YardDogLive (YardLiveComponent на корне).

import RealityKit
import SwiftUI
@preconcurrency import PetCore

extension YardArtStation {
    /// Станция модели → id станции в economy.json (yard.stations).
    var configId: String {
        switch self {
        case .dryer: return "dryer"
        case .bonePatch: return "bones"
        case .porridge: return "porridge"
        case .wheel: return "spinner"
        case .oven: return "pies"
        case .photo: return "photo"
        case .conveyor: return "sausage"
        case .mill: return "mill"
        }
    }
}

@MainActor
enum YardLive {
    /// Камера по ярусу: та же, что в превью «двор до яруса N».
    struct Cam {
        let target: SIMD3<Float>
        let eye: SIMD3<Float>
        let fov: Float
    }

    static func camera(tier: Int) -> Cam {
        switch tier {
        case 0: return Cam(target: SIMD3(0, 0.55, -1.5), eye: SIMD3(0, 1.05, 0.15), fov: 40)
        case 1: return Cam(target: SIMD3(0, 0.15, -0.8), eye: SIMD3(0, 1.7, 1.6), fov: 44)
        case 2: return Cam(target: SIMD3(0, 0.1, -0.4), eye: SIMD3(0, 2.1, 2.5), fov: 46)
        default: return Cam(target: SIMD3(0, 0, -0.35), eye: SIMD3(0, 3.3, 3.9), fov: 50)
        }
    }

    /// Сколько плит яруса k куплено подряд с начала (подложка рисует купленное по порядку §1).
    static func bought(_ s: YardState, tier k: Int, _ cfg: YardConfig = .shared) -> Int {
        var n = 0
        for p in cfg.plates where p.tier == k {
            guard s.owns(p.id) else { break }
            n += 1
        }
        return min(n, YardArtTier.plates.indices.contains(k) ? YardArtTier.plates[k].count : n)
    }

    /// Станция на сцене: где стоит, какого размера и на каком уровне.
    struct Spot: Hashable {
        let id: String
        let at: SIMD3<Float>
        let scale: Float
        let level: Int
    }

    /// Поставленные станции открытых ярусов.
    static func spots(_ s: YardState, tier: Int) -> [Spot] {
        var out: [Spot] = []
        for k in 0...min(max(tier, 0), YardArtTier.slots.count - 1) {
            for slot in YardArtTier.slots[k] {
                guard let lv = s.stations[slot.station.configId] else { continue }
                out.append(Spot(id: slot.station.configId, at: slot.at, scale: slot.scale, level: lv))
            }
        }
        return out
    }

    /// Имя сущности станции в сцене — по нему находим её для «выскока» после покупки.
    static func name(_ id: String) -> String { "yard.live.\(id)" }

    /// Что в сцене живёт кроме станций: доход (таблички и тиканье), пёс.
    struct Live {
        /// Доход станций в монетах в час (с уровнем пса, помощником и золотом).
        var rates: [YardTickRate] = []
        var mode: YardDogMode = .absent
        /// Reduce Motion: пёс отдыхает на месте.
        var calm = false
        /// PET_YARD_DOG (UI-тест).
        var forced: String?
    }

    /// Сцена: слои 0…max(ярус, 1) (за подоконником — пустырь), станции, таблички, свет и камера.
    /// Пса сцена не ждёт: YardDogLive.model() грузит его отдельно, экран сажает через attach.
    /// district (волна 36 Q) — квартал после переезда: свои земля, плиты, забор и декор; станции те же.
    /// Небо — фон экрана: `district.skyColor(night:)`. Под UI-тестом район задаёт PET_YARD_DISTRICT.
    /// weather (волна 39 D) — погода в квартале (Weather.now(in:)): приглушённый свет и капли или хлопья.
    static func scene(_ s: YardState, tier: Int, fill: Float, night: Bool, brushed: Bool,
                      district: YardDistrict = .street, weather: WeatherKind = .clear, live: Live = Live()) -> Entity {
        let district = YardDistrict.forced ?? district
        let world = Entity()
        world.name = "yardLive"
        // Корень «живёт» (нулевой пульс): часы двора идут, даже если станций ещё нет.
        world.components.set(YardArtMotionComponent(motion: .pulse(amount: 0, period: 1, phase: 0), base: .zero))
        let top = min(max(tier, 1), YardArtTier.plates.count - 1)
        var plates: [Int] = []
        for k in 0...top {
            let b = k <= tier ? bought(s, tier: k) : 0
            plates.append(b)
            world.addChild(YardArtStage.entity(YardArtTier.layer(k, bought: b, district: district)))
        }
        if !district.decor.isEmpty {
            world.addChild(YardArtStage.entity(YardArtTier.decor(district, top: top, bought: plates, night: night)))
        }
        let cam = camera(tier: tier)
        let all = spots(s, tier: tier)
        for spot in all {
            guard let st = YardArtStation.allCases.first(where: { $0.configId == spot.id }) else { continue }
            let e = YardArtStage.entity(YardArt.station(st, level: spot.level, fill: fill, night: night, brushed: brushed,
                                                                district: district))
            e.name = name(spot.id)
            e.position = spot.at
            e.scale = SIMD3<Float>(repeating: spot.scale)
            let gold = s.gold.contains(spot.id)
            if gold { e.addChild(YardPlate3D.goldTrim()) }
            world.addChild(e)
            if let r = live.rates.first(where: { $0.id == spot.id }) {
                let top = spot.at + SIMD3<Float>(0, 0.62 * spot.scale, 0)
                world.addChild(YardPlate3D.make(YardText.perHour(r.rate), at: top, cam: cam, gold: gold, id: spot.id))
            }
        }
        world.addChild(YardArtStage.camera(target: cam.target, eye: cam.eye, fov: cam.fov))
        world.addChild(PetRoom.lights())
        // Ночью — лунный свет, тинт и тёплые огни (волна 38 B); пёс садится позже и тинта не получает.
        // Погода (волна 39 D): пасмурно — свет приглушён, дождь или снег — коробка капель перед камерой.
        YardLight.apply(night: night, gloom: WeatherConfig.shared.gloom(of: weather),
                        lamps: YardLight.lamps(district, top: top, bought: plates, night: night), to: world)
        if let fx = WeatherFx.yard(weather, target: cam.target, eye: cam.eye, fov: cam.fov, night: night,
                                   calm: live.calm) {
            world.addChild(fx)
        }
        let rest = YardDogLive.rest(tier: tier)
        world.components.set(YardLiveComponent(mode: live.mode, spots: YardDogLive.spots(all), rest: rest.at,
                                               dogScale: rest.scale, night: night, brushed: brushed, calm: live.calm,
                                               forced: live.forced, rates: live.rates))
        return world
    }

    /// Держатель мира в RealityView экрана: в имени — ключ сцены (всё видимое), мир внутри меняется, когда ключ
    /// другой. Сам вид не пересоздаётся.
    private static let holderPrefix = "yard.holder#"

    static func isHolder(_ e: Entity) -> Bool { e.name.hasPrefix(holderPrefix) }

    /// probe — имя сцены для UI-теста (YardFrame): под тестом мир помечается, и экран знает, что он уже нарисован.
    static func swap(in holder: Entity, key: String, probe: String? = nil, build: @MainActor () -> Entity) {
        let name = holderPrefix + key
        guard holder.name != name else { return }
        holder.name = name
        for child in Array(holder.children) { child.removeFromParent() }
        let world = build()
        if let probe, Env.isUITest { YardFrame.mark(world, probe: probe, key: key) }
        holder.addChild(world)
    }

    /// Новая станция «выскакивает»: из точки до полного размера с перелётом (кривая easeOutBack).
    static func pop(_ id: String, in world: Entity, scale: Float) {
        guard let e = world.findEntity(named: name(id)) else { return }
        var to = e.transform
        to.scale = SIMD3<Float>(repeating: scale)
        e.scale = SIMD3<Float>(repeating: scale * 0.05)
        e.move(to: to, relativeTo: e.parent, duration: 0.55,
               timingFunction: .cubicBezier(controlPoint1: SIMD2(0.34, 1.56), controlPoint2: SIMD2(0.64, 1)))
    }

    /// Точка сцены → точка на экране размера size (камера смотрит из eye в target, fov — по вертикали).
    /// nil — точка за камерой.
    nonisolated static func project(_ p: SIMD3<Float>, cam: Cam, size: CGSize) -> CGPoint? {
        guard size.width > 0, size.height > 0 else { return nil }
        let f = YardArtMath.normalize(cam.target - cam.eye)
        let r = YardArtMath.normalize(YardArtMath.cross(f, SIMD3(0, 1, 0)))
        let u = YardArtMath.cross(r, f)
        let d = p - cam.eye
        let z = YardArtMath.dot(d, f)
        guard z > 0.01 else { return nil }
        let t = tan(cam.fov * .pi / 360)
        let aspect = Float(size.width / size.height)
        let sx = YardArtMath.dot(d, r) / (z * t * aspect)
        let sy = YardArtMath.dot(d, u) / (z * t)
        return CGPoint(x: size.width / 2 * CGFloat(1 + sx), y: size.height / 2 * CGFloat(1 - sy))
    }
}

/// Табличка «+N/ч» над станцией прямо в сцене: светлая доска с тёмными цифрами, без света и теней
/// (читается и ночью), всегда лицом к экрану. Размер — от расстояния до камеры: на любом ярусе как ~12 pt.
/// Золотая станция — доска цвета монеты.
@MainActor
enum YardPlate3D {
    static let cream: UInt32 = 0xfdf6ea
    static let ink: UInt32 = 0x4a3b33
    /// Высота строки на экране — доля высоты кадра.
    static let screenShare: Float = 0.055

    private static var meshes: [String: MeshResource] = [:]

    static func name(_ id: String) -> String { "yard.plate.\(id)" }

    /// Доля пути от станции к камере: табличка встаёт на луче взгляда ближе к зрителю — на экране там же и того же
    /// размера, но фонарь, ограда и соседние станции её больше не закрывают.
    static let pull: Float = 0.45

    static func make(_ text: String, at anchor: SIMD3<Float>, cam: YardLive.Cam, gold: Bool, id: String) -> Entity {
        let root = Entity()
        root.name = name(id)
        let p = anchor + (cam.eye - anchor) * pull
        root.position = p
        // Плоскость таблички параллельна кадру: лицом против взгляда камеры.
        let f = YardArtMath.normalize(cam.target - cam.eye)
        let d = -f
        let yaw = atan2(d.x, d.z)
        let pitch = -asin(max(-1, min(1, d.y)))
        root.orientation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
        let dist = YardArtMath.dot(p - cam.eye, f)
        let k = max(0.05, screenShare * 2 * dist * tan(cam.fov * .pi / 360)) / 0.1
        root.scale = SIMD3<Float>(repeating: k)

        let mesh = textMesh(text)
        let b = mesh.bounds
        let glyphs = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: PetRoom.color(ink))])
        glyphs.position = SIMD3(-b.center.x, -b.center.y, 0.004)
        let w = b.extents.x + 0.07, h = max(b.extents.y, 0.07) + 0.04
        let board = ModelEntity(mesh: .generatePlane(width: w, height: h, cornerRadius: h / 2),
                                materials: [UnlitMaterial(color: PetRoom.color(gold ? YardArtColors.coin : cream))])
        PetRoom.noShadow(board)
        PetRoom.noShadow(glyphs)
        // Ночью табличка не темнеет вместе с двором (YardLight → RoomLighting: RoomGlow без тинта).
        RoomLighting.registerOnce()
        board.components.set(RoomGlow())
        glyphs.components.set(RoomGlow())
        root.addChild(board)
        root.addChild(glyphs)
        return root
    }

    /// Меш строки при кегле 0,1 м (масштаб — у корня таблички), один на строку.
    private static func textMesh(_ text: String) -> MeshResource {
        if let m = meshes[text] { return m }
        let m = MeshResource.generateText(text, extrusionDepth: 0.002,
                                          font: .systemFont(ofSize: 0.1, weight: .heavy))
        meshes[text] = m
        return m
    }

    /// Золотая табличка станции: рамка из золота по краю плиты-основания и плашка спереди (в координатах станции).
    static func goldTrim() -> Entity {
        let root = Entity()
        root.name = "yard.gold"
        var mat = PetRoom.matteMaterial(YardArtColors.coin)
        mat.metallic = .init(floatLiteral: 0.35)
        mat.roughness = .init(floatLiteral: 0.4)
        func bar(_ size: SIMD3<Float>, _ at: SIMD3<Float>) {
            let e = ModelEntity(mesh: .generateBox(size: size), materials: [mat])
            e.position = at
            PetRoom.noShadow(e)
            root.addChild(e)
        }
        // Плита: x ±0,25, z −0,25…0,2, верх 0,03 — рамка чуть шире и выше.
        bar(SIMD3(0.54, 0.045, 0.025), SIMD3(0, 0.0225, 0.2075))
        bar(SIMD3(0.54, 0.045, 0.025), SIMD3(0, 0.0225, -0.2575))
        bar(SIMD3(0.025, 0.045, 0.44), SIMD3(0.2575, 0.0225, -0.025))
        bar(SIMD3(0.025, 0.045, 0.44), SIMD3(-0.2575, 0.0225, -0.025))
        // Плашка спереди, чуть наклонена к зрителю.
        let plaque = ModelEntity(mesh: .generateBox(width: 0.17, height: 0.075, depth: 0.012, cornerRadius: 0.006),
                                 materials: [mat])
        plaque.position = SIMD3(0, 0.07, 0.225)
        plaque.orientation = simd_quatf(angle: -0.35, axis: SIMD3(1, 0, 0))
        PetRoom.noShadow(plaque)
        root.addChild(plaque)
        return root
    }
}

extension YardDistrict {
    /// PET_YARD_DISTRICT=<район или номер> — только в UI-тесте: двор в этом квартале (снимки ui-36-district-*).
    /// Читается там, где строится сцена (YardLive.scene), экран двора о нём не знает.
    nonisolated static var forced: YardDistrict? {
        Env.isUITest ? parse(Env.value("PET_YARD_DISTRICT")) : nil
    }

    /// Небо района — фон под RealityView.
    func skyColor(night: Bool) -> Color { Color(hex: sky(night: night)) }
}

// MARK: - Готовность кадра для UI-теста (волна 41 H)

/// Под CI-симулятором RealityKit рисует 1–2 кадра в секунду, и фиксированная пауза перед снимком то хватает, то нет.
/// Под тестом (Env.isUITest) мир сцены помечается YardFrameMark; система считает кадры, которые он прожил в сцене,
/// и после нескольких кадров последний мир этой сцены считается нарисованным. Экран пишет это в accessibilityValue
/// («frame=ready»), тест ждёт его вместо паузы. Без тестового флага метки нет и система не регистрируется.
@MainActor
enum YardFrame {
    /// Сколько кадров мир должен прожить в сцене, чтобы считаться нарисованным.
    static let frames = 3

    private static var seq = 0
    private static var current: [String: (seq: Int, key: String)] = [:]
    private static var drawn: [String: Int] = [:]
    private static var registered = false

    /// Новый мир сцены probe (по ключу key): с этого момента она «ждёт кадра».
    static func mark(_ world: Entity, probe: String, key: String) {
        if !registered {
            registered = true
            YardFrameMark.registerComponent()
            YardFrameSystem.registerSystem()
        }
        seq += 1
        current[probe] = (seq, key)
        world.components.set(YardFrameMark(probe: probe, seq: seq))
    }

    /// Мир прожил нужное число кадров.
    static func drew(_ probe: String, seq: Int) {
        if seq > (drawn[probe] ?? 0) { drawn[probe] = seq }
    }

    /// Сцена ушла с экрана (RealityView снята): пока её не поставят заново, кадра нет.
    static func gone(_ probe: String) {
        current[probe] = nil
    }

    /// Последний мир сцены собран по этому ключу и уже нарисован.
    static func ready(_ probe: String, key: String) -> Bool {
        guard let c = current[probe], c.key == key else { return false }
        return (drawn[probe] ?? 0) >= c.seq
    }
}

struct YardFrameMark: Component {
    var probe: String
    var seq: Int
    var frames = 0
}

struct YardFrameSystem: System {
    private let query = EntityQuery(where: .has(YardFrameMark.self))

    init(scene: RealityKit.Scene) {}

    @MainActor func update(context: SceneUpdateContext) {
        for e in context.entities(matching: query, updatingSystemWhen: .rendering) {
            guard var m = e.components[YardFrameMark.self], m.frames < YardFrame.frames else { continue }
            m.frames += 1
            e.components.set(m)
            if m.frames >= YardFrame.frames { YardFrame.drew(m.probe, seq: m.seq) }
        }
    }
}

/// accessibilityValue сцены для UI-теста: «<tag>frame=ready|wait». Опрос раз в 0,3 с, пока сцена на экране;
/// новый ключ — снова «wait», пока новый мир не нарисуется. Без тестового флага — ничего не меняет.
struct YardFrameProbe: ViewModifier {
    let probe: String
    let key: String
    var tag: String = ""
    @State private var ready = false

    func body(content: Content) -> some View {
        if Env.isUITest {
            content
                .accessibilityValue(Text(tag + "frame=" + (ready ? "ready" : "wait")))
                .task(id: key) {
                    ready = false
                    while !Task.isCancelled {
                        let now = YardFrame.ready(probe, key: key)
                        if now != ready { ready = now }
                        try? await Task.sleep(for: .milliseconds(300))
                    }
                }
        } else {
            content
        }
    }
}
