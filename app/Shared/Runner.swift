// Мини-игра «Раннер» (волна 55b, TZ_v3 «Волна 55» п. 3): Шиба бежит по своему миру — двор → район → парк, мир
// меняется каждые biome_m метров. Три полосы; свайп влево/вправо — сменить полосу, вверх — прыжок, вниз — подкат.
// Препятствия — из мира питомца: лужи и клумбы перепрыгнуть, под лавочкой и стаей голубей проскользнуть,
// ящики — только обежать. По пути монеты-косточки. Скорость и плотность растут плавно; три сердечка; заезд — до
// max_seconds (3 мин), дальше «Финиш!». Средний заезд — 1–2 мин: к концу скорость вдвое выше стартовой.
//
// Здесь только логика без экрана (RunnerScreen.swift рисует):
// • трасса детерминирована от сида: ряды препятствий и монеты генерирует CatchRandom (SplitMix64) по порядку,
//   и раскладка не зависит от игрока — один сид, одни и те же ряды (UI-тесты, тесты);
// • проходимость по построению: в каждом ряду есть «безопасная» полоса без препятствий, и от ряда к ряду она
//   сдвигается не больше чем на одну полосу; редкая «стенка» (во всех трёх полосах то, что перепрыгивают или
//   проползают) — проходима действием в любой полосе. Между рядами всегда ≥ ~0,5 с — смена полосы 0,12 с;
// • сложность — от пройденных метров: k = 1 − e^(−d/900); скорость, промежуток между рядами и плотность — lerp по k;
// • столкновения — по подшагам 1/120 с: собака в полосе round(x), препятствие на отрезке [z − L/2, z + L/2];
//   прыжок снимает «прыгучие», подкат — «подкатные», ящик бьёт всегда. Удар — минус сердечко и 1,2 с неуязвимости;
// • очки — метры + coin_points за монету; награда — как у «Лови мячик» (CatchGame.want через asCatch): base…max до
//   par_score, убывание по номеру партии за сутки, польза вещей, свой daily_cap и общий потолок мини-игр;
//   настроение — ядерным play. Пёс занят (MiniGames.busy) — заезд «просто так»: только рекорд;
// • рекорд и дневные счётчики — верхним уровнем SaveFile (runnerBest, runnerDay, runnerCoins, runnerGames).
//
// Координаты: полосы 0…2 слева направо (x — дробная, пока собака перебегает), z — метры вперёд от старта.

import Foundation
@preconcurrency import PetCore

// MARK: - Настройки

struct RunnerConfig: Hashable, Sendable {
    var name = "Раннер"
    /// Монеты за заезд хоть с одним очком…
    var base = 5
    /// …и за par_score очков и больше.
    var max = 35
    var parScore = 1500
    /// Свой потолок монет в местные сутки и общий на все мини-игры.
    var dailyCap = 60
    var sharedCap = MiniGames.defaultSharedCap
    var diminishing: [CatchConfig.Step] = [.init(from: 1, x: 1), .init(from: 7, x: 0.5), .init(from: 13, x: 0.2)]
    var lives = 3
    /// Дольше заезд не длится: финиш.
    var maxSeconds = 180.0
    /// Через сколько метров меняется мир (двор → район → парк → двор…).
    var biomeMetres = 400.0
    /// Метров в секунду на старте и к чему скорость стремится.
    var speedMin = 7.0
    var speedMax = 15.0
    var coinPoints = 5

    static let shared = RunnerConfig(json: Catalog.economy() ?? .null)

    init() {}

    init(json e: JSONValue) {
        func int(_ v: JSONValue, _ d: Int) -> Int { v.double.map { Int($0) } ?? d }
        let g = e["minigames"]
        let c = g["list"]["runner"]
        name = c["name"].string ?? name
        base = int(c["base"], base)
        max = Swift.max(base, int(c["max"], max))
        parScore = Swift.max(1, int(c["par_score"], parScore))
        dailyCap = Swift.max(0, int(c["daily_cap"], dailyCap))
        sharedCap = Swift.max(0, int(g["daily_cap"], sharedCap))
        lives = Swift.max(1, int(c["lives"], lives))
        maxSeconds = Swift.max(30, c["max_seconds"].double ?? maxSeconds)
        biomeMetres = Swift.max(100, c["biome_m"].double ?? biomeMetres)
        speedMin = Swift.max(2, c["speed_min"].double ?? speedMin)
        speedMax = Swift.max(speedMin, c["speed_max"].double ?? speedMax)
        coinPoints = Swift.max(0, int(c["coin_points"], coinPoints))
        diminishing = CatchConfig(json: e).diminishing
    }

