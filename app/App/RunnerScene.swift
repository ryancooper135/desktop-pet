// Раннер (волна 55b): 3D-мир заезда на RealityKit. Логика — RunnerRun (Shared/Runner.swift), тут только картинка.
// Лёгкий рендер: пёс — та же модель породы, что во дворе (YardDogLive.model: Шиба или Хаски из сейва, клипы gallop /
// gallop_jump), всё остальное — простые фигуры из пулов. Мир едет навстречу камере, пёс стоит у начала координат и только
// перебегает полосы, прыгает и проползает. Объекты не создаются в кадре: пулы на каждый вид (RunnerPool), лишние гаснут.
// Дальний край — проявление масштабом (pop), чтобы вещи не выскакивали. Reduce Motion: монеты не крутятся, голуби
// не качаются, камера не идёт за псом, неуязвимость — ровная полупрозрачность без мигания.
// Время двигают два источника (RunnerSession.frame): система RunnerTickSystem на кадрах рендера (вровень с экраном)
// и запасной цикл экрана — на CI RealityView под fullScreenCover может не нарисовать ни кадра, а заезд должен идти.

import RealityKit
import SwiftUI
import UIKit
@preconcurrency import PetCore

// MARK: - Сессия: заезд + часы + сцена

/// Заезд одного экрана. Наблюдаемые поля — только для HUD и меняются, лишь когда число другое (60 раз в секунду
/// перерисовывать SwiftUI незачем). Сам заезд и часы — без наблюдения.
@Observable @MainActor
final class RunnerSession {
    @ObservationIgnored private(set) var run = RunnerRun(seed: 1)
    @ObservationIgnored private var clock = FrameClock(now: ProcessInfo.processInfo.systemUptime)
    /// Когда последний раз шагнули: запасной цикл молчит, пока кадры рендера идут сами.
    @ObservationIgnored private(set) var lastTick: TimeInterval = 0
    /// Приложение активно (scenePhase): в фоне время заезда стоит.
    @ObservationIgnored var live = true
    /// Заезд идёт (фаза «играем», не снимок UI-теста).
    @ObservationIgnored private(set) var running = false
    @ObservationIgnored private(set) var frozen = false
    @ObservationIgnored var calm = Motion.reduce
    @ObservationIgnored let world = RunnerWorld()
    /// Звук монеты — не чаще раза в 0,15 с (косточки идут цепочкой).
    @ObservationIgnored private var lastChime: TimeInterval = 0
    @ObservationIgnored private var aheadRow = -1

    // HUD
    private(set) var metres = 0
    private(set) var lives = RunnerConfig.shared.lives
    private(set) var picked = 0
    private(set) var biome = RunnerBiome.yard
    private(set) var lane = 1
    private(set) var over = false
    /// Что впереди — для VoiceOver; меняется с каждым новым рядом.
    private(set) var ahead = ""

    /// Новый заезд с нуля.
    func start(seed: UInt64) {
        load(RunnerRun(seed: seed), running: true)
    }

    /// Готовый заезд (снимок UI-теста или автопилот): running == false — стоит.
    func load(_ r: RunnerRun, running: Bool) {
        run = r
        self.running = running
        frozen = !running
        clock = FrameClock(now: ProcessInfo.processInfo.systemUptime)
        lastTick = 0
        aheadRow = -1
        world.reset()
        world.clip(running ? .run : .idle)
        publish()
        world.sync(run, calm: calm)
    }

    /// Заезд записан или экран ушёл: время больше не идёт.
    func stop(pose: RunnerWorld.Pose) {
        running = false
        world.clip(pose)
    }

    func swipe(_ m: RunnerMove) {
        guard running, !run.isOver else { return }
        let wasJumping = run.jumping
        run.swipe(m)
        if m == .jump, !wasJumping, run.jumping {
            world.jump()
            Feel.soft()
        } else if m == .left || m == .right {
            Feel.select()
        }
        publish()
    }

