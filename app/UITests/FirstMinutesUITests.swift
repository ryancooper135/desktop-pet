// Волна 21: первые 15 минут глазами новичка (ui-94-*). Свежая установка (PET_RESET), полдень (PET_NOW), светлая
// тема, подсказки новичка включены (PET_TIPS=1), знакомство — только в первой части (PET_GUIDE=intro).
// Снимок на каждом шаге: по ним смотрят, понятен ли следующий шаг, нет ли тупиков, наложений и спорящих подсказок.
// Путь разбит на четыре части: у каждого теста в CI 180 с, и каждая часть начинает со свежего щенка.
//   ui-94-0N  знакомство (3 карточки) → главный экран → плашка «что нужно» → по ней → покормить, погладить
//             пальцем, кнопкой, поиграть
//   ui-94-2N  шкалы: свайп вверх по сцене → закрыть → ручка «⌃ Шкалы» → закрыть
//   ui-94-3N  круги: Альбом, Автомат, Дом, Трюки, Мини-игры (меню → «Лови мячик» → крестик) — открыть и назад
//   ui-94-4N  «Гулять» → настройки → «Подсказки» → «Честно о главном» → закрыть настройки
// Волна 22 «одно сообщение за раз» (ui-95-*, PET_SEED=wants_pet): палец и плашка без повтора фразы, палец прячется,
// пока Шиба ест, и возвращается; после ласки кнопкой — один тост, подсказка жеста ждёт; шкалы с крестиком
// и «щенячьим пухом» вместо «колтуны — расчеши».

import XCTest

