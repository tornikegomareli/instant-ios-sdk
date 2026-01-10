import Foundation

// MARK: - Type Aliases

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

// MARK: - Flexible Bool

/// A boolean type that can decode from both Bool and Int values.
///
/// InstantDB's server sometimes returns `0`/`1` for boolean fields instead of
/// `true`/`false`. This type handles both cases transparently.
///
/// ## Usage
///
/// Use `FlexibleBool` in your entity types for boolean fields:
///
/// ```swift
/// struct Todo: Codable {
///   let id: String
///   let title: String
///   var done: FlexibleBool  // Decodes from true/false OR 0/1
/// }
/// ```
///
/// You can use it like a regular Bool thanks to `ExpressibleByBooleanLiteral`:
/// ```swift
/// var todo = Todo(done: false)  // Works!
/// if todo.done.wrappedValue {
///   print("Done!")
/// }
/// todo.done.toggle()  // Toggle support
/// ```
@propertyWrapper
public struct FlexibleBool: Codable, Sendable, Equatable, Hashable, ExpressibleByBooleanLiteral {
  public var wrappedValue: Bool
  
  public init(wrappedValue: Bool) {
    self.wrappedValue = wrappedValue
  }
  
  public init(_ value: Bool) {
    self.wrappedValue = value
  }
  
  public init(booleanLiteral value: Bool) {
    self.wrappedValue = value
  }
  
  /// Toggle the boolean value
  public mutating func toggle() {
    wrappedValue.toggle()
  }
  
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    
    // Try decoding as Bool first
    if let boolValue = try? container.decode(Bool.self) {
      self.wrappedValue = boolValue
      return
    }
    
    // Try decoding as Int (0 = false, non-zero = true)
    if let intValue = try? container.decode(Int.self) {
      self.wrappedValue = intValue != 0
      return
    }
    
    // Try decoding as Double (0.0 = false, non-zero = true)
    if let doubleValue = try? container.decode(Double.self) {
      self.wrappedValue = doubleValue != 0
      return
    }
    
    throw DecodingError.typeMismatch(
      Bool.self,
      DecodingError.Context(
        codingPath: decoder.codingPath,
        debugDescription: "Expected Bool, Int, or Double for FlexibleBool"
      )
    )
  }
  
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(wrappedValue)
  }
}

// MARK: - Flexible Double

/// A Double type that can decode from both Double and Bool values.
///
/// InstantDB's server sometimes returns `false` for `0` and `true` for non-zero
/// numeric fields. This type handles both cases transparently.
///
/// ## Usage
///
/// Use `FlexibleDouble` in your entity types for numeric fields that might
/// receive boolean values from the server:
///
/// ```swift
/// struct Post: Codable {
///   let id: String
///   let content: String
///   var likesCount: FlexibleDouble  // Decodes from number OR false/true
/// }
/// ```
@propertyWrapper
public struct FlexibleDouble: Codable, Sendable, Equatable, Hashable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
  public var wrappedValue: Double
  
  public init(wrappedValue: Double) {
    self.wrappedValue = wrappedValue
  }
  
  public init(_ value: Double) {
    self.wrappedValue = value
  }
  
  public init(floatLiteral value: Double) {
    self.wrappedValue = value
  }
  
  public init(integerLiteral value: Int) {
    self.wrappedValue = Double(value)
  }
  
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    
    // Try decoding as Double first
    if let doubleValue = try? container.decode(Double.self) {
      self.wrappedValue = doubleValue
      return
    }
    
    // Try decoding as Int
    if let intValue = try? container.decode(Int.self) {
      self.wrappedValue = Double(intValue)
      return
    }
    
    // Try decoding as Bool (false = 0, true = 1)
    // This handles InstantDB returning `false` for 0
    if let boolValue = try? container.decode(Bool.self) {
      self.wrappedValue = boolValue ? 1.0 : 0.0
      return
    }
    
    throw DecodingError.typeMismatch(
      Double.self,
      DecodingError.Context(
        codingPath: decoder.codingPath,
        debugDescription: "Expected Double, Int, or Bool for FlexibleDouble"
      )
    )
  }
  
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(wrappedValue)
  }
}

// MARK: - Value Types

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

// MARK: - Connection State

/// Represents the current state of the WebSocket connection to InstantDB.
///
/// The connection progresses through states: disconnected → connecting → connected → authenticated.
/// If an error occurs at any point, the state transitions to `.error`.
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

// MARK: - Errors

/// Errors specific to InstantDB operations.
///
/// These errors cover connection issues, authentication failures, and data handling problems.
/// Each error provides a localized description and, where applicable, recovery suggestions.
public enum InstantError: Error, LocalizedError {
  /// The client is not connected to the InstantDB server.
  case notConnected
  
  /// The client is not authenticated (no valid session).
  case notAuthenticated
  
  /// The provided app ID is malformed.
  case invalidAppID
  
  /// A message from the server could not be parsed.
  case invalidMessage
  
