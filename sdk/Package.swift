// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import PackageDescription
import Foundation

// --- Platform-conditional paths -----------------------------------------------

// Absolute path to this package's directory. engineOutDir is derived from it so
// that -L / -rpath flags resolve correctly even when this package is consumed as
// a dependency: the executable link step runs in the *consumer's* directory (e.g.
// apps/FlutterDemoApp), where a relative "../engine/..." would point at the wrong
// place. Using #filePath makes the path independent of the build invocation's cwd.
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

// Overridable by environment, because where the engine was built or unpacked is
// not a property of the package. The default is the layout this repo has always
// used, so an in-tree build still takes no configuration.
// Context.environment, not ProcessInfo: it is the API SwiftPM sanctions for
// manifests and the one it tracks for cache invalidation, so changing the
// variable actually re-evaluates the manifest. swift-corelibs-foundation reads
// CURL_LIBRARY_PATH and friends the same way.
func env(_ key: String, default fallback: String) -> String {
    guard let v = Context.environment[key], !v.isEmpty else { return fallback }
    return v
}

// No toolchain include path here any more: <swift/bridging>, the only toolchain
// header the bridge headers needed, is vendored by tools/sync-vendored-headers.sh
// and resolves through the C++ target's own include/ directory. That removed an
// absolute -I from every Swift target in the package.

// Where the engine binaries are, in precedence order:
//
//   1. $FLUTTER_SWIFT_ENGINE_OUT      — explicit override, wins always
//   2. <package>/engine/lib           — a distribution bundle (tools/make-bundle.sh);
//                                       this is what an external consumer gets
//   3. a sibling engine checkout      — developing on the engine and the framework
//                                       together, either through an `engine`
//                                       symlink beside this package or a sibling
//                                       clone of starling-engine
//
// Probing for (2) is what lets one tarball carry the framework and the engine
// together: a consumer unpacks it, depends on it by path, and needs no engine
// checkout and no configuration. Note this keeps -L/-rpath as .unsafeFlags, which
// is legal for a path dependency and is the reason the bundle is distributed as a
// directory to point at rather than a versioned SwiftPM dependency.
//
// The candidate is identified by a *file* that must exist in it, not by the
// directory: an engine out/ directory is created by `gn gen` long before anything
// is built, so testing the directory alone happily selects an empty one and the
// link fails with an unresolved -lflutter_engine instead of falling through.
func dirContaining(_ candidates: [(dir: String, marker: String)]) -> String? {
    candidates.first { FileManager.default.fileExists(atPath: $0.dir + "/" + $0.marker) }?.dir
}

// Canonicalise before this reaches a -L or an -rpath. The candidates above are
// built with "..", and this package is often reached through a symlink (the
// desktop points its repo-root `sdk` at a checkout of this repo). Clang
// normalises -L paths *lexically*: it rewrites `<repo>/sdk/../starling-engine`
// to `<repo>/starling-engine`, which is a different directory whenever `sdk` is
// a symlink pointing outside `<repo>` — and it is. The kernel resolves the
// original correctly, ld resolves it correctly, and `ls` shows the library
// sitting there, so the failure reads as an impossible
// "cannot find -lflutter_engine" against a -L you can see is right.
//
// resolvingSymlinksInPath(), not .standardized: standardized does the same
// lexical collapse clang does and reproduces the bug exactly.
func canonical(_ path: String) -> String {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else { return url.path }
    return url.resolvingSymlinksInPath().path
}

#if os(Linux)
// On Linux the Swift bridge is merged into libflutter_engine.so.
let engineLinkName = "flutter_engine"
let engineMarker = "libflutter_engine.so"
let engineCandidates = [
    packageDir + "/engine/lib",
    packageDir + "/../engine/src/out/host_debug",
    packageDir + "/../starling-engine/engine/src/out/host_debug",
]
#elseif os(Windows)
// On Windows the Swift bridge is merged into flutter_engine.dll, exactly as on
// Linux; what gets linked is that DLL's import library. GN names it after the
// DLL — flutter_engine.dll.lib — and clang's -l appends the .lib, so the link
// name has to carry the .dll.
let engineLinkName = "flutter_engine.dll"
let engineMarker = "flutter_engine.dll.lib"
let engineCandidates = [
    packageDir + "/engine/lib",
    packageDir + "/../engine/src/out/host_debug",
    packageDir + "/../starling-engine/engine/src/out/host_debug",
]
#else
// On macOS the Swift bridge is a separate libswift_bridge.dylib that sits
// alongside FlutterMacOS.framework (the engine itself) in engineOutDir.
let engineLinkName = "swift_bridge"
let engineMarker = "libswift_bridge.dylib"
let engineCandidates = [
    packageDir + "/engine/lib",
    packageDir + "/../engine/src/out/ci/host_debug_unopt_arm64",
    packageDir + "/../starling-engine/engine/src/out/ci/host_debug_unopt_arm64",
]
#endif

