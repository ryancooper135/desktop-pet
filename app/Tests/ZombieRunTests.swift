// «Щенок против зомби» (ZombieRun.swift, RetroRaster.swift, ZombieArt.swift): расписание от сида, попадания,
// большой с трёх раз, обнимашки и сердечки, «Гав!», автопилот; монеты с убыванием, своим и общим потолком
// мини-игр (вместе с «Лови мячик» и «Блок Дуо»), рекорд, настроение ядерным play, поля сейва верхним уровнем,
// переход к новому щенку; программный растеризатор (грани, глубина, туман, дизеринг) и сцена игры.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.
// PET_ZOMBIE_DUMP=<папка> — сложить кадры сцены в PPM (посмотреть стиль без телефона).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000: днём пёс не спит.
private let zT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

private func zFile(at t: Double = zT0, level: Double = 60) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = "zombie-pet-1"
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = level }
    return f
}

/// Конфиг с явными цифрами — тесты не зависят от правок economy.json.
private func zCfg(cap: Int = 60, shared: Int = 60, seconds: Double = 50) -> ZombieConfig {
    var c = ZombieConfig()
    c.roundSeconds = seconds
    c.hearts = 3
    c.base = 5
    c.max = 40
    c.parScore = 500
    c.dailyCap = cap
    c.sharedCap = shared
    c.diminishing = [.init(from: 1, x: 1), .init(from: 7, x: 0.5), .init(from: 13, x: 0.2)]
    return c
}

/// Раунд, в котором Шиба стоит у стены, а все зомби идут по одной линии — для точных проверок.
private func still(_ r: inout ZombieRound, to t: Double, at x: Double) -> [ZombieEvent] {
    var all: [ZombieEvent] = []
    while r.t < t - 1e-9, !r.isOver { all += r.advance(to: r.t + ZombieRound.dt, target: x) }
    return all
}

final class ZombieRunTests: XCTestCase {

    // MARK: расписание

    func testLayoutIsDeterministicAndPaced() {
        let a = ZombieRound.layout(seed: 42, seconds: 50)
        XCTAssertEqual(a, ZombieRound.layout(seed: 42, seconds: 50), "один сид — одно расписание")
        XCTAssertNotEqual(a, ZombieRound.layout(seed: 43, seconds: 50))
        XCTAssertGreaterThan(a.count, 30)
        XCTAssertLessThan(a.count, 80)
        XCTAssertEqual(a.first?.t ?? 0, 1, accuracy: 1e-9)
        XCTAssertLessThan(a.last?.t ?? 99, 47.5, "последний выходит заранее — успевает дойти")
        for (p, n) in zip(a, a.dropFirst()) {
            XCTAssertGreaterThan(n.t, p.t)
            XCTAssertGreaterThanOrEqual(abs(n.x - p.x), 0.2, "не прямо за прошлым")
        }
        for s in a {
            XCTAssertLessThanOrEqual(abs(s.x), ZombieRound.lane + 1e-9)
            if s.t < 10 { XCTAssertNotEqual(s.kind, .big, "большие — с 10-й секунды") }
        }
        // Под конец гуще, чем в начале.
        let early = a.filter { $0.t < 15 }.count
        let late = a.filter { $0.t >= 32 && $0.t < 47 }.count
        XCTAssertGreaterThan(late, early)
        XCTAssertEqual(ZombieRound.gap(at: 0, seconds: 50), 1.45, accuracy: 1e-9)
        XCTAssertEqual(ZombieRound.gap(at: 50, seconds: 50), 0.6, accuracy: 1e-9)
        // Все три вида встречаются на длинной выборке.
        let kinds = Set((1...20).flatMap { ZombieRound.layout(seed: UInt64($0), seconds: 50).map(\.kind) })
        XCTAssertEqual(kinds, Set(ZombieKind.allCases))
    }

    // MARK: попадания, обнимашки, лай

