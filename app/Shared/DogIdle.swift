// Волна 44 M: пёс сам по себе. Пока его не трогают, он иногда живёт своей жизнью на главном экране:
// подходит понюхать миску, смотрит в окно на погоду, обнюхивает купленные кухню и ванну, играет с мячиком,
// валяется на ковре (на лежанке), отряхивается, зевает и прилегает. Раньше в простое он только переминался
// на месте (PetModel.tick: фиджеты раз в 15–25 с) и никуда не ходил.
//
// Что и когда — здесь, чисто и детерминированно: слот времени (slotSec) по (petId, слот) «выпадает» с шансом,
// выбор — взвешенный по позе (нуждам), часу дня, погоде, сезону, купленному и характеру (Traits), прошлое дело
// реже. Ночью и пока хозяин спит — ничего (quiet). Экономия заряда — только дела на месте и реже.
// Как — тоже здесь: путь IdleRoute (выйти с разворотом, дойти, повернуться к делу, клипы, обратно, дома ровно
// в 3/4) и реплики клипов IdleCue. Проигрывает PetChoreo.step существующими клипами, тяжёлых ассетов нет.
// Любое касание или новая поза перебивает дело сразу (PetModel.drive → PetChoreo.cutChore).
// Нужды, сейв и журнал не трогает — чистая косметика. Решения — DECISIONS.md, «Волна 44 M».

import Foundation
@preconcurrency import PetCore

/// Чем пёс занят сам.
enum IdleChore: String, CaseIterable, Sendable {
    /// Подойти к миске и понюхать.
    case bowl
    /// Поиграть с мячиком на месте.
    case toy
    /// Подойти к окну и посмотреть на погоду.
    case window
    /// Обнюхать купленное: кухню или ванну.
    case sniff
    /// Поваляться на ковре (на лежанке).
    case rug
    /// Почесаться и отряхнуться.
    case scratch
    /// Зевнуть и прилечь.
    case yawn

    /// Без шагов и поворотов — годится и при экономии заряда.
    var inPlace: Bool { self == .scratch || self == .yawn }
}

/// Что режиссёр простоя знает о псе. Собирает DogIdle.scene; тесты — напрямую.
struct IdleScene: Equatable, Sendable {
    var petId: String
    var name: String
    var pose: Pose
    var needs: [Need: Double]
    var levels: RoomPlan.Levels
    var traits: [Trait]
    /// Ночь пса или спит хозяин: в квартире тихо, пёс сам ничего не затевает.
    var quiet: Bool
    var alive: Bool
    var tzOffsetMin: Int

    func need(_ n: Need) -> Double { needs[n] ?? 100 }
    func has(_ t: Trait) -> Bool { traits.contains(t) }
}

/// Решённое дело: клипы, место и строка для VoiceOver.
struct IdlePlan: Equatable, Sendable {
    typealias P = RoomPlan.P
    var chore: IdleChore
    /// Клипы на месте по разу.
    var steps: [String]
    /// Цикл после steps и сколько секунд его держать; nil — сразу out.
    var hold: String?
    var holdSec: Double = 0
    /// Клипы по разу перед уходом обратно (встать с ковра, отряхнуться).
    var out: [String] = []
    /// Где стоять (центр пса во взрослом размере; дома — начало координат) и куда смотреть.
    var spot: P
    var face: Float
    /// Морда должна оказаться у вещи: щенку (и своему персонажу) место сдвигается вдоль взгляда под его длину.
    var aimed: Bool
    /// Лёжа (с ковра, после зевка) — встать, если дело перебили: lie_out.
    var lies = false
    var line: String

    var clips: [String] { steps + out + (hold.map { [$0] } ?? []) }

    /// Сколько длится дело на месте при длинах клипов len.
    func act(_ len: (String) -> Double) -> Double {
        steps.reduce(0.0) { $0 + len($1) } + (hold == nil ? 0 : holdSec) + out.reduce(0.0) { $0 + len($1) }
    }
}

/// Реплика клипов дела: в момент at (от начала) сыграть steps по разу, потом цикл loop.
/// back — чем вернуться в стойку дома, если дело перебили после этой реплики.
struct IdleCue: Equatable, Sendable {
    var at: Double
    var steps: [String]
    var loop: String
    var back: [String] = []
}

