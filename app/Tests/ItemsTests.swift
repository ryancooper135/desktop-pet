// Волна 11: предметы и лавка. Каталог (роль у каждого id, иконка в рамке, эмодзи на запас), полка и мячик
// (вкл/выкл, отказы, поля в сейве), «Лавка» дня (детерминизм, три редкости, цены по полосам, покупка и отказы,
// журнал shop.buy). Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let iT0: Double = 1_760_000_000

/// Щенок с монетами и предметами ids.
private func iFile(_ ids: [String] = [], coins: Int = 0) -> SaveFile {
    var f = SaveFile.fresh(now: iT0)
    if coins > 0 { Economy.grant(&f, coins: coins) }
    for id in ids { f.econ.items[id] = 1 }
    return f
}

private var allIds: [String] {
    Rarity.allCases.flatMap { (EconomyConfig.shared.capsule.pools[$0] ?? []).map(\.id) }
}

final class ItemCatalogTests: XCTestCase {
    func testCatalogHasRolesArtAndOldIds() {
        let ids = allIds
        XCTAssertEqual(Set(ids).count, ids.count, "id в пулах не повторяются")
        XCTAssertGreaterThanOrEqual(ids.count, 24)
        // Старые id на месте: по ним лежат сейвы.
        for id in ["bandana_red", "bow_blue", "leaf_hat", "bowl_plain", "mat_check", "scarf_knit", "collar_star",
                   "lamp_mushroom", "raincoat", "hoodie_pumpkin", "sofa_mini", "cape_champion", "kennel_castle"] {
            XCTAssertTrue(ids.contains(id), id)
        }
        for id in ids {
            XCTAssertNotNil(ItemCatalog.role(id), "\(id): без роли предмет мёртвый")
            XCTAssertNotNil(ItemArt.layers(id), "\(id): нет иконки")
            XCTAssertNotEqual(ItemCatalog.emoji(id), "📦", "\(id): нет запасного эмодзи")
        }
        // Роли не пересекаются.
        XCTAssertTrue(ItemCatalog.decor.isDisjoint(with: Wear.table.keys))
        XCTAssertTrue(ItemCatalog.decor.isDisjoint(with: ItemCatalog.toys.keys))
        XCTAssertTrue(Set(ItemCatalog.toys.keys).isDisjoint(with: Wear.table.keys))
        // Всё из ролей — из пулов.
        for id in ItemCatalog.decor.union(ItemCatalog.toys.keys) { XCTAssertTrue(ids.contains(id), id) }
        XCTAssertEqual(ItemCatalog.emoji("nope"), "📦")
        XCTAssertNil(ItemCatalog.role("nope"))
        XCTAssertNil(ItemArt.layers("nope"))
    }

    func testEveryRarityHasEveryRoleSomewhere() {
        // В каждой редкости, кроме легендарной, есть и что надеть, и что поставить, и мячик.
        for r in [Rarity.common, .rare, .epic] {
            let roles = Set((EconomyConfig.shared.capsule.pools[r] ?? []).compactMap { ItemCatalog.role($0.id) })
            XCTAssertEqual(roles, [.wear, .decor, .toy], r.rawValue)
        }
    }

    func testArtInsideUnitSquare() {
        for (id, layers) in ItemArt.table {
            XCTAssertGreaterThanOrEqual(layers.count, 2, "\(id): иконка из одного пятна не читается")
            for l in layers {
                let b = l.shape.bounds
                XCTAssertGreaterThanOrEqual(b.lo.x, -1e-6, id)
                XCTAssertGreaterThanOrEqual(b.lo.y, -1e-6, id)
                XCTAssertLessThanOrEqual(b.hi.x, 1 + 1e-6, id)
                XCTAssertLessThanOrEqual(b.hi.y, 1 + 1e-6, id)
                if case .poly(let p) = l.shape { XCTAssertGreaterThanOrEqual(p.count, 3, id) }
            }
        }
    }

    func testNewWearablesHaveOwnShapes() {
        XCTAssertEqual(Wear.info("beret_red")?.shape, .beret)
        XCTAssertEqual(Wear.info("crown_champion")?.slot, .head)
        XCTAssertEqual(Wear.info("bell_collar")?.slot, .neck)
        XCTAssertEqual(Wear.info("bowtie_dots")?.slot, .neck)
        XCTAssertEqual(Wear.info("backpack_mini")?.slot, .back)
        XCTAssertEqual(Wear.info("wreath_autumn")?.shape, .wreath)
    }

    // MARK: полка и мячик

