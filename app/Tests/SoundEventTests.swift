// Волна 49: что звучит и что нет. Монеты звенят только за реальную добычу монет; еда — мягкий хруст без
// высоких нот; все звуки одного уровня громкости и с мягким подъёмом. Идёт на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet

final class SoundEventTests: XCTestCase {
    // MARK: монеты

    func testCoinsOnlyForRealEarnings() {
        XCTAssertEqual(CoinChime.cue(.yardCollect(coins: 120)), .coins, "сбор копилки двора")
        XCTAssertEqual(CoinChime.cue(.dailyTask(coins: 20)), .coins, "задание дня")
        XCTAssertEqual(CoinChime.cue(.dogAsk(coins: 10)), .coins, "просьба пса")
        XCTAssertEqual(CoinChime.cue(.miniGame(coins: 15, record: false)), .coins, "награда мини-игры")
    }

    func testNoCoinsWithoutCoins() {
        // Траты — не добыча: плита, улучшение, золотая табличка, покупки звенят обычным «динь».
        for e: CoinChime.Event in [.yardPlate, .yardUpgrade, .yardGild, .purchase] {
            XCTAssertEqual(CoinChime.cue(e), .ok, "\(e)")
        }
        // Копилка без монет (только порции/билеты) — не монеты.
        XCTAssertEqual(CoinChime.cue(.yardCollect(coins: 0)), .ok)
        // Монеты игр на сегодня кончились — обычный итог; рекорд — сердечки.
        XCTAssertEqual(CoinChime.cue(.miniGame(coins: 0, record: false)), .ok)
        XCTAssertEqual(CoinChime.cue(.miniGame(coins: 0, record: true)), .hearts)
        XCTAssertEqual(CoinChime.cue(.miniGame(coins: 30, record: true)), .hearts, "рекорд важнее")
        // Задание без монет — молчит: своё действие уже прозвучало.
        XCTAssertNil(CoinChime.cue(.dailyTask(coins: 0)))
        XCTAssertNil(CoinChime.cue(.dogAsk(coins: 0)))
    }

    func testCareActionsNeverSoundLikeCoins() {
        for kind in ["feed", Cooking.reactKind, "pet", "play", "walk", "bath", "wake", "steps", "brush", "cook"] {
            XCTAssertNotEqual(SoundRecipe.forAction(kind: kind, ok: true), .coins, kind)
            XCTAssertNotEqual(SoundRecipe.forAction(kind: kind, ok: false), .coins, kind)
        }
    }

