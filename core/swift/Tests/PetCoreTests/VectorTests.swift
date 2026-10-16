// Сверка Swift-ядра с TS по общим векторам из core/vectors (генерирует core/ts/tools/vectors.ts).

import Foundation
import XCTest
@testable import PetCore

final class VectorTests: XCTestCase {
    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let tol = 1e-6

    func rules() throws -> Rules {
        try Rules(data: Data(contentsOf: Self.repo.appendingPathComponent("config/economy.json")))
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
        let r = try rules()
        let files = try vectorFiles()
        XCTAssertFalse(files.isEmpty, "нет векторов в core/vectors")
        for f in files {
            let v = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: f))
            let name = v["name"].string ?? f.lastPathComponent
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
        }
    }

    func testChunksEqualWhole() throws {
        let r = try rules()
        let o = PetEngine.defaultOwner(r)
        var s = PetEngine.newPet(r, t: 1_788_220_800 + 9 * 3600)
        s.needs[.food] = 80
        let whole = PetEngine.advance(s, r, o, s.t + 50 * 3600)
        var part = s
        for dt in [1.0, 59, 61, 3599, 7 * 3600 + 17, 13 * 3600, 29 * 3600] { part = PetEngine.advance(part, r, o, part.t + dt) }
        part = PetEngine.advance(part, r, o, s.t + 50 * 3600)
        XCTAssertEqual(part, whole)
    }
}
