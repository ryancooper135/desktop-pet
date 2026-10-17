// Чистая логика визуальной полировки виджетов и острова: подписи таймера, «Спасти», короткая реплика,
// пустая шкала, толщина линий мордочки, кольцо круглого виджета. Вью не рендерим — это делают снимки.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

final class VisualPolishTests: XCTestCase {

    // MARK: остаток таймера

    func testRemainingTextHoursAndMinutes() {
        XCTAssertEqual(Presenter.remainingText(9 * 3600 + 25 * 60 + 53), "9 ч 25 мин")
        XCTAssertEqual(Presenter.remainingText(7200), "2 ч")
        XCTAssertEqual(Presenter.remainingText(2400), "40 мин")
        XCTAssertEqual(Presenter.remainingText(3600), "1 ч")
        XCTAssertEqual(Presenter.remainingText(3599), "59 мин")
    }

    func testRemainingTextEdges() {
        XCTAssertEqual(Presenter.remainingText(30), "1 мин", "меньше минуты — всё равно «1 мин», не «0»")
        XCTAssertEqual(Presenter.remainingText(0), "0 мин")
        XCTAssertEqual(Presenter.remainingText(-120), "0 мин")
    }

    func testPrefixByKind() {
        XCTAssertEqual(Presenter.timerPrefix(kind: "low"), "через")
        XCTAssertEqual(Presenter.timerPrefix(kind: "bath"), "ещё")
        XCTAssertEqual(Presenter.timerPrefix(kind: "nap"), "ещё")
    }

    func testLiveCountdownOnlyUnderAnHour() {
        XCTAssertTrue(Presenter.timerIsLive(remaining: 40 * 60))
        XCTAssertTrue(Presenter.timerIsLive(remaining: 3599))
        XCTAssertFalse(Presenter.timerIsLive(remaining: 3600))
        XCTAssertFalse(Presenter.timerIsLive(remaining: 9 * 3600))
    }

    func testTimerPhrase() {
        XCTAssertEqual(Presenter.timerPhrase(kind: "low", title: "Испачкается", remaining: 9 * 3600 + 25 * 60),
                       "Испачкается через 9 ч 25 мин")
        XCTAssertEqual(Presenter.timerPhrase(kind: "bath", title: "Моется", remaining: 4 * 60),
                       "Моется ещё 4 мин")
        XCTAssertEqual(Presenter.timerPhrase(kind: "low", title: "", remaining: 7200), "через 2 ч")
    }

    func testTimerTitleMatchesKindAndNeed() {
        XCTAssertEqual(Presenter.timerTitle(kind: "bath", need: nil), "Моется")
        XCTAssertEqual(Presenter.timerTitle(kind: "nap", need: "food"), "Дремлет")
        XCTAssertEqual(Presenter.timerTitle(kind: "low", need: "food"), "Проголодается")
        XCTAssertEqual(Presenter.timerTitle(kind: "low", need: "clean"), "Испачкается")
        XCTAssertEqual(Presenter.timerTitle(kind: "low", need: "fun"), "Заскучает")
        XCTAssertEqual(Presenter.timerTitle(kind: "low", need: "love"), "Затоскует")
        XCTAssertEqual(Presenter.timerTitle(kind: "low", need: nil), "Попросит")
    }

    // MARK: критично, сон, короткая реплика, пустая шкала

    func testCritical() {
        XCTAssertTrue(Presenter.isCritical(level: 3, alive: true))
        XCTAssertFalse(Presenter.isCritical(level: 2, alive: true), "«плохо» ещё не красное")
        XCTAssertFalse(Presenter.isCritical(level: 3, alive: false), "умершему «Спасти» не показываем")
    }

    func testSnapshotFlags() {
        var s = PreviewFixtures.snapshot("fed")
        s.alive = true
        s.level = 3
        XCTAssertTrue(s.critical)
        s.level = 1
        XCTAssertFalse(s.critical)

        s.mood = "sleep"
        XCTAssertTrue(s.sleeping)
        s.mood = "nap"
        XCTAssertFalse(s.sleeping, "дрёма — не ночной сон, кнопка «Разбудить» остаётся")
        s.mood = "sleep"
        s.alive = false
        XCTAssertFalse(s.sleeping)
    }

    func testCriticalFixtureIsCritical() {
        let s = PreviewFixtures.snapshot("critical")
        XCTAssertTrue(s.critical)
        XCTAssertNotEqual(s.main, .none)
        XCTAssertFalse(PreviewFixtures.snapshot("fed").critical)
    }

    func testShortLine() {
        let short = "Хорошо мне"
        let long = String(repeating: "а", count: Presenter.shortLineMax + 1)
        XCTAssertEqual(Presenter.shortLine(short, island: "Ок"), short)
        XCTAssertEqual(Presenter.shortLine(long, island: "Ок"), "Ок")
        XCTAssertEqual(Presenter.shortLine(long, island: ""), long, "нет короткой — оставляем свою")

        var s = PreviewFixtures.snapshot("fed")
        s.line = long
        s.islandLine = "Ок"
        XCTAssertEqual(s.shortLine, "Ок")
    }

    func testNeedEmpty() {
        XCTAssertTrue(Presenter.needEmpty(0))
        XCTAssertTrue(Presenter.needEmpty(0.4))
        XCTAssertFalse(Presenter.needEmpty(1))
        XCTAssertFalse(Presenter.needEmpty(50))
    }

    // MARK: Siri и виджеты говорят одинаково

    func testSharedTitles() {
        XCTAssertEqual(Presenter.sleepTitle, IslandAct.sleep.title)
        XCTAssertEqual(Presenter.rescueTitle, "Спасти")
    }

    // MARK: каталог превью

    func testCatalogTimers() {
        let fed = PreviewFixtures.catalogSnapshot("fed")
        let tm = fed.timer
        XCTAssertNotNil(tm)
        XCTAssertEqual(tm?.title, "Испачкается")
        XCTAssertFalse(Presenter.timerIsLive(remaining: (tm?.end ?? 0) - fed.t), "у сытого — длинный таймер")

        let crit = PreviewFixtures.catalogSnapshot("critical")
        XCTAssertTrue(Presenter.timerIsLive(remaining: (crit.timer?.end ?? 0) - crit.t), "у критичного — живой отсчёт")
        XCTAssertEqual(PreviewFixtures.islandState("critical").timerNeed, "love")
        XCTAssertNil(PreviewFixtures.snapshot("fed").timer, "заглушка виджета без таймера")
    }

    // MARK: геометрия

    func testFaceStrokeScalesWithSide() {
        XCTAssertEqual(PetFaceView.strokeWidth(3, side: 100), 3, accuracy: 1e-9)
        XCTAssertEqual(PetFaceView.strokeWidth(2.2, side: 150), 3.3, accuracy: 1e-9)
        XCTAssertEqual(PetFaceView.strokeWidth(2.2, side: 24), 1, accuracy: 1e-9, "не тоньше 1 pt")
    }

    func testCircularRingFraction() {
        XCTAssertEqual(AccessoryCircularView.fraction(hearts: 2.5, max: 5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(AccessoryCircularView.fraction(hearts: 7, max: 5), 1, accuracy: 1e-9)
        XCTAssertEqual(AccessoryCircularView.fraction(hearts: 1, max: 0), 0, accuracy: 1e-9)
    }
}
