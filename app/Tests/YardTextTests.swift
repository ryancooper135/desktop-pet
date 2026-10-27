// Волна 34 G: тексты экрана «Двор» и бейдж кнопки (YardText).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

final class YardTextTests: XCTestCase {
    private let t0: Double = 1_760_054_400
    private let hour: Double = 3600
    private let cfg = YardConfig()

    func testPerHourRounds() {
        XCTAssertEqual(YardText.perHour(14), "+14/ч")
        XCTAssertEqual(YardText.perHour(44.1), "+44/ч")
        XCTAssertEqual(YardText.perHour(0), "+0/ч")
    }

    func testBankCaption() {
        let clock: (Double) -> String = { _ in "21:10" }
        XCTAssertEqual(YardText.bank(fill: 0.4, fullAt: t0, clock: clock), "полная в 21:10")
        XCTAssertEqual(YardText.bank(fill: 1, fullAt: t0, clock: clock), "Полная — собери")
        XCTAssertEqual(YardText.bank(fill: 0, fullAt: nil, clock: clock), "Поставь станцию — и копилка пойдёт")
    }

    func testMoreCountsCollects() {
        // ставка 6/ч → полная копилка (сутки) 144 🪙
        XCTAssertEqual(YardText.more(price: 700, coins: 60, rate: 6, cfg), "ещё 640 🪙 · ≈ 5 сборов")
        XCTAssertEqual(YardText.more(price: 100, coins: 60, rate: 6, cfg), "ещё 40 🪙 · ≈ 1 сбор")
        XCTAssertEqual(YardText.more(price: 300, coins: 60, rate: 6, cfg), "ещё 240 🪙 · ≈ 2 сбора")
        XCTAssertEqual(YardText.more(price: 100, coins: 0, rate: 0, cfg), "ещё 100 🪙")
        XCTAssertEqual(YardText.more(price: 100, coins: 100, rate: 0, cfg), "Хватает, бери")
        XCTAssertEqual(YardText.progress(price: 400, coins: 100), 0.25, accuracy: 1e-9)
        XCTAssertEqual(YardText.progress(price: 400, coins: 900), 1)
        XCTAssertEqual(YardText.progress(price: 0, coins: 0), 1)
    }

    func testPayback() {
        XCTAssertNil(YardText.payback(nil))
        XCTAssertEqual(YardText.payback(0.4), "окупится меньше чем за день")
        XCTAssertEqual(YardText.payback(2.1), "окупится за ≈ 3 дн.")
        // сушилка 1 → 2: 60 🪙 за +2/ч = 1,25 дня
        XCTAssertEqual(YardText.payback(Yard.paybackDays("dryer", level: 1, cfg)), "окупится за ≈ 2 дн.")
    }

    func testLockTexts() {
        XCTAssertEqual(YardText.lock(.level(9), cfg), "Нужен ур. 9 пса")
        XCTAssertEqual(YardText.lock(.tier(2), cfg), "Откроется в ярусе «Сад»")
        XCTAssertEqual(YardText.lock(.order("fence"), cfg), "Сначала — «Починить забор»")
        XCTAssertTrue(YardText.lock(.kitchen(1), cfg).hasPrefix("Нужна кухня: «"))
        XCTAssertEqual(YardText.noCoins(340), "Не хватает 340 🪙 — собери копилку")
    }

    func testTierButton() {
        let open = YardText.tierButton(.open(tier: 2, price: 1700), cfg)
        XCTAssertEqual(open.title, "Открыть ярус «Сад»")
        XCTAssertTrue(open.isOpen)
        let lv = YardText.tierButton(.level(tier: 2, need: 9), cfg)
        XCTAssertEqual(lv.reason, "нужен ур. 9 пса")
        XCTAssertFalse(lv.isOpen)
        let pl = YardText.tierButton(.plates(tier: 1, left: ["daisy", "dryer"]), cfg)
        XCTAssertEqual(pl.title, "Ярус «Дворик»")
        XCTAssertEqual(pl.reason, "купи все плиты яруса — осталось 2")
        XCTAssertEqual(YardText.tierButton(.maxed, cfg).title, "Все ярусы открыты")
    }

    func testHarvestToast() {
        XCTAssertEqual(YardText.harvest(YardHarvest(), cfg), "Пока пусто — станции ещё копят")
        var h = YardHarvest()
        h.coins = 132
        h.bonus = 12
        h.tip = .bonus
        h.portions = ["porridge": 2, "pies": 1]
        h.pantry = 18
        XCTAssertEqual(YardText.harvest(h, cfg), "+132 🪙 · чаевые +12 · в кладовую: пирожок, каша ×2")
        var t = YardHarvest()
        t.coins = 40
        t.tickets = 1
        t.tip = .ticket
        XCTAssertEqual(YardText.harvest(t, cfg), "+40 🪙 · билетик 🎟")
    }

    /// Карточка «следующая плита» не застревает на котелке без кухни: двор идёт дальше.
    func testFocusSkipsKitchenWait() {
        var s = YardState()
        s.plates = ["window", "daisy", "trash", "fence", "path", "lamp"]
        s.stations = ["dryer": 1, "bones": 1]
        XCTAssertEqual(YardText.focusPlate(s, yardLevel: 1, dogLevel: 9, kitchenLevel: 0, cfg)?.id, "porridge",
                       "яруса 2 нет — показываем котелок с его замком")
        XCTAssertEqual(YardText.focusPlate(s, yardLevel: 2, dogLevel: 9, kitchenLevel: 0, cfg)?.id, "mailbox")
        XCTAssertEqual(YardText.focusPlate(s, yardLevel: 2, dogLevel: 9, kitchenLevel: 1, cfg)?.id, "porridge")
        XCTAssertEqual(YardText.focusPlate(YardState(), yardLevel: 0, dogLevel: 1, kitchenLevel: 0, cfg)?.id, "window")
    }

    func testBadgeOnFullBankOrAffordablePlate() {
        var f = SaveFile.fresh(now: t0)
        f.econ.wallet.coins = 0
        XCTAssertFalse(YardText.badge(f, now: t0, dogLevel: 1, cfg), "нечего собрать и не на что купить")
        f.econ.wallet.coins = 10
        XCTAssertTrue(YardText.badge(f, now: t0, dogLevel: 1, cfg), "хватает на «Протереть окно»")

        f.econ.wallet.coins = 0
        f.yard.plates = ["window", "daisy"]
        f.yard.stations = ["dryer": 1]
        f.yard.t = t0
        XCTAssertFalse(YardText.badge(f, now: t0 + hour, dogLevel: 1, cfg))
        XCTAssertFalse(YardText.badge(f, now: t0 + 13 * hour, dogLevel: 1, cfg), "полсуток — ещё не полная")
        XCTAssertTrue(YardText.badge(f, now: t0 + 25 * hour, dogLevel: 1, cfg), "копилка полная")

        // Монет хватает, но плита закрыта уровнем пса — бейджа нет.
        var g = SaveFile.fresh(now: t0)
        g.yard.plates = ["window", "daisy"]
        g.econ.wallet.coins = 1000
        XCTAssertFalse(YardText.badge(g, now: t0, dogLevel: 1, cfg), "сушилка с ур. 2")
        XCTAssertTrue(YardText.badge(g, now: t0, dogLevel: 2, cfg))
    }
}
