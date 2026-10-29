// Волна 45 P: прогрев симулятора перед UI-тестами шарда. Ничего не проверяет и ничего не снимает.
// Первый UI-тест шарда платил холодный старт: установка приложения и раннера, первая загрузка RealityKit и
// компиляция Metal-шейдеров — на CI это 1,5–3 мин, и первым тестам (LevelUITests/testAchievementsSheet в шарде 3)
// не хватало 3 минут на свои проверки (прогон 40765117525). Класс назван так, чтобы идти первым (XCTest гоняет
// классы по алфавиту): шарды 1 и 3 берут его явно (app.yml, warm_ui), шард 2 — сам, его нет в -skip-testing.
// Двор с 3D — самый тяжёлый экран: после него шейдеры и ассеты уже в кэше у всех остальных тестов.

import XCTest

final class A0WarmUpUITests: XCTestCase {
    @MainActor
    func testWarmUp() throws {
        // Свой потолок: холодный старт под 3D бывает дольше 3 мин, а проверок здесь нет — ждать не страшно.
        executionTimeAllowance = 360
        let app = ScreenshotUITests.makeApp()
        app.launchEnvironment["PET_SEED"] = "yard_plates"
        app.launchEnvironment["PET_NOW"] = ScreenshotUITests.noon
        app.launchEnvironment["PET_SCHEME"] = "light"
        app.launchEnvironment["PET_OPEN"] = "yard"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60), "приложение не запустилось")
        acceptSystemAlerts()
        // Ждём первый кадр двора; не дождались — не падаем: двор проверяют свои тесты, тут только прогрев.
        let scene = app.descendants(matching: .any)["yard.screen.scene"]
        let start = Date()
        let frame = waitSnapshot(scene, timeout: 240) { ($0.value as? String)?.contains("frame=ready") == true }
        XCTContext.runActivity(named: "прогрев: кадр двора \(frame.ok ? "готов" : "не дождались") за "
                               + "\(Int(Date().timeIntervalSince(start))) с") { _ in }
        app.terminate()
    }
}
