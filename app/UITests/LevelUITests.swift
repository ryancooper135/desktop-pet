// Волна 34 I: уровень пса и рост. Сиды LaunchSeed: level_puppy (ур. 4, щенок), level_up (ур. 3 ещё не показан —
// сцена нового уровня сама при запуске), level_adult (ур. 12, взрослый).
//   ui-34-level-header  шапка со значком «ур. 4» и полоской опыта
//   ui-34-level-sheet   лист «Уровень»: опыт, сегодня, рост, что откроется
//   ui-34-level-puppy   щенок в комнате: маленький, голова крупнее, уши висят
//   ui-34-level-up      сцена нового уровня: «★3» и тост «Уровень 3! +… 🪙»
//   ui-34-level-adult   взрослый пёс в полный рост

import XCTest

final class LevelUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHeaderAndSheetPuppy() throws {
        let app = launch("level_puppy")
        let any = app.descendants(matching: .any)

        let chip = any["level.chip"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 15), "нет значка уровня в шапке")
        XCTAssertTrue(chip.label.contains("Уровень 4"), "значок: \(chip.label)")
        settle(1.5)
        snap("ui-34-level-header")

        let sheet = any["level.sheet"].firstMatch
        XCTAssertTrue(tap(chip, expecting: sheet, timeout: 10, name: "ui-34-level-chip"), "лист «Уровень» не открылся")
        XCTAssertTrue(any["level.title"].firstMatch.waitForExistence(timeout: 5), "нет заголовка листа")
        let growth = any["level.growth"].firstMatch
        XCTAssertTrue(growth.waitForExistence(timeout: 5), "нет строки роста")
        XCTAssertTrue(growth.label.contains("Щенок"), "строка роста: \(growth.label)")
        settle(1)
        snap("ui-34-level-sheet")

        let close = any["level.close"].firstMatch
        XCTAssertTrue(tapWhenReady(close), "нет кнопки закрытия листа")
        _ = sheet.waitForNonExistence(timeout: 5)
        XCTAssertFalse(sheet.exists, "лист «Уровень» не закрылся")
        settle(2)
        snap("ui-34-level-puppy")
        app.terminate()
    }

    @MainActor
    func testLevelUpScene() throws {
        let app = launch("level_up")
        let any = app.descendants(matching: .any)

        // Сцена идёт сама: refresh видит оплаченный, но не показанный уровень. Тост «Уровень 3!» живёт 2.6 с, потом
        // его сменяет «Открылось: …» — пока тест закрывает системные окна, первый можно пропустить. Годится любой из двух.
        let toast = any.matching(identifier: "toast")
            .matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "Уровень 3", "Открылось")).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 15), "нет тоста нового уровня")
        snap("ui-34-level-up")

        let chip = any["level.chip"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "нет значка уровня в шапке")
        XCTAssertTrue(chip.label.contains("Уровень 3"), "значок: \(chip.label)")
        app.terminate()
    }

    @MainActor
    func testAdult() throws {
        let app = launch("level_adult")
        let any = app.descendants(matching: .any)

        let chip = any["level.chip"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 15), "нет значка уровня в шапке")
        XCTAssertTrue(chip.label.contains("Уровень 12"), "значок: \(chip.label)")
        settle(2)
        snap("ui-34-level-adult")
        app.terminate()
    }

    /// Запуск с сидом в полдень, светлая тема; ждём сцену.
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
}
