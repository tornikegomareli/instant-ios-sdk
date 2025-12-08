import XCTest
@testable import InstantDB

final class CursorTests: XCTestCase {
  func testCursorInitFromArray() {
    let array: [Any] = [
      "entity-id-123",
      "attr-id-456",
      "some-value",
      1718118155976
    ]

    let cursor = Cursor(from: array)
    XCTAssertEqual(cursor.values.count, 4)
  }

  func testCursorToQueryValue() {
    let array: [Any] = [
      "entity-id-123",
      "attr-id-456",
      "test-value",
      1234567890
    ]

    let cursor = Cursor(from: array)
    let queryValue = cursor.toQueryValue()

    XCTAssertEqual(queryValue.count, 4)
    XCTAssertEqual(queryValue[0] as? String, "entity-id-123")
    XCTAssertEqual(queryValue[1] as? String, "attr-id-456")
    XCTAssertEqual(queryValue[2] as? String, "test-value")
    XCTAssertEqual(queryValue[3] as? Int, 1234567890)
  }

  func testCursorEquality() {
    let array1: [Any] = ["a", "b", "c", 123]
    let array2: [Any] = ["a", "b", "c", 123]
    let array3: [Any] = ["x", "y", "z", 999]

    let cursor1 = Cursor(from: array1)
    let cursor2 = Cursor(from: array2)
    let cursor3 = Cursor(from: array3)

    XCTAssertEqual(cursor1, cursor2)
    XCTAssertNotEqual(cursor1, cursor3)
  }

  func testCursorHashable() {
    let array1: [Any] = ["a", "b", "c", 123]
    let array2: [Any] = ["a", "b", "c", 123]

    let cursor1 = Cursor(from: array1)
    let cursor2 = Cursor(from: array2)

    var set = Set<Cursor>()
    set.insert(cursor1)
    set.insert(cursor2)

    XCTAssertEqual(set.count, 1)
  }

  func testCursorWithDifferentValueTypes() {
    let arrayWithInt: [Any] = ["id", "attr", 42, 1000]
    let arrayWithDouble: [Any] = ["id", "attr", 3.14, 1000]
    let arrayWithBool: [Any] = ["id", "attr", true, 1000]

    let cursor1 = Cursor(from: arrayWithInt)
    let cursor2 = Cursor(from: arrayWithDouble)
    let cursor3 = Cursor(from: arrayWithBool)

    XCTAssertEqual(cursor1.toQueryValue()[2] as? Int, 42)
    XCTAssertEqual(cursor2.toQueryValue()[2] as? Double, 3.14)
    XCTAssertEqual(cursor3.toQueryValue()[2] as? Bool, true)
  }
}
