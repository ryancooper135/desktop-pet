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
        XCTAssertEqual(T.strokePath, 220)
        XCTAssertEqual(T.tickleTaps, 4)
        XCTAssertEqual(T.tickleWindow, 1.5)
        XCTAssertEqual(T.swipeUp, 80)
        XCTAssertEqual(T.swipeSide, 60)
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
}
