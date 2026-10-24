// Мини-игра «Щенок против зомби» (волна 13, ROADMAP этап 5, стиль C): Шиба в конце коридора, из тумана ковыляют
// смешные низкополигональные зомби. Шиба сам кидает игрушки (мячик, косточка, уточка) прямо перед собой — ведёшь его
// пальцем влево-вправо. Попал — зомби обнимает игрушку, над ним сердечки, он уходит другом. Дошёл до Шибы — обслюнявил:
// минус сердечко. За каждого друга копится «Гав!»: полный — громкий лай, ближние зомби становятся друзьями,
// дальние пятятся и стоят ошарашенные. Не страшно, а смешно: Nintendogs перед зомби из Resident Evil.
//
// Здесь только логика без экрана (ZombieRunScreen.swift рисует, ZombieArt — картинка):
// • раунд 50 с или до последнего сердечка; шаг симуляции фиксированный 1/60 с — один сид и те же движения пальцем
//   дают ту же игру (UI-снимки, тесты); генератор — CatchRandom (SplitMix64), как у «Лови мячик»;
// • кто, где и когда выходит — расписание от сида: промежутки 1,45 → 0,6 с к концу, мелкие быстрые чаще,
//   большие (три попадания) — с 10-й секунды;
// • награда — как у «Лови мячик» и «Блок Дуо» (CatchGame.want): base…max до par_score, убывание по номеру раунда за сутки,
//   бафф дома, свой дневной потолок и общий потолок мини-игр; настроение — ядерным play;
// • рекорд и дневные счётчики — верхним уровнем SaveFile (zombieBest, zombieDay, zombieCoins, zombieGames).

import Foundation
@preconcurrency import PetCore

// MARK: - Настройки

struct ZombieConfig: Hashable, Sendable {
    var name = "Щенок против зомби"
    var roundSeconds = 50.0
    var hearts = 3
    /// Монеты за раунд хоть с одним другом…
    var base = 5
    /// …и за par_score очков и больше.
    var max = 40
    var parScore = 500
    /// Потолок монет за игру в местные сутки…
    var dailyCap = 60
    /// …и общий на все мини-игры (с «Лови мячик» и «Блок Дуо»).
    var sharedCap = MiniGames.defaultSharedCap
    var diminishing: [CatchConfig.Step] = [.init(from: 1, x: 1), .init(from: 7, x: 0.5), .init(from: 13, x: 0.2)]

    static let shared = ZombieConfig(json: Catalog.economy() ?? .null)

    init() {}

    init(json e: JSONValue) {
        func int(_ v: JSONValue, _ d: Int) -> Int { v.double.map { Int($0) } ?? d }
        let g = e["minigames"]
        let c = g["list"]["zombie_run"]
        name = c["name"].string ?? name
        roundSeconds = Swift.max(10, c["round_seconds"].double ?? roundSeconds)
        hearts = Swift.max(1, int(c["hearts"], hearts))
        base = int(c["base"], base)
        max = Swift.max(base, int(c["max"], max))
        parScore = Swift.max(1, int(c["par_score"], parScore))
        dailyCap = Swift.max(0, int(c["daily_cap"], dailyCap))
        sharedCap = Swift.max(0, int(g["daily_cap"], sharedCap))
        diminishing = CatchConfig(json: e).diminishing
    }

    /// Те же цифры в виде CatchConfig — формула монет одна (CatchGame.want).
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

// MARK: - Зомби, игрушки, события

enum ZombieKind: Int, CaseIterable, Hashable, Sendable {
    /// Обычный: одно попадание.
    case walker
    /// Мелкий в кепке с пропеллером: быстрый, одно попадание.
    case small
    /// Большой: три попадания, медленный.
    case big

