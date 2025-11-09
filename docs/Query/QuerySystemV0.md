# InstantDB iOS SDK - Query System v0

## Overview

Version 0 of the query system implements **server-side query execution** without optimistic updates. This follows the admin SDK pattern where the server handles all query processing and returns structured JSON results.

## Architecture

```
[iOS App]
    ↓ subscribeQuery(["goals": [:]])
[InstantClient]
    ↓ registers callback with QueryManager
[QueryManager]
    ↓ stores subscription
[WebSocket]
    ↓ sends AddQueryMessage
[Server]
    ↓ executes InstaQL query
    ↓ returns structured JSON
[WebSocket]
    ↓ receives add-query-ok
[QueryManager]
    ↓ delivers QueryResult
[iOS App]
    ↓ receives callback with data
```

## Components

### 1. QueryResult (`Query/QueryResult.swift`)
- Wraps query response data
- Provides loading/error states
- Convenient subscript access for namespaces

### 2. QuerySubscription (`Query/QuerySubscription.swift`)
- Internal model for tracking subscriptions
- Manages multiple callbacks per query
- Caches current result

### 3. QueryManager (`Query/QueryManager.swift`)
- Manages all active subscriptions
- Deduplicates identical queries
- Routes server responses to callbacks
- Handles real-time updates (refresh-ok)

### 4. InstantClient Updates
- New `subscribeQuery(_:callback:)` method
- Returns unsubscribe function
- Integrates with QueryManager

## Usage

### Basic Query
```swift
let unsubscribe = try db.subscribeQuery(["goals": [:]]) { result in
  if let error = result.error {
    print("Query failed: \(error)")
  } else if let goals = result["goals"] {
    print("Got \(goals.count) goals")
  }
}

// Later...
unsubscribe()
```

### Query with Relationships
```swift
let query = [
  "goals": [
    "todos": [:]
  ]
]

try db.subscribeQuery(query) { result in
  if let goals = result["goals"] as? [[String: Any]] {
    for goal in goals {
      if let todos = goal["todos"] as? [[String: Any]] {
        print("Goal has \(todos.count) todos")
      }
    }
  }
}
```

### Query with Where Clause
```swift
let query = [
  "goals": [
    "$": [
      "where": ["id": goalId]
    ]
  ]
]

try db.subscribeQuery(query) { result in
  // Handle single goal result
}
```

## Real-time Updates

The system automatically handles `refresh-ok` messages from the server, delivering updated results through the same callback:

1. Initial query sent → `add-query-ok` → callback with data
2. Another client updates data → server sends `refresh-ok` → callback with new data
3. No additional code needed - just works!

## Limitations (v0)

This is a simplified v0 that doesn't include:

- ❌ Client-side triple store
- ❌ Optimistic updates
- ❌ Offline support
- ❌ Query caching beyond current session
- ❌ Local query execution

These features will be added in v1 when we implement the full client-side triple store.

## Testing

Use `QueryTestView.swift` in the example app to test:
1. Simple queries (goals, todos)
2. Nested queries (goals with todos)
3. Real-time updates (modify data from another client)
4. Unsubscribe functionality

## Next Steps (v1)

1. **Triple Store**: Implement client-side EAV/AEV/VAE indexes
2. **InstaQL Engine**: Port query execution to Swift
3. **Optimistic Updates**: Apply mutations locally before server confirmation
4. **Persistence**: Cache query results and pending mutations
5. **Offline Support**: Work without connection using cached data