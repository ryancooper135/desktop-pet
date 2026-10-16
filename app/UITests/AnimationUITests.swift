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
    func testFeedFrames() throws { try recordAction("act.feed", name: "anim-feed") }

    @MainActor
    func testPetFrames() throws { try recordAction("act.pet", name: "anim-pet") }

    @MainActor
    func testPlayFrames() throws { try recordAction("act.play", name: "anim-play") }

    @MainActor
    func testWakeFrames() throws { try recordAction("act.wake", name: "anim-wake") }

    /// Дрёма из сида PET_SEED=nap, потом «Разбудить»: видно выход из сна.
    @MainActor
    func testWakeFromSleepFrames() throws {
        try recordAction("act.wake", name: "anim-wake-from-sleep", seed: "nap")
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
    func recordAction(_ identifier: String, name: String, seed: String? = nil) throws {
        let app = Self.makeApp(seed: seed)
        let stage = try launch(app)
        let button = app.descendants(matching: .any)[identifier]
        guard button.waitForExistence(timeout: 5) else {
            throw XCTSkip("нет кнопки \(identifier): сборка без идентификаторов действий")
        }
        guard button.isHittable else {
            throw XCTSkip("кнопка \(identifier) есть, но не нажимается (перекрыта или выключена)")
        }
        let crop = stage.frame
        let start = Date()
        button.tap()
        let frames = capture(app, crop: crop, count: Self.frameCount, step: Self.frameStep, since: start)
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
        Thread.sleep(forTimeInterval: 1)
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

    /// Как в ScreenshotUITests, плюс необязательный сид (PET_SEED=nap|critical|bath).
    @MainActor
    static func makeApp(seed: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-uiTesting"]
        app.launchEnvironment["PET_UI_TEST"] = "1"
        app.launchEnvironment["PET_RESET"] = "1"
        if let seed { app.launchEnvironment["PET_SEED"] = seed }
        return app
    }

    /// Системные алерты (уведомления, движение) перекрывают сцену: разрешить и закрыть.
    @MainActor
    func acceptSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = ["Разрешить", "Allow", "OK", "ОК", "Разрешить при использовании", "Allow While Using App"]
        for n in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: n == 0 ? 2 : 1) else { return }
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
        }
    }
}
