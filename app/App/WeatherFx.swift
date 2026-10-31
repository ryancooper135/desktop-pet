// Погода в 3D (волна 39 D): капли и хлопья за окном комнаты и во дворе. Логика погоды — Shared/Weather.swift.
// Частиц мало (WeatherConfig.particles: в окне 12–18, во дворе 28–47), каждая — крупный ретро-брусок или ромбик
// на общем меше и материале. Падают по кругу в своей коробке: позиция — чистая функция часов группы
// (WeatherClock), без накопления и без физики. Reduce Motion — часы стоят: капли висят на месте, как на картинке.
// В комнате капли красит свет комнаты (вечером темнее), во дворе они светятся сами (RoomGlow) — цвет под ночь
// подбирается при сборке сцены, она и так пересобирается по ключу.

import SwiftUI
@preconcurrency import RealityKit

/// Капля или хлопок: падает от top вниз на height, по кругу.
struct WeatherDrop: Component {
    var top: SIMD3<Float>
    var height: Float
    /// Доля пути в момент 0.
    var phase: Float
    /// Доли пути в секунду.
    var speed: Float
    /// Снег качается по x: размах и частота (Гц). У дождя — косой снос slant на весь путь.
    var sway: Float = 0
    var swayRate: Float = 0
    var slant: Float = 0
}

/// Часы частиц на корне группы. still — Reduce Motion: часы стоят.
struct WeatherClock: Component {
    var t: Double = 0
    var still = false
}

struct WeatherFallSystem: System {
    private let query = EntityQuery(where: .has(WeatherClock.self))

    init(scene: RealityKit.Scene) {}

    @MainActor func update(context: SceneUpdateContext) {
        let dt = min(Double(context.deltaTime), 0.1)
        for root in context.entities(matching: query, updatingSystemWhen: .rendering) {
            guard var c = root.components[WeatherClock.self], !c.still, dt > 0 else { continue }
            c.t += dt
            root.components.set(c)
            for e in root.children {
                guard let d = e.components[WeatherDrop.self] else { continue }
                e.position = WeatherFx.position(d, t: c.t)
            }
        }
    }
}

@MainActor
enum WeatherFx {
    private static var registered = false

    static func registerOnce() {
        guard !registered else { return }
        registered = true
        WeatherDrop.registerComponent()
        WeatherClock.registerComponent()
        WeatherFallSystem.registerSystem()
        RoomWeatherShown.registerComponent()
    }

    /// Где частица в момент t: сверху вниз по кругу, снег качается, дождь чуть косит.
    nonisolated static func position(_ d: WeatherDrop, t: Double) -> SIMD3<Float> {
        let u0 = Double(d.phase) + t * Double(d.speed)
        let u = Float(u0 - u0.rounded(.down))
        let sway = d.sway == 0 ? 0 : d.sway * Float(sin((t * Double(d.swayRate) + Double(d.phase)) * 2 * .pi))
        return SIMD3(d.top.x + d.slant * u + sway, d.top.y - u * d.height, d.top.z)
    }

