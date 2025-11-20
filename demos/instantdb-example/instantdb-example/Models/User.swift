import Foundation
import InstantDB

@InstantEntity("users")
struct User {
  let id: String
  var email: String?
  var name: String?
}
