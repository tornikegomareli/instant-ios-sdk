// TypedPresence.swift
// InstantDB
//
// Type-safe presence types that provide compile-time safety for presence data.
//
// ## Why This Exists
//
// The base `PresenceSlice` uses `[String: Any]` for flexibility, but this loses
// type safety. When you know your presence shape at compile time (e.g., from
// generated schema types), you can use `TypedPresenceSlice<T>` instead.
//
// ## Architecture
//
// ```
// ┌─────────────────────────────────────────────────────────────────────┐
// │                         User Code                                   │
// │  @Shared(.instantPresence(Schema.Rooms.chat, roomId: "123", ...))  │
// │  var presence: RoomPresence<ChatPresence>                          │
// └─────────────────────────────────────────────────────────────────────┘
//                                  │
//                                  ▼
// ┌─────────────────────────────────────────────────────────────────────┐
// │                      SharingInstant Layer                           │
// │  TypedPresenceKey<T> - handles @Shared subscription lifecycle      │
// │  RoomPresence<T> - type-safe state container                       │
// └─────────────────────────────────────────────────────────────────────┘
//                                  │
//                                  ▼
// ┌─────────────────────────────────────────────────────────────────────┐
// │                      InstantDB SDK Layer                            │
// │  TypedPresenceSlice<T> - type-safe presence data                   │
// │  PresenceManager.subscribeTypedPresence<T>() - type-safe API       │
// └─────────────────────────────────────────────────────────────────────┘
//                                  │
//                                  ▼
// ┌─────────────────────────────────────────────────────────────────────┐
// │                      Wire Protocol Layer                            │
// │  [String: Any] dictionaries sent/received over WebSocket           │
// └─────────────────────────────────────────────────────────────────────┘
// ```
//
// ## Usage
//
// ```swift
// // Define your presence type
// struct CursorPresence: PresenceData {
//   var x: Double
//   var y: Double
//   var name: String
// }
//
// // Subscribe with type safety
// let unsub = presence.subscribeTypedPresence(
//   roomId: "document-123",
//   initialPresence: CursorPresence(x: 0, y: 0, name: "Alice")
// ) { (slice: TypedPresenceSlice<CursorPresence>) in
//   // slice.user.x, slice.user.y are type-safe!
//   for peer in slice.peers {
//     print("\(peer.data.name) at (\(peer.data.x), \(peer.data.y))")
//   }
// }
// ```
//
// - SeeAlso: [PR #6 Feedback - Type-Unsafe Dictionaries](../docs/PR6-FEEDBACK-ANALYSIS.md#5-type-unsafe-dictionaries)

import Foundation

// MARK: - PresenceData Protocol

/// A protocol for types that can be used as presence data.
///
/// Conform to this protocol to create type-safe presence data that can be
/// used with `TypedPresenceSlice<T>` and `subscribeTypedPresence<T>()`.
///
/// ## Requirements
///
/// - `Codable`: For JSON serialization to/from the wire protocol
/// - `Sendable`: For safe concurrent access across actors
/// - `Equatable`: For change detection to avoid unnecessary callbacks
///
/// ## Example
///
/// ```swift
/// struct CursorPresence: PresenceData {
///   var x: Double
///   var y: Double
///   var name: String
///   var color: String
/// }
/// ```
public protocol PresenceData: Codable, Sendable, Equatable {}

// MARK: - TypedPeer

/// A peer in a room with type-safe presence data.
///
/// Each peer has a unique session ID and their current presence data.
/// The data type is generic, allowing compile-time type safety.
public struct TypedPeer<T: PresenceData>: Identifiable, Sendable, Equatable {
  /// The peer's unique session ID assigned by InstantDB.
  public let id: String
  
  /// The peer's current presence data.
  public let data: T
  
  /// Creates a new typed peer.
  ///
  /// - Parameters:
  ///   - id: The peer's session ID.
  ///   - data: The peer's presence data.
  public init(id: String, data: T) {
    self.id = id
    self.data = data
  }
}

// MARK: - TypedPresenceSlice

