import Foundation
import Combine

/// Logger for WebSocketConnection
private let logger = CompatibilityLogger(subsystem: "com.instantdb.sdk", category: "WebSocket")

/// WebSocket connection manager for InstantDB
public final class WebSocketConnection: NSObject {
  private let url: URL
  private var webSocketTask: URLSessionWebSocketTask?
  private let urlSessionConfiguration: URLSessionConfiguration
  private lazy var urlSession: URLSession = {
    URLSession(configuration: urlSessionConfiguration, delegate: self, delegateQueue: nil)
  }()
  private var isActive = false
  
  /// Current connection state
  @Published public private(set) var state: ConnectionState = .disconnected
  
  /// Whether the device is currently online (has network connectivity).
  ///
  /// ## Why This Exists
  /// The TypeScript SDK tracks `_isOnline` to:
  /// - Skip reconnection attempts when offline (saves resources)
  /// - Queue mutations without timeouts when offline
  /// - Immediately attempt reconnection when back online
  ///
  /// ## TypeScript Reference
  /// See `instant/client/packages/core/src/Reactor.js` lines 353-377
  @Published public private(set) var isOnline: Bool = true
  
  /// Message handler callback
  public var onMessage: ((ServerMessage) -> Void)?
  
  /// Error handler callback
  public var onError: ((InstantError) -> Void)?
  
  /// Connection opened callback
  public var onOpen: (() -> Void)?
  
  /// Connection closed callback
  public var onClose: (() -> Void)?
  
  /// Called when network status changes (online/offline).
  ///
  /// ## Why This Exists
  /// Allows InstantClient to react to network changes, such as:
  /// - Flushing pending mutations when coming back online
  /// - Updating UI to show offline status
  public var onNetworkStatusChange: ((Bool) -> Void)?
  
  private let jsonEncoder: JSONEncoder
  private let jsonDecoder: JSONDecoder

  // MARK: - Reconnection Properties
  
  /// Whether automatic reconnection is enabled
  public var autoReconnect = true
  
  /// Current reconnection delay in seconds
  private var reconnectDelaySeconds: TimeInterval = 0
  
  /// Maximum reconnection delay in seconds
  private let maxReconnectDelaySeconds: TimeInterval = 10
  
  /// Reconnection delay increment in seconds
  private let reconnectDelayIncrement: TimeInterval = 1
  
  /// Active reconnection task
  private var reconnectTask: Task<Void, Never>?
  
  /// Whether the connection was explicitly shut down (don't auto-reconnect)
  private var isShutdown = false
  
  /// Closure to remove network listener on deinit
  private var removeNetworkListener: (@Sendable () -> Void)?
  
  /// The network monitor client for detecting online/offline status.
  ///
  /// ## Dependency Injection
  /// This can be overridden for testing using `NetworkMonitorClient.mock()`.
  /// By default, uses the live implementation.
  private let networkMonitor: NetworkMonitorClient
  
  /// Initialize WebSocket connection
  /// - Parameters:
  ///   - appID: InstantDB application ID
  ///   - baseURL: Base WebSocket URL (default: production)
  ///   - networkMonitor: Network monitor client (default: live implementation)
  public init(
    appID: String,
    baseURL: String = "wss://api.instantdb.com",
    networkMonitor: NetworkMonitorClient = .live
  ) {
    guard let url = URL(string: "\(baseURL)/runtime/session?app_id=\(appID)") else {
      fatalError("Invalid WebSocket URL")
    }
    
    self.url = url
    self.networkMonitor = networkMonitor
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 300
    self.urlSessionConfiguration = configuration
    
    self.jsonEncoder = JSONEncoder()
    jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
    
    self.jsonDecoder = JSONDecoder()
    jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
    
    super.init()
    
    // Initialize network monitoring
    //
    // ## Why This Exists
    // The TypeScript SDK uses WindowNetworkListener to detect online/offline status.
    // When offline, we skip reconnection attempts to save resources.
    // When back online, we immediately attempt to reconnect.
    //
    // ## TypeScript Reference
    // See `instant/client/packages/core/src/Reactor.js` lines 353-377
    setupNetworkMonitoring()
  }
  
