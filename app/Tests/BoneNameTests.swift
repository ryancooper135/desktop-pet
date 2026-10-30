// Имена костей (волна 50, BoneName): код звал уши «Ear1.L», в shiba.usdz они «Ear1_L» — уши на тап не двигались.

import XCTest
@testable import Pet

final class BoneNameTests: XCTestCase {
    /// Кости как в shiba.usdz: уши под Neck3, челюсть и язык под Head.
    private let shiba = [
        "Body",
        "Body/Back/Torso/Torso2/Torso3/Neck1/Neck2/Neck3",
        "Body/Back/Torso/Torso2/Torso3/Neck1/Neck2/Neck3/Head",
        "Body/Back/Torso/Torso2/Torso3/Neck1/Neck2/Neck3/Head/Jaw",
        "Body/Back/Torso/Torso2/Torso3/Neck1/Neck2/Neck3/Head/Jaw/Tongue",
        "Body/Back/Torso/Torso2/Torso3/Neck1/Neck2/Neck3/Head/Jaw/Tongue/TongueTip",
        "Body/Back/Torso/Torso2/Torso3/Neck1/Neck2/Neck3/Ear1_L",
        "Body/Back/Torso/Torso2/Torso3/Neck1/Neck2/Neck3/Ear1_L/Ear2_L",
        "Body/Back/Torso/Torso2/Torso3/Neck1/Neck2/Neck3/Ear1_R",
        "Body/Back/Torso/Torso2/Torso3/Neck1/Neck2/Neck3/Ear1_R/Ear2_R",
    ]

    func testNormalized() {
        XCTAssertEqual(BoneName.normalized("Ear1.L"), "ear1_l")
        XCTAssertEqual(BoneName.normalized("ear1-l"), "ear1_l")
        XCTAssertEqual(BoneName.normalized("EAR1 L"), "ear1_l")
        XCTAssertEqual(BoneName.normalized("rig:Ear1_L"), "rig_ear1_l")
    }

    func testDotNameFindsUnderscoreBone() {
        XCTAssertEqual(BoneName.index(shiba, "Ear1.L"), 6)
        XCTAssertEqual(BoneName.index(shiba, "Ear1.R"), 8)
        XCTAssertEqual(BoneName.index(shiba, "Ear2.L"), 7)
        XCTAssertEqual(BoneName.index(shiba, "Ear2.R"), 9)
        XCTAssertEqual(BoneName.index(shiba, "Head"), 2)
        XCTAssertEqual(BoneName.index(shiba, "TongueTip"), 5)
        XCTAssertNil(BoneName.index(shiba, "Tail1"))
        XCTAssertNil(BoneName.index(shiba, ""))
    }

    func testExactMatchWins() {
        // Точное звено важнее похожего по нормализации.
        let names = ["Root/ear1_l", "Root/Ear1.L"]
        XCTAssertEqual(BoneName.index(names, "Ear1.L"), 1)
        XCTAssertEqual(BoneName.index(names, "ear1_l"), 0)
        // Путь ищется только точно.
        XCTAssertEqual(BoneName.index(shiba, "Neck3/Head"), 2)
        XCTAssertNil(BoneName.index(shiba, "Neck3/head"))
    }

    func testLeafAndDescendants() {
        XCTAssertEqual(BoneName.leaf("A/B/Head"), "Head")
        XCTAssertEqual(BoneName.leaf("Head"), "Head")
        XCTAssertEqual(BoneName.descendants(shiba, of: 2), [3, 4, 5])
        XCTAssertEqual(BoneName.descendants(shiba, of: 6), [7])
        XCTAssertEqual(BoneName.descendants(shiba, of: 99), [])
    }
}