/// Путь дела: из дома (начало координат, yaw3q) к месту, дело, обратно, дома ровно yaw3q.
/// Повороты без перескоков: углы «развёрнуты» (PetChoreo.step смешивает их линейно, без заворота через ±π).
struct IdleRoute: Equatable, Sendable {
    typealias P = RoomPlan.P
    /// Шаг, м/с — как ChoreoPath.Walk.speed (клип walk, лапы не скользят). С плавным разгоном пик — 1,5 средней.
    static let speed: Float = 0.4
    /// Поворот на месте, рад/с, и не быстрее minTurn.
    static let turnRate: Float = 3.0
    static let minTurn = 0.35

    var spot: P
    /// Где кончается разворот назад: spot или чуть в сторону от миски (с места дела она под боком —
    /// крутясь на месте, пёс задел бы её мордой или задом, так что разворачивается, переступая в сторону).
    var pivot: P
    var y0: Float
    var yOut: Float
    var yFace: Float
    var yBack: Float
    /// Дома: y0 или y0 ± 2π, если обходил миску кругом.
    var yHome: Float
    var turnOut: Double
    var turnFace: Double
    var turnBack: Double
    var turnHome: Double
    var go: Double
    var act: Double
    var back: Double
    /// Размер пса (длина) относительно взрослого Шибы: запас у края кадра.
    var size: Float

    var moves: Bool { spot.length > 0.001 }
    var arriveAt: Double { go }
    var leaveAt: Double { go + act }
    var homeAt: Double { go + act + back }

    static func turnTime(_ d: Float) -> Double {
        abs(d) < 0.01 ? 0 : max(minTurn, Double(abs(d) / turnRate))
    }

    /// a, сдвинутый на 2πk ближе всего к b.
    static func near(_ a: Float, _ b: Float) -> Float {
        let k = ((b - a) / (2 * .pi)).rounded()
        return a + 2 * .pi * k
    }

    /// Насколько пёс при повороте yaw выступает по x — как ChoreoPath.petReach.
    static func reach(_ yaw: Float, size: Float) -> Float {
        (abs(sin(yaw)) * RoomPlan.Keep.petHalfLength + abs(cos(yaw)) * RoomPlan.Keep.petHalfWidth) * size
    }

    static func make(_ plan: IdlePlan, act: Double, size: Float = 1) -> IdleRoute {
        let y0 = RoomPlan.Keep.yaw3q
        let size = max(0.2, size)
        var spot = plan.spot
        if plan.aimed && spot.length > 0.001 {
            // Морда — там же, где у взрослого: центр вдоль взгляда на разницу полудлин.
            let d = RoomPlan.Keep.petHalfLength * (1 - size)
            spot = spot + P(sin(plan.face), cos(plan.face)) * d
        }
        if spot.length > 0.001 {
            // На месте пёс стоит мордой к делу: запас у края — под этот поворот (по пути прижимает pose(at:)).
            spot = RoomPlan.playArea.clamp(spot, inset: reach(plan.face, size: size))
        }
        let moving = spot.length > 0.001
        let yOut = moving ? near(RoomPlan.yaw(toward: spot), y0) : near(plan.face, y0)
        let yFace = near(plan.face, yOut)
        // Назад: разворот к дому — в ту сторону, где пёс не заденет миску и мяч, а из двух таких — где
        // поворачивать меньше (с доворотом дома). Если с места дела не выходит ни так, ни так — разворачивается,
        // переступая от миски, на сколько нужно. На месте — сразу из yFace в 3/4 (за turnHome).
        var yBack = yFace
        var pivot = spot
        if moving {
            let full: Float = 2 * .pi
            func cost(_ y: Float) -> Float {
                let home: Float = near(y0, y)
                return abs(y - yFace) + abs(home - y)
            }
            let away = spot - RoomPlan.Keep.bowlHome
            let dir = away * (1 / max(away.length, 0.001))
            var found = false
            for k in 0...40 where !found {
                let q = RoomPlan.playArea.clamp(spot + dir * (Float(k) * 0.01), inset: reach(yFace, size: size))
                let raw: Float = near(RoomPlan.yaw(toward: P(0, 0) - q), yFace)
                let turns: [Float] = [raw, raw - full, raw + full].sorted { cost($0) < cost($1) }
                if let y = turns.first(where: { clearTurn(from: spot, to: q, yaw: yFace, to: $0, size: size,
                                                          chore: plan.chore) }) {
                    yBack = y
                    pivot = q
                    found = true
                } else if k == 0 {
                    yBack = turns[0]
                }
            }
        }
        // Дома ровно 3/4 — с точностью до витка (обошёл миску кругом — тот же поворот на 2π дальше).
        let yHome = near(y0, yBack)
        let tOut = turnTime(yOut - y0)
        let tFace = moving ? turnTime(yFace - yOut) : 0
        let tBack = moving ? max(turnTime(yBack - yFace), Double((pivot - spot).length * 1.5 / speed) / stepAside) : 0
        let walk = moving ? Double(1.5 * spot.length / speed) : 0
        let walkHome = moving ? Double(1.5 * pivot.length / speed) : 0
        // В 3/4 пёс заворачивает ещё на подходе (последняя треть пути), а не крутится дома: морда не тычется в мяч.
        let tHome = moving ? max(turnTime(yHome - yBack), min(1.2, walkHome / 3)) : turnTime(yHome - yFace)
        return IdleRoute(spot: spot, pivot: pivot, y0: y0, yOut: yOut, yFace: yFace, yBack: yBack, yHome: yHome,
                         turnOut: tOut, turnFace: tFace, turnBack: tBack, turnHome: tHome,
                         go: max(walk, tOut + tFace), act: max(0, act), back: tBack + max(walkHome, tHome), size: size)
    }

