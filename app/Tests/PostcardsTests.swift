// Открытка дня без экрана: моменты из журнала, стабильный выбор, местная полночь, срок 7 суток,
// альбом с лимитом и старые сейвы без поля cards. Время — местные дни в поясе UTC+2 (pcTZ), чтобы полночь
// не совпадала с UTC. Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let pcPet = "pet-postcards"
private let pcTZ = 120
/// Тестовый день: местный день момента 1_760_000_000.
private let pcDay = Postcards.day(1_760_000_000, tzOffsetMin: pcTZ)

/// Свежий файл, созданный в 9:00 местного дня createdDay (по умолчанию за 20 дней: не веха).
private func pcFile(createdDay: Int = pcDay - 20) -> SaveFile {
    var f = SaveFile.fresh(now: Postcards.dayStart(createdDay, tzOffsetMin: pcTZ) + 9 * 3600)
    f.petId = pcPet
    f.owner.tzOffsetMin = pcTZ
    return f
}

/// Местное время дня d.
private func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Double {
    Postcards.dayStart(d, tzOffsetMin: pcTZ) + Double(h * 3600 + m * 60)
}

/// Начало дня d: в этот момент появляется открытка за d − 1.
private func midnight(_ d: Int) -> Double { Postcards.dayStart(d, tzOffsetMin: pcTZ) }

private func act(_ f: inout SaveFile, _ kind: String, _ t: Double, ok: Bool = true, key: String? = nil, value: Int? = nil) {
    f.log("act.\(kind)", t: t, source: .app, ok: ok, reason: ok ? nil : "cooldown", key: key, value: value)
}

private func dummy(day: Int) -> Postcard {
    Postcard(id: "c\(day)", day: day, kind: "play", t: Double(day) * 86400, tz: 0, score: 35, caption: "Играли.",
             lineId: nil, find: nil, item: nil, count: nil, pose: "happy", clip: nil, prop: nil,
             expiresT: Double(day + 8) * 86400, savedT: Double(day + 1) * 86400, image: nil)
}

final class PostcardsTests: XCTestCase {
    // MARK: выбор

    func testChoiceIsDeterministic() throws {
        var f = pcFile()
        let d = pcDay
        act(&f, "feed", at(d, 12), key: Catalog.mainFood)
        act(&f, "play", at(d, 13))
        f.log("ev.back_home.cone", t: at(d, 16), key: "cone")
        act(&f, "bath", at(d, 18))

        let a = try XCTUnwrap(Postcards.card(for: d, in: f, tzOffsetMin: pcTZ))
        XCTAssertEqual(Postcards.card(for: d, in: f, tzOffsetMin: pcTZ), a, "второй раз — то же самое")
        let g = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(Postcards.card(for: d, in: g, tzOffsetMin: pcTZ), a, "после диска (виджет) — то же самое")

        let ms = Postcards.moments(f, day: d, tzOffsetMin: pcTZ)
        XCTAssertEqual(Set(ms.map(\.kind)), [.feed, .play, .find, .bath])
        XCTAssertEqual(Postcards.choose(Array(ms.reversed()), petId: pcPet, day: d),
                       Postcards.choose(ms, petId: pcPet, day: d), "порядок моментов не влияет")

        // Выбор зависит от питомца и дня, но слабое (кормёжка 20 при лучшем 50) в пул не попадает.
        var kinds = Set<MomentKind>()
        for p in 0..<60 { kinds.insert(try XCTUnwrap(Postcards.choose(ms, petId: "p\(p)", day: d)).kind) }
        XCTAssertGreaterThan(kinds.count, 1, "не всегда один и тот же тип")
        XCTAssertFalse(kinds.contains(.feed), "кормёжка слабее 60 % находки")

        // Вчерашний тип вдвое дешевле: находка 50 → 25, теперь в пуле игра и мытьё.
        for p in 0..<60 {
            let m = try XCTUnwrap(Postcards.choose(ms, petId: "p\(p)", day: d, previous: .find))
            XCTAssertNotEqual(m.kind, .feed)
            if m.kind == .find { XCTAssertEqual(m.score, 25) }
        }
    }

