import Foundation

// MARK: - Triple

/// A triple represents a single fact in InstantDB's data model.
///
/// InstantDB stores all data as triples in the form `[entityId, attributeId, value, createdAt]`.
/// This is similar to RDF triples but with an additional timestamp for conflict resolution.
///
/// For example, a todo item `{ id: "abc", title: "Buy milk", done: false }` becomes:
/// ```
/// Triple(entityId: "abc", attributeId: "todos/title", value: .string("Buy milk"), createdAt: 1702847293000)
/// Triple(entityId: "abc", attributeId: "todos/done", value: .bool(false), createdAt: 1702847293000)
/// Triple(entityId: "abc", attributeId: "todos/id", value: .string("abc"), createdAt: 1702847293000)
/// ```
///
/// The `createdAt` timestamp is used for Last-Write-Wins (LWW) conflict resolution.
/// When two clients update the same attribute, the triple with the higher timestamp wins.
///
/// - Note: This is ported from `instant/client/packages/core/src/store.ts`
public struct Triple: Sendable, Equatable, Hashable {
  /// The entity this triple belongs to (UUID string)
  public let entityId: String
  
  /// The attribute identifier (UUID string referencing an attribute definition)
  public let attributeId: String
  
  /// The value of this attribute for this entity
  public let value: TripleValue
  
  /// Timestamp for conflict resolution (milliseconds since epoch * 10 for optimistic updates)
  ///
  /// InstantDB uses Last-Write-Wins (LWW) conflict resolution. When conflicts occur,
  /// the triple with the highest `createdAt` wins.
  ///
  /// For optimistic updates, we multiply `Date.now() * 10` to ensure local changes
  /// always appear "newer" than server values until confirmed.
  public let createdAt: Int64
  
  /// Creates a new triple.
  ///
  /// - Parameters:
  ///   - entityId: The entity this triple belongs to
  ///   - attributeId: The attribute identifier
  ///   - value: The value
  ///   - createdAt: Timestamp for conflict resolution
  public init(entityId: String, attributeId: String, value: TripleValue, createdAt: Int64) {
    self.entityId = entityId
    self.attributeId = attributeId
    self.value = value
    self.createdAt = createdAt
  }
  
  /// Creates a triple from a raw array representation `[entityId, attributeId, value, createdAt]`
  ///
  /// This is the format used in the wire protocol with the InstantDB server.
  public init?(fromArray array: [Any]) {
    guard array.count >= 4,
          let entityId = array[0] as? String,
          let attributeId = array[1] as? String,
          let createdAt = array[3] as? Int64 ?? (array[3] as? Int).map({ Int64($0) })
    else {
      return nil
    }
    
    self.entityId = entityId
    self.attributeId = attributeId
    self.value = TripleValue(fromAny: array[2])
    self.createdAt = createdAt
  }
  
  /// Converts the triple to array format for the wire protocol
  public func toArray() -> [Any] {
    [entityId, attributeId, value.toAny(), createdAt]
  }
}

// MARK: - TripleValue

/// A type-safe wrapper for values that can be stored in a triple.
///
/// InstantDB supports several value types:
/// - Strings
/// - Numbers (integers and floating point)
/// - Booleans
/// - Null
/// - References to other entities (stored as entity ID strings)
/// - JSON blobs (dictionaries and arrays)
/// - Dates (stored as ISO 8601 strings or timestamps)
public enum TripleValue: Sendable, Equatable, Hashable {
  case string(String)
  case int(Int64)
  case double(Double)
  case bool(Bool)
  case null
  case ref(String)  // Reference to another entity
  case json(JSONValue)
  case date(Date)
  
  /// Creates a TripleValue from an arbitrary value
  public init(fromAny value: Any?) {
    guard let value = value else {
      self = .null
      return
    }
    
    switch value {
    case let string as String:
      self = .string(string)
    case let int as Int:
      self = .int(Int64(int))
    case let int64 as Int64:
      self = .int(int64)
    case let double as Double:
      self = .double(double)
    case let bool as Bool:
      self = .bool(bool)
    case let dict as [String: Any]:
      self = .json(JSONValue.from(dict))
    case let array as [Any]:
      self = .json(JSONValue.from(array))
    case let date as Date:
      self = .date(date)
    default:
      self = .string(String(describing: value))
    }
  }
  
  /// Converts the value back to a raw type for the wire protocol
  public func toAny() -> Any {
    switch self {
    case .string(let s): return s
    case .int(let i): return i
    case .double(let d): return d
    case .bool(let b): return b
    case .null: return NSNull()
    case .ref(let id): return id
    case .json(let json): return json.toAny()
    case .date(let date): return ISO8601DateFormatter().string(from: date)
    }
  }
  
