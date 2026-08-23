// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Widget-to-RenderObject bridge and `runApp()` entry point.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/binding.dart` (runApp),
///                  `packages/flutter/lib/src/widgets/binding.dart` (RenderObjectToWidgetAdapter)

import FlutterSwiftBridge
@preconcurrency import Foundation

// MARK: - Frame timing

/// STARLING_FRAME_LOG=1: one stderr line per composited frame with the
/// build / layout / paint / composite / finalize split, in microseconds.
/// External CPU sampling cannot attribute per-frame costs (the dead end
/// documented in docs/plans/winshell-perf.md); this is the timer it asks
/// for. Same convention as STARLING_SWAPCHAIN_DEBUG. FileHandle rather
/// than print(): print is block-buffered through pipes and the consumer
/// of this log IS a pipe.
private let frameLogEnabled =
    (ProcessInfo.processInfo.environment["STARLING_FRAME_LOG"] ?? "") == "1"

private func frameLogNow() -> UInt64 {
    frameLogEnabled ? DispatchTime.now().uptimeNanoseconds : 0
}

private func frameLogWrite(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}

// MARK: - RenderObjectToWidgetAdapter

/// A `RenderObjectWidget` that bridges a widget subtree to an existing
/// `RenderView`.
///
/// This is the root widget used by `runApp()` to connect the widget tree
/// to the render tree.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/binding.dart:1648`
public class RenderObjectToWidgetAdapter: RenderObjectWidget {
    public let child: Widget?
    public let container: RenderView

    public init(child: Widget?, container: RenderView) {
        self.child = child
        self.container = container
        super.init()
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return container
    }

    public override func createElement() -> Element {
        return RenderObjectToWidgetElement(self)
    }

    /// Creates the root element and attaches it to the build owner.
    ///
    /// If `element` is nil, a new `RenderObjectToWidgetElement` is created
    /// and mounted. Otherwise the existing element is updated.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/binding.dart:1688`
    public func attachToRenderTree(
        _ owner: BuildOwner,
        _ element: RenderObjectToWidgetElement? = nil
    ) -> RenderObjectToWidgetElement {
        if let element = element {
            element.update(self)
            return element
        }
        let newElement = createElement() as! RenderObjectToWidgetElement
        newElement.owner = owner
        owner.buildScopeWithCallback(newElement) {
            newElement.mount(nil, nil)
        }
        return newElement
    }
}

// MARK: - RenderObjectToWidgetElement

/// Root element that bridges the widget tree to the `RenderView`.
///
/// Manages a single child widget and inserts/removes its render object
/// as the child of the `RenderView`.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/binding.dart:1714`
public class RenderObjectToWidgetElement: RenderTreeRootElement, RootElementMixin {
    private var _child: Element?

    public override func mount(_ parent: Element?, _ newSlot: Any?) {
        super.mount(parent, newSlot)
        _rebuild()
    }

    private func _rebuild() {
        _child = updateChild(
            _child,
            newWidget: (widget as! RenderObjectToWidgetAdapter).child,
            newSlot: nil
        )
    }

    public override func visitChildElements(_ visitor: (Element) -> Void) {
        if let child = _child {
            visitor(child)
        }
    }

    public override func insertRenderObjectChild(_ child: RenderObject, _ slot: Any?) {
        let renderView = renderObject as! RenderView
        renderView.child = child as? RenderBox
    }

    public override func removeRenderObjectChild(_ child: RenderObject, _ slot: Any?) {
        let renderView = renderObject as! RenderView
        renderView.child = nil
    }
}

// MARK: - runApp

/// Inflate the given widget and attach it to the screen.
///
/// Set by SIGUSR1 handler to force a composite on the next frame,
/// allowing the DRM screenshot glReadPixels to capture the current state.
public nonisolated(unsafe) var _forceNextComposite = false

