// Волна 40 F: времена года в мире (Seasons.swift). Сезонные вещи за ✂️ — только в свой сезон, навсегда;
// сезон под тестами стабильный (осень); реплики о сезоне — свой редкий ход PetMind. Гоняется и на Linux.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let sT0: Double = 1_760_000_000

private func sFile(_ pet: String = "dog-1") -> SaveFile {
    var f = SaveFile.fresh(now: sT0)
    f.petId = pet
    return f
}

private func configURL() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("config/economy.json")
}

/// Полночь UTC даты y-m-d.
private func utc(_ y: Int, _ m: Int, _ d: Int) -> Double {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c.date(from: DateComponents(year: y, month: m, day: d))!.timeIntervalSince1970
}

final class SeasonsTests: XCTestCase {

    override func tearDown() {
        Seasons.pinned = nil
        super.tearDown()
    }

    // MARK: какой сезон

    func testSeasonUnderTestIsStable() {
        XCTAssertNil(Seasons.forced, "в unit-тестах PET_SEASON не задан")
        // Любая дата — под тестами осень: снимки и Мастерская не зависят от дня прогона.
        for (m, d) in [(1, 15), (4, 1), (7, 20), (10, 27), (12, 31)] {
            XCTAssertEqual(Seasons.shown(at: utc(2026, m, d), tzOffsetMin: 0), .autumn)
        }
        XCTAssertEqual(Seasons.now(), Seasons.testSeason)
        XCTAssertNil(Seasons.talking(at: utc(2026, 1, 15), tzOffsetMin: 0), "под тестами без закрепления — без слов")
    }

    func testPinnedWins() {
        for s in Season.allCases {
            Seasons.pinned = s
            XCTAssertEqual(Seasons.shown(at: utc(2026, 10, 27), tzOffsetMin: 0), s)
            XCTAssertEqual(Seasons.talking(at: utc(2026, 10, 27), tzOffsetMin: 0), s)
        }
    }

    func testNextCyclesYear() {
        var s = Season.winter
        var seen: [Season] = []
        for _ in 0..<4 { seen.append(s); s = Seasons.next(s) }
        XCTAssertEqual(seen, [.winter, .spring, .summer, .autumn])
        XCTAssertEqual(s, .winter)
    }

    // MARK: вещи в каталоге

    func testItemsAreRealItemsButNotInPools() {
        let cap = EconomyConfig.shared.capsule
        let pooled = Set(cap.pools.values.flatMap { $0 }.map(\.id))
        let sinks = Set(ScrapSinks.all.map(\.id))
        XCTAssertEqual(Seasons.all.count, 8)
        XCTAssertEqual(Set(Seasons.all.map(\.id)).count, 8, "id уникальны")
        for s in Season.allCases {
            let mine = Seasons.items(of: s)
            XCTAssertEqual(mine.count, 2, "по две вещи на \(s)")
            XCTAssertEqual(mine.filter(\.wear).count, 1, "\(s): одна на пса, одна на полку")
        }
        for it in Seasons.all {
            XCTAssertTrue(it.id.hasPrefix("season_"), it.id)
            XCTAssertFalse(pooled.contains(it.id), "\(it.id) не в капсуле")
            XCTAssertFalse(sinks.contains(it.id), it.id)
            XCTAssertNil(PremiumConfig.shared.exclusive(it.id), "\(it.id): не в лоскутных")
            XCTAssertEqual(cap.itemsById[it.id]?.rarity, .rare, "\(it.id) в коллекции, редкая")
            XCTAssertEqual(ItemCatalog.role(it.id), it.wear ? .wear : .decor, it.id)
            XCTAssertEqual(Wear.canWear(it.id), it.wear, it.id)
            XCTAssertNotEqual(ItemCatalog.emoji(it.id), "📦", it.id)
            XCTAssertEqual(PremiumConfig.shared.perks[it.id], it.perk, it.id)
            XCTAssertNotEqual(it.perk, .coins, "\(it.id): польза не в доход")
            XCTAssertEqual(ItemPerks.pct(it.id), 5, "\(it.id): польза маленькая — как у редкой")
        }
    }

