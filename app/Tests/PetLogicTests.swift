// Логика без экрана: реакция на действие, главная кнопка, «Пока тебя не было», план уведомлений,
// реплики, файл сохранения, догон времени и стор. Стор — только во временной папке (StoreHooks),
// настоящую группу не трогаем; зеркало Documents, которое стор пишет попутно, StoreHooks возвращает как было.
// wipe() не зовём: он стирает зеркало приложения.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Фиксированный момент: тесты не зависят от того, когда их запустили.
private let t0: Double = 1_760_000_000

private func freshFile(at t: Double = t0) -> SaveFile {
    SaveFile.fresh(now: t)
}

private func lastAction(_ kind: String, at t: Double, ok: Bool = true) -> SaveFile.LastAction {
    SaveFile.LastAction(kind: kind, source: .app, t: t, ok: ok, reason: ok ? nil : "cooldown")
}

/// Местный день как в ядре (Insights.localDay).
private func localDay(_ t: Double, _ o: Owner) -> Int {
    let m = Int((t / 60).rounded(.down)) + o.tzOffsetMin
    return Int((Double(m) / 1440).rounded(.down))
}

private func encodeFile(_ f: SaveFile) throws -> Data {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    return try enc.encode(f)
}

private func decodeFile(_ data: Data) throws -> SaveFile {
    try JSONDecoder().decode(SaveFile.self, from: data)
}

final class PetLogicTests: XCTestCase {

    // MARK: Presenter: реакция держится 90 секунд

    func testReactionWindowIs90Seconds() {
        XCTAssertEqual(Presenter.reactionWindow, 90)
    }

    func testReactionHoldsPoseInsideWindow() {
        var f = freshFile()
        f.lastAction = lastAction("pet", at: t0 - 60)
        XCTAssertEqual(Presenter.make(f, at: t0).pose, .loved, "через 60 с после «погладить» — поза от реакции")

        f.lastAction = lastAction("feed", at: t0 - 30)
        XCTAssertEqual(Presenter.make(f, at: t0).pose, .eating)

        f.lastAction = lastAction("play", at: t0 - 89)
        XCTAssertEqual(Presenter.make(f, at: t0).pose, .happy)
    }

    func testReactionGoneAfterWindow() {
        var f = freshFile()
        f.lastAction = lastAction("pet", at: t0 - 120)
        XCTAssertNotEqual(Presenter.make(f, at: t0).pose, .loved, "через 120 с реакции уже нет")

        f.lastAction = lastAction("feed", at: t0 - 90)
        XCTAssertNotEqual(Presenter.make(f, at: t0).pose, .eating, "ровно 90 с — окно закрыто")

        // Действие «из будущего» (часы назад) реакцию тоже не даёт.
        f.lastAction = lastAction("feed", at: t0 + 30)
        XCTAssertNotEqual(Presenter.make(f, at: t0).pose, .eating)
    }

    func testFailedActionHasNoReaction() {
        var f = freshFile()
        f.lastAction = lastAction("feed", at: t0 - 10, ok: false)
        XCTAssertNotEqual(Presenter.make(f, at: t0).pose, .eating, "отказ ядра — не повод жевать")
    }

    func testDeadPetOpensAppAndIgnoresReaction() {
        var f = freshFile()
        f.pet.alive = false
        f.pet.diedAt = t0 - 3600
        f.pet.cause = .starve
        f.lastAction = lastAction("pet", at: t0 - 10)
        let snap = Presenter.make(f, at: t0)
        XCTAssertFalse(snap.alive)
        XCTAssertEqual(snap.main, .open)
        XCTAssertEqual(snap.pose, .dead)
        XCTAssertNil(snap.main.action)
    }

    func testNapMakesMainWake() {
        var f = freshFile()
        f.pet.napUntil = t0 + 40 * 60
        let snap = Presenter.make(f, at: t0)
        XCTAssertEqual(snap.main, .wake)
        XCTAssertEqual(snap.main.action, .wake)
    }

    // MARK: MainAct из строки ядра