  /// The query format is invalid.
  case invalidQuery
  
  /// A generic connection failure occurred.
  case connectionFailed(Error)
  
  /// SSL/TLS certificate trust evaluation failed.
  ///
  /// ## Why This Error Exists
  /// Corporate security software (Zscaler, Netskope, Cisco AnyConnect, etc.) often
  /// performs SSL inspection by intercepting HTTPS traffic with their own certificates.
  /// iOS's App Transport Security rejects these certificates because they're not from
  /// a trusted root CA, causing connection failures.
  ///
  /// ## Discovery
  /// This was identified during testing when developers behind corporate VPNs experienced
  /// cryptic `-1200` and `-9802` errors. The SDK now detects these specific error codes
  /// and provides actionable guidance.
  ///
  /// - Parameter underlyingError: The original NSError from URLSession.
  case sslTrustFailure(underlyingError: Error)
  
  /// The server returned an error response.
  case serverError(String, hint: [String: Any]? = nil)
  
  /// A request timed out.
  case timeout
  
  /// Failed to decode a server response.
  case decodingError(Error)
  
  /// Failed to encode a message for sending.
  case encodingError(Error)

  // MARK: LocalizedError
  
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
      return Self.sslTrustFailureRecoverySuggestion
    default:
      return nil
    }
  }
}

// MARK: - SSL/TLS Error Detection

extension InstantError {
  
  /// Returns true if this error represents an SSL/TLS trust failure.
  ///
  /// Used to determine whether to show SSL-specific recovery guidance to the user.
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
  
  /// Determines if an error is an SSL/TLS trust failure based on system error codes.
  ///
  /// ## Why This Detection Exists
  /// iOS reports SSL failures through various error domains and codes. Without explicit
  /// detection, these appear as generic "connection failed" errors, leaving developers
  /// confused about why their app won't connect.
  ///
  /// ## Error Codes Detected
  /// **NSURLErrorDomain:**
  /// - `-1200`: NSURLErrorSecureConnectionFailed
  /// - `-1201`: NSURLErrorServerCertificateHasBadDate
  /// - `-1202`: NSURLErrorServerCertificateUntrusted
  /// - `-1203`: NSURLErrorServerCertificateHasUnknownRoot
  /// - `-1204`: NSURLErrorServerCertificateNotYetValid
  /// - `-1205`: NSURLErrorClientCertificateRejected
  /// - `-1206`: NSURLErrorClientCertificateRequired
  ///
  /// **kCFStreamErrorDomainSSL:**
  /// - `-9802`: errSSLFatalAlert
  /// - `-9813`: errSSLNoRootCert
  /// - `-9814`: errSSLUnknownRootCert
  /// - `-9824`: errSSLPeerHandshakeFail
  /// - `-9843`: errSSLXCertChainInvalid
  public static func isSSLTrustError(_ error: Error) -> Bool {
    let nsError = error as NSError
    
    // NSURLErrorDomain SSL-related codes
    if nsError.domain == NSURLErrorDomain {
      let sslErrorCodes: Set<Int> = [
        -1200, -1201, -1202, -1203, -1204, -1205, -1206
      ]
      if sslErrorCodes.contains(nsError.code) {
        return true
      }
    }
    
    // Recursively check underlying errors
    if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
      return isSSLTrustError(underlyingError)
    }
    
    // kCFStreamErrorDomainSSL codes (domain 3)
    if nsError.domain == "kCFErrorDomainCFNetwork" || nsError.domain == "NSOSStatusErrorDomain" {
      let sslStreamErrorCodes: Set<Int> = [
        -9802, -9813, -9814, -9824, -9843
      ]
      if sslStreamErrorCodes.contains(nsError.code) {
        return true
      }
    }
    
    return false
  }
  
  /// Creates an appropriate InstantError from a connection error.
  ///
  /// Automatically detects SSL/TLS trust failures and wraps them in the
  /// `.sslTrustFailure` case for better error messaging.
  public static func fromConnectionError(_ error: Error) -> InstantError {
    if isSSLTrustError(error) {
      return .sslTrustFailure(underlyingError: error)
    }
    return .connectionFailed(error)
  }
}

// MARK: - Error Messages

extension InstantError {
  
  /// Recovery suggestion for SSL/TLS trust failures.
  ///
  /// Provides actionable steps for developers encountering certificate trust issues,
  /// which are commonly caused by corporate VPN/proxy software performing SSL inspection.
  static let sslTrustFailureRecoverySuggestion = """
    This is likely caused by a corporate VPN/proxy (e.g., Zscaler, Netskope, \
    Cisco AnyConnect) intercepting SSL/TLS connections.

    Possible solutions:
    1. Temporarily disable your VPN/proxy software
    2. Add the VPN's root certificate to your device/simulator trust store
    3. Contact your IT department to whitelist api.instantdb.com

    For iOS Simulator: Drag the root certificate onto the simulator window, \
    then go to Settings > General > About > Certificate Trust Settings to enable it.
    """
  
