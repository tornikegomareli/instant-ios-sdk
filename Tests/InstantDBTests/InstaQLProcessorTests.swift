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
  
  // MARK: - Reverse Link Tests
  
  /// Tests that reverse links with `unique? = false` (has-many) are stored as arrays.
  ///
  /// Schema: mediaFilesMedia link
  /// - Forward: MediaFile.media has "one" (cardinality = one)
  /// - Reverse: Media.files has "many" (unique? = false)
  ///
  /// Server encoding (instant/server/src/instant/model/schema.clj lines 199-200):
  /// ```clojure
  /// :cardinality (keyword (:has forward))  ; "one"
  /// :unique?     (= "one" (:has reverse))  ; false (reverse has "many")
  /// ```
  func testReverseLinkWithHasManyIsStoredAsArray() {
    let mediaId = "media-1"
    let fileId1 = "file-1"
    let fileId2 = "file-2"
    
    // Link attribute: MediaFile.media -> Media
    // Forward: cardinality = one (MediaFile has one Media)
    // Reverse: unique? = false (Media has many files)
    let mediaLinkAttr = Attribute(
      id: "attr-media-link",
      forwardIdentity: ["ident-media-link", "mediaFiles", "media"],
      reverseIdentity: ["ident-files-link", "media", "files"],
      valueType: .ref,
      cardinality: .one,  // Forward cardinality
      unique: false,      // Reverse has "many" (not "one"), so unique? = false
      indexed: false,
      checkedDataType: nil
    )
    
    let mediaTitleAttr = Attribute(
      id: "attr-media-title",
      forwardIdentity: ["ident-title", "media", "title"],
      reverseIdentity: nil,
      valueType: .blob,
      cardinality: .one,
      unique: false,
      indexed: false,
      checkedDataType: nil
    )
    
    let filePathAttr = Attribute(
      id: "attr-file-path",
      forwardIdentity: ["ident-path", "mediaFiles", "path"],
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
                // Media entity
                [mediaId, mediaTitleAttr.id, "Test Recording"],
                // MediaFile entities linking to Media
                [fileId1, mediaLinkAttr.id, mediaId],
                [fileId1, filePathAttr.id, "/path/to/file1.m4a"],
                [fileId2, mediaLinkAttr.id, mediaId],
                [fileId2, filePathAttr.id, "/path/to/file2.m4a"],
              ],
            ],
          ],
        ],
      ],
    ]
    
    let processed = InstaQLProcessor.process(
      result: result,
      attributes: [mediaLinkAttr, mediaTitleAttr, filePathAttr],
      order: nil
    )
    
    // Verify Media entity exists
    guard let mediaEntities = processed["media"] as? [[String: Any]] else {
      XCTFail("Expected processed InstaQL data to include a media array")
      return
    }
    
    guard let media = mediaEntities.first(where: { ($0["id"] as? String) == mediaId }) else {
      XCTFail("Expected processed media to include mediaId \(mediaId)")
      return
    }
    
    // KEY TEST: Reverse link "files" should be an ARRAY (because unique? = false)
    guard let files = media["files"] as? [[String: Any]] else {
      XCTFail("Expected media.files to be an array (reverse link with unique? = false should be array)")
      return
    }
    
    XCTAssertEqual(files.count, 2, "Expected 2 files in the array")
    
    let fileIds = Set(files.compactMap { $0["id"] as? String })
    XCTAssertTrue(fileIds.contains(fileId1), "Expected files to contain file1")
    XCTAssertTrue(fileIds.contains(fileId2), "Expected files to contain file2")
  }
  
  /// Tests that reverse links with `unique? = true` (has-one) are stored as single entities.
  ///
  /// Schema: mediaTranscriptionRuns link
  /// - Forward: Media.transcriptionRuns has "many" (cardinality = many)
  /// - Reverse: TranscriptionRun.media has "one" (unique? = true)
  func testReverseLinkWithHasOneIsStoredAsSingleEntity() {
    let mediaId = "media-1"
    let runId = "run-1"
    
    // Link attribute: Media.transcriptionRuns -> TranscriptionRun
    // Forward: cardinality = many (Media has many transcriptionRuns)
    // Reverse: unique? = true (TranscriptionRun has one media)
    let transcriptionRunsAttr = Attribute(
      id: "attr-runs-link",
      forwardIdentity: ["ident-runs-link", "media", "transcriptionRuns"],
      reverseIdentity: ["ident-media-link", "transcriptionRuns", "media"],
      valueType: .ref,
      cardinality: .many,  // Forward cardinality
      unique: true,        // Reverse has "one", so unique? = true
      indexed: false,
      checkedDataType: nil
    )
    
    let mediaTitleAttr = Attribute(
      id: "attr-media-title",
      forwardIdentity: ["ident-title", "media", "title"],
      reverseIdentity: nil,
      valueType: .blob,
      cardinality: .one,
      unique: false,
      indexed: false,
      checkedDataType: nil
    )
    
    let runTypeAttr = Attribute(
      id: "attr-run-type",
      forwardIdentity: ["ident-run-type", "transcriptionRuns", "runType"],
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
                // Media entity
                [mediaId, mediaTitleAttr.id, "Test Recording"],
                // Link: Media -> TranscriptionRun
                [mediaId, transcriptionRunsAttr.id, runId],
                // TranscriptionRun entity
                [runId, runTypeAttr.id, "finalized"],
              ],
            ],
          ],
        ],
      ],
    ]
    
    let processed = InstaQLProcessor.process(
      result: result,
      attributes: [transcriptionRunsAttr, mediaTitleAttr, runTypeAttr],
      order: nil
    )
    
    // Verify TranscriptionRun entity exists
    guard let runEntities = processed["transcriptionRuns"] as? [[String: Any]] else {
      XCTFail("Expected processed InstaQL data to include a transcriptionRuns array")
      return
    }
    
    guard let run = runEntities.first(where: { ($0["id"] as? String) == runId }) else {
      XCTFail("Expected processed transcriptionRuns to include runId \(runId)")
      return
    }
    
    // KEY TEST: Reverse link "media" should be a SINGLE ENTITY (because unique? = true)
    guard let linkedMedia = run["media"] as? [String: Any] else {
      XCTFail("Expected transcriptionRun.media to be a single entity (reverse link with unique? = true should be singular)")
      return
    }
    
    XCTAssertEqual(linkedMedia["id"] as? String, mediaId)
    XCTAssertEqual(linkedMedia["title"] as? String, "Test Recording")
  }
  
  // MARK: - Nested Link Tests
  
  /// Tests that nested links are properly resolved.
  ///
  /// Query: media.with(\.transcriptionRuns).with(\.words)
  /// Expected: Media.transcriptionRuns[].words[] should be populated
  func testNestedLinksAreResolved() {
    let mediaId = "media-1"
    let runId = "run-1"
    let wordId1 = "word-1"
    let wordId2 = "word-2"
    
    // Link: Media.transcriptionRuns -> TranscriptionRun
    let transcriptionRunsAttr = Attribute(
      id: "attr-runs-link",
      forwardIdentity: ["ident-runs-link", "media", "transcriptionRuns"],
      reverseIdentity: ["ident-media-link", "transcriptionRuns", "media"],
      valueType: .ref,
      cardinality: .many,
      unique: true,  // TranscriptionRun has one media
      indexed: false,
      checkedDataType: nil
    )
    
    // Link: TranscriptionRun.words -> Word
    let wordsAttr = Attribute(
      id: "attr-words-link",
      forwardIdentity: ["ident-words-link", "transcriptionRuns", "words"],
      reverseIdentity: ["ident-run-link", "words", "transcriptionRun"],
      valueType: .ref,
      cardinality: .many,
      unique: true,  // Word has one transcriptionRun
      indexed: false,
      checkedDataType: nil
    )
    
    let mediaTitleAttr = Attribute(
      id: "attr-media-title",
      forwardIdentity: ["ident-title", "media", "title"],
      reverseIdentity: nil,
      valueType: .blob,
      cardinality: .one,
      unique: false,
      indexed: false,
      checkedDataType: nil
    )
    
    let runTypeAttr = Attribute(
      id: "attr-run-type",
      forwardIdentity: ["ident-run-type", "transcriptionRuns", "runType"],
      reverseIdentity: nil,
      valueType: .blob,
      cardinality: .one,
      unique: false,
      indexed: false,
      checkedDataType: nil
    )
    
    let wordTextAttr = Attribute(
      id: "attr-word-text",
      forwardIdentity: ["ident-word-text", "words", "text"],
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
                // Media entity
                [mediaId, mediaTitleAttr.id, "Test Recording"],
                // Link: Media -> TranscriptionRun
                [mediaId, transcriptionRunsAttr.id, runId],
                // TranscriptionRun entity
                [runId, runTypeAttr.id, "finalized"],
                // Links: TranscriptionRun -> Words
                [runId, wordsAttr.id, wordId1],
                [runId, wordsAttr.id, wordId2],
                // Word entities
                [wordId1, wordTextAttr.id, "hello"],
                [wordId2, wordTextAttr.id, "world"],
              ],
            ],
          ],
        ],
      ],
    ]
    
    let processed = InstaQLProcessor.process(
      result: result,
      attributes: [transcriptionRunsAttr, wordsAttr, mediaTitleAttr, runTypeAttr, wordTextAttr],
      order: nil
    )
    
    // Verify Media entity
    guard let mediaEntities = processed["media"] as? [[String: Any]] else {
      XCTFail("Expected processed InstaQL data to include a media array")
      return
    }
    
    guard let media = mediaEntities.first(where: { ($0["id"] as? String) == mediaId }) else {
      XCTFail("Expected processed media to include mediaId \(mediaId)")
      return
    }
    
    // Verify transcriptionRuns is an array
    guard let transcriptionRuns = media["transcriptionRuns"] as? [[String: Any]] else {
      XCTFail("Expected media.transcriptionRuns to be an array, got: \(String(describing: media["transcriptionRuns"]))")
      return
    }
    
    XCTAssertEqual(transcriptionRuns.count, 1, "Expected 1 transcription run")
    
    guard let run = transcriptionRuns.first else {
      XCTFail("Expected at least one transcription run")
      return
    }
    
    XCTAssertEqual(run["runType"] as? String, "finalized")
    
    // KEY TEST: Nested link - words should be populated on the transcription run
    guard let words = run["words"] as? [[String: Any]] else {
      XCTFail("Expected transcriptionRun.words to be an array (nested forward link)")
      return
    }
    
    XCTAssertEqual(words.count, 2, "Expected 2 words in the array")
    
    let wordTexts = Set(words.compactMap { $0["text"] as? String })
    XCTAssertTrue(wordTexts.contains("hello"), "Expected words to contain 'hello'")
    XCTAssertTrue(wordTexts.contains("world"), "Expected words to contain 'world'")
  }
}
