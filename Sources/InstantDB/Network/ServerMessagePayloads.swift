import Foundation

// MARK: - Server Message Payload Enum

/// Type-safe server message payloads.
///
/// ## Design Philosophy
/// - **Fail Fast**: Unknown operations throw immediately with comprehensive error messages
/// - **No `as?` Casts**: All payloads use Codable with strict types
/// - **Compile-Time Safety**: CodingKeys map server keys to Swift properties
/// - **Self-Documenting**: Each case documents what operation it handles
///
/// ## TypeScript Reference
/// See `instant/client/packages/core/src/Reactor.js` `_handleReceive()` method
/// for the canonical message handling implementation.
///
/// ## Adding New Operations
/// 1. Add a new case to this enum
/// 2. Create a corresponding payload struct with Codable conformance
/// 3. Add the case to `ServerMessagePayload.parse()`
/// 4. The compiler will guide you through any missing handlers
public enum ServerMessagePayload: Sendable {
  /// Response to `init` - contains session ID, schema attrs, and auth info
  /// TypeScript: Reactor.js line 563
  case initOk(InitOkPayload)
  
  /// Response to `add-query` - contains query results
  /// TypeScript: Reactor.js line 582
  case addQueryOk(AddQueryOkPayload)
  
  /// Query already exists (duplicate subscription)
  /// TypeScript: Reactor.js line 578
  case addQueryExists(AddQueryExistsPayload)
  
  /// Response to `refresh` - data refresh complete
  /// TypeScript: Reactor.js line 634
  case refreshOk(RefreshOkPayload)
  
  /// Response to `transact` - transaction committed
  /// TypeScript: Reactor.js line 716
  case transactOk(TransactOkPayload)
  
  /// Response to `join-room` - room joined successfully
  /// TypeScript: Reactor.js line 778
  case joinRoomOk(JoinRoomOkPayload)
  
  /// Response to `leave-room` - room left successfully
  /// TypeScript: Reactor.js line 795
  case leaveRoomOk(LeaveRoomOkPayload)
  
  /// Error joining room
  /// TypeScript: Reactor.js line 800
  case joinRoomError(JoinRoomErrorPayload)
  
  /// Full presence refresh - contains all peers in room
  /// TypeScript: Reactor.js line 764
  case refreshPresence(RefreshPresencePayload)
  
  /// Incremental presence update - contains edits to apply
  /// TypeScript: Reactor.js line 757
  case patchPresence(PatchPresencePayload)
  
  /// Broadcast from another peer on a topic
  /// TypeScript: Reactor.js line 771
  case serverBroadcast(ServerBroadcastPayload)
  
  /// Response to `set-presence` - presence updated
  case setPresenceOk(SetPresenceOkPayload)
  
  /// Response to `client-broadcast` - broadcast sent
  case clientBroadcastOk(ClientBroadcastOkPayload)
  
  /// Server error response
  case error(ErrorPayload)
}

// MARK: - Payload Structs

/// Payload for `init-ok` message.
///
/// Contains the session ID, schema attributes, and authentication info.
/// TypeScript: Reactor.js line 563-576
public struct InitOkPayload: Codable, Sendable {
  public let sessionId: String
  public let clientEventId: String?
  public let attrs: [Attribute]
  public let auth: AuthInfo?
  
  enum CodingKeys: String, CodingKey {
    case sessionId = "session-id"
    case clientEventId = "client-event-id"
    case attrs
    case auth
  }
}

/// Payload for `add-query-ok` message.
///
/// Contains the query that was subscribed and initial results.
/// TypeScript: Reactor.js line 582-616
public struct AddQueryOkPayload: Codable, Sendable {
  public let clientEventId: String?
  public let q: AnyCodable
  public let result: [AnyCodable]
  
  enum CodingKeys: String, CodingKey {
    case clientEventId = "client-event-id"
    case q
    case result
  }
}

/// Payload for `add-query-exists` message.
///
/// Indicates the query subscription already exists.
/// TypeScript: Reactor.js line 578-580
public struct AddQueryExistsPayload: Codable, Sendable {
  public let clientEventId: String?
  public let q: AnyCodable
  
  enum CodingKeys: String, CodingKey {
    case clientEventId = "client-event-id"
    case q
  }
}

