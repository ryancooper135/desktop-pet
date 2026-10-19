// Хореография сцены: миска под мордой на время еды, мяч в «Поиграть», уход на прогулку и возвращение
// с находкой, взгляд головой и моргание.
// ChoreoPath — чистые траектории без RealityKit (их покрывает PetChoreoTests). PetChoreo ведёт их по часам
// ClipState: двигает обёртку питомца с пятном-тенью, миску и мяч и ставит клипы на границах отрезков игры.
// PetRig поворачивает шею и голову к взгляду (кости Neck3 и Head) и моргает подменой материалов глаз.
// Время — секунды от начала реакции; координаты мировые, +y вверх, питомец дома стоит в нуле.
// Челюсти и век в shiba.usdz нет: «закрытый глаз» — материал шерсти на месте глаза (style_a eyes_closed).

import Foundation
import simd
import UIKit
@preconcurrency import RealityKit

// MARK: - Траектории

enum ChoreoPath {
    static let up = SIMD3<Float>(0, 1, 0)

    // MARK: помощники

    static func clamp01(_ x: Double) -> Float { Float(min(max(x, 0), 1)) }
    static func smooth(_ x: Double) -> Float { let t = clamp01(x); return t * t * (3 - 2 * t) }
    static func easeOut(_ x: Double) -> Float { let t = clamp01(x); return 1 - (1 - t) * (1 - t) }
    static func easeIn(_ x: Double) -> Float { let t = clamp01(x); return t * t }
    /// С небольшим перелётом за 1 — «выскочила».
    static func easeOutBack(_ x: Double) -> Float {
        let t = clamp01(x) - 1
        let c1: Float = 1.70158, c3 = c1 + 1
        return 1 + c3 * t * t * t + c1 * t * t
    }

    static func bezier(_ a: SIMD3<Float>, _ c: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        let s = 1 - t
        return s * s * a + 2 * s * t * c + t * t * b
    }

    /// Оси подставки (повёрнута на yaw3q) → мир и обратно.
    static func toWorld(_ p: SIMD3<Float>) -> SIMD3<Float> { simd_quatf(angle: PetRoom.yaw3q, axis: up).act(p) }
    static func toStand(_ p: SIMD3<Float>) -> SIMD3<Float> { simd_quatf(angle: -PetRoom.yaw3q, axis: up).act(p) }

    /// Поворот по y, при котором морда (+z) смотрит вдоль d. Положительный — к +x, вправо по экрану.
    static func yaw(toward d: SIMD3<Float>) -> Float { atan2(d.x, d.z) }

    static func wrap(_ a: Float) -> Float {
        var x = a
        while x > .pi { x -= 2 * .pi }
        while x < -.pi { x += 2 * .pi }
        return x
    }

    // MARK: еда

    /// Миска под мордой в осях подставки: при eat морда опускается к полу ~0.3 м вперёд от центра.
    static let bowlUnderSnout = SIMD3<Float>(0, 0.025, 0.30)
    static var bowlTarget: SIMD3<Float> { toWorld(bowlUnderSnout) }
    /// С какой высоты миска падает под морду.
    static let bowlDrop: Float = 0.3
    /// За сколько секунд до конца еды корм кончается: последние ~0,96 с подхода (eat_up, кадры 41–64 клипа eat)
    /// Шиба поднимает голову — к этому моменту миска уже пустая. Дальше она только уходит домой, без второй порции.
    static let foodDoneBeforeEnd: Double = 0.9

    /// Когда идёт еда: от начала шагов до первого eat (или его части, EatClip) и до конца подряд идущих. Нет — nil.
    static func eatWindow(_ steps: [String], duration: (String) -> Double) -> (start: Double, end: Double)? {
        guard let i = steps.firstIndex(where: EatClip.isEat) else { return nil }
        let start = steps[..<i].reduce(0) { $0 + duration($1) }
        var end = start
        var j = i
        while j < steps.count, EatClip.isEat(steps[j]) {
            end += duration(steps[j])
            j += 1
        }
        return (start, end)
    }

    struct BowlPose: Equatable {
        var position: SIMD3<Float>
        var scale: SIMD3<Float>
        /// Сколько корма: 1 — горка, 0 — пусто (горка спрятана).
        var food: Float
    }

    /// Миска в момент t: дома → тает → падает под морду с приплющиванием → корм убывает за едой → уходит домой.
    /// present — миска уже стоит под мордой (кормят ещё раз подряд): не прыгает, корм досыпается.
    static func bowl(_ t: Double, eatStart: Double, eatEnd: Double, leave: Double, present: Bool = false) -> BowlPose {
        let home = BowlPose(position: PetRoom.bowlPos, scale: .one, food: 0)
        let target = bowlTarget
        let eatFrom = eatStart + 0.4
        let food = 1 - clamp01((t - eatFrom) / max(eatEnd - foodDoneBeforeEnd - eatFrom, 0.1))
        if t >= leave {
            let k = t - leave
            if k < 0.15 {
                return BowlPose(position: target, scale: .init(repeating: max(1 - easeIn(k / 0.15), 0.001)), food: food)
            }
            return BowlPose(position: home.position, scale: .init(repeating: max(easeOutBack((k - 0.15) / 0.2), 0.001)),
                            food: 0)
        }
        if present { return BowlPose(position: target, scale: .one, food: food) }
        let d0 = max(0, eatStart - 0.5)
        if t < d0 { return home }
        if t < d0 + 0.15 {
            return BowlPose(position: home.position, scale: .init(repeating: max(1 - easeIn((t - d0) / 0.15), 0.001)),
                            food: 0)
        }
        let arrive = d0 + 0.4
        if t < arrive {
            let k = (t - d0 - 0.15) / 0.25
            let y = bowlDrop * (1 - easeIn(k))
            return BowlPose(position: target + SIMD3<Float>(0, y, 0),
                            scale: .init(repeating: max(easeOut(k * 1.6), 0.001)), food: 1)
        }
        // Приземлилась: короткое приплющивание.
        let a = 1 - clamp01((t - arrive) / 0.25)
        let s = a * a
        return BowlPose(position: target, scale: SIMD3<Float>(1 + 0.1 * s, 1 - 0.2 * s, 1 + 0.1 * s), food: food)
    }

    // MARK: площадка в кадре

