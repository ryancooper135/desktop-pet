// Волна 20: подсказки не спорят с тем, что на экране. Плашка «что нужно сейчас», подпись и тост «Гулять», пузырь
// мысли и строка статуса («Проголодается через…») говорят об одних и тех же шкалах одними и теми же числами.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let cT0: Double = 1_760_000_000

/// Свежий файл на момент t: все шкалы на level, кроме перечисленных.
private func cFile(at t: Double, level: Double = 80, _ needs: [Need: Double] = [:]) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = needs[n] ?? level }
    f.lastSeenT = t
    return f
}

/// Утро: не спит, до ночи больше 4 часов.
private func cMorning() throws -> Double {
    let r = Catalog.rules
    let probe = SaveFile.fresh(now: cT0)
    var t = cT0
    while t < cT0 + 3 * 86400 {
        let o = PetRunner.owner(probe, at: t)
        if !PetEngine.petNight(t, r, o) && PetEngine.petNight(t - 3600, r, o)
            && !(0...8).contains(where: { PetEngine.petNight(t + 3600 + Double($0) * 1800, r, o) }) { return t }
        t += 600
    }
    throw XCTSkip("нет утра за трое суток")
}

/// Всё, что хозяин видит на главном экране словами: плашка, подпись и тост «Гулять», пузырь, таймер.
private struct Screen {
    let snap: PetSnapshot
    let hint: NeedHint?
    let gate: WalkGate
    let needs: [Need: Double]

    init(_ f: SaveFile, at t: Double) {
        snap = Presenter.make(f, at: t)
        hint = NeedHints.pick(snap, file: f)
        gate = WalkPlan.gate(f, at: t)
        needs = PetRunner.peek(f, at: t).needs
    }

    /// Слова-советы и слова-состояния (без таймера).
    var texts: [String] {
        [hint?.title, hint?.detail, gate.hint, gate.toast, snap.wantText].compactMap { $0 }
    }
    var timer: String { snap.timer?.title ?? "" }
    func has(_ word: String) -> Bool { texts.contains { $0.localizedCaseInsensitiveContains(word) } }
}

final class HintConsistencyTests: XCTestCase {

    // MARK: общий порог «уже плохо» = порог ядра

    func testLowThresholdMatchesCore() throws {
        let t = try cMorning()
        let r = Catalog.rules
        for n in NeedHints.watched {
            let below = PetRunner.peek(cFile(at: t, level: 90, [n: r.warnLow - 0.5]), at: t)
            let at = PetRunner.peek(cFile(at: t, level: 90, [n: r.warnLow]), at: t)
            XCTAssertEqual(PetEngine.level(below, r), 1, "\(n): ниже warnLow — «Просит»")
            XCTAssertEqual(PetEngine.level(at, r), 0, "\(n): на warnLow ещё не просит")
            XCTAssertTrue(NeedHints.isLow(n, r.warnLow - 0.5, r))
            XCTAssertFalse(NeedHints.isLow(n, r.warnLow, r))
        }
        // Силы: «плохо» = настроение tired у ядра.
        for v in [0.0, 10, 19.5, 20, 25, 60] {
            let s = PetRunner.peek(cFile(at: t, level: 90, [.energy: v]), at: t)
            XCTAssertEqual(PetEngine.moods(s, r, PetRunner.owner(cFile(at: t), at: t)).contains("tired"),
                           NeedHints.isLow(.energy, v, r), "energy \(v)")
        }
        XCTAssertFalse(NeedHints.isLow(.walk, 0, r), "движение не в уровне «Просит» и не в таймере")
    }

    // MARK: главный баг: «Сначала покормить» при «Проголодается через 59 мин»

    func testWalkLockFoodAgreesWithStatusLine() throws {
        let t = try cMorning()
        // Волна 32: гулять можно с сытости 30 — это и есть порог «голодного». «Проголодается через…» в строке
        // статуса и замок прогулки по еде больше не встречаются вместе: пока не голодный — гулять можно.
        for v in [30.0, 35] {
            let sc = Screen(cFile(at: t, [.walk: 0, .food: v]), at: t)
            XCTAssertTrue(sc.timer.hasPrefix("Проголодается"), "строка статуса: ещё не голодный — \(sc.timer)")
            XCTAssertTrue(sc.gate.ok, "сытость \(v): гулять можно")
            XCTAssertFalse(sc.has("для прогулки нужно"), "\(v): \(sc.texts)")
        }
        // Чуть ниже порога — уже голодный: «покормить» и на замке, и на плашке, без «подкормить».
        let sc = Screen(cFile(at: t, [.walk: 0, .food: 29]), at: t)
        XCTAssertFalse(sc.timer.hasPrefix("Проголодается"), sc.timer)
        XCTAssertEqual(sc.gate.hint, "сначала покормить")
        XCTAssertEqual(sc.hint?.go, .feed)
        XCTAssertFalse(sc.has("подкормить"), "\(sc.texts)")
    }

