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
        // волна 13 (mouth.py): лай на «Голос» и язык наружу после игры и прогулки
        "bark",
        "pant",
    ]
}

/// Еда одним подходом. Клип eat (AnimalArmature|Eating, 64 кадра) сам поднимает голову: 0–0,5 с опускает,
/// 0,5–2,0 с жуёт, 2,0–2,67 с встаёт и смотрит в камеру. Три eat подряд давали «голову вверх» на каждом стыке.
/// Сцена режет eat на три части (ClipTable.shared добавляет их сама): опустил голову → жуёт по кругу → поднял.
/// Шов цикла «жуёт» (кадры 17→41) — 2,3° по худшей кости, как обычный шаг кадра (замер по tools/assets/source/shiba.glb).
enum EatClip {
    static let down = "eat_down"
    static let chew = "eat_chew"
    static let up = "eat_up"
    static let parts = [down, chew, up]

    /// Кадры от начала eat (24 fps): конец «опустил» = начало «жуёт», конец «жуёт» = начало «поднял».
    static let chewFrom = 17
    static let chewTo = 41

    /// Сколько раз жуёт «Покормить» (волна 32: 3 вместо 6, ≈4,7 с вместо 7,7 — ReactBeat.mealChews) и «вещь»
    /// (ровно одна длина eat).
    static let feedChews = ReactBeat.mealChews
    static let itemChews = 1

    static func isEat(_ name: String) -> Bool { name == "eat" || parts.contains(name) }

    /// Границы частей на таймлайне по границам eat. Клип короче частей — nil (части не добавляются).
    static func ranges(start: Double, end: Double, fps: Double) -> [(name: String, start: Double, end: Double)]? {
        let f = max(fps, 1)
        let a = start + Double(chewFrom) / f
        let b = start + Double(chewTo) / f
        guard a > start, b > a, end - b > 0.5 / f else { return nil }
        return [(down, start, a), (chew, a, b), (up, b, end)]
    }

    /// Один подход к миске: голова вниз один раз, жуёт chews раз, голова вверх один раз.
    /// Частей нет (eat короче частей) — целые eat, по одному на две «жуёт».
    static func meal(chews: Int, available: Set<String>) -> [String] {
        let n = max(chews, 1)
        if parts.allSatisfy(available.contains) {
            return [down] + Array(repeating: chew, count: n) + [up]
        }
        return available.contains("eat") ? Array(repeating: "eat", count: (n + 1) / 2) : []
    }
}
