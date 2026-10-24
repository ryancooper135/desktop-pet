// Волна 32: ✂️ клочки и польза вещей (Premium.swift). Источники (день заботы, сундук недели, рекорды,
// находки, достижения) — идемпотентно; траты (Ателье, лоскутные вещи, цена возврата пса); польза вещей —
// одна функция, потолок по виду, одежда только надетой; сейв и переход к новому щенку; конфиг = economy.json.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000.
private let pT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

private func pFile(at t: Double = pT0) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = "premium-pet-1"
    return f
}

/// n удачных дел в момент t (журнал, как пишет PetRunner.apply).
private func acts(_ f: inout SaveFile, _ n: Int, at t: Double, kind: String = "act.feed") {
    for i in 0..<n { f.log(kind, t: t + Double(i), ok: true) }
}

final class PremiumTests: XCTestCase {

    // MARK: конфиг

    func testDefaultsMatchEconomyJson() {
        let json = PremiumConfig.shared
        let code = PremiumConfig()
        XCTAssertEqual(json, code, "цифры premium в economy.json и умолчания в коде разошлись")
        XCTAssertEqual(code.perkPct, [.common: 3, .rare: 5, .epic: 8, .legendary: 12])
        XCTAssertEqual(code.perkCapPct, 20)
        XCTAssertEqual(code.reviveBase, 30)
    }

    func testEveryItemHasPerkAndExclusivesAreItems() {
        let eco = EconomyConfig.shared
        let items = eco.capsule.itemsById
        for id in items.keys { XCTAssertNotNil(PremiumConfig.shared.perks[id], "\(id): у вещи нет пользы") }
        for k in PremiumConfig.shared.perks.keys { XCTAssertNotNil(items[k], "\(k): польза у несуществующей вещи") }
        for ex in PremiumConfig.shared.exclusives {
            XCTAssertNotNil(items[ex.id], ex.id)
            XCTAssertNotNil(ItemCatalog.role(ex.id), ex.id)
            XCTAssertNotNil(ItemArt.layers(ex.id), ex.id)
            // Лоскутных нет ни в капсуле, ни в лавке.
            for r in Rarity.allCases { XCTAssertFalse((eco.capsule.pools[r] ?? []).contains { $0.id == ex.id }, ex.id) }
        }
        // И одежда, и мебель.
        let roles = Set(PremiumConfig.shared.exclusives.compactMap { ItemCatalog.role($0.id) })
        XCTAssertTrue(roles.isSuperset(of: [.wear, .decor]))
        // Сердечек ни один вид не трогает.
        for k in PerkKind.allCases { XCTAssertFalse(k.key.contains("heart"), k.rawValue) }
    }

    func testShopNeverShowsExclusives() {
        for day in 0..<60 {
            let ids = ShopDaily.pick(petId: "premium-pet-1", day: day, owned: [])
            for ex in PremiumConfig.shared.exclusives { XCTAssertFalse(ids.contains(ex.id)) }
        }
    }

    // MARK: польза вещей

    func testPerkStrengthByRarityAndLine() {
        XCTAssertEqual(ItemPerks.pct("bowl_plain"), 3)
        XCTAssertEqual(ItemPerks.pct("lamp_mushroom"), 5)
        XCTAssertEqual(ItemPerks.pct("sofa_mini"), 8)
        XCTAssertEqual(ItemPerks.pct("kennel_castle"), 12)
        XCTAssertEqual(ItemPerks.pct("nope"), 0)
        XCTAssertEqual(ItemPerks.line("bowl_plain"), "Голодает на 3% медленнее")
        XCTAssertEqual(ItemPerks.line("lamp_mushroom"), "Высыпается на 5% быстрее")
        XCTAssertEqual(ItemPerks.line("bandana_red"), "Скучает на 3% медленнее · пока надето")
        XCTAssertNil(ItemPerks.line("nope"))
    }

