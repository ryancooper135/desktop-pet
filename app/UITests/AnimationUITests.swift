// Кадры анимации на симуляторе: тап по действию, потом 16 снимков сцены через 0.2 с,
// склеенных в контактный лист 4×4 (240 pt на кадр, подпись «#N +X.Xs»). Вложение anim-<id>, keepAlways;
// CI выгружает их в PNG вместе со скриншотами. Без Мака это единственный способ увидеть, как Шиба двигается.
//
// Нужны accessibilityIdentifier сцены (pet.stage) и кнопок (act.feed, act.pet, act.play, act.wake).
// Нет сцены или кнопки — тест пропускается (XCTSkip), а не падает: на main их может ещё не быть.

import UIKit
import XCTest

final class AnimationUITests: XCTestCase {
    static let frameCount = 16
    static let frameStep: TimeInterval = 0.2
    static let columns = 4
    static let cellWidth: CGFloat = 240
    static let labelHeight: CGFloat = 22

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // MARK: - Действия

    @MainActor
    func testFeedFrames() throws { try recordAction("act.feed", name: "anim-feed", count: 24, step: 0.4) }

    @MainActor
    func testPetFrames() throws { try recordAction("act.pet", name: "anim-pet") }

    @MainActor
    func testPlayFrames() throws { try recordAction("act.play", name: "anim-play", count: 24, step: 0.3) }

    @MainActor
    func testWakeFrames() throws { try recordAction("act.wake", name: "anim-wake") }

    /// Игра и прогулка среди вещей дома (PET_SEED=room_max, полдень): собака сходит с лежанки через бортик,
    /// бежит за мячом мимо игрового угла, уходит за край мимо ванны.
    @MainActor
    func testPlayRoomFrames() throws {
        try recordAction("act.play", name: "anim-play-room", seed: "room_max", noon: true, count: 24, step: 0.3)
    }

    @MainActor
    func testWalkOutRoomFrames() throws {
        try recordAction("act.walk", name: "anim-walk-room", seed: "room_max", noon: true, count: 24, step: 0.3)
    }

    /// Дрёма из сида PET_SEED=nap, потом «Разбудить»: видно выход из сна.
    @MainActor
    func testWakeFromSleepFrames() throws {
        try recordAction("act.wake", name: "anim-wake-from-sleep", seed: "nap")
    }

    /// «Гулять» у чистого щенка в полдень: поворот к краю, уход за кадр и пустая комната с запиской.
    @MainActor
    func testWalkOutFrames() throws {
        try recordAction("act.walk", name: "anim-walk-out", count: 24, step: 0.3)
    }

    /// Возвращение: сид PET_SEED=walk_back — гуляет и вернётся через 6 с после запуска. Сначала пустая
    /// комната с запиской, потом Шиба входит с шишкой в зубах, кладёт её, радуется, находка тает.
    @MainActor
    func testWalkBackFrames() throws {
        let app = Self.makeApp(seed: "walk_back", noon: true)
        let stage = try launch(app)
        let crop = stage.frame
        let frames = capture(app, crop: crop, count: 36, step: 0.4, since: Date())
        attachSheet(frames, name: "anim-walk")
    }

    /// Трюк «Сидеть» из листа «Трюки» (сид tricks: уже выучен; PET_TRICK_ROLL=0 — всегда выходит): лист уезжает,
    /// Шиба садится, сидит и встаёт, прыжок пружиной и тост «Сидит!».
    @MainActor
    func testTrickSitFrames() throws { try recordTrick("trick.sit", roll: "0", name: "anim-trick-sit", count: 24, step: 0.3) }

    /// Промах (PET_TRICK_ROLL=0.99): склонил голову, понюхал, «Не понял…».
    @MainActor
    func testTrickMissFrames() throws { try recordTrick("trick.lie", roll: "0.99", name: "anim-trick-miss") }

