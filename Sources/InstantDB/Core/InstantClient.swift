import Foundation
import Combine

/// Main InstantDB client
@MainActor
public final class InstantClient: ObservableObject {
  public let appID: String
  private let baseURL: String
  private let connection: WebSocketConnection
  private var cancellables = Set<AnyCancellable>()
  
  /// Current connection state
  @Published public private(set) var connectionState: ConnectionState = .disconnected
  
  /// Whether client is authenticated
  @Published public private(set) var isAuthenticated = false
  
  /// Current session ID
  @Published public private(set) var sessionID: String?
  
  /// App attributes (schema)
  @Published public private(set) var attributes: [Attribute] = []
  
  /// Current auth info
  @Published public private(set) var authInfo: AuthInfo?
  
  /// Auth manager
  public let authManager: AuthManager

  /// Query manager
  private let queryManager = QueryManager()
  
  /// Presence manager for real-time presence and topics
  public let presence: PresenceManager

  /// Transaction builder for constructing database mutations
  public let tx = TransactionBuilder()

  private var messageHandlers: [String: (ServerMessage) -> Void] = [:]
  
  /// Initialize InstantDB client
  /// - Parameters:
  ///   - appID: Your InstantDB application ID
  ///   - baseURL: Optional custom server URL (default: production)
  public init(
    appID: String,
    baseURL: String = "wss://api.instantdb.com"
  ) {
    self.appID = appID
    self.baseURL = baseURL
    self.connection = WebSocketConnection(appID: appID, baseURL: baseURL)
    
    let httpBaseURL = baseURL
      .replacingOccurrences(of: "wss://", with: "https://")
      .replacingOccurrences(of: "ws://", with: "http://")
    self.authManager = AuthManager(appID: appID, baseURL: httpBaseURL)
    
    // Initialize presence manager and wire up message sending
    self.presence = PresenceManager()
    setupPresenceManager()
    
    setupConnection()
    setupMessageHandlers()

    Task {
      await authManager.restoreAuth()
    }

    connection.connect()
  }
  
  private func setupPresenceManager() {
    // Wire up the presence manager's send callback to use typed messages
    presence.sendMessage = { [weak self] eventId, message in
      guard let self = self else { return }
      
      do {
        guard let op = message["op"] as? String else { return }
        
        switch op {
        case "join-room":
          let roomId = message["room-id"] as? String ?? ""
          let data = message["data"] as? [String: Any]
          let msg = JoinRoomMessage(clientEventId: eventId, roomId: roomId, data: data)
          try self.connection.send(msg)
          
        case "leave-room":
          let roomId = message["room-id"] as? String ?? ""
          let msg = LeaveRoomMessage(clientEventId: eventId, roomId: roomId)
          try self.connection.send(msg)
          
        case "set-presence":
          let roomId = message["room-id"] as? String ?? ""
          let data = message["data"] as? [String: Any] ?? [:]
          let msg = SetPresenceMessage(clientEventId: eventId, roomId: roomId, data: data)
          try self.connection.send(msg)
          
        case "client-broadcast":
          let roomId = message["room-id"] as? String ?? ""
          let topic = message["topic"] as? String ?? ""
          let data = message["data"] as? [String: Any] ?? [:]
          let msg = ClientBroadcastMessage(clientEventId: eventId, roomId: roomId, topic: topic, data: data)
          try self.connection.send(msg)
          
        default:
          print("[InstantDB] Unknown presence op: \(op)")
        }
      } catch {
        print("[InstantDB] Failed to send presence message: \(error)")
      }
    }
  }
  
  private func setupConnection() {
    connection.$state
      .sink { [weak self] state in
        self?.connectionState = state
      }
      .store(in: &cancellables)

    connection.onMessage = { [weak self] message in
      self?.handleServerMessage(message)
    }

    connection.onError = { [weak self] error in
      print("[InstantDB] Error: \(error.localizedDescription)")
    }

    connection.onOpen = { [weak self] in
      self?.sendInitMessage()
      // Resend room joins on reconnect
      self?.presence.resendRoomJoins()
    }

    // Set up query manager callback for removing queries
    queryManager.onRemoveQuery = { [weak self] query in
      self?.sendRemoveQuery(query)
    }
  }
  
