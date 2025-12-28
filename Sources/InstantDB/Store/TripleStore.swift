import Foundation

// MARK: - TripleStore

/// An in-memory store for triples with multiple indexes for efficient querying.
///
/// InstantDB uses a triple store with three indexes:
/// - **EAV** (Entity-Attribute-Value): For looking up "what are all the attributes of entity X?"
/// - **AEV** (Attribute-Entity-Value): For looking up "which entities have attribute Y?"
/// - **VAE** (Value-Attribute-Entity): For looking up reverse references "which entities point to entity Z?"
///
/// This is the core data structure that enables InstantDB's query engine.
///
/// ## Example
///
/// ```swift
/// let store = TripleStore()
///
/// // Add a triple
/// let triple = Triple(
///   entityId: "todo-1",
///   attributeId: "attr-title",
///   value: .string("Buy milk"),
///   createdAt: ConflictResolution.optimisticTimestamp()
/// )
/// store.addTriple(triple, hasCardinalityOne: true)
///
/// // Query by entity
/// let todoTriples = store.getTriples(entity: "todo-1")
/// ```
///
/// - Note: This is ported from `instant/client/packages/core/src/store.ts`
public final class TripleStore: @unchecked Sendable {
  private let lock = NSRecursiveLock()
  
  // MARK: - Indexes
  
  /// EAV index: entity -> attribute -> value -> Triple
  ///
  /// Used for queries like "get all attributes of entity X"
  private var eav: [String: [String: [AnyHashable: Triple]]] = [:]
  
  /// AEV index: attribute -> entity -> value -> Triple
  ///
  /// Used for queries like "get all entities with attribute Y"
  private var aev: [String: [String: [AnyHashable: Triple]]] = [:]
  
  /// VAE index: value -> attribute -> entity -> Triple
  ///
  /// Used for reverse reference lookups (only populated for ref attributes)
  private var vae: [AnyHashable: [String: [String: Triple]]] = [:]
  
  /// Configuration
  public var useDateObjects: Bool = false
  public var cardinalityInference: Bool = false
  
  // MARK: - Initialization
  
  /// Creates an empty triple store
  public init() {}
  
  /// Creates a triple store from an array of triples
  ///
  /// - Parameters:
  ///   - triples: The triples to add
  ///   - attrsStore: The attribute store for looking up attribute metadata
  public init(triples: [Triple], attrsStore: AttrsStore) {
    for triple in triples {
      let attr = attrsStore.getAttr(triple.attributeId)
      let hasCardinalityOne = attr?.cardinality == .one
      let isRef = attr?.valueType == .ref
      addTripleInternal(triple, hasCardinalityOne: hasCardinalityOne, isRef: isRef)
    }
  }
  
  // MARK: - Triple Operations
  
  /// Adds a triple to the store.
  ///
  /// For cardinality-one attributes, this replaces any existing value.
  /// For cardinality-many attributes, this adds to the set of values.
  ///
  /// - Parameters:
  ///   - triple: The triple to add
  ///   - hasCardinalityOne: Whether this attribute has cardinality one (replaces existing)
  ///   - isRef: Whether this is a reference attribute (adds to VAE index)
  public func addTriple(_ triple: Triple, hasCardinalityOne: Bool, isRef: Bool = false) {
    lock.withLock {
      addTripleInternal(triple, hasCardinalityOne: hasCardinalityOne, isRef: isRef)
    }
  }
  
