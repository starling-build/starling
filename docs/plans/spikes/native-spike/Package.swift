// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "spike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "spike", path: "Sources/spike",
            swiftSettings: [.unsafeFlags(["-Onone"])])
    ]
)
