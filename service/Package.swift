// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StarlingDocumentService",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "starling-documents", targets: ["Server"])],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.20.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.25.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),
        .package(url: "https://github.com/soto-project/soto.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "DocumentService", dependencies: [
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "PostgresNIO", package: "postgres-nio"),
            .product(name: "JWTKit", package: "jwt-kit"),
            .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "SotoS3", package: "soto"),
        ], resources: [.copy("Migrations")]),
        .executableTarget(name: "Server", dependencies: ["DocumentService",
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "PostgresNIO", package: "postgres-nio"),
        ]),
        .testTarget(name: "DocumentServiceTests", dependencies: [
            "DocumentService", .product(name: "HummingbirdTesting", package: "hummingbird"),
            .product(name: "JWTKit", package: "jwt-kit"),
        ], resources: [.copy("Fixtures")]),
    ]
)
