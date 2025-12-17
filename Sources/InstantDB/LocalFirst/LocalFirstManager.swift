import Foundation
import Combine

// MARK: - LocalFirstManager

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
/// let manager = try LocalFirstManager(appId: "my-app")
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
  
  // MARK: - Callbacks
  
  /// Called when the store changes (for notifying query subscribers)
  public var onStoreChanged: (() -> Void)?
  
  // MARK: - Initialization
  
  /// Creates a new local-first manager.
  ///
  /// - Parameters:
  ///   - appId: The InstantDB app ID
  ///   - enablePersistence: Whether to enable local storage (default: true)
  public init(appId: String, enablePersistence: Bool = true) throws {
    self.serverStore = TripleStore()
    self.serverAttrsStore = AttrsStore()
    self.optimisticManager = OptimisticUpdateManager()
    
    if enablePersistence {
      self.localStorage = try LocalStorage(appId: appId)
    } else {
      self.localStorage = nil
    }
    
    // Load persisted data
    Task {
      await loadPersistedData()
    }
  }
  
  /// Creates a manager without persistence (for testing)
  public init() {
    self.serverStore = TripleStore()
    self.serverAttrsStore = AttrsStore()
    self.optimisticManager = OptimisticUpdateManager()
    self.localStorage = nil
  }
  
  // MARK: - Persistence
  
  private func loadPersistedData() async {
    guard let storage = localStorage else { return }
    
    do {
      // Load triples
      let triples = try await storage.loadTriples()
      for triple in triples {
        let attr = serverAttrsStore.getAttr(triple.attributeId)
        serverStore.addTriple(
          triple,
          hasCardinalityOne: attr?.cardinality == .one,
          isRef: attr?.valueType == .ref
        )
      }
      
      // Load attributes
      let attrs = try await storage.loadAttrs()
      for attr in attrs {
        serverAttrsStore.addAttr(attr)
      }
      
      // Load pending mutations
      let mutations = try await storage.loadPendingMutations()
      for mutation in mutations {
        optimisticManager.load(from: [mutation.eventId: mutation])
      }
      
      // Load processedTxId
      if let txId: Int64 = try await storage.getValue(forKey: "processedTxId") {
        processedTxId = txId
      }
      
      storeVersion += 1
      onStoreChanged?()
      
      print("[LocalFirst] Loaded \(triples.count) triples, \(attrs.count) attrs, \(mutations.count) pending mutations")
    } catch {
      print("[LocalFirst] Failed to load persisted data: \(error)")
    }
  }
  
  private func persistTriples(_ triples: [Triple]) {
    guard let storage = localStorage else { return }
    Task {
      try? await storage.saveTriples(triples)
    }
  }
  
  private func persistMutation(_ mutation: PendingMutation) {
    guard let storage = localStorage else { return }
    Task {
      try? await storage.savePendingMutation(mutation)
    }
  }
  
  private func persistAttrs(_ attrs: [Attribute]) {
    guard let storage = localStorage else { return }
    Task {
      try? await storage.saveAttrs(attrs)
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
          try? await storage.setValue(txId, forKey: "processedTxId")
          try? await storage.cleanupProcessedMutations(processedTxId: txId)
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
  /// - Parameter eventId: The event ID of the mutation to remove
  public func removeMutation(eventId: String) {
    optimisticManager.removeMutation(eventId: eventId)
    
    // Remove from storage
    if let storage = localStorage {
      Task {
        try? await storage.deletePendingMutation(eventId: eventId)
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
      print("[LocalFirst] Back online, \(optimisticManager.count) mutations pending")
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