  // MARK: - Network Monitoring
  
  private func setupNetworkMonitoring() {
    // Get initial online status from the injected client
    isOnline = networkMonitor.isOnline()
    
    // Listen for network status changes using the injected client
    removeNetworkListener = networkMonitor.listen { [weak self] newIsOnline in
      guard let self = self else { return }
      
      // Only handle state changes (TypeScript: if (isOnline === this._isOnline) return)
      guard newIsOnline != self.isOnline else { return }
      
      logger.info("[network] online = \(newIsOnline)")
      
      DispatchQueue.main.async {
        self.isOnline = newIsOnline
        self.onNetworkStatusChange?(newIsOnline)
        
        if newIsOnline {
          // Coming back online - attempt to reconnect
          // TypeScript: this._startSocket()
          self.startSocketIfNeeded()
        } else {
          // Going offline.
          //
          // ## Parity with JS core
          // The TypeScript Reactor transitions to `STATUS.CLOSED` when offline and
          // closes the active socket. This prevents:
          // - sending mutations while "offline" (tests + deterministic behavior)
          // - scheduling reconnect backoff while offline
          // - leaving `isActive = true`, which would block reconnect when online again
          //
          // TypeScript: this._setStatus(STATUS.CLOSED)
          // TypeScript: close socket + skip reconnect scheduling while offline.
          self.reconnectTask?.cancel()
          self.reconnectTask = nil

          if self.isActive {
            self.disconnect(allowReconnect: true)
          } else {
            self.state = .disconnected
          }
        }
      }
    }
  }
  
  /// Starts the socket connection if not already connected and not shutdown.
  ///
  /// ## Why This Exists
  /// Called when coming back online to attempt reconnection.
  /// This is the Swift equivalent of TypeScript's `_startSocket()`.
  private func startSocketIfNeeded() {
    guard !isShutdown else {
      logger.info("[socket] shutdown, not starting")
      return
    }
    
    guard !isActive else {
      logger.info("[socket] already active, not starting")
      return
    }
    
    logger.info("[socket] starting after coming online")
    connect()
  }
  
  /// Connect to WebSocket server
  public func connect() {
    guard !isActive else { return }

    // Cancel any pending reconnection.
    //
    // ## Why This Exists
    // If callers explicitly call `connect()` while a reconnect task is pending
    // (or after a manual `shutdown()`), we want to treat that as intent to
    // resume normal connectivity once the network allows it.
    reconnectTask?.cancel()
    reconnectTask = nil
    isShutdown = false

    // Do not start a socket while offline. The network monitor will call
    // `startSocketIfNeeded()` when connectivity returns.
    guard isOnline else {
      logger.info("[socket] offline, not connecting")
      DispatchQueue.main.async { [weak self] in
        self?.state = .disconnected
      }
      return
    }

    DispatchQueue.main.async { [weak self] in
      self?.state = .connecting
    }
    isActive = true

    webSocketTask = urlSession.webSocketTask(with: url)
    webSocketTask?.resume()
  }
  
  /// Disconnect from WebSocket server
  /// - Parameter allowReconnect: If false, prevents automatic reconnection
  public func disconnect(allowReconnect: Bool = true) {
    guard isActive else { return }
    
    if !allowReconnect {
      isShutdown = true
    }
    
    // Cancel any pending reconnection
    reconnectTask?.cancel()
    reconnectTask = nil

    isActive = false
    webSocketTask?.cancel(with: .normalClosure, reason: nil)
    webSocketTask = nil
    state = .disconnected
    onClose?()
  }
  
