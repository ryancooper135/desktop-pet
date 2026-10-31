// Волна 53: логика нового главного экрана — награды под кнопками, награда из тоста, карточка «Задание дня», числа.

import XCTest
@preconcurrency import PetCore
@testable import Pet

final class HomeLookTests: XCTestCase {

    func testActRewardsNameTheNeed() {
        XCTAssertEqual(HomeLook.actNeed("feed"), .food)
        XCTAssertEqual(HomeLook.actNeed("pet"), .love)
        XCTAssertEqual(HomeLook.actNeed("play"), .fun)
        XCTAssertEqual(HomeLook.actNeed("bath"), .clean)
        XCTAssertNil(HomeLook.actNeed("wake"))
        XCTAssertNil(HomeLook.actReward("bed"))
        for k in ["feed", "pet", "play", "bath"] {
            let r = HomeLook.actReward(k)
            XCTAssertNotNil(r, k)
            XCTAssertEqual(r?.first, "+", k)
            XCTAssertEqual(r, r?.lowercased(), "\(k): подпись строчными")
            XCTAssertLessThanOrEqual(r?.count ?? 99, 12, "\(k): «\(r ?? "")» не влезет под круг 54 pt")
        }
    }

    func testToastSplitTakesRewardTail() {
        let a = HomeLook.toastSplit("Задание дня: Покормить 2 раза · +20 🪙")
        XCTAssertEqual(a.text, "Задание дня: Покормить 2 раза")
        XCTAssertEqual(a.reward, "+20 🪙")

        let b = HomeLook.toastSplit("Все задания дня! Погладить · +20 🪙 · +30 🪙 · +1 ✂️")
        XCTAssertEqual(b.text, "Все задания дня! Погладить")
        XCTAssertEqual(b.reward, "+20 🪙 +30 🪙 +1 ✂️")

        let c = HomeLook.toastSplit("Поймал мячик +5 🪙")
        XCTAssertEqual(c.text, "Поймал мячик")
        XCTAssertEqual(c.reward, "+5 🪙")
    }

    func testToastSplitLeavesPlainText() {
        for s in ["Ням!", "Сытость +20", "Гуляет · скоро вернётся", "+5 🪙", "Двор · +много 🪙", ""] {
            let r = HomeLook.toastSplit(s)
            XCTAssertEqual(r.text, s, s)
            XCTAssertNil(r.reward, s)
        }
    }

    func testToastSplitKeepsWholeTextForVoiceOver() {
        // Вью берёт подпись из полного текста; части в сумме не теряют слов.
        let s = "Задание дня: Поиграть · +15 🪙"
        let r = HomeLook.toastSplit(s)
        XCTAssertEqual("\(r.text) · \(r.reward ?? "")", s)
    }

    func testQuestShowsFirstOpenTask() throws {
        let b = TaskBoard(day: 1, items: [
            DailyTask(id: "feed", need: 2, n: 2, coins: 20, doneT: 100),
            DailyTask(id: "pet", need: 3, n: 1, coins: 45),
            DailyTask(id: "play", need: 1, coins: 15),
        ], allPaid: false, allShards: 1, allCoins: 0, swapsLeft: 1)
        let q = try XCTUnwrap(HomeLook.quest(b))
        XCTAssertEqual(q.done, 1)
        XCTAssertEqual(q.total, 3)
        XCTAssertEqual(q.fraction, 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(q.title, "Погладить 3 раза")
        XCTAssertEqual(q.emoji, DailyTaskText.emoji("pet"))
        XCTAssertEqual(q.caption, "Задание дня · 1/3")
        XCTAssertEqual(q.reward, "+45 🪙")
        XCTAssertFalse(q.allDone)
        XCTAssertTrue(q.a11y.hasPrefix("Задания дня: выполнено 1 из 3"))
        XCTAssertTrue(q.a11y.contains("1 / 3"))
    }

    func testQuestAllDoneAndEmpty() throws {
        let b = TaskBoard(day: 1, items: [DailyTask(id: "feed", need: 1, n: 1, coins: 20, doneT: 5)],
                          allPaid: true, allShards: 1, allCoins: 0, swapsLeft: 0)
        let q = try XCTUnwrap(HomeLook.quest(b))
        XCTAssertTrue(q.allDone)
        XCTAssertEqual(q.fraction, 1)
        XCTAssertNil(q.reward)
        XCTAssertEqual(q.title, "Все выполнены")
        XCTAssertNil(HomeLook.quest(TaskBoard(day: 1, items: [], allPaid: false, allShards: 0, allCoins: 0, swapsLeft: 0)))
    }

    func testShortNumbers() {
        XCTAssertEqual(HomeLook.short(0), "0")
        XCTAssertEqual(HomeLook.short(999), "999")
        XCTAssertEqual(HomeLook.short(1000), "1к")
        XCTAssertEqual(HomeLook.short(1250), "1,2к")
        XCTAssertEqual(HomeLook.short(12_400), "12к")
        XCTAssertEqual(HomeLook.short(3_200_000), "3м")
        XCTAssertEqual(HomeLook.short(-1500), "−1,5к")
    }
}