    /// Пятно пса (с запасом pad) накрывает точку q — как RoomPlan.petCovers, но под размер.
    static func covers(_ p: P, _ yaw: Float, size: Float, _ q: P, pad: Float) -> Bool {
        let d = q - p
        let along = d.x * sin(yaw) + d.z * cos(yaw)
        let across = d.x * cos(yaw) - d.z * sin(yaw)
        return abs(along) <= RoomPlan.Keep.petHalfLength * size + pad
            && abs(across) <= RoomPlan.Keep.petHalfWidth * size + pad
    }

    /// Доля разворота назад, за которую пёс успевает переступить от миски (поворот — за весь разворот).
    static let stepAside = 0.4

    /// Разворот из (p0, a) в (p1, b) — по тем же долям, что в pose(at:) — не задевает миску
    /// (кроме дела у миски) и мяч (кроме игры с ним).
    static func clearTurn(from p0: P, to p1: P, yaw a: Float, to b: Float, size: Float, chore: IdleChore) -> Bool {
        let n = max(8, Int(abs(b - a) / 0.03))
        for i in 0...n {
            let t = Double(i) / Double(n)
            let yaw = a + (b - a) * smooth(t)
            let p = RoomPlan.playArea.clamp(p0 + (p1 - p0) * smooth(t / stepAside), inset: reach(yaw, size: size))
            if chore != .bowl && covers(p, yaw, size: size, RoomPlan.Keep.bowlHome, pad: RoomPlan.Keep.bowlRadius + 0.01) {
                return false
            }
            if chore != .toy && covers(p, yaw, size: size, RoomPlan.Keep.ballHome, pad: RoomPlan.Keep.ballRadius + 0.01) {
                return false
            }
        }
        return true
    }

    static func smooth(_ x: Double) -> Float {
        let t = Float(min(max(x, 0), 1))
        return t * t * (3 - 2 * t)
    }

    /// Доля [0…1] шага длиной d с начала u; d = 0 — сразу 1.
    static func ease(_ u: Double, _ d: Double) -> Float {
        d <= 0 ? (u >= 0 ? 1 : 0) : smooth(u / d)
    }

