// Касания по сцене: тап, тики, ласка, щекотка, свайп вверх. Чистая логика, без UI.

import CoreGraphics
import XCTest
@testable import Pet

final class StrokeTrackerTests: XCTestCase {
    private typealias T = StrokeTracker

    /// Тап в точке p, начиная с момента t: касание и отпускание через dt.
    private func tap(_ s: inout StrokeTracker, at t: Double, dt: Double = 0.1, p: CGPoint = CGPoint(x: 100, y: 100)) -> [StrokeEvent] {
        s.begin(at: p, time: t)
        return s.end(at: p, time: t + dt)
    }

    /// Горизонтальное ведение пальцем по шагам step, всего на length.
    private func drag(_ s: inout StrokeTracker, length: CGFloat, step: CGFloat = 10, from: CGPoint = CGPoint(x: 0, y: 200)) -> [StrokeEvent] {
        s.begin(at: from, time: 0)
        var out: [StrokeEvent] = []
        var x: CGFloat = 0
        var t = 0.0
        while x < length {
            x = min(length, x + step)
            t += 0.016
            out += s.move(to: CGPoint(x: from.x + x, y: from.y), time: t)
        }
        out += s.end(at: CGPoint(x: from.x + length, y: from.y), time: t + 0.016)
        return out
    }

    func testThresholdsAreStatic() {
        XCTAssertEqual(T.tapMaxPath, 12)
        XCTAssertEqual(T.tapMaxTime, 0.3)
        XCTAssertEqual(T.tickStep, 50)
        XCTAssertEqual(T.strokePath, 150)
        XCTAssertEqual(T.tickleTaps, 4)
        XCTAssertEqual(T.tickleWindow, 1.5)
        XCTAssertEqual(T.swipeUp, 80)
        XCTAssertEqual(T.upRatio, 1.5)
        XCTAssertEqual(T.upLock, 30)
    }

    func testShortTouchIsTap() {
        var s = StrokeTracker()
        s.begin(at: CGPoint(x: 100, y: 100), time: 10)
        XCTAssertEqual(s.move(to: CGPoint(x: 103, y: 104), time: 10.05), [])
        XCTAssertEqual(s.end(at: CGPoint(x: 103, y: 104), time: 10.1), [.tap])
        XCTAssertFalse(s.active)
    }

    func testLongPressIsNotTap() {
        var s = StrokeTracker()
        XCTAssertEqual(tap(&s, at: 0, dt: 0.5), [])
    }

    func testStrokeGivesTicksAndOneStroke() {
        var s = StrokeTracker()
        let ev = drag(&s, length: 260)
        let ticks = ev.filter { if case .tick = $0 { return true } else { return false } }
        XCTAssertEqual(ticks, [.tick(1), .tick(2), .tick(3), .tick(4), .tick(5)])
        XCTAssertEqual(ev.filter { $0 == .stroke }.count, 1)
        XCTAssertFalse(ev.contains(.tap))
        XCTAssertFalse(ev.contains(.swipeUp))
    }

    func testStrokeOncePerGesture() {
        var s = StrokeTracker()
        s.begin(at: .zero, time: 0)
        XCTAssertTrue(s.move(to: CGPoint(x: 230, y: 0), time: 0.3).contains(.stroke))
        // Ещё 30 pt в том же жесте: путь 260, тик 5 есть, второй ласки нет.
        XCTAssertEqual(s.move(to: CGPoint(x: 260, y: 0), time: 0.4), [.tick(5)])
        XCTAssertEqual(s.end(at: CGPoint(x: 260, y: 0), time: 0.5), [])
        // Новый жест — снова можно.
        XCTAssertEqual(drag(&s, length: 230).filter { $0 == .stroke }.count, 1)
    }

    func testFourQuickTapsTickle() {
        var s = StrokeTracker()
        XCTAssertEqual(tap(&s, at: 0.0), [.tap])
        XCTAssertEqual(tap(&s, at: 0.4), [.tap])
        XCTAssertEqual(tap(&s, at: 0.8), [.tap])
        XCTAssertEqual(tap(&s, at: 1.1), [.tickle])
        // Окно сброшено: следующий тап обычный.
        XCTAssertEqual(tap(&s, at: 1.3), [.tap])
    }

    func testFourSlowTapsNoTickle() {
        var s = StrokeTracker()
        var all: [StrokeEvent] = []
        for i in 0..<4 { all += tap(&s, at: Double(i) * 0.633) }
        XCTAssertEqual(all, [.tap, .tap, .tap, .tap])
    }

