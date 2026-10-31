// Отклик Шибы на действие (волна 32). Вадим: «анимации странные, не особо понятные». Разбор — RESEARCH/19-anim-feedback.md.
// Правило: подготовка (короткий присед телом) → действие (клип) → возврат (переход в цикл позы). Короткая реакция —
// 0,5–1,5 с, «занятие» (еда, игра, пробуждение, щётка, трюк) — не дольше activityMax. Что было не так и что поменяли:
//  • поверх скелетных клипов тело ещё и прыгало пружиной (hop) и плющилось на 12% с перелётом — «желе» и двойной прыжок
//    (play_bow кланяется, а тело при этом взлетает). Теперь у скелета без прыжка, присед 3,5% — как вдох перед движением;
//  • на закрытую кнопку (спит, откат) сначала начиналась миска или мяч, а через миг — «не понял». Теперь сразу отказ;
//  • ласка 2,7 с с наклоном шеи на 18° (кривая морда) — теперь одно виляние с наклоном к руке, 1,5 с;
//  • еда 7,7 с без конца — теперь короче и кончается вилянием; проснулся — зевнул; ванна — сел, после неё отряхнулся.
// Чистая логика без RealityKit: тело — PetModel.apply/drive (PetStage.swift), клипы — PetStance.reaction, тесты — ReactBeatTests.

import Foundation

enum ReactBeat {
    // MARK: присед и прыжок телом (JuiceComponent)

    /// Пружина тела: как JuiceComponent (омега и затухание приседа).
    static let springOmega: Float = 14
    static let springZeta: Float = 0.55

    /// Толчок телом в начале реакции: squash — доля роста (<0 — присел), hop — подскок в долях роста.
    struct Accent: Equatable, Sendable {
        var squash: Float = 0
        var hop: Float = 0
        static let none = Accent()
    }

    /// Присед у скелетной модели: «вдох» перед клипом, перелёт пружины меньше полпроцента — глазом не виден.
    static let skeletonSquash: Float = -0.035
    /// Заглушка без скелета (капсула): клипов нет, присед и прыжок — весь отклик, как было до волны 32.
    static let stubSquash: Float = -0.12
    static let stubHop: Float = 0.04
    static let stubHopTap: Float = 0.025
    static let stubHopTrick: Float = 0.03

    /// Где присед: ласка, еда, вещь, щётка, блюдо с кухни.
    static let squashKinds: Set<String> = ["pet", "feed", "item", Brush.journalKind, Cooking.reactKind]

    /// Толчок на удачную реакцию. skeleton — у модели есть клипы: прыгает она сама (hop, play_bow, трюки),
    /// пружинный прыжок поверх давал двойной подскок. Отказ — без толчка, его показывает клип.
    static func accent(kind: String, ok: Bool, skeleton: Bool) -> Accent {
        guard ok else { return .none }
        if squashKinds.contains(kind) { return Accent(squash: skeleton ? skeletonSquash : stubSquash) }
        if skeleton { return .none }
        switch kind {
        case "play", BlockDuo.reactKind, "levelup": return Accent(hop: stubHop)
        case "tap.playful": return Accent(hop: stubHopTap)
        case let k where k.hasPrefix("trick."): return Accent(hop: stubHopTrick)
        default: return .none
        }
    }

    /// Скорость толчка, после которого пружина из покоя отклонится на peak (точное решение, как SoftSpring.step).
    static func impulse(peak: Float, omega: Float = springOmega, zeta: Float = springZeta) -> Float {
        let z = min(max(zeta, 0), 1)
        let perV: Float
        if z >= 0.999 {
            perV = 1 / (omega * Float(exp(1.0)))
        } else {
            let a = z * omega
            let wd = omega * (1 - z * z).squareRoot()
            let t = atan2(wd, a) / wd
            perV = exp(-a * t) * sin(wd * t) / wd
        }
        return perV > 0 ? peak / perV : 0
    }

