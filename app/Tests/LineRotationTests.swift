// Ротация реплик (LineRotation, Lines): без повторов 7 дней на настоящих пулах с учётом tier,
// редкие кадры — ровно 1 из 20 получасов, дневная пасхалка не реже раза в 3 дня, без повторов неделю.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let t0: Double = 1_760_000_000
private let week: Double = 7 * 86400

final class LineRotationTests: XCTestCase {

    private func realLines() throws -> Lines {
        let lines = Lines.shared
        guard !(lines.sections["widget"] ?? [:]).isEmpty else { throw XCTSkip("lines.json нет в бандле") }
        return lines
    }

    // MARK: генератор и порядок

    func testStableRandomGolden() {
        var r = StableRandom(seed: 0)
        XCTAssertEqual(r.next(), 0xE220_A839_7B1D_CDAF, "splitmix64 от 0 — известное значение")
        XCTAssertEqual(StableHash.fnv1a("golden"), 0x2B72_C88E_FE37_D9C4)
        let h = StableRandom.mix(StableHash.fnv1a("golden"))
        XCTAssertEqual(h, 0xA90E_0A46_F956_A476)
        // Порядок не должен меняться между версиями: иначе после обновления реплики пойдут по кругу заново.
        XCTAssertEqual(LineRotation.order(count: 10, seed: h, cycle: 0, block: 1), [6, 7, 1, 9, 3, 0, 4, 8, 2, 5])
        XCTAssertEqual(LineRotation.order(count: 10, seed: h, cycle: 5, block: 3), [7, 6, 1, 9, 0, 3, 2, 8, 4, 5])
        XCTAssertEqual(LineRotation.order(count: 10, seed: h, cycle: -1, block: 3), [7, 1, 6, 0, 3, 9, 4, 8, 2, 5])
    }

    func testFloorDivAndMod() {
        XCTAssertEqual(LineRotation.floorDiv(7, 3), 2)
        XCTAssertEqual(LineRotation.floorDiv(-7, 3), -3)
        XCTAssertEqual(LineRotation.floorDiv(-6, 3), -2)
        XCTAssertEqual(LineRotation.mod(-7, 3), 2)
        XCTAssertEqual(LineRotation.mod(6, 3), 0)
    }

    func testOrderIsPermutationAndKeepsGap() {
        for n in 1...45 {
            for w in [1, 2, 3, 5, 8] where w <= n {
                let seed = StableHash.fnv1a("perm:\(n):\(w)")
                var prev: [Int]? = nil
                for c in -2...6 {
                    let o = LineRotation.order(count: n, seed: seed, cycle: c, block: w)
                    XCTAssertEqual(o.sorted(), Array(0..<n), "n=\(n) w=\(w) c=\(c)")
                    if let prev {
                        // Строка i: позиция в прошлом цикле → позиция в этом; расстояние ≥ n − w + 1.
                        for i in 0..<n {
                            let a = prev.firstIndex(of: i)!, b = o.firstIndex(of: i)!
                            XCTAssertGreaterThanOrEqual(n - a + b, n - w + 1, "n=\(n) w=\(w) c=\(c) i=\(i)")
                        }
                    }
                    prev = o
                }
            }
        }
    }

    func testPlanPicksShortestPeriodThatFitsWeek() {
        for n in 1...80 {
            for slack in 0...12 {
                let p = LineRotation.plan(count: n, slack: slack)
                let need = { (h: Int) in (LineRotation.windowHours + h - 1) / h + 1 + slack }
                if let fit = LineRotation.periodsHours.first(where: { n >= need($0) }) {
                    XCTAssertEqual(p.periodHours, fit)
                    XCTAssertEqual(n - p.block + 1, need(fit), "n=\(n) slack=\(slack)")
                } else {
                    XCTAssertEqual(p.periodHours, 24)
                    XCTAssertEqual(p.block, 1)
                }
            }
        }
        XCTAssertEqual(LineRotation.rareGap, 18)
    }

    // MARK: без повторов на настоящих пулах