    /// Пёс в момент u: точка на полу и поворот. Прижат к playArea с запасом на свой поворот, как ChoreoPath.pet.
    /// Обратно: сперва разворот на месте (turnBack), потом шаг домой; в 3/4 доворачивает на последних turnHome.
    func pose(at u: Double) -> (p: P, yaw: Float) {
        let p: P, yaw: Float
        if u < leaveAt {
            p = spot * Self.ease(u, go)
            yaw = y0 + (yOut - y0) * Self.ease(u, turnOut) + (yFace - yOut) * Self.ease(u - (go - turnFace), turnFace)
        } else {
            let v = u - leaveAt
            p = (spot + (pivot - spot) * Self.ease(v, turnBack * Self.stepAside))
                * (1 - Self.ease(v - turnBack, back - turnBack))
            yaw = yFace + (yBack - yFace) * Self.ease(v, turnBack)
                + (yHome - yBack) * Self.ease(v - (back - turnHome), turnHome)
        }
        guard p.length > 0.0001 else { return (P(0, 0), yaw) }
        return (RoomPlan.playArea.clamp(p, inset: Self.reach(yaw, size: size)), yaw)
    }
}

enum DogIdle {
    /// Слот времени: раз в столько секунд пёс решает, затеять ли что-то.
    static let slotSec: Double = 40
    /// Шанс, что слот даст дело, %; при экономии заряда — меньше.
    static let chancePct = 50
    static let lowPowerChancePct = 25
    /// Вечер (местный час): чаще зевает.
    static let eveningHour = 20

    /// Дела включены. В UI-тестах — только с сидом idle*: иначе пёс уходил бы к окну посреди чужих проверок
    /// (снимки, тапы по Шибе). Юнит-тесты могут переключать.
    nonisolated(unsafe) static var enabled: Bool = !Env.isUITest || (Env.value("PET_SEED")?.hasPrefix("idle") ?? false)

    static func hash(_ key: String) -> UInt64 { StableRandom.mix(StableHash.fnv1a(key)) }

    static func slot(_ t: Double) -> Int { Int((t / slotSec).rounded(.down)) }

    // MARK: сцена

    static func scene(_ f: SaveFile, name: String, pose: Pose, needs: [Need: Double], alive: Bool,
                      levels: RoomPlan.Levels, traits: [Trait], at t: Double) -> IdleScene {
        let r = ItemPerks.rules(f)
        let o = PetRunner.owner(f, at: t)
        let quiet = PetEngine.ownerAsleep(t, o) || PetEngine.petNight(t, r, o)
        return IdleScene(petId: f.petId, name: name, pose: pose, needs: needs, levels: levels, traits: traits,
                         quiet: quiet, alive: alive, tzOffsetMin: o.tzOffsetMin)
    }

    // MARK: выбор

    enum Stance { case stand, sit, lie }

    /// Как стоит пёс в этой позе (копия PetStance.stance для простоя: грязный сидит, устал — лежит).
    static func stance(_ p: Pose) -> Stance {
        switch p {
        case .dirty, .bath: return .sit
        case .tired, .critical, .sleep, .nap: return .lie
        default: return .stand
        }
    }

    /// Что вообще можно в этой позе. Ест, ласкается, спит, моется, плохо, гуляет — ничего.
    static func allowed(_ p: Pose) -> [IdleChore] {
        switch p {
        case .happy, .idle: return IdleChore.allCases
        case .hungry: return [.bowl, .window, .sniff]
        case .bored: return [.toy, .window, .sniff, .rug]
        case .lonely, .sulky: return [.window]
        case .dirty: return [.scratch]
        case .tired: return [.yawn]
        default: return []
        }
    }

    static func localHour(_ t: Double, tzOffsetMin: Int) -> Int {
        let s = (t + Double(tzOffsetMin) * 60).truncatingRemainder(dividingBy: 86400)
        return Int(((s < 0 ? s + 86400 : s) / 3600).rounded(.down))
    }