    func testNeverInShopOrAtelier() {
        let ids = Set(Seasons.all.map(\.id))
        let day = DayKey.of(sT0)
        for d in 0..<60 {
            for id in ShopDaily.pick(petId: "dog-1", day: day + d, owned: []) { XCTAssertFalse(ids.contains(id)) }
        }
        let f = sFile()
        for r in Rarity.allCases {
            XCTAssertTrue(Shards.atelierLeft(f, r).allSatisfy { !ids.contains($0.id) }, "ателье их не выдаёт")
        }
        XCTAssertTrue(Shards.offers(f).allSatisfy { o in o.itemId.map { !ids.contains($0) } ?? true })
    }

    func testArtInsideUnitSquare() {
        for it in Seasons.all {
            guard let layers = SeasonItemArt.table[it.id] else { XCTFail("\(it.id): нет иконки"); continue }
            XCTAssertEqual(ItemArt.layers(it.id), layers)
            XCTAssertGreaterThanOrEqual(layers.count, 2, it.id)
            for l in layers {
                let b = l.shape.bounds
                XCTAssertGreaterThanOrEqual(b.lo.x, 0, it.id); XCTAssertGreaterThanOrEqual(b.lo.y, 0, it.id)
                XCTAssertLessThanOrEqual(b.hi.x, 1, it.id); XCTAssertLessThanOrEqual(b.hi.y, 1, it.id)
                if case .poly(let pts) = l.shape { XCTAssertGreaterThanOrEqual(pts.count, 3, it.id) }
            }
        }
        XCTAssertEqual(Set(SeasonItemArt.table.keys), Set(Seasons.all.map(\.id)), "лишних иконок нет")
    }

    // MARK: цены

    func testPricesSitBetweenGoldenAndPlaceExclusive() throws {
        let c = SeasonConfig()
        for p in [c.wearPrice, c.decorPrice] {
            XCTAssertGreaterThan(p, ScrapSinks.goldenPrice, "дороже золотого шарика: вещь выбираешь сам")
            XCTAssertLessThan(p, ScrapSinks.placePrice, "дешевле эксклюзива места: польза меньше (5 % против 8 %)")
        }
        XCTAssertGreaterThan(c.wearPrice, c.decorPrice, "на псе видно везде — чуть дороже")
    }

    func testConfigFileMatchesDefaults() throws {
        let data = try Data(contentsOf: configURL())
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(SeasonConfig(json: json), SeasonConfig(), "config/economy.json и умолчания в Swift разошлись")
        XCTAssertEqual(SeasonConfig(json: .null), SeasonConfig())
    }

