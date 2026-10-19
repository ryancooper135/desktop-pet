// Сцена: RealityView с виртуальной камерой (без AR). Модель — Resources/shiba.usdz, если она есть в бандле,
// иначе заглушка из коробок и сфер в цветах Шибы (стиль A, low-poly).
// Позы — клипы одного таймлайна с переходами (PetStance), простой ведёт режиссёр, дыхание и пружины — PetJuice.
// Вещи дома в комнате — RoomDecor по AppModel.homeLevels. Надетое из капсулы — PetWear по AppModel.worn,
// вещица на полке и мячик — RoomDecor.applyShelf / applyToy по AppModel.shelf / toy.
// Шерсть — текстура штрихами по стадии (PetRoom.applyCoat), клочки на спине — PetWear.applyTufts (CoatFur).
// Вечер и ночь — RoomLighting по AppModel.roomSchedule и теме; поверх сцены — виньетка фазы (без касаний).
// Reduce Motion: статичная поза на последнем кадре цикла, без дыхания и пружин.

import SwiftUI
import UIKit
@preconcurrency import RealityKit
@preconcurrency import PetCore

struct PetStage: View {
    var pose: Pose
    /// Растёт на каждое действие: новая реакция телом (kind — feed/item/pet/play/wake/bath).
    var reactionId: Int = 0
    var reactionKind: String = ""
    var reactionOk: Bool = true
    /// Куда смотреть: −1 — влево, 1 — вправо, nil — прямо.
    var lookX: Float? = nil
    /// Растёт на каждое возвращение с прогулки (AppModel.walkHome): Шиба входит в кадр с находкой find.
    var walkHomeId: Int = 0
    var walkHomeFind: String = ""
    /// Вид шерсти (блеск, грязь). nil — как есть. Перекрашиваем только при смене значения.
    var coat: CoatLook? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Дом в комнате (RoomDecor) — уровни из модели; без модели (превью) комната как была.
    @Environment(AppModel.self) private var model: AppModel?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // В @Sendable-замыкание RealityView передаём только Sendable-значения, не self.
        let pose = self.pose
        let reduceMotion = self.reduceMotion
        let reaction = PetReaction(id: reactionId, kind: reactionKind, ok: reactionOk)
        let lookX = self.lookX
        let walkHome = (id: walkHomeId, find: walkHomeFind)
        let coat = self.coat
        let home = model?.homeLevels ?? RoomPlan.Levels()
        // Расчёсывание (BrushFx): колтунов осталось, было в начале, счётчик мазков.
        let brushTotal = model?.brushTufts ?? 0
        let brushLeft = model?.brush?.tufts(of: brushTotal) ?? 0
        let brushPuff = model?.brushPuff ?? 0
        // Клочки шерсти на спине (PetWear.applyTufts): чешем — сколько осталось в сеансе, иначе — по стадии (CoatLook.tufts).
        let tufts = brushTotal > 0 ? (left: brushLeft, total: brushTotal) : (left: coat?.tufts ?? 0, total: coat?.tufts ?? 0)
        let tuftStage = coat?.stage ?? .normal
        let schedule = model?.roomSchedule ?? RoomSchedule.standard
        let dark = colorScheme == .dark
        // Надетое из капсулы (PetWear): шапка, шарф, плащ.
        let worn = model?.worn ?? [:]
        // Вещица на полке и мячик для игры (волна 11, ItemCatalog).
        let shelf = model?.shelf
        let toy = model?.toy
        return RealityView { content in
            content.camera = .virtual
            PetModel.registerOnce()
            RoomLighting.registerOnce()
            let pet = await PetModel.load()
            pet.name = PetModel.petName
            PetRoom.matte(pet)
            PetRoom.prepareCoat(pet)
            if let coat { PetRoom.applyCoat(coat, to: pet) }
            // После prepareCoat: вещи не попадают в материалы шерсти и не перекрашиваются блеском и грязью.
            PetWear.apply(worn, to: pet)
            PetWear.applyTufts(left: tufts.left, total: tufts.total, stage: tuftStage, to: pet)
            // Подставка с поворотом 3/4: внутри питомец и пятно-тень (пятно не дышит вместе с ним).
            let stand = Entity()
            stand.name = PetModel.standName
            stand.orientation = simd_quatf(angle: PetRoom.yaw3q, axis: SIMD3<Float>(0, 1, 0))
            stand.addChild(PetRoom.blobShadow())
            stand.addChild(pet)
            content.add(stand)
            let room = PetRoom.room()
            RoomDecor.apply(home, to: room)
            RoomDecor.applyShelf(shelf, to: room)
            RoomDecor.applyToy(toy, to: room)
            // Свет — внутри комнаты: RoomLighting красит его вместе с ней, сразу нужной фазы (без мигания).
            room.addChild(PetRoom.lights())
            RoomLighting.setup(room, schedule: schedule, dark: dark)
            content.add(room)
            content.add(PetRoom.camera())
            // Лапы на матрасе лежанки, а не в нём (RoomPlan.petLift).
            PetChoreo.setHome(pet, home)
            // Клипы играем, когда питомец уже в сцене. Старую реакцию при открытии не повторяем.
            PetModel.prime(pet, reactionId: reaction.id)
            PetChoreo.walk(pet, away: pose == .away, instant: pose == .dead, homeId: walkHome.id, find: walkHome.find,
                           reduceMotion: reduceMotion)
            PetModel.apply(pose: pose, reduceMotion: reduceMotion, reaction: reaction, lookX: lookX, to: pet)
            BrushFx.prime(puff: brushPuff)
            BrushFx.apply(left: brushLeft, total: brushTotal, puff: brushPuff, reduceMotion: reduceMotion, to: pet)
        } update: { content in
            guard let stand = content.entities.first(where: { $0.name == PetModel.standName }),
                  let pet = stand.children.first(where: { $0.name == PetModel.petName }) else { return }
            // Прогулка — до позы: возвращение держит новую позу, пока Шиба не дошёл до дома.
            PetChoreo.walk(pet, away: pose == .away, instant: pose == .dead, homeId: walkHome.id, find: walkHome.find,
                           reduceMotion: reduceMotion)
            PetModel.apply(pose: pose, reduceMotion: reduceMotion, reaction: reaction, lookX: lookX, to: pet)
            if let coat { PetRoom.applyCoat(coat, to: pet) }
            PetWear.apply(worn, to: pet)
            PetWear.applyTufts(left: tufts.left, total: tufts.total, stage: tuftStage, to: pet)
            BrushFx.apply(left: brushLeft, total: brushTotal, puff: brushPuff, reduceMotion: reduceMotion, to: pet)
            // Купили уровень — вещи перестраиваются сразу (RoomDecor сам пропускает, если уровни те же).
            if let room = content.entities.first(where: { $0.name == RoomDecor.roomName }) {
                // Не через ||: все три должны отработать.
                let built = [RoomDecor.apply(home, to: room), RoomDecor.applyShelf(shelf, to: room),
                             RoomDecor.applyToy(toy, to: room)]
                let rebuilt = built.contains(true)
                RoomLighting.update(room, schedule: schedule, dark: dark, force: rebuilt)
            }
            PetChoreo.setHome(pet, home)
        }
        .overlay { RoomVignette(schedule: schedule, dark: dark) }
        .background(PetPalette.bg)
    }
}

