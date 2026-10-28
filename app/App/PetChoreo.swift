// Хореография сцены: миска под мордой на время еды, мяч в «Поиграть», уход на прогулку и возвращение
// с находкой, взгляд головой и моргание.
// ChoreoPath (ChoreoPath.swift) — чистые траектории без RealityKit (их покрывает PetChoreoTests). PetChoreo ведёт их по часам
// ClipState: двигает обёртку питомца с пятном-тенью, миску и мяч и ставит клипы на границах отрезков игры.
// PetRig (PetRig.swift) поворачивает шею и голову к взгляду (кости Neck3 и Head) и моргает веками (PetRig.lids).
// Время — секунды от начала реакции; координаты мировые, +y вверх, питомец дома стоит в нуле.
// Век в shiba.usdz нет: «закрытый глаз» — копия глаз цвета шерсти поверх них (PetRoom.eyeLid).

import Foundation
import simd
import UIKit
@preconcurrency import RealityKit

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

    struct Petting {
        var start: Double
        var length: Double
        /// Где рука: -1 слева, +1 справа по экрану.
        var side: Float
    }

    struct Walk {
        /// true — уходит, false — возвращается.
        var out: Bool
        /// Часы на начале ухода (после перехода в стойку) или возвращения.
        var start: Double
        /// Находка в зубах (id); пусто — без находки.
        var find: String
        /// Виляние хвостом дома уже поставлено.
        var cued = false
    }

    /// Дело простоя (волна 44 M, DogIdle): путь по комнате и реплики клипов.
    struct Chore {
        /// Часы на начале.
        var start: Double
        var route: IdleRoute
        var cues: [IdleCue]
        var cue = 0
        /// Чем встать домой, если перебили (back последней сыгранной реплики).
        var back: [String] = []
    }

    var feed: Feed?
    var play: Play?
    var petting: Petting?
    var walk: Walk?
    var chore: Chore?
    /// Длина текущего перехода (blend); перебитое дело возвращается домой дольше — по расстоянию.
    var blendLen: Double = PetChoreo.blend
    /// Гуляет: тело и пятно спрятаны, комната пустая.
    var hidden = false
    /// Последнее возвращение, которое сцена уже видела (AppModel.walkHome.id), как lastReactionId у реакций.
    var walkHomeId = 0
    var walkPrimed = false
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

/// Уровни дома, по которым PetChoreo поднимает Шибу на матрас лежанки (PetChoreo.setHome).
struct HomeLift: Component {
    var levels: RoomPlan.Levels
}

/// Взгляд головой и моргание.
struct PetFace: Component {
    /// Предел поворота головы за мячом в игре, радианы (шея 40%, голова 60%). К пальцу — SoftLook.fingerLimit.
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
    /// Гладят: глаза закрыты от удовольствия. Пишет PetChoreo.step.
    var bliss = false
    /// Reduce Motion: голова сразу на месте, без моргания.
    var still = false
    /// Реплика на экране (AppModel.sayLine) и когда она появилась (по time): челюсть «говорит» (JawTalk).
    var talk: String? = nil
    var talkFrom: Double = 0
    /// Угол челюсти поверх клипа и его скорость (пружина).
    var jaw: Float = 0
    var jawSpeed: Float = 0
    /// Отклик на тап и щекотку поверх клипа (волна 18): запускает PetModel.apply, шагает PetRig.step.
    var wiggle = TapWiggle()
}

// MARK: - Хореография

@MainActor
enum PetChoreo {
    nonisolated static let blend: Double = 0.35
    /// Рост пса (волна 34 I, ставит PetRig.setGrowth): щенку миска поменьше и ближе — под его морду.
    static var growth: Float = 1

    nonisolated static func duration(_ name: String) -> Double {
        guard let c = ClipTable.shared?.clips[name] else { return 0 }
        return c.end - c.start
    }

