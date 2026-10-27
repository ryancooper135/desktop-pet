// Районы двора ночью и станции в духе района (волна 37 B). Модели двора живут в App (RealityKit-стадия рядом),
// поэтому тест только в Xcode CI; на Linux — исключён в Package.swift.

import Foundation
import RealityKit
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

    // MARK: Волна 38 B: свет двора ночью

    private func dist(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { simd_length(a - b) }

    func testNightLampsOnlyAtNightAndFew() {
        let noLamp = [YardArtTier.plates[0].count, 3, 0, 0, 0]
        for d in YardDistrict.allCases {
            for top in 1..<YardArtTier.plates.count {
                XCTAssertEqual(YardLight.lamps(d, top: top, bought: full, night: false), [], "\(d) днём")
                let n = YardLight.lamps(d, top: top, bought: full, night: true)
                XCTAssertLessThanOrEqual(n.count, YardLight.maxLamps, "\(d) ярус \(top)")
                XCTAssertFalse(n.isEmpty, "\(d) ярус \(top): ночью нет ни одного огня")
                for l in n {
                    XCTAssertTrue(l.name.hasPrefix(YardLight.lampPrefix))
                    XCTAssertGreaterThan(l.lumens, 0)
                    XCTAssertLessThanOrEqual(l.radius, 1.6, "огонь двора светит рядом, а не на весь двор")
                }
            }
            // Без плиты «Фонарь» фонаря двора нет; на улице тогда и вовсе темно (декора района нет).
            let n = YardLight.lamps(d, top: 1, bought: noLamp, night: true)
            XCTAssertFalse(n.contains { $0.name.hasSuffix(".yard") }, "\(d)")
            XCTAssertEqual(n.count, d == .street ? 0 : 1, "\(d)")
        }
        XCTAssertEqual(YardLight.moveLamps(night: false).count, 0)
        XCTAssertLessThanOrEqual(YardLight.moveLamps(night: true).count, YardLight.maxLamps)
    }

    func testNightLampsSitAtTheirGlow() {
        func lamp(_ d: YardDistrict, _ top: Int, _ suffix: String) -> YardNightLamp? {
            YardLight.lamps(d, top: top, bought: full, night: true).first { $0.name.hasSuffix(suffix) }
        }
        let wallZ = YardDecorArt.wallZ
        // Фонарь двора — у стекла фонаря плиты слоя 1.
        XCTAssertLessThan(dist(lamp(.street, 1, ".yard")!.at, SIMD3(0.3, 0.86, -0.18)), 0.2)
        XCTAssertLessThan(dist(lamp(.winter, 4, ".window")!.at, SIMD3(0, 0.82, wallZ + 0.065)), 0.45)
        XCTAssertLessThan(dist(lamp(.roof, 3, ".bulb")!.at, YardDecorArt.boothBulbAt), 0.2)
        for top in 1..<YardArtTier.plates.count {
            let ctx = YardDecorCtx(top: top, bought: full, night: true, palette: YardDistrict.river.palette)
            XCTAssertLessThan(dist(lamp(.river, top, ".lantern")!.at, YardDecorArt.lanternAt(ctx)), 0.1, "ярус \(top)")
        }
    }

    func testNightPresetIsMoonlit() {
        let n = YardLight.night
        // Холодный и тихий относительно дня, синева сильнее красного; лампа комнаты погашена.
        XCTAssertLessThan(n.keyI, RoomLight.day.keyI)
        XCTAssertGreaterThan(n.key.b, n.key.r)
        XCTAssertGreaterThan(n.tint.b, n.tint.r)
        XCTAssertLessThan(n.tint.luminance, 0.6)
        XCTAssertEqual(n.lamp, 0)
        // Комната своё ночное не потеряла (двор берёт копию пресета).
        XCTAssertEqual(RoomLight.night.tint, RoomRGB(0.36, 0.40, 0.60))
        XCTAssertEqual(RoomLight.night.lamp, 0.35)
    }

    private func all(_ root: Entity) -> [Entity] {
        var out: [Entity] = [], stack = [root]
        while let e = stack.popLast() { out.append(e); stack += Array(e.children) }
        return out
    }

    private func keyIntensity(_ world: Entity) -> Float? {
        all(world).compactMap { $0 as? DirectionalLight }.first { $0.name == PetRoom.keyLight.name }?.light.intensity
    }

    func testSceneLightDayUnchangedNightMoonlit() {
        let day = YardArtStage.scene(.tier(4), level: 3, fill: 1, night: false, progress: 6, district: .winter)
        let night = YardArtStage.scene(.tier(4), level: 3, fill: 1, night: true, progress: 6, district: .winter)
        // День — ровно свет комнаты: ключ 2200, ни тинта, ни огней.
        XCTAssertEqual(keyIntensity(day), 2200)
        XCTAssertFalse(all(day).contains { $0.components.has(RoomTintBase.self) })
        XCTAssertFalse(all(day).contains { $0.name.hasPrefix(YardLight.lampPrefix) })
        // Ночь — лунный ключ, матовое под тинтом, светящееся без него, огней два (фонарь двора и окно дома).
        XCTAssertEqual(keyIntensity(night), Float(YardLight.night.keyI))
        let ents = all(night)
        XCTAssertTrue(ents.contains { $0.components.has(RoomTintBase.self) })
        XCTAssertFalse(ents.contains { $0.components.has(RoomGlow.self) && $0.components.has(RoomTintBase.self) })
        let lamps = ents.compactMap { $0 as? PointLight }.filter { $0.name.hasPrefix(YardLight.lampPrefix) }
        XCTAssertEqual(lamps.count, 2)
        // Лампа комнаты во дворе не горит.
        XCTAssertFalse(ents.compactMap { $0 as? PointLight }.contains { $0.name == PetRoom.lampName && $0.isEnabled })
    }

    func testMoveSceneCargoLightRidesTheVan() {
        let night = YardMoveStage.scene(from: .street, to: .winter, calm: false, night: true)
        let cargo = night.findEntity(named: "\(YardLight.lampPrefix).cargo")
        XCTAssertEqual(cargo?.parent?.name, "night.cargo")
        XCTAssertNotNil(night.findEntity(named: "\(YardLight.lampPrefix).road"))
        let day = YardMoveStage.scene(from: .street, to: .winter, calm: false)
        XCTAssertNil(day.findEntity(named: "\(YardLight.lampPrefix).road"))
        XCTAssertEqual(keyIntensity(day), 2200)
    }
}
