// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The macOS half of the example-app plumbing: the engine-data bootstrap and
// the window-host run sequence. Mirrors ExampleHost.swift (GTK, Linux) and
// ExampleHostWindows.swift.

#if os(macOS)
import CupertinoIcons
import Flutter
import FlutterSwiftBridge
import FlutterCocoa
import Foundation

/// Dev bootstrap, the counterpart of the Linux one: when `<exe dir>/data` is
/// missing (a `swift build` from the repo rather than an installed bundle),
/// assemble it as symlinks — icudtl.dat from the engine checkout
/// ($FLUTTER_SWIFT_ENGINE_OUT / $FLUTTER_ENGINE_OUT / a bundle / a sibling
/// clone), flutter_assets from this package's Resources.
///
/// icudtl.dat sits inside FlutterMacOS.framework here (Versions/A/Resources)
/// rather than beside the engine library as on Linux, so both spellings are
/// tried for each candidate directory.
public func ensureEngineData() {
    let fm = FileManager.default
    let exeDir = URL(fileURLWithPath: Bundle.main.executablePath
        ?? ProcessInfo.processInfo.arguments.first ?? ".")
        .deletingLastPathComponent().path
    let dataDir = exeDir + "/data"
    if fm.fileExists(atPath: dataDir + "/icudtl.dat") { return }

    let packageDir = URL(fileURLWithPath: #filePath)  // …/Examples/ExampleHost/ExampleHostMacOS.swift
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().path

    var engineDirs: [String] = []
    let env = ProcessInfo.processInfo.environment
    for key in ["FLUTTER_SWIFT_ENGINE_OUT", "FLUTTER_ENGINE_OUT"] {
        if let v = env[key], !v.isEmpty { engineDirs.append(v) }
    }
    // Both out-directory spellings: flutter/tools/gn appends the CPU only when
    // it is not the default, so an Apple Silicon build is host_debug_arm64 and
    // an Intel one host_debug.
    engineDirs += [
        packageDir + "/engine/lib",
        packageDir + "/../engine/src/out/host_debug_arm64",
        packageDir + "/../engine/src/out/host_debug",
        packageDir + "/../starling-engine/engine/src/out/host_debug_arm64",
        packageDir + "/../starling-engine/engine/src/out/host_debug",
    ]
    let icuCandidates = engineDirs.flatMap {
        ["\($0)/FlutterMacOS.framework/Versions/A/Resources/icudtl.dat",
         "\($0)/icudtl.dat"]
    } + [packageDir + "/engine/share/icudtl.dat"]

    guard let icu = icuCandidates.first(where: { fm.fileExists(atPath: $0) }) else {
        FileHandle.standardError.write(Data((
            "[ExampleHost] no data/ next to the executable and no engine " +
            "checkout to link from — tried " +
            icuCandidates.joined(separator: ", ") + "\n").utf8))
        return
    }
    try? fm.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
    try? fm.createSymbolicLink(atPath: dataDir + "/icudtl.dat",
                               withDestinationPath: icu)
    let assets = packageDir + "/Resources/flutter_assets"
    if fm.fileExists(atPath: assets) {
        try? fm.createSymbolicLink(atPath: dataDir + "/flutter_assets",
                                   withDestinationPath: assets)
    }
    print("[ExampleHost] Linked engine data into \(dataDir)")
}

/// The host created by runExampleApp, for apps that need window control
/// beyond mounting a widget.
public private(set) var activeCocoaHost: CocoaHost? = nil

/// Opens a window (Cocoa embedder, engine in Swift mode), mounts the app
/// widget, and runs until the window closes.
public func runExampleApp(
    title: String, width: Int = 480, height: Int = 720, root: () -> Widget
) {
    setbuf(stdout, nil)
    print("[\(title)] Starting (Cocoa host)")
    ensureEngineData()
    guard let host = CocoaHost(width: width, height: height, title: title) else {
        fatalError("[\(title)] Could not create a window or start the engine.")
    }
    activeCocoaHost = host
    host.mountWidget(root)
    host.run()
}
#endif
