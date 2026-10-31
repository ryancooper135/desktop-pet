// «Команды» (Tricks.swift, волна 57): восемь команд и их клипы, детерминированный бросок и кривая шанса,
// засчёт не чаще gap, выучена ровно за свои 3–5 удач, открытие уровнем пса, щенку — только первые,
// когда нельзя (нет пса, гуляет, моется, спит, плохо), голодный/грустный слушается хуже,
// настроение без перезарядки «Погладить», монеты за выучку разово и за показ — в общем дневном потолке,
// задание дня «Покажи трюки», журнал без act.*, старое сохранение (и выученные трюки волны 8).
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000: ночью пёс спит, и команды закрыты.
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

/// Взрослый пёс уровня dog: открыто всё до этого уровня, щенячьего предела нет.
private func kAdult(dog: Int = 1, level: Double = 80) -> SaveFile {
    var f = kFile(level: level)
    f.growth.points = 40
    f.level.xp = DogLevel.xpTo(dog)
    return f
}

/// Выучить команду удачами подряд с шагом gap. Возвращает момент после последней.
@discardableResult
private func teach(_ t: Trick, _ f: inout SaveFile, from: Double) -> Double {
    var now = from
    for _ in 0..<t.needed {
        Tricks.attempt(t, in: &f, now: now, roll: 0)
        now += Tricks.gap
    }
    return now
}

private func teachOutcome(_ t: Trick, _ f: inout SaveFile, from: Double) -> TrickOutcome {
    var now = from
    var last: TrickOutcome?
    for _ in 0..<t.needed {
        last = Tricks.attempt(t, in: &f, now: now, roll: 0)
        now += Tricks.gap
    }
    return last!
}

/// Имена клипов породы из бандла приложения — по пути исходников.
private func clipNames(_ breed: String) throws -> Set<String> {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Pets/\(breed).clips.json")
    guard let data = try? Data(contentsOf: url) else { throw XCTSkip("нет \(url.path)") }
    let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let clips = try XCTUnwrap(obj["clips"] as? [String: Any])
    return Set(clips.keys)
}

final class TricksTests: XCTestCase {
    // MARK: каталог

    func testEightCommandsOrderTitlesAndLevels() {
        XCTAssertEqual(Trick.allCases.map(\.rawValue),
                       ["sit", "paw", "lie", "speak", "spin", "five", "play_dead", "crawl"])
        XCTAssertEqual(Trick.allCases.map(\.title),
                       ["Сидеть", "Лапу", "Лежать", "Голос", "Кружись", "Дай пять", "Притворись спящим", "Ползи"])
        XCTAssertEqual(Trick.allCases.map(\.needed), [3, 3, 4, 4, 4, 5, 5, 5], "3–5 удач, первые — быстрее")
        XCTAssertTrue(Trick.allCases.allSatisfy { (3...Tricks.maxNeeded).contains($0.needed) })
        XCTAssertEqual(Trick.allCases.map(\.level), [1, 1, 2, 3, 5, 7, 9, 12])
        XCTAssertEqual(Trick.allCases.map(\.level), Trick.allCases.map(\.level).sorted(), "открываются по порядку")
        XCTAssertEqual(Trick.playDead.kind, "trick.play_dead")
        XCTAssertEqual(Trick(kind: "trick.play_dead"), .playDead)
        XCTAssertEqual(Trick(kind: "trick.speak"), .speak)
        XCTAssertNil(Trick(kind: "pet"))
        XCTAssertNil(Trick(kind: "trick.fly"))
        XCTAssertNil(Trick(kind: "trick.bow"), "трюки волны 8 в сетку не возвращаются")
        XCTAssertEqual(Trick.sit.done, "Сидит!")
        for t in Trick.allCases {
            XCTAssertFalse(t.symbol.isEmpty, "\(t)")
            XCTAssertFalse(t.done.isEmpty, "\(t)")
            XCTAssertLessThanOrEqual(t.short.count, 10, "\(t): подпись под иконкой короткая")
        }
        XCTAssertEqual(Set(Trick.allCases.map(\.symbol)).count, Trick.allCases.count, "иконки разные")
        // Названия трюков по ключу сейва — и старых тоже (для «Воспоминаний»).
        XCTAssertEqual(Trick.title(raw: "paw"), "Лапу")
        XCTAssertEqual(Trick.title(raw: "bow"), "Поклон")
        XCTAssertEqual(Trick.title(raw: "jump"), "Прыжок")
        XCTAssertEqual(Trick.title(raw: "shake"), "Отряхнись")
        XCTAssertNil(Trick.title(raw: "fly"))
    }

