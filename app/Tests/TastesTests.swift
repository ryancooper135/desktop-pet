// Вкусы (Tastes.swift): детерминизм от petId, разброс между питомцами, открытие ровно после K наблюдений,
// идемпотентная запись, бонус к шкалам поверх ядра, находка с прогулки и старое сохранение без поля tastes.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let tT0: Double = 1_760_000_000

/// Свежий файл с заданным petId, шкалы на level.
private func tFile(_ petId: String = "taste-pet-1", at t: Double = tT0, level: Double = 90) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = petId
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = level }
    return f
}

final class TastesTests: XCTestCase {
    // MARK: скрытые вкусы

    func testCandidatesFromConfig() {
        let food = Tastes.candidates(.food)
        XCTAssertTrue(food.contains("kibble"))
        XCTAssertTrue(food.contains("carrot"))
        XCTAssertFalse(food.contains("gold_bone"), "легендарное любят все — не кандидат")
        XCTAssertEqual(Tastes.candidates(.toy), ["ball", "squeaky", "rope", "laser", "robot"])
        XCTAssertEqual(Tastes.candidates(.find), Finds.all.map(\.id), "находки — как в конфиге и Finds")
        for c in TasteCategory.allCases { XCTAssertGreaterThanOrEqual(Tastes.candidates(c).count, 3, "\(c)") }
    }

    func testHiddenIsDeterministicFromPetId() {
        for i in 0..<30 {
            let id = "pet-\(i)"
            for c in TasteCategory.allCases {
                let a = Tastes.hidden(petId: id, c)
                let b = Tastes.hidden(petId: id, c)
                XCTAssertEqual(a.love, b.love)
                XCTAssertEqual(a.dislike, b.dislike)
                XCTAssertNotNil(a.love, "\(id) \(c): любимое есть")
                XCTAssertNotNil(a.dislike, "\(id) \(c): нелюбимое есть")
                XCTAssertNotEqual(a.love, a.dislike)
                XCTAssertTrue(Tastes.candidates(c).contains(a.love ?? ""))
                XCTAssertTrue(Tastes.candidates(c).contains(a.dislike ?? ""))
                XCTAssertFalse(Tastes.staples.contains(Tastes.key(c, a.dislike ?? "")), "главную еду и мячик не разлюбить")
            }
        }
        // Тот же petId в другом файле (другое устройство, другое время) — те же реакции на всё.
        let f1 = tFile("same-pet", at: tT0)
        let f2 = tFile("same-pet", at: tT0 + 86400 * 3)
        XCTAssertNotEqual(f1.deviceId, f2.deviceId)
        for c in TasteCategory.allCases {
            for item in Tastes.candidates(c) {
                XCTAssertEqual(Tastes.reaction(c, item, in: f1), Tastes.reaction(c, item, in: f2), "\(c).\(item)")
            }
        }
    }

    func testDifferentPetsGetDifferentTastes() {
        let ids = (0..<200).map { "pet-\($0)" }
        var profiles = Set<String>()
        var loves: [TasteCategory: Set<String>] = [:]
        var dislikes: [TasteCategory: Set<String>] = [:]
        for id in ids {
            var p: [String] = []
            for c in TasteCategory.allCases {
                let h = Tastes.hidden(petId: id, c)
                loves[c, default: []].insert(h.love ?? "")
                dislikes[c, default: []].insert(h.dislike ?? "")
                p += [h.love ?? "", h.dislike ?? ""]
            }
            profiles.insert(p.joined(separator: "|"))
        }
        XCTAssertGreaterThanOrEqual(profiles.count, 150, "почти у каждого свой набор вкусов")
        for c in TasteCategory.allCases {
            XCTAssertEqual(loves[c], Set(Tastes.candidates(c)), "\(c): любимым бывает любая вещь")
            let canDislike = Set(Tastes.candidates(c).filter { !Tastes.staples.contains(Tastes.key(c, $0)) })
            XCTAssertEqual(dislikes[c], canDislike, "\(c): нелюбимым — любая, кроме главной")
        }
    }

