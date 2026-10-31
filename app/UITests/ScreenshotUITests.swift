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
//   ui-50/54/55     команды: лист, ряд с лапой, тост после «Сидеть»
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
//   ui-75           «Команды» ночью (тёмная тема): пёс спит, иконки серые с луной
//   ui-76-brush-N   дочесали: серия из 4 кадров через 0,5 с — встряхнулся, подпрыгнул, виляет; новая фраза в тосте
//   ui-77/78        кухня шефа (PET_SEED=kitchen): лист «Кухня» — рецепты и еда со скидкой (старая цена зачёркнута);
//                   после «Приготовить» Шиба ест рагу и говорит фразу; «Угостить» морковкой за 3 вместо 4
//   ui-79/80        «Блок Дуо» (волна 12, PET_SEED=blockduo, PET_BLOCKDUO, сид 7): ui-79-games-menu — меню «Мини-игры»,
//                   ui-79-blockduo-play — партия на 10-м ходу, фигура над местом с подсветкой; ui-80-blockduo-done — итог
//                   с монетами, ui-80-blockduo-room — после «Готово» Шиба в комнате радуется и говорит
//   ui-81/82        свои персонажи (PET_SEED=charpack): «Свой персонаж» — список, «Без стойки» с ошибкой красным;
//                   комната с «Серым Шибой» из папки (клипы переименованы, рост 0,8, серая шерсть)
//   ui-85           рот крупно (PET_CAMERA=face, волна 13): -face-idle — морда в покое, -face-talk-N — после «Блок Дуо»
//                   Шиба говорит реплику, челюсть Jaw открывается по гласным (-face-result — служебный кадр итога)
//   ui-86           свой персонаж в шапке (волна 14, PET_SEED=charpack): ui-86-char-header — главный экран, в шапке
//                   имя пака «Серый Шиба» и аватар-снимок морды; ui-86-char-header-card — плашка крупно
//   ui-87           главный экран на крупном шрифте (волна 15): ui-87-dynamic-type — Dynamic Type AccessibilityL
//                   (-UIPreferredContentSizeCategoryName); подписи кнопок и реплика не должны вылезать и рваться
//   ui-88           тап по питомцу крупно (волна 18, PET_CAMERA=face): ui-88-tap-before — покой, ui-88-tap-mid — через
//                   ~0,3 с после тапа слева (голова чуть набок, уши назад), ui-88-tap-after — снова покой
//   ui-88           подсказки (волна 18, PET_SEED=walk_blocked): ui-88-hint-plate — «Лапы чешутся», «Гулять» с замком,
//                   плашка «Сначала помыть → Гулять» и «Чистота 29, для прогулки нужно 30» (волна 32: с сытости 30 уже
//                   гуляем, замок держит чистота), цветные кнопки; ui-88-walk-locked — тап по «Гулять»: тоста-повтора
//                   нет, подсвечена «Помыть»
//   ui-89           обучение ласке (PET_SEED=wants_pet, PET_TIPS=1): палец по спине и «Проведи пальцем по Шибе»,
//                   плашка «Погладить», ручка «Шкалы» под панелью
//   ui-91           знакомство (волна 19, PET_GUIDE=intro): ui-91-intro-1..3 — три карточки («Знакомься», «Как ухаживать»,
//                   «Что где» с легендой ряда значков и монет); после «Понятно, поехали» знакомство закрывается
//   ui-92           пояснения (волна 19): ui-92-settings-hints — раздел «Подсказки» в настройках; -reopen — знакомство,
//                   открытое оттуда снова; ui-92-capsule-legend — строчка «🪙 монеты — … ✂️ клочки — …» в автомате
// Ждём элементы через waitForExistence; Thread.sleep остался только там, где ждать нечего (3D-сцена, SpringBoard).
//   ui-93           согласованность (волна 20, PET_SEED=walk_hungry): еды 20 — ui-93-hungry-plate: плашка «Покормить»
//                   «Голодный — …», строка статуса не «Проголодается», а «Совсем оголодает через…»; ui-93-hungry-walk-locked —
//                   тап по «Гулять»: тост «Для прогулки сначала покормить: сытость 20, нужно 30»
//   ui-94           первые 15 минут новичка (волна 21) — FirstMinutesUITests: знакомство, плашка, панель, шкалы,
//                   круги ряда, «Гулять», настройки → «Подсказки»; снимок на каждом шаге
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
            guard tab.exists, waitHittable(tab, timeout: 2) else { continue }
            tab.tap()
            settle(1)
            snap("ui-1\(i + 1)-tab-\(i + 1)")
        }

        // Экраны по идентификаторам: каждый с чистого запуска, чтобы не искать «назад».
        for screen in present {
            app.terminate()
            app.launch()
            let el = app.descendants(matching: .any)[screen.identifier]
            guard el.waitForExistence(timeout: 15), waitHittable(el) else { continue }
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

    /// Волна 52: «Пока тебя не было» с копилкой двора — карточка «Накопилось» и кнопка «Забрать всё».
    @MainActor
    func testStates52AwayStash() {
        shootState("ui-52-away-stash", env: ["PET_SEED": "away_yard"], marker: "away.collect")
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
        if tap(app.descendants(matching: .any)["postcard.card"], expecting: app.descendants(matching: .any)["postcard.sheet"],
               timeout: 10, name: "ui-48-postcard-sheet") {
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
        if tap(chip, expecting: app.descendants(matching: .any)["postcard.sheet"], timeout: 10, name: "ui-65-postcard-photo") {
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
        let note = app.descendants(matching: .any)["postcard.expiry"]
        if tap(app.descendants(matching: .any)["postcard.card"], expecting: app.descendants(matching: .any)["postcard.sheet"],
               timeout: 10, name: "ui-66-postcard-expiring") {
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
        shootState("ui-51-room-max", env: ["PET_SEED": "room_max", "PET_NOW": Self.today(12, 0)], marker: Self.mainMarker,
                   settleFor: 2.5)
    }

    /// Уровни 1–2 вперемешку: промежуточные вещи не налезают друг на друга.
    @MainActor
    func testStates52RoomMid() {
        shootState("ui-52-room-mid", env: ["PET_SEED": "room_mid", "PET_NOW": Self.today(12, 0)], marker: Self.mainMarker,
                   settleFor: 2.5)
    }

    /// Верхний уровень в тёмной теме: комната та же, проверяем, что интерфейс поверх читается.
    /// 51–53 — полдень (PET_NOW): без него ночью по часам раннера Шиба спит и на кнопках замки «спит».
    @MainActor
    func testStates53RoomMaxDark() {
        shootState("ui-53-room-max-dark", env: ["PET_SEED": "room_max", "PET_NOW": Self.today(12, 0), "PET_SCHEME": "dark"],
                   marker: Self.mainMarker, settleFor: 2.5)
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

    /// Лист «Команды» (светлая тема, полдень — иначе ночью команды серые): пёс 5-го уровня, «Сидеть», «Лапу», «Лежать»
    /// выучены, «Голос» 2 из 4, «Кружись» 1 из 4, дальше замки с уровнем.
    /// ui-54/55 — после команды «Сидеть» (PET_TRICK_ROLL=0 — всегда выходит): лист уехал, тост, ряд кнопок с лапой.
    @MainActor
    func testStates50Tricks() throws {
        let env = ["PET_SEED": "tricks", "PET_NOW": Self.noon, "PET_SCHEME": "light"]
        try shootOptional("ui-50-tricks", env: env.merging(["PET_OPEN": "tricks"]) { $1 }, marker: "tricks.screen")

        let app = try shootOptional("ui-54-tricks-main", env: env.merging(["PET_TRICK_ROLL": "0"]) { $1 },
                                    marker: "open.tricks", keepRunning: true)
        let sit = app.descendants(matching: .any)["trick.sit"]
        guard tap(app.descendants(matching: .any)["open.tricks"], expecting: sit, name: "ui-55-tricks-open") else {
            app.terminate()
            throw XCTSkip("нет trick.sit")
        }
        // Лист ещё едет: тап по кнопке в движении мог промахнуться.
        tapWhenReady(sit)
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

    /// «Команды» вместо «Привычек» (волна 57): тот же сид tricks ночью в тёмной теме — пёс спит, все иконки серые
    /// с луной (tricks.gate), лист всё равно открывается.
    @MainActor
    func testStates75TricksAsleep() throws {
        try shootOptional("ui-75-tricks-asleep", env: ["PET_SEED": "tricks", "PET_NOW": Self.today(2, 0),
                                                       "PET_SCHEME": "dark", "PET_OPEN": "tricks"],
                          marker: "tricks.gate")
    }

    /// Конец расчёсывания (волна 11): тот же сеанс, что ui-60, но снимок раньше — посреди встряхивания и прыжка.
    @MainActor
    func testStates76BrushFinale() throws {
        // Серия с одного запуска: момент, когда видна поза, зависит от скорости симулятора.
        try brushShot("ui-76-brush-1", strokes: 7, expect: "Готово", settleFor: 0.3,
                      then: [("ui-76-brush-2", 0.5), ("ui-76-brush-3", 0.5), ("ui-76-brush-4", 0.5)])
    }

    // MARK: волна 12: кухня шефа (ui-77/78)

    /// Лист «Кухня» (PET_OPEN=kitchen открывает «Дом», а из него лист): «Приготовить» с четырьмя блюдами
    /// (печенье просит банку желудей), ниже «Угостить» — цены со скидкой −10%, старая зачёркнута.
    @MainActor
    func testStates77Kitchen() throws {
        let env = ["PET_SEED": "kitchen", "PET_NOW": Self.noon, "PET_SCHEME": "light", "PET_OPEN": "kitchen"]
        try shootOptional("ui-77-kitchen", env: env, marker: "kitchen.screen")
        try shootOptional("ui-77-kitchen-food", env: env, marker: "kitchen.buy.carrot", scrollIn: "kitchen.screen")
    }

    /// «Приготовить» рагу: листы закрываются, Шиба ест (клипы кормёжки) и говорит фразу, тост с монетами дня.
    /// Потом отдельный запуск: «Угостить» морковкой — в тосте цена со скидкой.
    @MainActor
    func testStates78Cooked() throws {
        let env = ["PET_SEED": "kitchen", "PET_NOW": Self.noon, "PET_SCHEME": "light", "PET_OPEN": "kitchen"]
        let app = try shootOptional("ui-78-before", env: env, marker: "kitchen.cook.stew_home", keepRunning: true)
        let cook = app.descendants(matching: .any)["kitchen.cook.stew_home"]
        // Фраза в пузыре живёт 5 с, тост — 2,5 с, а касание на CI (комната в 3D) возвращается через десятки секунд:
        // пузырь успевал погаснуть до первой проверки (волна 41 H). Фразу подтверждает любое из двух: пузырь на экране
        // или след «said=…» в pet.stage (последняя реплика, держится до следующей) — как покупку в HouseUITests.
        let stage = app.descendants(matching: .any)["pet.stage"].firstMatch
        if tapWhenReady(cook) {
            let line = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "уплетает"))
            let said = eventually(timeout: 60) {
                line.firstMatch.exists || (valueNow(stage)?.contains("уплетает") ?? false)
            }
            snap("ui-78-cooked")
            XCTAssertTrue(said, "ui-78: после «Приготовить» нет фразы «Шиба уплетает…» (\(valueNow(stage) ?? "нет pet.stage"))")
            settle(1.5)
            snap("ui-78-cooked-2")
        }
        app.terminate()

        let shop = try shootOptional("ui-78-buy-before", env: env, marker: "kitchen.buy.carrot",
                                     scrollIn: "kitchen.screen", keepRunning: true)
        let buy = shop.descendants(matching: .any)["kitchen.buy.carrot"]
        let shopStage = shop.descendants(matching: .any)["pet.stage"].firstMatch
        if tapWhenReady(buy) {
            let toast = shop.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Угощение: "))
            // Тост — или след «toast=Угощение: …» в pet.stage (см. выше).
            let shown = eventually(timeout: 60) {
                toast.firstMatch.exists || (valueNow(shopStage)?.contains("toast=Угощение: ") ?? false)
            }
            snap("ui-78-bought")
            XCTAssertTrue(shown, "ui-78: после «Угостить» нет тоста с ценой (\(valueNow(shopStage) ?? "нет pet.stage"))")
        }
        shop.terminate()
    }

    // MARK: волна 12 — «Блок Дуо» (ui-79, ui-80)

    /// Меню кнопки «Мини-игры» на главной: «Лови мячик» и «Блок Дуо».
    @MainActor
    func testStates79GamesMenu() throws {
        let app = try shootOptional("ui-79-games-main", env: ["PET_SEED": "blockduo", "PET_NOW": Self.noon,
                                                              "PET_SCHEME": "light"],
                                    marker: "open.games", keepRunning: true)
        let item = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Блок Дуо")).firstMatch
        tap(app.descendants(matching: .any)["open.games"].firstMatch, expecting: item, name: "ui-79-games-menu")
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
        if tapWhenReady(done) {
            // Экран уезжает, через 0,6 с Шиба подпрыгивает и говорит.
            settle(1.3)
            snap("ui-80-blockduo-room")
        }
        app.terminate()
    }

    static var blockDuoEnv: [String: String] { ["PET_SEED": "blockduo", "PET_NOW": Self.noon, "PET_SCHEME": "light", "PET_OPEN": "blockduo"] }

    // MARK: - Волна 12: свои персонажи (ui-81/82)

    /// «Свой персонаж» (PET_SEED=charpack, pet://characters): Шиба, «Без стойки» с ошибкой про idle,
    /// «Серый Шиба» активен (галочка). -add — кнопка «Добавить из «Файлов»» и шпаргалка формата внизу.
    @MainActor
    func testStates81CharacterPacks() throws {
        let env = ["PET_SEED": "charpack", "PET_NOW": Self.noon, "PET_SCHEME": "light", "PET_OPEN": "characters"]
        let app = try shootOptional("ui-81-characters", env: env, marker: "characters.screen", keepRunning: true)
        let error = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "characters.error.")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5), "ui-81: у сломанного пака нет ошибки")
        let howTo = app.descendants(matching: .any)["characters.add"]
        for _ in 0..<4 where !(howTo.exists && howTo.isHittable) {
            app.swipeUp()
            settle(0.5)
        }
        app.swipeUp()
        settle(0.8)
        snap("ui-81-characters-add")
        app.terminate()
    }

    /// Комната со своим персонажем (PET_SEED=charpack): «Серый Шиба» — та же модель из папки, ниже ростом и серый.
    /// Не загрузился бы — была бы рыжая Шиба и тост «не загрузился».
    @MainActor
    func testStates82CharacterRoom() {
        shootState("ui-82-character-room", env: ["PET_SEED": "charpack", "PET_NOW": Self.noon, "PET_SCHEME": "light"],
                   marker: Self.mainMarker, settleFor: 2.5)
    }

    // MARK: - Волна 14: свой персонаж в шапке (ui-86)

    /// Шапка со своим персонажем (PET_SEED=charpack): имя пака «Серый Шиба» и круглый аватар — снимок морды
    /// модели (avatar.png в паке нет). Снимок снимается в фоне при первом показе — ждём «name.card.avatar».
    /// -card — сама плашка крупно.
    @MainActor
    func testStates86CharacterHeader() {
        let app = Self.makeApp()
        for (k, v) in ["PET_SEED": "charpack", "PET_NOW": Self.noon, "PET_SCHEME": "light"] { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        waitForMain(app)
        let card = app.descendants(matching: .any)["name.card.avatar"].firstMatch
        let found = card.waitForExistence(timeout: 20)
        settle(1.5)
        snap("ui-86-char-header")
        if found {
            let shot = XCTAttachment(screenshot: card.screenshot())
            shot.name = "ui-86-char-header-card"
            shot.lifetime = .keepAlways
            add(shot)
        }
        XCTAssertTrue(found, "ui-86: в шапке нет аватара своего персонажа")
        app.terminate()
    }

    // MARK: - Волна 15: крупный шрифт (ui-87)

    /// Главный экран при Dynamic Type AccessibilityL: реплика растёт (до 22 pt, три строки), подписи панели
    /// подгоняются под ширину ячейки, остальное — фиксированные кегли. Ничего не должно наезжать и рваться.
    @MainActor
    func testStates87DynamicType() {
        let app = Self.makeApp()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        for (k, v) in ["PET_NOW": Self.noon, "PET_SCHEME": "light"] { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        waitForMain(app)
        let line = app.descendants(matching: .any)["pet.line"].firstMatch
        let found = line.waitForExistence(timeout: 10)
        settle(1.5)
        snap("ui-87-dynamic-type")
        XCTAssertTrue(found, "ui-87: нет реплики на главном экране")
        app.terminate()
    }

    // MARK: - Волна 18: тап по питомцу (ui-88)

    /// Тап по сцене слева от центра (PET_CAMERA=face, полдень): -before — морда в покое, -mid — через ~0,3 с голова
    /// чуть склонилась влево (не больше 7°), уши отведены, взгляд на палец не дальше ~21°; -after — через 1,6 с снова покой.
    @MainActor
    func testStates88TapMid() throws {
        let app = Self.makeApp()
        for (k, v) in ["PET_NOW": Self.noon, "PET_SCHEME": "light", "PET_CAMERA": "face"] { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        waitForMain(app)
        let stage = app.descendants(matching: .any)["pet.stage"].firstMatch
        guard stage.waitForExistence(timeout: 10) else {
            snap("ui-88-tap-before")
            app.terminate()
            throw XCTSkip("ui-88: нет pet.stage")
        }
        settle(1)
        snap("ui-88-tap-before")
        stage.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45)).tap()
        settle(0.15)
        snap("ui-88-tap-mid")
        settle(1.4)
        snap("ui-88-tap-after")
        app.terminate()
    }

    // MARK: - Волна 50: живые глаза (ui-50-eyes-a/b)

    /// Морда крупно (PET_CAMERA=face, полдень): тёплая карая радужка и белый блик. A — один крупный блик
    /// B — два маленьких (по умолчанию). Вариант в приложении — одна константа EyeStyle.variant.
    @MainActor
    func testStates50EyesA() throws { try shootEyes("a") }

    @MainActor
    func testStates50EyesB() throws { try shootEyes("b") }

    @MainActor
    private func shootEyes(_ v: String) throws {
        let app = Self.makeApp()
        for (k, val) in ["PET_NOW": Self.noon, "PET_SCHEME": "light", "PET_CAMERA": "face", "PET_EYES": v] {
            app.launchEnvironment[k] = val
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        waitForMain(app)
        let stage = app.descendants(matching: .any)["pet.stage"].firstMatch
        let found = stage.waitForExistence(timeout: 10)
        settle(2)
        snap("ui-50-eyes-\(v)")
        app.terminate()
        if !found { throw XCTSkip("ui-50-eyes-\(v): нет pet.stage") }
    }

    // MARK: - Волна 18: подсказки и жесты (ui-88/89)

    /// Хочет гулять, а чистоты мало: плашка ведёт к ванне, на «Гулять» замок. Тап по «Гулять» — подсветка.
    @MainActor
    func testStates88HintPlate() {
        let app = Self.makeApp()
        for (k, v) in ["PET_SEED": "walk_blocked", "PET_NOW": Self.noon, "PET_SCHEME": "light"] { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        let plate = app.descendants(matching: .any)["hint.plate"].firstMatch
        let found = plate.waitForExistence(timeout: 20)
        settle(1.5)
        snap("ui-88-hint-plate")
        XCTAssertTrue(found, "ui-88: нет плашки hint.plate")
        let walk = app.descendants(matching: .any)["act.walk"].firstMatch
        if tapWhenReady(walk) {
            settle(0.6)
            snap("ui-88-walk-locked")
        }
        XCTAssertTrue(app.descendants(matching: .any)["open.needs"].exists, "ui-88: нет ручки «Шкалы»")
        app.terminate()
    }

    /// Просит ласки, новичок: палец ходит по спине, подпись «Проведи пальцем по Шибе».
    @MainActor
    func testStates89PetTutor() {
        shootState("ui-89-pet-tutor", env: ["PET_SEED": "wants_pet", "PET_TIPS": "1", "PET_NOW": Self.noon, "PET_SCHEME": "light"],
                   marker: "tip.pet", settleFor: 2)
    }

    // MARK: - Волна 25: свежий взгляд (ui-96)

    /// Лист шкал говорит о том же событии, что строка статуса («Затоскует…»), шапка — «Просит ласки».
    @MainActor
    func testStates96NeedsSameEvent() {
        let app = Self.makeApp()
        for (k, v) in ["PET_SEED": "wants_pet", "PET_OPEN": "needs", "PET_NOW": Self.noon, "PET_SCHEME": "light"] {
            app.launchEnvironment[k] = v
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        let next = app.descendants(matching: .any)["needs.next"].firstMatch
        let found = next.waitForExistence(timeout: 20)
        settle(1.5)
        snap("ui-96-needs-same-event")
        XCTAssertTrue(found, "ui-96: нет строки needs.next")
        if found { XCTAssertTrue(next.label.hasPrefix("Затоскует"), "ui-96: в листе «\(next.label)», а строка — «Затоскует…»") }
        app.terminate()
    }

    /// «Гулять» с замком: плашка «Сначала помыть» уже всё сказала — тоста-повтора нет, кнопка подсвечена.
    @MainActor
    func testStates96WalkLockedNoRepeat() {
        let app = Self.makeApp()
        for (k, v) in ["PET_SEED": "walk_blocked", "PET_NOW": Self.noon, "PET_SCHEME": "light"] { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        let plate = app.descendants(matching: .any)["hint.plate"].firstMatch
        XCTAssertTrue(plate.waitForExistence(timeout: 20), "ui-96: нет плашки hint.plate")
        settle(1.5)
        let walk = app.descendants(matching: .any)["act.walk"].firstMatch
        if tapWhenReady(walk) {
            settle(0.6)
            snap("ui-96-walk-locked")
            XCTAssertFalse(app.descendants(matching: .any)["toast"].exists, "ui-96: тост повторяет плашку")
        }
        app.terminate()
    }

    /// Ссылка pet://needs, пока открыт альбом: альбом закрывается, открываются шкалы (раньше — молча ничего).
    @MainActor
    func testStates96DeepLinkOverSheet() throws {
        let app = Self.makeApp()
        // PET_THEN: приложение само через 4 с зовёт model.open(pet://needs) поверх альбома — тот же путь, что ссылка
        // виджета. XCUIApplication.open на симуляторе ссылку до приложения не довёз (прогон 39382964447).
        for (k, v) in ["PET_OPEN": "album", "PET_THEN": "needs", "PET_NOW": Self.noon, "PET_SCHEME": "light"] {
            app.launchEnvironment[k] = v
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        settle(2.5)
        snap("ui-96-deeplink-before")
        let needs = app.descendants(matching: .any)["needs.sheet"].firstMatch
        let found = needs.waitForExistence(timeout: 15)
        settle(1)
        snap("ui-96-deeplink-needs")
        XCTAssertTrue(found, "ui-96: pet://needs поверх альбома не открыл шкалы")
        app.terminate()
    }

    // MARK: - Волна 20: согласованность подсказок (ui-93)

    /// Уже голодный и хочет гулять: плашка «Покормить», таймер беды «Совсем оголодает», тост замка с числами.
    @MainActor
    func testStates93HungryWalkLock() {
        let app = Self.makeApp()
        for (k, v) in ["PET_SEED": "walk_hungry", "PET_NOW": Self.noon, "PET_SCHEME": "light"] { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        let plate = app.descendants(matching: .any)["hint.plate"].firstMatch
        let found = plate.waitForExistence(timeout: 20)
        settle(1.5)
        snap("ui-93-hungry-plate")
        XCTAssertTrue(found, "ui-93: нет плашки hint.plate")
        let walk = app.descendants(matching: .any)["act.walk"].firstMatch
        if tapWhenReady(walk) {
            settle(0.6)
            snap("ui-93-hungry-walk-locked")
        }
        app.terminate()
    }

    // MARK: - Волна 19: понятность (ui-91/92)

    /// Знакомство при первом запуске (PET_GUIDE=intro): три карточки по «Дальше», потом «Понятно, поехали».
    /// В остальных UI-тестах знакомства нет: GuideCenter молчит, пока PET_GUIDE не задан.
    @MainActor
    func testStates91Intro() {
        let app = Self.makeApp()
        for (k, v) in ["PET_GUIDE": "intro", "PET_NOW": Self.noon, "PET_SCHEME": "light"] { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        let next = app.buttons["intro.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 20), "ui-91: знакомство не показалось")
        settle(1.2)
        snap("ui-91-intro-1")
        for k in 2...3 {
            // Карточка ещё листается — ждём, пока «Дальше» снова нажимается, а не жмём в анимацию.
            guard tapWhenReady(app.buttons["intro.next"], timeout: 3) else { break }
            settle(0.9)
            snap("ui-91-intro-\(k)")
        }
        let done = app.buttons["intro.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "ui-91: нет «Понятно, поехали» на последней карточке")
        tapWhenReady(done)
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "ui-91: знакомство не закрылось")
        app.terminate()
    }

    /// Раздел «Подсказки» в настройках и знакомство, открытое оттуда снова.
    @MainActor
    func testStates92Hints() throws {
        let app = try shootOptional("ui-92-settings-hints",
                                    env: ["PET_NOW": Self.noon, "PET_SCHEME": "light", "PET_OPEN": "settings"],
                                    marker: "settings.intro", lazyIn: "settings.siri", keepRunning: true)
        let row = app.descendants(matching: .any)["settings.intro"]
        if inView(row, app) {
            if tap(row, expecting: app.buttons["intro.next"], name: "ui-92-settings-intro-reopen") {
                settle(1)
                snap("ui-92-settings-intro-reopen")
            }
        }
        app.terminate()
    }

    /// Автомат: под кошельком строчка, что такое 🪙, 🎟 и ✂️.
    @MainActor
    func testStates92CapsuleLegend() throws {
        try shootOptional("ui-92-capsule-legend",
                          env: ["PET_NOW": Self.noon, "PET_SCHEME": "light", "PET_OPEN": "capsule"],
                          marker: "capsule.walletHelp")
    }

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
        if tapWhenReady(bow) {
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
        if waitHittable(row, timeout: 3) {
            if tap(row, expecting: app.descendants(matching: .any)["ownerSleep.now"], name: "ui-69-owner-sleep-edit") {
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
        let any = app.descendants(matching: .any)
        let first = any.matching(NSPredicate(format: "identifier BEGINSWITH %@", "shop.buy.")).firstMatch
        // Волна 30: лавка — лист поверх листа автомата; единственный тап по «Купить» изредка уходит в жест листа
        // (CI 39449839223: тап синтезирован, кадр до и после совпал байт в байт). Ждём, пока кнопка нажимаема,
        // и жмём с одним повтором по общему хелперу: «Куплено» на этой же кнопке — результат. Повтор безопасен —
        // второй тап по проданному ядро отклоняет (ShopDaily.buy: sold), а кнопка «Куплено» выключена.
        guard waitHittable(first, timeout: 10) else {
            XCTFail("ui-68: нет кнопки «Купить» в лавке: \(idsNow(app).filter { $0.hasPrefix("shop.") }.sorted())")
            app.terminate()
            return
        }
        let id = first.identifier
        let buy = any[id]
        settle(0.5)
        let sold = any.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", id, "Куплено")).firstMatch
        let ok = tap(buy, expecting: sold, timeout: 6, name: "ui-68-shop-buy")
        let refusal = any["shop.refusal"]
        XCTAssertTrue(ok, "ui-68: после покупки \(id) нет «Куплено»; кнопка: «\(buy.label)»; отказ: «\(refusal.exists ? refusal.label : "нет")»")
        settle(0.8)
        snap("ui-68-shop-bought")
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

    /// Рот крупным планом (PET_CAMERA=face, полдень, волна 13): морда в покое; потом итог «Блок Дуо» → «Готово» —
    /// Шиба в комнате говорит фразу про партию, и пока висит реплика, челюсть «говорит» по гласным. Три кадра через 0,35 с.
    @MainActor
    func testStates85Face() throws {
        shootState("ui-85-face-idle", env: ["PET_NOW": Self.noon, "PET_SCHEME": "light", "PET_CAMERA": "face"],
                   marker: Self.mainMarker, settleFor: 2.0)
        let env = Self.blockDuoEnv.merging(["PET_BLOCKDUO": "done", "PET_CAMERA": "face"]) { $1 }
        let app = try shootOptional("ui-85-face-result", env: env, marker: "blockduo.result", keepRunning: true)
        let done = app.descendants(matching: .any)["blockduo.done"].firstMatch
        if tapWhenReady(done) {
            // Экран уезжает, через 0,6 с реплика — дальше рот говорит до ~3 с.
            settle(1.1)
            for k in 1...3 {
                snap("ui-85-face-talk-\(k)")
                settle(0.35)
            }
        }
        app.terminate()
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
            for _ in 0..<8 where !inView(element, app) {
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
        // Главный экран: стеклянные кнопки сначала пересматривают готовую комнату (GlassSettle), потом пауза.
        if marker == Self.mainMarker { waitGlass(app) }
        settle(settleFor)
        snap(name)
        XCTAssertTrue(found, "\(name): нет элемента \(marker)")
        app.terminate()
    }

    /// Волна 27: дождаться, пока ряды стеклянных кнопок пересоздадутся поверх готовой комнаты — pet.stage
    /// в UI-тестах несёт «glass=N», N ≥ 1 (GlassSettle). Иначе Liquid Glass держит светлый или тёмный вид, который
    /// выбрал над недогруженной сценой, и снимок ui-53 меняется от прогона к прогону.
    /// Старая сборка (A/B-замер) этого значения не знает — тогда просто истекает ожидание.
    @MainActor
    @discardableResult
    func waitGlass(_ app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        let stage = app.descendants(matching: .any)["pet.stage"].firstMatch
        let settled = NSPredicate(format: "value MATCHES %@", ".*glass=[1-9][0-9]*$")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: settled, object: stage)],
                                timeout: timeout) == .completed
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
}

// Системный запрос проверен в этом процессе тестов: разрешение запоминает симулятор, а не приложение (PET_RESET его
// не сбрасывает), поэтому ждать алерт имеет смысл только при первом запуске; дальше — мгновенная проверка.
@MainActor private var springboardChecked = false

// Общие помощники снимков и нажатий: ими пользуются все UI-тесты (FirstMinutes, House, Animation, Guide).
extension XCTestCase {
    @MainActor
    func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Дать анимациям и 3D-сцене дорисоваться. Только для момента снимка: ждать элемент — waitHittable/waitForExistence.
    func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Дождаться, пока элемент можно нажать: есть в дереве, на экране и не перекрыт (лист доехал, затемнение ушло).
    @MainActor
    @discardableResult
    /// Элемент на экране по рамке. isHittable у ленивой строки Form за краем экрана не false, а падение теста
    /// («Activation point invalid») — поэтому при прокрутке смотрим на рамку.
    func inView(_ e: XCUIElement, _ app: XCUIApplication) -> Bool {
        guard e.exists else { return false }
        let f = e.frame, screen = app.windows.firstMatch.frame
        return !f.isEmpty && screen.insetBy(dx: 0, dy: 40).contains(CGPoint(x: f.midX, y: f.midY))
    }

    func waitHittable(_ e: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        if e.exists && e.isHittable { return true }
        let ready = NSPredicate(format: "exists == true AND hittable == true")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: ready, object: e)], timeout: timeout) == .completed
    }

    /// Нажать, когда кнопка готова. Не стала нажимаемой, но есть (SwiftUI иногда не отдаёт hittable у стекла) —
    /// тап в центр рамки, как сделал бы палец. Нет совсем — false, решает вызывающий.
    @MainActor
    @discardableResult
    func tapWhenReady(_ e: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        if waitHittable(e, timeout: timeout) {
            e.tap()
            return true
        }
        guard e.exists else { return false }
        e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    /// Нажать и дождаться результата. Не дождались, а кнопка всё ещё нажимаема (лист не перекрыл её) — тап ушёл
    /// в анимацию или первый кадр раскладки: снимок <name>-retry для разбора и ещё одно нажатие. Повтор только
    /// при отсутствии результата — второй тап по открывшемуся листу не попадёт.
    @MainActor
    @discardableResult
    func tap(_ e: XCUIElement, expecting target: XCUIElement, timeout: TimeInterval = 5, name: String) -> Bool {
        guard tapWhenReady(e) else { return false }
        if target.waitForExistence(timeout: timeout) { return true }
        guard e.exists, e.isHittable else { return target.exists }
        snap("\(name)-retry")
        e.tap()
        return target.waitForExistence(timeout: timeout)
    }

    /// Повторять проверку, пока не выйдет или не истечёт срок (волна 41 H). Пока на экране 3D, на CI-симуляторе
    /// один запрос к дереву идёт 20–40 с, и XCTNSPredicateExpectation с таймаутом 5–8 с успевал проверить один раз:
    /// состояние наступало на секунду позже — тест падал. Здесь проверок минимум две, срок смотрим после каждой,
    /// так что последнее состояние перед сроком всегда проверено. Ретраи с таймаутом вместо фиксированных пауз.
    @MainActor
    @discardableResult
    func eventually(timeout: TimeInterval, poll: TimeInterval = 0.5, _ check: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var tries = 0
        while true {
            if check() { return true }
            tries += 1
            if tries >= 2 && Date() >= deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(poll))
        }
    }

    /// Значение элемента одним снимком; элемента нет — nil.
    @MainActor
    func valueNow(_ e: XCUIElement) -> String? {
        guard let s = try? e.snapshot() else { return nil }
        return s.value as? String
    }

    /// Опрашивать снимок элемента, пока check не выйдет; вернуть последний снимок (подпись и значение из ОДНОГО
    /// состояния). Волна 45 P: прямое scene.label / scene.value — отдельный запрос к дереву, и при 3D на CI он сам
    /// упирался в таймаут запроса: тест падал со спиндампом, хотя проверяемое давно было на экране (testDogAtStation,
    /// джобы 122926946641, 123043578333). Снимок через try? — неудача запроса значит «ещё раз», а не провал.
    @MainActor
    @discardableResult
    func waitSnapshot(_ e: XCUIElement, timeout: TimeInterval = 60,
                      _ check: (XCUIElementSnapshot) -> Bool) -> (ok: Bool, last: XCUIElementSnapshot?) {
        var last: XCUIElementSnapshot?
        let ok = eventually(timeout: timeout) {
            guard let s = try? e.snapshot() else { return false }
            last = s
            return check(s)
        }
        return (ok, last)
    }

    /// Дождаться, пока в значении элемента есть все подстроки (сцены двора: «frame=ready», «dog3d=on»…).
    @MainActor
    @discardableResult
    func waitValue(_ e: XCUIElement, has parts: String..., timeout: TimeInterval = 60) -> Bool {
        waitValue(e, all: parts, timeout: timeout)
    }

    @MainActor
    @discardableResult
    func waitValue(_ e: XCUIElement, all parts: [String], timeout: TimeInterval = 60) -> Bool {
        eventually(timeout: timeout) {
            guard let v = valueNow(e) else { return false }
            return parts.allSatisfy { v.contains($0) }
        }
    }

    /// Перед снимком 3D: дождаться признака готовности сцены («frame=ready» — мир по текущему ключу прожил несколько
    /// кадров, YardFrame) вместо паузы наугад. Это про качество кадра, не проверка поведения: не дождались — снимок
    /// всё равно делаем, а в отчёт кладём заметку <name>-not-ready с последним значением, чтобы было видно почему.
    @MainActor
    @discardableResult
    func readyForSnap(_ e: XCUIElement, has parts: String..., timeout: TimeInterval = 60, name: String) -> Bool {
        if waitValue(e, all: parts, timeout: timeout) { return true }
        let note = XCTAttachment(string: "\(name): за \(Int(timeout)) с нет \(parts.joined(separator: ", ")); value=\(valueNow(e) ?? "нет элемента")")
        note.name = "\(name)-not-ready"
        note.lifetime = .keepAlways
        add(note)
        return false
    }

    /// Дождаться, пока элемент уйдёт из дерева, опросом (пара к waitExists).
    @MainActor
    @discardableResult
    func waitGone(_ e: XCUIElement, timeout: TimeInterval = 60) -> Bool {
        eventually(timeout: timeout) { !e.exists }
    }

    /// Дождаться элемента опросом (а не одним waitForExistence, которое на CI с 3D успевает глянуть раз).
    @MainActor
    @discardableResult
    func waitExists(_ e: XCUIElement, timeout: TimeInterval = 60) -> Bool {
        eventually(timeout: timeout) { e.exists }
    }

    /// Идентификаторы всего, что сейчас в дереве приложения, одним снимком иерархии. Проверка «А и Б вместе»
    /// двумя запросами гоняется с таймерами (тост живёт 2,5 с): между запросами один уходит, другой возвращается.
    @MainActor
    func idsNow(_ app: XCUIApplication) -> Set<String> {
        guard let root = try? app.snapshot() else { return [] }
        var out = Set<String>()
        var stack: [XCUIElementSnapshot] = [root]
        while let s = stack.popLast() {
            if !s.identifier.isEmpty { out.insert(s.identifier) }
            stack.append(contentsOf: s.children)
        }
        return out
    }

    /// Системные алерты рисует SpringBoard, не приложение: снимаем и разрешаем. В UI-тестах их не ждём (запрос
    /// уведомлений выключен под тестом, шагомера на симуляторе нет), поэтому 2 с ожидания — только на первом
    /// запуске процесса, дальше мгновенная проверка: раньше это были лишние ~2 с на каждом из ~70 запусков.
    @MainActor
    func acceptSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = ["Разрешить", "Allow", "OK", "ОК", "Разрешить при использовании", "Allow While Using App"]
        let firstWait: TimeInterval = springboardChecked ? 0 : 2
        springboardChecked = true
        for n in 0..<3 {
            let alert = springboard.alerts.firstMatch
            let present = n == 0 && firstWait == 0 ? alert.exists : alert.waitForExistence(timeout: n == 0 ? firstWait : 1)
            guard present else { return }
            snap("ui-00-alert-\(n + 1)")
            if let title = allow.first(where: { alert.buttons[$0].exists }) {
                alert.buttons[title].tap()
            } else if alert.buttons.count > 0 {
                alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
            } else {
                return
            }
            settle(1)
        }
    }
}
