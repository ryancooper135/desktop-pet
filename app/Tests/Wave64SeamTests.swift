// Волна 64: мини-игры решают «занят / плашка / монеты» на текущее время, а не по снимку model.snap.t;
// Tricks.gate и MiniGames.busy берут правила ядра из того же источника, что PetRunner.apply (ItemPerks.rules).
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore (плюс чтение исходников экранов).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let w64T0: Double = 1_760_054_400   // 2025-10-10 00:00 UTC
private let w64H: Double = 3600

private let w64App = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

final class Wave64SeamTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Clock.zoneOverride = TimeZone(identifier: "UTC")
    }

    override func tearDown() {
        Clock.zoneOverride = nil
        super.tearDown()
    }

    /// Пёс днём, всё по 60, хозяин ложится в 23:00 и встаёт в 7:00 (UTC).
    private func dayFile(at t: Double = w64T0 + 12 * w64H) -> SaveFile {
        var f = SaveFile.fresh(now: t - 600)
        f.petId = "w64-pet"
        f.owner.tzOffsetMin = 0
        f.owner.bedMin = 23 * 60
        f.owner.wakeMin = 7 * 60
        for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 60 }
        return f
    }

    /// Правила ядра этого сейва, у которых ночь пса начинается на 12 часов раньше: полдень — уже ночь.
    private func earlyNightRules(_ f: SaveFile) throws -> Rules {
        let base = ItemPerks.rules(f)
        let raw = try XCTUnwrap(Catalog.economy())
        guard case .object(var root) = raw, case .object(var care)? = root["care"],
              case .object(var night)? = care["night"], case .object(var off)? = night["pet_sleep_offset_min"]
        else { XCTFail("нет care.night в economy.json"); return base }
        off["after_bed"] = .number(Double(base.afterBedMin - 12 * 60))
        night["pet_sleep_offset_min"] = .object(off)
        care["night"] = .object(night)
        root["care"] = .object(care)
        return try Rules(json: .object(root), preset: base.preset)
    }

    // MARK: 2. текущее время на старте мини-игры

    /// Было: экран открыт в 22:58 (снимок), старт в 23:40 — ночь пса уже идёт, а раунд «настоящий» и без плашки.
    func testStartSeesNightThatBeganAfterSnapshot() {
        let f = dayFile()
        let r = ItemPerks.rules(f)
        let snapT = w64T0 + 23 * w64H - 120          // 22:58
        let nightStart = w64T0 + 23 * w64H + Double(r.afterBedMin) * 60
        let now = nightStart + 300
        XCTAssertFalse(PetEngine.petNight(snapT, r, PetRunner.owner(f, at: snapT)), "на снимке — ещё вечер")
        XCTAssertTrue(PetEngine.petNight(now, r, PetRunner.owner(f, at: now)), "сейчас — ночь пса")

        for g in MiniGame.allCases {
            XCTAssertNil(MiniGames.start(f, g, now: snapT).busy, "\(g): на снимке пёс свободен")
            let s = MiniGames.start(f, g, now: now)
            XCTAssertEqual(s.busy, "asleep", "\(g): старт после начала ночи — «просто так»")
            XCTAssertEqual(s.note, "asleep", "\(g): плашка про сон")
        }
    }

    /// Было: дрёма кончилась минуты назад, снимок ещё её помнит — карточка «Шиба спит», раунд без монет.
    func testStartSeesNapEnded() {
        var f = dayFile()
        let snapT = w64T0 + 12 * w64H
        f.pet.napUntil = snapT + 300
        let now = snapT + 900
        for g in MiniGame.allCases {
            XCTAssertEqual(MiniGames.start(f, g, now: snapT).busy, "asleep")
            XCTAssertNil(MiniGames.start(f, g, now: now).busy, "\(g): дрёма кончилась — раунд настоящий")
        }
    }

    /// Было: вчера монеты кончились, после полуночи снимок ещё вчерашний — «Монеты на сегодня всё», 0 монет.
    func testStartSeesNewDayCoins() {
        var f = dayFile()
        f.owner.bedMin = 3 * 60          // хозяин сова: в 0:01 пёс ещё не спит
        f.owner.wakeMin = 11 * 60
        let snapT = w64T0 + 24 * w64H - 60           // 23:59
        let now = w64T0 + 24 * w64H + 60              // 0:01 следующих суток
        let day = DayKey.of(snapT)
        for g in MiniGame.allCases {
            f[keyPath: g.dayKey] = day
            f[keyPath: g.coinsKey] = 10_000
        }
        for g in MiniGame.allCases {
            let stale = MiniGames.start(f, g, now: snapT)
            XCTAssertEqual(stale.left, 0, "\(g): вчера потолок")
            XCTAssertEqual(stale.note, MiniGames.capReason)
            let fresh = MiniGames.start(f, g, now: now)
            XCTAssertGreaterThan(fresh.left, 0, "\(g): новые сутки — монеты снова есть")
            XCTAssertNil(fresh.note, "\(g): плашки нет")
            XCTAssertEqual(fresh.left, g.coinsLeft(f, now: now))
        }
    }

    /// Старт = то же, что busy/note/coinsLeft по отдельности на тот же момент; без сейва — пусто.
    func testStartMatchesPartsAndNoFile() {
        let f = dayFile()
        let t = w64T0 + 15 * w64H
        for g in MiniGame.allCases {
            let s = MiniGames.start(f, g, now: t)
            XCTAssertEqual(s.busy, MiniGames.busy(f, at: t))
            XCTAssertEqual(s.note, MiniGames.note(f, at: t, left: s.left))
            XCTAssertEqual(s.left, g.coinsLeft(f, now: t))
        }
        XCTAssertEqual(MiniGames.start(nil, .runner, now: t), MiniGames.Start(busy: nil, note: nil, left: 0))
    }

    /// Экраны мини-игр решают по MiniGames.start(…, now: Clock.now()), а не по снимку model.snap.t.
    func testScreensUseCurrentTime() throws {
        for (file, game) in [("RunnerScreen.swift", "runner"), ("BlockDuoScreen.swift", "blockduo"),
                             ("CatchGameScreen.swift", "ball")] {
            let src = try String(contentsOf: w64App.appendingPathComponent("App").appendingPathComponent(file),
                                 encoding: .utf8)
            XCTAssertTrue(src.contains("MiniGames.start(model.file, .\(game), now: Clock.now())"), file)
            for stale in ["MiniGames.busy($0, at: model.snap.t)", "MiniGames.note($0, at: model.snap.t",
                          "coinsLeft($0, now: model.snap.t)"] {
                XCTAssertFalse(src.contains(stale), "\(file): \(stale)")
            }
        }
    }

    // MARK: 3. один источник правил

    /// Было: Tricks.gate и MiniGames.busy считали ночь, «плохо» и отказ play по Catalog.rules — мимо правил сейва.
    /// Подставленные правила (ночь на 12 ч раньше) должны менять ответ — значит, решение идёт по ним.
    func testGateAndBusyFollowGivenRules() throws {
        let f = dayFile()
        let noon = w64T0 + 12 * w64H
        let early = try earlyNightRules(f)
        XCTAssertTrue(PetEngine.petNight(noon, early, PetRunner.owner(f, at: noon)), "подменённые правила: полдень — ночь")
        XCTAssertNil(Tricks.gate(f, at: noon))
        XCTAssertNil(MiniGames.busy(f, at: noon))
        XCTAssertEqual(Tricks.gate(f, at: noon, rules: early), "asleep")
        XCTAssertEqual(MiniGames.busy(f, at: noon, rules: early), "asleep")
    }

    /// По умолчанию — ItemPerks.rules(f): щенок (стадия роста) и надетые вещи дают другие правила, чем Catalog.rules.
    func testDefaultRulesAreItemPerks() {
        var f = dayFile()
        f.econ.items["bandana_red"] = 1
        f.econ.items["ball_tennis"] = 1
        XCTAssertFalse(ItemPerks.coreMods(f).isEmpty, "у сейва есть польза вещей/роста — правила отличаются")
        for h in stride(from: 0.0, to: 24, by: 1) {
            let t = w64T0 + h * w64H
            let r = ItemPerks.rules(f)
            XCTAssertEqual(Tricks.gate(f, at: t), Tricks.gate(f, at: t, rules: r), "час \(h)")
            XCTAssertEqual(MiniGames.busy(f, at: t), MiniGames.busy(f, at: t, rules: r), "час \(h)")
        }
    }

    /// Шов: «пёс свободен для игры» (busy == nil) ⇔ ядро через PetRunner.apply принимает «Поиграть» в тот же момент.
    func testBusyAgreesWithRunnerApplyAcrossDay() {
        for h in stride(from: 0.0, to: 24, by: 0.5) {
            for energy in [5.0, 60.0] {
                let t = w64T0 + h * w64H
                var f = dayFile(at: t)          // сейв за 10 минут до t: догон короткий, событий по дороге нет
                f.econ.items["bandana_red"] = 1
                f.pet.needs[.energy] = energy
                let busy = MiniGames.busy(f, at: t)
                var g = f
                let out = PetRunner.apply(.play, source: .app, to: &g, now: t)
                XCTAssertEqual(busy == nil, out.ok, "час \(h), энергия \(energy): busy \(busy ?? "nil"), apply \(out.reason ?? "ok")")
                if let busy, !out.ok { XCTAssertEqual(busy, out.reason, "час \(h): та же причина") }
            }
        }
    }
}
