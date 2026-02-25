import SwiftUI
import InstantDB

/// Root navigation for the demo app.
///
/// On iOS/iPadOS/macOS this shows a tab bar with three sections.
/// On watchOS the tab bar adapts automatically to a vertical page style.
struct DemoTabView: View {
  @EnvironmentObject var db: InstantClient
  @EnvironmentObject var authManager: AuthManager

  var body: some View {
    TabView {
      GoalsView()
        .tabItem {
          Label("Goals", systemImage: "target")
        }

      PresenceView()
        .tabItem {
          Label("Presence", systemImage: "person.2.fill")
        }

      AuthView()
        .tabItem {
          Label("Account", systemImage: "person.circle")
        }
    }
  }
}
