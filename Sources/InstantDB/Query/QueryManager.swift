import Foundation

// MARK: - QueryManager

/// Manages query subscriptions and their lifecycle.
///
/// ## Overview
/// QueryManager is the central coordinator for all active query subscriptions in the SDK.
/// It handles subscription creation, deduplication, result delivery, and cleanup.
///
/// ## Architecture
/// - Subscriptions are deduplicated by query hash (same query = same subscription)
/// - Multiple callbacks can be attached to a single subscription
/// - Results are cached and delivered to new subscribers immediately
/// - Server responses are routed to the correct subscription via eventId mapping
///
/// ## Thread Safety
/// This class is marked `@MainActor` because subscription state must be synchronized
/// with UI updates. All mutations happen on the main thread.
///
/// - TODO: Replace print statements with a proper Logger for configurable log levels
@MainActor
final class QueryManager {

  // MARK: - Properties
  
  private let localStorage: LocalStorage?

  /// Active subscriptions indexed by query hash.
  ///
  /// The hash is computed from the JSON representation of the query,
  /// ensuring identical queries share a single subscription.
  private var subscriptions: [String: QuerySubscription] = [:]

  /// Maps server event IDs to query hashes.
  ///
  /// When the server responds to a query, it includes the eventId we sent.
  /// This map lets us route the response to the correct subscription.
  private var eventIdToHash: [String: String] = [:]

  /// Callback invoked when a subscription is fully unsubscribed.
  ///
  /// The InstantClient uses this to send `remove-query` messages to the server,
  /// freeing server resources for queries we no longer care about.
  var onRemoveQuery: (([String: Any]) -> Void)?

  // MARK: - Initialization

  init(localStorage: LocalStorage? = nil) {
    self.localStorage = localStorage
  }

  // MARK: - Subscription Management

  /// Creates or joins a subscription for the given query.
  ///
  /// If a subscription for this exact query already exists, the callback is added
  /// to the existing subscription and receives cached data immediately (if available).
  ///
  /// - Parameters:
  ///   - query: InstaQL query dictionary (e.g., `["todos": ["$": ["where": ...]]]`)
  ///   - callback: Called when results arrive or update
  /// - Returns: An unsubscribe function. Call this to remove your callback.
  func subscribe(
    query: [String: Any],
    emitCachedResult: Bool = true,
    callback: @escaping QueryCallback
  ) -> (() -> Void) {
    let hash = QueryHashing.hash(query)

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

    if emitCachedResult, let cached = loadCachedQueryResult(hash: hash) {
      subscription.updateResult(cached)
      subscriptions[hash] = subscription
    } else {
      callback(.loading)
    }

    return { [weak self] in
      self?.unsubscribe(hash: hash, callback: callback)
    }
  }

  /// Retrieves a subscription by its hash.
  ///
  /// Used by InstantClient to get the eventId for sending to the server.
  func getSubscription(hash: String) -> QuerySubscription? {
    return subscriptions[hash]
  }

  /// Returns all active subscriptions.
  func getPendingSubscriptions() -> [QuerySubscription] {
    return Array(subscriptions.values)
  }
  
  // MARK: - Reconnection Support
  
  /// Returns all active query subscriptions for re-registration with the server.
  ///
  /// ## Why This Exists
  /// When the WebSocket connection drops and reconnects (due to network changes,
  /// VPN toggling, app backgrounding, etc.), the server loses track of our active
  /// subscriptions. Without re-sending these queries, the UI would remain stale
  /// showing the last known data or an error state.
  ///
  /// ## Discovery
  /// This was discovered during testing with corporate VPNs (Zscaler) where SSL
  /// inspection would cause connection failures. When the VPN was disabled, the
  /// connection would recover but the UI stayed stuck on "Connection Error" because
  /// the queries were never re-sent to the new server session.
  ///
  /// ## Usage
  /// Called by `InstantClient.resendActiveQueries()` after receiving `init-ok`.
  ///
  /// - Returns: Tuples of (eventId, query) for each active subscription that needs
  ///   to be re-registered with the server.
  func getActiveQueries() -> [(eventId: String, query: [String: Any])] {
    return subscriptions.values.map { ($0.eventId, $0.query) }
  }
  
  /// Transitions all subscriptions to loading state.
  ///
  /// ## Why This Exists
  /// During reconnection, we want the UI to show a loading state rather than
  /// stale data. This method is called before resending queries so that
  /// subscribers know fresh data is being fetched.
  ///
  /// - Note: Currently unused but available for future reconnection UX improvements.
  func markAllLoading() {
    for (hash, var subscription) in subscriptions {
      subscription.updateResult(.loading)
      subscriptions[hash] = subscription
    }
  }

