// Волна 33 E: выбор события островка и таймлайн виджета (RESEARCH/20-tycoon-design.md §8).
// Пояс закреплён (UTC, tzOffsetMin: 0): полдень и ночь не зависят от машины, где гоняют тесты.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Полдень UTC: хозяин точно не спит.
private let noon: Double = (1_760_000_000 / 86400).rounded(.down) * 86400 + 12 * 3600

/// Свежий файл на момент t, все шкалы на level (кроме перечисленных), пояс UTC.
private func file(at t: Double, _ level: Double = 90, _ needs: [Need: Double] = [:]) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.owner.tzOffsetMin = 0
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = needs[n] ?? level }
    return f
}

/// Чистый вход: живой пёс, ничего не происходит, ночи нет.
private func calm(_ now: Double = noon) -> IslandInput {
    IslandInput(now: now, name: "Шиба", alive: true, outlook: IslandOutlook())
}

private func status(trails: Int = 1, hoursLeft: Double = 41, found: Bool = false, lost: String? = nil) -> Runaway.Status {
    Runaway.Status(canReturn: lost == nil, lost: lost, hoursLeft: hoursLeft, trails: trails, trailsNeed: 2,
                   trailReady: true, trailInH: 0, steps: 0, stepsNeed: 3000, shardsCost: 30, shardsHave: 0, found: found)
}

/// Конфиг без чтения economy.json: тесты не зависят от чужих правок конфига.
private let cfg = IslandEventsConfig()

final class IslandEventsTests: XCTestCase {

    // MARK: приоритеты

    func testPriorityFollowsTable() {
        let now = noon
        var i = calm(now)
        i.outlook = IslandOutlook(lastChanceAt: now, deathAt: now + 5 * 3600, hunger: [IslandSpan(from: now, until: nil)])
        i.trip = IslandTrip(from: now - 600, backAt: now + 1800, place: "Маяк")
        i.bank = IslandBank(fullAt: now - 60, from: now - 12 * 3600, coins: 412)
        i.levelUp = IslandLevelUp(level: 14, at: now)
        var c = IslandEvents.candidates(i, cfg)
        // Все живые события есть, побег — только с прогнозной смерти.
        XCTAssertEqual(Set(c.map(\.kind)), [.runaway, .lastChance, .hungry, .trip, .home, .bank, .levelUp])
        let order: [IslandEvent.Kind] = [.lastChance, .hungry, .trip, .bank, .levelUp]
        for k in order {
            XCTAssertEqual(IslandEvents.top(c, at: now, quiet: nil)?.kind, k)
            c.removeAll { $0.kind == k }
        }
        XCTAssertNil(IslandEvents.top(c, at: now, quiet: nil), "побег ещё не начался, «Я дома!» — после похода")

        // Побег главнее всего: уже убежал — только он.
        var d = calm(now)
        d.alive = false
        d.runaway = status()
        d.bank = i.bank
        let dc = IslandEvents.candidates(d, cfg)
        XCTAssertEqual(dc.map(\.kind), [.runaway])
        XCTAssertEqual(IslandEvents.show(d, cfg).current?.title, "Найди Шиба: 1/2 следа, 41 ч")
        XCTAssertEqual(IslandEvent.Kind.allCases.map(\.rank), [1, 2, 3, 4, 4, 5, 6, 7])
    }

    /// Волна 36 O: слово «след» согласовано с числом всего следов.
    func testTrailsWordAgrees() {
        XCTAssertEqual(IslandEvents.trailsText(0, 1), "0/1 след")
        XCTAssertEqual(IslandEvents.trailsText(1, 2), "1/2 следа")
        XCTAssertEqual(IslandEvents.trailsText(2, 4), "2/4 следа")
        XCTAssertEqual(IslandEvents.trailsText(3, 5), "3/5 следов")
        XCTAssertEqual(IslandEvents.trailsText(0, 11), "0/11 следов")
        XCTAssertEqual(IslandEvents.trailsText(0, 14), "0/14 следов")
        XCTAssertEqual(IslandEvents.trailsText(5, 21), "5/21 след")
        XCTAssertEqual(IslandEvents.trailsText(0, 22), "0/22 следа")
    }