  private func setupMessageHandlers() {
    messageHandlers["init-ok"] = { [weak self] message in
      self?.handleInitOk(message)
    }

    messageHandlers["add-query-ok"] = { [weak self] message in
      self?.handleAddQueryOk(message)
    }

    messageHandlers["add-query-exists"] = { [weak self] message in
      self?.handleAddQueryExists(message)
    }

    messageHandlers["remove-query-ok"] = { [weak self] message in
      self?.handleRemoveQueryOk(message)
    }

    messageHandlers["transact-ok"] = { [weak self] message in
      self?.handleTransactOk(message)
    }

    messageHandlers["refresh-ok"] = { [weak self] message in
      self?.handleRefreshOk(message)
    }

    messageHandlers["error"] = { [weak self] message in
      self?.handleError(message)
    }
    
    // Presence/Room message handlers
    messageHandlers["join-room-ok"] = { [weak self] message in
      self?.handleJoinRoomOk(message)
    }
    
    messageHandlers["refresh-presence"] = { [weak self] message in
      self?.handleRefreshPresence(message)
    }
    
    messageHandlers["patch-presence"] = { [weak self] message in
      self?.handlePatchPresence(message)
    }
    
    messageHandlers["server-broadcast"] = { [weak self] message in
      self?.handleServerBroadcast(message)
    }
    
    messageHandlers["room-error"] = { [weak self] message in
      self?.handleRoomError(message)
    }
    
    // Acknowledgment handlers (no action needed, just prevents "Unhandled" warnings)
    messageHandlers["set-presence-ok"] = { _ in
      // Acknowledgment that presence was set successfully
    }
    
    messageHandlers["leave-room-ok"] = { _ in
      // Acknowledgment that room was left successfully
    }
  }
  
  /// Connect to InstantDB server
  public func connect() {
    connection.connect()
  }
  
  /// Disconnect from InstantDB server
  public func disconnect() {
    connection.disconnect()
    isAuthenticated = false
    sessionID = nil
    attributes = []
    authInfo = nil
  }
  
  private func sendInitMessage() {
    let message = InitMessage(
      clientEventId: UUID().uuidString,
      appId: appID,
      refreshToken: authManager.refreshToken
    )

    do {
      try connection.send(message)
    } catch {
      print("[InstantDB] Failed to send init message: \(error)")
    }
  }

  private func sendRemoveQuery(_ query: [String: Any]) {
    guard connectionState == .authenticated else { return }

    let message = RemoveQueryMessage(
      clientEventId: UUID().uuidString,
      query: query
    )

    do {
      try connection.send(message)
      print("[InstantDB] → Sent remove-query")
    } catch {
      print("[InstantDB] Failed to send remove-query: \(error)")
    }
  }
  
  private func handleServerMessage(_ message: ServerMessage) {
    print("[InstantDB] ← Received: \(message.op)")
    
    if let handler = messageHandlers[message.op] {
      handler(message)
    } else {
      print("[InstantDB] Unhandled message type: \(message.op)")
    }
  }
  
  private func handleInitOk(_ message: ServerMessage) {
    guard let sessionId = message.data["session-id"]?.value as? String else {
      print("[InstantDB] Init-ok missing session-id")
      return
    }
    
    Task { @MainActor in
      self.sessionID = sessionId
      
      // Update presence manager with session ID
      self.presence.sessionId = sessionId
      
      if let attrsData = message.data["attrs"]?.value {
        do {
          let data = try JSONSerialization.data(withJSONObject: attrsData)
          let attrs = try JSONDecoder().decode([Attribute].self, from: data)
          self.attributes = attrs
        } catch {
          print("[InstantDB] Failed to decode attributes: \(error)")
        }
      }
      
      if let authData = message.data["auth"]?.value {
        do {
          let data = try JSONSerialization.data(withJSONObject: authData)
          let auth = try JSONDecoder().decode(AuthInfo.self, from: data)
          self.authInfo = auth
          self.isAuthenticated = auth.user != nil
          
          if let user = auth.user {
            try? self.authManager.saveAuth(user)
          }
        } catch {
          print("[InstantDB] Failed to decode auth info: \(error)")
        }
      }
      
      print("[InstantDB] ✓ Connected! Session: \(sessionId)")
      print("[InstantDB] ✓ Loaded \(self.attributes.count) attributes")
      
      if let auth = self.authInfo {
        print("[InstantDB] ✓ Authenticated as: \(auth.user?.email ?? "guest")")
      }
      
      // Resend all active queries after reconnection
      // This ensures data is refreshed after connection recovery
      self.resendActiveQueries()
    }
  }
  
