// Стор: порча файла без копий, пропажа файла, зеркало, откат mutate, параллельные записи.
// Каждый тест — своя временная папка; зеркало приложения сохраняется и возвращается StoreHooks.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let rT0: Double = 1_760_000_000

private struct RecoveryBoom: Error {}

private func rRemove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

private func rBrokenNames(_ dir: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix("state.broken-") }
}

final class PetStoreRecoveryTests: XCTestCase {

    func testCorruptWithoutBackupsIsError() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-recovery")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: rT0)
        rRemove(store.bakURL)
        rRemove(store.prevURL)
        rRemove(Paths.mirror)
        try Data("{ \"pet\": ".utf8).write(to: store.stateURL)

        XCTAssertThrowsError(try store.read()) { err in
            guard let se = err as? StoreError, case .corrupted = se else {
                return XCTFail("ждали StoreError.corrupted, пришло \(err)")
            }
        }
        // Волна 15: читатель (виджет) файлы не двигает — иначе следующий mutate видел пустую папку и молча заводил щенка.
        XCTAssertTrue(rBrokenNames(dir).isEmpty, "читатель ничего не откладывает")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.stateURL.path), "испорченный файл на месте")
        XCTAssertThrowsError(try store.read(), "и второй раз — та же ошибка, а не «первый запуск»")
    }

    func testMissingStateRecoversFromBakThenPrev() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-recovery")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: rT0)
        for i in 1...3 { try store.mutate { (f: inout SaveFile) -> Void in f.debugMarker = Double(i) } }
        rRemove(store.stateURL)

        let f = try XCTUnwrap(store.read(), "файл пропал — берём копию")
        XCTAssertEqual(f.rev, 2, "state.bak.json — прошлая запись, раньше prev и зеркала")
        XCTAssertEqual(f.debugMarker, 2)
        rRemove(store.bakURL)
        let g = try XCTUnwrap(store.read())
        XCTAssertEqual(g.rev, 0, "без bak — prev (rev 0)")
        XCTAssertNil(g.debugMarker)
        XCTAssertTrue(rBrokenNames(dir).isEmpty, "пропажа — не порча, откладывать нечего")
    }

    func testMissingStateAndPrevRecoversFromMirror() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-recovery")
        defer { StoreHooks.removeTempStore(dir) }
        rRemove(Paths.mirror)
        let store = PetStore(dir: dir)
        try store.startOver(now: rT0)
        try store.mutate { (f: inout SaveFile) -> Void in f.debugMarker = 7 }
        guard FileManager.default.fileExists(atPath: Paths.mirror.path) else {
            throw XCTSkip("зеркало пишет только приложение (APP_TARGET)")
        }
        rRemove(store.stateURL)
        rRemove(store.prevURL)

        let f = try XCTUnwrap(store.read(), "переподпись съела группу — спасает зеркало")
        XCTAssertEqual(f.debugMarker, 7)
        XCTAssertEqual(f.rev, 1)
    }

    func testMutateOverCorruptFileContinuesFromBak() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-recovery")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: rT0)
        for _ in 0..<10 { try store.mutate { (f: inout SaveFile) -> Void in f.seq += 0 } }
        let good = try XCTUnwrap(store.read())
        try Data("мусор".utf8).write(to: store.stateURL)

        try store.mutate { (f: inout SaveFile) -> Void in f.debugMarker = 42 }
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.petId, good.petId, "тот же щенок, не новый")
        XCTAssertEqual(f.rev, 10, "bak (rev 9) + эта запись: потеряна только испорченная")
        XCTAssertEqual(f.debugMarker, 42)
        XCTAssertEqual(f.journal.last?.kind, "save_restored")
        XCTAssertEqual(f.journal.last?.key, "state.bak.json")
        XCTAssertEqual(rBrokenNames(dir).count, 1)
        XCTAssertEqual(store.takeRecovery(), .restored(from: "state.bak.json"))
        XCTAssertNil(store.takeRecovery(), "тост — один раз")
    }

    func testThrowingBodyWritesNothing() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-recovery")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: rT0)
        try store.mutate { (f: inout SaveFile) -> Void in f.debugMarker = 1 }
        let before = try Data(contentsOf: store.stateURL)

        XCTAssertThrowsError(try store.mutate { (f: inout SaveFile) -> Void in
            f.debugMarker = 2
            throw RecoveryBoom()
        }) { err in XCTAssertTrue(err is RecoveryBoom, "ошибка тела доходит как есть: \(err)") }

        XCTAssertEqual(try Data(contentsOf: store.stateURL), before, "файл не тронут")
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.rev, 1)
        XCTAssertEqual(f.debugMarker, 1)
    }

    func testEmptyDirReadsNilAndMutateCreates() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-recovery")
        defer { StoreHooks.removeTempStore(dir) }
        rRemove(Paths.mirror)
        let store = PetStore(dir: dir)
        XCTAssertNil(try store.read(), "первый запуск: файла нет и копий нет")

        let seen = try store.mutate { (f: inout SaveFile) -> Bool in f.pet.alive }
        XCTAssertTrue(seen, "mutate на пустом месте видит живого щенка")
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.rev, 1)
        XCTAssertTrue(rBrokenNames(dir).isEmpty)
    }

    func testStartOverOnEmptyDirMakesNoBroken() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-recovery")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: rT0)
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.rev, 0)
        XCTAssertEqual(f.createdT, rT0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.prevURL.path), "rev 0 пишет и prev")
        XCTAssertTrue(rBrokenNames(dir).isEmpty)
    }

    func testConcurrentMutatesDoNotLoseWrites() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-recovery")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: rT0)
        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            _ = try? store.mutate { (f: inout SaveFile) -> Void in f.debugMarker = (f.debugMarker ?? 0) + 1 }
        }
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.debugMarker, 20, "ни одна запись не потерялась")
        XCTAssertEqual(f.rev, 20)
    }
}
