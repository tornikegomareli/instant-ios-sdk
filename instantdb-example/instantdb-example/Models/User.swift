import Foundation
import InstantDB

struct User: InstantEntity, Identifiable {
    static var namespace: String { "users" }

    let id: String
    var email: String?
    var name: String?
}