/// Payload for `refresh-ok` message.
///
/// Indicates data refresh is complete.
/// TypeScript: Reactor.js line 634-714
public struct RefreshOkPayload: Codable, Sendable {
  public let clientEventId: String?
  public let computations: [[AnyCodable]]?
  
  enum CodingKeys: String, CodingKey {
    case clientEventId = "client-event-id"
    case computations
  }
}

/// Payload for `transact-ok` message.
///
/// Contains the transaction ID of the committed transaction.
/// TypeScript: Reactor.js line 716-754
public struct TransactOkPayload: Codable, Sendable {
  public let clientEventId: String
  public let txId: Int
  
  enum CodingKeys: String, CodingKey {
    case clientEventId = "client-event-id"
    case txId = "tx-id"
  }
}

/// Payload for `join-room-ok` message.
///
/// Indicates the room was joined successfully.
/// Note: TypeScript (line 778-793) doesn't process sessions data here -
/// sessions come via `refresh-presence` messages.
/// TypeScript: Reactor.js line 778-793
public struct JoinRoomOkPayload: Codable, Sendable {
  public let roomId: String
  
  enum CodingKeys: String, CodingKey {
    case roomId = "room-id"
  }
}

/// Payload for `leave-room-ok` message.
///
/// Indicates the room was left successfully.
/// TypeScript: Reactor.js line 795-798
public struct LeaveRoomOkPayload: Codable, Sendable {
  public let roomId: String
  
  enum CodingKeys: String, CodingKey {
    case roomId = "room-id"
  }
}

/// Payload for `join-room-error` message.
///
/// Contains the error that occurred when joining the room.
/// TypeScript: Reactor.js line 800-804
public struct JoinRoomErrorPayload: Codable, Sendable {
  public let roomId: String
  public let error: String?
  public let message: String?
  
  enum CodingKeys: String, CodingKey {
    case roomId = "room-id"
    case error
    case message
  }
  
  /// Returns the error message, preferring `message` over `error`
  public var errorMessage: String {
    message ?? error ?? "Unknown error"
  }
}

/// Payload for `refresh-presence` message.
///
/// Contains all peers currently in the room.
/// The `sessions` field maps to the server's `data` key.
///
/// ## Server Message Format
/// ```json
/// {
///   "room-id": "my-room",
///   "data": {
///     "session-id-1": { "data": { "name": "Alice" }, "peer-id": "...", ... },
///     "session-id-2": { "data": { "name": "Bob" }, "peer-id": "...", ... }
///   }
/// }
/// ```
///
/// TypeScript: Reactor.js line 764-769
public struct RefreshPresencePayload: Codable, Sendable {
  public let roomId: String
  /// Sessions data keyed by session ID.
  /// Maps to server's `data` field (NOT `sessions`!)
  public let sessions: [String: SessionPresenceData]
  
  enum CodingKeys: String, CodingKey {
    case roomId = "room-id"
    // CRITICAL: Server sends "data", not "sessions"
    // This mapping prevents the bug where we looked for wrong key
    case sessions = "data"
  }
}

/// Presence data for a single session/peer.
public struct SessionPresenceData: Codable, Sendable {
  /// The actual presence data set by the user
  public let data: [String: AnyCodable]
  /// The peer ID (same as session ID in most cases)
  public let peerId: String?
  /// Server instance ID
  public let instanceId: String?
  /// User info if authenticated
  public let user: AnyCodable?
  
  enum CodingKeys: String, CodingKey {
    case data
    case peerId = "peer-id"
    case instanceId = "instance-id"
    case user
  }
}

/// Payload for `patch-presence` message.
///
/// Contains incremental edits to apply to the presence state.
/// TypeScript: Reactor.js line 757-762
public struct PatchPresencePayload: Codable, Sendable {
  public let roomId: String
  public let edits: [[AnyCodable]]
  
  enum CodingKeys: String, CodingKey {
    case roomId = "room-id"
    case edits
  }
}

/// Payload for `server-broadcast` message.
///
/// Contains a broadcast from another peer on a topic.
/// TypeScript: Reactor.js line 771-776
/// Payload for `server-broadcast` message.
///
/// The server sends broadcasts with a nested structure:
/// ```json
/// {
///   "room-id": "...",
///   "topic": "emoji",
///   "data": {
///     "peer-id": "session-id-of-sender",
///     "data": { ... actual payload ... }
///   }
/// }
/// ```
///
/// TypeScript: Reactor.js line 771-776, 2393-2402
/// - `msg['room-id']` - room identifier
/// - `msg.topic` - topic name
/// - `msg.data['peer-id']` - sender's session ID (inside data!)
/// - `msg.data.data` - actual payload (inside data!)
public struct ServerBroadcastPayload: Codable, Sendable {
  public let roomId: String
  public let topic: String
  /// The data wrapper containing peer-id and the actual payload
  public let dataWrapper: BroadcastDataWrapper
  
