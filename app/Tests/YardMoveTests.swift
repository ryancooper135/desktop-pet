// Волна 36 P: переезд двора и слава (Yard.canMove, Yard.move, Yard.glory, Yard.district, YardText переезда).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

final class YardMoveTests: XCTestCase {
    private let t0: Double = 1_760_054_400
    private let hour: Double = 3600
    private let cfg = YardConfig()
    /// Без чаевых — для точных сумм.
    private var calm: YardConfig { var c = YardConfig(); c.tipsPerDay = 0; return c }

    /// Полный двор: все плиты-декор, все станции на максимуме.
    private func full(at t: Double = 0) -> YardState {
        var s = YardState()
        for p in cfg.plates where !p.isStation { s.plates.append(p.id) }
        for st in cfg.stations { s.stations[st.id] = st.maxLevel }
        s.t = t
        return s
    }

    private func fullSave(coins: Int, dogLevel: Int = 30) -> SaveFile {
        var f = SaveFile.fresh(now: t0)
        f.yard = full(at: t0)
        f.yard.bank = 500
        f.yard.food = ["pies": 3]
        f.yard.larder = 4
        f.yard.gold = ["mill"]
        f.yard.collects = 9
        f.yard.collected = 12_345
        f.pet.home[.yard] = cfg.maxTier
        f.pet.home[.kitchen] = 2
        f.econ.wallet.coins = coins
        f.econ.wallet.shards = 77
        f.econ.wallet.tickets = 3
        return f
    }

    // MARK: конфиг

    func testConfigDefaults() {
        XCTAssertEqual(cfg.moveMinDogLevel, 30)
        XCTAssertEqual(cfg.moveKeepCoins, 1000)
        XCTAssertEqual(cfg.gloryX, [1.5, 2, 2.5])
        var e: [String: JSONValue] = [:]
        e["yard"] = .object(["move": .object(["min_dog_level": .number(25), "keep_coins": .number(500),
                                              "glory_x": .array([.number(1.2), .number(0.5)])])])
        let c = YardConfig(json: .object(e))
        XCTAssertEqual(c.moveMinDogLevel, 25)
        XCTAssertEqual(c.moveKeepCoins, 500)
        XCTAssertEqual(c.gloryX, [1.2, 1], "слава не меньше ×1")
    }

    // MARK: условие

    func testCanMoveNeedsLevelAndFullYard() {
        let s = full()
        XCTAssertTrue(Yard.isFull(s, cfg))
        XCTAssertEqual(Yard.moveLeft(s, cfg), 0)
        XCTAssertTrue(Yard.canMove(s, dogLevel: 30, cfg))
        XCTAssertTrue(Yard.canMove(s, dogLevel: 40, cfg))
        XCTAssertFalse(Yard.canMove(s, dogLevel: 29, cfg), "пёс мал")

        var one = s
        one.stations["mill"] = 4
        XCTAssertFalse(Yard.canMove(one, dogLevel: 30, cfg), "мельница не на максимуме")
        XCTAssertEqual(Yard.moveLeft(one, cfg), 1)
        var decor = s
        decor.plates.removeAll { $0 == "telescope" }
        XCTAssertFalse(Yard.canMove(decor, dogLevel: 30, cfg), "телескоп не куплен")
        XCTAssertEqual(Yard.moveLeft(decor, cfg), 1)
        XCTAssertFalse(Yard.canMove(YardState(), dogLevel: 99, cfg))
        XCTAssertEqual(Yard.moveLeft(YardState(), cfg), cfg.plates.filter { !$0.isStation }.count + cfg.stations.count * 5)
    }

    // MARK: сброс

