// Волна 35 M: Шиба во дворе — сам подходит к станции и делает её дело (§2 «пёс у станции»).
// Чистая часть: дома ли пёс (прогулка/поход — нет, спит — спит), к какой станции идёт и когда,
// где стоит в эту секунду, какой клип играть. Плюс тиканье монет: какие станции слышно и когда «тик».
// Всё детерминировано от часов (StableHash по номеру окна): тот же момент — та же поза, без таймеров.

import Foundation

/// Пёс во дворе: нет его (гуляет, в походе, умер), спит или бодрствует.
enum YardDogMode: String, Hashable, Sendable {
    case absent, asleep, awake

    static func of(pose: Pose, alive: Bool) -> YardDogMode {
        guard alive else { return .absent }
        switch pose {
        case .away, .dead: return .absent
        case .sleep, .nap: return .asleep
        default: return .awake
        }
    }
}

/// Что пёс делает у станции.
enum YardDogAct: String, Hashable, Sendable, CaseIterable {
    /// Сушилка: тянется носом к корзинке, облизывается.
    case reach
    /// Грядка: роет рядом, летит земля.
    case dig
    /// Котелок: сидит, смотрит на пар.
    case watch
    /// Прялка: ловит лапой нитку.
    case paw
    /// Печь: нюхает воздух, хвост ходуном.
    case sniff
    /// Фотобудка: позирует — садится и наклоняет голову.
    case pose
    /// Конвейер: бежит вдоль ленты.
    case run
    /// Мельница: воет ночью.
    case howl

    static func of(station id: String) -> YardDogAct? {
        switch id {
        case "dryer": return .reach
        case "bones": return .dig
        case "porridge": return .watch
        case "spinner": return .paw
        case "pies": return .sniff
        case "photo": return .pose
        case "sausage": return .run
        case "mill": return .howl
        default: return nil
        }
    }

    /// Клипы Шибы (ClipTable.shiba): разовые по порядку, потом петля по кругу.
    var clips: YardDogClips {
        switch self {
        case .reach: return YardDogClips(once: ["sniff"], loop: ["pant", "sniff", "pant", "ear_flick"])
        case .dig: return YardDogClips(once: ["play_bow"], loop: ["hit_left", "hit_right"])
        case .watch: return YardDogClips(once: ["sit_in"], loop: ["sit"])
        case .paw: return YardDogClips(once: [], loop: ["attack", "look_l", "attack", "look_r"])
        case .sniff: return YardDogClips(once: ["sniff"], loop: ["happy_wag", "sniff"])
        case .pose: return YardDogClips(once: ["head_tilt", "sit_in"], loop: ["sit"])
        case .run: return YardDogClips(once: [], loop: ["gallop"])
        case .howl: return YardDogClips(once: [], loop: ["bark", "idle_2"])
        }
    }

    /// Сидячие дела: уходя, сначала встать (sit_out), стоя на месте exitHold секунд.
    var sits: Bool { self == .watch || self == .pose }

    /// Летит ли земля (грядка) — сцена показывает комочки.
    var dirt: Bool { self == .dig }
}

/// Что играть: разовые клипы, потом петля.
struct YardDogClips: Hashable, Sendable {
    let once: [String]
    let loop: [String]
}

/// Станция на сцене для пса: id, центр и масштаб.
struct YardDogSpot: Hashable, Sendable {
    let id: String
    let at: SIMD3<Float>
    let scale: Float
}

/// Фаза визита.
enum YardDogPhase: String, Hashable, Sendable {
    case rest, walkTo, act, walkBack, sleep
}

/// Поза пса в момент времени: где стоит, куда смотрит (yaw: 0 — к камере, +z), что делает.
struct YardDogPose: Hashable, Sendable {
    var at: SIMD3<Float>
    var yaw: Float
    var phase: YardDogPhase
    /// Станция визита (nil — отдыхает или спит).
    var station: String?
    var act: YardDogAct?

    /// Ключ анимации: сменился — играем новые клипы.
    var clipKey: String {
        switch phase {
        case .rest: return "rest"
        case .sleep: return "sleep"
        case .walkTo: return "walk"
        case .act: return "act.\(station ?? "")"
        case .walkBack: return (act?.sits ?? false) ? "back.sit" : "walk"
        }
    }

