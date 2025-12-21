# PR #6 Feedback Analysis: TypeScript → Swift Port

**PR**: [feat: Add presence, local-first architecture, and connection robustness](https://github.com/tornikegomareli/instant-ios-sdk/pull/6)  
**Reviewer**: [@tornikegomareli](https://github.com/tornikegomareli) (Repository Owner)  
**Date**: December 20, 2025

---

## ✅ Fixes Applied

All feedback items have been addressed in commit [`143b4f2`](https://github.com/technoplato/instant-ios-sdk/commit/143b4f2).

| Issue | Status | Commit |
|-------|--------|--------|
| Async init race condition | ✅ Fixed | [`143b4f2`](https://github.com/technoplato/instant-ios-sdk/commit/143b4f2) |
| Attr/triple load order | ✅ Fixed | [`143b4f2`](https://github.com/technoplato/instant-ios-sdk/commit/143b4f2) |
| Reconnect task not cancelled | ✅ Fixed | [`143b4f2`](https://github.com/technoplato/instant-ios-sdk/commit/143b4f2) |
| Dictionary comparison bug | ✅ Fixed | [`143b4f2`](https://github.com/technoplato/instant-ios-sdk/commit/143b4f2) |
| Silent error handling | ✅ Fixed | [`143b4f2`](https://github.com/technoplato/instant-ios-sdk/commit/143b4f2) |
| Internal methods exposed | ✅ Fixed | [`143b4f2`](https://github.com/technoplato/instant-ios-sdk/commit/143b4f2) |
| OSLog integration | ✅ Fixed | [`143b4f2`](https://github.com/technoplato/instant-ios-sdk/commit/143b4f2) |
| Lookup ref warning | ✅ Fixed | [`143b4f2`](https://github.com/technoplato/instant-ios-sdk/commit/143b4f2) |
| Misleading method names | ✅ Fixed | [`143b4f2`](https://github.com/technoplato/instant-ios-sdk/commit/143b4f2) |

---

## Executive Summary

This document analyzes the code review feedback from Tornike Gomareli on PR #6, which adds presence, local-first architecture, and connection robustness to the InstantDB iOS SDK. The PR ports significant functionality from the TypeScript `Reactor.js` and `store.ts` files to Swift.

The feedback identifies several areas for improvement, ranging from Swift-idiomatic patterns to fundamental architectural concerns. This analysis provides:

1. **Context** from the upstream TypeScript implementation
2. **Explanation** of the Swift paradigms being requested
3. **Recommended fixes** for each issue

---

## Table of Contents

1. [General Feedback](#general-feedback)
2. [Inline Code Review Comments](#inline-code-review-comments)
3. [Upstream TypeScript Reference](#upstream-typescript-reference)

---

## General Feedback

### 1. OS Logging (Non-blocking)

**Feedback**: Use `OSLog` instead of `print()` statements for production logging.

**Why This Matters**:

In Swift/Apple development, `print()` statements have several problems:
- **Performance**: `print()` is not cheap in production - it synchronously writes to stdout
- **Security**: Implementation details may be exposed in device logs
- **No filtering**: Cannot filter by log level or subsystem in Console.app
- **No persistence**: Logs are lost when the app closes

**Swift Paradigm - OSLog**:

```swift
import os.log

// Define a subsystem and category
private let logger = Logger(subsystem: "com.instantdb.sdk", category: "LocalFirst")

// Usage
logger.debug("Loading \(triples.count) triples")
logger.info("Connection established")
logger.warning("Mutation pending for \(timeout)s")
logger.error("Failed to persist: \(error.localizedDescription)")
```

**Benefits**:
- Logs appear in Console.app with proper filtering
- Log levels can be configured per-subsystem
- Privacy-aware: can redact sensitive data with `\(value, privacy: .private)`
- Minimal performance impact when log level is disabled

**TypeScript Equivalent** (from `Reactor.js` line 287):
```javascript
this._log = createLogger(
  config.verbose || flags.devBackend || flags.instantLogs,
  () => this._reactorStats(),
);
```

---

### 2. TODO Comments

**Locations Identified**:

| File | Line | Comment |
|------|------|---------|
| `StoreOperations.swift` | 130 | "For now, skip if we can't resolve" |
| `LocalFirstManager.swift` | 320 | "For now, return server attrs" |
| `PresenceManager.swift` | 558 | "Simple comparison - could be optimized" |
| `QueryManager.swift` | 280 | "simple implementation - production would need better" |
| `AttrsStore.swift` | 301 | "TODO: Implement schema parsing" |

**Why This Matters**:

TODOs indicate incomplete implementations that could cause silent failures. At minimum, these should log warnings so issues are visible during testing.

**Recommended Action**:
- Add `logger.warning()` calls at each TODO location
- Create GitHub issues to track each TODO
- Consider using `#warning("TODO: ...")` for compile-time visibility

---

### 3. Design Issue: `appId` Passed Through Multiple Layers

**Current Pattern**:
```swift
LocalFirstManager.init(appId: String)
  → LocalStorage.init(appId: String)
    → uses appId for database path
```

**Problem**: `LocalFirstManager` stores `appId` but only passes it to `LocalStorage`. This violates the principle of minimal knowledge.

**Recommended Solutions**:

**Option A - Pass storage directly (Dependency Injection)**:
```swift
// Better: inject the dependency
public init(storage: LocalStorage) {
  self.localStorage = storage
  // ...
}

// Usage
let storage = try LocalStorage(appId: "my-app")
let manager = LocalFirstManager(storage: storage)
```

**Option B - Use a configuration object**:
```swift
public struct InstantConfig {
  let appId: String
  let enablePersistence: Bool
  let databasePath: URL?
}

public init(config: InstantConfig) {
  if config.enablePersistence {
    self.localStorage = try LocalStorage(config: config)
  }
}
```

**TypeScript Reference** (from `Reactor.js` constructor):
```javascript
constructor(
  config,
  Storage = IndexedDBStorage,  // Storage is injected!
  NetworkListener = WindowNetworkListener,
  versions,
  EventSourceConstructor,
) {
  this.config = { ...defaultConfig, ...config };
  // ...
}
```

The TypeScript implementation uses **dependency injection** for `Storage`, which is the pattern we should follow.

---

### 4. Internal Methods Exposed as Public

**Problem Methods**:
```swift
public func handleRefreshPresence(...)
public func handlePatchPresence(...)
public func handleServerBroadcast(...)
public func handleJoinRoomOk(...)
```

**Why This Matters**:

These are **internal implementation details** called by `InstantClient` when processing server messages. SDK users should never call `handleJoinRoomOk()` directly.

**Swift Paradigm - Access Control**:

```swift
// WRONG: Exposes internal implementation
public func handleRefreshPresence(roomId: String, sessions: [String: Any]) { ... }

// RIGHT: Internal visibility
internal func handleRefreshPresence(roomId: String, sessions: [String: Any]) { ... }

// Or if in same module as InstantClient:
func handleRefreshPresence(roomId: String, sessions: [String: Any]) { ... }
```

**If cross-module access is needed**, use `@_spi`:
```swift
@_spi(InstantInternal)
public func handleRefreshPresence(roomId: String, sessions: [String: Any]) { ... }
```

This requires consumers to explicitly opt-in with `@_spi(InstantInternal) import InstantDB`.

---

### 5. Type-Unsafe Dictionaries

**Current Pattern**:
```swift
public let user: [String: Any]
public let peers: [String: [String: Any]]
```

**Why This Matters**:

`[String: Any]` loses all type safety - the core advantage of Swift over JavaScript. Keys can be misspelled, values can be wrong types, and the compiler can't help.

**TypeScript Reference** (from `presence.ts`):
```typescript
export type RoomSchemaShape = {
  [roomType: string]: {
    presence?: { [k: string]: any };
    topics?: { [topic: string]: any };
  };
};
```

Even TypeScript uses generics for presence data!

**Swift Paradigm - Generic Presence**:

```swift
// Define a protocol for presence data
public protocol PresenceData: Codable, Sendable {}

// Generic presence slice
public struct PresenceSlice<T: PresenceData>: Sendable {
  public let user: T
  public let peers: [String: T]
  public let isLoading: Bool
  public let error: String?
}

// Usage
struct CursorPresence: PresenceData {
  let x: Double
  let y: Double
  let name: String
}

let slice: PresenceSlice<CursorPresence> = ...
// Now slice.user.x is type-safe!
```

---

### 6. Magic Strings

**Current Pattern**:
```swift
"op": "join-room"
"op": "leave-room"
"op": "set-presence"
"room-id"
"client-event-id"
```

**Why This Matters**:

Magic strings are error-prone. A typo like `"room_id"` instead of `"room-id"` causes silent failures.

**Swift Paradigm - String Enums**:

```swift
// Wire protocol operations
enum PresenceOp: String, Sendable {
  case joinRoom = "join-room"
  case leaveRoom = "leave-room"
  case setPresence = "set-presence"
  case clientBroadcast = "client-broadcast"
}

// Wire protocol keys
enum WireKey: String {
  case op
  case roomId = "room-id"
  case clientEventId = "client-event-id"
  case data
  case topic
}

// Usage
let message: [String: Any] = [
  WireKey.op.rawValue: PresenceOp.joinRoom.rawValue,
  WireKey.roomId.rawValue: roomId
]
```

**TypeScript Reference** (from `Reactor.js` line 106-110):
```javascript
const ignoreLogging = {
  'set-presence': true,
  'set-presence-ok': true,
  'refresh-presence': true,
  'patch-presence': true,
};
```

Even TypeScript uses constant objects for these strings.

---

### 7. Inconsistent Error Handling

**Problem**: Some places silently ignore errors, others log warnings. This makes debugging difficult.

**Current Pattern**:
```swift
Task {
  try? await storage.saveTriples(triples)  // Silent failure!
}
```

**Swift Paradigm - Explicit Error Handling**:

```swift
// Option 1: Log errors
Task {
  do {
    try await storage.saveTriples(triples)
  } catch {
    logger.error("Failed to save triples: \(error)")
  }
}

// Option 2: Propagate errors (for critical operations)
public func saveTriples(_ triples: [Triple]) async throws {
  // Let caller decide how to handle
}

// Option 3: Result type (for recoverable errors)
public func saveTriples(_ triples: [Triple]) async -> Result<Void, StorageError> {
  // ...
}
```

**Philosophy**: For an SDK, **throwing errors is usually better than silent failures** because:
1. Developers can catch and handle them appropriately
2. Issues are visible during development
3. Production apps can report errors to crash analytics

---

## Inline Code Review Comments

### Comment 1: Async Initialization Race Condition

**File**: `LocalFirstManager.swift` line 93  
**Code**:
```swift
public init(appId: String, enablePersistence: Bool = true) throws {
  // ...
  Task {
    await loadPersistedData()  // Runs asynchronously!
  }
}
```

**Feedback**: "The init returns immediately, but loading happens asynchronously. If the caller uses the manager before loading completes, we will get undefined behavior."

**Why This Matters**:

Swift initializers are synchronous. By spawning a `Task`, we create a race condition:

```swift
let manager = try LocalFirstManager(appId: "my-app")
manager.getEntity("todo-1", entityType: "todos")  // May return nil even if data exists!
```

**TypeScript Reference** (from `Reactor.js` constructor):
```javascript
constructor(config, Storage, ...) {
  // TypeScript also initializes asynchronously, but...
  this._initStorage(Storage);  // Sets up storage
  // ...then waits for data before using it:
  NetworkListener.getIsOnline().then((isOnline) => {
    this._isOnline = isOnline;
    this._startSocket();  // Only starts after setup
  });
}
```

**Swift Paradigm - Async Factory Method**:

```swift
// Private synchronous init
private init(serverStore: TripleStore, attrsStore: AttrsStore, ...) {
  self.serverStore = serverStore
  // ...
}

// Public async factory
public static func create(appId: String, enablePersistence: Bool = true) async throws -> LocalFirstManager {
  let manager = LocalFirstManager(...)
  
  if enablePersistence {
    await manager.loadPersistedData()
  }
  
  return manager
}

// Usage
let manager = try await LocalFirstManager.create(appId: "my-app")
// Now guaranteed to have loaded data
```

---

### Comment 2: Load Order Issue - Attrs Before Triples

**File**: `LocalFirstManager.swift` line 112  
**Code**:
```swift
// Load triples
let triples = try await storage.loadTriples()
for triple in triples {
  let attr = serverAttrsStore.getAttr(triple.attributeId)  // May be nil!
  serverStore.addTriple(triple, ...)
}

// Load attributes (AFTER triples!)
let attrs = try await storage.loadAttrs()
```

**Feedback**: "Shouldn't happen after we will load attributes from storage?"

**Why This Matters**:

When loading triples, we call `serverAttrsStore.getAttr()` to determine cardinality and value type. But attributes haven't been loaded yet, so this always returns `nil`.

**TypeScript Reference** (from `store.ts` line 220-249):
```javascript
function createTripleIndexes(
  attrsStore: AttrsStore,  // Attrs must exist first!
  triples: Triple[],
  useDateObjects,
) {
  for (const triple of triples) {
    const attr = attrsStore.getAttr(aid);  // Looks up attr
    if (!attr) {
      console.warn('no such attr', aid, eid);
      continue;  // Skips triple if no attr!
    }
    // ...
  }
}
```

**Fix**: Load attributes first:

```swift
private func loadPersistedData() async {
  // 1. Load attributes FIRST
  let attrs = try await storage.loadAttrs()
  for attr in attrs {
    serverAttrsStore.addAttr(attr)
  }
  
  // 2. THEN load triples (which depend on attrs)
  let triples = try await storage.loadTriples()
  for triple in triples {
    let attr = serverAttrsStore.getAttr(triple.attributeId)
    // Now attr lookup will succeed!
    serverStore.addTriple(triple, ...)
  }
  
  // 3. Load pending mutations
  // ...
}
```

---

### Comment 3: Missing getAttr Call

**File**: `LocalFirstManager.swift` line 124  
**Feedback**: "Shouldn't it need to be called before calling `getAttr`?"

This is the same issue as Comment 2 - the load order is wrong.

---

### Comments 4-7: Silent Error Handling in Persistence

**Files**: `LocalFirstManager.swift` lines 149, 156, 163, 288

**Code Pattern**:
```swift
private func persistTriples(_ triples: [Triple]) {
  guard let storage = localStorage else { return }
  Task {
    try? await storage.saveTriples(triples)  // Silent failure!
  }
}
```

**Feedback**: "I think we need to catch any kind of errors and at least log them in console."

**Why This Matters**:

`try?` converts errors to `nil`, silently swallowing them. If persistence fails, we have no way to know.

**Fix**:
```swift
private func persistTriples(_ triples: [Triple]) {
  guard let storage = localStorage else { return }
  Task {
    do {
      try await storage.saveTriples(triples)
    } catch {
      logger.error("Failed to persist \(triples.count) triples: \(error)")
      // Optionally: notify observers, retry, etc.
    }
  }
}
```

---

### Comment 8: Storage/Memory State Inconsistency

**File**: `LocalFirstManager.swift` line 288  
**Code**:
```swift
public func removeMutation(eventId: String) {
  optimisticManager.removeMutation(eventId: eventId)  // Removes from memory
  
  if let storage = localStorage {
    Task {
      try? await storage.deletePendingMutation(eventId: eventId)  // May fail!
    }
  }
}
```

**Feedback**: "If this will fail, we will have removed mutation in `optimisticManager` but there will be this mutation pending inside storage, what will happen in this case?"

**Why This Matters**:

This creates an inconsistency:
- Memory: mutation is gone
- Storage: mutation still exists

On next app launch, the mutation will be loaded from storage and re-applied, potentially causing duplicate operations.

**TypeScript Reference** (from `Reactor.js` pendingMutations handling):
The TypeScript SDK handles this by treating storage as secondary - if storage fails, the in-memory state is authoritative. But it also has cleanup mechanisms.

**Fix Options**:

**Option A - Remove from storage first**:
```swift
public func removeMutation(eventId: String) async throws {
  // Remove from storage first
  try await localStorage?.deletePendingMutation(eventId: eventId)
  
  // Only remove from memory if storage succeeded
  optimisticManager.removeMutation(eventId: eventId)
}
```

**Option B - Accept eventual consistency, but log**:
```swift
public func removeMutation(eventId: String) {
  optimisticManager.removeMutation(eventId: eventId)
  
  Task {
    do {
      try await localStorage?.deletePendingMutation(eventId: eventId)
    } catch {
      // Log but don't fail - storage will be cleaned up on next sync
      logger.warning("Failed to remove mutation \(eventId) from storage: \(error)")
    }
  }
}
```

---

### Comment 9: Misleading Method Name and Return Value

**File**: `OptimisticUpdateManager.swift` line 208 & 215

**Code**:
```swift
/// Applies pending mutations on top of a server store.
/// ...
/// - Returns: A new store with optimistic updates applied  // <-- Misleading!
public func applyOptimisticUpdates(to store: TripleStore, ...) -> TripleStore {
  // Actually mutates `store` in place and returns the same reference
  for mutation in mutations {
    _ = applyTransaction(store: store, ...)
  }
  return store  // Same object!
}
```

**Feedback**: "In comments it is written that this function returns new store, but actually it just mutates reference type and returns same store."

**Why This Matters**:

The documentation says "returns a new store" but it mutates the input. This is confusing and could cause bugs if callers expect immutability.

**TypeScript Reference** (from `store.ts` line 891-949):
```javascript
export function transact(store, attrsStore, txSteps) {
  // Uses 'mutative' library for immutable updates
  return create(
    { store, attrsStore },
    (draft) => {
      txStepsFiltered.forEach((txStep) => {
        applyTxStep(draft.store, draft.attrsStore, txStep);
      });
    },
  );
}
```

The TypeScript version uses the `mutative` library to create an **immutable copy**.

**Fix Options**:

**Option A - Make truly immutable (matches TypeScript)**:
```swift
public func applyOptimisticUpdates(to store: TripleStore, ...) -> TripleStore {
  // Create a copy
  let optimisticStore = store.copy()
  
  for mutation in mutations {
    _ = applyTransaction(store: optimisticStore, ...)
  }
  
  return optimisticStore
}
```

**Option B - Fix documentation and don't return**:
```swift
/// Applies pending mutations to the store in place.
///
/// - Note: This mutates the input store directly.
public func applyOptimisticUpdates(to store: TripleStore, ...) {
  for mutation in mutations {
    _ = applyTransaction(store: store, ...)
  }
}
```

---

### Comment 10: Misleading Method Name - toJSON

**File**: `OptimisticUpdateManager.swift` line 215

**Code**:
```swift
/// Converts to a dictionary for persistence
public func toJSON() -> [String: PendingMutation] {
  lock.withLock { pendingMutations }
}
```

**Feedback**: "I think this method doesn't return json, so maybe we need better naming for it."

**Why This Matters**:

`toJSON()` implies it returns JSON data (like `Data` or `String`), but it returns a Swift dictionary.

**Better Names**:
```swift
// Options:
public func toDictionary() -> [String: PendingMutation]
public func asDictionary() -> [String: PendingMutation]
public var allMutations: [String: PendingMutation]
public func export() -> [String: PendingMutation]
```

---

### Comment 11: Reconnection Task Not Cancelled

**File**: `WebSocketConnection.swift` line 144

**Code**:
```swift
private func scheduleReconnect() {
  // ...
  reconnectTask = Task { [weak self] in  // Overwrites previous task!
    do {
      try await Task.sleep(...)
      // ...
    }
  }
}
```

**Feedback**: "If scheduleReconnect is called twice rapidly, the first reconnectTask isn't cancelled, should we add `reconnectTask?.cancel()`?"

**Why This Matters**:

If `scheduleReconnect()` is called twice quickly:
1. First task starts sleeping
2. Second call overwrites `reconnectTask` reference
3. First task completes and attempts reconnect
4. Second task completes and attempts reconnect
5. Two simultaneous reconnection attempts!

**Fix**:
```swift
private func scheduleReconnect() {
  guard autoReconnect, !isShutdown else { return }
  
  // Cancel any existing reconnection attempt
  reconnectTask?.cancel()
  
  let delay = reconnectDelaySeconds
  // ...
  
  reconnectTask = Task { [weak self] in
    do {
      try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      guard !Task.isCancelled else { return }
      // ...
    } catch {
      // Task was cancelled
    }
  }
}
```

---

### Comment 12: Unreliable Dictionary Comparison

**File**: `PresenceManager.swift` line 562

**Code**:
```swift
private func hasPresenceChanged(_ a: PresenceSlice, _ b: PresenceSlice) -> Bool {
  // Simple comparison - could be optimized
  return a.user.description != b.user.description ||
         a.peers.description != b.peers.description ||
         // ...
}
```

**Feedback**: "Two different dictionaries could have same description but different contents. We should implement deep equality check or use `NSDictionary.isEqual()`"

**Why This Matters**:

`Dictionary.description` is for debugging, not comparison. Two dictionaries with the same contents might have different string representations due to:
- Key ordering (dictionaries are unordered)
- Floating point formatting
- Nested object representation

**Example of the bug**:
```swift
let a: [String: Any] = ["x": 1, "y": 2]
let b: [String: Any] = ["y": 2, "x": 1]

a.description  // Could be "{x: 1, y: 2}"
b.description  // Could be "{y: 2, x: 1}"

a.description == b.description  // false! But they're equal!
```

**TypeScript Reference** (from `presence.ts`):
```javascript
export function hasPresenceResponseChanged(a, b) {
  // Uses deep equality check
  return !areObjectsDeepEqual(a.peers, b.peers) ||
         !areObjectsDeepEqual(a.user, b.user) ||
         a.isLoading !== b.isLoading ||
         a.error !== b.error;
}
```

**Fix**:
```swift
private func hasPresenceChanged(_ a: PresenceSlice, _ b: PresenceSlice) -> Bool {
  // Use NSDictionary for deep equality (handles [String: Any])
  let userEqual = NSDictionary(dictionary: a.user).isEqual(to: b.user)
  let peersEqual = NSDictionary(dictionary: a.peers).isEqual(to: b.peers)
  
  return !userEqual || !peersEqual || a.isLoading != b.isLoading || a.error != b.error
}

// Or better: make PresenceSlice generic with Equatable conformance
public struct PresenceSlice<T: PresenceData>: Equatable where T: Equatable {
  // Now == works correctly
}
```

---

### Comment 13: Silent Failure in Lookup Ref Resolution

**File**: `StoreOperations.swift` line 130

**Code**:
```swift
private func applyAddTriple(store: TripleStore, attrsStore: AttrsStore, args: [Any]) {
  // Handle lookup refs (entityId can be [attrId, value] for lookups)
  if let eid = args[0] as? String {
    entityId = eid
  } else if let lookup = args[0] as? [Any], lookup.count == 2 {
    // Lookup ref - need to resolve
    // For now, skip if we can't resolve
    return  // Silent failure!
  }
}
```

**Feedback**: "Should at least log a warning"

**TypeScript Reference** (from `store.ts` line 336-386):
```javascript
function resolveLookupRefs(store, triple) {
  if (Array.isArray(triple[0])) {
    const [a, v] = triple[0];
    const eMaps = store.aev.get(a);
    if (!eMaps) {
      // We don't have the attr, so don't try to add the triple
      return null;  // Returns null, caller handles it
    }
    // ...
  }
}
```

The TypeScript version returns `null` and the caller decides what to do. In Swift, we should at least log:

**Fix**:
```swift
} else if let lookup = args[0] as? [Any], lookup.count == 2 {
  // Lookup ref - need to resolve
  // TODO: Implement lookup ref resolution
  logger.warning("Lookup ref resolution not yet implemented, skipping triple: \(args)")
  return
}
```

---

## Upstream TypeScript Reference

### Key Files

| TypeScript File | Swift Equivalent | Purpose |
|-----------------|------------------|---------|
| `Reactor.js` | `InstantClient.swift` + `PresenceManager.swift` | Main coordinator, presence handling |
| `store.ts` | `TripleStore.swift` + `AttrsStore.swift` + `StoreOperations.swift` | Triple storage with EAV/AEV/VAE indexes |
| `presence.ts` | `PresenceManager.swift` | Presence slice building, change detection |
| `Connection.ts` | `WebSocketConnection.swift` | WebSocket transport |

### Architecture Comparison

**TypeScript (Reactor.js)**:
```
Reactor
├── _transport (WSConnection)
├── querySubs (PersistedObject)
├── kv (PersistedObject) → pendingMutations
├── _rooms (presence room state)
├── _presence (presence data)
└── _broadcastSubs (topic handlers)
```

**Swift (Current)**:
```
InstantClient
├── connection (WebSocketConnection)
├── queryManager (QueryManager)
├── localFirstManager (LocalFirstManager)
│   ├── serverStore (TripleStore)
│   ├── serverAttrsStore (AttrsStore)
│   ├── optimisticManager (OptimisticUpdateManager)
│   └── localStorage (LocalStorage)
├── presence (PresenceManager)
│   ├── rooms
│   ├── presence
│   └── broadcastSubs
└── authManager (AuthManager)
```

The Swift implementation has more separation of concerns, which is good, but needs to maintain the same behavioral semantics as the TypeScript version.

---

## Action Items Summary

| Priority | Issue | File(s) | Effort |
|----------|-------|---------|--------|
| 🔴 High | Fix async init race condition | `LocalFirstManager.swift` | Medium |
| 🔴 High | Fix attr/triple load order | `LocalFirstManager.swift` | Low |
| 🔴 High | Cancel reconnect task | `WebSocketConnection.swift` | Low |
| 🔴 High | Fix dictionary comparison | `PresenceManager.swift` | Medium |
| 🟡 Medium | Add error logging | Multiple files | Low |
| 🟡 Medium | Fix internal visibility | `PresenceManager.swift` | Low |
| 🟡 Medium | Add OSLog | Multiple files | Medium |
| 🟡 Medium | Fix storage/memory consistency | `LocalFirstManager.swift` | Medium |
| 🟢 Low | String enums for wire protocol | Multiple files | Medium |
| 🟢 Low | Generic presence types | `PresenceManager.swift` | High |
| 🟢 Low | Rename toJSON | `OptimisticUpdateManager.swift` | Low |
| 🟢 Low | Fix applyOptimisticUpdates return | `OptimisticUpdateManager.swift` | Medium |

---

## Conclusion

The PR adds significant functionality that closely follows the TypeScript implementation. The feedback focuses on making the code more Swift-idiomatic and robust:

1. **Safety**: Fix race conditions, proper error handling, reliable comparisons
2. **Clarity**: Better naming, correct documentation, proper visibility
3. **Maintainability**: Structured logging, type safety, dependency injection

Most fixes are straightforward. The highest priority items are the async initialization race condition and the dictionary comparison bug, as these can cause subtle runtime issues.

