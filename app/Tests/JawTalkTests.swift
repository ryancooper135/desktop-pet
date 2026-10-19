// Челюсть «говорит» (JawTalk): гласные открывают, согласные чуть, пробел закрывает; конец и предел по времени.

import XCTest
@testable import Pet

final class JawTalkTests: XCTestCase {
    func testWeights() {
        XCTAssertEqual(JawTalk.weight("а"), 1)
        XCTAssertEqual(JawTalk.weight("Ю"), 1)
        XCTAssertEqual(JawTalk.weight("o"), 1)
        XCTAssertEqual(JawTalk.weight("г"), 0.45)
        XCTAssertEqual(JawTalk.weight("W"), 0.45)
        XCTAssertEqual(JawTalk.weight(" "), 0)
        XCTAssertEqual(JawTalk.weight("!"), 0)
        XCTAssertEqual(JawTalk.weight("7"), 0)
        XCTAssertEqual(JawTalk.weight("🐶"), 0)
    }

    func testOpensOnVowelAndClosesOnSpace() {
        let cps = JawTalk.charsPerSecond
        // «Гав! Ура» — буквы по 1/14 с: на «а» открыт полностью, на пробеле закрыт.
        let text = "Гав! Ура"
        XCTAssertEqual(JawTalk.openness(text, at: 1 / cps), 1, accuracy: 1e-9)
        XCTAssertEqual(JawTalk.openness(text, at: 0.0001 + 0 / cps), 0.45, accuracy: 0.01)
        XCTAssertEqual(JawTalk.openness(text, at: 4 / cps), 0, accuracy: 1e-9)
        // Между «а» и «в» — посередине.
        XCTAssertEqual(JawTalk.openness(text, at: 1.5 / cps), (1 + 0.45) / 2, accuracy: 1e-9)
    }

    func testSilentOutsideTheLine() {
        XCTAssertEqual(JawTalk.openness("Ура", at: 0), 0)
        XCTAssertEqual(JawTalk.openness("Ура", at: -1), 0)
        XCTAssertEqual(JawTalk.openness("Ура", at: 10), 0)
        XCTAssertEqual(JawTalk.openness("", at: 0.1), 0)
        XCTAssertEqual(JawTalk.openness("Ура", at: .nan), 0)
        XCTAssertEqual(JawTalk.openness("Ура", at: .infinity), 0)
    }

    func testLongLineStopsAtLimitAndFades() {
        let long = String(repeating: "а", count: 200)
        XCTAssertEqual(JawTalk.duration(long), JawTalk.maxTalk)
        XCTAssertEqual(JawTalk.openness(long, at: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(JawTalk.openness(long, at: JawTalk.maxTalk - JawTalk.fade / 2), 0.5, accuracy: 1e-6)
        XCTAssertEqual(JawTalk.openness(long, at: JawTalk.maxTalk + 0.01), 0)
    }

    func testAlwaysInRangeAndAngleCapped() {
        let text = "Наелся! Спасибо, хозяин 🐾 мм… вкусно-вкусно?!"
        var t = -0.5
        while t < 4 {
            let o = JawTalk.openness(text, at: t)
            XCTAssertGreaterThanOrEqual(o, 0)
            XCTAssertLessThanOrEqual(o, 1)
            XCTAssertLessThanOrEqual(JawTalk.angle(text, at: t), JawTalk.maxAngle + 1e-6)
            t += 0.013
        }
        XCTAssertEqual(JawTalk.maxAngle, 9 * .pi / 180, accuracy: 1e-6)
    }

    /// Говорит — значит рот хоть раз заметно открылся (не дрожь на месте).
    func testTalkingMovesTheJaw() {
        let text = "Привет! Я Шиба"
        var lo = 1.0, hi = 0.0
        var t = 0.0
        while t < JawTalk.duration(text) {
            let o = JawTalk.openness(text, at: t)
            lo = min(lo, o); hi = max(hi, o)
            t += 0.01
        }
        XCTAssertGreaterThan(hi, 0.9)
        XCTAssertLessThan(lo, 0.1)
    }
}
