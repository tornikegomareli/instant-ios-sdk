//
//  OAuthSession.swift
//  InstantDB
//
//  Created by Tornike Gomareli on 29.10.25.
//


@MainActor
private internal class OAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
  private let provider: OAuthProvider
  private let redirectURI: String
  private let appID: String
  private var continuation: CheckedContinuation<String, Error>?

  init(provider: OAuthProvider, redirectURI: String, appID: String) {
    self.provider = provider
    self.redirectURI = redirectURI
    self.appID = appID
  }

  func authenticate(presentationAnchor: ASPresentationAnchor) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation

      let authURL = buildAuthURL()

      let session = ASWebAuthenticationSession(
        url: authURL,
        callbackURLScheme: "instantdb"
      ) { [weak self] callbackURL, error in
        if let error = error {
          continuation.resume(throwing: error)
          return
        }

        guard let callbackURL = callbackURL,
              let code = self?.extractCode(from: callbackURL) else {
          continuation.resume(throwing: InstantError.invalidMessage)
          return
        }

        continuation.resume(returning: code)
      }

      session.presentationContextProvider = self
      session.prefersEphemeralWebBrowserSession = true
      session.start()
    }
  }

  private func buildAuthURL() -> URL {
    var components = URLComponents(string: provider.authorizationEndpoint)!

    var queryItems = [
      URLQueryItem(name: "client_id", value: provider.clientID),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "state", value: appID)
    ]

    switch provider {
    case .apple:
      queryItems.append(URLQueryItem(name: "response_mode", value: "form_post"))
      queryItems.append(URLQueryItem(name: "scope", value: "name email"))
    case .google:
      queryItems.append(URLQueryItem(name: "scope", value: "openid email profile"))
    case .github:
      queryItems.append(URLQueryItem(name: "scope", value: "read:user user:email"))
    }

    components.queryItems = queryItems
    return components.url!
  }

  private func extractCode(from url: URL) -> String? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let queryItems = components.queryItems else {
      return nil
    }

    return queryItems.first(where: { $0.name == "code" })?.value
  }

  nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    ASPresentationAnchor()
  }
}