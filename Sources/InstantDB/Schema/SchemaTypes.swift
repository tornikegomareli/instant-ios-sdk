import Foundation

public enum InstantDataType: String, Codable, Sendable {
  case string
  case number
  case boolean
  case date
  case json
  case any
}

public enum Cardinality: String, Codable, Sendable {
  case one
  case many
}

public enum OnDeleteAction: String, Codable, Sendable {
  case cascade
}