    func testMainActRawValues() {
        for m in MainAct.allCases {
            XCTAssertEqual(MainAct(rawValue: m.rawValue), m)
            XCTAssertFalse(m.title.isEmpty)
            XCTAssertFalse(m.icon.isEmpty)
        }
        XCTAssertNil(MainAct(rawValue: "мусор"))
        XCTAssertNil(MainAct(rawValue: ""))
        XCTAssertNil(MainAct(rawValue: "food"), "ключ ядра food переводится в feed руками, а не через rawValue")
        // Как в Presenter: неизвестный ключ спасения — «погладить».
        let garbage = "мусор"
        let fallback: MainAct = MainAct(rawValue: garbage == "food" ? "feed" : garbage) ?? MainAct.pet
        XCTAssertEqual(fallback, MainAct.pet)
        XCTAssertEqual(MainAct.feed.action, .feed(Catalog.mainFood))
        XCTAssertEqual(MainAct.heal.action, .item(Catalog.healItem))
        XCTAssertNil(MainAct.none.action)
    }

    // MARK: AwayBuilder

    // AwayBuilder живёт в App/AwayReport.swift, в Linux-сборку логики (app/Package.swift) он не входит.
    #if !SWIFT_PACKAGE
    func testAwayShortAbsenceHasNoReport() {
        let f = freshFile()
        XCTAssertNil(AwayBuilder.make(f, prev: f.pet, now: t0 + 10 * 60), "10 минут — не повод для ленты")
        XCTAssertNil(AwayBuilder.make(f, prev: f.pet, now: t0), "ноль времени — тоже")
        XCTAssertNil(AwayBuilder.make(f, prev: f.pet, now: t0 - 3600), "часы назад — тоже")
    }

    func testAwayLongAbsenceHasReport() throws {
        let f = freshFile()
        let r = try XCTUnwrap(AwayBuilder.make(f, prev: f.pet, now: t0 + 6 * 3600), "6 часов — лента есть")
        XCTAssertFalse(r.died)
        XCTAssertEqual(r.subtitle, "Тебя не было 6 ч")
        XCTAssertLessThanOrEqual(r.cards.count, AwayBuilder.maxMiddle)
        XCTAssertFalse(r.greet.isEmpty)
        XCTAssertFalse(r.cta.isEmpty)
        XCTAssertEqual(Set(r.cards.map(\.id)).count, r.cards.count, "карточки не повторяются")
    }

    func testAwaySubtitleAndTimes() {
        XCTAssertEqual(AwayBuilder.subtitle(0.25), "Тебя не было 15 мин")
        XCTAssertEqual(AwayBuilder.subtitle(6), "Тебя не было 6 ч")
        XCTAssertEqual(AwayBuilder.subtitle(72), "Тебя не было 3 дн")
        let cases: [(Int, String)] = [(1, "раз"), (2, "раза"), (4, "раза"), (5, "раз"), (11, "раз"),
                                      (12, "раз"), (14, "раз"), (21, "раз"), (22, "раза"), (104, "раза"), (111, "раз")]
        for (n, want) in cases {
            XCTAssertEqual(AwayBuilder.times(n), want, "\(n)")
        }
    }
    #endif

    // MARK: NotificationPlanner

    func testNotificationsAtMostOnePerLocalDay() {
        var snapshots: [(String, SaveFile)] = []
        snapshots.append(("свежий", freshFile()))

        var low = freshFile()
        for n in [Need.food, .clean, .fun, .love] { low.pet.needs[n] = 35 }
        snapshots.append(("низкие шкалы", low))

        var away = freshFile()
        away.lastSeenT = t0 - 2 * 86400
        snapshots.append(("не открывали 2 дня", away))

        var critical = freshFile()
        critical.pet.hearts = 2
        for n in [Need.food, .clean, .energy, .fun, .love] { critical.pet.needs[n] = 10 }
        snapshots.append(("критично", critical))

        var build = freshFile()
        build.build = SaveFile.BuildInfo(expiresT: t0 + 3 * 86400, seenT: t0)
        snapshots.append(("подпись кончается", build))

        for (name, f) in snapshots {
            let plan = NotificationPlanner.plan(f, now: t0)
            XCTAssertLessThanOrEqual(plan.count, NotificationPlanner.maxNotes, name)
            XCTAssertEqual(Set(plan.map(\.id)).count, plan.count, "\(name): id повторяются")
            XCTAssertEqual(plan.map(\.date), plan.map(\.date).sorted(), "\(name): план не по времени")
            let o = PetRunner.owner(f, at: t0)
            var perDay: [Int: Int] = [:]
            for n in plan {
                XCTAssertGreaterThan(n.date.timeIntervalSince1970, t0, "\(name): уведомление в прошлом")
                XCTAssertLessThanOrEqual(n.title.count, LineLimit.notifTitle, "\(name): \(n.title)")
                XCTAssertFalse(n.body.isEmpty, name)
                // Напоминания о подписи идут отдельно от заботы о питомце.
                guard n.category != "pet.build" else { continue }
                perDay[localDay(n.date.timeIntervalSince1970, o), default: 0] += 1
            }
            for (day, c) in perDay {
                XCTAssertLessThanOrEqual(c, 1, "\(name): \(c) уведомлений в местный день \(day)")
            }
        }
    }