    func testClipsExistInBothBreeds() throws {
        XCTAssertEqual(Trick.sit.clips, ["sit_in", "sit", "sit_out"])
        XCTAssertEqual(Trick.paw.clips, ["sit_in", "paw", "sit_out"])
        XCTAssertEqual(Trick.five.clips, ["sit_in", "high_five", "sit_out"])
        XCTAssertEqual(Trick.playDead.clips, ["death", "play_dead_out"], "притворился и встал")
        XCTAssertTrue(Trick.speak.clips.contains("bark"))
        XCTAssertTrue(Trick.crawl.clips.contains("crawl"))
        XCTAssertEqual(Trick.spin.clips, ["spin"])
        for breed in ["shiba", "husky"] {
            let names = try clipNames(breed)
            for t in Trick.allCases {
                for c in t.clips { XCTAssertTrue(names.contains(c), "\(breed): нет клипа \(c) для \(t)") }
            }
            for c in Tricks.failClips { XCTAssertTrue(names.contains(c), "\(breed): нет клипа промаха \(c)") }
        }
    }

    // MARK: бросок и шанс

    func testRollIsDeterministicAndUniform() {
        for i in 0..<50 {
            XCTAssertEqual(Tricks.roll(petId: "p", .sit, tries: i), Tricks.roll(petId: "p", .sit, tries: i))
        }
        XCTAssertNotEqual(Tricks.roll(petId: "p", .sit, tries: 1), Tricks.roll(petId: "q", .sit, tries: 1))
        XCTAssertNotEqual(Tricks.roll(petId: "p", .sit, tries: 1), Tricks.roll(petId: "p", .paw, tries: 1))
        let rolls = (0..<4000).map { Tricks.roll(petId: "pet-x", .spin, tries: $0) }
        XCTAssertTrue(rolls.allSatisfy { $0 >= 0 && $0 < 1 })
        let mean = rolls.reduce(0, +) / Double(rolls.count)
        XCTAssertEqual(mean, 0.5, accuracy: 0.03)
        let low = Double(rolls.filter { $0 < 0.3 }.count) / Double(rolls.count)
        XCTAssertEqual(low, 0.3, accuracy: 0.03, "новая команда выходит примерно в трети попыток")
    }

