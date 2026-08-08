// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(macOS)
import AppKit
import FlutterMacOSBridge
#elseif os(Linux)
import FlutterEmbedderBridge
import FlutterDRMBridge
import WaylandServerBridge
import PortalService
import Foundation
import Glibc
#endif

import Flutter
import FlutterSwiftBridge
import SwiftRuntime
import StarlingRegistry

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - macOS Entry Point
// ═══════════════════════════════════════════════════════════════════════════════

#if os(macOS)

// MARK: - Global Compositor

/// Global reference to the external app manager, set after engine starts.
nonisolated(unsafe) var externalAppManager: ExternalAppManager? = nil

/// Global reference to the process app manager, set after engine starts.
nonisolated(unsafe) var processAppManager: ProcessAppManager? = nil

// MARK: - Entry Point

let app = NSApplication.shared
app.setActivationPolicy(.regular)

// Create FlutterEngine (headless — we start it manually in Swift mode).
let engine = FlutterEngine(name: "swift-app", project: nil, allowHeadlessExecution: true)

// Build the widget tree: MacosApp wrapping our DesktopShell.
// MacosApp provides Directionality and Overlay (via Navigator) automatically.
runApp(
    MacosApp(
        themeMode: .dark,
        home: DesktopShell(),
        title: "Desktop Shell PoC"
    )
)

// Create the C callback table backed by SwiftRuntimeDelegate.
var callbacks = createRuntimeCallbacks()

// Start engine in Swift mode BEFORE creating the view controller.
let started = withUnsafePointer(to: &callbacks) { ptr in
   engine.runSwift(withRuntimeCallbacks: UnsafeRawPointer(ptr))
}
guard started else {
    fatalError("[DesktopShellApp] Failed to start engine in Swift mode")
}

// Initialize the external app manager now that the engine is running.
externalAppManager = ExternalAppManager(engine: engine)

// Initialize the process app manager for cross-process IOSurface compositing.
processAppManager = ProcessAppManager(engine: engine)

// Create FlutterViewController with the already-running engine.
let viewController = FlutterViewController(engine: engine, nibName: nil, bundle: nil)

// Create window.
let window = NSWindow(
    contentRect: NSMakeRect(0, 0, 1440, 900),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
)
window.title = "Desktop Shell PoC"
window.contentViewController = viewController
window.setContentSize(NSMakeSize(1440, 900))
window.center()
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

// Schedule first frame.
PlatformDispatcher.instance.scheduleFrame()

// Enter event loop.
app.run()

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Linux Entry Point
// ═══════════════════════════════════════════════════════════════════════════════
//
// Creates an X11 window via GLFW3, renders with OpenGL ES 2 via EGL, and
// forwards mouse/keyboard input to the Flutter engine. Falls back to the
// headless software renderer when --headless is passed.

#elseif os(Linux)

// ─── AppState ────────────────────────────────────────────────────────────────

/// Holds all mutable state shared between GLFW callbacks and the embedder.
/// Passed as `Unmanaged<AppState>.toOpaque()` through the embedder's
/// `user_data` and GLFW's `glfwSetWindowUserPointer`.
///
/// Must NOT be @MainActor — engine callbacks come from io/raster threads.
/// @unchecked Sendable because we manually synchronize access (main thread
/// for GLFW callbacks, NSLock for taskQueue).
// A compositor legitimately holds many fds — one dup per live client
// buffer, EGLImage-internal dups, the recorder's ring, input devices — and
// the distro's 1024 soft limit is sized for none of that. Hitting it is
// catastrophic in a specific way: libwayland's accept handler fails with
// EMFILE, logs "failed to accept" in a hot loop, and no new client can
// ever connect. Raise the soft limit to the hard limit (524288 here)
// before anything opens.
do {
    // Glibc imports RLIMIT_NOFILE as the __rlimit_resource enum while
    // get/setrlimit take the raw Int32 — bridge explicitly.
    let nofile = __rlimit_resource_t(RLIMIT_NOFILE.rawValue)
    var lim = rlimit()
    if getrlimit(nofile, &lim) == 0 && lim.rlim_cur < lim.rlim_max {
        lim.rlim_cur = lim.rlim_max
        if setrlimit(nofile, &lim) != 0 {
            FileHandle.standardError.write(
                "[main] setrlimit(RLIMIT_NOFILE) failed — long sessions may exhaust fds\n".data(using: .utf8)!)
        }
    }
}

// Whether a first-party app counts as installed depends on where its binary
// can be found, and only the shell knows all the layouts (staged, packaged,
// sibling dev build). Hand that to the registry before anything reads it —
// the launcher and dock ask it on their very first build.
AppRegistry.shared.firstPartyResolver = { LinuxProcessAppManager.resolveAppExecutable($0) }

/// Global reference to the Linux external app manager, set after engine starts.
nonisolated(unsafe) var linuxExternalAppManager: LinuxExternalAppManager? = nil

/// Global reference to the Linux process app manager (cross-process compositing).
nonisolated(unsafe) var linuxProcessAppManager: LinuxProcessAppManager? = nil

nonisolated(unsafe) var waylandIntegration: WaylandIntegration? = nil
nonisolated(unsafe) var x11Integration: X11Integration? = nil
nonisolated(unsafe) var portalIntegration: PortalIntegration? = nil
nonisolated(unsafe) var notificationIntegration: NotificationIntegration? = nil
/// Screen recording. A global (not a shell-state property) because the
/// engine's frame callback lands on the recorder writer thread, where
/// touching shell state is off-limits — the service is the thread-safe
/// mailbox between the two worlds.
nonisolated(unsafe) var recordingService: RecordingService? = nil
/// Portal ScreenCast (screen share into Chromium/OBS/gstreamer) — a global
/// for the same reason as recordingService: hooks land on the portal and
/// recorder writer threads.
nonisolated(unsafe) var screenCastService: ScreenCastService? = nil

/// Current shell DPI — updated at runtime by Settings app. Read this instead
/// of the FLUTTER_DRM_DPI env var for coordinate conversion.
///
/// This is only the value to use before there is a display to ask. On DRM the
/// engine derives the real scale from the panel while creating the view, and
/// the code below adopts it (`fl_drm_view_get_scale`) before anything reads
/// this. It used to default to 2.0 for 4K panels, which was right on every
/// machine it had been run on and wrong everywhere else: a 1280x800 display
/// then rendered a 640x400 desktop, too short for windows the registry sizes
/// in logical pixels.
nonisolated(unsafe) var currentShellDpi: Double =
    Double(ProcessInfo.processInfo.environment["FLUTTER_DRM_DPI"] ?? "") ?? 1.0

