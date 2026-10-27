// Волна 33 C: двор-тайкун — ярусы, плиты, станции, копилка на 12 ч (RESEARCH/20-tycoon-design.md §1, §2).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

final class YardTests: XCTestCase {
    private let t0: Double = 1_760_054_400
    private let hour: Double = 3600
    private let cfg = YardConfig()
    /// Без чаевых — для точных сумм.
    private var calm: YardConfig { var c = YardConfig(); c.tipsPerDay = 0; return c }

    private func state(_ st: [String: Int], at t: Double) -> YardState {
        var s = YardState()
        s.stations = st
        s.t = t
        return s
    }

    /// Все плиты ярусов ниже tier и все плиты яруса до id.
    private func owned(before id: String) -> YardState {
        var s = YardState()
        for p in cfg.plates {
            if p.id == id { break }
            if p.isStation { s.stations[p.id] = 1 } else { s.plates.append(p.id) }
        }
        return s
    }

    // MARK: сейв

    func testEmptyIsNotWritten() throws {
        let f = SaveFile.fresh(now: 1_760_054_400)
        let data = try JSONEncoder().encode(f)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(obj?["yard"], "пустое поле не пишется в сейв")
        XCTAssertNoThrow(try JSONDecoder().decode(SaveFile.self, from: data))
    }

    func testRoundTripAndTolerantDecode() throws {
        var f = SaveFile.fresh(now: t0)
        f.yard.plates = ["window", "daisy"]
        f.yard.stations = ["dryer": 3]
        f.yard.bank = 12.5
        f.yard.t = t0
        f.yard.food = ["porridge": 4]
        f.yard.larder = 7
        f.yard.tipDay = 20_000
        f.yard.tipsToday = 1
        f.yard.collects = 5
        f.yard.collected = 300
        let data = try JSONEncoder().encode(f)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(obj?["yard"])
        let back = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(back.yard, f.yard)

        let junk = #"{"plates": 5, "stations": {"dryer": 2}, "bank": "много", "larder": -3}"#
        let y = try JSONDecoder().decode(YardState.self, from: Data(junk.utf8))
        XCTAssertEqual(y.plates, [])
        XCTAssertEqual(y.stations, ["dryer": 2])
        XCTAssertEqual(y.bank, 0)
        XCTAssertEqual(y.larder, 0)
        XCTAssertTrue(try JSONDecoder().decode(YardState.self, from: Data("{}".utf8)).isEmpty)
    }

    // MARK: конфиг

