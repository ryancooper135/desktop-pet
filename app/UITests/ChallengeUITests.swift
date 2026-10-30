// Волна 35 K: челлендж дня в мини-играх. Сид LaunchSeed challenge — пёс ур. 12, рекорд «Блок Дуо» 1800 (цель 2 000).
// Игра челленджа зависит от дня (Мячик ↔ Блок Дуо по кругу; зомби убран в волне 55), поэтому PET_NOW — полдень ближайшего дня,
// когда челлендж в «Блок Дуо» (тот же счёт суток, что Challenges.game: местные сутки по поясу симулятора).
//   ui-35-challenge-badge      «Блок Дуо», карточка «Играть»: плашка «Челлендж: 2 000 · сегодня»
//   ui-35-challenge-reward     партия автопилотом (сид 7) до конца: всплывашка «+1 ✂️ · +10 опыта»
//   ui-35-challenge-done       через 3 с плашка «✓ Челлендж выполнен»
//   ui-35-challenge-elsewhere  «Лови мячик» в тот же день: «Челлендж дня — в «Блок Дуо»»

import XCTest

final class ChallengeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBadgeOnBlockDuo() throws {
        let app = launch(open: "blockduo")
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["blockduo.screen"].firstMatch.waitForExistence(timeout: 20), "экран «Блок Дуо» не открылся")
        let badge = any["challenge.badge"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 10), "нет плашки челленджа")
        XCTAssertTrue(badge.label.contains("набери"), "плашка: \(badge.label)")
        settle(1)
        snap("ui-35-challenge-badge")
        app.terminate()
    }

    @MainActor
    func testRewardThenDone() throws {
        let app = launch(open: "blockduo", extra: ["PET_BLOCKDUO": "done"])
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["blockduo.screen"].firstMatch.waitForExistence(timeout: 20), "экран «Блок Дуо» не открылся")
        // Всплывашка живёт 3 с, а запуск с системными алертами бывает дольше — снимок по возможности,
        // обязательна итоговая плашка «выполнен» (она есть, только если раунд засчитан).
        let reward = any["challenge.reward"].firstMatch
        if reward.waitForExistence(timeout: 4) {
            XCTAssertTrue(reward.label.contains("✂️"), "всплывашка: \(reward.label)")
            snap("ui-35-challenge-reward")
        }

        let badge = any.matching(identifier: "challenge.badge")
            .matching(NSPredicate(format: "label CONTAINS %@", "выполнен")).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 10), "плашка не стала «Челлендж выполнен»")
        settle(0.5)
        snap("ui-35-challenge-done")
        app.terminate()
    }

    @MainActor
    func testElsewhereOnCatch() throws {
        let app = launch(open: "catch")
        let any = app.descendants(matching: .any)
        let badge = any["challenge.badge"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 20), "нет плашки челленджа на «Лови мячик»")
        XCTAssertTrue(badge.label.contains("Блок Дуо"), "плашка: \(badge.label)")
        settle(1.5)
        snap("ui-35-challenge-elsewhere")
        app.terminate()
    }

    // MARK: помощники

    /// Сид challenge, полдень дня «Блок Дуо», светлая тема, сразу открыть экран игры.
    @MainActor
    private func launch(open: String, extra: [String: String] = [:]) -> XCUIApplication {
        let app = ScreenshotUITests.makeApp()
        app.launchEnvironment["PET_SEED"] = "challenge"
        app.launchEnvironment["PET_NOW"] = Self.blockDuoNoon()
        app.launchEnvironment["PET_SCHEME"] = "light"
        app.launchEnvironment["PET_OPEN"] = open
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение не запустилось")
        acceptSystemAlerts()
        return app
    }

    /// Полдень ближайшего (сегодня или позже) дня, когда челлендж в «Блок Дуо»: сутки № d с d mod 2 == 1,
    /// как Challenges.game(day:) по реестру MiniGame — Мячик, Блок Дуо.
    static func blockDuoNoon() -> String {
        let start = Calendar.current.startOfDay(for: Date())
        for k in 0..<2 {
            let noon = start.addingTimeInterval(Double(k * 86400 + 12 * 3600))
            let t = noon.timeIntervalSince1970
            let off = Double(TimeZone.current.secondsFromGMT(for: noon))
            let day = Int(((t + off) / 86400).rounded(.down))
            if ((day % 2) + 2) % 2 == 1 { return String(Int(t)) }
        }
        return ScreenshotUITests.noon
    }
}
