// Кухня шефа (волна 12): верхний уровень линии «Кухня» в Доме. Бафф уровня
// { food_price_x 0.9, cooking: true } ядро не читает — его применяет приложение, тут:
// • «Угостить»: еда из shop.food за монеты, кроме хрустиков (они бесплатно на «Покормить»).
//   Цена × food_price_x из mods ядра (любой уровень, где бафф задан), округление вниз — в пользу хозяина,
//   чтобы скидка была видна и на дешёвой морковке. Кормит само ядро (.feed): вкусы, запас, монеты за уход —
//   как у обычной кормёжки. Ядро отказало (моется, гуляет, откат) — монеты не списываются;
// • «Приготовить»: блюдо из запаса кухни (pet.pantry, тот же, что у автокормушки) и, для двух рецептов,
//   с вещью из капсул (тыковка, банка желудей — не тратятся). Блюдо кормит лучше обычной еды,
//   прибавка × вкус той еды, из которой оно (любит рагу — домашнее рагу на 25% сытнее);
// • первое блюдо местных суток приносит приятное: открывает скрытый любимый вкус (если ещё не открыт),
//   иначе bonus_coins монет — мимо потолка ухода: это награда за кухню, а не за уход;
// • откат между блюдами cooldown_min и не больше per_day блюд в сутки. Числа — в economy.json,
//   home_upgrades.kitchen.cooking; нет ключа — дефолт из CookConfig.
// Ядро не трогаем: шкалы правим сами (как Tricks с лаской), в журнал — «cook» (не act.*: монеты за уход
// и открытки по act.* не должны считать блюдо), реакция сцены — по f.lastAction с видом «cook».
// Отметки — верхним уровнем SaveFile (cooking), пустое не пишется, новому щенку переходит вместе с домом.
// Только Foundation и PetCore: гоняется на Linux (app/Package.swift).

import Foundation
@preconcurrency import PetCore

// MARK: - Настройки

/// Блюдо из листа «Кухня». gains — прибавка шкал, pantry — сколько запаса кухни уходит.
struct CookRecipe: Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var emoji: String
    var pantry: Double
    var gains: [Need: Double]
    /// Вкус какой еды у блюда (Tastes, категория food): от него множитель прибавки.
    var taste: String
    /// Нужна вещь из капсул (ItemCatalog, decor) — есть в коллекции, не тратится.
    var needsItem: String?
}

/// Еда на продажу в листе «Кухня»: id, имя, цена без скидки, редкость, сытость (для подписи).
struct FoodPrice: Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var price: Int
    var rarity: String
    var food: Int
}

struct CookConfig: Hashable, Sendable {
    var cooldownMin: Double = 180
    var perDay = 2
    var bonusCoins = 15
    var recipes: [CookRecipe] = CookConfig.defaultRecipes
    /// shop.food без главной еды и легендарного (золотую косточку — только из капсул и лавки, как раньше).
    var foods: [FoodPrice] = []

    static let shared = CookConfig(json: Catalog.economy() ?? .null)

    init() {}

    init(json e: JSONValue) {
        func int(_ v: JSONValue, _ d: Int) -> Int { v.double.map { Int($0) } ?? d }
        let c = e["home_upgrades"]["kitchen"]["cooking"]
        cooldownMin = max(0, c["cooldown_min"].double ?? cooldownMin)
        perDay = max(1, int(c["per_day"], perDay))
        bonusCoins = max(0, int(c["bonus_coins"], bonusCoins))
        let list = c["recipes"].array.compactMap(Self.recipe)
        if !list.isEmpty { recipes = list }
        foods = e["shop"]["food"].array.compactMap { it in
            guard let id = it["id"].string, id != Catalog.mainFood, let p = it["price"].double, p > 0 else { return nil }
            let r = it["rarity"].string ?? "common"
            guard r != "legendary" else { return nil }
            return FoodPrice(id: id, name: it["name"].string ?? Catalog.name(id), price: Int(p), rarity: r,
                             food: int(it["food"], 0))
        }
    }

    private static func recipe(_ j: JSONValue) -> CookRecipe? {
        guard let id = j["id"].string, let name = j["name"].string else { return nil }
        var gains: [Need: Double] = [:]
        for n in [Need.food, .fun, .love, .energy, .clean] { if let v = j[n.rawValue].double, v != 0 { gains[n] = v } }
        guard !gains.isEmpty else { return nil }
        return CookRecipe(id: id, name: name, emoji: j["emoji"].string ?? "🍽", pantry: max(0, j["pantry"].double ?? 0),
                          gains: gains, taste: j["taste"].string ?? Catalog.mainFood, needsItem: j["needs_item"].string)
    }

