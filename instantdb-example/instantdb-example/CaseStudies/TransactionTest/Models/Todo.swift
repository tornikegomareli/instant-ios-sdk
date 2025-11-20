import Foundation
import InstantDB

@InstantEntity("todos")
struct Todo {
  let id: String
  var text: String
  var done: Bool?
}
