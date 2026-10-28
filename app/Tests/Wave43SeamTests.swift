// Волна 43 L: хвосты волны 42 I. (1) Один источник текущего сезона: погода, декор и Мастерская сходятся
// и при PET_SEASON / закреплённом сезоне. (2) Несколько наград в одну запись — в тосте все (механизм 40 E + recent),
// без дублей при повторном settle. Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

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

/// 15 июля 2026, 00:00 UTC — середина лета.
private let july: Double = 1_784_073_600

/// Свежий сейв, учёт уже заведён; опыта — на 1 до уровня 5; сегодня не хватает одного дела до дня заботы,
/// а на неделе — одного дня до сундука. Одно действие даёт разом: день заботы, сундук недели, «Уровень 5».
private func allAtOnce(_ t: Double) -> SaveFile {
    var f = SaveFile.fresh(now: sT0)
    f.petId = "seam-pet-43"
    _ = Shards.settle(&f, now: sT0)
    _ = DogLevel.settle(&f, now: sT0)
    f.level.xp = DogLevel.xpTo(5) - 1
    f.level.paidLevel = 4
    let cfg = PremiumConfig.shared
    let d = DayKey.of(t)
    f.shardLog.day = d
    f.shardLog.dayActs = cfg.goalActs - 1
    f.shardLog.dayPaid = false
    f.shardLog.week = Shards.week(d)
    f.shardLog.weekDays = cfg.chestDays - 1
    f.shardLog.chestPaid = false
    return f
}

final class Wave43SeamTests: XCTestCase {

    override func tearDown() {
        Seasons.pinned = nil
        Weather.pinned = nil
        super.tearDown()
    }

    // MARK: 1. Один сезон на всех

    /// Weather.seasonNow — тот же сезон, что у декора и Мастерской (Seasons.now), при любом закреплённом.
    /// Раньше погода считала свой (по дате UTC) и не знала ни про pinned, ни про PET_SEASON.
    func testWeatherSeasonIsSeasonsNow() {
        XCTAssertEqual(Weather.seasonNow(), Seasons.now())
        for s in Season.allCases {
            Seasons.pinned = s
            XCTAssertEqual(Seasons.picked, s)
            XCTAssertEqual(Weather.seasonNow(), s)
            XCTAssertEqual(Seasons.now(), s)
            XCTAssertEqual(Seasons.shown(at: july, tzOffsetMin: 0), s, "сезон по заказу — и в июле")
        }
        Seasons.pinned = nil
        XCTAssertEqual(Weather.seasonNow(), Seasons.now())
    }

    /// Погода с сезоном «по заказу» берёт его шансы: зимой в июле идёт снег и не бывает грозы,
    /// а по календарю июль без снега.
    func testWeatherUsesPickedSeasonOdds() {
        let step = Double(WeatherConfig.shared.blockHours) * 3600
        var summerSnow = 0, winterSnow = 0, winterStorm = 0
        for i in 0..<240 {
            let t = july + Double(i) * step
            if Weather.at(t, tzOffsetMin: 0) == .snow { summerSnow += 1 }
            let w = Weather.at(t, tzOffsetMin: 0, season: .winter)
            if w == .snow { winterSnow += 1 }
            if w == .storm { winterStorm += 1 }
        }
        XCTAssertEqual(summerSnow, 0, "по календарю летом снега нет")
        XCTAssertGreaterThan(winterSnow, 0, "зима по заказу — снег")
        XCTAssertEqual(winterStorm, 0, "зимой грозы нет")
        // Без заказа — как раньше, по дате блока.
        XCTAssertEqual(Weather.at(july, tzOffsetMin: 0, season: nil), Weather.at(july, tzOffsetMin: 0))
    }

    /// Зимний квартал при закреплённой зиме — снег (сезон тот же, что у декора); летом — ясно, как во всём дворе
    /// под тестами. Квартал и сезон считаются на один момент.
    func testDistrictWeatherFollowsPickedSeason() {
        Seasons.pinned = .winter
        XCTAssertEqual(Weather.now(in: .winter), .snow)
        XCTAssertEqual(Weather.shown(at: july, tzOffsetMin: 0, in: .winter), .snow)
        XCTAssertEqual(Weather.now(in: .street), Weather.now())
        Seasons.pinned = .summer
        XCTAssertEqual(Weather.now(in: .winter), .clear)
        Weather.pinned = .rain
        XCTAssertEqual(Weather.now(in: .winter), .snow, "в Зимнем квартале дождь — снегом")
        XCTAssertEqual(Weather.now(in: .river), .rain)
    }

