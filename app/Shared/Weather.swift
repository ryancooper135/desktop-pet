// Погода и времена года (волна 39 D): псевдопогода без сети, WeatherKit и геолокации.
// Детерминирована по местному времени: сутки режутся на блоки по blockHours от местной полуночи, вид погоды
// блока — хеш его номера (StableHash + StableRandom), так что один и тот же момент даёт одну и ту же погоду
// при каждом запуске, в приложении, виджете и тестах. Сезон — по месяцу, северное полушарие, умеренный климат
// как в Сербии: зимой бывает снег, весной и осенью чаще дождь, летом ясно и изредка короткая гроза.
// Погода — только косметика: свет и капли в комнате и во дворе, реплики Шибы. Экономику, нужды, доход и опыт
// она не трогает (DECISIONS.md, волна 39 D). Цифры — WeatherConfig (раздел weather в config/economy.json).

import Foundation
@preconcurrency import PetCore

/// Погода сейчас.
enum WeatherKind: String, CaseIterable, Codable, Hashable, Sendable {
    case clear, cloudy, rain, storm, snow

    var title: String {
        switch self {
        case .clear: "Ясно"
        case .cloudy: "Пасмурно"
        case .rain: "Дождь"
        case .storm: "Гроза"
        case .snow: "Снег"
        }
    }

    /// Мокро: после прогулки Шиба отряхивается.
    var wet: Bool { self == .rain || self == .storm }

    /// Что-то падает с неба: капли или хлопья.
    var falls: Bool { wet || self == .snow }

    /// Ключ реплики в lines.json; у ясной погоды своих реплик нет.
    var lineKey: String? {
        switch self {
        case .clear: nil
        case .cloudy: "weather_cloudy"
        case .rain: "weather_rain"
        case .storm: "weather_storm"
        case .snow: "weather_snow"
        }
    }

    /// Как погода выглядит в квартале двора. Зимний квартал — вечная зима: вместо дождя снег,
    /// а зимой там снег идёт всегда (ТЗ волны 39 D).
    func inDistrict(_ d: YardDistrict, season: Season) -> WeatherKind {
        guard d == .winter else { return self }
        if wet { return .snow }
        return season == .winter ? .snow : self
    }
}

/// Время года по месяцу (северное полушарие): зима — декабрь–февраль, весна — март–май и так далее.
enum Season: String, CaseIterable, Hashable, Sendable {
    case winter, spring, summer, autumn

    init(month: Int) {
        switch month {
        case 3...5: self = .spring
        case 6...8: self = .summer
        case 9...11: self = .autumn
        default: self = .winter
        }
    }

    /// Сезон местных суток day (номер DayKey).
    init(day: Int) { self.init(month: Season.month(ofDay: day)) }

    /// Месяц 1…12 местных суток day (дни от 1970-01-01). Без Calendar: чистая арифметика григорианского
    /// календаря (алгоритм civil_from_days), одинаковая на iPhone, в виджете и на Linux.
    static func month(ofDay day: Int) -> Int {
        let z = day + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        return mp < 10 ? mp + 3 : mp - 9
    }

    var title: String {
        switch self {
        case .winter: "Зима"
        case .spring: "Весна"
        case .summer: "Лето"
        case .autumn: "Осень"
        }
    }
}

