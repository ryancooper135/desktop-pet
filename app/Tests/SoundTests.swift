// Звук без экрана: нотная таблица, огибающая, рецепты и синтезатор (рендер в буфер, без AVFoundation).
// Идёт и на Linux (app/Package.swift), и в app.yml.

import Foundation
import XCTest
@testable import Pet

final class SoundTests: XCTestCase {
    static let allCues: [SoundCue] = [
        .button, .boop, .petTick(1), .petTick(4), .petTick(30), .pet, .feed, .yip, .bath, .refuse,
        .ok, .wake, .hearts, .heartLost, .hello, .death, .brush, .brushDone,
    ]

    static var choreoTones: [Tone] {
        SoundRecipe.ball(start: 0.2, kick: 1.15, bounces: [(0.5, 0.16), (0.32, 0.07), (0.2, 0.025)], knock: 3.05)
            + SoundRecipe.eat(from: 0.4, to: 2.2)
    }

    // MARK: нотная таблица

    func testScaleAnchors() {
        XCTAssertEqual(Scale.midi(0), 60)
        XCTAssertEqual(Scale.midi(4), 69)
        XCTAssertEqual(Scale.midi(5), 72)
        XCTAssertEqual(Scale.midi(-1), 57)  // ля малой октавы
        XCTAssertEqual(Scale.midi(-3), 52)  // ми малой октавы
        XCTAssertEqual(Scale.midi(-5), 48)
        XCTAssertEqual(Scale.note(0), 261.63, accuracy: 0.01)
        XCTAssertEqual(Scale.note(4), 440, accuracy: 1e-9)
        XCTAssertEqual(Scale.note(5), 523.25, accuracy: 0.01)
    }

    func testScaleTableRisesAndClamps() {
        for s in Scale.lowest..<Scale.highest {
            XCTAssertLessThan(Scale.note(s), Scale.note(s + 1))
        }
        XCTAssertEqual(Scale.note(Scale.highest + 7), Scale.note(Scale.highest))
        XCTAssertEqual(Scale.note(Scale.lowest - 7), Scale.note(Scale.lowest))
        XCTAssertEqual(Scale.table.count, Scale.highest - Scale.lowest + 1)
    }

    func testIsInKey() {
        for s in Scale.lowest...Scale.highest {
            XCTAssertTrue(Scale.isInKey(Scale.note(s)), "ступень \(s)")
        }
        XCTAssertFalse(Scale.isInKey(Scale.hz(midi: 61)))  // до-диез
        XCTAssertFalse(Scale.isInKey(Scale.hz(midi: 65)))  // фа
        XCTAssertFalse(Scale.isInKey(Scale.hz(midi: 71)))  // си
        XCTAssertFalse(Scale.isInKey(450))
        XCTAssertFalse(Scale.isInKey(0))
    }

    // MARK: огибающая

    func testEnvelopeShape() {
        let e = Envelope(attack: 0.01, hold: 0.02, release: 0.1)
        XCTAssertEqual(e.length, 0.13, accuracy: 1e-12)
        XCTAssertEqual(e.level(0), 0)
        XCTAssertEqual(e.level(-1), 0)
        XCTAssertEqual(e.level(0.005), 0.5, accuracy: 1e-9)
        XCTAssertEqual(e.level(0.01), 1, accuracy: 1e-9)
        XCTAssertEqual(e.level(0.025), 1, accuracy: 1e-9)
        XCTAssertEqual(e.level(0.08), 0.25, accuracy: 1e-9)  // половина спада: (1 − 0,5)²
        XCTAssertEqual(e.level(0.13), 0, accuracy: 1e-12)
        XCTAssertEqual(e.level(1), 0)
        var last = 1.0
        for i in 0...100 {
            let v = e.level(0.03 + 0.001 * Double(i))
            XCTAssertLessThanOrEqual(v, last + 1e-12)
            last = v
        }
    }

    // MARK: рецепты

    /// Всё, что звучит нотой, — в до-мажорной пентатонике, и начало, и конец скольжения.
    func testEverythingInOneKey() {
        let tones = Self.allCues.flatMap(SoundRecipe.tones) + Self.choreoTones
        for t in tones where t.wave != .noise {
            XCTAssertTrue(Scale.isInKey(t.freq), "\(t.freq) Гц не в тональности")
            XCTAssertTrue(Scale.isInKey(t.glideTo), "\(t.glideTo) Гц не в тональности")
        }
    }

