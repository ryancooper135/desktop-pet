// Мини-игра «Лови мячик»: сверху падают мячики и косточки, хозяин водит миской внизу и ловит.
// Раунд — 30 с, падает всё чаще и быстрее; три промаха — раунд кончается раньше.
//
// Здесь только логика без экрана (CatchGameScreen.swift рисует):
// • падение детерминировано от сида и времени: один сид — одна и та же раскладка мячиков (UI-тесты, тесты);
// • счёт: мячик 1, косточка 2;
// • награда: монеты ∝ очкам (base…max до par_score), с убыванием по числу раундов за сутки и дневным потолком
//   (minigames.list.catch и minigames.diminishing в config/economy.json — тот же приём «min(хочу, потолок − уже)»,
//   что у Economy для ухода и шагов);
// • настроение — ядерным действием play (PetRunner.apply): +fun и −energy по minigames.fun_gain/energy_cost,
//   и обычные монеты ухода за «Поиграть». Своего правила ядру не придумываем;
// • рекорд и дневные счётчики — верхним уровнем SaveFile (catchBest, catchDay, catchCoins, catchGames).
//
// Поле — единичный квадрат: x 0…1 слева направо, y 0…1 сверху вниз. Экран сам растягивает его на свой размер.

import Foundation
@preconcurrency import PetCore

// MARK: - Настройки

struct CatchConfig: Hashable, Sendable {
    struct Step: Hashable, Sendable {
        /// С какого по счёту раунда за сутки (с 1).
        var from: Int
        var x: Double
    }

    var name = "Лови мячик"
    var roundSeconds = 30.0
    var maxMisses = 3
    /// Монеты за раунд хоть с одним пойманным…
    var base = 5
    /// …и за par_score очков и больше.
    var max = 30
    var parScore = 40
    /// Потолок монет за игру в местные сутки.
    var dailyCap = 60
    var diminishing: [Step] = [Step(from: 1, x: 1), Step(from: 7, x: 0.5), Step(from: 13, x: 0.2)]

    static let shared = CatchConfig(json: Catalog.economy() ?? .null)

    init() {}

    init(json e: JSONValue) {
        func int(_ v: JSONValue, _ d: Int) -> Int { v.double.map { Int($0) } ?? d }
        let g = e["minigames"]
        let c = g["list"]["catch"]
        name = c["name"].string ?? name
        roundSeconds = c["round_seconds"].double ?? roundSeconds
        maxMisses = Swift.max(1, int(c["misses"], maxMisses))
        base = int(c["base"], base)
        max = Swift.max(base, int(c["max"], max))
        parScore = Swift.max(1, int(c["par_score"], parScore))
        dailyCap = int(c["daily_cap"], dailyCap)
        let steps = g["diminishing"].array.compactMap { s -> Step? in
            guard let from = s["games_from"].double, let x = s["x"].double else { return nil }
            return Step(from: Int(from), x: x)
        }
        if !steps.isEmpty { diminishing = steps.sorted { $0.from < $1.from } }
    }

    /// Множитель для n-го раунда за сутки (n с 1).
    func factor(game n: Int) -> Double {
        diminishing.last(where: { $0.from <= n })?.x ?? 1
    }
}

// MARK: - Падение

enum CatchKind: String, Hashable, Sendable {
    case ball, bone

    var points: Int { self == .bone ? 2 : 1 }
}

/// Один мячик или косточка: где появился, когда и с какой скоростью падает.
struct CatchDrop: Hashable, Sendable {
    let index: Int
    let kind: CatchKind
    let x: Double
    let spawnT: Double
    /// Высот поля в секунду.
    let speed: Double

    /// Сверху за краем поля…
    static let startY = -CatchGame.radius
    /// …до линии миски: здесь решается, поймал или нет.
    var landT: Double { spawnT + (CatchGame.catchY - Self.startY) / speed }

    func y(at t: Double) -> Double { Self.startY + speed * (t - spawnT) }
}

enum CatchEvent: Hashable, Sendable {
    case caught(CatchDrop)
    case missed(CatchDrop)
}

/// Генератор SplitMix64: на всех платформах одна и та же последовательность.
struct CatchRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ≤ x < 1.
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

/// Раунд: раскладка от сида, время, счёт и промахи. Двигает его экран (advance), миску водит палец.
struct CatchRound: Sendable {
    enum Status: Hashable, Sendable { case falling, caught, missed }

    let seed: UInt64
    let seconds: Double
    let maxMisses: Int
    let drops: [CatchDrop]
    private(set) var status: [Status]
    private(set) var t = 0.0
    private(set) var score = 0
    private(set) var caught = 0
    private(set) var missed = 0