    func testClothesCountOnlyWhileWorn() {
        var f = pFile()
        f.econ.items["bandana_red"] = 1
        XCTAssertEqual(ItemPerks.totals(f)[.fun], nil, "лежит в шкафу — не работает")
        _ = Wear.put(&f, "bandana_red")
        XCTAssertEqual(ItemPerks.totals(f)[.fun], 3)
        // Мебель и мячики — всегда.
        f.econ.items["mat_check"] = 1
        f.econ.items["ball_tennis"] = 1
        XCTAssertEqual(ItemPerks.totals(f)[.clean], 3)
        XCTAssertEqual(ItemPerks.totals(f)[.fun], 6)
    }

    func testCapPerKind() {
        var f = pFile()
        // sleep: лампа 5 + диван 8 + будка 12 + подушка-нет (love) = 25 → 20.
        for id in ["lamp_mushroom", "sofa_mini", "kennel_castle"] { f.econ.items[id] = 1 }
        XCTAssertEqual(ItemPerks.totals(f)[.sleep], 20)
        XCTAssertEqual(ItemPerks.summary(f), ["Высыпается на 20% быстрее · предел"])
        XCTAssertEqual(ItemPerks.mods(f)["sleep_regen_x"] ?? 0, 1.2, accuracy: 1e-9)
    }

    func testRulesCarryPerksIntoCore() {
        var f = pFile()
        let base = Catalog.rules
        XCTAssertEqual(ItemPerks.rules(f).preset, base.preset)
        let m0 = PetEngine.mods(f.pet, ItemPerks.rules(f))
        f.econ.items["mat_check"] = 1      // чистота −3%
        f.econ.items["bowl_plain"] = 1     // сытость −3%
        let m1 = PetEngine.mods(f.pet, ItemPerks.rules(f))
        func x(_ m: Effect, _ k: String) -> Double {
            if case .number(let n)? = m[k] { return n }
            return 1
        }
        XCTAssertEqual(x(m1, "clean_decay_x"), x(m0, "clean_decay_x") * 0.97, accuracy: 1e-9)
        XCTAssertEqual(x(m1, "food_decay_x"), x(m0, "food_decay_x") * 0.97, accuracy: 1e-9)
        XCTAssertEqual(x(m1, "heart_damage_x"), x(m0, "heart_damage_x"), "сердечки не трогаем")
        // Чистота тает медленнее на деле: 6 часов шага ядра.
        var plain = pFile()
        plain.pet.needs[.clean] = 90
        f.pet.needs[.clean] = 90
        let t = pT0 + 6 * 3600
        XCTAssertGreaterThan(PetRunner.peek(f, at: t).needs[.clean] ?? 0, PetRunner.peek(plain, at: t).needs[.clean] ?? 0)
    }

    func testCoinsPerkMultipliesMinigames() {
        var f = pFile()
        XCTAssertEqual(CatchGame.coinsX(f), CatchGame.coinsX(f.pet), accuracy: 1e-9)
        f.econ.items["trophy_cup"] = 1     // монеты +8%, мебель
        XCTAssertEqual(CatchGame.coinsX(f), CatchGame.coinsX(f.pet) * 1.08, accuracy: 1e-9)
    }

    // MARK: источники

    func testCareDayAndIdempotent() {
        var f = pFile()
        let w0 = f.econ.wallet.shards
        acts(&f, 4, at: pT0)
        XCTAssertTrue(Shards.settle(&f, now: pT0 + 10).isEmpty)
        acts(&f, 1, at: pT0 + 20)
        let g = Shards.settle(&f, now: pT0 + 30)
        XCTAssertEqual(g.map(\.reason), ["care_day"])
        XCTAssertEqual(f.econ.wallet.shards, w0 + 3)
        XCTAssertTrue(Shards.settle(&f, now: pT0 + 40).isEmpty, "второй раз не платит")
        acts(&f, 10, at: pT0 + 50)
        XCTAssertTrue(Shards.settle(&f, now: pT0 + 100).isEmpty, "раз в сутки")
        XCTAssertEqual(Shards.gainText(g[0]), "+3 ✂️ за день заботы")
    }

