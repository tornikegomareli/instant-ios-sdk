import SwiftUI
import InstantDB
import GoogleSignIn
import Clerk

@main
struct instantdb_exampleApp: App {
  let db = InstantClient(appID: AppConfig.instantAppID)

  init() {
    Clerk.shared.configure(publishableKey: AppConfig.clerkPublishableKey)
  }

  var body: some Scene {
    WindowGroup {
      TabView {
        DemoSelectorView()
          .tabItem {
            Label("Demos", systemImage: "square.grid.2x2")
          }

        AuthExamplesView()
          .tabItem {
            Label("Auth", systemImage: "person.circle")
          }
      }
      .instantClient(db)
      .onOpenURL { url in
        GIDSignIn.sharedInstance.handle(url)
      }
      .task {
        try? await Clerk.shared.load()
      }
    }
  }
}
