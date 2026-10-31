// Волна 32: игры всегда. Одно правило «кто занят» (MiniGames.busy) на все мини-игры, плашка «просто так»
// на карточке «Играть» и раунд «просто так»: рекорд пишется, монет, «Поиграть» в ядре и убывания нет.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.
// Волна 55: «Щенок против зомби» убран — старый сейв с его полями читается (testOldZombieSaveStillLoads).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000: днём пёс не спит.
private let mT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

private func mFile(at t: Double = mT0, level: Double = 60) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = "games-pet-1"
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = level }
    return f
}

/// Пёс спит днём — самый частый «занят».
private func napping() -> SaveFile {
    var f = mFile()
    f.pet.napUntil = mT0 + 1800
    return f
}

final class MiniGamesTests: XCTestCase {

    // MARK: кто занят

    func testBusyIsTricksGatePlusTired() {
        XCTAssertNil(MiniGames.busy(mFile(), at: mT0), "свободен — раунд настоящий")

        var dead = mFile()
        dead.pet.alive = false
        XCTAssertEqual(MiniGames.busy(dead, at: mT0), "dead")

        var away = mFile()
        away.pet.outing = Outing(from: mT0 - 600, until: mT0 + 3600, find: "stick")
        XCTAssertEqual(MiniGames.busy(away, at: mT0), "away")

        var bath = mFile()
        bath.pet.bathUntil = mT0 + 600
        XCTAssertEqual(MiniGames.busy(bath, at: mT0), "bathing")

        XCTAssertEqual(MiniGames.busy(napping(), at: mT0), "asleep")
        let night = mT0 - 9 * 3600
        XCTAssertEqual(MiniGames.busy(mFile(at: night), at: night), "asleep", "ночью тоже спит")

        var bad = mFile()
        bad.pet.hearts = 1
        XCTAssertEqual(MiniGames.busy(bad, at: mT0), "unwell")

        var tired = mFile()
        tired.pet.needs[.energy] = 10
        XCTAssertEqual(MiniGames.busy(tired, at: mT0), "tired", "ядро не играет без сил")
    }

    func testBusyMatchesTricksForEveryTricksReason() {
        // Одно правило: всё, что закрывает трюки, делает игру «просто так».
        var away = mFile()
        away.pet.outing = Outing(from: mT0 - 600, until: mT0 + 3600, find: "stick")
        var bath = mFile()
        bath.pet.bathUntil = mT0 + 600
        var dead = mFile()
        dead.pet.alive = false
        for f in [mFile(), away, bath, dead, napping()] {
            let trick = Tricks.gate(f, at: mT0)
            if let trick { XCTAssertEqual(MiniGames.busy(f, at: mT0), trick) }
        }
    }

    func testNoteAddsCapOnlyWhenDogIsFree() {
        XCTAssertNil(MiniGames.note(mFile(), at: mT0, left: 10))
        XCTAssertEqual(MiniGames.note(mFile(), at: mT0, left: 0), MiniGames.capReason)
        XCTAssertEqual(MiniGames.note(napping(), at: mT0, left: 0), "asleep", "занятость важнее потолка")
        XCTAssertEqual(MiniGames.note(napping(), at: mT0, left: 10), "asleep")
    }

    // MARK: тексты

    func testNoteTexts() {
        XCTAssertEqual(MiniGames.noteText("asleep"), "Шиба спит — играем просто так, без монет")
        XCTAssertEqual(MiniGames.noteText(MiniGames.capReason), "Монеты на сегодня всё — играем просто так")
        for r in ["asleep", "bathing", "away", "tired", "unwell", "dead", MiniGames.capReason, "unavailable"] {
            let t = MiniGames.noteText(r)
            XCTAssertTrue(t.contains("просто так"), r)
            XCTAssertFalse(MiniGames.noteIcon(r).isEmpty, r)
            XCTAssertFalse(t.hasSuffix("."), "плашка без точки, как соседние: \(r)")
        }
        // Причины busy — и обычные тексты отказа, если они где-то всплывут.
        for r in ["dead", "away", "bathing", "asleep", "unwell", "tired"] {
            XCTAssertNotEqual(RefuseText.text(r), "", r)
            XCTAssertNotEqual(MiniGames.noteText(r), MiniGames.noteText("unavailable"), "у причины свой текст: \(r)")
        }
    }

