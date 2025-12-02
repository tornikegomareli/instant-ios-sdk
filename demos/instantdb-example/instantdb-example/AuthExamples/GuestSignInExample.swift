import SwiftUI
import InstantDB

/// Example: Sign in as Guest
///
/// This example demonstrates anonymous guest authentication
/// that can be upgraded later to a full account.
struct GuestSignInExample: View {
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
    .navigationTitle("Guest Sign-In")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var headerView: some View {
    VStack(spacing: 12) {
      Image(systemName: "person.crop.circle.badge.questionmark")
        .font(.system(size: 60))
        .foregroundStyle(.orange)

      Text("Guest Sign-In")
        .font(.title2)
        .fontWeight(.semibold)

      Text("Anonymous authentication that can be upgraded to a full account later")
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
    Button(action: signInAsGuest) {
      Label("Continue as Guest", systemImage: "person.circle")
        .frame(maxWidth: .infinity)
        .padding()
    }
    .buttonStyle(.borderedProminent)
    .tint(.orange)
    .disabled(isLoading)
  }

  private var codeExample: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Code Example:")
        .font(.caption)
        .fontWeight(.semibold)

      ScrollView {
        Text("""
        // Sign in as guest
        try await authManager.signInAsGuest()

        // Later upgrade to full account with magic code
        try await authManager.sendMagicCode(
          email: "user@example.com"
        )

        try await authManager.signInWithMagicCode(
          email: "user@example.com",
          code: "123456"
        )
        """)
        .font(.system(.caption, design: .monospaced))
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
      }
    }
  }

  private func signInAsGuest() {
    isLoading = true
    errorMessage = nil

    Task {
      do {
        try await authManager.signInAsGuest()
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