    /// Часть пола, где всё, что стоит на полу (от пола до макушки, 0…0.42 м), целиком в кадре.
    /// Трапеция по z между ближним и дальним краем; x на краях — где точка уходит за |NDC x| = 0.95
    /// (тот же запас ~10 pt, что у миски в HomeLayoutTests). Посчитано для камеры PetRoom (FOV 32°,
    /// глаз (0.06, 0.78, 2.4), цель (-0.02, 0.2, 0)) и самого узкого портрета 390/844 — iPhone Air 420/912 шире.
    /// Край кадра на полу при такой камере — прямая, поэтому между краями линейно. Тронули камеру, рост
    /// или узкий портрет — пересчитать: PetChoreoTests.testPlayStaysInFrame проецирует путь через саму камеру.
    struct Area: Sendable {
        var nearZ: Float, nearMinX: Float, nearMaxX: Float
        var farZ: Float, farMinX: Float, farMaxX: Float

        func xRange(_ z: Float) -> (min: Float, max: Float) {
            let t = (nearZ - z) / (nearZ - farZ)
            return (nearMinX + (farMinX - nearMinX) * t, nearMaxX + (farMaxX - nearMaxX) * t)
        }

        /// Точка в площадку: z между краями, x не ближе inset к боковому краю (уже не влезает — середина).
        func clamp(_ p: SIMD3<Float>, inset: Float) -> SIMD3<Float> {
            var q = p
            q.z = min(max(p.z, farZ), nearZ)
            let r = xRange(q.z)
            let lo = r.min + inset, hi = r.max - inset
            q.x = lo <= hi ? min(max(p.x, lo), hi) : (r.min + r.max) / 2
            return q
        }
    }

    static let playArea = Area(nearZ: 0.35, nearMinX: -0.27, nearMaxX: 0.25,
                               farZ: -1.0, farMinX: -0.48, farMaxX: 0.37)

    /// Пятно Шибы на полу от центра: полудлина (морда…хвост) и полуширина. По мешу shiba.usdz после нормировки
    /// на рост 0.42 — 0.53 × 0.15 м, с запасом под шаг лап, хвост и поворот головы.
    static let petHalfLength: Float = 0.29
    static let petHalfWidth: Float = 0.09

    /// Насколько Шиба при повороте yaw выступает по x от своего центра.
    static func petReach(yaw: Float) -> Float { abs(sin(yaw)) * petHalfLength + abs(cos(yaw)) * petHalfWidth }
    /// Запас при любом повороте — полудиагональ пятна. Точки, где Шиба разворачивается, ставим с ним.
    static var petReachMax: Float { (petHalfLength * petHalfLength + petHalfWidth * petHalfWidth).squareRoot() }

    // MARK: игра

    /// «Поиграть», время u — от начала play_bow. Мяч уходит вправо назад дугой с затухающими отскоками,
    /// Шиба ещё на поклоне разворачивается за ним через «лицом к камере», отходя чуть назад к середине кадра,
    /// бежит, прыгает на мяч, разворачивается и идёт на место; мяч катится домой справа от него, Шиба
    /// дома виляет хвостом мордой к камере и в конце встаёт в 3/4. Все точки пути — в playArea с запасом
    /// на размер (pet/ball их ещё и прижимают в каждом кадре), чтобы на узком портрете ничего не резалось.
    /// Тайминги подобраны в симуляции: мяч и тело (капсула) не пересекаются нигде, кроме прыжка.
    enum Play {
        static let kick = 1.15, fly = 1.4
        /// turn0 — конец play_bow (1.42 с): сразу разворот за мячом.
        static let turn0 = 1.4, turn1 = 2.3, run1 = 2.8, pounce1 = 3.3, back0 = 3.8, walk1 = 4.7
        /// Мяч катится домой через ballDelay после разворота, за ballBack.
        static let ballDelay = 0.3, ballBack = 1.6
        /// Последние faceHome секунд игры дома: от «мордой к камере» в 3/4. Раньше нельзя — мимо зада катится мяч.
        static let faceHome = 0.5
        /// Игра занимает питомца: вернулся и повилял хвостом.
        static let length = walk1 + 1.5
        static let ballRadius: Float = 0.05
        static var ballHome: SIMD3<Float> { PetRoom.ballPos }
        /// Где Шиба разворачивается за мячом: чуть назад и к середине кадра, там помещается боком.
        static var turnAt: SIMD3<Float> { playArea.clamp(SIMD3<Float>(-0.04, 0, -0.30), inset: petReachMax) }
        /// Куда улетает мяч: вглубь, правее середины.
        static var ballFar: SIMD3<Float> { playArea.clamp(SIMD3<Float>(0.08, 0.05, -0.88), inset: ballRadius) }
        /// Опоры дуг полёта и возврата: справа, в обход зада Шибы (зазор > 0.13 м).
        static let flyCurve = SIMD3<Float>(0.34, 0.05, -0.10)
        static let backCurve = SIMD3<Float>(0.30, 0.05, -0.35)
        /// Отскоки в полёте: длительность и высота.
        static let bounces: [(Double, Float)] = [(0.5, 0.16), (0.32, 0.07), (0.2, 0.025)]

        static var runDir: SIMD3<Float> {
            let d = ballFar - turnAt
            return simd_normalize(SIMD3<Float>(d.x, 0, d.z))
        }
        /// Где Шиба останавливается перед мячом (там же разворачивается обратно).
        static var runTo: SIMD3<Float> {
            playArea.clamp(SIMD3<Float>(ballFar.x, 0, ballFar.z) - runDir * 0.30, inset: petReachMax)
        }
        /// Куда мяч откатывается от прыжка.
        static var knockTo: SIMD3<Float> { playArea.clamp(ballFar + runDir * 0.08, inset: ballRadius) }
        static var yawRun: Float { yaw(toward: runDir) }
        static var yawBack: Float { yaw(toward: -runTo) }

        struct Cue: Sendable {
            var at: Double
            var steps: [String]
            /// nil — основной цикл позы.
            var loop: String?
        }

        static let cues: [Cue] = [
            Cue(at: turn0, steps: [], loop: "walk"),
            Cue(at: turn1, steps: [], loop: "gallop"),
            Cue(at: run1, steps: ["hop"], loop: "idle"),
            Cue(at: pounce1, steps: [], loop: "walk"),
            Cue(at: walk1, steps: ["happy_wag"], loop: nil),
        ]
    }

    struct PetPose: Equatable {
        /// Мировая точка на полу.
        var position: SIMD3<Float>
        /// Мировой поворот по y (дома — yaw3q).
        var yaw: Float
    }

