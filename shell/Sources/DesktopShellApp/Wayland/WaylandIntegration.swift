// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import WaylandServerBridge
import Foundation
#if os(Linux)
import DmaBufBridge
import FlutterDRMBridge   // fl_drm_view_arm_capture / read_capture (screencopy)
import FlutterEmbedderBridge
import Glibc
import Dispatch
#endif

/// A layer surface's arrangement (zwlr_layer_shell_v1), as the compositor
/// reports it: which output and layer, how it is anchored, the size it was
/// configured to. The shell places it from this plus the buffer the client
/// actually committed.
struct LayerSurfaceInfo {
    var outputIndex: Int
    /// 0 background, 1 bottom, 2 top, 3 overlay
    var layer: Int
    /// Bitfield: 1 top, 2 bottom, 4 left, 8 right
    var anchor: UInt32
    var marginTop: Int, marginRight: Int, marginBottom: Int, marginLeft: Int
    var width: Int, height: Int
    var exclusiveZone: Int
    /// One anchor bit, or 0 = reserves nothing
    var exclusiveEdge: UInt32
    /// 0 none, 1 exclusive, 2 on demand
    var keyboardInteractivity: Int
    var namespace: String

    init(_ c: WaylandLayerSurfaceInfo) {
        outputIndex = Int(c.output_index)
        layer = Int(c.layer)
        anchor = c.anchor
        marginTop = Int(c.margin_top)
        marginRight = Int(c.margin_right)
        marginBottom = Int(c.margin_bottom)
        marginLeft = Int(c.margin_left)
        width = Int(c.width)
        height = Int(c.height)
        exclusiveZone = Int(c.exclusive_zone)
        exclusiveEdge = c.exclusive_edge
        keyboardInteractivity = Int(c.keyboard_interactivity)
        namespace = withUnsafeBytes(of: c.namespace_) { buf in
            String(cString: buf.bindMemory(to: CChar.self).baseAddress!)
        }
    }
}

// MARK: - Thread-Safe Queue

/// Thread-safe mutable box for sharing state across threads.
private final class AtomicBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
    init(_ value: T) { self._value = value }

    /// Atomic read-modify-write — appends must use this, not get+set
    /// (two lock acquisitions lose updates against a concurrent drain).
    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return body(&_value)
    }

    /// Atomically take the current value, leaving `empty` behind.
    func take(_ empty: T) -> T {
        lock.lock(); defer { lock.unlock() }
        let v = _value
        _value = empty
        return v
    }
}

// MARK: - Event / Command Enums

/// Events produced on the platform thread (C callbacks), consumed on the UI thread.
private enum WaylandEvent: @unchecked Sendable {
    case newToplevel(surfaceId: UInt32, clientId: UInt64)
    case surfaceCommit(surfaceId: UInt32, fd: Int32, width: Int, height: Int,
                       stride: Int, fourcc: UInt32, modifier: UInt64,
                       firstCommit: Bool, bufferScale: Int,
                       viewportWidth: Int, viewportHeight: Int)
    /// wl_shm commit. `pixels` is a tightly-packed copy owned by this event —
    /// whoever consumes it must deallocate.
    case shmSurfaceCommit(surfaceId: UInt32, pixels: UnsafeMutableRawPointer,
                          width: Int, height: Int, format: UInt32,
                          firstCommit: Bool, bufferScale: Int,
                          viewportWidth: Int, viewportHeight: Int)
    case toplevelDestroy(surfaceId: UInt32)
    /// A client connection closed. The last moment its clientId means
    /// anything — see WaylandIntegration.onClientDestroyed.
    case clientDestroy(clientId: UInt64)
    case titleChanged(surfaceId: UInt32, title: String)
    case appIdChanged(surfaceId: UInt32, appId: String)
    case newPopup(surfaceId: UInt32, parentSurfaceId: UInt32,
                  x: Int, y: Int, width: Int, height: Int)
    case popupDestroy(surfaceId: UInt32)
    case windowGeometry(surfaceId: UInt32, x: Int, y: Int, width: Int, height: Int)
    /// xdg_toplevel min/max size hints, surface coordinates, 0 = unset.
    case sizeHints(surfaceId: UInt32, minW: Int32, minH: Int32, maxW: Int32, maxH: Int32)
    /// xdg_toplevel.set_parent: a dialog for `parentId` (0 = cleared).
    case toplevelParent(surfaceId: UInt32, parentId: UInt32)
    /// xdg_popup.reposition answered: parent-relative place and size.
    case popupRepositioned(surfaceId: UInt32, x: Int, y: Int, width: Int, height: Int)
    /// A subsurface with content of its own, drawn inside its toplevel's
    /// window at (x, y) from the toplevel's surface origin.
    case subsurfacePlaced(surfaceId: UInt32, toplevelId: UInt32, x: Int32, y: Int32, z: Int32, acceptsInput: Bool)
    case subsurfaceUnmapped(surfaceId: UInt32)
    case fullscreenRequest(surfaceId: UInt32)
    case unfullscreenRequest(surfaceId: UInt32)
    case cursorShape(shape: UInt32)
    case moveRequest(surfaceId: UInt32)
    case interactiveResizeRequest(surfaceId: UInt32, edges: UInt32)
    /// zwp_text_input_v3 state on the focused surface (cursor rect is
    /// surface-local logical coords).
    case textInputState(surfaceId: UInt32, enabled: Bool,
                        x: Int32, y: Int32, w: Int32, h: Int32)
    /// A client asked for a window-state change the shell owns
    /// (WAYLAND_TOPLEVEL_REQUEST_*): its own xdg_toplevel.set_maximized, a
    /// taskbar's unminimize, an xdg_activation activate.
    case toplevelRequest(surfaceId: UInt32, request: Int32)
    case newLayerSurface(surfaceId: UInt32, info: LayerSurfaceInfo)
    case layerSurfaceChanged(surfaceId: UInt32, info: LayerSurfaceInfo)
    case layerSurfaceDestroy(surfaceId: UInt32)
    case surfaceAlpha(surfaceId: UInt32, alpha: Double)
    case toplevelPositionRequest(surfaceId: UInt32, outputIndex: Int32, x: Int32, y: Int32)
    case systemBell(surfaceId: UInt32)
    case shortcutsInhibit(surfaceId: UInt32, inhibited: Bool)
    case sessionLock(locked: Bool)
    /// ext_workspace: a panel's request (WAYLAND_WORKSPACE_REQUEST_*).
    case workspaceRequest(id: UInt32, request: Int32, name: String)
    /// ext_background_effect: blur rects (x, y, w, h)… in surface coords.
    case surfaceBlur(surfaceId: UInt32, rects: [Int32])
    /// zwlr_virtual_pointer: one frame of synthetic pointer input.
    case virtualPointer(outputIndex: Int, hasAbs: Bool, ax: Double, ay: Double,
                        dx: Double, dy: Double, buttons: Int64,
                        wheelDx: Double, wheelDy: Double)
    /// zwp_virtual_keyboard: one key, decoded through the client's keymap.
    case virtualKey(evdev: UInt32, keysym: UInt32, text: String, pressed: Bool)
    /// wp_pointer_warp: put the pointer at (x, y) of the surface.
    case pointerWarp(surfaceId: UInt32, x: Double, y: Double)
    /// zwp_pointer_constraints: a lock or confinement came into force or
    /// ended; a lock's end may carry a cursor position hint (surface units).
    case pointerConstraint(surfaceId: UInt32, lock: Bool, active: Bool,
                           hintX: Double?, hintY: Double?)
    /// wl_data_device drag: `active` while a drag is on; the icon surface
    /// (0 = none) is a role of its own, drawn at the pointer.
    case dragIcon(surfaceId: UInt32, active: Bool)
    /// xdg_toplevel_drag: the toplevel riding the drag, and its offset.
    case toplevelDrag(surfaceId: UInt32, xOff: Int32, yOff: Int32, active: Bool)
    /// wlr-output-management apply: the host output's scale.
    case outputConfig(configId: UInt32, hostScale: Double)
}

/// Commands produced on the UI thread, executed on the platform thread.
private enum WaylandCommand: @unchecked Sendable {
    case configureToplevel(surfaceId: UInt32, width: Int32, height: Int32)
    /// A 0x0 configure: the client picks its size (a dialog).
    case configureToplevelNatural(surfaceId: UInt32)
    /// Focus moved: every pointer lock and confinement ends.
    case breakPointerConstraints
    case closeToplevel(surfaceId: UInt32)
    case flushClients
    case updateScale(scale: Int32, fractional120: UInt32)
    case setOutputs(outputs: [WaylandOutputDesc])
    case setSurfaceOutputs(surfaceId: UInt32, mask: UInt32, paceMask: UInt32)
    case setSurfaceThrottle(surfaceId: UInt32, intervalMs: UInt32)
    case textInputCommit(text: String)
    case textInputPreedit(text: String, cursor: Int32)
    case setToplevelState(surfaceId: UInt32, states: UInt32)
    /// `pixels` is BGRX top-down, owned by the command — freed once copied.
    case screencopyDeliver(frameId: UInt32, pixels: UnsafeMutableRawPointer, stride: Int32)
    case screencopyFail(frameId: UInt32)
    case toplevelPosition(surfaceId: UInt32, x: Int32, y: Int32)
    case toplevelPositionFailed(surfaceId: UInt32)
    case setWorkArea(outputIndex: Int32, x: Int32, y: Int32, w: Int32, h: Int32)
    case setFrameExtents(top: Int32, bottom: Int32, left: Int32, right: Int32)
    case setWorkspaces(list: [WaylandWorkspaceEntry])
    case outputConfigResult(configId: UInt32, ok: Bool)
}

/// One workspace as ext_workspace_v1 advertises it: the shell's space id,
/// its display name and whether it is the active one.
struct WaylandWorkspaceEntry: Equatable {
    let id: UInt32
    let name: String
    let active: Bool
}

// MARK: - WaylandIntegration

/// The only two `wl_shm` formats the compositor advertises (see
/// `wayland_shm.c`). Both are B,G,R,{A,X} in memory on a little-endian host,
/// so ARGB is the only one carrying alpha worth honouring.
private let kShmFormatARGB8888: UInt32 = 0
private let kShmFormatXRGB8888: UInt32 = 1

/// Bridges the Wayland compositor server to DesktopShellApp's window system.
///
/// Thread model:
/// - **Platform thread** (epoll): `wayland_server_dispatch()`, C callbacks queue
///   events into `pendingEvents`, configure commands are executed here.
/// - **UI thread** (onBeginFrame → FrameCallbackScheduler): `tick()` drains
///   queued events and calls DesktopShell callbacks (setState, etc.).
/// - Input forwarding (pointer/keyboard/scroll) uses the C-level deferred pipe
///   and is safe from any thread.
class WaylandIntegration {
    private var server: OpaquePointer?  // WaylandServer*
    let engine: OpaquePointer
    let textureRegistry: LinuxTextureRegistry

    // ─── Surface tracking (UI thread only) ──────────────────────────────

    private var surfaceTextures: [UInt32: Int64] = [:]   // surfaceId → textureId
    private var surfaceWindows: [UInt32: String] = [:]    // surfaceId → windowId
    private var surfaceAppIds: [UInt32: String] = [:]     // surfaceId → xdg app_id
    private var surfacePids: [UInt32: pid_t] = [:]        // surfaceId → client pid
    private var surfaceClients: [UInt32: UInt64] = [:]    // surfaceId → wl_client id
    private var surfaceSizes: [UInt32: (Int, Int)] = [:]  // surfaceId → (width, height) in buffer pixels
    private var surfaceBufferScales: [UInt32: Int] = [:]  // surfaceId → buffer_scale from client
    private var surfaceGeometry: [UInt32: (x: Int, y: Int, width: Int, height: Int)] = [:]
    private var lastEmittedGeometry: [UInt32: (x: Int, y: Int, w: Int, h: Int, bufW: Int, bufH: Int)] = [:]
    private var popupSurfaceIds: Set<UInt32> = []
    /// Popups repositioned since their last frame: the new place waits for
    /// the frame the client commits for it (surface units, parent-relative).
    private var pendingPopupMoves: [UInt32: (x: Int, y: Int)] = [:]
    /// Wayland subsurfaces the shell draws inside a window: their toplevel
    /// (a surface id in surfaceWindows), their offset from its surface
    /// origin, their logical size, and the rect last handed to the shell.
    private var subsurfaceParents: [UInt32: UInt32] = [:]
    private var subsurfaceOffsets: [UInt32: (x: Int, y: Int)] = [:]
    private var subsurfaceZ: [UInt32: Int] = [:]
    /// Whether the pointer over the subsurface is the subsurface's own
    /// (false for an empty wl_surface input region: it passes through).
    private var subsurfaceAcceptsInput: [UInt32: Bool] = [:]
    private var subsurfaceLogicalSizes: [UInt32: (Int, Int)] = [:]
    private var subsurfaceEmitted: [UInt32: (Double, Double, Double, Double, Int, Bool)] = [:]
    /// Surfaces with the zwlr_layer_surface_v1 role: placed by the shell at a
    /// screen coordinate, drawn in their layer, never decorated or managed.
    private var layerSurfaceIds: Set<UInt32> = []
    /// The WAYLAND_TOPLEVEL_* bits last pushed per surface (diff guard).
    private var surfaceStateCache: [UInt32: UInt32] = [:]
    /// The zone-relative frame position last reported per surface.
    private var surfacePositionCache: [UInt32: (Int32, Int32)] = [:]
    private var workAreaCache: [Int32: (Int32, Int32, Int32, Int32)] = [:]
    /// Surfaces whose client holds a keyboard-shortcuts inhibitor: every key
    /// goes to them, the desktop's chords included.
    private var shortcutsInhibitedSurfaces: Set<UInt32> = []
    private var outputScale: Int = 1
    private var shellDpi: Double = 1.0
    private var fractionalScale: Double = 1.0

    // Resize throttling (UI thread only)
    private var lastResizeTime: [UInt32: UInt64] = [:]
    private var pendingResize: [UInt32: (width: Int, height: Int)] = [:]
    private let resizeIntervalNs: UInt64 = 33_000_000  // 33ms (~30fps)

    // ─── Thread-safe queues ─────────────────────────────────────────────

    /// Events from platform thread → UI thread.
    private let pendingEvents = AtomicBox<[WaylandEvent]>([])

    /// Commands from UI thread → platform thread.
    private let pendingCommands = AtomicBox<[WaylandCommand]>([])

    /// Wakeup pipe: UI thread writes to trigger epoll → platform drains commands.
    private(set) var wakeupReadFd: Int32 = -1
    private var wakeupWriteFd: Int32 = -1

    /// When true, dispatch is driven by epoll (DRM mode). When false, tick()
    /// dispatches directly (GLFW mode).
    private var _epollDriven = false

