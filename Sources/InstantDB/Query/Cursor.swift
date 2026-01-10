import Foundation

/// Opaque cursor for pagination
///
/// Cursors are used for cursor-based pagination to navigate through query results.
/// Do not construct cursors manually - use `pageInfo.startCursor` or `pageInfo.endCursor`
/// from query results.
///
/// Example:
/// ```swift
/// // Get first page
/// for await result in db.query(Goal.self).first(10).values() {
///   if let endCursor = result.pageInfo?.endCursor {
///     // Use endCursor for next page
///   }
/// }
/// ```
public struct Cursor: Sendable, Equatable, Hashable {
  let values: [AnyCodableValue]

  init(from array: [Any]) {
    self.values = array.map { AnyCodableValue($0) }
  }

  func toQueryValue() -> [Any] {
    values.map { $0.value }
  }

  public static func == (lhs: Cursor, rhs: Cursor) -> Bool {
    lhs.values == rhs.values
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(values)
  }
}

/// Internal wrapper for Any values that need Sendable conformance
/// Uses @unchecked because cursor values are always primitives (String, Int, Double, Bool)
public struct AnyCodableValue: @unchecked Sendable, Equatable, Hashable {
  public let value: Any

  public init(_ value: Any) {
    self.value = value
  }
  
  /// Alias for consistency with other initializers
  public init(value: Any) {
    self.value = value
  }

  public static func == (lhs: AnyCodableValue, rhs: AnyCodableValue) -> Bool {
    switch (lhs.value, rhs.value) {
    case let (l as String, r as String):
      return l == r
    case let (l as Int, r as Int):
      return l == r
    case let (l as Double, r as Double):
      return l == r
    case let (l as Bool, r as Bool):
      return l == r
    default:
      return String(describing: lhs.value) == String(describing: rhs.value)
    }
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(String(describing: value))
  }
}

// MARK: - AnyCodableValue Codable

extension AnyCodableValue: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    
    if container.decodeNil() {
      value = NSNull()
    } else if let bool = try? container.decode(Bool.self) {
      value = bool
    } else if let int = try? container.decode(Int64.self) {
      value = int
    } else if let double = try? container.decode(Double.self) {
      value = double
    } else if let string = try? container.decode(String.self) {
      value = string
    } else if let array = try? container.decode([AnyCodableValue].self) {
      value = array.map(\.value)
    } else if let dict = try? container.decode([String: AnyCodableValue].self) {
      value = dict.mapValues(\.value)
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodableValue")
    }
  }
  
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    
    switch value {
    case is NSNull:
      try container.encodeNil()
    case let bool as Bool:
      try container.encode(bool)
    case let int as Int:
      try container.encode(int)
    case let int64 as Int64:
      try container.encode(int64)
    case let double as Double:
      try container.encode(double)
    case let string as String:
      try container.encode(string)
    case let array as [Any]:
      try container.encode(array.map { AnyCodableValue($0) })
    case let dict as [String: Any]:
      try container.encode(dict.mapValues { AnyCodableValue($0) })
    default:
      try container.encode(String(describing: value))
    }
  }
}