  /// Permanently shut down the connection, preventing any reconnection attempts
  public func shutdown() {
    disconnect(allowReconnect: false)
  }
  
  // MARK: - Reconnection Logic
  
  /// Schedule a reconnection attempt with exponential backoff.
  ///
  /// ## Task Cancellation
  ///
  /// If called while a previous reconnection is pending, the previous task
  /// is cancelled first to prevent multiple simultaneous reconnection attempts.
  ///
  /// ## Offline Behavior
  /// When offline, we skip scheduling reconnection attempts entirely.
  /// The network monitor will trigger a reconnection when we come back online.
  ///
  /// ## TypeScript Reference
  /// See `instant/client/packages/core/src/Reactor.js` lines 1602-1624
  ///
  /// - SeeAlso: [PR #6 Feedback - Reconnection Task](https://github.com/tornikegomareli/instant-ios-sdk/blob/feat/local-first-triple-store/docs/PR6-FEEDBACK-ANALYSIS.md#comment-11-reconnection-task-not-cancelled)
  private func scheduleReconnect() {
    guard autoReconnect, !isShutdown else {
      logger.info("Reconnection disabled or connection shut down, not reconnecting")
      return
    }
    
    // Skip reconnection when offline - network monitor will trigger reconnect when online
    // TypeScript: if (!this._isOnline) { ... return; }
    guard isOnline else {
      logger.info("[socket][close] we are offline, no need to start socket")
      return
    }
    
    // Cancel any existing reconnection attempt to prevent multiple simultaneous reconnects
    // This fixes a bug where calling scheduleReconnect() twice rapidly would result in
    // two reconnection attempts happening in parallel.
    reconnectTask?.cancel()
    
    // Calculate delay with exponential backoff
    let delay = reconnectDelaySeconds
    reconnectDelaySeconds = min(
      reconnectDelaySeconds + reconnectDelayIncrement,
      maxReconnectDelaySeconds
    )
    
    logger.info("Scheduling reconnect in \(delay)s (next delay: \(self.reconnectDelaySeconds)s)")
    
    reconnectTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        guard !Task.isCancelled else { return }
        await self?.attemptReconnect()
      } catch {
        // Task was cancelled, that's fine
      }
    }
  }
  
  /// Attempt to reconnect
  @MainActor
  private func attemptReconnect() {
    guard !isShutdown else {
      logger.info("Connection shut down, aborting reconnect")
      return
    }
    
    logger.info("Attempting reconnect...")
    isActive = false
    connect()
  }
  
  /// Reset reconnection delay (called on successful connection)
  private func resetReconnectDelay() {
    reconnectDelaySeconds = 0
  }
  
  /// Send a client message to the server
  /// - Parameter message: The message to send
  public func send<T: ClientMessage>(_ message: T) throws {
    guard (state == .connected || state == .authenticated), let webSocketTask else {
      throw InstantError.notConnected
    }
    
    do {
      let data = try jsonEncoder.encode(message)
      guard let jsonString = String(data: data, encoding: .utf8) else {
        throw InstantError.encodingError(NSError(domain: "InstantDB", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert data to string"]))
      }
      
      webSocketTask.send(.string(jsonString)) { [weak self] error in
        guard let self else { return }
        guard let error else { return }
        guard self.isActive, !self.isShutdown else { return }
        self.handleError(InstantError.fromConnectionError(error))
      }
    } catch {
      throw InstantError.encodingError(error)
    }
  }
  
  /// Send raw dictionary message
  /// - Parameter dictionary: Message dictionary
  public func sendRaw(_ dictionary: [String: Any]) throws {
    guard (state == .connected || state == .authenticated), let webSocketTask else {
      throw InstantError.notConnected
    }
    
    do {
      let data = try JSONSerialization.data(withJSONObject: dictionary)
      guard let jsonString = String(data: data, encoding: .utf8) else {
        throw InstantError.encodingError(NSError(domain: "InstantDB", code: -1))
      }
      
      webSocketTask.send(.string(jsonString)) { [weak self] error in
        guard let self else { return }
        guard let error else { return }
        guard self.isActive, !self.isShutdown else { return }
        self.handleError(InstantError.fromConnectionError(error))
      }
    } catch {
      throw InstantError.encodingError(error)
    }
  }
  
  private func receiveMessage(for task: URLSessionWebSocketTask) {
    guard isActive else { return }

    task.receive { [weak self] result in
      guard let self = self else { return }

      // Ignore messages from stale tasks (e.g., a previous socket that was closed
      // while a new one is already in-flight). Without this guard, delayed delegate
      // callbacks from an older task can:
      // - flip `isActive` back to false
      // - set `state = .disconnected`
      // - break init/init-ok ordering and prevent authentication
      guard self.webSocketTask === task else { return }
      guard self.isActive, !self.isShutdown else { return }

      switch result {
      case .success(let message):
        self.handleWebSocketMessage(message)
        self.receiveMessage(for: task)

      case .failure(let error):
        guard self.isActive, !self.isShutdown else { return }
        let instantError = InstantError.fromConnectionError(error)
        self.handleError(instantError)

        // Don't call disconnect() as it would prevent reconnection.
        // Instead, mark as inactive and clean up.
        self.isActive = false
        task.cancel(with: .abnormalClosure, reason: nil)
        self.webSocketTask = nil

        DispatchQueue.main.async { [weak self] in
          self?.state = .disconnected
          self?.onClose?()

          // Schedule reconnection
          self?.scheduleReconnect()
        }
      }
    }
  }
  
  private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
    switch message {
    case .string(let text):
      parseMessage(text)
      
    case .data(let data):
      if let text = String(data: data, encoding: .utf8) {
        parseMessage(text)
      }
      
    @unknown default:
      break
    }
  }
  
  private func parseMessage(_ text: String) {
    guard let data = text.data(using: .utf8) else {
      handleError(.invalidMessage)
      return
    }

    do {
      let message = try jsonDecoder.decode(ServerMessage.self, from: data)
      let isInitOk = message.op == "init-ok"

      if isInitOk {
        // Reset reconnection delay on successful authentication
        resetReconnectDelay()
      }

      // Deliver messages on the main queue to match the expectations of higher layers
      // (InstantClient is @MainActor). For init-ok, we must transition to `.authenticated`
      // before delivering the message so that the client can flush pending mutations.
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }

        if isInitOk {
          self.state = .authenticated
        }

        self.onMessage?(message)
      }
    } catch {
      handleError(.decodingError(error))
    }
  }
  
  private func handleError(_ error: InstantError) {
    guard isActive, !isShutdown else { return }

    // Log the error for debugging
    logger.error("Error: \(error.localizedDescription)")
    
    // Log SSL/TLS errors with helpful guidance
    if error.isSSLTrustFailure {
      logger.error("\(InstantError.sslTrustFailureConsoleMessage)")
    }
    
    DispatchQueue.main.async { [weak self] in
      self?.state = .error(error)
    }
    onError?(error)
  }
  
  deinit {
    removeNetworkListener?()
    disconnect()
  }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketConnection: URLSessionWebSocketDelegate {
  public func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol protocol: String?
  ) {
    guard self.webSocketTask === webSocketTask else {
      logger.info("[socket] Ignoring didOpen for stale task")
      return
    }

    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      guard self.webSocketTask === webSocketTask else { return }
      self.state = .connected
      self.onOpen?()
    }

    receiveMessage(for: webSocketTask)
  }

  public func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      guard self.webSocketTask === webSocketTask else { return }
      
      self.isActive = false
      self.webSocketTask = nil
      self.state = .disconnected
      self.onClose?()
      
      // Schedule reconnection unless it was a normal closure
      if closeCode != .normalClosure {
        self.scheduleReconnect()
      }
    }
  }
}
