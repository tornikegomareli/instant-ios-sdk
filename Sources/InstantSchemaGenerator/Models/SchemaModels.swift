/// Schema Models for InstantDB Schema Generator
///
/// These models represent the JSON schema structure that InstantDB expects.
/// The generator parses Swift source files and produces JSON matching this format.

import Foundation

/// Output structure for the generated schema JSON.
///
/// Maps directly to InstantDB's expected schema format:
/// ```json
/// {
///   "entities": { ... },
///   "links": { ... }
/// }
/// ```
struct SchemaOutput: Encodable {
  let entities: [String: EntitySchema]
  let links: [String: LinkSchema]
}

/// Represents an entity (table) in the InstantDB schema.
///
/// Each entity has a name and a collection of attributes.
/// The `name` and `typeName` are used internally but only `attrs` is serialized.
struct EntitySchema: Encodable {
  /// The namespace name used in InstantDB (e.g., "users", "goals")
  let name: String

  /// The Swift type name (e.g., "User", "Goal")
  let typeName: String

  /// Dictionary of attribute name to attribute configuration
  var attrs: [String: AttributeSchema]

  enum CodingKeys: String, CodingKey {
    case attrs
  }
}

/// Represents an attribute (column) configuration in an entity.
///
/// Example JSON output:
/// ```json
/// {
///   "valueType": "string",
///   "config": { "indexed": true, "unique": false },
///   "required": true
/// }
/// ```
struct AttributeSchema: Encodable {
  /// The InstantDB data type: "string", "number", "boolean", "date", "json"
  let valueType: String

  /// Index and uniqueness configuration
  var config: AttributeConfig

  /// Whether this attribute is required (non-optional)
  var required: Bool?

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(valueType, forKey: .valueType)
    try container.encode(config, forKey: .config)
    if let required = required, required {
      try container.encode(required, forKey: .required)
    }
  }

  enum CodingKeys: String, CodingKey {
    case valueType, config, required
  }
}

/// Configuration options for an attribute.
struct AttributeConfig: Encodable {
  /// Whether this attribute is indexed for faster queries
  var indexed: Bool = false

  /// Whether this attribute must be unique across all entities
  var unique: Bool = false
}

/// Represents a link (relationship) between two entities.
///
/// Links are bidirectional with forward and reverse endpoints.
struct LinkSchema: Encodable {
  /// Internal name for the link (e.g., "users_goals")
  let name: String

  /// The forward direction of the relationship
  let forward: LinkEndpointSchema

  /// The reverse direction of the relationship
  let reverse: LinkEndpointSchema

  enum CodingKeys: String, CodingKey {
    case forward, reverse
  }
}

/// Represents one direction of a link relationship.
///
/// Example: User has many Goals
/// - `on`: "users"
/// - `has`: "many"
/// - `label`: "goals"
struct LinkEndpointSchema: Encodable {
  /// The entity this endpoint belongs to
  let on: String

  /// Cardinality: "one" or "many"
  let has: String

  /// The label used to access this relationship
  let label: String
}
