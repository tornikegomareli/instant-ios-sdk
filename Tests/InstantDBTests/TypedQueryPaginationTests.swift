import XCTest
@testable import InstantDB

final class TypedQueryPaginationTests: XCTestCase {

  func testFirstModifiesQuery() {
    let query = TypedQuery<MockEntity>(namespace: "items").first(10)

    XCTAssertEqual(query.firstValue, 10)
    XCTAssertNil(query.lastValue)
  }

  func testLastModifiesQuery() {
    let query = TypedQuery<MockEntity>(namespace: "items").last(5)

    XCTAssertEqual(query.lastValue, 5)
    XCTAssertNil(query.firstValue)
  }

  func testAfterAddsCursor() {
    let cursor = Cursor(from: ["entity", "attr", "value", 1000])
    let query = TypedQuery<MockEntity>(namespace: "items").after(cursor)

    XCTAssertNotNil(query.afterCursor)
    XCTAssertNil(query.beforeCursor)
    XCTAssertEqual(query.afterCursor, cursor)
  }

  func testBeforeAddsCursor() {
    let cursor = Cursor(from: ["entity", "attr", "value", 2000])
    let query = TypedQuery<MockEntity>(namespace: "items").before(cursor)

    XCTAssertNotNil(query.beforeCursor)
    XCTAssertNil(query.afterCursor)
    XCTAssertEqual(query.beforeCursor, cursor)
  }

  func testOrderByFieldName() {
    let query = TypedQuery<MockEntity>(namespace: "items").order(by: "title", .asc)

    XCTAssertNotNil(query.orderValue)
    XCTAssertEqual(query.orderValue?["title"], "asc")
  }

  func testOrderByFieldNameDesc() {
    let query = TypedQuery<MockEntity>(namespace: "items").order(by: "createdAt", .desc)

    XCTAssertNotNil(query.orderValue)
    XCTAssertEqual(query.orderValue?["createdAt"], "desc")
  }

  func testToQueryIncludesFirst() {
    let query = TypedQuery<MockEntity>(namespace: "items").first(10)
    let dict = query.toQuery()

    let inner = dict["items"] as? [String: Any]
    let modifiers = inner?["$"] as? [String: Any]

    XCTAssertEqual(modifiers?["first"] as? Int, 10)
  }

  func testToQueryIncludesLast() {
    let query = TypedQuery<MockEntity>(namespace: "items").last(5)
    let dict = query.toQuery()

    let inner = dict["items"] as? [String: Any]
    let modifiers = inner?["$"] as? [String: Any]

    XCTAssertEqual(modifiers?["last"] as? Int, 5)
  }

  func testToQueryIncludesAfterCursor() {
    let cursor = Cursor(from: ["e1", "a1", "v1", 1234])
    let query = TypedQuery<MockEntity>(namespace: "items").after(cursor)
    let dict = query.toQuery()

    let inner = dict["items"] as? [String: Any]
    let modifiers = inner?["$"] as? [String: Any]
    let afterArray = modifiers?["after"] as? [Any]

    XCTAssertNotNil(afterArray)
    XCTAssertEqual(afterArray?.count, 4)
    XCTAssertEqual(afterArray?[0] as? String, "e1")
    XCTAssertEqual(afterArray?[3] as? Int, 1234)
  }

  func testToQueryIncludesBeforeCursor() {
    let cursor = Cursor(from: ["e2", "a2", "v2", 5678])
    let query = TypedQuery<MockEntity>(namespace: "items").before(cursor)
    let dict = query.toQuery()

    let inner = dict["items"] as? [String: Any]
    let modifiers = inner?["$"] as? [String: Any]
    let beforeArray = modifiers?["before"] as? [Any]

    XCTAssertNotNil(beforeArray)
    XCTAssertEqual(beforeArray?.count, 4)
    XCTAssertEqual(beforeArray?[0] as? String, "e2")
  }

  func testToQueryIncludesOrder() {
    let query = TypedQuery<MockEntity>(namespace: "items").order(by: "title", .asc)
    let dict = query.toQuery()

    let inner = dict["items"] as? [String: Any]
    let modifiers = inner?["$"] as? [String: Any]
    let order = modifiers?["order"] as? [String: String]

    XCTAssertEqual(order?["title"], "asc")
  }

  func testChainedPaginationQuery() {
    let cursor = Cursor(from: ["e", "a", "v", 999])
    let query = TypedQuery<MockEntity>(namespace: "items")
      .order(by: "title", .asc)
      .first(10)
      .after(cursor)

    let dict = query.toQuery()

    let inner = dict["items"] as? [String: Any]
    let modifiers = inner?["$"] as? [String: Any]

    XCTAssertEqual(modifiers?["first"] as? Int, 10)
    XCTAssertNotNil(modifiers?["after"])
    XCTAssertNotNil(modifiers?["order"])

    let order = modifiers?["order"] as? [String: String]
    XCTAssertEqual(order?["title"], "asc")
  }

  func testQueryPreservesWhereWithPagination() {
    let query = TypedQuery<MockEntity>(namespace: "items")
      .where { $0.title == "Test" }
      .first(5)

    let dict = query.toQuery()

    let inner = dict["items"] as? [String: Any]
    let modifiers = inner?["$"] as? [String: Any]

    XCTAssertNotNil(modifiers?["where"])
    XCTAssertEqual(modifiers?["first"] as? Int, 5)
  }

  func testFullPaginationQuery() {
    let afterCursor = Cursor(from: ["e1", "a1", "v1", 1000])

    let query = TypedQuery<MockEntity>(namespace: "goals")
      .order(by: "title", .asc)
      .first(20)
      .after(afterCursor)

    let dict = query.toQuery()

    let inner = dict["goals"] as? [String: Any]
    XCTAssertNotNil(inner)

    let modifiers = inner?["$"] as? [String: Any]
    XCTAssertNotNil(modifiers)

    XCTAssertEqual(modifiers?["first"] as? Int, 20)

    let order = modifiers?["order"] as? [String: String]
    XCTAssertEqual(order?["title"], "asc")

    let after = modifiers?["after"] as? [Any]
    XCTAssertEqual(after?.count, 4)
  }
}

struct MockEntity: InstantEntity {
  static var namespace: String { "items" }

  var id: String
  var title: String?
  var createdAt: Int?
}
