// «Лови мячик» (CatchGame.swift): раскладка от сида, темп раунда, поймал/мимо, три промаха и 30 секунд,
// монеты ∝ очкам с убыванием, баффом дома (minigame_coins_x) и дневным потолком, рекорд, настроение ядерным play, когда играть нельзя,
// поля сейва верхним уровнем (старый сейв — нули) и переход к новому щенку.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000: днём пёс не спит.
private let cT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

private func cFile(at t: Double = cT0, level: Double = 60) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = "catch-pet-1"
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = level }
    return f
}

/// Конфиг с явными цифрами — тесты не зависят от правок economy.json.
private func cCfg() -> CatchConfig {
    var c = CatchConfig()
    c.base = 5
    c.max = 30
    c.parScore = 40
    c.dailyCap = 60
    c.roundSeconds = 30
    c.maxMisses = 3
    c.diminishing = [.init(from: 1, x: 1), .init(from: 7, x: 0.5), .init(from: 13, x: 0.2)]
    return c
}

final class CatchGameTests: XCTestCase {

    // MARK: раскладка

    func testLayoutIsDeterministicAndFair() {
        let a = CatchGame.layout(seed: 42, seconds: 30)
        XCTAssertEqual(a, CatchGame.layout(seed: 42, seconds: 30), "один сид — одна раскладка")
        XCTAssertNotEqual(a, CatchGame.layout(seed: 43, seconds: 30))
        XCTAssertGreaterThan(a.count, 30)
        XCTAssertLessThan(a.count, 70)
        for (i, d) in a.enumerated() {
            XCTAssertEqual(d.index, i)
            XCTAssertTrue((0.08...0.92).contains(d.x), "мячик в поле: \(d.x)")
            XCTAssertLessThan(d.spawnT, 30)
            if i > 0 {
                let p = a[i - 1]
                XCTAssertGreaterThan(d.spawnT, p.spawnT)
                XCTAssertGreaterThan(d.landT, p.landT, "падают по очереди, не обгоняют друг друга")
                XCTAssertGreaterThanOrEqual(d.speed, p.speed, "дальше — быстрее")
                XCTAssertLessThanOrEqual(abs(d.x - p.x), 0.5 + 1e-9, "до соседнего можно добежать")
            }
        }
        let bones = a.filter { $0.kind == .bone }.count
        XCTAssertGreaterThan(bones, 0)
        XCTAssertLessThan(bones, a.count / 2)
    }

    func testPaceGrows() {
        XCTAssertGreaterThan(CatchGame.gap(at: 0, seconds: 30), CatchGame.gap(at: 29, seconds: 30))
        XCTAssertLessThan(CatchGame.speed(at: 0, seconds: 30), CatchGame.speed(at: 29, seconds: 30))
        XCTAssertEqual(CatchGame.gap(at: 99, seconds: 30), CatchGame.gap(at: 30, seconds: 30))
        XCTAssertEqual(CatchKind.ball.points, 1)
        XCTAssertEqual(CatchKind.bone.points, 2)
    }

    func testRandomIsStable() {
        var r = CatchRandom(seed: 1)
        let first = (0..<3).map { _ in r.next() }
        var again = CatchRandom(seed: 1)
        XCTAssertEqual(first, (0..<3).map { _ in again.next() })
        var u = CatchRandom(seed: 7)
        for _ in 0..<1000 { XCTAssertTrue((0..<1).contains(u.unit())) }
    }

    // MARK: раунд

