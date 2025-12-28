import Foundation
import GRDB

// MARK: - LocalStorage

/// GRDB-backed local storage for offline persistence.
///
/// This provides SQLite-based persistence for:
/// - Triples (the core data)
/// - Pending mutations (for optimistic updates that haven't been confirmed)
/// - Query subscriptions (cached query results)
/// - Sync subscriptions (for real-time sync state)
///
/// ## Tables
///
/// The database has the following tables:
/// - `triples`: Stores all triples with EAV indexes
/// - `pending_mutations`: Stores mutations waiting for server confirmation
/// - `query_subs`: Caches query results for offline access
/// - `attrs`: Stores attribute metadata from the server
///
/// ## Example
///
/// ```swift
/// let storage = try LocalStorage(appId: "my-app-id")
///
/// // Save triples
/// try await storage.saveTriples(triples)
///
/// // Load triples
/// let triples = try await storage.loadTriples()
///
/// // Save pending mutation
/// try await storage.savePendingMutation(mutation)
/// ```
///
/// - Note: This is ported from `instant/client/packages/core/src/IndexedDBStorage.ts`
public final class LocalStorage: Sendable {
  private let dbQueue: DatabaseQueue
  private let appId: String
  
  // MARK: - Initialization
  
  /// Creates a new local storage instance for the given app.
  ///
  /// The database file is stored in the app's Application Support directory.
  ///
  /// - Parameter appId: The InstantDB app ID
  /// - Throws: If the database cannot be created or migrated
  public init(appId: String) throws {
    self.appId = appId
    
    // Get the storage path
    let fileManager = FileManager.default
    let appSupport = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let instantDir = appSupport.appendingPathComponent("InstantDB", isDirectory: true)
    try fileManager.createDirectory(at: instantDir, withIntermediateDirectories: true)
    
    let dbPath = instantDir.appendingPathComponent("instant_\(appId).sqlite").path
    
    // Create the database
    var config = Configuration()
    config.foreignKeysEnabled = true
    config.prepareDatabase { db in
      // Enable WAL mode for better concurrent access
      try db.execute(sql: "PRAGMA journal_mode = WAL")
      // When multiple InstantDB clients are instantiated with the same app ID
      // (common in integration tests and multi-window apps), they may open multiple
      // SQLite connections to the same database file. A small busy timeout makes
      // those brief write-contention windows deterministic instead of failing with
      // `SQLITE_BUSY` ("database is locked").
      try db.execute(sql: "PRAGMA busy_timeout = 5000")
    }
    
    dbQueue = try DatabaseQueue(path: dbPath, configuration: config)
    
    // Run migrations
    try runMigrations()
  }
  
  /// Creates an in-memory storage instance for testing.
  public static func inMemory(appId: String) throws -> LocalStorage {
    let storage = try LocalStorage(appId: appId, inMemory: true)
    return storage
  }
  
  private init(appId: String, inMemory: Bool) throws {
    self.appId = appId
    
    var config = Configuration()
    config.foreignKeysEnabled = true
    
    if inMemory {
      dbQueue = try DatabaseQueue(configuration: config)
    } else {
      fatalError("Use init(appId:) for persistent storage")
    }
    
    try runMigrations()
  }
  
  // MARK: - Migrations
  
  private func runMigrations() throws {
    var migrator = DatabaseMigrator()
    
    // Version 1: Initial schema
    migrator.registerMigration("v1") { db in
      // Triples table
      try db.create(table: "triples") { t in
        t.column("entity_id", .text).notNull()
        t.column("attribute_id", .text).notNull()
        t.column("value", .blob).notNull()
        t.column("created_at", .integer).notNull()
        t.primaryKey(["entity_id", "attribute_id", "value"])
      }
      
      // Index for attribute lookups
      try db.create(index: "idx_triples_attribute", on: "triples", columns: ["attribute_id"])
      
      // Index for entity lookups
      try db.create(index: "idx_triples_entity", on: "triples", columns: ["entity_id"])
      
      // Pending mutations table
      try db.create(table: "pending_mutations") { t in
        t.column("event_id", .text).primaryKey()
        t.column("tx_steps", .blob).notNull()
        t.column("created_at", .datetime).notNull()
        t.column("order_index", .integer).notNull()
        t.column("tx_id", .integer)
        t.column("confirmed_at", .datetime)
        t.column("error", .text)
      }
      
      // Query subscriptions cache
      try db.create(table: "query_subs") { t in
        t.column("hash", .text).primaryKey()
        t.column("query", .blob).notNull()
        t.column("result", .blob)
        t.column("last_accessed", .datetime).notNull()
      }
      
      // Attributes table
      try db.create(table: "attrs") { t in
        t.column("id", .text).primaryKey()
        t.column("data", .blob).notNull()
      }
      
      // Key-value store for misc data
      try db.create(table: "kv") { t in
        t.column("key", .text).primaryKey()
        t.column("value", .blob).notNull()
      }
    }
    
    try migrator.migrate(dbQueue)
  }
  
