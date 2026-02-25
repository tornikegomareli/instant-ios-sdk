import Foundation

// MARK: - QueryManager

/// Manages query subscriptions with optimistic updates.
///
/// ## Optimistic Update Architecture (Parity with TypeScript Reactor.js)
///
/// Each subscription stores the **raw server result** as the base truth. When results
/// are delivered to callbacks, `dataForQuery` merges pending mutations on top:
///
/// 1. Extract triples from the raw server result
/// 2. Build a fresh `TripleStore` from those triples
/// 3. Apply pending mutations (skipping those already processed by the server)
/// 4. Re-run `InstaQLProcessor` on the optimistic store's triples
///
/// This matches the TypeScript SDK's `dataForQuery` → `_applyOptimisticUpdates` →
/// `instaql()` pipeline.
///
/// ## Thread Safety
/// `@MainActor` — all subscription state is synchronized with UI updates.
@MainActor
final class QueryManager {

  // MARK: - Properties
  
  private let localStorage: LocalStorage?

  /// In-memory tracker for pending mutations.
  ///
  /// `InstantClient` adds/confirms/cleans up mutations through this manager.
  /// `dataForQuery` reads pending mutations to merge optimistic updates.
  let optimisticManager = OptimisticUpdateManager()

  /// Active subscriptions indexed by query hash.
  private var subscriptions: [String: QuerySubscription] = [:]

  /// Maps server event IDs to query hashes.
  private var eventIdToHash: [String: String] = [:]

  /// Callback invoked when a subscription is fully unsubscribed.
  var onRemoveQuery: (([String: Any]) -> Void)?

  /// Current attributes from the server. Set by InstantClient whenever
  /// attributes are updated (init-ok, refresh-ok, transact-ok).
  var attributes: [Attribute] = []

  // MARK: - Initialization

  init(localStorage: LocalStorage? = nil) {
    self.localStorage = localStorage
  }

  // MARK: - Subscription Management

  /// Creates or joins a subscription for the given query.
  func subscribe(
    query: [String: Any],
    emitCachedResult: Bool = true,
    callback: @escaping QueryCallback
  ) -> (() -> Void) {
    let hash = QueryHashing.hash(query)

    if var existing = subscriptions[hash] {
      let callbackId = existing.addCallback(callback)
      subscriptions[hash] = existing
      return { [weak self] in
        self?.unsubscribe(hash: hash, callbackId: callbackId)
      }
    }

    var subscription = QuerySubscription(query: query)
    let eventId = subscription.eventId
    let callbackId = subscription.addCallback(callback)

    subscriptions[hash] = subscription
    eventIdToHash[eventId] = hash

    if emitCachedResult, let cached = loadCachedQueryResult(hash: hash) {
      subscription.updateResult(cached)
      subscriptions[hash] = subscription
    } else {
      callback(.loading)
    }

    return { [weak self] in
      self?.unsubscribe(hash: hash, callbackId: callbackId)
    }
  }

  func getSubscription(hash: String) -> QuerySubscription? {
    return subscriptions[hash]
  }

  func getPendingSubscriptions() -> [QuerySubscription] {
    return Array(subscriptions.values)
  }
  
  // MARK: - Reconnection Support
  
  func getActiveQueries() -> [(eventId: String, query: [String: Any])] {
    return subscriptions.values.map { ($0.eventId, $0.query) }
  }
  
  func markAllLoading() {
    for (hash, var subscription) in subscriptions {
      subscription.updateResult(.loading)
      subscriptions[hash] = subscription
    }
  }

  // MARK: - Optimistic Update Pipeline

