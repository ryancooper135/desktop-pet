// Свет комнаты по времени суток и теме (волна 10): применяет RoomLight (app/Shared) к сцене.
// Состояние живёт компонентом RoomLightState на корне комнаты; система раз в несколько секунд сверяет
// фазу с часами и плавно ведёт текущую к ней — смена дня, вечера и ночи и смена темы идут без мигания.
// Что красим: свет key/fill/rim и лампа (дочерние "lights" комнаты), матовые вещи — множителем тинта
// от исходных материалов (RoomTintBase), небо в окне (RoomSky) — своим цветом, луна и звёзды (RoomNightSky)
// проявляются ночью. Светящиеся детали (RoomGlow: огонёк, камин, лампа-торшер) и питомец — без тинта.

import UIKit
@preconcurrency import RealityKit

/// Светится сам: тинт комнаты не трогает.
struct RoomGlow: Component {}
/// Небо в окне: красим не тинтом, а цветом неба фазы.
struct RoomSky: Component {}
/// Луна или звезда в окне: видна вечером и ночью (RoomLight.moon).
struct RoomNightSky: Component {
    var hex: UInt32
}
/// Исходные материалы вещи: красим всегда от них, а не от прошлой покраски.
struct RoomTintBase: Component {
    var materials: [any Material]
}

/// Свет комнаты сейчас: что задано и куда идём.
struct RoomLightState: Component {
    var schedule: RoomSchedule = .standard
    var dark = false
    /// Текущая и целевая фаза 0…2.
    var current: Double = 0
    var target: Double = 0
    /// Фаза, с которой сцена покрашена последней (NaN — ещё ни разу).
    var applied: Double = .nan
    var sinceCheck: Double = 0
    /// Перекрасить при следующем кадре (вещи дома перестроены).
    var force = false

    /// Скорость перехода, фаз в секунду: смена темы день ↔ ночь — около полутора секунд.
    static let speed: Double = 1.3
    /// Как часто сверяться с часами, секунды.
    static let checkEvery: Double = 5
    /// Шаг фазы, мельче которого не перекрашиваем (кроме прихода в цель).
    static let minStep: Double = 0.02
}

struct RoomLightSystem: System {
    private let query = EntityQuery(where: .has(RoomLightState.self))

    init(scene: RealityKit.Scene) {}

    @MainActor func update(context: SceneUpdateContext) {
        let dt = min(Double(context.deltaTime), 0.1)
        for e in context.entities(matching: query, updatingSystemWhen: .rendering) {
            guard var s = e.components[RoomLightState.self] else { continue }
            s.sinceCheck += dt
            if s.sinceCheck >= RoomLightState.checkEvery {
                s.sinceCheck = 0
                s.target = s.schedule.phaseNow(dark: s.dark)
            }
            s.current = RoomLighting.step(s.current, to: s.target, by: RoomLightState.speed * dt)
            if s.force || RoomLighting.needsPaint(current: s.current, target: s.target, applied: s.applied) {
                RoomLighting.apply(RoomLight.at(phase: s.current), to: e)
                s.applied = s.current
                s.force = false
            }
            e.components.set(s)
        }
    }
}

@MainActor
enum RoomLighting {
    private static var registered = false

    static func registerOnce() {
        guard !registered else { return }
        registered = true
        RoomGlow.registerComponent()
        RoomSky.registerComponent()
        RoomNightSky.registerComponent()
        RoomTintBase.registerComponent()
        RoomLightState.registerComponent()
        RoomLightSystem.registerSystem()
    }

    /// Сразу при открытии: свет уже нужной фазы, без перехода от дня.
    static func setup(_ room: Entity, schedule: RoomSchedule, dark: Bool) {
        let phase = schedule.phaseNow(dark: dark)
        var s = RoomLightState(schedule: schedule, dark: dark, current: phase, target: phase)
        apply(RoomLight.at(phase: phase), to: room)
        s.applied = phase
        room.components.set(s)
    }

