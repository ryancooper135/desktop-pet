// Волна 35 L: стоки клочков ✂️ — золотой шарик, вещи из очень редких находок, эксклюзивы мест.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let kT0: Double = 1_760_000_000

private func kFile(_ pet: String = "dog-1") -> SaveFile {
    var f = SaveFile.fresh(now: kT0)
    f.petId = pet
    return f
}

final class ScrapSinksTests: XCTestCase {
    // MARK: вещи в каталоге

    func testItemsAreRealItemsButNotInPools() {
        let cap = EconomyConfig.shared.capsule
        let pooled = Set(cap.pools.values.flatMap { $0 }.map(\.id))
        XCTAssertEqual(ScrapSinks.all.count, 16)
        XCTAssertEqual(Set(ScrapSinks.all.map(\.id)).count, 16, "id уникальны")
        for s in ScrapSinks.all {
            XCTAssertFalse(pooled.contains(s.id), "\(s.id) не в капсуле")
            XCTAssertNotNil(cap.itemsById[s.id], "\(s.id) в коллекции")
            XCTAssertNotNil(ItemCatalog.role(s.id), "\(s.id): роль")
            XCTAssertNotNil(PremiumConfig.shared.perks[s.id], "\(s.id): польза")
            XCTAssertNotEqual(ItemCatalog.emoji(s.id), "📦", s.id)
            XCTAssertNotNil(PlacesConfig.shared.place(s.place), "\(s.id): место \(s.place)")
            XCTAssertNil(PremiumConfig.shared.exclusive(s.id), "\(s.id): не в мастерской")
        }
        // Каждая очень редкая находка с ролью даёт вещь, и роль та же (light — полка со светом).
        for p in PlacesConfig.shared.places {
            for x in p.finds where x.role != nil {
                let it = try? XCTUnwrap(ScrapSinks.item(forFind: x.id), x.id)
                guard let it else { continue }
                let want: ItemRole = x.role == "toy" ? .toy : .decor
                XCTAssertEqual(ItemCatalog.role(it.id), want, x.id)
                XCTAssertEqual(it.place, p.id)
            }
            XCTAssertNotNil(ScrapSinks.exclusive(p.id), "у \(p.id) есть эксклюзив")
        }
        XCTAssertEqual(ItemCatalog.role("place_colander"), .wear)
        XCTAssertEqual(ItemCatalog.role("place_towel_scarf"), .wear)
        XCTAssertEqual(ItemCatalog.toys["found_pixel_ball"]?.pattern, .pixel)
    }

    func testShopDailyNeverOffersSinkItems() {
        let ids = Set(ScrapSinks.all.map(\.id))
        let day = DayKey.of(kT0)
        for d in 0..<60 {
            for id in ShopDaily.pick(petId: "dog-1", day: day + d, owned: []) { XCTAssertFalse(ids.contains(id)) }
        }
    }

    func testArtInsideUnitSquare() {
        for s in ScrapSinks.all {
            guard let layers = SinksArt.table[s.id] else { XCTFail("\(s.id): нет иконки"); continue }
            XCTAssertEqual(ItemArt.layers(s.id), layers)
            XCTAssertGreaterThanOrEqual(layers.count, 2, s.id)
            for l in layers {
                let b = l.shape.bounds
                XCTAssertGreaterThanOrEqual(b.lo.x, 0, s.id); XCTAssertGreaterThanOrEqual(b.lo.y, 0, s.id)
                XCTAssertLessThanOrEqual(b.hi.x, 1, s.id); XCTAssertLessThanOrEqual(b.hi.y, 1, s.id)
                if case .poly(let pts) = l.shape { XCTAssertGreaterThanOrEqual(pts.count, 3, s.id) }
            }
        }
        XCTAssertEqual(Set(SinksArt.table.keys), Set(ScrapSinks.all.map(\.id)), "лишних иконок нет")
    }

