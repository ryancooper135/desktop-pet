// Кадры «Открытки дня» и её срок без экрана: когда снимать (лимиты, пауза, лучший вытесняет худший),
// какой кадр достаётся открытке, уборка файлов-сирот, обрезка 4:3, «последний день» и старые сейвы без shots.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let ppPet = "pet-photos"
private let ppTZ = 120
private let ppDay = Postcards.day(1_760_000_000, tzOffsetMin: ppTZ)

private func ppFile(createdDay: Int = ppDay - 20) -> SaveFile {
    var f = SaveFile.fresh(now: Postcards.dayStart(createdDay, tzOffsetMin: ppTZ) + 9 * 3600)
    f.petId = ppPet
    f.owner.tzOffsetMin = ppTZ
    return f
}

private func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Double {
    Postcards.dayStart(d, tzOffsetMin: ppTZ) + Double(h * 3600 + m * 60)
}

private func shot(_ k: MomentKind, _ t: Double, day: Int = ppDay) -> PostcardShot {
    PostcardShot(day: day, kind: k.rawValue, t: t, score: PostcardPhotos.score(k),
                 file: PostcardPhotos.fileName(day: day, t: t, kind: k))
}

/// Снять, если план разрешает (как приложение): план → кадр → commit.
@discardableResult
private func take(_ f: inout SaveFile, _ k: MomentKind, _ t: Double) -> PostcardPhotos.Plan {
    let p = PostcardPhotos.plan(f, kind: k, now: t)
    if p.shoots { PostcardPhotos.commit(shot(k, t, day: Postcards.day(t, tzOffsetMin: ppTZ)), in: &f) }
    return p
}

final class PostcardPhotosTests: XCTestCase {
    // MARK: когда снимать

    func testKindsForActions() {
        XCTAssertEqual(PostcardPhotos.kind(forAction: "feed", key: Catalog.mainFood), .feed)
        XCTAssertEqual(PostcardPhotos.kind(forAction: "feed", key: nil), .feed)
        XCTAssertEqual(PostcardPhotos.kind(forAction: "feed", key: "something_else"), .treat)
        XCTAssertEqual(PostcardPhotos.kind(forAction: "play", key: nil), .play)
        XCTAssertEqual(PostcardPhotos.kind(forAction: "pet", key: nil), .pets)
        XCTAssertEqual(PostcardPhotos.kind(forAction: "bath", key: nil), .bath)
        for k in ["item", "wake", "steps", "walk", "unknown"] {
            XCTAssertNil(PostcardPhotos.kind(forAction: k, key: nil), k)
        }
    }

    func testFirstShotThenGapAndSameKind() {
        var f = ppFile()
        let d = ppDay
        XCTAssertEqual(take(&f, .feed, at(d, 9)), .add)
        XCTAssertEqual(f.shots.items.count, 1)
        XCTAssertEqual(f.shots.taken, 1)
        XCTAssertEqual(f.shots.day, d)
        // Через 5 минут поглаживание (10 очков < 20) — рано и хуже.
        XCTAssertEqual(take(&f, .pets, at(d, 9, 5)), .skip("too_soon"))
        // Через 10 минут игра (35 > 20) — тот же всплеск ухода, лучший момент заменяет кадр еды.
        XCTAssertEqual(take(&f, .play, at(d, 9, 10)), .replace(shot(.feed, at(d, 9)).file))
        XCTAssertEqual(f.shots.items.map(\.kind), ["play"])
        XCTAssertEqual(f.shots.taken, 2, "вытесненный кадр тоже считается")
        // Через час снова игра — такой тип уже есть.
        XCTAssertEqual(take(&f, .play, at(d, 11)), .skip("have_kind"))
        XCTAssertEqual(take(&f, .bath, at(d, 12)), .add)
        XCTAssertEqual(Set(f.shots.items.map(\.kind)), ["play", "bath"])
    }

    func testBetterReplacesWorstWhenFull() {
        var f = ppFile()
        let d = ppDay
        XCTAssertEqual(take(&f, .pets, at(d, 8)), .add)     // 10
        XCTAssertEqual(take(&f, .feed, at(d, 9)), .add)     // 20
        XCTAssertEqual(take(&f, .bath, at(d, 10)), .add)    // 30
        XCTAssertEqual(f.shots.items.count, PostcardPhotos.keepPerDay)
        // Лакомство (30) лучше худшего (поглаживание 10) — вытесняет его.
        XCTAssertEqual(take(&f, .treat, at(d, 11)), .replace(shot(.pets, at(d, 8)).file))
        XCTAssertEqual(Set(f.shots.items.map(\.kind)), ["feed", "bath", "treat"])
        // Снова поглаживание (10) хуже всех — нет.
        XCTAssertEqual(take(&f, .pets, at(d, 12)), .skip("not_better"))
        // Игра (35) вытесняет худший — кормёжку (20).
        XCTAssertEqual(take(&f, .play, at(d, 13)), .replace(shot(.feed, at(d, 9)).file))
        XCTAssertEqual(f.shots.items.count, PostcardPhotos.keepPerDay)
    }