    func testNoteTextsFollowPetName() {
        XCTAssertEqual(MiniGames.noteText("asleep", name: PetNames.shiba), MiniGames.noteText("asleep"))
        XCTAssertEqual(MiniGames.noteText("asleep", name: "Мурка"), "Мурка спит — играем просто так, без монет")
        XCTAssertEqual(MiniGames.noteText("tired", name: "Мурка"), "Питомец устал — играем просто так, без монет")
        for r in ["asleep", "bathing", "away", "tired", "unwell", "dead"] {
            XCTAssertFalse(MiniGames.noteText(r, name: "Мурка").contains("Шиб"), r)
        }
    }

    // MARK: раунд «просто так»

    func testCatchFreeRoundKeepsOnlyRecord() {
        var f = napping()
        let coins = f.econ.wallet.coins, fun = f.pet.needs[.fun], energy = f.pet.needs[.energy]
        let r = CatchGame.finish(score: 33, in: &f, now: mT0, free: "asleep")
        XCTAssertEqual(r.free, "asleep")
        XCTAssertEqual(r.totalCoins, 0)
        XCTAssertFalse(r.capped, "не «хватит на сегодня»: просто так")
        XCTAssertFalse(r.played)
        XCTAssertNil(r.reason)
        XCTAssertEqual(f.econ.wallet.coins, coins)
        XCTAssertEqual(f.catchCoins, 0, "дневной потолок не тронут")
        XCTAssertEqual(f.catchGames, 0, "убывание не растёт")
        XCTAssertEqual(f.pet.needs[.fun], fun)
        XCTAssertEqual(f.pet.needs[.energy], energy)
        XCTAssertEqual(f.catchBest, 33)
        XCTAssertTrue(r.isRecord)
        XCTAssertEqual(CatchGame.rewardText(r), MiniGames.freeReward)
    }

    func testBlockDuoFreeRoundKeepsOnlyRecord() {
        var f = napping()
        let coins = f.econ.wallet.coins, fun = f.pet.needs[.fun]
        let r = BlockDuo.finish(BlockDuo.autoplay(seed: 3, moves: 4), in: &f, now: mT0, free: "asleep")
        XCTAssertGreaterThan(r.score, 0)
        XCTAssertEqual(r.totalCoins, 0)
        XCTAssertFalse(r.capped)
        XCTAssertFalse(r.played)
        XCTAssertEqual(f.econ.wallet.coins, coins)
        XCTAssertEqual(f.blockduoCoins, 0)
        XCTAssertEqual(f.blockduoGames, 0)
        XCTAssertEqual(f.pet.needs[.fun], fun)
        XCTAssertEqual(f.blockduoBest, r.score)
        XCTAssertEqual(BlockDuo.rewardText(r), MiniGames.freeReward)
        XCTAssertEqual(BlockDuo.toastText(r)?.hasSuffix("играли просто так — без монет"), true)
    }

    func testSameScoreWhenFreePaysCoins() {
        // Контроль: без «просто так» тот же счёт даёт монеты и «Поиграть».
        var f = mFile()
        let coins = f.econ.wallet.coins
        let r = CatchGame.finish(score: 33, in: &f, now: mT0, free: MiniGames.busy(f, at: mT0))
        XCTAssertNil(r.free)
        XCTAssertGreaterThan(r.coins, 0)
        XCTAssertTrue(r.played)
        XCTAssertEqual(f.catchGames, 1)
        XCTAssertGreaterThan(f.econ.wallet.coins, coins)
        XCTAssertNotEqual(CatchGame.rewardText(r), MiniGames.freeReward)
    }