    func testMoveResetsYardKeepsTheRest() {
        var f = fullSave(coins: 5_000)
        let pet = f.pet, level = f.level, cards = f.cards
        let journal = f.journal.count
        let r = Yard.move(in: &f, now: t0 + hour, dogLevel: 30, calm)
        XCTAssertEqual(r, .ok(moves: 1, cut: 4_000))
        // Заново
        XCTAssertEqual(f.yard.plates, [])
        XCTAssertEqual(f.yard.stations, [:])
        XCTAssertEqual(f.yard.bank, 0)
        XCTAssertEqual(f.yard.t, 0)
        XCTAssertEqual(f.yard.food, [:])
        XCTAssertEqual(f.yard.larder, 0)
        XCTAssertEqual(f.econ.wallet.coins, 1_000, "монеты сверх 1000 срезаны")
        // Остаётся
        XCTAssertEqual(f.yard.moves, 1)
        XCTAssertEqual(f.yard.gold, ["mill"], "золото куплено за ✂️ — остаётся за станцией")
        XCTAssertEqual(f.yard.collects, 9)
        XCTAssertEqual(f.yard.collected, 12_345)
        XCTAssertEqual(f.econ.wallet.shards, 77, "✂️ не трогаются")
        XCTAssertEqual(f.econ.wallet.tickets, 3)
        XCTAssertEqual(f.pet, pet, "Шиба, рост, вещи, дом (в том числе ярус двора) — как были")
        XCTAssertEqual(f.level, level, "уровень пса не трогается")
        XCTAssertEqual(f.cards, cards, "альбом не трогается")
        XCTAssertEqual(HomeShop.level(f, .yard), cfg.maxTier)
        // Журнал
        XCTAssertEqual(f.journal.count, journal + 1)
        XCTAssertEqual(f.journal.last?.kind, "yard.move")
        XCTAssertEqual(f.journal.last?.key, "4000")
        XCTAssertEqual(f.journal.last?.value, 1)
    }

    func testCoinsBelowKeepAreNotTouched() {
        var s = full()
        var coins = 640
        XCTAssertEqual(Yard.move(&s, coins: &coins, now: t0, cfg), 0)
        XCTAssertEqual(coins, 640, "меньше 1000 — не добавляем и не режем")
        var c2 = 1_000
        var s2 = full()
        XCTAssertEqual(Yard.move(&s2, coins: &c2, now: t0, cfg), 0)
        XCTAssertEqual(c2, 1_000)
    }

    func testMoveRefusedWithoutGate() {
        var f = fullSave(coins: 5_000)
        let before = f
        XCTAssertEqual(Yard.move(in: &f, now: t0, dogLevel: 29, cfg), .level(need: 30))
        XCTAssertEqual(f.yard, before.yard, "отказ ничего не меняет")
        XCTAssertEqual(f.econ.wallet, before.econ.wallet)
        XCTAssertEqual(f.journal.count, before.journal.count)
        f.yard.stations["dryer"] = 3
        let half = f
        XCTAssertEqual(Yard.move(in: &f, now: t0, dogLevel: 35, cfg), .notFull(left: 2))
        XCTAssertEqual(f.yard, half.yard)
        XCTAssertEqual(f.econ.wallet, half.econ.wallet)
    }

    func testSecondMoveAfterRebuild() {
        var f = fullSave(coins: 3_000)
        XCTAssertEqual(Yard.move(in: &f, now: t0, dogLevel: 30, cfg), .ok(moves: 1, cut: 2_000))
        XCTAssertFalse(Yard.canMove(f.yard, dogLevel: 30, cfg), "сразу после переезда двор пустой")
        // Ярус двора остался: все плиты сразу на открытых ярусах, кнопки «следующий ярус» нет.
        XCTAssertEqual(Yard.nextTier(f.yard, yardLevel: HomeShop.level(f, .yard), dogLevel: 30, cfg), .maxed)
        XCTAssertEqual(Yard.nextPlate(f.yard, yardLevel: HomeShop.level(f, .yard), cfg)?.id, "window")
        f.yard = { var s = full(at: t0); s.moves = 1; s.gold = f.yard.gold; return s }()
        f.econ.wallet.coins = 900
        XCTAssertEqual(Yard.move(in: &f, now: t0, dogLevel: 30, cfg), .ok(moves: 2, cut: 0))
        XCTAssertEqual(f.yard.moves, 2)
        XCTAssertEqual(f.econ.wallet.coins, 900)
    }

    // MARK: слава

    func testGloryLadder() {
        XCTAssertEqual(Yard.glory(moves: 0, cfg), 1)
        XCTAssertEqual(Yard.glory(moves: 1, cfg), 1.5)
        XCTAssertEqual(Yard.glory(moves: 2, cfg), 2)
        XCTAssertEqual(Yard.glory(moves: 3, cfg), 2.5)
        XCTAssertEqual(Yard.glory(moves: 7, cfg), 2.5, "дальше — последняя ступень")
        XCTAssertEqual(Yard.glory(moves: -1, cfg), 1)
        XCTAssertEqual(Yard.gloryStars(moves: 0, cfg), 0)
        XCTAssertEqual(Yard.gloryStars(moves: 2, cfg), 2)
        XCTAssertEqual(Yard.gloryStars(moves: 9, cfg), 3, "звёзд не больше трёх")
    }