// nil when no engine is present locally — which flips the package into
// static mode (below) instead of pointing -L at a directory that isn't there.
let engineDirFound: String? = {
    if let v = Context.environment["FLUTTER_SWIFT_ENGINE_OUT"], !v.isEmpty { return v }
    return dirContaining(engineCandidates.map { ($0, engineMarker) })
}()

let engineOutDir = canonical(engineDirFound ?? engineCandidates[0])

// --- Linkage mode --------------------------------------------------------------
//
// dynamic — an engine checkout or bundle is present: link its .so with
//           -L/-rpath. Those are .unsafeFlags, so this mode is for path
//           consumption (in-tree development, the make-bundle.sh SDK).
// static  — no local engine: the engine arrives as a SwiftPM binaryTarget
//           (SE-0482 staticLibrary artifactbundle, tools/make-static-engine.sh)
//           and the manifest carries no unsafe linker flags at all, which is
//           what makes versioned `.package(url:from:)` consumption legal.
//           System libraries the archive expects become plain .linkedLibrary.
//
// The mode is chosen by whether an engine was found; FLUTTER_SWIFT_LINK=static
// or =dynamic overrides. On Ubuntu 26.04 the glibc math compat flags (below)
// are still unsafe and unavoidable, so versioned consumption works on other
// platforms first — see README.
#if os(Linux)
let linkModeOverride = env("FLUTTER_SWIFT_LINK", default: "")
let staticEngine = linkModeOverride == "static"
    || (linkModeOverride != "dynamic" && engineDirFound == nil)
#else
let staticEngine = false
#endif

// Where the static artifactbundle comes from: a locally built one wins (its
// checksum changes on every rebuild, so pre-release verification cannot go
// through the published URL), otherwise the released artifact.
let staticBundleLocal: String? = {
    guard staticEngine else { return nil }
    if let v = Context.environment["FLUTTER_SWIFT_ENGINE_BUNDLE"], !v.isEmpty { return v }
    let inTree = packageDir + "/.build/static-engine/FlutterEngineStatic.artifactbundle"
    return FileManager.default.fileExists(atPath: inTree + "/info.json")
        ? ".build/static-engine/FlutterEngineStatic.artifactbundle" : nil
}()
let staticBundleURL =
    "https://github.com/starling-build/starling-sdk/releases/download/v0.1.0/FlutterEngineStatic.artifactbundle.zip"
let staticBundleChecksum =
    "acc453fd93119e9d1ddd6aa1a9fcf63b545c7f8b8ae9adfee5458d7f695d4646"

// The engine .so link flags for dynamic mode; empty in static mode, where the
// binaryTarget supplies the objects and these system libraries — dynamic
// dependencies of the engine core — are declared safely instead.
let engineLinkSettings: [LinkerSetting]
let staticSystemLibs: [LinkerSetting]
#if os(Linux)
if staticEngine {
    engineLinkSettings = []
    staticSystemLibs = [
        .linkedLibrary("drm"),
        .linkedLibrary("gbm"),
        .linkedLibrary("EGL"),
        .linkedLibrary("GLESv2"),
        .linkedLibrary("input"),
        .linkedLibrary("udev"),
        .linkedLibrary("xkbcommon"),
    ]
} else {
    engineLinkSettings = [
        .unsafeFlags([
            "-L\(engineOutDir)", "-l\(engineLinkName)",
            "-Xlinker", "-rpath", "-Xlinker", "\(engineOutDir)",
        ]),
    ]
    staticSystemLibs = []
}
#elseif os(Windows)
// No rpath on Windows — the loader has no such concept. flutter_engine.dll is
// found beside the .exe (or on PATH), which is what staging arranges; the link
// step only needs the import library.
engineLinkSettings = [
    .unsafeFlags(["-L\(engineOutDir)", "-l\(engineLinkName)"]),
]
staticSystemLibs = []
#else
engineLinkSettings = [
    .unsafeFlags([
        "-L\(engineOutDir)", "-l\(engineLinkName)",
        "-Xlinker", "-rpath", "-Xlinker", "\(engineOutDir)",
    ]),
]
staticSystemLibs = []
#endif