    /// Шиба в момент u игры, прижатый к playArea с запасом на свой размер при этом повороте.
    static func pet(_ u: Double) -> PetPose {
        var p = petPath(u)
        p.position = playArea.clamp(p.position, inset: petReach(yaw: p.yaw))
        p.position.y = 0
        return p
    }

    static func petPath(_ u: Double) -> PetPose {
        typealias P = Play
        let y0 = PetRoom.yaw3q
        if u < P.turn0 { return PetPose(position: .zero, yaw: y0) }
        if u < P.turn1 {
            // Через «лицом к камере», не спиной; заодно отходит к turnAt, где боком влезает в кадр.
            let s = smooth((u - P.turn0) / (P.turn1 - P.turn0))
            return PetPose(position: P.turnAt * s, yaw: y0 + (P.yawRun - y0) * s)
        }
        if u < P.run1 {
            return PetPose(position: P.turnAt + (P.runTo - P.turnAt) * smooth((u - P.turn1) / (P.run1 - P.turn1)),
                           yaw: P.yawRun)
        }
        if u < P.pounce1 { return PetPose(position: P.runTo, yaw: P.yawRun) }
        if u < P.back0 {
            return PetPose(position: P.runTo,
                           yaw: P.yawRun + (P.yawBack - P.yawRun) * smooth((u - P.pounce1) / (P.back0 - P.pounce1)))
        }
        if u < P.walk1 {
            let s = smooth((u - P.back0) / (P.walk1 - P.back0))
            return PetPose(position: P.runTo * (1 - s), yaw: P.yawBack)
        }
        // Дома мордой к камере, пока справа катится мяч; в конце — в 3/4.
        let k = smooth((u - (P.length - P.faceHome)) / P.faceHome)
        return PetPose(position: .zero, yaw: P.yawBack + (y0 - P.yawBack) * k)
    }

    /// Высота отскока над полом через t после удара.
    static func bounce(_ t: Double) -> Float {
        var t = t
        for (d, h) in Play.bounces {
            if t < d {
                let s = Float(max(t, 0) / d)
                return h * 4 * s * (1 - s)
            }
            t -= d
        }
        return 0
    }

    /// Мяч в момент u игры, прижатый к playArea.
    static func ball(_ u: Double) -> SIMD3<Float> {
        playArea.clamp(ballPath(u), inset: Play.ballRadius)
    }

    static func ballPath(_ u: Double) -> SIMD3<Float> {
        typealias P = Play
        let r = P.ballRadius
        if u < P.kick { return P.ballHome }
        if u < P.kick + P.fly {
            var p = bezier(P.ballHome, P.flyCurve, P.ballFar, easeOut((u - P.kick) / P.fly))
            p.y = r + bounce(u - P.kick)
            return p
        }
        let k0 = P.pounce1 - 0.25
        if u < k0 { return P.ballFar }
        if u < k0 + 0.3 {
            let k = clamp01((u - k0) / 0.3)
            var p = P.ballFar + (P.knockTo - P.ballFar) * easeOut((u - k0) / 0.3)
            p.y = r + 0.04 * 4 * k * (1 - k)
            return p
        }
        let b0 = P.back0 + P.ballDelay
        if u < b0 { return P.knockTo }
        if u < b0 + P.ballBack {
            var p = bezier(P.knockTo, P.backCurve, P.ballHome, easeOut((u - b0) / P.ballBack))
            p.y = r
            return p
        }
        return P.ballHome
    }

    /// Поворот головы к мячу относительно морды, в пределах ±limit. Вне игры — nil.
    static func look(_ u: Double, limit: Float) -> Float? {
        guard u >= 0, u < Play.walk1 else { return nil }
        let p = pet(u)
        let d = ball(u) - p.position
        return min(max(wrap(yaw(toward: d) - p.yaw), -limit), limit)
    }

    // MARK: ласка

    /// «Погладить» стоя: поверх клипов (head_tilt, happy_wag) Шиба тянется к руке — клонится вбок к пальцу,
    /// жмурится и виляет задом (поворот по y туда-сюда). Время t — от начала реакции, length — длина её клипов.
    enum Petting {
        /// Наклон к руке, радианы (~8°: макушка уходит на ~6 см).
        static let lean: Float = 0.14
        /// Виляние задом: размах цели поворота, радианы, и частота. Пружина yaw (omega 14) на 2,6 Гц
        /// отдаёт примерно половину размаха — на экране ~±5°.
        static let wiggle: Float = 0.16
        static let wiggleHz: Float = 2.6
        /// Наклон набирается за leanIn и уходит за leanOut до конца.
        static let leanIn = 0.35, leanOut = 0.45
        /// Глаза закрыты с eyesFrom и до eyesBeforeEnd до конца: сначала увидел руку, в конце открыл глаза.
        static let eyesFrom = 0.25, eyesBeforeEnd = 0.4
        /// Короче — не успеет ни зажмуриться, ни наклониться.
        static let minLength = 1.5
    }

    struct PettingPose: Equatable {
        /// Крен к руке, радианы: + — макушка вправо по экрану.
        var lean: Float
        /// Добавка к цели поворота по y, радианы.
        var wiggle: Float
        var eyesClosed: Bool

        static let rest = PettingPose(lean: 0, wiggle: 0, eyesClosed: false)
    }

    /// side — где рука: -1 слева, +1 справа по экрану.
    static func petting(_ t: Double, length: Double, side: Float) -> PettingPose {
        typealias P = Petting
        guard t >= 0, t < length else { return .rest }
        let env = smooth(t / P.leanIn) * (1 - smooth((t - (length - P.leanOut)) / P.leanOut))
        let s: Float = side < 0 ? -1 : 1
        let wig = P.wiggle * env * sin(2 * .pi * P.wiggleHz * Float(t))
        return PettingPose(lean: s * P.lean * env, wiggle: wig,
                           eyesClosed: t >= P.eyesFrom && t < length - P.eyesBeforeEnd)
    }
}

extension ChoreoPath {
    // MARK: прогулка

