// Прогулка с находкой без экрана: слова находок и альбом, кнопка «Гулять» (WalkPlan), остров и снимок,
// пока Шиба гуляет, уведомление «Вернулся!» в лимите 1 в день и строки lines.json.
// Моменты дня и ночи ищем перебором от t0 в поясе машины: тесты не зависят от того, где их запустили.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let wT0: Double = 1_760_000_000

/// Свежий файл на момент t, все шкалы на level (кроме перечисленных).
private func wFile(at t: Double, level: Double = 90, _ needs: [Need: Double] = [:]) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = needs[n] ?? level }
    f.lastSeenT = t
    return f
}

/// Первый момент от t0 с шагом step, где выполнено условие (пояс — как у ядра на этот момент).
private func wFind(step: Double = 600, _ ok: (Double, Owner) -> Bool) -> Double? {
    let probe = SaveFile.fresh(now: wT0)
    var t = wT0
    while t < wT0 + 3 * 86400 {
        if ok(t, PetRunner.owner(probe, at: t)) { return t }
        t += step
    }
    return nil
}

/// Утро: питомец бодр и до ночи больше 4 часов — прогулка точно влезает.
private func wMorning() throws -> Double {
    let r = Catalog.rules
    return try XCTUnwrap(wFind { t, o in
        !PetEngine.petNight(t, r, o) && PetEngine.petNight(t - 3600, r, o)
            && !(0...8).contains { PetEngine.petNight(t + 3600 + Double($0) * 1800, r, o) }
    }, "нет утра за трое суток")
}

final class WalkTests: XCTestCase {

    // MARK: находки

    func testFindsMatchConfigOrder() throws {
        let w = try XCTUnwrap(Catalog.rules.walkOut, "care.walk_out есть в конфиге")
        XCTAssertEqual(Finds.all.map(\.id), w.finds, "порядок и состав — как в config/economy.json")
        XCTAssertEqual(Set(Finds.all.map(\.id)).count, Finds.all.count)
        for f in Finds.all {
            XCTAssertFalse(f.name.isEmpty, f.id)
            XCTAssertFalse(f.acc.isEmpty, f.id)
            XCTAssertFalse(f.emoji.isEmpty, f.id)
            XCTAssertEqual(f.name, f.name.lowercased(), "\(f.id): имя со строчной, в {item} середины фразы")
            XCTAssertEqual(f.title.first.map(String.init), f.name.first.map { String($0).uppercased() }, f.id)
            XCTAssertEqual(Finds.find(f.id), f)
        }
        XCTAssertEqual(Finds.name("cone"), "шишка")
        XCTAssertEqual(Finds.acc("cone"), "шишку")
        XCTAssertEqual(Finds.name("pebble"), "камешек")
        XCTAssertEqual(Finds.broughtText("stick"), "Принёс палку!")
        XCTAssertEqual(Finds.name("новое"), "находка", "находка из конфига новее приложения")
        XCTAssertEqual(Finds.acc("новое"), "находку")
    }

    func testClockAndNote() {
        XCTAssertEqual(Finds.clock(0, tzOffsetMin: 0), "0:00")
        XCTAssertEqual(Finds.clock(14 * 3600 + 20 * 60 + 59, tzOffsetMin: 0), "14:20")
        XCTAssertEqual(Finds.clock(14 * 3600 + 5 * 60, tzOffsetMin: 120), "16:05")
        XCTAssertEqual(Finds.clock(10 * 60, tzOffsetMin: -60), "23:10", "через полночь назад")
        XCTAssertEqual(Finds.clock(23 * 3600 + 30 * 60, tzOffsetMin: 60), "0:30", "через полночь вперёд")
        XCTAssertEqual(Finds.awayNote(until: 14 * 3600 + 20 * 60, tzOffsetMin: 0), "Ушёл гулять, вернусь в 14:20")
    }

    func testAlbumRowsAndTotals() {
        let empty = Finds.album([:])
        XCTAssertEqual(empty.map(\.find.id), Finds.all.map(\.id), "пустой альбом — все клетки «???»")
        XCTAssertTrue(empty.allSatisfy { $0.count == 0 })
        XCTAssertEqual(Finds.total([:]), 0)
        XCTAssertEqual(Finds.kinds([:]), 0)

        let finds = ["cone": 2, "ball": 1, "zzz": 1, "sock": -3]
        let rows = Finds.album(finds)
        XCTAssertEqual(rows.count, Finds.all.count + 1, "незнакомая находка — отдельной клеткой в конце")
        XCTAssertEqual(rows.first { $0.find.id == "cone" }?.count, 2)
        XCTAssertEqual(rows.first { $0.find.id == "sock" }?.count, 0, "отрицательное — как ноль")
        XCTAssertEqual(rows.last?.find.id, "zzz")
        XCTAssertEqual(rows.last?.find.name, "находка")
        XCTAssertEqual(Finds.total(finds), 4)
        XCTAssertEqual(Finds.kinds(finds), 2)
    }

