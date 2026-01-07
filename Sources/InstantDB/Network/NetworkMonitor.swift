import Foundation
import Network
import Combine

// MARK: - NetworkMonitor

// MARK: - NetworkMonitorClient

/// A client interface for network connectivity monitoring.
///
/// ## Why This Exists
/// Using a client protocol allows for:
/// - Dependency injection in tests
/// - Simulating offline/online states
/// - Controllable network conditions for debugging
///
/// ## Swift Dependencies Integration
/// This follows the pattern used by swift-dependencies for testable clients.
/// In production, use `NetworkMonitorClient.live`. In tests, use `.mock()` or
/// configure via dependency injection.
public struct NetworkMonitorClient: Sendable {
  /// Gets the current online status.
  public var isOnline: @Sendable () -> Bool
  
  /// Adds a listener for network status changes.
  /// Returns a closure to remove the listener.
  public var listen: @Sendable (@escaping @Sendable (Bool) -> Void) -> (@Sendable () -> Void)
  
  /// Publisher for online status (for Combine/SwiftUI integration).
  public var isOnlinePublisher: @Sendable () -> AnyPublisher<Bool, Never>
  
  public init(
    isOnline: @escaping @Sendable () -> Bool,
    listen: @escaping @Sendable (@escaping @Sendable (Bool) -> Void) -> (@Sendable () -> Void),
    isOnlinePublisher: @escaping @Sendable () -> AnyPublisher<Bool, Never>
  ) {
    self.isOnline = isOnline
    self.listen = listen
    self.isOnlinePublisher = isOnlinePublisher
  }
}

// MARK: - Live Implementation

extension NetworkMonitorClient {
  /// The live implementation using Apple's Network framework.
  ///
  /// ## TypeScript Reference
  /// See `instant/client/packages/core/src/WindowNetworkListener.js`
  public static let live: NetworkMonitorClient = {
    let monitor = LiveNetworkMonitor.shared
    return NetworkMonitorClient(
      isOnline: { monitor.isOnline },
      listen: { listener in monitor.listen(listener) },
      isOnlinePublisher: { monitor.isOnlinePublisher }
    )
  }()
  
  /// A mock implementation for testing that starts online.
  ///
  /// Use `setOnline(_:)` to simulate network changes.
  public static func mock(initiallyOnline: Bool = true) -> (client: NetworkMonitorClient, setOnline: @Sendable (Bool) -> Void) {
    let state = MockNetworkState(isOnline: initiallyOnline)
    let client = NetworkMonitorClient(
      isOnline: { state.isOnline },
      listen: { listener in state.addListener(listener) },
      isOnlinePublisher: { state.publisher }
    )
    return (client, { newValue in state.setOnline(newValue) })
  }
  
  /// A mock implementation that is always online (for simple tests).
  public static let alwaysOnline = NetworkMonitorClient(
    isOnline: { true },
    listen: { _ in { } },
    isOnlinePublisher: { Just(true).eraseToAnyPublisher() }
  )
  
  /// A mock implementation that is always offline (for offline testing).
  public static let alwaysOffline = NetworkMonitorClient(
    isOnline: { false },
    listen: { _ in { } },
    isOnlinePublisher: { Just(false).eraseToAnyPublisher() }
  )
}

// MARK: - Mock Network State

/// Thread-safe state container for mock network monitoring.
private final class MockNetworkState: @unchecked Sendable {
  private let lock = NSLock()
  private var _isOnline: Bool
  private var listeners: [@Sendable (Bool) -> Void] = []
  private let subject: CurrentValueSubject<Bool, Never>
  
  var isOnline: Bool {
    lock.lock()
    defer { lock.unlock() }
    return _isOnline
  }
  
  var publisher: AnyPublisher<Bool, Never> {
    subject.eraseToAnyPublisher()
  }
  
  init(isOnline: Bool) {
    self._isOnline = isOnline
    self.subject = CurrentValueSubject(isOnline)
  }
  
