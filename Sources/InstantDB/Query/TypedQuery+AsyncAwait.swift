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
  /// - Returns: An `AsyncStream` that yields `TypedResult<T>` containing the latest query data
  ///
  /// - Important: The query must be created with a valid `InstantClient` instance.
  ///   If no client is available, the stream will finish immediately with an error message.
  ///
  /// ## Usage Examples
  ///
  /// ### In a ViewModel
  /// ```swift
  /// @MainActor
  /// class GoalViewModel: ObservableObject {
  ///     @Published var goals: [Goal] = []
  ///     @Published var isLoading = false
  ///
  ///     func subscribeToGoals() {
  ///      Task {
  ///             for await result in db.query(Goal.self).values() {
  ///                 self.goals = result.data
  ///                 self.isLoading = result.isLoading
  ///             }
  ///      }
  ///     }
  /// }
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
  /// This convenience method provides an alternative way to subscribe to query results
  /// using async/await patterns. It's functionally equivalent to calling `query.values()`,
  /// but provides a more explicit API when working directly with the client.
  ///
  /// - Parameter query: The `TypedQuery` to subscribe to for real-time updates
  /// - Returns: An `AsyncStream` that yields `TypedResult<T>` containing the latest query data
  ///
  /// ## Usage Examples
  ///
  /// ### Basic Subscription
  /// ```swift
  /// Task {
  ///     for await result in db.stream(db.query(Goal.self)) {
  ///         self.goals = result.data
  ///     }
  /// }
  /// ```
  ///
  /// ### With Query Building
  /// ```swift
  /// let query = db.query(Goal.self).where("completed", isEqualTo: false)
  /// 
  /// Task {
  ///     for await result in db.stream(query) {
  ///         self.activeGoals = result.data
  ///     }
  /// }
  /// ```
  ///
  /// - Note: This method delegates to `TypedQuery.values()` and provides the same
  ///   automatic cleanup and lifecycle management.
  ///
  /// - SeeAlso: ``TypedQuery/values()`` for detailed documentation on stream behavior
  public func stream<T: InstantEntity & Sendable>(_ query: TypedQuery<T>) -> AsyncStream<TypedResult<T>> {
    query.values()
  }
}
