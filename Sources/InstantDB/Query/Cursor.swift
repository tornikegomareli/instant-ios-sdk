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
struct AnyCodableValue: @unchecked Sendable, Equatable, Hashable {
  let value: Any

  init(_ value: Any) {
    self.value = value
  }

  static func == (lhs: AnyCodableValue, rhs: AnyCodableValue) -> Bool {
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

  func hash(into hasher: inout Hasher) {
    hasher.combine(String(describing: value))
  }
}