  /// Resend all active queries to the server
  /// Called after reconnection to refresh data
  private func resendActiveQueries() {
    let activeQueries = queryManager.getActiveQueries()
    
    guard !activeQueries.isEmpty else {
      print("[InstantDB] No active queries to resend")
      return
    }
    
    print("[InstantDB] ↻ Resending \(activeQueries.count) active queries after reconnection...")
    
    for (eventId, query) in activeQueries {
      let message = AddQueryMessage(
        clientEventId: eventId,
        query: query
      )
      
      do {
        try connection.send(message)
        if let namespace = query.keys.first {
          print("[InstantDB]   → Resent query for '\(namespace)'")
        }
      } catch {
        print("[InstantDB]   ✗ Failed to resend query: \(error)")
      }
    }
    
    print("[InstantDB] ✓ All active queries resent")
  }
  
  private func handleAddQueryOk(_ message: ServerMessage) {
    if let resultValue = message.data["result"]?.value,
         let jsonData = try? JSONSerialization.data(withJSONObject: resultValue, options: .prettyPrinted),
         let jsonString = String(data: jsonData, encoding: .utf8) {
        print("[InstantDB] DEBUG add-query-ok full result:")
        print(jsonString)
      }
    
    // Parse result array
    guard let resultArray = message.data["result"]?.value as? [[String: Any]] else {
      print("[InstantDB] Add-query-ok missing result array")
      return
    }

    // Let QueryManager process the result with client-side sorting
    // (QueryManager has access to the subscription's query which contains the order)
    Task { @MainActor in
      self.queryManager.handleQueryResult(
        eventId: message.clientEventId,
        rawResult: resultArray,
        attributes: self.attributes
      )
    }

    print("[InstantDB] ✓ Query result delivered")
  }
  
  private func handleAddQueryExists(_ message: ServerMessage) {
    print("[InstantDB] Query already exists, delivering cached data")

    // The server sends add-query-exists when a query with the same hash already exists.
    // This happens when we try to subscribe to the same query twice.
    // The message contains the query ("q") but NOT the result data.
    // We need to look up the existing subscription and deliver its cached result.
    
    guard let queryDict = message.data["q"]?.value as? [String: Any] else {
      print("[InstantDB] Add-query-exists missing query ('q')")
      print("[InstantDB] Available keys: \(message.data.keys)")
      return
    }
    
    Task { @MainActor in
      // Find the existing subscription by query hash and deliver its cached result
      self.queryManager.handleQueryExists(
        eventId: message.clientEventId,
        query: queryDict
      )
    }

    print("[InstantDB] ✓ Cached query result delivered")
  }
  
  private func handleRemoveQueryOk(_ message: ServerMessage) {
    print("[InstantDB] ✓ Query removed from server")
  }

  private func handleTransactOk(_ message: ServerMessage) {
    guard let txId = message.data["tx-id"]?.value as? Int else {
      print("[InstantDB] Transact-ok missing tx-id")
      return
    }

    print("[InstantDB] ✓ Transaction confirmed: \(txId)")
  }
  
