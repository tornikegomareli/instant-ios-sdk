import Foundation

/// Represents a chain of transaction operations
public final class TransactionChunk {
  private(set) var ops: [[Any]]
  private let entityType: String
  private let entityId: String

  init(entityType: String, entityId: String, ops: [[Any]] = []) {
    self.entityType = entityType
    self.entityId = entityId
    self.ops = ops
  }

  /// Create a new entity with the provided attributes
  /// - Parameter attributes: Dictionary of attribute names and values
  /// - Returns: A new TransactionChunk with the create operation added
  public func create(_ attributes: [String: Any]) -> TransactionChunk {
    let newOps = ops + [["create", entityType, entityId, attributes]]
    return TransactionChunk(entityType: entityType, entityId: entityId, ops: newOps)
  }

  /// Update entity attributes (upsert by default)
  /// - Parameters:
  ///   - attributes: Dictionary of attribute names and values
  ///   - upsert: If false, throws error if entity doesn't exist. Default is true.
  /// - Returns: A new TransactionChunk with the update operation added
  public func update(_ attributes: [String: Any], upsert: Bool = true) -> TransactionChunk {
    let opts = ["upsert": upsert]
    let newOps = ops + [["update", entityType, entityId, attributes, opts]]
    return TransactionChunk(entityType: entityType, entityId: entityId, ops: newOps)
  }

  /// Merge attributes with existing entity (deep merge for nested objects)
  /// - Parameters:
  ///   - attributes: Dictionary of attribute names and values to merge
  ///   - upsert: If false, throws error if entity doesn't exist. Default is true.
  /// - Returns: A new TransactionChunk with the merge operation added
  public func merge(_ attributes: [String: Any], upsert: Bool = true) -> TransactionChunk {
    let opts = ["upsert": upsert]
    let newOps = ops + [["merge", entityType, entityId, attributes, opts]]
    return TransactionChunk(entityType: entityType, entityId: entityId, ops: newOps)
  }

  /// Link this entity to other entities
  /// - Parameter links: Dictionary mapping link names to entity IDs (String or [String])
  /// - Returns: A new TransactionChunk with the link operation added
  ///
  /// Example:
  /// ```swift
  /// tx.goals[goalId].link(["todos": todoId])
  /// tx.goals[goalId].link(["todos": [todoId1, todoId2]])
  /// ```
  public func link(_ links: [String: Any]) -> TransactionChunk {
    let newOps = ops + [["link", entityType, entityId, links]]
    return TransactionChunk(entityType: entityType, entityId: entityId, ops: newOps)
  }

  /// Unlink this entity from other entities
  /// - Parameter links: Dictionary mapping link names to entity IDs (String or [String])
  /// - Returns: A new TransactionChunk with the unlink operation added
  public func unlink(_ links: [String: Any]) -> TransactionChunk {
    let newOps = ops + [["unlink", entityType, entityId, links]]
    return TransactionChunk(entityType: entityType, entityId: entityId, ops: newOps)
  }

  /// Delete this entity and all its links
  /// - Returns: A new TransactionChunk with the delete operation added
  public func delete() -> TransactionChunk {
    let newOps = ops + [["delete", entityType, entityId]]
    return TransactionChunk(entityType: entityType, entityId: entityId, ops: newOps)
  }
}