    func testStepsRefusalsAndEventsDoNotCount() {
        var f = pFile()
        for i in 0..<10 { f.log("act.steps", t: pT0 + Double(i), ok: true) }
        for i in 0..<10 { f.log("act.feed", t: pT0 + Double(i), ok: false, reason: "full") }
        for i in 0..<10 { f.log("ev.walk_end", t: pT0 + Double(i)) }
        XCTAssertTrue(Shards.settle(&f, now: pT0 + 20).isEmpty)
        XCTAssertEqual(f.shardLog.dayActs, 0)
    }

    func testWeekChestOnFifthDay() {
        var f = pFile()
        var paid: [String] = []
        for d in 0..<7 {
            let t = pT0 + Double(d) * 86400
            acts(&f, 5, at: t)
            paid += Shards.settle(&f, now: t + 100).map(\.reason)
        }
        // 7 дней заботы: 7 × день; сундук один или два (неделя с понедельника может смениться внутри 7 дней).
        XCTAssertEqual(paid.filter { $0 == "care_day" }.count, 7)
        XCTAssertGreaterThanOrEqual(paid.filter { $0 == "week_chest" }.count, 0)
        XCTAssertLessThanOrEqual(paid.filter { $0 == "week_chest" }.count, 1)
        XCTAssertTrue(paid.contains("ach.good_days_7"))
        XCTAssertEqual(f.shardLog.goodDays, 7)

        // Пять дней подряд с понедельника — ровно один сундук.
        var g = pFile()
        let monday = (0..<7).map { pT0 + Double($0) * 86400 }.first { Shards.week(DayKey.of($0)) != Shards.week(DayKey.of($0 - 86400)) }!
        var chest = 0
        for d in 0..<7 {
            let t = monday + Double(d) * 86400
            acts(&g, 5, at: t)
            chest += Shards.settle(&g, now: t + 100).filter { $0.reason == "week_chest" }.count
            if d == 3 { XCTAssertEqual(chest, 0, "четыре дня — рано") }
            if d == 4 { XCTAssertEqual(chest, 1, "пятый день — сундук") }
        }
        XCTAssertEqual(chest, 1, "раз в неделю")
    }

    func testClockBackDoesNotRepayOldDay() {
        var f = pFile()
        acts(&f, 5, at: pT0 + 86400)
        XCTAssertEqual(Shards.settle(&f, now: pT0 + 86400 + 10).count, 1)
        acts(&f, 5, at: pT0)   // часы назад: вчерашние сутки
        XCTAssertTrue(Shards.settle(&f, now: pT0 + 10).isEmpty)
    }

    func testRecordOncePerDayNotFirstRound() {
        var f = pFile()
        Shards.settle(&f, now: pT0)
        f.catchBest = 10   // первый рекорд — от нуля: не платим
        XCTAssertTrue(Shards.settle(&f, now: pT0 + 1).isEmpty)
        f.catchBest = 15
        XCTAssertEqual(Shards.settle(&f, now: pT0 + 2).map(\.reason), ["record"])
        f.zombieBest = 3
        f.blockduoBest = 50
        Shards.settle(&f, now: pT0 + 3)
        f.zombieBest = 9
        XCTAssertTrue(Shards.settle(&f, now: pT0 + 4).isEmpty, "раз в сутки")
        f.catchBest = 20
        XCTAssertEqual(Shards.settle(&f, now: pT0 + 86400).map(\.reason), ["record"])
    }

    func testFreeRoundRecordPaysNoShards() {
        var f = pFile()
        Shards.settle(&f, now: pT0)
        f.catchBest = 10
        Shards.settle(&f, now: pT0 + 1)
        let r = CatchGame.finish(score: 30, in: &f, now: pT0 + 2, free: "asleep")
        XCTAssertTrue(r.isRecord, "рекорд пишется и «просто так»")
        XCTAssertFalse(Shards.settle(&f, now: pT0 + 3).contains { $0.reason == "record" }, "но без ✂️")
    }

