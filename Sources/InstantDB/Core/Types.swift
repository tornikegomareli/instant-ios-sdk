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
public enum ValueType: String, Codable, Sendable {
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
  case sslTrustFailure(underlyingError: Error)
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
    case .sslTrustFailure:
      return "SSL/TLS certificate trust evaluation failed"
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
    case .sslTrustFailure:
      return """
        This is likely caused by a corporate VPN/proxy (e.g., Zscaler, Netskope, Cisco AnyConnect) \
        intercepting SSL/TLS connections.

        Possible solutions:
        1. Temporarily disable your VPN/proxy software
        2. Add the VPN's root certificate to your device/simulator trust store
        3. Contact your IT department to whitelist api.instantdb.com

        For iOS Simulator: Drag the root certificate onto the simulator window, \
        then go to Settings > General > About > Certificate Trust Settings to enable it.
        """
    default:
      return nil
    }
  }
  
  /// Returns true if this error is an SSL/TLS trust failure
  public var isSSLTrustFailure: Bool {
    switch self {
    case .sslTrustFailure:
      return true
    case .connectionFailed(let error):
      return Self.isSSLTrustError(error)
    default:
      return false
    }
  }
  
  /// Check if an error is an SSL/TLS trust failure based on error codes
  /// NSURLErrorDomain codes:
  /// -1200: NSURLErrorSecureConnectionFailed
  /// -1201: NSURLErrorServerCertificateHasBadDate
  /// -1202: NSURLErrorServerCertificateUntrusted
  /// -1203: NSURLErrorServerCertificateHasUnknownRoot
  /// -1204: NSURLErrorServerCertificateNotYetValid
  /// -1205: NSURLErrorClientCertificateRejected
  /// -1206: NSURLErrorClientCertificateRequired
  /// -9802: errSSLFatalAlert (kCFStreamErrorDomainSSL)
  /// -9813: errSSLNoRootCert
  /// -9814: errSSLUnknownRootCert
  /// -9843: errSSLXCertChainInvalid
  public static func isSSLTrustError(_ error: Error) -> Bool {
    let nsError = error as NSError
    
    // Check NSURLErrorDomain SSL-related codes
    if nsError.domain == NSURLErrorDomain {
      let sslErrorCodes: Set<Int> = [
        -1200,  // NSURLErrorSecureConnectionFailed
        -1201,  // NSURLErrorServerCertificateHasBadDate
        -1202,  // NSURLErrorServerCertificateUntrusted
        -1203,  // NSURLErrorServerCertificateHasUnknownRoot
        -1204,  // NSURLErrorServerCertificateNotYetValid
        -1205,  // NSURLErrorClientCertificateRejected
        -1206,  // NSURLErrorClientCertificateRequired
      ]
      if sslErrorCodes.contains(nsError.code) {
        return true
      }
    }
    
    // Check for underlying SSL errors in kCFStreamErrorDomainSSL
    // These are typically in the _kCFStreamErrorCodeKey
    if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
      return isSSLTrustError(underlyingError)
    }
    
    // Check kCFStreamErrorDomainSSL codes directly
    // Domain 3 is kCFStreamErrorDomainSSL
    if nsError.domain == "kCFErrorDomainCFNetwork" || nsError.domain == "NSOSStatusErrorDomain" {
      let sslStreamErrorCodes: Set<Int> = [
        -9802,  // errSSLFatalAlert
        -9813,  // errSSLNoRootCert
        -9814,  // errSSLUnknownRootCert
        -9843,  // errSSLXCertChainInvalid
        -9824,  // errSSLPeerHandshakeFail
      ]
      if sslStreamErrorCodes.contains(nsError.code) {
        return true
      }
    }
    
    return false
  }
  
  /// Creates an appropriate InstantError from a connection error,
  /// detecting SSL/TLS trust failures and wrapping them appropriately
  public static func fromConnectionError(_ error: Error) -> InstantError {
    if isSSLTrustError(error) {
      return .sslTrustFailure(underlyingError: error)
    }
    return .connectionFailed(error)
  }
}

/// Attribute definition from server
public struct Attribute: Codable, Equatable, Sendable {
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
public struct User: Codable, Equatable, Sendable {
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
