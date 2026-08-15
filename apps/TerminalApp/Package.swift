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

// An unpacked SDK bundle to build against instead of this repo's sdk/ — the
// release path, where the app is built exactly the way an external consumer
// builds it. Empty (the default) means the in-repo framework and an engine
// checkout, which is every dev build.
let sdkBundle = env("STARLING_SDK_BUNDLE", default: "")

#if os(Linux) || os(Windows)
// When building against a bundle the engine is *in* the bundle, so pointing -L
// at an engine checkout would defeat the point — and would silently succeed on
// a machine that happens to have one, linking a release against something the
// bundle does not contain. STARLING_ENGINE_OUT still overrides both.
let engineOutDir = env("STARLING_ENGINE_OUT",
                       default: sdkBundle.isEmpty
                           ? appPackageDir + "/../../engine/src/out/host_debug"
                           : sdkBundle + "/engine/lib")
#else
// Two out-directory spellings on macOS, because flutter/tools/gn appends the
// CPU only when it is not the default: an Apple Silicon build (--mac-cpu
// arm64) lands in host_debug_arm64, an Intel one in host_debug. Same probe as
// sdk/Package.swift, keyed on the same marker — picking a directory that does
// not exist would point -L and the baked rpath at nothing, and the failure
// would not surface until the app launched.
//
// iOS narrows that list to one directory rather than adding to it: a
// simulator build and a device build are different SDKs and different
// architecture slices, so probing between them would only ever find the wrong
// one first. Which one is chosen comes from STARLING_IOS, spelled exactly as
// sdk/Package.swift spells it — an environment variable and not `#if os(iOS)`
// because a manifest is compiled and run on the host, so every `#if` here
// reports macOS even mid-cross-compile. The two manifests must agree on the
// directory, and one convention is how they do.
let iosMode = env("STARLING_IOS", default: "")
let iosBuild = !iosMode.isEmpty
let engineOutDir: String = {
    if let v = Context.environment["STARLING_ENGINE_OUT"], !v.isEmpty { return v }
    // A bundle build links the bundle's own engine — the same rule the
    // Linux/Windows branch above applies, for the same reason: this Mac has an
    // engine checkout, so a "bundle" build that defaulted to the probe below
    // would link against the checkout and pass, proving nothing about what the
    // bundle contains. (iOS excepted: a desktop bundle carries no iOS engine.)
    if !iosBuild, !sdkBundle.isEmpty { return sdkBundle + "/engine/lib" }
    let candidates = iosBuild
        ? [appPackageDir + "/../../engine/src/out/"
            + (iosMode == "device" ? "ios_debug" : "ios_debug_sim_arm64")]
        : [appPackageDir + "/../../engine/src/out/host_debug_arm64",
           appPackageDir + "/../../engine/src/out/host_debug"]
    let fm = FileManager.default
    return candidates.first { fm.fileExists(atPath: $0 + "/libswift_bridge.dylib") }
        ?? candidates[0]
}()
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
let platformConstraints: [SupportedPlatform] =
    iosBuild ? [.macOS(.v14), .iOS(.v17)] : [.macOS(.v14)]
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
            if iosBuild {
                // FlutterUIKit is the Cocoa host's counterpart and carries the
                // same things with it: FlutterUIKitBridge underneath owns the
                // vendored Flutter headers and the -F/-framework that link the
                // framework. The rpath here is @executable_path/Frameworks and
                // NOT the engine out-directory — an iOS app loads its
                // libraries from inside its own bundle, and pointing at a
                // build tree would work on the simulator and fail on a device.
                return .executableTarget(
                    name: "TerminalApp",
                    dependencies: [
                        .product(name: "Flutter", package: "FlutterSwift"),
                        .product(name: "FlutterSwiftBridge", package: "FlutterSwift"),
                        .product(name: "SwiftRuntime", package: "FlutterSwift"),
                        .product(name: "CupertinoIcons", package: "FlutterSwift"),
                        .product(name: "FlutterUIKit", package: "FlutterSwift"),
                        .product(name: "CTerminalCore", package: "FlutterSwift"),
                        // The ssh client. iOS is the only platform here that
                        // needs one in-process: everywhere else the terminal
                        // reaches another machine by spawning the system
                        // `ssh`, and iOS has no fork to spawn it with.
                        .product(name: "NIOSSH", package: "swift-nio-ssh"),
                    ],
                    swiftSettings: [
                        .interoperabilityMode(.Cxx),
                    ],
                    linkerSettings: [
                        .unsafeFlags([
                            "-L\(engineOutDir)",
                            "-lswift_bridge",
                            "-Xlinker", "-rpath", "-Xlinker", "@executable_path/Frameworks",
                        ]),
                    ]
                )
            }
            // FlutterCocoa brings the engine's Cocoa embedder host in with it,
            // and FlutterCocoaBridge underneath it owns the vendored
            // FlutterMacOS headers and the -F/-framework/-rpath that link the
            // framework — so nothing here names those. What is left is the
            // Swift bridge, which on macOS is a dylib of its own beside the
            // framework rather than merged into the engine library.
            return .executableTarget(
                name: "TerminalApp",
                dependencies: [
                    .product(name: "Flutter", package: "FlutterSwift"),
                    .product(name: "FlutterSwiftBridge", package: "FlutterSwift"),
                    .product(name: "SwiftRuntime", package: "FlutterSwift"),
                    .product(name: "CupertinoIcons", package: "FlutterSwift"),
                    .product(name: "FlutterCocoa", package: "FlutterSwift"),
                    .product(name: "CTerminalCore", package: "FlutterSwift"),
                ],
                swiftSettings: [
                    .interoperabilityMode(.Cxx),
                ],
                linkerSettings: [
                    .unsafeFlags([
                        "-L\(engineOutDir)",
                        "-lswift_bridge",
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
                    .product(name: "CTerminalCore", package: "FlutterSwift"),
                ],
                swiftSettings: [
                    .interoperabilityMode(.Cxx),
                ],
                linkerSettings: [
                    .unsafeFlags([
                        "-L\(engineOutDir)",
                        "-lflutter_engine.dll",
                        // Windows picks a subsystem from the entry point, and
                        // every Swift executable's entry point is `main` — so
                        // the default link is a CONSOLE binary, and launching
                        // it from Explorer opens a console window that sits
                        // behind the terminal's own for the life of the
                        // process. A GUI app is what this is; say so.
                        //
                        // /ENTRY comes with it and is not optional:
                        // SUBSYSTEM:WINDOWS makes the linker look for
                        // WinMainCRTStartup, which wants a `WinMain` no Swift
                        // program has, and the link fails with an unresolved
                        // external rather than anything about subsystems.
                        //
                        // Logging survives: a GUI process still inherits a
                        // redirected stdout/stderr, and
                        // `flwin32_attach_parent_console` borrows the console
                        // when there is one to borrow.
                        "-Xlinker", "/SUBSYSTEM:WINDOWS",
                        "-Xlinker", "/ENTRY:mainCRTStartup",
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
]
#endif

let package = Package(
    name: "TerminalApp",
    platforms: platformConstraints.isEmpty ? nil : platformConstraints,
    // swift-nio-ssh only on the iOS build, and deliberately here rather than
    // in sdk/: the framework has no external dependencies at all — that is
    // what lets it be consumed as a path dependency with a vendored engine and
    // nothing else — and an ssh client is not framework material. It stays a
    // property of this one app until something else wants it.
    dependencies: {
        // Dev builds compile the framework out of this repo; a release build can
        // instead point at an unpacked SDK bundle, which is what an external
        // consumer gets and therefore the thing worth releasing against. The
        // bundle declares the same package name (FlutterSwift), so nothing in
        // the target list changes -- only where the sources and the engine come
        // from. It has to be a *path*: locating the bundled engine needs -L,
        // which SwiftPM classes as .unsafeFlags and forbids for a dependency
        // resolved by URL+version, so unpack the archive and name the directory.
        //
        // An env var rather than a #if, for the reason STARLING_IOS is one: a
        // manifest is compiled and run on the host.
        var deps: [Package.Dependency] = [
            .package(name: "FlutterSwift",
                     path: sdkBundle.isEmpty ? "../../sdk" : sdkBundle),
        ]
        // `iosBuild` exists only under the macOS guard above — a manifest is
        // compiled on the host, and using it bare here broke `swift build`
        // for this package on every Linux machine.
        #if os(macOS)
        if iosBuild {
            deps.append(.package(url: "https://github.com/apple/swift-nio-ssh.git",
                                 from: "0.9.0"))
        }
        #endif
        return deps
    }(),
    targets: targets,
    cxxLanguageStandard: .cxx20
)
