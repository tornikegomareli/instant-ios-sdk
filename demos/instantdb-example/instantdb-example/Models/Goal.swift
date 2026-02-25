import Foundation
import InstantDB

@InstantEntity("goals")
struct Goal {
  let id: String
  var title: String
  var difficulty: Int?
  var completed: Bool?
}
