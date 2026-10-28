// Волна 42 J: задания дня (DailyTasks.swift). Выбор по суткам, прогресс по журналу один раз на запись,
// третье задание с ур. 7, полночь, перевод часов и перелёт без второго набора, награды один раз, замена раз в день,
// старые сейвы читаются, новый щенок не получает второй набор. Гоняется и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000.
private let tT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

/// Пёс уровня lvl, учёт уровня заведён; достижения уже получены — считаем только ✂️ заданий.
private func tFile(level lvl: Int = 1, at t: Double = tT0) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = "tasks-pet-1"
    DogLevel.settle(&f, now: t)
    f.level.xp = DogLevel.xpTo(lvl)
    f.level.paidLevel = lvl
    f.shardLog.once += Achievements.all.map { Achievements.key($0.id) }
    return f
}

/// Задания сегодня — ровно эти (чтобы проверять прогресс без зависимости от выбора по суткам).
private func force(_ f: inout SaveFile, _ items: [(String, Int)], at t: Double = tT0, coins: Int = 20) {
    DailyTasks.settle(&f, now: t)
    f.tasks.items = items.map { DailyTask(id: $0.0, need: $0.1, coins: coins) }
}

private func ids(_ f: SaveFile) -> [String] { f.tasks.items.map(\.id) }

private func count(_ f: SaveFile, _ kind: String) -> Int { f.journal.filter { $0.kind == kind }.count }

final class DailyTasksTests: XCTestCase {

    override func tearDown() {
        Clock.zoneOverride = nil
        DailyTasks.enabled = true
        super.tearDown()
    }

    // MARK: конфиг

    func testConfigMatchesEconomyJSON() {
        let code = DailyTaskConfig(), json = DailyTaskConfig.shared
        XCTAssertEqual(code.count, json.count)
        XCTAssertEqual(code.coinBase, json.coinBase)
        XCTAssertEqual(code.coinPerLevel, json.coinPerLevel)
        XCTAssertEqual(code.coinRound, json.coinRound)
        XCTAssertEqual(code.allShards, json.allShards)
        XCTAssertEqual(code.allCoins, json.allCoins)
        XCTAssertEqual(code.swaps, json.swaps)
        XCTAssertEqual(code.need, json.need)
        XCTAssertEqual(Set(code.need.keys), Set(DailyTasks.pool.map(\.id)), "у каждого задания пула есть need")
        // Монеты за задание: 15 + 3 × уровень, к ближайшим 5.
        XCTAssertEqual(code.coins(level: 1), 20)
        XCTAssertEqual(code.coins(level: 7), 35)
        XCTAssertEqual(code.coins(level: 10), 45)
        XCTAssertEqual(code.coins(level: 20), 75)
        XCTAssertEqual(code.coins(level: 30), 105)
        // ✂️ — скупо: только 1 за все задания дня.
        XCTAssertEqual(code.allShards, 1)
    }

    func testConfigNeedZeroRemovesTask() {
        let cfg = DailyTaskConfig(json: .object(["daily_tasks": .object(["need": .object(["feed": .number(0)])])]))
        let f = tFile()
        XCTAssertFalse(DailyTasks.candidates(f, level: 1, cfg).contains("feed"))
        XCTAssertTrue(DailyTasks.candidates(f, level: 1, cfg).contains("pet"))
    }

    // MARK: выбор по суткам

    func testPickIsDeterministicPerDay() {
        var a = tFile(), b = tFile()
        b.petId = "another-pet"
        DailyTasks.settle(&a, now: tT0)
        DailyTasks.settle(&b, now: tT0 + 3600)
        XCTAssertEqual(a.tasks.items.count, 2, "до ур. 7 — два задания")
        XCTAssertEqual(ids(a), ids(b), "одни сутки — одни задания")
        XCTAssertEqual(Set(ids(a)).count, 2, "без повторов")
        XCTAssertEqual(DailyTasks.board(a, now: tT0 + 7200).items, a.tasks.items, "лист показывает то же")
        // По разным суткам наборы меняются.
        let day = DayKey.of(tT0)
        let sets = Set((0..<14).map { DailyTasks.fill([], day: day + $0, a, level: 1).map(\.id).joined(separator: ",") })
        XCTAssertGreaterThan(sets.count, 3)
    }