    func testSwipeUp() {
        var s = StrokeTracker()
        s.begin(at: CGPoint(x: 200, y: 400), time: 0)
        _ = s.move(to: CGPoint(x: 205, y: 350), time: 0.05)
        let ev = s.end(at: CGPoint(x: 210, y: 300), time: 0.1)
        XCTAssertTrue(ev.contains(.swipeUp))
        XCTAssertFalse(ev.contains(.stroke))
        XCTAssertFalse(ev.contains(.tap))
    }

    func testSideSwipeIsNotSwipeUp() {
        var s = StrokeTracker()
        s.begin(at: CGPoint(x: 200, y: 400), time: 0)
        let ev = s.end(at: CGPoint(x: 300, y: 300), time: 0.2)
        XCTAssertFalse(ev.contains(.swipeUp))
    }

    /// Ведение пальцем из from в to по шагам (по прямой).
    private func line(_ s: inout StrokeTracker, from: CGPoint, to: CGPoint, steps: Int = 30) -> [StrokeEvent] {
        s.begin(at: from, time: 0)
        var out: [StrokeEvent] = []
        for i in 1...steps {
            let k = CGFloat(i) / CGFloat(steps)
            out += s.move(to: CGPoint(x: from.x + (to.x - from.x) * k, y: from.y + (to.y - from.y) * k), time: Double(i) * 0.016)
        }
        out += s.end(at: to, time: Double(steps + 1) * 0.016)
        return out
    }

    // Волна 18: длинный свайп вверх раньше набирал путь ласки (220) и вместо шкал гладил.
    func testLongSwipeUpOpensNeedsNotStroke() {
        var s = StrokeTracker()
        let ev = line(&s, from: CGPoint(x: 200, y: 700), to: CGPoint(x: 220, y: 250))
        XCTAssertEqual(ev, [.swipeUp], "450 pt вверх — только свайп: ни тиков, ни ласки")
    }

    func testSlantedSwipeUpStillSwipe() {
        var s = StrokeTracker()
        // ~30° от вертикали: |dy| 300, |dx| 160 (≥ 1.5·|dx|).
        let ev = line(&s, from: CGPoint(x: 100, y: 600), to: CGPoint(x: 260, y: 300))
        XCTAssertTrue(ev.contains(.swipeUp))
        XCTAssertFalse(ev.contains(.stroke))
    }

    func testDiagonalUpIsStrokeNotSwipe() {
        var s = StrokeTracker()
        // 45°: вбок столько же, сколько вверх — это ласка, шкалы не открываем.
        let ev = line(&s, from: CGPoint(x: 50, y: 500), to: CGPoint(x: 250, y: 300))
        XCTAssertTrue(ev.contains(.stroke))
        XCTAssertFalse(ev.contains(.swipeUp))
    }

    func testStrokeThenFlickUpGivesBoth() {
        var s = StrokeTracker()
        s.begin(at: CGPoint(x: 100, y: 500), time: 0)
        var ev: [StrokeEvent] = []
        // Погладил вбок и обратно (путь 300) — ласка засчитана…
        ev += s.move(to: CGPoint(x: 250, y: 500), time: 0.2)
        ev += s.move(to: CGPoint(x: 100, y: 500), time: 0.4)
        XCTAssertEqual(ev.filter { $0 == .stroke }.count, 1)
        // …потом увёл палец вверх: от касания в основном вверх — свайп тоже.
        _ = s.move(to: CGPoint(x: 110, y: 350), time: 0.5)
        XCTAssertTrue(s.end(at: CGPoint(x: 110, y: 300), time: 0.6).contains(.swipeUp))
    }

    func testUpThenSidewaysResumesTicks() {
        var s = StrokeTracker()
        s.begin(at: CGPoint(x: 200, y: 500), time: 0)
        XCTAssertEqual(s.move(to: CGPoint(x: 200, y: 400), time: 0.1), [], "вверх — молчим")
        // Ушёл вбок: от касания уже не «в основном вверх», набранный путь догоняет тиками.
        let ev = s.move(to: CGPoint(x: 400, y: 400), time: 0.3)
        XCTAssertEqual(ev, [.tick(1), .tick(2), .tick(3), .tick(4), .tick(5), .tick(6), .stroke])
        XCTAssertFalse(s.end(at: CGPoint(x: 400, y: 400), time: 0.4).contains(.swipeUp))
    }

    func testShortStrokeCountsAt150() {
        var s = StrokeTracker()
        XCTAssertEqual(drag(&s, length: 140).filter { $0 == .stroke }.count, 0)
        XCTAssertEqual(drag(&s, length: 150).filter { $0 == .stroke }.count, 1)
    }
}
