// Экономика без экрана: кошелёк, монеты за уход и шаги с дневными потолками, идемпотентность по журналу,
// капсула (детерминизм, веса, гарант, дубликаты, нехватка монет, лимит на день), старые сейвы, тексты.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let eT0: Double = 1_760_000_000

/// Момент от t0, после которого ещё 6 часов те же местные сутки (пояс машины).
private func eMidday() -> Double {
    var t = eT0
    while Economy.day(t) != Economy.day(t + 6 * 3600) { t += 600 }
    return t
}

/// Конфиг для тестов: настоящий из economy.json, поправленный под случай.
private func eConfig(_ edit: (inout EconomyConfig) -> Void = { _ in }) -> EconomyConfig {
    var c = EconomyConfig.shared
    edit(&c)
    return c
}

/// Записать удачное (или нет) действие прямо в журнал — так пишет PetRunner.apply.
private func eAct(_ f: inout SaveFile, _ kind: String, t: Double, ok: Bool = true, value: Int? = nil) {
    f.log("act.\(kind)", t: t, source: .app, ok: ok, value: value)
}

final class EconomyTests: XCTestCase {

    // MARK: конфиг

    func testConfigFromEconomyJSON() {
        let c = EconomyConfig.shared
        XCTAssertEqual(c.coinsStart, 150)
        XCTAssertEqual(c.ticketsStart, 1)
        XCTAssertEqual(c.shardsStart, 0)
        XCTAssertEqual(c.careDailyCap, 30)
        XCTAssertEqual(c.careCoins["feed"], 2)
        XCTAssertEqual(c.careCoins["bath"], 5)
        XCTAssertEqual(c.stepsPerCoin, 250)
        XCTAssertEqual(c.stepsCap, 40)
        XCTAssertEqual(c.habitsCap, 70)
        XCTAssertEqual(c.capsule.priceCoins, 120)
        XCTAssertEqual(c.capsule.coinsStep, 40)
        XCTAssertEqual(c.capsule.maxCoinPulls, 10)
        XCTAssertEqual(c.capsule.odds, [.common: 70, .rare: 22, .epic: 7, .legendary: 1])
        XCTAssertEqual(c.capsule.epicEvery, 15)
        XCTAssertEqual(c.capsule.legendaryEvery, 60)
        XCTAssertEqual(c.capsule.pityStart, 3)
        XCTAssertEqual(c.capsule.duplicateShards[.legendary], 150)
        XCTAssertEqual(c.rarity(.legendary).dogShow, "Чемпионская")
        for r in Rarity.allCases { XCTAssertFalse(c.capsule.pools[r, default: []].isEmpty, "пул \(r)") }
        XCTAssertEqual(Set(c.capsule.itemsById.keys).count, c.capsule.pools.values.map(\.count).reduce(0, +), "id уникальны")
    }

    func testFreshFileStartsWithWallet() {
        let f = SaveFile.fresh(now: eT0)
        XCTAssertEqual(f.econ.wallet, Econ.Wallet(coins: 150, tickets: 1, shards: 0))
        XCTAssertEqual(f.econ.paidSeq, 0)
        XCTAssertEqual(f.econ.capsule, Econ.CapsuleState(pulls: 0, pityEpic: 3, pityLegendary: 3))
        XCTAssertTrue(f.econ.items.isEmpty)
    }

    // MARK: начисление

    func testCareIncomeThroughRunner() throws {
        // Ищем час, когда «погладить» проходит (днём, не во сне): монета приходит вместе с действием.
        let base = SaveFile.fresh(now: eT0)
        var found = false
        for h in 0..<48 {
            var f = base
            let out = PetRunner.apply(.pet, source: .widget, to: &f, now: eT0 + Double(h) * 3600)
            guard out.ok else {
                XCTAssertEqual(out.coins, 0, "отказ не оплачивается")
                XCTAssertEqual(f.econ.wallet.coins, 150)
                continue
            }
            XCTAssertEqual(out.coins, 1)
            XCTAssertEqual(f.econ.wallet.coins, 151)
            XCTAssertEqual(f.econ.paidSeq, f.seq, "оплачено всё до последней записи")
            XCTAssertEqual(f.econ.lastEarn?.kind, "pet")
            XCTAssertEqual(f.econ.lastEarn.flatMap { EconText.toast($0) }, "+1 монета")
            found = true
            break
        }
        XCTAssertTrue(found, "за двое суток ни одного удачного «погладить»")
    }

