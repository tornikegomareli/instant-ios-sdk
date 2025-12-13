import ArgumentParser
import Foundation
import InstantDB

struct GetCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "get",
    abstract: "Get current schema from InstantDB"
  )

  @Option(name: .long, help: "InstantDB App ID")
  var appId: String

  @Option(name: .long, help: "Admin token")
  var token: String

  @Flag(name: .long, help: "Output as JSON")
  var json: Bool = false

  func run() async throws {
    let api = PlatformAPI(token: token)

    print("Fetching schema...")
    let schema = try await api.getSchema(appId: appId)

    if json {
      let data = try JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys])
      print(String(data: data, encoding: .utf8) ?? "")
    } else {
      SchemaPrinter.print(schema)
    }
  }
}
