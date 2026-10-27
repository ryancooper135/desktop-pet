// Волна 34 G: тексты экрана «Двор» и бейдж кнопки «Двор» — чистые функции над Yard и сейвом.
// Экран (App/YardScreen.swift) только рисует: что написать на свинке, карточке плиты, станции и кнопке яруса — здесь,
// чтобы проверялось тестами (YardTextTests). Денег нет: всё в монетах 🪙 из игры.

import Foundation
@preconcurrency import PetCore

enum YardText {
    // MARK: ставки и копилка

    /// «+14/ч» — табличка над станцией и строка карточки.
    static func perHour(_ rate: Double) -> String { "+\(Int(rate.rounded()))/ч" }

    /// Подпись под свинкой: «полная в 21:10», «полная — собери» или подсказка, что копить пока нечему.
    static func bank(fill: Double, fullAt: Double?, clock: (Double) -> String = Clock.hm) -> String {
        guard let fullAt else { return "Поставь станцию — и копилка пойдёт" }
        if fill >= 1 - 1e-9 { return "Полная — собери" }
        return "полная в \(clock(fullAt))"
    }

    /// «1 сбор», «2 сбора», «5 сборов».
    static func collects(_ n: Int) -> String { "\(n) \(EconText.plural(n, "сбор", "сбора", "сборов"))" }

    /// Полоска под ценой: «ещё 340 🪙 · ≈ 1 сбор». Хватает — «Хватает, бери».
    static func more(price: Int, coins: Int, rate: Double, _ cfg: YardConfig = .shared) -> String {
        let need = price - coins
        guard need > 0 else { return "Хватает, бери" }
        guard let k = Yard.collectsToAfford(price, coins: coins, rate: rate, cfg) else { return "ещё \(need) 🪙" }
        return "ещё \(need) 🪙 · ≈ \(collects(k))"
    }

    /// Доля накопленного к цене 0…1 — для полоски.
    static func progress(price: Int, coins: Int) -> Double {
        price > 0 ? min(1, max(0, Double(coins) / Double(price))) : 1
    }

    /// «окупится за ≈ 3 дн.»; меньше суток — «окупится меньше чем за день».
    static func payback(_ days: Double?) -> String? {
        guard let days, days > 0 else { return nil }
        if days < 1 { return "окупится меньше чем за день" }
        return "окупится за ≈ \(Int(days.rounded(.up))) дн."
    }

    // MARK: замки

    /// Почему плиту не купить — коротко, для кнопки.
    static func lock(_ l: YardLock, _ cfg: YardConfig = .shared) -> String {
        switch l {
        case .tier(let n): return "Откроется в ярусе «\(tierName(n, cfg))»"
        case .level(let need): return "Нужен ур. \(need) пса"
        case .kitchen(let k): return "Нужна кухня: «\(kitchenName(k))»"
        case .order(let id): return "Сначала — «\(cfg.plate(id)?.name ?? id)»"
        }
    }

    /// Отказ на нажатие без монет: кнопка не тускнеет, а объясняет.
    static func noCoins(_ need: Int) -> String { "Не хватает \(need) 🪙 — собери копилку" }

    // MARK: ярус

    /// Кнопка следующего яруса: заголовок и почему закрыта (nil — открыта, платится монетами).
    struct TierButton: Hashable, Sendable {
        let title: String
        let reason: String?
        let price: Int?
        var isOpen: Bool { reason == nil && price != nil }
    }

    static func tierButton(_ gate: YardTierGate, _ cfg: YardConfig = .shared) -> TierButton {
        switch gate {
        case .open(let n, let price):
            return TierButton(title: "Открыть ярус «\(tierName(n, cfg))»", reason: nil, price: price)
        case .level(let n, let need):
            return TierButton(title: "Ярус «\(tierName(n, cfg))»", reason: "нужен ур. \(need) пса", price: nil)
        case .plates(let n, let left):
            return TierButton(title: "Ярус «\(tierName(n, cfg))»",
                              reason: "купи все плиты яруса — осталось \(left.count)", price: nil)
        case .maxed:
            return TierButton(title: "Все ярусы открыты", reason: nil, price: nil)
        }
    }

    // MARK: сбор

