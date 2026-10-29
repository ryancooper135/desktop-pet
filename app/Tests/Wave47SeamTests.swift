// Волна 47 S: охота на баги на стыках волн 44–46 (поход домой шагом × игра/обложка, просьба × островок).
// Каждый тест — найденный баг (DECISIONS.md, «Волна 47 S»). Гоняется и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private typealias K = RoomPlan.Keep

/// Номинальные длины клипов Шибы, с (как в GaitTests).
private let clipLen: [String: Double] = [
    "idle": 3.33, "walk": 1.08, "sit_in": 0.75, "sit": 3.0, "sit_out": 0.58, "lie_in": 1.08, "lie": 3.0,
    "lie_out": 0.92, "shake": 0.92, "hop": 0.5, "play_bow": 1.42, "idle_wag": 2.0, "head_tilt": 1.21,
    "sniff": 1.5, "look_l": 1.58, "look_r": 1.58, "yawn": 1.79,
]
private func len(_ s: String) -> Double { clipLen[s] ?? 1 }

private func scene() -> IdleScene {
    var n: [Need: Double] = [:]
    for k in Need.allCases { n[k] = 90 }
    return IdleScene(petId: "w47s-pet", name: "Шиба", pose: .idle, needs: n,
                     levels: RoomPlan.Levels(bath: 1, bed: 1, kitchen: 1), traits: [], quiet: false, alive: true,
                     tzOffsetMin: 0)
}

/// Местный полдень рядом с 1_760_000_000.
private let sT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

/// Пёс с закреплённым petId: всё по 90, энергия — energy.
private func sFile(energy: Double = 90, _ id: String = "w47s-pet", at t: Double = sT0) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = id
    for n in Need.allCases { f.pet.needs[n] = 90 }
    f.pet.needs[.energy] = energy
    DogLevel.settle(&f, now: t)
    return f
}

/// Сегодня — ровно одна просьба kind со стартом start.
private func sForce(_ f: inout SaveFile, _ kind: String, start: Double, coins: Int = 10) {
    DogAsks.settle(&f, now: start)
    f.asks.items = [DogAsk(start: start, kind: kind, coins: coins)]
}

final class Wave47SeamTests: XCTestCase {

    override func setUp() {
        super.setUp()
        DogAsks.enabled = true
        DailyTasks.enabled = true
    }

    override func tearDown() {
        Clock.zoneOverride = nil
        DogAsks.enabled = true
        DailyTasks.enabled = true
        super.tearDown()
    }

    // MARK: Баг 1 — «Поиграть» посреди дела: пёс съезжал домой за долю секунды, лапы шагали на месте

    /// Пока пёс идёт домой перед игрой (homing-дело + отложенная игра), телом правит дело, а не игра.
    /// Раньше ветка игры забирала тело сразу: ChoreoPath.pet(u<0) — это дом, и пёс съезжал туда за 0,35 с.
    func testHomingLeadsUntilPlayStarts() {
        // Идёт домой, игра начнётся через 3 с — ведёт дело.
        XCTAssertEqual(DogIdle.lead(now: 10, playStart: 13, walking: false, chore: true, homing: true), .chore)
        // Игра началась — ведёт игра.
        XCTAssertEqual(DogIdle.lead(now: 13, playStart: 13, walking: false, chore: true, homing: true), .play)
        XCTAssertEqual(DogIdle.lead(now: 14, playStart: 13, walking: false, chore: true, homing: true), .play)
        // Обычное дело (не путь домой) и прогулку игра перебивает сразу, как и раньше.
        XCTAssertEqual(DogIdle.lead(now: 10, playStart: 13, walking: false, chore: true, homing: false), .play)
        XCTAssertEqual(DogIdle.lead(now: 10, playStart: 13, walking: true, chore: false, homing: false), .play)
        // Без игры: прогулка, дело, ничего.
        XCTAssertEqual(DogIdle.lead(now: 10, playStart: nil, walking: true, chore: true, homing: true), .walk)
        XCTAssertEqual(DogIdle.lead(now: 10, playStart: nil, walking: false, chore: true, homing: true), .chore)
        XCTAssertEqual(DogIdle.lead(now: 10, playStart: nil, walking: false, chore: false, homing: false), .none)
    }