    func testReactionShape() {
        let f = tFile()
        let h = Tastes.hidden(petId: f.petId, .food)
        let love = Tastes.reaction(.food, h.love!, in: f)
        XCTAssertEqual(love.taste, .love)
        XCTAssertEqual(love.strength, 1)
        XCTAssertGreaterThan(love.needX, 1)
        XCTAssertEqual(love.lineKey, "taste_love")
        XCTAssertFalse(love.clips.isEmpty)
        XCTAssertFalse(love.known)
        let dis = Tastes.reaction(.food, h.dislike!, in: f)
        XCTAssertEqual(dis.taste, .dislike)
        XCTAssertLessThan(dis.needX, 1)
        XCTAssertEqual(dis.lineKey, "taste_dislike")
        XCTAssertGreaterThan(dis.strength, 0)
        XCTAssertLessThan(dis.strength, 1)
        // Легендарное и эпическое, если не любимое/нелюбимое, — «нравится».
        XCTAssertEqual(Tastes.reaction(.food, "gold_bone", in: f).taste, .like)
        if h.love != "cake" && h.dislike != "cake" { XCTAssertEqual(Tastes.reaction(.food, "cake", in: f).taste, .like) }
        // Незнакомая вещь — без разницы.
        XCTAssertEqual(Tastes.reaction(.food, "нет-такого", in: f).taste, .neutral)
        // Действия без вкуса.
        XCTAssertNil(Tastes.reaction(for: .pet, in: f))
        XCTAssertNil(Tastes.reaction(for: .bath, in: f))
        XCTAssertEqual(Tastes.reaction(for: .feed(h.love!), in: f), love)
        XCTAssertEqual(Tastes.reaction(for: .play, in: f)?.item, Tastes.playToy)
    }

    // MARK: открытие

    func testOpensExactlyAfterK() throws {
        var f = tFile()
        let love = try XCTUnwrap(Tastes.hidden(petId: f.petId, .food).love)
        let k = Tastes.needed(.food)
        XCTAssertTrue((2...3).contains(k))
        for i in 1...k {
            let o = Tastes.observe(.food, love, at: tT0 + Double(i) * Tastes.gap, in: &f)
            XCTAssertTrue(o.counted)
            XCTAssertEqual(o.count, i)
            XCTAssertEqual(Tastes.progress(.food, love, in: f), i == k ? k : i)
            if i < k {
                XCTAssertNil(o.opened, "раньше K не открывается (\(i))")
                XCTAssertTrue(Tastes.album(f).isEmpty)
                XCTAssertEqual(o.lineKey, "taste_love")
            } else {
                let fact = try XCTUnwrap(o.opened, "открылся ровно на K")
                XCTAssertEqual(fact.taste, .love)
                XCTAssertEqual(fact.text, "Обожает \(Tastes.acc(love))")
                XCTAssertEqual(o.lineKey, Tastes.openLineKey)
                XCTAssertTrue(o.reaction.known)
            }
        }
        XCTAssertEqual(Tastes.album(f).map(\.item), [love])
        XCTAssertEqual(f.journal.last?.kind, "taste.open")
        XCTAssertEqual(f.journal.last?.key, "food.\(love)")
        XCTAssertNil(f.tastes.seen["food.\(love)"], "открытое из seen убрано — файл не растёт")
        XCTAssertEqual(Tastes.opened(f, since: tT0).count, 1)
        XCTAssertTrue(Tastes.opened(f, since: tT0 + Double(k) * Tastes.gap).isEmpty)

        // После открытия — без новых записей и без второго taste.open.
        let journal = f.journal.count
        let again = Tastes.observe(.food, love, at: tT0 + 100 * Tastes.gap, in: &f)
        XCTAssertFalse(again.counted)
        XCTAssertNil(again.opened)
        XCTAssertEqual(f.journal.count, journal)
        XCTAssertTrue(Tastes.reaction(.food, love, in: f).known)
    }

