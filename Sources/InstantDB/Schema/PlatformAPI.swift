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
      let rawDetails = array.count > 1 ? (array[1] as? [String: Any] ?? [:]) : [:]
      let details = SchemaPlanStepDetails(fromJSON: rawDetails)
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

public struct SchemaPlanResponse: Sendable {
  public let steps: [SchemaPlanStep]
}

/// Represents the identity of an attribute in a schema plan step.
/// Contains the namespace ID, entity name, and attribute name.
public struct AttributeIdentity: Sendable, Equatable {
  public let namespaceId: String
  public let entityName: String
  public let attributeName: String
  
  public init(namespaceId: String, entityName: String, attributeName: String) {
    self.namespaceId = namespaceId
    self.entityName = entityName
    self.attributeName = attributeName
  }
}

/// Type-safe details for a schema plan step.
/// 
/// The InstantDB API returns step details as a dictionary with known keys.
/// This struct provides type-safe access to those fields, eliminating the
/// need for `[String: Any]` and enabling proper `Sendable` conformance.
public struct SchemaPlanStepDetails: Sendable, Equatable {
  /// The identity of the attribute being modified (entity.attribute).
  public let forwardIdentity: AttributeIdentity?
  
  /// The attribute ID for existing attributes.
  public let attrId: String?
  
  /// The data type of the attribute (e.g., "string", "number", "boolean").
  public let valueType: String?
  
  /// Whether the attribute is indexed.
  public let indexed: Bool?
  
  /// Whether the attribute has a unique constraint.
  public let unique: Bool?
  
  public init(
    forwardIdentity: AttributeIdentity? = nil,
    attrId: String? = nil,
    valueType: String? = nil,
    indexed: Bool? = nil,
    unique: Bool? = nil
  ) {
    self.forwardIdentity = forwardIdentity
    self.attrId = attrId
    self.valueType = valueType
    self.indexed = indexed
    self.unique = unique
  }
  
  /// Parse from raw JSON dictionary returned by InstantDB API.
  /// 
  /// The API returns details as `[String: Any]`. This initializer extracts
  /// the known fields into a type-safe structure.
  public init(fromJSON json: [String: Any]) {
    // Parse forward-identity: [namespaceId, entityName, attributeName, ...]
    if let identity = json["forward-identity"] as? [Any], identity.count >= 3 {
      self.forwardIdentity = AttributeIdentity(
        namespaceId: identity[0] as? String ?? "",
        entityName: identity[1] as? String ?? "",
        attributeName: identity[2] as? String ?? ""
      )
    } else {
      self.forwardIdentity = nil
    }
    
    self.attrId = json["attr-id"] as? String
    self.valueType = json["value-type"] as? String
    self.indexed = json["indexed"] as? Bool
    self.unique = json["unique"] as? Bool
  }
}

/// Represents a single step in a schema migration plan.
///
/// Each step describes one change to be made to the schema, such as
/// adding an attribute, creating an index, or setting a unique constraint.
public struct SchemaPlanStep: Sendable, Equatable {
  /// The type of schema change (e.g., "add-attr", "index", "unique").
  public let type: String
  
  /// Type-safe details about the schema change.
  public let details: SchemaPlanStepDetails

  public init(type: String, details: SchemaPlanStepDetails) {
    self.type = type
    self.details = details
  }
  
  /// A human-readable description of this step.
  public var friendlyDescription: String? {
    if let identity = details.forwardIdentity {
      return "\(type): \(identity.entityName).\(identity.attributeName)"
    }
    return type
  }
}

public struct SchemaPushResponse: Sendable {
  public let steps: [SchemaPlanStep]?
}