    var hp: Int { self == .big ? 3 : 1 }
    var points: Int {
        switch self {
        case .walker: return 10
        case .small: return 15
        case .big: return 30
        }
    }
    /// Единиц коридора в секунду в начале раунда (к концу на четверть быстрее).
    var speed: Double {
        switch self {
        case .walker: return 1.7
        case .small: return 2.6
        case .big: return 1.15
        }
    }
    /// Полуширина для попадания игрушкой.
    var radius: Double {
        switch self {
        case .walker: return 0.36
        case .small: return 0.28
        case .big: return 0.5
        }
    }
    /// Рост для картинки (масштаб сетки).
    var size: Double {
        switch self {
        case .walker: return 1
        case .small: return 0.7
        case .big: return 1.35
        }
    }
}

enum ZombieToy: Int, CaseIterable, Hashable, Sendable {
    case ball, bone, duck
}

struct ZombieSpawn: Hashable, Sendable {
    var t: Double
    var x: Double
    var kind: ZombieKind
    /// 0…1: своя фаза качания и шарканья.
    var wobble: Double
}

struct Zombie: Hashable, Sendable {
    enum State: Hashable, Sendable {
        case walking
        /// Ошарашен лаем до момента until.
        case stunned(until: Double)
        /// Стал другом в момент since (держит игрушку, сердечки, потом уходит к стене).
        case friend(since: Double)
        /// Добрался до Шибы и обслюнявил его в момент since; потом тоже уходит другом, но без очков.
        case hug(since: Double)
    }

    let id: Int
    let kind: ZombieKind
    var x: Double
    var z: Double
    /// Куда шаркает (x без качания).
    var baseX: Double
    var hp: Int
    var state = State.walking
    var wobble: Double
    /// Когда в него последний раз попали (вспышка).
    var hitT = -10.0
    /// Игрушка в руках у друга.
    var toy: ZombieToy? = nil
    /// Сколько прошёл (для шага на картинке).
    var walked = 0.0

    var isActive: Bool {
        switch state {
        case .walking, .stunned: return true
        case .friend, .hug: return false
        }
    }
}

struct ZombieToyShot: Hashable, Sendable {
    let id: Int
    let kind: ZombieToy
    var x: Double
    var z: Double
    let fromZ: Double
}

enum ZombieEvent: Hashable, Sendable {
    case thrown(ZombieToy)
    /// Попал, но большому мало (осталось hp).
    case hit(id: Int, left: Int)
    case friend(id: Int, kind: ZombieKind, points: Int, x: Double, z: Double)
    /// Дошёл и обслюнявил: минус сердечко.
    case hug(id: Int, heartsLeft: Int)
    /// «Гав!»: сколько стали друзьями и сколько попятились.
    case bark(friends: Int, scared: Int)
    case over
}

// MARK: - Раунд

struct ZombieRound: Sendable {
    static let dt = 1.0 / 60
    /// Полуширина дорожки (по x), стены коридора — ZombieArt.wall.
    static let lane = 1.15
    static let spawnZ = 19.0
    /// Где стоит Шиба и докуда доходит зомби, чтобы обслюнявить.
    static let hugZ = 0.55
    static let toySpeed = 12.5
    /// Докуда долетает игрушка (дальше падает в туман): зомби надо подпустить поближе.
    static let toyRange = 8.0
    static let throwEvery = 0.42
    static let puppySpeed = 7.0
    /// Друзей до полного «Гав!».
    static let barkNeed = 4
    static let barkFriendZ = 4.0
    static let barkScareZ = 13.0
    static let barkPush = 3.5
    static let stunSeconds = 1.6
    /// Сколько друг стоит с игрушкой и потом уходит.
    static let friendStay = 0.8
    static let friendGone = 2.6

    let seed: UInt64
    let seconds: Double
    let maxHearts: Int
    let schedule: [ZombieSpawn]

