// Волна 25: свежий взгляд (RESEARCH/12-fresh-eyes.md). Мелкие правки по снимкам глазами новичка:
// «Просит» в шапке — чего; лист шкал — то же событие, что строка статуса; без тоста-повтора плашки у «Гулять»;
// ссылка pet:// поверх открытого листа; защёлка камеры открыток; тексты.

import XCTest
@testable import Pet
@preconcurrency import PetCore

private let fT0: Double = 1_760_000_000

private func fFile(at t: Double, _ needs: [Need: Double] = [:]) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = needs[n] ?? 80 }
    f.lastSeenT = t
    return f
}

/// Полдень по часам хозяина (как PET_NOW=noon в UI-тестах).
private func fNoon() throws -> Double {
    let probe = SaveFile.fresh(now: fT0)
    var t = fT0
    while t < fT0 + 2 * 86400 {
        if PetEngine.localMin(t, PetRunner.owner(probe, at: t)) == 720 { return t }
        t += 60
    }
    throw XCTSkip("нет полудня")
}

final class FreshEyesTests: XCTestCase {

    // MARK: «Просит» — чего

    func testAskTitleNamesTheLowestWatchNeed() {
        let warn = Catalog.rules.warnLow
        XCTAssertEqual(Presenter.askTitle(needs: [.food: 10, .love: 20, .fun: 80, .clean: 80], warnLow: warn), "Просит есть")
        XCTAssertEqual(Presenter.askTitle(needs: [.food: 80, .love: 10, .fun: 80, .clean: 80], warnLow: warn), "Просит ласки")
        XCTAssertEqual(Presenter.askTitle(needs: [.food: 80, .love: 80, .fun: 5, .clean: 25], warnLow: warn), "Просит поиграть")
        XCTAssertEqual(Presenter.askTitle(needs: [.food: 80, .love: 80, .fun: 80, .clean: 12], warnLow: warn), "Просит помыть")
        // Энергия и прогулка — не шкалы «просит» (уровень 1 ядро считает по food/clean/fun/love).
        XCTAssertEqual(Presenter.askTitle(needs: [.energy: 1, .walk: 0, .food: 80], warnLow: warn), "Просит")
    }

    /// Шапка (ui-89): сид wants_pet — ласки 10 — «Просит ласки», а не голое «Просит».
    func testHeaderSaysWhatIsWanted() throws {
        let t = try fNoon()
        let snap = Presenter.make(fFile(at: t, [.love: 10]), at: t)
        XCTAssertEqual(snap.level, 1)
        XCTAssertEqual(snap.levelTitle, "Просит ласки")
    }

    func testAskWordsFitTheHeader() {
        // Карточка шапки узкая (lineLimit 1, ужимается до 0.7): слова короткие.
        for (_, w) in Presenter.askWords {
            XCTAssertTrue(w.hasPrefix("Просит "), w)
            XCTAssertLessThanOrEqual(w.count, 15, w)
        }
    }

    // MARK: лист шкал и строка статуса — про одно событие

    /// ui-89: строка «Затоскует через 11 ч 40 мин», а лист шкал — «Заскучает в 20:21». Теперь лист — «Затоскует в …».
    func testNeedsSheetMatchesStatusLine() throws {
        let t = try fNoon()
        let f = fFile(at: t, [.love: 10])
        let snap = Presenter.make(f, at: t)
        let tm = try XCTUnwrap(snap.timer)
        XCTAssertEqual(tm.title, "Затоскует")
        let events = ForecastTools.upcoming(f, at: t, horizonH: 24)
        let nearest = ForecastTools.nextLow(events, after: t)
        let line = Presenter.sheetNext(timer: snap.timer, event: nearest, at: t)
        XCTAssertEqual(line, "Затоскует в \(Clock.hm(tm.end))")
        XCTAssertNotEqual(nearest.map { ForecastTools.title($0) }, "Затоскует", "проверка сценария: ближайшее — другое")
    }

    func testNeedsSheetFallsBackToForecast() throws {
        let t = try fNoon()
        let f = fFile(at: t)
        let events = ForecastTools.upcoming(f, at: t, horizonH: 24)
        let e = try XCTUnwrap(ForecastTools.nextLow(events, after: t))
        let want = "\(ForecastTools.title(e)) в \(Clock.hm(e.t))"
        XCTAssertEqual(Presenter.sheetNext(timer: nil, event: e, at: t), want)
        // Таймер не «low» (ванна, сон) или уже прошёл — как раньше, по прогнозу.
        let bath = NeedTimer(kind: "bath", start: t, end: t + 60, title: "Моется")
        XCTAssertEqual(Presenter.sheetNext(timer: bath, event: e, at: t), want)
        let stale = NeedTimer(kind: "low", start: t - 120, end: t - 60, title: "Заскучает")
        XCTAssertEqual(Presenter.sheetNext(timer: stale, event: e, at: t), want)
        XCTAssertEqual(Presenter.sheetNext(timer: nil, event: nil, at: t), "Сутки без забот")
    }

    // MARK: «Гулять» с замком — без тоста-повтора плашки