    func testCaptionAndFrame() throws {
        var f = pcFile()
        let d = pcDay
        f.log("ev.back_home.cone", t: at(d, 14, 20), key: "cone")
        let c = try XCTUnwrap(Postcards.card(for: d, in: f, tzOffsetMin: pcTZ))
        XCTAssertEqual(c.kind, "find")
        XCTAssertEqual(c.id, "c\(d)")
        XCTAssertTrue(c.lineId?.hasPrefix("a.card_find.") ?? false, "подпись из lines.json: \(c.lineId ?? "nil")")
        XCTAssertFalse(c.caption.contains("{"), "подстановки заполнены: \(c.caption)")
        XCTAssertLessThanOrEqual(c.caption.count, Postcards.captionMax)
        let fr = c.frame
        XCTAssertEqual(fr.time, "14:20", "время по местному поясу")
        XCTAssertEqual(fr.find?.id, "cone")
        XCTAssertEqual(fr.prop, "cone")
        XCTAssertEqual(fr.pose, .happy)
        XCTAssertEqual(fr.date, Postcards.dateLabel(d))

        XCTAssertEqual(Postcards.vars(Moment(kind: .treat, t: 0, score: 30, item: "sausage"))["item"], "сосиска")
        XCTAssertEqual(Postcards.vars(Moment(kind: .steps, t: 0, score: 25, count: 12500))["steps"], "12 500")
        XCTAssertNil(Postcards.vars(Moment(kind: .pets, t: 0, score: 10))["count"], "без серии — строка без {count}")
        XCTAssertEqual(Postcards.dateLabel(0), "1 января")
        XCTAssertEqual(Postcards.dateLabel(20_743), "17 октября", "2026-10-17")
        XCTAssertEqual(Postcards.civil(19_782).month, 2, "2024-02-29")
        XCTAssertEqual(Postcards.civil(19_782).day, 29)
    }

    func testCaptionsInLines() {
        for k in MomentKind.allCases {
            let lines = Lines.shared.sections["away"]?[k.lineKey] ?? []
            XCTAssertTrue((3...5).contains(lines.count), "\(k.lineKey): \(lines.count) строк")
            XCTAssertTrue(lines.contains { Lines.placeholders($0.text).isEmpty }, "\(k.lineKey): нужна строка без подстановок")
            for l in lines {
                XCTAssertTrue(l.id.hasPrefix("a.\(k.lineKey)."), l.id)
                // Подстановка считается за 14 знаков, как в проверке content/README.md.
                var vars: [String: String] = [:]
                for p in Lines.placeholders(l.text) { vars[p] = String(repeating: "x", count: 14) }
                XCTAssertLessThanOrEqual(Lines.fill(l.text, vars).count, Postcards.captionMax, l.id)
            }
        }
    }

    // MARK: моменты

    func testEmptyDayHasNoCard() {
        var f = pcFile()
        let d = pcDay
        f.log("ev.low.food", t: at(d, 14), key: "food")
        act(&f, "play", at(d, 15), ok: false)
        act(&f, "pet", at(d, 16), ok: false)
        act(&f, "steps", at(d, 17), value: 400)
        XCTAssertTrue(Postcards.moments(f, day: d, tzOffsetMin: pcTZ).isEmpty, "предупреждения, отказы и мало шагов — не моменты")
        XCTAssertNil(Postcards.card(for: d, in: f, tzOffsetMin: pcTZ))
        let made = Postcards.refresh(&f, now: midnight(d + 1) + 60)
        XCTAssertTrue(made.isEmpty)
        XCTAssertTrue(f.cards.pending.isEmpty, "ничего не выдумываем")
        XCTAssertEqual(f.cards.doneDay, d, "пустой день тоже разобран")
    }

    func testPetsSeries() {
        var f = pcFile()
        let d = pcDay
        for i in 0..<5 { act(&f, "pet", at(d, 15, i * 3), ok: i != 2) }
        act(&f, "pet", at(d, 19))
        let pets = Postcards.moments(f, day: d, tzOffsetMin: pcTZ).filter { $0.kind == .pets }
        XCTAssertEqual(pets.count, 2)
        XCTAssertEqual(pets.first?.count, 5, "серия из 5 тапов, один в кулдаун")
        XCTAssertEqual(pets.first?.score, 35)
        XCTAssertEqual(pets.last?.score, 10, "одно поглаживание — слабый момент")
        XCTAssertNil(pets.last?.count)
    }