    private(set) var tick = 0
    private(set) var puppyX = 0.0
    private(set) var hearts: Int
    private(set) var score = 0
    private(set) var friends = 0
    private(set) var hugs = 0
    private(set) var barks = 0
    /// 0…barkNeed.
    private(set) var meter = 0
    private(set) var zombies: [Zombie] = []
    private(set) var toys: [ZombieToyShot] = []
    private(set) var thrown = 0
    /// Когда последний раз лаял (для картинки), −10 — не лаял.
    private(set) var barkT = -10.0
    /// Когда последний раз обслюнявили (тряска картинки).
    private(set) var hugT = -10.0
    private var nextSpawn = 0
    private var nextThrow = 0.35
    private var nextToyID = 0

    var t: Double { Double(tick) * Self.dt }
    var timeLeft: Double { Swift.max(0, seconds - t) }
    var isOver: Bool { hearts <= 0 || t >= seconds - 1e-9 }
    var canBark: Bool { meter >= Self.barkNeed && !isOver }
    /// Продержался до конца с сердечками.
    var survived: Bool { hearts > 0 && t >= seconds - 1e-9 }

    init(seed: UInt64, cfg: ZombieConfig = .shared) {
        self.seed = seed
        seconds = cfg.roundSeconds
        maxHearts = cfg.hearts
        hearts = cfg.hearts
        schedule = Self.layout(seed: seed, seconds: cfg.roundSeconds)
    }

    /// Промежуток между зомби в момент t: 1,45 с в начале → 0,6 с к концу.
    static func gap(at t: Double, seconds: Double) -> Double {
        let k = Swift.min(1, Swift.max(0, t / seconds))
        return 1.45 + (0.6 - 1.45) * k
    }

    /// Расписание раунда: зависит только от сида и длины.
    static func layout(seed: UInt64, seconds: Double) -> [ZombieSpawn] {
        var rng = CatchRandom(seed: seed ^ 0x5A0B_1E5_0F_D06)
        var out: [ZombieSpawn] = []
        var t = 1.0
        var lastX = 0.0
        while t < seconds - 2.5 {
            let k = t / seconds
            let r = rng.unit()
            let smallP = 0.08 + 0.22 * k
            let bigP = t >= 10 ? 0.1 + 0.08 * k : 0
            let kind: ZombieKind = r < smallP ? .small : (r < smallP + bigP ? .big : .walker)
            // Не прямо за прошлым: иначе один бросок закрывает двоих.
            var x = (rng.unit() * 2 - 1) * lane
            if abs(x - lastX) < 0.35 { x = x > 0 ? x - 0.6 : x + 0.6 }
            x = Swift.min(lane, Swift.max(-lane, x))
            lastX = x
            out.append(ZombieSpawn(t: t, x: x, kind: kind, wobble: rng.unit()))
            t += gap(at: t, seconds: seconds) * (0.75 + 0.5 * rng.unit())
        }
        return out
    }

    static func clampX(_ x: Double) -> Double { Swift.min(lane, Swift.max(-lane, x)) }

    /// Прогнать симуляцию до момента newT (шагами по 1/60 с). target — куда тянет палец (x дорожки).
    mutating func advance(to newT: Double, target: Double) -> [ZombieEvent] {
        var events: [ZombieEvent] = []
        while !isOver, Double(tick + 1) * Self.dt <= newT + 1e-9 {
            step(target: target, &events)
            if isOver { events.append(.over) }
        }
        return events
    }

    /// «Гав!», если шкала полная: ближние становятся друзьями, дальние пятятся и стоят. nil — рано.
    mutating func bark() -> ZombieEvent? {
        guard canBark else { return nil }
        meter = 0
        barks += 1
        barkT = t
        var made = 0, scared = 0
        for i in zombies.indices where zombies[i].isActive {
            let dz = zombies[i].z
            if dz <= Self.barkFriendZ {
                befriend(i, toy: nil)
                made += 1
            } else if dz <= Self.barkScareZ {
                zombies[i].z = Swift.min(Self.spawnZ, dz + Self.barkPush)
                zombies[i].state = .stunned(until: t + Self.stunSeconds)
                scared += 1
            }
        }
        // Друзья от лая шкалу не копят: иначе лай кормит сам себя.
        meter = 0
        return .bark(friends: made, scared: scared)
    }

