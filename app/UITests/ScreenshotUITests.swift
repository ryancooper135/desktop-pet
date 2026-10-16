// Скриншоты настоящего приложения на симуляторе. Каждый снимок — вложение keepAlways в xcresult,
// CI выгружает их в PNG (xcresulttool export attachments) под именем вложения.
//
// Что снимается:
//   ui-00-alert-N   системные запросы (уведомления, движение), если всплыли; потом «Разрешить»
//   ui-01-main      главный экран
//   ui-01-main-tree дерево элементов главного экрана (txt) — по нему видно accessibilityIdentifier
//   ui-1N-tab-N     каждая вкладка TabView, если она есть
//   ui-2N-<имя>     экраны из списка `screens` ниже (по accessibilityIdentifier)
//   ui-90-home      рабочий стол после выхода: видно остров, если приложение запустило Live Activity

import XCTest

final class ScreenshotUITests: XCTestCase {
    /// Экран → accessibilityIdentifier кнопки, которая его открывает с главного.
    /// Нет такого элемента — снимок пропускается. Дополняется по мере появления экранов.
    static let screens: [(name: String, identifier: String)] = [
        ("ui-21-shop", "open.shop"),
        ("ui-22-home", "open.home"),
        ("ui-23-wardrobe", "open.wardrobe"),
        ("ui-24-settings", "open.settings"),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testScreens() throws {
        let app = Self.makeApp()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        settle(2)
        acceptSystemAlerts()
        settle(2)

        snap("ui-01-main")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "ui-01-main-tree"
        tree.lifetime = .keepAlways
        add(tree)

        // Какие экраны из списка вообще есть на главном — только их и открываем.
        let present = Self.screens.filter { app.descendants(matching: .any)[$0.identifier].exists }

        // Вкладки, если приложение на TabView.
        let tabs = app.tabBars.buttons
        for i in 0..<min(tabs.count, 6) {
            let tab = tabs.element(boundBy: i)
            guard tab.exists, tab.isHittable else { continue }
            tab.tap()
            settle(1)
            snap("ui-1\(i + 1)-tab-\(i + 1)")
        }

        // Экраны по идентификаторам: каждый с чистого запуска, чтобы не искать «назад».
        for screen in present {
            app.terminate()
            app.launch()
            settle(2)
            let el = app.descendants(matching: .any)[screen.identifier]
            guard el.waitForExistence(timeout: 2), el.isHittable else { continue }
            el.tap()
            settle(1.5)
            snap(screen.name)
        }

        // Рабочий стол: остров с Live Activity (если она есть).
        XCUIDevice.shared.press(.home)
        settle(2)
        snap("ui-90-home")
    }

    // MARK: - Помощники

    @MainActor
    static func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-uiTesting"]
        app.launchEnvironment["PET_UI_TEST"] = "1"
        // Чистый щенок на каждом запуске: юнит-тесты до этого писали в тот же стор.
        app.launchEnvironment["PET_RESET"] = "1"
        return app
    }

    @MainActor
    func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Дать анимациям и 3D-сцене дорисоваться.
    func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Системные алерты рисует SpringBoard, не приложение: снимаем и разрешаем.
    @MainActor
    func acceptSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = ["Разрешить", "Allow", "OK", "ОК", "Разрешить при использовании", "Allow While Using App"]
        for n in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: n == 0 ? 2 : 1) else { return }
            snap("ui-00-alert-\(n + 1)")
            var tapped = false
            for title in allow where alert.buttons[title].exists {
                alert.buttons[title].tap()
                tapped = true
                break
            }
            if !tapped {
                let count = alert.buttons.count
                guard count > 0 else { return }
                alert.buttons.element(boundBy: count - 1).tap()
            }
            settle(1)
        }
    }
}
