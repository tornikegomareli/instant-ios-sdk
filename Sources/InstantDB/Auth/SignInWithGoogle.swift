import Foundation
import GoogleSignIn

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
public typealias PresentingWindow = NSWindow
#else
import UIKit
public typealias PresentingViewController = UIViewController
#endif

@MainActor
public final class SignInWithGoogle {
  private let clientID: String

  public init(clientID: String) {
    self.clientID = clientID
  }

  #if canImport(AppKit) && !targetEnvironment(macCatalyst)
  public func signIn(presenting window: NSWindow) async throws -> String {
    let config = GIDConfiguration(clientID: clientID)
    GIDSignIn.sharedInstance.configuration = config

    let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)

    guard let idToken = result.user.idToken?.tokenString else {
      throw InstantError.invalidMessage
    }

    return idToken
  }
  #else
  public func signIn(presenting viewController: UIViewController) async throws -> String {
    let config = GIDConfiguration(clientID: clientID)
    GIDSignIn.sharedInstance.configuration = config

    let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)

    guard let idToken = result.user.idToken?.tokenString else {
      throw InstantError.invalidMessage
    }

    return idToken
  }
  #endif
}
