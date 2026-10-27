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
// Волна 36 P (в значении сцены ещё «moves=N»; сид yard_full — пёс ур. переезда (28), двор полный, 5000 🪙):
//   ui-36-yard-move          внизу тихая карточка «Переезд двора»
//   ui-36-yard-move-confirm  подтверждение: что останется, что заново, слава ×1,5
//   ui-36-yard-trip          сразу после «Переехать»: экран фургона «Улица → Зимний квартал»
//   ui-36-yard-moved         переехали: двор пустой, в шапке ★ славы

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
        // Сад с 3D-станциями: на CI дерево запросов медленное, 3 мин по умолчанию не хватало (прогон 40398816300).
        executionTimeAllowance = 300
        let app = launch("yard_rich")
        let any = app.descendants(matching: .any)
        let screen = any["yard.screen"]
        let scene = any["yard.screen.scene"]
        XCTAssertTrue(scene.waitForExistence(timeout: 20), "экран «Двор» не открылся")
        XCTAssertTrue(wait(scene, valueHas: "dryer=3"), "сид yard_rich: сушилка ур. 3 (\(String(describing: scene.value)))")

        // Сначала копилка — она наверху, под сценой.
        let collect = any["yard.screen.collect"]
        XCTAssertTrue(tap(collect, expecting: any["toast"], timeout: 8, name: "ui-34-yard-collect-miss"), "сбор без тоста")
        settle(0.6)
        snap("ui-34-yard-collect")

        let up = any["yard.screen.station.dryer.up"]
        XCTAssertTrue(up.waitForExistence(timeout: 5), "нет кнопки «Улучшить» у сушилки")
        reveal(up, in: screen, app: app)
        XCTAssertTrue(tapWhenReady(up), "«Улучшить» не нажимается")
        XCTAssertTrue(wait(scene, valueHas: "dryer=4", timeout: 20), "сушилка не выросла (\(String(describing: scene.value)))")
        settle(1)
        snap("ui-34-yard-station")

        let close = any["yard.screen.close"]
        toTop(screen, app: app)
        reveal(close, in: screen, app: app)
        XCTAssertTrue(tapWhenReady(close), "нет крестика")
        XCTAssertTrue(screen.waitForNonExistence(timeout: 10), "двор не закрылся")
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
        toTop(screen, app: app)
        reveal(any["yard.screen.close"], in: screen, app: app)
        reveal(scene, in: screen, app: app)
        // Золото пересобрало сцену: ждём, пока новая отрисуется (пёс в ней — значит, кадры идут).
        _ = wait(scene, valueHas: "dog3d=on", timeout: 30)
        settle(3)
        snap("ui-35-yard-gold")
        app.terminate()
    }

    /// Переезд: карточка внизу, подтверждение («Остаться» закрывает, «Переехать» — двор заново), звёзды славы.
    @MainActor
    func testMoveYard() throws {
        // Полный двор — восемь станций в 3D и длинный список: на CI листать долго.
        executionTimeAllowance = 300
        let app = launch("yard_full")
        let any = app.descendants(matching: .any)
        let screen = any["yard.screen"]
        let scene = any["yard.screen.scene"]
        XCTAssertTrue(scene.waitForExistence(timeout: 20), "экран «Двор» не открылся")
        XCTAssertTrue(wait(scene, valueHas: "moves=0", timeout: 10),
                      "сид yard_full: переездов не было (\(String(describing: scene.value)))")
        XCTAssertFalse(any["yard.screen.glory"].exists, "до переезда звёзд славы нет")

        let move = any["yard.screen.move"]
        XCTAssertTrue(move.waitForExistence(timeout: 10), "нет карточки «Переезд двора»")
        // Карточка в самом низу, под восемью станциями: одного захода reveal (8 рывков) может не хватить.
        for _ in 0..<3 { reveal(move, in: screen, app: app) }
        settle(1.5)
        snap("ui-36-yard-move")

        let confirm = any["yard.screen.move.confirm"]
        let cancel = any["yard.screen.move.cancel"]
        XCTAssertTrue(tap(move, expecting: confirm, timeout: 8, name: "ui-36-yard-move-miss"), "подтверждение не открылось")
        XCTAssertTrue(cancel.exists, "нет кнопки «Остаться»")
        settle(1)
        snap("ui-36-yard-move-confirm")

        // «Остаться» — ничего не меняется.
        XCTAssertTrue(tapWhenReady(cancel), "«Остаться» не нажимается")
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 8), "подтверждение не закрылось")
        XCTAssertTrue(wait(scene, valueHas: "moves=0"), "«Остаться» переселило двор (\(String(describing: scene.value)))")

        // Теперь всерьёз.
        XCTAssertTrue(tap(move, expecting: confirm, timeout: 8, name: "ui-36-yard-move-miss2"),
                      "подтверждение не открылось второй раз")
        XCTAssertTrue(tapWhenReady(confirm), "«Переехать» не нажимается")
        // Сразу после переезда — экран фургона поверх двора; «Готово» возвращает к пустому двору.
        let caption = any["yard.move.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 10), "после переезда нет экрана фургона")
        XCTAssertEqual(caption.label, "Переезжаем: Улица → Зимний квартал")
        settle(2.5)
        snap("ui-36-yard-trip")
        XCTAssertTrue(tapWhenReady(any["yard.move.close"]), "«Готово» на экране фургона не нажимается")
        XCTAssertTrue(caption.waitForNonExistence(timeout: 8), "экран фургона не закрылся")
        XCTAssertTrue(wait(scene, valueHas: "moves=1", timeout: 20), "переезд не случился (\(String(describing: scene.value)))")
        XCTAssertTrue(wait(scene, valueHas: "plates=0"), "после переезда плиты остались (\(String(describing: scene.value)))")
        XCTAssertTrue(move.waitForNonExistence(timeout: 8), "карточка переезда не ушла с пустого двора")
        // Волна 37 A: вместо кнопки — тусклая карточка «почему закрыт и сколько осталось».
        let locked = any["yard.screen.move.locked"]
        XCTAssertTrue(locked.waitForExistence(timeout: 8), "после переезда нет тусклой карточки переезда")
        let lockedValue = (locked.value as? String) ?? ""
        XCTAssertTrue(lockedValue.contains("Откроется, когда двор достроен"), "тусклая карточка: \(lockedValue)")

        toTop(screen, app: app)
        reveal(any["yard.screen.close"], in: screen, app: app)
        let glory = any["yard.screen.glory"]
        XCTAssertTrue(glory.waitForExistence(timeout: 10), "в шапке нет звёзд славы")
        XCTAssertTrue(glory.label.contains("Слава"), "VoiceOver не читает славу: \(glory.label)")
        reveal(scene, in: screen, app: app)
        settle(2)
        snap("ui-36-yard-moved")
        app.terminate()
    }

    /// Прокрутить экран двора, пока рамка e целиком не окажется в окне. Не swipeUp/swipeDown: их середина экрана
    /// попадает в 3D-сцену, и на CI свайп то листал, то нет; и не isHittable: у кнопки за краем экрана в ScrollView
    /// он бывает true. Тянем пальцем ниже сцены (или выше — вниз) по рамкам, до 8 рывков. Сцена, ушедшая за край,
    /// снимается с экрана (YardScreen.sceneOnScreen) — дальше листается легко.
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
            settle(0.8)
            // На медленном CI-симуляторе рывок иногда не доходит: рамка не сдвинулась — даём приложению отдышаться.
            if abs(e.frame.minY - f.minY) < 1 { settle(2) }
        }
    }

    /// Наверх одним касанием строки состояния (scrollsToTop): на медленном CI это надёжнее рывков вниз —
    /// по пути вверх сцена снова встаёт на экран и тяжелеет, и второй-третий рывок не успевал дойти.
    @MainActor
    private func toTop(_ screen: XCUIElement, app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
        settle(1.5)
    }

    /// Значение элемента содержит text (ждём до timeout секунд).
    @MainActor
    private func wait(_ e: XCUIElement, valueHas text: String, timeout: TimeInterval = 5) -> Bool {
        let p = NSPredicate(format: "value CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: timeout) == .completed
    }
}