  private func handleRefreshOk(_ message: ServerMessage) {
    print("[InstantDB] refresh-ok received, data keys: \(message.data.keys)")
    
    guard let computations = message.data["computations"]?.value as? [[String: Any]] else {
      print("[InstantDB] Refresh-ok missing computations")
      // Debug: print all available data
      for (key, value) in message.data {
        print("[InstantDB]   \(key): \(type(of: value.value))")
      }
      return
    }

    var refreshedAttributes: [Attribute]?
    if let attrsData = message.data["attrs"]?.value {
      do {
        let data = try JSONSerialization.data(withJSONObject: attrsData)
        refreshedAttributes = try JSONDecoder().decode([Attribute].self, from: data)
      } catch {
        print("[InstantDB] Failed to decode attributes from refresh: \(error)")
      }
    }

    print("[InstantDB] refresh-ok has \(computations.count) computations")
    for (index, computation) in computations.enumerated() {
      print("[InstantDB]   computation[\(index)] keys: \(computation.keys)")
      if let query = computation["instaql-query"] as? [String: Any] {
        print("[InstantDB]   computation[\(index)] query namespaces: \(query.keys)")
      }
    }

    Task { @MainActor in
      if let refreshedAttributes {
        self.attributes = refreshedAttributes
        print("[InstantDB] ✓ Updated \(refreshedAttributes.count) attributes from refresh")
      }

      self.queryManager.handleRefresh(
        computations: computations,
        attributes: refreshedAttributes ?? self.attributes
      )
    }

    print("[InstantDB] ✓ Real-time update delivered (\(computations.count) queries)")
  }
  
  private func handleError(_ message: ServerMessage) {
    let errorMsg = message.data["message"]?.value as? String ?? "Unknown error"
    let hint = message.data["hint"]?.value as? [String: Any]

    print("[InstantDB] ✗ Server error: \(errorMsg)")
    if let hint = hint {
      print("[InstantDB] ℹ Hint: \(hint)")
    }
    print("[InstantDB] ⚠ Learn more: https://www.instantdb.com/docs")

    let error = InstantError.serverError(errorMsg, hint: hint)

    if let eventId = message.clientEventId {
      Task { @MainActor in
        self.queryManager.handleQueryError(eventId: eventId, error: error)
      }
    }
  }

  
  // MARK: - Presence Message Handlers
  //
  // These handlers use typed payloads from ServerMessagePayloads.swift.
  // The CodingKeys in each payload struct map server keys to Swift properties,
  // preventing bugs like the "sessions" vs "data" typo.
  //
  // TypeScript Reference: Reactor.js _handleReceive() method
  
  private func handleJoinRoomOk(_ message: ServerMessage) {
    // Use typed payload - CodingKeys ensure correct key mapping
    // TypeScript: Reactor.js line 778-793
    guard let roomId = message.data["room-id"]?.value as? String else {
      print("[InstantDB] join-room-ok missing room-id")
      return
    }
    
    // Note: TypeScript doesn't process sessions in join-room-ok.
    // It just sets room connected and flushes queued data.
    // Sessions come via refresh-presence messages.
    presence.handleJoinRoomOk(roomId: roomId, data: nil)
    print("[InstantDB] ✓ Joined room: \(roomId)")
  }
  
  private func handleRefreshPresence(_ message: ServerMessage) {
    // TypeScript: Reactor.js line 764-769
    // Key mapping: RefreshPresencePayload.sessions maps to server's "data" key
    // via CodingKeys, preventing the "sessions" vs "data" bug
    print("[InstantDB] handleRefreshPresence - raw data keys: \(message.data.keys)")
    
    guard let roomId = message.data["room-id"]?.value as? String else {
      // This can happen when server sends a global refresh before room is joined
      print("[InstantDB] refresh-presence has no room-id, ignoring (global refresh)")
      return
    }
    
    // IMPORTANT: Server sends "data", not "sessions"
    // See RefreshPresencePayload.CodingKeys where sessions = "data"
    guard let sessions = message.data["data"]?.value as? [String: Any] else {
      print("[InstantDB] refresh-presence for room \(roomId) missing data")
      return
    }
    
    print("[InstantDB] refresh-presence for room \(roomId) with \(sessions.count) sessions")
    presence.handleRefreshPresence(roomId: roomId, sessions: sessions)
    print("[InstantDB] ✓ Presence refreshed for room: \(roomId)")
  }
  
