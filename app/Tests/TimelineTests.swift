// Timeline виджета без телефона: ForecastTools.timeline — чистая функция от файла и момента,
// пояс закреплён (UTC), petId фиксирован, так что реплики и точки одинаковы при каждом запуске.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// 2026-09-21 14:13:20 UTC — день, до отбоя хозяина (23:30) ещё 9 ч.
private let t0: Double = 1_790_000_000
private let hour: Double = 3600

private func file(_ needs: [Need: Double] = [:], hearts: Double? = nil, at t: Double = t0) -> SaveFile {
    let r = Catalog.rules
    var f = SaveFile(petId: "timeline-test", deviceId: "timeline-test", createdT: t - 86400,
                     owner: PetEngine.defaultOwner(r, tzOffsetMin: 0), pet: PetEngine.newPet(r, t: t))
    for (k, v) in needs { f.pet.needs[k] = v }
    if let hearts { f.pet.hearts = hearts }
    f.seen = f.pet
    f.lastSeenT = t
    return f
}

private func timeline(_ f: SaveFile, now: Double = t0) -> [PetSnapshot] {
    ForecastTools.timeline(f, now: now, tzOffsetMin: 0)
}

private let hungryNeeds: [Need: Double] = [.food: 30, .clean: 70, .energy: 60, .fun: 55, .love: 60]
private let criticalNeeds: [Need: Double] = [.food: 0, .clean: 15, .energy: 20, .fun: 10, .love: 10]

final class TimelineTests: XCTestCase {

    // MARK: форма и бюджет WidgetKit

    func testShapeAcrossDay() {
        for needs in [[:], hungryNeeds] {
            for h in 0..<24 {
                let now = t0 + Double(h) * hour
                let tl = timeline(file(needs, at: t0), now: now)
                let tag = "старт +\(h) ч, \(needs.isEmpty ? "свежий" : "голодный")"
                XCTAssertFalse(tl.isEmpty, tag)
                guard let first = tl.first, let last = tl.last else { continue }
                XCTAssertEqual(first.t, now, "первая точка — сейчас, \(tag)")
                XCTAssertLessThanOrEqual(tl.count, ForecastTools.Budget.maxEntries, tag)
                XCTAssertLessThanOrEqual(last.t, now + ForecastTools.Budget.horizonH * hour, tag)
                for (a, b) in zip(tl, tl.dropFirst()) {
                    XCTAssertGreaterThan(b.t, a.t, "точки строго по возрастанию, \(tag)")
                    // Склейка точек ближе minGap сдвигает точку позже, на меньше минуты.
                    XCTAssertLessThanOrEqual(b.t - a.t, ForecastTools.Budget.nightStep + ForecastTools.Budget.minGap, "дыра больше 2 ч, \(tag)")
                }
                if last.alive {
                    XCTAssertGreaterThanOrEqual(last.t, now + 12 * hour, "живому хватает на 12 ч, \(tag)")
                }
                let reload = ForecastTools.reloadT(tl, now: now)
                XCTAssertGreaterThanOrEqual(reload, now + ForecastTools.Budget.minReload, tag)
                XCTAssertLessThanOrEqual(reload, now + ForecastTools.Budget.reloadH * hour, tag)
            }
        }
    }

    func testDaytimeEvery30Minutes() {
        // С 14:13 до 22:13 питомец не спит: точки не реже чем раз в 30 минут.
        let tl = timeline(file())
        for (a, b) in zip(tl, tl.dropFirst()) where b.t <= t0 + 8 * hour {
            XCTAssertLessThanOrEqual(b.t - a.t, ForecastTools.Budget.nearStep + ForecastTools.Budget.minGap)
        }
    }

    // MARK: точные моменты смены позы

    func testPoseChangesAtExactMinute() {
        let r = Catalog.rules
        for needs in [[:], hungryNeeds, criticalNeeds] {
            let f = file(needs, hearts: needs == criticalNeeds ? 1 : nil)
            let o = f.owner
            let tl = timeline(f)
            for (a, b) in zip(tl, tl.dropFirst()) where a.pose != b.pose && b.t - 120 > a.t {
                // За 2 минуты до точки смены картинка ещё прежняя: точка стоит в минуту смены, а не на сетке.
                let t = b.t - 120
                let s = PetEngine.advance(f.pet, r, o, t)
                let before = Presenter.make(file: f, pet: s, owner: o, at: t)
                XCTAssertEqual(before.pose, a.pose, "\(a.pose) → \(b.pose) в \(b.t - t0) с")
            }
        }
    }

