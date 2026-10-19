// Кухня шефа (Cooking.swift): скидка food_price_x на «Угостить» (цена, монеты только при удачной кормёжке),
// готовка — блюдо сытнее еды, запас кухни, вещь из капсул, откат и дневной лимит, смена суток, бонус первого
// блюда (вкус, потом монеты), отказы, тексты, конфиг из economy.json, поле сейва верхним уровнем и переход
// к новому щенку, реакция сцены «cook» как у кормёжки.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000.
private let cT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

/// Кухня шефа, полный запас, шкалы с запасом до потолка — прибавка видна целиком.
private func cFile(at t: Double = cT0, kitchen: Int = 3) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = "cook-pet-1"
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 50 }
    f.pet.needs[.food] = 30
    f.pet.home[.kitchen] = kitchen
    f.pet.pantry = 60
    f.econ.wallet.coins = 100
    return f
}

/// Конфиг с явными цифрами — тесты не зависят от правок economy.json (еда — из него: цены те же, что в лавке).
private func cCfg(perDay: Int = 2, cooldownMin: Double = 180, bonus: Int = 15) -> CookConfig {
    var c = CookConfig()
    c.perDay = perDay
    c.cooldownMin = cooldownMin
    c.bonusCoins = bonus
    c.foods = CookConfig.shared.foods
    return c
}

final class CookingTests: XCTestCase {

    // MARK: скидка

    func testPriceRounding() {
        XCTAssertEqual(Cooking.price(4, x: 0.9), 3, "вниз — в пользу хозяина, скидка видна и на морковке")
        XCTAssertEqual(Cooking.price(60, x: 0.9), 54)
        XCTAssertEqual(Cooking.price(12, x: 0.9), 10)
        XCTAssertEqual(Cooking.price(1, x: 0.5), 1, "бесплатно не бывает")
        XCTAssertEqual(Cooking.price(6, x: 1), 6)
        XCTAssertEqual(Cooking.discountText(0.9), "−10%")
        XCTAssertNil(Cooking.discountText(1))
    }

    func testDiscountOnlyWithBuff() {
        XCTAssertEqual(Cooking.priceX(cFile().pet), 0.9, accuracy: 1e-9, "кухня шефа: food_price_x 0.9")
        XCTAssertTrue(Cooking.canCook(cFile().pet))
        for lv in 0...2 {
            let f = cFile(kitchen: lv)
            XCTAssertEqual(Cooking.priceX(f.pet), 1, "кухня \(lv) — без скидки")
            XCTAssertFalse(Cooking.canCook(f.pet), "кухня \(lv) — без готовки")
        }
    }

    func testBuyFoodWithDiscount() throws {
        var f = cFile()
        let food0 = f.pet.needs[.food] ?? 0
        let r = Cooking.buyFood("carrot", in: &f, now: cT0, cCfg())
        guard case .ok(let price, let out) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(price, 3, "морковка 4 × 0.9 → 3")
        XCTAssertTrue(out.ok)
        XCTAssertEqual(f.econ.wallet.coins, 100 - 3 + out.coins, "цена со скидкой, монеты за уход — как у кормёжки")
        XCTAssertGreaterThan(f.pet.needs[.food] ?? 0, food0, "кормит ядро")
        XCTAssertEqual(f.lastAction?.kind, "feed")
        let e = try XCTUnwrap(f.journal.last { $0.kind == "food.buy" })
        XCTAssertEqual(e.key, "carrot")
        XCTAssertEqual(e.value, 3)
        XCTAssertEqual(Cooking.buyText(r, name: "Морковка"), "Угощение: морковка за \(EconText.coins(3))")
    }

    func testBuyFoodFullPriceWithoutBuff() {
        var f = cFile(kitchen: 1)
        guard case .ok(let price, let out) = Cooking.buyFood("carrot", in: &f, now: cT0, cCfg()) else { return XCTFail() }
        XCTAssertEqual(price, 4)
        XCTAssertEqual(f.econ.wallet.coins, 100 - 4 + out.coins)
    }

