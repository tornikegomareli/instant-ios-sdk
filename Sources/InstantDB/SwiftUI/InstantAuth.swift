import SwiftUI

extension View {
  public func instantClient(_ client: InstantClient) -> some View {
    environmentObject(client)
      .environmentObject(client.authManager)
  }
}
