// Волна 11: «Лавка» — раз в сутки три предмета из пулов капсулы на витрине, за монеты (только монеты,
// реальных денег в игре нет). Витрина детерминирована по petId и местным суткам (StableHash): та же собака
// в тот же день видит то же самое, а на другом телефоне с тем же сейвом — тоже. Легендарных в лавке нет
// (economy.json shop.price_bands._note: они только из капсул/вех/ярмарки). Цена — по редкости в полосах
// price_bands: одежда и мячики — clothes, вещи на полку — furniture.

import Foundation
@preconcurrency import PetCore

/// Поле shop в SaveFile: витрина на сутки day и что из неё уже купили. Вложенные поля читаются мягко.
struct ShopDay: Codable, Hashable, Sendable {
    var day: Int
    var ids: [String]
    var bought: [String] = []

    init(day: Int, ids: [String], bought: [String] = []) {
        self.day = day
        self.ids = ids
        self.bought = bought
    }

    enum CodingKeys: String, CodingKey { case day, ids, bought }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? c.decodeIfPresent(Int.self, forKey: .day)) ?? Int.min
        ids = (try? c.decodeIfPresent([String].self, forKey: .ids)) ?? []
        bought = (try? c.decodeIfPresent([String].self, forKey: .bought)) ?? []
    }
}

/// Карточка витрины для экрана.
struct ShopOffer: Hashable, Sendable, Identifiable {
    enum State: Hashable, Sendable {
        /// Можно купить; need > 0 — не хватает монет.
        case buy(need: Int)
        /// Купили сегодня здесь.
        case sold
        /// Уже есть в коллекции (из капсулы).
        case owned
    }

    let item: CapsuleItem
    let role: ItemRole?
    let price: Int
    let state: State

    var id: String { item.id }
}

enum ShopDaily {
    /// Слоты витрины: по одному предмету каждой редкости, дешёвое слева.
    static let slots: [Rarity] = [.common, .rare, .epic]

    /// Полосы цен по редкости: [от, до] монет.
    struct Bands: Hashable, Sendable {
        var clothes: [Rarity: ClosedRange<Int>] = [
            .common: 80...150, .rare: 300...600, .epic: 900...1800, .legendary: 3000...6000,
        ]
        var furniture: [Rarity: ClosedRange<Int>] = [
            .common: 100...250, .rare: 400...800, .epic: 1200...2500, .legendary: 5000...8000,
        ]

        init() {}

        /// Из economy.json shop.price_bands; чего нет — значения по умолчанию выше.
        init(json e: JSONValue) {
            func read(_ v: JSONValue, into out: inout [Rarity: ClosedRange<Int>]) {
                for r in Rarity.allCases {
                    let a = v[r.rawValue].array.compactMap { $0.double }
                    guard a.count == 2, a[0] >= 0, a[1] >= a[0] else { continue }
                    out[r] = Int(a[0])...Int(a[1])
                }
            }
            read(e["shop"]["price_bands"]["clothes"], into: &clothes)
            read(e["shop"]["price_bands"]["furniture"], into: &furniture)
        }
    }

    static let bands = Bands(json: Catalog.economy() ?? .null)

    static func hash(_ s: String) -> UInt64 { StableRandom.mix(StableHash.fnv1a(s)) }

    /// Цена предмета: точка в полосе его редкости, шаг 10 монет. От дня не зависит — у вещи одна цена.
    static func price(_ item: CapsuleItem, _ b: Bands = bands) -> Int {
        let table = ItemCatalog.decor.contains(item.id) ? b.furniture : b.clothes
        guard let band = table[item.rarity] else { return 0 }
        let lo = (band.lowerBound + 9) / 10 * 10
        let steps = max(0, (band.upperBound - lo) / 10)
        return lo + Int(hash("shop:price:\(item.id)") % UInt64(steps + 1)) * 10
    }

    /// Витрина на сутки day: из каждой редкости слота — предмет, которого ещё нет; если есть всё —
    /// любой (покажется «Уже есть»). Порядок внутри пула — по хешу petId+день+id, не по месту в списке:
    /// новые предметы в пулах не сдвигают выбор старых дней.
    static func pick(petId: String, day: Int, owned: Set<String>,
                     cfg: CapsuleConfig = EconomyConfig.shared.capsule) -> [String] {
        slots.compactMap { r -> String? in
            let pool = cfg.pools[r] ?? []
            let ranked = pool.map(\.id).sorted {
                let a = hash("\(petId):shop:\(day):\($0)"), b = hash("\(petId):shop:\(day):\($1)")
                return a != b ? a < b : $0 < $1
            }
            return ranked.first { !owned.contains($0) } ?? ranked.first
        }
    }

