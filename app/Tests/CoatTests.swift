// Облик шерсти от ухода (Coat): монотонность по уходу, инерция, гистерезис стадий, детерминизм,
// мёртвый и новорождённый питомец, пустой журнал, реплики coat_* в lines.json.
// Историю прогоняем через PetRunner (события ev.* пишет catchUp), остальные шкалы держим на 90,
// а сердца полными — чтобы мерить только шерсть. Гоняется и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let cT0: Double = 1_760_000_000

/// Прожить от t0 столько суток: шаг 30 мин, ванна и поглаживание по расписанию (nil — никогда).
@discardableResult
private func cLive(_ f: inout SaveFile, from t0: Double, days: Double, bathEveryH: Double?,
                   petEveryH: Double? = nil) -> Double {
    let r = Catalog.rules
    var t = t0
    var nextBath = bathEveryH.map { t0 + $0 * 3600 } ?? .infinity
    var nextPet = petEveryH.map { t0 + $0 * 3600 } ?? .infinity
    let end = t0 + days * 86400
    while t < end {
        t += 1800
        PetRunner.catchUp(&f, now: t)
        for n in [Need.food, .energy, .fun, .love, .walk] { f.pet.needs[n] = 90 }
        f.pet.hearts = PetEngine.maxHearts(f.pet, r)
        if t >= nextBath, let h = bathEveryH {
            _ = PetRunner.apply(.bath, source: .app, to: &f, now: t)
            nextBath += h * 3600
        }
        if t >= nextPet, let h = petEveryH {
            _ = PetRunner.apply(.pet, source: .app, to: &f, now: t)
            nextPet += h * 3600
        }
    }
    return t
}

private func cFile(days: Double, bathEveryH: Double?, petEveryH: Double? = nil) -> (SaveFile, Double) {
    var f = SaveFile.fresh(now: cT0)
    let t = cLive(&f, from: cT0, days: days, bathEveryH: bathEveryH, petEveryH: petEveryH)
    return (f, t)
}

private func cAssertInRange(_ l: CoatLook, _ msg: String, file: StaticString = #filePath, line: UInt = #line) {
    for (name, v) in [("groom", l.groom), ("fluff", l.fluff), ("dirt", l.dirt), ("shine", l.shine), ("mats", l.mats)] {
        XCTAssertFalse(v.isNaN, "\(msg): \(name) NaN", file: file, line: line)
        XCTAssertTrue((0...1).contains(v), "\(msg): \(name)=\(v)", file: file, line: line)
    }
    XCTAssertEqual(l.hintKey, "coat_" + l.stage.rawValue, msg, file: file, line: line)
}

final class CoatTests: XCTestCase {

    // MARK: монотонность

    func testMoreCareIsMoreGroomed() {
        var looks: [CoatLook] = []
        for every in [24.0, 48, 96, nil] as [Double?] {
            let (f, t) = cFile(days: 10, bathEveryH: every)
            let l = Coat.look(f, now: t)
            cAssertInRange(l, "ванна раз в \(every.map { "\($0) ч" } ?? "никогда")")
            looks.append(l)
        }
        for i in 1..<looks.count {
            XCTAssertGreaterThanOrEqual(looks[i - 1].groom, looks[i].groom, "реже мыть — не ухоженнее (\(i))")
            XCTAssertGreaterThanOrEqual(looks[i - 1].stage.rank, looks[i].stage.rank, "стадия тоже (\(i))")
            XCTAssertLessThanOrEqual(looks[i - 1].fluff, looks[i].fluff, "и не глаже (\(i))")
        }
        XCTAssertEqual(looks.first?.stage, .sleek, "моют каждый день — гладкий")
        XCTAssertEqual(looks.last?.stage, .matted, "неделю без ванны — колтуны")
        XCTAssertGreaterThan(looks[0].groom - looks[3].groom, 0.5)
        XCTAssertEqual(looks[3].dirt, 1, accuracy: 1e-9, "грязный сейчас")
        XCTAssertEqual(looks[3].shine, 0, accuracy: 1e-9, "грязь гасит блеск")
        XCTAssertGreaterThan(looks[3].mats, 0.5)
    }

    func testPettingHelpsALittle() {
        let (a, ta) = cFile(days: 10, bathEveryH: 96)
        let (b, tb) = cFile(days: 10, bathEveryH: 96, petEveryH: 3)
        XCTAssertEqual(ta, tb)
        let la = Coat.look(a, now: ta), lb = Coat.look(b, now: tb)
        XCTAssertGreaterThan(lb.groom, la.groom, "поглаживания помогают")
        XCTAssertLessThan(lb.groom - la.groom, 0.25, "но ванну не заменяют")
    }

