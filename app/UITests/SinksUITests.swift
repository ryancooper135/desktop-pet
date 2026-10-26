// Волна 35 L: стоки клочков ✂️. Сид sinks: 500 ✂️, пёс 12 уровня, на остановке 4 находки из 6.
//   ui-35-sinks-1  автомат: карточка «Золотой шарик» · ✂️ 50 под кнопками крутки
//   ui-35-sinks-2  золотой шарик открылся: редкая (или лучше) вещь
//   ui-35-sinks-3  карточка «Остановки»: эксклюзив места «Табличка · 120 ✂️» можно купить
//   ui-35-sinks-4  эксклюзив куплен: «— уже у тебя»

import XCTest

final class SinksUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGoldenBall() throws {
        let app = launch(["PET_OPEN": "capsule"])
        let any = app.descendants(matching: .any)
        let screen = any["capsule.screen"]
        XCTAssertTrue(screen.waitForExistence(timeout: 20), "автомат не открылся")
        let golden = any["sinks.golden"]
        XCTAssertTrue(golden.waitForExistence(timeout: 5), "нет карточки золотого шарика")
        for _ in 0..<3 where !golden.isHittable { screen.swipeUp() }
        settle(1)
        snap("ui-35-sinks-1")

        XCTAssertTrue(tapWhenReady(golden), "золотой шарик не нажимается")
        XCTAssertFalse(any["capsule.refusal"].waitForExistence(timeout: 1), "отказ при 500 ✂️")
        // Шарик обычно виден и так; свайп вниз у верхнего края закрывает лист — листаем, только если не видно.
        let ball = any["capsule.ball"]
        for _ in 0..<2 where screen.exists && !ball.isHittable { screen.swipeDown() }
        // Капсула трясётся («Капсула трясётся»), потом «нажми» и сама открывается: ждём, пока подпись
        // перестанет начинаться с «Капсула», и даём автооткрытию дойти до вещи.
        let got = NSPredicate(format: "NOT (label BEGINSWITH %@)", "Капсула")
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: got, object: ball)], timeout: 8)
        settle(4)
        snap("ui-35-sinks-2")
        XCTAssertTrue(ball.exists)
        app.terminate()
    }

    @MainActor
    func testPlaceExclusive() throws {
        let app = launch([:])
        let any = app.descendants(matching: .any)
        let walk = any["act.walk"]
        XCTAssertTrue(walk.waitForExistence(timeout: 10), "нет кнопки «Гулять»")
        XCTAssertTrue(tap(walk, expecting: any["map.screen"], timeout: 10, name: "ui-35-sinks-map"), "карта не открылась")
        let bus = any["map.place.bus_stop"]
        XCTAssertTrue(bus.waitForExistence(timeout: 5), "на карте нет остановки")
        let card = any["map.card"]
        XCTAssertTrue(tap(bus, expecting: card, timeout: 10, name: "ui-35-sinks-card"), "карточка места не открылась")
        let button = any["sinks.exclusive"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "в карточке нет эксклюзива места")
        for _ in 0..<3 where !button.isHittable { card.swipeUp() }
        let note = any["sinks.exclusive.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3), "нет подписи под эксклюзивом")
        settle(1)
        snap("ui-35-sinks-3")

        XCTAssertTrue(tapWhenReady(button), "эксклюзив не нажимается")
        let owned = NSPredicate(format: "label CONTAINS 'уже у тебя'")
        let done = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: owned, object: button)], timeout: 6)
        settle(1)
        snap("ui-35-sinks-4")
        XCTAssertEqual(done, .completed, "после покупки кнопка говорит «уже у тебя» (\(button.label))")
        app.terminate()
    }

    @MainActor
    private func launch(_ extra: [String: String]) -> XCUIApplication {
        let app = ScreenshotUITests.makeApp()
        app.launchEnvironment["PET_SEED"] = "sinks"
        app.launchEnvironment["PET_NOW"] = ScreenshotUITests.noon
        app.launchEnvironment["PET_SCHEME"] = "light"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        if extra["PET_OPEN"] == nil {
            XCTAssertTrue(app.descendants(matching: .any)["pet.stage"].waitForExistence(timeout: 20), "нет сцены pet.stage")
        }
        return app
    }
}