    @MainActor
    func recordTrick(_ identifier: String, roll: String, name: String,
                     count: Int = AnimationUITests.frameCount, step: TimeInterval = AnimationUITests.frameStep) throws {
        let app = Self.makeApp(seed: "tricks", noon: true)
        app.launchEnvironment["PET_TRICK_ROLL"] = roll
        let stage = try launch(app)
        let open = app.descendants(matching: .any)["open.tricks"]
        guard open.waitForExistence(timeout: 5), waitHittable(open) else {
            throw XCTSkip("нет кнопки open.tricks")
        }
        let crop = stage.frame
        let button = app.descendants(matching: .any)[identifier]
        guard tap(open, expecting: button, name: name) else {
            throw XCTSkip("нет кнопки \(identifier) в листе «Трюки»")
        }
        // Лист доехал — потом команда (нажимаема кнопка и в движении, поэтому ещё и пауза на выезд).
        settle(0.6)
        waitHittable(button, timeout: 3)
        let start = Date()
        button.tap()
        let frames = capture(app, crop: crop, count: count, step: step, since: start)
        attachSheet(frames, name: name)
    }

    /// Поглаживание пальцем: 4 мазка туда-обратно по сцене, после каждого по 4 кадра.
    @MainActor
    func testStrokeFrames() throws {
        let app = Self.makeApp()
        let stage = try launch(app)
        let crop = stage.frame
        let start = Date()
        var frames: [Frame] = []
        for i in 0..<4 {
            let left = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45))
            let right = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.45))
            if i % 2 == 0 {
                left.press(forDuration: 0.1, thenDragTo: right)
            } else {
                right.press(forDuration: 0.1, thenDragTo: left)
            }
            frames += capture(app, crop: crop, count: Self.frameCount / 4, step: Self.frameStep, since: start)
        }
        attachSheet(frames, name: "anim-stroke")
    }

    /// Тапы по питомцу (волна 18): слева, справа и два быстрых подряд, после каждого — кадры раз в 0,12 с.
    /// Голова склоняется плавно и чуть-чуть, хвост виляет, цикл простоя не перезапускается рывком.
    @MainActor
    func testTapFrames() throws {
        let app = Self.makeApp(noon: true)
        let stage = try launch(app)
        let crop = stage.frame
        let start = Date()
        var frames: [Frame] = []
        let left = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45))
        let right = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.45))
        left.tap()
        frames += capture(app, crop: crop, count: 6, step: 0.12, since: start)
        Thread.sleep(forTimeInterval: 0.6)
        right.tap()
        frames += capture(app, crop: crop, count: 6, step: 0.12, since: start)
        Thread.sleep(forTimeInterval: 0.6)
        right.tap()
        Thread.sleep(forTimeInterval: 0.25)
        right.tap()
        frames += capture(app, crop: crop, count: 8, step: 0.12, since: start)
        attachSheet(frames, name: "anim-tap")
    }

    /// Покой без действий: 16 кадров раз в 2 с (полминуты жизни на сцене).
    @MainActor
    func testIdleFrames() throws {
        let app = Self.makeApp()
        let stage = try launch(app)
        let crop = stage.frame
        let frames = capture(app, crop: crop, count: Self.frameCount, step: 2, since: Date())
        attachSheet(frames, name: "anim-idle")
    }

    // MARK: - Запись

    struct Frame {
        let image: UIImage
        let t: TimeInterval
    }

    @MainActor
    func recordAction(_ identifier: String, name: String, seed: String? = nil, noon: Bool? = nil,
                      count: Int = AnimationUITests.frameCount, step: TimeInterval = AnimationUITests.frameStep) throws {
        // Без сида — полдень по часам симулятора: ночью чистый щенок спит и «Поиграть» выключена.
        let app = Self.makeApp(seed: seed, noon: noon ?? (seed == nil))
        let stage = try launch(app)
        let button = app.descendants(matching: .any)[identifier]
        guard button.waitForExistence(timeout: 5) else {
            throw XCTSkip("нет кнопки \(identifier): сборка без идентификаторов действий")
        }
        // Сразу после появления сцены кнопка может быть ещё под анимацией панели: ждём, а не пропускаем по первому взгляду.
        guard waitHittable(button) else {
            throw XCTSkip("кнопка \(identifier) есть, но не нажимается (перекрыта или выключена)")
        }
        let crop = stage.frame
        let start = Date()
        button.tap()
        let frames = capture(app, crop: crop, count: count, step: step, since: start)
        attachSheet(frames, name: name)
    }

    /// Запуск с чистым щенком; сцена pet.stage должна появиться, иначе — пропуск.
    @MainActor
    func launch(_ app: XCUIApplication) throws -> XCUIElement {
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        let stage = app.descendants(matching: .any)["pet.stage"]
        guard stage.waitForExistence(timeout: 15) else {
            throw XCTSkip("нет pet.stage: сборка без идентификатора сцены")
        }
        // Секунда сцене на загрузку модели и первый кадр.
        settle(1)
        return stage
    }

    /// count снимков экрана раз в step секунд, обрезанных по рамке сцены.
    /// Рамку берём один раз до действия: запрос элемента на каждом кадре сбивал бы шаг.
    @MainActor
    func capture(_ app: XCUIApplication, crop: CGRect, count: Int, step: TimeInterval, since start: Date) -> [Frame] {
        let screenWidth = app.frame.width
        var out: [Frame] = []
        for i in 0..<count {
            let shotAt = Date()
            let image = XCUIScreen.main.screenshot().image
            out.append(Frame(image: Self.cropped(image, to: crop, screenWidth: screenWidth),
                             t: shotAt.timeIntervalSince(start)))
            if i < count - 1 {
                let left = step - Date().timeIntervalSince(shotAt)
                if left > 0 { Thread.sleep(forTimeInterval: left) }
            }
        }
        return out
    }

    /// Вырезать сцену из снимка экрана. Масштаб — пиксели снимка на точку экрана.
    /// Что-то не сходится (нулевая рамка, нет cgImage) — весь экран.
    static func cropped(_ image: UIImage, to rect: CGRect, screenWidth: CGFloat) -> UIImage {
        guard let cg = image.cgImage, screenWidth > 0, rect.width > 1, rect.height > 1 else { return image }
        let scale = CGFloat(cg.width) / screenWidth
        let px = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard !px.isNull, px.width > 1, px.height > 1, let part = cg.cropping(to: px) else { return image }
        return UIImage(cgImage: part)
    }

    // MARK: - Контактный лист

    /// 4 колонки по 240 pt, высота кадра по пропорциям первого, подпись над кадром.
    @MainActor
    func attachSheet(_ frames: [Frame], name: String) {
        guard let first = frames.first, first.image.size.width > 0 else {
            XCTFail("\(name): ни одного кадра")
            return
        }
        let cols = Self.columns
        let rows = (frames.count + cols - 1) / cols
        let cellW = Self.cellWidth
        let imgH = (cellW * first.image.size.height / first.image.size.width).rounded()
        let cellH = imgH + Self.labelHeight
        let size = CGSize(width: cellW * CGFloat(cols), height: cellH * CGFloat(rows))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let labelH = Self.labelHeight
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let png = renderer.pngData { ctx in
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 13),
                .foregroundColor: UIColor.white,
            ]
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            for (i, f) in frames.enumerated() {
                let x = CGFloat(i % cols) * cellW
                let y = CGFloat(i / cols) * cellH
                let label = "#\(i + 1) +" + String(format: "%.1f", f.t) + "s"
                NSString(string: label).draw(at: CGPoint(x: x + 6, y: y + 3), withAttributes: attrs)
                f.image.draw(in: CGRect(x: x, y: y + labelH, width: cellW, height: imgH))
            }
        }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Помощники

    /// Как в ScreenshotUITests, плюс необязательный сид (PET_SEED=nap|critical|bath|walk_back) и полдень (PET_NOW).
    @MainActor
    static func makeApp(seed: String? = nil, noon: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-uiTesting"]
        app.launchEnvironment["PET_UI_TEST"] = "1"
        app.launchEnvironment["PET_RESET"] = "1"
        if let seed { app.launchEnvironment["PET_SEED"] = seed }
        if noon {
            let t = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
            app.launchEnvironment["PET_NOW"] = String(Int(t.timeIntervalSince1970))
        }
        return app
    }
}