    /// Те же блюда, что в economy.json на 19.10: тесты и сборка без конфига не остаются без кухни.
    static let defaultRecipes: [CookRecipe] = [
        CookRecipe(id: "stew_home", name: "Домашнее рагу", emoji: "🍲", pantry: 20,
                   gains: [.food: 45, .fun: 6, .love: 4], taste: "stew", needsItem: nil),
        CookRecipe(id: "porridge", name: "Каша на молоке", emoji: "🥣", pantry: 15,
                   gains: [.food: 35, .fun: 4, .love: 6], taste: "milk", needsItem: nil),
        CookRecipe(id: "pumpkin_soup", name: "Тыквенный суп", emoji: "🎃", pantry: 25,
                   gains: [.food: 40, .fun: 10, .love: 6], taste: "carrot", needsItem: "pumpkin_small"),
        CookRecipe(id: "acorn_cookies", name: "Желудёвое печенье", emoji: "🍪", pantry: 20,
                   gains: [.food: 25, .fun: 15, .love: 10], taste: "cake", needsItem: "acorn_jar"),
    ]

    func recipe(_ id: String) -> CookRecipe? { recipes.first { $0.id == id } }
    func food(_ id: String) -> FoodPrice? { foods.first { $0.id == id } }
}

// MARK: - Отметки в сейве

/// Что готовили. day — местные сутки (DayKey), today — блюд сегодня, lastT — последнее блюдо,
/// total — сколько каждого всего (ключ — id рецепта), bonusDay — сутки, за которые бонус уже выдан.
struct CookLog: Codable, Hashable, Sendable {
    var day = 0
    var today = 0
    var lastT: Double = 0
    var total: [String: Int] = [:]
    var bonusDay = 0

    init() {}

    var isEmpty: Bool { day == 0 && today == 0 && lastT == 0 && total.isEmpty && bonusDay == 0 }

    enum CodingKeys: String, CodingKey { case day, today, lastT, total, bonusDay }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? c.decodeIfPresent(Int.self, forKey: .day)) ?? 0
        today = (try? c.decodeIfPresent(Int.self, forKey: .today)) ?? 0
        lastT = (try? c.decodeIfPresent(Double.self, forKey: .lastT)) ?? 0
        total = (try? c.decodeIfPresent([String: Int].self, forKey: .total)) ?? [:]
        bonusDay = (try? c.decodeIfPresent(Int.self, forKey: .bonusDay)) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if day != 0 { try c.encode(day, forKey: .day) }
        if today != 0 { try c.encode(today, forKey: .today) }
        if lastT != 0 { try c.encode(lastT, forKey: .lastT) }
        if !total.isEmpty { try c.encode(total, forKey: .total) }
        if bonusDay != 0 { try c.encode(bonusDay, forKey: .bonusDay) }
    }
}

// MARK: - Итоги

/// Итог «Приготовить». reason — почему нет (Cooking.reasons), gains — сколько прибавилось на самом деле.
struct CookOutcome: Hashable, Sendable {
    let recipe: String
    let ok: Bool
    let reason: String?
    let gains: [String: Int]
    /// Бонус первого блюда за сутки: монеты или открытый вкус (ключ «food.stew»).
    let coins: Int
    let openedTaste: String?
    /// Что сказать: фраза пса или причина отказа.
    let text: String
}

enum Cooking {
    /// Вид реакции сцены и f.lastAction: клипы еды, как у кормёжки (PetStance, Presenter.pose).
    static let reactKind = "cook"
    /// Ключи баффа кухни (home_upgrades.kitchen), их читает приложение, а не ядро.
    static let buffKey = "cooking"
    static let priceKey = "food_price_x"

    // MARK: бафф

    /// Множитель цены еды от дома (произведение по линиям, как mods ядра); 1 — скидки нет.
    static func priceX(_ pet: PetState) -> Double {
        if case .number(let n)? = PetEngine.mods(pet, Catalog.rules)[priceKey], n > 0 { return n }
        return 1
    }

