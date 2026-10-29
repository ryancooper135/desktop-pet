// Волна 48 U: охота на баги на стыках волн 45–47 (виджет × островок, AskMemo, ведущий idle/возврат клипов).
// Каждый тест — найденный баг (DECISIONS.md, «Волна 48 U»). Гоняется и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000.
private let uT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

/// Пёс с закреплённым petId: всё по 90, энергия — energy.
private func uFile(energy: Double = 90, at t: Double = uT0) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = "w48u-pet"
    for n in Need.allCases { f.pet.needs[n] = 90 }
    f.pet.needs[.energy] = energy
    DogLevel.settle(&f, now: t)
    return f
}

/// Сегодня — ровно одна просьба kind со стартом start.
private func uForce(_ f: inout SaveFile, _ kind: String, start: Double) {
    DogAsks.settle(&f, now: start)
    f.asks.items = [DogAsk(start: start, kind: kind, coins: 10)]
}

final class Wave48SeamTests: XCTestCase {

    override func setUp() {
        super.setUp()
        DogAsks.enabled = true
        DailyTasks.enabled = true
    }

    override func tearDown() {
        Clock.zoneOverride = nil
        DogAsks.enabled = true
        DailyTasks.enabled = true
        super.tearDown()
    }

    // MARK: Баг 1 — виджет держал «просьбу» до 5 минут после того, как островок её убрал

    /// Пёс задремал посреди окна просьбы. Островок убирает просьбу в минуту дрёмы (hideAt, волна 47 S),
    /// а кадры виджета в окне шли только через 5 мин от старта — до следующего кадра на экране блокировки
    /// висело «Почеши за ушком? · ещё N мин» над спящим псом. Теперь кадр стоит ровно в минуту дрёмы.
    func testWidgetDropsAskAtIslandHideMinute() {
        var f = uFile(energy: 16)
        let start = uT0 - 600
        uForce(&f, "pet", start: start)
        let end = start + DogAskConfig.shared.window
        guard let hide = IslandFeed.ask(f, now: uT0)?.hideAt else { return XCTFail("островок знает минуту дрёмы") }
        XCTAssertGreaterThan(hide, uT0)
        XCTAssertLessThan(hide, end)

        let frames = IslandEvents.widget(f, now: uT0, asks: f.asks.items)
        let inWindow = frames.filter { $0.t < end }
        guard let firstGone = inWindow.first(where: { $0.ask == nil }) else {
            return XCTFail("виджет должен убрать просьбу с дремлющего пса")
        }
        XCTAssertEqual(firstGone.t, hide, "виджет убирает просьбу в ту же минуту, что и островок (+\(Int(firstGone.t - hide)) с)")
        for fr in inWindow where fr.t < hide {
            XCTAssertNotNil(fr.ask, "кадр +\(Int(fr.t - uT0)) с: пёс ещё не спит")
        }
    }

    /// Бодрый пёс: лишних кадров нет — сетка та же, что в волне 45 O.
    func testWidgetFramesUnchangedForAwakeDog() {
        var f = uFile()
        let start = uT0 - 600
        uForce(&f, "pet", start: start)
        let frames = IslandEvents.widget(f, now: uT0, asks: f.asks.items)
        let expected = IslandEvents.frameTimes(now: uT0, asks: f.asks.items, window: DogAskConfig.shared.window)
        XCTAssertEqual(frames.map(\.t), expected)
    }

    // MARK: Баг 2 — смерть посреди дела: пёс вставал и шёл домой, а уже потом падал

    /// Поза «убежал» посреди дела (или пути домой после «Поиграть»): раньше cutChore строил путь домой
    /// шагом на 2–5 с, тело при этом съезжало вбок (deathShift), а после обложки пёс замирал стоя.
    /// Смерть, как и в walk(instant:), — сразу, без пути домой.
    func testDeathNeverWalksHome() {
        XCTAssertFalse(DogIdle.walksHome(dying: true, walking: false, hidden: false, walkClip: true))
        XCTAssertTrue(DogIdle.walksHome(dying: false, walking: false, hidden: false, walkClip: true))
        // Прежние запреты на путь домой остаются.
        XCTAssertFalse(DogIdle.walksHome(dying: false, walking: true, hidden: false, walkClip: true))
        XCTAssertFalse(DogIdle.walksHome(dying: false, walking: false, hidden: true, walkClip: true))
        XCTAssertFalse(DogIdle.walksHome(dying: false, walking: false, hidden: false, walkClip: false))
    }
}
