// Волна 43 K: просьбы пса (DogAsks.swift). Расписание детерминировано по (petId, сутки, час) и одинаково для
// приложения и виджета, не больше perDay в сутки, не ночью; просьба по нужде; окно; награда и ask.done один раз;
// часы назад без второй оплаты; новый щенок наследует день; опыт через DogLevel; старые сейвы читаются.
// Гоняется и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000.
private let aT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

/// Пёс уровня lvl, бодрый, учёт уровня заведён; достижения уже получены — считаем только монеты просьб.
private func aFile(level lvl: Int = 1, at t: Double = aT0) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = "asks-pet-1"
    for n in Need.allCases { f.pet.needs[n] = 90 }
    DogLevel.settle(&f, now: t)
    f.level.xp = DogLevel.xpTo(lvl)
    f.level.paidLevel = lvl
    f.shardLog.once += Achievements.all.map { Achievements.key($0.id) }
    return f
}

/// Сегодня — ровно одна просьба kind со стартом start.
private func force(_ f: inout SaveFile, _ kind: String, start: Double, coins: Int = 10) {
    DogAsks.settle(&f, now: start)
    f.asks.items = [DogAsk(start: start, kind: kind, coins: coins)]
}

private func count(_ f: SaveFile, _ kind: String) -> Int { f.journal.filter { $0.kind == kind }.count }

final class DogAsksTests: XCTestCase {

    override func setUp() {
        super.setUp()
        DogAsks.enabled = true
    }

    override func tearDown() {
        Clock.zoneOverride = nil
        DogAsks.enabled = true
        DailyTasks.enabled = true
        super.tearDown()
    }

    // MARK: конфиг

    func testConfigMatchesEconomyJSON() {
        let code = DogAskConfig(), json = DogAskConfig.shared
        XCTAssertEqual(code.perDay, json.perDay)
        XCTAssertEqual(code.chancePct, json.chancePct)
        XCTAssertEqual(code.minGapMin, json.minGapMin)
        XCTAssertEqual(code.windowMin, json.windowMin)
        XCTAssertEqual(code.wakeGapMin, json.wakeGapMin)
        XCTAssertEqual(code.coinBase, json.coinBase)
        XCTAssertEqual(code.coinPerLevel, json.coinPerLevel)
        XCTAssertEqual(code.coinRound, json.coinRound)
        XCTAssertEqual(code.below, json.below)
        XCTAssertEqual(Set(code.below.keys), Set(DogAsks.needOrder.map(\.need.rawValue)), "у каждой шкалы есть порог")
        // Монеты — немного: 5 + 1 × уровень, к ближайшим 5.
        XCTAssertEqual(code.coins(level: 1), 5)
        XCTAssertEqual(code.coins(level: 10), 15)
        XCTAssertEqual(code.coins(level: 20), 25)
        XCTAssertEqual(code.coins(level: 30), 35)
        XCTAssertEqual(code.windowMin, 60)
        XCTAssertLessThanOrEqual(code.perDay, 6)
    }

    // MARK: расписание

    func testScheduleIsDeterministicAndPerPet() {
        let a = aFile()
        var b = aFile(at: aT0 + 3600)
        let day = DayKey.of(aT0)
        XCTAssertEqual(DogAsks.schedule(a, day: day), DogAsks.schedule(b, day: day), "тот же пёс — те же старты")
        b.petId = "another-pet"
        let mine = (0..<14).map { DogAsks.schedule(a, day: day + $0) }
        let other = (0..<14).map { DogAsks.schedule(b, day: day + $0) }
        XCTAssertNotEqual(mine, other, "у другого пса — своё расписание")
        XCTAssertGreaterThan(Set(mine.map { $0.map { Int($0) % 86400 } }).count, 3, "дни не одинаковые")
    }