    func testChanceGrowsWithProgress() {
        for trick in [Trick.sit, .five] {
            var f = kAdult(dog: 12)
            XCTAssertEqual(Tricks.chance(trick, in: f), Tricks.baseChance, accuracy: 1e-9)
            var prev = Tricks.chance(trick, in: f)
            var now = kT0
            for _ in 0..<(trick.needed - 1) {
                Tricks.attempt(trick, in: &f, now: now, roll: 0)
                now += Tricks.gap
                let c = Tricks.chance(trick, in: f)
                XCTAssertGreaterThan(c, prev, "\(trick)")
                XCTAssertLessThan(c, Tricks.learnedChance, "\(trick)")
                prev = c
            }
            Tricks.attempt(trick, in: &f, now: now, roll: 0)
            XCTAssertTrue(Tricks.learned(trick, in: f))
            XCTAssertEqual(Tricks.chance(trick, in: f), Tricks.learnedChance)
        }
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

    // MARK: голодный и грустный

    func testHungryOrSadListensWorse() {
        let ok = kFile()
        XCTAssertNil(Tricks.distracted(ok, at: kT0))
        XCTAssertEqual(Tricks.chance(.sit, in: ok, at: kT0), Tricks.baseChance, accuracy: 1e-9)

        var hungry = kFile()
        hungry.pet.needs[.food] = 15
        XCTAssertEqual(Tricks.distracted(hungry, at: kT0), .food)
        XCTAssertEqual(Tricks.chance(.sit, in: hungry, at: kT0), Tricks.baseChance * Tricks.distractedFactor,
                       accuracy: 1e-9)
        XCTAssertEqual(Tricks.chance(.sit, in: hungry), Tricks.baseChance, accuracy: 1e-9, "без времени — без поправки")

        var sad = kFile()
        sad.pet.needs[.love] = 15
        XCTAssertEqual(Tricks.distracted(sad, at: kT0), .love)
        XCTAssertLessThan(Tricks.chance(.sit, in: sad, at: kT0), Tricks.chance(.sit, in: ok, at: kT0))

        // Выученную тоже делает реже, но всё равно чаще новой.
        var learned = kFile()
        teach(.sit, &learned, from: kT0)
        learned.pet.needs[.food] = 15
        let c = Tricks.chance(.sit, in: learned, at: kT0 + 600)
        XCTAssertEqual(c, Tricks.learnedChance * Tricks.distractedFactor, accuracy: 1e-9)
        XCTAssertGreaterThan(c, Tricks.baseChance)

        // Бросок, который у сытого проходит, у голодного — «Не понял…».
        let r = Tricks.baseChance * 0.8
        var a = kFile()
        XCTAssertTrue(Tricks.attempt(.sit, in: &a, now: kT0, roll: r).ok)
        var b = kFile()
        b.pet.needs[.food] = 15
        let o = Tricks.attempt(.sit, in: &b, now: kT0, roll: r)
        XCTAssertFalse(o.ok)
        XCTAssertNil(o.reason, "пробовал — просто отвлёкся")
    }

    // MARK: обучение

    func testLearnedAfterOwnNeededCountedSuccesses() {
        for trick in Trick.allCases {
            var f = kAdult(dog: 12)
            var now = kT0
            for i in 1..<trick.needed {
                let o = Tricks.attempt(trick, in: &f, now: now, roll: 0)
                XCTAssertTrue(o.ok, "\(trick)")
                XCTAssertTrue(o.counted, "\(trick)")
                XCTAssertEqual(o.progress, i, "\(trick)")
                XCTAssertFalse(o.learnedNow, "\(trick)")
                now += Tricks.gap
            }
            XCTAssertEqual(Tricks.rows(f).first { $0.trick == trick }?.fraction ?? 0,
                           Double(trick.needed - 1) / Double(trick.needed), accuracy: 1e-9)
            let last = Tricks.attempt(trick, in: &f, now: now, roll: 0)
            XCTAssertTrue(last.learnedNow, "\(trick)")
            XCTAssertEqual(last.progress, trick.needed)
            XCTAssertEqual(f.tricks[trick].learned, now)
            XCTAssertEqual(Tricks.rows(f).first { $0.trick == trick }?.fraction, 1)
            // Дальше выученная: удачи не «доучивают» и второй раз не выучивают.
            let again = Tricks.attempt(trick, in: &f, now: now + Tricks.gap, roll: 0)
            XCTAssertTrue(again.ok)
            XCTAssertFalse(again.learnedNow)
            XCTAssertEqual(again.progress, trick.needed)
            XCTAssertEqual(f.journal.filter { $0.kind == Tricks.learnKind }.count, 1, "\(trick)")
            XCTAssertEqual(f.journal.last { $0.kind == Tricks.learnKind }?.key, trick.rawValue)
        }
    }

    func testRepeatsWithinGapDoNotCount() {
        var f = kFile()
        XCTAssertTrue(Tricks.attempt(.sit, in: &f, now: kT0, roll: 0).counted)
        for k in 1..<10 {
            let o = Tricks.attempt(.sit, in: &f, now: kT0 + Double(k) * 1.5, roll: 0)
            XCTAssertTrue(o.ok, "команду выполнил")
            XCTAssertFalse(o.counted, "но чаще gap в счёт не идёт")
            XCTAssertEqual(o.progress, 1)
        }
        XCTAssertTrue(Tricks.attempt(.sit, in: &f, now: kT0 + Tricks.gap, roll: 0).counted)
        XCTAssertEqual(Tricks.progress(.sit, in: f), 2)
        XCTAssertEqual(f.journal.filter { $0.kind == Tricks.showKind }.count, 2, "в журнал — только засчитанные")
    }

    func testFailureChangesOnlyTries() {
        var f = kFile(level: 50)
        let before = f.pet.needs
        let o = Tricks.attempt(.sit, in: &f, now: kT0, roll: 0.99)
        XCTAssertFalse(o.ok)
        XCTAssertNil(o.reason, "пробовал, просто не понял")
        XCTAssertTrue(o.tried)
        XCTAssertEqual(o.love, 0)
        XCTAssertEqual(o.coins, 0)
        XCTAssertEqual(f.tricks[.sit].n, 0)
        XCTAssertEqual(f.tricks[.sit].tries, 1)
        XCTAssertEqual(f.pet.needs, before)
        XCTAssertNil(f.tricks.joyT)
        XCTAssertFalse(f.journal.contains { $0.kind.hasPrefix("trick.") })
    }

    // MARK: открытие уровнем

    func testUnlockByDogLevel() {
        var f = kAdult(dog: 1)
        XCTAssertEqual(DogLevel.level(f), 1)
        XCTAssertEqual(Tricks.rows(f).map(\.locked), [false, false, true, true, true, true, true, true])
        let o = Tricks.attempt(.lie, in: &f, now: kT0, roll: 0)
        XCTAssertFalse(o.ok)
        XCTAssertEqual(o.reason, Tricks.lockedReason)
        XCTAssertFalse(o.tried)
        XCTAssertEqual(f.tricks[.lie].tries, 0, "закрытую команду не пробуют")
        XCTAssertEqual(Tricks.reasonText(o.reason, for: .lie), "С уровня 2")
        XCTAssertEqual(Tricks.reasonText(Tricks.lockedReason, for: .crawl), "С уровня 12")

        for (dog, open) in [(2, 3), (3, 4), (5, 5), (7, 6), (9, 7), (12, 8)] {
            let g = kAdult(dog: dog)
            XCTAssertEqual(DogLevel.level(g), dog)
            XCTAssertEqual(Tricks.rows(g).filter { !$0.locked }.count, open, "уровень \(dog)")
        }
        var top = kAdult(dog: 12)
        var t = kT0
        for trick in Trick.allCases { t = teach(trick, &top, from: t) }
        XCTAssertEqual(Tricks.learnedCount(top), Trick.allCases.count)
        XCTAssertTrue(Tricks.rows(top).allSatisfy { $0.learned && !$0.locked && $0.fraction == 1 })
    }

    func testLearnedStaysOpenBelowLevel() {
        // Старый сейв или правка опыта: команда выучена, а уровень ниже — выученное не отнимаем.
        var f = kAdult(dog: 1)
        f.tricks[.crawl].learned = kT0 - 100
        f.tricks[.crawl].n = Trick.crawl.needed
        XCTAssertTrue(Tricks.unlocked(.crawl, in: f))
        XCTAssertFalse(Tricks.rows(f).first { $0.trick == .crawl }!.locked)
        XCTAssertTrue(Tricks.attempt(.crawl, in: &f, now: kT0, roll: 0).ok)
        XCTAssertTrue(Tricks.rows(f).first { $0.trick == .playDead }!.locked)
    }

    // MARK: когда нельзя

    func testGateReasonsAndSymbols() {
        let ok = kFile()
        XCTAssertNil(Tricks.gate(ok, at: kT0))
        XCTAssertNil(Tricks.gateSymbol(nil))

        var dead = kFile()
        dead.pet.alive = false
        XCTAssertEqual(Tricks.gate(dead, at: kT0), "dead")

        var away = kFile()
        away.pet.outing = Outing(from: kT0 - 600, until: kT0 + 3600, find: "stick")
        XCTAssertEqual(Tricks.gate(away, at: kT0), "away")
        XCTAssertEqual(Tricks.gateSymbol("away"), "figure.walk")

        var bath = kFile()
        bath.pet.bathUntil = kT0 + 600
        XCTAssertEqual(Tricks.gate(bath, at: kT0), "bathing")
        XCTAssertEqual(Tricks.gateSymbol("bathing"), "bubbles.and.sparkles.fill")

        var nap = kFile()
        nap.pet.napUntil = kT0 + 1800
        XCTAssertEqual(Tricks.gate(nap, at: kT0), "asleep")
        XCTAssertEqual(Tricks.gateSymbol("asleep"), "moon.zzz.fill")

        let night = kT0 - 9 * 3600 // 03:00 местного
        XCTAssertEqual(Tricks.gate(kFile(at: night), at: night), "asleep")

        var bad = kFile()
        bad.pet.hearts = 1
        XCTAssertEqual(Tricks.gate(bad, at: kT0), "unwell")
        for r in ["dead", "unwell", Tricks.loadingReason] { XCTAssertNotNil(Tricks.gateSymbol(r), r) }

        // Отказ не тратит попытку и не трогает пса; значок причины — на всех иконках.
        var f = nap
        let o = Tricks.attempt(.sit, in: &f, now: kT0, roll: 0)
        XCTAssertEqual(o.reason, "asleep")
        XCTAssertFalse(o.tried)
        XCTAssertTrue(f.tricks.isEmpty)
        XCTAssertEqual(Tricks.reasonText("asleep"), RefuseText.text("asleep"))
        XCTAssertEqual(Tricks.reasonText(Tricks.growReason), Tricks.growText)
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
        XCTAssertNil(f.pet.cooldowns["pet"], "команда не запрещает погладить")
        XCTAssertTrue(PetRunner.apply(.pet, source: .app, to: &f, now: kT0 + 1).ok)

        // Следующая засчитанная раньше joyGap — без прибавки, после — снова.
        var g = kFile(level: 50)
        Tricks.attempt(.sit, in: &g, now: kT0, roll: 0)
        XCTAssertEqual(Tricks.attempt(.sit, in: &g, now: kT0 + Tricks.gap, roll: 0).love, 0)
        XCTAssertGreaterThan(Tricks.attempt(.sit, in: &g, now: kT0 + Tricks.joyGap, roll: 0).love, 0)
    }

    func testLearnCheersPastJoyGap() {
        // Выучка — мимо перерыва настроения и вдвое щедрее обычной удачи.
        var f = kFile(level: 40)
        var now = kT0
        for _ in 0..<(Trick.sit.needed - 1) {
            Tricks.attempt(.sit, in: &f, now: now, roll: 0)
            now += Tricks.gap
        }
        XCTAssertLessThan(now, (f.tricks.joyT ?? 0) + Tricks.joyGap)
        let o = Tricks.attempt(.sit, in: &f, now: now, roll: 0)
        XCTAssertTrue(o.learnedNow)
        XCTAssertGreaterThan(o.love, 0)
    }

    func testNoActEntriesInJournal() {
        var f = kFile()
        var now = teach(.sit, &f, from: kT0)
        for _ in 0..<5 {
            Tricks.attempt(.paw, in: &f, now: now, roll: 0.99)
            now += 1
        }
        XCTAssertFalse(f.journal.contains { $0.kind.hasPrefix("act.") }, "команды — не уход: монеты и открытки их не видят")
        XCTAssertEqual(f.journal.filter { $0.kind == Tricks.showKind }.count, Trick.sit.needed)
        XCTAssertEqual(f.journal.filter { $0.kind == Tricks.learnKind }.count, 1)
        XCTAssertTrue(Economy.settle(&f).isEmpty, "settle ничего сверху не платит")
    }

    func testLearnCoinsOncePastCareCap() {
        var f = kFile()
        let wallet0 = f.econ.wallet.coins
        var now = kT0
        for _ in 0..<(Trick.sit.needed - 1) {
            XCTAssertEqual(Tricks.attempt(.sit, in: &f, now: now, roll: 0).coins, 0, "пока учится — монет нет")
            now += Tricks.gap
        }
        let learned = Tricks.attempt(.sit, in: &f, now: now, roll: 0)
        XCTAssertEqual(learned.coins, Tricks.learnCoins)
        XCTAssertEqual(f.econ.wallet.coins, wallet0 + Tricks.learnCoins + DogLevel.coinsPaid(f.level))
        XCTAssertEqual(f.econ.daily.care, 0, "потолок ухода не тратится")
        XCTAssertEqual(f.econ.daily.habits, 0, "и общий потолок шагов — тоже: выучка разовая")
        XCTAssertEqual(f.econ.lastEarn?.kind, "trick")
        XCTAssertEqual(f.econ.lastEarn?.coins, Tricks.learnCoins)
        XCTAssertEqual(f.econ.lastEarn?.capped, false)

        // Вечер, потолок ухода выбран: разовая награда всё равно целиком, иначе сгорела бы навсегда.
        let cap = EconomyConfig.shared.careDailyCap
        f.econ.daily.care = cap
        let w1 = f.econ.wallet.coins - DogLevel.coinsPaid(f.level)
        let paw = teachOutcome(.paw, &f, from: now + Tricks.gap)
        XCTAssertTrue(paw.learnedNow)
        XCTAssertEqual(paw.coins, Tricks.learnCoins)
        XCTAssertEqual(f.econ.wallet.coins, w1 + Tricks.learnCoins + DogLevel.coinsPaid(f.level))
        XCTAssertEqual(f.econ.daily.care, cap)
    }

    func testShowCoinsDailyAndSharedCap() {
        var f = kFile()
        var now = teach(.sit, &f, from: kT0)
        let w0 = f.econ.wallet.coins - DogLevel.coinsPaid(f.level)
        XCTAssertEqual(Tricks.showCoinsLeft(f, at: now), Tricks.showDaily)
        // Показ выученной: showCoins за засчитанный, не больше showDaily в сутки.
        var got = 0
        for _ in 0..<(Tricks.showDaily + 3) {
            got += Tricks.attempt(.sit, in: &f, now: now, roll: 0).coins
            now += Tricks.gap
        }
        XCTAssertEqual(got, Tricks.showDaily * Tricks.showCoins)
        XCTAssertEqual(f.tricks.showCoins, Tricks.showDaily)
        XCTAssertEqual(f.econ.daily.habits, Tricks.showDaily, "в общий дневной счётчик с шагами")
        XCTAssertEqual(f.econ.wallet.coins - DogLevel.coinsPaid(f.level), w0 + got)
        XCTAssertEqual(Tricks.showCoinsLeft(f, at: now), 0)
        // Незасчитанный повтор (чаще gap) — без монет, даже когда норма не выбрана.
        var g = kFile()
        let tg = teach(.sit, &g, from: kT0)
        XCTAssertEqual(Tricks.attempt(.sit, in: &g, now: tg, roll: 0).coins, Tricks.showCoins)
        XCTAssertEqual(Tricks.attempt(.sit, in: &g, now: tg + 1, roll: 0).coins, 0)

        // Новые сутки — норма заново.
        let tomorrow = kT0 + 86400
        XCTAssertEqual(Tricks.showCoinsLeft(f, at: tomorrow), Tricks.showDaily)
        XCTAssertEqual(Tricks.attempt(.sit, in: &f, now: tomorrow, roll: 0).coins, Tricks.showCoins)
        XCTAssertEqual(f.tricks.showCoins, Tricks.showCoins)
        XCTAssertEqual(f.tricks.day, DayKey.of(tomorrow))

        // Шаги выбрали общий потолок — за показ уже ничего.
        var h = kFile()
        let th = teach(.sit, &h, from: kT0)
        Economy.rollDay(&h.econ, day: DayKey.of(th))
        h.econ.daily.habits = EconomyConfig.shared.habitsCap
        let o = Tricks.attempt(.sit, in: &h, now: th, roll: 0)
        XCTAssertTrue(o.ok && o.counted)
        XCTAssertEqual(o.coins, 0)
        XCTAssertEqual(h.econ.daily.habits, EconomyConfig.shared.habitsCap, "потолок не перебрали")
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
        // Ласка от команды — тоже через свой перерыв от «сейчас», а не от метки из будущего.
        XCTAssertEqual(next.love, 0)
        XCTAssertGreaterThan(Tricks.attempt(.sit, in: &f, now: kT0 + Tricks.joyGap, roll: 0).love, 0)
    }

    // MARK: задание дня «Покажи трюки»

    func testDailyTaskShowTricks() {
        XCTAssertTrue(DailyTasks.pool.contains { $0.id == "tricks" && $0.kind == Tricks.showKind })
        XCTAssertEqual(DailyTasks.defaultNeed["tricks"], 3, "покажи 3 трюка")
        XCTAssertEqual(DailyTaskConfig.shared.need("tricks"), 3, "и в economy.json")
        XCTAssertEqual(DailyTaskText.name(DailyTask(id: "tricks", need: 3, coins: 10)), "Показать трюки 3 раза")
        XCTAssertEqual(DailyTaskText.emoji("tricks"), "🐾")

        var f = kFile()
        XCTAssertFalse(DailyTasks.available("tricks", f, level: 1), "не знает ни одной команды — задания нет")
        XCTAssertFalse(DailyTasks.candidates(f, level: 1).contains("tricks"))
        var now = teach(.sit, &f, from: kT0)
        XCTAssertTrue(DailyTasks.available("tricks", f, level: 1))

        // Засчитанные показы двигают задание; незасчитанные (чаще gap) и промахи — нет.
        f.tasks.started = true
        f.tasks.day = DayKey.of(now)
        f.tasks.seenSeq = f.seq
        f.tasks.items = [DailyTask(id: "tricks", need: 3, coins: 10)]
        f.tasks.allPaid = true // не добирать другие задания — проверяем только это
        Tricks.attempt(.sit, in: &f, now: now, roll: 0)
        Tricks.attempt(.sit, in: &f, now: now + 1, roll: 0)
        Tricks.attempt(.sit, in: &f, now: now + 2, roll: 0.99)
        XCTAssertEqual(f.tasks.items.first { $0.id == "tricks" }?.n, 1)
        now += Tricks.gap
        Tricks.attempt(.sit, in: &f, now: now, roll: 0)
        now += Tricks.gap
        Tricks.attempt(.sit, in: &f, now: now, roll: 0)
        let task = f.tasks.items.first { $0.id == "tricks" }
        XCTAssertEqual(task?.n, 3)
        XCTAssertTrue(task?.done ?? false)
        XCTAssertTrue(f.journal.contains { $0.kind == DailyTasks.doneKind && $0.key == "tricks" })
    }

    // MARK: сохранение

    func testSaveRoundTripAndOldFile() throws {
        var f = kFile()
        let empty = try JSONSerialization.jsonObject(with: JSONEncoder().encode(f)) as? [String: Any]
        XCTAssertNil(empty?["tricks"], "пустое не пишем")

        let now = teach(.sit, &f, from: kT0)
        Tricks.attempt(.sit, in: &f, now: now, roll: 0)
        Tricks.attempt(.paw, in: &f, now: kT0 + 3600, roll: 0.99)
        XCTAssertGreaterThan(f.tricks.showCoins, 0)
        let data = try JSONEncoder().encode(f)
        let back = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(back.tricks, f.tricks)
        XCTAssertTrue(Tricks.learned(.sit, in: back))
        XCTAssertEqual(back.tricks[.paw].tries, 1)
        XCTAssertEqual(back.tricks.showCoins, f.tricks.showCoins)
        XCTAssertEqual(back.tricks.day, f.tricks.day)

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

    func testOldWave8TricksKeptButNotInGrid() throws {
        // Сейв до волны 57: выучены «Сидеть», «Поклон» и «Отряхнись», «Прыжок» начат; поля day/showCoins нет.
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(kAdult(dog: 1))) as? [String: Any])
        obj["tricks"] = [
            "items": [
                "sit": ["n": 5, "t": kT0 - 900, "tries": 9, "learned": kT0 - 900],
                "bow": ["n": 5, "t": kT0 - 800, "tries": 7, "learned": kT0 - 800],
                "shake": ["n": 5, "t": kT0 - 700, "tries": 6, "learned": kT0 - 700],
                "jump": ["n": 2, "t": kT0 - 600, "tries": 4],
            ],
            "joyT": kT0 - 600,
        ]
        let data = try JSONSerialization.data(withJSONObject: obj)
        var f = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(f.tricks.items.count, 4, "старые ключи читаются")
        XCTAssertEqual(f.tricks.day, 0)
        XCTAssertEqual(f.tricks.showCoins, 0)
        XCTAssertTrue(Tricks.learned(.sit, in: f), "«Сидеть» осталась выученной")
        XCTAssertEqual(Tricks.progress(.sit, in: f), Trick.sit.needed, "старые 5 удач — не больше новой нормы")
        XCTAssertEqual(Tricks.learnedCount(f), 1, "в сетке считаются только восемь команд")
        XCTAssertEqual(Tricks.rows(f).map(\.trick), Trick.allCases)
        XCTAssertEqual(Tricks.attempt(.sit, in: &f, now: kT0, roll: 0).coins, Tricks.showCoins,
                       "старая выученная сразу идёт как показ, без повторной выучки")
        XCTAssertFalse(f.journal.contains { $0.kind == Tricks.learnKind })
        // Пересохранение старые ключи не теряет (откат на прошлую версию их увидит).
        let again = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertNotNil(again.tricks.items["bow"]?.learned)
        XCTAssertNotNil(again.tricks.items["shake"]?.learned)
        XCTAssertEqual(again.tricks.items["jump"]?.n, 2)
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

    // MARK: рост (Growth.perks)

    func testPuppyLimit() {
        var f = kFile()
        f.level.xp = DogLevel.xpTo(5)
        XCTAssertEqual(Growth.phase(f), .puppy)
        let limit = Growth.perks(f).trickLimit ?? 0
        XCTAssertEqual(limit, 2)
        XCTAssertEqual(Tricks.rows(f).map(\.young), Trick.allCases.indices.map { $0 >= limit })
        let o = Tricks.attempt(.lie, in: &f, now: kT0, roll: 0)
        XCTAssertFalse(o.ok)
        XCTAssertEqual(o.reason, Tricks.growReason, "щенку рано — важнее уровня")
        XCTAssertEqual(f.tricks[.lie].tries, 0, "щенок не пробует")
        XCTAssertEqual(Tricks.reasonText(o.reason, for: .lie), "Подрастёт — научится")
        XCTAssertTrue(Tricks.attempt(.paw, in: &f, now: kT0, roll: 0).ok)
        // Подрос — открыто дальше по уровню.
        f.growth.points = 40
        XCTAssertTrue(Tricks.rows(f).allSatisfy { !$0.young })
        XCTAssertTrue(Tricks.attempt(.lie, in: &f, now: kT0 + Tricks.gap, roll: 0).ok)
    }

    func testLearnedStaysForPuppy() {
        var f = kFile()
        f.tricks[.spin].learned = kT0 - 100
        f.tricks[.spin].n = Trick.spin.needed
        XCTAssertFalse(Tricks.young(.spin, in: f))
        XCTAssertTrue(Tricks.young(.lie, in: f))
    }

    func testTeenRefusesSometimesWithoutPenalty() {
        var f = kFile()
        f.growth.points = 20
        XCTAssertEqual(Growth.phase(f), .teen)
        var refused = 0, tried = 0
        var t = kT0
        let before = f.pet.needs
        for _ in 0..<400 {
            let o = Tricks.attempt(.sit, in: &f, now: t)
            tried += 1
            if o.refused {
                refused += 1
                XCTAssertFalse(o.ok)
                XCTAssertNil(o.reason, "пробовал — просто не захотел")
                XCTAssertFalse(o.counted)
                XCTAssertEqual(o.love, 0)
            }
            t += 1
        }
        XCTAssertEqual(f.tricks[.sit].tries, tried)
        let share = Double(refused) / Double(tried)
        XCTAssertGreaterThan(share, 0.08)
        XCTAssertLessThan(share, 0.22)
        XCTAssertGreaterThanOrEqual(f.pet.needs[.love] ?? 0, before[.love] ?? 0, "без штрафа")

        // Детерминированно: тот же файл — тот же исход.
        var a = kFile(); a.growth.points = 20
        var b = a
        let ra = (0..<50).map { Tricks.attempt(.sit, in: &a, now: kT0 + Double($0)).refused }
        let rb = (0..<50).map { Tricks.attempt(.sit, in: &b, now: kT0 + Double($0)).refused }
        XCTAssertEqual(ra, rb)
    }

    func testForcedRollNeverRefuses() {
        var f = kFile()
        f.growth.points = 20
        for i in 0..<100 { XCTAssertFalse(Tricks.attempt(.sit, in: &f, now: kT0 + Double(i), roll: 0).refused) }
    }

    func testAdultAndPuppyNeverRefuse() {
        for pts in [0.0, 40] {
            var f = kFile()
            f.growth.points = pts
            for i in 0..<200 { XCTAssertFalse(Tricks.attempt(.sit, in: &f, now: kT0 + Double(i)).refused, "\(pts)") }
        }
    }
}
