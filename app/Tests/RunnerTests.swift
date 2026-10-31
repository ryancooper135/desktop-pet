// «Раннер» (Runner.swift, волна 55b): трасса от сида проходима на тысячах сидов (безопасная полоса, стенки,
// промежутки по времени, перебежки), сложность растёт плавно, мир меняется двор → район → парк, свайпы и
// столкновения, автопилот добегает до финиша; монеты с убыванием, своим и общим потолком мини-игр, пёс занят —
// заезд «просто так» без наград, рекорд, поля сейва верхним уровнем (старые сейвы читаются), новый щенок.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000: днём пёс не спит.
private let rT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

private func rFile(at t: Double = rT0, level: Double = 60) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = "runner-pet-1"
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = level }
    return f
}

/// Конфиг с явными цифрами — тесты не зависят от правок economy.json.
private func rCfg(cap: Int = 60, shared: Int = 60) -> RunnerConfig {
    var c = RunnerConfig()
    c.base = 5
    c.max = 35
    c.parScore = 1500
    c.dailyCap = cap
    c.sharedCap = shared
    c.diminishing = [.init(from: 1, x: 1), .init(from: 7, x: 0.5), .init(from: 13, x: 0.2)]
    return c
}

/// Сколько метров пробегается за 3 минуты при этой скорости (с запасом): дальше трассу не проверяем.
private let fullRun = 2300.0

final class RunnerTests: XCTestCase {

    // MARK: трасса

    func testTrackIsDeterministicFromSeed() {
        var a = RunnerTrack(seed: 42, cfg: rCfg())
        var b = RunnerTrack(seed: 42, cfg: rCfg())
        var c = RunnerTrack(seed: 43, cfg: rCfg())
        a.ensure(to: 800); b.ensure(to: 800); c.ensure(to: 800)
        XCTAssertEqual(a.rows, b.rows)
        XCTAssertEqual(a.coins, b.coins)
        XCTAssertNotEqual(a.rows.map(\.lanes), c.rows.map(\.lanes), "другой сид — другая трасса")
        // Достраивание кусками даёт ту же трассу, что сразу.
        var d = RunnerTrack(seed: 42, cfg: rCfg())
        for z in stride(from: 10.0, through: 800, by: 37) { d.ensure(to: z) }
        d.ensure(to: 800)
        XCTAssertEqual(Array(d.rows.prefix(a.rows.count)), a.rows)
    }

    /// Главное обещание: на тысячах сидов каждый ряд проходим, и от ряда к ряду есть путь с учётом времени
    /// на перебежку (смена полосы 0,12 с, пока собака не на препятствии). Проверка независима от генератора:
    /// по рядам, а не по полю safe.
    func testEveryTrackIsPassableOnThousandsOfSeeds() {
        let cfg = rCfg()
        var rowsTotal = 0, walls = 0
        for seed in 0..<2000 as Range<UInt64> {
            var track = RunnerTrack(seed: seed &* 0x9E37_79B9 &+ 7, cfg: cfg)
            track.ensure(to: fullRun)
            let rows = track.rows
            XCTAssertGreaterThanOrEqual(rows.first?.z ?? 0, Runner.startClear, "seed \(seed): старт свободен")
            // Достижимые полосы перед первым рядом — все (до него 30 м разгона).
            var reach: Set<Int> = [0, 1, 2]
            for (i, row) in rows.enumerated() {
                rowsTotal += 1
                if row.wall { walls += 1 }
                XCTAssertEqual(row.index, i)
                XCTAssertTrue(row.lanes.contains { $0 != nil }, "seed \(seed) row \(i): пустых рядов нет")
                XCTAssertTrue(row.lanes.allSatisfy { $0.map { row.biome.kinds.contains($0) } ?? true },
                              "seed \(seed) row \(i): препятствия из своего мира")
                if row.wall {
                    XCTAssertGreaterThan(row.z, Runner.wallFrom)
                    XCTAssertTrue((0..<3).allSatisfy { row.passable($0) }, "стенка проходима действием в любой полосе")
                    XCTAssertEqual(Set(row.lanes.compactMap { $0 }).count, 1, "стенка — одно препятствие во всю ширину")
                } else {
                    XCTAssertNil(row.lanes[row.safe], "seed \(seed) row \(i): безопасная полоса пуста")
                }
                let ok = (0..<3).filter { row.passable($0) }
                let now = reach.intersection(ok)
                XCTAssertFalse(now.isEmpty, "seed \(seed) row \(i) z \(row.z): тупик, \(row.lanes)")
                guard i + 1 < rows.count else { break }
                let next = rows[i + 1]
                let v = Runner.speed(at: row.z, cfg)
                let gap = (next.z - row.z) / v
                XCTAssertGreaterThanOrEqual(gap, 0.5, "seed \(seed) row \(i): ряды не слипаются")
                // Свободное время между рядами — минус сами препятствия и длина собаки.
                let busy = (row.span / 2 + next.span / 2 + 2 * Runner.dogHalf) / v
                let shifts = Swift.min(2, Int((gap - busy) / Runner.laneSeconds))
                XCTAssertGreaterThanOrEqual(shifts, 2, "seed \(seed) row \(i): за промежуток успеть через две полосы")
                reach = Set(now.flatMap { a in (0..<3).filter { abs($0 - a) <= shifts } })
            }
            XCTAssertGreaterThanOrEqual(rows.last?.z ?? 0, fullRun - 30)
            // Монеты не лежат на препятствиях своей полосы.
            for c in track.coins {
                let blocked = rows.contains { r in
                    r.lanes[c.lane] != nil && abs(r.z - c.z) < (r.lanes[c.lane]?.length ?? 0) / 2 + Runner.coinReach
                }
                XCTAssertFalse(blocked, "seed \(seed): монета \(c.index) на препятствии")
            }
        }
        XCTAssertGreaterThan(rowsTotal, 2000 * 150, "рядов много — проверка не пустая")
        XCTAssertGreaterThan(walls, 1000, "стенки встречаются")
    }