  // MARK: - Server Response Handlers

  /// Processes a successful query response from the server.
  ///
  /// Called when the server sends `add-query-ok` with query results.
  /// Routes the data to the correct subscription via the eventId.
  ///
  /// - Parameters:
  ///   - eventId: The event ID from the server response
  ///   - rawResult: The raw result array from the server (before InstaQL processing)
  ///   - attributes: Schema attributes for processing
  func handleQueryResult(eventId: String?, rawResult: [[String: Any]], attributes: [Attribute]) {
    guard let eventId = eventId,
          let hash = eventIdToHash[eventId],
          var subscription = subscriptions[hash] else {
      return
    }
    
    // Extract order from the query for client-side sorting
    let order = extractOrder(from: subscription.query)
    
    // Process datalog-result into InstaQL format with client-side sorting
    let instaqlData = InstaQLProcessor.process(result: rawResult, attributes: attributes, order: order)
    
    // Extract page-info if available
    let pageInfo = rawResult.first?["data"] as? [String: Any]
    let pageInfoData = pageInfo?["page-info"] as? [String: Any]

    let queryResult = QueryResult.success(data: instaqlData, pageInfo: pageInfoData)
    subscription.updateResult(queryResult)
    subscriptions[hash] = subscription

    persistQueryResultCache(hash: hash, query: subscription.query, result: queryResult)
  }
  
  /// Handles the server's response when a query already exists.
  ///
  /// ## Why This Exists
  /// The server sends `add-query-exists` when we try to subscribe to a query
  /// that's already registered (e.g., after reconnection with the same eventId).
  /// We need to map the eventId and deliver any cached data.
  ///
  /// - Parameters:
  ///   - eventId: The eventId from our subscription request
  ///   - query: The query that already exists on the server
  func handleQueryExists(eventId: String?, query: [String: Any]) {
    guard let eventId = eventId else {
      InstantLog.warning("[QueryManager] handleQueryExists: missing eventId")
      return
    }
    
    // The eventId maps to the NEW subscription request, but the query already exists
    // Find the existing subscription by query hash
    let hash = QueryHashing.hash(query)
    
    guard let existingSubscription = subscriptions[hash] else {
      InstantLog.warning("[QueryManager] handleQueryExists: no existing subscription found for query")
      return
    }
    
    // Map the new eventId to the existing subscription's hash
    eventIdToHash[eventId] = hash
    
    // If we have cached data, deliver it to all callbacks (including the new one)
    if !existingSubscription.currentResult.isLoading {
      InstantLog.debug("[QueryManager] handleQueryExists: delivering cached result to callbacks")
      existingSubscription.notifyCallbacks()
    } else {
      InstantLog.debug("[QueryManager] handleQueryExists: subscription exists but still loading")
    }
  }

  /// Processes real-time updates from the server.
  ///
  /// ## How Real-Time Updates Work
  /// When data changes on the server (from any client), the server sends a
  /// `refresh-ok` message containing updated results for all affected queries.
  /// Each "computation" in the response contains the query and its new results.
  ///
  /// - Parameters:
  ///   - computations: Array of query/result pairs from the server
  ///   - attributes: Current schema attributes for result processing
  func handleRefresh(computations: [[String: Any]], attributes: [Attribute]) {
    InstantLog.debug("[QueryManager] handleRefresh with \(computations.count) computations, \(subscriptions.count) active subscriptions")
    
    // Debug: print all active subscription hashes
    for (hash, sub) in subscriptions {
      if let namespace = sub.query.keys.first {
        InstantLog.debug("[QueryManager]   active subscription: \(namespace) (hash: \(hash.prefix(20))...)")
      }
    }
    
    // Each computation has 'instaql-query' and 'instaql-result'
    for computation in computations {
      guard let query = computation["instaql-query"] as? [String: Any],
            let resultArray = computation["instaql-result"] as? [[String: Any]] else {
        InstantLog.warning("[QueryManager] computation missing instaql-query or instaql-result")
        continue
      }

      let hash = QueryHashing.hash(query)
      InstantLog.debug("[QueryManager] looking for subscription with hash: \(hash.prefix(20))... for query: \(query.keys)")
      
      guard var subscription = subscriptions[hash] else {
        InstantLog.warning("[QueryManager] ⚠️ No subscription found for refresh query!")
        // Debug: try to find a similar subscription
        for (_, sub) in subscriptions {
          if sub.query.keys == query.keys {
            InstantLog.debug("[QueryManager]   found subscription with same namespace but different hash")
            InstantLog.debug("[QueryManager]   server query: \(query)")
            InstantLog.debug("[QueryManager]   local query: \(sub.query)")
          }
        }
        continue
      }

      InstantLog.debug("[QueryManager] ✓ Found subscription, processing \(resultArray.count) results")
      
      // Extract order from the query for client-side sorting
      let order = extractOrder(from: subscription.query)
      
      // Process datalog-result into InstaQL format with client-side sorting
      let instaqlData = InstaQLProcessor.process(result: resultArray, attributes: attributes, order: order)

      // Extract page-info if available
      let pageInfo = resultArray.first?["data"] as? [String: Any]
      let pageInfoData = pageInfo?["page-info"] as? [String: Any]

      let queryResult = QueryResult.success(data: instaqlData, pageInfo: pageInfoData)
      subscription.updateResult(queryResult)
      subscriptions[hash] = subscription

      persistQueryResultCache(hash: hash, query: subscription.query, result: queryResult)
    }
  }