    func testConfigReadsOverrides() throws {
        let raw = #"{"seasons": {"price": {"wear": 33, "decor": 0}, "talk_one_in": 99}}"#
        let c = SeasonConfig(json: try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)))
        XCTAssertEqual(c.wearPrice, 33)
        XCTAssertEqual(c.decorPrice, 1, "бесплатно не бывает")
        XCTAssertEqual(c.talkOneIn, 24, "потолок")
    }

    // MARK: покупка

    func testBuyOnlyInOwnSeason() {
        for it in Seasons.all {
            for s in Season.allCases where s != it.season {
                var f = sFile()
                f.econ.wallet.shards = 500
                guard case .failure(.offSeason(let want)) = Seasons.buy(it.id, in: &f, season: s, now: sT0) else {
                    XCTFail("\(it.id) продали в \(s)"); continue
                }
                XCTAssertEqual(want, it.season)
                XCTAssertEqual(f.econ.wallet.shards, 500, "клочки целы")
                XCTAssertNil(f.econ.items[it.id])
            }
        }
        XCTAssertEqual(Seasons.refusalText(.offSeason(.winter)), "Это продают только зимой")
    }

    func testNotEnoughShards() {
        let c = SeasonConfig()
        let it = Seasons.items(of: .autumn).first { $0.wear }!
        var f = sFile()
        f.econ.wallet.shards = c.wearPrice - 1
        guard case .failure(.notEnough(need: 1)) = Seasons.buy(it.id, in: &f, season: .autumn, now: sT0) else {
            return XCTFail()
        }
        XCTAssertEqual(f.econ.wallet.shards, c.wearPrice - 1)
        XCTAssertNil(f.econ.items[it.id])
        XCTAssertEqual(Seasons.refusalText(.notEnough(need: 1)), "Не хватает клочков: 1 ✂️")
    }

    func testBuySpendsOnceAndKeepsForever() throws {
        let c = SeasonConfig()
        let it = Seasons.items(of: .winter).first { !$0.wear }!
        var f = sFile()
        f.econ.wallet.shards = 200
        let coins = f.econ.wallet.coins
        let xp = f.level
        guard case .success(let got) = Seasons.buy(it.id, in: &f, season: .winter, now: sT0) else { return XCTFail() }
        XCTAssertEqual(got.id, it.id)
        XCTAssertEqual(f.econ.wallet.shards, 200 - c.decorPrice)
        XCTAssertEqual(f.econ.items[it.id], 1)
        XCTAssertEqual(f.econ.wallet.coins, coins, "монеты не трогает")
        XCTAssertEqual(f.level, xp, "опыт не трогает")
        XCTAssertEqual(f.journal.last?.kind, "season.buy")
        XCTAssertEqual(f.journal.last?.key, it.id)
        // Второй раз — «уже есть», даже в чужой сезон отказ про «уже есть», а не про сезон.
        guard case .failure(.owned) = Seasons.buy(it.id, in: &f, season: .winter, now: sT0) else { return XCTFail() }
        guard case .failure(.owned) = Seasons.buy(it.id, in: &f, season: .summer, now: sT0) else { return XCTFail() }
        XCTAssertEqual(f.econ.wallet.shards, 200 - c.decorPrice)
        // Сезон прошёл — вещь на месте и работает (полка — всегда), и переживает сейв.
        let back = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back.econ.items[it.id], 1)
        XCTAssertTrue(ItemPerks.activeIds(back).contains(it.id))
        XCTAssertEqual(ItemPerks.totals(back)[it.perk], 5)
    }

    func testUnknownItem() {
        var f = sFile()
        f.econ.wallet.shards = 500
        guard case .failure(.unknown) = Seasons.buy("pillow_patch", in: &f, season: .autumn, now: sT0) else {
            return XCTFail("чужая вещь через сезон не продаётся")
        }
        XCTAssertEqual(f.econ.wallet.shards, 500)
    }

    func testBuyIsDeterministic() {
        func run() -> SaveFile {
            var f = sFile()
            f.econ.wallet.shards = 300
            for it in Seasons.all { _ = Seasons.buy(it.id, in: &f, season: .spring, now: sT0) }
            return f
        }
        let a = run(), b = run()
        XCTAssertEqual(a.econ.items, b.econ.items)
        XCTAssertEqual(a.econ.wallet.shards, b.econ.wallet.shards)
        XCTAssertEqual(Set(a.econ.items.keys), Set(Seasons.items(of: .spring).map(\.id)), "весной — только весеннее")
    }

    // MARK: Мастерская

    func testOffersFollowSeasonAndState() {
        let c = SeasonConfig()
        var f = sFile()
        f.econ.wallet.shards = c.decorPrice
        for s in Season.allCases {
            let o = Seasons.offers(f, season: s)
            XCTAssertEqual(o.map(\.itemId), Seasons.items(of: s).sorted { $0.wear && !$1.wear }.map(\.id))
            XCTAssertTrue(o.first.map { Wear.canWear($0.itemId!) } ?? false, "сначала вещь на пса")
            XCTAssertTrue(o.allSatisfy { $0.id.hasPrefix("season.season_") })
            XCTAssertEqual(o.first?.state, .buy(need: c.wearPrice - c.decorPrice))
            XCTAssertEqual(o.last?.state, .buy(need: 0))
            XCTAssertTrue(o.allSatisfy { $0.note.contains("5%") }, "польза в подписи")
        }
        let it = Seasons.items(of: .autumn).first { !$0.wear }!
        _ = Seasons.buy(it.id, in: &f, season: .autumn, now: sT0)
        XCTAssertEqual(Seasons.offers(f, season: .autumn).first { $0.itemId == it.id }?.state, .owned)
        XCTAssertEqual(Shards.offers(f).count, PremiumConfig.shared.atelier.count + PremiumConfig.shared.exclusives.count,
                       "старый список Мастерской не трогаем")
        XCTAssertEqual(Seasons.title(.autumn), "🍂 Осеннее — только осенью")
    }

    // MARK: реплики

    func testLinesFitAndExist() throws {
        guard !(Lines.shared.sections["widget"] ?? [:]).isEmpty else { throw XCTSkip("lines.json нет в бандле") }
        for s in Season.allCases {
            let key = SeasonTalk.lineKey(s)
            let w = try XCTUnwrap(Lines.shared.sections["widget"]?[key], key)
            let i = try XCTUnwrap(Lines.shared.sections["island"]?[key], key)
            XCTAssertTrue((2...4).contains(w.count), key)
            XCTAssertTrue((2...4).contains(i.count), key)
            XCTAssertTrue(w.allSatisfy { $0.text.count <= LineLimit.widget }, key)
            XCTAssertTrue(i.allSatisfy { $0.text.count <= LineLimit.island }, key)
        }
    }

    func testSeasonTalkIsRareAndOwnTurn() throws {
        guard !(Lines.shared.sections["widget"] ?? [:]).isEmpty else { throw XCTSkip("lines.json нет в бандле") }
        var f = sFile()
        f.petId = "season-pet"
        var spoke = 0
        let slots = 12 * 60   // 60 суток по 12 слотов
        for k in 0..<slots {
            let t = utc(2026, 10, 1) + Double(k) * 2 * 3600 + 600
            let slot = PetMind.slot(t, tzOffsetMin: 0)
            let said = SeasonTalk.line(f, at: t, tzOffsetMin: 0, season: .autumn)
            XCTAssertNil(SeasonTalk.line(f, at: t, tzOffsetMin: 0), "под тестами без закрепления — молчит")
            if let said {
                XCTAssertEqual(PetMind.roll(f, slot: slot), SeasonTalk.turn, "только в свой ход")
                XCTAssertTrue(Lines.shared.sections["widget"]?["season_autumn"]?.contains { $0.text == said } ?? false)
                XCTAssertNotNil(SeasonTalk.line(f, at: t, tzOffsetMin: 0, island: true, season: .winter))
                XCTAssertEqual(said, SeasonTalk.line(f, at: t, tzOffsetMin: 0, season: .autumn), "детерминизм")
                spoke += 1
            }
        }
        // Ход 1 из 8, из них 1 из 3: ~30 за 60 суток (раз в двое суток).
        XCTAssertGreaterThan(spoke, 12)
        XCTAssertLessThan(spoke, 60)
        XCTAssertNotEqual(SeasonTalk.turn, WeatherTalk.turn, "не отбирает ход погоды")
    }

    /// Presenter в ход сезона (закреплённый) говорит о нём, без закрепления под тестами — обычная строка.
    func testPresenterSaysSeason() throws {
        guard !(Lines.shared.sections["widget"] ?? [:]).isEmpty else { throw XCTSkip("lines.json нет в бандле") }
        var f = sFile()
        f.petId = "season-pet"
        let r = Catalog.rules
        let owner = Owner(bedMin: r.bedMin, wakeMin: r.wakeMin, tzOffsetMin: 0)
        var used = 0
        for d in 1..<40 {
            for h in [11.0, 13, 15, 17] {
                let t = utc(2026, 10, 1) + Double(d) * 86_400 + h * 3600
                guard SeasonTalk.speaks(f, slot: PetMind.slot(t, tzOffsetMin: 0)) else { continue }
                var s = PetEngine.newPet(r, t: t)
                for n in Need.allCases { s.needs[n] = 100 }
                Seasons.pinned = .winter
                let winter = Presenter.make(file: f, pet: s, owner: owner, at: t)
                Seasons.pinned = nil
                let plain = Presenter.make(file: f, pet: s, owner: owner, at: t)
                let said = SeasonTalk.line(f, at: t, tzOffsetMin: 0, season: .winter)
                guard winter.line == said else { continue }   // спокойного «ok» могло не быть (утро, вечер)
                used += 1
                XCTAssertNotEqual(plain.line, said, "без сезона — обычная реплика")
                XCTAssertEqual(winter.mood, plain.mood, "сезон не меняет настроение")
            }
        }
        XCTAssertGreaterThan(used, 0, "сезон доходит до пузыря")
    }
}
