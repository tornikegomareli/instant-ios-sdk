import Foundation

// MARK: - AttrsStore

/// A store for attribute metadata with efficient lookup indexes.
///
/// Attributes define the schema of your InstantDB data. Each attribute has:
/// - A unique ID
/// - A forward identity `[_, entityType, label]` (e.g., `["_", "todos", "title"]`)
/// - An optional reverse identity for link attributes
/// - A value type (string, number, boolean, ref, etc.)
/// - Cardinality (one or many)
///
/// The AttrsStore maintains several indexes for efficient lookups:
/// - By attribute ID
/// - By forward identity (entityType + label)
/// - By reverse identity (for link attributes)
/// - Primary keys by entity type
/// - Blob attributes by entity type
///
/// ## Example
///
/// ```swift
/// let attrsStore = AttrsStore()
///
/// // Add an attribute from server
/// attrsStore.addAttr(titleAttr)
///
/// // Look up by forward identity
/// if let attr = attrsStore.getAttrByForwardIdent(entityType: "todos", label: "title") {
///   print("Found attribute: \(attr.id)")
/// }
/// ```
///
/// - Note: This is ported from `instant/client/packages/core/src/store.ts` AttrsStoreClass
public final class AttrsStore: @unchecked Sendable {
  private let lock = NSRecursiveLock()
  
  // MARK: - Storage
  
  /// All attributes by ID
  private var attrs: [String: Attribute] = [:]
  
  /// Link index for relationship traversal
  public var linkIndex: LinkIndex?
  
  // MARK: - Cached Indexes (lazily computed)
  
  private var _blobAttrs: [String: [String: Attribute]]?
  private var _primaryKeys: [String: Attribute]?
  private var _forwardIdents: [String: [String: Attribute]]?
  private var _revIdents: [String: [String: Attribute]]?
  
  // MARK: - Initialization
  
  /// Creates an empty attribute store
  public init() {}
  
  /// Creates an attribute store from an array of attributes
  public init(attrs: [Attribute], linkIndex: LinkIndex? = nil) {
    self.linkIndex = linkIndex
    for attr in attrs {
      self.attrs[attr.id] = attr
    }
  }
  
  // MARK: - Attribute Operations
  
  /// Gets an attribute by ID
  public func getAttr(_ id: String) -> Attribute? {
    lock.withLock { attrs[id] }
  }
  
  /// Adds a new attribute
  public func addAttr(_ attr: Attribute) {
    lock.withLock {
      attrs[attr.id] = attr
      resetAttrIndexes()
    }
  }
  
  /// Deletes an attribute by ID
  public func deleteAttr(_ attrId: String) {
    lock.withLock {
      attrs.removeValue(forKey: attrId)
      resetAttrIndexes()
    }
  }
  
  /// Updates an existing attribute
  public func updateAttr(_ partialAttr: PartialAttribute) {
    lock.withLock {
      guard var attr = attrs[partialAttr.id] else { return }
      
      // Update fields that are provided
      if let cardinality = partialAttr.cardinality {
        attr = Attribute(
          id: attr.id,
          forwardIdentity: attr.forwardIdentity,
          reverseIdentity: attr.reverseIdentity,
          valueType: attr.valueType,
          cardinality: cardinality,
          unique: partialAttr.unique ?? attr.unique,
          indexed: partialAttr.indexed ?? attr.indexed,
          checkedDataType: attr.checkedDataType
        )
      }
      
      attrs[partialAttr.id] = attr
      resetAttrIndexes()
    }
  }
  
  /// Resets all cached indexes (call after modifying attrs)
  private func resetAttrIndexes() {
    _blobAttrs = nil
    _primaryKeys = nil
    _forwardIdents = nil
    _revIdents = nil
  }
  
  // MARK: - Index Accessors
  
  /// Gets blob (non-ref) attributes grouped by entity type and label
  public var blobAttrs: [String: [String: Attribute]] {
    lock.withLock {
      if let cached = _blobAttrs { return cached }
      
      var result: [String: [String: Attribute]] = [:]
      for attr in attrs.values {
        if attr.valueType != .ref {
          guard attr.forwardIdentity.count >= 3 else { continue }
          let entityType = attr.forwardIdentity[1]
          let label = attr.forwardIdentity[2]
          
          if result[entityType] == nil { result[entityType] = [:] }
          result[entityType]![label] = attr
        }
      }
      
      _blobAttrs = result
      return result
    }
  }
  
