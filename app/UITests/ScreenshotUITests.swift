// Скриншоты настоящего приложения на симуляторе. Каждый снимок — вложение keepAlways в xcresult,
// CI выгружает их в PNG (xcresulttool export attachments) под именем вложения.
//
// Что снимается:
//   ui-00-alert-N   системные запросы (уведомления, движение), если всплыли; потом «Разрешить»
//   ui-01-main      главный экран
//   ui-01-main-tree дерево элементов главного экрана (txt) — по нему видно accessibilityIdentifier
//   ui-1N-tab-N     каждая вкладка TabView, если она есть
//   ui-2N-<имя>     экраны из списка `screens` ниже (по accessibilityIdentifier)
//   ui-4N-<имя>     состояния с отдельного запуска (testStates*): критично, смерть, шкалы, «Пока тебя не было»,
//                   тёмная тема, автомат, вкусы в альбоме, открытка дня. Состояние задаёт окружение запуска
//                   (PET_SEED, PET_AWAY_H, PET_OPEN, PET_SCHEME).
//   ui-5N-room-*    дом в комнате: все линии на максимуме, уровни 1–2 вперемешку, максимум в тёмной теме
// Ждём элементы через waitForExistence; Thread.sleep остался только там, где ждать нечего (3D-сцена, SpringBoard).
//   ui-90-home      рабочий стол после выхода: видно остров, если приложение запустило Live Activity

import XCTest

final class ScreenshotUITests: XCTestCase {
    /// Экран → accessibilityIdentifier кнопки, которая его открывает с главного.
    /// Нет такого элемента — снимок пропускается. Дополняется по мере появления экранов
    /// (магазин, дом и гардероб вернутся сюда вместе со своими кнопками).
    static let screens: [(name: String, identifier: String)] = [
        ("ui-24-settings", "open.settings"),
    ]

    /// Элемент, по которому видно, что главный экран дорисовался.
    static let mainMarker = "open.settings"

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testScreens() throws {
        let app = Self.makeApp()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        waitForMain(app)

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
            let el = app.descendants(matching: .any)[screen.identifier]
            guard el.waitForExistence(timeout: 15), el.isHittable else { continue }
            el.tap()
            settle(1.5)
            snap(screen.name)
        }