    /// Те же цифры в виде CatchConfig — формула монет одна на все игры (CatchGame.want).
    var asCatch: CatchConfig {
        var c = CatchConfig()
        c.base = base
        c.max = max
        c.parScore = parScore
        c.dailyCap = dailyCap
        c.sharedCap = sharedCap
        c.diminishing = diminishing
        return c
    }
}

// MARK: - Мир и препятствия

/// Как увернуться от препятствия.
enum RunnerDodge: String, Hashable, Sendable {
    /// Перепрыгнуть (свайп вверх) — или обежать.
    case jump
    /// Проскользнуть под ним (свайп вниз) — или обежать.
    case slide
    /// Только обежать по соседней полосе.
    case lane
}

/// Препятствия — из мира питомца, свои (не «поезда и барьеры» из чужих раннеров).
enum RunnerObstacle: String, CaseIterable, Hashable, Sendable {
    case puddle, flowerbed, crate, bench, pigeons

    var dodge: RunnerDodge {
        switch self {
        case .puddle, .flowerbed: return .jump
        case .bench, .pigeons: return .slide
        case .crate: return .lane
        }
    }

    /// Длина вдоль трассы, м.
    var length: Double {
        switch self {
        case .puddle: return 1.2
        case .flowerbed: return 0.9
        case .crate: return 0.9
        case .bench: return 0.7
        case .pigeons: return 0.8
        }
    }

    /// Для VoiceOver: «впереди лужа».
    var title: String {
        switch self {
        case .puddle: return "лужа"
        case .flowerbed: return "клумба"
        case .crate: return "ящики"
        case .bench: return "лавочка"
        case .pigeons: return "голуби"
        }
    }
}

/// Мир под лапами: меняется каждые biome_m метров по кругу.
enum RunnerBiome: Int, CaseIterable, Hashable, Sendable {
    case yard, district, park

    /// Что встречается в этом мире (в каждом есть и «прыгнуть», и «проползти», и «обежать»).
    var kinds: [RunnerObstacle] {
        switch self {
        case .yard: return [.puddle, .crate, .flowerbed, .bench]
        case .district: return [.crate, .bench, .pigeons, .puddle]
        case .park: return [.flowerbed, .bench, .pigeons, .puddle, .crate]
        }
    }

    var title: String {
        switch self {
        case .yard: return "Двор"
        case .district: return "Район"
        case .park: return "Парк"
        }
    }

    /// Значок на плашке (SF Symbol).
    var icon: String {
        switch self {
        case .yard: return "house.fill"
        case .district: return "building.2.fill"
        case .park: return "tree.fill"
        }
    }
}

/// Ряд трассы: на отметке z в каждой из трёх полос — препятствие или пусто.
struct RunnerRow: Hashable, Sendable {
    let index: Int
    let z: Double
    let biome: RunnerBiome
    /// По полосам 0…2.
    let lanes: [RunnerObstacle?]
    /// Полоса гарантированного пути (без препятствий; у «стенки» — проходима действием).
    let safe: Int
    /// Во всех трёх полосах — перепрыгнуть или проползти.
    let wall: Bool

    func passable(_ lane: Int) -> Bool { lanes[lane].map { $0.dodge != .lane } ?? true }
    /// Самое длинное препятствие ряда (для «уже пробежали»).
    var span: Double { lanes.compactMap { $0?.length }.max() ?? 0 }
}

/// Монета-косточка на трассе.
struct RunnerCoin: Hashable, Sendable {
    let index: Int
    let lane: Int
    let z: Double
}

