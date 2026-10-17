// План уведомлений: приоритеты, id и категории, «скучаю» по дням, мёртвый питомец,
// и регрессия «два уведомления в один день» (старый lastSentT при уже сработавшем из плана).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let nT0: Double = 1_760_000_000
private let nDay: Double = 86400

private func nFile(needs: Double? = nil, lastSeen: Double? = nT0) -> SaveFile {
    var f = SaveFile.fresh(now: nT0)
    if let needs { for n in Need.allCases { f.pet.needs[n] = needs } }
    f.lastSeenT = lastSeen
    return f
}

/// Местный день так же, как его видит ядро: пояс хозяина на момент планирования.
private func nLocalDay(_ t: Double, _ f: SaveFile, now: Double) -> Int {
    let tz = PetRunner.owner(f, at: now).tzOffsetMin
    return Int(((t + Double(tz) * 60) / 86400).rounded(.down))
}

private func nCare(_ notes: [PlannedNote]) -> [PlannedNote] {
    notes.filter { $0.category != "pet.build" }
}

final class NotificationPlannerCoverageTests: XCTestCase {

    func testPriorityForEveryTrigger() {
        let expect: [NotifyTrigger: Int] = [
            .last_chance: 5, .critical: 5, .heart_lost: 4, .smelly: 3, .unwell: 3, .miss_you: 1,
            .hungry: 2, .dirty: 2, .bored: 2, .wants_love: 2,
        ]
        XCTAssertEqual(Set(expect.keys), Set(NotifyTrigger.allCases), "новый триггер — реши его приоритет")
        for t in NotifyTrigger.allCases {
            XCTAssertEqual(NotificationPlanner.priority(t), expect[t], t.rawValue)
            XCTAssertLessThan(NotificationPlanner.priority(t), 6, "подпись важнее любого ухода")
        }
    }

    func testNoteShapeAndWindow() throws {
        let f = nFile(needs: 30)
        let notes = NotificationPlanner.plan(f, now: nT0)
        XCTAssertLessThanOrEqual(notes.count, NotificationPlanner.maxNotes)
        XCTAssertEqual(notes.map(\.date), notes.map(\.date).sorted(), "по времени")
        XCTAssertEqual(Set(notes.map(\.id)).count, notes.count, "id не повторяются")
        for n in nCare(notes) {
            let trig = try XCTUnwrap(NotifyTrigger(rawValue: n.trigger), n.trigger)
            let at = n.date.timeIntervalSince1970
            XCTAssertEqual(n.id, "pet.\(n.trigger).\(Int(at))")
            XCTAssertEqual(n.category, trig == .miss_you ? "pet.miss" : "pet.need")
            XCTAssertEqual(n.priority, NotificationPlanner.priority(trig))
            XCTAssertGreaterThanOrEqual(at, nT0 + 3600, "не раньше чем через час")
            XCTAssertLessThanOrEqual(at, nT0 + NotificationPlanner.horizonH * 3600)
            XCTAssertLessThanOrEqual(n.title.count, LineLimit.notifTitle)
            XCTAssertFalse(n.title.isEmpty)
            XCTAssertFalse(n.body.isEmpty)
            XCTAssertFalse(n.body.contains("{"), "подстановки заполнены: \(n.body)")
        }
        let days = nCare(notes).map { nLocalDay($0.date.timeIntervalSince1970, f, now: nT0) }
        XCTAssertEqual(Set(days).count, days.count, "не больше одного в день")
    }

    func testMissYouAfterThreeDaysAway() throws {
        let lastSeen = nT0 - 2.9 * nDay
        var f = nFile(needs: 100, lastSeen: lastSeen)
        f.pet.t = nT0
        let notes = nCare(NotificationPlanner.plan(f, now: nT0))
        let miss = notes.filter { $0.trigger == NotifyTrigger.miss_you.rawValue }
        let first = try XCTUnwrap(miss.first, "через 3 дня без хозяина — «скучаю»")
        let at = first.date.timeIntervalSince1970
        XCTAssertGreaterThanOrEqual(at, lastSeen + 3 * nDay)
        XCTAssertLessThanOrEqual(at, lastSeen + 3 * nDay + 8 * 3600 + 60, "сдвиг из тихих часов не больше 8 ч")
        XCTAssertEqual(first.category, "pet.miss")
        XCTAssertTrue(miss.allSatisfy { $0.date.timeIntervalSince1970 < lastSeen + 14 * nDay }, "после 14 дней не зовём")
        XCTAssertTrue(notes.filter { $0.category == "pet.need" }.isEmpty, "всё по 100 — просить нечего")
    }

