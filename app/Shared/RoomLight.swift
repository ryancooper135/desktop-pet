// Свет комнаты по времени суток и теме (волна 10, «Тёмная комната»). Чистая логика без RealityKit:
// какой «час комнаты» сейчас (фаза 0 — день, 1 — вечер, 2 — ночь), какие при нём свет, тинт стен и небо в окне,
// и нужна ли подложка под статус-бар. Применяет к сцене RoomLighting (app/App), тесты — RoomLightTests.
//
// Фаза по часам идёт от сна хозяина (Owner.bedMin/wakeMin), а не от фиксированных часов:
//   подъём → +60 мин рассвет (2 → 0), день, 18:00–19:30 закат (0 → 1), вечер,
//   за 30 минут до сна → через 15 минут после (1 → 2: тогда же засыпает Шиба), ночь до подъёма.
// Настройка «Комната вечером» (SaveFile.roomEvening): по времени, по теме, всегда день.

import Foundation

/// Настройка «Комната вечером». В файле — rawValue; нет поля или незнакомое значение — standard.
enum RoomEveningMode: String, CaseIterable, Sendable {
    /// Вечер и ночь по часам, тема не влияет.
    case byTime = "time"
    /// Тёмная тема — вечерний свет (ночью — ночь), светлая — всегда день.
    case byTheme = "theme"
    /// Комната всегда дневная.
    case alwaysDay = "day"

    /// По умолчанию — по времени (DECISIONS.md, волна 10).
    static let standard: RoomEveningMode = .byTime

    init(stored: String?) {
        self = stored.flatMap(RoomEveningMode.init(rawValue:)) ?? .standard
    }

    var title: String {
        switch self {
        case .byTime: "По времени"
        case .byTheme: "По теме"
        case .alwaysDay: "Всегда день"
        }
    }
}

/// Цвет 0…1 без UIKit: множитель тинта и цвета света.
struct RoomRGB: Equatable, Sendable {
    var r: Double, g: Double, b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xff) / 255, Double((hex >> 8) & 0xff) / 255, Double(hex & 0xff) / 255)
    }

    static let white = RoomRGB(1, 1, 1)

    /// Относительная яркость (веса Rec. 709 по sRGB-значениям — для порога хватает).
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    static func * (a: RoomRGB, b: RoomRGB) -> RoomRGB { RoomRGB(a.r * b.r, a.g * b.g, a.b * b.b) }

    static func lerp(_ a: RoomRGB, _ b: RoomRGB, _ t: Double) -> RoomRGB {
        RoomRGB(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
    }
}

/// Свет комнаты в одной фазе. Интенсивности — как в PetRoom (люксы направленного света),
/// lamp/moon/stars/vignette — доли 0…1.
struct RoomLight: Equatable, Sendable {
    /// Множитель цвета всех матовых вещей комнаты (стены, пол, вещи дома). Питомец и «светящиеся» детали — без него.
    var tint: RoomRGB
    var key: RoomRGB, keyI: Double
    var fill: RoomRGB, fillI: Double
    var rim: RoomRGB, rimI: Double
    /// Тёплая лампа над лежанкой: 1 — полная (вечер), ночник — поменьше.
    var lamp: Double
    /// Луна и звёзды в окне.
    var moon: Double
    /// Небо в окне (без тинта: окно — источник света).
    var sky: RoomRGB
    /// Затемнение краёв кадра поверх сцены (SwiftUI), чтобы центр с собакой читался.
    var vignette: Double

