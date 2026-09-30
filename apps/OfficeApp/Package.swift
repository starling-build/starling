// swift-tools-version: 6.0

import PackageDescription
import Foundation

// Office: the document suite (docs/plans/office.md). Cross-platform from the
// start — the Cocoa host on macOS is the first target, then the Starling
// shell as a DMA-BUF child, then Win32. The manifest is TerminalApp's shape
// minus the terminal core; see that file for why each branch looks the way
// it does.

func env(_ key: String, default fallback: String) -> String {
    guard let v = Context.environment[key], !v.isEmpty else { return fallback }
    return v
}

// Absolute so the -rpath baked into this app resolves regardless of the cwd
// the shell spawns it from: child processes get LD_LIBRARY_PATH scrubbed and
// fall back to their own RUNPATH.
let appPackageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

// Opt-in GTK windowed build on Linux (`STARLING_APP_GTK=1`), off by default
// so the shipped binary does not drag GTK into its link set.
let gtkHost = !env("STARLING_APP_GTK", default: "").isEmpty

// An unpacked SDK bundle to build against instead of this repo's sdk/.
let sdkBundle = env("STARLING_SDK_BUNDLE", default: "")

#if os(Linux) || os(Windows)
let engineOutDir = env("STARLING_ENGINE_OUT",
                       default: sdkBundle.isEmpty
                           ? appPackageDir + "/../../engine/src/out/host_debug"
                           : sdkBundle + "/engine/lib")
#else
// STARLING_IOS is an environment variable, not `#if os(iOS)`: a manifest is
// compiled and run on the host, so every `#if` here reports macOS.
let iosMode = env("STARLING_IOS", default: "")
let iosBuild = !iosMode.isEmpty
let engineOutDir: String = {
    if let v = Context.environment["STARLING_ENGINE_OUT"], !v.isEmpty { return v }
    if !iosBuild, !sdkBundle.isEmpty { return sdkBundle + "/engine/lib" }
    let candidates = iosBuild
        ? [appPackageDir + "/../../engine/src/out/"
            + (iosMode == "device" ? "ios_debug_arm64" : "ios_debug_sim_arm64")]
        : [appPackageDir + "/../../engine/src/out/host_debug_arm64",
           appPackageDir + "/../../engine/src/out/host_debug"]
    let fm = FileManager.default
    return candidates.first { fm.fileExists(atPath: $0 + "/libswift_bridge.dylib") }
        ?? candidates[0]
}()
#endif

// Ubuntu 26.04 (glibc 2.43 + libstdc++ 15) vs the ubuntu24.04-built 6.2.4
// toolchain: stops the C++-interop importer parsing <cmath> twice.
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

let resources: [Resource] = [
    .copy("Resources/fonts"),
]

