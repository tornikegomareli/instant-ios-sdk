import XCTest
@testable import InstantDB

final class TransactionTransformerTests: XCTestCase {
  
  // MARK: - Test Fixtures
  
  /// Creates a mock attribute with forward identity
  private func makeAttribute(
    id: String,
    entityType: String,
    label: String,
    valueType: ValueType = .blob,
    reverseIdentity: [String]? = nil
  ) -> Attribute {
    Attribute(
      id: id,
      forwardIdentity: [UUID().uuidString, entityType, label],
      reverseIdentity: reverseIdentity,
      valueType: valueType,
      cardinality: .one,
      unique: label == "id",
      indexed: false,
      checkedDataType: nil
    )
  }
  
  /// Creates a link attribute (has both forward and reverse identity)
  private func makeLinkAttribute(
    id: String,
    forwardEntity: String,
    forwardLabel: String,
    reverseEntity: String,
    reverseLabel: String
  ) -> Attribute {
    Attribute(
      id: id,
      forwardIdentity: [UUID().uuidString, forwardEntity, forwardLabel],
      reverseIdentity: [UUID().uuidString, reverseEntity, reverseLabel],
      valueType: .ref,
      cardinality: .many,
      unique: false,
      indexed: false,
      checkedDataType: nil
    )
  }
  
  // MARK: - Tests
  
  func testFindAttributeByForwardIdentity() throws {
    // Given: An attribute with forward identity "todos.title"
    let titleAttr = makeAttribute(id: "attr-title", entityType: "todos", label: "title")
    let attributes = [titleAttr]
    
    // When: We transform an update operation
    let chunk = TransactionChunk(
      namespace: "todos",
      id: "todo-1",
      ops: [["update", "todos", "todo-1", ["title": "Test"]]]
    )
    
    let (txSteps, _) = try TransactionTransformer.transform([chunk], attributes: attributes)
    
    // Then: It should use the existing attribute ID
    // The steps should include add-triple with the attribute ID
    let addTripleSteps = txSteps.filter { ($0.first as? String) == "add-triple" }
    XCTAssertFalse(addTripleSteps.isEmpty, "Should have add-triple steps")
    
    // Find the title triple
    let titleTriple = addTripleSteps.first { step in
      step.count >= 4 && (step[2] as? String) == titleAttr.id
    }
    XCTAssertNotNil(titleTriple, "Should find title triple using existing attribute ID")
  }
  
  func testFindAttributeByReverseIdentity() throws {
    // Given: A link attribute where "author" is the REVERSE label on "posts"
    // This simulates the profilePosts link: profiles.posts <-> posts.author
    let linkAttr = makeLinkAttribute(
      id: "attr-profilePosts",
      forwardEntity: "profiles",
      forwardLabel: "posts",
      reverseEntity: "posts",
      reverseLabel: "author"
    )
    let attributes = [linkAttr]
    
    // When: We transform a link operation for posts.author
    let chunk = TransactionChunk(
      namespace: "posts",
      id: "post-1",
      ops: [["link", "posts", "post-1", ["author": "profile-1"]]]
    )
    
    let (txSteps, newAttributes) = try TransactionTransformer.transform([chunk], attributes: attributes)
    
    // Then: It should find the existing link attribute via reverse identity
    // and NOT create a new attribute
    XCTAssertTrue(newAttributes.isEmpty, "Should not create new attributes when link attribute exists")
    
    // The add-triple should use the existing link attribute ID
    let addTripleSteps = txSteps.filter { ($0.first as? String) == "add-triple" }
    let linkTriple = addTripleSteps.first { step in
      step.count >= 4 && (step[2] as? String) == linkAttr.id
    }
    XCTAssertNotNil(linkTriple, "Should use existing link attribute ID for reverse link")
  }
  