        // Рабочий стол: остров с Live Activity (если она есть).
        XCUIDevice.shared.press(.home)
        settle(2)
        snap("ui-90-home")
    }

    // MARK: - Состояния (каждое — с чистого запуска)

    /// Уровень 3 в приложении: красная виньетка, кнопка «Спасти», обводка карточки.
    @MainActor
    func testStates40Critical() {
        shootState("ui-40-critical", env: ["PET_SEED": "critical"], marker: "act.rescue")
    }

    /// Питомец умер: «Нет с нами» и кнопка «Начать заново» вместо панели.
    @MainActor
    func testStates41Dead() {
        shootState("ui-41-dead", env: ["PET_SEED": "dead"], marker: "act.startOver")
    }

    /// Шкалы (NeedsSheet) — открываются сами через PET_OPEN, без жеста.
    @MainActor
    func testStates42Needs() {
        shootState("ui-42-needs", env: ["PET_OPEN": "needs"], marker: "needs.sheet")
    }

    /// «Пока тебя не было» после 9 часов без приложения.
    @MainActor
    func testStates43Away() {
        shootState("ui-43-away", env: ["PET_AWAY_H": "9"], marker: "away.screen")
    }

    /// Главный экран в тёмной теме.
    @MainActor
    func testStates44MainDark() {
        shootState("ui-44-main-dark", env: ["PET_SCHEME": "dark"], marker: Self.mainMarker)
    }

    /// Критично в тёмной теме: красное не должно тонуть в тёмном.
    @MainActor
    func testStates45CriticalDark() {
        shootState("ui-45-critical-dark", env: ["PET_SEED": "critical", "PET_SCHEME": "dark"], marker: "act.rescue")
    }

    // MARK: - Волна 5 (элемента нет — тест пропускается, а не падает)

    /// Автомат с капсулами: цены, полоска гаранта, пустой инвентарь.
    @MainActor
    func testStates46Capsule() throws {
        try shootOptional("ui-46-capsule", env: ["PET_OPEN": "capsule"], marker: "capsule.screen")
    }

    /// Альбом, раздел «Вкусы»: один открытый вкус и один «???» с полоской.
    @MainActor
    func testStates47Tastes() throws {
        try shootOptional("ui-47-tastes", env: ["PET_SEED": "tastes", "PET_OPEN": "album"], marker: "album.tastes",
                          scrollIn: "album.sheet")
    }

    /// «Открытка дня» на главной, потом сам лист открытки.
    @MainActor
    func testStates48Postcard() throws {
        let app = try shootOptional("ui-48-postcard", env: ["PET_SEED": "postcard"], marker: "postcard.card",
                                    keepRunning: true)
        app.descendants(matching: .any)["postcard.card"].tap()
        if app.descendants(matching: .any)["postcard.sheet"].waitForExistence(timeout: 10) {
            settle(1.5)
            snap("ui-48-postcard-sheet")
        }
        app.terminate()
    }

    /// Экран «Дом»: шесть линий на стартовых уровнях, кнопки «Купить» и «Не хватает N». Тёмная — чтобы проверить тему.
    @MainActor
    func testStates49House() throws {
        try shootOptional("ui-49-house", env: ["PET_OPEN": "house"], marker: "house.screen")
        try shootOptional("ui-49-house-dark", env: ["PET_OPEN": "house", "PET_SCHEME": "dark"], marker: "house.screen")
    }

    // MARK: - Дом в комнате (RoomDecor)

    /// Все линии дома на верхнем уровне: кухня, ванна, окно с двором и будкой, лежанка, игровой угол.
    @MainActor
    func testStates51RoomMax() {
        shootState("ui-51-room-max", env: ["PET_SEED": "room_max"], marker: Self.mainMarker, settleFor: 2.5)
    }

    /// Уровни 1–2 вперемешку: промежуточные вещи не налезают друг на друга.
    @MainActor
    func testStates52RoomMid() {
        shootState("ui-52-room-mid", env: ["PET_SEED": "room_mid"], marker: Self.mainMarker, settleFor: 2.5)
    }

    /// Верхний уровень в тёмной теме: комната та же, проверяем, что интерфейс поверх читается.
    @MainActor
    func testStates53RoomMaxDark() {
        shootState("ui-53-room-max-dark", env: ["PET_SEED": "room_max", "PET_SCHEME": "dark"], marker: Self.mainMarker,
                   settleFor: 2.5)
    }

    /// Как shootState, но без маркера — XCTSkip (экран ещё не в этой сборке). Снимок делается в любом случае.
    /// scrollIn — контейнер, который листаем вверх, пока маркер не станет видимым.
    @MainActor
    @discardableResult
    func shootOptional(_ name: String, env: [String: String], marker: String, scrollIn: String? = nil,
                       keepRunning: Bool = false) throws -> XCUIApplication {
        let app = Self.makeApp()
        for (k, v) in env { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        let element = app.descendants(matching: .any)[marker]
        let found = element.waitForExistence(timeout: 20)
        if found, let scrollIn {
            let box = app.descendants(matching: .any)[scrollIn]
            for _ in 0..<4 where !element.isHittable {
                box.swipeUp()
                settle(0.5)
            }
        }
        settle(1.5)
        snap(name)
        guard found else {
            app.terminate()
            throw XCTSkip("\(name): нет элемента \(marker)")
        }
        if !keepRunning { app.terminate() }
        return app
    }

    /// Запуск с окружением → ждать маркер → снимок. Снимок делается и без маркера: по нему видно, что пошло не так.
    @MainActor
    func shootState(_ name: String, env: [String: String], marker: String, settleFor: TimeInterval = 1.5) {
        let app = Self.makeApp()
        for (k, v) in env { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        let found = app.descendants(matching: .any)[marker].waitForExistence(timeout: 20)
        settle(settleFor)
        snap(name)
        XCTAssertTrue(found, "\(name): нет элемента \(marker)")
        app.terminate()
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

    /// Главный экран на месте (по mainMarker), плюс секунда сцене на первый кадр.
    /// Маркера нет (старая сборка) — просто подождать, как раньше.
    @MainActor
    func waitForMain(_ app: XCUIApplication) {
        if !app.descendants(matching: .any)[Self.mainMarker].waitForExistence(timeout: 15) {
            settle(2)
        }
        settle(1)
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
