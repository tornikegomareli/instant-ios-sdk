// swift-tools-version: 5.9
import PackageDescription
import CompilerPluginSupport

let package = Package(
  name: "InstantDB",
  platforms: [
    .iOS(.v15),
    .macOS(.v10_15),
  ],
  products: [
    .library(
      name: "InstantDB",
      targets: ["InstantDB"]
    ),
    .plugin(
      name: "GenerateSchemaPlugin",
      targets: ["GenerateSchemaPlugin"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "9.0.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.3.2"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
  ],
  targets: [
    .macro(
      name: "InstantDBMacros",
      dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
      ]
    ),
    .target(
      name: "InstantDB",
      dependencies: [
        "InstantDBMacros",
        .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras")
      ],
      path: "Sources/InstantDB"
    ),
    .testTarget(
      name: "InstantDBTests",
      dependencies: ["InstantDB"],
      path: "Tests/InstantDBTests"
    ),
    .testTarget(
      name: "InstantDBMacrosTests",
      dependencies: [
        "InstantDBMacros",
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
      ]
    ),
    .executableTarget(
      name: "instant-schema",
      dependencies: [
        "InstantDB",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ],
      path: "Sources/InstantSchemaCLI"
    ),
    .executableTarget(
      name: "InstantSchemaGenerator",
      dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax")
      ],
      path: "Sources/InstantSchemaGenerator"
    ),
    .plugin(
      name: "GenerateSchemaPlugin",
      capability: .command(
        intent: .custom(verb: "generate-schema", description: "Generate instant.schema.json from Swift schema"),
        permissions: [.writeToPackageDirectory(reason: "To write instant.schema.json")]
      ),
      dependencies: ["InstantSchemaGenerator"],
      path: "Plugins/GenerateSchemaPlugin"
    )
  ]
)
