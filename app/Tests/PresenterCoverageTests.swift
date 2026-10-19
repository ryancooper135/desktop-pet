// Presenter и ForecastTools: позы для всех настроений, tier, таймеры, главная кнопка, срок подписи,
// точки timeline и staleDate. Хозяин с поясом 0, чтобы время суток не зависело от машины CI.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let pT0: Double = 1_760_000_000          // 08:53 UTC — хозяин уже встал
private let pDay: Double = (pT0 / 86400).rounded(.down) * 86400

private func pOwner() -> Owner {
    let r = Catalog.rules
    return Owner(bedMin: r.bedMin, wakeMin: r.wakeMin, tzOffsetMin: 0)
}

private func pPet(_ needs: [Need: Double] = [:], at t: Double = pT0) -> PetState {
    var s = PetEngine.newPet(Catalog.rules, t: t)
    for (n, v) in needs { s.needs[n] = v }
    return s
}

private func pFull() -> [Need: Double] {
    var v: [Need: Double] = [:]
    for n in Need.allCases { v[n] = 100 }
    return v
}

private func pSnap(_ s: PetState, file: SaveFile? = nil, at t: Double = pT0) -> PetSnapshot {
    let f = file ?? SaveFile.fresh(now: s.t)
    return Presenter.make(file: f, pet: s, owner: pOwner(), at: t)
}

final class PresenterCoverageTests: XCTestCase {

    // MARK: поза

    func testPoseForEveryMood() {
        let expect: [Mood: Pose] = [
            .dead: .dead, .walking: .away, .critical: .critical, .bath: .bath, .sleep: .sleep, .nap: .nap,
            .hungry: .hungry, .smelly: .dirty, .dirty: .dirty, .tired: .tired, .bored: .bored,
            .wants_love: .lonely, .wants_walk: .bored, .sulky: .sulky, .ok: .idle,
        ]
        XCTAssertEqual(Set(expect.keys), Set(Mood.allCases), "новое настроение — допиши позу")
        for m in Mood.allCases {
            XCTAssertEqual(Presenter.pose(mood: m, reaction: nil, needs: [:]), expect[m], "\(m)")
        }
    }

    func testReactionsOverrideMood() {
        XCTAssertEqual(Presenter.pose(mood: .hungry, reaction: "feed", needs: [:]), .eating)
        XCTAssertEqual(Presenter.pose(mood: .critical, reaction: "item", needs: [:]), .eating)
        XCTAssertEqual(Presenter.pose(mood: .wants_love, reaction: "pet", needs: [:]), .loved)
        XCTAssertEqual(Presenter.pose(mood: .bored, reaction: "play", needs: [:]), .happy)
        XCTAssertEqual(Presenter.pose(mood: .nap, reaction: "wake", needs: [:]), .happy)
        // Без своей позы реакция не перебивает настроение.
        XCTAssertEqual(Presenter.pose(mood: .dirty, reaction: "bath", needs: [:]), .dirty)
        XCTAssertEqual(Presenter.pose(mood: .tired, reaction: "steps", needs: [:]), .tired)
    }

    func testHappyNeedsAllWatchedAt60() {
        let good: [Need: Double] = [.food: 60, .clean: 60, .fun: 60, .love: 60]
        XCTAssertEqual(Presenter.pose(mood: .ok, reaction: nil, needs: good), .happy)
        for n in [Need.food, .clean, .fun, .love] {
            var v = good
            v[n] = 59.9
            XCTAssertEqual(Presenter.pose(mood: .ok, reaction: nil, needs: v), .idle, "\(n) ниже 60")
            v[n] = nil
            XCTAssertEqual(Presenter.pose(mood: .ok, reaction: nil, needs: v), .idle, "нет \(n) — считаем 0")
        }
        // Энергия и прогулка на позу «доволен» не влияют.
        var extra = good
        extra[.energy] = 0
        extra[.walk] = 0
        XCTAssertEqual(Presenter.pose(mood: .ok, reaction: nil, needs: extra), .happy)
    }