    /// Проигрыватель поставил шаги. Есть eat — миска под морду, есть play_bow — игра с мячом.
    /// Прошлая хореография при этом сворачивается. Возвращает, до какого момента часов занята игра.
    /// trick — шаги играют удачный трюк: «Поклон» без мяча, «Голос» лает (bark) или тявкает на прыжке.
    @discardableResult
    static func begin(_ pet: Entity, steps: [String], clock: Double, mainLoop: String,
                      trick: Trick? = nil) -> Double? {
        var cs = pet.components[ChoreoState.self] ?? ChoreoState()
        let present = bowlAtSnout(cs, clock)
        interrupt(&cs, clock)
        SoundKit.shared.cancelChoreo()
        if let w = cs.walk, !w.out, clock - w.start < ChoreoPath.Walk.inWalk {
            // Новое действие, пока идёт домой: находка сразу «в альбоме», Шиба плавно домой.
            // Дома (поза после прихода) находка доигрывает сама.
            cs.walk = nil
            removeProp(pet)
            snapshot(&cs, clock)
            cs.active = true
        }
        if cs.petting != nil {
            cs.petting = nil
            relax(pet)
        }
        var until: Double?
        if let w = ChoreoPath.eatWindow(steps, duration: duration) {
            cs.feed = .init(start: clock, eatStart: w.start, eatEnd: w.end, leave: w.end + 0.5, present: present)
            cs.active = true
            SoundKit.shared.eat(from: w.start, to: w.end)
        }
        if trick == .speak, let i = steps.firstIndex(of: "bark") {
            // Клип bark: два «гав», пасть открыта сильнее всего на 0,2 и 0,6 с (poses.json, 2,5 Гц).
            let at = steps[..<i].reduce(0) { $0 + duration($1) }
            for t in ChoreoPath.barkYips { SoundKit.shared.play(.yip, after: at + t) }
        } else if trick == .speak, let i = steps.firstIndex(of: "hop") {
            SoundKit.shared.play(.yip, after: steps[..<i].reduce(0) { $0 + duration($1) })
        }
        if trick == nil, let i = steps.firstIndex(of: "play_bow") {
            let offset = steps[..<i].reduce(0) { $0 + duration($1) }
            cs.play = .init(start: clock + offset, mainLoop: mainLoop)
            cs.active = true
            SoundKit.shared.ball(after: offset)
            until = clock + offset + ChoreoPath.Play.length
        }
        pet.components.set(cs)
        return until
    }

    /// Дело простоя (волна 44 M): пёс сам идёт по route, клипы — по cues. Только из покоя: хореография
    /// не занята и Шиба не гуляет (проверяет PetModel.tick).
    static func startChore(_ pet: Entity, route: IdleRoute, cues: [IdleCue], clock: Double) {
        var cs = pet.components[ChoreoState.self] ?? ChoreoState()
        cs.chore = .init(start: clock, route: route, cues: cues)
        cs.active = true
        pet.components.set(cs)
    }

    /// Хореография занята (игра, миска, прогулка, ласка, дело или переход) или пёс гуляет.
    static func busy(_ pet: Entity) -> Bool {
        guard let cs = pet.components[ChoreoState.self] else { return false }
        return cs.active || cs.hidden
    }

    /// Касание или новая поза перебили дело простоя: пёс плавно домой. Возвращает клипы, которыми встать
    /// в стойку (лежал на ковре — lie_out), или nil, если дела не было.
    @discardableResult
    static func cutChore(_ pet: Entity, clock: Double) -> [String]? {
        guard var cs = pet.components[ChoreoState.self], let c = cs.chore else { return nil }
        interrupt(&cs, clock)
        pet.components.set(cs)
        return c.back
    }

    /// Гладят стоя: поверх клипов реакции наклон к руке, виляние и закрытые глаза на length секунд.
    /// Вызывать после begin (begin снимает прошлую ласку).
    static func petting(_ pet: Entity, clock: Double, length: Double, side: Float) {
        var cs = pet.components[ChoreoState.self] ?? ChoreoState()
        cs.petting = .init(start: clock, length: max(length, ChoreoPath.Petting.minLength), side: side)
        cs.active = true
        pet.components.set(cs)
    }

