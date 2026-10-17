// Прогулка с находкой (care.walk_out): то же, что core/ts/test/walk.test.ts, в главном. Сверка чисел с TS — в векторах walk_*.

import Foundation
import XCTest
@testable import PetCore

final class WalkTests: XCTestCase {
    let H: Double = 3600
    let T0: Double = 1_788_220_800 // полночь UTC, как в core/ts/src/scenarios.ts

    func rules() throws -> Rules {
        try Rules(data: Data(contentsOf: VectorTests.repo.appendingPathComponent("config/economy.json")))
    }

    func pet(_ r: Rules, hour: Double, fill: Double = 80) -> PetState {
        var s = PetEngine.newPet(r, t: T0 + hour * H)
        for n in Need.allCases where n != .look { s.needs[n] = fill }
        return s
    }

    func testRefusals() throws {
        let r = try rules()
        let o = PetEngine.defaultOwner(r)
        func why(_ s: PetState) -> String? {
            var c = s
            let res = PetEngine.act(&c, r, o, .walk)
            if !res.ok { XCTAssertEqual(c, s, "отказ не меняет состояние") }
            return res.reason
        }
        var dead = pet(r, hour: 10); dead.alive = false
        XCTAssertEqual(why(dead), "dead")
        var bath = pet(r, hour: 10); _ = PetEngine.act(&bath, r, o, .bath)
        XCTAssertEqual(why(bath), "bathing")
        var nap = pet(r, hour: 10); nap.napUntil = nap.t + 1800
        XCTAssertEqual(why(nap), "asleep")
        XCTAssertEqual(why(pet(r, hour: 2)), "asleep")
        var starving = pet(r, hour: 10); starving.needs[.food] = 0
        XCTAssertEqual(why(starving), "unwell")
        for n in [Need.food, .clean, .energy] {
            var s = pet(r, hour: 10); s.needs[n] = 25
            XCTAssertEqual(why(s), "not_ready", n.rawValue)
        }
        var sad = pet(r, hour: 10); sad.needs[.fun] = 20; sad.needs[.love] = 20
        XCTAssertNil(why(sad), "fun и love не мешают")
        XCTAssertEqual(why(pet(r, hour: 22 + 50.0 / 60)), "too_late")

        var out = pet(r, hour: 10)
        XCTAssertTrue(PetEngine.act(&out, r, o, .walk).ok)
        for a: Action in [.feed("stew"), .item("vitamin"), .pet, .play, .bath, .wake, .walk] {
            var c = out
            XCTAssertEqual(PetEngine.act(&c, r, o, a), ActResult(ok: false, reason: "away"))
            XCTAssertEqual(c, out)
        }
        var c = out
        XCTAssertTrue(PetEngine.act(&c, r, o, .steps(800)).ok, "шаги принимаются")
    }

