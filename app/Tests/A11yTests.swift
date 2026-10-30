// Волна 31 «для всех»: слова VoiceOver и правила движения/шрифта из Shared/A11y.swift. Гоняются и на Linux.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

final class A11yTests: XCTestCase {

    private func snap(pose: Pose = .idle, want: String? = nil, thought: String? = nil,
                      needs: [Need: Double] = [:], alive: Bool = true, name: String = PetNames.shiba) -> PetSnapshot {
        PetSnapshot(t: 0, name: name, pose: pose, mood: "ok", want: want, wantIcon: nil, wantText: thought, urgent: false,
                    line: "", islandLine: "", hearts: 3, heartsMax: 5, level: 0, main: .pet, timer: nil,
                    needs: needs, alive: alive, buildDaysLeft: nil, shared: false)
    }

    // MARK: сцена

    func testPercentIsClampedWholeNumber() {
        XCTAssertEqual(A11y.percent(69.6), 70)
        XCTAssertEqual(A11y.percent(-3), 0)
        XCTAssertEqual(A11y.percent(140), 100)
        XCTAssertEqual(A11y.percent(.nan), 0)
    }

    func testEveryCoreWantHasVerbPhrase() {
        for w in WantKey.allCases {
            let p = A11y.wantPhrase(w.rawValue)
            XCTAssertNotNil(p, "нет фразы для желания \(w.rawValue)")
            XCTAssertTrue(p?.hasPrefix("хочет ") ?? false, "\(w.rawValue): \(p ?? "")")
        }
        XCTAssertEqual(A11y.wantPhrase("play"), "хочет играть")
        XCTAssertEqual(A11y.wantPhrase("pet"), "хочет ласки")
    }

    func testUnknownWantFallsBackToThought() {
        XCTAssertEqual(A11y.wantPhrase("treat", thought: "Вкусняшку?"), "хочет: вкусняшку?")
        XCTAssertNil(A11y.wantPhrase(nil, thought: "  "))
        XCTAssertNil(A11y.wantPhrase(nil))
    }

    func testNeedsLineUsesSheetOrderAndNames() {
        let line = A11y.needsLine([.fun: 20, .food: 70.4, .love: 90, .clean: 40])
        XCTAssertEqual(line, "сытость 70 %, чистота 40 %, настроение 20 %, ласка 90 %")
    }

    func testNeedOrderMatchesSheetBars() {
        // Тот же порядок, что VisibleNeeds.all в листе шкал (Shared/Views/Components.swift) — сверяем по исходнику.
        let src = try? String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Shared/Views/Components.swift"), encoding: .utf8)
        guard let src else { return XCTFail("нет Components.swift") }
        XCTAssertTrue(src.contains("static let all: [Need] = [.food, .clean, .energy, .fun, .love, .walk]"),
                      "VisibleNeeds.all поменялся — поправь A11y.needOrder")
        XCTAssertEqual(A11y.needOrder, [.food, .clean, .energy, .fun, .love, .walk])
    }

    func testStageValueSaysWantThenNeeds() {
        let s = snap(want: "play", needs: [.food: 70, .fun: 20])
        XCTAssertEqual(A11y.stageValue(s), "хочет играть; сытость 70 %, настроение 20 %")
        XCTAssertEqual(A11y.stageValue(snap(needs: [.food: 70])), "сытость 70 %", "без желания — только шкалы")
        XCTAssertEqual(A11y.stageValue(snap(want: "food", needs: [.food: 5], alive: false)), "", "ушедшему — пусто")
    }

    func testStageValueHasNoGenderedWords() {
        // Свой персонаж может быть кем угодно: в сводке нет «сыт», «голоден», «соскучился».
        for w in WantKey.allCases {
            let v = A11y.stageValue(snap(want: w.rawValue, needs: [.food: 50]))
            for bad in ["сыт ", "голоден", "соскучил", "устал", "грязн"] {
                XCTAssertFalse(v.contains(bad), "\(w.rawValue): «\(v)» содержит «\(bad)»")
            }
        }
    }

    func testStageActsFollowPanel() {
        XCTAssertEqual(A11y.stageActs(pose: .idle, alive: true).map(\.title), ["Покормить", "Погладить", "Поиграть", "Помыть"])
        XCTAssertEqual(A11y.stageActs(pose: .nap, alive: true).first, .wake, "дрёма — сначала «Разбудить», как на панели")
        XCTAssertFalse(A11y.stageActs(pose: .sleep, alive: true).contains(.wake), "ночной сон не будим со сцены")
        XCTAssertEqual(A11y.stageActs(pose: .dead, alive: false), [])
        XCTAssertEqual(A11y.stageActs(pose: .idle, alive: false), [])
    }

