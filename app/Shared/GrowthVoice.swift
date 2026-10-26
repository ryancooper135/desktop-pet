// Волна 34 I: голос по росту (Growth.look: voicePitch, voiceCrack). Щенок тявкает выше, взрослый — ниже,
// у подростка голос иногда «ломается»: начинает высоко и проваливается вниз. Только собачьи голоса (SoundCue.isVoice) —
// кнопки и хруст не трогаем. Числа, без AVFoundation: SoundKit применяет к рецепту перед проигрыванием.
// Собирается там же, где SoundRecipes (приложение и пакет логики).

#if APP_TARGET || SWIFT_PACKAGE
import Foundation

enum GrowthVoice {
    /// Высота голоса держится в разумных пределах, что бы ни пришло из конфига.
    static let pitchRange = 0.5...2.0
    /// Срыв голоса: начало выше, конец ниже.
    static let crackUp = 1.3
    static let crackDown = 0.75

    /// Ноты голоса с поправкой роста. roll 0..<1: меньше crack — голос сорвался.
    static func apply(_ tones: [Tone], pitch: Double, crack: Double, roll: Double) -> [Tone] {
        let p = min(pitchRange.upperBound, max(pitchRange.lowerBound, pitch.isFinite ? pitch : 1))
        let broke = crack > 0 && roll < crack
        guard p != 1 || broke else { return tones }
        return tones.map { t in
            var t = t
            t.freq *= p
            t.glideTo *= p
            if t.cutoff > 0 { t.cutoff *= p }
            if broke, t.wave != .noise {
                t.freq *= crackUp
                t.glideTo *= crackDown
                if t.glide <= 0 { t.glide = max(0.02, t.env.length * 0.6) }
            }
            return t
        }
    }
}
#endif
