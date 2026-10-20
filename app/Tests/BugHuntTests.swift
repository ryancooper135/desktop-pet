// Волна 30: охота на баги. Каждый тест — регрессия найденного бага (RESEARCH/16-bugs.md): сначала падал, потом починили.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000: днём пёс не спит.
private let bT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

private func bFile(at t: Double = bT0, level: Double = 60) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = "bughunt-pet-1"
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = level }
    return f
}

/// Конфиг зомби с явными цифрами — тест не зависит от правок economy.json.
private func bZombieCfg() -> ZombieConfig {
    var c = ZombieConfig()
    c.roundSeconds = 50
    c.hearts = 3
    c.base = 5
    c.max = 40
    c.parScore = 500
    c.dailyCap = 60
    c.sharedCap = 60
    c.diminishing = [.init(from: 1, x: 1), .init(from: 7, x: 0.5), .init(from: 13, x: 0.2)]
    return c
}

final class BugHuntTests: XCTestCase {

    // MARK: «Щенок против зомби» платил мёртвому псу

    func testZombieFinishAfterDeathPaysNothing() {
        // Волна 13 (DECISIONS «Мини-игры после смерти»): пёс умер, пока шёл раунд, — монет нет, рекорд остаётся.
        // «Лови мячик» и «Блок Дуо» так и делают; зомби платили — монеты уходили в кошелёк, который переходит щенку.
        let cfg = bZombieCfg()
        let round = ZombieRun.autoplay(seed: 3, cfg)
        XCTAssertGreaterThan(round.score, 0, "раунд с очками: иначе монет и так ноль")
        var f = bFile()
        f.pet.alive = false
        let coins = f.econ.wallet.coins
        let r = ZombieRun.finish(round, in: &f, now: bT0, cfg)
        XCTAssertEqual(r.coins, 0)
        XCTAssertEqual(r.totalCoins, 0)
        XCTAssertFalse(r.capped, "не «на сегодня хватит»: просто некому")
        XCTAssertNil(ZombieRun.rewardText(r))
        XCTAssertEqual(f.econ.wallet.coins, coins)
        XCTAssertEqual(f.zombieCoins, 0, "дневной потолок не съеден")
        XCTAssertFalse(r.played)
        XCTAssertEqual(f.zombieBest, round.score, "рекорд остаётся")
    }

    func testZombieFinishAliveStillPays() {
        // Контроль к тесту выше: живому псу платим как раньше.
        let cfg = bZombieCfg()
        let round = ZombieRun.autoplay(seed: 3, cfg)
        var f = bFile()
        let coins = f.econ.wallet.coins
        let r = ZombieRun.finish(round, in: &f, now: bT0, cfg)
        XCTAssertGreaterThan(r.coins, 0)
        XCTAssertEqual(f.econ.wallet.coins, coins + r.coins + r.careCoins)
    }

    // MARK: ссылка pet://shop / pet://kitchen: второй шаг после того, как автомат или «Дом» уже закрыли

    func testDeepLinkFollowUpOnlyForNestedSheets() {
        XCTAssertEqual(DeepLink.followUp("shop")?.parent, "capsule")
        XCTAssertEqual(DeepLink.followUp("shop")?.child, "shop")
        XCTAssertEqual(DeepLink.followUp("kitchen")?.parent, "house")
        XCTAssertEqual(DeepLink.followUp("kitchen")?.child, "kitchen")
        for h in DeepLink.routes.subtracting(["shop", "kitchen"]) {
            XCTAssertNil(DeepLink.followUp(h), h)
        }
        XCTAssertNil(DeepLink.followUp(nil))
        XCTAssertNil(DeepLink.followUp("home"))
    }

    func testDeepLinkFollowUpNeedsParentStillOpen() {
        // pet://shop: автомат открыт — через 0.8 с лавка поверх него.
        XCTAssertTrue(DeepLink.mayFollow("shop", open: ["capsule"]))
        XCTAssertTrue(DeepLink.mayFollow("kitchen", open: ["house"]))
        // Автомат успели закрыть (свайп, pet://home, другая ссылка) — лавку не открывать: её лист висит внутри
        // автомата, флаг остался бы true без листа (anyCover держит подсказки, лавка выскочит при следующем автомате).
        XCTAssertFalse(DeepLink.mayFollow("shop", open: []))
        XCTAssertFalse(DeepLink.mayFollow("kitchen", open: []))
        // Пока ждали, открыли чужое — тоже нет.
        XCTAssertFalse(DeepLink.mayFollow("shop", open: ["needs"]))
        XCTAssertFalse(DeepLink.mayFollow("shop", open: ["capsule", "needs"]))
        XCTAssertFalse(DeepLink.mayFollow("kitchen", open: ["capsule"]))
        // Лавка уже открыта (кнопкой в автомате) — второй раз нечего.
        XCTAssertFalse(DeepLink.mayFollow("shop", open: ["capsule", "shop"]))
        // У простых целей второго шага нет.
        XCTAssertFalse(DeepLink.mayFollow("needs", open: ["needs"]))
        XCTAssertFalse(DeepLink.mayFollow(nil, open: []))
    }
}