    /// Веса дел: нужды, час, погода, сезон, купленное, характер. 0 — нельзя.
    static func weights(_ s: IdleScene, pose: Pose, at t: Double, weather: WeatherKind, season: Season,
                        last: IdleChore?, lowPower: Bool) -> [(IdleChore, Int)] {
        let hour = localHour(t, tzOffsetMin: s.tzOffsetMin)
        let evening = hour >= eveningHour || hour < 7
        var out: [(IdleChore, Int)] = []
        for c in allowed(pose) {
            if lowPower && !c.inPlace { continue }
            var w = 0
            switch c {
            case .bowl:
                w = pose == .hungry ? 6 : (s.need(.food) < 60 ? 3 : 1)
            case .toy:
                w = 1 + (s.need(.fun) < 50 ? 3 : 0) + (s.has(.playful) ? 3 : 0) + (pose == .bored ? 3 : 0)
                    - (evening ? 1 : 0)
            case .window:
                w = 2 + (weather != .clear ? 3 : 0) + (s.has(.independent) ? 2 : 0) + (season == .winter ? 1 : 0)
            case .sniff:
                guard s.levels.kitchen > 0 || s.levels.bath > 0 else { continue }
                w = 2 + (s.levels.kitchen > 0 && s.need(.food) < 60 ? 2 : 0) + (s.has(.independent) ? 1 : 0)
            case .rug:
                w = 1 + (s.has(.calm) ? 3 : 0) + (s.has(.cuddly) ? 1 : 0) + (season == .summer ? 1 : 0)
                    + (s.levels.bed > 0 ? 1 : 0)
            case .scratch:
                w = pose == .dirty ? 3 : ((s.need(.clean) < 50 ? 3 : 1) + (s.has(.scruffy) || s.has(.tidy) ? 2 : 0))
            case .yawn:
                w = pose == .tired ? 3 : ((s.need(.energy) < 40 ? 5 : 1) + (evening ? 2 : 0))
            }
            if c == last { w = (w + 2) / 3 }
            if w > 0 { out.append((c, w)) }
        }
        return out
    }

    /// Дело на слот времени t или nil: тихо, не жив, поза не та, слот не выпал, нечего делать.
    /// pose — что сейчас играет сцена (может отставать от снимка); нет — поза из сцены.
    static func decide(_ s: IdleScene, pose: Pose? = nil, at t: Double, weather: WeatherKind, season: Season,
                       last: IdleChore? = nil, lowPower: Bool = false) -> IdlePlan? {
        guard enabled, s.alive, !s.quiet else { return nil }
        let pose = pose ?? s.pose
        let n = slot(t)
        let gate = hash("idle:\(s.petId):\(n)")
        guard Int(gate % 100) < (lowPower ? lowPowerChancePct : chancePct) else { return nil }
        let ws = weights(s, pose: pose, at: t, weather: weather, season: season, last: last, lowPower: lowPower)
        let total = ws.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        var r = Int(hash("idle:\(s.petId):\(n):pick") % UInt64(total))
        var pick = ws[0].0
        for (c, w) in ws {
            if r < w { pick = c; break }
            r -= w
        }
        let h = hash("idle:\(s.petId):\(n):hold")
        return plan(pick, s, stance: stance(pose), weather: weather, roll: Double(h % 1000) / 999)
    }

    // MARK: места (комната, начало — дом; сверка — AutonomyTests)

    typealias P = RoomPlan.P
    /// У миски: на линии дом → миска, морда в 2 см от её края.
    static var bowlSpot: P {
        let b = RoomPlan.Keep.bowlHome
        let d = b * (1 / b.length)
        return b - d * (RoomPlan.Keep.petHalfLength + RoomPlan.Keep.bowlRadius + 0.02)
    }
    /// У окна: на дальнем краю площадки под окном, спиной к камере.
    static let windowSpot = P(0.06, -1.0)
    /// У кухни: правее холодильника, морда к его углу; у ванны — левее ванны.
    static let kitchenSpot = P(-0.05, -1.0)
    static let kitchenLook = P(-0.33, -1.18)
    static let bathSpot = P(0.10, -0.88)
    static let bathLook = P(0.25, -1.18)
    /// Валяется дома боком к камере влево: вправо морда упёрлась бы в мячик.
    static let rugYaw: Float = RoomPlan.Keep.yaw3q - 0.7