    func testCuesAreShortSoftAndClickFree() {
        for cue in Self.allCues {
            let tones = SoundRecipe.tones(cue)
            XCTAssertFalse(tones.isEmpty, "\(cue)")
            let end = tones.map(\.end).max() ?? 0
            if cue != .death {
                XCTAssertLessThanOrEqual(end, SoundRecipe.maxLength, "\(cue) длиннее 0,6 с")
            } else {
                XCTAssertLessThan(end, 2.5)
            }
            for t in tones {
                XCTAssertGreaterThanOrEqual(t.env.attack, Envelope.minAttack, "\(cue): щелчок в начале")
                XCTAssertGreaterThan(t.env.release, 0.02, "\(cue): щелчок в конце")
                XCTAssertGreaterThan(t.gain, 0)
                XCTAssertLessThanOrEqual(t.gain, 0.4)
                XCTAssertGreaterThanOrEqual(t.at, 0)
                XCTAssertFalse(t.choreo, "\(cue): обычный звук не должен сниматься с хореографией")
            }
        }
    }

    /// Кнопка — самый тихий звук.
    func testButtonIsQuietest() {
        let button = SoundRecipe.tones(.button).map(\.gain).max() ?? 1
        for cue in Self.allCues where cue != .button {
            XCTAssertLessThan(button, SoundRecipe.tones(cue).map(\.gain).max() ?? 0, "\(cue)")
        }
    }

    func testPetTicksClimbThenHold() {
        let f = (1...12).map { SoundRecipe.tones(.petTick($0))[0].freq }
        for i in 1..<8 { XCTAssertGreaterThan(f[i], f[i - 1]) }
        XCTAssertEqual(f[8], f[7])
        XCTAssertEqual(f[11], f[7])
        XCTAssertEqual(SoundRecipe.tones(.petTick(0))[0].freq, f[0])
    }

    func testRefuseIsTwoLowNotesDown() {
        let t = SoundRecipe.tones(.refuse)
        XCTAssertEqual(t.count, 2)
        XCTAssertGreaterThan(t[0].freq, t[1].freq)
        XCTAssertLessThan(t[0].freq, Scale.note(0))
    }

    func testDeathDescends() {
        let t = SoundRecipe.tones(.death).sorted { $0.at < $1.at }
        for i in 1..<t.count { XCTAssertLessThan(t[i].freq, t[i - 1].freq) }
        XCTAssertLessThan(t.last!.glideTo, t.last!.freq)
    }

    func testHeartsArpeggioRises() {
        let t = SoundRecipe.tones(.hearts)
        XCTAssertEqual(t.count, 4)
        for i in 1..<t.count {
            XCTAssertGreaterThan(t[i].freq, t[i - 1].freq)
            XCTAssertEqual(t[i].at - t[i - 1].at, 0.07, accuracy: 1e-9)
        }
    }

    func testActionMapping() {
        XCTAssertEqual(SoundRecipe.forAction(kind: "feed", ok: true), .feed)
        XCTAssertEqual(SoundRecipe.forAction(kind: "pet", ok: true), .pet)
        XCTAssertEqual(SoundRecipe.forAction(kind: "play", ok: true), .yip)
        XCTAssertEqual(SoundRecipe.forAction(kind: "walk", ok: true), .yip)
        XCTAssertEqual(SoundRecipe.forAction(kind: "bath", ok: true), .bath)
        XCTAssertEqual(SoundRecipe.forAction(kind: "wake", ok: true), .wake)
        XCTAssertEqual(SoundRecipe.forAction(kind: "item", ok: true), .ok)
        XCTAssertNil(SoundRecipe.forAction(kind: "steps", ok: true))
        for kind in ["feed", "pet", "play", "bath", "wake", "item", "steps"] {
            XCTAssertEqual(SoundRecipe.forAction(kind: kind, ok: false), .refuse, kind)
        }
    }

    /// Виды действий из ядра совпадают с теми, что знают рецепты.
    func testPetActionKindsMatchRecipes() {
        let expected: [(PetAction, SoundCue?)] = [
            (.feed("kibble"), .feed), (.item("vitamin"), .ok), (.pet, .pet), (.play, .yip), (.bath, .bath),
            (.wake, .wake), (.steps(100), nil), (.walk, .yip),
        ]
        for (a, cue) in expected {
            XCTAssertEqual(SoundRecipe.forAction(kind: a.kind, ok: true), cue, a.kind)
            XCTAssertEqual(SoundRecipe.forAction(kind: a.kind, ok: false), .refuse, a.kind)
        }
    }

    // MARK: хореография

    func testBloopFollowsBounceHeight() {
        let heights = [0.16, 0.07, 0.025, 0.0]
        let b = heights.map { SoundRecipe.bloop(at: 0, height: $0) }
        for i in 1..<b.count {
            XCTAssertLessThanOrEqual(b[i].freq, b[i - 1].freq)
            XCTAssertLessThan(b[i].gain, b[i - 1].gain)
        }
        XCTAssertGreaterThan(b[0].freq, b[2].freq)
        XCTAssertEqual(SoundRecipe.bounceStep(0.16), 9)
        XCTAssertEqual(SoundRecipe.bounceStep(5), 10)
        XCTAssertEqual(SoundRecipe.bounceStep(-1), 5)
        for t in b { XCTAssertLessThan(t.glideTo, t.freq) }
    }