    func testSafeLaneShiftsAtMostOneLane() {
        for seed in 0..<300 as Range<UInt64> {
            var track = RunnerTrack(seed: seed, cfg: rCfg())
            track.ensure(to: fullRun)
            for (a, b) in zip(track.rows, track.rows.dropFirst()) {
                XCTAssertLessThanOrEqual(abs(a.safe - b.safe), 1)
            }
        }
    }

    func testBiomesCycleYardDistrictPark() {
        let cfg = rCfg()
        XCTAssertEqual(Runner.biome(at: 0, cfg), .yard)
        XCTAssertEqual(Runner.biome(at: 399, cfg), .yard)
        XCTAssertEqual(Runner.biome(at: 400, cfg), .district)
        XCTAssertEqual(Runner.biome(at: 800, cfg), .park)
        XCTAssertEqual(Runner.biome(at: 1200, cfg), .yard, "по кругу")
        XCTAssertEqual(Runner.biome(at: -5, cfg), .yard)
        var track = RunnerTrack(seed: 5, cfg: cfg)
        track.ensure(to: 1300)
        XCTAssertEqual(Set(track.rows.map(\.biome)), Set(RunnerBiome.allCases))
        for b in RunnerBiome.allCases {
            let dodges = Set(b.kinds.map(\.dodge))
            XCTAssertEqual(dodges, [.jump, .slide, .lane], "\(b): в каждом мире прыгнуть, проползти и обежать")
            XCTAssertFalse(b.title.isEmpty)
            XCTAssertFalse(b.icon.isEmpty)
        }
        // Препятствия свои, из мира питомца.
        XCTAssertEqual(Set(RunnerObstacle.allCases.map(\.rawValue)), ["puddle", "flowerbed", "crate", "bench", "pigeons"])
        XCTAssertTrue(RunnerObstacle.allCases.allSatisfy { !$0.title.isEmpty && $0.length > 0 && $0.length <= Runner.maxLength })
    }

    // MARK: сложность

