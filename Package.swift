// swift-tools-version: 6.2.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "InstantDB",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .watchOS(.v8),
        .tvOS(.v15)
    ],
    products: [
        .library(
            name: "InstantDB",
            targets: ["InstantDB"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "9.0.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.3.2")
    ],
    targets: [
        // Macro implementation (compiler plugin)
        .macro(
            name: "InstantDBMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),

        // Main library
        .target(
            name: "InstantDB",
            dependencies: [
                "InstantDBMacros",
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras")
            ],
            path: "Sources/InstantDB"
        ),

        // Main tests
        .testTarget(
            name: "InstantDBTests",
            dependencies: ["InstantDB"],
            path: "Tests/InstantDBTests"
        ),

        // Macro tests
        .testTarget(
            name: "InstantDBMacrosTests",
            dependencies: [
                "InstantDBMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ]
        )
    ]
)