    private mutating func step(target: Double, _ events: inout [ZombieEvent]) {
        tick += 1
        let now = t
        let dt = Self.dt
        // Шиба к пальцу.
        let goal = Self.clampX(target)
        let d = goal - puppyX
        puppyX = Self.clampX(puppyX + Swift.max(-Self.puppySpeed * dt, Swift.min(Self.puppySpeed * dt, d)))

        // Новые зомби.
        while nextSpawn < schedule.count, schedule[nextSpawn].t <= now {
            let s = schedule[nextSpawn]
            zombies.append(Zombie(id: nextSpawn, kind: s.kind, x: s.x, z: Self.spawnZ, baseX: s.x, hp: s.kind.hp,
                                  wobble: s.wobble))
            nextSpawn += 1
        }

        // Бросок.
        if now >= nextThrow {
            let kind = ZombieToy.allCases[thrown % ZombieToy.allCases.count]
            toys.append(ZombieToyShot(id: nextToyID, kind: kind, x: puppyX, z: Self.hugZ, fromZ: Self.hugZ))
            nextToyID += 1
            thrown += 1
            nextThrow = now + Self.throwEvery
            events.append(.thrown(kind))
        }

        // Зомби идут.
        let pace = 1 + 0.25 * Swift.min(1, now / seconds)
        for i in zombies.indices {
            var zb = zombies[i]
            switch zb.state {
            case .stunned(let until):
                if now >= until { zb.state = .walking }
            case .walking:
                let v = zb.kind.speed * pace * dt
                zb.z -= v
                zb.walked += v
                zb.x = Self.clampX(zb.baseX + 0.16 * sin(zb.walked * 2.4 + zb.wobble * 6.283))
                if zb.z <= Self.hugZ {
                    zb.z = Self.hugZ
                    zb.state = .hug(since: now)
                    hearts -= 1
                    hugs += 1
                    hugT = now
                    events.append(.hug(id: zb.id, heartsLeft: hearts))
                }
            case .friend(let since), .hug(let since):
                // Дошедший сначала бредёт обниматься к Шибе (только картинка: он уже не опасен).
                if case .hug = zb.state, now - since <= Self.friendStay {
                    zb.x += (puppyX - zb.x) * Swift.min(1, 5 * dt)
                }
                // Постоял — и вразвалочку к ближней стене, потом пропадает.
                if now - since > Self.friendStay {
                    let side: Double = zb.x >= 0 ? 1 : -1
                    zb.x += side * 1.1 * dt
                    zb.z += 0.5 * dt
                    zb.walked += 1.1 * dt
                }
            }
            zombies[i] = zb
        }
        zombies.removeAll { zb in
            switch zb.state {
            case .friend(let since), .hug(let since): return now - since > Self.friendGone
            default: return false
            }
        }

        // Игрушки летят и попадают.
        var keep: [ZombieToyShot] = []
        for var toy in toys {
            let prevZ = toy.z
            toy.z += Self.toySpeed * dt
            var hit: Int? = nil
            var bestZ = Double.infinity
            for (i, zb) in zombies.enumerated() where zb.isActive {
                guard abs(zb.x - toy.x) <= zb.kind.radius + 0.14 else { continue }
                guard zb.z >= prevZ - 0.25, zb.z <= toy.z + 0.25, zb.z < bestZ else { continue }
                hit = i
                bestZ = zb.z
            }
            if let i = hit {
                zombies[i].hp -= 1
                zombies[i].hitT = now
                if zombies[i].hp <= 0 {
                    let zb = zombies[i]
                    befriend(i, toy: toy.kind)
                    meter = Swift.min(Self.barkNeed, meter + 1)
                    events.append(.friend(id: zb.id, kind: zb.kind, points: zb.kind.points, x: zb.x, z: zb.z))
                } else {
                    // Большой от попадания чуть пятится.
                    zombies[i].z = Swift.min(Self.spawnZ, zombies[i].z + 0.35)
                    events.append(.hit(id: zombies[i].id, left: zombies[i].hp))
                }
                continue
            }
            if toy.z < toy.fromZ + Self.toyRange { keep.append(toy) }
        }
        toys = keep
    }

