// Отклик на касание (волна 29): виды, сила, кулдауны, настройки, фон и тишина после фона — без UIKit.
// Идёт и на Linux (app/Package.swift), и в app.yml.

import Foundation
import XCTest
@testable import Pet

final class FeelTests: XCTestCase {
    // MARK: виды и сила

    func testCooldownsAreShortAndOrdered() {
        for k in FeelKind.allCases {
            XCTAssertGreaterThan(k.cooldown, 0, "\(k)")
            XCTAssertLessThanOrEqual(k.cooldown, 0.6, "\(k): отклик не должен глохнуть надолго")
        }
        // Частые касания (выбор, ласка) пропускаются чаще, чем успех и отказ.
        XCTAssertLessThan(FeelKind.select.cooldown, FeelKind.tap.cooldown)
        XCTAssertLessThan(FeelKind.soft.cooldown, FeelKind.success.cooldown)
        XCTAssertLessThan(FeelKind.success.cooldown, FeelKind.denied.cooldown)
    }

    func testRanks() {
        XCTAssertEqual(FeelKind.select.rank, 0)
        XCTAssertEqual(FeelKind.tap.rank, FeelKind.soft.rank)
        XCTAssertEqual(FeelKind.bump.rank, FeelKind.nudge.rank)
        XCTAssertEqual(FeelKind.success.rank, FeelKind.denied.rank)
        XCTAssertLessThan(FeelKind.soft.rank, FeelKind.bump.rank)
        XCTAssertLessThan(FeelKind.nudge.rank, FeelKind.success.rank)
    }

    func testStrongest() {
        XCTAssertEqual(FeelKind.strongest(nil, .tap), .tap)
        XCTAssertEqual(FeelKind.strongest(.tap, .bump), .bump)
        XCTAssertEqual(FeelKind.strongest(.success, .tap), .success)
        // Равные — новый.
        XCTAssertEqual(FeelKind.strongest(.bump, .nudge), .nudge)
        XCTAssertEqual(FeelKind.strongest(.nudge, .bump), .bump)
        // Свёртка кадра игры: один, самый сильный.
        let frame: [FeelKind] = [.tap, .tap, .nudge, .tap]
        XCTAssertEqual(frame.reduce(nil as FeelKind?) { FeelKind.strongest($0, $1) }, .nudge)
    }

    func testSoundKeys() {
        XCTAssertEqual(SoundCue.petTick(1).feelKey, SoundCue.petTick(30).feelKey)
        XCTAssertNotEqual(SoundCue.boop.feelKey, SoundCue.yip.feelKey)
        XCTAssertNotEqual(SoundCue.hearts.feelKey, SoundCue.heartLost.feelKey)
        let keys = Set(SoundTests.allCues.map(\.feelKey))
        // 18 сигналов, из них три тика ласки — один ключ.
        XCTAssertEqual(keys.count, SoundTests.allCues.count - 2)
    }

    // MARK: кулдаун

    func testSameKindCooldown() {
        var g = FeelGate()
        for k in FeelKind.allCases {
            let t0 = 1000 * Double(FeelKind.allCases.firstIndex(of: k)!)
            XCTAssertTrue(g.allowHaptic(k, at: t0), "\(k) первый")
            XCTAssertFalse(g.allowHaptic(k, at: t0 + k.cooldown * 0.5), "\(k) в кулдауне")
            XCTAssertTrue(g.allowHaptic(k, at: t0 + k.cooldown + 0.001), "\(k) после кулдауна")
        }
    }

    func testCooldownIsPerKind() {
        var g = FeelGate()
        XCTAssertTrue(g.allowHaptic(.denied, at: 10))
        // Другой вид после кадра — пропускается, хотя denied ещё в кулдауне.
        XCTAssertTrue(g.allowHaptic(.tap, at: 10.1))
        XCTAssertFalse(g.allowHaptic(.denied, at: 10.3))
        XCTAssertTrue(g.allowHaptic(.denied, at: 10.7))
    }

    func testRefusedHapticDoesNotRestartCooldown() {
        var g = FeelGate()
        XCTAssertTrue(g.allowHaptic(.success, at: 0))
        XCTAssertFalse(g.allowHaptic(.success, at: 0.3))
        // Отсчёт — от прошедшего отклика (0), а не от отброшенного (0.3).
        XCTAssertTrue(g.allowHaptic(.success, at: 0.41))
    }

    func testSameFrameWeakerDropped() {
        var g = FeelGate()
        XCTAssertTrue(g.allowHaptic(.success, at: 5))
        XCTAssertFalse(g.allowHaptic(.tap, at: 5.01), "слабый сразу после сильного")
        XCTAssertFalse(g.allowHaptic(.denied, at: 5.02), "равный в том же кадре")
        XCTAssertTrue(g.allowHaptic(.tap, at: 5.06), "после кадра — можно")
    }

    func testSameFrameStrongerPasses() {
        var g = FeelGate()
        XCTAssertTrue(g.allowHaptic(.tap, at: 5))
        XCTAssertTrue(g.allowHaptic(.success, at: 5.01), "сильный после слабого не теряется")
        g = FeelGate()
        XCTAssertTrue(g.allowHaptic(.select, at: 1))
        XCTAssertTrue(g.allowHaptic(.soft, at: 1.01))
    }

