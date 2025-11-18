import Foundation

/// Result of a query subscription
public struct QueryResult {
  /// The query data as a dictionary
  public let data: [String: Any]

  /// Page information for paginated queries
  public let pageInfo: [String: Any]?

  /// Whether the query is loading
  public let isLoading: Bool

  /// Error if query failed
  public let error: Error?

  /// Initialize a loading state
  public static var loading: QueryResult {
    QueryResult(data: [:], pageInfo: nil, isLoading: true, error: nil)
  }

  /// Initialize with data
  public static func success(data: [String: Any], pageInfo: [String: Any]? = nil) -> QueryResult {
    QueryResult(data: data, pageInfo: pageInfo, isLoading: false, error: nil)
  }

  /// Initialize with error
  public static func failure(_ error: Error) -> QueryResult {
    QueryResult(data: [:], pageInfo: nil, isLoading: false, error: error)
  }

  /// Get a namespace from the result
  public subscript(namespace: String) -> [[String: Any]]? {
    return data[namespace] as? [[String: Any]]
  }
}

// MARK: - Convenience Helpers

extension QueryResult {

  /// Get entities for namespace, never nil (returns empty array if not found)
  public func get(_ namespace: String) -> [[String: Any]] {
    data[namespace] as? [[String: Any]] ?? []
  }

  /// Get entities with custom default
  public func get(_ namespace: String, default: [[String: Any]]) -> [[String: Any]] {
    data[namespace] as? [[String: Any]] ?? `default`
  }

  /// Get first entity in namespace
  public func getFirst(_ namespace: String) -> [String: Any]? {
    get(namespace).first
  }
}

// MARK: - Codable Support

extension QueryResult {

  /// Decode entities from namespace to Codable array
  ///
  /// Example:
  /// ```swift
  /// struct Goal: Codable {
  ///   let id: String
  ///   let title: String
  /// }
  ///
  /// db.subscribeQuery(Q.namespace("goals")) { result in
  ///   let goals: [Goal] = result.decode(Goal.self, from: "goals")
  /// }
  /// ```
  public func decode<T: Decodable>(_ type: T.Type, from namespace: String) -> [T] {
    let entities = get(namespace)
    guard !entities.isEmpty else { return [] }

    do {
      let jsonData = try JSONSerialization.data(withJSONObject: entities)
      return try JSONDecoder().decode([T].self, from: jsonData)
    } catch {
      print("[InstantDB] Failed to decode \(namespace) to [\(T.self)]: \(error)")
      return []
    }
  }

  /// Decode single entity from namespace
  ///
  /// Returns the first entity decoded to the specified type.
  ///
  /// Example:
  /// ```swift
  /// let goal: Goal? = result.decodeFirst(Goal.self, from: "goals")
  /// ```
  public func decodeFirst<T: Decodable>(_ type: T.Type, from namespace: String) -> T? {
    decode(type, from: namespace).first
  }

  /// Decode entities using custom JSONDecoder
  ///
  /// Use this when you need custom decoding strategies (e.g., date formatting, key conversion)
  ///
  /// Example:
  /// ```swift
  /// let decoder = JSONDecoder()
  /// decoder.dateDecodingStrategy = .iso8601
  /// decoder.keyDecodingStrategy = .convertFromSnakeCase
  ///
  /// let goals: [Goal] = result.decode(Goal.self, from: "goals", decoder: decoder)
  /// ```
  public func decode<T: Decodable>(
    _ type: T.Type,
    from namespace: String,
    decoder: JSONDecoder
  ) -> [T] {
    let entities = get(namespace)
    guard !entities.isEmpty else { return [] }

    do {
      let jsonData = try JSONSerialization.data(withJSONObject: entities)
      return try decoder.decode([T].self, from: jsonData)
    } catch {
      print("[InstantDB] Failed to decode \(namespace) to [\(T.self)]: \(error)")
      return []
    }
  }
}

/// Callback type for query subscriptions
public typealias QueryCallback = (QueryResult) -> Void
