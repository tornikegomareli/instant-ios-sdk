import SwiftUI
import InstantDB

/// Simple authentication screen showing guest sign-in and magic code.
///
/// This screen works on all platforms (no platform-specific OAuth dependencies).
/// It demonstrates:
/// - Auth state observation via AuthManager (@Published state)
/// - Guest sign-in (anonymous users)
/// - Magic code sign-in (email-based passwordless auth)
/// - Sign out
struct AuthView: View {
  @EnvironmentObject var db: InstantClient
  @EnvironmentObject var authManager: AuthManager

  @State private var email = ""
  @State private var magicCode = ""
  @State private var codeSent = false
  @State private var isWorking = false
  @State private var error: String?

  var body: some View {
    NavigationStack {
      ZStack(alignment: .top) {
        authContent
        ConnectionBanner()
      }
      .navigationTitle("Account")
    }
  }

  @ViewBuilder
  private var authContent: some View {
    switch authManager.state {
    case .loading:
      VStack {
        Spacer()
        ProgressView("Restoring session...")
        Spacer()
      }

    case .authenticated(let user):
      signedInView(user: user, isGuest: false)

    case .guest(let user):
      signedInView(user: user, isGuest: true)

    case .unauthenticated:
      signedOutView
    }
  }

  // MARK: - Signed In

  private func signedInView(user: User, isGuest: Bool) -> some View {
    List {
      Section {
        HStack(spacing: 12) {
          Image(systemName: isGuest ? "person.crop.circle.badge.questionmark" : "person.crop.circle.fill")
            .font(.largeTitle)
            .foregroundStyle(isGuest ? .orange : .green)

          VStack(alignment: .leading, spacing: 2) {
            Text(isGuest ? "Guest" : (user.email ?? "Signed In"))
              .font(.headline)
            Text("ID: \(String(user.id.prefix(12)))...")
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }
        .padding(.vertical, 4)
      }

      if isGuest {
        Section {
          Text("You're signed in anonymously. Upgrade to a full account with magic code below.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section {
        Button("Sign Out", role: .destructive) {
          Task {
            try? await authManager.signOut()
          }
        }
      }
    }
    #if !os(watchOS)
    .listStyle(.insetGrouped)
    #endif
    .padding(.top, 24)
  }

  // MARK: - Signed Out

  private var signedOutView: some View {
    List {
      // Guest sign-in
      Section {
        Button {
          signInAsGuest()
        } label: {
          HStack {
            Image(systemName: "person.badge.plus")
              .foregroundStyle(.orange)
            Text("Continue as Guest")
            Spacer()
            if isWorking { ProgressView().controlSize(.small) }
          }
        }
        .disabled(isWorking)
      } header: {
        Text("Quick Start")
      } footer: {
        Text("Creates an anonymous account. You can sign in with email later to keep your data.")
      }

      // Magic code sign-in
      Section {
        if !codeSent {
          TextField("Email", text: $email)
            #if !os(watchOS)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .autocapitalization(.none)
            #endif

          Button {
            sendMagicCode()
          } label: {
            HStack {
              Text("Send Magic Code")
              Spacer()
              if isWorking { ProgressView().controlSize(.small) }
            }
          }
          .disabled(email.isEmpty || isWorking)
        } else {
          Text("Code sent to \(email)")
            .font(.caption)
            .foregroundStyle(.secondary)

          TextField("Enter code", text: $magicCode)
            #if !os(watchOS)
            .keyboardType(.numberPad)
            #endif

          Button {
            verifyMagicCode()
          } label: {
            HStack {
              Text("Verify Code")
              Spacer()
              if isWorking { ProgressView().controlSize(.small) }
            }
          }
          .disabled(magicCode.isEmpty || isWorking)

          Button("Use a different email") {
            codeSent = false
            magicCode = ""
            error = nil
          }
          .font(.caption)
        }
      } header: {
        Text("Email Sign In")
      }

      // Error
      if let error {
        Section {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }
    }
    #if !os(watchOS)
    .listStyle(.insetGrouped)
    #endif
    .padding(.top, 24)
  }

  // MARK: - Actions

  private func signInAsGuest() {
    isWorking = true
    error = nil
    Task {
      do {
        try await authManager.signInAsGuest()
      } catch {
        self.error = error.localizedDescription
      }
      isWorking = false
    }
  }

  private func sendMagicCode() {
    isWorking = true
    error = nil
    Task {
      do {
        try await authManager.sendMagicCode(email: email)
        codeSent = true
      } catch {
        self.error = error.localizedDescription
      }
      isWorking = false
    }
  }

  private func verifyMagicCode() {
    isWorking = true
    error = nil
    Task {
      do {
        try await authManager.signInWithMagicCode(email: email, code: magicCode)
      } catch {
        self.error = error.localizedDescription
      }
      isWorking = false
    }
  }
}