/// Трасса, которая достраивается вперёд по мере бега. Зависит только от сида: игрок её не меняет.
struct RunnerTrack: Sendable {
    let seed: UInt64
    let cfg: RunnerConfig
    private(set) var rows: [RunnerRow] = []
    private(set) var coins: [RunnerCoin] = []
    private var rng: CatchRandom
    private var nextZ = Runner.startClear
    private var safe = 1

    init(seed: UInt64, cfg: RunnerConfig = .shared) {
        self.seed = seed
        self.cfg = cfg
        rng = CatchRandom(seed: seed ^ 0x52_55_4E_4E_45_52)  // «RUNNER»: не та же последовательность, что у мячика
    }

    /// Достроить ряды до отметки z (включительно с запасом одного ряда).
    mutating func ensure(to z: Double) {
        while nextZ <= z { addRow() }
    }

    private mutating func addRow() {
        let z = nextZ
        let k = Runner.difficulty(at: z)
        let biome = Runner.biome(at: z, cfg)
        let r = rng.unit()
        safe = Swift.min(2, Swift.max(0, safe + (r < 0.3 ? -1 : r < 0.6 ? 1 : 0)))
        var lanes: [RunnerObstacle?] = [nil, nil, nil]
        let wall = z > Runner.wallFrom && rng.unit() < Runner.lerp(0, 0.14, k)
        if wall {
            let soft = biome.kinds.filter { $0.dodge != .lane }
            let kind = soft[Int(rng.unit() * Double(soft.count)) % soft.count]
            lanes = [kind, kind, kind]
        } else {
            let density = Runner.lerp(0.3, 0.8, k)
            for l in 0..<3 where l != safe && rng.unit() < density {
                lanes[l] = biome.kinds[Int(rng.unit() * Double(biome.kinds.count)) % biome.kinds.count]
            }
            if lanes.allSatisfy({ $0 == nil }) {
                let others = (0..<3).filter { $0 != safe }
                let l = others[Int(rng.unit() * 2) % 2]
                lanes[l] = biome.kinds[Int(rng.unit() * Double(biome.kinds.count)) % biome.kinds.count]
            }
        }
        let row = RunnerRow(index: rows.count, z: z, biome: biome, lanes: lanes, safe: safe, wall: wall)
        rows.append(row)
        let v = Runner.speed(at: z, cfg)
        var gap = v * Runner.lerp(1.25, 0.6, k) * (0.9 + 0.25 * rng.unit())
        if wall { gap += v * 0.3 }   // после стенки — время приземлиться
        // Дорожка монет в безопасной полосе между этим рядом и следующим: не на препятствиях.
        if rng.unit() < 0.45 {
            let from = z + row.span / 2 + 1.0
            let to = z + gap - Runner.maxLength / 2 - 1.0
            var c = from
            while c <= to {
                coins.append(RunnerCoin(index: coins.count, lane: safe, z: c))
                c += 1.6
                if c - from > 7 { break }
            }
        }
        nextZ = z + gap
    }
}

// MARK: - Заезд

enum RunnerMove: String, Hashable, Sendable {
    case left, right, jump, slide
}

enum RunnerEvent: Hashable, Sendable {
    case coin(RunnerCoin)
    case hit(RunnerObstacle, lane: Int)
    case biome(RunnerBiome)
    case finish
}

/// Заезд: трасса, время, метры, полоса, прыжок/подкат, сердечки и монеты. Двигает его экран (advance), свайпы — swipe.
struct RunnerRun: Sendable {
    let cfg: RunnerConfig
    private(set) var track: RunnerTrack
    private(set) var t = 0.0
    private(set) var distance = 0.0
    /// Полоса, куда бежим (0…2), и где собака сейчас (дробная — в перебежке).
    private(set) var lane = 1
    private(set) var x = 1.0
    /// Сколько уже в прыжке / в подкате, с; nil — нет.
    private(set) var air: Double?
    private(set) var slide: Double?
    private(set) var lives: Int
    private(set) var hits = 0
    private(set) var picked = 0
    private(set) var biome = RunnerBiome.yard
    /// До какого t после удара собака неуязвима.
    private(set) var safeUntil = 0.0
    /// Собранные монеты (index) и сбитые препятствия (row * 3 + lane) — экран их прячет.
    private(set) var taken: Set<Int> = []
    private(set) var knocked: Set<Int> = []
    private var firstRow = 0
    private var firstCoin = 0