    /// Готовить можно: у дома есть бафф cooking (сейчас — «Кухня шефа»).
    static func canCook(_ pet: PetState) -> Bool {
        if case .flag(true)? = PetEngine.mods(pet, Catalog.rules)[buffKey] { return true }
        return false
    }

    /// Вместимость запаса кухни (storage из mods); 0 — запаса нет.
    static func pantryCap(_ pet: PetState) -> Int {
        if case .number(let n)? = PetEngine.mods(pet, Catalog.rules)["storage"] { return Int(n) }
        return 0
    }

    /// Цена со скидкой: вниз до целого, не меньше 1 монеты. Без скидки — как есть.
    static func price(_ base: Int, x: Double) -> Int {
        guard x != 1 else { return max(0, base) }
        return max(1, Int((Double(base) * x).rounded(.down)))
    }

    /// «−10%» на ценнике; nil — скидки нет.
    static func discountText(_ x: Double) -> String? {
        let p = Int(((1 - x) * 100).rounded())
        return p > 0 ? "−\(p)%" : nil
    }

    // MARK: угостить

    enum BuyResult: Hashable, Sendable {
        case ok(price: Int, out: ActOutcome)
        case noCoins(need: Int)
        /// Ядро не дало покормить: моется, гуляет, откат… Монеты целы.
        case refused(reason: String?)
        case unknown
    }

    /// Купить еду и сразу дать. Монеты списываются, только если ядро покормило.
    static func buyFood(_ id: String, in f: inout SaveFile, now: Double, _ cfg: CookConfig = .shared) -> BuyResult {
        guard let food = cfg.food(id) else { return .unknown }
        PetRunner.catchUp(&f, now: now)
        let p = price(food.price, x: priceX(f.pet))
        guard Economy.canAfford(f, coins: p) else { return .noCoins(need: p - f.econ.wallet.coins) }
        let out = PetRunner.apply(.feed(id), source: .app, to: &f, now: now)
        guard out.ok else { return .refused(reason: out.reason) }
        Economy.spend(&f, coins: p)
        f.log("food.buy", t: now, key: id, value: p)
        return .ok(price: p, out: out)
    }

    static func buyText(_ r: BuyResult, name: String) -> String {
        switch r {
        case .ok(let p, _): return "Угостили: \(name) за \(EconText.coins(p))"
        case .noCoins(let need): return EconText.notEnough(need: need)
        case .refused(let reason): return RefuseText.text(reason)
        case .unknown: return RefuseText.text("unknown_item")
        }
    }

    // MARK: приготовить

    /// Почему блюдо сейчас нельзя: общие причины (пса нет, гуляет, моется, ночь), потом кухня и лимиты.
    enum State: Hashable, Sendable {
        case ready
        case blocked(String)
        /// Откат: можно снова в момент until.
        case cooldown(until: Double)
        case needsItem(String)
        /// Запаса мало: есть столько, нужно recipe.pantry.
        case lowPantry(have: Int)
    }

    static let reasons = (noKitchen: "no_kitchen", enough: "enough", cooldown: "cooldown", noItem: "no_item",
                          pantry: "pantry", night: "night")

    /// Блюд сегодня (с учётом смены суток — без записи).
    static func todayCount(_ f: SaveFile, now: Double) -> Int {
        DayKey.today(f.cooking.today, day: f.cooking.day, at: now)
    }

    /// Бонус первого блюда за эти сутки ещё не выдан.
    static func bonusLeft(_ f: SaveFile, now: Double) -> Bool { f.cooking.bonusDay < DayKey.of(now) }

    /// Общая причина для всех рецептов (без запаса и вещей). nil — кухня открыта.
    static func gate(_ f: SaveFile, now: Double, _ cfg: CookConfig = .shared) -> State? {
        let s = PetRunner.peek(f, at: now)
        if !s.alive { return .blocked("dead") }
        if s.outing != nil { return .blocked("away") }
        if s.bathUntil != nil { return .blocked("bathing") }
        // Ночью не готовим: пёс спит, а запах рагу в два часа ночи — так себе забота. Днём дрёму блюдо прерывает,
        // как обычная кормёжка.
        if PetEngine.petNight(now, Catalog.rules, PetRunner.owner(f, at: now)) { return .blocked(reasons.night) }
        if !canCook(s) { return .blocked(reasons.noKitchen) }
        if todayCount(f, now: now) >= cfg.perDay { return .blocked(reasons.enough) }
        // Метка из будущего (часы назад) — как будто готовили сейчас (PetRunner.settleFutureMarks).
        let until = min(f.cooking.lastT, now) + cfg.cooldownMin * 60
        if f.cooking.lastT > 0, now < until { return .cooldown(until: until) }
        return nil
    }

