// Улучшения дома без экрана: конфиг home_upgrades, покупка (монеты, уровень, журнал), отказы,
// автокормушка кухни после покупки, тексты баффов, дом переживает щенка, запас кухни в сейве.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let hT0: Double = 1_760_000_000

/// Новый сейв с монетами на всё.
private func hRich(_ coins: Int = 50_000) -> SaveFile {
    var f = SaveFile.fresh(now: hT0)
    Economy.grant(&f, coins: coins)
    return f
}

/// Пёс на уровне L (опыт и выплаты уже учтены — settle ничего не доплатит).
private func hLevel(_ f: inout SaveFile, _ l: Int) {
    f.level.started = true
    f.level.xp = DogLevel.xpTo(l)
    f.level.paidLevel = l
}

/// Плиты яруса «Подоконник» куплены — двор готов к «Дворику».
private func hSill(_ f: inout SaveFile) {
    f.yard.plates = ["window", "daisy"]
    f.yard.stations["dryer"] = 1
}

final class HomeShopTests: XCTestCase {

    // MARK: конфиг

    func testLinesFromEconomyJSON() {
        let all = HomeShop.shared
        XCTAssertEqual(all.map(\.id), HomeLine.allCases, "все шесть линий, в порядке HomeLine")
        for l in all {
            // волна 34 G: у двора пятый уровень — «Квартал»
            XCTAssertEqual(l.levels.count, l.id == .yard ? 5 : 4, "\(l.id): база + уровни")
            XCTAssertEqual(l.levels[0].price, 0, "\(l.id): стартовый уровень бесплатный")
            XCTAssertFalse(l.name.isEmpty)
        }
        let bath = try! XCTUnwrap(HomeShop.line(.bath))
        XCTAssertEqual(bath.levels.map(\.price), [0, 700, 1800, 4000])
        XCTAssertEqual(bath.levels[1].buff["bath_min"]?.double, 40)
        XCTAssertEqual(HomeShop.line(.kitchen)?.levels[1].buff["autofeed_below"]?.double, 10, "холодильник тоже кормит сам — иначе покупка пустая")
        XCTAssertEqual(HomeShop.line(.kitchen)?.levels[2].buff["autofeed_below"]?.double, 15)
    }

    func testEmptyConfigHasNoLines() {
        XCTAssertTrue(HomeShop.lines(.null).isEmpty)
        var f = hRich()
        XCTAssertEqual(HomeShop.buy(.bath, in: &f, now: hT0, []), .unknown)
    }

    // MARK: покупка

    func testBuySpendsCoinsRaisesLevelAndLogs() {
        var f = hRich(1000)
        let coins = f.econ.wallet.coins
        XCTAssertEqual(HomeShop.level(f, .bath), 0)
        XCTAssertEqual(HomeShop.next(f, .bath)?.index, 1)

        XCTAssertEqual(HomeShop.buy(.bath, in: &f, now: hT0 + 60), .ok(level: 1, price: 700))
        XCTAssertEqual(f.econ.wallet.coins, coins - 700)
        XCTAssertEqual(HomeShop.level(f, .bath), 1)
        XCTAssertEqual(f.pet.home[.bath], 1, "уровень лежит в PetState.home — его читает ядро")
        let e = try! XCTUnwrap(f.journal.last)
        XCTAssertEqual(e.kind, "home.buy")
        XCTAssertEqual(e.key, "bath")
        XCTAssertEqual(e.value, 1)
        XCTAssertEqual(f.pet.t, hT0 + 60, accuracy: 60, "питомец догнан до покупки")
    }

    func testNotEnoughCoinsChangesNothing() {
        var f = SaveFile.fresh(now: hT0)
        let coins = f.econ.wallet.coins
        XCTAssertLessThan(coins, 700)
        let journal = f.journal.count
        XCTAssertEqual(HomeShop.buy(.bath, in: &f, now: hT0), .noCoins(need: 700 - coins))
        XCTAssertEqual(f.econ.wallet.coins, coins)
        XCTAssertEqual(HomeShop.level(f, .bath), 0)
        XCTAssertEqual(f.journal.count, journal)
    }

    func testMaxedAfterLastLevel() {
        var f = hRich()
        hLevel(&f, 12)
        for want in 1...3 {
            XCTAssertEqual(HomeShop.buy(.kennel, in: &f, now: hT0), .ok(level: want, price: HomeShop.line(.kennel)!.levels[want].price))
        }
        let coins = f.econ.wallet.coins
        XCTAssertNil(HomeShop.next(f, .kennel))
        XCTAssertEqual(HomeShop.buy(.kennel, in: &f, now: hT0), .maxed)
        XCTAssertEqual(f.econ.wallet.coins, coins)
        XCTAssertEqual(HomeShop.level(f, .kennel), 3)
    }