// The 6.2.4 toolchain is an ubuntu24.04 build, and Ubuntu 26.04 — the base
// platform — pairs glibc 2.43 with libstdc++ 15. That combination makes the
// C++-interop importer parse <cmath> textually *and* from the prebuilt `std`
// module, so Foundation's C shim dies with "cmath: redefinition of 'acos'".
// Predefining libstdc++'s <math.h> include guard stops the textual pull;
// force-including glibc's math.h keeps the C declarations every TU expects.
// Identical semantics on older glibc, so it used to be applied uniformly rather
// than version-gated. Remove once the toolchain ships a native 26.04 build.
// Full write-up: docs/BUILDING.md.
//
// Applying it uniformly turned out to cost more than it looked. These are the
// last .unsafeFlags on every Swift target, and .unsafeFlags anywhere in a package
// makes the *whole* package unusable as a versioned dependency (SwiftPM rejects
// it before compiling). So they are now added only where the clash exists, which
// leaves macOS and pre-26.04 Linux consumers with a publishable package and makes
// this self-healing once the toolchain is fixed.
//
// libstdc++ 15 is the discriminator: 24.04 ships 13/14, 26.04 ships 15. That is a
// heuristic for a known-bad pairing, not a feature test — a compile probe would be
// exact but manifests are evaluated constantly and must stay cheap. Override with
// FLUTTER_SWIFT_GLIBC_MATH_COMPAT=1 or =0 when it guesses wrong.
func needsGlibcMathCompat() -> Bool {
    if let forced = ProcessInfo.processInfo.environment["FLUTTER_SWIFT_GLIBC_MATH_COMPAT"],
       !forced.isEmpty {
        return forced != "0"
    }
    let fm = FileManager.default
    guard fm.fileExists(atPath: "/usr/include/math.h") else { return false }
    let newest = ((try? fm.contentsOfDirectory(atPath: "/usr/include/c++")) ?? [])
        .compactMap { Int($0) }.max() ?? 0
    return newest >= 15
}

#if os(Linux)
let glibcMathCompat = needsGlibcMathCompat()
    ? ["-Xcc", "-D_GLIBCXX_MATH_H", "-Xcc", "-include", "-Xcc", "/usr/include/math.h"]
    : []
#else
let glibcMathCompat: [String] = []
#endif

// C++ interop plus, only where it is actually needed, the glibc compat flags.
// Built as a list so that when the compat flags are empty no .unsafeFlags setting
// is emitted at all — an empty one would still taint the package.
let cxxInteropSettings: [SwiftSetting] = glibcMathCompat.isEmpty
    ? [.interoperabilityMode(.Cxx)]
    : [.interoperabilityMode(.Cxx), .unsafeFlags(glibcMathCompat)]

// Bridge headers are vendored under Sources/FlutterSwiftBridgeCxx/include/engine
// (tools/sync-vendored-headers.sh), so compiling needs no engine checkout — the
// engine is a link-time dependency only.

// --- Products ----------------------------------------------------------------

var products: [Product] = [
    .library(name: "FlutterSwiftBridge", targets: ["FlutterSwiftBridge"]),
    .library(name: "Flutter", targets: ["Flutter"]),
    .library(name: "SwiftRuntime", targets: ["SwiftRuntime"]),
    .library(name: "CupertinoIcons", targets: ["CupertinoIcons"]),
    // The terminal emulator core: dependency-free C, shared by TerminalApp
    // today and the TerminalView widget to come (docs/plans/terminal-widget.md).
    // Its public header is the compatibility boundary; test/core/conformance.c
    // is the contract's test.
    .library(name: "CTerminalCore", targets: ["CTerminalCore"]),
]

