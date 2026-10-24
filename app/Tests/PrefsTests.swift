// Волна 32: переключатели «Звук и отклик», голос пса (тявк / редкое рычание), музыка мини-игр,
// выключение уведомлений. Без UIKit — идёт и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet

final class PrefsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "PrefsTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: переключатели

    func testKeysMatchFeelAndSound() {
        XCTAssertEqual(PetPref.sound.key, FeelGate.soundKey)
        XCTAssertEqual(PetPref.haptics.key, FeelGate.hapticsKey)
        XCTAssertEqual(Set(PetPref.allCases.map(\.key)).count, PetPref.allCases.count)
        XCTAssertEqual(Set(PetPref.allCases.map(\.id)).count, PetPref.allCases.count)
        XCTAssertEqual(PetPref.sound.id, "settings.sound", "id из прошлых UI-тестов")
    }

    func testEverythingOnByDefaultAndRemembers() {
        let d = freshDefaults()
        for p in PetPref.allCases {
            XCTAssertTrue(p.isOn(in: d), "\(p)")
            p.set(false, in: d)
            XCTAssertFalse(p.isOn(in: d), "\(p)")
            XCTAssertFalse(FeelGate.enabled(p.key, in: d))
        }
    }

    func testTitlesShortAndRussian() {
        for p in PetPref.allCases {
            XCTAssertFalse(p.title.isEmpty)
            XCTAssertLessThanOrEqual(p.title.count, 14, p.title)
            XCTAssertNil(p.title.range(of: "[A-Za-z]", options: .regularExpression), p.title)
            if let f = p.footer { XCTAssertLessThanOrEqual(f.count, 70, f) }
        }
        XCTAssertTrue(PetPref.voice.needsSound)
        XCTAssertFalse(PetPref.music.needsSound, "музыка — отдельно от звуков")
    }

    // MARK: уведомления

    func testNotificationsOffPlansNothing() {
        let note = PlannedNote(id: "pet.need.1", date: Date(timeIntervalSince1970: 0), title: "t", body: "b",
                               category: "pet.need", priority: 3, trigger: "x")
        XCTAssertEqual(NotifPref.notes([note], on: true), [note])
        XCTAssertEqual(NotifPref.notes([note], on: false), [])
    }

    func testNotificationFooter() {
        XCTAssertTrue(NotifPref.needsSystemSettings(on: true, permission: .denied))
        XCTAssertFalse(NotifPref.needsSystemSettings(on: false, permission: .denied))
        XCTAssertFalse(NotifPref.needsSystemSettings(on: true, permission: .allowed))
        var seen = Set<String>()
        for on in [true, false] {
            for p in [NotifPermission.allowed, .denied, .notAsked] {
                let f = NotifPref.footer(on: on, permission: p)
                XCTAssertFalse(f.isEmpty)
                XCTAssertLessThanOrEqual(f.count, 70, f)
                seen.insert(f)
            }
        }
        XCTAssertEqual(seen.count, 4, "выключено — одна фраза, включено — по одной на разрешение")
    }

    // MARK: голос пса

    func testVoiceOffDropsDogSounds() {
        XCTAssertEqual(SoundRecipe.tones(.yip, voice: false), SoundRecipe.tones(.ok))
        XCTAssertTrue(SoundRecipe.tones(.growl, voice: false).isEmpty)
        XCTAssertEqual(SoundRecipe.tones(.hello, voice: false), SoundRecipe.arpeggio([5, 7, 8, 10]))
        XCTAssertEqual(SoundRecipe.tones(.feed, voice: false), SoundRecipe.tones(.feed))
        for cue in SoundTests.allCues {
            XCTAssertEqual(SoundRecipe.tones(cue, voice: true), SoundRecipe.tones(cue), "\(cue)")
        }
        XCTAssertTrue(SoundCue.growl.isVoice)
        XCTAssertFalse(SoundCue.ok.isVoice)
    }

    func testYipIsSofterThanBefore() {
        // Волна 32: тявк стал мягче — основной голос треугольником, квадрат только тихим телом под ним.
        let t = SoundRecipe.tones(.yip)
        let squares = t.filter { $0.wave == .square }
        XCTAssertFalse(squares.isEmpty)
        XCTAssertTrue(squares.allSatisfy { $0.gain <= 0.06 && $0.cutoff > 0 && $0.cutoff <= 1500 })
        XCTAssertEqual(t.filter { $0.wave == .triangle }.count, 2, "два тявка")
    }

    func testGrowlIsLowRumbleThenPlayfulRise() {
        let t = SoundRecipe.tones(.growl)
        let pulses = t.filter { $0.wave == .square }
        XCTAssertGreaterThanOrEqual(pulses.count, 8)
        XCTAssertTrue(pulses.allSatisfy { $0.freq < 200 && $0.cutoff <= 800 }, "низкий и тёмный")
        let last = t.max { $0.at < $1.at }!
        XCTAssertEqual(last.wave, .triangle)
        XCTAssertGreaterThan(last.glideTo, last.freq, "в конце — вопросительно вверх")
        // Не громче тявка.
        XCTAssertLessThanOrEqual(t.map(\.gain).max()!, SoundRecipe.tones(.yip).map(\.gain).max()!)
    }

    func testFirstPlaysAreYips() {
        var v = PetVoice()
        XCTAssertEqual(v.cue(.play, at: 0, roll: 0), .yip)
        XCTAssertEqual(v.cue(.play, at: 1, roll: 0), .yip)
        XCTAssertEqual(v.cue(.play, at: 2, roll: 0), .growl)
    }

    func testGrowlIsRareAndNeverTwiceInARow() {
        var v = PetVoice()
        _ = v.cue(.tickle, at: 0, roll: 0.9)
        _ = v.cue(.tickle, at: 1, roll: 0.9)
        XCTAssertEqual(v.cue(.tickle, at: 2, roll: PetVoice.chance(.tickle) + 0.01), .yip, "кубик не выпал")
        XCTAssertEqual(v.cue(.tickle, at: 3, roll: 0), .growl)
        // Пауза: сколько бы ни выпадало, следующие две минуты — тявк.
        for i in 0..<20 {
            XCTAssertEqual(v.cue(.play, at: 4 + Double(i), roll: 0), .yip)
        }
        XCTAssertEqual(v.cue(.play, at: 3 + PetVoice.cooldown, roll: 0), .growl)
        XCTAssertEqual(v.cue(.play, at: 3 + 3 * PetVoice.cooldown, roll: 0), .yip, "не два раза подряд")
    }

    func testGrowlShareOverManyGames() {
        // Кубик честный, игры раз в минуту: рычание — сюрприз, а не каждый раз.
        var v = PetVoice()
        var rng = SplitMix(seed: 7)
        var growls = 0
        let games = 400
        for i in 0..<games where v.cue(.play, at: Double(i) * 60, roll: rng.unit()) == .growl {
            growls += 1
        }
        XCTAssertGreaterThan(growls, games / 20)
        XCTAssertLessThan(growls, games / 4)
    }

    func testVoiceSurvivesClockReset() {
        var v = PetVoice()
        _ = v.cue(.play, at: 1000, roll: 1)
        _ = v.cue(.play, at: 1001, roll: 1)
        XCTAssertEqual(v.cue(.play, at: 1002, roll: 0), .growl)
        _ = v.cue(.play, at: 5, roll: 1)
        _ = v.cue(.play, at: 6, roll: 1)
        XCTAssertEqual(v.cue(.play, at: 7, roll: 0), .growl, "часы ушли назад — пауза не вечная")
    }

    // MARK: музыка

    func testMusicInKeyQuietAndFlagged() {
        for k in MusicTheme.Kind.allCases {
            XCTAssertEqual(MusicTheme.bars(k), 8)
            for i in 0..<MusicTheme.bars(k) {
                XCTAssertEqual(MusicTheme.melody(k)[i].count, MusicTheme.stepsPerBar)
                let bar = MusicTheme.bar(i, k)
                XCTAssertFalse(bar.isEmpty)
                for t in bar {
                    XCTAssertTrue(t.music)
                    XCTAssertFalse(t.choreo)
                    XCTAssertTrue(Scale.isInKey(t.freq), "\(t.freq)")
                    XCTAssertLessThanOrEqual(t.gain, 0.05, "музыка тише любого звука")
                    XCTAssertGreaterThanOrEqual(t.env.attack, Envelope.minAttack)
                    XCTAssertGreaterThan(t.env.release, 0.02)
                    XCTAssertGreaterThanOrEqual(t.at, 0)
                    XCTAssertLessThan(t.end, MusicTheme.barLength(k), "нота не вылезает в следующий такт")
                }
            }
            XCTAssertEqual(MusicTheme.loopLength(k), MusicTheme.barLength(k) * 8, accuracy: 1e-9)
            XCTAssertEqual(MusicTheme.bar(8, k), MusicTheme.bar(0, k), "по кругу")
            XCTAssertEqual(MusicTheme.bar(-1, k), MusicTheme.bar(7, k))
        }
        XCTAssertLessThan(MusicTheme.beat(.play), MusicTheme.beat(.calm))
    }

    func testMusicTakesAtMostTwoVoices() {
        for k in MusicTheme.Kind.allCases {
            for i in 0..<MusicTheme.bars(k) {
                let bar = MusicTheme.bar(i, k)
                for probe in stride(from: 0.0, to: MusicTheme.barLength(k), by: 0.01) {
                    let on = bar.filter { $0.at <= probe && probe < $0.end }.count
                    XCTAssertLessThanOrEqual(on, 2, "\(k) такт \(i), \(probe) с")
                }
            }
        }
    }

    func testMusicIsQuieterThanButton() {
        let button = SoundRecipe.tones(.button).map(\.gain).max()!
        for k in MusicTheme.Kind.allCases {
            XCTAssertLessThan(MusicTheme.bar(0, k).map(\.gain).max()!, button)
        }
    }

    // MARK: синтезатор

    private func run(_ core: SynthCore, seconds: Double, block: Int = 512) -> (samples: [Float], silent: [Bool]) {
        let total = Int(seconds * core.sampleRate)
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: block)
        defer { buf.deallocate() }
        var out: [Float] = []
        var silent: [Bool] = []
        var done = 0
        while done < total {
            silent.append(core.render(into: buf, frames: block))
            out.append(contentsOf: UnsafeBufferPointer(start: buf, count: block))
            done += block
        }
        return (out, silent)
    }

    func testCancelMusicKeepsSounds() {
        let core = SynthCore()
        core.push(MusicTheme.bar(0, .calm) + MusicTheme.bar(1, .calm).map { var t = $0; t.at += 2.4; return t })
        core.push(SoundRecipe.tones(.death))
        _ = run(core, seconds: 0.1)
        core.cancelMusic()
        let r = run(core, seconds: 0.4)
        let ref = SynthCore()
        ref.push(SoundRecipe.tones(.death))
        _ = run(ref, seconds: 0.1)
        let refRun = run(ref, seconds: 0.4)
        // Звучащий бас гаснет за fadeSamples, дальше — ровно как одна смерть.
        let tail = SynthCore.fadeSamples + 512
        XCTAssertEqual(Array(r.samples.dropFirst(tail)), Array(refRun.samples.dropFirst(tail)))
    }

    func testCancelMusicFadesAndLeavesChoreo() {
        let core = SynthCore()
        core.push(MusicTheme.bar(0, .play))
        _ = run(core, seconds: 0.005, block: 128)
        XCTAssertGreaterThan(core.activeVoices, 0)
        core.cancelMusic()
        let r = run(core, seconds: 0.5, block: 128)
        XCTAssertFalse(r.silent[0], "спад, а не обрыв")
        XCTAssertTrue(r.silent.dropFirst(3).allSatisfy { $0 })

        // Музыку, положенную после снятия, играет.
        core.push(MusicTheme.bar(1, .play))
        XCTAssertTrue(run(core, seconds: 0.2).silent.contains(false))

        // Снятие хореографии музыку не трогает.
        let other = SynthCore()
        other.push(MusicTheme.bar(0, .calm))
        _ = run(other, seconds: 0.01, block: 128)
        other.cancelChoreo()
        XCTAssertTrue(run(other, seconds: 0.1, block: 128).silent.allSatisfy { !$0 })
    }
}

/// Маленький детерминированный генератор для «честного кубика».
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func unit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