    /// Set by handle* methods on platform thread, cleared by dispatchEvents.
    private var _needsFrame = false

    // ─── Callbacks (set by DesktopShell, called from tick on UI thread) ──

    var onNewWindow: ((_ surfaceId: UInt32, _ textureId: Int, _ title: String, _ clientId: UInt64) -> String)?
    var onWindowDestroyed: ((_ windowId: String) -> Void)?
    /// A client connection went away, so its clientId is now free for reuse
    /// by an unrelated client. Anything the shell keyed on it — agent window
    /// ownership, most of all — must be dropped here, or the next client to
    /// land on the same address inherits it.
    var onClientDestroyed: ((_ clientId: UInt64) -> Void)?
    var onTitleChanged: ((_ windowId: String, _ title: String) -> Void)?
    /// The client's own name for itself (`xdg_toplevel.set_app_id`). This is
    /// how a window is tied back to an installed app — it matches the
    /// `StartupWMClass` in the app's `.desktop` entry, which is what
    /// `app-install` records into the app registry. Nothing else identifies a
    /// window reliably: titles follow the open document.
    var onAppIdChanged: ((_ windowId: String, _ appId: String) -> Void)?
    var onWindowBufferResized: ((_ windowId: String, _ logicalWidth: Int, _ logicalHeight: Int) -> Void)?
    var onPopupBufferResized: ((_ popupId: String, _ logicalWidth: Int, _ logicalHeight: Int, _ geoX: Int, _ geoY: Int) -> Void)?
    /// A repositioned popup's first frame after the reposition: its new
    /// parent-relative place (x, y — surface units, before the geometry
    /// offset) with the size and geometry of that frame, all at once.
    var onPopupRepositioned: ((_ popupId: String, _ logicalWidth: Int, _ logicalHeight: Int,
                               _ geoX: Int, _ geoY: Int, _ x: Int, _ y: Int) -> Void)?
    var onNewPopup: ((_ surfaceId: UInt32, _ textureId: Int, _ parentSurfaceId: UInt32, _ x: Int, _ y: Int, _ width: Int, _ height: Int) -> String)?
    var onPopupDestroyed: ((_ popupId: String) -> Void)?
    var onWindowGeometryChanged: ((_ windowId: String, _ x: Int, _ y: Int, _ width: Int, _ height: Int, _ bufferLogicalWidth: Int, _ bufferLogicalHeight: Int) -> Void)?
    /// xdg_toplevel.set_parent: the window is a dialog for `parentWindowId`
    /// (nil = cleared). `mapped` says whether it has drawn yet — before its
    /// first buffer the shell can still change what it is configured to.
    var onWindowParent: ((_ windowId: String, _ parentWindowId: String?, _ mapped: Bool) -> Void)?
    /// xdg_toplevel min/max size hints in the shell's logical pixels
    /// (content size; 0 = unset). The shell clamps its resizes to them.
    var onWindowSizeHints: ((_ windowId: String, _ minW: Double, _ minH: Double,
                             _ maxW: Double, _ maxH: Double) -> Void)?
    /// A Wayland subsurface to draw inside a window's content: its texture
    /// and where, content-relative, in the shell's logical pixels. Called
    /// when it appears and whenever its place or size changes — not per
    /// frame; the texture updates on its own. `acceptsInput`: the pointer
    /// over it is the subsurface's own (send events under ITS id); false
    /// when the client gave it an empty input region, and the pointer
    /// passes through to the window (Chrome's video overlays).
    var onSubsurfaceChanged: ((_ windowId: String, _ surfaceId: UInt32,
                               _ textureId: Int, _ rect: Rect, _ z: Int,
                               _ acceptsInput: Bool) -> Void)?
    var onSubsurfaceRemoved: ((_ windowId: String, _ surfaceId: UInt32) -> Void)?
    var onFullscreenRequest: ((_ windowId: String) -> Void)?
    var onUnfullscreenRequest: ((_ windowId: String) -> Void)?
    /// Client-initiated interactive move/resize (xdg_toplevel.move/resize).
    var onMoveRequest: ((_ windowId: String) -> Void)?
    /// Focused Wayland client's text-input state: enabled + cursor rect
    /// (surface-local logical coords). Drives IME routing + panel anchor.
    var onTextInputState: ((_ windowId: String, _ enabled: Bool,
                            _ x: Double, _ y: Double,
                            _ w: Double, _ h: Double) -> Void)?

    /// IME delivery to the focused client's enabled text input (queued to
    /// the server's event-loop thread).
    func sendTextInputCommit(_ text: String) {
        enqueueCommand(.textInputCommit(text: text))
        enqueueCommand(.flushClients)
    }

    func sendTextInputPreedit(_ text: String, cursor: Int32) {
        enqueueCommand(.textInputPreedit(text: text, cursor: cursor))
        enqueueCommand(.flushClients)
    }
    var onInteractiveResizeRequest: ((_ windowId: String, _ edges: UInt32) -> Void)?

    // ─── Window state, layer shell, alpha, zones (UI thread) ─────────────

    /// The shell's window state for a Wayland window, as WAYLAND_TOPLEVEL_*
    /// bits (maximized, fullscreen, activated, minimized). Read right before
    /// every configure and by syncAllToplevelStates, so the bits a client
    /// sees are always the shell's current ones.
    var stateProvider: ((_ windowId: String) -> UInt32)?
    /// A client asked for a state change (WAYLAND_TOPLEVEL_REQUEST_*).
    var onToplevelRequest: ((_ windowId: String, _ request: Int32) -> Void)?
    /// A layer surface appeared (its texture is registered; buffers follow
    /// through the ordinary commit path), changed its arrangement, got a new
    /// buffer size, or went away.
    var onNewLayerSurface: ((_ surfaceId: UInt32, _ textureId: Int, _ info: LayerSurfaceInfo) -> Void)?
    var onLayerSurfaceChanged: ((_ surfaceId: UInt32, _ info: LayerSurfaceInfo) -> Void)?
    var onLayerSurfaceBufferResized: ((_ surfaceId: UInt32, _ logicalWidth: Int, _ logicalHeight: Int) -> Void)?
    var onLayerSurfaceDestroyed: ((_ surfaceId: UInt32) -> Void)?
    /// wp_alpha_modifier: the surface (a window's, a popup's or a layer
    /// surface's) wants its content drawn at this opacity.
    var onSurfaceAlpha: ((_ surfaceId: UInt32, _ alpha: Double) -> Void)?
    /// xx-zones: a client wants its window's frame at (x, y) of the work
    /// area of output `outputIndex`. Answer with reportToplevelPosition.
    var onToplevelPositionRequest: ((_ windowId: String, _ outputIndex: Int, _ x: Int, _ y: Int) -> Void)?
    /// xdg_system_bell: ring for a window (nil = no surface named).
    var onSystemBell: ((_ windowId: String?) -> Void)?
    /// ext_session_lock: locked (true) or unlocked. Lock surfaces arrive as
    /// overlay layer surfaces named "session-lock"; while locked the shell
    /// draws nothing but those, and black.
    var onSessionLock: ((_ locked: Bool) -> Void)?
    /// ext_workspace_v1: a panel activated/removed/created a workspace.
    var onWorkspaceRequest: ((_ id: UInt32, _ request: Int32, _ name: String) -> Void)?
    /// ext_background_effect_v1: blur these rects (surface coords, flat
    /// x,y,w,h quads; empty = no blur) behind the surface's content.
    var onSurfaceBlur: ((_ surfaceId: UInt32, _ rects: [Int32]) -> Void)?
    /// zwlr_virtual_pointer_v1: a client's pointer frame — absolute as
    /// fractions of the output, or relative in logical px; buttons are the
    /// Flutter mask; wheel deltas are Flutter's units.
    var onVirtualPointer: ((_ outputIndex: Int, _ hasAbs: Bool, _ ax: Double, _ ay: Double,
                            _ dx: Double, _ dy: Double, _ buttons: Int64,
                            _ wheelDx: Double, _ wheelDy: Double) -> Void)?
    /// zwp_virtual_keyboard_v1: a decoded key press/release.
    var onVirtualKey: ((_ evdev: UInt32, _ keysym: UInt32, _ text: String, _ pressed: Bool) -> Void)?
    /// wp_pointer_warp_v1: (x, y) are logical, surface-local.
    var onPointerWarp: ((_ surfaceId: UInt32, _ x: Double, _ y: Double) -> Void)?
    /// A pointer lock (lock=true) or confinement on a window came into force
    /// or ended. The hint, on a lock's end, is where the client wants the
    /// cursor back, content-relative in logical pixels.
    var onPointerConstraint: ((_ windowId: String, _ surfaceId: UInt32, _ lock: Bool,
                               _ active: Bool, _ hint: Offset?) -> Void)?
    /// The surface a pointer lock is in force on: its client gets relative
    /// motion from the shell's root listener and no absolute motion.
    private(set) var lockedSurface: UInt32? = nil
    /// A drag-and-drop began or ended.
    var onDragStateChanged: ((_ active: Bool) -> Void)?
    /// The drag's icon surface appeared (its id and texture) or went (nil).
    var onDragIcon: ((_ iconId: String?, _ textureId: Int) -> Void)?
    /// xdg_toplevel_drag_v1: keep the window's content origin at the
    /// pointer minus the offset while active.
    var onToplevelDrag: ((_ windowId: String, _ xOff: Int, _ yOff: Int, _ active: Bool) -> Void)?
    /// wlr-output-management: apply this host scale, then answer through
    /// outputConfigResult.
    var onOutputConfig: ((_ configId: UInt32, _ hostScale: Double) -> Void)?
    /// A wl_data_device drag is in progress: ordinary per-window pointer
    /// forwarding pauses and the shell's drag router steers the pointer
    /// (see _DesktopShellState._dragPointerMoved).
    private(set) var dragActive = false
    private var dragIconSurfaceId: UInt32? = nil
    private var lastWorkspaces: [WaylandWorkspaceEntry]? = nil
    /// Surface coordinates → shell logical px (the inverse of what
    /// sendPointerEvent applies on the way in).
    var surfaceToLogical: Double { fractionalScale / shellDpi }
    /// Screencopy is in flight: the desktop must present so the engine's
    /// capture mirror refreshes. Same rider contract as the recorders.
    nonisolated(unsafe) var onFramePumpNeedChanged: (() -> Void)?
    private let screencopyInFlight = AtomicBox<Int>(0)
    var needsFramePump: Bool { screencopyInFlight.value > 0 }

    // ─── Init / Lifecycle ───────────────────────────────────────────────

    init(engine: OpaquePointer, textureRegistry: LinuxTextureRegistry) {
        self.engine = engine
        self.textureRegistry = textureRegistry
    }

    deinit {
        stop()
    }

    /// Mark as epoll-driven (DRM mode). Call after registering Wayland fd with epoll.
    func setEpollDriven() {
        _epollDriven = true
    }

    /// Update scale factors at runtime (e.g. from Settings app DPI change).
    func updateScale(_ scale: Int, shellDpi: Double, fractionalScale: Double) {
        outputScale = max(scale, 1)
        self.shellDpi = max(shellDpi, 1.0)
        self.fractionalScale = fractionalScale
        enqueueCommand(.updateScale(scale: Int32(outputScale),
                                     fractional120: UInt32(fractionalScale * 120.0)))
    }