    func testCatchUnderBowlAndMissAside() {
        let cfg = cCfg()
        var round = CatchRound(seed: 5, cfg: cfg)
        let d = round.drops[0]
        XCTAssertTrue(round.visible.isEmpty, "в начале поле пустое")
        round.advance(to: d.spawnT + 0.1, bowlX: d.x)
        XCTAssertEqual(round.visible.first, d)
        let ev = round.advance(to: d.landT, bowlX: d.x)
        XCTAssertEqual(ev, [.caught(d)])
        XCTAssertEqual(round.score, d.kind.points)
        XCTAssertEqual(round.caught, 1)
        XCTAssertFalse(round.visible.contains(d))

        var other = CatchRound(seed: 5, cfg: cfg)
        let far = d.x > 0.5 ? 0.11 : 0.89
        XCTAssertEqual(other.advance(to: d.landT, bowlX: far), [.missed(d)])
        XCTAssertEqual(other.missed, 1)
        XCTAssertEqual(other.score, 0)
        // Назад и на то же время — ничего.
        XCTAssertEqual(other.advance(to: d.landT, bowlX: d.x), [])
        XCTAssertEqual(other.advance(to: 0, bowlX: d.x), [])
    }

    func testEdgeOfBowlStillCatches() {
        var round = CatchRound(seed: 9, cfg: cCfg())
        let d = round.drops[0]
        let bowl = d.x + CatchGame.reach * 0.99
        XCTAssertEqual(round.advance(to: d.landT, bowlX: bowl), [.caught(d)])
    }

    func testThreeMissesEndRoundEarly() {
        var round = CatchRound(seed: 11, cfg: cCfg())
        var t = 0.0
        while !round.isOver {
            t += 1.0 / 60
            // Миска всегда на другой половине от того, что падает следующим.
            let next = round.drops.first { round.status[$0.index] == .falling && $0.landT >= t - 1.0 / 60 }
            let bowl = (next?.x ?? 0.5) > 0.5 ? 0.11 : 0.89
            round.advance(to: t, bowlX: bowl)
        }
        XCTAssertEqual(round.missed, 3)
        XCTAssertEqual(round.score, 0)
        XCTAssertLessThan(round.t, 30, "кончился раньше времени")
        XCTAssertEqual(round.t, round.drops[2].landT, accuracy: 1e-9, "на третьем промахе")
        XCTAssertEqual(round.advance(to: 30, bowlX: 0.5), [], "после конца ничего не считается")
    }

    func testRoundEndsAtThirtySeconds() {
        let (round, _) = CatchGame.autoplay(seed: 3, speed: 3, cCfg())
        XCTAssertTrue(round.isOver)
        XCTAssertLessThan(round.missed, 3, "быстрый автопилот почти всё ловит")
        XCTAssertEqual(round.t, 30, accuracy: 1e-9)
        XCTAssertEqual(round.timeLeft, 0)
        XCTAssertGreaterThan(round.score, 30)
        XCTAssertEqual(round.score, round.drops.filter { round.status[$0.index] == .caught }.map(\.kind.points).reduce(0, +))
    }

    func testAutoplayIsDeterministicAndStopsAtUntil() {
        let a = CatchGame.autoplay(seed: 17, cCfg())
        let b = CatchGame.autoplay(seed: 17, cCfg())
        XCTAssertEqual(a.round.score, b.round.score)
        XCTAssertEqual(a.round.missed, b.round.missed)
        XCTAssertEqual(a.bowlX, b.bowlX)
        let mid = CatchGame.autoplay(seed: 17, until: 12, cCfg())
        XCTAssertEqual(mid.round.t, 12, accuracy: 1e-9)
        XCTAssertFalse(mid.round.isOver)
        XCTAssertFalse(mid.round.visible.isEmpty, "в середине раунда на поле что-то падает")
        XCTAssertTrue(CatchGame.bowlRange.contains(mid.bowlX))
    }

    // MARK: награда

