// Волна 34 J: вид островка и виджета поверх IslandEvents — карточки, пиксельный пёс, кадры виджета, «Собрать».
// Пояс закреплён (UTC, tzOffsetMin: 0): полдень и ночь не зависят от машины, где гоняют тесты.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Полдень UTC: хозяин точно не спит.
private let noon: Double = (1_760_000_000 / 86400).rounded(.down) * 86400 + 12 * 3600

private func file(at t: Double, _ level: Double = 90, _ needs: [Need: Double] = [:]) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.owner.tzOffsetMin = 0
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = needs[n] ?? level }
    return f
}

private func calm(_ now: Double = noon) -> IslandInput {
    IslandInput(now: now, name: "Шиба", alive: true, outlook: IslandOutlook())
}

private let cfg = IslandEventsConfig()

final class IslandLookTests: XCTestCase {

    // MARK: карточки острова

    func testGlyphPerEvent() {
        let map: [IslandEvent.Kind: IslandGlyph] = [.runaway: .tracks, .lastChance: .heart, .hungry: .bowl,
                                                    .trip: .trip, .home: .home, .bank: .piggy, .levelUp: .star]
        for (k, g) in map { XCTAssertEqual(IslandGlyph(k), g, "\(k)") }
        for g in IslandGlyph.allCases { XCTAssertFalse(g.symbol.isEmpty) }
    }

    func testCardButtons() {
        func act(_ k: IslandEvent.Kind, _ pick: IslandPick? = nil) -> IslandAct {
            let e = IslandEvent(kind: k, from: noon, until: nil, title: "x", detail: nil, soon: "x", compact: "x",
                                pose: .sit, timerEnd: nil, progressFrom: nil, ring: nil)
            return IslandLook.card(e, pick: pick).act
        }
        XCTAssertEqual(act(.hungry), .feed, "голод — «Покормить»")
        XCTAssertEqual(act(.home), .pet, "дома — «Погладить»")
        XCTAssertEqual(act(.lastChance, IslandPick(primary: .bath, secondary: nil)), .bath, "сердечко — спасающая")
        XCTAssertEqual(act(.lastChance), .open)
        for k in [IslandEvent.Kind.runaway, .bank, .levelUp] { XCTAssertEqual(act(k), .open) }
        XCTAssertFalse(IslandLook.card(IslandEvent(kind: .trip, from: noon, until: nil, title: "x", detail: nil,
                                                   soon: "x", compact: "x", pose: .away, timerEnd: nil,
                                                   progressFrom: nil, ring: nil)).actsInPlace)
    }