    private mutating func befriend(_ i: Int, toy: ZombieToy?) {
        zombies[i].hp = 0
        zombies[i].state = .friend(since: t)
        zombies[i].toy = toy ?? ZombieToy.allCases[zombies[i].id % ZombieToy.allCases.count]
        score += zombies[i].kind.points
        friends += 1
    }
}

// MARK: - Итог

struct ZombieResult: Hashable, Sendable {
    var score = 0
    var friends = 0
    var hugs = 0
    var hearts = 0
    var survived = false
    /// Монеты за раунд (после убывания, баффа дома и потолков).
    var coins = 0
    /// Монеты ухода за «Поиграть» (ядерное действие play).
    var careCoins = 0
    var capped = false
    var best = 0
    var isRecord = false
    var played = false
    var reason: String?

    var totalCoins: Int { coins + careCoins }
}

enum ZombieRun {
    /// Реакция в комнате после раунда — та же радость, что после «Блок Дуо» (прыжок и виляние, PetStage/PetStance).
    static let reactKind = BlockDuo.reactKind

    // MARK: автопилот (тесты, UI-снимки)

    /// Тянет Шибу под ближнего живого зомби, лает, когда шкала полная и кто-то близко.
    struct Pilot: Sendable {
        /// Отставание «реакции»: с какой дистанции начинает целиться (меньше — играет хуже).
        var sight = ZombieRound.spawnZ

        func target(_ r: ZombieRound) -> Double {
            let live = r.zombies.filter { $0.isActive && $0.z <= sight }
            guard let next = live.min(by: { arrival($0, r) < arrival($1, r) }) else { return r.puppyX }
            return next.x
        }

        /// Лает, когда кто-то уже совсем рядом или из тумана лезет толпа.
        func wantsBark(_ r: ZombieRound) -> Bool {
            guard r.canBark else { return false }
            let live = r.zombies.filter(\.isActive)
            return live.contains { $0.z < 2.4 } || live.filter { $0.z <= ZombieRound.barkScareZ }.count >= 4
        }

        private func arrival(_ z: Zombie, _ r: ZombieRound) -> Double {
            let pace = 1 + 0.25 * Swift.min(1, r.t / r.seconds)
            return (z.z - ZombieRound.hugZ) / (z.kind.speed * pace) + Double(z.hp - 1) * 0.5
        }
    }

    /// Прогнать раунд автопилотом до момента until (или до конца): кадры по 1/60 с. Детерминировано.
    static func autoplay(seed: UInt64, until: Double = .infinity, pilot: Pilot = Pilot(),
                         _ cfg: ZombieConfig = .shared) -> ZombieRound {
        var r = ZombieRound(seed: seed, cfg: cfg)
        while !r.isOver, r.t < until - 1e-9 {
            if pilot.wantsBark(r) { _ = r.bark() }
            _ = r.advance(to: r.t + ZombieRound.dt, target: pilot.target(r))
        }
        return r
    }

    // MARK: награда

    /// Сменились местные сутки — счётчики с нуля. Назад не откатываемся, как Economy.rollDay.
    static func rollDay(_ f: inout SaveFile, now: Double) {
        guard let d = DayKey.newer(than: f.zombieDay, at: now) else { return }
        f.zombieDay = d
        f.zombieCoins = 0
        f.zombieGames = 0
    }

    /// Монет за эту игру сегодня (до смены суток — 0).
    static func coinsToday(_ f: SaveFile, now: Double) -> Int {
        DayKey.today(f.zombieCoins, day: f.zombieDay, at: now)
    }

