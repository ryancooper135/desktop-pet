// «Сок» сцены: дыхание с сохранением объёма, пружины squash / hop / yaw и режиссёр простоя.
// Всё считается в своих ECS-системах по накопленному deltaTime, без Timer и Task.
// Трансформ пишется в обёртку petJuice между корнем и моделью: пивот у лап, корень не трогаем.

import Foundation
@preconcurrency import RealityKit

// MARK: - Пружина

/// Затухающая пружина, решённая точно на шаге dt (без ошибки интегратора, стабильна при любом dt).
enum PetSpring {
    /// Новые (x, v) через dt. zeta ≥ 1 считается как критическое демпфирование.
    static func step(x: Float, v: Float, target: Float, omega: Float, zeta: Float, dt: Float) -> (Float, Float) {
        let z = min(max(zeta, 0), 1)
        let x0 = x - target
        if z >= 0.999 {
            let e = exp(-omega * dt)
            let c = v + omega * x0
            return (target + e * (x0 + c * dt), e * (v - omega * c * dt))
        }
        let a = z * omega
        let wd = omega * (1 - z * z).squareRoot()
        let e = exp(-a * dt)
        let cs = cos(wd * dt), sn = sin(wd * dt)
        let b = (v + a * x0) / wd
        return (target + e * (x0 * cs + b * sn), e * (v * cs - (a * b + x0 * wd) * sn))
    }

    /// Скорость толчка, после которого пружина из покоя отклонится на peak.
    static func impulse(peak: Float, omega: Float, zeta: Float) -> Float {
        let z = min(max(zeta, 0), 1)
        let perV: Float
        if z >= 0.999 {
            perV = 1 / (omega * Float(M_E))
        } else {
            let a = z * omega
            let wd = omega * (1 - z * z).squareRoot()
            let t = atan2(wd, a) / wd
            perV = exp(-a * t) * sin(wd * t) / wd
        }
        return perV > 0 ? peak / perV : 0
    }
}

// MARK: - Компонент

/// Дыхание и пружины. target* пишет PetModel.apply по позе, система плавно подтягивает текущие значения.
struct JuiceComponent: Component {
    static let omega: Float = 14
    static let squashZeta: Float = 0.55
    static let yawZeta: Float = 0.8

    var rate: Float = 0.3            // вдохов в секунду
    var amount: Float = 0.012        // доля роста по y на вдохе
    var targetRate: Float = 0.3
    var targetAmount: Float = 0.012
    var primed = false
    var phase: Float = 0             // угол, держим в [0, 2π)

    var squash: Float = 0, squashV: Float = 0   // <0 — присел, >0 — вытянулся
    var hop: Float = 0, hopV: Float = 0         // подскок по y, метры
    var yaw: Float = 0, yawV: Float = 0
    var yawTarget: Float = 0
    // Ласка (PetChoreo.petting): крен к руке вокруг мировой горизонтали к камере и виляние задом добавкой к цели yaw.
    var lean: Float = 0, leanV: Float = 0
    var leanTarget: Float = 0
    var wiggle: Float = 0

    // Только заглушка без скелета: покачивание и «лёг» приплющиванием.
    var sway: Float = 0
    var swayPhase: Float = 0
    var lie: Float = 0

    var still = false                // Reduce Motion: ни дыхания, ни пружин
    var lastReactionId = 0

    mutating func advance(_ dt: Float) {
        let k = 1 - exp(-dt / 0.35)
        rate += (targetRate - rate) * k
        amount += (targetAmount - amount) * k
        if still {
            amount = 0
            squash = 0; squashV = 0
            hop = 0; hopV = 0
            yaw = 0; yawV = 0
            lean = 0; leanV = 0; leanTarget = 0; wiggle = 0
            return
        }
        let twoPi = 2 * Float.pi
        phase += dt * twoPi * rate
        if phase >= twoPi { phase -= twoPi }
        swayPhase += dt * twoPi * 0.35
        if swayPhase >= twoPi { swayPhase -= twoPi }
        let w = JuiceComponent.omega
        (squash, squashV) = PetSpring.step(x: squash, v: squashV, target: 0, omega: w, zeta: JuiceComponent.squashZeta, dt: dt)
        (hop, hopV) = PetSpring.step(x: hop, v: hopV, target: 0, omega: w, zeta: JuiceComponent.squashZeta, dt: dt)
        (yaw, yawV) = PetSpring.step(x: yaw, v: yawV, target: yawTarget + wiggle, omega: w, zeta: JuiceComponent.yawZeta, dt: dt)
        (lean, leanV) = PetSpring.step(x: lean, v: leanV, target: leanTarget, omega: w, zeta: JuiceComponent.yawZeta, dt: dt)
    }

    /// Масштаб с сохранением объёма: тянется по y — сужается по x/z.
    var scale: SIMD3<Float> {
        let s = 1 + amount * sin(phase)
        let f = min(max(s * (1 + squash), 0.7), 1.3)
        let side = 1 / f.squareRoot()
        return SIMD3<Float>(side, f * (1 - 0.3 * lie), side)
    }

    var lift: Float { max(0, hop) }

    var angle: Float { yaw + (still ? 0 : sway * sin(swayPhase)) }
}

// MARK: - Системы

struct JuiceSystem: System {
    private let query = EntityQuery(where: .has(JuiceComponent.self))

    init(scene: RealityKit.Scene) {}

    @MainActor func update(context: SceneUpdateContext) {
        let dt = min(Float(context.deltaTime), 0.1)
        guard dt > 0 else { return }
        for e in context.entities(matching: query, updatingSystemWhen: .rendering) {
            guard var c = e.components[JuiceComponent.self],
                  let pivot = e.children.first(where: { $0.name == PetModel.pivotName }) else { continue }
            c.advance(dt)
            pivot.scale = c.scale
            pivot.position = SIMD3<Float>(0, c.lift, 0)
            let up = SIMD3<Float>(0, 1, 0)
            var turn = simd_quatf(angle: c.angle, axis: up)
            if abs(c.lean) > 1e-4 {
                // Крен вокруг горизонтали «от камеры» (мировая -z) в осях обёртки: + — макушка вправо по экрану.
                var axis = e.convert(direction: SIMD3<Float>(0, 0, -1), from: nil)
                axis.y = 0
                if simd_length(axis) > 1e-4 {
                    turn = simd_quatf(angle: c.lean, axis: simd_normalize(axis)) * turn
                }
            }
            pivot.orientation = turn
            e.components.set(c)
        }
    }

    @MainActor private static var registered = false

    @MainActor static func registerOnce() {
        guard !registered else { return }
        registered = true
        JuiceComponent.registerComponent()
        ClipState.registerComponent()
        JuiceSystem.registerSystem()
        IdleDirectorSystem.registerSystem()
        ChoreoState.registerComponent()
        PetFace.registerComponent()
        PetActSystem.registerSystem()
    }
}

/// Режиссёр простоя: ведёт часы ClipState, доигрывает отложенную позу и вставляет фиджеты.
struct IdleDirectorSystem: System {
    private let query = EntityQuery(where: .has(ClipState.self))

    init(scene: RealityKit.Scene) {}

    @MainActor func update(context: SceneUpdateContext) {
        let dt = min(context.deltaTime, 0.25)
        guard dt > 0 else { return }
        for e in context.entities(matching: query, updatingSystemWhen: .rendering) {
            PetModel.tick(e, dt: dt)
        }
    }
}
