// Волна 47 T: лишняя нагрузка. AppModel.dogAsk читается телом HomeScreen (дважды, на каждое движение пальца) —
// теперь через AskMemo: DogAsks.shown раз на (запись сейва, now). Здесь — что ответ ровно тот же, что кэш
// сбрасывается при любой смене сейва, времени, пояса и выключателя, и замер «до/после».

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let pT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

/// Бодрый пёс с полным журналом; последняя запись — lag назад (pet.t на диске отстаёт от now, как между refresh).
private func pFile(lag: Double, journal: Int = 200) -> SaveFile {
    let start = pT0 - 6 * 3600
    var f = SaveFile.fresh(now: start)
    f.petId = "w47t-pet"
    for n in Need.allCases { f.pet.needs[n] = 90 }
    DogLevel.settle(&f, now: start)
    for i in 0..<journal {
        f.log(i % 3 == 0 ? "act.pet" : "act.feed", t: start + Double(i) * 30, source: .app, ok: true)
    }
    PetRunner.catchUp(&f, now: pT0 - lag)
    return f
}

/// Сегодня одна просьба со стартом 20 минут назад: kind nil — ещё не решена (shown решает её на копии через peek
/// на старт), иначе — решена.
private func withAsk(_ f: SaveFile, kind: String?, ago: Double = 1200) -> SaveFile {
    var g = f
    g.asks.items = [kind.map { DogAsk(start: pT0 - ago, kind: $0, coins: 10) } ?? DogAsk(start: pT0 - ago)]
    return g
}

private func us(_ n: Int, _ body: () -> Void) -> Double {
    let a = Date()
    for _ in 0..<n { body() }
    return Date().timeIntervalSince(a) / Double(n) * 1e6
}

final class Wave47PerfTests: XCTestCase {
    override func setUp() { super.setUp(); DogAsks.enabled = true }
    override func tearDown() { Clock.zoneOverride = nil; DogAsks.enabled = true; super.tearDown() }

    /// Кэш ничего не меняет: на любых сейвах и моментах — ровно DogAsks.shown.
    func testMemoEqualsShown() {
        var cases: [SaveFile] = []
        for lag in [Double]([0, 1800, 10800]) {
            let f = pFile(lag: lag)
            cases += [f, withAsk(f, kind: nil), withAsk(f, kind: "pet"), withAsk(f, kind: DogAsks.skip)]
            var nap = withAsk(f, kind: "pet")
            nap.pet.napUntil = pT0 + 1800
            cases.append(nap)
        }
        var shownSome = 0
        for f in cases {
            for now in [pT0 - 3600, pT0 - 1200, pT0, pT0 + 600, pT0 + 7200] {
                var m = AskMemo()
                let want = DogAsks.shown(f, now: now)
                XCTAssertEqual(m.shown(f, now: now), want)
                XCTAssertEqual(m.shown(f, now: now), want, "из кэша — то же")
                XCTAssertEqual(m.misses, 1)
                if want != nil { shownSome += 1 }
            }
        }
        XCTAssertGreaterThan(shownSome, 0, "есть случаи с видимой просьбой — сравнение не на одних nil")
    }

    /// Один memo на смену сейвов и моментов подряд (как у AppModel): каждый ответ — как без кэша.
    func testMemoFollowsSequence() {
        var m = AskMemo()
        var f = withAsk(pFile(lag: 1800), kind: "pet")
        let open = DogAsks.shown(f, now: pT0)
        XCTAssertNotNil(open, "просьба открыта и видна")
        XCTAssertEqual(m.shown(f, now: pT0), open)

        // Выполнили (pet): запись двигает seq и pet.t — кэш пересчитывает, плашки больше нет.
        XCTAssertTrue(PetRunner.apply(.pet, source: .app, to: &f, now: pT0 + 60).ok)
        let after = DogAsks.shown(f, now: pT0 + 60)
        XCTAssertNil(after)
        XCTAssertEqual(m.shown(f, now: pT0 + 60), after)
        XCTAssertEqual(m.misses, 2)
    }

    func testMemoInvalidates() {
        let base = withAsk(pFile(lag: 1800), kind: "pet")
        var m = AskMemo()
        _ = m.shown(base, now: pT0)
        _ = m.shown(base, now: pT0)
        XCTAssertEqual(m.misses, 1, "та же пара — без пересчёта")

        // Другой now (следующий refresh).
        _ = m.shown(base, now: pT0 + 30)
        XCTAssertEqual(m.misses, 2)

        // Каждое поле записи сейва по отдельности.
        var edits: [(String, (inout SaveFile) -> Void)] = [
            ("rev", { $0.rev += 1 }),
            ("seq", { $0.seq += 1 }),
            ("pet.t", { $0.pet.t += 60 }),
            ("petId", { $0.petId = "w47t-other" }),
            ("deviceId", { $0.deviceId = "w47t-device" }),
        ]
        edits.append(("всё сразу", { $0.rev += 1; $0.seq += 1; $0.pet.t += 60 }))
        for (name, edit) in edits {
            var g = base
            edit(&g)
            var mm = AskMemo()
            _ = mm.shown(base, now: pT0 + 30)
            XCTAssertEqual(mm.shown(g, now: pT0 + 30), DogAsks.shown(g, now: pT0 + 30), name)
            XCTAssertEqual(mm.misses, 2, "\(name): другая запись сейва — пересчёт")
        }

        // Выключатель просьб.
        var e = AskMemo()
        XCTAssertNotNil(e.shown(base, now: pT0))
        DogAsks.enabled = false
        XCTAssertNil(e.shown(base, now: pT0), "выключили — сразу nil, не из кэша")
        XCTAssertEqual(e.misses, 2)
        DogAsks.enabled = true

        // Часовой пояс (перелёт): ночь пса и сутки считаются в нём.
        var z = AskMemo()
        _ = z.shown(base, now: pT0)
        let here = Clock.tzOffsetMin(at: pT0)
        Clock.zoneOverride = TimeZone(secondsFromGMT: (here + 9 * 60) * 60)
        XCTAssertEqual(z.shown(base, now: pT0), DogAsks.shown(base, now: pT0))
        XCTAssertEqual(z.misses, 2, "другой пояс — пересчёт")
    }

    /// Ключ записи сейва: одинаковый у копии, разный при любой записи через PetStore.mutate (rev).
    func testSaveStamp() {
        let f = pFile(lag: 0)
        XCTAssertEqual(SaveStamp(f), SaveStamp(f))
        var g = f
        g.rev += 1
        XCTAssertNotEqual(SaveStamp(f), SaveStamp(g))
    }

    /// Замер «до/после» для DECISIONS: тело HomeScreen читает dogAsk дважды; до — два DogAsks.shown,
    /// после — один на (сейв, now), дальше сравнение ключа. Проверяем только, что попадание в кэш дешевле.
    func testMeasureHitVsMiss() {
        for lag in [Double]([0, 1800, 10800]) {
            for kind in [String?.none, "pet"] {
                let f = withAsk(pFile(lag: lag), kind: kind)
                let before = us(20) { _ = DogAsks.shown(f, now: pT0) }
                var m = AskMemo()
                _ = m.shown(f, now: pT0)
                let after = us(2000) { _ = m.shown(f, now: pT0) }
                print("PROBE lag=\(Int(lag))s ask=\(kind ?? "nil") shown=\(Int(before))us memoHit=\(String(format: "%.2f", after))us")
                XCTAssertLessThan(after, before)
                XCTAssertEqual(m.misses, 1)
            }
        }
    }
}
