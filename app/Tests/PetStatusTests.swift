// Волна 51: «что сейчас» (PetStatusLogic) — таблица «состояние → что показано» на все PetStatusKind,
// и главное правило: кнопка только та, что ядро примет прямо сейчас (недоступное не предлагаем).
// Пояс закреплён (UTC, tzOffsetMin: 0): полдень и ночь не зависят от машины, где гоняют тесты.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Полдень UTC: хозяин точно не спит.
private let noon: Double = (1_760_000_000 / 86400).rounded(.down) * 86400 + 12 * 3600

private func file(at t: Double = noon, _ level: Double = 90, _ needs: [Need: Double] = [:]) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.owner.tzOffsetMin = 0
    for n in [Need.food, .clean, .energy, .fun, .love, .walk, .look] { f.pet.needs[n] = needs[n] ?? level }
    return f
}

private func status(_ f: SaveFile, at t: Double = noon, trip: IslandTrip? = nil, ate: Bool = false) -> PetStatus {
    let r = ItemPerks.rules(f)
    var s = t > f.pet.t ? PetEngine.advance(f.pet, r, f.owner, t) : f.pet
    s.t = max(s.t, t)
    return PetStatusLogic.of(s, r, engine: f.owner, local: f.owner, trip: trip, ate: ate)
}

/// Первая минута ночи пса после полудня (по правилам и хозяину файла).
private func nightT(_ f: SaveFile) -> Double {
    let r = ItemPerks.rules(f)
    var t = noon
    while !PetEngine.petNight(t, r, f.owner) && t < noon + 86400 { t += 60 }
    return t + 3600
}

/// Ядро примет действие кнопки на копии стейта.
private func accepted(_ st: PetStatus, _ f: SaveFile, at t: Double) -> Bool {
    guard let a = st.act?.action else { return true }
    let r = ItemPerks.rules(f)
    var s = t > f.pet.t ? PetEngine.advance(f.pet, r, f.owner, t) : f.pet
    s.t = max(s.t, t)
    return PetEngine.act(&s, r, f.owner, a.core).ok
}

final class PetStatusTests: XCTestCase {

    /// Строка таблицы: состояние → вид.
    private struct Row {
        var name: String
        var f: SaveFile
        var t: Double = noon
        var trip: IslandTrip? = nil
        var ate = false
        var kind: PetStatusKind
        var title: String
        var timer: Bool
        var act: IslandAct?
        var pose: DogPose
        /// false — кнопку сверяем только правилом «ядро примет» (у болезни она зависит от беды).
        var checkAct = true
    }

    private func rows() -> [Row] {
        var out: [Row] = []

        var dead = file()
        dead.pet.alive = false
        dead.pet.diedAt = noon - 60
        out.append(Row(name: "убежал", f: dead, kind: .gone, title: "Убежал", timer: false, act: nil, pose: .away))

        out.append(Row(name: "поход", f: file(), trip: IslandTrip(from: noon - 600, backAt: noon + 3000, place: "Маяк"),
                       kind: .trip, title: "Маяк", timer: true, act: nil, pose: .run))

        var walk = file()
        walk.pet.outing = Outing(from: noon - 600, until: noon + 1200, find: "cone")
        out.append(Row(name: "гуляет", f: walk, kind: .walk, title: "Гуляет", timer: true, act: nil, pose: .run))

        var bath = file()
        bath.pet.bathUntil = noon + 180
        out.append(Row(name: "моется", f: bath, kind: .bath, title: "Моется", timer: true, act: nil, pose: .bath))

        var nap = file(at: noon, 90, [.energy: 30])
        nap.pet.napUntil = noon + 1500
        out.append(Row(name: "дремлет", f: nap, kind: .nap, title: "Дремлет", timer: true, act: nil, pose: .sleep))

        // Шкалы полные на сам момент ночи: без беды кнопки нет («Разбудить» не предлагаем).
        let nt = nightT(file())
        let nf = file(at: nt)
        out.append(Row(name: "ночь", f: nf, t: nt, kind: .night, title: "Спит", timer: false, act: nil,
                       pose: .sleep))

        out.append(Row(name: "ест", f: file(), ate: true, kind: .eat, title: "Ест", timer: false, act: nil, pose: .eat))

        var sick = file(at: noon, 15)
        sick.pet.hearts = 1
        out.append(Row(name: "болеет", f: sick, kind: .sick, title: "Плохо себя чувствует", timer: false,
                       act: nil, pose: .lie, checkAct: false))

        out.append(Row(name: "голоден", f: file(at: noon, 90, [.food: 10]), kind: .need, title: "Хочет есть",
                       timer: false, act: .feed, pose: .bowl))
        out.append(Row(name: "грязный", f: file(at: noon, 90, [.clean: 10]), kind: .need, title: "Пора помыться",
                       timer: false, act: .bath, pose: .lie))
        out.append(Row(name: "скучает", f: file(at: noon, 90, [.fun: 10]), kind: .need, title: "Скучает",
                       timer: false, act: .play, pose: .lie))
        out.append(Row(name: "хочет ласки", f: file(at: noon, 90, [.love: 10]), kind: .need, title: "Хочет ласки",
                       timer: false, act: .pet, pose: .lie))

        out.append(Row(name: "всё хорошо", f: file(), kind: .fine, title: "Всё хорошо", timer: false, act: .pet,
                       pose: .sit))
        return out
    }