    func testScheduleLimitGapAndNight() {
        let f = aFile()
        let r = ItemPerks.rules(f)
        let cfg = DogAskConfig()
        let day = DayKey.of(aT0)
        var total = 0
        for d in day..<(day + 60) {
            let starts = DogAsks.schedule(f, day: d)
            total += starts.count
            XCTAssertLessThanOrEqual(starts.count, cfg.perDay, "не больше perDay в сутки")
            for (i, s) in starts.enumerated() {
                XCTAssertEqual(DayKey.of(s), d)
                if i > 0 { XCTAssertGreaterThanOrEqual(s - starts[i - 1], Double(cfg.minGapMin) * 60) }
                for t in [s, s + cfg.window - 60] {
                    let o = PetRunner.owner(f, at: t)
                    XCTAssertFalse(PetEngine.ownerAsleep(t, o), "хозяин спит")
                    XCTAssertFalse(PetEngine.petNight(t, r, o), "ночь пса")
                }
                let o = PetRunner.owner(f, at: s)
                XCTAssertFalse(PetEngine.ownerAsleep(s - Double(cfg.wakeGapMin) * 60, o), "сразу после подъёма")
            }
        }
        let avg = Double(total) / 60
        XCTAssertGreaterThanOrEqual(avg, 2, "в среднем хотя бы пара просьб в день")
        XCTAssertLessThanOrEqual(avg, 5.5)
    }

    func testDailyLimitWithEveryHour() {
        let f = aFile()
        let cfg = DogAskConfig(json: .object(["asks": .object(["chance_pct": .number(100), "min_gap_min": .number(0)])]))
        let starts = DogAsks.schedule(f, day: DayKey.of(aT0), cfg)
        XCTAssertEqual(starts.count, cfg.perDay, "каждый час выпадает — упор в per_day")
        let none = DogAskConfig(json: .object(["asks": .object(["per_day": .number(0)])]))
        XCTAssertTrue(DogAsks.schedule(f, day: DayKey.of(aT0), none).isEmpty)
    }

    func testSettleBuildsTodayAndDecidesOnlyStarted() {
        var f = aFile()
        let day = DayKey.of(aT0)
        DogAsks.settle(&f, now: aT0)
        XCTAssertTrue(f.asks.started)
        XCTAssertEqual(f.asks.day, day)
        XCTAssertEqual(f.asks.items.map(\.start), DogAsks.schedule(f, day: day))
        for a in f.asks.items {
            if a.start <= aT0 { XCTAssertNotNil(a.kind, "наступившая — решена") } else { XCTAssertNil(a.kind, "будущая — нет") }
        }
    }

    // MARK: что просит

    func testAskFollowsNeeds() {
        var f = aFile()
        let t = aT0 + 60
        f.pet.needs[.food] = 20
        XCTAssertEqual(DogAsks.choose(f, at: t, prev: nil), "feed", "голодный — еда")
        f.pet.needs[.food] = 90
        f.pet.needs[.clean] = 10
        XCTAssertEqual(DogAsks.choose(f, at: t, prev: nil), "bath", "грязный — помыть")
        f.pet.needs[.clean] = 90
        f.pet.needs[.love] = 20
        XCTAssertEqual(DogAsks.choose(f, at: t, prev: nil), "pet", "соскучился — погладить")
        f.pet.needs[.love] = 90
        f.pet.needs[.fun] = 20
        XCTAssertEqual(DogAsks.choose(f, at: t, prev: nil), "play", "скучно — поиграть")
        f.pet.needs[.fun] = 90
        // Всё хорошо — что-то «для души», не то же, что прошлая просьба.
        for prev in DogAsks.funPool {
            let k = DogAsks.choose(f, at: t, prev: prev)
            XCTAssertTrue(DogAsks.funPool.contains(k) || k == DogAsks.skip, k)
            XCTAssertNotEqual(k, prev)
        }
    }

