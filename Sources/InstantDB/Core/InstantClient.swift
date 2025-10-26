import Foundation
import Combine

/// Main InstantDB client
@MainActor
public final class InstantClient: ObservableObject {
  private let appID: String
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
    print("[InstantDB] Query subscription confirmed")
  }
  
  private func handleAddQueryExists(_ message: ServerMessage) {
    print("[InstantDB] Query already exists")
  }
  
  private func handleTransactOk(_ message: ServerMessage) {
    guard let txId = message.data["tx-id"]?.value as? String else {
      print("[InstantDB] Transact-ok missing tx-id")
      return
    }
    
    print("[InstantDB] ✓ Transaction confirmed: \(txId)")
  }
  
  private func handleRefreshOk(_ message: ServerMessage) {
    print("[InstantDB] Data refreshed")
  }
  
  private func handleError(_ message: ServerMessage) {
    let errorMsg = message.data["message"]?.value as? String ?? "Unknown error"
    let hint = message.data["hint"]?.value as? [String: Any]
    
    print("[InstantDB] ✗ Server error: \(errorMsg)")
    if let hint = hint {
      print("[InstantDB]   Hint: \(hint)")
    }
  }
}

// MARK: - Query API

extension InstantClient {
  
  /// Subscribe to a query
  /// - Parameter query: InstaQL query dictionary
  public func subscribeQuery(_ query: [String: Any]) throws {
    guard connectionState == .authenticated else {
      throw InstantError.notAuthenticated
    }
    
    let message = AddQueryMessage(
      clientEventId: UUID().uuidString,
      query: query
    )
    
    try connection.send(message)
  }
}

// MARK: - Transaction API

extension InstantClient {
  
  /// Send a transaction to the server
  /// - Parameter txSteps: Array of transaction operations
  public func transact(_ txSteps: [[Any]]) throws {
    guard connectionState == .authenticated else {
      throw InstantError.notAuthenticated
    }
    
    let message = TransactMessage(
      clientEventId: UUID().uuidString,
      txSteps: txSteps
    )
    
    try connection.send(message)
  }
}