let appTarget: Target = {
    #if os(macOS)
    if iosBuild {
        return .executableTarget(
            name: "OfficeApp",
            dependencies: [
                .product(name: "Flutter", package: "FlutterSwift"),
                .product(name: "FlutterSwiftBridge", package: "FlutterSwift"),
                .product(name: "SwiftRuntime", package: "FlutterSwift"),
                .product(name: "FluentSystemIcons", package: "FlutterSwift"),
            "CZlib",
                "CZlib",
                .product(name: "FlutterUIKit", package: "FlutterSwift"),
            ],
            resources: resources,
            swiftSettings: [.interoperabilityMode(.Cxx), .swiftLanguageMode(.v5)],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(engineOutDir)",
                    "-lswift_bridge",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/Frameworks",
                ]),
            ]
        )
    }
    return .executableTarget(
        name: "OfficeApp",
        dependencies: [
            .product(name: "Flutter", package: "FlutterSwift"),
            .product(name: "FlutterSwiftBridge", package: "FlutterSwift"),
            .product(name: "SwiftRuntime", package: "FlutterSwift"),
            .product(name: "FluentSystemIcons", package: "FlutterSwift"),
            "CZlib",
            .product(name: "FlutterCocoa", package: "FlutterSwift"),
        ],
        resources: resources,
        swiftSettings: [.interoperabilityMode(.Cxx), .swiftLanguageMode(.v5)],
        linkerSettings: [
            .unsafeFlags([
                "-L\(engineOutDir)",
                "-lswift_bridge",
                "-Xlinker", "-rpath", "-Xlinker", "\(engineOutDir)",
            ]),
        ]
    )
    #elseif os(Windows)
    return .executableTarget(
        name: "OfficeApp",
        dependencies: [
            .product(name: "Flutter", package: "FlutterSwift"),
            .product(name: "FlutterSwiftBridge", package: "FlutterSwift"),
            .product(name: "SwiftRuntime", package: "FlutterSwift"),
            .product(name: "FluentSystemIcons", package: "FlutterSwift"),
            "CZlib",
            .product(name: "FlutterWin32", package: "FlutterSwift"),
        ],
        resources: resources,
        swiftSettings: [.interoperabilityMode(.Cxx), .swiftLanguageMode(.v5)],
        linkerSettings: [
            .unsafeFlags([
                "-L\(engineOutDir)",
                "-lflutter_engine.dll",
                "-Xlinker", "/SUBSYSTEM:WINDOWS",
                "-Xlinker", "/ENTRY:mainCRTStartup",
            ]),
        ]
    )
    #else
    return .executableTarget(
        name: "OfficeApp",
        dependencies: gtkHost
            ? [
                .product(name: "FlutterShared", package: "FlutterSwift"),
                .product(name: "FluentSystemIcons", package: "FlutterSwift"),
            "CZlib",
                "CZlib",
                .product(name: "FlutterGTK", package: "FlutterSwift"),
            ]
            : [
                .product(name: "FlutterShared", package: "FlutterSwift"),
                .product(name: "FluentSystemIcons", package: "FlutterSwift"),
            "CZlib",
                "CZlib",
            ],
        resources: resources,
        swiftSettings: gtkHost
            ? [
                .interoperabilityMode(.Cxx),
                .swiftLanguageMode(.v5),
                .unsafeFlags(glibcMathCompat),
                .define("STARLING_GTK"),
            ]
            : [
                .interoperabilityMode(.Cxx),
                .swiftLanguageMode(.v5),
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

// zlib for the zip container .docx lives in (macOS SDK; zlib1g-dev on Ubuntu).
// The web build (STARLING_WASM=1, see sdk/Package.swift): no C++ interop,
// no engine, the host is the page. zlib is compiled in from the sources
// build/tools/fetch-zlib.sh puts in Vendor/zlib, since the WASI sysroot has
// no system zlib; the same CZlib module name, so Zip.swift does not know.
let wasmBuild = !env("STARLING_WASM", default: "").isEmpty

let zlibTarget: Target = wasmBuild
    ? .target(
        name: "CZlib",
        path: "Vendor/zlib",
        exclude: ["LICENSE", "VERSION"],
        publicHeadersPath: "include",
        cSettings: [.define("HAVE_UNISTD_H"), .define("Z_HAVE_STDARG_H")]
    )
    : .systemLibrary(name: "CZlib", path: "Sources/CZlib")

let webAppTarget: Target = .executableTarget(
    name: "OfficeApp",
    dependencies: [
        .product(name: "Flutter", package: "FlutterSwift"),
        .product(name: "FlutterSwiftBridge", package: "FlutterSwift"),
        .product(name: "SwiftRuntime", package: "FlutterSwift"),
        .product(name: "FluentSystemIcons", package: "FlutterSwift"),
        .product(name: "FlutterWeb", package: "FlutterSwift"),
        "CZlib",
    ],
    // No resources: the page fetches the fonts (build/web-app.sh stages
    // Resources/fonts and writes the manifest).
    exclude: ["Resources"],
    swiftSettings: [
        .swiftLanguageMode(.v5),
        .unsafeFlags(
            ["Foundation", "CoreFoundation", "FoundationInternationalization", "_FoundationICU"]
                .flatMap { ["-Xfrontend", "-disable-autolink-library", "-Xfrontend", $0] }),
        .unsafeFlags(["-Osize"], .when(configuration: .release)),
    ],
    linkerSettings: [
        .unsafeFlags([
            "-Xclang-linker", "-mexec-model=reactor",
            "-Xlinker", "--export-if-defined=__main_argc_argv",
            "-Xlinker", "-z", "-Xlinker", "stack-size=16777216",
        ]),
        .unsafeFlags(
            env("STARLING_WASM_NAMES", default: "").isEmpty
                ? ["-Xlinker", "--strip-all"] : ["-Xlinker", "--strip-debug"],
            .when(configuration: .release)),
    ]
)

let package = Package(
    name: "OfficeApp",
    platforms: (wasmBuild || platformConstraints.isEmpty) ? nil : platformConstraints,
    dependencies: [
        .package(name: "FlutterSwift",
                 path: sdkBundle.isEmpty ? "../../sdk" : sdkBundle),
    ],
    targets: [
        wasmBuild ? webAppTarget : appTarget,
        zlibTarget,
        // Round-trip tests for the file formats. `swift test --package-path
        // apps/OfficeApp` — pure Swift over the document model, no window.
        .testTarget(
            name: "OfficeAppTests",
            dependencies: ["OfficeApp"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.interoperabilityMode(.Cxx), .swiftLanguageMode(.v5)]
        ),
    ],
    cxxLanguageStandard: .cxx20
)