    /// ui-88-walk-locked: сид walk_blocked — плашка «Сначала … → Гулять», тост повторял её. Волна 32: сытость с 30
    /// уже пускает, сид держит чистотой 29 < 30 — плашка «Сначала помыть → Гулять».
    func testLockedWalkToastSilentWhenPlateSaysIt() throws {
        let t = try fNoon()
        let f = fFile(at: t, [.walk: 0, .clean: 29])
        let gate = WalkPlan.gate(f, at: t)
        XCTAssertFalse(gate.ok)
        XCTAssertEqual(gate.reason, "not_ready")
        let plate = try XCTUnwrap(NeedHints.pick(Presenter.make(f, at: t), file: f))
        XCTAssertEqual(plate.key, "walk")
        XCTAssertNil(Hush.walkToast(gate: gate, plate: plate))
        // Плашки нет (или она о другом) — тост ворот, как было.
        XCTAssertEqual(Hush.walkToast(gate: gate, plate: nil), gate.toast)
        let other = NeedHint(key: "pet", go: .pet, title: "Погладить", detail: "", icon: "hand.raised.fill",
                             urgent: false, then: nil)
        XCTAssertEqual(Hush.walkToast(gate: gate, plate: other), gate.toast)
    }

    func testWalkToastAwayAndOpen() {
        let away = WalkGate(ok: false, reason: "away", hint: "вернётся в 14:20", toast: "Гуляет, вернётся в 14:20", until: 1)
        let plate = NeedHint(key: "walk", go: .none, title: "Гулять — позже", detail: "x", icon: "figure.walk",
                             urgent: false, then: nil)
        XCTAssertEqual(Hush.walkToast(gate: away, plate: plate), away.toast, "гуляет — тост «когда вернётся» нужен")
        let open = WalkGate(ok: true, reason: nil, hint: "1–3 ч", toast: "", until: nil)
        XCTAssertNil(Hush.walkToast(gate: open, plate: nil))
    }

    // MARK: ссылка pet:// поверх открытого листа

    func testDeepLinkGoesStraightWhenNothingOpen() {
        for h in DeepLink.routes { XCTAssertEqual(DeepLink.step(target: h, open: []), .go, h) }
        XCTAssertEqual(DeepLink.step(target: "home", open: ["album", "needs"]), .go, "home и так закрывает всё")
        XCTAssertEqual(DeepLink.step(target: nil, open: ["album"]), .go)
        XCTAssertEqual(DeepLink.step(target: "nope", open: ["album"]), .go)
    }

    func testDeepLinkClosesForeignSheetFirst() {
        XCTAssertEqual(DeepLink.step(target: "needs", open: ["album"]), .closeFirst)
        XCTAssertEqual(DeepLink.step(target: "catch", open: ["settings"]), .closeFirst)
        XCTAssertEqual(DeepLink.step(target: "album", open: ["postcard"]), .closeFirst)
        XCTAssertEqual(DeepLink.step(target: "brush", open: ["tricks"]), .closeFirst)
        XCTAssertEqual(DeepLink.step(target: "capsule", open: ["capsule", "shop"]), .closeFirst)
    }

    func testDeepLinkKeepsSheetsOnTheWay() {
        XCTAssertEqual(DeepLink.step(target: "needs", open: ["needs"]), .go)
        XCTAssertEqual(DeepLink.step(target: "shop", open: ["capsule"]), .go, "лавка — лист в автомате")
        XCTAssertEqual(DeepLink.step(target: "kitchen", open: ["house"]), .go, "кухня — лист в «Доме»")
        XCTAssertEqual(DeepLink.step(target: "characters", open: ["settings"]), .go)
        XCTAssertEqual(DeepLink.step(target: "shop", open: ["house"]), .closeFirst)
        XCTAssertGreaterThan(DeepLink.closeDelay, 0.4)
        XCTAssertLessThan(DeepLink.closeDelay, 2)
    }

    // MARK: защёлка камеры открыток

    func testFirstWinsOnlyOnce() {
        let once = FirstWins()
        XCTAssertTrue(once.claim())
        XCTAssertFalse(once.claim())
        XCTAssertFalse(once.claim())
    }

    func testFirstWinsAcrossThreads() {
        let once = FirstWins()
        let wins = FreshCounter()
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            if once.claim() { wins.bump() }
        }
        XCTAssertEqual(wins.value, 1)
    }

    // MARK: тексты и место пальца

    func testRulesHeartsLineReadsNaturally() throws {
        let t = try fNoon()
        let f = fFile(at: t)
        let all = Guides.rulesItems(name: PetNames.shiba, owner: PetRunner.owner(f, at: t)).map(\.text).joined(separator: "\n")
        XCTAssertTrue(all.contains("Сердечки не падают ниже одного."))
        XCTAssertFalse(all.contains("Ниже одного сердечки"))
    }

    func testTutorPathSitsAboveCenter() {
        // ui-89: на 0.5 дорожка шла по животу. Спина — выше центра, но не у шапки.
        XCTAssertLessThan(Tips.tutorY, 0.5)
        XCTAssertGreaterThan(Tips.tutorY, 0.35)
    }
}

private final class FreshCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func bump() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}
