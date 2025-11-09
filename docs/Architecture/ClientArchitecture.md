# InstantDB Client Architecture

## Overview

This document explains how the React/React Native client works and serves as a blueprint for the iOS SDK implementation.

**Key Insight:** InstantDB clients maintain a **client-side triple store** that syncs with the server. Queries run **locally** against this triple store, not against the server directly.

---

## Architecture Layers

```
┌─────────────────────────────────────────────┐
│   Developer-Facing API (InstaQL DSL)       │
│   db.useQuery({ goals: { todos: {} } })    │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│   Reactor (Orchestration Layer)             │
│   - Query subscriptions                     │
│   - Mutation queue                          │
│   - Optimistic updates                      │
│   - Network sync                            │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│   InstaQL Query Engine                      │
│   - Converts InstaQL → Datalog              │
│   - Runs queries against local store        │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│   Triple Store (store.js)                  │
│   - EAV, AEV, VAE indexes                  │
│   - Triple operations (add/retract)        │
│   - In-memory + IndexedDB persistence      │
└─────────────────────────────────────────────┘
```

---

## Component Deep Dive

### 1. Triple Store (store.js)

**File:** `/client/packages/core/src/store.js`

#### Data Structure

Triples are stored as: `[entity_id, attribute_id, value, timestamp]`

Three indexes provide O(1) lookups:
- **EAV** (Entity-Attribute-Value): `Map<entity, Map<attribute, Map<value, triple>>>`
- **AEV** (Attribute-Entity-Value): `Map<attribute, Map<entity, Map<value, triple>>>`
- **VAE** (Value-Attribute-Entity): `Map<value, Map<attribute, Map<entity, triple>>>` (for refs only)

#### Core Operations

```javascript
// Create store
const store = createStore(attrs, triples, cardinalityInference, linkIndex, useDateObjects)

// Add triple (for optimistic updates)
addTriple(store, [entityId, attrId, value])

// Remove triple
retractTriple(store, [entityId, attrId, value])

// Delete entire entity
deleteEntity(store, [entityId, entityType])

// Query triples
getTriples(store, [e, a, v]) // Any combination of e/a/v can be undefined
```

#### Key Features

1. **Cardinality enforcement**: Attributes marked as `cardinality: 'one'` automatically replace existing values
2. **Ref tracking**: Reference attributes are indexed in VAE for reverse lookups
3. **Timestamp tracking**: Each triple has `createdAt` for ordering
4. **Immutable updates**: Uses `mutative` library for structural sharing
5. **Lookup refs**: Support for `[attrId, value]` style entity references

#### iOS Implementation Notes

- Use Swift value types (structs) where possible
- Consider `Dictionary<Key, Dictionary<Key, Dictionary<Key, Triple>>>` for indexes
- Use `Codable` for persistence to file system or Core Data
- Implement copy-on-write for efficient updates

---

### 2. InstaQL Query Engine (instaql.js)

**File:** `/client/packages/core/src/instaql.js`

#### Query Translation Flow

```
InstaQL JSON
    ↓
Parse query structure
    ↓
Generate Datalog patterns
    ↓
Execute against triple store
    ↓
Assemble nested result objects
```

#### Example Translation

**InstaQL:**
```javascript
{
  goals: {
    $: { where: { id: "123" } },
    todos: {}
  }
}
```

**Datalog (conceptual):**
```clojure
[:find ?goal
 :where
 [?goal goal/id "123"]
 [?goal goal/todos ?todo]]
```

**Execution:**
1. Find entity with `goal/id = "123"`
2. Find all triples where goal is entity
3. Find all todos linked to goal
4. Assemble into nested structure

#### Where Clause Features

- **Simple filters**: `{ id: "123" }`
- **Comparison**: `{ age: { $gt: 18 } }`
- **Pattern matching**: `{ title: { $like: "%promoted%" } }`
- **Null checks**: `{ location: { $isNull: false } }`
- **OR/AND**: `{ or: [{...}, {...}] }`
- **$in**: `{ status: { $in: ["active", "pending"] } }`
- **Nested paths**: `{ 'todos.title': 'Code' }` (filter by related entity)

#### iOS Implementation Notes

- Build result builder DSL for query construction
- Use Swift keypaths for type-safe field access
- Implement Datalog-style pattern matching
- Cache query plans for repeated queries

---

### 3. Reactor (Reactor.js)

**File:** `/client/packages/core/src/Reactor.js`

The orchestrator that manages everything.

#### Core Responsibilities

##### A. Query Subscriptions

