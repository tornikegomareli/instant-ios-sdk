import Foundation

/// Base protocol for all messages
public protocol Message: Codable {
  var op: String { get }
}

/// Base protocol for client messages
public protocol ClientMessage: Message {
  var clientEventId: String { get }
}

// MARK: - Client → Server Messages

/// Init message to authenticate and get schema
public struct InitMessage: ClientMessage {
  public let op = "init"
  public let clientEventId: String
  public let appId: String
  public let refreshToken: String?
  public let versions: [String: String]
  
  enum CodingKeys: String, CodingKey {
    case op
    case clientEventId = "client-event-id"
    case appId = "app-id"
    case refreshToken = "refresh-token"
    case versions
  }
  
  public init(
    clientEventId: String,
    appId: String,
    refreshToken: String? = nil,
    versions: [String: String] = ["InstantDB-Swift": "0.1.0"]
  ) {
    self.clientEventId = clientEventId
    self.appId = appId
    self.refreshToken = refreshToken
    self.versions = versions
  }
}

/// Add query subscription
public struct AddQueryMessage: ClientMessage {
  public let op = "add-query"
  public let clientEventId: String
  public let q: AnyCodable
  
  enum CodingKeys: String, CodingKey {
    case op
    case clientEventId = "client-event-id"
    case q
  }
  
  public init(clientEventId: String, query: [String: Any]) {
    self.clientEventId = clientEventId
    self.q = AnyCodable(query)
  }
}

/// Remove query subscription
public struct RemoveQueryMessage: ClientMessage {
  public let op = "remove-query"
  public let clientEventId: String
  public let q: AnyCodable
  
  enum CodingKeys: String, CodingKey {
    case op
    case clientEventId = "client-event-id"
    case q
  }
  
  public init(clientEventId: String, query: [String: Any]) {
    self.clientEventId = clientEventId
    self.q = AnyCodable(query)
  }
}

/// Send transaction
public struct TransactMessage: ClientMessage {
  public let op = "transact"
  public let clientEventId: String
  public let txSteps: [[AnyCodable]]
  
  enum CodingKeys: String, CodingKey {
    case op
    case clientEventId = "client-event-id"
    case txSteps = "tx-steps"
  }
  
  public init(clientEventId: String, txSteps: [[Any]]) {
    self.clientEventId = clientEventId
    self.txSteps = txSteps.map { $0.map { AnyCodable($0) } }
  }
}

// MARK: - Server → Client Messages

/// Server message envelope
public struct ServerMessage: Message, Codable {
  public let op: String
  public let clientEventId: String?
  public let data: [String: AnyCodable]
  
  enum CodingKeys: String, CodingKey {
    case op
    case clientEventId = "client-event-id"
  }
  
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.op = try container.decode(String.self, forKey: .op)
    self.clientEventId = try container.decodeIfPresent(String.self, forKey: .clientEventId)
    
    let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKeys.self)
    var data: [String: AnyCodable] = [:]
    
    for key in dynamicContainer.allKeys {
      if key.stringValue != "op" && key.stringValue != "client-event-id" {
        if let value = try? dynamicContainer.decode(AnyCodable.self, forKey: key) {
          data[key.stringValue] = value
        }
      }
    }
    
    self.data = data
  }
  
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(op, forKey: .op)
    try container.encodeIfPresent(clientEventId, forKey: .clientEventId)
    
    var dynamicContainer = encoder.container(keyedBy: DynamicCodingKeys.self)
    for (key, value) in data {
      let codingKey = DynamicCodingKeys(stringValue: key)!
      try dynamicContainer.encode(value, forKey: codingKey)
    }
  }
}

/// Init response
public struct InitOkMessage: Codable {
  public let op = "init-ok"
  public let sessionId: String
  public let clientEventId: String?
  public let attrs: [Attribute]
  public let auth: AuthInfo?
  
  enum CodingKeys: String, CodingKey {
    case op
    case sessionId = "session-id"
    case clientEventId = "client-event-id"
    case attrs
    case auth
  }
}

/// Query response
public struct AddQueryOkMessage: Codable {
  public let op = "add-query-ok"
  public let clientEventId: String?
  public let q: AnyCodable
  public let result: [AnyCodable]
  
  enum CodingKeys: String, CodingKey {
    case op
    case clientEventId = "client-event-id"
    case q
    case result
  }
}

/// Transaction response
public struct TransactOkMessage: Codable {
  public let op = "transact-ok"
  public let clientEventId: String
  public let txId: String
  
  enum CodingKeys: String, CodingKey {
    case op
    case clientEventId = "client-event-id"
    case txId = "tx-id"
  }
}

/// Error response
public struct ErrorMessage: Codable {
  public let op = "error"
  public let clientEventId: String?
  public let message: String
  public let hint: [String: AnyCodable]?
  public let status: Int?
  public let type: String?
  
  enum CodingKeys: String, CodingKey {
    case op
    case clientEventId = "client-event-id"
    case message
    case hint
    case status
    case type
  }
}

// MARK: - Helper Types

/// Type-erased Codable wrapper
public struct AnyCodable: Codable {
  public let value: Any
  
  public init(_ value: Any) {
    self.value = value
  }
  
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    
    if let bool = try? container.decode(Bool.self) {
      value = bool
    } else if let int = try? container.decode(Int.self) {
      value = int
    } else if let double = try? container.decode(Double.self) {
      value = double
    } else if let string = try? container.decode(String.self) {
      value = string
    } else if let array = try? container.decode([AnyCodable].self) {
      value = array.map { $0.value }
    } else if let dictionary = try? container.decode([String: AnyCodable].self) {
      value = dictionary.mapValues { $0.value }
    } else {
      value = NSNull()
    }
  }
  
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    
    switch value {
    case let bool as Bool:
      try container.encode(bool)
    case let int as Int:
      try container.encode(int)
    case let double as Double:
      try container.encode(double)
    case let string as String:
      try container.encode(string)
    case let array as [Any]:
      try container.encode(array.map { AnyCodable($0) })
    case let dictionary as [String: Any]:
      try container.encode(dictionary.mapValues { AnyCodable($0) })
    case is NSNull:
      try container.encodeNil()
    default:
      let context = EncodingError.Context(
        codingPath: container.codingPath,
        debugDescription: "Cannot encode value of type \(type(of: value))"
      )
      throw EncodingError.invalidValue(value, context)
    }
  }
}

/// Dynamic coding keys for runtime key access
struct DynamicCodingKeys: CodingKey {
  var stringValue: String
  var intValue: Int?
  
  init?(stringValue: String) {
    self.stringValue = stringValue
    self.intValue = nil
  }
  
  init?(intValue: Int) {
    self.stringValue = "\(intValue)"
    self.intValue = intValue
  }
}
