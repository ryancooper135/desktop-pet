import ActivityKit
import Foundation

struct PetAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var mood: String
        var food: Int
        var status: String
        var updatedAt: Date
    }

    var petName: String
}