    func testTableAllKinds() {
        let rs = rows()
        XCTAssertEqual(Set(rs.map(\.kind)), Set(PetStatusKind.allCases), "в таблице все состояния")
        for row in rs {
            let st = status(row.f, at: row.t, trip: row.trip, ate: row.ate)
            XCTAssertEqual(st.kind, row.kind, row.name)
            XCTAssertEqual(st.title, row.title, row.name)
            XCTAssertEqual(st.timerEnd != nil, row.timer, "\(row.name): таймер")
            if row.checkAct { XCTAssertEqual(st.act, row.act, "\(row.name): кнопка") }
            XCTAssertEqual(st.pose, row.pose, "\(row.name): поза")
            XCTAssertFalse(st.symbol.isEmpty, row.name)
            XCTAssertFalse(st.line.isEmpty, row.name)
            XCTAssertEqual(st.kind.busy, [.trip, .walk, .bath, .nap, .night, .eat].contains(row.kind), row.name)
            XCTAssertTrue(accepted(st, row.f, at: row.t), "\(row.name): кнопку ядро примет")
            if let a = st.act { XCTAssertNotNil(a.action, "\(row.name): кнопка — действие, не статус") }
        }
    }

    func testDetailsAndTimers() {
        var bath = file()
        bath.pet.bathUntil = noon + 170
        let b = status(bath)
        XCTAssertEqual(b.detail, "ещё 3 мин")
        XCTAssertEqual(b.line, "Моется · ещё 3 мин")
        XCTAssertEqual(b.timerEnd, noon + 170)
        XCTAssertEqual(b.timerFrom, noon)

        var walk = file()
        walk.pet.outing = Outing(from: noon - 600, until: noon + 1200, find: "cone")
        let w = status(walk)
        XCTAssertEqual(w.detail, "вернётся в 12:20")
        XCTAssertEqual(w.progress ?? -1, 600.0 / 1800, accuracy: 1e-9)

        let h = status(file(at: noon, 90, [.food: 18]))
        XCTAssertEqual(h.need, .food)
        XCTAssertEqual(h.detail?.hasSuffix("%"), true)
        XCTAssertNotNil(h.progress)

        let nf = file()
        let n = status(nf, at: nightT(nf))
        XCTAssertEqual(n.detail?.hasPrefix("до "), true)

        XCTAssertEqual(PetStatusLogic.left(59), "ещё 1 мин")
        XCTAssertEqual(PetStatusLogic.left(3600), "ещё 1 ч")
        XCTAssertEqual(PetStatusLogic.left(4800), "ещё 1 ч 20 мин")
    }

