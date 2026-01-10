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

  func testAnyCodableEquatableDeepComparison() throws {
    XCTAssertEqual(AnyCodable(true), AnyCodable(true))
    XCTAssertNotEqual(AnyCodable(true), AnyCodable(false))

    XCTAssertEqual(AnyCodable(1), AnyCodable(1))
    XCTAssertEqual(AnyCodable(1), AnyCodable(Int64(1)))
    XCTAssertEqual(AnyCodable(1), AnyCodable(1.0))

    XCTAssertEqual(
      AnyCodable(["a": 1, "b": "two", "c": true]),
      AnyCodable(["a": Int64(1), "b": "two", "c": true])
    )

    XCTAssertEqual(
      AnyCodable(["nested": ["items": [1, 2, 3], "flag": false]]),
      AnyCodable(["nested": ["items": [1, 2, 3], "flag": false]])
    )

    XCTAssertNotEqual(
      AnyCodable(["nested": ["items": [1, 2, 3], "flag": false]]),
      AnyCodable(["nested": ["items": [1, 2, 4], "flag": false]])
    )

    XCTAssertEqual(AnyCodable(NSNull()), AnyCodable(NSNull()))
    XCTAssertNotEqual(AnyCodable(NSNull()), AnyCodable("null"))
  }
}
