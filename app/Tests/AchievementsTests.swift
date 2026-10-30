// Волна 39 C: достижения (Achievements.swift + раздел 4 Shards.settle). Прогресс каждого, выплата один раз
// с датой, старые ach.* без повторной выплаты, бюджет наград, длина текстов, тост.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000.
private let aT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

private func aFile() -> SaveFile {
    var f = SaveFile.fresh(now: aT0)
    f.petId = "achieve-pet-1"
    return f
}

private func card(_ day: Int) -> Postcard {
    Postcard(id: "c\(day)", day: day, kind: "play", t: Double(day) * 86400, tz: 0, score: 35, caption: "Играли.",
             lineId: nil, find: nil, item: nil, count: nil, pose: "happy", clip: nil, prop: nil,
             expiresT: Double(day + 8) * 86400, savedT: Double(day + 1) * 86400, image: nil)
}

private let oldIds = ["good_days_7", "good_days_30", "good_days_100", "first_dish", "first_trick"]

/// Сейв, где выполнено всё.
private func allDone() -> SaveFile {
    var f = aFile()
    f.shardLog.goodDays = 100
    f.level.xp = DogLevel.xpTo(30)
    f.growth.points = GrowthConfig.shared.adult + 1
    f.yard.stations["dryer"] = 1
    f.yard.gold = ["dryer"]
    f.yard.moves = YardConfig.shared.gloryX.count
    for p in PlacesConfig.shared.places { f.trip.visits[p.id] = 1 }
    f.trip.count = PlacesConfig.shared.places.count
    f.trip.sets = ["bus_stop"]
    for x in Finds.all { f.pet.finds[x.id] = 1 }
    for r in CookConfig.shared.recipes { f.cooking.total[r.id] = 1 }
    for t in Trick.allCases {
        var e = TrickLog.Entry()
        e.learned = aT0
        f.tricks.items[t.rawValue] = e
    }
    f.catchBest = 3
    f.blockduoBest = 4
    f.challenge.count = 10
    f.cards.album = (0..<10).map { card(20_000 + $0) }
    return f
}

final class AchievementsTests: XCTestCase {

    // MARK: список и цифры

