// Дом в комнате со сценой (только iOS — RealityKit): копия точек хореографии в RoomPlan.Keep совпадает
// с PetChoreo/PetRoom, вещи дома не занимают имён миски и мяча, перестройка — только при смене уровней.
// Геометрия зазоров — RoomPlanTests (там же на Linux).

import Foundation
import RealityKit
import simd
import XCTest
@testable import Pet

@MainActor
final class RoomDecorTests: XCTestCase {
    typealias K = RoomPlan.Keep

    private func same(_ p: RoomPlan.P, _ v: SIMD3<Float>, _ what: String) {
        XCTAssertEqual(p.x, v.x, accuracy: 1e-3, what)
        XCTAssertEqual(p.z, v.z, accuracy: 1e-3, what)
    }

    func testKeepMatchesChoreo() {
        XCTAssertEqual(K.yaw3q, PetRoom.yaw3q)
        XCTAssertEqual(RoomPlan.backWallZ, PetRoom.backWallZ)
        same(K.bowlHome, PetRoom.bowlPos, "миска дома")
        XCTAssertEqual(K.bowlRadius, PetRoom.bowlRadius)
        same(K.ballHome, PetRoom.ballPos, "мяч дома")
        XCTAssertEqual(K.ballRadius, ChoreoPath.Play.ballRadius)
        same(K.bowlUnderSnoutLocal, ChoreoPath.bowlUnderSnout, "миска у морды")
        same(K.dropLocal, ChoreoPath.Walk.dropped, "находка")
        XCTAssertEqual(K.petHalfLength, ChoreoPath.petHalfLength)
        XCTAssertEqual(K.petHalfWidth, ChoreoPath.petHalfWidth)
        same(K.walkTurnAt, ChoreoPath.Walk.turnAt, "разворот прогулки")
        same(K.walkOffstage, ChoreoPath.Walk.offstage, "уход прогулки")
        same(K.playTurnAt, ChoreoPath.Play.turnAt, "разворот игры")
        same(K.playRunTo, ChoreoPath.Play.runTo, "пробежка игры")
        same(K.ballFar, ChoreoPath.Play.ballFar, "мяч далеко")
        same(K.knockTo, ChoreoPath.Play.knockTo, "мяч после толчка")
        same(K.flyCurve, ChoreoPath.Play.flyCurve, "дуга вылета")
        same(K.backCurve, ChoreoPath.Play.backCurve, "дуга возврата")
    }

    func testDecorDoesNotTakeChoreoNames() {
        let root = RoomDecor.build(.all(RoomPlan.maxLevel))
        var names: [String] = []
        func walk(_ e: Entity) {
            names.append(e.name)
            e.children.forEach(walk)
        }
        walk(root)
        for reserved in ["room", "bowl", "food", "ball", "petStand", "blobShadow"] {
            XCTAssertFalse(names.contains(reserved), "вещь дома с именем \(reserved)")
        }
        let lines = Set(root.children.map(\.name))
        XCTAssertEqual(lines, ["decor.kitchen", "decor.bath", "decor.window", "decor.bed", "decor.play"])
    }

    func testApplyRebuildsOnlyOnChange() {
        let room = Entity()
        room.name = RoomDecor.roomName
        RoomDecor.apply(RoomPlan.Levels(), to: room)
        XCTAssertTrue(room.children.isEmpty, "уровень 0 — комната как была")
        var l = RoomPlan.Levels()
        l.kitchen = 1
        RoomDecor.apply(l, to: room)
        let first = room.children.first { $0.name == RoomDecor.rootName }
        XCTAssertNotNil(first)
        RoomDecor.apply(l, to: room)
        XCTAssertTrue(room.children.first { $0.name == RoomDecor.rootName } === first, "те же уровни — не перестраиваем")
        l.kitchen = 2
        RoomDecor.apply(l, to: room)
        let second = room.children.first { $0.name == RoomDecor.rootName }
        XCTAssertFalse(second === first, "покупка — новые вещи сразу")
        XCTAssertEqual(room.children.filter { $0.name == RoomDecor.rootName }.count, 1)
        RoomDecor.apply(RoomPlan.Levels(), to: room)
        XCTAssertTrue(room.children.isEmpty)
    }

    func testMoreLevelMoreParts() {
        func parts(_ e: Entity) -> Int { (e is ModelEntity ? 1 : 0) + e.children.reduce(0) { $0 + parts($1) } }
        let counts = (0...RoomPlan.maxLevel).map { parts(RoomDecor.build(.all($0))) }
        XCTAssertEqual(counts[0], 0)
        XCTAssertEqual(counts, counts.sorted(), "с уровнем деталей не меньше")
    }
}
