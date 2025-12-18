import Foundation
import Combine

// MARK: - PresenceManager

/// Manages real-time presence for InstantDB rooms.
///
/// Presence allows you to see who else is in a room and share ephemeral state
/// like cursor positions, typing indicators, or user status.
///
/// ## Concepts
///
/// - **Room**: A named channel where users can share presence
/// - **User presence**: Your own presence data (e.g., cursor position)
/// - **Peers**: Other users in the room and their presence data
///
/// ## Example
///
/// ```swift
/// let presence = PresenceManager()
///
/// // Join a room with initial presence
/// let cleanup = presence.joinRoom("document-123", initialPresence: [
///   "cursor": ["x": 100, "y": 200],
///   "name": "Alice"
/// ])
///
/// // Subscribe to presence changes
/// let unsub = presence.subscribePresence(roomId: "document-123") { slice in
///   print("Me: \(slice.user)")
///   print("Others: \(slice.peers)")
/// }
///
/// // Update your presence
/// presence.publishPresence(roomId: "document-123", data: [
///   "cursor": ["x": 150, "y": 250]
/// ])
///
/// // Leave the room
/// cleanup()
/// ```
///
/// - Note: This is ported from `instant/client/packages/core/src/Reactor.js` lines 2136-2339
public final class PresenceManager: @unchecked Sendable {
  private let lock = NSRecursiveLock()
  
  /// Room state
  private var rooms: [String: RoomState] = [:]
  
  /// Presence data per room
  private var presence: [String: PresenceState] = [:]
  
  /// Broadcast subscriptions per room
  private var broadcastSubs: [String: [String: [BroadcastHandler]]] = [:]
  
  /// Rooms pending leave (waiting for connection)
  private var roomsPendingLeave: Set<String> = []
  
  /// Current session ID (set by client)
  public var sessionId: String?
  
  /// Callback to send messages to server
  public var sendMessage: ((String, [String: Any]) -> Void)?
  
  // MARK: - Initialization
  
  public init() {}
  
  // MARK: - Room Management
  
  /// Joins a room with optional initial presence.
  ///
  /// - Parameters:
  ///   - roomId: The room identifier
  ///   - initialPresence: Optional initial presence data
  /// - Returns: A cleanup function to leave the room
  public func joinRoom(_ roomId: String, initialPresence: [String: Any]? = nil) -> () -> Void {
    lock.withLock {
      var needsToSendJoin = false
      
      print("[Presence] joinRoom called for: \(roomId), initialPresence: \(String(describing: initialPresence))")
      
      if rooms[roomId] == nil {
        needsToSendJoin = true
        rooms[roomId] = RoomState()
        print("[Presence] Created new room state for: \(roomId)")
      }
      
      if presence[roomId] == nil {
        presence[roomId] = PresenceState()
        print("[Presence] Created new presence state for: \(roomId)")
      }
      
      // Set initial presence if provided and no previous result
      if let initial = initialPresence, presence[roomId]?.result == nil {
        presence[roomId]?.result = PresenceResult(user: initial, peers: [:])
        print("[Presence] Set initial presence for \(roomId): \(initial)")
        notifyPresenceSubs(roomId: roomId)
      }
      
      if needsToSendJoin {
        print("[Presence] Sending join-room for: \(roomId)")
        tryJoinRoom(roomId: roomId, data: initialPresence)
      } else {
        print("[Presence] Room \(roomId) already exists, not sending join")
      }
      
      return { [weak self] in
        self?.cleanupRoom(roomId: roomId)
      }
    }
  }
  
  private func cleanupRoom(roomId: String) {
    lock.withLock {
      let hasPresenceHandlers = !(presence[roomId]?.handlers.isEmpty ?? true)
      let hasBroadcastSubs = !(broadcastSubs[roomId]?.isEmpty ?? true)
      
      if !hasPresenceHandlers && !hasBroadcastSubs {
        let isConnected = rooms[roomId]?.isConnected ?? false
        
        rooms.removeValue(forKey: roomId)
        presence.removeValue(forKey: roomId)
        broadcastSubs.removeValue(forKey: roomId)
        
        if isConnected {
          tryLeaveRoom(roomId: roomId)
        } else {
          roomsPendingLeave.insert(roomId)
        }
      }
    }
  }
  