    func testNotificationsSkipDayOfLastSent() {
        var f = freshFile()
        for n in [Need.food, .clean, .fun, .love] { f.pet.needs[n] = 30 }
        f.notif.lastSentT = t0
        let o = PetRunner.owner(f, at: t0)
        let today = localDay(t0, o)
        let plan = NotificationPlanner.plan(f, now: t0).filter { $0.category != "pet.build" }
        for n in plan {
            XCTAssertNotEqual(localDay(n.date.timeIntervalSince1970, o), today, "сегодня уже было: \(n.trigger)")
        }
    }

    func testBuildNotesBeforeExpiry() {
        var f = freshFile()
        f.build = SaveFile.BuildInfo(expiresT: t0 + 3 * 86400, seenT: t0)
        let notes = NotificationPlanner.buildNotes(f, now: t0)
        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes.allSatisfy { $0.category == "pet.build" })
        // Через сутки с небольшим напоминание «за 48 ч» уже в прошлом, «за 24 ч» ещё впереди.
        let late = NotificationPlanner.buildNotes(f, now: t0 + 86400 + 3600)
        XCTAssertEqual(late.count, 1)
        f.build = nil
        XCTAssertTrue(NotificationPlanner.buildNotes(f, now: t0).isEmpty)
    }

    // MARK: Lines

    func testLinesWithinLimits() throws {
        let lines = Lines.shared
        guard lines.sections.values.contains(where: { !$0.isEmpty }) else {
            throw XCTSkip("lines.json нет в бандле")
        }
        let limits: [(String, Int)] = [("widget", LineLimit.widget), ("island", LineLimit.island), ("away", LineLimit.away)]
        for (section, max) in limits {
            let byKey = lines.sections[section] ?? [:]
            XCTAssertFalse(byKey.isEmpty, "раздел \(section) пуст")
            for (key, items) in byKey {
                for it in items {
                    XCTAssertLessThanOrEqual(it.text.count, max, "\(section).\(key) \(it.id): «\(it.text)»")
                }
            }
        }
        for (key, items) in lines.sections["notifications"] ?? [:] {
            for it in items {
                XCTAssertLessThanOrEqual(it.title?.count ?? 0, LineLimit.notifTitle, "notifications.\(key) \(it.id)")
                XCTAssertLessThanOrEqual(it.text.count, LineLimit.notifBody, "notifications.\(key) \(it.id)")
            }
        }
        for (key, th) in lines.thoughts {
            XCTAssertLessThanOrEqual(th.text.count, LineLimit.thought, "thoughts.\(key)")
        }
        // Обёртки всегда укладываются в лимит, даже с запасным текстом.
        for slot in 0..<48 {
            XCTAssertLessThanOrEqual(lines.widget(["ok"], seed: "pet", slot: slot).count, LineLimit.widget)
            XCTAssertLessThanOrEqual(lines.island(["ok"], seed: "pet", slot: slot).count, LineLimit.island)
        }
    }

    func testLinesPickIsStableAndFillsPlaceholders() {
        let lines = Lines.shared
        for slot in 0..<10 {
            XCTAssertEqual(lines.widget(["ok"], seed: "a", slot: slot), lines.widget(["ok"], seed: "a", slot: slot))
        }
        XCTAssertEqual(Lines.placeholders("Съел {item} и ещё {count}"), ["item", "count"])
        XCTAssertEqual(Lines.placeholders("без подстановок"), [])
        XCTAssertEqual(Lines.placeholders("сломано {item"), [])
        XCTAssertEqual(Lines.fill("Съел {item}", ["item": "хрустики"]), "Съел хрустики")
        XCTAssertEqual(Lines.fill("Съел {item}", [:]), "Съел {item}")
        XCTAssertNil(Lines.empty.pick("widget", "ok", seed: "a", slot: 0))
        XCTAssertEqual(Lines.empty.widget(["ok"], seed: "a", slot: 0), "Я тут")
        XCTAssertNil(Lines.empty.away("welcome", seed: "a", slot: 0))
    }

    // MARK: SaveFile

    func testSaveFileRoundTrip() throws {
        var f = freshFile()
        f.rev = 7
        f.debugMarker = 42
        f.lastAction = lastAction("feed", at: t0 - 5)
        f.build = SaveFile.BuildInfo(expiresT: t0 + 86400 * 6, seenT: t0)
        f.notif.lastSentT = t0 - 100
        f.log("act.feed", t: t0 - 5, source: .widget, ok: true, key: Catalog.mainFood)

        let d1 = try decodeFile(encodeFile(f))
        XCTAssertEqual(d1.petId, f.petId)
        XCTAssertEqual(d1.deviceId, f.deviceId)
        XCTAssertEqual(d1.rev, 7)
        XCTAssertEqual(d1.seq, f.seq)
        XCTAssertEqual(d1.createdT, f.createdT)
        XCTAssertEqual(d1.owner, f.owner)
        XCTAssertEqual(d1.pet.t, f.pet.t)
        XCTAssertEqual(d1.pet.hearts, f.pet.hearts)
        for n in Need.allCases { XCTAssertEqual(d1.pet.needs[n], f.pet.needs[n], "\(n)") }
        XCTAssertEqual(d1.lastAction, f.lastAction)
        XCTAssertEqual(d1.build, f.build)
        XCTAssertEqual(d1.notif, f.notif)
        XCTAssertEqual(d1.journal, f.journal)
        XCTAssertEqual(d1.debugMarker, 42)

        // Второй круг байт в байт: формат устойчив.
        let e2 = try encodeFile(d1)
        let e3 = try encodeFile(decodeFile(e2))
        XCTAssertEqual(e2, e3)
    }

    func testSaveFileSurvivesBrokenSubobjects() throws {
        let f = freshFile()
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: encodeFile(f)) as? [String: Any])
        obj["journal"] = "мусор"
        obj["outbox"] = 5
        obj["build"] = ["expiresT": "завтра"]
        obj["notif"] = ["scheduled": "никогда"]
        obj["lastAction"] = [1, 2, 3]
        obj["flags"] = NSNull()
        obj["island"] = "вкл"
        let data = try JSONSerialization.data(withJSONObject: obj)

        let d = try decodeFile(data)
        XCTAssertEqual(d.petId, f.petId, "питомец пережил битые подобъекты")
        XCTAssertEqual(d.pet.hearts, f.pet.hearts)
        XCTAssertTrue(d.journal.isEmpty)
        XCTAssertTrue(d.outbox.isEmpty)
        XCTAssertNil(d.build)
        XCTAssertNil(d.lastAction)
        XCTAssertNil(d.notif.lastSentT)
        XCTAssertTrue(d.notif.scheduled.isEmpty)
        XCTAssertTrue(d.island.enabled)
    }

    func testSaveFileWithoutPetFails() throws {
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: encodeFile(freshFile())) as? [String: Any])
        obj.removeValue(forKey: "pet")
        let data = try JSONSerialization.data(withJSONObject: obj)
        XCTAssertThrowsError(try decodeFile(data), "без питомца файл — ошибка, а не новый щенок")
    }

    // MARK: прогулка с находкой

    func testSaveFileKeepsOutingAndFinds() throws {
        var f = freshFile()
        f.pet.outing = Outing(from: t0, until: t0 + 90 * 60, find: "stick")
        f.pet.finds = ["cone": 2, "stick": 1]
        let d = try decodeFile(encodeFile(f))
        XCTAssertEqual(d.pet.outing, f.pet.outing)
        XCTAssertEqual(d.pet.finds, f.pet.finds)
    }

    func testOldSaveWithoutWalkFieldsDecodes() throws {
        let f = freshFile()
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: encodeFile(f)) as? [String: Any])
        var pet = try XCTUnwrap(obj["pet"] as? [String: Any])
        pet.removeValue(forKey: "outing")
        pet.removeValue(forKey: "finds")
        obj["pet"] = pet
        let d = try decodeFile(JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(d.pet.outing, "старое сохранение — питомец дома")
        XCTAssertTrue(d.pet.finds.isEmpty)
        XCTAssertEqual(d.pet.hearts, f.pet.hearts)
    }

    func testWalkingSnapshotShowsTimerAndOpensApp() {
        var f = freshFile()
        f.pet.outing = Outing(from: t0 - 600, until: t0 + 50 * 60, find: "ball")
        let snap = Presenter.make(f, at: t0)
        XCTAssertEqual(snap.mood, "walking")
        XCTAssertEqual(snap.pose, .away, "Шибы дома нет — сцена и виджет показывают прогулку")
        XCTAssertEqual(snap.main, .open)
        XCTAssertNil(snap.want)
        XCTAssertEqual(snap.timer, NeedTimer(kind: "walk", start: t0 - 600, end: t0 + 50 * 60, title: "Гуляет"))
        XCTAssertEqual(Presenter.timerTitle(kind: "walk", need: nil), "Гуляет")
        XCTAssertEqual(Presenter.timerPhrase(kind: "walk", title: "Гуляет", remaining: 50 * 60), "Гуляет ещё 50 мин")
        let back = ForecastTools.upcoming(f.pet, at: t0).first { $0.kind == .back_home }
        XCTAssertEqual(back?.t, t0 + 50 * 60, "возвращение есть в прогнозе")
        XCTAssertEqual(back?.key, "ball")
        XCTAssertEqual(back.map { ForecastTools.title($0) }, "Вернётся")
        let stale = ForecastTools.staleDate(f.pet, events: [], now: t0, startedT: nil)
        XCTAssertEqual(stale.timeIntervalSince1970, t0 + 50 * 60)
    }

    func testWalkActionRoundTrip() {
        XCTAssertEqual(PetAction(.walk), .walk)
        XCTAssertEqual(PetAction.walk.core, .walk)
        XCTAssertEqual(PetAction.walk.kind, "walk")
        XCTAssertEqual(PetAction(kind: "walk", key: nil, value: nil), .walk)
        XCTAssertNotEqual(RefuseText.text("away"), RefuseText.text(nil))
        XCTAssertNotEqual(RefuseText.text("too_late"), RefuseText.text(nil))
        XCTAssertNotEqual(RefuseText.text("not_ready"), RefuseText.text(nil))
    }

    func testJournalTrimmedTo200() {
        var f = freshFile()
        for i in 0..<250 { f.log("act.pet", t: t0 + Double(i), source: .app, ok: true) }
        XCTAssertEqual(SaveFile.journalMax, 200)
        XCTAssertEqual(f.journal.count, 200)
        XCTAssertEqual(f.seq, 250)
        XCTAssertEqual(f.journal.first?.id, "\(f.deviceId):51", "старые записи уходят с начала")
        XCTAssertEqual(f.journal.last?.id, "\(f.deviceId):250")
        XCTAssertEqual(f.outbox.count, 250, "outbox длиннее журнала")
    }

    // MARK: Догон времени

    func testCatchUpWithClockBack() {
        var f = freshFile()
        let pet = f.pet
        PetRunner.catchUp(&f, now: t0 - 3600)
        XCTAssertEqual(f.pet, pet, "часы назад — питомец не меняется")
        XCTAssertEqual(f.journal.last?.kind, "clock_back")
        XCTAssertEqual(f.journal.last?.value, 3600)

        PetRunner.catchUp(&f, now: t0 - 3500)
        XCTAssertEqual(f.journal.filter { $0.kind == "clock_back" }.count, 1, "clock_back не дублируется подряд")

        // Меньше 5 минут назад — дрожь часов, не событие.
        var g = freshFile()
        PetRunner.catchUp(&g, now: t0 - 120)
        XCTAssertFalse(g.journal.contains { $0.kind == "clock_back" })
    }

    func testCatchUpForward() {
        var f = freshFile()
        let food0 = f.pet.needs[.food] ?? 0
        let now = t0 + 6 * 3600
        PetRunner.catchUp(&f, now: now)
        XCTAssertLessThanOrEqual(abs(f.pet.t - now), 60, "питомец догнан до now")
        XCTAssertLessThan(f.pet.needs[.food] ?? 0, food0, "за 6 часов еда убывает")
        XCTAssertTrue(f.pet.alive)
    }

    func testCatchUpKeepsDeadPetDead() {
        var f = freshFile()
        f.pet.alive = false
        f.pet.diedAt = t0
        f.pet.cause = .toska
        PetRunner.catchUp(&f, now: t0 + 86400)
        XCTAssertFalse(f.pet.alive)
        XCTAssertEqual(f.pet.diedAt, t0)
        XCTAssertEqual(f.pet.t, t0, "мёртвого не догоняем")
    }

    // MARK: PetStore во временной папке

    func testStoreRecoversFromPrev() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-logic")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        // startOver пишет свежего щенка с rev 0, не заглядывая в зеркало приложения.
        try store.startOver(now: t0)
        for _ in 0..<10 { try store.mutate { (f: inout SaveFile) -> Void in f.seq += 0 } }
        let good = try XCTUnwrap(store.read())
        XCTAssertEqual(good.rev, 10)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.prevURL.path), "на rev 10 есть state.prev.json")

        try Data("{ это не json".utf8).write(to: store.stateURL)
        try FileManager.default.removeItem(at: store.bakURL)
        let back = try XCTUnwrap(store.read(), "испорченный файл, bak нет — восстановление из prev")
        XCTAssertEqual(back.petId, good.petId)
        XCTAssertEqual(back.rev, 10)
        // Откладывает испорченный файл писатель, а не читатель.
        try store.mutate { (f: inout SaveFile) -> Void in f.seq += 0 }
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("state.broken-") }, "испорченный файл отложен: \(names)")
        XCTAssertEqual(try XCTUnwrap(store.read()).rev, 11)
    }

    func testStoreStartOver() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-logic")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: t0)
        let first = try XCTUnwrap(store.read())
        try store.startOver(now: t0 + 100)
        let second = try XCTUnwrap(store.read())
        XCTAssertNotEqual(first.petId, second.petId, "новый щенок")
        XCTAssertEqual(second.createdT, t0 + 100)
        let broken = dir.appendingPathComponent("state.broken-\(Int(t0 + 100)).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: broken.path), "старый файл не стёрт, а отложен")
    }

    func testRepeatedRefusalLoggedOnce() {
        var f = SaveFile.fresh(now: t0)
        let first = PetRunner.apply(.wake, source: .app, to: &f, now: t0 + 120)
        XCTAssertFalse(first.ok)
        let n = f.journal.count
        for i in 1...30 {
            let out = PetRunner.apply(.wake, source: .app, to: &f, now: t0 + 120 + Double(i) * 5)
            XCTAssertEqual(out, first, "отказ по-прежнему возвращается")
        }
        XCTAssertEqual(f.journal.count, n, "30 одинаковых отказов подряд — одна запись")
        XCTAssertEqual(f.lastAction?.ok, false)
        _ = PetRunner.apply(.wake, source: .app, to: &f, now: t0 + 120 + PetRunner.refusalGap + 60)
        XCTAssertEqual(f.journal.count, n + 1, "через 10 минут тот же отказ пишется снова")
        _ = PetRunner.apply(.pet, source: .app, to: &f, now: t0 + 120 + PetRunner.refusalGap + 70)
        XCTAssertEqual(f.journal.last?.kind, "act.pet", "другое действие пишется сразу")
    }

    func testPerformWritesJournalAndLastAction() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-logic")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: t0)
        let now = t0 + 2 * 3600
        let out = try PetRunner.perform(.pet, source: .widget, store: store, now: now)
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.rev, 1)
        XCTAssertEqual(f.journal.last?.kind, "act.pet")
        XCTAssertEqual(f.journal.last?.source, .widget)
        XCTAssertEqual(f.journal.last?.ok, out.ok)
        XCTAssertEqual(f.lastAction?.kind, "pet")
        XCTAssertEqual(f.lastAction?.source, .widget)
        XCTAssertEqual(f.lastAction?.t, now)
    }

    func testStoreHooksUseTempStore() throws {
        let marker = 123.5
        let r = try XCTUnwrap(StoreHooks.writeThenRead(marker: marker))
        XCTAssertEqual(r.written, marker)
        XCTAssertEqual(r.read, marker, "второй экземпляр стора над той же папкой видит запись первого")
    }
}
