import SwiftUI
import InstantDB

@main
struct instantdb_exampleApp: App {
  let db = InstantClient(appID: "a8a567cc-34a7-41b4-8802-d81186ad7014")

  var body: some Scene {
    WindowGroup {
      TabView {
        ContentView()
          .tabItem {
            Label("Connection", systemImage: "network")
          }

        AuthDemoView()
          .tabItem {
            Label("Auth", systemImage: "person.circle")
          }
      }
      .instantClient(db)
    }
  }
}
