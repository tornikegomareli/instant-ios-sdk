import Foundation
import AuthenticationServices

/// Native Sign in with Apple helper
@MainActor
public final class SignInWithApple: NSObject {
  private var continuation: CheckedContinuation<(idToken: String, nonce: String), Error>?
  private var currentNonce: String?

  /// Start Sign in with Apple flow
  public func signIn(presentationAnchor: ASPresentationAnchor) async throws -> (idToken: String, nonce: String) {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation

      let nonce = UUID().uuidString
      self.currentNonce = nonce

      let appleIDProvider = ASAuthorizationAppleIDProvider()
      let request = appleIDProvider.createRequest()
      request.requestedScopes = [.fullName, .email]
      request.nonce = nonce

      let authorizationController = ASAuthorizationController(authorizationRequests: [request])
      authorizationController.delegate = self
      authorizationController.presentationContextProvider = self
      authorizationController.performRequests()
    }
  }
}

extension SignInWithApple: ASAuthorizationControllerDelegate {
  public func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
          let identityTokenData = appleIDCredential.identityToken,
          let identityToken = String(data: identityTokenData, encoding: .utf8),
          let nonce = currentNonce else {
      continuation?.resume(throwing: InstantError.invalidMessage)
      return
    }

    continuation?.resume(returning: (idToken: identityToken, nonce: nonce))
  }

  public func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithError error: Error
  ) {
    continuation?.resume(throwing: error)
  }
}

extension SignInWithApple: ASAuthorizationControllerPresentationContextProviding {
  public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    ASPresentationAnchor()
  }
}