    // MARK: инерция

    func testOneBathAfterAWeekOfDirtIsNotSleek() throws {
        var (f, t) = cFile(days: 8, bathEveryH: nil)
        let before = Coat.look(f, now: t)
        XCTAssertEqual(before.stage, .matted)
        XCTAssertTrue(PetRunner.apply(.bath, source: .app, to: &f, now: t).ok)
        let bathMin = Catalog.rules.bathMinutes.first ?? 60
        let after = Coat.look(f, now: t + bathMin * 60 + 60)
        cAssertInRange(after, "сразу после ванны")
        XCTAssertEqual(after.dirt, 0, accuracy: 1e-9, "грязь смывается сразу")
        XCTAssertGreaterThan(after.shine, 0, "блёстки после ванны")
        XCTAssertGreaterThan(after.groom, before.groom, "ванна помогает")
        XCTAssertLessThan(after.groom, Coat.edges[1], "но шерсть ещё не обычная")
        XCTAssertTrue([.matted, .shaggy].contains(after.stage), "\(after.stage)")
        XCTAssertGreaterThan(after.fluff, 0.5, "всё ещё лохматый")

        // Неделя ежедневных ванн — гладкий.
        t = cLive(&f, from: t, days: 7, bathEveryH: 24)
        let week = Coat.look(f, now: t)
        XCTAssertEqual(week.stage, .sleek, "\(week.groom)")
        XCTAssertLessThan(week.fluff, after.fluff)
        XCTAssertEqual(week.mats, 0, accuracy: 1e-9)
    }

    func testOneMissedDayDoesNotRuinSleek() {
        var (f, t) = cFile(days: 10, bathEveryH: 24)
        XCTAssertEqual(Coat.look(f, now: t).stage, .sleek)
        t = cLive(&f, from: t, days: 2, bathEveryH: nil)
        let l = Coat.look(f, now: t)
        XCTAssertTrue([.sleek, .normal].contains(l.stage), "двое суток без ванны — не сразу лохматый: \(l.stage) \(l.groom)")
    }

    // MARK: гистерезис

    func testHysteresisAtEdge() {
        let h = Coat.hysteresis
        for (i, e) in Coat.edges.enumerated() {
            let lo = CoatStage.allCases[i], hi = CoatStage.allCases[i + 1]
            for d in [-h * 0.9, -0.001, 0, 0.001, h * 0.9] {
                XCTAssertEqual(Coat.stage(for: e + d, from: lo), lo, "у границы \(e)\(d) снизу держится \(lo)")
                XCTAssertEqual(Coat.stage(for: e + d, from: hi), hi, "у границы \(e)\(d) сверху держится \(hi)")
            }
            XCTAssertEqual(Coat.stage(for: e + h + 0.001, from: lo), hi, "за полосой вверх")
            XCTAssertEqual(Coat.stage(for: e - h - 0.001, from: hi), lo, "за полосой вниз")
        }
        XCTAssertEqual(Coat.stage(for: 0.95, from: .matted), .sleek, "скачок через стадии")
        XCTAssertEqual(Coat.stage(for: 0.0, from: .sleek), .matted)
        XCTAssertEqual(Coat.stage(for: 0.0), .matted)
        XCTAssertEqual(Coat.stage(for: 1.0), .sleek)
        XCTAssertEqual(CoatStage.allCases.map(\.rank), [0, 1, 2, 3])
    }

    func testTraceStageFollowsAutomaton() {
        let (f, t) = cFile(days: 10, bathEveryH: 48, petEveryH: 6)
        let tr = Coat.trace(f, now: t)
        XCTAssertGreaterThan(tr.points.count, 100)
        var st = Coat.stage(for: tr.points[0].groom)
        var flips = 0
        for p in tr.points.dropFirst() {
            let n = Coat.stage(for: p.groom, from: st)
            if n != st { flips += 1 }
            st = n
        }
        XCTAssertEqual(st, tr.stage)
        XCTAssertEqual(Coat.look(f, now: t).stage, tr.stage)
        XCTAssertLessThan(flips, 12, "за неделю стадия не мигает")
        for (a, b) in zip(tr.points, tr.points.dropFirst()) { XCTAssertLessThan(a.t, b.t) }
    }

    // MARK: детерминизм

