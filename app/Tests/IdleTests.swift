// Волна 27, тихий покой: стеклянные кнопки в UI-тестах пересоздаются поверх готовой комнаты (GlassSettle),
// а у живого пользователя ничего не меняется — проход всегда 0, значение сцены пустое.

import XCTest
@testable import Pet

final class IdleTests: XCTestCase {
    func testGlassPassStaysZeroOutsideUITests() {
        XCTAssertEqual(GlassSettle.next(0, uiTest: false), 0)
        // Даже если бы проход откуда-то взялся — вне UI-тестов id кнопок не меняется.
        XCTAssertEqual(GlassSettle.next(7, uiTest: false), 0)
    }

    func testGlassPassCountsEachSceneBuildInUITests() {
        var pass = 0
        for want in 1...3 {
            pass = GlassSettle.next(pass, uiTest: true)
            XCTAssertEqual(pass, want)
        }
    }

    func testStageValueEmptyOutsideUITests() {
        XCTAssertEqual(GlassSettle.stageValue(levels: RoomPlan.Levels().tag, pass: 3, uiTest: false), "")
    }

    func testStageValueKeepsHouseLevelsForHouseUITests() {
        var l = RoomPlan.Levels()
        l.bed = 1
        let v = GlassSettle.stageValue(levels: l.tag, pass: 0, uiTest: true)
        // HouseUITests ищут «bed=N» подстрокой — проход стекла не должен ему мешать.
        XCTAssertTrue(v.contains("bed=1"), v)
        XCTAssertTrue(v.hasSuffix(" glass=0"), v)
    }

    func testSettledOnlyAfterFirstPass() {
        let tag = RoomPlan.Levels().tag
        XCTAssertFalse(GlassSettle.settled(GlassSettle.stageValue(levels: tag, pass: 0, uiTest: true)))
        XCTAssertTrue(GlassSettle.settled(GlassSettle.stageValue(levels: tag, pass: 1, uiTest: true)))
        XCTAssertTrue(GlassSettle.settled(GlassSettle.stageValue(levels: tag, pass: 12, uiTest: true)))
    }

    func testSettledRejectsOldBuildsAndJunk() {
        // Старая сборка (A/B-замер против прошлого коммита) отдаёт только уровни дома.
        XCTAssertFalse(GlassSettle.settled(RoomPlan.Levels().tag))
        XCTAssertFalse(GlassSettle.settled(""))
        XCTAssertFalse(GlassSettle.settled("glass="))
        XCTAssertFalse(GlassSettle.settled("glass=x1"))
    }

    func testDelayFitsBeforeScreenshotPause() {
        // Проход должен случиться заметно позже первого кадра комнаты, но не растягивать каждый снимок главного
        // экрана: shootState ждёт его до 15 с, потом ещё settle.
        XCTAssertGreaterThan(GlassSettle.delay, 0.5)
        XCTAssertLessThanOrEqual(GlassSettle.delay, 3)
    }
}