    /// Снять ласку: наклон и виляние к нулю (пружиной), глаза снова моргают.
    static func relax(_ pet: Entity) {
        if var j = pet.components[JuiceComponent.self] {
            j.leanTarget = 0
            j.wiggle = 0
            pet.components.set(j)
        }
        if var face = pet.components[PetFace.self], face.bliss {
            face.bliss = false
            pet.components.set(face)
        }
    }

    /// Reduce Motion: всё сразу домой, без движения.
    static func stop(_ pet: Entity) {
        guard var cs = pet.components[ChoreoState.self], cs.active else { return }
        SoundKit.shared.cancelChoreo()
        cs.feed = nil
        cs.play = nil
        cs.chore = nil
        cs.blendLen = blend
        if cs.walk != nil {
            cs.walk = nil
            removeProp(pet)
        }
        if cs.petting != nil {
            cs.petting = nil
            relax(pet)
        }
        cs.active = false
        cs.pos = .zero
        cs.yaw = PetRoom.yaw3q
        cs.ball = ChoreoPath.Play.ballHome
        cs.blendStart = -100
        let room = sceneRoom(of: pet)
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
        if cs.chore != nil {
            // Дело простоя: домой из того места, где застали, тем же поворотом без лишнего витка.
            cs.chore = nil
            snapshot(&cs, clock)
            cs.fromYaw = IdleRoute.near(cs.fromYaw, PetRoom.yaw3q)
            let d = Double(simd_length(SIMD2<Float>(cs.fromPos.x, cs.fromPos.z)))
            cs.blendLen = max(blend, min(1.2, d * 1.2))
            cs.active = true
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
        let room = sceneRoom(of: pet)

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
            // Набор клипов — только когда подошла реплика, а не на каждом кадре игры.
            while p.cue < cues.count, u >= cues[p.cue].at {
                let c = cues[p.cue]
                ClipPlayer.play(PetStance.pick(c.steps, available: availableClips()), then: c.loop ?? p.mainLoop, on: pet,
                                transition: 0.2, randomSpeed: false, initial: false)
                p.cue += 1
            }
            pose = ChoreoPath.pet(u)
            ball = ChoreoPath.ball(u)
            look = ChoreoPath.look(u, limit: PetFace.limit)
            cs.play = u >= ChoreoPath.Play.length ? nil : p
        } else if var w = cs.walk {
            let u = now - w.start
            if w.out {
                pose = ChoreoPath.walkOut(max(u, 0))
                if u >= ChoreoPath.Walk.outLength {
                    // Ушёл за край: комната пустая до возвращения.
                    cs.walk = nil
                    cs.hidden = true
                    setHidden(pet, true)
                }
            } else {
                pose = ChoreoPath.walkIn(u)
                if !w.cued && u >= ChoreoPath.Walk.inWalk {
                    // Дома: виляет хвостом, пока кладёт находку; новую позу потом поставит режиссёр (lockUntil).
                    w.cued = true
                    ClipPlayer.play(PetStance.pick(["happy_wag", "pant"], available: availableClips()), then: "idle", on: pet,
                                    transition: 0.2, randomSpeed: false, initial: false)
                }
                placeProp(pet, ChoreoPath.walkProp(u))
                cs.walk = u >= ChoreoPath.Walk.inLength ? nil : w
            }
        } else if var c = cs.chore {
            // Дело простоя (волна 44 M): клипы на репликах, тело — по пути DogIdle.
            let u = now - c.start
            while c.cue < c.cues.count, u >= c.cues[c.cue].at {
                let q = c.cues[c.cue]
                ClipPlayer.play(PetStance.pick(q.steps, available: availableClips()), then: q.loop, on: pet,
                                transition: 0.25, randomSpeed: false, initial: false)
                c.back = q.back
                c.cue += 1
            }
            let p = c.route.pose(at: u)
            pose = ChoreoPath.PetPose(position: SIMD3<Float>(p.p.x, 0, p.p.z), yaw: p.yaw)
            cs.chore = u >= c.route.homeAt ? nil : c
        }

        var bliss = false
        if let g = cs.petting {
            let t = now - g.start
            let pp = ChoreoPath.petting(t, length: g.length, side: g.side)
            if var j = pet.components[JuiceComponent.self] {
                j.leanTarget = pp.lean
                j.wiggle = pp.wiggle
                pet.components.set(j)
            }
            bliss = pp.eyesClosed
            if t >= g.length {
                cs.petting = nil
                relax(pet)
            }
        }

        let k = ChoreoPath.smooth((now - cs.blendStart) / cs.blendLen)
        if k >= 1 { cs.blendLen = blend }
        cs.pos = cs.fromPos + (pose.position - cs.fromPos) * k
        cs.yaw = cs.fromYaw + (pose.yaw - cs.fromYaw) * k
        cs.ball = cs.fromBall + (ball - cs.fromBall) * k
        place(pet, cs, room)
        if var face = pet.components[PetFace.self], face.follow != look || face.bliss != bliss {
            face.follow = look
            face.bliss = bliss
            pet.components.set(face)
        }
        if cs.feed == nil && cs.play == nil && cs.petting == nil && cs.walk == nil && cs.chore == nil && k >= 1 {
            cs.active = false
        }
        pet.components.set(cs)
    }

