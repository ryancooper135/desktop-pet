// Волна 22: одно сообщение за раз (Shared/Hush.swift) и шерсть щенка в первой сессии (Onboarding.coatLine).

import XCTest
@testable import Pet
@preconcurrency import PetCore

final class HushTests: XCTestCase {
    private func act(_ kind: String, at t: Double, ok: Bool = true) -> SaveFile.LastAction {
        SaveFile.LastAction(kind: kind, source: .app, t: t, ok: ok, reason: nil)
    }

    private func hint(_ go: HintGo, detail: String) -> NeedHint {
        NeedHint(key: go.rawValue, go: go, title: "Погладить", detail: detail, icon: "hand.raised.fill",
                 urgent: false, then: nil)
    }

    // MARK: кто говорит

    func testSpeakerIsTheLoudestOne() {
        XCTAssertEqual(Hush.speaker([.tutor, .tip, .toast]), .toast)
        XCTAssertEqual(Hush.speaker([.tutor, .tip]), .tip)
        XCTAssertEqual(Hush.speaker([.tutor]), .tutor)
        XCTAssertNil(Hush.speaker([]))
    }

    // MARK: подсказка жеста

    /// ui-94-10: после ласки кнопкой «Только что гладил…» и «Четыре быстрых тапа…» висели вместе.
    func testTipWaitsForToast() {
        XCTAssertEqual(Hush.tipStep(offeredAt: 100, now: 101, toastUp: true, sceneClear: true), .wait)
        XCTAssertEqual(Hush.tipStep(offeredAt: 100, now: 104, toastUp: false, sceneClear: true), .show)
        XCTAssertEqual(Hush.tipStep(offeredAt: 100, now: 101, toastUp: false, sceneClear: false), .wait)
    }

    func testStaleTipIsDropped() {
        let late = 100 + Hush.tipStaleS + 1
        XCTAssertEqual(Hush.tipStep(offeredAt: 100, now: late, toastUp: false, sceneClear: true), .drop)
        XCTAssertEqual(Hush.tipStep(offeredAt: 100, now: late, toastUp: true, sceneClear: true), .drop)
        XCTAssertEqual(Hush.tipStep(offeredAt: 100, now: 100 + Hush.tipStaleS, toastUp: false, sceneClear: true), .show)
    }

    func testShownTipHidesUnderToast() {
        XCTAssertTrue(Hush.tipVisible(hasTip: true, toastUp: false))
        XCTAssertFalse(Hush.tipVisible(hasTip: true, toastUp: true))
        XCTAssertFalse(Hush.tipVisible(hasTip: false, toastUp: false))
    }

    // MARK: палец

    func testTutorYieldsToToastAndTip() {
        XCTAssertTrue(Hush.tutorVisible(wants: true, forced: false, busy: false, toastUp: false, tipUp: false))
        XCTAssertFalse(Hush.tutorVisible(wants: true, forced: false, busy: false, toastUp: true, tipUp: false))
        XCTAssertFalse(Hush.tutorVisible(wants: true, forced: false, busy: false, toastUp: false, tipUp: true))
        XCTAssertFalse(Hush.tutorVisible(wants: true, forced: true, busy: false, toastUp: true, tipUp: false))
        XCTAssertFalse(Hush.tutorVisible(wants: false, forced: false, busy: false, toastUp: false, tipUp: false))
    }

    /// ui-94-07: палец ходил по жующему Шибе. Пока идёт анимация — прячется, по тапу хозяина — нет.
    func testTutorHidesWhileBusyUnlessAsked() {
        XCTAssertFalse(Hush.tutorVisible(wants: true, forced: false, busy: true, toastUp: false, tipUp: false))
        XCTAssertTrue(Hush.tutorVisible(wants: true, forced: true, busy: true, toastUp: false, tipUp: false))
    }

    func testBusyByPose() {
        for p in [Pose.eating, .bath, .away, .sleep, .nap] {
            XCTAssertTrue(Hush.busy(pose: p, lastAction: nil, now: 0), "\(p)")
        }
        for p in [Pose.idle, .hungry, .lonely, .bored] {
            XCTAssertFalse(Hush.busy(pose: p, lastAction: nil, now: 0), "\(p)")
        }
    }

