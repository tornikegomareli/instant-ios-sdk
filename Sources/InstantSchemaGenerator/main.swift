/// InstantDB Schema Generator
///
/// A command-line tool that parses Swift schema files and generates
/// JSON schema files compatible with InstantDB's Platform API.
///
/// Usage:
/// ```
/// InstantSchemaGenerator <input-files...> <output-path>
/// ```
///
/// Example:
/// ```
/// InstantSchemaGenerator instant.schema.swift instant.schema.json
/// ```

import Foundation
import SwiftSyntax
import SwiftParser

/// Parses Swift schema files and generates InstantDB JSON schema.
enum InstantSchemaGenerator {
  static func main() throws {
    let arguments = CommandLine.arguments

    guard arguments.count >= 3 else {
      printUsage()
      exit(1)
    }

    let outputPath = arguments.last!
    let inputFiles = Array(arguments.dropFirst().dropLast())

    let schema = try generateSchema(from: inputFiles)
    try writeSchema(schema, to: outputPath)
  }

  /// Prints usage information.
  private static func printUsage() {
    print("Usage: InstantSchemaGenerator <schema-files...> <output-path>")
    print("")
    print("Example:")
    print("  InstantSchemaGenerator instant.schema.swift instant.schema.json")
  }

  /// Generates schema from input Swift files.
  private static func generateSchema(from inputFiles: [String]) throws -> SchemaOutput {
    var allEntities: [String: EntitySchema] = [:]
    var entityTypeToName: [String: String] = [:]

    // First pass: collect ALL @InstantEntity definitions from all files
    for inputFile in inputFiles {
      let source = try String(contentsOfFile: inputFile, encoding: .utf8)
      let syntaxTree = Parser.parse(source: source)

      let entityVisitor = EntityVisitor(viewMode: .all)
      entityVisitor.walk(syntaxTree)

      for entity in entityVisitor.entities {
        allEntities[entity.name] = entity
        entityTypeToName[entity.typeName] = entity.name
      }
    }

    // Second pass: find InstantSchema block and extract used entities + links
    var usedEntities: [String: EntitySchema] = [:]
    var links: [String: LinkSchema] = [:]

    for inputFile in inputFiles {
      let source = try String(contentsOfFile: inputFile, encoding: .utf8)
      let syntaxTree = Parser.parse(source: source)

      let schemaVisitor = SchemaBlockVisitor(
        viewMode: .all,
        entities: allEntities,
        entityTypeToName: entityTypeToName
      )
      schemaVisitor.walk(syntaxTree)

      // Merge results
      for (name, entity) in schemaVisitor.entities {
        usedEntities[name] = entity
      }
      for (name, link) in schemaVisitor.links {
        links[name] = link
      }
    }

    return SchemaOutput(entities: usedEntities, links: links)
  }

  /// Writes schema to JSON file.
  private static func writeSchema(_ schema: SchemaOutput, to path: String) throws {
    let jsonData = try JSONEncoder().encode(schema)
    let prettyData = try JSONSerialization.data(
      withJSONObject: try JSONSerialization.jsonObject(with: jsonData),
      options: [.prettyPrinted, .sortedKeys]
    )
    try prettyData.write(to: URL(fileURLWithPath: path))
  }
}

try InstantSchemaGenerator.main()
