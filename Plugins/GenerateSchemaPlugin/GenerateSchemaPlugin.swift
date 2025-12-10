/// GenerateSchema Command Plugin
///
/// Generates `instant.schema.json` from Swift schema files.
///
/// Usage from consumer app:
/// ```
/// swift package generate-schema
/// ```

import PackagePlugin
import Foundation

@main
struct GenerateSchemaPlugin: CommandPlugin {
  func performCommand(context: PluginContext, arguments: [String]) async throws {
    let workingDir = FileManager.default.currentDirectoryPath

    // Find all Swift files with @InstantEntity or InstantSchema
    let inputFiles = findAllSchemaFiles(in: workingDir)

    guard !inputFiles.isEmpty else {
      Diagnostics.error("No schema files found. Create @InstantEntity structs and instant.schema.swift")
      return
    }

    print("Found \(inputFiles.count) schema file(s)")

    let outputPath = (workingDir as NSString).appendingPathComponent("instant.schema.json")
    let generator = try context.tool(named: "InstantSchemaGenerator")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: generator.path.string)
    process.arguments = inputFiles + [outputPath]

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus == 0 {
      print("Generated instant.schema.json")
    } else {
      Diagnostics.error("Schema generation failed")
    }
  }

  /// Finds schema files in current directory and Models/ subdirectory
  private func findAllSchemaFiles(in directory: String) -> [String] {
    var schemaFiles: [String] = []

    // Search current directory
    schemaFiles.append(contentsOf: findSwiftFilesWithSchema(in: directory))

    // Also search Models/ subdirectory if it exists
    let modelsDir = (directory as NSString).appendingPathComponent("Models")
    if FileManager.default.fileExists(atPath: modelsDir) {
      schemaFiles.append(contentsOf: findSwiftFilesWithSchema(in: modelsDir))
    }

    return schemaFiles
  }

  private func findSwiftFilesWithSchema(in directory: String) -> [String] {
    let fm = FileManager.default
    var files: [String] = []

    guard let contents = try? fm.contentsOfDirectory(atPath: directory) else {
      return []
    }

    for file in contents {
      guard file.hasSuffix(".swift") else { continue }

      let fullPath = (directory as NSString).appendingPathComponent(file)

      if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
        if content.contains("@InstantEntity") || content.contains("InstantSchema") {
          files.append(fullPath)
        }
      }
    }

    return files
  }
}
