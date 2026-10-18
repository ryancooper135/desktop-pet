// Экран «Дом» без экрана: строки линий, «что даёт следующий», цена и нехватка монет, подписи кнопки и отказов,
// покупка через стор. Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let oT0: Double = 1_760_000_000

/// Новый сейв ровно с coins монетами.
private func oFile(coins: Int) -> SaveFile {
    var f = SaveFile.fresh(now: oT0)
    f.econ.wallet.coins = coins
    return f
}

final class HomeOfferTests: XCTestCase {

    func testRowsForFreshSave() {
        let rows = HomeOffer.rows(oFile(coins: 650))
        XCTAssertEqual(rows.map(\.id), HomeLine.allCases)
        for r in rows {
            XCTAssertEqual(r.level, 0, "\(r.id): старт")
            XCTAssertEqual(r.top, 3)
            XCTAssertFalse(r.levelName.isEmpty)
            XCTAssertNotNil(r.next)
            XCTAssertEqual(r.next?.index, 1)
            XCTAssertFalse(r.next?.perks.isEmpty ?? true, "\(r.id): «Дальше» никогда не пустое")
        }
        let bath = rows[0]
        XCTAssertEqual(bath.name, "Ванная")
        XCTAssertEqual(bath.levelName, "Тазик")
        XCTAssertEqual(bath.perks, [])
        XCTAssertEqual(bath.next?.name, "Ванна")
        XCTAssertEqual(bath.next?.price, 700)
        XCTAssertEqual(bath.next?.need, 50)
        XCTAssertEqual(bath.next?.perks, ["Мытьё 40 мин", "Пачкается на 10% медленнее"])
        XCTAssertFalse(bath.canBuy)
        let play = rows.first { $0.id == .play }!
        XCTAssertEqual(play.next?.price, 500)
        XCTAssertEqual(play.next?.need, 0)
        XCTAssertTrue(play.canBuy)
    }

    func testKitchenFridgeFeedsItself() {
        let k = HomeOffer.rows(oFile(coins: 0)).first { $0.id == .kitchen }!
        XCTAssertEqual(k.levelName, "Миска")
        XCTAssertEqual(k.next?.name, "Холодильник")
        XCTAssertEqual(k.next?.perks, ["Запас еды: 15", "Сам ест из запаса, когда сытость ниже 10"],
                       "с 18.10 холодильник тоже кормит сам — пустых покупок нет")
    }

    func testRowAfterBuyAndAtTop() {
        var f = oFile(coins: 20_000)
        HomeShop.buy(.bed, in: &f, now: oT0)
        var bed = HomeOffer.rows(f).first { $0.id == .bed }!
        XCTAssertEqual(bed.level, 1)
        XCTAssertEqual(bed.levelName, "Лежанка")
        XCTAssertEqual(bed.perks, ["Высыпается на 15% быстрее"])
        XCTAssertEqual(bed.next?.name, "Кроватка с балдахином")

        HomeShop.buy(.bed, in: &f, now: oT0)
        HomeShop.buy(.bed, in: &f, now: oT0)
        bed = HomeOffer.rows(f).first { $0.id == .bed }!
        XCTAssertEqual(bed.level, 3)
        XCTAssertTrue(bed.maxed)
        XCTAssertFalse(bed.canBuy)
        XCTAssertNil(bed.next)
        XCTAssertEqual(HomeOffer.buttonTitle(bed), "Лучший уровень")
    }

    func testLevelOutOfRangeIsClamped() {
        var f = oFile(coins: 0)
        f.pet.home[.yard] = 9   // битый сейв
        let y = HomeOffer.rows(f).first { $0.id == .yard }!
        XCTAssertEqual(y.level, 3)
        XCTAssertEqual(y.levelName, "Парк")
        XCTAssertTrue(y.maxed)
    }

    func testButtonTitles() {
        let rows = HomeOffer.rows(oFile(coins: 600))
        XCTAssertEqual(HomeOffer.buttonTitle(rows.first { $0.id == .bath }!), "Не хватает 100")
        XCTAssertEqual(HomeOffer.buttonTitle(rows.first { $0.id == .bed }!), "Купить", "ровно хватает")
    }

    func testRefusalAndBoughtTexts() {
        XCTAssertNil(HomeOffer.refusal(.ok(level: 1, price: 700)))
        XCTAssertEqual(HomeOffer.refusal(.noCoins(need: 35)), EconText.notEnough(need: 35))
        XCTAssertTrue(HomeOffer.refusal(.noCoins(need: 35))?.contains("35") ?? false)
        XCTAssertEqual(HomeOffer.refusal(.maxed), HomeOffer.maxedText)
        XCTAssertNotNil(HomeOffer.refusal(.unknown))

        XCTAssertEqual(HomeOffer.bought(.ok(level: 1, price: 700), line: .bath), "Готово: Ванна")
        XCTAssertNil(HomeOffer.bought(.maxed, line: .bath))
        XCTAssertNil(HomeOffer.bought(.ok(level: 7, price: 0), line: .bath))
    }

    func testEmptyConfigHasNoRows() {
        XCTAssertTrue(HomeOffer.rows(oFile(coins: 100), []).isEmpty)
    }

    func testPerformWritesStore() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-home-offer")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: oT0)
        try store.mutate { (f: inout SaveFile) -> Void in f.econ.wallet.coins = 800 }

        XCTAssertEqual(try HomeOffer.perform(.bath, store: store, now: oT0 + 60), .ok(level: 1, price: 700))
        var f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.econ.wallet.coins, 100)
        XCTAssertEqual(HomeShop.level(f, .bath), 1)
        XCTAssertEqual(f.journal.last?.kind, "home.buy")

        let again = try HomeOffer.perform(.bath, store: store, now: oT0 + 120)
        XCTAssertEqual(again, .noCoins(need: 1700))
        f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.econ.wallet.coins, 100, "отказ ничего не списал")
        XCTAssertEqual(HomeShop.level(f, .bath), 1)
    }
}
