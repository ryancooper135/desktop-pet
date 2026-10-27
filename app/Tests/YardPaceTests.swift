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
//
// Волна 37 A: три профиля (RESEARCH/20 §2) — активный, средний (2 сбора, 280 🪙, 70 опыта, взрослый с 50-го дня)
// и ленивый (1 сбор в 20:00, 130 🪙, 40 опыта, взрослый с 70-го). Для каждого: день полного двора, день, когда
// открылся переезд (ожидание между ними), и за сколько дней переезд окупается против «остаться на полном дворе».

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Игрок модели темпа.
struct YardPacePlayer {
    var name = "активный"
    var collectHours: [Double] = [9, 21]
    var careCoinsPerDay = 440
    var xpPerDay = 100
    var firstDayXp = 160
    var adultDay = 35
    var helperPct = 5
    var kitchenLevel = 2

    static let active = YardPacePlayer()
    static let medium = YardPacePlayer(name: "средний", careCoinsPerDay: 280, xpPerDay: 70, firstDayXp: 130, adultDay: 50)
    static let lazy = YardPacePlayer(name: "ленивый", collectHours: [20], careCoinsPerDay: 130, xpPerDay: 40,
                                     firstDayXp: 100, adultDay: 70)
    static let all = [active, medium, lazy]
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
    /// День игры, когда двор стал полным, и когда открылся переезд.
    var fullDay: Double = 0
    var moveDay: Double = 0
    /// Сколько дней полный двор ждал переезда.
    var wait: Double { moveDay - fullDay }
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
    var spent = 0                    // монеты на двор за круг (ярусы, плиты, улучшения)

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
    var day: Int { slot / p.collectHours.count }
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
            spent += b.cost
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

    /// Круг: от текущего момента до полного двора (не дольше limitDays), потом ждать, пока откроется переезд
    /// (игрок заходит как обычно; ждать дольше limitDays — нет круга).
    mutating func round(limitDays: Int = 400) -> YardPaceRound? {
        let start = lastHour   // первый круг — с полуночи первого дня, следующие — с часа переезда
        earned = 0
        spent = 0
        while !Yard.isFull(s, cfg) {
            guard lastHour - start < Double(limitDays) * 24 else { return nil }
            step()
        }
        let h = lastHour - start
        var r = YardPaceRound(moves: s.moves, days: h / 24, rate: Yard.rate(s, dogLevel: dogLevel, helper: helper, cfg),
                              avgRate: h > 0 ? Double(earned) / h : 0, dogLevel: dogLevel, fullDay: lastHour / 24)
        while !Yard.canMove(s, dogLevel: dogLevel, cfg) {
            guard lastHour - start < Double(limitDays) * 24 else { return nil }
            step()
        }
        r.moveDay = lastHour / 24
        return r
    }

    /// Золото на все станции (допущение модели) и переезд. Возвращает, сколько монет срезано.
    @discardableResult
    mutating func gildAllAndMove() -> Int {
        gildAll()
        XCTAssertTrue(Yard.canMove(s, dogLevel: dogLevel, cfg), "переезд ещё закрыт")
        let cut = Yard.move(&s, coins: &coins, now: now, cfg)
        yardLevel = cfg.maxTier   // ярусы остаются открытыми
        return cut
    }

    mutating func gildAll() {
        var shards = cfg.goldPrice * cfg.stations.count
        for st in cfg.stations where !s.gold.contains(st.id) {
            _ = Yard.gild(st.id, &s, shards: &shards, now: now, dogLevel: dogLevel, helper: helper, cfg)
        }
    }

    /// Окупаемость переезда (волна 37 A): через сколько дней после переезда двор со славой принёс чистыми
    /// (доход станций минус всё, что ушло на новый двор) столько же, сколько дал бы старый полный двор, если остаться
    /// (его ставка — с тем же уровнем пса и помощником). Срезанные монеты не считаются: их можно потратить до
    /// переезда (дом, капсулы). nil — дольше limitDays.
    mutating func moveBreakEven(limitDays: Int = 400) -> Double? {
        gildAll()
        let stay = s
        gildAllAndMove()
        let start = lastHour
        var net = 0.0, kept = 0.0
        earned = 0
        spent = 0
        while lastHour - start < Double(limitDays) * 24 {
            let h0 = lastHour
            let e0 = earned, s0 = spent
            step()
            let stayHelper = day >= p.adultDay ? Yard.helperStation(stay, cfg).map { YardHelper(station: $0, pct: p.helperPct) } : nil
            kept += Yard.rate(stay, dogLevel: dogLevel, helper: stayHelper, cfg) * (lastHour - h0)
            net += Double(earned - e0 - (spent - s0))
            if net >= kept { return (lastHour - start) / 24 }
        }
        return nil
    }