    func testReturnedOnlyWhenWalkEndedAlive() {
        var s = wFile(at: wT0).pet
        let w = Outing(from: wT0 - 600, until: wT0 + 600, find: "leaf")
        XCTAssertNil(Finds.returned(before: nil, after: s), "не гулял")
        XCTAssertEqual(Finds.returned(before: w, after: s), "leaf")
        s.outing = w
        XCTAssertNil(Finds.returned(before: w, after: s), "ещё гуляет")
        s.outing = nil
        s.alive = false
        XCTAssertNil(Finds.returned(before: w, after: s), "умер — праздника нет")
    }

    // MARK: кнопка «Гулять»

    func testGateOkThenAwayThenBackWithFind() throws {
        let t = try wMorning()
        var f = wFile(at: t)
        let g = WalkPlan.gate(f, at: t)
        XCTAssertTrue(g.ok, "\(g)")
        XCTAssertNil(g.reason)
        XCTAssertEqual(g.hint, "1–3 ч, с находкой")
        XCTAssertLessThanOrEqual(g.hint.count, 24)
        XCTAssertNil(g.until)

        let res = PetRunner.apply(.walk, source: .app, to: &f, now: t)
        XCTAssertTrue(res.ok, "\(res)")
        let out = try XCTUnwrap(f.pet.outing)
        XCTAssertGreaterThanOrEqual(out.until - out.from, 3600)
        XCTAssertLessThanOrEqual(out.until - out.from, 3 * 3600)
        XCTAssertNotNil(Finds.find(out.find), "находка из известных")

        let mid = t + 120
        let away = WalkPlan.gate(f, at: mid)
        let o = PetRunner.owner(f, at: mid)
        XCTAssertFalse(away.ok)
        XCTAssertEqual(away.reason, "away")
        XCTAssertEqual(away.until, out.until)
        XCTAssertEqual(away.hint, "вернётся в \(Finds.clock(out.until, tzOffsetMin: o.tzOffsetMin))")
        XCTAssertLessThanOrEqual(away.hint.count, 24)
        XCTAssertEqual(away.toast, Finds.awayNote(until: out.until, tzOffsetMin: o.tzOffsetMin))

        // Остров: статус «Гуляет» без кнопок. Снимок: позы нет, главное — открыть приложение, таймер прогулки.
        let pick = IslandPlan.pick(f, at: mid)
        XCTAssertEqual(pick.primary, .walk)
        XCTAssertNil(pick.secondary)
        XCTAssertNil(IslandAct.walk.action)
        let snap = Presenter.make(f, at: mid)
        XCTAssertEqual(snap.pose, .away)
        XCTAssertEqual(snap.main, .open)
        XCTAssertEqual(snap.timer?.kind, "walk")
        XCTAssertEqual(snap.timer?.end, out.until)
        for line in [snap.line, snap.islandLine] {
            XCTAssertFalse(line.isEmpty)
            XCTAssertFalse(line.contains("{"), line)
            XCTAssertNotEqual(line, "Я тут", "реплика прогулки нашлась")
        }

        // Вернулся: находка в альбоме, прогулки больше нет, кнопка снова про прогулку.
        let back = PetRunner.peek(f, at: out.until + 60)
        XCTAssertNil(back.outing)
        XCTAssertEqual(back.finds[out.find], 1)
        XCTAssertEqual(Finds.returned(before: out, after: back), out.find)
        XCTAssertEqual(Finds.total(back.finds), PetEngine.walksDone(back))
        XCTAssertNotEqual(WalkPlan.gate(f, at: out.until + 60).reason, "away")
    }

