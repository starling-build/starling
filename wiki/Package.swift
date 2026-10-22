// swift-tools-version: 6.0

import PackageDescription

// The wiki server (docs/plans/wiki.md): Hummingbird over SwiftNIO, Postgres
// through PostgresNIO. Pure Swift — it does NOT link the Office suite or the
// engine: page bodies are opaque JSON here, conversions shell out to the
// headless OfficeApp binary, and the operational-transform code in WikiModel
// works on positions alone. (hummingbird-websocket joins in W5; its
// swift-websocket needs a macOS 26 deployment target on a Mac.)
let package = Package(
    name: "wiki",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "wiki-server", targets: ["WikiServer"]),
        .library(name: "WikiModel", targets: ["WikiModel"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "WikiModel",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "WikiServer",
            dependencies: [
                "WikiModel",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "WikiModelTests",
            dependencies: ["WikiModel"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