/// Затемнение краёв кадра вечером и ночью: центр с собакой читается. Фазу сверяет раз в полминуты.
private struct RoomVignette: View {
    var schedule: RoomSchedule
    var dark: Bool

    /// Цвет краёв — ночная синева.
    static let edge = Color(red: 0x10 / 255, green: 0x16 / 255, blue: 0x2e / 255)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let v = RoomLight.at(phase: schedule.phaseNow(dark: dark)).vignette
            EllipticalGradient(stops: [.init(color: Self.edge.opacity(0), location: 0.35),
                                       .init(color: Self.edge.opacity(v), location: 1)],
                               center: UnitPoint(x: 0.5, y: 0.55), startRadiusFraction: 0, endRadiusFraction: 0.85)
                .animation(.easeInOut(duration: 1.4), value: v)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@MainActor
enum PetModel {
    static let petName = "pet"
    static let standName = "petStand"
    static let bodyName = "petBody"
    /// Обёртка между корнем и моделью: ей JuiceSystem задаёт дыхание, squash, подскок и поворот.
    static let pivotName = "petJuice"
    /// Высота питомца в метрах сцены; камера подобрана под неё.
    static let height: Float = 0.42

    static func registerOnce() {
        JuiceSystem.registerOnce()
    }

    /// Корень с JuiceComponent → petJuice → модель, приведённая к росту height и поставленная на пол.
    static func load() async -> Entity {
        let wrapper = Entity()
        var model: Entity?
        if Bundle.main.url(forResource: "shiba", withExtension: "usdz") != nil {
            model = try? await Entity(named: "shiba", in: Bundle.main)
        }
        let body = model ?? StubDog.make()
        body.name = bodyName
        let bounds = body.visualBounds(relativeTo: nil)
        if model != nil, bounds.extents.y > 0 {
            let k = height / bounds.extents.y
            body.scale = SIMD3<Float>(repeating: k)
            body.position = SIMD3<Float>(-bounds.center.x * k, -bounds.min.y * k, -bounds.center.z * k)
        }
        let pivot = Entity()
        pivot.name = pivotName
        pivot.addChild(body)
        wrapper.addChild(pivot)
        wrapper.components.set(JuiceComponent())
        if model != nil, !body.availableAnimations.isEmpty {
            if ClipTable.shared != nil {
                // Позы даёт скелет по клипам; кэш клипов — от прошлой модели, собираем заново.
                ClipPlayer.reset()
                wrapper.components.set(ClipState())
            } else if let anim = body.availableAnimations.first {
                // Нет clips.json — играем весь таймлайн по кругу, как в самом начале.
                body.playAnimation(anim.repeat())
            }
        }
        return wrapper
    }