    /// Клипы для ключа.
    var clips: YardDogClips {
        switch phase {
        case .rest: return YardDogClips(once: [], loop: ["idle", "look_l", "idle_wag", "idle", "look_r"])
        case .sleep: return YardDogClips(once: ["lie_in", "sleep_in"], loop: ["sleep"])
        case .walkTo: return YardDogClips(once: [], loop: ["walk"])
        case .act: return act?.clips ?? YardDogClips(once: [], loop: ["idle"])
        case .walkBack: return (act?.sits ?? false) ? YardDogClips(once: ["sit_out"], loop: ["walk"])
                                                    : YardDogClips(once: [], loop: ["walk"])
        }
    }
}

/// Планировщик визитов: время делится на окна по `slot` секунд; в каждом окне 50/50 — визит к одной станции
/// (подойти, act секунд дела, вернуться) или отдых. Станция — по хешу окна среди поставленных
/// (мельница — только ночью). forced — станция из PET_YARD_DOG для UI-теста: пёс стоит у неё всё время.
enum YardDogPlan {
    static let slot: Double = 40
    static let actTime: Double = 14
    /// Шаг, сцена/с, при масштабе пса 1.
    static let speed: Float = 0.42
    /// Сидячие: встать перед уходом.
    static let exitHold: Double = 1.0

    /// Номер окна и секунда внутри.
    static func window(_ now: Double) -> (n: Int, t: Double) {
        let n = Int((now / slot).rounded(.down))
        return (n, now - Double(n) * slot)
    }

    /// Станции, к которым пёс ходит: с известным делом, мельница — только ночью; порядок — как пришли.
    static func candidates(_ spots: [YardDogSpot], night: Bool) -> [YardDogSpot] {
        spots.filter { s in
            guard let a = YardDogAct.of(station: s.id) else { return false }
            return a != .howl || night
        }
    }

    /// Визит окна n: станция или nil (отдых). 50/50 по хешу, станция — по другому биту хеша.
    static func visit(window n: Int, _ spots: [YardDogSpot], night: Bool) -> YardDogSpot? {
        let list = candidates(spots, night: night)
        guard !list.isEmpty else { return nil }
        let h = StableHash.fnv1a("yard.dog|\(n)")
        guard h % 2 == 0 else { return nil }
        return list[Int((h / 2) % UInt64(list.count))]
    }

    /// Куда встать у станции: сбоку от центра в сторону места отдыха (reach — по размеру станции и пса).
    /// Подоконник (сушилка выше земли, а пёс на земле) — встаёт под ним мордой к окну.
    static func stand(_ s: YardDogSpot, rest: SIMD3<Float>, dogScale: Float) -> SIMD3<Float> {
        if s.at.y > 0.2 && rest.y < 0.2 {
            return SIMD3(s.at.x, 0, s.at.z + 0.3)
        }
        if s.id == "sausage" {
            // Вдоль ленты: перед станцией, ближе к камере.
            return SIMD3(s.at.x, rest.y, s.at.z + 0.3 * s.scale + 0.12 * dogScale)
        }
        var d = SIMD3<Float>(rest.x - s.at.x, 0, rest.z - s.at.z)
        let len = (d.x * d.x + d.z * d.z).squareRoot()
        d = len > 1e-4 ? d / len : SIMD3(0, 0, 1)
        let reach = 0.25 * s.scale + 0.2 * dogScale
        return SIMD3(s.at.x + d.x * reach, rest.y, s.at.z + d.z * reach)
    }

    /// Поворот к цели (0 — к камере, +z).
    static func yaw(from a: SIMD3<Float>, to b: SIMD3<Float>) -> Float {
        let dx = b.x - a.x, dz = b.z - a.z
        guard dx * dx + dz * dz > 1e-8 else { return 0 }
        return atan2(dx, dz)
    }

