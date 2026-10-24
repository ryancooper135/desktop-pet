// Волна 33 B: рост щенок → подросток → взрослый (Growth.swift). Очки за сутки ухода по §4
// RESEARCH/20-tycoon-design.md: идеальный уход — взрослый на 35-й день, забытый — около сотого; сутки по DayKey
// один раз, часы назад ничего не дают, побег не растит; вид плавный, у щенка ×0,65. Гоняется и на Linux.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// 10:00 местного времени: сутки рождения начинаются не с полуночи.
private let gT0: Double = DayKey.start(DayKey.of(1_760_000_000)) + 10 * 3600
private let hourS: Double = 3600

private func gFile(at t: Double = gT0) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = "growth-pet"
    Growth.observe(&f, now: t)   // первый взгляд в момент рождения: старых дней нет
    return f
}

/// Каждый час: наблюдение роста, догон ядра (как PetRunner.catchUp), потом забота — все шкалы полные, сердца
/// полные, касание из приложения. care = false — пса не трогают.
private func live(_ f: inout SaveFile, until end: Double, care: Bool = true) {
    var t = f.growth.t ?? f.pet.t
    while t < end {
        t = min(end, t + hourS)
        Growth.observe(&f, now: t)
        let r = ItemPerks.rules(f)
        if f.pet.alive { f.pet = PetEngine.advance(f.pet, r, f.owner, t) }
        guard care, f.pet.alive else { continue }
        for n in Array(f.pet.needs.keys) { f.pet.needs[n] = 100 }
        f.pet.hearts = PetEngine.maxHearts(f.pet, r)
        f.log("act.pet", t: t, source: .app, ok: true)
    }
}

private func configURL() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("config/wave33/growth.json")
}

final class GrowthTests: XCTestCase {

    // MARK: сейв

    func testEmptyIsNotWritten() throws {
        let f = SaveFile.fresh(now: 1_760_054_400)
        let data = try JSONEncoder().encode(f)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(obj?["growth"], "пустое поле не пишется в сейв")
        XCTAssertNoThrow(try JSONDecoder().decode(SaveFile.self, from: data))
    }