    /// Из update RealityView: настройка, тема, перестройка вещей. Новая цель — сразу, переход — плавно.
    static func update(_ room: Entity, schedule: RoomSchedule, dark: Bool, force: Bool) {
        guard var s = room.components[RoomLightState.self] else {
            setup(room, schedule: schedule, dark: dark)
            return
        }
        guard s.schedule != schedule || s.dark != dark || force else { return }
        if s.schedule != schedule || s.dark != dark {
            s.schedule = schedule
            s.dark = dark
            s.target = schedule.phaseNow(dark: dark)
            s.sinceCheck = 0
        }
        s.force = s.force || force
        room.components.set(s)
    }

    nonisolated static func step(_ x: Double, to target: Double, by d: Double) -> Double {
        guard x.isFinite else { return target }
        if abs(target - x) <= d { return target }
        return x + (target > x ? d : -d)
    }

    nonisolated static func needsPaint(current: Double, target: Double, applied: Double) -> Bool {
        guard applied.isFinite else { return true }
        if current == applied { return false }
        return abs(current - applied) >= RoomLightState.minStep || current == target
    }

    // MARK: Покраска

    static func apply(_ light: RoomLight, to room: Entity) {
        let skyMul = RoomRGB(light.sky.r / RoomLight.day.sky.r, light.sky.g / RoomLight.day.sky.g,
                             light.sky.b / RoomLight.day.sky.b)
        var stack: [Entity] = Array(room.children)
        while let e = stack.popLast() {
            stack += Array(e.children)
            if let l = e as? DirectionalLight {
                switch l.name {
                case PetRoom.keyLight.name: set(l, light.key, light.keyI)
                case PetRoom.fillLight.name: set(l, light.fill, light.fillI)
                case PetRoom.rimLight.name: set(l, light.rim, light.rimI)
                default: break
                }
                continue
            }
            if let lamp = e as? PointLight {
                if lamp.name == PetRoom.lampName {
                    lamp.light.intensity = Float(light.lamp) * PetRoom.lampLumens
                    lamp.isEnabled = light.lamp > 0.001
                }
                continue
            }
            if let night = e.components[RoomNightSky.self] {
                let a = min(max(light.moon, 0), 1)
                e.isEnabled = a > 0.01
                if e.isEnabled, var model = e.components[ModelComponent.self] {
                    var m = UnlitMaterial(color: PetRoom.color(night.hex))
                    m.blending = .transparent(opacity: .init(floatLiteral: Float(a)))
                    model.materials = [m]
                    e.components.set(model)
                }
                continue
            }
            if e.components.has(RoomGlow.self) { continue }
            guard var model = e.components[ModelComponent.self] else { continue }
            let base: [any Material]
            if let b = e.components[RoomTintBase.self], b.materials.count == model.materials.count {
                base = b.materials
            } else {
                base = model.materials
                e.components.set(RoomTintBase(materials: base))
            }
            let mul = e.components.has(RoomSky.self) ? skyMul : light.tint
            model.materials = base.map { tinted($0, mul) }
            e.components.set(model)
        }
    }

    private static func set(_ l: DirectionalLight, _ c: RoomRGB, _ i: Double) {
        l.light.color = uiColor(c)
        l.light.intensity = Float(i)
    }

    /// Материал с цветом, умноженным на mul. Белый множитель — исходный материал как есть (день — как было).
    private static func tinted(_ m: any Material, _ mul: RoomRGB) -> any Material {
        if mul == .white { return m }
        if var p = m as? PhysicallyBasedMaterial {
            p.baseColor = .init(tint: times(p.baseColor.tint, mul), texture: p.baseColor.texture)
            return p
        }
        if var u = m as? UnlitMaterial {
            u.color = .init(tint: times(u.color.tint, mul), texture: u.color.texture)
            return u
        }
        return m
    }

    private static func times(_ c: UIColor, _ mul: RoomRGB) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard c.getRed(&r, green: &g, blue: &b, alpha: &a) else { return c }
        return UIColor(red: r * CGFloat(mul.r), green: g * CGFloat(mul.g), blue: b * CGFloat(mul.b), alpha: a)
    }

    static func uiColor(_ c: RoomRGB) -> UIColor {
        UIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1)
    }
}