    /// «Гулять»: Шиба на месте разворачивается через «лицом к камере», чуть отходя назад (иначе морда задела бы мяч),
    /// и уходит шагом за правый край кадра; комната пустеет (PetChoreo прячет тело и пятно, на месте — записка).
    /// Возвращается оттуда же с находкой в зубах, дома встаёт в 3/4, кладёт находку перед собой и виляет хвостом;
    /// находка подпрыгивает и тает — «ушла в альбом». Время u — от начала ухода (после перехода в стойку)
    /// или от начала возвращения. Числа — на глаз, сверять по раскадровке anim-walk.
    enum Walk {
        /// Где разворачивается перед уходом: назад от мяча, чтобы морда при повороте его не задела.
        /// Глубже -0.3: ближе площадка уже двух «радиусов» Шибы, и поворот на месте задевал бы край кадра.
        static let turnAt = SIMD3<Float>(0.0, 0, -0.30)
        /// Точка за правым краем кадра: Шиба там целиком за краем playArea (testWalkExitOffFrame).
        static let offstage = SIMD3<Float>(0.95, 0, -0.15)
        /// Скорость шага, м/с: под клип walk, чтобы лапы не скользили. Править по anim-walk.
        static let speed: Float = 0.4
        /// Разворот на месте перед уходом и дома после прихода.
        static let turnOut = 0.8, turnIn = 0.5
        /// Находка: падает из пасти, лежит перед мордой, подпрыгивает и тает.
        static let dropTime = 0.3, showTime = 1.8, fadeTime = 0.35
        /// Где держит находку и куда кладёт — в осях питомца (морда к +z), начало пропа — внизу.
        /// Пасть у Шибы ~0.25 м над полом и ~0.3 м вперёд от центра (как миска под мордой при еде).
        /// Проп не привязан к кости головы: при кивках может чуть разойтись с пастью — сверять по anim-walk.
        static let carry = SIMD3<Float>(0, 0.235, 0.30)
        static let dropped = SIMD3<Float>(0, PetRoom.blobY, 0.36)

        static var outWalk: Double { Double(simd_length(offstage - turnAt) / speed) }
        static var inWalk: Double { Double(simd_length(offstage) / speed) }
        static var outLength: Double { turnOut + outWalk }
        static var dropAt: Double { inWalk + turnIn }
        static var inLength: Double { dropAt + dropTime + showTime + fadeTime }
        static var yawOut: Float { ChoreoPath.yaw(toward: offstage - turnAt) }
        static var yawIn: Float { ChoreoPath.yaw(toward: -offstage) }
    }

    /// Разгон с места: 0 → 1, скорость в начале 0, в конце 1.5 — уходит за край, не тормозя.
    static func accel(_ x: Double) -> Float { let t = clamp01(x); return t * t * (3 - t) / 2 }

    /// Уход: разворот через «лицом к камере» с шагом назад к turnAt, потом шаг к offstage с разгоном.
    static func walkOut(_ u: Double) -> PetPose {
        typealias W = Walk
        let y0 = PetRoom.yaw3q
        if u < W.turnOut {
            let s = smooth(u / W.turnOut)
            return PetPose(position: W.turnAt * s, yaw: y0 + (W.yawOut - y0) * s)
        }
        return PetPose(position: W.turnAt + (W.offstage - W.turnAt) * accel((u - W.turnOut) / W.outWalk), yaw: W.yawOut)
    }

    /// Возвращение: из-за края домой с торможением (мордой влево, мяч остаётся сбоку), дома — в 3/4.
    static func walkIn(_ u: Double) -> PetPose {
        typealias W = Walk
        let y0 = PetRoom.yaw3q
        if u < W.inWalk {
            let s = 1 - accel(1 - u / W.inWalk)
            return PetPose(position: W.offstage * (1 - s), yaw: W.yawIn)
        }
        return PetPose(position: .zero, yaw: W.yawIn + (y0 - W.yawIn) * smooth((u - W.inWalk) / W.turnIn))
    }

    /// С какого u возвращения начать, если Шиба ещё не скрылся (прогулку отменили на полпути):
    /// точка на пути домой на том же расстоянии от дома.
    static func walkInStart(from p: SIMD3<Float>) -> Double {
        let q = min(max(simd_length(SIMD3<Float>(p.x, 0, p.z)) / simd_length(Walk.offstage), 0), 1)
        // accel(1 - u/inWalk) = q, accel монотонна — делим пополам.
        var lo = 0.0, hi = 1.0
        for _ in 0..<30 {
            let mid = (lo + hi) / 2
            if accel(mid) < q { lo = mid } else { hi = mid }
        }
        return (1 - lo) * Walk.inWalk
    }

    struct PropPose: Equatable {
        /// В осях питомца.
        var position: SIMD3<Float>
        var scale: Float
    }

    /// Находка в момент u возвращения: в пасти → падает перед мордой → лежит → подпрыгивает и тает. nil — уже в альбоме.
    static func walkProp(_ u: Double) -> PropPose? {
        typealias W = Walk
        let d = u - W.dropAt
        if d < 0 { return PropPose(position: W.carry, scale: 1) }
        if d < W.dropTime {
            return PropPose(position: W.carry + (W.dropped - W.carry) * easeIn(d / W.dropTime), scale: 1)
        }
        let f = d - W.dropTime - W.showTime
        if f < 0 { return PropPose(position: W.dropped, scale: 1) }
        if f < W.fadeTime {
            let k = f / W.fadeTime
            return PropPose(position: W.dropped + SIMD3<Float>(0, 0.12 * easeOut(k), 0), scale: max(1 - easeIn(k), 0.001))
        }
        return nil
    }
}

// MARK: - Компоненты

/// Что сейчас ведёт хореография. Часы — ClipState.clock.
struct ChoreoState: Component {
    struct Feed {
        var start: Double
        var eatStart: Double
        var eatEnd: Double
        /// Когда миска уходит домой, от start.
        var leave: Double
        var present: Bool
    }

    struct Play {
        /// Часы на начале play_bow.
        var start: Double
        var mainLoop: String
        var cue = 0
    }

    struct Petting {
        var start: Double
        var length: Double
        /// Где рука: -1 слева, +1 справа по экрану.
        var side: Float
    }

    struct Walk {
        /// true — уходит, false — возвращается.
        var out: Bool
        /// Часы на начале ухода (после перехода в стойку) или возвращения.
        var start: Double
        /// Находка в зубах (id); пусто — без находки.
        var find: String
        /// Виляние хвостом дома уже поставлено.
        var cued = false
    }

