// Хореография сцены: миска под мордой на время еды, мяч в «Поиграть», взгляд головой и моргание.
// ChoreoPath — чистые траектории без RealityKit (их покрывает PetChoreoTests). PetChoreo ведёт их по часам
// ClipState: двигает обёртку питомца с пятном-тенью, миску и мяч и ставит клипы на границах отрезков игры.
// PetRig поворачивает шею и голову к взгляду (кости Neck3 и Head) и моргает подменой материалов глаз.
// Время — секунды от начала реакции; координаты мировые, +y вверх, питомец дома стоит в нуле.
// Челюсти и век в shiba.usdz нет: «закрытый глаз» — материал шерсти на месте глаза (style_a eyes_closed).

import Foundation
import simd
import UIKit
@preconcurrency import RealityKit

// MARK: - Траектории

enum ChoreoPath {
    static let up = SIMD3<Float>(0, 1, 0)

    // MARK: помощники

    static func clamp01(_ x: Double) -> Float { Float(min(max(x, 0), 1)) }
    static func smooth(_ x: Double) -> Float { let t = clamp01(x); return t * t * (3 - 2 * t) }
    static func easeOut(_ x: Double) -> Float { let t = clamp01(x); return 1 - (1 - t) * (1 - t) }
    static func easeIn(_ x: Double) -> Float { let t = clamp01(x); return t * t }
    /// С небольшим перелётом за 1 — «выскочила».
    static func easeOutBack(_ x: Double) -> Float {
        let t = clamp01(x) - 1
        let c1: Float = 1.70158, c3 = c1 + 1
        return 1 + c3 * t * t * t + c1 * t * t
    }

    static func bezier(_ a: SIMD3<Float>, _ c: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        let s = 1 - t
        return s * s * a + 2 * s * t * c + t * t * b
    }

    /// Оси подставки (повёрнута на yaw3q) → мир и обратно.
    static func toWorld(_ p: SIMD3<Float>) -> SIMD3<Float> { simd_quatf(angle: PetRoom.yaw3q, axis: up).act(p) }
    static func toStand(_ p: SIMD3<Float>) -> SIMD3<Float> { simd_quatf(angle: -PetRoom.yaw3q, axis: up).act(p) }

    /// Поворот по y, при котором морда (+z) смотрит вдоль d. Положительный — к +x, вправо по экрану.
    static func yaw(toward d: SIMD3<Float>) -> Float { atan2(d.x, d.z) }

    static func wrap(_ a: Float) -> Float {
        var x = a
        while x > .pi { x -= 2 * .pi }
        while x < -.pi { x += 2 * .pi }
        return x
    }

    // MARK: еда

    /// Миска под мордой в осях подставки: при eat морда опускается к полу ~0.3 м вперёд от центра.
    static let bowlUnderSnout = SIMD3<Float>(0, 0.025, 0.30)
    static var bowlTarget: SIMD3<Float> { toWorld(bowlUnderSnout) }
    /// С какой высоты миска падает под морду.
    static let bowlDrop: Float = 0.3

    /// Когда идёт еда: от начала шагов до первого eat и до конца подряд идущих eat. Нет eat — nil.
    static func eatWindow(_ steps: [String], duration: (String) -> Double) -> (start: Double, end: Double)? {
        guard let i = steps.firstIndex(of: "eat") else { return nil }
        let start = steps[..<i].reduce(0) { $0 + duration($1) }
        var end = start
        var j = i
        while j < steps.count, steps[j] == "eat" {
            end += duration(steps[j])
            j += 1
        }
        return (start, end)
    }

    struct BowlPose: Equatable {
        var position: SIMD3<Float>
        var scale: SIMD3<Float>
        /// Сколько корма: 1 — горка, 0 — пусто (горка спрятана).
        var food: Float
    }

