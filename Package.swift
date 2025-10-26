// swift-tools-version: 6.2.0
import PackageDescription

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
    targets: [
        .target(
            name: "InstantDB",
            dependencies: [],
            path: "Sources/InstantDB"
        ),
        .testTarget(
            name: "InstantDBTests",
            dependencies: ["InstantDB"],
            path: "Tests/InstantDBTests"
        ),
    ]
)