    func testWalkLockFoodWhenReallyHungry() throws {
        let t = try cMorning()
        let sc = Screen(cFile(at: t, [.walk: 0, .food: 20]), at: t)
        XCTAssertFalse(sc.timer.hasPrefix("Проголодается"), "уже голодный — таймера «проголодается» нет")
        XCTAssertEqual(sc.gate.hint, "сначала покормить")
        XCTAssertEqual(sc.gate.toast, "Для прогулки сначала покормить: сытость 20, нужно 30")
    }

    /// Каждая шкала, что держит прогулку: названа она, её число и сколько нужно. Порог — из условия конфига.
    func testEachWalkLockNamesRealStat() throws {
        let t = try cMorning()
        let r = Catalog.rules
        XCTAssertEqual(WalkPlan.required(.food, r), 30, "волна 32: с сытости 30")
        XCTAssertEqual(WalkPlan.required(.clean, r), 30)
        XCTAssertEqual(WalkPlan.required(.energy, r), 30)
        XCTAssertEqual(WalkPlan.required(.fun, r), 0, "настроение прогулку не держит")
        for n in [Need.food, .clean, .energy] {
            let need = try XCTUnwrap(WalkPlan.required(n, r))
            for v in [Double(need) - 1, Double(need) - 0.4, Double(need) - 12] {
                let f = cFile(at: t, [.walk: 0, n: v])
                let sc = Screen(f, at: t)
                XCTAssertEqual(sc.gate.reason, "not_ready", "\(n) \(v)")
                let lacks = WalkPlan.lacks(PetRunner.peek(f, at: t), r)
                XCTAssertEqual(lacks.map(\.need), [n], "держит только \(n)")
                let l = try XCTUnwrap(lacks.first)
                let shown = PetRunner.peek(f, at: t).needs[n] ?? 0
                XCTAssertEqual(l.value, min(Int(shown.rounded()), need - 1), "число как на шкале, но ниже порога")
                XCTAssertLessThan(l.value, l.required, "не «40, нужно 40»")
                let name = Catalog.needName(n)
                XCTAssertTrue(sc.gate.toast.hasSuffix("\(name.lowercased()) \(l.value), нужно \(need)"), sc.gate.toast)
                let h = try XCTUnwrap(sc.hint, "\(n) \(v)")
                if h.key != "walk" {
                    // Уже голодный / грязный и это желание сильнее прогулки: плашка ведёт к той же кнопке как к нужде.
                    XCTAssertTrue(l.low, "\(n) \(v): прогулку обогнала не низкая шкала")
                    XCTAssertEqual(h.go.rawValue, WalkPlan.fixKind(n), "\(n) \(v)")
                    XCTAssertEqual("сначала " + WalkPlan.todoWord(l), sc.gate.hint)
                    continue
                }
                XCTAssertEqual(h.detail, "\(name) \(l.value), для прогулки нужно \(need)")
                XCTAssertEqual(h.then, "Гулять")
                if n == .energy {
                    XCTAssertTrue(h.quiet, "силы кнопкой не поднять")
                    XCTAssertEqual(h.title, "Сначала пусть отдохнёт")
                } else {
                    XCTAssertEqual(h.title, "Сначала " + WalkPlan.todoWord(l))
                    XCTAssertEqual("сначала " + WalkPlan.todoWord(l), sc.gate.hint, "плашка и подпись — одно слово")
                }
            }
            // На пороге — пускает.
            XCTAssertTrue(Screen(cFile(at: t, [.walk: 0, n: Double(need)]), at: t).gate.ok, "\(n) = \(need)")
        }
    }

    /// Сила не «устал» (25), а гулять нельзя: не говорим «устал», говорим число.
    func testEnergyLockIsNotCalledTired() throws {
        let t = try cMorning()
        let sc = Screen(cFile(at: t, [.walk: 0, .energy: 25]), at: t)
        XCTAssertFalse(sc.snap.mood == "tired")
        XCTAssertFalse(sc.has("устал"), "\(sc.texts)")
        XCTAssertEqual(sc.hint?.detail, "Энергия 25, для прогулки нужно 30")
        XCTAssertEqual(sc.gate.toast, "Для прогулки сначала дать отдохнуть: энергия 25, нужно 30")
    }

    // MARK: сплошная проверка: слово о состоянии — только когда шкала и правда низкая