    /// Миска в момент t: дома → тает → падает под морду с приплющиванием → корм убывает за едой → уходит домой.
    /// present — миска уже стоит под мордой (кормят ещё раз подряд): не прыгает, корм досыпается.
    static func bowl(_ t: Double, eatStart: Double, eatEnd: Double, leave: Double, present: Bool = false) -> BowlPose {
        let home = BowlPose(position: PetRoom.bowlPos, scale: .one, food: 0)
        let target = bowlTarget
        let eatFrom = eatStart + 0.4
        let food = 1 - clamp01((t - eatFrom) / max(eatEnd - 0.3 - eatFrom, 0.1))
        if t >= leave {
            let k = t - leave
            if k < 0.15 {
                return BowlPose(position: target, scale: .init(repeating: max(1 - easeIn(k / 0.15), 0.001)), food: food)
            }
            return BowlPose(position: home.position, scale: .init(repeating: max(easeOutBack((k - 0.15) / 0.2), 0.001)),
                            food: 0)
        }
        if present { return BowlPose(position: target, scale: .one, food: food) }
        let d0 = max(0, eatStart - 0.5)
        if t < d0 { return home }
        if t < d0 + 0.15 {
            return BowlPose(position: home.position, scale: .init(repeating: max(1 - easeIn((t - d0) / 0.15), 0.001)),
                            food: 0)
        }
        let arrive = d0 + 0.4
        if t < arrive {
            let k = (t - d0 - 0.15) / 0.25
            let y = bowlDrop * (1 - easeIn(k))
            return BowlPose(position: target + SIMD3<Float>(0, y, 0),
                            scale: .init(repeating: max(easeOut(k * 1.6), 0.001)), food: 1)
        }
        // Приземлилась: короткое приплющивание.
        let a = 1 - clamp01((t - arrive) / 0.25)
        let s = a * a
        return BowlPose(position: target, scale: SIMD3<Float>(1 + 0.1 * s, 1 - 0.2 * s, 1 + 0.1 * s), food: food)
    }

    // MARK: игра

    /// «Поиграть», время u — от начала play_bow. Мяч уходит вправо назад дугой с затухающими отскоками,
    /// Шиба разворачивается, бежит, прыгает на мяч, возвращается на место и виляет хвостом; мяч катится домой.
    /// Тайминги подобраны в 2D-симуляции: мяч и тело (капсула) не пересекаются нигде, кроме прыжка.
    enum Play {
        static let kick = 1.15, fly = 1.4
        static let turn0 = 1.85, turn1 = 2.3, run1 = 2.8, pounce1 = 3.3, back0 = 3.8, walk1 = 4.7
        /// Мяч катится домой через ballDelay после разворота, за ballBack.
        static let ballDelay = 0.5, ballBack = 1.4
        /// Игра занимает питомца: вернулся и повилял хвостом.
        static let length = walk1 + 1.5
        static let ballRadius: Float = 0.05
        static var ballHome: SIMD3<Float> { PetRoom.ballPos }
        static let ballFar = SIMD3<Float>(0.24, 0.05, -0.45)
        static let ballCurve = SIMD3<Float>(0.34, 0.05, 0.05)
        /// Отскоки в полёте: длительность и высота.
        static let bounces: [(Double, Float)] = [(0.5, 0.16), (0.32, 0.07), (0.2, 0.025)]

        static var runDir: SIMD3<Float> { simd_normalize(SIMD3<Float>(ballFar.x, 0, ballFar.z)) }
        /// Где Шиба останавливается перед мячом.
        static var runTo: SIMD3<Float> { SIMD3<Float>(ballFar.x, 0, ballFar.z) - runDir * 0.30 }
        /// Куда мяч откатывается от прыжка.
        static var knockTo: SIMD3<Float> { ballFar + runDir * 0.08 }
        static var yawRun: Float { yaw(toward: runDir) }
        static var yawBack: Float { yaw(toward: -runTo) }

        struct Cue: Sendable {
            var at: Double
            var steps: [String]
            /// nil — основной цикл позы.
            var loop: String?
        }

        static let cues: [Cue] = [
            Cue(at: turn0, steps: [], loop: "walk"),
            Cue(at: turn1, steps: [], loop: "gallop"),
            Cue(at: run1, steps: ["hop"], loop: "idle"),
            Cue(at: pounce1, steps: [], loop: "walk"),
            Cue(at: walk1, steps: ["happy_wag"], loop: nil),
        ]
    }

    struct PetPose: Equatable {
        /// Мировая точка на полу.
        var position: SIMD3<Float>
        /// Мировой поворот по y (дома — yaw3q).
        var yaw: Float
    }

