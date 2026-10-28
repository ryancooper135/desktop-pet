// Сезонный акцент (волна 40 F): модели двора и комнаты живут в App (RealityKit), поэтому тест только в Xcode CI;
// на Linux — исключён в Package.swift. Логика сезонов и покупок — SeasonsTests.

import Foundation
import RealityKit
import XCTest
@testable import Pet

@MainActor
final class SeasonArtTests: XCTestCase {
    /// Точки модели в её координатах (узел + вершина).
    private func points(_ m: YardArtModel) -> [SIMD3<Float>] {
        m.nodes.flatMap { n in n.meshes.values.flatMap { $0.positions.map { $0 + n.at } } }
    }

    func testAccentIsSmallAndMatte() {
        for s in Season.allCases {
            let m = SeasonDecor.model(s)
            XCTAssertGreaterThanOrEqual(m.triangles, 30, "\(s): несколько десятков треугольников")
            XCTAssertLessThanOrEqual(m.triangles, 150, "\(s): акцент, а не станция")
            XCTAssertLessThanOrEqual(m.triangles, YardArt.stationBudget, "\(s): бюджет станции")
            let glow = m.nodes.flatMap { $0.meshes.keys }.filter(\.glow)
            XCTAssertTrue(glow.isEmpty, "\(s): только матовое — ночью тонируется, как всё остальное")
            XCTAssertTrue(m.nodes.allSatisfy { $0.motion == nil }, "\(s): стоит на месте")
        }
    }

    /// Акцент стоит на доске и влезает на оба подоконника: во дворе (глубина 0.34) и в комнате (0.05 при ×0.32).
    func testAccentFitsSills() {
        let roomZ = SeasonDecor.roomSpot().z
        let back = (RoomPlan.backWallZ - roomZ) / SeasonDecor.roomScale
        let front = (RoomPlan.backWallZ + 0.05 - roomZ) / SeasonDecor.roomScale
        for s in Season.allCases {
            let p = points(SeasonDecor.model(s))
            let lo = p.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }
            let hi = p.reduce(SIMD3<Float>(repeating: -.infinity)) { simd_max($0, $1) }
            XCTAssertGreaterThanOrEqual(lo.y, -0.002, "\(s): не проваливается в доску")
            XCTAssertLessThanOrEqual(lo.y, 0.01, "\(s): не висит над доской")
            XCTAssertLessThanOrEqual(hi.y, 0.26, "\(s): невысокий")
            XCTAssertGreaterThanOrEqual(lo.z, back, "\(s): не уходит в стену комнаты")
            XCTAssertLessThanOrEqual(hi.z, front + 0.005, "\(s): не свисает с подоконника комнаты")
            XCTAssertLessThanOrEqual(SeasonDecor.yardAt.x + hi.x, 0.475, "\(s): на подоконнике двора")
            XCTAssertGreaterThanOrEqual(SeasonDecor.yardAt.x + lo.x, 0.24, "\(s): правее сушилки")
            // Левый край в комнате — правее полога балдахина (RoomPlan.canopy + canopyDrape).
            let roomLeft = SeasonDecor.roomSpot().x + lo.x * SeasonDecor.roomScale
            XCTAssertGreaterThan(roomLeft, RoomPlan.canopy.minX + RoomPlan.canopyDrape, "\(s): не под пологом")
        }
    }

    func testSeasonsDiffer() {
        let sets = Season.allCases.map { s in Set(SeasonDecor.model(s).nodes.flatMap { $0.meshes.keys.map(\.hex) }) }
        XCTAssertEqual(Set(sets).count, Season.allCases.count, "у каждого сезона своя палитра")
    }

    func testYardSceneHasAccentBeforeLight() {
        let world = YardLive.scene(YardState(), tier: 0, fill: 0, night: true, brushed: false, season: .winter)
        let accent = world.children.first { $0.name == SeasonDecor.yardName }
        XCTAssertNotNil(accent, "акцент на подоконнике")
        XCTAssertEqual(accent?.children.first?.name, "season.winter")
        // Под тестами сезон стабильный — осень.
        let auto = YardLive.scene(YardState(), tier: 2, fill: 0, night: false, brushed: false)
        XCTAssertEqual(auto.children.first { $0.name == SeasonDecor.yardName }?.children.first?.name, "season.autumn")
        let shot = YardArtStage.scene(.tier(0), level: 1, fill: 0, night: false, progress: 3, season: .summer)
        XCTAssertNotNil(shot.children.first { $0.name == SeasonDecor.yardName }, "превью ярусов тоже")
    }

    func testRoomRebuildsOnlyOnChange() {
        let room = Entity()
        room.name = RoomDecor.roomName
        XCTAssertTrue(RoomDecor.applySeason(.autumn, window: true, to: room))
        let first = room.children.first { $0.name == SeasonDecor.roomName }
        XCTAssertNotNil(first)
        XCTAssertFalse(RoomDecor.applySeason(.autumn, window: true, to: room), "тот же сезон — не перестраиваем")
        XCTAssertTrue(room.children.first { $0.name == SeasonDecor.roomName } === first)
        XCTAssertTrue(RoomDecor.applySeason(.autumn, window: false, to: room), "без окна — своя полочка")
        let shelf = room.children.first { $0.name == SeasonDecor.roomName }
        XCTAssertEqual(shelf?.children.count, 4, "доска, два кронштейна и акцент")
        XCTAssertTrue(RoomDecor.applySeason(.spring, window: false, to: room), "сменился сезон")
        XCTAssertEqual(room.children.filter { $0.name == SeasonDecor.roomName }.count, 1)
        XCTAssertEqual(room.children.first { $0.name == SeasonDecor.roomName }?.children.count, 4)
        RoomDecor.applySeason(.spring, window: true, to: room)
        XCTAssertEqual(room.children.first { $0.name == SeasonDecor.roomName }?.children.count, 1, "на подоконнике окна")
    }

    func testShelfDrawsSeasonItems() {
        for id in Seasons.decor.sorted() {
            let g = Entity()
            XCTAssertTrue(RoomDecor.seasonShelf(id, sx: 0, y: 0, z: 0, in: g), id)
            XCTAssertGreaterThanOrEqual(g.children.count, 3, "\(id): не плетёный кубик-заглушка")
        }
        XCTAssertFalse(RoomDecor.seasonShelf("bowl_plain", sx: 0, y: 0, z: 0, in: Entity()))
    }
}
