import SwiftUI
import InstantDB

/// Example: Sign in with LinkedIn
///
/// This example demonstrates OAuth authentication with LinkedIn
/// using web-based OAuth flow.
struct LinkedInSignInExample: View {
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
    .navigationTitle("Sign in with LinkedIn")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var headerView: some View {
    VStack(spacing: 12) {
      Image(systemName: "briefcase.fill")
        .font(.system(size: 60))
        .foregroundStyle(.blue)

      Text("Sign in with LinkedIn")
        .font(.title2)
        .fontWeight(.semibold)

      Text("OAuth authentication using LinkedIn and InstantDB OAuth flow")
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
    Button(action: signInWithLinkedIn) {
      Label("Sign in with LinkedIn", systemImage: "briefcase.fill")
        .frame(maxWidth: .infinity)
        .padding()
    }
    .buttonStyle(.borderedProminent)
    .disabled(isLoading)
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
          provider: .linkedin(clientName: "linkedin-ios"),
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

  private func signInWithLinkedIn() {
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
          provider: .linkedin(clientName: "linkedin-ios"),
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