    init(seed: UInt64, cfg: RunnerConfig = .shared) {
        self.cfg = cfg
        track = RunnerTrack(seed: seed, cfg: cfg)
        lives = cfg.lives
        track.ensure(to: Runner.lookahead)
    }

    var seed: UInt64 { track.seed }
    var isOver: Bool { lives <= 0 || t >= cfg.maxSeconds }
    /// Добежали до конца времени, не растеряв сердечки.
    var finished: Bool { lives > 0 && t >= cfg.maxSeconds }
    var score: Int { Int(distance) + picked * cfg.coinPoints }
    var metres: Int { Int(distance) }
    var speed: Double { Runner.speed(at: distance, cfg) }
    var timeLeft: Double { Swift.max(0, cfg.maxSeconds - t) }
    var invulnerable: Bool { t < safeUntil }
    /// Высота прыжка 0…1 (парабола) — для экрана.
    var height: Double {
        guard let a = air else { return 0 }
        let p = Swift.min(1, a / Runner.jumpSeconds)
        return 4 * p * (1 - p)
    }
    var sliding: Bool { slide != nil }
    var jumping: Bool { air != nil }
    /// Полоса, в которой собака сейчас для столкновений.
    var hitLane: Int { Swift.min(2, Swift.max(0, Int(x.rounded()))) }

    /// Ряды и монеты, которые видно: от чуть позади до lookahead вперёд.
    func rows(ahead: Double = Runner.lookahead) -> ArraySlice<RunnerRow> {
        let lo = distance - 6, hi = distance + ahead
        var i = firstRow
        while i > 0, track.rows[i - 1].z >= lo { i -= 1 }
        var j = i
        while j < track.rows.count, track.rows[j].z <= hi { j += 1 }
        return track.rows[i..<j]
    }

    func coins(ahead: Double = Runner.lookahead) -> [RunnerCoin] {
        let lo = distance - 3, hi = distance + ahead
        var out: [RunnerCoin] = []
        var i = firstCoin
        while i < track.coins.count, track.coins[i].z <= hi {
            let c = track.coins[i]
            if c.z >= lo, !taken.contains(c.index) { out.append(c) }
            i += 1
        }
        return out
    }

    /// Ближайший ряд, который ещё не пробежали.
    var nextRow: RunnerRow? {
        var i = firstRow
        while i < track.rows.count {
            let r = track.rows[i]
            if r.z + r.span / 2 + Runner.dogHalf > distance { return r }
            i += 1
        }
        return nil
    }

    func isTaken(_ c: RunnerCoin) -> Bool { taken.contains(c.index) }
    func isKnocked(_ row: RunnerRow, lane: Int) -> Bool { knocked.contains(row.index * 3 + lane) }

    /// Свайп. Прыжок — только с земли (из подката можно: подкат обрывается); вниз в прыжке — быстро вниз и подкат.
    mutating func swipe(_ m: RunnerMove) {
        guard !isOver else { return }
        switch m {
        case .left: lane = Swift.max(0, lane - 1)
        case .right: lane = Swift.min(2, lane + 1)
        case .jump:
            guard air == nil else { return }
            slide = nil
            air = 0
        case .slide:
            air = nil
            slide = 0
        }
    }

    /// Время вперёд на dt (экран даёт ≤ 0,05 с; больше — режется). Внутри подшаги по 1/120 с.
    @discardableResult
    mutating func advance(by dt: Double) -> [RunnerEvent] {
        guard !isOver, dt > 0 else { return [] }
        let total = Swift.min(dt, 0.05, cfg.maxSeconds - t)
        let n = Swift.max(1, Int((total / Runner.substep).rounded(.up)))
        let h = total / Double(n)
        var events: [RunnerEvent] = []
        for _ in 0..<n {
            step(h, &events)
            if lives <= 0 { break }
        }
        if t >= cfg.maxSeconds - 1e-9, lives > 0 {
            t = cfg.maxSeconds
            events.append(.finish)
        }
        return events
    }