    func testRescueFirstFindAndMilestones() throws {
        let d = pcDay
        var f = pcFile()
        f.log("ev.heart.3", t: at(d - 1, 22), value: 3)
        act(&f, "feed", at(d, 11), key: Catalog.mainFood)
        act(&f, "pet", at(d, 11, 10))
        act(&f, "play", at(d, 11, 30))
        act(&f, "bath", at(d, 15))
        let rescue = Postcards.moments(f, day: d, tzOffsetMin: pcTZ).filter { $0.kind == .rescue }
        XCTAssertEqual(rescue.map(\.t), [at(d, 11, 30)], "спасение — последнее дело серии заботы после беды")
        XCTAssertEqual(rescue.first?.score, 70)

        var lc = pcFile()
        lc.log("ev.last_chance", t: at(d, 9))
        act(&lc, "item", at(d, 12), key: Catalog.healItem)
        XCTAssertEqual(Postcards.moments(lc, day: d, tzOffsetMin: pcTZ).first { $0.kind == .rescue }?.score, 90)

        var late = pcFile()
        late.log("ev.distress.starve", t: at(d - 3, 12), key: "starve")
        act(&late, "feed", at(d, 12), key: Catalog.mainFood)
        XCTAssertFalse(Postcards.moments(late, day: d, tzOffsetMin: pcTZ).contains { $0.kind == .rescue }, "через 72 ч — уже не спасение")

        var g = pcFile()
        g.pet.finds = ["cone": 1]
        g.log("ev.back_home.cone", t: at(d, 16), key: "cone")
        XCTAssertEqual(Postcards.moments(g, day: d, tzOffsetMin: pcTZ).map(\.kind), [.findFirst])
        g.pet.finds = ["cone": 3]
        XCTAssertEqual(Postcards.moments(g, day: d, tzOffsetMin: pcTZ).map(\.kind), [.find], "прошлые шишки вытеснены из журнала")

        // День знакомства — без дел хозяина, 7-й день — только если заходил, и веха важнее находки.
        var w = pcFile(createdDay: d - 7)
        XCTAssertEqual(Postcards.card(for: d - 7, in: w, tzOffsetMin: pcTZ)?.kind, "first_day")
        w.log("ev.back_home.cone", t: at(d, 13), key: "cone")
        XCTAssertEqual(Postcards.card(for: d, in: w, tzOffsetMin: pcTZ)?.kind, "find", "не заходил — веху не отмечаем")
        act(&w, "feed", at(d, 12), key: Catalog.mainFood)
        let days = try XCTUnwrap(Postcards.card(for: d, in: w, tzOffsetMin: pcTZ))
        XCTAssertEqual(days.kind, "days")
        XCTAssertEqual(days.count, 7)

        var b = pcFile(createdDay: d - 365)
        act(&b, "play", at(d, 12))
        let bd = try XCTUnwrap(Postcards.card(for: d, in: b, tzOffsetMin: pcTZ))
        XCTAssertEqual(bd.kind, "birthday")
        XCTAssertEqual(bd.count, 1)
        XCTAssertEqual(bd.prop, "cake")
    }

    // MARK: время

    func testLocalMidnight() throws {
        var f = pcFile()
        let d = pcDay
        let late = at(d, 23, 30), early = at(d + 1, 0, 30)
        XCTAssertEqual(Postcards.day(late, tzOffsetMin: pcTZ), d)
        XCTAssertEqual(Postcards.day(early, tzOffsetMin: pcTZ), d + 1)
        XCTAssertEqual(Postcards.day(late, tzOffsetMin: 0), Postcards.day(early, tzOffsetMin: 0), "по UTC это один день")
        act(&f, "play", late)
        act(&f, "bath", early)

        XCTAssertTrue(Postcards.refresh(&f, now: at(d, 23, 59)).isEmpty, "день ещё не кончился")
        XCTAssertNil(f.cards.card("c\(d)"))

        let made = Postcards.refresh(&f, now: at(d + 1, 0, 1))
        XCTAssertEqual(made.map(\.id), ["c\(d)"], "после местной полуночи — открытка за вчера")
        let c = try XCTUnwrap(f.cards.card("c\(d)"))
        XCTAssertEqual(c.kind, "play", "мытьё в 00:30 — уже следующий день")
        XCTAssertEqual(c.t, late)
        XCTAssertEqual(c.frame.time, "23:30")
        XCTAssertTrue(Postcards.refresh(&f, now: at(d + 1, 12)).isEmpty, "день разбирается один раз")
        XCTAssertEqual(f.cards.pending.count, 1)

        let next = Postcards.refresh(&f, now: midnight(d + 2))
        XCTAssertEqual(next.map(\.kind), ["bath"])
    }