  enum CodingKeys: String, CodingKey {
    case roomId = "room-id"
    case topic
    case dataWrapper = "data"
  }
  
  /// Nested structure inside the "data" field
  public struct BroadcastDataWrapper: Codable, Sendable {
    public let peerId: String
    public let data: [String: AnyCodable]
    
    enum CodingKeys: String, CodingKey {
      case peerId = "peer-id"
      case data
    }
  }
}

/// Payload for `set-presence-ok` message.
///
/// Indicates presence was updated successfully.
public struct SetPresenceOkPayload: Codable, Sendable {
  public let clientEventId: String?
  
  enum CodingKeys: String, CodingKey {
    case clientEventId = "client-event-id"
  }
}

/// Payload for `client-broadcast-ok` message.
///
/// Indicates broadcast was sent successfully.
public struct ClientBroadcastOkPayload: Codable, Sendable {
  public let clientEventId: String?
  
  enum CodingKeys: String, CodingKey {
    case clientEventId = "client-event-id"
  }
}

/// Payload for `error` message.
///
/// Contains error information from the server.
public struct ErrorPayload: Codable, Sendable {
  public let clientEventId: String?
  public let message: String
  public let hint: [String: AnyCodable]?
  public let status: Int?
  public let type: String?
  
  enum CodingKeys: String, CodingKey {
    case clientEventId = "client-event-id"
    case message
    case hint
    case status
    case type
  }
}

// MARK: - Error Types

/// Error thrown when server sends an unrecognized operation.
///
/// Contains comprehensive debugging information including:
/// - The unknown operation name
/// - Raw JSON payload for inspection
/// - File and line where parsing failed
/// - Instructions for how to fix
public struct UnknownServerOperationError: Error, LocalizedError, CustomStringConvertible {
  public let op: String
  public let rawJSON: String
  public let file: String
  public let line: Int
  
  public var description: String {
    """
    ════════════════════════════════════════════════════════════════════════════════
    UNKNOWN SERVER OPERATION: "\(op)"
    ════════════════════════════════════════════════════════════════════════════════
    
    WHAT HAPPENED:
      The InstantDB server sent a message with operation "\(op)" which is not
      recognized by this version of the iOS SDK.
    
    RAW JSON PAYLOAD:
    \(rawJSON.prefix(500))\(rawJSON.count > 500 ? "... (truncated)" : "")
    
    WHERE THIS FAILED:
      File: \(file)
      Line: \(line)
    
    HOW TO FIX:
      1. Check if this is a new operation added to InstantDB
      2. Look at the TypeScript reference implementation:
         instant/client/packages/core/src/Reactor.js
         Search for: case '\(op)':
      3. Add a new case to ServerMessagePayload enum
      4. Create a corresponding payload struct with Codable conformance
      5. Add the case to ServerMessagePayload.parse()
    
    TYPESCRIPT REFERENCE:
      The canonical message handling is in Reactor.js _handleReceive() method.
      All server ops are handled in a switch statement starting around line 560.
    ════════════════════════════════════════════════════════════════════════════════
    """
  }
  
  public var errorDescription: String? { description }
}

/// Error thrown when a server message payload doesn't match expected schema.
///
/// Contains comprehensive debugging information including:
/// - The operation that failed
/// - Expected type name
/// - Underlying decoding error
/// - Raw JSON for inspection
public struct ServerMessageParseError: Error, LocalizedError, CustomStringConvertible {
  public let op: String
  public let expectedType: String
  public let underlyingError: Error
  public let rawJSON: String
  public let file: String
  public let line: Int
  