    var feed: Feed?
    var play: Play?
    var petting: Petting?
    var walk: Walk?
    /// Гуляет: тело и пятно спрятаны, комната пустая.
    var hidden = false
    /// Последнее возвращение, которое сцена уже видела (AppModel.walkHome.id), как lastReactionId у реакций.
    var walkHomeId = 0
    var walkPrimed = false
    var active = false
    /// Переход к новой траектории (начало игры, отмена) из того, что стояло, за PetChoreo.blend.
    var blendStart: Double = -100
    var fromPos = SIMD3<Float>.zero
    var fromYaw: Float = PetRoom.yaw3q
    var fromBall = PetRoom.ballPos
    var pos = SIMD3<Float>.zero
    var yaw: Float = PetRoom.yaw3q
    var ball = PetRoom.ballPos
}

/// Уровни дома, по которым PetChoreo поднимает Шибу на матрас лежанки (PetChoreo.setHome).
struct HomeLift: Component {
    var levels: RoomPlan.Levels
}

/// Взгляд головой и моргание.
struct PetFace: Component {
    /// Предел поворота головы, радианы (шея 40%, голова 60%).
    static let limit: Float = 0.6
    /// Куда повернуть голову, радианы: + — вправо по экрану. Пишет PetModel.apply из lookX.
    var target: Float = 0
    /// Игра ведёт взгляд за мячом поверх target.
    var follow: Float? = nil
    var angle: Float = 0
    var speed: Float = 0
    var time: Double = 0
    var nextBlink: Double = 2.5
    var blinkUntil: Double = 0
    /// Гладят: глаза закрыты от удовольствия. Пишет PetChoreo.step.
    var bliss = false
    /// Reduce Motion: голова сразу на месте, без моргания.
    var still = false
}

// MARK: - Хореография

@MainActor
enum PetChoreo {
    static let blend: Double = 0.35

    nonisolated static func duration(_ name: String) -> Double {
        guard let c = ClipTable.shared?.clips[name] else { return 0 }
        return c.end - c.start
    }

    /// Проигрыватель поставил шаги. Есть eat — миска под морду, есть play_bow — игра с мячом.
    /// Прошлая хореография при этом сворачивается. Возвращает, до какого момента часов занята игра.
    /// trick — шаги играют удачный трюк: «Поклон» без мяча, «Голос» тявкает на прыжке.
    @discardableResult
    static func begin(_ pet: Entity, steps: [String], clock: Double, mainLoop: String,
                      trick: Trick? = nil) -> Double? {
        var cs = pet.components[ChoreoState.self] ?? ChoreoState()
        let present = bowlAtSnout(cs, clock)
        interrupt(&cs, clock)
        SoundKit.shared.cancelChoreo()
        if let w = cs.walk, !w.out, clock - w.start < ChoreoPath.Walk.inWalk {
            // Новое действие, пока идёт домой: находка сразу «в альбоме», Шиба плавно домой.
            // Дома (поза после прихода) находка доигрывает сама.
            cs.walk = nil
            removeProp(pet)
            snapshot(&cs, clock)
            cs.active = true
        }
        if cs.petting != nil {
            cs.petting = nil
            relax(pet)
        }
        var until: Double?
        if let w = ChoreoPath.eatWindow(steps, duration: duration) {
            cs.feed = .init(start: clock, eatStart: w.start, eatEnd: w.end, leave: w.end + 0.5, present: present)
            cs.active = true
            SoundKit.shared.eat(from: w.start, to: w.end)
        }
        if trick == .speak, let i = steps.firstIndex(of: "hop") {
            SoundKit.shared.play(.yip, after: steps[..<i].reduce(0) { $0 + duration($1) })
        }
        if trick == nil, let i = steps.firstIndex(of: "play_bow") {
            let offset = steps[..<i].reduce(0) { $0 + duration($1) }
            cs.play = .init(start: clock + offset, mainLoop: mainLoop)
            cs.active = true
            SoundKit.shared.ball(after: offset)
            until = clock + offset + ChoreoPath.Play.length
        }
        pet.components.set(cs)
        return until
    }

    /// Гладят стоя: поверх клипов реакции наклон к руке, виляние и закрытые глаза на length секунд.
    /// Вызывать после begin (begin снимает прошлую ласку).
    static func petting(_ pet: Entity, clock: Double, length: Double, side: Float) {
        var cs = pet.components[ChoreoState.self] ?? ChoreoState()
        cs.petting = .init(start: clock, length: max(length, ChoreoPath.Petting.minLength), side: side)
        cs.active = true
        pet.components.set(cs)
    }

    /// Снять ласку: наклон и виляние к нулю (пружиной), глаза снова моргают.
    static func relax(_ pet: Entity) {
        if var j = pet.components[JuiceComponent.self] {
            j.leanTarget = 0
            j.wiggle = 0
            pet.components.set(j)
        }
        if var face = pet.components[PetFace.self], face.bliss {
            face.bliss = false
            pet.components.set(face)
        }
    }

    /// Reduce Motion: всё сразу домой, без движения.
    static func stop(_ pet: Entity) {
        guard var cs = pet.components[ChoreoState.self], cs.active else { return }
        SoundKit.shared.cancelChoreo()
        cs.feed = nil
        cs.play = nil
        if cs.walk != nil {
            cs.walk = nil
            removeProp(pet)
        }
        if cs.petting != nil {
            cs.petting = nil
            relax(pet)
        }
        cs.active = false
        cs.pos = .zero
        cs.yaw = PetRoom.yaw3q
        cs.ball = ChoreoPath.Play.ballHome
        cs.blendStart = -100
        let room = pet.scene?.findEntity(named: "room")
        place(pet, cs, room)
        placeBowl(room, .init(position: PetRoom.bowlPos, scale: .one, food: 0))
        if var face = pet.components[PetFace.self] {
            face.follow = nil
            pet.components.set(face)
        }
        pet.components.set(cs)
    }

    /// Миска сейчас стоит под мордой и ещё не уходит.
    static func bowlAtSnout(_ cs: ChoreoState, _ clock: Double) -> Bool {
        guard let f = cs.feed else { return false }
        let t = clock - f.start
        let arrived = f.present || t >= max(0, f.eatStart - 0.5) + 0.4
        return arrived && t < f.leave
    }

    /// Новая реакция перебила: игра плавно домой, миска уходит (если ещё не начала прыгать — остаётся дома).
    static func interrupt(_ cs: inout ChoreoState, _ clock: Double) {
        if cs.play != nil {
            cs.play = nil
            snapshot(&cs, clock)
        }
        if var f = cs.feed {
            let t = clock - f.start
            let d0 = max(0, f.eatStart - 0.5)
            if !f.present && t < d0 {
                cs.feed = nil
            } else if t < f.leave {
                f.leave = f.present ? t : max(t, d0 + 0.6)
                cs.feed = f
            }
        }
    }