    // MARK: tier

    func testTierBoundaries() {
        let o = Owner(bedMin: 1410, wakeMin: 450, tzOffsetMin: 0)
        func tier(_ m: Int) -> Int { Presenter.tier(pDay + Double(m) * 60, o) }
        XCTAssertEqual(tier(1410), 3, "в момент отбоя — последний час")
        XCTAssertEqual(tier(1350), 3)
        XCTAssertEqual(tier(1349), 2)
        XCTAssertEqual(tier(1230), 2)
        XCTAssertEqual(tier(1229), 1)
        XCTAssertEqual(tier(1411), 1, "после отбоя до следующего вечера далеко")
        XCTAssertEqual(tier(600), 1)

        let late = Owner(bedMin: 30, wakeMin: 540, tzOffsetMin: 0)
        XCTAssertEqual(Presenter.tier(pDay + 1430 * 60, late), 3, "отбой после полуночи")
        XCTAssertEqual(Presenter.tier(pDay + 1300 * 60, late), 2)
        // Пояс сдвигает местные минуты.
        let east = Owner(bedMin: 1410, wakeMin: 450, tzOffsetMin: 120)
        XCTAssertEqual(Presenter.tier(pDay + 1290 * 60, east), 3)
    }

    func testLevelTitle() {
        var s = pSnap(pPet())
        let titles = [0: "Всё хорошо", 1: "Просит", 2: "Плохо", 3: "Критично"]
        for (lvl, title) in titles {
            s.level = lvl
            XCTAssertEqual(s.levelTitle, title)
        }
        s.alive = false
        s.level = 3
        XCTAssertEqual(s.levelTitle, "Нет с нами")
    }

    // MARK: таймеры

    func testBathTimer() {
        let r = Catalog.rules
        var s = pPet(pFull())
        s.bathUntil = pT0 + 600
        let tm = Presenter.timer(s, r, pOwner(), at: pT0, upcoming: [])
        XCTAssertEqual(tm, NeedTimer(kind: "bath", start: pT0 + 600 - r.bathMinutes[0] * 60, end: pT0 + 600, title: "Моется"))
        if r.bathMinutes.first == 60 { XCTAssertEqual(tm?.start, pT0 - 3000) }

        let snap = pSnap(s)
        XCTAssertEqual(snap.main, .none, "пока моется — кнопки нет")
        XCTAssertEqual(snap.pose, .bath)
        XCTAssertNil(snap.main.action)

        // Уровень ванной вне таблицы — берём последний.
        s.home[.bath] = 10
        let top = Presenter.timer(s, r, pOwner(), at: pT0, upcoming: [])
        XCTAssertEqual(top?.start, pT0 + 600 - (r.bathMinutes.last ?? 0) * 60)
        s.home[.bath] = -3
        XCTAssertEqual(Presenter.timer(s, r, pOwner(), at: pT0, upcoming: [])?.start, tm?.start)
    }

    func testBathTimerNeverStartsAfterNow() {
        var s = pPet()
        s.bathUntil = pT0 + 24 * 3600    // длиннее любой ванны
        let tm = Presenter.timer(s, Catalog.rules, pOwner(), at: pT0, upcoming: [])
        XCTAssertEqual(tm?.start, pT0)
    }

    func testNapTimerAndExpired() {
        let r = Catalog.rules
        var s = pPet(pFull())
        s.napUntil = pT0 + 1200
        XCTAssertEqual(Presenter.timer(s, r, pOwner(), at: pT0, upcoming: []),
                       NeedTimer(kind: "nap", start: pT0, end: pT0 + 1200, title: "Дремлет"))

        s.napUntil = pT0 - 1
        XCTAssertNil(Presenter.timer(s, r, pOwner(), at: pT0, upcoming: []), "дрёма кончилась, событий нет")
        s.napUntil = nil
        s.bathUntil = pT0
        XCTAssertNil(Presenter.timer(s, r, pOwner(), at: pT0, upcoming: []), "ванна кончилась ровно сейчас")
    }

