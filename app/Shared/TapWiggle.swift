// Отклик на тап поверх клипа (волна 18): голова чуть склоняется набок, уши дёргаются, хвост коротко виляет.
// Раньше тап мог перезапустить цикл простоя переходом 0,15 с (режиссёр к тому времени сменил idle на idle_2),
// оборвать фиджет на середине (head_tilt — шея набок на 18°) и повернуть голову к пальцу на 34° пружиной без
// разгона — Вадим: «морда косится, и как-то супер резко». Теперь тап — только эта добавка к позе: пружины к целям,
// положение и скорость непрерывны, углы ограничены, частые тапы продлевают отклик, а не начинают его заново.
// Чистая логика без RealityKit: кости пишет PetRig (PetRig.swift), тесты — TapWiggleTests.

import Foundation

/// Пружина к цели: точное решение для dt (не разлетается на длинном кадре). zeta ≥ 1 — критическое демпфирование.
/// Ей же пользуется PetSpring приложения.
enum SoftSpring {
    static func step(x: Float, v: Float, target: Float, omega: Float, zeta: Float, dt: Float) -> (Float, Float) {
        let z = min(max(zeta, 0), 1)
        let x0 = x - target
        if z >= 0.999 {
            let e = exp(-omega * dt)
            let c = v + omega * x0
            return (target + e * (x0 + c * dt), e * (v - omega * c * dt))
        }
        let a = z * omega
        let wd = omega * (1 - z * z).squareRoot()
        let e = exp(-a * dt)
        let cs = cos(wd * dt), sn = sin(wd * dt)
        let b = (v + a * x0) / wd
        return (target + e * (x0 * cs + b * sn), e * (v * cs - (a * b + x0 * wd) * sn))
    }
}

/// Взгляд на палец (AppModel.touch → lookX): мягче и меньше, чем раньше (0,6 рад пружиной omega 10).
enum SoftLook {
    /// Предел поворота головы к пальцу, радианы (≈ 21°). За мячом в игре голова ходит шире (PetFace.limit).
    static let fingerLimit: Float = 0.36
    /// Доля поворота телом (JuiceComponent.yawTarget) у скелетной модели: было 0,15.
    static let bodyShare: Float = 0.08
    /// Пружина головы к пальцу: без перелёта, с разгоном — ~0,45 с до 90%.
    static let omega: Float = 8.5
    static let zeta: Float = 1
}

/// Добавка к позе на тап и щекотку. Углы — радианы; знак наклона — сторона тапа (−1 слева, +1 справа по экрану).
struct TapWiggle: Equatable, Sendable {
    enum Kind: Sendable { case tap, tickle }

    /// Что сейчас добавить к костям.
    struct Pose: Equatable, Sendable {
        /// Наклон головы набок (шея 40% и голова 60%, вокруг оси морды).
        var roll: Float = 0
        /// Уши назад (+) и вперёд (−), обе одинаково.
        var ear: Float = 0
        /// Хвост вбок: Tail1, Tail2, Tail3.
        var tail: [Float] = [0, 0, 0]

        static let zero = Pose()
    }

    /// Какие реакции сцена показывает этой добавкой: тап (с чертой и без, Traits.tapKind) и щекотка.
    static func kind(of reaction: String) -> Kind? {
        if reaction == "tickle" { return .tickle }
        return reaction == "tap" || reaction.hasPrefix("tap.") ? .tap : nil
    }

    // MARK: пределы (их держат тесты)

    static let rollMax: Float = 7 * .pi / 180
    static let earMax: Float = 16 * .pi / 180
    /// Уши вперёд при отскоке — не дальше этой доли earMax.
    static let earBackFraction: Float = 0.5
    static let tailMax: Float = 22 * .pi / 180
    /// Доли размаха Tail2 и Tail3 от Tail1 и их запаздывание по фазе, радианы.
    static let tailShare: [Float] = [1, 0.45, 0.3]
    static let tailLag: [Float] = [0, 0.6, 1.2]
    static let tailHz: Float = 3.2

    // MARK: время

