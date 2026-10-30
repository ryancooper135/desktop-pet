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
        XCTAssertEqual(SoundRecipe.tones(.hello, voice: false),
                       SoundRecipe.normalized(SoundRecipe.arpeggio([5, 7, 8, 10]), to: SoundRecipe.loudness(.hello)))
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
        // Не громче тявка (волна 49: громкость по слуху, а не по одной ноте).
        XCTAssertLessThanOrEqual(SoundRecipe.perceived(t), SoundRecipe.perceived(SoundRecipe.tones(.yip)) + 1e-9)
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

    // Волна 49: музыка — файлы, тесты чиптюна (такты, свинг, голоса) ушли вместе с ним.

    func testMusicTracksPerPlace() {
        XCTAssertEqual(MusicTheme.track(.play), MusicTheme.playTrack, "у мини-игр свой луп")
        for k in [MusicTheme.Kind.home, .shop, .walk, .sleep] {
            XCTAssertEqual(MusicTheme.track(k), MusicTheme.homeTrack, "\(k)")
        }
        XCTAssertEqual(Set(MusicTheme.tracks).count, 2)
        XCTAssertTrue(Set(MusicTheme.Kind.allCases.map(MusicTheme.track)).isSubset(of: Set(MusicTheme.tracks)))
    }

    func testMusicIsQuietAndQuieterAtNightAndAsleep() {
        for k in MusicTheme.Kind.allCases {
            let v = MusicTheme.volume(k)
            XCTAssertGreaterThan(v, 0, "\(k): тише, но не тишина")
            XCTAssertLessThanOrEqual(v, 0.4, "\(k): музыка — фон")
            XCTAssertLessThan(MusicTheme.level(k, quiet: true), MusicTheme.level(k, quiet: false), "\(k): ночью тише")
            XCTAssertGreaterThan(MusicTheme.level(k, quiet: true), 0, "\(k): ночью тише, а не молчит")
        }
        XCTAssertLessThan(MusicTheme.volume(.sleep), MusicTheme.volume(.home) / 2, "пёс спит — еле слышно")
        XCTAssertLessThanOrEqual(MusicTheme.volume(.home), MusicTheme.volume(.play))
        XCTAssertGreaterThan(MusicTheme.fadeIn, 0.5, "мягкий вход")
        XCTAssertGreaterThan(MusicTheme.fadeOut, 0.2)
    }

    private var appDir: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }

    func testMusicFilesBundledSmallAndLicensed() throws {
        var total = 0
        for t in MusicTheme.tracks {
            let url = appDir.appendingPathComponent("Resources/Music/\(t).\(MusicTheme.fileExtension)")
            let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, t)
            XCTAssertGreaterThan(size, 50_000, t)
            total += size
        }
        XCTAssertLessThanOrEqual(total, 1_500_000, "вся музыка не больше 1,5 МБ")
        let lic = try String(contentsOf: appDir.deletingLastPathComponent().appendingPathComponent("content/ASSETS_LICENSES.md"),
                             encoding: .utf8)
        for t in MusicTheme.tracks {
            XCTAssertTrue(lic.contains("\(t).\(MusicTheme.fileExtension)"), "лицензия \(t) записана")
        }
        XCTAssertTrue(lic.contains("CC0"))
    }

    func testMusicRespectsSilentSwitchAndOtherMusic() throws {
        let src = try String(contentsOf: appDir.appendingPathComponent("App/SoundKit.swift"), encoding: .utf8)
        XCTAssertTrue(src.contains("setCategory(.ambient"), "беззвучный режим и смешивание — категория .ambient")
        XCTAssertFalse(src.contains(".playback"), "не перебивать беззвучный режим")
        XCTAssertTrue(src.contains("secondaryAudioShouldBeSilencedHint"), "играет чужая музыка — своя молчит")
        XCTAssertTrue(src.contains("silenceSecondaryAudioHintNotification"))
        XCTAssertTrue(src.contains("numberOfLoops = -1"), "луп по кругу")
        XCTAssertTrue(src.contains("Self.musicOn"), "переключатель «Музыка»")
    }

    func testHomeMusicFollowsTheDog() {
        XCTAssertEqual(MusicTheme.homeKind(pose: .idle, alive: true), .home)
        XCTAssertEqual(MusicTheme.homeKind(pose: .happy, alive: true), .home)
        XCTAssertEqual(MusicTheme.homeKind(pose: .hungry, alive: true), .home)
        XCTAssertEqual(MusicTheme.homeKind(pose: .away, alive: true), .walk, "пёс гуляет — музыка прогулки")
        for asleep in [Pose.sleep, .nap] {
            XCTAssertEqual(MusicTheme.homeKind(pose: asleep, alive: true), .sleep, "\(asleep): тише, а не тишина")
        }
        for quiet in [Pose.critical, .dead] {
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

    /// Такт «музыки» для тестов движка (Tone.music): бас на весь такт и две ноты мелодии. Сама музыка с волны 49 — файлы.
    private static let musicBarLength = 2.4

    private func musicBar(_ i: Int) -> [Tone] {
        let bass = Tone(.triangle, Scale.note(-5 - i % 2), env: Envelope(attack: 0.01, hold: 1, release: 1.2), gain: 0.035,
                        cutoff: 600)
        let lead = [0.0, 0.6].map {
            Tone(at: $0, .square, Scale.note(7 + i % 3), env: Envelope(attack: 0.008, hold: 0.02, release: 0.4), gain: 0.03,
                 cutoff: 1100)
        }
        return ([bass] + lead).map { var t = $0; t.music = true; return t }
    }

    func testCancelMusicKeepsSounds() {
        let core = SynthCore()
        core.push(musicBar(0) + musicBar(1).map { var t = $0; t.at += Self.musicBarLength; return t })
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
        core.push(musicBar(0))
        _ = run(core, seconds: 0.005, block: 128)
        XCTAssertGreaterThan(core.activeVoices, 0)
        core.cancelMusic()
        let r = run(core, seconds: 0.5, block: 128)
        XCTAssertFalse(r.silent[0], "спад, а не обрыв")
        XCTAssertTrue(r.silent.dropFirst(3).allSatisfy { $0 })

        // Музыку, положенную после снятия, играет.
        core.push(musicBar(1))
        XCTAssertTrue(run(core, seconds: 0.2).silent.contains(false))

        // Снятие хореографии музыку не трогает.
        let other = SynthCore()
        other.push(musicBar(0))
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