    func testWantFollowsScoreAndDiminishes() {
        let c = cCfg()
        XCTAssertEqual(CatchGame.want(score: 0, game: 1, c), 0)
        XCTAssertEqual(CatchGame.want(score: 1, game: 1, c), 6) // 5 + 25 · 1/40 ≈ 5,6
        XCTAssertEqual(CatchGame.want(score: 20, game: 1, c), 18) // 5 + 12,5
        XCTAssertEqual(CatchGame.want(score: 40, game: 1, c), 30)
        XCTAssertEqual(CatchGame.want(score: 400, game: 1, c), 30, "выше par_score — не больше max")
        XCTAssertEqual(CatchGame.want(score: 40, game: 6, c), 30)
        XCTAssertEqual(CatchGame.want(score: 40, game: 7, c), 15)
        XCTAssertEqual(CatchGame.want(score: 40, game: 13, c), 6)
        XCTAssertEqual(c.factor(game: 0), 1)
    }

    func testFinishPaysUnderDailyCapAndKeepsRecord() {
        let c = cCfg()
        var f = cFile()
        let coins0 = f.econ.wallet.coins

        let r1 = CatchGame.finish(score: 40, caught: 30, missed: 1, in: &f, now: cT0, c)
        XCTAssertEqual(r1.coins, 30)
        XCTAssertTrue(r1.isRecord)
        XCTAssertEqual(r1.best, 40)
        XCTAssertTrue(r1.played)
        XCTAssertFalse(r1.capped)
        XCTAssertEqual(f.econ.wallet.coins, coins0 + r1.coins + r1.careCoins)
        XCTAssertEqual(f.catchBest, 40)
        XCTAssertEqual(f.catchGames, 1)
        XCTAssertEqual(f.catchCoins, 30)
        XCTAssertEqual(f.catchDay, Economy.day(cT0))

        let r2 = CatchGame.finish(score: 25, in: &f, now: cT0 + 60, c)
        XCTAssertFalse(r2.isRecord)
        XCTAssertEqual(r2.best, 40)
        XCTAssertEqual(r2.coins, 21) // 5 + 25 · 25/40 = 20,6
        XCTAssertEqual(CatchGame.coinsLeft(f, now: cT0 + 60, c), 9)

        let r3 = CatchGame.finish(score: 40, in: &f, now: cT0 + 120, c)
        XCTAssertEqual(r3.coins, 9, "сколько осталось до потолка")
        XCTAssertTrue(r3.capped)
        let r4 = CatchGame.finish(score: 40, in: &f, now: cT0 + 180, c)
        XCTAssertEqual(r4.coins, 0)
        XCTAssertTrue(r4.capped)
        XCTAssertEqual(r4.totalCoins, r4.careCoins, "за игру ноль, монеты ухода за «Поиграть» — как обычно")
        XCTAssertEqual(f.catchCoins, 60)

        // Новые сутки — потолок заново, рекорд остаётся.
        let tomorrow = cT0 + 86400
        XCTAssertEqual(CatchGame.coinsLeft(f, now: tomorrow, c), 60)
        let r5 = CatchGame.finish(score: 10, in: &f, now: tomorrow, c)
        XCTAssertEqual(r5.coins, 11) // 5 + 6,25
        XCTAssertEqual(f.catchGames, 1)
        XCTAssertEqual(f.catchBest, 40)
    }

    // MARK: бафф дома (minigame_coins_x)

    func testHomeBuffByPlayLevel() {
        var f = cFile()
        XCTAssertEqual(CatchGame.coinsX(f.pet), 1, "пустой угол")
        f.pet.home[.play] = 1
        XCTAssertEqual(CatchGame.coinsX(f.pet), 1, "корзина игрушек — бафф только к скуке")
        f.pet.home[.play] = 2
        XCTAssertEqual(CatchGame.coinsX(f.pet), 1.1, accuracy: 1e-12)
        f.pet.home[.play] = 3
        XCTAssertEqual(CatchGame.coinsX(f.pet), 1.15, accuracy: 1e-12)
        f.pet.home[.play] = 9   // битый сейв — как у ядра: уровня нет, баффа нет
        XCTAssertEqual(CatchGame.coinsX(f.pet), 1)
    }