#if os(Linux)
products += [
    .library(name: "FlutterEmbedderBridge", targets: ["FlutterEmbedderBridge"]),
    .library(name: "FlutterDRMBridge", targets: ["FlutterDRMBridge"]),
    .library(name: "DmaBufBridge", targets: ["DmaBufBridge"]),
    // Desktop-session host: the engine's own GTK embedder (FlView/FlEngine in
    // Swift mode) instead of the Starling shell — window management, input,
    // IME and a11y come from the same code path real Flutter Linux apps use.
    // Separate product so shell/DRM consumers don't inherit GTK linkage.
    .library(name: "FlutterGTK", targets: ["FlutterGTK"]),
    // The demo, runnable on a stock desktop: swift run -c release FlutterDemo.
    // Named FlutterDemo, not FlutterDemoApp: the starling desktop ships an app
    // by that name in the same package graph, and SwiftPM requires target and
    // product names to be unique across it.
    .executable(name: "FlutterDemo", targets: ["FlutterDemo"]),
    // Ports of famous Flutter sample apps, hosted the same way as the demo.
    .executable(name: "CounterApp", targets: ["CounterApp"]),
    // The twenty-line terminal built on TerminalView (Examples/TerminalDemo).
    .executable(name: "TerminalDemo", targets: ["TerminalDemo"]),
    // The same widget, tiled: a split tree of terminals with draggable seams.
    .executable(name: "TerminalTiling", targets: ["TerminalTiling"]),
    .executable(name: "StartupNamerApp", targets: ["StartupNamerApp"]),
    .executable(name: "TodosApp", targets: ["TodosApp"]),
    .executable(name: "YouTubeApp", targets: ["YouTubeApp"]),
    // The calendar package (a kalender port: day/week/month views) as a
    // library plus its demo app.
    .library(name: "CalendarKit", targets: ["CalendarKit"]),
    .executable(name: "CalendarApp", targets: ["CalendarApp"]),
    // One shared dylib carrying the whole framework stack (plus the C shim
    // modules apps import directly). Apps that link this single product get
    // binaries with only their own code — the packaged desktop ships one
    // libFlutterShared.so instead of nine statically-duplicated frameworks.
    .library(name: "FlutterShared", type: .dynamic,
             targets: ["Flutter", "SwiftRuntime", "FlutterSwiftBridge",
                       "CupertinoIcons", "FlutterEmbedderBridge", "DmaBufBridge"]),
]
#endif

#if os(macOS)
products += [
    .library(name: "FlutterMacOSBridge", targets: ["FlutterMacOSBridge"]),
]
#endif

#if os(Windows)
products += [
    // Desktop host: the engine's own Win32 embedder (flutter_windows.dll) with
    // the engine in Swift mode, rather than a hand-rolled window — so window
    // management, input, IME and accessibility come from the same code path
    // real Flutter Windows apps use. The counterpart of FlutterGTK on Linux.
    .library(name: "FlutterWin32", targets: ["FlutterWin32"]),
    // The classic `flutter create` counter, ported from Dart — the first
    // sample proven on this platform.
    .executable(name: "CounterApp", targets: ["CounterApp"]),
    // The twenty-line terminal built on TerminalView (Examples/TerminalDemo).
    .executable(name: "TerminalDemo", targets: ["TerminalDemo"]),
    // The same widget, tiled: a split tree of terminals with draggable seams.
    .executable(name: "TerminalTiling", targets: ["TerminalTiling"]),
]
#endif

// --- Targets -----------------------------------------------------------------

// FlutterEmbedderBridge and DmaBufBridge are Linux-only targets (declared under
// #if os(Linux) below). Referencing them from the Flutter target on macOS — even
// with a .linux platform condition — makes SwiftPM require the targets to exist,
// so the dependency list itself must be gated by platform.
#if os(Linux)
let flutterDeps: [Target.Dependency] = [
    "FlutterSwiftBridge",
    .target(name: "SwiftRuntime"),
    .target(name: "CTerminalCore"),
    .target(name: "FlutterEmbedderBridge"),
    .target(name: "DmaBufBridge"),
    .target(name: "WaylandClipboardBridge"),
]
#elseif os(Windows)
let flutterDeps: [Target.Dependency] = [
    "FlutterSwiftBridge",
    .target(name: "SwiftRuntime"),
    .target(name: "CTerminalCore"),
    .target(name: "CStarlingConPTY"),
]
#else
let flutterDeps: [Target.Dependency] = [
    "FlutterSwiftBridge",
    .target(name: "SwiftRuntime"),
    .target(name: "CTerminalCore"),
]
#endif

#if os(Linux)
let bridgeDeps: [Target.Dependency] = staticEngine
    ? ["FlutterSwiftBridgeCxx", "FlutterEngineStatic"]
    : ["FlutterSwiftBridgeCxx"]
#else
let bridgeDeps: [Target.Dependency] = ["FlutterSwiftBridgeCxx"]
#endif