  // MARK: - Query Cache (Offline Support)

  private func loadCachedQueryResult(hash: String) -> QueryResult? {
    guard let localStorage else { return nil }

    do {
      guard let data = try localStorage.getCachedQueryResultSync(hash: hash) else { return nil }
      return queryResult(fromCachedData: data)
    } catch {
      InstantLog.debug("[QueryManager] Failed to load cached query result: \(error)")
      return nil
    }
  }

  private func persistQueryResultCache(hash: String, query: [String: Any], result: QueryResult) {
    guard let localStorage else { return }

    guard let queryData = QueryHashing.canonicalJSONData(query) else { return }
    guard let resultData = cachedData(from: result) else { return }

    Task {
      do {
        try await localStorage.cacheQueryResult(hash: hash, query: queryData, result: resultData)
      } catch {
        InstantLog.debug("[QueryManager] Failed to persist query cache: \(error)")
      }
    }
  }

  private func queryResult(fromCachedData data: Data) -> QueryResult? {
    do {
      guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
      guard let cachedData = obj["data"] as? [String: Any] else { return nil }

      let pageInfo = obj["pageInfo"] as? [String: Any]
      return QueryResult.success(data: cachedData, pageInfo: pageInfo)
    } catch {
      return nil
    }
  }

  private func cachedData(from result: QueryResult) -> Data? {
    var payload: [String: Any] = [
      "data": result.data
    ]

    if let pageInfo = result.pageInfo {
      payload["pageInfo"] = pageInfo
    } else {
      payload["pageInfo"] = NSNull()
    }

    return try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
  }

  /// Handles a query error from the server.
  ///
  /// Routes the error to the correct subscription so callbacks can display
  /// appropriate error UI.
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

  // MARK: - Private Helpers

  /// Removes a callback from a subscription.
  ///
  /// If no callbacks remain, the subscription is fully removed and the server
  /// is notified via `onRemoveQuery`.
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

  /// Computes a canonical hash for query deduplication.
  ///
  /// Identical queries produce identical hashes, allowing multiple subscribers
  /// to share a single server subscription.
  ///
  /// ## Why Canonical Hashing
  ///
  /// Dictionary key ordering in Swift is not guaranteed, and JSONSerialization
  /// may produce different JSON strings for semantically identical dictionaries.
  /// This function sorts keys recursively to ensure consistent hashing.
  ///
  /// For example, these two queries are semantically identical:
  /// - `["posts": ["$": [...], "author": [:]]]`
  /// - `["posts": ["author": [:], "$": [...]]]`
  ///
  /// Without canonical hashing, they would produce different hashes and the
  /// server's refresh updates would fail to match the local subscription.
  /// Extracts the order specification from an InstaQL query.
  ///
  /// Query format: `["namespace": ["$": ["order": ["fieldName": "asc|desc"]]]]`
  ///
  /// - Parameter query: The InstaQL query dictionary
  /// - Returns: QueryOrder if order is specified, nil otherwise
  private func extractOrder(from query: [String: Any]) -> QueryOrder? {
    // Get the first namespace (e.g., "posts")
    guard let (_, namespaceValue) = query.first,
          let namespaceDict = namespaceValue as? [String: Any],
          let modifiers = namespaceDict["$"] as? [String: Any],
          let orderDict = modifiers["order"] as? [String: String],
          let (field, directionStr) = orderDict.first else {
      return nil
    }
    
    let direction: QueryOrder.OrderDirection = directionStr == "asc" ? .asc : .desc
    return QueryOrder(field: field, direction: direction)
  }
}