    func testToyMakesFriendAndBigNeedsThree() {
        XCTAssertEqual(ZombieKind.walker.hp, 1)
        XCTAssertEqual(ZombieKind.big.hp, 3)
        XCTAssertGreaterThan(ZombieKind.small.speed, ZombieKind.walker.speed)
        XCTAssertLessThan(ZombieKind.big.speed, ZombieKind.walker.speed)
        // Шиба стоит под первым зомби — тот становится другом до обнимашек.
        var r = ZombieRound(seed: 5, cfg: zCfg())
        let first = r.schedule[0]
        let ev = still(&r, to: first.t + 9, at: first.x)
        XCTAssertTrue(ev.contains { if case .friend(let id, _, let p, _, _) = $0 { return id == 0 && p > 0 } else { return false } })
        XCTAssertTrue(ev.contains(.thrown(.ball)))
        XCTAssertTrue(ev.contains(.thrown(.bone)))
        XCTAssertGreaterThanOrEqual(r.friends, 1)
        XCTAssertEqual(r.score, r.friends == 1 ? first.kind.points : r.score)
        XCTAssertGreaterThan(r.meter, 0, "друг копит «Гав!»")
        XCTAssertGreaterThan(r.thrown, 10, "кидает сам")
    }

    func testHugCostsHeartAndRoundEndsOnLastHeart() {
        // Шиба у левой стены, игрушки летят мимо правой половины: кто идёт справа — дойдёт.
        var cfg = zCfg()
        cfg.hearts = 2
        var r = ZombieRound(seed: 9, cfg: cfg)
        var hugs: [Int] = []
        while !r.isOver {
            // Уходим от ближнего: не попадать.
            let near = r.zombies.filter(\.isActive).min { $0.z < $1.z }
            let away = (near?.x ?? 0) > 0 ? -ZombieRound.lane : ZombieRound.lane
            for e in r.advance(to: r.t + ZombieRound.dt, target: away) {
                if case .hug(_, let left) = e { hugs.append(left) }
            }
        }
        XCTAssertEqual(hugs, [1, 0], "по сердечку за обнимашки")
        XCTAssertEqual(r.hearts, 0)
        XCTAssertEqual(r.hugs, 2)
        XCTAssertFalse(r.survived)
        XCTAssertLessThan(r.t, 50, "кончилось раньше времени")
        XCTAssertTrue(r.advance(to: r.t + 5, target: 0).isEmpty, "после конца ничего не идёт")
    }

    func testBarkBefriendsNearAndScaresFar() {
        var r = ZombieRound(seed: 11, cfg: zCfg())
        XCTAssertNil(r.bark(), "пустая шкала — не лает")
        // Копим четыре друга автопилотом без лая.
        while r.meter < ZombieRound.barkNeed, !r.isOver {
            let p = ZombieRun.Pilot()
            _ = r.advance(to: r.t + ZombieRound.dt, target: p.target(r))
        }
        XCTAssertTrue(r.canBark)
        // Ждём, пока кто-то подойдёт поближе, а кто-то будет ещё далеко.
        var guardN = 0
        while !(r.zombies.contains { $0.isActive && $0.z <= ZombieRound.barkFriendZ }
                && r.zombies.contains { $0.isActive && $0.z > ZombieRound.barkFriendZ && $0.z <= ZombieRound.barkScareZ }),
              !r.isOver, guardN < 3000 {
            _ = r.advance(to: r.t + ZombieRound.dt, target: ZombieRound.lane * 2)
            guardN += 1
        }
        let friendsBefore = r.friends
        let near = r.zombies.filter { $0.isActive && $0.z <= ZombieRound.barkFriendZ }.count
        let far = r.zombies.filter { $0.isActive && $0.z > ZombieRound.barkFriendZ && $0.z <= ZombieRound.barkScareZ }
        guard case .bark(let made, let scared)? = r.bark() else { return XCTFail("должен залаять") }
        XCTAssertEqual(made, near)
        XCTAssertEqual(scared, far.count)
        XCTAssertGreaterThan(made, 0)
        XCTAssertGreaterThan(scared, 0)
        XCTAssertEqual(r.friends, friendsBefore + made)
        XCTAssertEqual(r.meter, 0, "лай шкалу не кормит")
        XCTAssertEqual(r.barks, 1)
        XCTAssertFalse(r.canBark)
        for f in far {
            let now = r.zombies.first { $0.id == f.id }
            XCTAssertEqual(now?.z ?? 0, Swift.min(ZombieRound.spawnZ, f.z + ZombieRound.barkPush), accuracy: 1e-9, "попятился")
            if case .stunned? = now?.state {} else { XCTFail("ошарашен") }
        }
        // Ошарашенный постоит и снова пойдёт.
        _ = r.advance(to: r.t + ZombieRound.stunSeconds + 0.1, target: ZombieRound.lane * 2)
        XCTAssertFalse(r.zombies.contains { if case .stunned = $0.state { return true } else { return false } })
    }

