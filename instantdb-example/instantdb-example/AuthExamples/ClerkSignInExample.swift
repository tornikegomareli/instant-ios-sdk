import SwiftUI
import InstantDB
import Clerk

/// Example: Sign in with Clerk
///
/// This example demonstrates authentication using Clerk's iOS SDK
/// and linking it to InstantDB with ID tokens.
struct ClerkSignInExample: View {
  @EnvironmentObject var authManager: AuthManager
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var showClerkAuth = false

  var body: some View {
    VStack(spacing: 24) {
      headerView

      if let error = errorMessage {
        errorView(error)
      }

      authStatusView

      Spacer()

      codeExample
    }
    .padding()
    .navigationTitle("Sign in with Clerk")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $showClerkAuth) {
      AuthView()
    }
  }

  private var headerView: some View {
    VStack(spacing: 12) {
      Image(systemName: "key.fill")
        .font(.system(size: 60))
        .foregroundStyle(.indigo)

      Text("Sign in with Clerk")
        .font(.title2)
        .fontWeight(.semibold)

      Text("Complete authentication platform with SwiftUI components")
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

  private var authStatusView: some View {
    VStack(spacing: 12) {
      if Clerk.shared.user != nil {
        VStack(spacing: 8) {
          Text("✓ Signed in to Clerk")
            .font(.caption)
            .foregroundStyle(.green)

          Button(action: signInWithClerk) {
            Label("Link Clerk to InstantDB", systemImage: "link")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .disabled(isLoading)
        }
      } else {
        Button(action: openClerkSignIn) {
          Label("Sign in with Clerk", systemImage: "key.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isLoading)
      }
    }
  }

  private var codeExample: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Code Example:")
        .font(.caption)
        .fontWeight(.semibold)

      ScrollView {
        Text("""
        // Step 1: Configure Clerk in app init
        init() {
          Clerk.shared.configure(
            publishableKey: "pk_test_..."
          )
        }

        // Step 2: Load Clerk
        .task {
          try? await Clerk.shared.load()
        }

        // Step 3: Sign in with Clerk UI
        .sheet(isPresented: $showClerkAuth) {
          AuthView()
        }

        // Step 4: Link to InstantDB
        guard let session = Clerk.shared.session else {
          throw InstantError.invalidMessage
        }

        let token = try await session.getToken()

        try await authManager.signInWithIdToken(
          clientName: "clerk",
          idToken: token!.jwt
        )
        """)
        .font(.system(.caption, design: .monospaced))
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
      }
    }
  }

  private func openClerkSignIn() {
    showClerkAuth = true
  }

  private func signInWithClerk() {
    isLoading = true
    errorMessage = nil

    Task {
      do {
        guard let user = Clerk.shared.user else {
          await MainActor.run {
            errorMessage = "Please sign in with Clerk first"
            isLoading = false
          }
          return
        }

        guard let session = Clerk.shared.session else {
          await MainActor.run {
            errorMessage = "No active Clerk session found"
            isLoading = false
          }
          return
        }

        let token = try await session.getToken()

        try await authManager.signInWithIdToken(
          clientName: "clerk",
          idToken: token!.jwt
        )

        await MainActor.run {
          isLoading = false
        }
      } catch {
        await MainActor.run {
          errorMessage = "Clerk sign-in error: \(error.localizedDescription)"
          isLoading = false
        }
      }
    }
  }
}
