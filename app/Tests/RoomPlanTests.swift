// Дом в комнате без экрана: уровни из сейва, и что предметы дома не лезут на собаку, миску, мяч,
// находку с прогулки и пути прогулки и игры. Точки хореографии — копия RoomPlan.Keep (сверка с PetChoreo —
// RoomDecorTests на macOS). Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let rT0: Double = 1_760_000_000

final class RoomPlanTests: XCTestCase {
    typealias P = RoomPlan.P
    typealias K = RoomPlan.Keep

    // MARK: уровни

    func testLevelsFromSave() {
        var f = SaveFile.fresh(now: rT0)
        XCTAssertEqual(RoomPlan.levels(f), RoomPlan.Levels(), "новый сейв — всё на базе, комната как была")
        f.pet.home[.bath] = 2
        f.pet.home[.yard] = 1
        f.pet.home[.bed] = 9      // битый сейв
        f.pet.home[.play] = -3
        let l = RoomPlan.levels(f)
        XCTAssertEqual(l.bath, 2)
        XCTAssertEqual(l.yard, 1)
        XCTAssertEqual(l.bed, RoomPlan.maxLevel, "выше верхнего уровня не рисуем")
        XCTAssertEqual(l.play, 0)
        XCTAssertEqual(l.kitchen, 0)
        XCTAssertTrue(l.window)
    }

    func testLevelsAfterPurchase() {
        var f = SaveFile.fresh(now: rT0)
        Economy.grant(&f, coins: 50_000)
        let before = RoomPlan.levels(f)
        guard case .ok = HomeShop.buy(.kitchen, in: &f, now: rT0) else { return XCTFail("кухня не купилась") }
        let after = RoomPlan.levels(f)
        XCTAssertNotEqual(before, after, "покупка меняет уровни — сцена перестроится без перезапуска")
        XCTAssertEqual(after.kitchen, 1)
    }

    func testAllAndWindow() {
        let max = RoomPlan.Levels.all(RoomPlan.maxLevel)
        for line in HomeLine.allCases { XCTAssertEqual(max[line], RoomPlan.maxLevel) }
        XCTAssertEqual(RoomPlan.Levels.all(7), max, "all тоже обрезает")
        XCTAssertFalse(RoomPlan.Levels().window)
        var k = RoomPlan.Levels()
        k.kennel = 1
        XCTAssertTrue(k.window, "будка стоит во дворе — окно нужно и без двора")
    }

    // MARK: пол

    private var allLevels: [RoomPlan.Levels] {
        (0...RoomPlan.maxLevel).map { RoomPlan.Levels.all($0) }
    }

    func testFloorItemsGrowWithLevel() {
        XCTAssertTrue(RoomPlan.floorItems(RoomPlan.Levels()).isEmpty, "на базе ничего нового")
        let counts = allLevels.map { RoomPlan.floorItems($0).count }
        XCTAssertEqual(counts, counts.sorted(), "с уровнем вещей не меньше")
    }

    func testFloorItemsDoNotOverlap() {
        let items = RoomPlan.floorItems(.all(RoomPlan.maxLevel))
        for i in items.indices {
            for j in items.indices where j > i {
                XCTAssertFalse(items[i].rect.intersects(items[j].rect), "\(items[i].line) и \(items[j].line) налезают")
            }
        }
    }

    /// Пол у задней стены не дальше стены, а всё — не на ковре (ковёр — место собаки и мяча).
    func testFloorItemsOffRug() {
        for (line, r) in RoomPlan.floorItems(.all(RoomPlan.maxLevel)) {
            XCTAssertGreaterThanOrEqual(r.minZ, RoomPlan.wallFront - 1e-4, "\(line): в стене")
            XCTAssertGreaterThan(r.distance(to: P(0, 0)), 0.45, "\(line): на ковре")
        }
    }

    func testFloorItemsClearOfBowlBallAndDrop() {
        let bowlSnout = RoomPlan.toRoom(K.bowlUnderSnoutLocal)
        let drop = RoomPlan.toRoom(K.dropLocal)
        for (line, r) in RoomPlan.floorItems(.all(RoomPlan.maxLevel)) {
            XCTAssertGreaterThan(r.distance(to: K.bowlHome), K.bowlRadius + 0.04, "\(line) у миски")
            XCTAssertGreaterThan(r.distance(to: bowlSnout), K.bowlRadius + 0.04, "\(line) там, где Шиба ест")
            XCTAssertGreaterThan(r.distance(to: K.ballHome), K.ballRadius + 0.1, "\(line) у мяча")
            XCTAssertGreaterThan(r.distance(to: drop), 0.1, "\(line) там, куда кладётся находка")
        }
    }

