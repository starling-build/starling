// swift-tools-version: 6.0

import PackageDescription
import Foundation

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
// directory. Nothing here may name a toolchain path: a build against a
// distribution's own Swift has no such directory to name.

// Absolute so the -rpath baked into this app resolves regardless of the cwd the
// shell spawns it from: child processes get LD_LIBRARY_PATH scrubbed and fall
// back to their own RUNPATH.
let appPackageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

// Opt-in windowed build: `STARLING_APP_GTK=1 swift build -c release` adds the
// engine's GTK embedder, so the same sources run in an ordinary window on a
// normal desktop session (GNOME/KDE, Wayland or X11) instead of compositing
// through the shell. Off by default, because the shipped app must not drag GTK
// into its link set — the same split TaskManagerApp's manifest describes.
// The source side is guarded by `#if STARLING_GTK`; `runStarlingApp` picks the
// host at runtime, so the default binary behaves exactly as before.
let gtkHost = !env("STARLING_APP_GTK", default: "").isEmpty

#if os(Linux) || os(Windows)
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

#if os(macOS)
let platformConstraints: [SupportedPlatform] = [.macOS(.v14)]
#else
let platformConstraints: [SupportedPlatform] = []
#endif

var targets: [Target] = [
        // The emulator core: parser + grid + scrollback in C. It is here rather
        // than in Swift because the Swift version spent ~47% of its time in
        // exclusivity/ARC/COW bookkeeping instead of the emulator's own work.
        // See test/bench/core/ for the measurement and the differential test.
        {
            #if os(macOS)
            return .executableTarget(
                name: "TerminalApp",
                dependencies: [
                    .product(name: "SwiftRuntime", package: "FlutterSwift"),
                    .product(name: "FlutterMacOSBridge", package: "FlutterSwift"),
                    .product(name: "Flutter", package: "FlutterSwift"),
                ],
                resources: [
                    .copy("Resources/RobotoMono-Regular.ttf"),
                    .copy("Resources/RobotoMono-Bold.ttf"),
                    .copy("Resources/DejaVuSansMono-Regular.ttf"),
                    .copy("Resources/DejaVuSansMono-Bold.ttf"),
                    .copy("Resources/DejaVuSansMono-LICENSE.txt"),
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
            #elseif os(Windows)
            // Windows links the engine's import library rather than a shared
            // FlutterShared: there is no such product there, and no rpath —
            // the loader finds flutter_engine.dll beside the .exe. FlutterWin32
            // brings the Win32 embedder host in with it.
            return .executableTarget(
                name: "TerminalApp",
                dependencies: [
                    .product(name: "Flutter", package: "FlutterSwift"),
                    .product(name: "FlutterSwiftBridge", package: "FlutterSwift"),
                    .product(name: "SwiftRuntime", package: "FlutterSwift"),
                    .product(name: "CupertinoIcons", package: "FlutterSwift"),
                    .product(name: "FlutterWin32", package: "FlutterSwift"),
                    "CStarlingConPTY",
                    .product(name: "CTerminalCore", package: "FlutterSwift"),
                ],
                resources: [
                    .copy("Resources/RobotoMono-Regular.ttf"),
                    .copy("Resources/RobotoMono-Bold.ttf"),
                    .copy("Resources/DejaVuSansMono-Regular.ttf"),
                    .copy("Resources/DejaVuSansMono-Bold.ttf"),
                    .copy("Resources/DejaVuSansMono-LICENSE.txt"),
                ],
                swiftSettings: [
                    .interoperabilityMode(.Cxx),
                ],
                linkerSettings: [
                    .unsafeFlags([
                        "-L\(engineOutDir)",
                        "-lflutter_engine.dll",
                    ]),
                ]
            )
            #else
            return .executableTarget(
                name: "TerminalApp",
                dependencies: gtkHost
                    ? [
                        .product(name: "FlutterShared", package: "FlutterSwift"),
                        .product(name: "FlutterGTK", package: "FlutterSwift"),
                        .product(name: "CTerminalCore", package: "FlutterSwift"),
                    ]
                    : [
                        .product(name: "FlutterShared", package: "FlutterSwift"),
                        .product(name: "CTerminalCore", package: "FlutterSwift"),
                    ],
                resources: [
                    .copy("Resources/RobotoMono-Regular.ttf"),
                    .copy("Resources/RobotoMono-Bold.ttf"),
                    .copy("Resources/DejaVuSansMono-Regular.ttf"),
                    .copy("Resources/DejaVuSansMono-Bold.ttf"),
                    .copy("Resources/DejaVuSansMono-LICENSE.txt"),
                ],
                swiftSettings: gtkHost
                    ? [
                        .interoperabilityMode(.Cxx),
                        .unsafeFlags(glibcMathCompat),
                        .define("STARLING_GTK"),
                    ]
                    : [
                        .interoperabilityMode(.Cxx),
                        .unsafeFlags(glibcMathCompat),
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
]

#if os(Windows)
// The ConPTY shim. C rather than Swift-over-WinSDK because the pseudoconsole
// process attribute is a computed macro Swift cannot import; see the header.
// <windows.h> stays inside this target, away from the C++-interop importer.
targets += [
    .target(name: "CStarlingConPTY"),
]
#endif

let package = Package(
    name: "TerminalApp",
    platforms: platformConstraints.isEmpty ? nil : platformConstraints,
    dependencies: [
        .package(name: "FlutterSwift", path: "../../sdk"),
    ],
    targets: targets,
    cxxLanguageStandard: .cxx20
)