    func testDeadPetHasNoTimer() {
        var s = pPet()
        s.alive = false
        s.hearts = 0
        XCTAssertNil(Presenter.timer(s, Catalog.rules, pOwner(), at: pT0, upcoming: nil))
        let snap = pSnap(s)
        XCTAssertEqual(snap.main, .open)
        XCTAssertNil(snap.want)
        XCTAssertEqual(snap.levelTitle, "Нет с нами")
    }

    func testLowTimerMatchesNextLow() throws {
        let r = Catalog.rules
        let o = pOwner()
        let s = pPet([.food: 31])
        let ev = ForecastTools.upcoming(s, at: pT0, horizonH: 12, owner: o)
        let e = try XCTUnwrap(ForecastTools.nextLow(ev, after: pT0), "сытость 31 за 12 ч днём точно упадёт ниже порога")
        let tm = try XCTUnwrap(Presenter.timer(s, r, o, at: pT0, upcoming: nil))
        XCTAssertEqual(tm.kind, "low")
        XCTAssertEqual(tm.start, pT0)
        XCTAssertEqual(tm.end, e.t)
        XCTAssertEqual(tm.title, ForecastTools.title(e))
        XCTAssertLessThanOrEqual(tm.end - tm.start, 12 * 3600)
        // Переданный прогноз важнее своего.
        XCTAssertEqual(Presenter.timer(s, r, o, at: pT0, upcoming: ev), tm)
    }

    // MARK: главная кнопка

    func testMainActionFollowsRescue() {
        XCTAssertEqual(pSnap(pPet([.food: 0])).main, .feed)
        XCTAssertEqual(pSnap(pPet([.clean: 5])).main, .bath)
        XCTAssertEqual(pSnap(pPet(pFull())).main, .pet, "всё хорошо — просто погладить")

        var napping = pPet(pFull())
        napping.napUntil = pT0 + 1800
        XCTAssertEqual(pSnap(napping).main, .wake)
    }

    func testMainActionTitlesAndActions() {
        for m in MainAct.allCases {
            XCTAssertFalse(m.title.isEmpty)
            XCTAssertFalse(m.icon.isEmpty)
        }
        XCTAssertEqual(MainAct.feed.action, .feed(Catalog.mainFood))
        XCTAssertEqual(MainAct.heal.action, .item(Catalog.healItem))
        XCTAssertNil(MainAct.open.action)
        XCTAssertNil(MainAct.none.action)
        // Что ответит «Главное действие», когда кнопки нет (логика IntentBridge.runMain).
        func reason(alive: Bool) -> String { alive ? "bathing" : "dead" }
        XCTAssertEqual(RefuseText.text(reason(alive: true)), "Сначала домоемся")
        XCTAssertEqual(RefuseText.text(reason(alive: false)), "Шибы больше нет")
    }

    func testMainActionAppliesThroughRunner() throws {
        var f = SaveFile.fresh(now: pT0)
        f.owner = pOwner()
        f.pet.needs[.food] = 0
        let snap = Presenter.make(file: f, pet: f.pet, owner: f.owner, at: pT0)
        let a = try XCTUnwrap(snap.main.action)
        let out = PetRunner.apply(a, source: .shortcut, to: &f, now: pT0)
        XCTAssertTrue(out.ok, "главная кнопка не должна упираться в отказ: \(out.reason ?? "")")
        XCTAssertGreaterThan(f.pet.needs[.food] ?? 0, 0)
        XCTAssertEqual(f.lastAction?.source, .shortcut)
    }

    // MARK: подпись, реплики, желание