/// The display layout (virtual desktop of one or more outputs). Built at DRM
/// startup; nil on the macOS/GLFW dev paths (screen size falls back there).
nonisolated(unsafe) var displayLayout: DisplayLayout? = nil


final class AppState: @unchecked Sendable {
    nonisolated(unsafe) var window: OpaquePointer? = nil
    nonisolated(unsafe) var resourceWindow: OpaquePointer? = nil
    nonisolated(unsafe) var engine: OpaquePointer? = nil

    nonisolated(unsafe) var pixelsPerScreenCoord: Double = 1.0

    // Pointer state machine (mirrors flutter_glfw.cc)
    nonisolated(unsafe) var pointerAdded = false
    nonisolated(unsafe) var pointerDown = false
    nonisolated(unsafe) var buttons: Int64 = 0

    /// Set to true after the first frame has been processed (layout complete).
    /// Pointer events are suppressed until this is true to avoid hit-testing
    /// render objects that haven't been laid out yet.
    nonisolated(unsafe) var firstFrameProcessed = false

    /// Texture registry for external texture compositing (set after engine init).
    nonisolated(unsafe) var textureRegistry: LinuxTextureRegistry? = nil

    nonisolated let taskQueue = FlutterTaskQueue()
    nonisolated let mainThreadPthread = pthread_self()
}

// ─── FlutterTaskQueue ────────────────────────────────────────────────────────

/// Thread-safe priority queue of engine tasks. The engine posts tasks from
/// arbitrary threads; we drain them on the main GLFW thread.
class FlutterTaskQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [(task: FlutterTask, targetNanos: UInt64)] = []

    func enqueue(_ task: FlutterTask, targetNanos: UInt64) {
        lock.lock()
        tasks.append((task, targetNanos))
        lock.unlock()
    }

    /// Returns (expired tasks, next-deadline-nanos-or-nil).
    func drainExpired() -> (expired: [(FlutterTask, UInt64)], nextNanos: UInt64?) {
        let now = FlutterEngineGetCurrentTime()
        lock.lock()
        var expired: [(FlutterTask, UInt64)] = []
        var remaining: [(task: FlutterTask, targetNanos: UInt64)] = []
        for entry in tasks {
            if entry.targetNanos <= now {
                expired.append((entry.task, entry.targetNanos))
            } else {
                remaining.append(entry)
            }
        }
        tasks = remaining
        let nextNanos = remaining.map(\.targetNanos).min()
        lock.unlock()
        return (expired, nextNanos)
    }
}

// ─── Pointer helpers ─────────────────────────────────────────────────────────

/// Sends a pointer event to the Flutter engine, handling the add/remove
/// synthesis protocol that the engine requires.
func sendPointerEvent(
    _ state: AppState,
    phase: FlutterPointerPhase,
    x: Double,
    y: Double,
    signalKind: FlutterPointerSignalKind = kFlutterPointerSignalKindNone,
    scrollDeltaX: Double = 0,
    scrollDeltaY: Double = 0,
    buttons: Int64 = 0
) {
    guard let engine = state.engine else { return }
    // Suppress pointer events until the first frame is laid out, otherwise
    // hit testing crashes on render boxes that have never been laid out.
    guard state.firstFrameProcessed else { return }

    // Synthesise kAdd if the pointer hasn't been added yet
    if !state.pointerAdded && phase != kAdd {
        sendPointerEvent(state, phase: kAdd, x: x, y: y)
    }
    // Don't double-add
    if state.pointerAdded && phase == kAdd { return }

    var event = FlutterPointerEvent()
    event.struct_size = MemoryLayout<FlutterPointerEvent>.size
    event.phase = phase
    event.timestamp = Int(FlutterEngineGetCurrentTime() / 1000)  // ns → µs
    event.x = x * state.pixelsPerScreenCoord
    event.y = y * state.pixelsPerScreenCoord
    event.device = 0
    event.signal_kind = signalKind
    event.scroll_delta_x = scrollDeltaX
    event.scroll_delta_y = scrollDeltaY
    event.device_kind = kFlutterPointerDeviceKindMouse
    event.buttons = buttons
    event.view_id = 0

    FlutterEngineSendPointerEvent(engine, &event, 1)

    // Update state machine
    switch phase {
    case kAdd:    state.pointerAdded = true
    case kRemove: state.pointerAdded = false
    case kDown:   state.pointerDown = true
    case kUp:     state.pointerDown = false
    default: break
    }
}

/// Determines the correct pointer phase based on current button state,
/// matching the flutter_glfw.cc state machine.
func pointerPhaseForButtonState(_ state: AppState) -> FlutterPointerPhase {
    if state.buttons == 0 {
        return state.pointerDown ? kUp : kHover
    } else {
        return state.pointerDown ? kMove : kDown
    }
}


// ─── DRM/KMS mode (--drm flag) ───────────────────────────────────────────────

/// Global reference to the DRM texture registry (used by the DRM texture callback).
nonisolated(unsafe) var drmTextureRegistry: LinuxTextureRegistry? = nil

/// The engine view handle — hotplug callbacks and the multi-view content
/// builder's fallback path query outputs through it.
nonisolated(unsafe) var drmViewHandle: OpaquePointer? = nil
/// The per-screen shell child feeding an externally sourced output
/// (STARLING_SCREEN_SHELL; Stage B of docs/plans/nv-view.md).
nonisolated(unsafe) var externalScreenShell: ExternalScreenShell? = nil
/// Output-level click-to-focus for the keyboard: a pointer down on the
/// external screen claims it (set in the external input callback), a pointer
/// down on any shell output takes it back (cleared in the trees' root
/// listeners). While set, routeKey forwards keys to the screen-shell child.
nonisolated(unsafe) var externalScreenKeyFocus = false
/// The output externally sourced this session (STARLING_SCREEN_SHELL, or
/// FLUTTER_DRM_EXTERNAL_TEST for the engine-side Stage A test producer);
/// nil when every output is engine-rendered. An external output gets no
/// Flutter view, which must NOT read as "simulated layout": DesktopShell
/// keeps the real-multi-output path (normal desktop on the host) instead of
/// the scale-to-fit overview harness — the overview has no root input
/// listeners, so landing in it by accident makes the host tree deaf.
let externallySourcedOutput: Int? = ProcessInfo.processInfo
    .environment["FLUTTER_DRM_EXTERNAL_TEST"].flatMap { Int($0) }
    ?? ProcessInfo.processInfo
    .environment["STARLING_SCREEN_SHELL"].flatMap { Int($0) }