    /// Запомнить текущую реакцию как уже показанную: при открытии экрана её не играем.
    static func prime(_ pet: Entity, reactionId: Int) {
        if var c = pet.components[JuiceComponent.self] {
            c.lastReactionId = reactionId
            pet.components.set(c)
        }
        if var st = pet.components[ClipState.self] {
            st.lastReactionId = reactionId
            pet.components.set(st)
        }
    }

    static func apply(pose: Pose, reduceMotion: Bool, to pet: Entity) {
        apply(pose: pose, reduceMotion: reduceMotion, reaction: nil, lookX: nil, to: pet)
    }

    /// Поза → дыхание и пружины (JuiceComponent) и клипы (ClipState). Реакция проверяется раньше позы.
    static func apply(pose: Pose, reduceMotion: Bool, reaction: PetReaction?, lookX: Float?, to pet: Entity) {
        let hasClips = pet.components.has(ClipState.self)
        var c = pet.components[JuiceComponent.self] ?? JuiceComponent()
        switch pose {
        case .sleep, .nap:
            c.targetRate = 0.22; c.targetAmount = 0.018
        case .critical:
            c.targetRate = 0.5; c.targetAmount = 0.03
        case .dead:
            c.targetRate = 0; c.targetAmount = 0
        default:
            c.targetRate = 0.3; c.targetAmount = 0.012
        }
        if !c.primed {
            c.rate = c.targetRate
            c.amount = c.targetAmount
            c.primed = true
        }
        if hasClips {
            // Скелет лежит и поворачивается сам: вертушки и приплющивания нет.
            c.sway = 0; c.lie = 0
        } else {
            switch pose {
            case .sleep, .nap, .dead: c.sway = 0; c.lie = 1
            case .critical, .tired: c.sway = 0.02; c.lie = 0.4
            case .happy, .loved, .eating: c.sway = 0.12; c.lie = 0
            case .bored, .lonely, .sulky: c.sway = 0.04; c.lie = 0.2
            default: c.sway = 0.07; c.lie = 0
            }
        }
        // Взгляд: телом чуть-чуть, остальное — шея и голова (PetFace). Мёртвый не смотрит.
        let look: Float = pose == .dead ? 0 : min(max(lookX ?? 0, -1), 1)
        c.yawTarget = look * (hasClips ? 0.15 : 0.35)
        var face = pet.components[PetFace.self] ?? PetFace()
        face.target = look * PetFace.limit
        face.still = reduceMotion
        pet.components.set(face)
        c.still = reduceMotion
        if reduceMotion { c.amount = 0; c.targetAmount = 0 }
        if let r = reaction, r.id != c.lastReactionId {
            c.lastReactionId = r.id
            if !reduceMotion && r.ok && pose != .dead {
                let w = JuiceComponent.omega, z = JuiceComponent.squashZeta
                switch r.kind {
                case "pet", "feed", "item", "brush", Cooking.reactKind:
                    c.squashV += PetSpring.impulse(peak: -0.12, omega: w, zeta: z)
                case "play", Habits.reactKind:
                    c.hopV += PetSpring.impulse(peak: 0.04 * height, omega: w, zeta: z)
                case "tap.playful":
                    // Игривый на тап подскакивает сам — пониже, чем в игре.
                    c.hopV += PetSpring.impulse(peak: 0.025 * height, omega: w, zeta: z)
                case let k where k.hasPrefix("trick."):
                    // Трюк вышел: подпрыгнул от радости, пониже, чем в игре.
                    c.hopV += PetSpring.impulse(peak: 0.03 * height, omega: w, zeta: z)
                default:
                    break
                }
            }
        }
        pet.components.set(c)
        if hasClips {
            drive(pet, pose: pose, reduceMotion: reduceMotion, reaction: reaction, lookX: lookX)
        }
    }

