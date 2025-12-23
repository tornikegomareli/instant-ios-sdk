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
  private let queryManager: QueryManager

  /// Offline persistence (query cache + pending mutations)
  private let localStorage: LocalStorage?

  /// Tracks mutations that have been sent but not yet acknowledged by the server.
  ///
  /// ## Why This Exists
  /// When reconnecting, we flush persisted pending mutations back to the server.
  /// Without tracking in-flight event IDs we can accidentally send the same
  /// mutation multiple times during rapid reconnects.
  private var inFlightMutationEventIds: Set<String> = []
  
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
    baseURL: String = "wss://api.instantdb.com",
    enableLocalPersistence: Bool = true
  ) {
    self.appID = appID
    self.baseURL = baseURL
    self.connection = WebSocketConnection(appID: appID, baseURL: baseURL)

    if enableLocalPersistence {
      self.localStorage = try? LocalStorage(appId: appID)
    } else {
      self.localStorage = nil
    }
    
    let httpBaseURL = baseURL
      .replacingOccurrences(of: "wss://", with: "https://")
      .replacingOccurrences(of: "ws://", with: "http://")
    self.authManager = AuthManager(appID: appID, baseURL: httpBaseURL)

    self.queryManager = QueryManager(localStorage: self.localStorage)
    
    // Initialize presence manager and wire up message sending
    self.presence = PresenceManager()
    setupPresenceManager()
    
    setupConnection()
    setupMessageHandlers()

    Task { @MainActor in
      await self.loadPersistedSchemaIfAvailable()
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
          InstantLog.warning("[InstantDB] Unknown presence op: \(op)")
        }
      } catch {
        InstantLog.warning("[InstantDB] Failed to send presence message: \(error)")
      }
    }
  }
  
  private func setupConnection() {
    connection.$state
      .sink { [weak self] state in
        guard let self else { return }
        self.connectionState = state

        switch state {
        case .disconnected, .error:
          self.inFlightMutationEventIds.removeAll()
        case .connecting, .connected, .authenticated:
          break
        }
      }
      .store(in: &cancellables)

    connection.onMessage = { [weak self] message in
      self?.handleServerMessage(message)
    }

    connection.onError = { error in
      InstantLog.warning("[InstantDB] Error: \(error.localizedDescription)")
    }

    connection.onOpen = { [weak self] in
      Task { @MainActor in
        guard let self = self else { return }
        await self.authManager.restoreAuth()
        self.sendInitMessage()
        // Resend room joins on reconnect
        self.presence.resendRoomJoins()
      }
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
    
    messageHandlers["client-broadcast-ok"] = { _ in
      // Acknowledgment that a client broadcast was sent successfully
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
      InstantLog.warning("[InstantDB] Failed to send init message: \(error)")
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
      InstantLog.debug("[InstantDB] → Sent remove-query")
    } catch {
      InstantLog.warning("[InstantDB] Failed to send remove-query: \(error)")
    }
  }
  
  private func handleServerMessage(_ message: ServerMessage) {
    InstantLog.debug("[InstantDB] ← Received: \(message.op)")
    
    if let handler = messageHandlers[message.op] {
      handler(message)
    } else {
      InstantLog.warning("[InstantDB] Unhandled message type: \(message.op)")
    }
  }
  
  private func handleInitOk(_ message: ServerMessage) {
    guard let sessionId = message.data["session-id"]?.value as? String else {
      InstantLog.warning("[InstantDB] Init-ok missing session-id")
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

          if let localStorage {
            do {
              try await localStorage.saveAttrs(attrs)
            } catch {
              InstantLog.warning("[InstantDB] Failed to persist attributes for offline mode: \(error)")
            }
          }
        } catch {
          InstantLog.warning("[InstantDB] Failed to decode attributes: \(error)")
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
          InstantLog.warning("[InstantDB] Failed to decode auth info: \(error)")
        }
      }
      
      InstantLog.info("[InstantDB] ✓ Connected! Session: \(sessionId)")
      InstantLog.info("[InstantDB] ✓ Loaded \(self.attributes.count) attributes")
      
      if let auth = self.authInfo {
        InstantLog.info("[InstantDB] ✓ Authenticated as: \(auth.user?.email ?? "guest")")
      }
      
      // Resend all active queries after reconnection
      // This ensures data is refreshed after connection recovery
      self.resendActiveQueries()

      // Flush queued mutations after reconnect.
      // We intentionally do this after resending queries so that refresh updates
      // caused by these mutations can be delivered to active subscriptions.
      await self.flushPendingMutations()
    }
  }
  
  /// Resend all active queries to the server
  /// Called after reconnection to refresh data
  private func resendActiveQueries() {
    let activeQueries = queryManager.getActiveQueries()
    
    guard !activeQueries.isEmpty else {
      InstantLog.debug("[InstantDB] No active queries to resend")
      return
    }
    
    InstantLog.debug("[InstantDB] ↻ Resending \(activeQueries.count) active queries after reconnection...")
    
    for (eventId, query) in activeQueries {
      let message = AddQueryMessage(
        clientEventId: eventId,
        query: query
      )
      
      do {
        try connection.send(message)
        if let namespace = query.keys.first {
          InstantLog.debug("[InstantDB]   → Resent query for '\(namespace)'")
        }
      } catch {
        InstantLog.warning("[InstantDB]   ✗ Failed to resend query: \(error)")
      }
    }
    
    InstantLog.debug("[InstantDB] ✓ All active queries resent")
  }
  
  private func handleAddQueryOk(_ message: ServerMessage) {
    if let resultValue = message.data["result"]?.value,
         let jsonData = try? JSONSerialization.data(withJSONObject: resultValue, options: .prettyPrinted),
         let jsonString = String(data: jsonData, encoding: .utf8) {
        InstantLog.debug("[InstantDB] DEBUG add-query-ok full result:")
        InstantLog.debug(jsonString)
      }

    if let processedTxValue = message.data["processed-tx-id"]?.value,
       let processedTxId = parseInt64(processedTxValue) {
      Task { @MainActor in
        await self.persistAndCleanupProcessedTxId(processedTxId)
      }
    }
    
    // Parse result array
    guard let resultArray = message.data["result"]?.value as? [[String: Any]] else {
      InstantLog.warning("[InstantDB] Add-query-ok missing result array")
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

    InstantLog.debug("[InstantDB] ✓ Query result delivered")
  }
  
  private func handleAddQueryExists(_ message: ServerMessage) {
    InstantLog.debug("[InstantDB] Query already exists, delivering cached data")

    // The server sends add-query-exists when a query with the same hash already exists.
    // This happens when we try to subscribe to the same query twice.
    // The message contains the query ("q") but NOT the result data.
    // We need to look up the existing subscription and deliver its cached result.
    
    guard let queryDict = message.data["q"]?.value as? [String: Any] else {
      InstantLog.warning("[InstantDB] Add-query-exists missing query ('q')")
      InstantLog.debug("[InstantDB] Available keys: \(message.data.keys)")
      return
    }
    
    Task { @MainActor in
      // Find the existing subscription by query hash and deliver its cached result
      self.queryManager.handleQueryExists(
        eventId: message.clientEventId,
        query: queryDict
      )
    }

    InstantLog.debug("[InstantDB] ✓ Cached query result delivered")
  }
  
  private func handleRemoveQueryOk(_ message: ServerMessage) {
    InstantLog.debug("[InstantDB] ✓ Query removed from server")
  }

  private func handleTransactOk(_ message: ServerMessage) {
    guard let txIdValue = message.data["tx-id"]?.value,
          let txId = parseInt64(txIdValue) else {
      InstantLog.warning("[InstantDB] Transact-ok missing tx-id")
      return
    }

    guard let eventId = message.clientEventId else {
      InstantLog.warning("[InstantDB] Transact-ok missing client-event-id")
      return
    }

    inFlightMutationEventIds.remove(eventId)

    if let localStorage {
      Task { @MainActor in
        do {
          try await localStorage.markPendingMutationConfirmed(eventId: eventId, txId: txId)
        } catch {
          InstantLog.warning("[InstantDB] Failed to persist transact-ok for \(eventId): \(error)")
        }
      }
    }

    InstantLog.debug("[InstantDB] ✓ Transaction confirmed: \(txId)")
  }
  
  private func handleRefreshOk(_ message: ServerMessage) {
    InstantLog.debug("[InstantDB] refresh-ok received, data keys: \(message.data.keys)")
    
    guard let computations = message.data["computations"]?.value as? [[String: Any]] else {
      InstantLog.warning("[InstantDB] Refresh-ok missing computations")
      // Debug: print all available data
      for (key, value) in message.data {
        InstantLog.debug("[InstantDB]   \(key): \(type(of: value.value))")
      }
      return
    }

    var refreshedAttributes: [Attribute]?
    if let attrsData = message.data["attrs"]?.value {
      do {
        let data = try JSONSerialization.data(withJSONObject: attrsData)
        refreshedAttributes = try JSONDecoder().decode([Attribute].self, from: data)
      } catch {
        InstantLog.warning("[InstantDB] Failed to decode attributes from refresh: \(error)")
      }
    }

    let processedTxId: Int64? = {
      guard let value = message.data["processed-tx-id"]?.value else { return nil }
      return parseInt64(value)
    }()

    InstantLog.debug("[InstantDB] refresh-ok has \(computations.count) computations")
    for (index, computation) in computations.enumerated() {
      InstantLog.debug("[InstantDB]   computation[\(index)] keys: \(computation.keys)")
      if let query = computation["instaql-query"] as? [String: Any] {
        InstantLog.debug("[InstantDB]   computation[\(index)] query namespaces: \(query.keys)")
      }
    }

    Task { @MainActor in
      if let refreshedAttributes {
        self.attributes = refreshedAttributes
        InstantLog.debug("[InstantDB] ✓ Updated \(refreshedAttributes.count) attributes from refresh")

        if let localStorage {
          do {
            try await localStorage.saveAttrs(refreshedAttributes)
          } catch {
            InstantLog.warning("[InstantDB] Failed to persist refreshed attributes: \(error)")
          }
        }
      }

      if let processedTxId {
        await self.persistAndCleanupProcessedTxId(processedTxId)
      }

      self.queryManager.handleRefresh(
        computations: computations,
        attributes: refreshedAttributes ?? self.attributes
      )
    }

    InstantLog.debug("[InstantDB] ✓ Real-time update delivered (\(computations.count) queries)")
  }
  
  private func handleError(_ message: ServerMessage) {
    let errorMsg = message.data["message"]?.value as? String ?? "Unknown error"
    let hint = message.data["hint"]?.value as? [String: Any]

    InstantLog.error("[InstantDB] ✗ Server error: \(errorMsg)")
    if let hint = hint {
      InstantLog.error("[InstantDB] ℹ Hint: \(hint)")
    }
    InstantLog.error("[InstantDB] ⚠ Learn more: https://www.instantdb.com/docs")

    let error = InstantError.serverError(errorMsg, hint: hint)

    if let eventId = message.clientEventId {
      Task { @MainActor in
        self.inFlightMutationEventIds.remove(eventId)

        if let localStorage {
          do {
            try await localStorage.markPendingMutationErrored(eventId: eventId, error: errorMsg)
          } catch {
            InstantLog.warning("[InstantDB] Failed to persist pending mutation error for \(eventId): \(error)")
          }
        }

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
      InstantLog.warning("[InstantDB] join-room-ok missing room-id")
      return
    }
    
    // Note: TypeScript doesn't process sessions in join-room-ok.
    // It just sets room connected and flushes queued data.
    // Sessions come via refresh-presence messages.
    presence.handleJoinRoomOk(roomId: roomId, data: nil)
    InstantLog.debug("[InstantDB] ✓ Joined room: \(roomId)")
  }
  
  private func handleRefreshPresence(_ message: ServerMessage) {
    // TypeScript: Reactor.js line 764-769
    // Key mapping: RefreshPresencePayload.sessions maps to server's "data" key
    // via CodingKeys, preventing the "sessions" vs "data" bug
    InstantLog.debug("[InstantDB] handleRefreshPresence - raw data keys: \(message.data.keys)")
    
    guard let roomId = message.data["room-id"]?.value as? String else {
      // This can happen when server sends a global refresh before room is joined
      InstantLog.debug("[InstantDB] refresh-presence has no room-id, ignoring (global refresh)")
      return
    }
    
    // IMPORTANT: Server sends "data", not "sessions"
    // See RefreshPresencePayload.CodingKeys where sessions = "data"
    guard let sessions = message.data["data"]?.value as? [String: Any] else {
      InstantLog.warning("[InstantDB] refresh-presence for room \(roomId) missing data")
      return
    }
    
    InstantLog.debug("[InstantDB] refresh-presence for room \(roomId) with \(sessions.count) sessions")
    presence.handleRefreshPresence(roomId: roomId, sessions: sessions)
    InstantLog.debug("[InstantDB] ✓ Presence refreshed for room: \(roomId)")
  }
  
  private func handlePatchPresence(_ message: ServerMessage) {
    // TypeScript: Reactor.js line 757-762
    // Key mapping: PatchPresencePayload uses roomId = "room-id", edits = "edits"
    InstantLog.debug("[InstantDB] handlePatchPresence - raw data keys: \(message.data.keys)")
    
    guard let roomId = message.data["room-id"]?.value as? String else {
      InstantLog.warning("[InstantDB] patch-presence missing room-id")
      return
    }
    
    guard let edits = message.data["edits"]?.value as? [[Any]] else {
      InstantLog.warning("[InstantDB] patch-presence for room \(roomId) missing edits")
      return
    }
    
    InstantLog.debug("[InstantDB] patch-presence for room \(roomId) with \(edits.count) edits")
    presence.handlePatchPresence(roomId: roomId, edits: edits)
    InstantLog.debug("[InstantDB] ✓ Presence patched for room: \(roomId)")
  }
  
  private func handleServerBroadcast(_ message: ServerMessage) {
    // TypeScript: Reactor.js line 771-776, 2393-2402
    // The server sends: { "room-id", "topic", "data": { "peer-id", "data": <payload> } }
    // Note: peer-id is INSIDE the data object, not at the top level!
    InstantLog.debug("[InstantDB] handleServerBroadcast - raw data keys: \(message.data.keys)")
    
    guard let roomId = message.data["room-id"]?.value as? String,
          let topic = message.data["topic"]?.value as? String,
          let dataWrapper = message.data["data"]?.value as? [String: Any] else {
      InstantLog.warning("[InstantDB] server-broadcast missing room-id, topic, or data")
      return
    }
    
    // peer-id is inside the data wrapper, along with the actual payload
    // TypeScript: msg.data['peer-id'] and msg.data.data
    let peerId = dataWrapper["peer-id"] as? String ?? "unknown"
    let payload = dataWrapper["data"] as? [String: Any] ?? [:]
    
    InstantLog.debug("[InstantDB] server-broadcast for room \(roomId), topic: \(topic), peerId: \(peerId)")
    presence.handleServerBroadcast(roomId: roomId, topic: topic, data: payload, peerId: peerId)
    InstantLog.debug("[InstantDB] ✓ Broadcast received on topic: \(topic)")
  }
  
  private func handleRoomError(_ message: ServerMessage) {
    // TypeScript: Reactor.js line 800-804
    // Key mapping: JoinRoomErrorPayload uses roomId = "room-id"
    guard let roomId = message.data["room-id"]?.value as? String,
          let errorMsg = message.data["message"]?.value as? String else {
      InstantLog.warning("[InstantDB] room-error missing room-id or message")
      return
    }
    
    presence.handleRoomError(roomId: roomId, error: errorMsg)
    InstantLog.error("[InstantDB] ✗ Room error for \(roomId): \(errorMsg)")
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
    let wrappedCallback: QueryCallback = { result in
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

    if connectionState == .authenticated {
      try connection.send(message)
    } else {
      // Defer sending until we receive init-ok and become authenticated.
      //
      // ## Why This Exists
      // The server expects `init` to run before we send `add-query`. When a caller
      // subscribes early (cold start, app foreground, network flap), we still want to:
      // - Register the subscription locally (so cached results can be emitted immediately),
      // - Avoid sending an invalid message order over the wire,
      // - Let `resendActiveQueries()` send the query after init-ok.
      InstantLog.debug("[InstantDB] subscribe: deferring add-query until authenticated")
    }

    return SubscriptionToken(onCleanup: unsubscribe)
  }

  // MARK: - Query Once API

  /// Runs a query a single time and returns the first non-loading result.
  ///
  /// ## Why This Exists
  /// `queryOnce` is intended for "fetch on demand" UX (e.g. pull-to-refresh,
  /// background refresh, or imperative reads).
  ///
  /// ## Offline Semantics (Parity with JS Core)
  /// - Subscriptions (`subscribe` / `TypedQuery.values()`) may emit cached results
  ///   immediately for offline-friendly UX.
  /// - `queryOnce` fails when offline so callers do not accidentally treat stale
  ///   cached data as a successful fresh read.
  ///
  /// ## Last-Known Data
  /// When offline (or when a request fails), the thrown `QueryOnceError` may carry
  /// `lastKnownResult` (if available) so callers can render cached data in an error UI.
  ///
  /// - Parameters:
  ///   - query: The InstaQL query dictionary.
  ///   - timeout: Maximum time to wait for a server response.
  /// - Returns: A `QueryResult` containing the query data and page info.
  public func queryOnce(
    _ query: [String: Any],
    timeout: TimeInterval = 15.0
  ) async throws -> QueryResult {
    let hash = hashQuery(query)

    if isOfflineForQueryOnce {
      throw QueryOnceError.offline(
        queryHash: hash,
        lastKnownResult: loadCachedQueryResultData(hash: hash)
      )
    }

    if let existing = queryManager.getSubscription(hash: hash), !existing.currentResult.isLoading {
      return existing.currentResult
    }

    let isAuthenticated = await waitForAuthenticated(timeoutSeconds: min(timeout, 10.0))
    guard isAuthenticated else {
      if isOfflineForQueryOnce {
        throw QueryOnceError.offline(
          queryHash: hash,
          lastKnownResult: loadCachedQueryResultData(hash: hash)
        )
      }

      throw QueryOnceError.timedOut(
        queryHash: hash,
        seconds: timeout,
        lastKnownResult: loadCachedQueryResultData(hash: hash)
      )
    }

    return try await withCheckedThrowingContinuation { continuation in
      var didFinish = false
      var unsubscribe: (() -> Void)?

      let callback: QueryCallback = { result in
        guard !result.isLoading else { return }
        guard !didFinish else { return }
        didFinish = true

        unsubscribe?()
        unsubscribe = nil

        if let error = result.error {
          continuation.resume(
            throwing: QueryOnceError.requestFailed(
              queryHash: hash,
              message: String(describing: error),
              lastKnownResult: self.loadCachedQueryResultData(hash: hash)
            )
          )
          return
        }

        continuation.resume(returning: result)
      }

      unsubscribe = self.queryManager.subscribe(query: query, emitCachedResult: false, callback: callback)

      guard let subscription = self.queryManager.getSubscription(hash: hash) else {
        didFinish = true
        unsubscribe?()
        unsubscribe = nil
        continuation.resume(
          throwing: QueryOnceError.requestFailed(
            queryHash: hash,
            message: "Failed to create query subscription.",
            lastKnownResult: self.loadCachedQueryResultData(hash: hash)
          )
        )
        return
      }

      do {
        let message = AddQueryMessage(clientEventId: subscription.eventId, query: query)
        try self.connection.send(message)
      } catch {
        didFinish = true
        unsubscribe?()
        unsubscribe = nil
        continuation.resume(
          throwing: QueryOnceError.requestFailed(
            queryHash: hash,
            message: String(describing: error),
            lastKnownResult: self.loadCachedQueryResultData(hash: hash)
          )
        )
        return
      }

      Task { @MainActor in
        guard !didFinish else { return }
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        guard !didFinish else { return }
        didFinish = true

        unsubscribe?()
        unsubscribe = nil

        continuation.resume(
          throwing: QueryOnceError.timedOut(
            queryHash: hash,
            seconds: timeout,
            lastKnownResult: self.loadCachedQueryResultData(hash: hash)
          )
        )
      }
    }
  }

  /// Runs a typed query once and returns decoded entities.
  ///
  /// This is equivalent to calling `queryOnce(query.toQuery())` and decoding the result.
  public func queryOnce<T: InstantEntity>(
    _ query: TypedQuery<T>,
    timeout: TimeInterval = 15.0
  ) async throws -> TypedResult<T> {
    let instaqlQuery = query.toQuery()
    let namespace = query.namespace

    let result = try await queryOnce(instaqlQuery, timeout: timeout)
    let decoded = result.decode(T.self, from: namespace)
    let pageInfo = PageInfo(from: result.pageInfo, namespace: namespace)

    return .success(data: decoded, pageInfo: pageInfo)
  }

  /// Computes a canonical hash for query matching.
  ///
  /// This must match the hashing algorithm in QueryManager to ensure
  /// we can look up subscriptions by hash after creating them.
  private func hashQuery(_ query: [String: Any]) -> String {
    QueryHashing.hash(query)
  }

  private var isOfflineForQueryOnce: Bool {
    switch connectionState {
    case .disconnected:
      return true
    case .error:
      return true
    case .connecting, .connected, .authenticated:
      return false
    }
  }

  private func waitForAuthenticated(timeoutSeconds: TimeInterval) async -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
      if connectionState == .authenticated { return true }
      if isOfflineForQueryOnce { return false }
      try? await Task.sleep(nanoseconds: 100_000_000)
    }

    return connectionState == .authenticated
  }

  private func loadCachedQueryResultData(hash: String) -> Data? {
    guard let localStorage else { return nil }
    return try? localStorage.getCachedQueryResultSync(hash: hash)
  }

  // MARK: - Local-first / Offline Support

  private func loadPersistedSchemaIfAvailable() async {
    guard let localStorage else { return }
    guard attributes.isEmpty else { return }

    do {
      let cached = try await localStorage.loadAttrs()
      guard !cached.isEmpty else { return }
      attributes = cached
    } catch {
      InstantLog.warning("[InstantDB] Failed to load persisted schema attributes: \(error)")
    }
  }

  private func flushPendingMutations() async {
    guard connectionState == .authenticated else { return }
    guard let localStorage else { return }

    do {
      let mutations = try await localStorage.loadPendingMutations()

      for mutation in mutations where mutation.txId == nil && mutation.error == nil {
        let txSteps = mutation.txSteps.map { $0.map(\.value) }
        trySendPendingMutation(eventId: mutation.eventId, txSteps: txSteps)
      }
    } catch {
      InstantLog.warning("[InstantDB] Failed to load pending mutations for flush: \(error)")
    }
  }

  private func trySendPendingMutation(eventId: String, txSteps: [[Any]]) {
    guard connectionState == .authenticated else { return }
    guard !inFlightMutationEventIds.contains(eventId) else { return }

    do {
      let message = TransactMessage(clientEventId: eventId, txSteps: txSteps)
      try connection.send(message)
      inFlightMutationEventIds.insert(eventId)
    } catch {
      InstantLog.warning("[InstantDB] Failed to send queued mutation \(eventId): \(error)")
    }
  }

  private func persistAndCleanupProcessedTxId(_ processedTxId: Int64) async {
    guard let localStorage else { return }

    do {
      try await localStorage.setValue(processedTxId, forKey: "processedTxId")
      try await localStorage.cleanupProcessedMutations(processedTxId: processedTxId)
    } catch {
      InstantLog.warning("[InstantDB] Failed to persist processed-tx-id \(processedTxId): \(error)")
    }
  }

  private func parseInt64(_ value: Any) -> Int64? {
    if let int64 = value as? Int64 { return int64 }
    if let int = value as? Int { return Int64(int) }
    if let double = value as? Double { return Int64(double) }
    if let string = value as? String { return Int64(string) }
    return nil
  }
}

