import Foundation
import InstantDB

struct Goal: InstantEntity, Identifiable {
  static var namespace: String { "goals" }

  let id: String
  var title: String
  var difficulty: Int?
  var completed: Bool?

  var todos: [Todo]?

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case difficulty
    case completed
    case todos
  }
}