    static func pet(_ u: Double) -> PetPose {
        typealias P = Play
        let y0 = PetRoom.yaw3q
        if u < P.turn0 { return PetPose(position: .zero, yaw: y0) }
        if u < P.turn1 {
            // Через «лицом к камере», не спиной.
            return PetPose(position: .zero, yaw: y0 + (P.yawRun - y0) * smooth((u - P.turn0) / (P.turn1 - P.turn0)))
        }
        if u < P.run1 {
            return PetPose(position: P.runTo * smooth((u - P.turn1) / (P.run1 - P.turn1)), yaw: P.yawRun)
        }
        if u < P.pounce1 { return PetPose(position: P.runTo, yaw: P.yawRun) }
        if u < P.back0 {
            return PetPose(position: P.runTo,
                           yaw: P.yawRun + (P.yawBack - P.yawRun) * smooth((u - P.pounce1) / (P.back0 - P.pounce1)))
        }
        if u < P.walk1 {
            let s = smooth((u - P.back0) / (P.walk1 - P.back0))
            let y = P.yawBack + (y0 - P.yawBack) * smooth((u - P.walk1 + 0.3) / 0.3)
            return PetPose(position: P.runTo * (1 - s), yaw: y)
        }
        return PetPose(position: .zero, yaw: y0)
    }

    /// Высота отскока над полом через t после удара.
    static func bounce(_ t: Double) -> Float {
        var t = t
        for (d, h) in Play.bounces {
            if t < d {
                let s = Float(max(t, 0) / d)
                return h * 4 * s * (1 - s)
            }
            t -= d
        }
        return 0
    }

    static func ball(_ u: Double) -> SIMD3<Float> {
        typealias P = Play
        let r = P.ballRadius
        if u < P.kick { return P.ballHome }
        if u < P.kick + P.fly {
            var p = bezier(P.ballHome, P.ballCurve, P.ballFar, easeOut((u - P.kick) / P.fly))
            p.y = r + bounce(u - P.kick)
            return p
        }
        let k0 = P.pounce1 - 0.25
        if u < k0 { return P.ballFar }
        if u < k0 + 0.3 {
            let k = clamp01((u - k0) / 0.3)
            var p = P.ballFar + (P.knockTo - P.ballFar) * easeOut((u - k0) / 0.3)
            p.y = r + 0.04 * 4 * k * (1 - k)
            return p
        }
        let b0 = P.back0 + P.ballDelay
        if u < b0 { return P.knockTo }
        if u < b0 + P.ballBack {
            var p = bezier(P.knockTo, P.ballCurve, P.ballHome, easeOut((u - b0) / P.ballBack))
            p.y = r
            return p
        }
        return P.ballHome
    }

    /// Поворот головы к мячу относительно морды, в пределах ±limit. Вне игры — nil.
    static func look(_ u: Double, limit: Float) -> Float? {
        guard u >= 0, u < Play.walk1 else { return nil }
        let p = pet(u)
        let d = ball(u) - p.position
        return min(max(wrap(yaw(toward: d) - p.yaw), -limit), limit)
    }
}

// MARK: - Компоненты

/// Что сейчас ведёт хореография. Часы — ClipState.clock.
struct ChoreoState: Component {
    struct Feed {
        var start: Double
        var eatStart: Double
        var eatEnd: Double
        /// Когда миска уходит домой, от start.
        var leave: Double
        var present: Bool
    }

    struct Play {
        /// Часы на начале play_bow.
        var start: Double
        var mainLoop: String
        var cue = 0
    }

    var feed: Feed?
    var play: Play?
    var active = false
    /// Переход к новой траектории (начало игры, отмена) из того, что стояло, за PetChoreo.blend.
    var blendStart: Double = -100
    var fromPos = SIMD3<Float>.zero
    var fromYaw: Float = PetRoom.yaw3q
    var fromBall = PetRoom.ballPos
    var pos = SIMD3<Float>.zero
    var yaw: Float = PetRoom.yaw3q
    var ball = PetRoom.ballPos
}

/// Взгляд головой и моргание.
struct PetFace: Component {
    /// Предел поворота головы, радианы (шея 40%, голова 60%).
    static let limit: Float = 0.6
    /// Куда повернуть голову, радианы: + — вправо по экрану. Пишет PetModel.apply из lookX.
    var target: Float = 0
    /// Игра ведёт взгляд за мячом поверх target.
    var follow: Float? = nil
    var angle: Float = 0
    var speed: Float = 0
    var time: Double = 0
    var nextBlink: Double = 2.5
    var blinkUntil: Double = 0
    /// Reduce Motion: голова сразу на месте, без моргания.
    var still = false
}

// MARK: - Хореография

@MainActor
enum PetChoreo {
    static let blend: Double = 0.35

    nonisolated static func duration(_ name: String) -> Double {
        guard let c = ClipTable.shared?.clips[name] else { return 0 }
        return c.end - c.start
    }

