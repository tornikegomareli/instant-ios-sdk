import Foundation

/// Protocol for types that can be queried from InstantDB
///
/// Conform your models to this protocol to specify their namespace:
///
/// ```swift
/// struct Goal: Codable, InstantEntity {
///     static var namespace: String { "goals" }
///
///     let id: String
///     var title: String
///     var difficulty: Int?
/// }
/// ```
public protocol InstantEntity: Codable {
  /// The namespace for this entity in InstantDB
  static var namespace: String { get }
}
