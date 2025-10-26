# InstantDB iOS SDK

> ⚠️ **Early Development Warning**: This SDK is in very early development (v0.0.1). APIs may change significantly between releases. Not recommended for production use yet.

A Swift SDK for [InstantDB](https://instantdb.com) - build real-time applications with a triple-store database.

## Features

- ✅ WebSocket real-time connection
- ✅ Authentication (Guest & Magic Code)
- ✅ Automatic token management with Keychain
- ✅ Query subscriptions
- ✅ Transactions
- ✅ SwiftUI integration
- ⏳ Query result parsing (in progress)
- ⏳ Triple store (planned)
- ⏳ Offline support (planned)

## Requirements

- iOS 15.0+ / macOS 12.0+ / watchOS 8.0+ / tvOS 15.0+
- Swift 5.9+
- Xcode 15.0+

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/tornikegomareli/instant-ios-sdk.git", from: "0.0.1")
]
```

Or in Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/tornikegomareli/instant-ios-sdk.git`
3. Select version: `0.0.1`

## Quick Start

### Basic Setup

```swift
import SwiftUI
import InstantDB

@main
struct MyApp: App {
    let db = InstantClient(appID: "your-app-id")

    var body: some Scene {
        WindowGroup {
            ContentView()
                .instantClient(db)
        }
    }
}
```

### Authentication

```swift
struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var db: InstantClient

    var body: some View {
        VStack {
            // Sign in as guest
            Button("Continue as Guest") {
                Task {
                    try? await authManager.signInAsGuest()
                }
            }

            // Magic code authentication
            Button("Send Magic Code") {
                Task {
                    try? await authManager.sendMagicCode(email: "user@example.com")
                }
            }
        }
    }
}
```

### Real-time Connection

```swift
struct MyView: View {
    @EnvironmentObject var db: InstantClient

    var body: some View {
        VStack {
            Text("Status: \(db.connectionState)")

            Button("Connect") {
                db.connect()
            }
        }
    }
}
```

## Current Limitations

This is an early alpha release with several limitations:

- Query results are not yet parsed into usable objects
- No offline support
- Limited error handling
- APIs will change in future releases
- Limited documentation

## Example App

Check out the `instantdb-example` folder for a complete working example with:
- Real-time connection monitoring
- Authentication flows (Guest & Magic Code)
- Query subscriptions
- Comprehensive logging

## Development Status

See current progress and upcoming features in the project.

## Contributing

This SDK is in early development. Contributions are welcome but expect significant API changes.

## License

MIT License - see LICENSE file for details

## Links

- [InstantDB Website](https://instantdb.com)
- [InstantDB Documentation](https://instantdb.com/docs)
- [Issue Tracker](https://github.com/tornikegomareli/instant-ios-sdk/issues)

---

**Version**: 0.0.1
**Status**: Early Alpha
**Last Updated**: October 27, 2025
