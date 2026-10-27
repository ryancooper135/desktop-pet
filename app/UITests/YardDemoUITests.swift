// Волна 33 F: двор в 3D (ui-98-yard-*). Превью «Двор 3D» из каталога (Настройки → Для разработки → Каталог превью),
// раздел виден под тестом только с PET_DEVTOOLS=1. К настоящему экрану двор ещё не подключён.
//
//   ui-98-yard-st-N       станция N (1–8) крупно, уровень 1 (доска), копилка полная
//   ui-98-yard-look-L     котелок на уровне L (1 доска, 3 металл, 5 медь с лампочками)
//   ui-98-yard-mill-night мельница ночью, медь: крылья быстрее, мука светится
//   ui-98-yard-tier-N     двор до яруса N, все плиты яруса куплены
//   ui-98-yard-tier-1-0   дворик без плит — стартовый пустырь (лужа, мешок, кривой забор)
//   ui-98-yard-tier-1-3   дворик на середине: мусор убран, забор починен, тропинка
//   ui-98-yard-fps        текст: кадров в секунду в превью станции
//   ui-36-district-D      двор до яруса 4 в районе D (street, winter, river, roof) — волна 36 Q
//   ui-36-move-van        сцена переезда: фургон, коробки, Шиба в кабине (Улица → Зимний квартал)
//
// Бюджет §2: у каждой станции и у худшей по всем видам не больше 400 треугольников (подписи yard.tris, yard.maxTris).

import XCTest

final class YardDemoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// Восемь станций, три вида по уровню, мельница ночью, бюджет треугольников и fps.
    @MainActor
    func testYard1Stations() throws {
        let app = try openDemo()
        let budget = 400
        let worst = number(app, "yard.maxTris")
        XCTAssertNotNil(worst, "нет подписи худшей станции")
        if let worst { XCTAssertLessThanOrEqual(worst, budget, "худшая станция тяжелее бюджета §2") }
        for s in 1...8 {
            tapWhenReady(el(app, "yard.st.\(s)"))
            settle(1.6)
            snap("ui-98-yard-st-\(s)")
            let tris = number(app, "yard.tris")
            XCTAssertNotNil(tris, "станция \(s): нет подписи треугольников")
            if let tris { XCTAssertLessThanOrEqual(tris, budget, "станция \(s): \(tris) треугольников") }
        }
        // Секунда-другая на счётчик кадров (окно — 1 с), потом показание.
        settle(1.5)
        let fps = number(app, "yard.fps") ?? 0
        let note = XCTAttachment(string: "fps \(fps) (симулятор CI, станция 8)")
        note.name = "ui-98-yard-fps"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertGreaterThan(fps, 0, "превью двора не рисует кадры")

        tapWhenReady(el(app, "yard.st.3"))
        for l in [1, 3, 5] {
            tapWhenReady(el(app, "yard.lv.\(l)"))
            settle(1.2)
            snap("ui-98-yard-look-\(l)")
        }
        tapWhenReady(el(app, "yard.st.8"))
        tapWhenReady(el(app, "yard.night"))
        settle(1.6)
        snap("ui-98-yard-mill-night")
        app.terminate()
    }

    /// Пять ярусов накопительно и стройка дворика по плитам.
    @MainActor
    func testYard2Tiers() throws {
        let app = try openDemo()
        tapWhenReady(el(app, "yard.lv.3"))
        for n in 0..<5 {
            tapWhenReady(el(app, "yard.tier.\(n)"))
            settle(1.6)
            snap("ui-98-yard-tier-\(n)")
        }
        tapWhenReady(el(app, "yard.tier.1"))
        let minus = el(app, "yard.plate.minus")
        for _ in 0..<6 { tapWhenReady(minus) }
        settle(1.2)
        snap("ui-98-yard-tier-1-0")
        let plus = el(app, "yard.plate.plus")
        for _ in 0..<3 { tapWhenReady(plus) }
        settle(1.2)
        snap("ui-98-yard-tier-1-3")
        app.terminate()
    }

    /// Волна 36 Q: четыре района двора на ярусе 4 (ui-36-district-*) и сцена переезда (ui-36-move-van).
    /// Бюджет декора района — 800 треугольников сверх слоёв (подпись yard.districtTris, второе число — худший).
    @MainActor
    func testYard3Districts() throws {
        let app = try openDemo()
        tapWhenReady(el(app, "yard.lv.3"))
        tapWhenReady(el(app, "yard.tier.4"))
        for d in ["street", "winter", "river", "roof"] {
            tapWhenReady(el(app, "yard.district.\(d)"))
            settle(1.8)
            snap("ui-36-district-\(d)")
        }
        // Ярус 4 с декором на симуляторе CI — 2–3 кадра/с, снимок дерева элементов медленный: ждём с запасом.
        let label = el(app, "yard.districtTris")
        if label.waitForExistence(timeout: 15) {
            let nums = label.label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            XCTAssertEqual(nums.count, 2, "подпись декора: \(label.label)")
            if let worst = nums.last { XCTAssertLessThanOrEqual(worst, 800, "декор района тяжелее бюджета") }
        } else {
            XCTFail("нет подписи декора района")
        }
        // Переезд с улицы в зимний квартал: фургон, подпись, Шиба в кабине.
        tapWhenReady(el(app, "yard.district.street"))
        let caption = el(app, "yard.move.caption")
        XCTAssertTrue(tap(el(app, "yard.move"), expecting: caption, timeout: 15, name: "ui-36-move-open"),
                      "сцена переезда не открылась")
        XCTAssertEqual(caption.label, "Переезжаем: Улица → Зимний квартал")
        XCTAssertTrue(el(app, "yard.move.scene").waitForExistence(timeout: 10), "нет сцены фургона")
        settle(4)
        snap("ui-36-move-van")
        tapWhenReady(el(app, "yard.move.close"))
        app.terminate()
    }

    // MARK: - Помощники

    @MainActor
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// Первое число в подписи («треугольников 268 из 400» → 268).
    @MainActor
    private func number(_ app: XCUIApplication, _ id: String) -> Int? {
        let e = el(app, id)
        guard e.waitForExistence(timeout: 5) else { return nil }
        let digits = e.label.split(whereSeparator: { !$0.isNumber }).first
        return digits.flatMap { Int($0) }
    }

    /// Настройки по PET_OPEN → вниз до «Каталог превью» → «Двор 3D».
    @MainActor
    private func openDemo() throws -> XCUIApplication {
        let app = ScreenshotUITests.makeApp()
        app.launchEnvironment["PET_OPEN"] = "settings"
        app.launchEnvironment["PET_DEVTOOLS"] = "1"
        app.launchEnvironment["PET_SCHEME"] = "light"
        app.launch()
        acceptSystemAlerts()
        // settings.habits в ленивом списке без прокрутки не виден — ждём сам запуск, раздел найдёт прокрутка ниже.
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        settle(1.5)
        let catalog = app.buttons["Каталог превью"]
        for _ in 0..<10 where !(catalog.exists && catalog.isHittable) {
            app.swipeUp()
            settle(0.5)
        }
        guard tapWhenReady(catalog, timeout: 3) else {
            snap("ui-98-yard-no-catalog")
            app.terminate()
            XCTFail("нет раздела «Для разработки» с PET_DEVTOOLS=1")
            throw XCTSkip("дальше без превью двора")
        }
        let demo = el(app, "yard.demo")
        XCTAssertTrue(tap(demo, expecting: el(app, "yard.st.1"), timeout: 8, name: "ui-98-yard-open"),
                      "превью двора не открылось")
        settle(1.5)
        return app
    }
}
