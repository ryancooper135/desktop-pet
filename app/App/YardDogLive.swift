// Волна 35 M: Шиба во дворе и тиканье монет. План (куда идёт, что делает) — YardDogPlan в Shared, тут только сцена.
// Пёс — своя копия модели породы (шаблон грузится один раз и клонируется): глобальное состояние рига главной
// комнаты (ClipTable.shared, ClipPlayer, PetModel.boneAlias, ChoreoPath.body) не трогаем — двор открыт поверх неё.
// Клипы — из таблицы породы (ClipTable.of) своим маленьким проигрывателем. Поза каждый кадр из Clock.now(): пересборка сцены
// (поднос копилки, покупка) не сбивает пса с маршрута. Свой персонаж во дворе не показываем — только Шиба.

import RealityKit
import SwiftUI
@preconcurrency import PetCore

/// Всё, что двору нужно на кадр: пёс (если есть), где станции, кого слышно. Висит на корне сцены YardLive.
struct YardLiveComponent: Component {
    var mode: YardDogMode
    var spots: [YardDogSpot]
    var rest: SIMD3<Float>
    var dogScale: Float
    var night: Bool
    var brushed: Bool
    /// Reduce Motion: пёс не ходит и не копает, отдыхает на месте.
    var calm: Bool
    /// PET_YARD_DOG (UI-тест): пёс всё время у этой станции.
    var forced: String?
    /// Доход станций: тикают самые доходные (YardTick.audible).
    var rates: [YardTickRate]
    var dog: Entity?
    var body: Entity?
    var dirt: Entity?
    var clipKey = ""
    /// Номер посадки пса (YardDogLive.attached): по нему экран знает, что пса уже видно в этой сцене.
    var seq = 0
    var yaw: Float = 0
    /// Станция, у которой пёс сейчас что-то делает (её тик слышно первым).
    var dogAt: String?
    /// Номер последнего тика по станциям: вырос — щёлкнуть.
    var ticks: [String: Int] = [:]
}

struct YardTickRate: Hashable, Sendable {
    let id: String
    let rate: Double
}

struct YardLiveSystem: System {
    private let query = EntityQuery(where: .has(YardLiveComponent.self))

    init(scene: RealityKit.Scene) {}

    @MainActor func update(context: SceneUpdateContext) {
        let dt = Float(min(max(context.deltaTime, 0), 0.1))
        let now = Clock.now()
        for e in context.entities(matching: query, updatingSystemWhen: .rendering) {
            guard var c = e.components[YardLiveComponent.self] else { continue }
            YardDogLive.step(&c, now: now, dt: dt)
            YardDogLive.tick(&c, clock: YardArtSystem.clock)
            if c.dog?.isEnabled == true { YardDogLive.framed(c.seq) }
            e.components.set(c)
        }
    }

    @MainActor private static var registered = false

    @MainActor static func registerOnce() {
        guard !registered else { return }
        registered = true
        YardLiveComponent.registerComponent()
        YardLiveSystem.registerSystem()
    }
}

@MainActor
enum YardDogLive {
    static let dogName = "yard.dog"

    /// Где пёс отдыхает и какого он размера: на подоконнике (ярус 0) — маленький у горшка, во дворе — у дорожки.
    static func rest(tier: Int) -> (at: SIMD3<Float>, scale: Float) {
        tier <= 0 ? (SIMD3(-0.18, 0.5, -1.56), 0.45) : (SIMD3(0, 0, -0.45), 0.75)
    }

    /// Станции сцены для плана пса.
    static func spots(_ s: [YardLive.Spot]) -> [YardDogSpot] {
        s.map { YardDogSpot(id: $0.id, at: $0.at, scale: $0.scale) }
    }

    // MARK: модель

    private static var template: Entity?
    /// Порода шаблона (волна 58): сменили породу в настройках — грузим заново.
    private static var templateBreed: PetBreed?
    private static var loading: Task<Entity, Never>?
    /// Сколько раз пса сажали в сцену и до какой посадки дошёл кадр (пёс включён и сцена рисуется).
    private(set) static var attached = 0
    private(set) static var shown = 0

    static func framed(_ seq: Int) {
        if seq > shown { shown = seq }
    }

    /// Для UI-теста и отладки: off — пса не сажали, load — модель грузится, wait — посадили, кадра ещё не было,
    /// on — пёс в сцене и сцена живёт.
    static var state: String {
        if attached == 0 { return loading != nil ? "load" : "off" }
        return shown >= attached ? "on" : (loading != nil ? "load" : "wait")
    }

