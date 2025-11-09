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

/// Callback type for query subscriptions
public typealias QueryCallback = (QueryResult) -> Void