    /// Шаг к моменту now. render — с кадра RealityKit; запасной цикл (render == false) шагает, только если кадров нет.
    func frame(now: TimeInterval, render: Bool) {
        guard running else { return }
        if !render, now - lastTick < 0.03 { return }
        let dt = clock.tick(now: now, running: live)
        lastTick = now
        guard dt > 0, !run.isOver else { return }
        let events = run.advance(by: dt)
        for e in events {
            if case .hit = e { world.hit() }
        }
        world.sync(run, calm: calm)
        publish()
        if !events.isEmpty { feel(events, now: now) }
    }

    /// Отклик на события заезда: косточка — тихий «буп», удар — сердечко, новое место — мягкое «ок».
    private func feel(_ events: [RunnerEvent], now: TimeInterval) {
        for e in events {
            switch e {
            case .coin:
                if now - lastChime > 0.15 {
                    lastChime = now
                    Feel.tap(.boop)
                }
            case .hit:
                Feel.nudge(.heartLost)
            case .biome:
                Feel.soft(.ok)
            case .finish:
                break
            }
        }
    }

    private func publish() {
        if metres != run.metres { metres = run.metres }
        if lives != run.lives { lives = run.lives }
        if picked != run.picked { picked = run.picked }
        if biome != run.biome { biome = run.biome }
        if lane != run.lane { lane = run.lane }
        if over != run.isOver { over = run.isOver }
        let row = run.nextRow?.index ?? -2
        if row != aheadRow {
            aheadRow = row
            ahead = Runner.ahead(run)
        }
    }
}

// MARK: - Система кадров

/// Висит на корне мира: система шагает заезд на каждом кадре рендера.
struct RunnerTickComponent: Component {
    weak var session: RunnerSession?
}

struct RunnerTickSystem: System {
    private let query = EntityQuery(where: .has(RunnerTickComponent.self))

    init(scene: RealityKit.Scene) {}

    @MainActor func update(context: SceneUpdateContext) {
        let now = ProcessInfo.processInfo.systemUptime
        for e in context.entities(matching: query, updatingSystemWhen: .rendering) {
            e.components[RunnerTickComponent.self]?.session?.frame(now: now, render: true)
        }
    }

    @MainActor private static var registered = false

    @MainActor static func registerOnce() {
        guard !registered else { return }
        registered = true
        RunnerTickComponent.registerComponent()
        RunnerTickSystem.registerSystem()
    }
}

// MARK: - Пул

/// Готовые копии одного вида: take() выдаёт следующую (дорастает при нехватке), end() гасит невыданные.
@MainActor
final class RunnerPool {
    private let proto: Entity
    private let parent: Entity
    private var items: [Entity] = []
    private var used = 0

    init(_ proto: Entity, parent: Entity, warm: Int) {
        self.proto = proto
        self.parent = parent
        for _ in 0..<warm { add() }
        for e in items { e.isEnabled = false }
    }

    private func add() {
        let e = proto.clone(recursive: true)
        parent.addChild(e)
        items.append(e)
    }

    func begin() { used = 0 }

    func take() -> Entity {
        if used == items.count { add() }
        let e = items[used]
        used += 1
        if !e.isEnabled { e.isEnabled = true }
        return e
    }

    func end() {
        for i in used..<items.count where items[i].isEnabled { items[i].isEnabled = false }
    }

    var count: Int { items.count }
}

// MARK: - Мир

@MainActor
final class RunnerWorld {
    /// Сцены на метр трассы и ширина полосы (в единицах сцены; пёс ростом PetModel.height = 0,42).
    static let scale: Float = 0.6
    static let laneW: Float = 0.55
    /// Сколько метров вперёд рисуем (трасса знает больше — Runner.lookahead) и сколько проявляется.
    static let drawAhead = 40.0
    static let popIn = 6.0
    static let tileLen = 8.0
    static let propStep = 5.0
    /// Высота прыжка в сцене при height = 1.
    static let jumpY: Float = 0.5