    func testGateNotReadyNamesWhatToDo() throws {
        let t = try wMorning()
        let hungry = WalkPlan.gate(wFile(at: t, [.food: 35]), at: t)
        XCTAssertFalse(hungry.ok)
        XCTAssertEqual(hungry.reason, "not_ready")
        XCTAssertEqual(hungry.hint, "сначала покормить")
        XCTAssertEqual(hungry.toast, "Для прогулки сначала покормить")

        let two = WalkPlan.gate(wFile(at: t, [.food: 35, .clean: 20]), at: t)
        XCTAssertEqual(two.reason, "not_ready")
        XCTAssertEqual(two.hint, "сначала покормить и помыть")
        XCTAssertLessThanOrEqual(two.hint.count, 26)

        let f = wFile(at: t, [.food: 35, .clean: 20, .energy: 10])
        XCTAssertEqual(WalkPlan.lacking(PetRunner.peek(f, at: t), Catalog.rules), [.food, .clean, .energy])
        XCTAssertEqual(WalkPlan.lacking(PetRunner.peek(wFile(at: t), at: t), Catalog.rules), [])
    }

    func testGateRefusalsHaveHints() throws {
        let r = Catalog.rules
        let night = try XCTUnwrap(wFind { t, o in PetEngine.petNight(t, r, o) })
        let asleep = WalkPlan.gate(wFile(at: night), at: night)
        XCTAssertEqual(asleep.reason, "asleep")
        XCTAssertEqual(asleep.hint, "спит")
        XCTAssertFalse(asleep.toast.isEmpty)

        // За полчаса до ночи прогулка не влезает в минимальный час.
        let late = try XCTUnwrap(wFind(step: 300) { t, o in
            !PetEngine.petNight(t, r, o) && PetEngine.petNight(t + 1800, r, o)
        })
        let tooLate = WalkPlan.gate(wFile(at: late), at: late)
        XCTAssertEqual(tooLate.reason, "too_late")
        XCTAssertEqual(tooLate.hint, "поздно, завтра")

        let t = try wMorning()
        var bath = wFile(at: t)
        bath.pet.bathUntil = t + 600
        XCTAssertEqual(WalkPlan.gate(bath, at: t).reason, "bathing")

        let starving = WalkPlan.gate(wFile(at: t, [.food: 0]), at: t)
        XCTAssertEqual(starving.reason, "unwell")
        XCTAssertEqual(starving.hint, "сначала помоги")

        var dead = wFile(at: t)
        dead.pet.alive = false
        dead.pet.diedAt = t - 3600
        dead.pet.cause = .starve
        let gone = WalkPlan.gate(dead, at: t)
        XCTAssertFalse(gone.ok)
        XCTAssertEqual(gone.hint, "")

        for g in [asleep, tooLate, starving] {
            XCTAssertLessThanOrEqual(g.hint.count, 24, g.hint)
        }
    }

    func testJoinedWords() {
        XCTAssertEqual(WalkPlan.joined([]), "")
        XCTAssertEqual(WalkPlan.joined(["a"]), "a")
        XCTAssertEqual(WalkPlan.joined(["a", "b"]), "a и b")
        XCTAssertEqual(WalkPlan.joined(["a", "b", "c"]), "a, b и c")
        for n in [Need.food, .clean, .energy, .fun, .love] { XCTAssertNotEqual(WalkPlan.todoWord(n), "позаботиться") }
    }

    /// Между until и шагом ядра, который снимает прогулку (до минуты), комната пустая — и подписи
    /// не врут: таймер «Гуляет» до backAt, записка и кнопка «вот-вот», а не время из прошлого.
    func testLateWalkStaysConsistentUntilCoreStep() throws {
        let t = try wMorning()
        let until = t + 600
        let f = walking(now: t, until: until)
        let late = until + 30
        let s = PetRunner.peek(f, at: late)
        let w = try XCTUnwrap(s.outing, "ядро ещё не дошло до шага с t ≥ until")
        XCTAssertEqual(Finds.backAt(w, stateT: s.t), until + 60)
        XCTAssertEqual(Finds.backAt(w, stateT: t), until + 60, "сетка шагов та же с любого места")

        let snap = Presenter.make(f, at: late)
        XCTAssertEqual(snap.pose, .away)
        XCTAssertEqual(snap.timer?.kind, "walk")
        XCTAssertEqual(snap.timer?.end, until + 60)

        let o = PetRunner.owner(f, at: late)
        XCTAssertEqual(Finds.awayNote(until: w.until, tzOffsetMin: o.tzOffsetMin, now: late), "Ушёл гулять, вот-вот вернусь")
        XCTAssertEqual(Finds.awayNote(until: w.until, tzOffsetMin: o.tzOffsetMin, now: t),
                       "Ушёл гулять, вернусь в \(Finds.clock(until, tzOffsetMin: o.tzOffsetMin))")
        XCTAssertEqual(WalkPlan.gate(f, at: late).hint, "вот-вот вернётся")

        XCTAssertNil(PetRunner.peek(f, at: until + 60).outing, "дома ровно к backAt")
    }

