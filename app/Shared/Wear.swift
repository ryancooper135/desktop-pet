// «Надето»: предметы из капсулы на собаке. Три места — голова, шея, спина, по одному предмету на место.
// Здесь только логика и таблица (что куда и каким цветом); форма в 3D — app/App/PetWear.swift.
// Мебель и мелочи из капсулы не надеваются: они встают на полку или идут в игру (ItemCatalog).

import Foundation

// WearSlot и WearShape — в WearMesh.swift (рядом с геометрией).

/// Как предмет выглядит на собаке: место, фигура, основной цвет и второй (кант, звёздочка, черенок).
struct WearInfo: Hashable, Sendable {
    let slot: WearSlot
    let shape: WearShape
    let color: UInt32
    let accent: UInt32
}

enum Wear {
    /// Таблица надеваемого. Новые предметы пулов без строки здесь — не надеваются (это мебель или
    /// ещё не нарисовано); id из конфига с known-местом можно добавить сюда одной строкой.
    static let table: [String: WearInfo] = [
        "leaf_hat":       WearInfo(slot: .head, shape: .leafHat, color: 0x7DBB5A, accent: 0x8A5A3B),
        "bow_blue":       WearInfo(slot: .head, shape: .bow, color: 0x5B8FE0, accent: 0x3E6CB8),
        "bandana_red":    WearInfo(slot: .neck, shape: .bandana, color: 0xE2554B, accent: 0xF6E7D2),
        "collar_star":    WearInfo(slot: .neck, shape: .collar, color: 0x3D6FD1, accent: 0xF2C14E),
        "scarf_knit":     WearInfo(slot: .neck, shape: .scarf, color: 0xC9506A, accent: 0xF6E7D2),
        "raincoat":       WearInfo(slot: .back, shape: .genericBlanket, color: 0xF4C430, accent: 0xD9A21B),
        "hoodie_pumpkin": WearInfo(slot: .back, shape: .genericBlanket, color: 0xF08A2A, accent: 0x5E8C3A),
        "cape_champion":  WearInfo(slot: .back, shape: .cape, color: 0xC23B4A, accent: 0xF2B01E),
        // волна 11
        "bell_collar":    WearInfo(slot: .neck, shape: .bellCollar, color: 0xD24B45, accent: 0xF2C14E),
        "bowtie_dots":    WearInfo(slot: .neck, shape: .bowtie, color: 0x2F5FA8, accent: 0xF6E7D2),
        "beret_red":      WearInfo(slot: .head, shape: .beret, color: 0xC8323C, accent: 0x3A2A22),
        "wreath_autumn":  WearInfo(slot: .head, shape: .wreath, color: 0xE08A2E, accent: 0xB8322B),
        "crown_champion": WearInfo(slot: .head, shape: .crown, color: 0xF2B01E, accent: 0xC23B4A),
        "backpack_mini":  WearInfo(slot: .back, shape: .backpack, color: 0xC98A4B, accent: 0x6B4428),
        // волна 32: лоскутные, только за клочки ✂️
        "scarf_patch":    WearInfo(slot: .neck, shape: .scarf, color: 0x8E6BBF, accent: 0xF2C14E),
        "hat_patch":      WearInfo(slot: .head, shape: .genericHat, color: 0x4FA3A5, accent: 0xE2554B),
        "blanket_patch":  WearInfo(slot: .back, shape: .genericBlanket, color: 0x6E8B3D, accent: 0xE8B04A),
    ].merging(ScrapSinks.wear) { a, _ in a }   // волна 35 L: полотенце и дуршлаг (ScrapSinks)
        .merging(Seasons.wear) { a, _ in a }   // волна 40 F: сезонные шапка, венок, бандана, шарф

    static func info(_ id: String) -> WearInfo? { table[id] }
    static func canWear(_ id: String) -> Bool { table[id] != nil }

    /// Что надето сейчас: только своё и надеваемое на своём месте. Мусор в файле (предмета нет,
    /// место не то, незнакомый слот) молча не показываем, сам файл не трогаем.
    static func worn(_ f: SaveFile) -> [WearSlot: String] {
        var out: [WearSlot: String] = [:]
        for (k, id) in f.worn {
            guard let slot = WearSlot(rawValue: k), let inf = table[id], inf.slot == slot,
                  f.econ.items[id] != nil else { continue }
            out[slot] = id
        }
        return out
    }

    static func isWorn(_ f: SaveFile, _ id: String) -> Bool { worn(f).values.contains(id) }

    enum Refusal: Error, Hashable, Sendable {
        case notOwned
        case notWearable
    }

    enum Change: Hashable, Sendable {
        /// Надел; replaced — что сняли с того же места.
        case put(WearSlot, replaced: String?)
        case tookOff(WearSlot)
    }

    /// Надеть: с того же места снимается прежнее.
    static func put(_ f: inout SaveFile, _ id: String) -> Result<Change, Refusal> {
        guard let inf = table[id] else { return .failure(.notWearable) }
        guard f.econ.items[id] != nil else { return .failure(.notOwned) }
        let before = worn(f)[inf.slot]
        f.worn[inf.slot.rawValue] = id
        return .success(.put(inf.slot, replaced: before == id ? nil : before))
    }

    /// Снять. Не надето — ничего не меняется, nil.
    @discardableResult
    static func takeOff(_ f: inout SaveFile, _ id: String) -> WearSlot? {
        guard let slot = f.worn.first(where: { $0.value == id }).flatMap({ WearSlot(rawValue: $0.key) }) else {
            return nil
        }
        f.worn[slot.rawValue] = nil
        return slot
    }

    /// Кнопка «Надеть/Снять»: надетое снимает, иначе надевает.
    static func toggle(_ f: inout SaveFile, _ id: String) -> Result<Change, Refusal> {
        if isWorn(f, id), let slot = takeOff(&f, id) { return .success(.tookOff(slot)) }
        return put(&f, id)
    }

    /// То же через стор: одна запись под замком.
    static func perform(_ id: String, store: PetStore = .shared) throws -> Result<Change, Refusal> {
        try store.mutate { f in toggle(&f, id) }
    }
}
