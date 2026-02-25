import Foundation
import InstantDB
import Combine

#if os(watchOS)
import WatchKit
#endif

#if canImport(UIKit)
import UIKit
#endif

/// Presence data shared by each device in the demo room.
struct DevicePresence: PresenceData {
  var deviceName: String
  var platform: String
  var joinedAt: Double
  var lastActive: Double
}

/// Manages real-time presence for the demo room.
///
/// This demonstrates:
/// - Joining a shared room across devices
/// - Publishing typed presence data
/// - Receiving peer presence updates in real time
/// - Topic broadcasts (emoji reactions)
@MainActor
final class PresenceViewModel: ObservableObject {
  @Published var user: DevicePresence?
  @Published var peers: [TypedPeer<DevicePresence>] = []
  @Published var isLoading = true
  @Published var error: String?
  @Published var recentReactions: [ReactionEvent] = []

  private weak var db: InstantClient?
  private var presenceUnsub: (() -> Void)?
  private var topicUnsub: (() -> Void)?

  struct ReactionEvent: Identifiable {
    let id = UUID()
    let emoji: String
    let senderName: String
    let timestamp: Date
  }

  func setup(db: InstantClient) {
    guard self.db == nil else { return }
    self.db = db
    joinRoom()
  }

  // MARK: - Room Lifecycle

  private func joinRoom() {
    guard let db else { return }

    let initial = DevicePresence(
      deviceName: Self.currentDeviceName,
      platform: Self.currentPlatform,
      joinedAt: Date().timeIntervalSince1970 * 1000,
      lastActive: Date().timeIntervalSince1970 * 1000
    )

    presenceUnsub = db.presence.subscribeTypedPresence(
      roomId: AppConfig.presenceRoomID,
      initialPresence: initial
    ) { [weak self] (slice: TypedPresenceSlice<DevicePresence>) in
      guard let self else { return }
      self.user = slice.user
      self.peers = slice.peers
      self.isLoading = slice.isLoading
      self.error = slice.error
    }

    topicUnsub = db.presence.subscribeTopic(
      roomId: AppConfig.presenceRoomID,
      topic: "reactions"
    ) { [weak self] message in
      guard let self else { return }
      if let emoji = message.data["emoji"] as? String,
         let name = message.data["name"] as? String {
        let event = ReactionEvent(emoji: emoji, senderName: name, timestamp: Date())
        self.recentReactions.append(event)
        // Keep last 20 reactions
        if self.recentReactions.count > 20 {
          self.recentReactions.removeFirst()
        }
      }
    }
  }

  func sendReaction(_ emoji: String) {
    guard let db else { return }

    db.presence.publishTopic(
      roomId: AppConfig.presenceRoomID,
      topic: "reactions",
      data: [
        "emoji": emoji,
        "name": Self.currentDeviceName,
      ]
    )
  }

  func updateActivity() {
    guard let db else { return }

    db.presence.publishTypedPresence(
      roomId: AppConfig.presenceRoomID,
      data: DevicePresence(
        deviceName: Self.currentDeviceName,
        platform: Self.currentPlatform,
        joinedAt: user?.joinedAt ?? Date().timeIntervalSince1970 * 1000,
        lastActive: Date().timeIntervalSince1970 * 1000
      )
    )
  }

  deinit {
    presenceUnsub?()
    topicUnsub?()
  }

  // MARK: - Platform Detection

  static var currentPlatform: String {
    #if os(watchOS)
    return "watchOS"
    #elseif os(macOS)
    return "macOS"
    #elseif os(tvOS)
    return "tvOS"
    #elseif os(visionOS)
    return "visionOS"
    #else
    if UIDevice.current.userInterfaceIdiom == .pad {
      return "iPadOS"
    }
    return "iOS"
    #endif
  }

  static var currentDeviceName: String {
    #if os(watchOS)
    return WKInterfaceDevice.current().name
    #elseif os(macOS)
    return Host.current().localizedName ?? "Mac"
    #else
    return UIDevice.current.name
    #endif
  }

  static var platformSymbol: String {
    #if os(watchOS)
    return "applewatch"
    #elseif os(macOS)
    return "macbook"
    #elseif os(tvOS)
    return "appletv"
    #elseif os(visionOS)
    return "visionpro"
    #else
    if UIDevice.current.userInterfaceIdiom == .pad {
      return "ipad"
    }
    return "iphone"
    #endif
  }
}
