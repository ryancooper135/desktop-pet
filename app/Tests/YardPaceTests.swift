// Волна 36 S: темп кругов двора. Модель активного игрока из RESEARCH/20 §2 «Ориентиры темпа» — на настоящих
// функциях Yard (buyPlate, upgrade, collect, gild, move) и кривой DogLevel: за сколько дней двор достроен
// (все плиты, все станции на максимуме) на первом круге и после первого и второго переезда.
//
// Допущения (YardPacePlayer): 2 сбора в день (9:00 и 21:00), уход/игры/задания 440 🪙 и 100 опыта в сутки
// (первый день 160), монеты за уровни пса, взрослый с 35-го дня — пёс-помощник +5 % у самой доходной станции.
// Дом и капсулы вне модели: кухня считается купленной, её цена не тратится (как в таблице темпа); ярусы — тратятся.
// Чаевые выключены (≈ +3 % к сбору — модель чуть медленнее жизни). Покупки — «копит на лучшее»: всегда самая
// быстрая окупаемость (цена / прибавка 🪙/ч), постройка станции — вместе с ярусом и плитами-декором перед ней.
// Золотые таблички: к концу первого круга куплены на все 8 станций (480 ✂️ из ~800 за 15 недель), переезд их оставляет.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Игрок модели темпа.
struct YardPacePlayer {
    var collectHours: [Double] = [9, 21]
    var careCoinsPerDay = 440
    var xpPerDay = 100
    var firstDayXp = 160
    var adultDay = 35
    var helperPct = 5
    var kitchenLevel = 2
}

/// Итог круга двора.
struct YardPaceRound {
    /// Номер переезда перед кругом (0 — первый двор).
    let moves: Int
    /// Дней от начала круга (переезда) до полного двора.
    let days: Double
    /// Ставка 🪙/ч на полном дворе (слава, проценты пса, помощник, золото).
    let rate: Double
    /// Средний доход станций за круг, 🪙/ч.
    let avgRate: Double
    let dogLevel: Int
}

/// Прогон модели: круг за кругом на одном сейве-заглушке.
struct YardPaceSim {
    let cfg: YardConfig
    let dl: DogLevelConfig
    let p: YardPacePlayer
    let t0: Double = 1_760_054_400   // полночь: часы сборов — от неё
    var s = YardState()
    var coins: Int
    var xp = 0
    var yardLevel = 0
    var slot = 0                     // номер ближайшего сбора
    var lastHour = 0.0               // час последнего сделанного сбора (от полуночи первого дня)
    var earned = 0                   // монеты станций за круг

    init(cfg: YardConfig = .shared, dl: DogLevelConfig = .shared, player: YardPacePlayer = YardPacePlayer()) {
        var c = cfg
        c.tipsPerDay = 0
        self.cfg = c
        self.dl = dl
        self.p = player
        coins = EconomyConfig.shared.coinsStart   // «из грязи»: 20 🪙
    }

    var dogLevel: Int { DogLevel.level(xp: xp, dl) }
    private var hour: Double { Double(slot / p.collectHours.count) * 24 + p.collectHours[slot % p.collectHours.count] }
    private var day: Int { slot / p.collectHours.count }
    var now: Double { t0 + hour * 3600 }

    var helper: YardHelper? {
        guard day >= p.adultDay, let id = Yard.helperStation(s, cfg) else { return nil }
        return YardHelper(station: id, pct: p.helperPct)
    }

    /// Сбор: копилка, уход, опыт (и монеты за взятые уровни), потом покупки.
    mutating func step() {
        let h = Yard.collect(&s, now: now, dogLevel: dogLevel, helper: helper, cfg)
        coins += h.coins
        earned += h.coins
        coins += p.careCoinsPerDay / p.collectHours.count
        let before = dogLevel
        xp += (day == 0 ? p.firstDayXp : p.xpPerDay) / p.collectHours.count
        if dogLevel > before { for l in (before + 1)...dogLevel { coins += DogLevel.reward(l, dl).coins } }
        buy()
        lastHour = hour
        slot += 1
    }