    // MARK: прогулка

    /// Прогулка по позе и счётчику возвращений (AppModel.walkHome). Вызывать до PetModel.apply: возвращение
    /// держит новую позу (lockUntil), пока Шиба не дойдёт до дома, потом её ставит режиссёр (pendingPose).
    /// Сразу, без шага: первый вызов (открыли экран — гуляет, значит комната пустая; вернулся, пока приложение
    /// было закрыто, — просто стоит дома), Reduce Motion, заглушка без клипов и смерть (instant).
    static func walk(_ pet: Entity, away: Bool, instant: Bool, homeId: Int, find: String, reduceMotion: Bool) {
        var cs = pet.components[ChoreoState.self] ?? ChoreoState()
        let fresh = cs.walkPrimed && homeId != cs.walkHomeId
        let first = !cs.walkPrimed
        cs.walkPrimed = true
        cs.walkHomeId = homeId
        guard var st = pet.components[ClipState.self], ClipTable.shared != nil,
              !reduceMotion, !first, !instant else {
            if cs.walk != nil {
                cs.walk = nil
                removeProp(pet)
            }
            if cs.hidden != away {
                cs.hidden = away
                cs.pos = .zero
                cs.yaw = PetRoom.yaw3q
                cs.blendStart = -100
                place(pet, cs, sceneRoom(of: pet))
            }
            setHidden(pet, away)
            pet.components.set(cs)
            return
        }
        let now = st.clock

        if away {
            // Уже ушёл или уходит.
            guard !cs.hidden, cs.walk?.out != true else {
                pet.components.set(cs)
                return
            }
            // Уход — после перехода в стойку (его сыграет drive) и после идущей реакции.
            let path = PetStance.pick(PetStance.path(from: st.stance, to: .stand), available: availableClips())
            let start = max(now, st.lockUntil) + path.reduce(0) { $0 + duration($1) }
            interrupt(&cs, now)
            if cs.petting != nil {
                cs.petting = nil
                relax(pet)
            }
            if cs.walk != nil { removeProp(pet) }
            snapshot(&cs, now)
            cs.walk = .init(out: true, start: start, find: "")
            cs.active = true
            pet.components.set(cs)
            return
        }

        if let w = cs.walk, w.out, now - w.start < ChoreoPath.Walk.turnOut {
            // Прогулку отменили до первого шага (ночь, беда): просто домой.
            cs.walk = nil
            snapshot(&cs, now)
            cs.active = true
            pet.components.set(cs)
            return
        }
        guard cs.hidden || cs.walk?.out == true else {
            // Уже дома или идёт домой: находку, пришедшую чуть позже позы, всё равно дать в зубы.
            if fresh, !find.isEmpty, var w = cs.walk, !w.out, w.find.isEmpty {
                w.find = find
                cs.walk = w
                addProp(pet, find)
            }
            pet.components.set(cs)
            return
        }

        // Возвращение: из-за края (или с полпути), шагом, с находкой в зубах.
        var start = now
        if cs.hidden {
            cs.pos = ChoreoPath.Walk.offstage
            cs.yaw = ChoreoPath.Walk.yawIn
            cs.blendStart = -100
        } else {
            start = now - ChoreoPath.walkInStart(from: cs.pos)
            snapshot(&cs, now)
        }
        cs.hidden = false
        setHidden(pet, false)
        let item = fresh ? find : ""
        removeProp(pet)
        if !item.isEmpty { addProp(pet, item) }
        cs.walk = .init(out: false, start: start, find: item)
        cs.active = true
        place(pet, cs, sceneRoom(of: pet))
        pet.components.set(cs)

        ClipPlayer.play([], then: "walk", on: pet, transition: 0.2, randomSpeed: false, initial: false)
        let wag = PetStance.pick(["happy_wag"], available: availableClips())
        let home = start + ChoreoPath.Walk.inWalk
        let hold = home + max(ChoreoPath.Walk.turnIn, wag.reduce(0) { $0 + duration($1) })
        st.current = "~walk"
        st.stance = .stand
        st.loop = "walk"
        st.reactionSteps = []
        st.busyUntil = hold
        st.lockUntil = hold
        st.nextFidgetAt = hold + Double.random(in: 15...25)
        pet.components.set(st)
    }

