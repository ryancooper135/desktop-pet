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
}
