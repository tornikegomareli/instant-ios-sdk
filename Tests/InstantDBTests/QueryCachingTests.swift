import XCTest

@testable import InstantDB

// MARK: - QueryCachingTests

final class QueryCachingTests: XCTestCase {
  @MainActor
  func testSubscribeDeliversCachedResultBeforeLoading() async throws {
    let storage = try LocalStorage.inMemory(appId: "test-app")
    let manager = QueryManager(localStorage: storage)

    let query: [String: Any] = [
      "todos": [
        "$": ["where": ["done": false]],
      ],
    ]

    let hash = QueryHashing.hash(query)
    let queryData = try XCTUnwrap(QueryHashing.canonicalJSONData(query))

    let cachedPayload: [String: Any] = [
      "data": [
        "todos": [
          ["id": "todo-1", "title": "Cached", "done": false]
        ]
      ],
      "pageInfo": NSNull(),
    ]

    let cachedResultData = try JSONSerialization.data(withJSONObject: cachedPayload, options: [.sortedKeys])
    try await storage.cacheQueryResult(hash: hash, query: queryData, result: cachedResultData)

    var received: QueryResult?
    _ = manager.subscribe(query: query) { result in
      received = result
    }

    let result = try XCTUnwrap(received)
    XCTAssertFalse(result.isLoading)
    XCTAssertNil(result.error)
    XCTAssertEqual(result.get("todos").count, 1)
    XCTAssertEqual(result.get("todos").first?["id"] as? String, "todo-1")
  }
}