    /// Гуляет: прячем тело (обёртку с дыханием) и пятно-тень; сама обёртка остаётся — её часы и системы идут.
    static func setHidden(_ pet: Entity, _ hidden: Bool) {
        pet.findEntity(named: PetModel.pivotName)?.isEnabled = !hidden
        pet.parent?.children.first(where: { $0.name == "blobShadow" })?.isEnabled = !hidden
    }

    static func addProp(_ pet: Entity, _ find: String) {
        let prop = PetRoom.findProp(find)
        prop.position = ChoreoPath.Walk.carry
        pet.addChild(prop)
    }

    static func removeProp(_ pet: Entity) {
        pet.children.first(where: { $0.name == PetRoom.propName })?.removeFromParent()
    }

    static func placeProp(_ pet: Entity, _ p: ChoreoPath.PropPose?) {
        guard let prop = pet.children.first(where: { $0.name == PetRoom.propName }) else { return }
        guard let p else {
            prop.removeFromParent()
            return
        }
        prop.position = p.position
        prop.scale = SIMD3<Float>(repeating: p.scale)
    }

    /// Уровни дома для подъёма на лежанку (RoomPlan.petLift). Зовётся из PetStage на каждый пересчёт вью:
    /// те же уровни — ничего; новые (купили лежанку) — стоящего Шибу сразу поднимаем, идущего поднимет place.
    static func setHome(_ pet: Entity, _ levels: RoomPlan.Levels) {
        if pet.components[HomeLift.self]?.levels == levels { return }
        pet.components.set(HomeLift(levels: levels))
        let cs = pet.components[ChoreoState.self]
        if cs?.active == true { return }
        pet.position.y = lift(pet, at: cs?.pos ?? .zero)
    }

    /// Высота лап над полом, когда середина Шибы в точке p комнаты: верх матраса на лежанке, иначе 0.
    static func lift(_ pet: Entity, at p: SIMD3<Float>) -> Float {
        guard let levels = pet.components[HomeLift.self]?.levels else { return 0 }
        return RoomPlan.petLift(levels, at: RoomPlan.P(p.x, p.z))
    }