    func testDislikedFindOpensAfterTwoWithText() throws {
        var f = tFile()
        let bad = try XCTUnwrap(Tastes.hidden(petId: f.petId, .find).dislike)
        XCTAssertEqual(Tastes.needed(.find), 2)
        XCTAssertNil(Tastes.observe(.find, bad, at: tT0, in: &f).opened)
        let fact = try XCTUnwrap(Tastes.observe(.find, bad, at: tT0 + 3 * 3600, in: &f).opened)
        XCTAssertEqual(fact.taste, .dislike)
        XCTAssertEqual(fact.text, "Не в восторге, когда находит \(Finds.acc(bad))")
        XCTAssertEqual(fact.emoji, Finds.find(bad)?.emoji)
    }

    func testNeutralAndLikeNeverOpen() throws {
        var f = tFile()
        let neutral = try XCTUnwrap(Tastes.candidates(.food).first {
            Tastes.taste(.food, $0, petId: f.petId) == .neutral
        })
        for i in 0..<10 { Tastes.observe(.food, neutral, at: tT0 + Double(i) * Tastes.gap, in: &f) }
        for i in 0..<10 { Tastes.observe(.food, "gold_bone", at: tT0 + Double(i) * Tastes.gap, in: &f) }
        XCTAssertTrue(Tastes.album(f).isEmpty)
        XCTAssertEqual(f.tastes.seen["food.\(neutral)"]?.n, 10)
        XCTAssertEqual(f.tastes.seen["food.gold_bone"]?.r, "like")
        XCTAssertFalse(f.journal.contains { $0.kind == "taste.open" })
    }

    func testChangedReactionResetsCount() throws {
        var f = tFile()
        let love = try XCTUnwrap(Tastes.hidden(petId: f.petId, .food).love)
        // Наблюдения, записанные другой реакцией (например, до правки конфига), не в счёт.
        f.tastes.seen["food.\(love)"] = TasteLog.Seen(n: 2, t: tT0, r: "neutral")
        let o = Tastes.observe(.food, love, at: tT0 + Tastes.gap, in: &f)
        XCTAssertEqual(o.count, 1)
        XCTAssertNil(o.opened)
    }

    func testOpenedTasteIsPinned() throws {
        var f = tFile()
        let h = Tastes.hidden(petId: f.petId, .toy)
        let other = try XCTUnwrap(Tastes.candidates(.toy).first { $0 != h.love && $0 != h.dislike })
        // Открытое закреплено: даже если хеш теперь выбирает другое, любимое — то, что в альбоме.
        f.tastes.opened["toy.\(other)"] = TasteLog.Fact(r: "love", t: tT0)
        XCTAssertEqual(Tastes.hidden(petId: f.petId, .toy, log: f.tastes).love, other)
        XCTAssertEqual(Tastes.reaction(.toy, other, in: f).taste, .love)
        XCTAssertEqual(Tastes.reaction(.toy, h.love!, in: f).taste == .love, false, "любимое одно")
    }

    // MARK: идемпотентность

    func testSameObservationIsIdempotent() throws {
        var f = tFile()
        let love = try XCTUnwrap(Tastes.hidden(petId: f.petId, .food).love)
        let a = Tastes.observe(.food, love, at: tT0, in: &f)
        let b = Tastes.observe(.food, love, at: tT0, in: &f)
        let c = Tastes.observe(.food, love, at: tT0 + Tastes.gap - 1, in: &f)
        XCTAssertTrue(a.counted)
        XCTAssertFalse(b.counted)
        XCTAssertFalse(c.counted)
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(f.tastes.seen["food.\(love)"], TasteLog.Seen(n: 1, t: tT0, r: "love"))
        // Часы назад — тоже не в счёт.
        XCTAssertFalse(Tastes.observe(.food, love, at: tT0 - 3600, in: &f).counted)
        XCTAssertEqual(Tastes.progress(.food, love, in: f), 1)
    }

    func testRunnerFeedSpamCountsOnce() throws {
        var f = tFile()
        let love = try XCTUnwrap(Tastes.hidden(petId: f.petId, .food).love)
        for s in 0..<5 {
            XCTAssertTrue(PetRunner.apply(.feed(love), source: .app, to: &f, now: tT0 + Double(s)).ok)
        }
        XCTAssertEqual(Tastes.progress(.food, love, in: f), 1, "пять тапов подряд — одно наблюдение")
        XCTAssertTrue(Tastes.album(f).isEmpty)
    }

