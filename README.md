# InstantDB iOS SDK

> **Early Development Warning**: This SDK is in very early development (v0.1 Beta). Server-side execution only. No offline support, no optimistic updates yet.

A Swift SDK for [InstantDB](https://instantdb.com) - build real-time applications

## Installation

```swift
.package(url: "https://github.com/instantdb/instant-ios-sdk", from: "0.1.2")
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

## Schema Definition

Define your schema using the Swift

```swift
// instant.schema.swift
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

## Limitations

- No offline mode
- No optimistic updates
- No storage API
- No permission management

## Troubleshooting

### Links resolve to `nil` (e.g. "Unknown Author")

If a linked entity shows up in the optimistic UI but later flips to `nil` after a server
refresh, the most common cause is a **broken link attribute in the server schema**:

- The attribute exists but has `value-type: blob` instead of `ref`, or
- The attribute is a `ref` but is missing `reverse-identity` metadata.

#### Why This Matters

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
- [ ] Nested queries on linked entities
- [ ] `queryOnce()` for one-time reads

### Schema & Tooling
- [x] Schema definition DSL in Swift
- [x] CLI tool to deploy schema via Platform API
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
