// Волна 32: игры всегда. Одно правило «кто занят» (MiniGames.busy) на все три игры, плашка «просто так»
// на карточке «Играть» и раунд «просто так»: рекорд пишется, монет, «Поиграть» в ядре и убывания нет.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

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

    func testZombieFreeRoundKeepsOnlyRecord() {
        var f = napping()
        let coins = f.econ.wallet.coins, fun = f.pet.needs[.fun]
        let r = ZombieRun.finish(ZombieRun.autoplay(seed: 3, until: 10), in: &f, now: mT0, free: "asleep")
        XCTAssertGreaterThan(r.score, 0)
        XCTAssertEqual(r.totalCoins, 0)
        XCTAssertFalse(r.capped)
        XCTAssertFalse(r.played)
        XCTAssertEqual(f.econ.wallet.coins, coins)
        XCTAssertEqual(f.zombieCoins, 0)
        XCTAssertEqual(f.zombieGames, 0)
        XCTAssertEqual(f.pet.needs[.fun], fun)
        XCTAssertEqual(f.zombieBest, r.score)
        XCTAssertEqual(ZombieRun.rewardText(r), MiniGames.freeReward)
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
}
