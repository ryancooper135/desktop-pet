// Волна 46 R: походка пса. Чистые правила, по которым сцена (PetChoreo) двигает тело и подгоняет клип walk:
// скорость шага под рост, разгон и торможение (трапеция вместо smoothstep — лапы не скользят на середине пути),
// темп клипа от скорости лап, поворот на месте «переступанием», и чем встать/сесть/лечь, чтобы уйти и вернуться.
// Без RealityKit — гоняется в WSL (GaitTests). Решения — DECISIONS.md, «Волна 46 R».

import Foundation

enum Gait {
    /// Скорость шага взрослого Шибы при темпе клипа walk 1 (как ChoreoPath.Walk.speed), м/с.
    static let nominal: Float = 0.4
    /// Разгон и торможение, с: столько тело набирает (и сбрасывает) скорость шага.
    static let ramp: Double = 0.35
    /// Пределы темпа клипа walk: медленнее — «мультяшная» ходьба на месте, быстрее — семенит.
    static let minRate: Float = 0.5
    static let maxRate: Float = 1.5
    /// При повороте на месте лапы описывают дугу примерно в половину полудлины тела.
    static let pivotArm: Float = 0.5
    /// Поворот на месте с переступанием, рад/с, и не короче minPivot, с.
    static let pivotRate: Float = 2.0
    static let minPivot: Double = 0.5
    /// Поворот меньше этого (рад) — без шагов: пёс просто доворачивается в своём цикле.
    static let pivotMin: Float = 0.15
    /// Сдвиг меньше этого (м) — без шагов: доезжает на месте.
    static let stepMin: Float = 0.04

    /// Скорость шага пса размера size (длина относительно взрослого Шибы). Щенок идёт медленнее, но не вдвое:
    /// снизу 0,55, иначе крошка шёл бы к окну полминуты (темп клипа тогда чуть выше 1, см. rate).
    static func speed(size: Float) -> Float {
        nominal * min(max(size, 0.55), 1.25)
    }

    /// Темп клипа walk, при котором лапы пса размера size идут со скоростью foot (м/с). Модель масштабирована
    /// целиком, так что шаг клипа при темпе 1 — nominal * size.
    static func rate(foot: Float, size: Float) -> Float {
        min(max(foot / (nominal * max(size, 0.2)), minRate), maxRate)
    }

    /// Сколько поворачиваться на месте на угол d, с; почти ноль — 0.
    static func pivotTime(_ d: Float) -> Double {
        abs(d) < 0.01 ? 0 : max(minPivot, Double(abs(d) / pivotRate))
    }

    /// Сколько идти d метров со скоростью speed с разгоном и торможением, с.
    static func walkTime(_ d: Float, speed: Float) -> Double {
        d < 0.001 ? 0 : Double(d / max(speed, 0.01)) + ramp
    }

    /// Доля [0…1] пути длиной T к моменту t: разгон ramp с равным ускорением, ровный шаг, торможение.
    /// Скорость непрерывна, на ровном участке — 1/(T−ramp) (сравни: smoothstep даёт пик 1,5 средней и
    /// почти всё время не совпадает с шагом клипа). Короткий путь — треугольник (ramp ≤ T/2).
    static func travel(_ t: Double, _ T: Double, ramp: Double = Gait.ramp) -> Float {
        guard T > 0 else { return t >= 0 ? 1 : 0 }
        if t <= 0 { return 0 }
        if t >= T { return 1 }
        let r = min(ramp, T / 2)
        let v = 1 / (T - r)
        let s: Double
        if r <= 0 {
            s = t / T
        } else if t < r {
            s = v * t * t / (2 * r)
        } else if t <= T - r {
            s = v * (r / 2 + (t - r))
        } else {
            let e = T - t
            s = 1 - v * e * e / (2 * r)
        }
        return Float(min(max(s, 0), 1))
    }

    /// Клипы из положения from в to существующими переходами (sit_in/out, lie_in/out). Лёжа ↔ сидя — через стойку.
    static func backClips(from: DogIdle.Stance, to: DogIdle.Stance) -> [String] {
        switch (from, to) {
        case (.sit, .stand): return ["sit_out"]
        case (.lie, .stand): return ["lie_out"]
        case (.stand, .sit): return ["sit_in"]
        case (.stand, .lie): return ["lie_in"]
        case (.lie, .sit): return ["lie_out", "sit_in"]
        case (.sit, .lie): return ["sit_out", "lie_in"]
        default: return []
        }
    }

    /// Положение после клипа clip, сыгранного из from.
    static func stance(after clip: String, from: DogIdle.Stance) -> DogIdle.Stance {
        switch clip {
        case "sit_in": return .sit
        case "sit_out", "lie_out": return .stand
        case "lie_in": return .lie
        default: return from
        }
    }
}
