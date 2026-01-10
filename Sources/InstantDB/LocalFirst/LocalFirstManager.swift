import Foundation
import Combine

// MARK: - LocalFirstManager

/// Logger for LocalFirstManager
private let logger = CompatibilityLogger(subsystem: "com.instantdb.sdk", category: "LocalFirst")

/// Coordinates local-first functionality for InstantDB.
///
/// This manager integrates all the local-first components:
/// - Triple Store for in-memory data
/// - Optimistic Update Manager for pending mutations
/// - Local Storage for persistence
/// - Conflict resolution using Last-Write-Wins
///
/// ## How it works
///
/// 1. **Server data arrives** → Stored in `serverStore`
/// 2. **User makes a mutation** → Added to `optimisticManager`, applied to local view
/// 3. **Query results** → Computed from `serverStore` + optimistic updates
/// 4. **Server confirms** → Mutation marked with `tx-id`, eventually cleaned up
/// 5. **Offline** → Mutations queued, persisted to storage, synced when online
///
/// ## Example
///
/// ```swift
/// // Use async factory method to ensure data is loaded before use
/// let manager = try await LocalFirstManager.create(appId: "my-app")
///
/// // Apply server data
/// manager.applyServerTriples(triples, attrs: attrs)
///
/// // Add optimistic mutation
/// let eventId = manager.addOptimisticMutation([
///   ["add-triple", "todo-1", "attr-title", "Buy milk"]
/// ])
///
/// // Get current view (server + optimistic)
/// let store = manager.currentStore()
/// ```
///
/// - Note: This integrates patterns from `instant/client/packages/core/src/Reactor.js`
///
/// ## Why Async Factory?
///
/// The `create()` factory method ensures persisted data is fully loaded before
/// the manager is returned. This prevents race conditions where the manager
/// is used before data loading completes.
///
/// - SeeAlso: [PR #6 Feedback Analysis](https://github.com/tornikegomareli/instant-ios-sdk/blob/feat/local-first-triple-store/docs/PR6-FEEDBACK-ANALYSIS.md#comment-1-async-initialization-race-condition)
@MainActor
public final class LocalFirstManager: ObservableObject {
  
  // MARK: - Storage
  
  /// The server's authoritative triple store
  private var serverStore: TripleStore
  
  /// Attribute metadata from the server
  private var serverAttrsStore: AttrsStore
  
  /// Manages pending optimistic mutations
  private let optimisticManager: OptimisticUpdateManager
  
  /// Persistent storage for offline support
  private let localStorage: LocalStorage?
  
  /// The highest transaction ID processed by the server
  @Published public private(set) var processedTxId: Int64?
  
  /// Whether we're currently online
  @Published public private(set) var isOnline: Bool = true
  
  /// Version counter for tracking store changes
  @Published public private(set) var storeVersion: Int = 0
  
  /// Whether persisted data has been loaded
  @Published public private(set) var isLoaded: Bool = false
  
  // MARK: - Callbacks
  
  /// Called when the store changes (for notifying query subscribers)
  public var onStoreChanged: (() -> Void)?
  
  // MARK: - Initialization
  
  /// Creates a new local-first manager asynchronously, ensuring persisted data is loaded.
  ///
  /// This is the preferred way to create a LocalFirstManager as it guarantees
  /// that persisted data (triples, attributes, pending mutations) is fully loaded
  /// before the manager is returned.
  ///
  /// ## Why Async?
  ///
  /// Loading persisted data from SQLite is asynchronous. Using a synchronous
  /// initializer with a background Task creates a race condition where the
  /// manager might be used before data is loaded.
  ///
  /// - Parameters:
  ///   - appId: The InstantDB app ID
  ///   - enablePersistence: Whether to enable local storage (default: true)
  /// - Returns: A fully initialized LocalFirstManager with persisted data loaded
  /// - Throws: If storage initialization fails
  ///
  /// - SeeAlso: [PR #6 Feedback - Async Init Race Condition](https://github.com/tornikegomareli/instant-ios-sdk/blob/feat/local-first-triple-store/docs/PR6-FEEDBACK-ANALYSIS.md#comment-1-async-initialization-race-condition)
  public static func create(appId: String, enablePersistence: Bool = true) async throws -> LocalFirstManager {
    let manager = try LocalFirstManager(appId: appId, enablePersistence: enablePersistence, loadData: false)
    await manager.loadPersistedData()
    return manager
  }
  
