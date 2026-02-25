import SwiftUI
import InstantDB

/// Demonstrates real-time presence across devices.
///
/// Features shown:
/// - Typed presence (DevicePresence struct, not raw dictionaries)
/// - See which devices are connected in real time
/// - Topic broadcasts (send emoji reactions to all peers)
/// - Platform detection (shows device type icon for each peer)
struct PresenceView: View {
  @EnvironmentObject var db: InstantClient
  @StateObject private var viewModel = PresenceViewModel()

  private let reactionEmojis = ["👋", "🎉", "🔥", "👍", "❤️", "😂"]

  var body: some View {
    NavigationStack {
      ZStack(alignment: .top) {
        content
        ConnectionBanner()
      }
      .navigationTitle("Presence")
      .onAppear {
        viewModel.setup(db: db)
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    if viewModel.isLoading {
      VStack {
        Spacer()
        ProgressView("Joining room...")
        Spacer()
      }
    } else {
      List {
        // This device
        Section("This Device") {
          if let user = viewModel.user {
            DeviceRow(
              name: user.deviceName,
              platform: user.platform,
              isCurrentDevice: true
            )
          }
        }

        // Other devices
        Section("Other Devices (\(viewModel.peers.count))") {
          if viewModel.peers.isEmpty {
            HStack {
              Spacer()
              VStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                  .font(.title2)
                  .foregroundStyle(.tertiary)
                Text("No other devices connected")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                Text("Open this app on another device to see it appear here.")
                  .font(.caption2)
                  .foregroundStyle(.tertiary)
                  .multilineTextAlignment(.center)
              }
              .padding(.vertical, 12)
              Spacer()
            }
          } else {
            ForEach(viewModel.peers) { peer in
              DeviceRow(
                name: peer.data.deviceName,
                platform: peer.data.platform,
                isCurrentDevice: false
              )
            }
          }
        }

        // Reactions
        Section("Send a Reaction") {
          #if os(watchOS)
          ForEach(reactionEmojis, id: \.self) { emoji in
            Button(emoji) {
              viewModel.sendReaction(emoji)
            }
          }
          #else
          LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
            ForEach(reactionEmojis, id: \.self) { emoji in
              Button {
                viewModel.sendReaction(emoji)
              } label: {
                Text(emoji)
                  .font(.title)
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.vertical, 4)
          #endif
        }

        // Reaction feed
        if !viewModel.recentReactions.isEmpty {
          Section("Recent Reactions") {
            ForEach(viewModel.recentReactions.suffix(10).reversed()) { event in
              HStack(spacing: 8) {
                Text(event.emoji)
                  .font(.title3)
                Text(event.senderName)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                Spacer()
                Text(event.timestamp, style: .time)
                  .font(.caption2)
                  .foregroundStyle(.tertiary)
              }
            }
          }
        }
      }
      #if !os(watchOS)
      .listStyle(.insetGrouped)
      #endif
      .padding(.top, 24)
    }
  }
}

// MARK: - Device Row

struct DeviceRow: View {
  let name: String
  let platform: String
  let isCurrentDevice: Bool

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: platformIcon)
        .font(.title3)
        .foregroundStyle(isCurrentDevice ? .blue : .secondary)
        .frame(width: 32)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Text(name)
            .font(.body)
          if isCurrentDevice {
            Text("(you)")
              .font(.caption2)
              .foregroundStyle(.blue)
          }
        }

        Text(platform)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Circle()
        .fill(.green)
        .frame(width: 8, height: 8)
    }
    .padding(.vertical, 2)
  }

  private var platformIcon: String {
    switch platform.lowercased() {
    case "watchos": return "applewatch"
    case "macos": return "macbook"
    case "tvos": return "appletv"
    case "visionos": return "visionpro"
    case "ipados": return "ipad"
    default: return "iphone"
    }
  }
}