    // Днём — ровно как было до волны 10 (PetRoom.keyLight/fillLight/rimLight, небо DecorColors.sky).
    static let day = RoomLight(tint: .white,
                               key: RoomRGB(hex: 0xfff3e2), keyI: 2200,
                               fill: RoomRGB(hex: 0xc9d6e6), fillI: 700,
                               rim: RoomRGB(hex: 0xffe2c4), rimI: 900,
                               lamp: 0, moon: 0, sky: RoomRGB(hex: 0xcfe9f7), vignette: 0)
    // Вечер: закатный янтарный ключ, стены приглушены и теплее, загорается лампа, небо персиковое.
    static let evening = RoomLight(tint: RoomRGB(0.84, 0.72, 0.62),
                                   key: RoomRGB(hex: 0xffb878), keyI: 1500,
                                   fill: RoomRGB(hex: 0x9fa8c8), fillI: 380,
                                   rim: RoomRGB(hex: 0xff9d63), rimI: 1000,
                                   lamp: 1, moon: 0, sky: RoomRGB(hex: 0xf3a77c), vignette: 0.18)
    // Ночь: тёмно-синий полумрак, лунный ключ, ночник, луна и звёзды в тёмно-синем окне.
    static let night = RoomLight(tint: RoomRGB(0.36, 0.40, 0.60),
                                 key: RoomRGB(hex: 0xa9bcff), keyI: 1000,
                                 fill: RoomRGB(hex: 0x5c6ca8), fillI: 260,
                                 rim: RoomRGB(hex: 0x93a6ec), rimI: 650,
                                 lamp: 0.35, moon: 1, sky: RoomRGB(hex: 0x1f2c55), vignette: 0.42)

    static func lerp(_ a: RoomLight, _ b: RoomLight, _ t: Double) -> RoomLight {
        // Концы — ровно ключевые кадры (без погрешности a + (b − a)·1): днём свет совпадает со старым.
        if t <= 0 { return a }
        if t >= 1 { return b }
        func f(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return RoomLight(tint: .lerp(a.tint, b.tint, t),
                         key: .lerp(a.key, b.key, t), keyI: f(a.keyI, b.keyI),
                         fill: .lerp(a.fill, b.fill, t), fillI: f(a.fillI, b.fillI),
                         rim: .lerp(a.rim, b.rim, t), rimI: f(a.rimI, b.rimI),
                         lamp: f(a.lamp, b.lamp), moon: f(a.moon, b.moon),
                         sky: .lerp(a.sky, b.sky, t), vignette: f(a.vignette, b.vignette))
    }

    /// Свет при фазе 0…2 (вне диапазона — зажимается): 0–1 день → вечер, 1–2 вечер → ночь.
    static func at(phase: Double) -> RoomLight {
        let p = min(max(phase.isFinite ? phase : 0, 0), 2)
        return p <= 1 ? lerp(day, evening, p) : lerp(evening, night, p - 1)
    }

    /// Яркость задней стены (RoomColors.wall × тинт) — по ней решаем, видны ли часы в статус-баре.
    var wallLuminance: Double { (RoomRGB(hex: 0xfbefe4) * tint).luminance }
}

/// Час комнаты: фаза по времени, теме и настройке.
enum RoomClock {
    /// Минута местных суток 0..<1440 (дробная) для момента now при смещении tzOffsetMin.
    static func localMinute(now: Double, tzOffsetMin: Int) -> Double {
        let m = (now / 60 + Double(tzOffsetMin)).truncatingRemainder(dividingBy: 1440)
        return m < 0 ? m + 1440 : m
    }

    /// Плавная ступенька 0…1.
    static func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    // Закат по часам: начало и конец перехода день → вечер.
    static let sunsetFrom = 18 * 60
    static let sunsetTo = 19 * 60 + 30
    /// Рассвет: сколько минут после подъёма ночь переходит в день.
    static let dawnMin = 60
    /// Вечер → ночь: от bed − bedLead до bed + bedLag (тогда же засыпает Шиба: pet_sleep_offset.after_bed).
    static let bedLead = 30
    static let bedLag = 15