    func testFloorItemsClearOfBallFlight() {
        for (line, r) in RoomPlan.floorItems(.all(RoomPlan.maxLevel)) {
            for p in RoomPlan.ballPath() {
                XCTAssertGreaterThan(r.distance(to: p), K.ballRadius + 0.03, "\(line) на пути мяча у \(p)")
            }
        }
    }

    /// Пятно Шибы во всех позах прогулки и игры (и дома при любом повороте) не задевает вещей на полу.
    func testFloorItemsClearOfPetPaths() {
        let poses = petPoses()
        XCTAssertGreaterThan(poses.count, 100)
        for (line, r) in RoomPlan.floorItems(.all(RoomPlan.maxLevel)) {
            for (p, yaw) in poses {
                for q in corners(r) {
                    XCTAssertFalse(RoomPlan.petCovers(at: p, yaw: yaw, point: q, pad: 0.04),
                                   "\(line) под Шибой в \(p), поворот \(yaw)")
                }
            }
            // Дома Шиба крутится на месте: круг его размаха.
            XCTAssertGreaterThan(r.distance(to: P(0, 0)), K.petReachMax + 0.04, "\(line) в размахе Шибы дома")
            for turn in [K.walkTurnAt, K.playTurnAt, K.playRunTo] {
                XCTAssertGreaterThan(r.distance(to: turn), K.petReachMax + 0.04, "\(line) там, где Шиба разворачивается")
            }
        }
    }

    // MARK: лежанка

    func testBedUnderPetNotUnderBowlOrBall() {
        XCTAssertLessThan(RoomPlan.bedEllipse(P(0, 0)), 1, "центр подставки — на лежанке")
        let snout = RoomPlan.toRoom(K.bowlUnderSnoutLocal)
        for k in 0..<24 {
            let a = Float(k) / 24 * 2 * .pi
            let rim = P(cos(a), sin(a))
            XCTAssertGreaterThan(RoomPlan.bedEllipse(snout + rim * K.bowlRadius), 1, "миска у морды наезжает на лежанку")
            XCTAssertGreaterThan(RoomPlan.bedEllipse(K.ballHome + rim * K.ballRadius), 1, "мяч на лежанке")
        }
        XCTAssertGreaterThan(RoomPlan.bedEllipse(RoomPlan.toRoom(K.dropLocal)), 1, "находка ляжет на бортик")
        XCTAssertGreaterThan(RoomPlan.bedEllipse(K.bowlHome, grow: K.bowlRadius), 1)
    }

    func testBedOnRugAndLow() {
        // Лежанка целиком на ковре и не выше бортика, через который перешагивают.
        for k in 0..<48 {
            let a = Float(k) / 48 * 2 * .pi
            let local = RoomPlan.bedCenterLocal
                + P(cos(a) * (RoomPlan.bedHalfX + RoomPlan.bedRim), sin(a) * (RoomPlan.bedHalfZ + RoomPlan.bedRim))
            XCTAssertLessThan(RoomPlan.toRoom(local).length, 0.45, "лежанка свисает с ковра")
        }
        XCTAssertLessThanOrEqual(RoomPlan.bedRimHeight, 0.03)
        XCTAssertLessThanOrEqual(RoomPlan.bedTop, 0.015)
    }

    func testStandRoundTrip() {
        let p = P(0.2, -0.4)
        let back = RoomPlan.toRoom(RoomPlan.toStand(p))
        XCTAssertEqual(back.x, p.x, accuracy: 1e-5)
        XCTAssertEqual(back.z, p.z, accuracy: 1e-5)
        // Морда в 3/4 смотрит влево к камере: +z подставки уходит в -x комнаты.
        XCTAssertLessThan(RoomPlan.toRoom(P(0, 1)).x, 0)
    }

    // MARK: стена