/// The real-output virtual desktop, derived deterministically from the
/// engine's enumeration: the HOST output at (0,0) at the shell DPI, the others
/// to its right in enumeration order at 1x (per-output scale settings come
/// later). Startup, hotplug, and the content builder's fallback all use this,
/// so they always agree on the arrangement.
///
/// The host is the engine's own primary — the output its implicit view renders
/// to — and stays at the origin because the shell tree's coordinates are that
/// output's. Which output is the *user's* primary is a separate, persisted
/// choice that `DisplayLayout` applies on construction.
func computeRealLayoutFromEngine(_ view: OpaquePointer?) -> DisplayLayout? {
    guard let view else { return nil }
    let count = Int(fl_drm_view_get_output_count(view))
    guard count > 0 else { return nil }
    var outputs: [DisplayOutput] = []
    var nameBuf = [CChar](repeating: 0, count: 32)
    for i in 0..<count {
        var w: UInt32 = 0, h: UInt32 = 0, refresh: UInt32 = 0
        var isEnginePrimary: Int32 = 0
        guard fl_drm_view_get_output_info(
            view, UInt32(i), &w, &h, &refresh, &isEnginePrimary,
            &nameBuf, UInt32(nameBuf.count)) == 1 else { continue }
        let host = isEnginePrimary == 1
        let name = String(cString: nameBuf)
        // An output that was already in the layout keeps its scale — a
        // runtime host switch and a hotplug must not reset a 2x monitor to
        // 1x. A NEW output gets its honest panel scale: the host's is
        // currentShellDpi (already derived or overridden), the others ask
        // the engine, which has the EDID this side never sees. Per-output
        // scale *settings* come later; per-output scale *defaults* are here.
        let known = displayLayout?.outputs.first(where: { $0.name == name })?.scale
        outputs.append(DisplayOutput(
            id: i, name: name,
            physicalWidth: Int(w), physicalHeight: Int(h),
            scale: known ?? (host ? currentShellDpi
                                  : fl_drm_view_get_output_derived_scale(view, UInt32(i))),
            originX: 0, originY: 0, isHost: host, isPrimary: host,
            refreshMhz: Int(refresh)))
    }
    guard !outputs.isEmpty else { return nil }
    var cursorX = 0.0
    if let p = outputs.firstIndex(where: { $0.isHost }) {
        outputs[p].originX = 0
        cursorX = outputs[p].logicalWidth
    }
    for i in outputs.indices where !outputs[i].isHost {
        outputs[i].originX = cursorX
        cursorX += outputs[i].logicalWidth
    }
    return DisplayLayout(outputs: outputs)
}

/// Give every secondary output without a Flutter view one, and (re)install
/// the engine's pointer-space placements. Must run on a thread the engine
/// accepts AddView from: main during startup (before fl_drm_view_run), the
/// engine platform thread at hotplug.
func syncEngineViewsAndLayout(_ view: OpaquePointer?, _ dl: DisplayLayout) {
    guard let view else { return }
    let mapped = Set(secondaryViewOutputs.outputIds)
    // An externally sourced output (docs/plans/nv-view.md) must not get a
    // Flutter view — the engine would refuse the AddView anyway, this just
    // keeps the id allocation clean.
    for output in dl.outputs where !output.isHost && !mapped.contains(output.id) {
        if let ext = externallySourcedOutput, ext == output.id { continue }
        let viewId = secondaryViewOutputs.allocateViewId()
        // Mapped BEFORE AddView: the content builder reads it on the view's
        // first frame.
        secondaryViewOutputs[viewId] = output.id
        if fl_drm_view_add_output_view(
            view, UInt32(output.id), Int64(viewId), output.scale) != 1 {
            secondaryViewOutputs[viewId] = nil
        }
    }
    guard dl.outputs.count > 1 else { return }
    for output in dl.outputs {
        fl_drm_view_set_output_layout(
            view, UInt32(output.id), output.originX, output.originY, output.scale)
    }
}

/// Tell every child app which displays exist and which one is primary — the
/// Settings app's Displays pane is drawn from exactly this. Called whenever the
/// arrangement changes (startup, hotplug, a new primary), and by the process
/// manager for each child as it connects.
func publishDisplaysToChildren() {
    guard let dl = displayLayout else { return }
    linuxProcessAppManager?.broadcastDisplays(dl.outputs.map {
        LinuxProcessAppManager.ChildDisplay(
            id: $0.id, name: $0.name,
            physicalWidth: $0.physicalWidth, physicalHeight: $0.physicalHeight,
            scale: $0.scale, isPrimary: $0.isPrimary)
    })
}

/// The heap box a host-switch request travels in through the C trampoline
/// (fl_drm_view_post_task takes a bare function pointer + user_data).
private final class HostSwitchRequest {
    let outputId: Int
    init(_ outputId: Int) { self.outputId = outputId }
}

/// Ask for the full "primary display" switch: the shell's own view moves to
/// `outputId`. Called on the main thread; the engine work is marshalled to
/// the ENGINE PLATFORM thread, the only one AddView/RemoveView accept.
func requestHostOutputSwitch(to outputId: Int) {
    guard let view = drmViewHandle else { return }
    let raw = Unmanaged.passRetained(HostSwitchRequest(outputId)).toOpaque()
    if fl_drm_view_post_task(view, { raw in
        let req = Unmanaged<HostSwitchRequest>.fromOpaque(raw!).takeRetainedValue()
        performHostOutputSwitch(to: req.outputId)
    }, raw) == 0 {
        Unmanaged<HostSwitchRequest>.fromOpaque(raw).release()
        FileHandle.standardError.write(Data(
            "[DisplayLayout] host switch: post_task unavailable\n".utf8))
    }
}