  func testCreateNewAttributeWhenNotFound() throws {
    // Given: No existing attributes
    let attributes: [Attribute] = []
    
    // When: We transform an update with a new field
    let chunk = TransactionChunk(
      namespace: "todos",
      id: "todo-1",
      ops: [["update", "todos", "todo-1", ["newField": "value"]]]
    )
    
    let (txSteps, newAttributes) = try TransactionTransformer.transform([chunk], attributes: attributes)
    
    // Then: It should create a new attribute
    XCTAssertEqual(newAttributes.count, 2, "Should create attributes for 'id' and 'newField'")
    
    // And add-attr steps should be first
    let addAttrSteps = txSteps.filter { ($0.first as? String) == "add-attr" }
    XCTAssertFalse(addAttrSteps.isEmpty, "Should have add-attr steps for new attributes")
  }
  
  func testLinkOperationWithForwardIdentity() throws {
    // Given: A link attribute where "posts" is the FORWARD label on "profiles"
    let linkAttr = makeLinkAttribute(
      id: "attr-profilePosts",
      forwardEntity: "profiles",
      forwardLabel: "posts",
      reverseEntity: "posts",
      reverseLabel: "author"
    )
    let attributes = [linkAttr]
    
    // When: We transform a link operation for profiles.posts (forward direction)
    let chunk = TransactionChunk(
      namespace: "profiles",
      id: "profile-1",
      ops: [["link", "profiles", "profile-1", ["posts": "post-1"]]]
    )
    
    let (txSteps, newAttributes) = try TransactionTransformer.transform([chunk], attributes: attributes)
    
    // Then: It should find the existing link attribute via forward identity
    XCTAssertTrue(newAttributes.isEmpty, "Should not create new attributes when link attribute exists")
    
    // The add-triple should use the existing link attribute ID
    let addTripleSteps = txSteps.filter { ($0.first as? String) == "add-triple" }
    let linkTriple = addTripleSteps.first { step in
      step.count >= 4 && (step[2] as? String) == linkAttr.id
    }
    XCTAssertNotNil(linkTriple, "Should use existing link attribute ID for forward link")
  }
  
  func testLinkOperationWithMultipleIds() throws {
    // Given: A link attribute
    let linkAttr = makeLinkAttribute(
      id: "attr-profilePosts",
      forwardEntity: "profiles",
      forwardLabel: "posts",
      reverseEntity: "posts",
      reverseLabel: "author"
    )
    let attributes = [linkAttr]
    
    // When: We link multiple posts to a profile
    let chunk = TransactionChunk(
      namespace: "profiles",
      id: "profile-1",
      ops: [["link", "profiles", "profile-1", ["posts": ["post-1", "post-2", "post-3"]]]]
    )
    
    let (txSteps, _) = try TransactionTransformer.transform([chunk], attributes: attributes)
    
    // Then: It should create an add-triple for each linked ID
    let addTripleSteps = txSteps.filter { ($0.first as? String) == "add-triple" }
    let linkTriples = addTripleSteps.filter { step in
      step.count >= 4 && (step[2] as? String) == linkAttr.id
    }
    XCTAssertEqual(linkTriples.count, 3, "Should create 3 link triples for 3 posts")
  }
  
  func testUpdateOperationPreservesIdAttribute() throws {
    // Given: An id attribute
    let idAttr = makeAttribute(id: "attr-id", entityType: "todos", label: "id")
    let attributes = [idAttr]
    
    // When: We transform an update
    let chunk = TransactionChunk(
      namespace: "todos",
      id: "todo-1",
      ops: [["update", "todos", "todo-1", ["title": "Test"]]]
    )
    
    let (txSteps, _) = try TransactionTransformer.transform([chunk], attributes: attributes)
    
    // Then: The id triple should be included
    let addTripleSteps = txSteps.filter { ($0.first as? String) == "add-triple" }
    let idTriple = addTripleSteps.first { step in
      step.count >= 4 && (step[2] as? String) == idAttr.id
    }
    XCTAssertNotNil(idTriple, "Should include id triple in update")
  }
}

