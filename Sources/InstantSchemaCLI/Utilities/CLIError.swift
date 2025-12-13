import Foundation

enum CLIError: Error, LocalizedError {
  case fileNotFound(String)
  case invalidJSON
  case invalidSchemaFormat(String)
  case schemaNotFound
  case schemaCompilationFailed
  case message(String)

  var errorDescription: String? {
    switch self {
    case .fileNotFound(let path):
      return "File not found: \(path)"
    case .invalidJSON:
      return "Invalid JSON in schema file"
    case .invalidSchemaFormat(let msg):
      return "Invalid schema format: \(msg)"
    case .schemaNotFound:
      return "Could not find instant.schema.json. Run 'instant-schema generate' first."
    case .schemaCompilationFailed:
      return "Failed to compile schema file"
    case .message(let msg):
      return msg
    }
  }
}
