// Волна 39 D: погода и времена года (Weather.swift). Псевдопогода по дате без сети: детерминирована, блоки по
// 4 часа от местной полуночи, частоты по сезонам как в Сербии, снега летом нет, гроза короткая. Только косметика:
// свет, частицы, реплики. Гоняется и на Linux.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let wDay: Double = 86_400

private func configURL() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("config/economy.json")
}

/// Полночь UTC даты y-m-d (секунды от 1970).
private func utc(_ y: Int, _ m: Int, _ d: Int) -> Double {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c.date(from: DateComponents(year: y, month: m, day: d))!.timeIntervalSince1970
}

/// Все блоки года y (UTC) с их сезоном.
private func blocks(year y: Int, _ cfg: WeatherConfig = WeatherConfig()) -> [(season: Season, kind: WeatherKind)] {
    let from = Weather.block(utc(y, 1, 1), tzOffsetMin: 0, cfg)
    let to = Weather.block(utc(y + 1, 1, 1), tzOffsetMin: 0, cfg)
    return (from..<to).map { (Weather.season(ofBlock: $0, cfg), Weather.kind(block: $0, cfg)) }
}

final class WeatherTests: XCTestCase {

    override func tearDown() {
        Weather.pinned = nil
        super.tearDown()
    }

    // MARK: календарь