    func testWantWithBuffRoundsOnceAfterDiminishing() {
        let c = cCfg()
        XCTAssertEqual(CatchGame.want(score: 40, game: 1, buff: 1, c), CatchGame.want(score: 40, game: 1, c))
        XCTAssertEqual(CatchGame.want(score: 40, game: 1, buff: 1.1, c), 33)
        XCTAssertEqual(CatchGame.want(score: 40, game: 1, buff: 1.15, c), 35) // 34,5
        XCTAssertEqual(CatchGame.want(score: 20, game: 1, buff: 1.1, c), 19) // 17,5 · 1,1 = 19,25 (без баффа 18)
        XCTAssertEqual(CatchGame.want(score: 20, game: 1, buff: 1.15, c), 20) // 20,125
        XCTAssertEqual(CatchGame.want(score: 40, game: 7, buff: 1.15, c), 17) // 30 · 0,5 · 1,15 = 17,25
        XCTAssertEqual(CatchGame.want(score: 0, game: 1, buff: 1.15, c), 0, "без очков бафф не помогает")
    }

    func testFinishAppliesBuffButCapStays() {
        let c = cCfg()
        var f = cFile()
        f.pet.home[.play] = 3
        let r1 = CatchGame.finish(score: 40, in: &f, now: cT0, c)
        XCTAssertEqual(r1.coins, 35)
        XCTAssertFalse(r1.capped)
        XCTAssertEqual(CatchGame.coinsLeft(f, now: cT0, c), 25)
        let r2 = CatchGame.finish(score: 40, in: &f, now: cT0 + 60, c)
        XCTAssertEqual(r2.coins, 25, "потолок дня тот же 60 — с баффом до него просто быстрее")
        XCTAssertTrue(r2.capped)
        let r3 = CatchGame.finish(score: 40, in: &f, now: cT0 + 120, c)
        XCTAssertEqual(r3.coins, 0)
        XCTAssertEqual(f.catchCoins, c.dailyCap)

        var plain = cFile()
        plain.pet.home[.play] = 1
        XCTAssertEqual(CatchGame.finish(score: 40, in: &plain, now: cT0, c).coins, 30, "без комплекса — как раньше")
    }

    func testPlayLinePerkText() {
        let play = HomeShop.line(.play)!.levels
        XCTAssertFalse(HomeShop.perks(play[1].buff).contains { $0.contains("Лови мячик") })
        XCTAssertTrue(HomeShop.perks(play[2].buff).contains("Монет за «Лови мячик» на 10% больше"))
        XCTAssertTrue(HomeShop.perks(play[3].buff).contains("Монет за «Лови мячик» на 15% больше"))
    }

    func testFinishRaisesFunThroughCorePlay() {
        var f = cFile(level: 50)
        var ref = f
        let core = PetRunner.apply(.play, source: .app, to: &ref, now: cT0)
        XCTAssertTrue(core.ok)

        let r = CatchGame.finish(score: 12, in: &f, now: cT0, cCfg())
        XCTAssertTrue(r.played)
        XCTAssertEqual(f.pet.needs[.fun] ?? 0, ref.pet.needs[.fun] ?? 0, accuracy: 1e-9, "то же, что «Поиграть»")
        XCTAssertEqual(f.pet.needs[.energy] ?? 0, ref.pet.needs[.energy] ?? 0, accuracy: 1e-9)
        XCTAssertGreaterThan(f.pet.needs[.fun] ?? 0, 50)
        XCTAssertEqual(f.journal.last?.kind, "act.play", "в журнале обычная игра")
        XCTAssertEqual(r.careCoins, core.coins, "монеты ухода за игру — как у «Поиграть»")
    }

