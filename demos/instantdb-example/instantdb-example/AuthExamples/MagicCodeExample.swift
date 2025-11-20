import SwiftUI
import InstantDB

/// Example: Sign in with Magic Code
///
/// This example demonstrates email-based authentication
/// using a magic code sent via email.
struct MagicCodeExample: View {
  @EnvironmentObject var authManager: AuthManager
  @State private var email = ""
  @State private var code = ""
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var codeSent = false

  var body: some View {
    VStack(spacing: 24) {
      headerView

      if let error = errorMessage {
        errorView(error)
      }

      formView

      Spacer()

      codeExample
    }
    .padding()
    .navigationTitle("Magic Code")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var headerView: some View {
    VStack(spacing: 12) {
      Image(systemName: "envelope.badge.shield.half.filled")
        .font(.system(size: 60))
        .foregroundStyle(.purple)

      Text("Magic Code Authentication")
        .font(.title2)
        .fontWeight(.semibold)

      Text("Passwordless authentication using email-based magic codes")
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

  private var formView: some View {
    VStack(spacing: 12) {
      TextField("Email", text: $email)
        .textContentType(.emailAddress)
        .keyboardType(.emailAddress)
        .autocapitalization(.none)
        .textFieldStyle(.roundedBorder)

      if codeSent {
        TextField("Magic Code", text: $code)
          .textContentType(.oneTimeCode)
          .keyboardType(.numberPad)
          .textFieldStyle(.roundedBorder)

        Button(action: signInWithCode) {
          if isLoading {
            ProgressView()
          } else {
            Text("Sign In with Code")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(code.isEmpty || isLoading)
      } else {
        Button(action: sendMagicCode) {
          if isLoading {
            ProgressView()
          } else {
            Text("Send Magic Code")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(email.isEmpty || isLoading)
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
        // Step 1: Send magic code
        try await authManager.sendMagicCode(
          email: "user@example.com"
        )

        // Step 2: Sign in with the code
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

  private func sendMagicCode() {
    isLoading = true
    errorMessage = nil

    Task {
      do {
        try await authManager.sendMagicCode(email: email)
        await MainActor.run {
          codeSent = true
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

  private func signInWithCode() {
    isLoading = true
    errorMessage = nil

    Task {
      do {
        try await authManager.signInWithMagicCode(email: email, code: code)
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
