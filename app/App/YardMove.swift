// Волна 36 Q: сцена переезда двора (RESEARCH/20-tycoon-design.md §7). Фургон у дома: коробки по сходне
// въезжают в кузов, фургон покачивается на холостых, Шиба сидит в кабине и смотрит в боковое окно.
// Пока модель пса грузится, в окне его силуэт (голова в цветах шерсти) — сцена не бывает пустой.
// К экрану двора не подключено: подтверждение переезда и сама логика — отдельная задача (Yard.district(moves:)).
// Превью — «Двор 3D» → «Переезд» (Настройки → Для разработки).

import RealityKit
import SwiftUI

/// Цвета фургона и коробок (0xRRGGBB).
enum YardMoveColors {
    static let van: UInt32 = 0xf2ede4
    static let chassis: UInt32 = 0x4a4f57
    static let tire: UInt32 = 0x2f3237
    static let hub: UInt32 = 0x9aa6ad
    static let glass: UInt32 = 0xbfe3f0
    static let cabin: UInt32 = 0x6b5e52
    static let headlight: UInt32 = 0xfff3c4
    static let taillight: UInt32 = 0xd9483b
    static let cardboard: UInt32 = 0xc89a62
    static let cardboardDark: UInt32 = 0xa97c4a
    static let tape: UInt32 = 0xe9d3a6
    static let road: UInt32 = 0x5b5f66
    static let dash: UInt32 = 0xf1ece2
    // Силуэт Шибы, пока грузится модель (цвета StubDog).
    static let fur: UInt32 = 0xe39a55
    static let furDark: UInt32 = 0xc97a3a
    static let cream: UInt32 = 0xfbebd6
    static let ink: UInt32 = 0x4a3b33
}

extension YardArt {
    /// Узлы сцены, которые ищет YardMoveStage: кузов (к нему садится пёс) и силуэт пса.
    static let moveVanNode = "van"
    static let moveStubNode = "dogStub"
    /// Где пёс сидит в кабине (координаты узла «van») и его масштаб.
    static let moveSeat = SIMD3<Float>(0.45, 0.4, -0.04)
    static let moveDogScale: Float = 0.8