    static func plan(_ c: IdleChore, _ s: IdleScene, stance: Stance, weather: WeatherKind, roll: Double) -> IdlePlan? {
        let name = s.name.isEmpty ? "Пёс" : s.name
        let home = P(0, 0)
        func span(_ a: Double, _ b: Double) -> Double { a + (b - a) * roll }
        switch (c, stance) {
        case (.bowl, .stand):
            let b = RoomPlan.Keep.bowlHome
            return IdlePlan(chore: c, steps: ["sniff", "head_tilt"], hold: nil, spot: bowlSpot,
                            face: RoomPlan.yaw(toward: b - bowlSpot), aimed: true, line: "\(name) нюхает миску")
        case (.window, .stand):
            var line = "\(name) смотрит в окно"
            var steps = ["look_l", "look_r"]
            if weather.wet {
                line += " — там дождь"
                steps.append("head_tilt")
            } else if weather == .snow {
                line += " — идёт снег"
                steps.append("head_tilt")
            }
            return IdlePlan(chore: c, steps: steps, hold: "idle", holdSec: span(3, 5), spot: windowSpot,
                            face: .pi, aimed: false, line: line)
        case (.sniff, .stand):
            let kitchen: Bool
            switch (s.levels.kitchen > 0, s.levels.bath > 0) {
            case (true, false): kitchen = true
            case (false, true): kitchen = false
            case (true, true):
                if s.need(.food) < 60 { kitchen = true } else if s.need(.clean) < 60 { kitchen = false } else { kitchen = roll < 0.5 }
            default: return nil
            }
            let spot = kitchen ? kitchenSpot : bathSpot
            let look = kitchen ? kitchenLook : bathLook
            return IdlePlan(chore: c, steps: ["sniff", "head_tilt"], hold: nil, spot: spot,
                            face: RoomPlan.yaw(toward: look - spot), aimed: true,
                            line: "\(name) обнюхивает \(kitchen ? "кухню" : "ванную")")
        case (.toy, .stand):
            return IdlePlan(chore: c, steps: ["sniff", "play_bow", "hop", "idle_wag"], hold: nil, spot: home,
                            face: RoomPlan.yaw(toward: RoomPlan.Keep.ballHome), aimed: false,
                            line: "\(name) играет с мячиком")
        case (.rug, .stand):
            return IdlePlan(chore: c, steps: ["lie_in"], hold: "lie", holdSec: span(6, 9), out: ["lie_out", "shake"],
                            spot: home, face: rugYaw, aimed: false, lies: true,
                            line: "\(name) валяется \(s.levels.bed > 0 ? "на лежанке" : "на ковре")")
        case (.scratch, .sit):
            return IdlePlan(chore: c, steps: ["sit_out", "shake", "sit_in"], hold: nil, spot: home,
                            face: RoomPlan.Keep.yaw3q, aimed: false, line: "\(name) отряхивается")
        case (.scratch, .stand):
            return IdlePlan(chore: c, steps: ["shake"], hold: nil, spot: home, face: RoomPlan.Keep.yaw3q, aimed: false,
                            line: "\(name) отряхивается")
        case (.yawn, .stand):
            return IdlePlan(chore: c, steps: ["yawn", "lie_in"], hold: "lie", holdSec: span(6, 10), out: ["lie_out"],
                            spot: home, face: RoomPlan.Keep.yaw3q, aimed: false, lies: true, line: "\(name) зевает")
        case (.yawn, .lie):
            return IdlePlan(chore: c, steps: ["yawn"], hold: nil, spot: home, face: RoomPlan.Keep.yaw3q, aimed: false,
                            line: "\(name) зевает")
        default:
            return nil
        }
    }

    // MARK: клипы по пути

    /// Реплики клипов: шаг (если идёт), дело на месте, шаг обратно, дома — свой цикл homeLoop.
    static func cues(_ plan: IdlePlan, _ r: IdleRoute, homeLoop: String, len: (String) -> Double) -> [IdleCue] {
        var out: [IdleCue] = []
        if r.moves { out.append(IdleCue(at: 0, steps: [], loop: "walk")) }
        if !plan.steps.isEmpty || r.moves {
            out.append(IdleCue(at: r.arriveAt, steps: plan.steps, loop: plan.hold ?? homeLoop,
                               back: plan.lies ? ["lie_out"] : []))
        }
        // Конец лёжки/стойки: если уходит пешком без клипов выхода — эту роль играет шаг на leaveAt.
        if plan.hold != nil, !plan.out.isEmpty || !r.moves {
            let at = r.arriveAt + plan.steps.reduce(0.0) { $0 + len($1) } + plan.holdSec
            out.append(IdleCue(at: min(at, r.leaveAt), steps: plan.out, loop: homeLoop))
        }
        if r.moves {
            out.append(IdleCue(at: r.leaveAt, steps: [], loop: "walk"))
            out.append(IdleCue(at: r.homeAt, steps: [], loop: homeLoop))
        }
        return out
    }
}
