// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Runs a FlutterSwift app the way a real Flutter iOS app runs: inside the
// engine's iOS embedder (Flutter.framework), which owns the view, the Metal
// rendering surface, touch input, the software keyboard, text editing and
// accessibility. The engine is started in Swift mode, so this framework drives
// frames through the SwiftRuntimeCallbacks table instead of a Dart isolate.
//
// All UIKit/embedder mechanics live in the ObjC glue (FlutterUIKitBridge);
// this type only owns the callback table's lifetime and the run sequence. The
// counterpart of FlutterCocoa's CocoaHost, FlutterGTK's GTKHost and
// FlutterWin32's Win32Host.
//
// The shape differs from the other three in one way, and iOS forces it: there
// is no create/mount/run split. UIApplicationMain owns the launch sequence,
// the engine can only be created inside a delegate callback it drives, and it
// never returns. So `run` takes the widget tree rather than a prior
// `mountWidget` call having stashed it.

#if os(iOS)
import Flutter
import FlutterSwiftBridge
import SwiftRuntime
import FlutterUIKitBridge
import Foundation

public final class UIKitHost {

    // The engine holds this pointer for its lifetime; heap-allocate so it
    // never moves and never dies before the process does.
    private let callbacks: UnsafeMutablePointer<SwiftRuntimeCallbacks>

    /// The widget tree, kept until the delegate calls back for it. It cannot
    /// be built any earlier than that — mounting runs `initState` on every
    /// stateful widget in the tree, and those may touch a framework that is
    /// only alive once the engine is.
    private let builder: () -> Widget

    public init(builder: @escaping () -> Widget) {
        callbacks = UnsafeMutablePointer<SwiftRuntimeCallbacks>.allocate(capacity: 1)
        callbacks.initialize(to: createRuntimeCallbacks())
        self.builder = builder
    }

    /// Creates the engine, starts it in Swift mode, mounts the tree and hands
    /// the process to UIKit. Does not return: UIApplicationMain exits rather
    /// than unwinding, so anything after a call to this is unreachable.
    public func run(title: String) -> Never {
        // Unbalanced by design. The box is read once, inside the callback, and
        // the process ends with UIKit rather than returning here — so there is
        // no point at which releasing it would be correct, and taking a
        // retained pointer is what keeps it alive across the C boundary.
        let box = Unmanaged.passRetained(Box(builder)).toOpaque()
        _ = fluikit_host_run(title, UnsafeRawPointer(callbacks), { userData in
            guard let userData else { return }
            // The bridge dylib has its own ICU, and it starts empty: until it is
            // given the data Flutter.framework carries, no paragraph has a line
            // break inside a run — text breaks only where the style changes and
            // otherwise runs on past the margin. (sdk/CLAUDE.md; CocoaHost does
            // the same.) Before the tree, so no paragraph is built without it.
            UIKitHost.initializeBridgeICU()
            // Before the tree is mounted: a widget's initState may already want
            // to know whether this host has a keyboard to offer.
            UIKitSoftKeyboard.install()
            let box = Unmanaged<Box>.fromOpaque(userData).takeUnretainedValue()
            // The second-surface spike (docs/plans/ipad-multi-window.md, step 1): with
            // STARLING_SPIKE_SECOND_VIEW set, the host adds a second view in a corner of
            // the window (fluikit_host.m) and this is the tree it shows.
            if ProcessInfo.processInfo.environment["STARLING_SPIKE_SECOND_VIEW"] != nil {
                multiViewContentBuilder = { view in
                    Directionality(textDirection: .ltr, child:
                        ColoredBox(color: Color(0xFF2E7D32), child:
                            Center(child: Text("view \(view.viewId)",
                                               style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 28)))))
                }
            }
            runApp(box.builder())
        }, box)
        // UIApplicationMain only returns on a failure to launch at all, and the
        // glue has already said why on stderr.
        exit(1)
    }

    /// Where the engine's ICU data is: inside the app's Flutter.framework.
    public static var icuDataPath: String? {
        Bundle.main.privateFrameworksPath.map { $0 + "/Flutter.framework/icudtl.dat" }
            .flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
    }

    /// Gives the Swift bridge's own ICU the data. Safe to call more than once.
    public static func initializeBridgeICU() {
        guard let path = icuDataPath else {
            FileHandle.standardError.write(
                "[UIKitHost] no icudtl.dat in Flutter.framework; paragraphs will not wrap at word boundaries\n".data(using: .utf8)!)
            return
        }
        if !flutter.swift_bridge.InitializeICU(path) {
            FileHandle.standardError.write("[UIKitHost] could not load ICU data for the Swift bridge: \(path)\n".data(using: .utf8)!)
        }
    }

    /// The window iOS gave the app, in logical pixels. Valid once the tree has
    /// been mounted; zero before that.
    public static var windowSize: (width: Double, height: Double) {
        var w = 0.0, h = 0.0
        fluikit_host_window_size(&w, &h)
        return (w, h)
    }

    /// A class box, because a Swift closure is not a C pointer and the glue
    /// hands the callback back a bare `void*`.
    private final class Box {
        let builder: () -> Widget
        init(_ builder: @escaping () -> Widget) { self.builder = builder }
    }
}
#endif
