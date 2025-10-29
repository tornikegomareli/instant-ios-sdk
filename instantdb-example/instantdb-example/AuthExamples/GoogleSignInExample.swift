import SwiftUI
import InstantDB

/// Example: Sign in with Google using native authentication
///
/// This example demonstrates how to use Google Sign-In
/// with InstantDB's ID token authentication flow.
struct GoogleSignInExample: View {
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
    .navigationTitle("Sign in with Google")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var headerView: some View {
    VStack(spacing: 12) {
      Image(systemName: "g.circle.fill")
        .font(.system(size: 60))
        .foregroundStyle(.blue)

      Text("Sign in with Google")
        .font(.title2)
        .fontWeight(.semibold)

      Text("Native iOS authentication using Google Sign-In SDK and InstantDB ID token flow")
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
    Button(action: signInWithGoogle) {
      Label("Sign in with Google", systemImage: "g.circle.fill")
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
        let googleSignIn = SignInWithGoogle(
          clientID: "your-client-id.apps.googleusercontent.com"
        )

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
          throw InstantError.invalidMessage
        }

        let idToken = try await googleSignIn.signIn(
          presentingViewController: rootViewController
        )

        try await authManager.signInWithIdToken(
          clientName: "google-ios",
          idToken: idToken
        )
        """)
        .font(.system(.caption, design: .monospaced))
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
      }
    }
  }

  private func signInWithGoogle() {
    isLoading = true
    errorMessage = nil

    Task {
      do {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
          throw InstantError.invalidMessage
        }

        let googleSignIn = SignInWithGoogle(clientID: "855344946109-q2lc0rf5f9nttpqvhf9jon0sg5d7h44h.apps.googleusercontent.com")
        let idToken = try await googleSignIn.signIn(presentingViewController: rootViewController)
        try await authManager.signInWithIdToken(
          clientName: "google-ios",
          idToken: idToken
        )

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
