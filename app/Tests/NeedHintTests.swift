// Волна 18: плашка «что нужно сейчас» (NeedHints.pick), бейджи кнопок (NeedHints.gates), WalkGate.fix
// и когда учить жестам (Tips). Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let hT0: Double = 1_760_000_000

/// Свежий файл на момент t, все шкалы на level (кроме перечисленных).
private func hFile(at t: Double, level: Double = 90, _ needs: [Need: Double] = [:]) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = needs[n] ?? level }
    f.lastSeenT = t
    return f
}

/// Утро: питомец не спит и до ночи больше 4 часов — прогулка точно влезает.
private func hMorning() throws -> Double {
    let r = Catalog.rules
    let probe = SaveFile.fresh(now: hT0)
    var t = hT0
    while t < hT0 + 3 * 86400 {
        let o = PetRunner.owner(probe, at: t)
        if !PetEngine.petNight(t, r, o) && PetEngine.petNight(t - 3600, r, o)
            && !(0...8).contains(where: { PetEngine.petNight(t + 3600 + Double($0) * 1800, r, o) }) { return t }
        t += 600
    }
    throw XCTSkip("нет утра за трое суток")
}

private func hint(_ f: SaveFile, at t: Double) -> NeedHint? {
    NeedHints.pick(Presenter.make(f, at: t), file: f)
}

final class NeedHintTests: XCTestCase {

    // MARK: плашка

    func testHintHiddenWhenAllFine() throws {
        let t = try hMorning()
        XCTAssertNil(hint(hFile(at: t), at: t), "всё хорошо — плашки нет")
    }

    func testHintHungryLeadsToFeed() throws {
        let t = try hMorning()
        let h = try XCTUnwrap(hint(hFile(at: t, [.food: 15]), at: t))
        XCTAssertEqual(h.key, "food")
        XCTAssertEqual(h.go, .feed)
        XCTAssertEqual(h.title, "Покормить")
        XCTAssertFalse(h.quiet)
        XCTAssertNil(h.then)
    }

    func testHintWantsLoveLeadsToPetTutor() throws {
        let t = try hMorning()
        let h = try XCTUnwrap(hint(hFile(at: t, [.love: 10]), at: t))
        XCTAssertEqual(h.go, .pet)
        XCTAssertEqual(h.title, "Погладить")
        XCTAssertEqual(h.detail, "Проведи пальцем по Шибе")
    }

    func testHintPetCooldownIsQuietWithMinutes() throws {
        let t = try hMorning()
        var f = hFile(at: t, [.love: 10])
        f.pet.cooldowns["pet"] = t + 100
        let h = try XCTUnwrap(hint(f, at: t))
        XCTAssertEqual(h.go, .none)
        XCTAssertTrue(h.quiet)
        XCTAssertEqual(h.title, "Погладить — через 2 мин")
        XCTAssertEqual(h.detail, "Только что гладил")
    }

    func testHintWalkBlockedLeadsToMissingAction() throws {
        let t = try hMorning()
        // Хочет гулять сильнее, чем есть (0.4 > 0.3), но еды 35 < 40 — ядро не пустит.
        let f = hFile(at: t, level: 80, [.walk: 0, .food: 35])
        XCTAssertEqual(Presenter.make(f, at: t).want, "walk", "пузырь — «Лапы чешутся»")
        let h = try XCTUnwrap(hint(f, at: t))
        XCTAssertEqual(h.key, "walk")
        XCTAssertEqual(h.go, .feed)
        // Волна 20: еды 35 — ещё не голодный (строка статуса: «Проголодается через…»), поэтому «подкормить»
        // и настоящая причина с числом со шкалы.
        XCTAssertEqual(h.title, "Сначала подкормить")
        XCTAssertEqual(h.detail, "Сытость 35, для прогулки нужно 40")
        XCTAssertEqual(h.then, "Гулять")
    }

    func testHintWalkReadyLeadsToWalk() throws {
        let t = try hMorning()
        let h = try XCTUnwrap(hint(hFile(at: t, level: 80, [.walk: 0]), at: t))
        XCTAssertEqual(h.go, .walk)
        XCTAssertEqual(h.title, "Гулять")
    }

    func testHintWalkNeedsRestIsQuiet() throws {
        let t = try hMorning()
        // Сил 25 < 30: гулять нельзя, а кнопки «отдохнуть» нет. Желание сна (0.1) слабее прогулки (0.4).
        let h = try XCTUnwrap(hint(hFile(at: t, level: 80, [.walk: 0, .energy: 25]), at: t))
        XCTAssertEqual(h.key, "walk")
        XCTAssertTrue(h.quiet)
        XCTAssertEqual(h.then, "Гулять")
        XCTAssertEqual(h.title, "Сначала пусть отдохнёт")
        XCTAssertEqual(h.detail, "Энергия 25, для прогулки нужно 30")
    }

    func testHintSilentWhileNappingBathingAway() throws {
        let t = try hMorning()
        var nap = hFile(at: t, [.food: 15])
        nap.pet.napUntil = t + 1200
        XCTAssertNil(hint(nap, at: t), "дремлет — своя кнопка «Разбудить»")
        var bath = hFile(at: t, [.food: 15])
        bath.pet.bathUntil = t + 600
        XCTAssertNil(hint(bath, at: t), "моется")
        var dead = hFile(at: t, [.food: 15])
        dead.pet.alive = false
        XCTAssertNil(hint(dead, at: t))
    }