    // MARK: клипы

    /// Реакции играет сцена клипами: тявк «Голоса» ставит PetChoreo.begin на прыжке. При «Уменьшении движения»
    /// или без таблицы клипов drive до режиссёра не доходит — звук трюка тогда ставит AppModel сразу.
    static var playsReactions: Bool { !UIAccessibility.isReduceMotionEnabled && ClipTable.shared != nil }

    /// Сменить позу и/или сыграть реакцию. Реакция проверяется до сравнения ключа позы.
    static func drive(_ pet: Entity, pose: Pose, reduceMotion: Bool, reaction: PetReaction?, lookX: Float?) {
        guard var st = pet.components[ClipState.self], let table = ClipTable.shared else { return }
        let available = Set(table.clips.keys)
        let target = PetStance.stance(for: pose)
        let loop = PetStance.loop(for: pose)
        let key = PetStance.intro(for: pose).joined(separator: ",") + ">" + loop + (reduceMotion ? "~" : "")

        var fresh = false
        if let r = reaction, r.id != st.lastReactionId {
            st.lastReactionId = r.id
            fresh = true
        }
        st.reduceMotion = reduceMotion
        let poseChanged = key != st.current
        guard fresh || poseChanged else {
            // Поза вернулась к той, что играет: отложенная уже устарела.
            st.pendingPose = nil
            pet.components.set(st)
            return
        }

        if reduceMotion {
            // Без переходов и реакций: сразу статичная поза на последнем кадре цикла.
            PetChoreo.stop(pet)
            if poseChanged {
                ClipPlayer.still(loop, on: pet)
                st.current = key
                st.stance = target
                st.loop = loop
                st.busyUntil = st.clock
                st.lockUntil = st.clock
                st.pendingPose = nil
            }
            deathShift(pet, &st, animated: false)
            pet.components.set(st)
            return
        }

        // Реакция ещё идёт — новую позу доиграет режиссёр, когда она кончится.
        if !fresh && st.clock < st.lockUntil {
            st.pendingPose = pose
            pet.components.set(st)
            return
        }
        st.pendingPose = nil

        let initial = st.current.isEmpty
        var steps: [String] = []
        if !initial {
            steps += PetStance.pick(PetStance.path(from: st.stance, to: target), available: available)
        }
        var mainLoop = loop
        var endStance = target
        var reacted = false
        var petting: (offset: Double, length: Double)?
        var trick: Trick?
        if fresh, let r = reaction {
            trick = r.ok ? Trick(kind: r.kind) : nil
            let rc = PetStance.reaction(kind: r.kind, ok: r.ok, stance: target, lookX: lookX, available: available)
            if r.kind == "pet" && r.ok && target == .stand && !rc.isEmpty {
                let offset = steps.reduce(0) { $0 + PetChoreo.duration($1) }
                petting = (offset, rc.reduce(0) { $0 + PetChoreo.duration($1) })
            }
            steps += rc
            reacted = !rc.isEmpty
            st.reactionSteps = rc
            endStance = PetStance.endStance(after: rc, from: target)
            if endStance != target {
                // Реакция сменила положение (разбудили, а поза ещё «спит»): стоим так, пока не придёт новая поза.
                mainLoop = PetStance.restLoop(for: endStance)
            } else if reacted, let next = PetStance.poseAfter(reaction: r.kind, ok: r.ok),
                      PetStance.stance(for: next) == endStance {
                // Покормили: ядро следом пришлёт «ест». Реакция сразу кончается его циклом — когда поза
                // придёт, перезапускать нечего, и между едой и стойкой не мелькает прежний цикл.
                mainLoop = PetStance.loop(for: next)
            }
        }
        if poseChanged && !reacted && !initial {
            // Поза пришла следом за реакцией, которая уже сыграла её intro (подход к миске после «Покормить»), —
            // второй круг еды не играем.
            steps += PetStance.introSteps(for: pose, after: st.reactionSteps, available: available)
        }
        if !fresh {
            // Поза отыграна — следующая такая же поза снова со своим intro.
            st.reactionSteps = []
        }

        if steps.isEmpty && !initial && mainLoop == st.loop && !st.current.hasSuffix("~") {
            // Играть нечего, цикл тот же (реакция без клипа, happy→loved): не перезапускаем его.
            // После Reduce Motion («~») стоит замерший кадр — его перезапускать надо.
            st.current = key
            st.stance = endStance
            pet.components.set(st)
            return
        }

        let transition: TimeInterval = initial ? 0 : (fresh ? 0.15 : 0.25)
        let busy = ClipPlayer.play(steps, then: mainLoop, on: pet, transition: transition,
                                   randomSpeed: steps.isEmpty, initial: initial) ?? 0
        st.current = key
        st.stance = endStance
        st.loop = mainLoop
        st.busyUntil = st.clock + busy
        st.lockUntil = fresh ? st.busyUntil : st.clock
        // Миска под мордой на время eat, мяч и пробежка после play_bow: игра держит питомца дольше клипов.
        if let until = PetChoreo.begin(pet, steps: steps, clock: st.clock, mainLoop: mainLoop, trick: trick) {
            st.busyUntil = max(st.busyUntil, until)
            st.lockUntil = max(st.lockUntil, until)
        }
        if let p = petting, endStance == .stand {
            // Гладят: клонится к руке (с той стороны, куда смотрит), жмурится, виляет. Сторона руки — по lookX.
            let side: Float
            if let x = lookX, x != 0 { side = x < 0 ? -1 : 1 } else { side = Bool.random() ? -1 : 1 }
            PetChoreo.petting(pet, clock: st.clock + p.offset, length: p.length, side: side)
        }
        if endStance != target {
            // Через полторы секунды без новой позы — вернуться в прежнюю переходом.
            st.current = "~settle"
            st.pendingPose = pose
            st.lockUntil = st.busyUntil + 1.5
        }
        st.nextFidgetAt = st.busyUntil + Double.random(in: 15...25)
        deathShift(pet, &st, animated: !initial)
        pet.components.set(st)
    }

