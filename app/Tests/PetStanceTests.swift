// Логика поз Шибы: положения, переходы, реакции, контракт имён клипов и пружины «сока».
// Без RealityKit-сцены: проверяем то, что решает, какие клипы играть, а не сам рендер.

import Foundation
import XCTest
@testable import Pet
#if canImport(PetCore)
import PetCore
#endif

final class PetStanceTests: XCTestCase {
    // MARK: поза → положение

    func testStanceForAllPoses() {
        for pose in Pose.allCases {
            let s = PetStance.stance(for: pose)
            XCTAssertTrue(Stance.allCases.contains(s), "\(pose)")
            XCTAssertFalse(PetStance.loop(for: pose).isEmpty, "\(pose)")
        }
        XCTAssertEqual(PetStance.stance(for: .dead), .dead)
        XCTAssertEqual(PetStance.stance(for: .sleep), .sleep)
        XCTAssertEqual(PetStance.stance(for: .nap), .sleep)
        XCTAssertEqual(PetStance.stance(for: .critical), .lie)
        XCTAssertEqual(PetStance.stance(for: .dirty), .sit)
        XCTAssertEqual(PetStance.stance(for: .idle), .stand)
        XCTAssertEqual(PetStance.loop(for: .dead), "death")
    }

    // MARK: переходы

    func testAllPathPairs() {
        var pairs = 0
        for a in Stance.allCases {
            for b in Stance.allCases {
                pairs += 1
                let path = PetStance.path(from: a, to: b)
                if a == b {
                    XCTAssertEqual(path, [], "\(a)→\(b)")
                    continue
                }
                if b == .dead {
                    XCTAssertEqual(path.last, "death", "\(a)→\(b)")
                    continue
                }
                if a == .dead {
                    XCTAssertEqual(path, [], "\(a)→\(b)")
                    continue
                }
                // Переход реально приводит тело в b и состоит из клипов, которые есть в контракте.
                XCTAssertFalse(path.isEmpty, "\(a)→\(b)")
                XCTAssertEqual(PetStance.endStance(after: path, from: a), b, "\(a)→\(b): \(path)")
                for clip in path {
                    XCTAssertTrue(PetClipNames.required.contains(clip), "\(a)→\(b): \(clip)")
                }
            }
        }
        XCTAssertEqual(pairs, 25)
        XCTAssertEqual(PetStance.path(from: .sleep, to: .stand), ["sleep_out", "lie_out"])
        XCTAssertEqual(PetStance.path(from: .stand, to: .sleep), ["lie_in", "sleep_in"])
        XCTAssertEqual(PetStance.path(from: .sit, to: .stand), ["sit_out"])
    }

    func testPickFiltersMissingClips() {
        let available: Set<String> = ["idle", "eat"]
        XCTAssertEqual(PetStance.pick(["eat", "hop", "idle", "yawn"], available: available), ["eat", "idle"])
        XCTAssertEqual(PetStance.pick(["hop"], available: available), [])
        XCTAssertEqual(PetStance.pick([], available: available), [])
    }

    // MARK: реакции

    func testReactions() {
        let all = Set(PetClipNames.required + PetClipNames.optional)
        XCTAssertEqual(PetStance.reaction(kind: "feed", ok: true, stance: .stand), ["eat", "eat", "eat"])

        for _ in 0..<20 {
            let pet = PetStance.reaction(kind: "pet", ok: true, stance: .stand, available: all)
            XCTAssertTrue(pet.first == "hit_left" || pet.first == "hit_right", "\(pet)")
        }
        // Без optional-клипов happy_wag выпадает, удар остаётся.
        let petRequired = PetStance.reaction(kind: "pet", ok: true, stance: .stand)
        XCTAssertTrue(petRequired == ["hit_left"] || petRequired == ["hit_right"], "\(petRequired)")
        XCTAssertEqual(PetStance.reaction(kind: "pet", ok: true, stance: .stand, lookX: -1).first, "hit_left")
        XCTAssertEqual(PetStance.reaction(kind: "pet", ok: true, stance: .stand, lookX: 1).first, "hit_right")

        // Отказ во сне — без движения; мёртвый не реагирует.
        XCTAssertEqual(PetStance.reaction(kind: "feed", ok: false, stance: .sleep, available: all), [])
        XCTAssertEqual(PetStance.reaction(kind: "pet", ok: true, stance: .dead, available: all), [])

        // Разбудили: из сна встаёт, и тело кончает стоя.
        let wake = PetStance.reaction(kind: "wake", ok: true, stance: .sleep)
        XCTAssertEqual(wake, ["sleep_out", "lie_out"])
        XCTAssertEqual(PetStance.endStance(after: wake, from: .sleep), .stand)

        // Без hop/play_bow игра — прыжок из контракта.
        XCTAssertEqual(PetStance.reaction(kind: "play", ok: true, stance: .stand), ["jump_to_idle"])
    }