    func testCareDailyCapAndNextDay() {
        let t = eMidday()
        var f = SaveFile.fresh(now: t)
        for i in 0..<5 { eAct(&f, "bath", t: t + Double(i) * 60) }       // 25
        eAct(&f, "play", t: t + 400)                                       // 28
        eAct(&f, "play", t: t + 500)                                       // 30, хотели 31
        let earned = Economy.settle(&f)
        XCTAssertEqual(f.econ.wallet.coins, 150 + 30, "потолок 30 в сутки")
        XCTAssertEqual(f.econ.daily.care, 30)
        XCTAssertEqual(earned.last?.coins, 2)
        XCTAssertEqual(earned.last?.capped, true)
        XCTAssertEqual(Economy.careLeftToday(f, at: t + 600), 0)

        eAct(&f, "feed", t: t + 700)
        let more = Economy.settle(&f)
        XCTAssertEqual(more.map(\.coins), [0])
        XCTAssertEqual(more.first.flatMap { EconText.toast($0) }, "На сегодня монет за заботу хватит")
        XCTAssertEqual(f.econ.wallet.coins, 180)

        // Следующие сутки: потолок с нуля.
        XCTAssertEqual(Economy.careLeftToday(f, at: t + 86400), 30)
        eAct(&f, "bath", t: t + 86400)
        Economy.settle(&f)
        XCTAssertEqual(f.econ.wallet.coins, 185)
        XCTAssertEqual(f.econ.daily.care, 5)
    }

    func testFailedAndUnknownActionsPayNothing() {
        let t = eMidday()
        var f = SaveFile.fresh(now: t)
        eAct(&f, "feed", t: t, ok: false)
        eAct(&f, "wake", t: t + 60)
        eAct(&f, "item", t: t + 120)
        f.log("ev.heart_lost", t: t + 180)
        XCTAssertTrue(Economy.settle(&f).isEmpty)
        XCTAssertEqual(f.econ.wallet.coins, 150)
        XCTAssertEqual(f.econ.paidSeq, f.seq, "просмотренные записи всё равно отмечены")
    }

    func testSettleIsIdempotent() throws {
        let t = eMidday()
        var f = SaveFile.fresh(now: t)
        for i in 0..<3 { eAct(&f, "feed", t: t + Double(i) * 60) }
        XCTAssertEqual(Economy.settle(&f).map(\.coins), [2, 2, 2])
        XCTAssertTrue(Economy.settle(&f).isEmpty, "второй раз — ничего")
        XCTAssertEqual(f.econ.wallet.coins, 156)

        // Другой процесс прочитал файл после записи и тоже зовёт settle: оплачено уже записано в файле.
        let data = try JSONEncoder().encode(f)
        var other = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertTrue(Economy.settle(&other).isEmpty)
        XCTAssertEqual(other.econ.wallet.coins, 156)

        // Запись, которую виджет сделал без settle, подбирается ровно один раз.
        eAct(&other, "play", t: t + 300)
        XCTAssertEqual(Economy.settle(&other).map(\.coins), [3])
        XCTAssertTrue(Economy.settle(&other).isEmpty)
        XCTAssertEqual(other.econ.wallet.coins, 159)

        // Чужое устройство (будущая синхронизация) здесь не оплачивается.
        other.journal.append(JournalEntry(id: "other-device:99", t: t + 400, kind: "act.bath", source: .app, ok: true))
        XCTAssertTrue(Economy.settle(&other).isEmpty)
        XCTAssertEqual(other.econ.wallet.coins, 159)
    }

    func testStepsIncomeWithCaps() {
        let t = eMidday()
        var f = SaveFile.fresh(now: t)
        eAct(&f, "steps", t: t, value: 1000)
        XCTAssertEqual(Economy.settle(&f).map(\.coins), [4], "1000 шагов / 250")
        eAct(&f, "steps", t: t + 3600, value: 120)
        XCTAssertTrue(Economy.settle(&f).isEmpty, "1120 шагов — всё ещё 4 монеты")
        eAct(&f, "steps", t: t + 7200, value: 9500)
        XCTAssertEqual(Economy.settle(&f).map(\.coins), [36], "10620 шагов → 42, но потолок шагов 40")
        eAct(&f, "steps", t: t + 9000, value: 5000)
        XCTAssertTrue(Economy.settle(&f).isEmpty)
        XCTAssertEqual(f.econ.wallet.coins, 190)
        XCTAssertEqual(f.econ.daily.habits, 40)

        // Общий потолок привычек меньше потолка шагов.
        let cfg = eConfig { $0.habitsCap = 10 }
        var g = SaveFile.fresh(now: t)
        eAct(&g, "steps", t: t, value: 5000)
        let e = Economy.settle(&g, cfg)
        XCTAssertEqual(e.first?.coins, 10)
        XCTAssertEqual(e.first?.capped, true)
    }

