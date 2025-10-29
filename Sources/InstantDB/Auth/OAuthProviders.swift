import Foundation
import AuthenticationServices

/// OAuth provider configuration
public enum OAuthProvider {
  case apple(clientName: String = "apple")
  case google(clientName: String = "google-ios")
  case github(clientName: String = "github-ios")

  var clientName: String {
    switch self {
    case .apple(let clientName):
      return clientName
    case .google(let clientName):
      return clientName
    case .github(let clientName):
      return clientName
    }
  }
}
