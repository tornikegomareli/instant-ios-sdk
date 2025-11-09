import Foundation
import GoogleSignIn

/// Native Google Sign-In helper
@MainActor
public final class SignInWithGoogle {
  private let clientID: String

  /// Initialize with Google iOS Client ID
  /// Get this from Google Cloud Console
  public init(clientID: String) {
    self.clientID = clientID
  }

  /// Start Google Sign-In flow
  public func signIn(presentingViewController: UIViewController) async throws -> String {
    let config = GIDConfiguration(clientID: clientID)
    GIDSignIn.sharedInstance.configuration = config

    let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)

    guard let idToken = result.user.idToken?.tokenString else {
      throw InstantError.invalidMessage
    }

    return idToken
  }
}