/// Цифры погоды. Умолчания — здесь, файл (economy.json → weather) их переопределяет; тест сверяет одно с другим.
struct WeatherConfig: Hashable, Sendable {
    /// Длина блока погоды, часы. Блоки выровнены по местной полуночи: 0–4, 4–8, … — 6 блоков в сутки.
    var blockHours = 4
    /// Доля блоков, которые повторяют погоду прошлого блока: дождь идёт полдня, а не мигает каждые 4 часа.
    var stay = 0.45
    /// Сколько блоков назад смотреть при повторе (защита от длинной цепочки; 0,45⁸ ≈ 0,2 %).
    var stayDepth = 8
    /// Шансы вида погоды по сезонам (нормируются; нет вида — шанс 0). Гроза не повторяется: следом — дождь.
    var odds: [Season: [WeatherKind: Double]] = [
        .winter: [.clear: 0.30, .cloudy: 0.35, .snow: 0.30, .rain: 0.05],
        .spring: [.clear: 0.35, .cloudy: 0.30, .rain: 0.30, .storm: 0.05],
        .summer: [.clear: 0.60, .cloudy: 0.17, .rain: 0.13, .storm: 0.10],
        .autumn: [.clear: 0.28, .cloudy: 0.35, .rain: 0.35, .storm: 0.02],
    ]
    /// Насколько погода приглушает свет 0…1 (RoomLight.weathered): пасмурно — чуть, гроза — заметно.
    var gloom: [WeatherKind: Double] = [.clear: 0, .cloudy: 0.45, .rain: 0.7, .storm: 0.9, .snow: 0.5]
    /// Частиц за окном комнаты и во дворе. Мало и крупные — ретро и 60 кадров/с.
    var roomRain = 14
    var roomSnow = 12
    var yardRain = 36
    var yardSnow = 28
    /// Гроза — дождь гуще во столько раз.
    var stormMul = 1.3
    /// Скорость падения, высот объёма в секунду: капля пролетает окно за ~0,6 с, хлопок — за ~5 с.
    var rainFall = 1.6
    var snowFall = 0.18

    static let shared = WeatherConfig(json: Catalog.economy() ?? .null)

    init() {}

    init(json e: JSONValue) {
        func num(_ v: JSONValue, _ d: Double) -> Double { v.double ?? d }
        func int(_ v: JSONValue, _ d: Int) -> Int { v.double.map { Int($0) } ?? d }
        let w = e["weather"]
        blockHours = min(max(int(w["block_hours"], blockHours), 1), 24)
        // Блоки выровнены по местной полуночи, только если длина делит сутки: 5 ч дали бы блок через полночь
        // и сутки без своего начала. Берём ближайший делитель 24 вниз (волна 40 E).
        while 24 % blockHours != 0 { blockHours -= 1 }
        stay = min(max(num(w["stay"], stay), 0), 0.95)
        stayDepth = min(max(int(w["stay_depth"], stayDepth), 0), 32)
        for season in Season.allCases {
            let o = w["odds"][season.rawValue]
            guard case .object = o else { continue }
            var row: [WeatherKind: Double] = [:]
            for k in WeatherKind.allCases {
                let p = max(0, num(o[k.rawValue], 0))
                if p > 0 { row[k] = p }
            }
            if !row.isEmpty { odds[season] = row }
        }
        for k in WeatherKind.allCases {
            gloom[k] = min(max(num(w["gloom"][k.rawValue], gloom[k] ?? 0), 0), 1)
        }
        let room = w["room"], yard = w["yard"], fall = w["fall"]
        roomRain = max(0, int(room["rain"], roomRain))
        roomSnow = max(0, int(room["snow"], roomSnow))
        yardRain = max(0, int(yard["rain"], yardRain))
        yardSnow = max(0, int(yard["snow"], yardSnow))
        stormMul = max(1, num(w["storm_mul"], stormMul))
        rainFall = max(0.05, num(fall["rain"], rainFall))
        snowFall = max(0.01, num(fall["snow"], snowFall))
    }

    /// Шанс вида в сезоне, нормированный (сумма по сезону — 1).
    func chance(_ k: WeatherKind, in s: Season) -> Double {
        let row = odds[s] ?? [:]
        let sum = row.values.reduce(0, +)
        guard sum > 0 else { return k == .clear ? 1 : 0 }
        return (row[k] ?? 0) / sum
    }

    func gloom(of k: WeatherKind) -> Double { gloom[k] ?? 0 }

    /// Частиц для вида погоды: room — за окном комнаты, иначе во дворе.
    func particles(_ k: WeatherKind, room: Bool) -> Int {
        switch k {
        case .clear, .cloudy: return 0
        case .snow: return room ? roomSnow : yardSnow
        case .rain: return room ? roomRain : yardRain
        case .storm: return Int((Double(room ? roomRain : yardRain) * stormMul).rounded())
        }
    }
}