    /// Скорость после нового толчка к уже идущему движению (x, v), без наложения: толкаем только на остаток до peak
    /// (пружина из x тянет назад, так что дальше peak тело не уйдёт; на обратном качке — от покоя, перелёт пары
    /// процентов), уже идущий более сильный толчок не трогаем. Три быстрых нажатия не плющат пса втрое.
    /// Меняется только скорость — положение не прыгает.
    static func kick(x: Float, v: Float, peak: Float, omega: Float = springOmega, zeta: Float = springZeta) -> Float {
        let room = x * peak > 0 ? peak - x : peak
        guard peak != 0, room * peak > 0 else { return v }
        let need = impulse(peak: room, omega: omega, zeta: zeta)
        if v * peak > 0 && abs(v) >= abs(need) { return v }
        return need
    }

    // MARK: показывать ли сразу

    /// Реакция сцены сразу по нажатию — только если кнопка открыта (или про неё ничего не известно: «Разбудить»,
    /// трюки). Закрытая (спит, откат, моется) — ждём ответа ядра: оно скажет «нельзя», и пёс сразу покажет отказ,
    /// а не начнёт есть или играть, чтобы через миг передумать.
    static func showsAtOnce(_ gate: ActGate?) -> Bool {
        gate?.ok ?? true
    }

    // MARK: клипы реакций (PetStance.reaction берёт отсюда, лишние отфильтрует по модели)

    /// Погладили стоя: виляет, а наклон к руке, зажмуривание и виляние задом кладёт PetChoreo.petting.
    /// head_tilt убран: шея набок на 18° читалась кривой мордой (как у тапа в волне 18), а ласка тянулась 2,7 с.
    static let pet = ["happy_wag"]
    /// Нельзя (спит — без движения): склонил голову — «не сейчас?».
    static let refuse = ["head_tilt"]
    /// Разбудили из сна: открыл глаза, зевнул лёжа, встал.
    static let wakeFromSleep = ["sleep_out", "yawn", "lie_out"]
    /// Сколько раз жуёт «Покормить» (было 6, ≈7,7 с): короче, но всё ещё видно, что ест.
    static let mealChews = 3
    /// Поел — вильнул хвостом: ясный конец еды, миска уезжает на нём.
    static let afterMeal = ["happy_wag"]
    /// Ванна, а пёс уже сидит (грязный): повёл ухом — «ой, вода». Стоя реакции нет: сесть в ванну — и есть отклик.
    static let bathSitting = ["ear_flick"]
    /// Вышел из ванны (встал): отряхнулся.
    static let afterBath = ["shake"]
    /// Вернулся с прогулки, а на улице дождь (волна 39 D): дома отряхнулся. Только клип — нужды не меняются.
    static let afterRain = ["shake"]

    // MARK: правила хореографии

    enum Weight: Sendable, Equatable {
        /// Короткий отклик: тап, ласка, отказ, ванна сидя.
        case flash
        /// Занятие: еда, игра, пробуждение, щётка, трюк, радость после игры.
        case activity
    }

    /// Короткий отклик, с: 0,5–1,5 по ТЗ и по десятой допуска на целые клипы (ear_flick 0,42, look_l 1,58) —
    /// резать клип ради десятой хуже, чем отыграть его целиком.
    static let flash: ClosedRange<Double> = 0.4...1.6
    /// Занятие — не дольше, с (игра с мячом — 6,2).
    static let activityMax: Double = 6.5

    static func weight(of kind: String, ok: Bool = true) -> Weight {
        guard ok else { return .flash }
        switch kind {
        case "feed", "item", "play", "wake", Cooking.reactKind, Brush.journalKind, BlockDuo.reactKind, "levelup":
            return .activity
        case let k where k.hasPrefix("trick."):
            return .activity
        default:
            return .flash
        }
    }

    /// Длина плана по длинам клипов.
    static func length(_ clips: [String], duration: (String) -> Double) -> Double {
        clips.reduce(0) { $0 + duration($1) }
    }

    /// План укладывается в своё окно. Пустой план — тоже ответ (отклик даёт поза или добавка тапа).
    static func fits(_ clips: [String], weight: Weight, duration: (String) -> Double) -> Bool {
        if clips.isEmpty { return true }
        let len = length(clips, duration: duration)
        switch weight {
        case .flash: return flash.contains(len)
        case .activity: return len > 0 && len <= activityMax
        }
    }

    /// Клипы, после которых тело в другом положении: короткий отклик их не содержит — пёс возвращается туда же.
    static let stanceClips: Set<String> = ["sit_in", "sit_out", "lie_in", "lie_out", "sleep_in", "sleep_out", "death"]
}