  // MARK: - Presence
  
  /// Gets the current presence for a room.
  ///
  /// - Parameters:
  ///   - roomId: The room identifier
  ///   - keys: Optional keys to filter peers by
  /// - Returns: The presence slice, or nil if not in room
  public func getPresence(roomId: String, keys: [String]? = nil) -> PresenceSlice? {
    lock.withLock {
      guard let room = rooms[roomId],
            let presenceState = presence[roomId],
            let result = presenceState.result else {
        return nil
      }
      
      return buildPresenceSlice(
        result: result,
        keys: keys,
        sessionId: sessionId
      )
    }
  }
  
  /// Publishes presence data to a room.
  ///
  /// This merges with existing presence data.
  ///
  /// - Parameters:
  ///   - roomId: The room identifier
  ///   - data: The presence data to publish
  public func publishPresence(roomId: String, data: [String: Any]) {
    lock.withLock {
      print("[Presence] publishPresence called for room: \(roomId), data: \(data)")
      
      guard rooms[roomId] != nil else {
        print("[Presence] ✗ Room \(roomId) not found, cannot publish presence")
        return
      }
      
      if presence[roomId] == nil {
        presence[roomId] = PresenceState()
      }
      
      // Merge with existing user presence
      var currentUser = presence[roomId]?.result?.user ?? [:]
      for (key, value) in data {
        currentUser[key] = value
      }
      
      if presence[roomId]?.result == nil {
        presence[roomId]?.result = PresenceResult(user: currentUser, peers: [:])
      } else {
        presence[roomId]?.result?.user = currentUser
      }
      
      // Only send if connected
      if rooms[roomId]?.isConnected == true {
        print("[Presence] Room \(roomId) is connected, sending set-presence with: \(currentUser)")
        trySetPresence(roomId: roomId, data: currentUser)
        notifyPresenceSubs(roomId: roomId)
      } else {
        print("[Presence] ✗ Room \(roomId) is NOT connected (isConnected=\(rooms[roomId]?.isConnected ?? false)), cannot send presence")
      }
    }
  }
  
  /// Subscribes to presence changes in a room.
  ///
  /// - Parameters:
  ///   - roomId: The room identifier
  ///   - keys: Optional keys to filter peers by
  ///   - initialPresence: Optional initial presence data
  ///   - callback: Called when presence changes
  /// - Returns: Unsubscribe function
  public func subscribePresence(
    roomId: String,
    keys: [String]? = nil,
    initialPresence: [String: Any]? = nil,
    callback: @escaping (PresenceSlice) -> Void
  ) -> () -> Void {
    print("[Presence] subscribePresence called for room: \(roomId), keys: \(String(describing: keys))")
    
    let leaveRoom = joinRoom(roomId, initialPresence: initialPresence)
    
    let handler = PresenceHandler(
      roomId: roomId,
      keys: keys,
      callback: callback
    )
    
    lock.withLock {
      if presence[roomId] == nil {
        presence[roomId] = PresenceState()
      }
      presence[roomId]?.handlers.append(handler)
      print("[Presence] Added handler for room \(roomId), total handlers: \(presence[roomId]?.handlers.count ?? 0)")
    }
    
    // Notify immediately with current state
    notifyPresenceSub(roomId: roomId, handler: handler)
    
    return { [weak self] in
      self?.lock.withLock {
        self?.presence[roomId]?.handlers.removeAll { $0.id == handler.id }
      }
      leaveRoom()
    }
  }
  
  // MARK: - Broadcast (Topics)
  
