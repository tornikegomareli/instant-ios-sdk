import Foundation

/// Sort direction for ordering query results
public enum SortDirection: String {
  case asc
  case desc
}

/// Type-safe query builder for InstantDB
///
/// Example:
/// ```swift
/// db.query(Goal.self)
///     .where { $0.difficulty > 5 }
///     .order(by: \.title, .asc)
///     .first(10)
/// ```
public struct TypedQuery<T: InstantEntity> {
  let namespace: String
  var whereClause: [String: Any]?
  var limitValue: Int?
  var offsetValue: Int?
  var nestedQueries: [String: Any] = [:]

  var firstValue: Int?
  var lastValue: Int?
  var afterCursor: Cursor?
  var beforeCursor: Cursor?
  var orderValue: [String: String]?

  internal weak var client: InstantClient?

  init(namespace: String, client: InstantClient? = nil) {
    self.namespace = namespace
    self.client = client
  }

  /// Filters query results using a type-safe predicate
  ///
  /// - Parameter buildPredicate: A closure that builds the filter predicate using property comparisons
  /// - Returns: A new query with the filter applied
  ///
  /// ## Supported Operators
  /// - `>`, `>=`, `<`, `<=`, `==`, `!=`
  /// - Note: Comparison operators on optional fields require the field to be indexed.
  public func `where`(_ buildPredicate: (QueryProxy<T>) -> PredicateExpression) -> TypedQuery<T> {
    var copy = self
    let proxy = QueryProxy<T>()
    let predicate = buildPredicate(proxy)
    copy.whereClause = predicate.toDict()
    return copy
  }

  /// Limits the maximum number of results (offset-based pagination)
  ///
  /// For cursor-based pagination, use ``first(_:)`` or ``last(_:)`` instead.
  public func limit(_ count: Int) -> TypedQuery<T> {
    var copy = self
    copy.limitValue = count
    return copy
  }

  /// Skips the specified number of results (offset-based pagination)
  ///
  /// For cursor-based pagination, use ``after(_:)`` or ``before(_:)`` instead.
  public func offset(_ count: Int) -> TypedQuery<T> {
    var copy = self
    copy.offsetValue = count
    return copy
  }

  /// Get first N results from the beginning (cursor-based pagination)
  ///
  /// Use with ``after(_:)`` to paginate forward through results.
  ///
  /// ```swift
  /// // First page
  /// db.query(Goal.self).order(by: \.title).first(10)
  ///
  /// // Next page
  /// db.query(Goal.self).order(by: \.title).first(10).after(pageInfo.endCursor)
  /// ```
  public func first(_ count: Int) -> TypedQuery<T> {
    var copy = self
    copy.firstValue = count
    return copy
  }

  /// Get last N results from the end (cursor-based pagination)
  ///
  /// Use with ``before(_:)`` to paginate backward through results.
  public func last(_ count: Int) -> TypedQuery<T> {
    var copy = self
    copy.lastValue = count
    return copy
  }

  /// Start results after the given cursor (next page)
  ///
  /// Use `pageInfo.endCursor` from a previous query result.
  ///
  /// ```swift
  /// if let cursor = result.pageInfo?.endCursor {
  ///   db.query(Goal.self).first(10).after(cursor)
  /// }
  /// ```
  public func after(_ cursor: Cursor) -> TypedQuery<T> {
    var copy = self
    copy.afterCursor = cursor
    return copy
  }

  /// End results before the given cursor (previous page)
  ///
  /// Use `pageInfo.startCursor` from a previous query result.
  public func before(_ cursor: Cursor) -> TypedQuery<T> {
    var copy = self
    copy.beforeCursor = cursor
    return copy
  }

  /// Order results by field name
  ///
  /// - Parameters:
  ///   - field: Field name to order by
  ///   - direction: Sort direction (default: ascending)
  /// - Note: The field must be indexed in your InstantDB schema.
  public func order(by field: String, _ direction: SortDirection = .asc) -> TypedQuery<T> {
    var copy = self
    copy.orderValue = [field: direction.rawValue]
    return copy
  }

  /// Order results by property (type-safe)
  ///
  /// ```swift
  /// db.query(Goal.self).order(by: \.title, .asc)
  /// db.query(Goal.self).order(by: \.createdAt, .desc)
  /// ```
  /// - Note: The field must be indexed in your InstantDB schema.
  public func order<V>(by keyPath: KeyPath<T, V>, _ direction: SortDirection = .asc) -> TypedQuery<T> {
    let fieldName = extractFieldName(from: keyPath)
    return order(by: fieldName, direction)
  }

  /// Convert to InstaQL dictionary format
  func toQuery() -> [String: Any] {
    var inner: [String: Any] = nestedQueries
    var modifiers: [String: Any] = [:]

    if let whereClause = whereClause {
      modifiers["where"] = whereClause
    }

    if let orderValue = orderValue {
      modifiers["order"] = orderValue
    }

    if let limitValue = limitValue {
      modifiers["limit"] = limitValue
    }

    if let offsetValue = offsetValue {
      modifiers["offset"] = offsetValue
    }

    if let firstValue = firstValue {
      modifiers["first"] = firstValue
    }

    if let lastValue = lastValue {
      modifiers["last"] = lastValue
    }

    if let afterCursor = afterCursor {
      modifiers["after"] = afterCursor.toQueryValue()
    }

    if let beforeCursor = beforeCursor {
      modifiers["before"] = beforeCursor.toQueryValue()
    }

    if !modifiers.isEmpty {
      inner["$"] = modifiers
    }

    return [namespace: inner]
  }
}