    enum Pose: Equatable { case idle, run, sit }

    let root = Entity()
    private let cam = PerspectiveCamera()
    private var camX: Float = .nan
    private let dogRoot = Entity()
    private let shadow: ModelEntity
    private var body: Entity?
    private var pose: Pose = .idle
    private var bodyPose: Pose?
    private var loading = false

    private var tiles: [(road: ModelEntity, left: ModelEntity, right: ModelEntity, key: Int)] = []
    private var obstacles: [RunnerObstacle: RunnerPool] = [:]
    private var bones: RunnerPool!
    private var props: [String: RunnerPool] = [:]
    private var tileMats: [Int: [PhysicallyBasedMaterial]] = [:]

    init() {
        // Тень-пятно под псом: дешевле настоящих теней и не мигает.
        shadow = ModelEntity(mesh: .generateCylinder(height: 0.004, radius: 0.2), materials: [UnlitMaterial(color: .black)])
        shadow.components.set(OpacityComponent(opacity: 0.18))
        shadow.position = SIMD3(0, 0.003, 0)
        shadow.scale = SIMD3(1, 1, 1.5)
        root.name = "runner.world"
        root.addChild(PetRoom.lights())
        cam.name = "runner.camera"
        cam.camera.fieldOfViewInDegrees = 52
        root.addChild(cam)
        aim(0)
        root.addChild(shadow)
        dogRoot.name = "runner.dog"
        dogRoot.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
        root.addChild(dogRoot)
        buildGround()
        buildPools()
        root.components.set(RunnerTickComponent())
    }

    func bind(_ session: RunnerSession) {
        root.components.set(RunnerTickComponent(session: session))
    }

    func reset() {
        for t in tiles.indices { tiles[t].key = -1 }
    }

    // MARK: пёс

    /// Модель породы из сейва; грузится один раз на экран.
    func loadDog() {
        guard body == nil, !loading else { return }
        loading = true
        Task { @MainActor [weak self] in
            let b = await YardDogLive.model()
            guard let self else { return }
            b.components.set(DynamicLightShadowComponent(castsShadow: false))
            self.dogRoot.addChild(b)
            self.body = b
            self.loading = false
            self.bodyPose = nil
            self.clip(self.pose)
        }
    }

    func clip(_ p: Pose) {
        pose = p
        guard let body, bodyPose != p else { return }
        bodyPose = p
        let clips: YardDogClips
        switch p {
        case .idle: clips = YardDogClips(once: [], loop: ["idle", "idle_2"])
        case .run: clips = YardDogClips(once: [], loop: ["gallop"])
        case .sit: clips = YardDogClips(once: ["sit_in"], loop: ["sit"])
        }
        YardDogLive.play(clips, on: body, initial: p != .sit)
    }

    func jump() {
        guard let body, pose == .run else { return }
        YardDogLive.play(YardDogClips(once: ["gallop_jump"], loop: ["gallop"]), on: body, initial: false)
    }

    func hit() {
        guard let body, pose == .run else { return }
        YardDogLive.play(YardDogClips(once: ["hit_left"], loop: ["gallop"]), on: body, initial: false)
    }

    // MARK: кадр