    func testMonthMatchesCalendar() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        // 1960…2060 через день: и до 1970 (отрицательные дни), и високосные годы.
        var day = DayKey.of(utc(1960, 1, 1), tzOffsetMin: 0)
        let end = DayKey.of(utc(2060, 12, 31), tzOffsetMin: 0)
        while day <= end {
            let date = Date(timeIntervalSince1970: Double(day) * wDay)
            XCTAssertEqual(Season.month(ofDay: day), c.component(.month, from: date), "день \(day)")
            day += 2
        }
    }

    func testSeasonsByMonth() {
        XCTAssertEqual((1...12).map { Season(month: $0) },
                       [.winter, .winter, .spring, .spring, .spring, .summer,
                        .summer, .summer, .autumn, .autumn, .autumn, .winter])
        XCTAssertEqual(Season(day: DayKey.of(utc(2026, 10, 27), tzOffsetMin: 0)), .autumn)
        XCTAssertEqual(Season(day: DayKey.of(utc(2026, 12, 1), tzOffsetMin: 0)), .winter)
        XCTAssertEqual(Season(day: DayKey.of(utc(2027, 2, 28), tzOffsetMin: 0)), .winter)
        XCTAssertEqual(Season(day: DayKey.of(utc(2027, 3, 1), tzOffsetMin: 0)), .spring)
    }

    // MARK: детерминированность и блоки

    func testSameMomentSameWeather() {
        let t0 = utc(2026, 10, 27) + 13 * 3600
        for k in 0..<500 {
            let t = t0 + Double(k) * 3917
            for tz in [0, 60, 120, -300, 330] {
                let a = Weather.at(t, tzOffsetMin: tz)
                XCTAssertEqual(a, Weather.at(t, tzOffsetMin: tz))
                XCTAssertEqual(a, Weather.kind(block: Weather.block(t, tzOffsetMin: tz)))
            }
        }
        // Своя копия конфига с теми же цифрами — та же погода (нет скрытого состояния).
        let cfg = WeatherConfig()
        XCTAssertEqual((0..<200).map { Weather.kind(block: 120_000 + $0, cfg) },
                       (0..<200).map { Weather.kind(block: 120_000 + $0, WeatherConfig()) })
    }

    /// Погода меняется только на границах блоков: 0:00, 4:00, 8:00… по местному времени.
    func testWeatherChangesOnlyOnBlockEdges() {
        let cfg = WeatherConfig()
        XCTAssertEqual(cfg.blockHours, 4)
        for tz in [0, 120, -420] {
            let start = utc(2026, 4, 1) - Double(tz) * 60   // местная полночь 1 апреля
            var prev = Weather.at(start, tzOffsetMin: tz, cfg)
            var changes = 0
            for m in stride(from: 10, to: 20 * 24 * 60, by: 10) {
                let t = start + Double(m) * 60
                let k = Weather.at(t, tzOffsetMin: tz, cfg)
                if k != prev {
                    changes += 1
                    XCTAssertEqual(m % (cfg.blockHours * 60), 0, "смена в \(m / 60):\(m % 60) местного, пояс \(tz)")
                }
                prev = k
            }
            XCTAssertGreaterThan(changes, 10, "за 20 дней погода меняется")
            XCTAssertEqual(Weather.blockEnd(start + 3600, tzOffsetMin: tz, cfg), start + 4 * 3600)
        }
    }

    /// Блоки липкие: дождь в среднем идёт дольше одного блока, но не неделями.
    func testRunLengths() {
        var runs: [Int] = []
        var stormRuns: [Int] = []
        for y in 2025...2028 {
            let b = blocks(year: y).map(\.kind)
            var i = 0
            while i < b.count {
                var j = i
                while j + 1 < b.count, b[j + 1] == b[i] { j += 1 }
                runs.append(j - i + 1)
                if b[i] == .storm { stormRuns.append(j - i + 1) }
                i = j + 1
            }
        }
        let mean = Double(runs.reduce(0, +)) / Double(runs.count)
        XCTAssertGreaterThan(mean, 1.6, "погода держится несколько блоков")
        XCTAssertLessThan(mean, 4.0, "и не стоит неделями")
        XCTAssertLessThanOrEqual(runs.max() ?? 0, 30, "одна погода не дольше 5 суток")
        XCTAssertFalse(stormRuns.isEmpty, "гроза бывает")
        XCTAssertEqual(stormRuns.max(), 1, "гроза — не дольше одного блока")
    }

    // MARK: сезоны

    /// Частоты на годе блоков — в коридорах вокруг шансов конфига; так 4 года подряд.
    func testSeasonFrequenciesStayInCorridors() {
        let cfg = WeatherConfig()
        for y in 2025...2028 {
            var count: [Season: [WeatherKind: Int]] = [:]
            var total: [Season: Int] = [:]
            for (s, k) in blocks(year: y) {
                count[s, default: [:]][k, default: 0] += 1
                total[s, default: 0] += 1
            }
            func share(_ s: Season, _ k: WeatherKind) -> Double {
                Double(count[s]?[k] ?? 0) / Double(max(1, total[s] ?? 0))
            }
            for s in Season.allCases {
                for k in WeatherKind.allCases where k != .storm && k != .rain {
                    let p = cfg.chance(k, in: s)
                    XCTAssertEqual(share(s, k), p, accuracy: 0.13, "\(y) \(s) \(k)")
                }
                // Дождь и гроза вместе: повтор грозы превращается в дождь.
                let wet = cfg.chance(.rain, in: s) + cfg.chance(.storm, in: s)
                XCTAssertEqual(share(s, .rain) + share(s, .storm), wet, accuracy: 0.13, "\(y) \(s) мокро")
            }
            // Характер сезонов (ТЗ): летом чаще всего ясно, весной и осенью дождь чаще, чем летом и зимой.
            XCTAssertGreaterThan(share(.summer, .clear), 0.45, "\(y): лето ясное")
            XCTAssertGreaterThan(share(.summer, .clear), share(.autumn, .clear))
            XCTAssertGreaterThan(share(.autumn, .rain), share(.summer, .rain), "\(y): осень дождливее лета")
            XCTAssertGreaterThan(share(.spring, .rain), share(.winter, .rain), "\(y): весна дождливее зимы")
            XCTAssertGreaterThan(share(.winter, .snow), 0.15, "\(y): зимой бывает снег")
            XCTAssertGreaterThan(share(.summer, .storm), 0, "\(y): летом бывает гроза")
            XCTAssertLessThan(share(.summer, .storm), 0.12, "\(y): гроза — изредка")
        }
    }

    func testNoSnowOutsideWinterAndNoWinterStorm() {
        for y in 2020...2031 {
            for (s, k) in blocks(year: y) {
                if s != .winter { XCTAssertNotEqual(k, .snow, "\(y) \(s): снег не в сезон") }
                if s == .winter { XCTAssertNotEqual(k, .storm, "\(y): гроза зимой") }
            }
        }
    }

    /// Летом снега нет и по местному времени (повтор зимней погоды через границу сезона не протаскивает снег).
    func testSnowNeverCrossesIntoSpring() {
        for y in 2020...2040 {
            let t = utc(y, 3, 1)
            for h in 0..<72 {
                for tz in [0, 60, 120] {
                    XCTAssertNotEqual(Weather.at(t + Double(h) * 3600 - Double(tz) * 60, tzOffsetMin: tz), .snow,
                                      "\(y)-03-01 +\(h) ч, пояс \(tz)")
                }
            }
        }
    }

    // MARK: конфиг

    func testConfigFileMatchesDefaults() throws {
        let data = try Data(contentsOf: configURL())
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(WeatherConfig(json: json), WeatherConfig(), "config/economy.json и умолчания в Swift разошлись")
        XCTAssertEqual(WeatherConfig(json: .null), WeatherConfig())
    }

    /// Волна 40 E: длина блока, не делящая сутки, не даёт блока через полночь — берётся делитель 24 вниз.
    func testBlockHoursDivideDay() throws {
        for (raw, want) in [(5, 4), (7, 6), (9, 8), (13, 12), (24, 24), (1, 1), (0, 1), (40, 24)] {
            let json = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"weather": {"block_hours": \#(raw)}}"#.utf8))
            let c = WeatherConfig(json: json)
            XCTAssertEqual(c.blockHours, want, "\(raw)")
            // Местная полночь — всегда начало блока, и блок не переходит в другие сутки.
            for tz in [-300, 0, 60, 345] {
                let midnight = utc(2026, 3, 1) - Double(tz) * 60
                let b = Weather.block(midnight, tzOffsetMin: tz, c)
                XCTAssertEqual(Weather.block(midnight - 1, tzOffsetMin: tz, c), b - 1)
                XCTAssertEqual(Weather.day(ofBlock: b, c), Weather.day(ofBlock: b + 24 / c.blockHours - 1, c))
            }
        }
    }

    func testConfigReadsOverrides() throws {
        let raw = #"{"weather": {"block_hours": 6, "odds": {"summer": {"clear": 1}}, "room": {"rain": 3}, "fall": {"snow": 0.5}}}"#
        let c = WeatherConfig(json: try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)))
        XCTAssertEqual(c.blockHours, 6)
        XCTAssertEqual(c.chance(.clear, in: .summer), 1)
        XCTAssertEqual(c.chance(.rain, in: .summer), 0)
        XCTAssertEqual(c.odds[.winter], WeatherConfig().odds[.winter])
        XCTAssertEqual(c.roomRain, 3)
        XCTAssertEqual(c.snowFall, 0.5)
        // Всё лето ясно — так и есть на каждом блоке.
        let from = Weather.block(utc(2026, 7, 1), tzOffsetMin: 0, c)
        XCTAssertTrue((from..<from + 100).allSatisfy { Weather.kind(block: $0, c) == .clear })
    }

    func testChancesAreNormalised() {
        let cfg = WeatherConfig()
        for s in Season.allCases {
            let sum = WeatherKind.allCases.map { cfg.chance($0, in: s) }.reduce(0, +)
            XCTAssertEqual(sum, 1, accuracy: 1e-9, "\(s)")
            XCTAssertEqual(cfg.chance(.snow, in: s) > 0, s == .winter, "\(s): снег только зимой")
        }
    }

    /// Частиц мало: 60 кадров/с на iPhone Air (ТЗ).
    func testParticlesAreFew() {
        let cfg = WeatherConfig()
        for k in WeatherKind.allCases {
            XCTAssertLessThanOrEqual(cfg.particles(k, room: true), 24)
            XCTAssertLessThanOrEqual(cfg.particles(k, room: false), 60)
            XCTAssertEqual(cfg.particles(k, room: true) > 0, k.falls)
        }
        XCTAssertGreaterThan(cfg.particles(.storm, room: false), cfg.particles(.rain, room: false))
    }

    // MARK: показ

    func testShownUnderTestsIsClearUnlessPinned() {
        let t = utc(2026, 11, 3) + 15 * 3600
        XCTAssertEqual(Weather.shown(at: t, tzOffsetMin: 60), .clear, "тесты не зависят от даты прогона")
        Weather.pinned = .snow
        XCTAssertEqual(Weather.shown(at: t, tzOffsetMin: 60), .snow)
        XCTAssertEqual(Weather.now(), .snow)
        Weather.pinned = nil
        XCTAssertEqual(Weather.now(), .clear)
    }

    func testWinterDistrictTurnsWetIntoSnow() {
        XCTAssertEqual(WeatherKind.rain.inDistrict(.winter, season: .summer), .snow)
        XCTAssertEqual(WeatherKind.storm.inDistrict(.winter, season: .autumn), .snow)
        XCTAssertEqual(WeatherKind.clear.inDistrict(.winter, season: .winter), .snow, "зимой в Зимнем квартале — снег")
        XCTAssertEqual(WeatherKind.cloudy.inDistrict(.winter, season: .summer), .cloudy)
        XCTAssertEqual(WeatherKind.clear.inDistrict(.winter, season: .summer), .clear)
        for d in YardDistrict.allCases where d != .winter {
            for k in WeatherKind.allCases {
                XCTAssertEqual(k.inDistrict(d, season: .winter), k, "\(d): на крыше дождь тоже идёт")
            }
        }
        // Под тестами двор без закреплённой погоды ясный в любом квартале (снимки не зависят от месяца).
        XCTAssertEqual(Weather.now(in: .winter), .clear)
        Weather.pinned = .rain
        XCTAssertEqual(Weather.now(in: .winter), .snow)
        XCTAssertEqual(Weather.now(in: .roof), .rain)
    }

    // MARK: свет

    func testClearLightIsUntouched() {
        for l in [RoomLight.day, .evening, .night, RoomLight.at(phase: 0.4)] {
            XCTAssertEqual(l.weathered(0), l, "ясно — свет как был")
        }
    }

    func testGloomDimsDayAndHidesMoon() {
        let cfg = WeatherConfig()
        var last = RoomLight.day.keyI
        for k in [WeatherKind.cloudy, .rain, .storm] {
            let l = RoomLight.day.weathered(cfg.gloom(of: k))
            XCTAssertLessThan(l.keyI, last, "\(k): темнее")
            XCTAssertGreaterThan(l.keyI, RoomLight.day.keyI * 0.5, "\(k): приглушён, а не ночь")
            XCTAssertLessThan(l.tint.luminance, 1)
            XCTAssertEqual(l.lamp, 0, "днём лампа не загорается")
            last = l.keyI
        }
        let night = RoomLight.night.weathered(cfg.gloom(of: .rain))
        XCTAssertLessThan(night.moon, RoomLight.night.moon, "в дождь луну видно хуже")
        XCTAssertEqual(night.lamp, RoomLight.night.lamp, "ночник как был")
        // Ночью облака действуют вполовину: ночь не проваливается в черноту.
        XCTAssertGreaterThan(night.tint.luminance, RoomLight.night.tint.luminance * 0.85)
    }

    // MARK: реплики

    func testWeatherLinesExistAndFit() throws {
        let lines = Lines.shared
        guard !(lines.sections["widget"] ?? [:]).isEmpty else { throw XCTSkip("lines.json нет в бандле") }
        for k in WeatherKind.allCases {
            guard let key = k.lineKey else { continue }
            let w = try XCTUnwrap(lines.sections["widget"]?[key], "widget.\(key)")
            let i = try XCTUnwrap(lines.sections["island"]?[key], "island.\(key)")
            XCTAssertGreaterThanOrEqual(w.count, 3)
            XCTAssertGreaterThanOrEqual(i.count, 2)
            XCTAssertTrue(w.allSatisfy { $0.text.count <= LineLimit.widget }, key)
            XCTAssertTrue(i.allSatisfy { $0.text.count <= LineLimit.island }, key)
        }
    }

    func testWeatherTalkTakesOwnTurnOnly() throws {
        guard !(Lines.shared.sections["widget"] ?? [:]).isEmpty else { throw XCTSkip("lines.json нет в бандле") }
        var f = SaveFile.fresh(now: utc(2026, 10, 27))
        f.petId = "weather-pet"
        var spoke = 0
        for k in 0..<120 {
            let t = utc(2026, 10, 27) + Double(k) * 2 * 3600 + 600
            let turn = PetMind.roll(f, slot: PetMind.slot(t, tzOffsetMin: 0))
            let rain = WeatherTalk.line(f, at: t, tzOffsetMin: 0, weather: .rain)
            XCTAssertNil(WeatherTalk.line(f, at: t, tzOffsetMin: 0, weather: .clear), "в ясную погоду молчит")
            if turn == WeatherTalk.turn {
                let text = try XCTUnwrap(rain)
                XCTAssertTrue(Lines.shared.sections["widget"]?["weather_rain"]?.contains { $0.text == text } ?? false)
                XCTAssertNotNil(WeatherTalk.line(f, at: t, tzOffsetMin: 0, island: true, weather: .snow))
                spoke += 1
            } else {
                XCTAssertNil(rain, "чужой ход")
            }
        }
        XCTAssertGreaterThan(spoke, 3, "ход погоды — примерно 1 из 8")
        XCTAssertLessThan(spoke, 40)
    }

    /// Presenter в ход погоды говорит о ней (закреплённый дождь), без погоды — обычная строка.
    func testPresenterSaysWeather() throws {
        guard !(Lines.shared.sections["widget"] ?? [:]).isEmpty else { throw XCTSkip("lines.json нет в бандле") }
        var f = SaveFile.fresh(now: utc(2026, 10, 27))
        f.petId = "weather-pet"
        let r = Catalog.rules
        let owner = Owner(bedMin: r.bedMin, wakeMin: r.wakeMin, tzOffsetMin: 0)
        var used = 0
        for d in 1..<8 {
            for h in [11.0, 13, 15, 17] {
                let t = utc(2026, 10, 27) + Double(d) * wDay + h * 3600
                guard PetMind.roll(f, slot: PetMind.slot(t, tzOffsetMin: 0)) == WeatherTalk.turn else { continue }
                var s = PetEngine.newPet(r, t: t)
                for n in Need.allCases { s.needs[n] = 100 }
                Weather.pinned = .rain
                let rainy = Presenter.make(file: f, pet: s, owner: owner, at: t)
                Weather.pinned = .clear
                let clear = Presenter.make(file: f, pet: s, owner: owner, at: t)
                Weather.pinned = nil
                let said = WeatherTalk.line(f, at: t, tzOffsetMin: 0, weather: .rain)
                guard rainy.line == said else { continue }   // спокойного «ok» могло не быть (утро, вечер)
                used += 1
                XCTAssertNotEqual(clear.line, said, "в ясную погоду — обычная реплика")
                XCTAssertEqual(rainy.mood, clear.mood, "погода не меняет настроение")
            }
        }
        XCTAssertGreaterThan(used, 0, "погода доходит до пузыря")
    }
}
