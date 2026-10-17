// Файл сохранения: старые и неполные JSON, лишние ключи, опционалы питомца, журнал и outbox.
// Только в памяти, диск не трогаем.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let sfT0: Double = 1_760_000_000

private func sfObject(_ f: SaveFile) throws -> [String: Any] {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    let data = try enc.encode(f)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func sfDecodeObject(_ obj: [String: Any]) throws -> SaveFile {
    try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
}

private func sfEntry(_ kind: String, key: String? = nil, value: Int? = nil) -> JournalEntry {
    JournalEntry(id: "d:1", t: sfT0, kind: kind, source: nil, ok: true, reason: nil, key: key, value: value)
}

final class SaveFileCoverageTests: XCTestCase {

    // MARK: старые и неполные файлы

    func testMinimalFileWithOnlyPet() throws {
        let f = SaveFile.fresh(now: sfT0)
        let pet = try XCTUnwrap(try sfObject(f)["pet"])
        let d = try sfDecodeObject(["pet": pet])

        XCTAssertEqual(d.pet, f.pet, "питомец читается как был")
        XCTAssertEqual(d.v, SaveFile.version)
        XCTAssertEqual(d.rev, 0)
        XCTAssertEqual(d.seq, 0)
        XCTAssertEqual(d.name, "Шиба")
        XCTAssertEqual(d.createdT, f.pet.t, "createdT по умолчанию — время питомца")
        XCTAssertEqual(d.owner, PetEngine.defaultOwner(Catalog.rules, tzOffsetMin: Clock.tzOffsetMin(at: f.pet.t)))
        XCTAssertFalse(d.petId.isEmpty)
        XCTAssertFalse(d.deviceId.isEmpty)
        XCTAssertNil(d.seen)
        XCTAssertNil(d.lastSeenT)
        XCTAssertNil(d.lastStepsT)
        XCTAssertNil(d.lastAction)
        XCTAssertNil(d.build)
        XCTAssertNil(d.debugMarker)
        XCTAssertTrue(d.journal.isEmpty)
        XCTAssertTrue(d.outbox.isEmpty)
        XCTAssertEqual(d.island, SaveFile.IslandInfo())
        XCTAssertEqual(d.flags, SaveFile.Flags())
        XCTAssertEqual(d.notif, SaveFile.NotifInfo())
    }

    func testOldFileWithoutNewerSections() throws {
        var f = SaveFile.fresh(now: sfT0)
        f.rev = 12
        f.log("act.pet", t: sfT0 + 5, source: .app, ok: true)
        var obj = try sfObject(f)
        for k in ["island", "flags", "notif", "build", "outbox", "lastStepsT", "debugMarker", "seen", "lastAction"] {
            obj.removeValue(forKey: k)
        }
        let d = try sfDecodeObject(obj)
        XCTAssertEqual(d.petId, f.petId)
        XCTAssertEqual(d.deviceId, f.deviceId)
        XCTAssertEqual(d.rev, 12)
        XCTAssertEqual(d.seq, f.seq)
        XCTAssertEqual(d.journal, f.journal)
        XCTAssertTrue(d.outbox.isEmpty)
        XCTAssertTrue(d.island.enabled)
        XCTAssertEqual(d.notif, SaveFile.NotifInfo())
    }

    func testNullScalarsFallBackToDefaults() throws {
        let f = SaveFile.fresh(now: sfT0)
        var obj = try sfObject(f)
        obj["rev"] = NSNull()
        obj["seq"] = NSNull()
        obj["name"] = NSNull()
        obj["lastSeenT"] = NSNull()
        obj["createdT"] = NSNull()
        obj["owner"] = NSNull()
        let d = try sfDecodeObject(obj)
        XCTAssertEqual(d.rev, 0)
        XCTAssertEqual(d.seq, 0)
        XCTAssertEqual(d.name, "Шиба")
        XCTAssertNil(d.lastSeenT)
        XCTAssertEqual(d.createdT, f.pet.t)
        XCTAssertEqual(d.petId, f.petId)
    }

    func testUnknownKeysIgnoredAndDropped() throws {
        let f = SaveFile.fresh(now: sfT0)
        var obj = try sfObject(f)
        obj["future"] = ["friends": [1, 2, 3]]
        obj["v"] = 99
        let d = try sfDecodeObject(obj)
        XCTAssertEqual(d.petId, f.petId)
        XCTAssertEqual(d.v, 99, "версию из файла не затираем")
        XCTAssertNil(try sfObject(d)["future"], "чужие ключи при записи не тащим")
    }

    func testBrokenPetIsReadError() throws {
        let f = SaveFile.fresh(now: sfT0)
        let bad: [(String, Any)] = [
            ("null", NSNull()),
            ("строка", "собака"),
            ("пустой объект", [String: Any]()),
            ("массив", [1, 2]),
            ("без alive", ["t": sfT0, "hearts": 5]),
        ]
        for (name, value) in bad {
            var obj = try sfObject(f)
            obj["pet"] = value
            XCTAssertThrowsError(try sfDecodeObject(obj), "\(name): битый питомец — ошибка чтения, а не мёртвый щенок")
        }
    }

    func testDeadPetStillDecodes() throws {
        var f = SaveFile.fresh(now: sfT0)
        f.pet.alive = false
        f.pet.hearts = 0
        f.pet.diedAt = sfT0
        f.pet.cause = .starve
        let d = try sfDecodeObject(sfObject(f))
        XCTAssertFalse(d.pet.alive)
        XCTAssertEqual(d.pet.hearts, 0)
        XCTAssertEqual(d.pet.cause, .starve)
    }

    // MARK: PetCodec

    func testPetCodecKeepsOptionals() throws {
        var f = SaveFile.fresh(now: sfT0)
        f.pet.napUntil = sfT0 + 600
        f.pet.bathUntil = sfT0 + 900
        f.pet.lastChanceH = 3.5
        f.pet.lastHeartLossT = sfT0 - 7200
        f.pet.cooldowns = ["pet": sfT0 + 180, "vitamin": sfT0 + 86400]
        f.pet.home[.bath] = 2
        f.pet.home[.kennel] = 1
        f.pet.grace[.dirty] = 3.25
        f.pet.cause = .dirty
        f.seen = f.pet
        f.owner = Owner(bedMin: 60, wakeMin: 600, tzOffsetMin: -300)
        let d = try sfDecodeObject(sfObject(f))
        XCTAssertEqual(d.pet, f.pet)
        XCTAssertEqual(d.seen, f.seen)
        XCTAssertEqual(d.owner, f.owner)
    }

    func testFreshPetSurvivesCodecExactly() {
        let f = SaveFile.fresh(now: sfT0)
        XCTAssertEqual(PetState(json: PetCodec.json(f.pet)), f.pet)
        XCTAssertEqual(Owner(json: PetCodec.json(f.owner)), f.owner)
    }

    // MARK: fresh

    func testFreshInvariants() {
        let f = SaveFile.fresh(now: sfT0)
        let r = Catalog.rules
        XCTAssertEqual(f.createdT, sfT0)
        XCTAssertEqual(f.pet.t, sfT0)
        XCTAssertEqual(f.seen, f.pet)
        XCTAssertEqual(f.lastSeenT, sfT0)
        XCTAssertEqual(f.rev, 0)
        XCTAssertEqual(f.seq, 0)
        XCTAssertTrue(f.pet.alive)
        XCTAssertEqual(f.pet.hearts, r.heartsMax)
        XCTAssertEqual(f.owner.bedMin, r.bedMin)
        XCTAssertEqual(f.owner.wakeMin, r.wakeMin)
        XCTAssertEqual(f.owner.tzOffsetMin, Clock.tzOffsetMin(at: sfT0))
        XCTAssertNotEqual(f.petId, SaveFile.fresh(now: sfT0).petId, "у каждого щенка свой id")
        XCTAssertNotEqual(f.petId, f.deviceId)
    }

    // MARK: журнал

    func testLogIdsAndFields() {
        var f = SaveFile.fresh(now: sfT0)
        f.log("act.feed", t: sfT0 + 1, source: .widget, ok: true, key: "fish")
        f.log("set_bed", t: sfT0 + 2, value: 1410)
        XCTAssertEqual(f.journal.map(\.id), ["\(f.deviceId):1", "\(f.deviceId):2"])
        XCTAssertEqual(f.journal[0].source, .widget)
        XCTAssertEqual(f.journal[0].key, "fish")
        XCTAssertNil(f.journal[1].source)
        XCTAssertNil(f.journal[1].ok)
        XCTAssertEqual(f.journal[1].value, 1410)
        XCTAssertEqual(f.outbox, f.journal)
    }

    func testOutboxTrimmedTo500() {
        var f = SaveFile.fresh(now: sfT0)
        for i in 0..<520 { f.log("act.pet", t: sfT0 + Double(i), source: .app, ok: true) }
        XCTAssertEqual(SaveFile.outboxMax, 500)
        XCTAssertEqual(f.outbox.count, 500)
        XCTAssertEqual(f.outbox.first?.id, "\(f.deviceId):21")
        XCTAssertEqual(f.outbox.last?.id, "\(f.deviceId):520")
        XCTAssertEqual(f.journal.count, SaveFile.journalMax)
    }

    func testTimedActsWindowAndFilter() {
        var f = SaveFile.fresh(now: sfT0)
        f.log("act.feed", t: sfT0 + 10, source: .widget, ok: true, key: "kibble")
        f.log("act.pet", t: sfT0 + 20, source: .island, ok: false, reason: "cooldown")
        f.log("ev.low.food", t: sfT0 + 30, key: "food")
        f.log("act.steps", t: sfT0 + 40, source: .steps, ok: true, value: 800)
        f.log("act.play", t: sfT0 + 50, source: .app)
        f.log("act.dance", t: sfT0 + 60, source: .app, ok: true)

        // Окно (from, to]: левая граница не входит, правая входит.
        XCTAssertEqual(f.timedActs(from: sfT0 + 10, to: sfT0 + 40), [TimedAct(t: sfT0 + 40, action: .steps(800))])
        let all = f.timedActs(from: sfT0, to: sfT0 + 100)
        XCTAssertEqual(all.map(\.t), [sfT0 + 10, sfT0 + 40], "только удачные act.* известных типов")
        XCTAssertEqual(all.first?.action, .feed("kibble"))
        XCTAssertTrue(f.timedActs(from: sfT0 + 100, to: sfT0 + 200).isEmpty)
    }

    func testJournalEntryAction() {
        XCTAssertEqual(sfEntry("act.feed", key: "fish").action, .feed("fish"))
        XCTAssertEqual(sfEntry("act.feed").action, .feed(Catalog.mainFood))
        XCTAssertEqual(sfEntry("act.item").action, .item(Catalog.healItem))
        XCTAssertEqual(sfEntry("act.item", key: "soap").action, .item("soap"))
        XCTAssertEqual(sfEntry("act.steps", value: 1200).action, .steps(1200))
        XCTAssertEqual(sfEntry("act.steps").action, .steps(0))
        XCTAssertEqual(sfEntry("act.pet").action, .pet)
        XCTAssertEqual(sfEntry("act.play").action, .play)
        XCTAssertEqual(sfEntry("act.bath").action, .bath)
        XCTAssertEqual(sfEntry("act.wake").action, .wake)
        XCTAssertNil(sfEntry("act.dance").action)
        XCTAssertNil(sfEntry("act.").action)
        XCTAssertNil(sfEntry("ev.low.food", key: "food").action)
        XCTAssertNil(sfEntry("clock_back").action)
        XCTAssertNil(sfEntry("feed").action, "без префикса act. — не действие")
    }
}