    func testPuppyMovesAtLimitedSpeedInsideLane() {
        var r = ZombieRound(seed: 1, cfg: zCfg())
        _ = r.advance(to: 0.1, target: 99)
        XCTAssertEqual(r.puppyX, Swift.min(ZombieRound.lane, ZombieRound.puppySpeed * 0.1), accuracy: 1e-6)
        _ = r.advance(to: 1, target: 99)
        XCTAssertEqual(r.puppyX, ZombieRound.lane, accuracy: 1e-9, "не за стену")
        _ = r.advance(to: 2, target: -99)
        XCTAssertEqual(r.puppyX, -ZombieRound.lane, accuracy: 1e-9)
    }

    func testRoundLastsConfiguredTimeAndAdvanceIsStepInvariant() {
        var a = ZombieRound(seed: 21, cfg: zCfg(seconds: 20))
        var b = ZombieRound(seed: 21, cfg: zCfg(seconds: 20))
        var evA: [ZombieEvent] = [], evB: [ZombieEvent] = []
        while !a.isOver { evA += a.advance(to: a.t + 0.05, target: 0.4) }
        while !b.isOver { evB += b.advance(to: b.t + 0.5, target: 0.4) }
        XCTAssertEqual(evA, evB, "кадры по-разному — игра та же")
        XCTAssertEqual(a.score, b.score)
        XCTAssertEqual(evA.last, .over)
        XCTAssertEqual(a.hearts, b.hearts)
        XCTAssertLessThanOrEqual(a.t, 20 + 1e-9)
    }

    // MARK: автопилот и баланс

    func testAutoplayIsDeterministicAndSkillMatters() {
        let a = ZombieRun.autoplay(seed: 7, zCfg())
        let b = ZombieRun.autoplay(seed: 7, zCfg())
        XCTAssertEqual(a.score, b.score)
        XCTAssertEqual(a.friends, b.friends)
        XCTAssertTrue(a.isOver)
        var good = 0, poor = 0, survived = 0, barks = 0
        var scores: [Int] = []
        for s in 1...12 {
            let g = ZombieRun.autoplay(seed: UInt64(s), zCfg())
            let p = ZombieRun.autoplay(seed: UInt64(s), pilot: ZombieRun.Pilot(sight: 0), zCfg())
            good += g.score
            poor += p.score
            survived += g.survived ? 1 : 0
            barks += g.barks
            scores.append(g.score)
        }
        print("ZOMBIE-BALANCE good=\(good / 12) poor=\(poor / 12) survived=\(survived)/12 barks=\(barks) scores=\(scores)")
        XCTAssertGreaterThan(good, poor, "кто водит Шибу, играет лучше стоящего")
        XCTAssertGreaterThan(barks, 0, "лай в ходу")
        XCTAssertGreaterThan(survived, 0, "до конца продержаться можно")
        // Средний хороший раунд — около par: монеты за хорошую игру близки к max, не выше.
        let par = ZombieConfig.shared.parScore
        XCTAssertGreaterThan(good / 12, par / 2)
        XCTAssertLessThan(good / 12, par * 2)
        // Мид-раунд для UI-снимка: в кадре есть зомби и игрушки.
        let mid = ZombieRun.autoplay(seed: 7, until: 21)
        XCTAssertFalse(mid.isOver)
        XCTAssertFalse(mid.zombies.isEmpty)
        XCTAssertFalse(mid.toys.isEmpty)
    }

    // MARK: награда

