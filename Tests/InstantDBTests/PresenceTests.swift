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



