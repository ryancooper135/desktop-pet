// Волна 32: мягкая смерть (Runaway.swift). Пёс «убежал» на последнем сердечке: поиски по следам в разные
// заходы, шаги или ✂️; возвращается тот же пёс (имя, память, трюки), но уставший, грязный и с потерей монет.
// Срок поисков, третий побег за 30 дней, перевод часов назад — только новый щенок. Сейв: поле верхним уровнем,
// новому щенку не переходит. Гоняется и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let rT0: Double = 1_760_000_000

/// Пёс умер в t0: монеты, клочки, имя и трюк — чтобы проверить, что возвращается он сам.
private func deadFile(at t: Double = rT0, coins: Int = 200, shards: Int = 0) -> SaveFile {
    var f = SaveFile.fresh(now: t - 3600)
    f.petId = "runaway-pet"
    f.name = "Бублик"
    f.pet.alive = false
    f.pet.diedAt = t
    f.pet.cause = .toska
    f.pet.hearts = 1
    f.pet.t = t
    f.econ.wallet.coins = coins
    f.econ.wallet.shards = shards
    return f
}

private func cfg() -> RunawayConfig { RunawayConfig() }

final class RunawayTests: XCTestCase {

    func testConfigFromEconomyJSON() {
        let c = RunawayConfig.shared
        XCTAssertTrue(c.enabled, "death.permanent = false")
        XCTAssertEqual(c.searchH, 72)
        XCTAssertEqual(c.trails, 2)
        XCTAssertEqual(c.trailGapH, 4)
        XCTAssertEqual(c.steps, 3000)
        XCTAssertEqual(c.shards, 30)
        XCTAssertEqual(c.maxInWindow, 2)
        XCTAssertEqual(c.windowDays, 30)
        XCTAssertEqual(c.backHearts, 2.5)
        XCTAssertEqual(c.coinsLostPct, 20)
        XCTAssertEqual(c.backNeeds["clean"], 20)
        var f = SaveFile.fresh(now: rT0)
        XCTAssertEqual(Runaway.shardsCost(f), 30)
        f.runaway.comebacks = [rT0, rT0 + 1]
        XCTAssertEqual(Runaway.shardsCost(f), 60, "каждый прошлый возврат дороже на 15")
    }

    func testAliveHasNoStatus() {
        let f = SaveFile.fresh(now: rT0)
        XCTAssertNil(Runaway.status(f, at: rT0))
        var g = f
        Runaway.observe(&g, now: rT0)
        XCTAssertTrue(g.runaway.isEmpty)
    }

    func testObserveStartsSearchWhenSeen() {
        var f = deadFile()
        // Хозяин открыл приложение через 10 ч после смерти: срок идёт от этого момента.
        Runaway.observe(&f, now: rT0 + 10 * 3600, cfg())
        XCTAssertEqual(f.runaway.since, rT0 + 10 * 3600)
        let st = Runaway.status(f, at: rT0 + 10 * 3600, cfg())!
        XCTAssertTrue(st.canReturn)
        XCTAssertEqual(st.hoursLeft, 72, accuracy: 0.01)
        XCTAssertTrue(st.trailReady)
        XCTAssertFalse(st.found)
    }

    func testTwoTrailsInDifferentVisitsFindThePet() {
        var f = deadFile()
        let c = cfg()
        XCTAssertEqual(Runaway.searchTrail(&f, now: rT0 + 60, c), .ok)
        XCTAssertEqual(Runaway.searchTrail(&f, now: rT0 + 3600, c), .no("later"), "в тот же заход — нельзя")
        XCTAssertFalse(Runaway.status(f, at: rT0 + 3600, c)!.trailReady)
        XCTAssertEqual(Runaway.status(f, at: rT0 + 3600, c)!.trailInH, 3, accuracy: 0.05)
        XCTAssertEqual(Runaway.searchTrail(&f, now: rT0 + 60 + 4 * 3600, c), .found)
        XCTAssertTrue(Runaway.status(f, at: rT0 + 5 * 3600, c)!.found)
        XCTAssertEqual(Runaway.bringBack(&f, way: .trails, now: rT0 + 5 * 3600, c), .ok)
        XCTAssertTrue(f.pet.alive)
    }

