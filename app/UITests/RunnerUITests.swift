// Волна 55b: «Раннер» по-настоящему — из меню «Игры» на главной, забег идёт сам, свайпы доходят до игры,
// крестик засчитывает забег и возвращает на главную.
//   ui-99-runner-live   живой забег после пары свайпов (сид 7)
// Снимки-«заморозки» (ui-99-runner-play, ui-100-runner-done) — в ScreenshotUITests.

import XCTest

final class RunnerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRunnerFromGamesMenuSwipesAndClose() throws {
        let app = ScreenshotUITests.makeApp()
        app.launchEnvironment["PET_SEED"] = "runner"
        app.launchEnvironment["PET_NOW"] = ScreenshotUITests.noon
        app.launchEnvironment["PET_SCHEME"] = "light"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        let any = app.descendants(matching: .any)

        // Меню «Игры» → «Раннер».
        let games = any["open.games"].firstMatch
        XCTAssertTrue(games.waitForExistence(timeout: 20), "нет кнопки «Игры»")
        let item = any["open.runner"].firstMatch
        XCTAssertTrue(tap(games, expecting: item, name: "ui-99-runner-menu"), "в меню «Игры» нет «Раннера»")
        tapWhenReady(item)
        XCTAssertTrue(any["runner.screen"].firstMatch.waitForExistence(timeout: 15), "экран «Раннер» не открылся")

        // «Играть» → забег.
        let play = any["runner.play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 10), "нет кнопки «Играть»")
        let track = any["runner.track"].firstMatch
        XCTAssertTrue(tap(play, expecting: track, timeout: 8, name: "ui-99-runner-play-tap"), "забег не начался")

        // Пара свайпов: полоса влево, прыжок, полоса вправо, подкат.
        track.swipeLeft()
        track.swipeUp()
        track.swipeRight()
        track.swipeDown()

        // Забег идёт: метры растут (время двигает и кадр сцены, и запасной цикл — на CI сцена может не рисоваться).
        let metres = any["runner.metres"].firstMatch
        XCTAssertTrue(metres.waitForExistence(timeout: 5), "нет счётчика метров")
        let moving = NSPredicate(format: "NOT (label BEGINSWITH %@)", "0 ")
        let ran = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: moving, object: metres)], timeout: 15)
        XCTAssertEqual(ran, .completed, "метры не растут: \(metres.label)")
        snap("ui-99-runner-live")

        // Крестик: забег засчитан, экран закрылся (или забег уже кончился — тогда «Готово» на итоге).
        let result = any["runner.result"].firstMatch
        if result.exists {
            tapWhenReady(any["runner.done"].firstMatch)
        } else {
            tapWhenReady(any["runner.close"].firstMatch)
        }
        let gone = NSPredicate(format: "exists == false")
        let closed = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: gone, object: any["runner.screen"].firstMatch)],
                                      timeout: 10)
        XCTAssertEqual(closed, .completed, "экран «Раннер» не закрылся")
        XCTAssertTrue(games.waitForExistence(timeout: 10), "не вернулись на главную")
        app.terminate()
    }
}