    private mutating func step(_ h: Double, _ events: inout [RunnerEvent]) {
        t += h
        distance += Runner.speed(at: distance, cfg) * h
        track.ensure(to: distance + Runner.lookahead)
        // Перебежка между полосами.
        let move = h / Runner.laneSeconds
        let d = Double(lane) - x
        x += abs(d) <= move ? d : (d < 0 ? -move : move)
        if let a = air { air = a + h >= Runner.jumpSeconds ? nil : a + h }
        if let s = slide { slide = s + h >= Runner.slideSeconds ? nil : s + h }
        let b = Runner.biome(at: distance, cfg)
        if b != biome {
            biome = b
            events.append(.biome(b))
        }
        // Ряды позади больше не нужны.
        while firstRow < track.rows.count, track.rows[firstRow].z + 3 < distance { firstRow += 1 }
        while firstCoin < track.coins.count, track.coins[firstCoin].z + 2 < distance { firstCoin += 1 }
        let l = hitLane
        // Монеты.
        var i = firstCoin
        while i < track.coins.count, track.coins[i].z <= distance + Runner.coinReach {
            let c = track.coins[i]
            if c.lane == l, abs(c.z - distance) <= Runner.coinReach, !isTaken(c) {
                taken.insert(c.index)
                picked += 1
                events.append(.coin(c))
            }
            i += 1
        }
        // Препятствия.
        var j = firstRow
        while j < track.rows.count, track.rows[j].z - 2 <= distance {
            let row = track.rows[j]
            j += 1
            guard let o = row.lanes[l], !knocked.contains(row.index * 3 + l) else { continue }
            guard abs(row.z - distance) <= o.length / 2 + Runner.dogHalf else { continue }
            if o.dodge == .jump, height >= Runner.clearHeight { continue }
            if o.dodge == .slide, slide != nil { continue }
            if invulnerable { continue }
            knocked.insert(row.index * 3 + l)
            lives -= 1
            hits += 1
            safeUntil = t + Runner.hurtSeconds
            events.append(.hit(o, lane: l))
            if lives <= 0 { return }
        }
    }
}

// MARK: - Итог

struct RunnerResult: Hashable, Sendable {
    var score = 0
    var metres = 0
    /// Монет-косточек собрано на трассе.
    var picked = 0
    var hits = 0
    /// Добежали до финиша.
    var finished = false
    /// Монеты за игру (после убывания, пользы вещей и потолков).
    var coins = 0
    /// Монеты ухода за «Поиграть» (ядерное play).
    var careCoins = 0
    var capped = false
    var best = 0
    var isRecord = false
    var played = false
    var reason: String?
    /// Заезд «просто так» (MiniGames.busy на старте); nil — настоящий.
    var free: String?

    var totalCoins: Int { coins + careCoins }
}

enum Runner {
    static let lanes = 3
    /// Первые метры без препятствий: разогнаться.
    static let startClear = 30.0
    /// Стенки — не раньше этой отметки.
    static let wallFrom = 250.0
    /// Сколько метров трассы вперёд держит экран.
    static let lookahead = 70.0
    static let substep = 1.0 / 120
    /// Полдлины собаки вдоль трассы, м.
    static let dogHalf = 0.35
    static let coinReach = 0.6
    static let laneSeconds = 0.12
    static let jumpSeconds = 0.62
    static let slideSeconds = 0.7
    /// С какой доли высоты прыжка «прыгучее» уже под лапами.
    static let clearHeight = 0.35
    static let hurtSeconds = 1.2
    static let maxLength = RunnerObstacle.allCases.map(\.length).max() ?? 1

    /// Сложность 0…1 от метров: быстро растёт в начале, к ~2 км почти 1.
    static func difficulty(at d: Double) -> Double { 1 - exp(-Swift.max(0, d) / 900) }

