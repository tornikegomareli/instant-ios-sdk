import Foundation

/// Internal model for tracking a query subscription.
///
/// ## Optimistic Update Architecture
///
/// Each subscription stores the **raw server result** (`rawServerResult`) alongside
/// the processed `currentResult`. When pending mutations exist, `QueryManager`
/// rebuilds the query output by:
///
/// 1. Extracting triples from `rawServerResult`
/// 2. Building a `TripleStore` from those triples
/// 3. Applying pending mutations (sorted by order, skipping already-processed ones)
/// 4. Re-running `InstaQLProcessor` on the optimistic store
/// 5. Delivering the merged result to callbacks
///
/// This matches the TypeScript SDK's `dataForQuery` pattern in `Reactor.js`.
struct QuerySubscription {
  struct CallbackEntry {
    let id: UUID
    let callback: QueryCallback
  }

  /// Unique identifier for this subscription
  let id: String

  /// The InstaQL query
  let query: [String: Any]

  /// Event ID sent to server
  let eventId: String

  /// Callbacks to notify when data arrives
  var callbacks: [CallbackEntry]

  /// Current result (cached, may include optimistic updates)
  var currentResult: QueryResult

  /// Raw server result from `add-query-ok` or `refresh-ok`.
  ///
  /// This is the authoritative server state, before any optimistic mutations
  /// are applied. We keep it so that `dataForQuery` can always rebuild the
  /// optimistic view from a clean base.
  ///
  /// Format: `[[String: Any]]` — the `instaql-result` array from the server.
  ///
  /// ## TypeScript Reference
  /// Equivalent to `querySubs[hash].result.store` in Reactor.js, which stores
  /// the base server TripleStore per subscription.
  var rawServerResult: [[String: Any]]?

  /// The server's processed transaction ID watermark for this subscription.
  ///
  /// Mutations with `txId <= processedTxId` are already reflected in
  /// `rawServerResult` and should be skipped during optimistic application.
  ///
  /// ## TypeScript Reference
  /// Equivalent to `querySubs[hash].result.processedTxId` in Reactor.js.
  var processedTxId: Int64?

  /// When this subscription was created
  let createdAt: Date

  /// Create a new subscription
  init(query: [String: Any]) {
    self.id = UUID().uuidString
    self.query = query
    self.eventId = UUID().uuidString
    self.callbacks = []
    self.currentResult = .loading
    self.rawServerResult = nil
    self.processedTxId = nil
    self.createdAt = Date()
  }

  /// Add a callback to this subscription
  @discardableResult
  mutating func addCallback(_ callback: @escaping QueryCallback) -> UUID {
    let callbackId = UUID()
    callbacks.append(CallbackEntry(id: callbackId, callback: callback))
    // Immediately call with current result if we have data
    if !currentResult.isLoading {
      callback(currentResult)
    }
    return callbackId
  }

  /// Remove a callback by identifier.
  mutating func removeCallback(id: UUID) {
    callbacks.removeAll { $0.id == id }
  }

  /// Update the result and notify all callbacks
  mutating func updateResult(_ result: QueryResult) {
    currentResult = result
    notifyCallbacks()
  }

  /// Notify all callbacks with current result
  func notifyCallbacks() {
    InstantLog.debug("[QuerySubscription] Notifying \(callbacks.count) callbacks")
    callbacks.forEach { $0.callback(currentResult) }
  }
}
