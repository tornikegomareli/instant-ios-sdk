import Foundation
import XCTest

@testable import InstantDB

// MARK: - StorageIntegrationTests

final class StorageIntegrationTests: XCTestCase {

  private static let testAppID = "b9319949-2f2d-410b-8f8a-6990177c1d44"
  private static let timeout: TimeInterval = 20.0

  @MainActor
  func testUploadDownloadAndDeleteFile() async throws {
    let client = InstantClient(appID: Self.testAppID, enableLocalPersistence: false)

    let user: User
    do {
      user = try await client.authManager.signInAsGuest()
    } catch {
      throw XCTSkip("Storage integration requires guest auth. Error: \(error)")
    }

    let userIdPrefix = "\(user.id)/"
    let path = "\(userIdPrefix)swift-storage-tests/\(UUID().uuidString.lowercased()).txt"

    let payloadString = "hello storage \(UUID().uuidString)"
    guard let payload = payloadString.data(using: .utf8) else {
      XCTFail("Failed to encode payload as UTF-8")
      return
    }

    var uploadedFileId: String?
    defer {
      Task { @MainActor in
        _ = try? await client.storage.deleteFile(path: path)
        client.disconnect()
      }
    }

    do {
      uploadedFileId = try await client.storage.uploadFile(
        path: path,
        data: payload,
        options: .init(contentType: "text/plain")
      )
    } catch let error as InstantError {
      switch error {
      case .serverError(let message, _):
        throw XCTSkip(
          """
          Storage integration test is not runnable for appID=\(Self.testAppID).

          WHAT HAPPENED:
            Upload failed with a server error.

          WHY THIS HAPPENS:
            Storage is gated by `$files` permissions and may be disabled per app.

          HOW TO FIX:
            1) Enable storage for the app, and
            2) Add `$files` rules allowing create/view/delete for the test user.

          SERVER MESSAGE:
            \(message)
          """
        )
      default:
        throw error
      }
    }

    guard let uploadedFileId else {
      XCTFail("Expected upload to return a file id")
      return
    }

    XCTAssertFalse(uploadedFileId.isEmpty)

    let downloadURL: URL
    do {
      downloadURL = try await client.storage.downloadURL(path: path)
    } catch let error as InstantError {
      switch error {
      case .serverError(let message, _):
        throw XCTSkip("Download URL failed (likely missing `$files` view permission). Message: \(message)")
      default:
        throw error
      }
    }

    let (downloadedData, _) = try await URLSession.shared.data(from: downloadURL)
    XCTAssertEqual(downloadedData, payload)

    let deletedId: String?
    do {
      deletedId = try await client.storage.deleteFile(path: path)
    } catch let error as InstantError {
      switch error {
      case .serverError(let message, _):
        throw XCTSkip("Delete failed (likely missing `$files` delete permission). Message: \(message)")
      default:
        throw error
      }
    }

    XCTAssertEqual(deletedId, uploadedFileId)

    let deadline = Date().addingTimeInterval(Self.timeout)
    var didObserveNotFound = false
    while Date() < deadline && !didObserveNotFound {
      do {
        _ = try await client.storage.downloadURL(path: path)
        try await Task.sleep(nanoseconds: 200_000_000)
      } catch {
        didObserveNotFound = true
      }
    }

    XCTAssertTrue(didObserveNotFound)
  }
}