final class FirstMinutesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// Окружение новичка: полдень, светлая тема, подсказки жестов и палец-учитель.
    private static func env(intro: Bool = false) -> [String: String] {
        var e = ["PET_TIPS": "1", "PET_NOW": ScreenshotUITests.noon, "PET_SCHEME": "light"]
        if intro { e["PET_GUIDE"] = "intro" }
        return e
    }

    @MainActor
    private func launch(intro: Bool = false) -> XCUIApplication {
        let app = ScreenshotUITests.makeApp()
        for (k, v) in Self.env(intro: intro) { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        return app
    }

    @MainActor
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor
    private func waitHome(_ app: XCUIApplication) {
        _ = el(app, ScreenshotUITests.mainMarker).waitForExistence(timeout: 20)
        settle(2)
    }

    /// Назад с листа: крестик, если есть; иначе смахнуть лист вниз, как сделал бы новичок. Снимок после.
    @MainActor
    private func back(_ app: XCUIApplication, sheet: String, close: String?, name: String) {
        let s = el(app, sheet)
        // Крестик ждём нажимаемым: лист мог ещё доезжать, и мгновенная проверка уводила в свайп.
        if let close, el(app, close).exists, waitHittable(el(app, close), timeout: 2) {
            el(app, close).tap()
        } else if s.exists {
            s.swipeDown(velocity: .fast)
        }
        var gone = s.waitForNonExistence(timeout: 4)
        if !gone {
            // Короткий лист: тап по затемнению над ним.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
            gone = s.waitForNonExistence(timeout: 3)
        }
        settle(0.8)
        snap(name)
        XCTAssertTrue(gone, "\(name): «\(sheet)» не закрылся")
    }

    /// Открыть кнопкой, снять, вернуться. Кнопку жмём, когда она нажимаема (прошлый лист уехал, затемнение ушло);
    /// лист не открылся, а кнопка свободна — тап ушёл в анимацию, ещё один (ui-94-31 так и падал на CI).
    @MainActor
    private func visit(_ app: XCUIApplication, button: String, sheet: String, close: String?, name: String) {
        let b = el(app, button)
        guard b.waitForExistence(timeout: 5) else {
            snap("\(name)-missing")
            XCTFail("\(name): нет кнопки \(button)")
            return
        }
        let opened = tap(b, expecting: el(app, sheet), name: name)
        settle(1.2)
        snap("\(name)-open")
        XCTAssertTrue(opened, "\(name): «\(sheet)» не открылся")
        if opened { back(app, sheet: sheet, close: close, name: "\(name)-back") }
    }

    // MARK: 1. Знакомство и первые действия

    @MainActor
    func testJourney1FirstSteps() {
        let app = launch(intro: true)
        let next = app.buttons["intro.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 20), "знакомство не показалось")
        settle(1.2)
        snap("ui-94-01-intro-1")
        for k in 2...3 {
            // Карточка ещё листается — ждём, пока «Дальше» снова нажимается.
            guard tapWhenReady(app.buttons["intro.next"], timeout: 3) else { break }
            settle(0.9)
            snap("ui-94-0\(k)-intro-\(k)")
        }
        let done = app.buttons["intro.done"]
        if done.waitForExistence(timeout: 5) { tapWhenReady(done) }
        _ = done.waitForNonExistence(timeout: 5)
        waitHome(app)
        snap("ui-94-04-home")
        settle(3)
        snap("ui-94-05-home-later")

        // Плашка «что нужно сейчас», если есть, — новичок жмёт её первой.
        let plate = el(app, "hint.plate")
        if plate.exists, tapWhenReady(plate, timeout: 2) {
            settle(1.5)
            snap("ui-94-06-plate-tapped")
        }

        // Кнопки панели по очереди: покормить, погладить пальцем, погладить кнопкой, поиграть.
        tapAct(app, "act.feed", name: "ui-94-07-feed")
        stroke(app)
        settle(0.4)
        snap("ui-94-08-stroke")
        settle(3)
        snap("ui-94-09-after-stroke")
        tapAct(app, "act.pet", name: "ui-94-10-pet-button")
        tapAct(app, "act.play", name: "ui-94-11-play")
        settle(3)
        snap("ui-94-12-home-after")
        app.terminate()
    }

    @MainActor
    private func tapAct(_ app: XCUIApplication, _ id: String, name: String) {
        guard tapWhenReady(el(app, id)) else {
            XCTFail("\(name): нет кнопки \(id)")
            return
        }
        settle(1.3)
        snap(name)
    }

    /// Провести пальцем по спине Шибы: медленно, слева направо почти во всю сцену — засчитывается от 150 pt
    /// (StrokeTracker.strokePath, та же длина, что дорожка пальца-учителя).
    @MainActor
    private func stroke(_ app: XCUIApplication) {
        let stage = el(app, "pet.stage")
        let base = stage.exists ? stage : app
        let a = base.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.55))
        let b = base.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.55))
        a.press(forDuration: 0.1, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    // MARK: 2. Шкалы: свайп и ручка

    @MainActor
    func testJourney2Scales() {
        let app = launch()
        waitHome(app)
        snap("ui-94-20-home")
        let stage = el(app, "pet.stage")
        (stage.exists ? stage : app).swipeUp()
        let bySwipe = el(app, "needs.sheet").waitForExistence(timeout: 4)
        settle(1)
        snap("ui-94-21-swipe-needs")
        XCTAssertTrue(bySwipe, "свайп вверх не открыл шкалы")
        if bySwipe { back(app, sheet: "needs.sheet", close: nil, name: "ui-94-22-needs-closed") }

        visit(app, button: "open.needs", sheet: "needs.sheet", close: "needs.close", name: "ui-94-23-handle")
        app.terminate()
    }

    // MARK: 5. Одно сообщение за раз (волна 22)

    @MainActor
    func testJourney5OneVoice() {
        let app = ScreenshotUITests.makeApp()
        for (k, v) in Self.env() { app.launchEnvironment[k] = v }
        app.launchEnvironment["PET_SEED"] = "wants_pet"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        let tutor = el(app, "tip.pet")
        let shown = tutor.waitForExistence(timeout: 20)
        settle(1.5)
        snap("ui-95-01-tutor-plate")
        XCTAssertTrue(shown, "ui-95-01: нет пальца-учителя")
        XCTAssertTrue(el(app, "hint.plate").exists, "ui-95-01: нет плашки «Погладить»")

        // Покормить: тост «+N монет», палец молчит, пока Шиба ест, и возвращается после.
        tapAct(app, "act.feed", name: "ui-95-02-feed")
        XCTAssertTrue(tutor.waitForNonExistence(timeout: 2), "ui-95-02: палец поверх тоста и жующего Шибы")
        settle(3.5)
        // «Тост и палец вместе» — одним снимком дерева: два запроса подряд гонялись с таймером тоста.
        let eating = idsNow(app)
        snap("ui-95-03-eating")
        XCTAssertFalse(eating.contains("toast") && eating.contains("tip.pet"), "ui-95-03: тост и палец вместе")
        XCTAssertFalse(eating.contains("tip.pet"), "ui-95-03: палец ходит по жующему Шибе")
        let tutorBack = tutor.waitForExistence(timeout: 14)
        settle(0.5)
        snap("ui-95-04-tutor-back")
        XCTAssertTrue(tutorBack, "ui-95-04: палец не вернулся после еды")

        // Погладить пальцем → подсказка жеста; кнопкой «Погладить» → тост отката, подсказка под ним молчит.
        stroke(app)
        let chip = el(app, "tip.gesture")
        let tip = chip.waitForExistence(timeout: 10)
        settle(0.4)
        snap("ui-95-05-gesture-tip")
        if tip {
            guard tapWhenReady(el(app, "act.pet")) else {
                XCTFail("ui-95-06: нет кнопки act.pet")
                app.terminate()
                return
            }
            // Тост живёт 2,5 с, а подсказка жеста после него возвращается: проверять «тост и подсказка вместе»
            // двумя запросами нельзя — тост успевал уйти между ними, подсказка вернуться, и тест ловил призрака.
            // Ждём тост, даём подсказке спрятаться и смотрим на одно мгновение дерева; снимок — тот же момент.
            _ = el(app, "toast").waitForExistence(timeout: 2)
            settle(0.8)
            let ids = idsNow(app)
            snap("ui-95-06-pet-button")
            XCTAssertFalse(ids.contains("toast") && ids.contains("tip.gesture"), "ui-95-06: тост и подсказка жеста вместе")
            XCTAssertFalse(ids.contains("toast") && ids.contains("tip.pet"), "ui-95-06: тост и палец вместе")
        }

        // Шкалы ручкой: крестик и строчка шерсти щенка без «колтуны — расчеши».
        let handle = el(app, "open.needs")
        let opened = handle.waitForExistence(timeout: 5) && tap(handle, expecting: el(app, "needs.sheet"), name: "ui-95-07-needs")
        settle(1)
        snap("ui-95-07-needs")
        XCTAssertTrue(opened, "ui-95-07: шкалы не открылись")
        let coat = el(app, "needs.coat")
        if coat.exists { XCTAssertFalse(coat.label.contains("колтуны"), "ui-95-07: щенку в первой сессии — «колтуны»") }
        XCTAssertTrue(el(app, "needs.close").exists, "ui-95-07: у шкал нет крестика")
        if opened { back(app, sheet: "needs.sheet", close: "needs.close", name: "ui-95-08-needs-closed") }
        app.terminate()
    }

    // MARK: 3. Круги над панелью

    @MainActor
    func testJourney3Circles() {
        let app = launch()
        waitHome(app)
        snap("ui-94-30-row")
        visit(app, button: "open.album", sheet: "album.sheet", close: "album.close", name: "ui-94-31-album")
        visit(app, button: "act.capsule", sheet: "capsule.screen", close: "capsule.close", name: "ui-94-32-capsule")
        visit(app, button: "open.house", sheet: "house.screen", close: "house.close", name: "ui-94-33-house")
        visit(app, button: "open.tricks", sheet: "tricks.screen", close: "tricks.close", name: "ui-94-34-tricks")

        // Мини-игры: меню из трёх, «Лови мячик» на весь экран, крестик.
        let games = el(app, "open.games")
        guard games.waitForExistence(timeout: 5) else {
            XCTFail("нет «Мини-игры»")
            app.terminate()
            return
        }
        let ball = app.buttons["open.catch"]
        let menu = tap(games, expecting: ball, timeout: 4, name: "ui-94-35-games-menu")
        settle(0.8)
        snap("ui-94-35-games-menu")
        if menu {
            let open = tap(ball, expecting: el(app, "catch.screen"), timeout: 6, name: "ui-94-36-catch-open")
            settle(1.5)
            snap("ui-94-36-catch-open")
            XCTAssertTrue(open, "«Лови мячик» не открылся")
            if open { back(app, sheet: "catch.screen", close: "catch.close", name: "ui-94-37-catch-back") }
        }
        app.terminate()
    }

    // MARK: 4. «Гулять» и настройки

    @MainActor
    func testJourney4WalkSettings() {
        let app = launch()
        waitHome(app)
        tapAct(app, "act.walk", name: "ui-94-40-walk-tap")
        settle(3)
        snap("ui-94-41-walk-later")

        let gear = el(app, "open.settings")
        guard gear.waitForExistence(timeout: 5) else {
            XCTFail("нет шестерёнки")
            app.terminate()
            return
        }
        tap(gear, expecting: el(app, "settings.habits"), timeout: 6, name: "ui-94-42-settings")
        settle(1)
        snap("ui-94-42-settings")
        let intro = el(app, "settings.intro")
        for _ in 0..<6 where !(intro.exists && intro.isHittable) {
            app.swipeUp()
            settle(0.6)
        }
        snap("ui-94-43-settings-hints")
        XCTAssertTrue(intro.exists, "в настройках нет «Подсказки»")
        let rules = el(app, "settings.rules")
        if rules.exists && waitHittable(rules, timeout: 2) {
            let ok = app.buttons["rules.ok"]
            let shown = tap(rules, expecting: ok, name: "ui-94-44-rules")
            settle(1)
            snap("ui-94-44-rules")
            if shown, tapWhenReady(ok) {
                settle(1)
                snap("ui-94-45-rules-closed")
            }
        }
        let close = app.buttons["Закрыть"].firstMatch
        if close.waitForExistence(timeout: 3), tapWhenReady(close) {
            settle(1.5)
            snap("ui-94-46-settings-closed")
        } else {
            snap("ui-94-46-no-close")
            XCTFail("в настройках нет «Закрыть»")
        }
        app.terminate()
    }
}
