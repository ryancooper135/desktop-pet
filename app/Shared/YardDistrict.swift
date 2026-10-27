// Волна 36 Q: районы двора (RESEARCH/20-tycoon-design.md §7 «Переезд двора»). После переезда двор строится заново
// в новом квартале: станции те же, а земля, плиты-дорожки, забор, небо и декор — свои. Здесь только данные
// (цвета hex и список декора), без RealityKit: геометрию по ним строит YardArtTier (app/App/YardModels.swift).
// Номер района даёт логика переезда (`Yard.district(moves:)`: 0 улица, 1 зима, 2 река, 3 крыша, дальше по кругу 1…3).

import Foundation

/// Цвета района (0xRRGGBB). У улицы — ровно те, что были у двора до волны 36 (YardArtColors).
struct YardDistrictPalette: Hashable, Sendable {
    /// Дворик перед домом (слой 1): земля, снег, песок, рубероид.
    var ground: UInt32
    /// Сад перед забором (слой 2).
    var garden: UInt32
    /// Парк слева (слой 3).
    var park: UInt32
    /// Квартал справа (слой 4).
    var paving: UInt32
    /// Плиты-дорожки.
    var tile: UInt32
    /// Забор починенный и старый.
    var fence: UInt32
    var fenceOld: UInt32
    /// Стена дома и крыша над окном.
    var wall: UInt32
    var houseRoof: UInt32
    /// Крона яблони, вода пруда, лужа пустыря.
    var crown: UInt32
    var water: UInt32
    var puddle: UInt32
    /// Фон за сценой днём и ночью.
    var sky: UInt32
    var skyNight: UInt32

    /// Все поверхности земли — по ним тест проверяет «никакой травы на крыше».
    var surfaces: [UInt32] { [ground, garden, park, paving] }
}

/// Что стоит в районе кроме станций и плит. Геометрия — YardArtTier.decor.
enum YardDistrictDecor: String, CaseIterable, Hashable, Sendable {
    // зима
    case snowdrifts, firTree, garland, snowCaps, snowfall
    // река
    case river, bridge, reeds, duck, lifebuoy
    // крыша
    case parapet, antennas, vents, waterTank, skyline
}

enum YardDistrict: String, CaseIterable, Hashable, Sendable {
    case street, winter, river, roof

    /// Номер района из логики переезда: 0 — улица, 1…3 — зима, река, крыша; дальше по кругу 1…3 (4 — снова зима).
    /// Отрицательный — улица.
    init(index: Int) {
        guard index > 0 else {
            self = .street
            return
        }
        switch (index - 1) % 3 {
        case 0: self = .winter
        case 1: self = .river
        default: self = .roof
        }
    }

    var index: Int {
        switch self {
        case .street: return 0
        case .winter: return 1
        case .river: return 2
        case .roof: return 3
        }
    }

    /// Куда едем дальше — следующий номер по кругу (с крыши — снова в зиму).
    var next: YardDistrict { YardDistrict(index: index + 1) }

    var title: String {
        switch self {
        case .street: return "Улица"
        case .winter: return "Зимний квартал"
        case .river: return "У реки"
        case .roof: return "На крыше"
        }
    }

    /// Подпись сцены переезда: «Переезжаем: Улица → Зимний квартал».
    static func moveCaption(from: YardDistrict, to: YardDistrict) -> String {
        "Переезжаем: \(from.title) → \(to.title)"
    }

    /// Район по строке: имя (winter) или номер (1). Для PET_YARD_DISTRICT в UI-тестах.
    static func parse(_ raw: String?) -> YardDistrict? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return nil }
        if let d = YardDistrict(rawValue: raw) { return d }
        if let n = Int(raw) { return YardDistrict(index: n) }
        return nil
    }

    func sky(night: Bool) -> UInt32 { night ? palette.skyNight : palette.sky }

    var palette: YardDistrictPalette {
        switch self {
        case .street:
            return YardDistrictPalette(ground: 0xa07850, garden: 0xa6d48f, park: 0x8cc77a, paving: 0xc9c4bc,
                                       tile: 0xd9cfc0, fence: 0xf6ead6, fenceOld: 0xb3a088, wall: 0xead0ae,
                                       houseRoof: 0xc8553d, crown: 0x5fa860, water: 0xa9d8f0, puddle: 0x8fa6ad,
                                       sky: 0xf6efe6, skyNight: 0x2a3350)
        case .winter:
            // Снег белый с синевой, дорожки расчищены до серо-синего камня, забор тёмного дерева — читается на снегу.
            return YardDistrictPalette(ground: 0xeef3f7, garden: 0xe3ebf2, park: 0xdbe5ee, paving: 0xb4c2cd,
                                       tile: 0x8399ab, fence: 0x8a5a3c, fenceOld: 0x6f6458, wall: 0xe8d4b8,
                                       houseRoof: 0x9a4a3a, crown: 0x3f7a5a, water: 0xcfe6f2, puddle: 0xc3d8e4,
                                       sky: 0xd9e4ee, skyNight: 0x1b2540)
        case .river:
            // Песчаный берег, сочная трава у воды, доски вместо брусчатки, голубая крыша дома.
            return YardDistrictPalette(ground: 0xdcc58e, garden: 0x76c27f, park: 0x68b276, paving: 0xb48c62,
                                       tile: 0xf0e6cc, fence: 0xc9a27e, fenceOld: 0x8f8574, wall: 0xdde8e4,
                                       houseRoof: 0x4f7ea8, crown: 0x4e9a5a, water: 0x5fb0d8, puddle: 0x7fbfdc,
                                       sky: 0xd3ecf0, skyNight: 0x1d3347)
        case .roof:
            // Рубероид, гравий и дощатый настил — ни травинки; кирпичная будка выхода, металлические перила, закат.
            return YardDistrictPalette(ground: 0x676a71, garden: 0x9d978c, park: 0xb98a5e, paving: 0xa7a39b,
                                       tile: 0xc0c4c7, fence: 0x9aa6ad, fenceOld: 0x8a6a52, wall: 0xb5654a,
                                       houseRoof: 0x4a4f57, crown: 0x5fa860, water: 0x7fb4d6, puddle: 0x858a91,
                                       sky: 0xf4d9c3, skyNight: 0x2a2340)
        }
    }

    /// Декор района. У улицы его нет — это вид двора до переезда.
    var decor: [YardDistrictDecor] {
        switch self {
        case .street: return []
        case .winter: return [.snowdrifts, .firTree, .garland, .snowCaps, .snowfall]
        case .river: return [.river, .bridge, .reeds, .duck, .lifebuoy]
        case .roof: return [.parapet, .antennas, .vents, .waterTank, .skyline]
        }
    }
}