  private func addTripleInternal(_ triple: Triple, hasCardinalityOne: Bool, isRef: Bool) {
    let e = triple.entityId
    let a = triple.attributeId
    let v = triple.value.hashableKey
    
    // NOTE: The JavaScript store does NOT do LWW conflict resolution in addTriple.
    // It simply overwrites values. The server is the source of truth, and when
    // server data arrives, it should always be applied.
    //
    // The previous implementation compared createdAt timestamps, but this caused
    // a bug where optimistic updates (with createdAt = Date.now * 10) would always
    // beat server updates (with createdAt = 0 or Date.now), causing server changes
    // to be silently ignored after a local mutation.
    //
    // - SeeAlso: instant/client/packages/core/src/store.ts addTriple()
    
    if hasCardinalityOne {
      // Replace the entire value map for cardinality one
      setInMap(&eav, path: [e, a], value: [v: triple])
      setInMap(&aev, path: [a, e], value: [v: triple])
    } else {
      // Add or overwrite for cardinality many
      setInMap(&eav, path: [e, a, v], value: triple)
      setInMap(&aev, path: [a, e, v], value: triple)
    }
    
    if isRef {
      setInMap(&vae, path: [v, a, e], value: triple)
    }
  }
  
  /// Retracts (removes) a triple from the store.
  ///
  /// - Parameters:
  ///   - triple: The triple to remove
  ///   - isRef: Whether this is a reference attribute
  public func retractTriple(_ triple: Triple, isRef: Bool = false) {
    lock.withLock {
      let e = triple.entityId
      let a = triple.attributeId
      let v = triple.value.hashableKey
      
      // Check for existing triple
      if let existingTriple = getInMap(eav, path: [e, a, v]) as? Triple {
          if existingTriple.createdAt > triple.createdAt {
              // Existing triple is newer than this retraction, ignore retraction
              return
          }
      } else {
          // If data doesn't exist, we don't need to do anything?
          // Or should we store a "tombstone"? 
          // Current implementation just removes from map, so if not present, nothing to do.
          return
      }
      
      deleteInMap(&eav, path: [e, a, v])
      deleteInMap(&aev, path: [a, e, v])
      
      if isRef {
        deleteInMap(&vae, path: [v, a, e])
      }
    }
  }
  
  /// Deletes an entire entity and all its triples.
  ///
  /// - Parameters:
  ///   - entityId: The entity to delete
  ///   - attrsStore: The attribute store for determining ref attributes
  public func deleteEntity(_ entityId: String, attrsStore: AttrsStore) {
    lock.withLock {
      // Delete forward attributes
      if let entityAttrs = eav[entityId] {
        for (attrId, _) in entityAttrs {
          deleteInMap(&aev, path: [attrId, entityId])
        }
        eav.removeValue(forKey: entityId)
      }
      
      // Delete reverse references (where this entity is the value)
      if let refAttrs = vae[AnyHashable(entityId)] {
        for (attrId, entities) in refAttrs {
          for (refEntityId, _) in entities {
            deleteInMap(&eav, path: [refEntityId, attrId, AnyHashable(entityId)])
            deleteInMap(&aev, path: [attrId, refEntityId, AnyHashable(entityId)])
          }
        }
        vae.removeValue(forKey: AnyHashable(entityId))
      }
    }
  }
  
  // MARK: - Queries
  
  /// Checks if a triple exists in the store.
  public func hasTriple(_ triple: Triple) -> Bool {
    lock.withLock {
      getInMap(eav, path: [triple.entityId, triple.attributeId, triple.value.hashableKey]) != nil
    }
  }
  
  /// Checks if an entity exists in the store.
  public func hasEntity(_ entityId: String) -> Bool {
    lock.withLock {
      eav[entityId] != nil
    }
  }
  