    // MARK: через PetRunner: бонус и открытие

    func testRunnerFeedLovedFoodBoostsAndOpens() throws {
        var f = tFile(level: 10)
        let love = try XCTUnwrap(Tastes.hidden(petId: f.petId, .food).love)
        let k = Tastes.needed(.food)
        for i in 0..<k {
            let now = tT0 + Double(i) * (Tastes.gap + 60)
            PetRunner.catchUp(&f, now: now)
            f.pet.needs[.food] = 10
            var core = f.pet
            XCTAssertTrue(PetEngine.act(&core, Catalog.rules, f.owner, .feed(love)).ok)
            let d = (core.needs[.food] ?? 0) - 10
            XCTAssertGreaterThan(d, 0)
            XCTAssertTrue(PetRunner.apply(.feed(love), source: .app, to: &f, now: now).ok)
            XCTAssertEqual(f.pet.needs[.food] ?? 0, min(100, 10 + d * 1.25), accuracy: 1e-9, "любимое сытнее ×1.25")
            XCTAssertEqual(Tastes.album(f).isEmpty, i < k - 1, "шаг \(i)")
        }
        XCTAssertEqual(f.journal.last?.kind, "taste.open")
        XCTAssertEqual(f.lastAction?.kind, "feed")
    }

    func testRunnerDislikedFoodGivesLess() throws {
        var f = tFile(level: 10)
        let bad = try XCTUnwrap(Tastes.hidden(petId: f.petId, .food).dislike)
        let before = f.pet.needs
        var core = f.pet
        XCTAssertTrue(PetEngine.act(&core, Catalog.rules, f.owner, .feed(bad)).ok)
        XCTAssertTrue(PetRunner.apply(.feed(bad), source: .app, to: &f, now: tT0).ok)
        for n in Need.allCases {
            let b = before[n] ?? 0, c = core.needs[n] ?? b, got = f.pet.needs[n] ?? b
            if c > b { XCTAssertEqual(got, b + (c - b) * 0.85, accuracy: 1e-9, "\(n)") } else { XCTAssertEqual(got, c, "\(n): минусы ядра не трогаем") }
        }
        XCTAssertEqual(f.pet.hearts, core.hearts, "сердечки — как в ядре")
    }

    func testRefusedActionIsNotObserved() throws {
        var f = tFile()
        let love = try XCTUnwrap(Tastes.hidden(petId: f.petId, .food).love)
        f.pet.bathUntil = tT0 + 3600
        XCTAssertFalse(PetRunner.apply(.feed(love), source: .app, to: &f, now: tT0).ok)
        XCTAssertTrue(f.tastes.isEmpty)
    }

    // MARK: находка с прогулки

    func testWalkReturnObservesFindAndLovedFindJoy() throws {
        var f = tFile()
        let fav = try XCTUnwrap(Tastes.hidden(petId: f.petId, .find).love)
        let joy = Tastes.findReaction(fav, in: f)
        XCTAssertEqual(joy.taste, .love)
        XCTAssertEqual(joy.lineKey, "taste_find_love")
        XCTAssertEqual(joy.strength, 1)
        XCTAssertGreaterThan(joy.clips.count, Tastes.reaction(.food, Tastes.hidden(petId: f.petId, .food).love!, in: f).clips.count,
                             "любимая находка — радость сильнее")

        f.pet.outing = Outing(from: tT0, until: tT0 + 3600, find: fav)
        PetRunner.catchUp(&f, now: tT0 + 2 * 3600)
        XCTAssertNil(f.pet.outing, "вернулся")
        XCTAssertEqual(Tastes.progress(.find, fav, in: f), 1)
        XCTAssertTrue(Tastes.album(f).isEmpty)
        // Повторный догон без новой прогулки ничего не добавляет.
        PetRunner.catchUp(&f, now: tT0 + 3 * 3600)
        XCTAssertEqual(Tastes.progress(.find, fav, in: f), 1)

        let t2 = tT0 + 4 * 3600
        f.pet.outing = Outing(from: t2, until: t2 + 3600, find: fav)
        PetRunner.catchUp(&f, now: t2 + 2 * 3600)
        let album = Tastes.album(f)
        XCTAssertEqual(album.count, 1)
        XCTAssertEqual(album.first?.text, "Любимая находка — \(Finds.name(fav))")
        XCTAssertEqual(album.first?.category, .find)
        XCTAssertTrue(Tastes.findReaction(fav, in: f).known)
    }