    /// Проигрыватель поставил шаги. Есть eat — миска под морду, есть play_bow — игра с мячом.
    /// Прошлая хореография при этом сворачивается. Возвращает, до какого момента часов занята игра.
    @discardableResult
    static func begin(_ pet: Entity, steps: [String], clock: Double, mainLoop: String) -> Double? {
        var cs = pet.components[ChoreoState.self] ?? ChoreoState()
        let present = bowlAtSnout(cs, clock)
        interrupt(&cs, clock)
        var until: Double?
        if let w = ChoreoPath.eatWindow(steps, duration: duration) {
            cs.feed = .init(start: clock, eatStart: w.start, eatEnd: w.end, leave: w.end + 0.5, present: present)
            cs.active = true
        }
        if let i = steps.firstIndex(of: "play_bow") {
            let offset = steps[..<i].reduce(0) { $0 + duration($1) }
            cs.play = .init(start: clock + offset, mainLoop: mainLoop)
            cs.active = true
            until = clock + offset + ChoreoPath.Play.length
        }
        pet.components.set(cs)
        return until
    }

    /// Reduce Motion: всё сразу домой, без движения.
    static func stop(_ pet: Entity) {
        guard var cs = pet.components[ChoreoState.self], cs.active else { return }
        cs.feed = nil
        cs.play = nil
        cs.active = false
        cs.pos = .zero
        cs.yaw = PetRoom.yaw3q
        cs.ball = ChoreoPath.Play.ballHome
        cs.blendStart = -100
        let room = pet.scene?.findEntity(named: "room")
        place(pet, cs, room)
        placeBowl(room, .init(position: PetRoom.bowlPos, scale: .one, food: 0))
        if var face = pet.components[PetFace.self] {
            face.follow = nil
            pet.components.set(face)
        }
        pet.components.set(cs)
    }

    /// Миска сейчас стоит под мордой и ещё не уходит.
    static func bowlAtSnout(_ cs: ChoreoState, _ clock: Double) -> Bool {
        guard let f = cs.feed else { return false }
        let t = clock - f.start
        let arrived = f.present || t >= max(0, f.eatStart - 0.5) + 0.4
        return arrived && t < f.leave
    }

    /// Новая реакция перебила: игра плавно домой, миска уходит (если ещё не начала прыгать — остаётся дома).
    static func interrupt(_ cs: inout ChoreoState, _ clock: Double) {
        if cs.play != nil {
            cs.play = nil
            snapshot(&cs, clock)
        }
        if var f = cs.feed {
            let t = clock - f.start
            let d0 = max(0, f.eatStart - 0.5)
            if !f.present && t < d0 {
                cs.feed = nil
            } else if t < f.leave {
                f.leave = f.present ? t : max(t, d0 + 0.6)
                cs.feed = f
            }
        }
    }

    static func snapshot(_ cs: inout ChoreoState, _ clock: Double) {
        cs.fromPos = cs.pos
        cs.fromYaw = cs.yaw
        cs.fromBall = cs.ball
        cs.blendStart = clock
    }

    /// Кадр: миска, игра (клипы на границах отрезков), обёртка с пятном-тенью и мяч.
    static func step(_ pet: Entity) {
        guard var cs = pet.components[ChoreoState.self], cs.active,
              let st = pet.components[ClipState.self] else { return }
        let now = st.clock
        let room = pet.scene?.findEntity(named: "room")

        if let f = cs.feed {
            let t = now - f.start
            placeBowl(room, ChoreoPath.bowl(t, eatStart: f.eatStart, eatEnd: f.eatEnd, leave: f.leave, present: f.present))
            if t > f.leave + 0.4 {
                cs.feed = nil
                placeBowl(room, .init(position: PetRoom.bowlPos, scale: .one, food: 0))
            }
        }

        var pose = ChoreoPath.PetPose(position: .zero, yaw: PetRoom.yaw3q)
        var ball = ChoreoPath.Play.ballHome
        var look: Float? = nil
        if var p = cs.play {
            let u = now - p.start
            let cues = ChoreoPath.Play.cues
            let available = Set(ClipTable.shared?.clips.keys.map { $0 } ?? [])
            while p.cue < cues.count, u >= cues[p.cue].at {
                let c = cues[p.cue]
                ClipPlayer.play(PetStance.pick(c.steps, available: available), then: c.loop ?? p.mainLoop, on: pet,
                                transition: 0.2, randomSpeed: false, initial: false)
                p.cue += 1
            }
            pose = ChoreoPath.pet(u)
            ball = ChoreoPath.ball(u)
            look = ChoreoPath.look(u, limit: PetFace.limit)
            cs.play = u >= ChoreoPath.Play.length ? nil : p
        }

        let k = ChoreoPath.smooth((now - cs.blendStart) / blend)
        cs.pos = cs.fromPos + (pose.position - cs.fromPos) * k
        cs.yaw = cs.fromYaw + (pose.yaw - cs.fromYaw) * k
        cs.ball = cs.fromBall + (ball - cs.fromBall) * k
        place(pet, cs, room)
        if var face = pet.components[PetFace.self], face.follow != look {
            face.follow = look
            pet.components.set(face)
        }
        if cs.feed == nil && cs.play == nil && k >= 1 {
            cs.active = false
        }
        pet.components.set(cs)
    }