    func testCapExhaustedIsNotFree() {
        // Потолок кончился — плашка «просто так», но пёс свободен: раунд настоящий, настроение растёт, монет нет.
        var f = mFile()
        f.catchDay = DayKey.of(mT0)
        f.catchCoins = 10_000
        XCTAssertEqual(CatchGame.coinsLeft(f, now: mT0), 0)
        XCTAssertEqual(MiniGames.note(f, at: mT0, left: 0), MiniGames.capReason)
        let fun = f.pet.needs[.fun]!
        let r = CatchGame.finish(score: 33, in: &f, now: mT0, free: MiniGames.busy(f, at: mT0))
        XCTAssertNil(r.free)
        XCTAssertEqual(r.coins, 0)
        XCTAssertTrue(r.capped)
        XCTAssertTrue(r.played)
        XCTAssertGreaterThan(f.pet.needs[.fun]!, fun)
    }

    // MARK: старый сейв с «Щенок против зомби» (волна 55)

    /// Игру убрали, а сейвы с её полями остались: они читаются, поля не теряются при записи, в потолок монет,
    /// опыт, рекорды и челлендж зомби больше не попадает, и ничего не падает на старых ключах "zombie".
    func testOldZombieSaveStillLoads() throws {
        let day = DayKey.of(mT0)
        var old = mFile()
        old.shardLog.best = ["zombie": 400, "catch": 12]
        old.level.started = true
        old.level.day = day
        old.level.gameDay = ["zombie": day]
        old.level.gameSeen = ["zombie": 1]
        old.challenge.day = day - 1
        old.challenge.count = 2
        old.challenge.last = ChallengeWin(game: "zombie", goal: 300, score: 350, shards: 1, weekShards: 0, t: mT0 - 86400)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        // Поля игры — как их писала старая версия.
        raw["zombieBest"] = 412
        raw["zombieDay"] = day
        raw["zombieCoins"] = 45
        raw["zombieGames"] = 3
        let data = try JSONSerialization.data(withJSONObject: raw)

        var f = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(f.zombieBest, 412)
        XCTAssertEqual(f.zombieDay, day)
        XCTAssertEqual(f.zombieCoins, 45)
        XCTAssertEqual(f.zombieGames, 3)
        XCTAssertEqual(f.challenge.last?.game, "zombie", "старая запись челленджа читается как есть")
        XCTAssertEqual(f.shardLog.best["zombie"], 400)
        XCTAssertEqual(f.level.gameDay["zombie"], day)

        // Запись не теряет поля (откат на старую версию увидит свой рекорд).
        let again = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(f)) as? [String: Any])
        XCTAssertEqual(again["zombieBest"] as? Int, 412)
        XCTAssertEqual(again["zombieGames"] as? Int, 3)

        // В реестре зомби нет: монеты за сутки, рекорды, челлендж — только «Мячик», «Блок Дуо» и «Раннер» (волна 55b).
        XCTAssertNil(MiniGame(rawValue: "zombie"))
        XCTAssertEqual(MiniGame.allCases, [.ball, .blockduo, .runner])
        XCTAssertEqual(MiniGames.coinsToday(f, now: mT0), 0, "45 монет зомби не съедают общий потолок")
        XCTAssertEqual(Set(Shards.records(f).keys), ["catch", "blockduo", "runner"])
        XCTAssertEqual(Shards.recordGames, ["catch", "blockduo", "runner"])
        XCTAssertNil(DogLevel.games(f)["zombie"])
        for d in day..<(day + 4) { XCTAssertNotEqual(Challenges.game(day: d).rawValue, "zombie") }

        // Опыт и клочки: старые партии зомби ничего не дают, сейв проходит settle без ошибок.
        let out = DogLevel.settle(&f, now: mT0)
        XCTAssertFalse(out.gains.contains { $0.reason.contains("zombie") }, "\(out.gains)")
        XCTAssertNil(DogLevelConfig.shared.rule("game.zombie"))
        let shards = Shards.settle(&f, now: mT0)
        XCTAssertFalse(shards.contains { $0.reason.contains("zombie") }, "\(shards)")
        XCTAssertEqual(f.zombieBest, 412, "settle старые поля не трогает")
        // Монеты мини-игр по-прежнему считаются по живым играм.
        f.catchDay = day
        f.catchCoins = 10
        XCTAssertEqual(MiniGames.coinsToday(f, now: mT0), 10)
        XCTAssertEqual(MiniGames.menuHint(), "\(CatchConfig.shared.name), \(BlockDuoConfig.shared.name) или \(RunnerConfig.shared.name) вместе с Шибой")
    }
}