    func testNoAskWhenAwayBathingOrNapping() {
        var f = aFile()
        let t = aT0 + 60
        f.pet.outing = Outing(from: aT0 - 60, until: aT0 + 3600, find: "stick")
        XCTAssertEqual(DogAsks.choose(f, at: t, prev: nil), DogAsks.skip, "гуляет")
        f.pet.outing = nil
        f.pet.bathUntil = aT0 + 600
        XCTAssertEqual(DogAsks.choose(f, at: t, prev: nil), DogAsks.skip, "моется")
        f.pet.bathUntil = nil
        f.pet.napUntil = aT0 + 1800
        XCTAssertEqual(DogAsks.choose(f, at: t, prev: nil), DogAsks.skip, "спит")
        f.pet.napUntil = nil
        f.pet.alive = false
        XCTAssertEqual(DogAsks.choose(f, at: t, prev: nil), DogAsks.skip, "нет пса")
    }

    func testLongCooldownMakesAskUndoable() {
        var f = aFile()
        let t = aT0 + 60
        f.pet.cooldowns["pet"] = t + 3 * 3600
        XCTAssertFalse(DogAsks.doable("pet", f.pet, f, at: t), "откат на часы — не просит")
        f.pet.cooldowns["pet"] = t + 5 * 60
        XCTAssertTrue(DogAsks.doable("pet", f.pet, f, at: t), "откат скоро пройдёт — можно")
    }

    // MARK: окно и награда

    func testWindowBounds() {
        var f = aFile()
        let s = aT0 + 600
        force(&f, "pet", start: s)
        let coins = f.econ.wallet.coins
        f.log("act.pet", t: s - 30, ok: true)                  // до старта — мимо
        f.log("act.pet", t: s + 3600 + 30, ok: true)           // после окна — мимо
        f.log("act.feed", t: s + 60, ok: true)                 // не то — мимо
        f.log("act.pet", t: s + 120, ok: false, reason: "cooldown")   // отказ — мимо
        DogAsks.settle(&f, now: s + 3700)
        XCTAssertFalse(f.asks.items[0].done)
        XCTAssertEqual(f.econ.wallet.coins, coins, "не выполнено — без награды и без наказания")
        XCTAssertEqual(count(f, DogAsks.doneKind), 0)

        var g = aFile()
        force(&g, "pet", start: s)
        let c0 = g.econ.wallet.coins
        g.log("act.pet", t: s + 3600 - 5, ok: true)            // последняя минута окна — засчитано
        DogAsks.settle(&g, now: s + 3600)
        XCTAssertTrue(g.asks.items[0].done)
        XCTAssertEqual(g.econ.wallet.coins, c0 + 10)
        XCTAssertEqual(g.asks.total, 1)
        XCTAssertEqual(g.asks.last?.kind, "pet")
    }

    func testSettleIsIdempotent() {
        var f = aFile()
        let s = aT0 + 600
        force(&f, "play", start: s)
        let coins = f.econ.wallet.coins
        f.log("act.play", t: s + 60, ok: true)
        f.log("act.play", t: s + 120, ok: true)                // второй раз — та же просьба, не вторая оплата
        for _ in 0..<3 { DogAsks.settle(&f, now: s + 130) }
        XCTAssertEqual(f.econ.wallet.coins, coins + 10)
        XCTAssertEqual(count(f, DogAsks.doneKind), 1)
        XCTAssertEqual(f.asks.total, 1)
        let e = f.journal.last { $0.kind == DogAsks.doneKind }
        XCTAssertEqual(e?.key, "play")
        XCTAssertEqual(e?.value, 10)
        XCTAssertEqual(e?.t, s + 60, "ask.done — временем выполнения")
    }

    func testAskDoneGivesXpThroughDogLevel() {
        var f = aFile()
        let s = aT0 + 600
        force(&f, "walk", start: s)
        f.log("act.walk", t: s + 10, ok: true)
        DogAsks.settle(&f, now: s + 10)
        let out = DogLevel.settle(&f, now: s + 10)
        XCTAssertTrue(out.gains.contains { $0.reason == "ask" && $0.xp == 5 }, "ask.done — 5 опыта")
        XCTAssertEqual(DogLevel.reasonText("ask"), "за просьбу пса")
    }

