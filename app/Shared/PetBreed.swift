// Волна 58: порода пса из коробки — Шиба или Хаски (обе Quaternius, CC0; tools/assets собирает их одним
// пайплайном: те же клипы, рот, глаза, материалы по номерам). Выбор — в «Свой персонаж» → «Кто в комнате».
// Без RealityKit: читают сейв, сцена, двор и тесты.

import Foundation

enum PetBreed: String, CaseIterable, Sendable {
    case shiba, husky

    /// Порода нового сейва и всех сейвов до волны 58.
    static let standard: PetBreed = .shiba

    /// Из сейва (SaveFile.breed): nil или незнакомое имя (сейв из будущей версии) — Шиба.
    init(save: String?) {
        self = save.flatMap(PetBreed.init(rawValue:)) ?? .standard
    }

    /// Что писать в сейв: Шиба — nil, файл старого сейва не меняется.
    var saved: String? { self == .standard ? nil : rawValue }

    /// Ресурсы в бандле (app/Resources/Pets): <resource>.usdz и <resource>.clips.json.
    var resource: String { rawValue }
    var clipsResource: String { rawValue + ".clips" }

    /// Для списка «Кто в комнате» и тостов.
    var title: String {
        switch self {
        case .shiba: return "Шиба"
        case .husky: return "Хаски"
        }
    }

    /// Строка под названием в списке.
    var note: String {
        switch self {
        case .shiba: return "Рыжая, карие глаза"
        case .husky: return "Серая, голубые глаза"
        }
    }

    /// Сдвиг лёжа на боку (клип death) в единицах модели: середина рамки скина в конце death минус в idle,
    /// замер по собранным клипам tools/assets (build_clips.py). Шиба: +1,36 при росте 3,09; Хаски: +1,42 при 3,18.
    var deathShiftX: Float {
        switch self {
        case .shiba: return -1.36
        case .husky: return -1.42
        }
    }

    /// Радужка (материал Eyes_Pupil, PetRig.styleEyes).
    var iris: UInt32 {
        switch self {
        case .shiba: return EyeStyle.iris
        case .husky: return EyeStyle.irisBlue
        }
    }

    /// Основной цвет шерсти для клочков при расчёсывании (CoatFur.tuftColors). Шиба — nil: её рыжие клочки как были.
    var fur: UInt32? {
        switch self {
        case .shiba: return nil
        case .husky: return 0x8E99AA
        }
    }

    /// Пятно тела рядом с Шибой при том же росте (рамка idle): Хаски на ~9 % короче и на ~10 % уже —
    /// миска и мяч встают к его морде, тень по нему.
    var body: PetBody {
        switch self {
        case .shiba: return .shiba
        case .husky: return PetBody(height: 1, length: 0.91, width: 0.9, lift: 0)
        }
    }
}