var targets: [Target] = [
    // The terminal emulator core: dependency-free portable C (the widths
    // header is generated from python wcwidth — see the file's provenance
    // comment). Unconditional because the product is: Linux consumes it
    // today, Windows will through ConPTY. Public header starling_term.h is
    // the compatibility boundary; test/core/conformance.c is its contract.
    .target(name: "CTerminalCore"),
    // Main Swift target containing the dart:ui Swift implementation
    .target(
        name: "FlutterSwiftBridge",
        dependencies: bridgeDeps,
        swiftSettings: cxxInteropSettings,
        linkerSettings: engineLinkSettings + staticSystemLibs
    ),
    // C++ bridge module with modulemap pointing to engine headers
    .target(
        name: "FlutterSwiftBridgeCxx"
    ),
    // Flutter Framework target (Swift port of Flutter framework)
    .target(
        name: "Flutter",
        dependencies: flutterDeps,
        path: "Sources/Flutter",
        resources: [
            // TerminalView's bundled faces (see TerminalFontLoader).
            .copy("Terminal/Fonts/RobotoMono-Regular.ttf"),
            .copy("Terminal/Fonts/RobotoMono-Bold.ttf"),
            .copy("Terminal/Fonts/DejaVuSansMono-Regular.ttf"),
            .copy("Terminal/Fonts/DejaVuSansMono-Bold.ttf"),
            // Proportional, and last in the chain: the only face here with
            // braille, which every TUI spinner is made of.
            .copy("Terminal/Fonts/DejaVuSans.ttf"),
            .copy("Terminal/Fonts/DejaVu-LICENSE.txt"),
        ],
        // Language mode 5 restores the minimal concurrency checking this target
        // predates (tools-version 6.0 defaults every target to mode 6). It replaces
        // .unsafeFlags(["-strict-concurrency=minimal"]) and is a *safe* setting.
        //
        // Mode 5 is not a pure concurrency knob, though: it also turns bare regex
        // literals back off, and Foundation/Print.swift uses one
        // (`/^ *(?:[-+*] |[0-9]+[.):] )?/`), which fails to parse as
        // "unary operator cannot be separated from its operand". Re-enabling the
        // upcoming feature is itself safe, so the pair costs nothing.
        swiftSettings: cxxInteropSettings + [
            .swiftLanguageMode(.v5),
            .enableUpcomingFeature("BareSlashRegexLiterals"),
        ]
    ),
    // SwiftRuntime target -- Swift delegate that receives Shell->Framework calls
    .target(
        name: "SwiftRuntime",
        dependencies: ["FlutterSwiftBridge"],
        path: "Sources/SwiftRuntime",
        swiftSettings: cxxInteropSettings
    ),
    // CupertinoIcons -- Apple SF Symbols-style icon set (1,322 icons + TTF font)
    .target(
        name: "CupertinoIcons",
        dependencies: ["Flutter", "FlutterSwiftBridge"],
        path: "Sources/CupertinoIcons",
        resources: [
            .copy("Resources/CupertinoIcons.ttf"),
        ],
        swiftSettings: cxxInteropSettings
    ),
    // Test targets
    .testTarget(
        name: "FlutterSwiftBridgeTests",
        dependencies: ["FlutterSwiftBridge"],
        swiftSettings: cxxInteropSettings,
        linkerSettings: engineLinkSettings
    ),
    .testTarget(
        name: "FlutterTests",
        dependencies: ["Flutter"],
        path: "Tests/FlutterTests",
        swiftSettings: cxxInteropSettings,
        linkerSettings: engineLinkSettings
    ),
    .testTarget(
        name: "SwiftRuntimeTests",
        dependencies: ["SwiftRuntime", "FlutterSwiftBridge"],
        path: "Tests/SwiftRuntimeTests",
        swiftSettings: cxxInteropSettings,
        linkerSettings: engineLinkSettings
    ),
]

// --- macOS-only targets ------------------------------------------------------

#if os(macOS)
targets += [
    .target(
        name: "FlutterMacOSBridge",
        cSettings: [
            .unsafeFlags([
                "-I", "\(engineOutDir)/FlutterMacOS.framework/Versions/A/Headers",
            ]),
        ]
    ),
]
#endif

// --- Windows-only targets ----------------------------------------------------

