import XCTest

@testable import InstantDB

// MARK: - QueryOnceErrorTests

final class QueryOnceErrorTests: XCTestCase {
  private struct Todo: Codable, Equatable {
    let id: String
    let title: String
    let done: Bool
  }

  func testOfflineErrorCanDecodeLastKnownEntities() throws {
    let cachedPayload: [String: Any] = [
      "data": [
        "todos": [
          ["id": "todo-1", "title": "Cached", "done": false]
        ]
      ],
      "pageInfo": NSNull(),
    ]

    let cachedData = try JSONSerialization.data(withJSONObject: cachedPayload, options: [.sortedKeys])

    let error = QueryOnceError.offline(queryHash: "test-hash", lastKnownResult: cachedData)
    let decoded = error.decodeLastKnownEntities(Todo.self, from: "todos")

    XCTAssertEqual(decoded, [Todo(id: "todo-1", title: "Cached", done: false)])
  }
}

