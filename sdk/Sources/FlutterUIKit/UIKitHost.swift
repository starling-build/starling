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
            // A removed view's builder and pipeline are let go of (the pipeline in the next frame).
            fluikit_host_set_view_gone_handler({ _, id in releaseView(id: Int(id)) }, nil)
            let box = Unmanaged<Box>.fromOpaque(userData).takeUnretainedValue()
            // The second-surface spike (docs/plans/ipad-multi-window.md, step 1): with
            // STARLING_SPIKE_SECOND_VIEW set, the host adds a second view in a corner of
            // the window (fluikit_host.m) and this is the tree it shows.
            // STARLING_SPIKE_SECOND_VIEW=list: view 1 is a real scrolling list (runView), so a drag
            // on it must scroll that list and nothing in view 0.
            if ProcessInfo.processInfo.environment["STARLING_SPIKE_SECOND_VIEW"] == "list" {
                runView(id: 1) { SpikeList(viewId: 1) }
            }
            if ProcessInfo.processInfo.environment["STARLING_SPIKE_SECOND_VIEW"] != nil {
                multiViewContentBuilder = { view in
                    // STARLING_SPIKE_EMPTY_TREE: a view with nothing in it (isolates the leak from the tree).
                    if ProcessInfo.processInfo.environment["STARLING_SPIKE_EMPTY_TREE"] != nil {
                        return SizedBox(width: 1, height: 1) as Widget
                    }
                    return SpikeTapTile(viewId: view.viewId) as Widget
                }
            }
            runApp(box.builder())
            TextInputChannel.keyViewChanged = { fluikit_text_input_host(Int64($0)) }
            TextInputChannel.viewOrigin = { id in
                var x = 0.0, y = 0.0
                return fluikit_view_origin(Int64(id), &x, &y) ? (x, y) : nil
            }
            UIKitScriptedInput.runIfRequested()
            UIKitSelfTest.runIfRequested()
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
    /// Brings extra view `id` (see `runView`) in front of the others in the window.
    public static func raiseExtraView(_ id: Int) { fluikit_view_raise(Int64(id)) }

    /// Brings the window (scene) that shows view `id` to the front; nothing if no window shows it.
    public static func activateScene(_ id: Int) { fluikit_scene_activate(Int64(id)) }

    /// Asks the system to close the window that shows view `id` (never the first window).
    public static func closeScene(_ id: Int) { fluikit_scene_close(Int64(id)) }

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

// The second-surface spike's tree: a tile that counts the taps it gets and changes colour on each,
// so a touch routed to the second view shows on screen and in the log.
private final class SpikeTapTile: StatefulWidget {
    let viewId: Int
    init(viewId: Int) {
        self.viewId = viewId
        super.init(key: nil)
    }
    override func createState() -> State<StatefulWidget> { SpikeTapTileState() }
}

private final class SpikeTapTileState: State<StatefulWidget> {
    private var taps = 0
    override func build(_ context: any BuildContext) -> Widget {
        let id = (widget as! SpikeTapTile).viewId
        return Directionality(textDirection: .ltr, child:
            GestureDetector(onTap: { [weak self] in
                guard let self else { return }
                self.setState { self.taps += 1 }
                fputs("[spike] view \(id) tap \(self.taps)\n", stderr)
            }, child:
                ColoredBox(color: taps % 2 == 0 ? Color(0xFF2E7D32) : Color(0xFFEF6C00), child:
                    Center(child: Text(ProcessInfo.processInfo.environment["STARLING_SPIKE_FIXED_TEXT"] != nil ? "view" : "view \(id): \(taps) taps",
                                       style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 28))))))
    }
}

// The test host's real second view: a scrolling list of tappable rows. Its taps and its scroll offset
// are the proof that a view of its own gets its own hit test, gesture arena and metrics.
private final class SpikeList: StatefulWidget {
    let viewId: Int
    init(viewId: Int) {
        self.viewId = viewId
        super.init(key: nil)
    }
    override func createState() -> State<StatefulWidget> { SpikeListState() }
}

private final class SpikeListState: State<StatefulWidget> {
    private var picked = -1
    override func build(_ context: any BuildContext) -> Widget {
        let id = (widget as! SpikeList).viewId
        return Directionality(textDirection: .ltr, child:
            ColoredBox(color: Color(0xFFFFFFFF), child:
                ListView(itemCount: 60) { [weak self] _, i in
                    GestureDetector(onTap: { [weak self] in
                        guard let self else { return }
                        self.setState { self.picked = i }
                        fputs("[spike] view \(id) row \(i) tapped\n", stderr)
                    }, child:
                        ColoredBox(color: i == self?.picked ? Color(0xFFFFE082) : (i % 2 == 0 ? Color(0xFFE3F2FD) : Color(0xFFFFFFFF)), child:
                            SizedBox(height: 44, child:
                                Center(child: Text("view \(id) row \(i)",
                                                   style: TextStyle(color: Color(0xFF000000), fontSize: 18))))))
                }))
    }
}