    private struct Pick {
        let payback: Double
        let cost: Int
        let order: Int
        var tier: Int?
        var plates: [String] = []
        var upgrade: String?
    }

    private func gain(_ id: String, from lv: Int) -> Double {
        let g = s.gold.contains(id)
        return Yard.stationRate(id, level: lv + 1, dogLevel: dogLevel, helper: helper, gold: g, moves: s.moves, cfg)
            - Yard.stationRate(id, level: lv, dogLevel: dogLevel, helper: helper, gold: g, moves: s.moves, cfg)
    }

    /// Лучшая по окупаемости покупка, доступная сейчас (даже если монет пока нет — игрок на неё копит).
    private func best() -> Pick? {
        var out: [Pick] = []
        for (i, st) in cfg.stations.enumerated() {
            if let lv = s.stations[st.id] {
                guard let price = st.price(toLevel: lv + 1) else { continue }
                out.append(Pick(payback: Double(price) / gain(st.id, from: lv), cost: price, order: i, upgrade: st.id))
                continue
            }
            guard let plate = cfg.plate(st.id), dogLevel >= plate.level, let price = st.price(toLevel: 1) else { continue }
            var pick = Pick(payback: 0, cost: 0, order: i)
            var cost = 0
            if plate.tier > yardLevel {
                guard case .open(let t, let tp) = Yard.nextTier(s, yardLevel: yardLevel, dogLevel: dogLevel, cfg),
                      t == plate.tier else { continue }
                pick.tier = t
                cost += tp
            }
            let before = cfg.plates(tier: plate.tier).prefix(while: { $0.id != st.id }).filter { !s.owns($0.id) }
            guard !before.contains(where: \.isStation) else { continue }   // сначала станция раньше в ярусе
            pick.plates = before.map(\.id) + [st.id]
            cost += before.reduce(0) { $0 + $1.price } + price
            out.append(Pick(payback: Double(cost) / gain(st.id, from: 0), cost: cost, order: i,
                            tier: pick.tier, plates: pick.plates))
        }
        return out.min { ($0.payback, $0.cost, $0.order) < ($1.payback, $1.cost, $1.order) }
    }

    private mutating func buy() {
        while let b = best(), b.cost <= coins {
            if let t = b.tier { coins -= cfg.tiers[t].price; yardLevel = t }   // ярус платит HomeShop
            for id in b.plates {
                let r = Yard.buyPlate(id, &s, coins: &coins, now: now, yardLevel: yardLevel, dogLevel: dogLevel,
                                      kitchenLevel: p.kitchenLevel, helper: helper, cfg)
                guard case .ok = r else { XCTFail("плита \(id): \(r)"); return }
            }
            if let id = b.upgrade {
                let r = Yard.upgrade(id, &s, coins: &coins, now: now, dogLevel: dogLevel, helper: helper, cfg)
                guard case .upgraded = r else { XCTFail("улучшение \(id): \(r)"); return }
            }
        }
    }

    /// Круг: от текущего момента до полного двора (не дольше limitDays).
    mutating func round(limitDays: Int = 400) -> YardPaceRound? {
        let start = lastHour   // первый круг — с полуночи первого дня, следующие — с часа переезда
        earned = 0
        while !Yard.isFull(s, cfg) {
            guard lastHour - start < Double(limitDays) * 24 else { return nil }
            step()
        }
        let h = lastHour - start
        return YardPaceRound(moves: s.moves, days: h / 24, rate: Yard.rate(s, dogLevel: dogLevel, helper: helper, cfg),
                             avgRate: h > 0 ? Double(earned) / h : 0, dogLevel: dogLevel)
    }

    /// Золото на все станции (допущение модели), дождаться уровня пса для переезда и переехать.
    mutating func gildAllAndMove() {
        var shards = cfg.goldPrice * cfg.stations.count
        for st in cfg.stations where !s.gold.contains(st.id) {
            _ = Yard.gild(st.id, &s, shards: &shards, now: now, dogLevel: dogLevel, helper: helper, cfg)
        }
        while !Yard.canMove(s, dogLevel: dogLevel, cfg) { step() }
        Yard.move(&s, coins: &coins, now: now, cfg)
        yardLevel = cfg.maxTier   // ярусы остаются открытыми
    }