    func testBuyFoodNoCoinsAndRefusalCostNothing() {
        var f = cFile()
        f.econ.wallet.coins = 2
        let food0 = f.pet.needs[.food]
        XCTAssertEqual(Cooking.buyFood("carrot", in: &f, now: cT0, cCfg()), .noCoins(need: 1))
        XCTAssertEqual(f.econ.wallet.coins, 2)
        XCTAssertEqual(f.pet.needs[.food], food0, "не купили — не покормили")

        var g = cFile()
        g.pet.bathUntil = cT0 + 600
        XCTAssertEqual(Cooking.buyFood("sausage", in: &g, now: cT0, cCfg()), .refused(reason: "bathing"))
        XCTAssertEqual(g.econ.wallet.coins, 100, "ядро не покормило — монеты целы")
        XCTAssertFalse(g.journal.contains { $0.kind == "food.buy" })

        var h = cFile()
        XCTAssertEqual(Cooking.buyFood("kibble", in: &h, now: cT0, cCfg()), .unknown, "хрустики — бесплатно на «Покормить»")
        XCTAssertEqual(Cooking.buyFood("gold_bone", in: &h, now: cT0, cCfg()), .unknown, "легендарное — только из капсул")
        XCTAssertEqual(h.econ.wallet.coins, 100)
    }

    // MARK: готовка

    func testDishFeedsBetterThanFood() {
        var kib = cFile()
        let before = kib.pet.needs[.food] ?? 0
        _ = PetRunner.apply(.feed(Catalog.mainFood), source: .app, to: &kib, now: cT0)
        let kibbleGain = (kib.pet.needs[.food] ?? 0) - before

        var f = cFile()
        let out = Cooking.cook("stew_home", in: &f, now: cT0, cCfg())
        XCTAssertTrue(out.ok, out.text)
        let x = Tastes.reaction(.food, "stew", in: f).needX
        XCTAssertEqual(out.gains["food"], Int((45 * x).rounded()))
        XCTAssertGreaterThan(Double(out.gains["food"] ?? 0), kibbleGain, "блюдо сытнее хрустиков")
        XCTAssertEqual(f.pet.needs[.food] ?? 0, 30 + 45 * x, accuracy: 1e-9)
        XCTAssertGreaterThan(out.gains["fun"] ?? 0, 0)
        XCTAssertGreaterThan(out.gains["love"] ?? 0, 0)
        XCTAssertEqual(f.pet.pantry, 40, accuracy: 1e-9, "запас кухни тратится")
        XCTAssertEqual(f.lastAction?.kind, Cooking.reactKind, "сцена: клипы еды")
        XCTAssertTrue(f.lastAction?.ok ?? false)
        XCTAssertEqual(f.journal.last { $0.kind == Cooking.reactKind }?.key, "stew_home")
        XCTAssertFalse(f.journal.contains { $0.kind.hasPrefix("act.") && $0.t == cT0 && $0.kind != "act.feed" },
                       "не act.*: монеты за уход и открытки блюдо не считают")
        XCTAssertEqual(f.cooking.total["stew_home"], 1)
        XCTAssertEqual(out.text, Cooking.lines["stew_home"]?[0])
    }

    func testNeedsClampAtHundred() {
        var f = cFile()
        f.pet.needs[.food] = 95
        let out = Cooking.cook("porridge", in: &f, now: cT0, cCfg())
        XCTAssertTrue(out.ok)
        XCTAssertEqual(f.pet.needs[.food], 100)
        XCTAssertEqual(out.gains["food"], 5, "прибавка — сколько влезло")
    }

