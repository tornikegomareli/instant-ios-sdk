import SwiftUI
import InstantDB

struct AuthDemoView: View {
  @EnvironmentObject var authManager: AuthManager
  @EnvironmentObject var db: InstantClient

  var body: some View {
    NavigationView {
      VStack(spacing: 24) {
        authStateIndicator

        Divider()

        switch authManager.state {
        case .loading:
          ProgressView("Loading...")

        case .unauthenticated:
          UnauthenticatedView()

        case .guest(let user):
          GuestView(user: user)

        case .authenticated(let user):
          AuthenticatedView(user: user)
        }
      }
      .padding()
      .navigationTitle("Auth Demo")
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private var authStateIndicator: some View {
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
}

struct UnauthenticatedView: View {
  @EnvironmentObject var authManager: AuthManager
  @EnvironmentObject var db: InstantClient
  @State private var email = ""
  @State private var code = ""
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var codeSent = false

  var body: some View {
    VStack(spacing: 20) {
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

        if let error = errorMessage {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }

      Divider()

      Text("Or sign in with")
        .font(.caption)
        .foregroundStyle(.secondary)

      VStack(spacing: 12) {
        Button(action: signInWithApple) {
          Label("Sign in with Apple", systemImage: "applelogo")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.black)
        .disabled(isLoading)

        Button(action: signInWithGoogle) {
          Label("Sign in with Google", systemImage: "g.circle.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(isLoading)

        Button(action: signInWithGitHub) {
          Label("Sign in with GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(isLoading)

        Button(action: signInWithLinkedIn) {
          Label("Sign in with LinkedIn", systemImage: "briefcase.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(isLoading)
      }

      Divider()

      Button(action: signInAsGuest) {
        Label("Continue as Guest", systemImage: "person.circle")
      }
      .buttonStyle(.bordered)
      .disabled(isLoading)
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

struct GuestView: View {
  let user: User
  @EnvironmentObject var authManager: AuthManager
  @State private var showUpgrade = false

  var body: some View {
    VStack(spacing: 20) {
      VStack(spacing: 8) {
        Image(systemName: "person.crop.circle.badge.questionmark")
          .font(.largeTitle)
          .foregroundStyle(.orange)

        Text("Guest Account")
          .font(.title2)

        Text("Upgrade to keep your data")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Button(action: { showUpgrade = true }) {
        Label("Upgrade Account", systemImage: "arrow.up.circle.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(.orange)

      Button(action: signOut) {
        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .tint(.red)
    }
    .sheet(isPresented: $showUpgrade) {
      UpgradeAccountView()
    }
  }

  private func signOut() {
    Task {
      try? await authManager.signOut()
    }
  }
}

struct AuthenticatedView: View {
  let user: User
  @EnvironmentObject var authManager: AuthManager

  var body: some View {
    VStack(spacing: 20) {
      VStack(spacing: 8) {
        Image(systemName: "checkmark.seal.fill")
          .font(.largeTitle)
          .foregroundStyle(.green)

        Text("Authenticated")
          .font(.title2)

        if let email = user.email {
          Text(email)
            .font(.body)
            .foregroundStyle(.secondary)
        }
      }

      Divider()

      VStack(alignment: .leading, spacing: 8) {
        Text("User Details")
          .font(.headline)

        DetailRow(label: "ID", value: user.id)
        DetailRow(label: "Email", value: user.email ?? "N/A")
        DetailRow(label: "Token", value: user.refreshToken.map { String($0.prefix(20)) } ?? "N/A")
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

struct UpgradeAccountView: View {
  @Environment(\.dismiss) var dismiss
  @EnvironmentObject var authManager: AuthManager
  @State private var email = ""
  @State private var code = ""
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var codeSent = false

  var body: some View {
    NavigationView {
      VStack(spacing: 20) {
        Text("Upgrade your guest account to keep your data")
          .font(.headline)
          .multilineTextAlignment(.center)
          .padding()

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

            Button(action: upgradeAccount) {
              if isLoading {
                ProgressView()
              } else {
                Text("Upgrade Account")
              }
            }
            .buttonStyle(.borderedProminent)
            .disabled(code.isEmpty || isLoading)
          } else {
            Button(action: sendMagicCode) {
              if isLoading {
                ProgressView()
              } else {
                Text("Send Code")
              }
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty || isLoading)
          }

          if let error = errorMessage {
            Text(error)
              .font(.caption)
              .foregroundStyle(.red)
          }
        }
        .padding()

        Spacer()
      }
      .navigationTitle("Upgrade Account")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
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

  private func upgradeAccount() {
    isLoading = true
    errorMessage = nil

    Task {
      do {
        try await authManager.signInWithMagicCode(email: email, code: code)
        await MainActor.run {
          isLoading = false
          dismiss()
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

#Preview {
  AuthDemoView()
}