    func testDifficultyGrowsSmoothly() {
        let cfg = rCfg()
        var prev = (k: -1.0, v: 0.0, gap: 99.0, dens: -1.0)
        for d in stride(from: 0.0, through: 3000, by: 10) {
            let k = Runner.difficulty(at: d), v = Runner.speed(at: d, cfg)
            let g = Runner.gapSeconds(at: d), dn = Runner.density(at: d)
            XCTAssertGreaterThan(k, prev.k)
            XCTAssertGreaterThan(v, prev.v)
            XCTAssertLessThan(g, prev.gap)
            XCTAssertGreaterThan(dn, prev.dens)
            if prev.v > 0 { XCTAssertLessThan(v - prev.v, 0.1, "без скачков скорости") }
            prev = (k, v, g, dn)
        }
        XCTAssertEqual(Runner.speed(at: 0, cfg), cfg.speedMin, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(Runner.speed(at: 100_000, cfg), cfg.speedMax)
    }

    /// На трассе препятствий в секунду к концу заезда заметно больше, чем в начале (средне по 200 сидам).
    func testObstaclesPerSecondGrowAlongTheRun() {
        let cfg = rCfg()
        var early = 0.0, late = 0.0
        for seed in 0..<200 as Range<UInt64> {
            var track = RunnerTrack(seed: seed, cfg: cfg)
            track.ensure(to: fullRun)
            func rate(_ from: Double, _ to: Double) -> Double {
                let n = track.rows.filter { $0.z >= from && $0.z < to }.reduce(0) { $0 + $1.lanes.compactMap { $0 }.count }
                let seconds = (to - from) / Runner.speed(at: (from + to) / 2, cfg)
                return Double(n) / seconds
            }
            early += rate(30, 250)
            late += rate(1700, 2000)
        }
        XCTAssertGreaterThan(late, early * 2, "ранние \(early / 200)/с, поздние \(late / 200)/с")
    }

    /// Заезд длится 1–3 минуты: финиш на max_seconds, к минуте пробегается ~полкилометра, 180 с — ~2 км.
    func testRunLengthAndFinish() {
        let cfg = rCfg()
        var run = RunnerRun(seed: 1, cfg: cfg)
        var pilot = Runner.Pilot()
        var finishEvents = 0
        while !run.isOver {
            pilot.step(&run)
            finishEvents += run.advance(by: 1.0 / 60).filter { $0 == .finish }.count
            if run.t > 59.99 && run.t < 60.01 {
                XCTAssertEqual(run.distance, 530, accuracy: 25)
            }
        }
        XCTAssertEqual(run.t, cfg.maxSeconds, accuracy: 1e-9)
        XCTAssertTrue(run.finished)
        XCTAssertEqual(finishEvents, 1)
        XCTAssertEqual(run.distance, 2064, accuracy: 40)
        XCTAssertTrue(run.advance(by: 0.05).isEmpty, "после финиша время стоит")
    }

    /// Тот, кто не уворачивается вовсе, теряет все сердечки быстро — заезд не тянется без игры.
    func testIdleDogLosesQuickly() {
        for seed in 0..<50 as Range<UInt64> {
            var run = RunnerRun(seed: seed, cfg: rCfg())
            while !run.isOver { run.advance(by: 1.0 / 60) }
            XCTAssertFalse(run.finished)
            XCTAssertEqual(run.lives, 0)
            XCTAssertEqual(run.hits, 3)
            XCTAssertLessThan(run.t, 60, "seed \(seed): без игры — меньше минуты")
        }
    }

    /// Автопилот (ближайшая свободная полоса + прыжок/подкат вовремя) добегает до финиша — трасса проходима и
    /// в реальной симуляции с подшагами, а не только по рядам.
    func testPilotFinishesManySeeds() {
        var hits = 0
        for seed in 0..<60 as Range<UInt64> {
            let run = Runner.autoplay(seed: seed &* 7919, rCfg())
            XCTAssertTrue(run.finished, "seed \(seed): упал на \(run.metres) м, \(run.t) с")
            hits += run.hits
        }
        XCTAssertLessThanOrEqual(hits, 6, "автопилот почти не спотыкается: \(hits)")
    }

    func testAutoplayIsDeterministic() {
        let a = Runner.autoplay(seed: 9, until: 45, rCfg())
        let b = Runner.autoplay(seed: 9, until: 45, rCfg())
        XCTAssertEqual(a.distance, b.distance)
        XCTAssertEqual(a.picked, b.picked)
        XCTAssertEqual(a.hits, b.hits)
        XCTAssertEqual(a.lane, b.lane)
        XCTAssertGreaterThan(a.picked, 0, "монеты собираются")
        XCTAssertEqual(a.score, a.metres + a.picked * rCfg().coinPoints)
    }

    // MARK: свайпы и столкновения

    func testSwipesLanesJumpAndSlide() {
        var run = RunnerRun(seed: 1, cfg: rCfg())
        XCTAssertEqual(run.lane, 1)
        run.swipe(.left); run.swipe(.left)
        XCTAssertEqual(run.lane, 0, "за край не уходит")
        run.advance(by: 0.05); run.advance(by: 0.05); run.advance(by: 0.05)
        XCTAssertEqual(run.x, 0, accuracy: 1e-9, "перебежка за 0,12 с")
        run.swipe(.right); run.swipe(.right); run.swipe(.right)
        XCTAssertEqual(run.lane, 2)

        run.swipe(.jump)
        XCTAssertTrue(run.jumping)
        run.advance(by: 0.05); run.advance(by: 0.05)
        XCTAssertGreaterThan(run.height, 0)
        let mid = run.height
        run.swipe(.jump)
        run.advance(by: 0.05)
        XCTAssertNotEqual(run.height, 0)
        XCTAssertTrue(run.height != mid, "второй прыжок в воздухе не начинается заново")
        run.swipe(.slide)
        XCTAssertFalse(run.jumping, "вниз в прыжке — сразу подкат")
        XCTAssertTrue(run.sliding)
        XCTAssertEqual(run.height, 0)
        for _ in 0..<15 { run.advance(by: 0.05) }
        XCTAssertFalse(run.sliding, "подкат кончается сам")
        run.swipe(.slide); run.swipe(.jump)
        XCTAssertTrue(run.jumping)
        XCTAssertFalse(run.sliding, "из подката можно прыгнуть")
        for _ in 0..<15 { run.advance(by: 0.05) }
        XCTAssertFalse(run.jumping)
    }

    func testAdvanceClampsLongFrames() {
        var run = RunnerRun(seed: 1, cfg: rCfg())
        run.advance(by: 5)
        XCTAssertEqual(run.t, 0.05, accuracy: 1e-9, "длинный кадр (фон, тормоз) режется до 0,05 с")
        XCTAssertTrue(run.advance(by: 0).isEmpty)
        XCTAssertTrue(run.advance(by: -1).isEmpty)
        XCTAssertEqual(run.t, 0.05, accuracy: 1e-9)
    }

    /// Ящик бьёт и в прыжке; лужу снимает прыжок; лавочку — подкат. После удара 1,2 с неуязвимости.
    func testCollisionsByDodgeKind() {
        let cfg = rCfg()
        // Ищем первый ряд с препятствием в средней полосе и проверяем каждый способ.
        func firstRow(where pred: (RunnerRow) -> Bool) -> (UInt64, RunnerRow)? {
            for seed in 0..<500 as Range<UInt64> {
                let run = RunnerRun(seed: seed, cfg: cfg)
                if let r = run.track.rows.first, pred(r) { return (seed, r) }
            }
            return nil
        }
        func runTo(_ seed: UInt64, _ row: RunnerRow, act: RunnerMove?) -> RunnerRun {
            var run = RunnerRun(seed: seed, cfg: cfg)
            var acted = false
            while run.distance < row.z + 2, !run.isOver {
                if let a = act, !acted, row.z - run.distance <= run.speed * 0.25 {
                    run.swipe(a)
                    acted = true
                }
                run.advance(by: 1.0 / 60)
            }
            return run
        }
        let crate = try? XCTUnwrap(firstRow { $0.lanes[1] == .crate })
        let jumpy = try? XCTUnwrap(firstRow { $0.lanes[1]?.dodge == .jump })
        let slidy = try? XCTUnwrap(firstRow { $0.lanes[1]?.dodge == .slide })
        if let (s, r) = crate {
            XCTAssertEqual(runTo(s, r, act: .jump).hits, 1, "ящик не перепрыгнуть")
            XCTAssertEqual(runTo(s, r, act: .slide).hits, 1, "и не проползти")
            let hit = runTo(s, r, act: nil)
            XCTAssertEqual(hit.lives, cfg.lives - 1)
            XCTAssertTrue(hit.isKnocked(r, lane: 1), "сбитое прячется")
        }
        if let (s, r) = jumpy {
            XCTAssertEqual(runTo(s, r, act: .jump).hits, 0, "\(r.lanes[1]!) перепрыгнули")
            XCTAssertEqual(runTo(s, r, act: nil).hits, 1)
        }
        if let (s, r) = slidy {
            XCTAssertEqual(runTo(s, r, act: .slide).hits, 0, "под \(r.lanes[1]!) проползли")
            XCTAssertEqual(runTo(s, r, act: .jump).hits, 1, "через лавочку/голубей не прыгают")
        }
    }

    func testHitGivesShortInvulnerabilityAndEvents() throws {
        let cfg = rCfg()
        var run = RunnerRun(seed: 3, cfg: cfg)
        var hit: RunnerEvent?
        var hitT = 0.0
        var biomes: [RunnerBiome] = []
        while !run.isOver, run.distance < 420 {
            let ev = run.advance(by: 1.0 / 60)
            for e in ev {
                if case .hit = e, hit == nil { hit = e; hitT = run.t; XCTAssertTrue(run.invulnerable) }
                if case .biome(let b) = e { biomes.append(b) }
            }
            if hit != nil, run.t < hitT + Runner.hurtSeconds - 0.02 { XCTAssertEqual(run.hits, 1) }
        }
        XCTAssertNotNil(hit)
        // Пилот добегает до смены мира — событие ровно одно.
        let far = Runner.autoplay(seed: 3, until: 70, cfg)
        XCTAssertGreaterThan(far.distance, 400)
        XCTAssertEqual(far.biome, .district)
        _ = biomes
    }

    func testCoinsAreCollectedOnce() {
        let cfg = rCfg()
        var run = RunnerRun(seed: 11, cfg: cfg)
        var pilot = Runner.Pilot()
        var seen = Set<Int>()
        while !run.isOver, run.t < 60 {
            pilot.step(&run)
            for e in run.advance(by: 1.0 / 60) {
                if case .coin(let c) = e {
                    XCTAssertFalse(seen.contains(c.index), "монета \(c.index) дважды")
                    seen.insert(c.index)
                    XCTAssertTrue(run.isTaken(c))
                }
            }
            XCTAssertTrue(run.coins().allSatisfy { !run.isTaken($0) }, "собранные экран не рисует")
        }
        XCTAssertEqual(seen.count, run.picked)
        XCTAssertGreaterThan(run.picked, 3)
    }

    func testVisibleWindowStaysSmall() {
        // Экран держит пул: видно не больше ~lookahead метров рядов и монет.
        var run = Runner.autoplay(seed: 2, until: 120, rCfg())
        let rows = run.rows()
        XCTAssertFalse(rows.isEmpty)
        XCTAssertLessThan(rows.count, 30, "в окне не больше пула")
        XCTAssertTrue(rows.allSatisfy { $0.z >= run.distance - 6 && $0.z <= run.distance + Runner.lookahead })
        XCTAssertLessThan(run.coins().count, 40)
        run.advance(by: 0.05)
        XCTAssertNotNil(run.nextRow)
        XCTAssertGreaterThan(run.nextRow!.z + run.nextRow!.span / 2 + Runner.dogHalf, run.distance)
    }

    // MARK: награда

    func testFinishPaysRecordAndPlay() {
        var f = rFile()
        let fun = f.pet.needs[.fun] ?? 0
        let run = Runner.autoplay(seed: 3, until: 90, rCfg())
        let c = rCfg(cap: 500, shared: 500)
        let r = Runner.finish(run, in: &f, now: rT0, c)
        XCTAssertEqual(r.score, run.score)
        XCTAssertEqual(r.metres, run.metres)
        XCTAssertEqual(r.picked, run.picked)
        XCTAssertEqual(r.coins, CatchGame.want(score: run.score, game: 1, c.asCatch))
        XCTAssertGreaterThan(r.coins, 0)
        XCTAssertTrue(r.isRecord)
        XCTAssertEqual(f.runnerBest, run.score)
        XCTAssertEqual(f.runnerGames, 1)
        XCTAssertEqual(f.runnerCoins, r.coins)
        XCTAssertTrue(r.played)
        XCTAssertGreaterThan(f.pet.needs[.fun] ?? 0, fun, "настроение — ядерным play")
        let worse = Runner.finish(score: 40, in: &f, now: rT0 + 60, c)
        XCTAssertFalse(worse.isRecord)
        XCTAssertEqual(worse.best, run.score)
        XCTAssertEqual(f.runnerGames, 2)
    }

    func testWantScalesToParAndDiminishes() {
        let c = rCfg().asCatch
        XCTAssertEqual(CatchGame.want(score: 0, game: 1, c), 0)
        XCTAssertEqual(CatchGame.want(score: 1500, game: 1, c), 35)
        XCTAssertEqual(CatchGame.want(score: 5000, game: 1, c), 35, "выше par — не больше max")
        XCTAssertLessThan(CatchGame.want(score: 1500, game: 7, c), 35)
        XCTAssertLessThan(CatchGame.want(score: 1500, game: 13, c), CatchGame.want(score: 1500, game: 7, c))
        // Полный заезд (3 мин) дотягивает до par, минутный — примерно половина.
        let full = Runner.autoplay(seed: 4, rCfg())
        XCTAssertGreaterThanOrEqual(full.score, 1500)
        let minute = Runner.autoplay(seed: 4, until: 60, rCfg())
        XCTAssertLessThan(minute.score, 1000)
    }

    func testOwnDailyCapAndNextDay() {
        var f = rFile()
        var total = 0
        for i in 0..<6 { total += Runner.finish(score: 1500, in: &f, now: rT0 + Double(i) * 60, rCfg(cap: 50, shared: 500)).coins }
        XCTAssertEqual(total, 50, "не больше своего потолка")
        XCTAssertEqual(Runner.coinsLeft(f, now: rT0 + 600, rCfg(cap: 50, shared: 500)), 0)
        let r = Runner.finish(score: 1500, in: &f, now: rT0 + 900, rCfg(cap: 50, shared: 500))
        XCTAssertEqual(r.coins, 0)
        XCTAssertTrue(r.capped)
        XCTAssertEqual(Runner.coinsLeft(f, now: rT0 + 86400, rCfg(cap: 50, shared: 500)), 50, "завтра снова")
    }

    /// Общий потолок мини-игр один: мячик и Блок Дуо его съели — раннеру не остаётся, и наоборот.
    func testSharedCapWithOtherGames() {
        var f = rFile()
        f.catchDay = DayKey.of(rT0)
        f.catchCoins = 30
        f.blockduoDay = DayKey.of(rT0)
        f.blockduoCoins = 20
        XCTAssertEqual(Runner.coinsLeft(f, now: rT0, rCfg()), 10)
        let r = Runner.finish(score: 1500, in: &f, now: rT0, rCfg())
        XCTAssertEqual(r.coins, 10)
        XCTAssertTrue(r.capped)
        XCTAssertEqual(MiniGames.coinsToday(f, now: rT0), 60)
        var cc = CatchConfig()
        cc.dailyCap = 60
        cc.sharedCap = 60
        XCTAssertEqual(CatchGame.coinsLeft(f, now: rT0, cc), 0, "мячик видит монеты раннера")
        // Вчерашнее не в счёт.
        var y = rFile()
        y.runnerDay = DayKey.of(rT0) - 1
        y.runnerCoins = 60
        XCTAssertEqual(MiniGames.coinsToday(y, now: rT0), 0)
        XCTAssertEqual(Runner.coinsLeft(y, now: rT0, rCfg()), 60)
    }

    /// Пёс занят (спит) — играть можно, но без наград: только рекорд, без монет, play и счётчика партий.
    func testBusyDogRunsForFunWithoutRewards() {
        var f = rFile()
        f.pet.napUntil = rT0 + 1800
        let busy = MiniGames.busy(f, at: rT0)
        XCTAssertEqual(busy, "asleep")
        let coins = f.econ.wallet.coins
        let fun = f.pet.needs[.fun]
        let r = Runner.finish(score: 900, in: &f, now: rT0, free: busy, rCfg())
        XCTAssertEqual(r.coins, 0)
        XCTAssertEqual(r.careCoins, 0)
        XCTAssertFalse(r.capped)
        XCTAssertFalse(r.played)
        XCTAssertEqual(r.free, "asleep")
        XCTAssertEqual(f.econ.wallet.coins, coins)
        XCTAssertEqual(f.pet.needs[.fun], fun)
        XCTAssertEqual(f.runnerGames, 0, "заезд просто так не съедает убывание")
        XCTAssertEqual(f.runnerCoins, 0)
        XCTAssertTrue(r.isRecord)
        XCTAssertEqual(f.runnerBest, 900, "рекорд — пишется")
        XCTAssertEqual(f.shardLog.best[MiniGame.runner.rawValue], 900)
        XCTAssertEqual(Runner.rewardText(r), MiniGames.freeReward)
    }

    func testZeroScoreCountsGameWithoutPlay() {
        var f = rFile()
        let fun = f.pet.needs[.fun]
        let r = Runner.finish(RunnerRun(seed: 1, cfg: rCfg()), in: &f, now: rT0, rCfg())
        XCTAssertEqual(r.coins, 0)
        XCTAssertFalse(r.played)
        XCTAssertFalse(r.isRecord)
        XCTAssertNil(Runner.rewardText(r))
        XCTAssertNil(Runner.toastText(r))
        XCTAssertEqual(f.pet.needs[.fun], fun)
        XCTAssertEqual(f.runnerGames, 1)
    }

    func testFinishAfterDeathPaysNothing() {
        var f = rFile()
        f.pet.alive = false
        let coins = f.econ.wallet.coins
        let r = Runner.finish(score: 700, in: &f, now: rT0, rCfg())
        XCTAssertEqual(r.totalCoins, 0)
        XCTAssertFalse(r.capped)
        XCTAssertEqual(f.econ.wallet.coins, coins)
        XCTAssertFalse(r.played)
        XCTAssertEqual(f.runnerBest, 700)
    }

    func testTexts() {
        var r = RunnerResult()
        XCTAssertEqual(Runner.resultTitle(r), "Даже не разбежались…")
        r.score = 300; r.metres = 280; r.best = 900
        XCTAssertEqual(Runner.resultTitle(r), "Ой, споткнулись!")
        r.finished = true
        XCTAssertEqual(Runner.resultTitle(r), "Финиш!")
        r.isRecord = true
        XCTAssertEqual(Runner.resultTitle(r), "Новый рекорд!")
        r.coins = 12; r.careCoins = 3
        XCTAssertEqual(Runner.rewardText(r), "+\(EconText.coins(15))")
        XCTAssertEqual(Runner.toastText(r), "Раннер: 280 м, +\(EconText.coins(15))")
        r.coins = 0; r.careCoins = 0; r.capped = true
        XCTAssertEqual(Runner.toastText(r), "Раннер: 280 м, на сегодня монет за игры хватит")
        // Фраза пса в комнате: рекорд — с метрами, иначе — по кругу, не пустая.
        XCTAssertTrue(Runner.shibaLine(r).contains("280 м"))
        r.isRecord = false
        XCTAssertTrue(Runner.shibaLine(r).hasPrefix("Добежали"))
        r.finished = false
        XCTAssertFalse(Runner.shibaLine(r).isEmpty)
        XCTAssertNotEqual(Runner.shibaLine(RunnerResult()), Runner.shibaLine(r))
        // VoiceOver: что впереди.
        let run = RunnerRun(seed: 1, cfg: rCfg())
        let ahead = Runner.ahead(run)
        XCTAssertTrue(ahead.hasPrefix("Впереди: "), ahead)
        XCTAssertTrue(RunnerObstacle.allCases.contains { ahead.contains($0.title) })
    }

    // MARK: реестр, челлендж, сейв, конфиг

    func testRegistryAndChallenge() {
        XCTAssertTrue(MiniGame.allCases.contains(.runner))
        XCTAssertEqual(MiniGame.runner.name, RunnerConfig.shared.name)
        XCTAssertEqual(MiniGame.runner.icon, "figure.run")
        var f = rFile()
        f.runnerBest = 777
        XCTAssertEqual(f[keyPath: MiniGame.runner.bestKey], 777)
        XCTAssertEqual(ChallengeConfig().base(.runner), 400)
        XCTAssertEqual(Challenges.goal(.runner, record: 0, ChallengeConfig()), 400)
        XCTAssertEqual(Challenges.goal(.runner, record: 2000, ChallengeConfig()), 1400)
        XCTAssertTrue(A11y.Game.allCases.contains(.runner))
        XCTAssertTrue(A11y.gameNote(.runner).contains("VoiceOver"))
        XCTAssertTrue(DeepLink.routes.contains("runner"))
    }

    func testSaveFieldsTopLevelAndOldSave() throws {
        var f = rFile()
        Runner.finish(score: 1234, in: &f, now: rT0, rCfg())
        let data = try JSONEncoder().encode(f)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((obj["runnerBest"] as? NSNumber)?.intValue, 1234, "рекорд — верхним уровнем")
        XCTAssertNotNil(obj["runnerDay"])
        XCTAssertNotNil(obj["runnerCoins"])
        let back = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(back.runnerBest, 1234)
        XCTAssertEqual(back.runnerDay, f.runnerDay)
        XCTAssertEqual(back.runnerCoins, f.runnerCoins)
        XCTAssertEqual(back.runnerGames, 1)

        // Старый сейв без полей — нули, остальное на месте.
        var plain = f
        plain.runnerBest = 0; plain.runnerDay = 0; plain.runnerCoins = 0; plain.runnerGames = 0
        let oldData = try JSONEncoder().encode(plain)
        for k in ["runnerBest", "runnerDay", "runnerCoins", "runnerGames"] {
            XCTAssertFalse(String(decoding: oldData, as: UTF8.self).contains("\"\(k)\""), "нули не пишутся: \(k)")
        }
        let oldFile = try JSONDecoder().decode(SaveFile.self, from: oldData)
        XCTAssertEqual(oldFile.runnerBest, 0)
        XCTAssertEqual(oldFile.petId, f.petId)
        XCTAssertEqual(oldFile.econ.wallet, f.econ.wallet)

        // Битое поле — ноль, а не весь сейв.
        let text = String(decoding: oldData, as: UTF8.self)
        let broken = "{\"runnerBest\":\"далеко\",\"runnerGames\":2," + text.dropFirst()
        let b = try JSONDecoder().decode(SaveFile.self, from: Data(broken.utf8))
        XCTAssertEqual(b.runnerBest, 0)
        XCTAssertEqual(b.runnerGames, 2)
        XCTAssertEqual(b.petId, f.petId)

        let fresh = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SaveFile.fresh(now: rT0))) as? [String: Any]
        XCTAssertNil(fresh?["runnerBest"])
        XCTAssertNil(fresh?["runnerGames"])
    }

    func testOldFixturesStillLoad() throws {
        // Сохранения всех прошлых эпох (Tests/Fixtures и Fixtures/upgrade) читаются, раннер в них нулевой,
        // и заезд на старом сейве пишется как на новом.
        let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        var seen = 0
        for dir in [base, base.appendingPathComponent("upgrade")] {
            let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
                .filter { $0.hasPrefix("save-") && $0.hasSuffix(".json") }.sorted()
            for name in names {
                var f = try JSONDecoder().decode(SaveFile.self, from: Data(contentsOf: dir.appendingPathComponent(name)))
                XCTAssertEqual(f.runnerBest, 0, name)
                XCTAssertEqual(f.runnerGames, 0, name)
                let now = Swift.max(f.pet.t, f.lastSeenT ?? 0) + 60
                let r = Runner.finish(score: 321, in: &f, now: now, rCfg())
                XCTAssertEqual(f.runnerBest, 321, name)
                XCTAssertEqual(r.best, 321, name)
                let again = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
                XCTAssertEqual(again.runnerBest, 321, name)
                seen += 1
            }
        }
        XCTAssertGreaterThanOrEqual(seen, 8)
    }

    func testStartOverKeepsRecordAndDailyCap() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-runner")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: rT0)
        try store.mutate { (f: inout SaveFile) -> Void in
            f.runnerBest = 1810
            f.runnerDay = DayKey.of(rT0)
            f.runnerCoins = 60
            f.runnerGames = 4
        }
        try store.startOver(now: rT0 + 100)
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.runnerBest, 1810, "рекорд хозяина остаётся")
        XCTAssertEqual(f.runnerCoins, 60, "новым щенком потолок не обнулить")
        XCTAssertEqual(f.runnerDay, DayKey.of(rT0))
        XCTAssertEqual(f.runnerGames, 4)
    }

    func testConfigFromEconomyJSON() throws {
        let d = RunnerConfig(json: .null)
        XCTAssertEqual(d.name, "Раннер")
        XCTAssertEqual(d.sharedCap, MiniGames.defaultSharedCap)
        XCTAssertEqual(d.maxSeconds, 180)

        let s = RunnerConfig.shared
        XCTAssertEqual(s.name, "Раннер")
        XCTAssertGreaterThan(s.base, 0)
        XCTAssertGreaterThanOrEqual(s.max, s.base)
        XCTAssertLessThanOrEqual(s.max, s.dailyCap, "один заезд не выбирает больше дневного потолка")
        XCTAssertEqual(s.sharedCap, CatchConfig.shared.sharedCap, "общий потолок один на все игры")
        XCTAssertEqual(s.diminishing, CatchConfig.shared.diminishing, "убывание общее")
        XCTAssertEqual(s.asCatch.parScore, s.parScore)
        XCTAssertGreaterThanOrEqual(s.maxSeconds, 60)
        XCTAssertLessThanOrEqual(s.maxSeconds, 180, "заезд — до трёх минут")
        XCTAssertLessThan(s.speedMin, s.speedMax)

        let raw = #"{"minigames": {"daily_cap": 80, "list": {"runner": {"base": 4, "max": 2, "max_seconds": 10, "speed_min": 9, "speed_max": 5, "biome_m": 250}}}}"#
        let c = RunnerConfig(json: try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)))
        XCTAssertEqual(c.base, 4)
        XCTAssertEqual(c.max, 4, "max не меньше base")
        XCTAssertEqual(c.maxSeconds, 30, "заезд не короче 30 с")
        XCTAssertEqual(c.speedMax, 9, "скорость не падает")
        XCTAssertEqual(c.biomeMetres, 250)
        XCTAssertEqual(c.sharedCap, 80)
    }
}
