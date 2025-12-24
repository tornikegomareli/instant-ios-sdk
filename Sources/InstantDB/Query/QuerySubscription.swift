import Foundation

/// Internal model for tracking a query subscription
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

  /// Current result (cached)
  var currentResult: QueryResult

  /// When this subscription was created
  let createdAt: Date

  /// Create a new subscription
  init(query: [String: Any]) {
    self.id = UUID().uuidString
    self.query = query
    self.eventId = UUID().uuidString
    self.callbacks = []
    self.currentResult = .loading
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
