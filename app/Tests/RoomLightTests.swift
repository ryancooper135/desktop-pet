// Свет комнаты по времени и теме (RoomLight.swift): фаза от сна хозяина, режимы настройки «Комната вечером»,
// интерполяция ключевых кадров, полдень в UI-тестах, подложка под статус-бар и поле в сейве.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let lT0: Double = 1_760_000_000

final class RoomLightTests: XCTestCase {
    private func hm(_ h: Int, _ m: Int = 0) -> Double { Double(h * 60 + m) }
    private let bed = 23 * 60 + 30, wake = 7 * 60 + 30

    private func dusk(_ h: Int, _ m: Int = 0, bed: Int? = nil, wake: Int? = nil) -> Double {
        RoomClock.dusk(localMin: hm(h, m), bedMin: bed ?? self.bed, wakeMin: wake ?? self.wake)
    }

    // MARK: фаза по часам

    func testDefaultScheduleKeyPoints() {
        XCTAssertEqual(dusk(12), 0, "днём — день")
        XCTAssertEqual(dusk(9), 0, "через час после подъёма уже день")
        XCTAssertEqual(dusk(17, 59), 0, "до заката день")
        XCTAssertEqual(dusk(19, 30), 1, accuracy: 1e-9, "после заката вечер")
        XCTAssertEqual(dusk(20, 30), 1, "вечер")
        XCTAssertEqual(dusk(23), 1, "за полчаса до сна ещё вечер")
        XCTAssertEqual(dusk(23, 45), 2, accuracy: 1e-9, "через 15 минут после сна хозяина — ночь, Шиба спит")
        XCTAssertEqual(dusk(2), 2, "ночь")
        XCTAssertEqual(dusk(7, 29), 2, accuracy: 1e-3, "перед подъёмом ночь")
        XCTAssertEqual(dusk(8), 1, accuracy: 1e-9, "середина рассвета — как вечер")
    }

    func testMonotonicTransitions() {
        var last = -1.0
        for m in stride(from: 18 * 60, through: 19 * 60 + 30, by: 5) {
            let d = dusk(m / 60, m % 60)
            XCTAssertGreaterThanOrEqual(d, last, "закат не откатывается назад в \(m)")
            XCTAssert((0...1).contains(d))
            last = d
        }
        last = 0.99
        for m in stride(from: 23 * 60, through: 23 * 60 + 45, by: 5) {
            let d = dusk(m / 60, m % 60)
            XCTAssertGreaterThanOrEqual(d, last)
            last = d
        }
        XCTAssertEqual(dusk(18, 45), 0.5, accuracy: 1e-9, "середина заката")
    }

    func testEarlyBedPullsSunsetEarlier() {
        // Ложится в 18:30: ночь с 18:45, вечер начинается не позже 18:00.
        let b = 18 * 60 + 30
        XCTAssertEqual(dusk(19, bed: b), 2)
        XCTAssertEqual(dusk(18, 50, bed: b), 2)
        XCTAssertEqual(dusk(18, 0, bed: b), 1, "за полчаса до сна — уже вечер")
        XCTAssertEqual(dusk(12, bed: b), 0)
        var last = 0.0
        for m in stride(from: 12 * 60, through: 19 * 60, by: 5) {
            let d = dusk(m / 60, m % 60, bed: b)
            XCTAssertGreaterThanOrEqual(d, last, "без скачков назад в \(m)")
            last = d
        }
    }

    func testLateBedAfterMidnight() {
        let b = 1 * 60 + 30
        XCTAssertEqual(dusk(23, 59, bed: b), 1, "в полночь ещё вечер")
        XCTAssertEqual(dusk(1, 45, bed: b), 2, accuracy: 1e-9)
        XCTAssertEqual(dusk(4, bed: b), 2)
        XCTAssertEqual(dusk(12, bed: b), 0)
    }

    func testOtherWakeTime() {
        let w = 10 * 60
        XCTAssertEqual(dusk(9, wake: w), 2, "до подъёма в 10:00 ещё ночь")
        XCTAssertEqual(dusk(11, wake: w), 0)
        XCTAssertEqual(dusk(20, wake: w), 1)
    }

    func testAllValuesInRange() {
        for b in stride(from: 0, to: 1440, by: 85) {
            for w in stride(from: 0, to: 1440, by: 95) {
                for m in stride(from: 0, to: 1440, by: 20) {
                    let d = RoomClock.dusk(localMin: Double(m), bedMin: b, wakeMin: w)
                    XCTAssert(d.isFinite && d >= 0 && d <= 2, "bed \(b) wake \(w) m \(m): \(d)")
                }
            }
        }
    }

