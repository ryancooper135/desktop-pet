// Волна 34 G: настоящий двор в 3D — сцена экрана «Двор» из сейва, а не из ползунков превью (YardStage).
// Слои яруса — по купленным плитам (порядок конфига = порядок YardArtTier.plates), станции — по f.yard.stations
// на своём уровне. Плюс проекция точки сцены на экран: таблички «+N/ч» висят над станциями SwiftUI-слоем.

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

    /// Сцена: слои 0…max(ярус, 1) (за подоконником — пустырь), станции, свет и камера.
    static func scene(_ s: YardState, tier: Int, fill: Float, night: Bool, brushed: Bool) -> Entity {
        let world = Entity()
        world.name = "yardLive"
        // Корень «живёт» (нулевой пульс): часы двора идут, даже если станций ещё нет.
        world.components.set(YardArtMotionComponent(motion: .pulse(amount: 0, period: 1, phase: 0), base: .zero))
        let top = min(max(tier, 1), YardArtTier.plates.count - 1)
        for k in 0...top {
            let b = k <= tier ? bought(s, tier: k) : 0
            world.addChild(YardArtStage.entity(YardArtTier.layer(k, bought: b)))
        }
        for spot in spots(s, tier: tier) {
            guard let st = YardArtStation.allCases.first(where: { $0.configId == spot.id }) else { continue }
            let e = YardArtStage.entity(YardArt.station(st, level: spot.level, fill: fill, night: night, brushed: brushed))
            e.name = name(spot.id)
            e.position = spot.at
            e.scale = SIMD3<Float>(repeating: spot.scale)
            world.addChild(e)
        }
        let cam = camera(tier: tier)
        world.addChild(YardArtStage.camera(target: cam.target, eye: cam.eye, fov: cam.fov))
        world.addChild(PetRoom.lights())
        return world
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
