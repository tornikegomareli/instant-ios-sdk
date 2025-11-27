import Foundation

extension TypedQuery: @unchecked Sendable where T: Sendable {}
extension TypedResult: @unchecked Sendable where T: Sendable {}

extension TypedQuery {
  /// Returns an AsyncStream of query results
  ///
  /// This provides a modern async/await interface for subscribing to query updates.
  /// The stream automatically cleans up when the Task is cancelled.
  ///
  /// Example:
  /// ```swift
  /// // In a ViewModel
  /// Task {
  ///     for await result in db.query(Goal.self).values {
  ///         self.goals = result.data
  ///         self.isLoading = result.isLoading
  ///     }
  /// }
  ///
  /// // In TCA Reducer
  /// case .subscribeToGoals:
  ///     return .run { send in
  ///         for await result in db.query(Goal.self).values {
  ///             await send(.goalsUpdated(result.data))
  ///         }
  ///     }
  /// ```
  public func values(using client: InstantClient) -> AsyncStream<TypedResult<T>> where T: Sendable {
    AsyncStream { continuation in
      let query = self
      
      Task { @MainActor in
        do {
          let token = try client.subscribe(query) { result in
            continuation.yield(result)
          }
          
          continuation.onTermination = { _ in
            Task { @MainActor in
              token.cancel()
            }
          }
          
        } catch {
          continuation.yield(.failure(error))
          continuation.finish()
        }
      }
    }
  }
}

extension InstantClient {
  /// Subscribe to a query using AsyncStream
  ///
  /// This is a convenience method that creates an AsyncStream for the query.
  /// The stream automatically cleans up when the Task is cancelled.
  ///
  /// Example:
  /// ```swift
  /// Task {
  ///     for await result in db.stream(db.query(Goal.self)) {
  ///         self.goals = result.data
  ///     }
  /// }
  /// ```
  public func stream<T: InstantEntity & Sendable>(_ query: TypedQuery<T>) -> AsyncStream<TypedResult<T>> {
    query.values(using: self)
  }
}
