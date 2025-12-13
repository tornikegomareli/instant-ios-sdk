import Foundation

public actor PlatformAPI {
  private let baseURL: String
  private let token: String

  public init(token: String, baseURL: String = "https://api.instantdb.com") {
    self.token = token
    self.baseURL = baseURL
  }

  public func planSchemaPush(appId: String, schema: InstantSchema) async throws -> SchemaPlanResponse {
    let url = URL(string: "\(baseURL)/superadmin/apps/\(appId)/schema/push/plan")!
    let body = try createPushBody(schema: schema)

    let data = try await performRequest(url: url, method: "POST", body: body)
    return try parseResponse(data)
  }

  public func pushSchema(appId: String, schema: InstantSchema) async throws -> SchemaPushResponse {
    let url = URL(string: "\(baseURL)/superadmin/apps/\(appId)/schema/push/apply")!
    let body = try createPushBody(schema: schema)

    let data = try await performRequest(url: url, method: "POST", body: body)
    let planResponse: SchemaPlanResponse = try parseResponse(data)
    return SchemaPushResponse(steps: planResponse.steps)
  }

  private func parseResponse(_ data: Data) throws -> SchemaPlanResponse {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rawSteps = json["steps"] as? [[Any]] else {
      return SchemaPlanResponse(steps: [])
    }

    let steps = rawSteps.map { array -> SchemaPlanStep in
      let type = array.first as? String ?? "unknown"
      let details = array.count > 1 ? (array[1] as? [String: Any] ?? [:]) : [:]
      return SchemaPlanStep(type: type, details: details)
    }

    return SchemaPlanResponse(steps: steps)
  }

  public func getSchema(appId: String) async throws -> [String: Any] {
    let url = URL(string: "\(baseURL)/superadmin/apps/\(appId)/schema")!
    let data = try await performRequest(url: url, method: "GET", body: nil)

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw PlatformAPIError.invalidResponse
    }
    return json
  }

  private func createPushBody(schema: InstantSchema) throws -> Data {
    let schemaDict = SchemaSerializer.toDictionary(schema)
    let body: [String: Any] = [
      "schema": schemaDict,
      "check_types": true,
      "supports_background_updates": true
    ]
    return try JSONSerialization.data(withJSONObject: body)
  }

  private func performRequest(url: URL, method: String, body: Data?) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw PlatformAPIError.invalidResponse
    }

    if httpResponse.statusCode == 200 {
      return data
    }

    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let message = errorJson["message"] as? String {
      throw PlatformAPIError.serverError(statusCode: httpResponse.statusCode, message: message)
    }

    throw PlatformAPIError.serverError(statusCode: httpResponse.statusCode, message: "Unknown error")
  }
}

public enum PlatformAPIError: Error, LocalizedError {
  case invalidResponse
  case serverError(statusCode: Int, message: String)
  case encodingError

  public var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "Invalid response from server"
    case .serverError(let code, let message):
      return "Server error (\(code)): \(message)"
    case .encodingError:
      return "Failed to encode request"
    }
  }
}

public struct SchemaPlanResponse {
  public let steps: [SchemaPlanStep]
}

public struct SchemaPlanStep {
  public let type: String
  public let details: [String: Any]

  public var friendlyDescription: String? {
    if let forwardIdentity = details["forward-identity"] as? [Any], forwardIdentity.count >= 3 {
      let entity = forwardIdentity[1] as? String ?? "?"
      let attr = forwardIdentity[2] as? String ?? "?"
      return "\(type): \(entity).\(attr)"
    }
    return type
  }
}

public struct SchemaPushResponse {
  public let steps: [SchemaPlanStep]?
}