    /// Тост после сбора: монеты, чаевые и порции в кладовую.
    static func harvest(_ h: YardHarvest, _ cfg: YardConfig = .shared) -> String {
        guard !h.isEmpty else { return "Пока пусто — станции ещё копят" }
        var parts: [String] = []
        if h.coins > 0 { parts.append("+\(h.coins) 🪙") }
        switch h.tip {
        case .bonus: parts.append("чаевые +\(h.bonus)")
        case .ticket: parts.append("билетик 🎟")
        case .ingredient: parts.append("соседи принесли продуктов")
        case .none: break
        }
        let food = h.portions.keys.sorted().compactMap { id -> String? in
            guard let n = h.portions[id], n > 0 else { return nil }
            let name = cfg.station(id)?.portionName ?? id
            return n > 1 ? "\(name) ×\(n)" : name
        }
        if !food.isEmpty { parts.append("в кладовую: " + food.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    // MARK: что дальше и бейдж

    /// Плита для карточки «следующая»: первая некупленная на открытых ярусах, кроме ждущих кухню
    /// (котелок не держит двор — как и в Yard.nextTier). nil — на открытых ярусах всё куплено.
    static func focusPlate(_ s: YardState, yardLevel: Int, dogLevel: Int, kitchenLevel: Int,
                           _ cfg: YardConfig = .shared) -> YardPlate? {
        let open = cfg.plates.filter { $0.tier <= yardLevel && !s.owns($0.id) }
        let ready = open.first {
            if case .kitchen = Yard.lock($0.id, s, yardLevel: yardLevel, dogLevel: dogLevel, kitchenLevel: kitchenLevel, cfg) {
                return false
            }
            return true
        }
        return ready ?? open.first
    }

    /// Бейдж на кнопке «Двор»: копилка полная или следующую плиту можно купить прямо сейчас.
    static func badge(_ f: SaveFile, now: Double, dogLevel: Int, _ cfg: YardConfig = .shared) -> Bool {
        if !f.yard.stations.isEmpty && Yard.fill(f, now: now, dogLevel: dogLevel, cfg) >= 1 - 1e-9 { return true }
        let yl = HomeShop.level(f, .yard), kl = HomeShop.level(f, .kitchen)
        guard let p = focusPlate(f.yard, yardLevel: yl, dogLevel: dogLevel, kitchenLevel: kl, cfg) else { return false }
        return Yard.lock(p.id, f.yard, yardLevel: yl, dogLevel: dogLevel, kitchenLevel: kl, cfg) == nil
            && f.econ.wallet.coins >= p.price
    }

    // MARK: переезд (волна 36 P)

    /// «1,5», «2», «2,5» — множитель славы по-русски.
    static func times(_ x: Double) -> String {
        let r = (x * 10).rounded() / 10
        let s = r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r).replacingOccurrences(of: ".", with: ",")
        return "×" + s
    }

    /// Район двора по номеру (Yard.district): улица, зимний квартал, у реки, на крыше. Те же имена, что у 3D-района.
    static func districtName(_ d: Int) -> String { YardDistrict(index: d).title }

    /// Звёзды славы на вывеске: «★★»; без переездов — пусто.
    static func gloryStars(moves: Int, _ cfg: YardConfig = .shared) -> String {
        String(repeating: "★", count: Yard.gloryStars(moves: moves, cfg))
    }

    /// Звёзды для VoiceOver: «Слава двора ×1,5».
    static func gloryLabel(moves: Int, _ cfg: YardConfig = .shared) -> String {
        "Слава двора \(times(Yard.glory(moves: moves, cfg)))"
    }

    /// Тихая карточка внизу экрана: заголовок и одна строка.
    static let moveTitle = "Переезд двора"
    static func moveLine(moves: Int, _ cfg: YardConfig = .shared) -> String {
        "Двор достроен. Новый район — «\(districtName(Yard.district(moves: moves + 1)))», "
            + "слава \(times(Yard.glory(moves: moves + 1, cfg)))"
    }

    /// Подтверждение: что останется, что начнётся заново, какая слава будет.
    static func moveConfirm(moves: Int, _ cfg: YardConfig = .shared) -> [String] {
        let keep = cfg.moveKeepCoins
        return [
            "Останется: Шиба, его уровень и рост, вещи, дом, ✂️, альбом, \(keep) 🪙",
            "Начнётся заново: плиты, станции, копилка, монеты сверх \(keep)",
            "Слава двора \(times(Yard.glory(moves: moves + 1, cfg))) к доходу станций навсегда",
        ]
    }

    /// Тост после переезда.
    static func moved(moves: Int, _ cfg: YardConfig = .shared) -> String {
        "Переехали: «\(districtName(Yard.district(moves: moves)))» · слава \(times(Yard.glory(moves: moves, cfg)))"
    }

    /// Тусклая карточка до полного двора (волна 37 A): почему закрыт и сколько осталось. Одна-две короткие строки.
    /// «Откроется, когда двор достроен: ещё 5 покупок» + «Лунная мельница — с ур. 28 пса»
    /// или «На 257 100 🪙 · ≈ 12 сборов» / «На 3 000 🪙 — уже хватает».
    static func moveLocked(_ w: YardMoveWait, coins: Int, rate: Double, _ cfg: YardConfig = .shared) -> [String] {
        guard w.left > 0 else { return ["Двор достроен. Переезд — с ур. \(w.needLevel) пса"] }
        let buys = "\(w.left) \(EconText.plural(w.left, "покупка", "покупки", "покупок"))"
        let first = "Откроется, когда двор достроен: ещё \(buys)"
        if let p = w.plate, w.needLevel > 0 {
            return [first, "\(p.name) — с ур. \(p.level) пса"]
        }
        let money = "На \(coinsText(w.cost)) 🪙"
        guard let k = Yard.collectsToAfford(w.cost, coins: coins, rate: rate, cfg) else { return [first, money] }
        return [first, k == 0 ? "\(money) — уже хватает" : "\(money) · ≈ \(collects(k))"]
    }

    /// 257100 → «257 100» (неразрывные пробелы: число не рвётся по строкам).
    static func coinsText(_ n: Int) -> String {
        Postcards.grouped(n).replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// Отказ (кнопки нет, но на всякий случай — не немой).
    static func moveRefuse(_ r: YardMoveResult) -> String? {
        switch r {
        case .ok: return nil
        case .level(let need): return "Переезд — с ур. \(need) пса"
        case .notFull(let left): return "Сначала дострой двор — осталось \(left)"
        }
    }

    // MARK: имена

    static func tierName(_ n: Int, _ cfg: YardConfig = .shared) -> String {
        cfg.tiers.indices.contains(n) ? cfg.tiers[n].name : "ярус \(n)"
    }

    static func kitchenName(_ k: Int) -> String {
        let levels = HomeShop.line(.kitchen)?.levels ?? []
        return levels.indices.contains(k) ? levels[k].name : "ур. \(k)"
    }
}
