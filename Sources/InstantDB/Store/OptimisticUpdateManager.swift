import Foundation

// MARK: - OptimisticUpdateManager

/// Manages optimistic updates for local-first functionality.
///
/// When a user makes a change, we want to show it immediately in the UI (optimistic update)
/// while sending it to the server in the background. This manager tracks pending mutations
/// and applies them on top of server state.
///
/// ## How it works
///
/// 1. User makes a change (e.g., creates a todo)
/// 2. We generate transaction steps and add them to the pending queue
/// 3. The change is applied locally immediately
/// 4. We send the transaction to the server
/// 5. Server responds with `transact-ok` including a `tx-id`
/// 6. We mark the mutation as confirmed
/// 7. When server sends `refresh-ok` with `processedTxId`, we remove confirmed mutations
///
/// ## Example
///
/// ```swift
/// let manager = OptimisticUpdateManager()
///
/// // Add a mutation
/// let eventId = manager.addMutation([
///   ["add-triple", "todo-1", "attr-title", "Buy milk"]
/// ])
///
/// // Later, server confirms
/// manager.confirmMutation(eventId: eventId, txId: 12345)
///
/// // Apply optimistic updates to a store
/// let optimisticStore = manager.applyOptimisticUpdates(
///   to: serverStore,
///   attrsStore: attrsStore,
///   processedTxId: 12340
/// )
/// ```
///
/// - Note: This is ported from `instant/client/packages/core/src/Reactor.js` pendingMutations handling
public final class OptimisticUpdateManager: @unchecked Sendable {
  private let lock = NSRecursiveLock()
  
  /// Pending mutations keyed by event ID
  private var pendingMutations: [String: PendingMutation] = [:]
  
  /// Counter for ordering mutations
  private var orderCounter: Int = 0
  
  // MARK: - Initialization
  
  public init() {}
  
  /// Creates a manager with existing mutations (e.g., loaded from storage)
  public init(mutations: [String: PendingMutation]) {
    self.pendingMutations = mutations
    self.orderCounter = mutations.values.map(\.order).max() ?? 0
  }
  
  // MARK: - Mutation Operations
  
  /// Adds a new mutation to the pending queue.
  ///
  /// - Parameter txSteps: The transaction steps to apply
  /// - Returns: The event ID for tracking this mutation
  @discardableResult
  public func addMutation(_ txSteps: [[Any]]) -> String {
    lock.withLock {
      let eventId = UUID().uuidString
      orderCounter += 1
      
      let mutation = PendingMutation(
        eventId: eventId,
        txSteps: txSteps,
        createdAt: Date(),
        order: orderCounter
      )
      
      pendingMutations[eventId] = mutation
      return eventId
    }
  }
  
  /// Confirms a mutation with the server's transaction ID.
  ///
  /// Called when we receive `transact-ok` from the server.
  ///
  /// - Parameters:
  ///   - eventId: The event ID of the mutation
  ///   - txId: The server-assigned transaction ID
  public func confirmMutation(eventId: String, txId: Int64) {
    lock.withLock {
      guard var mutation = pendingMutations[eventId] else { return }
      mutation.txId = txId
      mutation.confirmedAt = Date()
      pendingMutations[eventId] = mutation
    }
  }
  
  /// Removes a mutation from the queue.
  ///
  /// Called when a mutation fails or is no longer needed.
  ///
  /// - Parameter eventId: The event ID of the mutation to remove
  public func removeMutation(eventId: String) {
    lock.withLock {
      pendingMutations.removeValue(forKey: eventId)
    }
  }
  
  /// Gets a mutation by event ID.
  public func getMutation(eventId: String) -> PendingMutation? {
    lock.withLock { pendingMutations[eventId] }
  }
  
  /// Gets all pending mutations sorted by order.
  public var allMutations: [PendingMutation] {
    lock.withLock {
      pendingMutations.values.sorted { $0.order < $1.order }
    }
  }
  
  /// Gets mutations that haven't been confirmed yet.
  public var unconfirmedMutations: [PendingMutation] {
    lock.withLock {
      pendingMutations.values
        .filter { $0.txId == nil }
        .sorted { $0.order < $1.order }
    }
  }
  
  /// Cleans up mutations that have been processed by the server.
  ///
  /// Called when we receive `refresh-ok` with a `processedTxId`.
  /// Mutations with `txId <= processedTxId` have been fully processed
  /// and can be removed from the queue.
  ///
  /// - Parameter processedTxId: The highest transaction ID the server has processed
  public func cleanupProcessedMutations(processedTxId: Int64) {
    lock.withLock {
      pendingMutations = pendingMutations.filter { _, mutation in
        guard let txId = mutation.txId else {
          // Keep unconfirmed mutations
          return true
        }
        // Remove if server has processed this mutation
        return txId > processedTxId
      }
    }
  }
  
  /// Cleans up old confirmed mutations that may have timed out.
  ///
  /// If a mutation has been confirmed but not cleaned up after a timeout,
  /// we assume the query is unaffected and remove it.
  ///
  /// - Parameter timeout: Time interval after which to clean up (default 30 seconds)
  public func cleanupTimedOutMutations(timeout: TimeInterval = 30) {
    lock.withLock {
      let now = Date()
      pendingMutations = pendingMutations.filter { _, mutation in
        guard let confirmedAt = mutation.confirmedAt else {
          // Keep unconfirmed mutations
          return true
        }
        // Remove if confirmed more than timeout ago
        return now.timeIntervalSince(confirmedAt) < timeout
      }
    }
  }
  