    // MARK: капсула

    func testCapsuleRollIsDeterministic() {
        let cfg = EconomyConfig.shared
        for i in 0..<50 {
            let a = CapsuleMachine.roll(petId: "pet-A", index: i, pityEpic: 0, pityLegendary: 0, cfg)
            let b = CapsuleMachine.roll(petId: "pet-A", index: i, pityEpic: 0, pityLegendary: 0, cfg)
            XCTAssertEqual(a.rarity, b.rarity)
            XCTAssertEqual(CapsuleMachine.item(petId: "pet-A", index: i, rarity: a.rarity, cfg),
                           CapsuleMachine.item(petId: "pet-A", index: i, rarity: a.rarity, cfg))
        }
        let seqA = (0..<50).map { CapsuleMachine.rawRarity(petId: "pet-A", index: $0, cfg) }
        let seqB = (0..<50).map { CapsuleMachine.rawRarity(petId: "pet-B", index: $0, cfg) }
        XCTAssertNotEqual(seqA, seqB, "у другого щенка своя последовательность")

        // Два файла одного щенка крутят одинаково.
        var f = SaveFile.fresh(now: eT0)
        f.econ.wallet.tickets = 30
        var g = f
        for _ in 0..<30 {
            let a = try? CapsuleMachine.pull(&f, pay: .ticket, now: eT0, cfg).get()
            let b = try? CapsuleMachine.pull(&g, pay: .ticket, now: eT0, cfg).get()
            XCTAssertNotNil(a)
            XCTAssertEqual(a, b)
        }
        XCTAssertEqual(f.econ, g.econ)
    }

    func testRarityDistributionMatchesWeights() {
        let cfg = EconomyConfig.shared
        var count: [Rarity: Int] = [:]
        for i in 0..<10_000 { count[CapsuleMachine.rawRarity(petId: "dist-pet", index: i, cfg), default: 0] += 1 }
        // 70 / 22 / 7 / 1 %, допуск около 4 сигм.
        XCTAssertTrue((6800...7200).contains(count[.common, default: 0]), "\(count)")
        XCTAssertTrue((2030...2370).contains(count[.rare, default: 0]), "\(count)")
        XCTAssertTrue((590...810).contains(count[.epic, default: 0]), "\(count)")
        XCTAssertTrue((60...145).contains(count[.legendary, default: 0]), "\(count)")
    }

    func testPityTriggersExactlyOnNth() throws {
        // Без удачи вообще: только обычные по весам — эпическую даёт лишь гарант.
        let cfg = eConfig {
            $0.capsule.odds = [.common: 100, .rare: 0, .epic: 0, .legendary: 0]
            $0.capsule.pityStart = 0
        }
        var f = SaveFile.fresh(now: eT0)
        f.econ = Econ.start(cfg, paidSeq: 0)
        f.econ.wallet.tickets = 100
        var got: [(Rarity, Bool)] = []
        for _ in 0..<60 {
            let p = try CapsuleMachine.pull(&f, pay: .ticket, now: eT0, cfg).get()
            got.append((p.rarity, p.forced))
        }
        for (i, (r, forced)) in got.enumerated() {
            let n = i + 1
            if n == 60 {
                XCTAssertEqual(r, .legendary, "60-я — гарант легендарной")
                XCTAssertTrue(forced)
            } else if n % 15 == 0 {
                XCTAssertEqual(r, .epic, "\(n)-я — гарант эпической")
                XCTAssertTrue(forced)
            } else {
                XCTAssertEqual(r, .common, "\(n)-я")
                XCTAssertFalse(forced)
            }
        }
        XCTAssertEqual(f.econ.capsule.pityEpic, 0)
        XCTAssertEqual(f.econ.capsule.pityLegendary, 0)

        // Старт счётчика с 3 (вложенный прогресс): гарант на 12-й крутке.
        let cfg3 = eConfig {
            $0.capsule.odds = [.common: 100, .rare: 0, .epic: 0, .legendary: 0]
        }
        var g = SaveFile.fresh(now: eT0)
        g.econ = Econ.start(cfg3, paidSeq: 0)
        g.econ.wallet.tickets = 20
        let first = (0..<12).map { _ in (try? CapsuleMachine.pull(&g, pay: .ticket, now: eT0, cfg3).get())?.rarity }
        XCTAssertEqual(first.prefix(11).compactMap { $0 }, Array(repeating: .common, count: 11))
        XCTAssertEqual(first.last, .epic)
    }