    func testZeroScoreGivesNothingButCountsRound() {
        var f = cFile(level: 50)
        let before = f
        let r = CatchGame.finish(score: 0, missed: 3, in: &f, now: cT0, cCfg())
        XCTAssertEqual(r.totalCoins, 0)
        XCTAssertFalse(r.played)
        XCTAssertFalse(r.isRecord)
        XCTAssertFalse(r.capped)
        XCTAssertNil(CatchGame.rewardText(r))
        XCTAssertEqual(CatchGame.resultTitle(r), "Ни одного… Ещё разок?")
        XCTAssertEqual(f.pet.needs[.fun], before.pet.needs[.fun])
        XCTAssertEqual(f.econ.wallet, before.econ.wallet)
        XCTAssertEqual(f.catchGames, 1)
        XCTAssertEqual(f.catchBest, 0)
    }

    func testTexts() {
        XCTAssertEqual(CatchGame.resultTitle(CatchResult(score: 12, best: 12, isRecord: true)), "Новый рекорд!")
        XCTAssertEqual(CatchGame.resultTitle(CatchResult(score: 5, missed: 3, best: 9)), "Ой, упустили!")
        XCTAssertEqual(CatchGame.resultTitle(CatchResult(score: 5, missed: 1, best: 9)), "Время вышло!")
        XCTAssertEqual(CatchGame.rewardText(CatchResult(score: 5, coins: 8, careCoins: 3)), "+\(EconText.coins(11))")
        XCTAssertEqual(CatchGame.rewardText(CatchResult(score: 5, capped: true)), "На сегодня монет за игру хватит")
    }

    // MARK: когда нельзя

    func testGateLikeTricksPlusTired() {
        XCTAssertNil(CatchGame.gate(cFile(), at: cT0))

        var dead = cFile()
        dead.pet.alive = false
        XCTAssertEqual(CatchGame.gate(dead, at: cT0), "dead")

        var away = cFile()
        away.pet.outing = Outing(from: cT0 - 600, until: cT0 + 3600, find: "stick")
        XCTAssertEqual(CatchGame.gate(away, at: cT0), "away")

        var bath = cFile()
        bath.pet.bathUntil = cT0 + 600
        XCTAssertEqual(CatchGame.gate(bath, at: cT0), "bathing")

        var nap = cFile()
        nap.pet.napUntil = cT0 + 1800
        XCTAssertEqual(CatchGame.gate(nap, at: cT0), "asleep")

        let night = cT0 - 9 * 3600
        XCTAssertEqual(CatchGame.gate(cFile(at: night), at: night), "asleep")

        var bad = cFile()
        bad.pet.hearts = 1
        XCTAssertEqual(CatchGame.gate(bad, at: cT0), "unwell")

        // Причины — обычные тексты отказа.
        for r in ["dead", "away", "bathing", "asleep", "unwell", "tired"] {
            XCTAssertNotEqual(RefuseText.text(r), "", r)
        }
    }

    func testFinishAfterDeathPaysNothing() {
        // Волна 13: пёс умер, пока шёл раунд, — монеты не капают (кошелёк переходит новому щенку), рекорд остаётся.
        var f = cFile()
        f.pet.alive = false
        let coins = f.econ.wallet.coins
        let r = CatchGame.finish(score: 33, in: &f, now: cT0, cCfg())
        XCTAssertEqual(r.coins, 0)
        XCTAssertEqual(r.totalCoins, 0)
        XCTAssertFalse(r.capped, "не «на сегодня хватит»: просто некому")
        XCTAssertNil(CatchGame.rewardText(r))
        XCTAssertEqual(f.econ.wallet.coins, coins)
        XCTAssertEqual(f.catchCoins, 0, "дневной потолок не съеден")
        XCTAssertFalse(r.played)
        XCTAssertEqual(f.catchBest, 33)
    }

    func testFinishWhileAsleepKeepsRecordWithoutPlay() {
        var f = cFile()
        f.pet.napUntil = cT0 + 1800
        let fun = f.pet.needs[.fun]
        let r = CatchGame.finish(score: 8, in: &f, now: cT0, cCfg())
        XCTAssertFalse(r.played)
        XCTAssertEqual(r.reason, "asleep")
        XCTAssertEqual(r.careCoins, 0)
        XCTAssertEqual(f.pet.needs[.fun], fun)
        XCTAssertEqual(f.catchBest, 8)
    }