    func sync(_ run: RunnerRun, calm: Bool) {
        let d = run.distance
        let s = Self.scale
        let t = Float(run.t)
        // Пёс: полоса, прыжок, подкат, мигание после удара.
        let x = Float(run.x - 1) * Self.laneW
        let y = Float(run.height) * Self.jumpY
        dogRoot.position = SIMD3(x, y, 0)
        dogRoot.scale = run.sliding ? SIMD3(1.12, 0.58, 1.12) : SIMD3(repeating: 1)
        let blink: Float = run.invulnerable ? (calm ? 0.5 : (Int(run.t * 10) % 2 == 0 ? 0.3 : 1)) : 1
        if dogRoot.components[OpacityComponent.self]?.opacity != blink {
            dogRoot.components.set(OpacityComponent(opacity: blink))
        }
        shadow.position.x = x
        aim(calm ? 0 : x)
        let lift = 1 - min(0.6, y * 1.2)
        shadow.scale = SIMD3(lift, 1, 1.5 * lift)

        // Земля: плитки по tileLen метров, цвет по месту на трассе (двор → район → парк), через одну — чуть темнее.
        let base = (floor((d - 4) / Self.tileLen)) * Self.tileLen
        for i in tiles.indices {
            let start = base + Double(i) * Self.tileLen
            let z = -Float(start + Self.tileLen / 2 - d) * s
            tiles[i].road.position.z = z
            tiles[i].left.position.z = z
            tiles[i].right.position.z = z
            let biome = Runner.biome(at: start + Self.tileLen / 2)
            let parity = Int((start / Self.tileLen).rounded()) & 1
            let key = biome.rawValue * 2 + parity
            if tiles[i].key != key, let m = tileMats[biome.rawValue] {
                tiles[i].key = key
                tiles[i].road.model?.materials = [m[parity]]
                tiles[i].left.model?.materials = [m[2 + parity]]
                tiles[i].right.model?.materials = [m[2 + parity]]
            }
        }

        // Препятствия.
        for p in obstacles.values { p.begin() }
        for row in run.rows(ahead: Self.drawAhead) {
            let dz = row.z - d
            let k = Self.pop(dz)
            guard k > 0 else { continue }
            let z = -Float(dz) * s
            for l in 0..<Runner.lanes {
                guard let o = row.lanes[l], !run.isKnocked(row, lane: l), let pool = obstacles[o] else { continue }
                let e = pool.take()
                var yy: Float = 0
                if o == .pigeons, !calm { yy = sin(t * 9 + Float(row.index * 3 + l)) * 0.025 }
                e.position = SIMD3(Float(l - 1) * Self.laneW, yy, z)
                e.scale = SIMD3(repeating: k)
            }
        }
        for p in obstacles.values { p.end() }

        // Косточки-монеты.
        bones.begin()
        let spin = simd_quatf(angle: calm ? 0.5 : t * 4, axis: SIMD3(0, 1, 0))
        for c in run.coins(ahead: Self.drawAhead) {
            let dz = c.z - d
            let k = Self.pop(dz)
            guard k > 0 else { continue }
            let e = bones.take()
            e.position = SIMD3(Float(c.lane - 1) * Self.laneW, 0.24, -Float(dz) * s)
            e.orientation = spin
            e.scale = SIMD3(repeating: k)
        }
        bones.end()

        // Обочина: через каждые propStep метров по вещи с двух сторон — заборы и кусты во дворе, дома в районе, деревья в парке.
        for p in props.values { p.begin() }
        let lo = Int(floor((d - 4) / Self.propStep)), hi = Int(ceil((d + Self.drawAhead) / Self.propStep))
        for i in lo...hi {
            let zm = Double(i) * Self.propStep + Self.propStep / 2
            let dz = zm - d
            let k = Self.pop(dz)
            guard k > 0 else { continue }
            let biome = Runner.biome(at: zm)
            for side in [-1, 1] {
                let h = Self.hash(i &* 2 &+ (side > 0 ? 1 : 0))
                guard let kind = Self.prop(biome, h), let pool = props[kind] else { continue }
                let e = pool.take()
                let jitter = Float(h % 7) * 0.03
                let off: Float = kind.hasPrefix("house") ? 0.85 : 0.5
                e.position = SIMD3(Float(side) * (1.5 * Self.laneW + off + jitter), 0, -Float(dz) * s)
                let size = 0.85 + Float(h % 5) * 0.075
                e.scale = SIMD3(repeating: k * size)
            }
        }
        for p in props.values { p.end() }
    }