  private func handlePatchPresence(_ message: ServerMessage) {
    // TypeScript: Reactor.js line 757-762
    // Key mapping: PatchPresencePayload uses roomId = "room-id", edits = "edits"
    print("[InstantDB] handlePatchPresence - raw data keys: \(message.data.keys)")
    
    guard let roomId = message.data["room-id"]?.value as? String else {
      print("[InstantDB] patch-presence missing room-id")
      return
    }
    
    guard let edits = message.data["edits"]?.value as? [[Any]] else {
      print("[InstantDB] patch-presence for room \(roomId) missing edits")
      return
    }
    
    print("[InstantDB] patch-presence for room \(roomId) with \(edits.count) edits")
    presence.handlePatchPresence(roomId: roomId, edits: edits)
    print("[InstantDB] ✓ Presence patched for room: \(roomId)")
  }
  
  private func handleServerBroadcast(_ message: ServerMessage) {
    // TypeScript: Reactor.js line 771-776, 2393-2402
    // The server sends: { "room-id", "topic", "data": { "peer-id", "data": <payload> } }
    // Note: peer-id is INSIDE the data object, not at the top level!
    print("[InstantDB] handleServerBroadcast - raw data keys: \(message.data.keys)")
    
    guard let roomId = message.data["room-id"]?.value as? String,
          let topic = message.data["topic"]?.value as? String,
          let dataWrapper = message.data["data"]?.value as? [String: Any] else {
      print("[InstantDB] server-broadcast missing room-id, topic, or data")
      return
    }
    
    // peer-id is inside the data wrapper, along with the actual payload
    // TypeScript: msg.data['peer-id'] and msg.data.data
    let peerId = dataWrapper["peer-id"] as? String ?? "unknown"
    let payload = dataWrapper["data"] as? [String: Any] ?? [:]
    
    print("[InstantDB] server-broadcast for room \(roomId), topic: \(topic), peerId: \(peerId)")
    presence.handleServerBroadcast(roomId: roomId, topic: topic, data: payload, peerId: peerId)
    print("[InstantDB] ✓ Broadcast received on topic: \(topic)")
  }
  
  private func handleRoomError(_ message: ServerMessage) {
    // TypeScript: Reactor.js line 800-804
    // Key mapping: JoinRoomErrorPayload uses roomId = "room-id"
    guard let roomId = message.data["room-id"]?.value as? String,
          let errorMsg = message.data["message"]?.value as? String else {
      print("[InstantDB] room-error missing room-id or message")
      return
    }
    
    presence.handleRoomError(roomId: roomId, error: errorMsg)
    print("[InstantDB] ✗ Room error for \(roomId): \(errorMsg)")
  }
}

// MARK: - Type-Safe Query API

extension InstantClient {

  /// Create a type-safe query for an entity type
  /// - Parameter type: The InstantEntity type to query
  /// - Returns: A typed query builder
  ///
  /// Example:
  /// ```swift
  /// db.query(Goal.self)
  ///     .where { $0.difficulty > 5 }
  ///     .limit(10)
  /// ```
  public func query<T: InstantEntity>(_ type: T.Type) -> TypedQuery<T> {
    TypedQuery<T>(namespace: T.namespace, client: self)
  }

