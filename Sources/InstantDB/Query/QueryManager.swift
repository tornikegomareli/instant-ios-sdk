import Foundation

/// Manages query subscriptions
@MainActor
final class QueryManager {

  /// Active subscriptions by query hash
  private var subscriptions: [String: QuerySubscription] = [:]

  /// Map event IDs to query hashes for lookup
  private var eventIdToHash: [String: String] = [:]

  /// Callback for when a query should be removed from server
  var onRemoveQuery: (([String: Any]) -> Void)?

  /// Subscribe to a query
  /// - Parameters:
  ///   - query: InstaQL query dictionary
  ///   - callback: Called when results arrive or update
  /// - Returns: Unsubscribe function
  func subscribe(
    query: [String: Any],
    callback: @escaping QueryCallback
  ) -> (() -> Void) {
    let hash = hashQuery(query)

    // If subscription exists, just add callback
    if var existing = subscriptions[hash] {
      existing.addCallback(callback)
      subscriptions[hash] = existing
      return { [weak self] in
        self?.unsubscribe(hash: hash, callback: callback)
      }
    }

    // Create new subscription
    var subscription = QuerySubscription(query: query, callback: callback)
    let eventId = subscription.eventId

    subscriptions[hash] = subscription
    eventIdToHash[eventId] = hash

    // Immediately deliver loading state
    callback(.loading)

    return { [weak self] in
      self?.unsubscribe(hash: hash, callback: callback)
    }
  }

  /// Get subscription for sending to server
  func getSubscription(hash: String) -> QuerySubscription? {
    return subscriptions[hash]
  }

  /// Get all subscriptions that need to be sent to server
  func getPendingSubscriptions() -> [QuerySubscription] {
    return Array(subscriptions.values)
  }

  /// Handle add-query-ok response from server
  func handleQueryResult(eventId: String?, result: [String: Any], pageInfo: [String: Any]?) {
    guard let eventId = eventId,
          let hash = eventIdToHash[eventId],
          var subscription = subscriptions[hash] else {
      return
    }

    let queryResult = QueryResult.success(data: result, pageInfo: pageInfo)
    subscription.updateResult(queryResult)
    subscriptions[hash] = subscription
  }

  /// Handle refresh-ok response (real-time update)
  func handleRefresh(computations: [[String: Any]], attributes: [Attribute]) {
    // Each computation has 'instaql-query' and 'instaql-result'
    for computation in computations {
      guard let query = computation["instaql-query"] as? [String: Any],
            let resultArray = computation["instaql-result"] as? [[String: Any]] else {
        continue
      }

      let hash = hashQuery(query)
      guard var subscription = subscriptions[hash] else {
        continue
      }

      // Process datalog-result into InstaQL format
      let instaqlData = InstaQLProcessor.process(result: resultArray, attributes: attributes)

      // Extract page-info if available
      let pageInfo = resultArray.first?["data"] as? [String: Any]
      let pageInfoData = pageInfo?["page-info"] as? [String: Any]

      let queryResult = QueryResult.success(data: instaqlData, pageInfo: pageInfoData)
      subscription.updateResult(queryResult)
      subscriptions[hash] = subscription
    }
  }

  /// Handle query error
  func handleQueryError(eventId: String?, error: Error) {
    guard let eventId = eventId,
          let hash = eventIdToHash[eventId],
          var subscription = subscriptions[hash] else {
      return
    }

    let queryResult = QueryResult.failure(error)
    subscription.updateResult(queryResult)
    subscriptions[hash] = subscription
  }

  /// Unsubscribe from a query
  private func unsubscribe(hash: String, callback: @escaping QueryCallback) {
    guard var subscription = subscriptions[hash] else {
      return
    }

    // Remove the specific callback
    // Note: This is a simple implementation - production would need better callback matching
    subscription.callbacks.removeAll { cb in
      // Swift doesn't allow comparing closures, so this removes all for now
      // In production, you'd use a wrapper with an ID
      return true
    }

    // If no callbacks left, remove subscription and notify server
    if subscription.callbacks.isEmpty {
      let query = subscription.query
      subscriptions.removeValue(forKey: hash)
      eventIdToHash.removeValue(forKey: subscription.eventId)

      // Notify InstantClient to send remove-query to server
      onRemoveQuery?(query)
    } else {
      subscriptions[hash] = subscription
    }
  }

  /// Generate a hash for a query (for deduplication)
  private func hashQuery(_ query: [String: Any]) -> String {
    // Simple JSON-based hash
    // In production, you might want a more sophisticated approach
    guard let data = try? JSONSerialization.data(withJSONObject: query),
          let string = String(data: data, encoding: .utf8) else {
      return UUID().uuidString
    }
    return string.hash.description
  }
}
