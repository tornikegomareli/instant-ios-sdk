import Foundation

/// Type-safe query builder for InstantDB
///
/// Example:
/// ```swift
/// db.query(Goal.self)
///     .where { $0.difficulty > 5 }
///     .limit(10)
/// ```
public struct TypedQuery<T: InstantEntity> {
  let namespace: String
  var whereClause: [String: Any]?
  var limitValue: Int?
  var offsetValue: Int?
  var nestedQueries: [String: Any] = [:]
  
  init(namespace: String) {
    self.namespace = namespace
  }
  
  /// Filters query results using a type-safe predicate
  ///
  /// Use this method to filter entities based on their property values. The predicate closure
  /// receives a proxy object that provides type-safe access to entity properties.
  ///
  /// - Parameter buildPredicate: A closure that builds the filter predicate using property comparisons
  /// - Returns: A new query with the filter applied
  ///
  /// ## Supported Operators
  ///
  /// **Comparison operators:**
  /// - `>` - Greater than
  /// - `>=` - Greater than or equal
  /// - `<` - Less than
  /// - `<=` - Less than or equal
  /// - `==` - Equal to
  /// - `!=` - Not equal to
  /// - Note: The where clause is executed server-side. For comparison operators on optional fields,
  ///         the field must be indexed in your InstantDB schema.
  public func `where`(_ buildPredicate: (QueryProxy<T>) -> PredicateExpression) -> TypedQuery<T> {
    var copy = self
    let proxy = QueryProxy<T>()
    let predicate = buildPredicate(proxy)
    copy.whereClause = predicate.toDict()
    return copy
  }
  
  /// Limits the maximum number of results returned by the query
  ///
  /// Use this method to paginate results or restrict the number of entities returned.
  /// Combine with ``offset(_:)`` to implement pagination.
  ///
  /// - Parameter count: The maximum number of entities to return
  /// - Returns: A new query with the limit applied
  /// - Important: Limit is applied server-side after filtering. If you have 100 goals
  ///              but filter to 30, limit(10) will return the first 10 of those 30.
  public func limit(_ count: Int) -> TypedQuery<T> {
    var copy = self
    copy.limitValue = count
    return copy
  }
  
  /// Skips the specified number of results before returning data
  ///
  /// Use this method together with ``limit(_:)`` to implement pagination. The offset determines
  /// how many results to skip before starting to return data.
  ///
  /// - Parameter count: The number of entities to skip
  /// - Returns: A new query with the offset applied
  /// - Note: Offset is applied server-side after filtering and before limiting.
  ///         The order is: filter → offset → limit
  public func offset(_ count: Int) -> TypedQuery<T> {
    var copy = self
    copy.offsetValue = count
    return copy
  }
  
  /// Convert to InstaQL dictionary format
  func toQuery() -> [String: Any] {
    var inner: [String: Any] = nestedQueries
    var modifiers: [String: Any] = [:]
    
    if let whereClause = whereClause {
      modifiers["where"] = whereClause
    }
    
    if let limitValue = limitValue {
      modifiers["limit"] = limitValue
    }
    
    if let offsetValue = offsetValue {
      modifiers["offset"] = offsetValue
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

// MARK: - Comparison Operators

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

// MARK: - Optional Int Operators

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

// MARK: - Optional String Operators

extension QueryField where Value == String? {
  public static func == (lhs: QueryField<String?>, rhs: String) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .eq, value: rhs)
  }
  
  public static func != (lhs: QueryField<String?>, rhs: String) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .neq, value: rhs)
  }
}

// MARK: - Optional Bool Operators

extension QueryField where Value == Bool? {
  public static func == (lhs: QueryField<Bool?>, rhs: Bool) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .eq, value: rhs)
  }
  
  public static func != (lhs: QueryField<Bool?>, rhs: Bool) -> PredicateExpression {
    ComparisonPredicate(field: lhs.name, op: .neq, value: rhs)
  }
}

// MARK: - Optional Double Operators

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

// MARK: - Logical Operators

public func && (lhs: PredicateExpression, rhs: PredicateExpression) -> PredicateExpression {
  LogicalPredicate(op: .and, left: lhs, right: rhs)
}

public func || (lhs: PredicateExpression, rhs: PredicateExpression) -> PredicateExpression {
  LogicalPredicate(op: .or, left: lhs, right: rhs)
}

// MARK: - Predicate Implementations

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
      // Simple equality doesn't need operator wrapper
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
    
    // Merge conditions into single where clause
    var merged: [String: Any] = [:]
    merged.merge(leftDict) { _, new in new }
    merged.merge(rightDict) { _, new in new }
    
    return merged
  }
}