    // MARK: комната и клипы без поиска на каждом кадре (волна 26)

    /// Имена клипов модели (для PetStance.pick): набор собирается раз на таблицу, а не на кадре игры.
    static func availableClips() -> Set<String> { ClipTable.sharedNames }

    /// Найденное по имени у родителя; ссылка слабая. Годится, пока вещь жива, зовётся так же и висит под тем же
    /// родителем (комнату пересобрали — ищем заново). Раньше findEntity по всей сцене шёл на каждом кадре реакции.
    private struct FoundKey: Hashable {
        let parent: Entity.ID
        let name: String
    }
    private final class Found {
        weak var entity: Entity?
        init(_ e: Entity) { entity = e }
    }
    private static var found: [FoundKey: Found] = [:]

    /// Комната сцены питомца.
    static func sceneRoom(of pet: Entity) -> Entity? {
        guard let scene = pet.scene else { return nil }
        let key = FoundKey(parent: pet.id, name: "room")
        if let r = found[key]?.entity, r.name == "room", r.scene === scene { return r }
        return remember(key, scene.findEntity(named: "room"))
    }

    /// Часть комнаты или миски по имени: миска, корм, мяч.
    static func roomPart(_ parent: Entity, _ name: String) -> Entity? {
        let key = FoundKey(parent: parent.id, name: name)
        if let e = found[key]?.entity, e.name == name, isUnder(e, parent) { return e }
        return remember(key, parent.findEntity(named: name))
    }

    private static func isUnder(_ e: Entity, _ ancestor: Entity) -> Bool {
        var p = e.parent
        while let q = p {
            if q === ancestor { return true }
            p = q.parent
        }
        return false
    }

    private static func remember(_ key: FoundKey, _ e: Entity?) -> Entity? {
        guard let e else {
            found[key] = nil
            return nil
        }
        if found.count > 32 { found.removeAll() }
        found[key] = Found(e)
        return e
    }

    /// Обёртка питомца и пятно-тень (оба в подставке) и мяч (в комнате).
    static func place(_ pet: Entity, _ cs: ChoreoState, _ room: Entity?) {
        var local = ChoreoPath.toStand(cs.pos)
        local.y += lift(pet, at: cs.pos)
        let rot = simd_quatf(angle: cs.yaw - PetRoom.yaw3q, axis: ChoreoPath.up)
        pet.position = local
        pet.orientation = rot
        if let shadow = pet.parent?.children.first(where: { $0.name == "blobShadow" }) {
            shadow.position = SIMD3<Float>(local.x, PetRoom.blobY, local.z)
            shadow.orientation = rot
        }
        if let room { roomPart(room, "ball")?.position = cs.ball }
    }

    /// Миска дома — под рост пса (волна 34 I). Пока она у морды, размер ведёт placeBowl.
    static func growBowl(_ room: Entity?) {
        guard let room, let bowl = roomPart(room, "bowl"), bowl.position == PetRoom.bowlPos else { return }
        bowl.scale = SIMD3<Float>(repeating: 0.6 + 0.4 * growth)
    }

    static func placeBowl(_ room: Entity?, _ b: ChoreoPath.BowlPose) {
        guard let room, let bowl = roomPart(room, "bowl") else { return }
        let g = growth
        if g == 1 || b.position == PetRoom.bowlPos {
            bowl.position = b.position
        } else {
            // Под мордой: точка от центра подставки по полу ближе во столько же раз, во сколько пёс меньше.
            var local = ChoreoPath.toStand(b.position)
            local.x *= g
            local.z *= g
            bowl.position = ChoreoPath.toWorld(local)
        }
        bowl.scale = b.scale * (0.6 + 0.4 * g)
        if let food = roomPart(bowl, "food") {
            food.isEnabled = b.food > 0.01
            let side = 0.7 + 0.3 * b.food
            food.scale = SIMD3<Float>(side, max(0.45 * b.food, 0.001), side)
        }
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
            PetWear.step(e)
        }
    }
}