#if os(Windows)
targets += [
    // C glue around the engine's Win32 embedder: a top-level window hosting
    // the view controller's child HWND, with the engine in Swift mode. The
    // vendored flutter_windows headers stay inside this target — <windows.h>
    // defines several thousand macros and must never reach the C++-interop
    // importer. Same containment the GTK bridge gives flutter_linux.
    // ConPTY shim for the terminal's Windows PTY (moved from TerminalApp
    // with the TerminalSession extraction).
    .target(name: "CStarlingConPTY"),
    .target(
        name: "FlutterWin32Bridge",
        linkerSettings: [
            .unsafeFlags([
                "-L\(engineOutDir)", "-lflutter_windows.dll",
            ]),
        ]
    ),
    // The desktop host: the real Flutter Windows embedder, Swift-driven.
    .target(
        name: "FlutterWin32",
        dependencies: [
            "Flutter",
            "FlutterSwiftBridge",
            .target(name: "SwiftRuntime"),
            .target(name: "FlutterWin32Bridge"),
        ],
        swiftSettings: cxxInteropSettings + [.swiftLanguageMode(.v5)]
    ),
    // Shared plumbing for the ported example apps: the engine-data bootstrap,
    // the run sequence, and the Material-look chrome. Same target as on Linux,
    // hosted on FlutterWin32 instead of FlutterGTK.
    .target(
        name: "ExampleHost",
        dependencies: [
            "Flutter",
            "FlutterWin32",
            "FlutterSwiftBridge",
            "CupertinoIcons",
            .target(name: "SwiftRuntime"),
        ],
        path: "Examples/ExampleHost",
        swiftSettings: cxxInteropSettings + [.swiftLanguageMode(.v5)]
    ),
    // The classic `flutter create` counter, ported from Dart.
    .executableTarget(
        name: "CounterApp",
        dependencies: [
            "Flutter",
            "ExampleHost",
            "FlutterSwiftBridge",
            "CupertinoIcons",
        ],
        path: "Examples/CounterApp",
        swiftSettings: cxxInteropSettings + [.swiftLanguageMode(.v5)],
        linkerSettings: engineLinkSettings
    ),
]
#endif

// --- Linux-only targets ------------------------------------------------------

#if os(Linux)
targets += [
    // Clang module exposing Flutter embedder API to Swift
    .target(
        name: "FlutterEmbedderBridge"
    ),
    // Clang module exposing DRM shell public API (fl_drm_view.h) to Swift
    .target(
        name: "FlutterDRMBridge"
    ),
    // Clang module wrapping GBM + SCM_RIGHTS + EGL DMA-BUF import helpers.
    // No cSettings: this target used to carry -I/usr/include/libdrm, but it
    // includes only <gbm.h>, EGL, GLES2 and libc — nothing here reaches a libdrm
    // header, directly or transitively. The flag was dead weight.
    .target(
        name: "DmaBufBridge",
        linkerSettings: [
            .linkedLibrary("gbm"),
            .linkedLibrary("EGL"),
            .linkedLibrary("GLESv2"),
        ]
    ),
    // The system clipboard for a Starling app, spoken as a zwlr_data_control
    // client on its own thread. Vendors the wayland-scanner output for the
    // protocol the same way shell/Sources/WaylandServer does, so no build-time
    // codegen step is needed.
    //
    // This does put libwayland-client on every Linux consumer of Flutter. That
    // is in keeping with what is already there — DmaBufBridge hangs gbm, EGL
    // and GLESv2 off the same target — and it buys a Clipboard that is not a
    // stub. wlclip_connect() returns NULL wherever data-control is absent, so
    // linking it off Starling costs nothing but the .so reference.
    .target(
        name: "WaylandClipboardBridge",
        exclude: ["wlr-data-control-unstable-v1.xml"],
        linkerSettings: [
            .linkedLibrary("wayland-client"),
        ]
    ),
    // System GTK 3 via pkg-config — supplies GTK/GLib include paths and libs
    // to dependents without hardcoding multiarch paths.
    .systemLibrary(
        name: "CGtk3",
        path: "Sources/CGtk3",
        pkgConfig: "gtk+-3.0",
        providers: [.apt(["libgtk-3-dev"])]
    ),
    // C glue around the engine's GTK embedder: FlView in a GtkWindow with the
    // engine in Swift mode. The vendored flutter_linux headers stay inside
    // this target — GTK types never reach the C++-interop importer.
    // In static mode the fl_* symbols come out of the engine archive (the
    // GTK embedder is merged into it) and epoxy — a dynamic dependency the
    // shared library would have carried as NEEDED — is declared explicitly.
    .target(
        name: "FlutterGTKBridge",
        dependencies: staticEngine
            ? ["CGtk3", "DmaBufBridge", "FlutterEngineStatic"]
            : ["CGtk3", "DmaBufBridge"],
        linkerSettings: staticEngine
            ? [.linkedLibrary("epoxy")]
            : [
                .unsafeFlags([
                    "-L\(engineOutDir)", "-lflutter_linux_gtk",
                    "-Xlinker", "-rpath", "-Xlinker", "\(engineOutDir)",
                ]),
            ]
    ),
    // The desktop-session host: the real Flutter Linux embedder, Swift-driven.
    .target(
        name: "FlutterGTK",
        dependencies: [
            "Flutter",
            "FlutterSwiftBridge",
            .target(name: "SwiftRuntime"),
            .target(name: "FlutterGTKBridge"),
        ],
        swiftSettings: cxxInteropSettings + [.swiftLanguageMode(.v5)]
    ),
    // The demo app (rotating boxes + frame-time graph) as a runnable proof
    // that the standalone framework can present on a normal desktop.
    .executableTarget(
        name: "FlutterDemo",
        dependencies: [
            "Flutter",
            "FlutterGTK",
            "FlutterSwiftBridge",
            .target(name: "SwiftRuntime"),
        ],
        path: "Examples/FlutterDemoApp",
        swiftSettings: cxxInteropSettings + [.swiftLanguageMode(.v5)],
        linkerSettings: engineLinkSettings
    ),
]