    func testOneEventAtATime() {
        var i = calm()
        i.outlook.hunger = [IslandSpan(from: noon, until: nil)]
        i.bank = IslandBank(fullAt: noon - 1, from: nil, coins: nil)
        let s = IslandEvents.show(i, cfg)
        XCTAssertEqual(s.current?.kind, .hungry)
        XCTAssertEqual(s.current?.title, "Голоден!")
        // Голод до захода, копилка ниже — ничего не сменится: stale на пределе жизни активности, вид тот же.
        XCTAssertEqual(s.staleDate, noon + 8 * 3600)
        XCTAssertEqual(s.after?.kind, .hungry)
    }

    // MARK: «всё хорошо»

    func testAllGoodNoActivity() {
        let s = IslandEvents.show(calm(), cfg)
        XCTAssertFalse(s.activity)
        XCTAssertNil(s.current)
        XCTAssertNil(s.staleDate)
        XCTAssertNil(s.after)

        // Сытый пёс днём из сейва: активности нет, ближайшее событие — только в будущем.
        let f = file(at: noon)
        let fs = IslandEvents.show(f, at: noon, tzOffsetMin: 0, cfg)
        XCTAssertFalse(fs.activity)
        if let st = fs.staleDate { XCTAssertGreaterThan(st, noon) }
        if let a = fs.after { XCTAssertGreaterThan(a.from, noon - 1) }
    }

    // MARK: staleDate

    func testStaleDateIsNearestEvent() {
        var i = calm()
        i.outlook.hunger = [IslandSpan(from: noon + 2 * 3600, until: nil)]
        i.bank = IslandBank(fullAt: noon + 5 * 3600, from: noon - 7 * 3600, coins: 300)
        let s = IslandEvents.show(i, cfg)
        XCTAssertNil(s.current)
        XCTAssertEqual(s.staleDate, noon + 2 * 3600)
        XCTAssertEqual(s.after?.kind, .hungry)
        XCTAssertEqual(s.after?.soon, "Проголодается к 14:00")
        XCTAssertEqual(s.stale, Date(timeIntervalSince1970: noon + 2 * 3600))
    }

    func testTripThenHome() {
        var i = calm()
        i.trip = IslandTrip(from: noon - 3600, backAt: noon + 12 * 60, place: "Остановка без автобуса")
        let s = IslandEvents.show(i, cfg)
        XCTAssertEqual(s.current?.kind, .trip)
        XCTAssertEqual(s.current?.title, "Остановка без автобуса")
        XCTAssertEqual(s.current?.timerEnd, noon + 12 * 60)
        XCTAssertEqual(s.current?.progressFrom, noon - 3600)
        XCTAssertEqual(s.staleDate, noon + 12 * 60)
        XCTAssertEqual(s.after?.kind, .home)
        XCTAssertEqual(s.after?.title, "Я дома!")

        // Уже вернулся: «Я дома!» висит час, потом пусто.
        var j = calm()
        j.trip = IslandTrip(from: nil, backAt: noon - 600, place: "Маяк")
        let h = IslandEvents.show(j, cfg)
        XCTAssertEqual(h.current?.kind, .home)
        XCTAssertEqual(h.staleDate, noon - 600 + cfg.homeHoldS)
        XCTAssertNil(h.after)
    }

    func testLevelUpIsShort() {
        var i = calm()
        i.levelUp = IslandLevelUp(level: 14, at: noon)
        let s = IslandEvents.show(i, cfg)
        XCTAssertEqual(s.current?.compact, "★14")
        XCTAssertEqual(s.staleDate, noon + 15 * 60)
        XCTAssertNil(s.after, "после уровня островок пустеет")

        // Давний уровень не показываем.
        i.levelUp = IslandLevelUp(level: 14, at: noon - 3600)
        XCTAssertFalse(IslandEvents.show(i, cfg).activity)
    }