    // MARK: сохранение

    func testOldSaveWithoutTastesDecodes() throws {
        let f = tFile()
        // JSONValue, а не JSONSerialization: на Linux true/false там превращаются в числа.
        var obj = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(f)).object
        XCTAssertNil(obj["tastes"], "пустые вкусы в файл не пишутся")
        obj.removeValue(forKey: "tastes")
        func decode(_ o: [String: JSONValue]) throws -> SaveFile {
            try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(JSONValue.object(o)))
        }
        let old = try decode(obj)
        XCTAssertTrue(old.tastes.isEmpty)
        XCTAssertEqual(old.petId, f.petId)

        obj["tastes"] = .number(5)
        let broken = try decode(obj)
        XCTAssertTrue(broken.tastes.isEmpty, "кривое поле — пустые вкусы, а не ошибка чтения")
        obj["tastes"] = .object(["seen": .object(["food.carrot": .object([
            "n": .number(1), "t": .number(tT0), "r": .string("love"),
        ])])])
        let partial = try decode(obj)
        XCTAssertEqual(partial.tastes.seen["food.carrot"]?.n, 1)
        XCTAssertTrue(partial.tastes.opened.isEmpty)
    }

    func testTastesRoundTrip() throws {
        var f = tFile()
        let love = try XCTUnwrap(Tastes.hidden(petId: f.petId, .food).love)
        let neutral = try XCTUnwrap(Tastes.candidates(.toy).first { Tastes.taste(.toy, $0, petId: f.petId) == .neutral })
        for i in 0..<Tastes.needed(.food) { Tastes.observe(.food, love, at: tT0 + Double(i) * Tastes.gap, in: &f) }
        Tastes.observe(.toy, neutral, at: tT0, in: &f)
        let back = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back.tastes, f.tastes)
        XCTAssertEqual(Tastes.album(back), Tastes.album(f))
    }

    // MARK: реплики

    func testTasteLinesExistAndFit() {
        let lines = Lines.shared
        guard lines.sections.values.contains(where: { !$0.isEmpty }) else { return }
        for key in ["taste_love", "taste_dislike", "taste_open", "taste_find_love"] {
            for slot in 0..<6 {
                let t = tT0 + Double(slot) * 6 * 3600
                let w = Tastes.line(key, seed: "pet", at: t, lines: lines)
                let i = Tastes.line(key, island: true, seed: "pet", at: t, lines: lines)
                XCTAssertNotNil(w, "widget.\(key)")
                XCTAssertNotNil(i, "island.\(key)")
                XCTAssertLessThanOrEqual(w?.count ?? 0, LineLimit.widget)
                XCTAssertLessThanOrEqual(i?.count ?? 0, LineLimit.island)
                XCTAssertFalse(w?.contains("{") ?? false)
            }
        }
    }

    func testAlbumTexts() {
        XCTAssertEqual(Tastes.text(.food, "carrot", .love), "Обожает морковку")
        XCTAssertEqual(Tastes.text(.food, "broccoli", .dislike), "Не любит брокколи")
        XCTAssertEqual(Tastes.text(.toy, "laser", .love), "Обожает лазерную указку")
        XCTAssertEqual(Tastes.text(.find, "cone", .love), "Любимая находка — шишка")
        XCTAssertEqual(Tastes.text(.find, "sock", .dislike), "Не в восторге, когда находит носок")
        for c in [TasteCategory.food, .toy] {
            for item in Tastes.candidates(c) {
                XCTAssertNotNil(Tastes.accusative[item], "падеж для \(item)")
                XCTAssertNotNil(Tastes.emojis[item], "значок для \(item)")
            }
        }
    }
}
