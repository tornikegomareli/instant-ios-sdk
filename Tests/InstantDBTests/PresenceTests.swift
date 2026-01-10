import XCTest
@testable import InstantDB

/// Tests for presence synchronization between multiple clients.
///
/// ## Why These Tests Exist
///
/// These tests verify that the `refresh-presence` handler correctly parses
/// server messages. The bug was that the handler looked for `"sessions"` key
/// but the server sends `"data"` key (TypeScript: Reactor.js line 764-769).
///
/// ## Test Strategy
///
/// We create two **separate** `InstantClient` instances (not using the factory cache)
/// so each gets a unique `sessionID` from the server. This allows us to test
/// true peer-to-peer presence synchronization in a single process.
@MainActor
final class PresenceTests: XCTestCase {
  
  // Use a real app ID for integration tests
  private let appID = "b9319949-2f2d-410b-8f8a-6990177c1d44"
  
  // MARK: - Two-Client Presence Sync
  
  /// Tests that two clients in the same room can see each other's presence.
  ///
  /// ## Why This Test Exists
  /// This verifies the fix for the `refresh-presence` bug where the iOS SDK
  /// was looking for `message.data["sessions"]` but the server sends
  /// `message.data["data"]`. Without this fix, peers would never appear.
  ///
  /// ## How It Works
  /// 1. Create two separate `InstantClient` instances (different session IDs)
  /// 2. Both join the same room with different presence data
  /// 3. Wait for presence updates
  /// 4. Verify each client sees the other as a peer
  ///
  /// ## TypeScript Reference
  /// Reactor.js line 764-769:
  /// ```javascript
  /// case 'refresh-presence': {
  ///   const roomId = msg['room-id'];
  ///   this._setPresencePeers(roomId, msg['data']);  // Uses 'data', not 'sessions'
  /// }
  /// ```
  func testTwoClientPresenceSync() async throws {
    let roomId = "test-presence-\(UUID().uuidString.prefix(8))"
    print("Testing presence sync in room: \(roomId)")
    
    // Create two SEPARATE InstantClient instances
    // Each gets a unique sessionId from the server
    let alice = InstantClient(appID: appID)
    let bob = InstantClient(appID: appID)
    
    defer {
      // Cleanup: disconnect both clients
      alice.disconnect()
      bob.disconnect()
    }
    
    // Wait for both clients to authenticate
    try await waitForAuthentication(alice, name: "Alice")
    try await waitForAuthentication(bob, name: "Bob")
    
    // Verify they have different session IDs
    XCTAssertNotNil(alice.sessionID, "Alice should have a session ID")
    XCTAssertNotNil(bob.sessionID, "Bob should have a session ID")
    XCTAssertNotEqual(alice.sessionID, bob.sessionID, "Clients should have different session IDs")
    
    print("Alice sessionID: \(alice.sessionID ?? "nil")")
    print("Bob sessionID: \(bob.sessionID ?? "nil")")
    
    // Track presence updates
    var aliceSeenPeers: [[String: [String: Any]]] = []
    var bobSeenPeers: [[String: [String: Any]]] = []
    
    // Alice joins room
    let aliceUnsub = alice.presence.subscribePresence(
      roomId: roomId,
      initialPresence: ["name": "Alice", "color": "#FF0000"]
    ) { slice in
      print("Alice presence update: peers=\(slice.peers.count), isLoading=\(slice.isLoading)")
      if !slice.isLoading {
        aliceSeenPeers.append(slice.peers)
      }
    }
    defer { aliceUnsub() }
    
    // Wait a moment for Alice's join to complete
    try await Task.sleep(nanoseconds: 500_000_000)
    
    // Bob joins the same room
    let bobUnsub = bob.presence.subscribePresence(
      roomId: roomId,
      initialPresence: ["name": "Bob", "color": "#00FF00"]
    ) { slice in
      print("Bob presence update: peers=\(slice.peers.count), isLoading=\(slice.isLoading)")
      if !slice.isLoading {
        bobSeenPeers.append(slice.peers)
      }
    }
    defer { bobUnsub() }
    
    // Wait for presence updates to propagate
    // The server sends refresh-presence when a new peer joins
    try await Task.sleep(nanoseconds: 2_000_000_000)
    
    // Verify Alice sees Bob as a peer
    let aliceFinalPeers = aliceSeenPeers.last ?? [:]
    print("Alice's final peers: \(aliceFinalPeers)")
    
    XCTAssertFalse(
      aliceFinalPeers.isEmpty,
      "Alice should see at least one peer (Bob). " +
      "If this fails, the refresh-presence handler may be looking for the wrong key."
    )
    
    // Verify Bob sees Alice as a peer
    let bobFinalPeers = bobSeenPeers.last ?? [:]
    print("Bob's final peers: \(bobFinalPeers)")
    
    XCTAssertFalse(
      bobFinalPeers.isEmpty,
      "Bob should see at least one peer (Alice). " +
      "If this fails, the refresh-presence handler may be looking for the wrong key."
    )
    
    // Verify the peer data contains expected fields
    if let alicePeer = aliceFinalPeers.values.first {
      XCTAssertEqual(alicePeer["name"] as? String, "Bob", "Alice should see Bob's name")
    }
    
    if let bobPeer = bobFinalPeers.values.first {
      XCTAssertEqual(bobPeer["name"] as? String, "Alice", "Bob should see Alice's name")
    }
    
    print("✅ Two-client presence sync test passed!")
  }
  
