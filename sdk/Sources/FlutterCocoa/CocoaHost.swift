// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Runs a FlutterSwift app the way a real Flutter macOS app runs: inside the
// engine's Cocoa embedder (FlutterMacOS.framework), which owns the view, the
// Metal rendering surface, pointer/keyboard input, IME and accessibility. The
// engine is started in Swift mode, so this framework drives frames through the
// SwiftRuntimeCallbacks table instead of a Dart isolate.
//
// All AppKit/embedder mechanics live in the ObjC glue (FlutterCocoaBridge);
// this type only owns the callback table's lifetime and the run sequence. The
// counterpart of FlutterGTK's GTKHost and FlutterWin32's Win32Host.

#if os(macOS)
import Flutter
import FlutterSwiftBridge
import SwiftRuntime
import FlutterCocoaBridge
import Foundation

public final class CocoaHost {

    private let host: OpaquePointer
    // The engine holds this pointer for its lifetime; heap-allocate so it
    // never moves and never dies before the process does.
    private let callbacks: UnsafeMutablePointer<SwiftRuntimeCallbacks>

    /// Creates the window, the engine and the view, and starts the engine in
    /// Swift mode. Returns nil if the engine could not be created or started.
    ///
    /// `assetsPath`/`icuDataPath` default to `<executable dir>/data/…`, the
    /// same layout the GTK and Win32 hosts use. They are passed to the engine
    /// explicitly rather than left to FlutterDartProject's bundle lookup,
    /// which resolves inside a `.app` — something a `swift build` executable
    /// is not.
    public init?(width: Int, height: Int, title: String,
                 assetsPath: String? = nil, icuDataPath: String? = nil) {
        let dataDir = CocoaHost.executableDirectory + "/data"
        let assets = assetsPath ?? (dataDir + "/flutter_assets")
        let icu = icuDataPath ?? (dataDir + "/icudtl.dat")

        callbacks = UnsafeMutablePointer<SwiftRuntimeCallbacks>.allocate(capacity: 1)
        callbacks.initialize(to: createRuntimeCallbacks())
        guard let host = flcocoa_host_create(title, Int32(width), Int32(height),
                                             assets, icu,
                                             UnsafeRawPointer(callbacks)) else {
            callbacks.deinitialize(count: 1)
            callbacks.deallocate()
            return nil
        }
        self.host = host
    }

    /// Sets up the widget binding. Call before run() — the tree must be
    /// mounted by the time the engine requests the first frame.
    public func mountWidget(_ builder: () -> Widget) {
        runApp(builder())
    }

    /// Shows the window and runs the AppKit event loop. Returns when the
    /// window is closed.
    public func run() {
        flcocoa_host_show(host)
        flcocoa_host_run(host)
    }

    /// Fullscreens or restores the window.
    public func setFullscreen(_ fullscreen: Bool) {
        flcocoa_host_set_fullscreen(host, fullscreen ? 1 : 0)
    }

    /// The directory holding this process's executable. Bundle.main resolves
    /// this for a bare Mach-O too — it is the binary's own path when there is
    /// no bundle around it — and argv[0] is the fallback for the case where
    /// there is no main bundle at all.
    static var executableDirectory: String {
        let exe = Bundle.main.executablePath
            ?? ProcessInfo.processInfo.arguments.first
            ?? "."
        return URL(fileURLWithPath: exe).deletingLastPathComponent().path
    }
}
#endif
