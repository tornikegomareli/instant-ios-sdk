import Foundation
import Combine

/// WebSocket connection manager for InstantDB
public final class WebSocketConnection: NSObject {
  
  private let url: URL
  private var webSocketTask: URLSessionWebSocketTask?
  private let urlSession: URLSession
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
    self.urlSession = URLSession(configuration: configuration)
    
    self.jsonEncoder = JSONEncoder()
    jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
    
    self.jsonDecoder = JSONDecoder()
    jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
    
    super.init()
  }
  
  /// Connect to WebSocket server
  public func connect() {
    guard !isActive else { return }

    DispatchQueue.main.async { [weak self] in
      self?.state = .connecting
    }
    isActive = true

    webSocketTask = urlSession.webSocketTask(with: url)
    webSocketTask?.resume()

    DispatchQueue.main.async { [weak self] in
      self?.state = .connected
      self?.onOpen?()
    }

    receiveMessage()
  }
  
  /// Disconnect from WebSocket server
  public func disconnect() {
    guard isActive else { return }

    isActive = false
    webSocketTask?.cancel(with: .normalClosure, reason: nil)
    webSocketTask = nil
    DispatchQueue.main.async { [weak self] in
      self?.state = .disconnected
    }
    onClose?()
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
          self?.handleError(.connectionFailed(error))
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
          self?.handleError(.connectionFailed(error))
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
        self.handleError(.connectionFailed(error))
        self.disconnect()
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
        DispatchQueue.main.async { [weak self] in
          self?.state = .authenticated
        }
      }
    } catch {
      handleError(.decodingError(error))
    }
  }
  
  private func handleError(_ error: InstantError) {
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
  }

  public func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    DispatchQueue.main.async { [weak self] in
      self?.state = .disconnected
      self?.onClose?()
    }
  }
}
