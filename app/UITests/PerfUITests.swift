// Замеры плавности и скорости (волна 26). Не снимки: числа уходят в xcresult, шаг CI «Perf metrics» печатает их
// в лог и кладёт perf-<шард>.json рядом с xcresult. Базы (baseline) не задаём — тест падает только если сценарий
// сломался (лист не открылся, кнопки нет), а не от медленного раннера: числа сравниваем глазами в RESEARCH/13-perf.md.
// Итераций мало (3 + разогрев), чтобы шард рос не больше чем на ~2 мин.
//   testPerfLaunch      холодный запуск до первого кадра и отклика (XCTApplicationLaunchMetric)
//   testPerfNeedsSheet  тап «Шкалы» → лист на экране: время, память и CPU приложения
//   testPerfFeedAnim    тап «Покормить» и 3 с анимации: CPU и память приложения
//   testPerfIdle        5 с покоя на главном (Шиба дышит, ничего не трогаем): CPU — это и есть батарея.
//                       Волна 27: 6 итераций вместо 3 (+15 с) — покой шумнее остальных замеров.
//   testPerfIdleMinutes волна 56 «лёгкость»: 3 минуты покоя на главном (3 итерации по 60 с): CPU за минуту (доля CPU =
//                       CPU Time / Clock — прокси батареи; батарею на симуляторе честно не померить), память и её рост.
//                       Только в режиме perf (job perf ставит TEST_RUNNER_PET_PERF_LONG=1): в обычном шарде 3 — skip.
//                       RESEARCH/56-lightness.md.

import XCTest

final class PerfUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private static func options(_ n: Int = 3) -> XCTMeasureOptions {
        let o = XCTMeasureOptions()
        o.iterationCount = n
        return o
    }

    private static func manualOptions() -> XCTMeasureOptions {
        let o = options()
        o.invocationOptions = [.manuallyStart, .manuallyStop]
        return o
    }

    /// Тот же день и тема на каждом запуске: числа сравнимы между прогонами.
    @MainActor
    private func perfApp() -> XCUIApplication {
        let app = ScreenshotUITests.makeApp()
        app.launchEnvironment["PET_NOW"] = ScreenshotUITests.noon
        app.launchEnvironment["PET_SCHEME"] = "light"
        return app
    }

    @MainActor
    private func launchHome() -> XCUIApplication {
        let app = perfApp()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        XCTAssertTrue(app.descendants(matching: .any)[ScreenshotUITests.mainMarker].waitForExistence(timeout: 20),
                      "нет главного экрана")
        settle(2)
        return app
    }

    @MainActor
    func testPerfLaunch() throws {
        let app = perfApp()
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: Self.options()) {
            app.launch()
            app.terminate()
        }
    }

    @MainActor
    func testPerfNeedsSheet() throws {
        let app = launchHome()
        let any = app.descendants(matching: .any)
        let open = any["open.needs"].firstMatch
        let sheet = any["needs.sheet"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5), "нет ручки «Шкалы»")
        let metrics: [XCTMetric] = [XCTClockMetric(), XCTMemoryMetric(application: app), XCTCPUMetric(application: app)]
        measure(metrics: metrics, options: Self.manualOptions()) {
            XCTAssertTrue(waitHittable(open, timeout: 10), "ручка «Шкалы» не нажимается")
            startMeasuring()
            open.tap()
            let shown = waitHittable(sheet, timeout: 10)
            stopMeasuring()
            XCTAssertTrue(shown, "лист шкал не открылся")
            close(app, sheet: sheet)
        }
        app.terminate()
    }

    @MainActor
    func testPerfFeedAnim() throws {
        let app = launchHome()
        let feed = app.descendants(matching: .any)["act.feed"].firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: 5), "нет кнопки «Покормить»")
        let metrics: [XCTMetric] = [XCTMemoryMetric(application: app), XCTCPUMetric(application: app)]
        measure(metrics: metrics, options: Self.manualOptions()) {
            // Волна 27: стекло иногда не отдаёт hittable, хотя кнопка на месте (как в tapWhenReady): в A/B-замерах
            // «не нажимается» роняло раунды. Есть, но не hittable — тап в центр рамки, как сделал бы палец.
            XCTAssertTrue(feed.waitForExistence(timeout: 10), "«Покормить» пропала")
            let ready = waitHittable(feed, timeout: 5)
            startMeasuring()
            if ready {
                feed.tap()
            } else {
                feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            settle(3)
            stopMeasuring()
            settle(1)
        }
        app.terminate()
    }

    @MainActor
    func testPerfIdle() throws {
        let app = launchHome()
        let metrics: [XCTMetric] = [XCTMemoryMetric(application: app), XCTCPUMetric(application: app)]
        measure(metrics: metrics, options: Self.options(6)) {
            settle(5)
        }
        app.terminate()
    }

    /// Волна 56: долгий покой. Окно 60 с — чтобы в CPU попали и редкие события покоя (фиджеты режиссёра раз в несколько
    /// секунд, свет комнаты раз в 5 с, тикер стора раз в 30 с), а память показала рост, если он есть.
    @MainActor
    func testPerfIdleMinutes() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PET_PERF_LONG"] == "1",
                          "долгий покой меряется только в режиме perf (TEST_RUNNER_PET_PERF_LONG=1)")
        executionTimeAllowance = 600
        let app = launchHome()
        let metrics: [XCTMetric] = [XCTClockMetric(), XCTMemoryMetric(application: app), XCTCPUMetric(application: app)]
        measure(metrics: metrics, options: Self.options(3)) {
            settle(60)
        }
        XCTAssertEqual(app.state, .runningForeground, "приложение ушло с экрана за время покоя")
        app.terminate()
    }

    /// Закрыть лист шкал: крестик, а нет — смахнуть вниз. Ждём, пока уедет, чтобы следующая итерация начиналась с главной.
    @MainActor
    private func close(_ app: XCUIApplication, sheet: XCUIElement) {
        let x = app.descendants(matching: .any)["needs.close"].firstMatch
        if waitHittable(x, timeout: 2) {
            x.tap()
        } else if sheet.exists {
            let from = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
            from.press(forDuration: 0.05, thenDragTo: sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.3)))
        }
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "лист шкал не закрылся")
        settle(1)
    }
}