  // MARK: - Triple Operations
  
  /// Saves triples to the database.
  ///
  /// Uses INSERT OR REPLACE to handle conflicts.
  ///
  /// - Parameter triples: The triples to save
  public func saveTriples(_ triples: [Triple]) async throws {
    try await dbQueue.write { db in
      for triple in triples {
        let valueData = try JSONEncoder().encode(triple.value)
        try db.execute(
          sql: """
            INSERT OR REPLACE INTO triples (entity_id, attribute_id, value, created_at)
            VALUES (?, ?, ?, ?)
            """,
          arguments: [triple.entityId, triple.attributeId, valueData, triple.createdAt]
        )
      }
    }
  }
  
  /// Loads all triples from the database.
  ///
  /// - Returns: All stored triples
  public func loadTriples() async throws -> [Triple] {
    try await dbQueue.read { db in
      let rows = try Row.fetchAll(db, sql: "SELECT * FROM triples")
      return try rows.compactMap { row -> Triple? in
        guard let entityId = row["entity_id"] as? String,
              let attributeId = row["attribute_id"] as? String,
              let valueData = row["value"] as? Data,
              let createdAt = row["created_at"] as? Int64 else {
          return nil
        }
        let value = try JSONDecoder().decode(TripleValue.self, from: valueData)
        return Triple(entityId: entityId, attributeId: attributeId, value: value, createdAt: createdAt)
      }
    }
  }
  
