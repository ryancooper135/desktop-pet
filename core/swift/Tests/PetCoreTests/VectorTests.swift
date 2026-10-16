// Сверка Swift-ядра с TS по общим векторам из core/vectors (генерирует core/ts/tools/vectors.ts).

import Foundation
import XCTest
@testable import PetCore

final class VectorTests: XCTestCase {
    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let tol = 1e-6

    func rules(preset: String? = nil) throws -> Rules {
        try Rules(data: Data(contentsOf: Self.repo.appendingPathComponent("config/economy.json")), preset: preset)
    }

    func vectorFiles() throws -> [URL] {
        let dir = Self.repo.appendingPathComponent("core/vectors")
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func near(_ a: Double?, _ b: Double?, _ what: String, _ ctx: String) {
        switch (a, b) {
        case (nil, nil): return
        case let (x?, y?): XCTAssertEqual(x, y, accuracy: tol, "\(ctx): \(what)")
        default: XCTFail("\(ctx): \(what) = \(String(describing: a)), ждали \(String(describing: b))")
        }
    }

    func compare(_ got: PetState, _ want: PetState, _ ctx: String) {
        near(got.t, want.t, "t", ctx)
        for n in Need.allCases { near(got.needs[n], want.needs[n], n.rawValue, ctx) }
        near(got.hearts, want.hearts, "hearts", ctx)
        for d in Distress.allCases { near(got.grace[d], want.grace[d], "grace.\(d)", ctx) }
        near(got.lastChanceH, want.lastChanceH, "lastChanceH", ctx)
        near(got.napUntil, want.napUntil, "napUntil", ctx)
        near(got.bathUntil, want.bathUntil, "bathUntil", ctx)
        near(got.lastHeartLossT, want.lastHeartLossT, "lastHeartLossT", ctx)
        XCTAssertEqual(Set(got.cooldowns.keys), Set(want.cooldowns.keys), "\(ctx): cooldowns")
        for (k, v) in want.cooldowns { near(got.cooldowns[k], v, "cooldown.\(k)", ctx) }
        XCTAssertEqual(got.home, want.home, "\(ctx): home")
        XCTAssertEqual(got.alive, want.alive, "\(ctx): alive")
        near(got.diedAt, want.diedAt, "diedAt", ctx)
        XCTAssertEqual(got.cause, want.cause, "\(ctx): cause")
    }

    func testConfigLoads() throws {
        let r = try rules()
        XCTAssertEqual(r.heartsMax, 5)
        XCTAssertEqual(r.distress.count, 3)
        XCTAssertNotNil(r.food["stew"])
    }

    func testVectors() throws {
        let r0 = try rules()
        let files = try vectorFiles()
        XCTAssertFalse(files.isEmpty, "нет векторов в core/vectors")
        for f in files {
            let v = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: f))
            let name = v["name"].string ?? f.lastPathComponent
            // вектор с полем preset считан на правилах этого пресета строгости
            let r = try v["preset"].string.map { try rules(preset: $0) } ?? r0
            let o = Owner(json: v["owner"])
            var s = PetState(json: v["start"])
            for (i, st) in v["steps"].array.enumerated() {
                let t = st["t"].double!
                PetEngine.stepTo(&s, r, o, t)
                let ctx = "\(name)#\(i)"
                if !st["do"].isNull {
                    let a = try XCTUnwrap(Action(json: st["do"]), ctx)
                    let res = PetEngine.act(&s, r, o, a)
                    XCTAssertEqual(res.ok, st["ok"].bool, "\(ctx): ok")
                    XCTAssertEqual(res.reason, st["reason"].string, "\(ctx): reason")
                } else {
                    compare(s, PetState(json: st["expect"]), ctx)
                    XCTAssertEqual(PetEngine.level(s, r), Int(st["level"].double ?? -1), "\(ctx): level")
                    XCTAssertEqual(PetEngine.moods(s, r, o), st["moods"].array.compactMap(\.string), "\(ctx): moods")
                    checkInsights(s, r, o, st, ctx)
                }
            }
            let fc = v["forecast"]
            let ev = PetEngine.forecast(PetState(json: fc["from"]), r, o, horizonH: fc["horizonH"].double ?? 72)
            let want = fc["events"].array
            XCTAssertEqual(ev.count, want.count, "\(name): число событий прогноза")
            for (e, w) in zip(ev, want) {
                XCTAssertEqual(e.t, w["t"].double, "\(name): forecast t")
                XCTAssertEqual(e.kind.rawValue, w["kind"].string, "\(name): forecast kind")
                XCTAssertEqual(e.key, w["key"].string, "\(name): forecast key")
                XCTAssertEqual(e.value, w["value"].double.map { Int($0) }, "\(name): forecast value")
            }
            checkAway(v["away"], PetState(json: v["start"]), r, o, name)
            for (k, c) in v["notify"].array.enumerated() { checkNotify(c, r, o, "\(name)/notify#\(k)") }
        }
    }

    func testPresets() throws {
        let strict = try rules()
        XCTAssertEqual(strict.preset, "strict")
        let explicit = try rules(preset: "strict")
        XCTAssertEqual(explicit.lastChanceH, strict.lastChanceH)
        XCTAssertEqual(explicit.regenAllGe, strict.regenAllGe)
        let medium = try rules(preset: "medium")
        XCTAssertEqual(medium.preset, "medium")
        XCTAssertEqual(medium.distress[.dirty]?.hoursPerHeart, 48)
        XCTAssertEqual(medium.distress[.dirty]?.graceH, 24)
        XCTAssertEqual(medium.distress[.toska]?.hoursPerHeart, 36)
        XCTAssertEqual(medium.regenAllGe, 15)
        XCTAssertEqual(medium.lastChanceH, 12)
        XCTAssertEqual(medium.distress[.starve]?.hoursPerHeart, strict.distress[.starve]?.hoursPerHeart)
        let soft = try rules(preset: "soft")
        XCTAssertEqual(soft.regenPerH, 0.125)
        XCTAssertEqual(soft.distress[.starve]?.hoursPerHeart, 8)
        var dirty: Vals = [:]
        for n in Need.allCases { dirty[n] = 80 }
        dirty[.clean] = 0
        XCTAssertFalse(soft.distress[.dirty]!.cond(dirty), "в мягком грязь не беда")
        XCTAssertTrue(strict.distress[.dirty]!.cond(dirty))
        XCTAssertThrowsError(try rules(preset: "hardcore"))
        XCTAssertThrowsError(try rules(preset: "_note"))
        // конфиг без пресетов читается как раньше
        let raw = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: Self.repo.appendingPathComponent("config/economy.json")))
        var care = raw["care"].object, hearts = raw["care"]["hearts"].object, root = raw.object
        hearts["preset"] = nil
        hearts["presets"] = nil
        care["hearts"] = .object(hearts)
        root["care"] = .object(care)
        let bare = try Rules(json: .object(root))
        XCTAssertNil(bare.preset)
        XCTAssertEqual(bare.lastChanceH, strict.lastChanceH)
        XCTAssertEqual(bare.distress[.dirty]?.hoursPerHeart, strict.distress[.dirty]?.hoursPerHeart)
    }

    func testChunksEqualWhole() throws {
        let r = try rules()
        let o = PetEngine.defaultOwner(r)
        var s = PetEngine.newPet(r, t: 1_788_220_800 + 9 * 3600)
        s.needs[.food] = 80
        let whole = PetEngine.advance(s, r, o, s.t + 50 * 3600)
        var part = s
        let dts: [Double] = [1, 59, 61, 3599, 7 * 3600 + 17, 13 * 3600, 29 * 3600]
        for dt in dts { part = PetEngine.advance(part, r, o, part.t + dt) }
        part = PetEngine.advance(part, r, o, s.t + 50 * 3600)
        XCTAssertEqual(part, whole)
    }

    // MARK: insights (core/ts/src/insights.ts)

    func checkInsights(_ s: PetState, _ r: Rules, _ o: Owner, _ st: JSONValue, _ ctx: String) {
        XCTAssertEqual(PetEngine.mood(s, r, o).rawValue, st["mood"].string, "\(ctx): mood")
        XCTAssertEqual(PetEngine.daypart(s.t, r, o).rawValue, st["daypart"].string, "\(ctx): daypart")
        let w = PetEngine.wants(s, r, o)
        let ww = st["wants"].array
        XCTAssertEqual(w.map { $0.key.rawValue }, ww.compactMap { $0["key"].string }, "\(ctx): wants")
        for (a, b) in zip(w, ww) {
            near(a.strength, b["strength"].double, "want.\(a.key.rawValue)", ctx)
            XCTAssertEqual(a.urgent, b["urgent"].bool, "\(ctx): want.\(a.key.rawValue).urgent")
        }
        let rs = PetEngine.rescue(s, r, o)
        let rj = st["rescue"]
        if rj.isNull {
            XCTAssertNil(rs, "\(ctx): rescue")
        } else {
            XCTAssertEqual(rs?.key, rj["key"].string, "\(ctx): rescue.key")
            XCTAssertEqual(rs?.because, rj["because"].string, "\(ctx): rescue.because")
            XCTAssertEqual(rs?.action, Action(json: rj["action"]), "\(ctx): rescue.action")
        }
    }

    func checkAway(_ j: JSONValue, _ start: PetState, _ r: Rules, _ o: Owner, _ name: String) {
        let ctx = "\(name)/away"
        var journal: [TimedAct] = []
        for x in j["journal"].array {
            if let a = Action(json: x["action"]), let t = x["t"].double { journal.append(TimedAct(t: t, action: a)) }
        }
        XCTAssertEqual(journal.count, j["journal"].array.count, "\(ctx): journal")
        let a = PetEngine.awaySummary(start, r, o, now: j["now"].double ?? 0, journal: journal)
        near(a.from, j["from"].double, "from", ctx)
        near(a.to, j["to"].double, "to", ctx)
        near(a.awayH, j["awayH"].double, "awayH", ctx)
        XCTAssertEqual(a.show, j["show"].bool, "\(ctx): show")
        XCTAssertEqual(a.greet, j["greet"].string, "\(ctx): greet")
        XCTAssertEqual(a.cta, j["cta"].string, "\(ctx): cta")
        near(a.sleptH, j["sleptH"].double, "sleptH", ctx)
        near(a.heartsFrom, j["heartsFrom"].double, "heartsFrom", ctx)
        near(a.heartsTo, j["heartsTo"].double, "heartsTo", ctx)
        for n in Need.allCases { near(a.needs[n], j["needs"][n.rawValue].double, "needs.\(n.rawValue)", ctx) }
        XCTAssertEqual(a.died, j["died"].bool, "\(ctx): died")
        compare(a.state, PetState(json: j["state"]), ctx)
        let want = j["events"].array
        XCTAssertEqual(a.events.count, want.count, "\(ctx): число событий")
        for (e, w) in zip(a.events, want) {
            XCTAssertEqual(e.kind, w["kind"].string, "\(ctx): kind")
            near(e.t, w["t"].double, "t(\(e.kind))", ctx)
            XCTAssertEqual(e.key, w["key"].string, "\(ctx): key(\(e.kind))")
            XCTAssertEqual(e.value, w["value"].double.map { Int($0) }, "\(ctx): value(\(e.kind))")
            XCTAssertEqual(e.ok, w["ok"].bool, "\(ctx): ok(\(e.kind))")
        }
    }

    func checkNotify(_ c: JSONValue, _ r: Rules, _ o: Owner, _ ctx: String) {
        let oj = c["opts"]
        let opts = NotifyOpts(horizonH: oj["horizonH"].double ?? 72, lastOpenT: oj["lastOpenT"].double,
                              lastSentT: oj["lastSentT"].double,
                              quietFromMin: oj["quietFromMin"].double.map { Int($0) },
                              quietToMin: oj["quietToMin"].double.map { Int($0) })
        let plan = PetEngine.notificationPlan(PetState(json: c["from"]), r, o, now: c["now"].double ?? 0, opts: opts)
        let want = c["plan"].array
        XCTAssertEqual(plan.count, want.count, "\(ctx): число уведомлений")
        for (p, w) in zip(plan, want) {
            near(p.at, w["at"].double, "at", ctx)
            XCTAssertEqual(p.trigger.rawValue, w["trigger"].string, "\(ctx): trigger")
            XCTAssertEqual(p.kind, w["kind"].string, "\(ctx): kind")
            XCTAssertEqual(p.key, w["key"].string, "\(ctx): key")
        }
    }

    func testNotificationRules() throws {
        let r = try rules()
        let o = PetEngine.defaultOwner(r)
        var s = PetEngine.newPet(r, t: 1_788_220_800 + 13 * 3600)
        for n in Need.allCases { s.needs[n] = 100 }
        s.home[.kennel] = 3
        let lastOpen = s.t - 2.5 * 86400
        let plan = PetEngine.notificationPlan(s, r, o, now: s.t, opts: NotifyOpts(horizonH: 14 * 24, lastOpenT: lastOpen))
        XCTAssertFalse(plan.isEmpty)
        var days = Set<Int>()
        for p in plan {
            XCTAssertTrue(days.insert(Int(((p.at / 60).rounded(.down) / 1440).rounded(.down))).inserted, "больше одного в день")
            XCTAssertFalse(PetEngine.ownerAsleep(p.at, o), "тихие часы")
            if p.at >= lastOpen + 3 * 86400 { XCTAssertEqual(p.trigger, .miss_you) }
            XCTAssertLessThan(p.at, lastOpen + 14 * 86400)
        }
    }
}
