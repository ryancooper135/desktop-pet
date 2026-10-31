// Волна 52: «Пока тебя не было» 2.0 — отчёт из настоящего сейва: моменты (что делал пёс), копилка двора одной
// кнопкой «Забрать всё» (платит ровно как ручной сбор), что изменилось (погода, сезон, уровень, достижения)
// и одна подсказка с наградой. Логика — AwayBuilder в Shared/AwayReport.swift, чистая функция.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let awT0: Double = 1_760_054_400   // 2025-10-10 00:00 UTC
private let awH: Double = 3600

private let awFixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures").appendingPathComponent("upgrade")

final class AwayReportTests: XCTestCase {

    /// Как AppModel.becameActive: prev = seen ?? pet, догоняем время, собираем отчёт по сейву после догонки.
    private func comeBack(_ f: inout SaveFile, at now: Double,
                          weatherAt: @escaping AwayBuilder.WeatherAt = AwayBuilder.shownWeather,
                          seasonAt: @escaping AwayBuilder.SeasonAt = AwayBuilder.shownSeason) -> AwayReport? {
        let prev = f.seen ?? f.pet
        PetRunner.catchUp(&f, now: now)
        let r = AwayBuilder.make(f, prev: prev, now: now, weatherAt: weatherAt, seasonAt: seasonAt)
        f.seen = f.pet
        f.lastSeenT = now
        return r
    }