  /// Gets all triples matching the given pattern.
  ///
  /// Any parameter can be `nil` to match all values:
  /// - `getTriples(entity: "e1", attribute: nil, value: nil)` - all triples for entity e1
  /// - `getTriples(entity: nil, attribute: "a1", value: nil)` - all triples with attribute a1
  /// - `getTriples(entity: "e1", attribute: "a1", value: nil)` - specific attribute of entity
  ///
  /// - Parameters:
  ///   - entity: Entity ID to match, or nil for any
  ///   - attribute: Attribute ID to match, or nil for any
  ///   - value: Value to match, or nil for any
  /// - Returns: Array of matching triples
  public func getTriples(entity: String? = nil, attribute: String? = nil, value: AnyHashable? = nil) -> [Triple] {
    lock.withLock {
      switch (entity, attribute, value) {
      case (.some(let e), .some(let a), .some(let v)):
        // EAV lookup
        if let triple = getInMap(eav, path: [e, a, v]) as? Triple {
          return [triple]
        }
        return []
        
      case (.some(let e), .some(let a), .none):
        // EA lookup - all values for entity+attribute
        guard let valueMap = getInMap(eav, path: [e, a]) as? [AnyHashable: Triple] else {
          return []
        }
        return Array(valueMap.values)
        
      case (.some(let e), .none, .none):
        // E lookup - all triples for entity
        guard let attrMap = eav[e] else { return [] }
        return attrMap.values.flatMap { $0.values }
        
      case (.none, .some(let a), .none):
        // A lookup - all triples with attribute
        guard let entityMap = aev[a] else { return [] }
        return entityMap.values.flatMap { $0.values }
        
      case (.none, .some(let a), .some(let v)):
        // AV lookup - entities with specific attribute value
        guard let entityMap = aev[a] else { return [] }
        return entityMap.values.compactMap { valueMap -> Triple? in
          valueMap[v]
        }
        
      case (.some(let e), .none, .some(let v)):
        // EV lookup - attributes of entity with specific value
        guard let attrMap = eav[e] else { return [] }
        return attrMap.values.compactMap { valueMap -> Triple? in
          valueMap[v]
        }
        
      case (.none, .none, .some(let v)):
        // V lookup - all triples with value
        var results: [Triple] = []
        for attrMap in eav.values {
          for valueMap in attrMap.values {
            if let triple = valueMap[v] {
              results.append(triple)
            }
          }
        }
        return results
        
      case (.none, .none, .none):
        // All triples
        return allTriples()
      }
    }
  }
  
  /// Gets all triples in the store.
  public func allTriples() -> [Triple] {
    lock.withLock {
      var results: [Triple] = []
      for attrMap in eav.values {
        for valueMap in attrMap.values {
          results.append(contentsOf: valueMap.values)
        }
      }
      return results
    }
  }
  
  /// Gets reverse references - entities that reference the given entity.
  ///
  /// - Parameters:
  ///   - entityId: The entity being referenced
  ///   - attributeId: Optional attribute to filter by
  /// - Returns: Triples where the value is a reference to the given entity
  public func getReverseRefs(entityId: String, attributeId: String? = nil) -> [Triple] {
    lock.withLock {
      guard let attrMap = vae[AnyHashable(entityId)] else { return [] }
      
      if let attrId = attributeId {
        guard let entityMap = attrMap[attrId] else { return [] }
        return Array(entityMap.values)
      }
      
      return attrMap.values.flatMap { $0.values }
    }
  }
  
  /// Gets an entity as a dictionary of attribute labels to values.
  ///
  /// - Parameters:
  ///   - entityId: The entity ID
  ///   - blobAttrs: Map of attribute labels to attribute definitions
  /// - Returns: Dictionary of label -> value
  public func getAsObject(entityId: String, blobAttrs: [String: Attribute]?) -> [String: Any] {
    lock.withLock {
      var obj: [String: Any] = [:]
      
      guard let attrs = blobAttrs, let attrMap = eav[entityId] else {
        return obj
      }
      
      for (label, attr) in attrs {
        if let valueMap = attrMap[attr.id], let triple = valueMap.values.first {
          obj[label] = triple.value.toAny()
        }
      }
      
      return obj
    }
  }
  
  // MARK: - Serialization
  
  /// Converts the store to a JSON-serializable format.
  public func toJSON() -> StoreJSON {
    StoreJSON(
      triples: allTriples(),
      cardinalityInference: cardinalityInference,
      useDateObjects: useDateObjects,
      version: 1
    )
  }
  