    /// Обёртка питомца и пятно-тень (оба в подставке) и мяч (в комнате).
    static func place(_ pet: Entity, _ cs: ChoreoState, _ room: Entity?) {
        let local = ChoreoPath.toStand(cs.pos)
        let rot = simd_quatf(angle: cs.yaw - PetRoom.yaw3q, axis: ChoreoPath.up)
        pet.position = local
        pet.orientation = rot
        if let shadow = pet.parent?.children.first(where: { $0.name == "blobShadow" }) {
            shadow.position = SIMD3<Float>(local.x, PetRoom.blobY, local.z)
            shadow.orientation = rot
        }
        room?.findEntity(named: "ball")?.position = cs.ball
    }

    static func placeBowl(_ room: Entity?, _ b: ChoreoPath.BowlPose) {
        guard let bowl = room?.findEntity(named: "bowl") else { return }
        bowl.position = b.position
        bowl.scale = b.scale
        if let food = bowl.findEntity(named: "food") {
            food.isEnabled = b.food > 0.01
            let side = 0.7 + 0.3 * b.food
            food.scale = SIMD3<Float>(side, max(0.45 * b.food, 0.001), side)
        }
    }
}

// MARK: - Кости и глаза

/// Шея и голова Шибы и материалы глаз. Ищется один раз на питомца.
@MainActor
final class PetRig {
    private static var rigs: [Entity.ID: PetRig] = [:]

    private weak var skin: ModelEntity?
    /// Neck3 и Head, доля поворота каждой.
    private var joints: [Int] = []
    private let share: [Float] = [0.4, 0.6]
    private var parents: [Int] = []
    private var base: [simd_quatf] = []
    private var last: [simd_quatf?] = []

    private weak var eyes: ModelEntity?
    private var open: [any Material] = []
    private var closed: [any Material] = []
    private var eyesClosed = false

    static func rig(for pet: Entity) -> PetRig? {
        let id = pet.id
        if let r = rigs[id] { return r }
        guard let body = pet.findEntity(named: PetModel.bodyName) else { return nil }
        if rigs.count > 8 { rigs.removeAll() }
        let r = PetRig(body)
        rigs[id] = r
        return r
    }

    private init(_ body: Entity) {
        var queue: [Entity] = [body]
        while !queue.isEmpty {
            let e = queue.removeFirst()
            if let m = e as? ModelEntity {
                if skin == nil, !m.jointNames.isEmpty { setUpJoints(m) }
                if eyes == nil, let mats = m.model?.materials, mats.count == 6 { setUpEyes(m, mats) }
            }
            queue += Array(e.children)
        }
    }

    /// Пути костей вида «Body/…/Neck3/Head»: родитель — путь без последнего звена.
    private func setUpJoints(_ m: ModelEntity) {
        let names = m.jointNames
        func find(_ leaf: String) -> Int? { names.firstIndex { $0 == leaf || $0.hasSuffix("/" + leaf) } }
        guard let neck = find("Neck3"), let head = find("Head"), m.jointTransforms.count == names.count else { return }
        var index: [String: Int] = [:]
        for (i, n) in names.enumerated() { index[n] = i }
        parents = names.map { n in
            guard let cut = n.lastIndex(of: "/") else { return -1 }
            return index[String(n[..<cut])] ?? -1
        }
        skin = m
        joints = [neck, head]
        base = joints.map { m.jointTransforms[$0].rotation }
        last = [nil, nil]
    }