    /// Камера чуть сзади-сверху, смотрит вперёд по трассе; без Reduce Motion идёт за псом на треть полосы.
    private func aim(_ dogX: Float) {
        let cx = dogX * 0.35
        guard cx != camX else { return }
        camX = cx
        cam.look(at: SIMD3(cx, 0.22, -3), from: SIMD3(cx, 1.15, 1.75), relativeTo: nil)
    }

    /// Проявление на дальнем краю: 0 за drawAhead, 1 ближе на popIn метров.
    static func pop(_ dz: Double) -> Float {
        Float(min(1, max(0, (drawAhead - dz) / popIn)))
    }

    static func hash(_ i: Int) -> Int {
        var x = UInt64(bitPattern: Int64(i)) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        return Int((x ^ (x >> 31)) % 1_000_003)
    }

    /// Что стоит у дороги: по месту и случаю; nil — пусто (чтобы не стеной).
    static func prop(_ b: RunnerBiome, _ h: Int) -> String? {
        switch b {
        case .yard: return ["fence", "fence", "bush", nil][h % 4]
        case .district: return ["houseA", "houseB", "houseC", "lamp"][h % 4]
        case .park: return ["tree", "tree", "bush", "lamp", nil][h % 5]
        }
    }

    // MARK: сборка

    private static let palette: [RunnerBiome: (road: UInt32, side: UInt32)] = [
        .yard: (0xd8c3a0, 0x9ccc78),
        .district: (0x8f90a3, 0xcfc9db),
        .park: (0xe3d2ac, 0x7fc06a),
    ]

    private func buildGround() {
        for b in RunnerBiome.allCases {
            let p = Self.palette[b] ?? (0xcccccc, 0x99cc88)
            tileMats[b.rawValue] = [PetRoom.matteMaterial(p.road), PetRoom.matteMaterial(p.road, shade: 0.95),
                                    PetRoom.matteMaterial(p.side), PetRoom.matteMaterial(p.side, shade: 0.94)]
        }
        let depth = Float(Self.tileLen) * Self.scale
        let roadW = 3 * Self.laneW + 0.2
        let sideW: Float = 4
        let roadMesh = MeshResource.generateBox(width: roadW, height: 0.02, depth: depth)
        let sideMesh = MeshResource.generateBox(width: sideW, height: 0.02, depth: depth)
        let count = Int(ceil((Self.drawAhead + 4) / Self.tileLen)) + 1
        let m0 = tileMats[0]!
        for _ in 0..<count {
            let road = ModelEntity(mesh: roadMesh, materials: [m0[0]])
            road.position.y = -0.01
            let left = ModelEntity(mesh: sideMesh, materials: [m0[2]])
            left.position = SIMD3(-(roadW + sideW) / 2, -0.005, 0)
            let right = ModelEntity(mesh: sideMesh, materials: [m0[2]])
            right.position = SIMD3((roadW + sideW) / 2, -0.005, 0)
            for e in [road, left, right] {
                PetRoom.noShadow(e)
                root.addChild(e)
            }
            tiles.append((road, left, right, -1))
        }
        // Разметка полос — две светлые линии, стоят на месте (движение видно по плиткам и обочине).
        let lineMesh = MeshResource.generateBox(width: 0.025, height: 0.004, depth: Float(Self.drawAhead) * Self.scale)
        let lineMat = PetRoom.matteMaterial(0xf6f1e6)
        for side: Float in [-0.5, 0.5] {
            let line = ModelEntity(mesh: lineMesh, materials: [lineMat])
            line.components.set(OpacityComponent(opacity: 0.55))
            line.position = SIMD3(side * Self.laneW, 0.003, -Float(Self.drawAhead) * Self.scale / 2 + 1)
            PetRoom.noShadow(line)
            root.addChild(line)
        }
    }

