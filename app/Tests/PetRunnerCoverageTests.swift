// PetRunner: пауза подписи, лампа отбоя, peek, пояс хозяина, журнал действий и догон времени.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let rnT0: Double = 1_760_000_000
private let rnH: Double = 3600

private func rnDate(_ t: Double) -> Date { Date(timeIntervalSince1970: t) }

final class PetRunnerCoverageTests: XCTestCase {

    // MARK: applyBuild

    func testExpiredBuildPauseIsForgiven() {
        let r = Catalog.rules
        var f = SaveFile.fresh(now: rnT0)
        f.build = SaveFile.BuildInfo(expiresT: rnT0 + rnH, seenT: rnT0)
        let atExpiry = PetEngine.advance(f.pet, r, f.owner, rnT0 + rnH)
        let now = rnT0 + 5 * rnH

        PetRunner.applyBuild(&f, expires: rnDate(rnT0 + 7 * 86400), now: now)

        XCTAssertEqual(f.pet.t, now, "время без подписи питомцу прощено")
        XCTAssertEqual(f.pet.needs, atExpiry.needs, "шкалы — как в момент конца подписи")
        XCTAssertEqual(f.journal.last?.kind, "sign_pause")
        XCTAssertEqual(f.journal.last?.value, 4)
        XCTAssertEqual(f.build, SaveFile.BuildInfo(expiresT: rnT0 + 7 * 86400, seenT: now))
    }

    func testPauseClearsFinishedBathAndNap() {
        var f = SaveFile.fresh(now: rnT0)
        f.build = SaveFile.BuildInfo(expiresT: rnT0 + rnH, seenT: rnT0)
        f.pet.bathUntil = rnT0 + 2 * rnH
        f.pet.napUntil = rnT0 + 3 * rnH
        PetRunner.applyBuild(&f, expires: nil, now: rnT0 + 5 * rnH)
        XCTAssertNil(f.pet.bathUntil, "ванна кончилась во время паузы")
        XCTAssertNil(f.pet.napUntil)
        XCTAssertEqual(f.build?.seenT, rnT0 + 5 * rnH)
        XCTAssertEqual(f.build?.expiresT, rnT0 + rnH, "без нового срока старый остаётся")
    }

    func testShortPauseIsNotLogged() {
        var f = SaveFile.fresh(now: rnT0)
        f.build = SaveFile.BuildInfo(expiresT: rnT0 + rnH, seenT: rnT0)
        PetRunner.applyBuild(&f, expires: nil, now: rnT0 + 1.5 * rnH)
        XCTAssertFalse(f.journal.contains { $0.kind == "sign_pause" }, "полчаса — не пауза")
        XCTAssertEqual(f.pet.t, rnT0 + rnH, "досчитан до конца подписи, остальное догонит catchUp")
    }

    func testValidBuildOnlyTouchesSeen() {
        var f = SaveFile.fresh(now: rnT0)
        f.build = SaveFile.BuildInfo(expiresT: rnT0 + 10 * rnH, seenT: rnT0)
        let pet = f.pet
        PetRunner.applyBuild(&f, expires: nil, now: rnT0 + 5 * rnH)
        XCTAssertEqual(f.pet, pet)
        XCTAssertTrue(f.journal.isEmpty)
        XCTAssertEqual(f.build, SaveFile.BuildInfo(expiresT: rnT0 + 10 * rnH, seenT: rnT0 + 5 * rnH))

        var empty = SaveFile.fresh(now: rnT0)
        PetRunner.applyBuild(&empty, expires: nil, now: rnT0 + rnH)
        XCTAssertNil(empty.build, "срока не знаем — и не выдумываем")
    }

    func testDeadPetBuildUpdateOnly() {
        var f = SaveFile.fresh(now: rnT0)
        f.pet.alive = false
        f.pet.hearts = 0
        f.build = SaveFile.BuildInfo(expiresT: rnT0 + rnH, seenT: rnT0)
        let pet = f.pet
        PetRunner.applyBuild(&f, expires: rnDate(rnT0 + 7 * 86400), now: rnT0 + 5 * rnH)
        XCTAssertEqual(f.pet, pet)
        XCTAssertTrue(f.journal.isEmpty)
        XCTAssertEqual(f.build?.expiresT, rnT0 + 7 * 86400)
    }

    // MARK: лампа отбоя

