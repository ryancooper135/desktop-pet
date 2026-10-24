// Волна 33 D: карта необычных мест и походы поверх прогулки. Пока заготовка (шаг 0).

import Foundation

/// Состояние в SaveFile. Пустое не пишется — старые сейвы читаются без этого поля.
struct TripLog: Codable, Hashable, Sendable {
    var isEmpty: Bool { true }
}