    func testLongAbsenceStopsCalling() {
        for daysAway in [12.5, 14, 30] {
            let f = nFile(needs: 100, lastSeen: nT0 - daysAway * nDay)
            XCTAssertTrue(nCare(NotificationPlanner.plan(f, now: nT0)).isEmpty, "\(daysAway) дн. — уже не зовём")
        }
    }

    func testDeadPetGetsOnlyBuildNotes() {
        var f = nFile()
        f.pet.alive = false
        f.pet.hearts = 0
        f.build = SaveFile.BuildInfo(expiresT: nT0 + 3 * nDay, seenT: nT0)
        let plan = NotificationPlanner.plan(f, now: nT0)
        XCTAssertEqual(plan, NotificationPlanner.buildNotes(f, now: nT0))
        XCTAssertEqual(plan.map(\.id), ["pet.build.48", "pet.build.24"])
        XCTAssertTrue(plan.allSatisfy { $0.priority == 6 && $0.category == "pet.build" })
    }

    func testBuildNotesSkipPast() {
        var f = nFile()
        XCTAssertTrue(NotificationPlanner.buildNotes(f, now: nT0).isEmpty, "без подписи — нечего")
        f.build = SaveFile.BuildInfo(expiresT: nT0 + 30 * 3600, seenT: nT0)
        XCTAssertEqual(NotificationPlanner.buildNotes(f, now: nT0).map(\.id), ["pet.build.24"], "за 48 ч уже прошло")
        f.build = SaveFile.BuildInfo(expiresT: nT0 - 3600, seenT: nT0)
        XCTAssertTrue(NotificationPlanner.buildNotes(f, now: nT0).isEmpty)
    }

    /// Регрессия: lastSentT трёхдневной давности не должен перебивать уведомление, сработавшее час назад.
    func testFiredNoteBeatsStaleLastSent() {
        var f = nFile(needs: 30)
        let fired = nT0 - 3600
        f.notif.lastSentT = nT0 - 3 * nDay
        f.notif.scheduled = [fired, nT0 + 5 * 3600]
        let firedDay = nLocalDay(fired, f, now: nT0)
        for n in nCare(NotificationPlanner.plan(f, now: nT0)) {
            XCTAssertNotEqual(nLocalDay(n.date.timeIntervalSince1970, f, now: nT0), firedDay,
                              "\(n.id): в этот день уже было уведомление")
        }
    }

    func testScheduledExactlyNowCountsAsFired() {
        var f = nFile(needs: 30)
        f.notif.scheduled = [nT0]
        let today = nLocalDay(nT0, f, now: nT0)
        for n in nCare(NotificationPlanner.plan(f, now: nT0)) {
            XCTAssertNotEqual(nLocalDay(n.date.timeIntervalSince1970, f, now: nT0), today, n.id)
        }
    }

    func testFutureScheduledIsNotFired() {
        var f = nFile(needs: 30)
        let base = NotificationPlanner.plan(f, now: nT0)
        f.notif.scheduled = base.map { $0.date.timeIntervalSince1970 }
        XCTAssertEqual(NotificationPlanner.plan(f, now: nT0), base, "ещё не сработавшие из прошлого плана не мешают")
    }

    func testEveryTriggerHasText() throws {
        guard let notif = Lines.shared.sections["notifications"], !notif.isEmpty else {
            throw XCTSkip("lines.json нет в бандле")
        }
        for t in NotifyTrigger.allCases {
            XCTAssertFalse(notif[t.rawValue]?.isEmpty ?? true, "нет текстов для \(t.rawValue)")
        }
    }
}