    init(seed: UInt64, cfg: CatchConfig = .shared) {
        self.seed = seed
        seconds = cfg.roundSeconds
        maxMisses = cfg.maxMisses
        drops = CatchGame.layout(seed: seed, seconds: cfg.roundSeconds)
        status = Array(repeating: .falling, count: drops.count)
    }

    var isOver: Bool { t >= seconds || missed >= maxMisses }
    var timeLeft: Double { Swift.max(0, seconds - t) }
    /// 0 в начале раунда, 1 в конце: темп падения.
    var pace: Double { Swift.min(1, t / seconds) }

    /// Что сейчас на поле.
    var visible: [CatchDrop] {
        drops.indices.compactMap { i in
            let d = drops[i]
            guard status[i] == .falling, d.spawnT <= t, d.landT > t else { return nil }
            return d
        }
    }

    /// Время вперёд до to; миска сейчас в bowlX. Всё, что долетело до линии миски, — поймано или мимо.
    /// Третий промах останавливает раунд на нём: дальше ничего не считается.
    @discardableResult
    mutating func advance(to newT: Double, bowlX: Double) -> [CatchEvent] {
        guard !isOver, newT > t else { return [] }
        let end = Swift.min(newT, seconds)
        var events: [CatchEvent] = []
        for i in drops.indices where status[i] == .falling {
            let d = drops[i]
            if d.spawnT > end { break }
            guard d.landT <= end else { continue }
            if abs(d.x - bowlX) <= CatchGame.reach {
                status[i] = .caught
                caught += 1
                score += d.kind.points
                events.append(.caught(d))
            } else {
                status[i] = .missed
                missed += 1
                events.append(.missed(d))
                if missed >= maxMisses {
                    t = d.landT
                    return events
                }
            }
        }
        t = end
        return events
    }
}

// MARK: - Игра

/// Итог раунда после записи в сейв.
struct CatchResult: Hashable, Sendable {
    var score = 0
    var caught = 0
    var missed = 0
    /// Монеты за игру (после убывания и потолка).
    var coins = 0
    /// Монеты ухода за «Поиграть» (ядерное действие play, потолок ухода).
    var careCoins = 0
    /// Хотели больше, но упёрлись в дневной потолок игры.
    var capped = false
    var best = 0
    var isRecord = false
    /// Ядро засчитало игру (настроение выросло).
    var played = false
    /// Почему ядро не приняло игру (уснул, пока играли); nil — приняло или очков нет.
    var reason: String?

    var totalCoins: Int { coins + careCoins }
}

enum CatchGame {
    /// Линия миски (верх миски) по высоте поля.
    static let catchY = 0.86
    /// Полуширина миски по полю.
    static let bowlHalf = 0.11
    /// Радиус мячика.
    static let radius = 0.045
    /// Насколько далеко от центра миски мячик ещё ловится: полуширина и полмячика.
    static let reach = bowlHalf + radius * 0.6
    static let bowlRange: ClosedRange<Double> = bowlHalf...(1 - bowlHalf)
    /// Доля косточек.
    static let boneShare = 0.22

    /// Сколько ждать между мячиками в момент t: от 0,95 с в начале до 0,45 с в конце раунда.
    static func gap(at t: Double, seconds: Double) -> Double {
        lerp(0.95, 0.45, Swift.min(1, Swift.max(0, t / seconds)))
    }

    /// Скорость падения в момент появления: от 0,45 до 1 высоты поля в секунду.
    static func speed(at t: Double, seconds: Double) -> Double {
        lerp(0.45, 1.0, Swift.min(1, Swift.max(0, t / seconds)))
    }

    /// Раскладка раунда: всё, что появится до конца. Соседние мячики не дальше полполя друг от друга —
    /// чтобы успеть добежать и в конце раунда.
    static func layout(seed: UInt64, seconds: Double) -> [CatchDrop] {
        var rng = CatchRandom(seed: seed)
        var out: [CatchDrop] = []
        var t = 0.6
        var x = 0.5
        while t < seconds {
            let jump = (rng.unit() * 2 - 1) * 0.5
            x = Swift.min(0.92, Swift.max(0.08, x + jump))
            let kind: CatchKind = rng.unit() < boneShare ? .bone : .ball
            out.append(CatchDrop(index: out.count, kind: kind, x: x, spawnT: t, speed: speed(at: t, seconds: seconds)))
            t += gap(at: t, seconds: seconds) * (0.85 + 0.3 * rng.unit())
        }
        return out
    }

    static func clampBowl(_ x: Double) -> Double { Swift.min(bowlRange.upperBound, Swift.max(bowlRange.lowerBound, x)) }

    /// Можно ли играть: та же причина, что у трюков (умер, гуляет, моется, спит, беда), плюс отказ ядра
    /// на play (нет сил). nil — можно.
    static func gate(_ f: SaveFile, at t: Double) -> String? {
        if let r = Tricks.gate(f, at: t) { return r }
        var s = PetRunner.peek(f, at: t)
        let res = PetEngine.act(&s, Catalog.rules, PetRunner.owner(f, at: t), .play)
        return res.ok ? nil : (res.reason ?? "unavailable")
    }