    func testPityScale() {
        var f = SaveFile.fresh(now: eT0)
        var o = CapsuleMachine.offer(f, at: eT0)
        XCTAssertEqual(o.pityCount, 3)
        XCTAssertEqual(o.pityTotal, 15)
        XCTAssertEqual(o.pityLeft, 12)
        XCTAssertEqual(o.pityProgress, 3.0 / 14.0, accuracy: 1e-9)
        f.econ.capsule.pityEpic = 14
        o = CapsuleMachine.offer(f, at: eT0)
        XCTAssertEqual(o.pityProgress, 1, "полная шкала — следующая точно эпическая")
        XCTAssertEqual(o.pityLeft, 1)
        f.econ.capsule.pityEpic = 40
        XCTAssertEqual(CapsuleMachine.offer(f, at: eT0).pityProgress, 1, "не больше 1")
    }

    func testDuplicateBecomesShards() throws {
        let one: [Rarity: [CapsuleItem]] = Dictionary(uniqueKeysWithValues: Rarity.allCases.map {
            ($0, [CapsuleItem(id: "only_\($0.rawValue)", name: "Единственный", rarity: $0)])
        })
        let cfg = eConfig {
            $0.capsule.odds = [.common: 100, .rare: 0, .epic: 0, .legendary: 0]
            $0.capsule.pools = one
        }
        var f = SaveFile.fresh(now: eT0)
        f.econ.wallet.tickets = 2
        let a = try CapsuleMachine.pull(&f, pay: .ticket, now: eT0, cfg).get()
        XCTAssertFalse(a.duplicate)
        XCTAssertEqual(f.econ.items["only_common"], 1)
        let b = try CapsuleMachine.pull(&f, pay: .ticket, now: eT0 + 1, cfg).get()
        XCTAssertTrue(b.duplicate)
        XCTAssertEqual(b.shards, 5)
        XCTAssertEqual(f.econ.wallet.shards, 5)
        XCTAssertEqual(f.econ.items.count, 1)
        XCTAssertEqual(f.journal.last?.kind, "capsule")
        XCTAssertEqual(f.journal.last?.key, "only_common")
        XCTAssertEqual(CapsuleMachine.inventory(f, cfg).map(\.id), ["only_common"])
    }

    func testNotEnoughCoinsAndNoTickets() {
        var f = SaveFile.fresh(now: eT0)
        f.econ.wallet = Econ.Wallet(coins: 100, tickets: 0, shards: 0)
        let before = f
        let byCoins = CapsuleMachine.pull(&f, pay: .coins, now: eT0)
        let byTicket = CapsuleMachine.pull(&f, pay: .ticket, now: eT0)
        XCTAssertEqual(byCoins.failure, .notEnoughCoins(need: 20))
        XCTAssertEqual(byTicket.failure, .noTickets)
        XCTAssertEqual(f.econ.wallet, before.econ.wallet, "отказ ничего не списал")
        XCTAssertEqual(f.econ.capsule, before.econ.capsule)
        XCTAssertEqual(f.seq, before.seq, "и в журнал не попал")
        XCTAssertFalse(CapsuleMachine.offer(f, at: eT0).canPayCoins)
        XCTAssertEqual(EconText.notEnough(need: 20), "Не хватает монет: 20")

        XCTAssertFalse(Economy.spend(&f, coins: 101))
        XCTAssertEqual(f.econ.wallet.coins, 100)
        XCTAssertTrue(Economy.spend(&f, coins: 40))
        XCTAssertEqual(f.econ.wallet.coins, 60)
    }

    func testCoinPriceGrowsAndDailyLimit() throws {
        let t = eMidday()
        var f = SaveFile.fresh(now: t)
        f.econ.wallet.coins = 100_000
        var prices: [Int] = []
        for i in 0..<10 {
            XCTAssertEqual(CapsuleMachine.offer(f, at: t + Double(i)).coinPrice, 120 + 40 * i)
            prices.append(try CapsuleMachine.pull(&f, pay: .coins, now: t + Double(i)).get().price)
        }
        XCTAssertEqual(prices, (0..<10).map { 120 + 40 * $0 })
        XCTAssertEqual(f.econ.wallet.coins, 100_000 - prices.reduce(0, +))
        XCTAssertEqual(CapsuleMachine.offer(f, at: t + 20).coinPullsLeft, 0)
        let over = CapsuleMachine.pull(&f, pay: .coins, now: t + 20)
        XCTAssertEqual(over.failure, .dailyLimit)
        // Билетик лимитом на монеты не ограничен.
        let byTicket = CapsuleMachine.pull(&f, pay: .ticket, now: t + 30)
        XCTAssertNil(byTicket.failure)
        // Назавтра цена снова 120.
        XCTAssertEqual(CapsuleMachine.offer(f, at: t + 86400).coinPrice, 120)
        let tomorrow = try CapsuleMachine.pull(&f, pay: .coins, now: t + 86400).get()
        XCTAssertEqual(tomorrow.price, 120)
    }