  /// Computes the query result for a subscription, merging pending mutations
  /// on top of the server's base data.
  ///
  /// ## TypeScript Reference
  /// Equivalent to `dataForQuery(hash)` in Reactor.js (lines 1149-1186).
  ///
  /// Flow:
  /// 1. Get raw server result from subscription
  /// 2. Extract triples from the server result
  /// 3. Build a TripleStore from those triples
  /// 4. Apply each pending mutation (skipping already-processed ones)
  /// 5. Extract triples back from the optimistic store
  /// 6. Re-run InstaQLProcessor
  private func dataForQuery(hash: String) -> QueryResult? {
    guard let subscription = subscriptions[hash] else { return nil }
    guard let rawResult = subscription.rawServerResult else { return nil }

    let order = extractOrder(from: subscription.query)
    let pendingMutations = optimisticManager.allMutations

    // Fast path: no pending mutations → use server result directly.
    if pendingMutations.isEmpty {
      let instaqlData = InstaQLProcessor.process(
        result: rawResult,
        attributes: attributes,
        order: order
      )
      let pageInfo = extractPageInfo(from: rawResult)
      return .success(data: instaqlData, pageInfo: pageInfo)
    }

    // Slow path: build a TripleStore, apply optimistic mutations, re-run InstaQL.
    let attrsStore = AttrsStore(attrs: attributes)
    let store = buildTripleStore(from: rawResult, attrsStore: attrsStore)

    // Apply each pending mutation that the server hasn't processed yet.
    // This is the equivalent of TypeScript's `_applyOptimisticUpdates`.
    let processedTxId = subscription.processedTxId
    for mutation in pendingMutations {
      if let txId = mutation.txId, let processed = processedTxId, txId <= processed {
        // Server already includes this mutation's effects — skip.
        continue
      }
      // Convert AnyCodableValue steps back to [[Any]] for applyTransaction.
      let txSteps: [[Any]] = mutation.txSteps.map { step in
        step.map { $0.value }
      }
      _ = applyTransaction(store: store, attrsStore: attrsStore, txSteps: txSteps)
    }

    // Extract all triples from the optimistic store and wrap them in the
    // format InstaQLProcessor.process() expects.
    let optimisticTriples = store.allTriples()
    let wrappedResult = wrapTriplesAsServerResult(optimisticTriples)

    let instaqlData = InstaQLProcessor.process(
      result: wrappedResult,
      attributes: attributes,
      order: order
    )
    let pageInfo = extractPageInfo(from: rawResult)
    return .success(data: instaqlData, pageInfo: pageInfo)
  }

  /// Recompute and deliver results for a single subscription.
  ///
  /// ## TypeScript Reference
  /// Equivalent to `notifyOne(hash)` in Reactor.js (lines 1198-1208).
  private func notifyOne(hash: String) {
    guard var subscription = subscriptions[hash] else { return }
    guard let result = dataForQuery(hash: hash) else { return }

    subscription.updateResult(result)
    subscriptions[hash] = subscription

    persistQueryResultCache(hash: hash, query: subscription.query, result: result)
  }

  /// Recompute and deliver results for ALL active subscriptions.
  ///
  /// Called after a mutation is added to `optimisticManager` so that every
  /// query immediately reflects the local change.
  ///
  /// ## TypeScript Reference
  /// Equivalent to `notifyAll()` in Reactor.js (lines 1226-1233).
  func notifyAll() {
    for hash in subscriptions.keys {
      notifyOne(hash: hash)
    }
  }

  // MARK: - Server Response Handlers

  /// Processes a successful query response (`add-query-ok`).
  ///
  /// Stores the raw server result, then delivers via `notifyOne` which merges
  /// any pending optimistic mutations before notifying callbacks.
  func handleQueryResult(eventId: String?, rawResult: [[String: Any]], attributes: [Attribute], processedTxId: Int64? = nil) {
    guard let eventId = eventId,
          let hash = eventIdToHash[eventId],
          var subscription = subscriptions[hash] else {
      return
    }

    // Store the raw server result as the authoritative base.
    subscription.rawServerResult = rawResult
    subscription.processedTxId = processedTxId
    self.attributes = attributes
    subscriptions[hash] = subscription

    // Deliver via notifyOne, which merges optimistic mutations on top.
    notifyOne(hash: hash)
  }
  
  /// Handles `add-query-exists`.
  func handleQueryExists(eventId: String?, query: [String: Any]) {
    guard let eventId = eventId else {
      InstantLog.warning("[QueryManager] handleQueryExists: missing eventId")
      return
    }
    
    let hash = QueryHashing.hash(query)
    
    guard let existingSubscription = subscriptions[hash] else {
      InstantLog.warning("[QueryManager] handleQueryExists: no existing subscription found for query")
      return
    }
    
    eventIdToHash[eventId] = hash
    
    if !existingSubscription.currentResult.isLoading {
      existingSubscription.notifyCallbacks()
    }
  }

