import Foundation

/// Entity identifier (UUID string)
public typealias EntityID = String

/// Attribute identifier (UUID string)
public typealias AttributeID = String

/// Transaction identifier
public typealias TransactionID = String

/// Client event identifier
public typealias EventID = String

/// Room identifier
public typealias RoomID = String

/// Session identifier
public typealias SessionID = String

/// Value types supported by InstantDB
public enum ValueType: String, Codable {
  case string
  case number
  case boolean
  case ref
  case json
  case date
  case blob
}

/// Attribute cardinality
public enum Cardinality: String, Codable, Sendable {
  case one
  case many
}

/// Connection state
public enum ConnectionState: Equatable {
  case disconnected
  case connecting
  case connected
  case authenticated
  case error(InstantError)
  
  public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
    switch (lhs, rhs) {
    case (.disconnected, .disconnected),
      (.connecting, .connecting),
      (.connected, .connected),
      (.authenticated, .authenticated):
      return true
    case (.error(let lhsError), .error(let rhsError)):
      return lhsError.localizedDescription == rhsError.localizedDescription
    default:
      return false
    }
  }
}

/// InstantDB specific errors
public enum InstantError: Error, LocalizedError {
  case notConnected
  case notAuthenticated
  case invalidAppID
  case invalidMessage
  case invalidQuery
  case connectionFailed(Error)
  case serverError(String, hint: [String: Any]? = nil)
  case timeout
  case decodingError(Error)
  case encodingError(Error)

  public var errorDescription: String? {
    switch self {
    case .notConnected:
      return "Not connected to InstantDB server"
    case .notAuthenticated:
      return "Not authenticated"
    case .invalidAppID:
      return "Invalid app ID format"
    case .invalidMessage:
      return "Invalid message format"
    case .invalidQuery:
      return "Invalid query format"
    case .connectionFailed(let error):
      return "Connection failed: \(error.localizedDescription)"
    case .serverError(let message, let hint):
      var errorText = message
      if let hint = hint, !hint.isEmpty {
        errorText += "\n\nHint: \(hint)"
      }
      errorText += "\n\nLearn more: https://www.instantdb.com/docs"
      return errorText
    case .timeout:
      return "Request timed out"
    case .decodingError(let error):
      return "Failed to decode message: \(error.localizedDescription)"
    case .encodingError(let error):
      return "Failed to encode message: \(error.localizedDescription)"
    }
  }

  public var recoverySuggestion: String? {
    switch self {
    case .serverError:
      return "Check the InstantDB docs: https://www.instantdb.com/docs"
    default:
      return nil
    }
  }
}

/// Attribute definition from server
public struct Attribute: Codable, Equatable {
  public let id: AttributeID
  public let forwardIdentity: [String]
  public let reverseIdentity: [String]?
  public let valueType: ValueType
  public let cardinality: Cardinality
  public let unique: Bool?
  public let indexed: Bool?
  public let checkedDataType: String?

  enum CodingKeys: String, CodingKey {
    case id
    case forwardIdentity = "forward-identity"
    case reverseIdentity = "reverse-identity"
    case valueType = "value-type"
    case cardinality
    case unique
    case indexed
    case checkedDataType = "checked-data-type"
  }
}

/// User information
public struct User: Codable, Equatable {
  public let id: String
  public let email: String?
  public let refreshToken: String?

  public init(id: String, email: String?, refreshToken: String?) {
    self.id = id
    self.email = email
    self.refreshToken = refreshToken
  }

  enum CodingKeys: String, CodingKey {
    case id
    case email
    case refreshToken = "refresh_token"
  }
}

/// App information
public struct AppInformation: Codable, Equatable {
  public let id: String
  public let title: String
}

/// Authentication info
public struct AuthInfo: Codable, Equatable {
  public let user: User?
  public let app: AppInformation
  public let admin: Bool?
}