  /// Creates a new local-first manager.
  ///
  /// - Parameters:
  ///   - appId: The InstantDB app ID
  ///   - enablePersistence: Whether to enable local storage (default: true)
  ///
  /// - Warning: This initializer returns before persisted data is loaded.
  ///   Prefer using `LocalFirstManager.create(appId:enablePersistence:)` instead.
  @available(*, deprecated, message: "Use LocalFirstManager.create(appId:enablePersistence:) instead to avoid race conditions")
  public init(appId: String, enablePersistence: Bool = true) throws {
    self.serverStore = TripleStore()
    self.serverAttrsStore = AttrsStore()
    self.optimisticManager = OptimisticUpdateManager()
    
    if enablePersistence {
      self.localStorage = try LocalStorage(appId: appId)
    } else {
      self.localStorage = nil
    }
    
    // Load persisted data in background
    // Note: This creates a race condition - prefer using create() factory
    Task {
      await loadPersistedData()
    }
  }
  
  /// Private initializer for the async factory method.
  private init(appId: String, enablePersistence: Bool, loadData: Bool) throws {
    self.serverStore = TripleStore()
    self.serverAttrsStore = AttrsStore()
    self.optimisticManager = OptimisticUpdateManager()
    
    if enablePersistence {
      self.localStorage = try LocalStorage(appId: appId)
    } else {
      self.localStorage = nil
    }
    
    // Data loading is handled by the factory method
  }
  
  /// Creates a manager without persistence (for testing)
  public init() {
    self.serverStore = TripleStore()
    self.serverAttrsStore = AttrsStore()
    self.optimisticManager = OptimisticUpdateManager()
    self.localStorage = nil
    self.isLoaded = true
  }
  
  // MARK: - Persistence
  
  /// Loads persisted data from storage.
  ///
  /// ## Load Order
  ///
  /// Data must be loaded in this specific order:
  /// 1. **Attributes first** - Required to determine cardinality and value types
  /// 2. **Triples second** - Depend on attributes for proper indexing
  /// 3. **Pending mutations** - Applied on top of loaded triples
  /// 4. **Processed transaction ID** - For cleanup of confirmed mutations
  ///
  /// - SeeAlso: [PR #6 Feedback - Load Order](https://github.com/tornikegomareli/instant-ios-sdk/blob/feat/local-first-triple-store/docs/PR6-FEEDBACK-ANALYSIS.md#comment-2-load-order-issue---attrs-before-triples)
  private func loadPersistedData() async {
    guard let storage = localStorage else {
      isLoaded = true
      return
    }
    
    do {
      // 1. Load attributes FIRST - triples depend on attrs for cardinality/type info
      // This fixes the load order bug where triples were loaded before attrs.
      // See: instant/client/packages/core/src/store.ts createTripleIndexes()
      let attrs = try await storage.loadAttrs()
      for attr in attrs {
        serverAttrsStore.addAttr(attr)
      }
      
      // 2. Load triples AFTER attributes are loaded
      // Now getAttr() will return valid attribute metadata
      let triples = try await storage.loadTriples()
      for triple in triples {
        let attr = serverAttrsStore.getAttr(triple.attributeId)
        serverStore.addTriple(
          triple,
          hasCardinalityOne: attr?.cardinality == .one,
          isRef: attr?.valueType == .ref
        )
      }
      
      // 3. Load pending mutations
      let mutations = try await storage.loadPendingMutations()
      for mutation in mutations {
        optimisticManager.load(from: [mutation.eventId: mutation])
      }
      
      // 4. Load processedTxId
      if let txId: Int64 = try await storage.getValue(forKey: "processedTxId") {
        processedTxId = txId
      }
      
      isLoaded = true
      storeVersion += 1
      onStoreChanged?()
      
      logger.info("Loaded \(attrs.count) attrs, \(triples.count) triples, \(mutations.count) pending mutations")
    } catch {
      logger.error("Failed to load persisted data: \(error.localizedDescription)")
      isLoaded = true  // Mark as loaded even on error to unblock usage
    }
  }
  
  /// Persists triples to storage.
  ///
  /// - SeeAlso: [PR #6 Feedback - Error Logging](https://github.com/tornikegomareli/instant-ios-sdk/blob/feat/local-first-triple-store/docs/PR6-FEEDBACK-ANALYSIS.md#comments-4-7-silent-error-handling-in-persistence)
  private func persistTriples(_ triples: [Triple]) {
    guard let storage = localStorage else { return }
    Task {
      do {
        try await storage.saveTriples(triples)
      } catch {
        logger.error("Failed to persist \(triples.count) triples: \(error.localizedDescription)")
      }
    }
  }
  