    func testBringBackKeepsTheSameDogAndCostsSomething() {
        var f = deadFile(coins: 200)
        var e = TrickLog.Entry()
        e.n = 5
        e.learned = rT0 - 7200
        f.tricks.items["sit"] = e
        let c = cfg()
        Runaway.searchTrail(&f, now: rT0, c)
        Runaway.searchTrail(&f, now: rT0 + 5 * 3600, c)
        let t = rT0 + 6 * 3600
        XCTAssertEqual(Runaway.bringBack(&f, way: .trails, now: t, c), .ok)
        XCTAssertEqual(f.petId, "runaway-pet")
        XCTAssertEqual(f.name, "Бублик")
        XCTAssertEqual(f.tricks.items["sit"]?.n, 5, "трюки остаются")
        XCTAssertTrue(f.pet.alive)
        XCTAssertNil(f.pet.diedAt)
        XCTAssertNil(f.pet.cause)
        XCTAssertEqual(f.pet.hearts, 2.5)
        XCTAssertEqual(f.pet.t, t)
        XCTAssertEqual(f.pet.needs[.clean], 20)
        XCTAssertEqual(f.pet.needs[.food], 40)
        XCTAssertEqual(f.econ.wallet.coins, 160, "20 % монет — на объявления")
        XCTAssertEqual(f.runaway.comebacks, [t])
        XCTAssertNil(f.runaway.since)
        XCTAssertEqual(f.journal.last?.kind, "runaway.back")
        XCTAssertEqual(f.journal.last?.value, 40)
        // Вернулся не на грани: не «Критично», и после возвращения ядро идёт дальше как обычно.
        XCTAssertLessThan(PetEngine.level(f.pet, Catalog.rules), 3)
        PetRunner.catchUp(&f, now: t + 3600)
        XCTAssertTrue(f.pet.alive)
        XCTAssertEqual(f.pet.t, t + 3600, accuracy: 60)
    }

    func testNotFoundCannotBringBackForFree() {
        var f = deadFile()
        XCTAssertEqual(Runaway.bringBack(&f, way: .trails, now: rT0, cfg()), .no("not_found"))
        XCTAssertFalse(f.pet.alive)
    }

    func testShardsBringBackRightAway() {
        var f = deadFile(coins: 50, shards: 31)
        XCTAssertEqual(Runaway.bringBack(&f, way: .shards, now: rT0 + 60, cfg()), .ok)
        XCTAssertEqual(f.econ.wallet.shards, 1)
        XCTAssertEqual(f.econ.wallet.coins, 40)
        var g = deadFile(shards: 29)
        XCTAssertEqual(Runaway.bringBack(&g, way: .shards, now: rT0 + 60, cfg()), .no("shards"))
        XCTAssertEqual(g.econ.wallet.shards, 29)
        XCTAssertFalse(g.pet.alive)
    }

    func testStepsAfterEscapeFindThePet() {
        var f = deadFile()
        let c = cfg()
        Runaway.observe(&f, now: rT0, c)
        XCTAssertNil(Runaway.stepsFrom(f, at: rT0 + 60, c), "окно короче 15 минут")
        XCTAssertEqual(Runaway.stepsFrom(f, at: rT0 + 3600, c), rT0)
        XCTAssertEqual(Runaway.addSteps(1800, &f, now: rT0 + 3600, c), .ok)
        XCTAssertEqual(Runaway.stepsFrom(f, at: rT0 + 7200, c), rT0 + 3600)
        XCTAssertEqual(Runaway.addSteps(1500, &f, now: rT0 + 7200, c), .found)
        XCTAssertNil(Runaway.stepsFrom(f, at: rT0 + 9000, c), "уже нашёлся — шагомер не нужен")
        XCTAssertEqual(Runaway.status(f, at: rT0 + 7200, c)!.steps, 3000)
        XCTAssertEqual(Runaway.bringBack(&f, way: .steps, now: rT0 + 7300, c), .ok)
    }

    func testSearchTimeRunsOut() {
        var f = deadFile()
        let c = cfg()
        Runaway.observe(&f, now: rT0, c)
        Runaway.searchTrail(&f, now: rT0 + 3600, c)
        Runaway.observe(&f, now: rT0 + 73 * 3600, c)
        XCTAssertEqual(f.runaway.lost, "late")
        let st = Runaway.status(f, at: rT0 + 73 * 3600, c)!
        XCTAssertFalse(st.canReturn)
        XCTAssertEqual(Runaway.bringBack(&f, way: .shards, now: rT0 + 73 * 3600, c), .no("late"))
        XCTAssertEqual(Runaway.title("Шиба", st), "Шибы больше нет")
    }

    func testFoundPetWaitsPastDeadline() {
        var f = deadFile()
        let c = cfg()
        Runaway.searchTrail(&f, now: rT0, c)
        Runaway.searchTrail(&f, now: rT0 + 5 * 3600, c)
        Runaway.observe(&f, now: rT0 + 100 * 3600, c)
        XCTAssertNil(f.runaway.lost, "нашёлся — ждёт, пока заберут")
        XCTAssertEqual(Runaway.bringBack(&f, way: .trails, now: rT0 + 100 * 3600, c), .ok)
    }