/// A type-safe slice of presence data for a room.
///
/// This is the generic equivalent of `PresenceSlice`, providing compile-time
/// type safety for presence data. Use this when you know the shape of your
/// presence data at compile time.
///
/// ## Benefits over `PresenceSlice`
///
/// - **Type Safety**: Access `user.x` instead of `user["x"] as? Double`
/// - **Autocomplete**: IDE knows all available properties
/// - **Refactoring**: Rename properties safely across the codebase
/// - **Documentation**: Properties can have doc comments
///
/// ## Example
///
/// ```swift
/// struct CursorPresence: PresenceData {
///   var x: Double
///   var y: Double
///   var name: String
/// }
///
/// // Type-safe access
/// let slice: TypedPresenceSlice<CursorPresence> = ...
/// let x = slice.user.x  // Double, not Any
/// for peer in slice.peers {
///   print("\(peer.data.name) at (\(peer.data.x), \(peer.data.y))")
/// }
/// ```
public struct TypedPresenceSlice<T: PresenceData>: Sendable, Equatable {
  /// Your own presence data.
  public let user: T
  
  /// Other users' presence data.
  public let peers: [TypedPeer<T>]
  
  /// Whether we're still connecting to the room.
  public let isLoading: Bool
  
  /// Error message if room join failed.
  public let error: String?
  
  /// Creates a new typed presence slice.
  ///
  /// - Parameters:
  ///   - user: Your presence data.
  ///   - peers: Other users' presence data.
  ///   - isLoading: Whether still connecting.
  ///   - error: Any error that occurred.
  public init(
    user: T,
    peers: [TypedPeer<T>] = [],
    isLoading: Bool = false,
    error: String? = nil
  ) {
    self.user = user
    self.peers = peers
    self.isLoading = isLoading
    self.error = error
  }
  
  /// Total count of users in the room (including yourself).
  public var totalCount: Int {
    1 + peers.count
  }
  
  /// Whether there are any peers in the room.
  public var hasPeers: Bool {
    !peers.isEmpty
  }
}

// MARK: - TypedTopicMessage

/// A type-safe message received on a topic.
///
/// This is the generic equivalent of `TopicMessage`, providing compile-time
/// type safety for topic payloads.
public struct TypedTopicMessage<T: Codable & Sendable>: Sendable {
  /// The topic name.
  public let topic: String
  
  /// The message data (type-safe).
  public let data: T
  
  /// The session ID of the sender.
  public let peerId: String
  
  /// Creates a new typed topic message.
  ///
  /// - Parameters:
  ///   - topic: The topic name.
  ///   - data: The message data.
  ///   - peerId: The sender's session ID.
  public init(topic: String, data: T, peerId: String) {
    self.topic = topic
    self.data = data
    self.peerId = peerId
  }
}

// MARK: - Conversion Helpers

/// Logger for typed presence operations
private let logger = CompatibilityLogger(subsystem: "com.instantdb.sdk", category: "TypedPresence")

extension TypedPresenceSlice {
  /// Creates a typed presence slice from an untyped `PresenceSlice`.
  ///
  /// This converts the `[String: Any]` dictionaries to strongly-typed `T` values
  /// using JSON serialization.
  ///
  /// - Parameters:
  ///   - slice: The untyped presence slice.
  ///   - fallbackUser: The fallback value if user data can't be decoded.
  /// - Returns: A typed presence slice, or nil if conversion fails.
  public static func from(
    _ slice: PresenceSlice,
    fallbackUser: T
  ) -> TypedPresenceSlice<T> {
    // Decode user presence
    let user: T
    if let decoded = Self.decode(slice.user) {
      user = decoded
    } else {
      logger.warning("Failed to decode user presence, using fallback")
      user = fallbackUser
    }
    
    // Decode peer presence
    var peers: [TypedPeer<T>] = []
    for (peerId, peerData) in slice.peers {
      if let decoded: T = Self.decode(peerData) {
        peers.append(TypedPeer(id: peerId, data: decoded))
      } else {
        logger.warning("Failed to decode peer \(peerId) presence, skipping")
      }
    }
    
    return TypedPresenceSlice(
      user: user,
      peers: peers,
      isLoading: slice.isLoading,
      error: slice.error
    )
  }
  
  /// Decodes a dictionary to a typed value using JSON serialization.
  private static func decode(_ dict: [String: Any]) -> T? {
    do {
      let data = try JSONSerialization.data(withJSONObject: dict)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .millisecondsSince1970
      return try decoder.decode(T.self, from: data)
    } catch {
      logger.debug("Decode error: \(error.localizedDescription)")
      return nil
    }
  }
}

// MARK: - Encoding Helper

/// Encodes a `Codable` value to a dictionary for the wire protocol.
///
/// - Parameter value: The value to encode.
/// - Returns: A dictionary representation, or empty dictionary on failure.
public func encodePresenceData<T: Codable>(_ value: T) -> [String: Any] {
  do {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    let data = try encoder.encode(value)
    if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
      return dict
    }
  } catch {
    logger.error("Failed to encode presence data: \(error.localizedDescription)")
  }
  return [:]
}




