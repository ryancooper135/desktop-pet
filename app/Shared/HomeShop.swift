// Улучшения дома за монеты: ванная, лежанка, кухня, будка, игровой уголок, дворик (economy.json home_upgrades).
// Уровень линии живёт в PetState.home — его читает ядро (баффы), а дом переживает щенка (death.keep "house").
// Покупка: догнать питомца по старым баффам, списать монеты, поднять уровень, записать home.buy в журнал.

import Foundation
@preconcurrency import PetCore

enum HomeShop {
    struct Level: Equatable, @unchecked Sendable {   // JSONValue не Hashable и не Sendable, но неизменяем
        let name: String
        let price: Int
        let buff: [String: JSONValue]
    }

    struct Line: Equatable, @unchecked Sendable {
        let id: HomeLine
        let name: String
        let levels: [Level]   // [0] — стартовый бесплатный
    }

    enum BuyResult: Equatable, Sendable {
        case ok(level: Int, price: Int)
        case maxed
        case noCoins(need: Int)
        case unknown
    }

    static let shared: [Line] = lines(Catalog.economy() ?? .null)

    /// Линии в порядке HomeLine; линия без уровней в конфиге пропускается.
    static func lines(_ e: JSONValue) -> [Line] {
        let h = e["home_upgrades"]
        return HomeLine.allCases.compactMap { id in
            let l = h[id.rawValue]
            let levels = l["levels"].array.map { v in
                Level(name: v["name"].string ?? "", price: Int(v["price"].double ?? 0), buff: v["buff"].object)
            }
            guard !levels.isEmpty else { return nil }
            return Line(id: id, name: l["name"].string ?? id.rawValue, levels: levels)
        }
    }

    static func line(_ id: HomeLine, _ all: [Line] = shared) -> Line? { all.first { $0.id == id } }

    static func level(_ f: SaveFile, _ id: HomeLine) -> Int { max(0, f.pet.home[id] ?? 0) }

    /// Следующий уровень и его индекс; nil — линия на максимуме.
    static func next(_ f: SaveFile, _ id: HomeLine, _ all: [Line] = shared) -> (index: Int, level: Level)? {
        guard let l = line(id, all) else { return nil }
        let i = level(f, id) + 1
        return i < l.levels.count ? (i, l.levels[i]) : nil
    }

    /// Купить следующий уровень линии. Не хватает монет или максимум — ничего не меняет.
    @discardableResult
    static func buy(_ id: HomeLine, in f: inout SaveFile, now: Double, _ all: [Line] = shared) -> BuyResult {
        guard line(id, all) != nil else { return .unknown }
        // Время до покупки — по старым баффам: иначе новая лежанка задним числом «досыпала» бы за прошлое.
        PetRunner.catchUp(&f, now: now)
        guard let n = next(f, id, all) else { return .maxed }
        guard Economy.spend(&f, coins: n.level.price) else { return .noCoins(need: n.level.price - f.econ.wallet.coins) }
        f.pet.home[id] = n.index
        f.log("home.buy", t: now, key: id.rawValue, value: n.index)
        return .ok(level: n.index, price: n.level.price)
    }

    // MARK: тексты

    /// Что даёт уровень — по-русски, только то, что ядро уже умеет. Остальные ключи молчат, чтобы не обещать лишнего.
    static func perks(_ buff: [String: JSONValue]) -> [String] {
        func pct(_ x: Double) -> Int { Int((abs(1 - x) * 100).rounded()) }
        var out: [String] = []
        for k in perkOrder {
            // готовка — флаг, не число (читает приложение, Cooking.swift)
            if k == Cooking.buffKey {
                if buff[k]?.bool == true { out.append("Готовка: блюда сытнее еды, первое за день — с подарком") }
                continue
            }
            guard let v = buff[k]?.double else { continue }
            switch k {
            case "bath_min": out.append("Мытьё \(Int(v)) мин")
            case "clean_decay_x": out.append("Пачкается на \(pct(v))% медленнее")
            case "fun_after_bath": out.append("После ванны +\(Int(v)) настроения")
            case "look_after_bath": out.append("После ванны +\(Int(v)) к блеску шерсти")
            case "sleep_regen_x": out.append("Высыпается на \(pct(v))% быстрее")
            case "night_food_decay_x": out.append("Ночью голодает на \(pct(v))% медленнее")
            case "love_on_wake": out.append("Утром +\(Int(v)) ласки")
            // запас нужен только автокормушке: без неё ядро его не тратит
            case "storage": if buff["autofeed_below"] != nil { out.append("Запас еды: \(Int(v))") }
            case "autofeed_below": out.append("Сам ест из запаса, когда сытость ниже \(Int(v))")
            case "heart_damage_x": out.append("Сердечки тают на \(pct(v))% медленнее")
            case "heart_regen_x": out.append("Сердечки растут на \(pct(v))% быстрее")
            case "max_hearts": out.append("Сердечек до \(Int(v))")
            case "fun_decay_x": out.append("Скучает на \(pct(v))% медленнее")
            case "walk_decay_x": out.append("Просится гулять на \(pct(v))% реже")
            // бафф читает приложение (CatchGame.coinsX), не ядро
            case CatchGame.buffKey: out.append("Монет за «Лови мячик» на \(pct(v))% больше")
            // скидку применяет приложение при покупке еды на кухне (Cooking.price)
            case Cooking.priceKey: out.append("Еда в «Угостить» на \(pct(v))% дешевле")
            default: break
            }
        }
        return out
    }

    /// Ключи, которые ядро применяет (core/README), и баффы из приложения («Лови мячик», кухня шефа) — в порядке показа.
    static let perkOrder = [
        "bath_min", "clean_decay_x", "fun_after_bath", "look_after_bath",
        "sleep_regen_x", "night_food_decay_x", "love_on_wake",
        "storage", "autofeed_below", Cooking.priceKey, Cooking.buffKey,
        "heart_damage_x", "heart_regen_x", "max_hearts",
        "fun_decay_x", "walk_decay_x",
        CatchGame.buffKey,
    ]
}