    /// Путь домой укладывается в клипы, после которых стартует игра: к play_bow пёс уже дома, в доме yaw3q.
    /// А посреди пути он не дома — если бы телом правила игра (дом), был бы скачок.
    func testHomeTripEndsBeforeDeferredPlay() {
        var checked = 0
        for s in [DogIdle.Stance.stand, .sit, .lie] {
            for c in IdleChore.allCases {
                guard let p = DogIdle.plan(c, scene(), stance: s, weather: .clear, roll: 0.5) else { continue }
                let r = IdleRoute.make(p, act: p.act(len), size: 1)
                let u = r.arriveAt + 0.01
                let at = r.pose(at: u)
                guard at.p.length > 0.3 else { continue }
                let cues = DogIdle.cues(p, r, homeLoop: "idle", len: len)
                let stance = DogIdle.stance(at: u, cues, home: p.home, len: len)
                let trip = DogIdle.homeTrip(from: at.p, yaw: at.yaw, stance: stance, home: p.home, size: 1,
                                            chore: p.chore, len: len)
                let tag = "\(c) \(s)"
                let clips = trip.steps.reduce(0.0) { $0 + len($1) }
                // Игра стартует после всех клипов пути — тело к тому времени дома.
                XCTAssertLessThanOrEqual(trip.route.homeAt, clips + 0.02 * len("walk"), tag)
                let z = trip.route.pose(at: max(clips, trip.route.homeAt))
                XCTAssertLessThan(z.p.length, 1e-3, tag)
                XCTAssertEqual(sin(z.yaw), sin(K.yaw3q), accuracy: 1e-4, tag)
                XCTAssertEqual(cos(z.yaw), cos(K.yaw3q), accuracy: 1e-4, tag)
                // Через 0,35 с после «Поиграть» пёс ещё далеко от дома: ведёт дело, не игра.
                XCTAssertGreaterThan(trip.route.pose(at: 0.35).p.length, 0.2, tag)
                XCTAssertEqual(DogIdle.lead(now: 0.35, playStart: clips, walking: false, chore: true, homing: true),
                               .chore, tag)
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0, "есть дела вдали от дома")
    }

    // MARK: Баг 3 — обложка закрылась посреди дела/пути домой: тело шло, лапы стояли в idle

    /// После обложки клипы продолжаются с того места дела, где пёс сейчас, а не циклом дома.
    func testResumeClipsAfterCover() {
        let cues = [IdleCue(at: 0, steps: [], loop: "walk"),
                    IdleCue(at: 2, steps: ["sniff", "look_l"], loop: "idle_wag"),
                    IdleCue(at: 10, steps: ["walk"], loop: "")]
        func r(_ u: Double) -> (steps: [String], loop: String) {
            DogIdle.resume(at: u, cues, homeLoop: "idle", len: len)
        }
        // До первой реплики — дома.
        XCTAssertEqual(r(-1).steps, [])
        XCTAssertEqual(r(-1).loop, "idle")
        // Идёт к месту — цикл шага, а не стойка.
        XCTAssertEqual(r(1).steps, [])
        XCTAssertEqual(r(1).loop, "walk")
        // У дела: середина клипа впереди — играем его целиком; середина прошла — следующий.
        XCTAssertEqual(r(2.5).steps, ["sniff", "look_l"])
        XCTAssertEqual(r(3.0).steps, ["look_l"])
        XCTAssertEqual(r(3.0).loop, "idle_wag")
        XCTAssertEqual(r(9).steps, [])
        // Пустой цикл реплики — цикл дома.
        XCTAssertEqual(r(10.2).steps, ["walk"])
        XCTAssertEqual(r(10.2).loop, "idle")
    }

    /// Путь домой (одна реплика с шагами, loop ""): посреди пути — оставшиеся шаги, потом цикл дома.
    func testResumeHomingTrip() {
        let trip = IdleCue(at: 0, steps: ["sit_out", "walk", "walk", "walk"], loop: "")
        let r = DogIdle.resume(at: 2.0, [trip], homeLoop: "sit", len: len)
        // sit_out 0–0,58 и walk 0,58–1,66 позади; walk 1,66–2,74 — середина 2,2 впереди.
        XCTAssertEqual(r.steps, ["walk", "walk"])
        XCTAssertEqual(r.loop, "sit")
        let done = DogIdle.resume(at: 100, [trip], homeLoop: "sit", len: len)
        XCTAssertEqual(done.steps, [])
        XCTAssertEqual(done.loop, "sit")
    }

    // MARK: Баг 2 — островок держал просьбу над задремавшим псом

    /// Пёс с энергией чуть выше порога дрёмы: в окне просьбы он задремлет. Островок, поставленный при уходе
    /// в фон, должен сменить вид в эту минуту (staleDate), как кадр виджета и плашка дома. Раньше — до конца окна.
    func testIslandAskHidesWhenDogNaps() {
        var f = sFile(energy: 16)
        let start = sT0 - 600
        sForce(&f, "pet", start: start)
        XCTAssertNotNil(DogAsks.shown(f, now: sT0), "бодрствует — просьба видна")
        let end = start + DogAskConfig.shared.window

        var napAt: Double?
        var t = sT0
        while t < end {
            t += 60
            if PetRunner.peek(f, at: t).napUntil != nil { napAt = t; break }
        }
        guard let nap = napAt else { return XCTFail("пёс должен задремать в окне просьбы") }

        guard let ask = IslandFeed.ask(f, now: sT0) else { return XCTFail("островок видит просьбу") }
        guard let hide = ask.hideAt else { return XCTFail("островок не знает, когда пёс задремлет") }
        XCTAssertEqual(hide, nap, accuracy: 60)
        XCTAssertEqual(ask.end, end, "таймер окна прежний")
        XCTAssertNil(DogAsks.shown(f, now: hide + 60), "дом в эту минуту просьбу уже не показывает")

        let show = IslandEvents.show(IslandFeed.input(f, now: sT0))
        XCTAssertEqual(show.current?.kind, .ask)
        guard let stale = show.staleDate else { return XCTFail("у островка нет смены вида") }
        XCTAssertLessThanOrEqual(stale, hide + 1e-6, "островок сменит вид не позже, чем пёс задремлет")
        XCTAssertNotEqual(show.after?.kind, .ask)

        // Виджет в те же минуты — без просьбы.
        let frames = IslandEvents.widget(f, now: sT0, asks: f.asks.items)
        XCTAssertNotNil(frames.first?.ask)
        for fr in frames where fr.t >= hide + 60 && fr.t < end {
            XCTAssertNil(fr.ask, "кадр +\(Int(fr.t - sT0)) с: пёс дремлет")
        }
    }

    /// Бодрый пёс днём: просьба на островке до конца окна, края нет.
    func testIslandAskStaysForAwakeDog() {
        var f = sFile()
        sForce(&f, "pet", start: sT0 - 600)
        guard let ask = IslandFeed.ask(f, now: sT0) else { return XCTFail("островок видит просьбу") }
        XCTAssertNil(ask.hideAt)
        XCTAssertEqual(ask.shownUntil, ask.end)
    }
}
