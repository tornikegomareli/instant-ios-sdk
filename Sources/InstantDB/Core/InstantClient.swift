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
    
    setupConnection()
    setupMessageHandlers()
    
    Task {
      await authManager.restoreAuth()
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
    }
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

    // Process datalog-result into InstaQL format
    let instaqlData = InstaQLProcessor.process(result: resultArray, attributes: attributes)

    // Extract page-info if available
    let pageInfo = resultArray.first?["data"] as? [String: Any]
    let pageInfoData = pageInfo?["page-info"] as? [String: Any]

    Task { @MainActor in
      self.queryManager.handleQueryResult(
        eventId: message.clientEventId,
        result: instaqlData,
        pageInfo: pageInfoData
      )
    }

    print("[InstantDB] ✓ Query result delivered")
  }
  
  private func handleAddQueryExists(_ message: ServerMessage) {
    print("[InstantDB] Query already exists, delivering current data")

    // Debug: log the full message data
    if let jsonData = try? JSONSerialization.data(withJSONObject: message.data.mapValues { $0.value }, options: .prettyPrinted),
       let jsonString = String(data: jsonData, encoding: .utf8) {
      print("[InstantDB] DEBUG add-query-exists message data:")
      print(jsonString)
    }

    // Parse result array
    guard let resultArray = message.data["result"]?.value as? [[String: Any]] else {
      print("[InstantDB] Add-query-exists missing result array")
      print("[InstantDB] Available keys: \(message.data.keys)")
      return
    }

    // Process datalog-result into InstaQL format
    let instaqlData = InstaQLProcessor.process(result: resultArray, attributes: attributes)

    // Extract page-info if available
    let pageInfo = resultArray.first?["data"] as? [String: Any]
    let pageInfoData = pageInfo?["page-info"] as? [String: Any]

    Task { @MainActor in
      self.queryManager.handleQueryResult(
        eventId: message.clientEventId,
        result: instaqlData,
        pageInfo: pageInfoData
      )
    }

    print("[InstantDB] ✓ Query result delivered (existing query)")
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
    guard let computations = message.data["computations"]?.value as? [[String: Any]] else {
      print("[InstantDB] Refresh-ok missing computations")
      return
    }

    Task { @MainActor in
      self.queryManager.handleRefresh(computations: computations, attributes: self.attributes)
    }

    print("[InstantDB] ✓ Real-time update delivered (\(computations.count) queries)")
  }
  
  private func handleError(_ message: ServerMessage) {
    let errorMsg = message.data["message"]?.value as? String ?? "Unknown error"
    let hint = message.data["hint"]?.value as? [String: Any]

    print("[InstantDB] ✗ Server error: \(errorMsg)")
    if let hint = hint {
      print("[InstantDB]   Hint: \(hint)")
    }

    // If this error is for a query, notify the query manager
    if let eventId = message.clientEventId {
      let error = InstantError.serverError(errorMsg)
      Task { @MainActor in
        self.queryManager.handleQueryError(eventId: eventId, error: error)
      }
    }
  }
}

// MARK: - Query API

extension InstantClient {

  /// Subscribe to a query with a callback for results
  /// - Parameters:
  ///   - query: InstaQL query dictionary (e.g., ["goals": [:]])
  ///   - callback: Called when query results arrive or update
  /// - Returns: Unsubscribe function - call this to stop receiving updates
  ///
  /// Example:
  /// ```swift
  /// let unsubscribe = try db.subscribeQuery(["goals": [:]]) { result in
  ///   if let error = result.error {
  ///     print("Query failed: \(error)")
  ///   } else if let goals = result["goals"] {
  ///     print("Got \(goals.count) goals")
  ///   }
  /// }
  ///
  /// // Later, to unsubscribe:
  /// unsubscribe()
  /// ```
  @discardableResult
  public func subscribeQuery(
    _ query: [String: Any],
    callback: @escaping QueryCallback
  ) throws -> (() -> Void) {
    guard connectionState == .authenticated else {
      throw InstantError.notAuthenticated
    }

    let unsubscribe = queryManager.subscribe(query: query, callback: callback)

    // Get the subscription to send to server
    let hash = hashQuery(query)
    guard let subscription = queryManager.getSubscription(hash: hash) else {
      throw InstantError.invalidQuery
    }

    let message = AddQueryMessage(
      clientEventId: subscription.eventId,
      query: query
    )

    try connection.send(message)

    return unsubscribe
  }

  private func hashQuery(_ query: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: query),
          let string = String(data: data, encoding: .utf8) else {
      return UUID().uuidString
    }
    return string.hash.description
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