    /// Шаблон пса: модель породы (PetModel.breed: shiba.usdz или husky.usdz, иначе заглушка), ростом PetModel.height,
    /// низ на полу, смотрит на +z. Грузится один раз на породу.
    static func model() async -> Entity {
        let breed = PetModel.breed
        if let t = template, templateBreed == breed { return t.clone(recursive: true) }
        if templateBreed != breed {
            // Клипы кэша вырезаны из таймлайна прошлой породы — у новой свои границы.
            template = nil
            loading = nil
            cache.removeAll()
        }
        let task = loading ?? Task { @MainActor in
            var model: Entity?
            if Bundle.main.url(forResource: breed.resource, withExtension: "usdz") != nil {
                model = try? await Entity(named: breed.resource, in: Bundle.main)
            }
            let body = model ?? StubDog.make()
            // Глаза держатся головы (как в комнате). Свой персонаж в комнате — кости под его именами, тогда не трогаем.
            if model != nil, PetModel.boneAlias.isEmpty { PetRig.pinEyes(body) }
            // Живые глаза (волна 50) — как в комнате.
            if model != nil { PetRig.styleEyes(body, iris: breed.iris) }
            let b = body.visualBounds(relativeTo: nil)
            if model != nil, b.extents.y > 0 {
                let k = PetModel.height / b.extents.y
                body.scale = SIMD3<Float>(repeating: k)
                body.position = SIMD3<Float>(-b.center.x * k, -b.min.y * k, -b.center.z * k)
            }
            return body
        }
        loading = task
        templateBreed = breed
        let t = await task.value
        if templateBreed == breed {
            template = t
            loading = nil
        }
        return t.clone(recursive: true)
    }

    /// Посадить пса в сцену: корень (позиция, поворот, масштаб) → модель, плюс комочки земли для «копает».
    static func attach(to world: Entity, body: Entity) {
        guard var c = world.components[YardLiveComponent.self] else { return }
        let dog = Entity()
        dog.name = dogName
        dog.scale = SIMD3<Float>(repeating: c.dogScale)
        dog.addChild(body)
        let dirt = Entity()
        dirt.name = "yard.dog.dirt"
        let mat = PetRoom.matteMaterial(0x7a5636)
        for _ in 0..<5 {
            let bit = ModelEntity(mesh: .generateBox(size: 0.026), materials: [mat])
            PetRoom.noShadow(bit)
            dirt.addChild(bit)
        }
        // Комочки земли — часть двора, а не пса: ночью темнеют вместе с ним (волна 38 B).
        if c.night { RoomLighting.apply(YardLight.night, to: dirt) }
        dirt.isEnabled = false
        dog.addChild(dirt)
        dog.isEnabled = false
        world.addChild(dog)
        c.dog = dog
        c.body = body
        c.dirt = dirt
        c.clipKey = ""
        attached += 1
        c.seq = attached
        // Сразу на место и в позу: пёс виден с первого же кадра, не дожидаясь системы.
        step(&c, now: Clock.now(), dt: 0)
        world.components.set(c)
    }

    // MARK: кадр

    /// Поза пса на этот кадр: место, поворот (плавно), клипы при смене дела, земля при копании.
    static func step(_ c: inout YardLiveComponent, now: Double, dt: Float) {
        guard let dog = c.dog else { return }
        let pose = YardDogPlan.pose(now: now, mode: c.mode, spots: c.calm ? [] : c.spots, rest: c.rest,
                                    dogScale: c.dogScale, night: c.night, forced: c.calm ? nil : c.forced)
        guard let pose else {
            if dog.isEnabled { dog.isEnabled = false }
            c.dogAt = nil
            return
        }
        let first = c.clipKey.isEmpty
        if !dog.isEnabled { dog.isEnabled = true }
        dog.position = pose.at
        if first {
            c.yaw = pose.yaw
        } else {
            let d = atan2(sin(pose.yaw - c.yaw), cos(pose.yaw - c.yaw))
            c.yaw += d * min(1, dt * 9)
        }
        dog.orientation = simd_quatf(angle: c.yaw, axis: SIMD3<Float>(0, 1, 0))
        if pose.clipKey != c.clipKey, let body = c.body {
            // Первый кадр сцены — сразу цикл: пёс уже сидит или спит, вставать-ложиться заново не надо.
            play(pose.clips, on: body, initial: first)
            c.clipKey = pose.clipKey
        }
        c.dogAt = pose.phase == .act ? pose.station : nil
        let digging = pose.phase == .act && (pose.act?.dirt ?? false)
        if let dirt = c.dirt {
            if dirt.isEnabled != digging { dirt.isEnabled = digging }
            if digging { fling(dirt, now: now) }
        }
    }

