// Волна 35 K: челлендж дня в мини-играх (Challenges.swift). Ротация по дням, цель от рекорда по-человечески,
// замок до ур. 11, «просто так» не в счёт, раз в день (переигрывать можно без награды), опыт через журнал,
// бонус недели за 3 дня, старые сейвы читаются. Гоняется и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000.
private let cT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

/// Полдень суток day.
private func noonOf(_ day: Int) -> Double { DayKey.start(day) + 12 * 3600 }

/// Ближайшие сутки от cT0 (вперёд), где челлендж в игре g.
private func dayOf(_ g: ChallengeGame, after k: Int = 0) -> Int {
    var d = DayKey.of(cT0) + k
    while Challenges.game(day: d) != g { d += 1 }
    return d
}

/// Пёс уровня lvl, учёт уровня заведён (settle уже был).
private func cFile(level lvl: Int = 11, at t: Double = cT0) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = "challenge-pet-1"
    DogLevel.settle(&f, now: t)
    f.level.xp = DogLevel.xpTo(lvl)
    f.level.paidLevel = lvl
    // Волна 39 C: достижения (ур. 5/10, первый челлендж) уже получены — здесь считаем только ✂️ челленджа.
    f.shardLog.once += Achievements.all.map { Achievements.key($0.id) }
    return f
}

/// Партия «Блок Дуо» с заданным счётом через Challenges.play (как на экране).
@discardableResult
private func playBlocks(_ f: inout SaveFile, score: Int, at t: Double, free: String? = nil) -> ChallengeWin? {
    let before = f.challenge.count
    // Счёт партии закрыт (private(set)) — подменяем его в итоге: челленджу важен только итог.
    Challenges.play(.blockduo, in: &f, now: t) { f, now in
        var r = BlockDuo.finish(BlockDuoGame(seed: 1), in: &f, now: now, free: free)
        r.score = score
        return r
    }
    return f.challenge.count > before ? f.challenge.last : nil
}

final class ChallengesTests: XCTestCase {

    // MARK: ротация и цель

    func testRotationGoesBallBlocksRunner() {
        // Волна 55: зомби убран — круг из игр реестра MiniGame; волна 55b: Мячик → Блок Дуо → Раннер.
        let d = dayOf(.ball)
        XCTAssertEqual(Challenges.game(day: d), .ball)
        XCTAssertEqual(Challenges.game(day: d + 1), .blockduo)
        XCTAssertEqual(Challenges.game(day: d + 2), .runner)
        XCTAssertEqual(Challenges.game(day: d + 3), .ball)
        // Отрицательные сутки тоже по кругу, без вылета.
        XCTAssertEqual(Challenges.game(day: -1), Challenges.game(day: 2))
        XCTAssertEqual(Challenges.game(day: 0), .ball)
        // Каждая игра реестра бывает в челлендже, другой нет.
        let seen = Set((0..<10).map { Challenges.game(day: d + $0) })
        XCTAssertEqual(seen, Set(MiniGame.allCases))
        XCTAssertNil(ChallengeGame(rawValue: "zombie"), "зомби больше не игра челленджа")
    }

    func testRunnerChallengeCountsRealRunOnly() {
        let t = noonOf(dayOf(.runner))
        var f = cFile(at: t)
        XCTAssertEqual(Challenges.goal(.runner, in: f), 400)
        // Просто так (пёс занят) — не в счёт.
        Challenges.play(.runner, in: &f, now: t) { g, now in Runner.finish(score: 900, in: &g, now: now, free: "asleep") }
        XCTAssertFalse(Challenges.doneToday(f, at: t))
        // Рекорд «просто так» засчитан — цель выросла до 70 % от него.
        let goal = Challenges.goal(.runner, in: f)
        XCTAssertGreaterThan(goal, 400)
        Challenges.play(.runner, in: &f, now: t + 30) { g, now in Runner.finish(score: goal - 10, in: &g, now: now) }
        XCTAssertFalse(Challenges.doneToday(f, at: t + 30), "ниже цели")
        Challenges.play(.runner, in: &f, now: t + 60) { g, now in Runner.finish(score: goal, in: &g, now: now) }
        XCTAssertTrue(Challenges.doneToday(f, at: t + 60))
        XCTAssertEqual(f.challenge.last?.game, "runner")
    }