    /// Start the Wayland server. Call after engine is running.
    /// `refreshMhz`: the display's real refresh rate (wl_output.mode +
    /// wp_presentation refresh period); 0 falls back to 60 Hz.
    func start(screenWidth: Int, screenHeight: Int, scale: Int = 1, shellDpi: Double = 1.0,
               refreshMhz: Int = 0) {
        outputScale = max(scale, 1)
        self.shellDpi = max(shellDpi, 1.0)
        self.fractionalScale = max(shellDpi, 1.0)
        var config = WaylandServerConfig()
        config.display_width = Int32(screenWidth)
        config.display_height = Int32(screenHeight)
        config.refresh_mhz = refreshMhz > 0 ? Int32(refreshMhz) : 60000
        config.scale = Int32(scale)

        server = wayland_server_create(&config)
        guard let server = server else { return }

        // The shell usually runs as root (DRM master) while clients run as
        // the login user. AppArmor's wayland interface rule is
        // owner-qualified (`owner /run/user/*/wayland-* rw`), so a
        // root-owned socket is unreachable from confined user apps (snap
        // browsers) even though its mode bits allow it. Hand the socket to
        // the runtime dir's owner so user-session clients can connect.
        if getuid() == 0, let name = socketName {
            let xdg = LoginUser.runtimeDir
            var st = stat()
            if stat(xdg, &st) == 0, st.st_uid != 0 {
                _ = chown(xdg + "/" + name, st.st_uid, st.st_gid)
            }
        }

        wayland_server_update_scale(server, Int32(outputScale), UInt32(fractionalScale * 120.0))

        // Create wakeup pipe for UI→platform command delivery
        var pipeFds: [Int32] = [0, 0]
        if pipe(&pipeFds) == 0 {
            wakeupReadFd = pipeFds[0]
            wakeupWriteFd = pipeFds[1]
            let fl0 = fcntl(wakeupReadFd, F_GETFL, 0)
            fcntl(wakeupReadFd, F_SETFL, fl0 | O_NONBLOCK)
            let fl1 = fcntl(wakeupWriteFd, F_GETFL, 0)
            fcntl(wakeupWriteFd, F_SETFL, fl1 | O_NONBLOCK)
        }

        let ctx = Unmanaged.passUnretained(self).toOpaque()

        wayland_server_on_new_toplevel(server, { (ctx, surfaceId, clientId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleNewToplevel(surfaceId, clientId: clientId)
        }, ctx)

        wayland_server_on_surface_commit(server, { (ctx, surfaceId, fd, w, h, stride, fourcc, modifier, firstCommit, bufferScale) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleSurfaceCommit(surfaceId, fd: fd, width: Int(w), height: Int(h),
                                     stride: Int(stride), fourcc: UInt32(fourcc),
                                     modifier: modifier, firstCommit: firstCommit != 0,
                                     bufferScale: Int(bufferScale))
        }, ctx)

        // Software clients (wl_shm). Without this the compositor's SHM branch
        // finds a NULL callback and silently drops every frame, so the client
        // attaches, damages, commits and gets its buffers released — while the
        // window composites as nothing at all.
        wayland_server_on_shm_surface_commit(server, { (ctx, surfaceId, pixels, w, h, stride, format, firstCommit, bufferScale, keepAlpha) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            guard let pixels = pixels else { return }
            this.handleShmSurfaceCommit(surfaceId, pixels: pixels,
                                        width: Int(w), height: Int(h), stride: Int(stride),
                                        format: format, firstCommit: firstCommit != 0,
                                        bufferScale: Int(bufferScale),
                                        keepAlpha: keepAlpha != 0)
        }, ctx)

        wayland_server_on_toplevel_destroy(server, { (ctx, surfaceId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleToplevelDestroy(surfaceId)
        }, ctx)

        wayland_server_on_client_destroy(server, { (ctx, clientId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleClientDestroy(clientId)
        }, ctx)

        wayland_server_on_text_input_state(server, { (ctx, surfaceId, enabled, x, y, w, h) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleTextInputState(surfaceId, enabled: enabled != 0,
                                      x: x, y: y, w: w, h: h)
        }, ctx)

        wayland_server_on_title_changed(server, { (ctx, surfaceId, title) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            guard let title = title else { return }
            this.handleTitleChanged(surfaceId, title: String(cString: title))
        }, ctx)

        // Declared in wayland_server.h and fired by wayland_xdg_shell.c since
        // the compositor was written — but never registered here, so every
        // window's app_id was thrown away and the dock had to guess from
        // titles. Same failure shape as the wl_shm commit callback: complete C
        // plumbing, no Swift setter, silent.
        wayland_server_on_app_id_changed(server, { (ctx, surfaceId, appId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            guard let appId = appId else { return }
            this.handleAppIdChanged(surfaceId, appId: String(cString: appId))
        }, ctx)

        wayland_server_on_new_popup(server, { (ctx, surfaceId, parentSurfaceId, x, y, w, h) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleNewPopup(surfaceId, parentSurfaceId: parentSurfaceId,
                                 x: Int(x), y: Int(y), width: Int(w), height: Int(h))
        }, ctx)

        wayland_server_on_popup_destroy(server, { (ctx, surfaceId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handlePopupDestroy(surfaceId)
        }, ctx)

        wayland_server_on_window_geometry(server, { (ctx, surfaceId, x, y, w, h) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleWindowGeometry(surfaceId, x: Int(x), y: Int(y),
                                       width: Int(w), height: Int(h))
        }, ctx)

        wayland_server_on_popup_repositioned(server, { (ctx, surfaceId, x, y, w, h) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.pendingEvents.withLock { $0.append(.popupRepositioned(
                surfaceId: surfaceId, x: Int(x), y: Int(y), width: Int(w), height: Int(h))) }
            this._needsFrame = true
        }, ctx)

        wayland_server_on_toplevel_parent(server, { (ctx, surfaceId, parentId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.pendingEvents.withLock { $0.append(.toplevelParent(
                surfaceId: surfaceId, parentId: parentId)) }
            this._needsFrame = true
        }, ctx)

        wayland_server_on_toplevel_size_hints(server, { (ctx, surfaceId, minW, minH, maxW, maxH) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.pendingEvents.withLock { $0.append(.sizeHints(
                surfaceId: surfaceId, minW: minW, minH: minH, maxW: maxW, maxH: maxH)) }
            this._needsFrame = true
        }, ctx)

        // Subsurfaces: placed before their first buffer arrives (the commit
        // callbacks above need a texture keyed on the id by then).
        wayland_server_on_subsurface_placed(server, { (ctx, surfaceId, toplevelId, x, y, z, acceptsInput) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.pendingEvents.withLock { $0.append(.subsurfacePlaced(
                surfaceId: surfaceId, toplevelId: toplevelId, x: x, y: y, z: z,
                acceptsInput: acceptsInput != 0)) }
            this._needsFrame = true
        }, ctx)
        wayland_server_on_subsurface_unmapped(server, { (ctx, surfaceId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.pendingEvents.withLock { $0.append(.subsurfaceUnmapped(surfaceId: surfaceId)) }
            this._needsFrame = true
        }, ctx)

        wayland_server_on_fullscreen_request(server, { (ctx, surfaceId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleFullscreenRequest(surfaceId)
        }, ctx)

        wayland_server_on_unfullscreen_request(server, { (ctx, surfaceId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleUnfullscreenRequest(surfaceId)
        }, ctx)

        wayland_server_on_cursor_shape(server, { (ctx, shape) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleCursorShape(shape)
        }, ctx)

        wayland_server_on_move_request(server, { (ctx, surfaceId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.moveRequest(surfaceId: surfaceId))
        }, ctx)

        wayland_server_on_interactive_resize_request(server, { (ctx, surfaceId, edges) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.interactiveResizeRequest(surfaceId: surfaceId, edges: edges))
        }, ctx)

        wayland_server_on_toplevel_request(server, { (ctx, surfaceId, request) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.toplevelRequest(surfaceId: surfaceId, request: request))
        }, ctx)

        wayland_server_on_new_layer_surface(server, { (ctx, surfaceId, info) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            guard let info = info else { return }
            this.queueEvent(.newLayerSurface(surfaceId: surfaceId, info: LayerSurfaceInfo(info.pointee)))
        }, ctx)

        wayland_server_on_layer_surface_changed(server, { (ctx, surfaceId, info) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            guard let info = info else { return }
            this.queueEvent(.layerSurfaceChanged(surfaceId: surfaceId, info: LayerSurfaceInfo(info.pointee)))
        }, ctx)

        wayland_server_on_layer_surface_destroy(server, { (ctx, surfaceId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.layerSurfaceDestroy(surfaceId: surfaceId))
        }, ctx)

        wayland_server_on_surface_alpha(server, { (ctx, surfaceId, alpha) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.surfaceAlpha(surfaceId: surfaceId, alpha: alpha))
        }, ctx)

        wayland_server_on_toplevel_position_request(server, { (ctx, surfaceId, outputIndex, x, y) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.toplevelPositionRequest(surfaceId: surfaceId, outputIndex: outputIndex,
                                                     x: x, y: y))
        }, ctx)

        wayland_server_on_system_bell(server, { (ctx, surfaceId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.systemBell(surfaceId: surfaceId))
        }, ctx)

        wayland_server_on_shortcuts_inhibit(server, { (ctx, surfaceId, inhibited) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.shortcutsInhibit(surfaceId: surfaceId, inhibited: inhibited != 0))
        }, ctx)

        wayland_server_on_session_lock(server, { (ctx, locked) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.sessionLock(locked: locked != 0))
        }, ctx)

        wayland_server_on_workspace_request(server, { (ctx, id, request, name) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.workspaceRequest(id: id, request: request,
                                              name: name.map { String(cString: $0) } ?? ""))
        }, ctx)

        wayland_server_on_surface_blur(server, { (ctx, surfaceId, rects, count) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            var flat: [Int32] = []
            if let rects = rects, count > 0 {
                flat = Array(UnsafeBufferPointer(start: rects, count: Int(count) * 4))
            }
            this.queueEvent(.surfaceBlur(surfaceId: surfaceId, rects: flat))
        }, ctx)

        wayland_server_on_virtual_pointer(server, { (ctx, outputIndex, hasAbs, ax, ay, dx, dy,
                                                     buttons, wheelDx, wheelDy) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.virtualPointer(outputIndex: Int(outputIndex), hasAbs: hasAbs != 0,
                                            ax: ax, ay: ay, dx: dx, dy: dy,
                                            buttons: Int64(buttons),
                                            wheelDx: wheelDx, wheelDy: wheelDy))
        }, ctx)

        wayland_server_on_virtual_key(server, { (ctx, evdev, keysym, utf8, pressed) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.virtualKey(evdev: evdev, keysym: keysym,
                                        text: utf8.map { String(cString: $0) } ?? "",
                                        pressed: pressed != 0))
        }, ctx)

        wayland_server_on_pointer_constraint(server, { (ctx, surfaceId, lock, active, hasHint, hx, hy) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.pointerConstraint(surfaceId: surfaceId, lock: lock != 0, active: active != 0,
                                               hintX: hasHint != 0 ? hx : nil,
                                               hintY: hasHint != 0 ? hy : nil))
        }, ctx)

