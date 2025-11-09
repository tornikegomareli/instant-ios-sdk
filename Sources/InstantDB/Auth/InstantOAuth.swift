//
//  InstantOAuth.swift
//  InstantDB
//
//  Created by Tornike Gomareli on 29.10.25.
//

import Foundation
import AuthenticationServices

/// OAuth client for InstantDB
@MainActor
public final class InstantOAuth {
  private let appID: String
  private let baseURL: String
  private let redirectURI: String

  public init(
    appID: String,
    baseURL: String = "https://api.instantdb.com",
    redirectURI: String = "instantdb://oauth-callback"
  ) {
    self.appID = appID
    self.baseURL = baseURL
    self.redirectURI = redirectURI
  }

  /// Start OAuth flow with a provider
  public func startOAuth(
    provider: OAuthProvider,
    presentationAnchor: ASPresentationAnchor
  ) async throws -> String {
    let session = OAuthSession(
      provider: provider,
      redirectURI: redirectURI,
      appID: appID,
      baseURL: baseURL
    )

    return try await session.authenticate(presentationAnchor: presentationAnchor)
  }
}
