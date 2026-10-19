// Память питомца (Memories): знакомство, первая прогулка и находки, трюки, вкусы, рекорд, первая вещь, дом, дни вместе;
// без дублей, с датой, старый сейв без поля и с потерянным началом журнала, стор и новый щенок, строки альбома и реплик.
// Гоняется и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let mT0: Double = 1_760_000_000
private let mDay: Double = 86400

/// Свежий сейв с поясом 0: дни и даты не зависят от машины CI.
private func mFresh(_ t: Double = mT0) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.owner.tzOffsetMin = 0
    return f
}

/// Пёс вернулся с находкой: в состоянии +1 и запись в журнале, как у PetRunner.advance.
private func mWalk(_ f: inout SaveFile, _ id: String, at t: Double) {
    f.pet.finds[id, default: 0] += 1
    f.log("ev.back_home.\(id)", t: t, key: id)
}

final class MemoriesTests: XCTestCase {

    // MARK: знакомство и повторы

    func testFreshBookHasOnlyMet() {
        var f = mFresh()
        Memories.update(&f)
        XCTAssertEqual(f.memories.items.map(\.id), ["met"])
        XCTAssertEqual(f.memories["met"]?.t, f.createdT)
        XCTAssertEqual(f.memories.seq, f.seq)
        let once = f.memories
        Memories.update(&f)
        XCTAssertEqual(f.memories, once, "повторный разбор ничего не добавляет")
    }

    // MARK: прогулки и находки

    func testFirstWalkThenNewFindsWithoutDuplicates() {
        var f = mFresh()
        Memories.update(&f)
        mWalk(&f, "cone", at: mT0 + 3600)
        Memories.update(&f)
        XCTAssertEqual(f.memories["walk.first"]?.key, "cone")
        XCTAssertEqual(f.memories["walk.first"]?.t, mT0 + 3600)
        XCTAssertNil(f.memories["find.cone"], "находка первой прогулки уже в walk.first")

        mWalk(&f, "cone", at: mT0 + 7200)
        mWalk(&f, "stick", at: mT0 + 9000)
        Memories.update(&f)
        Memories.update(&f)
        XCTAssertEqual(f.memories["find.stick"]?.t, mT0 + 9000)
        XCTAssertNil(f.memories["find.cone"])
        XCTAssertEqual(f.memories.items.filter { $0.kind == "walk" }.count, 1)
        XCTAssertEqual(Set(f.memories.items.map(\.id)).count, f.memories.items.count, "id без дублей")
    }

    /// Старый сейв: ранние прогулки уже ушли из журнала — «первой прогулки» задним числом нет,
    /// а находка, все записи которой ещё в журнале, засчитывается.
    func testOldSaveWithLostWalksGetsNoFirstWalk() {
        var f = mFresh()
        f.pet.finds["cone"] = 5
        f.log("ev.back_home.cone", t: mT0 + 100, key: "cone")
        f.log("ev.back_home.cone", t: mT0 + 200, key: "cone")
        mWalk(&f, "stick", at: mT0 + 300)
        XCTAssertNil(f.memories.seq, "книга ещё не заводилась")
        Memories.update(&f)
        XCTAssertNil(f.memories["walk.first"])
        XCTAssertNil(f.memories["find.cone"])
        XCTAssertEqual(f.memories["find.stick"]?.t, mT0 + 300)

        // Дальше — по новым записям, тоже без «первой прогулки».
        mWalk(&f, "leaf", at: mT0 + 400)
        Memories.update(&f)
        XCTAssertNil(f.memories["walk.first"])
        XCTAssertNotNil(f.memories["find.leaf"])
    }

    /// Первый разбор старого сейва с целым журналом: первая прогулка находится.
    func testOldSaveWithWholeJournalFindsFirstWalk() {
        var f = mFresh()
        mWalk(&f, "sock", at: mT0 + 100)
        mWalk(&f, "ball", at: mT0 + 200)
        Memories.update(&f)
        XCTAssertEqual(f.memories["walk.first"]?.key, "sock")
        XCTAssertEqual(f.memories["find.ball"]?.t, mT0 + 200)
    }

    // MARK: трюки, вкусы, дни