    func testCardsNowAndAfterStale() {
        var i = calm()
        i.trip = IslandTrip(from: noon - 600, backAt: noon + 1800, place: "Маяк")
        let show = IslandEvents.show(i, cfg)
        let c = IslandLook.cards(show, i)
        XCTAssertEqual(c.now?.kind, .trip)
        XCTAssertEqual(c.now?.glyph, .trip)
        XCTAssertEqual(c.now?.trailing, .timer)
        XCTAssertTrue(c.now?.hasProgress ?? false, "поход с началом — полоска")
        XCTAssertEqual(c.now?.progress(at: noon - 600) ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(c.now?.progress(at: noon + 1800) ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(c.now?.progress(at: noon + 600) ?? -1, 0.5, accuracy: 1e-9)
        // После возвращения — «Я дома!» с кнопкой «Погладить».
        XCTAssertEqual(c.next?.kind, .home)
        XCTAssertEqual(c.next?.act, .pet)
        XCTAssertEqual(IslandLook.shown(c.now, next: c.next, stale: false)?.kind, .trip)
        XCTAssertEqual(IslandLook.shown(c.now, next: c.next, stale: true)?.kind, .home)
    }

    func testRestCardWhenNothingAfter() {
        var i = calm()
        i.levelUp = IslandLevelUp(level: 14, at: noon)
        let show = IslandEvents.show(i, cfg)
        XCTAssertEqual(show.current?.kind, .levelUp)
        let c = IslandLook.cards(show, i)
        XCTAssertEqual(c.now?.title.contains("14"), true, "уровень — «★14»")
        XCTAssertNotNil(show.staleDate)
        XCTAssertNil(c.next?.kind, "дальше ничего: тихий вид")
        XCTAssertEqual(c.next?.glyph, .calm)
        XCTAssertEqual(c.next?.title, "Всё хорошо")

        XCTAssertEqual(IslandLook.rest(name: "Шиба", night: true, at: noon).title, "Шиба спит")
        XCTAssertEqual(IslandLook.rest(name: "Шиба", night: true, at: noon).pose, .sleep)
    }

    func testNoCardWhenAllGood() {
        let i = calm()
        let c = IslandLook.cards(IslandEvents.show(i, cfg), i)
        XCTAssertNil(c.now)
        XCTAssertNil(c.next)
    }

    func testBankCardRing() {
        var i = calm()
        i.bank = IslandBank(fullAt: noon - 60, from: noon - 12 * 3600, coins: 412)
        let c = IslandLook.cards(IslandEvents.show(i, cfg), i)
        XCTAssertEqual(c.now?.kind, .bank)
        XCTAssertEqual(c.now?.glyph, .piggy)
        XCTAssertEqual(c.now?.trailing, .ring)
    }

    func testCardRoundTrip() throws {
        var i = calm()
        i.trip = IslandTrip(from: noon - 600, backAt: noon + 1800, place: "Маяк")
        let c = IslandLook.cards(IslandEvents.show(i, cfg), i)
        let data = try JSONEncoder().encode(c.now)
        XCTAssertEqual(try JSONDecoder().decode(IslandCard.self, from: data), c.now)
        let rest = IslandLook.rest(name: "Шиба", night: false, at: noon)
        XCTAssertEqual(try JSONDecoder().decode(IslandCard.self, from: JSONEncoder().encode(rest)), rest)
    }

    // MARK: пиксельный пёс

    func testPixelDogFramesWellFormed() {
        for p in DogPose.allCases {
            let fs = PixelDog.frames(p)
            XCTAssertTrue((2...3).contains(fs.count), "\(p): 2–3 кадра")
            XCTAssertLessThanOrEqual(PixelDog.cycleS(p), 2, "\(p): цикл не дольше 2 с")
            for (k, rows) in fs.enumerated() {
                XCTAssertEqual(rows.count, PixelDog.height, "\(p)#\(k)")
                for r in rows {
                    XCTAssertEqual(r.count, PixelDog.width, "\(p)#\(k): «\(r)»")
                    for ch in r where ch != "." { XCTAssertNotNil(PixelInk(rawValue: ch), "\(p)#\(k): «\(ch)»") }
                }
                XCTAssertFalse(PixelDog.cells(rows).isEmpty)
            }
            // Кадры разные — иначе анимации нет.
            XCTAssertEqual(Set(fs.map { $0.joined() }).count, fs.count, "\(p): кадры различаются")
        }
    }

    func testPixelDogFrameIndexCycles() {
        XCTAssertEqual(PixelDog.frameIndex(.sit, at: 0), 0)
        XCTAssertEqual(PixelDog.frameIndex(.sit, at: 0.5), 1)
        XCTAssertEqual(PixelDog.frameIndex(.sit, at: 1.0), 0)
        XCTAssertEqual(PixelDog.frameIndex(.away, at: 1.0), 2)
        XCTAssertEqual(PixelDog.frameIndex(.away, at: 1.5), 0)
        XCTAssertEqual(PixelDog.frameIndex(.sit, at: -0.2), 1, "до нуля — тоже по кругу")
        XCTAssertEqual(PixelDog.frameIndex(.sit, at: .nan), 0)
        XCTAssertEqual(PixelDog.cells(.sit, frame: 7), PixelDog.cells(.sit, frame: 1))
    }

    // MARK: виджет

    func testSkyPhase() {
        let day0 = (noon / 86400).rounded(.down) * 86400
        XCTAssertEqual(SkyPhase.at(day0 + 6 * 3600, tz: 0), .dawn)
        XCTAssertEqual(SkyPhase.at(day0 + 12 * 3600, tz: 0), .day)
        XCTAssertEqual(SkyPhase.at(day0 + 19 * 3600, tz: 0), .dusk)
        XCTAssertEqual(SkyPhase.at(day0 + 23 * 3600, tz: 0), .night)
        XCTAssertEqual(SkyPhase.at(day0 + 2 * 3600, tz: 0), .night)
        // Пояс: 4:00 UTC при +120 — это 6:00, рассвет.
        XCTAssertEqual(SkyPhase.at(day0 + 4 * 3600, tz: 120), .dawn)
        XCTAssertEqual(SkyPhase.at(day0 + 23 * 3600, tz: -300), .dusk)
    }

    func testLowestBars() {
        let bars: [Need: Int] = [.food: 50, .clean: 20, .energy: 90, .fun: 20, .love: 70, .walk: 10]
        XCTAssertEqual(WidgetLook.lowest(bars, 1).map(\.need), [.walk])
        XCTAssertEqual(WidgetLook.lowest(bars, 3).map(\.need), [.clean, .fun, .walk], "в обычном порядке")
        let even = Dictionary(uniqueKeysWithValues: WidgetLook.order.map { ($0, 80) })
        XCTAssertEqual(WidgetLook.lowest(even, 3).map(\.need), [.food, .clean, .energy], "равные — по порядку")
    }

    func testBankLine() {
        let day0 = (noon / 86400).rounded(.down) * 86400
        XCTAssertEqual(WidgetLook.bankLine(coins: 214, full: false, fullAt: day0 + 21 * 3600 + 600, tz: 0),
                       "+214 · полная в 21:10")
        XCTAssertEqual(WidgetLook.bankLine(coins: 412, full: true, fullAt: day0, tz: 0), "+412 · собери!")
    }

    func testLooksFromSave() {
        var f = file(at: noon)
        f.yard.stations = ["dryer": 3]
        f.yard.t = noon
        f.yard.bank = 0
        let looks = WidgetLook.looks(f, now: noon, tzOffsetMin: 0, cfg)
        XCTAssertEqual(looks.count, cfg.widgetEntries)
        for (a, b) in zip(looks, looks.dropFirst()) {
            XCTAssertLessThan(a.t, b.t)
            XCTAssertGreaterThanOrEqual(b.ring ?? 0, a.ring ?? 0, "копилка не убывает")
            XCTAssertGreaterThanOrEqual(b.coins ?? 0, a.coins ?? 0)
        }
        let first = looks[0]
        XCTAssertEqual(first.pose, .sit)
        XCTAssertEqual(first.caption, "Всё хорошо")
        XCTAssertEqual(first.sky, .day)
        XCTAssertEqual(first.bars.count, 3)
        XCTAssertNotNil(first.main)
        XCTAssertEqual(first.lock, .ring)
        XCTAssertEqual(first.coins, 0)
        XCTAssertFalse(first.canCollect, "пустую не собираем")
        XCTAssertEqual(first.bankLine?.hasPrefix("+0 · полная в "), true)
        // Лента — 12 ч, копилка — сутки: к концу ленты кольцо заполнено на половину.
        XCTAssertEqual(looks.last?.ring ?? 0, 0.5, accuracy: 0.05, "к концу ленты копилка наполовину полна")
        // Через сутки полна: «собери!».
        let later = WidgetLook.looks(f, now: noon + 24 * 3600, tzOffsetMin: 0, cfg)
        XCTAssertTrue(later.first?.bankFull ?? false, "за сутки копилка полна")
        XCTAssertEqual(later.first?.bankLine?.hasSuffix("собери!"), true)
        XCTAssertTrue(later.first?.canCollect ?? false)
        XCTAssertGreaterThan(WidgetLook.reloadT(looks, now: noon, cfg), looks.last?.t ?? .infinity)

        // Без станций — копилки нет.
        let bare = WidgetLook.looks(file(at: noon), now: noon, tzOffsetMin: 0, cfg)
        XCTAssertNil(bare.first?.ring)
        XCTAssertNil(bare.first?.bankLine)
        XCTAssertEqual(bare.first?.lock, .pose)
    }

    func testLooksHungryAndOuting() {
        let hungry = WidgetLook.looks(file(at: noon, 90, [.food: 10]), now: noon, tzOffsetMin: 0, cfg)
        XCTAssertEqual(hungry.first?.pose, .bowl)
        XCTAssertEqual(hungry.first?.main?.need, .food)
        XCTAssertGreaterThan(hungry.first?.relevance ?? 0, 0.5)

        var g = file(at: noon)
        g.pet.outing = Outing(from: noon - 600, until: noon + 1200, find: "cone")
        let w = WidgetLook.looks(g, now: noon, tzOffsetMin: 0, cfg)
        XCTAssertEqual(w.first?.pose, .away)
        XCTAssertEqual(w.first?.lock, .trip)
        XCTAssertEqual(w.first?.tripUntil, noon + 1200)
        XCTAssertEqual(w.first?.tripFrom, noon - 600, "прогулка ядра — тоже с полоской")
        XCTAssertEqual(w.first?.tripProgress ?? -1, 600.0 / 1800, accuracy: 1e-9)
        XCTAssertEqual(w.first?.caption.hasPrefix("Гуляет"), true)
    }

    func testYardTierClamped() {
        var f = file(at: noon)
        XCTAssertEqual(IslandFeed.yardTier(f).index, 0)
        f.pet.home[.yard] = 99
        XCTAssertEqual(IslandFeed.yardTier(f).index, YardConfig.shared.maxTier)
    }

    // MARK: входы из сейва

    func testFeedBankFromYard() {
        var f = file(at: noon)
        XCTAssertNil(IslandFeed.bank(f, now: noon), "без станций копилки нет")
        f.yard.stations = ["dryer": 3]
        f.yard.t = noon
        f.yard.bank = 0
        guard let b = IslandFeed.bank(f, now: noon) else { return XCTFail("копилка есть") }
        XCTAssertEqual(b.fullAt - (b.from ?? 0), YardConfig.shared.bankHours * 3600, accuracy: 1e-6)
        XCTAssertEqual(b.ring(at: noon), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(b.coins ?? 0, 0)
    }

    func testFeedTripFromPlaces() {
        var f = file(at: noon)
        XCTAssertNil(IslandFeed.trip(f, now: noon, cfg))
        f.trip.active = ActiveTrip(place: "nope-place", from: noon - 900, start: noon - 600, until: noon + 1800, star: false)
        let t = IslandFeed.trip(f, now: noon, cfg)
        XCTAssertEqual(t?.from, noon - 600)
        XCTAssertEqual(t?.backAt, noon + 1800)
        XCTAssertEqual(t?.place, "Прогулка", "неизвестное место — просто прогулка")
    }

    func testFeedLevelUp() {
        var f = file(at: noon)
        XCTAssertNil(IslandFeed.levelUp(f))
        f.level.lastUp = LevelUp(level: 14, coins: 50, shards: 0, t: noon)
        XCTAssertEqual(IslandFeed.levelUp(f), IslandLevelUp(level: 14, at: noon))
    }

    // MARK: «Собрать» из виджета

    func testCollectGivesCoinsAndXp() {
        var f = file(at: noon - 12 * 3600)
        f.yard.stations = ["dryer": 3]
        f.yard.t = noon - 12 * 3600
        f.yard.bank = 0
        // Сначала догоняем ядро и опыт за прошедшие сутки (хороший день и т. п.) — меряем только сбор.
        PetRunner.catchUp(&f, now: noon)
        DogLevel.settle(&f, now: noon)
        let xp0 = f.level.xp
        let coins0 = f.econ.wallet.coins
        let h = WidgetLook.collect(in: &f, now: noon)
        XCTAssertFalse(h.isEmpty)
        XCTAssertGreaterThan(h.coins, 0)
        XCTAssertEqual(f.econ.wallet.coins, coins0 + h.coins)
        // yard.collect даёт 4 XP, первый сбор — ещё бонус «первый раз».
        XCTAssertEqual(f.level.xp - xp0, 4 + DogLevelConfig.shared.firstBonus, "yard.collect даёт 4 XP")
        XCTAssertTrue(f.journal.contains { $0.kind == "yard.collect" })
        XCTAssertEqual(Yard.peek(f.yard, now: noon, dogLevel: DogLevel.level(f)).bank, 0, accuracy: 1e-9)
        // Второй раз пусто — ни монет, ни опыта.
        let xp1 = f.level.xp
        XCTAssertTrue(WidgetLook.collect(in: &f, now: noon).isEmpty)
        XCTAssertEqual(f.level.xp, xp1)
    }

    // Волна 35 N: обратный отсчёт текстом — для замороженных снимков (Text(timerInterval:pauseTime:) показывал прошедшее).
    func testCountdownText() {
        XCTAssertEqual(IslandLook.countdown(2400), "40:00")
        XCTAssertEqual(IslandLook.countdown(5400), "1:30:00")
        XCTAssertEqual(IslandLook.countdown(3605), "1:00:05")
        XCTAssertEqual(IslandLook.countdown(5), "0:05")
        XCTAssertEqual(IslandLook.countdown(59.2), "1:00")
        XCTAssertEqual(IslandLook.countdown(-30), "0:00")
        XCTAssertEqual(IslandLook.countdown(.nan), "0:00")
        XCTAssertEqual(IslandLook.countdown(.infinity), "0:00")
    }
}
