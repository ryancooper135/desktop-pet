// Волна 46 Q: охота на баги на стыках волн 43–45 (просьбы пса, задания дня, idle-дела, виджет и островок).
// Каждый тест — найденный баг: сначала падал, потом исправлен (DECISIONS.md, «Волна 46 Q»).
// Гоняется и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000.
private let qT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

/// Бодрый пёс с закреплённым petId (свежий сейв даёт случайный — расписание тогда плавает).
private func qFile(_ id: String = "w46q-pet", at t: Double = qT0) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = id
    for n in Need.allCases { f.pet.needs[n] = 90 }
    DogLevel.settle(&f, now: t)
    return f
}

/// Сегодня — ровно одна просьба kind со стартом start.
private func qForce(_ f: inout SaveFile, _ kind: String, start: Double, coins: Int = 10) {
    DogAsks.settle(&f, now: start)
    f.asks.items = [DogAsk(start: start, kind: kind, coins: coins)]
}

private let qWindow = DogAskConfig.shared.window

final class Wave46SeamTests: XCTestCase {

    override func setUp() {
        super.setUp()
        DogAsks.enabled = true
        DailyTasks.enabled = true
    }

    override func tearDown() {
        Clock.zoneOverride = nil
        DogAsks.enabled = true
        DailyTasks.enabled = true
        super.tearDown()
    }

    // MARK: Баг 1 — плашка просьбы дома видна, когда пса нет дома / он спит / моется

    /// Дом (AppModel.dogAsk), островок (IslandFeed.ask) и виджет (кадр) показывают просьбу одинаково:
    /// гуляет, в походе, дремлет, моется — просьбы не видно нигде. Раньше дом проверял только «жив».
    func testShownAskHiddenWhenAwayNappingOrBathing() {
        var f = qFile()
        let start = qT0 - 1200
        qForce(&f, "pet", start: start)
        XCTAssertNotNil(DogAsks.shown(f, now: qT0), "дома, бодрый — просьба видна")
        XCTAssertEqual(DogAsks.shown(f, now: qT0)?.start, IslandFeed.ask(f, now: qT0)?.start)

        var walk = f
        walk.pet.outing = Outing(from: qT0 - 60, until: qT0 + 3600, find: "stick")
        XCTAssertNotNil(DogAsks.current(walk, now: qT0), "окно открыто…")
        XCTAssertNil(DogAsks.shown(walk, now: qT0), "…но пёс гуляет: погладить нельзя, плашки нет")

        var trip = f
        trip.trip.active = ActiveTrip(place: "forest_tv", from: qT0 - 900, start: qT0 - 600, until: qT0 + 1800,
                                      star: false)
        XCTAssertNil(DogAsks.shown(trip, now: qT0), "в походе")

        var nap = f
        nap.pet.napUntil = qT0 + 1800
        XCTAssertNil(DogAsks.shown(nap, now: qT0), "дремлет")

        var bath = f
        bath.pet.bathUntil = qT0 + 600
        XCTAssertNil(DogAsks.shown(bath, now: qT0), "моется")

        // Хозяин сдвинул сон (OwnerSleep выучил новое окно) — у пса ночь посреди окна: в кадре виджета поза «спит»
        // и просьбы нет; дом и островок — так же.
        var night = f
        night.owner.bedMin = 10 * 60
        night.owner.wakeMin = 22 * 60
        XCTAssertTrue(PetEngine.petNight(qT0, ItemPerks.rules(night), PetRunner.owner(night, at: qT0)))
        XCTAssertNil(DogAsks.shown(night, now: qT0), "ночь пса")

        // Та же картина у островка.
        for g in [walk, trip, nap, bath, night] {
            XCTAssertNil(IslandFeed.ask(g, now: qT0))
        }
    }

    /// Прогулка из приложения посреди просьбы «погладь»: дом прячет плашку, пока пёс не вернётся,
    /// и снова показывает её, если окно ещё открыто.
    func testShownAskReturnsAfterWalkInsideWindow() {
        var f = qFile()
        let start = qT0 - 600
        qForce(&f, "pet", start: start)
        let out = PetRunner.apply(.walk, source: .app, to: &f, now: qT0)
        guard out.ok, let until = f.pet.outing?.until else { return XCTFail("прогулка не началась") }
        XCTAssertNil(DogAsks.shown(f, now: qT0 + 60))
        if until + 120 < start + qWindow {
            XCTAssertNotNil(DogAsks.shown(f, now: until + 120), "вернулся, окно открыто — плашка снова")
        }
    }
}