  /// Publishes a message to a topic in a room.
  ///
  /// - Parameters:
  ///   - roomId: The room identifier
  ///   - topic: The topic name
  ///   - data: The message data
  public func publishTopic(roomId: String, topic: String, data: [String: Any]) {
    lock.withLock {
      guard rooms[roomId] != nil else { return }
      
      sendMessage?(UUID().uuidString, [
        "op": "client-broadcast",
        "room-id": roomId,
        "topic": topic,
        "data": data
      ])
    }
  }
  
  /// Subscribes to a topic in a room.
  ///
  /// - Parameters:
  ///   - roomId: The room identifier
  ///   - topic: The topic name
  ///   - callback: Called when a message is received
  /// - Returns: Unsubscribe function
  public func subscribeTopic(
    roomId: String,
    topic: String,
    callback: @escaping (TopicMessage) -> Void
  ) -> () -> Void {
    let leaveRoom = joinRoom(roomId)
    
    let handler = BroadcastHandler(callback: callback)
    
    lock.withLock {
      if broadcastSubs[roomId] == nil {
        broadcastSubs[roomId] = [:]
      }
      if broadcastSubs[roomId]?[topic] == nil {
        broadcastSubs[roomId]?[topic] = []
      }
      broadcastSubs[roomId]?[topic]?.append(handler)
    }
    
    return { [weak self] in
      self?.lock.withLock {
        self?.broadcastSubs[roomId]?[topic]?.removeAll { $0.id == handler.id }
      }
      leaveRoom()
    }
  }
  
  // MARK: - Server Message Handling
  
  /// Handles a join-room-ok message from the server.
  public func handleJoinRoomOk(roomId: String, data: [String: Any]?) {
    lock.withLock {
      print("[Presence] handleJoinRoomOk for room: \(roomId)")
      rooms[roomId]?.isConnected = true
      rooms[roomId]?.error = nil
      
      if let sessions = data?["sessions"] as? [String: Any] {
        print("[Presence] join-room-ok has \(sessions.count) sessions")
        setPresencePeers(roomId: roomId, sessions: sessions)
      } else {
        print("[Presence] join-room-ok has no sessions data")
      }
      
      // Send any pending presence
      if let userPresence = presence[roomId]?.result?.user {
        print("[Presence] Sending pending user presence: \(userPresence)")
        trySetPresence(roomId: roomId, data: userPresence)
      }
      
      notifyPresenceSubs(roomId: roomId)
    }
  }
  
  /// Handles a refresh-presence message from the server.
  public func handleRefreshPresence(roomId: String, sessions: [String: Any]) {
    lock.withLock {
      print("[Presence] handleRefreshPresence for room: \(roomId), sessions count: \(sessions.count)")
      for (sessionId, sessionData) in sessions {
        print("[Presence]   Session \(sessionId): \(sessionData)")
      }
      setPresencePeers(roomId: roomId, sessions: sessions)
      notifyPresenceSubs(roomId: roomId)
    }
  }
  
  /// Handles a patch-presence message from the server.
  public func handlePatchPresence(roomId: String, edits: [[Any]]) {
    lock.withLock {
      print("[Presence] handlePatchPresence for room: \(roomId), edits count: \(edits.count)")
      for edit in edits {
        print("[Presence]   Edit: \(edit)")
      }
      patchPresencePeers(roomId: roomId, edits: edits)
      notifyPresenceSubs(roomId: roomId)
    }
  }
  
  /// Handles a server-broadcast message from the server.
  public func handleServerBroadcast(roomId: String, topic: String, data: [String: Any], peerId: String) {
    lock.withLock {
      print("[Presence] handleServerBroadcast for room: \(roomId), topic: \(topic), peerId: \(peerId)")
      let handlers = broadcastSubs[roomId]?[topic] ?? []
      let message = TopicMessage(topic: topic, data: data, peerId: peerId)
      
      print("[Presence] Broadcasting to \(handlers.count) handlers")
      for handler in handlers {
        handler.callback(message)
      }
    }
  }
  
  /// Handles a room error from the server.
  public func handleRoomError(roomId: String, error: String) {
    lock.withLock {
      print("[Presence] handleRoomError for room: \(roomId), error: \(error)")
      rooms[roomId]?.error = error
      notifyPresenceSubs(roomId: roomId)
    }
  }
  
