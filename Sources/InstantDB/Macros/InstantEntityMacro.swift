import Foundation

/// Generates transaction methods for InstantDB entities
///
/// Apply this macro to a `Codable` struct to automatically generate type-safe transaction methods.
///
/// Example:
/// ```swift
/// @InstantEntity("goals")
/// struct Goal: Codable {
///     let id: String
///     var title: String
///     var difficulty: Int?
///     var completed: Bool?
/// }
/// ```
///
/// Generated methods:
/// - `create(id:title:difficulty:completed:)` - Create with all properties
/// - `update(id:title:difficulty:completed:)` - Update specific properties
/// - `update(_:)` - Update from entity instance
/// - `merge(id:title:difficulty:completed:)` - Merge properties
/// - `delete(id:)` - Delete entity
/// - `link(id:_:to:)` - Link to other entities
/// - `unlink(id:_:from:)` - Unlink from entities
///
/// Usage:
/// ```swift
/// try db.transact {
///     Goal.create(
///         title: "Get fit",
///         difficulty: 5,
///         completed: false
///     )
///
///     Goal.update(
///         id: goalId,
///         difficulty: 7
///     )
///
///     Goal.delete(id: oldGoalId)
/// }
/// ```
@attached(member, names: named(namespace), named(schemaAttributes), named(create), named(update), named(merge), named(delete), named(link), named(unlink))
@attached(extension, conformances: InstantEntity, InstantEntitySchema, Identifiable, Codable)
public macro InstantEntity(_ namespace: String) = #externalMacro(module: "InstantDBMacros", type: "InstantEntityMacro")
