import Foundation

/// Represents a transaction operation chunk
///
/// TransactionChunk is immutable and chainable - each operation returns a new chunk.
/// This matches the React InstantDB API pattern.
public struct TransactionChunk {
    public let namespace: String
    public let id: String
    public let ops: [[Any]]

    public init(namespace: String, id: String, ops: [[Any]]) {
        self.namespace = namespace
        self.id = id
        self.ops = ops
    }
}

/// Result builder for batch transactions
///
/// Enables clean transaction syntax:
/// ```swift
/// try db.transact {
///     Goal.create(title: "Get fit")
///     Todo.update(id: todoId, done: true)
///     Goal.delete(id: oldGoalId)
/// }
/// ```
@resultBuilder
public struct TransactionBatchBuilder {
    public static func buildBlock(_ components: TransactionChunk...) -> [TransactionChunk] {
        Array(components)
    }

    public static func buildArray(_ components: [TransactionChunk]) -> [TransactionChunk] {
        components
    }

    public static func buildOptional(_ component: TransactionChunk?) -> [TransactionChunk] {
        component.map { [$0] } ?? []
    }

    public static func buildEither(first component: TransactionChunk) -> [TransactionChunk] {
        [component]
    }

    public static func buildEither(second component: TransactionChunk) -> [TransactionChunk] {
        [component]
    }

    public static func buildExpression(_ expression: TransactionChunk) -> TransactionChunk {
        expression
    }
}

/// Generate a new UUID for use as an entity ID
public func id() -> String {
    UUID().uuidString
}
