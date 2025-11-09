//
//  OAuthSession.swift
//  InstantDB
//
//  Created by Tornike Gomareli on 29.10.25.
//

import Foundation
import AuthenticationServices

@MainActor
internal final class OAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
  private let provider: OAuthProvider
  private let redirectURI: String
  private let appID: String
  private let baseURL: String
  private var continuation: CheckedContinuation<String, Error>?

  init(provider: OAuthProvider, redirectURI: String, appID: String, baseURL: String) {
    self.provider = provider
    self.redirectURI = redirectURI
    self.appID = appID
    self.baseURL = baseURL
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
    var components = URLComponents(string: "\(baseURL)/runtime/oauth/start")!

    components.queryItems = [
      URLQueryItem(name: "app_id", value: appID),
      URLQueryItem(name: "client_name", value: provider.clientName),
      URLQueryItem(name: "redirect_uri", value: redirectURI)
    ]

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