  /// Subscribe to a type-safe query
  /// - Parameters:
  ///   - query: Typed query instance
  ///   - callback: Called when query results arrive or update
  /// - Returns: Subscription token that auto-cleans on deinit
  ///
  /// Example:
  /// ```swift
  /// class GoalsViewModel {
  ///     private var subscriptions = Set<Subscription>()
  ///
  ///     func start() {
  ///         try? db.subscribe(db.query(Goal.self)) { result in
  ///             self.goals = result.data
  ///         }
  ///         .store(in: &subscriptions)
  ///     }
  /// }
  /// ```
  @discardableResult
  public func subscribe<T: InstantEntity>(
    _ query: TypedQuery<T>,
    callback: @escaping TypedQueryCallback<T>
  ) throws -> SubscriptionToken {
    let instaqlQuery = query.toQuery()
    let namespace = query.namespace

    // Wrap callback to decode results automatically
    let wrappedCallback: QueryCallback = { [weak self] result in
      guard let self = self else { return }

      if result.isLoading {
        callback(.loading)
        return
      }

      if let error = result.error {
        callback(.failure(error))
        return
      }

      // Decode data to type T
      let decoded = result.decode(T.self, from: namespace)

      // Parse pageInfo for this namespace
      let pageInfo = PageInfo(from: result.pageInfo, namespace: namespace)

      callback(.success(data: decoded, pageInfo: pageInfo))
    }

    let unsubscribe = queryManager.subscribe(query: instaqlQuery, callback: wrappedCallback)

    // Get the subscription to send to server
    // Use the same canonical hashing as QueryManager to ensure hash matches
    let hash = hashQuery(instaqlQuery)
    guard let subscription = queryManager.getSubscription(hash: hash) else {
      throw InstantError.invalidQuery
    }

    let message = AddQueryMessage(
      clientEventId: subscription.eventId,
      query: instaqlQuery
    )

    try connection.send(message)

    return SubscriptionToken(onCleanup: unsubscribe)
  }

  /// Computes a canonical hash for query matching.
  ///
  /// This must match the hashing algorithm in QueryManager to ensure
  /// we can look up subscriptions by hash after creating them.
  private func hashQuery(_ query: [String: Any]) -> String {
    let canonical = canonicalizeQuery(query)
    guard let data = try? JSONSerialization.data(withJSONObject: canonical, options: .sortedKeys),
          let string = String(data: data, encoding: .utf8) else {
      return UUID().uuidString
    }
    return string.hash.description
  }
  
  /// Recursively sorts dictionary keys to create a canonical representation.
  private func canonicalizeQuery(_ value: Any) -> Any {
    if let dict = value as? [String: Any] {
      var result: [String: Any] = [:]
      for key in dict.keys.sorted() {
        result[key] = canonicalizeQuery(dict[key]!)
      }
      return result
    } else if let array = value as? [Any] {
      return array.map { canonicalizeQuery($0) }
    } else {
      return value
    }
  }
}

// MARK: - Transaction API

extension InstantClient {

  /// Send a transaction to the server using transaction chunks
  /// - Parameter chunks: Transaction chunks built using the tx builder
  ///
  /// Example:
  /// ```swift
  /// try db.transact([
  ///   db.tx.goals[newId()].update(["title": "Get fit"]),
  ///   db.tx.todos[todoId].link(["goals": goalId])
  /// ])
  /// ```
  public func transact(_ chunks: [TransactionChunk]) throws {
    // Transform high-level operations into tx-steps format
    let (txSteps, newAttributes) = try TransactionTransformer.transform(chunks, attributes: attributes)

    // Add new attributes to local schema (optimistically)
    attributes.append(contentsOf: newAttributes)

    try transact(txSteps)
  }

  /// Send a transaction to the server using transaction chunks
  /// - Parameter chunk: A single transaction chunk
  public func transact(_ chunk: TransactionChunk) throws {
    try transact([chunk])
  }

  /// Execute transactions using result builder syntax
  ///
  /// Example:
  /// ```swift
  /// try db.transact {
  ///     Goal.create(title: "Get fit", difficulty: 5)
  ///     Todo.update(id: todoId, done: true)
  ///     Goal.delete(id: oldGoalId)
  /// }
  /// ```
  /// - Parameter build: Result builder closure that returns transaction chunks
  public func transact(@TransactionBatchBuilder _ build: () -> [TransactionChunk]) throws {
    let chunks = build()
    try transact(chunks)
  }

  /// Send a transaction to the server
  /// - Parameter txSteps: Array of transaction operations
  public func transact(_ txSteps: [[Any]]) throws {
    guard connectionState == .authenticated else {
      throw InstantError.notAuthenticated
    }

    // Debug: log tx-steps being sent
    print("[InstantDB] Sending transaction with \(txSteps.count) steps:")
    for (index, step) in txSteps.enumerated() {
      print("[InstantDB]   Step \(index): \(step)")
    }

    let message = TransactMessage(
      clientEventId: UUID().uuidString,
      txSteps: txSteps
    )

    try connection.send(message)
  }
}