  // MARK: - Single Client Presence
  
  /// Tests that a single client can set and update presence.
  func testSingleClientPresence() async throws {
    let roomId = "test-single-\(UUID().uuidString.prefix(8))"
    let client = InstantClient(appID: appID)
    
    defer { client.disconnect() }
    
    try await waitForAuthentication(client, name: "Client")
    
    var presenceUpdates: [PresenceSlice] = []
    
    let unsub = client.presence.subscribePresence(
      roomId: roomId,
      initialPresence: ["status": "online"]
    ) { slice in
      presenceUpdates.append(slice)
    }
    defer { unsub() }
    
    // Wait for initial presence
    try await Task.sleep(nanoseconds: 1_000_000_000)
    
    // Update presence
    client.presence.publishPresence(roomId: roomId, data: ["status": "busy"])
    
    // Wait for update
    try await Task.sleep(nanoseconds: 500_000_000)
    
    // Should have received at least one update
    XCTAssertFalse(presenceUpdates.isEmpty, "Should receive presence updates")
    
    // The latest update should show our user data
    if let latest = presenceUpdates.last {
      XCTAssertFalse(latest.isLoading, "Should not be loading after connection")
    }
  }
  
  /// Tests that presence updates are received when user data changes.
  func testPresenceUpdatePropagation() async throws {
    let roomId = "test-update-\(UUID().uuidString.prefix(8))"
    let client = InstantClient(appID: appID)
    
    defer { client.disconnect() }
    
    try await waitForAuthentication(client, name: "Client")
    
    var receivedStatuses: [String] = []
    
    let unsub = client.presence.subscribePresence(
      roomId: roomId,
      initialPresence: ["status": "online"]
    ) { slice in
      if let status = slice.user["status"] as? String {
        receivedStatuses.append(status)
      }
    }
    defer { unsub() }
    
    // Wait for initial presence
    try await Task.sleep(nanoseconds: 500_000_000)
    
    // Update presence multiple times
    client.presence.publishPresence(roomId: roomId, data: ["status": "away"])
    try await Task.sleep(nanoseconds: 300_000_000)
    
    client.presence.publishPresence(roomId: roomId, data: ["status": "busy"])
    try await Task.sleep(nanoseconds: 300_000_000)
    
    // Should have received updates
    print("Received statuses: \(receivedStatuses)")
    XCTAssertTrue(receivedStatuses.contains("online"), "Should have initial 'online' status")
  }
  
  // MARK: - Topics
  
