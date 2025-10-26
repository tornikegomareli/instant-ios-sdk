import Foundation
import InstantDB

/// Basic example of connecting to InstantDB
///
/// To run this example:
/// 1. Replace "your-app-id" with your actual InstantDB app ID
/// 2. Run: swift run BasicExample

@main
struct BasicExample {
  static func main() async {
    print("🚀 InstantDB Swift SDK - Basic Example\n")
    
    let appID = "a8a567cc-34a7-41b4-8802-d81186ad7014"
    
    let db = InstantClient(appID: appID)
    
    db.$connectionState
      .sink { state in
        print("📡 Connection state: \(state)")
      }
      .store(in: &cancellables)
    
    db.$isAuthenticated
      .sink { isAuth in
        if isAuth {
          print("✅ Authenticated!")
        }
      }
      .store(in: &cancellables)
    
    print("Connecting to InstantDB...")
    db.connect()
    
    try? await Task.sleep(nanoseconds: 3_000_000_000)
    
    if db.isAuthenticated {
      print("\n📊 Trying to subscribe to a query...")
      
      let query: [String: Any] = [
        "users": [:]
      ]
      
      do {
        try db.subscribeQuery(query)
        print("✅ Query subscription sent!")
      } catch {
        print("❌ Failed to subscribe: \(error)")
      }
    }
    
    try? await Task.sleep(nanoseconds: 2_000_000_000)
    
    print("\n👋 Disconnecting...")
    db.disconnect()
    
    try? await Task.sleep(nanoseconds: 1_000_000_000)
    print("✅ Done!")
  }
  
  nonisolated(unsafe) static var cancellables = Set<AnyCancellable>()
}
