// Ссылки pet://… (виджет, остров, Spotlight) поверх уже открытого листа (волна 25, хвост волны 23).
// Все листы и обложки висят на HomeScreen: пока показан один, второй SwiftUI молча не покажет, а его флаг
// останется true — кнопка этого листа потом «мёртвая» (флаг не меняется, лист не едет). Поэтому: если открыто
// что-то не по пути к цели — сначала закрыть всё, через closeDelay открыть цель.

import Foundation

enum DeepLink {
    enum Step: Equatable, Sendable {
        /// Открыть сразу: ничего не открыто или открыто только то, что по пути к цели.
        case go
        /// Сначала закрыть всё, потом (через closeDelay) открыть цель.
        case closeFirst
    }

    /// Сколько ждать между «закрыть» и «открыть»: лист уезжает ~0.5 с (как у лавки поверх автомата).
    static let closeDelay: Double = 0.8

    /// Путь к цели: лавка — лист в автомате, кухня — в «Доме», персонажи — в стеке настроек.
    static func chain(_ host: String?) -> Set<String> {
        switch host {
        case "shop": return ["capsule", "shop"]
        case "kitchen": return ["house", "kitchen"]
        case "characters": return ["settings", "characters"]
        case let h?: return [h]
        case nil: return []
        }
    }

    /// Цели, которые что-то открывают. Остальное (pet://home и незнакомое) — «закрыть всё», это и так .go.
    static let routes: Set<String> = ["needs", "settings", "album", "capsule", "shop", "house", "tricks", "catch",
                                      "blockduo", "zombie", "brush", "habits", "kitchen", "characters"]

    /// open — что показано сейчас (имена как у хостов; открытка — "postcard").
    static func step(target host: String?, open: Set<String>) -> Step {
        guard let host, routes.contains(host) else { return .go }
        if open.isEmpty || open.isSubset(of: chain(host)) { return .go }
        return .closeFirst
    }
}