    func testBuildDaysLeft() {
        let s = pPet()
        var f = SaveFile.fresh(now: pT0)
        XCTAssertNil(pSnap(s, file: f).buildDaysLeft)
        f.build = SaveFile.BuildInfo(expiresT: pT0 + 2.5 * 86400, seenT: pT0)
        XCTAssertEqual(pSnap(s, file: f).buildDaysLeft, 3, "неполный день считаем целым")
        f.build = SaveFile.BuildInfo(expiresT: pT0 + 86400, seenT: pT0)
        XCTAssertEqual(pSnap(s, file: f).buildDaysLeft, 1)
        f.build = SaveFile.BuildInfo(expiresT: pT0 - 3600, seenT: pT0)
        XCTAssertEqual(pSnap(s, file: f).buildDaysLeft, 0)
    }

    func testLinesFitLimits() {
        var states: [PetState] = [pPet(), pPet(pFull()), pPet([.food: 0]), pPet([.clean: 5]), pPet([.fun: 10, .love: 10])]
        var dead = pPet()
        dead.alive = false
        dead.hearts = 0
        states.append(dead)
        for s in states {
            for h in stride(from: 0.0, to: 24, by: 3) {
                let t = pT0 + h * 3600
                var st = s
                st.t = t
                let snap = pSnap(st, at: t)
                XCTAssertLessThanOrEqual(snap.line.count, LineLimit.widget, snap.line)
                XCTAssertLessThanOrEqual(snap.islandLine.count, LineLimit.island, snap.islandLine)
                XCTAssertFalse(snap.line.isEmpty)
            }
        }
    }

    func testWantMatchesCoreWants() {
        let r = Catalog.rules
        let o = pOwner()
        for s in [pPet(), pPet(pFull()), pPet([.food: 5]), pPet([.love: 15]), pPet([.clean: 20, .fun: 20])] {
            let snap = pSnap(s)
            let w = PetEngine.wants(s, r, o, now: pT0).first
            if let w, w.urgent || w.strength >= 0.25 {
                XCTAssertEqual(snap.want, w.key.rawValue)
                XCTAssertEqual(snap.urgent, w.urgent)
                XCTAssertNotNil(snap.wantText)
            } else {
                XCTAssertNil(snap.want)
                XCTAssertFalse(snap.urgent)
                XCTAssertNil(snap.wantText)
            }
        }
    }

    func testReactionWindow() {
        var f = SaveFile.fresh(now: pT0)
        f.owner = pOwner()
        f.pet.needs[.food] = 10
        f.lastAction = SaveFile.LastAction(kind: "feed", source: .widget, t: pT0 - 30, ok: true, reason: nil)
        XCTAssertEqual(Presenter.make(file: f, pet: f.pet, owner: f.owner, at: pT0).pose, .eating)
        XCTAssertNotEqual(Presenter.make(file: f, pet: f.pet, owner: f.owner, at: pT0, reactionWindow: 20).pose, .eating,
                          "окно приложения короче — реакция уже прошла")
        f.lastAction = SaveFile.LastAction(kind: "feed", source: .widget, t: pT0 - 30, ok: false, reason: "cooldown")
        XCTAssertNotEqual(Presenter.make(file: f, pet: f.pet, owner: f.owner, at: pT0).pose, .eating, "отказ — не реакция")
        f.lastAction = SaveFile.LastAction(kind: "feed", source: .widget, t: pT0 + 30, ok: true, reason: nil)
        XCTAssertNotEqual(Presenter.make(file: f, pet: f.pet, owner: f.owner, at: pT0).pose, .eating, "действие из будущего")
    }
}

final class ForecastToolsCoverageTests: XCTestCase {

