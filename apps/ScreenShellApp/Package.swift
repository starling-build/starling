// swift-tools-version: 6.0

import PackageDescription
import Foundation

// Absolute so the -rpath baked into this app resolves regardless of the cwd the
// shell spawns it from: child processes get LD_LIBRARY_PATH scrubbed and fall
// back to their own RUNPATH.
let appPackageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

// Context.environment, not ProcessInfo: it is the API SwiftPM sanctions for
// manifest-time environment reads, and the one where changing a variable
// actually re-evaluates the manifest. Same as sdk/Package.swift.
func env(_ key: String, default fallback: String) -> String {
    guard let v = Context.environment[key], !v.isEmpty else { return fallback }
    return v
}

// No toolchain include path here: <swift/bridging>, the only toolchain header
// the bridge headers needed, is vendored by the framework
// (sdk/tools/sync-vendored-headers.sh) and resolves through its own include
// directory. sdk/Package.swift dropped the absolute -I for that reason; these
// manifests carried it for a while longer, which forced every non-Swiftly
// packager to patch all fifteen of them.

// STARLING_ENGINE_OUT is the same override build/stage.sh reads, so one engine
// flavour can be built and pointed at from everywhere.
#if os(Linux)
let engineOutDir = env("STARLING_ENGINE_OUT",
                       default: appPackageDir + "/../../engine/src/out/host_debug")
#else
let engineOutDir = env("STARLING_ENGINE_OUT",
                       default: appPackageDir + "/../../engine/src/out/ci/host_debug_unopt_arm64")
#endif

// Ubuntu 26.04 (glibc 2.43 + libstdc++ 15) vs the ubuntu24.04-built 6.2.4
// toolchain: stops the C++-interop importer parsing <cmath> twice. Same as
// sdk/Package.swift; see docs/BUILDING.md.
#if os(Linux)
let glibcMathCompat = ["-Xcc", "-D_GLIBCXX_MATH_H", "-Xcc", "-include", "-Xcc", "/usr/include/math.h"]
#else
let glibcMathCompat: [String] = []
#endif

let toolchainSwiftCFlags: [String] = glibcMathCompat

#if os(macOS)
let platformConstraints: [SupportedPlatform] = [.macOS(.v14)]
#else
let platformConstraints: [SupportedPlatform] = []
#endif

let package = Package(
    name: "ScreenShellApp",
    platforms: platformConstraints.isEmpty ? nil : platformConstraints,
    dependencies: [
        .package(name: "FlutterSwift", path: "../../sdk"),
    ],
    targets: [
        {
            #if os(macOS)
            return .executableTarget(
                name: "ScreenShellApp",
                dependencies: [
                    .product(name: "SwiftRuntime", package: "FlutterSwift"),
                    .product(name: "FlutterMacOSBridge", package: "FlutterSwift"),
                    .product(name: "Flutter", package: "FlutterSwift"),
                ],
                swiftSettings: [
                    .interoperabilityMode(.Cxx),
                    .unsafeFlags([
                        "-Xcc", "-I\(engineOutDir)/FlutterMacOS.framework/Versions/A/Headers",
                    ]),
                ],
                linkerSettings: [
                    .unsafeFlags([
                        "-F\(engineOutDir)",
                        "-framework", "FlutterMacOS",
                        "-Xlinker", "-rpath", "-Xlinker", "\(engineOutDir)",
                    ]),
                ]
            )
            #else
            return .executableTarget(
                name: "ScreenShellApp",
                dependencies: [
                    .product(name: "FlutterShared", package: "FlutterSwift"),
                ],
                swiftSettings: [
                    .interoperabilityMode(.Cxx),
                    .unsafeFlags(toolchainSwiftCFlags),
                ],
                linkerSettings: [
                    .unsafeFlags([
                        "-L\(engineOutDir)",
                        "-lflutter_engine",
                        "-Xlinker", "-rpath", "-Xlinker", "\(engineOutDir)",
                        "-Xlinker", "--allow-shlib-undefined",
                        "-Xlinker", "--export-dynamic",
                    ]),
                ]
            )
            #endif
        }()
    ],
    cxxLanguageStandard: .cxx20
)
