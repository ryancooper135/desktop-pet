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
                                      "blockduo", "brush", "habits", "kitchen", "characters", "yard",
                                      "map"]  // волна 34 H: карта мест

    /// open — что показано сейчас (имена как у хостов; открытка — "postcard").
    static func step(target host: String?, open: Set<String>) -> Step {
        guard let host, routes.contains(host) else { return .go }
        if open.isEmpty || open.isSubset(of: chain(host)) { return .go }
        return .closeFirst
    }

    /// Лист поверх листа (лавка в автомате, кухня в «Доме»): родитель сразу, ребёнок — через closeDelay. nil — одним шагом.
    static func followUp(_ host: String?) -> (parent: String, child: String)? {
        switch host {
        case "shop": return ("capsule", "shop")
        case "kitchen": return ("house", "kitchen")
        default: return nil
        }
    }

    /// Волна 30: второй шаг ещё уместен — открыт ровно родитель (ребёнок ещё нет, чужого ничего). Лист ребёнка висит внутри
    /// родителя: если родителя за 0.8 с закрыли, флаг ребёнка остался бы true без листа (anyCover держит подсказки,
    /// а лавка выскакивала при следующем открытии автомата).
    static func mayFollow(_ host: String?, open: Set<String>) -> Bool {
        guard let parent = followUp(host)?.parent else { return false }
        return open == [parent]
    }
}
