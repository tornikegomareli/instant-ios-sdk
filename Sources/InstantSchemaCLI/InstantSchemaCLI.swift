import ArgumentParser

@main
struct InstantSchemaCLI: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "instant-schema",
    abstract: "CLI tool for managing InstantDB schemas",
    subcommands: [GenerateCommand.self, PushCommand.self, PlanCommand.self, GetCommand.self]
  )
}