    func testCooldownAndDailyLimit() {
        var f = cFile()
        XCTAssertTrue(Cooking.cook("stew_home", in: &f, now: cT0, cCfg()).ok)
        let early = Cooking.cook("porridge", in: &f, now: cT0 + 3600, cCfg())
        XCTAssertFalse(early.ok)
        XCTAssertEqual(early.reason, Cooking.reasons.cooldown)
        XCTAssertEqual(Cooking.state(cCfg().recipes[1], f, now: cT0 + 3600, cCfg()), .cooldown(until: cT0 + 180 * 60))
        XCTAssertTrue(Cooking.cook("porridge", in: &f, now: cT0 + 181 * 60, cCfg()).ok, "после отката можно")
        XCTAssertEqual(Cooking.todayCount(f, now: cT0 + 181 * 60), 2)
        let third = Cooking.cook("porridge", in: &f, now: cT0 + 400 * 60, cCfg())
        XCTAssertFalse(third.ok)
        XCTAssertEqual(third.reason, Cooking.reasons.enough)
        XCTAssertEqual(third.text, "На сегодня наготовлено: 2 блюда в день")
        XCTAssertEqual(f.cooking.today, 2, "отказ не считается")
    }

    func testNewDayResetsToday() {
        var f = cFile()
        let c = cCfg(perDay: 1, cooldownMin: 0)
        XCTAssertTrue(Cooking.cook("stew_home", in: &f, now: cT0, c).ok)
        XCTAssertEqual(Cooking.cook("stew_home", in: &f, now: cT0 + 60, c).reason, Cooking.reasons.enough)
        f.pet.pantry = 60
        XCTAssertEqual(Cooking.todayCount(f, now: cT0 + 86400), 0, "новые сутки — с нуля")
        XCTAssertTrue(Cooking.cook("stew_home", in: &f, now: cT0 + 86400, c).ok)
        XCTAssertEqual(f.cooking.today, 1)
        XCTAssertEqual(f.cooking.total["stew_home"], 2, "всего — не обнуляется")
        XCTAssertEqual(f.cooking.day, DayKey.of(cT0 + 86400))
    }

    func testRefusals() {
        var f = cFile(kitchen: 2)
        XCTAssertEqual(Cooking.cook("stew_home", in: &f, now: cT0, cCfg()).reason, Cooking.reasons.noKitchen)

        var g = cFile()
        g.pet.pantry = 10
        let low = Cooking.cook("stew_home", in: &g, now: cT0, cCfg())
        XCTAssertEqual(low.reason, Cooking.reasons.pantry)
        XCTAssertEqual(Cooking.state(cCfg().recipe("stew_home")!, g, now: cT0, cCfg()), .lowPantry(have: 10))

        var h = cFile()
        XCTAssertEqual(Cooking.cook("pumpkin_soup", in: &h, now: cT0, cCfg()).reason, Cooking.reasons.noItem)
        h.econ.items["pumpkin_small"] = 1
        XCTAssertTrue(Cooking.cook("pumpkin_soup", in: &h, now: cT0, cCfg()).ok)
        XCTAssertEqual(h.econ.items["pumpkin_small"], 1, "вещь не тратится")

        var b = cFile()
        b.pet.bathUntil = cT0 + 600
        XCTAssertEqual(Cooking.cook("stew_home", in: &b, now: cT0, cCfg()).reason, "bathing")

        var d = cFile()
        d.pet.alive = false
        XCTAssertEqual(Cooking.cook("stew_home", in: &d, now: cT0, cCfg()).reason, "dead")

        var u = cFile()
        XCTAssertEqual(Cooking.cook("soup_of_the_day", in: &u, now: cT0, cCfg()).reason, "unknown_item")

        // Ночью кухня закрыта: в 3 часа ночи пёс спит.
        var n = cFile()
        let night = cT0 - 9 * 3600
        n.pet.t = night
        n.seen = n.pet
        XCTAssertEqual(Cooking.cook("stew_home", in: &n, now: night, cCfg()).reason, Cooking.reasons.night)

        for x in [f, g, b, d] {
            XCTAssertTrue(x.cooking.isEmpty, "отказ ничего не пишет")
            XCTAssertNotEqual(x.lastAction?.kind, Cooking.reactKind)
        }
    }