    func testOldSaveBaselinesWithoutPaying() {
        var f = pFile()
        f.catchBest = 40
        acts(&f, 20, at: pT0)
        // Как старый сейв: учёта клочков не было.
        let data = try! JSONEncoder().encode(f)
        var old = try! JSONDecoder().decode(SaveFile.self, from: data)
        old.shardLog = ShardLog()
        old.shardLog.seenSeq = old.seq
        XCTAssertTrue(Shards.settle(&old, now: pT0 + 100).filter { $0.reason == "care_day" || $0.reason == "record" }.isEmpty)
        // Без поля в файле — то же самое (seenSeq = seq при чтении).
        var plain = pFile()
        acts(&plain, 20, at: pT0)
        let back = try! JSONDecoder().decode(SaveFile.self, from: try! JSONEncoder().encode(plain))
        XCTAssertEqual(back.shardLog.seenSeq, plain.seq)
    }

    func testFindsSometimesHoldShardsAndNewKindPaysOnce() {
        var f = pFile()
        Shards.settle(&f, now: pT0)
        var got = 0, newKinds = 0
        for i in 0..<200 {
            f.pet.finds[i % 2 == 0 ? "stick" : "leaf", default: 0] += 1
            for g in Shards.settle(&f, now: pT0 + Double(i)) {
                if g.reason == "find" { got += 1; XCTAssertTrue((1...2).contains(g.shards)) }
                if g.reason == "new_find" { newKinds += 1 }
            }
        }
        XCTAssertEqual(newKinds, 2)
        XCTAssertGreaterThan(got, 5, "≈10% находок")
        XCTAssertLessThan(got, 45)
        // Детерминированно: тот же пёс — те же клочки.
        var a = pFile(), b = pFile()
        Shards.settle(&a, now: pT0); Shards.settle(&b, now: pT0)
        a.pet.finds["stick"] = 30; b.pet.finds["stick"] = 30
        XCTAssertEqual(Shards.settle(&a, now: pT0 + 1), Shards.settle(&b, now: pT0 + 1))
    }

    func testAchievementsOnce() {
        var f = pFile()
        f.cooking.total["soup"] = 1
        f.tricks.items["sit"] = TrickLog.Entry()
        f.tricks.items["sit"]?.learned = pT0
        let g = Shards.settle(&f, now: pT0).map(\.reason).sorted()
        XCTAssertEqual(g, ["ach.first_dish", "ach.first_trick"])
        XCTAssertTrue(Shards.settle(&f, now: pT0 + 1).isEmpty)
    }