/// ENGINE PLATFORM thread: rebind the implicit view to `outputId`, give the
/// old host an explicit view, re-derive the layout, and publish it to main.
/// On engine refusal (recording active, output vanished) the desktop keeps
/// the dock-only behavior it already switched to — a degradation, not a
/// broken state.
func performHostOutputSwitch(to outputId: Int) {
    guard let view = drmViewHandle, let dl = displayLayout,
          let target = dl.outputs.first(where: { $0.id == outputId }),
          !target.isHost
    else { return }
    let oldHost = dl.host
    let oldWindowLayout = dl.outputs

    // The engine removes the explicit view on the target; forget our mapping
    // first so the content builder answers black for any straggler frame.
    secondaryViewOutputs.removeMapping(forOutput: target.id)

    guard fl_drm_view_set_primary_output(
        view, UInt32(target.id), target.scale) == 1 else {
        FileHandle.standardError.write(Data(
            "[DisplayLayout] host switch to \(target.name) refused by engine; dock-only move stands\n".utf8))
        return
    }

    // The old host becomes an ordinary secondary: its own Flutter view at
    // the scale it was running at. Mapped BEFORE AddView, like startup.
    let newViewId = secondaryViewOutputs.allocateViewId()
    secondaryViewOutputs[newViewId] = oldHost.id
    if fl_drm_view_add_output_view(
        view, UInt32(oldHost.id), Int64(newViewId), oldHost.scale) != 1 {
        secondaryViewOutputs[newViewId] = nil
        FileHandle.standardError.write(Data(
            "[DisplayLayout] host switch: add_output_view failed for \(oldHost.name) — it will show its last frame\n".utf8))
    }

    // The shell view's scale is the new host's now. Set before the layout
    // recompute (its host-scale fallback reads it) and exported for spawned
    // children, exactly like the runtime DPI path.
    currentShellDpi = target.scale
    setenv("FLUTTER_DRM_DPI", "\(currentShellDpi)", 1)
    setenv("FLUTTER_SCREEN_WIDTH", "\(target.physicalWidth)", 1)
    setenv("FLUTTER_SCREEN_HEIGHT", "\(target.physicalHeight)", 1)

    guard let newLayout = computeRealLayoutFromEngine(view) else { return }
    syncEngineViewsAndLayout(view, newLayout)

    DispatchQueue.main.async {
        // Before the layout publish: each PANEL keeps the space it was
        // showing across the host identity change (the compat index means
        // "the host's space", and the host just became a different monitor).
        _shellState?.windowManager.hostChanged(from: oldHost.id, to: target.id)
        displayLayout = newLayout
        FileHandle.standardError.write(Data(
            "[DisplayLayout] host switch: \(newLayout.describe())\n".utf8))
        // Windows stay on their physical monitors. The switch renumbers the
        // virtual desktop (the host moves to the origin), so every window's
        // rect is translated by its owning output's origin delta — without
        // this, windows visually JUMP monitors while keeping their numbers.
        if let shell = _shellState {
            for win in shell.windowManager.windows {
                guard let oldOwner = oldWindowLayout.first(where: {
                    $0.containsLogical(win.rect.left + win.rect.width / 2,
                                       win.rect.top + win.rect.height / 2) })
                    ?? oldWindowLayout.first(where: { $0.isHost }),
                    let newOwner = newLayout.outputs.first(where: { $0.id == oldOwner.id })
                else { continue }
                win.rect = Rect.fromLTWH(
                    win.rect.left - oldOwner.originX + newOwner.originX,
                    win.rect.top - oldOwner.originY + newOwner.originY,
                    win.rect.width, win.rect.height)
            }
        }
        waylandIntegration?.setOutputs(newLayout.outputs)
        publishDisplaysToChildren()
        // Children re-render at the new host density (the DPI-slider path's
        // exact contract: Wayland scale factors deliberately untouched).
        linuxProcessAppManager?.broadcastDpiChange(currentShellDpi)
        _shellState?.setState {}
        invalidateSecondaryScreens()
    }
}

/// DRM connector hotplug — runs on the ENGINE PLATFORM thread (the thread
/// AddView requires). The engine has already built the new output's swap
/// chain and modeset it black; here the shell gives it a view + pointer
/// placement, then publishes the layout to the main thread (DisplayLayout,
/// wl_output advertisement, repaint).
func drmOutputsChanged() {
    guard let view = drmViewHandle,
          let dl = computeRealLayoutFromEngine(view) else { return }
    // Unplugged outputs (their get_output_info now fails) lose their view
    // mapping so a later reconnect gets a fresh view.
    secondaryViewOutputs.removeMappings(notIn: Set(dl.outputs.map { $0.id }))
    syncEngineViewsAndLayout(view, dl)
    DispatchQueue.main.async {
        displayLayout = dl
        FileHandle.standardError.write(Data(
            "[DisplayLayout] hotplug: \(dl.describe())\n".utf8))
        // Always re-advertise on hotplug — shrinking back to one output
        // must reach clients too.
        waylandIntegration?.setOutputs(dl.outputs)
        // A monitor arriving or leaving changes the Displays pane, and may
        // change which output is primary: the remembered one comes back as
        // primary when it is replugged, and hands the role to the host while
        // it is away (DisplayLayout applies that on construction).
        publishDisplaysToChildren()
        // Windows stranded on an unplugged output come home (macOS behavior),
        // keeping their size. "Stranded" is a matter of degree, not of bare
        // intersection: a window that straddled the boundary still overlaps the
        // surviving output, and testing only for zero intersection left it
        // exactly where it was, with most of its area off the desktop.
        //
        // Home is the output it most belongs to among the survivors, not always
        // the primary — a straddling window stays on the monitor it was mostly
        // on. owningOutput falls back to the primary when nothing overlaps,
        // which is the fully-stranded case.
        if let shell = _shellState {
            for win in shell.windowManager.visibleWindows
            where dl.visibleFraction(ofRect: win.rect) < DisplayLayout.minVisibleFractionToStay {
                let home = dl.owningOutput(ofRect: win.rect)
                let w = win.rect.width
                let h = win.rect.height
                let nx = min(max(win.rect.left, home.logicalLeft),
                             max(home.logicalLeft, home.logicalRight - w))
                let ny = min(max(win.rect.top, home.logicalTop),
                             max(home.logicalTop, home.logicalBottom - h))
                win.rect = Rect.fromLTWH(nx, ny, w, h)
            }
        }
        _shellState?.setState {}
    }
}