    func testBallTimeline() {
        let t = SoundRecipe.ball(start: 1, kick: 1.15, bounces: [(0.5, 0.16), (0.32, 0.07), (0.2, 0.025)], knock: 3.05)
        XCTAssertEqual(t.count, 5)
        assertClose(t.map(\.at), [2.15, 2.65, 2.97, 3.17, 4.05])
        XCTAssertTrue(t.allSatisfy(\.choreo))
    }

    func testDelayedIsShiftedChoreo() {
        let base = SoundRecipe.tones(.yip)
        let d = SoundRecipe.delayed(.yip, by: 0.7)
        XCTAssertEqual(d.count, base.count)
        assertClose(d.map(\.at), base.map { $0.at + 0.7 })
        XCTAssertTrue(d.allSatisfy(\.choreo))
        assertClose(SoundRecipe.delayed(.yip, by: -1).map(\.at), base.map(\.at))
    }

    func testEatCrunches() {
        let t = SoundRecipe.eat(from: 0.5, to: 1.8)
        let crunches = t.filter { $0.wave == .noise }
        XCTAssertEqual(crunches.count, 4)  // 0,5 / 0,82 / 1,14 / 1,46
        XCTAssertEqual(crunches.first?.at ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertTrue(t.allSatisfy(\.choreo))
        XCTAssertTrue(SoundRecipe.eat(from: 1, to: 1).isEmpty)
        XCTAssertEqual(SoundRecipe.eat(from: 0, to: 100).filter { $0.wave == .noise }.count, SoundRecipe.maxCrunches)
    }

    // MARK: синтезатор

    /// Прогнать рендер блоками по 512, пока не наберётся seconds. Возвращает все семплы и тишину по блокам.
    private func run(_ core: SynthCore, seconds: Double, block: Int = 512) -> (samples: [Float], silent: [Bool]) {
        let total = Int(seconds * core.sampleRate)
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: block)
        defer { buf.deallocate() }
        var out: [Float] = []
        var silent: [Bool] = []
        var done = 0
        while done < total {
            let s = core.render(into: buf, frames: block)
            silent.append(s)
            out.append(contentsOf: UnsafeBufferPointer(start: buf, count: block))
            done += block
        }
        return (out, silent)
    }

