// Волна 35 L: куда тратить клочки ✂️ (RESEARCH/20-tycoon-design.md §6, «стоки»). Три вещи:
// 1. Золотой шарик в автомате — 50 ✂️, только редкое и выше из обычных пулов, без повторов, 85 / 13 / 2 %.
//    Пулы и шансы обычной крутки не трогает: свой бросок, свой журнал («golden»), гарант не двигает.
// 2. Очень редкие находки мест с ролью — настоящие вещи коллекции: нашёл «Ключ от ниоткуда» — он и на полке.
//    Выдаются при возвращении из похода (Places.settle), заодно доходят и до старых сейвов.
// 3. Эксклюзив места — 120 ✂️, по одной вещи в стиле места; продаётся, когда найдена половина находок места.
// Все эти вещи в коллекции обычные (itemsById, польза, роль, иконка), но в капсулах, лавке и ателье их нет:
// те берут вещи из пулов, а эти лежат в capsule.exclusive. Иконки и шапка-дуршлаг — SinksArt.swift,
// полка и мячик в 3D — app/App/RoomDecor.swift.

import Foundation

/// Вещь только с карты или только за клочки.
struct SinkItem: Hashable, Sendable {
    let id: String
    let name: String
    /// Место, к которому вещь относится.
    let place: String
    /// Очень редкая находка, которая даёт вещь. nil — эксклюзив места за ✂️.
    let find: String?
    let emoji: String
    let perk: PerkKind

    /// Редкость в коллекции: польза как у лоскутных (эпическая), а не легендарная — потолок пользы и так 20 %.
    static let rarity = Rarity.epic

    var item: CapsuleItem { CapsuleItem(id: id, name: name, rarity: Self.rarity) }
}

/// Почему не вышло.
enum SinkRefusal: Error, Hashable, Sendable {
    case notEnough(need: Int)   // сколько клочков не хватает
    case allOwned               // золотому шарику больше нечего дать
    case owned                  // эксклюзив места уже есть
    case fewFinds(left: Int)    // сколько ещё находок места нужно
    case unknown                // у места нет эксклюзива
}

/// Эксклюзив места на карточке: что показать.
enum PlaceExclusiveState: Hashable, Sendable {
    case locked(left: Int)
    case buy(price: Int, canAfford: Bool)
    case owned
}

enum ScrapSinks {
    static let goldenPrice = 50
    static let placePrice = 120
    /// Шансы золотого шарика в процентах: редкая, эпическая, легендарная.
    static let goldenOdds: [Rarity: Int] = [.rare: 85, .epic: 13, .legendary: 2]
    /// Редкости золотого шарика по порядку.
    static let goldenTiers: [Rarity] = [.rare, .epic, .legendary]

    // MARK: вещи

    /// Восемь вещей из очень редких находок и восемь эксклюзивов мест. Id не переименовывать: лежат в сейвах.
    static let all: [SinkItem] = [
        // Находки (роль вещи — из PlaceFind.role: decor → полка, toy → «Поиграть», light → полка со светом).
        SinkItem(id: "found_key", name: "Ключ от ниоткуда", place: "bus_stop", find: "bus_stop.key", emoji: "🗝", perk: .coins),
        SinkItem(id: "found_twin_sock", name: "Носок-близнец", place: "laundry", find: "laundry.twin_sock", emoji: "🧦", perk: .clean),
        SinkItem(id: "found_cat_dream", name: "Сон кота", place: "cat_hill", find: "cat_hill.dream", emoji: "🔮", perk: .sleep),
        SinkItem(id: "found_pixel_ball", name: "Мячик-пиксель", place: "arcade", find: "arcade.pixel_ball", emoji: "🟨", perk: .fun),
        SinkItem(id: "found_static_jar", name: "Помеха в банке", place: "forest_tv", find: "forest_tv.static_jar", emoji: "🫙", perk: .fun),
        SinkItem(id: "found_light", name: "Кусочек света", place: "lighthouse", find: "lighthouse.light", emoji: "✨", perk: .love),
        SinkItem(id: "found_letter", name: "Письмо со дна", place: "echo_well", find: "echo_well.letter", emoji: "✉️", perk: .love),
        SinkItem(id: "found_moon_stone", name: "Лунный камень", place: "rocket", find: "rocket.moon_stone", emoji: "🌑", perk: .sleep),
        // Эксклюзивы мест за ✂️.
        SinkItem(id: "place_route_sign", name: "Табличка «Маршрут 0»", place: "bus_stop", find: nil, emoji: "🚏", perk: .coins),
        SinkItem(id: "place_towel_scarf", name: "Шарф-полотенце", place: "laundry", find: nil, emoji: "🧣", perk: .clean),
        SinkItem(id: "place_cat_pillow", name: "Подушка-котик", place: "cat_hill", find: nil, emoji: "🐈", perk: .sleep),
        SinkItem(id: "place_mini_arcade", name: "Мини-автомат", place: "arcade", find: nil, emoji: "🕹", perk: .fun),
        SinkItem(id: "place_tv_lamp", name: "Телевизор-ночник", place: "forest_tv", find: nil, emoji: "📺", perk: .sleep),
        SinkItem(id: "place_beacon_lamp", name: "Лампа-маяк", place: "lighthouse", find: nil, emoji: "🗼", perk: .love),
        SinkItem(id: "place_well_bank", name: "Колодец-копилка", place: "echo_well", find: nil, emoji: "🪣", perk: .coins),
        SinkItem(id: "place_colander", name: "Шапка-дуршлаг", place: "rocket", find: nil, emoji: "🪖", perk: .food),
    ]