    func testExpiresExactlyAfterSevenDays() throws {
        var f = pcFile()
        let d = pcDay
        act(&f, "play", at(d, 15))
        let born = midnight(d + 1)
        Postcards.refresh(&f, now: born)
        let c = try XCTUnwrap(f.cards.card("c\(d)"))
        XCTAssertEqual(c.expiresT, born + 7 * 86400)

        XCTAssertEqual(Postcards.active(f, now: born + 7 * 86400 - 1).map(\.id), ["c\(d)"], "за секунду до срока ещё есть")
        XCTAssertTrue(Postcards.active(f, now: born + 7 * 86400).isEmpty, "ровно через 7 суток — нет")
        var copy = f
        XCTAssertEqual(Postcards.save("c\(d)", in: &copy, now: born + 7 * 86400), .expired)
        XCTAssertTrue(copy.cards.album.isEmpty)

        Postcards.refresh(&f, now: born + 7 * 86400)
        XCTAssertTrue(f.cards.pending.isEmpty, "не сохранили — пропала")
        Postcards.refresh(&f, now: born + 9 * 86400)
        XCTAssertNil(f.cards.card("c\(d)"), "заново не собирается")

        // Старый сейв без открыток: дни старше 7 суток не досчитываем.
        var old = pcFile()
        act(&old, "play", at(d, 15))
        XCTAssertTrue(Postcards.refresh(&old, now: midnight(d + 8)).isEmpty)
        var fresh = pcFile()
        act(&fresh, "play", at(d, 15))
        XCTAssertEqual(Postcards.refresh(&fresh, now: midnight(d + 8) - 1).map(\.id), ["c\(d)"])
    }

    func testSavedCardSurvivesExpiry() throws {
        var f = pcFile()
        let d = pcDay
        act(&f, "bath", at(d, 10, 45))
        let born = midnight(d + 1)
        XCTAssertEqual(Postcards.save("c\(d)", in: &f, now: born + 3600), .saved)
        XCTAssertEqual(Postcards.save("c\(d)", in: &f, now: born + 3601), .already)
        XCTAssertEqual(Postcards.save("c\(d + 5)", in: &f, now: born + 3601), .notFound)
        XCTAssertTrue(f.cards.pending.isEmpty)

        Postcards.refresh(&f, now: born + 30 * 86400)
        let kept = try XCTUnwrap(Postcards.album(f).first)
        XCTAssertEqual(kept.id, "c\(d)")
        XCTAssertEqual(kept.savedT, born + 3600)
        XCTAssertEqual(kept.frame.time, "10:45")
        XCTAssertTrue(Postcards.active(f, now: born + 30 * 86400).isEmpty, "в ленте свежих её уже нет, в альбоме — есть")

        Postcards.setImage("c\(d).heic", for: "c\(d)", in: &f)
        XCTAssertEqual(f.cards.album.first?.image, "c\(d).heic")
        XCTAssertTrue(Postcards.remove("c\(d)", in: &f))
        XCTAssertTrue(f.cards.album.isEmpty)
    }

    func testDiscardAndDeath() {
        var f = pcFile()
        let d = pcDay
        act(&f, "play", at(d, 15))
        Postcards.refresh(&f, now: midnight(d + 1))
        Postcards.discard("c\(d)", in: &f)
        XCTAssertTrue(f.cards.pending.isEmpty)
        XCTAssertTrue(Postcards.refresh(&f, now: midnight(d + 2)).isEmpty, "выброшенная не возвращается")

        var dead = pcFile()
        act(&dead, "play", at(d - 1, 15))
        act(&dead, "play", at(d, 15))
        dead.pet.alive = false
        dead.pet.diedAt = at(d, 20)
        XCTAssertEqual(Postcards.refresh(&dead, now: midnight(d + 2)).map(\.id), ["c\(d - 1)"], "день смерти — без открытки")
    }

    // MARK: альбом и сейв

