import ArgumentParser
import Foundation

struct GenerateCommand: ParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "generate",
    abstract: "Generate instant.schema.json from Swift schema file"
  )

  @Argument(help: "Path to Swift schema file (e.g., instant.schema.swift)")
  var input: String?

  func run() throws {
    let inputPath = input ?? findSchemaSwiftFile()

    guard let inputPath else {
      throw CLIError.message("No schema file found. Specify path or create instant.schema.swift")
    }

    guard FileManager.default.fileExists(atPath: inputPath) else {
      throw CLIError.message("File not found: \(inputPath)")
    }

    let outputPath = "instant.schema.json"
    let generatorPath = findGenerator()

    guard let generatorPath else {
      throw CLIError.message("InstantSchemaGenerator not found. Run 'swift build' first.")
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: generatorPath)
    process.arguments = [inputPath, outputPath]

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus == 0 {
      print("Generated \(outputPath)")
    } else {
      throw CLIError.message("Generation failed")
    }
  }

  private func findSchemaSwiftFile() -> String? {
    let candidates = ["instant.schema.swift", "schema.swift"]
    for candidate in candidates {
      if FileManager.default.fileExists(atPath: candidate) {
        return candidate
      }
    }
    return nil
  }

  private func findGenerator() -> String? {
    let candidates = [
      ".build/debug/InstantSchemaGenerator",
      ".build/release/InstantSchemaGenerator",
      ".build/arm64-apple-macosx/debug/InstantSchemaGenerator",
      ".build/arm64-apple-macosx/release/InstantSchemaGenerator"
    ]
    for candidate in candidates {
      if FileManager.default.fileExists(atPath: candidate) {
        return candidate
      }
    }
    return nil
  }
}