    func testDailyLimitAndNewDay() {
        var book = ShotBook()
        book.day = ppDay
        book.taken = PostcardPhotos.shotsPerDay
        XCTAssertEqual(PostcardPhotos.plan(book, kind: .play, now: at(ppDay, 20), day: ppDay), .skip("day_limit"))
        // Новые сутки — счётчик с нуля.
        XCTAssertEqual(PostcardPhotos.plan(book, kind: .play, now: at(ppDay + 1, 9), day: ppDay + 1), .add)
        var f = ppFile()
        f.shots = book
        take(&f, .play, at(ppDay + 1, 9))
        XCTAssertEqual(f.shots.day, ppDay + 1)
        XCTAssertEqual(f.shots.taken, 1)
    }

    func testCommitRechecksPlan() {
        var f = ppFile()
        let d = ppDay
        take(&f, .play, at(d, 9))
        // Пока снимали, другой кадр уже лёг (или пауза не вышла): новый файл возвращается на выброс.
        let late = shot(.pets, at(d, 9, 1))
        XCTAssertEqual(PostcardPhotos.commit(late, in: &f), [late.file])
        XCTAssertEqual(f.shots.items.count, 1)
    }

    // MARK: кадр открытке

    func testCardGetsMatchingShot() throws {
        var f = ppFile()
        let d = ppDay
        f.log("act.feed", t: at(d, 12), source: .app, ok: true, reason: nil, key: Catalog.mainFood, value: nil)
        take(&f, .play, at(d, 10))
        take(&f, .feed, at(d, 12))
        take(&f, .bath, at(d, 18))
        let made = Postcards.refresh(&f, now: at(d + 1, 8))
        let c = try XCTUnwrap(made.first)
        XCTAssertEqual(c.kind, "feed", "в журнале только еда")
        XCTAssertEqual(c.image, shot(.feed, at(d, 12)).file, "кадр того же момента, а не лучший по очкам")
        XCTAssertEqual(f.cards.pending.first?.image, c.image, "в сейве тоже")
        XCTAssertTrue(f.shots.items.isEmpty, "кадры прошедшего дня разобраны")
        // Невыбранные кадры стали сиротами, кадр открытки — нет.
        let live = PostcardPhotos.liveFiles(f)
        XCTAssertEqual(live, [c.image!])
    }

    func testCardFallsBackToBestShot() {
        let card = Postcard(id: "c\(ppDay)", day: ppDay, kind: "first_day", t: at(ppDay, 9), tz: ppTZ, score: 100,
                            caption: "Наш первый день.", lineId: nil, find: nil, item: nil, count: nil, pose: "happy",
                            clip: nil, prop: nil, expiresT: at(ppDay + 8, 0), savedT: nil, image: nil)
        let shots = [shot(.pets, at(ppDay, 10)), shot(.play, at(ppDay, 12)), shot(.bath, at(ppDay, 14)),
                     shot(.find, at(ppDay - 1, 12), day: ppDay - 1)]
        XCTAssertEqual(PostcardPhotos.pick(for: card, among: shots)?.kind, "play", "лучший кадр своего дня")
        XCTAssertNil(PostcardPhotos.pick(for: card, among: [shots[3]]), "кадр другого дня не берём")
        // Находка к находке, ближайшая по времени.
        var find = card
        find = Postcard(id: card.id, day: ppDay, kind: "find_first", t: at(ppDay, 15), tz: ppTZ, score: 70,
                        caption: "", lineId: nil, find: "cone", item: nil, count: nil, pose: "happy", clip: nil,
                        prop: nil, expiresT: card.expiresT, savedT: nil, image: nil)
        let finds = [shot(.find, at(ppDay, 9)), shot(.find, at(ppDay, 16)), shot(.play, at(ppDay, 15))]
        XCTAssertEqual(PostcardPhotos.pick(for: find, among: finds)?.t, at(ppDay, 16))
    }