    func testGloryInRateAndBank() {
        var s = YardState()
        s.stations = ["mill": 1, "dryer": 2]
        s.gold = ["mill"]
        s.t = t0
        let base = Yard.rate(s, dogLevel: 30, cfg)
        XCTAssertEqual(Yard.stationRate("mill", level: 1, dogLevel: 1, gold: true, moves: 1, cfg), 42 * 1.03 * 1.5,
                       accuracy: 1e-9, "слава — поверх процентов")
        for m in 1...4 {
            var g = s
            g.moves = m
            let x = Yard.glory(moves: m, cfg)
            XCTAssertEqual(Yard.rate(g, dogLevel: 30, cfg), base * x, accuracy: 1e-9, "переездов: \(m)")
            XCTAssertEqual(Yard.stationRate("dryer", in: g, dogLevel: 30, cfg),
                           Yard.stationRate("dryer", in: s, dogLevel: 30, cfg) * x, accuracy: 1e-9)
            // Копилка: за 6 ч накопила в x раз больше, потолок тоже в x раз выше — «полная в» не сдвигается.
            let a = Yard.peek(s, now: t0 + 6 * hour, dogLevel: 30, cfg)
            let b = Yard.peek(g, now: t0 + 6 * hour, dogLevel: 30, cfg)
            XCTAssertEqual(b.bank, a.bank * x, accuracy: 1e-6)
            XCTAssertEqual(Yard.fullAt(g, now: t0, dogLevel: 30, cfg)!, Yard.fullAt(s, now: t0, dogLevel: 30, cfg)!, accuracy: 1e-6)
        }
        // Сбор со славой: монет в 1,5 раза больше.
        var g = s
        g.moves = 1
        var plain = s
        let hs = Yard.collect(&plain, now: t0 + 24 * hour, dogLevel: 30, calm)
        let hg = Yard.collect(&g, now: t0 + 24 * hour, dogLevel: 30, calm)
        XCTAssertEqual(Double(hg.coins), Double(hs.coins) * 1.5, accuracy: 1.01)
        // «≈ N сборов» — меньше со славой.
        let r0 = Yard.rate(s, dogLevel: 30, cfg), r1 = Yard.rate({ var c = s; c.moves = 1; return c }(), dogLevel: 30, cfg)
        XCTAssertLessThan(Yard.collectsToAfford(50_000, coins: 0, rate: r1, cfg)!,
                          Yard.collectsToAfford(50_000, coins: 0, rate: r0, cfg)!)
    }

    func testGloryOnSaveFileWrappers() {
        var f = SaveFile.fresh(now: t0)
        f.yard.stations = ["dryer": 1]
        f.yard.t = t0
        let base = Yard.rate(f, dogLevel: 1, cfg)
        f.yard.moves = 2
        XCTAssertEqual(Yard.rate(f, dogLevel: 1, cfg), base * 2, accuracy: 1e-9, "островок и виджет берут ставку отсюда")
    }

    /// Окупаемость со славой только короче, и всё так же ≤ 90 дней.
    func testPaybackWithGloryOnlyShorter() throws {
        for st in cfg.stations {
            for l in 1..<st.maxLevel {
                let d0 = try XCTUnwrap(Yard.paybackDays(st.id, level: l, cfg))
                XCTAssertEqual(Yard.paybackDays(st.id, level: l, moves: 0, cfg), d0)
                for m in 1...4 {
                    let d = try XCTUnwrap(Yard.paybackDays(st.id, level: l, moves: m, cfg))
                    XCTAssertLessThan(d, d0, "\(st.id) ур. \(l), переездов \(m)")
                    XCTAssertEqual(d, d0 / Yard.glory(moves: m, cfg), accuracy: 1e-9)
                    XCTAssertLessThanOrEqual(d, 90)
                }
            }
            XCTAssertNil(Yard.paybackDays(st.id, level: st.maxLevel, moves: 2, cfg))
        }
    }

