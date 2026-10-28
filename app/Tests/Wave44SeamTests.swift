// Волна 44 N: свежий взгляд на стыки волн 42–43 (задания дня, просьбы пса, награды записи).
// (1) Старый сейв без поля asks: первая запись после обновления не платит за сегодняшние действия, сделанные
//     до того, как просьбы появились (их никто не видел). (2) Окно просьбы не переходит через полночь: в полночь
//     расписание сменяется, и просьба «ещё 40 мин» в 23:20 пропадала невыполнимой. (3) Задание и просьба,
//     закрытые одним действием, — обе выплаты и оба опыта в ту же запись (страховка порядка settleRewards).
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000.
private let nT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

/// Пёс уровня lvl, бодрый, учёт уровня заведён; достижения уже получены — считаем только монеты заданий и просьб.
private func nFile(level lvl: Int = 1, at t: Double = nT0, pet: String = "seam-pet-44") -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = pet
    for n in Need.allCases { f.pet.needs[n] = 90 }
    DogLevel.settle(&f, now: t)
    f.level.xp = DogLevel.xpTo(lvl)
    f.level.paidLevel = lvl
    f.shardLog.once += Achievements.all.map { Achievements.key($0.id) }
    return f
}

private func count(_ f: SaveFile, _ kind: String) -> Int { f.journal.filter { $0.kind == kind }.count }

final class Wave44SeamTests: XCTestCase {

    override func setUp() {
        super.setUp()
        DogAsks.enabled = true
        DailyTasks.enabled = true
    }

    override func tearDown() {
        Clock.zoneOverride = nil
        DogAsks.enabled = true
        DailyTasks.enabled = true
        super.tearDown()
    }

    // MARK: 1. Старый сейв без asks

    /// Сейв до волны 43 K: сегодня уже гладили, кормили, играли — в часы, на которые выпали бы просьбы.
    /// Первая запись после обновления заводит просьбы, но за прошлые действия не платит: плашки тогда не было.
    func testOldSaveDoesNotPayForActsBeforeAsksExisted() {
        var day = DayKey.of(nT0)
        var starts: [Double] = []
        for d in day..<(day + 30) {
            let s = DogAsks.schedule(nFile(at: DayKey.start(d) + 8 * 3600), day: d)
            if s.count >= 2 { day = d; starts = s; break }
        }
        XCTAssertGreaterThanOrEqual(starts.count, 2, "нашёлся день с парой просьб")
        var f = nFile(at: DayKey.start(day) + 8 * 3600)
        f.asks = DogAsksLog()
        // Каждое окно — все шесть дел (какое бы пёс ни попросил).
        for s in starts {
            for (_, kind) in DogAsks.kinds { f.log(kind, t: s + 120, source: .app, ok: true) }
        }
        let coins = f.econ.wallet.coins
        let now = DayKey.start(day + 1) - 60
        DogAsks.settle(&f, now: now)
        XCTAssertTrue(f.asks.started)
        XCTAssertEqual(f.asks.total, 0, "просьб до обновления не было — и выплат за них нет")
        XCTAssertEqual(count(f, DogAsks.doneKind), 0)
        XCTAssertEqual(f.econ.wallet.coins, coins)

        // После обновления всё как обычно: следующий день, просьба в окне — платится.
        let next = DogAsks.schedule(f, day: day + 1)
        guard let s = next.first else { return }
        DogAsks.settle(&f, now: s)
        guard let a = f.asks.items.first(where: { $0.start == s }), a.real, let k = a.kind,
              let kind = DogAsks.kinds.first(where: { $0.id == k })?.kind else { return }
        f.log(kind, t: s + 60, source: .app, ok: true)
        DogAsks.settle(&f, now: s + 61)
        XCTAssertEqual(f.asks.total, 1, "новые записи после обновления засчитываются")
    }

    /// То же через настоящий путь записи: обновился и сразу что-то сделал — платит только новая просьба,
    /// если окно открыто сейчас, а не старые записи.
    func testOldSaveFirstApplyCountsOnlyNewActs() {
        var day = DayKey.of(nT0)
        var starts: [Double] = []
        for d in day..<(day + 30) {
            let s = DogAsks.schedule(nFile(at: DayKey.start(d) + 8 * 3600), day: d)
            if s.count >= 2 { day = d; starts = s; break }
        }
        let now = DayKey.start(day + 1) - 60
        var f = nFile(at: DayKey.start(day) + 8 * 3600)
        f.asks = DogAsksLog()
        for s in starts {
            for (_, kind) in DogAsks.kinds { f.log(kind, t: s + 120, source: .app, ok: true) }
        }
        _ = PetRunner.apply(.pet, source: .app, to: &f, now: now)
        XCTAssertEqual(f.asks.day, day)
        XCTAssertTrue(f.journal.filter { $0.kind == DogAsks.doneKind }.allSatisfy { $0.t >= now },
                      "дела до обновления не закрывают просьб")
    }

