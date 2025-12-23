import XCTest
@testable import InstantDB

final class PendingMutationsPersistenceTests: XCTestCase {

  func testNextPendingMutationOrderIndexStartsAtOneAndIncrements() async throws {
    let storage = try LocalStorage.inMemory(appId: "pending-mutations-order")

    let first = try await storage.nextPendingMutationOrderIndex()
    XCTAssertEqual(first, 1)

    let mutation = PendingMutation(
      eventId: "event-1",
      txSteps: [["update", "todos", "todo-1", ["done": true]]],
      createdAt: Date(),
      order: first
    )
    try await storage.savePendingMutation(mutation)

    let second = try await storage.nextPendingMutationOrderIndex()
    XCTAssertEqual(second, 2)
  }

  func testMarkPendingMutationConfirmedPersistsTxIdAndTimestamp() async throws {
    let storage = try LocalStorage.inMemory(appId: "pending-mutations-confirmed")

    let order = try await storage.nextPendingMutationOrderIndex()
    let mutation = PendingMutation(
      eventId: "event-1",
      txSteps: [["update", "todos", "todo-1", ["done": true]]],
      createdAt: Date(),
      order: order
    )
    try await storage.savePendingMutation(mutation)

    let confirmedAt = Date(timeIntervalSince1970: 1_700_000_000)
    try await storage.markPendingMutationConfirmed(eventId: "event-1", txId: 123, confirmedAt: confirmedAt)

    let loaded = try await storage.loadPendingMutations()
    guard let mutation = loaded.first else {
      XCTFail("Expected one pending mutation to be persisted")
      return
    }

    XCTAssertEqual(loaded.count, 1)
    XCTAssertEqual(mutation.eventId, "event-1")
    XCTAssertEqual(mutation.txId, 123)

    guard let persistedConfirmedAt = mutation.confirmedAt else {
      XCTFail("Expected confirmedAt to be set after transact-ok persistence")
      return
    }

    XCTAssertLessThan(
      abs(persistedConfirmedAt.timeIntervalSince1970 - confirmedAt.timeIntervalSince1970),
      0.001
    )
  }

  func testMarkPendingMutationErroredPersistsErrorMessage() async throws {
    let storage = try LocalStorage.inMemory(appId: "pending-mutations-error")

    let order = try await storage.nextPendingMutationOrderIndex()
    let mutation = PendingMutation(
      eventId: "event-1",
      txSteps: [["update", "todos", "todo-1", ["done": true]]],
      createdAt: Date(),
      order: order
    )
    try await storage.savePendingMutation(mutation)

    try await storage.markPendingMutationErrored(eventId: "event-1", error: "nope")

    let loaded = try await storage.loadPendingMutations()
    guard let mutation = loaded.first else {
      XCTFail("Expected one pending mutation to be persisted")
      return
    }

    XCTAssertEqual(loaded.count, 1)
    XCTAssertEqual(mutation.eventId, "event-1")
    XCTAssertEqual(mutation.error, "nope")
  }
}