  /// Returns the value as a hashable key for use in indexes
  public var hashableKey: AnyHashable {
    switch self {
    case .string(let s): return AnyHashable(s)
    case .int(let i): return AnyHashable(i)
    case .double(let d): return AnyHashable(d)
    case .bool(let b): return AnyHashable(b)
    case .null: return AnyHashable("__null__")
    case .ref(let id): return AnyHashable(id)
    case .json(let json): return AnyHashable(json.description)
    case .date(let date): return AnyHashable(date)
    }
  }
}

// MARK: - JSONValue

/// A recursive JSON value type for storing complex nested data
public indirect enum JSONValue: Sendable, Equatable, Hashable, CustomStringConvertible {
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  case array([JSONValue])
  case object([String: JSONValue])
  
  public var description: String {
    switch self {
    case .string(let s): return "\"\(s)\""
    case .number(let n): return String(n)
    case .bool(let b): return String(b)
    case .null: return "null"
    case .array(let arr): return "[\(arr.map(\.description).joined(separator: ","))]"
    case .object(let obj): return "{\(obj.map { "\"\($0)\":\($1.description)" }.joined(separator: ","))}"
    }
  }
  
  /// Creates a JSONValue from an arbitrary value
  public static func from(_ value: Any?) -> JSONValue {
    guard let value = value else { return .null }
    
    switch value {
    case let string as String:
      return .string(string)
    case let int as Int:
      return .number(Double(int))
    case let int64 as Int64:
      return .number(Double(int64))
    case let double as Double:
      return .number(double)
    case let bool as Bool:
      return .bool(bool)
    case let dict as [String: Any]:
      return .object(dict.mapValues { from($0) })
    case let array as [Any]:
      return .array(array.map { from($0) })
    default:
      return .string(String(describing: value))
    }
  }
  
  /// Converts back to a raw dictionary/array/primitive
  public func toAny() -> Any {
    switch self {
    case .string(let s): return s
    case .number(let n): return n
    case .bool(let b): return b
    case .null: return NSNull()
    case .array(let arr): return arr.map { $0.toAny() }
    case .object(let obj): return obj.mapValues { $0.toAny() }
    }
  }
}

// MARK: - Conflict Resolution

/// Utilities for conflict resolution in InstantDB's Last-Write-Wins (LWW) strategy.
///
/// InstantDB uses timestamps to resolve conflicts:
/// - Every triple has a `createdAt` timestamp
/// - When conflicts occur, the triple with the highest timestamp wins
/// - For optimistic updates, we use `Date.now() * 10` to ensure local changes appear newer
///
/// - Note: This is ported from `instant/client/packages/core/src/store.ts` lines 411-446
public enum ConflictResolution {
  /// Generates a timestamp for optimistic updates.
  ///
  /// We multiply by 10 to ensure optimistic timestamps are always greater than
  /// anything the server could return. This way, optimistic updates always "win"
  /// locally until the server confirms or rejects them.
  ///
  /// - Returns: A timestamp suitable for optimistic updates
  public static func optimisticTimestamp() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000) * 10
  }
  
  /// Resolves a conflict between two triples using Last-Write-Wins.
  ///
  /// - Parameters:
  ///   - a: First triple
  ///   - b: Second triple
  /// - Returns: The triple with the higher `createdAt` timestamp
  public static func resolve(_ a: Triple, _ b: Triple) -> Triple {
    a.createdAt >= b.createdAt ? a : b
  }
}

// MARK: - Codable Conformance

extension Triple: Codable {
  enum CodingKeys: String, CodingKey {
    case entityId
    case attributeId
    case value
    case createdAt
  }
}

extension TripleValue: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    
    if container.decodeNil() {
      self = .null
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else if let int = try? container.decode(Int64.self) {
      self = .int(int)
    } else if let double = try? container.decode(Double.self) {
      self = .double(double)
    } else if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let json = try? container.decode(JSONValue.self) {
      self = .json(json)
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode TripleValue")
    }
  }
  
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let s): try container.encode(s)
    case .int(let i): try container.encode(i)
    case .double(let d): try container.encode(d)
    case .bool(let b): try container.encode(b)
    case .null: try container.encodeNil()
    case .ref(let id): try container.encode(id)
    case .json(let json): try container.encode(json)
    case .date(let date): try container.encode(ISO8601DateFormatter().string(from: date))
    }
  }
}

extension JSONValue: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    
    if container.decodeNil() {
      self = .null
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else if let double = try? container.decode(Double.self) {
      self = .number(double)
    } else if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let array = try? container.decode([JSONValue].self) {
      self = .array(array)
    } else if let object = try? container.decode([String: JSONValue].self) {
      self = .object(object)
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode JSONValue")
    }
  }
  
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let s): try container.encode(s)
    case .number(let n): try container.encode(n)
    case .bool(let b): try container.encode(b)
    case .null: try container.encodeNil()
    case .array(let arr): try container.encode(arr)
    case .object(let obj): try container.encode(obj)
    }
  }
}

