import SwiftUI
import InstantDB
import GoogleSignIn
import Clerk

@main
struct instantdb_exampleApp: App {
  let db = InstantClient(appID: "a8a567cc-34a7-41b4-8802-d81186ad7014")

  init() {
    Clerk.shared.configure(publishableKey: "pk_test_cHJpbWFyeS1jaGltcC02My5jbGVyay5hY2NvdW50cy5kZXYk")
  }

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
      .onOpenURL { url in
        GIDSignIn.sharedInstance.handle(url)
      }
      .task {
        try? await Clerk.shared.load()
      }
    }
  }
}