    func testRoundTripKeepsLog() throws {
        var f = gFile()
        live(&f, until: gT0 + 30 * hourS)
        XCTAssertFalse(f.growth.isEmpty)
        let back = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back.growth, f.growth)
    }

    func testDecodesTolerantly() throws {
        let raw = #"{"points": "много", "day": 20000, "t": 1760000000, "open": {"d": 20000, "awake": "x"}}"#
        let g = try JSONDecoder().decode(GrowthLog.self, from: Data(raw.utf8))
        XCTAssertEqual(g.points, 0, "мусор в очках — ноль, а не отказ всего сейва")
        XCTAssertEqual(g.day, 20000)
        XCTAssertEqual(g.open?.d, 20000)
        XCTAssertEqual(g.open?.awake, 0)
    }

    // MARK: конфиг

    func testConfigFileMatchesDefaults() throws {
        let data = try Data(contentsOf: configURL())
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(GrowthConfig(json: json), GrowthConfig(), "config/wave33/growth.json и умолчания в Swift разошлись")
        XCTAssertEqual(GrowthConfig.shared, GrowthConfig(json: json), "раздел growth в economy.json расходится с волной 33")
        XCTAssertEqual(GrowthConfig(json: .null), GrowthConfig())
    }

    func testConfigReadsOverrides() throws {
        let raw = #"{"growth": {"phases": {"teen": 5, "adult": 20}, "mods": {"teen": {"fun_decay_x": 1.3, "bad": 2}}}}"#
        let c = GrowthConfig(json: try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)))
        XCTAssertEqual(c.teen, 5)
        XCTAssertEqual(c.adult, 20)
        XCTAssertEqual(c.mods[.teen], ["fun_decay_x": 1.3], "только ключи _x")
        XCTAssertEqual(c.mods[.puppy], GrowthConfig().mods[.puppy])
    }

    // MARK: формула

    func testDayPointsFormula() {
        let c = GrowthConfig()
        XCTAssertEqual(Growth.dayPoints(hearts: 4, calm: 1, visit: true, c), 1, accuracy: 1e-12, "идеальный день")
        XCTAssertEqual(Growth.dayPoints(hearts: 5, calm: 1, visit: true, cozy: 80, c), 1, accuracy: 1e-12,
                       "уют не поднимает выше 1: взрослый не раньше 35-го дня")
        XCTAssertEqual(Growth.dayPoints(hearts: 1, calm: 0, visit: false, c), 0.34375, accuracy: 1e-12, "забыт")
        XCTAssertEqual(Growth.dayPoints(hearts: 0, calm: 0, visit: false, c), 0.25, accuracy: 1e-12,
                       "плохой уход замедляет, но не останавливает")
        XCTAssertEqual(Growth.dayPoints(hearts: 1, calm: 0, visit: false, cozy: 45, c), 0.39375, accuracy: 1e-12,
                       "уют ≥ 45 даёт +0,05")
        XCTAssertEqual(Growth.dayPoints(hearts: 3, calm: 0.8, visit: true, c), 0.25 + 0.75 * (0.375 + 0.24 + 0.2),
                       accuracy: 1e-12, "обычный уход из §4")
        XCTAssertEqual(Growth.dayPoints(hearts: 4, calm: 1, visit: true, home: 0, c), 0, "весь день в побеге — ноль")
        XCTAssertEqual(Growth.dayPoints(hearts: 4, calm: 1, visit: true, home: 0.5, c), 0.5, accuracy: 1e-12)
    }

    private func daysTo(_ goal: Double, g: Double) -> Int {
        var log = GrowthLog()
        var d = 0
        while log.points < goal - 1e-9 { Growth.credit(&log, day: d, g: g); d += 1 }
        return d
    }

    func testPaceByCare() {
        let c = GrowthConfig()
        let ideal = Growth.dayPoints(hearts: 4, calm: 1, visit: true, c)
        XCTAssertEqual(daysTo(c.teen, g: ideal), 10)
        XCTAssertEqual(daysTo(c.adult, g: ideal), 35, "идеальный уход — взрослый на 35-й день")
        let forgotten = Growth.dayPoints(hearts: 1, calm: 0, visit: false, c)
        let adultDay = daysTo(c.adult, g: forgotten)
        XCTAssertTrue((95...105).contains(adultDay), "забыт — взрослый через 100 ± 5 дней, вышло \(adultDay)")
        let usual = Growth.dayPoints(hearts: 3, calm: 0.8, visit: true, c)
        XCTAssertTrue((38...44).contains(daysTo(c.adult, g: usual)), "обычный уход — около 41 дня")
    }

    func testCreditOncePerDay() {
        var log = GrowthLog()
        XCTAssertTrue(Growth.credit(&log, day: 100, g: 1))
        XCTAssertFalse(Growth.credit(&log, day: 100, g: 1), "те же сутки второй раз не платят")
        XCTAssertFalse(Growth.credit(&log, day: 99, g: 1), "сутки раньше засчитанных — тоже")
        XCTAssertEqual(log.points, 1)
        XCTAssertTrue(Growth.credit(&log, day: 101, g: 0.5))
        XCTAssertEqual(log.points, 1.5)
    }

    // MARK: стадии

    func testPhases() {
        let c = GrowthConfig()
        XCTAssertEqual(Growth.phase(0, c), .puppy)
        XCTAssertEqual(Growth.phase(9.99, c), .puppy)
        XCTAssertEqual(Growth.phase(10, c), .teen)
        XCTAssertEqual(Growth.phase(34.99, c), .teen)
        XCTAssertEqual(Growth.phase(35, c), .adult)
        XCTAssertEqual(Growth.phase(1000, c), .adult)
        XCTAssertEqual(Growth.progress(5, c), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Growth.next(4, c)?.phase, .teen)
        XCTAssertEqual(Growth.next(4, c)?.left ?? 0, 6, accuracy: 1e-12)
        XCTAssertEqual(Growth.next(20, c)?.phase, .adult)
        XCTAssertNil(Growth.next(35, c))
    }

    // MARK: вид

    func testPuppyIsSmallAdultIsFull() {
        let c = GrowthConfig()
        XCTAssertEqual(Growth.look(points: 0, c).scale, 0.65, accuracy: 1e-12, "щенок ×0,65 от взрослого")
        XCTAssertEqual(Growth.look(points: 0, c).head, 1.25, accuracy: 1e-12)
        XCTAssertEqual(Growth.look(points: 10, c).scale, 0.85, accuracy: 1e-12)
        XCTAssertEqual(Growth.look(points: 35, c).scale, 1.0, accuracy: 1e-12)
        XCTAssertEqual(Growth.look(points: 35, c).earDroop, 0, accuracy: 1e-12)
        XCTAssertEqual(Growth.look(points: 200, c), Growth.look(points: 35, c), "взрослый больше не растёт")
        XCTAssertEqual(Growth.look(points: 365, c).grey, 1, accuracy: 1e-12, "седая морда к году")
        XCTAssertEqual(Growth.look(points: 300, c).grey, 0)
        XCTAssertEqual(Growth.look(gFile()).scale, 0.65, accuracy: 1e-12, "новый пёс — щенок")
    }

    func testLookIsSmooth() {
        let c = GrowthConfig()
        func fields(_ l: GrowthLook) -> [Double] {
            [l.scale, l.head, l.legs, l.earDroop, l.tailCurl, l.voicePitch, l.voiceCrack, l.grey]
        }
        var prev = fields(Growth.look(points: 0, c))
        var p = 0.0
        var worst = 0.0
        while p < 400 {
            p += 0.1
            let cur = fields(Growth.look(points: p, c))
            for (a, b) in zip(prev, cur) { worst = max(worst, abs(a - b)) }
            prev = cur
        }
        XCTAssertLessThan(worst, 0.01, "шаг 0,1 очка не даёт скачка ни в одном параметре")
        for edge in [c.teen, c.adult, c.greyFrom, c.grey] {
            let a = fields(Growth.look(points: edge - 1e-6, c)), b = fields(Growth.look(points: edge, c))
            for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: 1e-5, "скачок на границе \(edge)") }
        }
        // Размер только растёт.
        var s = 0.0
        for i in 0...400 {
            let v = Growth.look(points: Double(i) * 0.1, c).scale
            XCTAssertGreaterThanOrEqual(v, s)
            s = v
        }
    }

    // MARK: механика

    func testModsAndPerksByPhase() {
        var f = gFile()
        let c = GrowthConfig()
        XCTAssertEqual(Growth.mods(f, c)["food_decay_x"], 1.15)
        XCTAssertEqual(Growth.mods(f, c)["sleep_regen_x"], 1.2)
        XCTAssertEqual(Growth.mods(f, c)["trip_time_x"], 1.3)
        XCTAssertEqual(Growth.perks(f, c).trickLimit, 2)
        f.growth.points = 12
        XCTAssertEqual(Growth.mods(f, c), ["fun_decay_x": 1.15])
        XCTAssertEqual(Growth.perks(f, c).trickRefusePct, 15)
        XCTAssertNil(Growth.perks(f, c).trickLimit)
        f.growth.points = 40
        XCTAssertEqual(Growth.mods(f, c)["food_decay_x"], 0.95)
        XCTAssertEqual(Growth.mods(f, c)["fun_decay_x"], 0.9)
        XCTAssertEqual(Growth.mods(f, c)["trip_time_x"], 0.85)
        XCTAssertEqual(Growth.perks(f, c).findDoublePct, 10)
        XCTAssertEqual(Growth.perks(f, c).stationBonusPct, 5)
        for ph in GrowthPhase.allCases {
            for (k, v) in c.mods[ph] ?? [:] {
                XCTAssertTrue(k.hasSuffix("_x"), k)
                XCTAssertNotEqual(v, 1, "единицы не пишутся: \(k)")
            }
        }
    }

    // MARK: наблюдение

    /// Живой прогон: каждый час заход и полная забота. Подросток в начале 10-го дня, взрослый — 35-го.
    func testIdealCareGrowsUpOnDay35() {
        var f = gFile()
        let born = f.bornDay
        live(&f, until: DayKey.start(born + 10) - hourS)
        XCTAssertEqual(f.growth.points, 9, accuracy: 1e-9)
        XCTAssertEqual(Growth.phase(f), .puppy)
        live(&f, until: DayKey.start(born + 10) + 60)
        XCTAssertEqual(f.growth.points, 10, accuracy: 1e-9)
        XCTAssertEqual(Growth.phase(f), .teen)
        XCTAssertEqual(f.journal.filter { $0.kind == "growth.phase" }.map(\.key), ["teen"])
        live(&f, until: DayKey.start(born + 35) - hourS)
        XCTAssertEqual(Growth.phase(f), .teen)
        live(&f, until: DayKey.start(born + 35) + 60)
        XCTAssertEqual(f.growth.points, 35, accuracy: 1e-9)
        XCTAssertEqual(Growth.phase(f), .adult, "взрослый на 35-й день")
        XCTAssertEqual(f.growth.day, born + 34)
        let last = f.growth.last
        XCTAssertEqual(last?.g ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(last?.v, true)
        XCTAssertEqual(last?.n ?? 0, 1, accuracy: 1e-9)
    }

    func testSameMomentAndClockBackGiveNothing() {
        var f = gFile()
        live(&f, until: gT0 + 3 * 24 * hourS)
        let snap = f.growth
        let j = f.journal.count
        Growth.observe(&f, now: gT0 + 3 * 24 * hourS)
        XCTAssertEqual(f.growth, snap, "тот же момент — ничего")
        Growth.observe(&f, now: gT0 + 24 * hourS)
        XCTAssertEqual(f.growth, snap, "часы назад — ничего, курсор не уходит назад")
        Growth.observe(&f, now: gT0 + 3 * 24 * hourS)
        XCTAssertEqual(f.growth, snap, "часы вернулись — сутки второй раз не платят")
        XCTAssertEqual(f.journal.count, j)
    }

    /// Приложение не открывали: сутки досчитываются задним числом по копии ядра, V = 0, каждые сутки по разу.
    func testMissedDaysCountedBackwards() {
        var f = gFile()
        live(&f, until: gT0 + 6 * hourS)
        let born = f.bornDay
        let rep = Growth.observe(&f, now: DayKey.start(born + 4) + 60)
        XCTAssertEqual(rep.days.map(\.d), [born, born + 1, born + 2, born + 3], "каждые сутки — один раз, по порядку")
        XCTAssertEqual(rep.days.first?.v, true, "в сутки рождения заходили")
        XCTAssertEqual(rep.days[1].home, 1, "сутки после рождения пёс ещё дома")
        for d in rep.days.dropFirst() {
            XCTAssertFalse(d.v, "без захода V = 0")
            XCTAssertLessThanOrEqual(d.g, 0.85 + 1e-9)
            // Если без заботы пёс успел убежать — сутки по доле дома (это проверяют тесты побега).
            if d.home == 1 { XCTAssertGreaterThanOrEqual(d.g, 0.25 - 1e-9, "рост не останавливается") }
        }
        XCTAssertEqual(f.growth.points, rep.days.map(\.g).reduce(0, +), accuracy: 1e-9)
        XCTAssertEqual(Growth.observe(&f, now: DayKey.start(born + 4) + 120).days, [], "повтор ничего не даёт")
    }

    /// Дальше replayMaxH ядро не повторяем: живому псу — base за сутки, без данных.
    func testLongGapWithoutDataGivesBase() {
        var c = GrowthConfig()
        c.replayMaxH = 24
        var f = SaveFile.fresh(now: gT0)
        Growth.observe(&f, now: gT0, c)
        let born = f.bornDay
        let rep = Growth.observe(&f, now: DayKey.start(born + 6) + 60, c)
        XCTAssertEqual(rep.days.count, 6)
        for d in rep.days.suffix(4) {
            XCTAssertTrue(d.g == 0.25 || d.g == 0, "сутки без данных: \(d.g)")
        }
    }

    func testDeadDogDoesNotGrow() {
        var f = gFile()
        live(&f, until: gT0 + 2 * hourS)
        let p0 = f.growth.points
        let t = f.growth.t!
        f.pet.alive = false
        f.pet.diedAt = t
        f.pet.t = t
        Runaway.observe(&f, now: t)
        let born = f.bornDay
        let rep = Growth.observe(&f, now: DayKey.start(born + 3) + 60)
        XCTAssertEqual(rep.days.count, 3)
        XCTAssertEqual(rep.days.dropFirst().map(\.g), [0, 0], "весь день в побеге — ноль")
        XCTAssertLessThan(rep.days[0].home, 0.2, "в сутки побега дома был пару часов")
        XCTAssertLessThan(f.growth.points - p0, 0.2)
    }

    /// Полдня в побеге, полдня дома с заботой: очки по доле времени дома.
    func testRunawayHalfDayCountsHalf() throws {
        var f = gFile()
        let born = f.bornDay
        live(&f, until: DayKey.start(born + 1) + 60)
        let t1 = f.growth.t!
        f.pet.alive = false
        f.pet.diedAt = t1
        f.pet.t = t1
        let noon = DayKey.start(born + 1) + 12 * hourS
        Growth.observe(&f, now: noon)
        // Вернули пса в полдень (как Runaway.bringBack): жив, время ядра — сейчас.
        f.pet.alive = true
        f.pet.diedAt = nil
        f.pet.t = noon
        f.runaway.comebacks.append(noon)
        live(&f, until: DayKey.start(born + 2) + 60)
        let last = try XCTUnwrap(f.growth.last)
        XCTAssertEqual(last.d, born + 1)
        XCTAssertEqual(last.home, 0.5, accuracy: 0.03)
        XCTAssertEqual(last.g, 0.5, accuracy: 0.03)
    }

    /// Возвращение, о котором рост узнал после догона: время до возвращения — не дома.
    func testComebackBridgeIsAway() throws {
        var f = gFile()
        let born = f.bornDay
        live(&f, until: DayKey.start(born + 1) + 60)
        let t1 = f.growth.t!
        let noon = DayKey.start(born + 1) + 12 * hourS
        f.pet.t = noon
        f.runaway.comebacks.append(noon)
        Growth.observe(&f, now: noon + hourS)
        live(&f, until: DayKey.start(born + 2) + 60)
        let last = try XCTUnwrap(f.growth.last)
        XCTAssertEqual(last.home, (DayKey.start(born + 2) - noon) / (DayKey.start(born + 2) - t1), accuracy: 0.01)
    }

    /// Сейв старше роста: дни с рождения — как обычный уход, сегодняшние сутки — по-настоящему.
    func testLegacySaveGetsUsualCare() {
        var f = SaveFile.fresh(now: gT0 - 20 * 24 * hourS)
        let today = DayKey.of(gT0)
        let rep = Growth.observe(&f, now: gT0)
        XCTAssertEqual(rep.days, [])
        XCTAssertEqual(f.growth.points, Double(today - f.bornDay) * 0.85, accuracy: 1e-9)
        XCTAssertEqual(Growth.phase(f), .teen)
        XCTAssertEqual(f.growth.day, today - 1)
        XCTAssertEqual(f.growth.t, gT0)
        let again = f.growth
        Growth.observe(&f, now: gT0 - 3600)
        XCTAssertEqual(f.growth, again)
    }

    func testTouchesOnlyFromOwner() {
        var f = gFile()
        let born = f.bornDay
        f.log("act.steps", t: gT0 + hourS, source: .steps, ok: true)
        f.log("act.walk", t: gT0 + hourS, source: .shortcut, ok: true)
        XCTAssertTrue(Growth.touchDays(f, from: gT0, to: gT0 + 2 * hourS).isEmpty, "шаги и «Команды» — не заход")
        f.log("act.pet", t: gT0 + hourS, source: .widget, ok: true)
        XCTAssertEqual(Growth.touchDays(f, from: gT0, to: gT0 + 2 * hourS), [born])
    }
}