    func testTimelineShape() {
        var f = SaveFile.fresh(now: pT0)
        f.pet.bathUntil = pT0 + 1000
        f.lastAction = SaveFile.LastAction(kind: "pet", source: .app, t: pT0 - 30, ok: true, reason: nil)
        let pts = ForecastTools.timeline(f, now: pT0, tzOffsetMin: 0).map(\.t)

        XCTAssertEqual(pts.first, pT0)
        XCTAssertLessThanOrEqual(pts.count, 64)
        XCTAssertLessThanOrEqual(pts.last ?? 0, pT0 + 86400 + 1)
        for (a, b) in zip(pts, pts.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b - a, 60, "точки ближе минуты склеены")
        }
        XCTAssertTrue(pts.contains { abs($0 - (pT0 - 30 + Presenter.reactionWindow + 1)) < 60 }, "есть точка на конце реакции")
    }

    func testTimelineForDeadPet() {
        var f = SaveFile.fresh(now: pT0)
        f.pet.alive = false
        let tl = ForecastTools.timeline(f, now: pT0, tzOffsetMin: 0)
        XCTAssertEqual(tl.count, 1, "после смерти точек нет")
        XCTAssertEqual(tl.first?.alive, false)
    }

    func testStaleDate() {
        var s = pPet()
        func stale(_ ev: [ForecastEvent] = [], startedT: Double? = nil) -> Double {
            ForecastTools.staleDate(s, events: ev, now: pT0, startedT: startedT).timeIntervalSince1970
        }
        XCTAssertEqual(stale(), pT0 + 8 * 3600)
        XCTAssertEqual(stale(startedT: pT0 - 7 * 3600), pT0 + 3600, "остров живёт 8 ч от старта")
        s.bathUntil = pT0 + 600
        XCTAssertEqual(stale(), pT0 + 600)
        s.bathUntil = pT0 - 600
        XCTAssertEqual(stale(), pT0 + 8 * 3600, "прошедшая ванна не в счёт")

        s.bathUntil = nil
        let ev = ForecastTools.upcoming(s, at: pT0, horizonH: 24, owner: pOwner())
        let firstAfter = ev.first { $0.t > pT0 }?.t
        XCTAssertEqual(stale(ev), min(pT0 + 8 * 3600, firstAfter ?? .infinity))
    }

    func testTitlesOnRealForecast() throws {
        let ev = ForecastTools.upcoming(pPet(), at: pT0, horizonH: 96, owner: pOwner())
        let death = try XCTUnwrap(ev.first { $0.kind == .death }, "брошенный щенок за 4 дня не выживает")
        XCTAssertEqual(ForecastTools.title(death), "Может не дождаться")
        let lowFood = try XCTUnwrap(ev.first { $0.kind == .low && $0.key == "food" })
        XCTAssertEqual(ForecastTools.title(lowFood), "Проголодается")
        for e in ev where e.kind == .heart || e.kind == .level {
            XCTAssertEqual(ForecastTools.title(e), "Попросит")
        }
        for e in ev where e.kind == .last_chance {
            XCTAssertEqual(ForecastTools.title(e), "Последний шанс")
        }
        for e in ev where e.kind == .low || e.kind == .distress {
            XCTAssertFalse(ForecastTools.title(e).isEmpty)
        }
    }

    func testNextLowEdges() throws {
        XCTAssertNil(ForecastTools.nextLow([], after: pT0))
        let ev = ForecastTools.upcoming(pPet(), at: pT0, horizonH: 96, owner: pOwner())
        let first = try XCTUnwrap(ForecastTools.nextLow(ev, after: pT0))
        XCTAssertTrue([.low, .distress, .last_chance, .death].contains(first.kind))
        XCTAssertGreaterThan(first.t, pT0)
        XCTAssertNil(ev.first { $0.t > pT0 && $0.t < first.t && [.low, .distress, .last_chance, .death].contains($0.kind) },
                     "раньше нет подходящих событий")
        XCTAssertNil(ForecastTools.nextLow(ev, after: ev.map(\.t).max() ?? pT0), "после последнего — пусто")
        if let next = ForecastTools.nextLow(ev, after: first.t) {
            XCTAssertGreaterThan(next.t, first.t, "строго после")
        }
    }

    // MARK: тире

    func testKeepDashGluesDashToPreviousWord() {
        XCTAssertEqual(Presenter.keepDash("Не помог — умрёт"), "Не помог\u{00A0}— умрёт")
        XCTAssertEqual(Presenter.keepDash("а — б — в"), "а\u{00A0}— б\u{00A0}— в", "все тире, не только первое")
        XCTAssertEqual(Presenter.keepDash("без тире"), "без тире")
        XCTAssertEqual(Presenter.keepDash("—сразу"), "—сразу", "без пробела перед тире — не трогаем")
        XCTAssertEqual(Presenter.keepDash("что-нибудь"), "что-нибудь", "дефис не тире")
    }

    func testKeepUnitsGluesNumberToUnit() {
        XCTAssertEqual(Presenter.keepUnits("около 20 ч, потом ещё 5 мин"), "около 20\u{00A0}ч, потом ещё 5\u{00A0}мин")
        XCTAssertEqual(Presenter.keepUnits("через 2 дн."), "через 2\u{00A0}дн.")
        XCTAssertEqual(Presenter.keepUnits("9 ч 25 мин"), "9\u{00A0}ч 25\u{00A0}мин", "между «ч» и следующим числом перенос можно")
        XCTAssertEqual(Presenter.keepUnits("5 часов и 3 часа"), "5 часов и 3 часа", "полные слова не трогаем")
        XCTAssertEqual(Presenter.keepUnits("где 2 машины"), "где 2 машины", "«м» только отдельным словом")
        XCTAssertEqual(Presenter.keepUnits("ч 5"), "ч 5")
        XCTAssertEqual(Presenter.keepUnits(""), "")
    }

    func testTypesetDoesDashAndUnits() {
        XCTAssertEqual(Presenter.typeset("Продержится около 20 ч — потом всё"), "Продержится около 20\u{00A0}ч\u{00A0}— потом всё")
    }

    func testKeepHyphensGluesWordParts() {
        XCTAssertEqual(Presenter.keepHyphens("Начало чего-то хорошего"), "Начало чего-\u{2060}то хорошего")
        XCTAssertEqual(Presenter.keepHyphens("кто-то где-нибудь"), "кто-\u{2060}то где-\u{2060}нибудь", "все дефисы")
        XCTAssertEqual(Presenter.keepHyphens("1-3 часа"), "1-3 часа", "между цифрами не трогаем")
        XCTAssertEqual(Presenter.keepHyphens("-то"), "-то", "дефис в начале строки не трогаем")
        XCTAssertEqual(Presenter.keepHyphens("а — б"), "а — б", "тире не трогаем")
        XCTAssertEqual(Presenter.keepHyphens(""), "")
    }

    /// Волна 15: сердечки для VoiceOver — как нарисованы (дробь вниз до половинки), без «0» у живого.
    func testHeartsSpokenMatchesDrawing() {
        XCTAssertEqual(Presenter.heartsSpoken(5, of: 5), "5 из 5")
        XCTAssertEqual(Presenter.heartsSpoken(3, of: 5), "3 из 5")
        XCTAssertEqual(Presenter.heartsSpoken(2.5, of: 5), "2 с половиной из 5")
        XCTAssertEqual(Presenter.heartsSpoken(2.9, of: 5), "2 с половиной из 5", "нарисовано 2,5 — так и читаем")
        XCTAssertEqual(Presenter.heartsSpoken(3.2, of: 5), "3 из 5")
        XCTAssertEqual(Presenter.heartsSpoken(0.6, of: 5), "половинка из 5")
        XCTAssertEqual(Presenter.heartsSpoken(0.2, of: 5), "меньше половинки из 5", "живой — не ноль")
        XCTAssertEqual(Presenter.heartsSpoken(0, of: 5), "0 из 5")
        XCTAssertEqual(Presenter.heartsSpoken(7, of: 6), "6 из 6", "больше максимума не бывает")
    }
}
