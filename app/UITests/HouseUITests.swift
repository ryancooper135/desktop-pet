// Покупка в «Доме» доходит до комнаты: с главной открыть лист, купить лежанку, закрыть — и вещь стоит в сцене.
// Сид house_rich: все линии на базе, монет хватает. Что стоит в комнате, видно по значению pet.stage
// (RoomPlan.Levels.tag, только при PET_UI_TEST): «bath=0,bed=1,… glass=N» (проход стекла, GlassSettle — волна 27).
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
        // Строка «Готово» живёт 2,5 с (HouseScreen.noteFor): на занятом раннере снимок дерева её пропускал, хотя покупка
        // прошла и pet.stage уже показывал bed=1 (CI волн 25 и 27). Покупку подтверждает любое из двух.
        let note = any["house.note.bed"]
        var bought = false
        let deadline = Date().addingTimeInterval(5)
        while !bought && Date() < deadline {
            bought = note.exists || ((stage.value as? String)?.contains("bed=1") ?? false)
            if !bought { RunLoop.current.run(until: Date().addingTimeInterval(0.25)) }
        }
        XCTAssertTrue(bought, "после покупки ни строки «Готово», ни лежанки (\(String(describing: stage.value)))")

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

    /// Волна 41 G: из «Дома» открывается «Интерьер», обои покупаются и сразу встают («Стоит»).
    ///   ui-56-interior  лист «Интерьер» после покупки полосатых обоев
    @MainActor
    func testInteriorBuyWalls() throws {
        let app = ScreenshotUITests.makeApp()
        app.launchEnvironment["PET_SEED"] = "house_rich"
        app.launchEnvironment["PET_NOW"] = ScreenshotUITests.noon
        app.launchEnvironment["PET_SCHEME"] = "light"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()

        let any = app.descendants(matching: .any)
        let open = any["open.house"]
        XCTAssertTrue(open.waitForExistence(timeout: 20), "нет кнопки «Дом»")
        let house = any["house.screen"]
        XCTAssertTrue(tap(open, expecting: house, timeout: 10, name: "ui-56-interior-house"), "лист «Дом» не открылся")

        let entry = any["house.interior.open"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "нет входа «Обои, пол и ковёр»")
        let screen = any["interior.screen"]
        XCTAssertTrue(tap(entry, expecting: screen, timeout: 10, name: "ui-56-interior-open"), "лист «Интерьер» не открылся")

        XCTAssertTrue(any["interior.take.wall_cream"].waitForExistence(timeout: 5), "нет обоев по умолчанию")
        let buy = any["interior.take.wall_stripes"]
        XCTAssertTrue(buy.waitForExistence(timeout: 5), "нет кнопки полосатых обоев")
        tapWhenReady(buy)
        let p = NSPredicate(format: "label CONTAINS %@", "Стоит")
        let placed = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: buy)], timeout: 5)
        XCTAssertEqual(placed, .completed, "обои не встали (\(buy.label))")
        snap("ui-56-interior")
        app.terminate()
    }

    /// Значение элемента содержит text (ждём до timeout секунд).
    @MainActor
    private func wait(_ e: XCUIElement, valueHas text: String, timeout: TimeInterval = 5) -> Bool {
        let p = NSPredicate(format: "value CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: timeout) == .completed
    }
}