// The ported example apps, appended separately: one more entry in the array
// literal above tips the manifest type-checker over its time budget.
//
// App targets live under Examples/ (explicit `path:`), keeping Sources/ to
// the SDK — the targets a consumer can depend on.
targets += [
    // Shared plumbing for the ported example apps: the engine-data bootstrap,
    // the GTK run sequence, and the Material-look chrome the classic samples
    // are styled with.
    .target(
        name: "ExampleHost",
        dependencies: [
            "Flutter",
            "FlutterGTK",
            "FlutterSwiftBridge",
            "CupertinoIcons",
            .target(name: "SwiftRuntime"),
        ],
        path: "Examples/ExampleHost",
        swiftSettings: cxxInteropSettings + [.swiftLanguageMode(.v5)]
    ),
    // The classic `flutter create` counter, ported from Dart.
    .executableTarget(
        name: "CounterApp",
        dependencies: [
            "Flutter",
            "ExampleHost",
            "FlutterSwiftBridge",
            "CupertinoIcons",
        ],
        path: "Examples/CounterApp",
        swiftSettings: cxxInteropSettings + [.swiftLanguageMode(.v5)],
        linkerSettings: engineLinkSettings
    ),
    // The "Write your first Flutter app" codelab (startup_namer), ported.
    .executableTarget(
        name: "StartupNamerApp",
        dependencies: [
            "Flutter",
            "ExampleHost",
            "FlutterSwiftBridge",
            "CupertinoIcons",
        ],
        path: "Examples/StartupNamerApp",
        swiftSettings: cxxInteropSettings + [.swiftLanguageMode(.v5)],
        linkerSettings: engineLinkSettings
    ),
    // The todo-list classic, on the framework's FluentUI widget set.
    .executableTarget(
        name: "TodosApp",
        dependencies: [
            "Flutter",
            "ExampleHost",
            "FlutterSwiftBridge",
            "CupertinoIcons",
        ],
        path: "Examples/TodosApp",
        swiftSettings: cxxInteropSettings + [.swiftLanguageMode(.v5)],
        linkerSettings: engineLinkSettings
    ),
]

// Appended separately for the same type-checker-budget reason as the block
// above. (TaskManagerApp lived here as an example; it moved to the desktop's
// apps/TaskManagerApp, booting through runStarlingApp — same code, either
// backend.)
targets += [
    // System GStreamer (core + appsink) via pkg-config, for the YouTube
    // example's software video path. Lives in Examples/ because only the
    // example apps use it — Sources/ stays SDK-only.
    .systemLibrary(
        name: "CGStreamer",
        path: "Examples/CGStreamer",
        pkgConfig: "gstreamer-app-1.0",
        providers: [.apt(["libgstreamer1.0-dev", "libgstreamer-plugins-base1.0-dev"])]
    ),
    // A YouTube player: yt-dlp searches and resolves streams, GStreamer
    // decodes, and each frame becomes a Skia image drawn by a CustomPaint —
    // no platform texture involved.
    .executableTarget(
        name: "YouTubeApp",
        dependencies: [
            "Flutter",
            "ExampleHost",
            "FlutterSwiftBridge",
            "CupertinoIcons",
            "CGtk3",
            "CGStreamer",
            "DmaBufBridge",
            "FlutterGTK",
        ],
        path: "Examples/YouTubeApp",
        swiftSettings: cxxInteropSettings + [.swiftLanguageMode(.v5)],
        linkerSettings: engineLinkSettings
    ),
]

