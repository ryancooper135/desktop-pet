// Волна 33 A: уровень пса (DogLevel.swift). Кривая = таблица RESEARCH/20 §3; опыт по журналу идемпотентно,
// часы назад не платят, потолок 150 в сутки и лимиты по видам; ур. 40 — предел; награды за уровни один раз;
// старый сейв — не выше ур. 10; открытия по таблице; модель «неделя ухода → ур. 10»; конфиг = config/wave33/level.json.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000.
private let lT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

/// Новый пёс; первый settle уже был (учёт заведён, переносить нечего).
private func lFile(at t: Double = lT0) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = "level-pet-1"
    DogLevel.settle(&f, now: t)
    return f
}

/// n удачных дел вида kind с момента t (журнал, как пишет PetRunner.apply).
private func acts(_ f: inout SaveFile, _ n: Int, at t: Double, kind: String = "act.feed") {
    for i in 0..<n { f.log(kind, t: t + Double(i), ok: true) }
}

/// Полдень k-х суток после lT0 (с летним временем — тот же местный час).
private func noon(_ k: Int) -> Double { DayKey.start(DayKey.of(lT0) + k) + 12 * 3600 }

/// Сыграть n партий в «Лови мячик» с наградой в момент t (как пишет CatchGame).
private func catchGames(_ f: inout SaveFile, _ n: Int, at t: Double) {
    let d = DayKey.of(t)
    if f.catchDay != d { f.catchDay = d; f.catchGames = 0 }
    f.catchGames += n
}

private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

final class DogLevelTests: XCTestCase {

    // MARK: сейв и конфиг

    func testEmptyIsNotWritten() throws {
        let f = SaveFile.fresh(now: 1_760_054_400)
        let data = try JSONEncoder().encode(f)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(obj?["level"], "пустое поле не пишется в сейв")
        XCTAssertNoThrow(try JSONDecoder().decode(SaveFile.self, from: data))
    }

