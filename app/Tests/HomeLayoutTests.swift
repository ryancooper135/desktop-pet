// Раскладка главного экрана без рендера: миска в кадре портретной камеры, равные кнопки панели и общий кегль подписей.

import CoreGraphics
import Foundation
import simd
import XCTest
@testable import Pet

final class HomeLayoutTests: XCTestCase {

    // MARK: миска в кадре

    /// Портрет iPhone (ширина / высота). Узкий экран — худший случай по ширине.
    private static let portraitAspects: [Float] = [390.0 / 844.0, 420.0 / 912.0, 440.0 / 956.0]

    /// x в NDC (-1…1) для точки мира при камере PetRoom; FOV вертикальный.
    @MainActor
    private func ndcX(_ p: SIMD3<Float>, aspect: Float) -> Float {
        let eye = PetRoom.cameraEye
        let f = simd_normalize(PetRoom.cameraTarget - eye)
        let r = simd_normalize(simd_cross(f, SIMD3<Float>(0, 1, 0)))
        let d = p - eye
        let depth = simd_dot(d, f)
        let half = tan(PetRoom.cameraFov * .pi / 180 / 2)
        return simd_dot(d, r) / (depth * half * aspect)
    }

    @MainActor
    func testBowlFullyInPortraitFrame() {
        let c = PetRoom.bowlPos
        let rad = PetRoom.bowlRadius
        var edge: [SIMD3<Float>] = []
        for a in stride(from: Float(0), to: 2 * .pi, by: .pi / 8) {
            for y: Float in [-0.025, 0.025] {
                edge.append(c + SIMD3<Float>(rad * cos(a), y, rad * sin(a)))
            }
        }
        for aspect in Self.portraitAspects {
            let xs = edge.map { ndcX($0, aspect: aspect) }
            // 0.95 — запас ~10 pt до края экрана, чтобы миску не резало и на узком айфоне.
            XCTAssertGreaterThan(xs.min() ?? -9, -0.95, "миска режется слева при aspect \(aspect)")
            XCTAssertLessThan(xs.max() ?? 9, 0.95, "миска режется справа при aspect \(aspect)")
        }
    }

    // MARK: панель действий

    @MainActor
    func testTitlesMatchBarOrder() {
        XCTAssertEqual(ActionBar.titles(nap: false, lamp: false), ["Покормить", "Погладить", "Поиграть", "Помыть"])
        XCTAssertEqual(ActionBar.titles(nap: true, lamp: true).first, "Разбудить")
        XCTAssertEqual(ActionBar.titles(nap: true, lamp: true).last, "Отбой")
        XCTAssertEqual(ActionBar.titles(nap: true, lamp: true).count, 6)
    }

    @MainActor
    func testCellsAreEqualAndFillBar() {
        let total: CGFloat = 388
        for n in 4...6 {
            let cell = ActionBar.cellWidth(total: total, count: n)
            XCTAssertEqual(cell * CGFloat(n) + ActionBar.spacing * CGFloat(n - 1), total, accuracy: 0.01)
        }
        XCTAssertEqual(ActionBar.cellWidth(total: 0, count: 5), 0)
    }

    @MainActor
    func testOneLabelSizeFitsLongestTitle() {
        let titles = ActionBar.titles(nap: true, lamp: true)
        // Широкая ячейка: базовый кегль не трогаем.
        XCTAssertEqual(ActionBar.labelSize(titles: titles, cellWidth: 200, maxSize: 13), 13)
        // Ширина ещё не измерена: тоже базовый.
        XCTAssertEqual(ActionBar.labelSize(titles: titles, cellWidth: 0, maxSize: 13), 13)
        // Узкая ячейка (6 кнопок на 390 pt): кегль меньше, но самая длинная подпись влезает.
        let cell = ActionBar.cellWidth(total: 358, count: 6)
        let size = ActionBar.labelSize(titles: titles, cellWidth: cell, maxSize: 13)
        XCTAssertLessThan(size, 13)
        XCTAssertGreaterThanOrEqual(size, 8)
        let widest = titles.map { ActionBar.labelWidth($0, size: size) }.max() ?? 0
        if size > 8 { XCTAssertLessThanOrEqual(widest, cell - 10) }
        // Крупный Dynamic Type упирается в ширину ячейки, а не в базу.
        XCTAssertLessThanOrEqual(ActionBar.labelWidth("Покормить",
                                                      size: ActionBar.labelSize(titles: titles, cellWidth: 80, maxSize: 30)),
                                 80 - 10)
    }

    /// Подписи не режутся ни на iPhone Air (420 pt, ряд 388), ни на iPhone SE (375 pt, ряд 343),
    /// ни при Dynamic Type крупнее обычного: самая длинная подпись влезает в ячейку с полями.
    @MainActor
    func testRowFitsAirAndSE() {
        for total: CGFloat in [388, 358, 343] {
            for titles in [ActionBar.titles(nap: false, lamp: false), ActionBar.titles(nap: false, lamp: true),
                           ActionBar.titles(nap: true, lamp: true)] {
                for base: CGFloat in [13, 15, 17, 20] {
                    let fit = ActionBar.fit(titles: titles, total: total, maxSize: base)
                    XCTAssertEqual(fit.cell * CGFloat(titles.count) + fit.spacing * CGFloat(titles.count - 1), total, accuracy: 0.01)
                    let widest = titles.map { ActionBar.labelWidth($0, size: fit.label) }.max() ?? 0
                    // В кнопке поля по 2 pt; minimumScaleFactor — только страховка, без неё должно влезать.
                    XCTAssertLessThanOrEqual(widest, fit.cell - 4, "\(total) pt, \(titles.count) кнопок, база \(base)")
                    XCTAssertGreaterThanOrEqual(fit.label, 8)
                    XCTAssertLessThanOrEqual(fit.label, base)
                }
            }
        }
    }

    /// Днём на iPhone Air (4 кнопки) зазор обычный и кегль базовый; узкий зазор — только когда тесно.
    @MainActor
    func testTightSpacingOnlyWhenCramped() {
        let day = ActionBar.fit(titles: ActionBar.titles(nap: false, lamp: false), total: 388, maxSize: 13)
        XCTAssertEqual(day.spacing, ActionBar.spacing)
        XCTAssertEqual(day.label, 13)
        let se = ActionBar.fit(titles: ActionBar.titles(nap: true, lamp: true), total: 343, maxSize: 13)
        XCTAssertEqual(se.spacing, ActionBar.tightSpacing)
    }
}