    /// Аудит v0.5: звуки и сброс с главного потока, пока аудиопоток рендерит, — без NaN, без выхода за
    /// потолок, и после всего синтезатор затихает (SPSC-кольцо, Atomic-метки).
    func testPushAndResetWhileRenderingOnAnotherThread() {
        let core = SynthCore()
        let cues = Self.allCues
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            for i in 0..<300 {
                _ = core.push(SoundRecipe.tones(cues[i % cues.count]))
                if i % 37 == 0 { core.requestReset() }
                if i % 53 == 0 { core.cancelChoreo() }
                usleep(100)
            }
            done.signal()
        }
        let block = 256
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: block)
        defer { buf.deallocate() }
        var peak: Float = 0
        var bad = 0
        var finished = false
        var tail = 0
        while tail < Int(4 * core.sampleRate) / block {
            _ = core.render(into: buf, frames: block)
            for v in UnsafeBufferPointer(start: buf, count: block) {
                if v.isNaN || v.isInfinite { bad += 1 } else { peak = max(peak, abs(v)) }
            }
            if !finished { finished = done.wait(timeout: .now()) == .success } else { tail += 1 }
        }
        XCTAssertEqual(bad, 0)
        XCTAssertLessThanOrEqual(Double(peak), SynthCore.ceiling + 1e-6)
        XCTAssertTrue(core.render(into: buf, frames: block), "после очереди тишина")
    }

    func testRenderEveryCueIsSaneAndEnds() {
        for cue in Self.allCues {
            let core = SynthCore()
            XCTAssertEqual(core.push(SoundRecipe.tones(cue)), SoundRecipe.tones(cue).count)
            let r = run(core, seconds: 3)
            XCTAssertFalse(r.samples.contains { $0.isNaN || $0.isInfinite }, "\(cue)")
            let peak = r.samples.map { abs($0) }.max() ?? 0
            XCTAssertGreaterThan(peak, 0.001, "\(cue) не слышно")
            XCTAssertLessThanOrEqual(Double(peak), SynthCore.ceiling + 1e-6, "\(cue)")
            XCTAssertTrue(r.silent.last ?? false, "\(cue) не затих")
            XCTAssertEqual(core.activeVoices, 0)
        }
    }

    func testSilenceBeforeAnything() {
        let core = SynthCore()
        let r = run(core, seconds: 0.1)
        XCTAssertTrue(r.silent.allSatisfy { $0 })
        XCTAssertTrue(r.samples.allSatisfy { $0 == 0 })
    }

    /// Нота с задержкой стартует точно в свой семпл, даже посреди блока.
    func testSampleAccurateStart() {
        let core = SynthCore()
        let at = 0.05
        core.push([Tone(at: at, .square, 440, env: Envelope(attack: 0.001, hold: 0.05, release: 0.05), gain: 0.3)])
        let r = run(core, seconds: 0.2)
        let first = r.samples.firstIndex { $0 != 0 } ?? -1
        let expected = Int((at * core.sampleRate).rounded())
        XCTAssertEqual(first, expected + 1)  // в самом первом семпле огибающая ещё 0
    }

    func testPolyphonyCapsAtSixVoices() {
        let core = SynthCore()
        let many = (0..<20).map { i in
            Tone(.triangle, Scale.note(i % 10), env: Envelope(attack: 0.01, hold: 0.3, release: 0.2), gain: 0.4)
        }
        XCTAssertEqual(core.push(many), 20)
        let r = run(core, seconds: 0.05)
        XCTAssertEqual(core.activeVoices, SynthCore.voiceCount)
        let peak = r.samples.map { abs($0) }.max() ?? 0
        XCTAssertLessThanOrEqual(Double(peak), SynthCore.ceiling + 1e-6)
        _ = run(core, seconds: 1)
        XCTAssertEqual(core.activeVoices, 0)
    }

    func testRingOverflowDropsTail() {
        let core = SynthCore()
        let tone = Tone(.sine, 440, env: Envelope(attack: 0.001, hold: 0, release: 0.03), gain: 0.1)
        let n = SynthCore.queueCapacity + 10
        XCTAssertEqual(core.push(Array(repeating: tone, count: n)), SynthCore.queueCapacity)
        XCTAssertEqual(core.push([tone]), 0)
        _ = run(core, seconds: 0.01)
        XCTAssertEqual(core.push([tone]), 1)  // рендер дочитал кольцо — место снова есть
    }

    func testResetSilencesAndDropsQueued() {
        let core = SynthCore()
        core.push(SoundRecipe.tones(.death))
        _ = run(core, seconds: 0.1)
        XCTAssertGreaterThan(core.activeVoices, 0)
        core.requestReset()
        let r = run(core, seconds: 2)
        XCTAssertTrue(r.silent.allSatisfy { $0 })
        // После сброса новые ноты играют.
        core.push(SoundRecipe.tones(.ok))
        let after = run(core, seconds: 0.05)
        XCTAssertTrue(after.silent.contains(false))
    }

    func testCancelChoreoKeepsOtherSounds() {
        let core = SynthCore()
        core.push(SoundRecipe.eat(from: 0.3, to: 3))
        core.push(SoundRecipe.tones(.death))
        _ = run(core, seconds: 0.1)
        core.cancelChoreo()
        // Смерть продолжает звучать, а хрусты сняты.
        let r = run(core, seconds: 0.4)
        XCTAssertTrue(r.silent.contains(false))
        // Сравнение с прогоном только смерти: семплы совпадают, если хрусты сняты.
        let ref = SynthCore()
        ref.push(SoundRecipe.tones(.death))
        _ = run(ref, seconds: 0.1)
        let refRun = run(ref, seconds: 0.4)
        XCTAssertEqual(r.samples, refRun.samples)
    }

    func testCancelChoreoFadesSoundingVoice() {
        let core = SynthCore()
        core.push(SoundRecipe.eat(from: 0, to: 3))
        _ = run(core, seconds: 0.005, block: 128)
        XCTAssertGreaterThan(core.activeVoices, 0)
        core.cancelChoreo()
        let r = run(core, seconds: 0.5, block: 128)
        // Первый блок после снятия — спад, без скачка к нулю в начале.
        XCTAssertFalse(r.silent[0])
        XCTAssertTrue(r.silent.dropFirst(3).allSatisfy { $0 })
    }

    func testLimiter() {
        XCTAssertEqual(SynthCore.limit(0), 0)
        XCTAssertEqual(SynthCore.limit(1), SynthCore.ceiling, accuracy: 1e-12)
        XCTAssertEqual(SynthCore.limit(10), SynthCore.ceiling, accuracy: 1e-12)
        XCTAssertEqual(SynthCore.limit(-10), -SynthCore.ceiling, accuracy: 1e-12)
        XCTAssertEqual(SynthCore.limit(0.1), 0.1, accuracy: 0.001)
        var last = -1.0
        for i in 0...200 {
            let v = SynthCore.limit(-2 + 0.02 * Double(i))
            XCTAssertGreaterThanOrEqual(v, last - 1e-12)
            last = v
        }
    }
}

private func assertClose(_ a: [Double], _ b: [Double], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: 1e-9, file: file, line: line) }
}