    func testThirdEscapeInMonthIsFinal() {
        var f = deadFile()
        let c = cfg()
        f.runaway.comebacks = [rT0 - 20 * 86400, rT0 - 5 * 86400]
        Runaway.observe(&f, now: rT0, c)
        XCTAssertEqual(f.runaway.lost, "third")
        let st = Runaway.status(f, at: rT0, c)!
        XCTAssertEqual(Runaway.title("Шиба", st), "Шиба теперь в новой семье")
        XCTAssertTrue(Runaway.detail(st).contains("Третий побег"))
        // Старые возвращения (больше 30 дней назад) не в счёт.
        var g = deadFile()
        g.runaway.comebacks = [rT0 - 40 * 86400, rT0 - 5 * 86400]
        Runaway.observe(&g, now: rT0, c)
        XCTAssertNil(g.runaway.lost)
    }

    func testClockBackClosesSearch() {
        var f = deadFile()
        let c = cfg()
        Runaway.searchTrail(&f, now: rT0 + 3600, c)
        // Часы перевели назад, чтобы поискать ещё раз в тот же заход.
        XCTAssertEqual(Runaway.searchTrail(&f, now: rT0 - 4 * 3600, c), .no("clock"))
        XCTAssertEqual(f.runaway.lost, "clock")
        // Вернули часы обратно — поиски всё равно закрыты: перевод часов не прощается.
        XCTAssertEqual(Runaway.searchTrail(&f, now: rT0 + 6 * 3600, c), .no("clock"))
        XCTAssertTrue(Runaway.detail(Runaway.status(f, at: rT0 + 6 * 3600, c)!).contains("Часы"))
    }

    func testCatchUpObservesDeath() {
        var f = deadFile()
        PetRunner.catchUp(&f, now: rT0 + 3600)
        XCTAssertEqual(f.runaway.since, rT0 + 3600)
        // Перевод часов назад у мёртвого пса — тоже clock.
        PetRunner.catchUp(&f, now: rT0 - 3600)
        XCTAssertEqual(f.runaway.lost, "clock")
    }

    func testPermanentDeathConfigTurnsItOff() throws {
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"death":{"permanent":true,"comeback":{"search_h":72}}}"#.utf8))
        let c = RunawayConfig(json: json)
        XCTAssertFalse(c.enabled)
        var f = deadFile()
        let st = Runaway.status(f, at: rT0, c)!
        XCTAssertFalse(st.canReturn)
        XCTAssertEqual(st.lost, "off")
        XCTAssertEqual(Runaway.searchTrail(&f, now: rT0, c), .no("off"))
    }

    func testSaveRoundTripAndNewPuppyForgets() throws {
        var f = deadFile()
        Runaway.searchTrail(&f, now: rT0, cfg())
        f.runaway.comebacks = [rT0 - 86400]
        let data = try JSONEncoder().encode(f)
        let g = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(g.runaway, f.runaway)
        // Пустое не пишется.
        let fresh = try JSONEncoder().encode(SaveFile.fresh(now: rT0))
        XCTAssertFalse(String(decoding: fresh, as: UTF8.self).contains("\"runaway\""))
        // Новый щенок (PetStore.startOver) начинает без чужой истории побегов.
        let dir = StoreHooks.makeTempStoreDir("pet-runaway")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: rT0 - 3600)
        let saved = f
        try store.mutate { (g: inout SaveFile) -> Void in g.runaway = saved.runaway; g.pet = saved.pet }
        XCTAssertFalse(try XCTUnwrap(store.read()).runaway.isEmpty)
        try store.startOver(now: rT0 + 86400)
        let n = try XCTUnwrap(store.read())
        XCTAssertTrue(n.runaway.isEmpty)
        XCTAssertTrue(n.pet.alive)
    }

    func testTexts() {
        let c = cfg()
        var f = deadFile()
        Runaway.observe(&f, now: rT0, c)
        let st = Runaway.status(f, at: rT0, c)!
        XCTAssertEqual(Runaway.title("Шиба", st), "Шибы нет дома")
        XCTAssertEqual(Runaway.title("Мурка", st), "Дома пусто")
        XCTAssertEqual(Runaway.detail(st), "Тоска выгнала из дома. Найди по следам (0 из 2) или пройди 3000 шагов (0). Осталось 3 суток.")
        XCTAssertEqual(Runaway.hoursText(72), "3 суток")
        XCTAssertEqual(Runaway.hoursText(30), "1 сутки 6 ч")
        XCTAssertEqual(Runaway.hoursText(0.2), "1 ч")
        XCTAssertEqual(Runaway.toast(.found), "Нашёлся! Веди домой")
        XCTAssertEqual(Runaway.toast(.no("later")), "Сегодня уже искали. Загляни попозже")
    }
}
