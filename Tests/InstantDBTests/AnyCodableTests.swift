import XCTest
@testable import InstantDB

final class AnyCodableTests: XCTestCase {

  func testTransactMessageEncodesNestedInt64Values() throws {
    let txSteps: [[Any]] = [[
      "update",
      "todos",
      "todo-1",
      ["createdAt": Int64(1_700_000_000_000)],
    ]]

    let message = TransactMessage(clientEventId: "event-1", txSteps: txSteps)

    XCTAssertNoThrow(try JSONEncoder().encode(message))
  }
}

