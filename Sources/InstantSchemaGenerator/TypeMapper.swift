/// Type Mapper for InstantDB Schema Generator
///
/// Maps Swift types to InstantDB data types.

import Foundation

/// Utility for mapping Swift types to InstantDB schema types.
enum TypeMapper {
  /// Converts a Swift type name to an InstantDB value type.
  ///
  /// Mapping:
  /// - `String` → `"string"`
  /// - `Int`, `Double`, `Float`, etc. → `"number"`
  /// - `Bool` → `"boolean"`
  /// - `Date` → `"date"`
  /// - Everything else → `"json"`
  ///
  /// - Parameter swiftType: The Swift type name (e.g., "String", "Int")
  /// - Returns: The InstantDB type string
  static func swiftTypeToInstant(_ swiftType: String) -> String {
    switch swiftType {
    case "String":
      return "string"

    case "Int", "Double", "Float", "Int8", "Int16", "Int32", "Int64",
         "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "CGFloat":
      return "number"

    case "Bool":
      return "boolean"

    case "Date":
      return "date"

    default:
      return "json"
    }
  }
}