    /// Фаза по часам 0…2 от сна хозяина. Точки идут по кругу от подъёма; если сон рано —
    /// закат сдвигается раньше, чтобы вечер не начинался после сна.
    static func dusk(localMin: Double, bedMin: Int, wakeMin: Int) -> Double {
        func rel(_ m: Int) -> Double {
            let d = Double(((m - wakeMin) % 1440 + 1440) % 1440)
            return d
        }
        // Точки в минутах от подъёма: [день с, закат с, вечер с, ночь-переход с, ночь с].
        // Порядок держим с конца: ранний сон сдвигает закат раньше целиком, той же длины, без скачка.
        let dawn = rel(wakeMin + dawnMin)
        let nightFrom = max(rel(bedMin + bedLag), dawn)
        let toNight = min(rel(bedMin - bedLead), nightFrom)
        let evening = min(rel(sunsetTo), toNight)
        let sunset = max(min(rel(sunsetFrom), evening - Double(sunsetTo - sunsetFrom)), min(dawn, evening))
        let p = [min(dawn, sunset), sunset, evening, toNight, nightFrom]
        let x = ((localMin - Double(wakeMin)).truncatingRemainder(dividingBy: 1440) + 1440)
            .truncatingRemainder(dividingBy: 1440)
        func ramp(_ a: Double, _ b: Double) -> Double { b > a ? smooth((x - a) / (b - a)) : (x >= b ? 1 : 0) }
        if x < p[0] { return 2 - 2 * ramp(0, p[0]) }
        if x < p[1] { return 0 }
        if x < p[2] { return ramp(p[1], p[2]) }
        if x < p[3] { return 1 }
        if x < p[4] { return 1 + ramp(p[3], p[4]) }
        return 2
    }

    /// Итоговая фаза по настройке и теме.
    static func phase(mode: RoomEveningMode, dark: Bool, localMin: Double, bedMin: Int, wakeMin: Int) -> Double {
        switch mode {
        case .alwaysDay:
            return 0
        case .byTime:
            return dusk(localMin: localMin, bedMin: bedMin, wakeMin: wakeMin)
        case .byTheme:
            guard dark else { return 0 }
            return max(1, dusk(localMin: localMin, bedMin: bedMin, wakeMin: wakeMin))
        }
    }

    /// Момент, по которому считаем свет. В UI-тестах без PET_NOW — полдень сегодняшнего дня,
    /// чтобы снимки не зависели от часа, в который их снимает CI.
    static func now(clock: Double, uiTest: Bool, petNowSet: Bool, tzOffsetMin: Int) -> Double {
        guard uiTest, !petNowSet else { return clock }
        let local = localMinute(now: clock, tzOffsetMin: tzOffsetMin)
        return clock + (12 * 60 - local) * 60
    }

    /// Нужна ли подложка под статус-бар: системные часы в тёмной теме белые, в светлой — чёрные;
    /// если стена комнаты за ними того же тона, их не видно.
    static func needsStatusScrim(phase: Double, dark: Bool) -> Bool {
        let lum = RoomLight.at(phase: phase).wallLuminance
        return dark ? lum > statusThreshold : lum < statusThreshold
    }

    /// Порог яркости стены для статус-бара.
    static let statusThreshold = 0.5
}

/// Что нужно сцене от сейва: настройка и сон хозяина. Сравнимое — AppModel меняет его только при правке,
/// чтобы сцена не пересчитывалась на каждый тик.
struct RoomSchedule: Equatable, Sendable {
    var mode: RoomEveningMode
    var bedMin: Int
    var wakeMin: Int

    static let standard = RoomSchedule(mode: .standard, bedMin: Catalog.rules.bedMin, wakeMin: Catalog.rules.wakeMin)

    /// Фаза в момент now (unix-секунды) при смещении пояса tzOffsetMin.
    func phase(dark: Bool, now: Double, tzOffsetMin: Int) -> Double {
        RoomClock.phase(mode: mode, dark: dark, localMin: RoomClock.localMinute(now: now, tzOffsetMin: tzOffsetMin),
                        bedMin: bedMin, wakeMin: wakeMin)
    }

    /// Фаза сейчас по часам приложения. В UI-тестах без PET_NOW — полдень (снимки не зависят от часа CI).
    func phaseNow(dark: Bool, clock: Double = Clock.now()) -> Double {
        let t = RoomClock.now(clock: clock, uiTest: Env.isUITest, petNowSet: Env.value("PET_NOW") != nil,
                              tzOffsetMin: Clock.tzOffsetMin(at: clock))
        return phase(dark: dark, now: t, tzOffsetMin: Clock.tzOffsetMin(at: t))
    }
}

extension SaveFile {
    /// Настройка «Комната вечером» из сейва.
    var roomEveningMode: RoomEveningMode { RoomEveningMode(stored: roomEvening) }

    var roomSchedule: RoomSchedule {
        RoomSchedule(mode: roomEveningMode, bedMin: owner.bedMin, wakeMin: owner.wakeMin)
    }
}