    /// Фургон переезда. Земля — район, откуда уезжаем; полоса на борту и знак у дороги — цвета района, куда едем.
    /// calm (Reduce Motion) — без качки и без въезжающих коробок: они уже стоят в кузове.
    static func moveScene(from: YardDistrict, to: YardDistrict, calm: Bool = false) -> YardArtModel {
        var m = YardArtModel(name: "yardMove")
        let src = from.palette, dst = to.palette
        typealias C = YardMoveColors

        // Земля района и дорога с разметкой.
        m.box(src.ground, SIMD3(7, 0.02, 4.4), at: SIMD3(0, -0.02, -0.6))
        m.box(C.road, SIMD3(7, 0.012, 1.7), at: SIMD3(0, -0.004, 0.15))
        for k in -3...3 {
            m.box(C.dash, SIMD3(0.32, 0.006, 0.05), at: SIMD3(Float(k) * 0.7 + 0.2, 0.004, 0.82))
        }
        // Бордюр и полоса района за фургоном.
        m.box(src.paving, SIMD3(7, 0.05, 0.12), at: SIMD3(0, 0.02, -0.76))

        // Колёса стоят, качается кузов над ними.
        for x: Float in [-0.5, 0.5] {
            for z: Float in [-0.32, 0.32] {
                m.prism(C.tire, sides: 8, r: 0.13, h: 0.07, at: SIMD3(x, 0.13, z), rot: SIMD3(90, 0, 0))
                m.prism(C.hub, sides: 6, r: 0.055, h: 0.074, at: SIMD3(x, 0.13, z), rot: SIMD3(90, 0, 0))
            }
        }

        // Сходня к открытому кузову и коробки, которые ещё ждут погрузки.
        m.box(C.chassis, SIMD3(0.5, 0.02, 0.3), at: SIMD3(-1.02, 0.1, 0), rot: SIMD3(0, 0, 24))
        cardboard(&m, SIMD3(0.18, 0.18, 0.18), at: SIMD3(-1.3, 0.09, 0.5))
        cardboard(&m, SIMD3(0.15, 0.13, 0.15), at: SIMD3(-1.3, 0.245, 0.5), rot: 15)
        cardboard(&m, SIMD3(0.16, 0.14, 0.2), at: SIMD3(-1.55, 0.07, 0.22), rot: -10)

        // Знак у дороги: столб и стрелка в цвете района, куда едем.
        m.prism(C.chassis, sides: 6, r: 0.018, h: 0.8, at: SIMD3(1.25, 0.4, -0.55))
        m.box(dst.houseRoof, SIMD3(0.3, 0.14, 0.02), at: SIMD3(1.33, 0.74, -0.55))
        m.box(dst.houseRoof, SIMD3(0.12, 0.12, 0.02), at: SIMD3(1.47, 0.74, -0.55), rot: SIMD3(0, 0, 45))
        m.box(dst.ground, SIMD3(0.18, 0.03, 0.021), at: SIMD3(1.32, 0.74, -0.55))

        // Кузов и кабина — в одном узле: качаются вместе, с ними и пёс (YardMoveStage сажает его в этот узел).
        m.node(moveVanNode, at: .zero,
               motion: calm ? nil : YardArtMotion.swing(axis: SIMD3(1, 0, 0), deg: 1.1, period: 1.7, phase: 0))
        m.box(C.chassis, SIMD3(1.62, 0.06, 0.6), at: SIMD3(0, 0.16, 0))
        // Грузовой отсек: пол, крыша, борта, перегородка; зад открыт (шторка поднята).
        m.box(C.van, SIMD3(1.05, 0.04, 0.68), at: SIMD3(-0.275, 0.2, 0))
        m.box(C.van, SIMD3(1.07, 0.04, 0.7), at: SIMD3(-0.275, 0.86, 0))
        m.box(C.van, SIMD3(1.05, 0.62, 0.03), at: SIMD3(-0.275, 0.53, 0.335))
        m.box(C.van, SIMD3(1.05, 0.62, 0.03), at: SIMD3(-0.275, 0.53, -0.335))
        m.box(C.cabin, SIMD3(0.03, 0.62, 0.64), at: SIMD3(0.235, 0.53, 0))
        m.box(C.chassis, SIMD3(0.04, 0.1, 0.7), at: SIMD3(-0.8, 0.8, 0))
        for z: Float in [-0.3, 0.3] {
            m.box(C.taillight, SIMD3(0.02, 0.06, 0.05), at: SIMD3(-0.81, 0.3, z), glow: true)
        }
        // Полоса и домик на борту — цвета нового района.
        m.box(dst.houseRoof, SIMD3(1.0, 0.07, 0.01), at: SIMD3(-0.27, 0.42, 0.352))
        m.box(dst.wall, SIMD3(0.14, 0.1, 0.012), at: SIMD3(-0.3, 0.6, 0.352))
        m.prism(dst.houseRoof, sides: 3, r: 0.1, h: 0.014, at: SIMD3(-0.3, 0.7, 0.352), rot: SIMD3(90, 0, 0))
        m.box(dst.ground, SIMD3(0.04, 0.06, 0.014), at: SIMD3(-0.3, 0.58, 0.353))
        // Уже погруженное — видно в открытый зад.
        cardboard(&m, SIMD3(0.2, 0.2, 0.2), at: SIMD3(0.08, 0.32, -0.15))
        cardboard(&m, SIMD3(0.2, 0.2, 0.2), at: SIMD3(0.08, 0.32, 0.12), rot: 8)
        cardboard(&m, SIMD3(0.17, 0.16, 0.17), at: SIMD3(0.06, 0.5, -0.03), rot: -12)
        // Кабина: низ, стойки вокруг бокового окна, крыша, лобовое стекло, фары, бампер.
        m.box(C.van, SIMD3(0.53, 0.32, 0.68), at: SIMD3(0.515, 0.34, 0))
        m.box(C.van, SIMD3(0.08, 0.3, 0.03), at: SIMD3(0.29, 0.65, 0.325))
        m.box(C.van, SIMD3(0.06, 0.3, 0.03), at: SIMD3(0.62, 0.65, 0.325))
        m.box(C.van, SIMD3(0.39, 0.05, 0.03), at: SIMD3(0.445, 0.785, 0.325))
        m.box(C.van, SIMD3(0.39, 0.3, 0.03), at: SIMD3(0.445, 0.65, -0.325))
        m.box(C.van, SIMD3(0.44, 0.04, 0.68), at: SIMD3(0.455, 0.82, 0))
        m.box(C.cabin, SIMD3(0.3, 0.02, 0.6), at: SIMD3(0.45, 0.505, 0))
        m.box(C.glass, SIMD3(0.03, 0.34, 0.62), at: SIMD3(0.69, 0.66, 0), rot: SIMD3(0, 0, 17))
        m.box(C.chassis, SIMD3(0.06, 0.08, 0.7), at: SIMD3(0.8, 0.22, 0))
        m.box(C.chassis, SIMD3(0.02, 0.1, 0.36), at: SIMD3(0.785, 0.38, 0))
        for z: Float in [-0.25, 0.25] {
            m.box(C.headlight, SIMD3(0.02, 0.06, 0.09), at: SIMD3(0.785, 0.4, z), glow: true)
        }
        m.box(C.chassis, SIMD3(0.06, 0.04, 0.02), at: SIMD3(0.5, 0.42, 0.345))

        // Силуэт пса в окне — пока не приехала модель (YardMoveStage выключает узел, когда пёс сел).
        m.node(moveStubNode, at: SIMD3(0.45, 0.64, 0.05))
        m.box(C.fur, SIMD3(0.16, 0.13, 0.14), at: .zero)
        m.box(C.cream, SIMD3(0.09, 0.05, 0.07), at: SIMD3(0, -0.035, 0.09))
        m.box(C.ink, SIMD3(0.03, 0.022, 0.02), at: SIMD3(0, -0.02, 0.13))
        for x: Float in [-0.04, 0.04] {
            m.prism(C.furDark, sides: 3, r: 0.035, h: 0.06, top: 0, at: SIMD3(x, 0.09, 0))
            m.box(C.ink, SIMD3(0.02, 0.022, 0.01), at: SIMD3(x, 0.02, 0.071))
        }

        // Три коробки по очереди въезжают по сходне и уходят вглубь кузова (за борт — их уже не видно).
        guard !calm else { return m }
        let inside = SIMD3<Float>(-0.5, 0.3, 0)
        let keys: [YardArtKey] = [
            YardArtKey(t: 0, offset: SIMD3(-0.83, -0.2, 0), scale: 0, angle: 24),
            YardArtKey(t: 0.06, offset: SIMD3(-0.83, -0.2, 0), scale: 1, angle: 24),
            YardArtKey(t: 0.42, offset: SIMD3(-0.34, 0.01, 0), scale: 1, angle: 24),
            YardArtKey(t: 0.52, offset: SIMD3(-0.2, 0, 0), scale: 1, angle: 0),
            YardArtKey(t: 0.84, offset: SIMD3(0.3, 0, 0), scale: 1, angle: 0),
            YardArtKey(t: 0.88, offset: SIMD3(0.3, 0, 0), scale: 0, angle: 0),
            YardArtKey(t: 1, offset: SIMD3(-0.83, -0.2, 0), scale: 0, angle: 24),
        ]
        for (i, phase) in [Float(0), 0.34, 0.67].enumerated() {
            m.node("moveBox\(i)", at: inside, motion: .keys(keys, axis: SIMD3(0, 0, 1), period: 4.5, phase: phase))
            cardboard(&m, i == 1 ? SIMD3(0.15, 0.13, 0.16) : SIMD3(0.17, 0.16, 0.17), at: .zero)
        }
        return m
    }

