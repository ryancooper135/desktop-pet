// Волна 21: строка статуса под репликой говорит о той же шкале, что и плашка «что нужно сейчас», когда у этой шкалы
// есть свой таймер. Нет — как было: ближайшее событие прогноза.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let pT0: Double = 1_760_000_000

private func pFile(at t: Double, level: Double = 80, _ needs: [Need: Double] = [:]) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = needs[n] ?? level }
    f.lastSeenT = t
    return f
}

/// Полдень по часам хозяина (как PET_NOW=noon в UI-тестах).
private func pNoon() throws -> Double {
    let probe = SaveFile.fresh(now: pT0)
    var t = pT0
    while t < pT0 + 2 * 86400 {
        if PetEngine.localMin(t, PetRunner.owner(probe, at: t)) == 720 { return t }
        t += 60
    }
    throw XCTSkip("нет полудня")
}

/// Экран словами: плашка, таймер по-старому (ближайшее событие) и таймер, который покажут.
private struct Shown {
    let hint: NeedHint?
    let nearest: NeedTimer?
    let timer: NeedTimer?
    let events: [ForecastEvent]
    let t: Double

    init(_ f: SaveFile, at t: Double) {
        let snap = Presenter.make(f, at: t)
        let s = PetRunner.peek(f, at: t)
        let o = PetRunner.owner(f, at: t)
        self.t = t
        hint = NeedHints.pick(snap, file: f)
        nearest = Presenter.timer(s, Catalog.rules, o, at: t, upcoming: nil)
        timer = snap.timer
        events = ForecastTools.upcoming(s, at: t, horizonH: 12, owner: o)
    }

    func first(_ kind: ForecastEvent.Kind, _ key: String) -> ForecastEvent? {
        events.first { $0.t > t && $0.kind == kind && $0.key == key }
    }
}

final class PlateTimerTests: XCTestCase {

    // MARK: главный случай (ui-89): «Погладить» и «Заскучает через…»

    func testPetPlateTimerIsAboutLove() throws {
        let t = try pNoon()
        // Сид wants_pet: всё 80, ласки 10 — плашка «Погладить», ближайшее событие — игра опустится.
        let v = Shown(pFile(at: t, [.love: 10]), at: t)
        XCTAssertEqual(v.hint?.go, .pet)
        XCTAssertEqual(v.nearest?.title, "Заскучает", "проверка сценария: раньше всего — игра")
        let toska = try XCTUnwrap(v.first(.distress, "toska"), "тоска в пределах 12 ч")
        XCTAssertEqual(v.timer?.title, "Затоскует")
        XCTAssertEqual(v.timer?.end, toska.t)
        XCTAssertEqual(v.timer?.kind, "low")
    }

    func testFeedPlateTimerIsAboutFood() throws {
        let t = try pNoon()
        // Ядро хочет есть при 35 (ещё не голодный) — «Подкормить»; игра опустится раньше, но строка — про сытость.
        let v = Shown(pFile(at: t, [.food: 35, .fun: 33]), at: t)
        XCTAssertEqual(v.hint?.go, .feed)
        XCTAssertEqual(v.nearest?.title, "Заскучает")
        XCTAssertEqual(v.timer?.title, "Проголодается")
        XCTAssertEqual(v.timer?.end, v.first(.low, "food")?.t)
    }

    func testBathPlateTimerIsAboutClean() throws {
        let t = try pNoon()
        let v = Shown(pFile(at: t, [.clean: 31, .fun: 31, .food: 90]), at: t)
        XCTAssertEqual(v.hint?.go, .bath)
        XCTAssertEqual(v.nearest?.title, "Заскучает")
        XCTAssertEqual(v.timer?.title, "Испачкается")
    }

    // MARK: иначе — как было

    func testNoPlateKeepsNearest() throws {
        let t = try pNoon()
        // Свежий щенок днём: просить нечего, строка — ближайшее событие.
        let v = Shown(pFile(at: t, [.food: 70, .clean: 35, .energy: 80, .fun: 60, .love: 50, .walk: 50]), at: t)
        XCTAssertNil(v.hint)
        XCTAssertEqual(v.timer, v.nearest)
    }

    func testPlateNeedAlreadyNearestUnchanged() throws {
        let t = try pNoon()
        let v = Shown(pFile(at: t, [.love: 33, .fun: 32]), at: t)
        XCTAssertEqual(v.hint?.go, .play)
        XCTAssertEqual(v.timer, v.nearest)
    }

    func testOtherNeedsDistressNotHiddenByLow() throws {
        let t = try pNoon()
        // Сытость 2: «Совсем оголодает» через минуты. Ласка опустится позже — её low не перебивает чужую беду.
        let f = pFile(at: t, [.food: 2, .love: 35])
        let v = Shown(f, at: t)
        let first = try XCTUnwrap(ForecastTools.nextLow(v.events, after: t))
        XCTAssertEqual(first.kind, .distress)
        XCTAssertNil(Presenter.plateEvent(v.events, need: .love, at: t))
        XCTAssertEqual(v.timer, v.nearest, "плашка тут про еду или её нет — строка та же")
    }

    func testPlateEventIgnoresFarAndForeign() throws {
        let t = try pNoon()
        let v = Shown(pFile(at: t, [.love: 10]), at: t)
        // Ходьба и силы не дают своих событий low — плашке «Гулять» таймер не подбираем.
        XCTAssertNil(Presenter.plateEvent(v.events, need: .walk, at: t))
        XCTAssertNil(Presenter.plateEvent(v.events, need: .energy, at: t))
        // Шкала плашки и есть ближайшая — nil (оставить как есть).
        XCTAssertNil(Presenter.plateEvent(v.events, need: .fun, at: t))
    }

    // MARK: шкала плашки

    func testPlateNeed() {
        func h(_ key: String, _ go: HintGo) -> NeedHint {
            NeedHint(key: key, go: go, title: "", detail: "", icon: "", urgent: false, then: nil)
        }
        XCTAssertEqual(Presenter.plateNeed(h("food", .feed)), .food)
        XCTAssertEqual(Presenter.plateNeed(h("bath", .bath)), .clean)
        XCTAssertEqual(Presenter.plateNeed(h("play", .play)), .fun)
        XCTAssertEqual(Presenter.plateNeed(h("pet", .pet)), .love)
        // «Сначала подкормить → Гулять»: желание — прогулка, а плашка про сытость.
        XCTAssertEqual(Presenter.plateNeed(h("walk", .feed)), .food)
        // Откат «Погладить — через 3 мин»: кнопки нет, шкала — ласка.
        XCTAssertEqual(Presenter.plateNeed(h("pet", .none)), .love)
        XCTAssertNil(Presenter.plateNeed(h("sleep", .none)))
        XCTAssertNil(Presenter.plateNeed(h("walk", .walk)))
        XCTAssertEqual(Presenter.distressNeeds("toska"), [.love, .fun])
        XCTAssertEqual(Presenter.distressNeeds("starve"), [.food])
        XCTAssertEqual(Presenter.distressNeeds("dirty"), [.clean])
        XCTAssertEqual(Presenter.distressNeeds(nil), [])
    }
}