    /// Частицы в коробке: x и z — разброс, сверху top, падают на height. Расстановка детерминирована (seed) —
    /// одна и та же погода выглядит одинаково при каждом запуске и в снимках.
    /// size — длина капли (хлопок — size по диагонали), glow — светится сам (двор), иначе красится светом комнаты.
    static func group(_ kind: WeatherKind, count: Int, x: ClosedRange<Float>, z: ClosedRange<Float>, top: Float,
                      height: Float, size: Float, hex: UInt32, glow: Bool, still: Bool, seed: String,
                      cfg: WeatherConfig = .shared) -> Entity {
        registerOnce()
        let g = Entity()
        g.name = "weather.\(kind.rawValue)"
        g.components.set(WeatherClock(still: still))
        guard kind.falls, count > 0 else { return g }
        let snow = kind == .snow
        let mesh = self.mesh(snow: snow, size: size)
        let material = self.material(hex, opacity: snow ? 0.92 : 0.6)
        // Путь в секунду: дождь — rainFall высот коробки … чуть разный у каждой капли, снег — медленно.
        let base = Float(snow ? cfg.snowFall : cfg.rainFall) * (kind == .storm ? 1.35 : 1)
        // Косой дождь и качание снега не выводят частицу за коробку (в комнате — за раму окна).
        let slant = snow ? 0 : height * (kind == .storm ? 0.22 : 0.1)
        let sway = snow ? size * 0.9 : 0
        let lo = x.lowerBound + sway, hi = max(lo, x.upperBound - sway - slant)
        for i in 0..<count {
            let h = StableRandom.mix(StableHash.fnv1a("\(seed):\(kind.rawValue):\(i)"))
            func u(_ k: Int) -> Float { Float((h >> (UInt64(k) * 12)) & 0xfff) / 4096 }
            let e = ModelEntity(mesh: mesh, materials: [material])
            PetRoom.noShadow(e)
            if glow { e.components.set(RoomGlow()) }
            var d = WeatherDrop(top: SIMD3(lo + (hi - lo) * u(0), top,
                                           z.lowerBound + (z.upperBound - z.lowerBound) * u(1)),
                                height: height, phase: u(2), speed: base * (0.8 + 0.4 * u(3)))
            if snow {
                d.sway = sway
                d.swayRate = 0.25 + 0.3 * u(4)
                e.orientation = simd_quatf(angle: .pi / 4, axis: SIMD3(0, 0, 1))
            } else {
                // Ветер слегка сносит дождь вправо, в грозу сильнее: капля наклонена по ходу.
                d.slant = slant
                e.orientation = simd_quatf(angle: atan2(d.slant, d.height), axis: SIMD3(0, 0, 1))
            }
            e.components.set(d)
            e.position = position(d, t: 0)
            g.addChild(e)
        }
        return g
    }

    // Меши и материалы — общие: частицы одной погоды отличаются только местом.
    private struct Paint: Hashable { var hex: UInt32, opacity: Float }
    private struct Shape: Hashable { var snow: Bool, size: Float }
    private static var meshes: [Shape: MeshResource] = [:]
    private static var paints: [Paint: UnlitMaterial] = [:]

    private static func mesh(snow: Bool, size: Float) -> MeshResource {
        let key = Shape(snow: snow, size: size)
        if let m = meshes[key] { return m }
        // Капля — тонкий брусок (ретро, без сглаживания), хлопок — плоский квадрат, повёрнутый ромбом.
        let m: MeshResource = snow ? .generateBox(size: SIMD3(size * 0.7, size * 0.7, size * 0.15))
                                   : .generateBox(size: SIMD3(size * 0.12, size, size * 0.12))
        meshes[key] = m
        return m
    }

    private static func material(_ hex: UInt32, opacity: Float) -> UnlitMaterial {
        let key = Paint(hex: hex, opacity: opacity)
        if let m = paints[key] { return m }
        var m = UnlitMaterial(color: PetRoom.color(hex))
        m.blending = .transparent(opacity: .init(floatLiteral: opacity))
        paints[key] = m
        return m
    }

    // MARK: Двор

    /// Цвет частиц двора: светятся сами, поэтому ночью темнее и синее.
    nonisolated static func yardHex(_ kind: WeatherKind, night: Bool) -> UInt32 {
        switch kind {
        case .snow: night ? 0xc9d3f0 : 0xffffff
        default: night ? 0x6d7cab : 0x9fb8d8
        }
    }

    /// Вуаль на небо фона (SwiftUI): серость пасмурного неба, доля 0…1.
    nonisolated static func veil(_ kind: WeatherKind, cfg: WeatherConfig = .shared) -> Double {
        cfg.gloom(of: kind) * 0.35
    }
    nonisolated static let veilHex: UInt32 = 0x8a9099

