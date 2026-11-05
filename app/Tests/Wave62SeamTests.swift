// Волна 62: охота на баги стыков волн 49–59. Каждый тест — найденный баг: сначала падал, потом починен.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let w62T0: Double = 1_760_054_400   // 2025-10-10 00:00 UTC
private let w62H: Double = 3600

final class Wave62SeamTests: XCTestCase {

    // MARK: «Пока тебя не было» × задания дня × пёс занят

    /// Свежий щенок за 10 минут до now, задания дня — «Поиграть», «Гулять», «Расчесать», просьб пса в этот час нет.
    private func taskSave(now: Double) -> SaveFile {
        var f = SaveFile.fresh(now: now - 600)
        f.owner.tzOffsetMin = 0
        f.asks = DogAsksLog()
        if let id = (0..<64).map({ "w62-away-\($0)" }).first(where: { id in
            var g = f
            g.petId = id
            return DogAsks.shown(g, now: now) == nil
        }) { f.petId = id }
        var t = f.tasks
        t.started = true
        t.day = DayKey.of(now)
        t.items = [DailyTask(id: "play", need: 2, coins: 3), DailyTask(id: "walk", need: 1, coins: 3),
                   DailyTask(id: "brush", need: 1, coins: 3)]
        f.tasks = t
        return f
    }

    private func checkHintDoable(_ f: SaveFile, now: Double, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let h = AwayBuilder.hint(f, now: now), let a = h.action else { return }
        XCTAssertTrue(AwayBuilder.accepts(f, a, now: now),
                      "\(what): подсказка «\(h.button)» (\(h.kind)) — ядро откажет, хозяин увидит тост отказа",
                      file: file, line: line)
    }

    /// Было: пёс гуляет / в походе — в отчёте «Задание дня · Поиграть», кнопка давала тост «пёс не дома».
    func testAwayTaskHintSkipsWhenDogIsOut() {
        let now = w62T0 + 12 * w62H
        var f = taskSave(now: now)
        f.pet.outing = Outing(from: now - 600, until: now + 2 * w62H, find: "")
        XCTAssertFalse(AwayBuilder.accepts(f, .play, now: now), "предусловие: на прогулке «Поиграть» ядро не примет")
        checkHintDoable(f, now: now, "прогулка")
        XCTAssertNotEqual(AwayBuilder.hint(f, now: now)?.kind, "task", "задание, которое сейчас не выполнить, — не подсказка")
    }

    /// Было: пёс дремлет — «Поиграть» / «Гулять» / «Расчесать» из отчёта получали «спит».
    func testAwayTaskHintSkipsWhenDogNaps() {
        let now = w62T0 + 12 * w62H
        var f = taskSave(now: now)
        f.pet.napUntil = now + w62H
        XCTAssertFalse(AwayBuilder.accepts(f, .play, now: now), "предусловие: в дрёме «Поиграть» ядро не примет")
        checkHintDoable(f, now: now, "дрёма")
    }

    /// Было: вернулся в 2 ночи — «Задание дня · Поиграть», а пёс спит ночью.
    func testAwayTaskHintSkipsAtNight() {
        let now = w62T0 + 26 * w62H   // 02:00 UTC, пояс 0
        let f = taskSave(now: now)
        XCTAssertFalse(AwayBuilder.accepts(f, .play, now: now), "предусловие: ночью «Поиграть» ядро не примет")
        checkHintDoable(f, now: now, "ночь")
    }

    /// Моется: подсказка, если есть, исполнима.
    func testAwayTaskHintDuringBathIsDoable() {
        let now = w62T0 + 12 * w62H
        var f = taskSave(now: now)
        f.pet.bathUntil = now + 10 * 60
        checkHintDoable(f, now: now, "мытьё")
    }

    /// Не сломали: днём, пёс свободен — задание дня по-прежнему подсказка.
    func testAwayTaskHintStillShownWhenDogIsFree() throws {
        let now = w62T0 + 12 * w62H
        let f = taskSave(now: now)
        XCTAssertTrue(AwayBuilder.accepts(f, .play, now: now), "предусловие: свободный пёс днём играет")
        let h = try XCTUnwrap(AwayBuilder.hint(f, now: now))
        XCTAssertEqual(h.kind, "task")
        XCTAssertEqual(h.action, .play)
    }

    // MARK: Siri «Шиба, сидеть» × открытый лист / раннер

    /// Было: команда голосом при открытом раннере, дворе или листе шла за ним — трюка не видно.
    /// Теперь сначала всё закрывается (как pet://home), трюк — через DeepLink.closeDelay.
    func testVoiceTrickClosesSheetsFirst() {
        XCTAssertFalse(Tricks.voiceClosesFirst(open: []))
        XCTAssertFalse(Tricks.voiceClosesFirst(open: ["tricks"]), "лист «Команды» — свой, трюк виден за ним")
        XCTAssertTrue(Tricks.voiceClosesFirst(open: ["runner"]))
        XCTAssertTrue(Tricks.voiceClosesFirst(open: ["yard", "tricks"]))
        XCTAssertTrue(Tricks.voiceClosesFirst(open: ["postcard"]))
        XCTAssertEqual(Tricks.voiceCloseDelayMs(open: []), 0)
        XCTAssertEqual(Tricks.voiceCloseDelayMs(open: ["tricks"]), 0)
        XCTAssertEqual(Tricks.voiceCloseDelayMs(open: ["runner"]), Int(DeepLink.closeDelay * 1000))
    }

    /// Было: давно не заходил, «Шиба, сидеть» открывает приложение — сверху сразу «Пока тебя не было»
    /// (fullScreenCover), а через 0,9 с пёс садился под ним: трюк, сердечки и тост не видны.
    func testVoiceTrickClosesAwayReportFirst() {
        XCTAssertTrue(Tricks.voiceClosesFirst(open: [], away: true))
        XCTAssertTrue(Tricks.voiceClosesFirst(open: ["tricks"], away: true))
        XCTAssertFalse(Tricks.voiceClosesFirst(open: ["tricks"], away: false))
        XCTAssertEqual(Tricks.voiceCloseDelayMs(open: [], away: true), Int(DeepLink.closeDelay * 1000))
    }

    // MARK: свой персонаж в комнате × двор / фургон / раннер

    /// Было: свой персонаж в комнате (у него «Head» → своё имя) — двор, фургон и раннер грузят Шибу или Хаски,
    /// а глаза им не пришивали (или искали голову по чужому псевдониму) — глаза ехали с ушами.
    func testBoxModelEyesIgnoreRoomCharacterAliases() {
        let names = ["Body/Root/Spine/Neck3/Head", "Body/Root/Spine/Neck3/Head/Ear1_L", "Body/Root/Spine/Neck3/Head/Jaw"]
        let roomAlias = ["Head": "char_head", "Neck3": "char_neck"]
        XCTAssertNil(BoneName.index(names, "Head", alias: roomAlias), "механизм бага: псевдоним персонажа в Шибе не находится")
        for b in PetBreed.allCases {
            XCTAssertTrue(b.boneAlias.isEmpty, "\(b): у модели из коробки кости под нашими именами")
            XCTAssertEqual(BoneName.index(names, "Head", alias: b.boneAlias), 0, "\(b): голова находится всегда")
        }
        XCTAssertEqual(BoneName.index(["X/char_head"], "Head", alias: roomAlias), 0, "в самом персонаже — по псевдониму")
    }
}
