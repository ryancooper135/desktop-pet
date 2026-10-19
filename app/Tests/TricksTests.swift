// Трюки (Tricks.swift): детерминированный бросок и кривая шанса, засчёт не чаще gap, выучен ровно за needed,
// порядок открытия, когда нельзя (нет пса, гуляет, моется, спит, плохо), настроение без перезарядки «Погладить»,
// монеты за первый раз в дневном потолке, журнал без act.* и старое сохранение без поля tricks.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000: ночью пёс спит, и трюки закрыты.
private let kT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

/// Свежий файл на полдень, шкалы на level (по умолчанию всё хорошо).
private func kFile(_ petId: String = "trick-pet-1", at t: Double = kT0, level: Double = 80) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = petId
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = level }
    return f
}

/// Выучить трюк удачами подряд с шагом gap. Возвращает момент после последней.
@discardableResult
private func teach(_ t: Trick, _ f: inout SaveFile, from: Double) -> Double {
    var now = from
    for _ in 0..<Tricks.needed {
        Tricks.attempt(t, in: &f, now: now, roll: 0)
        now += Tricks.gap
    }
    return now
}

final class TricksTests: XCTestCase {
    // MARK: каталог

    func testOrderTitlesAndClips() {
        XCTAssertEqual(Trick.allCases.map(\.rawValue), ["sit", "lie", "bow", "jump", "shake", "speak"])
        XCTAssertEqual(Trick.allCases.map(\.title), ["Сидеть", "Лежать", "Поклон", "Прыжок", "Отряхнись", "Голос"])
        XCTAssertNil(Trick.sit.previous)
        XCTAssertEqual(Trick.lie.previous, .sit)
        XCTAssertEqual(Trick.speak.previous, .shake)
        XCTAssertEqual(Trick.sit.clips, ["sit_in", "sit", "sit_out"])
        XCTAssertEqual(Trick.lie.clips, ["lie_in", "lie", "lie_out"])
        XCTAssertEqual(Trick.sit.done, "Сидит!")
        XCTAssertEqual(Trick.bow.kind, "trick.bow")
        XCTAssertEqual(Trick(kind: "trick.speak"), .speak)
        XCTAssertNil(Trick(kind: "pet"))
        XCTAssertNil(Trick(kind: "trick.fly"))
        for t in Trick.allCases {
            XCTAssertFalse(t.clips.isEmpty, "\(t)")
            XCTAssertFalse(t.symbol.isEmpty, "\(t)")
            XCTAssertLessThanOrEqual(t.title.count, 10, "\(t): подпись короткая")
        }
    }

    // MARK: бросок и шанс

    func testRollIsDeterministicAndUniform() {
        for i in 0..<50 {
            XCTAssertEqual(Tricks.roll(petId: "p", .sit, tries: i), Tricks.roll(petId: "p", .sit, tries: i))
        }
        XCTAssertNotEqual(Tricks.roll(petId: "p", .sit, tries: 1), Tricks.roll(petId: "q", .sit, tries: 1))
        XCTAssertNotEqual(Tricks.roll(petId: "p", .sit, tries: 1), Tricks.roll(petId: "p", .lie, tries: 1))
        let rolls = (0..<4000).map { Tricks.roll(petId: "pet-x", .bow, tries: $0) }
        XCTAssertTrue(rolls.allSatisfy { $0 >= 0 && $0 < 1 })
        let mean = rolls.reduce(0, +) / Double(rolls.count)
        XCTAssertEqual(mean, 0.5, accuracy: 0.03)
        let low = Double(rolls.filter { $0 < 0.3 }.count) / Double(rolls.count)
        XCTAssertEqual(low, 0.3, accuracy: 0.03, "новый трюк выходит примерно в трети попыток")
    }

    func testChanceGrowsWithProgress() {
        var f = kFile()
        XCTAssertEqual(Tricks.chance(.sit, in: f), 0.3, accuracy: 1e-9)
        var prev = Tricks.chance(.sit, in: f)
        var now = kT0
        for _ in 0..<(Tricks.needed - 1) {
            Tricks.attempt(.sit, in: &f, now: now, roll: 0)
            now += Tricks.gap
            let c = Tricks.chance(.sit, in: f)
            XCTAssertGreaterThan(c, prev)
            XCTAssertLessThan(c, Tricks.learnedChance)
            prev = c
        }
        Tricks.attempt(.sit, in: &f, now: now, roll: 0)
        XCTAssertTrue(Tricks.learned(.sit, in: f))
        XCTAssertEqual(Tricks.chance(.sit, in: f), Tricks.learnedChance)
    }

