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
//                   тёмная тема, автомат, вкусы в альбоме, открытка дня, дом, трюки. Состояние задаёт окружение запуска
//                   (PET_SEED, PET_AWAY_H, PET_OPEN, PET_SCHEME).
//   ui-5N-room-*    дом в комнате: все линии на максимуме, уровни 1–2 вперемешку, максимум в тёмной теме
//   ui-50/54/55     трюки: лист, ряд с лапой, тост после «Сидеть»
//   ui-56           покупка лежанки в «Доме» видна в комнате — HouseUITests
//   ui-57/58        мини-игра «Лови мячик»: раунд в разгаре, итог с наградой (PET_CATCH, сид 7)
//   ui-59/60        расчесать: полоса на 50% с колтунами на спине, дочесали (отряхнулся, тост)
//   ui-61/62        надето: Шиба в шапочке-листике, шарфе и плаще; коллекция с «Надеть/Снять», замена бантиком
//   ui-63/64        свет комнаты: вечер 20:30 в светлой теме (лампа, закатное окно), ночь 02:00 в тёмной (пёс спит, луна)
//   ui-65/66        открытка дня: с кадром 3D-сцены (снял сам PostcardCamera), в последний день перед пропажей
//   ui-69/70        сон хозяина: настройки с выученным окном «Я сплю примерно 00:40–08:10» (и экран «Я сплю»),
//                   «Доброе утро» при первом заходе утром (PET_SEED=sleep_learned / good_morning)
//   ui-73/74        характер и память (PET_SEED=memories): «Характер» и «Помню» в альбоме; пузырь-воспоминание на главной
//   ui-67           предметы: коллекция с иконками и кнопками по роли; комната с кубком на полке и теннисным мячиком
//   ui-68           лавка дня: три карточки за монеты, потом одна куплена
//   ui-71/72        шерсть текстурой крупным планом (PET_CAMERA=close): лохматая с клочками на спине, она же расчёсанная — гладкая
//   ui-75           привычки для «Команд»: утро и вода отмечены сегодня, зарядка вчера; -howto — шаги автоматизации
//   ui-76-brush-N   дочесали: серия из 4 кадров через 0,5 с — встряхнулся, подпрыгнул, виляет; новая фраза в тосте
//   ui-79/80        «Блок Дуо» (волна 12, PET_SEED=blockduo, PET_BLOCKDUO, сид 7): ui-79-games-menu — меню «Мини-игры»,
//                   ui-79-blockduo-play — партия на 10-м ходу, фигура над местом с подсветкой; ui-80-blockduo-done — итог
//                   с монетами, ui-80-blockduo-room — после «Готово» Шиба в комнате радуется и говорит
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

    /// Открытка с кадром 3D-сцены: после старта приложение само снимает сцену (PET_SEED=postcard_photo)
    /// и вешает кадр на вчерашнюю открытку. Значение чипа «photo:<способ>» — ar / metal / window, а если
    /// настоящий снимок на симуляторе не вышел — fallback (мордочка); способ печатается в лог прогона.
    @MainActor
    func testStates65PostcardPhoto() throws {
        let env = ["PET_SEED": "postcard_photo", "PET_NOW": Self.noon, "PET_SCHEME": "light"]
        let app = try shootOptional("ui-65-postcard-photo-main", env: env, marker: "postcard.card", keepRunning: true)
        let chip = app.descendants(matching: .any)["postcard.card"]
        let hasPhoto = NSPredicate(format: "value BEGINSWITH %@", "photo:")
        let shot = XCTNSPredicateExpectation(predicate: hasPhoto, object: chip)
        let got = XCTWaiter().wait(for: [shot], timeout: 30) == .completed
        print("ui-65: источник кадра = \((chip.value as? String) ?? "нет")")
        chip.tap()
        if app.descendants(matching: .any)["postcard.sheet"].waitForExistence(timeout: 10) {
            settle(1.5)
            snap("ui-65-postcard-photo")
        }
        app.terminate()
        XCTAssertTrue(got, "ui-65: у открытки так и не появился кадр")
    }

    /// Открытке неделя, не сохранена: сегодня последний день. Чип «· последний день», в листе — мягкое напоминание.
    @MainActor
    func testStates66PostcardExpiring() throws {
        let env = ["PET_SEED": "postcard_expiring", "PET_NOW": Self.noon, "PET_SCHEME": "light"]
        let app = try shootOptional("ui-66-postcard-expiring-main", env: env, marker: "postcard.card", keepRunning: true)
        app.descendants(matching: .any)["postcard.card"].tap()
        let note = app.descendants(matching: .any)["postcard.expiry"]
        if app.descendants(matching: .any)["postcard.sheet"].waitForExistence(timeout: 10) {
            settle(1.5)
            snap("ui-66-postcard-expiring")
        }
        XCTAssertTrue(note.exists && note.label.contains("последний день"), "ui-66: нет напоминания о последнем дне")
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

    /// Вечер (20:30, светлая тема): тёплый свет, приглушённые стены, лампа, персиковое небо в окне.
    @MainActor
    func testStates63RoomEvening() {
        shootState("ui-63-room-evening", env: ["PET_SEED": "room_mid", "PET_NOW": Self.today(20, 30), "PET_SCHEME": "light"],
                   marker: Self.mainMarker, settleFor: 2.5)
    }

    /// Ночь (02:00, тёмная тема): синий полумрак, ночник, луна и звёзды в окне; Шиба спит на лежанке.
    @MainActor
    func testStates64RoomNightDark() {
        shootState("ui-64-room-night-dark", env: ["PET_SEED": "room_max", "PET_NOW": Self.today(2, 0), "PET_SCHEME": "dark"],
                   marker: Self.mainMarker, settleFor: 2.5)
    }

    /// Лист «Трюки» (светлая тема, полдень — иначе ночью трюки серые): «Сидеть» выучен, «Лежать» 3 из 5, дальше замки.
    /// ui-54/55 — после команды «Сидеть» (PET_TRICK_ROLL=0 — всегда выходит): лист уехал, тост, ряд кнопок с лапой.
    @MainActor
    func testStates50Tricks() throws {
        let env = ["PET_SEED": "tricks", "PET_NOW": Self.noon, "PET_SCHEME": "light"]
        try shootOptional("ui-50-tricks", env: env.merging(["PET_OPEN": "tricks"]) { $1 }, marker: "tricks.screen")

        let app = try shootOptional("ui-54-tricks-main", env: env.merging(["PET_TRICK_ROLL": "0"]) { $1 },
                                    marker: "open.tricks", keepRunning: true)
        app.descendants(matching: .any)["open.tricks"].tap()
        let sit = app.descendants(matching: .any)["trick.sit"]
        guard sit.waitForExistence(timeout: 5) else {
            app.terminate()
            throw XCTSkip("нет trick.sit")
        }
        sit.tap()
        settle(1.2)
        snap("ui-55-tricks-done")
        app.terminate()
    }

    /// Мини-игра «Лови мячик» (полдень, светлая тема, сид раунда 7 — снимки одинаковые на каждом прогоне):
    /// ui-57 — раунд замер на 12-й секунде (PET_CATCH=play), ui-58 — раунд сыгран автопилотом, карточка итога с наградой.
    @MainActor
    func testStates57Catch() throws {
        let env = ["PET_NOW": Self.noon, "PET_SCHEME": "light", "PET_OPEN": "catch"]
        try shootOptional("ui-57-catch-play", env: env.merging(["PET_CATCH": "play"]) { $1 }, marker: "catch.field")
        try shootOptional("ui-58-catch-done", env: env.merging(["PET_CATCH": "done"]) { $1 }, marker: "catch.result")
    }

    /// Расчесать: щенок со свалявшейся шерстью (PET_SEED=brush), сеанс открыт сразу (PET_OPEN=brush) с уже засчитанными
    /// мазками (PET_BRUSH_STROKES), ещё один — настоящим жестом слева направо по спине.
    @MainActor
    func testStates59Brush() throws {
        try brushShot("ui-59-brush", strokes: 3, expect: "Расчёсано 50%", settleFor: 1.0)
    }

    @MainActor
    func testStates60BrushDone() throws {
        try brushShot("ui-60-brush-done", strokes: 7, expect: "Готово", settleFor: 2.2)
    }

    /// Привычки (PET_SEED=habits): лист по pet://habits, отметки «Сегодня ✓», «Сегодня 3 из 8», «Было 1 раз».
    @MainActor
    func testStates75Habits() throws {
        try shootOptional("ui-75-habits", env: ["PET_SEED": "habits", "PET_NOW": Self.noon, "PET_SCHEME": "light",
                                                "PET_OPEN": "habits"],
                          marker: "habits.screen")
        // Низ листа: шаги «Автоматизации» и кнопка «Открыть «Команды»».
        try shootOptional("ui-75-habits-howto", env: ["PET_SEED": "habits", "PET_NOW": Self.noon, "PET_SCHEME": "light",
                                                      "PET_OPEN": "habits"],
                          marker: "habits.openShortcuts", lazyIn: "habits.screen")
    }

    /// Конец расчёсывания (волна 11): тот же сеанс, что ui-60, но снимок раньше — посреди встряхивания и прыжка.
    @MainActor
    func testStates76BrushFinale() throws {
        // Серия с одного запуска: момент, когда видна поза, зависит от скорости симулятора.
        try brushShot("ui-76-brush-1", strokes: 7, expect: "Готово", settleFor: 0.3,
                      then: [("ui-76-brush-2", 0.5), ("ui-76-brush-3", 0.5), ("ui-76-brush-4", 0.5)])
    }

    // MARK: волна 12 — «Блок Дуо» (ui-79, ui-80)

    /// Меню кнопки «Мини-игры» на главной: «Лови мячик» и «Блок Дуо».
    @MainActor
    func testStates79GamesMenu() throws {
        let app = try shootOptional("ui-79-games-main", env: ["PET_SEED": "blockduo", "PET_NOW": Self.noon,
                                                              "PET_SCHEME": "light"],
                                    marker: "open.games", keepRunning: true)
        app.descendants(matching: .any)["open.games"].firstMatch.tap()
        let item = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Блок Дуо")).firstMatch
        _ = item.waitForExistence(timeout: 5)
        settle(0.8)
        snap("ui-79-games-menu")
        app.terminate()
    }

    /// Партия на 10-м ходу (автопилот, сид 7): фигура висит над своим местом, линии, которые исчезнут, подсвечены,
    /// клетки Шибы рыжие с лапкой.
    @MainActor
    func testStates79BlockDuo() throws {
        try shootOptional("ui-79-blockduo-play", env: Self.blockDuoEnv.merging(["PET_BLOCKDUO": "play"]) { $1 },
                          marker: "blockduo.board")
    }

    /// Итог: партия сыграна автопилотом до конца — счёт, «Ты · Шиба», монеты. «Готово» — и Шиба радуется в комнате.
    @MainActor
    func testStates80BlockDuoDone() throws {
        let app = try shootOptional("ui-80-blockduo-done", env: Self.blockDuoEnv.merging(["PET_BLOCKDUO": "done"]) { $1 },
                                    marker: "blockduo.result", keepRunning: true)
        let done = app.descendants(matching: .any)["blockduo.done"].firstMatch
        if done.waitForExistence(timeout: 5) {
            done.tap()
            // Экран уезжает, через 0,6 с Шиба подпрыгивает и говорит.
            settle(1.3)
            snap("ui-80-blockduo-room")
        }
        app.terminate()
    }

    static var blockDuoEnv: [String: String] { ["PET_SEED": "blockduo", "PET_NOW": Self.noon, "PET_SCHEME": "light", "PET_OPEN": "blockduo"] }

    /// Надето (PET_SEED=wear): шапочка-листик, вязаный шарф и плащ чемпиона на Шибе посреди дня.
    @MainActor
    func testStates61Wear() {
        shootState("ui-61-wear", env: ["PET_SEED": "wear", "PET_NOW": Self.noon, "PET_SCHEME": "light"],
                   marker: Self.mainMarker, settleFor: 2.5)
    }

    /// Коллекция в автомате: у надетого «Снять» и подпись «надето», у остального «Надеть», у миски кнопки нет.
    /// Потом «Надеть» бантик — шапочка снимается сама, тост «вместо».
    @MainActor
    func testStates62WearList() throws {
        let app = try shootOptional("ui-62-wear-list",
                                    env: ["PET_SEED": "wear", "PET_NOW": Self.noon, "PET_SCHEME": "light",
                                          "PET_OPEN": "capsule"],
                                    marker: "wear.leaf_hat", scrollIn: "capsule.screen", keepRunning: true)
        let bow = app.descendants(matching: .any)["wear.bow_blue"]
        if bow.waitForExistence(timeout: 5) {
            bow.tap()
            let toast = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "вместо"))
            _ = toast.firstMatch.waitForExistence(timeout: 5)
            settle(0.6)
            snap("ui-62-wear-list-swap")
        }
        app.terminate()
    }

    /// Сон хозяина выучен (PET_SEED=sleep_learned): в настройках «Я сплю примерно 00:40–08:10 (учится сам)»
    /// и «Ложиться вместе со мной». Потом экран «Я сплю» — пикеры «Засыпаю/Просыпаюсь» и «Забыть выученное».
    @MainActor
    func testStates69OwnerSleep() throws {
        let app = try shootOptional("ui-69-owner-sleep",
                                    env: ["PET_SEED": "sleep_learned", "PET_NOW": Self.noon, "PET_SCHEME": "light",
                                          "PET_OPEN": "settings"],
                                    marker: "settings.ownerSleep", keepRunning: true)
        let row = app.descendants(matching: .any)["settings.ownerSleep"]
        if row.isHittable {
            row.tap()
            if app.descendants(matching: .any)["ownerSleep.now"].waitForExistence(timeout: 5) {
                settle(1)
                snap("ui-69-owner-sleep-edit")
            }
        }
        app.terminate()
    }

    /// Первый заход утром после ночи (PET_SEED=good_morning, 08:20): Шиба говорит «Доброе утро…» один раз.
    @MainActor
    func testStates70GoodMorning() throws {
        let app = Self.makeApp()
        let env = ["PET_SEED": "good_morning", "PET_NOW": Self.today(8, 20), "PET_SCHEME": "light"]
        for (k, v) in env { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        let line = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Доброе утро"))
        let found = line.firstMatch.waitForExistence(timeout: 20)
        settle(2.0)
        snap("ui-70-good-morning")
        app.terminate()
        XCTAssertTrue(found, "ui-70: нет «Доброе утро»")
    }

    /// Альбом (PET_SEED=memories): «Характер» — три оси, игривый подсвечен; дальше «Помню» — воспоминания с датами.
    @MainActor
    func testStates73Character() throws {
        let app = try shootOptional("ui-73-character",
                                    env: ["PET_SEED": "memories", "PET_NOW": Self.noon, "PET_SCHEME": "light",
                                          "PET_OPEN": "album"],
                                    marker: "album.trait.tidiness", scrollIn: "album.sheet", keepRunning: true)
        let box = app.descendants(matching: .any)["album.sheet"]
        let met = app.descendants(matching: .any)["album.memory.met"]
        if met.waitForExistence(timeout: 5) {
            for _ in 0..<5 where !met.isHittable {
                box.swipeUp()
                settle(0.5)
            }
            settle(1)
            snap("ui-73-memories")
        }
        app.terminate()
    }

    /// Главная в полдень (PET_SEED=memories): в пузыре — воспоминание («Помнишь…»), а не обычная строка.
    @MainActor
    func testStates74MemoryLine() {
        shootState("ui-74-memory-line", env: ["PET_SEED": "memories", "PET_NOW": Self.noon, "PET_SCHEME": "light"],
                   marker: "pet.line", settleFor: 2.5)
    }

    /// Предметы (PET_SEED=items): сначала комната — кубок на полке, теннисный мячик, корона с бабочкой на собаке;
    /// потом коллекция в автомате — иконки на плитках редкости, «Надеть / На полку / Играть».
    @MainActor
    func testStates67Items() throws {
        shootState("ui-67-items-room", env: ["PET_SEED": "items", "PET_NOW": Self.noon, "PET_SCHEME": "light"],
                   marker: Self.mainMarker, settleFor: 2.5)
        try shootOptional("ui-67-items-list",
                          env: ["PET_SEED": "items", "PET_NOW": Self.noon, "PET_SCHEME": "light", "PET_OPEN": "capsule"],
                          marker: "shelf.trophy_cup", scrollIn: "capsule.screen")
    }

    /// Лавка дня (PET_OPEN=shop открывает автомат, а из него лист): три карточки, потом покупка первой — «Куплено».
    @MainActor
    func testStates68Shop() throws {
        let app = try shootOptional("ui-68-shop",
                                    env: ["PET_SEED": "items", "PET_NOW": Self.noon, "PET_SCHEME": "light",
                                          "PET_OPEN": "shop"],
                                    marker: "shop.screen", keepRunning: true)
        let buy = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "shop.buy.")).firstMatch
        if buy.waitForExistence(timeout: 5) {
            buy.tap()
            let sold = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Куплено"))
            XCTAssertTrue(sold.firstMatch.waitForExistence(timeout: 5), "ui-68: после покупки нет «Куплено»")
            settle(0.8)
            snap("ui-68-shop-bought")
        }
        app.terminate()
    }

    /// Шерсть крупным планом (PET_CAMERA=close, полдень): лохматая — штрихи гуще, тёмные пятна, клочки на спине
    /// (PET_SEED=fur_shaggy). Сравнивать с ui-59/60.
    @MainActor
    func testStates71FurShaggy() {
        shootState("ui-71-fur-shaggy", env: ["PET_SEED": "fur_shaggy", "PET_NOW": Self.noon, "PET_SCHEME": "light",
                                             "PET_CAMERA": "close"], marker: Self.mainMarker, settleFor: 2.5)
    }

    /// Тот же щенок после расчёсывания (PET_SEED=fur_brushed): гладкая шерсть, штрихи редкие и светлые, клочков нет.
    @MainActor
    func testStates72FurSleek() {
        shootState("ui-72-fur-sleek", env: ["PET_SEED": "fur_brushed", "PET_NOW": Self.noon, "PET_SCHEME": "light",
                                            "PET_CAMERA": "close"], marker: Self.mainMarker, settleFor: 2.5)
    }

    /// expect — подпись элемента после мазка (жест засчитан).
    @MainActor
    private func brushShot(_ name: String, strokes: Int, expect: String, settleFor: TimeInterval,
                           then more: [(String, TimeInterval)] = []) throws {
        let app = Self.makeApp()
        let env = ["PET_SEED": "brush", "PET_NOW": Self.noon, "PET_SCHEME": "light", "PET_OPEN": "brush",
                   "PET_BRUSH_STROKES": String(strokes)]
        for (k, v) in env { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        let pad = app.descendants(matching: .any)["brush.pad"]
        guard pad.waitForExistence(timeout: 20) else {
            snap(name)
            app.terminate()
            throw XCTSkip("\(name): нет brush.pad")
        }
        settle(1.2)
        // Голова Шибы слева: по шерсти — слева направо, по середине сцены.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.5))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.74, dy: 0.52))
        from.press(forDuration: 0.05, thenDragTo: to)
        let label = NSPredicate(format: "label CONTAINS %@", expect)
        let found = app.descendants(matching: .any).matching(label).firstMatch.waitForExistence(timeout: 5)
        settle(settleFor)
        snap(name)
        for (n, pause) in more {
            settle(pause)
            snap(n)
        }
        app.terminate()
        if !found { throw XCTSkip("\(name): нет «\(expect)» после мазка") }
    }

    /// Полдень по часам симулятора (PET_NOW): днём пёс не спит.
    static var noon: String { today(12, 0) }

    /// Сегодня в hh:mm по часам симулятора (PET_NOW, unix-секунды).
    static func today(_ hour: Int, _ minute: Int) -> String {
        let t = Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(hour * 3600 + minute * 60))
        return String(Int(t.timeIntervalSince1970))
    }

    /// Как shootState, но без маркера — XCTSkip (экран ещё не в этой сборке). Снимок делается в любом случае.
    /// scrollIn — контейнер, который листаем вверх, пока маркер не станет видимым.
    /// lazyIn — ленивый экран (Form): ждём его, листаем всё приложение, пока маркер не появится.
    @MainActor
    @discardableResult
    func shootOptional(_ name: String, env: [String: String], marker: String, scrollIn: String? = nil,
                       lazyIn: String? = nil, keepRunning: Bool = false) throws -> XCUIApplication {
        let app = Self.makeApp()
        for (k, v) in env { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        let element = app.descendants(matching: .any)[marker]
        var found: Bool
        if let lazyIn {
            // Нижние строки Form создаются лениво: маркера может не быть, пока не прокрутишь.
            _ = app.descendants(matching: .any)[lazyIn].firstMatch.waitForExistence(timeout: 20)
            settle(1.0)
            for _ in 0..<5 where !(element.exists && element.isHittable) {
                app.swipeUp()
                settle(0.6)
            }
            found = element.exists
        } else {
            found = element.waitForExistence(timeout: 20)
        }
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

    /// Главный экран на месте (по mainMarker), плюс секунда сцене на первый кадр.
    /// Маркера нет (старая сборка) — просто подождать, как раньше.
    @MainActor
    func waitForMain(_ app: XCUIApplication) {
        if !app.descendants(matching: .any)[Self.mainMarker].waitForExistence(timeout: 15) {
            settle(2)
        }
        settle(1)
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

// Общие помощники снимков: ими пользуются и другие UI-тесты (HouseUITests).
extension XCTestCase {
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
}