    /// Клип death валит собаку на бок, и центр уезжает вбок почти на полроста: замер скина по исходнику
    /// (tools/assets/source/shiba.glb) — середина рамки с 0 до +1.36 ед. по X модели при росте 3.09.
    /// Без поправки мёртвый лежит у края экрана головой на мяче. Сдвигаем модель обратно, пока он лежит.
    static let deathShiftX: Float = -1.36

    static func deathShift(_ pet: Entity, _ st: inout ClipState, animated: Bool) {
        let want = st.stance == .dead
        guard want != st.shifted, let body = pet.findEntity(named: bodyName) else { return }
        let base = st.bodyBase ?? body.position
        st.bodyBase = base
        st.shifted = want
        var t = body.transform
        t.translation = base + (want ? body.transform.rotation.act(SIMD3<Float>(deathShiftX * body.scale.x, 0, 0)) : .zero)
        if animated {
            // Клип падения ~1 с: съезжаем вместе с ним, а не прыжком.
            body.move(to: t, relativeTo: body.parent, duration: 1.0, timingFunction: .easeInOut)
        } else {
            body.transform = t
        }
    }

    /// Кадр режиссёра: часы, отложенная поза, фиджеты в простое.
    static func tick(_ pet: Entity, dt: TimeInterval) {
        guard var st = pet.components[ClipState.self] else { return }
        st.clock += dt
        if let p = st.pendingPose, st.clock >= st.lockUntil {
            st.pendingPose = nil
            st.lockUntil = st.clock
            pet.components.set(st)
            drive(pet, pose: p, reduceMotion: st.reduceMotion, reaction: nil, lookX: nil)
            return
        }
        guard !st.reduceMotion, st.pendingPose == nil, st.stance != .dead,
              st.clock >= st.busyUntil, st.clock >= st.nextFidgetAt, let table = ClipTable.shared else {
            pet.components.set(st)
            return
        }
        let available = Set(table.clips.keys)
        let idles = ["idle", "idle_2"]
        let standIdle = st.stance == .stand && idles.contains(st.loop)
        var options = PetStance.pick(PetStance.fidgets(for: st.stance), available: available).filter { $0 != st.loop }
        // Стоя фиджетим только в спокойном цикле; грустная стойка (idle_headlow) просто дышит.
        if st.stance == .stand && !standIdle { options = [] }

        // Каждые 2–3 фиджета — смена цикла idle ↔ idle_2. Нечего вставить — меняем цикл сразу.
        var loop = st.loop
        st.fidgets += 1
        if standIdle && (st.fidgets >= st.swapEvery || options.isEmpty) {
            let other = st.loop == "idle" ? "idle_2" : "idle"
            if available.contains(other) {
                loop = other
                options = options.filter { $0 != other }
            }
            st.fidgets = 0
            st.swapEvery = Int.random(in: 2...3)
        }
        let fidget = options.randomElement()
        if fidget == nil && loop == st.loop {
            st.nextFidgetAt = st.clock + Double.random(in: 15...25)
            pet.components.set(st)
            return
        }
        let busy = ClipPlayer.play(fidget.map { [$0] } ?? [], then: loop, on: pet, transition: 0.3,
                                   randomSpeed: true, initial: false) ?? 0
        st.loop = loop
        st.busyUntil = st.clock + busy
        st.nextFidgetAt = st.busyUntil + Double.random(in: 15...25)
        pet.components.set(st)
    }

