import SwiftUI
import InstantDB

/// Example: Sign in with GitHub
///
/// This example demonstrates OAuth authentication with GitHub
/// using web-based OAuth flow.
struct GitHubSignInExample: View {
  @EnvironmentObject var authManager: AuthManager
  @EnvironmentObject var db: InstantClient
  @State private var isLoading = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 24) {
      headerView

      if let error = errorMessage {
        errorView(error)
      }

      signInButton

      Spacer()

      codeExample
    }
    .padding()
    .navigationTitle("Sign in with GitHub")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var headerView: some View {
    VStack(spacing: 12) {
      Image("githublogo")
        .resizable()
        .scaledToFit()
        .frame(width: 60, height: 60)

      Text("Sign in with GitHub")
        .font(.title2)
        .fontWeight(.semibold)

      Text("OAuth authentication using GitHub and InstantDB OAuth flow")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
  }

  private func errorView(_ message: String) -> some View {
    Text(message)
      .font(.caption)
      .foregroundStyle(.red)
      .padding()
      .background(Color.red.opacity(0.1))
      .cornerRadius(8)
  }

  private var signInButton: some View {
    SocialSignInButton(
      provider: .github,
      action: signInWithGitHub,
      isLoading: isLoading
    )
  }

  private var codeExample: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Code Example:")
        .font(.caption)
        .fontWeight(.semibold)

      ScrollView {
        Text("""
        guard let window = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene })
          .first?.windows.first else {
          throw InstantError.invalidMessage
        }

        let oauth = InstantOAuth(appID: db.appID)
        let code = try await oauth.startOAuth(
          provider: .github(clientName: "github-ios"),
          presentationAnchor: window
        )

        try await authManager.signInWithOAuth(code: code)
        """)
        .font(.system(.caption, design: .monospaced))
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
      }
    }
  }

  private func signInWithGitHub() {
    isLoading = true
    errorMessage = nil

    Task {
      do {
        guard let window = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene })
          .first?.windows.first else {
          throw InstantError.invalidMessage
        }

        let oauth = InstantOAuth(appID: db.appID)
        let code = try await oauth.startOAuth(
          provider: .github(clientName: "github-ios"),
          presentationAnchor: window
        )
        try await authManager.signInWithOAuth(code: code)
        await MainActor.run {
          isLoading = false
        }
      } catch {
        await MainActor.run {
          errorMessage = error.localizedDescription
          isLoading = false
        }
      }
    }
  }
}
