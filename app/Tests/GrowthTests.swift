// Волна 33 B: рост щенок → подросток → взрослый, очки за сутки ухода. Пока заготовка (шаг 0).

import Foundation
import XCTest
@testable import Pet

final class GrowthTests: XCTestCase {

    func testEmptyIsNotWritten() throws {
        let f = SaveFile.fresh(now: 1_760_054_400)
        let data = try JSONEncoder().encode(f)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(obj?["growth"], "пустое поле не пишется в сейв")
        XCTAssertNoThrow(try JSONDecoder().decode(SaveFile.self, from: data))
    }
}