    func testStateWordsOnlyWhenNeedIsLow() throws {
        let t = try cMorning()
        let r = Catalog.rules
        // «Голодный», «покормить», «Хочу есть» — только при сытости ниже warnLow; «Пора в ванну» — при чистоте ниже;
        // «Скучает» — при настроении ниже. И никогда рядом с таймером, который обещает это «через …».
        let words: [(Need, [String], String)] = [
            (.food, ["голодн", "покормить", "Хочу есть"], "Проголодается"),
            (.clean, ["Пора в ванну"], "Испачкается"),
            (.fun, ["Скучает"], "Заскучает"),
        ]
        var checked = 0
        for (n, bad, timerWord) in words {
            for v in stride(from: 0.0, through: 60, by: 1) {
                for walk in [0.0, 80] {
                    let f = cFile(at: t, [n: v, .walk: walk])
                    let sc = Screen(f, at: t)
                    guard sc.snap.alive, !sc.snap.critical else { continue }
                    let low = NeedHints.isLow(n, sc.needs[n] ?? 0, r)
                    for w in bad where sc.has(w) {
                        XCTAssertTrue(low, "\(n)=\(v) walk=\(walk): «\(w)» при не низкой шкале — \(sc.texts)")
                        XCTAssertFalse(sc.timer.hasPrefix(timerWord), "«\(w)» рядом с «\(sc.timer)»")
                    }
                    checked += 1
                }
            }
        }
        XCTAssertGreaterThan(checked, 300)
    }

    // MARK: строка статуса: «проголодается» — только пока он ещё не голодный

    func testDistressTimerHasItsOwnWord() throws {
        let t = try cMorning()
        let f = cFile(at: t, [.food: 20])
        let ev = ForecastTools.upcoming(f, at: t, horizonH: 48)
        let starve = try XCTUnwrap(ev.first { $0.kind == .distress && $0.key == "starve" })
        XCTAssertEqual(ForecastTools.title(starve), "Совсем оголодает")
        let sc = Screen(f, at: t)
        XCTAssertEqual(sc.hint?.detail, "Голодный — нажми, и он поест")
        XCTAssertFalse(sc.timer.hasPrefix("Проголодается"), "голодный — не «проголодается»: \(sc.timer)")
        // Остров берёт тот же заголовок из ContentState.timerTitle — проверка в IslandPlanTests (ActivityKit не на Linux).

        let dirty = cFile(at: t, [.clean: 20])
        let d = try XCTUnwrap(ForecastTools.upcoming(dirty, at: t, horizonH: 48).first { $0.kind == .distress && $0.key == "dirty" })
        XCTAssertEqual(ForecastTools.title(d), "Завоняет")
    }

    // MARK: пузырь и плашка без прогулки

    func testFoodWantBeforeHungerIsSoft() throws {
        let t = try cMorning()
        let soft = Screen(cFile(at: t, [.food: 35]), at: t)
        XCTAssertEqual(soft.snap.want, "food", "ядро хочет есть уже при 35")
        XCTAssertTrue(soft.timer.hasPrefix("Проголодается"))
        XCTAssertEqual(soft.snap.wantText, Lines.shared.thought("treat").text)
        XCTAssertEqual(soft.snap.wantIcon, Lines.shared.thought("treat").icon)
        XCTAssertEqual(soft.hint?.title, "Подкормить")
        XCTAssertEqual(soft.hint?.go, .feed)
        XCTAssertEqual(soft.hint?.detail, "Не прочь перекусить — нажми, и он поест")

        let hungry = Screen(cFile(at: t, [.food: 15]), at: t)
        XCTAssertEqual(hungry.snap.wantText, Lines.shared.thought("food").text)
        XCTAssertEqual(hungry.hint?.detail, "Голодный — нажми, и он поест")
    }

    func testBathAndPlayWordsFollowScale() throws {
        let t = try cMorning()
        let bath = Screen(cFile(at: t, [.clean: 33]), at: t)
        XCTAssertEqual(bath.hint?.go, .bath)
        XCTAssertEqual(bath.hint?.detail, "Ванна не помешает — нажми, и он помоется")
        XCTAssertEqual(Screen(cFile(at: t, [.clean: 20]), at: t).hint?.detail, "Пора в ванну — нажми, и он помоется")

        let play = Screen(cFile(at: t, [.fun: 31]), at: t)
        XCTAssertEqual(play.hint?.go, .play)
        XCTAssertEqual(play.hint?.detail, "Хочет поиграть — нажми, поиграйте")
        XCTAssertEqual(Screen(cFile(at: t, [.fun: 20]), at: t).hint?.detail, "Скучает — нажми, поиграйте")
    }

    // MARK: откаты: минуты одни и те же

