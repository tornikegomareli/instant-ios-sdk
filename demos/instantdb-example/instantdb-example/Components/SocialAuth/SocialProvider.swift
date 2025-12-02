import SwiftUI

/// Social sign-in provider definition with brand styling
enum SocialProvider {
  case google
  case github
  case linkedin
  case apple

  var displayName: String {
    switch self {
    case .google: return "Google"
    case .github: return "GitHub"
    case .linkedin: return "LinkedIn"
    case .apple: return "Apple"
    }
  }

  var imageName: String? {
    switch self {
    case .google: return "googlesignin"
    case .github: return "githublogo"
    case .linkedin: return "linkedinlogo"
    case .apple: return nil
    }
  }

  var systemIcon: String? {
    switch self {
    case .apple: return "applelogo"
    default: return nil
    }
  }

  var backgroundColor: Color {
    switch self {
    case .google: return Color.white
    case .github: return Color(hex: "24292e")
    case .linkedin: return Color(hex: "0077b5")
    case .apple: return Color.black
    }
  }

  var foregroundColor: Color {
    switch self {
    case .google: return Color(hex: "1f1f1f")
    case .github: return Color.white
    case .linkedin: return Color.white
    case .apple: return Color.white
    }
  }

  var borderColor: Color? {
    switch self {
    case .google: return Color(hex: "dadce0")
    default: return nil
    }
  }
}