    static func snapshot(_ cs: inout ChoreoState, _ clock: Double) {
        cs.fromPos = cs.pos
        cs.fromYaw = cs.yaw
        cs.fromBall = cs.ball
        cs.blendStart = clock
    }

    /// Кадр: миска, игра (клипы на границах отрезков), обёртка с пятном-тенью и мяч.
    static func step(_ pet: Entity) {
        guard var cs = pet.components[ChoreoState.self], cs.active,
              let st = pet.components[ClipState.self] else { return }
        let now = st.clock
        let room = pet.scene?.findEntity(named: "room")

        if let f = cs.feed {
            let t = now - f.start
            placeBowl(room, ChoreoPath.bowl(t, eatStart: f.eatStart, eatEnd: f.eatEnd, leave: f.leave, present: f.present))
            if t > f.leave + 0.4 {
                cs.feed = nil
                placeBowl(room, .init(position: PetRoom.bowlPos, scale: .one, food: 0))
            }
        }

        var pose = ChoreoPath.PetPose(position: .zero, yaw: PetRoom.yaw3q)
        var ball = ChoreoPath.Play.ballHome
        var look: Float? = nil
        if var p = cs.play {
            let u = now - p.start
            let cues = ChoreoPath.Play.cues
            let available = Set(ClipTable.shared?.clips.keys.map { $0 } ?? [])
            while p.cue < cues.count, u >= cues[p.cue].at {
                let c = cues[p.cue]
                ClipPlayer.play(PetStance.pick(c.steps, available: available), then: c.loop ?? p.mainLoop, on: pet,
                                transition: 0.2, randomSpeed: false, initial: false)
                p.cue += 1
            }
            pose = ChoreoPath.pet(u)
            ball = ChoreoPath.ball(u)
            look = ChoreoPath.look(u, limit: PetFace.limit)
            cs.play = u >= ChoreoPath.Play.length ? nil : p
        } else if var w = cs.walk {
            let u = now - w.start
            if w.out {
                pose = ChoreoPath.walkOut(max(u, 0))
                if u >= ChoreoPath.Walk.outLength {
                    // Ушёл за край: комната пустая до возвращения.
                    cs.walk = nil
                    cs.hidden = true
                    setHidden(pet, true)
                }
            } else {
                pose = ChoreoPath.walkIn(u)
                if !w.cued && u >= ChoreoPath.Walk.inWalk {
                    // Дома: виляет хвостом, пока кладёт находку; новую позу потом поставит режиссёр (lockUntil).
                    w.cued = true
                    let available = Set(ClipTable.shared?.clips.keys.map { $0 } ?? [])
                    ClipPlayer.play(PetStance.pick(["happy_wag"], available: available), then: "idle", on: pet,
                                    transition: 0.2, randomSpeed: false, initial: false)
                }
                placeProp(pet, ChoreoPath.walkProp(u))
                cs.walk = u >= ChoreoPath.Walk.inLength ? nil : w
            }
        }

        var bliss = false
        if let g = cs.petting {
            let t = now - g.start
            let pp = ChoreoPath.petting(t, length: g.length, side: g.side)
            if var j = pet.components[JuiceComponent.self] {
                j.leanTarget = pp.lean
                j.wiggle = pp.wiggle
                pet.components.set(j)
            }
            bliss = pp.eyesClosed
            if t >= g.length {
                cs.petting = nil
                relax(pet)
            }
        }

        let k = ChoreoPath.smooth((now - cs.blendStart) / blend)
        cs.pos = cs.fromPos + (pose.position - cs.fromPos) * k
        cs.yaw = cs.fromYaw + (pose.yaw - cs.fromYaw) * k
        cs.ball = cs.fromBall + (ball - cs.fromBall) * k
        place(pet, cs, room)
        if var face = pet.components[PetFace.self], face.follow != look || face.bliss != bliss {
            face.follow = look
            face.bliss = bliss
            pet.components.set(face)
        }
        if cs.feed == nil && cs.play == nil && cs.petting == nil && cs.walk == nil && k >= 1 {
            cs.active = false
        }
        pet.components.set(cs)
    }

    // MARK: прогулка