    func testShelfToggle() {
        var f = iFile(["lamp_mushroom", "trophy_cup", "leaf_hat"])
        XCTAssertNil(ItemCatalog.shelf(f))
        XCTAssertEqual(try ItemCatalog.toggleShelf(&f, "lamp_mushroom").get(), true)
        XCTAssertEqual(ItemCatalog.shelf(f), "lamp_mushroom")
        // Другая вещь заменяет прежнюю.
        XCTAssertEqual(try ItemCatalog.toggleShelf(&f, "trophy_cup").get(), true)
        XCTAssertEqual(ItemCatalog.shelf(f), "trophy_cup")
        XCTAssertEqual(try ItemCatalog.toggleShelf(&f, "trophy_cup").get(), false)
        XCTAssertNil(ItemCatalog.shelf(f))
        XCTAssertNil(f.shelf)
        // Отказы: чужое и шапка.
        XCTAssertEqual(ItemCatalog.toggleShelf(&f, "acorn_jar"), .failure(.notOwned))
        XCTAssertEqual(ItemCatalog.toggleShelf(&f, "leaf_hat"), .failure(.wrongRole))
        XCTAssertNil(f.shelf)
        // Мусор в файле не показывается.
        f.shelf = "acorn_jar"
        XCTAssertNil(ItemCatalog.shelf(f))
        f.shelf = "leaf_hat"
        XCTAssertNil(ItemCatalog.shelf(f))
    }

    func testToyToggle() {
        var f = iFile(["ball_tennis", "ball_star", "trophy_cup"])
        XCTAssertNil(ItemCatalog.toy(f), "без выбора — обычный мячик")
        XCTAssertEqual(try ItemCatalog.toggleToy(&f, "ball_tennis").get(), true)
        XCTAssertEqual(ItemCatalog.toy(f), "ball_tennis")
        XCTAssertEqual(try ItemCatalog.toggleToy(&f, "ball_star").get(), true)
        XCTAssertEqual(ItemCatalog.toy(f), "ball_star")
        XCTAssertEqual(try ItemCatalog.toggleToy(&f, "ball_star").get(), false)
        XCTAssertNil(ItemCatalog.toy(f))
        XCTAssertEqual(ItemCatalog.toggleToy(&f, "ball_pumpkin"), .failure(.notOwned))
        XCTAssertEqual(ItemCatalog.toggleToy(&f, "trophy_cup"), .failure(.wrongRole))
        for (id, t) in ItemCatalog.toys { XCTAssertNotEqual(t.color, t.accent, id) }
    }

    func testSaveFieldsRoundTripAndOldFile() throws {
        var f = iFile(["lamp_mushroom", "ball_tennis"])
        let empty = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(f)) as? [String: Any])
        XCTAssertNil(empty["shelf"], "пустое не пишется")
        XCTAssertNil(empty["toy"])
        XCTAssertNil(empty["shop"])

        _ = ItemCatalog.toggleShelf(&f, "lamp_mushroom")
        _ = ItemCatalog.toggleToy(&f, "ball_tennis")
        ShopDaily.roll(&f, now: iT0)
        let data = try JSONEncoder().encode(f)
        let back = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(back.shelf, "lamp_mushroom")
        XCTAssertEqual(back.toy, "ball_tennis")
        XCTAssertEqual(back.shop, f.shop)

        // Старый сейв без полей и с кривыми полями читается, остальное цело.
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj["shelf"] = nil
        obj["toy"] = nil
        obj["shop"] = nil
        let old = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(old.shelf)
        XCTAssertNil(old.toy)
        XCTAssertNil(old.shop)
        XCTAssertEqual(old.econ.items["ball_tennis"], 1)
        obj["shelf"] = 5
        obj["toy"] = ["x": 1]
        obj["shop"] = ["day": "вчера", "ids": [1, 2]]
        let bad = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(bad.shelf)
        XCTAssertNil(bad.toy)
        XCTAssertEqual(bad.petId, f.petId)
        XCTAssertEqual(bad.econ.items["lamp_mushroom"], 1)
        // Кривая витрина — просто новая на сегодня.
        XCTAssertEqual(ShopDaily.today(bad, now: iT0).ids.count, 3)
    }

    func testStoreShelfToyAndStartOver() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-items")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: iT0)
        try store.mutate { (f: inout SaveFile) -> Void in
            f.econ.items["trophy_cup"] = 1
            f.econ.items["ball_star"] = 1
        }
        XCTAssertEqual(try ItemCatalog.performShelf("trophy_cup", store: store).get(), true)
        XCTAssertEqual(try ItemCatalog.performToy("ball_star", store: store).get(), true)
        try store.startOver(now: iT0 + 100)
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(ItemCatalog.shelf(f), "trophy_cup", "полка переживает щенка, как и предметы")
        XCTAssertEqual(ItemCatalog.toy(f), "ball_star")
    }
}