    func testListShape() {
        let ids = Achievements.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "id не повторяются")
        XCTAssertTrue((20...26).contains(ids.count), "достижений \(ids.count)")
        XCTAssertEqual(Array(ids.prefix(5)), oldIds, "старые пять — первыми и с теми же id")
        for id in ids {
            XCTAssertGreaterThan(Achievements.reward(id), 0, "награда \(id)")
            XCTAssertGreaterThan(Achievements.goal(id), 0, "цель \(id)")
        }
        XCTAssertEqual(Set(PremiumConfig().achievements.keys), Set(ids), "награды в конфиге — ровно на список")
    }

    func testOldRewardsUnchanged() {
        let c = PremiumConfig.shared.achievements
        XCTAssertEqual(c["good_days_7"], 5)
        XCTAssertEqual(c["good_days_30"], 10)
        XCTAssertEqual(c["good_days_100"], 25)
        XCTAssertEqual(c["first_dish"], 3)
        XCTAssertEqual(c["first_trick"], 3)
    }

    func testNewRewardsBudget() {
        let new = Achievements.all.map(\.id).filter { !oldIds.contains($0) }
        let sum = new.reduce(0) { $0 + Achievements.reward($1) }
        XCTAssertLessThanOrEqual(sum, 150, "все новые достижения вместе")
        XCTAssertGreaterThan(sum, 0)
        for id in new { XCTAssertLessThanOrEqual(Achievements.reward(id), 12, "одно достижение не ломает дефицит: \(id)") }
    }

    func testTextsShort() {
        for a in Achievements.all {
            XCTAssertLessThanOrEqual(a.title.count, 30, a.id)
            XCTAssertLessThanOrEqual(a.note.count, 60, a.id)
            XCTAssertFalse(a.emoji.isEmpty, a.id)
            let toast = Achievements.toast([a.id]) ?? ""
            XCTAssertLessThanOrEqual(toast.count, 60, toast)
            XCTAssertLessThanOrEqual(Shards.toastText(ShardGain(reason: "ach.\(a.id)", shards: 12, t: 0)).count, 60)
        }
        XCTAssertEqual(Achievements.summary(aFile()), "Получено 0 из \(Achievements.all.count)")
    }

    // MARK: прогресс

    func testFreshSaveHasNothing() {
        var f = aFile()
        XCTAssertEqual(Achievements.reached(f), [])
        XCTAssertTrue(Shards.settle(&f, now: aT0).isEmpty)
        for r in Achievements.rows(f) {
            XCTAssertFalse(r.got, r.id)
            XCTAssertNil(r.t, r.id)
        }
    }

    func testProgressEach() {
        var f = aFile()
        func p(_ id: String) -> Int { Achievements.progress(id, f) }

        f.shardLog.goodDays = 3
        XCTAssertEqual(p("good_days_7"), 3)
        f.cooking.total["porridge"] = 2
        XCTAssertEqual(p("first_dish"), 1)
        var e = TrickLog.Entry()
        e.learned = aT0
        f.tricks.items["sit"] = e
        XCTAssertEqual(p("first_trick"), 1)
        XCTAssertEqual(p("tricks_all"), 1)

        XCTAssertEqual(p("level_5"), 1)
        f.level.xp = DogLevel.xpTo(7)
        XCTAssertEqual(p("level_5"), 7)
        XCTAssertTrue(Achievements.done("level_5", f))
        XCTAssertFalse(Achievements.done("level_10", f))

        f.growth.points = 4.6
        XCTAssertEqual(p("grow_teen"), 4)

        XCTAssertEqual(p("yard_station"), 0)
        f.yard.stations["dryer"] = 2
        XCTAssertEqual(p("yard_station"), 1)
        f.yard.gold = ["dryer"]
        XCTAssertEqual(p("yard_gold"), 1)
        f.yard.moves = 1
        XCTAssertEqual(p("yard_move"), 1)
        XCTAssertEqual(p("yard_roof"), 1)
        XCTAssertFalse(Achievements.done("yard_roof", f))

        f.trip.count = 2
        f.trip.visits = ["bus_stop": 2, "nowhere": 5]
        XCTAssertEqual(p("trip_first"), 2)
        XCTAssertEqual(p("trip_all"), 1, "неизвестное место не считается")
        XCTAssertEqual(p("trip_set"), 0)
        f.trip.sets = ["bus_stop"]
        XCTAssertEqual(p("trip_set"), 1)

        f.pet.finds = ["stick": 3, "cone": 1]
        XCTAssertEqual(p("finds_all"), 2)
        XCTAssertEqual(p("recipes_all"), 1)

        f.catchBest = 7
        XCTAssertEqual(p("games_all"), 1)

        f.challenge.count = 3
        XCTAssertEqual(p("challenge_first"), 3)
        XCTAssertEqual(p("challenge_10"), 3)

        f.cards.album = [card(20_000), card(20_001)]
        XCTAssertEqual(p("postcard_first"), 2)
        XCTAssertEqual(p("postcards_10"), 2)

        // Строки экрана: прогресс не больше цели, полоска 0…1.
        let rows = Achievements.rows(f)
        let cha = rows.first { $0.id == "challenge_first" }!
        XCTAssertEqual(cha.progress, 1)
        XCTAssertEqual(cha.goal, 1)
        let ten = rows.first { $0.id == "challenge_10" }!
        XCTAssertEqual(Achievements.progressText(ten), "3 / 10")
        XCTAssertEqual(ten.fraction, 0.3, accuracy: 0.001)
    }

    func testAllReachedAndPaid() {
        var f = allDone()
        XCTAssertEqual(Achievements.reached(f), Achievements.all.map(\.id), "каждое достижимо")
        let before = f.econ.wallet.shards
        let gains = Shards.settle(&f, now: aT0)
        let total = Achievements.all.reduce(0) { $0 + Achievements.reward($1.id) }
        XCTAssertEqual(gains.filter { $0.reason.hasPrefix("ach.") }.reduce(0) { $0 + $1.shards }, total)
        XCTAssertEqual(f.econ.wallet.shards - before, gains.reduce(0) { $0 + $1.shards })
        XCTAssertEqual(Achievements.gotCount(f), Achievements.all.count)
        XCTAssertEqual(Achievements.summary(f), "Получено \(Achievements.all.count) из \(Achievements.all.count)")
        for r in Achievements.rows(f) {
            XCTAssertTrue(r.got, r.id)
            XCTAssertEqual(r.t, aT0, r.id)
            XCTAssertEqual(r.fraction, 1)
        }
    }

    // MARK: выплата

    func testPaidOnceWithDate() {
        var f = aFile()
        f.level.xp = DogLevel.xpTo(5)
        let g = Shards.settle(&f, now: aT0)
        XCTAssertEqual(g.map(\.reason), ["ach.level_5"])
        XCTAssertEqual(g.first?.shards, 2)
        XCTAssertEqual(f.shardLog.achT["level_5"], aT0)
        XCTAssertTrue(f.shardLog.once.contains("ach.level_5"))
        let wallet = f.econ.wallet.shards
        XCTAssertTrue(Shards.settle(&f, now: aT0 + 60).isEmpty, "второй раз не платит")
        XCTAssertEqual(f.econ.wallet.shards, wallet)
        XCTAssertEqual(f.shardLog.achT["level_5"], aT0, "дата не переписывается")
        let row = Achievements.rows(f).first { $0.id == "level_5" }!
        XCTAssertEqual(Achievements.gotText(row), "Получено \(Postcards.dateLabel(DayKey.of(aT0)))")
    }

    func testOldOnceNotPaidAgain() {
        var f = aFile()
        f.shardLog.goodDays = 8
        f.cooking.total["porridge"] = 1
        var e = TrickLog.Entry()
        e.learned = aT0
        f.tricks.items["sit"] = e
        // Старый сейв (волна 32): всё уже оплачено, даты нет.
        f.shardLog.once = ["ach.good_days_7", "ach.first_dish", "ach.first_trick", "find:stick"]
        let wallet = f.econ.wallet.shards
        XCTAssertTrue(Shards.settle(&f, now: aT0).isEmpty)
        XCTAssertEqual(f.econ.wallet.shards, wallet)
        XCTAssertTrue(f.shardLog.achT.isEmpty)
        let rows = Achievements.rows(f)
        let week = rows.first { $0.id == "good_days_7" }!
        XCTAssertTrue(week.got)
        XCTAssertNil(week.t)
        XCTAssertEqual(Achievements.gotText(week), "Получено")
        XCTAssertEqual(Achievements.gotCount(f), 3)
    }

    func testNewPuppyKeepsAchievements() {
        var f = allDone()
        Shards.settle(&f, now: aT0)
        let kept = f.shardLog.carriedOver()
        var g = aFile()
        g.shardLog = kept
        XCTAssertEqual(Achievements.gotCount(g), Achievements.all.count, "достижения — хозяина")
        XCTAssertTrue(Shards.settle(&g, now: aT0 + 86400).filter { $0.reason.hasPrefix("ach.") }.isEmpty)
        let lvl = Achievements.rows(g).first { $0.id == "level_10" }!
        XCTAssertTrue(lvl.got)
        XCTAssertEqual(lvl.fraction, 1, "полученное — полной полоской, хоть щенок и с нуля")
    }

    /// Очень активная первая неделя: из новых достижений приходит немного — дефицит ✂️ цел.
    func testFirstWeekBudget() {
        var f = aFile()
        f.level.xp = DogLevel.xpTo(10)
        f.growth.points = 7
        f.yard.stations["dryer"] = 3
        f.trip.count = 5
        f.trip.visits = ["bus_stop": 3, "laundry": 2]
        f.trip.sets = ["bus_stop"]
        for x in Finds.all { f.pet.finds[x.id] = 2 }
        f.catchBest = 10
        f.blockduoBest = 10
        f.challenge.count = 6
        f.cards.album = (0..<6).map { card(20_000 + $0) }
        let gains = Shards.settle(&f, now: aT0).filter { $0.reason.hasPrefix("ach.") }
        let new = gains.filter { !oldIds.contains(String($0.reason.dropFirst(4))) }.reduce(0) { $0 + $1.shards }
        XCTAssertGreaterThan(new, 0)
        XCTAssertLessThanOrEqual(new, 20, "первая неделя: \(gains.map(\.reason))")
    }

    // MARK: тост и тексты

    func testToastFresh() {
        var f = aFile()
        f.level.xp = DogLevel.xpTo(10)
        Shards.settle(&f, now: aT0)
        let fr = Achievements.fresh(f, now: aT0 + 2, shownT: nil)
        XCTAssertEqual(fr?.ids, ["level_5", "level_10"])
        XCTAssertEqual(fr?.t, aT0)
        XCTAssertEqual(Achievements.toast(fr?.ids ?? []), "Достижения: 2 новых · +5 ✂️")
        XCTAssertNil(Achievements.fresh(f, now: aT0 + 2, shownT: aT0), "уже показано")
        XCTAssertNil(Achievements.fresh(f, now: aT0 + 30, shownT: nil), "старое не показываем")
        XCTAssertEqual(Achievements.toast(["level_10"]), "Достижение: Ур. 10 · +3 ✂️")
        XCTAssertNil(Achievements.toast([]))
    }

    /// Волна 40 E: достижение и обычная выплата одного действия — один тост, не два подряд.
    func testToastAlso() {
        let day = ShardGain(reason: "care_day", shards: 3, t: aT0)
        XCTAssertEqual(Achievements.toast(["good_days_7"], also: day),
                       "Достижение: Неделя заботы · +\(Achievements.reward("good_days_7")) ✂️ · +3 ✂️ за день заботы")
        XCTAssertEqual(Achievements.toast(["level_10"], also: ShardGain(reason: "ach.level_5", shards: 2, t: aT0)),
                       "Достижение: Ур. 10 · +3 ✂️", "достижение в also не дублируем")
        // Самый длинный вариант — две строки тоста, не больше.
        let reasons = ["care_day", "week_chest", "record", "find", "new_find", Places.shardReason, Places.setReason,
                       Places.wellReason]
        for a in Achievements.all {
            for r in reasons {
                let t = Achievements.toast([a.id], also: ShardGain(reason: r, shards: 12, t: aT0)) ?? ""
                XCTAssertLessThanOrEqual(t.count, 80, t)
            }
        }
    }

    /// Волна 40 E: «7 дней заботы» в той же записи, что и день заботы, не затирает last — тост ✂️ не теряется.
    func testAchievementKeepsFreshPlainGain() {
        var f = aFile()
        f.level.xp = DogLevel.xpTo(5)
        f.shardLog.last = ShardGain(reason: "care_day", shards: 3, t: aT0)
        let g = Shards.settle(&f, now: aT0 + 1)
        XCTAssertEqual(g.map(\.reason), ["ach.level_5"])
        XCTAssertEqual(f.shardLog.last?.reason, "care_day", "свежая обычная выплата осталась последней")
        XCTAssertEqual(Shards.freshGain(f, now: aT0 + 2, shownT: nil)?.reason, "care_day")
        // Старую обычную выплату достижение сменяет как раньше.
        var h = aFile()
        h.level.xp = DogLevel.xpTo(5)
        h.shardLog.last = ShardGain(reason: "care_day", shards: 3, t: aT0 - 3600)
        Shards.settle(&h, now: aT0)
        XCTAssertEqual(h.shardLog.last?.reason, "ach.level_5")
    }

    /// Волна 40 E: уровень, взятый в записи (тут — миграция старого сейва), платит «Ур. N» в ней же, а не при
    /// следующем действии.
    func testSettleRewardsPaysLevelSameWrite() {
        var f = aFile()
        f.shardLog.goodDays = 30
        f.shardLog.once = ["ach.good_days_7", "ach.good_days_30"]
        XCTAssertFalse(f.level.started)
        PetRunner.settleRewards(&f, now: aT0)
        XCTAssertGreaterThanOrEqual(DogLevel.level(f), 5)
        XCTAssertTrue(Achievements.got("level_5", f), "в той же записи")
        XCTAssertEqual(f.shardLog.achT["level_5"], aT0)
    }

    /// Волна 40 E: список игр с рекордом один — ChallengeGame; цель «Все игры» и рекорды из него же.
    func testRecordGamesOneSource() {
        let games = ChallengeGame.allCases.map(\.rawValue)
        XCTAssertEqual(Shards.recordGames, games)
        let f = allDone()
        XCTAssertEqual(Set(Shards.records(f).keys), Set(games))
        XCTAssertEqual(Achievements.goal("games_all"), games.count)
        XCTAssertEqual(Achievements.progress("games_all", f), games.count)
        XCTAssertEqual(Set(DogLevel.games(f).keys), Set(games), "опыт за партии — по тем же играм")
        for g in ChallengeGame.allCases { XCTAssertGreaterThan(g.record(f), 0, g.rawValue) }
    }

    func testReasonText() {
        XCTAssertEqual(Shards.reasonText("ach.first_dish"), "первое блюдо", "старые подписи как были")
        XCTAssertEqual(Shards.reasonText("ach.trip_all"), "за достижение «Все места»")
        XCTAssertEqual(Shards.reasonText("ach.nope"), "награда")
    }

    func testSpeech() {
        var f = aFile()
        f.challenge.count = 4
        let r = Achievements.rows(f).first { $0.id == "challenge_10" }!
        XCTAssertEqual(Achievements.speech(r),
                       "Десять челленджей. Выполнить 10 челленджей. Пока 4 из 10. Награда \(EconText.shards(6))")
    }

    // MARK: сейв

    func testAchTRoundTripAndOldSave() throws {
        var s = ShardLog()
        s.once = ["ach.level_5"]
        s.achT = ["level_5": aT0]
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(ShardLog.self, from: data), s)
        let old = #"{"seenSeq":3,"once":["ach.good_days_7"],"goodDays":7}"#.data(using: .utf8)!
        let o = try JSONDecoder().decode(ShardLog.self, from: old)
        XCTAssertEqual(o.achT, [:])
        XCTAssertEqual(o.once, ["ach.good_days_7"])
    }
}
