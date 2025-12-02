# InstantDB iOS SDK

> **Early Development Warning**: This SDK is in very early development (v0.1 Beta). Server-side execution only. No offline support, no optimistic updates yet.

A Swift SDK for [InstantDB](https://instantdb.com) - build real-time applications

## Installation

```swift
.package(url: "https://github.com/instantdb/instant-ios-sdk", from: "0.1.0")
```

## Setup

```swift
let db = InstantClient(appID: "YOUR_APP_ID")
```

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

/// With filters
/// PS - U can't use comparison operator until property is not indexed in instant db. 
for await result in db.query(Goal.self)
    .where { $0.difficulty > 5 }
    .limit(10)
    .values() {
    self.goals = result.data
}
```

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
// Magic code
try await db.authManager.sendMagicCode(email: "user@example.com")
try await db.authManager.signInWithMagicCode(email: email, code: code)

// Sign in with Apple/Google
try await db.authManager.signInWithIdToken(clientName: "apple", idToken: token)

// Guest
try await db.authManager.signInAsGuest()

// Sign out
try await db.authManager.signOut()
```

## Limitations

- No offline mode
- No optimistic updates
- No local storage
- Can not define database schema
- No permission management

## Roadmap

### Query Enhancements
- [ ] Cursor-based pagination (`first`, `last`, `after`, `before`)
- [ ] Advanced where operators (`$in`, `$like`, `$isNull`, `and`/`or`)
- [ ] Ordering/sorting by indexed fields
- [ ] Field projection (select specific attributes)
- [ ] Nested queries on linked entities
- [ ] `queryOnce()` for one-time reads

### Schema & Tooling
- [ ] Schema definition DSL in Swift
- [ ] CLI tool or Swift script to deploy schema via Platform API
- [ ] Type generation from schema
- [ ] Query/transaction validation against schema

### Real-Time Collaboration
- [ ] Presence system (`joinRoom`, `publishPresence`, `subscribePresence`)
- [ ] Pub/Sub topics (`publishTopic`, `subscribeTopic`)
- [ ] Room management
- [ ] Connection status monitoring

### Storage & Files
- [ ] File upload (`db.storage.upload`)
- [ ] File delete (`db.storage.delete`)
- [ ] Signed URL generation

### Local-First
- [ ] Local triple store (SQLite)
- [ ] Optimistic updates
- [ ] Offline mode with sync
- [ ] Conflict resolution

## Links

- [InstantDB Website](https://instantdb.com)
- [InstantDB Documentation](https://instantdb.com/docs)
- [InstantDB Repository](https://github.com/instantdb/instant)
- [Issue Tracker](https://github.com/tornikegomareli/instant-ios-sdk/issues)
