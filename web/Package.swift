// swift-tools-version:6.0
// The browser build. A package of its own rather than targets in sdk/,
// because sdk/'s manifest turns on C++ interop for every Swift target and
// the WebAssembly Swift SDK cannot compile a module that imports C++
// (docs/plans/wasm.md). Nothing here uses it: the engine boundary on the web
// is skwasm's C exports.
//
// Build with build/web-app.sh, which also assembles the page.
import PackageDescription

let package = Package(
    name: "StarlingWeb",
    targets: [
        // Declarations only. Every function in it is a WebAssembly import,
        // resolved by the page when it instantiates the module.
        .target(name: "CSkwasm"),
        .executableTarget(
            name: "Pixels",
            dependencies: ["CSkwasm"],
            linkerSettings: [
                // A reactor, not a command: the page calls into the module
                // once per frame for as long as the tab lives, so there is no
                // `_start` that runs and exits. `_initialize` sets the runtime
                // up and main.swift's top level is exported to be called once.
                .unsafeFlags([
                    "-Xclang-linker", "-mexec-model=reactor",
                    "-Xlinker", "--export-if-defined=__main_argc_argv",
                ])
            ]
        ),
    ]
)
