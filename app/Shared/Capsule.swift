// Капсула «Шарик»: цена, бросок редкости по весам, гарант (pity), предмет из пула, дубликаты в клочки.
// Бросок детерминированный: от petId и номера крутки (StableHash), поэтому приложение и интенты
// получат одно и то же, а переоткрыть экран ради другого исхода нельзя.
// Цифры — capsule.* в config/economy.json; пулов там пока нет, берутся заглушки CapsuleConfig.stubPools.

import Foundation
@preconcurrency import PetCore

enum CapsulePay: String, Codable, Sendable {
    case ticket, coins
}

enum CapsuleRefusal: Error, Hashable, Sendable {
    case noTickets
    case notEnoughCoins(need: Int)   // сколько не хватает
    case dailyLimit                  // кончились крутки за монеты на сегодня
}

/// Что показать на экране автомата до крутки.
struct CapsuleOffer: Hashable, Sendable {
    let name: String
    let tickets: Int
    let coins: Int
    let ticketPrice: Int
    /// Цена следующей крутки за монеты (растёт в течение суток).
    let coinPrice: Int
    let coinPullsLeft: Int
    let canPayTicket: Bool
    let canPayCoins: Bool
    /// Мини-шкала гаранта эпической: pityCount из pityTotal, progress 0…1 (1 — следующая точно эпическая или лучше).
    let pityCount: Int
    let pityTotal: Int
    let pityProgress: Double
    /// Сколько круток до гаранта, включая гарантированную (1 — следующая).
    let pityLeft: Int
    let legendaryLeft: Int
}

/// Итог крутки для анимации в три такта: дрожит цветом rarity, раскрывается в item.
struct CapsulePull: Hashable, Sendable {
    let index: Int            // номер крутки (с нуля)
    let item: CapsuleItem
    let rarity: Rarity
    let forced: Bool          // сработал гарант
    let duplicate: Bool
    let shards: Int           // клочков за дубликат
    let paid: CapsulePay
    let price: Int            // монет или билетиков
    let pityProgress: Double  // шкала после крутки
}

enum CapsuleMachine {
    /// Цена следующей крутки за монеты на момент t.
    static func coinPrice(_ f: SaveFile, at t: Double, _ cfg: EconomyConfig = .shared) -> Int {
        cfg.capsule.priceCoins + cfg.capsule.coinsStep * coinPullsToday(f, at: t)
    }

    static func coinPullsToday(_ f: SaveFile, at t: Double) -> Int {
        Economy.day(t) > f.econ.daily.day ? 0 : f.econ.daily.coinPulls
    }

    static func pityProgress(_ c: Econ.CapsuleState, _ cfg: EconomyConfig = .shared) -> Double {
        let every = cfg.capsule.epicEvery
        guard every > 1 else { return 1 }
        return min(1, max(0, Double(c.pityEpic) / Double(every - 1)))
    }

    static func offer(_ f: SaveFile, at t: Double, _ cfg: EconomyConfig = .shared) -> CapsuleOffer {
        let c = cfg.capsule
        let w = f.econ.wallet
        let price = coinPrice(f, at: t, cfg)
        let left = max(0, c.maxCoinPulls - coinPullsToday(f, at: t))
        let st = f.econ.capsule
        return CapsuleOffer(
            name: c.name, tickets: w.tickets, coins: w.coins, ticketPrice: c.priceTickets,
            coinPrice: price, coinPullsLeft: left,
            canPayTicket: w.tickets >= c.priceTickets, canPayCoins: left > 0 && w.coins >= price,
            pityCount: min(st.pityEpic, c.epicEvery), pityTotal: c.epicEvery,
            pityProgress: pityProgress(st, cfg),
            pityLeft: max(1, c.epicEvery - st.pityEpic),
            legendaryLeft: max(1, c.legendaryEvery - st.pityLegendary))
    }

    // MARK: бросок

    static func hash(_ petId: String, _ index: Int, _ salt: String) -> UInt64 {
        StableRandom.mix(StableHash.fnv1a("\(petId):capsule:\(index):\(salt)"))
    }

    /// Выбор по весам: u по модулю суммы весов. Пустые веса — первый вариант.
    static func weighted(_ u: UInt64, _ list: [(Rarity, Int)]) -> Rarity {
        let total = list.reduce(0) { $0 + max(0, $1.1) }
        guard total > 0 else { return list.first?.0 ?? .common }
        var x = Int(u % UInt64(total))
        for (r, w) in list where w > 0 {
            if x < w { return r }
            x -= w
        }
        return list.last?.0 ?? .common
    }