    /// Прогулка по позе и счётчику возвращений (AppModel.walkHome). Вызывать до PetModel.apply: возвращение
    /// держит новую позу (lockUntil), пока Шиба не дойдёт до дома, потом её ставит режиссёр (pendingPose).
    /// Сразу, без шага: первый вызов (открыли экран — гуляет, значит комната пустая; вернулся, пока приложение
    /// было закрыто, — просто стоит дома), Reduce Motion, заглушка без клипов и смерть (instant).
    static func walk(_ pet: Entity, away: Bool, instant: Bool, homeId: Int, find: String, reduceMotion: Bool) {
        var cs = pet.components[ChoreoState.self] ?? ChoreoState()
        let fresh = cs.walkPrimed && homeId != cs.walkHomeId
        let first = !cs.walkPrimed
        cs.walkPrimed = true
        cs.walkHomeId = homeId
        guard var st = pet.components[ClipState.self], ClipTable.shared != nil,
              !reduceMotion, !first, !instant else {
            if cs.walk != nil {
                cs.walk = nil
                removeProp(pet)
            }
            if cs.hidden != away {
                cs.hidden = away
                cs.pos = .zero
                cs.yaw = PetRoom.yaw3q
                cs.blendStart = -100
                place(pet, cs, pet.scene?.findEntity(named: "room"))
            }
            setHidden(pet, away)
            pet.components.set(cs)
            return
        }
        let now = st.clock

        if away {
            // Уже ушёл или уходит.
            guard !cs.hidden, cs.walk?.out != true else {
                pet.components.set(cs)
                return
            }
            // Уход — после перехода в стойку (его сыграет drive) и после идущей реакции.
            let available = Set(ClipTable.shared?.clips.keys.map { $0 } ?? [])
            let path = PetStance.pick(PetStance.path(from: st.stance, to: .stand), available: available)
            let start = max(now, st.lockUntil) + path.reduce(0) { $0 + duration($1) }
            interrupt(&cs, now)
            if cs.petting != nil {
                cs.petting = nil
                relax(pet)
            }
            if cs.walk != nil { removeProp(pet) }
            snapshot(&cs, now)
            cs.walk = .init(out: true, start: start, find: "")
            cs.active = true
            pet.components.set(cs)
            return
        }

        if let w = cs.walk, w.out, now - w.start < ChoreoPath.Walk.turnOut {
            // Прогулку отменили до первого шага (ночь, беда): просто домой.
            cs.walk = nil
            snapshot(&cs, now)
            cs.active = true
            pet.components.set(cs)
            return
        }
        guard cs.hidden || cs.walk?.out == true else {
            // Уже дома или идёт домой: находку, пришедшую чуть позже позы, всё равно дать в зубы.
            if fresh, !find.isEmpty, var w = cs.walk, !w.out, w.find.isEmpty {
                w.find = find
                cs.walk = w
                addProp(pet, find)
            }
            pet.components.set(cs)
            return
        }

        // Возвращение: из-за края (или с полпути), шагом, с находкой в зубах.
        var start = now
        if cs.hidden {
            cs.pos = ChoreoPath.Walk.offstage
            cs.yaw = ChoreoPath.Walk.yawIn
            cs.blendStart = -100
        } else {
            start = now - ChoreoPath.walkInStart(from: cs.pos)
            snapshot(&cs, now)
        }
        cs.hidden = false
        setHidden(pet, false)
        let item = fresh ? find : ""
        removeProp(pet)
        if !item.isEmpty { addProp(pet, item) }
        cs.walk = .init(out: false, start: start, find: item)
        cs.active = true
        place(pet, cs, pet.scene?.findEntity(named: "room"))
        pet.components.set(cs)

        ClipPlayer.play([], then: "walk", on: pet, transition: 0.2, randomSpeed: false, initial: false)
        let wag = PetStance.pick(["happy_wag"], available: Set(ClipTable.shared?.clips.keys.map { $0 } ?? []))
        let home = start + ChoreoPath.Walk.inWalk
        let hold = home + max(ChoreoPath.Walk.turnIn, wag.reduce(0) { $0 + duration($1) })
        st.current = "~walk"
        st.stance = .stand
        st.loop = "walk"
        st.reactionSteps = []
        st.busyUntil = hold
        st.lockUntil = hold
        st.nextFidgetAt = hold + Double.random(in: 15...25)
        pet.components.set(st)
    }

    /// Гуляет: прячем тело (обёртку с дыханием) и пятно-тень; сама обёртка остаётся — её часы и системы идут.
    static func setHidden(_ pet: Entity, _ hidden: Bool) {
        pet.findEntity(named: PetModel.pivotName)?.isEnabled = !hidden
        pet.parent?.children.first(where: { $0.name == "blobShadow" })?.isEnabled = !hidden
    }

    static func addProp(_ pet: Entity, _ find: String) {
        let prop = PetRoom.findProp(find)
        prop.position = ChoreoPath.Walk.carry
        pet.addChild(prop)
    }

    static func removeProp(_ pet: Entity) {
        pet.children.first(where: { $0.name == PetRoom.propName })?.removeFromParent()
    }

    static func placeProp(_ pet: Entity, _ p: ChoreoPath.PropPose?) {
        guard let prop = pet.children.first(where: { $0.name == PetRoom.propName }) else { return }
        guard let p else {
            prop.removeFromParent()
            return
        }
        prop.position = p.position
        prop.scale = SIMD3<Float>(repeating: p.scale)
    }

    /// Уровни дома для подъёма на лежанку (RoomPlan.petLift). Зовётся из PetStage на каждый пересчёт вью:
    /// те же уровни — ничего; новые (купили лежанку) — стоящего Шибу сразу поднимаем, идущего поднимет place.
    static func setHome(_ pet: Entity, _ levels: RoomPlan.Levels) {
        if pet.components[HomeLift.self]?.levels == levels { return }
        pet.components.set(HomeLift(levels: levels))
        let cs = pet.components[ChoreoState.self]
        if cs?.active == true { return }
        pet.position.y = lift(pet, at: cs?.pos ?? .zero)
    }

    /// Высота лап над полом, когда середина Шибы в точке p комнаты: верх матраса на лежанке, иначе 0.
    static func lift(_ pet: Entity, at p: SIMD3<Float>) -> Float {
        guard let levels = pet.components[HomeLift.self]?.levels else { return 0 }
        return RoomPlan.petLift(levels, at: RoomPlan.P(p.x, p.z))
    }

    /// Обёртка питомца и пятно-тень (оба в подставке) и мяч (в комнате).
    static func place(_ pet: Entity, _ cs: ChoreoState, _ room: Entity?) {
        var local = ChoreoPath.toStand(cs.pos)
        local.y += lift(pet, at: cs.pos)
        let rot = simd_quatf(angle: cs.yaw - PetRoom.yaw3q, axis: ChoreoPath.up)
        pet.position = local
        pet.orientation = rot
        if let shadow = pet.parent?.children.first(where: { $0.name == "blobShadow" }) {
            shadow.position = SIMD3<Float>(local.x, PetRoom.blobY, local.z)
            shadow.orientation = rot
        }
        room?.findEntity(named: "ball")?.position = cs.ball
    }

    static func placeBowl(_ room: Entity?, _ b: ChoreoPath.BowlPose) {
        guard let bowl = room?.findEntity(named: "bowl") else { return }
        bowl.position = b.position
        bowl.scale = b.scale
        if let food = bowl.findEntity(named: "food") {
            food.isEnabled = b.food > 0.01
            let side = 0.7 + 0.3 * b.food
            food.scale = SIMD3<Float>(side, max(0.45 * b.food, 0.001), side)
        }
    }
}

// MARK: - Кости и глаза

/// Шея и голова Шибы и материалы глаз. Ищется один раз на питомца.
@MainActor
final class PetRig {
    private static var rigs: [Entity.ID: PetRig] = [:]

    private weak var skin: ModelEntity?
    /// Neck3 и Head, доля поворота каждой.
    private var joints: [Int] = []
    private let share: [Float] = [0.4, 0.6]
    private var parents: [Int] = []
    private var base: [simd_quatf] = []
    private var last: [simd_quatf?] = []

    private weak var eyes: ModelEntity?
    private var open: [any Material] = []
    private var closed: [any Material] = []
    private var eyesClosed = false

