import Foundation

/// Type-safe result for queries
public struct TypedResult<T: InstantEntity> {
  /// Decoded entities of type T
  public let data: [T]
  
  /// Whether the query is loading
  public let isLoading: Bool
  
  /// Error if query failed
  public let error: Error?
  
  /// Initialize a loading state
  public static var loading: TypedResult<T> {
    TypedResult(data: [], isLoading: true, error: nil)
  }
  
  /// Initialize with data
  public static func success(data: [T]) -> TypedResult<T> {
    TypedResult(data: data, isLoading: false, error: nil)
  }
  
  /// Initialize with error
  public static func failure(_ error: Error) -> TypedResult<T> {
    TypedResult(data: [], isLoading: false, error: error)
  }
}

/// Callback type for typed query subscriptions
public typealias TypedQueryCallback<T: InstantEntity> = (TypedResult<T>) -> Void