    // MARK: режимы

    func testModes() {
        func ph(_ mode: RoomEveningMode, dark: Bool, _ h: Int) -> Double {
            RoomClock.phase(mode: mode, dark: dark, localMin: hm(h), bedMin: bed, wakeMin: wake)
        }
        // По времени: тема не влияет.
        XCTAssertEqual(ph(.byTime, dark: false, 12), 0)
        XCTAssertEqual(ph(.byTime, dark: true, 12), 0)
        XCTAssertEqual(ph(.byTime, dark: false, 21), 1)
        XCTAssertEqual(ph(.byTime, dark: false, 2), 2)
        // По теме: светлая — день всегда, тёмная — не светлее вечера, ночью ночь.
        XCTAssertEqual(ph(.byTheme, dark: false, 2), 0)
        XCTAssertEqual(ph(.byTheme, dark: true, 12), 1)
        XCTAssertEqual(ph(.byTheme, dark: true, 21), 1)
        XCTAssertEqual(ph(.byTheme, dark: true, 2), 2)
        // Всегда день.
        for h in [2, 12, 21] {
            XCTAssertEqual(ph(.alwaysDay, dark: true, h), 0)
            XCTAssertEqual(ph(.alwaysDay, dark: false, h), 0)
        }
    }

    func testModeStorage() {
        XCTAssertEqual(RoomEveningMode.standard, .byTime, "по умолчанию — по времени (DECISIONS.md)")
        XCTAssertEqual(RoomEveningMode(stored: nil), .standard)
        XCTAssertEqual(RoomEveningMode(stored: "мусор"), .standard)
        for m in RoomEveningMode.allCases {
            XCTAssertEqual(RoomEveningMode(stored: m.rawValue), m)
            XCTAssertFalse(m.title.isEmpty)
        }
        XCTAssertEqual(RoomEveningMode.allCases.map(\.title), ["По времени", "По теме", "Всегда день"])
    }

    // MARK: свет

    func testKeyframesAndLerp() {
        XCTAssertEqual(RoomLight.at(phase: 0), .day)
        XCTAssertEqual(RoomLight.at(phase: 1), .evening)
        XCTAssertEqual(RoomLight.at(phase: 2), .night)
        XCTAssertEqual(RoomLight.at(phase: -3), .day, "вне диапазона зажимается")
        XCTAssertEqual(RoomLight.at(phase: 9), .night)
        XCTAssertEqual(RoomLight.at(phase: .nan), .day)
        let half = RoomLight.at(phase: 0.5)
        XCTAssertEqual(half.keyI, (RoomLight.day.keyI + RoomLight.evening.keyI) / 2, accuracy: 1e-9)
        XCTAssertEqual(half.tint.g, (1 + RoomLight.evening.tint.g) / 2, accuracy: 1e-9)
        XCTAssertEqual(RoomLight.at(phase: 1.5).moon, 0.5, accuracy: 1e-9)
    }

    func testDayIsUnchangedRoom() {
        // Днём комната ровно как до волны 10: снимки ui-01 и соседей не меняются.
        let d = RoomLight.day
        XCTAssertEqual(d.tint, .white)
        XCTAssertEqual(d.keyI, 2200)
        XCTAssertEqual(d.fillI, 700)
        XCTAssertEqual(d.rimI, 900)
        XCTAssertEqual(d.key, RoomRGB(hex: 0xfff3e2))
        XCTAssertEqual(d.sky, RoomRGB(hex: 0xcfe9f7))
        XCTAssertEqual(d.lamp, 0)
        XCTAssertEqual(d.moon, 0)
        XCTAssertEqual(d.vignette, 0)
    }

    func testEveningWarmNightDarkBlue() {
        let e = RoomLight.evening, n = RoomLight.night
        XCTAssertGreaterThan(e.tint.r, e.tint.b, "вечер тёплый")
        XCTAssertGreaterThan(e.key.r, e.key.b)
        XCTAssertLessThan(e.wallLuminance, RoomLight.day.wallLuminance, "стены вечером приглушены")
        XCTAssertGreaterThan(n.tint.b, n.tint.r, "ночь синяя")
        XCTAssertLessThan(n.wallLuminance, e.wallLuminance)
        XCTAssertLessThan(n.sky.luminance, 0.25, "небо ночью тёмное")
        XCTAssertGreaterThan(n.moon, 0.9)
        XCTAssertGreaterThan(n.lamp, 0, "ночник, чтобы спящий пёс читался")
        XCTAssertGreaterThan(n.keyI, 0)
    }

