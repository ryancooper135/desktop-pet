// Покупка в «Доме» доходит до комнаты: с главной открыть лист, купить лежанку, закрыть — и вещь стоит в сцене.
// Сид house_rich: все линии на базе, монет хватает. Что стоит в комнате, видно по значению pet.stage
// (RoomPlan.Levels.tag, только при PET_UI_TEST): «bath=0,bed=1,…».
//   ui-56-house-bought  главный экран сразу после покупки: лежанка под Шибой

import XCTest

final class HouseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBuyShowsInRoom() throws {
        let app = ScreenshotUITests.makeApp()
        app.launchEnvironment["PET_SEED"] = "house_rich"
        app.launchEnvironment["PET_NOW"] = ScreenshotUITests.noon
        app.launchEnvironment["PET_SCHEME"] = "light"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()

        let any = app.descendants(matching: .any)
        let stage = any["pet.stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 20), "нет сцены pet.stage")
        XCTAssertTrue(wait(stage, valueHas: "bed=0"), "сид house_rich: лежанка уже стоит (\(String(describing: stage.value)))")

        let open = any["open.house"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "нет кнопки «Дом»")
        let screen = any["house.screen"]
        XCTAssertTrue(tap(open, expecting: screen, timeout: 10, name: "ui-56-house-open"), "лист «Дом» не открылся")

        let buy = any["house.buy.bed"]
        XCTAssertTrue(buy.waitForExistence(timeout: 5), "нет кнопки покупки лежанки")
        for _ in 0..<4 where !buy.isHittable {
            screen.swipeUp()
            settle(0.5)
        }
        tapWhenReady(buy)
        XCTAssertTrue(any["house.note.bed"].waitForExistence(timeout: 5), "после покупки нет строки «Готово»")

        // Лист на весь экран: тянем вниз, пока не уедет (первый свайп может только долистать наверх).
        for _ in 0..<4 where screen.exists {
            let from = screen.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
            from.press(forDuration: 0.05, thenDragTo: screen.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.3)))
            _ = screen.waitForNonExistence(timeout: 2)
        }
        XCTAssertFalse(screen.exists, "лист «Дом» не закрылся")

        XCTAssertTrue(wait(stage, valueHas: "bed=1"), "в комнате нет лежанки (\(String(describing: stage.value)))")
        settle(2.5)
        snap("ui-56-house-bought")
        app.terminate()
    }

    /// Значение элемента содержит text (ждём до timeout секунд).
    @MainActor
    private func wait(_ e: XCUIElement, valueHas text: String, timeout: TimeInterval = 5) -> Bool {
        let p = NSPredicate(format: "value CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: timeout) == .completed
    }
}
