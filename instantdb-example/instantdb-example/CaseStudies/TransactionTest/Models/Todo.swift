import Foundation
import InstantDB

struct Todo: InstantEntity, Identifiable {
    static var namespace: String { "todos" }

    let id: String
    var text: String
    var done: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case done
    }
}
