// Характер (Traits) и мысли вслух (PetMind): учёт ухода не чаще раза в полчаса, окно 7 дней, «ещё складывается»,
// черты от доли игр, ласк и купаний, отклик на тап, баланс не трогается, доля воспоминаний и черт в репликах,
// строка Presenter в спокойное время. Хозяин с поясом 0. Гоняется и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let tT0: Double = 1_760_000_000          // 08:53 UTC
private let tDay: Double = 86400

private func tFresh(_ t: Double = tT0) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.owner.tzOffsetMin = 0
    return f
}

/// Уход по дням: по каждому виду n раз в день с шагом в час (все засчитываются).
private func tCare(_ f: inout SaveFile, days: Int, perDay: [String: Int], from t0: Double = tT0) {
    for d in 0..<days {
        var t = t0 + Double(d) * tDay
        for (kind, n) in perDay.sorted(by: { $0.key < $1.key }) {
            for _ in 0..<n {
                f.log("act.\(kind)", t: t, ok: true)
                t += 3600
            }
        }
    }
    f.pet.t = t0 + Double(days - 1) * tDay + 12 * 3600
}

final class TraitsTests: XCTestCase {

    // MARK: учёт

    func testTallyCountsOkActsWithGap() {
        var f = tFresh()
        f.log("act.pet", t: tT0, ok: true)
        f.log("act.pet", t: tT0 + 60, ok: true)          // серия — не считается
        f.log("act.pet", t: tT0 + 31 * 60, ok: true)
        f.log("act.play", t: tT0 + 120, ok: false)       // не вышло
        f.log("act.feed", t: tT0 + 180, ok: true)        // еда — не характер
        f.log("act.walk", t: tT0 + 240, ok: true)
        f.pet.t = tT0 + 3600
        Traits.update(&f)
        XCTAssertEqual(Traits.counts(f, at: tT0 + 3600), ["pet": 2, "walk": 1])
        XCTAssertEqual(f.care.seq, f.seq)
        let once = f.care
        Traits.update(&f)
        XCTAssertEqual(f.care, once, "повторный разбор ничего не добавляет")

        // Новые записи — по seq.
        f.log("act.bath", t: tT0 + 4000, ok: true)
        Traits.update(&f)
        XCTAssertEqual(Traits.total(f, at: tT0 + 4000), 4)
    }

    func testWindowIsSevenDays() {
        var f = tFresh()
        tCare(&f, days: 10, perDay: ["play": 2])
        Traits.update(&f)
        let now = f.pet.t
        XCTAssertEqual(Traits.counts(f, at: now)["play"], 14, "7 дней по 2")
        XCTAssertLessThanOrEqual(f.care.days.count, Traits.windowDays + 1, "старые дни выкидываются")
    }

    // MARK: черты

    func testTooLittleCareIsStillForming() {
        var f = tFresh()
        tCare(&f, days: 1, perDay: ["play": 5, "pet": 3])
        Traits.update(&f)
        XCTAssertNil(Traits.scores(f, at: f.pet.t))
        XCTAssertNil(Traits.lead(f, at: f.pet.t))
        XCTAssertNil(Traits.summary(f, at: f.pet.t))
        XCTAssertEqual(Traits.tapKind(f, at: f.pet.t), "tap")
        XCTAssertEqual(Traits.total(f, at: f.pet.t), 8)
    }

    func testPlayfulDog() throws {
        var f = tFresh()
        tCare(&f, days: 7, perDay: ["play": 4, "walk": 2, "pet": 3, "bath": 1])
        Traits.update(&f)
        let now = f.pet.t
        let s = try XCTUnwrap(Traits.scores(f, at: now))
        XCTAssertEqual(s.map(\.axis), TraitAxis.allCases)
        XCTAssertEqual(Traits.lead(f, at: now), .playful)
        XCTAssertEqual(Traits.tapKind(f, at: now), "tap.playful")
        XCTAssertEqual(Traits.tapTrait("tap.playful"), .playful)
        XCTAssertNil(Traits.tapTrait("tap"))
        XCTAssertNil(Traits.tapTrait("pet"))
        let summary = try XCTUnwrap(Traits.summary(f, at: now))
        XCTAssertTrue(summary.hasPrefix("Очень игривый") || summary.hasPrefix("Игривый"), summary)
    }

    func testCuddlyAndScruffy() throws {
        var f = tFresh()
        tCare(&f, days: 7, perDay: ["pet": 6, "play": 2, "walk": 1])
        Traits.update(&f)
        let traits = Set(Traits.visibleTraits(f, at: f.pet.t).compactMap(\.trait))
        XCTAssertTrue(traits.contains(.cuddly), "\(traits)")
        XCTAssertTrue(traits.contains(.scruffy), "без ванны и щётки — сорванец")
        XCTAssertFalse(traits.contains(.tidy))
        let summary = try XCTUnwrap(Traits.summary(f, at: f.pet.t))
        XCTAssertTrue(summary.contains(" и "), summary)
    }