  func setOnline(_ value: Bool) {
    lock.lock()
    let oldValue = _isOnline
    _isOnline = value
    let currentListeners = listeners
    lock.unlock()
    
    subject.send(value)
    
    guard value != oldValue else { return }
    for listener in currentListeners {
      listener(value)
    }
  }
  
  func addListener(_ listener: @escaping @Sendable (Bool) -> Void) -> @Sendable () -> Void {
    lock.lock()
    listeners.append(listener)
    let index = listeners.count - 1
    lock.unlock()
    
    return { [weak self] in
      guard let self = self else { return }
      self.lock.lock()
      if index < self.listeners.count {
        self.listeners.remove(at: index)
      }
      self.lock.unlock()
    }
  }
}

// MARK: - Live Network Monitor

/// The actual NWPathMonitor-based implementation.
///
/// ## Why This Exists
/// The TypeScript SDK uses `WindowNetworkListener` to detect online/offline status.
/// When offline, the SDK:
/// - Stops attempting WebSocket reconnections (saves resources)
/// - Queues mutations locally without timeouts
/// - Immediately attempts reconnection when back online
///
/// This Swift implementation uses Apple's Network framework (`NWPathMonitor`)
/// to provide equivalent functionality.
private final class LiveNetworkMonitor: @unchecked Sendable {
  static let shared = LiveNetworkMonitor()
  
  private let monitor: NWPathMonitor
  private let queue = DispatchQueue(label: "com.instantdb.network-monitor", qos: .utility)
  private var listeners: [@Sendable (Bool) -> Void] = []
  private let lock = NSLock()
  private let subject: CurrentValueSubject<Bool, Never>
  
  private var _isOnline: Bool = true
  
  var isOnline: Bool {
    lock.lock()
    defer { lock.unlock() }
    return _isOnline
  }
  
  var isOnlinePublisher: AnyPublisher<Bool, Never> {
    subject.eraseToAnyPublisher()
  }
  
  private init() {
    self.monitor = NWPathMonitor()
    self.subject = CurrentValueSubject(true)
    
    monitor.pathUpdateHandler = { [weak self] path in
      guard let self = self else { return }
      
      let newStatus = path.status == .satisfied
      
      self.lock.lock()
      let oldStatus = self._isOnline
      guard newStatus != oldStatus else {
        self.lock.unlock()
        return
      }
      
      self._isOnline = newStatus
      let currentListeners = self.listeners
      self.lock.unlock()
      
      self.subject.send(newStatus)
      
      for listener in currentListeners {
        listener(newStatus)
      }
    }
    
    monitor.start(queue: queue)
  }
  
  deinit {
    monitor.cancel()
  }
  
  func listen(_ listener: @escaping @Sendable (Bool) -> Void) -> @Sendable () -> Void {
    lock.lock()
    listeners.append(listener)
    let index = listeners.count - 1
    lock.unlock()
    
    return { [weak self] in
      guard let self = self else { return }
      self.lock.lock()
      if index < self.listeners.count {
        self.listeners.remove(at: index)
      }
      self.lock.unlock()
    }
  }
}

// MARK: - Legacy Singleton (Deprecated)

/// Monitors network connectivity status for offline mode support.
///
/// - Note: This singleton is deprecated. Use `NetworkMonitorClient` with dependency
///   injection instead for better testability.
@available(*, deprecated, message: "Use NetworkMonitorClient instead for better testability")
public final class NetworkMonitor: ObservableObject, @unchecked Sendable {
  public static let shared = NetworkMonitor()
  
  @Published public private(set) var isOnline: Bool = true
  
  private let client: NetworkMonitorClient
  private var removeListener: (() -> Void)?
  
  private init() {
    self.client = .live
    self.isOnline = client.isOnline()
    
    self.removeListener = client.listen { [weak self] newStatus in
      DispatchQueue.main.async {
        self?.isOnline = newStatus
      }
    }
  }
  
  deinit {
    removeListener?()
  }
  
  public func getIsOnline() async -> Bool {
    return isOnline
  }
  
  @discardableResult
  public func listen(_ listener: @escaping (Bool) -> Void) -> () -> Void {
    return client.listen(listener)
  }
  
  public var isOnlineSync: Bool {
    return isOnline
  }
}