    /// Круги подряд (первый, второй, третий...) для игрока.
    static func rounds(_ n: Int = 3, cfg: YardConfig = .shared, player: YardPacePlayer = .active) -> [YardPaceRound] {
        var sim = YardPaceSim(cfg: cfg, player: player)
        var out: [YardPaceRound] = []
        for k in 0..<n {
            if k > 0 { sim.gildAllAndMove() }
            guard let r = sim.round() else { break }
            out.append(r)
        }
        return out
    }

    static func threeRounds(cfg: YardConfig = .shared) -> [YardPaceRound] { rounds(3, cfg: cfg) }
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

/// Волна 37 A: гейт переезда для всех профилей — переезд открыт в день полного двора, круги не тянутся.
final class YardMovePaceTests: XCTestCase {
    private func fmt(_ p: YardPacePlayer, _ r: YardPaceRound) -> String {
        String(format: "%@, круг %d: %.1f дн., полный на дне %.1f, переезд с дня %.1f (ждал %.1f), пёс ур. %d",
               p.name, r.moves + 1, r.days, r.fullDay, r.moveDay, r.wait, r.dogLevel)
    }

    /// Ни один профиль не ждёт переезда после полного двора (гейт ур. 28 = мельница), все три круга укладываются.
    func testEveryProfileMovesOnFullYardDay() {
        // Первый круг: активный 90–125, средний 110–150, ленивый 190–260 (ленивого держит мельница с ур. 28).
        let first: [String: ClosedRange<Double>] = ["активный": 90...125, "средний": 110...150, "ленивый": 190...260]
        for p in YardPacePlayer.all {
            let rs = YardPaceSim.rounds(3, player: p)
            XCTAssertEqual(rs.count, 3, "\(p.name): три круга за 400 дней каждый")
            for r in rs {
                print("YardMovePace", fmt(p, r))
                XCTAssertLessThanOrEqual(r.wait, 0.5, "полный двор ждёт переезда: \(fmt(p, r))")
                XCTAssertGreaterThanOrEqual(r.dogLevel, 28, fmt(p, r))
            }
            guard rs.count == 3 else { continue }
            XCTAssertTrue(first[p.name]!.contains(rs[0].days), fmt(p, rs[0]))
            XCTAssertTrue((45...75).contains(rs[1].days), fmt(p, rs[1]))
            XCTAssertTrue((35...60).contains(rs[2].days), fmt(p, rs[2]))
        }
    }

    /// Почему не ур. 30: со старым гейтом средний ждал бы ~25 дней, ленивый ~43 на полном дворе впустую.
    func testOldGate30MadeSlowPlayersWait() throws {
        var cfg = YardConfig.shared
        cfg.moveMinDogLevel = 30
        let medium = try XCTUnwrap(YardPaceSim.rounds(1, cfg: cfg, player: .medium).first)
        let lazy = try XCTUnwrap(YardPaceSim.rounds(1, cfg: cfg, player: .lazy).first)
        print("YardMovePace гейт 30:", fmt(.medium, medium), "/", fmt(.lazy, lazy))
        XCTAssertGreaterThan(medium.wait, 15, fmt(.medium, medium))
        XCTAssertGreaterThan(lazy.wait, 30, fmt(.lazy, lazy))
    }

    /// Переезд против «остаться на полном дворе» (те же пёс и помощник): когда переехавший догоняет по монетам.
    /// Это не покупка из правила ≤ 90 дней (каждая покупка на новом круге со славой окупается быстрее) —
    /// сторож, чтобы переезд не стал заметно невыгоднее, чем сейчас (~180–200 дн.).
    func testMoveBreakEvenPerProfile() throws {
        for p in YardPacePlayer.all {
            var sim = YardPaceSim(player: p)
            _ = try XCTUnwrap(sim.round(), p.name)
            let days = try XCTUnwrap(sim.moveBreakEven(), "\(p.name): переезд не окупился за 400 дней")
            print(String(format: "YardMovePace %@: первый переезд окупается за %.0f дн.", p.name, days))
            XCTAssertLessThanOrEqual(days, 230, p.name)
        }
    }
}