    /// Порядок подмножеств: Main, Main_Light, Black, Eyes_White, Eyes_Pupil, Eyes_Black. Проверяем по цвету,
    /// что 3 светлее шерсти, а 4 и 5 темнее; не сошлось — не моргаем.
    private func setUpEyes(_ m: ModelEntity, _ mats: [any Material]) {
        let light = mats.map(Self.brightness)
        guard let fur = light[0], let white = light[3], let pupil = light[4], let black = light[5],
              white > fur + 0.1, pupil < fur, black < fur else { return }
        eyes = m
        open = mats
        closed = mats
        for i in 3...5 { closed[i] = mats[0] }
    }

    private static func brightness(_ m: any Material) -> CGFloat? {
        guard let p = m as? PhysicallyBasedMaterial else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard p.baseColor.tint.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return r + g + b
    }

    /// Поворот шеи и головы вокруг вертикали сцены. Анимация пишет кости каждый кадр — добавку кладём поверх
    /// её позы; если кость не перезаписали (стоит наша прошлая запись), берём прошлую основу, а не копим поворот.
    func look(_ angle: Float) {
        guard let m = skin, joints.count == 2 else { return }
        if abs(angle) < 1e-4 && last.allSatisfy({ $0 == nil }) { return }
        var tr = m.jointTransforms
        guard tr.count == parents.count else { return }
        for k in 0..<2 {
            let cur = tr[joints[k]].rotation
            if let l = last[k], Self.same(cur, l) { continue }
            base[k] = cur
        }
        var rot = tr.map(\.rotation)
        for k in 0..<2 { rot[joints[k]] = base[k] }
        let up = simd_normalize(m.convert(direction: ChoreoPath.up, from: nil))
        for k in 0..<2 {
            let j = joints[k]
            let axis = simd_normalize(global(j, rot).inverse.act(up))
            let q = base[k] * simd_quatf(angle: angle * share[k], axis: axis)
            tr[j].rotation = q
            last[k] = q
        }
        m.jointTransforms = tr
    }

    func setEyes(closed shut: Bool) {
        guard shut != eyesClosed, let e = eyes, var model = e.model else { return }
        model.materials = shut ? closed : open
        e.model = model
        eyesClosed = shut
    }

    private func global(_ j: Int, _ rot: [simd_quatf]) -> simd_quatf {
        var q = rot[j]
        var p = parents[j]
        var n = 0
        while p >= 0 && n < 64 {
            q = rot[p] * q
            p = parents[p]
            n += 1
        }
        return q
    }

    private static func same(_ a: simd_quatf, _ b: simd_quatf) -> Bool {
        let d = a.vector - b.vector
        return max(abs(d.x), abs(d.y), abs(d.z), abs(d.w)) < 1e-5
    }

    /// Кадр лица: пружина взгляда, моргание, во сне глаза закрыты.
    static func step(_ pet: Entity, dt: Double) {
        guard var face = pet.components[PetFace.self] else { return }
        face.time += dt
        let goal = face.follow ?? face.target
        if face.still {
            face.angle = goal
            face.speed = 0
        } else {
            (face.angle, face.speed) = PetSpring.step(x: face.angle, v: face.speed, target: goal,
                                                      omega: 10, zeta: 0.9, dt: Float(dt))
        }
        var shut = false
        let st = pet.components[ClipState.self]
        if let st, st.stance == .sleep, st.clock >= st.busyUntil - 0.4 {
            shut = true
        } else if !face.still {
            if face.time >= face.nextBlink {
                face.blinkUntil = face.time + 0.13
                // Иногда двойное моргание.
                face.nextBlink = face.time + (Double.random(in: 0..<1) < 0.2 ? 0.3 : Double.random(in: 2.5...6))
            }
            shut = face.time < face.blinkUntil
        }
        pet.components.set(face)
        guard let rig = rig(for: pet) else { return }
        rig.look(face.angle)
        rig.setEyes(closed: shut)
    }
}

/// Хореография и лицо по кадрам.
struct PetActSystem: System {
    private let query = EntityQuery(where: .has(PetFace.self))

    init(scene: RealityKit.Scene) {}

    @MainActor func update(context: SceneUpdateContext) {
        let dt = min(context.deltaTime, 0.1)
        guard dt > 0 else { return }
        for e in context.entities(matching: query, updatingSystemWhen: .rendering) {
            PetChoreo.step(e)
            PetRig.step(e, dt: dt)
        }
    }
}