  /// Processes real-time updates (`refresh-ok`).
  ///
  /// For each computation, stores the new raw server result, then delivers
  /// via `notifyOne` which merges any remaining optimistic mutations on top.
  func handleRefresh(computations: [[String: Any]], attributes: [Attribute], processedTxId: Int64? = nil) {
    self.attributes = attributes

    for computation in computations {
      guard let query = computation["instaql-query"] as? [String: Any],
            let resultArray = computation["instaql-result"] as? [[String: Any]] else {
        continue
      }

      let hash = QueryHashing.hash(query)
      
      guard var subscription = subscriptions[hash] else {
        continue
      }

      // Update the raw server result base and processedTxId.
      subscription.rawServerResult = resultArray
      if let processedTxId {
        subscription.processedTxId = processedTxId
      }
      subscriptions[hash] = subscription

      // Deliver via notifyOne, which re-applies remaining optimistic mutations.
      notifyOne(hash: hash)
    }

    // Clean up mutations that ALL subscriptions have caught up on.
    cleanupProcessedMutations()
  }

  // MARK: - Mutation Lifecycle

  /// Clean up pending mutations that all subscriptions have processed.
  ///
  /// Finds the minimum `processedTxId` across all subscriptions. Any mutation
  /// with `txId <= minProcessedTxId` is reflected in every subscription's server
  /// data and can be safely removed.
  ///
  /// ## TypeScript Reference
  /// Equivalent to `_cleanupPendingMutationsQueries()` in Reactor.js (lines 1384-1399).
  func cleanupProcessedMutations() {
    var minProcessedTxId: Int64 = .max

    for subscription in subscriptions.values {
      if let processedTxId = subscription.processedTxId {
        minProcessedTxId = min(minProcessedTxId, processedTxId)
      }
    }

    guard minProcessedTxId < .max else { return }
    optimisticManager.cleanupProcessedMutations(processedTxId: minProcessedTxId)
  }

  // MARK: - Triple Extraction Helpers

  /// Builds a `TripleStore` from raw server result arrays.
  ///
  /// Extracts triples from the server's `join-rows` format and indexes them.
  private func buildTripleStore(from rawResult: [[String: Any]], attrsStore: AttrsStore) -> TripleStore {
    let store = TripleStore()

    for item in rawResult {
      guard let data = item["data"] as? [String: Any],
            let datalogResult = data["datalog-result"] as? [String: Any],
            let joinRows = datalogResult["join-rows"] as? [[[Any]]] else {
        continue
      }

      for rows in joinRows {
        for tripleArray in rows {
          guard tripleArray.count >= 3,
                let entityId = tripleArray[0] as? String,
                let attrId = tripleArray[1] as? String else {
            continue
          }

          let value = tripleArray[2]
          let createdAt: Int64 = tripleArray.count > 3 ? (tripleArray[3] as? Int64 ?? 0) : 0
          let tripleValue = TripleValue(fromAny: value)

          let attr = attrsStore.getAttr(attrId)
          let hasCardinalityOne = attr?.cardinality == .one
          let isRef = attr?.valueType == .ref

          let triple = Triple(
            entityId: entityId,
            attributeId: attrId,
            value: tripleValue,
            createdAt: createdAt
          )
          store.addTriple(triple, hasCardinalityOne: hasCardinalityOne, isRef: isRef)
        }
      }
    }

    return store
  }

  /// Wraps extracted triples into the format `InstaQLProcessor.process()` expects.
  ///
  /// InstaQLProcessor expects: `[["data": ["datalog-result": ["join-rows": [[[Any]]]]]]]`
  private func wrapTriplesAsServerResult(_ triples: [Triple]) -> [[String: Any]] {
    let joinRows: [[[Any]]] = triples.map { triple in
      [[triple.entityId, triple.attributeId, triple.value.toAny(), triple.createdAt]]
    }

    return [
      [
        "data": [
          "datalog-result": [
            "join-rows": joinRows
          ]
        ] as [String: Any]
      ]
    ]
  }

  /// Extracts page-info from raw server result.
  private func extractPageInfo(from rawResult: [[String: Any]]) -> [String: Any]? {
    let pageInfo = rawResult.first?["data"] as? [String: Any]
    return pageInfo?["page-info"] as? [String: Any]
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

  private func unsubscribe(hash: String, callbackId: UUID) {
    guard var subscription = subscriptions[hash] else {
      return
    }

    subscription.removeCallback(id: callbackId)

    if subscription.callbacks.isEmpty {
      let query = subscription.query
      subscriptions.removeValue(forKey: hash)
      eventIdToHash.removeValue(forKey: subscription.eventId)
      onRemoveQuery?(query)
    } else {
      subscriptions[hash] = subscription
    }
  }

  private func extractOrder(from query: [String: Any]) -> QueryOrder? {
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