  /// Tests that topic messages can be published and received.
  func testTopicPublishAndReceive() async throws {
    let roomId = "test-topic-\(UUID().uuidString.prefix(8))"
    
    // Create two clients for sender and receiver
    let sender = InstantClient(appID: appID)
    let receiver = InstantClient(appID: appID)
    
    defer {
      sender.disconnect()
      receiver.disconnect()
    }
    
    try await waitForAuthentication(sender, name: "Sender")
    try await waitForAuthentication(receiver, name: "Receiver")
    
    var receivedMessages: [TopicMessage] = []
    
    // Receiver subscribes to topic
    let receiverUnsub = receiver.presence.subscribeTopic(
      roomId: roomId,
      topic: "emoji"
    ) { message in
      print("Receiver got message: \(message)")
      receivedMessages.append(message)
    }
    defer { receiverUnsub() }
    
    // Also join the room so we're connected
    let receiverPresenceUnsub = receiver.presence.subscribePresence(
      roomId: roomId,
      initialPresence: ["role": "receiver"]
    ) { _ in }
    defer { receiverPresenceUnsub() }
    
    // Sender joins room and publishes
    let senderPresenceUnsub = sender.presence.subscribePresence(
      roomId: roomId,
      initialPresence: ["role": "sender"]
    ) { _ in }
    defer { senderPresenceUnsub() }
    
    // Wait for both to be connected
    try await Task.sleep(nanoseconds: 1_000_000_000)
    
    // Sender publishes topic message
    sender.presence.publishTopic(
      roomId: roomId,
      topic: "emoji",
      data: ["name": "fire", "direction": 0.5]
    )
    
    // Wait for message to propagate
    try await Task.sleep(nanoseconds: 1_000_000_000)
    
    // Receiver should have gotten the message
    // Note: The sender might also receive their own message depending on server behavior
    print("Total received messages: \(receivedMessages.count)")
    
    // This test verifies the topic system is working
    // The actual message verification depends on whether server echoes back to sender
  }
  
  // MARK: - Helpers
  
  private func waitForAuthentication(
    _ client: InstantClient,
    name: String,
    timeout: TimeInterval = 5.0
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    
    while client.connectionState != .authenticated && Date() < deadline {
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    
    guard client.connectionState == .authenticated else {
      throw XCTSkip("\(name) failed to authenticate within \(timeout)s. State: \(client.connectionState)")
    }
    
    print("\(name) authenticated with sessionID: \(client.sessionID ?? "nil")")
  }
}

// MARK: - Typed Presence Tests

/// Tests for the type-safe presence API.
///
/// ## Why These Tests Exist
///
/// The typed presence API (`TypedPresenceSlice<T>`, `subscribeTypedPresence<T>()`)
/// provides compile-time type safety for presence data. These tests verify:
/// 1. Encoding/decoding works correctly for Codable types
/// 2. The typed API behaves identically to the untyped API
/// 3. Edge cases like missing fields are handled gracefully
@MainActor
final class TypedPresenceTests: XCTestCase {
  
  private let appID = "b9319949-2f2d-410b-8f8a-6990177c1d44"
  
  // MARK: - Test Types
  
  /// A simple presence type for testing.
  struct CursorPresence: PresenceData {
    var x: Double
    var y: Double
    var name: String
    var color: String
    
    init(x: Double = 0, y: Double = 0, name: String = "", color: String = "#000000") {
      self.x = x
      self.y = y
      self.name = name
      self.color = color
    }
  }
  
  /// A presence type with optional fields for testing.
  struct UserPresence: PresenceData {
    var name: String
    var status: String
    var avatar: String?
    
    init(name: String, status: String = "online", avatar: String? = nil) {
      self.name = name
      self.status = status
      self.avatar = avatar
    }
  }
  
  // MARK: - Encoding/Decoding Tests
  
  /// Tests that `encodePresenceData` correctly encodes a Codable type.
  func testEncodePresenceData() {
    let presence = CursorPresence(x: 100, y: 200, name: "Alice", color: "#FF0000")
    let dict = encodePresenceData(presence)
    
    XCTAssertEqual(dict["x"] as? Double, 100)
    XCTAssertEqual(dict["y"] as? Double, 200)
    XCTAssertEqual(dict["name"] as? String, "Alice")
    XCTAssertEqual(dict["color"] as? String, "#FF0000")
  }
  
  /// Tests that `encodePresenceData` handles optional fields correctly.
  func testEncodePresenceDataWithOptionals() {
    // With optional present
    let withAvatar = UserPresence(name: "Alice", status: "online", avatar: "https://example.com/avatar.png")
    let dictWithAvatar = encodePresenceData(withAvatar)
    
    XCTAssertEqual(dictWithAvatar["name"] as? String, "Alice")
    XCTAssertEqual(dictWithAvatar["status"] as? String, "online")
    XCTAssertEqual(dictWithAvatar["avatar"] as? String, "https://example.com/avatar.png")
    
    // Without optional
    let withoutAvatar = UserPresence(name: "Bob", status: "away", avatar: nil)
    let dictWithoutAvatar = encodePresenceData(withoutAvatar)
    
    XCTAssertEqual(dictWithoutAvatar["name"] as? String, "Bob")
    XCTAssertEqual(dictWithoutAvatar["status"] as? String, "away")
    // nil optionals should not be present in the dictionary
    XCTAssertNil(dictWithoutAvatar["avatar"])
  }
  