  /// Persists a mutation to storage.
  ///
  /// - SeeAlso: [PR #6 Feedback - Error Logging](https://github.com/tornikegomareli/instant-ios-sdk/blob/feat/local-first-triple-store/docs/PR6-FEEDBACK-ANALYSIS.md#comments-4-7-silent-error-handling-in-persistence)
  private func persistMutation(_ mutation: PendingMutation) {
    guard let storage = localStorage else { return }
    Task {
      do {
        try await storage.savePendingMutation(mutation)
      } catch {
        logger.error("Failed to persist mutation \(mutation.eventId): \(error.localizedDescription)")
      }
    }
  }
  
  /// Persists attributes to storage.
  ///
  /// - SeeAlso: [PR #6 Feedback - Error Logging](https://github.com/tornikegomareli/instant-ios-sdk/blob/feat/local-first-triple-store/docs/PR6-FEEDBACK-ANALYSIS.md#comments-4-7-silent-error-handling-in-persistence)
  private func persistAttrs(_ attrs: [Attribute]) {
    guard let storage = localStorage else { return }
    Task {
      do {
        try await storage.saveAttrs(attrs)
      } catch {
        logger.error("Failed to persist \(attrs.count) attrs: \(error.localizedDescription)")
      }
    }
  }
  
  // MARK: - Server Data
  
  /// Applies triples received from the server.
  ///
  /// This is called when we receive query results or refresh updates.
  ///
  /// - Parameters:
  ///   - triples: The triples from the server
  ///   - attrs: Attribute metadata from the server
  public func applyServerTriples(_ triples: [Triple], attrs: [Attribute]) {
    // Update attrs store
    for attr in attrs {
      serverAttrsStore.addAttr(attr)
    }
    
    // Add triples to server store
    for triple in triples {
      let attr = serverAttrsStore.getAttr(triple.attributeId)
      serverStore.addTriple(
        triple,
        hasCardinalityOne: attr?.cardinality == .one,
        isRef: attr?.valueType == .ref
      )
    }
    
    // Persist
    persistTriples(triples)
    persistAttrs(attrs)
    
    storeVersion += 1
    onStoreChanged?()
  }
  
  /// Applies transaction steps received from the server (refresh-ok).
  ///
  /// - Parameters:
  ///   - txSteps: The transaction steps to apply
  ///   - processedTxId: The new processed transaction ID
  public func applyServerTransaction(_ txSteps: [[Any]], processedTxId: Int64?) {
    // Apply to server store
    _ = applyTransaction(store: serverStore, attrsStore: serverAttrsStore, txSteps: txSteps)
    
    // Update processed tx id
    if let txId = processedTxId {
      self.processedTxId = txId
      
      // Cleanup processed mutations
      optimisticManager.cleanupProcessedMutations(processedTxId: txId)
      
      // Persist
      if let storage = localStorage {
        Task {
          do {
            try await storage.setValue(txId, forKey: "processedTxId")
            try await storage.cleanupProcessedMutations(processedTxId: txId)
          } catch {
            logger.error("Failed to persist transaction state: \(error.localizedDescription)")
          }
        }
      }
    }
    
    storeVersion += 1
    onStoreChanged?()
  }
  
  /// Updates attributes from the server (init-ok).
  ///
  /// - Parameter attrs: The attribute definitions
  public func updateAttrs(_ attrs: [Attribute]) {
    for attr in attrs {
      serverAttrsStore.addAttr(attr)
    }
    persistAttrs(attrs)
  }
  
  // MARK: - Optimistic Updates
  
  /// Adds an optimistic mutation.
  ///
  /// The mutation is applied locally immediately and sent to the server.
  /// If the server rejects it, it will be rolled back.
  ///
  /// - Parameter txSteps: The transaction steps
  /// - Returns: The event ID for tracking this mutation
  @discardableResult
  public func addOptimisticMutation(_ txSteps: [[Any]]) -> String {
    let eventId = optimisticManager.addMutation(txSteps)
    
    // Persist the mutation
    if let mutation = optimisticManager.getMutation(eventId: eventId) {
      persistMutation(mutation)
    }
    
    storeVersion += 1
    onStoreChanged?()
    
    return eventId
  }
  