    func testHonestRollsSameFileSameOutcome() {
        var a = kFile("same")
        var b = kFile("same")
        for i in 0..<12 {
            let ra = Tricks.attempt(.sit, in: &a, now: kT0 + Double(i) * 61)
            let rb = Tricks.attempt(.sit, in: &b, now: kT0 + Double(i) * 61)
            XCTAssertEqual(ra.ok, rb.ok, "попытка \(i)")
        }
        XCTAssertEqual(a.tricks, b.tricks)
        XCTAssertEqual(a.tricks[.sit].tries, 12)
    }

    // MARK: обучение

    func testLearnedAfterNeededCountedSuccesses() {
        var f = kFile()
        var now = kT0
        for i in 1..<Tricks.needed {
            let o = Tricks.attempt(.sit, in: &f, now: now, roll: 0)
            XCTAssertTrue(o.ok)
            XCTAssertTrue(o.counted)
            XCTAssertEqual(o.progress, i)
            XCTAssertFalse(o.learnedNow)
            now += Tricks.gap
        }
        let last = Tricks.attempt(.sit, in: &f, now: now, roll: 0)
        XCTAssertTrue(last.learnedNow)
        XCTAssertEqual(last.progress, Tricks.needed)
        XCTAssertEqual(f.tricks[.sit].learned, now)
        // Дальше выученный: удачи не «доучивают» и второй раз не выучивают.
        let again = Tricks.attempt(.sit, in: &f, now: now + Tricks.gap, roll: 0)
        XCTAssertTrue(again.ok)
        XCTAssertFalse(again.learnedNow)
        XCTAssertEqual(again.progress, Tricks.needed)
        XCTAssertEqual(f.journal.filter { $0.kind == "trick.learn" }.count, 1)
        XCTAssertEqual(f.journal.last { $0.kind == "trick.learn" }?.key, "sit")
    }

    func testRepeatsWithinGapDoNotCount() {
        var f = kFile()
        XCTAssertTrue(Tricks.attempt(.sit, in: &f, now: kT0, roll: 0).counted)
        for k in 1..<10 {
            let o = Tricks.attempt(.sit, in: &f, now: kT0 + Double(k) * 5, roll: 0)
            XCTAssertTrue(o.ok, "трюк сделал")
            XCTAssertFalse(o.counted, "но чаще gap в счёт не идёт")
            XCTAssertEqual(o.progress, 1)
        }
        XCTAssertTrue(Tricks.attempt(.sit, in: &f, now: kT0 + Tricks.gap, roll: 0).counted)
        XCTAssertEqual(Tricks.progress(.sit, in: f), 2)
    }

    func testFailureChangesOnlyTries() {
        var f = kFile(level: 50)
        let before = f.pet.needs
        let o = Tricks.attempt(.sit, in: &f, now: kT0, roll: 0.99)
        XCTAssertFalse(o.ok)
        XCTAssertNil(o.reason, "пробовал, просто не понял")
        XCTAssertTrue(o.tried)
        XCTAssertEqual(o.love, 0)
        XCTAssertEqual(f.tricks[.sit].n, 0)
        XCTAssertEqual(f.tricks[.sit].tries, 1)
        XCTAssertEqual(f.pet.needs, before)
        XCTAssertNil(f.tricks.joyT)
    }

    func testUnlockOrder() {
        var f = kFile()
        XCTAssertEqual(Tricks.rows(f).map(\.locked), [false, true, true, true, true, true])
        let o = Tricks.attempt(.lie, in: &f, now: kT0, roll: 0)
        XCTAssertFalse(o.ok)
        XCTAssertEqual(o.reason, Tricks.lockedReason)
        XCTAssertEqual(f.tricks[.lie].tries, 0, "закрытый трюк не пробуют")
        XCTAssertEqual(Tricks.reasonText(o.reason, for: .lie), "Сначала выучи «Сидеть»")

        let now = teach(.sit, &f, from: kT0)
        XCTAssertEqual(Tricks.rows(f).map(\.locked), [false, false, true, true, true, true])
        XCTAssertTrue(Tricks.attempt(.lie, in: &f, now: now, roll: 0).ok)
        var t = now
        for trick in Trick.allCases.dropFirst() { t = teach(trick, &f, from: t) }
        XCTAssertEqual(Tricks.learnedCount(f), Trick.allCases.count)
        XCTAssertTrue(Tricks.rows(f).allSatisfy { $0.learned && !$0.locked })
    }