  /// Creates a store from JSON.
  public static func fromJSON(_ json: StoreJSON, attrsStore: AttrsStore) -> TripleStore {
    let store = TripleStore(triples: json.triples, attrsStore: attrsStore)
    store.cardinalityInference = json.cardinalityInference
    store.useDateObjects = json.useDateObjects
    return store
  }
}

// MARK: - StoreJSON

/// JSON-serializable representation of a TripleStore
public struct StoreJSON: Codable, Sendable {
  public let triples: [Triple]
  public let cardinalityInference: Bool
  public let useDateObjects: Bool
  public let version: Int
}

// MARK: - Map Helpers

/// Sets a value in a nested dictionary structure
private func setInMap<V>(_ map: inout [String: [String: [AnyHashable: V]]], path: [Any], value: V) {
  guard path.count == 3,
        let k1 = path[0] as? String,
        let k2 = path[1] as? String,
        let k3 = path[2] as? AnyHashable else { return }
  
  if map[k1] == nil { map[k1] = [:] }
  if map[k1]![k2] == nil { map[k1]![k2] = [:] }
  map[k1]![k2]![k3] = value
}

/// Sets a value map in a nested dictionary (for cardinality one)
private func setInMap<V>(_ map: inout [String: [String: [AnyHashable: V]]], path: [String], value: [AnyHashable: V]) {
  guard path.count == 2 else { return }
  let k1 = path[0]
  let k2 = path[1]
  
  if map[k1] == nil { map[k1] = [:] }
  map[k1]![k2] = value
}

/// Sets a value in VAE index
private func setInMap(_ map: inout [AnyHashable: [String: [String: Triple]]], path: [Any], value: Triple) {
  guard path.count == 3,
        let k1 = path[0] as? AnyHashable,
        let k2 = path[1] as? String,
        let k3 = path[2] as? String else { return }
  
  if map[k1] == nil { map[k1] = [:] }
  if map[k1]![k2] == nil { map[k1]![k2] = [:] }
  map[k1]![k2]![k3] = value
}

/// Gets a value from a nested dictionary
private func getInMap<K1: Hashable, K2: Hashable, K3: Hashable, V>(_ map: [K1: [K2: [K3: V]]], path: [Any]) -> Any? {
  guard path.count >= 1, let k1 = path[0] as? K1 else { return nil }
  guard let level1 = map[k1] else { return nil }
  
  if path.count == 1 { return level1 }
  guard let k2 = path[1] as? K2, let level2 = level1[k2] else { return nil }
  
  if path.count == 2 { return level2 }
  guard let k3 = path[2] as? K3 else { return nil }
  
  return level2[k3]
}

/// Deletes a value from a nested dictionary
private func deleteInMap<V>(_ map: inout [String: [String: [AnyHashable: V]]], path: [Any]) {
  guard path.count == 3,
        let k1 = path[0] as? String,
        let k2 = path[1] as? String,
        let k3 = path[2] as? AnyHashable else { return }
  
  map[k1]?[k2]?.removeValue(forKey: k3)
  
  // Clean up empty nested maps
  if map[k1]?[k2]?.isEmpty == true {
    map[k1]?.removeValue(forKey: k2)
  }
  if map[k1]?.isEmpty == true {
    map.removeValue(forKey: k1)
  }
}

/// Deletes from VAE index
private func deleteInMap(_ map: inout [AnyHashable: [String: [String: Triple]]], path: [Any]) {
  guard path.count == 3,
        let k1 = path[0] as? AnyHashable,
        let k2 = path[1] as? String,
        let k3 = path[2] as? String else { return }
  
  map[k1]?[k2]?.removeValue(forKey: k3)
  
  if map[k1]?[k2]?.isEmpty == true {
    map[k1]?.removeValue(forKey: k2)
  }
  if map[k1]?.isEmpty == true {
    map.removeValue(forKey: k1)
  }
}