/// Builds the widget tree for a non-implicit `FlutterView` (multi-monitor:
/// one Flutter view per output). Set before `runApp`. When the engine adds
/// a view, the next frame builds its widget tree with this and renders it
/// every frame alongside the implicit view. When nil (the default), added
/// views get no content and are never rendered.
public nonisolated(unsafe) var multiViewContentBuilder: ((FlutterView) -> Widget)? = nil

/// Called once per non-implicit view, right after its FIRST scene is
/// composited — the moment a host that kept the view's window hidden can
/// show it without exposing an unpainted surface (the Win32 popup surfaces
/// open hidden and show here, which is what keeps a menu from flashing as
/// a flat rectangle before its first present).
public nonisolated(unsafe) var multiViewFirstComposite: ((Int) -> Void)? = nil

/// Called after EVERY composite of a non-implicit view (the first one
/// included, after `multiViewFirstComposite`). What a POOLED popup's reopen
/// waits on: its hidden view keeps compositing, and the safe moment to show
/// the window again is the composite that carries the reopened menu's
/// rebuild — a timer can only guess at that, this observes it.
public nonisolated(unsafe) var multiViewComposited: ((Int) -> Void)? = nil

/// The render/build pipeline of one non-implicit view (multi-monitor).
private final class SecondaryViewPipeline {
    let renderView: RenderView
    let pipelineOwner: PipelineOwner
    let rootElement: RenderObjectToWidgetElement
    var hasComposited = false

    init(
        renderView: RenderView,
        pipelineOwner: PipelineOwner,
        rootElement: RenderObjectToWidgetElement
    ) {
        self.renderView = renderView
        self.pipelineOwner = pipelineOwner
        self.rootElement = rootElement
    }
}