    func testDeterministic() {
        let (a, ta) = cFile(days: 9, bathEveryH: 36, petEveryH: 5)
        let (b, tb) = cFile(days: 9, bathEveryH: 36, petEveryH: 5)
        XCTAssertNotEqual(a.petId, b.petId)
        XCTAssertEqual(Coat.look(a, now: ta), Coat.look(b, now: tb), "одинаковая история — одинаковый облик")
        XCTAssertEqual(Coat.look(a, now: ta), Coat.look(a, now: ta))
        let l0 = Coat.look(a, now: ta), l1 = Coat.look(a, now: ta + 60)
        XCTAssertEqual(l0.groom, l1.groom, accuracy: 0.005, "минута ничего не меняет")
        XCTAssertEqual(l0.stage, l1.stage)
        // Через JSON — то же самое.
        let data = try? JSONEncoder().encode(a)
        let back = data.flatMap { try? JSONDecoder().decode(SaveFile.self, from: $0) }
        XCTAssertNotNil(back)
        if let back { XCTAssertEqual(Coat.look(back, now: ta).stage, l0.stage) }
    }

    // MARK: края

    func testNewborn() {
        let f = SaveFile.fresh(now: cT0)
        XCTAssertTrue(f.journal.isEmpty)
        for dt in [0.0, 60, 3600, -600] {
            let l = Coat.look(f, now: cT0 + dt)
            cAssertInRange(l, "щенок +\(dt)")
            XCTAssertEqual(l.stage, .matted, "щенок «рваный», как look.stages[0]")
            XCTAssertLessThan(l.shine, 0.1)
        }
        let tr = Coat.trace(f, now: cT0)
        XCTAssertEqual(tr.points.count, 1)
    }

    func testEmptyJournal() {
        for clean in [0.0, 50, 100] {
            var f = SaveFile.fresh(now: cT0)
            f.createdT = cT0 - 30 * 86400
            f.pet.needs[.clean] = clean
            f.journal = []
            let l = Coat.look(f, now: cT0)
            cAssertInRange(l, "пустой журнал, чистота \(clean)")
        }
        var dirty = SaveFile.fresh(now: cT0), clean = SaveFile.fresh(now: cT0)
        dirty.createdT = cT0 - 30 * 86400
        clean.createdT = dirty.createdT
        dirty.pet.needs[.clean] = 0
        clean.pet.needs[.clean] = 100
        XCTAssertGreaterThan(Coat.look(clean, now: cT0).groom, Coat.look(dirty, now: cT0).groom)
    }

    func testDeadPet() {
        // Настоящая смерть: месяц без ухода.
        var f = SaveFile.fresh(now: cT0)
        PetRunner.catchUp(&f, now: cT0 + 30 * 86400)
        XCTAssertFalse(f.pet.alive)
        let l = Coat.look(f, now: cT0 + 30 * 86400)
        cAssertInRange(l, "умер")
        XCTAssertEqual(l, Coat.look(f, now: cT0 + 40 * 86400), "после смерти облик застыл")

        // Умер вчера посреди ухоженной жизни.
        var (g, t) = cFile(days: 9, bathEveryH: 24)
        g.pet.alive = false
        g.pet.diedAt = t - 86400
        let dead = Coat.look(g, now: t)
        cAssertInRange(dead, "умер вчера")
        XCTAssertEqual(dead, Coat.look(g, now: t + 5 * 86400))
        // Часы назад — не падаем.
        cAssertInRange(Coat.look(g, now: t - 3 * 86400), "часы назад")
    }

    // MARK: реплики

    func testCoatLines() throws {
        let lines = Lines.shared
        guard let widget = lines.sections["widget"], !widget.isEmpty else { throw XCTSkip("нет lines.json") }
        let island = lines.sections["island"] ?? [:]
        var ids = Set<String>()
        for st in CoatStage.allCases {
            let w = widget[st.lineKey] ?? []
            XCTAssertTrue((3...4).contains(w.count), "widget.\(st.lineKey): \(w.count)")
            for it in w {
                XCTAssertLessThanOrEqual(it.text.count, LineLimit.widget, it.id)
                XCTAssertTrue(it.id.hasPrefix("w.\(st.lineKey)."), it.id)
                XCTAssertTrue(ids.insert(it.id).inserted, it.id)
            }
            let i = island[st.lineKey] ?? []
            XCTAssertFalse(i.isEmpty, "island.\(st.lineKey)")
            for it in i {
                XCTAssertLessThanOrEqual(it.text.count, LineLimit.island, it.id)
                XCTAssertTrue(ids.insert(it.id).inserted, it.id)
            }
            let look = CoatLook(groom: 0.5, fluff: 0, dirt: 0, shine: 0, mats: 0, stage: st)
            XCTAssertTrue(w.map(\.text).contains(look.line(seed: "pet", at: cT0)), st.rawValue)
            XCTAssertTrue(i.map(\.text).contains(look.islandLine(seed: "pet", at: cT0)), st.rawValue)
            XCTAssertFalse(st.title.isEmpty)
        }
    }
}