    func testRealActionThroughPetRunner() {
        var f = aFile()
        f.pet.needs[.love] = 40
        let s = aT0 + 60
        force(&f, "pet", start: s)
        let xp0 = f.level.xp
        let coins0 = f.econ.wallet.coins
        XCTAssertTrue(PetRunner.apply(.pet, source: .app, to: &f, now: s + 120).ok)
        XCTAssertTrue(f.asks.items[0].done, "settleRewards в конце apply закрывает просьбу")
        XCTAssertEqual(count(f, DogAsks.doneKind), 1)
        XCTAssertGreaterThanOrEqual(f.econ.wallet.coins, coins0 + 10)
        XCTAssertGreaterThanOrEqual(f.level.xp, xp0 + 5, "опыт той же записью (DogLevel после DogAsks)")
    }

    // MARK: приложение и виджет видят одно

    func testWidgetAndAppSeeTheSameAsk() throws {
        let day = DayKey.of(aT0)
        var f = aFile(at: DayKey.start(day))
        // Первая просьба суток, у которой стейт на старт решает что-то (сутки с хотя бы одной просьбой — найдутся).
        var start: Double?
        var d = day
        while start == nil, d < day + 10 {
            start = DogAsks.schedule(f, day: d).first
            if start == nil { d += 1 }
        }
        guard let s = start else { throw XCTSkip("за 10 суток нет просьб") }
        f = aFile(at: s - 2 * 3600)                      // файл записан за два часа до старта
        f.pet.needs[.food] = 60                          // к старту проголодается или нет — решает стейт на старт
        let now = s + 20 * 60
        let widget = DogAsks.current(f, now: now)       // виджет: копия, без записи
        var app = f
        PetRunner.catchUp(&app, now: now)               // приложение: запись с догоном
        let stored = app.asks.items.first { $0.start == s }
        XCTAssertEqual(stored?.kind, DogAsks.choose(f, at: s, prev: nil), "решено по стейту на старт")
        if let w = widget {
            XCTAssertEqual(w.kind, stored?.kind)
            XCTAssertEqual(DogAsks.current(app, now: now)?.kind, w.kind)
        } else {
            XCTAssertNil(DogAsks.current(app, now: now))
            XCTAssertFalse(stored?.real ?? false)
        }
    }

    // MARK: часы и сутки

    func testClockBackGivesNoRepeatReward() {
        var f = aFile()
        let tomorrow = aT0 + 86400
        let day = DayKey.of(aT0)
        force(&f, "brush", start: tomorrow)
        XCTAssertEqual(f.asks.day, day + 1)
        f.log(Brush.actKind, t: tomorrow + 60, ok: true)
        DogAsks.settle(&f, now: tomorrow + 60)
        XCTAssertTrue(f.asks.items[0].done)
        let coins = f.econ.wallet.coins
        // Часы назад: сутки не откатываются, нового расписания нет, сегодняшние записи не платят.
        f.log(Brush.actKind, t: aT0 + 100, ok: true)
        f.log("act.pet", t: aT0 + 110, ok: true)
        DogAsks.settle(&f, now: aT0 + 120)
        XCTAssertEqual(f.asks.day, day + 1)
        XCTAssertEqual(f.asks.items.count, 1)
        XCTAssertEqual(f.econ.wallet.coins, coins)
        // Настоящее «завтра» наступило — те же сутки, второй оплаты нет.
        f.log(Brush.actKind, t: tomorrow + 120, ok: true)
        DogAsks.settle(&f, now: tomorrow + 130)
        XCTAssertEqual(f.econ.wallet.coins, coins)
        XCTAssertEqual(count(f, DogAsks.doneKind), 1)
        // Через PetRunner (observe + settleRewards) — тоже ни второй просьбы, ни второй записи ask.done.
        var g = f
        PetRunner.catchUp(&g, now: aT0 + 200)
        XCTAssertEqual(g.asks.day, day + 1)
        XCTAssertEqual(g.asks.total, 1)
        XCTAssertEqual(count(g, DogAsks.doneKind), 1)
    }

