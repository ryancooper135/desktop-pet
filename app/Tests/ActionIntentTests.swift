// PetAction ↔ Action ядра и JSON, источники действий, тексты отказов и source у интентов.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let aAll: [PetAction] = [.feed("kibble"), .feed("fish"), .item("vitamin"), .pet, .play, .bath, .wake, .steps(0), .steps(1200)]

final class ActionIntentTests: XCTestCase {

    func testCoreRoundTrip() {
        for a in aAll {
            XCTAssertEqual(PetAction(a.core), a)
        }
    }

    func testKindKeyValueRoundTrip() {
        for a in aAll {
            XCTAssertEqual(PetAction(kind: a.kind, key: a.key, value: a.value), a, "\(a)")
        }
        XCTAssertEqual(PetAction.feed("fish").kind, "feed")
        XCTAssertEqual(PetAction.item("vitamin").kind, "item")
        XCTAssertEqual(PetAction.steps(5).kind, "steps")
        XCTAssertEqual(PetAction.wake.kind, "wake")
        XCTAssertNil(PetAction.pet.key)
        XCTAssertNil(PetAction.feed("fish").value)
        XCTAssertEqual(PetAction.steps(7).value, 7)
    }

    func testJSONRoundTrip() throws {
        let data = try JSONEncoder().encode(aAll)
        XCTAssertEqual(try JSONDecoder().decode([PetAction].self, from: data), aAll)
    }

    func testKindDefaultsAndUnknown() {
        XCTAssertEqual(PetAction(kind: "feed", key: nil, value: nil), .feed(Catalog.mainFood))
        XCTAssertEqual(PetAction(kind: "item", key: nil, value: nil), .item(Catalog.healItem))
        XCTAssertEqual(PetAction(kind: "steps", key: nil, value: nil), .steps(0))
        XCTAssertEqual(PetAction(kind: "pet", key: "лишнее", value: 3), .pet, "лишние поля не мешают")
        for bad in ["", "Feed", "dance", "act.feed", "heal"] {
            XCTAssertNil(PetAction(kind: bad, key: nil, value: nil), bad)
        }
    }

    func testActionSource() {
        XCTAssertEqual(ActionSource.allCases.map(\.rawValue),
                       ["app", "widget", "island", "control", "shortcut", "notification", "steps"],
                       "rawValue пишутся в журнал — менять нельзя")
        XCTAssertNil(ActionSource(rawValue: "siri"))
        XCTAssertEqual(ActionSource(rawValue: "siri") ?? .shortcut, .shortcut, "как в perform() интентов")
    }

    func testRefuseTexts() {
        let expect: [String: String] = [
            "dead": "Шибы больше нет",
            "bathing": "Сначала домоемся",
            "cooldown": "Чуть позже, только что было",
            "asleep": "Спит. Пусть поспит",
            "tired": "Сил нет играть, пусть отдохнёт",
            "not_napping": "Он и так не спит",
            "unknown_item": "Такого у нас нет",
            "store": "Не получилось сохранить",
        ]
        for (reason, text) in expect {
            XCTAssertEqual(RefuseText.text(reason), text)
        }
        XCTAssertEqual(RefuseText.text(nil), "Не вышло")
        XCTAssertEqual(RefuseText.text("что-то новое"), "Не вышло")
        XCTAssertEqual(ActOutcome.storeFailed, ActOutcome(ok: false, reason: "store"))
    }

    /// Отказы ядра, которые реально бывают, — у каждого свой текст, не «Не вышло».
    func testCoreRefusalsHaveTexts() {
        let r = Catalog.rules
        let o = Owner(bedMin: r.bedMin, wakeMin: r.wakeMin, tzOffsetMin: 0)
        let t0: Double = 1_760_000_000
        var reasons: Set<String> = []

        var s = PetEngine.newPet(r, t: t0)
        _ = PetEngine.act(&s, r, o, .pet)
        reasons.insert(PetEngine.act(&s, r, o, .pet).reason ?? "")                   // cooldown
        reasons.insert(PetEngine.act(&s, r, o, .wake).reason ?? "")                  // not_napping
        reasons.insert(PetEngine.act(&s, r, o, .feed("нет-такого")).reason ?? "")    // unknown_item
        _ = PetEngine.act(&s, r, o, .bath)
        reasons.insert(PetEngine.act(&s, r, o, .bath).reason ?? "")                  // bathing
        var dead = PetEngine.newPet(r, t: t0)
        dead.alive = false
        reasons.insert(PetEngine.act(&dead, r, o, .pet).reason ?? "")                // dead

        XCTAssertEqual(reasons, ["cooldown", "not_napping", "unknown_item", "bathing", "dead"])
        for reason in reasons {
            XCTAssertNotEqual(RefuseText.text(reason), "Не вышло", reason)
        }
    }

    @MainActor
    func testIntentsKeepSource() {
        XCTAssertEqual(FeedIntent(.widget).source, "widget")
        XCTAssertEqual(PetIntent(.island).source, "island")
        XCTAssertEqual(BathIntent(.control).source, "control")
        XCTAssertEqual(WakeIntent(.notification).source, "notification")
        XCTAssertEqual(MainActionIntent(.widget).source, "widget")
        XCTAssertEqual(PlayIntent(.island).source, "island")
        XCTAssertEqual(StartIslandIntent(.app).source, "app")
    }
}