    /// Скорость, м/с, на отметке d.
    static func speed(at d: Double, _ cfg: RunnerConfig = .shared) -> Double {
        lerp(cfg.speedMin, cfg.speedMax, difficulty(at: d))
    }

    /// Средний промежуток между рядами по времени, с (без разброса).
    static func gapSeconds(at d: Double) -> Double { lerp(1.25, 0.6, difficulty(at: d)) }
    /// Доля «лишних» полос с препятствием.
    static func density(at d: Double) -> Double { lerp(0.3, 0.8, difficulty(at: d)) }

    static func biome(at d: Double, _ cfg: RunnerConfig = .shared) -> RunnerBiome {
        let i = Int(Swift.max(0, d) / cfg.biomeMetres) % RunnerBiome.allCases.count
        return RunnerBiome.allCases[i]
    }

    static func lerp(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * k }

    // MARK: награда

    static func rollDay(_ f: inout SaveFile, now: Double) {
        guard let d = DayKey.newer(than: f.runnerDay, at: now) else { return }
        f.runnerDay = d
        f.runnerCoins = 0
        f.runnerGames = 0
    }

    static func coinsToday(_ f: SaveFile, now: Double) -> Int {
        DayKey.today(f.runnerCoins, day: f.runnerDay, at: now)
    }

    /// Сколько монет ещё можно получить сегодня: свой потолок и общий потолок мини-игр.
    static func coinsLeft(_ f: SaveFile, now: Double, _ cfg: RunnerConfig = .shared) -> Int {
        let own = cfg.dailyCap - coinsToday(f, now: now)
        let all = cfg.sharedCap - MiniGames.coinsToday(f, now: now)
        return Swift.max(0, Swift.min(own, all))
    }

    /// Заезд кончился: рекорд, монеты с потолками, настроение через ядерный play. Пишет только в f.
    @discardableResult
    static func finish(_ run: RunnerRun, in f: inout SaveFile, now: Double, free: String? = nil,
                       _ cfg: RunnerConfig = .shared) -> RunnerResult {
        finish(score: run.score, metres: run.metres, picked: run.picked, hits: run.hits, finished: run.finished,
               in: &f, now: now, free: free, cfg)
    }

    /// free — заезд «просто так» (MiniGames.busy на старте, волна 32): только рекорд, без монет, play и счётчика.
    @discardableResult
    static func finish(score: Int, metres: Int = 0, picked: Int = 0, hits: Int = 0, finished: Bool = false,
                       in f: inout SaveFile, now: Double, free: String? = nil,
                       _ cfg: RunnerConfig = .shared) -> RunnerResult {
        var r = RunnerResult(score: Swift.max(0, score), metres: metres, picked: picked, hits: hits, finished: finished)
        r.free = free
        PetRunner.catchUp(&f, now: now)
        rollDay(&f, now: now)
        if free == nil { f.runnerGames += 1 }
        let wish = free != nil ? 0 : CatchGame.want(score: r.score, game: f.runnerGames, buff: CatchGame.coinsX(f), cfg.asCatch)
        // Пёс умер, пока бежали, — монет нет: мёртвому не платим.
        let got = f.pet.alive ? Swift.min(wish, coinsLeft(f, now: now, cfg)) : 0
        f.runnerCoins += got
        f.econ.wallet.coins += got
        r.coins = got
        r.capped = f.pet.alive && got < wish
        r.isRecord = r.score > f.runnerBest
        f.runnerBest = Swift.max(f.runnerBest, r.score)
        // Рекорд «просто так» — без ✂️: Shards.settle его уже видел (волна 32).
        if free != nil { f.shardLog.best[MiniGame.runner.rawValue] = f.runnerBest }
        r.best = f.runnerBest
        if r.score > 0, free == nil {
            let out = PetRunner.apply(.play, source: .app, to: &f, now: now)
            r.played = out.ok
            r.careCoins = out.ok ? out.coins : 0
            r.reason = out.ok ? nil : out.reason
        }
        return r
    }

    // MARK: автопилот (тесты, UI-снимки)