    private func json(_ f: SaveFile) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return String(decoding: try enc.encode(f), as: UTF8.self)
    }

    private func checkShape(_ r: AwayReport, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(r.cards.count, AwayBuilder.maxMiddle, what, file: file, line: line)
        XCTAssertLessThanOrEqual(r.changes.count, AwayBuilder.maxChanges, what, file: file, line: line)
        XCTAssertEqual(Set(r.cards.map(\.id)).count, r.cards.count, "\(what): моменты не повторяются", file: file, line: line)
        XCTAssertEqual(Set(r.changes.map(\.id)).count, r.changes.count, "\(what): перемены не повторяются", file: file, line: line)
        XCTAssertFalse(r.greet.isEmpty, what, file: file, line: line)
        for c in r.cards {
            XCTAssertFalse(c.icon.isEmpty, "\(what): \(c.id)", file: file, line: line)
            XCTAssertFalse(c.text.isEmpty, "\(what): \(c.id)", file: file, line: line)
            XCTAssertFalse(c.title.isEmpty, "\(what): \(c.id) — у момента есть короткий заголовок", file: file, line: line)
        }
        if let s = r.stash { XCTAssertFalse(s.isEmpty, "\(what): пустую копилку не показываем", file: file, line: line) }
    }

    // MARK: пустой отчёт

    func testShortAbsenceGivesNoReport() {
        var f = SaveFile.fresh(now: awT0)
        XCTAssertNil(comeBack(&f, at: awT0 + 10 * 60), "10 минут — отчёта нет")
        var g = SaveFile.fresh(now: awT0)
        XCTAssertNil(AwayBuilder.make(g, prev: g.pet, now: awT0), "ноль времени — тоже")
        XCTAssertNil(comeBack(&g, at: awT0 - awH), "часы назад — тоже")
    }

    /// Нового щенка без двора, уровня и достижений: блоков «Накопилось» и «Что изменилось» нет.
    func testFreshPetHasNoStashAndNoChanges() throws {
        var f = SaveFile.fresh(now: awT0)
        let r = try XCTUnwrap(comeBack(&f, at: awT0 + 6 * awH))
        checkShape(r, "6 ч")
        XCTAssertFalse(r.died)
        XCTAssertNil(r.stash, "двора нет — копить нечему")
        XCTAssertTrue(r.stashChips.isEmpty)
        XCTAssertTrue(r.changes.isEmpty, "под тестами погода и сезон стоят, уровня и достижений не было")
        XCTAssertFalse(r.cards.isEmpty, "хоть один момент есть всегда")
    }

    // MARK: только сон

    /// Ушёл в 22:00, вернулся в 7:00 — пёс проспал ночь: момент «Сон», ни копилки, ни перемен.
    func testSleepOnlyNight() throws {
        var f = SaveFile.fresh(now: awT0 - 2 * awH)
        let r = try XCTUnwrap(comeBack(&f, at: awT0 + 7 * awH))
        checkShape(r, "ночь")
        let ids = r.cards.map(\.id)
        XCTAssertTrue(ids.contains("slept") || ids.contains("nap"), "сон — первым делом: \(ids)")
        if let sleep = r.cards.first(where: { $0.id == "slept" }) {
            XCTAssertEqual(sleep.icon, "moon.zzz.fill")
            XCTAssertTrue(sleep.title.hasPrefix("Сон · "), sleep.title)
            XCTAssertTrue(sleep.title.hasSuffix(" ч"), sleep.title)
        }
        XCTAssertFalse(ids.contains("back_home"))
        XCTAssertFalse(ids.contains("autofed"))
        XCTAssertNil(r.stash)
        XCTAssertTrue(r.changes.isEmpty)
    }

    // MARK: накопилось

    private func yardFile() -> SaveFile {
        var f = SaveFile.fresh(now: awT0)
        f.yard.stations = ["dryer": 2, "sausage": 1]
        f.yard.t = awT0
        f.econ.wallet.coins = 100
        return f
    }

    func testStashShowsWhatCollectWouldGive() throws {
        var f = yardFile()
        let now = awT0 + 8 * awH
        let r = try XCTUnwrap(comeBack(&f, at: now))
        checkShape(r, "двор")
        let stash = try XCTUnwrap(r.stash, "станции копили 8 ч")
        XCTAssertGreaterThan(stash.coins, 0)
        XCTAssertGreaterThan(stash.pantry, 0, "колбасная станция даёт порции")
        XCTAssertTrue(r.stashChips.contains { $0.hasPrefix("Кладовая: ") }, "\(r.stashChips)")
        // Предпросмотр сейв не трогает: монеты по-прежнему в копилке.
        XCTAssertEqual(f.econ.wallet.coins, 100)
        XCTAssertEqual(AwayBuilder.stash(f, now: now), stash, "второй взгляд — то же самое")
    }

    /// «Забрать всё» = ручной сбор во дворе (Yard.collect + награды записи), бит в бит; и равно предпросмотру.
    func testCollectAllPaysExactlyLikeManualCollect() throws {
        var f = yardFile()
        let now = awT0 + 8 * awH
        let r = try XCTUnwrap(comeBack(&f, at: now))
        let stash = try XCTUnwrap(r.stash)

        var all = f
        let hAll = AwayBuilder.collectAll(in: &all, now: now)
        var hand = f
        let hHand = Yard.collect(in: &hand, now: now, dogLevel: DogLevel.level(hand))
        PetRunner.settleRewards(&hand, now: now)

        XCTAssertEqual(hAll, hHand)
        XCTAssertEqual(hAll, stash, "отчёт обещал ровно это")
        XCTAssertEqual(try json(all), try json(hand), "сейв после «Забрать всё» — как после сбора во дворе")
        XCTAssertGreaterThanOrEqual(all.econ.wallet.coins, 100 + hAll.coins)
        XCTAssertEqual(all.journal.filter { $0.kind == "yard.collect" }.count, 1)

        // Второй раз — пусто, отчёт копилку больше не показывает.
        let again = AwayBuilder.collectAll(in: &all, now: now)
        XCTAssertTrue(again.isEmpty)
        XCTAssertNil(AwayBuilder.stash(all, now: now))
    }

    func testStashChips() {
        var h = YardHarvest()
        h.coins = 40
        XCTAssertEqual(AwayBuilder.stashChips(h), [])
        h.portions = ["sausage": 2, "bones": 1]
        h.tickets = 1
        XCTAssertEqual(AwayBuilder.stashChips(h), ["Кладовая: 3 порции", "Билетик"])
        h.tickets = 2
        h.tip = .bonus
        h.bonus = 5
        XCTAssertEqual(AwayBuilder.stashChips(h), ["Кладовая: 3 порции", "Билетики ×2", "Чаевые +5"])
        h.portions = ["sausage": 5]
        h.tip = .ingredient
        XCTAssertEqual(AwayBuilder.stashChips(h), ["Кладовая: 5 порций", "Билетики ×2", "Гостинец соседей"])
    }

    // MARK: что изменилось

    func testChangesWeatherSeasonLevelAchievement() throws {
        var f = SaveFile.fresh(now: awT0)
        let now = awT0 + 6 * awH
        let mid = awT0 + 3 * awH
        let ach = try XCTUnwrap(Achievements.all.first)
        f.level.lastUp = LevelUp(level: 8, coins: 50, shards: 1, t: mid)
        f.shardLog.achT[ach.id] = mid
        let r = try XCTUnwrap(comeBack(&f, at: now,
                                       weatherAt: { $0 < mid ? .clear : .rain },
                                       seasonAt: { $0 < mid ? .summer : .autumn }))
        checkShape(r, "перемены")
        XCTAssertEqual(r.changes.map(\.id), ["season", "weather", "level", "ach.\(ach.id)"])
        XCTAssertEqual(r.changes.map(\.title), ["Наступила осень", "Пошёл дождь", "Уровень 8", "«\(ach.title)»"])
        XCTAssertEqual(r.changes[2].text, "Новый уровень 8: +50 🪙")
    }

    func testChangesOnlyInsideTheWindow() {
        var f = SaveFile.fresh(now: awT0)
        let ach = Achievements.all.first!
        f.level.lastUp = LevelUp(level: 3, coins: 10, shards: 0, t: awT0 - awH)
        f.shardLog.achT[ach.id] = awT0 - 1
        let c = AwayBuilder.changes(f, from: awT0, to: awT0 + 5 * awH,
                                    weatherAt: { _ in .snow }, seasonAt: { _ in .winter })
        XCTAssertTrue(c.isEmpty, "уровень и достижение — до ухода, погода и сезон те же: \(c.map(\.id))")
    }

    func testWeatherClearsUp() {
        let f = SaveFile.fresh(now: awT0)
        let c = AwayBuilder.changes(f, from: awT0, to: awT0 + 4 * awH,
                                    weatherAt: { $0 <= awT0 ? .storm : .clear }, seasonAt: { _ in .autumn })
        XCTAssertEqual(c.map(\.title), ["Распогодилось"])
        XCTAssertEqual(c.first?.icon, "sun.max.fill")
    }

    func testChangesCapped() {
        var f = SaveFile.fresh(now: awT0)
        for (i, a) in Achievements.all.prefix(6).enumerated() { f.shardLog.achT[a.id] = awT0 + Double(i + 1) * 60 }
        let c = AwayBuilder.changes(f, from: awT0, to: awT0 + 5 * awH,
                                    weatherAt: { $0 <= awT0 ? .clear : .cloudy }, seasonAt: { _ in .autumn })
        XCTAssertEqual(c.count, AwayBuilder.maxChanges)
        XCTAssertEqual(c.first?.id, "weather")
    }

    // MARK: подсказка

    /// Голодный пёс: подсказка «Покормить» с монетами за уход; дневной потолок выбран — награду не обещаем.
    func testHintNeedFeedWithHonestReward() throws {
        // Днём (13:00 UTC): ночью статус «спит», а не «голоден».
        let noon = awT0 + 12 * awH
        var f = SaveFile.fresh(now: noon)
        f.asks = DogAsksLog()
        let now = noon + awH
        f.pet.needs[.food] = 5
        let st = PetStatusLogic.of(f, now: now)
        XCTAssertEqual(st.kind, .need, "статус: \(st.kind)")
        XCTAssertEqual(st.act, .feed)
        XCTAssertNil(DogAsks.shown(f, now: now), "просьб пса у нового щенка ещё нет")
        let h = try XCTUnwrap(AwayBuilder.hint(f, now: now))
        XCTAssertEqual(h.kind, "need")
        XCTAssertEqual(h.action, .feed(Catalog.mainFood))
        XCTAssertEqual(h.button, IslandAct.feed.title)
        XCTAssertEqual(h.reward, "+\(EconomyConfig.shared.careCoins["feed"] ?? 0) 🪙")

        f.econ.daily.day = DayKey.of(now)
        f.econ.daily.care = EconomyConfig.shared.careDailyCap
        XCTAssertEqual(AwayBuilder.hint(f, now: now)?.reward, "", "за уход сегодня уже всё получено")
    }

    func testAskAndTaskActionsMap() {
        XCTAssertEqual(AwayBuilder.askAction("feed"), .feed(Catalog.mainFood))
        XCTAssertEqual(AwayBuilder.askAction("walk"), .walk)
        XCTAssertEqual(AwayBuilder.askAction("brush"), .brush)
        XCTAssertNil(AwayBuilder.askAction("trip"), "поход — с карты, не из отчёта")
        XCTAssertNil(AwayBuilder.askAction("collect"), "копилка — своей кнопкой «Забрать всё»")
        XCTAssertEqual(AwayBuilder.taskButton("walk"), "Гулять")
        XCTAssertEqual(AwayBuilder.taskButton("pet"), DogAskText.button("pet"))
    }

    /// Подсказка всегда исполнима: если есть действие, у кнопки есть текст.
    func testHintAlwaysHasButton() throws {
        for hours in [1.0, 3, 6, 9, 14, 30] {
            var f = SaveFile.fresh(now: awT0)
            guard let r = comeBack(&f, at: awT0 + hours * awH), let h = r.hint else { continue }
            XCTAssertFalse(h.title.isEmpty, "\(hours) ч")
            XCTAssertFalse(h.button.isEmpty, "\(hours) ч")
            XCTAssertTrue(["sick", "ask", "need", "task"].contains(h.kind), h.kind)
        }
    }

    // MARK: старый сейв

    /// Сейвы всех эпох (v0.15…w45): отчёт собирается без падений, блоки в рамках, «Забрать всё» = предпросмотр.
    func testOldSavesBuildReport() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: awFixtures.path)
            .filter { $0.hasPrefix("save-") && $0.hasSuffix(".json") }.sorted()
        XCTAssertGreaterThanOrEqual(files.count, 8)
        for name in files {
            let raw = try Data(contentsOf: awFixtures.appendingPathComponent(name))
            var f = try JSONDecoder().decode(SaveFile.self, from: raw)
            let start = max(f.pet.t, f.seen?.t ?? 0, f.lastSeenT ?? 0)
            let now = start + 9 * awH
            let r = comeBack(&f, at: now)
            guard let r else { continue }
            checkShape(r, name)
            if let s = r.stash {
                var g = f
                XCTAssertEqual(AwayBuilder.collectAll(in: &g, now: now), s, "\(name): забрали ровно обещанное")
            }
        }
    }
}