    func testNoBlockMeansUnavailable() throws {
        let raw = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: VectorTests.repo.appendingPathComponent("config/economy.json")))
        var care = raw["care"].object, root = raw.object
        care["walk_out"] = nil
        root["care"] = .object(care)
        let r = try Rules(json: .object(root))
        XCTAssertNil(r.walkOut)
        var s = pet(r, hour: 10)
        XCTAssertEqual(PetEngine.act(&s, r, PetEngine.defaultOwner(r), .walk).reason, "unavailable")
    }

    func testDurationAndFindAreDeterministic() throws {
        let r = try rules()
        let o = PetEngine.defaultOwner(r)
        let finds = try XCTUnwrap(r.walkOut).finds
        var durs = Set<Double>(), got = Set<String>()
        for m in 0..<240 {
            var a = pet(r, hour: 9); a.t += Double(m) * 60
            var b = a
            XCTAssertTrue(PetEngine.act(&a, r, o, .walk).ok)
            _ = PetEngine.act(&b, r, o, .walk)
            XCTAssertEqual(a.outing, b.outing)
            let w = try XCTUnwrap(a.outing)
            let d = (w.until - w.from) / 60
            XCTAssertTrue(d >= 60 && d <= 180 && d == d.rounded(), "\(d)")
            XCTAssertTrue(finds.contains(w.find))
            durs.insert(d); got.insert(w.find)
        }
        XCTAssertGreaterThan(durs.count, 30)
        XCTAssertEqual(got, Set(finds), "выпадает каждая находка")
    }

    func testWhileAwayAndReturn() throws {
        let r = try rules()
        let o = PetEngine.defaultOwner(r)
        var s = pet(r, hour: 10, fill: 50)
        XCTAssertTrue(PetEngine.act(&s, r, o, .walk).ok)
        let w = try XCTUnwrap(s.outing)
        XCTAssertEqual(PetEngine.moods(s, r, o).first, "walking")
        XCTAssertEqual(PetEngine.mood(s, r, o), .walking)
        XCTAssertTrue(PetEngine.wants(s, r, o).isEmpty)
        XCTAssertNil(PetEngine.rescue(s, r, o))

        let mid = PetEngine.advance(s, r, o, s.t + 50 * 60)
        XCTAssertNotNil(mid.outing)
        XCTAssertEqual(mid.needs[.fun], s.needs[.fun])
        XCTAssertEqual(mid.needs[.love], s.needs[.love])
        XCTAssertEqual(mid.needs[.food]!, s.needs[.food]! - 5 * 1.5 * 50 / 60, accuracy: 1e-6)

        let back = PetEngine.forecast(s, r, o, horizonH: 6).filter { $0.kind == .back_home }
        XCTAssertEqual(back, [ForecastEvent(t: w.until, kind: .back_home, key: w.find, value: nil)])
        let before = PetEngine.advance(s, r, o, w.until)
        XCTAssertNotNil(before.outing)
        var after = PetEngine.advance(s, r, o, w.until + 60)
        XCTAssertNil(after.outing)
        XCTAssertEqual(after.finds, [w.find: 1])
        XCTAssertEqual(PetEngine.walksDone(after), 1)
        XCTAssertGreaterThan(after.needs[.walk]!, before.needs[.walk]! + 39)
        XCTAssertTrue(PetEngine.act(&after, r, o, .pet).ok, "дома снова принимает действия")

        let away = PetEngine.awaySummary(s, r, o, now: w.until + 3 * H)
        XCTAssertEqual(away.events.filter { $0.kind == "back_home" }.map(\.key), [w.find])
        let j = PetEngine.awaySummary(pet(r, hour: 10), r, o, now: T0 + 15 * H, journal: [TimedAct(t: T0 + 11 * H, action: .walk)])
        XCTAssertEqual(j.events.first { $0.kind == "act" }?.key, "walk")
        XCTAssertEqual(PetEngine.walksDone(j.state), 1)
    }

    func testNoDamageAwayAndDistressBringsHome() throws {
        let r = try rules()
        let o = PetEngine.defaultOwner(r)
        var s = pet(r, hour: 10)
        XCTAssertTrue(PetEngine.act(&s, r, o, .walk).ok)
        s.hearts = 3; s.needs[.food] = 1
        let back = try XCTUnwrap(PetEngine.forecast(s, r, o, horizonH: 6).first { $0.kind == .back_home })
        XCTAssertLessThan(back.t, s.outing!.until)
        let door = PetEngine.advance(s, r, o, back.t)
        XCTAssertNotNil(door.outing)
        XCTAssertEqual(door.hearts, 3)
        XCTAssertEqual(door.grace[.starve], 0)
        XCTAssertNil(PetEngine.advance(s, r, o, back.t + 60).outing)
    }

    func testOldSaveWithoutWalkFields() throws {
        let r = try rules()
        let o = PetEngine.defaultOwner(r)
        let j = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"t": \(T0 + 10 * H), "needs": {"food": 80, "clean": 80, "energy": 80, "fun": 80, "love": 80, "walk": 80, "look": 80},
         "hearts": 5, "grace": {}, "cooldowns": {}, "home": {}, "alive": true}
        """.utf8))
        var s = PetState(json: j)
        XCTAssertNil(s.outing)
        XCTAssertTrue(s.finds.isEmpty)
        XCTAssertTrue(PetEngine.act(&s, r, o, .walk).ok)
        PetEngine.stepTo(&s, r, o, s.t + 4 * H)
        XCTAssertEqual(PetEngine.walksDone(s), 1)
    }
}