    // MARK: уведомление «Вернулся!»

    /// Файл, где Шиба гуляет с now до until (до ночи питомца, чтобы прогулка не кончилась раньше).
    private func walking(now: Double, until: Double, find: String = "cone") -> SaveFile {
        var f = wFile(at: now)
        f.pet.outing = Outing(from: now, until: until, find: find)
        return f
    }

    private func care(_ notes: [PlannedNote]) -> [PlannedNote] { notes.filter { $0.category != "pet.build" } }

    func testWalkHomeNoteTakesTheDay() throws {
        let t = try wMorning()
        let until = t + 2 * 3600
        let f = walking(now: t, until: until)
        let o = PetRunner.owner(f, at: t)
        let notes = care(NotificationPlanner.plan(f, now: t))
        let home = try XCTUnwrap(notes.first { $0.trigger == "walk_home" }, "\(notes.map(\.trigger))")
        XCTAssertEqual(home.date.timeIntervalSince1970, until)
        XCTAssertEqual(home.id, "pet.walk_home.\(Int(until))")
        XCTAssertEqual(home.category, "pet.need")
        XCTAssertFalse(home.title.isEmpty)
        XCTAssertLessThanOrEqual(home.title.count, LineLimit.notifTitle)
        XCTAssertFalse(home.body.contains("{"), home.body)
        XCTAssertNotEqual(home.body, "Загляни ко мне", "строки walk_home есть в lines.json")
        let day = NotificationPlanner.localDay(until, o)
        let sameDay = notes.filter { NotificationPlanner.localDay($0.date.timeIntervalSince1970, o) == day }
        XCTAssertEqual(sameDay.map(\.trigger), ["walk_home"], "лимит 1 в местный день")
        XCTAssertEqual(notes.map(\.date), notes.map(\.date).sorted())
    }

    func testWalkHomeRespectsCapQuietHoursAndLead() throws {
        let t = try wMorning()
        let until = t + 2 * 3600

        // В этот день уже было уведомление — не шлём.
        var sent = walking(now: t, until: until)
        sent.notif.lastSentT = t - 60
        XCTAssertNil(NotificationPlanner.plan(sent, now: t).first { $0.trigger == "walk_home" })

        // Вернётся меньше чем через 2 минуты — не успеть.
        let soon = walking(now: t, until: t + 60)
        XCTAssertNil(NotificationPlanner.plan(soon, now: t).first { $0.trigger == "walk_home" })

        // Не гуляет — нечего.
        XCTAssertNil(NotificationPlanner.plan(wFile(at: t), now: t).first { $0.trigger == "walk_home" })

        // Возвращение в тихие часы хозяина (лёг, а питомец ещё нет) — не шлём и не переносим.
        let r = Catalog.rules
        if let quiet = wFind(step: 60, { q, o in PetEngine.ownerAsleep(q, o) && !PetEngine.petNight(q, r, o) }) {
            let f = walking(now: quiet - 3600, until: quiet)
            if PetRunner.peek(f, at: quiet - 3600).outing != nil {
                XCTAssertNil(NotificationPlanner.plan(f, now: quiet - 3600).first { $0.trigger == "walk_home" })
            }
        }
    }

    // MARK: строки

    func testWalkLinesExistAndFill() {
        let lines = Lines.shared
        for slot in 0..<6 {
            let n = lines.notification("walk_home", seed: "w", slot: slot, vars: ["item": "шишка"])
            XCTAssertNotEqual(n.body, "Загляни ко мне")
            XCTAssertFalse(n.body.contains("{"), n.body)
            XCTAssertLessThanOrEqual(n.title.count, LineLimit.notifTitle)
            let a = lines.away("back_home", seed: "w", slot: slot, vars: ["item": "шишка"])
            XCTAssertNotNil(a, "back_home в ленте «Пока тебя не было»")
            XCTAssertFalse(a?.contains("{") ?? true, a ?? "")
            for (section, key) in [("widget", "react_walk"), ("widget", "walking"),
                                   ("island", "react_walk"), ("island", "walking")] {
                let it = lines.pick(section, key, seed: "w", slot: slot)
                XCTAssertNotNil(it, "\(section).\(key)")
                XCTAssertFalse(it?.text.contains("{") ?? true)
            }
        }
        // Без item строки с подстановкой отпадают, но пул не пустеет.
        XCTAssertNotNil(lines.away("back_home", seed: "w", slot: 0))
    }
}