final class ShopDailyTests: XCTestCase {
    func testPickDeterministicThreeRarities() {
        let cfg = EconomyConfig.shared.capsule
        let byId = cfg.itemsById
        let day = DayKey.of(iT0)
        let a = ShopDaily.pick(petId: "dog-1", day: day, owned: [])
        XCTAssertEqual(a, ShopDaily.pick(petId: "dog-1", day: day, owned: []), "тот же день — та же витрина")
        XCTAssertEqual(a.count, 3)
        XCTAssertEqual(Set(a).count, 3)
        XCTAssertEqual(a.compactMap { byId[$0]?.rarity }, [.common, .rare, .epic])
        // За неделю витрина меняется хотя бы раз, а у другой собаки в тот же день — своя хотя бы иногда.
        let week = (0..<7).map { ShopDaily.pick(petId: "dog-1", day: day + $0, owned: []) }
        XCTAssertGreaterThan(Set(week).count, 1)
        let other = (0..<7).map { ShopDaily.pick(petId: "dog-2", day: day + $0, owned: []) }
        XCTAssertNotEqual(week, other)
        // Легендарных не бывает никогда.
        for d in 0..<60 {
            for id in ShopDaily.pick(petId: "dog-1", day: day + d, owned: []) {
                XCTAssertNotEqual(byId[id]?.rarity, .legendary)
            }
        }
    }

    func testPickPrefersMissing() {
        let cfg = EconomyConfig.shared.capsule
        let day = DayKey.of(iT0)
        let commons = (cfg.pools[.common] ?? []).map(\.id)
        // Есть всё обычное, кроме одного, — на витрине именно оно.
        for missing in commons {
            let owned = Set(commons).subtracting([missing])
            XCTAssertEqual(ShopDaily.pick(petId: "dog-1", day: day, owned: owned).first, missing)
        }
        // Есть всё — витрина всё равно полная (покажет «Уже есть»).
        let all = Set(allIds)
        XCTAssertEqual(ShopDaily.pick(petId: "dog-1", day: day, owned: all).count, 3)
    }

    func testPricesInBands() {
        let b = ShopDaily.Bands()
        for r in Rarity.allCases {
            for it in EconomyConfig.shared.capsule.pools[r] ?? [] {
                let p = ShopDaily.price(it, b)
                let band = ItemCatalog.decor.contains(it.id) ? b.furniture[r]! : b.clothes[r]!
                XCTAssertTrue(band.contains(p), "\(it.id): \(p) мимо \(band)")
                XCTAssertEqual(p % 10, 0, it.id)
                XCTAssertEqual(p, ShopDaily.price(it, b), "цена не прыгает")
            }
        }
        // Конфиг читается из economy.json; пустой — значения по умолчанию.
        XCTAssertEqual(ShopDaily.Bands(json: .null), b)
        XCTAssertEqual(ShopDaily.bands.clothes[.rare], 300...600)
    }

    func testBuyFlow() throws {
        var f = iFile(coins: 50_000)
        let offers = ShopDaily.offers(f, now: iT0)
        XCTAssertEqual(offers.count, 3)
        XCTAssertTrue(offers.allSatisfy { $0.state == .buy(need: 0) })
        let o = offers[1]
        let coins = f.econ.wallet.coins
        XCTAssertEqual(ShopDaily.buy(o.id, in: &f, now: iT0), .ok(price: o.price))
        XCTAssertEqual(f.econ.wallet.coins, coins - o.price)
        XCTAssertEqual(f.econ.items[o.id], 1)
        let e = try XCTUnwrap(f.journal.last)
        XCTAssertEqual(e.kind, "shop.buy")
        XCTAssertEqual(e.key, o.id)
        XCTAssertEqual(e.value, o.price)
        // Повтор — «Куплено», витрина за день не перетасовалась.
        XCTAssertEqual(ShopDaily.buy(o.id, in: &f, now: iT0 + 60), .sold)
        let after = ShopDaily.offers(f, now: iT0 + 60)
        XCTAssertEqual(after.map(\.id), offers.map(\.id))
        XCTAssertEqual(after[1].state, .sold)
        XCTAssertEqual(ShopDaily.buttonTitle(after[1]), "Куплено")
        // Чего нет на витрине — не продаём.
        let notHere = allIds.first { !offers.map(\.id).contains($0) }!
        XCTAssertEqual(ShopDaily.buy(notHere, in: &f, now: iT0), .notOnShelf)
        XCTAssertEqual(ShopDaily.buy("nope", in: &f, now: iT0), .notOnShelf)
        XCTAssertNil(f.econ.items[notHere])
    }

