// Общий стейт и время. Стор приложения подключается через StoreHooks (SnapshotCatalog.swift);
// пока хуки не подключены, эти тесты пропускаются, а проверки контейнера группы и ядра работают сразу.

import Foundation
import XCTest
@testable import Pet
#if canImport(PetCore)
import PetCore
#endif

final class StoreTests: XCTestCase {
    // MARK: App Group

    /// Контейнер группы на симуляторе есть, файл в нём пишется и читается обратно.
    func testAppGroupContainerRoundTrip() throws {
        #if !canImport(Darwin)
        throw XCTSkip("App Group есть только на Apple (Linux-сборка логики)")
        #else
        guard let dir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: StoreHooks.appGroupID)
        else {
            throw XCTSkip("Контейнера \(StoreHooks.appGroupID) нет: сборка без entitlements (CODE_SIGNING_ALLOWED=NO?)")
        }
        let url = dir.appendingPathComponent("ci-roundtrip-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let written = ["marker": Date().timeIntervalSince1970]
        try JSONEncoder().encode(written).write(to: url, options: .atomic)
        let read = try JSONDecoder().decode([String: Double].self, from: Data(contentsOf: url))
        XCTAssertEqual(read, written)
        #endif
    }

    // MARK: Стор приложения

    func testStoreWriteThenRead() throws {
        let marker = Double(Int(Date().timeIntervalSince1970))
        guard let r = try StoreHooks.writeThenRead(marker: marker) else {
            throw XCTSkip("TODO: StoreHooks.writeThenRead не подключён к стору приложения")
        }
        XCTAssertEqual(r.written, marker)
        XCTAssertEqual(r.read, marker, "виджет прочитал не то, что записало приложение")
    }

    func testStoreTimeMoves() throws {
        guard let r = try StoreHooks.food(afterHours: 6) else {
            throw XCTSkip("TODO: StoreHooks.food(afterHours:) не подключён к стору приложения")
        }
        XCTAssertLessThan(r.after, r.before, "за 6 часов без ухода еда должна убывать")
    }

    // MARK: Ядро: время идёт

    #if canImport(PetCore)
    /// economy.json из бандла приложения, иначе из репозитория (симулятор видит файлы Mac).
    func rules() throws -> Rules {
        if let url = Bundle.main.url(forResource: "economy", withExtension: "json") {
            return try Rules(data: Data(contentsOf: url))
        }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = repo.appendingPathComponent("config/economy.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("economy.json нет ни в бандле, ни в \(url.path)")
        }
        return try Rules(data: Data(contentsOf: url))
    }

    func testCoreTimeMoves() throws {
        let r = try rules()
        let o = PetEngine.defaultOwner(r)
        let t0 = 1_760_000_000.0
        let s0 = PetEngine.newPet(r, t: t0)

        let s6 = PetEngine.advance(s0, r, o, t0 + 6 * 3600)
        XCTAssertEqual(s6.t, t0 + 6 * 3600, accuracy: 1e-6)
        XCTAssertLessThan(s6.needs[.food] ?? 0, s0.needs[.food] ?? 0, "еда не убывает со временем")

        // Виджет догоняет состояние кусками — результат тот же, что одним шагом.
        let s3 = PetEngine.advance(s0, r, o, t0 + 3 * 3600)
        let s3x2 = PetEngine.advance(s3, r, o, t0 + 6 * 3600)
        XCTAssertEqual(s3x2.needs[.food] ?? -1, s6.needs[.food] ?? -2, accuracy: 1e-9)
        XCTAssertEqual(s3x2.hearts, s6.hearts, accuracy: 1e-9)

        // Трое суток без ухода — питомцу плохо (или он умер).
        let s72 = PetEngine.advance(s0, r, o, t0 + 72 * 3600)
        XCTAssertGreaterThanOrEqual(PetEngine.level(s72, r), 2)
    }
    #else
    func testCoreTimeMoves() throws {
        throw XCTSkip("PetCore не подключён к PetTests (dependencies: - package: PetCore)")
    }
    #endif
}