    /// Дождь или снег во дворе: коробка перед камерой — между ней и точкой, куда она смотрит, по размеру кадра.
    /// nil — ничего не падает.
    static func yard(_ kind: WeatherKind, target: SIMD3<Float>, eye: SIMD3<Float>, fov: Float, night: Bool,
                     calm: Bool, cfg: WeatherConfig = .shared) -> Entity? {
        guard kind.falls else { return nil }
        let dir = eye - target
        let dist = (dir.x * dir.x + dir.y * dir.y + dir.z * dir.z).squareRoot()
        // Середина коробки — на 0,4 пути от цели к камере; полуразмер — сколько видно на этом расстоянии.
        let c = target + dir * 0.4
        let half = 0.6 * dist * tan(fov * .pi / 360) * 1.15
        let g = group(kind, count: cfg.particles(kind, room: false),
                      x: (c.x - half)...(c.x + half), z: (c.z - half * 0.6)...(c.z + half * 0.6),
                      top: c.y + half * 1.2, height: half * 2.6, size: (kind == .snow ? 0.022 : 0.05) * dist / 2.9,
                      hex: yardHex(kind, night: night), glow: true, still: calm, seed: "yard", cfg: cfg)
        g.name = yardName
        return g
    }

    static let yardName = "yard.weather"
}

// MARK: - Комната

/// Что сейчас за окном комнаты: погода, своё ли окошко (окна двора нет), стоят ли часы.
struct RoomWeatherShown: Component, Equatable {
    var kind: WeatherKind
    var plainWindow: Bool
    var still: Bool
}

@MainActor
enum RoomWeather {
    static let nodeName = "room.weather"

    /// Окна во двор ещё нет — капли в окне комнаты стиля B (PetRoom.baseWindowRect, волна 53): своё окошко
    /// больше не строим, оно и так висит на стене.
    static var plainWindow: RoomPlan.WallRect { PetRoom.baseWindowRect }
    static var plainFrame: Float { PetRoom.baseWindowFrame }

    /// Поставить погоду в комнату (узел room.weather в корне комнаты). То же, что уже стоит, — ничего не делает.
    /// true — узел перестроен: новым каплям нужен текущий свет комнаты (RoomLighting).
    @discardableResult
    static func apply(_ kind: WeatherKind, plainWindow: Bool, still: Bool, to room: Entity,
                      cfg: WeatherConfig = .shared) -> Bool {
        WeatherFx.registerOnce()
        let shown = RoomWeatherShown(kind: kind, plainWindow: plainWindow, still: still)
        let old = room.children.first(where: { $0.name == nodeName })
        if let old, old.components[RoomWeatherShown.self] == shown { return false }
        old?.removeFromParent()
        let node = Entity()
        node.name = nodeName
        node.components.set(shown)
        room.addChild(node)
        guard kind.falls else { return old != nil }
        let wallZ = RoomPlan.backWallZ
        let rect: RoomPlan.WallRect
        let frame: Float
        if plainWindow {
            rect = Self.plainWindow
            frame = plainFrame
        } else {
            rect = RoomPlan.window
            frame = RoomPlan.windowFrame
        }
        // Капли — внутри рамы, перед слоями «двора» (они до ~+0.03 от стены), за передом рамы (+0.035).
        let inX = (rect.minX + frame + 0.006)...(rect.maxX - frame - 0.006)
        let size: Float = kind == .snow ? 0.011 : 0.022
        let top = rect.maxY - frame - size / 2
        let height = rect.height - 2 * frame - size
        let z = wallZ + 0.032
        node.addChild(WeatherFx.group(kind, count: cfg.particles(kind, room: true), x: inX, z: z...z, top: top,
                                      height: height, size: size, hex: kind == .snow ? 0xffffff : 0x8fb3dc,
                                      glow: false, still: still, seed: "room", cfg: cfg))
        return true
    }
}

/// Серость пасмурного неба поверх цвета фона сцены двора (небо двора — фон экрана). Ясно — прозрачно.
struct WeatherVeil: View {
    var kind: WeatherKind

    var body: some View {
        Color(hex: WeatherFx.veilHex).opacity(WeatherFx.veil(kind)).allowsHitTesting(false)
    }
}
