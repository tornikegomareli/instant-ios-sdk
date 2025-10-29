import Foundation

/// HTTP client for authentication endpoints
@MainActor
public final class AuthAPI {

  private let appID: String
  private let baseURL: String

  public init(appID: String, baseURL: String) {
    self.appID = appID
    self.baseURL = baseURL
  }

  /// Send magic code to email
  public func sendMagicCode(email: String) async throws -> SendMagicCodeResponse {
    let url = URL(string: "\(baseURL)/runtime/auth/send_magic_code")!

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
      "app-id": appID,
      "email": email
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw InstantError.connectionFailed(URLError(.badServerResponse))
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      try handleErrorResponse(data, statusCode: httpResponse.statusCode)
    }

    return try JSONDecoder().decode(SendMagicCodeResponse.self, from: data)
  }

  /// Verify magic code and sign in
  public func verifyMagicCode(
    email: String,
    code: String,
    refreshToken: String? = nil
  ) async throws -> AuthResponse {
    let url = URL(string: "\(baseURL)/runtime/auth/verify_magic_code")!

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var body: [String: Any] = [
      "app-id": appID,
      "email": email,
      "code": code
    ]

    if let refreshToken = refreshToken {
      body["refresh-token"] = refreshToken
    }

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw InstantError.connectionFailed(URLError(.badServerResponse))
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      try handleErrorResponse(data, statusCode: httpResponse.statusCode)
    }

    return try JSONDecoder().decode(AuthResponse.self, from: data)
  }

  /// Sign in as guest
  public func signInAsGuest() async throws -> AuthResponse {
    let url = URL(string: "\(baseURL)/runtime/auth/sign_in_guest")!

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
      "app-id": appID
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw InstantError.connectionFailed(URLError(.badServerResponse))
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      try handleErrorResponse(data, statusCode: httpResponse.statusCode)
    }

    return try JSONDecoder().decode(AuthResponse.self, from: data)
  }

  /// Exchange OAuth authorization code for user token
  public func exchangeCodeForToken(
    code: String,
    codeVerifier: String? = nil,
    refreshToken: String? = nil
  ) async throws -> AuthResponse {
    let url = URL(string: "\(baseURL)/runtime/oauth/token")!

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var body: [String: Any] = [
      "app_id": appID,
      "code": code
    ]

    if let codeVerifier = codeVerifier {
      body["code_verifier"] = codeVerifier
    }

    if let refreshToken = refreshToken {
      body["refresh_token"] = refreshToken
    }

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw InstantError.connectionFailed(URLError(.badServerResponse))
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      try handleErrorResponse(data, statusCode: httpResponse.statusCode)
    }

    return try JSONDecoder().decode(AuthResponse.self, from: data)
  }

  /// Sign in with OAuth ID token (for native sign-in flows)
  public func signInWithIdToken(
    clientName: String,
    idToken: String,
    nonce: String? = nil,
    refreshToken: String? = nil
  ) async throws -> AuthResponse {
    let url = URL(string: "\(baseURL)/runtime/oauth/id_token")!

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var body: [String: Any] = [
      "app_id": appID,
      "client_name": clientName,
      "id_token": idToken
    ]

    if let nonce = nonce {
      body["nonce"] = nonce
    }

    if let refreshToken = refreshToken {
      body["refresh_token"] = refreshToken
    }

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw InstantError.connectionFailed(URLError(.badServerResponse))
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      try handleErrorResponse(data, statusCode: httpResponse.statusCode)
    }

    return try JSONDecoder().decode(AuthResponse.self, from: data)
  }

  /// Sign out
  public func signOut(refreshToken: String) async throws {
    let url = URL(string: "\(baseURL)/runtime/signout")!

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
      "app_id": appID,
      "refresh_token": refreshToken
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw InstantError.connectionFailed(URLError(.badServerResponse))
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      try handleErrorResponse(data, statusCode: httpResponse.statusCode)
    }
  }

  private func handleErrorResponse(_ data: Data, statusCode: Int) throws -> Never {
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let message = json["message"] as? String {
      let hint = json["hint"] as? [String: Any]
      throw InstantError.serverError(message, hint: hint)
    }

    throw InstantError.serverError("HTTP \(statusCode)", hint: nil)
  }
}

public struct SendMagicCodeResponse: Codable {
  public let sent: Bool
}