    static func state(_ r: CookRecipe, _ f: SaveFile, now: Double, _ cfg: CookConfig = .shared) -> State {
        if let g = gate(f, now: now, cfg) { return g }
        if let item = r.needsItem, f.econ.items[item] == nil { return .needsItem(item) }
        let have = PetRunner.peek(f, at: now).pantry
        if have + 0.001 < r.pantry { return .lowPantry(have: Int(have.rounded(.down))) }
        return .ready
    }

    /// Приготовить и дать блюдо. Пишет только в f: шкалы, запас кухни, отметки, журнал, бонус.
    @discardableResult
    static func cook(_ id: String, in f: inout SaveFile, now: Double, _ cfg: CookConfig = .shared) -> CookOutcome {
        let name = f.petName
        guard let r = cfg.recipe(id) else { return refusal(id, "unknown_item", cfg, name: name) }
        PetRunner.catchUp(&f, now: now)
        switch state(r, f, now: now, cfg) {
        case .ready: break
        case .blocked(let why): return refusal(id, why, cfg, name: name)
        case .cooldown: return refusal(id, reasons.cooldown, cfg, name: name)
        case .needsItem: return refusal(id, reasons.noItem, cfg, name: name)
        case .lowPantry: return refusal(id, reasons.pantry, cfg, name: name)
        }
        // Блюдо любимой еды сытнее, нелюбимой — скромнее (тот же множитель, что у кормёжки).
        let x = Tastes.reaction(.food, r.taste, in: f).needX
        var gains: [String: Int] = [:]
        for (n, v) in r.gains {
            let before = f.pet.needs[n] ?? 0
            let after = min(100, max(0, before + v * x))
            f.pet.needs[n] = after
            let d = Int((after - before).rounded())
            if d != 0 { gains[n.rawValue] = d }
        }
        f.pet.napUntil = nil
        f.pet.pantry = max(0, f.pet.pantry - r.pantry)

        let day = DayKey.of(now)
        if let d = DayKey.newer(than: f.cooking.day, at: now) {
            f.cooking.day = d
            f.cooking.today = 0
        }
        f.cooking.today += 1
        f.cooking.lastT = now
        let total = (f.cooking.total[id] ?? 0) + 1
        f.cooking.total[id] = total

        // Бонус первого блюда суток: сначала секрет (любимая еда), когда секретов нет — монеты.
        var coins = 0
        var opened: String?
        if f.cooking.bonusDay < day {
            f.cooking.bonusDay = day
            if let love = Tastes.hidden(petId: f.petId, .food, log: f.tastes).love,
               f.tastes.opened[Tastes.key(.food, love)] == nil {
                let k = Tastes.key(.food, love)
                f.tastes.seen[k] = nil
                f.tastes.opened[k] = TasteLog.Fact(r: Taste.love.rawValue, t: now)
                f.log("taste.open", t: now, key: k)
                opened = k
            } else if cfg.bonusCoins > 0 {
                coins = cfg.bonusCoins
                Economy.grant(&f, coins: coins)
                f.econ.lastEarn = Earning(id: "cook:\(Int(now))", kind: reactKind, coins: coins, capped: false, t: now)
            }
        }
        f.log(reactKind, t: now, source: .app, ok: true, key: id, value: coins > 0 ? coins : nil)
        f.lastAction = SaveFile.LastAction(kind: reactKind, source: .app, t: now, ok: true, reason: nil)
        if OwnerSleep.counts(.app) { OwnerSleep.note(&f.sleep, t: now, tzOffsetMin: f.owner.tzOffsetMin) }
        return CookOutcome(recipe: id, ok: true, reason: nil, gains: gains, coins: coins, openedTaste: opened,
                           text: PetNames.adapt(dishLine(id, n: total), name: f.petName))
    }

    private static func refusal(_ id: String, _ why: String, _ cfg: CookConfig, name: String) -> CookOutcome {
        CookOutcome(recipe: id, ok: false, reason: why, gains: [:], coins: 0, openedTaste: nil,
                    text: reasonText(why, cfg, name: name))
    }