```javascript
// User subscribes to query
subscribeQuery(q, callback)
  ↓
// Generate hash of query
hash = weakHash(q)
  ↓
// Store subscription
querySubs[hash] = { q, result: null, eventId }
  ↓
// Send to server (if not cached)
send({ op: 'add-query', q })
  ↓
// Server responds with triples
receive({ op: 'add-query-ok', result: [...triples...] })
  ↓
// Store triples in local triple store
store = createStore(attrs, triples)
querySubs[hash].result = { store, pageInfo, aggregate }
  ↓
// Run InstaQL against local store
data = instaql(store, q)
  ↓
// Call callback with result
callback(data)
```

**Key insight:** Subsequent renders query the **local store**, not the server.

##### B. Optimistic Updates

```javascript
// User calls transact
pushTx([{ goals: { id123: { update: { title: 'New' } } } }])
  ↓
// Convert to tx-steps
txSteps = [['add-triple', 'id123', 'attr-title', 'New']]
  ↓
// Store in pending mutations
pendingMutations.set(eventId, { txSteps, created: Date.now() })
  ↓
// Apply optimistically to local store
newStore = applyOptimisticUpdates(store, pendingMutations)
  ↓
// Re-run queries
data = instaql(newStore, q)
  ↓
// UI updates IMMEDIATELY
callback(data)
  ↓
// Send to server in background
send({ op: 'transact', 'tx-steps': txSteps })
  ↓
// Server confirms
receive({ op: 'transact-ok', 'tx-id': txId })
  ↓
// Mark mutation as confirmed
pendingMutations.get(eventId)['tx-id'] = txId
```

**Key insight:** UI updates before server confirmation, then reconciles.

##### C. Real-time Sync

```javascript
// Server sends update
receive({ op: 'refresh-ok', computations: [...] })
  ↓
// Extract new triples
triples = extractTriples(computations)
  ↓
// Create new store
newStore = createStore(attrs, triples)
  ↓
// Apply pending optimistic updates on top
finalStore = applyOptimisticUpdates(newStore, pendingMutations)
  ↓
// Re-run all active queries
for (hash in querySubs) {
  data = instaql(finalStore, querySubs[hash].q)
  callback(data)
}
  ↓
// UI automatically updates
```

**Key insight:** Server sends incremental updates, client merges with optimistic state.

##### D. Persistence

```javascript
// Queries persisted to IndexedDB
querySubs → querySubsToStorage() → IndexedDB
  ↓
// On app restart
IndexedDB → querySubsFromStorage() → querySubs
  ↓
// Queries work immediately from cache
data = instaql(cachedStore, q)
callback(data)
  ↓
// Then sync with server in background
```

**Key features:**
- Top 10 queries cached by `lastAccessed`
- Pending mutations persisted (queue survives restart)
- Store serialized as JSON (triples + attrs)

#### iOS Implementation Notes

- Use Combine for reactive subscriptions
- Persist to file system (JSON) or Core Data
- Use `URLSession` for WebSocket
- Implement exponential backoff for reconnection
- Use `@Published` properties for state updates

---

### 4. Network Protocol

#### Message Types (Client → Server)

```javascript
// Initialize connection
{ op: 'init', 'app-id': uuid, 'client-version': '0.0.1' }

// Subscribe to query
{ op: 'add-query', q: { goals: {} }, 'event-id': uuid }

// Unsubscribe from query
{ op: 'remove-query', q: { goals: {} }, 'event-id': uuid }

// Send transaction
{ op: 'transact', 'tx-steps': [...], 'client-event-id': uuid }

// Join room (presence)
{ op: 'join-room', 'room-id': 'room-123' }
```

#### Message Types (Server → Client)

```javascript
// Connection established
{ op: 'init-ok', attrs: [...], 'session-id': uuid }

// Query result
{
  op: 'add-query-ok',
  q: { goals: {} },
  result: [{
    data: { triples: [[e, a, v, t], ...] }
  }],
  'processed-tx-id': 123
}

// Real-time update
{
  op: 'refresh-ok',
  attrs: [...],
  computations: [{
    'instaql-query': { goals: {} },
    'instaql-result': [{ data: { triples: [...] } }]
  }],
  'processed-tx-id': 124
}

// Transaction confirmed
{ op: 'transact-ok', 'client-event-id': uuid, 'tx-id': 124 }

// Error
{ op: 'error', message: '...', hint: {...}, 'original-event': {...} }
```

---

## Data Flow Examples

### Example 1: Query Execution

```
User Code:
  db.useQuery({ goals: { todos: {} } })
     ↓
Reactor:
  hash = "abc123"
  if (!querySubs[hash]) {
    querySubs[hash] = { q, result: null }
    send('add-query', q)
  }
     ↓
Server:
  - Receives query
  - Translates to triple lookups
  - Returns triples
     ↓
Reactor:
  receive('add-query-ok')
  store = createStore(triples)
  querySubs[hash].result = { store }
     ↓
InstaQL:
  data = instaql(store, q)
  // Runs locally against triple store!
     ↓
User Code:
  callback({ goals: [...with nested todos...] })
```

