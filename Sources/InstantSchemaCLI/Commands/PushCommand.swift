import ArgumentParser
import Foundation
import InstantDB

struct PushCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "push",
    abstract: "Push schema to InstantDB"
  )

  @Option(name: .long, help: "InstantDB App ID")
  var appId: String

  @Option(name: .long, help: "Admin token")
  var token: String

  @Option(name: .long, help: "Path to schema JSON file (auto-detected if not specified)")
  var schema: String?

  @Flag(name: .long, help: "Skip confirmation")
  var force: Bool = false

  func run() async throws {
    let schemaInstance = try loadSchema()
    let api = PlatformAPI(token: token)

    print("Planning schema push...")
    let plan = try await api.planSchemaPush(appId: appId, schema: schemaInstance)

    if plan.steps.isEmpty {
      print("Schema is up to date.")
      return
    }

    print("\nChanges:")
    for (index, step) in plan.steps.enumerated() {
      print("  \(index + 1). \(step.friendlyDescription ?? step.type)")
    }

    if !force {
      print("\nApply? [y/N] ", terminator: "")
      guard readLine()?.lowercased() == "y" else {
        print("Aborted.")
        return
      }
    }

    _ = try await api.pushSchema(appId: appId, schema: schemaInstance)
    print("Schema pushed successfully.")
  }

  private func loadSchema() throws -> InstantSchema {
    if let schemaPath = schema {
      return try SchemaLoader.load(from: schemaPath)
    }

    guard let foundPath = SchemaFinder.findSchemaFile() else {
      throw CLIError.schemaNotFound
    }

    print("Found schema at: \(foundPath)")
    return try SchemaLoader.load(from: foundPath)
  }
}
