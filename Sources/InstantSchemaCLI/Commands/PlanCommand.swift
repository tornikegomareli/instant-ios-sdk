import ArgumentParser
import Foundation
import InstantDB

struct PlanCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "plan",
    abstract: "Preview schema changes without applying"
  )

  @Option(name: .long, help: "InstantDB App ID")
  var appId: String

  @Option(name: .long, help: "Admin token")
  var token: String

  @Option(name: .long, help: "Path to schema JSON file (auto-detected if not specified)")
  var schema: String?

  func run() async throws {
    let schemaInstance = try loadSchema()
    let api = PlatformAPI(token: token)

    print("Planning schema push...")
    let plan = try await api.planSchemaPush(appId: appId, schema: schemaInstance)

    if plan.steps.isEmpty {
      print("No changes needed. Schema is up to date.")
      return
    }

    print("\nPlanned changes:")
    for (index, step) in plan.steps.enumerated() {
      print("  \(index + 1). \(step.friendlyDescription ?? step.type)")
    }
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
