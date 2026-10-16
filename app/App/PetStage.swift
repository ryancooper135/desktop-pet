// Сцена: RealityView с виртуальной камерой (без AR). Модель — Resources/shiba.usdz, если она есть в бандле,
// иначе заглушка из коробок и сфер в цветах Шибы (стиль A, low-poly).
// Дыхание и покачивание — своя ECS-система по компоненту на обёртке питомца. При Reduce Motion — стоит неподвижно.

import SwiftUI
import UIKit
@preconcurrency import RealityKit
@preconcurrency import PetCore

struct PetStage: View {
    var pose: Pose
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // В @Sendable-замыкание RealityView передаём только Sendable-значения, не self.
        let pose = self.pose
        let reduceMotion = self.reduceMotion
        return RealityView { content in
            content.camera = .virtual
            BreatheSystem.registerOnce()
            let pet = await PetModel.load()
            pet.name = PetModel.petName
            PetModel.apply(pose: pose, reduceMotion: reduceMotion, to: pet)
            content.add(pet)
            content.add(PetModel.floor())
            content.add(PetModel.camera())
            content.add(PetModel.light())
        } update: { content in
            guard let pet = content.entities.first(where: { $0.name == PetModel.petName }) else { return }
            PetModel.apply(pose: pose, reduceMotion: reduceMotion, to: pet)
        }
        .background(PetPalette.bg)
    }
}

@MainActor
enum PetModel {
    static let petName = "pet"
    /// Высота питомца в метрах сцены; камера подобрана под неё.
    static let height: Float = 0.42

    /// Обёртка с BreatheComponent; внутри — модель, приведённая к росту height и поставленная на пол.
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
        wrapper.addChild(body)
        wrapper.components.set(BreatheComponent())
        // Клипы есть — позы даёт скелет; нет таблицы — играем всю анимацию по кругу, как раньше.
        if model != nil, ClipTable.shared != nil, !body.availableAnimations.isEmpty {
            wrapper.components.set(ClipState())
        } else if let anim = body.availableAnimations.first {
            body.playAnimation(anim.repeat())
        }
        return wrapper
    }

    static let bodyName = "petBody"

    /// Какой клип играть в позе и чем в него войти (sit_in, sleep_in…).
    static func clip(for pose: Pose) -> (intro: String?, main: String) {
        switch pose {
        case .happy, .loved: return (nil, "idle_2")
        case .eating: return (nil, "eat")
        case .sleep, .nap: return ("sleep_in", "sleep")
        case .critical, .tired: return ("lie_in", "lie")
        case .bored, .lonely, .sulky, .hungry: return (nil, "idle_headlow")
        case .dirty, .bath: return ("sit_in", "sit")
        case .dead: return (nil, "death")
        case .idle: return (nil, "idle")
        }
    }

    static func playClip(for pose: Pose, reduceMotion: Bool, on pet: Entity) {
        guard var st = pet.components[ClipState.self], let table = ClipTable.shared,
              let body = pet.findEntity(named: bodyName), let source = body.availableAnimations.first else { return }
        var (intro, main) = clip(for: pose)
        if reduceMotion { intro = nil }
        let key = main + (reduceMotion ? "~" : "")
        guard st.current != key, let mc = table.clips[main] else { return }
        do {
            let mainView = AnimationView(source: source.definition, name: main,
                                         fillMode: mc.loop ? [] : .forwards,
                                         trimStart: mc.start, trimEnd: mc.end)
            var res = try AnimationResource.generate(with: mainView)
            if mc.loop && !reduceMotion { res = res.repeat(count: 100_000) }
            if let i = intro, let ic = table.clips[i], !st.current.isEmpty {
                let introView = AnimationView(source: source.definition, name: i, trimStart: ic.start, trimEnd: ic.end)
                res = try AnimationResource.sequence(with: [AnimationResource.generate(with: introView), res])
            }
            let ctl = body.playAnimation(res, transitionDuration: st.current.isEmpty ? 0 : 0.3, startsPaused: false)
            // Reduce Motion: встал в позу и замер на первом кадре цикла.
            if reduceMotion && mc.loop { ctl.pause() }
            st.current = key
            pet.components.set(st)
        } catch {
            st.current = key
            pet.components.set(st)
        }
    }

    static func apply(pose: Pose, reduceMotion: Bool, to pet: Entity) {
        let hasClips = pet.components.has(ClipState.self)
        if hasClips { playClip(for: pose, reduceMotion: reduceMotion, on: pet) }
        var c = pet.components[BreatheComponent.self] ?? BreatheComponent()
        switch pose {
        case .sleep, .nap:
            c.rate = 0.18; c.amount = 0.035; c.sway = 0; c.lie = 1
        case .dead:
            c.rate = 0; c.amount = 0; c.sway = 0; c.lie = 1
        case .critical, .tired:
            c.rate = 0.22; c.amount = 0.015; c.sway = 0.02; c.lie = 0.4
        case .happy, .loved, .eating:
            c.rate = 0.45; c.amount = 0.03; c.sway = 0.12; c.lie = 0
        case .bored, .lonely, .sulky:
            c.rate = 0.25; c.amount = 0.02; c.sway = 0.04; c.lie = 0.2
        default:
            c.rate = 0.3; c.amount = 0.025; c.sway = 0.07; c.lie = 0
        }
        if reduceMotion {
            c.amount = 0
            c.sway = 0
        }
        // Лежит и спит скелет сам; приплющивание — только для заглушки.
        if hasClips { c.lie = 0 }
        pet.components.set(c)
        if reduceMotion || pose == .dead {
            // Система всё равно поставит позу в следующем кадре, но без движения.
            pet.scale = SIMD3<Float>(1, 1 - 0.3 * c.lie, 1)
            pet.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        }
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
    static func make() -> Entity {
        let root = Entity()
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

// MARK: - Дыхание

/// rate — вдохов в секунду, amount — доля роста по y, sway — амплитуда покачивания (рад), lie — насколько «лёг» (0…1).
struct BreatheComponent: Component {
    var rate: Float = 0.3
    var amount: Float = 0.025
    var sway: Float = 0.07
    var lie: Float = 0
    var phase: Float = 0
}

struct BreatheSystem: System {
    private let query = EntityQuery(where: .has(BreatheComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        for e in context.entities(matching: query, updatingSystemWhen: .rendering) {
            guard var c = e.components[BreatheComponent.self] else { continue }
            c.phase += dt
            let breath = 1 + c.amount * sin(c.phase * c.rate * 2 * .pi)
            let ly = 1 - 0.3 * c.lie
            e.scale = SIMD3<Float>(1, ly * breath, 1)
            let angle = c.sway * sin(c.phase * 0.35 * 2 * .pi)
            e.orientation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
            e.components.set(c)
        }
    }

    @MainActor private static var registered = false

    @MainActor static func registerOnce() {
        guard !registered else { return }
        registered = true
        BreatheComponent.registerComponent()
        ClipState.registerComponent()
        BreatheSystem.registerSystem()
    }
}

// MARK: - Клипы

/// Какой клип сейчас играет (ключ: имя клипа, «~» — замер при Reduce Motion).
struct ClipState: Component {
    var current = ""
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
        return try? JSONDecoder().decode(ClipTable.self, from: data)
    }()
}