    /// Как предметы коллекции — уходят в capsule.exclusive (не в пулы).
    static let items: [CapsuleItem] = all.map(\.item)
    static let perks: [String: PerkKind] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.perk) })
    static let emoji: [String: String] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.emoji) })

    /// Мячик для «Поиграть»: жёлтый, в синих квадратиках-пикселях.
    static let toys: [String: ToyInfo] = [
        "found_pixel_ball": ToyInfo(color: 0xF2C94C, accent: 0x3D6FD1, pattern: .pixel),
    ]

    /// Надеваемое: полотенце из прачечной на шею, дуршлаг с ракеты на голову.
    static let wear: [String: WearInfo] = [
        "place_towel_scarf": WearInfo(slot: .neck, shape: .scarf, color: 0xF4F1EA, accent: 0x5B8FE0),
        "place_colander": WearInfo(slot: .head, shape: .colander, color: 0xB9C2CC, accent: 0xE2554B),
    ]

    /// На полку — всё остальное.
    static let decor: Set<String> = Set(all.map(\.id)).subtracting(toys.keys).subtracting(wear.keys)

    static func item(_ id: String) -> SinkItem? { all.first { $0.id == id } }
    /// Вещь, которую даёт очень редкая находка.
    static func item(forFind id: String) -> SinkItem? { all.first { $0.find == id } }
    /// Эксклюзив места за ✂️.
    static func exclusive(_ place: String) -> SinkItem? { all.first { $0.place == place && $0.find == nil } }

    // MARK: находки → вещи

    /// Положить в коллекцию вещи всех очень редких находок, что уже в альбоме. Зовёт Places.settle;
    /// повторно ничего не делает. В журнал — sinks.find (key — id вещи). Вернёт выданные id.
    @discardableResult
    static func grantFinds(_ f: inout SaveFile, now: Double) -> [String] {
        var out: [String] = []
        for it in all {
            guard let find = it.find, (f.trip.album[find] ?? 0) > 0, f.econ.items[it.id] == nil else { continue }
            f.econ.items[it.id] = 1
            f.log("sinks.find", t: now, key: it.id)
            out.append(it.id)
        }
        return out
    }

    // MARK: золотой шарик

    /// Чего ещё нет из редкого и выше (только обычные пулы — лоскутное и вещи мест сюда не попадают).
    static func goldenLeft(_ f: SaveFile, _ cfg: CapsuleConfig = EconomyConfig.shared.capsule) -> [Rarity: [CapsuleItem]] {
        var out: [Rarity: [CapsuleItem]] = [:]
        for r in goldenTiers {
            let left = (cfg.pools[r] ?? []).filter { f.econ.items[$0.id] == nil }
            if !left.isEmpty { out[r] = left }
        }
        return out
    }

    /// Редкость по числу v (0…99): 0–84 редкая, 85–97 эпическая, 98–99 легендарная.
    /// Выпавшей редкости уже не осталось — честная замена: ближайшая ниже (не ниже редкой), иначе ближайшая выше.
    /// nil — не осталось ничего.
    static func goldenRarity(_ v: Int, left: Set<Rarity>) -> Rarity? {
        var acc = 0
        var rolled = Rarity.legendary
        for r in goldenTiers {
            acc += goldenOdds[r] ?? 0
            if v < acc { rolled = r; break }
        }
        if left.contains(rolled) { return rolled }
        if let down = goldenTiers.reversed().first(where: { $0 < rolled && left.contains($0) }) { return down }
        return goldenTiers.first { $0 > rolled && left.contains($0) }
    }

    /// Что показать на карточке шарика: можно ли (есть что дать) и хватает ли клочков.
    static func goldenOpen(_ f: SaveFile, _ cfg: CapsuleConfig = EconomyConfig.shared.capsule) -> Bool {
        !goldenLeft(f, cfg).isEmpty
    }

    /// Крутка золотого шарика без диска. Ничего не осталось — отказ без списания.
    /// Бросок детерминированный: ключ — сколько редких и выше уже есть (после каждой крутки он другой).
    /// Ответ — та же CapsulePull, что у обычной крутки: экран автомата показывает его той же анимацией.
    /// paid .coins и price 50 — только для вида (экран их не печатает), гарант и счёт круток не двигаются.
    static func golden(_ f: inout SaveFile, now: Double, _ cfg: EconomyConfig = .shared) -> Result<CapsulePull, SinkRefusal> {
        let left = goldenLeft(f, cfg.capsule)
        guard !left.isEmpty else { return .failure(.allOwned) }
        guard Shards.spend(&f, goldenPrice) else { return .failure(.notEnough(need: goldenPrice - f.econ.wallet.shards)) }
        let owned = goldenTiers.flatMap { cfg.capsule.pools[$0] ?? [] }.filter { f.econ.items[$0.id] != nil }.count
        let u = StableRandom.mix(StableHash.fnv1a("\(f.petId):golden:\(owned)"))
        guard let rarity = goldenRarity(Int(u % 100), left: Set(left.keys)), let list = left[rarity] else {
            return .failure(.allOwned)   // не бывает: left не пуст
        }
        let it = list[Int((u / 100) % UInt64(list.count))]
        f.econ.items[it.id] = 1
        f.log("golden", t: now, key: it.id, value: goldenPrice)
        return .success(CapsulePull(index: f.econ.capsule.pulls, item: it, rarity: rarity, forced: false,
                                    duplicate: false, shards: 0, paid: .coins, price: goldenPrice,
                                    pityProgress: CapsuleMachine.pityProgress(f.econ.capsule, cfg)))
    }

    /// Через стор: одна запись под замком.
    static func performGolden(store: PetStore = .shared, now: Double = Clock.now()) throws -> Result<CapsulePull, SinkRefusal> {
        try store.mutate { f in golden(&f, now: now) }
    }

    // MARK: эксклюзив места

    /// Сколько находок места нужно для эксклюзива: половина (6 → 3).
    static func findsNeeded(_ p: Place) -> Int { (p.finds.count + 1) / 2 }

    /// Состояние кнопки на карточке места. nil — у места нет эксклюзива.
    static func placeState(_ f: SaveFile, _ p: Place) -> PlaceExclusiveState? {
        guard let ex = exclusive(p.id) else { return nil }
        if f.econ.items[ex.id] != nil { return .owned }
        let left = findsNeeded(p) - Places.have(f, p)
        if left > 0 { return .locked(left: left) }
        return .buy(price: placePrice, canAfford: Shards.canAfford(f, placePrice))
    }

    /// Купить эксклюзив места. В журнал — sinks.place (key — id вещи, value — цена).
    static func buyPlace(_ placeId: String, in f: inout SaveFile, now: Double,
                         _ cfg: PlacesConfig = .shared) -> Result<CapsuleItem, SinkRefusal> {
        guard let p = cfg.place(placeId), let ex = exclusive(p.id) else { return .failure(.unknown) }
        if f.econ.items[ex.id] != nil { return .failure(.owned) }
        let left = findsNeeded(p) - Places.have(f, p)
        guard left <= 0 else { return .failure(.fewFinds(left: left)) }
        guard Shards.spend(&f, placePrice) else { return .failure(.notEnough(need: placePrice - f.econ.wallet.shards)) }
        f.econ.items[ex.id] = 1
        f.log("sinks.place", t: now, key: ex.id, value: placePrice)
        return .success(ex.item)
    }

    static func performPlace(_ placeId: String, store: PetStore = .shared,
                             now: Double = Clock.now()) throws -> Result<CapsuleItem, SinkRefusal> {
        try store.mutate { f in buyPlace(placeId, in: &f, now: now) }
    }

    // MARK: тексты

    static func refusalText(_ r: SinkRefusal) -> String {
        switch r {
        case .notEnough(let need): return "Не хватает клочков: \(need) ✂️"
        case .allOwned: return "Редкие вещи из автомата уже все у тебя"
        case .owned: return "Это уже есть в коллекции"
        case .fewFinds(let left): return "Найди здесь ещё \(findsWord(left))"
        case .unknown: return "Здесь такого нет"
        }
    }

    /// «1 находку», «2 находки», «5 находок».
    static func findsWord(_ n: Int) -> String {
        "\(n) \(EconText.plural(n, "находку", "находки", "находок"))"
    }

    /// Подпись карточки золотого шарика.
    static func goldenNote(_ f: SaveFile) -> String {
        goldenOpen(f) ? "Только редкое и выше, без повторов" : "Все редкие вещи уже у тебя"
    }

    /// Надпись на кнопке эксклюзива места (без эмодзи: значок вещи кнопка рисует сама).
    static func placeButton(_ s: PlaceExclusiveState, _ it: SinkItem) -> String {
        switch s {
        case .owned: return "\(it.name) — уже у тебя"
        case .locked: return "\(it.name) · \(placePrice) ✂️"
        case .buy(let price, _): return "\(it.name) · \(price) ✂️"
        }
    }

    /// Строка под кнопкой.
    static func placeNote(_ s: PlaceExclusiveState, have shards: Int) -> String {
        switch s {
        case .owned: return "Вещь этого места уже в коллекции."
        case .locked(let left): return "Вещь этого места. Продадут, когда найдёшь здесь ещё \(findsWord(left))."
        case .buy(let price, let can):
            return can ? "Вещь этого места, такой больше нигде нет. У тебя \(shards) ✂️."
                       : "Вещь этого места. Не хватает \(price - shards) ✂️."
        }
    }
}