    func testNiceRounding() {
        XCTAssertEqual(Challenges.nice(7.3), 7)
        XCTAssertEqual(Challenges.nice(19.4), 19)
        XCTAssertEqual(Challenges.nice(21), 20)
        XCTAssertEqual(Challenges.nice(33), 35)
        XCTAssertEqual(Challenges.nice(256), 260)
        XCTAssertEqual(Challenges.nice(1234), 1200)
        XCTAssertEqual(Challenges.nice(2870), 2900)
        XCTAssertEqual(Challenges.nice(-5), 0)
    }

    func testGoalIsBaseOrSeventyPercentOfRecord() {
        let cfg = ChallengeConfig()
        XCTAssertEqual(Challenges.goal(.ball, record: 0, cfg), 25)
        XCTAssertEqual(Challenges.goal(.blockduo, record: 1800, cfg), 2000, "70 % рекорда меньше базы — база")
        XCTAssertEqual(Challenges.goal(.blockduo, record: 4100, cfg), 2900, "70 % от 4100 = 2870 → 2 900")
        XCTAssertEqual(Challenges.goal(.ball, record: 50, cfg), 35)
    }

    func testConfigFromJSON() throws {
        let raw = #"{"challenges": {"base": {"catch": 30, "zombie": 150}, "ratio": 0.5, "shards": 2, "week_need": 2, "week_shards": 5}}"#
        let cfg = ChallengeConfig(json: try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)))
        XCTAssertEqual(cfg.base(.ball), 30)
        XCTAssertEqual(cfg.base(.blockduo), 2000, "нет в конфиге — умолчание")
        XCTAssertEqual(Set(cfg.bases.keys), Set(MiniGame.allCases), "старый ключ zombie в конфиге не мешает")
        XCTAssertEqual(cfg.ratio, 0.5)
        XCTAssertEqual(cfg.shards, 2)
        XCTAssertEqual(cfg.weekNeed, 2)
        XCTAssertEqual(cfg.weekShards, 5)
        let none = ChallengeConfig(json: .null)
        XCTAssertEqual(none.base(.blockduo), 2000)
        XCTAssertEqual(none.ratio, 0.7)
    }

    func testUnlockLevelIsEleven() {
        XCTAssertEqual(DogLevel.needLevel(Challenges.unlockId), 11)
        XCTAssertEqual(DogLevelConfig.shared.rule(Challenges.journalKind)?.xp, 10)
    }

    // MARK: плашка

    func testStatusClosedBeforeLevelEleven() {
        let t = noonOf(dayOf(.blockduo))
        XCTAssertNil(Challenges.status(cFile(level: 10, at: t), game: .blockduo, at: t))
        XCTAssertEqual(Challenges.status(cFile(level: 11, at: t), game: .blockduo, at: t), .today(goal: 2000))
        XCTAssertEqual(Challenges.status(cFile(level: 11, at: t), game: .ball, at: t), .elsewhere(.blockduo))
    }

    func testBadgeTexts() {
        XCTAssertEqual(Challenges.badgeText(.today(goal: 2000)), "Челлендж: 2\u{00A0}000 · сегодня")
        XCTAssertEqual(Challenges.badgeText(.today(goal: 25)), "Челлендж: 25 · сегодня")
        XCTAssertEqual(Challenges.badgeText(.elsewhere(.ball)), "Челлендж дня — в «Мячик»")
        XCTAssertEqual(Challenges.badgeText(.done), "✓ Челлендж выполнен")
        XCTAssertEqual(Challenges.number(12_345), "12\u{00A0}345")
        XCTAssertEqual(Challenges.number(999), "999")
        XCTAssertTrue(Challenges.badgeA11y(.today(goal: 2000)).contains("очков"))
        let w = ChallengeWin(game: "catch", goal: 25, score: 30, shards: 1, weekShards: 0, t: 0)
        XCTAssertEqual(Challenges.rewardText(w), "+1 ✂️ · +10 опыта")
        var wk = w
        wk.weekShards = 3
        XCTAssertEqual(Challenges.rewardText(wk), "+1 ✂️ · +10 опыта · +3 ✂️ за неделю")
    }

    // MARK: засчитывание

    func testWinPaysShardOnceAndMarksDay() {
        let t = noonOf(dayOf(.blockduo))
        var f = cFile(at: t)
        let shards0 = f.econ.wallet.shards
        let earned0 = f.shardLog.earned
        let w = playBlocks(&f, score: 2100, at: t)
        XCTAssertNotNil(w)
        XCTAssertEqual(w?.goal, 2000)
        XCTAssertEqual(f.econ.wallet.shards, shards0 + 1)
        XCTAssertEqual(f.shardLog.earned, earned0 + 1)
        XCTAssertTrue(Challenges.doneToday(f, at: t))
        XCTAssertEqual(Challenges.status(f, game: .blockduo, at: t), .done)
        XCTAssertEqual(Challenges.status(f, game: .ball, at: t), .done, "выполнен — на всех экранах")
        // Переиграть можно, но второй раз без награды.
        XCTAssertNil(playBlocks(&f, score: 5000, at: t + 600))
        XCTAssertEqual(f.econ.wallet.shards, shards0 + 1)
        XCTAssertEqual(f.challenge.count, 1)
        // Послезавтра — мячик (Блок Дуо → Раннер → Мячик), плашка снова с целью.
        let next = t + 2 * 86400
        XCTAssertFalse(Challenges.doneToday(f, at: next))
        XCTAssertEqual(Challenges.status(f, game: .ball, at: next), .today(goal: 25))
    }

    func testBelowGoalOrWrongGameOrClosedDoesNotCount() {
        let t = noonOf(dayOf(.blockduo))
        var f = cFile(at: t)
        XCTAssertNil(playBlocks(&f, score: 1990, at: t), "ниже цели")
        var g = cFile(at: t)
        Challenges.play(.ball, in: &g, now: t) { CatchGame.finish(score: 99, in: &$0, now: $1) }
        XCTAssertEqual(g.challenge.count, 0, "сегодня не мячик")
        var low = cFile(level: 10, at: t)
        XCTAssertNil(playBlocks(&low, score: 9000, at: t), "до ур. 11 закрыто")
        XCTAssertTrue(low.challenge.isEmpty)
    }

    func testFreeRoundDoesNotCount() {
        let t = noonOf(dayOf(.blockduo))
        var f = cFile(at: t)
        XCTAssertNil(playBlocks(&f, score: 3000, at: t, free: "walk"), "пёс занят — партия «просто так»")
        XCTAssertFalse(Challenges.doneToday(f, at: t))
        XCTAssertNotNil(playBlocks(&f, score: 3000, at: t + 60), "потом настоящая — засчитана")
    }

    func testGoalCountsFromRecordBeforeRound() {
        // Рекорд 4000 → цель 2 800. Партия на 3000 — рекорд не побит, но цель выполнена.
        let t = noonOf(dayOf(.blockduo))
        var f = cFile(at: t)
        f.blockduoBest = 4000
        XCTAssertEqual(Challenges.goal(.blockduo, in: f), 2800)
        XCTAssertNotNil(playBlocks(&f, score: 3000, at: t))
        // Новый рекорд сам по себе цель не задирает посреди раунда: 9000 при старом рекорде — тоже засчитан бы.
        var g = cFile(at: t)
        g.blockduoBest = 2000
        XCTAssertEqual(playBlocks(&g, score: 9000, at: t)?.goal, 2000)
    }

    func testOtherGamesWork() {
        let tb = noonOf(dayOf(.ball))
        var f = cFile(at: tb)
        Challenges.play(.ball, in: &f, now: tb) { CatchGame.finish(score: 25, in: &$0, now: $1) }
        XCTAssertEqual(f.challenge.last?.game, "catch")
    }

    func testDeadDogGetsNothing() {
        let t = noonOf(dayOf(.blockduo))
        var f = cFile(at: t)
        f.pet.alive = false
        XCTAssertNil(Challenges.settle(.blockduo, score: 5000, free: nil, goal: 2000, in: &f, now: t))
    }

    // MARK: опыт и неделя

    func testXpComesThroughJournal() {
        let t = noonOf(dayOf(.blockduo))
        var f = cFile(at: t)
        DogLevel.settle(&f, now: t)
        let xp0 = f.level.xp
        let w = Challenges.settle(.blockduo, score: 2500, free: nil, goal: 2000, in: &f, now: t)
        XCTAssertNotNil(w)
        let out = DogLevel.settle(&f, now: t + 1)
        let fromChallenge = out.gains.filter { $0.reason == "challenge" }.map(\.xp).reduce(0, +)
        XCTAssertEqual(fromChallenge, 10, "правило game.challenge — 10 опыта")
        XCTAssertGreaterThanOrEqual(f.level.xp - xp0, 10)
        XCTAssertEqual(DogLevel.reasonText("challenge"), "за челлендж")
    }

    func testWeekBonusAfterThreeDaysAndResetNextWeek() {
        // Понедельник недели, где-то после cT0.
        var mon = DayKey.of(cT0)
        while Shards.week(mon) == Shards.week(mon - 1) { mon += 1 }
        var f = cFile(at: noonOf(mon))
        let s0 = f.econ.wallet.shards
        for k in 0..<3 {
            let day = mon + k
            let t = noonOf(day)
            let g = Challenges.game(day: day)
            let w = Challenges.settle(g, score: 99_999, free: nil, goal: Challenges.goal(g, in: f), in: &f, now: t)
            XCTAssertNotNil(w, "день \(k)")
            XCTAssertEqual(w?.weekShards, k == 2 ? 3 : 0, "бонус недели — на третий день")
        }
        XCTAssertEqual(f.econ.wallet.shards, s0 + 3 + 3)
        XCTAssertTrue(f.challenge.weekPaid)
        // Четвёртый день той же недели — только дневной клочок.
        let d4 = mon + 3
        let w4 = Challenges.settle(Challenges.game(day: d4), score: 99_999, free: nil, goal: 1, in: &f, now: noonOf(d4))
        XCTAssertEqual(w4?.weekShards, 0)
        XCTAssertEqual(f.challenge.weekDays, 4)
        // Следующая неделя — счёт с нуля.
        let d8 = mon + 7
        let w8 = Challenges.settle(Challenges.game(day: d8), score: 99_999, free: nil, goal: 1, in: &f, now: noonOf(d8))
        XCTAssertNotNil(w8)
        XCTAssertEqual(f.challenge.weekDays, 1)
        XCTAssertFalse(f.challenge.weekPaid)
    }

    func testWeekGapsStillCountDistinctDays() {
        // Пн, Ср, Пт — три разных дня с перерывами: бонус есть.
        var mon = DayKey.of(cT0)
        while Shards.week(mon) == Shards.week(mon - 1) { mon += 1 }
        var f = cFile(at: noonOf(mon))
        var bonus = 0
        for day in [mon, mon + 2, mon + 4] {
            let g = Challenges.game(day: day)
            bonus += Challenges.settle(g, score: 99_999, free: nil, goal: 1, in: &f, now: noonOf(day))?.weekShards ?? 0
        }
        XCTAssertEqual(bonus, 3)
    }

    // MARK: сейв

    func testSaveRoundTripAndOldSave() throws {
        let fresh = SaveFile.fresh(now: cT0)
        let data = try JSONEncoder().encode(fresh)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(obj?["challenge"], "пустое поле не пишется")
        XCTAssertTrue(try JSONDecoder().decode(SaveFile.self, from: data).challenge.isEmpty, "старый сейв — пустой учёт")

        let t = noonOf(dayOf(.blockduo))
        var f = cFile(at: t)
        playBlocks(&f, score: 2500, at: t)
        let back = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back.challenge, f.challenge)
        XCTAssertTrue(Challenges.doneToday(back, at: t))

        // Битое поле не роняет сейв.
        var raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(f)) as! [String: Any]
        raw["challenge"] = ["day": "вчера", "count": 3]
        let broken = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertEqual(broken.challenge.day, 0)
        XCTAssertEqual(broken.challenge.count, 3)
    }

    /// UI-снимок ui-35-challenge-done: автопилот «Блок Дуо» (сид экрана 7) набирает больше базовой цели.
    func testUiAutopilotBeatsBase() {
        let g = BlockDuo.autoplay(seed: 7)
        XCTAssertGreaterThanOrEqual(g.score, ChallengeConfig().base(.blockduo), "автопилот сид 7: \(g.score)")
    }
}
