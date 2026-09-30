// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Office — entry point. Picks the windowed host for this platform (or runs
// as a Starling shell child when FLUTTER_DMABUF_SOCKET is set) and mounts
// the Fluent-rooted app.
//
//   swift run OfficeApp [file]                 open a document
//   OFFICE_DEMO_PAGES=200 swift run OfficeApp  the Phase 0 perf document

import Flutter
import FlutterSwiftBridge
import Foundation

#if os(Windows)
import FlutterWin32
#elseif os(macOS)
import FlutterCocoa
#elseif os(iOS)
import FlutterUIKit
#elseif STARLING_GTK
import FlutterGTK
#endif

#if os(Windows)
Win32WindowedHost.install()
#elseif os(macOS)
CocoaWindowedHost.install()
#elseif os(iOS)
UIKitWindowedHost.install()
#elseif STARLING_GTK
GTKWindowedHost.install()
#endif

private func windowMetric(_ key: String, _ fallback: Int) -> Int {
    guard let v = ProcessInfo.processInfo.environment[key], let n = Int(v), n > 0
    else { return fallback }
    return n
}

let initialPath: String? = {
    let args = CommandLine.arguments
    if args.count > 1 && !args[1].hasPrefix("-") { return args[1] }
    return nil
}()

runStarlingApp(title: "Office",
               width: windowMetric("STARLING_WINDOW_W", 1280),
               height: windowMetric("STARLING_WINDOW_H", 820)) {
    OfficeRoot(initialPath: initialPath)
}