    func testFinishPaysRecordAndPlay() {
        var f = zFile()
        let fun = f.pet.needs[.fun] ?? 0
        let g = ZombieRun.autoplay(seed: 3, zCfg())
        let c = zCfg(cap: 500, shared: 500)
        let r = ZombieRun.finish(g, in: &f, now: zT0, c)
        XCTAssertGreaterThan(g.score, 0)
        XCTAssertEqual(r.score, g.score)
        XCTAssertEqual(r.friends, g.friends)
        XCTAssertEqual(r.coins, CatchGame.want(score: g.score, game: 1, c.asCatch))
        XCTAssertTrue(r.isRecord)
        XCTAssertEqual(f.zombieBest, g.score)
        XCTAssertEqual(f.zombieGames, 1)
        XCTAssertEqual(f.zombieCoins, r.coins)
        XCTAssertTrue(r.played)
        XCTAssertGreaterThan(f.pet.needs[.fun] ?? 0, fun, "настроение — ядерным play")
        let worse = ZombieRun.autoplay(seed: 3, until: 8, zCfg())
        let r2 = ZombieRun.finish(worse, in: &f, now: zT0 + 60, c)
        XCTAssertFalse(r2.isRecord)
        XCTAssertEqual(r2.best, g.score)
        XCTAssertEqual(f.zombieGames, 2)
    }

    func testOwnDailyCapAndNextDay() {
        var f = zFile()
        let g = ZombieRun.autoplay(seed: 3, zCfg())
        var total = 0
        for i in 0..<6 { total += ZombieRun.finish(g, in: &f, now: zT0 + Double(i) * 60, zCfg(cap: 50, shared: 500)).coins }
        XCTAssertEqual(total, 50, "не больше своего потолка")
        XCTAssertEqual(ZombieRun.coinsLeft(f, now: zT0 + 600, zCfg(cap: 50, shared: 500)), 0)
        let r = ZombieRun.finish(g, in: &f, now: zT0 + 900, zCfg(cap: 50, shared: 500))
        XCTAssertEqual(r.coins, 0)
        XCTAssertTrue(r.capped)
        XCTAssertEqual(ZombieRun.rewardText(r), r.careCoins > 0 ? "+\(EconText.coins(r.careCoins))" : "На сегодня монет за игры хватит")
        XCTAssertEqual(ZombieRun.coinsLeft(f, now: zT0 + 86400, zCfg(cap: 50, shared: 500)), 50, "завтра снова")
    }

    func testSharedCapWithOtherGames() {
        var f = zFile()
        f.catchDay = DayKey.of(zT0)
        f.catchCoins = 30
        f.blockduoDay = DayKey.of(zT0)
        f.blockduoCoins = 20
        XCTAssertEqual(ZombieRun.coinsLeft(f, now: zT0, zCfg()), 10, "мячик и блоки уже взяли 50 из общих 60")
        let r = ZombieRun.finish(ZombieRun.autoplay(seed: 3, zCfg()), in: &f, now: zT0, zCfg())
        XCTAssertEqual(r.coins, 10)
        XCTAssertTrue(r.capped)
        XCTAssertEqual(MiniGames.coinsToday(f, now: zT0), 60)
        // И наоборот: другие игры видят монеты зомби.
        var cc = CatchConfig()
        cc.dailyCap = 60
        cc.sharedCap = 60
        XCTAssertEqual(CatchGame.coinsLeft(f, now: zT0, cc), 0)
        var only = zFile()
        only.zombieDay = DayKey.of(zT0)
        only.zombieCoins = 45
        XCTAssertEqual(CatchGame.coinsLeft(only, now: zT0, cc), 15)
        var bc = BlockDuoConfig()
        bc.dailyCap = 60
        bc.sharedCap = 60
        XCTAssertEqual(BlockDuo.coinsLeft(only, now: zT0, bc), 15)
        // Вчерашнее не в счёт.
        var y = zFile()
        y.zombieDay = DayKey.of(zT0) - 1
        y.zombieCoins = 60
        XCTAssertEqual(MiniGames.coinsToday(y, now: zT0), 0)
        XCTAssertEqual(ZombieRun.coinsLeft(y, now: zT0, zCfg()), 60)
    }