// MARK: - Transaction API

extension InstantClient {

  /// Merges attribute updates into the in-memory schema cache.
  ///
  /// ## Why This Exists
  /// Some transactions include schema repairs (e.g. adding a missing `reverse-identity`)
  /// by emitting an `add-attr` step that reuses an existing attribute ID.
  ///
  /// If we only ever append, we can end up with duplicate attribute IDs in memory.
  /// More importantly, we would keep using stale schema until the next server refresh.
  private func mergeAttributesById(_ incoming: [Attribute]) {
    guard !incoming.isEmpty else { return }

    var indexById: [String: Int] = [:]
    for (index, attr) in attributes.enumerated() {
      indexById[attr.id] = index
    }

    for attr in incoming {
      if let index = indexById[attr.id] {
        attributes[index] = attr
      } else {
        attributes.append(attr)
      }
    }
  }

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
    mergeAttributesById(newAttributes)

    if let localStorage, !newAttributes.isEmpty {
      Task { @MainActor in
        do {
          try await localStorage.saveAttrs(newAttributes)
        } catch {
          InstantLog.warning("[InstantDB] Failed to persist new attributes from transaction: \(error)")
        }
      }
    }

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

  // MARK: - Local-first Transaction API

  /// Applies a transaction locally-first and queues it for sending when online.
  ///
  /// ## Semantics
  /// This mirrors JS core Reactor behavior:
  /// - The mutation is persisted immediately.
  /// - If the client is not yet authenticated/online, the mutation is queued.
  /// - Once the WebSocket session is authenticated, queued mutations are flushed.
  ///
  /// - Returns: The client-event-id used to track this mutation on the wire.
  @discardableResult
  public func transactLocalFirst(_ chunks: [TransactionChunk]) async throws -> String {
    await loadPersistedSchemaIfAvailable()

    let (txSteps, newAttributes) = try TransactionTransformer.transform(chunks, attributes: attributes)

    if !newAttributes.isEmpty {
      mergeAttributesById(newAttributes)

      if let localStorage {
        do {
          try await localStorage.saveAttrs(newAttributes)
        } catch {
          InstantLog.warning("[InstantDB] Failed to persist new attributes for offline mode: \(error)")
        }
      }
    }

    return try await transactLocalFirst(txSteps)
  }