    private func buildPools() {
        let holder = Entity()
        holder.name = "runner.pools"
        root.addChild(holder)
        for o in RunnerObstacle.allCases {
            obstacles[o] = RunnerPool(Self.obstacle(o), parent: holder, warm: 6)
        }
        bones = RunnerPool(Self.bone(), parent: holder, warm: 16)
        for kind in ["fence", "bush", "houseA", "houseB", "houseC", "lamp", "tree"] {
            props[kind] = RunnerPool(Self.sideProp(kind), parent: holder, warm: 4)
        }
    }

    private static func box(_ w: Float, _ h: Float, _ d: Float, _ hex: UInt32, at p: SIMD3<Float>, corner: Float = 0) -> ModelEntity {
        let e = ModelEntity(mesh: .generateBox(width: w, height: h, depth: d, cornerRadius: corner), materials: [PetRoom.matteMaterial(hex)])
        e.position = p
        PetRoom.noShadow(e)
        return e
    }

    private static func ball(_ r: Float, _ hex: UInt32, at p: SIMD3<Float>) -> ModelEntity {
        let e = ModelEntity(mesh: .generateSphere(radius: r), materials: [PetRoom.matteMaterial(hex)])
        e.position = p
        PetRoom.noShadow(e)
        return e
    }

    /// Препятствия — вещи из мира пса, по габаритам Runner (длина вдоль трассы — length метров).
    static func obstacle(_ o: RunnerObstacle) -> Entity {
        let e = Entity()
        e.name = "runner.\(o.rawValue)"
        let depth = Float(o.length) * scale
        switch o {
        case .puddle:
            let water = ModelEntity(mesh: .generateCylinder(height: 0.012, radius: 0.5), materials: [PetRoom.matteMaterial(0x5fb0ee)])
            water.scale = SIMD3(0.46, 1, depth)
            water.position.y = 0.006
            PetRoom.noShadow(water)
            e.addChild(water)
            e.addChild(ball(0.05, 0xa9d7f7, at: SIMD3(0.08, 0.0, -0.1)))
        case .flowerbed:
            e.addChild(box(0.44, 0.12, depth * 0.9, 0x8b5e3c, at: SIMD3(0, 0.06, 0), corner: 0.02))
            e.addChild(box(0.4, 0.02, depth * 0.84, 0x5e4029, at: SIMD3(0, 0.125, 0)))
            let colors: [UInt32] = [0xff7aa8, 0xffd25a, 0xfaf6ff, 0xb18cff]
            for (i, c) in colors.enumerated() {
                let fx = Float(i % 2 == 0 ? -0.1 : 0.1), fz = Float(i < 2 ? -0.08 : 0.08)
                e.addChild(ball(0.05, c, at: SIMD3(fx, 0.18, fz)))
            }
        case .crate:
            e.addChild(box(0.44, 0.4, 0.44, 0xc99258, at: SIMD3(0, 0.2, 0), corner: 0.015))
            e.addChild(box(0.46, 0.04, 0.46, 0xa8743f, at: SIMD3(0, 0.2, 0)))
            let top = box(0.32, 0.28, 0.32, 0xb98048, at: SIMD3(0.02, 0.54, 0), corner: 0.015)
            top.orientation = simd_quatf(angle: 0.3, axis: SIMD3(0, 1, 0))
            e.addChild(top)
        case .bench:
            // Сиденье выше пса в подкате (0,42 × 0,58): проползаем под ним.
            e.addChild(box(0.52, 0.05, 0.2, 0x9a6b45, at: SIMD3(0, 0.34, 0), corner: 0.012))
            e.addChild(box(0.52, 0.12, 0.03, 0x9a6b45, at: SIMD3(0, 0.46, -0.1), corner: 0.01))
            for lx: Float in [-0.23, 0.23] {
                for lz: Float in [-0.08, 0.08] {
                    e.addChild(box(0.035, 0.34, 0.035, 0x4b4f5c, at: SIMD3(lx, 0.17, lz)))
                }
            }
        case .pigeons:
            for (i, px) in [Float(-0.14), 0, 0.14].enumerated() {
                let y: Float = 0.36 + Float(i % 2) * 0.05
                e.addChild(ball(0.06, 0x9a9fb0, at: SIMD3(px, y, 0)))
                e.addChild(ball(0.035, 0x6f7385, at: SIMD3(px, y + 0.06, 0.04)))
                e.addChild(box(0.16, 0.012, 0.05, 0xb6bac8, at: SIMD3(px, y + 0.01, -0.01)))
            }
        }
        return e
    }

