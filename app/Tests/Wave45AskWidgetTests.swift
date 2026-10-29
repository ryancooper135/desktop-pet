// Волна 45 O: просьба пса (DogAsks, волна 43 K) в виджете и на островке.
// Виджет: те же просьбы, что у приложения (DogAsks.upcoming ⊇ current), подпись = плашка дома (DogAskText.plate),
// кадры в окне чаще (каждые 5 мин), спящему/гуляющему просьбу не показываем.
// Островок: просьба — только текущая, ранг между походом и копилкой, после stale ею не бывает, stale — на конце окна;
// кнопка — та, что выполняет просьбу, только если ядро примет её, не будя пса; иначе «Открыть».
// Гоняется и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000.
private let wT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

/// Бодрый пёс с закреплённым petId (свежий сейв даёт случайный — расписание тогда плавает).
private func wFile(_ id: String = "w45o-pet", at t: Double = wT0) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = id
    for n in Need.allCases { f.pet.needs[n] = 90 }
    DogLevel.settle(&f, now: t)
    return f
}

/// Сегодня — ровно одна просьба kind со стартом start.
private func wForce(_ f: inout SaveFile, _ kind: String, start: Double, coins: Int = 10) {
    DogAsks.settle(&f, now: start)
    f.asks.items = [DogAsk(start: start, kind: kind, coins: coins)]
}

private let ecfg = IslandEventsConfig()
private let window = DogAskConfig.shared.window

private func calmInput(_ now: Double = wT0) -> IslandInput {
    IslandInput(now: now, name: "Шиба", alive: true, outlook: IslandOutlook())
}

private func openAsk(_ kind: String = "pet", now: Double = wT0, ago: Double = 1200) -> IslandAsk {
    IslandAsk(kind: kind, start: now - ago, end: now - ago + window, coins: 10)
}

final class Wave45AskWidgetTests: XCTestCase {

    override func setUp() {
        super.setUp()
        DogAsks.enabled = true
    }

    override func tearDown() {
        Clock.zoneOverride = nil
        DogAsks.enabled = true
        super.tearDown()
    }

    // MARK: прогноз просьб для виджета

    func testUpcomingIncludesCurrentAndSkipsDone() {
        var f = wFile()
        wForce(&f, "pet", start: wT0 - 1200)
        let cur = DogAsks.current(f, now: wT0)
        XCTAssertNotNil(cur)
        let up = DogAsks.upcoming(f, now: wT0, until: wT0 + 3600)
        XCTAssertEqual(up.first, cur, "открытая сейчас просьба — первой")
        XCTAssertEqual(DogAsks.upcoming(f, now: wT0, until: wT0 + 3600), up, "без записи в сейв, повторяемо")

        // Выполненная — не просьба: ни дома, ни в виджете.
        f.asks.items[0].doneT = wT0 - 60
        XCTAssertNil(DogAsks.current(f, now: wT0))
        XCTAssertFalse(DogAsks.upcoming(f, now: wT0, until: wT0 + 3600).contains { $0.start == wT0 - 1200 })

        // Выключены — пусто.
        DogAsks.enabled = false
        XCTAssertTrue(DogAsks.upcoming(f, now: wT0, until: wT0 + 3600).isEmpty)
    }