    func testNapIsInterrupted() {
        var f = cFile()
        f.pet.napUntil = cT0 + 1800
        XCTAssertTrue(Cooking.cook("stew_home", in: &f, now: cT0, cCfg()).ok, "дрёму блюдо прерывает, как кормёжка")
        XCTAssertNil(f.pet.napUntil)
    }

    func testDailyBonusTasteThenCoins() {
        var f = cFile()
        let love = try? XCTUnwrap(Tastes.hidden(petId: f.petId, .food, log: f.tastes).love)
        guard let love else { return }
        let k = Tastes.key(.food, love)
        XCTAssertNil(f.tastes.opened[k])

        let a = Cooking.cook("stew_home", in: &f, now: cT0, cCfg())
        XCTAssertEqual(a.openedTaste, k, "первое блюдо дня выдаёт секрет — любимую еду")
        XCTAssertEqual(a.coins, 0)
        XCTAssertEqual(f.tastes.opened[k]?.r, Taste.love.rawValue)
        XCTAssertTrue(f.journal.contains { $0.kind == "taste.open" && $0.key == k })
        XCTAssertFalse(Cooking.bonusLeft(f, now: cT0 + 60))

        let b = Cooking.cook("porridge", in: &f, now: cT0 + 181 * 60, cCfg())
        XCTAssertTrue(b.ok)
        XCTAssertNil(b.openedTaste)
        XCTAssertEqual(b.coins, 0, "второе блюдо за день — без подарка")

        let day2 = cT0 + 86400
        f.pet.pantry = 60
        XCTAssertTrue(Cooking.bonusLeft(f, now: day2))
        let coins0 = f.econ.wallet.coins
        let c = Cooking.cook("stew_home", in: &f, now: day2, cCfg())
        XCTAssertTrue(c.ok)
        XCTAssertNil(c.openedTaste, "секрет уже открыт")
        XCTAssertEqual(c.coins, 15, "тогда — монеты")
        XCTAssertEqual(f.econ.wallet.coins, coins0 + 15)
        XCTAssertEqual(f.econ.lastEarn?.kind, Cooking.reactKind)
        XCTAssertEqual(Cooking.bonusText(c), "Подарок за первое блюдо дня: +\(EconText.coins(15))")
        XCTAssertFalse(Cooking.bonusText(c)?.contains(c.text) ?? true, "фраза про блюдо — только в пузыре, в тосте её нет")
    }

    // MARK: тексты и конфиг

    func testTexts() {
        XCTAssertEqual(Cooking.dishes(1), "блюдо")
        XCTAssertEqual(Cooking.dishes(2), "блюда")
        XCTAssertEqual(Cooking.dishes(5), "блюд")
        XCTAssertEqual(Cooking.dishes(11), "блюд")
        XCTAssertEqual(Cooking.dishes(21), "блюдо")
        XCTAssertEqual(Cooking.dishLine("stew_home", n: 3), Cooking.lines["stew_home"]?[0], "по кругу")
        XCTAssertFalse(Cooking.dishLine("nope", n: 1).isEmpty)
        XCTAssertEqual(Cooking.waitText(125 * 60), "Через 2 ч 5 мин")
        XCTAssertEqual(Cooking.waitText(30), "Через 1 мин")
        let stew = CookConfig.defaultRecipes[0]
        XCTAssertEqual(Cooking.gainsText(stew),
                       "\(Catalog.needName(.food))\u{00A0}+45 · \(Catalog.needName(.fun))\u{00A0}+6 · \(Catalog.needName(.love))\u{00A0}+4")
        for why in ["no_kitchen", "enough", "cooldown", "no_item", "pantry", "night"] {
            XCTAssertNotEqual(Cooking.reasonText(why), RefuseText.text(nil), why)
        }
        var f = cFile()
        XCTAssertEqual(Cooking.statusText(f, now: cT0, cCfg()), "Сегодня 0 из 2 · первое блюдо дня с подарком")
        Cooking.cook("stew_home", in: &f, now: cT0, cCfg())
        XCTAssertEqual(Cooking.statusText(f, now: cT0, cCfg()), "Сегодня 1 из 2")
        XCTAssertEqual(Cooking.stateText(.needsItem("acorn_jar"), stew, now: cT0), "Нужна вещь из капсул: банка желудей")
        XCTAssertNil(Cooking.stateText(.ready, stew, now: cT0))
    }

