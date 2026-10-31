// Волна 31 «для всех»: аудит доступности (XCUIApplication.performAccessibilityAudit, Xcode 15+) на главном экране
// и листах, которые появились после волны 15, плюс крупный шрифт AccessibilityXL со снимком.
//
// Аудит не падает на первом же замечании: собирает все, отбрасывает задокументированные исключения (excuse ниже,
// почему — RESEARCH/17-a11y.md) и валит тест одним списком того, что осталось. Полный отчёт с исключениями —
// вложения «a11y-audit-<экран>» (видно в артефактах CI), чтобы исключения не прятали новое.
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
        var interactive = false
        /// Подробное описание аудита и рамка элемента — только в отчёт у настоящих замечаний (у elementDetection
        /// элемента нет, без снимка и подробностей непонятно, какой текст аудит увидел).
        var detail = ""
        var line: String { "[\(screen)] \(type) · \(id.isEmpty ? "—" : id) «\(label)»: \(text)" }
    }

    /// Исключения (документированы в RESEARCH/17-a11y.md, «Аудит»). nil — замечание настоящее.
    /// clipStrict — обрезку текста считать замечанием (крупный шрифт); на обычном размере она только в отчёте.
    static func excuse(_ f: Found, fixed: Bool, clipStrict: Bool = false) -> String? {
        // 3D-сцена: SceneKit/RealityKit-кадр аудит видит картинкой, контраст и «текст» в нём не про нас.
        if f.id == "pet.stage" || f.id == "blockduo.board" {
            return "3D-сцена или игровое поле: картинка, озвучено подписью и значением"
        }
        // Главный экран, панель, HUD и игры фиксированы (волна 15): растёт только реплика.
        if fixed && f.type == "dynamicType" { return "фиксированный экран (волна 15)" }
        // Эмодзи-значки (блюдо, предмет, монета) фиксированного размера, скрыты от VoiceOver: рисунок, а не текст.
        if ["dynamicType", "textClipped", "contrast"].contains(f.type) && Self.emojiOnly(f.label) {
            return "эмодзи-значок фиксированного размера"
        }
        // petFont растёт с Dynamic Type, но не больше 2× (A11y.fontCap, решение волны 31): аудит зовёт это «частично».
        if f.type == "dynamicType" && f.text.localizedCaseInsensitiveContains("partially") {
            return "petFont: растёт до потолка 2×"
        }
        // Цветной эмодзи (🪙, 🎟) в строке выше строки текста: аудит считает глиф обрезанным, на снимке он целый.
        if f.type == "textClipped" && Self.hasEmoji(f.label) { return "эмодзи в строке выше кегля" }
        // Прирост блюда «Сытость +45 · Настроение +6 · Ласка +4» на XL переносится по «·» и на снимке
        // ui-97-a11y-xl-kitchen виден целиком; аудит всё равно зовёт перенесённую строку обрезанной (2 прогона).
        // Перед «+» неразрывный пробел (Cooking.gainsText).
        if f.type == "textClipped" && f.label.contains(" · ") && f.label.contains("\u{00A0}+") { return "прирост блюда: перенесён целиком, см. ui-97" }
        // Зона касания важна тому, что нажимают. Строка шкалы, сердечки, подписи — не кнопки, их только читают.
        if f.type == "hitRegion" && !f.interactive { return "не нажимается: подпись, а не кнопка" }
        // Обычный размер шрифта не менялся с волны 15 (зрячий текст не трогаем); ужатие minimumScaleFactor аудит
        // тоже зовёт обрезкой. Многоточий на снимках ui-46/49/77 нет. Строго — только на крупном шрифте.
        if f.type == "textClipped" && !clipStrict { return "обычный размер: ужатие по ширине, без многоточия" }
        // Контраст в прогон не входит (см. audited); если попадёт — цвета палитры, вопрос вкуса в PROGRESS.
        if f.type == "contrast" { return "контраст палитры: вопрос Вадиму (PROGRESS «Ждёт Вадима»)" }
        return nil
    }

    /// Замечание elementDetection без элемента: ни id, ни подписи — аудит не может показать, какой текст увидел.
    static func ghostText(_ f: Found) -> Bool {
        f.type == "elementDetection" && f.id.isEmpty && f.label.isEmpty
    }

    // MARK: - аудит

    /// Что проверяем: всё, кроме контраста. Контраст — самая долгая проверка (снимок на каждый текст), а его
    /// замечания — цвета палитры, вопрос вкуса: список из прогона 39510200240 — в RESEARCH/17-a11y.md и PROGRESS.
    static let audited: XCUIAccessibilityAuditType = XCUIAccessibilityAuditType.all.subtracting(.contrast)

    // Пять тестов по 1–3 экрана: перезапуск с аудитом — 20–120 с на экран, а CI даёт тесту 180 с
    // (-default-test-execution-time-allowance), свой потолок — executionTimeAllowance ниже. Отчёт — после каждого
    // экрана, чтобы и при убийстве по времени было видно, что успели.
    // Волна 45 P: «Кухня, лавка, автомат, дом» одним тестом шли 233 с на обычном раннере и вылетели за 400 с на
    // перегруженном (прогон 40792335518, дом не успел) — разбиты на два по два экрана, экраны и проверки те же.

    /// Главный экран: 3D-комната, панель, стеклянные кнопки — отдельно, он самый долгий.
    @MainActor
    func testAccessibilityAudit1Main() throws {
        try audit(["main"])
    }

    /// Лист шкал, трюки, альбом.
    @MainActor
    func testAccessibilityAudit2Sheets() throws {
        try audit(["needs", "tricks", "album"])
    }

    /// Кухня и лавка.
    @MainActor
    func testAccessibilityAudit3Shops() throws {
        try audit(["kitchen", "shop"])
    }

    /// Автомат и дом.
    @MainActor
    func testAccessibilityAudit3bCapsuleHouse() throws {
        try audit(["capsule", "house"])
    }

    /// Заставка «Блок Дуо» («Зомби» убран в волне 55).
    @MainActor
    func testAccessibilityAudit4Games() throws {
        try audit(["blockduo"])
    }

    /// VoiceOver-подписи, контраст, зоны касания, обрезка текста, трейты — на каждом экране из списка.
    @MainActor
    func audit(_ names: [String]) throws {
        executionTimeAllowance = 400
        var real: [Found] = []
        var skipped: [String] = []
        for s in Self.screens where names.contains(s.name) {
          for attempt in 1...2 {
            let started = Date()
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
                break
            }
            if s.name == "main" { waitStageSettled(app) }
            settle(1.5)
            let ready = Date()
            report("a11y-audit-" + s.name + "-start", ["Экран \(s.name) открыт за \(Int(ready.timeIntervalSince(started))) с"])
            var found: [Found] = []
            try app.performAccessibilityAudit(for: Self.audited) { issue in
                found.append(Self.describe(issue, screen: s.name))
                return true
            }
            var mine: [Found] = []
            var excused: [String] = []
            for f in found {
                if let why = Self.excuse(f, fixed: s.fixed) {
                    excused.append(f.line + " — исключение: " + why)
                } else {
                    mine.append(f)
                }
            }
            // «Возможно, недоступный текст» без элемента, подписи и рамки — догадка ML-распознавания по снимку,
            // и она плавает: один и тот же лист (needs/tricks/album) в прогоне 41197598812 помечен, в 41204615972
            // чистый, и без полки/HUD тоже чистый. Такое — перепроверить один раз с перезапуска; повторилось —
            // настоящее замечание (см. RESEARCH/17-a11y.md, «Аудит»).
            if attempt == 1 && !mine.isEmpty && mine.allSatisfy(Self.ghostText) {
                report("a11y-audit-" + s.name + "-retry", ["Экран \(s.name): попытка 1, только призрачный текст — перепроверка", ""]
                       + mine.map { $0.detail.isEmpty ? $0.line : $0.line + "\n    " + $0.detail })
                app.terminate()
                continue
            }
            real += mine
            if !mine.isEmpty {
                // Снимок экрана после аудита: что было видно, когда нашлось замечание.
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "a11y-audit-" + s.name + "-shot"
                shot.lifetime = .keepAlways
                add(shot)
            }
            let took = "аудит \(Int(Date().timeIntervalSince(ready))) с"
            report("a11y-audit-" + s.name, ["Экран \(s.name): \(took)", "", "Замечания:"]
                   + mine.map { $0.detail.isEmpty ? $0.line : $0.line + "\n    " + $0.detail }
                   + ["", "Исключения:"] + excused)
            app.terminate()
            break
          }
        }
        XCTAssertTrue(skipped.isEmpty, "аудит: не открылись \(skipped)")
        XCTAssertTrue(real.isEmpty, "аудит доступности, \(real.count) замечаний:\n" + real.map(\.line).joined(separator: "\n"))
    }

    /// Текстовый отчёт во вложения xcresult (и Pet-screens), хранится и у зелёного теста.
    func report(_ name: String, _ lines: [String]) {
        let a = XCTAttachment(string: lines.joined(separator: "\n"))
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    // MARK: - крупный шрифт

    /// AccessibilityXL: главный экран (фиксированный, растёт реплика) и листы Кухни и Лавки — карточки стопкой.
    /// Аудит обрезки текста (textClipped) на листах: при крупном шрифте ничего не режется многоточием.
    @MainActor
    func testAccessibilityExtraLargeText() throws {
        executionTimeAllowance = 300
        let shots: [(name: String, env: [String: String], marker: String)] = [
            ("ui-97-a11y-xl-main", [:], ScreenshotUITests.mainMarker),
            ("ui-97-a11y-xl-kitchen", ["PET_SEED": "kitchen", "PET_OPEN": "kitchen"], "kitchen.screen"),
            ("ui-97-a11y-xl-shop", ["PET_SEED": "items", "PET_OPEN": "shop"], "shop.screen"),
        ]
        var clipped: [String] = []
        var excused: [String] = []
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
                    if let why = Self.excuse(f, fixed: false, clipStrict: true) {
                        excused.append(f.line + " — исключение: " + why)
                    } else {
                        clipped.append(f.line)
                    }
                    return true
                }
            }
            app.terminate()
        }
        report("a11y-audit-xl", ["AccessibilityXL, обрезка текста", "", "Замечания:"] + clipped
               + ["", "Исключения:"] + excused)
        XCTAssertTrue(clipped.isEmpty, "AccessibilityXL режет текст:\n" + clipped.joined(separator: "\n"))
    }

    // MARK: - помощники

    @MainActor
    static func describe(_ issue: XCUIAccessibilityAuditIssue, screen: String) -> Found {
        let e = issue.element
        let alive = e?.exists ?? false
        let kinds: [XCUIElement.ElementType] = [.button, .link, .switch, .toggle, .slider, .stepper, .textField,
                                                .segmentedControl, .picker, .menuItem, .cell, .tab]
        return Found(screen: screen, type: typeName(issue.auditType),
                     id: alive ? (e?.identifier ?? "") : "", label: alive ? (e?.label ?? "") : "",
                     text: issue.compactDescription,
                     interactive: !alive || kinds.contains(e?.elementType ?? .any),
                     detail: issue.detailedDescription + (alive ? " · рамка \(e?.frame ?? .zero)" : ""))
    }

    /// Подпись — только эмодзи (с модификаторами и ZWJ), без букв и цифр.
    static func emojiOnly(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && t.unicodeScalars.allSatisfy { u in
            (u.properties.isEmojiPresentation || u.properties.isEmoji && u.value > 0xFF)
                || u.value == 0x200D || (0xFE00...0xFE0F).contains(u.value)
        }
    }

    /// В подписи есть эмодзи (монета, билетик рядом с числом).
    static func hasEmoji(_ s: String) -> Bool {
        s.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0x2000 }
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