func runDRM() -> Never {
    // Content for non-implicit Flutter views — one per secondary output,
    // created below once the engine is up and the display layout is known.
    multiViewContentBuilder = { flutterView in
        guard let outputId = secondaryViewOutputs[flutterView.viewId] else {
            return ColoredBox(color: Color(0xFF000000))
        }
        // The published layout can lag a hotplug by a beat (it's posted to
        // the main queue); the engine-derived layout is identical by
        // construction, so fall back to it for the missing output.
        let output = displayLayout?.outputs.first(where: { $0.id == outputId })
            ?? computeRealLayoutFromEngine(drmViewHandle)?
                .outputs.first(where: { $0.id == outputId })
        guard let output else {
            return ColoredBox(color: Color(0xFF000000))
        }
        return SecondaryScreenHost(output: output)
    }

    // Build the widget tree and runtime callbacks.
    runApp(
        MacosApp(
            themeMode: .dark,
            home: DesktopShell(),
            title: "Desktop Shell"
        )
    )
    var callbacks = createRuntimeCallbacks()

    let engineOutDir = ProcessInfo.processInfo.environment["FLUTTER_ENGINE_OUT"] ?? "../engine/src/out/host_debug"
    let assetsPath = "\(engineOutDir)/flutter_assets"
    let icuPath = "\(engineOutDir)/icudtl.dat"

    // FLUTTER_DRM_DPI is deliberately NOT forced here. Setting it would be
    // the engine's own override, so the view could never derive a scale from
    // the panel — it would only ever read back the guess we just made. The
    // adoption happens after creation instead, below.

    // Create the DRM view — this initializes DRM display, GBM, EGL,
    // the Flutter engine, and input handling.
    guard let view = withUnsafeMutablePointer(to: &callbacks, { cbPtr in
        fl_drm_view_create(assetsPath, icuPath, UnsafeMutableRawPointer(cbPtr))
    }) else {
        fatalError("[DesktopShellApp] fl_drm_view_create failed")
    }

    let drmEngine = fl_drm_view_get_engine(view)!
    let screenW = fl_drm_view_get_width(view)
    let screenH = fl_drm_view_get_height(view)

    // Build the display layout (virtual desktop). STARLING_SIM_OUTPUTS
    // fabricates a hardware-free arrangement for development; otherwise the
    // engine's REAL output enumeration drives it: primary at (0,0), secondary
    // outputs to its right, each with its own Flutter view rendering a
    // SecondaryOutputScreen. At N=1 this reproduces the previous
    // single-screen behavior exactly.
    drmViewHandle = view

    // Adopt the scale the view resolved from the panel. Everything downstream
    // reads currentShellDpi — the display layout below, coordinate
    // conversion, the recorder's capture size — so this has to land before
    // any of them. Exported so spawned apps and shell-drive.py inherit the
    // real value instead of each keeping their own default.
    currentShellDpi = fl_drm_view_get_scale(view)
    setenv("FLUTTER_DRM_DPI", "\(currentShellDpi)", 1)
    FileHandle.standardError.write(Data(
        "[DisplayLayout] scale \(currentShellDpi) for \(screenW)x\(screenH)\n".utf8))

    let simSpec = ProcessInfo.processInfo.environment["STARLING_SIM_OUTPUTS"] ?? ""
    let realOutputCount = Int(fl_drm_view_get_output_count(view))

    // The persisted primary display, applied BEFORE any secondary views
    // exist: rebinding the implicit view now displaces nothing, so this is
    // the clean version of the runtime switch. Main is still the engine
    // platform thread here (fl_drm_view_run hasn't spawned the real one).
    // A pixel_ratio of 0 lets the engine derive the panel's own scale, and
    // currentShellDpi is re-adopted after — the first read was the engine
    // pick's panel, not this one.
    if simSpec.isEmpty && realOutputCount > 1,
       let wanted = DisplayLayout.preferredPrimaryName {
        var nameBuf = [CChar](repeating: 0, count: 32)
        for i in 0..<realOutputCount {
            var isEnginePrimary: Int32 = 0
            guard fl_drm_view_get_output_info(
                view, UInt32(i), nil, nil, nil, &isEnginePrimary,
                &nameBuf, UInt32(nameBuf.count)) == 1 else { continue }
            if String(cString: nameBuf) == wanted {
                // FLUTTER_DRM_DPI is the user's override and follows the
                // shell wherever it hosts; without it the engine derives the
                // new panel's own scale (0 = derive).
                let dpiEnv = ProcessInfo.processInfo.environment["FLUTTER_DRM_DPI"]
                let ratio = (dpiEnv?.isEmpty == false) ? currentShellDpi : 0
                if isEnginePrimary != 1,
                   fl_drm_view_set_primary_output(view, UInt32(i), ratio) == 1 {
                    currentShellDpi = fl_drm_view_get_scale(view)
                    setenv("FLUTTER_DRM_DPI", "\(currentShellDpi)", 1)
                    FileHandle.standardError.write(Data(
                        "[DisplayLayout] persisted primary \(wanted) hosts the shell (scale \(currentShellDpi))\n".utf8))
                }
                break
            }
        }
    }

    if simSpec.isEmpty && realOutputCount > 1,
       let dl = computeRealLayoutFromEngine(view) {
        displayLayout = dl
    } else {
        displayLayout = DisplayLayout.build(
            physicalWidth: Int(screenW), physicalHeight: Int(screenH),
            scale: currentShellDpi, refreshMhz: Int(fl_drm_view_get_refresh_mhz(view)))
    }
    FileHandle.standardError.write(Data(
        "[DisplayLayout] \(displayLayout!.describe())\n".utf8))

    // One Flutter view per REAL secondary output (sim outputs render inside
    // the primary's scale-to-fit overview instead), pointer-space placements,
    // and runtime hotplug: a monitor plugged in later gets the same
    // treatment via the outputs-changed callback (engine platform thread).
    if simSpec.isEmpty {
        if let dl = displayLayout {
            syncEngineViewsAndLayout(view, dl)
        }
        fl_drm_view_set_outputs_changed_callback(view, { _ in
            drmOutputsChanged()
        }, nil)
    }

    // STARLING_SCREEN_SHELL=<output index>: that output's content is a
    // per-screen shell child rendering on its own GPU (Stage B of
    // docs/plans/nv-view.md). The output was skipped by
    // syncEngineViewsAndLayout above, so the engine accepts it as external.
    if simSpec.isEmpty,
       let extIdStr = ProcessInfo.processInfo.environment["STARLING_SCREEN_SHELL"],
       let extId = Int(extIdStr),
       let dl = displayLayout,
       let out = dl.outputs.first(where: { $0.id == extId && !$0.isHost }) {
        if fl_drm_view_set_output_external(view, UInt32(extId), 1) == 1 {
            let dev = ProcessInfo.processInfo
                .environment["STARLING_SCREEN_SHELL_DEVICE"]
                ?? "/dev/dri/renderD128"
            let shell = ExternalScreenShell(
                view: view, outputId: extId,
                logicalWidth: Int(out.logicalWidth.rounded()),
                logicalHeight: Int(out.logicalHeight.rounded()),
                scale: out.scale, device: dev)
            externalScreenShell = shell
            shell.start()
            fl_drm_view_set_external_input_callback(view, {
                _, phase, x, y, buttons, sdx, sdy, _ in
                if phase == 2 {  // kDown — a click here claims the keyboard
                    if !externalScreenKeyFocus,
                       ProcessInfo.processInfo.environment["STARLING_SWAPCHAIN_DEBUG"] == "1" {
                        FileHandle.standardError.write(Data(
                            "[KeyFocus] external click claims keyboard\n".utf8))
                    }
                    externalScreenKeyFocus = true
                }
                externalScreenShell?.sendInput(phase: Int32(phase), x: x, y: y,
                                               buttons: buttons,
                                               scrollDx: sdx, scrollDy: sdy)
            }, nil)
        } else {
            FileHandle.standardError.write(Data(
                "[ScreenShell] engine refused external mode for output \(extId)\n".utf8))
        }
    }

    // Wire the global cursor-shape setter so widgets (resize handles, title
    // bars, content areas) can ask for a different hardware cursor bitmap.
    DesktopCursor.shapeSetter = { shape in
        fl_drm_view_set_cursor_shape(view, shape.rawValue)
    }
    // Export screen resolution so child apps (SettingsApp) can compute max DPI.
    // Fresh reads, not the values captured at create: the persisted-primary
    // rebind above may have moved the implicit view to a different panel.
    setenv("FLUTTER_SCREEN_WIDTH", "\(fl_drm_view_get_width(view))", 1)
    setenv("FLUTTER_SCREEN_HEIGHT", "\(fl_drm_view_get_height(view))", 1)

    // Set up texture registry with DRM proc address resolver (eglGetProcAddress).
    let textureRegistry = LinuxTextureRegistry()
    textureRegistry.glProcAddressResolver = { name in
        return fl_drm_view_get_proc_address(name)
    }
    drmTextureRegistry = textureRegistry

    // Set up external app manager in vsync-driven mode.
    let engine = OpaquePointer(drmEngine)
    let manager = LinuxExternalAppManager(
        engine: engine,
        textureRegistry: textureRegistry
    )
    manager.enableVsyncDriven()
    linuxExternalAppManager = manager
    let processManager = LinuxProcessAppManager(
        engine: engine,
        textureRegistry: textureRegistry
    )
    FrameCallbackScheduler.shared.register(processManager) { [weak processManager] in
        processManager?.tick()
    }
    linuxProcessAppManager = processManager

    // Appearance change requests from child processes (SettingsApp's Dark
    // Mode toggle) route to the shell's appearance switch.
    processManager.onThemeChangeRequested = { dark in
        _shellState?._setAppearance(dark: dark)
    }

    // Window-manager layout requests (SettingsApp's Tiling toggle).
    processManager.onLayoutChangeRequested = { tiling in
        _shellState?._setTiling(tiling)
    }

    // Wallpaper preset requests (SettingsApp's wallpaper picker).
    processManager.onWallpaperChangeRequested = { preset in
        _shellState?._setWallpaper(preset)
    }

    // Screensaver idle-timeout requests (SettingsApp's Screensaver picker).
    processManager.onScreensaverChangeRequested = { seconds in
        _shellState?._setScreensaverIdle(seconds: Double(seconds))
    }

    // Primary-display picks (SettingsApp's Displays pane).
    processManager.onPrimaryDisplayChangeRequested = { outputId in
        _shellState?._setPrimaryDisplay(outputId: outputId)
    }

    // Seed the list every child is told at connect. Sent again on any change.
    publishDisplaysToChildren()

    // Caret reports from child apps drive the IME candidate panel placement.
    processManager.onCaretChanged = { texId, x, y, w, h, visible in
        _shellState?._imeCaretChanged(textureId: texId, x: x, y: y,
                                      width: w, height: h, visible: visible)
    }

    // Handle runtime DPI change requests from child processes (e.g. SettingsApp).
    processManager.onDpiChangeRequested = { newDpi in
        let oldDpi = currentShellDpi
        // Update the global DPI used for coordinate conversion
        currentShellDpi = newDpi
        // Keep the host output's scale in step with the runtime DPI change —
        // the slider resizes the view the shell tree renders into.
        displayLayout?.updateHostScale(newDpi)
        // Persist so child processes (SettingsApp) inherit the current value
        setenv("FLUTTER_DRM_DPI", "\(newDpi)", 1)
        // Update parent engine metrics
        fl_drm_view_send_metrics(view, newDpi)
        // Don't update Wayland scale factors — existing clients (Chrome) have
        // buffers rendered at the original scale. Changing shellDpi/fractionalScale
        // would break coordinate conversions for those buffers. The engine's
        // pixel_ratio change + texture scaling handles the visual mapping.
        // Notify all child processes (SettingsApp, FlutterDemoApp) to re-render at new DPI
        processManager.broadcastDpiChange(newDpi)
    }

    // Set up Wayland compositor server.
    let wayland = WaylandIntegration(engine: engine, textureRegistry: textureRegistry)
    let drmWidth = Int(fl_drm_view_get_width(view))
    let drmHeight = Int(fl_drm_view_get_height(view))
    let drmDpiInt = max(1, Int(currentShellDpi))
    // Advertise integer scale for wl_output, fractional via wp_fractional_scale_v1.
    // shellDpi uses the actual fractional value for correct coordinate conversion.
    // refreshMhz: the panel's real refresh rate from the active DRM mode.
    wayland.start(screenWidth: drmWidth, screenHeight: drmHeight, scale: drmDpiInt, shellDpi: currentShellDpi,
                  refreshMhz: Int(fl_drm_view_get_refresh_mhz(view)))
    // REAL multi-output: advertise the arrangement to clients — one
    // wl_output per display with logical positions (replaces the single
    // config-built output). Surface enter/leave follows window rects via
    // updateWaylandSurfaceOutputs(). Sim outputs stay single-output: clients
    // really do render onto the one physical panel there.
    if let dl = displayLayout, dl.outputs.count > 1, !secondaryViewOutputs.isEmpty {
        wayland.setOutputs(dl.outputs)
    }
    // Advertise the dma-buf modifiers our EGL can actually import (v3
    // modifier events + v4 feedback table) so external clients negotiate
    // layouts explicitly instead of relying on implicit-modifier guessing.
    wayland.advertiseDmaBufFormats(eglDisplay: fl_drm_view_get_egl_display(view))
    FrameCallbackScheduler.shared.register(wayland) { [weak wayland] in
        wayland?.tick()
    }
    waylandIntegration = wayland
    _onWaylandIntegrationReady?()  // Wire up DesktopShell callbacks now that waylandIntegration is set

    // Register Wayland server fd with DRM epoll so client connections
    // wake the event loop and dispatch events on the platform thread.
    let waylandFd = wayland.serverFd
    if waylandFd >= 0 {
        fl_drm_view_add_external_fd(view, Int32(waylandFd), { userData in
            guard let wl = waylandIntegration else { return }
            wl.dispatchEvents()
        }, nil)
    }

    // Register wakeup pipe fd so UI thread commands are drained promptly.
    let wakeupFd = wayland.wakeupReadFd
    if wakeupFd >= 0 {
        fl_drm_view_add_external_fd(view, wakeupFd, { userData in
            guard let wl = waylandIntegration else { return }
            wl.drainWakeupPipe()
        }, nil)
    }

    // Real-vsync frame pacing: page-flip completions (platform thread, same
    // thread as the Wayland event loop) drive client frame callbacks and
    // presentation feedback with kernel scanout timestamps — per output, so
    // clients are paced by the panel they actually sit on.
    //
    // `dropped` recovery: secondary chains are frame-dropping mailboxes (a
    // slow panel must not stall the raster thread), and a drop can be the
    // FINAL frame of an animation — nothing else in flight would ever fix
    // the staleness. Poking the output's screen host rebuilds its tree,
    // which re-renders the view and presents the newest content.
    fl_drm_view_set_output_present_callback(view, { _, outputIndex, flipTimeNs, refreshNs, dropped in
        if let wl = waylandIntegration {
            wl.handlePresent(flipTimeNs: flipTimeNs, refreshNs: refreshNs,
                             outputId: Int(outputIndex))
        }
        if dropped != 0 {
            let idx = Int(outputIndex)
            DispatchQueue.main.async {
                secondaryScreenForceRedraws[idx]?()
            }
        }
    }, nil)

    // Screen recording: register the frame sink before the event loop runs
    // (the engine refuses recording_start with no callback). Frames arrive
    // on the engine's recorder writer thread; ingest copies into the
    // service's mailbox and returns — nothing here may touch shell state.
    let recording = RecordingService()
    recordingService = recording
    screenCastService = ScreenCastService()
    // One frame sink, two consumers: the engine runs a single capture
    // session, so each frame belongs to whichever service claimed it —
    // a ScreenCast session routes here, everything else is a recording.
    fl_drm_view_set_record_frame_callback(view, { _, rgba, w, h, _ in
        if ScreenCastService.captureActive {
            screenCastService?.ingest(rgba, width: Int(w), height: Int(h))
        } else {
            recordingService?.ingest(rgba, width: Int(w), height: Int(h))
        }
    }, nil)
    // Zero-copy sibling: dmabuf frames on the engine's PRESENTING thread —
    // ingestDmabuf queues the frame and returns; anything heavier here
    // stalls the desktop's present path.
    fl_drm_view_set_record_dmabuf_callback(view, { _, frame in
        guard let frame else { return }
        recordingService?.ingestDmabuf(frame.pointee)
    }, nil)

    // Mark as epoll-driven so tick() doesn't dispatch (epoll handles it).
    wayland.setEpollDriven()

    // Set up X11 server (listens on :1 to avoid conflict with any existing X)
    let x11 = X11Integration(engine: engine, textureRegistry: textureRegistry)
    x11.start(displayNum: 1, screenWidth: drmWidth, screenHeight: drmHeight, drmView: view)
    x11Integration = x11
    _onX11IntegrationReady?()  // Wire up DesktopShell callbacks now that x11Integration is set

    // Register X11 listen fd with DRM epoll for new connections.
    let x11Fd = x11.serverFd
    if x11Fd >= 0 {
        fl_drm_view_add_external_fd(view, Int32(x11Fd), { userData in
            guard let x = x11Integration else { return }
            x.dispatchEvents()
        }, nil)
    }
    // Dispatch X11 on every engine frame to process client requests
    // on already-connected sockets (not in epoll set).
    /* NOTE: Do NOT register X11 with FrameCallbackScheduler.
     * The FrameCallbackScheduler runs on the raster thread (io.flutter.raster),
     * but x11_server_dispatch is also called from the DRM epoll thread (main).
     * Concurrent dispatch from two threads causes data races → SIGABRT crash.
     * X11 dispatch is handled solely by the epoll fd callbacks. */

    // Register the external texture callback with the DRM view.
    fl_drm_view_set_external_texture_callback(view, { (userData, textureId, width, height, textureOut) -> Int32 in
        guard let registry = drmTextureRegistry,
              let out = textureOut?.assumingMemoryBound(to: FlutterOpenGLTexture.self) else {
            return 0
        }
        return registry.populateTexture(
            id: textureId,
            width: Int(width),
            height: Int(height),
            textureOut: out
        ) ? 1 : 0
    }, nil)

    // Start the portal service (Settings + FileChooser) on THIS session's bus
    // — $XDG_RUNTIME_DIR/bus, which is the bus app-run points every client at.
    //
    // Pin the address explicitly in both cases. Letting sd-bus pick (the old
    // unprivileged path) makes it honour an inherited DBUS_SESSION_BUS_ADDRESS,
    // and under GDM that is the user's real /run/user/<uid>/bus: the portal
    // then claims org.freedesktop.portal.Desktop on a bus no client in this
    // session ever talks to. On the session's own bus the name is left
    // unowned, so the first client request D-Bus-activates the stock
    // xdg-desktop-portal there instead — which finds no Starling backend and
    // serves no FileChooser, breaking every file dialog. Running as root hid
    // this completely, because that branch always pinned the address.
    //
    // targetUid only matters as root: the portal thread drops euid to the
    // login user before connecting, so it can reach their runtime dir.
    let portal = PortalIntegration()
    portal.start(busAddress: "unix:path=\(LoginUser.runtimeDir)/bus",
                 targetUid: getuid() == 0 ? UInt32(LoginUser.uid) : 0)
    // Advertise the persisted appearance (1 = dark, 2 = light) — Wayland
    // clients (Chrome, GTK/Qt) read org.freedesktop.appearance/color-scheme
    // and follow SettingChanged on switches (_setAppearance emits it).
    _DesktopShellState.loadPersistedAppearance()
    portal.setColorScheme(shellTheme.isDark ? 1 : 2)
    // FileChooser: launch FileExplorerApp --picker as a composited DMA-BUF
    // child window (see PortalFileChooser.swift). userdata unused — the thunk
    // reaches the shell via the _shellState global.
    portal.setChooserLauncher(portalChooserLaunchThunk, userdata: nil)
    // ScreenCast: monitor capture into a PipeWire stream (screen share for
    // Chromium/Electron/OBS). The completion closure is assigned before the
    // hooks so a request cannot race the wiring; it is thread-safe.
    screenCastService?.completeStart = { handle, node, w, h, response in
        portalIntegration?.completeScreenCastStart(
            handle: handle, node: node, width: w, height: h,
            response: response)
    }
    portalIntegration = portal
    portal.setScreenCastHooks(start: portalScreenCastStartThunk,
                              stop: portalScreenCastStopThunk,
                              userdata: nil)

    // The notification daemon, on the same pinned bus for the same reasons.
    // The launchers mask org.freedesktop.Notifications so a stock daemon
    // cannot be activation-raced onto this bus, exactly like the portal.
    let notifications = NotificationIntegration()
    notifications.start(busAddress: "unix:path=\(LoginUser.runtimeDir)/bus",
                        targetUid: getuid() == 0 ? UInt32(LoginUser.uid) : 0)
    notificationIntegration = notifications

    // Schedule first frame.
    PlatformDispatcher.instance.scheduleFrame()

    // Run the event loop (blocks until shutdown).
    // fl_drm_view_run installs its own SIGUSR1 handler (ScreenshotSignalHandler)
    // which sets g_screenshot_requested and schedules a frame. But the Swift
    // adapter skips compositing when nothing is dirty, so the present callback
    // (which does glReadPixels) never fires. We re-install SIGUSR1 after the
    // C++ handler is set, chaining both: set _forceNextComposite AND call the
    // C++ function to set g_screenshot_requested.
    //
    // fl_drm_view_run calls signal(SIGUSR1, ...) synchronously before entering
    // the epoll loop, so we use DispatchQueue to install our handler on the
    // next run loop iteration (after the C++ handler is already installed).
    DispatchQueue.main.async {
        signal(SIGUSR1) { _ in
            Flutter._forceNextComposite = true
            fl_drm_view_request_screenshot()
        }
    }

    // SIGRTMIN+1: toggle DPI between 2.0 and 1.5 for testing.
    // SIGUSR2 is used by VT switching — cannot use it.
    fl_drm_view_run(view)

    // Cleanup.
    portalIntegration?.stop()
    portalIntegration = nil
    x11Integration?.stop()
    x11Integration = nil
    waylandIntegration?.stop()
    waylandIntegration = nil
    linuxProcessAppManager = nil
    linuxExternalAppManager = nil
    drmTextureRegistry = nil
    fl_drm_view_destroy(view)
    exit(0)
}

