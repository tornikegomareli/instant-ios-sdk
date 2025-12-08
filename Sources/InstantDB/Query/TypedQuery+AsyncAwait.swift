import Foundation

extension TypedQuery: @unchecked Sendable where T: Sendable {}
extension TypedResult: @unchecked Sendable where T: Sendable {}

extension TypedQuery {
  /// Returns an `AsyncStream` of query results for real-time data subscription.
  ///
  /// This method provides a modern async/await interface for subscribing to query updates
  /// in real-time. The stream automatically manages subscription lifecycle and cleans up
  /// resources when the task is cancelled or completed.
  ///
  /// - Returns: An `AsyncStream` that yields `TypedResult<T>` containing query data and pagination info
  ///
  /// - Important: The query must be created with a valid `InstantClient` instance.
  ///   If no client is available, the stream will finish immediately.
  ///
  /// ## Basic Usage
  /// ```swift
  /// for await result in db.query(Goal.self).values() {
  ///   self.goals = result.data
  /// }
  /// ```
  ///
  /// ## Cursor-Based Pagination
  /// ```swift
  /// // First page
  /// for await result in db.query(Goal.self).order(by: \.title).first(10).values() {
  ///   self.goals = result.data
  ///   self.pageInfo = result.pageInfo
  ///   self.hasMore = result.pageInfo?.hasNextPage ?? false
  /// }
  ///
  /// // Load next page
  /// if let cursor = pageInfo?.endCursor {
  ///   for await result in db.query(Goal.self)
  ///       .order(by: \.title)
  ///       .first(10)
  ///       .after(cursor)
  ///       .values() {
  ///     self.goals.append(contentsOf: result.data)
  ///     self.pageInfo = result.pageInfo
  ///   }
  /// }
  /// ```
  ///
  /// ## Automatic Cleanup
  /// The subscription is automatically cancelled when:
  /// - The containing `Task` is cancelled
  /// - The `AsyncStream` is deallocated
  /// - The stream reaches completion
  public func values() -> AsyncStream<TypedResult<T>> where T: Sendable {
    guard let client = self.client else {
      print("[InstantDB] Error: Query was created without an InstantClient instance.")
      return AsyncStream { $0.finish() }
    }

    return AsyncStream { continuation in
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
  /// Creates an `AsyncStream` for real-time query subscription.
  ///
  /// Convenience method equivalent to `query.values()`.
  ///
  /// ```swift
  /// for await result in db.stream(db.query(Goal.self)) {
  ///   self.goals = result.data
  /// }
  /// ```
  public func stream<T: InstantEntity & Sendable>(_ query: TypedQuery<T>) -> AsyncStream<TypedResult<T>> {
    query.values()
  }
}