    func testMidnightRollsToNewSchedule() {
        var f = aFile()
        let day = DayKey.of(aT0)
        DogAsks.settle(&f, now: aT0)
        let midnight = DayKey.start(day + 1)
        DogAsks.settle(&f, now: midnight + 60)
        XCTAssertEqual(f.asks.day, day + 1)
        XCTAssertEqual(f.asks.items.map(\.start), DogAsks.schedule(f, day: day + 1))
        XCTAssertTrue(f.asks.items.allSatisfy { !$0.done })
    }

    // MARK: сейв и щенок

    func testOldSaveDecodesAndEmptyIsNotWritten() throws {
        DogAsks.enabled = false
        var f = aFile()
        f.asks = DogAsksLog()
        let data = try JSONEncoder().encode(f)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"asks\""), "пустое не пишется")
        XCTAssertTrue(try JSONDecoder().decode(SaveFile.self, from: data).asks.isEmpty)
        DogAsks.enabled = true
        force(&f, "feed", start: aT0)
        f.asks.last = AskWin(kind: "feed", coins: 10, t: aT0)
        let again = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(again.asks, f.asks)
        let partial = try JSONDecoder().decode(DogAsksLog.self, from: Data(#"{"day": 5, "items": "x", "total": 3}"#.utf8))
        XCTAssertEqual(partial.day, 5)
        XCTAssertEqual(partial.total, 3)
        XCTAssertTrue(partial.items.isEmpty)
    }

    func testNewPuppyInheritsTheDay() {
        var f = aFile()
        let s = aT0 + 600
        force(&f, "pet", start: s)
        f.log("act.pet", t: s + 5, ok: true)
        DogAsks.settle(&f, now: s + 5)
        XCTAssertTrue(f.asks.items[0].done)
        let carried = f.asks.carriedOver()
        XCTAssertEqual(carried.seenSeq, 0)
        XCTAssertNil(carried.last)
        XCTAssertEqual(carried.items, f.asks.items)
        var pup = SaveFile.fresh(now: s + 60)
        pup.petId = "asks-pup"
        pup.econ = f.econ.carriedOver()
        pup.asks = carried
        let coins = pup.econ.wallet.coins
        pup.log("act.pet", t: s + 70, ok: true)
        DogAsks.settle(&pup, now: s + 80)
        XCTAssertEqual(pup.asks.day, f.asks.day)
        XCTAssertEqual(pup.asks.items.map(\.start), f.asks.items.map(\.start), "нового расписания за сутки нет")
        XCTAssertEqual(pup.econ.wallet.coins, coins, "выполненная просьба не платит второй раз")
        XCTAssertTrue(DogAsksLog().carriedOver().isEmpty)
    }

    func testDisabledDoesNothing() {
        DogAsks.enabled = false
        var f = aFile()
        f.log("act.pet", t: aT0, ok: true)
        DogAsks.settle(&f, now: aT0)
        DogAsks.observe(&f, now: aT0)
        XCTAssertTrue(f.asks.isEmpty)
        XCTAssertNil(DogAsks.current(f, now: aT0))
    }

    // MARK: тексты

    func testTexts() {
        for (k, _) in DogAsks.kinds {
            XCTAssertFalse(DogAskText.line(k).isEmpty)
            XCTAssertNotEqual(DogAskText.emoji(k), "🐾", k)
        }
        let a = DogAsk(start: aT0, kind: "feed", coins: 10)
        XCTAssertEqual(DogAskText.plate(a, now: aT0 + 20 * 60), "Хочу кушать! · ещё 40 мин")
        XCTAssertEqual(DogAskText.hint(a), "Нажми «Покормить» — +10 🪙")
        XCTAssertEqual(DogAskText.toast(AskWin(kind: "walk", coins: 15, t: aT0)), "Просьба выполнена! Гулять · +15 🪙")
        XCTAssertEqual(DogAsks.minutesLeft(a, now: aT0 + 3599), 1)
    }
}
