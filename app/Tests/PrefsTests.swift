// Волна 32: переключатели «Звук и отклик», голос пса (тявк / редкое рычание), музыка (лупы по местам),
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
            XCTAssertGreaterThanOrEqual(MusicTheme.bars(k), 8)
            for i in 0..<MusicTheme.bars(k) {
                let line = MusicTheme.sheet(k)[i]
                XCTAssertTrue(line.isEmpty || line.count == MusicTheme.stepsPerBar, "\(k) такт \(i)")
                let bar = MusicTheme.bar(i, k)
                XCTAssertEqual(bar.isEmpty, MusicTheme.isRest(i, k))
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
            let n = MusicTheme.bars(k)
            XCTAssertEqual(MusicTheme.loopLength(k), MusicTheme.barLength(k) * Double(n), accuracy: 1e-9)
            XCTAssertEqual(MusicTheme.bar(n, k), MusicTheme.bar(0, k), "по кругу")
            XCTAssertEqual(MusicTheme.bar(-1, k), MusicTheme.bar(n - 1, k))
            XCTAssertFalse(MusicTheme.bar(0, k).isEmpty, "луп начинается с музыки, а не с паузы")
        }
    }

    func testEachPlaceHasItsOwnShortLoop() {
        let kinds = MusicTheme.Kind.allCases
        XCTAssertEqual(Set(kinds.map { MusicTheme.sheet($0) }).count, kinds.count, "у каждого места свой луп")
        for k in kinds {
            XCTAssertLessThanOrEqual(MusicTheme.loopLength(k), 30, "\(k): луп короткий")
        }
        XCTAssertLessThan(MusicTheme.beat(.play), MusicTheme.beat(.walk))
        XCTAssertLessThan(MusicTheme.beat(.walk), MusicTheme.beat(.shop))
        XCTAssertLessThan(MusicTheme.beat(.shop), MusicTheme.beat(.home))
    }

    func testMusicLeavesPauses() {
        func restShare(_ k: MusicTheme.Kind) -> Double {
            let n = MusicTheme.bars(k)
            return Double((0..<n).filter { MusicTheme.isRest($0, k) }.count) / Double(n)
        }
        for k in MusicTheme.Kind.allCases {
            XCTAssertGreaterThanOrEqual(restShare(k), 0.25, "\(k): после фраз — тишина")
            // Пауза в конце лупа: повтор не встык.
            XCTAssertTrue(MusicTheme.isRest(MusicTheme.bars(k) - 1, k))
        }
        for k in [MusicTheme.Kind.play, .shop, .walk] {
            XCTAssertGreaterThan(restShare(.home), restShare(k), "на главном пауз больше всех")
        }
    }

    func testSoftChiptune() {
        for k in MusicTheme.Kind.allCases {
            let bar = MusicTheme.bar(0, k)
            let lead = bar.filter { $0.wave == .square }
            XCTAssertFalse(lead.isEmpty, "\(k): 8-битная мелодия")
            for t in lead {
                XCTAssertGreaterThan(t.cutoff, 0, "квадрат только за фильтром — без писка")
                XCTAssertLessThanOrEqual(t.cutoff, 1600)
            }
            XCTAssertTrue(bar.contains { $0.wave == .triangle && $0.freq < Scale.note(0) }, "мягкий бас")
        }
        // Лоу-фай: каждая вторая восьмая чуть запаздывает.
        XCTAssertGreaterThan(MusicTheme.stepStart(1, .shop), MusicTheme.beat(.shop))
        XCTAssertEqual(MusicTheme.stepStart(2, .shop), 2 * MusicTheme.beat(.shop), accuracy: 1e-12)
    }

    func testHomeIsQuietest() {
        let home = MusicTheme.bar(0, .home).map(\.gain).max()!
        for k in [MusicTheme.Kind.play, .shop, .walk] {
            XCTAssertLessThan(home, MusicTheme.bar(0, k).map(\.gain).max()!)
        }
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

    func testHomeMusicFollowsTheDog() {
        XCTAssertEqual(MusicTheme.homeKind(pose: .idle, alive: true), .home)
        XCTAssertEqual(MusicTheme.homeKind(pose: .happy, alive: true), .home)
        XCTAssertEqual(MusicTheme.homeKind(pose: .hungry, alive: true), .home)
        XCTAssertEqual(MusicTheme.homeKind(pose: .away, alive: true), .walk, "пёс гуляет — музыка прогулки")
        for quiet in [Pose.sleep, .nap, .critical, .dead] {
            XCTAssertNil(MusicTheme.homeKind(pose: quiet, alive: true), "\(quiet): тишина")
        }
        XCTAssertNil(MusicTheme.homeKind(pose: .idle, alive: false))
    }

    func testQuietHoursFromBedToWake() {
        // Отбой 23:00, подъём 7:30.
        let bed = 23 * 60, wake = 7 * 60 + 30
        XCTAssertFalse(MusicTheme.quietHours(localMin: 22 * 60 + 59, bedMin: bed, wakeMin: wake))
        XCTAssertTrue(MusicTheme.quietHours(localMin: 23 * 60, bedMin: bed, wakeMin: wake))
        XCTAssertTrue(MusicTheme.quietHours(localMin: 3 * 60, bedMin: bed, wakeMin: wake))
        XCTAssertTrue(MusicTheme.quietHours(localMin: 7 * 60 + 29.5, bedMin: bed, wakeMin: wake))
        XCTAssertFalse(MusicTheme.quietHours(localMin: 7 * 60 + 30, bedMin: bed, wakeMin: wake))
        XCTAssertFalse(MusicTheme.quietHours(localMin: 12 * 60, bedMin: bed, wakeMin: wake))
        // Отбой после полуночи.
        XCTAssertFalse(MusicTheme.quietHours(localMin: 23 * 60 + 30, bedMin: 60, wakeMin: 9 * 60))
        XCTAssertTrue(MusicTheme.quietHours(localMin: 2 * 60, bedMin: 60, wakeMin: 9 * 60))
    }

    // MARK: подписи под круглыми кнопками

    func testRoundCaptionsShortRussianAndDistinct() {
        XCTAssertEqual(Set(RoundCaption.all).count, RoundCaption.all.count)
        for w in RoundCaption.all {
            XCTAssertLessThanOrEqual(w.count, RoundCaption.maxLength, w)
            XCTAssertFalse(w.contains(" "), "одно слово: \(w)")
            XCTAssertTrue(w.unicodeScalars.allSatisfy { (0x0400...0x04FF).contains($0.value) }, w)
        }
        XCTAssertGreaterThanOrEqual(RoundCaption.room, 10, "место под подписью кеглем 10")
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
        core.push(MusicTheme.bar(0, .shop) + MusicTheme.bar(1, .shop).map { var t = $0; t.at += MusicTheme.barLength(.shop); return t })
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
        other.push(MusicTheme.bar(0, .shop))
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