enum Weather {
    /// Номер блока погоды для момента t: местные минуты / длина блока (вниз, и до 1970).
    static func block(_ t: Double, tzOffsetMin: Int, _ cfg: WeatherConfig = .shared) -> Int {
        DayKey.floorDiv(DayKey.minute(t) + tzOffsetMin, cfg.blockHours * 60)
    }

    /// Местные сутки, в которые начинается блок.
    static func day(ofBlock b: Int, _ cfg: WeatherConfig = .shared) -> Int {
        DayKey.floorDiv(b * cfg.blockHours * 60, 1440)
    }

    static func season(ofBlock b: Int, _ cfg: WeatherConfig = .shared) -> Season {
        Season(day: day(ofBlock: b, cfg))
    }

    /// Псевдопогода в момент t по поясу на этот момент.
    static func at(_ t: Double, _ cfg: WeatherConfig = .shared) -> WeatherKind {
        at(t, tzOffsetMin: Clock.tzOffsetMin(at: t), cfg)
    }

    static func at(_ t: Double, tzOffsetMin: Int, _ cfg: WeatherConfig = .shared) -> WeatherKind {
        kind(block: block(t, tzOffsetMin: tzOffsetMin, cfg), cfg)
    }

    /// Погода блока b: с шансом stay — как у прошлого блока (если та уместна в этом сезоне), иначе свой бросок
    /// по шансам сезона. Гроза не тянется: повтор грозы — уже просто дождь.
    static func kind(block b: Int, _ cfg: WeatherConfig = .shared) -> WeatherKind {
        kind(block: b, depth: 0, cfg)
    }

    private static func kind(block b: Int, depth: Int, _ cfg: WeatherConfig) -> WeatherKind {
        let season = season(ofBlock: b, cfg)
        let h = StableRandom.mix(StableHash.fnv1a("weather:\(b)"))
        let u1 = Double(h & 0xFFFF_FFFF) / 4_294_967_296
        let u2 = Double(h >> 32) / 4_294_967_296
        let rolled = roll(u2, season, cfg)
        let stays = u1 < cfg.stay
        // Прошлый блок нужен для повтора и для грозы; считается один раз (цепочка не глубже stayDepth).
        let prev = depth < cfg.stayDepth && (stays || rolled == .storm)
            ? kind(block: b - 1, depth: depth + 1, cfg) : nil
        if stays, let prev {
            let next: WeatherKind = prev == .storm ? .rain : prev
            if cfg.chance(next, in: season) > 0 { return next }
        }
        // Гроза короткая: две подряд не бывает, вторая — уже дождь.
        if rolled == .storm, prev == .storm {
            return cfg.chance(.rain, in: season) > 0 ? .rain : .cloudy
        }
        return rolled
    }

    private static func roll(_ u: Double, _ season: Season, _ cfg: WeatherConfig) -> WeatherKind {
        var acc = 0.0
        for k in WeatherKind.allCases {
            let p = cfg.chance(k, in: season)
            guard p > 0 else { continue }
            acc += p
            if u < acc { return k }
        }
        return WeatherKind.allCases.last { cfg.chance($0, in: season) > 0 } ?? .clear
    }

    /// Когда кончается блок, в котором t: следующая смена погоды не раньше.
    static func blockEnd(_ t: Double, tzOffsetMin: Int, _ cfg: WeatherConfig = .shared) -> Double {
        Double((block(t, tzOffsetMin: tzOffsetMin, cfg) + 1) * cfg.blockHours * 60 - tzOffsetMin) * 60
    }

    // MARK: Что показывать

    /// Закреплённая погода (чипы «Погода в комнате» в каталоге превью). В файл не пишется, живёт до перезапуска.
    nonisolated(unsafe) static var pinned: WeatherKind?