    static func floor() -> Entity {
        let mat = SimpleMaterial(color: UIColor(red: 0.86, green: 0.78, blue: 0.70, alpha: 1), roughness: 0.9, isMetallic: false)
        let plane = ModelEntity(mesh: .generatePlane(width: 2.4, depth: 2.4), materials: [mat])
        plane.position = SIMD3<Float>(0, 0, 0)
        return plane
    }

    static func camera() -> Entity {
        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = 38
        cam.look(at: SIMD3<Float>(0, height * 0.55, 0), from: SIMD3<Float>(0.35, height * 1.35, 1.25), relativeTo: nil)
        return cam
    }

    static func light() -> Entity {
        let sun = DirectionalLight()
        sun.light.intensity = 2800
        sun.look(at: SIMD3<Float>(0, 0, 0), from: SIMD3<Float>(0.8, 1.6, 1.0), relativeTo: nil)
        return sun
    }
}

/// Заглушка, пока нет shiba.usdz: туловище, голова, морда, уши, хвост и лапы. Смотрит на камеру (+z).
@MainActor
enum StubDog {
    /// Пустой ребёнок-метка: по нему PetWear узнаёт заглушку и надевает вещи по её коробкам.
    static let markName = "stubDog"

    static func make() -> Entity {
        let root = Entity()
        let mark = Entity()
        mark.name = markName
        root.addChild(mark)
        let fur = mat(0xe39a55), dark = mat(0xc97a3a), cream = mat(0xfbebd6), ink = mat(0x4a3b33)
        func box(_ size: SIMD3<Float>, _ pos: SIMD3<Float>, _ m: SimpleMaterial) {
            let e = ModelEntity(mesh: .generateBox(size: size), materials: [m])
            e.position = pos
            root.addChild(e)
        }
        // Лапы
        for x: Float in [-0.065, 0.065] {
            for z: Float in [-0.10, 0.10] {
                box(SIMD3<Float>(0.055, 0.10, 0.055), SIMD3<Float>(x, 0.05, z), cream)
            }
        }
        // Туловище и грудка
        box(SIMD3<Float>(0.20, 0.15, 0.32), SIMD3<Float>(0, 0.17, 0), fur)
        box(SIMD3<Float>(0.14, 0.10, 0.04), SIMD3<Float>(0, 0.16, 0.16), cream)
        // Голова, морда, нос, глаза
        box(SIMD3<Float>(0.19, 0.16, 0.16), SIMD3<Float>(0, 0.31, 0.15), fur)
        box(SIMD3<Float>(0.10, 0.07, 0.07), SIMD3<Float>(0, 0.27, 0.25), cream)
        box(SIMD3<Float>(0.035, 0.025, 0.02), SIMD3<Float>(0, 0.295, 0.29), ink)
        box(SIMD3<Float>(0.025, 0.03, 0.01), SIMD3<Float>(-0.045, 0.335, 0.232), ink)
        box(SIMD3<Float>(0.025, 0.03, 0.01), SIMD3<Float>(0.045, 0.335, 0.232), ink)
        // Уши
        box(SIMD3<Float>(0.05, 0.07, 0.03), SIMD3<Float>(-0.06, 0.42, 0.13), dark)
        box(SIMD3<Float>(0.05, 0.07, 0.03), SIMD3<Float>(0.06, 0.42, 0.13), dark)
        // Хвост бубликом
        let tail = ModelEntity(mesh: .generateSphere(radius: 0.055), materials: [fur])
        tail.position = SIMD3<Float>(0, 0.28, -0.17)
        root.addChild(tail)
        return root
    }