    // MARK: когда нельзя

    func testGateReasons() {
        let ok = kFile()
        XCTAssertNil(Tricks.gate(ok, at: kT0))

        var dead = kFile()
        dead.pet.alive = false
        XCTAssertEqual(Tricks.gate(dead, at: kT0), "dead")

        var away = kFile()
        away.pet.outing = Outing(from: kT0 - 600, until: kT0 + 3600, find: "stick")
        XCTAssertEqual(Tricks.gate(away, at: kT0), "away")

        var bath = kFile()
        bath.pet.bathUntil = kT0 + 600
        XCTAssertEqual(Tricks.gate(bath, at: kT0), "bathing")

        var nap = kFile()
        nap.pet.napUntil = kT0 + 1800
        XCTAssertEqual(Tricks.gate(nap, at: kT0), "asleep")

        let night = kT0 - 9 * 3600 // 03:00 местного
        XCTAssertEqual(Tricks.gate(kFile(at: night), at: night), "asleep")

        var bad = kFile()
        bad.pet.hearts = 1
        XCTAssertEqual(Tricks.gate(bad, at: kT0), "unwell")

        // Отказ не тратит попытку и не трогает пса.
        var f = nap
        let o = Tricks.attempt(.sit, in: &f, now: kT0, roll: 0)
        XCTAssertEqual(o.reason, "asleep")
        XCTAssertFalse(o.tried)
        XCTAssertTrue(f.tricks.isEmpty)
        XCTAssertEqual(Tricks.reasonText("asleep"), RefuseText.text("asleep"))
    }

    // MARK: настроение и монеты

    func testSuccessCheersWithoutPetCooldown() {
        var f = kFile(level: 50)
        var petted = f
        _ = PetRunner.apply(.pet, source: .app, to: &petted, now: kT0)
        let full = (petted.pet.needs[.love] ?? 0) - 50
        XCTAssertGreaterThan(full, 0)

        let o = Tricks.attempt(.sit, in: &f, now: kT0, roll: 0)
        XCTAssertEqual(o.love, full * Tricks.loveShare, accuracy: 1e-6)
        XCTAssertEqual(f.pet.needs[.love] ?? 0, 50 + full * Tricks.loveShare, accuracy: 1e-6)
        XCTAssertNil(f.pet.cooldowns["pet"], "трюк не запрещает погладить")
        XCTAssertTrue(PetRunner.apply(.pet, source: .app, to: &f, now: kT0 + 1).ok)

        // Следующий засчитанный трюк раньше joyGap — без прибавки, после — снова.
        var g = kFile(level: 50)
        Tricks.attempt(.sit, in: &g, now: kT0, roll: 0)
        XCTAssertEqual(Tricks.attempt(.sit, in: &g, now: kT0 + Tricks.gap, roll: 0).love, 0)
        XCTAssertGreaterThan(Tricks.attempt(.sit, in: &g, now: kT0 + Tricks.joyGap, roll: 0).love, 0)
    }

    func testNoActEntriesInJournal() {
        var f = kFile()
        var now = teach(.sit, &f, from: kT0)
        for _ in 0..<5 {
            Tricks.attempt(.lie, in: &f, now: now, roll: 0.99)
            now += 1
        }
        XCTAssertFalse(f.journal.contains { $0.kind.hasPrefix("act.") }, "трюки — не уход: монеты и открытки их не видят")
        XCTAssertEqual(f.journal.filter { $0.kind.hasPrefix("trick.") }.count, 1)
        XCTAssertTrue(Economy.settle(&f).isEmpty, "settle ничего сверху не платит")
    }