    // MARK: сейвы

    func testOldSaveWithoutEconDecodes() throws {
        var old = SaveFile.fresh(now: eT0)
        for i in 0..<5 { eAct(&old, "feed", t: eT0 + Double(i) * 60) }
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        obj["econ"] = nil
        let data = try JSONSerialization.data(withJSONObject: obj)
        var f = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(f.econ.wallet, Econ.Wallet(coins: 150, tickets: 1, shards: 0))
        XCTAssertEqual(f.econ.paidSeq, old.seq, "старый журнал задним числом не оплачиваем")
        XCTAssertEqual(f.econ.capsule.pityEpic, 3)
        XCTAssertTrue(Economy.settle(&f).isEmpty)

        // Частичное поле econ: чего нет — по умолчанию.
        obj["econ"] = ["wallet": ["coins": 7], "paidSeq": 2]
        let g = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertEqual(g.econ.wallet, Econ.Wallet(coins: 7, tickets: 0, shards: 0))
        XCTAssertEqual(g.econ.paidSeq, 2)
        XCTAssertEqual(g.econ.capsule.pityEpic, 3)

        // Туда-обратно без потерь.
        var h = SaveFile.fresh(now: eT0)
        h.econ.items["scarf_knit"] = 1
        h.econ.capsule.pulls = 7
        h.econ.daily.coinPulls = 2
        let back = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(h))
        XCTAssertEqual(back.econ, h.econ)
    }

    func testStartOverKeepsWalletAndItems() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-econ")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: eT0)
        try store.mutate { (f: inout SaveFile) -> Void in
            f.econ.wallet = Econ.Wallet(coins: 999, tickets: 4, shards: 12)
            f.econ.items["cape_champion"] = 1
            f.econ.capsule.pityEpic = 9
        }
        let first = try XCTUnwrap(store.read())
        try store.startOver(now: eT0 + 100)
        let second = try XCTUnwrap(store.read())
        XCTAssertNotEqual(first.petId, second.petId)
        XCTAssertEqual(second.econ.wallet, Econ.Wallet(coins: 999, tickets: 4, shards: 12), "кошелёк переживает щенка")
        XCTAssertEqual(second.econ.items["cape_champion"], 1)
        XCTAssertEqual(second.econ.capsule.pityEpic, 9)
        XCTAssertEqual(second.econ.paidSeq, 0)
        XCTAssertNil(second.econ.lastEarn)
    }

    func testPerformThroughStore() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-econ")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: eT0)
        let p = try CapsuleMachine.perform(pay: .ticket, store: store, now: eT0).get()
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.econ.wallet.tickets, 0)
        XCTAssertEqual(f.econ.capsule.pulls, 1)
        XCTAssertEqual(f.econ.items[p.item.id], 1)
        let again = try CapsuleMachine.perform(pay: .ticket, store: store, now: eT0)
        XCTAssertEqual(again.failure, .noTickets)
    }

    // MARK: тексты

    func testEconTextKeysExist() throws {
        let ui = Lines.shared.sections["ui"] ?? [:]
        guard !ui.isEmpty else { throw XCTSkip("lines.json нет в бандле") }
        for k in EconText.keys {
            XCTAssertFalse((ui[k] ?? []).isEmpty, "нет строки ui.\(k)")
            XCTAssertTrue(k.hasPrefix("econ_") || k.hasPrefix("capsule_"), k)
        }
        XCTAssertEqual(EconText.coins(1), "1 монета")
        XCTAssertEqual(EconText.coins(3), "3 монеты")
        XCTAssertEqual(EconText.coins(5), "5 монет")
        XCTAssertEqual(EconText.coins(11), "11 монет")
        XCTAssertEqual(EconText.coins(21), "21 монета")
        XCTAssertEqual(EconText.coins(112), "112 монет")
        XCTAssertEqual(EconText.tickets(2), "2 билетика")
        XCTAssertEqual(EconText.shards(150), "150 клочков")
        XCTAssertEqual(EconText.rarityName(.epic), "Эпическая")
        XCTAssertEqual(EconText.rarityShowName(.rare), "Породистая")
        XCTAssertEqual(EconText.ui("capsule_pity", ["count": "3", "total": "15"]), "До эпической: 3/15")
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let e) = self { return e }
        return nil
    }
}