    func testEmptyDayDropsShots() {
        var f = ppFile()
        let d = ppDay
        // Кадр есть, а в журнале за день ничего (например, действие было из виджета другого пояса) — открытки нет.
        f.shots.items = [shot(.play, at(d, 10))]
        let made = Postcards.refresh(&f, now: at(d + 1, 8))
        XCTAssertTrue(made.isEmpty)
        XCTAssertTrue(f.shots.items.isEmpty)
        XCTAssertTrue(PostcardPhotos.liveFiles(f).isEmpty)
    }

    func testTodayShotsSurviveRefresh() {
        var f = ppFile()
        let d = ppDay
        take(&f, .play, at(d, 10))
        Postcards.refresh(&f, now: at(d, 11))
        XCTAssertEqual(f.shots.items.count, 1, "сегодняшний кадр ждёт полуночи")
    }

    // MARK: уборка

    func testOrphansGoWithCards() throws {
        var f = ppFile()
        let d = ppDay
        f.log("act.play", t: at(d, 10), source: .app, ok: true, reason: nil, key: nil, value: nil)
        take(&f, .play, at(d, 10))
        Postcards.refresh(&f, now: at(d + 1, 8))
        let c = try XCTUnwrap(f.cards.pending.first)
        let file = try XCTUnwrap(c.image)
        let now = at(d + 1, 9)
        let disk = [file: at(d, 10), "old.jpg": at(d - 3, 10), "fresh.jpg": now - 60, "notes.txt": 0]
        XCTAssertEqual(PostcardPhotos.orphans(disk, live: PostcardPhotos.liveFiles(f), now: now), ["old.jpg"],
                       "свежий файл (ещё не в сейве) и чужие файлы не трогаем")
        // Сохранили в альбом — кадр живёт.
        XCTAssertEqual(Postcards.save(c.id, in: &f, now: now), .saved)
        XCTAssertTrue(PostcardPhotos.liveFiles(f).contains(file))
        // Удалили из альбома — кадр сирота.
        Postcards.remove(c.id, in: &f)
        XCTAssertEqual(PostcardPhotos.orphans(disk, live: PostcardPhotos.liveFiles(f), now: now), ["old.jpg", file])
    }

    func testExpiredCardFreesShot() throws {
        var f = ppFile()
        let d = ppDay
        f.log("act.bath", t: at(d, 10), source: .app, ok: true, reason: nil, key: nil, value: nil)
        take(&f, .bath, at(d, 10))
        Postcards.refresh(&f, now: at(d + 1, 8))
        let c = try XCTUnwrap(f.cards.pending.first)
        XCTAssertNotNil(c.image)
        Postcards.refresh(&f, now: c.expiresT)
        XCTAssertTrue(f.cards.pending.isEmpty, "не сохранили за 7 дней — пропала")
        XCTAssertFalse(PostcardPhotos.liveFiles(f).contains(c.image!), "и кадр уходит в уборку")
    }

    // MARK: обрезка и размер

    func testCropAndFit() {
        // Экран 1260×2736, пёс чуть ниже середины: окно во всю ширину, 4:3.
        let r = PostcardPhotos.crop(width: 1260, height: 2736, centerY: 0.52)
        XCTAssertEqual(r.w, 1260)
        XCTAssertEqual(r.h, 945)
        XCTAssertEqual(r.x, 0)
        XCTAssertEqual(r.y, 2736 * 0.52 - 472.5, accuracy: 0.001)
        // У края — не выходит за картинку.
        let top = PostcardPhotos.crop(width: 1260, height: 2736, centerY: 0)
        XCTAssertEqual(top.y, 0)
        let bottom = PostcardPhotos.crop(width: 1260, height: 2736, centerY: 1)
        XCTAssertEqual(bottom.y + bottom.h, 2736, accuracy: 0.001)
        // Широкая картинка — окно во всю высоту.
        let wide = PostcardPhotos.crop(width: 2000, height: 600, centerY: 0.5)
        XCTAssertEqual(wide.h, 600)
        XCTAssertEqual(wide.w, 800)
        XCTAssertEqual(wide.x, 600)
        let fit = PostcardPhotos.fitted(width: 1260, height: 945)
        XCTAssertEqual(fit.w, 512)
        XCTAssertEqual(fit.h, 384)
        XCTAssertEqual(PostcardPhotos.fitted(width: 300, height: 200).w, 300, "маленькое не растягиваем")
    }

    // MARK: срок

