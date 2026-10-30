// Волна 30: охота на баги. Каждый тест — регрессия найденного бага (RESEARCH/16-bugs.md): сначала падал, потом починили.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000: днём пёс не спит.
private let bT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

private func bFile(at t: Double = bT0, level: Double = 60) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = "bughunt-pet-1"
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = level }
    return f
}

final class BugHuntTests: XCTestCase {

    // MARK: ссылка pet://shop / pet://kitchen: второй шаг после того, как автомат или «Дом» уже закрыли

    func testDeepLinkFollowUpOnlyForNestedSheets() {
        XCTAssertEqual(DeepLink.followUp("shop")?.parent, "capsule")
        XCTAssertEqual(DeepLink.followUp("shop")?.child, "shop")
        XCTAssertEqual(DeepLink.followUp("kitchen")?.parent, "house")
        XCTAssertEqual(DeepLink.followUp("kitchen")?.child, "kitchen")
        for h in DeepLink.routes.subtracting(["shop", "kitchen"]) {
            XCTAssertNil(DeepLink.followUp(h), h)
        }
        XCTAssertNil(DeepLink.followUp(nil))
        XCTAssertNil(DeepLink.followUp("home"))
    }

    func testDeepLinkFollowUpNeedsParentStillOpen() {
        // pet://shop: автомат открыт — через 0.8 с лавка поверх него.
        XCTAssertTrue(DeepLink.mayFollow("shop", open: ["capsule"]))
        XCTAssertTrue(DeepLink.mayFollow("kitchen", open: ["house"]))
        // Автомат успели закрыть (свайп, pet://home, другая ссылка) — лавку не открывать: её лист висит внутри
        // автомата, флаг остался бы true без листа (anyCover держит подсказки, лавка выскочит при следующем автомате).
        XCTAssertFalse(DeepLink.mayFollow("shop", open: []))
        XCTAssertFalse(DeepLink.mayFollow("kitchen", open: []))
        // Пока ждали, открыли чужое — тоже нет.
        XCTAssertFalse(DeepLink.mayFollow("shop", open: ["needs"]))
        XCTAssertFalse(DeepLink.mayFollow("shop", open: ["capsule", "needs"]))
        XCTAssertFalse(DeepLink.mayFollow("kitchen", open: ["capsule"]))
        // Лавка уже открыта (кнопкой в автомате) — второй раз нечего.
        XCTAssertFalse(DeepLink.mayFollow("shop", open: ["capsule", "shop"]))
        // У простых целей второго шага нет.
        XCTAssertFalse(DeepLink.mayFollow("needs", open: ["needs"]))
        XCTAssertFalse(DeepLink.mayFollow(nil, open: []))
    }
}