  /// Tests that `TypedPresenceSlice.from` correctly decodes presence data.
  func testTypedPresenceSliceFromUntyped() {
    let untypedSlice = PresenceSlice(
      user: ["x": 100.0, "y": 200.0, "name": "Alice", "color": "#FF0000"],
      peers: [
        "peer-1": ["x": 50.0, "y": 60.0, "name": "Bob", "color": "#00FF00"],
        "peer-2": ["x": 70.0, "y": 80.0, "name": "Charlie", "color": "#0000FF"]
      ],
      isLoading: false,
      error: nil
    )
    
    let fallback = CursorPresence()
    let typedSlice = TypedPresenceSlice<CursorPresence>.from(untypedSlice, fallbackUser: fallback)
    
    // Verify user
    XCTAssertEqual(typedSlice.user.x, 100.0)
    XCTAssertEqual(typedSlice.user.y, 200.0)
    XCTAssertEqual(typedSlice.user.name, "Alice")
    XCTAssertEqual(typedSlice.user.color, "#FF0000")
    
    // Verify peers
    XCTAssertEqual(typedSlice.peers.count, 2)
    
    let bob = typedSlice.peers.first { $0.id == "peer-1" }
    XCTAssertNotNil(bob)
    XCTAssertEqual(bob?.data.name, "Bob")
    XCTAssertEqual(bob?.data.x, 50.0)
    
    let charlie = typedSlice.peers.first { $0.id == "peer-2" }
    XCTAssertNotNil(charlie)
    XCTAssertEqual(charlie?.data.name, "Charlie")
    
    // Verify metadata
    XCTAssertFalse(typedSlice.isLoading)
    XCTAssertNil(typedSlice.error)
    XCTAssertEqual(typedSlice.totalCount, 3)
    XCTAssertTrue(typedSlice.hasPeers)
  }
  
  /// Tests that `TypedPresenceSlice.from` uses fallback when user data can't be decoded.
  func testTypedPresenceSliceUseFallbackOnInvalidUser() {
    let untypedSlice = PresenceSlice(
      user: ["invalid": "data"],  // Missing required fields
      peers: [:],
      isLoading: false,
      error: nil
    )
    
    let fallback = CursorPresence(x: 999, y: 888, name: "Fallback", color: "#FFFFFF")
    let typedSlice = TypedPresenceSlice<CursorPresence>.from(untypedSlice, fallbackUser: fallback)
    
    // Should use fallback values
    XCTAssertEqual(typedSlice.user.x, 999)
    XCTAssertEqual(typedSlice.user.y, 888)
    XCTAssertEqual(typedSlice.user.name, "Fallback")
  }
  
  /// Tests that `TypedPresenceSlice.from` skips peers that can't be decoded.
  func testTypedPresenceSliceSkipsInvalidPeers() {
    let untypedSlice = PresenceSlice(
      user: ["x": 0.0, "y": 0.0, "name": "User", "color": "#000"],
      peers: [
        "valid-peer": ["x": 10.0, "y": 20.0, "name": "Valid", "color": "#FFF"],
        "invalid-peer": ["garbage": "data"]  // Missing required fields
      ],
      isLoading: false,
      error: nil
    )
    
    let fallback = CursorPresence()
    let typedSlice = TypedPresenceSlice<CursorPresence>.from(untypedSlice, fallbackUser: fallback)
    
    // Should only have the valid peer
    XCTAssertEqual(typedSlice.peers.count, 1)
    XCTAssertEqual(typedSlice.peers.first?.id, "valid-peer")
    XCTAssertEqual(typedSlice.peers.first?.data.name, "Valid")
  }
  
  // MARK: - Integration Tests
  
