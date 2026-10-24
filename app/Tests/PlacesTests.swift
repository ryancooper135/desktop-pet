// Волна 33 D: карта необычных мест и походы поверх прогулки. Конфиг совпадает с config/places.json,
// поход без прогулки не начинается, с похода ровно одна находка, всё решает хеш, полный набор платит один раз,
// ✂️ не больше одного за поход, у каждого события есть текст записки, колодец — раз в сутки.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let pT0: Double = 1_760_000_000

/// Свежий файл на момент t, все шкалы на level.
private func pFile(at t: Double, level: Double = 90) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = level }
    f.lastSeenT = t
    return f
}

/// Утро: питомец бодр и до ночи больше 4 часов — любой поход влезает.
private func pMorning() throws -> Double {
    let r = Catalog.rules
    let probe = SaveFile.fresh(now: pT0)
    var t = pT0
    while t < pT0 + 3 * 86400 {
        let o = PetRunner.owner(probe, at: t)
        if !PetEngine.petNight(t, r, o) && PetEngine.petNight(t - 3600, r, o)
            && !(0...8).contains(where: { PetEngine.petNight(t + 3600 + Double($0) * 1800, r, o) }) { return t }
        t += 600
    }
    throw XCTSkip("нет утра за трое суток")
}

/// Поход на id «кончился» к моменту t: прогулки нет, поход висит — settle его закрывает.
@discardableResult
private func pBack(_ f: inout SaveFile, _ id: String, star: Bool = false, at t: Double) -> TripResult? {
    f.pet.outing = nil
    f.trip.active = ActiveTrip(place: id, from: t - 3600, start: t - 3600, until: t, star: star)
    return Places.settle(&f, now: t)
}

private func trip(_ r: Result<ActiveTrip, PlaceRefusal>) -> ActiveTrip? {
    if case .success(let a) = r { return a }
    return nil
}

private func refusal<T>(_ r: Result<T, PlaceRefusal>) -> PlaceRefusal? {
    if case .failure(let e) = r { return e }
    return nil
}

final class PlacesTests: XCTestCase {

    // MARK: сохранение

    func testEmptyIsNotWritten() throws {
        let f = SaveFile.fresh(now: 1_760_054_400)
        let data = try JSONEncoder().encode(f)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(obj?["trip"], "пустое поле не пишется в сейв")
        XCTAssertNoThrow(try JSONDecoder().decode(SaveFile.self, from: data))
    }

    func testRoundTripAndTolerantDecode() throws {
        var f = pFile(at: pT0)
        let r = try XCTUnwrap(pBack(&f, "bus_stop", at: pT0 + 7200))
        XCTAssertFalse(f.trip.isEmpty)
        let data = try JSONEncoder().encode(f)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(obj?["trip"])
        let back = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(back.trip, f.trip)
        XCTAssertEqual(back.trip.last, r)

        // Чужие поля и битые значения не валят сейв.
        let odd = Data(#"{"count":3,"visits":{"bus_stop":2},"album":"нет","bogus":1}"#.utf8)
        let t = try JSONDecoder().decode(TripLog.self, from: odd)
        XCTAssertEqual(t.count, 3)
        XCTAssertEqual(t.visits, ["bus_stop": 2])
        XCTAssertEqual(t.album, [:])
        XCTAssertTrue(try JSONDecoder().decode(TripLog.self, from: Data("{}".utf8)).isEmpty)
    }

    // MARK: конфиг и содержимое

    func testConfigFileMatchesDefaults() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("config/places.json")
        let e = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        let c = PlacesConfig(json: e)
        XCTAssertEqual(c.places.count, 8, "все места из файла разобрались")
        XCTAssertEqual(c, PlacesConfig(), "значения по умолчанию — те же, что в config/places.json")
        XCTAssertEqual(PlacesConfig(json: .null), PlacesConfig())
    }