    func testCooldownMinutesAgreeEverywhere() throws {
        let t = try cMorning()
        var f = cFile(at: t, [.love: 10])
        f.pet.cooldowns["pet"] = t + 170
        let sc = Screen(f, at: t)
        let g = NeedHints.gates(f, at: t)["pet"]
        XCTAssertEqual(g?.badge, "3 мин")
        XCTAssertEqual(sc.hint?.title, "Погладить — через 3 мин", "плашка — те же минуты, что бейдж")
        XCTAssertEqual(NeedHints.minutesLeft(try XCTUnwrap(g?.until), now: t), "3 мин", "и тост «ещё раз через…»")

        // Откат миски, пока прогулку держит сытость: тот же глагол, что в «Сначала покормить» (волна 32: порог 30).
        var w = cFile(at: t, [.walk: 0, .food: 25])
        w.pet.cooldowns[Catalog.mainFood] = t + 100
        let h = try XCTUnwrap(Screen(w, at: t).hint)
        XCTAssertTrue(h.quiet)
        XCTAssertEqual(h.title, "Покормить — через 2 мин")
        XCTAssertEqual(Screen(w, at: t).gate.hint, "сначала покормить")
    }

    // MARK: «завтра» — только когда правда завтра

    func testTomorrowOnlyWhenWalkCannotFitToday() throws {
        let r = Catalog.rules
        let w = try XCTUnwrap(r.walkOut)
        let probe = SaveFile.fresh(now: cT0)
        var seen = 0
        var t = cT0
        while t < cT0 + 86400 {
            let f = cFile(at: t, level: 90)
            let g = WalkPlan.gate(f, at: t)
            let o = PetRunner.owner(probe, at: t)
            if g.hint.contains("завтра") || g.toast.contains("завтра") {
                seen += 1
                XCTAssertTrue(PetEngine.petNight(t + Double(w.minMin) * 60, r, o) || PetEngine.petNight(t, r, o),
                              "«завтра» днём, когда час прогулки ещё влезает")
            }
            t += 900
        }
        XCTAssertGreaterThan(seen, 0, "поздний вечер в сутках есть")

        // Дрёма днём: не «завтра».
        let m = try cMorning()
        var nap = cFile(at: m, level: 90)
        nap.pet.napUntil = m + 1200
        let g = WalkPlan.gate(nap, at: m)
        XCTAssertEqual(g.reason, "asleep")
        XCTAssertFalse(g.hint.contains("завтра") || g.toast.contains("завтра"))
    }

    // MARK: прочие причины замка

    func testOtherLockReasonsNameTheirState() throws {
        let t = try cMorning()
        var bath = cFile(at: t, level: 90)
        bath.pet.bathUntil = t + 600
        let b = WalkPlan.gate(bath, at: t)
        XCTAssertEqual(b.reason, "bathing")
        XCTAssertEqual(Screen(bath, at: t).snap.timer?.title, "Моется", "подпись «моется» = таймер «Моется»")
        XCTAssertEqual(b.hint, "моется")

        var away = cFile(at: t, level: 90)
        away.pet.outing = Outing(from: t - 600, until: t + 3600, find: "cone")
        let a = WalkPlan.gate(away, at: t)
        XCTAssertEqual(a.reason, "away")
        XCTAssertTrue(a.hint.hasPrefix("вернётся в"))
        XCTAssertEqual(Screen(away, at: t).snap.timer?.title, "Гуляет")

        let sick = WalkPlan.gate(cFile(at: t, level: 90, [.food: 0]), at: t)
        XCTAssertEqual(sick.reason, "unwell")
        XCTAssertFalse(sick.toast.isEmpty)
    }

    func testGenericNotReadyNoLongerClaimsHunger() {
        let s = RefuseText.text("not_ready")
        XCTAssertFalse(s.localizedCaseInsensitiveContains("покорм"), s)
        XCTAssertFalse(s.localizedCaseInsensitiveContains("почист"), s)
    }

    // MARK: свой персонаж: подсказки без «Шибы»

    func testHintsAndTipsUseCharacterName() throws {
        let t = try cMorning()
        var f = cFile(at: t, [.love: 10])
        f.character = "murka"
        f.characterName = "Мурка"
        let h = try XCTUnwrap(NeedHints.pick(Presenter.make(f, at: t), file: f))
        XCTAssertEqual(h.go, .pet)
        XCTAssertFalse(h.detail.contains("Шиб"), h.detail)
        XCTAssertEqual(h.detail, "Проведи пальцем по питомцу")
        XCTAssertFalse(Tips.petTutorText(name: "Мурка").contains("Шиб"))
        XCTAssertFalse(Tips.petTutorLabel(name: "Мурка").contains("Шиб"))
        XCTAssertEqual(Tips.petTutorText(name: PetNames.shiba), "Проведи пальцем по Шибе")
        var log = TipLog()
        Tips.noteStroke(&log, at: t)
        let tip = try XCTUnwrap(Tips.nextGesture(log, name: "Мурка"))
        XCTAssertFalse(tip.text.contains("Шиб"), tip.text)
        XCTAssertEqual(Tips.nextGesture(log)?.text, "Четыре быстрых тапа по Шибе — щекотка")
    }
}
