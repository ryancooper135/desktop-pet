// Волна 34 I: уровень пса и рост. Сиды LaunchSeed: level_puppy (ур. 4, щенок), level_up (ур. 3 ещё не показан —
// сцена нового уровня сама при запуске), level_adult (ур. 12, взрослый).
//   ui-34-level-header  шапка со значком «ур. 4» и полоской опыта
//   ui-34-level-sheet   лист «Уровень»: опыт, сегодня, рост, что откроется
//   ui-34-level-puppy   щенок в комнате: маленький, голова крупнее, уши висят
//   ui-34-level-up      сцена нового уровня: «★3» и тост «Уровень 3! +… 🪙»
//   ui-34-level-adult   взрослый пёс в полный рост
// Волна 39 C, сид level_achieve (ур. 12, взрослый, достижения за уровень и рост только что получены):
//   ui-39-achieve-toast  тост «Достижения: 5 новых · +… ✂️» при запуске (если успели поймать)
//   ui-39-achieve-entry  лист «Уровень» с карточкой «Достижения · 5 из …»
//   ui-39-achieve-sheet  лист «Достижения»: сводка, полученные с датой, неполученные с прогрессом
// Волна 42 J, сид tasks (ур. 7 — три задания дня; задания в UI-тестах включены только сидами tasks*):
//   ui-42-tasks-entry  лист «Уровень» с карточкой «Задания дня · 0 из 3»
//   ui-42-tasks-sheet  лист «Задания дня»: три задания с прогрессом и наградой, награда за все (✂️)
// Волна 43 K, сид asks (ур. 7, пёс просит «Почеши за ушком?»; просьбы в UI-тестах включены только сидами asks*):
//   ui-43-ask-plate  плашка просьбы под мыслью: «🤲 Почеши за ушком? · ещё 59 мин»
//   ui-43-ask-hint   тост-подсказка по нажатию: «Нажми «Погладить» — +… 🪙»

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
        // Волна 45 P: тост живёт 2,5 с, а один запрос к дереву под 3D на CI — до десятков секунд, и
        // waitForExistence мог проспать оба тоста (прогон 40794999478, шард 3: «нет тоста нового уровня»). Как в ui-78:
        // годится сам тост или след «toast=…|» в значении pet.stage (последние 4 тоста, только в UI-тестах, волна 41 H).
        let toast = any.matching(identifier: "toast")
            .matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "Уровень 3", "Открылось")).firstMatch
        let stage = any["pet.stage"].firstMatch
        let shown = eventually(timeout: 60) {
            toast.exists || (valueNow(stage).map { $0.contains("toast=Уровень 3") || $0.contains("toast=Открылось") } ?? false)
        }
        XCTAssertTrue(shown, "нет тоста нового уровня (\(valueNow(stage) ?? "нет pet.stage"))")
        // Тост въезжает снизу с прозрачности (~0,35 с): без паузы снимок ловил пустое место.
        settle(0.6)
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

    @MainActor
    func testAchievementsSheet() throws {
        let app = launch("level_achieve")
        let any = app.descendants(matching: .any)

        // Тост живёт 2,5 с — пока закрывались системные окна, мог уйти: снимок, если поймали, без падения.
        let toast = any.matching(identifier: "toast")
            .matching(NSPredicate(format: "label CONTAINS %@", "Достижени")).firstMatch
        if toast.waitForExistence(timeout: 6) {
            settle(0.6)
            snap("ui-39-achieve-toast")
        }

        let chip = any["level.chip"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 15), "нет значка уровня в шапке")
        let level = any["level.sheet"].firstMatch
        XCTAssertTrue(open(chip, level, name: "ui-39-achieve-chip"), "лист «Уровень» не открылся")
        // Волна 45 P: каждое ожидание + чтение .label — отдельные запросы к дереву, а под нагрузкой CI каждый стоит
        // десятки секунд (прогон 40765117525: тест упёрся в 3 мин). Ждём и читаем одним снимком элемента.
        let entry = any["level.achievements"].firstMatch
        let entryNow = waitSnapshot(entry, timeout: 15) { $0.label.contains("Достижения") }
        XCTAssertTrue(entryNow.ok, "нет входа в достижения: \(entryNow.last?.label ?? "нет")")
        settle(1)
        snap("ui-39-achieve-entry")

        let sheet = any["achieve.sheet"].firstMatch
        XCTAssertTrue(open(entry, sheet, name: "ui-39-achieve-entry-tap"), "лист «Достижения» не открылся")
        let summary = waitSnapshot(any["achieve.summary"].firstMatch, timeout: 15) { $0.label.contains("Получено") }
        let summaryText = summary.last?.label ?? "нет сводки"
        XCTAssertTrue(summary.ok, "сводка: \(summaryText)")
        XCTAssertFalse(summaryText.contains("Получено 0 "), "ничего не получено: \(summaryText)")
        let got = waitSnapshot(any["achieve.level_10"].firstMatch, timeout: 15) { $0.label.contains("Получено") }
        XCTAssertTrue(got.ok, "ур. 10 не получен: \(got.last?.label ?? "нет карточки «Ур. 10»")")
        let todo = waitSnapshot(any["achieve.challenge_10"].firstMatch, timeout: 5) { $0.label.contains("4 из 10") }
        XCTAssertTrue(todo.ok, "прогресс челленджей: \(todo.last?.label ?? "нет карточки «Десять челленджей»")")
        settle(1)
        snap("ui-39-achieve-sheet")

        XCTAssertTrue(tapWhenReady(any["achieve.close"].firstMatch), "нет кнопки закрытия")
        _ = sheet.waitForNonExistence(timeout: 5)
        XCTAssertFalse(sheet.exists, "лист «Достижения» не закрылся")
        XCTAssertTrue(level.exists, "лист «Уровень» под ним остался")
        app.terminate()
    }

    @MainActor
    func testDailyTasksSheet() throws {
        let app = launch("tasks")
        let any = app.descendants(matching: .any)

        let chip = any["level.chip"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 15), "нет значка уровня в шапке")
        let level = any["level.sheet"].firstMatch
        XCTAssertTrue(open(chip, level, name: "ui-42-tasks-chip"), "лист «Уровень» не открылся")
        let entry = any["level.tasks"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "нет карточки «Задания дня»")
        XCTAssertTrue(entry.label.contains("из 3"), "на ур. 7 три задания: \(entry.label)")
        settle(1)
        snap("ui-42-tasks-entry")

        let sheet = any["tasks.sheet"].firstMatch
        XCTAssertTrue(open(entry, sheet, name: "ui-42-tasks-entry-tap"), "лист «Задания дня» не открылся")
        let rows = any.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tasks.row."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "нет строк заданий")
        XCTAssertEqual(rows.count, 3, "заданий на ур. 7")
        XCTAssertTrue(rows.firstMatch.label.contains("награда"), "строка: \(rows.firstMatch.label)")
        XCTAssertTrue(any["tasks.all"].firstMatch.exists, "нет награды за все задания")
        settle(1)
        snap("ui-42-tasks-sheet")

        XCTAssertTrue(tapWhenReady(any["tasks.close"].firstMatch), "нет кнопки закрытия")
        _ = sheet.waitForNonExistence(timeout: 5)
        XCTAssertFalse(sheet.exists, "лист «Задания дня» не закрылся")
        XCTAssertTrue(level.exists, "лист «Уровень» под ним остался")
        app.terminate()
    }

    @MainActor
    func testDogAsk() throws {
        let app = launch("asks")
        let any = app.descendants(matching: .any)

        let plate = any["pet.ask"].firstMatch
        XCTAssertTrue(plate.waitForExistence(timeout: 15), "нет плашки просьбы")
        XCTAssertTrue(plate.label.contains("Почеши за ушком"), "плашка: \(plate.label)")
        XCTAssertTrue(plate.label.contains("ещё"), "плашка без остатка времени: \(plate.label)")
        settle(1)
        snap("ui-43-ask-plate")

        // Тост живёт ~2,5 с; под нагрузкой CI первый тап мог уйти мимо — до трёх нажатий, подсказка безвредна.
        let hint = any.matching(identifier: "toast").matching(NSPredicate(format: "label CONTAINS %@", "Погладить")).firstMatch
        var shown = false
        for _ in 0..<3 where !shown {
            guard tapWhenReady(plate, timeout: 10) else { continue }
            shown = hint.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(shown, "нет подсказки по нажатию на просьбу")
        settle(0.6)
        snap("ui-43-ask-hint")
        XCTAssertTrue(plate.exists, "плашка пропала от подсказки")
        app.terminate()
    }

    /// Открыть лист кнопкой: до трёх нажатий, пока лист не появился. Под нагрузкой CI (шард 3, 3D двора рядом)
    /// первый тап мог уйти в кадр, когда приложение ещё раскладывало тост/шапку, а общий tap(_:expecting:) не
    /// повторяет, если кнопка в этот момент «не нажимаема». Повтор безопасен: кнопка только открывает лист,
    /// а открывшийся лист её перекрывает — следующего нажатия уже не будет.
    @MainActor
    private func open(_ button: XCUIElement, _ target: XCUIElement, name: String) -> Bool {
        for i in 0..<3 {
            if target.exists { return true }
            if i > 0 { snap("\(name)-retry\(i)") }
            guard tapWhenReady(button, timeout: 10) else { continue }
            if target.waitForExistence(timeout: 10) { return true }
        }
        return target.waitForExistence(timeout: 5)
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
