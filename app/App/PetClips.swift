// Контракт имён клипов Шибы (shiba.clips.json из tools/assets). Без RealityKit: читают сцена, тесты и проверка ассетов.
// По одному имени в строке литерала — tests-frames парсит этот файл регуляркой.

import Foundation

enum PetClipNames {
    /// Клипы, которые есть в текущем shiba.clips.json (21 шт.). Сцена на них опирается.
    static let required: [String] = [
        "idle",
        "idle_2",
        "idle_headlow",
        "walk",
        "gallop",
        "gallop_jump",
        "jump_to_idle",
        "eat",
        "attack",
        "hit_left",
        "hit_right",
        "death",
        "sit_in",
        "sit",
        "sit_out",
        "lie_in",
        "lie",
        "lie_out",
        "sleep_in",
        "sleep",
        "sleep_out",
    ]

    /// Клипы на будущее: если пайплайн их соберёт, сцена подхватит сама; нет — шаг пропускается.
    static let optional: [String] = [
        "idle_wag",
        "happy_wag",
        "head_tilt",
        "shake",
        "hop",
        "play_bow",
        "ear_flick",
        "sniff",
        "look_l",
        "look_r",
        "yawn",
    ]
}
