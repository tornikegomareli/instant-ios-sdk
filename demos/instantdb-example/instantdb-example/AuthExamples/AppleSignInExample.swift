import SwiftUI
import InstantDB

/// Example: Sign in with Apple using native authentication
///
/// This example demonstrates how to use Sign in with Apple
/// with InstantDB's ID token authentication flow.
struct AppleSignInExample: View {
  @EnvironmentObject var authManager: AuthManager
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
    .navigationTitle("Sign in with Apple")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var headerView: some View {
    VStack(spacing: 12) {
      Image(systemName: "applelogo")
        .font(.system(size: 60))
        .foregroundStyle(.black)

      Text("Sign in with Apple")
        .font(.title2)
        .fontWeight(.semibold)

      Text("Native iOS authentication using Sign in with Apple and InstantDB ID token flow")
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
    Button(action: signInWithApple) {
      Label("Sign in with Apple", systemImage: "applelogo")
        .frame(maxWidth: .infinity)
        .padding()
    }
    .buttonStyle(.borderedProminent)
    .tint(.black)
    .disabled(isLoading)
  }

  private var codeExample: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Code Example:")
        .font(.caption)
        .fontWeight(.semibold)

      ScrollView {
        Text("""
        let appleSignIn = SignInWithApple()
        let (idToken, nonce) = try await appleSignIn.signIn(
          presentationAnchor: window
        )

        try await authManager.signInWithIdToken(
          clientName: "apple",
          idToken: idToken,
          nonce: nonce
        )
        """)
        .font(.system(.caption, design: .monospaced))
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
      }
    }
  }

  private func signInWithApple() {
    isLoading = true
    errorMessage = nil

    Task {
      do {
        guard let window = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene })
          .first?.windows.first else {
          throw InstantError.invalidMessage
        }

        let appleSignIn = SignInWithApple()
        let (idToken, nonce) = try await appleSignIn.signIn(presentationAnchor: window)
        try await authManager.signInWithIdToken(
          clientName: "apple",
          idToken: idToken,
          nonce: nonce
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