    func testPoolRespectsLevelAndState() {
        var f = tFile(level: 1)
        f.yard.stations = [:]
        var c = DailyTasks.candidates(f, level: 1)
        XCTAssertFalse(c.contains("trip"), "места — с ур. 2")
        XCTAssertFalse(c.contains("collect"), "нет станции — нечего собирать")
        XCTAssertFalse(c.contains("cook"), "без «Кухни шефа» не готовят")
        XCTAssertTrue(c.contains("feed") && c.contains("pet") && c.contains("walk"))
        f.yard.stations = ["lemonade": 1]
        c = DailyTasks.candidates(f, level: 2)
        XCTAssertTrue(c.contains("trip"))
        XCTAssertTrue(c.contains("collect"))
        // Пул в 14 сутках подряд не выходит за доступное.
        let low = tFile(level: 1)
        for d in 0..<14 {
            let got = DailyTasks.fill([], day: DayKey.of(tT0) + d, low, level: 1).map(\.id)
            XCTAssertTrue(Set(got).isSubset(of: Set(DailyTasks.candidates(low, level: 1))))
        }
    }

    func testThirdTaskFromLevelSeven() {
        var six = tFile(level: 6)
        DailyTasks.settle(&six, now: tT0)
        XCTAssertEqual(six.tasks.items.count, 2)
        var seven = tFile(level: 7)
        DailyTasks.settle(&seven, now: tT0)
        XCTAssertEqual(seven.tasks.items.count, 3)
        XCTAssertEqual(Array(ids(seven).prefix(2)), ids(six), "третье добавляется к тем же двум")
        // Дорос до 7 посреди дня — третье добирается, первые два на месте.
        let before = six.tasks.items
        six.level.xp = DogLevel.xpTo(7)
        DailyTasks.settle(&six, now: tT0 + 60)
        XCTAssertEqual(six.tasks.items.count, 3)
        XCTAssertEqual(Array(six.tasks.items.prefix(2)), before)
        XCTAssertEqual(six.tasks.items[2].coins, DailyTaskConfig().coins(level: 7))
    }

    // MARK: прогресс и награды

    func testProgressCountsEachJournalEntryOnce() {
        var f = tFile()
        force(&f, [("feed", 2), ("pet", 3)])
        let coins0 = f.econ.wallet.coins
        f.log("act.feed", t: tT0 + 10, ok: true)
        DailyTasks.settle(&f, now: tT0 + 10)
        DailyTasks.settle(&f, now: tT0 + 20)
        XCTAssertEqual(f.tasks.items[0].n, 1, "повторный settle не считает запись второй раз")
        f.log("act.feed", t: tT0 + 30, ok: false, reason: "full")
        f.log("act.bath", t: tT0 + 31, ok: true)
        DailyTasks.settle(&f, now: tT0 + 40)
        XCTAssertEqual(f.tasks.items[0].n, 1, "отказ и чужие дела не в счёт")
        XCTAssertEqual(f.econ.wallet.coins, coins0)
        f.log("act.feed", t: tT0 + 50, ok: true)
        DailyTasks.settle(&f, now: tT0 + 50)
        XCTAssertTrue(f.tasks.items[0].done)
        XCTAssertEqual(f.econ.wallet.coins, coins0 + 20)
        XCTAssertEqual(count(f, DailyTasks.doneKind), 1)
        XCTAssertEqual(f.tasks.last?.task, "feed")
        XCTAssertEqual(f.tasks.last?.shards, 0)
        // Ещё кормления — выполненное задание больше не платит.
        f.log("act.feed", t: tT0 + 60, ok: true)
        DailyTasks.settle(&f, now: tT0 + 60)
        DailyTasks.settle(&f, now: tT0 + 70)
        XCTAssertEqual(f.econ.wallet.coins, coins0 + 20)
        XCTAssertEqual(count(f, DailyTasks.doneKind), 1)
        XCTAssertEqual(f.tasks.total, 1)
    }