    private static func mat(_ hex: UInt32) -> SimpleMaterial {
        let c = UIColor(red: CGFloat((hex >> 16) & 0xff) / 255,
                        green: CGFloat((hex >> 8) & 0xff) / 255,
                        blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        return SimpleMaterial(color: c, roughness: 0.8, isMetallic: false)
    }
}

// MARK: - Клипы

/// Что сейчас играет и где режиссёр простоя. Время — свои часы по deltaTime, не Date.
struct ClipState: Component {
    /// Ключ позы (intro>цикл, «~» — Reduce Motion). Пусто — ещё ничего не играли.
    var current = ""
    var stance: Stance = .stand
    /// Цикл, который крутится сейчас (idle и idle_2 режиссёр меняет местами).
    var loop = ""
    var lastReactionId = 0
    var clock: TimeInterval = 0
    /// До этого момента идут одноразовые клипы: фиджеты не вставляем.
    var busyUntil: TimeInterval = 0
    /// До этого момента реакцию не перебиваем: новая поза ждёт в pendingPose.
    var lockUntil: TimeInterval = 0
    var nextFidgetAt: TimeInterval = 20
    var fidgets = 0
    var swapEvery = 2
    var reduceMotion = false
    var pendingPose: Pose? = nil
    /// Клипы последней реакции: поза, пришедшая следом (покормили → «ест»), не повторяет их своим intro.
    var reactionSteps: [String] = []
    /// Положение модели после load(): от него считается сдвиг лёжа на боку (deathShift).
    var bodyBase: SIMD3<Float>? = nil
    var shifted = false
}

/// shiba.clips.json из tools/assets: клипы — куски одной анимации «Clips», границы в секундах.
struct ClipTable: Decodable, Sendable {
    struct Clip: Decodable, Sendable {
        var start: Double
        var end: Double
        var loop: Bool
    }
    var fps: Double
    var clips: [String: Clip]

    static let shared: ClipTable? = {
        guard let url = Bundle.main.url(forResource: "shiba.clips", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode(ClipTable.self, from: data))?.addingEatParts()
    }()

    /// Таблица плюс части eat (EatClip): опустил голову / жуёт по кругу / поднял. Своих частей в файле нет —
    /// режем eat по кадрам EatClip.chewFrom/chewTo. Уже есть или eat слишком короткий — таблица как была.
    func addingEatParts() -> ClipTable {
        guard let eat = clips["eat"], !EatClip.parts.contains(where: { clips[$0] != nil }),
              let ranges = EatClip.ranges(start: eat.start, end: eat.end, fps: fps) else { return self }
        var out = self
        for r in ranges {
            out.clips[r.name] = Clip(start: r.start, end: r.end, loop: r.name == EatClip.chew)
        }
        return out
    }
}

/// Проигрыватель клипов: вырезает куски из таймлайна «Clips», склеивает в sequence, держит кэш и контроллеры.
@MainActor
enum ClipPlayer {
    enum Mode {
        case once   // один раз
        case loop   // по кругу
        case hold   // один раз и стоять на последнем кадре (death)
        case still  // только последний кадр (Reduce Motion, открытие экрана мёртвым)
    }