// ─── Headless fallback (--headless flag) ─────────────────────────────────────

func runHeadless() -> Never {
    runApp(
        MacosApp(
            themeMode: .dark,
            home: DesktopShell(),
            title: "Desktop Shell"
        )
    )
    var callbacks = createRuntimeCallbacks()

    var rendererConfig = FlutterRendererConfig()
    rendererConfig.type = kSoftware
    rendererConfig.software.struct_size = MemoryLayout<FlutterSoftwareRendererConfig>.size
    rendererConfig.software.surface_present_callback = {
        (_userData, _allocation, rowBytes, height) -> Bool in
        return true
    }

    var args = FlutterProjectArgs()
    args.struct_size = MemoryLayout<FlutterProjectArgs>.size
    let engineOutDir = ProcessInfo.processInfo.environment["FLUTTER_ENGINE_OUT"] ?? "../engine/src/out/host_debug"
    let assetsPath = strdup("\(engineOutDir)/flutter_assets")!
    let icuPath = strdup("\(engineOutDir)/icudtl.dat")!
    args.assets_path = UnsafePointer(assetsPath)
    args.icu_data_path = UnsafePointer(icuPath)

    let argv0 = strdup("DesktopShellApp")!
    let argv1 = strdup("--enable-impeller=false")!
    let argvBuf = UnsafeMutableBufferPointer<UnsafePointer<CChar>?>.allocate(capacity: 3)
    argvBuf[0] = UnsafePointer(argv0)
    argvBuf[1] = UnsafePointer(argv1)
    argvBuf[2] = nil
    args.command_line_argc = 2
    args.command_line_argv = UnsafePointer(argvBuf.baseAddress!)

    var engine: OpaquePointer? = nil
    let initResult = withUnsafeMutablePointer(to: &callbacks) { cbPtr in
        FlutterEngineInitializeSwift(
            Int(FLUTTER_ENGINE_VERSION),
            &rendererConfig,
            &args,
            nil,
            UnsafeRawPointer(cbPtr),
            &engine
        )
    }
    guard initResult == kSuccess, let engine = engine else {
        fatalError("[DesktopShellApp] FlutterEngineInitializeSwift failed")
    }
    let runResult = FlutterEngineRunInitializedSwift(engine)
    guard runResult == kSuccess else {
        fatalError("[DesktopShellApp] FlutterEngineRunInitializedSwift failed")
    }
    var metrics = FlutterWindowMetricsEvent()
    metrics.struct_size = MemoryLayout<FlutterWindowMetricsEvent>.size
    metrics.width = 1440; metrics.height = 900
    metrics.pixel_ratio = 1.0; metrics.view_id = 0
    FlutterEngineSendWindowMetricsEvent(engine, &metrics)
    PlatformDispatcher.instance.scheduleFrame()
    Foundation.RunLoop.main.run()
    exit(0)
}

// ─── Windowed entry point ────────────────────────────────────────────────────

// Check for --drm flag (DRM/KMS direct rendering)
if CommandLine.arguments.contains("--drm") {
    runDRM()
}

// Check for --headless flag
if CommandLine.arguments.contains("--headless") {
    runHeadless()
}

// The windowed X11/GLFW dev path has been removed — the shell is DRM-only
// (plus --headless). runDRM()/runHeadless() above never return.
fatalError("[DesktopShellApp] requires --drm (or --headless); windowed mode is not supported")
#endif  // os(Linux)