    /// Редкость по весам odds без гаранта.
    static func rawRarity(petId: String, index: Int, _ cfg: EconomyConfig = .shared) -> Rarity {
        weighted(hash(petId, index, "rarity"), Rarity.allCases.map { ($0, cfg.capsule.odds[$0] ?? 0) })
    }

    /// Редкость с гарантом. Счётчики — сколько круток подряд уже было без эпической / легендарной.
    static func roll(petId: String, index: Int, pityEpic: Int, pityLegendary: Int,
                     _ cfg: EconomyConfig = .shared) -> (rarity: Rarity, forced: Bool) {
        let c = cfg.capsule
        let r = rawRarity(petId: petId, index: index, cfg)
        if r < .legendary, pityLegendary + 1 >= c.legendaryEvery { return (.legendary, true) }
        if r < .epic, pityEpic + 1 >= c.epicEvery {
            // Гарант эпической: эпическая или легендарная в пропорции их весов.
            let up = weighted(hash(petId, index, "pity"), [(.epic, c.odds[.epic] ?? 0), (.legendary, c.odds[.legendary] ?? 0)])
            return (up, true)
        }
        return (r, false)
    }

    static func item(petId: String, index: Int, rarity: Rarity, _ cfg: EconomyConfig = .shared) -> CapsuleItem {
        let pool = cfg.capsule.pools[rarity] ?? []
        guard !pool.isEmpty else { return CapsuleItem(id: "\(rarity.rawValue)_\(index)", name: "Сюрприз", rarity: rarity) }
        return pool[Int(hash(petId, index, "item") % UInt64(pool.count))]
    }

    // MARK: крутка

    /// Крутка без диска: проверить оплату, списать, бросить, положить предмет, записать в журнал.
    static func pull(_ f: inout SaveFile, pay: CapsulePay, now: Double,
                     _ cfg: EconomyConfig = .shared) -> Result<CapsulePull, CapsuleRefusal> {
        let c = cfg.capsule
        Economy.rollDay(&f.econ, day: Economy.day(now))
        let price: Int
        switch pay {
        case .ticket:
            price = c.priceTickets
            guard f.econ.wallet.tickets >= price else { return .failure(.noTickets) }
            f.econ.wallet.tickets -= price
        case .coins:
            guard f.econ.daily.coinPulls < c.maxCoinPulls else { return .failure(.dailyLimit) }
            price = coinPrice(f, at: now, cfg)
            guard f.econ.wallet.coins >= price else { return .failure(.notEnoughCoins(need: price - f.econ.wallet.coins)) }
            f.econ.wallet.coins -= price
            f.econ.daily.coinPulls += 1
        }

        let index = f.econ.capsule.pulls
        let st = f.econ.capsule
        let (rarity, forced) = roll(petId: f.petId, index: index, pityEpic: st.pityEpic, pityLegendary: st.pityLegendary, cfg)
        let it = item(petId: f.petId, index: index, rarity: rarity, cfg)

        f.econ.capsule.pulls += 1
        f.econ.capsule.pityEpic = rarity >= .epic ? 0 : st.pityEpic + 1
        f.econ.capsule.pityLegendary = rarity >= .legendary ? 0 : st.pityLegendary + 1

        let duplicate = f.econ.items[it.id] != nil
        let shards = duplicate ? (c.duplicateShards[rarity] ?? 0) : 0
        if duplicate { f.econ.wallet.shards += shards } else { f.econ.items[it.id] = 1 }

        f.log("capsule", t: now, key: it.id, value: rarity.rank)
        return .success(CapsulePull(index: index, item: it, rarity: rarity, forced: forced, duplicate: duplicate,
                                    shards: shards, paid: pay, price: price,
                                    pityProgress: pityProgress(f.econ.capsule, cfg)))
    }

    /// То же через стор: одна запись под замком, виджет и приложение не разъедутся.
    static func perform(pay: CapsulePay, store: PetStore = .shared,
                        now: Double = Clock.now()) throws -> Result<CapsulePull, CapsuleRefusal> {
        try store.mutate { f in pull(&f, pay: pay, now: now) }
    }

    /// Предметы хозяина с именами, по редкости от легендарных к обычным.
    static func inventory(_ f: SaveFile, _ cfg: EconomyConfig = .shared) -> [CapsuleItem] {
        let known = cfg.capsule.itemsById
        return f.econ.items.keys.map { known[$0] ?? CapsuleItem(id: $0, name: $0, rarity: .common) }
            .sorted { $0.rarity != $1.rarity ? $0.rarity > $1.rarity : $0.name < $1.name }
    }
}
