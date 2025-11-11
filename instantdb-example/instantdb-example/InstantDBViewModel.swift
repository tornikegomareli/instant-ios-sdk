import Foundation
import InstantDB
import Combine
import UIKit

@MainActor
class InstantDBViewModel: ObservableObject {
  @Published var connectionState: ConnectionState = .disconnected
  @Published var isAuthenticated = false
  @Published var authState: AuthState = .loading
  @Published var sessionID: String?
  @Published var attributesCount = 0
  @Published var logs: [String] = []

  private weak var db: InstantClient?
  private weak var authManager: AuthManager?
  private var cancellables = Set<AnyCancellable>()
  private var isSetup = false

  init() {
    addLog("[SUCCESS] InstantDB ViewModel initialized")
  }

  func setup(db: InstantClient, authManager: AuthManager) {
    guard !isSetup else { return }
    isSetup = true

    self.db = db
    self.authManager = authManager
    setupObservers()
    addLog("[SUCCESS] Connected to shared InstantClient")
    addLog("[INFO] Auth state: \(authManager.state)")
  }
  
  private func setupObservers() {
    guard let db = db, let authManager = authManager else { return }

    db.$connectionState
      .receive(on: DispatchQueue.main)
      .sink { [weak self] state in
        self?.connectionState = state
        self?.addLog("[INFO] Connection: \(state)")
      }
      .store(in: &cancellables)

    db.$isAuthenticated
      .receive(on: DispatchQueue.main)
      .sink { [weak self] isAuth in
        self?.isAuthenticated = isAuth
        if isAuth {
          self?.addLog("[SUCCESS] Connection authenticated!")
        } else {
          self?.addLog("[INFO] Connection is guest/unauthenticated")
        }
      }
      .store(in: &cancellables)

    db.$sessionID
      .receive(on: DispatchQueue.main)
      .sink { [weak self] sessionID in
        self?.sessionID = sessionID
        if let sessionID = sessionID {
          self?.addLog("[INFO] Session: \(sessionID.prefix(8))...")
        }
      }
      .store(in: &cancellables)

    db.$attributes
      .receive(on: DispatchQueue.main)
      .sink { [weak self] attrs in
        self?.attributesCount = attrs.count
        if !attrs.isEmpty {
          self?.addLog("[INFO] Loaded \(attrs.count) attributes")
        }
      }
      .store(in: &cancellables)

    authManager.$state
      .receive(on: DispatchQueue.main)
      .sink { [weak self] state in
        self?.authState = state
        switch state {
        case .loading:
          self?.addLog("[INFO] Auth: Loading...")
        case .unauthenticated:
          self?.addLog("[INFO] Auth: Not signed in")
        case .guest(let user):
          self?.addLog("[INFO] Auth: Guest user (id: \(user.id.prefix(8))...)")
        case .authenticated(let user):
          self?.addLog("[SUCCESS] Auth: Signed in as \(user.email ?? "unknown")")
        }
      }
      .store(in: &cancellables)
  }
  
  func connect() {
    guard let db = db else {
      addLog("[ERROR] DB not initialized")
      return
    }
    addLog("[INFO] Connecting to InstantDB...")
    db.connect()
  }

  func disconnect() {
    guard let db = db else {
      addLog("[ERROR] DB not initialized")
      return
    }
    addLog("[INFO] Disconnecting...")
    db.disconnect()
    addLog("[INFO] Disconnected")
  }

  func subscribeToQuery() {
    guard let db = db else {
      addLog("[ERROR] DB not initialized")
      return
    }

    guard isAuthenticated else {
      addLog("[ERROR] Not authenticated")
      return
    }

    let query: [String: Any] = [
      "users": [:]
    ]

    do {
      _ = try db.subscribeQuery(query) { [weak self] result in
        if let error = result.error {
          self?.addLog("[ERROR] Query error: \(error.localizedDescription)")
        } else if result.isLoading {
          self?.addLog("[INFO] Query loading...")
        } else if let users = result["users"] as? [[String: Any]] {
          self?.addLog("[SUCCESS] Received \(users.count) users")
        } else {
          self?.addLog("[SUCCESS] Query result: \(result.data)")
        }
      }
      addLog("[INFO] Query subscription sent")
    } catch {
      addLog("[ERROR] Failed to subscribe: \(error.localizedDescription)")
    }
  }
  
  func clearLogs() {
    logs.removeAll()
  }

  func copyLogs() {
    let logsText = logs.joined(separator: "\n")
    UIPasteboard.general.string = logsText
    addLog("[SUCCESS] Logs copied to clipboard")
  }
  
  private func addLog(_ message: String) {
    let timestamp = Date().formatted(date: .omitted, time: .standard)
    logs.append("[\(timestamp)] \(message)")
  }
  
  var statusEmoji: String {
    switch connectionState {
    case .disconnected:
      return "⚫️"
    case .connecting:
      return "🟡"
    case .connected:
      return "🟢"
    case .authenticated:
      return "✅"
    case .error:
      return "🔴"
    }
  }
  
  var statusText: String {
    switch connectionState {
    case .disconnected:
      return "Disconnected"
    case .connecting:
      return "Connecting..."
    case .connected:
      return "Connected"
    case .authenticated:
      return "Authenticated"
    case .error(let error):
      return "Error: \(error.localizedDescription)"
    }
  }
}
