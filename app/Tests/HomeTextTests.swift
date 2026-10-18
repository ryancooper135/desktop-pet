// Тексты главного экрана: спокойный таймер без секунд, когда ему обновляться, кошелёк и подпись сцены для VoiceOver,
// высота листа шкал. Гоняются и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet

final class HomeTextTests: XCTestCase {

    // MARK: таймер под репликой

    func testCalmRemainingHasNoSeconds() {
        XCTAssertEqual(HomeText.calmRemaining(2 * 3600 + 51 * 60 + 59), "2 ч 51 мин", "минуты вниз, секунд нет")
        XCTAssertEqual(HomeText.calmRemaining(40 * 60 + 43), "40 мин")
        XCTAssertEqual(HomeText.calmRemaining(7200), "2 ч", "ровно часы — без «0 мин»")
        XCTAssertEqual(HomeText.calmRemaining(7200 + 30), "2 ч")
        XCTAssertEqual(HomeText.calmRemaining(3599), "59 мин")
        XCTAssertEqual(HomeText.calmRemaining(60), "1 мин")
        XCTAssertEqual(HomeText.calmRemaining(26 * 3600 + 5 * 60), "26 ч 5 мин")
    }

    func testCalmRemainingUnderMinute() {
        XCTAssertEqual(HomeText.calmRemaining(59.9), "меньше минуты")
        XCTAssertEqual(HomeText.calmRemaining(1), "меньше минуты")
        XCTAssertEqual(HomeText.calmRemaining(0), "меньше минуты")
        XCTAssertEqual(HomeText.calmRemaining(-30), "меньше минуты", "конец прошёл, снимок вот-вот обновится")
    }

    func testCalmTimerPhrase() {
        XCTAssertEqual(HomeText.calmTimer(kind: "low", title: "Испачкается", remaining: 2 * 3600 + 51 * 60 + 12),
                       "Испачкается через 2 ч 51 мин")
        XCTAssertEqual(HomeText.calmTimer(kind: "low", title: "Заскучает", remaining: 40 * 60 + 43),
                       "Заскучает через 40 мин")
        XCTAssertEqual(HomeText.calmTimer(kind: "bath", title: "Моется", remaining: 4 * 60 + 10), "Моется ещё 4 мин")
        XCTAssertEqual(HomeText.calmTimer(kind: "low", title: "Испачкается", remaining: 7200), "Испачкается через 2 ч")
        XCTAssertEqual(HomeText.calmTimer(kind: "low", title: "", remaining: 600), "через 10 мин")
    }

    func testCalmTimerUnderMinuteReadsAsRussian() {
        XCTAssertEqual(HomeText.calmTimer(kind: "low", title: "Проголодается", remaining: 42),
                       "Проголодается меньше чем через минуту", "не «через меньше минуты»")
        XCTAssertEqual(HomeText.calmTimer(kind: "nap", title: "Дремлет", remaining: 10), "Дремлет ещё меньше минуты")
        XCTAssertEqual(HomeText.calmTimer(kind: "walk", title: "", remaining: 5), "ещё меньше минуты")
    }

    func testCalmTimerHasNoLiveDigits() {
        // Ни «40:43», ни секунд — таймер под репликой не должен дёргаться.
        for r in stride(from: 0.0, through: 4 * 3600, by: 37) {
            let s = HomeText.calmTimer(kind: "low", title: "Заскучает", remaining: r)
            XCTAssertFalse(s.contains(":"), s)
            XCTAssertFalse(s.contains(" с"), s)
        }
    }

    // MARK: когда обновляться