    func testLastChanceThenRunaway() {
        var i = calm()
        i.outlook = IslandOutlook(lastChanceAt: noon, deathAt: noon + 3 * 3600, hunger: [])
        let s = IslandEvents.show(i, cfg)
        XCTAssertEqual(s.current?.kind, .lastChance)
        XCTAssertEqual(s.current?.timerEnd, noon + 3 * 3600)
        XCTAssertEqual(s.staleDate, noon + 3 * 3600)
        XCTAssertEqual(s.after?.kind, .runaway)

        // Третий побег за окно — насовсем: после сердечка пусто.
        i.runawayClosed = true
        XCTAssertNil(IslandEvents.show(i, cfg).after)
    }

    func testActivityStaleCappedAtEightHours() {
        var i = calm()
        i.bank = IslandBank(fullAt: noon - 60, from: nil, coins: 99)
        i.outlook.hunger = [IslandSpan(from: noon + 20 * 3600, until: nil)]
        let s = IslandEvents.show(i, cfg)
        XCTAssertEqual(s.current?.kind, .bank)
        XCTAssertEqual(s.current?.title, "+99 🪙 ждут")
        XCTAssertEqual(s.staleDate, noon + 8 * 3600)
        XCTAssertEqual(s.after?.kind, .bank)
    }

    // MARK: ночь хозяина

    func testOwnerNightIsQuiet() {
        // Хозяин спит 23:00–07:00 UTC. Сейчас 02:00: голоден, но островок пустой до утра.
        let q = IslandQuiet(from: 23 * 60, to: 7 * 60, tzOffsetMin: 0)
        let night = noon - 10 * 3600
        var i = calm(night)
        i.quiet = q
        i.outlook.hunger = [IslandSpan(from: night, until: nil)]
        i.runaway = nil
        let s = IslandEvents.show(i, cfg)
        XCTAssertFalse(s.activity)
        XCTAssertEqual(s.staleDate, noon - 5 * 3600, "в 07:00")
        XCTAssertEqual(s.after?.kind, .hungry)

        // Днём голоден, ночь в 23:00 гасит островок.
        var d = calm(noon + 8 * 3600)
        d.quiet = q
        d.outlook.hunger = [IslandSpan(from: noon, until: nil)]
        let ds = IslandEvents.show(d, cfg)
        XCTAssertEqual(ds.current?.kind, .hungry)
        XCTAssertEqual(ds.staleDate, noon + 11 * 3600)
        XCTAssertNil(ds.after)

        // Даже побег ночью молчит.
        var r = calm(night)
        r.alive = false
        r.runaway = status()
        r.quiet = q
        XCTAssertFalse(IslandEvents.show(r, cfg).activity)
    }

    func testQuietEdges() {
        let q = IslandQuiet(from: 23 * 60, to: 7 * 60, tzOffsetMin: 60)
        // 12:00 UTC = 13:00 местного: ближе всего 23:00 местного = 22:00 UTC.
        XCTAssertEqual(q.nextEdge(after: noon), noon + 10 * 3600)
        XCTAssertTrue(q.asleep(noon + 10 * 3600))
        XCTAssertFalse(q.asleep(noon + 10 * 3600 - 60))
        XCTAssertEqual(q.nextEdge(after: noon + 10 * 3600), noon + 18 * 3600)
        XCTAssertNil(IslandQuiet(from: 0, to: 0, tzOffsetMin: 0).nextEdge(after: noon))
    }

