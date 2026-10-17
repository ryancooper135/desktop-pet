// Остров: какая кнопка большая, какая маленькая, и реакция мордочки после действия.
// Ночь и день ищем перебором от t0 в поясе машины: тесты не зависят от того, где их запустили.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let t0: Double = 1_760_000_000

/// Первый момент от t0 с шагом 30 минут, когда питомец спит ночью (night) или бодрствует.
private func moment(night: Bool) -> Double {
    let probe = SaveFile.fresh(now: t0)
    var t = t0
    while PetEngine.petNight(t, Catalog.rules, PetRunner.owner(probe, at: t)) != night { t += 1800 }
    return t
}

/// Свежий файл на момент t, все шкалы на level (кроме перечисленных).
private func file(at t: Double, level: Double = 90, _ needs: [Need: Double] = [:]) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = needs[n] ?? level }
    return f
}

private func pick(_ f: SaveFile, at t: Double) -> IslandPick {
    IslandPlan.pick(f, at: t)
}

final class IslandPlanTests: XCTestCase {

    // MARK: большая кнопка

    func testDeadPetOnlyOpensApp() {
        let t = moment(night: false)
        var f = file(at: t)
        f.pet.alive = false
        f.pet.diedAt = t - 3600
        f.pet.cause = .starve
        let p = pick(f, at: t)
        XCTAssertEqual(p.primary, .open)
        XCTAssertNil(p.secondary)
        XCTAssertNil(IslandAct.open.action)
    }

    func testBathingWaitsWithoutButtons() {
        let t = moment(night: false)
        var f = file(at: t, [.food: 20])
        f.pet.bathUntil = t + 10 * 60
        let p = pick(f, at: t)
        XCTAssertEqual(p.primary, .wait, "в ванне кормить нельзя — только статус")
        XCTAssertNil(p.secondary)
    }

    func testStarvingFeedsFirst() {
        let t = moment(night: false)
        let p = pick(file(at: t, [.food: 0]), at: t)
        XCTAssertEqual(p.primary, .feed)
        XCTAssertNotEqual(p.secondary, .feed)
    }

    func testStarvingAtNightStillFeeds() {
        let t = moment(night: true)
        let p = pick(file(at: t, [.food: 0]), at: t)
        XCTAssertEqual(p.primary, .feed, "беда важнее сна")
    }

    func testNightWithoutTroubleIsQuiet() {
        let t = moment(night: true)
        let p = pick(file(at: t, [.food: 40]), at: t)
        XCTAssertEqual(p.primary, .sleep, "слегка голоден ночью — не будим")
        XCTAssertNil(p.secondary)
        XCTAssertNil(IslandAct.sleep.action)
    }

    func testNapMakesWakePrimary() {
        let t = moment(night: false)
        var f = file(at: t)
        f.pet.napUntil = t + 30 * 60
        let p = pick(f, at: t)
        XCTAssertEqual(p.primary, .wake)
        XCTAssertNotEqual(p.secondary, .wake)
    }

    func testWantBecomesPrimaryWithPetAside() {
        let t = moment(night: false)
        // Чистота 40: хочет мыться, но до спасения (ниже 30) не дошло.
        let p = pick(file(at: t, [.clean: 40]), at: t)
        XCTAssertEqual(p.primary, .bath)
        if IslandPlan.petAsFallback { XCTAssertEqual(p.secondary, .pet) }
    }

    func testPlayFromIslandFollowsFlag() {
        let t = moment(night: false)
        let p = pick(file(at: t, [.fun: 35]), at: t)
        if IslandPlan.playFromIsland {
            XCTAssertEqual(p.primary, .play)
        } else {
            XCTAssertNotEqual(p.primary, .play)
            XCTAssertNotEqual(p.secondary, .play)
        }
    }

