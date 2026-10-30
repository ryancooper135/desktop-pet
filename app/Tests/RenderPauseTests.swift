import XCTest
@testable import Pet

/// Волна 16: пауза комнаты под обложками и часы кадров мини-игр.
final class RenderPauseTests: XCTestCase {
    func testCoveredByAnyFullScreenCover() {
        XCTAssertFalse(StagePause.covered(catchGame: false, blockDuo: false, away: false))
        XCTAssertTrue(StagePause.covered(catchGame: true, blockDuo: false, away: false))
        XCTAssertTrue(StagePause.covered(catchGame: false, blockDuo: true, away: false))
        XCTAssertTrue(StagePause.covered(catchGame: false, blockDuo: false, away: true))
    }

    func testHideLateWakeAtOnce() {
        // Гасим, когда обложка доехала (въезд у SwiftUI ~0.35–0.5 с), включаем без задержки.
        XCTAssertGreaterThanOrEqual(StagePause.delay(covered: true), 0.5)
        XCTAssertLessThanOrEqual(StagePause.delay(covered: true), 1.5)
        XCTAssertEqual(StagePause.delay(covered: false), 0)
    }

    func testFrameClockSumsClampedSteps() {
        var c = FrameClock(now: 100)
        XCTAssertEqual(c.tick(now: 100.016, running: true), 0.016, accuracy: 1e-9)
        // Подвисание на секунду — шаг не больше maxStep.
        XCTAssertEqual(c.tick(now: 101.016, running: true), FrameClock.maxStep, accuracy: 1e-9)
        // Часы назад (не должно быть, но) — не отрицательный шаг.
        XCTAssertEqual(c.tick(now: 101.0, running: true), 0)
    }

    func testFrameClockStandsWhileInactive() {
        var c = FrameClock(now: 0)
        var t = 0.0
        var round = 0.0
        // 10 с неактивности: раунд стоит.
        for _ in 0..<40 {
            t += 0.25
            round += c.tick(now: t, running: false)
        }
        XCTAssertEqual(round, 0)
        // Вернулись — первый шаг обычный, пауза в него не попала.
        XCTAssertEqual(c.tick(now: t + 0.016, running: true), 0.016, accuracy: 1e-9)
    }

    func testIdleLoopWakesRarely() {
        XCTAssertEqual(FrameClock.waitMs(running: true), FrameClock.frameMs)
        XCTAssertGreaterThan(FrameClock.waitMs(running: false), FrameClock.frameMs * 10)
    }
}