    func testLinesAreIndependent() {
        var f = hRich()
        hLevel(&f, 5)
        hSill(&f)
        HomeShop.buy(.bed, in: &f, now: hT0)
        HomeShop.buy(.bed, in: &f, now: hT0)
        HomeShop.buy(.yard, in: &f, now: hT0)
        XCTAssertEqual(HomeShop.level(f, .bed), 2)
        XCTAssertEqual(HomeShop.level(f, .yard), 1)
        XCTAssertEqual(HomeShop.level(f, .bath), 0)
    }

    // MARK: гейт по уровню пса (волна 34 G)

    func testSecondLevelNeedsDogLevel5() {
        var f = hRich()
        XCTAssertEqual(HomeShop.buy(.bed, in: &f, now: hT0), .ok(level: 1, price: HomeShop.line(.bed)!.levels[1].price))
        let coins = f.econ.wallet.coins
        let journal = f.journal.count
        XCTAssertEqual(HomeShop.gate(f, .bed), .level(5))
        XCTAssertEqual(HomeShop.buy(.bed, in: &f, now: hT0), .needLevel(5))
        XCTAssertEqual(f.econ.wallet.coins, coins, "отказ не списывает")
        XCTAssertEqual(HomeShop.level(f, .bed), 1)
        XCTAssertEqual(f.journal.count, journal)
        hLevel(&f, 5)
        XCTAssertNil(HomeShop.gate(f, .bed))
        XCTAssertEqual(HomeShop.buy(.bed, in: &f, now: hT0), .ok(level: 2, price: HomeShop.line(.bed)!.levels[2].price))
        XCTAssertEqual(HomeShop.buy(.bed, in: &f, now: hT0), .needLevel(12))
        hLevel(&f, 12)
        XCTAssertEqual(HomeShop.buy(.bed, in: &f, now: hT0), .ok(level: 3, price: HomeShop.line(.bed)!.levels[3].price))
    }

    func testNeedLevelTable() {
        XCTAssertEqual(HomeShop.needLevel(.bath, index: 1), 0)
        XCTAssertEqual(HomeShop.needLevel(.bath, index: 2), 5)
        XCTAssertEqual(HomeShop.needLevel(.kitchen, index: 3), 12)
        XCTAssertEqual(HomeShop.needLevel(.yard, index: 1), 4)
        XCTAssertEqual(HomeShop.needLevel(.yard, index: 2), 9)
        XCTAssertEqual(HomeShop.needLevel(.yard, index: 3), 12)
        XCTAssertEqual(HomeShop.needLevel(.yard, index: 4), 20)
    }

    func testYardTierNeedsPlatesThenLevel() {
        var f = hRich()
        hLevel(&f, 4)
        XCTAssertEqual(HomeShop.buy(.yard, in: &f, now: hT0), .needPlates(3), "окно, ромашка, сушилка")
        hSill(&f)
        hLevel(&f, 3)
        XCTAssertEqual(HomeShop.buy(.yard, in: &f, now: hT0), .needLevel(4))
        hLevel(&f, 4)
        let coins = f.econ.wallet.coins
        XCTAssertEqual(HomeShop.buy(.yard, in: &f, now: hT0 + 60), .ok(level: 1, price: 700))
        XCTAssertEqual(f.econ.wallet.coins, coins - 700)
        let tier = try! XCTUnwrap(f.journal.last { $0.kind == "yard.tier" })
        XCTAssertEqual(tier.value, 1)
        // Опыт за ярус придёт со следующим settle.
        let xp = f.level.xp
        DogLevel.settle(&f, now: hT0 + 120)
        XCTAssertGreaterThanOrEqual(f.level.xp - xp, 25)
    }

    func testKvartalIsTopYardTier() {
        var f = hRich(20_000)
        f.pet.home[.yard] = 3
        // все плиты ярусов 0…3 без кухонных
        for p in YardConfig.shared.plates where p.tier < 4 && p.kitchen == 0 {
            if p.isStation { f.yard.stations[p.id] = 1 } else { f.yard.plates.append(p.id) }
        }
        hLevel(&f, 19)
        XCTAssertEqual(HomeShop.next(f, .yard)?.level.name, "Квартал")
        XCTAssertEqual(HomeShop.buy(.yard, in: &f, now: hT0), .needLevel(20))
        hLevel(&f, 20)
        XCTAssertEqual(HomeShop.buy(.yard, in: &f, now: hT0), .ok(level: 4, price: 9000))
        XCTAssertEqual(HomeShop.buy(.yard, in: &f, now: hT0), .maxed)
    }

    func testOldSaveKeepsBoughtLevels() {
        var f = hRich()
        f.pet.home[.bath] = 3
        f.pet.home[.yard] = 3
        f.pet.home[.bed] = 2
        hLevel(&f, 1)
        PetRunner.catchUp(&f, now: hT0 + 3600)
        XCTAssertEqual(HomeShop.level(f, .bath), 3, "купленное не отнимаем")
        XCTAssertEqual(HomeShop.level(f, .yard), 3)
        XCTAssertEqual(HomeShop.level(f, .bed), 2)
        XCTAssertEqual(HomeShop.buy(.bath, in: &f, now: hT0 + 3600), .maxed)
        XCTAssertEqual(HomeShop.buy(.bed, in: &f, now: hT0 + 3600), .needLevel(12))
        XCTAssertEqual(HomeShop.level(f, .bed), 2)
    }