    func testConfigOverridesAndBrokenList() throws {
        let j = #"{"places":{"tiers_pct":{"rare":30,"very_rare":7},"repeat_coins":7,"well":{"coins":15},"list":[{"id":"x"}]}}"#
        let c = PlacesConfig(json: try JSONDecoder().decode(JSONValue.self, from: Data(j.utf8)))
        XCTAssertEqual(c.rarePct, 30)
        XCTAssertEqual(c.veryRarePct, 7)
        XCTAssertEqual(c.repeatCoins, 7)
        XCTAssertEqual(c.wellCoins, 15)
        XCTAssertEqual(c.places, PlacesConfig.stubPlaces, "битое место — список остаётся встроенным")
        XCTAssertEqual(Places.odds(star: false, c), [.common: 63, .rare: 30, .veryRare: 7])
    }

    func testEightPlacesContent() {
        let c = PlacesConfig()
        XCTAssertEqual(c.places.count, 8)
        XCTAssertEqual(Set(c.places.map(\.id)).count, 8)
        XCTAssertEqual(c.places.map(\.level), c.places.map(\.level).sorted(), "на карте по порядку открытия")
        XCTAssertEqual(c.places.map(\.minutes), c.places.map(\.minutes).sorted(), "дальше — дольше")
        var ids = Set<String>()
        for p in c.places {
            XCTAssertFalse(p.name.isEmpty, p.id)
            XCTAssertFalse(p.emoji.isEmpty, p.id)
            XCTAssertFalse(p.about.isEmpty, "\(p.id): подпись для бумажной карты")
            XCTAssertEqual(p.finds.count, 6, p.id)
            XCTAssertEqual(p.finds(.common).count, 3, p.id)
            XCTAssertEqual(p.finds(.rare).count, 2, p.id)
            XCTAssertEqual(p.finds(.veryRare).count, 1, p.id)
            XCTAssertNotNil(p.finds(.veryRare).first?.role, "\(p.id): очень редкая — будущая вещь")
            for x in p.finds {
                XCTAssertTrue(x.id.hasPrefix(p.id + "."), x.id)
                XCTAssertFalse(x.name.isEmpty, x.id)
                XCTAssertFalse(x.emoji.isEmpty, x.id)
                XCTAssertTrue(ids.insert(x.id).inserted, "находка \(x.id) одна на всю карту")
                XCTAssertEqual(Places.find(x.id), x)
            }
            XCTAssertEqual(p.events.count, 3, p.id)
            XCTAssertEqual(Set(p.events.map(\.id)).count, 3, p.id)
            for ev in p.events {
                XCTAssertFalse(ev.text.isEmpty, "\(p.id).\(ev.id): у события есть записка")
                if ev.effect == .ticket { XCTAssertFalse(ev.spent?.isEmpty ?? true, "\(ev.id): текст, когда жетон уже был") }
                if ev.effect == .forecast { XCTAssertTrue(ev.text.contains("{forecast}"), ev.id) }
                if ev.effect != .forecast { XCTAssertFalse(ev.text.contains("{"), ev.id) }
            }
        }
        XCTAssertNotNil(c.place(c.wellPlace), "колодец стоит на карте")
        XCTAssertFalse(c.forecasts.isEmpty)
    }

    // MARK: открытие и время

    func testUnlockByDogLevel() {
        XCTAssertTrue(Places.unlocked(dogLevel: 1).isEmpty)
        XCTAssertEqual(Places.unlocked(dogLevel: 2).map(\.id), ["bus_stop"])
        XCTAssertEqual(Places.unlocked(dogLevel: 11).count, 4)
        XCTAssertEqual(Places.unlocked(dogLevel: 30).count, 8)
        let f = pFile(at: pT0)
        XCTAssertEqual(Places.check("rocket", f, dogLevel: 29), .locked(level: 30))
        XCTAssertNil(Places.check("rocket", f, dogLevel: 30))
        XCTAssertEqual(Places.check("nowhere", f, dogLevel: 30), .unknown)
        let cards = Places.cards(f, dogLevel: 8, now: pT0)
        XCTAssertEqual(cards.map(\.id), PlacesConfig().places.map(\.id))
        XCTAssertEqual(cards.filter(\.open).count, 3)
        XCTAssertEqual(cards.last?.line, "Откроется на 30 уровне")
        XCTAssertEqual(cards.first?.line, "Находки 0 из 6")
    }