        wayland_server_on_pointer_warp(server, { (ctx, surfaceId, x, y) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.pointerWarp(surfaceId: surfaceId, x: x, y: y))
        }, ctx)

        wayland_server_on_drag_icon(server, { (ctx, surfaceId, active) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.dragIcon(surfaceId: surfaceId, active: active != 0))
        }, ctx)

        wayland_server_on_toplevel_drag(server, { (ctx, surfaceId, xOff, yOff, active) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.toplevelDrag(surfaceId: surfaceId, xOff: xOff, yOff: yOff,
                                          active: active != 0))
        }, ctx)

        wayland_server_on_output_config(server, { (ctx, configId, hostScale) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.outputConfig(configId: configId, hostScale: hostScale))
        }, ctx)

        // Screencopy stays on the platform thread: the capture is read out
        // of the engine on a worker and answered through the command queue.
        wayland_server_on_screencopy_request(server, { (ctx, frameId, outputIndex, x, y, w, h) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleScreencopyRequest(frameId: frameId, outputIndex: outputIndex,
                                         x: x, y: y, w: w, h: h)
        }, ctx)
    }

    /// Queue an event from a platform-thread C callback for UI-thread tick().
    private func queueEvent(_ event: WaylandEvent) {
        pendingEvents.withLock { $0.append(event) }
        _needsFrame = true
    }

    func stop() {
        if let server = server {
            wayland_server_destroy(server)
            self.server = nil
        }
        if wakeupReadFd >= 0 { Glibc.close(wakeupReadFd); wakeupReadFd = -1 }
        if wakeupWriteFd >= 0 { Glibc.close(wakeupWriteFd); wakeupWriteFd = -1 }
    }

    var serverFd: Int {
        guard let server = server else { return -1 }
        return Int(wayland_server_get_fd(server))
    }

    var socketName: String? {
        guard let server = server else { return nil }
        return String(cString: wayland_server_get_socket_name(server))
    }

    /// Also listen for clients in `dir` (its basename kept the same as the
    /// primary socket). Confined snaps can only reach the compositor at the
    /// standard /run/user/<uid>/ path — the App Center itself is one — so the
    /// shell exposes a socket there in addition to its private one. Returns
    /// true on success.
    @discardableResult
    func exposeExtraSocket(inDir dir: String) -> Bool {
        guard let server = server, let name = socketName else { return false }
        return wayland_server_add_socket_at(server, "\(dir)/\(name)") == 0
    }

    /// True while any client holds a zwp_idle_inhibitor_v1 — Chrome or
    /// Firefox playing video, a slideshow, a player. The shell's screensaver
    /// idle timer treats this as ongoing activity, so a film watched without
    /// touching the mouse doesn't get covered up.
    var idleInhibited: Bool {
        guard let server = server else { return false }
        return wayland_server_idle_inhibited(server) > 0
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - Platform Thread: Dispatch + Command Execution
    // ═══════════════════════════════════════════════════════════════════════

    /// Called from DRM epoll when the Wayland fd is readable.
    /// Dispatches protocol events (C callbacks queue into pendingEvents).
    func dispatchEvents() {
        guard let server = server else { return }
        _needsFrame = false
        executePendingCommands()
        wayland_server_dispatch(server)
        if _needsFrame {
            FlutterEngineScheduleFrame(engine)
        }
    }

    /// Called from the DRM per-output present callback (platform thread —
    /// the same thread that dispatches the Wayland event loop) when a page
    /// flip lands on `outputId`. Drives the frame callbacks + presentation
    /// feedback of the clients ON that output off its real vsync — a client
    /// on the 30Hz panel is paced at 30, one on the 90Hz panel at 90.
    func handlePresent(flipTimeNs: UInt64, refreshNs: UInt32, outputId: Int) {
        guard let server = server else { return }
        wayland_server_on_present(server, flipTimeNs, refreshNs,
                                  1 << outputBit(forId: outputId))
    }

    /// Called from DRM epoll when the wakeup pipe is readable.
    /// Drains command queue from the UI thread.
    func drainWakeupPipe() {
        // Consume wakeup bytes
        if wakeupReadFd >= 0 {
            var buf = [UInt8](repeating: 0, count: 64)
            while Glibc.read(wakeupReadFd, &buf, buf.count) > 0 {}
        }
        executePendingCommands()
    }

    /// Execute queued commands on the platform thread.
    private func executePendingCommands() {
        let commands = pendingCommands.take([])
        guard !commands.isEmpty else { return }
        guard let server = server else { return }
        for cmd in commands {
            switch cmd {
            case .configureToplevel(let surfaceId, let w, let h):
                wayland_server_configure_toplevel(server, surfaceId, w, h)
            case .configureToplevelNatural(let surfaceId):
                wayland_server_configure_toplevel_natural(server, surfaceId)
            case .breakPointerConstraints:
                wayland_server_break_pointer_constraints(server)
            case .closeToplevel(let surfaceId):
                wayland_server_close_toplevel(server, surfaceId)
            case .flushClients:
                wayland_server_flush_clients(server)
            case .updateScale(let scale, let fractional120):
                wayland_server_update_scale(server, scale, fractional120)
            case .setOutputs(var outputs):
                wayland_server_set_outputs(server, &outputs,
                                           Int32(outputs.count))
            case .setSurfaceOutputs(let surfaceId, let mask, let paceMask):
                wayland_server_surface_set_outputs(server, surfaceId, mask,
                                                   paceMask)
            case .setSurfaceThrottle(let surfaceId, let intervalMs):
                wayland_server_set_surface_throttle(server, surfaceId, intervalMs)
            case .textInputCommit(let text):
                _ = wayland_server_text_input_commit_string(server, text)
            case .textInputPreedit(let text, let cursor):
                _ = wayland_server_text_input_preedit(server, text, cursor)
            case .setToplevelState(let surfaceId, let states):
                wayland_server_set_toplevel_state(server, surfaceId, states)
            case .screencopyDeliver(let frameId, let pixels, let stride):
                wayland_server_screencopy_deliver(server, frameId, pixels, stride, 0)
                pixels.deallocate()
            case .screencopyFail(let frameId):
                wayland_server_screencopy_fail(server, frameId)
            case .toplevelPosition(let surfaceId, let x, let y):
                wayland_server_toplevel_position(server, surfaceId, x, y)
            case .toplevelPositionFailed(let surfaceId):
                wayland_server_toplevel_position_failed(server, surfaceId)
            case .setWorkArea(let outputIndex, let x, let y, let w, let h):
                wayland_server_set_work_area(server, outputIndex, x, y, w, h)
            case .setFrameExtents(let top, let bottom, let left, let right):
                wayland_server_set_frame_extents(server, top, bottom, left, right)
            case .setWorkspaces(let list):
                var descs = list.map { entry -> WaylandWorkspaceDesc in
                    var d = WaylandWorkspaceDesc()
                    d.id = entry.id
                    d.active = entry.active ? 1 : 0
                    withUnsafeMutableBytes(of: &d.name) { buf in
                        let bytes = Array(entry.name.utf8.prefix(buf.count - 1))
                        for (i, b) in bytes.enumerated() { buf[i] = b }
                        buf[bytes.count] = 0
                    }
                    return d
                }
                wayland_server_set_workspaces(server, &descs, Int32(descs.count))
            case .outputConfigResult(let configId, let ok):
                wayland_server_output_config_result(server, configId, ok ? 1 : 0)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - UI Thread: Event Processing
    // ═══════════════════════════════════════════════════════════════════════

    /// Called from FrameCallbackScheduler on the UI thread.
    /// Drains queued events from the platform thread and processes them.
    func tick() {
        // In GLFW mode (no epoll), dispatch + execute commands here.
        if !_epollDriven, let server = server {
            executePendingCommands()
            wayland_server_dispatch(server)
        }

        let events = pendingEvents.take([])
        guard !events.isEmpty else { return }

        for event in events {
            switch event {
            case .newToplevel(let surfaceId, let clientId):
                processNewToplevel(surfaceId, clientId: clientId)
            case .surfaceCommit(let surfaceId, let fd, let width, let height,
                                let stride, let fourcc, let modifier,
                                let firstCommit, let bufferScale,
                                let vpW, let vpH):
                processSurfaceCommit(surfaceId, fd: fd, width: width, height: height,
                                     stride: stride, fourcc: fourcc, modifier: modifier,
                                     firstCommit: firstCommit, bufferScale: bufferScale,
                                     viewportWidth: vpW, viewportHeight: vpH)
            case .shmSurfaceCommit(let surfaceId, let pixels, let width, let height,
                                   let format, let firstCommit, let bufferScale,
                                   let vpW, let vpH):
                processShmSurfaceCommit(surfaceId, pixels: pixels,
                                        width: width, height: height, format: format,
                                        firstCommit: firstCommit, bufferScale: bufferScale,
                                        viewportWidth: vpW, viewportHeight: vpH)
            case .toplevelDestroy(let surfaceId):
                processToplevelDestroy(surfaceId)
            case .clientDestroy(let clientId):
                onClientDestroyed?(clientId)
            case .titleChanged(let surfaceId, let title):
                processTitleChanged(surfaceId, title: title)
            case .appIdChanged(let surfaceId, let appId):
                processAppIdChanged(surfaceId, appId: appId)
            case .newPopup(let surfaceId, let parentSurfaceId, let x, let y, let w, let h):
                processNewPopup(surfaceId, parentSurfaceId: parentSurfaceId,
                                x: x, y: y, width: w, height: h)
            case .popupDestroy(let surfaceId):
                processPopupDestroy(surfaceId)
            case .windowGeometry(let surfaceId, let x, let y, let w, let h):
                surfaceGeometry[surfaceId] = (x, y, w, h)
            case .sizeHints(let surfaceId, let minW, let minH, let maxW, let maxH):
                if let windowId = surfaceWindows[surfaceId] {
                    let f = fractionalScale / shellDpi
                    onWindowSizeHints?(windowId, Double(minW) * f, Double(minH) * f,
                                       Double(maxW) * f, Double(maxH) * f)
                }
            case .popupRepositioned(let surfaceId, let x, let y, _, _):
                pendingPopupMoves[surfaceId] = (x, y)
            case .toplevelParent(let surfaceId, let parentId):
                if let windowId = surfaceWindows[surfaceId] {
                    let parent = parentId != 0 ? surfaceWindows[parentId] : nil
                    onWindowParent?(windowId, parent, surfaceSizes[surfaceId] != nil)
                }
            case .subsurfacePlaced(let surfaceId, let toplevelId, let x, let y, let z, let acceptsInput):
                processSubsurfacePlaced(surfaceId, toplevelId: toplevelId,
                                        x: Int(x), y: Int(y), z: Int(z), acceptsInput: acceptsInput)
            case .subsurfaceUnmapped(let surfaceId):
                processSubsurfaceUnmapped(surfaceId)
            case .fullscreenRequest(let surfaceId):
                processFullscreenRequest(surfaceId)
            case .unfullscreenRequest(let surfaceId):
                processUnfullscreenRequest(surfaceId)
            case .cursorShape(let shape):
                processCursorShape(shape)
            case .moveRequest(let surfaceId):
                if let windowId = surfaceWindows[surfaceId] {
                    onMoveRequest?(windowId)
                }
            case .interactiveResizeRequest(let surfaceId, let edges):
                if let windowId = surfaceWindows[surfaceId] {
                    onInteractiveResizeRequest?(windowId, edges)
                }
            case .textInputState(let surfaceId, let enabled,
                                 let x, let y, let w, let h):
                if let windowId = surfaceWindows[surfaceId] {
                    onTextInputState?(windowId, enabled,
                                      Double(x), Double(y),
                                      Double(w), Double(h))
                }
            case .toplevelRequest(let surfaceId, let request):
                if let windowId = surfaceWindows[surfaceId],
                   !popupSurfaceIds.contains(surfaceId),
                   !layerSurfaceIds.contains(surfaceId) {
                    onToplevelRequest?(windowId, request)
                }
            case .newLayerSurface(let surfaceId, let info):
                processNewLayerSurface(surfaceId, info: info)
            case .layerSurfaceChanged(let surfaceId, let info):
                if layerSurfaceIds.contains(surfaceId) {
                    onLayerSurfaceChanged?(surfaceId, info)
                }
            case .layerSurfaceDestroy(let surfaceId):
                processLayerSurfaceDestroy(surfaceId)
            case .surfaceAlpha(let surfaceId, let alpha):
                onSurfaceAlpha?(surfaceId, alpha)
            case .toplevelPositionRequest(let surfaceId, let outputIndex, let x, let y):
                if let windowId = surfaceWindows[surfaceId],
                   !popupSurfaceIds.contains(surfaceId),
                   !layerSurfaceIds.contains(surfaceId) {
                    onToplevelPositionRequest?(windowId, Int(outputIndex), Int(x), Int(y))
                } else {
                    enqueueCommand(.toplevelPositionFailed(surfaceId: surfaceId))
                }
            case .systemBell(let surfaceId):
                onSystemBell?(surfaceId == 0 ? nil : surfaceWindows[surfaceId])
            case .shortcutsInhibit(let surfaceId, let inhibited):
                if inhibited {
                    shortcutsInhibitedSurfaces.insert(surfaceId)
                } else {
                    shortcutsInhibitedSurfaces.remove(surfaceId)
                }
            case .sessionLock(let locked):
                onSessionLock?(locked)
            case .workspaceRequest(let id, let request, let name):
                onWorkspaceRequest?(id, request, name)
            case .surfaceBlur(let surfaceId, let rects):
                // A blurred surface is seen through: its alpha must survive
                // the dma-buf import, which otherwise goes opaque for toplevels.
                if let textureId = surfaceTextures[surfaceId] {
                    textureRegistry.setKeepsAlpha(id: textureId, !rects.isEmpty)
                }
                onSurfaceBlur?(surfaceId, rects)
            case .virtualPointer(let outputIndex, let hasAbs, let ax, let ay, let dx, let dy,
                                 let buttons, let wheelDx, let wheelDy):
                onVirtualPointer?(outputIndex, hasAbs, ax, ay, dx, dy, buttons, wheelDx, wheelDy)
            case .virtualKey(let evdev, let keysym, let text, let pressed):
                onVirtualKey?(evdev, keysym, text, pressed)
            case .pointerWarp(let surfaceId, let x, let y):
                onPointerWarp?(surfaceId, x * surfaceToLogical, y * surfaceToLogical)
            case .pointerConstraint(let surfaceId, let lock, let active, let hx, let hy):
                if lock { lockedSurface = active ? surfaceId : (lockedSurface == surfaceId ? nil : lockedSurface) }
                if let windowId = surfaceWindows[surfaceId] {
                    var hint: Offset? = nil
                    if let hx = hx, let hy = hy {
                        hint = Offset(hx * surfaceToLogical, hy * surfaceToLogical)
                    }
                    onPointerConstraint?(windowId, surfaceId, lock, active, hint)
                }
            case .dragIcon(let surfaceId, let active):
                processDragIcon(surfaceId, active: active)
            case .toplevelDrag(let surfaceId, let xOff, let yOff, let active):
                if let windowId = surfaceWindows[surfaceId],
                   !popupSurfaceIds.contains(surfaceId), !layerSurfaceIds.contains(surfaceId) {
                    onToplevelDrag?(windowId, Int(xOff), Int(yOff), active)
                }
            case .outputConfig(let configId, let hostScale):
                if let handler = onOutputConfig {
                    handler(configId, hostScale)
                } else {
                    outputConfigResult(configId: configId, ok: false)
                }
            }
        }
    }

    // ─── Drag-and-drop (UI thread) ───────────────────────────────────────

    /// The drag's state: begins with its icon surface (or none), ends with
    /// active = false. The icon is a texture of its own, drawn by the
    /// shell at the pointer like a popup that follows it.
    private func processDragIcon(_ surfaceId: UInt32, active: Bool) {
        if let old = dragIconSurfaceId, old != surfaceId || !active {
            dragIconSurfaceId = nil
            popupSurfaceIds.remove(old)
            surfaceWindows.removeValue(forKey: old)
            if let textureId = surfaceTextures.removeValue(forKey: old) {
                textureRegistry.unregisterTexture(engine: engine, id: textureId)
            }
            surfaceSizes.removeValue(forKey: old)
            surfaceBufferScales.removeValue(forKey: old)
            onDragIcon?(nil, 0)
        }
        if dragActive != active {
            dragActive = active
            onDragStateChanged?(active)
        }
        guard active, surfaceId != 0, dragIconSurfaceId != surfaceId else { return }
        let textureId = textureRegistry.registerTexture(engine: engine)
        textureRegistry.markAsWaylandSurface(id: textureId)
        textureRegistry.markAsPopupSurface(id: textureId)   // alpha kept
        surfaceTextures[surfaceId] = textureId
        popupSurfaceIds.insert(surfaceId)
        dragIconSurfaceId = surfaceId
        let iconId = "dragicon-\(surfaceId)"
        surfaceWindows[surfaceId] = iconId
        onDragIcon?(iconId, Int(textureId))
    }

    /// The drag router's pointer: enter/motion/leave/button on the surface
    /// under the pointer while a drag is on (surfaceId 0 = over nothing,
    /// which leaves the last surface).
    func sendDragPointer(surfaceId: UInt32, phase: Int32, x: Double, y: Double) {
        guard let server = server else { return }
        if surfaceId == 0 {
            if pointerFocusSurface != 0 {
                wayland_server_pointer_leave(server, pointerFocusSurface)
                pointerFocusSurface = 0
            }
            return
        }
        _sendPointer(surfaceId: surfaceId, phase: phase, x: x, y: y, buttons: 0)
    }

    /// The drag's button came up over nothing a client owns: end it there.
    func pointerGlobalRelease() {
        guard let server = server else { return }
        if pointerFocusSurface != 0 {
            wayland_server_pointer_leave(server, pointerFocusSurface)
            pointerFocusSurface = 0
        }
        wayland_server_pointer_global_release(server)
    }

    /// ext_workspace_v1: the shell's spaces, pushed when they change.
    func setWorkspaces(_ list: [WaylandWorkspaceEntry]) {
        if lastWorkspaces == list { return }
        lastWorkspaces = list
        enqueueCommand(.setWorkspaces(list: list))
        enqueueCommand(.flushClients)
    }

    /// wlr-output-management: the answer to an apply.
    func outputConfigResult(configId: UInt32, ok: Bool) {
        enqueueCommand(.outputConfigResult(configId: configId, ok: ok))
        enqueueCommand(.flushClients)
    }

    // ─── Layer surfaces (UI thread) ──────────────────────────────────────

    private func processNewLayerSurface(_ surfaceId: UInt32, info: LayerSurfaceInfo) {
        if let old = surfaceTextures[surfaceId] {
            textureRegistry.unregisterTexture(engine: engine, id: old)
        }
        surfaceSizes.removeValue(forKey: surfaceId)
        surfaceBufferScales.removeValue(forKey: surfaceId)
        let textureId = textureRegistry.registerTexture(engine: engine)
        textureRegistry.markAsWaylandSurface(id: textureId)
        // Like a popup: its own surface, alpha kept (a bar is often
        // translucent), no window geometry cropping.
        textureRegistry.markAsPopupSurface(id: textureId)
        surfaceTextures[surfaceId] = textureId
        layerSurfaceIds.insert(surfaceId)
        surfaceWindows[surfaceId] = "layer-\(surfaceId)"
        onNewLayerSurface?(surfaceId, Int(textureId), info)
    }

    private func processLayerSurfaceDestroy(_ surfaceId: UInt32) {
        guard layerSurfaceIds.remove(surfaceId) != nil else { return }
        surfaceWindows.removeValue(forKey: surfaceId)
        if let textureId = surfaceTextures.removeValue(forKey: surfaceId) {
            textureRegistry.unregisterTexture(engine: engine, id: textureId)
        }
        surfaceSizes.removeValue(forKey: surfaceId)
        surfaceBufferScales.removeValue(forKey: surfaceId)
        onLayerSurfaceDestroyed?(surfaceId)
    }

    /// True for a surface with the layer-shell role.
    func isLayerSurface(_ surfaceId: UInt32) -> Bool {
        return layerSurfaceIds.contains(surfaceId)
    }

    /// True while the surface's client holds a keyboard-shortcuts inhibitor.
    func shortcutsInhibited(surfaceId: UInt32) -> Bool {
        return shortcutsInhibitedSurfaces.contains(surfaceId)
    }

    // ─── Window state (UI thread) ────────────────────────────────────────

    /// Push the shell's state bits for this surface's window, if they
    /// changed since the last push. Returns true when a command went out.
    @discardableResult
    func syncToplevelState(surfaceId: UInt32) -> Bool {
        guard server != nil, let windowId = surfaceWindows[surfaceId],
              !popupSurfaceIds.contains(surfaceId),
              !layerSurfaceIds.contains(surfaceId),
              let provider = stateProvider else { return false }
        let states = provider(windowId)
        if surfaceStateCache[surfaceId] == states { return false }
        surfaceStateCache[surfaceId] = states
        enqueueCommand(.setToplevelState(surfaceId: surfaceId, states: states))
        return true
    }

    func syncToplevelState(windowId: String) {
        guard let sid = surfaceId(forWindowId: windowId) else { return }
        if syncToplevelState(surfaceId: sid) { enqueueCommand(.flushClients) }
    }

    /// Every Wayland window at once — called after a build, which is where
    /// focus, minimize and maximize changes have all settled.
    func syncAllToplevelStates() {
        var any = false
        for sid in surfaceWindows.keys {
            if syncToplevelState(surfaceId: sid) { any = true }
        }
        if any { enqueueCommand(.flushClients) }
    }

    // ─── Zones (UI thread) ──────────────────────────────────────────────

    /// Where a window's frame sits relative to its output's work area, for
    /// xx-zones. Diff-guarded; cheap to call for every window every build.
    func reportToplevelPosition(windowId: String, x: Int, y: Int) {
        guard let sid = surfaceId(forWindowId: windowId) else { return }
        let p = (Int32(x), Int32(y))
        if let c = surfacePositionCache[sid], c.0 == p.0, c.1 == p.1 { return }
        surfacePositionCache[sid] = p
        publishOrigin(surfaceId: sid, x: Int(p.0), y: Int(p.1))
        enqueueCommand(.toplevelPosition(surfaceId: sid, x: p.0, y: p.1))
        enqueueCommand(.flushClients)
    }

    /// Tells the client's screen-reader bridge where its window is: a one-line file
    /// `$XDG_RUNTIME_DIR/starling-window-origin/<pid>` ("x y"), which the client reads
    /// (AtspiAccessibility.windowOrigin). A Wayland client cannot know its own position.
    private func publishOrigin(surfaceId: UInt32, x: Int, y: Int) {
        guard let pid = surfacePids[surfaceId], let dir = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"] else { return }
        let folder = dir + "/starling-window-origin"
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try? "\(x) \(y)\n".write(toFile: folder + "/\(pid)", atomically: true, encoding: .utf8)
    }

    func reportToplevelPositionFailed(windowId: String) {
        guard let sid = surfaceId(forWindowId: windowId) else { return }
        enqueueCommand(.toplevelPositionFailed(surfaceId: sid))
        enqueueCommand(.flushClients)
    }

    /// An output's work area (its rect less reserved strips), global logical.
    func setWorkArea(outputIndex: Int, x: Int, y: Int, width: Int, height: Int) {
        let v = (Int32(x), Int32(y), Int32(width), Int32(height))
        let key = Int32(outputIndex)
        if let c = workAreaCache[key], c == v { return }
        workAreaCache[key] = v
        enqueueCommand(.setWorkArea(outputIndex: key, x: v.0, y: v.1, w: v.2, h: v.3))
    }

    func setFrameExtents(top: Int, bottom: Int, left: Int, right: Int) {
        enqueueCommand(.setFrameExtents(top: Int32(top), bottom: Int32(bottom),
                                        left: Int32(left), right: Int32(right)))
    }

    // ─── Screencopy (platform thread → worker → command queue) ──────────

    /// grim & co. asked for the presented pixels of an output region. The
    /// engine keeps a CPU mirror of the presented desktop for the X server's
    /// GetImage; arming it makes the next few presents refill the mirror
    /// (the shell's frame pump forces those presents on an idle desktop),
    /// and the read after that is a fresh frame. Only the host view has a
    /// mirror, so a secondary output's request fails honestly.
    private func handleScreencopyRequest(frameId: UInt32, outputIndex: Int32,
                                         x: Int32, y: Int32, w: Int32, h: Int32) {
        #if os(Linux)
        guard outputIndex == 0, let view = drmViewHandle, w > 0, h > 0 else {
            enqueueCommand(.screencopyFail(frameId: frameId))
            enqueueCommand(.flushClients)
            return
        }
        screencopyInFlight.withLock { $0 += 1 }
        onFramePumpNeedChanged?()
        fl_drm_view_arm_capture(view)
        let job = ScreencopyJob(frameId: frameId, view: view, x: x, y: y, w: w, h: h)
        scheduleScreencopyStep(job)
        #else
        enqueueCommand(.screencopyFail(frameId: frameId))
        #endif
    }

    #if os(Linux)
    /// One screencopy in flight: the arm sets a four-present countdown, and
    /// once it has run out the mirror holds a frame made after the request.
    private final class ScreencopyJob {
        let frameId: UInt32
        let view: OpaquePointer
        let x: Int32, y: Int32, w: Int32, h: Int32
        let started = DispatchTime.now()
        let deadline = DispatchTime.now() + .milliseconds(2000)
        var armedPresents = false
        init(frameId: UInt32, view: OpaquePointer, x: Int32, y: Int32, w: Int32, h: Int32) {
            self.frameId = frameId; self.view = view
            self.x = x; self.y = y; self.w = w; self.h = h
        }
    }

    private func scheduleScreencopyStep(_ job: ScreencopyJob) {
        // Same laundering the shell uses for its own background work: the
        // closure touches nothing but the job and the command queue's lock.
        let work: () -> Void = { [self] in self.screencopyStep(job) }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + .milliseconds(16),
            execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
    }

    private func screencopyStep(_ job: ScreencopyJob) {
        if !job.armedPresents, fl_drm_view_capture_active() == 0 {
            job.armedPresents = true
        }
        guard job.armedPresents || DispatchTime.now() >= job.deadline else {
            scheduleScreencopyStep(job)
            return
        }
        let byteCount = Int(job.w) * Int(job.h) * 4
        let buf = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 16)
        let ok = fl_drm_view_read_capture(job.x, job.y, job.w, job.h,
                                          buf.assumingMemoryBound(to: UInt8.self),
                                          Int32(byteCount))
        screencopyInFlight.withLock { $0 -= 1 }
        onFramePumpNeedChanged?()
        // A capture that waited out the deadline read whatever the mirror
        // held — possibly an old frame. Said in the log, because that is
        // indistinguishable from "the window was never drawn" from outside.
        let ms = (DispatchTime.now().uptimeNanoseconds - job.started.uptimeNanoseconds) / 1_000_000
        if !job.armedPresents || ms > 500 || ok == 0 {
            FileHandle.standardError.write(Data(
                "[screencopy] frame \(job.frameId): \(ok != 0 ? "read" : "no mirror") after \(ms) ms, presents \(job.armedPresents ? "seen" : "NOT seen (deadline)")\n".utf8))
        }
        if ok != 0 {
            enqueueCommand(.screencopyDeliver(frameId: job.frameId, pixels: buf, stride: job.w * 4))
        } else {
            buf.deallocate()
            enqueueCommand(.screencopyFail(frameId: job.frameId))
        }
        enqueueCommand(.flushClients)
    }
    #endif

    /// Map wp_cursor_shape_device_v1 shapes onto the DRM hardware cursor's
    /// available bitmaps. Anything without a matching bitmap falls back to
    /// the default arrow (the shell's own hover handlers restore shapes when
    /// the pointer returns to shell chrome).
    private func processCursorShape(_ shape: UInt32) {
        let mapped: CursorShape
        switch shape {
        case 9, 10:               // text, vertical_text
            mapped = .text
        case 4, 16, 17:           // pointer (hand), grab, grabbing
            mapped = .pointer
        case 19, 22, 27, 31:      // n_resize, s_resize, ns_resize, row_resize
            mapped = .resizeNS
        case 18, 25, 26, 30:      // e_resize, w_resize, ew_resize, col_resize
            mapped = .resizeEW
        case 20, 24, 28:          // ne_resize, sw_resize, nesw_resize
            mapped = .resizeNESW
        case 21, 23, 29:          // nw_resize, se_resize, nwse_resize
            mapped = .resizeNWSE
        default:
            mapped = .default
        }
        DesktopCursor.setShape(mapped)
    }

    // ─── Event Processors (UI thread) ───────────────────────────────────

    private func processNewToplevel(_ surfaceId: UInt32, clientId: UInt64) {
        let textureId = textureRegistry.registerTexture(engine: engine)
        textureRegistry.markAsWaylandSurface(id: textureId)
        surfaceTextures[surfaceId] = textureId

        // Peer pid, captured here while the surface is certainly alive. The
        // dock's Quit needs it to escalate past a client that ignores
        // xdg_toplevel.close, and looking it up later races the client's own
        // teardown — by the time a user picks Quit the surface may be gone.
        if let server = server {
            let pid = wayland_server_surface_pid(server, surfaceId)
            if pid > 0 { surfacePids[surfaceId] = pid }
        }
        surfaceClients[surfaceId] = clientId
        if let windowId = onNewWindow?(surfaceId, Int(textureId), "Wayland App", clientId) {
            surfaceWindows[surfaceId] = windowId
            // An app_id that arrived before the window existed.
            if let appId = surfaceAppIds[surfaceId] {
                onAppIdChanged?(windowId, appId)
            }
        }
    }

    /// Size/scale bookkeeping plus the resize and geometry notifications that
    /// every commit owes the shell, shared by the dma-buf and wl_shm paths.
    /// Returns the buffer dimensions capped to the viewport content area.
    @discardableResult
    private func applyCommitGeometry(_ surfaceId: UInt32, width: Int, height: Int,
                                     bufferScale: Int,
                                     viewportWidth vpW: Int,
                                     viewportHeight vpH: Int) -> (Int, Int) {
        let prevSize = surfaceSizes[surfaceId]
        let prevScale = surfaceBufferScales[surfaceId]
        surfaceSizes[surfaceId] = (width, height)
        surfaceBufferScales[surfaceId] = bufferScale

        let scale = max(bufferScale, 1)
        let effectiveScale = max(Double(scale), shellDpi)
        let hasViewport = vpW > 0 && vpH > 0

        // A subsurface: its size (the viewport's, or the buffer's in logical
        // px) goes to the shell with its place; nothing below applies.
        if subsurfaceParents[surfaceId] != nil {
            subsurfaceLogicalSizes[surfaceId] = hasViewport
                ? (vpW, vpH)
                : (Int(Double(width) / effectiveScale), Int(Double(height) / effectiveScale))
            emitSubsurface(surfaceId)
        }

        // Notify shell of size changes
        let sizeChanged = prevSize.map { $0.0 != width || $0.1 != height } ?? true
        let scaleChanged = prevScale.map { $0 != bufferScale } ?? true
        let isLayer = layerSurfaceIds.contains(surfaceId)
        // A repositioned popup: this frame is the one drawn for the new
        // place, so the move lands with it, whatever the size did.
        if let move = pendingPopupMoves.removeValue(forKey: surfaceId),
           popupSurfaceIds.contains(surfaceId),
           let popupId = surfaceWindows[surfaceId] {
            let geo = surfaceGeometry[surfaceId]
            onPopupRepositioned?(popupId,
                                 Int(Double(width) / effectiveScale),
                                 Int(Double(height) / effectiveScale),
                                 Int(Double(geo?.x ?? 0) * fractionalScale / shellDpi),
                                 Int(Double(geo?.y ?? 0) * fractionalScale / shellDpi),
                                 move.x, move.y)
        } else if sizeChanged || scaleChanged {
            if let windowId = surfaceWindows[surfaceId] {
                let isPopup = popupSurfaceIds.contains(surfaceId)
                if isLayer {
                    onLayerSurfaceBufferResized?(surfaceId,
                                                 Int(Double(width) / effectiveScale),
                                                 Int(Double(height) / effectiveScale))
                } else if isPopup {
                    let logicalW = Int(Double(width) / effectiveScale)
                    let logicalH = Int(Double(height) / effectiveScale)
                    let geo = surfaceGeometry[surfaceId]
                    onPopupBufferResized?(windowId, logicalW, logicalH,
                                          Int(Double(geo?.x ?? 0) * fractionalScale / shellDpi),
                                          Int(Double(geo?.y ?? 0) * fractionalScale / shellDpi))
                } else if hasViewport {
                    onWindowBufferResized?(windowId, vpW, vpH)
                } else if let geo = surfaceGeometry[surfaceId] {
                    onWindowBufferResized?(windowId,
                                           Int(Double(geo.width) * fractionalScale / shellDpi),
                                           Int(Double(geo.height) * fractionalScale / shellDpi))
                } else {
                    onWindowBufferResized?(windowId,
                                           Int(Double(width) / effectiveScale),
                                           Int(Double(height) / effectiveScale))
                }
            }
        }

        // Emit geometry callback for toplevels
        if !popupSurfaceIds.contains(surfaceId), !isLayer,
           let windowId = surfaceWindows[surfaceId] {
            let bufLogW: Int
            let bufLogH: Int
            if hasViewport {
                bufLogW = vpW
                bufLogH = vpH
            } else {
                bufLogW = Int(Double(width) / effectiveScale)
                bufLogH = Int(Double(height) / effectiveScale)
            }
            let geo = surfaceGeometry[surfaceId]
            let gx = Int(Double(geo?.x ?? 0) * fractionalScale / shellDpi)
            let gy = Int(Double(geo?.y ?? 0) * fractionalScale / shellDpi)
            let gw = Int(Double(geo?.width ?? vpW) * fractionalScale / shellDpi)
            let gh = Int(Double(geo?.height ?? vpH) * fractionalScale / shellDpi)
            let cur = (gx, gy, gw, gh, bufLogW, bufLogH)
            let prev = lastEmittedGeometry[surfaceId]
            if prev == nil || prev!.x != cur.0 || prev!.y != cur.1
                || prev!.w != cur.2 || prev!.h != cur.3
                || prev!.bufW != cur.4 || prev!.bufH != cur.5 {
                lastEmittedGeometry[surfaceId] = (cur.0, cur.1, cur.2, cur.3, cur.4, cur.5)
                onWindowGeometryChanged?(windowId, gx, gy, gw, gh, bufLogW, bufLogH)
            }
        }

        // Cap import dimensions to viewport content area
        var importW = width
        var importH = height
        if hasViewport {
            let contentPixelW = Int(Double(vpW) * fractionalScale)
            let contentPixelH = Int(Double(vpH) * fractionalScale)
            if contentPixelW < width { importW = contentPixelW }
            if contentPixelH < height { importH = contentPixelH }
        }
        return (importW, importH)
    }

    /// Flush a throttled resize once the interval has elapsed.
    private func flushPendingResize(_ surfaceId: UInt32) {
        if let pending = pendingResize[surfaceId] {
            let now = DispatchTime.now().uptimeNanoseconds
            let last = lastResizeTime[surfaceId] ?? 0
            if now - last >= resizeIntervalNs {
                pendingResize.removeValue(forKey: surfaceId)
                lastResizeTime[surfaceId] = now
                syncToplevelState(surfaceId: surfaceId)
                enqueueCommand(.configureToplevel(surfaceId: surfaceId,
                                                   width: Int32(pending.width),
                                                   height: Int32(pending.height)))
                enqueueCommand(.flushClients)
            }
        }
    }

    private func processSurfaceCommit(_ surfaceId: UInt32, fd: Int32, width: Int, height: Int,
                                       stride: Int, fourcc: UInt32, modifier: UInt64,
                                       firstCommit: Bool, bufferScale: Int,
                                       viewportWidth vpW: Int, viewportHeight vpH: Int) {
        guard let textureId = surfaceTextures[surfaceId] else {
            // Surface already gone — we own the dup'd fd, don't leak it.
            if fd >= 0 { Glibc.close(fd) }
            return
        }

        // Read before applyCommitGeometry — it overwrites surfaceSizes.
        let prevSize = surfaceSizes[surfaceId]
        let (importW, importH) = applyCommitGeometry(surfaceId, width: width, height: height,
                                                     bufferScale: bufferScale,
                                                     viewportWidth: vpW, viewportHeight: vpH)

        // Import DMA-BUF. ownsFd: the fd is our dup (made at commit time on
        // the platform thread) — the registry closes it when it's replaced
        // or the texture is dropped.
        if firstCommit || prevSize == nil {
            textureRegistry.importDmaBuf(
                engine: engine, id: textureId,
                fd: fd, width: importW, height: importH,
                stride: stride, fourcc: fourcc,
                modifier: modifier, ownsFd: true
            )
        } else {
            textureRegistry.reimportDmaBuf(
                engine: engine, id: textureId,
                fd: fd, width: importW, height: importH,
                stride: stride, fourcc: fourcc,
                modifier: modifier, ownsFd: true
            )
        }

        flushPendingResize(surfaceId)
        FrameCallbackScheduler.shared.noteTextureUpdate(textureId)
    }

    /// wl_shm commit. `pixels` is this event's packed R,G,B,A copy, already
    /// swizzled and alpha-forced on the event-loop thread (see
    /// handleShmSurfaceCommit); the texture entry adopts it, or it is freed.
    private func processShmSurfaceCommit(_ surfaceId: UInt32,
                                          pixels: UnsafeMutableRawPointer,
                                          width: Int, height: Int, format: UInt32,
                                          firstCommit: Bool, bufferScale: Int,
                                          viewportWidth vpW: Int, viewportHeight vpH: Int) {
        _ = format
        guard let textureId = surfaceTextures[surfaceId] else {
            pixels.deallocate()
            return
        }

        applyCommitGeometry(surfaceId, width: width, height: height,
                            bufferScale: bufferScale,
                            viewportWidth: vpW, viewportHeight: vpH)

        textureRegistry.adoptPixelData(engine: engine, id: textureId,
                                       buffer: pixels, width: width, height: height)

        flushPendingResize(surfaceId)
        FrameCallbackScheduler.shared.noteTextureUpdate(textureId)
    }

    private func processToplevelDestroy(_ surfaceId: UInt32) {
        lastResizeTime.removeValue(forKey: surfaceId)
        pendingResize.removeValue(forKey: surfaceId)

        if let windowId = surfaceWindows.removeValue(forKey: surfaceId) {
            onWindowDestroyed?(windowId)
        }
        if let textureId = surfaceTextures.removeValue(forKey: surfaceId) {
            textureRegistry.unregisterTexture(engine: engine, id: textureId)
        }
        // Its subsurfaces went with the window (their unmap may still be
        // queued behind this; it then finds nothing).
        for (sid, parent) in subsurfaceParents where parent == surfaceId {
            processSubsurfaceUnmapped(sid)
        }

        surfaceSizes.removeValue(forKey: surfaceId)
        surfaceAppIds.removeValue(forKey: surfaceId)
        surfaceClients.removeValue(forKey: surfaceId)
        surfaceBufferScales.removeValue(forKey: surfaceId)
        surfaceGeometry.removeValue(forKey: surfaceId)
        lastEmittedGeometry.removeValue(forKey: surfaceId)
        surfaceOutputsMaskCache.removeValue(forKey: surfaceId)
        surfaceStateCache.removeValue(forKey: surfaceId)
        surfacePositionCache.removeValue(forKey: surfaceId)
        shortcutsInhibitedSurfaces.remove(surfaceId)
    }

    private func processTitleChanged(_ surfaceId: UInt32, title: String) {
        if let windowId = surfaceWindows[surfaceId] {
            onTitleChanged?(windowId, title)
        }
    }

    /// Clients may set their app_id before the surface has a window (the
    /// toplevel is created, app_id set, and only the first commit maps it), so
    /// remember it and replay when the window appears — otherwise the one
    /// authoritative identity signal is dropped for exactly the clients that
    /// are quickest off the mark.
    private func processAppIdChanged(_ surfaceId: UInt32, appId: String) {
        surfaceAppIds[surfaceId] = appId
        if let windowId = surfaceWindows[surfaceId] {
            onAppIdChanged?(windowId, appId)
        }
    }

    private func processNewPopup(_ surfaceId: UInt32, parentSurfaceId: UInt32,
                                  x: Int, y: Int, width: Int, height: Int) {
        if let oldTextureId = surfaceTextures[surfaceId] {
            textureRegistry.unregisterTexture(engine: engine, id: oldTextureId)
        }
        surfaceSizes.removeValue(forKey: surfaceId)
        surfaceBufferScales.removeValue(forKey: surfaceId)

        let textureId = textureRegistry.registerTexture(engine: engine)
        textureRegistry.markAsWaylandSurface(id: textureId)
        textureRegistry.markAsPopupSurface(id: textureId)
        surfaceTextures[surfaceId] = textureId

        popupSurfaceIds.insert(surfaceId)
        if let popupId = onNewPopup?(surfaceId, Int(textureId), parentSurfaceId, x, y, width, height) {
            surfaceWindows[surfaceId] = popupId
        }
    }

    /// A subsurface the shell draws inside a window. The texture is made
    /// here, before its first commit is drained; a re-placement of one that
    /// already has content is handed on at once.
    private func processSubsurfacePlaced(_ surfaceId: UInt32, toplevelId: UInt32,
                                         x: Int, y: Int, z: Int, acceptsInput: Bool) {
        subsurfaceParents[surfaceId] = toplevelId
        subsurfaceOffsets[surfaceId] = (x, y)
        subsurfaceZ[surfaceId] = z
        subsurfaceAcceptsInput[surfaceId] = acceptsInput
        if surfaceTextures[surfaceId] == nil {
            let textureId = textureRegistry.registerTexture(engine: engine)
            textureRegistry.markAsWaylandSurface(id: textureId)
            // A hover card is mostly transparent; a video is opaque anyway.
            textureRegistry.setKeepsAlpha(id: textureId, true)
            surfaceTextures[surfaceId] = textureId
        }
        if subsurfaceLogicalSizes[surfaceId] != nil {
            emitSubsurface(surfaceId)
        }
    }

    private func processSubsurfaceUnmapped(_ surfaceId: UInt32) {
        if let parent = subsurfaceParents.removeValue(forKey: surfaceId),
           subsurfaceEmitted.removeValue(forKey: surfaceId) != nil,
           let windowId = surfaceWindows[parent] {
            onSubsurfaceRemoved?(windowId, surfaceId)
        }
        subsurfaceOffsets.removeValue(forKey: surfaceId)
        subsurfaceZ.removeValue(forKey: surfaceId)
        subsurfaceAcceptsInput.removeValue(forKey: surfaceId)
        subsurfaceLogicalSizes.removeValue(forKey: surfaceId)
        subsurfaceEmitted.removeValue(forKey: surfaceId)
        if let textureId = surfaceTextures.removeValue(forKey: surfaceId) {
            textureRegistry.unregisterTexture(engine: engine, id: textureId)
        }
        surfaceSizes.removeValue(forKey: surfaceId)
        surfaceBufferScales.removeValue(forKey: surfaceId)
    }

    /// Where the subsurface sits in its window's content, in the shell's
    /// logical pixels: its offset from the toplevel's surface origin, less
    /// the toplevel's window-geometry origin, scaled as the geometry is.
    /// Handed to the shell only when it differs from what it last got.
    private func emitSubsurface(_ surfaceId: UInt32) {
        guard let parent = subsurfaceParents[surfaceId],
              let windowId = surfaceWindows[parent],
              let textureId = surfaceTextures[surfaceId],
              let size = subsurfaceLogicalSizes[surfaceId] else { return }
        let off = subsurfaceOffsets[surfaceId] ?? (0, 0)
        let geo = surfaceGeometry[parent]
        let f = fractionalScale / shellDpi
        let z = subsurfaceZ[surfaceId] ?? 0
        let input = subsurfaceAcceptsInput[surfaceId] ?? true
        let cur = (Double(off.x - (geo?.x ?? 0)) * f, Double(off.y - (geo?.y ?? 0)) * f,
                   Double(size.0), Double(size.1), z, input)
        if let prev = subsurfaceEmitted[surfaceId], prev == cur { return }
        subsurfaceEmitted[surfaceId] = cur
        onSubsurfaceChanged?(windowId, surfaceId, Int(textureId),
                             Rect.fromLTWH(cur.0, cur.1, cur.2, cur.3), z, input)
    }

    private func processPopupDestroy(_ surfaceId: UInt32) {
        popupSurfaceIds.remove(surfaceId)
        pendingPopupMoves.removeValue(forKey: surfaceId)

        if let popupId = surfaceWindows.removeValue(forKey: surfaceId) {
            onPopupDestroyed?(popupId)
        }
        if let textureId = surfaceTextures.removeValue(forKey: surfaceId) {
            textureRegistry.unregisterTexture(engine: engine, id: textureId)
        }

        surfaceSizes.removeValue(forKey: surfaceId)
        surfaceBufferScales.removeValue(forKey: surfaceId)
    }

    private func processFullscreenRequest(_ surfaceId: UInt32) {
        guard let windowId = surfaceWindows[surfaceId] else { return }
        onFullscreenRequest?(windowId)
    }

    private func processUnfullscreenRequest(_ surfaceId: UInt32) {
        guard let windowId = surfaceWindows[surfaceId] else { return }
        onUnfullscreenRequest?(windowId)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - C Callback Handlers (platform thread — just queue events)
    // ═══════════════════════════════════════════════════════════════════════

    private func handleNewToplevel(_ surfaceId: UInt32, clientId: UInt64) {
        pendingEvents.withLock { $0.append(.newToplevel(surfaceId: surfaceId, clientId: clientId)) }
        _needsFrame = true
    }

    private func handleCursorShape(_ shape: UInt32) {
        pendingEvents.withLock { $0.append(.cursorShape(shape: shape)) }
        _needsFrame = true
    }

    private func handleSurfaceCommit(_ surfaceId: UInt32, fd: Int32, width: Int, height: Int,
                                      stride: Int, fourcc: UInt32, modifier: UInt64,
                                      firstCommit: Bool, bufferScale: Int) {
        // Read viewport destination on platform thread (safe — inside dispatch)
        var vpW: Int32 = 0
        var vpH: Int32 = 0
        let hasViewport = server != nil && wayland_server_get_viewport_destination(server, surfaceId, &vpW, &vpH) != 0

        // Dup the DMA-BUF fd NOW, while the wl_buffer is guaranteed alive (we
        // are inside the commit dispatch on the event-loop thread). The C side
        // closes its fd whenever the client destroys the buffer — which can
        // happen before the UI thread processes this event. The dup is owned
        // by the texture registry (ownsFd) from import onward.
        let ownedFd = fd >= 0 ? dup(fd) : Int32(-1)

        pendingEvents.withLock { $0.append(.surfaceCommit(
            surfaceId: surfaceId, fd: ownedFd, width: width, height: height,
            stride: stride, fourcc: fourcc, modifier: modifier,
            firstCommit: firstCommit, bufferScale: bufferScale,
            viewportWidth: hasViewport ? Int(vpW) : 0,
            viewportHeight: hasViewport ? Int(vpH) : 0
        )) }
        _needsFrame = true
    }

    private func handleShmSurfaceCommit(_ surfaceId: UInt32, pixels: UnsafeRawPointer,
                                         width: Int, height: Int, stride: Int,
                                         format: UInt32, firstCommit: Bool,
                                         bufferScale: Int, keepAlpha: Bool) {
        guard width > 0, height > 0, stride >= width * 4 else { return }

        var vpW: Int32 = 0
        var vpH: Int32 = 0
        let hasViewport = server != nil && wayland_server_get_viewport_destination(server, surfaceId, &vpW, &vpH) != 0

        // The pool mapping is only guaranteed for the duration of this callback
        // (the client may destroy the pool the moment we return, and the
        // buffer is released to it as soon as we do), so the pixels have to
        // leave the pool here, on the event-loop thread. One vectorised pass
        // (wayland_shm_pack_rgba) packs the rows, swaps B,G,R,A to R,G,B,A
        // and forces alpha opaque where the role wants it: the buffer that
        // comes out is exactly what the GL upload takes, and the UI thread
        // adopts it without another copy. It used to be a memcpy here, a
        // per-byte Swift swizzle on the UI thread and a second memcpy into
        // the texture entry — three passes over a 4K frame for every commit
        // of a software client.
        let rowBytes = width * 4
        let copy = UnsafeMutableRawPointer.allocate(byteCount: rowBytes * height,
                                                    alignment: 16)
        wayland_shm_pack_rgba(copy, pixels, Int32(width), Int32(height), Int32(stride),
                              keepAlpha ? 1 : 0)

        pendingEvents.withLock { $0.append(.shmSurfaceCommit(
            surfaceId: surfaceId, pixels: copy, width: width, height: height,
            format: format, firstCommit: firstCommit, bufferScale: bufferScale,
            viewportWidth: hasViewport ? Int(vpW) : 0,
            viewportHeight: hasViewport ? Int(vpH) : 0
        )) }
        _needsFrame = true
    }

    private func handleTextInputState(_ surfaceId: UInt32, enabled: Bool,
                                       x: Int32, y: Int32, w: Int32, h: Int32) {
        var events = pendingEvents.value
        events.append(.textInputState(surfaceId: surfaceId, enabled: enabled,
                                      x: x, y: y, w: w, h: h))
        pendingEvents.value = events
        _needsFrame = true
    }

    private func handleClientDestroy(_ clientId: UInt64) {
        var events = pendingEvents.value
        events.append(.clientDestroy(clientId: clientId))
        pendingEvents.value = events
        _needsFrame = true
    }

    private func handleToplevelDestroy(_ surfaceId: UInt32) {
        var events = pendingEvents.value
        events.append(.toplevelDestroy(surfaceId: surfaceId))
        pendingEvents.value = events
        _needsFrame = true
    }

    private func handleTitleChanged(_ surfaceId: UInt32, title: String) {
        var events = pendingEvents.value
        events.append(.titleChanged(surfaceId: surfaceId, title: title))
        pendingEvents.value = events
    }

    private func handleAppIdChanged(_ surfaceId: UInt32, appId: String) {
        var events = pendingEvents.value
        events.append(.appIdChanged(surfaceId: surfaceId, appId: appId))
        pendingEvents.value = events
    }

    private func handleNewPopup(_ surfaceId: UInt32, parentSurfaceId: UInt32,
                                 x: Int, y: Int, width: Int, height: Int) {
        var events = pendingEvents.value
        events.append(.newPopup(surfaceId: surfaceId, parentSurfaceId: parentSurfaceId,
                                 x: x, y: y, width: width, height: height))
        pendingEvents.value = events
        _needsFrame = true
    }

    private func handlePopupDestroy(_ surfaceId: UInt32) {
        var events = pendingEvents.value
        events.append(.popupDestroy(surfaceId: surfaceId))
        pendingEvents.value = events
        _needsFrame = true
    }

    private func handleWindowGeometry(_ surfaceId: UInt32, x: Int, y: Int,
                                        width: Int, height: Int) {
        var events = pendingEvents.value
        events.append(.windowGeometry(surfaceId: surfaceId, x: x, y: y,
                                       width: width, height: height))
        pendingEvents.value = events
    }

    private func handleFullscreenRequest(_ surfaceId: UInt32) {
        var events = pendingEvents.value
        events.append(.fullscreenRequest(surfaceId: surfaceId))
        pendingEvents.value = events
        _needsFrame = true
    }

    private func handleUnfullscreenRequest(_ surfaceId: UInt32) {
        var events = pendingEvents.value
        events.append(.unfullscreenRequest(surfaceId: surfaceId))
        pendingEvents.value = events
        _needsFrame = true
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - Command Enqueuing (UI thread → platform thread)
    // ═══════════════════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - Multi-output (UI thread)
    // ═══════════════════════════════════════════════════════════════════════

    /// Output-array bit index per DisplayOutput.id (primary is always bit 0,
    /// matching the server's fresh-map default).
    /// Output id → wl_output bit. Written on the main thread (setOutputs),
    /// read on the PLATFORM thread (handlePresent maps the flipping engine
    /// output to its bit) — hence the lock; a torn Dictionary read is a
    /// crash, not just a stale answer.
    private var outputBitForId: [Int: Int] = [:]
    private let outputBitLock = NSLock()
    /// mask in the low 32 bits, pace mask in the high — one cache entry
    /// covers both, so a pace change with an unchanged intersection (a
    /// window sliding along the seam) still gets sent.
    private var surfaceOutputsMaskCache: [UInt32: UInt64] = [:]

    /// Advertise the virtual-desktop arrangement: one wl_output global per
    /// display, geometry in global logical coordinates.
    func setOutputs(_ outputs: [DisplayOutput]) {
        let ordered = outputs.filter { $0.isPrimary } +
                      outputs.filter { !$0.isPrimary }
        outputBitLock.lock()
        outputBitForId = Dictionary(
            uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0) })
        outputBitLock.unlock()
        let descs = ordered.map { o -> WaylandOutputDesc in
            var desc = WaylandOutputDesc()
            desc.logical_x = Int32(o.originX.rounded())
            desc.logical_y = Int32(o.originY.rounded())
            desc.physical_w = Int32(o.physicalWidth)
            desc.physical_h = Int32(o.physicalHeight)
            desc.scale = Int32(max(1, Int(o.scale)))
            desc.refresh_mhz = Int32(o.refreshMhz)
            withUnsafeMutableBytes(of: &desc.name) { buf in
                let bytes = Array(o.name.utf8.prefix(buf.count - 1))
                for (i, b) in bytes.enumerated() { buf[i] = b }
                buf[bytes.count] = 0
            }
            return desc
        }
        enqueueCommand(.setOutputs(outputs: descs))
    }

    /// Update which outputs a window's surface intersects; the server diffs
    /// and sends wl_surface.enter/leave. `paceOutputId` is the output the
    /// window mostly sits on — the one whose flips drive the client's frame
    /// callbacks. No-op for non-Wayland windows.
    func updateSurfaceOutputs(windowId: String, intersectingIds: [Int],
                              paceOutputId: Int? = nil) {
        outputBitLock.lock()
        let bits = outputBitForId
        outputBitLock.unlock()
        guard !bits.isEmpty,
              let surfaceId = surfaceWindows.first(
                  where: { $0.value == windowId })?.key
        else { return }
        var mask: UInt32 = 0
        for id in intersectingIds {
            if let bit = bits[id] {
                mask |= 1 << UInt32(bit)
            }
        }
        var paceMask: UInt32 = 0
        if let paceId = paceOutputId, let bit = bits[paceId] {
            paceMask = 1 << UInt32(bit)
        }
        let combined = UInt64(mask) | (UInt64(paceMask) << 32)
        if surfaceOutputsMaskCache[surfaceId] == combined { return }
        surfaceOutputsMaskCache[surfaceId] = combined
        enqueueCommand(.setSurfaceOutputs(surfaceId: surfaceId, mask: mask,
                                          paceMask: paceMask))
    }

    /// The wl_output bit for an engine output id, or bit 0 (the primary)
    /// when the id is unknown — single-output desktops never call
    /// setOutputs, and their one panel IS the primary. Platform-thread safe.
    func outputBit(forId id: Int) -> UInt32 {
        outputBitLock.lock()
        defer { outputBitLock.unlock() }
        return UInt32(outputBitForId[id] ?? 0)
    }

    private func enqueueCommand(_ cmd: WaylandCommand) {
        pendingCommands.withLock { $0.append(cmd) }
        // Wake the epoll loop to drain commands promptly. Writing before the
        // loop starts (or before setEpollDriven) is fine — the byte sits in
        // the pipe and fires as soon as the loop begins polling, which is
        // what lets startup commands (e.g. setOutputs) execute deterministically.
        if wakeupWriteFd >= 0 {
            var byte: UInt8 = 1
            _ = Glibc.write(wakeupWriteFd, &byte, 1)
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - Input Forwarding (safe from any thread — uses C deferred pipe)
    // ═══════════════════════════════════════════════════════════════════════

    /// Queries which DRM modifiers the compositor's EGL can import for the
    /// formats our texture path supports, and advertises exactly that list
    /// via linux-dmabuf (v3 modifier events + v4 feedback table). Clients
    /// bringing their own Mesa then negotiate layouts both sides explicitly
    /// support — no reliance on implicit-modifier guessing across Mesa
    /// versions.
    func advertiseDmaBufFormats(eglDisplay: UnsafeMutableRawPointer?) {
        guard let server = server, let eglDisplay = eglDisplay else { return }
        let DRM_FORMAT_MOD_INVALID: UInt64 = 0x00FF_FFFF_FFFF_FFFF
        // ARGB8888, XRGB8888, ABGR8888, XBGR8888 — the import path's formats.
        let fourccs: [UInt32] = [0x3432_5241, 0x3432_5258, 0x3432_4241, 0x3432_4258]

        // Tiled modifiers are opt-in for now: zink's
        // eglQueryDmaBufModifiersEXT reports the AMD tiled layouts as
        // importable, but eglCreateImageKHR then fails with BAD_ALLOC
        // (and DCC layouts additionally need multi-plane import we don't
        // have). Until that gap closes, advertise EGL-verified LINEAR plus
        // the implicit modifier — correctness first, tiling perf later.
        let allowTiled = ProcessInfo.processInfo.environment["STARLING_DMABUF_TILED"] == "1"
        let DRM_FORMAT_MOD_LINEAR: UInt64 = 0

        // Modifiers a previous session PROVED unimportable (the query lies;
        // the import is ground truth — e.g. radeonsi's GFX11 64K_R_X layout
        // fails zink's plane-layout translation). Skipped up front so
        // clients never waste a first frame on them.
        let demoted = Self.loadDemotedModifiers()

        var formats: [UInt32] = []
        var modifiers: [UInt64] = []
        var queried = [UInt64](repeating: 0, count: 64)
        for fourcc in fourccs {
            let n = dmabuf_query_modifiers(eglDisplay, fourcc, &queried, 64)
            for i in 0 ..< Int(n) {
                let modifier = queried[i]
                if !allowTiled && modifier != DRM_FORMAT_MOD_LINEAR {
                    continue
                }
                // Skip AMD DCC modifiers even in tiled mode: DCC buffers
                // carry extra metadata planes and our import path is
                // single-plane only (vendor 0x02 in bits 56-63, DCC bit 13).
                if (modifier >> 56) == 0x02 && (modifier >> 13) & 1 == 1 {
                    continue
                }
                if demoted.contains(modifier) {
                    continue
                }
                formats.append(fourcc)
                modifiers.append(modifier)
            }
            // Keep implicit-modifier support: producer and consumer share the
            // same kernel driver, which resolves the layout.
            formats.append(fourcc)
            modifiers.append(DRM_FORMAT_MOD_INVALID)
        }
        guard !formats.isEmpty else { return }
        wayland_server_set_dmabuf_formats(server, formats, modifiers,
                                          Int32(formats.count))
        if !demoted.isEmpty {
            print("[WaylandIntegration] skipping \(demoted.count) demoted dma-buf modifier(s) from a previous session")
        }
        print("[WaylandIntegration] advertising \(formats.count) dma-buf format+modifier pairs from EGL")

        // Runtime self-correction: when the raster thread's EGLImage import
        // rejects a buffer, demote its modifier live (feedback re-send makes
        // v4 clients re-allocate) and persist it for the next session.
        LinuxTextureRegistry.onDmaBufImportFailure = { [weak self] fourcc, modifier in
            guard let self, let server = self.server else { return }
            if Self.persistDemotedModifier(modifier) {
                print("[WaylandIntegration] dma-buf import failed (fourcc=0x\(String(fourcc, radix: 16)) modifier=0x\(String(modifier, radix: 16))) — demoting")
            }
            wayland_server_demote_dmabuf_modifier(server, fourcc, modifier)
        }
    }

    /// Demoted-modifier persistence: one hex modifier per line. Lives in
    /// TMPDIR so it survives shell restarts on the dev box (and resets per
    /// boot on the image, where /tmp is tmpfs) — a stale entry only costs
    /// tiling perf, never correctness.
    private static let demotedModifiersPath =
        (ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp") + "/starling-dmabuf-demoted"
    private static let demotedLock = NSLock()
    // nonisolated(unsafe): guarded by demotedLock.
    nonisolated(unsafe) private static var demotedPersisted: Set<UInt64>?

    private static func loadDemotedModifiers() -> Set<UInt64> {
        demotedLock.lock()
        defer { demotedLock.unlock() }
        if let cached = demotedPersisted { return cached }
        var set = Set<UInt64>()
        if let text = try? String(contentsOfFile: demotedModifiersPath, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                if let v = UInt64(line.trimmingCharacters(in: .whitespaces), radix: 16) {
                    set.insert(v)
                }
            }
        }
        demotedPersisted = set
        return set
    }

    /// Returns true when the modifier is newly demoted (first failure).
    private static func persistDemotedModifier(_ modifier: UInt64) -> Bool {
        demotedLock.lock()
        defer { demotedLock.unlock() }
        var set = demotedPersisted ?? Set<UInt64>()
        guard !set.contains(modifier) else { return false }
        set.insert(modifier)
        demotedPersisted = set
        let text = set.map { String($0, radix: 16) }.joined(separator: "\n") + "\n"
        try? text.write(toFile: demotedModifiersPath, atomically: true, encoding: .utf8)
        return true
    }

    private var pointerFocusSurface: UInt32 = 0
    /// Set by a button press forwarded to a client surface; read and
    /// cleared by the shell's root listener, which fires after every
    /// surface's own (hit-test order is child-first). A press that reached
    /// no client surface is a press "outside", which dismisses a grabbed
    /// popup — on the desktop, the dock, the bar, an X11 window.
    private var _pressReachedClient = false

    /// Relative pointer motion for a surface's client, in logical pixels.
    func sendRelativeMotion(surfaceId: UInt32, dx: Double, dy: Double) {
        guard let server = server else { return }
        let timeMs = UInt32(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        let d = shellDpi / fractionalScale
        wayland_server_pointer_relative_motion(server, surfaceId, timeMs, dx * d, dy * d)
    }

    /// Focus moved away from a constrained window: every lock and
    /// confinement ends (the client hears unlocked/unconfined).
    func breakPointerConstraints() {
        guard server != nil else { return }
        enqueueCommand(.breakPointerConstraints)
        enqueueCommand(.flushClients)
    }

    func notePointerDown() {
        let reached = _pressReachedClient
        _pressReachedClient = false
        guard !reached, !dragActive, let server = server else { return }
        wayland_server_pointer_pressed_outside(server)
    }
    private var keyboardFocusSurface: UInt32 = 0

    /// xkb modifier masks for the default us(pc105) keymap the seat sends.
    private var modsDepressed: UInt32 = 0
    private var modsLocked: UInt32 = 0

    /// Maps a modifier keysym to its bit in the default keymap
    /// (Shift=0, Lock=1, Control=2, Mod1/Alt=3, Mod2/Num=4, Mod4/Super=6,
    /// Mod5/AltGr=7).
    private static func modifierBit(forKeysym keysym: Int64) -> UInt32? {
        switch keysym {
        case 0xFFE1, 0xFFE2: return 1 << 0  // Shift_L / Shift_R
        case 0xFFE3, 0xFFE4: return 1 << 2  // Control_L / Control_R
        case 0xFFE9, 0xFFEA: return 1 << 3  // Alt_L / Alt_R
        case 0xFFEB, 0xFFEC: return 1 << 6  // Super_L / Super_R
        case 0xFE03: return 1 << 7          // ISO_Level3_Shift (AltGr)
        default: return nil
        }
    }

    /// Sync wl_keyboard focus (enter/leave + modifiers) to the
    /// pointer-focused surface without sending a key. Needed while the IME
    /// swallows every key: text-input enter rides keyboard enter, and the
    /// lazy enter inside sendKeyEvent would otherwise never fire.
    func ensureKeyboardFocus() {
        guard let server = server else { return }
        let surfaceId = pointerFocusSurface
        guard surfaceId != 0, keyboardFocusSurface != surfaceId else { return }
        if keyboardFocusSurface != 0 {
            wayland_server_keyboard_leave(server, keyboardFocusSurface)
        }
        wayland_server_keyboard_enter(server, surfaceId)
        keyboardFocusSurface = surfaceId
        wayland_server_keyboard_modifiers(server, surfaceId,
                                          modsDepressed, 0, modsLocked, 0)
    }

    /// Deliver a key to a Wayland client. `targetSurface` is the focused
    /// WINDOW's surface — keyboard focus follows window focus, not the pointer.
    /// Passing 0 falls back to the pointer-focus surface (legacy callers).
    ///
    /// This distinction is load-bearing: when a window is focused without the
    /// pointer over it — a new toplevel mapped on top (Zoom's SSO opening
    /// Chrome), or click-to-focus followed by the cursor moving away — the
    /// pointer-focus surface is 0, and keying off it dropped every keystroke.
    func sendKeyEvent(physical: Int64, logical: Int64, isDown: Bool,
                      targetSurface: UInt32 = 0) {
        guard let server = server else { return }
        let surfaceId = targetSurface != 0 ? targetSurface : pointerFocusSurface
        guard surfaceId != 0 else { return }

        if keyboardFocusSurface != surfaceId {
            if keyboardFocusSurface != 0 {
                wayland_server_keyboard_leave(server, keyboardFocusSurface)
            }
            wayland_server_keyboard_enter(server, surfaceId)
            keyboardFocusSurface = surfaceId
            // The spec requires a modifiers event after enter so the client
            // starts from the compositor's current state.
            wayland_server_keyboard_modifiers(server, surfaceId,
                                              modsDepressed, 0, modsLocked, 0)
        }

        // Track modifier state from the keysym and inform the client BEFORE
        // the key event: clients interpret keys through the xkb state driven
        // by wl_keyboard.modifiers, so without this Shift/Ctrl never apply.
        var modsChanged = false
        if let bit = WaylandIntegration.modifierBit(forKeysym: logical) {
            if isDown && modsDepressed & bit == 0 {
                modsDepressed |= bit
                modsChanged = true
            } else if !isDown && modsDepressed & bit != 0 {
                modsDepressed &= ~bit
                modsChanged = true
            }
        } else if isDown && (logical == 0xFFE5 || logical == 0xFF7F) {
            // Caps_Lock / Num_Lock toggle their locked bits on press.
            let bit: UInt32 = logical == 0xFFE5 ? (1 << 1) : (1 << 4)
            modsLocked ^= bit
            modsChanged = true
        }
        if modsChanged {
            wayland_server_keyboard_modifiers(server, surfaceId,
                                              modsDepressed, 0, modsLocked, 0)
        }

        let evdevKey = WaylandIntegration.hidToEvdev(UInt64(bitPattern: physical))
        let timeMs = UInt32(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        wayland_server_keyboard_key(server, surfaceId, timeMs, evdevKey,
                                     isDown ? 1 : 0)
    }

    /// USB HID usage (page 0x07) -> evdev key code. The exact inverse of the
    /// engine's FlDrmInput::EvdevToHID (fl_drm_input.cc) — keep in sync.
    /// Not private: the X11 key path (DesktopShell.routeKey) reuses this so the
    /// HID→evdev mapping has ONE source of truth across both display servers.
    /// HID → evdev for Wayland clients. The table lives in HidEvdev, which
    /// derives this direction and its inverse from one list of pairs — see
    /// there for why they must not be separate switches.
    static func hidToEvdev(_ hid: UInt64) -> UInt32 {
        return HidEvdev.evdev(fromHid: hid)
    }

    func sendScrollEvent(surfaceId: UInt32, x: Double, y: Double,
                          scrollDeltaX: Double, scrollDeltaY: Double) {
        guard let server = server else { return }
        let timeMs = UInt32(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        wayland_server_pointer_axis(server, surfaceId, timeMs,
                                     scrollDeltaX, scrollDeltaY)
    }

    func sendPointerEvent(surfaceId: UInt32, phase: Int32, x: Double, y: Double, buttons: Int64) {
        // A drag owns the pointer: the per-window forwarding that Flutter
        // keeps routing to the surface the button went down on would fight
        // the drag router, which follows the pointer across windows.
        guard !dragActive else { return }
        _sendPointer(surfaceId: surfaceId, phase: phase, x: x, y: y, buttons: buttons)
    }

    private func _sendPointer(surfaceId: UInt32, phase: Int32, x: Double, y: Double, buttons: Int64) {
        guard let server = server else { return }

        let timeMs = UInt32(DispatchTime.now().uptimeNanoseconds / 1_000_000)

        if pointerFocusSurface != surfaceId {
            if pointerFocusSurface != 0 {
                wayland_server_pointer_leave(server, pointerFocusSurface)
            }
            wayland_server_pointer_enter(server, surfaceId, x, y)
            pointerFocusSurface = surfaceId
            _lastAbsolute[surfaceId] = Offset(x, y)
        }

        switch phase {
        case 2: // down
            _pressReachedClient = true
            _syncButtons(server, surfaceId: surfaceId, mask: buttons, timeMs: timeMs)
        case 1: // up
            _syncButtons(server, surfaceId: surfaceId, mask: buttons, timeMs: timeMs)
        case 3, 6: // move (a second button pressed or released mid-drag
                   // arrives as a move with a changed mask, not as down/up)
                   // or hover
            let d = shellDpi / fractionalScale
            if lockedSurface == surfaceId {
                // Locked: the cursor is held; the root listener sends the
                // relative motion. No absolute motion, per the protocol.
            } else {
                wayland_server_pointer_motion(server, surfaceId, timeMs, x * d, y * d)
                if let last = _lastAbsolute[surfaceId] {
                    let dx = x - last.dx, dy = y - last.dy
                    if dx != 0 || dy != 0 {
                        wayland_server_pointer_relative_motion(server, surfaceId, timeMs, dx * d, dy * d)
                    }
                }
                _lastAbsolute[surfaceId] = Offset(x, y)
            }
            _syncButtons(server, surfaceId: surfaceId, mask: phase == 3 ? buttons : 0, timeMs: timeMs)
        default:
            break
        }
    }

    /// Flutter's button mask → evdev codes. What the client is told is the
    /// DIFFERENCE from what it was last told for this surface, so a chord
    /// presses and releases each button once, whatever order Flutter's
    /// events arrive in. Every button used to be sent as BTN_LEFT: a
    /// right-click in any Wayland app was a left click.
    private var _heldButtons: [UInt32: Int64] = [:]
    /// The last absolute position sent per surface, for relative motion.
    private var _lastAbsolute: [UInt32: Offset] = [:]
    private static let _buttonCodes: [(mask: Int64, code: UInt32)] = [
        (1, 0x110),   // kPrimaryButton      → BTN_LEFT
        (2, 0x111),   // kSecondaryButton    → BTN_RIGHT
        (4, 0x112),   // kMiddleMouseButton  → BTN_MIDDLE
        (8, 0x113),   // kBackMouseButton    → BTN_SIDE
        (16, 0x114),  // kForwardMouseButton → BTN_EXTRA
    ]
    private func _syncButtons(_ server: OpaquePointer, surfaceId: UInt32, mask: Int64,
                              timeMs: UInt32) {
        let held = _heldButtons[surfaceId] ?? 0
        if held == mask { return }
        for b in Self._buttonCodes {
            let was = held & b.mask != 0, now = mask & b.mask != 0
            if now && !was { wayland_server_pointer_button(server, surfaceId, timeMs, b.code, 1) }
            if was && !now { wayland_server_pointer_button(server, surfaceId, timeMs, b.code, 0) }
        }
        if mask == 0 { _heldButtons.removeValue(forKey: surfaceId) }
        else { _heldButtons[surfaceId] = mask }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - Quit
    // ═══════════════════════════════════════════════════════════════════════

    /// Ask the client owning `surfaceId` to close itself (xdg_toplevel.close).
    func requestClose(surfaceId: UInt32) {
        guard server != nil else { return }
        enqueueCommand(.closeToplevel(surfaceId: surfaceId))
    }

    /// pid behind a surface, captured when its toplevel appeared. nil if the
    /// surface never had one (or the compositor could not read credentials).
    func clientPid(surfaceId: UInt32) -> pid_t? {
        return surfacePids[surfaceId]
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - Resize / Configure (UI thread → enqueue commands)
    // ═══════════════════════════════════════════════════════════════════════

    func isResizing(surfaceId: UInt32) -> Bool {
        guard let t = lastResizeTime[surfaceId] else { return false }
        return DispatchTime.now().uptimeNanoseconds - t < resizeIntervalNs * 3
    }

    func sendResize(surfaceId: UInt32, width: Int, height: Int) {
        guard server != nil else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        if let last = lastResizeTime[surfaceId], now - last < resizeIntervalNs {
            pendingResize[surfaceId] = (width, height)
            return
        }
        pendingResize.removeValue(forKey: surfaceId)
        lastResizeTime[surfaceId] = now
        let sw = Int32(Double(width) * shellDpi / fractionalScale)
        let sh = Int32(Double(height) * shellDpi / fractionalScale)
        syncToplevelState(surfaceId: surfaceId)
        enqueueCommand(.configureToplevel(surfaceId: surfaceId, width: sw, height: sh))
        enqueueCommand(.flushClients)
    }

    func sendFullscreenResize(surfaceId: UInt32, width: Int, height: Int) {
        guard server != nil else { return }
        pendingResize.removeValue(forKey: surfaceId)
        lastResizeTime[surfaceId] = DispatchTime.now().uptimeNanoseconds
        let sw = Int32(Double(width) * shellDpi / fractionalScale)
        let sh = Int32(Double(height) * shellDpi / fractionalScale)
        syncToplevelState(surfaceId: surfaceId)
        enqueueCommand(.configureToplevel(surfaceId: surfaceId, width: sw, height: sh))
        enqueueCommand(.flushClients)
    }

    func sendExitFullscreen(surfaceId: UInt32, width: Int, height: Int) {
        guard server != nil else { return }
        pendingResize.removeValue(forKey: surfaceId)
        lastResizeTime[surfaceId] = DispatchTime.now().uptimeNanoseconds
        let sw = Int32(Double(width) * shellDpi / fractionalScale)
        let sh = Int32(Double(height) * shellDpi / fractionalScale)
        syncToplevelState(surfaceId: surfaceId)
        enqueueCommand(.configureToplevel(surfaceId: surfaceId, width: sw, height: sh))
        enqueueCommand(.flushClients)
    }

    /// Configure with no size: the client picks its own. For a dialog,
    /// which was configured to the maximized size when it appeared and must
    /// not draw at it. Any throttled resize is dropped — it was that size.
    func sendNaturalSize(surfaceId: UInt32) {
        guard server != nil else { return }
        pendingResize.removeValue(forKey: surfaceId)
        lastResizeTime[surfaceId] = DispatchTime.now().uptimeNanoseconds
        syncToplevelState(surfaceId: surfaceId)
        enqueueCommand(.configureToplevelNatural(surfaceId: surfaceId))
        enqueueCommand(.flushClients)
    }

    func sendResizeForced(surfaceId: UInt32, width: Int, height: Int) {
        guard server != nil else { return }
        pendingResize.removeValue(forKey: surfaceId)
        lastResizeTime[surfaceId] = DispatchTime.now().uptimeNanoseconds
        let sw = Int32(Double(width) * shellDpi / fractionalScale)
        let sh = Int32(Double(height) * shellDpi / fractionalScale)
        syncToplevelState(surfaceId: surfaceId)
        enqueueCommand(.configureToplevel(surfaceId: surfaceId, width: sw, height: sh))
        enqueueCommand(.flushClients)
    }

    func sendPointerEnter(surfaceId: UInt32, x: Double, y: Double) {
        guard let server = server else { return }
        let d = shellDpi / fractionalScale
        wayland_server_pointer_enter(server, surfaceId, x * d, y * d)
    }

    func sendPointerLeave(surfaceId: UInt32) {
        guard let server = server else { return }
        wayland_server_pointer_leave(server, surfaceId)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - Lookup Helpers
    // ═══════════════════════════════════════════════════════════════════════

    func surfaceId(forWindowId windowId: String) -> UInt32? {
        return surfaceWindows.first(where: { $0.value == windowId })?.key
    }

    /// Throttle a surface's frame callbacks (Murmuration: tile-only agent
    /// windows idle at ~5fps). 0 restores full rate. Safe from any thread.
    func setSurfaceThrottle(surfaceId: UInt32, intervalMs: UInt32) {
        enqueueCommand(.setSurfaceThrottle(surfaceId: surfaceId, intervalMs: intervalMs))
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - Agent Input (Murmuration)
    //
    // Broker-injected input into agent-owned Wayland windows. A dedicated
    // second wl_seat exists compositor-side (seat-agent), but Chromium's
    // Ozone layer is single-seat and takes no input from it (verified:
    // zero DOM events) — so agent input is delivered on seat 0 with
    // EXPLICIT per-event surface targeting and its own focus trackers.
    // Delivery is per-client, so the human (in one client) and the agent
    // (in another) never disturb each other; only concurrent human+agent
    // use of the SAME client's windows can interleave. Seat-aware clients
    // can move to the agent seat later without compositor changes.
    // ═══════════════════════════════════════════════════════════════════════

    private var agentPointerFocus: UInt32 = 0
    private var agentKeyboardFocus: UInt32 = 0

    /// Same phase contract as sendPointerEvent (2=down 1=up 3=move 6=hover),
    /// same coordinate scaling, but with independent focus tracking. A
    /// motion always precedes a button so the click lands at (x, y) even
    /// without preceding hovers.
    func agentPointerEvent(surfaceId: UInt32, phase: Int32, x: Double, y: Double) {
        guard let server = server else { return }
        let timeMs = UInt32(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        let d = shellDpi / fractionalScale
        if agentPointerFocus != surfaceId {
            wayland_server_pointer_enter(server, surfaceId, x * d, y * d)
            agentPointerFocus = surfaceId
        }
        switch phase {
        case 2:
            wayland_server_pointer_motion(server, surfaceId, timeMs, x * d, y * d)
            wayland_server_pointer_button(server, surfaceId, timeMs, 0x110, 1)
        case 1:
            wayland_server_pointer_button(server, surfaceId, timeMs, 0x110, 0)
        case 3, 6:
            wayland_server_pointer_motion(server, surfaceId, timeMs, x * d, y * d)
        default:
            break
        }
    }

    /// Agent key; `physical` is a HID usage (the broker's key contract),
    /// converted with the same table as the human path.
    func agentKeyEvent(surfaceId: UInt32, physical: Int64, isDown: Bool) {
        guard let server = server else { return }
        if agentKeyboardFocus != surfaceId {
            wayland_server_keyboard_enter(server, surfaceId)
            agentKeyboardFocus = surfaceId
        }
        let evdevKey = WaylandIntegration.hidToEvdev(UInt64(bitPattern: physical))
        guard evdevKey != 0 else { return }
        let timeMs = UInt32(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        wayland_server_keyboard_key(server, surfaceId, timeMs,
                                    evdevKey, isDown ? 1 : 0)
    }

    /// Agent scroll (deltas in the same units as sendScrollEvent).
    func agentScrollEvent(surfaceId: UInt32, deltaX: Double, deltaY: Double) {
        guard let server = server else { return }
        let timeMs = UInt32(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        wayland_server_pointer_axis(server, surfaceId, timeMs, deltaX, deltaY)
    }

    func windowId(forSurfaceId surfaceId: UInt32) -> String? {
        return surfaceWindows[surfaceId]
    }

    /// The connection a window's surface belongs to (the same opaque id
    /// onNewWindow reported), nil for a window that is not a Wayland toplevel.
    func clientId(forWindowId windowId: String) -> UInt64? {
        guard let sid = surfaceId(forWindowId: windowId) else { return nil }
        return surfaceClients[sid]
    }

}