    // MARK: 2. Окно не переходит через полночь

    /// Хозяин ложится в 2:00: просьба в 23:30 с окном до 00:30 возможна по сну, но в полночь расписание сменяется —
    /// и сделанное в 00:10 по плашке «ещё 20 мин» не засчитывалось. Каждая просьба должна быть выполнима всё окно.
    func testEveryAskIsPayableThroughItsWholeWindow() {
        let cfg = DogAskConfig.shared
        let day0 = DayKey.of(nT0)
        var checked = 0
        for d in day0..<(day0 + 120) {
            var f = nFile(at: DayKey.start(d) + 9 * 3600)
            f.owner.bedMin = 2 * 60
            f.owner.wakeMin = 10 * 60
            let starts = DogAsks.schedule(f, day: d)
            // Проверяем последнюю просьбу дня — только она может задеть полночь.
            guard let s = starts.last else { continue }
            DogAsks.settle(&f, now: s)
            guard let a = f.asks.items.first(where: { $0.start == s }), a.real, let k = a.kind,
                  let kind = DogAsks.kinds.first(where: { $0.id == k })?.kind else { continue }
            let t = s + cfg.window - 120
            f.log(kind, t: t, source: .app, ok: true)
            DogAsks.settle(&f, now: t + 1)
            checked += 1
            XCTAssertEqual(f.asks.total, 1, "просьба \(s) (день \(d)) выполнена в окне в \(t) — не засчитана")
        }
        XCTAssertGreaterThan(checked, 20, "проверено достаточно дней")
    }

    /// Расписание само: окно целиком внутри своих суток (до полуночи), и при позднем сне хозяина тоже.
    func testScheduleWindowEndsBeforeMidnight() {
        let cfg = DogAskConfig.shared
        let day0 = DayKey.of(nT0)
        for bed in [23 * 60, 0, 60, 2 * 60, 4 * 60] {
            var f = nFile()
            f.owner.bedMin = bed
            f.owner.wakeMin = (bed + 8 * 60) % 1440
            for d in day0..<(day0 + 60) {
                for s in DogAsks.schedule(f, day: d) {
                    XCTAssertEqual(DayKey.of(s + cfg.window - 60), d, "окно просьбы \(s) уходит в следующие сутки")
                }
            }
        }
    }

    // MARK: 3. Задание и просьба одним действием

    /// Ласка закрывает и задание «погладить», и просьбу «почеши за ушком»: обе выплаты, обе записи и опыт за обе —
    /// в ту же запись (DailyTasks → DogAsks → DogLevel), повтор settle ничего не добавляет.
    func testTaskAndAskClosedByOneAction() {
        var f = nFile(level: 3)
        f.pet.needs[.love] = 40
        let s = nT0 + 60
        DailyTasks.settle(&f, now: s)
        DogAsks.settle(&f, now: s)
        f.tasks.items = [DailyTask(id: "pet", need: 1, coins: 25)]
        f.asks.items = [DogAsk(start: s, kind: "pet", coins: 10)]
        let coins = f.econ.wallet.coins
        let xp = f.level.xp
        XCTAssertTrue(PetRunner.apply(.pet, source: .app, to: &f, now: s + 120).ok)
        XCTAssertEqual(count(f, DailyTasks.doneKind), 1)
        XCTAssertEqual(count(f, DogAsks.doneKind), 1)
        XCTAssertNotNil(f.tasks.last)
        XCTAssertNotNil(f.asks.last)
        XCTAssertGreaterThanOrEqual(f.econ.wallet.coins - coins, 25 + 10, "монеты и задания, и просьбы")
        XCTAssertGreaterThanOrEqual(f.level.xp - xp, 10, "опыт за task.done и ask.done той же записью")
        let after = f
        PetRunner.settleRewards(&f, now: s + 125)
        XCTAssertEqual(f.econ.wallet, after.econ.wallet, "повторный settle не платит")
        XCTAssertEqual(f.level.xp, after.level.xp)
    }
}