    func testCoinsOnlyFirstLearnPastDailyCap() {
        var f = kFile()
        let wallet0 = f.econ.wallet.coins
        var now = kT0
        for _ in 0..<(Tricks.needed - 1) {
            XCTAssertEqual(Tricks.attempt(.sit, in: &f, now: now, roll: 0).coins, 0)
            now += Tricks.gap
        }
        let learned = Tricks.attempt(.sit, in: &f, now: now, roll: 0)
        XCTAssertEqual(learned.coins, Tricks.learnCoins)
        XCTAssertEqual(f.econ.wallet.coins, wallet0 + Tricks.learnCoins)
        XCTAssertEqual(f.econ.daily.care, 0, "потолок ухода не тратится")
        XCTAssertEqual(f.econ.lastEarn?.kind, "trick")
        XCTAssertEqual(f.econ.lastEarn?.coins, Tricks.learnCoins)
        XCTAssertEqual(f.econ.lastEarn?.capped, false)
        // Повтор выученного — без монет.
        XCTAssertEqual(Tricks.attempt(.sit, in: &f, now: now + Tricks.gap, roll: 0).coins, 0)
        XCTAssertEqual(f.econ.wallet.coins, wallet0 + Tricks.learnCoins)

        // Вечер, потолок ухода выбран: разовая награда всё равно целиком, иначе сгорела бы навсегда.
        let cap = EconomyConfig.shared.careDailyCap
        f.econ.daily.care = cap
        let w1 = f.econ.wallet.coins
        let lie = teachOutcome(.lie, &f, from: now + Tricks.gap)
        XCTAssertTrue(lie.learnedNow)
        XCTAssertEqual(lie.coins, Tricks.learnCoins)
        XCTAssertEqual(f.econ.wallet.coins, w1 + Tricks.learnCoins)
        XCTAssertEqual(f.econ.daily.care, cap)
    }

    func testClockBackDoesNotFreezeProgress() {
        var f = kFile(level: 50)
        let late = kT0 + 600
        let first = Tricks.attempt(.sit, in: &f, now: late, roll: 0)
        XCTAssertTrue(first.counted)
        XCTAssertGreaterThan(first.love, 0)
        // Часы перевели на 10 минут назад (волна 14): счёт не сбрасывается и не дарится — метки из будущего
        // прижаты к «сейчас», перерыв идёт заново. Ждать, пока часы догонят, не нужно.
        let back = Tricks.attempt(.sit, in: &f, now: kT0, roll: 0)
        XCTAssertFalse(back.counted)
        XCTAssertEqual(back.progress, 1)
        XCTAssertEqual(f.tricks[.sit].t, kT0)
        XCTAssertEqual(f.tricks.joyT, kT0)
        XCTAssertFalse(Tricks.attempt(.sit, in: &f, now: kT0 + 1, roll: 0).counted)
        let next = Tricks.attempt(.sit, in: &f, now: kT0 + Tricks.gap, roll: 0)
        XCTAssertTrue(next.counted)
        XCTAssertEqual(next.progress, 2)
        // Ласка от трюка — тоже через свой перерыв от «сейчас», а не от метки из будущего.
        XCTAssertEqual(next.love, 0)
        XCTAssertGreaterThan(Tricks.attempt(.sit, in: &f, now: kT0 + Tricks.joyGap, roll: 0).love, 0)
    }

    private func teachOutcome(_ t: Trick, _ f: inout SaveFile, from: Double) -> TrickOutcome {
        var now = from
        var last: TrickOutcome?
        for _ in 0..<Tricks.needed {
            last = Tricks.attempt(t, in: &f, now: now, roll: 0)
            now += Tricks.gap
        }
        return last!
    }

    // MARK: сохранение

    func testSaveRoundTripAndOldFile() throws {
        var f = kFile()
        let empty = try JSONSerialization.jsonObject(with: JSONEncoder().encode(f)) as? [String: Any]
        XCTAssertNil(empty?["tricks"], "пустое не пишем")

        teach(.sit, &f, from: kT0)
        Tricks.attempt(.lie, in: &f, now: kT0 + 3600, roll: 0.99)
        let data = try JSONEncoder().encode(f)
        let back = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(back.tricks, f.tricks)
        XCTAssertTrue(Tricks.learned(.sit, in: back))
        XCTAssertEqual(back.tricks[.lie].tries, 1)

        // Старый файл без поля — пусто, остальное на месте.
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj["tricks"] = nil
        let old = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertTrue(old.tricks.isEmpty)
        XCTAssertEqual(old.petId, f.petId)
        // Битое поле — тоже пусто, а не ошибка чтения.
        obj["tricks"] = "мусор"
        let broken = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertTrue(broken.tricks.isEmpty)
        XCTAssertEqual(broken.econ, f.econ)
    }

    func testStartOverForgetsTricks() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-tricks")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: kT0)
        try store.mutate { (f: inout SaveFile) -> Void in
            for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
            teach(.sit, &f, from: kT0)
        }
        XCTAssertTrue(try XCTUnwrap(store.read()).tricks[.sit].learned != nil)
        try store.startOver(now: kT0 + 600)
        XCTAssertTrue(try XCTUnwrap(store.read()).tricks.isEmpty, "новый щенок учится с нуля")
    }
}