  // MARK: - Reconnection
  
  /// Called when reconnecting to resend room joins.
  public func resendRoomJoins() {
    lock.withLock {
      for (roomId, room) in rooms {
        if room.isConnected {
          rooms[roomId]?.isConnected = false
        }
        let userPresence = presence[roomId]?.result?.user
        tryJoinRoom(roomId: roomId, data: userPresence)
      }
      
      // Handle rooms that were pending leave
      for roomId in roomsPendingLeave {
        tryLeaveRoom(roomId: roomId)
      }
      roomsPendingLeave.removeAll()
    }
  }
  
  // MARK: - Private Helpers
  
  private func tryJoinRoom(roomId: String, data: [String: Any]?) {
    var message: [String: Any] = [
      "op": "join-room",
      "room-id": roomId
    ]
    if let data = data {
      message["data"] = data
    }
    sendMessage?(UUID().uuidString, message)
    roomsPendingLeave.remove(roomId)
  }
  
  private func tryLeaveRoom(roomId: String) {
    sendMessage?(UUID().uuidString, [
      "op": "leave-room",
      "room-id": roomId
    ])
  }
  
  private func trySetPresence(roomId: String, data: [String: Any]) {
    sendMessage?(UUID().uuidString, [
      "op": "set-presence",
      "room-id": roomId,
      "data": data
    ])
  }
  
  private func setPresencePeers(roomId: String, sessions: [String: Any]) {
    var peers: [String: [String: Any]] = [:]
    
    print("[Presence] setPresencePeers for room: \(roomId), my sessionId: \(sessionId ?? "nil")")
    
    for (sessionId, value) in sessions {
      // Skip our own session
      if sessionId == self.sessionId {
        print("[Presence]   Skipping own session: \(sessionId)")
        continue
      }
      
      if let sessionData = value as? [String: Any],
         let data = sessionData["data"] as? [String: Any] {
        peers[sessionId] = data
        print("[Presence]   Added peer \(sessionId) with data: \(data)")
      } else {
        print("[Presence]   Could not parse session data for \(sessionId): \(value)")
      }
    }
    
    print("[Presence] Total peers after setPresencePeers: \(peers.count)")
    
    if presence[roomId]?.result == nil {
      presence[roomId]?.result = PresenceResult(user: [:], peers: peers)
    } else {
      presence[roomId]?.result?.peers = peers
    }
  }
  
  private func patchPresencePeers(roomId: String, edits: [[Any]]) {
    guard var peers = presence[roomId]?.result?.peers else { return }
    
    for edit in edits {
      guard edit.count >= 2,
            let path = edit[0] as? [Any],
            let op = edit[1] as? String else { continue }
      
      let value = edit.count > 2 ? edit[2] : nil
      
      // Apply the edit based on operation
      switch op {
      case "+", "r":
        // Insert or replace
        if let sessionId = path.first as? String {
          if sessionId == self.sessionId { continue }
          
          if path.count == 1, let data = value as? [String: Any] {
            peers[sessionId] = data["data"] as? [String: Any] ?? [:]
          } else if path.count > 1, var sessionData = peers[sessionId] {
            // Deep path update
            var current: Any = sessionData
            for i in 1..<path.count - 1 {
              if let key = path[i] as? String,
                 let dict = current as? [String: Any] {
                current = dict[key] ?? [:]
              }
            }
            if let lastKey = path.last as? String,
               var dict = current as? [String: Any] {
              dict[lastKey] = value
              sessionData[path[1] as? String ?? ""] = dict
              peers[sessionId] = sessionData
            }
          }
        }
      case "-":
        // Delete
        if let sessionId = path.first as? String {
          if path.count == 1 {
            peers.removeValue(forKey: sessionId)
          }
        }
      default:
        break
      }
    }
    
    presence[roomId]?.result?.peers = peers
  }
  