    /// Строку видно только на её ходу и, если следующие строки недоступны (tier), чуть дольше — до (slack+1) ходов.
    /// Между разными ходами одной строки — не меньше недели.
    func testNoRepeatWithinWeekOnRealPools() throws {
        let lines = try realLines()
        let step: Double = 1800
        var checked = 0
        for section in ["widget", "island"] {
            for (key, all) in lines.sections[section] ?? [:] where !key.hasPrefix("rare") {
                let own = Lines.owners(all)
                // Мелкие пулы неделю не держат: у них цикл n дней.
                guard own.count >= (LineRotation.windowHours + 23) / 24 + 1 + Lines.slack(own.map { all[$0] }) else { continue }
                for (seed, tz, bed) in [("pet", 0, 23 * 60), ("Шиба-42", 180, 22 * 60), ("abc", -300, 30)] {
                    let owner = Owner(bedMin: bed, wakeMin: 8 * 60, tzOffsetMin: tz)
                    // Строка без tier, вернувшаяся после другой, — не раньше чем через неделю с прошлого показа.
                    // Строки эскалации (tier 2–3) выходят на ходах строк tier 1 и могут повторяться чаще.
                    var last: [String: Double] = [:]
                    var prev: String?
                    var t = t0
                    while t < t0 + 35 * 86400 {
                        let tier = Presenter.tier(t, owner)
                        guard let it = lines.pick(section, key, seed: seed, at: t, tzOffsetMin: tz, tier: tier) else {
                            XCTFail("\(section).\(key): пусто"); break
                        }
                        if it.id != prev, it.tier == nil, let g = last[it.id] {
                            XCTAssertGreaterThanOrEqual(t - g, week,
                                "\(section).\(key) \(it.id) seed=\(seed) tz=\(tz): повтор через \((t - g) / 3600) ч")
                        }
                        last[it.id] = t
                        prev = it.id
                        t += step
                    }
                }
                checked += 1
            }
        }
        XCTAssertGreaterThanOrEqual(checked, 12, "проверены основные пулы виджета и острова")
    }

    func testEscalationPoolsHaveTierOneLines() throws {
        let lines = try realLines()
        for section in ["widget", "island"] {
            for (key, all) in lines.sections[section] ?? [:] where all.contains(where: { ($0.tier ?? 1) > 1 }) {
                XCTAssertTrue(all.contains { $0.tier == 1 }, "\(section).\(key): строкам tier 2–3 нужны ходы строк tier 1")
            }
        }
    }

    func testCommonWidgetPoolsAreBigEnough() throws {
        let lines = try realLines()
        let w = lines.sections["widget"] ?? [:]
        for key in ["ok", "morning", "evening", "sleep", "hungry", "dirty", "tired", "bored", "wants_love"] {
            XCTAssertGreaterThanOrEqual(w[key]?.count ?? 0, 30, "widget.\(key)")
        }
        XCTAssertGreaterThanOrEqual(lines.sections["island"]?["ok"]?.count ?? 0, 30, "island.ok")
    }

    func testSlotPickCyclesWithoutShortRepeats() throws {
        let lines = try realLines()
        // Уведомления: слот — день; строка не повторяется раньше чем через min(7, n) дней.
        for (key, all) in lines.sections["notifications"] ?? [:] {
            let vars = ["item": "хрустики", "count": "3", "steps": "1000", "friend": "Бим"]
            var last: [String: Int] = [:]
            for day in 20_000..<20_060 {
                guard let it = lines.pick("notifications", key, seed: "pet", slot: day, vars: vars) else { continue }
                if let d = last[it.id] {
                    XCTAssertGreaterThanOrEqual(day - d, min(LineRotation.slotGap, all.count), "notifications.\(key)")
                }
                last[it.id] = day
            }
        }
    }

    func testPickIsDeterministicAndHoldsForPeriod() throws {
        let lines = try realLines()
        let a = lines.widget(["ok"], seed: "pet", at: t0, tzOffsetMin: 120)
        XCTAssertEqual(a, lines.widget(["ok"], seed: "pet", at: t0, tzOffsetMin: 120))
        let all = lines.sections["widget"]?["ok"] ?? []
        let p = Lines.plan(all).periodHours
        let start = Double(LineRotation.slot(t0, tzOffsetMin: 0, periodHours: p) * p * 3600)
        let first = lines.widget(["ok"], seed: "pet", at: start)
        XCTAssertEqual(first, lines.widget(["ok"], seed: "pet", at: start + Double(p) * 3600 - 60), "строка держится весь ход")
        XCTAssertNotEqual(first, lines.widget(["ok"], seed: "pet", at: start + Double(p) * 3600), "следующий ход — другая строка")
    }

    // MARK: редкие кадры