    // MARK: районы

    func testDistrictCycle() {
        XCTAssertEqual((0...8).map { Yard.district(moves: $0) }, [0, 1, 2, 3, 1, 2, 3, 1, 2])
        XCTAssertEqual(Yard.district(moves: -3), 0)
    }

    // MARK: сейв

    func testOldSaveWithoutMovesDecodes() throws {
        let old = #"{"plates": ["window"], "stations": {"dryer": 2}, "bank": 3, "t": 100, "gold": ["dryer"]}"#
        let y = try JSONDecoder().decode(YardState.self, from: Data(old.utf8))
        XCTAssertEqual(y.moves, 0)
        XCTAssertEqual(y.gold, ["dryer"])
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(y)) as? [String: Any]
        XCTAssertNil(plain?["moves"], "без переездов поле не пишется")
        var m = y
        m.moves = 3
        let back = try JSONDecoder().decode(YardState.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(back, m)
        XCTAssertEqual(back.moves, 3)
        let junk = try JSONDecoder().decode(YardState.self, from: Data(#"{"moves": "x"}"#.utf8))
        XCTAssertEqual(junk.moves, 0)
        let neg = try JSONDecoder().decode(YardState.self, from: Data(#"{"moves": -2}"#.utf8))
        XCTAssertEqual(neg.moves, 0)
        // Двор после переезда пустой, но не «пустой» для сейва: moves пишется.
        var moved = YardState()
        moved.moves = 1
        XCTAssertFalse(moved.isEmpty)
    }

    func testMovedSaveRoundTrip() throws {
        var f = fullSave(coins: 2_000)
        Yard.move(in: &f, now: t0, dogLevel: 30, cfg)
        let back = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back.yard.moves, 1)
        XCTAssertEqual(back.yard, f.yard)
    }

    // MARK: тексты

    func testMoveTexts() {
        XCTAssertEqual(YardText.times(1.5), "×1,5")
        XCTAssertEqual(YardText.times(2), "×2")
        XCTAssertEqual(YardText.times(2.5), "×2,5")
        XCTAssertEqual(YardText.gloryStars(moves: 0, cfg), "")
        XCTAssertEqual(YardText.gloryStars(moves: 1, cfg), "★")
        XCTAssertEqual(YardText.gloryStars(moves: 5, cfg), "★★★")
        XCTAssertEqual(YardText.gloryLabel(moves: 2, cfg), "Слава двора ×2")
        XCTAssertEqual(YardText.moveTitle, "Переезд двора")
        XCTAssertEqual(YardText.moveConfirm(moves: 0, cfg), [
            "Останется: Шиба, его уровень и рост, вещи, дом, ✂️, альбом, 1000 🪙",
            "Начнётся заново: плиты, станции, копилка, монеты сверх 1000",
            "Слава двора ×1,5 к доходу станций навсегда",
        ])
        XCTAssertEqual(YardText.moveConfirm(moves: 1, cfg).last, "Слава двора ×2 к доходу станций навсегда")
        XCTAssertEqual(YardText.moveConfirm(moves: 3, cfg).last, "Слава двора ×2,5 к доходу станций навсегда")
        XCTAssertEqual(YardText.moveLine(moves: 0, cfg), "Двор достроен. Новый район — «Зимний квартал», слава ×1,5")
        XCTAssertEqual(YardText.moved(moves: 1, cfg), "Переехали: «Зимний квартал» · слава ×1,5")
        XCTAssertEqual(YardText.moved(moves: 4, cfg), "Переехали: «Зимний квартал» · слава ×2,5")
        XCTAssertEqual((0...3).map(YardText.districtName), ["Улица", "Зимний квартал", "У реки", "На крыше"])
        XCTAssertNil(YardText.moveRefuse(.ok(moves: 1, cut: 0)))
        XCTAssertEqual(YardText.moveRefuse(.level(need: 30)), "Переезд — с ур. 30 пса")
        XCTAssertEqual(YardText.moveRefuse(.notFull(left: 3)), "Сначала дострой двор — осталось 3")
        for line in YardText.moveConfirm(moves: 0, cfg) + [YardText.moveLine(moves: 0, cfg)] {
            XCTAssertLessThanOrEqual(line.count, 80, "коротко: \(line)")
        }
    }
}