  /// Confirms a mutation with the server's transaction ID.
  ///
  /// Called when we receive `transact-ok` from the server.
  ///
  /// - Parameters:
  ///   - eventId: The event ID of the mutation
  ///   - txId: The server-assigned transaction ID
  public func confirmMutation(eventId: String, txId: Int64) {
    optimisticManager.confirmMutation(eventId: eventId, txId: txId)
    
    // Update persisted mutation
    if let mutation = optimisticManager.getMutation(eventId: eventId) {
      persistMutation(mutation)
    }
  }
  
  /// Removes a mutation (e.g., on error).
  ///
  /// ## Storage Consistency
  ///
  /// We remove from memory first, then storage. If storage fails, we log
  /// a warning but don't fail - the mutation will be cleaned up on next
  /// sync or app restart.
  ///
  /// - Parameter eventId: The event ID of the mutation to remove
  ///
  /// - SeeAlso: [PR #6 Feedback - Storage/Memory Consistency](https://github.com/tornikegomareli/instant-ios-sdk/blob/feat/local-first-triple-store/docs/PR6-FEEDBACK-ANALYSIS.md#comment-8-storagememory-state-inconsistency)
  public func removeMutation(eventId: String) {
    optimisticManager.removeMutation(eventId: eventId)
    
    // Remove from storage
    if let storage = localStorage {
      Task {
        do {
          try await storage.deletePendingMutation(eventId: eventId)
        } catch {
          // Log but don't fail - storage will be cleaned up on next sync
          // This maintains eventual consistency between memory and storage
          logger.warning("Failed to remove mutation \(eventId) from storage: \(error.localizedDescription). Will be cleaned up on next sync.")
        }
      }
    }
    
    storeVersion += 1
    onStoreChanged?()
  }
  
  /// Gets all pending mutations that need to be sent/resent to the server.
  public var pendingMutations: [PendingMutation] {
    optimisticManager.unconfirmedMutations
  }
  
  // MARK: - Current State
  
  /// Gets the current triple store with optimistic updates applied.
  ///
  /// This is what queries should use to compute their results.
  /// It takes the server's authoritative state and layers pending
  /// optimistic mutations on top.
  ///
  /// - Returns: A store with optimistic updates applied
  public func currentStore() -> TripleStore {
    optimisticManager.applyOptimisticUpdates(
      to: serverStore,
      attrsStore: serverAttrsStore,
      processedTxId: processedTxId
    )
  }
  
  /// Gets the current attributes store with optimistic updates.
  public func currentAttrsStore() -> AttrsStore {
    // For now, return server attrs (optimistic attr changes are rare)
    serverAttrsStore
  }
  
  /// Gets the server's authoritative store (without optimistic updates).
  public var serverTripleStore: TripleStore {
    serverStore
  }
  
  /// Gets the server's attribute store.
  public var attrsStore: AttrsStore {
    serverAttrsStore
  }
  
  // MARK: - Offline Support
  
  /// Updates the online status.
  ///
  /// When going online, pending mutations should be resent.
  ///
  /// - Parameter online: Whether we're currently online
  public func setOnlineStatus(_ online: Bool) {
    let wasOffline = !isOnline
    isOnline = online
    
    if online && wasOffline {
      // Going back online - caller should resend pending mutations
      logger.info("Back online, \(self.optimisticManager.count) mutations pending")
    }
  }
  
  /// Clears all local data.
  ///
  /// Use this when signing out or resetting the app.
  public func clearAll() async throws {
    serverStore = TripleStore()
    serverAttrsStore = AttrsStore()
    optimisticManager.load(from: [:])
    processedTxId = nil
    
    try await localStorage?.clearAll()
    
    storeVersion += 1
    onStoreChanged?()
  }
}

// MARK: - Convenience Extensions

extension LocalFirstManager {
  
  /// Gets triples for a specific entity.
  public func getEntityTriples(_ entityId: String) -> [Triple] {
    currentStore().getTriples(entity: entityId)
  }
  
  /// Gets an entity as a dictionary.
  public func getEntity(_ entityId: String, entityType: String) -> [String: Any] {
    let store = currentStore()
    let blobAttrs = serverAttrsStore.getBlobAttrs(entityType: entityType)
    return store.getAsObject(entityId: entityId, blobAttrs: blobAttrs)
  }
  
  /// Checks if an entity exists.
  public func entityExists(_ entityId: String) -> Bool {
    currentStore().hasEntity(entityId)
  }
}