    func testZeroScoreCountsGameWithoutPlay() {
        var f = zFile()
        let fun = f.pet.needs[.fun]
        let r = ZombieRun.finish(ZombieRound(seed: 1, cfg: zCfg()), in: &f, now: zT0, zCfg())
        XCTAssertEqual(r.coins, 0)
        XCTAssertFalse(r.capped)
        XCTAssertFalse(r.played)
        XCTAssertFalse(r.isRecord)
        XCTAssertNil(ZombieRun.rewardText(r))
        XCTAssertEqual(f.pet.needs[.fun], fun)
        XCTAssertEqual(f.zombieGames, 1)
    }

    func testFinishWhileAsleepKeepsRecordWithoutPlay() {
        var f = zFile()
        f.pet.napUntil = zT0 + 1800
        XCTAssertEqual(ZombieRun.gate(f, at: zT0), "asleep")
        let r = ZombieRun.finish(ZombieRun.autoplay(seed: 3, until: 10, zCfg()), in: &f, now: zT0, zCfg())
        XCTAssertFalse(r.played)
        XCTAssertEqual(r.reason, "asleep")
        XCTAssertGreaterThan(f.zombieBest, 0)
    }

    func testTexts() {
        XCTAssertEqual(ZombieRun.friendsText(1), "1 друг")
        XCTAssertEqual(ZombieRun.friendsText(3), "3 друга")
        XCTAssertEqual(ZombieRun.friendsText(5), "5 друзей")
        XCTAssertEqual(ZombieRun.friendsText(11), "11 друзей")
        XCTAssertEqual(ZombieRun.friendsText(12), "12 друзей")
        XCTAssertEqual(ZombieRun.friendsText(21), "21 друг")
        XCTAssertEqual(ZombieRun.friendsText(22), "22 друга")
        XCTAssertEqual(ZombieRun.friendsText(0), "0 друзей")
        var r = ZombieResult()
        XCTAssertEqual(ZombieRun.resultTitle(r), "Зомби даже не заметили…")
        XCTAssertFalse(ZombieRun.shibaLine(r).isEmpty)
        r.score = 240; r.friends = 18; r.best = 400; r.hugs = 3
        XCTAssertEqual(ZombieRun.resultTitle(r), "Зацеловали!")
        r.survived = true; r.hearts = 1; r.hugs = 2
        XCTAssertEqual(ZombieRun.resultTitle(r), "Продержались!")
        XCTAssertEqual(ZombieRun.shibaLine(r), ZombieRun.shibaLine(r), "один раунд — одна фраза")
        r.isRecord = true
        XCTAssertEqual(ZombieRun.resultTitle(r), "Новый рекорд!")
        XCTAssertTrue(ZombieRun.shibaLine(r).contains("18 друзей"))
        r.coins = 12; r.careCoins = 3
        XCTAssertEqual(ZombieRun.rewardText(r), "+\(EconText.coins(15))")
        XCTAssertEqual(ZombieRun.reactKind, BlockDuo.reactKind)
    }

    // MARK: сейв и конфиг