    func testColanderOnHead() {
        XCTAssertEqual(WearShape.colander.slot, .head)
        let parts = WearMesh.parts(.colander)
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts.contains { $0.accent } && parts.contains { !$0.accent })
        XCTAssertEqual(Wear.table["place_colander"]?.shape, .colander)
    }

    // MARK: находки → вещи

    func testGrantFindsOnceAndOnlyFound() {
        var f = kFile()
        XCTAssertEqual(ScrapSinks.grantFinds(&f, now: kT0), [])
        f.trip.album["bus_stop.key"] = 1
        f.trip.album["bus_stop.ticket"] = 3
        XCTAssertEqual(ScrapSinks.grantFinds(&f, now: kT0), ["found_key"])
        XCTAssertEqual(f.econ.items["found_key"], 1)
        XCTAssertEqual(f.journal.last?.kind, "sinks.find")
        XCTAssertEqual(ScrapSinks.grantFinds(&f, now: kT0), [], "второй раз — ничего")
        XCTAssertNil(f.econ.items["place_route_sign"], "эксклюзив находкой не выдаётся")
    }

    func testSettleGrantsVeryRareFindItem() {
        var f = kFile()
        f.trip.album["arcade.pixel_ball"] = 1    // старый сейв: находка уже была до волны 35
        f.pet.outing = nil
        f.trip.active = ActiveTrip(place: "bus_stop", from: kT0 - 3600, start: kT0 - 3600, until: kT0, star: false)
        let r = Places.settle(&f, now: kT0)
        XCTAssertNotNil(r)
        XCTAssertEqual(f.econ.items["found_pixel_ball"], 1, "дошла и до старого сейва")
        XCTAssertEqual(ItemCatalog.role("found_pixel_ball"), .toy)
    }

    func testFindLineSaysCollection() {
        let key = try! XCTUnwrap(Places.find("bus_stop.key"))
        XCTAssertTrue(Places.findLine(key, .veryRare, isNew: true).hasSuffix("— новое в альбоме и в коллекции"))
        let ticket = try! XCTUnwrap(Places.find("bus_stop.ticket"))
        XCTAssertTrue(Places.findLine(ticket, .common, isNew: true).hasSuffix("— новое в альбоме"))
    }

    // MARK: золотой шарик

    func testGoldenRarityOddsAndFallback() {
        let all: Set<Rarity> = [.rare, .epic, .legendary]
        XCTAssertEqual(ScrapSinks.goldenRarity(0, left: all), .rare)
        XCTAssertEqual(ScrapSinks.goldenRarity(84, left: all), .rare)
        XCTAssertEqual(ScrapSinks.goldenRarity(85, left: all), .epic)
        XCTAssertEqual(ScrapSinks.goldenRarity(97, left: all), .epic)
        XCTAssertEqual(ScrapSinks.goldenRarity(98, left: all), .legendary)
        XCTAssertEqual(ScrapSinks.goldenRarity(99, left: all), .legendary)
        XCTAssertEqual(ScrapSinks.goldenOdds.values.reduce(0, +), 100)
        // Выпавшей нет — ниже, ниже нечего — выше.
        XCTAssertEqual(ScrapSinks.goldenRarity(99, left: [.rare, .epic]), .epic)
        XCTAssertEqual(ScrapSinks.goldenRarity(99, left: [.rare]), .rare)
        XCTAssertEqual(ScrapSinks.goldenRarity(90, left: [.rare, .legendary]), .rare)
        XCTAssertEqual(ScrapSinks.goldenRarity(10, left: [.epic, .legendary]), .epic)
        XCTAssertEqual(ScrapSinks.goldenRarity(10, left: [.legendary]), .legendary)
        XCTAssertNil(ScrapSinks.goldenRarity(10, left: []))
    }

    func testGoldenOddsOverManyDogs() {
        var n: [Rarity: Int] = [:]
        let total = 4000
        for i in 0..<total {
            var f = kFile("dog-\(i)")
            f.econ.wallet.shards = 50
            guard case .success(let p) = ScrapSinks.golden(&f, now: kT0) else { return XCTFail() }
            n[p.rarity, default: 0] += 1
        }
        let pct = { (r: Rarity) in Double(n[r] ?? 0) * 100 / Double(total) }
        XCTAssertEqual(pct(.rare), 85, accuracy: 3)
        XCTAssertEqual(pct(.epic), 13, accuracy: 3)
        XCTAssertEqual(pct(.legendary), 2, accuracy: 1.5)
        XCTAssertNil(n[.common], "обычных не бывает")
    }

    func testGoldenNoRepeatsUntilAllOwnedAndPityUntouched() {
        var f = kFile()
        f.econ.wallet.shards = 49
        guard case .failure(.notEnough(need: 1)) = ScrapSinks.golden(&f, now: kT0) else { return XCTFail() }
        XCTAssertEqual(f.econ.wallet.shards, 49)
        let cap = EconomyConfig.shared.capsule
        let rarePlus = ScrapSinks.goldenTiers.flatMap { cap.pools[$0] ?? [] }
        f.econ.wallet.shards = 50 * rarePlus.count + 7
        let pity = f.econ.capsule
        var got: Set<String> = []
        for _ in rarePlus {
            guard case .success(let p) = ScrapSinks.golden(&f, now: kT0) else { return XCTFail() }
            XCTAssertGreaterThanOrEqual(p.rarity, .rare)
            XCTAssertEqual(p.item.rarity, p.rarity)
            XCTAssertFalse(p.duplicate)
            XCTAssertFalse(got.contains(p.item.id), "повтора нет")
            got.insert(p.item.id)
            XCTAssertEqual(f.journal.last?.kind, "golden")
        }
        XCTAssertEqual(got, Set(rarePlus.map(\.id)))
        XCTAssertFalse(ScrapSinks.goldenOpen(f))
        XCTAssertEqual(ScrapSinks.goldenNote(f), "Все редкие вещи уже у тебя")
        guard case .failure(.allOwned) = ScrapSinks.golden(&f, now: kT0) else { return XCTFail() }
        XCTAssertEqual(f.econ.wallet.shards, 7, "за отказ не списали")
        XCTAssertEqual(f.econ.capsule, pity, "гарант и счёт круток не трогаем")
    }

    func testGoldenSkipsOwnedCommonsAndSinkItems() {
        var f = kFile()
        // Есть все обычные и все вещи мест — шарик их не даёт и на них не смотрит.
        for it in EconomyConfig.shared.capsule.pools[.common] ?? [] { f.econ.items[it.id] = 1 }
        f.econ.wallet.shards = 500
        for _ in 0..<5 {
            guard case .success(let p) = ScrapSinks.golden(&f, now: kT0) else { return XCTFail() }
            XCTAssertNil(ScrapSinks.item(p.item.id))
            XCTAssertNotEqual(p.rarity, .common)
        }
    }

    // MARK: эксклюзив места

    func testPlaceExclusiveNeedsHalfTheFinds() throws {
        var f = kFile()
        let p = try XCTUnwrap(PlacesConfig.shared.place("rocket"))
        XCTAssertEqual(ScrapSinks.findsNeeded(p), 3)
        XCTAssertEqual(ScrapSinks.placeState(f, p), .locked(left: 3))
        guard case .failure(.fewFinds(left: 3)) = ScrapSinks.buyPlace("rocket", in: &f, now: kT0) else { return XCTFail() }
        f.trip.album[p.finds[0].id] = 5          // повторы одной находки не в счёт
        XCTAssertEqual(ScrapSinks.placeState(f, p), .locked(left: 2))
        f.trip.album[p.finds[1].id] = 1
        f.trip.album[p.finds[2].id] = 1
        XCTAssertEqual(ScrapSinks.placeState(f, p), .buy(price: 120, canAfford: false))
        f.econ.wallet.shards = 119
        guard case .failure(.notEnough(need: 1)) = ScrapSinks.buyPlace("rocket", in: &f, now: kT0) else { return XCTFail() }
        f.econ.wallet.shards = 130
        XCTAssertEqual(ScrapSinks.placeState(f, p), .buy(price: 120, canAfford: true))
        guard case .success(let it) = ScrapSinks.buyPlace("rocket", in: &f, now: kT0) else { return XCTFail() }
        XCTAssertEqual(it.id, "place_colander")
        XCTAssertEqual(f.econ.wallet.shards, 10)
        XCTAssertEqual(f.journal.last?.kind, "sinks.place")
        XCTAssertEqual(ScrapSinks.placeState(f, p), .owned)
        guard case .failure(.owned) = ScrapSinks.buyPlace("rocket", in: &f, now: kT0) else { return XCTFail() }
        XCTAssertEqual(f.econ.wallet.shards, 10)
        guard case .failure(.unknown) = ScrapSinks.buyPlace("nowhere", in: &f, now: kT0) else { return XCTFail() }
        XCTAssertTrue(Wear.canWear("place_colander"))
    }

    func testTexts() {
        XCTAssertEqual(ScrapSinks.findsWord(1), "1 находку")
        XCTAssertEqual(ScrapSinks.findsWord(2), "2 находки")
        XCTAssertEqual(ScrapSinks.findsWord(5), "5 находок")
        XCTAssertEqual(ScrapSinks.refusalText(.notEnough(need: 7)), "Не хватает клочков: 7 ✂️")
        XCTAssertEqual(ScrapSinks.refusalText(.fewFinds(left: 2)), "Найди здесь ещё 2 находки")
        let it = ScrapSinks.exclusive("rocket")!
        XCTAssertEqual(ScrapSinks.placeButton(.buy(price: 120, canAfford: true), it), "🪖 Шапка-дуршлаг · 120 ✂️")
        XCTAssertTrue(ScrapSinks.placeNote(.locked(left: 1), have: 0).contains("ещё 1 находку"))
        XCTAssertTrue(ScrapSinks.placeNote(.buy(price: 120, canAfford: false), have: 100).contains("20 ✂️"))
        XCTAssertEqual(ScrapSinks.goldenNote(kFile()), "Только редкое и выше, без повторов")
    }
}
