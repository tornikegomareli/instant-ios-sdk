import SwiftUI
import InstantDB

@main
struct DemoWatchOSApp: App {
  let db = InstantClient(appID: AppConfig.instantAppID)

  var body: some Scene {
    WindowGroup {
      DemoTabView()
        .instantClient(db)
    }
  }
}
