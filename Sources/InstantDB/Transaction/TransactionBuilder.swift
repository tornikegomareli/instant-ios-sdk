import Foundation

/// Entity builder that provides subscript access to entity IDs
public final class EntityBuilder {
  private let entityType: String

  init(entityType: String) {
    self.entityType = entityType
  }

  /// Access an entity by ID to start building a transaction
  /// - Parameter id: Entity ID (UUID string or lookup string)
  /// - Returns: A TransactionChunk ready for operations
  public subscript(id: String) -> TransactionChunk {
    TransactionChunk(entityType: entityType, entityId: id, ops: [])
  }
}

/// Transaction builder that provides dynamic access to entity types
///
/// Example:
/// ```swift
/// db.tx.goals[id()].update(["title": "Get fit"])
/// db.tx.todos[todoId].link(["goals": goalId])
/// db.tx.users[userId].delete()
/// ```
@dynamicMemberLookup
public final class TransactionBuilder {

  public init() {}

  /// Dynamic member lookup for entity types
  /// - Parameter entityType: Name of the entity type (e.g., "goals", "todos")
  /// - Returns: An EntityBuilder for that type
  public subscript(dynamicMember entityType: String) -> EntityBuilder {
    EntityBuilder(entityType: entityType)
  }
}