  @discardableResult
  public func transactLocalFirst(_ chunk: TransactionChunk) async throws -> String {
    try await transactLocalFirst([chunk])
  }

  @discardableResult
  public func transactLocalFirst(@TransactionBatchBuilder _ build: () -> [TransactionChunk]) async throws -> String {
    let chunks = build()
    return try await transactLocalFirst(chunks)
  }

  /// Persists a tx-steps transaction and attempts to send it if connected.
  ///
  /// This is the primitive used by `transactLocalFirst(_ chunks:)` after
  /// transforming high-level operations into wire-format steps.
  @discardableResult
  public func transactLocalFirst(_ txSteps: [[Any]]) async throws -> String {
    let eventId = UUID().uuidString

    guard let localStorage else {
      guard connectionState == .authenticated else {
        throw InstantError.notAuthenticated
      }

      let message = TransactMessage(clientEventId: eventId, txSteps: txSteps)
      try connection.send(message)
      return eventId
    }

    let order = try await localStorage.nextPendingMutationOrderIndex()
    let mutation = PendingMutation(eventId: eventId, txSteps: txSteps, createdAt: Date(), order: order)
    try await localStorage.savePendingMutation(mutation)

    trySendPendingMutation(eventId: eventId, txSteps: txSteps)

    return eventId
  }

  /// Send a transaction to the server
  /// - Parameter txSteps: Array of transaction operations
  public func transact(_ txSteps: [[Any]]) throws {
    guard connectionState == .authenticated else {
      throw InstantError.notAuthenticated
    }

    // Debug: log tx-steps being sent
    InstantLog.debug("[InstantDB] Sending transaction with \(txSteps.count) steps:")
    for (index, step) in txSteps.enumerated() {
      InstantLog.debug("[InstantDB]   Step \(index): \(step)")
    }

    let message = TransactMessage(
      clientEventId: UUID().uuidString,
      txSteps: txSteps
    )

    try connection.send(message)
  }
}