    func testSaveFieldsTopLevelAndOldSave() throws {
        var f = zFile()
        ZombieRun.finish(ZombieRun.autoplay(seed: 3, zCfg()), in: &f, now: zT0, zCfg())
        let data = try JSONEncoder().encode(f)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((obj["zombieBest"] as? NSNumber)?.intValue, f.zombieBest, "рекорд — верхним уровнем")
        XCTAssertNotNil(obj["zombieDay"])
        XCTAssertNotNil(obj["zombieCoins"])
        let back = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(back.zombieBest, f.zombieBest)
        XCTAssertEqual(back.zombieDay, f.zombieDay)
        XCTAssertEqual(back.zombieCoins, f.zombieCoins)
        XCTAssertEqual(back.zombieGames, 1)

        var plain = f
        plain.zombieBest = 0; plain.zombieDay = 0; plain.zombieCoins = 0; plain.zombieGames = 0
        let oldData = try JSONEncoder().encode(plain)
        XCTAssertFalse(String(decoding: oldData, as: UTF8.self).contains("\"zombieBest\""))
        XCTAssertFalse(String(decoding: oldData, as: UTF8.self).contains("\"zombieGames\""))
        let oldFile = try JSONDecoder().decode(SaveFile.self, from: oldData)
        XCTAssertEqual(oldFile.zombieBest, 0)
        XCTAssertEqual(oldFile.petId, f.petId)
        XCTAssertEqual(oldFile.econ.wallet, f.econ.wallet)

        let text = String(decoding: oldData, as: UTF8.self)
        let broken = "{\"zombieBest\":\"много\",\"zombieGames\":2," + text.dropFirst()
        let b = try JSONDecoder().decode(SaveFile.self, from: Data(broken.utf8))
        XCTAssertEqual(b.zombieBest, 0)
        XCTAssertEqual(b.zombieGames, 2)
        XCTAssertEqual(b.petId, f.petId)

        let fresh = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SaveFile.fresh(now: zT0))) as? [String: Any]
        XCTAssertNil(fresh?["zombieBest"])
        XCTAssertNil(fresh?["zombieGames"])
    }

    func testStartOverKeepsRecordAndDailyCap() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-zombie")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: zT0)
        try store.mutate { (f: inout SaveFile) -> Void in
            f.zombieBest = 470
            f.zombieDay = DayKey.of(zT0)
            f.zombieCoins = 60
            f.zombieGames = 4
        }
        try store.startOver(now: zT0 + 100)
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.zombieBest, 470, "рекорд хозяина остаётся")
        XCTAssertEqual(f.zombieCoins, 60, "новым щенком потолок не обнулить")
        XCTAssertEqual(f.zombieDay, DayKey.of(zT0))
        XCTAssertEqual(f.zombieGames, 4)
    }

    func testConfigFromEconomyJSON() {
        let d = ZombieConfig(json: .null)
        XCTAssertEqual(d.name, "Щенок против зомби")
        XCTAssertEqual(d.roundSeconds, 50)
        XCTAssertEqual(d.sharedCap, MiniGames.defaultSharedCap)

        let s = ZombieConfig.shared
        XCTAssertEqual(s.name, "Щенок против зомби")
        XCTAssertGreaterThanOrEqual(s.roundSeconds, 45, "раунд 45–60 с")
        XCTAssertLessThanOrEqual(s.roundSeconds, 60)
        XCTAssertGreaterThan(s.hearts, 0)
        XCTAssertGreaterThan(s.base, 0)
        XCTAssertGreaterThanOrEqual(s.max, s.base)
        XCTAssertLessThanOrEqual(s.max, s.dailyCap, "один раунд не выбирает больше дневного потолка")
        XCTAssertEqual(s.sharedCap, CatchConfig.shared.sharedCap, "общий потолок один на все игры")
        XCTAssertEqual(s.diminishing, CatchConfig.shared.diminishing, "убывание общее")
        XCTAssertEqual(s.asCatch.parScore, s.parScore)
    }

    // MARK: растеризатор

    private func flatCam() -> RetroCamera { RetroCamera(eye: RVec(0, 0, -3), target: .zero, fovY: 1.0) }

    func testBoxDrawsNearFaceAndCullsBack() {
        var c = RetroCanvas(w: 64, h: 48)
        c.jitter = false
        c.light = RetroLight(dir: RVec(0, 0, -1), ambient: 0.5, diffuse: 0.5)
        c.begin(flatCam(), top: .zero, bottom: .zero)
        c.draw(.box(.one, RVec(1, 0, 0), front: RVec(0, 1, 0)))  // front — грань +z, она от камеры
        XCTAssertTrue(c.covered(x: 32, y: 24))
        XCTAssertFalse(c.covered(x: 2, y: 2), "фон пустой")
        let mid = c.color(x: 32, y: 24)
        XCTAssertEqual(mid.x, 1, accuracy: 0.02, "к камере — грань −z, свет в лицо")
        XCTAssertEqual(mid.y, 0, accuracy: 0.02, "грань +z (front) не видна")
        XCTAssertLessThanOrEqual(c.drawn, 6, "задние грани отброшены")
        XCTAssertGreaterThan(c.drawn, 0)
        // За камерой — ничего.
        var back = RetroCanvas(w: 32, h: 32)
        back.begin(flatCam(), top: .zero, bottom: .zero)
        back.draw(.box(.one, at: RVec(0, 0, -6), .one))
        XCTAssertEqual(back.drawn, 0)
        XCTAssertNil(back.project(RVec(0, 0, -6)))
        let p = try? XCTUnwrap(c.project(.zero))
        XCTAssertEqual(p?.x ?? 0, 32, accuracy: 1e-9)
        XCTAssertEqual(p?.y ?? 0, 24, accuracy: 1e-9)
    }

    func testDepthKeepsNearerAndNearPlaneClips() {
        var c = RetroCanvas(w: 40, h: 40)
        c.jitter = false
        c.light = RetroLight(dir: RVec(0, 0, -1), ambient: 1, diffuse: 0)
        c.begin(flatCam(), top: .zero, bottom: .zero)
        c.draw(.box(.one, at: RVec(0, 0, -0.5), RVec(0, 0, 1)))
        c.draw(.box(RVec(3, 3, 1), at: RVec(0, 0, 2), RVec(1, 0, 0)))
        XCTAssertEqual(c.color(x: 20, y: 20).z, 1, accuracy: 0.02, "ближний синий поверх дальнего красного")
        XCTAssertEqual(c.color(x: 20, y: 20).x, 0, accuracy: 0.02)
        // Пол через камеру: часть за ближней плоскостью отрезается, а не выворачивается.
        var f = RetroCanvas(w: 40, h: 40)
        f.light = RetroLight(dir: RVec(0, 1, 0), ambient: 1, diffuse: 0)
        f.begin(RetroCamera(eye: RVec(0, 1, 0), target: RVec(0, 0.5, 5)), top: .zero, bottom: .zero)
        var floor = RetroMesh()
        floor.quad(RVec(-5, 0, -5), RVec(5, 0, -5), RVec(5, 0, 20), RVec(-5, 0, 20), normal: RVec(0, 1, 0), .one)
        f.draw(floor)
        XCTAssertTrue(f.covered(x: 20, y: 39), "пол под ногами виден")
        XCTAssertFalse(f.covered(x: 20, y: 2), "над горизонтом пола нет")
    }

    func testFogFadesFarToFogColor() {
        var c = RetroCanvas(w: 40, h: 40)
        c.jitter = false
        c.fog = RetroFog(color: RVec(0.2, 0.1, 0.3), start: 2, end: 10)
        c.light = RetroLight(dir: RVec(0, 0, -1), ambient: 1, diffuse: 0)
        c.begin(flatCam(), top: .zero, bottom: .zero)
        c.draw(.box(RVec(40, 40, 0.1), at: RVec(0, 0, 30), .one))
        let far = c.color(x: 20, y: 20)
        XCTAssertEqual(far.x, 0.2, accuracy: 0.01, "дальше конца тумана — цвет тумана")
        XCTAssertEqual(far.z, 0.3, accuracy: 0.01)
        var n = RetroCanvas(w: 40, h: 40)
        n.jitter = false
        n.fog = c.fog
        n.light = c.light
        n.begin(flatCam(), top: .zero, bottom: .zero)
        n.draw(.box(RVec(4, 4, 0.1), at: RVec(0, 0, 4), .one))
        let mid = n.color(x: 20, y: 20)
        XCTAssertLessThan(mid.x, 1)
        XCTAssertGreaterThan(mid.x, 0.4, "в середине тумана — наполовину")
    }

    func testDitherQuantizesAndIsDeterministic() {
        var c = RetroCanvas(w: 16, h: 16)
        c.begin(flatCam(), top: RVec(0.5, 0.5, 0.5), bottom: RVec(0.52, 0.52, 0.52))
        let plain = c.rgba(levels: 4, dither: false)
        let dith = c.rgba(levels: 4, dither: true)
        XCTAssertEqual(plain.count, 16 * 16 * 4)
        XCTAssertEqual(Set(stride(from: 3, to: plain.count, by: 4).map { plain[$0] }), [255], "непрозрачно")
        let levels = Set(stride(from: 0, to: plain.count, by: 4).map { plain[$0] })
        XCTAssertEqual(levels.count, 1, "без дизеринга ровная заливка одним уровнем")
        let dl = Set(stride(from: 0, to: dith.count, by: 4).map { dith[$0] })
        XCTAssertEqual(dl.count, 2, "с дизерингом — узор из двух соседних уровней")
        for v in dl { XCTAssertEqual(Int(v) % 85, 0, "4 уровня: 0, 85, 170, 255") }
        XCTAssertEqual(dith, c.rgba(levels: 4, dither: true))
        let ppm = c.ppm(levels: 4)
        XCTAssertEqual(ppm.count, "P6\n16 16\n255\n".utf8.count + 16 * 16 * 3)
    }

    // MARK: сцена

    func testSceneRendersPuppyZombiesAndToys() {
        let r = ZombieRun.autoplay(seed: 7, until: 21)
        let w = ZombieArt.width, h = ZombieArt.height(for: 1.5)
        var a = RetroCanvas(w: w, h: h)
        ZombieArt.render(r, into: &a)
        var b = RetroCanvas(w: w, h: h)
        ZombieArt.render(r, into: &b)
        XCTAssertEqual(a.rgba(), b.rgba(), "кадр детерминирован")
        XCTAssertGreaterThan(a.drawn, 200)
        // Шиба внизу посередине кадра закрывает пол.
        let p = a.project(RVec(r.puppyX, 0.45, 0))
        XCTAssertNotNil(p)
        if let p {
            XCTAssertGreaterThan(p.y, Double(h) * 0.55, "пёс в нижней части кадра")
            XCTAssertGreaterThan(p.x, 0)
            XCTAssertLessThan(p.x, Double(w))
            XCTAssertEqual(a.color(x: Int(p.x), y: Int(p.y)).x, ZombieArt.fur.x, accuracy: 0.35, "рыжий")
        }
        // Дальний конец коридора тонет в тумане.
        let far = a.project(RVec(0, 1.2, 24))
        if let far {
            let c = a.color(x: Int(far.x), y: Int(far.y))
            XCTAssertEqual(c.x, ZombieArt.fogColor.x, accuracy: 0.06)
            XCTAssertEqual(c.z, ZombieArt.fogColor.z, accuracy: 0.06)
        }
        for happy in [false, true] {
            var pc = RetroCanvas(w: w, h: ZombieArt.height(for: 0.62))
            ZombieArt.poster(into: &pc, happy: happy)
            XCTAssertGreaterThan(pc.drawn, 200)
            XCTAssertTrue(pc.covered(x: w / 2, y: pc.h * 2 / 3), "Шиба в центре постера")
        }
        XCTAssertEqual(ZombieArt.height(for: 1.5), 264)
        XCTAssertEqual(ZombieArt.height(for: 100), 520)
        XCTAssertEqual(ZombieArt.height(for: 0), 120)
    }

    /// Кадры для глаз: PET_ZOMBIE_DUMP=<папка> — несколько моментов игры и оба постера.
    func testDumpFramesWhenAsked() throws {
        guard let dir = ProcessInfo.processInfo.environment["PET_ZOMBIE_DUMP"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let w = ZombieArt.width, h = ZombieArt.height(for: 1.55)
        for t in [3.0, 12.0, 21.0, 33.0] {
            let r = ZombieRun.autoplay(seed: 7, until: t)
            var c = RetroCanvas(w: w, h: h)
            ZombieArt.render(r, into: &c)
            try c.ppm().write(to: url.appendingPathComponent("play-\(Int(t)).ppm"))
        }
        for happy in [false, true] {
            var c = RetroCanvas(w: w, h: ZombieArt.height(for: 0.62))
            ZombieArt.poster(into: &c, happy: happy)
            try c.ppm().write(to: url.appendingPathComponent(happy ? "poster-happy.ppm" : "poster.ppm"))
        }
    }
}