    /// Сколько монет ещё можно получить сегодня: свой потолок и общий потолок мини-игр.
    static func coinsLeft(_ f: SaveFile, now: Double, _ cfg: ZombieConfig = .shared) -> Int {
        let own = cfg.dailyCap - coinsToday(f, now: now)
        let all = cfg.sharedCap - MiniGames.coinsToday(f, now: now)
        return Swift.max(0, Swift.min(own, all))
    }

    /// Можно ли играть — как в других мини-играх: причина трюков или отказ ядра на play. nil — можно.
    static func gate(_ f: SaveFile, at t: Double) -> String? { CatchGame.gate(f, at: t) }

    /// Раунд кончился (или его бросили): рекорд, монеты с потолками, настроение через ядерный play. Пишет только в f.
    @discardableResult
    static func finish(_ r: ZombieRound, in f: inout SaveFile, now: Double, _ cfg: ZombieConfig = .shared) -> ZombieResult {
        var res = ZombieResult(score: Swift.max(0, r.score), friends: r.friends, hugs: r.hugs, hearts: r.hearts,
                               survived: r.survived)
        PetRunner.catchUp(&f, now: now)
        rollDay(&f, now: now)
        f.zombieGames += 1
        let wish = CatchGame.want(score: res.score, game: f.zombieGames, buff: CatchGame.coinsX(f), cfg.asCatch)
        // Волна 30: пёс умер, пока шёл раунд, — монет нет, как в «Лови мячик» и «Блок Дуо» (DECISIONS, волна 13).
        let got = f.pet.alive ? Swift.min(wish, coinsLeft(f, now: now, cfg)) : 0
        f.zombieCoins += got
        f.econ.wallet.coins += got
        res.coins = got
        res.capped = f.pet.alive && got < wish
        res.isRecord = res.score > f.zombieBest
        f.zombieBest = Swift.max(f.zombieBest, res.score)
        res.best = f.zombieBest
        // Ни одного друга — это не игра: настроение не трогаем.
        if res.score > 0 {
            let out = PetRunner.apply(.play, source: .app, to: &f, now: now)
            res.played = out.ok
            res.careCoins = out.ok ? out.coins : 0
            res.reason = out.ok ? nil : out.reason
        }
        return res
    }

    // MARK: тексты

    static func resultTitle(_ r: ZombieResult) -> String {
        if r.isRecord && r.score > 0 { return "Новый рекорд!" }
        if r.score == 0 { return "Зомби даже не заметили…" }
        if r.survived { return "Продержались!" }
        return "Зацеловали!"
    }

    /// «+12 монет», «На сегодня монет хватит» или nil (очков нет).
    static func rewardText(_ r: ZombieResult) -> String? {
        if r.totalCoins > 0 { return "+\(EconText.coins(r.totalCoins))" }
        if r.capped { return "На сегодня монет за игры хватит" }
        return nil
    }

    /// «3 друга», «1 друг», «5 друзей».
    static func friendsText(_ n: Int) -> String { "\(n) \(EconText.plural(n, "друг", "друга", "друзей"))" }

    /// Что Шиба скажет в комнате после раунда. Одна игра — одна фраза.
    static func shibaLine(_ r: ZombieResult) -> String {
        if r.score == 0 { return "Они такие медленные и смешные! Давай ещё?" }
        if r.isRecord { return "Гав! \(friendsText(r.friends)) за раз — рекорд!" }
        if r.survived && r.hugs == 0 { return "Ни один не обслюнявил! Я молодец?" }
        if !r.survived { return "Фу, обслюнявили всего… Но они добрые!" }
        let lines = [
            "Зомби теперь мои друзья! Уточку только жалко.",
            "Я им все игрушки раздал. Гав!",
            "Они просто хотели обниматься!",
        ]
        return lines[r.score % lines.count]
    }
}