    func testMoodWantMapping() {
        XCTAssertEqual(NeedHints.moodWant("hungry"), "food")
        XCTAssertEqual(NeedHints.moodWant("smelly"), "bath")
        XCTAssertEqual(NeedHints.moodWant("dirty"), "bath")
        XCTAssertEqual(NeedHints.moodWant("bored"), "play")
        XCTAssertEqual(NeedHints.moodWant("wants_love"), "pet")
        XCTAssertEqual(NeedHints.moodWant("wants_walk"), "walk")
        XCTAssertEqual(NeedHints.moodWant("tired"), "sleep")
        XCTAssertNil(NeedHints.moodWant("sulky"))
        XCTAssertNil(NeedHints.moodWant("ok"))
    }

    // MARK: кнопки панели

    func testGatesOpenWhenFree() throws {
        let t = try hMorning()
        let f = hFile(at: t)
        let g = NeedHints.gates(PetRunner.peek(f, at: t), Catalog.rules, PetRunner.owner(f, at: t))
        XCTAssertEqual(Set(g.keys), Set(NeedHints.kinds))
        XCTAssertTrue(g.values.allSatisfy(\.ok))
    }

    func testGatePetCooldownBadge() throws {
        let t = try hMorning()
        var f = hFile(at: t)
        f.pet.cooldowns["pet"] = t + 170
        let g = NeedHints.gates(PetRunner.peek(f, at: t), Catalog.rules, PetRunner.owner(f, at: t))
        XCTAssertEqual(g["pet"], ActGate(ok: false, reason: "cooldown", badge: "3 мин", until: t + 170))
        XCTAssertEqual(g["feed"]?.ok, true)
    }

    func testGatePlayAsleepBadge() throws {
        let t = try hMorning()
        var f = hFile(at: t)
        f.pet.napUntil = t + 1200
        let g = NeedHints.gates(PetRunner.peek(f, at: t), Catalog.rules, PetRunner.owner(f, at: t))
        XCTAssertEqual(g["play"]?.badge, "спит")
        XCTAssertEqual(g["pet"]?.ok, true, "гладить спящего можно")
    }

    func testMinutesLeftRoundsUpAtLeastOne() {
        XCTAssertEqual(NeedHints.minutesLeft(100, now: 99.5), "1 мин")
        XCTAssertEqual(NeedHints.minutesLeft(180, now: 0), "3 мин")
        XCTAssertEqual(NeedHints.minutesLeft(181, now: 0), "4 мин")
    }

    func testWalkGateFixPointsToButton() throws {
        let t = try hMorning()
        func fix(_ needs: [Need: Double]) -> String? {
            let f = hFile(at: t, level: 80, needs)
            return WalkPlan.gate(f, at: t).fix
        }
        XCTAssertEqual(fix([.food: 30]), "feed")
        XCTAssertEqual(fix([.clean: 20]), "bath")
        XCTAssertEqual(fix([.food: 30, .clean: 20]), "feed", "первым — как в подписи «подкормить и помыть»")
        XCTAssertNil(fix([.energy: 20]), "силы кнопкой не поднять")
        XCTAssertNil(fix([:]), "готов — исправлять нечего")
    }

    // MARK: обучение жестам

    func testPetTutorFirstStrokesThenOnlyWhenAsked() {
        var log = TipLog()
        XCTAssertTrue(Tips.showPetTutor(log, wantsPet: false, petReady: true, now: 0), "новичок — учим и без просьбы")
        XCTAssertFalse(Tips.showPetTutor(log, wantsPet: true, petReady: false, now: 0), "на откате пальцем не погладить")
        for i in 0..<Tips.learnedStrokes { Tips.noteStroke(&log, at: Double(i)) }
        XCTAssertEqual(log.strokes, Tips.learnedStrokes)
        XCTAssertFalse(Tips.showPetTutor(log, wantsPet: false, petReady: true, now: 10), "выучил")
        XCTAssertFalse(Tips.showPetTutor(log, wantsPet: true, petReady: true, now: 10), "просит, но гладил недавно")
        XCTAssertTrue(Tips.showPetTutor(log, wantsPet: true, petReady: true, now: 2 + Tips.refreshAfterS),
                      "просит, а пальцем давно не гладили — напомнить")
    }

    func testGestureTipsOncePerKindAfterFirstStroke() {
        var log = TipLog()
        XCTAssertNil(Tips.nextGesture(log), "сначала научиться гладить")
        Tips.noteStroke(&log, at: 0)
        XCTAssertEqual(Tips.nextGesture(log)?.key, "tickle")
        Tips.markSeen(&log, "tickle")
        Tips.markSeen(&log, "tickle")
        XCTAssertEqual(log.seen, ["tickle"])
        XCTAssertEqual(Tips.nextGesture(log)?.key, "swipe")
        Tips.markSeen(&log, "swipe")
        XCTAssertNil(Tips.nextGesture(log))
    }

    func testTipLogSavedOnlyWhenNotEmpty() throws {
        var f = SaveFile.fresh(now: hT0)
        let plain = String(decoding: try JSONEncoder().encode(f), as: UTF8.self)
        XCTAssertFalse(plain.contains("\"tips\""), "пустое в файл не пишется")
        Tips.noteStroke(&f.tips, at: hT0)
        Tips.markSeen(&f.tips, "tickle")
        let back = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back.tips, f.tips)
        XCTAssertEqual(back.tips.strokes, 1)
    }
}