    /// Недоступное не предлагаем: в ванне, на прогулке, в походе, убежал — без кнопки; ночью и в дрёму — без
    /// «Разбудить»; по сетке состояний любая кнопка проходит в ядре.
    func testNeverOffersUnavailable() {
        var bath = file(at: noon, 90, [.food: 5])
        bath.pet.bathUntil = noon + 300
        XCTAssertNil(status(bath).act, "в ванне голодного не кормим кнопкой — ядро откажет")

        var walk = file(at: noon, 90, [.food: 5, .love: 5])
        walk.pet.outing = Outing(from: noon - 60, until: noon + 1200, find: "cone")
        XCTAssertNil(status(walk).act, "гуляет — ядро откажет всем")

        var dead = file()
        dead.pet.alive = false
        XCTAssertNil(status(dead).act)

        var nap = file(at: noon, 90, [.energy: 20])
        nap.pet.napUntil = noon + 900
        XCTAssertNotEqual(status(nap).act, .wake, "дрёму не прерываем кнопкой")

        let nf = file(at: noon, 90, [.fun: 10])
        XCTAssertNotEqual(status(nf, at: nightT(nf)).act, .wake)
        XCTAssertNotEqual(status(nf, at: nightT(nf)).act, .play, "ночью не играем")

        // Сетка: шкалы × занятия; любая предложенная кнопка — ядро примет.
        let levels: [Double] = [3, 15, 28, 45, 90]
        var checked = 0
        for n in [Need.food, .clean, .energy, .fun, .love, .walk] {
            for v in levels {
                for mode in 0..<4 {
                    var f = file(at: noon, 80, [n: v])
                    var t = noon
                    switch mode {
                    case 1: f.pet.napUntil = noon + 600
                    case 2: t = nightT(f)
                    case 3: f.pet.hearts = 1.5
                    default: break
                    }
                    let st = status(f, at: t)
                    XCTAssertTrue(accepted(st, f, at: t), "\(n) \(v) режим \(mode): \(String(describing: st.act))")
                    if let a = st.act { XCTAssertNotNil(a.action) }
                    if st.kind == .need { XCTAssertNotNil(st.need) }
                    checked += 1
                }
            }
        }
        XCTAssertEqual(checked, 6 * 5 * 4)
    }

    /// Из сейва (контрол): та же логика, что и на кадре виджета.
    func testFromSaveMatchesFrame() {
        var f = file()
        f.pet.bathUntil = noon + 240
        let a = PetStatusLogic.of(f, now: noon, tzOffsetMin: 0)
        XCTAssertEqual(a.kind, .bath)
        let fr = IslandEvents.widget(f, now: noon, tzOffsetMin: 0)
        XCTAssertEqual(fr.first?.status.kind, .bath)
        XCTAssertEqual(fr.first?.pose, .bath)
        XCTAssertTrue(fr.contains { $0.t == noon + 240 }, "конец ванны — свой кадр")
        XCTAssertNotEqual(fr.first { $0.t == noon + 240 }?.status.kind, .bath, "после ванны — уже не моется")
        let look = WidgetLook.looks(f, now: noon, tzOffsetMin: 0, asks: [])
        XCTAssertEqual(look.first?.status.kind, .bath)
        XCTAssertEqual(look.first?.status.line, "Моется · ещё 4 мин")
    }

    // MARK: виджет: что ведёт подпись и когда кнопка

    private func look(_ st: PetStatus, ask: String? = nil, alive: Bool = true) -> WidgetLook {
        var l = WidgetLook(t: noon, pose: st.pose, alive: alive, caption: "Подпись", main: nil, bars: [], ring: nil,
                           coins: nil, coinsFull: nil, bankLine: nil, bankFull: false, tripFrom: nil, tripUntil: nil,
                           sky: .day, tier: 0, tierName: "", lock: .pose, dogScale: 1)
        l.status = st
        l.ask = ask
        return l
    }

    func testWidgetLookStatusLeads() {
        // Моется: занятие главнее просьбы, живой таймер вместо подписи, кнопки нет.
        var f = file()
        f.pet.bathUntil = noon + 180
        let bath = look(status(f), ask: "Почеши за ушком?")
        XCTAssertTrue(bath.statusLeads)
        XCTAssertEqual(bath.headline, "Моется")
        XCTAssertEqual(bath.statusTimer?.until, noon + 180)
        XCTAssertNil(bath.subline, "таймер заменяет подпись")
        XCTAssertNil(bath.button)
        XCTAssertEqual(bath.mediumBars, 2)

        // Голоден без просьбы: «Хочет есть», подпись шкалой, кнопка «Покормить» (ядро примет).
        let hungry = look(status(file(at: noon, 90, [.food: 12])))
        XCTAssertTrue(hungry.statusLeads)
        XCTAssertEqual(hungry.button, .feed)
        XCTAssertNotNil(hungry.subline)
        XCTAssertNil(hungry.statusTimer)

        // Голоден, но есть просьба: ведёт просьба — без кнопки статуса.
        let asked = look(status(file(at: noon, 90, [.food: 12])), ask: "Почеши за ушком?")
        XCTAssertFalse(asked.statusLeads)
        XCTAssertEqual(asked.headline, "Подпись")
        XCTAssertNil(asked.button)
        XCTAssertNil(asked.subline)
        XCTAssertEqual(asked.mediumBars, 2)

        // Всё хорошо: прежняя подпись настроения, три шкалы.
        let fine = look(status(file()))
        XCTAssertFalse(fine.statusLeads)
        XCTAssertEqual(fine.headline, "Подпись")
        XCTAssertNil(fine.button)
        XCTAssertEqual(fine.mediumBars, 3)

        // Мёртвый кадр кнопку не даёт, даже если в статусе она есть.
        XCTAssertNil(look(status(file(at: noon, 90, [.food: 12])), alive: false).button)

        // Кнопка только у действия с action (не «Открыть»).
        var open = status(file(at: noon, 90, [.food: 12]))
        open.act = .open
        XCTAssertNil(look(open).button)
    }