    func testRapidPettingThrottled() {
        var g = FeelGate()
        // Тики ласки каждые 30 мс в течение секунды: пропускается не чаще раза в кулдаун.
        var passed = 0
        for i in 0..<34 where g.allowHaptic(.soft, at: Double(i) * 0.03) { passed += 1 }
        XCTAssertGreaterThan(passed, 5)
        XCTAssertLessThanOrEqual(passed, Int(1 / FeelKind.soft.cooldown) + 1)
    }

    func testSoundCooldown() {
        var g = FeelGate()
        XCTAssertTrue(g.allowSound(.boop, at: 1))
        XCTAssertFalse(g.allowSound(.boop, at: 1.03), "двойной вызов того же звука")
        XCTAssertTrue(g.allowSound(.yip, at: 1.03), "другой звук — свой ключ")
        XCTAssertTrue(g.allowSound(.boop, at: 1 + FeelGate.soundCooldown + 0.001))
        // Тики ласки делят ключ.
        XCTAssertTrue(g.allowSound(.petTick(1), at: 3))
        XCTAssertFalse(g.allowSound(.petTick(2), at: 3.02))
        XCTAssertTrue(g.allowSound(.petTick(3), at: 3.1))
    }

    func testSoundAndHapticIndependent() {
        var g = FeelGate()
        XCTAssertTrue(g.allowHaptic(.success, at: 1))
        XCTAssertTrue(g.allowSound(.ok, at: 1), "звук того же события не глушится вибрацией")
    }

    // MARK: настройки

    func testHapticsOff() {
        var g = FeelGate()
        g.haptics = false
        for k in FeelKind.allCases { XCTAssertFalse(g.allowHaptic(k, at: Double(k.rank) * 10), "\(k)") }
        XCTAssertTrue(g.allowSound(.ok, at: 0), "звук живёт без вибрации")
        // Выключенная вибрация не оставляет следа в кулдауне.
        g.haptics = true
        XCTAssertTrue(g.allowHaptic(.success, at: 0))
    }

    func testSoundOff() {
        var g = FeelGate()
        g.sound = false
        XCTAssertFalse(g.allowSound(.ok, at: 0))
        XCTAssertFalse(g.allowSound(.refuse, at: 1))
        XCTAssertTrue(g.allowHaptic(.denied, at: 1), "вибрация живёт без звука")
        g.sound = true
        XCTAssertTrue(g.allowSound(.ok, at: 0.01))
    }

    func testSettingsKeys() {
        XCTAssertEqual(FeelGate.soundKey, "sound.on", "ключ старого переключателя «Звук»")
        XCTAssertNotEqual(FeelGate.hapticsKey, FeelGate.soundKey)
    }

    func testEnabledDefaultsToOn() throws {
        let suite = "feel.tests.\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertTrue(FeelGate.enabled(FeelGate.soundKey, in: d))
        XCTAssertTrue(FeelGate.enabled(FeelGate.hapticsKey, in: d))
        d.set(false, forKey: FeelGate.hapticsKey)
        XCTAssertFalse(FeelGate.enabled(FeelGate.hapticsKey, in: d))
        XCTAssertTrue(FeelGate.enabled(FeelGate.soundKey, in: d))
        d.set(false, forKey: FeelGate.soundKey)
        XCTAssertFalse(FeelGate.enabled(FeelGate.soundKey, in: d))
        d.set(true, forKey: FeelGate.soundKey)
        XCTAssertTrue(FeelGate.enabled(FeelGate.soundKey, in: d))
    }

    // MARK: фон

    func testBackgroundSilencesEverything() {
        var g = FeelGate()
        g.wentBackground()
        XCTAssertFalse(g.active)
        for k in FeelKind.allCases { XCTAssertFalse(g.allowHaptic(k, at: Double(k.rank)), "\(k)") }
        XCTAssertFalse(g.allowSound(.hearts, at: 0))
        XCTAssertFalse(g.allowSound(.ok, at: 0, ambient: true))
        g.becameActive(at: 100)
        XCTAssertTrue(g.active)
        XCTAssertTrue(g.allowHaptic(.tap, at: 100.1), "палец сразу после возврата — отклик есть")
        XCTAssertTrue(g.allowSound(.boop, at: 100.1))
    }

    func testWakeQuietOnlyForAmbient() {
        var g = FeelGate()
        XCTAssertFalse(g.quietAfterWake(at: 0), "без возврата из фона тишины нет")
        g.wentBackground()
        g.becameActive(at: 50)
        XCTAssertTrue(g.quietAfterWake(at: 51))
        XCTAssertFalse(g.allowSound(.hearts, at: 51, ambient: true))
        XCTAssertFalse(g.allowHaptic(.success, at: 51, ambient: true))
        XCTAssertTrue(g.allowHaptic(.success, at: 51, ambient: false), "от пальца — не глушим")
        XCTAssertTrue(g.allowSound(.ok, at: 51, ambient: false))
        XCTAssertFalse(g.quietAfterWake(at: 50 + FeelGate.wakeQuiet))
        XCTAssertTrue(g.allowSound(.hearts, at: 52.5, ambient: true))
        XCTAssertTrue(g.allowHaptic(.success, at: 52.5, ambient: true))
    }

    // MARK: звук итога действия

    func testActionOutcomeSounds() {
        // settle: ok и отказ — разные звуки; отказ всегда «не-а», а не тишина.
        for kind in ["feed", "pet", "play", "bath", "sleep", "wake", "nap"] {
            XCTAssertEqual(SoundRecipe.forAction(kind: kind, ok: false), .refuse, kind)
        }
        XCTAssertNotEqual(SoundRecipe.forAction(kind: "feed", ok: true), .refuse)
    }
}