    /// Витрина сегодня без записи: сохранённая за эти сутки или новая.
    static func today(_ f: SaveFile, now: Double, cfg: CapsuleConfig = EconomyConfig.shared.capsule) -> ShopDay {
        let day = Economy.day(now)
        if let s = f.shop, s.day == day, !s.ids.isEmpty { return s }
        return ShopDay(day: day, ids: pick(petId: f.petId, day: day, owned: Set(f.econ.items.keys), cfg: cfg))
    }

    /// Закрепить витрину суток в файле: после покупки или крутки капсулы она не перетасуется.
    @discardableResult
    static func roll(_ f: inout SaveFile, now: Double, cfg: CapsuleConfig = EconomyConfig.shared.capsule) -> ShopDay {
        let s = today(f, now: now, cfg: cfg)
        if f.shop != s { f.shop = s }
        return s
    }

    /// Карточки для экрана.
    static func offers(_ f: SaveFile, now: Double, cfg: CapsuleConfig = EconomyConfig.shared.capsule,
                       _ b: Bands = bands) -> [ShopOffer] {
        let s = today(f, now: now, cfg: cfg)
        let byId = cfg.itemsById
        let coins = f.econ.wallet.coins
        return s.ids.compactMap { id -> ShopOffer? in
            guard let it = byId[id] else { return nil }
            let p = price(it, b)
            let state: ShopOffer.State
            if s.bought.contains(id) { state = .sold }
            else if f.econ.items[id] != nil { state = .owned }
            else { state = .buy(need: max(0, p - coins)) }
            return ShopOffer(item: it, role: ItemCatalog.role(id), price: p, state: state)
        }
    }

    enum BuyResult: Equatable, Sendable {
        case ok(price: Int)
        /// Этого сегодня на витрине нет (сменились сутки, пока экран был открыт).
        case notOnShelf
        /// Уже купили сегодня.
        case sold
        /// Уже есть в коллекции.
        case owned
        case noCoins(need: Int)
    }

    /// Купить с витрины. Не хватает монет — ничего не меняется. В журнал — shop.buy (key — id, value — цена).
    @discardableResult
    static func buy(_ id: String, in f: inout SaveFile, now: Double,
                    cfg: CapsuleConfig = EconomyConfig.shared.capsule, _ b: Bands = bands) -> BuyResult {
        var s = roll(&f, now: now, cfg: cfg)
        guard s.ids.contains(id), let it = cfg.itemsById[id] else { return .notOnShelf }
        if s.bought.contains(id) { return .sold }
        if f.econ.items[id] != nil { return .owned }
        let p = price(it, b)
        guard Economy.spend(&f, coins: p) else { return .noCoins(need: p - f.econ.wallet.coins) }
        f.econ.items[id] = 1
        s.bought.append(id)
        f.shop = s
        f.log("shop.buy", t: now, key: id, value: p)
        return .ok(price: p)
    }

    /// Покупка через стор: одна запись под замком.
    static func perform(_ id: String, store: PetStore = .shared, now: Double = Clock.now()) throws -> BuyResult {
        try store.mutate { f in buy(id, in: &f, now: now) }
    }

    /// Открыли лавку — закрепить витрину суток.
    static func open(store: PetStore = .shared, now: Double = Clock.now()) throws {
        try store.mutate { f in roll(&f, now: now) }
    }

    /// Отказ после нажатия; nil — купили.
    static func refusal(_ r: BuyResult, lines: Lines = .shared) -> String? {
        switch r {
        case .ok: return nil
        case .notOnShelf: return "Витрина уже сменилась"
        case .sold: return "Уже купили сегодня"
        case .owned: return "Это уже есть в коллекции"
        case .noCoins(let need): return EconText.notEnough(need: need, lines: lines)
        }
    }

    /// Подпись на кнопке карточки.
    static func buttonTitle(_ o: ShopOffer) -> String {
        switch o.state {
        case .sold: return "Куплено"
        case .owned: return "Уже есть"
        case .buy(let need): return need > 0 ? "Не хватает \(need)" : "Купить"
        }
    }

    /// Секунд до новой витрины (местная полночь).
    static func secondsToNext(now: Double) -> Double {
        let off = Double(Clock.tzOffsetMin(at: now)) * 60
        let local = now + off
        return (local / 86400).rounded(.down) * 86400 + 86400 - local
    }
}