    /// PET_WEATHER=<clear|cloudy|rain|storm|snow> — погода для снимков и UI-тестов (и для отладки на телефоне).
    static let forced: WeatherKind? = Env.value("PET_WEATHER").flatMap(WeatherKind.init(rawValue:))

    /// Погода для показа: закреплённая, из PET_WEATHER, под тестами — ясно (снимки и строки не меняются
    /// от даты прогона), иначе по часам.
    static func shown(at t: Double, tzOffsetMin: Int) -> WeatherKind {
        if let p = pinned { return p }
        if let f = forced { return f }
        if underTest { return .clear }
        return at(t, tzOffsetMin: tzOffsetMin)
    }

    /// Под тестами: Xcode (Env) или swift test на Linux, где XCTestConfigurationFilePath нет, а бинарник — *.xctest.
    static let underTest: Bool = Env.isTesting
        || (ProcessInfo.processInfo.arguments.first.map { $0.hasSuffix(".xctest") || $0.contains(".xctest/") } ?? false)

    static func now() -> WeatherKind {
        let t = Clock.now()
        return shown(at: t, tzOffsetMin: Clock.tzOffsetMin(at: t))
    }

    static func seasonNow() -> Season { Season(day: DayKey.of(Clock.now())) }

    /// Погода во дворе квартала: в Зимнем квартале вместо дождя снег, а зимой снег всегда. Под тестами без
    /// закреплённой погоды — ясно и там (снимки района не зависят от месяца прогона).
    static func now(in d: YardDistrict) -> WeatherKind {
        let w = now()
        if pinned == nil && forced == nil && underTest { return w }
        return w.inDistrict(d, season: seasonNow())
    }
}

/// Реплика о погоде вместо обычной в спокойное время: свой ход PetMind (после воспоминаний и характера),
/// только если на улице не ясно. Ничего не даёт и не отнимает — только слова.
enum WeatherTalk {
    /// Номер хода PetMind, отданного погоде.
    static let turn: UInt64 = PetMind.memoryTurns + PetMind.traitTurns

    static func line(_ f: SaveFile, at t: Double, tzOffsetMin: Int, island: Bool = false,
                     weather: WeatherKind? = nil, lines: Lines = .shared) -> String? {
        let slot = PetMind.slot(t, tzOffsetMin: tzOffsetMin)
        guard PetMind.roll(f, slot: slot) == turn else { return nil }
        let w = weather ?? Weather.shown(at: t, tzOffsetMin: tzOffsetMin)
        guard let key = w.lineKey else { return nil }
        let max = island ? LineLimit.island : LineLimit.widget
        guard let text = lines.pick(island ? "island" : "widget", key, seed: f.petId, slot: slot, maxLen: max)?.text,
              text.count <= max, !text.contains("{") else { return nil }
        return text
    }
}

extension RoomLight {
    /// Свет под погоду: gloom 0…1 приглушает солнце, сереет небо и тинт. Ночью облака почти не видны
    /// (действует вполовину), зато прячут луну и звёзды. gloom 0 — свет как есть (день и ночь не меняются).
    func weathered(_ gloom: Double) -> RoomLight {
        let g = min(max(gloom, 0), 1)
        guard g > 0 else { return self }
        let k = g * (1 - 0.5 * min(max(moon, 0), 1))
        var l = self
        l.tint = tint * RoomRGB.lerp(.white, RoomRGB(0.86, 0.88, 0.92), k)
        l.key = RoomRGB.lerp(key, RoomRGB(hex: 0xdfe4ea), k)
        l.keyI = keyI * (1 - 0.45 * k)
        l.rim = RoomRGB.lerp(rim, RoomRGB(hex: 0xd6dbe2), k)
        l.rimI = rimI * (1 - 0.5 * k)
        let lum = sky.luminance * 0.92
        l.sky = RoomRGB.lerp(sky, RoomRGB(lum, lum * 1.01, lum * 1.05), k)
        l.moon = moon * (1 - 0.7 * g)
        return l
    }
}