    // MARK: статус-бар

    func testStatusScrim() {
        XCTAssertFalse(RoomClock.needsStatusScrim(phase: 0, dark: false), "день, светлая тема — чёрные часы на светлой стене")
        XCTAssertTrue(RoomClock.needsStatusScrim(phase: 0, dark: true), "день, тёмная тема — белые часы на светлой стене")
        XCTAssertFalse(RoomClock.needsStatusScrim(phase: 2, dark: true), "ночь, тёмная тема — белые часы на тёмной стене")
        XCTAssertTrue(RoomClock.needsStatusScrim(phase: 2, dark: false), "ночь, светлая тема — чёрные часы на тёмной стене")
        XCTAssertFalse(RoomClock.needsStatusScrim(phase: 1, dark: false), "вечер ещё светлый")
    }

    // MARK: время

    func testLocalMinuteAndUITestNoon() {
        XCTAssertEqual(RoomClock.localMinute(now: 0, tzOffsetMin: 60), 60)
        XCTAssertEqual(RoomClock.localMinute(now: 0, tzOffsetMin: -90), 1350)
        XCTAssertEqual(RoomClock.localMinute(now: 3600 * 25, tzOffsetMin: 0), 60)
        let t = lT0 + 1234
        XCTAssertEqual(RoomClock.now(clock: t, uiTest: false, petNowSet: false, tzOffsetMin: 120), t)
        XCTAssertEqual(RoomClock.now(clock: t, uiTest: true, petNowSet: true, tzOffsetMin: 120), t)
        let noon = RoomClock.now(clock: t, uiTest: true, petNowSet: false, tzOffsetMin: 120)
        XCTAssertEqual(RoomClock.localMinute(now: noon, tzOffsetMin: 120), 720, accuracy: 1e-6)
        XCTAssertLessThan(abs(noon - t), 86_400)
    }

    // MARK: сейв

    func testSaveFieldTopLevelAndOldSave() throws {
        var f = SaveFile.fresh(now: lT0)
        XCTAssertNil(f.roomEvening)
        XCTAssertEqual(f.roomEveningMode, .byTime)
        var data = try JSONEncoder().encode(f)
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(obj["roomEvening"], "по умолчанию в файл не пишется")

        f.roomEvening = RoomEveningMode.alwaysDay.rawValue
        data = try JSONEncoder().encode(f)
        obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["roomEvening"] as? String, "day", "верхним уровнем")
        let back = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(back.roomEveningMode, .alwaysDay)
        XCTAssertEqual(back.island.enabled, f.island.enabled, "соседние вложенные поля целы")
        XCTAssertEqual(back.catchBest, f.catchBest)

        // Битое значение не ломает сейв: читается как по умолчанию.
        obj["roomEvening"] = 42
        let bad = try JSONSerialization.data(withJSONObject: obj)
        let back2 = try JSONDecoder().decode(SaveFile.self, from: bad)
        XCTAssertNil(back2.roomEvening)
        XCTAssertEqual(back2.roomEveningMode, .standard)
        XCTAssertEqual(back2.pet.hearts, f.pet.hearts)
    }

    func testScheduleFromSave() {
        var f = SaveFile.fresh(now: lT0)
        XCTAssertEqual(f.roomSchedule, RoomSchedule.standard)
        f.owner.bedMin = 22 * 60
        f.roomEvening = RoomEveningMode.byTheme.rawValue
        let s = f.roomSchedule
        XCTAssertEqual(s.mode, .byTheme)
        XCTAssertEqual(s.bedMin, 22 * 60)
        XCTAssertNotEqual(s, RoomSchedule.standard)
        // 03:00 UTC при поясе 0: по времени — ночь; по теме в светлой — день.
        let t3 = 3.0 * 3600
        XCTAssertEqual(RoomSchedule.standard.phase(dark: false, now: t3, tzOffsetMin: 0), 2, accuracy: 1e-9)
        XCTAssertEqual(s.phase(dark: false, now: t3, tzOffsetMin: 0), 0)
        XCTAssertEqual(s.phase(dark: true, now: t3, tzOffsetMin: 0), 2, accuracy: 1e-9)
    }
}
