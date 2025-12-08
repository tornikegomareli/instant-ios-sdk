import XCTest
@testable import InstantDB

final class PageInfoTests: XCTestCase {

  func testPageInfoParsingFromServerResponse() {
    let serverResponse: [String: Any] = [
      "goals": [
        "start-cursor": ["entity1", "attr1", "value1", 1000],
        "end-cursor": ["entity2", "attr2", "value2", 2000],
        "has-next-page?": true,
        "has-previous-page?": false
      ]
    ]

    let pageInfo = PageInfo(from: serverResponse, namespace: "goals")

    XCTAssertNotNil(pageInfo)
    XCTAssertNotNil(pageInfo?.startCursor)
    XCTAssertNotNil(pageInfo?.endCursor)
    XCTAssertTrue(pageInfo!.hasNextPage)
    XCTAssertFalse(pageInfo!.hasPreviousPage)
  }

  func testPageInfoWithNoCursors() {
    let serverResponse: [String: Any] = [
      "goals": [
        "has-next-page?": false,
        "has-previous-page?": false
      ]
    ]

    let pageInfo = PageInfo(from: serverResponse, namespace: "goals")

    XCTAssertNotNil(pageInfo)
    XCTAssertNil(pageInfo?.startCursor)
    XCTAssertNil(pageInfo?.endCursor)
    XCTAssertFalse(pageInfo!.hasNextPage)
    XCTAssertFalse(pageInfo!.hasPreviousPage)
  }

  func testPageInfoWithWrongNamespace() {
    let serverResponse: [String: Any] = [
      "goals": [
        "start-cursor": ["e", "a", "v", 1],
        "end-cursor": ["e", "a", "v", 2],
        "has-next-page?": true,
        "has-previous-page?": false
      ]
    ]

    let pageInfo = PageInfo(from: serverResponse, namespace: "todos")

    XCTAssertNil(pageInfo)
  }

  func testPageInfoWithNilDict() {
    let pageInfo = PageInfo(from: nil, namespace: "goals")
    XCTAssertNil(pageInfo)
  }

  func testPageInfoWithEmptyDict() {
    let pageInfo = PageInfo(from: [:], namespace: "goals")
    XCTAssertNil(pageInfo)
  }

  func testPageInfoDefaultsForMissingBooleans() {
    let serverResponse: [String: Any] = [
      "goals": [
        "start-cursor": ["e", "a", "v", 1],
        "end-cursor": ["e", "a", "v", 2]
      ]
    ]

    let pageInfo = PageInfo(from: serverResponse, namespace: "goals")

    XCTAssertNotNil(pageInfo)
    XCTAssertFalse(pageInfo!.hasNextPage)
    XCTAssertFalse(pageInfo!.hasPreviousPage)
  }

  func testPageInfoCursorValues() {
    let serverResponse: [String: Any] = [
      "items": [
        "start-cursor": ["start-entity", "start-attr", "start-val", 1111],
        "end-cursor": ["end-entity", "end-attr", "end-val", 2222],
        "has-next-page?": true,
        "has-previous-page?": true
      ]
    ]

    let pageInfo = PageInfo(from: serverResponse, namespace: "items")

    XCTAssertNotNil(pageInfo)

    let startValues = pageInfo!.startCursor!.toQueryValue()
    XCTAssertEqual(startValues[0] as? String, "start-entity")
    XCTAssertEqual(startValues[3] as? Int, 1111)

    let endValues = pageInfo!.endCursor!.toQueryValue()
    XCTAssertEqual(endValues[0] as? String, "end-entity")
    XCTAssertEqual(endValues[3] as? Int, 2222)
  }
}
