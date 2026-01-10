# InstantDB iOS SDK

A Swift SDK for [InstantDB](https://instantdb.com) - build real-time, offline-first applications for Apple platforms.

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Features

- **Real-time sync** - Instant data synchronization across all clients
- **Offline-first** - Works offline with automatic sync when reconnected
- **Optimistic updates** - Instant UI feedback with automatic rollback on failure
- **Presence system** - Real-time collaboration with room-based presence
- **Type-safe** - Swift macros for compile-time safety
- **Multi-platform** - iOS, macOS, tvOS, and watchOS support

## Installation

```swift
.package(url: "https://github.com/instantdb/instant-ios-sdk", from: "0.2.0")
```

## Setup

```swift
let db = InstantClient(appID: "YOUR_APP_ID")
```

## Debugging & Logging

The SDK historically used a lot of `print(...)` statements while we were building out
the WebSocket transport, schema handling, and client-side joins. That was helpful during
development, but it quickly becomes noisy in real applications and in `swift test` output.

The SDK now keeps stdout **quiet by default** and makes verbose logging opt-in.

### Configuration

Logging is controlled via environment variables:

- `INSTANTDB_LOG_LEVEL`: `off`, `error`, `info`, `debug` (default: `error`)
- `INSTANTDB_DEBUG=1`: forces `debug`

### Examples

Enable high-signal connection logs:

```bash
INSTANTDB_LOG_LEVEL=info swift test --package-path instant-ios-sdk
```

Enable verbose protocol / query debugging:

```bash
INSTANTDB_LOG_LEVEL=debug swift test --package-path instant-ios-sdk
```

In Xcode:

1. Edit Scheme → Run → Arguments
2. Add an environment variable `INSTANTDB_LOG_LEVEL=debug` (or `INSTANTDB_DEBUG=1`)

Define your models with the `@InstantEntity` macro:

```swift
@InstantEntity("goals")
struct Goal {
    let id: String
    var title: String
    var difficulty: Int?
}
```

This generates `create`, `update`, `delete`, `link`, `unlink` transact methods on the type.

## Query

Real-time subscriptions with AsyncStream:

```swift
for await result in db.query(Goal.self).values() {
    self.goals = result.data
}

for await result in db.query(Goal.self)
    .where { $0.difficulty > 5 }
    .limit(10)
    .values() {
    self.goals = result.data
}
```

> **Note:** Comparison operators require the field to be indexed in InstantDB.

Callback-based:

```swift
var subscriptions = Set<SubscriptionToken>()

try db.subscribe(db.query(Goal.self)) { result in
    self.goals = result.data
}
.store(in: &subscriptions)
```

## Transact

Using generated methods inside transact result builder (requires `@InstantEntity` macro):

```swift
try db.transact {
    Goal.create(title: "Ship v1", difficulty: 8)
    Goal.update(id: goalId, title: "Ship v2")
    Goal.delete(id: oldId)
}
```

Using the transaction builder:

```swift
try db.transact(db.tx.goals[newId()].update(["title": "Ship v1"]))

try db.transact([
    db.tx.goals[id1].update(["title": "First"]),
    db.tx.goals[id2].delete()
])
```

## Auth

```swift
try await db.authManager.sendMagicCode(email: "user@example.com")
try await db.authManager.signInWithMagicCode(email: email, code: code)

try await db.authManager.signInWithIdToken(clientName: "apple", idToken: token)

try await db.authManager.signInAsGuest()

try await db.authManager.signOut()
```

## Schema Definition

Define your schema in Swift:

```swift
import InstantDB

let schema = InstantSchema {
    Entity("users")
        .field("email", .string, .unique, .indexed)
        .field("name", .string)
        .optionalField("bio", .string)

    Entity("posts")
        .field("title", .string, .indexed)
        .field("content", .string)
        .field("createdAt", .date)

    Link("users", "posts")
        .hasMany()
        .to("posts", "author")
}
```

Generate JSON and push to InstantDB:

```bash
# Generate instant.schema.json from Swift
instant-schema generate

# Preview changes
instant-schema plan --app-id <id> --token <admin token>

# Push schema
instant-schema push --app-id <id> --token <admin token>

```

## Presence (Real-Time Collaboration)

Build collaborative features with room-based presence:

```swift
let leaveRoom = db.presence.subscribePresence(
    roomId: "canvas-123",
    initialPresence: ["x": 100, "y": 200, "color": "blue"]
) { presenceSlice in
    for (peerId, peerData) in presenceSlice {
        print("Peer \(peerId): \(peerData)")
    }
}

db.presence.publishPresence(roomId: "canvas-123", data: ["x": 150, "y": 250])

leaveRoom()
```

### Typed Presence API

```swift
struct CursorPresence: Codable, Sendable {
    var x: Double
    var y: Double
    var color: String
}

let cleanup = db.presence.subscribeTypedPresence(
    roomId: "canvas-123",
    type: CursorPresence.self,
    initialPresence: CursorPresence(x: 100, y: 200, color: "blue")
) { peers in
    for (peerId, cursor) in peers {
        drawCursor(at: cursor.x, cursor.y, color: cursor.color)
    }
}
```

### Topic Pub/Sub (Broadcast)

```swift
let unsub = db.presence.subscribeTopic(roomId: "chat-room", topic: "reactions") { payload in
    if let emoji = payload["emoji"] as? String {
        showReaction(emoji)
    }
}

db.presence.publishTopic(roomId: "chat-room", topic: "reactions", data: ["emoji": "🎉"])
```

## Storage (File Upload/Download)

```swift
let fileId = try await db.storage.uploadFile(
    path: "photos/avatar.jpg",
    data: imageData,
    options: .init(contentType: "image/jpeg")
)

let fileId = try await db.storage.uploadFile(
    path: "documents/report.pdf",
    fileURL: localFileURL
)

let downloadURL = try await db.storage.downloadURL(path: "photos/avatar.jpg")

let deletedId = try await db.storage.deleteFile(path: "photos/avatar.jpg")
```

## Offline Support & Optimistic Updates

The SDK works offline by default:

- **Optimistic updates** - Mutations apply immediately to UI
- **Offline queue** - Transactions queue while offline
- **Auto-sync** - Queued mutations sync when reconnected
- **Query caching** - Query results persist across sessions

```swift
try db.transact {
    Todo.create(title: "Buy groceries")
}
```

## Connection Status

Monitor connection state using Combine:

```swift
import Combine

var cancellables = Set<AnyCancellable>()

db.$connectionState
    .sink { state in
        switch state {
        case .disconnected:
            print("Offline - changes will sync when reconnected")
        case .connecting:
            print("Connecting...")
        case .connected:
            print("Connected, authenticating...")
        case .authenticated:
            print("Online and ready")
        }
    }
    .store(in: &cancellables)
```

## Limitations

- No permission rule management from SDK (use dashboard or TypeScript SDK)
- watchOS/tvOS: No Google Sign-In (Apple Sign-In and Magic Code work)

## Troubleshooting

### Links resolve to `nil` (e.g. "Unknown Author")

If a linked entity shows up in the optimistic UI but later flips to `nil` after a server
refresh, the most common cause is a **broken link attribute in the server schema**:

- The attribute exists but has `value-type: blob` instead of `ref`, or
- The attribute is a `ref` but is missing `reverse-identity` metadata.

The Swift SDK assembles nested query results client-side. For `ref` attributes, it relies
on `reverse-identity` to understand which namespace and label represent the other side of
the relationship. Without that metadata, the SDK cannot perform the join reliably.

#### Recommended Fix

Push a correct schema definition (TypeScript or Swift schema DSL) so the server stores the
link as a true `ref` with forward + reverse identities.

The SDK also includes a best-effort, lazy repair mechanism when you perform link operations:
it may piggyback an `add-attr` update in the same transaction to repair a broken `ref` attribute,
and then it will apply refreshed schema data from `refresh-ok` before recomputing query results.

## Roadmap

### Query Enhancements
- [x] Cursor-based pagination (`first`, `last`, `after`, `before`)
- [ ] Advanced where operators (`$in`, `$like`, `$isNull`, `and`/`or`)
- [x] Ordering/sorting by indexed fields
- [ ] Field projection (select specific attributes)
- [x] Nested queries on linked entities
- [x] `queryOnce()` for one-time reads

### Schema & Tooling
- [x] Schema definition DSL in Swift
- [x] CLI tool to deploy schema via Platform API
- [ ] Type generation from schema
- [ ] Query/transaction validation against schema

### Real-Time Collaboration
- [x] Presence system (`joinRoom`, `publishPresence`, `subscribePresence`)
- [x] Pub/Sub topics (`publishTopic`, `subscribeTopic`)
- [x] Room management
- [x] Connection status monitoring

### Storage & Files
- [x] File upload URL generation
- [x] File delete
- [x] Download URL generation

### Local-First
- [x] Local triple store (GRDB/SQLite)
- [x] Optimistic updates
- [x] Offline mode with sync
- [ ] Conflict resolution (server-wins currently)

### Platform & Quality
- [ ] SwiftUI property wrappers (`@Query`, `@Presence`)
- [ ] GitHub Actions CI/CD
- [ ] DocC documentation
- [ ] 80%+ test coverage

## Links

- [InstantDB Website](https://instantdb.com)
- [InstantDB Documentation](https://instantdb.com/docs)
- [InstantDB Repository](https://github.com/instantdb/instant)
- [Issue Tracker](https://github.com/tornikegomareli/instant-ios-sdk/issues)