  public var description: String {
    """
    ════════════════════════════════════════════════════════════════════════════════
    SERVER MESSAGE PARSE FAILURE: "\(op)"
    ════════════════════════════════════════════════════════════════════════════════
    
    WHAT HAPPENED:
      Received "\(op)" message but failed to decode it as \(expectedType).
    
    DECODING ERROR:
      \(underlyingError.localizedDescription)
    
    RAW JSON PAYLOAD:
    \(rawJSON.prefix(500))\(rawJSON.count > 500 ? "... (truncated)" : "")
    
    WHERE THIS FAILED:
      File: \(file)
      Line: \(line)
    
    HOW TO FIX:
      1. The server sent a "\(op)" message with unexpected structure
      2. Compare the raw JSON above with the expected \(expectedType) struct
      3. Check if the server API changed - look at TypeScript:
         instant/client/packages/core/src/Reactor.js
         Search for: case '\(op)':
      4. Update the \(expectedType) struct to match the actual payload
    
    COMMON ISSUES:
      - Missing required field (check CodingKeys mapping)
      - Wrong field type (e.g., String vs Int)
      - Renamed field (e.g., "sessions" vs "data")
    ════════════════════════════════════════════════════════════════════════════════
    """
  }
  
  public var errorDescription: String? { description }
}

// MARK: - Parsing

extension ServerMessagePayload {
  /// Parse a server message with strict validation.
  ///
  /// ## Behavior
  /// - Throws `UnknownServerOperationError` for unrecognized ops
  /// - Throws `ServerMessageParseError` if payload doesn't match expected schema
  /// - NO fallback/unknown case - we fail fast
  ///
  /// ## Usage
  /// ```swift
  /// let payload = try ServerMessagePayload.parse(from: jsonData)
  /// switch payload {
  /// case .refreshPresence(let presence):
  ///   handleRefreshPresence(presence)
  /// // ... handle other cases
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - data: Raw JSON data from the server
  ///   - file: Source file (for error reporting)
  ///   - line: Source line (for error reporting)
  /// - Returns: Parsed and typed payload
  /// - Throws: `UnknownServerOperationError` or `ServerMessageParseError`
  public static func parse(
    from data: Data,
    file: String = #file,
    line: Int = #line
  ) throws -> ServerMessagePayload {
    let decoder = JSONDecoder()
    let rawJSON = String(data: data, encoding: .utf8) ?? "<binary data>"
    
    // First decode just the op to determine the type
    struct OpOnly: Decodable {
      let op: String
    }
    let opOnly = try decoder.decode(OpOnly.self, from: data)
    
    // Helper to decode with better error messages
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
      do {
        return try decoder.decode(type, from: data)
      } catch {
        throw ServerMessageParseError(
          op: opOnly.op,
          expectedType: String(describing: type),
          underlyingError: error,
          rawJSON: rawJSON,
          file: file,
          line: line
        )
      }
    }
    
    // Dispatch based on operation
    // Each case maps directly to a TypeScript case in Reactor.js
    switch opOnly.op {
    case "init-ok":
      return .initOk(try decode(InitOkPayload.self))
      
    case "add-query-ok":
      return .addQueryOk(try decode(AddQueryOkPayload.self))
      
    case "add-query-exists":
      return .addQueryExists(try decode(AddQueryExistsPayload.self))
      
    case "refresh-ok":
      return .refreshOk(try decode(RefreshOkPayload.self))
      
    case "transact-ok":
      return .transactOk(try decode(TransactOkPayload.self))
      
    case "join-room-ok":
      return .joinRoomOk(try decode(JoinRoomOkPayload.self))
      
    case "leave-room-ok":
      return .leaveRoomOk(try decode(LeaveRoomOkPayload.self))
      
    case "join-room-error":
      return .joinRoomError(try decode(JoinRoomErrorPayload.self))
      
    case "refresh-presence":
      return .refreshPresence(try decode(RefreshPresencePayload.self))
      
    case "patch-presence":
      return .patchPresence(try decode(PatchPresencePayload.self))
      
    case "server-broadcast":
      return .serverBroadcast(try decode(ServerBroadcastPayload.self))
      
    case "set-presence-ok":
      return .setPresenceOk(try decode(SetPresenceOkPayload.self))
      
    case "client-broadcast-ok":
      return .clientBroadcastOk(try decode(ClientBroadcastOkPayload.self))
      
    case "error":
      return .error(try decode(ErrorPayload.self))
      
    default:
      // NO FALLBACK - fail fast with comprehensive error
      throw UnknownServerOperationError(
        op: opOnly.op,
        rawJSON: rawJSON,
        file: file,
        line: line
      )
    }
  }
}