    // MARK: сейв и конфиг

    func testSaveFieldsTopLevelAndOldSave() throws {
        var f = cFile()
        CatchGame.finish(score: 33, in: &f, now: cT0, cCfg())
        let data = try JSONEncoder().encode(f)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((obj["catchBest"] as? NSNumber)?.intValue, 33, "рекорд — верхним уровнем")
        XCTAssertNotNil(obj["catchDay"])
        let back = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(back.catchBest, 33)
        XCTAssertEqual(back.catchDay, f.catchDay)
        XCTAssertEqual(back.catchCoins, f.catchCoins)
        XCTAssertEqual(back.catchGames, 1)

        // Старый сейв без полей — нули, остальное на месте. JSONSerialization на Linux превращает bool в числа,
        // поэтому «старый» файл — настоящий сейв без игр (нули не пишутся), а битое поле дописываем текстом.
        var plain = f
        plain.catchBest = 0; plain.catchDay = 0; plain.catchCoins = 0; plain.catchGames = 0
        let oldData = try JSONEncoder().encode(plain)
        XCTAssertFalse(String(decoding: oldData, as: UTF8.self).contains("\"catchBest\""))
        let oldFile = try JSONDecoder().decode(SaveFile.self, from: oldData)
        XCTAssertEqual(oldFile.catchBest, 0)
        XCTAssertEqual(oldFile.catchGames, 0)
        XCTAssertEqual(oldFile.petId, f.petId)
        XCTAssertEqual(oldFile.econ.wallet, f.econ.wallet)

        // Битое поле — ноль, а не весь сейв.
        let text = String(decoding: oldData, as: UTF8.self)
        let broken = "{\"catchBest\":\"много\",\"catchGames\":2," + text.dropFirst()
        let b = try JSONDecoder().decode(SaveFile.self, from: Data(broken.utf8))
        XCTAssertEqual(b.catchBest, 0)
        XCTAssertEqual(b.catchGames, 2)
        XCTAssertEqual(b.petId, f.petId)

        // Новый щенок без игр — полей в файле нет.
        let fresh = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SaveFile.fresh(now: cT0))) as? [String: Any]
        XCTAssertNil(fresh?["catchBest"])
        XCTAssertNil(fresh?["catchGames"])
    }

    func testStartOverKeepsRecordAndDailyCap() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-catch")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: cT0)
        try store.mutate { (f: inout SaveFile) -> Void in
            f.catchBest = 51
            f.catchDay = Economy.day(cT0)
            f.catchCoins = 60
            f.catchGames = 4
        }
        try store.startOver(now: cT0 + 100)
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.catchBest, 51, "рекорд хозяина остаётся")
        XCTAssertEqual(f.catchCoins, 60, "новым щенком потолок не обнулить")
        XCTAssertEqual(f.catchGames, 4)
    }

    func testConfigFromEconomyJSON() {
        let d = CatchConfig(json: .null)
        XCTAssertEqual(d.roundSeconds, 30)
        XCTAssertEqual(d.maxMisses, 3)
        XCTAssertEqual(d.factor(game: 1), 1)

        let s = CatchConfig.shared
        XCTAssertEqual(s.name, "Лови мячик")
        XCTAssertEqual(s.roundSeconds, 30)
        XCTAssertEqual(s.maxMisses, 3)
        XCTAssertGreaterThan(s.dailyCap, 0)
        XCTAssertGreaterThanOrEqual(s.max, s.base)
        XCTAssertLessThanOrEqual(s.max, s.dailyCap, "один раунд не выбирает больше дневного потолка")
        XCTAssertEqual(s.factor(game: 7), 0.5)
    }
}
