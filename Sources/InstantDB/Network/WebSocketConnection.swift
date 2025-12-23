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
  
  /// Message handler callback
  public var onMessage: ((ServerMessage) -> Void)?
  
  /// Error handler callback
  public var onError: ((InstantError) -> Void)?
  
  /// Connection opened callback
  public var onOpen: (() -> Void)?
  
  /// Connection closed callback
  public var onClose: (() -> Void)?
  
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
  
  /// Initialize WebSocket connection
  /// - Parameters:
  ///   - appID: InstantDB application ID
  ///   - baseURL: Base WebSocket URL (default: production)
  public init(
    appID: String,
    baseURL: String = "wss://api.instantdb.com"
  ) {
    guard let url = URL(string: "\(baseURL)/runtime/session?app_id=\(appID)") else {
      fatalError("Invalid WebSocket URL")
    }
    
    self.url = url
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 300
    self.urlSessionConfiguration = configuration
    
    self.jsonEncoder = JSONEncoder()
    jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
    
    self.jsonDecoder = JSONDecoder()
    jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
    
    super.init()
  }
  
  /// Connect to WebSocket server
  public func connect() {
    guard !isActive else { return }
    
    // Cancel any pending reconnection
    reconnectTask?.cancel()
    reconnectTask = nil
    isShutdown = false

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
  /// - SeeAlso: [PR #6 Feedback - Reconnection Task](https://github.com/tornikegomareli/instant-ios-sdk/blob/feat/local-first-triple-store/docs/PR6-FEEDBACK-ANALYSIS.md#comment-11-reconnection-task-not-cancelled)
  private func scheduleReconnect() {
    guard autoReconnect, !isShutdown else {
      logger.info("Reconnection disabled or connection shut down, not reconnecting")
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
        
        await MainActor.run {
          self?.attemptReconnect()
        }
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
    guard state == .connected || state == .authenticated else {
      throw InstantError.notConnected
    }
    
    do {
      let data = try jsonEncoder.encode(message)
      guard let jsonString = String(data: data, encoding: .utf8) else {
        throw InstantError.encodingError(NSError(domain: "InstantDB", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert data to string"]))
      }
      
      webSocketTask?.send(.string(jsonString)) { [weak self] error in
        if let error = error {
          self?.handleError(InstantError.fromConnectionError(error))
        }
      }
    } catch {
      throw InstantError.encodingError(error)
    }
  }
  
  /// Send raw dictionary message
  /// - Parameter dictionary: Message dictionary
  public func sendRaw(_ dictionary: [String: Any]) throws {
    guard state == .connected || state == .authenticated else {
      throw InstantError.notConnected
    }
    
    do {
      let data = try JSONSerialization.data(withJSONObject: dictionary)
      guard let jsonString = String(data: data, encoding: .utf8) else {
        throw InstantError.encodingError(NSError(domain: "InstantDB", code: -1))
      }
      
      webSocketTask?.send(.string(jsonString)) { [weak self] error in
        if let error = error {
          self?.handleError(InstantError.fromConnectionError(error))
        }
      }
    } catch {
      throw InstantError.encodingError(error)
    }
  }
  
  private func receiveMessage() {
    guard isActive else { return }
    
    webSocketTask?.receive { [weak self] result in
      guard let self = self else { return }
      
      switch result {
      case .success(let message):
        self.handleWebSocketMessage(message)
        self.receiveMessage()
        
      case .failure(let error):
        let instantError = InstantError.fromConnectionError(error)
        self.handleError(instantError)
        
        // Don't call disconnect() as it would prevent reconnection
        // Instead, mark as inactive and clean up
        self.isActive = false
        self.webSocketTask?.cancel(with: .abnormalClosure, reason: nil)
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
      onMessage?(message)

      if message.op == "init-ok" {
        // Reset reconnection delay on successful authentication
        resetReconnectDelay()
        
        DispatchQueue.main.async { [weak self] in
          self?.state = .authenticated
        }
      }
    } catch {
      handleError(.decodingError(error))
    }
  }
  
  private func handleError(_ error: InstantError) {
    // Log the error for debugging
    logger.error("Error: \(error.localizedDescription ?? "unknown")")
    
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
    DispatchQueue.main.async { [weak self] in
      self?.state = .connected
      self?.onOpen?()
    }

    receiveMessage()
  }

  public func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      
      self.isActive = false
      self.state = .disconnected
      self.onClose?()
      
      // Schedule reconnection unless it was a normal closure
      if closeCode != .normalClosure {
        self.scheduleReconnect()
      }
    }
  }
}