/// Proxy object used to build type-safe predicates
@dynamicMemberLookup
public final class QueryProxy<T> {
  init() {}

  public subscript<Value>(dynamicMember keyPath: KeyPath<T, Value>) -> QueryField<Value> {
    let fieldName = extractFieldName(from: keyPath)
    return QueryField<Value>(name: fieldName)
  }
}

/// Extracts property name from KeyPath
func extractFieldName<T, Value>(from keyPath: KeyPath<T, Value>) -> String {
  let keyPathString = String(describing: keyPath)
  let components = keyPathString.split(separator: ".")
  if let last = components.last {
    return String(last)
  }
  return keyPathString
}

/// Represents a queryable field with type-safe operators
public struct QueryField<Value> {
  let name: String

  init(name: String) {
    self.name = name
  }
}

/// Base protocol for predicate expressions
public protocol PredicateExpression {
  func toDict() -> [String: Any]
}

extension QueryField where Value: Equatable {
  public static func == (lhs: QueryField<Value>, rhs: Value) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .eq, value: rhs)
  }

  public static func != (lhs: QueryField<Value>, rhs: Value) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .neq, value: rhs)
  }
}

extension QueryField where Value: Comparable {
  public static func > (lhs: QueryField<Value>, rhs: Value) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .gt, value: rhs)
  }

  public static func >= (lhs: QueryField<Value>, rhs: Value) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .gte, value: rhs)
  }

  public static func < (lhs: QueryField<Value>, rhs: Value) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .lt, value: rhs)
  }

  public static func <= (lhs: QueryField<Value>, rhs: Value) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .lte, value: rhs)
  }
}

extension QueryField where Value == Int? {
  public static func > (lhs: QueryField<Int?>, rhs: Int) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .gt, value: rhs)
  }

  public static func >= (lhs: QueryField<Int?>, rhs: Int) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .gte, value: rhs)
  }

  public static func < (lhs: QueryField<Int?>, rhs: Int) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .lt, value: rhs)
  }

  public static func <= (lhs: QueryField<Int?>, rhs: Int) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .lte, value: rhs)
  }

  public static func == (lhs: QueryField<Int?>, rhs: Int) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .eq, value: rhs)
  }

  public static func != (lhs: QueryField<Int?>, rhs: Int) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .neq, value: rhs)
  }
}

extension QueryField where Value == String? {
  public static func == (lhs: QueryField<String?>, rhs: String) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .eq, value: rhs)
  }

  public static func != (lhs: QueryField<String?>, rhs: String) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .neq, value: rhs)
  }
}

extension QueryField where Value == Bool? {
  public static func == (lhs: QueryField<Bool?>, rhs: Bool) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .eq, value: rhs)
  }

  public static func != (lhs: QueryField<Bool?>, rhs: Bool) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .neq, value: rhs)
  }
}

extension QueryField where Value == Double? {
  public static func > (lhs: QueryField<Double?>, rhs: Double) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .gt, value: rhs)
  }

  public static func >= (lhs: QueryField<Double?>, rhs: Double) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .gte, value: rhs)
  }

  public static func < (lhs: QueryField<Double?>, rhs: Double) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .lt, value: rhs)
  }

  public static func <= (lhs: QueryField<Double?>, rhs: Double) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .lte, value: rhs)
  }

  public static func == (lhs: QueryField<Double?>, rhs: Double) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .eq, value: rhs)
  }

  public static func != (lhs: QueryField<Double?>, rhs: Double) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .neq, value: rhs)
  }
}

public func && (lhs: PredicateExpression, rhs: PredicateExpression) -> PredicateExpression {
  LogicalPredicate(op: .and, left: lhs, right: rhs)
}

public func || (lhs: PredicateExpression, rhs: PredicateExpression) -> PredicateExpression {
  LogicalPredicate(op: .or, left: lhs, right: rhs)
}

enum ComparisonOperator: String {
  case eq = "$eq"
  case neq = "$neq"
  case gt = "$gt"
  case gte = "$gte"
  case lt = "$lt"
  case lte = "$lte"
}

struct ComparisonPredicate: PredicateExpression {
  let field: String
  let op: ComparisonOperator
  let value: Any

  func toDict() -> [String: Any] {
    if op == .eq {
      return [field: value]
    } else {
      return [field: [op.rawValue: value]]
    }
  }
}

enum LogicalOperator: String {
  case and = "$and"
  case or = "$or"
}

struct LogicalPredicate: PredicateExpression {
  let op: LogicalOperator
  let left: PredicateExpression
  let right: PredicateExpression

  func toDict() -> [String: Any] {
    let leftDict = left.toDict()
    let rightDict = right.toDict()

    var merged: [String: Any] = [:]
    merged.merge(leftDict) { _, new in new }
    merged.merge(rightDict) { _, new in new }

    return merged
  }
}