    func testPetRunnerPaysThroughApply() {
        var f = pFile()
        for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 30 }
        var t = pT0
        var before = f.econ.wallet.shards
        for a in [PetAction.feed(Catalog.mainFood), .pet, .play, .pet, .bath, .pet, .feed(Catalog.mainFood), .pet] {
            _ = PetRunner.apply(a, source: .app, to: &f, now: t)
            t += 600
        }
        let okActs = f.journal.filter { $0.kind.hasPrefix("act.") && $0.ok == true }.count
        if okActs >= 5 { XCTAssertEqual(f.econ.wallet.shards, before + 3) }
        before = f.econ.wallet.shards
        PetRunner.catchUp(&f, now: t + 60)
        XCTAssertEqual(f.econ.wallet.shards, before, "догон не платит второй раз")
    }

    // MARK: траты

    func testSpendAndReviveCost() {
        var f = pFile()
        f.econ.wallet.shards = 10
        XCTAssertFalse(Shards.spend(&f, 11))
        XCTAssertEqual(f.econ.wallet.shards, 10)
        XCTAssertTrue(Shards.spend(&f, 10))
        XCTAssertEqual(f.econ.wallet.shards, 0)
        XCTAssertEqual(Shards.reviveCost(revivesBefore: 0), 30)
        XCTAssertEqual(Shards.reviveCost(revivesBefore: 1), 45)
        XCTAssertEqual(Shards.reviveCost(revivesBefore: 2), 60)
        XCTAssertEqual(Shards.reviveCost(revivesBefore: 10), 90)
        XCTAssertEqual(Shards.reviveCost(revivesBefore: -3), 30)
    }

    func testAtelierGivesUnownedOfRarity() {
        var f = pFile()
        XCTAssertNil(Shards.atelierPrice(.common), "за клочками — только за редким")
        guard case .failure(.unknown) = Shards.atelier(&f, rarity: .common, now: pT0) else { return XCTFail() }
        f.econ.wallet.shards = 69
        guard case .failure(.notEnough(need: 1)) = Shards.atelier(&f, rarity: .rare, now: pT0) else { return XCTFail() }
        XCTAssertEqual(f.econ.wallet.shards, 69)
        let pity = f.econ.capsule
        f.econ.wallet.shards = 70 * 20
        var got: Set<String> = []
        let rare = EconomyConfig.shared.capsule.pools[.rare] ?? []
        for _ in rare {
            guard case .success(let it) = Shards.atelier(&f, rarity: .rare, now: pT0) else { return XCTFail() }
            XCTAssertEqual(it.rarity, .rare)
            XCTAssertFalse(got.contains(it.id), "повтора нет")
            got.insert(it.id)
        }
        XCTAssertEqual(got.count, rare.count)
        guard case .failure(.allOwned) = Shards.atelier(&f, rarity: .rare, now: pT0) else { return XCTFail() }
        XCTAssertEqual(f.econ.wallet.shards, 70 * 20 - 70 * rare.count)
        XCTAssertEqual(f.econ.capsule, pity, "гарант капсулы не трогаем")
        XCTAssertEqual(f.journal.last?.kind, "atelier")
    }

    func testBuyExclusive() {
        var f = pFile()
        let ex = PremiumConfig.shared.exclusives[0]
        f.econ.wallet.shards = ex.price - 1
        guard case .failure(.notEnough(need: 1)) = Shards.buyExclusive(ex.id, in: &f, now: pT0) else { return XCTFail() }
        f.econ.wallet.shards = ex.price * 2
        guard case .success(let it) = Shards.buyExclusive(ex.id, in: &f, now: pT0) else { return XCTFail() }
        XCTAssertEqual(it.id, ex.id)
        XCTAssertEqual(f.econ.items[ex.id], 1)
        XCTAssertEqual(f.econ.wallet.shards, ex.price)
        guard case .failure(.owned) = Shards.buyExclusive(ex.id, in: &f, now: pT0) else { return XCTFail() }
        guard case .failure(.unknown) = Shards.buyExclusive("bandana_red", in: &f, now: pT0) else { return XCTFail() }
        XCTAssertEqual(f.journal.last?.kind, "shards.buy")
        // Лоскутную одежду можно надеть, и она работает.
        f.econ.wallet.shards = 1000
        _ = Shards.buyExclusive("scarf_patch", in: &f, now: pT0)
        XCTAssertNil(ItemPerks.totals(f)[.fun])
        _ = Wear.put(&f, "scarf_patch")
        XCTAssertEqual(ItemPerks.totals(f)[.fun], 8)
    }

    // MARK: сейв

    func testSaveRoundTripAndCarryOver() throws {
        var f = pFile()
        acts(&f, 5, at: pT0)
        f.cooking.total["soup"] = 1
        Shards.settle(&f, now: pT0 + 10)
        XCTAssertFalse(f.shardLog.isEmpty)
        let back = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back.shardLog, f.shardLog)
        // Пустой учёт не пишется.
        let fresh = pFile()
        let text = String(decoding: try JSONEncoder().encode(fresh), as: UTF8.self)
        XCTAssertFalse(text.contains("shardLog"))
        // Новый щенок: журнал заново, разовое и счётчик дней остаются.
        let c = f.shardLog.carriedOver()
        XCTAssertEqual(c.seenSeq, 0)
        XCTAssertEqual(c.finds, -1)
        XCTAssertEqual(c.goodDays, f.shardLog.goodDays)
        XCTAssertEqual(c.once, f.shardLog.once)
        // Битое поле не ломает сейв.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(f)) as! [String: Any]
        json["shardLog"] = "мусор"
        let broken = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(broken.shardLog.seenSeq, broken.seq)
    }

    func testProgressText() {
        var f = pFile()
        XCTAssertEqual(Shards.progress(f, now: pT0), "Сегодня: дел 0 из 5 · неделя: дней 0 из 5")
        acts(&f, 3, at: pT0)
        Shards.settle(&f, now: pT0 + 5)
        XCTAssertEqual(Shards.progress(f, now: pT0 + 5), "Сегодня: дел 3 из 5 · неделя: дней 0 из 5")
        acts(&f, 2, at: pT0 + 10)
        Shards.settle(&f, now: pT0 + 15)
        XCTAssertEqual(Shards.progress(f, now: pT0 + 15), "Сегодня: день заботы засчитан · неделя: дней 1 из 5")
    }

    // MARK: экран: кошелёк, мастерская, тост

    func testWalletWithShards() {
        XCTAssertEqual(EconText.wallet(coins: 150, tickets: 1, shards: 12), "150 монет, 1 билетик, 12 клочков")
        XCTAssertEqual(EconText.wallet(coins: 2, tickets: 0, shards: 1), "2 монеты, 0 билетиков, 1 клочок")
        // Нет клочков — фраза как раньше.
        XCTAssertEqual(EconText.wallet(coins: 150, tickets: 1, shards: 0), EconText.wallet(coins: 150, tickets: 1))
    }

    func testWorkshopOffers() {
        var f = pFile()
        f.econ.wallet.shards = 100
        let cfg = PremiumConfig.shared
        let offers = Shards.offers(f)
        XCTAssertEqual(offers.count, cfg.atelier.count + cfg.exclusives.count)
        XCTAssertEqual(Set(offers.map(\.id)).count, offers.count, "id карточек повторяются")
        // Сначала ателье по цене, потом лоскутные по цене.
        let atelier = offers.filter { $0.itemId == nil }
        let ex = offers.filter { $0.itemId != nil }
        XCTAssertEqual(atelier.map(\.price), atelier.map(\.price).sorted())
        XCTAssertEqual(ex.map(\.price), ex.map(\.price).sorted())
        XCTAssertEqual(offers.firstIndex { $0.itemId != nil }, atelier.count)
        // 100 клочков: редкое ателье (70) по карману, подушка (60) тоже, кресло (160) — нет.
        let rare = offers.first { $0.kind == .atelier(.rare) }!
        XCTAssertEqual(rare.state, .buy(need: 0))
        XCTAssertEqual(Shards.buttonTitle(rare), "Взять")
        let chair = offers.first { $0.kind == .exclusive("armchair_patch") }!
        XCTAssertEqual(chair.state, .buy(need: 60))
        XCTAssertEqual(Shards.buttonTitle(chair), "Не хватает 60")
        // У лоскутной вещи под названием — её польза.
        XCTAssertEqual(chair.note, ItemPerks.line("armchair_patch"))
        // Купили — «Уже есть».
        f.econ.items["pillow_patch"] = 1
        let pillow = Shards.offers(f).first { $0.itemId == "pillow_patch" }!
        XCTAssertEqual(pillow.state, .owned)
        XCTAssertEqual(Shards.buttonTitle(pillow), "Уже есть")
        // Все редкие собраны — «Всё собрано».
        for it in EconomyConfig.shared.capsule.pools[.rare] ?? [] { f.econ.items[it.id] = 1 }
        let done = Shards.offers(f).first { $0.kind == .atelier(.rare) }!
        XCTAssertEqual(done.state, .allOwned)
        XCTAssertEqual(Shards.buttonTitle(done), "Всё собрано")
    }

    func testRefusalTexts() {
        XCTAssertEqual(Shards.refusalText(.notEnough(need: 7)), "Не хватает клочков: 7 ✂️")
        for r in [ShardRefusal.allOwned, .owned, .unknown] { XCTAssertFalse(Shards.refusalText(r).isEmpty) }
    }

    func testFreshGainToastOnce() {
        var f = pFile()
        XCTAssertNil(Shards.freshGain(f, now: pT0, shownT: nil))
        acts(&f, 5, at: pT0)
        Shards.settle(&f, now: pT0 + 5)
        let g = Shards.freshGain(f, now: pT0 + 6, shownT: nil)
        XCTAssertNotNil(g)
        XCTAssertEqual(Shards.toastText(g!), "+3 клочка за день заботы")
        // Уже показали — второй раз нет; старая награда — тоже нет.
        XCTAssertNil(Shards.freshGain(f, now: pT0 + 7, shownT: g!.t))
        XCTAssertNil(Shards.freshGain(f, now: pT0 + 60, shownT: nil))
    }
}