    func testSleepWindow() {
        let r = Catalog.rules
        let f = file()
        let tl = timeline(f)
        guard let i = tl.firstIndex(where: { $0.pose == .sleep }) else {
            return XCTFail("ночью питомец спит — в timeline должен быть сон")
        }
        let fall = tl[i]
        XCTAssertTrue(PetEngine.petNight(fall.t, r, f.owner), "уснул ночью")
        XCTAssertFalse(PetEngine.petNight(fall.t - 300, r, f.owner), "точка засыпания — в начале ночи, а не на сетке")

        guard let j = tl[i...].firstIndex(where: { $0.pose != .sleep }) else {
            return XCTFail("утром питомец просыпается")
        }
        let wake = tl[j]
        XCTAssertTrue(PetEngine.petNight(wake.t - 300, r, f.owner), "проснулся сразу после конца ночи")

        // Ночью точек мало: сон не меняется, хватает раза в 2 ч и событий прогноза.
        let night = tl[i..<j]
        XCTAssertLessThanOrEqual(night.count, 8)
        XCTAssertLessThan(Double(night.count), (wake.t - fall.t) / ForecastTools.Budget.nearStep)
    }

    // MARK: нужды и эскалация

    func testHungryEscalates() {
        let tl = timeline(file(hungryNeeds))
        guard let first = tl.first, let last = tl.last else { return XCTFail("пустой timeline") }
        let hungry = tl.filter { $0.pose == .hungry }
        XCTAssertFalse(hungry.isEmpty, "при еде 30 питомец проголодается")
        let food = Lines.shared.thought("food")
        for s in hungry {
            XCTAssertEqual(s.want, "food")
            XCTAssertEqual(s.wantText, food.text)
        }
        XCTAssertLessThan(last.needs[.food] ?? 100, first.needs[.food] ?? 0, "без хозяина шкала падает")
        XCTAssertGreaterThan(tl.map(\.level).max() ?? 0, first.level, "чем дольше ждёт, тем тревожнее")
        XCTAssertTrue(tl.contains { $0.timer != nil }, "таймер «проголодается через…» есть")
    }

    func testReactionEndsOnTime() {
        var f = file()
        f.lastAction = SaveFile.LastAction(kind: "feed", source: .app, t: t0 - 30, ok: true, reason: nil)
        let tl = timeline(f)
        XCTAssertGreaterThan(tl.count, 1)
        guard tl.count > 1 else { return }
        XCTAssertEqual(tl[0].pose, .eating)
        let end = t0 - 30 + Presenter.reactionWindow
        XCTAssertGreaterThanOrEqual(tl[1].t, end, "реакция не обрывается раньше")
        XCTAssertLessThanOrEqual(tl[1].t, end + ForecastTools.Budget.minGap, "и не висит 30 минут до сетки")
        XCTAssertNotEqual(tl[1].pose, .eating)
    }

    // MARK: смерть

    func testStopsAfterDeath() {
        let now = t0
        let tl = timeline(file(criticalNeeds, hearts: 1), now: now)
        guard let last = tl.last else { return XCTFail("пустой timeline") }
        XCTAssertFalse(last.alive, "критичный без помощи не доживает до конца горизонта")
        XCTAssertEqual(last.pose, .dead)
        XCTAssertEqual(tl.filter { !$0.alive }.count, 1, "после смерти точек нет")
        XCTAssertTrue(tl.dropLast().allSatisfy { $0.alive })
        XCTAssertEqual(ForecastTools.reloadT(tl, now: now), now + ForecastTools.Budget.reloadH * hour)
    }

    // MARK: детерминизм и цена

    func testDeterministic() {
        let f = file(hungryNeeds)
        XCTAssertEqual(timeline(f), timeline(f))
    }

    func testPerformance24h() {
        let f = file(hungryNeeds)
        measure { _ = timeline(f) }
    }
}