    /// Косточка из фигур, золотая: перемычка и по два шарика на концах.
    static func bone() -> Entity {
        let e = Entity()
        e.name = "runner.bone"
        let gold: UInt32 = 0xffc94d
        e.addChild(box(0.15, 0.035, 0.035, gold, at: .zero, corner: 0.017))
        for x: Float in [-0.075, 0.075] {
            for y: Float in [-0.022, 0.022] {
                e.addChild(ball(0.028, gold, at: SIMD3(x, y, 0)))
            }
        }
        return e
    }

    static func sideProp(_ kind: String) -> Entity {
        let e = Entity()
        e.name = "runner.prop.\(kind)"
        switch kind {
        case "fence":
            e.addChild(box(0.04, 0.03, 1.4, 0xf2e6d2, at: SIMD3(0, 0.3, 0)))
            e.addChild(box(0.04, 0.03, 1.4, 0xf2e6d2, at: SIMD3(0, 0.16, 0)))
            for z: Float in [-0.6, -0.2, 0.2, 0.6] {
                e.addChild(box(0.05, 0.4, 0.05, 0xe8d8bf, at: SIMD3(0, 0.2, z)))
            }
        case "bush":
            e.addChild(ball(0.22, 0x6aae55, at: SIMD3(0, 0.18, 0)))
            e.addChild(ball(0.16, 0x7cc063, at: SIMD3(0.12, 0.14, 0.12)))
        case "houseA", "houseB", "houseC":
            let (wall, roof, h): (UInt32, UInt32, Float) = kind == "houseA" ? (0xf3c9a8, 0xb85c4a, 1.3)
                : kind == "houseB" ? (0xc9d4f2, 0x5b6fa8, 1.8) : (0xf2e2a6, 0x8a7a4a, 1.0)
            e.addChild(box(1.0, h, 1.2, wall, at: SIMD3(0, h / 2, 0)))
            e.addChild(box(1.06, 0.08, 1.26, roof, at: SIMD3(0, h + 0.04, 0)))
            for wy in stride(from: Float(0.35), to: h - 0.2, by: 0.42) {
                for wz: Float in [-0.3, 0.3] {
                    e.addChild(box(0.02, 0.2, 0.22, 0x8fb3d9, at: SIMD3(0, wy, wz)))
                }
            }
        case "lamp":
            e.addChild(box(0.04, 0.9, 0.04, 0x4b4f5c, at: SIMD3(0, 0.45, 0)))
            e.addChild(ball(0.07, 0xfff1c2, at: SIMD3(0, 0.92, 0)))
        case "tree":
            e.addChild(box(0.08, 0.5, 0.08, 0x8a5a3a, at: SIMD3(0, 0.25, 0)))
            e.addChild(ball(0.3, 0x5fa854, at: SIMD3(0, 0.68, 0)))
            e.addChild(ball(0.2, 0x74bd62, at: SIMD3(0.1, 0.86, 0.06)))
        default:
            break
        }
        return e
    }

    /// Небо за сценой — SwiftUI-градиент по месту (RealityView прозрачный).
    static func sky(_ b: RunnerBiome) -> [Color] {
        switch b {
        case .yard: return [Color(hex: 0x9fd0ff), Color(hex: 0xe6f2ff)]
        case .district: return [Color(hex: 0xb9b6e6), Color(hex: 0xebe7f7)]
        case .park: return [Color(hex: 0xa6e3c4), Color(hex: 0xeaf7ee)]
        }
    }
}
