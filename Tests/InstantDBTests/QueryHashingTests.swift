import XCTest

@testable import InstantDB

// MARK: - QueryHashingTests

final class QueryHashingTests: XCTestCase {
  func testHashIsDeterministicAndCanonical() {
    let queryA: [String: Any] = [
      "posts": [
        "author": [:],
        "$": [
          "where": ["id": "post-1"],
          "order": ["createdAt": "desc"],
          "first": 10,
        ],
      ],
    ]

    let queryB: [String: Any] = [
      "posts": [
        "$": [
          "first": 10,
          "order": ["createdAt": "desc"],
          "where": ["id": "post-1"],
        ],
        "author": [:],
      ],
    ]

    let hashA = QueryHashing.hash(queryA)
    let hashB = QueryHashing.hash(queryB)

    XCTAssertEqual(hashA, hashB)
    XCTAssertEqual(hashA.count, 64)
    XCTAssertTrue(hashA.allSatisfy { $0.isASCIIHexDigit })
  }
}

private extension Character {
  var isASCIIHexDigit: Bool {
    guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else { return false }
    switch scalar.value {
    case 48...57, 65...70, 97...102:
      return true
    default:
      return false
    }
  }
}