    /// Поза в момент now. rest — место отдыха (мордой к камере), dogScale — масштаб пса (для шага и отступа).
    static func pose(now: Double, mode: YardDogMode, spots: [YardDogSpot], rest: SIMD3<Float>, dogScale: Float = 1,
                     night: Bool, forced: String? = nil) -> YardDogPose? {
        switch mode {
        case .absent:
            return nil
        case .asleep:
            return YardDogPose(at: rest, yaw: 0, phase: .sleep, station: nil, act: nil)
        case .awake:
            break
        }
        if let id = forced, let s = spots.first(where: { $0.id == id }), let a = YardDogAct.of(station: id) {
            let p = stand(s, rest: rest, dogScale: dogScale)
            return YardDogPose(at: actSpot(a, s, p, t: now, dogScale: dogScale), yaw: actYaw(a, s, p, t: now),
                               phase: .act, station: id, act: a)
        }
        let w = window(now)
        guard let s = visit(window: w.n, spots, night: night), let a = YardDogAct.of(station: s.id) else {
            return YardDogPose(at: rest, yaw: 0, phase: .rest, station: nil, act: nil)
        }
        let p = stand(s, rest: rest, dogScale: dogScale)
        let dist = Double(((p.x - rest.x) * (p.x - rest.x) + (p.z - rest.z) * (p.z - rest.z)).squareRoot())
        let walk = dist / Double(max(0.05, speed * dogScale))
        let hold = a.sits ? exitHold : 0
        // Всё должно влезть в окно: подход, дело, подъём, обратно и хоть немного отдыха.
        let act = max(4, min(actTime, slot - 2 * walk - hold - 4))
        var t = w.t
        if t < walk {
            let k = Float(t / max(walk, 1e-6))
            return YardDogPose(at: rest + (p - rest) * k, yaw: yaw(from: rest, to: p), phase: .walkTo,
                               station: s.id, act: a)
        }
        t -= walk
        if t < act {
            return YardDogPose(at: actSpot(a, s, p, t: t, dogScale: dogScale), yaw: actYaw(a, s, p, t: t),
                               phase: .act, station: s.id, act: a)
        }
        t -= act
        let q = actSpot(a, s, p, t: act, dogScale: dogScale)   // где кончилось дело (пробежка — не в точке p)
        if t < hold {
            return YardDogPose(at: q, yaw: actYaw(a, s, p, t: act), phase: .walkBack, station: s.id, act: a)
        }
        t -= hold
        if t < walk {
            let k = Float(t / max(walk, 1e-6))
            return YardDogPose(at: q + (rest - q) * k, yaw: yaw(from: q, to: rest), phase: .walkBack,
                               station: s.id, act: a)
        }
        return YardDogPose(at: rest, yaw: 0, phase: .rest, station: nil, act: nil)
    }

    /// Пробежка вдоль ленты: качели ±0,22 масштаба станции за runPeriod с, из точки p; остальные дела — на месте.
    static let runPeriod: Double = 4.8

    static func actSpot(_ a: YardDogAct, _ s: YardDogSpot, _ p: SIMD3<Float>, t: Double, dogScale: Float) -> SIMD3<Float> {
        guard a == .run else { return p }
        let x = 0.22 * s.scale * Float(sin(2 * Double.pi * t / runPeriod))
        return SIMD3(p.x + x, p.y, p.z)
    }

    static func actYaw(_ a: YardDogAct, _ s: YardDogSpot, _ p: SIMD3<Float>, t: Double) -> Float {
        if a == .run {
            return cos(2 * Double.pi * t / runPeriod) >= 0 ? .pi / 2 : -.pi / 2
        }
        // Позирует — к камере; остальное — мордой к станции.
        if a == .pose { return 0 }
        return yaw(from: p, to: s.at)
    }
}

/// Тиканье монет: падает сухарик / косточка / пирожок — тихий «тик». Слышно не больше двух станций.
enum YardTick {
    static let audibleMax = 2

    /// Цикл станции (с) и доля цикла, когда добыча ложится в ящик/корзинку (по ключам YardModels).
    static func cycle(_ id: String, night: Bool, brushed: Bool) -> (period: Double, at: Double)? {
        switch id {
        case "dryer": return (6, 0.72)
        case "bones": return (4, 0.62)
        case "porridge": return (6, 0.1)            // пар — раз в два кольца, чтобы не трещал
        case "spinner": return (brushed ? 3 : 6, 0.85)
        case "pies": return (5, 0.64)
        case "photo": return (4, 0.4)
        case "sausage": return (3, 0.8)
        case "mill": return (night ? 2 : 4, 0.8)
        default: return nil
        }
    }

    /// Кого слышно: станция, у которой пёс, плюс самые доходные (при равенстве — раньше в списке).
    static func audible(_ rates: [(id: String, rate: Double)], dogAt: String?) -> [String] {
        var out: [String] = []
        if let d = dogAt, rates.contains(where: { $0.id == d }) { out.append(d) }
        let byRate = rates.enumerated().sorted { a, b in
            a.element.rate != b.element.rate ? a.element.rate > b.element.rate : a.offset < b.offset
        }
        for (_, r) in byRate where out.count < audibleMax && !out.contains(r.id) { out.append(r.id) }
        return out
    }

    /// Номер «тика» станции к моменту clock: вырос — пора щёлкнуть.
    static func count(_ id: String, clock: Double, night: Bool, brushed: Bool) -> Int? {
        guard let c = cycle(id, night: night, brushed: brushed), c.period > 0 else { return nil }
        return Int((clock / c.period - c.at).rounded(.down))
    }
}
