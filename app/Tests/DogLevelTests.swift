// Волна 33 A: уровень пса — опыт по журналу, кривая, открытия по уровню. Пока заготовка (шаг 0).

import Foundation
import XCTest
@testable import Pet

final class DogLevelTests: XCTestCase {

    func testEmptyIsNotWritten() throws {
        let f = SaveFile.fresh(now: 1_760_054_400)
        let data = try JSONEncoder().encode(f)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(obj?["level"], "пустое поле не пишется в сейв")
        XCTAssertNoThrow(try JSONDecoder().decode(SaveFile.self, from: data))
    }
}