  private func notifyPresenceSubs(roomId: String) {
    guard let handlers = presence[roomId]?.handlers else {
      print("[Presence] notifyPresenceSubs: no handlers for room \(roomId)")
      return
    }
    print("[Presence] notifyPresenceSubs for room \(roomId), notifying \(handlers.count) handlers")
    for handler in handlers {
      notifyPresenceSub(roomId: roomId, handler: handler)
    }
  }
  
  private func notifyPresenceSub(roomId: String, handler: PresenceHandler) {
    guard let slice = getPresence(roomId: roomId, keys: handler.keys) else {
      print("[Presence] notifyPresenceSub: could not get presence slice for room \(roomId)")
      return
    }
    
    // Check if changed
    if let prev = handler.previousSlice, !hasPresenceChanged(slice, prev) {
      print("[Presence] notifyPresenceSub: presence unchanged for room \(roomId), skipping callback")
      return
    }
    
    print("[Presence] notifyPresenceSub: calling callback for room \(roomId), peers: \(slice.peers.count), user: \(slice.user)")
    handler.previousSlice = slice
    handler.callback(slice)
  }
  
  private func buildPresenceSlice(
    result: PresenceResult,
    keys: [String]?,
    sessionId: String?
  ) -> PresenceSlice {
    var filteredPeers = result.peers
    
    // Remove our own session from peers
    if let sid = sessionId {
      filteredPeers.removeValue(forKey: sid)
    }
    
    // Filter by keys if specified
    if let keys = keys {
      filteredPeers = filteredPeers.filter { keys.contains($0.key) }
    }
    
    return PresenceSlice(
      user: result.user,
      peers: filteredPeers,
      isLoading: false,
      error: nil
    )
  }
  
  private func hasPresenceChanged(_ a: PresenceSlice, _ b: PresenceSlice) -> Bool {
    // Simple comparison - could be optimized
    return a.user.description != b.user.description ||
           a.peers.description != b.peers.description ||
           a.isLoading != b.isLoading ||
           a.error != b.error
  }
}

// MARK: - Supporting Types

/// State for a room
private struct RoomState {
  var isConnected: Bool = false
  var error: String?
}

/// State for presence in a room
private struct PresenceState {
  var result: PresenceResult?
  var handlers: [PresenceHandler] = []
}

/// Presence result containing user and peers
private struct PresenceResult {
  var user: [String: Any]
  var peers: [String: [String: Any]]
}

/// Handler for presence subscriptions
private class PresenceHandler {
  let id = UUID()
  let roomId: String
  let keys: [String]?
  let callback: (PresenceSlice) -> Void
  var previousSlice: PresenceSlice?
  
  init(roomId: String, keys: [String]?, callback: @escaping (PresenceSlice) -> Void) {
    self.roomId = roomId
    self.keys = keys
    self.callback = callback
  }
}

/// Handler for broadcast subscriptions
private struct BroadcastHandler {
  let id = UUID()
  let callback: (TopicMessage) -> Void
}

// MARK: - Public Types

/// A slice of presence data
public struct PresenceSlice: @unchecked Sendable {
  /// Your own presence data
  public let user: [String: Any]
  
  /// Other users' presence data, keyed by session ID
  public let peers: [String: [String: Any]]
  
  /// Whether we're still connecting to the room
  public let isLoading: Bool
  
  /// Error message if room join failed
  public let error: String?
  
  public init(user: [String: Any], peers: [String: [String: Any]], isLoading: Bool, error: String?) {
    self.user = user
    self.peers = peers
    self.isLoading = isLoading
    self.error = error
  }
}

/// A message received on a topic
public struct TopicMessage: @unchecked Sendable {
  /// The topic name
  public let topic: String
  
  /// The message data
  public let data: [String: Any]
  
  /// The session ID of the sender
  public let peerId: String
}

// Make PresenceSlice description work
extension PresenceSlice: CustomStringConvertible {
  public var description: String {
    "PresenceSlice(user: \(user), peers: \(peers.count) peers, loading: \(isLoading))"
  }
}