    /// Коробка с лентой поверх: 24 треугольника.
    private static func cardboard(_ m: inout YardArtModel, _ size: SIMD3<Float>, at: SIMD3<Float>, rot: Float = 0) {
        m.box(YardMoveColors.cardboard, size, at: at, rot: SIMD3(0, rot, 0))
        m.box(YardMoveColors.tape, SIMD3(size.x * 0.28, 0.006, size.z + 0.004),
              at: at + SIMD3(0, size.y / 2, 0), rot: SIMD3(0, rot, 0))
    }
}

// MARK: - Сцена

@MainActor
enum YardMoveStage {
    /// Фургон, свет и камера. Пёс садится позже (seat) — модель грузится асинхронно.
    static func scene(from: YardDistrict, to: YardDistrict, calm: Bool) -> Entity {
        let world = Entity()
        world.name = "yardMove"
        world.components.set(YardArtMotionComponent(motion: .pulse(amount: 0, period: 1, phase: 0), base: .zero))
        world.addChild(YardArtStage.entity(YardArt.moveScene(from: from, to: to, calm: calm)))
        world.addChild(YardArtStage.camera(target: SIMD3(-0.15, 0.42, 0), eye: SIMD3(-1.9, 1.25, 2.9), fov: 42))
        world.addChild(PetRoom.lights())
        return world
    }