    func testTiredPetIsNotOfferedPlay() {
        let t = moment(night: false)
        let p = pick(file(at: t, [.fun: 20, .energy: 10]), at: t)
        XCTAssertNotEqual(p.primary, .play, "без сил ядро игру откажет")
        XCTAssertNotEqual(p.secondary, .play)
    }

    func testAllFullFallsBackToPet() {
        let t = moment(night: false)
        let p = pick(file(at: t), at: t)
        XCTAssertEqual(p.primary, IslandPlan.petAsFallback ? .pet : .rest)
        XCTAssertNil(p.secondary, "больше ничего не нужно")
    }

    func testPetOnCooldownRests() {
        let t = moment(night: false)
        var f = file(at: t)
        f.pet.cooldowns["pet"] = t + 120
        let p = pick(f, at: t)
        XCTAssertEqual(p.primary, .rest, "только что гладили, всё полно — просто «всё хорошо»")
        XCTAssertNil(p.secondary)
    }

    /// Во всех состояниях: маленькая кнопка не повторяет большую, обе принимаются ядром.
    func testButtonsAreDistinctAndAccepted() {
        let day = moment(night: false), night = moment(night: true)
        var cases: [(String, SaveFile, Double)] = [
            ("полный", file(at: day), day),
            ("голодный", file(at: day, [.food: 10]), day),
            ("грязный", file(at: day, [.clean: 5]), day),
            ("тоска", file(at: day, [.fun: 5, .love: 5]), day),
            ("всё низко", file(at: day, level: 15), day),
            ("ночь, всё низко", file(at: night, level: 15), night),
        ]
        var nap = file(at: day, [.food: 40])
        nap.pet.napUntil = day + 1800
        cases.append(("дрёма", nap, day))
        var weak = file(at: day, level: 20)
        weak.pet.hearts = 1
        cases.append(("критично", weak, day))

        let r = Catalog.rules
        for (name, f, t) in cases {
            let p = pick(f, at: t)
            XCTAssertNotEqual(p.secondary, p.primary, name)
            let s = PetRunner.peek(f, at: t)
            let o = PetRunner.owner(f, at: t)
            for a in [p.primary, p.secondary].compactMap({ $0 }) {
                guard let pa = a.action else { continue }
                var c = s
                XCTAssertTrue(PetEngine.act(&c, r, o, pa.core).ok, "\(name): ядро откажет «\(a.title)»")
            }
            if let sec = p.secondary { XCTAssertNotNil(sec.action, "\(name): маленькая кнопка — всегда действие") }
        }
    }

    // MARK: IslandAct

    func testIslandActBasics() {
        for a in IslandAct.allCases {
            XCTAssertEqual(IslandAct(rawValue: a.rawValue), a)
            XCTAssertFalse(a.title.isEmpty)
            XCTAssertFalse(a.icon.isEmpty)
        }
        for a in [IslandAct.sleep, .wait, .open, .rest] { XCTAssertNil(a.action, a.rawValue) }
        XCTAssertEqual(IslandAct.feed.action, .feed(Catalog.mainFood))
        XCTAssertEqual(IslandAct.heal.action, .item(Catalog.healItem))
        XCTAssertEqual(IslandAct(rescueKey: "food"), .feed)
        XCTAssertEqual(IslandAct(rescueKey: "heal"), .heal)
        XCTAssertNil(IslandAct(rescueKey: "мусор"))
        XCTAssertNil(IslandAct(want: .walk))
        XCTAssertEqual(IslandAct.from(.none), .wait)
        for m in MainAct.allCases { XCTAssertEqual(IslandAct.from(m).action, m.action, m.rawValue) }
    }

    func testTimerNeedKeys() {
        XCTAssertEqual(IslandPlan.timerNeed(key: "starve"), .food)
        XCTAssertEqual(IslandPlan.timerNeed(key: "dirty"), .clean)
        XCTAssertEqual(IslandPlan.timerNeed(key: "toska"), .love)
        XCTAssertEqual(IslandPlan.timerNeed(key: "fun"), .fun)
        XCTAssertNil(IslandPlan.timerNeed(key: nil))
        XCTAssertNil(IslandPlan.timerNeed(key: "мусор"))
    }

