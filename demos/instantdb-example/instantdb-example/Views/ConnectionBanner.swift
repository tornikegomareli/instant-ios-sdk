import SwiftUI
import InstantDB

/// A compact banner showing the current connection state.
/// Shows a colored dot and label. Visible across all demo screens.
struct ConnectionBanner: View {
  @EnvironmentObject var db: InstantClient

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(statusColor)
        .frame(width: 8, height: 8)

      Text(statusLabel)
        .font(.caption2)
        .foregroundStyle(.secondary)

      Spacer()

      Text(platformLabel)
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    #if os(watchOS)
    .background(Color.black.opacity(0.6))
    #else
    .background(.bar)
    #endif
  }

  private var statusColor: Color {
    switch db.connectionState {
    case .authenticated: return .green
    case .connected: return .orange
    case .connecting: return .yellow
    case .disconnected: return .red
    case .error: return .red
    }
  }

  private var statusLabel: String {
    switch db.connectionState {
    case .authenticated: return "Connected"
    case .connected: return "Handshaking..."
    case .connecting: return "Connecting..."
    case .disconnected: return "Offline"
    case .error: return "Error"
    }
  }

  private var platformLabel: String {
    PresenceViewModel.currentPlatform
  }
}
