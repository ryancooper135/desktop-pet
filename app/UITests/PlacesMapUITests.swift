// Волна 34 H: «Гулять» открывает карту мест, тап по месту — карточка, в походе на карте видна точка пса.
// Сид map: пёс 12 уровня, открыты 4 места из 8; map_trip — он же в походе на Кошачий холм (вернётся через 30 мин).
//   ui-34-map-1  карта: двор, тропы, открытые места и закрытые с замком
//   ui-34-map-2  карточка «Остановки»: время, находки 3/6, «Пойти»
//   ui-34-map-3  поход: точка пса на тропе к Кошачьему холму и «вернётся в …»

import XCTest

final class PlacesMapUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMapAndPlaceCard() throws {
        let app = launch("map")
        let any = app.descendants(matching: .any)
        let screen = openMap(app)

        let bus = any["map.place.bus_stop"]
        XCTAssertTrue(bus.waitForExistence(timeout: 5), "на карте нет остановки")
        XCTAssertTrue(any["map.place.rocket"].exists, "закрытые места тоже должны быть на карте")
        XCTAssertTrue(any["map.walk"].exists, "нет «Просто погулять»")
        settle(1)
        snap("ui-34-map-1")

        let card = any["map.card"]
        XCTAssertTrue(tap(bus, expecting: card, timeout: 10, name: "ui-34-map-card"), "карточка места не открылась")
        XCTAssertTrue(any["map.go"].waitForExistence(timeout: 5), "в карточке нет «Пойти»")
        let count = any["map.card.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5), "в карточке нет счёта находок")
        XCTAssertTrue(count.label.contains("3/6"), "сид map: на остановке найдено 3 из 6 (\(count.label))")
        settle(1)
        snap("ui-34-map-2")
        XCTAssertTrue(screen.exists || card.exists)
        app.terminate()
    }

    @MainActor
    func testTripOnMap() throws {
        let app = launch("map_trip")
        let any = app.descendants(matching: .any)
        let walk = any["act.walk"]
        XCTAssertTrue(walk.waitForExistence(timeout: 20), "нет кнопки «Гулять»")
        let value = walk.value as? String ?? ""
        XCTAssertTrue(value.contains("вернётся"), "в походе «Гулять» говорит, где пёс и когда вернётся (\(value))")
        _ = openMap(app)
        XCTAssertTrue(any["map.dog"].waitForExistence(timeout: 5), "на карте нет точки пса")
        XCTAssertTrue(any["map.trip"].exists, "нет строки «вернётся в …»")
        settle(1.5)
        snap("ui-34-map-3")
        app.terminate()
    }

    @MainActor
    private func launch(_ seed: String) -> XCUIApplication {
        let app = ScreenshotUITests.makeApp()
        app.launchEnvironment["PET_SEED"] = seed
        app.launchEnvironment["PET_NOW"] = ScreenshotUITests.noon
        app.launchEnvironment["PET_SCHEME"] = "light"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        XCTAssertTrue(app.descendants(matching: .any)["pet.stage"].waitForExistence(timeout: 20), "нет сцены pet.stage")
        return app
    }

    /// «Гулять» с главной → лист карты.
    @MainActor
    private func openMap(_ app: XCUIApplication) -> XCUIElement {
        let any = app.descendants(matching: .any)
        let walk = any["act.walk"]
        XCTAssertTrue(walk.waitForExistence(timeout: 10), "нет кнопки «Гулять»")
        let screen = any["map.screen"]
        XCTAssertTrue(tap(walk, expecting: screen, timeout: 10, name: "ui-34-map-open"), "карта не открылась")
        return screen
    }
}
