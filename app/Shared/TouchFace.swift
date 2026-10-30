// Лицо под пальцем (волна 50). Вадим: «глаза пропадают и возвращаются при частых тапах». Причина — не веса:
// (1) в беде тап = «Погладить», каждая ласка начиналась с нуля: PetChoreo.begin снимал прошлую (relax — глаза
// открыты), новая через 0,25 с снова их закрывала; частые тапы — глаза мигают закрыто-открыто-закрыто, а закрытый
// глаз (веко цвета шерсти) читается как пропавший; (2) обычное моргание попадало под тапы и добавляло вспышек.
// Лечим: касание откладывает моргание (EyeBlink), повторная ласка продлевает идущую (PettingSpan), закрытый глаз
// рисуется швом (EyeStyle.crease), а не пустым местом. Плюс пена, когда гладят в ванне (BathFoam).
// Чистая логика без RealityKit, тесты — TouchFaceTests.

import Foundation

enum EyeBlink {
    /// Сколько после касания глаз не моргает, секунды. Тапы чаще — глаз открыт всё время, пока трогают.
    static let touchHold: Double = 1.2

    /// Тронули в момент time: следующее моргание не раньше time + hold, а начатое обрываем (глаз сразу открыт).
    static func touched(time: Double, nextBlink: Double, blinkUntil: Double) -> (nextBlink: Double, blinkUntil: Double) {
        (max(nextBlink, time + touchHold), min(blinkUntil, time))
    }
}

enum PettingSpan {
    /// Насколько каждая следующая ласка продлевает идущую, секунды.
    static let add: Double = 1.6
    /// Дольше этого от начала одна ласка не тянется: дальше — новая (клипы успели кончиться).
    static let cap: Double = 8

    /// Новая длина идущей ласки (start, length), если в now погладили ещё: до now + add, не короче прежней,
    /// не длиннее cap от начала (но и не короче прежней, если та уже длиннее cap).
    static func extended(start: Double, length: Double, now: Double, add: Double = add) -> Double {
        let want = max(length, now - start + max(add, 0))
        return min(want, max(length, cap))
    }

    /// Идёт ли ещё ласка в now (её можно продлить, а не начинать заново).
    static func active(start: Double, length: Double, now: Double) -> Bool {
        now >= start - 0.05 && now < start + length
    }
}

/// Довольная морда: гладят в ванне — зажмурился и приоткрыл пасть.
enum HappyFace {
    /// Сколько держится, секунды (повторная ласка продлевает).
    static let hold: Double = 1.3
    /// Пасть приоткрыта на столько радиан (речь JawTalk — до 0,2).
    static let jaw: Float = 0.12
}

/// Пена в ванне (волна 50): пузыри вокруг головы и спины, поднимаются и тают. Детерминированная раскладка
/// по номеру ласки — повторная гладка даёт другой узор, а тесты — один и тот же.
enum BathFoam {
    struct Bubble: Equatable, Sendable {
        /// Где рождается: доли полуразмеров тела (x — поперёк, -1…1; y — высота 0…1; z — вдоль, -1 хвост … 1 морда).
        var start: SIMD3<Float>
        /// Сдвиг вверх-вбок за жизнь, в тех же долях.
        var drift: SIMD3<Float>
        /// Радиус в долях высоты тела.
        var radius: Float
        /// Задержка рождения и жизнь, секунды.
        var delay: Double
        var life: Double
    }

    static let count = 9
    /// Самое долгое: задержка + жизнь. Потом контейнер удаляют.
    static let total: Double = 1.7

    /// Узор для ласки номер seed. side: где рука по экрану (-1…1), пена гуще с той стороны.
    static func bubbles(seed: Int, side: Float = 0) -> [Bubble] {
        var rng = UInt64(truncatingIfNeeded: seed &* 2_654_435_761 &+ 0x9E37_79B9)
        func next() -> Float {
            rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float((rng >> 40) & 0xFFFF) / Float(0xFFFF)
        }
        let lean = min(max(side.isFinite ? side : 0, -1), 1) * 0.35
        var out: [Bubble] = []
        for i in 0..<count {
            // Треть — на голове (z ближе к морде, выше), остальное — на спине.
            let head = i % 3 == 0
            let x = (next() * 2 - 1) * 0.75 + lean
            let y: Float = head ? 0.85 + next() * 0.15 : 0.6 + next() * 0.25
            let z: Float = head ? 0.55 + next() * 0.3 : (next() * 2 - 1) * 0.6
            let drift = SIMD3<Float>((next() * 2 - 1) * 0.15, 0.25 + next() * 0.2, 0)
            let radius: Float = 0.035 + next() * 0.035
            let delay = Double(i) * 0.05 + Double(next()) * 0.08
            let life = 0.9 + Double(next()) * 0.6
            out.append(Bubble(start: SIMD3(min(max(x, -1), 1), y, z), drift: drift, radius: radius,
                              delay: delay, life: min(life, total - delay)))
        }
        return out
    }
}
