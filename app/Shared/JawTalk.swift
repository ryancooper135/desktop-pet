// Челюсть «говорит» (волна 13): пока на экране реплика Шибы (AppModel.sayLine), рот приоткрывается по буквам —
// гласная открывает, согласная чуть-чуть, пробел и знаки закрывают. Не звук и не губы: лёгкое движение,
// чтобы реплика шла от пса. Сцена (PetRig.talk) кладёт угол поверх клипа на кость Jaw; нет кости — ничего.
// Здесь только расчёт открытости 0…1 по тексту и времени — без RealityKit, для тестов в Linux.

import Foundation

enum JawTalk {
    /// Предел открытия, радианы (~9°): зевок в клипе — 36°, лай — 26°.
    static let maxAngle: Float = 9 * .pi / 180
    /// Темп «речи», букв в секунду.
    static let charsPerSecond: Double = 14
    /// Дольше не болтает: длинная реплика договаривается молча.
    static let maxTalk: Double = 3
    /// Затухание в конце, секунды.
    static let fade: Double = 0.2

    /// Доля открытия для буквы: гласная 1, согласная 0.45, остальное (пробел, знаки, эмодзи, цифры) 0.
    static func weight(_ c: Character) -> Double {
        let s = String(c).lowercased()
        guard s.count == 1, let ch = s.first else { return 0 }
        if vowels.contains(ch) { return 1 }
        return ch.isLetter ? 0.45 : 0
    }

    private static let vowels: Set<Character> = Set("аеёиоуыэюяaeiouy")

    /// Сколько секунд пёс «говорит» эту реплику.
    static func duration(_ text: String) -> Double {
        min(Double(text.count) / charsPerSecond, maxTalk)
    }

    /// Открытость 0…1 через t секунд после появления реплики. Между буквами — плавно (косинус),
    /// после последней буквы и вне [0, duration] — 0; если реплику обрезало по maxTalk, рот закрывается за fade.
    static func openness(_ text: String, at t: Double) -> Double {
        let end = duration(text)
        guard t > 0, t < end, t.isFinite else { return 0 }
        let w = text.prefix(Int(maxTalk * charsPerSecond) + 1).map(weight)
        let f = t * charsPerSecond
        let i = Int(f)
        let a = i < w.count ? w[i] : 0
        let b = i + 1 < w.count ? w[i + 1] : 0
        let u = f - Double(i)
        let s = a + (b - a) * 0.5 * (1 - cos(.pi * u))
        return s * min(1, (end - t) / fade)
    }

    /// Угол челюсти, радианы.
    static func angle(_ text: String, at t: Double) -> Float {
        Float(openness(text, at: t)) * maxAngle
    }
}