### Example 2: Optimistic Update

```
User Code:
  db.transact(tx.goals[id].update({ title: 'New' }))
     ↓
Reactor:
  txSteps = [['add-triple', id, attr-title-id, 'New']]
  pendingMutations[eventId] = { txSteps }
     ↓
Store:
  optimisticStore = transact(store, txSteps)
     ↓
InstaQL:
  data = instaql(optimisticStore, q)
     ↓
User Code:
  callback({ goals: [{ title: 'New' }] }) // IMMEDIATE!
     ↓
Reactor (background):
  send('transact', txSteps)
     ↓
Server:
  - Validates
  - Persists
  - Broadcasts to other clients
  - Responds with tx-id
     ↓
Reactor:
  receive('transact-ok')
  pendingMutations[eventId]['tx-id'] = txId
  // Query re-runs, but result is same
```

### Example 3: Real-time Sync from Another Client

```
Another Client:
  transact({ goals: [{ update: { title: 'Changed' } }] })
     ↓
Server:
  - Persists mutation
  - Sends refresh-ok to all subscribers
     ↓
This Client Reactor:
  receive('refresh-ok')
  newTriples = extract(computations)
  store = createStore(newTriples)
     ↓
  // Merge with local optimistic updates
  finalStore = applyOptimisticUpdates(store, pendingMutations)
     ↓
InstaQL:
  data = instaql(finalStore, q)
     ↓
User Code:
  callback({ goals: [{ title: 'Changed' }] }) // Auto-updates!
```

---

## iOS Implementation Roadmap

### Phase 1: Foundation (Week 1-2)
- [ ] Triple store with EAV/AEV/VAE indexes
- [ ] Basic triple operations (add/retract/delete)
- [ ] Store serialization/deserialization
- [ ] Unit tests for store operations

### Phase 2: InstaQL Engine (Week 3-4)
- [ ] InstaQL JSON parser
- [ ] Query → Datalog translation
- [ ] Pattern matching against store
- [ ] Result assembly with nested relationships
- [ ] Support for where clauses, pagination, ordering

### Phase 3: Network Layer (Week 5-6)
- [ ] WebSocket connection management
- [ ] Message serialization (JSON)
- [ ] Connection lifecycle (init, auth, reconnect)
- [ ] Error handling
- [ ] Offline detection

### Phase 4: Reactor (Week 7-9)
- [ ] Query subscription management
- [ ] Pending mutations queue
- [ ] Optimistic updates
- [ ] Real-time sync handling
- [ ] State reconciliation

### Phase 5: Persistence (Week 10)
- [ ] File-based or Core Data persistence
- [ ] Query cache management
- [ ] Pending mutations persistence
- [ ] Migration handling

### Phase 6: DSL (Week 11-12)
- [ ] Swift result builder for queries
- [ ] Transaction builder DSL
- [ ] Type-safe schema integration
- [ ] SwiftUI integration hooks

### Phase 7: Polish (Week 13-14)
- [ ] Error handling improvements
- [ ] Performance optimization
- [ ] Memory management
- [ ] Documentation
- [ ] Example apps

---

## Key Differences for iOS

### 1. Memory Management
- JavaScript: Garbage collected
- iOS: Use weak references for callbacks, careful with retain cycles

### 2. Persistence
- JavaScript: IndexedDB (built-in)
- iOS: FileManager (JSON files) or Core Data

### 3. Reactivity
- JavaScript: Callbacks
- iOS: Combine publishers + @Published properties

### 4. Networking
- JavaScript: WebSocket API
- iOS: URLSessionWebSocketTask

### 5. Background Tasks
- JavaScript: Web Workers (optional)
- iOS: Background URLSession for persistence

### 6. Type Safety
- JavaScript: TypeScript (optional)
- iOS: Swift type system is mandatory and more powerful

---

## Reference Files

Essential files to study:

1. **store.js** - Triple store implementation
2. **Reactor.js** - Orchestration and sync
3. **instaql.js** - Query engine
4. **instaml.js** - Transaction transformation
5. **datalog.js** - Pattern matching
6. **Connection.ts** - WebSocket/SSE handling
7. **IndexedDBStorage.ts** - Persistence

---

## Summary

The InstantDB client is essentially:

1. **A local triple store** that mirrors server state
2. **A query engine** that runs InstaQL against the local store
3. **An orchestrator** that keeps local and remote state in sync
4. **A persistence layer** for offline support
5. **A developer-friendly API** that hides all complexity

The iOS SDK must replicate all of these components using Swift idioms and iOS frameworks.
