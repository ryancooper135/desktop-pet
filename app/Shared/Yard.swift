// Волна 33 C: двор-тайкун — ярусы, плиты, станции, копилка на 12 ч. Пока заготовка (шаг 0).

import Foundation

/// Состояние в SaveFile. Пустое не пишется — старые сейвы читаются без этого поля.
struct YardState: Codable, Hashable, Sendable {
    var isEmpty: Bool { true }
}
