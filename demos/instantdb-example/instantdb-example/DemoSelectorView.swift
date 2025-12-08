import SwiftUI
import InstantDB

struct DemoSelectorView: View {
  @EnvironmentObject var db: InstantClient
  @EnvironmentObject var authManager: AuthManager
  @StateObject private var viewModel = InstantDBViewModel()

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(spacing: 20) {
          connectionStatusView

          Divider()

          statsView

          Divider()

          demosSection

          Divider()

          actionsView

          LogView(title: "Connection Logs", logs: $viewModel.logs, height: 200)
        }
        .padding()
        .padding(.bottom, 60)
      }
      .navigationTitle("InstantDB Demos")
      .navigationBarTitleDisplayMode(.inline)
      .onAppear {
        viewModel.setup(db: db, authManager: authManager)
      }
    }
  }

  private var connectionStatusView: some View {
    VStack(spacing: 12) {
      Text(viewModel.statusEmoji)
        .font(.system(size: 60))

      Text(viewModel.statusText)
        .font(.headline)

      if let user = viewModel.authState.user {
        Text(user.email ?? "Guest User")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      if let sessionID = viewModel.sessionID {
        Text("Session: \(sessionID.prefix(8))...")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(Color.gray.opacity(0.1))
    .cornerRadius(12)
  }

  private var statsView: some View {
    HStack(spacing: 12) {
      StatItem(
        icon: "person.circle.fill",
        label: "Auth Status",
        value: viewModel.authState.isAuthenticated ? "Authenticated" : viewModel.authState.isGuest ? "Guest" : "Not signed in",
        color: viewModel.authState.isAuthenticated ? .green : viewModel.authState.isGuest ? .orange : .gray
      )

      StatItem(
        icon: "doc.text.fill",
        label: "Attributes",
        value: "\(viewModel.attributesCount)",
        color: .blue
      )
    }
  }

  private var demosSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Available Demos")
        .font(.headline)
        .padding(.horizontal)

      VStack(spacing: 12) {
        NavigationLink(destination: TransactionTestView()) {
          DemoCard(
            icon: "flask.fill",
            title: "Transaction Test",
            description: "Advanced transaction and query testing",
            color: .purple
          )
        }
        .disabled(db.connectionState != .authenticated)

        NavigationLink(destination: PaginationTestView()) {
          DemoCard(
            icon: "book.pages.fill",
            title: "Cursor Pagination",
            description: "Test cursor-based pagination with ordering",
            color: .blue
          )
        }
        .disabled(db.connectionState != .authenticated)
      }
      .padding(.horizontal)
    }
  }

  private var actionsView: some View {
    VStack(spacing: 12) {
      HStack(spacing: 12) {
        Button(action: { viewModel.connect() }) {
          Label("Connect", systemImage: "play.circle.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.green)

        Button(action: { viewModel.disconnect() }) {
          Label("Disconnect", systemImage: "stop.circle.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
      }
    }
  }
}

struct DemoCard: View {
  let icon: String
  let title: String
  let description: String
  let color: Color

  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundStyle(color)
        .frame(width: 44, height: 44)
        .background(color.opacity(0.1))
        .cornerRadius(10)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.headline)
          .foregroundStyle(.primary)

        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer()

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .padding()
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .cornerRadius(12)
  }
}

#Preview {
  DemoSelectorView()
}
