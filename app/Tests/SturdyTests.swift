// Волна 23: устойчивость. Часы назад (метки из будущего), шаги без двойного счёта, тихие часы
// через переход на зимнее время, имя персонажа в одну строку и огромные числа в character.json.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let sT0: Double = 1_760_000_000
private let belgrade = TimeZone(identifier: "Europe/Belgrade")!

private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Double {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: 0)!
    return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!.timeIntervalSince1970
}

final class SturdyTests: XCTestCase {
    override func tearDown() {
        Clock.zoneOverride = nil
        super.tearDown()
    }

    // MARK: шаги

    func testStepsWindow() {
        let day = sT0 - 3600 * 5
        // С прошлого раза, но не раньше начала суток.
        XCTAssertEqual(PetRunner.stepsFrom(lastStepsT: sT0 - 3600, createdT: 0, dayStart: day, now: sT0), sT0 - 3600)
        XCTAssertEqual(PetRunner.stepsFrom(lastStepsT: day - 86400, createdT: 0, dayStart: day, now: sT0), day)
        // Ни разу не засчитывали — с рождения (не раньше суток).
        XCTAssertEqual(PetRunner.stepsFrom(lastStepsT: nil, createdT: sT0 - 1800, dayStart: day, now: sT0), sT0 - 1800)
        // Слишком рано — молчим.
        XCTAssertNil(PetRunner.stepsFrom(lastStepsT: sT0 - 60, createdT: 0, dayStart: day, now: sT0))
        // Метка из будущего (часы назад) окна не открывает.
        XCTAssertNil(PetRunner.stepsFrom(lastStepsT: sT0 + 3600, createdT: 0, dayStart: day, now: sT0))
    }

    // MARK: часы назад

    func testClockBackSettlesFutureMarks() {
        var f = SaveFile.fresh(now: sT0 + 7200)
        f.lastStepsT = sT0 + 7000
        f.flags.widgetHintT = sT0 + 7000
        f.tips.lastStrokeT = sT0 + 7000
        f.cooking.lastT = sT0 + 7000
        PetRunner.catchUp(&f, now: sT0)
        XCTAssertEqual(f.lastStepsT, sT0)
        XCTAssertEqual(f.flags.widgetHintT, sT0)
        XCTAssertEqual(f.tips.lastStrokeT, sT0)
        XCTAssertEqual(f.cooking.lastT, sT0)
        XCTAssertEqual(f.journal.last?.kind, "clock_back", "питомец заморожен, а не откатан")
        XCTAssertGreaterThanOrEqual(f.pet.t, sT0)
        // Шаги после этого идут от «сейчас», а не ждут, пока часы догонят.
        XCTAssertEqual(PetRunner.stepsFrom(lastStepsT: f.lastStepsT, createdT: f.createdT, dayStart: sT0 - 3600,
                                           now: sT0 + 1000), f.lastStepsT)
    }

    func testPastMarksUntouched() {
        var f = SaveFile.fresh(now: sT0)
        f.lastStepsT = sT0 - 100
        f.flags.widgetHintT = sT0 - 100
        PetRunner.settleFutureMarks(&f, now: sT0)
        XCTAssertEqual(f.lastStepsT, sT0 - 100)
        XCTAssertEqual(f.flags.widgetHintT, sT0 - 100)
    }

    // MARK: зимнее время (Белград, 25.10.2026 03:00 → 02:00)

    private func summerOwner() -> Owner {
        var o = SaveFile.fresh(now: sT0).owner
        o.tzOffsetMin = 120
        return o
    }

    func testDstQuietShiftsToWake() {
        Clock.zoneOverride = belgrade
        let q = (from: 23 * 60, to: 8 * 60)
        // Ядро по летнему сдвигу поставило «08:00» = 06:00 UTC; по новым часам это 07:00 — ещё тихие часы.
        let t = utc(2026, 10, 26, 6)
        XCTAssertEqual(NotificationPlanner.dstQuiet(t, trigger: .hungry, quiet: q, owner: summerOwner()), t + 3600)
        XCTAssertEqual(NotificationPlanner.dstQuiet(t, trigger: .miss_you, quiet: q, owner: summerOwner()), t + 3600)
        // Срочное не двигаем.
        XCTAssertEqual(NotificationPlanner.dstQuiet(t, trigger: .last_chance, quiet: q, owner: summerOwner()), t)
        XCTAssertEqual(NotificationPlanner.dstQuiet(t, trigger: .critical, quiet: q, owner: summerOwner()), t)
        // Днём — без изменений.
        let noon = utc(2026, 10, 26, 11)
        XCTAssertEqual(NotificationPlanner.dstQuiet(noon, trigger: .hungry, quiet: q, owner: summerOwner()), noon)
        // До перевода сдвиг тот же — ядро уже всё учло.
        let before = utc(2026, 10, 24, 5)
        XCTAssertEqual(NotificationPlanner.dstQuiet(before, trigger: .hungry, quiet: q, owner: summerOwner()), before)
    }