    func testStartEarlyShowsSoonText() {
        var c = IslandEventsConfig()
        c.startEarly = true
        var i = calm()
        i.outlook.hunger = [IslandSpan(from: noon + 2 * 3600 + 40 * 60, until: nil)]
        let s = IslandEvents.show(i, c)
        XCTAssertTrue(s.pending)
        XCTAssertEqual(s.current?.soon, "Проголодается к 14:40")
        XCTAssertEqual(s.staleDate, noon + 2 * 3600 + 40 * 60)
        XCTAssertEqual(s.after?.title, "Голоден!")
        // По умолчанию (решение 7а) — нет.
        XCTAssertFalse(IslandEventsConfig().startEarly)
        XCTAssertFalse(IslandEvents.show(i, cfg).activity)
    }

    // MARK: прогноз и сейв

    func testOutlookHungerFromEngine() {
        let r = Catalog.rules
        let o = Owner(bedMin: r.bedMin, wakeMin: r.wakeMin, tzOffsetMin: 0)
        var f = file(at: noon, 90, [.food: 10])
        let now = IslandEvents.outlook(f.pet, r, o, horizonH: 12)
        XCTAssertEqual(now.hunger.first?.from, noon, "уже голоден — с этой минуты")
        // Кормушки в новом доме нет: голод до побега (или до горизонта).
        if let u = now.hunger.first?.until { XCTAssertEqual(u, now.deathAt) }

        f = file(at: noon, 90, [.food: r.warnLow + 5])
        let later = IslandEvents.outlook(f.pet, r, o, horizonH: 24)
        XCTAssertNotNil(later.hunger.first)
        if let h = later.hunger.first { XCTAssertGreaterThan(h.from, noon) }
    }

    func testFromSaveHungryAndOuting() {
        let f = file(at: noon, 90, [.food: 10])
        let s = IslandEvents.show(f, at: noon, tzOffsetMin: 0, cfg)
        XCTAssertEqual(s.current?.kind, .hungry)

        var g = file(at: noon)
        g.pet.outing = Outing(from: noon - 600, until: noon + 1200, find: "cone")
        let w = IslandEvents.show(g, at: noon, tzOffsetMin: 0, cfg)
        XCTAssertEqual(w.current?.kind, .trip)
        XCTAssertEqual(w.current?.title, "Прогулка")
        XCTAssertEqual(w.after?.kind, .home)

        // Параметр похода (Places) главнее прогулки ядра.
        let p = IslandEvents.show(g, at: noon, trip: IslandTrip(from: noon - 600, backAt: noon + 1200, place: "Маяк"),
                                  tzOffsetMin: 0, cfg)
        XCTAssertEqual(p.current?.title, "Маяк")
    }

    func testFromSaveRunaway() {
        var f = file(at: noon)
        f.pet.alive = false
        f.pet.diedAt = noon - 3600
        f.pet.cause = .starve
        let s = IslandEvents.show(f, at: noon, tzOffsetMin: 0, cfg)
        if RunawayConfig.shared.enabled {
            XCTAssertEqual(s.current?.kind, .runaway)
            XCTAssertEqual(s.current?.pose, .away)
        }
        // Насовсем потерян (третий побег за окно) — пусто.
        f.runaway.comebacks = [noon - 2 * 86400, noon - 86400]
        XCTAssertFalse(IslandEvents.show(f, at: noon, tzOffsetMin: 0, cfg).activity)
    }

    func testIslandButtons() {
        XCTAssertEqual(IslandPlan.act(for: .hungry), .feed)
        XCTAssertEqual(IslandPlan.act(for: .trip), .walk)
        XCTAssertEqual(IslandPlan.act(for: .home), .pet)
        XCTAssertEqual(IslandPlan.act(for: .bank), .open)
        XCTAssertEqual(IslandPlan.act(for: .runaway), .open)
        XCTAssertEqual(IslandPlan.act(for: .lastChance), .open)
        XCTAssertEqual(IslandPlan.act(for: .lastChance, pick: IslandPick(primary: .heal, secondary: nil)), .heal)
        XCTAssertEqual(IslandPlan.act(for: .lastChance, pick: IslandPick(primary: .sleep, secondary: nil)), .open)
    }

    // MARK: виджет

