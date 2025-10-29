/// OAuth client for InstantDB
@MainActor
public final class InstantOAuth {
  private let appID: String
  private let redirectURI: String

  public init(appID: String, redirectURI: String = "instantdb://oauth-callback") {
    self.appID = appID
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
      appID: appID
    )

    return try await session.authenticate(presentationAnchor: presentationAnchor)
  }
}