    func testConfigJSONMatchesDefaults() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("config/economy.json")
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        let c = YardConfig(json: json)
        XCTAssertEqual(c.tiers, cfg.tiers)
        XCTAssertEqual(c.stations, cfg.stations)
        XCTAssertEqual(c.plates, cfg.plates)
        XCTAssertEqual(c, cfg, "кусок config/economy.json = значения по умолчанию")
        XCTAssertEqual(YardConfig(json: .null), cfg)
    }

    func testStationTable() {
        let want: [String: [Int]] = [
            "dryer": [4, 6, 8, 11, 14], "bones": [6, 9, 13, 17, 22], "porridge": [9, 14, 19, 25, 32],
            "spinner": [13, 20, 27, 36, 47], "pies": [18, 27, 38, 50, 65], "photo": [24, 36, 50, 67, 86],
            "sausage": [32, 48, 67, 90, 115], "mill": [42, 63, 88, 118, 151],
        ]
        XCTAssertEqual(cfg.stations.count, 8)
        for st in cfg.stations {
            XCTAssertEqual(st.rates, want[st.id], st.id)
            XCTAssertEqual(st.maxLevel, 5)
            for l in 1...5 {
                XCTAssertEqual(Yard.rate(state([st.id: l], at: t0), dogLevel: 1, cfg), Double(want[st.id]![l - 1]), "\(st.id) ур.\(l)")
            }
        }
        XCTAssertEqual(Yard.totalStationCost(cfg), 658_550, "все станции на максимуме ≈ 659k")
        XCTAssertEqual(Yard.maxRate(cfg), 532)
        // Окупаемость улучшения = цена / прибавка ставки / 24; на максимуме — нет.
        XCTAssertEqual(Yard.paybackDays("dryer", level: 1, cfg)!, 60.0 / 2 / 24, accuracy: 1e-9)
        for st in cfg.stations { XCTAssertNil(Yard.paybackDays(st.id, level: 5, cfg)) }
        XCTAssertNil(Yard.paybackDays("nope", level: 1, cfg))
    }

    func testPlatesAndCozy() {
        XCTAssertEqual(cfg.plates.count, 24)
        XCTAssertEqual(cfg.plates.filter { !$0.isStation }.count, 16)
        XCTAssertEqual(Set(cfg.plates.map(\.id)).count, 24, "id плит уникальны")
        for st in cfg.stations { XCTAssertEqual(cfg.plate(st.id)?.price, st.prices[0], st.id) }
        XCTAssertEqual(cfg.plates.filter { !$0.isStation }.reduce(0) { $0 + $1.price }, 21_750)
        XCTAssertEqual(cfg.tiers.reduce(0) { $0 + $1.price }, 14_900)
        var s = YardState()
        s.plates = cfg.plates.filter { !$0.isStation }.map(\.id)
        s.stations = ["dryer": 5]
        XCTAssertEqual(Yard.cozy(s, cfg), 97)
        XCTAssertEqual(Yard.cozy(YardState(), cfg), 0)
    }

    func testLevelBoost() {
        let s = state(["dryer": 5, "mill": 5], at: t0)
        XCTAssertEqual(Yard.rate(s, dogLevel: 24, cfg), 165, accuracy: 1e-9)
        XCTAssertEqual(Yard.rate(s, dogLevel: 25, cfg), 165 * 1.05, accuracy: 1e-9)
        XCTAssertEqual(Yard.rate(s, dogLevel: 32, cfg), 165 * 1.09, accuracy: 1e-9)
        XCTAssertEqual(Yard.rate(s, dogLevel: 40, cfg), 165 * 1.13, accuracy: 1e-9)
        XCTAssertEqual(Yard.stationRate("mill", level: 5, dogLevel: 25, cfg), 151 * 1.05, accuracy: 1e-9)
    }

    // MARK: копилка

    func testBankCapsAt12Hours() {
        let s = state(["dryer": 1], at: t0)
        XCTAssertEqual(Yard.peek(s, now: t0 + 6 * hour, dogLevel: 1, cfg).bank, 24, accuracy: 1e-9)
        let at12 = Yard.peek(s, now: t0 + 12 * hour, dogLevel: 1, cfg).bank
        let at30 = Yard.peek(s, now: t0 + 30 * hour, dogLevel: 1, cfg).bank
        XCTAssertEqual(at12, 48, accuracy: 1e-9)
        XCTAssertEqual(at30, at12, "после 12 ч копилка не растёт")
        XCTAssertEqual(Yard.fill(s, now: t0 + 30 * hour, dogLevel: 1, cfg), 1)
        XCTAssertEqual(Yard.fill(s, now: t0 + 3 * hour, dogLevel: 1, cfg), 0.25, accuracy: 1e-9)
        XCTAssertEqual(Yard.fullAt(s, now: t0 + 3 * hour, dogLevel: 1, cfg)!, t0 + 12 * hour, accuracy: 1e-6)
        XCTAssertEqual(Yard.fullAt(s, now: t0 + 20 * hour, dogLevel: 1, cfg), t0 + 20 * hour)
        XCTAssertNil(Yard.fullAt(YardState(), now: t0, dogLevel: 1, cfg))
        // Пустой двор не копит и метку не ставит.
        var e = YardState()
        Yard.accrue(&e, now: t0, dogLevel: 1, cfg)
        XCTAssertTrue(e.isEmpty)
    }

    func testPurchaseMidWindowAccruesOldRateFirst() {
        var s = owned(before: "bones")
        s.t = t0
        var coins = 1000
        XCTAssertEqual(Yard.buyPlate("bones", &s, coins: &coins, now: t0 + 6 * hour, yardLevel: 1, dogLevel: 4,
                                     kitchenLevel: 0, cfg), .ok(price: 250))
        XCTAssertEqual(coins, 750)
        XCTAssertEqual(s.bank, 24, accuracy: 1e-9, "6 ч по старой ставке 4")
        XCTAssertEqual(s.t, t0 + 6 * hour)
        XCTAssertEqual(Yard.peek(s, now: t0 + 12 * hour, dogLevel: 4, cfg).bank, 84, accuracy: 1e-9, "24 + 6 ч × 10")
        XCTAssertEqual(Yard.peek(s, now: t0 + 40 * hour, dogLevel: 4, cfg).bank, 120, accuracy: 1e-9, "потолок 12 × 10")

        // Улучшение — так же: сперва начисление по старой ставке.
        var u = state(["dryer": 1], at: t0)
        var c2 = 100
        XCTAssertEqual(Yard.upgrade("dryer", &u, coins: &c2, now: t0 + 3 * hour, dogLevel: 1, cfg),
                       .upgraded(level: 2, price: 60))
        XCTAssertEqual(u.bank, 12, accuracy: 1e-9)
        XCTAssertEqual(Yard.peek(u, now: t0 + 5 * hour, dogLevel: 1, cfg).bank, 24, accuracy: 1e-9, "12 + 2 ч × 6")
    }

    func testFirstStationStartsTheClock() {
        var s = owned(before: "dryer")
        XCTAssertEqual(s.t, 0)
        var coins = 40
        XCTAssertEqual(Yard.buyPlate("dryer", &s, coins: &coins, now: t0, yardLevel: 0, dogLevel: 2, kitchenLevel: 0, cfg),
                       .ok(price: 40))
        XCTAssertEqual(coins, 0)
        XCTAssertEqual(s.stations, ["dryer": 1])
        XCTAssertEqual(s.t, t0)
        XCTAssertEqual(Yard.peek(s, now: t0 + hour, dogLevel: 2, cfg).bank, 4, accuracy: 1e-9)
    }

    func testClockBackGivesNothing() {
        var s = state(["dryer": 1], at: t0)
        Yard.accrue(&s, now: t0 - 5 * hour, dogLevel: 1, cfg)
        XCTAssertEqual(s.bank, 0)
        XCTAssertEqual(s.t, t0, "метка не сдвигается назад")
        let h = Yard.collect(&s, now: t0 - 5 * hour, dogLevel: 1, calm)
        XCTAssertTrue(h.isEmpty)
        XCTAssertEqual(h.coins, 0)
        XCTAssertEqual(s.collects, 0)
        // Время вернулось — копится только от метки, «назад» не засчитано вдвойне.
        XCTAssertEqual(Yard.peek(s, now: t0 + hour, dogLevel: 1, cfg).bank, 4, accuracy: 1e-9)
    }

    // MARK: плиты и ярусы

    func testPlateLocks() {
        var s = YardState()
        var coins = 100_000
        // Плита следующего яруса.
        XCTAssertEqual(Yard.buyPlate("trash", &s, coins: &coins, now: t0, yardLevel: 0, dogLevel: 30, kitchenLevel: 3, cfg),
                       .locked(.tier(1)))
        XCTAssertEqual(Yard.buyPlate("mill", &s, coins: &coins, now: t0, yardLevel: 3, dogLevel: 30, kitchenLevel: 3, cfg),
                       .locked(.tier(4)))
        // Строгий порядок внутри яруса.
        XCTAssertEqual(Yard.buyPlate("daisy", &s, coins: &coins, now: t0, yardLevel: 0, dogLevel: 30, kitchenLevel: 0, cfg),
                       .locked(.order("window")))
        XCTAssertEqual(coins, 100_000)
        XCTAssertEqual(Yard.buyPlate("window", &s, coins: &coins, now: t0, yardLevel: 0, dogLevel: 1, kitchenLevel: 0, cfg),
                       .ok(price: 10))
        XCTAssertEqual(Yard.buyPlate("window", &s, coins: &coins, now: t0, yardLevel: 0, dogLevel: 1, kitchenLevel: 0, cfg),
                       .owned)
        XCTAssertEqual(Yard.buyPlate("daisy", &s, coins: &coins, now: t0, yardLevel: 0, dogLevel: 1, kitchenLevel: 0, cfg),
                       .ok(price: 30))
        // Уровень пса.
        XCTAssertEqual(Yard.buyPlate("dryer", &s, coins: &coins, now: t0, yardLevel: 0, dogLevel: 1, kitchenLevel: 0, cfg),
                       .locked(.level(2)))
        // Кухня.
        var k = owned(before: "porridge")
        XCTAssertEqual(Yard.buyPlate("porridge", &k, coins: &coins, now: t0, yardLevel: 1, dogLevel: 7, kitchenLevel: 0, cfg),
                       .locked(.kitchen(1)))
        XCTAssertEqual(Yard.buyPlate("porridge", &k, coins: &coins, now: t0, yardLevel: 1, dogLevel: 7, kitchenLevel: 1, cfg),
                       .ok(price: 900))
        // Монет мало — копилка всё равно досчитана, плита не куплена.
        var p = owned(before: "mailbox")
        p.t = t0
        var few = 5
        XCTAssertEqual(Yard.buyPlate("mailbox", &p, coins: &few, now: t0 + hour, yardLevel: 2, dogLevel: 9, kitchenLevel: 1, cfg),
                       .noCoins(need: 395))
        XCTAssertFalse(p.owns("mailbox"))
        XCTAssertEqual(few, 5)
        XCTAssertEqual(Yard.buyPlate("nope", &p, coins: &few, now: t0, yardLevel: 4, dogLevel: 40, kitchenLevel: 3, cfg), .unknown)
        XCTAssertEqual(Yard.nextPlate(p, yardLevel: 2, cfg)?.id, "mailbox")
        XCTAssertEqual(Yard.nextPlate(p, yardLevel: 0, cfg)?.id, nil)
    }

    func testUpgradeToMax() {
        var s = YardState()
        var coins = 1_000
        XCTAssertEqual(Yard.upgrade("dryer", &s, coins: &coins, now: t0, dogLevel: 1, cfg), .notBuilt)
        XCTAssertEqual(Yard.upgrade("nope", &s, coins: &coins, now: t0, dogLevel: 1, cfg), .unknown)
        s.stations["dryer"] = 1
        s.t = t0
        for (lv, price) in [(2, 60), (3, 100), (4, 140), (5, 210)] {
            XCTAssertEqual(Yard.upgrade("dryer", &s, coins: &coins, now: t0, dogLevel: 1, cfg), .upgraded(level: lv, price: price))
        }
        XCTAssertEqual(coins, 490)
        XCTAssertEqual(Yard.upgrade("dryer", &s, coins: &coins, now: t0, dogLevel: 1, cfg), .maxed)
        var poor = 10
        s.stations["dryer"] = 2
        XCTAssertEqual(Yard.upgrade("dryer", &s, coins: &poor, now: t0, dogLevel: 1, cfg), .noCoins(need: 90))
        XCTAssertEqual(s.stations["dryer"], 2)
    }

    func testNextTier() {
        var s = YardState()
        XCTAssertEqual(Yard.nextTier(s, yardLevel: 0, dogLevel: 10, cfg), .plates(tier: 1, left: ["window", "daisy", "dryer"]))
        s = owned(before: "trash")
        XCTAssertEqual(Yard.nextTier(s, yardLevel: 0, dogLevel: 3, cfg), .level(tier: 1, need: 4))
        XCTAssertEqual(Yard.nextTier(s, yardLevel: 0, dogLevel: 4, cfg), .open(tier: 1, price: 700))
        // Сад (ур. 9): котелок каши ждёт кухню — ярус не держит.
        s = owned(before: "porridge")
        XCTAssertEqual(Yard.nextTier(s, yardLevel: 1, dogLevel: 9, cfg), .open(tier: 2, price: 1700))
        // Парк (ур. 12): прялка (ур. 10) нужна, печь (ур. 14, кухня 2) — нет.
        s = owned(before: "spinner")
        XCTAssertEqual(Yard.nextTier(s, yardLevel: 2, dogLevel: 12, cfg), .plates(tier: 3, left: ["spinner"]))
        s.stations["spinner"] = 1
        XCTAssertEqual(Yard.nextTier(s, yardLevel: 2, dogLevel: 12, cfg), .open(tier: 3, price: 3500))
        // Квартал (ур. 20): фотобудка (ур. 18) нужна.
        s = owned(before: "sign")
        s.stations["pies"] = nil
        s.stations["porridge"] = nil
        XCTAssertEqual(Yard.nextTier(s, yardLevel: 3, dogLevel: 20, cfg), .open(tier: 4, price: 9000))
        XCTAssertEqual(Yard.nextTier(s, yardLevel: 4, dogLevel: 40, cfg), .maxed)
    }

    // MARK: сбор

    func testCollectFloorsAndKeepsFraction() {
        var s = state(["dryer": 1], at: t0)
        s.bank = 10.7
        let h = Yard.collect(&s, now: t0, dogLevel: 1, cfg)
        XCTAssertEqual(h.coins, 10)
        XCTAssertEqual(s.bank, 0.7, accuracy: 1e-9)
        XCTAssertEqual(h.tip, .none, "копилка < 50 % — чаевых нет")
        XCTAssertEqual(s.tipsToday, 0)
        XCTAssertEqual(s.collects, 1)
        XCTAssertEqual(s.collected, 10)
        // Меньше монеты — сбора нет.
        let empty = Yard.collect(&s, now: t0, dogLevel: 1, cfg)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(s.collects, 1)
    }

    func testPortions() {
        var s = state(["porridge": 1, "pies": 1, "sausage": 1, "dryer": 1], at: t0)
        let h = Yard.collect(&s, now: t0 + 30 * hour, dogLevel: 1, calm)
        XCTAssertEqual(h.portions, ["porridge": 2, "pies": 2, "sausage": 3], "потолок окна 12 ч")
        XCTAssertEqual(h.pantry, 56, "2 × 5 + 2 × 8 + 3 × 10")
        XCTAssertEqual(h.coins, 756, "(9 + 18 + 32 + 4) × 12")
        // Остаток часов переходит на следующий сбор.
        var r = state(["porridge": 1], at: t0)
        let a = Yard.collect(&r, now: t0 + 9 * hour, dogLevel: 1, calm)
        XCTAssertEqual(a.portions, ["porridge": 1])
        XCTAssertEqual(r.food["porridge"]!, 3, accuracy: 1e-9)
        let b = Yard.collect(&r, now: t0 + 12 * hour, dogLevel: 1, calm)
        XCTAssertEqual(b.portions, ["porridge": 1])
    }

    func testTipsDeterministicAndOdds() {
        XCTAssertEqual(Yard.tip(day: 20_371, n: 7, dogLevel: 1, cfg), Yard.tip(day: 20_371, n: 7, dogLevel: 1, cfg))
        var base: [YardTip: Int] = [:], lucky: [YardTip: Int] = [:]
        let n = 20_000
        for i in 0..<n {
            base[Yard.tip(day: 20_000 + i / 50, n: i % 50, dogLevel: 1, cfg), default: 0] += 1
            lucky[Yard.tip(day: 20_000 + i / 50, n: i % 50, dogLevel: 15, cfg), default: 0] += 1
        }
        func pct(_ m: [YardTip: Int], _ k: YardTip) -> Double { Double(m[k] ?? 0) / Double(n) * 100 }
        XCTAssertEqual(pct(base, .none), 70, accuracy: 2)
        XCTAssertEqual(pct(base, .bonus), 20, accuracy: 2)
        XCTAssertEqual(pct(base, .ingredient), 8, accuracy: 1.5)
        XCTAssertEqual(pct(base, .ticket), 2, accuracy: 0.8)
        XCTAssertEqual(pct(lucky, .none), 55, accuracy: 2)
        XCTAssertEqual(pct(lucky, .bonus), 30, accuracy: 2)
        XCTAssertEqual(pct(lucky, .ingredient), 12, accuracy: 1.5)
        XCTAssertEqual(pct(lucky, .ticket), 3, accuracy: 0.8)
    }

    func testTipsTwicePerDayOnlyWhenHalfFull() {
        let noon = t0 + 10 * hour
        var s = state(["dryer": 1], at: noon)
        var rolls: [YardTip] = []
        for i in 0..<3 {
            s.bank = 48
            let h = Yard.collect(&s, now: noon + Double(i) * 60, dogLevel: 1, cfg)
            XCTAssertGreaterThanOrEqual(h.coins, 48)
            rolls.append(h.tip)
            switch h.tip {
            case .bonus: XCTAssertEqual(h.bonus, 5)
            case .ticket: XCTAssertEqual(h.tickets, 1)
            case .ingredient: XCTAssertEqual(h.pantry, 5)
            case .none: XCTAssertEqual(h.bonus + h.tickets, 0)
            }
        }
        XCTAssertEqual(s.tipsToday, 2, "не больше двух бросков в сутки")
        XCTAssertEqual(rolls[2], .none)
        XCTAssertEqual(s.tipDay, DayKey.of(noon))
        // Ровно повторяемо: те же сутки и номер сбора — тот же исход.
        XCTAssertEqual(rolls[0], Yard.tip(day: DayKey.of(noon), n: 1, dogLevel: 1, cfg))
        // Новые сутки — снова можно.
        s.bank = 30
        _ = Yard.collect(&s, now: noon + 24 * hour, dogLevel: 1, cfg)
        XCTAssertEqual(s.tipsToday, 1)
        // Копилка меньше половины — броска нет.
        s.bank = 20
        _ = Yard.collect(&s, now: noon + 24 * hour + 60, dogLevel: 1, cfg)
        XCTAssertEqual(s.tipsToday, 1)
    }

    func testCollectsToAfford() {
        XCTAssertEqual(Yard.collectsToAfford(250, coins: 300, rate: 4, cfg), 0)
        XCTAssertEqual(Yard.collectsToAfford(250, coins: 10, rate: 4, cfg), 5)   // 240 / 48
        XCTAssertNil(Yard.collectsToAfford(250, coins: 0, rate: 0, cfg))
    }

    // MARK: SaveFile

    func testSaveFileFlow() {
        var f = SaveFile.fresh(now: t0)
        f.econ.wallet.coins = 1_000
        let journal = f.journal.count
        XCTAssertEqual(Yard.buyPlate("window", in: &f, now: t0, dogLevel: 1, calm), .ok(price: 10))
        XCTAssertEqual(f.econ.wallet.coins, 990)
        XCTAssertEqual(f.journal.count, journal + 1)
        XCTAssertEqual(f.journal.last?.kind, "yard.buy")
        XCTAssertEqual(f.journal.last?.key, "window")
        // Ярус берётся из линии дома yard.
        XCTAssertEqual(Yard.buyPlate("trash", in: &f, now: t0, dogLevel: 10, calm), .locked(.tier(1)))
        XCTAssertEqual(f.econ.wallet.coins, 990)
        XCTAssertEqual(Yard.buyPlate("daisy", in: &f, now: t0, dogLevel: 1, calm), .ok(price: 30))
        XCTAssertEqual(Yard.buyPlate("dryer", in: &f, now: t0, dogLevel: 2, calm), .ok(price: 40))
        XCTAssertEqual(Yard.upgrade("dryer", in: &f, now: t0, dogLevel: 2, calm), .upgraded(level: 2, price: 60))
        XCTAssertEqual(f.journal.last?.kind, "yard.up")
        XCTAssertEqual(f.econ.wallet.coins, 860)

        let h = Yard.collect(in: &f, now: t0 + 12 * hour, dogLevel: 2, calm)
        XCTAssertEqual(h.coins, 72)
        XCTAssertEqual(f.econ.wallet.coins, 932)
        XCTAssertEqual(f.journal.last?.kind, "yard.collect")
        XCTAssertEqual(f.journal.last?.value, 72)
        let none = Yard.collect(in: &f, now: t0 + 12 * hour, dogLevel: 2, calm)
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(f.journal.last?.kind, "yard.collect", "пустой сбор журнал не трогает")
        XCTAssertEqual(f.journal.filter { $0.kind == "yard.collect" }.count, 1)
    }

    func testPortionsGoToPantryUpToCap() {
        var f = SaveFile.fresh(now: t0)
        f.yard.stations = ["sausage": 1]
        f.yard.t = t0
        PetRunner.catchUp(&f, now: t0 + 12 * hour)
        let before = f.pet.pantry
        let cap = Double(Cooking.pantryCap(f.pet))
        let h = Yard.collect(in: &f, now: t0 + 12 * hour, dogLevel: 1, calm)
        XCTAssertEqual(h.pantry, 30)
        XCTAssertLessThanOrEqual(f.pet.pantry, max(cap, before) + 1e-9)
        XCTAssertEqual(f.pet.pantry - before + f.yard.larder, 30, accuracy: 1e-9, "что не влезло — ждёт в larder")
    }

    // MARK: пёс-помощник (волна 34 G)

    /// Пёс встаёт у самой доходной станции; при равенстве — у той, что раньше в конфиге.
    func testHelperStationPicksBestRate() {
        XCTAssertNil(Yard.helperStation(YardState(), cfg))
        XCTAssertEqual(Yard.helperStation(state(["dryer": 5, "bones": 1], at: t0), cfg), "dryer")   // 14 > 6
        XCTAssertEqual(Yard.helperStation(state(["dryer": 1, "bones": 1], at: t0), cfg), "bones")   // 4 < 6
        XCTAssertEqual(Yard.helperStation(state(["spinner": 1, "bones": 3], at: t0), cfg), "bones") // 13 = 13
    }

    /// +5 % только своей станции и складывается с прибавкой от уровня.
    func testHelperBonusOnlyNearItsStation() {
        let s = state(["dryer": 5, "mill": 5], at: t0)
        let h = YardHelper(station: "mill", pct: 5)
        XCTAssertEqual(Yard.stationRate("mill", level: 5, dogLevel: 1, helper: h, cfg), 151 * 1.05, accuracy: 1e-9)
        XCTAssertEqual(Yard.stationRate("dryer", level: 5, dogLevel: 1, helper: h, cfg), 14, accuracy: 1e-9)
        XCTAssertEqual(Yard.rate(s, dogLevel: 1, helper: h, cfg), 14 + 151 * 1.05, accuracy: 1e-9)
        XCTAssertEqual(Yard.rate(s, dogLevel: 25, helper: h, cfg), 14 * 1.05 + 151 * 1.10, accuracy: 1e-9)
        XCTAssertEqual(Yard.rate(s, dogLevel: 1, helper: YardHelper(station: "mill", pct: 0), cfg), 165, accuracy: 1e-9)
        // Копилка с помощником полнеет быстрее, потолок — те же 12 ч по его ставке.
        let full = Yard.peek(s, now: t0 + 20 * hour, dogLevel: 1, helper: h, calm)
        XCTAssertEqual(full.bank, (14 + 151 * 1.05) * 12, accuracy: 1e-6)
    }

    /// По сейву: помогает только взрослый пёс, который дома; щенок, гуляющий и сбежавший — нет.
    func testHelperFromSave() {
        var f = SaveFile.fresh(now: t0)
        f.yard.stations = ["dryer": 2, "mill": 1]
        f.yard.t = t0
        XCTAssertNil(Yard.helper(f, cfg), "щенок не помогает")
        XCTAssertEqual(Yard.rate(f, dogLevel: 1, cfg), 6 + 42, accuracy: 1e-9)

        f.growth.points = GrowthConfig.shared.adult + 1
        XCTAssertEqual(Growth.phase(f), .adult)
        XCTAssertEqual(Yard.helper(f, cfg), YardHelper(station: "mill", pct: 5))
        XCTAssertEqual(Yard.rate(f, dogLevel: 1, cfg), 6 + 42 * 1.05, accuracy: 1e-9)

        var away = f
        away.pet.outing = Outing(from: t0 - 600, until: t0 + 3600, find: "cone")
        XCTAssertNil(Yard.helper(away, cfg), "на прогулке — не у станции")
        var gone = f
        gone.pet.alive = false
        XCTAssertNil(Yard.helper(gone, cfg), "сбежал — не помогает")

        var none = f
        none.yard.stations = [:]
        XCTAssertNil(Yard.helper(none, cfg), "станций нет")
    }

    /// Сбор по сейву со взрослым псом дома — на 5 % больше у его станции.
    func testHelperRaisesCollect() {
        var f = SaveFile.fresh(now: t0)
        f.yard.stations = ["mill": 1]
        f.yard.t = t0
        f.growth.points = GrowthConfig.shared.adult + 1
        let h = Yard.collect(in: &f, now: t0 + 12 * hour, dogLevel: 1, calm)
        XCTAssertEqual(h.coins, Int((42 * 1.05 * 12).rounded(.down)))
    }

    // MARK: золотая табличка (волна 35 M)

    /// Старый сейв без поля gold читается пустым; пустой список не пишется; с золотом — туда и обратно.
    func testGoldSaveCompat() throws {
        let old = #"{"plates": ["window"], "stations": {"dryer": 2}, "bank": 3, "t": 100}"#
        let y = try JSONDecoder().decode(YardState.self, from: Data(old.utf8))
        XCTAssertEqual(y.gold, [])
        XCTAssertEqual(y.stations, ["dryer": 2])
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(y)) as? [String: Any]
        XCTAssertNil(plain?["gold"], "без золота поле не пишется")
        XCTAssertNotNil(plain?["collected"], "остальные поля пишутся как раньше")
        var g = y
        g.gold = ["dryer"]
        let back = try JSONDecoder().decode(YardState.self, from: JSONEncoder().encode(g))
        XCTAssertEqual(back, g)
        let junk = try JSONDecoder().decode(YardState.self, from: Data(#"{"gold": 7}"#.utf8))
        XCTAssertEqual(junk.gold, [])
    }

    func testGoldRatePlusThreePercent() {
        XCTAssertEqual(cfg.goldPrice, 60)
        XCTAssertEqual(cfg.goldPct, 3)
        XCTAssertEqual(Yard.stationRate("mill", level: 1, dogLevel: 1, gold: true, cfg), 42 * 1.03, accuracy: 1e-9)
        var s = state(["mill": 1, "dryer": 1], at: t0)
        let plain = Yard.rate(s, dogLevel: 1, cfg)
        s.gold = ["mill"]
        XCTAssertEqual(Yard.rate(s, dogLevel: 1, cfg), plain + 42 * 0.03, accuracy: 1e-9, "только своей станции")
        XCTAssertEqual(Yard.stationRate("mill", in: s, dogLevel: 1, cfg), 42 * 1.03, accuracy: 1e-9)
        XCTAssertEqual(Yard.stationRate("dryer", in: s, dogLevel: 1, cfg), 4, accuracy: 1e-9)
        XCTAssertEqual(Yard.stationRate("pies", in: s, dogLevel: 1, cfg), 0, "не поставлена")
        // С помощником и уровнем — проценты складываются.
        let h = YardHelper(station: "mill", pct: 5)
        XCTAssertEqual(Yard.stationRate("mill", level: 1, dogLevel: 25, helper: h, gold: true, cfg),
                       42 * (1 + 0.05 + 0.05 + 0.03), accuracy: 1e-9)
    }

    func testGildRefusalsAndAccrual() {
        var s = state(["dryer": 1], at: t0)
        var shards = 100
        XCTAssertEqual(Yard.gild("nope", &s, shards: &shards, now: t0, dogLevel: 1, cfg), .unknown)
        XCTAssertEqual(Yard.gild("bones", &s, shards: &shards, now: t0, dogLevel: 1, cfg), .notBuilt)
        var poor = 59
        XCTAssertEqual(Yard.gild("dryer", &s, shards: &poor, now: t0, dogLevel: 1, cfg), .noShards(need: 1))
        XCTAssertEqual(poor, 59)
        XCTAssertEqual(s.gold, [])
        // Час копили по старой ставке — начислено до позолоты.
        XCTAssertEqual(Yard.gild("dryer", &s, shards: &shards, now: t0 + hour, dogLevel: 1, cfg), .ok(price: 60))
        XCTAssertEqual(shards, 40)
        XCTAssertEqual(s.gold, ["dryer"])
        XCTAssertEqual(s.bank, 4, accuracy: 1e-9)
        XCTAssertEqual(Yard.gild("dryer", &s, shards: &shards, now: t0 + hour, dogLevel: 1, cfg), .owned)
        XCTAssertEqual(shards, 40)
        Yard.accrue(&s, now: t0 + 2 * hour, dogLevel: 1, cfg)
        XCTAssertEqual(s.bank, 4 + 4 * 1.03, accuracy: 1e-9)
    }

    func testGildFromSave() {
        var f = SaveFile.fresh(now: t0)
        f.yard.stations = ["bones": 2]
        f.yard.t = t0
        f.econ.wallet.shards = 75
        let coins = f.econ.wallet.coins
        XCTAssertEqual(Yard.gild("bones", in: &f, now: t0, dogLevel: 1, cfg), .ok(price: 60))
        XCTAssertEqual(f.econ.wallet.shards, 15)
        XCTAssertEqual(f.econ.wallet.coins, coins, "монеты не трогаем")
        XCTAssertEqual(f.yard.gold, ["bones"])
        XCTAssertEqual(Yard.gild("bones", in: &f, now: t0, dogLevel: 1, cfg), .owned)
        XCTAssertEqual(f.econ.wallet.shards, 15)
    }
}
