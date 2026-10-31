// Волна 19, «понятность»: знакомство при первом запуске (Onboarding), легенда ряда значков, пояснения кошелька
// и шерсти. Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore; исходники App читаются текстом.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

final class ClarityTests: XCTestCase {

    // MARK: когда показывать знакомство

    func testIntroShownOnceToAlivePet() {
        var log = TipLog()
        XCTAssertTrue(Onboarding.shouldShowIntro(tips: log, alive: true), "новичку — показать")
        XCTAssertFalse(Onboarding.shouldShowIntro(tips: log, alive: false), "мёртвому щенку — нет")
        Tips.markSeen(&log, Onboarding.introKey)
        XCTAssertFalse(Onboarding.shouldShowIntro(tips: log, alive: true), "второй раз — нет")
        Tips.markSeen(&log, Onboarding.introKey)
        XCTAssertEqual(log.seen.filter { $0 == Onboarding.introKey }.count, 1, "ключ не дублируется")
    }

    /// Уже игравший до волны 19 (есть поглаживания и выученные жесты) тоже видит знакомство один раз.
    func testIntroShownToOldPlayerToo() {
        let log = TipLog(strokes: 12, lastStrokeT: 1_760_000_000, seen: ["tickle", "swipe"])
        XCTAssertTrue(Onboarding.shouldShowIntro(tips: log, alive: true))
    }

    /// Отметка «знакомство показано» сохраняется в файле и переживает «Начать заново» (tips — знание хозяина).
    func testIntroSeenSurvivesSaveRoundTrip() throws {
        var f = SaveFile.fresh(now: 1_760_000_000)
        Tips.markSeen(&f.tips, Onboarding.introKey)
        let back = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertFalse(Onboarding.shouldShowIntro(tips: back.tips, alive: true))
    }

    func testGuideKindHasIntro() {
        XCTAssertEqual(GuideKind(rawValue: "intro"), .intro, "PET_GUIDE=intro для скриншота")
    }

    // MARK: текст знакомства

    func testIntroPagesShortAndFilled() {
        let pages = Onboarding.pages(name: "Бублик")
        XCTAssertFalse(pages.isEmpty)
        XCTAssertLessThanOrEqual(pages.count, Onboarding.maxPages, "не больше трёх карточек")
        XCTAssertEqual(Set(pages.map(\.id)).count, pages.count, "id карточек разные")
        XCTAssertTrue(pages[0].title.contains("Бублик"), "имя питомца в первой карточке")
        for p in pages {
            XCTAssertFalse(p.title.isEmpty)
            XCTAssertFalse(p.text.isEmpty)
            XCTAssertFalse(p.rows.isEmpty, "\(p.id): без строчек")
            XCTAssertLessThanOrEqual(p.text.count, 160, "\(p.id): текст длинный")
            XCTAssertEqual(Set(p.rows.map(\.id)).count, p.rows.count, "\(p.id): id строчек разные")
            for r in p.rows {
                XCTAssertFalse(r.icon.isEmpty && r.emoji.isEmpty, "\(r.id): ни значка, ни эмодзи")
                XCTAssertFalse(r.title.isEmpty)
                XCTAssertLessThanOrEqual(r.text.count, 70, "\(r.id): строчка длинная")
                for s in [r.title, r.text] {
                    XCTAssertFalse(s.contains("{"), "\(r.id): незаполненная подстановка")
                    XCTAssertFalse(s.contains("Шиба"), "\(r.id): имя не должно быть зашито")
                }
            }
        }
    }

    /// Легенда ряда — те же значки, что на самих кнопках, и в том же порядке, что в WalkRow.
    func testRowLegendMatchesButtons() throws {
        let app = try appSources()
        for r in Onboarding.rowLegend {
            XCTAssertTrue(app.contains("systemName: \"\(r.icon)\""), "\(r.id): значка \(r.icon) нет на кнопках")
        }
        XCTAssertEqual(Onboarding.rowLegend.map(\.id), ["album", "capsule", "house", "tricks", "games", "walk"])
    }

    /// Кнопки ухода в карточке — те же значки и подписи, что в панели (ActButton в ActionBar).
    func testCareRowsMatchActionBar() throws {
        let home = try appSource("ActionBar.swift")
        let care = Onboarding.pages(name: "Шиба").first { $0.id == "care" }
        let rows = try XCTUnwrap(care).rows.filter { $0.id != "needs" }
        XCTAssertEqual(rows.count, 4)
        for r in rows {
            XCTAssertTrue(home.contains("ActButton(title: \"\(r.title)\", icon: \"\(r.icon)\""), "\(r.id): нет такой кнопки")
        }
    }

    // MARK: пояснения на экранах

    func testWalletLegendNamesAllThree() {
        for s in ["🪙", "🎟", "✂️", "монеты", "билетик", "клочки"] {
            XCTAssertTrue(Onboarding.walletLegend.contains(s), "нет «\(s)»")
        }
    }

    func testCoatLineSaysWhereToBrush() {
        XCTAssertTrue(Onboarding.coatLine(.matted).hasSuffix("расчеши в «Командах»"))
        XCTAssertTrue(Onboarding.coatLine(.shaggy).contains("Командах"))
        XCTAssertEqual(Onboarding.coatLine(.normal), "Шерсть: обычный")
        XCTAssertFalse(Onboarding.coatLine(.sleek).contains("Командах"))
        XCTAssertTrue(Onboarding.coatLine(.matted).hasPrefix("Шерсть: колтуны"))
    }

    // MARK: помощники

    private func appDir() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App")
    }

    private func appSource(_ name: String) throws -> String {
        let url = appDir().appendingPathComponent(name)
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { throw XCTSkip("нет исходника \(name)") }
        return s
    }

    private func appSources() throws -> String {
        let names = ["WalkViews.swift", "HouseScreen.swift", "TricksScreen.swift", "CatchGameScreen.swift"]
        return try names.map(appSource).joined(separator: "\n")
    }
}
