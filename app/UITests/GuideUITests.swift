// Скриншоты подсказок: PET_GUIDE=rules|widget показывает нужную один раз сразу после запуска.
// В обычных UI-тестах подсказки молчат (GuideCenter), поэтому остальные скриншоты не меняются.

import XCTest

final class GuideUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testRulesScreen() throws {
        try shoot(guide: "rules", button: "rules.ok", name: "ui-30-rules")
    }

    @MainActor
    func testWidgetGuide() throws {
        try shoot(guide: "widget", button: "guide.done", name: "ui-31-widget-guide")
    }

    @MainActor
    private func shoot(guide: String, button: String, name: String) throws {
        let app = ScreenshotUITests.makeApp()
        app.launchEnvironment["PET_GUIDE"] = guide
        app.launch()
        let ok = app.buttons[button]
        XCTAssertTrue(ok.waitForExistence(timeout: 20), "подсказка \(guide) не показалась")
        settle(1.5)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        tapWhenReady(ok)
        XCTAssertTrue(app.buttons[button].waitForNonExistence(timeout: 5), "подсказка \(guide) не закрылась")
    }
}