    // MARK: кухня в деле

    func testKitchenAutofeedAfterPurchase() {
        var f = hRich()
        hLevel(&f, 5)
        HomeShop.buy(.kitchen, in: &f, now: hT0)
        HomeShop.buy(.kitchen, in: &f, now: hT0)
        XCTAssertEqual(HomeShop.level(f, .kitchen), 2)
        // Покормить, когда можно (ночью ядро может отказать), — кормёжка наполняет запас кухни.
        var t = hT0
        while !PetRunner.apply(.feed("stew"), source: .app, to: &f, now: t).ok {
            t += 1800
            XCTAssertLessThan(t, hT0 + 86400, "за сутки ни разу не дали покормить")
            if t >= hT0 + 86400 { return }
        }
        XCTAssertEqual(f.pet.pantry, 30, "кухня L2: запас 30")
        // Уходим на двое суток: сытость падает ниже 15 — ест из кормушки.
        PetRunner.catchUp(&f, now: t + 2 * 86400)
        XCTAssertLessThan(f.pet.pantry, 30, "автокормушка взяла из запаса")
    }

    func testNoAutofeedWithoutKitchen() {
        var f = hRich()
        var t = hT0
        while !PetRunner.apply(.feed("stew"), source: .app, to: &f, now: t).ok {
            t += 1800
            if t >= hT0 + 86400 { return XCTFail("за сутки ни разу не дали покормить") }
        }
        XCTAssertEqual(f.pet.pantry, 5, "базовая кухня: запас 5, но кормушки нет")
        PetRunner.catchUp(&f, now: t + 2 * 86400)
        XCTAssertEqual(f.pet.pantry, 5, "без autofeed_below запас не тратится")
    }

    // MARK: тексты

    func testPerks() {
        let bath1 = HomeShop.line(.bath)!.levels[1].buff
        XCTAssertEqual(HomeShop.perks(bath1), ["Мытьё 40 мин", "Пачкается на 10% медленнее"])
        let kitchen = HomeShop.line(.kitchen)!.levels
        XCTAssertEqual(HomeShop.perks(kitchen[1].buff), ["Запас еды: 15", "Сам ест из запаса, когда сытость ниже 10"])
        XCTAssertEqual(HomeShop.perks(["storage": .number(15)]), [], "запас без кормушки ядро не тратит — не обещаем")
        XCTAssertEqual(HomeShop.perks(kitchen[2].buff),
                       ["Запас еды: 30", "Сам ест из запаса, когда сытость ниже 15"])
        let k3 = HomeShop.perks(kitchen[3].buff)
        // волна 12: скидку и готовку применяет приложение (Cooking.swift) — теперь их показываем
        XCTAssertEqual(k3, ["Запас еды: 60", "Сам ест из запаса, когда сытость ниже 25",
                            "Еда в «Угостить» на 10% дешевле", "Готовка: блюда сытнее еды, первое за день — с подарком"])
        XCTAssertEqual(HomeShop.perks(HomeShop.line(.kennel)!.levels[3].buff),
                       ["Сердечки тают на 45% медленнее", "Сердечки растут на 50% быстрее", "Сердечек до 6"])
        XCTAssertEqual(HomeShop.perks([:]), [])
    }

    // MARK: сейв

    func testStartOverKeepsHouse() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-home")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: hT0)
        try store.mutate { (f: inout SaveFile) -> Void in
            Economy.grant(&f, coins: 5000)
            HomeShop.buy(.kitchen, in: &f, now: hT0)
            HomeShop.buy(.bath, in: &f, now: hT0)
        }
        let before = try XCTUnwrap(store.read())
        try store.startOver(now: hT0 + 3600)
        let after = try XCTUnwrap(store.read())
        XCTAssertNotEqual(after.petId, before.petId, "новый щенок")
        XCTAssertEqual(HomeShop.level(after, .kitchen), 1)
        XCTAssertEqual(HomeShop.level(after, .bath), 1)
    }

    func testPantryRoundTrip() throws {
        var f = SaveFile.fresh(now: hT0)
        f.pet.pantry = 42
        f.pet.home[.kitchen] = 3
        let back = PetState(json: PetCodec.json(f.pet))
        XCTAssertEqual(back.pantry, 42)
        XCTAssertEqual(back.home[.kitchen], 3)
        // Старый сейв без поля — запас пуст.
        guard case .object(var o) = PetCodec.json(f.pet) else { return XCTFail("ждали объект") }
        o["pantry"] = nil
        XCTAssertEqual(PetState(json: .object(o)).pantry, 0)
    }
}