  /// Gets primary key attributes by entity type
  public var primaryKeys: [String: Attribute] {
    lock.withLock {
      if let cached = _primaryKeys { return cached }
      
      var result: [String: Attribute] = [:]
      for attr in attrs.values {
        // Check if this is a primary key (id attribute)
        guard attr.forwardIdentity.count >= 3 else { continue }
        let label = attr.forwardIdentity[2]
        if label == "id" {
          let entityType = attr.forwardIdentity[1]
          result[entityType] = attr
        }
      }
      
      _primaryKeys = result
      return result
    }
  }
  
  /// Gets attributes by forward identity (entityType -> label -> Attribute)
  public var forwardIdents: [String: [String: Attribute]] {
    lock.withLock {
      if let cached = _forwardIdents { return cached }
      
      var result: [String: [String: Attribute]] = [:]
      for attr in attrs.values {
        guard attr.forwardIdentity.count >= 3 else { continue }
        let entityType = attr.forwardIdentity[1]
        let label = attr.forwardIdentity[2]
        
        if result[entityType] == nil { result[entityType] = [:] }
        result[entityType]![label] = attr
      }
      
      _forwardIdents = result
      return result
    }
  }
  
  /// Gets attributes by reverse identity (entityType -> label -> Attribute)
  public var revIdents: [String: [String: Attribute]] {
    lock.withLock {
      if let cached = _revIdents { return cached }
      
      var result: [String: [String: Attribute]] = [:]
      for attr in attrs.values {
        guard let revIdent = attr.reverseIdentity, revIdent.count >= 3 else { continue }
        let entityType = revIdent[1]
        let label = revIdent[2]
        
        if result[entityType] == nil { result[entityType] = [:] }
        result[entityType]![label] = attr
      }
      
      _revIdents = result
      return result
    }
  }
  
  // MARK: - Lookup Methods
  
  /// Gets an attribute by forward identity
  ///
  /// - Parameters:
  ///   - entityType: The entity type (e.g., "todos")
  ///   - label: The attribute label (e.g., "title")
  /// - Returns: The attribute if found
  public func getAttrByForwardIdent(entityType: String, label: String) -> Attribute? {
    forwardIdents[entityType]?[label]
  }
  
  /// Gets an attribute by reverse identity
  ///
  /// - Parameters:
  ///   - entityType: The entity type
  ///   - label: The reverse label
  /// - Returns: The attribute if found
  public func getAttrByReverseIdent(entityType: String, label: String) -> Attribute? {
    revIdents[entityType]?[label]
  }
  
  /// Gets all blob attributes for an entity type
  public func getBlobAttrs(entityType: String) -> [String: Attribute]? {
    blobAttrs[entityType]
  }
  
  /// Gets the primary key attribute for an entity type
  public func getPrimaryKeyAttr(entityType: String) -> Attribute? {
    if let pk = primaryKeys[entityType] {
      return pk
    }
    // Fall back to looking for "id" in forward idents
    return forwardIdents[entityType]?["id"]
  }
  
  // MARK: - Serialization
  
  /// Converts to JSON-serializable format
  public func toJSON() -> AttrsStoreJSON {
    AttrsStoreJSON(attrs: Array(attrs.values), linkIndex: linkIndex)
  }
  
  /// Creates from JSON
  public static func fromJSON(_ json: AttrsStoreJSON) -> AttrsStore {
    AttrsStore(attrs: json.attrs, linkIndex: json.linkIndex)
  }
  
  /// All attributes as an array
  public var allAttrs: [Attribute] {
    lock.withLock { Array(attrs.values) }
  }
}

// MARK: - Supporting Types

/// Partial attribute for updates
public struct PartialAttribute {
  public let id: String
  public var cardinality: Cardinality?
  public var unique: Bool?
  public var indexed: Bool?
  
  public init(id: String, cardinality: Cardinality? = nil, unique: Bool? = nil, indexed: Bool? = nil) {
    self.id = id
    self.cardinality = cardinality
    self.unique = unique
    self.indexed = indexed
  }
}

/// JSON-serializable representation of AttrsStore
public struct AttrsStoreJSON: Codable, Sendable {
  public let attrs: [Attribute]
  public let linkIndex: LinkIndex?
}

/// Link index for relationship traversal
///
/// Maps entity types to their link attributes for efficient graph traversal
public struct LinkIndex: Codable, Sendable, Equatable {
  /// Forward links: sourceEntityType -> label -> targetEntityType
  public var forward: [String: [String: String]]
  
  /// Reverse links: targetEntityType -> label -> sourceEntityType
  public var reverse: [String: [String: String]]
  
  public init(forward: [String: [String: String]] = [:], reverse: [String: [String: String]] = [:]) {
    self.forward = forward
    self.reverse = reverse
  }
  
  /// Creates a link index from a schema
  public static func from(schema: [String: Any]?) -> LinkIndex? {
    // TODO: Implement schema parsing
    return nil
  }
}

