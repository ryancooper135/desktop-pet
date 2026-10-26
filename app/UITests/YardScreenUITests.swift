// Волна 34 G: экран «Двор» (YardScreen). Открываем через PET_OPEN=yard на сидах LaunchSeed.seedYard.
// Что во дворе, видно по значению yard.screen.scene: «plates=N,tier=K,dryer=3,…».
//   ui-34-yard-empty    пустырь: «Протереть окно» за 10 🪙, копилка пустая
//   ui-34-yard-plates   «Дворик»: сушилка, карточка «Дорожка» и полоска «ещё 80 🪙»
//   ui-34-yard-station  «Сад»: сушилка выросла до ур. 4
//   ui-34-yard-collect  полная копилка собрана: тост со свинкой
// Волна 35 M (значение сцены ещё «dog=<клип>,gold=<станции>,dog3d=on|load|wait|off|none» — dog3d: пёс уже в сцене и кадр дошёл):
//   ui-35-yard-dog      Шиба у каши смотрит на пар (PET_YARD_DOG=porridge)
//   ui-35-yard-plate    объёмные таблички «+N/ч» над станциями, у косточек золотая
//   ui-35-yard-gold     сушилке купили золотую табличку за 60 ✂️

import XCTest

final class YardScreenUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ seed: String, dog: String? = nil) -> XCUIApplication {
        let app = ScreenshotUITests.makeApp()
        app.launchEnvironment["PET_SEED"] = seed
        if let dog { app.launchEnvironment["PET_YARD_DOG"] = dog }
        app.launchEnvironment["PET_NOW"] = ScreenshotUITests.noon
        app.launchEnvironment["PET_SCHEME"] = "light"
        app.launchEnvironment["PET_OPEN"] = "yard"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        return app
    }

    /// Пустырь: снимок, потом первая плита покупается с первого нажатия.
    @MainActor
    func testEmptyYardBuysFirstPlate() throws {
        let app = launch("yard_empty")
        let any = app.descendants(matching: .any)
        let scene = any["yard.screen.scene"]
        XCTAssertTrue(scene.waitForExistence(timeout: 20), "экран «Двор» не открылся")
        XCTAssertTrue(wait(scene, valueHas: "plates=0"), "сид yard_empty: двор пустой (\(String(describing: scene.value)))")
        settle(2)
        snap("ui-34-yard-empty")

        let buy = any["yard.screen.plate.buy"]
        XCTAssertTrue(tapWhenReady(buy), "нет кнопки «Купить»")
        XCTAssertTrue(wait(scene, valueHas: "plates=1"), "плита не встала (\(String(describing: scene.value)))")
        app.terminate()
    }

    /// Дворик: снимок; без монет кнопка не немая — тост объясняет, сколько не хватает.
    @MainActor
    func testPlatesRefuseExplains() throws {
        let app = launch("yard_plates")
        let any = app.descendants(matching: .any)
        let scene = any["yard.screen.scene"]
        XCTAssertTrue(scene.waitForExistence(timeout: 20), "экран «Двор» не открылся")
        XCTAssertTrue(wait(scene, valueHas: "dryer=2"), "сид yard_plates: сушилка ур. 2 (\(String(describing: scene.value)))")
        XCTAssertTrue(any["yard.screen.plate.more"].waitForExistence(timeout: 5), "нет строки «ещё N 🪙»")
        settle(2)
        snap("ui-34-yard-plates")

        let buy = any["yard.screen.plate.buy"]
        XCTAssertTrue(tap(buy, expecting: any["toast"], timeout: 5, name: "ui-34-yard-refuse"), "отказ без тоста")
        XCTAssertTrue(wait(scene, valueHas: "plates=4"), "без монет плита не покупается")
        app.terminate()
    }

    /// Сад: улучшить сушилку, потом собрать полную копилку.
    @MainActor
    func testUpgradeAndCollect() throws {
        let app = launch("yard_rich")
        let any = app.descendants(matching: .any)
        let screen = any["yard.screen"]
        let scene = any["yard.screen.scene"]
        XCTAssertTrue(scene.waitForExistence(timeout: 20), "экран «Двор» не открылся")
        XCTAssertTrue(wait(scene, valueHas: "dryer=3"), "сид yard_rich: сушилка ур. 3 (\(String(describing: scene.value)))")

        // Сначала копилка — она наверху, под сценой.
        let collect = any["yard.screen.collect"]
        XCTAssertTrue(tap(collect, expecting: any["toast"], timeout: 5, name: "ui-34-yard-collect-miss"), "сбор без тоста")
        settle(0.6)
        snap("ui-34-yard-collect")

        let up = any["yard.screen.station.dryer.up"]
        XCTAssertTrue(up.waitForExistence(timeout: 5), "нет кнопки «Улучшить» у сушилки")
        reveal(up, in: screen, app: app)
        XCTAssertTrue(tapWhenReady(up), "«Улучшить» не нажимается")
        XCTAssertTrue(wait(scene, valueHas: "dryer=4"), "сушилка не выросла (\(String(describing: scene.value)))")
        settle(1)
        snap("ui-34-yard-station")

        let close = any["yard.screen.close"]
        reveal(close, in: screen, app: app)
        XCTAssertTrue(tapWhenReady(close), "нет крестика")
        XCTAssertTrue(screen.waitForNonExistence(timeout: 5), "двор не закрылся")
        XCTAssertTrue(any["open.yard"].waitForExistence(timeout: 10), "на главной нет кнопки «Двор»")
        app.terminate()
    }

    /// Шиба сам ходит к станциям; в тесте держим его у каши, чтобы снимок был про дело, а не про дорогу.
    @MainActor
    func testDogAtStation() throws {
        let app = launch("yard_rich", dog: "porridge")
        let scene = app.descendants(matching: .any)["yard.screen.scene"]
        XCTAssertTrue(scene.waitForExistence(timeout: 20), "экран «Двор» не открылся")
        XCTAssertTrue(wait(scene, valueHas: "dog=act.porridge", timeout: 10),
                      "пёс не у каши (\(String(describing: scene.value)))")
        XCTAssertTrue(scene.label.contains("Шиба"), "VoiceOver не говорит, где Шиба: \(scene.label)")
        // План говорит «у каши» сразу, а модель грузится отдельно: ждём, пока пёс сядет в сцену и она отрисуется.
        XCTAssertTrue(wait(scene, valueHas: "dog3d=on", timeout: 45),
                      "пёс не появился в сцене (\(String(describing: scene.value)))")
        settle(3)
        snap("ui-35-yard-dog")
        app.terminate()
    }

    /// Таблички в сцене, потом золотая табличка сушилки за клочки.
    @MainActor
    func testGoldPlate() throws {
        let app = launch("yard_rich")
        let any = app.descendants(matching: .any)
        let screen = any["yard.screen"]
        let scene = any["yard.screen.scene"]
        XCTAssertTrue(scene.waitForExistence(timeout: 20), "экран «Двор» не открылся")
        XCTAssertTrue(wait(scene, valueHas: "gold=bones"), "сид yard_rich: косточки золотые (\(String(describing: scene.value)))")
        XCTAssertTrue(scene.label.contains("/ч"), "VoiceOver не читает доход станций: \(scene.label)")
        _ = wait(scene, valueHas: "dog3d=on", timeout: 45)
        settle(2)
        snap("ui-35-yard-plate")

        let gold = any["yard.screen.station.dryer.gold"]
        XCTAssertTrue(gold.waitForExistence(timeout: 5), "нет кнопки золотой таблички у сушилки")
        reveal(gold, in: screen, app: app)
        XCTAssertTrue(tapWhenReady(gold), "золотая табличка не нажимается")
        XCTAssertTrue(wait(scene, valueHas: "gold=bones,dryer"), "сушилка не стала золотой (\(String(describing: scene.value)))")
        XCTAssertTrue(any["yard.screen.station.dryer.goldOwned"].waitForExistence(timeout: 5), "нет строки «Золотая табличка»")
        // Наверх до шапки: сцена видна целиком.
        reveal(any["yard.screen.close"], in: screen, app: app)
        reveal(scene, in: screen, app: app)
        // Золото пересобрало сцену: ждём, пока новая отрисуется (пёс в ней — значит, кадры идут).
        _ = wait(scene, valueHas: "dog3d=on", timeout: 30)
        settle(3)
        snap("ui-35-yard-gold")
        app.terminate()
    }

    /// Прокрутить экран двора, пока рамка e целиком не окажется в окне. Не swipeUp/swipeDown: их середина экрана
    /// попадает в 3D-сцену, и на CI свайп то листал, то нет; и не isHittable: у кнопки за краем экрана в ScrollView
    /// он бывает true. Тянем пальцем ниже сцены (или выше — вниз) по рамкам, до 8 рывков.
    @MainActor
    private func reveal(_ e: XCUIElement, in screen: XCUIElement, app: XCUIApplication) {
        guard e.waitForExistence(timeout: 5) else { return }
        let win = app.windows.firstMatch.frame
        let top = win.minY + 60, bottom = win.maxY - 60
        for _ in 0..<8 {
            let f = e.frame
            if f.minY >= top && f.maxY <= bottom { return }
            let low = screen.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
            let high = screen.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            // Ниже окна — тянем вверх, выше — вниз; шаг ~четверть экрана, чтобы не проскочить.
            if f.maxY > bottom {
                low.press(forDuration: 0.05, thenDragTo: high, withVelocity: .slow, thenHoldForDuration: 0.1)
            } else {
                high.press(forDuration: 0.05, thenDragTo: low, withVelocity: .slow, thenHoldForDuration: 0.1)
            }
            settle(0.5)
        }
    }

    /// Значение элемента содержит text (ждём до timeout секунд).
    @MainActor
    private func wait(_ e: XCUIElement, valueHas text: String, timeout: TimeInterval = 5) -> Bool {
        let p = NSPredicate(format: "value CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: timeout) == .completed
    }
}