    /// Обычный день ухода — характер ровный, черт нет.
    func testEvenCareHasNoTraits() throws {
        var f = tFresh()
        tCare(&f, days: 7, perDay: ["pet": 4, "play": 2, "walk": 1, "bath": 1, "brush": 1])
        Traits.update(&f)
        let s = try XCTUnwrap(Traits.scores(f, at: f.pet.t))
        XCTAssertTrue(s.allSatisfy { $0.trait == nil }, "\(s.map { ($0.axis, $0.score) })")
        XCTAssertNil(Traits.lead(f, at: f.pet.t))
    }

    func testEveryTraitHasTitlesClipsAndLines() throws {
        let lines = Lines.shared
        let hasLines = !(lines.sections["widget"] ?? [:]).isEmpty
        for t in Trait.allCases {
            XCTAssertFalse(t.title.isEmpty)
            XCTAssertFalse(t.strongTitle.isEmpty)
            XCTAssertFalse(t.hint.isEmpty)
            XCTAssertFalse(Traits.tapClips(t).isEmpty)
            guard hasLines else { continue }
            for section in ["widget", "island"] {
                let pool = try XCTUnwrap(lines.sections[section]?[t.lineKey], "\(section).\(t.lineKey)")
                XCTAssertGreaterThanOrEqual(pool.count, 2)
            }
        }
        for a in TraitAxis.allCases { XCTAssertNotEqual(a.plus, a.minus) }
    }

    /// Черты — только про слова и анимации: учёт не меняет ни нужд, ни монет, ни ядра.
    func testTallyDoesNotTouchBalance() {
        var f = tFresh()
        tCare(&f, days: 7, perDay: ["play": 5])
        let pet = f.pet, econ = f.econ, seq = f.seq
        Traits.update(&f)
        Memories.update(&f)
        XCTAssertEqual(f.pet, pet)
        XCTAssertEqual(f.econ, econ)
        XCTAssertEqual(f.seq, seq)
    }

    // MARK: мысли вслух

    /// Пёс с памятью и характером: по ходам бывают и воспоминания, и черта; мысли — меньшая часть ходов.
    func testMindMixesMemoriesAndTraits() {
        var f = tFresh()
        f.tricks[.sit].learned = tT0 + 100
        f.log("ev.back_home.cone", t: tT0 + 200, key: "cone")
        f.pet.finds["cone"] = 1
        tCare(&f, days: 7, perDay: ["play": 4, "walk": 2, "pet": 3, "bath": 1])
        Memories.update(&f)
        Traits.update(&f)
        let start = f.pet.t
        var memories = 0, traits = 0
        var said = Set<String>()
        let total = 400
        for k in 0..<total {
            let t = start + Double(k) * 2 * 3600
            switch PetMind.pick(f, at: t, tzOffsetMin: 0) {
            case .memory(let m)?:
                memories += 1
                said.insert(m.id)
            case .trait(let tr)?:
                traits += 1
                XCTAssertEqual(tr, .playful)
                XCTAssertLessThan(t - start, Double(Traits.windowDays) * tDay, "черта — пока уход в окне")
            case nil:
                break
            }
        }
        XCTAssertGreaterThan(traits, 0)
        XCTAssertEqual(said, ["met", "trick.sit", "walk.first"], "вспоминается всё по очереди")
        let share = Double(memories) / Double(total)
        XCTAssertGreaterThan(share, 0.15)
        XCTAssertLessThan(share, 0.35)
    }

    func testMindWithoutCareHasNoTrait() {
        let f = tFresh()
        for k in 0..<100 {
            let t = tT0 + 2 * tDay + Double(k) * 2 * 3600
            if case .trait? = PetMind.pick(f, at: t, tzOffsetMin: 0) { XCTFail("без ухода черты нет") }
        }
        XCTAssertNil(PetMind.line(f, at: tT0 + 60, tzOffsetMin: 0), "в первые сутки вспомнить нечего")
    }

    /// Presenter в спокойные дневные ходы берёт строку PetMind (пузырь и остров), в остальные — обычную.
    func testPresenterUsesMindLine() throws {
        guard !(Lines.shared.sections["widget"] ?? [:]).isEmpty else { throw XCTSkip("lines.json нет в бандле") }
        var f = tFresh()
        f.tricks[.sit].learned = tT0 + 100
        tCare(&f, days: 7, perDay: ["play": 4, "walk": 2, "pet": 3, "bath": 1])
        Memories.update(&f)
        Traits.update(&f)
        let r = Catalog.rules
        let owner = Owner(bedMin: r.bedMin, wakeMin: r.wakeMin, tzOffsetMin: 0)
        let day0 = (f.pet.t / tDay).rounded(.down) * tDay
        var used = 0
        for d in 0..<6 {
            for h in [11.0, 13, 15, 17] {
                let t = day0 + Double(d) * tDay + h * 3600
                var s = PetEngine.newPet(r, t: t)
                for n in Need.allCases { s.needs[n] = 100 }
                let snap = Presenter.make(file: f, pet: s, owner: owner, at: t)
                guard let mind = PetMind.line(f, at: t, tzOffsetMin: 0) else { continue }
                if snap.line == mind {
                    used += 1
                    XCTAssertLessThanOrEqual(mind.count, LineLimit.widget)
                }
            }
        }
        XCTAssertGreaterThan(used, 0, "мысли вслух доходят до пузыря")
    }
}
