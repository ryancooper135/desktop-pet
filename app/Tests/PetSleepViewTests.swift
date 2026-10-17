// Разворот спящей собаки боком к камере: цель по стойке, медленная пружина туда и обратно, Reduce Motion.

import Foundation
import XCTest
@testable import Pet

final class PetSleepViewTests: XCTestCase {
    @MainActor
    func testRestYawOnlyForSleep() {
        for s in Stance.allCases where s != .sleep {
            XCTAssertEqual(JuiceComponent.restYaw(for: s), 0, "\(s)")
        }
        XCTAssertEqual(JuiceComponent.restYaw(for: nil), 0)
        let y = JuiceComponent.restYaw(for: .sleep)
        // Вместе с yaw3q почти профиль (−75…−95°), но не спиной к камере.
        let total = (y + PetRoom.yaw3q) * 180 / .pi
        XCTAssertLessThan(total, -75)
        XCTAssertGreaterThan(total, -95)
    }

    /// Шаги по 1/60 с, пока не пройдёт t секунд.
    @MainActor
    private func run(_ c: inout JuiceComponent, _ t: Float) {
        for _ in 0..<Int(t * 60) { c.advance(1 / 60) }
    }

    @MainActor
    func testTurnsDuringLieInAndBack() {
        var c = JuiceComponent()
        c.restTarget = JuiceComponent.restYaw(for: .sleep)
        run(&c, 0.3)
        // Не рывком: за первые 0.3 с — меньше половины пути.
        XCTAssertLessThan(abs(c.rest), abs(c.restTarget) / 2)
        run(&c, 1.3)
        // К концу lie_in + начала sleep_in почти довернулся, без перелёта.
        XCTAssertEqual(c.rest, c.restTarget, accuracy: 0.03)
        run(&c, 3)
        XCTAssertEqual(c.rest, c.restTarget)
        XCTAssertEqual(c.angle, c.yaw + c.rest + c.sway * sin(c.swayPhase), accuracy: 1e-6)

        // Проснулся: обратно в 0 и ровно 0 после доводки.
        c.restTarget = JuiceComponent.restYaw(for: .stand)
        var highest = c.rest
        for _ in 0..<(5 * 60) {
            c.advance(1 / 60)
            highest = max(highest, c.rest)
        }
        XCTAssertEqual(c.rest, 0)
        XCTAssertEqual(c.restV, 0)
        XCTAssertLessThanOrEqual(highest, 0, "критическое демпфирование не перелетает через 0")
    }

    @MainActor
    func testStillSnaps() {
        var c = JuiceComponent()
        c.still = true
        c.restTarget = JuiceComponent.restYaw(for: .sleep)
        c.advance(1 / 60)
        XCTAssertEqual(c.rest, c.restTarget)
        c.restTarget = 0
        c.advance(1 / 60)
        XCTAssertEqual(c.rest, 0)
        XCTAssertEqual(c.restV, 0)
    }
}
