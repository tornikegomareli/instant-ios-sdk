import Foundation
import Combine

/// Central authentication coordinator
@MainActor
public final class AuthManager: ObservableObject {

  @Published public private(set) var state: AuthState = .loading

  private let keychain: KeychainStorage
  private let authAPI: AuthAPI
  private let appID: String
  private let baseURL: String

  private static let tokenKey = "instant_refresh_token"

  public init(appID: String, baseURL: String = "https://api.instantdb.com") {
    self.appID = appID
    self.baseURL = baseURL
    self.keychain = KeychainStorage()
    self.authAPI = AuthAPI(appID: appID, baseURL: baseURL)
  }

  /// Current authenticated user
  public var currentUser: User? {
    state.user
  }

  /// Restore authentication from stored token
  public func restoreAuth() async {
    do {
      guard let token = try keychain.retrieve(String.self, forKey: Self.tokenKey) else {
        self.state = .unauthenticated
        return
      }

      let user = try await verifyToken(token)

      if user.isGuest {
        self.state = .guest(user)
      } else {
        self.state = .authenticated(user)
      }

    } catch {
      print("[InstantDB] Failed to restore auth: \(error)")
      self.state = .unauthenticated
    }
  }

  /// Save user and token after successful authentication
  func saveAuth(_ user: User) throws {
    guard let token = user.refreshToken else {
      throw InstantError.invalidMessage
    }

    try keychain.save(token, forKey: Self.tokenKey)

    if user.isGuest {
      state = .guest(user)
    } else {
      state = .authenticated(user)
    }
  }

  /// Clear authentication
  func clearAuth() throws {
    try keychain.delete(forKey: Self.tokenKey)
    state = .unauthenticated
  }

  /// Get current refresh token if available
  var refreshToken: String? {
    try? keychain.retrieve(String.self, forKey: Self.tokenKey)
  }

  private func verifyToken(_ token: String) async throws -> User {
    let url = URL(string: "\(baseURL)/runtime/auth/verify_refresh_token")!

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
      "app-id": appID,
      "refresh-token": token
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw InstantError.connectionFailed(URLError(.badServerResponse))
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      throw InstantError.serverError("Token verification failed", hint: nil)
    }

    let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
    return authResponse.user
  }

  /// Sign in as guest
  @discardableResult
  public func signInAsGuest() async throws -> User {
    let response = try await authAPI.signInAsGuest()
    try saveAuth(response.user)
    return response.user
  }

  /// Send magic code to email
  public func sendMagicCode(email: String) async throws {
    _ = try await authAPI.sendMagicCode(email: email)
  }

  /// Sign in with magic code
  @discardableResult
  public func signInWithMagicCode(email: String, code: String) async throws -> User {
    let currentToken = refreshToken
    let response = try await authAPI.verifyMagicCode(
      email: email,
      code: code,
      refreshToken: currentToken
    )
    try saveAuth(response.user)
    return response.user
  }

  /// Sign in with OAuth code
  @discardableResult
  public func signInWithOAuth(code: String, codeVerifier: String? = nil) async throws -> User {
    let currentToken = refreshToken
    let response = try await authAPI.exchangeCodeForToken(
      code: code,
      codeVerifier: codeVerifier,
      refreshToken: currentToken
    )
    try saveAuth(response.user)
    return response.user
  }

  /// Sign out current user
  public func signOut() async throws {
    guard let token = refreshToken else {
      try clearAuth()
      return
    }

    try await authAPI.signOut(refreshToken: token)
    try clearAuth()
  }
}

/// Response from auth endpoints
public struct AuthResponse: Codable {
  public let user: User
}