    func testNextChangeLandsOnMinuteBoundaryOfRemaining() {
        let end = 10_000.0, lag = HomeText.tickLag
        // Осталось 2:30 → следующий текст сразу после 2:00, через 30 с.
        XCTAssertEqual(HomeText.nextChange(after: end - 150, end: end), end - 120 + lag, accuracy: 1e-9)
        // Ровно 2:00 (ещё «2 мин») → сразу, как станет «1 мин».
        XCTAssertEqual(HomeText.nextChange(after: end - 120, end: end), end - 120 + lag, accuracy: 1e-9)
        // Только что сменилось → следующая смена через минуту.
        XCTAssertEqual(HomeText.nextChange(after: end - 120 + lag, end: end), end - 60 + lag, accuracy: 1e-9)
        // Меньше минуты → в момент конца.
        XCTAssertEqual(HomeText.nextChange(after: end - 30, end: end), end + lag, accuracy: 1e-9)
        // После конца — раз в минуту.
        XCTAssertEqual(HomeText.nextChange(after: end + 5, end: end), end + 65)
        XCTAssertEqual(HomeText.nextChange(after: end, end: end), end + 60)
    }

    func testTextChangesOnlyAtTicks() {
        // Между соседними тиками текст один и тот же, на тике — новый: экран перерисовывается раз в минуту.
        let end = 50_000.0
        var t = end - 3 * 3600 - 17
        var ticks = 0
        while t < end {
            let next = HomeText.nextChange(after: t, end: end)
            XCTAssertGreaterThan(next, t)
            XCTAssertLessThanOrEqual(next - t, 60.0001)
            let here = HomeText.calmTimer(kind: "low", title: "Испачкается", remaining: end - t)
            let before = HomeText.calmTimer(kind: "low", title: "Испачкается", remaining: end - (next - 0.5))
            XCTAssertEqual(here, before, "внутри минуты текст не меняется")
            t = next
            ticks += 1
        }
        XCTAssertEqual(ticks, 3 * 60 + 1, "по тику на минуту плюс первый неполный отрезок")
    }

    // MARK: VoiceOver

    func testWalletIsOnePhraseWithPlurals() {
        XCTAssertEqual(EconText.wallet(coins: 150, tickets: 1), "150 монет, 1 билетик")
        XCTAssertEqual(EconText.wallet(coins: 1, tickets: 0), "1 монета, 0 билетиков")
        XCTAssertEqual(EconText.wallet(coins: 2, tickets: 2), "2 монеты, 2 билетика")
        XCTAssertEqual(EconText.wallet(coins: 5, tickets: 5), "5 монет, 5 билетиков")
        XCTAssertEqual(EconText.wallet(coins: 11, tickets: 21), "11 монет, 21 билетик")
        XCTAssertEqual(EconText.wallet(coins: 22, tickets: 14), "22 монеты, 14 билетиков")
        XCTAssertFalse(EconText.wallet(coins: 150, tickets: 1).contains("🪙"))
    }

    func testStageLabelSaysNameOnce() {
        XCTAssertEqual(HomeText.stageLabel(name: "Шиба", pose: .idle), "Шиба спокоен", "не «Шиба: Шиба спокоен»")
        for pose in Pose.allCases {
            let s = HomeText.stageLabel(name: "Шиба", pose: pose)
            let count = s.components(separatedBy: "Шиб").count - 1
            XCTAssertEqual(count, 1, "\(pose): «\(s)»")
            XCTAssertFalse(s.hasPrefix("Шиба:"), s)
        }
    }

    func testStageLabelKeepsOtherName() {
        // Если когда-нибудь имя станет другим, фраза позы его не называет — имя остаётся спереди.
        XCTAssertEqual(HomeText.stageLabel(name: "Рыжик", pose: .idle), "Рыжик: Шиба спокоен")
        XCTAssertEqual(HomeText.stageLabel(name: "", pose: .sleep), "Шиба спит")
    }

    func testEveryPoseHasText() {
        for pose in Pose.allCases { XCTAssertFalse(HomeText.poseText(pose).isEmpty, "\(pose)") }
    }

    // MARK: лист шкал

    func testSheetHeightFollowsContent() {
        XCTAssertEqual(HomeText.sheetHeight(content: 412.3), 421)
        XCTAssertEqual(HomeText.sheetHeight(content: 50), 200, "не щёлочка")
        XCTAssertGreaterThan(HomeText.sheetHeight(content: 1500), 1500, "длинное не режем — система ограничит, лист прокрутится")
    }
}
