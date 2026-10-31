// Волна 42 I: баги на стыках волн 39–41 (достижения, сезоны, интерьер, клочки ✂️, «Новый щенок», пояс).
// Каждый тест падал до фикса. Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000.
private let sT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

/// Свежий сейв, учёт опыта и клочков уже заведён (первые settle прошли), опыта — на 1 до уровня 5.
private func nearLevel5() -> SaveFile {
    var f = SaveFile.fresh(now: sT0)
    f.petId = "seam-pet-42"
    _ = Shards.settle(&f, now: sT0)
    _ = DogLevel.settle(&f, now: sT0)
    f.level.xp = DogLevel.xpTo(5) - 1
    f.level.paidLevel = 4
    return f
}

final class Wave42SeamTests: XCTestCase {

    /// Действие, которое добило уровень 5, платит достижение «Уровень 5» в ту же запись — с датой нажатия
    /// и тостом сразу. Раньше Shards.settle шёл до DogLevel.settle и видел старый уровень: награда
    /// и дата «Получено» приходили только со следующей записью (через минуты или дни).
    func testLevelAchievementPaidInSameWrite() {
        var f = nearLevel5()
        XCTAssertFalse(f.shardLog.once.contains("ach.level_5"))
        let t = sT0 + 120
        XCTAssertTrue(PetRunner.apply(.pet, source: .app, to: &f, now: t).ok)
        XCTAssertGreaterThanOrEqual(DogLevel.level(f), 5)
        XCTAssertTrue(f.shardLog.once.contains("ach.level_5"), "достижение — в ту же запись")
        XCTAssertEqual(f.shardLog.achT["level_5"], t)
        XCTAssertEqual(Achievements.fresh(f, now: t + 1, shownT: nil)?.ids, ["level_5"], "тост сразу")
    }

    /// То же при догоне: опыт, пришедший в catchUp (вернулся с прогулки, день заботы), платит достижение сразу.
    func testLevelAchievementPaidInSameCatchUp() {
        var f = nearLevel5()
        f.log("trip.first", t: sT0 + 60)
        PetRunner.catchUp(&f, now: sT0 + 120)
        XCTAssertGreaterThanOrEqual(DogLevel.level(f), 5)
        XCTAssertTrue(f.shardLog.once.contains("ach.level_5"))
        XCTAssertEqual(f.shardLog.achT["level_5"], sT0 + 120)
    }

    // MARK: достижения из записей мимо PetRunner (кухня, трюк, открытка, двор с виджета)

    /// Первое блюдо: «Первое блюдо» — в той же записи (раньше — со следующим действием или заходом).
    func testFirstDishPaidAtOnce() {
        var f = SaveFile.fresh(now: sT0)
        f.petId = "seam-cook-42"
        for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 50 }
        f.pet.needs[.food] = 30
        f.pet.home[.kitchen] = 3
        f.pet.pantry = 60
        _ = Shards.settle(&f, now: sT0)
        let t = sT0 + 60
        let out = Cooking.cook("stew_home", in: &f, now: t)
        XCTAssertTrue(out.ok, out.text)
        XCTAssertTrue(f.shardLog.once.contains("ach.first_dish"))
        XCTAssertEqual(f.shardLog.achT["first_dish"], t)
    }

    /// Выученный трюк: «Первый трюк» — в ту же запись, что и выучка.
    func testFirstTrickPaidAtOnce() {
        var f = SaveFile.fresh(now: sT0)
        f.petId = "seam-trick-42"
        for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
        var t = sT0
        var learned: TrickOutcome?
        for _ in 0..<Trick.sit.needed {
            let o = Tricks.attempt(.sit, in: &f, now: t, roll: 0)
            if o.learnedNow { learned = o; break }
            t += Tricks.gap
        }
        XCTAssertEqual(learned?.learnedNow, true)
        XCTAssertTrue(f.shardLog.once.contains("ach.first_trick"))
        XCTAssertEqual(f.shardLog.achT["first_trick"], t)
    }

    /// Открытка в альбом: «Первая открытка» — в ту же запись (через стор, как с экрана).
    func testFirstPostcardPaidAtOnce() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-seam-card")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: sT0)
        try store.mutate { (f: inout SaveFile) -> Void in
            for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 90 }
            _ = PetRunner.apply(.bath, source: .app, to: &f, now: sT0 + 60)
        }
        // Местная полночь прошла: открытка за вчера ждёт в «новых».
        let next = sT0 + 13 * 3600
        try store.mutate { (f: inout SaveFile) -> Void in PetRunner.catchUp(&f, now: next) }
        let id = try XCTUnwrap(store.read()?.cards.pending.first?.id)
        XCTAssertEqual(try Postcards.save(id, store: store, now: next + 60), .saved)
        let f = try XCTUnwrap(store.read())
        XCTAssertTrue(f.shardLog.once.contains("ach.postcard_first"))
        XCTAssertEqual(f.shardLog.achT["postcard_first"], next + 60)
    }

    /// «Собрать» двор с виджета: опыт за сбор добил уровень — «Ур. 5» в той же записи.
    func testYardCollectFromWidgetPaysLevelAchievement() {
        var f = nearLevel5()
        f.econ.wallet.coins = 1_000
        for id in ["window", "daisy", "dryer"] {
            guard case .ok = Yard.buyPlate(id, in: &f, now: sT0, dogLevel: DogLevel.level(f)) else {
                return XCTFail("не купить \(id)")
            }
        }
        _ = Shards.settle(&f, now: sT0)
        f.level.xp = DogLevel.xpTo(5) - 1
        let t = sT0 + 6 * 3600
        let h = WidgetLook.collect(in: &f, now: t)
        XCTAssertFalse(h.isEmpty)
        XCTAssertGreaterThanOrEqual(DogLevel.level(f), 5)
        XCTAssertTrue(f.shardLog.once.contains("ach.level_5"))
        XCTAssertEqual(f.shardLog.achT["level_5"], t)
    }
}