    /// Стор не записался.
    static func failed(_ id: String) -> CookOutcome {
        CookOutcome(recipe: id, ok: false, reason: "store", gains: [:], coins: 0, openedTaste: nil,
                    text: RefuseText.text("store"))
    }

    // MARK: тексты

    /// Фраза после блюда. n — который раз это блюдо: по кругу, детерминированно (тесты, снимки).
    static func dishLine(_ id: String, n: Int) -> String {
        let list = lines[id] ?? ["Шиба уплетает за обе щеки — миска блестит!"]
        return list[(max(1, n) - 1) % list.count]
    }

    static let lines: [String: [String]] = [
        "stew_home": ["Шиба уплетает домашнее рагу — миска блестит!",
                      "Рагу как у бабушки! Шиба вылизал всё до капли"],
        "porridge": ["Каша на молоке! Шиба довольно облизывает усы",
                     "Тёплая каша — и Шиба жмурится от удовольствия"],
        "pumpkin_soup": ["Тыквенный суп! Шиба чавкает и виляет хвостом",
                         "Суп из тыковки — Шиба просит добавки"],
        "acorn_cookies": ["Желудёвое печенье! Шиба хрустит и сияет",
                          "Печенье из желудей — Шиба прыгает от радости"],
    ]

    /// name — кто в комнате (SaveFile.petName): «Ночью кухня закрыта: Мурка спит».
    static func reasonText(_ why: String?, _ cfg: CookConfig = .shared, name: String = PetNames.shiba) -> String {
        PetNames.adapt(shibaReasonText(why, cfg), name: name)
    }

    private static func shibaReasonText(_ why: String?, _ cfg: CookConfig) -> String {
        switch why {
        case reasons.noKitchen: return "Готовить можно на «Кухне шефа»"
        case reasons.enough:
            return "На сегодня наготовлено: \(cfg.perDay) \(dishes(cfg.perDay)) в день"
        case reasons.cooldown: return "Плита ещё горячая — чуть позже"
        case reasons.noItem: return "Для этого блюда нужна вещь из капсул"
        case reasons.pantry: return "Мало запаса на кухне — сначала покорми"
        case reasons.night: return "Ночью кухня закрыта: Шиба спит"
        default: return RefuseText.text(why)
        }
    }

    /// «блюдо», «2 блюда», «5 блюд».
    static func dishes(_ n: Int) -> String { EconText.plural(n, "блюдо", "блюда", "блюд") }

    /// «Через 2 ч 5 мин», «Через 12 мин».
    static func waitText(_ s: Double) -> String {
        let m = max(1, Int((s / 60).rounded(.up)))
        return m >= 60 ? "Через \(m / 60) ч \(m % 60) мин" : "Через \(m) мин"
    }

    /// Строка под рецептом: что нужно и почему нельзя.
    static func stateText(_ st: State, _ r: CookRecipe, now: Double, _ cfg: CookConfig = .shared,
                          name: String = PetNames.shiba) -> String? {
        switch st {
        case .ready: return nil
        case .blocked(let why): return reasonText(why, cfg, name: name)
        case .cooldown(let until): return "Плита остывает · \(waitText(until - now).lowercased())"
        case .needsItem(let item): return "Нужно: \(itemName(item)) из капсул"
        case .lowPantry(let have): return "Запас \(have) из \(Int(r.pantry)) — сначала покорми"
        }
    }

    /// Состав блюда: «Сытость +45 · Настроение +6 · Ласка +4».
    static func gainsText(_ r: CookRecipe) -> String {
        [Need.food, .fun, .love, .energy, .clean].compactMap { n in
            r.gains[n].map { "\(Catalog.needName(n)) +\(Int($0))" }
        }.joined(separator: " · ")
    }

    /// «Сегодня 1 из 2 · бонус дня ждёт первое блюдо».
    static func statusText(_ f: SaveFile, now: Double, _ cfg: CookConfig = .shared) -> String {
        let n = todayCount(f, now: now)
        let base = "Сегодня \(n) из \(cfg.perDay)"
        return bonusLeft(f, now: now) ? "\(base) · первое блюдо дня с подарком" : base
    }

    /// Ответ целиком для тоста: фраза пса и бонус.
    static func reply(_ o: CookOutcome) -> String {
        if o.coins > 0 { return "\(o.text) · +\(EconText.coins(o.coins))" }
        return o.text
    }

    static func itemName(_ id: String) -> String {
        EconomyConfig.shared.capsule.itemsById[id]?.name ?? id
    }
}