    func testRoundTripAndTolerantDecode() throws {
        var f = lFile()
        acts(&f, 3, at: lT0 + 10)
        DogLevel.settle(&f, now: lT0 + 20)
        XCTAssertFalse(f.level.isEmpty)
        let back = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back.level, f.level, "уровень переживает запись и чтение")
        // Кривое поле не роняет сейв: что прочлось — то и есть, остальное по умолчанию.
        let junk = #"{"xp": "много", "started": true, "seenSeq": 7, "counts": [1, 2]}"#
        let l = try JSONDecoder().decode(DogLevelLog.self, from: Data(junk.utf8))
        XCTAssertEqual(l.xp, 0)
        XCTAssertTrue(l.started)
        XCTAssertEqual(l.seenSeq, 7)
        XCTAssertEqual(l.counts, [:])
        XCTAssertEqual(l.paidLevel, 1)
    }

    func testLevelJsonMatchesDefaults() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("config/wave33/level.json")
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        let fromJson = DogLevelConfig(json: json)
        let code = DogLevelConfig()
        XCTAssertEqual(fromJson.rules, code.rules, "источники опыта в level.json и в коде разошлись")
        XCTAssertEqual(fromJson.unlocks, code.unlocks, "открытия в level.json и в коде разошлись")
        XCTAssertEqual(fromJson, code, "цифры уровня в level.json и умолчания в коде разошлись")
        // В economy.json раздела пока нет (переносит сливающий) — или он тот же.
        XCTAssertEqual(DogLevelConfig.shared, code)
        XCTAssertEqual(DogLevelConfig(json: .null), code, "нет раздела — умолчания")
    }

    // MARK: кривая

    func testCurveMatchesTable() {
        // RESEARCH/20 §3: всего опыта до уровня.
        let table = [1: 0, 2: 25, 3: 55, 4: 100, 5: 155, 6: 230, 7: 320, 8: 430, 9: 560, 10: 715,
                     11: 895, 12: 1100, 15: 1890, 20: 3860, 25: 6775, 30: 10780, 35: 16010, 40: 22570]
        for (l, xp) in table {
            XCTAssertEqual(DogLevel.xpTo(l), xp, "ур. \(l)")
            XCTAssertEqual(DogLevel.level(xp: xp), l, "ровно \(xp) — уже ур. \(l)")
            if l > 1 { XCTAssertEqual(DogLevel.level(xp: xp - 1), l - 1, "\(xp - 1) — ещё ур. \(l - 1)") }
        }
        XCTAssertEqual(DogLevel.xpStep(1), 25)
        XCTAssertEqual(DogLevel.xpStep(9), 155)
        XCTAssertEqual(DogLevel.xpStep(39), 1425)
        for l in 1..<40 { XCTAssertEqual(DogLevel.xpStep(l) % 5, 0, "шаг кратен 5") }
        for l in 2..<40 { XCTAssertGreaterThan(DogLevel.xpStep(l), DogLevel.xpStep(l - 1), "кривая растёт") }
        XCTAssertEqual(DogLevel.level(xp: 0), 1)
        XCTAssertEqual(DogLevel.level(xp: 10_000_000), 40, "выше 40 не бывает")
        XCTAssertEqual(DogLevel.xpTo(99), 22570)
    }

    func testProgressAndHeader() {
        var f = lFile()
        f.level.xp = 715 + 40
        let p = DogLevel.progress(f)
        XCTAssertEqual(p.level, 10)
        XCTAssertEqual(p.into, 40)
        XCTAssertEqual(p.need, 180)
        XCTAssertFalse(p.isMax)
        XCTAssertEqual(DogLevel.headerText(p), "Ур. 10 · 40 из 180")
        f.level.xp = 22570
        let top = DogLevel.progress(f)
        XCTAssertTrue(top.isMax)
        XCTAssertEqual(top.fraction, 1)
        XCTAssertEqual(DogLevel.headerText(top), "Ур. 40 · предел")
    }

    // MARK: опыт по журналу

    func testFreshPuppyStartsAtLevelOne() {
        let f = lFile()
        XCTAssertTrue(f.level.started)
        XCTAssertEqual(f.level.xp, 0)
        XCTAssertEqual(f.level.migrated, 0)
        XCTAssertEqual(DogLevel.level(f), 1)
    }

    func testXpPerKindAndRepeatSettleGivesNothing() {
        var f = lFile()
        acts(&f, 2, at: lT0 + 10)                            // 2 × 2 + 5 «первый раз»
        acts(&f, 1, at: lT0 + 20, kind: "act.play")          // 3 + 5
        f.log("ev.back_home.bone", t: lT0 + 30, key: "bone") // прогулка: 10 + 5
        f.log("trick.learn", t: lT0 + 40, key: "sit")        // 20 + 5
        let o = DogLevel.settle(&f, now: lT0 + 50)
        XCTAssertEqual(o.xp, 4 + 3 + 10 + 20 + 4 * 5)
        XCTAssertEqual(f.level.xp, o.xp)
        XCTAssertEqual(Set(o.gains.map(\.reason)), ["feed", "play", "walk", "trick",
                                                   "first.feed", "first.play", "first.walk", "first.trick"])
        let again = DogLevel.settle(&f, now: lT0 + 60)
        XCTAssertEqual(again, LevelOutcome(), "второй раз ничего")
        XCTAssertEqual(DogLevel.settle(&f, now: lT0 + 70).xp, 0)
        acts(&f, 1, at: lT0 + 80)
        XCTAssertEqual(DogLevel.settle(&f, now: lT0 + 90).xp, 2, "бонус «первый раз» — один раз")
    }

    func testFailedAndForeignEntriesGiveNothing() {
        var f = lFile()
        f.log("act.feed", t: lT0 + 1, ok: false, reason: "cooldown")
        f.log("act.steps", t: lT0 + 2, ok: true, value: 3000)
        f.log("act.brush", t: lT0 + 3, ok: true)
        f.log("ev.low", t: lT0 + 4, key: "food")
        f.log("shop.buy", t: lT0 + 5, key: "ball")
        f.log("trick.learn", t: lT0 + 6, ok: false, key: "sit")
        // Запись другого устройства (синк) — не наша, не считаем.
        f.journal.append(JournalEntry(id: "other-device:999", t: lT0 + 7, kind: "act.feed", source: nil, ok: true,
                                      reason: nil, key: nil, value: nil))
        XCTAssertEqual(DogLevel.settle(&f, now: lT0 + 10).xp, 0)
    }

    func testPerKindLimits() {
        var f = lFile()
        acts(&f, 15, at: lT0 + 10, kind: "act.pet")
        acts(&f, 3, at: lT0 + 100, kind: "act.bath")
        DogLevel.settle(&f, now: lT0 + 200)
        XCTAssertEqual(f.level.xp, 10 + 8 + 2 * 5, "ласка — 10 в сутки, купание — 1")
        XCTAssertEqual(f.level.counts["pet"], 10)
        // Новые сутки — лимиты заново.
        acts(&f, 12, at: noon(1), kind: "act.pet")
        let o = DogLevel.settle(&f, now: noon(1) + 100)
        XCTAssertEqual(o.gains.filter { $0.reason == "pet" }.reduce(0) { $0 + $1.xp }, 10)
    }

    func testDailyCap() {
        var f = lFile()
        acts(&f, 100, at: lT0 - 3 * 3600)                    // 200 опыта за еду
        DogLevel.settle(&f, now: lT0)
        XCTAssertEqual(f.level.dayXp, 150)
        XCTAssertEqual(f.level.xp, 150 + 5, "потолок 150 + бонус «первый раз» сверху")
        acts(&f, 10, at: lT0 + 100, kind: "act.play")
        f.log("trick.learn", t: lT0 + 200, key: "paw")
        DogLevel.settle(&f, now: lT0 + 300)
        XCTAssertEqual(f.level.xp, 150 + 5 + 5 + 5, "сверх потолка — только бонусы «первый раз»")
        // Хороший день за полные сутки тоже упирается в потолок.
        acts(&f, 100, at: noon(1))
        let o = DogLevel.settle(&f, now: noon(1) + 500)
        XCTAssertFalse(o.gains.contains { $0.reason == "good_day" && $0.xp > 0 })
        XCTAssertEqual(o.xp, 150)
    }

    func testClockBackGivesNoXp() {
        var f = lFile()
        acts(&f, 2, at: noon(1))
        DogLevel.settle(&f, now: noon(1) + 10)
        let xp = f.level.xp
        // Часы назад на сутки: вчерашние дела не платят ни сейчас, ни потом.
        acts(&f, 30, at: lT0 + 100)
        acts(&f, 5, at: lT0 + 200, kind: "act.play")
        XCTAssertEqual(DogLevel.settle(&f, now: lT0 + 300).xp, 0)
        XCTAssertEqual(f.level.day, DayKey.of(noon(1)), "сутки учёта назад не откатываются")
        XCTAssertEqual(DogLevel.settle(&f, now: noon(1) + 400).xp, 0, "и когда часы вернули — тоже")
        XCTAssertEqual(f.level.xp, xp)
        // Перевод вперёд и обратно: прошлые сутки второй раз не открываются.
        acts(&f, 2, at: noon(3))
        DogLevel.settle(&f, now: noon(3) + 10)
        acts(&f, 5, at: noon(2))
        XCTAssertEqual(DogLevel.settle(&f, now: noon(2) + 100).xp, 0)
    }

    func testMiniGamesCountedOnceAndCapped() {
        var f = lFile()
        catchGames(&f, 3, at: lT0)
        XCTAssertEqual(DogLevel.settle(&f, now: lT0 + 10).xp, 3 * 5 + 5)
        XCTAssertEqual(DogLevel.settle(&f, now: lT0 + 20).xp, 0, "те же партии второй раз не платят")
        catchGames(&f, 1, at: lT0 + 30)
        f.zombieDay = DayKey.of(lT0); f.zombieGames = 5
        XCTAssertEqual(DogLevel.settle(&f, now: lT0 + 40).xp, 3 * 5, "6 партий в сутки на все игры: из 9 платят 6")
        // Новые сутки: счётчик игры с нуля.
        catchGames(&f, 2, at: noon(1))
        let o = DogLevel.settle(&f, now: noon(1) + 10)
        XCTAssertEqual(o.gains.filter { $0.reason == "game" }.count, 2)
        XCTAssertTrue(f.level.visited, "игра — это заход")
    }

    func testGoodDay() {
        // Был заход и в полночь ≥ 3 сердец — +15, когда сутки закрылись.
        var f = lFile()
        acts(&f, 1, at: lT0 + 10)
        f.pet.t = lT0 + 20
        f.pet.hearts = 4
        DogLevel.settle(&f, now: lT0 + 20)
        let o = DogLevel.settle(&f, now: noon(1))
        XCTAssertEqual(o.gains.map(\.reason), ["good_day"])
        XCTAssertEqual(o.xp, 15)
        XCTAssertEqual(DogLevel.settle(&f, now: noon(1) + 10).xp, 0, "один раз")
        // Дальше сутки без захода — без «хорошего дня».
        XCTAssertEqual(DogLevel.settle(&f, now: noon(3)).xp, 0)

        // Потеря сердец до 2 вечером — не хороший день.
        var g = lFile()
        acts(&g, 1, at: lT0 + 10)
        g.pet.t = lT0 + 20
        g.pet.hearts = 5
        DogLevel.settle(&g, now: lT0 + 20)
        g.log("ev.heart", t: lT0 + 8 * 3600, value: 2)
        XCTAssertFalse(DogLevel.settle(&g, now: noon(1)).gains.contains { $0.reason == "good_day" })

        // Пёс умер — тоже нет.
        var h = lFile()
        acts(&h, 1, at: lT0 + 10)
        h.log("ev.death", t: lT0 + 3600)
        XCTAssertFalse(DogLevel.settle(&h, now: noon(1)).gains.contains { $0.reason == "good_day" })
    }

    // MARK: предел и награды

    func testRewardsPaidOnce() {
        XCTAssertEqual(DogLevel.reward(2).coins, 40)
        XCTAssertEqual(DogLevel.reward(2).shards, 0)
        XCTAssertEqual(DogLevel.reward(5).coins, 100)
        XCTAssertEqual(DogLevel.reward(5).shards, 5)
        XCTAssertEqual(DogLevel.reward(40).shards, 5)
        XCTAssertEqual((2...40).reduce(0) { $0 + DogLevel.reward($1).shards }, 40, "✂️ за все уровни — 40")
        XCTAssertEqual((2...40).reduce(0) { $0 + DogLevel.reward($1).coins }, 20 * (2...40).reduce(0, +))

        var f = lFile()
        f.level.xp = DogLevel.xpTo(5) - 1
        f.level.paidLevel = 4
        let coins = f.econ.wallet.coins, shards = f.econ.wallet.shards
        acts(&f, 1, at: lT0 + 10)
        let o = DogLevel.settle(&f, now: lT0 + 20)
        XCTAssertEqual(o.ups, [LevelUp(level: 5, coins: 100, shards: 5, t: lT0 + 20)])
        XCTAssertEqual(f.econ.wallet.coins, coins + 100)
        XCTAssertEqual(f.econ.wallet.shards, shards + 5)
        XCTAssertEqual(DogLevel.upText(o.ups[0]), "Уровень 5! +\(EconText.coins(100)) · +\(EconText.shards(5))")
        XCTAssertEqual(DogLevel.freshUp(f, now: lT0 + 25, shownT: nil), o.ups[0])
        XCTAssertNil(DogLevel.freshUp(f, now: lT0 + 25, shownT: lT0 + 20), "показанный — не второй раз")
        XCTAssertNil(DogLevel.freshUp(f, now: lT0 + 60, shownT: nil), "старый — не показываем")
        DogLevel.settle(&f, now: lT0 + 30)
        XCTAssertEqual(f.econ.wallet.coins, coins + 100, "награда один раз")

        // Скачок через несколько уровней — награда за каждый.
        var g = lFile()
        g.log("yard.tier", t: lT0 + 1, key: "1")
        g.log("trick.learn", t: lT0 + 2, key: "sit")
        let c0 = g.econ.wallet.coins
        let jump = DogLevel.settle(&g, now: lT0 + 3)
        XCTAssertEqual(g.level.xp, 25 + 20 + 10)
        XCTAssertEqual(jump.ups.map(\.level), [2, 3])
        XCTAssertEqual(g.econ.wallet.coins, c0 + 40 + 60)
    }

    func testLevel40IsMax() {
        var f = lFile()
        f.level.xp = DogLevel.xpTo(40) - 5
        f.level.paidLevel = 39
        acts(&f, 50, at: lT0 + 10)
        let o = DogLevel.settle(&f, now: lT0 + 100)
        XCTAssertEqual(f.level.xp, DogLevel.xpTo(40), "опыт выше предела не копится")
        XCTAssertEqual(o.xp, 5)
        XCTAssertEqual(o.ups.map(\.level), [40])
        XCTAssertEqual(DogLevel.level(f), 40)
        acts(&f, 5, at: noon(1))
        XCTAssertEqual(DogLevel.settle(&f, now: noon(1) + 10).xp, 0)
        XCTAssertEqual(f.level.paidLevel, 40)
    }

    // MARK: старый сейв

    func testOldFixturesAtMostLevel10() throws {
        let files = try FileManager.default.contentsOfDirectory(at: fixtures, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertFalse(files.isEmpty)
        for url in files {
            var f = try JSONDecoder().decode(SaveFile.self, from: Data(contentsOf: url))
            XCTAssertTrue(f.level.isEmpty, "\(url.lastPathComponent): в старом сейве уровня нет")
            let coins = f.econ.wallet.coins, shards = f.econ.wallet.shards
            let now = max(f.lastSeenT ?? 0, f.pet.t) + 86400
            DogLevel.settle(&f, now: now)
            XCTAssertLessThanOrEqual(DogLevel.level(f), 10, url.lastPathComponent)
            XCTAssertEqual(f.level.xp, f.level.migrated, "\(url.lastPathComponent): старый журнал опыта не даёт")
            XCTAssertEqual(f.econ.wallet.coins, coins, "\(url.lastPathComponent): перенос без наград")
            XCTAssertEqual(f.econ.wallet.shards, shards)
            XCTAssertEqual(DogLevel.settle(&f, now: now + 10).xp, 0, "перенос — один раз")
        }
        // v0.14: один день заботы в окне характера → 60 опыта, ур. 3.
        var f = try JSONDecoder().decode(SaveFile.self, from: Data(contentsOf: fixtures.appendingPathComponent("save-v0.14.json")))
        DogLevel.settle(&f, now: (f.lastSeenT ?? f.pet.t) + 86400)
        XCTAssertEqual(f.level.migrated, 60)
        XCTAssertEqual(DogLevel.level(f), 3)
    }

    func testLongCaredSaveCappedAtLevel10() {
        var f = SaveFile.fresh(now: lT0)
        let today = DayKey.of(lT0)
        for d in 1...7 { f.care.days["\(today - d)"] = ["feed": 3, "pet": 2] }
        f.care.days["\(today - 8)"] = ["feed": 0]            // пустой день не считаем
        f.care.days["\(today)"] = ["feed": 5]                // сегодня — заплатит журнал, не перенос
        DogLevel.settle(&f, now: lT0)
        XCTAssertEqual(f.level.migrated, 7 * 60)

        var g = SaveFile.fresh(now: lT0)
        g.shardLog.goodDays = 200                            // долгоиграющий пёс
        DogLevel.settle(&g, now: lT0)
        XCTAssertEqual(g.level.xp, DogLevel.xpTo(10), "перенос — не выше ур. 10")
        XCTAssertEqual(DogLevel.level(g), 10)
        XCTAssertEqual(g.level.paidLevel, 10, "награды за перенесённые уровни не выдаются")
        acts(&g, 1, at: lT0 + 10)
        XCTAssertTrue(DogLevel.settle(&g, now: lT0 + 20).ups.isEmpty)
    }

    // MARK: открытия

    func testUnlocksTable() {
        for l in 1...40 { XCTAssertFalse(DogLevel.unlocks(l).isEmpty, "ур. \(l): ничего не открывает") }
        XCTAssertTrue(DogLevel.unlocks(41).isEmpty)
        XCTAssertEqual(DogLevel.unlocks(1).map(\.id), ["yard.0", "game.catch", "capsule"])
        XCTAssertEqual(DogLevel.needLevel("game.blockduo"), 3)
        XCTAssertEqual(DogLevel.needLevel("game.zombie"), 6)
        XCTAssertEqual(DogLevel.needLevel("spinner"), 10)
        XCTAssertNil(DogLevel.needLevel("nope"))
        XCTAssertTrue(DogLevel.isOpen("nope", level: 1), "чего нет в таблице — уровень не держит")
        XCTAssertFalse(DogLevel.isOpen("porridge", level: 6))
        XCTAssertTrue(DogLevel.isOpen("porridge", level: 7))
        XCTAssertEqual(DogLevel.unlocked(upTo: 2).count, 5)

        XCTAssertEqual([1, 3, 4, 8, 9, 11, 12, 19, 20, 40].map { DogLevel.yardTierMax(level: $0) },
                       [0, 0, 1, 1, 2, 2, 3, 3, 4, 4])
        XCTAssertEqual([1, 4, 5, 11, 12, 40].map { DogLevel.homeLineMax(level: $0) }, [1, 1, 2, 2, 3, 3])
        XCTAssertEqual([1, 9, 10, 25, 26, 40].map { DogLevel.shopSlots(level: $0) }, [3, 3, 4, 4, 5, 5])
        XCTAssertEqual([24, 25, 30, 31, 34, 40].map { DogLevel.stationsPct(level: $0) }, [0, 5, 5, 7, 13, 13])
        XCTAssertEqual(DogLevel.walkTimeX(level: 19), 1)
        XCTAssertEqual(DogLevel.walkTimeX(level: 20), 0.9, accuracy: 1e-9)
        XCTAssertEqual(DogLevel.sumValue("yard_decor_slots", level: 40), 4)

        // Игры: у старых сейвов, где уже играли, не закрываем.
        var f = lFile()
        XCTAssertTrue(DogLevel.gameOpen("catch", f))
        XCTAssertFalse(DogLevel.gameOpen("blockduo", f))
        XCTAssertFalse(DogLevel.gameOpen("zombie", f))
        f.zombieBest = 120
        XCTAssertTrue(DogLevel.gameOpen("zombie", f))
        f.level.xp = DogLevel.xpTo(3)
        XCTAssertTrue(DogLevel.gameOpen("blockduo", f))
    }

    func testTexts() {
        XCTAssertEqual(DogLevel.gainText(XpGain(reason: "walk", xp: 10, t: 0)), "+10 опыта за прогулку")
        XCTAssertEqual(DogLevel.gainText(XpGain(reason: "first.feed", xp: 5, t: 0)), "+5 опыта за первый раз")
        XCTAssertEqual(DogLevel.gainText(XpGain(reason: "good_day", xp: 1, t: 0)), "+1 опыт за хороший день")
        XCTAssertEqual(DogLevel.reasonText("что-то новое"), "за заботу")
    }

    // MARK: модель: ур. 10 — за неделю обычного ухода

    /// Один день ухода: дела в журнал с 9 до 21, игры, вечером сердечки. Возвращает день, когда взят ур. 10.
    private func play(days: Int, feeds: Int, pets: Int, plays: Int, bath: Bool, walks: Int, games: Int) -> (Int?, [Int]) {
        var f = lFile(at: noon(0) - 4 * 3600)
        var reached: Int?
        var perDay: [Int] = []
        for k in 0..<days {
            let morning = noon(k) - 3 * 3600
            let before = f.level.xp
            var t = morning
            func step(_ kind: String, _ n: Int) {
                for _ in 0..<n {
                    t += 600
                    if kind == "walk" { f.log("ev.back_home.bone", t: t, key: "bone") }
                    else { f.log(kind, t: t, ok: true) }
                }
            }
            step("act.feed", feeds)
            step("act.pet", pets)
            step("act.play", plays)
            step("act.bath", bath ? 1 : 0)
            step("walk", walks)
            DogLevel.settle(&f, now: t)
            catchGames(&f, games, at: t)
            f.pet.t = t + 60
            f.pet.hearts = 5
            DogLevel.settle(&f, now: t + 60)
            perDay.append(f.level.xp - before)
            if reached == nil, DogLevel.level(f) >= 10 { reached = k + 1 }
        }
        return (reached, perDay)
    }

    func testActiveWeekReachesLevel10() {
        // Активный уход: 5 еды, 10 ласк, 4 игры, купание, 3 прогулки, 4 партии + хороший день ≈ 105 в сутки.
        let (day, perDay) = play(days: 10, feeds: 5, pets: 10, plays: 4, bath: true, walks: 3, games: 4)
        XCTAssertEqual(perDay[0], 90 + 30, "первый день: дела + бонусы «первый раз» (хороший день — в полночь)")
        XCTAssertTrue((95...110).contains(perDay[3]), "обычный активный день ≈ 100: \(perDay[3])")
        XCTAssertNotNil(day)
        XCTAssertTrue((6...8).contains(day ?? 0), "ур. 10 — примерно за неделю, взят на \(day ?? 0)-й день")
    }

    func testLazyCareIsSlower() {
        // Ленивый: 2 еды, 3 ласки, игра, прогулка, партия + хороший день ≈ 40 в сутки.
        let (day, perDay) = play(days: 25, feeds: 2, pets: 3, plays: 1, bath: false, walks: 1, games: 1)
        XCTAssertTrue((35...45).contains(perDay[5]), "ленивый день ≈ 40: \(perDay[5])")
        XCTAssertNotNil(day)
        XCTAssertTrue((15...20).contains(day ?? 0), "ленивому ур. 10 — недели через 2–3, взят на \(day ?? 0)-й день")
    }
}