/// The main entry point for a Flutter Swift application.
///
/// On Linux, if `FLUTTER_DMABUF_SOCKET` is set, automatically bootstraps a
/// GPU DMA-BUF child process engine (zero-copy compositing with parent).
/// Otherwise, assumes an engine is already running (e.g. via DRM shell or GLFW).
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/binding.dart:1574`
///
/// The GPU renderer instance is stored in `gpuDmaBufRendererState` so widgets
/// can register external textures (e.g. for video playback).
#if os(Linux)
public nonisolated(unsafe) var gpuDmaBufRendererState: GpuRendererState? = nil
#endif

#if os(Linux)
/// Give a Starling child app the system clipboard.
///
/// The shell passes its Wayland socket name as STARLING_WAYLAND_DISPLAY — a
/// name of our own rather than WAYLAND_DISPLAY, which would tell every toolkit
/// linked into the app to switch to a Wayland backend and stop rendering
/// through the dma-buf socket.
///
/// Absent or unreachable, `Clipboard` stays process-local rather than failing:
/// an app run outside the shell still copies and pastes within itself.
private func _installStarlingClipboard() {
    let env = ProcessInfo.processInfo.environment
    guard let display = env["STARLING_WAYLAND_DISPLAY"], !display.isEmpty else { return }
    if let provider = WaylandClipboardProvider(display: display) {
        Clipboard.provider = provider
    }
}
#endif

public func runApp(_ app: Widget) {
    #if os(Linux)
    if let socketPath = ProcessInfo.processInfo.environment["FLUTTER_DMABUF_SOCKET"],
       !socketPath.isEmpty {
        // Default initial size — the parent will resize via the socket.
        let defaultW = Int(ProcessInfo.processInfo.environment["FLUTTER_WINDOW_WIDTH"].flatMap { Double($0) } ?? 800)
        let defaultH = Int(ProcessInfo.processInfo.environment["FLUTTER_WINDOW_HEIGHT"].flatMap { Double($0) } ?? 600)
        guard let gpu = GpuDmaBufRenderer(width: defaultW, height: defaultH, socketPath: socketPath) else {
            fatalError("[runApp] GpuDmaBufRenderer init failed")
        }
        gpuDmaBufRendererState = gpu.state
        GpuDmaBufRenderer.current = gpu
        _installStarlingClipboard()
        _setupWidgetBinding(app)
        gpu.run()  // initializes engine + enters event loop (never returns)
        return
    }
    #endif
    _setupWidgetBinding(app)
}

/// Internal: sets up PlatformDispatcher callbacks, RenderView, PipelineOwner,
/// BuildOwner, and the widget tree.
func _setupWidgetBinding(_ app: Widget) {
    // Initialize GestureBinding so gesture recognizers can access
    // pointerRouter and gestureArena via GestureBinding.instance.
    // Its onPointerDataPacket is overridden below by our custom handler.
    let gestureBinding = GestureBinding()

    let pd = PlatformDispatcher.instance

    // Key data is dispatched directly via dispatch_key_data callback
    // (bypasses channelBuffers). Allow overflow on legacy key event channel.
    MainActor.assumeIsolated {
        channelBuffers.allowOverflow("flutter/keydata", true)
        channelBuffers.allowOverflow("flutter/keyevent", true)
    }

    var renderView: RenderView?
    var rootElement: RenderObjectToWidgetElement?
    var pipelineOwner: PipelineOwner?
    // Pipelines for non-implicit views (multi-monitor), keyed by view id.
    var secondaryPipelines: [Int: SecondaryViewPipeline] = [:]
    let buildOwner = BuildOwner()
    // Expose the build owner so GlobalKey.currentState (which reads
    // WidgetsBinding.instance.buildOwner._globalKeyRegistry) resolves —
    // Navigator/Overlay lookups depend on it.
    WidgetsBinding.instance.buildOwner = buildOwner

    // Route key events to the focused widget (text fields etc.). Hosts that
    // install their own onKeyData (e.g. the desktop shell forwarding keys to
    // native windows) should fall back to FocusManager for unclaimed events.
    pd.onKeyData = { keyData in
        return FocusManager.instance.dispatchKeyData(keyData)
    }

    // Pointer event state — caches hit test results for active pointers.
    var hitTests: [Int: HitTestResult] = [:]

    // The mouse tracker, which is what makes MouseRegion's enter/exit fire.
    // Dart routes every pointer event through RendererBinding._dispatchEvent,
    // which feeds its tracker before dispatching; this adapter dispatches
    // directly and never did — so every MouseRegion in every app was
    // silently inert. Created here with the same per-view hit test the
    // dispatch below uses.
    let mouseTracker = MouseTracker({ position, viewId in
        let result = HitTestResult()
        if let implicitId = PlatformDispatcher.instance.implicitView?.viewId,
           viewId == implicitId {
            _ = renderView?.hitTest(result, position: position)
        } else if let sp = secondaryPipelines[viewId] {
            _ = sp.renderView.hitTest(result, position: position)
        }
        return result
    })

    // Track whether a fallback frame is already scheduled on the RunLoop.
    var _fallbackFrameScheduled = false

    // Guard against reentrancy: the engine may deliver a vsync callback
    // while the fallback RunLoop.perform frame is running (or vice versa).
    var _frameRunning = false

    // Track whether we've ever successfully composited a frame.
    // The first frame must always composite regardless of dirty flags.
    var _hasCompositedFirstFrame = false

    buildOwner.onBuildScheduled = {
        pd.scheduleFrame()

        #if os(Windows)
        // Schedule a fallback frame on the RunLoop, so that dirty
        // elements from programmatic setState (e.g. animation ticks from
        // Timer callbacks) get processed even if the engine doesn't deliver
        // a vsync frame promptly.
        //
        // Windows only, and the two exclusions are for opposite reasons.
        //
        // On Linux DRM mode, RunLoop.main never spins (the main thread runs
        // the C++ epoll loop), so this fallback is useless and could cause
        // race conditions if it somehow fires during initialization.
        //
        // On macOS it is worse than useless: it is destructive. [NSApp run]
        // spins RunLoop.main, so the fallback DOES fire — ahead of the vsync
        // frame the scheduleFrame() above just requested. It drains the whole
        // pipeline out of band (buildScope, flushLayout, flushPaint), and its
        // own compositeFrame() is submitted outside the engine's frame
        // callback, where the scene does not reach the screen. The real vsync
        // frame then arrives to find _dirtyElements, _nodesNeedingLayout and
        // _nodesNeedingPaint all empty, so `shouldComposite` is false and it
        // skips the composite that WOULD have been honoured. Net effect: the
        // window keeps compositing its first frame forever while build() runs
        // on every setState — a terminal whose emulator had the shell prompt
        // and a cursor at column 37 painted an empty grid with the cursor at
        // column 0. The engine delivers vsync reliably through the Cocoa
        // embedder, so there is nothing here to fall back FROM.
        // THE HOOK, NOT THE PIPELINE, when the host provides one. Asking
        // the embedder for a real frame (ForceRedraw -> the engine's own
        // begin-frame pass) is strictly better than the out-of-band drain
        // below: the drain composites outside the engine's frame callback,
        // and whether such a composite reaches the screen depends on the
        // context it runs from -- from a RunLoop pump it does, from the
        // host's WM_TIMER drain it silently does not, which surfaced as a
        // menu that never showed its rows. It also cannot race the real
        // frame into skipping (the macOS pathology in the comment above),
        // because it IS the real frame.
        if let kick = hostScheduleEngineFrame {
            kick()
        } else if !_fallbackFrameScheduled {
            // No hook installed: the RunLoop fallback. Late -- RunLoop.main
            // is pumped by input on this host, and by nearly nothing when
            // the pointer is still -- but visibly composites, which the
            // GCD main queue variant of this block did not.
            _fallbackFrameScheduled = true
            RunLoop.main.perform(_sendablePerform {
                _fallbackFrameScheduled = false
                guard rootElement != nil, let rv = renderView else { return }
                // Skip if another frame is already running (reentrancy guard)
                guard !_frameRunning else { return }
                _frameRunning = true
                defer { _frameRunning = false }
                buildOwner.buildScopeWithCallback(rootElement!) {}
                pipelineOwner!.flushLayout()
                if pipelineOwner!._nodesNeedingPaint.isEmpty {
                    rv.markNeedsPaint()
                }
                pipelineOwner!.flushPaint()
                rv.compositeFrame()
                // Same end-of-frame unmount as the onBeginFrame path; without
                // it this fallback leaks a paragraph per remount too.
                buildOwner.finalizeTree()
            })
        }
        #endif
    }

    pd.onBeginFrame = { duration in
        guard let view = pd.implicitView else { return }

        if renderView == nil {
            // One-time setup: create RenderView and widget pipeline
            renderView = RenderView(view: view)
            renderView!.configuration = RenderViewConfiguration.fromView(view)
            pipelineOwner = PipelineOwner()
            pipelineOwner!.onNeedVisualUpdate = {
                pd.scheduleFrame()
                #if os(Windows)
                // Same story as onBuildScheduled above: this embedder does
                // not deliver a vsync frame for ScheduleFrame in Swift
                // mode, so a RENDER-side invalidation — a scroll offset
                // moving, a markNeedsLayout outside any build — must kick
                // the host's real frame too, or the dirty layout sits
                // until some other frame happens by. Scrolling a ListView
                // was exactly this: the scroll position moved and notified,
                // the viewport marked itself for layout, and nothing on
                // screen ever moved.
                hostScheduleEngineFrame?()
                #endif
            }
            renderView!.attach(pipelineOwner!)
            renderView!.prepareInitialFrame()

            let adapter = RenderObjectToWidgetAdapter(child: app, container: renderView!)
            rootElement = adapter.attachToRenderTree(buildOwner)

            #if os(Linux)
            // Murmuration P3: the agent semantics endpoint walks the element
            // tree on demand ($STARLING_AGENT_ENDPOINT, set by the shell's
            // agent launch path; no-op otherwise).
            AgentSemanticsEndpoint.rootElementProvider = { rootElement }
            AgentSemanticsEndpoint.startIfConfigured()
            #endif
        }

        // Multi-monitor: dispose pipelines whose view was removed (monitor
        // unplugged). Unmounting via the nil-child adapter runs the tree's
        // dispose hooks (the host unregisters its invalidator).
        if !secondaryPipelines.isEmpty {
            let removedIds = secondaryPipelines.keys.filter { pd.view(id: $0) == nil }
            for id in removedIds {
                if let sp = secondaryPipelines.removeValue(forKey: id) {
                    _ = RenderObjectToWidgetAdapter(child: nil, container: sp.renderView)
                        .attachToRenderTree(buildOwner, sp.rootElement)
                    // try? — see the config-change write below: a failed
                    // diagnostic write must not be fatal.
                    try? FileHandle.standardError.write(contentsOf: Data(
                        "[Adapter] view \(id) pipeline disposed\n".utf8))
                }
            }
        }

        // Multi-monitor: build a pipeline + widget tree for any view the
        // engine has added since the last frame (each on its own
        // PipelineOwner; the BuildOwner and its dirty list are shared).
        if let builder = multiViewContentBuilder {
            for flutterView in pd.views {
                let id = flutterView.viewId
                if id == view.viewId || secondaryPipelines[id] != nil {
                    continue
                }
                let rv = RenderView(view: flutterView)
                rv.configuration = RenderViewConfiguration.fromView(flutterView)
                let po = PipelineOwner()
                po.onNeedVisualUpdate = {
                    pd.scheduleFrame()
                    #if os(Windows)
                    // See the implicit view's onNeedVisualUpdate above.
                    hostScheduleEngineFrame?()
                    #endif
                }
                rv.attach(po)
                rv.prepareInitialFrame()
                let adapter = RenderObjectToWidgetAdapter(
                    child: builder(flutterView), container: rv)
                let root = adapter.attachToRenderTree(buildOwner)
                secondaryPipelines[id] = SecondaryViewPipeline(
                    renderView: rv, pipelineOwner: po, rootElement: root)
                // try? — see the config-change write below: a failed
                // diagnostic write must not be fatal.
                try? FileHandle.standardError.write(contentsOf: Data(
                    "[Adapter] view \(id) pipeline created (\(flutterView.physicalSize.width)x\(flutterView.physicalSize.height))\n".utf8))
            }
        }

        // Update configuration each frame (view metrics may have changed)
        //
        // `try?`, and everywhere a diagnostic line is written from a running
        // frame: FileHandle's non-throwing write(_:) calls fatalError when the
        // write FAILS, and a GUI-subsystem Windows app launched from Explorer
        // starts with no stderr handle at all. This exact line was the first
        // stderr write of the process's life, so clicking maximize — the first
        // metrics change — trapped the whole app in the Swift runtime
        // (c000001d in swiftCore, inside the window procedure). A log line
        // with nowhere to go must be dropped, never fatal.
        let newConfig = RenderViewConfiguration.fromView(view)
        if renderView!.configuration != newConfig {
            try? FileHandle.standardError.write(
                contentsOf: Data("[Adapter] config change: \(renderView!.configuration) -> \(newConfig)\n".utf8))
            renderView!.configuration = newConfig
            // Metrics changed: re-run every build() so size-derived state
            // (a terminal's row count) follows the new metrics — see the
            // comment on onMetricsChanged for why the reassemble happens
            // here, on the UI task runner, and not there.
            rootElement?.reassemble()
        }

        // Skip rendering if the view has zero size (metrics not yet received)
        if renderView!.configuration.logicalConstraints.biggest == Size.zero {
            return
        }

        // Guard against reentrancy (macOS RunLoop.perform fallback).
        guard !_frameRunning else { return }
        _frameRunning = true
        defer { _frameRunning = false }

        // Advance all active Tickers (AnimationControllers).
        // This fires animation callbacks which may call setState, marking
        // elements dirty. Must happen BEFORE buildScope processes them.
        TickerScheduler.shared.tick()

        // Drive any registered frame callbacks (e.g. external texture renderers).
        // In DRM mode, Foundation.Timer doesn't fire, so renderers register here
        // to be driven from vsync instead.
        FrameCallbackScheduler.shared.tick()

        // Check if any work needs to be done before running the pipeline.
        // This avoids submitting redundant layer trees to the engine when
        // nothing has changed (e.g. extra frames scheduled by markNeedsPaint
        // during flushLayout, or external texture frame signals).
        let hasDirtyElements = !buildOwner.buildScope._dirtyElements.isEmpty
        let hasDirtyLayout = !pipelineOwner!._nodesNeedingLayout.isEmpty
        let hasDirtyPaint = !pipelineOwner!._nodesNeedingPaint.isEmpty
        let hasActiveTickers = TickerScheduler.shared.hasActiveTickers
        // Check if any external texture content was updated (DMA-BUF commit,
        // SHM upload, GL renderer, etc.).  Read and reset the flag so we only
        // composite when there's actually new content to rasterize.
        let hasNewTextureContent = FrameCallbackScheduler.shared.textureDidUpdate
        FrameCallbackScheduler.shared.textureDidUpdate = false
        // The ids behind that flag, for the secondary views below: each one
        // re-composites iff its OWN last scene contains an updated texture.
        // Without this, an app on a secondary output that repaints with no
        // widget change — a terminal echoing keystrokes — never re-presents.
        let updatedTextures = FrameCallbackScheduler.shared.takeUpdatedTextures()

        let ftStart = frameLogNow()

        // Flush dirty elements before layout
        buildOwner.buildScopeWithCallback(rootElement!) {}

        let ftBuild = frameLogNow()

        // Frame pipeline (mirrors RendererBinding.drawFrame)
        pipelineOwner!.flushLayout()
        let ftLayout = frameLogNow()
        pipelineOwner!.flushPaint()
        let ftPaint = frameLogNow()

        // Only composite if something actually changed. Skipping composite
        // when nothing is dirty avoids unnecessary scene builds, engine
        // renders, and page flips (in DRM mode), which would otherwise
        // cause continuous ~60fps CPU usage even when the UI is static.
        // A forced composite (screenshot capture) must reach EVERY view —
        // the DRM screenshot reads each output's next presented frame.
        let forceComposite = _forceNextComposite
        _forceNextComposite = false
        let shouldComposite = !_hasCompositedFirstFrame || hasDirtyElements || hasDirtyLayout || hasDirtyPaint || hasActiveTickers || hasNewTextureContent || forceComposite
        if shouldComposite {
            _hasCompositedFirstFrame = true
            renderView!.compositeFrame()
        }

        // Multi-monitor: run the frame pipeline for each secondary view.
        // Composite only when that view's own pipeline has work (or its
        // first frame, a forced capture, or new content in an external
        // texture its scene shows) so a static output doesn't re-present
        // on every primary animation frame.
        for sp in secondaryPipelines.values {
            let fv = sp.renderView.flutterView
            let newViewConfig = RenderViewConfiguration.fromView(fv)
            if sp.renderView.configuration != newViewConfig {
                sp.renderView.configuration = newViewConfig
            }
            if sp.renderView.configuration.logicalConstraints.biggest == Size.zero {
                continue
            }
            let viewDirty = !sp.hasComposited
                || !sp.pipelineOwner._nodesNeedingLayout.isEmpty
                || !sp.pipelineOwner._nodesNeedingPaint.isEmpty
                || forceComposite
                || !updatedTextures.isDisjoint(with: sp.renderView.sceneTextureIds)
            sp.pipelineOwner.flushLayout()
            sp.pipelineOwner.flushPaint()
            if viewDirty {
                let first = !sp.hasComposited
                sp.hasComposited = true
                sp.renderView.compositeFrame()
                if first {
                    // One line per view's life — the composite-side twin of
                    // "pipeline created" above. A view that was created and
                    // never composited, or composited into a surface that
                    // shows nothing, are different failures; this line is
                    // what tells them apart.
                    try? FileHandle.standardError.write(contentsOf: Data(
                        "[Adapter] view \(fv.viewId) first composite\n".utf8))
                    multiViewFirstComposite?(fv.viewId)
                }
                multiViewComposited?(fv.viewId)
            }
        }

        // End of frame: unmount everything deactivated during this build.
        //
        // This is the last line of WidgetsBinding.drawFrame upstream, and it
        // was missing here — `finalizeTree()` had no caller anywhere in the
        // SDK. Deactivated elements were added to `_inactiveElements` and
        // never removed, so `unmount()` never ran, and with it neither did
        // `RenderObjectElement.unmount`'s `renderObject.dispose()`. Every
        // deactivated element and its whole subtree was retained for the life
        // of the process. Measured before/after on a terminal repaint storm:
        // deactivated 50 / unmounted 0 becomes deactivated 50 / unmounted 49.
        //
        // NOT the cause of the terminal's ~20 MB-per-styled-dump growth — that
        // was measured separately and is unchanged by this. The leaked objects
        // there are RenderParagraph/TextPainter instances that are disposed and
        // unmounted correctly and still never deallocate, i.e. something else
        // holds a strong reference. See
        // docs/perf/terminal-vs-ghostty-2026-08-04/.
        //
        // AFTER compositing, not before: an element deactivated during build
        // may still own a render object that layout and paint walk this frame.
        let ftComposite = frameLogNow()
        buildOwner.finalizeTree()

        // Only frames that composited: the skipped ones are the cheap
        // steady state and would drown the signal.
        if frameLogEnabled && shouldComposite {
            let ftEnd = DispatchTime.now().uptimeNanoseconds
            func us(_ a: UInt64, _ b: UInt64) -> UInt64 { (b - a) / 1_000 }
            frameLogWrite("[frame] build=\(us(ftStart, ftBuild))us"
                + " layout=\(us(ftBuild, ftLayout))us"
                + " paint=\(us(ftLayout, ftPaint))us"
                + " composite=\(us(ftPaint, ftComposite))us"
                + " finalize=\(us(ftComposite, ftEnd))us"
                + " total=\(us(ftStart, ftEnd))us")
        }
    }
    pd.onDrawFrame = { }

    // When view metrics change, rebuild and then re-layout/repaint.
    //
    // Re-layout alone is not enough. Upstream Flutter funnels metrics through
    // MediaQuery, so a resize rebuilds everything that depends on the size;
    // this port has no such dependency tracking, so any widget that reads the
    // view metrics inside build() — a terminal deriving its row count, say —
    // keeps whatever it computed at its last build and lays out for the old
    // size. That surfaces as a RenderFlex overflow the moment a window is
    // tiled or resized smaller.
    // Marking the ROOT alone cannot do that, though. markNeedsBuild dirties
    // one element; when the root rebuilds, updateChild compares against the
    // adapter's stored child widget, finds the identical instance, and
    // returns without touching it (`child.widget === newWidget` in
    // ElementCore.updateChild) — so no descendant's build() ever re-runs and
    // the old flow only ever re-laid-out stale trees. The symptom that
    // exposed it: shrink the Terminal and the tree lays out at the new size
    // (the RenderFlex overflow bar lands on the new bottom edge) while the
    // app's build()-derived row count — and with it the pty size — stays at
    // the old window's.
    //
    // reassemble() is the tree-wide markNeedsBuild (Dart's hot-reload path:
    // dirty every element, then rebuild in depth order). Upstream would be
    // selective — metrics arrive through MediaQuery and only registered
    // dependents rebuild — but without InheritedWidget dependency tracking
    // there is nothing to be selective WITH, and a metrics change already
    // re-lays-out every render object, so a full rebuild is the same order
    // of work, at the rate windows resize, not per frame.
    //
    // The reassemble itself must NOT happen here. onMetricsChanged fires on
    // whatever thread delivered the resize — for a dma-buf child that is the
    // socket poll loop — while builds run on the engine's UI task runner.
    // reassemble() walks the element tree and appends every element to the
    // dirty list, so running it here mutated both under the UI thread's
    // feet: heap corruption, surfacing as malloc/memcpy segfaults in
    // whichever thread tripped first (the Settings app died on every tiling
    // toggle this way). onBeginFrame runs on the UI task runner and already
    // diffs the view configuration each frame, so the reassemble lives in
    // that branch — same trigger, single thread.
    pd.onMetricsChanged = {
        pd.scheduleFrame()
    }

    // --- Pointer event handling ---
    // Mirrors GestureBinding: converts PointerData to PointerEvents,
    // performs hit testing against the RenderView, and dispatches to targets.
    pd.onPointerDataPacket = { packet in
        guard let rv = renderView else { return }

        let events = PointerEventConverter.expand(
            packet.data,
            devicePixelRatioForView: { viewId in
                pd.view(id: viewId)?.devicePixelRatio
            }
        )

        for event in events {
            // Route to the render view the event targets (multi-monitor:
            // each output's view has its own tree). Unknown view → drop.
            let targetView: RenderView?
            if let implicitId = pd.implicitView?.viewId, event.viewId == implicitId {
                targetView = rv
            } else {
                targetView = secondaryPipelines[event.viewId]?.renderView
            }
            guard let eventView = targetView else { continue }

            var hitTestResult: HitTestResult? = nil

            if event is PointerDownEvent
                || event is PointerSignalEvent
                || event is PointerHoverEvent
                || event is PointerPanZoomStartEvent
            {
                hitTestResult = HitTestResult()
                _ = eventView.hitTest(hitTestResult!, position: event.position)
                if event is PointerDownEvent {
                    hitTests[event.pointer] = hitTestResult
                }
                if event is PointerPanZoomStartEvent {
                    hitTests[event.pointer] = hitTestResult
                }
            } else if event is PointerUpEvent
                        || event is PointerCancelEvent
                        || event is PointerPanZoomEndEvent
            {
                hitTestResult = hitTests.removeValue(forKey: event.pointer)
            } else if event.down || event is PointerPanZoomUpdateEvent {
                hitTestResult = hitTests[event.pointer]
            }

            // The tracker sees EVERY event, as RendererBinding's dispatch
            // gives it in Dart — it derives enter/exit for MouseRegions by
            // diffing the annotations under the device. Moves pass nil so
            // the tracker re-runs the hit test itself: the cached down-time
            // result deliberately does not follow the hover.
            mouseTracker.updateWithEvent(
                event,
                hitTestResult: event is PointerMoveEvent ? nil : hitTestResult)

            if let result = hitTestResult {
                for entry in result.path {
                    let transformedEvent = event.transformed(entry.transform)
                    entry.target.handleEvent(
                        transformedEvent,
                        entry: entry
                    )
                }
                // Route to gesture recognizers and manage the gesture arena.
                // Without this, recognizers registered via GestureDetector
                // never receive move/up events and gestures never resolve.
                gestureBinding.pointerRouter.route(event)
                if event is PointerDownEvent || event is PointerPanZoomStartEvent {
                    gestureBinding.gestureArena.close(event.pointer)
                } else if event is PointerUpEvent || event is PointerPanZoomEndEvent {
                    gestureBinding.gestureArena.sweep(event.pointer)
                }
            }
        }

        // Pointer events may trigger setState (which schedules via
        // onBuildScheduled), but also need a frame for hover/press visual
        // feedback even when no setState occurs.
        pd.scheduleFrame()
    }
}