    /// Бежит в ближайшую свободную полосу ближайшего ряда; у стенки прыгает или проползает вовремя.
    struct Pilot: Sendable {
        mutating func step(_ run: inout RunnerRun) {
            guard let row = run.nextRow else { return }
            let free = (0..<Runner.lanes).filter { row.lanes[$0] == nil }
            let pass = (0..<Runner.lanes).filter { row.passable($0) }
            let pool = free.isEmpty ? pass : free
            let target = pool.min { abs($0 - run.lane) < abs($1 - run.lane) } ?? run.lane
            if target < run.lane { run.swipe(.left) } else if target > run.lane { run.swipe(.right) }
            guard let o = row.lanes[run.lane], o.dodge != .lane else { return }
            let ahead = row.z - run.distance
            switch o.dodge {
            case .jump where !run.jumping && ahead <= run.speed * Runner.jumpSeconds * 0.42:
                run.swipe(.jump)
            case .slide where !run.sliding && ahead <= run.speed * Runner.slideSeconds * 0.4:
                run.swipe(.slide)
            default: break
            }
        }
    }

    /// Прогнать заезд автопилотом кадрами по 1/60 с до until секунд (или до конца). Детерминировано.
    static func autoplay(seed: UInt64, until: Double = .infinity, _ cfg: RunnerConfig = .shared) -> RunnerRun {
        var run = RunnerRun(seed: seed, cfg: cfg)
        var pilot = Pilot()
        while !run.isOver, run.t < until {
            pilot.step(&run)
            run.advance(by: Swift.min(1.0 / 60, until - run.t))
        }
        return run
    }

    // MARK: тексты

    static func resultTitle(_ r: RunnerResult) -> String {
        if r.isRecord && r.score > 0 { return "Новый рекорд!" }
        if r.finished { return "Финиш!" }
        if r.score == 0 { return "Даже не разбежались…" }
        return "Ой, споткнулись!"
    }

    /// «+12 монет», «На сегодня монет хватит», «Играли просто так — без монет» или nil (очков нет).
    static func rewardText(_ r: RunnerResult) -> String? {
        if r.free != nil { return MiniGames.freeReward }
        if r.totalCoins > 0 { return "+\(EconText.coins(r.totalCoins))" }
        if r.capped { return "На сегодня монет за игры хватит" }
        return nil
    }

    /// Тост, когда заезд закрыли не кнопкой: «Раннер: 340 м, +12 монет». Без награды и потолка — nil.
    static func toastText(_ r: RunnerResult) -> String? {
        guard let reward = rewardText(r) else { return nil }
        let tail = reward.first?.isLetter == true ? reward.prefix(1).lowercased() + reward.dropFirst() : reward
        return "\(RunnerConfig.shared.name): \(r.metres) м, \(tail)"
    }

    /// Реакция пса в комнате после заезда (экран закрылся): та же, что на «Поиграть».
    static let reactKind = "play"

    /// Фраза пса в комнате после заезда (AppModel.cheerRunner). Слова «Шиба» нет — PetNames.adapt не нужен.
    static func shibaLine(_ r: RunnerResult) -> String {
        if r.score == 0 { return "Побежали ещё? Я только разогрелся!" }
        if r.isRecord { return "Гав! \(r.metres) м — наш рекорд!" }
        if r.finished { return "Добежали до конца! Лапы гудят, но я счастлив!" }
        let lines = [
            "Вот это пробежка! Лужи — мои!",
            "Голуби разлетелись, а мы бежим дальше!",
            "Ещё забег? Я знаю короткую дорогу через парк!",
        ]
        return lines[r.metres % lines.count]
    }

    /// VoiceOver: что впереди в полосе lane ближайшего ряда.
    static func ahead(_ run: RunnerRun) -> String {
        guard let row = run.nextRow else { return "Дорога свободна" }
        let names = ["слева", "посередине", "справа"]
        let parts = (0..<lanes).compactMap { l in row.lanes[l].map { "\(names[l]) \($0.title)" } }
        return parts.isEmpty ? "Дорога свободна" : "Впереди: " + parts.joined(separator: ", ")
    }
}
