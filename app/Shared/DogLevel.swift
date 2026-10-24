// Волна 33 A: уровень пса — опыт по журналу, кривая, открытия по уровню. Пока заготовка (шаг 0).

import Foundation

/// Состояние в SaveFile. Пустое не пишется — старые сейвы читаются без этого поля.
struct DogLevelLog: Codable, Hashable, Sendable {
    var isEmpty: Bool { true }
}
