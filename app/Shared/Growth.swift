// Волна 33 B: рост щенок → подросток → взрослый, очки за сутки ухода. Пока заготовка (шаг 0).

import Foundation

/// Состояние в SaveFile. Пустое не пишется — старые сейвы читаются без этого поля.
struct GrowthLog: Codable, Hashable, Sendable {
    var isEmpty: Bool { true }
}
