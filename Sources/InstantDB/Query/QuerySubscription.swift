import Foundation

/// Internal model for tracking a query subscription
struct QuerySubscription {
  /// Unique identifier for this subscription
  let id: String

  /// The InstaQL query
  let query: [String: Any]

  /// Event ID sent to server
  let eventId: String

  /// Callbacks to notify when data arrives
  var callbacks: [QueryCallback]

  /// Current result (cached)
  var currentResult: QueryResult

  /// When this subscription was created
  let createdAt: Date

  /// Create a new subscription
  init(query: [String: Any], callback: @escaping QueryCallback) {
    self.id = UUID().uuidString
    self.query = query
    self.eventId = UUID().uuidString
    self.callbacks = [callback]
    self.currentResult = .loading
    self.createdAt = Date()
  }

  /// Add a callback to this subscription
  mutating func addCallback(_ callback: @escaping QueryCallback) {
    callbacks.append(callback)
    // Immediately call with current result if we have data
    if !currentResult.isLoading {
      callback(currentResult)
    }
  }

  /// Remove a callback
  mutating func removeCallback(at index: Int) {
    guard index < callbacks.count else { return }
    callbacks.remove(at: index)
  }

  /// Update the result and notify all callbacks
  mutating func updateResult(_ result: QueryResult) {
    currentResult = result
    notifyCallbacks()
  }

  /// Notify all callbacks with current result
  func notifyCallbacks() {
    callbacks.forEach { $0(currentResult) }
  }
}
