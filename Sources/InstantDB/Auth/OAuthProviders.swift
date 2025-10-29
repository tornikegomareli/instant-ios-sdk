import Foundation
import AuthenticationServices

/// OAuth provider configuration
public enum OAuthProvider {
  case apple
  case google
  case github

  var clientName: String {
    switch self {
    case .apple:
      return "apple"
    case .google:
      return "google"
    case .github:
      return "github-web"
    }
  }
}