  /// Loads triples for a specific entity.
  ///
  /// - Parameter entityId: The entity ID to load
  /// - Returns: All triples for the entity
  public func loadTriples(forEntity entityId: String) async throws -> [Triple] {
    try await dbQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: "SELECT * FROM triples WHERE entity_id = ?",
        arguments: [entityId]
      )
      return try rows.compactMap { row -> Triple? in
        guard let entityId = row["entity_id"] as? String,
              let attributeId = row["attribute_id"] as? String,
              let valueData = row["value"] as? Data,
              let createdAt = row["created_at"] as? Int64 else {
          return nil
        }
        let value = try JSONDecoder().decode(TripleValue.self, from: valueData)
        return Triple(entityId: entityId, attributeId: attributeId, value: value, createdAt: createdAt)
      }
    }
  }
  
  /// Deletes triples matching the given criteria.
  ///
  /// - Parameters:
  ///   - entityId: Optional entity ID to filter by
  ///   - attributeId: Optional attribute ID to filter by
  public func deleteTriples(entityId: String? = nil, attributeId: String? = nil) async throws {
    try await dbQueue.write { db in
      var sql = "DELETE FROM triples WHERE 1=1"
      var args: [DatabaseValueConvertible] = []
      
      if let entityId = entityId {
        sql += " AND entity_id = ?"
        args.append(entityId)
      }
      if let attributeId = attributeId {
        sql += " AND attribute_id = ?"
        args.append(attributeId)
      }
      
      try db.execute(sql: sql, arguments: StatementArguments(args))
    }
  }
  
  /// Clears all triples from the database.
  public func clearTriples() async throws {
    try await dbQueue.write { db in
      try db.execute(sql: "DELETE FROM triples")
    }
  }
  
  // MARK: - Pending Mutations
  
  /// Saves a pending mutation to the database.
  ///
  /// - Parameter mutation: The mutation to save
  public func savePendingMutation(_ mutation: PendingMutation) async throws {
    try await dbQueue.write { db in
      do {
        let txStepsData = try JSONEncoder().encode(mutation.txSteps)
        try db.execute(
          sql: """
            INSERT OR REPLACE INTO pending_mutations 
            (event_id, tx_steps, created_at, order_index, tx_id, confirmed_at, error)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
          arguments: [
            mutation.eventId,
            txStepsData,
            mutation.createdAt,
            mutation.order,
            mutation.txId,
            mutation.confirmedAt,
            mutation.error
          ]
        )
      } catch {
        throw error
      }
    }
  }

  /// Returns the next order index for a new pending mutation.
  ///
  /// ## Why This Exists
  /// Pending mutations must be replayed in the same order they were created to
  /// match JS core Reactor semantics and keep transaction replay deterministic
  /// across app launches.
  ///
  /// This is used by local-first transaction APIs to assign `order_index`
  /// atomically inside SQLite.
  public func nextPendingMutationOrderIndex() async throws -> Int {
    try await dbQueue.write { db in
      let maxOrder: Int? = try Int.fetchOne(db, sql: "SELECT MAX(order_index) FROM pending_mutations")
      return (maxOrder ?? 0) + 1
    }
  }

  /// Marks a pending mutation as confirmed by the server.
  ///
  /// ## Why This Exists
  /// When the server responds with `transact-ok`, we want to record the
  /// server-assigned tx-id so that future `processed-tx-id` updates can clean up
  /// confirmed mutations from disk.
  ///
  /// - Parameters:
  ///   - eventId: The client-event-id associated with the mutation
  ///   - txId: The server tx-id
  ///   - confirmedAt: Timestamp for the confirmation (defaults to now)
  public func markPendingMutationConfirmed(
    eventId: String,
    txId: Int64,
    confirmedAt: Date = Date()
  ) async throws {
    try await dbQueue.write { db in
      try db.execute(
        sql: """
          UPDATE pending_mutations
          SET tx_id = ?, confirmed_at = ?
          WHERE event_id = ?
          """,
        arguments: [txId, confirmedAt, eventId]
      )
    }
  }

  /// Records a server-side error for a pending mutation.
  ///
  /// This is a best-effort persistence mechanism for debugging and for
  /// preventing infinite resend loops when a queued mutation is rejected.
  public func markPendingMutationErrored(eventId: String, error: String) async throws {
    try await dbQueue.write { db in
      try db.execute(
        sql: "UPDATE pending_mutations SET error = ? WHERE event_id = ?",
        arguments: [error, eventId]
      )
    }
  }
  
  /// Loads all pending mutations from the database.
  ///
  /// - Returns: All pending mutations, sorted by order
  public func loadPendingMutations() async throws -> [PendingMutation] {
    try await dbQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: "SELECT * FROM pending_mutations ORDER BY order_index"
      )
      return try rows.compactMap { row -> PendingMutation? in
        guard let eventId = row["event_id"] as? String,
              let txStepsData = row["tx_steps"] as? Data else {
          return nil
        }

        let createdAt: Date = row["created_at"]
        let confirmedAt: Date? = row["confirmed_at"]
        let txId: Int64? = row["tx_id"]
        let error: String? = row["error"]

        let order: Int
        if let intOrder = row["order_index"] as? Int {
          order = intOrder
        } else if let int64Order = row["order_index"] as? Int64 {
          order = Int(int64Order)
        } else {
          return nil
        }

        let txSteps = try JSONDecoder().decode([[AnyCodableValue]].self, from: txStepsData)
        
        return PendingMutation(
          eventId: eventId,
          txSteps: txSteps.map { $0.map(\.value) },
          createdAt: createdAt,
          order: order,
          txId: txId,
          confirmedAt: confirmedAt,
          error: error
        )
      }
    }
  }
  
  /// Deletes a pending mutation by event ID.
  ///
  /// - Parameter eventId: The event ID of the mutation to delete
  public func deletePendingMutation(eventId: String) async throws {
    try await dbQueue.write { db in
      try db.execute(
        sql: "DELETE FROM pending_mutations WHERE event_id = ?",
        arguments: [eventId]
      )
    }
  }
  
  /// Deletes pending mutations that have been processed by the server.
  ///
  /// - Parameter processedTxId: The highest transaction ID that has been processed
  public func cleanupProcessedMutations(processedTxId: Int64) async throws {
    try await dbQueue.write { db in
      try db.execute(
        sql: "DELETE FROM pending_mutations WHERE tx_id IS NOT NULL AND tx_id <= ?",
        arguments: [processedTxId]
      )
    }
  }
  
  /// Clears all pending mutations from the database.
  public func clearPendingMutations() async throws {
    try await dbQueue.write { db in
      try db.execute(sql: "DELETE FROM pending_mutations")
    }
  }
  
  // MARK: - Attributes
  
  /// Saves attributes to the database.
  ///
  /// - Parameter attrs: The attributes to save
  public func saveAttrs(_ attrs: [Attribute]) async throws {
    try await dbQueue.write { db in
      for attr in attrs {
        let data = try JSONEncoder().encode(attr)
        try db.execute(
          sql: "INSERT OR REPLACE INTO attrs (id, data) VALUES (?, ?)",
          arguments: [attr.id, data]
        )
      }
    }
  }
  
  /// Loads all attributes from the database.
  ///
  /// - Returns: All stored attributes
  public func loadAttrs() async throws -> [Attribute] {
    try await dbQueue.read { db in
      let rows = try Row.fetchAll(db, sql: "SELECT data FROM attrs")
      return try rows.compactMap { row -> Attribute? in
        guard let data = row["data"] as? Data else { return nil }
        return try JSONDecoder().decode(Attribute.self, from: data)
      }
    }
  }
  
  /// Clears all attributes from the database.
  public func clearAttrs() async throws {
    try await dbQueue.write { db in
      try db.execute(sql: "DELETE FROM attrs")
    }
  }
  
  // MARK: - Key-Value Store
  
  /// Gets a value from the key-value store.
  ///
  /// - Parameter key: The key to look up
  /// - Returns: The value, or nil if not found
  public func getValue<T: Decodable>(forKey key: String) async throws -> T? {
    try await dbQueue.read { db in
      guard let row = try Row.fetchOne(
        db,
        sql: "SELECT value FROM kv WHERE key = ?",
        arguments: [key]
      ), let data = row["value"] as? Data else {
        return nil
      }
      return try JSONDecoder().decode(T.self, from: data)
    }
  }
  
  /// Sets a value in the key-value store.
  ///
  /// - Parameters:
  ///   - value: The value to store
  ///   - key: The key to store it under
  public func setValue<T: Encodable>(_ value: T, forKey key: String) async throws {
    try await dbQueue.write { db in
      let data = try JSONEncoder().encode(value)
      try db.execute(
        sql: "INSERT OR REPLACE INTO kv (key, value) VALUES (?, ?)",
        arguments: [key, data]
      )
    }
  }
  
  /// Deletes a value from the key-value store.
  ///
  /// - Parameter key: The key to delete
  public func deleteValue(forKey key: String) async throws {
    try await dbQueue.write { db in
      try db.execute(
        sql: "DELETE FROM kv WHERE key = ?",
        arguments: [key]
      )
    }
  }
  
  // MARK: - Query Cache
  
  /// Caches a query result.
  ///
  /// - Parameters:
  ///   - hash: The query hash (used as key)
  ///   - query: The query data
  ///   - result: The result data
  public func cacheQueryResult(hash: String, query: Data, result: Data) async throws {
    try await dbQueue.write { db in
      try db.execute(
        sql: """
          INSERT OR REPLACE INTO query_subs (hash, query, result, last_accessed)
          VALUES (?, ?, ?, ?)
          """,
        arguments: [hash, query, result, Date()]
      )
    }
  }
  
  /// Gets a cached query result.
  ///
  /// - Parameter hash: The query hash
  /// - Returns: The cached result data, or nil if not found
  public func getCachedQueryResult(hash: String) async throws -> Data? {
    let result: Data? = try await dbQueue.read { db in
      guard let row = try Row.fetchOne(
        db,
        sql: "SELECT result FROM query_subs WHERE hash = ?",
        arguments: [hash]
      ) else {
        return nil
      }

      return row["result"] as? Data
    }

    if result != nil {
      Task { [hash] in
        try? await self.touchCachedQuery(hash: hash)
      }
    }

    return result
  }

  /// Gets a cached query result synchronously.
  ///
  /// ## Why This Exists
  /// `InstantClient.subscribe` is a synchronous API today, but we still want to
  /// deliver previously cached results as early as possible (JS core semantics:
  /// subscriptions may emit cached results immediately).
  ///
  /// This method enables a best-effort, synchronous cache read on the calling
  /// thread. Keep the work small: a single keyed lookup and optional touch of
  /// `last_accessed`.
  ///
  /// - Parameter hash: The query hash
  /// - Returns: The cached result data, or nil if not found
  public func getCachedQueryResultSync(hash: String) throws -> Data? {
    let result: Data? = try dbQueue.read { db in
      guard let row = try Row.fetchOne(
        db,
        sql: "SELECT result FROM query_subs WHERE hash = ?",
        arguments: [hash]
      ) else {
        return nil
      }

      return row["result"] as? Data
    }

    if result != nil {
      Task { [hash] in
        try? await self.touchCachedQuery(hash: hash)
      }
    }

    return result
  }

  private func touchCachedQuery(hash: String) async throws {
    try await dbQueue.write { db in
      try db.execute(
        sql: "UPDATE query_subs SET last_accessed = ? WHERE hash = ?",
        arguments: [Date(), hash]
      )
    }
  }
  
  /// Clears old cached queries.
  ///
  /// - Parameter olderThan: Delete queries not accessed since this date
  public func clearOldQueryCache(olderThan: Date) async throws {
    try await dbQueue.write { db in
      try db.execute(
        sql: "DELETE FROM query_subs WHERE last_accessed < ?",
        arguments: [olderThan]
      )
    }
  }
  
  // MARK: - Utility
  
  /// Clears all data from the database.
  public func clearAll() async throws {
    try await dbQueue.write { db in
      try db.execute(sql: "DELETE FROM triples")
      try db.execute(sql: "DELETE FROM pending_mutations")
      try db.execute(sql: "DELETE FROM query_subs")
      try db.execute(sql: "DELETE FROM attrs")
      try db.execute(sql: "DELETE FROM kv")
    }
  }
  
  /// Gets the database file size in bytes.
  public var databaseSize: Int64 {
    get throws {
      let path = dbQueue.path
      let attrs = try FileManager.default.attributesOfItem(atPath: path)
      return (attrs[.size] as? Int64) ?? 0
    }
  }
}

