// Волна 64: разбор покоя главной по кускам. Каждый тест — запуск с ручками PET_PERF_KNOB (App/PerfKnobs.swift),
// 2 × 20 с покоя (CPU/Clock в xcresult, сводка perf.py ab по имени теста) и строка «PROBE <ручки>: …» из подписи
// perf.probe — частота кадров нашей системы, тела главной в секунду, размер сцены, классы вида RealityKit.
// Только в режиме perf (TEST_RUNNER_PET_PERF_LONG=1) и только по выборке perf_only=PerfDiagUITests:
// в обычных шардах — skip. Результаты — RESEARCH/56-lightness.md, «Волна 64».

import XCTest

final class PerfDiagUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PET_PERF_LONG"] == "1",
                          "разбор покоя — только в режиме perf (TEST_RUNNER_PET_PERF_LONG=1)")
    }

    @MainActor
    private func idle(_ knobs: String) throws {
        executionTimeAllowance = 300
        let app = ScreenshotUITests.makeApp()
        app.launchEnvironment["PET_NOW"] = ScreenshotUITests.noon
        app.launchEnvironment["PET_SCHEME"] = "light"
        app.launchEnvironment["PET_PERF_KNOB"] = knobs + ",probe"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        XCTAssertTrue(app.descendants(matching: .any)[ScreenshotUITests.mainMarker].waitForExistence(timeout: 20),
                      "нет главного экрана")
        settle(5)
        let o = XCTMeasureOptions()
        o.iterationCount = 2
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app)], options: o) {
            settle(20)
        }
        let probe = app.descendants(matching: .any)["perf.probe"].firstMatch
        let text = probe.waitForExistence(timeout: 3) ? probe.label : "подписи нет"
        print("PROBE \(knobs.isEmpty ? "base" : knobs): \(text)")
        // Кадр для глаз: ручки не должны менять картинку (артефакт Pet-perf, если CI задал папку).
        if let dir = ProcessInfo.processInfo.environment["PET_SHOT_DIR"], !dir.isEmpty {
            let name = (knobs.isEmpty ? "base" : knobs.replacingOccurrences(of: ",", with: "+"))
                + "-" + String(UUID().uuidString.prefix(4)) + ".png"
            try? XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        app.terminate()
    }

    /// Как в замере покоя: всё включено, пробы UI-тестов тоже.
    @MainActor func testDiag1Probe() throws { try idle("") }
    /// Без EyeProbeLabel (0,2 с) и EyeProbe на каждый кадр.
    @MainActor func testDiag2NoProbe() throws { try idle("noprobe") }
    /// Комната и пёс выключены, RealityView рисует пустой кадр.
    @MainActor func testDiag3StageOff() throws { try idle("noprobe,off") }
    /// Без RealityView: только SwiftUI главной.
    @MainActor func testDiag4NoStage() throws { try idle("noprobe,nostage") }
    /// Без теней ключевого света.
    @MainActor func testDiag5NoShadow() throws { try idle("noprobe,noshadow") }
    /// Наши системы ECS стоят.
    @MainActor func testDiag6NoSystems() throws { try idle("noprobe,nosys") }
    /// Системы стоят и клипы скелета остановлены.
    @MainActor func testDiag7Freeze() throws { try idle("noprobe,nosys,freeze") }
    /// Попытка 30 к/с через свойства вида RealityKit.
    @MainActor func testDiag8Fps30() throws { try idle("noprobe,fps30") }
    /// ARView.renderOptions: без размытия движения, глубины резкости, зерна, AR-окклюзии и AR-света.
    @MainActor func testDiag9RenderLite() throws { try idle("noprobe,ro") }
    /// То же и без HDR.
    @MainActor func testDiagANoHDR() throws { try idle("noprobe,ro,nohdr") }
    /// То же и без AR-теней на земле.
    @MainActor func testDiagBNoGrounding() throws { try idle("noprobe,ro,nogs") }
    /// Слой сцены в масштабе 2 вместо 3.
    @MainActor func testDiagCScale2() throws { try idle("noprobe,scale2") }
    /// CADisplayLink сцены (если найдётся) на 30 к/с.
    @MainActor func testDiagDLink30() throws { try idle("noprobe,dl30") }
}