    func testMinutesGrowAndShrink() throws {
        let p = try XCTUnwrap(Places.place("bus_stop"))
        XCTAssertEqual(Places.minutes(p, dogLevel: 2), 30)
        XCTAssertEqual(Places.minutes(p, growthX: 1.3, dogLevel: 2), 39, "щенок ходит дольше")
        XCTAssertEqual(Places.minutes(p, growthX: 0.85, dogLevel: 2), 26, "взрослый быстрее")
        XCTAssertEqual(Places.minutes(p, dogLevel: 20), 27, "с 20 уровня ×0,9")
        let rocket = try XCTUnwrap(Places.place("rocket"))
        XCTAssertEqual(Places.minutes(rocket, growthX: 0.85, dogLevel: 30), 92)
        XCTAssertEqual(Places.durationText(30), "30 мин")
        XCTAssertEqual(Places.durationText(120), "2 ч")
        XCTAssertEqual(Places.durationText(105), "1 ч 45 мин")
    }

    // MARK: поход поверх прогулки

    func testNoOutingNoTrip() throws {
        let t = try pMorning()
        var f = pFile(at: t)
        XCTAssertEqual(refusal(Places.start("bus_stop", in: &f, dogLevel: 2, now: t)), .noOuting)
        XCTAssertNil(f.trip.active)
        XCTAssertNil(f.pet.outing, "start сам прогулку не начинает")
        XCTAssertTrue(f.trip.isEmpty)
        XCTAssertNil(Places.settle(&f, now: t + 3600), "без похода нечего закрывать")
    }

    func testStartOnTopOfWalk() throws {
        let t = try pMorning()
        var f = pFile(at: t)
        XCTAssertTrue(PetRunner.apply(.walk, source: .app, to: &f, now: t).ok)
        let out = try XCTUnwrap(f.pet.outing)
        let a = try XCTUnwrap(trip(Places.start("cat_hill", in: &f, dogLevel: 8, now: t + 60)))
        XCTAssertEqual(a.from, out.from)
        XCTAssertEqual(a.start, t + 60)
        XCTAssertEqual(a.until, t + 60 + 50 * 60, "время похода — время места")
        XCTAssertEqual(f.pet.outing?.until, a.until, "прогулка ядра вернётся вместе с походом")
        XCTAssertEqual(Places.current(f)?.id, "cat_hill")
        XCTAssertEqual(f.journal.last?.kind, "place.go")
        XCTAssertEqual(f.journal.last?.key, "cat_hill")
        XCTAssertEqual(refusal(Places.start("bus_stop", in: &f, dogLevel: 8, now: t + 120)), .busy)
    }

    func testGoChecksPlaceBeforeWalk() throws {
        let t = try pMorning()
        var f = pFile(at: t)
        XCTAssertEqual(refusal(Places.go("rocket", in: &f, dogLevel: 8, now: t)), .locked(level: 30))
        XCTAssertNil(f.pet.outing, "закрытое место не отправляет просто гулять")
        var tired = pFile(at: t, level: 10)
        if case .walk = refusal(Places.go("bus_stop", in: &tired, dogLevel: 2, now: t)) {} else {
            XCTFail("уставшего не пускает ядро")
        }
        XCTAssertNil(tired.trip.active)
        let a = try XCTUnwrap(trip(Places.go("bus_stop", in: &f, dogLevel: 2, growthX: 1.3, now: t)))
        XCTAssertEqual(a.until - a.start, 39 * 60)
        XCTAssertEqual(f.pet.outing?.from, t)
        XCTAssertEqual(f.pet.outing?.until, a.until)
    }