    // MARK: награда

    /// Сколько монет хочется за раунд: 0 без очков; base…max пропорционально очкам до par_score;
    /// game — номер раунда за сутки (с 1), с него убывание.
    static func want(score: Int, game: Int, _ cfg: CatchConfig = .shared) -> Int {
        guard score > 0 else { return 0 }
        let share = Double(Swift.min(score, cfg.parScore)) / Double(cfg.parScore)
        let raw = Double(cfg.base) + Double(cfg.max - cfg.base) * share
        return Swift.max(0, Int((raw * cfg.factor(game: game)).rounded()))
    }

    /// Сменились местные сутки — счётчики игры с нуля. Назад не откатываемся, как Economy.rollDay.
    static func rollDay(_ f: inout SaveFile, now: Double) {
        let d = Economy.day(now)
        guard d > f.catchDay else { return }
        f.catchDay = d
        f.catchCoins = 0
        f.catchGames = 0
    }

    /// Сколько монет ещё можно получить сегодня.
    static func coinsLeft(_ f: SaveFile, now: Double, _ cfg: CatchConfig = .shared) -> Int {
        let used = Economy.day(now) > f.catchDay ? 0 : f.catchCoins
        return Swift.max(0, cfg.dailyCap - used)
    }

    /// Раунд кончился: рекорд, монеты с потолком, настроение через ядерный play. Пишет только в f.
    @discardableResult
    static func finish(score: Int, caught: Int = 0, missed: Int = 0, in f: inout SaveFile, now: Double,
                       _ cfg: CatchConfig = .shared) -> CatchResult {
        var r = CatchResult(score: Swift.max(0, score), caught: caught, missed: missed)
        PetRunner.catchUp(&f, now: now)
        rollDay(&f, now: now)
        f.catchGames += 1
        let wish = want(score: r.score, game: f.catchGames, cfg)
        let got = Swift.min(wish, Swift.max(0, cfg.dailyCap - f.catchCoins))
        f.catchCoins += got
        f.econ.wallet.coins += got
        r.coins = got
        r.capped = got < wish
        r.isRecord = r.score > f.catchBest
        f.catchBest = Swift.max(f.catchBest, r.score)
        r.best = f.catchBest
        // Ни одного пойманного — это не игра: настроение не трогаем.
        if r.score > 0 {
            let out = PetRunner.apply(.play, source: .app, to: &f, now: now)
            r.played = out.ok
            r.careCoins = out.ok ? out.coins : 0
            r.reason = out.ok ? nil : out.reason
        }
        return r
    }

    // MARK: автопилот (тесты, UI-снимки)

    /// Миска сама бежит к ближайшему падающему мячику со скоростью speed полей в секунду.
    struct Pilot: Sendable {
        var x = 0.5
        var speed = 1.4

        mutating func step(_ round: CatchRound, dt: Double) -> Double {
            let target = round.visible.min(by: { $0.landT < $1.landT })?.x ?? x
            let d = target - x
            let move = Swift.min(abs(d), speed * dt)
            x = CatchGame.clampBowl(x + (d < 0 ? -move : move))
            return x
        }
    }

    /// Прогнать раунд автопилотом до момента until (или до конца): кадры по 1/60 с. Детерминировано.
    static func autoplay(seed: UInt64, until: Double = .infinity, speed: Double = 1.4,
                         _ cfg: CatchConfig = .shared) -> (round: CatchRound, bowlX: Double) {
        var round = CatchRound(seed: seed, cfg: cfg)
        var pilot = Pilot(speed: speed)
        let dt = 1.0 / 60
        var frame = 0
        while !round.isOver {
            frame += 1
            let t = Swift.min(Double(frame) * dt, until)
            let x = pilot.step(round, dt: dt)
            round.advance(to: t, bowlX: x)
            if t >= until { break }
        }
        return (round, pilot.x)
    }

    // MARK: тексты

    static func resultTitle(_ r: CatchResult) -> String {
        if r.isRecord && r.score > 0 { return "Новый рекорд!" }
        if r.score == 0 { return "Ни одного… Ещё разок?" }
        if r.missed >= CatchConfig.shared.maxMisses { return "Ой, упустили!" }
        return "Время вышло!"
    }

    /// «+12 монет», «На сегодня монет хватит» или nil (очков нет).
    static func rewardText(_ r: CatchResult) -> String? {
        if r.totalCoins > 0 { return "+\(EconText.coins(r.totalCoins))" }
        if r.capped { return "На сегодня монет за игру хватит" }
        return nil
    }

    private static func lerp(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * k }
}
