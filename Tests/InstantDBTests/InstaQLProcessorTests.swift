import XCTest
@testable import InstantDB

final class InstaQLProcessorTests: XCTestCase {

  func testRefLinkInfersNamespaceWhenReverseIdentityMissing() {
    let postId = "post-1"
    let profileId = "profile-1"

    let authorAttr = Attribute(
      id: "attr-author",
      forwardIdentity: ["ident-author", "posts", "author"],
      reverseIdentity: nil,
      valueType: .ref,
      cardinality: .one,
      unique: false,
      indexed: false,
      checkedDataType: nil
    )

    let contentAttr = Attribute(
      id: "attr-content",
      forwardIdentity: ["ident-content", "posts", "content"],
      reverseIdentity: nil,
      valueType: .blob,
      cardinality: .one,
      unique: false,
      indexed: false,
      checkedDataType: nil
    )

    let displayNameAttr = Attribute(
      id: "attr-display-name",
      forwardIdentity: ["ident-display-name", "profiles", "displayName"],
      reverseIdentity: nil,
      valueType: .blob,
      cardinality: .one,
      unique: false,
      indexed: false,
      checkedDataType: nil
    )

    let result: [[String: Any]] = [
      [
        "data": [
          "datalog-result": [
            "join-rows": [
              [
                [postId, authorAttr.id, profileId],
                [postId, contentAttr.id, "Hello"],
                [profileId, displayNameAttr.id, "Alice"],
              ],
            ],
          ],
        ],
      ],
    ]

    let processed = InstaQLProcessor.process(
      result: result,
      attributes: [authorAttr, contentAttr, displayNameAttr],
      order: nil
    )

    guard let posts = processed["posts"] as? [[String: Any]] else {
      XCTFail("Expected processed InstaQL data to include a posts array")
      return
    }

    guard let post = posts.first(where: { ($0["id"] as? String) == postId }) else {
      XCTFail("Expected processed posts to include postId \(postId)")
      return
    }

    guard let author = post["author"] as? [String: Any] else {
      XCTFail("Expected post.author to be hydrated even without reverse identity metadata")
      return
    }

    XCTAssertEqual(author["id"] as? String, profileId)
    XCTAssertEqual(author["displayName"] as? String, "Alice")
  }
}

