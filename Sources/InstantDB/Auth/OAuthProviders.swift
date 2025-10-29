import Foundation
import AuthenticationServices

/// OAuth provider configuration
public enum OAuthProvider {
  case apple(clientName: String = "apple")
  case google(clientName: String = "google-ios")
  case github(clientName: String = "github-ios")
  case linkedin(clientName: String = "linkedin-ios")

  var clientName: String {
    switch self {
    case .apple(let clientName):
      return clientName
    case .google(let clientName):
      return clientName
    case .github(let clientName):
      return clientName
    case .linkedin(let clientName):
      return clientName
    }
  }
}
