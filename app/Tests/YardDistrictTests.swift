// Волна 36 Q: районы двора — имена, круг номеров, свой декор и различимые палитры.
import XCTest
@testable import Pet

final class YardDistrictTests: XCTestCase {
    func testNames() {
        XCTAssertEqual(YardDistrict.street.title, "Улица")
        XCTAssertEqual(YardDistrict.winter.title, "Зимний квартал")
        XCTAssertEqual(YardDistrict.river.title, "У реки")
        XCTAssertEqual(YardDistrict.roof.title, "На крыше")
        XCTAssertEqual(YardDistrict.moveCaption(from: .street, to: .winter), "Переезжаем: Улица → Зимний квартал")
    }

    func testIndexCircle() {
        XCTAssertEqual(YardDistrict(index: 0), .street)
        XCTAssertEqual(YardDistrict(index: -3), .street)
        XCTAssertEqual(YardDistrict(index: 1), .winter)
        XCTAssertEqual(YardDistrict(index: 2), .river)
        XCTAssertEqual(YardDistrict(index: 3), .roof)
        // После крыши — снова зима, улица не возвращается.
        XCTAssertEqual(YardDistrict(index: 4), .winter)
        XCTAssertEqual(YardDistrict(index: 5), .river)
        XCTAssertEqual(YardDistrict(index: 6), .roof)
        XCTAssertEqual(YardDistrict(index: 100), YardDistrict(index: 100 - 3))
        for d in YardDistrict.allCases { XCTAssertEqual(YardDistrict(index: d.index), d) }
        XCTAssertEqual(YardDistrict.street.next, .winter)
        XCTAssertEqual(YardDistrict.roof.next, .winter)
        for n in 1...30 { XCTAssertNotEqual(YardDistrict(index: n), .street) }
    }

    func testParse() {
        XCTAssertEqual(YardDistrict.parse("winter"), .winter)
        XCTAssertEqual(YardDistrict.parse(" Roof "), .roof)
        XCTAssertEqual(YardDistrict.parse("2"), .river)
        XCTAssertEqual(YardDistrict.parse("4"), .winter)
        XCTAssertNil(YardDistrict.parse(nil))
        XCTAssertNil(YardDistrict.parse(""))
        XCTAssertNil(YardDistrict.parse("луна"))
    }

    func testEachMovedDistrictHasOwnDecor() {
        XCTAssertTrue(YardDistrict.street.decor.isEmpty, "улица — вид двора до переезда")
        let moved = YardDistrict.allCases.filter { $0 != .street }
        for d in moved { XCTAssertFalse(d.decor.isEmpty, "\(d) без декора") }
        for (i, a) in moved.enumerated() {
            for b in moved[(i + 1)...] {
                XCTAssertTrue(Set(a.decor).isDisjoint(with: b.decor), "\(a) и \(b) делят декор")
            }
        }
        XCTAssertTrue(YardDistrict.winter.decor.contains(.firTree))
        XCTAssertTrue(YardDistrict.winter.decor.contains(.snowdrifts))
        XCTAssertTrue(YardDistrict.river.decor.contains(.river))
        XCTAssertTrue(YardDistrict.river.decor.contains(.bridge))
        XCTAssertTrue(YardDistrict.roof.decor.contains(.parapet))
        XCTAssertTrue(YardDistrict.roof.decor.contains(.waterTank))
    }

    /// Расстояние между цветами в RGB (0…441).
    private func dist(_ a: UInt32, _ b: UInt32) -> Double {
        func ch(_ c: UInt32, _ s: UInt32) -> Double { Double((c >> s) & 0xff) }
        let d = [16, 8, 0].map { s in ch(a, UInt32(s)) - ch(b, UInt32(s)) }
        return (d.map { $0 * $0 }.reduce(0, +)).squareRoot()
    }

    func testPalettesAreDistinct() {
        let all = YardDistrict.allCases
        for (i, a) in all.enumerated() {
            for b in all[(i + 1)...] {
                let pa = a.palette, pb = b.palette
                // Главная земля и небо — то, что видно с первого взгляда.
                XCTAssertGreaterThan(dist(pa.ground, pb.ground), 60, "земля \(a)/\(b)")
                XCTAssertGreaterThan(dist(pa.garden, pb.garden), 40, "сад \(a)/\(b)")
                XCTAssertGreaterThan(dist(pa.tile, pb.tile), 20, "плиты \(a)/\(b)")
                XCTAssertNotEqual(pa.sky, pb.sky, "небо \(a)/\(b)")
                XCTAssertNotEqual(pa.skyNight, pb.skyNight, "ночь \(a)/\(b)")
                XCTAssertNotEqual(pa, pb)
            }
        }
    }

    func testStreetKeepsOldColors() {
        let p = YardDistrict.street.palette
        XCTAssertEqual(p.ground, 0xa07850)
        XCTAssertEqual(p.garden, 0xa6d48f)
        XCTAssertEqual(p.tile, 0xd9cfc0)
        XCTAssertEqual(p.fence, 0xf6ead6)
        XCTAssertEqual(YardDistrict.street.sky(night: false), 0xf6efe6)
        XCTAssertEqual(YardDistrict.street.sky(night: true), 0x2a3350)
    }

    func testRoofHasNoGrass() {
        // «Зелёный» — зелёный канал заметно выше красного и синего.
        func green(_ c: UInt32) -> Bool {
            let r = Int((c >> 16) & 0xff), g = Int((c >> 8) & 0xff), b = Int(c & 0xff)
            return g > r + 20 && g > b + 20
        }
        for c in YardDistrict.roof.palette.surfaces { XCTAssertFalse(green(c), String(c, radix: 16)) }
        XCTAssertTrue(green(YardDistrict.street.palette.garden), "проверка сама видит траву")
    }

    func testNightSkyDarkerThanDay() {
        func luma(_ c: UInt32) -> Double {
            0.299 * Double((c >> 16) & 0xff) + 0.587 * Double((c >> 8) & 0xff) + 0.114 * Double(c & 0xff)
        }
        for d in YardDistrict.allCases {
            XCTAssertLessThan(luma(d.sky(night: true)) + 80, luma(d.sky(night: false)), "\(d)")
        }
    }
}