    func testTricksTastesAndDays() {
        var f = mFresh()
        f.tricks[.sit].learned = mT0 + mDay
        f.tricks[.lie].learned = mT0 + 2 * mDay
        f.tastes.opened["food.carrot"] = TasteLog.Fact(r: Taste.love.rawValue, t: mT0 + 3 * mDay)
        f.tastes.opened["food.broccoli"] = TasteLog.Fact(r: Taste.dislike.rawValue, t: mT0 + 3 * mDay)
        f.pet.t = mT0 + 31 * mDay
        Memories.update(&f)
        XCTAssertNotNil(f.memories["trick.sit"])
        XCTAssertNotNil(f.memories["trick.lie"])
        XCTAssertNotNil(f.memories["taste.food.carrot"])
        XCTAssertNil(f.memories["taste.food.broccoli"], "только любимое")
        XCTAssertNotNil(f.memories["days.7"])
        XCTAssertNotNil(f.memories["days.30"])
        XCTAssertNil(f.memories["days.50"])
        let born = Postcards.day(f.createdT, tzOffsetMin: 0)
        XCTAssertEqual(f.memories["days.30"]?.t, Postcards.dayStart(born + 30, tzOffsetMin: 0))

        let rows = Memories.album(f)
        let text = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.text) })
        XCTAssertEqual(text["trick.sit"], "Первый трюк — «Сидеть»")
        XCTAssertEqual(text["trick.lie"], "Выучил «Лежать»")
        XCTAssertEqual(text["taste.food.carrot"], "Обожает морковку")
        XCTAssertEqual(text["days.30"], "30 дней вместе")
        XCTAssertEqual(text["met"], "Познакомились")
        XCTAssertEqual(rows.last?.id, "met", "знакомство — внизу, новые сверху")
        XCTAssertEqual(rows.first(where: { $0.id == "days.30" })?.date,
                       Postcards.dateLabel(born + 30))
    }

    func testDeadPetGetsNoNewDays() {
        var f = mFresh()
        f.pet.alive = false
        f.pet.t = mT0 + 40 * mDay
        Memories.update(&f)
        XCTAssertNil(f.memories["days.7"])
    }

    func testMilestonesAndBirthday() {
        XCTAssertEqual(Memories.milestones(upTo: 0), [])
        XCTAssertEqual(Memories.milestones(upTo: 400), [7, 30, 50, 100, 200, 300, 365])
        XCTAssertTrue(Memories.milestones(upTo: 730).contains(730))
        XCTAssertEqual(Memories.text(Memory(id: "days.365", t: 0, value: 365)), "День рождения — 1 год")
        XCTAssertEqual(Memories.text(Memory(id: "days.730", t: 0, value: 730)), "День рождения — 2 года")
        XCTAssertEqual(Memories.years(5), "5 лет")
        XCTAssertEqual(Memories.years(21), "21 год")
        XCTAssertEqual(Memories.dayWord(12), "дней")
        XCTAssertEqual(Memories.dayWord(22), "дня")
    }

    // MARK: рекорд, вещь, дом

    /// Рекорд, перешедший от прошлого щенка, — база, не воспоминание. Побитый — одна запись, правится на месте.
    func testCatchRecordOnlyWhenBeaten() {
        var f = mFresh()
        f.catchBest = 20
        Memories.update(&f)
        XCTAssertNil(f.memories["catch.record"])
        XCTAssertEqual(f.memories.catchBase, 20)
        f.pet.t = mT0 + 600
        f.catchBest = 25
        Memories.update(&f)
        XCTAssertEqual(f.memories["catch.record"]?.value, 25)
        XCTAssertEqual(f.memories["catch.record"]?.t, mT0 + 600)
        f.catchBest = 31
        Memories.update(&f)
        XCTAssertEqual(f.memories["catch.record"]?.value, 31)
        XCTAssertEqual(f.memories.items.filter { $0.kind == "catch" }.count, 1)
    }

    func testFirstItemOnlyForVeryFirstPull() {
        var f = mFresh()
        Memories.update(&f)
        f.econ.capsule.pulls = 1
        f.log("capsule", t: mT0 + 50, key: "leaf_hat", value: 1)
        Memories.update(&f)
        XCTAssertEqual(f.memories["item.first"]?.key, "leaf_hat")
        f.econ.capsule.pulls = 2
        f.log("capsule", t: mT0 + 60, key: "scarf_knit", value: 1)
        Memories.update(&f)
        XCTAssertEqual(f.memories["item.first"]?.key, "leaf_hat")

        // Крутки были до журнала (или у прошлого щенка) — первой вещи не знаем.
        var g = mFresh()
        g.econ.capsule.pulls = 3
        g.log("capsule", t: mT0 + 50, key: "leaf_hat", value: 1)
        Memories.update(&g)
        XCTAssertNil(g.memories["item.first"])
    }

    func testHomeOneMemoryPerLine() throws {
        var f = mFresh()
        Memories.update(&f)
        f.log("home.buy", t: mT0 + 10, key: "bed", value: 1)
        Memories.update(&f)
        f.log("home.buy", t: mT0 + 20, key: "bed", value: 2)
        f.log("home.buy", t: mT0 + 30, key: "bath", value: 1)
        Memories.update(&f)
        XCTAssertEqual(f.memories.items.filter { $0.kind == "home" }.count, 2)
        XCTAssertEqual(f.memories["home.bed"]?.value, 2)
        XCTAssertEqual(f.memories["home.bed"]?.t, mT0 + 20)
        let line = try XCTUnwrap(HomeShop.line(.bed))
        XCTAssertEqual(Memories.text(try XCTUnwrap(f.memories["home.bed"])), "\(line.name): \(line.levels[2].name)")
    }

    // MARK: сейв

    func testSaveRoundTripAndOldFiles() throws {
        let empty = try JSONSerialization.jsonObject(with: JSONEncoder().encode(mFresh())) as? [String: Any]
        XCTAssertNil(empty?["memories"], "пустое не пишется")
        XCTAssertNil(empty?["care"])

        var f = mFresh()
        mWalk(&f, "cone", at: mT0 + 100)
        Memories.update(&f)
        Traits.update(&f)
        let back = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back.memories, f.memories)
        XCTAssertEqual(back.care, f.care)

        // Испорченное поле не ломает чтение сейва.
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(f)) as? [String: Any])
        obj["memories"] = 5
        obj["care"] = ["days": "x"]
        let bad = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertTrue(bad.memories.isEmpty)
        XCTAssertNil(bad.care.seq)
        XCTAssertEqual(bad.petId, f.petId)
    }

    func testStoreUpdatesAndNewPuppyStartsClean() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-memories")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: mT0)
        try store.mutate { (f: inout SaveFile) -> Void in
            f.tricks[.sit].learned = mT0 + 100
        }
        let before = try XCTUnwrap(store.read())
        XCTAssertNotNil(before.memories["trick.sit"], "стор разбирает память после записи")
        XCTAssertEqual(before.memories.seq, before.seq)
        XCTAssertNotNil(before.care.seq)

        try store.startOver(now: mT0 + mDay)
        let after = try XCTUnwrap(store.read())
        XCTAssertTrue(after.memories.items.allSatisfy { $0.t >= after.createdT }, "память не переходит новому щенку")
        XCTAssertNil(after.memories["trick.sit"])
    }

    // MARK: реплики

    /// Каждое воспоминание говорится: ключ есть в виджете и на острове, подстановки заполнены, длина в лимите.
    func testEveryMemoryHasLines() throws {
        let lines = Lines.shared
        guard !(lines.sections["widget"] ?? [:]).isEmpty else { throw XCTSkip("lines.json нет в бандле") }
        let all = [
            Memory(id: "met", t: 0),
            Memory(id: "walk.first", t: 0, key: "cone"),
            Memory(id: "find.pebble", t: 0, key: "pebble"),
            Memory(id: "trick.shake", t: 0, key: "shake"),
            Memory(id: "catch.record", t: 0, value: 42),
            Memory(id: "item.first", t: 0, key: "cape_champion"),
            Memory(id: "home.kennel", t: 0, key: "kennel", value: 3),
            Memory(id: "days.1000", t: 0, value: 1000),
            Memory(id: "days.730", t: 0, value: 730),
            Memory(id: "taste.food.gold_bone", t: 0, key: "food.gold_bone"),
            Memory(id: "taste.find.pebble", t: 0, key: "find.pebble"),
        ]
        for m in all {
            XCTAssertNotNil(Memories.text(m), m.id)
            let l = try XCTUnwrap(Memories.line(m), m.id)
            for section in ["widget", "island"] {
                let pool = try XCTUnwrap(lines.sections[section]?[l.key], "\(section).\(l.key)")
                XCTAssertGreaterThanOrEqual(pool.count, 2)
                for slot in 0..<pool.count {
                    let max = section == "island" ? LineLimit.island : LineLimit.widget
                    let it = try XCTUnwrap(lines.pick(section, l.key, seed: "p", slot: slot, vars: l.vars, maxLen: max))
                    XCTAssertFalse(it.text.contains("{"), it.text)
                    XCTAssertLessThanOrEqual(it.text.count, max, it.text)
                }
            }
        }
        let hat = Memories.itemName("leaf_hat")
        XCTAssertEqual(Memories.line(Memory(id: "item.first", t: 0, key: "leaf_hat"))?.vars["item"],
                       hat.prefix(1).lowercased() + hat.dropFirst(), "имя вещи со строчной")
        XCTAssertEqual(Memories.line(Memory(id: "days.365", t: 0, value: 365))?.vars["count"], "1 год")
    }

    /// Вспоминается только то, чему больше суток.
    func testRecallableIsAtLeastADayOld() {
        var f = mFresh()
        f.tricks[.sit].learned = mT0 + 3600
        f.pet.t = mT0 + 3600
        Memories.update(&f)
        XCTAssertEqual(Memories.recallable(f, at: mT0 + 7200).map(\.id), [])
        XCTAssertEqual(Memories.recallable(f, at: mT0 + 2 * mDay).map(\.id), ["met", "trick.sit"])
    }
}