    /// Будущая просьба в виджете — та же, что потом откроет приложение (то же расписание, то же решение).
    func testUpcomingMatchesWhatAppWillShow() {
        var checked = 0
        for n in 0..<40 {
            let now = wT0 - 4 * 3600   // местные 8:00
            let f = wFile("w45o-sched-\(n)", at: now)
            let up = DogAsks.upcoming(f, now: now, until: now + 12 * 3600)
            XCTAssertEqual(up.map(\.start), up.map(\.start).sorted())
            XCTAssertEqual(Set(up.map(\.start)).count, up.count, "без повторов")
            for a in up where a.start > now {
                XCTAssertTrue(a.real)
                XCTAssertLessThan(a.start, now + 12 * 3600)
                let app = DogAsks.current(f, now: a.start + 60)
                XCTAssertEqual(app?.start, a.start, "pet \(n)")
                XCTAssertEqual(app?.kind, a.kind, "pet \(n)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0, "хоть у одного пса днём есть просьба")
    }

    func testUpcomingCrossesMidnight() {
        let now = wT0 + 10 * 3600   // местные 22:00
        for n in 0..<10 {
            let f = wFile("w45o-night-\(n)", at: now)
            let until = now + 20 * 3600
            let up = DogAsks.upcoming(f, now: now, until: until)
            let tomorrow = DayKey.of(now) + 1
            let sched = DogAsks.schedule(f, day: tomorrow).filter { $0 < until }
            // Каждая просьба завтрашнего утра, которую пёс решит не пропустить, есть в прогнозе.
            for a in up { XCTAssertTrue(a.start < until && a.start + window > now) }
            XCTAssertTrue(Set(up.map(\.start)).isSubset(of: Set(sched + DogAsks.schedule(f, day: tomorrow - 1))))
        }
    }

    // MARK: кадры виджета

    func testAskFramesEveryFiveMinutes() {
        let now = wT0
        let a = DogAsk(start: now - 1200, kind: "pet", coins: 10)
        let grid = IslandEvents.frameTimes(now: now, ecfg)
        let ts = IslandEvents.frameTimes(now: now, asks: [a], window: window, ecfg)
        XCTAssertEqual(ts.first, now)
        XCTAssertEqual(ts.last, grid.last, "не дальше последнего кадра сетки")
        XCTAssertTrue(zip(ts, ts.dropFirst()).allSatisfy { $0 < $1 }, "строго по возрастанию")
        XCTAssertTrue(Set(grid).isSubset(of: Set(ts)))
        let end = a.start + window
        XCTAssertTrue(ts.contains(end), "кадр на конце окна — просьба уходит вовремя")
        let inWindow = ts.filter { $0 > now && $0 < end }
        XCTAssertTrue(zip([now] + inWindow, inWindow + [end]).allSatisfy { $1 - $0 <= ecfg.widgetAskStepS + 0.5 },
                      "в окне не реже раза в 5 мин")

        // Просьба за краем сетки кадров не добавляет; без просьб — та же сетка.
        let far = DogAsk(start: (grid.last ?? now) + 600, kind: "pet", coins: 10)
        XCTAssertEqual(IslandEvents.frameTimes(now: now, asks: [far], window: window, ecfg), grid)
        XCTAssertEqual(IslandEvents.frameTimes(now: now, asks: [], window: window, ecfg), grid)
    }

    func testWidgetCaptionIsHomePlate() {
        var f = wFile()
        let start = wT0 - 1200
        wForce(&f, "pet", start: start)
        let a = try! XCTUnwrap(DogAsks.current(f, now: wT0))
        let looks = WidgetLook.looks(f, now: wT0)
        let first = try! XCTUnwrap(looks.first)
        XCTAssertEqual(first.caption, DogAskText.plate(a, now: wT0))
        XCTAssertEqual(first.caption, "\(DogAskText.line("pet")) · ещё 40 мин")
        XCTAssertEqual(first.ask, first.caption)
        XCTAssertEqual(first.askEmoji, DogAskText.emoji("pet"))
        XCTAssertEqual(first.askEnd, start + window)
        XCTAssertGreaterThanOrEqual(first.relevance, 0.5, "просьба поднимает виджет в Smart Stack")

        // Минуты на каждом кадре — свои, как на плашке дома в тот момент.
        for l in looks where l.ask != nil {
            XCTAssertEqual(l.caption, DogAskText.plate(a, now: l.t))
            XCTAssertLessThan(l.t, start + window)
        }
        XCTAssertGreaterThanOrEqual(looks.filter { $0.ask != nil }.count, 8, "40 мин окна — кадры раз в 5 мин")
        // На конце окна — обычная подпись.
        let after = try! XCTUnwrap(looks.first { $0.t == start + window })
        XCTAssertNil(after.ask)
        XCTAssertNil(after.askEmoji)
        XCTAssertNotEqual(after.caption, first.caption)

        // asks: [] — без просьб (детерминированные снимки и старые тесты).
        XCTAssertTrue(WidgetLook.looks(f, now: wT0, asks: []).allSatisfy { $0.ask == nil })
        // Выключены — тоже без них.
        DogAsks.enabled = false
        XCTAssertTrue(WidgetLook.looks(f, now: wT0).allSatisfy { $0.ask == nil })
    }

    func testWidgetNoAskWhileNapOrOuting() {
        var f = wFile()
        wForce(&f, "pet", start: wT0 - 1200)
        let a = DogAsk(start: wT0 - 1200, kind: "pet", coins: 10)

        var nap = f
        nap.pet.napUntil = wT0 + 1800
        let nl = WidgetLook.looks(nap, now: wT0, asks: [a])
        XCTAssertNil(nl.first?.ask, "спящему просьбу не показываем")
        XCTAssertEqual(nl.first?.pose, .sleep)

        var walk = f
        walk.pet.outing = Outing(from: wT0 - 60, until: wT0 + 3600, find: "stick")
        let wl = WidgetLook.looks(walk, now: wT0, asks: [a])
        XCTAssertTrue(wl.filter { $0.t < wT0 + 3600 }.allSatisfy { $0.ask == nil }, "гуляет — просьбы нет")

        var bath = f
        bath.pet.bathUntil = wT0 + 600
        XCTAssertNil(WidgetLook.looks(bath, now: wT0, asks: [a]).first?.ask, "моется — просьбы нет")
    }

    func testReloadAfterLastFrame() {
        var f = wFile()
        wForce(&f, "pet", start: wT0 - 1200)
        let looks = WidgetLook.looks(f, now: wT0)
        let grid = IslandEvents.frameTimes(now: wT0, ecfg)
        XCTAssertEqual(looks.last?.t, grid.last)
        XCTAssertGreaterThan(WidgetLook.reloadT(looks, now: wT0, ecfg), grid.last ?? wT0)
    }

    // MARK: островок

    func testIslandAskRankAndCandidate() {
        var i = calmInput()
        i.ask = openAsk()
        i.bank = IslandBank(fullAt: wT0 - 60, from: nil, coins: 100)
        let c = IslandEvents.candidates(i, ecfg)
        let e = try! XCTUnwrap(c.first { $0.kind == .ask })
        XCTAssertEqual(e.title, DogAskText.line("pet"))
        XCTAssertEqual(e.compact, DogAskText.emoji("pet"))
        XCTAssertEqual(e.timerEnd, i.ask?.end)
        XCTAssertEqual(e.until, i.ask?.end)
        XCTAssertEqual(e.ask, "pet")
        XCTAssertEqual(e.pose, .sit)
        XCTAssertEqual(IslandEvents.top(c, at: wT0, quiet: nil)?.kind, .ask, "просьба выше копилки")

        // Голод — главнее просьбы.
        i.outlook.hunger = [IslandSpan(from: wT0 - 60, until: nil)]
        XCTAssertEqual(IslandEvents.top(IslandEvents.candidates(i, ecfg), at: wT0, quiet: nil)?.kind, .hungry)

        // Будущую и прошедшую просьбу островок не показывает.
        var j = calmInput()
        j.ask = IslandAsk(kind: "pet", start: wT0 + 600, end: wT0 + 600 + window, coins: 10)
        XCTAssertFalse(IslandEvents.candidates(j, ecfg).contains { $0.kind == .ask })
        j.ask = IslandAsk(kind: "pet", start: wT0 - window - 1, end: wT0 - 1, coins: 10)
        XCTAssertFalse(IslandEvents.candidates(j, ecfg).contains { $0.kind == .ask })

        // Тихие часы: островок пуст, просьба его не будит.
        var q = calmInput()
        q.ask = openAsk()
        q.quiet = IslandQuiet(from: 0, to: 1439, tzOffsetMin: 0)
        if q.quiet?.asleep(wT0) == true {
            XCTAssertNil(IslandEvents.show(q, ecfg).current)
        }
    }

    func testAskStaleAtWindowEndAndNeverAfter() {
        // Одна просьба: stale на конце окна, после — пусто (активность закончится).
        var i = calmInput()
        i.ask = openAsk()
        var s = IslandEvents.show(i, ecfg)
        XCTAssertEqual(s.current?.kind, .ask)
        XCTAssertEqual(s.staleDate, i.ask?.end)
        XCTAssertNil(s.after)

        // Просьба с копилкой: после просьбы — копилка.
        i.bank = IslandBank(fullAt: wT0 - 60, from: nil, coins: 100)
        s = IslandEvents.show(i, ecfg)
        XCTAssertEqual(s.current?.kind, .ask)
        XCTAssertEqual(s.staleDate, i.ask?.end)
        XCTAssertEqual(s.after?.kind, .bank)

        // Голод кончается раньше просьбы: после — не просьба (второго переключения нет, таймер завис бы на 0:00).
        var h = calmInput()
        h.ask = openAsk()
        h.outlook.hunger = [IslandSpan(from: wT0 - 60, until: wT0 + 600)]
        let hs = IslandEvents.show(h, ecfg)
        XCTAssertEqual(hs.current?.kind, .hungry)
        XCTAssertNotEqual(hs.after?.kind, .ask)
        XCTAssertEqual(hs.staleDate, wT0 + 600)

        // Поход и просьба по времени не пересекаются у живого сейва, но и во входе после похода не «Просит».
        var t = calmInput()
        t.ask = openAsk()
        t.trip = IslandTrip(from: wT0 - 600, backAt: wT0 + 300, place: "Маяк")
        let ts = IslandEvents.show(t, ecfg)
        XCTAssertNotEqual(ts.after?.kind, .ask)
    }

    func testCardGlyphTimerAndButton() {
        var i = calmInput()
        i.ask = openAsk("pet")
        let e = try! XCTUnwrap(IslandEvents.show(i, ecfg).current)
        let calmPick = IslandPick(primary: .pet, secondary: nil, calm: [.pet, .feed])
        let c = IslandLook.card(e, pick: calmPick)
        XCTAssertEqual(c.glyph, .ask)
        XCTAssertEqual(IslandGlyph.ask.symbol, "bubble.left.fill")
        XCTAssertEqual(c.trailing, .timer)
        XCTAssertEqual(c.timerEnd, i.ask?.end)
        XCTAssertEqual(c.act, .pet, "кнопка выполняет просьбу на месте")
        XCTAssertTrue(c.actsInPlace)
        XCTAssertEqual(c.detail, DogAskText.hint(i.ask!.ask))

        // Ядро не примет без побудки (дрёма) — «Открыть».
        XCTAssertEqual(IslandLook.card(e, pick: IslandPick(primary: .wake, secondary: nil, calm: [])).act, .open)
        XCTAssertEqual(IslandLook.card(e, pick: nil).act, .open)
        // Расчесать и гулять — только в приложении.
        let all = IslandPick(primary: .pet, secondary: nil, calm: [.feed, .bath, .play, .pet])
        XCTAssertEqual(IslandPlan.act(for: .ask, pick: all, ask: "brush"), .open)
        XCTAssertEqual(IslandPlan.act(for: .ask, pick: all, ask: "walk"), .open)
        XCTAssertEqual(IslandPlan.act(for: .ask, pick: all, ask: "feed"), .feed)
        XCTAssertEqual(IslandPlan.act(for: .ask, pick: all, ask: "bath"), .bath)
        XCTAssertEqual(IslandPlan.act(for: .ask, pick: all, ask: "play"), .play)
        XCTAssertEqual(IslandPlan.act(for: .ask, pick: all, ask: nil), .open)
    }

    func testPickCalmIsEmptyWhileNapping() {
        var f = wFile()
        f.pet.napUntil = wT0 + 1800
        let p = IslandPlan.pick(f, at: wT0)
        XCTAssertTrue(p.calm.isEmpty, "дрёма: кнопкой просьбы пса не будим")
        let awake = IslandPlan.pick(wFile(), at: wT0)
        XCTAssertTrue(awake.calm.isSubset(of: [.feed, .bath, .play, .pet]))
    }

    // MARK: из сейва

    func testFeedAskFromSave() {
        var f = wFile()
        let start = wT0 - 1200
        wForce(&f, "pet", start: start)
        let a = try! XCTUnwrap(IslandFeed.ask(f, now: wT0))
        XCTAssertEqual(a.kind, "pet")
        XCTAssertEqual(a.start, start)
        XCTAssertEqual(a.end, start + window)
        XCTAssertEqual(a.coins, 10)
        XCTAssertEqual(IslandFeed.input(f, now: wT0).ask, a)
        XCTAssertEqual(IslandEvents.show(IslandFeed.input(f, now: wT0, tzOffsetMin: 0), ecfg).current?.kind, .ask)

        var nap = f
        nap.pet.napUntil = wT0 + 1800
        XCTAssertNil(IslandFeed.ask(nap, now: wT0), "островок спящего не будит")
        var walk = f
        walk.pet.outing = Outing(from: wT0 - 60, until: wT0 + 3600, find: "stick")
        XCTAssertNil(IslandFeed.ask(walk, now: wT0))
        var bath = f
        bath.pet.bathUntil = wT0 + 600
        XCTAssertNil(IslandFeed.ask(bath, now: wT0))
        XCTAssertNil(IslandFeed.ask(f, now: start + window), "окно кончилось")

        DogAsks.enabled = false
        XCTAssertNil(IslandFeed.ask(f, now: wT0))
        XCTAssertNil(IslandFeed.input(f, now: wT0).ask)
    }
}