    func testClockBackKeepsShelf() {
        // Волна 13: перевод часов назад (или перелёт на запад) не даёт новую витрину.
        var f = iFile(coins: 50_000)
        let offers = ShopDaily.offers(f, now: iT0)
        let o = offers[2]
        XCTAssertEqual(ShopDaily.buy(o.id, in: &f, now: iT0), .ok(price: o.price))
        ShopDaily.roll(&f, now: iT0 - 86_400)
        XCTAssertEqual(f.shop?.bought, [o.id], "вчерашняя витрина не затёрла сегодняшнюю")
        let back = ShopDaily.offers(f, now: iT0)
        XCTAssertEqual(back.map(\.id), offers.map(\.id))
        XCTAssertEqual(back[2].state, .sold)
        // Новые сутки — новая витрина, как раньше.
        ShopDaily.roll(&f, now: iT0 + 86_400)
        XCTAssertEqual(f.shop?.day, DayKey.of(iT0 + 86_400))
    }

    func testOwnedAndNoCoins() {
        var f = iFile()
        f.econ.wallet.coins = 10
        let s = ShopDaily.roll(&f, now: iT0)
        // Уже выпало из капсулы — «Уже есть», без списания.
        f.econ.items[s.ids[0]] = 1
        XCTAssertEqual(ShopDaily.offers(f, now: iT0)[0].state, .owned)
        XCTAssertEqual(ShopDaily.buy(s.ids[0], in: &f, now: iT0), .owned)
        XCTAssertEqual(f.econ.wallet.coins, 10)
        // Не хватает — ничего не меняется, кнопка честно пишет сколько.
        let o = ShopDaily.offers(f, now: iT0)[2]
        XCTAssertEqual(o.state, .buy(need: o.price - 10))
        XCTAssertEqual(ShopDaily.buttonTitle(o), "Не хватает \(o.price - 10)")
        let journal = f.journal.count
        XCTAssertEqual(ShopDaily.buy(o.id, in: &f, now: iT0), .noCoins(need: o.price - 10))
        XCTAssertEqual(f.econ.wallet.coins, 10)
        XCTAssertNil(f.econ.items[o.id])
        XCTAssertEqual(f.journal.count, journal)
        XCTAssertNotNil(ShopDaily.refusal(.noCoins(need: 5)))
        XCTAssertNil(ShopDaily.refusal(.ok(price: 5)))
    }

    func testShelfKeptForDayThenRolls() {
        var f = iFile(coins: 50_000)
        let s = ShopDaily.roll(&f, now: iT0)
        // Выпало из капсулы после открытия лавки — витрина та же (закреплена), карточка «Уже есть».
        f.econ.items[s.ids[1]] = 1
        XCTAssertEqual(ShopDaily.today(f, now: iT0 + 60).ids, s.ids)
        // Новые сутки — новая витрина, купленное вчера не мешает.
        let next = iT0 + ShopDaily.secondsToNext(now: iT0) + 1
        XCTAssertEqual(DayKey.of(next), s.day + 1)
        let t = ShopDaily.roll(&f, now: next)
        XCTAssertEqual(t.day, s.day + 1)
        XCTAssertTrue(t.bought.isEmpty)
        XCTAssertEqual(f.shop, t)
        let wait = ShopDaily.secondsToNext(now: iT0)
        XCTAssertGreaterThan(wait, 0)
        XCTAssertLessThanOrEqual(wait, 86400)
    }

    func testStorePerform() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-shopday")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: iT0)
        try store.mutate { (f: inout SaveFile) -> Void in Economy.grant(&f, coins: 9000) }
        try ShopDaily.open(store: store, now: iT0)
        let s = try XCTUnwrap(try XCTUnwrap(store.read()).shop)
        XCTAssertEqual(s.ids.count, 3)
        guard case .ok = try ShopDaily.perform(s.ids[0], store: store, now: iT0) else { return XCTFail("ждали покупку") }
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.econ.items[s.ids[0]], 1)
        XCTAssertEqual(f.shop?.bought, [s.ids[0]])
    }
}
