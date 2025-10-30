import SwiftUI
import InstantDB

/// Main navigation view for browsing all authentication examples
struct AuthExamplesView: View {
  @EnvironmentObject var authManager: AuthManager
  @EnvironmentObject var db: InstantClient

  var body: some View {
    NavigationView {
      VStack(spacing: 24) {
        authStateHeader

        Divider()

        if authManager.state.user == nil {
          examplesList
        } else {
          authenticatedView
        }
      }
      .padding()
      .navigationTitle("Auth Examples")
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private var authStateHeader: some View {
    VStack(spacing: 12) {
      Image(systemName: authManager.state.icon)
        .font(.system(size: 50))
        .foregroundStyle(authManager.state.color)

      Text(authManager.state.title)
        .font(.headline)

      if let user = authManager.state.user {
        Text(user.email ?? "Guest User")
          .font(.caption)
          .foregroundStyle(.secondary)

        Text("ID: \(user.id.prefix(8))...")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(authManager.state.color.opacity(0.1))
    .cornerRadius(12)
  }

  private var examplesList: some View {
    ScrollView {
      VStack(spacing: 16) {
        sectionHeader("Email Authentication")

        NavigationLink(destination: MagicCodeExample()) {
          exampleRow(
            title: "Magic Code",
            description: "Passwordless email authentication",
            icon: "envelope.badge.shield.half.filled",
            color: .purple
          )
        }

        sectionHeader("Native Sign-In")

        NavigationLink(destination: AppleSignInExample()) {
          exampleRow(
            title: "Sign in with Apple",
            description: "Native iOS authentication",
            icon: "applelogo",
            color: .black
          )
        }

        NavigationLink(destination: GoogleSignInExample()) {
          exampleRow(
            title: "Sign in with Google",
            description: "Google Sign-In SDK",
            imageName: "googlesignin"
          )
        }

        sectionHeader("OAuth Providers")

        NavigationLink(destination: GitHubSignInExample()) {
          exampleRow(
            title: "Sign in with GitHub",
            description: "OAuth web flow",
            imageName: "githublogo"
          )
        }

        NavigationLink(destination: LinkedInSignInExample()) {
          exampleRow(
            title: "Sign in with LinkedIn",
            description: "OAuth web flow",
            imageName: "linkedinlogo"
          )
        }

        sectionHeader("Authentication Platforms")

        NavigationLink(destination: ClerkSignInExample()) {
          exampleRow(
            title: "Sign in with Clerk",
            description: "Complete auth platform",
            icon: "key.fill",
            color: .indigo
          )
        }

        sectionHeader("Guest Access")

        NavigationLink(destination: GuestSignInExample()) {
          exampleRow(
            title: "Guest Sign-In",
            description: "Anonymous authentication",
            icon: "person.crop.circle.badge.questionmark",
            color: .orange
          )
        }
      }
    }
  }

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.caption)
      .fontWeight(.semibold)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func exampleRow(
    title: String,
    description: String,
    icon: String? = nil,
    imageName: String? = nil,
    color: Color = .primary
  ) -> some View {
    HStack(spacing: 16) {
      Group {
        if let imageName = imageName {
          Image(imageName)
            .resizable()
            .scaledToFit()
        } else if let icon = icon {
          Image(systemName: icon)
            .font(.title2)
            .foregroundStyle(color)
        }
      }
      .frame(width: 40, height: 40)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.body)
          .fontWeight(.medium)

        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }

  private var authenticatedView: some View {
    VStack(spacing: 20) {
      VStack(spacing: 8) {
        Image(systemName: "checkmark.seal.fill")
          .font(.largeTitle)
          .foregroundStyle(.green)

        Text("Successfully Authenticated")
          .font(.title2)

        if let user = authManager.state.user, let email = user.email {
          Text(email)
            .font(.body)
            .foregroundStyle(.secondary)
        }
      }

      Divider()

      VStack(alignment: .leading, spacing: 8) {
        Text("User Details")
          .font(.headline)

        if let user = authManager.state.user {
          DetailRow(label: "ID", value: user.id)
          DetailRow(label: "Email", value: user.email ?? "N/A")
          DetailRow(label: "Token", value: user.refreshToken.map { String($0.prefix(20)) } ?? "N/A")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
      .background(Color.gray.opacity(0.1))
      .cornerRadius(8)

      Spacer()

      Button(action: signOut) {
        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .tint(.red)
    }
  }

  private func signOut() {
    Task {
      try? await authManager.signOut()
    }
  }
}

struct DetailRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)

      Spacer()

      Text(value)
        .font(.caption)
        .fontDesign(.monospaced)
    }
  }
}

extension AuthState {
  var icon: String {
    switch self {
    case .loading:
      return "hourglass"
    case .unauthenticated:
      return "person.crop.circle.badge.xmark"
    case .guest:
      return "person.crop.circle.badge.questionmark"
    case .authenticated:
      return "checkmark.seal.fill"
    }
  }

  var color: Color {
    switch self {
    case .loading:
      return .gray
    case .unauthenticated:
      return .red
    case .guest:
      return .orange
    case .authenticated:
      return .green
    }
  }

  var title: String {
    switch self {
    case .loading:
      return "Loading..."
    case .unauthenticated:
      return "Not Signed In"
    case .guest:
      return "Guest User"
    case .authenticated:
      return "Authenticated"
    }
  }
}