    /// Первый, второй и третий круг подряд.
    static func threeRounds(cfg: YardConfig = .shared) -> [YardPaceRound] {
        var sim = YardPaceSim(cfg: cfg)
        var out: [YardPaceRound] = []
        for n in 0..<3 {
            if n > 0 { sim.gildAllAndMove() }
            guard let r = sim.round() else { break }
            out.append(r)
        }
        return out
    }
}

final class YardPaceTests: XCTestCase {
    private lazy var rounds = YardPaceSim.threeRounds()

    private func fmt(_ r: YardPaceRound) -> String {
        String(format: "круг %d: %.1f дн., %.0f 🪙/ч на полном, в среднем %.0f 🪙/ч, пёс ур. %d",
               r.moves + 1, r.days, r.rate, r.avgRate, r.dogLevel)
    }

    /// Первый двор — в рамках таблицы темпа (день ~120 при старых ценах; модель без дома и капсул).
    func testFirstRoundMatchesPaceTable() throws {
        XCTAssertEqual(rounds.count, 3, "все три круга достроены за 400 дней")
        let r = try XCTUnwrap(rounds.first)
        for x in rounds { print("YardPace", fmt(x)) }
        XCTAssertEqual(r.moves, 0)
        XCTAssertGreaterThanOrEqual(r.days, 90, fmt(r))
        XCTAssertLessThanOrEqual(r.days, 125, fmt(r))
        XCTAssertGreaterThanOrEqual(r.dogLevel, 28, "мельница с ур. 28 — двор не достроить раньше")
    }

    /// Второй круг (слава ×glory_x[0], 1000 🪙, ярусы открыты, золото) — заметно быстрее первого, но не мгновенный.
    func testSecondRoundWithin45To75Days() throws {
        XCTAssertGreaterThanOrEqual(rounds.count, 2)
        let r = try XCTUnwrap(rounds.dropFirst().first)
        XCTAssertEqual(r.moves, 1)
        XCTAssertGreaterThanOrEqual(r.days, 45, fmt(r))
        XCTAssertLessThanOrEqual(r.days, 75, fmt(r))
    }

    /// Третий круг (слава ×glory_x[1]) — 35–60 дней.
    func testThirdRoundWithin35To60Days() throws {
        XCTAssertEqual(rounds.count, 3)
        let r = try XCTUnwrap(rounds.last)
        XCTAssertEqual(r.moves, 2)
        XCTAssertGreaterThanOrEqual(r.days, 35, fmt(r))
        XCTAssertLessThanOrEqual(r.days, 60, fmt(r))
    }

    /// Каждый круг быстрее прошлого, а монет в час — больше: и на полном дворе, и в среднем за круг.
    func testRoundsGetFasterAndRicher() {
        XCTAssertEqual(rounds.count, 3)
        for (a, b) in zip(rounds, rounds.dropFirst()) {
            XCTAssertLessThan(b.days, a.days, "\(fmt(b)) не быстрее \(fmt(a))")
            XCTAssertGreaterThan(b.rate, a.rate, "\(fmt(b)) / \(fmt(a))")
            XCTAssertGreaterThan(b.avgRate, a.avgRate, "\(fmt(b)) / \(fmt(a))")
        }
    }

    /// Модель стоит на настоящем переезде: после него пусто, монет не больше keepCoins, ярусы и золото на месте.
    func testMoveStartsRoundFromScratch() {
        var sim = YardPaceSim()
        _ = sim.round()
        sim.gildAllAndMove()
        XCTAssertEqual(sim.s.moves, 1)
        XCTAssertTrue(sim.s.stations.isEmpty)
        XCTAssertLessThanOrEqual(sim.coins, YardConfig.shared.moveKeepCoins)
        XCTAssertEqual(Set(sim.s.gold), Set(YardConfig.shared.stations.map(\.id)))
        XCTAssertGreaterThanOrEqual(sim.dogLevel, YardConfig.shared.moveMinDogLevel)
    }
}