    func testRareScheduleOnePerBlockAndDaytimeEveryThreeDays() {
        for seed in ["pet", "abc", "Шиба-42"] {
            for tz in [0, 120, -420, 330] {
                let total = 20 * 48  // 20 дней по полчаса
                var count = 0
                var blocks = Set<Int>()
                var lastDay: Double? = nil
                var maxDayGap: Double = 0
                for k in 0..<total {
                    let t = t0 + Double(k) * 1800
                    guard let b = LineRotation.rareBlock(seed: seed, at: t, tzOffsetMin: tz) else { continue }
                    count += 1
                    XCTAssertTrue(blocks.insert(b).inserted, "в блоке один редкий слот")
                    let q = LineRotation.floorDiv(LineRotation.localMinute(t, tz), LineRotation.rareSlotMinutes)
                    if LineRotation.isDay(slot: q) {
                        if let l = lastDay { maxDayGap = max(maxDayGap, t - l) }
                        lastDay = t
                    }
                }
                XCTAssertEqual(Double(count), Double(total) / Double(LineRotation.rareEvery), accuracy: 1, "~1 из 20")
                XCTAssertLessThanOrEqual(maxDayGap, 3 * 86400, "дневная пасхалка не реже раза в 3 дня")
                XCTAssertLessThanOrEqual(maxDayGap, 36 * 3600, "на деле — не реже чем раз в полтора дня")
            }
        }
    }

    func testRareLinesDoNotRepeatWithinWeek() throws {
        let lines = try realLines()
        for seed in ["pet", "abc"] {
            for sleeping in [false, true] {
                var last: [String: Double] = [:]
                var shown = 0
                for k in 0..<(40 * 48) {
                    let t = t0 + Double(k) * 1800
                    guard let it = lines.rare(sleeping: sleeping, seed: seed, at: t) else { continue }
                    shown += 1
                    XCTAssertNotNil(it.frame, "\(it.id): у редкой строки есть frame")
                    if let l = last[it.id] { XCTAssertGreaterThanOrEqual(t - l, week, "\(it.id) seed=\(seed)") }
                    last[it.id] = t
                    let island = lines.rareIsland(it, sleeping: sleeping, seed: seed, at: t)
                    XCTAssertNotNil(island)
                    XCTAssertLessThanOrEqual(island?.count ?? 0, LineLimit.island)
                }
                XCTAssertGreaterThan(shown, 80)
            }
        }
    }

    func testRarePoolsMatchByFrame() throws {
        let lines = try realLines()
        for key in ["rare", "rare_sleep"] {
            let w = lines.sections["widget"]?[key] ?? []
            let i = lines.sections["island"]?[key] ?? []
            XCTAssertGreaterThanOrEqual(w.count, LineRotation.rareGap, "widget.\(key): пул держит неделю")
            let frames = Set(i.compactMap(\.frame))
            for it in w {
                XCTAssertNotNil(it.frame, it.id)
                XCTAssertTrue(frames.contains(it.frame ?? ""), "\(it.id): нет пары на острове")
                XCTAssertLessThanOrEqual(it.text.count, LineLimit.widget, it.id)
            }
        }
    }

    func testPresenterShowsRareOnlyInCalmMoods() throws {
        _ = try realLines()
        let f = SaveFile.fresh(now: t0)
        var rares = 0
        for k in 2..<(2 * 48) {
            let t = t0 + Double(k) * 1800
            let snap = Presenter.make(f, at: t)
            let o = PetRunner.owner(f, at: t)
            let slot = LineRotation.rareBlock(seed: f.petId, at: t, tzOffsetMin: o.tzOffsetMin) != nil
            if let frame = snap.rare {
                rares += 1
                XCTAssertTrue(slot, "пасхалка только в редком слоте")
                XCTAssertTrue(Presenter.rareMoods.contains(snap.mood), "настроение \(snap.mood)")
                let key = (snap.mood == "sleep" || snap.mood == "nap") ? "rare_sleep" : "rare"
                XCTAssertTrue((Lines.shared.sections["widget"]?[key] ?? []).contains { $0.frame == frame && $0.text == snap.line })
            } else if slot && Presenter.rareMoods.contains(snap.mood) {
                XCTFail("редкий слот в спокойном настроении без пасхалки, t=\(t)")
            }
        }
        XCTAssertLessThanOrEqual(rares, 6)
    }
}