    func testStageActTitlesMatchActionBar() throws {
        // Названия — как подписи ActionBar: VoiceOver-пользователь слышит те же слова, что видит зрячий.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/ActionBar.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        for a in A11y.StageAct.allCases {
            XCTAssertTrue(src.contains("title: \"\(a.title)\""), "нет кнопки «\(a.title)» в ActionBar")
        }
    }

    // MARK: мини-игры

    func testGameNotesArePoliteAndAdaptable() {
        for g in A11y.Game.allCases {
            let n = A11y.gameNote(g)
            XCTAssertFalse(n.isEmpty)
            XCTAssertTrue(n.contains("VoiceOver"), "\(g): оговорка должна называть VoiceOver")
            XCTAssertTrue(n.hasSuffix(".") || n.hasSuffix("!"), "\(g): «\(n)»")
        }
        XCTAssertTrue(A11y.gameNote(.blockDuo).contains("Прости"))
        let custom = PetNames.adapt(A11y.gameNote(.catchBall), name: "Серый")
        XCTAssertFalse(custom.contains("Шиб"), "имя своего персонажа подставляется: \(custom)")
    }

    func testNudgeStepsAndStopsAtEdges() {
        let r = 0.11...0.89
        let up = A11y.nudge(0.5, up: true, range: r)
        XCTAssertEqual(up, 0.5 + 0.78 / 6, accuracy: 1e-9)
        XCTAssertEqual(A11y.nudge(0.88, up: true, range: r), 0.89, accuracy: 1e-9)
        XCTAssertEqual(A11y.nudge(0.12, up: false, range: r), 0.11, accuracy: 1e-9)
        XCTAssertEqual(A11y.nudge(0.3, up: true, range: 1...1), 0.3, "пустой ход — на месте")
        // Шесть шагов проходят весь ход.
        var x = r.lowerBound
        for _ in 0..<6 { x = A11y.nudge(x, up: true, range: r) }
        XCTAssertEqual(x, r.upperBound, accuracy: 1e-9)
    }

    func testSideWords() {
        let r = -1.0...1.0
        XCTAssertEqual(A11y.side(-1, in: r), "слева")
        XCTAssertEqual(A11y.side(-0.4, in: r), "левее середины")
        XCTAssertEqual(A11y.side(0, in: r), "посередине")
        XCTAssertEqual(A11y.side(0.4, in: r), "правее середины")
        XCTAssertEqual(A11y.side(1, in: r), "справа")
        XCTAssertEqual(A11y.side(5, in: 2...2), "посередине")
    }

    // MARK: движение и шрифт

    func testReduceMotionKeepsOnlyRestingStep() {
        let shake: [Double] = [0, -6, 6, -3, 0]
        XCTAssertEqual(A11y.steps(shake, reduce: false), shake)
        XCTAssertEqual(A11y.steps(shake, reduce: true), [0])
        XCTAssertEqual(A11y.steps([Double](), reduce: true), [])
    }

    func testScaledFontNeverShrinksAndIsCapped() {
        XCTAssertEqual(A11y.scaled(base: 14, scaled: 14), 14, "обычный размер — как было")
        XCTAssertEqual(A11y.scaled(base: 14, scaled: 11), 14, "мелкий шрифт системы не сжимает вёрстку")
        XCTAssertEqual(A11y.scaled(base: 14, scaled: 20), 20)
        XCTAssertEqual(A11y.scaled(base: 14, scaled: 60), 14 * A11y.fontCap)
        XCTAssertEqual(A11y.scaled(base: 14, scaled: .infinity), 14)
    }

    func testStyleRankIsMonotonic() {
        var last = -1
        for s in stride(from: 9.0, through: 26, by: 0.5) {
            let r = A11y.styleRank(size: s)
            XCTAssertGreaterThanOrEqual(r, last, "кегль \(s)")
            last = r
        }
        XCTAssertEqual(A11y.styleRank(size: 17), 4, "17 pt — body")
        XCTAssertEqual(A11y.styleRank(size: 12), 1, "12 pt — caption")
    }
}