    // MARK: контракт с shiba.clips.json

    func testBundledClipsCoverContract() throws {
        guard let table = ClipTable.shared else {
            throw XCTSkip("shiba.clips.json нет в бандле — сцена играет заглушку или весь таймлайн")
        }
        let have = Set(table.clips.keys)
        for name in PetClipNames.required {
            XCTAssertTrue(have.contains(name), "нет клипа \(name)")
        }
        for (name, clip) in table.clips {
            XCTAssertLessThan(clip.start, clip.end, name)
        }
        XCTAssertEqual(table.clips["death"]?.loop, false)
        XCTAssertEqual(table.clips["idle"]?.loop, true)

        for a in Stance.allCases {
            for b in Stance.allCases {
                for clip in PetStance.path(from: a, to: b) {
                    XCTAssertTrue(have.contains(clip), "\(a)→\(b): нет \(clip)")
                }
            }
            XCTAssertTrue(have.contains(PetStance.restLoop(for: a)), "\(a)")
        }
        for pose in Pose.allCases {
            XCTAssertTrue(have.contains(PetStance.loop(for: pose)), "\(pose)")
            for clip in PetStance.intro(for: pose) {
                XCTAssertTrue(have.contains(clip), "\(pose): нет \(clip)")
            }
        }
        // Реакции с клипами из контракта ссылаются только на то, что есть в бандле.
        for kind in ["feed", "item", "pet", "play", "wake", "bath"] {
            for stance in Stance.allCases {
                for ok in [true, false] {
                    for clip in PetStance.reaction(kind: kind, ok: ok, stance: stance) {
                        XCTAssertTrue(have.contains(clip), "\(kind)/\(stance): нет \(clip)")
                    }
                }
            }
        }
    }

    // MARK: пружины

    func testSpringConvergesWithSmallOvershoot() {
        let dt: Float = 1.0 / 60.0
        var x: Float = 1, v: Float = 0
        var lowest: Float = 1
        for _ in 0..<60 {
            (x, v) = PetSpring.step(x: x, v: v, target: 0, omega: JuiceComponent.omega,
                                    zeta: JuiceComponent.squashZeta, dt: dt)
            lowest = min(lowest, x)
        }
        XCTAssertLessThan(abs(x), 1e-3)
        XCTAssertGreaterThanOrEqual(lowest, -0.2, "перелёт больше 20%")

        // Поворот (ζ 0.8) тоже доходит до цели за секунду.
        var y: Float = 0, yv: Float = 0
        for _ in 0..<60 {
            (y, yv) = PetSpring.step(x: y, v: yv, target: 0.35, omega: JuiceComponent.omega,
                                     zeta: JuiceComponent.yawZeta, dt: dt)
        }
        XCTAssertEqual(y, 0.35, accuracy: 1e-3)
    }

    func testSpringImpulseReachesPeak() {
        let dt: Float = 1.0 / 240.0
        let w = JuiceComponent.omega, z = JuiceComponent.squashZeta
        var x: Float = 0
        var v = PetSpring.impulse(peak: -0.12, omega: w, zeta: z)
        var lowest: Float = 0
        for _ in 0..<240 {
            (x, v) = PetSpring.step(x: x, v: v, target: 0, omega: w, zeta: z, dt: dt)
            lowest = min(lowest, x)
        }
        XCTAssertEqual(lowest, -0.12, accuracy: 0.005)
        XCTAssertLessThan(abs(x), 1e-3)
    }
}
