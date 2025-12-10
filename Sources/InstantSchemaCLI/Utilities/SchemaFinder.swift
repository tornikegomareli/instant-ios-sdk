import Foundation

enum SchemaFinder {
  static func findSchemaFile(in directory: String = FileManager.default.currentDirectoryPath) -> String? {
    let path = (directory as NSString).appendingPathComponent("instant.schema.json")
    return FileManager.default.fileExists(atPath: path) ? path : nil
  }
}