    static let loopCount = 100_000
    private static var cache: [String: AnimationResource] = [:]
    private static var controllers: [ObjectIdentifier: AnimationPlaybackController] = [:]

    static func reset() {
        cache.removeAll()
        controllers.removeAll()
    }

    /// Клип из таблицы; нет клипа или не собрался — nil, шаг пропускается.
    static func resource(_ name: String, mode: Mode, source: AnimationResource, table: ClipTable) -> AnimationResource? {
        guard let c = table.clips[name], c.end > c.start else { return nil }
        let key: String
        switch mode {
        case .once: key = name
        case .loop: key = name + "×\(loopCount)"
        case .hold: key = name + "!"
        case .still: key = name + "·"
        }
        if let r = cache[key] { return r }
        var start = c.start
        if mode == .still {
            start = max(c.start, c.end - 1 / max(table.fps, 1))
        }
        let hold = mode == .hold || mode == .still
        let view = AnimationView(source: source.definition, name: name,
                                 fillMode: hold ? .forwards : [],
                                 trimStart: start, trimEnd: c.end)
        guard var res = try? AnimationResource.generate(with: view) else { return nil }
        if mode == .loop { res = res.repeat(count: loopCount) }
        cache[key] = res
        return res
    }

    /// Сыграть шаги по разу, потом цикл loop. Возвращает, сколько секунд идут одноразовые клипы; nil — играть нечего.
    @discardableResult
    static func play(_ steps: [String], then loop: String, on pet: Entity, transition: TimeInterval,
                     randomSpeed: Bool, initial: Bool) -> TimeInterval? {
        guard let table = ClipTable.shared,
              let body = pet.findEntity(named: PetModel.bodyName),
              let source = body.availableAnimations.first else { return nil }
        var steps = steps
        let main = table.clips[loop]
        let looping = main?.loop ?? false
        // death — не цикл: играет один раз и стоит. Если путь уже кончается им, второй раз не играем.
        if main != nil, !looping, steps.last == loop { steps.removeLast() }

        var parts: [AnimationResource] = []
        var busy: TimeInterval = 0
        for s in steps {
            guard let c = table.clips[s], let r = resource(s, mode: .once, source: source, table: table) else { continue }
            parts.append(r)
            busy += c.end - c.start
        }
        if let c = main {
            let mode: Mode = looping ? .loop : (initial && parts.isEmpty ? .still : .hold)
            if let r = resource(loop, mode: mode, source: source, table: table) {
                parts.append(r)
                if mode == .hold { busy += c.end - c.start }
            }
        }
        guard !parts.isEmpty else { return nil }

        let res: AnimationResource
        if parts.count == 1 {
            res = parts[0]
        } else {
            guard let seq = try? AnimationResource.sequence(with: parts) else { return nil }
            res = seq
        }
        let ctl = body.playAnimation(res, transitionDuration: transition, startsPaused: false)
        // Живость: циклы и фиджеты чуть быстрее или медленнее, переходы — ровно 1.
        let speed: Float = randomSpeed ? Float.random(in: 0.92...1.08) : 1
        ctl.speed = speed
        keep(ctl, for: pet)
        return busy / TimeInterval(speed)
    }

    /// Reduce Motion: сразу последний кадр клипа, без перехода и движения.
    static func still(_ name: String, on pet: Entity) {
        guard let table = ClipTable.shared,
              let body = pet.findEntity(named: PetModel.bodyName),
              let source = body.availableAnimations.first,
              let res = resource(name, mode: .still, source: source, table: table) else { return }
        let ctl = body.playAnimation(res, transitionDuration: 0, startsPaused: false)
        keep(ctl, for: pet)
    }

    private static func keep(_ ctl: AnimationPlaybackController, for pet: Entity) {
        let id = ObjectIdentifier(pet)
        if controllers.count > 8 { controllers.removeAll() }
        controllers[id] = ctl
    }
}
