// Волна 31 «для всех»: аудит доступности (XCUIApplication.performAccessibilityAudit, Xcode 15+) на главном экране
// и листах, которые появились после волны 15, плюс крупный шрифт AccessibilityXL со снимком.
//
// Аудит не падает на первом же замечании: собирает все, отбрасывает задокументированные исключения (Excuse ниже,
// почему — RESEARCH/17-a11y.md) и валит тест одним списком того, что осталось. Полный отчёт с исключениями —
// вложение «a11y-audit» (видно в артефактах CI), чтобы исключения не прятали новое.
//
//   ui-97-a11y-xl-main      главный экран на AccessibilityXL: панель и комната фиксированы (волна 15), реплика растёт
//   ui-97-a11y-xl-kitchen   «Кухня» на AccessibilityXL: карточки стопкой (AXRow), названия переносятся, без обрезки
//   ui-97-a11y-xl-shop      «Лавка дня» на AccessibilityXL: кнопка «Купить» под описанием, цена не режется

import XCTest

final class AccessibilityUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// Экран для аудита: что открыть (PET_OPEN), какой сид, по какому элементу понять, что открылся.
    /// fixed — экран нарочно не растёт с Dynamic Type (главный, игры): замечания dynamicType там — исключение.
    struct Screen {
        let name: String
        var env: [String: String] = [:]
        let marker: String
        var fixed = false
    }

    static let screens: [Screen] = [
        Screen(name: "main", marker: ScreenshotUITests.mainMarker, fixed: true),
        Screen(name: "needs", env: ["PET_OPEN": "needs"], marker: "needs.sheet"),
        Screen(name: "kitchen", env: ["PET_SEED": "kitchen", "PET_OPEN": "kitchen"], marker: "kitchen.screen"),
        Screen(name: "shop", env: ["PET_SEED": "items", "PET_OPEN": "shop"], marker: "shop.screen"),
        Screen(name: "capsule", env: ["PET_SEED": "items", "PET_OPEN": "capsule"], marker: "capsule.screen"),
        Screen(name: "house", env: ["PET_OPEN": "house"], marker: "house.screen"),
        Screen(name: "tricks", env: ["PET_OPEN": "tricks"], marker: "tricks.screen"),
        Screen(name: "album", env: ["PET_SEED": "memories", "PET_OPEN": "album"], marker: "album.sheet"),
        Screen(name: "zombie", env: ["PET_SEED": "zombie", "PET_OPEN": "zombie"], marker: "zombie.play", fixed: true),
        Screen(name: "blockduo", env: ["PET_SEED": "blockduo", "PET_OPEN": "blockduo"], marker: "blockduo.screen",
               fixed: true),
    ]

    /// Одно замечание аудита словами: экран, тип, элемент, описание.
    struct Found {
        let screen: String
        let type: String
        let id: String
        let label: String
        let text: String
        var line: String { "[\(screen)] \(type) · \(id.isEmpty ? "—" : id) «\(label)»: \(text)" }
    }

    /// Исключения (документированы в RESEARCH/17-a11y.md, «Аудит»). nil — замечание настоящее.
    static func excuse(_ f: Found, fixed: Bool) -> String? {
        // 3D-сцена: SceneKit/RealityKit-кадр аудит видит картинкой, контраст и «текст» в нём не про нас.
        if f.id == "pet.stage" || f.id == "zombie.view" || f.id == "blockduo.board" {
            return "3D-сцена или игровое поле: картинка, озвучено подписью и значением"
        }
        // Главный экран, панель, HUD и игры фиксированы (волна 15): растёт только реплика.
        if fixed && f.type == "dynamicType" { return "фиксированный экран (волна 15)" }
        return nil
    }

    // MARK: - аудит

    /// Главный экран и листы: VoiceOver-подписи, контраст, зоны касания, обрезка текста, трейты.
    @MainActor
    func testAccessibilityAudit() throws {
        var real: [Found] = []
        var excused: [String] = []
        var skipped: [String] = []
        for s in Self.screens {
            let app = ScreenshotUITests.makeApp()
            app.launchEnvironment["PET_NOW"] = ScreenshotUITests.noon
            app.launchEnvironment["PET_SCHEME"] = "light"
            for (k, v) in s.env { app.launchEnvironment[k] = v }
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "\(s.name): приложение не запустилось")
            acceptSystemAlerts()
            guard app.descendants(matching: .any)[s.marker].firstMatch.waitForExistence(timeout: 20) else {
                skipped.append(s.name)
                app.terminate()
                continue
            }
            if s.name == "main" { waitStageSettled(app) }
            settle(1.5)
            var found: [Found] = []
            try app.performAccessibilityAudit { issue in
                found.append(Self.describe(issue, screen: s.name))
                return true
            }
            for f in found {
                if let why = Self.excuse(f, fixed: s.fixed) {
                    excused.append(f.line + " — исключение: " + why)
                } else {
                    real.append(f)
                }
            }
            app.terminate()
        }
        let report = (["Замечания:"] + real.map(\.line) + ["", "Исключения:"] + excused
                      + ["", "Не открылись: " + skipped.joined(separator: ", ")]).joined(separator: "\n")
        let a = XCTAttachment(string: report)
        a.name = "a11y-audit"
        a.lifetime = .keepAlways
        add(a)
        XCTAssertTrue(skipped.isEmpty, "аудит: не открылись \(skipped)")
        XCTAssertTrue(real.isEmpty, "аудит доступности, \(real.count) замечаний:\n" + real.map(\.line).joined(separator: "\n"))
    }

    // MARK: - крупный шрифт

    /// AccessibilityXL: главный экран (фиксированный, растёт реплика) и листы Кухни и Лавки — карточки стопкой.
    /// Аудит обрезки текста (textClipped) на листах: при крупном шрифте ничего не режется многоточием.
    @MainActor
    func testAccessibilityExtraLargeText() throws {
        let shots: [(name: String, env: [String: String], marker: String)] = [
            ("ui-97-a11y-xl-main", [:], ScreenshotUITests.mainMarker),
            ("ui-97-a11y-xl-kitchen", ["PET_SEED": "kitchen", "PET_OPEN": "kitchen"], "kitchen.screen"),
            ("ui-97-a11y-xl-shop", ["PET_SEED": "items", "PET_OPEN": "shop"], "shop.screen"),
        ]
        var clipped: [String] = []
        for shot in shots {
            let app = ScreenshotUITests.makeApp()
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
            app.launchEnvironment["PET_NOW"] = ScreenshotUITests.noon
            app.launchEnvironment["PET_SCHEME"] = "light"
            for (k, v) in shot.env { app.launchEnvironment[k] = v }
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "\(shot.name): приложение не запустилось")
            acceptSystemAlerts()
            let found = app.descendants(matching: .any)[shot.marker].firstMatch.waitForExistence(timeout: 20)
            XCTAssertTrue(found, "\(shot.name): нет элемента \(shot.marker)")
            if shot.marker == ScreenshotUITests.mainMarker { waitStageSettled(app) }
            settle(1.5)
            snap(shot.name)
            if found && shot.marker != ScreenshotUITests.mainMarker {
                try app.performAccessibilityAudit(for: .textClipped) { issue in
                    let f = Self.describe(issue, screen: shot.name)
                    if Self.excuse(f, fixed: false) == nil { clipped.append(f.line) }
                    return true
                }
            }
            app.terminate()
        }
        XCTAssertTrue(clipped.isEmpty, "AccessibilityXL режет текст:\n" + clipped.joined(separator: "\n"))
    }

    // MARK: - помощники

    @MainActor
    static func describe(_ issue: XCUIAccessibilityAuditIssue, screen: String) -> Found {
        let e = issue.element
        let alive = e?.exists ?? false
        return Found(screen: screen, type: typeName(issue.auditType),
                     id: alive ? (e?.identifier ?? "") : "", label: alive ? (e?.label ?? "") : "",
                     text: issue.compactDescription)
    }

    static func typeName(_ t: XCUIAccessibilityAuditType) -> String {
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"), (.elementDetection, "elementDetection"), (.hitRegion, "hitRegion"),
            (.sufficientElementDescription, "sufficientElementDescription"), (.dynamicType, "dynamicType"),
            (.textClipped, "textClipped"), (.trait, "trait"),
        ]
        return names.first { t.contains($0.0) }?.1 ?? "type\(t.rawValue)"
    }

    /// Стеклянные кнопки главного пересоздаются поверх готовой комнаты (волна 27, GlassSettle): ждём glass=N.
    @MainActor
    func waitStageSettled(_ app: XCUIApplication, timeout: TimeInterval = 15) {
        let stage = app.descendants(matching: .any)["pet.stage"].firstMatch
        let settled = NSPredicate(format: "value MATCHES %@", ".*glass=[1-9][0-9]*$")
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: settled, object: stage)], timeout: timeout)
    }
}