    func testConfigFromEconomyJSON() {
        let d = CookConfig(json: .null)
        XCTAssertEqual(d.recipes, CookConfig.defaultRecipes)
        XCTAssertEqual(d.perDay, 2)
        XCTAssertTrue(d.foods.isEmpty)

        let s = CookConfig.shared
        XCTAssertEqual(s.perDay, 2)
        XCTAssertEqual(s.cooldownMin, 180)
        XCTAssertEqual(s.bonusCoins, 15)
        XCTAssertEqual(s.recipes, CookConfig.defaultRecipes, "дефолт в коде = economy.json")
        XCTAssertTrue((3...4).contains(s.recipes.count))
        let foodIds = Set(EconomyConfig.shared.capsule.itemsById.keys)
        for r in s.recipes {
            XCTAssertGreaterThan(r.gains[.food] ?? 0, 20, "\(r.id) сытнее хрустиков")
            XCTAssertTrue(Catalog.names[r.taste] != nil, "\(r.id): вкус \(r.taste) — еда из shop.food")
            if let item = r.needsItem { XCTAssertTrue(foodIds.contains(item), "\(r.id): \(item) есть в капсулах") }
        }
        XCTAssertNil(s.food(Catalog.mainFood))
        XCTAssertNil(s.food("gold_bone"))
        XCTAssertEqual(s.food("carrot")?.price, 4)
        XCTAssertGreaterThanOrEqual(s.foods.count, 5)
    }

    // MARK: сейв

    func testSaveFieldTopLevelAndOldSave() throws {
        var f = cFile()
        let plain = try JSONEncoder().encode(f)
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("\"cooking\":{"), "пустое в файл не пишется")
        Cooking.cook("stew_home", in: &f, now: cT0, cCfg())
        let data = try JSONEncoder().encode(f)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(obj["cooking"] as? [String: Any], "верхним уровнем")
        let back = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(back.cooking, f.cooking)
        XCTAssertEqual(back.cooking.total["stew_home"], 1)

        let old = try JSONDecoder().decode(SaveFile.self, from: plain)
        XCTAssertTrue(old.cooking.isEmpty)
        XCTAssertEqual(old.petId, f.petId)
        let text = String(decoding: plain, as: UTF8.self)
        let broken = "{\"cooking\":\"много\"," + text.dropFirst()
        let b = try JSONDecoder().decode(SaveFile.self, from: Data(broken.utf8))
        XCTAssertTrue(b.cooking.isEmpty, "битое поле — пусто, а не весь сейв")
        XCTAssertEqual(b.petId, f.petId)
    }

    func testStartOverKeepsCooking() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-cooking")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: cT0)
        try store.mutate { (f: inout SaveFile) -> Void in
            f.pet.home[.kitchen] = 3
            f.pet.pantry = 60
            Cooking.cook("stew_home", in: &f, now: cT0, cCfg())
        }
        try store.startOver(now: cT0 + 100)
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.cooking.total["stew_home"], 1, "кухня остаётся вместе с домом")
        XCTAssertFalse(Cooking.bonusLeft(f, now: cT0 + 200), "новым щенком второй подарок за день не взять")
    }

    // MARK: сцена

    func testSceneTreatsDishAsFood() {
        XCTAssertEqual(Presenter.pose(mood: .hungry, reaction: Cooking.reactKind, needs: [:]), .eating)
        XCTAssertEqual(PostcardPhotos.kind(forAction: Cooking.reactKind, key: "stew_home"), .treat)
        XCTAssertEqual(SoundRecipe.forAction(kind: Cooking.reactKind, ok: true), .feed)
    }
}
