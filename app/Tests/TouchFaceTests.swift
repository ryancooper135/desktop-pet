// Лицо под пальцем (волна 50): касание откладывает моргание, повторная ласка продлевает идущую,
// пена в ванне — детерминированная и в пределах тела.

import XCTest
@testable import Pet

final class TouchFaceTests: XCTestCase {
    func testTouchDelaysAndCutsBlink() {
        // Моргание через 0,1 с — после касания не раньше touchHold.
        var r = EyeBlink.touched(time: 10, nextBlink: 10.1, blinkUntil: 0)
        XCTAssertEqual(r.nextBlink, 10 + EyeBlink.touchHold, accuracy: 1e-9)
        // Уже моргает — глаз открывается сразу.
        r = EyeBlink.touched(time: 10, nextBlink: 14, blinkUntil: 10.08)
        XCTAssertEqual(r.blinkUntil, 10)
        XCTAssertEqual(r.nextBlink, 14, "дальнее моргание не приближаем")
    }

    func testTenFastTapsNeverBlink() {
        // 10 тапов раз в 0,25 с, кадры по 1/60: случайное моргание ни разу не попадает под палец.
        var next = 0.05, until = 0.0
        var shutTouched = 0
        var touchUntil = -1.0
        var t = 0.0
        var tap = 0
        while t < 3.5 {
            if tap < 10, t >= Double(tap) * 0.25 {
                (next, until) = EyeBlink.touched(time: t, nextBlink: next, blinkUntil: until)
                touchUntil = t + EyeBlink.touchHold
                tap += 1
            }
            if t >= next {
                until = t + 0.13
                next = t + 3
            }
            if t < touchUntil, t < until { shutTouched += 1 }
            t += 1.0 / 60
        }
        XCTAssertEqual(tap, 10)
        XCTAssertEqual(shutTouched, 0)
    }

    func testPettingExtendsUpToCap() {
        XCTAssertTrue(PettingSpan.active(start: 0, length: 3, now: 1))
        XCTAssertFalse(PettingSpan.active(start: 0, length: 3, now: 3))
        XCTAssertFalse(PettingSpan.active(start: 5, length: 3, now: 1))
        // Продление: до now + add, не короче прежней.
        XCTAssertEqual(PettingSpan.extended(start: 0, length: 3, now: 2.5), 2.5 + PettingSpan.add, accuracy: 1e-9)
        XCTAssertEqual(PettingSpan.extended(start: 0, length: 3, now: 0.5), 3)
        // Отказ (add 0) не удлиняет.
        XCTAssertEqual(PettingSpan.extended(start: 0, length: 3, now: 2.5, add: 0), 3)
        // Не дольше cap от начала.
        XCTAssertEqual(PettingSpan.extended(start: 0, length: 7.5, now: 7.4), PettingSpan.cap)
        // Уже длиннее cap — не режем.
        XCTAssertEqual(PettingSpan.extended(start: 0, length: 9, now: 8.5), 9)
        // 10 тапов подряд: ласка тянется, а не начинается заново.
        var length = 3.0
        for k in 1...10 {
            let now = Double(k) * 0.3
            XCTAssertTrue(PettingSpan.active(start: 0, length: length, now: now), "тап \(k) продлевает")
            length = PettingSpan.extended(start: 0, length: length, now: now)
        }
        XCTAssertLessThanOrEqual(length, PettingSpan.cap)
    }

    func testHappyFace() {
        XCTAssertGreaterThan(HappyFace.hold, 0.5)
        XCTAssertGreaterThan(HappyFace.jaw, 0)
        XCTAssertLessThanOrEqual(HappyFace.jaw, 0.2, "не шире речи")
    }

    func testFoamIsDeterministicAndBounded() {
        let a = BathFoam.bubbles(seed: 7, side: 0.4)
        XCTAssertEqual(a, BathFoam.bubbles(seed: 7, side: 0.4))
        XCTAssertNotEqual(a, BathFoam.bubbles(seed: 8, side: 0.4))
        XCTAssertEqual(a.count, BathFoam.count)
        for seed in 0..<50 {
            for side: Float in [-1, 0, 1, 5, .nan] {
                for b in BathFoam.bubbles(seed: seed, side: side) {
                    XCTAssert((-1...1).contains(b.start.x))
                    XCTAssert((0...1).contains(b.start.y))
                    XCTAssert((-1...1).contains(b.start.z))
                    XCTAssertGreaterThan(b.drift.y, 0, "пузырь поднимается")
                    XCTAssert((0.03...0.08).contains(b.radius))
                    XCTAssertGreaterThanOrEqual(b.delay, 0)
                    XCTAssertGreaterThan(b.life, 0.2)
                    XCTAssertLessThanOrEqual(b.delay + b.life, BathFoam.total + 1e-9)
                }
            }
        }
        // Пена гуще со стороны руки.
        let right = BathFoam.bubbles(seed: 3, side: 1).map(\.start.x).reduce(0, +)
        let left = BathFoam.bubbles(seed: 3, side: -1).map(\.start.x).reduce(0, +)
        XCTAssertGreaterThan(right, left)
    }
}