    func testPlanAcrossDstRespectsQuietHours() {
        Clock.zoneOverride = belgrade
        // Вечер перед переводом часов: ближайшие напоминания — уже утром по зимнему времени.
        let now = utc(2026, 10, 24, 19)
        var f = SaveFile.fresh(now: now)
        f.owner.tzOffsetMin = 120
        f.lastSeenT = now
        let o = PetRunner.owner(f, at: now)
        XCTAssertEqual(o.tzOffsetMin, 120)
        let q = NotificationPlanner.quietHours(f, now: now, owner: o)
        let urgent: Set<String> = ["last_chance", "critical", "build_expiring", "walk_home"]
        let notes = NotificationPlanner.plan(f, now: now).filter { !urgent.contains($0.trigger) }
        let switchT = utc(2026, 10, 25, 1)
        XCTAssertTrue(notes.contains { $0.date.timeIntervalSince1970 > switchT }, "план заходит за перевод часов: \(NotificationPlanner.plan(f, now: now).map { ($0.trigger, $0.date) })")
        for n in notes {
            let t = n.date.timeIntervalSince1970
            let m = ((DayKey.minute(t) + Clock.tzOffsetMin(at: t)) % 1440 + 1440) % 1440
            XCTAssertFalse(OwnerSleep.inWindow(m, q.from, q.to), "\(n.trigger) в \(m / 60):\(m % 60) по местным часам")
        }
        XCTAssertEqual(Set(notes.map(\.id)).count, notes.count, "id без повторов")
    }

    // MARK: имя

    func testCleanName() {
        XCTAssertEqual(PetNames.clean(""), "")
        XCTAssertEqual(PetNames.clean("  \n\t "), "")
        XCTAssertEqual(PetNames.clean("Мурка"), "Мурка")
        XCTAssertEqual(PetNames.clean("  Серый\nШиба \r\n "), "Серый Шиба")
        XCTAssertEqual(PetNames.clean("\u{202E}Кот\u{202C}"), "Кот")
        XCTAssertEqual(PetNames.clean("\u{2067}Кот\u{2069}\u{200F}"), "Кот")
        XCTAssertEqual(PetNames.clean("🐶 Пёс 👩‍👩‍👧"), "🐶 Пёс 👩‍👩‍👧", "эмодзи и составные эмодзи целы")
        XCTAssertEqual(PetNames.clean("قطة"), "قطة", "арабские буквы остаются")
        let long = PetNames.clean(String(repeating: "Ш", count: 5000))
        XCTAssertEqual(long.count, PetNames.maxLength)
        XCTAssertTrue(long.hasSuffix("…"))
        XCTAssertEqual(PetNames.clean(String(repeating: "🐶", count: 100)).count, PetNames.maxLength)
    }

    func testPetNameIsClean() {
        var f = SaveFile.fresh(now: sT0)
        f.character = "cat"
        f.characterName = "Мурка\nв две строки"
        XCTAssertEqual(f.petName, "Мурка в две строки")
        f.characterName = "\u{202E}\u{202C}"
        XCTAssertEqual(f.petName, "Шиба", "только знаки направления — как пустое")
        f.characterName = String(repeating: "а", count: 10_000)
        XCTAssertLessThanOrEqual(f.petName.count, PetNames.maxLength)
    }

    // MARK: character.json

    func testHugeNumbersDoNotCrashCheck() {
        var clips: [String: CharacterConfig.Range] = [:]
        for (i, n) in CharacterPack.allClips.enumerated() {
            clips[n] = CharacterConfig.Range(start: Double(i), end: Double(i) + 1, loop: nil)
        }
        clips["idle"] = CharacterConfig.Range(start: 1e300, end: -1e300, loop: nil)
        var c = CharacterConfig(name: "Кот", clips: clips)
        c.scale = 1e20
        c.lift = -1e19
        c.fps = -1e30
        let e = CharacterPack.check(c).errors
        XCTAssertTrue(e.contains { $0.hasPrefix("scale 1e+20") }, "\(e)")
        XCTAssertTrue(e.contains { $0.hasPrefix("fps") }, "\(e)")
        c.name = "\u{202E}\n"
        XCTAssertTrue(CharacterPack.check(c).errors.contains("пустое name — как зовут персонажа?"))
    }
}