// The calendar port, appended separately for the same type-checker-budget
// reason as the block above.
targets += [
    // The calendar package (a port of werner-scholtz/kalender): the calendar
    // BLoC, view configurations, the event-overlap and multi-day layout
    // delegates, and the day/week/month views. It lives in Examples/ with the
    // app it serves — a ported third-party package, not part of the SDK — but
    // stays a library product so it can be depended on. Named CalendarKit
    // because a module literally named Calendar would fight Foundation's
    // Calendar type at every use site.
    .target(
        name: "CalendarKit",
        dependencies: [
            "Flutter",
            "FlutterSwiftBridge",
        ],
        path: "Examples/Calendar/Library",
        swiftSettings: cxxInteropSettings + [.swiftLanguageMode(.v5)]
    ),
    // The calendar package's demo: a week view with a view switcher.
    .executableTarget(
        name: "CalendarApp",
        dependencies: [
            "Flutter",
            "CalendarKit",
            "ExampleHost",
            "FlutterSwiftBridge",
            "CupertinoIcons",
        ],
        path: "Examples/Calendar/App",
        swiftSettings: cxxInteropSettings + [.swiftLanguageMode(.v5)],
        linkerSettings: engineLinkSettings
    ),
]

// The engine as a binary target (static mode only): one archive carrying the
// embedder core, the Swift bridge, the DRM view and the GTK embedder. Its
// module declares nothing — headers come from this package's targets; the
// artifact exists to be linked.
if staticEngine {
    if let local = staticBundleLocal {
        targets += [.binaryTarget(name: "FlutterEngineStatic", path: local)]
    } else {
        targets += [.binaryTarget(
            name: "FlutterEngineStatic",
            url: staticBundleURL,
            checksum: staticBundleChecksum
        )]
    }
}
#endif

// --- Cross-platform example apps ---------------------------------------------

// The twenty-line terminal: TerminalSession + TerminalView, nothing else.
// Declared as a product on BOTH Linux and Windows, so the target append must
// sit outside either platform's region — inside `#if os(Linux)` the Windows
// product dangled and SwiftPM refused the whole graph, so *nothing* built on
// Windows. ExampleHost is the Win32-hosted target there; CounterApp above is
// the same shape.
//
// Its own append — every targets literal here sits near the manifest
// type-checker's time budget, and one more entry in either tips it over.
#if os(Linux) || os(Windows)
targets += [
    .executableTarget(
        name: "TerminalDemo",
        dependencies: [
            "Flutter",
            "ExampleHost",
            "FlutterSwiftBridge",
        ],
        path: "Examples/TerminalDemo",
        swiftSettings: cxxInteropSettings + [.swiftLanguageMode(.v5)],
        linkerSettings: engineLinkSettings
    ),
]

// The tiling workspace (Examples/TerminalTiling) — same dependencies as
// TerminalDemo, and its own append for the same reason: every targets
// literal here sits near the manifest type-checker's time budget.
targets += [
    .executableTarget(
        name: "TerminalTiling",
        dependencies: [
            "Flutter",
            "ExampleHost",
            "FlutterSwiftBridge",
        ],
        path: "Examples/TerminalTiling",
        swiftSettings: cxxInteropSettings + [.swiftLanguageMode(.v5)],
        linkerSettings: engineLinkSettings
    ),
]
#endif

// --- Package declaration -----------------------------------------------------

#if os(macOS)
let platformConstraints: [SupportedPlatform] = [.macOS(.v14)]
#else
let platformConstraints: [SupportedPlatform] = []
#endif

let package = Package(
    name: "FlutterSwift",
    platforms: platformConstraints.isEmpty ? nil : platformConstraints,
    products: products,
    targets: targets,
    cxxLanguageStandard: .cxx20
)