    private var appDir: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }

    /// Звон монет в приложении — только через CoinChime: прямой `.coins` в Feel/SoundKit вернул бы звон на тратах.
    func testAppPlaysCoinsOnlyThroughCoinChime() throws {
        let dir = appDir.appendingPathComponent("App")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(files.isEmpty)
        let direct = try NSRegularExpression(pattern: #"(Feel\.\w+|\.play)\(\s*\.coins\b"#)
        var chimes = 0
        for f in files {
            let src = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
            let range = NSRange(src.startIndex..., in: src)
            XCTAssertEqual(direct.numberOfMatches(in: src, range: range), 0, "\(f): .coins мимо CoinChime")
            chimes += src.components(separatedBy: "CoinChime.cue(").count - 1
        }
        // Двор (4), две мини-игры (зомби убраны в волне 55), задание дня, просьба.
        XCTAssertGreaterThanOrEqual(chimes, 8)
    }

    // MARK: еда

    func testFeedAndEatAreSoftAndLow() {
        let eat = SoundRecipe.eat(from: 0, to: 3)
        XCTAssertFalse(eat.isEmpty)
        for t in SoundRecipe.tones(.feed) + eat {
            if t.wave == .noise {
                XCTAssertLessThanOrEqual(t.cutoff, 1300, "шум без высоких частот")
                XCTAssertGreaterThan(t.cutoff, 0)
            } else {
                XCTAssertLessThanOrEqual(max(t.freq, t.glideTo), Scale.note(5), "без звонких нот выше до второй октавы")
                XCTAssertNotEqual(t.wave, .square)
            }
            XCTAssertGreaterThanOrEqual(t.env.attack, SoundRecipe.softAttack, "мягкий подъём")
        }
        // Хруст тише обычного звука: он повторяется всю еду.
        XCTAssertEqual(SoundRecipe.perceived(eat), SoundRecipe.crunchLevel, accuracy: 1e-9)
        XCTAssertLessThan(SoundRecipe.crunchLevel, SoundRecipe.level)
    }

    func testCoinsNotShrill() {
        for t in SoundRecipe.tones(.coins) {
            XCTAssertNotEqual(t.wave, .square)
            XCTAssertLessThanOrEqual(t.freq, Scale.note(15), "без писка")
        }
    }

    // MARK: громкость

    func testEveryCueNormalizedWithSoftAttack() {
        for cue in SoundTests.allCues {
            let tones = SoundRecipe.tones(cue)
            XCTAssertEqual(SoundRecipe.perceived(tones), SoundRecipe.loudness(cue), accuracy: 1e-9, "\(cue)")
            // Запас до ограничителя синтезатора: пик огибающих не упирается в потолок.
            XCTAssertLessThan(SoundRecipe.envelopePeak(tones), 0.6, "\(cue)")
            for t in tones {
                XCTAssertGreaterThanOrEqual(t.env.attack, SoundRecipe.softAttack, "\(cue): резкий подъём")
            }
        }
        // Без голоса — тоже к уровню.
        for cue in [SoundCue.yip, .hello] {
            XCTAssertEqual(SoundRecipe.perceived(SoundRecipe.tones(cue, voice: false)), SoundRecipe.level, accuracy: 1e-9)
        }
    }

    func testEnvelopePeakSumsOverlapsAndNormalizeKeepsShape() {
        let e = Envelope(attack: 0.01, hold: 0.1, release: 0.1)
        let a = Tone(.sine, 440, env: e, gain: 0.1)
        var b = a
        b.at = 0.05
        XCTAssertEqual(SoundRecipe.envelopePeak([a]), 0.1, accuracy: 1e-12)
        XCTAssertEqual(SoundRecipe.envelopePeak([a, b]), 0.2, accuracy: 1e-12, "полки совпали — складываются")
        b.at = 1
        XCTAssertEqual(SoundRecipe.envelopePeak([a, b]), 0.1, accuracy: 1e-12)
        let n = SoundRecipe.normalized([a, b], to: 0.03)
        XCTAssertEqual(SoundRecipe.perceived(n), 0.03, accuracy: 1e-12)
        XCTAssertEqual(n[0].gain, n[1].gain, accuracy: 1e-12, "соотношение нот то же")
        XCTAssertEqual(n[0].env.length, e.length, accuracy: 1e-12, "длина та же")
        // Резкий подъём смягчён за счёт полки.
        let sharp = SoundRecipe.normalized([Tone(.sine, 440, env: Envelope(attack: 0.001, hold: 0.02, release: 0.1), gain: 0.1)], to: 0.03)
        XCTAssertEqual(sharp[0].env.attack, SoundRecipe.softAttack, accuracy: 1e-12)
        XCTAssertEqual(sharp[0].env.length, 0.121, accuracy: 1e-12)
    }

    /// Слышимая громкость в рендере: обычные звуки одного уровня — разброс по RMS не больше 25 % (до волны 49 — в 4 раза).
    func testRenderedLoudnessIsEven() {
        var rms: [String: Double] = [:]
        for cue in SoundTests.allCues where SoundRecipe.loudness(cue) == SoundRecipe.level {
            rms["\(cue)"] = Self.loudness(SoundRecipe.tones(cue))
        }
        let lo = rms.values.min()!, hi = rms.values.max()!
        XCTAssertLessThanOrEqual(hi / lo, 1.25, "разброс громкости: \(rms.sorted { $0.value < $1.value })")
        // Хруст еды не громче обычного звука.
        XCTAssertLessThanOrEqual(Self.loudness(SoundRecipe.eat(from: 0, to: 1)), hi)
    }

    /// RMS 50-мс окна с наибольшей энергией: так ухо слышит короткий звук.
    static func loudness(_ tones: [Tone]) -> Double {
        let core = SynthCore()
        core.push(tones)
        let block = 256
        let frames = Int(0.8 * core.sampleRate)
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: block)
        defer { buf.deallocate() }
        var s: [Float] = []
        while s.count < frames {
            _ = core.render(into: buf, frames: block)
            s.append(contentsOf: UnsafeBufferPointer(start: buf, count: block))
        }
        let win = Int(0.05 * core.sampleRate)
        var best = 0.0, sum = 0.0
        for i in s.indices {
            sum += Double(s[i] * s[i])
            if i >= win { sum -= Double(s[i - win] * s[i - win]) }
            best = max(best, sum)
        }
        return (best / Double(win)).squareRoot()
    }
}