    func testReturnBringsExactlyOneFind() throws {
        let t = try pMorning()
        var f = pFile(at: t)
        let a = try XCTUnwrap(trip(Places.go("bus_stop", in: &f, dogLevel: 2, now: t)))
        PetRunner.catchUp(&f, now: a.until - 60)
        XCTAssertNil(Places.settle(&f, now: a.until - 60), "ещё гуляет")
        PetRunner.catchUp(&f, now: a.until + 600)
        XCTAssertNil(f.pet.outing, "прогулка ядра кончилась в until места")
        let r = try XCTUnwrap(Places.settle(&f, now: a.until + 600))
        XCTAssertEqual(f.trip.album.values.reduce(0, +), 1, "ровно одна находка места")
        XCTAssertTrue(r.isNew)
        XCTAssertEqual(r.coins, 0)
        XCTAssertEqual(r.t, a.until)
        XCTAssertNil(Places.settle(&f, now: a.until + 700), "второй раз не платит")
        XCTAssertEqual(f.trip.count, 1)
        XCTAssertEqual(f.trip.visits["bus_stop"], 1)
        XCTAssertEqual(r.xp, 25, "10 за поход + 15 за первый визит")
        XCTAssertEqual(f.trip.xp, 25)
        let tail = f.journal.suffix(2).map(\.kind)
        XCTAssertEqual(tail, ["place.back", "trip.first"], "первый визит — запись trip.first для опыта пса")
        XCTAssertEqual(f.journal.last(where: { $0.kind == "place.back" })?.value, 25)
        XCTAssertNil(f.trip.active)
        XCTAssertEqual(f.trip.last, r)
        let lines = Places.noteLines(r)
        XCTAssertTrue(r.star, "одно открытое место — оно и место дня")
        XCTAssertEqual(lines.first, "★ Остановка без автобуса")
        XCTAssertTrue(lines.contains(r.note))
        XCTAssertFalse(r.note.isEmpty)

        // Второй поход: опыт без бонуса первого визита.
        let t2 = a.until + 3600
        for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 90 }
        let r2 = try XCTUnwrap(pBack(&f, "bus_stop", at: t2))
        XCTAssertEqual(r2.xp, 10)
        XCTAssertEqual(f.trip.visits["bus_stop"], 2)
    }

    func testNewWalkIsNotOldTrip() throws {
        // Поход висит, но прогулка уже другая (вернулся и ушёл снова без места) — поход закрывается.
        var f = pFile(at: pT0)
        f.trip.active = ActiveTrip(place: "bus_stop", from: pT0 - 7200, start: pT0 - 7200, until: pT0 - 5400, star: false)
        f.pet.outing = Outing(from: pT0, until: pT0 + 3600, find: "stick")
        XCTAssertNil(Places.current(f))
        XCTAssertNotNil(Places.settle(&f, now: pT0))
        XCTAssertNil(f.trip.active)
    }

    func testDeadTripPaysNothing() {
        var f = pFile(at: pT0)
        f.pet.alive = false
        XCTAssertNil(pBack(&f, "bus_stop", at: pT0))
        XCTAssertNil(f.trip.active)
        XCTAssertTrue(f.trip.album.isEmpty)
        XCTAssertEqual(Places.check("bus_stop", f, dogLevel: 2), .dead)
    }

    // MARK: случайность по хешу

    func testDeterministic() {
        var a = pFile(at: pT0)
        var b = a   // тот же сейв (petId у свежего файла свой)
        for k in 0..<40 {
            let t = pT0 + Double(k) * 7200
            XCTAssertEqual(pBack(&a, "forest_tv", at: t), pBack(&b, "forest_tv", at: t))
        }
        XCTAssertEqual(a.trip, b.trip)
        XCTAssertEqual(a.econ.wallet, b.econ.wallet)
        XCTAssertEqual(Places.placeOfDay(a, dogLevel: 30, now: pT0), Places.placeOfDay(b, dogLevel: 30, now: pT0))
    }

    func testTierOdds() {
        XCTAssertEqual(Places.odds(star: false), [.common: 70, .rare: 25, .veryRare: 5])
        XCTAssertEqual(Places.odds(star: true), [.common: 40, .rare: 50, .veryRare: 10], "место дня: редкие ×2")
        for star in [false, true] {
            var f = pFile(at: pT0)
            var got: [FindTier: Int] = [:]
            let n = 3000
            for k in 0..<n {
                let r = pBack(&f, "lighthouse", star: star, at: pT0 + Double(k % 50) * 3600)
                got[r!.tier, default: 0] += 1
            }
            for (tier, pct) in Places.odds(star: star) {
                let share = Double(got[tier] ?? 0) * 100 / Double(n)
                XCTAssertEqual(share, Double(pct), accuracy: 3.5, "\(tier) star=\(star)")
            }
        }
    }

    func testPlaceOfDay() {
        let f = pFile(at: pT0)
        XCTAssertNil(Places.placeOfDay(f, dogLevel: 1, now: pT0))
        XCTAssertEqual(Places.placeOfDay(f, dogLevel: 2, now: pT0), "bus_stop", "одно открытое — оно и место дня")
        var seen = Set<String>()
        for d in 0..<60 {
            let id = Places.placeOfDay(f, dogLevel: 30, now: pT0 + Double(d) * 86400)
            XCTAssertNotNil(id)
            seen.insert(id!)
        }
        XCTAssertGreaterThan(seen.count, 4, "место дня меняется")
        XCTAssertEqual(Places.cards(f, dogLevel: 30, now: pT0).filter(\.star).count, 1)
    }

    // MARK: награды

    func testRepeatFindPaysCoins() {
        var f = pFile(at: pT0)
        var repeats = 0
        for k in 0..<30 {
            let before = f.econ.wallet.coins
            let had = f.trip.album
            let r = pBack(&f, "bus_stop", at: pT0 + Double(k) * 3600)!
            XCTAssertEqual(r.isNew, (had[r.find] ?? 0) == 0)
            XCTAssertEqual(r.coins, r.isNew ? 0 : 5)
            XCTAssertEqual(f.econ.wallet.coins - before, r.coins)
            if !r.isNew { repeats += 1 }
        }
        XCTAssertGreaterThan(repeats, 0)
    }

    func testFullSetPaysOnce() {
        var f = pFile(at: pT0)
        var paid = 0, trips = 0
        while f.trip.sets.isEmpty && trips < 2000 {
            let before = f.econ.wallet.shards
            let r = pBack(&f, "arcade", at: pT0 + Double(trips) * 3600)!
            trips += 1
            XCTAssertEqual(f.econ.wallet.shards - before, r.setShards + r.shards)
            paid += r.setShards
        }
        XCTAssertEqual(f.trip.sets, ["arcade"], "набор собран за \(trips) походов")
        XCTAssertEqual(paid, 8)
        XCTAssertEqual(f.trip.last?.setShards, 8)
        XCTAssertEqual(Places.cards(f, dogLevel: 11, now: pT0).first { $0.id == "arcade" }?.line, "Всё найдено")
        for k in 0..<200 {
            XCTAssertEqual(pBack(&f, "arcade", at: pT0 + Double(trips + k) * 3600)?.setShards, 0)
        }
        XCTAssertEqual(f.trip.sets, ["arcade"])
    }

    func testAtMostOneShardPerTrip() {
        var f = pFile(at: pT0)
        var lucky = 0
        let n = 3000
        for k in 0..<n {
            let before = f.shardLog.earned
            let r = pBack(&f, "echo_well", at: pT0 + Double(k) * 1800)!
            XCTAssertTrue((0...1).contains(r.shards))
            XCTAssertTrue([0, 8].contains(r.setShards))
            XCTAssertEqual(f.shardLog.earned - before, r.shards + r.setShards)
            lucky += r.shards
            if r.shards > 0 && r.setShards == 0 { XCTAssertEqual(f.shardLog.last?.reason, Places.shardReason) }
        }
        XCTAssertEqual(Double(lucky) * 100 / Double(n), 3, accuracy: 1.5, "клочок ~3 %")
        XCTAssertNotNil(Places.reasonText(Places.shardReason))
        XCTAssertNotNil(Places.reasonText(Places.setReason))
        XCTAssertNotNil(Places.reasonText(Places.wellReason))
    }

    // MARK: события

    func testEveryEventHasNoteAndEffect() throws {
        var f = pFile(at: pT0)
        let c = PlacesConfig()
        for p in c.places {
            var seen = Set<String>()
            var k = 0
            while seen.count < p.events.count && k < 300 {
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 50 }
                let r = try XCTUnwrap(pBack(&f, p.id, at: pT0 + Double(k) * 7 * 86400))
                k += 1
                seen.insert(r.event)
                let ev = try XCTUnwrap(p.events.first { $0.id == r.event })
                XCTAssertFalse(r.note.isEmpty)
                XCTAssertFalse(r.note.contains("{"), r.note)
                switch ev.effect {
                case .need(let need, let add): XCTAssertEqual(f.pet.needs[need], 50 + add, "\(p.id).\(ev.id)")
                case .photo: XCTAssertTrue(r.photo)
                case .forecast: XCTAssertTrue(c.forecasts.contains { r.note.contains($0) }, r.note)
                default: break
                }
            }
            XCTAssertEqual(seen.count, p.events.count, "\(p.id): все события выпадают")
        }
    }

    func testTicketOncePerWeek() throws {
        var f = pFile(at: pT0)
        let ev = try XCTUnwrap(Places.place("arcade")?.events.first { $0.effect == .ticket })
        let had = f.econ.wallet.tickets
        var tokens: [TripResult] = []
        var k = 0
        while tokens.count < 2 && k < 300 {
            let r = try XCTUnwrap(pBack(&f, "arcade", at: pT0 + Double(k)))   // всё в одни сутки
            if r.event == ev.id { tokens.append(r) }
            k += 1
        }
        XCTAssertEqual(tokens.count, 2)
        XCTAssertTrue(tokens[0].ticket)
        XCTAssertEqual(tokens[0].note, ev.text)
        XCTAssertFalse(tokens[1].ticket, "второй жетон на неделе не даётся")
        XCTAssertEqual(tokens[1].note, ev.spent)
        XCTAssertEqual(f.econ.wallet.tickets, had + 1)
    }

    // MARK: колодец

    func testWellOncePerDay() {
        var f = pFile(at: pT0)
        XCTAssertEqual(refusal(Places.wish(&f, dogLevel: 23, now: pT0)), .locked(level: 24))
        f.econ.wallet.coins = 5
        XCTAssertEqual(refusal(Places.wish(&f, dogLevel: 24, now: pT0)), .notEnough(need: 15))
        f.econ.wallet.coins = 100
        XCTAssertTrue(Places.canWish(f, dogLevel: 24, now: pT0))
        guard case .success(let w) = Places.wish(&f, dogLevel: 24, now: pT0) else { return XCTFail("бросок") }
        XCTAssertEqual(w.coins, 20)
        XCTAssertFalse(w.text.isEmpty)
        XCTAssertEqual(f.econ.wallet.coins, 80)
        XCTAssertEqual(f.journal.last?.kind, "place.well")
        XCTAssertEqual(refusal(Places.wish(&f, dogLevel: 24, now: pT0 + 60)), .notToday)
        XCTAssertEqual(f.econ.wallet.coins, 80, "отказ не списывает")

        var lucky = 0
        let days = 600
        for d in 1...days {
            f.econ.wallet.coins = 100
            let before = f.econ.wallet.shards
            guard case .success(let r) = Places.wish(&f, dogLevel: 24, now: pT0 + Double(d) * 86400) else {
                return XCTFail("день \(d)")
            }
            XCTAssertTrue([0, 1].contains(r.shards))
            XCTAssertEqual(f.econ.wallet.shards - before, r.shards)
            lucky += r.shards
        }
        XCTAssertEqual(Double(lucky) * 100 / Double(days), 10, accuracy: 4, "клочок из колодца ~10 %")
    }

    func testRefusalTexts() {
        let all: [PlaceRefusal] = [.unknown, .locked(level: 5), .noOuting, .busy, .dead, .walk("asleep"), .walk("??"),
                                   .notToday, .notEnough(need: 3)]
        for r in all { XCTAssertFalse(Places.refusalText(r).isEmpty, "\(r)") }
        XCTAssertEqual(Places.refusalText(.locked(level: 5)), "Откроется на 5 уровне")
    }
}
