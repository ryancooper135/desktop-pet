// Порода пса из коробки (волна 58, PetBreed): старые сейвы — Шиба, выбор переживает запись и нового щенка,
// у каждой породы в бандле свои usdz и clips.json с теми же именами клипов.
// Гоняется и на Linux (app/Package.swift): только Shared и PetCore, ресурсы — по #filePath.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
private let petsDir = testsDir.deletingLastPathComponent().appendingPathComponent("Resources/Pets")

final class PetBreedTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: Paths.mirror)
    }

    func testDefaultIsShibaAndUnknownFallsBack() {
        XCTAssertEqual(PetBreed.standard, .shiba)
        XCTAssertEqual(PetBreed(save: nil), .shiba)
        XCTAssertEqual(PetBreed(save: "shiba"), .shiba)
        XCTAssertEqual(PetBreed(save: "husky"), .husky)
        // Сейв из будущей версии с незнакомой породой — Шиба, а не падение.
        XCTAssertEqual(PetBreed(save: "corgi"), .shiba)
        XCTAssertEqual(PetBreed(save: ""), .shiba)
    }

    func testSavedValueKeepsOldFilesUntouched() {
        XCTAssertNil(PetBreed.shiba.saved, "Шиба в файл не пишется — сейв до волны 58 не меняется")
        XCTAssertEqual(PetBreed.husky.saved, "husky")
        for b in PetBreed.allCases { XCTAssertEqual(PetBreed(save: b.saved), b) }
    }

    func testOldSaveFixturesLoadAsShiba() throws {
        for v in ["0.7", "0.10", "0.14"] {
            let data = try Data(contentsOf: testsDir.appendingPathComponent("Fixtures/save-v\(v).json"))
            let f = try JSONDecoder().decode(SaveFile.self, from: data)
            XCTAssertNil(f.breed, v)
            XCTAssertEqual(PetBreed(save: f.breed), .shiba, v)
        }
    }

    func testBreedRoundTripsAndShibaIsOmitted() throws {
        var f = SaveFile.fresh(now: 1_800_000_000)
        XCTAssertNil(f.breed, "новый сейв — Шиба")
        f.breed = PetBreed.husky.saved
        let back = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(PetBreed(save: back.breed), .husky)
        f.breed = PetBreed.shiba.saved
        let data = try JSONEncoder().encode(f)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("breed"), "Шиба (nil) в файл не пишется")
    }

    func testGarbageBreedDoesNotBreakSave() throws {
        var f = SaveFile.fresh(now: 1_800_000_000)
        f.name = "Бублик"
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(f)) as? [String: Any])
        obj["breed"] = 42
        let back = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(back.breed, "не строка — как будто поля нет")
        XCTAssertEqual(back.name, "Бублик", "остальной сейв цел")
    }

    func testNewPuppyKeepsBreed() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-breed")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.mutate { $0.breed = PetBreed.husky.saved }
        try store.startOver()
        XCTAssertEqual(PetBreed(save: try XCTUnwrap(store.read()).breed), .husky, "новый щенок той же породы")
    }

    func testEveryBreedHasBundledModelAndSameClips() throws {
        struct Table: Decodable {
            struct Clip: Decodable { var start: Double; var end: Double; var loop: Bool? }
            var fps: Double
            var clips: [String: Clip]
        }
        var names: [PetBreed: Set<String>] = [:]
        for b in PetBreed.allCases {
            let usdz = petsDir.appendingPathComponent(b.resource + ".usdz")
            let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: usdz.path)[.size] as? Int, b.rawValue)
            XCTAssertGreaterThan(size, 100_000, "\(b): usdz пустой")
            // Бюджет волны 58 — до ~2 МБ на породу (2 МиБ с запасом на выравнивание usdz).
            XCTAssertLessThanOrEqual(size, 2 * 1024 * 1024, "\(b): usdz больше бюджета")
            let t = try JSONDecoder().decode(Table.self, from: Data(contentsOf: petsDir
                .appendingPathComponent(b.clipsResource + ".json")))
            XCTAssertEqual(t.fps, 24, b.rawValue)
            for (name, c) in t.clips { XCTAssertLessThan(c.start, c.end, "\(b): \(name)") }
            XCTAssertEqual(t.clips["death"]?.loop, false, b.rawValue)
            XCTAssertEqual(t.clips["idle"]?.loop, true, b.rawValue)
            names[b] = Set(t.clips.keys)
        }
        // Сцена, трюки и двор берут клипы по имени — у второй породы ровно те же, что у Шибы.
        XCTAssertEqual(names[.husky], names[.shiba])
        for clip in ["paw", "high_five", "spin", "play_dead_out", "crawl", "sit", "lie", "sleep", "idle_wag"] {
            XCTAssertTrue(names[.shiba]?.contains(clip) == true, clip)
        }
    }

    /// Миска и мячик (волна 58): готовые модели в бандле, в бюджете (≤ 300 КБ; треугольники — props_usdz.py ≤ 2000).
    func testRoomPropsBundledSmall() throws {
        for name in ["bowl", "ball"] {
            let url = petsDir.appendingPathComponent(name + ".usdz")
            let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, name)
            XCTAssertGreaterThan(size, 1_000, "\(name): пустой")
            XCTAssertLessThanOrEqual(size, 300 * 1024, "\(name): больше бюджета")
        }
        let src = try String(contentsOf: testsDir.deletingLastPathComponent().appendingPathComponent("App/PetProps.swift"),
                             encoding: .utf8)
        XCTAssertTrue(src.contains("\"bowl\"") && src.contains("\"ball\""), "PetProps грузит оба файла")
    }

    /// Каждый файл модели записан в ASSETS_LICENSES.md, а каждый CC-BY автор назван в приложении («Об игре»).
    func testAssetCreditsListed() throws {
        let appDir = testsDir.deletingLastPathComponent()
        let lic = try String(contentsOf: appDir.deletingLastPathComponent().appendingPathComponent("content/ASSETS_LICENSES.md"),
                             encoding: .utf8)
        let screens = try String(contentsOf: appDir.appendingPathComponent("App/Screens.swift"), encoding: .utf8)
        for file in PetBreed.allCases.map({ $0.resource + ".usdz" }) + ["bowl.usdz", "ball.usdz"] {
            let row = lic.split(separator: "\n").first { $0.contains("`\(file)`") }
            let line = try XCTUnwrap(row, "\(file) нет в ASSETS_LICENSES.md")
            XCTAssertTrue(line.contains("CC0") || line.contains("CC-BY"), "\(file): лицензия не открытая")
            if line.contains("CC-BY") {
                // | файл | модель | автор | источник | лицензия | — пустые края split отбрасывает.
                let author = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }[2]
                XCTAssertTrue(screens.contains(author), "\(file): CC-BY автор «\(author)» не назван в «Об игре»")
            }
        }
        XCTAssertTrue(screens.contains("Text(\"Об игре\")"))
    }

    func testBreedLook() {
        XCTAssertEqual(PetBreed.shiba.iris, EyeStyle.iris)
        XCTAssertNotEqual(PetBreed.husky.iris, EyeStyle.iris, "у Хаски голубые глаза")
        XCTAssertNil(PetBreed.shiba.fur, "клочки Шибы как были")
        XCTAssertNotNil(PetBreed.husky.fur)
        XCTAssertEqual(PetBreed.shiba.body, .shiba)
        for b in PetBreed.allCases {
            XCTAssertFalse(b.title.isEmpty)
            XCTAssertFalse(b.note.isEmpty)
            XCTAssertLessThan(b.deathShiftX, 0, "лёжа на боку пёс уезжает в одну сторону у обеих пород")
            XCTAssertEqual(b.body.height, 1, accuracy: 1e-9)
            XCTAssertGreaterThan(b.body.length, 0.5)
            XCTAssertGreaterThan(b.body.width, 0.5)
        }
        XCTAssertEqual(Set(PetBreed.allCases.map(\.title)).count, PetBreed.allCases.count)
    }
}