  /// Detailed console message for SSL/TLS trust failures.
  ///
  /// This message is logged to the console when an SSL trust failure is detected,
  /// providing comprehensive troubleshooting guidance without requiring developers
  /// to search for solutions.
  static let sslTrustFailureConsoleMessage = """

    ════════════════════════════════════════════════════════════════
    ⚠️  SSL/TLS TRUST FAILURE - Cannot Connect to InstantDB
    ════════════════════════════════════════════════════════════════

    WHAT HAPPENED:
      InstantDB requires a secure WebSocket connection to api.instantdb.com
      for real-time data synchronization. Your device rejected the server's
      SSL certificate.

    WHY THIS HAPPENS:
      Corporate security software intercepts HTTPS traffic for inspection
      (SSL inspection / MITM). Common culprits:
      • Zscaler
      • Netskope
      • Cisco AnyConnect / Umbrella
      • Other corporate VPN/proxy solutions

    HOW TO FIX:
      Option 1: Temporarily disable your VPN/proxy software
      Option 2: Add your VPN's root certificate to the device trust store
      Option 3: Ask IT to whitelist api.instantdb.com

    FOR iOS SIMULATOR:
      1. Export your VPN's root certificate:

         For Zscaler, run this in Terminal:

           security find-certificate -c "Zscaler Root CA" -p /Library/Keychains/System.keychain > ~/Desktop/Zscaler.crt

         For other VPNs: Open Keychain Access.app → System keychain
         → find your VPN's root certificate → right-click → Export

      2. Drag the .crt file onto the simulator window
      3. In Simulator: Settings → General → VPN & Device Management
      4. Tap the certificate profile and install it
      5. Settings → General → About → Certificate Trust Settings
      6. Enable full trust for the root certificate

    The SDK will automatically retry the connection...
    ════════════════════════════════════════════════════════════════

    """
}

// MARK: - Schema Types

/// Attribute definition from the server schema.
///
/// Attributes define the shape of data in InstantDB, including field names,
/// types, cardinality, and indexing options.
///
/// ## Server Encoding (Clojure)
///
/// The server encodes link attributes in `instant/server/src/instant/model/schema.clj` (lines 199-200):
/// ```clojure
/// :cardinality (keyword (:has forward))
/// :unique?     (= "one" (:has reverse))
/// ```
///
/// - `cardinality`: The forward side's cardinality ("one" or "many")
/// - `unique?`: `true` if reverse has "one", `false` if reverse has "many"
///
/// ## Reverse Cardinality Derivation
///
/// Since the server only sends forward cardinality directly, we derive reverse cardinality from `unique?`:
/// - `unique? = true`  → reverse has cardinality "one" (singular entity)
/// - `unique? = false` → reverse has cardinality "many" (array of entities)
///
/// ## Example: mediaFilesMedia Link
///
/// Schema definition:
/// ```typescript
/// mediaFilesMedia: {
///   forward: { on: "mediaFiles", has: "one", label: "media" },
///   reverse: { on: "media", has: "many", label: "files" }
/// }
/// ```
///
/// Server encoding:
/// - `cardinality = "one"` (forward's has)
/// - `unique? = false` (reverse's has is "many", not "one")
///
/// Client interpretation:
/// - Forward: `MediaFile.media` → singular `Media?`
/// - Reverse: `Media.files` → array `[MediaFile]?`
public struct Attribute: Codable, Equatable, Sendable {
  public let id: AttributeID
  public let forwardIdentity: [String]
  public let reverseIdentity: [String]?
  public let valueType: ValueType
  
  /// The forward side's cardinality ("one" or "many").
  /// Encoded directly from the schema's forward.has value.
  public let cardinality: Cardinality
  
  /// Encodes the reverse side's cardinality.
  ///
  /// Server encodes as: `unique? = (= "one" (:has reverse))`
  /// - `true`: reverse has "one" (singular relationship)
  /// - `false`: reverse has "many" (array relationship)
  /// - `nil`: not a ref attribute or not specified
  ///
  /// See: `instant/server/src/instant/model/schema.clj` lines 199-200
  public let unique: Bool?
  
  public let indexed: Bool?
  public let checkedDataType: String?

  enum CodingKeys: String, CodingKey {
    case id
    case forwardIdentity = "forward-identity"
    case reverseIdentity = "reverse-identity"
    case valueType = "value-type"
    case cardinality
    /// Server sends "unique?" (Clojure boolean predicate naming convention)
    case unique = "unique?"
    case indexed
    case checkedDataType = "checked-data-type"
  }
}

// MARK: - Auth Types

/// User information from InstantDB authentication.
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

/// App information from the server.
public struct AppInformation: Codable, Equatable, Sendable {
  public let id: String
  public let title: String
}

/// Authentication state returned from the server after connection.
public struct AuthInfo: Codable, Equatable, Sendable {
  public let user: User?
  public let app: AppInformation
  public let admin: Bool?
}
