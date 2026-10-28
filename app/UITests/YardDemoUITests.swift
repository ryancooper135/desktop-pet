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
//   ui-37-district-D-night  тот же двор ночью: зима — окна и гирлянда, река — фонарь и блик, крыша — огни города
//                           и лампочка у будки; у станций акценты района (снег, весла/круг, антенна) — волна 37 B
//   ui-37-move-van-night  переезд ночью: фонарь у дороги, лучи фар, свет в кузове, ночное небо
//   ui-39-weather-rain    станция под дождём сразу после чипа (волна 39 D; 3D не ждём — что успело)
//
// Бюджет §2: у каждой станции и у худшей по всем видам не больше 400 треугольников (подписи yard.tris, yard.maxTris).

import XCTest

final class YardDemoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// Станции 1–4 и бюджет треугольников худшей. 27.10: весь круг станций с видами и мельницей с ночным светом
    /// волны 38 B упирался в 3 мин на тест (1–2 кадра/с на CI) — разбит на три теста.
    @MainActor
    func testYard1Stations() throws {
        // Волна 41 H: вместо пауз — ожидание «shot=…,frame=ready» у сцены; каждое — запрос к дереву при 3D (на CI
        // десятки секунд), поэтому запас 420 с вместо 180 по умолчанию.
        executionTimeAllowance = 420
        let app = try openDemo()
        let worst = number(app, "yard.maxTris")
        XCTAssertNotNil(worst, "нет подписи худшей станции")
        if let worst { XCTAssertLessThanOrEqual(worst, Self.budget, "худшая станция тяжелее бюджета §2") }
        shootStations(app, 1...4)
        app.terminate()
    }

    /// Станции 5–8 и fps.
    @MainActor
    func testYard1bStations() throws {
        executionTimeAllowance = 420
        let app = try openDemo()
        shootStations(app, 5...8)
        // Счётчик кадров считает окном в 1 с и перечитывается раз в секунду: опрашиваем, пока не покажет кадры
        // (вместо паузы 1,5 с; проверка та же — fps > 0).
        var fps = 0
        eventually(timeout: 30) {
            fps = number(app, "yard.fps", timeout: 5) ?? 0
            return fps > 0
        }
        let note = XCTAttachment(string: "fps \(fps) (симулятор CI, станция 8)")
        note.name = "ui-98-yard-fps"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertGreaterThan(fps, 0, "превью двора не рисует кадры")
        app.terminate()
    }

    /// Котелок на трёх уровнях и мельница ночью.
    @MainActor
    func testYard1cLooks() throws {
        let app = try openDemo()
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

    private static let budget = 400

    @MainActor
    private func shootStations(_ app: XCUIApplication, _ range: ClosedRange<Int>) {
        for s in range {
            // Чип нажался — в значении сцены «shot=st.N»; на CI тап иногда теряется — ещё одно нажатие.
            let shot = "shot=st.\(s),"
            // Вместо паузы 1,6 с — мир станции прожил несколько кадров (YardFrame).
            choose(app, "yard.st.\(s)", shows: shot, snap: "ui-98-yard-st-\(s)")
            snap("ui-98-yard-st-\(s)")
            let tris = number(app, "yard.tris")
            XCTAssertNotNil(tris, "станция \(s): нет подписи треугольников")
            if let tris { XCTAssertLessThanOrEqual(tris, Self.budget, "станция \(s): \(tris) треугольников") }
        }
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
        // Волна 41 H: четыре района в 3D и фургон — ожидания готовности вместо пауз, запас под них.
        executionTimeAllowance = 420
        let app = try openDemo()
        choose(app, "yard.lv.3", shows: "lv=3,")
        choose(app, "yard.tier.4", shows: "shot=tier.4,")
        for d in ["street", "winter", "river", "roof"] {
            choose(app, "yard.district.\(d)", shows: "district=\(d),", snap: "ui-36-district-\(d)")
            snap("ui-36-district-\(d)")
        }
        // Ярус 4 с декором на симуляторе CI — 2–3 кадра/с, снимок дерева элементов медленный: ждём с запасом.
        let label = el(app, "yard.districtTris")
        if waitExists(label, timeout: 60) {
            let nums = label.label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            XCTAssertEqual(nums.count, 2, "подпись декора: \(label.label)")
            if let worst = nums.last { XCTAssertLessThanOrEqual(worst, 800, "декор района тяжелее бюджета") }
        } else {
            XCTFail("нет подписи декора района")
        }
        // Переезд с улицы в зимний квартал: фургон, подпись, Шиба в кабине.
        choose(app, "yard.district.street", shows: "district=street,")
        let caption = el(app, "yard.move.caption")
        XCTAssertTrue(tap(el(app, "yard.move"), expecting: caption, timeout: 30, name: "ui-36-move-open"),
                      "сцена переезда не открылась")
        XCTAssertEqual(caption.label, "Переезжаем: Улица → Зимний квартал")
        let van = el(app, "yard.move.scene")
        XCTAssertTrue(waitExists(van, timeout: 60), "нет сцены фургона")
        // Вместо паузы 4 с — фургон уже нарисован (YardFrame).
        readyForSnap(van, has: "frame=ready", timeout: 90, name: "ui-36-move-van")
        snap("ui-36-move-van")
        tapWhenReady(el(app, "yard.move.close"))
        app.terminate()
    }

    /// Волна 37 B: те же районы ночью (ui-37-district-*-night) и переезд ночью (ui-37-move-van-night).
    @MainActor
    func testYard4DistrictsNight() throws {
        // Волна 41 H: как testYard3Districts — готовность вместо пауз.
        executionTimeAllowance = 420
        let app = try openDemo()
        choose(app, "yard.lv.3", shows: "lv=3,")
        choose(app, "yard.tier.4", shows: "shot=tier.4,")
        tapWhenReady(el(app, "yard.night"), timeout: 30)
        for d in ["winter", "river", "roof", "street"] {
            choose(app, "yard.district.\(d)", shows: "district=\(d),", snap: "ui-37-district-\(d)-night")
            snap("ui-37-district-\(d)-night")
        }
        // С улицы ночью — в зимний квартал.
        let caption = el(app, "yard.move.caption")
        XCTAssertTrue(tap(el(app, "yard.move"), expecting: caption, timeout: 30, name: "ui-37-move-open"),
                      "сцена переезда ночью не открылась")
        let van = el(app, "yard.move.scene")
        XCTAssertTrue(waitExists(van, timeout: 60), "нет сцены фургона")
        readyForSnap(van, has: "frame=ready", timeout: 90, name: "ui-37-move-van-night")
        snap("ui-37-move-van-night")
        tapWhenReady(el(app, "yard.move.close"))
        app.terminate()
    }

    /// Волна 39 D: чипы погоды в «Двор 3D» и ряд «Погода в комнате» в каталоге. Дешёвый: только чипы,
    /// сцену не ждём (снимок — что успело нарисоваться, для глаза).
    @MainActor
    func testYard5WeatherChips() throws {
        let app = try openDemo()
        for w in ["clear", "cloudy", "rain", "snow"] {
            XCTAssertTrue(el(app, "yard.weather.\(w)").waitForExistence(timeout: 5), "нет чипа погоды \(w)")
        }
        XCTAssertTrue(tapWhenReady(el(app, "yard.weather.rain")), "чип «дождь» не нажимается")
        settle(1)
        snap("ui-39-weather-rain")
        XCTAssertTrue(tapWhenReady(el(app, "yard.weather.clear")), "чип «ясно» не нажимается")
        // Назад в каталог: там ряд «Погода в комнате».
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for w in ["auto", "clear", "cloudy", "rain", "snow"] {
            XCTAssertTrue(el(app, "weather.pin.\(w)").waitForExistence(timeout: 5), "нет чипа «Погода в комнате» \(w)")
        }
        app.terminate()
    }

    // MARK: - Помощники

    /// Нажать чип превью и дождаться, что сцена его приняла: в значении yard.scene есть mark («shot=st.3,», «lv=3,»,
    /// «district=winter,»). Волна 41 H: на CI тап при 3D иногда теряется — не дождались за 30 с, жмём ещё раз;
    /// так и не принял — провал (раньше тест молча снимал не тот вид после паузы).
    /// snap — дальше будет снимок: тем же опросом ждём и «frame=ready» (мир нарисован, YardFrame). Один запрос к
    /// дереву на попытку: при 3D на CI каждый стоит десятки секунд, отдельные ожидания «выбор» и «кадр» удваивали
    /// время (первый прогон волны 41 H упёрся в 45 мин шарда). Кадр не дождались — не провал, заметка <snap>-not-ready.
    @MainActor
    private func choose(_ app: XCUIApplication, _ chip: String, shows mark: String, snap: String? = nil) {
        let scene = el(app, "yard.scene")
        var last: String?
        var accepted = false
        let wait = { (t: TimeInterval) -> Bool in
            self.eventually(timeout: t) {
                last = self.valueNow(scene)
                guard let v = last, v.contains(mark) else { return false }
                accepted = true
                return snap == nil || v.contains("frame=ready")
            }
        }
        tapWhenReady(el(app, chip), timeout: 30)
        var ready = wait(30)
        if !accepted {
            tapWhenReady(el(app, chip), timeout: 30)
            ready = wait(30)
        }
        XCTAssertTrue(accepted, "\(chip): сцена не приняла выбор (\(last ?? "нет сцены"))")
        guard let snap else { return }
        if accepted && !ready { ready = wait(30) }
        if !ready {
            let note = XCTAttachment(string: "\(snap): нет \(mark) frame=ready; value=\(last ?? "нет элемента")")
            note.name = "\(snap)-not-ready"
            note.lifetime = .keepAlways
            add(note)
        }
    }

    @MainActor
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// Первое число в подписи («треугольников 268 из 400» → 268). Волна 41 H: опросом со сроком и одним снимком
    /// элемента на попытку (подпись и число из одного состояния), а не waitForExistence на 5 с + отдельный label.
    @MainActor
    private func number(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 30) -> Int? {
        let e = el(app, id)
        var n: Int?
        eventually(timeout: timeout) {
            guard let s = try? e.snapshot() else { return false }
            n = s.label.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
            return n != nil
        }
        return n
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