    /// Под тестами без заказа — как раньше: ясно, осень, реплик о сезоне нет (снимки не зависят от даты).
    func testUnderTestsWithoutPickIsStable() {
        XCTAssertNil(Seasons.picked)
        XCTAssertEqual(Seasons.now(), Seasons.testSeason)
        XCTAssertEqual(Weather.now(), .clear)
        XCTAssertEqual(Weather.now(in: .winter), .clear)
        XCTAssertNil(Seasons.talking(at: july, tzOffsetMin: 0))
        Seasons.pinned = .spring
        XCTAssertEqual(Seasons.talking(at: july, tzOffsetMin: 0), .spring)
    }

    // MARK: 2. Награды одной записи

    /// Одно действие: день заботы, сундук недели и «Уровень 5». Раньше ShardLog.last держал одну выплату,
    /// и «+3 ✂️ за день заботы» терялся за сундуком; теперь recent хранит все, а freshPlain отдаёт обычные.
    func testOneWriteKeepsAllPays() {
        let t = sT0 + 120
        var f = allAtOnce(t)
        XCTAssertTrue(PetRunner.apply(.pet, source: .app, to: &f, now: t).ok)
        let reasons = f.shardLog.recent.map(\.reason)
        XCTAssertTrue(reasons.contains("care_day"), "\(reasons)")
        XCTAssertTrue(reasons.contains("week_chest"), "\(reasons)")
        XCTAssertTrue(reasons.contains("ach.level_5"), "\(reasons)")

        let plain = Shards.freshPlain(f, now: t + 1, shownT: nil).map(\.reason)
        XCTAssertEqual(Set(plain), ["care_day", "week_chest"], "достижение — своим тостом по ids, не ✂️")
        XCTAssertEqual(plain.count, 2)
    }

    /// Один тост на всю запись: достижение и обе обычные выплаты, ничего не теряется.
    func testOneToastHasEveryReward() {
        let t = sT0 + 120
        var f = allAtOnce(t)
        XCTAssertTrue(PetRunner.apply(.pet, source: .app, to: &f, now: t).ok)
        var p = PendingAward()
        p.add(ids: ["level_5"])
        for g in Shards.freshPlain(f, now: t + 1, shownT: nil) { p.add(plain: g) }
        let a = try? XCTUnwrap(p.toast())
        XCTAssertEqual(a?.emoji, "🏆")
        let text = a?.text ?? ""
        XCTAssertTrue(text.hasPrefix(Achievements.toast(["level_5"]) ?? "?"), text)
        for g in f.shardLog.recent where !g.reason.hasPrefix("ach.") {
            XCTAssertTrue(text.contains(Shards.gainText(g)), "\(g.reason): \(text)")
        }
    }

    /// Повторный settle (refresh, следующая запись без наград) ничего не платит и новых выплат для тоста не даёт.
    func testRepeatSettleNoDuplicates() {
        let t = sT0 + 120
        var f = allAtOnce(t)
        XCTAssertTrue(PetRunner.apply(.pet, source: .app, to: &f, now: t).ok)
        let gs = Shards.freshPlain(f, now: t + 1, shownT: nil)
        XCTAssertEqual(gs.count, 2)
        let shownT = gs.map(\.t).max()

        let shards = f.econ.wallet.shards
        let recent = f.shardLog.recent
        PetRunner.settleRewards(&f, now: t + 2)
        PetRunner.settleRewards(&f, now: t + 3)
        XCTAssertEqual(f.econ.wallet.shards, shards, "повторный settle ничего не платит")
        XCTAssertEqual(f.shardLog.recent, recent)
        XCTAssertTrue(Shards.freshPlain(f, now: t + 4, shownT: shownT).isEmpty, "показанное не возвращается")
        // Через 10 с выплаты уже не свежие: после перезапуска (shownT забыт) тост не вернётся.
        XCTAssertTrue(Shards.freshPlain(f, now: t + 11, shownT: nil).isEmpty)
    }