    func testAlbumLimit() throws {
        var f = pcFile()
        let d = pcDay
        for i in 0..<PostcardBook.albumMax { f.cards.album.append(dummy(day: d - 100 - i)) }
        act(&f, "play", at(d, 15))
        let now = midnight(d + 1) + 60
        XCTAssertEqual(Postcards.save("c\(d)", in: &f, now: now), .albumFull)
        XCTAssertEqual(f.cards.album.count, PostcardBook.albumMax)
        XCTAssertNotNil(f.cards.pending.first { $0.id == "c\(d)" }, "отказ — открытка остаётся ждать")
        XCTAssertTrue(Postcards.remove("c\(d - 100)", in: &f))
        XCTAssertEqual(Postcards.save("c\(d)", in: &f, now: now), .saved)
        XCTAssertEqual(f.cards.album.count, PostcardBook.albumMax)

        // Полный альбом настоящих открыток в сейве — не больше ~100 КБ.
        var book = PostcardBook()
        for i in 0..<PostcardBook.albumMax {
            var c = Postcards.make(Moment(kind: .findFirst, t: at(d - i, 14), score: 70, find: "pebble"),
                                   day: d - i, petId: pcPet, tzOffsetMin: pcTZ)
            c.savedT = at(d - i + 1, 9)
            c.image = "c\(d - i).heic"
            book.album.append(c)
        }
        let size = try JSONEncoder().encode(book).count
        XCTAssertLessThan(size, 100_000, "альбом \(size) байт")
    }

    func testOldSaveDecodes() throws {
        var f = pcFile()
        act(&f, "play", at(pcDay, 15))
        Postcards.save("c\(pcDay)", in: &f, now: midnight(pcDay + 1) + 60)
        XCTAssertEqual(f.cards.album.count, 1)

        let data = try JSONEncoder().encode(f)
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(obj["cards"], "поле пишется")

        // Сейв до открыток: поля нет — пустой альбом, остальное на месте.
        obj.removeValue(forKey: "cards")
        let old = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertEqual(old.cards, PostcardBook())
        XCTAssertEqual(old.journal, f.journal)
        XCTAssertEqual(old.petId, f.petId)

        // Битая открытка и мусор вместо списка не стирают остальное.
        var cards = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.cards)) as? [String: Any])
        let good = try XCTUnwrap(cards["album"] as? [Any])
        var album: [Any] = [["id": 5] as [String: Any]]
        album += good
        album.append(["kind": "selfie"] as [String: Any])
        cards["album"] = album
        cards["pending"] = "мусор"
        obj["cards"] = cards
        let broken = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertEqual(broken.cards.album, f.cards.album)
        XCTAssertTrue(broken.cards.pending.isEmpty)
        XCTAssertEqual(broken.cards.doneDay, f.cards.doneDay)

        // Открытка незнакомого типа (из новой версии) читается и показывается.
        let base = dummy(day: pcDay)
        let future = Postcard(id: base.id, day: base.day, kind: "selfie", t: base.t, tz: 0, score: 40, caption: "Селфи!",
                              lineId: nil, find: nil, item: nil, count: nil, pose: "wink", clip: nil, prop: nil,
                              expiresT: base.expiresT, savedT: nil, image: nil)
        let back = try JSONDecoder().decode(Postcard.self, from: JSONEncoder().encode(future))
        XCTAssertNil(back.momentKind)
        XCTAssertEqual(back.frame.pose, .happy, "незнакомая поза — happy")

        // Туда-обратно без потерь.
        let again = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(again.cards, f.cards)
    }

    // MARK: через PetRunner

    func testCatchUpMakesCards() throws {
        let tz = Clock.tzOffsetMin(at: 1_760_000_000)
        let d = Postcards.day(1_760_000_000, tzOffsetMin: tz)
        let start = Postcards.dayStart(d, tzOffsetMin: tz) + 14 * 3600
        var f = SaveFile.fresh(now: start)
        _ = PetRunner.apply(.pet, source: .app, to: &f, now: start + 60)
        XCTAssertTrue(f.cards.pending.isEmpty, "в тот же день открытки нет")
        let next = Postcards.dayStart(d + 1, tzOffsetMin: f.owner.tzOffsetMin) + 120
        PetRunner.catchUp(&f, now: next)
        let c = try XCTUnwrap(f.cards.pending.first, "первая запись после полуночи собирает открытку")
        XCTAssertEqual(c.day, d)
        XCTAssertEqual(c.kind, "first_day")
        XCTAssertEqual(Postcards.latest(f, now: next)?.id, c.id)
    }
}