    /// Шиба (shiba.usdz или заглушка) — в кабину, сидит и смотрит в окно; силуэт гаснет.
    static func seat(in world: Entity) async {
        let dog = await YardDogLive.model()
        guard let van = world.findEntity(named: YardArt.moveVanNode) else { return }
        let root = Entity()
        root.name = "yard.move.dog"
        root.position = YardArt.moveSeat
        root.scale = SIMD3<Float>(repeating: YardArt.moveDogScale)
        // Чуть к камере (она слева спереди): морда в окне, а не в профиль.
        root.orientation = simd_quatf(angle: -0.45, axis: SIMD3(0, 1, 0))
        root.addChild(dog)
        van.addChild(root)
        YardDogLive.play(YardDogClips(once: [], loop: ["sit"]), on: dog, initial: true)
        world.findEntity(named: YardArt.moveStubNode)?.isEnabled = false
    }
}

/// Экран переезда: подпись «Переезжаем: Улица → Зимний квартал» и фургон. Фон — небо района, куда едем.
struct YardMoveView: View {
    let from: YardDistrict
    let to: YardDistrict
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var onScreen = false

    var body: some View {
        let from = self.from, to = self.to, calm = reduceMotion
        VStack(spacing: 14) {
            Text(YardDistrict.moveCaption(from: from, to: to))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(hex: 0x3a3330))
                .accessibilityIdentifier("yard.move.caption")
            // Сцена рождается после въезда экрана снизу: RealityView, созданный за краем, на CI оставался пустым.
            // Пёс садится отдельной задачей — фургон виден сразу, не ждёт загрузки модели.
            Group {
                if onScreen {
                    RealityView { content in
                        content.camera = .virtual
                        YardArtSystem.registerOnce()
                        let world = YardMoveStage.scene(from: from, to: to, calm: calm)
                        content.add(world)
                        Task { @MainActor in await YardMoveStage.seat(in: world) }
                    }
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 380)
            .accessibilityElement()
            .accessibilityLabel("Фургон у дома, коробки едут в кузов, Шиба сидит в кабине")
            .accessibilityIdentifier("yard.move.scene")
            Text("Станции едут с нами — во дворе нового района всё строится заново")
                .font(.system(.subheadline, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(hex: 0x3a3330).opacity(0.75))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(to.skyColor(night: false).ignoresSafeArea())
        .task {
            // Экран въезжает снизу ~0,5 с; на медленном симуляторе дольше — ждём с запасом.
            try? await Task.sleep(for: .milliseconds(900))
            onScreen = true
        }
    }
}