    func testSetBedtimeRoundsAndWraps() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-runner")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: rnT0)
        let cases: [(Int, Int)] = [(1412, 1410), (1413, 1415), (1438, 0), (-7, 1435), (1320, 1320), (1442, 0)]
        for (i, (input, want)) in cases.enumerated() {
            try PetRunner.setBedtime(minute: input, store: store, now: rnT0 + 10 + Double(i))
            let f = try XCTUnwrap(store.read())
            XCTAssertEqual(f.owner.bedMin, want, "\(input)")
            XCTAssertEqual(f.journal.last?.kind, "set_bed")
            XCTAssertEqual(f.journal.last?.value, want)
        }
    }

    // MARK: peek и пояс

    func testPeekNeverGoesBack() {
        let f = SaveFile.fresh(now: rnT0)
        XCTAssertEqual(PetRunner.peek(f, at: rnT0 - 3600), f.pet)
        XCTAssertEqual(PetRunner.peek(f, at: rnT0), f.pet)
        let later = PetRunner.peek(f, at: rnT0 + 3 * rnH)
        XCTAssertEqual(later, PetEngine.advance(f.pet, Catalog.rules, f.owner, rnT0 + 3 * rnH))
        XCTAssertEqual(later.t, rnT0 + 3 * rnH)
    }

    func testOwnerTakesClockZone() {
        var f = SaveFile.fresh(now: rnT0)
        f.owner = Owner(bedMin: 60, wakeMin: 600, tzOffsetMin: 777)
        let o = PetRunner.owner(f, at: rnT0)
        XCTAssertEqual(o.tzOffsetMin, Clock.tzOffsetMin(at: rnT0))
        XCTAssertEqual(o.bedMin, 60)
        XCTAssertEqual(o.wakeMin, 600)
    }

    // MARK: действия

    func testStepsSetLastStepsT() {
        var f = SaveFile.fresh(now: rnT0)
        let out = PetRunner.apply(.steps(1200), source: .steps, to: &f, now: rnT0 + 120)
        XCTAssertTrue(out.ok)
        XCTAssertEqual(f.lastStepsT, rnT0 + 120)
        let e = f.journal.last
        XCTAssertEqual(e?.kind, "act.steps")
        XCTAssertEqual(e?.value, 1200)
        XCTAssertEqual(e?.source, .steps)
        XCTAssertEqual(e?.ok, true)
        XCTAssertEqual(e?.action, .steps(1200))
    }

    func testRepeatedRefusalLoggedOnce() {
        var f = SaveFile.fresh(now: rnT0)
        let first = PetRunner.apply(.wake, source: .app, to: &f, now: rnT0 + 120)
        XCTAssertFalse(first.ok)
        let n = f.journal.count
        for i in 1...30 {
            let out = PetRunner.apply(.wake, source: .app, to: &f, now: rnT0 + 120 + Double(i) * 5)
            XCTAssertEqual(out, first, "отказ по-прежнему возвращается")
        }
        XCTAssertEqual(f.journal.count, n, "30 одинаковых отказов подряд — одна запись")
        XCTAssertEqual(f.lastAction?.ok, false)
        _ = PetRunner.apply(.wake, source: .app, to: &f, now: rnT0 + 120 + PetRunner.refusalGap + 60)
        XCTAssertEqual(f.journal.count, n + 1, "через 10 минут тот же отказ пишется снова")
        _ = PetRunner.apply(.pet, source: .app, to: &f, now: rnT0 + 120 + PetRunner.refusalGap + 70)
        XCTAssertEqual(f.journal.last?.kind, "act.pet", "другое действие пишется сразу")
    }

    func testFailedWakeIsLoggedButNotSteps() {
        var f = SaveFile.fresh(now: rnT0)
        let out = PetRunner.apply(.wake, source: .island, to: &f, now: rnT0 + 120)
        XCTAssertEqual(out, ActOutcome(ok: false, reason: "not_napping"))
        XCTAssertEqual(f.lastAction?.ok, false)
        XCTAssertEqual(f.lastAction?.reason, "not_napping")
        XCTAssertEqual(f.journal.last?.ok, false)
        XCTAssertNil(f.lastStepsT)
        XCTAssertTrue(f.timedActs(from: rnT0 - 1, to: rnT0 + 3600).isEmpty, "отказ — не действие для сводки")
    }

    func testPetTwiceHitsCooldown() {
        var f = SaveFile.fresh(now: rnT0)
        XCTAssertTrue(PetRunner.apply(.pet, source: .widget, to: &f, now: rnT0 + 10).ok)
        let again = PetRunner.apply(.pet, source: .widget, to: &f, now: rnT0 + 20)
        XCTAssertEqual(again.reason, "cooldown")
        XCTAssertEqual(RefuseText.text(again.reason), "Чуть позже, только что было")
    }

    // MARK: catchUp

    func testCatchUpLogsForecastEvents() {
        let r = Catalog.rules
        var f = SaveFile.fresh(now: rnT0)
        let now = rnT0 + 48 * rnH
        let expected = PetEngine.forecast(f.pet, r, f.owner, horizonH: 48).filter { $0.t <= now && $0.kind != .level }

        PetRunner.catchUp(&f, now: now)

        let ev = f.journal.filter { $0.kind.hasPrefix("ev.") }
        XCTAssertEqual(ev.count, expected.count)
        XCTAssertEqual(ev.map(\.t), expected.map(\.t))
        XCTAssertEqual(ev.map(\.t), ev.map(\.t).sorted(), "по времени")
        XCTAssertFalse(ev.contains { $0.kind.hasPrefix("ev.level") }, "смена уровня в журнал не пишется")
        XCTAssertTrue(ev.contains { $0.kind.hasPrefix("ev.low") }, "за двое суток что-то проседает")
        for (e, x) in zip(ev, expected) {
            XCTAssertTrue(e.kind.hasPrefix("ev.\(x.kind.rawValue)"), "\(e.kind) ↔ \(x.kind)")
            XCTAssertEqual(e.key, x.key)
            XCTAssertEqual(e.value, x.value)
        }
        XCTAssertEqual(f.pet.t, now)
    }

    func testCatchUpUnderMinuteDoesNothing() {
        var f = SaveFile.fresh(now: rnT0)
        let pet = f.pet
        PetRunner.catchUp(&f, now: rnT0 + 59)
        XCTAssertEqual(f.pet, pet)
        XCTAssertTrue(f.journal.isEmpty)
        XCTAssertEqual(f.owner.tzOffsetMin, Clock.tzOffsetMin(at: rnT0 + 59))
    }

    func testSmallClockDriftBackIsIgnored() {
        var f = SaveFile.fresh(now: rnT0)
        let pet = f.pet
        PetRunner.catchUp(&f, now: rnT0 - 200)
        XCTAssertEqual(f.pet, pet)
        XCTAssertTrue(f.journal.isEmpty, "до 5 минут назад — не событие")
    }
}
