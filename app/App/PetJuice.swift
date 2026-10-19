// «Сок» сцены: дыхание с сохранением объёма, пружины squash / hop / yaw и режиссёр простоя.
// Всё считается в своих ECS-системах по накопленному deltaTime, без Timer и Task.
// Трансформ пишется в обёртку petJuice между корнем и моделью: пивот у лап, корень не трогаем.

import Foundation
@preconcurrency import RealityKit

// MARK: - Пружина

/// Затухающая пружина, решённая точно на шаге dt (без ошибки интегратора, стабильна при любом dt).
enum PetSpring {
    /// Новые (x, v) через dt. zeta ≥ 1 считается как критическое демпфирование. Формула — SoftSpring (Shared):
    /// её же гоняют логические тесты отклика на тап (TapWiggleTests).
    static func step(x: Float, v: Float, target: Float, omega: Float, zeta: Float, dt: Float) -> (Float, Float) {
        SoftSpring.step(x: x, v: v, target: target, omega: omega, zeta: zeta, dt: dt)
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

    // Разворот всей собаки на месте под стойку (пока только сон: боком к камере, иначе сверху-спереди
    // свернувшаяся собака читается как бесформенный ком). Медленная пружина без перелёта поверх yaw.
    static let restOmega: Float = 4
    static let sleepYaw: Float = -0.9   // ≈ -52°: вместе с yaw3q почти профиль, морда влево по экрану
    var rest: Float = 0, restV: Float = 0
    var restTarget: Float = 0

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
            rest = restTarget; restV = 0
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
        (rest, restV) = PetSpring.step(x: rest, v: restV, target: restTarget, omega: JuiceComponent.restOmega, zeta: 1, dt: dt)
        // Докрутили — встаём ровно в цель, чтобы тень перестала переписываться каждый кадр.
        if abs(rest - restTarget) < 1e-4 && abs(restV) < 1e-3 {
            rest = restTarget; restV = 0
        }
    }

    /// Целевой разворот на месте для стойки: во сне — боком к камере, в остальных (и в смерти на боку) — как есть.
    static func restYaw(for stance: Stance?) -> Float {
        stance == .sleep ? sleepYaw : 0
    }

    /// Масштаб с сохранением объёма: тянется по y — сужается по x/z.
    var scale: SIMD3<Float> {
        let s = 1 + amount * sin(phase)
        let f = min(max(s * (1 + squash), 0.7), 1.3)
        let side = 1 / f.squareRoot()
        return SIMD3<Float>(side, f * (1 - 0.3 * lie), side)
    }

    var lift: Float { max(0, hop) }

    var angle: Float { yaw + rest + (still ? 0 : sway * sin(swayPhase)) }
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
            // Стойка меняется в начале цепочки (drive), так что разворот идёт вместе с lie_in / sleep_in
            // при засыпании и с sleep_out / lie_out при пробуждении.
            c.restTarget = JuiceComponent.restYaw(for: e.components[ClipState.self]?.stance)
            let turned = c.rest != 0
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
            // Пятно-тень вытянуто вдоль морды и живёт рядом с обёрткой (не в пивоте) — доворачиваем его
            // вслед за разворотом. Пишем только пока разворот не нулевой или только что вернулся в 0.
            if turned || c.rest != 0,
               let shadow = e.parent?.children.first(where: { $0.name == "blobShadow" }) {
                shadow.orientation = e.orientation * simd_quatf(angle: c.rest, axis: up)
            }
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
        HomeLift.registerComponent()
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
