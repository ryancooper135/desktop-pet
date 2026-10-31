// Чистые траектории хореографии без RealityKit: миска, мяч, прогулка, взгляд. Ведёт их PetChoreo.
// Перенесено из PetChoreo.swift без изменений (волна 28).

import Foundation
import simd
import UIKit
@preconcurrency import RealityKit

// MARK: - Траектории

enum ChoreoPath {
    static let up = SIMD3<Float>(0, 1, 0)
    /// Когда тявкнуть от начала клипа bark, секунды: чуть раньше, чем пасть раскрыта сильнее всего (0,2 и 0,6 с).
    static let barkYips: [Double] = [0.16, 0.56]

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

    // MARK: тело персонажа

    /// Тело в сцене относительно Шибы (ставит PetModel.assemble). Точки ниже подобраны под Шибу —
    /// всё, что «от морды» (миска, находка в пасти, где встать перед мячом), множится на него.
    nonisolated(unsafe) static var body = PetBody.shiba

    /// Точка на полу в осях питомца с поправкой на длину и ширину тела.
    static func onFloor(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let q = body.onFloor(Double(p.x), Double(p.y), Double(p.z))
        return SIMD3<Float>(Float(q.x), Float(q.y), Float(q.z))
    }

    /// Точка на теле (пасть) с поправкой ещё и на рост и подъём над полом.
    static func onBody(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let q = body.onBody(Double(p.x), Double(p.y), Double(p.z))
        return SIMD3<Float>(Float(q.x), Float(q.y), Float(q.z))
    }

    static func wrap(_ a: Float) -> Float {
        var x = a
        while x > .pi { x -= 2 * .pi }
        while x < -.pi { x += 2 * .pi }
        return x
    }

    // MARK: еда

    /// Миска под мордой в осях подставки: при eat морда Шибы опускается к полу ~0.3 м вперёд от центра.
    /// У своего персонажа — на его длину (body).
    static let shibaBowlUnderSnout = SIMD3<Float>(0, 0.025, 0.30)
    static var bowlUnderSnout: SIMD3<Float> { onFloor(shibaBowlUnderSnout) }
    static var bowlTarget: SIMD3<Float> { toWorld(bowlUnderSnout) }
    /// С какой высоты миска падает под морду.
    static let bowlDrop: Float = 0.3
    /// За сколько секунд до конца еды корм кончается: последние ~0,96 с подхода (eat_up, кадры 41–64 клипа eat)
    /// Шиба поднимает голову — к этому моменту миска уже пустая. Дальше она только уходит домой, без второй порции.
    /// Ровно длина eat_up: при коротком подходе (3 жевка, волна 32) 0,9 с не хватало — корм таял уже при подъёме.
    static let foodDoneBeforeEnd: Double = Double(64 - EatClip.chewTo) / 24

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
    /// (тот же запас ~10 pt, что у миски в HomeLayoutTests). Посчитано для камеры PetRoom (волна 53: FOV 29.5°,
    /// глаз (0.05, 0.40, 2.4), цель (-0.02, 0.28, 0)) и самого узкого портрета 390/844 — iPhone Air 420/912 шире.
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

    static let playArea = Area(nearZ: 0.35, nearMinX: -0.245, nearMaxX: 0.224,
                               farZ: -1.0, farMinX: -0.441, farMaxX: 0.340)

    /// Пятно Шибы на полу от центра: полудлина (морда…хвост) и полуширина. По мешу shiba.usdz после нормировки
    /// на рост 0.42 — 0.53 × 0.15 м, с запасом под шаг лап, хвост и поворот головы.
    /// У своего персонажа — на его длину и ширину (body).
    static let shibaHalfLength: Float = 0.29
    static let shibaHalfWidth: Float = 0.09
    static var petHalfLength: Float { shibaHalfLength * Float(body.length) }
    static var petHalfWidth: Float { shibaHalfWidth * Float(body.width) }

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
        /// Где Шиба останавливается перед мячом (там же разворачивается обратно): морда у мяча —
        /// 0,3 м от центра у Шибы, у своего персонажа — на его длину.
        static var runTo: SIMD3<Float> {
            playArea.clamp(SIMD3<Float>(ballFar.x, 0, ballFar.z) - runDir * 0.30 * Float(body.length), inset: petReachMax)
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
            // Набегался: виляет и дышит, высунув язык (pant — волна 13; нет клипа — только виляет).
            Cue(at: walk1, steps: ["happy_wag", "pant"], loop: nil),
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
        /// У своего персонажа — на его рост и длину (ChoreoPath.body).
        static let shibaCarry = SIMD3<Float>(0, 0.235, 0.30)
        static let shibaDropped = SIMD3<Float>(0, PetRoom.blobY, 0.36)
        static var carry: SIMD3<Float> { onBody(shibaCarry) }
        static var dropped: SIMD3<Float> { onFloor(shibaDropped) }

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