    /// Тапы чаще — та же реакция (не продлевают и не дёргают).
    static let minGap: Double = 0.2
    /// Сколько держится наклон головы и виляние после тапа (и щекотки).
    static let rollHold: Double = 0.35
    static let tickleRollHold: Double = 0.6
    static let wagHold: Double = 0.45
    static let tickleWagHold: Double = 1.0
    /// Ухо тянется назад столько, потом отпускается и пружинит.
    static let earPulse: Double = 0.09
    /// Пружины: наклон и размах хвоста — без перелёта; уши — с отскоком.
    static let rollOmega: Float = 9
    static let wagOmega: Float = 11
    static let earOmega: Float = 22
    static let earZeta: Float = 0.38
    /// Ниже этого всё обнуляется точно — сцена перестаёт писать кости.
    static let rest: Float = 1e-4

    // MARK: состояние

    private(set) var time: Double = 0
    private(set) var side: Float = 1
    private var lastTrigger: Double = -.infinity
    private var rollUntil: Double = -.infinity
    private var earUntil: Double = -.infinity
    private var wagUntil: Double = -.infinity
    private var roll: Float = 0, rollV: Float = 0
    private var ear: Float = 0, earV: Float = 0
    private var wag: Float = 0, wagV: Float = 0
    private var phase: Float = 0
    /// Спит: только ухо дёрнулось, голова и хвост лежат.
    private var earsOnly = false

    /// Ничего не двигается и не будет — кости не трогаем.
    var idle: Bool {
        time >= max(rollUntil, earUntil, wagUntil) && roll == 0 && rollV == 0 && ear == 0 && earV == 0
            && wag == 0 && wagV == 0
    }

    /// Тап (или щекотка). sideHint — куда тапнули (lookX), nil или 0 — по очереди.
    /// earsOnly — спит: дёрнуть ухом, остальное не трогать. Возвращает false, если тап проглочен (слишком частый).
    @discardableResult
    mutating func trigger(_ kind: Kind = .tap, sideHint: Float? = nil, earsOnly: Bool = false) -> Bool {
        if kind == .tap && time - lastTrigger < Self.minGap { return false }
        let active = time < rollUntil || abs(roll) > 0.15 * Self.rollMax
        if !active {
            // Новая сторона только из покоя: посреди наклона голову через центр не бросаем.
            if let s = sideHint, s != 0 { side = s < 0 ? -1 : 1 } else { side = -side }
        }
        self.earsOnly = earsOnly
        lastTrigger = time
        earUntil = time + Self.earPulse
        if !earsOnly {
            rollUntil = max(rollUntil, time + (kind == .tickle ? Self.tickleRollHold : Self.rollHold))
            wagUntil = max(wagUntil, time + (kind == .tickle ? Self.tickleWagHold : Self.wagHold))
        }
        return true
    }

    /// Кадр: пружины к целям, фаза хвоста. Возвращает добавку к позе (уже в пределах).
    mutating func step(dt: Double) -> Pose {
        let d = Float(max(0, min(dt, 0.1)))
        time += Double(d)
        let rollGoal: Float = time < rollUntil ? side * Self.rollMax : 0
        let earGoal: Float = time < earUntil ? 1 : 0
        let wagGoal: Float = time < wagUntil ? 1 : 0
        (roll, rollV) = SoftSpring.step(x: roll, v: rollV, target: rollGoal, omega: Self.rollOmega, zeta: 1, dt: d)
        (ear, earV) = SoftSpring.step(x: ear, v: earV, target: earGoal, omega: Self.earOmega, zeta: Self.earZeta, dt: d)
        (wag, wagV) = SoftSpring.step(x: wag, v: wagV, target: wagGoal, omega: Self.wagOmega, zeta: 1, dt: d)
        if rollGoal == 0 && abs(roll) < Self.rest && abs(rollV) < Self.rest { roll = 0; rollV = 0 }
        if earGoal == 0 && abs(ear) < Self.rest && abs(earV) < Self.rest { ear = 0; earV = 0 }
        if wagGoal == 0 && abs(wag) < Self.rest && abs(wagV) < Self.rest { wag = 0; wagV = 0; phase = 0 }
        if wag != 0 { phase = (phase + 2 * .pi * Self.tailHz * d).truncatingRemainder(dividingBy: 2 * .pi) }
        return pose
    }

    /// Текущая добавка, без шага.
    var pose: Pose {
        let r = min(max(roll, -Self.rollMax), Self.rollMax)
        let e = min(max(ear, -Self.earBackFraction), 1) * Self.earMax
        let a = min(max(wag, 0), 1) * Self.tailMax
        let tail = (0..<3).map { k in a * Self.tailShare[k] * sin(phase - Self.tailLag[k]) }
        return Pose(roll: r, ear: e, tail: tail)
    }
}
