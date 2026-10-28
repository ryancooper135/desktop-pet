// Волна 11: роль каждого предмета из капсулы. Надевается (Wear), встаёт на полку в комнате (decor)
// или идёт в «Поиграть» вместо обычного мячика (toys). Здесь же эмодзи — запасная картинка, если своей
// иконки (ItemArt) у предмета нет. Логика без SwiftUI/RealityKit: полку и мячик строит app/App/RoomDecor.swift.

import Foundation

enum ItemRole: String, Hashable, Sendable {
    case wear, decor, toy

    /// Подпись в коллекции и лавке.
    var title: String {
        switch self {
        case .wear: return "надеть"
        case .decor: return "на полку"
        case .toy: return "игрушка"
        }
    }
}

/// Узор мячика: по нему сцена добавляет детали второго цвета.
enum ToyPattern: String, Hashable, Sendable {
    /// Теннисный: изогнутый шов-обруч.
    case seam
    /// Тыква: дольки и черенок сверху.
    case pumpkin
    /// Звёздочки по кругу.
    case stars
    /// Квадратики-пиксели (волна 35 L, мячик из аркады).
    case pixel
}

struct ToyInfo: Hashable, Sendable {
    let color: UInt32
    let accent: UInt32
    let pattern: ToyPattern
}

enum ItemCatalog {
    /// На полку: прежняя «мебель» из капсулы (миниатюрой) и мелочи волны 11.
    static let decor: Set<String> = Set<String>([
        "bowl_plain", "mat_check", "lamp_mushroom", "sofa_mini", "kennel_castle",
        "pumpkin_small", "acorn_jar", "trophy_cup",
        // волна 32: лоскутные, только за клочки ✂️
        "pillow_patch", "armchair_patch",
    ]).union(ScrapSinks.decor).union(Seasons.decor)   // волна 35 L: вещи мест, 40 F: сезонные

    /// Мячики для «Поиграть».
    static let toys: [String: ToyInfo] = [
        "ball_tennis": ToyInfo(color: 0xD7E84A, accent: 0xF6F2E6, pattern: .seam),
        "ball_pumpkin": ToyInfo(color: 0xF08A2A, accent: 0x5E8C3A, pattern: .pumpkin),
        "ball_star": ToyInfo(color: 0x3D6FD1, accent: 0xF2C14E, pattern: .stars),
    ].merging(ScrapSinks.toys) { a, _ in a }

    /// Запасная картинка, если у предмета нет своей иконки. Незнакомый id — коробочка.
    static let emoji: [String: String] = [
        "bandana_red": "🧣", "bow_blue": "🎀", "leaf_hat": "🍃", "bowl_plain": "🥣", "mat_check": "🟫",
        "bell_collar": "🔔", "pumpkin_small": "🎃", "ball_tennis": "🎾",
        "scarf_knit": "🧣", "collar_star": "⭐", "lamp_mushroom": "🍄", "raincoat": "🧥",
        "beret_red": "🎨", "bowtie_dots": "🎀", "acorn_jar": "🫙", "ball_pumpkin": "🎃",
        "hoodie_pumpkin": "🎃", "sofa_mini": "🛋", "backpack_mini": "🎒", "wreath_autumn": "🍂",
        "trophy_cup": "🏆", "ball_star": "⭐",
        "cape_champion": "🦸", "kennel_castle": "🏰", "crown_champion": "👑",
        "scarf_patch": "🧶", "hat_patch": "🧢", "blanket_patch": "🧵", "pillow_patch": "🛏", "armchair_patch": "🪑",
    ].merging(ScrapSinks.emoji) { a, _ in a }.merging(Seasons.emoji) { a, _ in a }

    static func emoji(_ id: String) -> String { emoji[id] ?? "📦" }

    static func role(_ id: String) -> ItemRole? {
        if Wear.canWear(id) { return .wear }
        if decor.contains(id) { return .decor }
        if toys[id] != nil { return .toy }
        return nil
    }

    // MARK: полка и игрушка

    enum Refusal: Error, Hashable, Sendable {
        case notOwned
        /// Не та роль: шапку на полку не ставят.
        case wrongRole
    }

    /// Что на полке: только своё и подходящее. Мусор в файле молча не показываем, файл не трогаем.
    static func shelf(_ f: SaveFile) -> String? {
        guard let id = f.shelf, decor.contains(id), f.econ.items[id] != nil else { return nil }
        return id
    }

    /// Чем играем: nil — обычный мячик.
    static func toy(_ f: SaveFile) -> String? {
        guard let id = f.toy, toys[id] != nil, f.econ.items[id] != nil else { return nil }
        return id
    }

    /// Кнопка «На полку / Убрать»: стоящее убирает, иначе ставит (прежнее уходит в коллекцию).
    /// true — теперь на полке, false — убрали.
    static func toggleShelf(_ f: inout SaveFile, _ id: String) -> Result<Bool, Refusal> {
        guard decor.contains(id) else { return .failure(.wrongRole) }
        guard f.econ.items[id] != nil else { return .failure(.notOwned) }
        if shelf(f) == id {
            f.shelf = nil
            return .success(false)
        }
        f.shelf = id
        return .success(true)
    }

    /// Кнопка «Играть этим / Обычный мячик».
    static func toggleToy(_ f: inout SaveFile, _ id: String) -> Result<Bool, Refusal> {
        guard toys[id] != nil else { return .failure(.wrongRole) }
        guard f.econ.items[id] != nil else { return .failure(.notOwned) }
        if toy(f) == id {
            f.toy = nil
            return .success(false)
        }
        f.toy = id
        return .success(true)
    }

    /// То же через стор: одна запись под замком.
    static func performShelf(_ id: String, store: PetStore = .shared) throws -> Result<Bool, Refusal> {
        try store.mutate { f in toggleShelf(&f, id) }
    }

    static func performToy(_ id: String, store: PetStore = .shared) throws -> Result<Bool, Refusal> {
        try store.mutate { f in toggleToy(&f, id) }
    }
}