    // MARK: островок

    private func input(_ now: Double = noon) -> IslandInput {
        IslandInput(now: now, name: "Шиба", alive: true, outlook: IslandOutlook())
    }

    func testIslandBathOverridesQuiet() {
        var f = file()
        f.pet.bathUntil = noon + 300
        let st = status(f)
        let show = IslandEvents.show(input())
        let p = IslandLook.plan(show, input(), status: st, statusAt: { status(f, at: $0) })
        XCTAssertEqual(p?.now.busy, .bath)
        XCTAssertEqual(p?.now.glyph, .bath)
        XCTAssertEqual(p?.now.trailing, .timer)
        XCTAssertEqual(p?.now.timerEnd, noon + 300)
        XCTAssertEqual(p?.stale, noon + 300)
        XCTAssertFalse(p?.now.actsInPlace ?? true, "в ванне — «Открыть», не действие")
        XCTAssertNotEqual(p?.next?.busy, .bath)
    }

    func testIslandStrongEventWins() {
        var f = file()
        f.pet.bathUntil = noon + 300
        var i = input()
        i.trip = IslandTrip(from: noon - 600, backAt: noon + 1800, place: "Маяк")
        let show = IslandEvents.show(i)
        let p = IslandLook.plan(show, i, status: status(f), statusAt: { status(f, at: $0) })
        XCTAssertEqual(p?.now.kind, .trip, "поход главнее ванны")
        XCTAssertEqual(p?.now.pose, .run)
    }

    func testIslandEmptyWhenNothing() {
        let f = file()
        XCTAssertNil(IslandLook.plan(IslandEvents.show(input()), input(), status: status(f),
                                     statusAt: { status(f, at: $0) }), "ни события, ни занятия — островок пустеет")
    }

    func testStatusCardNeed() {
        let st = status(file(at: noon, 90, [.food: 12]))
        let c = IslandLook.statusCard(st, at: noon)
        XCTAssertEqual(c.glyph, .bowl)
        XCTAssertEqual(c.act, .feed)
        XCTAssertTrue(c.actsInPlace)
        XCTAssertEqual(c.trailing, .text)
        XCTAssertEqual(c.compact, "12 %")
        // Старый JSON ContentState без новых полей читается.
        let old = try? JSONDecoder().decode(IslandCard.self, from: Data("""
        {"glyph":"calm","title":"Всё хорошо","compact":"","pose":"sit","from":0,"act":"open"}
        """.utf8))
        XCTAssertNotNil(old)
        XCTAssertNil(old?.busy)
    }

    // MARK: кадры пса

    func testNewPosesFrames() {
        for p in [DogPose.run, .bath] {
            let fs = PixelDog.frames(p)
            XCTAssertGreaterThanOrEqual(fs.count, 2, "\(p): кадры меняются")
            for fr in fs {
                XCTAssertEqual(fr.count, PixelDog.height, "\(p)")
                for row in fr { XCTAssertEqual(row.count, PixelDog.width, "\(p): \(row)") }
            }
            XCTAssertNotEqual(fs[0], fs[1])
        }
        XCTAssertTrue(PixelDog.cells(.bath, frame: 0).contains { $0.ink == .zz }, "моется — с пузырями")
        XCTAssertTrue(PixelDog.cells(.sleep, frame: 0).contains { $0.ink == .zz }, "спит — с zzz")
        XCTAssertFalse(IslandEvents.askVisible(file().pet, .run), "бежит — просьбы нет")
    }
}