    func testExpiryNoteAndLastDay() throws {
        var f = ppFile()
        let d = ppDay
        f.log("act.play", t: at(d, 10), source: .app, ok: true, reason: nil, key: nil, value: nil)
        Postcards.refresh(&f, now: at(d + 1, 8))
        let c = try XCTUnwrap(f.cards.pending.first)
        XCTAssertEqual(c.expiresT, at(d + 8, 0), "7 суток с полуночи, когда появилась")

        XCTAssertEqual(Postcards.daysLeft(c, now: at(d + 1, 8)), 7)
        XCTAssertEqual(Postcards.expiryNote(c, now: at(d + 1, 8)), "Не сохранишь — пропадёт через 7 дней.")
        XCTAssertFalse(Postcards.isLastDay(c, now: at(d + 1, 8)))
        XCTAssertEqual(Postcards.expiryNote(c, now: at(d + 5, 12)), "Не сохранишь — пропадёт через 3 дня.")
        XCTAssertEqual(Postcards.expiryNote(c, now: at(d + 6, 23, 59)), "Не сохранишь — пропадёт через 2 дня.")
        // Последние сутки — мягкое предупреждение.
        XCTAssertTrue(Postcards.isLastDay(c, now: at(d + 7, 0)))
        XCTAssertTrue(Postcards.isLastDay(c, now: at(d + 7, 23, 59)))
        XCTAssertEqual(Postcards.daysLeft(c, now: at(d + 7, 12)), 1)
        XCTAssertEqual(Postcards.expiryNote(c, now: at(d + 7, 12)), Postcards.lastDayNote)
        // Срок вышел — ни строки, ни открытки.
        XCTAssertFalse(Postcards.isLastDay(c, now: c.expiresT))
        XCTAssertNil(Postcards.expiryNote(c, now: c.expiresT))
        XCTAssertTrue(Postcards.active(f, now: c.expiresT).isEmpty)
        // Сохранённая — бессрочно.
        XCTAssertEqual(Postcards.save(c.id, in: &f, now: at(d + 7, 12)), .saved)
        let saved = try XCTUnwrap(f.cards.album.first)
        XCTAssertFalse(Postcards.isLastDay(saved, now: at(d + 7, 13)))
        XCTAssertNil(Postcards.expiryNote(saved, now: at(d + 7, 13)))
        XCTAssertNil(Postcards.daysLeft(saved, now: at(d + 30, 0)))
    }

    func testDaysWord() {
        XCTAssertEqual([1, 2, 4, 5, 7, 11, 12, 14, 21, 22, 25, 101, 111].map(Postcards.daysWord),
                       ["день", "дня", "дня", "дней", "дней", "дней", "дней", "дней", "день", "дня", "дней", "день", "дней"])
    }

    // MARK: сейв

    func testShotsRoundTripAndOldSave() throws {
        var f = ppFile()
        // Пустая книжка в файл не пишется: старые версии и виджет не видят лишнего ключа.
        let empty = try JSONSerialization.jsonObject(with: JSONEncoder().encode(f)) as? [String: Any]
        XCTAssertNil(empty?["shots"])
        take(&f, .play, at(ppDay, 10))
        let data = try JSONEncoder().encode(f)
        let g = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(g.shots, f.shots)
        // Старый сейв без поля — пустая книжка, остальное цело.
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj["shots"] = nil
        let old = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertTrue(old.shots.isEmpty)
        XCTAssertEqual(old.petId, f.petId)
        // Битый кадр не валит остальные, битая книжка не валит сейв.
        obj["shots"] = ["items": [["day": ppDay, "kind": "play", "t": 1, "score": 35, "file": "a.jpg"], ["day": "x"]],
                        "day": ppDay, "taken": 2]
        let lossy = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertEqual(lossy.shots.items.map(\.file), ["a.jpg"])
        XCTAssertEqual(lossy.shots.taken, 2)
        obj["shots"] = "мусор"
        let broken = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertTrue(broken.shots.isEmpty)
        XCTAssertEqual(broken.petId, f.petId)
    }

    func testNewPetKeepsAlbumPhotos() throws {
        var f = ppFile()
        let d = ppDay
        f.log("act.play", t: at(d, 10), source: .app, ok: true, reason: nil, key: nil, value: nil)
        take(&f, .play, at(d, 10))
        Postcards.refresh(&f, now: at(d + 1, 8))
        let c = try XCTUnwrap(f.cards.pending.first)
        Postcards.save(c.id, in: &f, now: at(d + 1, 9))
        take(&f, .bath, at(d + 1, 10))
        var fresh = SaveFile.fresh(now: at(d + 1, 11))
        fresh.cards = f.cards.carriedOver()
        XCTAssertEqual(PostcardPhotos.liveFiles(fresh), [c.image!], "кадр альбома переходит, кадры дня — нет")
    }
}
