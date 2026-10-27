// Районы двора ночью и станции в духе района (волна 37 B). Модели двора живут в App (RealityKit-стадия рядом),
// поэтому тест только в Xcode CI; на Linux — исключён в Package.swift.

import Foundation
import XCTest
@testable import Pet

@MainActor
final class YardNightTests: XCTestCase {
    /// Декор района на ярус: днём и ночью не больше 800 треугольников (DECISIONS, волна 36 Q).
    private let decorBudget = 800
    private let full = YardArtTier.plates.map(\.count)

    private func names(_ m: YardArtModel) -> Set<String> { Set(m.nodes.map(\.name)) }

    func testDecorBudgetDayAndNight() {
        for d in YardDistrict.allCases {
            for top in 1..<YardArtTier.plates.count {
                for night in [false, true] {
                    let t = YardArtTier.decor(d, top: top, bought: full, night: night).triangles
                    XCTAssertLessThanOrEqual(t, decorBudget, "\(d) ярус \(top) ночь \(night)")
                }
            }
        }
        XCTAssertLessThanOrEqual(YardArtTier.worstDecorTriangles().triangles, decorBudget)
    }

    func testNightAddsLittle() {
        // Ночь — огоньки и таблички, а не новая геометрия: прибавка к дню скромная.
        for d in YardDistrict.allCases {
            for top in 1..<YardArtTier.plates.count {
                let day = YardArtTier.decor(d, top: top, bought: full, night: false).triangles
                let night = YardArtTier.decor(d, top: top, bought: full, night: true).triangles
                XCTAssertGreaterThanOrEqual(night, day, "\(d) ярус \(top)")
                XCTAssertLessThanOrEqual(night - day, 60, "\(d) ярус \(top)")
            }
        }
    }

    func testNightNodesOnlyAtNight() {
        XCTAssertEqual(YardArtTier.nightNodes(.street, top: 4), [])
        for d in YardDistrict.allCases where d != .street {
            for top in 1..<YardArtTier.plates.count {
                let want = YardArtTier.nightNodes(d, top: top)
                XCTAssertFalse(want.isEmpty, "\(d): ночью должно что-то гореть")
                let night = names(YardArtTier.decor(d, top: top, bought: full, night: true))
                let day = names(YardArtTier.decor(d, top: top, bought: full, night: false))
                for n in want {
                    XCTAssertTrue(night.contains(n), "\(d) ярус \(top): нет \(n) ночью")
                    XCTAssertFalse(day.contains(n), "\(d) ярус \(top): \(n) днём")
                }
            }
        }
        // По району — главное, что просили: гирлянда и окна, фонарь и блик, огни города и лампочка у будки.
        XCTAssertTrue(YardArtTier.nightNodes(.winter, top: 1).contains("night.window"))
        XCTAssertTrue(YardArtTier.nightNodes(.winter, top: 1).contains("night.eave0"))
        XCTAssertEqual(Set(YardArtTier.nightNodes(.river, top: 1)), ["night.lantern", "night.glint"])
        XCTAssertEqual(Set(YardArtTier.nightNodes(.roof, top: 3)), ["night.bulb", "night.city"])
    }

    func testStationAccentsWithinBudget() {
        XCTAssertLessThanOrEqual(YardArt.worstTriangles().triangles, YardArt.stationBudget)
        for d in YardDistrict.allCases {
            for s in YardArtStation.allCases {
                for level in 1...5 {
                    for night in [false, true] {
                        let t = YardArt.station(s, level: level, fill: 1, night: night, brushed: night, district: d)
                        XCTAssertLessThanOrEqual(t.triangles, YardArt.stationBudget, "\(d) \(s) ур. \(level)")
                    }
                }
            }
        }
    }

    func testStationAccentsPerDistrict() {
        let expected: [YardDistrict: Set<YardArtStation>] = [
            .street: [],
            .winter: [.oven, .photo, .conveyor, .mill],
            .river: [.bonePatch, .photo],
            .roof: [.bonePatch, .photo],
        ]
        for d in YardDistrict.allCases {
            var got = Set<YardArtStation>()
            for s in YardArtStation.allCases {
                let m = YardArt.station(s, level: 3, fill: 1, night: false, brushed: false, district: d)
                if names(m).contains("accent") { got.insert(s) }
                // Силуэт тот же: акцент — небольшая добавка к станции улицы.
                let base = YardArt.station(s, level: 3, fill: 1, night: false, brushed: false).triangles
                XCTAssertLessThanOrEqual(m.triangles - base, 80, "\(d) \(s)")
            }
            XCTAssertEqual(got, expected[d], "\(d)")
        }
    }

    func testMoveSceneNight() {
        for calm in [false, true] {
            let day = YardArt.moveScene(from: .street, to: .winter, calm: calm)
            let night = YardArt.moveScene(from: .street, to: .winter, calm: calm, night: true)
            for n in YardArt.moveNightNodes {
                XCTAssertTrue(names(night).contains(n), "нет \(n) ночью (calm \(calm))")
                XCTAssertFalse(names(day).contains(n), "\(n) днём (calm \(calm))")
            }
            XCTAssertLessThanOrEqual(night.triangles - day.triangles, 100, "calm \(calm)")
        }
        XCTAssertEqual(YardArt.moveScene(from: .street, to: .winter).triangles, 972, "день переезда не менялся")
    }
}