    /// PendingAward: ids и выплаты без дублей, выплаты за достижения и нулевые не берёт.
    func testPendingAwardDedups() {
        var p = PendingAward()
        p.add(ids: ["level_5"])
        p.add(ids: ["level_5", "level_10"])
        XCTAssertEqual(p.ids, ["level_5", "level_10"])
        let day = ShardGain(reason: "care_day", shards: 3, t: sT0)
        p.add(plain: day)
        p.add(plain: day)
        p.add(plain: ShardGain(reason: "ach.level_5", shards: 5, t: sT0))
        p.add(plain: ShardGain(reason: "record", shards: 0, t: sT0))
        XCTAssertEqual(p.plain, [day])
        XCTAssertNil(PendingAward().toast())
    }

    /// Без достижения: одна выплата — прежний тост «+3 клочка за день заботы», несколько — все через « · ».
    func testPlainOnlyToast() {
        let day = ShardGain(reason: "care_day", shards: 3, t: sT0)
        let place = ShardGain(reason: "place.park", shards: 2, t: sT0)
        var p = PendingAward()
        p.add(plain: day)
        XCTAssertEqual(p.toast()?.text, Shards.toastText(day))
        XCTAssertEqual(p.toast()?.emoji, "✂️")
        p.add(plain: place)
        XCTAssertEqual(p.toast()?.text, "\(Shards.gainText(day)) · \(Shards.gainText(place))")
        // Старый вызов с одной выплатой — как раньше.
        XCTAssertEqual(Achievements.toast(["level_5"], also: day), Achievements.toast(["level_5"], alsoAll: [day]))
    }

    /// Выплаты из будущего (часы назад) и старше 10 с — не тосты.
    func testFreshGainsWindow() {
        var f = SaveFile.fresh(now: sT0)
        f.shardLog.note(ShardGain(reason: "care_day", shards: 3, t: sT0))
        f.shardLog.note(ShardGain(reason: "record", shards: 0, t: sT0))
        f.shardLog.note(ShardGain(reason: "find", shards: 1, t: sT0 + 100))
        XCTAssertEqual(Shards.freshGains(f, now: sT0 + 5).map(\.reason), ["care_day"])
        XCTAssertEqual(Shards.freshGains(f, now: sT0 + 105).map(\.reason), ["find"])
        XCTAssertTrue(Shards.freshGains(f, now: sT0 + 200).isEmpty)
    }

    /// recent — не больше recentMax, last — последняя; новому щенку — пусто; старый сейв без recent — по last.
    func testShardLogRecent() throws {
        var s = ShardLog()
        for i in 0..<10 { s.note(ShardGain(reason: "find", shards: 1, t: Double(i))) }
        XCTAssertEqual(s.recent.count, ShardLog.recentMax)
        XCTAssertEqual(s.recent.first?.t, Double(10 - ShardLog.recentMax))
        XCTAssertEqual(s.last?.t, 9)
        XCTAssertTrue(s.carriedOver().recent.isEmpty)
        XCTAssertNil(s.carriedOver().last)

        let back = try JSONDecoder().decode(ShardLog.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.recent, s.recent)

        let old = #"{"seenSeq":3,"last":{"reason":"care_day","shards":3,"t":100}}"#
        let o = try JSONDecoder().decode(ShardLog.self, from: Data(old.utf8))
        XCTAssertTrue(o.recent.isEmpty)
        var f = SaveFile.fresh(now: 100)
        f.shardLog = o
        XCTAssertEqual(Shards.freshGains(f, now: 101).map(\.reason), ["care_day"], "старый сейв — тост по last")
    }

    /// Место (Places.pay) тоже пишет в recent: клочки за место не теряются за днём заботы той же записи.
    func testRecentKeepsBothPaysOfOneWrite() {
        var f = SaveFile.fresh(now: sT0)
        f.shardLog.note(ShardGain(reason: "care_day", shards: 3, t: sT0))
        f.shardLog.note(ShardGain(reason: "place.park", shards: 2, t: sT0))
        XCTAssertEqual(Shards.freshPlain(f, now: sT0 + 1, shownT: nil).map(\.reason), ["care_day", "place.park"])
    }
}