    /// Комочки земли из-под передних лап: дугой вверх и в стороны, по кругу со сдвигом.
    private static func fling(_ dirt: Entity, now: Double) {
        for (k, bit) in dirt.children.enumerated() {
            let u = Float((now / 0.8 + Double(k) / 5).truncatingRemainder(dividingBy: 1))
            let side: Float = k % 2 == 0 ? 1 : -1
            let x = side * (0.05 + 0.16 * u) + Float(k - 2) * 0.012
            let y = 0.02 + 0.2 * sin(.pi * u)
            let z = 0.2 - 0.12 * u
            bit.position = SIMD3(x, y, z)
            bit.scale = SIMD3<Float>(repeating: 1 - 0.6 * u)
        }
    }

    /// Тик монеты: падает сухарик, косточка, пирожок — щёлкаем у слышных станций (не больше двух).
    static func tick(_ c: inout YardLiveComponent, clock: Double) {
        guard !c.rates.isEmpty else { return }
        let loud = YardTick.audible(c.rates.map { (id: $0.id, rate: $0.rate) }, dogAt: c.dogAt)
        let all = YardConfig.shared.stations
        for r in c.rates {
            guard let n = YardTick.count(r.id, clock: clock, night: c.night, brushed: c.brushed) else { continue }
            if let was = c.ticks[r.id], n > was, loud.contains(r.id) {
                SoundKit.shared.play(.yardTick(all.firstIndex { $0.id == r.id } ?? 0))
            }
            c.ticks[r.id] = n
        }
    }

    // MARK: клипы

    private static var cache: [String: AnimationResource] = [:]
    private static let loopCount = 100_000

    /// Кусок таймлайна «Clips» по таблице Шибы; нет клипа — nil, шаг пропускается.
    private static func clip(_ name: String, source: AnimationResource, table: ClipTable) -> AnimationResource? {
        if let r = cache[name] { return r }
        guard let c = table.clips[name], c.end > c.start else { return nil }
        let view = AnimationView(source: source.definition, name: "yard.\(name)", fillMode: [],
                                 trimStart: c.start, trimEnd: c.end)
        guard let r = try? AnimationResource.generate(with: view) else { return nil }
        cache[name] = r
        return r
    }

    /// Одноразовые клипы, потом цикл из нескольких (sniff → pant → …) по кругу.
    static func play(_ clips: YardDogClips, on body: Entity, initial: Bool) {
        guard let table = ClipTable.of(templateBreed ?? PetModel.breed), let source = body.availableAnimations.first else { return }
        var parts: [AnimationResource] = []
        if !initial {
            parts += clips.once.compactMap { clip($0, source: source, table: table) }
        }
        let loop = clips.loop.compactMap { clip($0, source: source, table: table) }
        if loop.count == 1 {
            parts.append(loop[0].repeat(count: loopCount))
        } else if loop.count > 1, let seq = try? AnimationResource.sequence(with: loop) {
            parts.append(seq.repeat(count: loopCount))
        }
        guard !parts.isEmpty else { return }
        let res: AnimationResource
        if parts.count == 1 {
            res = parts[0]
        } else if let seq = try? AnimationResource.sequence(with: parts) {
            res = seq
        } else {
            res = parts[parts.count - 1]
        }
        body.playAnimation(res, transitionDuration: initial ? 0 : 0.3, startsPaused: false)
    }

    // MARK: для экрана

    /// Что делает пёс — для VoiceOver и UI-теста (тот же план, что у сцены).
    nonisolated static func pose(mode: YardDogMode, spots: [YardLive.Spot], tier: Int, night: Bool, calm: Bool,
                                 now: Double) -> YardDogPose? {
        let r: (at: SIMD3<Float>, scale: Float) = tier <= 0 ? (SIMD3(-0.18, 0.5, -1.56), 0.45) : (SIMD3(0, 0, -0.45), 0.75)
        return YardDogPlan.pose(now: now, mode: mode, spots: calm ? [] : spots.map { YardDogSpot(id: $0.id, at: $0.at, scale: $0.scale) },
                                rest: r.at, dogScale: r.scale, night: night, forced: calm ? nil : forced)
    }

    /// PET_YARD_DOG=<станция> — только в UI-тесте: пёс всё время у неё (снимок ui-35-yard-dog).
    nonisolated static var forced: String? {
        Env.isUITest ? Env.value("PET_YARD_DOG") : nil
    }
}