    static func rig(for pet: Entity) -> PetRig? {
        let id = pet.id
        if let r = rigs[id] { return r }
        guard let body = pet.findEntity(named: PetModel.bodyName) else { return nil }
        if rigs.count > 8 { rigs.removeAll() }
        let r = PetRig(body)
        rigs[id] = r
        return r
    }

    private init(_ body: Entity) {
        var queue: [Entity] = [body]
        while !queue.isEmpty {
            let e = queue.removeFirst()
            if let m = e as? ModelEntity {
                if skin == nil, !m.jointNames.isEmpty { setUpJoints(m) }
                if eyes == nil, let mats = m.model?.materials, mats.count == 6 { setUpEyes(m, mats) }
            }
            queue += Array(e.children)
        }
    }

    /// Пути костей вида «Body/…/Neck3/Head»: родитель — путь без последнего звена.
    private func setUpJoints(_ m: ModelEntity) {
        let names = m.jointNames
        // Свой персонаж — по псевдонимам костей из character.json.
        func find(_ leaf: String) -> Int? { PetModel.boneIndex(names, leaf) }
        guard let neck = find("Neck3"), let head = find("Head"), m.jointTransforms.count == names.count else { return }
        var index: [String: Int] = [:]
        for (i, n) in names.enumerated() { index[n] = i }
        parents = names.map { n in
            guard let cut = n.lastIndex(of: "/") else { return -1 }
            return index[String(n[..<cut])] ?? -1
        }
        skin = m
        joints = [neck, head]
        base = joints.map { m.jointTransforms[$0].rotation }
        last = [nil, nil]
    }

    /// Порядок подмножеств: Main, Main_Light, Black, Eyes_White, Eyes_Pupil, Eyes_Black. Проверяем по цвету,
    /// что 3 светлее шерсти, а 4 и 5 темнее; не сошлось — не моргаем.
    private func setUpEyes(_ m: ModelEntity, _ mats: [any Material]) {
        let light = mats.map(Self.brightness)
        guard let fur = light[0], let white = light[3], let pupil = light[4], let black = light[5],
              white > fur + 0.1, pupil < fur, black < fur else { return }
        eyes = m
        open = mats
        closed = mats
        for i in 3...5 { closed[i] = mats[0] }
    }

    private static func brightness(_ m: any Material) -> CGFloat? {
        guard let p = m as? PhysicallyBasedMaterial else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard p.baseColor.tint.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return r + g + b
    }

    /// Поворот шеи и головы вокруг вертикали сцены. Анимация пишет кости каждый кадр — добавку кладём поверх
    /// её позы; если кость не перезаписали (стоит наша прошлая запись), берём прошлую основу, а не копим поворот.
    func look(_ angle: Float) {
        guard let m = skin, joints.count == 2 else { return }
        if abs(angle) < 1e-4 && last.allSatisfy({ $0 == nil }) { return }
        var tr = m.jointTransforms
        guard tr.count == parents.count else { return }
        for k in 0..<2 {
            let cur = tr[joints[k]].rotation
            if let l = last[k], Self.same(cur, l) { continue }
            base[k] = cur
        }
        var rot = tr.map(\.rotation)
        for k in 0..<2 { rot[joints[k]] = base[k] }
        let up = simd_normalize(m.convert(direction: ChoreoPath.up, from: nil))
        for k in 0..<2 {
            let j = joints[k]
            let axis = simd_normalize(global(j, rot).inverse.act(up))
            let q = base[k] * simd_quatf(angle: angle * share[k], axis: axis)
            tr[j].rotation = q
            last[k] = q
        }
        m.jointTransforms = tr
    }

    /// Шерсть перекрасили (PetRoom.applyCoat): открытые и закрытые глаза берут новые материалы.
    func recolor(_ m: ModelEntity, _ mats: [any Material]) {
        guard let e = eyes, e === m, mats.count == open.count else { return }
        open = mats
        closed = mats
        for i in 3...5 { closed[i] = mats[0] }
        if eyesClosed, var model = e.model {
            model.materials = closed
            e.model = model
        }
    }

    func setEyes(closed shut: Bool) {
        guard shut != eyesClosed, let e = eyes, var model = e.model else { return }
        model.materials = shut ? closed : open
        e.model = model
        eyesClosed = shut
    }

    private func global(_ j: Int, _ rot: [simd_quatf]) -> simd_quatf {
        var q = rot[j]
        var p = parents[j]
        var n = 0
        while p >= 0 && n < 64 {
            q = rot[p] * q
            p = parents[p]
            n += 1
        }
        return q
    }

    private static func same(_ a: simd_quatf, _ b: simd_quatf) -> Bool {
        let d = a.vector - b.vector
        return max(abs(d.x), abs(d.y), abs(d.z), abs(d.w)) < 1e-5
    }

    /// Кадр лица: пружина взгляда, моргание, во сне глаза закрыты.
    static func step(_ pet: Entity, dt: Double) {
        guard var face = pet.components[PetFace.self] else { return }
        face.time += dt
        let goal = face.follow ?? face.target
        if face.still {
            face.angle = goal
            face.speed = 0
        } else {
            (face.angle, face.speed) = PetSpring.step(x: face.angle, v: face.speed, target: goal,
                                                      omega: 10, zeta: 0.9, dt: Float(dt))
        }
        var shut = false
        let st = pet.components[ClipState.self]
        if let st, st.stance == .sleep, st.clock >= st.busyUntil - 0.4 {
            shut = true
        } else if face.bliss {
            // Гладят — жмурится от удовольствия.
            shut = true
        } else if !face.still {
            if face.time >= face.nextBlink {
                face.blinkUntil = face.time + 0.13
                // Иногда двойное моргание.
                face.nextBlink = face.time + (Double.random(in: 0..<1) < 0.2 ? 0.3 : Double.random(in: 2.5...6))
            }
            shut = face.time < face.blinkUntil
        }
        pet.components.set(face)
        guard let rig = rig(for: pet) else { return }
        rig.look(face.angle)
        rig.setEyes(closed: shut)
    }
}

/// Хореография и лицо по кадрам.
struct PetActSystem: System {
    private let query = EntityQuery(where: .has(PetFace.self))

    init(scene: RealityKit.Scene) {}

    @MainActor func update(context: SceneUpdateContext) {
        let dt = min(context.deltaTime, 0.1)
        guard dt > 0 else { return }
        for e in context.entities(matching: query, updatingSystemWhen: .rendering) {
            PetChoreo.step(e)
            PetRig.step(e, dt: dt)
            PetWear.step(e)
        }
    }
}