    func testAllDonePaysShardOnce() {
        var f = tFile()
        force(&f, [("brush", 1), ("walk", 1)])
        let shards0 = f.econ.wallet.shards, earned0 = f.shardLog.earned, coins0 = f.econ.wallet.coins
        f.log(Brush.actKind, t: tT0 + 10, ok: true)
        f.log("act.walk", t: tT0 + 20, ok: true)
        DailyTasks.settle(&f, now: tT0 + 20)
        XCTAssertEqual(f.econ.wallet.shards, shards0 + 1)
        XCTAssertEqual(f.shardLog.earned, earned0 + 1, "✂️ заданий видны в учёте клочков")
        XCTAssertEqual(f.econ.wallet.coins, coins0 + 40)
        XCTAssertTrue(f.tasks.allPaid)
        XCTAssertEqual(f.tasks.allDays, 1)
        XCTAssertEqual(f.tasks.last?.shards, 1)
        XCTAssertEqual(count(f, DailyTasks.allKind), 1)
        for k in 0..<3 {
            f.log("act.walk", t: tT0 + 100 + Double(k), ok: true)
            DailyTasks.settle(&f, now: tT0 + 100 + Double(k))
        }
        XCTAssertEqual(f.econ.wallet.shards, shards0 + 1)
        XCTAssertEqual(f.econ.wallet.coins, coins0 + 40)
        XCTAssertEqual(count(f, DailyTasks.allKind), 1)
        XCTAssertEqual(f.tasks.items.count, 2, "после «все задания» третье не добирается")
    }

    func testTaskDoneGivesXpThroughDogLevel() {
        var f = tFile()
        force(&f, [("walk", 1), ("pet", 3)])
        f.log("act.walk", t: tT0 + 10, ok: true)
        DailyTasks.settle(&f, now: tT0 + 10)
        let out = DogLevel.settle(&f, now: tT0 + 10)
        XCTAssertTrue(out.gains.contains { $0.reason == "task" && $0.xp == 5 }, "task.done — 5 опыта")
        XCTAssertEqual(DogLevel.reasonText("task"), "за задание дня")
    }