    // MARK: состояние острова и реакция

    func testReactionHoldIsShort() {
        XCTAssertGreaterThan(IslandPlan.reactionHold, 0)
        XCTAssertLessThanOrEqual(IslandPlan.reactionHold, Presenter.reactionWindow)
    }

    func testFreshActionGivesReactionAndCalmFallback() throws {
        let t = moment(night: false)
        var f = file(at: t)
        f.lastAction = SaveFile.LastAction(kind: "pet", source: .island, t: t - 3, ok: true, reason: nil)
        let st = PetAttributes.ContentState.make(f, at: t, events: [])
        XCTAssertEqual(st.pose, .loved)
        let until = try XCTUnwrap(st.reactUntil)
        XCTAssertEqual(until, t - 3 + IslandPlan.reactionHold, accuracy: 0.001)
        let calm = try XCTUnwrap(st.calmPose)
        XCTAssertNotEqual(calm, .loved)
        XCTAssertEqual(st.shownPose(stale: false), .loved)
        XCTAssertEqual(st.shownPose(stale: true), calm, "после staleDate — спокойная мордочка")
        XCTAssertNotNil(st.calmLine)
    }

    func testOldOrFailedActionHasNoReaction() {
        let t = moment(night: false)
        var f = file(at: t)
        f.lastAction = SaveFile.LastAction(kind: "feed", source: .island, t: t - IslandPlan.reactionHold - 1, ok: true, reason: nil)
        var st = PetAttributes.ContentState.make(f, at: t, events: [])
        XCTAssertNil(st.reactUntil)
        XCTAssertNil(st.calmPose)
        XCTAssertNotEqual(st.pose, .eating)

        f.lastAction = SaveFile.LastAction(kind: "feed", source: .island, t: t - 2, ok: false, reason: "cooldown")
        st = PetAttributes.ContentState.make(f, at: t, events: [])
        XCTAssertNil(st.reactUntil, "отказ ядра — без реакции")
        XCTAssertEqual(st.shownPose(stale: true), st.pose)
    }

    func testStateCarriesIslandPick() {
        let t = moment(night: false)
        let f = file(at: t, [.food: 0])
        let st = PetAttributes.ContentState.make(f, at: t, events: [])
        let p = pick(f, at: t)
        XCTAssertEqual(st.primary, p.primary)
        XCTAssertEqual(st.bigAct, p.primary)
        XCTAssertNotEqual(st.smallAct, st.bigAct)
    }

    func testSnapshotInitMapsMainAct() {
        let t = moment(night: false)
        var f = file(at: t)
        f.pet.napUntil = t + 600
        let st = PetAttributes.ContentState(Presenter.make(f, at: t))
        XCTAssertEqual(st.bigAct, .wake)
        XCTAssertNil(st.smallAct)
    }

    /// JSON старой версии (без полей острова) читается, большая кнопка берётся из main.
    func testOldPayloadDecodes() throws {
        let t = moment(night: false)
        var f = file(at: t)
        f.lastAction = SaveFile.LastAction(kind: "pet", source: .island, t: t - 1, ok: true, reason: nil)
        let st = PetAttributes.ContentState.make(f, at: t, events: [])
        let data = try JSONEncoder().encode(st)
        XCTAssertEqual(try JSONDecoder().decode(PetAttributes.ContentState.self, from: data), st)

        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for k in ["primary", "secondary", "calmPose", "calmLine", "reactUntil", "timerNeed"] { obj[k] = nil }
        let old = try JSONDecoder().decode(PetAttributes.ContentState.self,
                                           from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(old.primary)
        XCTAssertEqual(old.bigAct, IslandAct.from(old.main))
        XCTAssertEqual(old.shownPose(stale: true), old.pose)
    }
}