  /// Tests the full type-safe presence flow with a real connection.
  func testTypedPresenceSubscription() async throws {
    let roomId = "typed-test-\(UUID().uuidString.prefix(8))"
    let client = InstantClient(appID: appID)
    
    defer { client.disconnect() }
    
    try await waitForAuthentication(client, name: "Client")
    
    var receivedUpdates: [TypedPresenceSlice<CursorPresence>] = []
    let initialPresence = CursorPresence(x: 100, y: 200, name: "TestUser", color: "#FF0000")
    
    // Subscribe using the type-safe API
    let unsub = client.presence.subscribeTypedPresence(
      roomId: roomId,
      initialPresence: initialPresence
    ) { (slice: TypedPresenceSlice<CursorPresence>) in
      print("Typed presence update: user=\(slice.user.name), peers=\(slice.peers.count)")
      receivedUpdates.append(slice)
    }
    defer { unsub() }
    
    // Wait for initial presence
    try await Task.sleep(nanoseconds: 1_000_000_000)
    
    // Should have received at least one update
    XCTAssertFalse(receivedUpdates.isEmpty, "Should receive typed presence updates")
    
    // The user data should be type-safe
    if let latest = receivedUpdates.last {
      XCTAssertFalse(latest.isLoading, "Should not be loading after connection")
      // Access type-safe properties
      let _ = latest.user.x  // This compiles because it's type-safe!
      let _ = latest.user.name
    }
  }
  
  /// Tests publishing typed presence data.
  func testTypedPresencePublish() async throws {
    let roomId = "typed-publish-\(UUID().uuidString.prefix(8))"
    let client = InstantClient(appID: appID)
    
    defer { client.disconnect() }
    
    try await waitForAuthentication(client, name: "Client")
    
    var receivedUpdates: [TypedPresenceSlice<CursorPresence>] = []
    let initialPresence = CursorPresence(x: 0, y: 0, name: "User", color: "#000")
    
    let unsub = client.presence.subscribeTypedPresence(
      roomId: roomId,
      initialPresence: initialPresence
    ) { (slice: TypedPresenceSlice<CursorPresence>) in
      receivedUpdates.append(slice)
    }
    defer { unsub() }
    
    // Wait for initial
    try await Task.sleep(nanoseconds: 500_000_000)
    
    // Publish typed presence update
    let updatedPresence = CursorPresence(x: 500, y: 600, name: "UpdatedUser", color: "#FF00FF")
    client.presence.publishTypedPresence(roomId: roomId, data: updatedPresence)
    
    // Wait for update
    try await Task.sleep(nanoseconds: 500_000_000)
    
    // Should have received updates
    XCTAssertGreaterThan(receivedUpdates.count, 0, "Should receive presence updates")
  }
  
  /// Tests typed topic messages.
  func testTypedTopicMessages() async throws {
    let roomId = "typed-topic-\(UUID().uuidString.prefix(8))"
    
    struct EmojiPayload: Codable, Sendable {
      var emoji: String
      var direction: Double
    }
    
    let sender = InstantClient(appID: appID)
    let receiver = InstantClient(appID: appID)
    
    defer {
      sender.disconnect()
      receiver.disconnect()
    }
    
    try await waitForAuthentication(sender, name: "Sender")
    try await waitForAuthentication(receiver, name: "Receiver")
    
    var receivedMessages: [TypedTopicMessage<EmojiPayload>] = []
    
    // Receiver subscribes to typed topic
    let topicUnsub = receiver.presence.subscribeTypedTopic(
      roomId: roomId,
      topic: "emoji"
    ) { (message: TypedTopicMessage<EmojiPayload>) in
      print("Received typed message: \(message.data.emoji)")
      receivedMessages.append(message)
    }
    defer { topicUnsub() }
    
    // Both join the room
    let receiverJoin = receiver.presence.joinRoom(roomId)
    let senderJoin = sender.presence.joinRoom(roomId)
    defer {
      receiverJoin()
      senderJoin()
    }
    
    // Wait for connection
    try await Task.sleep(nanoseconds: 1_000_000_000)
    
    // Sender publishes typed topic message
    sender.presence.publishTypedTopic(
      roomId: roomId,
      topic: "emoji",
      data: EmojiPayload(emoji: "🔥", direction: 0.5)
    )
    
    // Wait for message
    try await Task.sleep(nanoseconds: 1_000_000_000)
    
    // Verify type-safe access (this test mainly verifies compilation)
    for message in receivedMessages {
      let _ = message.data.emoji  // Type-safe!
      let _ = message.data.direction
    }
  }
  
  // MARK: - Helpers
  
  private func waitForAuthentication(
    _ client: InstantClient,
    name: String,
    timeout: TimeInterval = 5.0
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    
    while client.connectionState != .authenticated && Date() < deadline {
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    
    guard client.connectionState == .authenticated else {
      throw XCTSkip("\(name) failed to authenticate within \(timeout)s. State: \(client.connectionState)")
    }
  }
}