    /// «Поиграть» и «Погладить» дают позу happy/loved, которая бывает и сама по себе, — занятость по свежему действию.
    func testBusyByFreshActionThenComesBack() {
        for k in ["feed", "play", "pet", "bath", "walk", "cook", "item", "wake", "brush"] {
            XCTAssertTrue(Hush.busy(pose: .happy, lastAction: act(k, at: 100), now: 105), k)
            XCTAssertFalse(Hush.busy(pose: .happy, lastAction: act(k, at: 100), now: 100 + Hush.busyS), k)
        }
        XCTAssertFalse(Hush.busy(pose: .happy, lastAction: act("feed", at: 100, ok: false), now: 101))
        XCTAssertFalse(Hush.busy(pose: .happy, lastAction: act("steps", at: 100), now: 101))
        // Часы перевели назад: действие «из будущего» не держит палец.
        XCTAssertFalse(Hush.busy(pose: .idle, lastAction: act("feed", at: 200), now: 100))
    }

    /// Окно занятости — то же, что поза реакции в приложении (AppModel.reactionWindow, 12 с).
    func testBusyWindowMatchesReactionPose() {
        var f = SaveFile.fresh(now: 1_000_000)
        f.lastAction = act("feed", at: 1_000_000)
        let eating = Presenter.make(f, at: 1_000_000 + Hush.busyS - 1, reactionWindow: Hush.busyS)
        XCTAssertEqual(eating.pose, .eating)
        let after = Presenter.make(f, at: 1_000_000 + Hush.busyS, reactionWindow: Hush.busyS)
        XCTAssertNotEqual(after.pose, .eating)
        XCTAssertFalse(Hush.busy(pose: after.pose, lastAction: f.lastAction, now: 1_000_000 + Hush.busyS))
    }

    // MARK: плашка

    func testPlateDropsDetailThatTutorAlreadySays() {
        let tutor = Tips.petTutorText(name: "Шиба")
        let pet = hint(.pet, detail: NeedHints.how("pet"))
        XCTAssertEqual(NeedHints.how("pet"), tutor, "иначе правило «одна фраза» потеряет смысл")
        XCTAssertNil(Hush.plateDetail(pet, tutorShown: true, tutorText: tutor))
        XCTAssertEqual(Hush.plateDetail(pet, tutorShown: false, tutorText: tutor), tutor)
        let feed = hint(.feed, detail: "Хрустики бесплатно")
        XCTAssertEqual(Hush.plateDetail(feed, tutorShown: true, tutorText: tutor), "Хрустики бесплатно")
        XCTAssertNil(Hush.plateDetail(hint(.feed, detail: ""), tutorShown: false, tutorText: tutor))
    }

    // MARK: шерсть щенка

    /// Щенок «голый и рваный» нарочно: в первой сессии шкалы не говорят «колтуны — расчеши».
    func testPuppyCoatLineIsCalmInFirstSession() {
        for st in [CoatStage.matted, .shaggy] {
            let line = Onboarding.coatLine(st, ageS: 60)
            XCTAssertFalse(line.lowercased().contains("колтун"), line)
            XCTAssertFalse(line.contains("расчеши"), line)
            XCTAssertTrue(Onboarding.coatLine(st, ageS: Onboarding.coatGraceS).contains("расчеши"))
        }
        XCTAssertEqual(Onboarding.coatLine(.normal, ageS: 60), "Шерсть: обычный")
    }

    /// Новый щенок и правда «рваный» (Coat.newborn), а строчка шкал для него — без совета.
    func testFreshPetScalesLine() {
        let now = 1_000_000.0
        let f = SaveFile.fresh(now: now)
        let coat = Coat.look(f, now: now + 60)
        XCTAssertEqual(coat.stage, .matted)
        XCTAssertFalse(Onboarding.coatLine(coat.stage, ageS: 60).contains("колтуны"))
    }
}
