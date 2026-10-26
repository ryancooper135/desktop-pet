// Экран «Дом» без SwiftUI: строки линий (уровень, что даёт следующий, цена), подписи кнопки и отказов, покупка через стор.
// Решения (Вадим может поменять): кнопка без монет не гаснет — пишет «Не хватает N», нажатие объясняет отказ;
// уровень без понятных ядру баффов (кухня «Холодильник») честно говорит «Бонусов пока нет».

import Foundation
@preconcurrency import PetCore

struct HomeRow: Equatable, Sendable {
    struct Next: Equatable, Sendable {
        let index: Int
        let name: String
        let price: Int
        let perks: [String]
        /// Сколько монет не хватает; 0 — хватает.
        let need: Int
        /// Что держит кроме монет (уровень пса, плиты двора); nil — только монеты.
        var gate: HomeShop.Gate? = nil
    }

    let id: HomeLine
    let name: String
    /// Текущий уровень: 0 — стартовый бесплатный.
    let level: Int
    /// Последний уровень линии (3, у двора 4 — «Квартал»).
    let top: Int
    let levelName: String
    /// Что даёт текущий уровень.
    let perks: [String]
    /// nil — линия на максимуме.
    let next: Next?

    var maxed: Bool { next == nil }
    var canBuy: Bool { next.map { $0.need == 0 && $0.gate == nil } ?? false }
}

enum HomeOffer {
    static let noPerks = "Бонусов пока нет"
    static let maxedText = "Это уже лучший уровень"

    /// Строки всех линий в порядке HomeLine.
    static func rows(_ f: SaveFile, _ all: [HomeShop.Line] = HomeShop.shared) -> [HomeRow] {
        let coins = f.econ.wallet.coins
        return all.map { l in
            let i = min(HomeShop.level(f, l.id), l.levels.count - 1)
            let next = HomeShop.next(f, l.id, all).map { n in
                HomeRow.Next(index: n.index, name: n.level.name, price: n.level.price,
                             perks: perkLines(n.level.buff), need: max(0, n.level.price - coins),
                             gate: HomeShop.gate(f, l.id, all))
            }
            return HomeRow(id: l.id, name: l.name, level: i, top: l.levels.count - 1,
                           levelName: l.levels[i].name, perks: HomeShop.perks(l.levels[i].buff), next: next)
        }
    }

    /// Тексты баффа для «Дальше»: пусто — одна строка «Бонусов пока нет».
    static func perkLines(_ buff: [String: JSONValue]) -> [String] {
        let p = HomeShop.perks(buff)
        return p.isEmpty ? [noPerks] : p
    }

    /// Подпись на кнопке: «Купить», «Не хватает 120», «Нужен ур. 5 пса», «Сначала плиты», «Лучший уровень».
    static func buttonTitle(_ r: HomeRow) -> String {
        guard let n = r.next else { return "Лучший уровень" }
        if let g = n.gate { return gateTitle(g) }
        return n.need > 0 ? "Не хватает \(n.need)" : "Купить"
    }

    /// Короткая причина на кнопке и в карточке.
    static func gateTitle(_ g: HomeShop.Gate) -> String {
        switch g {
        case .level(let l): return "Нужен ур. \(l) пса"
        case .plates: return "Сначала плиты двора"
        }
    }

    /// Отказ после нажатия; nil — купили.
    static func refusal(_ r: HomeShop.BuyResult, lines: Lines = .shared) -> String? {
        switch r {
        case .ok: return nil
        case .noCoins(let need): return EconText.notEnough(need: need, lines: lines)
        case .maxed: return maxedText
        case .needLevel(let l): return "Пёс ещё мал: нужен ур. \(l)"
        case .needPlates(let k): return "Сначала купи все плиты яруса — осталось \(k)"
        case .unknown: return "Такого улучшения нет"
        }
    }

    /// «Готово: Ванна» после покупки.
    static func bought(_ r: HomeShop.BuyResult, line: HomeLine, _ all: [HomeShop.Line] = HomeShop.shared) -> String? {
        guard case .ok(let level, _) = r, let l = HomeShop.line(line, all), level < l.levels.count else { return nil }
        return "Готово: \(l.levels[level].name)"
    }

    /// Покупка через стор: одна запись под замком.
    static func perform(_ id: HomeLine, store: PetStore = .shared, now: Double = Clock.now()) throws -> HomeShop.BuyResult {
        try store.mutate { f in HomeShop.buy(id, in: &f, now: now) }
    }
}