    func testWallItemsAboveDogAndInsideWindow() {
        let w = RoomPlan.window
        XCTAssertGreaterThanOrEqual(w.minY, 0.2, "ниже окно закроет уши и хвост")
        XCTAssertGreaterThan(w.width, 0.3)
        let k = RoomPlan.kennelSlot
        XCTAssertGreaterThanOrEqual(k.minX, w.minX + RoomPlan.windowFrame)
        XCTAssertLessThanOrEqual(k.maxX, w.maxX - RoomPlan.windowFrame)
        XCTAssertGreaterThanOrEqual(k.minY, w.minY + RoomPlan.windowFrame)
        XCTAssertLessThanOrEqual(k.maxY, w.maxY - RoomPlan.windowFrame)
        // Полка кухни и полотенце ванной — над своими углами, мимо окна.
        XCTAssertLessThanOrEqual(RoomPlan.kitchenShelf.maxX, w.minX)
        XCTAssertGreaterThanOrEqual(RoomPlan.kitchenShelf.minX, RoomPlan.kitchen.minX - 1e-4)
        XCTAssertGreaterThanOrEqual(RoomPlan.bathTowel.minX, w.maxX)
        XCTAssertLessThanOrEqual(RoomPlan.bathTowel.maxX, RoomPlan.bath.maxX + 1e-4)
    }

    func testCanopyFramesWindowClearOfNeighbours() {
        // Балдахин на стене: пологи по бокам окна, мимо полки кухни и полотенца, выше свечей ванны,
        // ламбрекен — не выше окна больше чем на 4 см (строка таймера).
        let c = RoomPlan.canopy, w = RoomPlan.window
        let flare = RoomPlan.canopyFlare
        XCTAssertLessThanOrEqual(c.minX, w.minX, "левый полог закрывает край рамы")
        XCTAssertGreaterThanOrEqual(c.maxX, w.maxX, "правый полог закрывает край рамы")
        XCTAssertGreaterThan(c.minX - flare, RoomPlan.kitchenShelf.maxX)
        XCTAssertGreaterThan(c.minX - flare, RoomPlan.kitchen.maxX)
        XCTAssertLessThanOrEqual(c.maxX + flare, RoomPlan.bathTowel.minX)
        XCTAssertGreaterThan(c.minY, RoomPlan.bathTop)
        XCTAssertLessThanOrEqual(c.maxY, w.maxY + 0.04)
        XCTAssertGreaterThan(RoomPlan.canopyTieY, c.minY)
        XCTAssertLessThan(RoomPlan.canopyTieY, c.maxY)
        // Пологи не закрывают будку в окне.
        XCTAssertLessThanOrEqual(c.minX + RoomPlan.canopyDrape, RoomPlan.kennelSlot.minX)
        XCTAssertGreaterThanOrEqual(c.maxX - RoomPlan.canopyDrape, RoomPlan.kennelSlot.maxX - 0.005)
    }

    // MARK: помощники

    private func corners(_ r: RoomPlan.Rect) -> [P] {
        var out: [P] = []
        for i in 0...4 {
            let t = Float(i) / 4
            out.append(P(r.minX + r.width * t, r.minZ))
            out.append(P(r.minX + r.width * t, r.maxZ))
            out.append(P(r.minX, r.minZ + r.depth * t))
            out.append(P(r.maxX, r.minZ + r.depth * t))
        }
        return out
    }

    /// Позы Шибы (точка на полу и поворот) по формулам PetChoreo: уход, приход, игра; смягчение не важно — берём сетку.
    private func petPoses() -> [(P, Float)] {
        let y0 = K.yaw3q
        let yawOut = RoomPlan.yaw(toward: K.walkOffstage - K.walkTurnAt)
        let yawIn = RoomPlan.yaw(toward: P(0, 0) - K.walkOffstage)
        let yawRun = RoomPlan.yaw(toward: K.ballFar - K.playTurnAt)
        let yawBack = RoomPlan.yaw(toward: P(0, 0) - K.playRunTo)
        var out: [(P, Float)] = []
        let n = 20
        for i in 0...n {
            let s = Float(i) / Float(n)
            out.append((K.walkTurnAt * s, y0 + (yawOut - y0) * s))
            out.append((K.walkTurnAt + (K.walkOffstage - K.walkTurnAt) * s, yawOut))
            out.append((K.walkOffstage * (1 - s), yawIn))
            out.append((P(0, 0), yawIn + (y0 - yawIn) * s))
            out.append((K.playTurnAt * s, y0 + (yawRun - y0) * s))
            out.append((K.playTurnAt + (K.playRunTo - K.playTurnAt) * s, yawRun))
            out.append((K.playRunTo, yawRun + (yawBack - yawRun) * s))
            out.append((K.playRunTo * (1 - s), yawBack))
            out.append((P(0, 0), yawBack + (y0 - yawBack) * s))
        }
        return out
    }
}