    func testWidgetTimelineMonotonic() {
        let now = noon + 7 * 60 + 13
        let fr = IslandEvents.widget(file(at: now), now: now, tzOffsetMin: 0, cfg)
        XCTAssertEqual(fr.count, 24)
        XCTAssertEqual(fr.first?.t, now)
        for (a, b) in zip(fr, fr.dropFirst()) {
            XCTAssertGreaterThan(b.t, a.t)
            XCTAssertLessThanOrEqual(b.t - a.t, 1800)
        }
        for x in fr.dropFirst() { XCTAssertEqual(x.t.truncatingRemainder(dividingBy: 1800), 0, "по :00 и :30") }
        XCTAssertLessThan(fr.last!.t - now, 12 * 3600)
    }

    func testWidgetPoses() {
        let r = Catalog.rules
        // Сытый днём сидит, ночью питомца спит.
        let eve = noon + 4 * 3600
        let f0 = file(at: eve)
        let fr = IslandEvents.widget(f0, now: eve, tzOffsetMin: 0, cfg)
        XCTAssertEqual(fr.first?.pose, .sit)
        XCTAssertTrue(fr.contains { $0.pose == .sleep }, "16:00 → 03:30: ночь питомца попадает")
        var o = f0.owner
        o.tzOffsetMin = 0
        for x in fr where PetEngine.petNight(x.t, r, o) { XCTAssertEqual(x.pose, .sleep, "\(x.t)") }

        // Голодный ждёт у миски.
        XCTAssertEqual(IslandEvents.widget(file(at: noon, 90, [.food: 10]), now: noon, tzOffsetMin: 0, cfg).first?.pose, .bowl)
        // Уставший лежит.
        XCTAssertEqual(IslandEvents.widget(file(at: noon, 90, [.energy: 10]), now: noon, tzOffsetMin: 0, cfg).first?.pose, .lie)

        // В походе — нет дома и записка, после возвращения — дома.
        let trip = IslandTrip(from: noon - 600, backAt: noon + 3600, place: "Маяк")
        let tf = IslandEvents.widget(file(at: noon), now: noon, trip: trip, tzOffsetMin: 0, cfg)
        // Волна 51: в походе пёс бежит (.run); .away — только «убежал».
        XCTAssertEqual(tf.first?.pose, .run)
        XCTAssertEqual(tf.first?.note, "Маяк · вернётся в 13:00")
        XCTAssertEqual(tf.first?.tripUntil, noon + 3600)
        XCTAssertNotEqual(tf[3].pose, .run)
        XCTAssertNotEqual(tf[3].pose, .away)

        // Только что покормили — ест.
        var fed = file(at: noon)
        fed.lastAction = SaveFile.LastAction(kind: "feed", source: .app, t: noon - 60, ok: true)
        XCTAssertEqual(IslandEvents.widget(fed, now: noon, tzOffsetMin: 0, cfg).first?.pose, .eat)

        // Убежал — нет дома.
        var dead = file(at: noon)
        dead.pet.alive = false
        dead.pet.diedAt = noon - 60
        let df = IslandEvents.widget(dead, now: noon, tzOffsetMin: 0, cfg)
        XCTAssertTrue(df.allSatisfy { $0.pose == .away && !$0.alive })
    }

    func testWidgetBankRing() {
        let bank = IslandBank(fullAt: noon + 6 * 3600, from: noon - 6 * 3600, coins: 200)
        let fr = IslandEvents.widget(file(at: noon), now: noon, bank: bank, tzOffsetMin: 0, cfg)
        XCTAssertEqual(fr.first?.ring ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertFalse(fr.first?.bankFull ?? true)
        XCTAssertTrue(fr.last?.bankFull ?? false)
        for (a, b) in zip(fr, fr.dropFirst()) { XCTAssertGreaterThanOrEqual(b.ring ?? 0, a.ring ?? 0) }
        XCTAssertNil(IslandEvents.widget(file(at: noon), now: noon, tzOffsetMin: 0, cfg).first?.ring)
    }
}