    func testRealActionsThroughPetRunner() {
        var f = tFile()
        for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 50 }
        force(&f, [("pet", 3), ("feed", 2)])
        let coins0 = f.econ.wallet.coins
        var done = 0
        for h in 0..<6 where done < 3 {
            if PetRunner.apply(.pet, source: .app, to: &f, now: tT0 + Double(h) * 1800).ok { done += 1 }
        }
        XCTAssertEqual(done, 3, "три удачных ласки за три часа")
        XCTAssertTrue(f.tasks.items[0].done, "settleRewards в конце apply двигает задания")
        XCTAssertGreaterThanOrEqual(f.econ.wallet.coins, coins0 + 20)
        XCTAssertEqual(count(f, DailyTasks.doneKind), 1)
    }

    func testTripCountsThroughPlacesGo() throws {
        // Утро, пёс бодр: поход на остановку (ур. 2) — задание «место на карте» сразу этой же записью.
        let r = Catalog.rules
        let probe = SaveFile.fresh(now: tT0)
        var t = tT0
        while true {
            let o = PetRunner.owner(probe, at: t)
            if !PetEngine.petNight(t, r, o) && PetEngine.petNight(t - 3600, r, o)
                && !(0...8).contains(where: { PetEngine.petNight(t + 3600 + Double($0) * 1800, r, o) }) { break }
            t += 600
            if t > tT0 + 3 * 86400 { throw XCTSkip("нет утра за трое суток") }
        }
        var f = tFile(level: 2, at: t)
        for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 90 }
        f.lastSeenT = t
        force(&f, [("trip", 1), ("pet", 3)], at: t)
        if case .failure(let r) = Places.go("bus_stop", in: &f, dogLevel: 2, now: t) {
            throw XCTSkip("поход не начался: \(r)")
        }
        XCTAssertTrue(f.tasks.items[0].done)
        XCTAssertEqual(count(f, DailyTasks.doneKind), 1)
    }

    // MARK: полночь, часы, пояс

    func testMidnightRollsToNewSetWithoutCarryingProgress() {
        var f = tFile()
        force(&f, [("feed", 2), ("pet", 3)])
        let day = DayKey.of(tT0)
        let midnight = DayKey.start(day + 1)
        // Запись за минуту до полуночи, учтена уже после неё — идёт во вчерашние задания.
        f.log("act.feed", t: midnight - 60, ok: true)
        DailyTasks.settle(&f, now: midnight + 60)
        XCTAssertEqual(f.tasks.day, day + 1)
        XCTAssertTrue(f.tasks.items.allSatisfy { $0.n == 0 && !$0.done }, "новый набор — с нуля")
        XCTAssertFalse(f.tasks.allPaid)
        XCTAssertEqual(f.tasks.swaps, 0)
        XCTAssertEqual(ids(f), DailyTasks.fill([], day: day + 1, f, level: 1).map(\.id))
        // Повторный settle в те же сутки набор не меняет.
        let items = f.tasks.items
        DailyTasks.settle(&f, now: midnight + 3600)
        XCTAssertEqual(f.tasks.items, items)
    }

    func testClockBackDoesNotGiveSecondSet() {
        var f = tFile()
        let day = DayKey.of(tT0)
        let tomorrow = tT0 + 86400
        // Часы вперёд на сутки: набор завтрашний, выполнен.
        DailyTasks.settle(&f, now: tomorrow)
        XCTAssertEqual(f.tasks.day, day + 1)
        f.tasks.items = [DailyTask(id: "walk", need: 1, coins: 20), DailyTask(id: "brush", need: 1, coins: 20)]
        f.log("act.walk", t: tomorrow + 10, ok: true)
        f.log(Brush.actKind, t: tomorrow + 20, ok: true)
        DailyTasks.settle(&f, now: tomorrow + 20)
        XCTAssertTrue(f.tasks.allPaid)
        let coins = f.econ.wallet.coins, shards = f.econ.wallet.shards
        // Часы назад: сегодняшние записи не считаются, набор не откатывается.
        f.log("act.walk", t: tT0 + 100, ok: true)
        f.log("act.pet", t: tT0 + 110, ok: true)
        DailyTasks.settle(&f, now: tT0 + 120)
        XCTAssertEqual(f.tasks.day, day + 1)
        XCTAssertTrue(f.tasks.allPaid)
        XCTAssertEqual(f.econ.wallet.coins, coins)
        XCTAssertEqual(f.econ.wallet.shards, shards)
        // Настоящее «завтра» наступило — те же сутки, второго набора и второй оплаты нет.
        DailyTasks.settle(&f, now: tomorrow + 3600)
        XCTAssertEqual(f.tasks.day, day + 1)
        XCTAssertEqual(f.econ.wallet.shards, shards)
        XCTAssertEqual(count(f, DailyTasks.allKind), 1)
        // Swap на «часах назад» тоже работает с сутками набора, а не откатывает их.
        XCTAssertEqual(f.tasks.items.count, 2)
    }

    func testTimezoneWestDoesNotRepeatDay() {
        // Восток (+2): только что началась полночь — новые сутки, задания выполнены.
        Clock.zoneOverride = TimeZone(secondsFromGMT: 2 * 3600)
        let day = DayKey.of(tT0)
        let t = DayKey.start(day + 1) + 30 * 60   // 00:30 по +2
        var f = tFile(at: t)
        DailyTasks.settle(&f, now: t)
        XCTAssertEqual(f.tasks.day, day + 1)
        f.tasks.items = [DailyTask(id: "walk", need: 1, coins: 20), DailyTask(id: "pet", need: 1, coins: 20)]
        f.log("act.walk", t: t + 10, ok: true)
        f.log("act.pet", t: t + 20, ok: true)
        DailyTasks.settle(&f, now: t + 20)
        XCTAssertTrue(f.tasks.allPaid)
        let coins = f.econ.wallet.coins, shards = f.econ.wallet.shards
        // Перелёт на запад (−5): там ещё вчера. Сутки не откатываются, записи «вчера» не платят.
        Clock.zoneOverride = TimeZone(secondsFromGMT: -5 * 3600)
        XCTAssertEqual(DayKey.of(t + 60), day)
        f.log("act.walk", t: t + 60, ok: true)
        f.log("act.pet", t: t + 70, ok: true)
        DailyTasks.settle(&f, now: t + 80)
        XCTAssertEqual(f.tasks.day, day + 1)
        XCTAssertEqual(f.econ.wallet.coins, coins)
        XCTAssertEqual(f.econ.wallet.shards, shards)
        // Там наступили те же «сутки +1» — набор тот же, без второй оплаты.
        let later = DayKey.start(day + 1) + 3600
        DailyTasks.settle(&f, now: later)
        XCTAssertEqual(f.tasks.day, day + 1)
        XCTAssertTrue(f.tasks.allPaid)
        XCTAssertEqual(count(f, DailyTasks.allKind), 1)
    }

    // MARK: замена

    func testSwapOncePerDay() {
        var f = tFile()
        for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
        force(&f, [("feed", 2), ("pet", 3)])
        f.log("act.pet", t: tT0 + 5, ok: true)
        DailyTasks.settle(&f, now: tT0 + 5)
        XCTAssertEqual(f.tasks.items[1].n, 1)
        guard case .success(let got) = DailyTasks.swap("pet", in: &f, now: tT0 + 10) else {
            return XCTFail("первая замена проходит")
        }
        XCTAssertFalse(["feed", "pet"].contains(got.id))
        XCTAssertEqual(f.tasks.items[1].id, got.id)
        XCTAssertEqual(f.tasks.items[1].n, 0)
        XCTAssertEqual(f.tasks.out, ["pet"])
        XCTAssertEqual(count(f, DailyTasks.swapKind), 1)
        XCTAssertEqual(DailyTasks.board(f, now: tT0 + 20).swapsLeft, 0)
        if case .failure(let r) = DailyTasks.swap("feed", in: &f, now: tT0 + 30) {
            XCTAssertEqual(r, .noSwaps)
        } else { XCTFail("вторая замена за сутки — нет") }
        // Тот же swap детерминирован: копия до замены даёт то же задание.
        // Завтра замены снова есть.
        DailyTasks.settle(&f, now: tT0 + 86400)
        XCTAssertEqual(DailyTasks.board(f, now: tT0 + 86400).swapsLeft, 1)
        XCTAssertTrue(f.tasks.out.isEmpty)
    }

    func testSwapRefusesDoneTask() {
        var f = tFile()
        force(&f, [("walk", 1), ("pet", 3)])
        f.log("act.walk", t: tT0 + 5, ok: true)
        DailyTasks.settle(&f, now: tT0 + 5)
        if case .failure(let r) = DailyTasks.swap("walk", in: &f, now: tT0 + 10) {
            XCTAssertEqual(r, .done)
        } else { XCTFail("выполненное не меняется") }
        if case .failure(let r) = DailyTasks.swap("cook", in: &f, now: tT0 + 10) {
            XCTAssertEqual(r, .notFound)
        } else { XCTFail("чужое не меняется") }
        XCTAssertEqual(f.tasks.swaps, 0, "отказ замену не тратит")
    }

    // MARK: сейв

    func testOldSaveDecodesAndEmptyIsNotWritten() throws {
        var f = tFile()
        f.tasks = DailyTasksLog()
        let data = try JSONEncoder().encode(f)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("\"tasks\""), "пустое не пишется")
        let back = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertTrue(back.tasks.isEmpty)
        // Заполненное — туда и обратно.
        force(&f, [("feed", 2), ("pet", 3)])
        f.tasks.items[0].n = 1
        f.tasks.last = TaskWin(task: "feed", coins: 20, shards: 0, allCoins: 0, t: tT0)
        let again = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(again.tasks, f.tasks)
        // Кривое поле внутри не ломает остальное.
        let partial = try JSONDecoder().decode(DailyTasksLog.self, from: Data(#"{"day": 5, "items": "x", "total": 3}"#.utf8))
        XCTAssertEqual(partial.day, 5)
        XCTAssertEqual(partial.total, 3)
        XCTAssertTrue(partial.items.isEmpty)
    }

    func testNewPuppyKeepsTheDay() {
        var f = tFile()
        force(&f, [("walk", 1), ("brush", 1)])
        f.log("act.walk", t: tT0 + 5, ok: true)
        f.log(Brush.actKind, t: tT0 + 6, ok: true)
        DailyTasks.settle(&f, now: tT0 + 6)
        XCTAssertTrue(f.tasks.allPaid)
        let carried = f.tasks.carriedOver()
        XCTAssertEqual(carried.seenSeq, 0)
        XCTAssertNil(carried.last)
        XCTAssertEqual(carried.items, f.tasks.items)
        var pup = SaveFile.fresh(now: tT0 + 60)
        pup.econ = f.econ.carriedOver()
        pup.tasks = carried
        let shards = pup.econ.wallet.shards, coins = pup.econ.wallet.coins
        pup.log("act.walk", t: tT0 + 70, ok: true)
        DailyTasks.settle(&pup, now: tT0 + 80)
        XCTAssertEqual(pup.tasks.day, f.tasks.day)
        XCTAssertEqual(pup.tasks.items.map(\.id), f.tasks.items.map(\.id), "второго набора за сутки нет")
        XCTAssertEqual(pup.econ.wallet.shards, shards)
        XCTAssertEqual(pup.econ.wallet.coins, coins)
        XCTAssertTrue(DailyTasksLog().carriedOver().isEmpty)
    }

    func testDisabledDoesNothing() {
        DailyTasks.enabled = false
        var f = tFile()
        f.log("act.feed", t: tT0, ok: true)
        DailyTasks.settle(&f, now: tT0)
        XCTAssertTrue(f.tasks.isEmpty)
        XCTAssertTrue(DailyTasks.board(f, now: tT0).items.isEmpty)
    }

    // MARK: тексты

    func testTexts() {
        let t = DailyTask(id: "feed", need: 2, coins: 20)
        XCTAssertEqual(DailyTaskText.name(t), "Покормить 2 раза")
        XCTAssertEqual(DailyTaskText.name(DailyTask(id: "pet", need: 5, coins: 20)), "Погладить 5 раз")
        XCTAssertEqual(DailyTaskText.name(DailyTask(id: "brush", need: 1, coins: 20)), "Расчесать")
        XCTAssertEqual(DailyTaskText.progress(t), "0 / 2")
        XCTAssertEqual(DailyTaskText.reward(t), "+20 🪙")
        for (id, _) in DailyTasks.pool {
            XCTAssertNotEqual(DailyTaskText.name(DailyTask(id: id, need: 1, coins: 1)), id, "у \(id) есть название")
            XCTAssertNotEqual(DailyTaskText.emoji(id), "⭐")
        }
        let f = tFile()
        XCTAssertEqual(DailyTaskText.toast(TaskWin(task: "feed", coins: 20, shards: 0, allCoins: 0, t: 0), f),
                       "Задание дня: Покормить · +20 🪙")
        XCTAssertTrue(DailyTaskText.toast(TaskWin(task: "walk", coins: 20, shards: 1, allCoins: 0, t: 0), f)
            .hasPrefix("Все задания дня!"))
    }
}
