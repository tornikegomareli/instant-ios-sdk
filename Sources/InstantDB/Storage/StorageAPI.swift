import Foundation

// MARK: - StorageAPI

/// HTTP client for InstantDB file storage endpoints.
///
/// ## Why This Exists
/// InstantDB's JS clients expose `db.storage.*` helpers for uploading and deleting files.
/// The Swift SDK targets parity so Apple clients can use the same server-side storage
/// capabilities without re-implementing request signing or endpoint details.
///
/// ## Permissions
/// Storage operations are protected by InstantDB's permissions system via `$files`.
/// If your app does not define `$files` rules, the server will deny access by default.
///
/// - SeeAlso: https://www.instantdb.com/docs/storage
/// - SeeAlso: https://www.instantdb.com/docs/permissions
@MainActor
public final class StorageAPI {

  // MARK: - Types

  public struct UploadOptions: Sendable, Equatable {
    public var contentType: String?
    public var contentDisposition: String?

    public init(contentType: String? = nil, contentDisposition: String? = nil) {
      self.contentType = contentType
      self.contentDisposition = contentDisposition
    }
  }

  public struct UploadResponse: Decodable, Sendable, Equatable {
    public let data: UploadData

    public struct UploadData: Decodable, Sendable, Equatable {
      public let id: String
    }
  }

  public struct DeleteResponse: Decodable, Sendable, Equatable {
    public let data: DeleteData

    public struct DeleteData: Decodable, Sendable, Equatable {
      public let id: String?
    }
  }

  private struct SignedDownloadURLResponse: Decodable, Sendable, Equatable {
    let data: String
  }

  // MARK: - Properties

  private let appID: String
  private let baseURL: String
  private let refreshTokenProvider: @MainActor () -> String?

  // MARK: - Initialization

  init(
    appID: String,
    baseURL: String,
    refreshTokenProvider: @escaping @MainActor () -> String?
  ) {
    self.appID = appID
    self.baseURL = baseURL
    self.refreshTokenProvider = refreshTokenProvider
  }

  // MARK: - Public API

  /// Uploads a file to InstantDB storage at the provided path.
  ///
  /// The file is tracked in the `$files` system namespace.
  ///
  /// - Parameters:
  ///   - path: Storage path, e.g. `"photos/demo.png"`.
  ///   - data: File data to upload.
  ///   - options: Optional metadata such as content type and disposition.
  /// - Returns: The `$files` entity id created/updated for this path.
  public func uploadFile(
    path: String,
    data: Data,
    options: UploadOptions = .init()
  ) async throws -> String {
    let url = URL(string: "\(baseURL)/storage/upload")!

    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.httpBody = data

    request.setValue(appID, forHTTPHeaderField: "app_id")
    request.setValue(path, forHTTPHeaderField: "path")

    if let refreshToken = refreshTokenProvider() {
      request.setValue("Bearer \(refreshToken)", forHTTPHeaderField: "Authorization")
    }

    request.setValue(options.contentType ?? "application/octet-stream", forHTTPHeaderField: "Content-Type")

    if let contentDisposition = options.contentDisposition {
      request.setValue(contentDisposition, forHTTPHeaderField: "content-disposition")
    }

    let (responseData, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw InstantError.connectionFailed(URLError(.badServerResponse))
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      try handleErrorResponse(responseData, statusCode: httpResponse.statusCode)
    }

    let decoded = try JSONDecoder().decode(UploadResponse.self, from: responseData)
    return decoded.data.id
  }

  /// Uploads a file from disk.
  ///
  /// - Note: This reads the file into memory. Prefer streaming uploads on server-side
  /// tooling for very large files.
  public func uploadFile(
    path: String,
    fileURL: URL,
    options: UploadOptions = .init()
  ) async throws -> String {
    let data = try Data(contentsOf: fileURL)
    return try await uploadFile(path: path, data: data, options: options)
  }

  /// Deletes a file by path.
  ///
  /// - Parameter path: Storage path, e.g. `"photos/demo.png"`.
  /// - Returns: The `$files` entity id that was deleted, or nil if not found.
  public func deleteFile(path: String) async throws -> String? {
    var components = URLComponents(string: "\(baseURL)/storage/files")!
    components.queryItems = [
      URLQueryItem(name: "app_id", value: appID),
      URLQueryItem(name: "filename", value: path)
    ]

    var request = URLRequest(url: components.url!)
    request.httpMethod = "DELETE"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    if let refreshToken = refreshTokenProvider() {
      request.setValue("Bearer \(refreshToken)", forHTTPHeaderField: "Authorization")
    }

    let (responseData, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw InstantError.connectionFailed(URLError(.badServerResponse))
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      try handleErrorResponse(responseData, statusCode: httpResponse.statusCode)
    }

    let decoded = try JSONDecoder().decode(DeleteResponse.self, from: responseData)
    return decoded.data.id
  }

  /// Returns a temporary, signed URL for downloading a file.
  ///
  /// - Important: This endpoint is considered legacy by the JS SDK and may be removed
  /// in the future. Prefer querying `$files` and using the returned URL fields when
  /// available.
  public func downloadURL(path: String) async throws -> URL {
    var components = URLComponents(string: "\(baseURL)/storage/signed-download-url")!
    components.queryItems = [
      URLQueryItem(name: "app_id", value: appID),
      URLQueryItem(name: "filename", value: path)
    ]

    var request = URLRequest(url: components.url!)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    if let refreshToken = refreshTokenProvider() {
      request.setValue("Bearer \(refreshToken)", forHTTPHeaderField: "Authorization")
    }

    let (responseData, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw InstantError.connectionFailed(URLError(.badServerResponse))
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      try handleErrorResponse(responseData, statusCode: httpResponse.statusCode)
    }

    let decoded = try JSONDecoder().decode(SignedDownloadURLResponse.self, from: responseData)
    guard let url = URL(string: decoded.data) else {
      throw InstantError.decodingError(NSError(domain: "InstantDB.StorageAPI", code: -1))
    }

    return url
  }

  // MARK: - Error Handling

  private func handleErrorResponse(_ data: Data, statusCode: Int) throws -> Never {
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let message = json["message"] as? String {
      let hint = json["hint"] as? [String: Any]
      throw InstantError.serverError(message, hint: hint)
    }

    throw InstantError.serverError("HTTP \(statusCode)", hint: nil)
  }
}