  // MARK: - Optimistic Updates
  
  /// Applies pending mutations to a store in place.
  ///
  /// This is the core of optimistic updates: we take the server's state
  /// and apply our pending changes on top of it.
  ///
  /// ## Important
  ///
  /// This method **mutates the input store** directly. It does not create
  /// a copy. The return value is the same store instance for convenience.
  ///
  /// This differs from the TypeScript implementation which uses the `mutative`
  /// library to create immutable copies. For Swift, we chose in-place mutation
  /// for performance, as creating deep copies of the triple store indexes
  /// would be expensive.
  ///
  /// - Parameters:
  ///   - store: The server's triple store (will be mutated)
  ///   - attrsStore: The attribute store
  ///   - processedTxId: The highest transaction ID the server has processed (optional)
  /// - Returns: The same store with optimistic updates applied
  ///
  /// - SeeAlso: [PR #6 Feedback - applyOptimisticUpdates](https://github.com/tornikegomareli/instant-ios-sdk/blob/feat/local-first-triple-store/docs/PR6-FEEDBACK-ANALYSIS.md#comment-9-misleading-method-name-and-return-value)
  @discardableResult
  public func applyOptimisticUpdates(
    to store: TripleStore,
    attrsStore: AttrsStore,
    processedTxId: Int64? = nil
  ) -> TripleStore {
    lock.withLock {
      // Get mutations sorted by order
      let mutations = pendingMutations.values.sorted { $0.order < $1.order }
      
      // Apply each mutation that hasn't been processed yet
      for mutation in mutations {
        // Skip if server has already processed this mutation
        if let txId = mutation.txId, let processed = processedTxId, txId <= processed {
          continue
        }
        
        // Apply the mutation (mutates store in place)
        _ = applyTransaction(store: store, attrsStore: attrsStore, txSteps: mutation.txSteps)
      }
      
      return store
    }
  }
  
  // MARK: - Serialization
  
  /// Exports all pending mutations as a dictionary.
  ///
  /// Use this for persistence or debugging. The dictionary is keyed by event ID.
  ///
  /// - SeeAlso: [PR #6 Feedback - toJSON naming](https://github.com/tornikegomareli/instant-ios-sdk/blob/feat/local-first-triple-store/docs/PR6-FEEDBACK-ANALYSIS.md#comment-10-misleading-method-name---tojson)
  public func asDictionary() -> [String: PendingMutation] {
    lock.withLock { pendingMutations }
  }
  
  /// Converts to a dictionary for persistence.
  ///
  /// - Note: Deprecated in favor of `asDictionary()` which better describes the return type.
  @available(*, deprecated, renamed: "asDictionary", message: "Use asDictionary() instead - this method returns a Swift dictionary, not JSON")
  public func toJSON() -> [String: PendingMutation] {
    asDictionary()
  }
  
  /// Loads from a dictionary
  public func load(from json: [String: PendingMutation]) {
    lock.withLock {
      pendingMutations = json
      orderCounter = json.values.map(\.order).max() ?? 0
    }
  }
  
  /// Number of pending mutations
  public var count: Int {
    lock.withLock { pendingMutations.count }
  }
  
  /// Whether there are any pending mutations
  public var isEmpty: Bool {
    lock.withLock { pendingMutations.isEmpty }
  }
}

// MARK: - PendingMutation

/// A mutation waiting to be confirmed by the server.
public struct PendingMutation: Sendable {
  /// Unique identifier for this mutation (used in the wire protocol)
  public let eventId: String
  
  /// The transaction steps to apply
  public let txSteps: [[AnyCodableValue]]
  
  /// When this mutation was created locally
  public let createdAt: Date
  
  /// Order in which mutations should be applied
  public let order: Int
  
  /// Server-assigned transaction ID (set when server confirms)
  public var txId: Int64?
  
  /// When the server confirmed this mutation
  public var confirmedAt: Date?
  
  /// Optional error if the mutation failed
  public var error: String?
  
  public init(
    eventId: String,
    txSteps: [[Any]],
    createdAt: Date,
    order: Int,
    txId: Int64? = nil,
    confirmedAt: Date? = nil,
    error: String? = nil
  ) {
    self.eventId = eventId
    self.txSteps = txSteps.map { step in
      step.map { AnyCodableValue(value: $0) }
    }
    self.createdAt = createdAt
    self.order = order
    self.txId = txId
    self.confirmedAt = confirmedAt
    self.error = error
  }
}

// MARK: - PendingMutation Codable

extension PendingMutation: Codable {
  enum CodingKeys: String, CodingKey {
    case eventId, txSteps, createdAt, order, txId, confirmedAt, error
  }
  
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    eventId = try container.decode(String.self, forKey: .eventId)
    txSteps = try container.decode([[AnyCodableValue]].self, forKey: .txSteps)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    order = try container.decode(Int.self, forKey: .order)
    txId = try container.decodeIfPresent(Int64.self, forKey: .txId)
    confirmedAt = try container.decodeIfPresent(Date.self, forKey: .confirmedAt)
    error = try container.decodeIfPresent(String.self, forKey: .error)
  }
  
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(eventId, forKey: .eventId)
    try container.encode(txSteps, forKey: .txSteps)
    try container.encode(createdAt, forKey: .createdAt)
    try container.encode(order, forKey: .order)
    try container.encodeIfPresent(txId, forKey: .txId)
    try container.encodeIfPresent(confirmedAt, forKey: .confirmedAt)
    try container.encodeIfPresent(error, forKey: .error)
  }
}


