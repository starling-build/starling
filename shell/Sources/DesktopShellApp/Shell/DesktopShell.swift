// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation
import CupertinoIcons
import FluentSystemIcons
import StarlingRegistry
import StarlingNet
import StarlingPower
import StarlingAudio
#if os(Linux)
import FlutterDRMBridge  // fl_drm_view_capture_active (X11 GetImage present pump)
import FlutterEmbedderBridge  // FlutterEngineScheduleFrame (frame-pump ticks)
#endif

/// Called from main.swift after waylandIntegration is set.
/// Lets _DesktopShellState wire up callbacks that couldn't be set during initState().
nonisolated(unsafe) var _onWaylandIntegrationReady: (() -> Void)?

/// Called from main.swift after x11Integration is set.
nonisolated(unsafe) var _onX11IntegrationReady: (() -> Void)?

// MARK: - DesktopShell

/// Root widget of the Desktop Shell PoC.
///
/// Owns the window manager state and renders the desktop as a Stack:
/// background wallpaper at the bottom, windows in the middle, taskbar on top.
class DesktopShell: StatefulWidget {

    override func createState() -> State<StatefulWidget> {
        return _DesktopShellState()
    }
}

// MARK: - _DesktopShellState

/// Global ref for testing — allows SIGUSR2 to trigger shell-level resize.
nonisolated(unsafe) var _shellState: _DesktopShellState? = nil

class _DesktopShellState: State<StatefulWidget>, TickerProvider {

    /// Every shell state change may move/open/close/focus a window that a
    /// secondary output shows — poke those trees. Each host signature-checks
    /// its own content, so unrelated churn (dock hover) doesn't re-present.
    override func setState(_ fn: () -> Void) {
        super.setState(fn)
        // The three periodic timers below tick only while something is
        // WATCHING them, and this is where that is decided. It has to be a
        // funnel rather than a hook per gate: the gates are ordinary state
        // (which space is active, whether a popup is open, whether a
        // recording runs) mutated from dozens of places, and one missed site
        // is a timer that never starts -- a recording whose elapsed time
        // stops moving. Every shell state change comes through here, so
        // nothing can be missed. Three bool reads.
        _reevaluateShellTimers()
        if !secondaryScreenInvalidators.isEmpty {
            invalidateSecondaryScreens()
            updateWaylandSurfaceOutputs()
        }
    }

    /// Start/stop the watched-only timers. Suspended DispatchSourceTimers
    /// cost nothing; a running one whose handler returns immediately costs a
    /// wakeup on the libdispatch timer thread AND one on the main thread,
    /// every period, forever. Two of these ran at 1 Hz and were the whole of
    /// what the desktop still did while idle.
    func _reevaluateShellTimers() {
        #if os(Linux)
        // Workspace tiles show working/idle from broker activity and frame
        // recency, neither of which marks a widget dirty — so a workspace on
        // screen needs a poke once a second, and nothing else does.
        _tick(&_spaceRepaintTimer, windowManager.activeSpace.isSpecial,
              every: 1) { [weak self] in self?.setState {} }
        // The recording indicator's elapsed time.
        _tick(&_recordingTickTimer, recordingService?.isRecording == true,
              every: 1) { [weak self] in self?.setState {} }
        // Signal strengths and scan results, while the Wi-Fi popup is up.
        _tick(&_wifiRefreshTimer, activeStatusBarPopup == .wifi,
              every: 5) { [weak self] in self?.networkService.refreshNow() }
        #endif
    }

    /// Create the timer when something starts watching, CANCEL it when the
    /// last watcher goes.
    ///
    /// Cancel, not suspend — that distinction is the whole point and it cost
    /// a measurement to find. Suspending a `DispatchSourceTimer` stops its
    /// handler but leaves libdispatch's timerfd armed for the source's next
    /// deadline: the manager thread still wakes every period, re-arms, and
    /// goes back to sleep. The main thread goes quiet, the wakeups do not,
    /// and a CPU sample barely moves. Only cancelling takes the deadline out
    /// of libdispatch's set. (This is the shape `AgentBroker` already uses.)
    private func _tick(_ slot: inout DispatchSourceTimer?, _ wanted: Bool,
                       every seconds: Int, _ body: @escaping () -> Void) {
        if wanted {
            guard slot == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: .main)
            t.schedule(deadline: .now() + .seconds(seconds),
                       repeating: .seconds(seconds))
            t.setEventHandler(
                handler: unsafeBitCast(body, to: (@Sendable () -> Void).self))
            t.resume()
            slot = t
        } else if let t = slot {
            t.cancel()
            slot = nil
        }
    }

    func createTicker(_ onTick: @escaping TickerCallback) -> Ticker {
        return Ticker(onTick)
    }

    let windowManager = WindowManagerState()
    var wallpaperPreset: WallpaperPreset = .still
    var wallpaperTextureId: Int64 = -1
    private var _wallpaperDecodeStarted = false
    /// Apps whose host icon we have already tried to resolve (see
    /// _loadIconTexture(for:)). Not a one-shot flag: apps arrive mid-session.
    private var _iconDecodeAttempted: Set<String> = []

    // Dock icon textures (loaded from PNG-converted RGBA files)
    var iconTextures: [String: Int64] = [:]  // appId → textureId

    /// The active style's chrome — which surfaces the desktop draws and where
    /// (ShellStyle.swift). Rebuilt by `_setStyle`; it holds `self` unowned, so
    /// it must never outlive this state.
    lazy var chrome: any ShellChrome = shellStyle.makeChrome(self)

    // Context menu state. The position is LOCAL to the output it opened on —
    // each tree renders its own copy (the dock/launcher pattern), so a
    // right-click on the second monitor gets its menu there, not on the host.
    var contextMenuPosition: Offset?
    var contextMenuOutputId: Int = 0

    // Status bar popup state (nil = no popup open)
    enum StatusBarPopup { case wifi, battery, notifications, controlCenter, clock, power }
    var activeStatusBarPopup: StatusBarPopup? = nil

    /// What the power menu is asking the user to confirm, or nil while it is
    /// still showing the list. Ending a session is not undoable, so every item
    /// takes two clicks — the panel swaps its list for a confirm prompt rather
    /// than opening a second surface.
    enum PowerAction {
        case shutDown, restart, logOut

        var title: String {
            switch self {
            case .shutDown: return "Shut Down"
            case .restart:  return "Restart"
            case .logOut:   return "Log Out"
            }
        }

        /// One line each, and that is load-bearing: the confirm panel is 220
        /// logical px wide (_statusPopupGeometry), and a prompt that wraps
        /// makes THAT action's panel taller, so its Cancel/confirm buttons sit
        /// lower than the other two actions' — the destructive button moves
        /// between near-identical dialogs, which is exactly where a stray
        /// click costs the most. Log Out's prompt used to be "Close all apps
        /// and end the session?", which wrapped and put its buttons ~33px
        /// below Shut Down's. The release gate clicks Shut Down's confirm at
        /// fixed coordinates, so a wrap there fails the gate; the other two
        /// are only as good as this comment.
        var prompt: String {
            switch self {
            case .shutDown: return "Shut down the computer?"
            case .restart:  return "Restart the computer?"
            case .logOut:   return "Close all apps and log out?"
            }
        }

        /// systemd handles the privilege question: on a real session logind
        /// authorises the caller through polkit, and the shell running as root
        /// (dev mode) is allowed outright. Log Out terminates the session
        /// rather than killing the shell, so the display manager takes over.
        var command: (String, [String]) {
            switch self {
            case .shutDown: return ("/usr/bin/systemctl", ["poweroff"])
            case .restart:  return ("/usr/bin/systemctl", ["reboot"])
            case .logOut:   return ("/usr/bin/loginctl", ["terminate-session", "self"])
            }
        }
    }
    var _powerConfirm: PowerAction? = nil

    // Full-screen app launcher (Launchpad) open state; toggled by the dock's
    // grid icon. See AppLauncher. _launcherQuery is the live search string
    // (typed while the launcher is open) that filters the app grid.
    var _launcherOpen: Bool = false
    var _launcherQuery: String = ""
    // Blink phase of the Launchpad search caret. The search field is always
    // focused while the launcher is open, but it is a drawn pill rather than a
    // real text input, so the caret is the only thing telling a user the
    // keyboard is live — see AppLauncher.searchBar.
    var _launcherCaretToken: Int = 0

    // WiFi: real state behind the status-bar icon and popup. The service
    // owns all nmcli traffic; these vars are only the popup's UI state.
    let networkService = NetworkService()
    // Battery: real state behind the status-bar icon and popup. On a machine
    // with no battery the icon (and popup) simply don't exist.
    let batteryService = BatteryService()

    // Notifications: the freedesktop daemon lives on a service thread
    // (NotificationIntegration); these banners are its whole UI. Ordered
    // oldest-first; the overlay renders the newest few.
    struct ShellNotification {
        let id: UInt32
        var appName: String
        var summary: String
        var body: String
        var urgency: Int      // 0 low / 1 normal / 2 critical
    }
    var _notifications: [ShellNotification] = []
    /// A post arrived while the popup was closed — tints the bell until the
    /// user looks. Opening the popup is "looking"; it clears the tint, not
    /// the list.
    var _notificationsUnseen = false

    // Control center: live levels behind the quick panel, read on open and
    // on a 2s tick while it stays up — volume moved by a keyboard key or
    // wpctl by hand must show here, the same contract as the wifi popup.
    var _ccAudio = AudioStatus()
    var _ccBacklight = BacklightStatus()
    private var _ccTickScheduled = false
    /// Non-nil while the popup is showing the password prompt for this SSID.
    var _wifiPasswordSSID: String? = nil
    /// The prompt target's SECURITY string (picks WPA2 vs WPA3 key-mgmt).
    var _wifiPasswordSecurity: String = ""
    var _wifiPassword: String = ""
    // Password caret blink — same alpha-fade mechanism as the Launchpad
    // search caret (see _restartLauncherCaret and the trap it documents).
    var _wifiCaretOn: Bool = true
    var _wifiCaretToken: Int = 0
    /// SSID currently being joined (shows the spinner row), nil when idle.
    var _wifiConnecting: String? = nil
    /// Last join failure, shown in the popup until the next attempt or open.
    var _wifiError: String? = nil
    var _wifiRefreshTimer: DispatchSourceTimer?

    // Texture IDs for process-based apps (for cleanup on window close)
    var processTextureIds: [String: Int64] = [:]

    // App IDs currently being launched (child started but first frame not yet received)
    private var _pendingAppLaunches: Set<String> = []

    // Cache inner window widgets to avoid full subtree rebuilds during drag.
    // When only position changes, the cached widget instance is reused (===),
    // so updateChild short-circuits and skips rebuilding the entire window subtree.
    // The `isFullscreen` and `isTopBarRevealed` keys force a rebuild when the
    // window changes its fullscreen state or when the auto-hide reveal flips
    // (so the title-bar overlay shows/hides correctly).
    private var _windowChildCache: [String: (widget: DesktopWindow, isFocused: Bool, width: Double, height: Double, isFullscreen: Bool, isTopBarRevealed: Bool)] = [:]

    /// The size a maximised client last committed while disagreeing with the
    /// size we configured. Only there to keep the corrective configure from
    /// firing on every frame a non-compliant client draws — see
    /// `onWindowBufferResized`.
    private var _maximizedSizeSeen: [String: (Int, Int)] = [:]

    /// macOS-style fullscreen auto-hide: when a fullscreen window is on top,
    /// the desktop status bar and the window's title bar are hidden until the
    /// cursor approaches the top edge of the screen. The title bar then
    /// overlays inside the window; non-fullscreen windows always show it.
    private var _topBarRevealed: Bool = false
    /// Same treatment for the dock: hidden while a fullscreen window is on
    /// top, revealed while the cursor is in its band at the bottom edge.
    private var _dockRevealed: Bool = false

    // Popup tracking: popupId → (textureId, parentSurfaceId, x, y, width, height, mapped)
    // mapped=false until first buffer commit (Hyprland-style: don't render until content ready)
    var popups: [String: (textureId: Int, parentSurfaceId: UInt32, x: Double, y: Double, width: Double, height: Double, mapped: Bool)] = [:]


    // Screen dimensions — the logical size of the HOST output, i.e. the panel
    // this widget tree is actually rendered onto. Backed by the display layout
    // (virtual desktop); falls back to the implicit view / DPI on the
    // macOS/GLFW dev paths where no layout is built. At N=1 the host output is
    // the whole panel, so this equals the previous computation.
    //
    // The host, deliberately, not `dl.primary`: the user can make a different
    // monitor primary, and this tree still draws on the one the engine gave it.
    // Reading the primary's size here would lay the whole shell out against a
    // panel it is not on.
    // (Per-output chrome/window layout migrates individual call sites off these
    // host-only scalars in later slices.)
    var screenWidth: Double {
        if let dl = displayLayout { return dl.host.logicalWidth }
        return (PlatformDispatcher.instance.implicitView?.physicalSize.width ?? 3840.0) / currentShellDpi
    }
    var screenHeight: Double {
        if let dl = displayLayout { return dl.host.logicalHeight }
        return (PlatformDispatcher.instance.implicitView?.physicalSize.height ?? 2160.0) / currentShellDpi
    }

    // ── Apps ─────────────────────────────────────────────────────────────
    // There is no app table here, and there must not be one. Every app the
    // desktop knows about — its name, tile colour, icon, how it installs, how
    // it launches, and which window class its windows report — comes from the
    // registry: the shipped catalog in registry/catalog.d plus the records
    // app-install writes when an install succeeds. The App Store reads the
    // same records, so the two cannot disagree, and an install shows up here
    // without a relogin (see the watch set up in initState).
    //
    // The launcher shows every installed app; the dock shows the subset the
    // catalog marks as default, plus whatever the user pinned, plus transient
    // icons for running apps.

    /// Dock order, as app ids — mutable for drag-to-reorder and Remove from
    /// Dock. Seeded from the registry's default dock, which is already
    /// filtered to what is installed: a given build may not ship every
    /// first-party app (a dev stage carries only what was built), and a dock
    /// tile that launches nothing is worse than an absent one. Filtering at
    /// seed time
    /// rather than at display time keeps drag-to-reorder honest — those
    /// indices address dockAppOrder directly.
    var dockAppOrder: [String] = AppRegistry.shared.defaultDock.map { $0.id }

    /// Apps the user took out of the dock by hand. Remembered so that
    /// re-deriving the dock after a registry change can restore an app that
    /// came back without resurrecting one the user deliberately removed.
    private var _dockRemovedByUser: Set<String> = []

    /// What the shell knows about each app's liveness.
    ///
    /// The shell is the only process that sees every window and every launch,
    /// so it is the one that maintains this — the dock reads it, and the App
    /// Store subscribes to it over the broker socket rather than working it
    /// out a second time and drifting.
    ///
    /// Two facts, because they answer different questions. `window` is what
    /// the dock means by running (macOS: an app is running when it has a
    /// window) and drives the transient icon and the indicator dot.
    /// `process` is the stronger one the App Store needs before it removes a
    /// package: an Electron app with every window closed still has a zygote
    /// holding its files open, and apt deleting them underneath it leaves a
    /// half-uninstalled app.
    struct AppLiveness: Equatable {
        var window = false
        var process = false
    }
    /// Only apps that are live in some sense appear here.
    private(set) var appLiveness: [String: AppLiveness] = [:]

    // Dock drag-to-reorder state
    private var _dockDragIndex: Int? = nil       // index being dragged
    private var _dockDragStartX: Double = 0      // pointer X at drag start
    private var _dockDragCurrentX: Double = 0    // current pointer X
    private var _dockDragCurrentY: Double = 0    // current pointer Y
    private var _dockDragActive: Bool = false     // drag threshold exceeded

    // Dock icon context menu (right-click on an icon). The anchor X is the
    // icon's slot center captured at open time, so the menu stays put while
    // hover magnification relaxes underneath the dismiss barrier.
    private var _dockMenuAppId: String? = nil
    private var _dockMenuAnchorX: Double = 0

    // IME (fcitx5, toggled with Ctrl+Space). The shell draws the preedit +
    // candidate panel itself — fcitx runs headless and answers over DBus.
    var imeIntegration: ImeIntegration? = nil
    private var _imeEnabled = false
    private var _imePreedit = ""
    private var _imeCandidates: [(String, String)] = []
    private var _imeHighlighted = -1
    // Latest caret reported by a child app (texture id + rect in the child's
    // logical content coords) — anchors the IME panel next to the text caret.
    private var _imeCaret: (textureId: Int64, rect: Rect, visible: Bool)? = nil
    // The window the current composition targets; a focus change resets it.
    private var _imeTargetWindowId: String? = nil
    // Focused Wayland client's text-input state (windowId + cursor rect in
    // surface-local logical coords) — commits route to it, panel anchors it.
    private var _imeWaylandTI: (windowId: String, enabled: Bool, rect: Rect)? = nil

    // Dock hover-magnification state (macOS style). Pointer X in logical
    // screen coordinates while the cursor is over the dock strip; nil when
    // it isn't. Icon scales are a pure function of this — cursor-driven,
    // like macOS, rather than time-animated.
    private var _dockHoverX: Double? = nil

    // Liquid-glass refraction shader. The program is loaded lazily once; the
    // dock and the status-bar popup each mint their OWN shader instance so
    // the per-build uniform writes (panel rect) never clobber each other
    // when both panels are on screen in the same frame.
    private var _glassProgram: FragmentProgram?
    private var _glassProgramTried = false
    private var _dockGlassShader: FragmentShader?
    private var _popupGlassShader: FragmentShader?

    // Measured heights of the intrinsically-sized status popups, fed to the
    // liquid-glass shader as exact geometry. Populated by MeasureSize on the
    // popup's first layout (that first frame renders with the plain-frost
    // fallback, then the refraction kicks in).
    private var _statusPopupHeights: [StatusBarPopup: Double] = [:]

    // Windows currently playing their close animation. Teardown (destroy
    // app/texture, remove from the window manager) is deferred until the
    // animation completes so the window shrinks with live content.
    private var _closingWindows: Set<String> = []

    // Windows currently playing the scale-effect minimize (flying into
    // their dock icon). The actual minimize is deferred until it lands.
    private var _minimizingWindows: Set<String> = []

    // Frame tick for tooling (tools/shell-drive.py): SIGRTMIN+2 requests a
    // *presented* frame. Screenshots and the recording toggle are consumed
    // in the engine's present callback, but an idle scheduled frame with no
    // damage never presents — so the tick dirties a 1px invisible corner
    // overlay to force one. The signal handler just sets a flag; a 100ms
    // GCD timer polls it (signal handlers can't touch widget state).
    /// eventfd the forced-frame signal writes to, and a static copy of it so
    /// the signal handler (which cannot capture context) can reach it.
    var _frameTickEventFd: Int32 = -1
    nonisolated(unsafe) static var _frameTickFd: Int32 = -1
    private var _frameTick: Int = 0
    private var _frameTickTimer: DispatchSourceTimer?
    /// Whether the frame pump is running at its full rate.
    ///
    /// The pump exists for riders that need a liveness floor -- a screen
    /// capture, a recording, RDP -- and at idle it has none, so every one of
    /// its 30 wakeups a second found nothing to do and went back to sleep.
    /// That is not free: each is a timerfd re-arm, an epoll round trip and a
    /// context switch, and at idle it was most of what the main thread cost.
    /// The rate now follows the riders.
    private var _pumpFast = false
    /// Whether the pump is currently scheduled at all, and whether the
    /// DispatchSource has been resumed (suspend/resume must be balanced).
    /// STARLING_PUMP_LOG=1: one line whenever the frame pump arms or stops,
    /// naming which rider asked for it. "Why is an idle desktop still
    /// presenting" is otherwise unanswerable from outside.
    nonisolated(unsafe) static let _pumpLog =
        (ProcessInfo.processInfo.environment["STARLING_PUMP_LOG"] ?? "") == "1"
    private var _pumpRunning = false
    private var _pumpResumed = false

    // Screen recording: 1s repaint tick for the indicator's elapsed time
    // (fires only while recording), and the id counter for shell-posted
    // notifications — high range, disjoint from the daemon's allocator,
    // which counts up from 1 and cannot plausibly reach 2^31.
    private var _recordingTickTimer: DispatchSourceTimer?
    private var _localNoteId: UInt32 = 0x8000_0000

    // Modifier key tracking for keyboard shortcuts (Ctrl+Tab, etc.)
    private var _ctrlPressed: Bool = false
    private var _shiftPressed: Bool = false
    private var _altPressed: Bool = false
    private var _superPressed: Bool = false

    // ── Spaces (virtual desktops) ────────────────────────────────────────
    // macOS-style horizontal slide between spaces. While a slide is running,
    // build() renders BOTH spaces' wallpaper + windows in one flat Stack,
    // offset by the eased progress; the status bar and dock stay put. The
    // model (windowManager.activeSpaceIndex) flips at slide START — the
    // animation is purely visual. Keyed by space ID (not index) so a space
    // removed mid-slide degrades to a steady frame instead of mislabeling.
    // `dir` is +1 sliding toward a space on the right, -1 to the left.
    // `carried` pins one window at dx 0 during the slide — the window being
    // edge-drag-carried stays under the cursor while the desktop slides
    // behind it (macOS).
    private var _spaceSlide: (fromId: Int, toId: Int, dir: Double, carried: String?)? = nil
    private var _spaceSlideController: AnimationController?
    private var _spaceSlideCurve: CurvedAnimation?

    // ── Workspace mode ───────────────────────────────────────────────────
    // A driver app with whatever it opens beside it. Independent of the AI
    // Space below — it shares the "special space" mechanism and nothing else.
    // UI lives in WorkspaceSpace.swift; stored state has to be here because
    // extensions cannot add stored properties.
    /// Explicitly selected tab per workspace (workspaceId → windowId).
    /// Absent or stale = follow the workspace: newest window wins.
    var _workspaceActiveTab: [String: String] = [:]
    /// Serial for pane app ids, so a SECOND copy of the same app in one
    /// workspace gets its own identity. See `_launchIntoWorkspace`.
    var _wsPaneSerial: Int = 0
    /// Set while the launcher is filling a workspace's driver slot, so the
    /// app it launches lands in the middle column instead of on the desktop.
    var _launcherDriverTarget: String? = nil
    /// Live width of the driver column; the divider drags it.
    /// The output the workspace-UI build currently underway is for — inner
    /// builders (the rail) read the per-output selection through it. Pinned
    /// by `_buildWorkspaceSpace(output:)`; builds are single-threaded.
    var _wsBuildOutputId: Int = 0

    /// Last pointer position seen anywhere in the shell tree, in host-output
    /// logical px. Recorded by a translucent Listener at the root, so it
    /// sees motion over windows and panes too rather than only the parts of
    /// the wallpaper nothing claimed. Recording zoom centres on it.
    var _lastPointer: Offset = Offset(0, 0)

    /// `_lastPointer` as fractions of the screen — the coordinates the
    /// recording zoom consumes (`stepZoom` at the key, follow in the pump).
    var _pointerFraction: (x: Double, y: Double) {
        (x: _lastPointer.dx / max(screenWidth, 1),
         y: _lastPointer.dy / max(screenHeight, 1))
    }

    /// Open workspace context menu: a tab's (window id) or the left column's
    /// (workspace id). At most one is non-nil; both nil means no menu.
    var _wsTabMenuWinId: String? = nil
    var _wsDriverMenuWsId: String? = nil
    var _wsMenuAt: Offset = Offset(0, 0)
    /// Whether the left column — the agent you are talking to — is folded
    /// away, leaving its windows the whole panel. One flag, not per
    /// workspace: there is one workspace.
    var _wsDriverHidden: Bool = false

    /// Where each output returns when its workspace toggles off, keyed by
    /// output id (each monitor runs its own workspace now).
    var _workspaceReturnByOutput: [Int: Int] = [:]

    /// The output the pointer is currently over, as reported by each output's
    /// screen. Not `setState`-tracked: nothing renders from it directly, it
    /// only decides where the next workspace toggle lands.
    var _pointerOutputId: Int? = nil

    /// Called by every output's screen as the pointer moves over it.
    func notePointerOutput(_ outputId: Int) {
        _pointerOutputId = outputId
    }

    /// Which output the launcher is drawn on. It follows whatever opened it —
    /// the dock lives on the primary, but the workspace's `+` buttons do not,
    /// and an app picker that opens on a different monitor from the thing that
    /// asked for it is worse than no multi-output support at all.
    var _launcherOutputId: Int = 0

    /// Open the launcher on the output the request came from. Every call site
    /// goes through here; setting `_launcherOpen` directly leaves the picker on
    /// whichever monitor it happened to be on last.
    func openLauncher(driverTarget: String? = nil) {
        _launcherOutputId = _pointerOutputId ?? displayLayout?.primary.id ?? 0
        setState {
            _launcherDriverTarget = driverTarget
            _launcherQuery = ""
            _launcherOpen = true
            contextMenuPosition = nil
            activeStatusBarPopup = nil
        }
        // The pill is focused the moment it appears; start the caret so it
        // says so.
        _restartLauncherCaret()
    }

    /// Width of the left column. Wide by default: it holds the agent you are
    /// talking to, and reading its reasoning is the point of watching — a
    /// narrow column renders Claude Desktop below its own 948px minimum and
    /// scales it down, which is exactly the text you want legible. The tab
    /// pane keeps the rest, which at 4K is still most of the screen.
    var _workspaceDriverW: Double = 860
    /// True between pointer-down and pointer-up on the divider.
    var _workspaceDividerDragging: Bool = false

    // ── Broker-owned windows ─────────────────────────────────────────────
    // The persistent agent space holds the fleet UI instead of windows; it
    // is entered by Ctrl+Down / context menu only (never by Ctrl+arrow/Tab
    // cycling). Stored here because extensions can't add stored properties;
    // the UI lives in AgentSpace.swift.
    /// Wayland ownership hand-off (P4): set right before spawning a
    /// Wayland client (Chrome via app-run) for an agent. The first toplevel
    /// that arrives consumes it AND records the client connection in
    /// _agentWaylandClients — every later toplevel from that client
    /// (new windows, undocked devtools) is claimed for the same agent.
    var _pendingAgentWayland: (agentId: String, onWindow: ((String) -> Void)?)? = nil
    /// Wayland client connection → owning agent (ownership by launch
    /// chain: the wl_client identity, never process trees). Pruned when the
    /// client disconnects — the key is a pointer value and is reusable the
    /// moment it does.
    var _agentWaylandClients: [UInt64: String] = [:]
    /// Last frame-throttle interval applied per agent window (diff guard —
    /// the policy is re-evaluated on every fleet build).
    var _agentThrottleApplied: [String: UInt32] = [:]
    /// Content size an agent window was BORN with (the workspace pane),
    /// seeded at claim time and consumed by the window's first buffer
    /// commit: a client that mapped at some other size is re-asserted the
    /// birth size exactly once (see onWindowBufferResized).
    var _agentSizeApplied: [String: Size] = [:]
    /// True while the divider is being dragged: window re-configures are
    /// deferred to the drop, so clients reflow once instead of per frame.
    var _agentDividerDragging: Bool = false
    /// 1s tick that refreshes tile status text (working/idle) while the
    /// a workspace is visible — texture updates alone don't rebuild widgets.
    var _spaceRepaintTimer: DispatchSourceTimer? = nil
    #if os(Linux)
    /// The P1 agent broker: JSON-lines socket at
    /// $XDG_RUNTIME_DIR/starling-agent.sock. Every agent action crosses it.
    var _agentBroker: AgentBroker? = nil
    #endif

    /// Broker quiescence signal (await_settled v0): true when no shell-side
    /// animation is in flight. Frame-quiet per window is tracked by the
    /// broker itself from child frame signals.
    var _shellQuiescent: Bool {
        _spaceSlide == nil && _windowRectAnims.isEmpty
            && _closingWindows.isEmpty && _minimizingWindows.isEmpty
            && !_missionControlOpen
    }

    // ── Mission Control ──────────────────────────────────────────────────
    // Modal spaces overview (Ctrl+Up / context menu): spaces strip with
    // live thumbnails + "+" tile on top, the active space's windows spread
    // in an exposé grid below. While open, the normal desktop layers
    // (windows, popups, status bar) are not rendered — each window mounts
    // exactly once, inside the exposé. Stored here (not in the extension)
    // because Swift extensions cannot add stored properties; the UI lives
    // in MissionControl.swift.
    /// Frame-pump tick counter — see the frame-tick timer. The pump is a
    /// liveness floor: it forces a rebuild every `kPumpFloorTicks` ticks
    /// (33ms each) and otherwise stays out of the way so content-driven
    /// presents get the pipeline.
    var _pumpTicks = 0
    /// ~250ms. Long enough that a rebuild (~100ms at 4K) is not always in
    /// flight, short enough that a stop request is consumed promptly.
    static let kPumpFloorTicks = 8

    var _missionControlOpen = false
    /// The monitor Mission Control was invoked on — its windows, its space
    /// strip actions, its geometry. The overview draws in that output's tree.
    var _missionControlOutputId: Int = 0
    /// Whether Mission Control belongs to the host tree right now.
    var mcIsOnHost: Bool {
        _missionControlOutputId == (displayLayout?.host.id ?? 0)
    }

    /// The MC output resolved against the live layout (host fallback).
    var missionControlOutput: DisplayOutput {
        displayLayout?.outputs.first(where: { $0.id == _missionControlOutputId })
            ?? displayLayout?.host
            ?? DisplayOutput(id: 0, name: "primary",
                             physicalWidth: Int(screenWidth * currentShellDpi),
                             physicalHeight: Int(screenHeight * currentShellDpi),
                             scale: currentShellDpi, originX: 0, originY: 0,
                             isHost: true, isPrimary: true, refreshMhz: 60000)
    }
    var _mcOpenController: AnimationController?
    var _mcOpenCurve: CurvedAnimation?
    /// Record-App picker: Mission Control opened to CHOOSE a recording
    /// target rather than to navigate. The spaces strip and card drags are
    /// disabled; clicking a card starts recording that window; Esc or the
    /// backdrop cancels. Set only through _openMissionControl.
    var _mcPickRecordTarget = false
    /// True while the exposé is animating back to the desktop (controller
    /// running in reverse); the real teardown happens at dismissed.
    var _mcClosing = false
    /// Grid re-flow tween after a drop/removal: each surviving card lerps
    /// from its old grid rect to the new one, and the dropped card flies
    /// into its mini-rect inside the target thumbnail.
    var _mcRelayoutFrom: [String: Rect] = [:]
    var _mcDeparting: (id: String, from: Rect, to: Rect)? = nil
    var _mcRelayoutController: AnimationController?
    var _mcRelayoutCurve: CurvedAnimation?
    /// In-flight exposé card drag: window id, press origin, live pointer
    /// position, and whether the movement threshold was crossed (below it
    /// the release is a click that focuses the window).
    var _mcDragWindowId: String? = nil
    var _mcDragStart: Offset? = nil
    var _mcDragPos: Offset? = nil
    var _mcDragMoved = false

    // ── Edge-drag carry ──────────────────────────────────────────────────
    // Dragging a window and holding the pointer against the left/right
    // screen edge for a dwell carries the window to the adjacent space
    // (macOS). Pointer position comes from the topmost translucent
    // listener (it is in every pointer's hit path, so it keeps receiving
    // move events during window drags). The dwell uses asyncAfter with a
    // generation token — Foundation.Timer never fires on the DRM embedder.
    private var _dragPointerPos: Offset? = nil
    private var _edgeCarryToken: Int = 0
    private var _edgeCarryArmedDir: Int = 0
    private let _edgeCarryDwellMs = 400
    private let _edgeCarryZonePx = 3.0

    // ── Window rect animation (fullscreen zoom) ──────────────────────────
    // One controller per animating window; a retarget cancels the old run.
    private var _windowRectAnims: [String: AnimationController] = [:]

    // ── Screensaver ──────────────────────────────────────────────────────
    // Appears on its own after `_screensaverIdleSeconds` without input, and
    // on Ctrl+Shift+S (or STARLING_SCREENSAVER_TEST=<seconds> for tooling).
    // The overlay warps the LIVE desktop through a BackdropFilter — no
    // capture step — so the machinery here is a fade controller, a monotonic
    // time Ticker for the shader phases, the idle timer, and teardown.
    var _screensaverActive = false              // overlay mounted (broker-visible)
    private var _screensaverClosing = false     // reverse fade in flight
    private var _screensaverFade: AnimationController?
    private var _screensaverFadeCurve: CurvedAnimation?
    private var _screensaverTicker: Ticker?     // uTime driver
    private var _screensaverTime: Double = 0    // seconds since activation
    private var _screensaverShownAt = Date.distantPast  // input-grace anchor
    private var _screensaverTestToken = 0       // env auto-activate generation
    private var _screensaverProgram: FragmentProgram?
    private var _screensaverProgramTried = false
    private var _screensaverShader: FragmentShader?

    // Aerial mode: a looping clip decoded by a spawned ffmpeg (AerialPlayer),
    // cross-fading in over the warp once its first frame lands. Absent any
    // installed clip these stay nil and the warp is the whole screensaver.
    #if os(Linux)
    private var _aerialPlayer: AerialPlayer?
    #endif
    private var _aerialTextureId: Int64 = -1
    private var _aerialFirstFrameAt: Double = -1   // _screensaverTime of frame 1

    /// Where the pointer was when the saver first saw it; wake once it has
    /// travelled this far (logical px) from there.
    private var _screensaverPointerOrigin: Offset?
    private static let kScreensaverWakeDistance: Double = 24

    // ── Idle detection ───────────────────────────────────────────────────
    /// Seconds of no input before the saver appears; 0 disables it entirely.
    /// Loaded from `~/.config/starling/screensaver` at mount, changed by the
    /// Settings app's Screensaver picker.
    var _screensaverIdleSeconds: Double = kDefaultIdleSeconds
    static let kDefaultIdleSeconds: Double = 600   // 10 minutes, like macOS
    /// Last deliberate user input, from the shell's global pointer listener
    /// and the key hook — both see every event, including ones destined for
    /// Wayland/X11 clients, because client windows are textures in this tree.
    private var _lastInputActivity = Date()
    /// Generation token for the re-arming idle check (see `_armIdleTimer`).
    private var _idleTimerToken = 0
    /// Whether the last idle check found a client holding the screensaver
    /// off, so the check that finds the inhibitor gone can start a fresh
    /// full period rather than resuming a nearly-expired one.
    private var _idleWasInhibited = false

    /// Whether some client is currently holding the screensaver off. Read by
    /// the broker's `screensaver` op so the functional tier can tell "the
    /// timer hasn't fired yet" from "a client is suppressing it".
    var _screensaverInhibited: Bool {
        #if os(Linux)
        return waylandIntegration?.idleInhibited == true
        #else
        return false
        #endif
    }

    // Cached — the saver rebuilds every frame, and a per-build DateFormatter
    // (ICU setup) is real work. Only ever touched from the main queue.
    nonisolated(unsafe) private static let _ssTimeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm"; return f
    }()
    nonisolated(unsafe) private static let _ssAmpmFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "a"; return f
    }()
    nonisolated(unsafe) private static let _ssDateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"; return f
    }()

    func _activateScreensaver() {
        guard !_screensaverActive else { return }
        if _missionControlOpen { _closeMissionControl() }
        setState {
            _screensaverActive = true
            _screensaverClosing = false
            _screensaverTime = 0
            // Wake to a clean desktop: close anything modal now rather than
            // leaving it parked under the saver.
            _launcherOpen = false
            activeStatusBarPopup = nil
            contextMenuPosition = nil
        }
        _screensaverShownAt = Date()
        _screensaverPointerOrigin = nil
        if _screensaverFade == nil {
            let c = AnimationController(duration: .milliseconds(700),
                                        reverseDuration: .milliseconds(150),
                                        vsync: self)
            c.addListener { [weak self] in self?.setState {} }
            c.addStatusListener { [weak self] status in
                // Reverse run finished — the desktop is fully back.
                guard let self, status == .dismissed, self._screensaverClosing
                else { return }
                self._teardownScreensaver()
            }
            _screensaverFade = c
            _screensaverFadeCurve = CurvedAnimation(parent: c,
                                                    curve: Curves.easeOutCubic)
        }
        // Monotonic seconds for the shader phases — a repeating controller
        // would wrap into a sawtooth and pop every period.
        _screensaverTicker?.stop()
        _screensaverTicker = Ticker({ [weak self] elapsed in
            guard let self else { return }
            let comps = elapsed.components
            self._screensaverTime = Double(comps.seconds)
                + Double(comps.attoseconds) * 1e-18
            self._pumpAerialFrame()
            self.setState {}
        }, debugLabel: "screensaver time")
        _ = _screensaverTicker?.start()
        _ = _screensaverFade?.forward(from: 0)
        _startAerialIfAvailable()
    }

    /// Start decoding an aerial clip, if one is installed. Frames are decoded
    /// at the size they are SHOWN (STARLING_AERIAL_RES, default half the
    /// panel): a 4K RGBA frame is 33MB, and the CPU pipe cannot carry that —
    /// see AerialPlayer's note on the VAAPI/dmabuf path this stands in for.
    private func _startAerialIfAvailable() {
        #if os(Linux)
        guard _aerialPlayer == nil, let clip = AerialPlayer.discoverClip() else { return }
        // PHYSICAL pixels, not screenWidth/screenHeight — those are logical
        // (1280x800 on this 2560x1600 panel at DPI 2), and decoding to
        // logical size would upscale 4x on screen.
        //
        // Native panel resolution is affordable: measured on the dev box,
        // decoding the 4K NASA clip down to 2560x1600 RGBA runs at 4.3x
        // realtime (1.16s of CPU per 5s of video), and a pre-scaled source
        // at 5.7x. Decode is never the constraint — glTexImage2D of a 16MB
        // frame is, so STARLING_AERIAL_RES exists to step down if the
        // upload can't keep pace on a given box.
        let phys = PlatformDispatcher.instance.implicitView?.physicalSize
            ?? Size(screenWidth, screenHeight)
        var w = Int(phys.width), h = Int(phys.height)
        if let res = ProcessInfo.processInfo.environment["STARLING_AERIAL_RES"] {
            let parts = res.lowercased().split(separator: "x").compactMap { Int($0) }
            if parts.count == 2, parts[0] > 0, parts[1] > 0 {
                w = parts[0]; h = parts[1]
            }
        }
        guard let player = AerialPlayer(clip: clip, width: w, height: h) else {
            FileHandle.standardError.write(Data(
                "[DesktopShell] Aerial: ffmpeg unavailable — staying on the warp\n".utf8))
            return
        }
        FileHandle.standardError.write(Data(
            "[DesktopShell] Aerial: \(clip) at \(player.width)x\(player.height)\n".utf8))
        _aerialPlayer = player
        _aerialFirstFrameAt = -1
        player.start()
        #endif
    }

    /// Drain the decoder's mailbox into the aerial texture. Called from the
    /// screensaver ticker, so uploads happen on the main thread at frame
    /// cadence and the decode thread never touches engine state.
    private func _pumpAerialFrame() {
        #if os(Linux)
        guard let player = _aerialPlayer,
              let registry = drmTextureRegistry,
              let wl = waylandIntegration else { return }
        player.withNewFrame { data, w, h in
            if _aerialTextureId < 0 {
                _aerialTextureId = registry.registerTexture(engine: wl.engine)
                _aerialFirstFrameAt = _screensaverTime
            }
            registry.updatePixelData(engine: wl.engine, id: _aerialTextureId,
                                     data: data, width: w, height: h)
        }
        #endif
    }

    /// 0 until the first decoded frame, then a 1.5s ramp — the aerial
    /// dissolves in over the warped desktop rather than cutting to it.
    private var _aerialFadeT: Double {
        guard _aerialTextureId >= 0, _aerialFirstFrameAt >= 0 else { return 0 }
        return min(1.0, max(0.0, (_screensaverTime - _aerialFirstFrameAt) / 1.5))
    }

    private func _stopAerial() {
        #if os(Linux)
        _aerialPlayer?.stop()
        _aerialPlayer = nil
        if _aerialTextureId >= 0, let registry = drmTextureRegistry,
           let wl = waylandIntegration {
            registry.unregisterTexture(engine: wl.engine, id: _aerialTextureId)
        }
        #endif
        _aerialTextureId = -1
        _aerialFirstFrameAt = -1
    }

    func _dismissScreensaver() {
        guard _screensaverActive, !_screensaverClosing else { return }
        _screensaverClosing = true
        _ = _screensaverFade?.reverse()
    }

    /// Pointer or key activity while the saver is up. The grace window
    /// absorbs the activation chord's own repeat tail and any synthetic
    /// hover fired as the overlay mounts under the cursor.
    private func _screensaverInputWake() {
        guard Date().timeIntervalSince(_screensaverShownAt) > 0.35 else { return }
        _dismissScreensaver()
    }

    /// Pointer drift while the saver is up. A hand resting on a trackpad
    /// emits hover events a pixel at a time (and plugging in a device emits
    /// one on its own), so waking on the first of those dismissed the
    /// screensaver the moment it appeared — it never survived long enough to
    /// be seen. Wake only once the pointer has actually travelled.
    private func _screensaverPointerActivity(_ pos: Offset) {
        guard _screensaverActive, !_screensaverClosing else { return }
        guard Date().timeIntervalSince(_screensaverShownAt) > 0.35 else { return }
        guard let origin = _screensaverPointerOrigin else {
            _screensaverPointerOrigin = pos
            return
        }
        let dx = pos.dx - origin.dx, dy = pos.dy - origin.dy
        if dx * dx + dy * dy > Self.kScreensaverWakeDistance * Self.kScreensaverWakeDistance {
            _dismissScreensaver()
        }
    }

    private func _teardownScreensaver() {
        _screensaverTicker?.stop()
        _screensaverTicker = nil
        _stopAerial()
        setState {
            _screensaverActive = false
            _screensaverClosing = false
        }
        // The wake itself is the newest activity — without this the idle
        // clock still reads "hours", and the saver would come straight back.
        // `_checkIdle` bails while the saver is up, so this is also the one
        // place that restarts the idle cycle after a wake.
        _noteUserActivity()
        if _screensaverIdleSeconds > 0 { _armIdleTimer(after: _screensaverIdleSeconds) }
        _armScreensaverTestTimer()  // self-repeating test cycles
    }

    // ── Idle detection ───────────────────────────────────────────────────

    /// Deliberate user input. Called from the shell's topmost global pointer
    /// listener and from the key hook, which between them see every event —
    /// including those forwarded to Wayland and X11 clients, because client
    /// windows are textures inside this widget tree.
    ///
    /// This is on the hot path for every pointer move, so it does exactly one
    /// thing: stamp a Date. The timer is NOT re-armed here (that would queue a
    /// wakeup per mouse move); it re-arms itself when it finds the desktop
    /// still busy.
    func _noteUserActivity() {
        _lastInputActivity = Date()
    }

    /// Arm the idle check `seconds` from now. One timer is in flight at a
    /// time: the generation token invalidates the previous one, so a settings
    /// change or a wake can safely re-arm without stacking.
    ///
    /// `DispatchQueue.main.asyncAfter`, not `Foundation.Timer` — the latter
    /// never fires on the DRM embedder.
    private func _armIdleTimer(after seconds: Double) {
        _idleTimerToken += 1
        let token = _idleTimerToken
        let fire: () -> Void = { [weak self] in
            guard let self, token == self._idleTimerToken else { return }
            self._checkIdle()
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(1.0, seconds),
            execute: unsafeBitCast(fire, to: (@Sendable () -> Void).self))
    }

    /// Has the desktop been idle long enough? Re-arms for whatever time is
    /// left, so the common case (a busy desktop) costs one wakeup per idle
    /// period rather than a poll per second.
    private func _checkIdle() {
        guard _screensaverIdleSeconds > 0 else { return }  // disabled
        guard !_screensaverActive else { return }  // teardown re-arms
        let remaining = _screensaverIdleSeconds
            - Date().timeIntervalSince(_lastInputActivity)
        if remaining > 0 {
            _armIdleTimer(after: remaining)
            return
        }
        // A client is playing video (or otherwise asked to stay awake).
        #if os(Linux)
        if waylandIntegration?.idleInhibited == true {
            _idleWasInhibited = true
            _noteUserActivity()
            // Poll sooner than a full period so the release is noticed
            // promptly — otherwise the film can end most of a period before
            // anything here looks again.
            _armIdleTimer(after: min(_screensaverIdleSeconds, 30))
            return
        }
        if _idleWasInhibited {
            // The inhibitor has just gone. Start a FULL period from now
            // rather than resuming whatever was left of the one that was
            // running when playback started: measured on the dev box, the
            // naive version put the screensaver up 13s after a 20s-timeout
            // client died, because the last stamp was already 7s old. What
            // the user experiences is the credits rolling and the desktop
            // vanishing seconds later.
            _idleWasInhibited = false
            _noteUserActivity()
            _armIdleTimer(after: _screensaverIdleSeconds)
            return
        }
        #endif
        _activateScreensaver()  // teardown re-arms on wake
    }

    /// Change the idle timeout (Settings' Screensaver picker) and persist it.
    /// 0 turns the screensaver off; a saver already on screen stays up until
    /// the user dismisses it — switching the setting is not a wake gesture.
    func _setScreensaverIdle(seconds: Double) {
        let clean = seconds <= 0 ? 0 : max(10, seconds)
        guard clean != _screensaverIdleSeconds else { return }
        _screensaverIdleSeconds = clean
        #if os(Linux)
        linuxProcessAppManager?.broadcastScreensaver(seconds: Int(clean))
        #endif
        let path = Self._screensaverFile
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try? String(Int(clean)).write(toFile: path, atomically: true,
                                      encoding: .utf8)
        _noteUserActivity()
        if clean > 0 { _armIdleTimer(after: clean) }
    }

    private static var _screensaverFile: String {
        LoginUser.configDir + "/screensaver"
    }

    // MARK: Remote desktop (Settings › Sharing)

    private static var _remoteDesktopFile: String {
        LoginUser.configDir + "/remote-desktop"
    }

    /// Turn remote desktop on or off and persist the choice. The switch
    /// reports what the listener actually did, not what was asked for: a
    /// start can fail (no certificate, port taken), and a switch that sprang
    /// back to "on" over a dead listener would be worse than the failure.
    ///
    /// Off by default, and deliberately: share mode is TLS without NLA, so
    /// anyone who can reach the port can drive this desktop. The pane says
    /// so; see docs/plans/rdp.md.
    func _setRdpEnabled(_ enabled: Bool) {
        #if os(Linux)
        guard let rdp = rdpService else { return }
        let settled: Bool
        if enabled {
            settled = rdp.start()
        } else {
            rdp.stop()
            settled = false
        }
        if settled == enabled {
            try? FileManager.default.createDirectory(
                atPath: (Self._remoteDesktopFile as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)
            try? String(settled ? "1" : "0").write(
                toFile: Self._remoteDesktopFile, atomically: true, encoding: .utf8)
        }
        _broadcastRdpStatus()
        #endif
    }

    /// Push the listener's real state to every child, so the Sharing switch
    /// follows a failed start and a session-wide STARLING_RDP alike.
    func _broadcastRdpStatus() {
        #if os(Linux)
        guard let rdp = rdpService else { return }
        linuxProcessAppManager?.broadcastRdp(enabled: rdp.isRunning)
        #endif
    }

    /// Restore the persisted remote-desktop choice at startup. `STARLING_RDP`
    /// has already had its say by now (RdpService.startIfEnabled), and stays
    /// the override: it turns the listener on regardless of the stored value.
    func _restoreRdpSetting() {
        #if os(Linux)
        guard let rdp = rdpService else { return }
        if !rdp.isRunning,
           let s = try? String(contentsOfFile: Self._remoteDesktopFile,
                               encoding: .utf8),
           s.trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
            _ = rdp.start()
        }
        _broadcastRdpStatus()
        #endif
    }

    /// Restore the persisted idle timeout and start the clock. The env
    /// override exists so tooling and demos can ask for a short timeout
    /// without writing to the user's config.
    private func _startIdleDetection() {
        if let s = try? String(contentsOfFile: Self._screensaverFile,
                               encoding: .utf8),
           let secs = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            _screensaverIdleSeconds = secs <= 0 ? 0 : max(10, secs)
        }
        if let env = ProcessInfo.processInfo.environment["STARLING_SCREENSAVER_IDLE"],
           let secs = Double(env) {
            _screensaverIdleSeconds = secs <= 0 ? 0 : max(10, secs)
        }
        #if os(Linux)
        linuxProcessAppManager?.currentScreensaverIdle = Int(_screensaverIdleSeconds)
        #endif
        _noteUserActivity()
        guard _screensaverIdleSeconds > 0 else { return }
        _armIdleTimer(after: _screensaverIdleSeconds)
    }

    /// STARLING_SCREENSAVER_TEST=<seconds>: auto-activate that long after
    /// startup (and again after every wake), so tooling can screenshot the
    /// saver without holding a keyboard. DispatchQueue + generation token,
    /// not Foundation.Timer — the latter never fires on the DRM embedder.
    private func _armScreensaverTestTimer() {
        guard let s = ProcessInfo.processInfo.environment["STARLING_SCREENSAVER_TEST"],
              let secs = Double(s), secs > 0 else { return }
        _screensaverTestToken += 1
        let token = _screensaverTestToken
        let fire: () -> Void = { [weak self] in
            guard let self, token == self._screensaverTestToken,
                  !self._screensaverActive else { return }
            self._activateScreensaver()
        }
        // Main-queue-only state; @Sendable coercion is the codebase idiom.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + secs,
            execute: unsafeBitCast(fire, to: (@Sendable () -> Void).self))
    }

    // ── Key repeat synthesis ─────────────────────────────────────────────
    // The DRM embedder emits only down/up; typematic repeat is synthesized
    // here (vsync Ticker) and routed like a real key. Wayland clients are
    // excluded — they run their own repeat from wl_keyboard repeat_info.
    private var _keyRouter: ((KeyData) -> Bool)?
    private var _heldKeyForRepeat: KeyData?
    private var _repeatTicker: Ticker?
    private var _repeatsFired = 0
    private let _repeatDelayMs: Int64 = 400
    private let _repeatIntervalMs: Int64 = 35

    private func _trackKeyRepeat(_ keyData: KeyData) {
        switch keyData.type {
        case .down:
            // Modifiers and lock keys don't repeat (keysyms 0xFF7F Num_Lock,
            // 0xFFE1-0xFFEE Shift/Ctrl/Alt/Meta/Caps…).
            let sym = keyData.logical
            if sym == 0xFF7F || (0xFFE1 ... 0xFFEE).contains(sym) { return }
            _heldKeyForRepeat = keyData
            _repeatsFired = 0
            _repeatTicker?.stop()
            _repeatTicker = Ticker({ [weak self] elapsed in
                guard let self = self, let held = self._heldKeyForRepeat else { return }
                let comps = elapsed.components
                let ms = comps.seconds * 1_000 + comps.attoseconds / 1_000_000_000_000_000
                guard ms >= self._repeatDelayMs else { return }
                let expected = Int((ms - self._repeatDelayMs) / self._repeatIntervalMs) + 1
                while self._repeatsFired < expected {
                    self._repeatsFired += 1
                    let repeatEvent = KeyData(
                        timeStamp: held.timeStamp,
                        type: .repeat,
                        physical: held.physical,
                        logical: held.logical,
                        character: held.character,
                        synthesized: true,
                        deviceType: held.deviceType
                    )
                    _ = self._keyRouter?(repeatEvent)
                }
            }, debugLabel: "key repeat")
            _ = _repeatTicker?.start()
        case .up:
            if let held = _heldKeyForRepeat, held.physical == keyData.physical {
                _repeatTicker?.stop()
                _repeatTicker = nil
                _heldKeyForRepeat = nil
            }
        case .repeat:
            break
        }
    }

    override func initState() {
        super.initState()
        _shellState = self
        Self.loadPersistedAppearance()
        // Tiling choice persists like appearance; retile on any window
        // lifecycle change so tiled layouts stay current.
        if let s = try? String(contentsOfFile: Self._windowLayoutFile, encoding: .utf8) {
            windowManager.tilingEnabled =
                s.trimmingCharacters(in: .whitespacesAndNewlines) == "tiling"
        }
        #if os(Linux)
        linuxProcessAppManager?.currentLayoutIsTiling = windowManager.tilingEnabled
        #endif
        // Wallpaper choice persists the same way.
        if let s = try? String(contentsOfFile: Self._wallpaperFile, encoding: .utf8),
           let raw = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)),
           let preset = WallpaperPreset(rawValue: raw) {
            wallpaperPreset = preset
        }
        #if os(Linux)
        linuxProcessAppManager?.currentWallpaper = wallpaperPreset.rawValue
        // Seed the style the same way. Without this the mirror stays at 0 and
        // every child that connects is told "macOS" — so the Settings picker
        // came up on the wrong segment on a desktop that had booted into the
        // other style, and looked like the switch had silently failed.
        linuxProcessAppManager?.currentStyleIndex = _styleIndex(shellStyle)
        #endif
        windowManager.onAgentNeedsWorkspace = { [weak self] agentId in
            self?._retryBindAgent(agentId) ?? false
        }
        // A Wayland client gets the keyboard when it gets FOCUS, not when the
        // first key turns up. Chromium routes focus asynchronously, so a
        // client handed wl_keyboard.enter and a key in the same breath drops
        // that key — every prompt this desktop typed into Claude Desktop lost
        // its first character — or, worse, treats it as a global accelerator
        // and opens something. See WaylandIntegration.ensureKeyboardFocus.
        windowManager.onFocusedWindowChanged = { [weak self] winId in
            guard let self,
                  let win = self.windowManager.windows.first(where: { $0.id == winId }),
                  win.appId.hasPrefix("wayland-"),
                  let surface = UInt32(win.appId.dropFirst("wayland-".count))
            else { return }
            waylandIntegration?.focusKeyboard(surfaceId: surface)
        }

        windowManager.onWindowsChanged = { [weak self] in
            guard let self else { return }
            self.windowManager.retileAll(
                screenWidth: self.screenWidth, screenHeight: self.screenHeight)
            // A third-party window can appear without the shell having launched
            // it — the App Store's Open button shells out to app-run itself —
            // so resolve its host icon here rather than only on our own launch
            // paths. Idempotent per app id, so this is a no-op after the first.
            self._loadIconTexturesForRunningApps()
            // A window appearing or going away changes app liveness, and
            // anything subscribed (the App Store) needs to hear about it.
            self._refreshAppLiveness()
        }
        // Both icon fonts, both styles, always — a style switch is then a
        // repaint and not a font load. They carry different family names, so
        // registering both is safe; that has been a bug in this tree before
        // (only the LAST font registered survived) and is worth re-checking
        // if glyphs from one family ever come up empty.
        CupertinoIcons.registerFont()
        FluentSystemIcons.registerFont()
        SelawikFont.registerFont()

        #if os(Linux)
        // The App Store installs and removes apps while the session is
        // running, and app-install writes/deletes a registry record when it
        // does. Watching for that is what makes an install appear in the
        // launcher and the dock immediately instead of at the next login.
        // The handler runs on the main queue and reaches back through
        // _shellState rather than capturing self: the state class is not
        // Sendable (same pattern as the wallpaper and icon decodes).
        AppRegistry.shared.watch {
            guard let shell = _shellState else { return }
            shell.setState { shell._reconcileDock() }
            shell._loadIconTextures()
        }
        #endif

        _setupWaylandCallbacks()  // Try now (may be nil if waylandIntegration not yet set)
        _loadWallpaperTexture()   // Try now (needs waylandIntegration + drmTextureRegistry)
        _loadIconTextures()
        _onWaylandIntegrationReady = { [weak self] in
            self?._setupWaylandCallbacks()
            self?._loadWallpaperTexture()
            self?._loadIconTextures()
        }
        _setupX11Callbacks()  // Try now (may be nil if x11Integration not yet set)
        _onX11IntegrationReady = { [weak self] in
            self?._setupX11Callbacks()
        }

        #if os(Linux)
        // Murmuration P1: the agent broker. Handlers touch shell state, so
        // requests are marshalled onto the main queue inside the broker.
        let broker = AgentBroker()
        broker.start(shell: self)
        _agentBroker = broker

        // Murmuration P2: tile status (working/idle) derives from broker op
        // and frame recency, which don't mark widgets dirty — poke a rebuild
        // once a second while a workspace is on screen.
        // (its timer is created on demand — `_reevaluateShellTimers`)

        // The tooling-forced frame (SIGRTMIN+2 = 36 on glibc; `shell-drive shot`
        // sends it before every screenshot, because an idle desktop presents
        // nothing and the capture would be stale).
        //
        // It goes onto the EVENT LOOP rather than into a flag that something
        // has to notice. `write` is async-signal-safe and the read end is in
        // the DRM epoll set already, so the frame is forced the moment it is
        // asked for -- and costs nothing at all when it is not. Watching for
        // that flag was half the reason the pump ran on an idle desktop.
        //
        // A self-pipe, which is the idiom the X11 wakeup here already uses:
        // Swift's Glibc module does not surface `eventfd`, and a pipe does the
        // same job.
        var tickPipe: [Int32] = [-1, -1]
        if pipe(&tickPipe) == 0 {
            for fd in tickPipe {
                _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
                _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
            }
            _frameTickEventFd = tickPipe[0]
            _DesktopShellState._frameTickFd = tickPipe[1]
            signal(36, { _ in
                var one: UInt8 = 1
                _ = write(_DesktopShellState._frameTickFd, &one, 1)
            })
            if let view = drmViewHandle {
                fl_drm_view_add_external_fd(view, tickPipe[0], { _ in
                    guard let shell = _shellState else { return }
                    var drain = [UInt8](repeating: 0, count: 64)
                    _ = read(shell._frameTickEventFd, &drain, 64)
                    // A forced frame is a rebuild, now, once.
                    shell.setState { shell._frameTick += 1 }
                }, nil)
            }
        }
        // The frame pump: a LIVENESS FLOOR for the things that need presents to
        // keep happening on a desktop where nothing is moving -- a recording, a
        // screencast, an RDP client, an X screen capture. It is created
        // suspended and armed by `_reevaluateFramePump` when one of those
        // starts, so a desktop with none of them running does not tick at all.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.kPumpIdlePeriod,
                       repeating: Self.kPumpIdlePeriod)
        timer.setEventHandler { [weak self] in
            var tick = false
            var rebuild = false
            #if os(Linux)
            // X11 GetImage (Zoom screen share) reads a CPU mirror refreshed
            // per present and has no timeline of its own — a slow floor
            // would show the far end a 4fps desktop, so that path keeps the
            // full-rate rebuild it was written for.
            if fl_drm_view_capture_active() != 0 {
                tick = true
                rebuild = true
            }
            // Recording rides the same pump: presents carry the engine's
            // start/stop requests AND feed the frame mailbox, so it runs
            // from the start tap until the engine confirms the stop. An
            // app recording also checks its window still exists here.
            if recordingService?.needsFramePump == true {
                tick = true
                recordingService?.checkWindowAlive()
                recordingService?.refreshWindowRect()
                // Eases the recorded crop toward its target, and while
                // zoomed pans it to keep the pointer in frame. Cheap and a
                // no-op unless a zoom is in flight.
                recordingService?.tickZoom(pointer: self?._pointerFraction)
            }
            // ScreenCast rides it the same way: presents feed the PipeWire
            // stream, and the tick observes the stop draining. Until the
            // first frame lands it needs the full rate (see
            // needsPrimingRebuilds); live, the floor suffices — a static
            // desktop simply produces few frames, which is the point.
            if screenCastService?.needsFramePump == true {
                tick = true
                if screenCastService?.needsPrimingRebuilds == true {
                    rebuild = true
                }
                screenCastService?.pumpTick()
            }
            // RDP is the third rider, on identical terms: the floor keeps
            // the client's view alive on an idle desktop and carries the
            // stop through, while priming rebuilds only run until the
            // first frame reaches the client.
            if rdpService?.needsFramePump == true {
                tick = true
                if rdpService?.needsPrimingRebuilds == true {
                    rebuild = true
                }
                rdpService?.pumpTick()
            }
            #endif
            // Riders announce themselves, so the rate is not derived here --
            // with ONE exception. An X client starting a screen capture is
            // invisible until `fl_drm_view_capture_active` says so, which is
            // why the slow rate exists at all; re-deciding here is how that
            // escalates to the full rate. It is a no-op in every other state.
            self?._reevaluateFramePump()
            guard tick else { return }
            // The pump is a LIVENESS FLOOR, not a frame source. A present
            // only happens when the tree is dirty, and a full rebuild of
            // the 4K desktop takes ~100ms — so asking for one every 33ms
            // does not produce 30fps, it saturates the pipeline with
            // rebuilds and starves the presents that real content (a
            // client committing a new buffer) would otherwise drive. That
            // is what pinned recordings to exactly 10fps whatever they
            // captured. Ticking the floor slowly leaves the pipeline free
            // for content-driven presents, and an idle desktop still gets
            // refreshed often enough to carry start/stop requests and keep
            // the recording indicator's clock counting.
            self?._pumpTicks += 1
            if rebuild || (self?._pumpTicks ?? 0) % Self.kPumpFloorTicks == 0 {
                self?.setState { self?._frameTick += 1 }
            }
        }
        // NOT resumed here: the pump starts idle and is armed by
        // `_reevaluateFramePump` when a rider appears. A suspended timer costs
        // nothing at all, which is the point of the exercise.
        _frameTickTimer = timer
        // The riders say when they need the pump instead of being asked 30
        // times a second. They flip state from the engine's threads as well as
        // the main one, so the re-arm hops to the main queue -- which is where
        // the timer lives. Reached through the shell global rather than a
        // captured `self`, the same way the fd handler above does.
        let pokePump: @Sendable () -> Void = {
            DispatchQueue.main.async { _shellState?._reevaluateFramePump() }
        }
        recordingService?.onFramePumpNeedChanged = pokePump
        screenCastService?.onFramePumpNeedChanged = pokePump
        rdpService?.onFramePumpNeedChanged = pokePump
        _reevaluateFramePump()

        // WiFi state: monitor-driven while idle, plus a 5s re-read while the
        // popup is on screen so signal strengths and scan results stay live
        // (same tick-only-while-watched shape as the agent status timer).
        networkService.onChange = { [weak self] in
            self?.setState {}
        }
        networkService.start()
        // (its timer is created on demand — `_reevaluateShellTimers`)

        // Battery: the service polls on its own (5s) and calls back only on
        // real change — the icon must track plug/unplug with no popup open.
        batteryService.onChange = { [weak self] in
            self?.setState {}
        }
        batteryService.start()

        // Screen recording: state changes repaint the tile + indicator, a
        // finished session posts to the bell, and a 1s tick keeps the
        // indicator's elapsed time honest while (and only while) recording
        // — the tick-only-while-watched shape, like the agent status timer.
        recordingService?.onChange = { [weak self] in
            self?.setState {}
        }
        recordingService?.onFinished = { [weak self] saved, detail in
            guard let self else { return }
            if let saved {
                let home = LoginUser.home
                let shown = saved.hasPrefix(home)
                    ? "~" + saved.dropFirst(home.count) : saved
                self._postLocalNotification(summary: "Recording saved",
                                            body: shown)
            } else {
                self._postLocalNotification(summary: "Recording failed",
                                            body: detail)
            }
        }
        // (its timer is created on demand — `_reevaluateShellTimers`)
        #endif

        _startIdleDetection()
        _armScreensaverTestTimer()
        _restoreRdpSetting()
    }

    /// Resolve a data file (wallpaper, icons, shaders) across installed and
    /// dev layouts: $STARLING_DATA_DIR first (set by the packaged launcher),
    /// then `<exe dir>/../share/starling` (staged layout), then the dev-tree
    /// fallbacks the repo has always used.
    static func dataFilePath(_ relative: String) -> String? {
        var candidates: [String] = []
        if let dataDir = ProcessInfo.processInfo.environment["STARLING_DATA_DIR"] {
            candidates.append(dataDir + "/" + relative)
        }
        if let real = realpath("/proc/self/exe", nil) {
            let selfDir = (String(cString: real) as NSString).deletingLastPathComponent
            free(real)
            candidates.append(selfDir + "/../share/starling/" + relative)
        }
        // Dev-tree fallback: sdk/ at the repo root, derived from this source
        // file's compile-time path (<repo>/shell/Sources/DesktopShellApp/Shell/…).
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Shell/
            .deletingLastPathComponent()  // DesktopShellApp/
            .deletingLastPathComponent()  // Sources/
            .deletingLastPathComponent()  // shell/
            .deletingLastPathComponent()  // repo root
        candidates.append(repoRoot.appendingPathComponent("sdk/" + relative).path)
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Load the still wallpaper and upload it as a GL texture: a
    /// pre-rendered raw RGBA file if one is staged (legacy path), else the
    /// bundled JPEG, decoded via the image codec and center-cropped to the
    /// screen's aspect so TextureWidget's stretch-to-fill stays uniform.
    func _loadWallpaperTexture() {
        #if os(Linux)
        guard let registry = drmTextureRegistry,
              let wl = waylandIntegration else {
            return
        }
        guard wallpaperTextureId < 0, !_wallpaperDecodeStarted else { return }

        // Legacy path: pre-rendered 3840x2160 raw RGBA.
        if let path = Self.dataFilePath("wallpaper.rgba"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           data.count == 3840 * 2160 * 4 {
            let texId = registry.registerTexture(engine: wl.engine)
            data.withUnsafeBytes { ptr in
                registry.updatePixelData(
                    engine: wl.engine, id: texId,
                    data: ptr.baseAddress!, width: 3840, height: 2160)
            }
            wallpaperTextureId = texId
            _syncSharedWallpaper()
            return
        }

        // Bundled JPEG: packaged share dir first, then the dev tree
        // (the shell runs from apps/DesktopShellApp in dev).
        let candidates = [
            Self.dataFilePath("wallpapers/golden-gate-dark.jpg"),
            "Resources/Wallpapers/golden-gate-dark.jpg",
        ].compactMap { $0 }
        guard let jpg = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let data = try? Data(contentsOf: URL(fileURLWithPath: jpg)) else { return }
        _wallpaperDecodeStarted = true
        // Re-enter shell state via the _shellState global (the state class
        // is not Sendable, so the task must not capture self).
        Task { @MainActor in
            do {
                let codec = try await FlutterSwiftBridge.instantiateImageCodec([UInt8](data))
                let frame = try await codec.getNextFrame()
                codec.dispose()
                let image = frame.image
                defer { image.dispose() }
                guard let shell = _shellState,
                      let registry = drmTextureRegistry,
                      let wl = waylandIntegration else { return }
                let bytes = try image.toByteData(format: .rawRgba)
                let phys = PlatformDispatcher.instance.implicitView?.physicalSize
                    ?? Size(3840, 2160)
                let cropped = _DesktopShellState._centerCrop(
                    rgba: bytes, width: image.width, height: image.height,
                    toAspect: phys.width / phys.height)
                let texId = registry.registerTexture(engine: wl.engine)
                cropped.data.withUnsafeBytes { ptr in
                    registry.updatePixelData(
                        engine: wl.engine, id: texId,
                        data: ptr.baseAddress!,
                        width: cropped.width, height: cropped.height)
                }
                // Mica's ingredient: the wallpaper's average colour, which
                // the Fluent chrome leans toward so it looks related to the
                // picture behind it. Free here — the pixels are already
                // decoded and in hand.
                let tint = _DesktopShellState._averageColor(rgba: cropped.data)
                shell.setState {
                    shell.wallpaperTextureId = texId
                    shellMica = tint
                    // The palette is a FUNCTION of this, so re-resolve it —
                    // the theme built at launch was the untinted fallback.
                    shellTheme = shellStyle.theme(dark: shellTheme.isDark)
                    shell._windowChildCache.removeAll()
                    shell._syncSharedWallpaper()
                }
            } catch {
                // Decode failed — the preset's gradient stand-in stays up.
            }
        }
        #endif
    }

    /// The mean colour of raw RGBA pixels — Mica's ingredient.
    ///
    /// Sampled on a stride rather than every pixel: a 4K frame is 8.3M of
    /// them and the answer is a single average, so reading one pixel in every
    /// few hundred lands within a shade of the true mean for a fraction of
    /// the work. Alpha is ignored; a wallpaper is opaque.
    static func _averageColor(rgba: Data) -> Color? {
        let pixels = rgba.count / 4
        guard pixels > 0 else { return nil }
        let stride = max(1, pixels / 20_000)
        var r = 0, g = 0, b = 0, n = 0
        var i = 0
        while i < pixels {
            let o = i * 4
            r += Int(rgba[o]); g += Int(rgba[o + 1]); b += Int(rgba[o + 2])
            n += 1
            i += stride
        }
        guard n > 0 else { return nil }
        return Color(alpha: 1.0,
                     red: Double(r / n) / 255.0,
                     green: Double(g / n) / 255.0,
                     blue: Double(b / n) / 255.0)
    }

    /// Center-crop raw top-down RGBA pixels to a target aspect ratio,
    /// emitting rows bottom-up: the GL wallpaper-texture path samples with
    /// a flipped V, so a top-down buffer renders upside down (the legacy
    /// wallpaper.rgba / icon .rgba assets are stored pre-flipped for the
    /// same reason).
    private static func _centerCrop(rgba: Data, width: Int, height: Int,
                                    toAspect target: Double)
        -> (data: Data, width: Int, height: Int) {
        let srcAspect = Double(width) / Double(height)
        var cropW = width, cropH = height, x0 = 0, y0 = 0
        if srcAspect > target + 0.005 {
            // Too wide — trim columns.
            cropW = Int(Double(height) * target)
            x0 = (width - cropW) / 2
        } else if srcAspect < target - 0.005 {
            // Too tall — trim rows.
            cropH = Int(Double(width) / target)
            y0 = (height - cropH) / 2
        }
        var out = Data(capacity: cropW * cropH * 4)
        rgba.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            let base = src.baseAddress!
            for row in stride(from: y0 + cropH - 1, through: y0, by: -1) {
                out.append(Data(bytes: base + (row * width + x0) * 4,
                                count: cropW * 4))
            }
        }
        return (out, cropW, cropH)
    }

    /// Secondary-output screens are separate widget trees that can't reach
    /// this state object; they read the engine-global texture id. Publish it
    /// only while the still preset is active so gradient presets show there
    /// too.
    private func _syncSharedWallpaper() {
        sharedWallpaperTextureId =
            (wallpaperPreset == .still) ? wallpaperTextureId : -1
    }

    /// Dock and launcher icons, read from the copy of each app the user
    /// installed.
    ///
    /// Starling redistributes no third-party artwork — those marks are their
    /// owners' trademarks — so the icon path comes from the registry (resolved
    /// through the host's freedesktop lookup when the app was installed) and
    /// is decoded here. An app with no resolvable raster icon registers
    /// nothing and keeps the neutral painted glyph.
    func _loadIconTextures() {
        #if os(Linux)
        for rec in AppRegistry.shared.installedApps where rec.iconPath != nil {
            _loadIconTexture(for: rec.id)
        }
        #endif
    }

    /// Same, but only for apps that currently have a window. Cheap enough to
    /// call on every window-list change: `_loadIconTexture` is a no-op once an
    /// app's icon is loaded or has failed to resolve.
    func _loadIconTexturesForRunningApps() {
        #if os(Linux)
        for win in windowManager.windows {
            if let rec = _appOwning(win), rec.iconPath != nil {
                _loadIconTexture(for: rec.id)
            }
        }
        #endif
    }

    /// Resolve and decode one app's host icon, at most once per app id.
    ///
    /// Per-app rather than one-shot for the whole set, because an app can be
    /// installed while the session is running — the App Store's Install button
    /// does exactly that — and a single startup pass would leave it showing the
    /// neutral glyph until the next login. Callers re-invoke this on launch and
    /// when the Launchpad opens; an app whose icon is genuinely unresolvable is
    /// attempted once and then left alone.
    func _loadIconTexture(for name: String) {
        #if os(Linux)
        guard drmTextureRegistry != nil, waylandIntegration != nil else { return }
        guard iconTextures[name] == nil, !_iconDecodeAttempted.contains(name) else { return }
        guard let path = AppRegistry.shared.app(id: name)?.iconPath,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path))
        else { return }   // not installed yet — retry on the next launch
        _iconDecodeAttempted.insert(name)

        // Same re-entry pattern as the wallpaper decode: the state class is not
        // Sendable, so the task reaches back through _shellState.
        Task { @MainActor in
            do {
                let codec = try await FlutterSwiftBridge.instantiateImageCodec([UInt8](data))
                let frame = try await codec.getNextFrame()
                codec.dispose()
                let image = frame.image
                defer { image.dispose() }
                guard let shell = _shellState,
                      let registry = drmTextureRegistry,
                      let wl = waylandIntegration else { return }
                // The GL texture path samples with a flipped V, so the decoder's
                // top-down rows have to be reversed — the same reason
                // _centerCrop emits bottom-up.
                let flipped = _DesktopShellState._flipVertical(
                    rgba: try image.toByteData(format: .rawRgba),
                    width: image.width, height: image.height)
                let texId = registry.registerTexture(engine: wl.engine)
                flipped.withUnsafeBytes { ptr in
                    registry.updatePixelData(
                        engine: wl.engine, id: texId,
                        data: ptr.baseAddress!,
                        width: image.width, height: image.height)
                }
                shell.setState { shell.iconTextures[name] = texId }
            } catch {
                // Undecodable — the neutral painted glyph stays.
            }
        }
        #endif
    }

    /// Reverse raw RGBA rows: top-down decoder output -> bottom-up upload.
    private static func _flipVertical(rgba: Data, width: Int, height: Int) -> Data {
        let stride = width * 4
        guard height > 0, rgba.count >= stride * height else { return rgba }
        var out = Data(count: stride * height)
        rgba.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) in
                for row in 0..<height {
                    let from = src.baseAddress! + (height - 1 - row) * stride
                    memcpy(dst.baseAddress! + row * stride, from, stride)
                }
            }
        }
        return out
    }

    /// Wire up WaylandIntegration callbacks to create/destroy windows.
    /// Begin the close animation for a window by appId (used by the portal
    /// file chooser to tear down the picker window when it exits — its
    /// _closingWindows set is private to this state).
    func _portalBeginClosingWindow(appId: String) {
        guard let win = windowManager.windows.first(where: { $0.appId == appId })
        else { return }
        // An OWNED window is drawn in a workspace, not on the desktop, so the
        // desktop's close animation — which is what eventually calls
        // _finalizeWindowClose — never runs for it. Marking it "closing" and
        // waiting would strand it forever: the picker's process is gone and
        // its last frame sits in the workspace looking live, with the rail
        // still counting it. Tear it down directly instead.
        if win.ownerAgentId != nil {
            _finalizeWindowClose(win.id)
            return
        }
        setState { _closingWindows.insert(win.id) }
    }

    private func _setupWaylandCallbacks() {
        #if os(Linux)
        // Wayland-specific callbacks need the integration; the key
        // routing below does NOT — display mode (--rdp) has no Wayland
        // server yet and still has a keyboard, and an early return here
        // left pd.onKeyData unset, so every key vanished silently.
        if let wayland = waylandIntegration {

        // await_settled's raw material for third-party windows. Wired here
        // rather than in AgentBroker.start because the broker is created
        // while the compositor may still be nil.
        wayland.onSurfaceFrame = { [weak self] texId in
            self?._agentBroker?.noteFrame(textureId: texId)
        }

        wayland.onNewWindow = { [weak self] (surfaceId: UInt32, textureId: Int, title: String, clientId: UInt64) -> String in
            guard let self = self else { return "" }
            let appId = "wayland-\(surfaceId)"
            var windowId = ""
            self.setState {
                // addWindow may hop the active space to a user desktop (new
                // windows never open inside a workspace); if this turns out
                // to be an agent-claimed window, the hop is undone below.
                let spaceBefore = self.windowManager.activeSpaceIndex
                // Whether a workspace was on screen must be sampled HERE:
                // addWindow hops the active space to a user one, so asking
                // afterwards always says no, and the window lands on the
                // desktop the user cannot even see.
                let workspaceOnEntry: String? =
                    self.windowManager.spaces[spaceBefore].isWorkspace
                        ? self.windowManager.selectedWorkspace?.id : nil
                windowId = self.windowManager.addWindow(
                    title: Self._displayTitle(title),
                    appId: appId,
                    textureId: textureId,
                    onWindowClose: {
                        // xdg_toplevel.close — the protocol DOES have a
                        // server->client close; believing otherwise is what
                        // left Quit a no-op. The client runs its normal quit
                        // path and disconnects, and on_toplevel_destroy then
                        // fires and cleans up. If it ignores us, _quitApp
                        // escalates to the pid captured at map time.
                        wayland.requestClose(surfaceId: surfaceId)
                    },
                    onPointerEvent: { (phase, x, y, buttons) in
                        wayland.sendPointerEvent(
                            surfaceId: surfaceId,
                            phase: phase,
                            x: x, y: y,
                            buttons: buttons
                        )
                    },
                    onContentResize: { (width, height) in
                        wayland.sendResize(
                            surfaceId: surfaceId,
                            width: Int(width),
                            height: Int(height)
                        )
                    },
                    onResizeComplete: { (width, height) in
                        wayland.sendResizeForced(
                            surfaceId: surfaceId,
                            width: Int(width),
                            height: Int(height)
                        )
                    },
                    onScrollEvent: { (x, y, deltaX, deltaY) in
                        wayland.sendScrollEvent(
                            surfaceId: surfaceId,
                            x: x, y: y,
                            scrollDeltaX: deltaX,
                            scrollDeltaY: deltaY
                        )
                    },
                    flipTextureY: true,
                    appBuilder: { _ in SizedBox(expand: ()) }
                )
                // Agent-launched Wayland client (Murmuration): every
                // toplevel from a claimed client connection belongs to its
                // agent — no desktop presence, tile-only. A pending launch
                // marker claims the connection on its first window.
                var ownerId = self._agentWaylandClients[clientId]
                var launchReply: ((String) -> Void)? = nil
                if ownerId == nil, let pending = self._pendingAgentWayland {
                    self._pendingAgentWayland = nil
                    self._agentWaylandClients[clientId] = pending.agentId
                    ownerId = pending.agentId
                    launchReply = pending.onWindow
                } else if let pending = self._pendingAgentWayland,
                          pending.agentId == ownerId {
                    // The agent's SECOND launch of the same app. Chrome is one
                    // process per profile, so this window arrives on the
                    // connection that was claimed the first time — the marker
                    // above never matched, nothing answered the launch, and
                    // the agent was told "chrome launch timed out" 25s later
                    // about a window that had been sitting there, owned by it,
                    // the whole time.
                    self._pendingAgentWayland = nil
                    launchReply = pending.onWindow
                }
                // Workspace mode: a window that opens while a workspace is on
                // screen belongs to it. This is the path a GUI app started
                // from the driver takes — the driver spawns it, it connects to
                // the compositor, and its first toplevel arrives here.
                var isWorkspaceWindow = false
                if ownerId == nil, let wsId = workspaceOnEntry {
                    ownerId = wsId
                    isWorkspaceWindow = true
                }
                if let ownerId,
                   let win = self.windowManager.windows.first(where: { $0.id == windowId }) {
                    win.ownerAgentId = ownerId
                    win.spaceId = WindowManagerState.kNoSpaceId
                    win.pendingOpenAnimation = false
                    // An agent's first window earns it a rail entry, so the
                    // human can switch to workspace mode and watch. Not for a
                    // workspace window: that rail entry already exists and is
                    // what made this window owned in the first place.
                    if !isWorkspaceWindow,
                       self.windowManager.workspace(forAgent: ownerId) == nil,
                       !self._retryBindAgent(ownerId),
                       let agent = self.windowManager.agents.first(where: {
                           $0.id == ownerId
                       }) {
                        self.windowManager.ensureAgentWorkspace(
                            agentId: ownerId, name: agent.displayName)
                    }

                    // Agent windows never move the human's view: undo the
                    // user-space hop addWindow performed (e.g. Ctrl+N in a
                    // a broker client's Chrome opening a second window).
                    if self.windowManager.activeSpaceIndex != spaceBefore {
                        self.windowManager.switchToSpace(spaceBefore)
                    }
                    self.windowManager.focusTopmostInActiveSpace()
                    // Tile-only from birth: throttle immediately using the
                    // surfaceId in hand (the windowId→surface map is filled
                    // only after this callback returns; the fleet build
                    // re-evaluates the full policy from then on).
                    // Broker-owned windows are never drawn, so they are
                    // throttled hard. A workspace tab IS drawn and has no
                    // re-evaluation pass, so throttling it would leave the
                    // visible tab stuck at 5fps forever.
                    if !isWorkspaceWindow {
                        wayland.setSurfaceThrottle(surfaceId: surfaceId, intervalMs: 200)
                        self._agentThrottleApplied[windowId] = 200
                    }
                    launchReply?(windowId)
                }
            }
            // Agent-owned clients are sized to the workspace tab pane, so
            // they fill it exactly at scale 1.0 instead of being letterboxed
            // at some other aspect. The initial configure must go out before
            // the first frame; nothing resizes an agent window afterwards.
            if let win = self.windowManager.windows.first(where: { $0.id == windowId }),
               win.ownerAgentId != nil {
                let stage = self._agentStageContentSize()
                win.rect = Rect.fromLTWH(0, 0, stage.width,
                                         stage.height + DesktopTheme.kTitleBarHeight)
                self._agentSizeApplied[windowId] = stage
                wayland.sendResize(surfaceId: surfaceId,
                                   width: Int(stage.width), height: Int(stage.height))
                return windowId
            }
            // Send configure with the maximized content area — fills the
            // screen below status bar + title bar. The dock floats on top
            // (macOS-style) so its BackdropFilter can blur actual content.
            let topInset = DesktopTheme.kStatusBarHeight
            let contentWidth = Int(screenWidth)
            let contentHeight = Int(screenHeight - topInset - DesktopTheme.kTitleBarHeight)
            wayland.sendResize(surfaceId: surfaceId, width: contentWidth, height: contentHeight)
            // Start Wayland windows maximized (like Hyprland's default behavior).
            self.windowManager.maximizeWindow(windowId, screenWidth: screenWidth, screenHeight: screenHeight)
            return windowId
        }

        wayland.onWindowDestroyed = { [weak self] (windowId: String) in
            guard let self = self else { return }
            self.setState {
                self.windowManager.closeWindow(windowId)
            }
        }

        // A client connection closed: forget the agent ownership keyed on it.
        // clientId is the wl_client pointer, so once the client is gone the
        // allocator can hand the same value to an unrelated one — a stale
        // entry would claim THAT client's toplevels for the agent, giving them
        // no desktop presence. An agent's Chrome exiting could therefore make
        // the human's own browser, opened later, appear to vanish.
        wayland.onClientDestroyed = { [weak self] (clientId: UInt64) in
            guard let self = self else { return }
            guard let agentId = self._agentWaylandClients.removeValue(forKey: clientId)
            else { return }
            // Logged because this is the C→Swift registration path that has
            // silently gone missing twice in this codebase: a callback that
            // is declared, defined and called, but never registered, looks
            // exactly like a feature that works until something depends on it.
            // One line per agent-owned client exit is cheap and says it ran.
            FileHandle.standardError.write(Data(
                "[AgentSpace] wayland client gone; dropped \(agentId) ownership\n".utf8))
        }

        wayland.onTextInputState = { [weak self] windowId, enabled, x, y, w, h in
            guard let self = self else { return }
            self._imeWaylandTI = (windowId, enabled,
                                  Rect.fromLTWH(x, y, w, h))
            if self._imeEnabled,
               !self._imePreedit.isEmpty || !self._imeCandidates.isEmpty {
                self.setState {}
            }
        }

        wayland.onTitleChanged = { [weak self] (windowId: String, title: String) in
            guard let self = self else { return }
            if let win = self.windowManager.windows.first(where: { $0.id == windowId }) {
                self.setState {
                    win.title = Self._displayTitle(title, for: win)
                }
            }
            // For the few windows recognised by title rather than app_id, this
            // is the point at which "that window is Zoom" becomes true — the
            // title only arrives here, after the first commit.
            self._loadIconTexturesForRunningApps()
        }

        // What a window calls itself (`xdg_toplevel.set_app_id`), and the only
        // reliable link from a window back to an installed app. IntelliJ says
        // "jetbrains-idea" here on every window it owns, including the project
        // window whose title is just "untitled – Main.java".
        wayland.onAppIdChanged = { [weak self] (windowId: String, appId: String) in
            guard let self = self,
                  let win = self.windowManager.windows.first(where: { $0.id == windowId })
            else { return }
            guard win.wmClass != appId else { return }
            self.setState {
                win.wmClass = appId
                // A record may rename the window (WeChat's is the whole
                // rootful Xwayland screen, titled "Xwayland on :1").
                win.title = Self._displayTitle(win.title, for: win)
            }
            self._loadIconTexturesForRunningApps()
        }

        wayland.onNewPopup = { [weak self] (surfaceId: UInt32, textureId: Int, parentSurfaceId: UInt32, x: Int, y: Int, width: Int, height: Int) -> String in
            guard let self = self else { return "" }
            let popupId = "popup-\(surfaceId)"
            self.setState {
                // Dismiss stale sibling popups (same parent) and their descendants.
                // Chrome never destroys popups because we don't send popup_done,
                // so stale entries accumulate. Clean them up when a new sibling arrives.
                var toRemove: Set<String> = []
                for (id, p) in self.popups {
                    if id != popupId && p.parentSurfaceId == parentSurfaceId {
                        toRemove.insert(id)
                    }
                }
                // Also remove descendants of dismissed popups
                var changed = true
                while changed {
                    changed = false
                    for (id, p) in self.popups {
                        let parentKey = "popup-\(p.parentSurfaceId)"
                        if !toRemove.contains(id) && toRemove.contains(parentKey) {
                            toRemove.insert(id)
                            changed = true
                        }
                    }
                }
                for id in toRemove {
                    self.popups.removeValue(forKey: id)
                }

                self.popups[popupId] = (textureId: textureId, parentSurfaceId: parentSurfaceId,
                                         x: Double(x), y: Double(y),
                                         width: Double(width), height: Double(height),
                                         mapped: false)
            }
            return popupId
        }

        wayland.onPopupDestroyed = { [weak self] (popupId: String) in
            guard let self = self else { return }
            self.setState {
                self.popups.removeValue(forKey: popupId)
            }
        }

        // Client-initiated interactive move/resize (xdg_toplevel.move/resize —
        // CSD titlebar or Chrome tab-strip drag). Arm the grab state on the
        // window; DesktopWindow's content Listener (which owns the in-flight
        // pointer gesture) diverts motion into move/resize until button-up.
        wayland.onMoveRequest = { [weak self] (windowId: String) in
            guard let self = self,
                  let win = self.windowManager.windows.first(where: { $0.id == windowId })
            else { return }
            win.interactiveMoveActive = true
            win.interactiveResizeEdge = nil
            win.interactiveLastPos = nil
        }

        wayland.onInteractiveResizeRequest = { [weak self] (windowId: String, edges: UInt32) in
            guard let self = self,
                  let win = self.windowManager.windows.first(where: { $0.id == windowId })
            else { return }
            // xdg_toplevel.resize_edge bitmask: top=1 bottom=2 left=4 right=8.
            let edge: ResizeEdge?
            switch edges {
            case 1: edge = .top
            case 2: edge = .bottom
            case 4: edge = .left
            case 8: edge = .right
            case 5: edge = .topLeft
            case 9: edge = .topRight
            case 6: edge = .bottomLeft
            case 10: edge = .bottomRight
            default: edge = nil
            }
            guard let resolved = edge else { return }
            win.interactiveMoveActive = false
            win.interactiveResizeEdge = resolved
            win.interactiveLastPos = nil
            // Same start-of-drag contract as the shell's own resize handles.
            win.targetRect = win.rect
        }

        wayland.onWindowGeometryChanged = { [weak self] (windowId: String, x: Int, y: Int, width: Int, height: Int, bufLogW: Int, bufLogH: Int) in
            guard let self = self else { return }
            if let win = self.windowManager.windows.first(where: { $0.id == windowId }) {
                let oldOffset = win.geometryOffset
                let oldBufSize = win.bufferLogicalSize
                win.geometryOffset = (x: Double(x), y: Double(y))
                win.geometrySize = (width: Double(width), height: Double(height))
                win.bufferLogicalSize = (width: Double(bufLogW), height: Double(bufLogH))
                // Only rebuild if geometry actually changed (avoid rebuilds on every frame)
                let changed = oldOffset == nil
                    || oldOffset!.x != Double(x) || oldOffset!.y != Double(y)
                    || oldBufSize == nil
                    || oldBufSize!.width != Double(bufLogW) || oldBufSize!.height != Double(bufLogH)
                if changed {
                    self._windowChildCache.removeValue(forKey: windowId)
                    self.setState {}
                }
            }
        }

        wayland.onPopupBufferResized = { [weak self] (popupId: String, logicalWidth: Int, logicalHeight: Int, geoX: Int, geoY: Int) in
            guard let self = self else { return }
            if var popup = self.popups[popupId] {
                popup.width = Double(logicalWidth)
                popup.height = Double(logicalHeight)
                // Position buffer so content area (at geometry offset) aligns with positioner position.
                // geometry (geoX, geoY) = offset from buffer top-left to content top-left.
                popup.x -= Double(geoX)
                popup.y -= Double(geoY)
                popup.mapped = true
                self.setState {
                    self.popups[popupId] = popup
                }
            }
        }

        wayland.onWindowBufferResized = { [weak self] (windowId: String, logicalWidth: Int, logicalHeight: Int) in
            guard let self = self else { return }
            // Otherwise it's a toplevel window.
            guard let win = self.windowManager.windows.first(where: { $0.id == windowId }) else { return }

            // Fullscreen: rect is fixed (below status bar, full width).
            // Just schedule a repaint so the texture updates.
            if win.isFullscreen {
                PlatformDispatcher.instance.scheduleFrame()
                return
            }

            let titleBarH = DesktopTheme.kTitleBarHeight
            let newWidth = Double(logicalWidth)
            let newHeight = Double(logicalHeight) + titleBarH

            // Maximised: the size is the shell's, not the client's — the same
            // rule fullscreen already follows just above.
            //
            // Below this point a buffer commit RESIZES THE WINDOW to whatever
            // the client rendered, which is right while a client is settling
            // into a size we asked for and wrong for a maximised one, because
            // a maximised window's size was never the client's to pick. A
            // client that renders taller than the rect we configured drags the
            // window off the bottom of the screen and takes the end of its own
            // layout with it. Claude Desktop does exactly that: configured
            // 1280x768, it acks and commits a 1280x884 viewport, and its "Get
            // started" button — the last thing in the layout — ends up below
            // the screen, so the app cannot be signed into at all. The window
            // is only reachable again by un-maximising it.
            //
            // So hold the rect and re-assert the configure. Re-assert only
            // when the client's size CHANGES, not on every commit: a client
            // that ignores us (this one does) would otherwise be sent a
            // configure for every frame it draws, forever.
            if win.isMaximized {
                let wantW = Int(win.rect.width)
                let wantH = Int(win.rect.height - titleBarH)
                if logicalWidth != wantW || logicalHeight != wantH {
                    let seen = self._maximizedSizeSeen[windowId]
                    if seen == nil || seen! != (logicalWidth, logicalHeight) {
                        self._maximizedSizeSeen[windowId] = (logicalWidth, logicalHeight)
                        if let surfId = wayland.surfaceId(forWindowId: windowId) {
                            wayland.sendResize(surfaceId: surfId,
                                               width: wantW, height: wantH)
                        }
                    }
                } else {
                    self._maximizedSizeSeen.removeValue(forKey: windowId)
                }
                PlatformDispatcher.instance.scheduleFrame()
                return
            }
            self._maximizedSizeSeen.removeValue(forKey: windowId)

            // An agent window is born at the pane size the shell chose, and
            // some clients ignore the initial configure and map at their own
            // idea of a good size — Blender picks the whole output. Re-assert
            // the birth size ONCE, on the first commit: an honoring client
            // settles into the pane and fills it exactly. A client still
            // committing something else after that gets its size adopted by
            // the normal path below — the pane letterboxes it, and the
            // agent's coordinate space (win.rect) keeps telling the truth.
            if win.ownerAgentId != nil,
               let want = self._agentSizeApplied[windowId] {
                self._agentSizeApplied.removeValue(forKey: windowId)
                if Int(newWidth) != Int(want.width)
                    || Int(Double(logicalHeight)) != Int(want.height),
                   let surfId = wayland.surfaceId(forWindowId: windowId) {
                    wayland.sendResize(surfaceId: surfId,
                                       width: Int(want.width),
                                       height: Int(want.height))
                    PlatformDispatcher.instance.scheduleFrame()
                    return
                }
            }

            if win.resizeDragEdge != nil {
                // During active drag: don't update rect (it follows the mouse),
                // but schedule a frame so the texture repaints with new content.
                PlatformDispatcher.instance.scheduleFrame()

                // Check if Chrome matched target size (edge case)
                if let target = win.targetRect,
                   Int(newWidth) == Int(target.width),
                   Int(newHeight) == Int(target.height) {
                    win.targetRect = nil
                    win.resizeDragEdge = nil
                }
            } else if win.targetRect != nil {
                // Drag ended, waiting for Chrome to match final size.
                let target = win.targetRect!
                if Int(newWidth) == Int(target.width) &&
                   Int(newHeight) == Int(target.height) {
                    win.targetRect = nil
                    win.resizeDragEdge = nil
                }
                // Update rect to Chrome's actual rendered size
                self.setState {
                    win.rect = Rect.fromLTWH(win.rect.left, win.rect.top, newWidth, newHeight)
                }
            } else {
                // Normal buffer resize (not dragging)
                if Int(win.rect.width) != Int(newWidth) || Int(win.rect.height) != Int(newHeight) {
                    self.setState {
                        win.rect = Rect.fromLTWH(win.rect.left, win.rect.top, newWidth, newHeight)
                    }
                } else {
                    PlatformDispatcher.instance.scheduleFrame()
                }
            }
        }

        wayland.onFullscreenRequest = { [weak self] (windowId: String) in
            guard let self = self else { return }
            guard let win = self.windowManager.windows.first(where: { $0.id == windowId }) else { return }
            guard !win.isFullscreen else { return }  // already fullscreen
            guard let surfId = wayland.surfaceId(forWindowId: windowId) else { return }
            self.setState {
                self._fullscreenWithZoom(windowId)
            }
            // Fullscreen: window sits below the system status bar (reserved
            // top strip). The title bar overlays the content on demand so
            // the wayland client renders into the full window height.
            let contentW = Int(self.screenWidth)
            let contentH = Int(self.screenHeight - DesktopTheme.kStatusBarHeight)
            wayland.sendFullscreenResize(surfaceId: surfId, width: contentW, height: contentH)
        }

        wayland.onUnfullscreenRequest = { [weak self] (windowId: String) in
            guard let self = self else { return }
            guard let win = self.windowManager.windows.first(where: { $0.id == windowId }) else { return }
            guard win.isFullscreen else { return }
            guard let surfId = wayland.surfaceId(forWindowId: windowId) else { return }
            var finalRect: Rect? = nil
            self.setState {
                finalRect = self._fullscreenWithZoom(windowId)
            }
            // Restored — configure the client from the FINAL rect (win.rect
            // is mid-zoom).
            guard let restored = finalRect else { return }
            let contentW = Int(restored.width)
            let contentH = Int(restored.height - DesktopTheme.kTitleBarHeight)
            wayland.sendExitFullscreen(surfaceId: surfId, width: contentW, height: contentH)
        }

        }  // end Wayland-specific callbacks

        // Forward keyboard events to the focused Wayland or X11 client.
        let pd = PlatformDispatcher.instance
        let routeKey: (KeyData) -> Bool = { [weak self] keyData in
            guard let self = self else { return false }

            // Track Ctrl/Shift modifier state first (HID: 0xE0/0xE4 = Ctrl,
            // 0xE1/0xE5 = Shift) — the modal layers below rely on it.
            let phys = keyData.physical
            let modDown = keyData.type == .down || keyData.type == .repeat
            if phys == 0xE0 || phys == 0xE4 { self._ctrlPressed = modDown }
            if phys == 0xE1 || phys == 0xE5 { self._shiftPressed = modDown }
            if phys == 0xE2 || phys == 0xE6 { self._altPressed = modDown }
            if phys == 0xE3 || phys == 0xE7 { self._superPressed = modDown }
            // Push the true modifier state to the compositor on EVERY key, so
            // the state clients are told never drifts from the physical keys.
            // Its own accumulator only updated when a modifier was forwarded
            // to a client, so a Ctrl-up the shell consumed — every Ctrl+Down
            // into workspace mode does exactly that — left the client believing
            // Ctrl was still held. The next window the human typed into then
            // turned "…com" into Ctrl+O and opened a file dialog; a password
            // would have become a fistful of shortcuts.
            if phys == 0xE0 || phys == 0xE4 || phys == 0xE1 || phys == 0xE5
                || phys == 0xE2 || phys == 0xE6 || phys == 0xE3 || phys == 0xE7 {
                waylandIntegration?.setHumanModifiers(
                    ctrl: self._ctrlPressed, shift: self._shiftPressed,
                    alt: self._altPressed, super: self._superPressed)
            }

            // Screensaver: any key wakes it, and nothing reaches apps or the
            // shell's own UI while it is up (launcher-style modal swallow).
            // Wake on down/repeat only — the activation chord's own key-ups
            // pass through harmlessly.
            if self._screensaverActive {
                if keyData.type == .down || keyData.type == .repeat {
                    self._screensaverInputWake()
                }
                return true
            }

            // The app launcher (Launchpad) is modal: while it's open it owns
            // the keyboard. Type to search, Backspace to edit, Enter to launch
            // the top match, Esc to clear the query (then close). No keystroke
            // reaches the windows underneath.
            if self._launcherOpen {
                if keyData.type == .down || keyData.type == .repeat {
                    switch keyData.physical {
                    case 0x29:  // Escape
                        self.setState {
                            if self._launcherQuery.isEmpty {
                                self._launcherOpen = false
                                self._launcherDriverTarget = nil
                            } else {
                                self._launcherQuery = ""
                            }
                        }
                        // Harmless if that closed the launcher — the loop bails.
                        self._restartLauncherCaret()
                    case 0x2A:  // Backspace
                        self.setState {
                            if !self._launcherQuery.isEmpty { self._launcherQuery.removeLast() }
                        }
                        self._restartLauncherCaret()
                    case 0x28, 0x58:  // Enter / keypad Enter — launch the top match
                        if let first = self._launcherFilteredApps().first {
                            self._launchFromLauncher(first.appId)
                        }
                    default:
                        if let ch = keyData.character,
                           let s = ch.unicodeScalars.first,
                           s.value >= 0x20, s.value != 0x7F {
                            self.setState { self._launcherQuery += ch }
                            self._restartLauncherCaret()
                        }
                    }
                }
                return true  // swallow everything while the launcher is open
            }

            // The WiFi password prompt owns the keyboard while visible — the
            // one status popup that reads keys. Without this branch every
            // keystroke would fall through to the focused window while the
            // user watches a password field with a blinking caret.
            if self.activeStatusBarPopup == .wifi, let ssid = self._wifiPasswordSSID {
                if keyData.type == .down || keyData.type == .repeat {
                    switch keyData.physical {
                    case 0x29:  // Escape — back to the network list
                        self.setState {
                            self._wifiPasswordSSID = nil
                            self._wifiPassword = ""
                        }
                    case 0x2A:  // Backspace
                        self.setState {
                            if !self._wifiPassword.isEmpty { self._wifiPassword.removeLast() }
                        }
                        self._restartWifiCaret()
                    case 0x28, 0x58:  // Enter / keypad Enter — join
                        self._wifiJoin(ssid: ssid,
                                       security: self._wifiPasswordSecurity,
                                       password: self._wifiPassword)
                    default:
                        if let ch = keyData.character,
                           let s = ch.unicodeScalars.first,
                           s.value >= 0x20, s.value != 0x7F {
                            self.setState { self._wifiPassword += ch }
                            self._restartWifiCaret()
                        }
                    }
                }
                return true
            }

            // Esc hands a taken-over window back to its agent, and is checked
            // before every other Esc on the desktop: this is the most modal
            // state there is — an agent is being refused everything on that
            // window for as long as it holds.
            //
            // The cost, stated plainly: Esc cannot be typed INTO a window you
            // have taken. That is the price of a release key that needs no
            // modifier and no aiming, which is the property that matters when
            // you are grabbing a window because something is going wrong.
            if keyData.type == .down, phys == 0x29,
               self._releaseTakenOverWindows() {
                return true
            }

            // Escape closes an open status popup, like every other menu on
            // the desktop. Only Escape is taken — a status popup is not modal
            // otherwise, so everything else still reaches the focused window.
            if self.activeStatusBarPopup != nil, keyData.type == .down,
               phys == 0x29 {
                self.setState {
                    self.activeStatusBarPopup = nil
                    self._powerConfirm = nil
                    self._wifiPasswordSSID = nil
                    self._wifiPassword = ""
                }
                return true
            }

            // Mission Control owns the keyboard while open: Esc / Ctrl+Up
            // close it; Ctrl+←/→ retarget the active space instantly (the
            // strip highlight and exposé follow); all else is swallowed.
            if self._missionControlOpen {
                if keyData.type == .down || keyData.type == .repeat {
                    if keyData.type == .down,
                       phys == 0x29 || (phys == 0x52 && self._ctrlPressed) {
                        self._closeMissionControlAnimated()
                    } else if self._ctrlPressed, phys == 0x50 || phys == 0x4F {
                        let wm = self.windowManager
                        let out = self._missionControlOutputId
                        let cur = wm.spaceIndex(ofSpaceId: wm.activeSpaceId(onOutput: out))
                            ?? wm.activeSpaceIndex
                        let target = cur + (phys == 0x4F ? 1 : -1)
                        if wm.spaces.indices.contains(target),
                           !wm.spaces[target].isSpecial {
                            self._switchToSpace(target, animated: false, onOutput: out)
                        }
                    }
                }
                return true
            }

            // Spaces shortcuts (macOS): Ctrl+←/→ slide to the adjacent
            // space; Ctrl+Shift+←/→ carry the focused window along;
            // Ctrl+Tab cycles through all spaces. Swallowed even at the
            // ends of the strip — the system owns Ctrl+arrows, apps never
            // see them (macOS behaviour).
            if self._ctrlPressed, keyData.type == .down || keyData.type == .repeat {
                if phys == 0x50 || phys == 0x4F {  // Left / Right arrow
                    // Arrows never lead INTO a workspace (dedicated entry
                    // only) — but they do lead out of it. They act on the
                    // monitor the pointer is on (macOS: the pointer decides
                    // which display you're addressing); each output steps
                    // from ITS active space.
                    let wm = self.windowManager
                    let out = self._pointerOutputId ?? displayLayout?.host.id ?? 0
                    let current = wm.spaceIndex(ofSpaceId: wm.activeSpaceId(onOutput: out))
                        ?? wm.activeSpaceIndex
                    let target = current + (phys == 0x4F ? 1 : -1)
                    if wm.spaces.indices.contains(target),
                       !wm.spaces[target].isSpecial {
                        if self._shiftPressed {
                            self._moveFocusedWindowToSpace(target)
                        } else {
                            self._switchToSpace(target, onOutput: out)
                        }
                    }
                    return true
                }
                if phys == 0x2B && keyData.type == .down {  // Tab
                    // Cycle through the ordinary spaces; a workspace (always
                    // last) is skipped — from inside it, Tab exits to space 0.
                    // Pointer-scoped like the arrows.
                    let wm = self.windowManager
                    let out = self._pointerOutputId ?? displayLayout?.host.id ?? 0
                    let count = wm.spaces.count - wm.spaces.filter({ $0.isSpecial }).count
                    let current = wm.spaceIndex(ofSpaceId: wm.activeSpaceId(onOutput: out))
                        ?? wm.activeSpaceIndex
                    if count > 1 || wm.activeSpace(onOutput: out).isSpecial {
                        self._switchToSpace((current + 1) % max(count, 1), onOutput: out)
                    }
                    return true
                }
                if phys == 0x52 && keyData.type == .down {  // Up — Mission Control
                    self._openMissionControl()
                    return true
                }
                if phys == 0x51 && keyData.type == .down {  // Down
                    // Ctrl+Up is Mission Control and Ctrl+←/→ cycle spaces,
                    // so Down is the arrow left for workspace mode.
                    self._toggleWorkspaceSpace()
                    return true
                }
                if phys == 0x2C && keyData.type == .down {  // Space — IME toggle
                    self._toggleIme()
                    return true
                }
                // Ctrl+Shift+R — toggle screen recording. Swallowed only
                // with Shift down, so apps keep plain Ctrl+R (reload).
                if phys == 0x15 && self._shiftPressed && keyData.type == .down {
                    #if os(Linux)
                    if let rec = recordingService, rec.available {
                        rec.isRecording ? rec.stop() : rec.start()
                    }
                    #endif
                    return true
                }
                // Ctrl+Shift+= / Ctrl+Shift+- — zoom the RECORDING in and
                // out around the pointer. Nothing on screen moves; this
                // crops what the encoder sees, which is why a 4K capture can
                // zoom to 1:1 and come out sharper than the wide shot.
                // Shift-gated like the others so apps keep plain Ctrl+±.
                if (phys == 0x2E || phys == 0x2D) && self._shiftPressed
                    && (keyData.type == .down || keyData.type == .repeat) {
                    #if os(Linux)
                    if let rec = recordingService, rec.isRecording {
                        rec.stepZoom(phys == 0x2E ? 1 : -1,
                                     at: self._pointerFraction)
                    }
                    #endif
                    return true
                }
                // Ctrl+Shift+S — screensaver (dev trigger until the idle
                // timer lands). Shift-gated so apps keep plain Ctrl+S (save).
                if phys == 0x16 && self._shiftPressed && keyData.type == .down {
                    self._activateScreensaver()
                    return true
                }
            }

            guard let focusedId = self.windowManager.focusedWindowId,
                  let win = self.windowManager.windows.first(where: { $0.id == focusedId }) else {
                // No focused window — offer the key to the shell's own UI
                // (start menu search, etc.).
                return FocusManager.instance.dispatchKeyData(keyData)
            }


            // IME: while enabled, offer the key to fcitx first — consumed
            // keys are composition input (pinyin letters, candidate digits,
            // …) and must not reach the app. Commits arrive via onCommit.
            // Runs before the per-window forwarding so Wayland/X11 clients
            // compose too (commits reach them via text-input-v3).
            if self._imeEnabled, let ime = self.imeIntegration {
                if win.appId.hasPrefix("wayland-") {
                    // Text-input enter rides keyboard enter, which is
                    // normally lazy (first forwarded key) — force it so the
                    // client enables its text input before we compose.
                    waylandIntegration?.ensureKeyboardFocus()
                }
                // A half-typed composition must not follow focus to another
                // window (or survive its target's death) — reset it.
                if self._imeTargetWindowId != focusedId {
                    if self._imeTargetWindowId != nil { ime.resetComposition() }
                    self._imeTargetWindowId = focusedId
                }
                if ime.handleKey(keyData) {
                    return true
                }
            }

            if win.appId.hasPrefix("wayland-") {
                let isDown = keyData.type == .down || keyData.type == .repeat
                if keyData.type == .down || keyData.type == .up {
                    // Deliver to the FOCUSED window's surface, not wherever the
                    // pointer happens to be. appId is "wayland-<surfaceId>".
                    let surface = UInt32(win.appId.dropFirst("wayland-".count)) ?? 0
                    waylandIntegration?.sendKeyEvent(
                        physical: keyData.physical,
                        logical: keyData.logical,
                        isDown: isDown,
                        targetSurface: surface
                    )
                }
                return true
            }

            if win.appId.hasPrefix("x11-"), let x11 = x11Integration {
                // Convert HID physical key to evdev keycode — the SAME mapping
                // the Wayland path uses. keyData.physical is a HID usage code
                // (Backspace = 0x2A); the X11 server adds 8 to make the X
                // keycode. The old code passed the HID value straight through,
                // so every key was mis-mapped (Backspace 0x2A → evdev 42 =
                // Left Shift, i.e. did nothing; letters became other letters).
                // Repeats are delivered as extra presses (X11-style autorepeat).
                let evdevCode = WaylandIntegration.hidToEvdev(UInt64(bitPattern: keyData.physical))
                x11.sendKeyEvent(keycode: evdevCode, pressed: keyData.type != .up)
                return true
            }

            // Focused window hosts a child process app (Files, Settings, …):
            // forward over its DMA-BUF input socket.
            if let texId = self.processTextureIds[win.appId],
               let mgr = linuxProcessAppManager {
                let scalar = keyData.character?.unicodeScalars.first?.value ?? 0
                let phase: Int32
                switch keyData.type {
                case .down: phase = 0
                case .up: phase = 1
                case .repeat: phase = 2
                }
                mgr.sendKeyEvent(
                    textureId: texId,
                    physical: keyData.physical,
                    logical: keyData.logical,
                    character: scalar,
                    phase: phase
                )
                return true
            }

            // Focused window is shell-internal — offer the key to the
            // shell's own focused widget, if any.
            return FocusManager.instance.dispatchKeyData(keyData)
        }
        _keyRouter = routeKey
        pd.onKeyData = { [weak self] keyData in
            // Idle detection taps the raw hook, above routeKey's modal
            // branches, so a key typed into a Wayland client counts too.
            // Synthesized repeats don't: a stuck key is not a person.
            if keyData.type == .down { self?._noteUserActivity() }
            self?._trackKeyRepeat(keyData)
            return routeKey(keyData)
        }
        #endif
    }

    // MARK: - Spaces (virtual desktops)

    /// Switch the active space, macOS-style: the model flips immediately,
    /// then a 380ms eased slide carries the old space out and the new one in.
    /// A switch requested mid-slide retargets from the current destination.
    /// Switch the active space on ONE output — the host's switch is the
    /// animated slide the shell tree renders; a secondary snaps (its tree
    /// has no slide machinery yet; see multi-output.md staging). `onOutput`
    /// nil means the host, which is every pre-per-output call site's exact
    /// old meaning.
    func _switchToSpace(_ index: Int, animated: Bool = true,
                        carrying carriedId: String? = nil,
                        onOutput: Int? = nil) {
        let wm = windowManager
        let hostId = displayLayout?.host.id ?? 0
        let out = onOutput ?? hostId
        guard wm.spaces.indices.contains(index),
              wm.spaces[index].id != wm.activeSpaceId(onOutput: out) else { return }
        if out != hostId {
            let fromId = wm.activeSpaceId(onOutput: out)
            let fromIndex = wm.spaceIndex(ofSpaceId: fromId) ?? 0
            setState { wm.switchToSpace(index, onOutput: out) }
            if animated {
                _startSecondarySlide(onOutput: out, fromId: fromId,
                                     toId: wm.spaces[index].id,
                                     dir: index > fromIndex ? 1.0 : -1.0)
            }
            return
        }
        let from = wm.activeSpaceIndex
        setState {
            let fromId = wm.spaces[from].id
            wm.switchToSpace(index)
            if animated {
                _spaceSlide = (fromId, wm.activeSpace.id, index > from ? 1.0 : -1.0, carriedId)
            }
        }
        if animated { _startSpaceSlide() }
    }

    // MARK: Window rect zoom

    /// Animate a window's rect from wherever it is to `target` (macOS-style
    /// fullscreen zoom). The client is configured for the final size by the
    /// caller; the texture stretches during the zoom and sharpens when the
    /// client catches up — same contract as interactive resize.
    func _animateWindowRect(_ winId: String, to target: Rect, durationMs: Int = 320) {
        if let old = _windowRectAnims.removeValue(forKey: winId) {
            old.stop()
            old.dispose()
        }
        guard let win = windowManager.windows.first(where: { $0.id == winId }) else { return }
        let from = win.rect
        let c = AnimationController(duration: .milliseconds(durationMs), vsync: self)
        let curve = CurvedAnimation(parent: c, curve: Curves.easeInOutCubic)
        c.addListener { [weak self, weak win] in
            guard let self, let win else { return }
            let t = curve.value
            self.setState {
                win.rect = Rect.fromLTWH(
                    from.left + (target.left - from.left) * t,
                    from.top + (target.top - from.top) * t,
                    from.width + (target.width - from.width) * t,
                    from.height + (target.height - from.height) * t)
            }
        }
        c.addStatusListener { [weak self] status in
            guard let self, status == .completed else { return }
            if let done = self._windowRectAnims.removeValue(forKey: winId) {
                done.dispose()
            }
        }
        _windowRectAnims[winId] = c
        _ = c.forward(from: 0)
    }

    /// Toggle a window's fullscreen state with the macOS zoom: the model
    /// flips instantly (space bookkeeping included), then the rect animates
    /// between the windowed and fullscreen geometry. Returns the FINAL rect
    /// — callers must configure clients from it, not from win.rect, which
    /// is mid-animation.
    @discardableResult
    func _fullscreenWithZoom(_ winId: String) -> Rect? {
        guard let win = windowManager.windows.first(where: { $0.id == winId }) else { return nil }
        let fromRect = win.rect
        windowManager.fullscreenWindow(
            winId, screenWidth: screenWidth, screenHeight: screenHeight)
        let toRect = win.rect
        win.rect = fromRect
        _animateWindowRect(winId, to: toRect)
        return toRect
    }

    // MARK: Window chrome actions

    // What the traffic lights and the title-bar double-click do, as ONE
    // definition. Every widget tree that renders window chrome calls these:
    // this state's own build, and each secondary output's screen, whose
    // windows are separate DesktopWindow instances in their own Flutter view.
    // Spelling the closures out per tree is what left all three buttons dead
    // on a second monitor — the secondary passed only move/resize/raise, and
    // the rest defaulted to nil, so the buttons rendered and did nothing.

    /// Fullscreen chrome reveal — the shared flag behind the auto-hidden title
    /// bar. Every output's screen drives it from its own reveal zone; the
    /// pointer is only ever over one output, so whichever it is wins.
    ///
    /// A secondary output needs its own zone: the primary's lives in the
    /// primary tree and never sees a pointer event on another monitor. Without
    /// one, a window sent fullscreen on a second monitor has no title bar, no
    /// traffic lights, and no way back.
    var topBarRevealed: Bool { _topBarRevealed }

    func setTopBarRevealed(_ on: Bool) {
        guard _topBarRevealed != on else { return }
        setState { _topBarRevealed = on }
    }

    /// Same shape for the dock's own auto-hide sensor, so a secondary output
    /// hosting the dock can reveal it under a fullscreen window.
    var dockRevealed: Bool { _dockRevealed }

    func setDockRevealed(_ on: Bool) {
        guard _dockRevealed != on else { return }
        setState { _dockRevealed = on }
    }

    /// Close the dock icon's context menu — the barrier a secondary output
    /// puts under it when the dock is there.
    func dismissDockIconMenu() {
        guard _dockMenuAppId != nil else { return }
        setState { _dockMenuAppId = nil }
    }

    /// The desktop context menu positioned for `output`, or nil when it is
    /// closed or belongs to another screen. Same sharing shape as the dock:
    /// one state, drawn by exactly one tree.
    func contextMenuWidget(forOutput output: DisplayOutput) -> Widget? {
        guard let pos = contextMenuPosition,
              contextMenuOutputId == output.id else { return nil }
        return Positioned(
            left: pos.dx, top: pos.dy,
            child: SizedBox(width: 200, child: _buildContextMenu()))
    }

    /// Open the desktop context menu at `position` (output-local) on `output`
    /// — the secondary wallpaper's right-click.
    func openContextMenu(at position: Offset, onOutput outputId: Int) {
        setState {
            contextMenuPosition = position
            contextMenuOutputId = outputId
            activeStatusBarPopup = nil
        }
    }

    func dismissContextMenu() {
        guard contextMenuPosition != nil else { return }
        setState { contextMenuPosition = nil }
    }

    /// The open dock-icon context menu, laid out in `output`'s coordinates, or
    /// nil when nothing is open or the dock is elsewhere. Anchored above its
    /// icon and clamped to the output it is on — not to `screenWidth`, which is
    /// a different monitor's width once the primary moves.
    func dockIconMenuWidget(forOutput output: DisplayOutput) -> Widget? {
        guard output.isPrimary, let menuAppId = _dockMenuAppId else { return nil }
        let menuWidth = 200.0
        let menuLeft = max(8, min(_dockMenuAnchorX - menuWidth / 2,
                                  output.logicalWidth - menuWidth - 8))
        return Positioned(
            left: menuLeft,
            bottom: DesktopTheme.kDockBottomMargin
                + DesktopTheme.kDockHeight + 10,
            child: SizedBox(
                width: menuWidth,
                child: _buildDockIconMenu(for: menuAppId)))
    }

    /// The dock laid out for `output`, or nil when that output should not draw
    /// it. There is exactly one dock and it belongs to the primary display, so
    /// this answers nil everywhere else — including in the shell's own tree
    /// once the user has made another monitor primary.
    ///
    /// The hide rules match the primary tree's: no dock in a workspace space
    /// (every window there belongs to an agent), and none under a fullscreen
    /// window until the bottom sensor reveals it.
    func dockWidget(forOutput output: DisplayOutput) -> Widget? {
        guard output.isPrimary,
              !windowManager.activeSpace(onOutput: output.id).isSpecial
        else { return nil }
        if fullscreenWindow(onOutput: output) != nil && !_dockRevealed { return nil }
        // Same builder the host tree uses, so a secondary monitor cannot end
        // up drawing a different bar from the primary's.
        return chrome.bottomBar(forOutput: output, opacity: 1)
    }

    // MARK: - Chrome seam (macOS style)
    //
    // The macOS half of `ShellChrome`. These hold the PLACEMENT that used to
    // sit inline in `_buildShellRoot`; the drawing is still the `_build*`
    // methods further down. `MacosChrome` (ShellStyle.swift) forwards to them.
    // They live in this file rather than beside `MacosChrome` because they
    // reach private builders, and `private` in Swift is file-scoped.

    /// The menu bar: a frosted strip across the top. Blurred and saturated so
    /// the clock and the status icons stay legible over any wallpaper — or
    /// over whatever window content has scrolled underneath.
    func macosTopBar() -> Widget {
        Positioned(
            left: 0.0, top: 0.0, right: 0.0,
            height: DesktopTheme.kStatusBarHeight,
            child: ClipRect(
                child: BackdropFilter(
                    filter: ImageFilterFactory.compose(
                        outer: ColorFilter(matrix: _saturationMatrix(1.15)),
                        inner: ImageFilterFactory.blur(sigmaX: 18, sigmaY: 18)
                    ),
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: shellTheme.barTint,
                            border: Border(
                                bottom: BorderSide(
                                    color: shellTheme.barHairline, width: 1)
                            )
                        ),
                        child: _buildStatusBar()
                    )
                )
            )
        )
    }

    /// The dock. The container is taller than the pill: magnified icons and
    /// the app-name label grow upward out of it.
    ///
    /// `opacity` below 1 is a space slide or a fullscreen auto-hide fading it
    /// out, and a fading dock stops taking input — a half-transparent dock you
    /// can still click is a dock you click by accident.
    func macosDock(forOutput output: DisplayOutput, opacity: Double) -> Widget? {
        guard opacity > 0.01 else { return nil }
        let metrics = _dockMetrics(outputWidth: output.logicalWidth)
        let dock = _buildDock(
            appIds: _dockDisplayApps, metrics: metrics,
            dockTop: output.logicalHeight - DesktopTheme.kDockBottomMargin
                - DesktopTheme.kDockHeight)
        return Positioned(
            left: metrics.left,
            bottom: DesktopTheme.kDockBottomMargin,
            width: metrics.width,
            height: DesktopTheme.kDockContainerHeight,
            child: opacity < 0.99
                ? IgnorePointer(child: Opacity(opacity: opacity, child: dock))
                : dock
        )
    }

    /// Start: a panel above the taskbar rather than a full screen.
    func fluentStartMenu() -> Widget {
        Positioned(
            fill: (),
            child: FluentStartMenu(
                apps: _launcherFilteredApps(),
                installedCount: AppRegistry.shared.installedApps.count,
                query: _launcherQuery,
                caretResetToken: _launcherCaretToken,
                userName: LoginUser.name,
                screenWidth: screenWidth,
                screenHeight: screenHeight,
                onLaunch: { [self] appId in _launchFromLauncher(appId) },
                onPower: { [self] in
                    setState {
                        _launcherOpen = false
                        _launcherQuery = ""
                        _launcherDriverTarget = nil
                    }
                    _fluentOpenPopup(.power)
                },
                onDismiss: { [self] in
                    setState {
                        _launcherOpen = false
                        _launcherQuery = ""
                        _launcherDriverTarget = nil
                    }
                }
            )
        )
    }

    /// Launchpad: the full-screen grid over a dimmed wallpaper.
    func macosLauncher() -> Widget {
        Positioned(
            fill: (),
            child: AppLauncher(
                apps: _launcherFilteredApps(),
                query: _launcherQuery,
                caretResetToken: _launcherCaretToken,
                onLaunch: { [self] appId in _launchFromLauncher(appId) },
                onDismiss: { [self] in
                    setState {
                        _launcherOpen = false
                        _launcherQuery = ""
                        _launcherDriverTarget = nil
                    }
                }
            )
        )
    }

    /// A status-bar panel, hung under the item that opened it, aligned with
    /// the icon that opened it.
    func macosStatusFlyout(_ kind: StatusBarPopup) -> Widget {
        let o = macosStatusFlyoutOrigin(kind)
        return Positioned(left: o.dx, top: o.dy, child: _buildStatusBarPopup())
    }

    func macosStatusFlyoutOrigin(_ kind: StatusBarPopup) -> Offset {
        Offset(_statusPopupGeometry(kind).left, DesktopTheme.kStatusBarHeight + 1)
    }

    /// The width every status panel is laid out at. One number, shared by the
    /// panel and by the glass filter under it.
    func statusFlyoutWidth(_ kind: StatusBarPopup) -> Double {
        _statusPopupGeometry(kind).width
    }

    /// The desktop's right-click menu, at the pointer.
    func macosDesktopMenu() -> Widget {
        Positioned(
            left: contextMenuPosition?.dx ?? 0,
            top: contextMenuPosition?.dy ?? 0,
            child: SizedBox(width: 200, child: _buildContextMenu())
        )
    }

    /// Unmagnified dock slot centres in `output`'s own coordinates. The
    /// pointer is not over the dock yet when a caller asks where to move, so
    /// the magnified geometry would be the wrong answer.
    func macosDockSlots(forOutput output: DisplayOutput)
        -> [(app: String, x: Double, y: Double, size: Double)] {
        let metrics = _dockMetrics(outputWidth: output.logicalWidth)
        let ids = ["launcher"] + _dockDisplayApps
        let y = output.logicalHeight
            - DesktopTheme.kDockBottomMargin
            - DesktopTheme.kDockIconBottomInset - DesktopTheme.kDockIconSize / 2
        return ids.enumerated().prefix(metrics.baseCenters.count).map { i, id in
            (app: id,
             x: metrics.baseLeft + metrics.baseCenters[i],
             y: y,
             size: DesktopTheme.kDockIconSize)
        }
    }

    // MARK: - Chrome seam (Fluent style)

    /// An app's mark for the Fluent chrome: the GLYPH ALONE, with no tile
    /// behind it.
    ///
    /// This is the single biggest thing that made the taskbar read as the
    /// wrong desktop. Our first-party icons are macOS-shaped -- a coloured
    /// rounded square with a white glyph punched out of it -- and a row of
    /// those is a dock however Windows-like the bar under them is. Windows'
    /// taskbar icons are free-standing artwork sitting directly on the strip:
    /// no container, no fill, the mark carries its own colour.
    ///
    /// Third-party apps are unaffected either way, because their icon is a
    /// real image from their own install and already looks like itself.
    func fluentIconVisual(appId: String, size: Double) -> Widget {
        if let texId = iconTextures[appId] {
            return TextureWidget(textureId: Int(texId), filterQuality: .medium)
        }
        return SizedBox(
            width: size, height: size,
            child: CustomPaint(
                painter: IconPainter(_iconType(for: appId),
                                     color: _dockIconColor(for: appId))))
    }


    /// The taskbar. Unlike the dock it draws for the whole width of the
    /// output, so there is no centring to compute here — `FluentTaskbar` does
    /// its own, against the screen rather than against the space left over.
    func fluentTaskbar(forOutput output: DisplayOutput,
                       opacity: Double) -> Widget? {
        guard opacity > 0.01 else { return nil }
        let focusedApp = windowManager.focusedWindowId.flatMap { id in
            windowManager.windows.first { $0.id == id }
        }.flatMap { _appOwning($0)?.id }

        let tiles: [TaskbarTile] = _dockDisplayApps.map { appId in
            TaskbarTile(
                appId: appId,
                name: AppRegistry.shared.app(id: appId)?.name ?? appId,
                visual: fluentIconVisual(appId: appId, size: FluentBar.icon),
                isRunning: _isAppRunning(appId),
                isFocused: appId == focusedApp
            )
        }

        // The readout the status group shows. Volume is deliberately absent:
        // `_ccAudio` is only refreshed while the control centre is open, so a
        // speaker glyph here would show last week's mute state. It joins when
        // Quick Settings brings its own refresh.
        var statusIcons: [IconData] = [_fluentNetworkIcon()]
        if batteryService.snapshot.present {
            statusIcons.append(_fluentBatteryIcon())
        }

        let status = TaskbarStatus(
            statusIcons: statusIcons,
            statusActive: activeStatusBarPopup == .controlCenter,
            // The clock renders itself — see `ShellClock`.
            clockFormat: "h:mm a",
            dateFormat: "M/d/yyyy",
            clockActive: activeStatusBarPopup == .clock,
            showBell: !_notifications.isEmpty || _notificationsUnseen,
            bellTinted: _notificationsUnseen,
            bellActive: activeStatusBarPopup == .notifications
        )

        let bar = FluentTaskbar(
            tiles: tiles,
            status: status,
            outputWidth: output.logicalWidth,
            startActive: _launcherOpen,
            hoveredIndex: _fluentHoverIndex,
            onStart: { [self] in
                _loadIconTextures()
                openLauncher()
            },
            onTile: { [self] appId in _launchOrFocusApp(appId) },
            onTileMenu: { [self] appId in
                setState {
                    contextMenuPosition = nil
                    activeStatusBarPopup = nil
                    _dockMenuAppId = appId
                    _dockMenuAnchorX = _dockIconAnchorX(appId: appId)
                }
            },
            onStatus: { [self] in _fluentOpenPopup(.controlCenter) },
            onClock: { [self] in _fluentOpenPopup(.clock) },
            onBell: { [self] in _fluentOpenPopup(.notifications) }
        )

        return Positioned(
            left: 0, right: 0, bottom: 0,
            height: DesktopTheme.kDockContainerHeight,
            child: opacity < 0.99
                ? IgnorePointer(child: Opacity(opacity: opacity, child: bar))
                : bar
        )
    }

    /// Which taskbar tile the pointer is over (0 = Start), or nil.
    var _fluentHoverIndex: Int? = nil

    /// Global-hover hook for the taskbar, and the ONLY place a leave is
    /// visible: a Listener on a tile hears every enter and no exit, so the
    /// name label would stick there after the pointer moved up onto a window.
    /// Purely geometric, so it keeps working whatever is under the cursor.
    func fluentNoteBarHover(x: Double, y: Double, outputId: Int) {
        let output = dockOutput
        var next: Int? = nil
        if outputId == output.id,
           y >= output.logicalHeight - DesktopTheme.kDockHeight {
            let count = _dockDisplayApps.count + 1
            let rel = x - FluentBar.clusterLeft(
                count: count, outputWidth: output.logicalWidth)
            let idx = Int((rel / FluentBar.pitch).rounded(.down))
            // Inside a tile, not in the gap between two of them.
            if rel >= 0, idx < count,
               rel - Double(idx) * FluentBar.pitch <= FluentBar.tile {
                next = idx
            }
        }
        if next != _fluentHoverIndex { setState { _fluentHoverIndex = next } }
    }

    /// The hovered tile's preview: a LIVE thumbnail of each of the app's
    /// windows, or just its name when it has none.
    ///
    /// "Live" is not a stretch here -- the thumbnail is the very texture the
    /// compositor is scanning that window out of, the same one Mission
    /// Control's cards use, so it costs one more quad and is never stale.
    ///
    /// Geometry is our Windows shell's (`kPreviewThumb*` in
    /// sdk/Examples/WinShellBar/Dock.swift), so the two look alike; the panel
    /// grows to the right as an app collects windows and is clamped to the
    /// screen so a tile near either edge still shows its whole preview.
    func fluentHoverPreview() -> Widget? {
        guard let idx = _fluentHoverIndex, idx > 0 else { return nil }
        let apps = _dockDisplayApps
        guard idx - 1 < apps.count else { return nil }
        let appId = apps[idx - 1]
        let name = AppRegistry.shared.app(id: appId)?.name ?? appId
        let wins = windowManager.windows.filter {
            _appOwning($0)?.id == appId && !_closingWindows.contains($0.id)
        }

        let count = max(wins.count, 1)
        let panelW = wins.isEmpty
            ? 180.0
            : Double(count) * (Self.kPreviewThumbW + Self.kPreviewPad) + Self.kPreviewPad
        let panelH = wins.isEmpty
            ? 30.0
            : Self.kPreviewPad + Self.kPreviewTitleH + Self.kPreviewThumbH
                + Self.kPreviewPad

        let cx = FluentBar.tileCenterX(index: idx, count: apps.count + 1,
                                       outputWidth: screenWidth)
        let left = max(6, min(cx - panelW / 2, screenWidth - panelW - 6))

        let body: Widget = wins.isEmpty
            ? Center(child: Text(name, style: fluentType.styled(
                { $0.body }, shellTheme.fgPrimary)))
            : Row(mainAxisSize: .min, children: wins.map { w in
                Padding(
                    padding: EdgeInsets(left: Self.kPreviewPad, top: Self.kPreviewPad,
                                        right: 0, bottom: Self.kPreviewPad),
                    child: Column(mainAxisSize: .min,
                                  crossAxisAlignment: .start, children: [
                        SizedBox(
                            width: Self.kPreviewThumbW, height: Self.kPreviewTitleH,
                            child: Text(w.title.isEmpty ? name : w.title,
                                        style: fluentType.styled(
                                            { $0.caption }, shellTheme.fgSecondary),
                                        overflow: .ellipsis, maxLines: 1)),
                        SizedBox(
                            width: Self.kPreviewThumbW, height: Self.kPreviewThumbH,
                            child: _fluentThumb(w)),
                    ]))
            })

        return Positioned(
            left: left,
            bottom: DesktopTheme.kDockHeight + 8,
            width: panelW, height: panelH,
            child: IgnorePointer(child: DecoratedBox(
                decoration: BoxDecoration(
                    color: shellTheme.panelFill,
                    border: Border.all(color: shellTheme.panelStroke, width: 1),
                    borderRadius: BorderRadius.circular(
                        shellMetrics.panelCornerRadius),
                    boxShadow: [
                        BoxShadow(color: shellTheme.popupShadow,
                                  offset: Offset(0, 4), blurRadius: 16),
                    ]
                ),
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                        shellMetrics.panelCornerRadius),
                    child: body)
            ))
        )
    }

    /// One window's live thumbnail, or a placeholder for a window that has no
    /// texture yet -- a client that has mapped but not drawn.
    private func _fluentThumb(_ w: WindowInfo) -> Widget {
        guard let texId = w.textureId else {
            return DecoratedBox(
                decoration: BoxDecoration(color: shellTheme.controlFill),
                child: SizedBox(expand: ()))
        }
        // Fitted, not stretched: the thumbnail box is 16:9 and windows are
        // not, so scaling the texture to fill it squashes whatever is in
        // them. Windows letterboxes each preview to its window's shape and
        // so does this.
        return DecoratedBox(
            decoration: BoxDecoration(color: shellTheme.controlFill),
            child: FittedBox(
                fit: .contain,
                child: SizedBox(
                    width: max(w.rect.width, 1),
                    height: max(w.rect.height, 1),
                    // `.medium`, not `.low`: a window is minified about
                    // four times to reach this box, and `.low` is a plain
                    // bilinear sample that aliases badly that far down --
                    // text in the preview came out mush. `.medium` mipmaps,
                    // which is precisely the case mipmaps exist for, and at
                    // this size costs nothing worth measuring.
                    child: TextureWidget(textureId: texId,
                                         filterQuality: .medium))))
    }

    /// The Windows shell's own preview geometry, so the two shells' previews
    /// are the same size.
    static let kPreviewThumbW: Double = 208
    static let kPreviewThumbH: Double = 117
    static let kPreviewTitleH: Double = 20
    static let kPreviewPad: Double = 10

    /// Open (or close) a status panel from the taskbar. Same reset discipline
    /// as the menu bar's items — every open starts on the panel's own first
    /// screen, never on last week's password prompt or on
    /// "Shut down the computer?".
    private func _fluentOpenPopup(_ kind: StatusBarPopup) {
        let isActive = activeStatusBarPopup == kind
        setState {
            activeStatusBarPopup = isActive ? nil : kind
            if activeStatusBarPopup == .notifications { _notificationsUnseen = false }
            if activeStatusBarPopup == .controlCenter { _refreshControlCenter() }
            contextMenuPosition = nil
            _powerConfirm = nil
            _wifiPasswordSSID = nil
            _wifiPassword = ""
            _wifiError = nil
        }
        if activeStatusBarPopup == .wifi { networkService.refreshWithScan() }
    }

    /// Status panels come UP from the bottom-right corner, where Windows puts
    /// them, rather than down from a menu bar that this style does not have.
    /// They are all anchored to the same corner, unlike the macOS ones, which
    /// each hang under their own menu-bar icon — Windows has one tray, and
    /// everything it opens comes from there.
    func fluentStatusFlyout(_ kind: StatusBarPopup) -> Widget {
        Positioned(
            left: fluentStatusFlyoutOrigin(kind, height: 0).dx,
            bottom: DesktopTheme.kDockHeight + Self.kFluentFlyoutGap,
            child: _buildStatusBarPopup()
        )
    }

    static let kFluentFlyoutGap: Double = 8

    /// The same corner, resolved to a top-left once the panel has measured
    /// itself — which is what the glass filter underneath needs.
    func fluentStatusFlyoutOrigin(_ kind: StatusBarPopup,
                                  height: Double) -> Offset {
        Offset(
            max(8, screenWidth - statusFlyoutWidth(kind) - 8),
            screenHeight - DesktopTheme.kDockHeight - Self.kFluentFlyoutGap - height
        )
    }

    /// The network glyph, in the Fluent icon language. Signal strength is not
    /// modelled yet, so a connected Wi-Fi shows full bars — the states that
    /// matter (no adapter, radio off, connecting) are the ones that differ.
    private func _fluentNetworkIcon() -> IconData {
        let snap = networkService.snapshot
        if snap.wired?.connected == true { return FluentSystemIcons.ethernet }
        if !snap.available || !snap.wifiEnabled { return FluentSystemIcons.wifiOff }
        if snap.active == nil { return FluentSystemIcons.wifiWarning }
        return FluentSystemIcons.wifiFull
    }

    /// The same thresholds the menu bar's glyph uses, so the two styles never
    /// disagree about how full the battery is.
    private func _fluentBatteryIcon() -> IconData {
        let snap = batteryService.snapshot
        if snap.state == .charging { return FluentSystemIcons.batteryCharging }
        switch snap.percent {
        case ..<13: return FluentSystemIcons.batteryEmpty
        case ..<45: return FluentSystemIcons.batteryHalf
        default:    return FluentSystemIcons.battery
        }
    }

    /// Yellow. Deferred: the scale-effect zoom into the dock plays first;
    /// `_finalizeWindowMinimize` hides the window.
    func requestWindowMinimize(_ winId: String) {
        setState {
            _minimizingWindows.insert(winId)
        }
    }

    /// Red. Teardown is deferred to `_finalizeWindowClose` (fired by the close
    /// animation) so the shrink-out plays over live window content.
    func requestWindowClose(_ winId: String) {
        setState {
            _closingWindows.insert(winId)
        }
    }

    /// Green — fullscreen toggle, with the client reconfigured from the rect
    /// the zoom lands on.
    func requestWindowMaximize(_ winId: String) {
        // What this control MEANS is the style's business. macOS's green
        // takes the window fullscreen onto its own space; Windows' square
        // maximises it into the work area and leaves the caption and taskbar
        // alone. Sending the Windows one to fullscreen hid both, and left no
        // visible way back short of finding the top-edge reveal.
        guard shellStyle.maximizeIsFullscreen else {
            setState {
                windowManager.maximizeWindow(
                    winId, screenWidth: screenWidth, screenHeight: screenHeight)
                _windowChildCache.removeValue(forKey: winId)
            }
            if let w = windowManager.windows.first(where: { $0.id == winId }) {
                let contentW = w.rect.width
                let contentH = w.rect.height - DesktopTheme.kTitleBarHeight
                if contentW > 0, contentH > 0 {
                    if let surfId = waylandIntegration?.surfaceId(forWindowId: winId) {
                        waylandIntegration?.sendResize(
                            surfaceId: surfId,
                            width: Int(contentW), height: Int(contentH))
                    } else {
                        // DMA-BUF child process (Files, Settings, …) — the
                        // same reconfigure the fullscreen branch below does.
                        // Telling only the Wayland half is what made a
                        // maximised first-party app come up blurry: the child
                        // kept its launch-size buffer (Files: 980x540) and the
                        // shell stretched that texture across the work area,
                        // with hit-testing no longer matching the screen.
                        w.onContentResize?(contentW, contentH)
                    }
                }
            }
            return
        }
        let wasFullscreen = windowManager.windows.first(where: { $0.id == winId })?.isFullscreen ?? false
        setState {
            // The zoom animates win.rect — configure clients from the FINAL
            // rect it returns.
            guard let finalRect = _fullscreenWithZoom(winId) else { return }
            guard let w = windowManager.windows.first(where: { $0.id == winId }) else { return }
            if let surfId = waylandIntegration?.surfaceId(forWindowId: winId) {
                if w.isFullscreen {
                    // Entering fullscreen — content fills the window; title bar
                    // overlays on top only when revealed.
                    waylandIntegration?.sendFullscreenResize(
                        surfaceId: surfId,
                        width: Int(finalRect.width),
                        height: Int(finalRect.height))
                } else {
                    // Exiting fullscreen → restored to pre-fullscreen rect
                    let contentW = finalRect.width
                    let contentH = finalRect.height - DesktopTheme.kTitleBarHeight
                    if wasFullscreen {
                        waylandIntegration?.sendExitFullscreen(
                            surfaceId: surfId,
                            width: Int(contentW),
                            height: Int(contentH))
                    } else {
                        w.onContentResize?(contentW, contentH)
                    }
                }
            } else {
                // DMA-BUF child process (Settings, viewer, …): without this it
                // keeps its old buffer and the shell stretches it — 2x-scaled
                // UI whose hit-testing no longer matches the screen.
                let contentH = w.isFullscreen
                    ? finalRect.height
                    : finalRect.height - DesktopTheme.kTitleBarHeight
                if finalRect.width > 0 && contentH > 0 {
                    w.onContentResize?(finalRect.width, contentH)
                }
            }
        }
    }

    /// macOS-style: double-click the title bar toggles maximized state. Skipped
    /// while fullscreen — the green button owns that.
    func requestWindowTitleBarDoubleTap(_ winId: String) {
        guard let w = windowManager.windows.first(where: { $0.id == winId }),
              !w.isFullscreen else { return }
        setState {
            windowManager.maximizeWindow(
                winId,
                screenWidth: screenWidth,
                screenHeight: screenHeight
            )
        }
        // Tell the wayland client about its new content size.
        let contentW = w.rect.width
        let contentH = w.rect.height - DesktopTheme.kTitleBarHeight
        if contentW > 0 && contentH > 0 {
            w.onContentResize?(contentW, contentH)
        }
    }

    // MARK: Edge-drag carry

    /// Called on every window-drag move: arm (or re-arm/cancel) the dwell
    /// when the pointer is pressed against a screen edge with a space on
    /// that side.
    func _checkEdgeCarry(_ winId: String) {
        guard !_missionControlOpen, let pos = _dragPointerPos else { return }
        // The carry edges are the VIRTUAL desktop's outer boundary. An
        // inner edge is a seam — the pointer crosses it onto the next
        // monitor, and arming a space carry there would hijack every
        // cross-screen drag. The host sits at the origin, so its left edge
        // is outer iff nothing extends further left, ditto right.
        let dl = displayLayout
        let hostIsLeftmost = dl.map { $0.host.logicalLeft <= $0.virtualBounds.left } ?? true
        let hostIsRightmost = dl.map { $0.host.logicalRight >= $0.virtualBounds.right } ?? true
        let dir: Int
        if pos.dx <= _edgeCarryZonePx && hostIsLeftmost {
            dir = -1
        } else if pos.dx >= screenWidth - _edgeCarryZonePx && hostIsRightmost {
            dir = 1
        } else {
            dir = 0
        }
        guard dir != _edgeCarryArmedDir else { return }
        _edgeCarryToken += 1  // invalidate any pending dwell
        _edgeCarryArmedDir = dir
        guard dir != 0 else { return }
        let token = _edgeCarryToken
        let fire: () -> Void = { [weak self] in
            guard let self, self._edgeCarryToken == token else { return }
            self._edgeCarryArmedDir = 0
            self._fireEdgeCarry(winId, dir)
        }
        // Main-queue-only state; the @Sendable coercion is safe (codebase
        // idiom — see _recordStatusPopupHeight).
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(_edgeCarryDwellMs),
            execute: unsafeBitCast(fire, to: (@Sendable () -> Void).self))
    }

    /// Pointer released anywhere — disarm the dwell.
    func _cancelEdgeCarry() {
        _edgeCarryToken += 1
        _edgeCarryArmedDir = 0
        _dragPointerPos = nil
    }

    /// Dwell elapsed at an edge: carry the dragged window to the adjacent
    /// USER space (fullscreen windows own their space; private fullscreen
    /// spaces accept no guests) and slide over with the window pinned
    /// under the cursor. Holding at the edge re-arms for the next space.
    private func _fireEdgeCarry(_ winId: String, _ direction: Int) {
        let wm = windowManager
        guard let win = wm.windows.first(where: { $0.id == winId }),
              !win.isFullscreen, !win.isMinimized else { return }
        let target = wm.activeSpaceIndex + direction
        guard wm.spaces.indices.contains(target), wm.spaces[target].isUser else { return }
        setState {
            wm.moveWindow(winId, toSpaceIndex: target)
            wm.bringToFront(winId)
        }
        _switchToSpace(target, carrying: winId)
    }

    // MARK: - Workspace entry/exit

    /// Ctrl+Down / context menu: toggle between workspace mode and the
    /// desktop. The space is created lazily on first entry and persists;
    /// leaving returns to the space the user came from, and refuses to strand
    /// them on it if that index has since gone away.
    func _toggleWorkspaceSpace() {
        let wm = windowManager
        // Per-output: the toggle acts on the monitor the pointer is on —
        // entering there leaves every other monitor's desktop (or its own
        // workspace) alone, and each output remembers its own way back.
        let out = _pointerOutputId ?? displayLayout?.primary.id ?? 0
        if wm.activeSpace(onOutput: out).isWorkspace {
            var back = _workspaceReturnByOutput[out]
                ?? wm.spaces.indices.first(where: { wm.spaces[$0].isUser }) ?? 0
            if !wm.spaces.indices.contains(back) || wm.spaces[back].isSpecial {
                back = wm.spaces.indices.first(where: { wm.spaces[$0].isUser }) ?? 0
            }
            _switchToSpace(back, onOutput: out)
            // Leaving workspace mode: nothing draws the agent's windows any
            // more, so put their throttle back. The entering side is handled
            // by _buildWorkspaceSpace; this is the only path out.
            _applyAgentWindowThrottle()
            return
        }
        _workspaceReturnByOutput[out] = wm.spaceIndex(
            ofSpaceId: wm.activeSpaceId(onOutput: out)) ?? wm.activeSpaceIndex
        var idx: Int = 0
        setState {
            idx = wm.ensureWorkspaceSpace()
            // Entering with nothing to show — no workspaces at all, or every
            // one already displayed on another monitor — mints a fresh one,
            // so each output's workspace mode always has its own.
            if wm.selectedWorkspace(onOutput: out) == nil {
                wm.addWorkspace(onOutput: out)
            }
        }
        _switchToSpace(idx, onOutput: out)
    }

    /// In-flight space slides on SECONDARY outputs, keyed by output id —
    /// the host's slide is `_spaceSlide` in this tree; each secondary's is
    /// rendered by its own `SecondaryOutputScreen` from this table. Ticks
    /// drive the output's force-redraw hook (the gated invalidator would
    /// drop animation-only frames).
    var _secondarySlides:
        [Int: (fromId: Int, toId: Int, dir: Double,
               curve: CurvedAnimation, controller: AnimationController)] = [:]

    private func _startSecondarySlide(onOutput out: Int, fromId: Int,
                                      toId: Int, dir: Double) {
        _secondarySlides[out]?.controller.stop()
        let c = AnimationController(duration: .milliseconds(380), vsync: self)
        let curve = CurvedAnimation(parent: c, curve: Curves.easeInOutCubic)
        _secondarySlides[out] = (fromId, toId, dir, curve, c)
        c.addListener { secondaryScreenForceRedraws[out]?() }
        c.addStatusListener { [weak self] status in
            guard status == .completed else { return }
            self?._secondarySlides.removeValue(forKey: out)
            secondaryScreenForceRedraws[out]?()
        }
        _ = c.forward(from: 0)
    }

    private func _startSpaceSlide() {
        if _spaceSlideController == nil {
            let c = AnimationController(duration: .milliseconds(380), vsync: self)
            c.addListener { [weak self] in
                self?.setState {}
            }
            c.addStatusListener { [weak self] status in
                guard let self, status == .completed else { return }
                self.setState { self._spaceSlide = nil }
            }
            _spaceSlideController = c
            _spaceSlideCurve = CurvedAnimation(parent: c, curve: Curves.easeInOutCubic)
        }
        _ = _spaceSlideController?.forward(from: 0)
    }

    /// Open the Mission Control overview (Ctrl+Up / context menu). The
    /// exposé cards animate from the windows' desktop rects into the grid.
    /// With `pickRecordTarget` the same overview opens as the Record-App
    /// window picker instead (see _mcPickRecordTarget).
    func _openMissionControl(pickRecordTarget: Bool = false) {
        guard !_missionControlOpen else { return }
        // Invoked-output-scoped (macOS: the display you're addressing is the
        // pointer's): the overview shows THIS monitor's windows and drives
        // THIS monitor's space.
        _missionControlOutputId = _pointerOutputId ?? displayLayout?.host.id ?? 0
        // Mission Control shows desktops; from inside a special space, exit
        // to the return space first (neither has a strip thumbnail).
        if windowManager.activeSpace(onOutput: _missionControlOutputId).isSpecial {
            var back = _workspaceReturnByOutput[_missionControlOutputId]
                ?? windowManager.spaces.indices.first(where: {
                    windowManager.spaces[$0].isUser }) ?? 0
            if !windowManager.spaces.indices.contains(back)
                || windowManager.spaces[back].isSpecial {
                back = windowManager.spaces.indices.first(where: { windowManager.spaces[$0].isUser }) ?? 0
            }
            _switchToSpace(back, animated: false, onOutput: _missionControlOutputId)
        }
        setState {
            _missionControlOpen = true
            _mcPickRecordTarget = pickRecordTarget
            contextMenuPosition = nil
            activeStatusBarPopup = nil
            _launcherOpen = false
        }
        if _mcOpenController == nil {
            let c = AnimationController(duration: .milliseconds(300), vsync: self)
            c.addListener { [weak self] in
                self?.setState {}
                // On a secondary, animation-only ticks change no signature —
                // the gated invalidator drops them; the force hook doesn't.
                if let self, !self.mcIsOnHost {
                    secondaryScreenForceRedraws[self._missionControlOutputId]?()
                }
            }
            c.addStatusListener { [weak self] status in
                // Reverse run reached the desktop layout — finish the close.
                guard let self, status == .dismissed, self._mcClosing else { return }
                self._closeMissionControl()
            }
            _mcOpenController = c
            _mcOpenCurve = CurvedAnimation(parent: c, curve: Curves.easeInOutCubic)
        }
        _mcClosing = false
        _ = _mcOpenController?.forward(from: 0)
    }

    /// Immediate teardown (dock launches, and the tail end of the animated
    /// close).
    func _closeMissionControl() {
        setState {
            _missionControlOpen = false
            _mcPickRecordTarget = false
            _mcClosing = false
            _mcDragWindowId = nil
            _mcDragStart = nil
            _mcDragPos = nil
            _mcDragMoved = false
            _mcRelayoutFrom = [:]
            _mcDeparting = nil
        }
    }

    /// Animated close: the exposé cards fly back to their desktop rects
    /// (the open controller runs in reverse), then the overlay tears down.
    func _closeMissionControlAnimated() {
        guard _missionControlOpen, !_mcClosing else { return }
        guard let c = _mcOpenController else {
            _closeMissionControl()
            return
        }
        setState {
            _mcClosing = true
            _mcDragWindowId = nil
            _mcDragStart = nil
            _mcDragPos = nil
            _mcDragMoved = false
        }
        _ = c.reverse()
    }

    /// The Record-App picker chose `win`: close the overview and start a
    /// window recording once the cards have flown home. The capture reads
    /// the window's OWN texture, so the recording's dimensions are the
    /// content area's (no shell title bar), the picker overlay never
    /// appears in the footage, and overlap/moves/minimizing stay invisible.
    func _startWindowRecording(_ win: WindowInfo) {
        guard let texId = win.textureId else { return }
        let winId = win.id
        let label = _record(win.appId)?.name ?? win.title
        let dpi = currentShellDpi
        let cw = Int(win.rect.width * dpi)
        let ch = Int((win.rect.height - DesktopTheme.kTitleBarHeight) * dpi)
        let wm = windowManager
        let topDown = win.flipTextureY
        _closeMissionControlAnimated()
        // The aliveness check captures the (non-Sendable) window manager;
        // main-queue-only by construction — the codebase's unsafeBitCast
        // hop, same as the timers.
        let begin: () -> Void = {
            recordingService?.start(
                texture: Int64(texId), width: cw, height: ch,
                textureTopDown: topDown,
                windowAlive: {
                    wm.windows.contains(where: { $0.id == winId })
                },
                // Where the window's content is RIGHT NOW, in physical px:
                // the capture is window-space, so this is the only thing
                // that can place the screen-space pointer. Same title-bar
                // offset the texture size above uses — the texture is the
                // client's content, and the bar is drawn by the shell.
                // nil while the window is not on screen, so the cursor is
                // left out instead of pinned to a stale spot.
                windowRect: {
                    guard let w = wm.windows.first(where: { $0.id == winId }),
                          !w.isMinimized,
                          w.spaceId == wm.activeSpace.id else { return nil }
                    return (Int(w.rect.left * dpi),
                            Int((w.rect.top + DesktopTheme.kTitleBarHeight) * dpi),
                            Int(w.rect.width * dpi),
                            Int((w.rect.height - DesktopTheme.kTitleBarHeight) * dpi))
                },
                windowLabel: label)
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(350),
            execute: unsafeBitCast(begin, to: (@Sendable () -> Void).self))
    }

    /// Carry the focused window to the space at `index` and follow it there
    /// (Ctrl+Shift+←/→). Fullscreen windows own their space and don't move;
    /// with nothing to carry this degrades to a plain switch. The carried
    /// window is pinned during the slide — it stays put while the desktop
    /// changes behind it (same visual as the edge-drag carry).
    private func _moveFocusedWindowToSpace(_ index: Int) {
        var carriedId: String? = nil
        if let fid = windowManager.focusedWindowId,
           let win = windowManager.windows.first(where: { $0.id == fid }),
           // Agent-owned windows (e.g. the focused agent terminal in the
           // a workspace) never move onto a desktop via carry.
           win.ownerAgentId == nil,
           !win.isFullscreen, !win.isMinimized {
            setState {
                windowManager.moveWindow(fid, toSpaceIndex: index)
                windowManager.bringToFront(fid)
            }
            carriedId = fid
        }
        _switchToSpace(index, carrying: carriedId)
    }

    /// Wire up X11Integration callbacks to create/destroy windows.
    private func _setupX11Callbacks() {
        #if os(Linux)
        guard let x11 = x11Integration else { return }

        // A connect arms the capture poll; a disconnect stops it. Nothing else
        // announces an X screen capture, so this is the pump's only remaining
        // reason to run on a desktop that is otherwise doing nothing -- and on
        // a Wayland-only desktop it never runs at all.
        x11.onClientCountChanged = {
            DispatchQueue.main.async { _shellState?._reevaluateFramePump() }
        }

        x11.onNewWindow = { [weak self] (windowId: UInt32, textureId: Int, title: String,
                                           x: Int, y: Int, width: Int, height: Int) -> String in
            guard let self = self else { return "" }
            let appId = "x11-\(windowId)"
            var shellWindowId = ""
            // Honor the client's requested geometry (physical px → logical),
            // centered on screen when unplaced. Forcing X11 windows fullscreen
            // (the old Chrome-kiosk behavior) breaks apps with real dialog
            // windows — WeChat's 296x402 login ends up stretched, and the
            // follow-up fullscreen resize confuses Qt's swapchain sizing.
            let dpi = currentShellDpi
            let screenLogW = (PlatformDispatcher.instance.implicitView?.physicalSize.width ?? 3840.0) / dpi
            let screenLogH = (PlatformDispatcher.instance.implicitView?.physicalSize.height ?? 2160.0) / dpi
            let winLogW = max(80.0, Double(width) / dpi)
            let winLogH = max(60.0, Double(height) / dpi) + DesktopTheme.kTitleBarHeight
            let winLogX = (x != 0) ? Double(x) / dpi
                                   : max(0.0, (screenLogW - winLogW) / 2.0)
            let winLogY = (y != 0) ? Double(y) / dpi
                                   : max(0.0, (screenLogH - winLogH) / 2.0)
            let fullRect = Rect.fromLTWH(winLogX, winLogY, winLogW, winLogH)
            self.setState {
                shellWindowId = self.windowManager.addWindow(
                    title: title,
                    appId: appId,
                    rect: fullRect,
                    textureId: textureId,
                    onWindowClose: {
                        // ICCCM close request. The client runs its own quit
                        // path; if it ignores us, _quitApp escalates to the
                        // pid captured when the window was mapped.
                        x11.requestClose(windowId: windowId)
                    },
                    onPointerEvent: { (phase, px, py, buttons) in
                        // Scale logical to physical pixels for X11 client
                        let scale = currentShellDpi
                        x11.sendPointerEvent(
                            windowId: windowId,
                            phase: phase,
                            x: px * scale, y: py * scale,
                            buttons: buttons
                        )
                    },
                    onContentResize: { (w, h) in
                        // Scale logical pixels to physical for X11 client
                        let scale = currentShellDpi
                        x11.sendResize(
                            windowId: windowId,
                            width: Int(Double(w) * scale),
                            height: Int(Double(h) * scale)
                        )
                    },
                    onResizeComplete: { (w, h) in
                        // Force-send the final size on drag end, bypassing throttle
                        let scale = currentShellDpi
                        x11.sendResize(
                            windowId: windowId,
                            width: Int(Double(w) * scale),
                            height: Int(Double(h) * scale)
                        )
                    },
                    flipTextureY: true,  // DMA-BUF from X11/Vulkan needs Y-flip for GL
                    appBuilder: { _ in SizedBox(expand: ()) }
                )
            }
            // No forced resize: the client keeps the geometry it asked for.
            // (The old code configured every window to fullscreen for the
            // Chrome-kiosk flow; interactive resizes still flow through
            // onContentResize/onResizeComplete above.)
            return shellWindowId
        }

        x11.onWindowDestroyed = { [weak self] (windowId: String) in
            guard let self = self else { return }
            self.setState {
                self.windowManager.closeWindow(windowId)
            }
        }

        // Menus, dropdowns and tooltips from X11 clients. They reuse the popup
        // model the Wayland path already has, so the id carries an "x11popup-"
        // prefix and the renderer keys off that for input routing and Y flip.
        // X11 gives root-absolute physical coords; the renderer adds the parent
        // window's position, so store them parent-relative and logical.
        x11.onNewPopup = { [weak self] (windowId: UInt32, textureId: Int, parentWindowId: UInt32,
                                         x: Int, y: Int, width: Int, height: Int) -> String in
            guard let self = self else { return "" }
            let popupId = "x11popup-\(windowId)"
            let dpi = currentShellDpi
            // Already parent-relative (the server differenced it), so this is
            // just a device-px → logical conversion; the renderer adds the
            // parent window's position and title bar.
            self.setState {
                self.popups[popupId] = (textureId: textureId,
                                         parentSurfaceId: parentWindowId,
                                         x: Double(x) / dpi, y: Double(y) / dpi,
                                         width: Double(width) / dpi,
                                         height: Double(height) / dpi,
                                         mapped: true)
            }
            return popupId
        }

        x11.onPopupDestroyed = { [weak self] (popupId: String) in
            guard let self = self else { return }
            self.setState {
                self.popups.removeValue(forKey: popupId)
            }
        }

        x11.onPopupBufferResized = { [weak self] (popupId: String, physWidth: Int, physHeight: Int) in
            guard let self = self, var p = self.popups[popupId] else { return }
            let dpi = currentShellDpi
            let w = Double(physWidth) / dpi, h = Double(physHeight) / dpi
            if p.width == w && p.height == h { return }
            p.width = w; p.height = h
            self.setState { self.popups[popupId] = p }
        }

        x11.onWindowBufferResized = { [weak self] (windowId: String, physWidth: Int, physHeight: Int) in
            guard let self = self else { return }
            if let win = self.windowManager.windows.first(where: { $0.id == windowId }) {
                let dpi = currentShellDpi
                let logicalW = Double(physWidth) / dpi
                let logicalH = Double(physHeight) / dpi + DesktopTheme.kTitleBarHeight

                if win.resizeDragEdge != nil {
                    // Option A (xfwm4-style): during drag, suppress rect update
                    // from Chrome's buffer — rect already follows the mouse via
                    // resizeWindow(). Just schedule a frame so the texture repaints.
                    PlatformDispatcher.instance.scheduleFrame()

                    // If drag ended (targetRect set but edge cleared by drag-end),
                    // and Chrome matched, clear targetRect.
                    if let target = win.targetRect,
                       Int(logicalW) == Int(target.width),
                       Int(logicalH) == Int(target.height) {
                        win.targetRect = nil
                        win.resizeDragEdge = nil
                    }
                } else if win.targetRect != nil {
                    // Drag ended but Chrome hasn't matched final size yet.
                    // Once Chrome renders at final size, snap rect and clear.
                    let target = win.targetRect!
                    if Int(logicalW) == Int(target.width) &&
                       Int(logicalH) == Int(target.height) {
                        win.targetRect = nil
                        win.resizeDragEdge = nil
                    }
                    // Update rect to Chrome's actual rendered size
                    self.setState {
                        win.rect = Rect.fromLTWH(win.rect.left, win.rect.top, logicalW, logicalH)
                    }
                } else {
                    // Not dragging — normal buffer resize
                    if Int(win.rect.width) != Int(logicalW) || Int(win.rect.height) != Int(logicalH) {
                        self.setState {
                            win.rect = Rect.fromLTWH(win.rect.left, win.rect.top, logicalW, logicalH)
                        }
                    } else {
                        PlatformDispatcher.instance.scheduleFrame()
                    }
                }
            }
        }

        // onBufferPresented no longer needed — sync resize tracks via onWindowBufferResized

        x11.onTitleChanged = { [weak self] (windowId: String, title: String) in
            guard let self = self else { return }
            if let win = self.windowManager.windows.first(where: { $0.id == windowId }) {
                self.setState {
                    win.title = title
                }
            }
        }
        #endif
    }

    override func build(_ context: any BuildContext) -> Widget {
        // Pointer tap for the recording zoom. Translucent so it only
        // observes: it sits in the hit path of everything below and consumes
        // nothing, which is the pattern the overlay note in CLAUDE.md
        // settles on (a ColoredBox here would swallow the desktop).
        // Deliberately NOT setState — this feeds a crop, and rebuilding the
        // whole shell on every mouse move would be absurd.
        return Listener(
            onPointerDown: { [self] e in _lastPointer = e.position },
            onPointerMove: { [self] e in _lastPointer = e.position },
            onPointerHover: { [self] e in _lastPointer = e.position },
            behavior: .translucent,
            child: _buildShellRoot(context))
    }

    private func _buildShellRoot(_ context: any BuildContext) -> Widget {
        // SIMULATED multi-output (STARLING_SIM_OUTPUTS): render the whole
        // virtual desktop scaled to fit the one physical panel. REAL
        // multi-output instead gives each secondary its own Flutter view
        // (SecondaryOutputScreen) and the primary renders the normal desktop
        // below — the primary's slice of the virtual desktop is exactly its
        // own logical rect at (0,0).
        if let dl = displayLayout, dl.outputs.count > 1,
           secondaryViewOutputs.isEmpty {
            return _buildVirtualDesktopOverview(dl)
        }

        // Build window widgets sorted by z-index
        var children: [Widget] = []

        // Space-slide layers: (spaceId, dx). Steady state is one layer at
        // dx 0; during a slide the outgoing and incoming spaces render side
        // by side, offset by the eased progress. Resolved by space ID so a
        // space removed mid-slide degrades to a steady frame.
        var slideLayers: [(spaceId: Int, dx: Double)] = [(windowManager.activeSpace.id, 0)]
        if let s = _spaceSlide, let curve = _spaceSlideCurve,
           windowManager.spaces.contains(where: { $0.id == s.fromId }),
           windowManager.spaces.contains(where: { $0.id == s.toId }) {
            let p = curve.value
            slideLayers = [
                (s.fromId, -s.dir * p * screenWidth),
                (s.toId, s.dir * (1.0 - p) * screenWidth),
            ]
        }
        let isSliding = slideLayers.count > 1

        // [0] Desktop wallpaper with right-click support. During a slide
        // each space carries its own wallpaper copy as it moves (macOS).
        func makeWallpaper() -> Widget {
            let wallpaperWidget: Widget
            #if os(Linux)
            if wallpaperPreset == .still, wallpaperTextureId >= 0 {
                wallpaperWidget = TextureWidget(textureId: Int(wallpaperTextureId), filterQuality: .low)
            } else {
                wallpaperWidget = DesktopBackground(preset: wallpaperPreset)
            }
            #else
            wallpaperWidget = DesktopBackground(preset: wallpaperPreset)
            #endif
            return Listener(
                onPointerDown: { [self] event in
                    if event.buttons & kSecondaryButton != 0 {
                        setState {
                            contextMenuPosition = event.position
                            contextMenuOutputId = displayLayout?.host.id ?? 0
                            activeStatusBarPopup = nil
                        }
                    }
                },
                onPointerHover: { _ in
                    // Catch-all: any hover that reaches the wallpaper (i.e.
                    // wasn't claimed by a window edge, title bar, dock, etc.)
                    // resets the cursor back to the default arrow.
                    DesktopCursor.setShape(.default)
                },
                behavior: .opaque,
                child: wallpaperWidget
            )
        }
        if isSliding {
            for layer in slideLayers {
                children.append(Positioned(
                    left: layer.dx, top: 0,
                    width: screenWidth, height: screenHeight,
                    child: makeWallpaper()))
            }
        } else {
            children.append(makeWallpaper())
        }

        // [0.5] Workspace mode — rendered per slide layer,
        // like the wallpaper, so entering/leaving slides it with the space.
        // Ordinary spaces contribute nothing; the ValueKey keeps the fleet's
        // element (and its terminal focus state) alive across slide/steady
        // transitions.
        // The per-layer isWorkspace guard scopes this: with per-output
        // spaces, a workspace active on another monitor never appears in the
        // HOST's slide layers, so no output-ownership check is needed.
        let hostOutput = displayLayout?.host
        if !(_missionControlOpen && mcIsOnHost) {
            for layer in slideLayers {
                guard let space = windowManager.spaces.first(where: { $0.id == layer.spaceId }),
                      space.isWorkspace else { continue }
                children.append(Positioned(
                    key: ValueKey("workspace-space"),
                    left: layer.dx, top: 0,
                    width: screenWidth, height: screenHeight,
                    child: _buildWorkspaceSpace(output: hostOutput
                        ?? missionControlOutput)))
            }
        }

        // BISECT: temporarily removed search pill + date label
        // to test whether they trigger the Chrome DMA-BUF crash.

        // The top bar, if the active style has one — it always renders above
        // windows so the clock stays visible, and fullscreen windows lay out
        // below it. nil in a style whose chrome is all on the bottom edge.
        let topBarWidget: Widget? = chrome.topBar()

        // Whether the topmost visible window is fullscreen — gates the
        // macOS-style auto-hide of the desktop status bar.
        let topmostWindow = windowManager.visibleWindows.last
        let isFullscreenMode = topmostWindow?.isFullscreen ?? false
        if !isFullscreenMode && (_topBarRevealed || _dockRevealed) {
            // No fullscreen window any more — reset reveal state.
            _topBarRevealed = false
            _dockRevealed = false
        }

        // [1..N] Visible windows — both spaces' windows during a slide,
        // each offset by its layer's dx. None while Mission Control is up:
        // every window renders exactly once, inside the exposé.
        //
        // Steady state draws `visibleWindows` — the per-output union — so a
        // straddler owned by the other monitor renders its host-side portion
        // whatever space the host is in (windows entirely elsewhere clip
        // away; that was already true when spaces were global). During a
        // slide, each layer carries only windows the HOST answers for
        // (hostSlideWindows), and the other outputs' visible windows ride a
        // static dx=0 layer — the neighbor's straddler must not animate
        // with a space switch that isn't its monitor's.
        let slideSpaceIds = Set(slideLayers.map { $0.spaceId })
        let layerWindows: [(win: WindowInfo, layerDx: Double)] = (_missionControlOpen && mcIsOnHost)
            ? []
            : !isSliding
                ? windowManager.visibleWindows.map { ($0, 0.0) }
                : slideLayers.flatMap { layer in
                    windowManager.hostSlideWindows(inSpaceId: layer.spaceId).map { ($0, layer.dx) }
                } + windowManager.visibleWindows
                    .filter { !slideSpaceIds.contains($0.spaceId) }
                    .map { ($0, 0.0) }
        var liveWindowIds = Set<String>()
        for (win, layerDx) in layerWindows {
            let winId = win.id
            liveWindowIds.insert(winId)
            let isFocused = win.id == windowManager.focusedWindowId
            // Only the topmost fullscreen window gets the reveal flag — other
            // windows underneath are not affected.
            let windowTopBarRevealed = win.isFullscreen && win.id == topmostWindow?.id
                ? _topBarRevealed : false

            // Reuse cached widget when only position changed (drag).
            // updateChild's identity check (===) skips the entire subtree rebuild.
            let window: DesktopWindow
            if let cached = _windowChildCache[winId],
               cached.isFocused == isFocused,
               cached.width == win.rect.width,
               cached.height == win.rect.height,
               cached.isFullscreen == win.isFullscreen,
               cached.isTopBarRevealed == windowTopBarRevealed {
                window = cached.widget
            } else {
                window = DesktopWindow(
                    windowInfo: win,
                    isFocused: isFocused,
                    isTopBarRevealed: windowTopBarRevealed,
                    onBringToFront: { [self] in
                        setState {
                            windowManager.bringToFront(winId)
                        }
                    },
                    onMove: { [self] (delta: Offset) in
                        // Tiled windows are glued to their tiles.
                        if windowManager.tilingEnabled { return }
                        setState {
                            windowManager.moveWindowByDelta(winId, delta: delta)
                        }
                        _checkEdgeCarry(winId)
                    },
                    onResize: { [self] (edge: ResizeEdge, delta: Offset) in
                        if windowManager.tilingEnabled { return }
                        setState {
                            windowManager.resizeWindow(winId, edge: edge, delta: delta)
                        }
                    },
                    onMinimize: { [self] in requestWindowMinimize(winId) },
                    onMaximize: { [self] in requestWindowMaximize(winId) },
                    onClose: { [self] in requestWindowClose(winId) },
                    onTitleBarDoubleTap: { [self] in
                        requestWindowTitleBarDoubleTap(winId)
                    }
                )
                _windowChildCache[winId] = (window, isFocused, win.rect.width, win.rect.height, win.isFullscreen, windowTopBarRevealed)
            }

            // Open zoom plays only when the window is genuinely appearing
            // (new window, restore from minimize) — NOT when it merely
            // mounts because a space switch brought its desktop on screen.
            let animateOpen = win.pendingOpenAnimation
            win.pendingOpenAnimation = false
            // An edge-drag-carried window ignores the slide offset: it
            // stays pinned under the cursor while the desktop slides.
            let windowDx = win.id == _spaceSlide?.carried ? 0 : layerDx
            children.append(
                Positioned(
                    key: ValueKey(winId),
                    left: win.rect.left + windowDx,
                    top: win.rect.top,
                    width: win.rect.width,
                    height: win.rect.height,
                    // Zoom out of the dock icon on first appearance (and on
                    // restore from minimize — both mount a fresh element);
                    // shrink-out on close, with teardown deferred to the
                    // animation's end.
                    child: WindowLifecycleAnimation(
                        closing: _closingWindows.contains(winId),
                        minimizing: _minimizingWindows.contains(winId),
                        animateOpen: animateOpen,
                        onClosed: { [self] in _finalizeWindowClose(winId) },
                        onMinimized: { [self] in _finalizeWindowMinimize(winId) },
                        zoomFrom: _dockIconCenter(appId: win.appId, title: win.title).map {
                            Offset($0.dx - (win.rect.left + win.rect.width / 2),
                                   $0.dy - (win.rect.top + win.rect.height / 2))
                        },
                        child: window
                    )
                )
            )
        }

        // Evict closed windows from cache
        _windowChildCache = _windowChildCache.filter { liveWindowIds.contains($0.key) }

        // [N+1..] Popups (rendered on top of windows, no decorations)
        // Sort by nesting depth so children render on top of parents.
        #if os(Linux)
        let sortedPopups = (_missionControlOpen && mcIsOnHost) ? [] : popups.sorted { a, b in
            // Count nesting depth by walking parent chain
            func depth(_ p: (key: String, value: (textureId: Int, parentSurfaceId: UInt32, x: Double, y: Double, width: Double, height: Double, mapped: Bool))) -> Int {
                var d = 0
                var sid = p.value.parentSurfaceId
                while let parent = popups["popup-\(sid)"] ?? popups["x11popup-\(sid)"] {
                    d += 1
                    sid = parent.parentSurfaceId
                }
                return d
            }
            return depth(a) < depth(b)
        }
        for (popupId, popup) in sortedPopups {
            if !popup.mapped { continue }
            // Walk the parent chain to compute absolute popup position.
            // For nested popups (submenu of a menu), accumulate positions up to the toplevel.
            // Also track the immediate parent popup's absolute position for flip.
            var absX = popup.x
            var absY = popup.y
            var parentSurfaceId = popup.parentSurfaceId
            var immediateParentAbsX = 0.0
            var immediateParentWidth = 0.0
            var isFirstParent = true
            var popupSpaceId: Int? = nil
            while true {
                // Check if parent is another popup (a submenu's menu)
                if let parentPopup = popups["popup-\(parentSurfaceId)"]
                                  ?? popups["x11popup-\(parentSurfaceId)"] {
                    if isFirstParent {
                        // Compute the immediate parent's absolute position (recursively)
                        // by noting we'll add its x to absX next.
                        immediateParentWidth = parentPopup.width
                        isFirstParent = false
                    }
                    absX += parentPopup.x
                    absY += parentPopup.y
                    parentSurfaceId = parentPopup.parentSurfaceId
                    continue
                }
                // Parent is a toplevel window — add window position. The id is a
                // Wayland surface id or, for an X11 menu, an X11 window id.
                var parentWinIdOpt: String? = waylandIntegration?.windowId(forSurfaceId: parentSurfaceId)
                if parentWinIdOpt == nil {
                    parentWinIdOpt = x11Integration?.shellWindowId(forX11Window: parentSurfaceId)
                }
                if let parentWinId = parentWinIdOpt,
                   let parentWin = windowManager.windows.first(where: { $0.id == parentWinId }) {
                    absX += parentWin.rect.left
                    absY += parentWin.rect.top + DesktopTheme.kTitleBarHeight
                    popupSpaceId = parentWin.spaceId
                    if isFirstParent {
                        // Direct child of toplevel — no flip needed for x
                        immediateParentAbsX = parentWin.rect.left
                        immediateParentWidth = parentWin.rect.width
                    }
                }
                break
            }

            // Popups live on their toplevel's space: a menu opened on space 1
            // must not float over space 2 after a switch.
            if let sid = popupSpaceId, sid != windowManager.activeSpace.id { continue }

            // Compute immediate parent popup's absolute x for flip.
            if !isFirstParent {
                immediateParentAbsX = absX - popup.x
            }

            // Constraint adjustment: keep popups within screen bounds.
            if absX + popup.width > screenWidth {
                if !isFirstParent {
                    // Nested popup (submenu): flip to left side of parent popup.
                    absX = immediateParentAbsX - popup.width
                } else {
                    // Direct child of toplevel: slide left to fit.
                    absX = screenWidth - popup.width
                }
            }
            if absX < 0 { absX = 0 }
            if absY + popup.height > screenHeight {
                absY = screenHeight - popup.height
            }
            if absY < 0 { absY = 0 }

            let isX11Popup = popupId.hasPrefix("x11popup-")
            let texture: Widget = TextureWidget(textureId: popup.textureId, filterQuality: .none)
            // Both need the flip: Wayland surfaces arrive bottom-up, and an X11
            // menu is a DMA-BUF from Vulkan/GL exactly like its toplevels, which
            // pass flipTextureY: true. A solid-colour test popup looks identical
            // either way — only real content (mirrored menu labels) shows it.
            let flipped: Widget = Transform(
                transform: Matrix4.diagonal3Values(1.0, -1.0, 1.0),
                alignment: Alignment.center,
                child: texture
            )

            // Wrap in Listener to forward pointer events to popup surface.
            let popupChild: Widget
            if isX11Popup,
               let x11 = x11Integration,
               let x11WinId = UInt32(popupId.dropFirst("x11popup-".count)) {
                // Menus are only useful if you can click them. Same physical-px
                // conversion the X11 toplevel path does.
                let toPhys = currentShellDpi
                popupChild = Listener(
                    onPointerDown: { event in
                        x11.sendPointerEvent(windowId: x11WinId, phase: 2,
                                             x: event.localPosition.dx * toPhys,
                                             y: event.localPosition.dy * toPhys,
                                             buttons: Int64(event.buttons))
                    },
                    onPointerMove: { event in
                        x11.sendPointerEvent(windowId: x11WinId, phase: 3,
                                             x: event.localPosition.dx * toPhys,
                                             y: event.localPosition.dy * toPhys,
                                             buttons: Int64(event.buttons))
                    },
                    onPointerUp: { event in
                        x11.sendPointerEvent(windowId: x11WinId, phase: 1,
                                             x: event.localPosition.dx * toPhys,
                                             y: event.localPosition.dy * toPhys,
                                             buttons: 0)
                    },
                    onPointerHover: { event in
                        x11.sendPointerEvent(windowId: x11WinId, phase: 6,
                                             x: event.localPosition.dx * toPhys,
                                             y: event.localPosition.dy * toPhys,
                                             buttons: 0)
                    },
                    child: flipped
                )
            } else if let wl = waylandIntegration,
               let surfaceId = wl.surfaceId(forWindowId: popupId) {
                popupChild = Listener(
                    onPointerDown: { event in
                        wl.sendPointerEvent(
                            surfaceId: surfaceId,
                            phase: 2,
                            x: event.localPosition.dx,
                            y: event.localPosition.dy,
                            buttons: Int64(event.buttons)
                        )
                    },
                    onPointerMove: { event in
                        wl.sendPointerEvent(
                            surfaceId: surfaceId,
                            phase: 3,
                            x: event.localPosition.dx,
                            y: event.localPosition.dy,
                            buttons: Int64(event.buttons)
                        )
                    },
                    onPointerUp: { event in
                        wl.sendPointerEvent(
                            surfaceId: surfaceId,
                            phase: 1,
                            x: event.localPosition.dx,
                            y: event.localPosition.dy,
                            buttons: 0
                        )
                    },
                    onPointerHover: { event in
                        wl.sendPointerEvent(
                            surfaceId: surfaceId,
                            phase: 6,
                            x: event.localPosition.dx,
                            y: event.localPosition.dy,
                            buttons: 0
                        )
                    },
                    onPointerSignal: { event in
                        if let scroll = event as? PointerScrollEvent {
                            wl.sendScrollEvent(
                                surfaceId: surfaceId,
                                x: scroll.localPosition.dx,
                                y: scroll.localPosition.dy,
                                scrollDeltaX: scroll.scrollDelta.dx,
                                scrollDeltaY: scroll.scrollDelta.dy
                            )
                        }
                    },
                    behavior: .opaque,
                    child: flipped
                )
            } else {
                popupChild = flipped
            }

            children.append(
                Positioned(
                    key: ValueKey(popupId),
                    left: absX,
                    top: absY,
                    width: popup.width,
                    height: popup.height,
                    child: popupChild
                )
            )
        }
        #endif

        // Status bar renders ON TOP of windows. In fullscreen, the reserved
        // top strip is filled with solid black (matching the status-bar
        // background, hiding the wallpaper underneath) and the status-bar
        // items only appear while revealed. In non-fullscreen, the status
        // bar is transparent over the wallpaper as usual.
        if _missionControlOpen && mcIsOnHost {
            // Mission Control replaces the desktop layers: no status bar
            // (the spaces strip sits in that zone); the dock stays, above.
            // Only when it was invoked on THIS monitor — a secondary draws
            // its own copy and the host keeps its desktop.
            children.append(
                Positioned(fill: (), child: _buildMissionControl(context))
            )
        } else if isFullscreenMode {
            if DesktopTheme.kStatusBarHeight > 0 {
                children.append(
                    Positioned(
                        left: 0, top: 0, right: 0,
                        height: DesktopTheme.kStatusBarHeight,
                        child: ColoredBox(
                            color: Color(0xFF000000),
                            child: SizedBox(expand: ())
                        )
                    )
                )
            }
            if _topBarRevealed, let bar = topBarWidget {
                children.append(bar)
            }
        } else if let bar = topBarWidget {
            children.append(bar)
        }
        // The dock launches desktop apps — meaningless in a workspace, where
        // every window belongs to an agent. Hide it there, cross-fading with
        // the space slide (the model flips at slide start, so the fade tracks
        // the incoming space's progress rather than snapping).
        let agentTarget = windowManager.activeSpace.isSpecial
        var dockOpacity = agentTarget ? 0.0 : 1.0
        if let s = _spaceSlide, let curve = _spaceSlideCurve,
           let from = windowManager.spaces.first(where: { $0.id == s.fromId }),
           from.isSpecial != agentTarget {
            // Leaving a workspace fades the dock in; entering fades it out.
            dockOpacity = agentTarget ? 1.0 - curve.value : curve.value
        }
        // Fullscreen hides the dock like it hides the status bar — it only
        // draws while the cursor holds it revealed (the bottom sensor).
        if isFullscreenMode && !_dockRevealed {
            dockOpacity = 0
        }
        // Only when this tree owns the bar. The user can make another monitor
        // primary, and then it is drawn by that output's
        // SecondaryOutputScreen instead — there is one bottom bar, and it is
        // on the primary display.
        if dockIsOnHost,
           let bar = chrome.bottomBar(forOutput: dockOutput, opacity: dockOpacity) {
            children.append(bar)
            // Whatever the bar hangs above itself — Windows' live window
            // previews. Its own layer, because it is far taller than the bar
            // and the bar's box is what Mission Control measures against.
            if dockOpacity > 0.99, let over = chrome.hoverOverlay() {
                children.append(over)
            }
        }

        // Edge cursor sensors for macOS-style auto-hide. While in fullscreen
        // mode, three translucent Listeners sit on top of everything:
        //   - Top region: hovering inside reveals the bars.
        //   - Middle region: hovering inside hides both bars and dock.
        //   - Bottom region: hovering inside reveals the dock.
        // Using `.translucent` lets the events also reach the window content
        // below so the focused Wayland/X11 client still gets hover events.
        if isFullscreenMode && !(_missionControlOpen && mcIsOnHost) {
            // Collapsed: a 4-px sliver at the very top. Expanded: covers the
            // status bar + the title-bar overlay so the user can hover into
            // the title bar (and its traffic-light buttons) without the
            // cursor "exiting" the sensor zone.
            let revealZoneH = _topBarRevealed
                ? DesktopTheme.kStatusBarHeight + DesktopTheme.kTitleBarHeight
                : 4.0
            // Same shape at the bottom: a sliver to catch the approach, the
            // dock's whole band while revealed so hovering (and magnifying)
            // the dock doesn't count as leaving it.
            let dockZoneH = _dockRevealed
                ? DesktopTheme.kDockBottomMargin + DesktopTheme.kDockContainerHeight
                : 4.0
            children.append(
                Positioned(
                    left: 0, top: 0, right: 0,
                    height: revealZoneH,
                    child: Listener(
                        onPointerHover: { [self] _ in
                            if !_topBarRevealed {
                                setState { _topBarRevealed = true }
                            }
                        },
                        behavior: .translucent,
                        child: SizedBox(expand: ())
                    )
                )
            )
            children.append(
                Positioned(
                    left: 0, top: revealZoneH, right: 0, bottom: dockZoneH,
                    child: Listener(
                        onPointerHover: { [self] _ in
                            if _topBarRevealed || _dockRevealed {
                                setState {
                                    _topBarRevealed = false
                                    _dockRevealed = false
                                }
                            }
                        },
                        behavior: .translucent,
                        child: SizedBox(expand: ())
                    )
                )
            )
            children.append(
                Positioned(
                    left: 0, right: 0, bottom: 0,
                    height: dockZoneH,
                    child: Listener(
                        onPointerHover: { [self] _ in
                            if !_dockRevealed {
                                setState { _dockRevealed = true }
                            }
                        },
                        behavior: .translucent,
                        child: SizedBox(expand: ())
                    )
                )
            )
        }

        // Context menu (shown at right-click position) — only when it was
        // opened on THIS output; a secondary draws its own copy.
        if contextMenuPosition != nil,
           contextMenuOutputId == (displayLayout?.host.id ?? 0) {
            _appendDismissBarrier(&children) { [self] in
                self.contextMenuPosition = nil
            }
            children.append(chrome.desktopMenu())
        }

        // Dock icon context menu (right-click on a dock icon), anchored
        // above the icon's slot, macOS style. It goes wherever the dock is —
        // on the host only while the host is the primary display.
        if dockIsOnHost, _dockMenuAppId != nil {
            _appendDismissBarrier(&children) { [self] in
                self._dockMenuAppId = nil
            }
            if let menu = chrome.appIconMenu(forOutput: dockOutput) {
                children.append(menu)
            }
        }

        // IME panel: preedit + candidates while composing (shell-drawn).
        // Anchored just below the focused child's reported caret when
        // available (macOS style); falls back to floating above the dock.
        if _imeEnabled && (!_imePreedit.isEmpty || !_imeCandidates.isEmpty) {
            var anchored = false
            // Wayland clients: anchor at the reported text-input cursor rect.
            if let ti = _imeWaylandTI, ti.enabled,
               let focusedId = windowManager.focusedWindowId,
               focusedId == ti.windowId,
               let win = windowManager.windows.first(where: { $0.id == focusedId }) {
                let cx = win.rect.left + ti.rect.left
                let cy = win.rect.top + DesktopTheme.kTitleBarHeight
                    + ti.rect.top + ti.rect.height + 6
                if cy < screenHeight - 200 {
                    children.append(Positioned(
                        left: max(8, min(cx, screenWidth - 360)),
                        top: cy,
                        child: _buildImePanel()
                    ))
                    anchored = true
                }
            }
            if !anchored,
               let caret = _imeCaret, caret.visible,
               let focusedId = windowManager.focusedWindowId,
               let win = windowManager.windows.first(where: { $0.id == focusedId }),
               let texId = processTextureIds[win.appId],
               texId == caret.textureId {
                let cx = win.rect.left + caret.rect.left
                let cy = win.rect.top + DesktopTheme.kTitleBarHeight
                    + caret.rect.top + caret.rect.height + 6
                if cy < screenHeight - 200 {
                    children.append(Positioned(
                        left: max(8, min(cx, screenWidth - 360)),
                        top: cy,
                        child: _buildImePanel()
                    ))
                    anchored = true
                }
            }
            if !anchored {
                children.append(Positioned(
                    left: 0, right: 0,
                    bottom: DesktopTheme.kDockBottomMargin
                        + DesktopTheme.kDockContainerHeight + 12,
                    child: Center(child: _buildImePanel())
                ))
            }
        }

        // The panel behind a tapped status item. Where it hangs is the style's
        // business — under the menu bar, or up from the taskbar.
        if let popup = activeStatusBarPopup {
            _appendDismissBarrier(&children) { [self] in
                self.activeStatusBarPopup = nil
            }
            children.append(chrome.statusFlyout(popup))
        }

        // The app launcher, opened from the bottom bar. Above windows and the
        // bar itself; tap an app to launch it, tap empty space to dismiss.
        if _launcherOpen && _launcherOutputId == (hostOutput?.id ?? 0) {
            children.append(chrome.launcher())
        }

        // Floating dock icon follows cursor during drag
        if _dockDragActive, let dragIdx = _dockDragIndex, dragIdx < dockAppOrder.count {
            let dragAppId = dockAppOrder[dragIdx]
            let floatingIcon = _buildDockIconContent(
                appId: dragAppId, iconType: _iconType(for: dragAppId))
            let iconSize = DesktopTheme.kDockIconSize
            children.append(
                Positioned(
                    left: _dockDragCurrentX - iconSize / 2,
                    top: _dockDragCurrentY - iconSize / 2,
                    width: iconSize,
                    height: iconSize,
                    child: IgnorePointer(
                        child: floatingIcon
                    )
                )
            )
        }

        // While a space slide runs, an opaque full-screen barrier swallows
        // all pointer input (macOS: the desktop is inert during the switch);
        // it lifts automatically when the slide completes.
        if isSliding {
            children.append(
                Positioned(
                    fill: (),
                    child: Listener(
                        behavior: .opaque,
                        child: ColoredBox(
                            color: Color(0x00000000),
                            child: SizedBox(expand: ())
                        )
                    )
                )
            )
        }

        // Screensaver: dim + breathing blur + liquid warp over the LIVE
        // desktop (no capture step), thin clock on top. Any pointer input
        // wakes it via the overlay's opaque Listener; keys are swallowed by
        // the matching branch in routeKey. Above everything interactive —
        // only the frame-tick pixel and the non-claiming hover listener sit
        // higher, and both are invisible.
        if _screensaverActive {
            let t = _screensaverFadeCurve?.value ?? 1.0
            let now = Date()
            children.append(
                Positioned(
                    fill: (),
                    child: ScreenSaverOverlay(
                        filter: _screensaverFilter(fadeT: t),
                        fadeT: t,
                        timeText: Self._ssTimeFmt.string(from: now),
                        ampmText: Self._ssAmpmFmt.string(from: now),
                        dateText: Self._ssDateFmt.string(from: now),
                        aerialTextureId: _aerialTextureId >= 0 ? _aerialTextureId : nil,
                        aerialT: _aerialFadeT,
                        onWakeInput: { [weak self] in self?._screensaverInputWake() },
                        onPointerActivity: { [weak self] pos in
                            self?._screensaverPointerActivity(pos)
                        }
                    )
                )
            )
        }

        // Frame-tick pixel: 1px in the bottom-left corner whose (invisible)
        // alpha alternates with _frameTick, guaranteeing real damage — and
        // therefore a present — whenever the tooling requests a frame.
        children.append(
            Positioned(
                left: 0, top: screenHeight - 1, width: 1, height: 1,
                child: IgnorePointer(
                    child: ColoredBox(
                        color: Color(_frameTick % 2 == 0 ? 0x01000000 : 0x02000000),
                        child: SizedBox(expand: ())
                    )
                )
            )
        )

        // Topmost translucent hover listener: drives dock magnification from
        // the global pointer position with a purely geometric test, so it
        // keeps working (and relaxing) no matter what is under the cursor.
        // The child must be a bare SizedBox: it sizes the listener without
        // claiming hits (a ColoredBox — even fully transparent — hit-tests
        // opaque and would swallow every click for the widgets below).
        children.append(
            Positioned(
                fill: (),
                child: Listener(
                    // Pressed-pointer tracking for edge-drag carry: this
                    // listener is in every pointer's hit path, so it keeps
                    // seeing move events while a window drag is in flight.
                    // No setState — the position feeds the dwell check only.
                    // This listener is also the shell's idle-detection tap:
                    // it is in every pointer's hit path, including events on
                    // their way to a Wayland or X11 client, because client
                    // windows are textures inside this same tree.
                    onPointerDown: { [self] _ in _noteUserActivity() },
                    onPointerMove: { [self] event in
                        _dragPointerPos = event.position
                        _noteUserActivity()
                    },
                    onPointerUp: { [self] _ in
                        _cancelEdgeCarry()
                        _noteUserActivity()
                    },
                    onPointerHover: { [self] event in
                        chrome.notePointerHover(
                            x: event.position.dx, y: event.position.dy,
                            outputId: displayLayout?.host.id ?? 0)
                        _noteUserActivity()
                    },
                    onPointerSignal: { [self] _ in _noteUserActivity() },
                    behavior: .translucent,
                    child: SizedBox(expand: ())
                )
            )
        )

        // Keyed by style and theme: switching either one remounts the whole
        // shell tree. In-place recolor proved unreliable (title bars rebuilt
        // with the new theme but their stale layers kept compositing — a
        // framework layer-retention quirk); a remount repaints everything
        // from scratch and both switches are rare, deliberate actions. A
        // style switch needs it doubly: surfaces do not merely recolour, they
        // move or stop existing. Window
        // open-zooms stay silent (pendingOpenAnimation already consumed).
        // Which monitor the pointer is on, for whatever needs to open "here"
        // — today that is the workspace toggle. An ancestor Listener sees
        // events that hit anything inside it and consumes nothing, so this is
        // observation only; `.translucent` keeps it out of the way of the
        // wallpaper's own right-click handling.
        return Listener(
            onPointerDown: { [self] _ in notePointerOutput(displayLayout?.host.id ?? 0) },
            onPointerHover: { [self] _ in notePointerOutput(displayLayout?.host.id ?? 0) },
            behavior: .translucent,
            child: Stack(
                key: ValueKey("shell-\(shellStyle.id)-\(shellTheme.name)"),
                fit: .expand,
                children: children
            )
        )
    }

    // MARK: - Multi-output virtual desktop (scale-to-fit dev harness)

    /// Renders the whole virtual desktop — every output with its own wallpaper
    /// and menu bar, all windows in virtual coordinates, and the dock on the
    /// primary — scaled to fit the single physical panel (FittedBox .contain).
    /// This is the hardware-free harness for multi-monitor layout work; a
    /// production build spins one Flutter view per real output instead.
    private func _buildVirtualDesktopOverview(_ dl: DisplayLayout) -> Widget {
        let vb = dl.virtualBounds
        let ox = vb.left, oy = vb.top

        var layers: [Widget] = []

        // Wallpaper per output.
        for o in dl.outputs {
            layers.append(Positioned(
                left: o.logicalLeft - ox, top: o.logicalTop - oy,
                width: o.logicalWidth, height: o.logicalHeight,
                child: _overviewWallpaper()))
        }

        // Windows, positioned in virtual coordinates. A window straddling a
        // seam therefore renders across both outputs. Dragging works: the
        // FittedBox transform maps pointer motion back into virtual space.
        for win in windowManager.visibleWindows {
            let winId = win.id
            let isFocused = winId == windowManager.focusedWindowId
            layers.append(Positioned(
                key: ValueKey("ov-\(winId)"),
                left: win.rect.left - ox, top: win.rect.top - oy,
                width: win.rect.width, height: win.rect.height,
                child: _makeOverviewWindow(win, isFocused: isFocused)))
        }

        // Menu bar per output (macOS: one per display).
        for o in dl.outputs {
            layers.append(Positioned(
                left: o.logicalLeft - ox, top: o.logicalTop - oy,
                width: o.logicalWidth, height: DesktopTheme.kStatusBarHeight,
                child: _overviewStatusBar()))
        }

        // Dock on the primary output (macOS: single dock, homes on primary).
        let p = dl.primary
        let dockMetrics = _dockMetrics(outputWidth: p.logicalWidth)
        layers.append(Positioned(
            left: (p.logicalLeft - ox) + dockMetrics.left,
            top: (p.logicalBottom - oy) - DesktopTheme.kDockBottomMargin - DesktopTheme.kDockContainerHeight,
            width: dockMetrics.width, height: DesktopTheme.kDockContainerHeight,
            child: _buildDock(
                appIds: _dockDisplayApps, metrics: dockMetrics,
                dockTop: p.logicalHeight - DesktopTheme.kDockBottomMargin - DesktopTheme.kDockHeight)))

        // Bezel + label per output (non-interactive overlay on top).
        for o in dl.outputs {
            layers.append(Positioned(
                left: o.logicalLeft - ox, top: o.logicalTop - oy,
                width: o.logicalWidth, height: o.logicalHeight,
                child: IgnorePointer(child: _overviewBezel(o))))
        }

        let virtualStack = SizedBox(
            width: vb.width, height: vb.height,
            child: Stack(fit: .expand, children: layers))

        return Stack(
            fit: .expand,
            children: [
                Positioned(fill: (), child: ColoredBox(color: Color(0xFF0B0E13))),
                Positioned(fill: (), child: FittedBox(
                    fit: .contain, alignment: Alignment.center, child: virtualStack)),
            ])
    }

    private func _overviewWallpaper() -> Widget {
        #if os(Linux)
        if wallpaperPreset == .still, wallpaperTextureId >= 0 {
            return TextureWidget(textureId: Int(wallpaperTextureId), filterQuality: .low)
        }
        #endif
        return DesktopBackground(preset: wallpaperPreset)
    }

    private func _overviewStatusBar() -> Widget {
        ClipRect(
            child: BackdropFilter(
                filter: ImageFilterFactory.compose(
                    outer: ColorFilter(matrix: _saturationMatrix(1.15)),
                    inner: ImageFilterFactory.blur(sigmaX: 18, sigmaY: 18)),
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: Color(0x2E101014),
                        border: Border(bottom: BorderSide(color: Color(0x14FFFFFF), width: 1))),
                    child: _buildStatusBar())))
    }

    private func _overviewBezel(_ o: DisplayOutput) -> Widget {
        let borderColor = o.isPrimary ? Color(0xFFE6AB50) : Color(0x55FFFFFF)
        let scaleStr = String(format: "%.1f", o.scale)
        let label = "\(o.name)   \(o.physicalWidth)×\(o.physicalHeight) @\(scaleStr)×" +
            (o.isPrimary ? "   • primary" : "")
        return Stack(children: [
            Positioned(fill: (), child: DecoratedBox(
                decoration: BoxDecoration(border: Border.all(color: borderColor, width: 2)))),
            Positioned(
                left: 10, top: DesktopTheme.kStatusBarHeight + 8,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: Color(0x99000000),
                        borderRadius: BorderRadius.circular(5)),
                    child: Padding(
                        padding: EdgeInsets(left: 8, top: 4, right: 8, bottom: 4),
                        child: Text(label, style: TextStyle(
                            color: Color(0xFFFFFFFF), fontSize: 12, fontWeight: .w500, fontFamily: shellTheme.fontFamily))))),
        ])
    }

    /// A movable/resizable/closable window for the overview harness (skips the
    /// minimize/maximize/lifecycle-animation machinery of the single-screen path).
    private func _makeOverviewWindow(_ win: WindowInfo, isFocused: Bool) -> Widget {
        let winId = win.id
        return DesktopWindow(
            windowInfo: win,
            isFocused: isFocused,
            onBringToFront: { [self] in setState { windowManager.bringToFront(winId) } },
            onMove: { [self] (delta: Offset) in
                if windowManager.tilingEnabled { return }
                setState { windowManager.moveWindowByDelta(winId, delta: delta) }
            },
            onResize: { [self] (edge: ResizeEdge, delta: Offset) in
                if windowManager.tilingEnabled { return }
                setState { windowManager.resizeWindow(winId, edge: edge, delta: delta) }
            },
            onMaximize: { [self] in
                setState {
                    windowManager.fullscreenWindow(winId, screenWidth: screenWidth, screenHeight: screenHeight)
                }
            },
            onClose: { [self] in setState { _closingWindows.insert(winId) } },
            onTitleBarDoubleTap: { [self] in
                // Maximize to the window's OWNING output (derived from its rect).
                setState {
                    windowManager.maximizeWindow(winId, screenWidth: screenWidth, screenHeight: screenHeight)
                }
            })
    }

    // MARK: - Status Bar (macOS menu bar style, top)

    private func _statusBarItem(icon: IconData, popup: StatusBarPopup,
                                color: Color? = nil) -> Widget {
        let isActive = activeStatusBarPopup == popup
        let iconColor = color ?? shellTheme.fgPrimary
        let bg: Widget = isActive
            ? DecoratedBox(
                decoration: BoxDecoration(
                    color: shellTheme.hoverFill,
                    borderRadius: BorderRadius.circular(4)
                ),
                child: Padding(
                    padding: EdgeInsets(left: 6, top: 2, right: 6, bottom: 2),
                    child: MacosIcon(icon: icon, color: iconColor, size: 15)
                )
              )
            : Padding(
                padding: EdgeInsets(left: 6, top: 2, right: 6, bottom: 2),
                child: MacosIcon(icon: icon, color: iconColor, size: 15)
              )
        return GestureDetector(
            onTap: { [self] in
                setState {
                    activeStatusBarPopup = isActive ? nil : popup
                    // Opening the bell is "looking": the tint clears, the
                    // list stays.
                    if activeStatusBarPopup == .notifications {
                        _notificationsUnseen = false
                    }
                    // The control center reads live levels on open, then
                    // ticks while it stays up (see _refreshControlCenter).
                    if activeStatusBarPopup == .controlCenter {
                        _refreshControlCenter()
                    }
                    contextMenuPosition = nil
                    // Every open starts on the list. Reset here rather than at
                    // each of the eight places that close a popup — one of
                    // those would eventually be missed, and the failure mode is
                    // a menu that opens straight onto "Shut down the computer?".
                    _powerConfirm = nil
                    // Same reasoning for the WiFi panel: never open onto a
                    // stale password prompt or last week's join error.
                    _wifiPasswordSSID = nil
                    _wifiPassword = ""
                    _wifiError = nil
                }
                if activeStatusBarPopup == .wifi {
                    // Fresh scan on open; cached results render immediately.
                    networkService.refreshWithScan()
                }
            },
            behavior: .opaque,
            child: bg
        )
    }

    /// "● 0:42" while a recording runs — red, one tap to stop. A direct
    /// action rather than a popup: by the time someone wants the recording
    /// to end, a menu between them and "stop" is only footage of a menu.
    private func _recordingIndicator() -> Widget {
        let secs = recordingService?.elapsedSeconds ?? 0
        var label = String(format: "%d:%02d", secs / 60, secs % 60)
        // The zoom is invisible on screen by design — the desktop does not
        // move, only the crop does — so the indicator is the only way to
        // know the take is zoomed. Without it you narrate blind.
        if let rec = recordingService, rec.isZoomed {
            label += "  \(rec.zoomLabel)×"
        }
        return GestureDetector(
            onTap: { recordingService?.stop() },
            behavior: .opaque,
            child: Padding(
                padding: EdgeInsets(left: 6, top: 2, right: 6, bottom: 2),
                child: Row(mainAxisSize: .min, crossAxisAlignment: .center) {
                    MacosIcon(icon: CupertinoIcons.circle_fill,
                              color: Color(0xFFFF453A), size: 11)
                    SizedBox(width: 5)
                    Text(label, style: TextStyle(
                        color: Color(0xFFFF453A), fontSize: 12,
                        fontWeight: .w600, fontFamily: shellTheme.fontFamilyStrong))
                }
            )
        )
    }

    /// Approximate screen center of the recording indicator, for the broker.
    /// The glyph-width term is an estimate, but the whole item is one tap
    /// target ~60px wide, so the center misses by a few px at worst; tests
    /// that need exactness stop via the control-center tile instead.
    /// Only meaningful while the indicator exists (isRecording).
    func recordingIndicatorCenter() -> (x: Double, y: Double) {
        // The indicator sits immediately left of the wifi item (2px gap).
        let wifiGeo = _statusPopupGeometry(.wifi)
        let wifiLeft = wifiGeo.left + wifiGeo.width - 27
        let secs = recordingService?.elapsedSeconds ?? 0
        let label = String(format: "%d:%02d", secs / 60, secs % 60)
        // 6 pad + 11 icon + 5 gap + text + 6 pad, matching the Row above.
        let width = 6.0 + 11 + 5 + Double(label.count) * 7 + 6
        return (wifiLeft - 2 - width / 2, DesktopTheme.kStatusBarHeight / 2)
    }

    /// `dateString` is a FORMAT, not rendered text: the clock is its own
    /// widget so it can wake on the minute and rebuild only itself.
    private func _statusBarClockItem(dateString: String) -> Widget {
        let isActive = activeStatusBarPopup == .clock
        let textWidget = ShellClock(
            format: dateString,
            style: Flutter.TextStyle(
                color: shellTheme.fgPrimary,
                fontSize: 13,
                fontWeight: isActive ? .w600 : .w400, fontFamily: shellTheme.fontFamily)
        )
        let bg: Widget = isActive
            ? DecoratedBox(
                decoration: BoxDecoration(
                    color: shellTheme.hoverFill,
                    borderRadius: BorderRadius.circular(4)
                ),
                child: Padding(
                    padding: EdgeInsets(left: 8, top: 2, right: 8, bottom: 2),
                    child: textWidget
                )
              )
            : Padding(
                padding: EdgeInsets(left: 8, top: 2, right: 8, bottom: 2),
                child: textWidget
              )
        return GestureDetector(
            onTap: { [self] in
                setState {
                    activeStatusBarPopup = isActive ? nil : .clock
                    contextMenuPosition = nil
                }
            },
            behavior: .opaque,
            child: bg
        )
    }

    private func _buildStatusBar() -> Widget {
        // One pattern rather than two formatters and a join: the clock is a
        // widget now and takes the format, so that it can keep its own
        // cadence instead of freezing whenever the shell stops rebuilding.
        let combined = "h:mm   EEE, MMM d"

        return Padding(
            padding: EdgeInsets(left: 16, top: 0, right: 16, bottom: 0),
            child: Row(
                mainAxisAlignment: .spaceBetween,
                crossAxisAlignment: .center,
                children: [
                    // Left: clock + date
                    _statusBarClockItem(dateString: combined),
                    // Right: wifi, battery (laptops only), power
                    Row(
                        mainAxisSize: .min,
                        crossAxisAlignment: .center,
                        spacing: 2
                    ) {
                        // Recording indicator — leftmost ON PURPOSE: every
                        // popup offset in _statusPopupGeometry is measured
                        // from the right edge, so a conditional item can
                        // only sit left of them all without moving them.
                        // Tap = stop; it exists only while a session runs.
                        if recordingService?.isRecording == true {
                            _recordingIndicator()
                        }
                        _statusBarItem(icon: _networkStatusIcon(), popup: .wifi)
                        if batteryService.snapshot.present {
                            _statusBarItem(icon: _batteryStatusIcon(),
                                           popup: .battery,
                                           color: _batteryStatusColor())
                        }
                        // The bell fills while anything is collected and
                        // tints until the user looks; events only ever show
                        // inside its popup, never as banners over the desktop.
                        _statusBarItem(icon: _notifications.isEmpty
                                           ? CupertinoIcons.bell
                                           : CupertinoIcons.bell_fill,
                                       popup: .notifications,
                                       color: _notificationsUnseen
                                           ? shellTheme.accent : nil)
                        _statusBarItem(icon: CupertinoIcons.slider_horizontal_3,
                                       popup: .controlCenter)
                        // Rightmost, macOS-style. Until this existed there
                        // was no way to shut the desktop down from the UI
                        // at all — you had to find a terminal and sudo.
                        _statusBarItem(icon: CupertinoIcons.power, popup: .power)
                    },
                ]
            )
        )
    }

    // MARK: - Status Bar Popups

    private func _buildStatusBarPopup() -> Widget {
        switch activeStatusBarPopup! {
        case .wifi:
            return _buildWifiPopup()
        case .battery:
            return _buildBatteryPopup()
        case .notifications:
            return _buildNotificationsPopup()
        case .controlCenter:
            return _buildControlCenterPopup()
        case .clock:
            return _buildClockPopup()
        case .power:
            return _buildPowerPopup()
        }
    }

    /// Shut Down / Restart / Log Out, each behind a confirm step.
    private func _buildPowerPopup() -> Widget {
        if let pending = _powerConfirm {
            return _statusPopupPanel(popup: .power, children: [
                _popupSectionHeader(pending.title),
                Text(pending.prompt,
                     style: TextStyle(color: shellTheme.fgSecondary, fontSize: 12, fontFamily: shellTheme.fontFamily)),
                SizedBox(height: 12),
                Row(
                    mainAxisAlignment: .spaceBetween,
                    children: [
                        _powerButton("Cancel", destructive: false) { [self] in
                            setState { _powerConfirm = nil }
                        },
                        _powerButton(pending.title, destructive: true) { [self] in
                            // Close the menu first: the session may go away
                            // mid-frame, and a panel left open looks like a hang.
                            setState {
                                activeStatusBarPopup = nil
                                _powerConfirm = nil
                            }
                            _runPowerAction(pending)
                        },
                    ]
                ),
            ])
        }

        return _statusPopupPanel(popup: .power, children: [
            _popupSectionHeader("Power"),
            _powerMenuRow(.logOut, icon: CupertinoIcons.square_arrow_right),
            _powerMenuRow(.restart, icon: CupertinoIcons.arrow_clockwise),
            _powerMenuRow(.shutDown, icon: CupertinoIcons.power),
        ])
    }

    private func _powerMenuRow(_ action: PowerAction, icon: IconData) -> Widget {
        return GestureDetector(
            onTap: { [self] in setState { _powerConfirm = action } },
            behavior: .opaque,
            child: Padding(
                padding: EdgeInsets(left: 0, top: 7, right: 0, bottom: 7),
                child: Row(children: [
                    MacosIcon(icon: icon, color: shellTheme.fgPrimary, size: 15),
                    SizedBox(width: 10),
                    Text("\(action.title)\u{2026}",
                         style: TextStyle(color: shellTheme.fgPrimary, fontSize: 13, fontFamily: shellTheme.fontFamily)),
                ])
            )
        )
    }

    private func _powerButton(_ label: String, destructive: Bool,
                              _ onTap: @escaping () -> Void) -> Widget {
        return GestureDetector(
            onTap: onTap,
            behavior: .opaque,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: destructive ? shellTheme.accent : shellTheme.hoverFill,
                    borderRadius: BorderRadius.circular(6)
                ),
                child: Padding(
                    padding: EdgeInsets(left: 14, top: 6, right: 14, bottom: 6),
                    child: Text(label, style: TextStyle(
                        color: destructive ? shellTheme.accentInk
                                           : shellTheme.fgPrimary,
                        fontSize: 12, fontWeight: .w600, fontFamily: shellTheme.fontFamilyStrong))
                )
            )
        )
    }

    /// Hands the request to systemd and lets it decide. Deliberately no
    /// fallback to `shutdown`/`halt`: if logind refuses, the honest outcome is
    /// nothing happening rather than a second path with different semantics.
    private func _runPowerAction(_ action: PowerAction) {
        #if os(Linux)
        let (path, args) = action.command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        do {
            try process.run()
        } catch {
            FileHandle.standardError.write(Data(
                "[shell] power action \(action.title) failed: \(error)\n".utf8))
        }
        #endif
    }

    /// Fixed width and screen-left of each status popup — used both to
    /// position the panel and to hand the liquid-glass shader its rect.
    /// Anchors: status bar is padded 16 each side; each right-side icon item
    /// is 27px wide (6+15+6) with a 2px gap, so right edges run 16, 45, 74 from
    /// the right — power, battery, wifi, in status-bar order. The clock popup
    /// is left-anchored.
    private func _statusPopupGeometry(_ popup: StatusBarPopup) -> (width: Double, left: Double) {
        // Right-side items are 27px wide with 2px spacing, right-padded 16
        // (see _buildStatusBar). Right to left: power at -16 (FIXED — the
        // release gate clicks it at measured pixels), the bell at -45,
        // battery at -74 when a battery exists, wifi left of whichever of
        // those are present. The battery icon exists only on machines with
        // a battery, so wifi's position depends on it — a fixed offset once
        // put the wifi panel 29px left of the real icon on every desktop.
        let batteryW: Double = batteryService.snapshot.present ? 29 : 0
        switch popup {
        case .wifi:          return (280, screenWidth - 103 - batteryW - 280)
        case .battery:       return (260, screenWidth - 103 - 260)
        case .notifications: return (340, screenWidth - 74 - 340)
        case .controlCenter: return (Self.kCcPanelW, screenWidth - 45 - Self.kCcPanelW)
        case .power:         return (220, screenWidth - 16 - 220)
        case .clock:         return (260, 16)
        }
    }

    /// Screen position of a status-bar icon's center, derived from the same
    /// numbers that place its popup — tooling that clicks one asks for this
    /// rather than reproducing the arithmetic (the dock learned that lesson
    /// first; see `dockSlots`). Each right-side item is 27px wide.
    /// Internal, not private: the broker reports it.
    func statusItemCenter(_ popup: StatusBarPopup) -> (x: Double, y: Double) {
        let geo = _statusPopupGeometry(popup)
        // Panels are right-aligned to their icon, so the panel's right edge
        // is the icon's right edge — except the clock, which is left-anchored.
        let x = popup == .clock
            ? geo.left + 40
            : geo.left + geo.width - 13.5
        return (x, DesktopTheme.kStatusBarHeight / 2)
    }

    /// Where a status popup's *content column* sits: the panel inset by its
    /// 16px padding. Rows only take taps inside this band — the padding
    /// belongs to the panel — so tooling that clicks a row aims at
    /// `contentCenterX`, never at the icon's x (which is past the right
    /// edge of the content and hits nothing).
    /// Internal, not private: the broker reports it.
    func statusPopupContent(_ popup: StatusBarPopup)
        -> (left: Double, width: Double, top: Double, centerX: Double) {
        let geo = _statusPopupGeometry(popup)
        let pad: Double = 16
        let left = geo.left + pad
        let width = geo.width - pad * 2
        return (left, width, DesktopTheme.kStatusBarHeight + 1 + pad,
                left + width / 2)
    }

    /// Records a popup panel's laid-out height (fires from MeasureSize during
    /// layout — mutate state on the main queue, never synchronously).
    private func _recordStatusPopupHeight(_ popup: StatusBarPopup, _ size: Size) {
        if abs((_statusPopupHeights[popup] ?? -1) - size.height) < 0.5 { return }
        let h = size.height
        let update: () -> Void = { [weak self] in
            guard let self else { return }
            self.setState { self._statusPopupHeights[popup] = h }
        }
        // Same-thread hop out of the layout pass; the state is main-thread
        // only, so the @Sendable coercion is safe (codebase idiom).
        DispatchQueue.main.async(
            execute: unsafeBitCast(update, to: (@Sendable () -> Void).self))
    }

    /// macOS-style popup panel — Liquid Glass: blurred + saturation-boosted
    /// backdrop warped by the refraction shader, a translucent dark tint for
    /// text legibility, and a thin white hairline. The shader needs the exact
    /// panel rect; the height is intrinsic, so it comes from MeasureSize (the
    /// first frame after opening renders with the plain-frost fallback).
    private func _statusPopupPanel(popup: StatusBarPopup, children: [Widget]) -> Widget {
        let radius = shellMetrics.panelCornerRadius
        let geo = _statusPopupGeometry(popup)
        // The refraction shader is macOS's liquid glass — an edge that bends
        // the wallpaper behind it. Windows' acrylic has no such thing: it is
        // a flat frosted pane, so the Fluent style takes the blur without the
        // lensing, and desaturating rather than saturating (see ShellMaterial).
        let isAcrylic = shellTheme.material == .acrylic
        let shader = (!isAcrylic && _statusPopupHeights[popup] != nil)
            ? _popupGlassShaderIfAvailable() : nil
        // The panel's real screen rect, from the same place that positions it.
        // Two answers here means the glass refracts a rectangle the panel is
        // not standing in — which is exactly what happened when this read the
        // menu bar's height in a style that has no menu bar.
        let height = _statusPopupHeights[popup] ?? 0
        let origin = chrome.statusFlyoutOrigin(popup, height: height)
        let filter = _liquidGlassFilter(
            shader: shader,
            left: origin.dx, top: origin.dy,
            width: geo.width, height: height,
            cornerRadius: radius,
            blurSigma: isAcrylic ? 30 : 16,
            saturation: isAcrylic ? 0.75 : 1.15)
        return MeasureSize(
            onSize: { [weak self] size in
                self?._recordStatusPopupHeight(popup, size)
            },
            child: SizedBox(
                width: geo.width,
                child: DecoratedBox(
                    // Drop shadow lives outside the clip so it doesn't get blurred.
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius),
                        boxShadow: [
                            BoxShadow(color: shellTheme.popupShadow, offset: Offset(0, 6), blurRadius: 24),
                        ]
                    ),
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(radius),
                        child: BackdropFilter(
                            filter: filter,
                            child: DecoratedBox(
                                decoration: BoxDecoration(
                                    // Translucent tint over the glass —
                                    // lighter than plain frost needs, since the
                                    // refraction already separates the panel.
                                    color: shellTheme.popupTint,
                                    // Hairline that defines the panel against any backdrop.
                                    border: Border.all(
                                        color: shellTheme.popupInnerBorder,
                                        width: 1.0
                                    ),
                                    borderRadius: BorderRadius.circular(radius)
                                ),
                                child: Padding(
                                    padding: EdgeInsets(all: 16),
                                    child: Column(
                                        mainAxisSize: .min,
                                        crossAxisAlignment: .start,
                                        children: children
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    }

    /// Section header text (e.g. "Wi-Fi", "Battery")
    /// Fixed at kNetSectionHeaderH so the blocks below it sit at a computable
    /// offset (see the network popup metrics).
    private func _popupSectionHeader(_ title: String) -> Widget {
        return SizedBox(
            height: Self.kNetSectionHeaderH,
            child: Padding(
                padding: EdgeInsets(bottom: 10),
                child: Text(
                    title,
                    style: TextStyle(
                        color: shellTheme.fgPrimary,
                        fontSize: 15,
                        fontWeight: .w600, fontFamily: shellTheme.fontFamilyStrong)
                )
            )
        )
    }

    /// A row with icon, label, and right-side value
    private func _popupInfoRow(icon: IconData, label: String, value: String) -> Widget {
        return Padding(
            padding: EdgeInsets(top: 4, bottom: 4),
            child: Row(
                mainAxisSize: .max,
                children: [
                    MacosIcon(icon: icon, color: shellTheme.fgTertiary, size: 14),
                    SizedBox(width: 8),
                    Text(
                        label,
                        style: TextStyle(color: shellTheme.fgSecondary, fontSize: 13, fontFamily: shellTheme.fontFamily)
                    ),
                    Expanded(child: SizedBox(width: 0)),
                    Text(
                        value,
                        style: TextStyle(color: shellTheme.fgTertiary, fontSize: 13, fontFamily: shellTheme.fontFamily)
                    ),
                ]
            )
        )
    }

    /// Horizontal divider for popup panels
    private func _popupDivider() -> Widget {
        return Padding(
            padding: EdgeInsets(top: 8, bottom: 8),
            child: SizedBox(
                width: Double.infinity,
                height: 1,
                child: ColoredBox(color: shellTheme.popupDivider)
            )
        )
    }

    /// Clickable row item (e.g. "Network Preferences...")
    private func _popupActionRow(label: String, onTap: @escaping () -> Void) -> Widget {
        return GestureDetector(
            onTap: onTap,
            behavior: .opaque,
            child: Padding(
                padding: EdgeInsets(top: 6, bottom: 6),
                child: Text(
                    label,
                    style: TextStyle(
                        color: shellTheme.accent,
                        fontSize: 13, fontFamily: shellTheme.fontFamily)
                )
            )
        )
    }

    // MARK: - WiFi popup (real state via NetworkService)

    /// The status-bar glyph for the whole network, not just the radio: a
    /// machine on ethernet is online, and showing it a struck-through WiFi
    /// icon (because the radio is off) would be a lie about connectivity.
    /// Wired wins whenever it is carrying the connection.
    private func _networkStatusIcon() -> IconData {
        let snap = networkService.snapshot
        if snap.wired?.connected == true { return CupertinoIcons.globe }
        if !snap.available || !snap.wifiEnabled { return CupertinoIcons.wifi_slash }
        if snap.active == nil { return CupertinoIcons.wifi_exclamationmark }
        return CupertinoIcons.wifi
    }

    // MARK: Network popup metrics
    //
    // The panel's blocks are given these heights explicitly (SizedBox), so
    // they are the layout rather than a description of it. That makes every
    // row's position computable, which is the whole point: tooling that
    // clicks a network row asks the shell where it is (`wifi_state.rows`)
    // instead of carrying its own copy of the arithmetic. The dock learned
    // this the hard way — a mirrored layout in the test harness was wrong on
    // every machine but the one it was written on.
    static let kNetSectionHeaderH: Double = 28   // title + its bottom padding
    static let kNetDetailRowH: Double = 21       // one line of secondary text
    static let kNetDividerH: Double = 17         // rule + 8 above + 8 below
    static let kNetToggleRowH: Double = 30       // switch + bottom padding
    static let kNetNetworkRowH: Double = 27      // one scanned-network row

    /// Screen Y of each listed network's row center, filled in during build.
    /// Read by the broker; never used for layout.
    var _wifiRowCenters: [(ssid: String, y: Double)] = []

    /// Caret blink for the popup's password field — the Launchpad caret's
    /// token + asyncAfter loop with its own token, guarded on the prompt
    /// still being on screen (see _restartLauncherCaret for why not Timer).
    func _restartWifiCaret() {
        _wifiCaretToken &+= 1
        let token = _wifiCaretToken
        _wifiCaretOn = true

        func schedule() {
            let next: () -> Void = { [weak self] in
                guard let self, self._wifiCaretToken == token,
                      self.activeStatusBarPopup == .wifi,
                      self._wifiPasswordSSID != nil
                else { return }
                self.setState { self._wifiCaretOn.toggle() }
                schedule()
            }
            // Main-queue-only state; @Sendable coercion is the codebase idiom.
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(530),
                execute: unsafeBitCast(next, to: (@Sendable () -> Void).self))
        }
        schedule()
    }

    /// Start a join and reflect the outcome. `password` is nil for open and
    /// saved networks; the password prompt always passes one (possibly bad).
    func _wifiJoin(ssid: String, security: String, password: String?) {
        // WPA passwords are 8-63 characters. Catching a short one here costs
        // a message; letting NetworkManager discover it costs the user the
        // full 30-second activation timeout.
        if let pw = password, pw.count < 8 {
            setState { _wifiError = "Password must be at least 8 characters." }
            return
        }
        setState {
            _wifiConnecting = ssid
            _wifiError = nil
            _wifiPasswordSSID = nil
            _wifiPassword = ""
        }
        networkService.connect(ssid: ssid, security: security,
                               password: password) { [weak self] err in
            guard let self else { return }
            self.setState {
                self._wifiConnecting = nil
                self._wifiError = err
            }
        }
    }

    /// macOS-style switch, sized for the popup header row.
    private func _wifiToggle(on: Bool) -> Widget {
        return GestureDetector(
            onTap: { [self] in networkService.setWifiEnabled(!on) },
            behavior: .opaque,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: on ? shellTheme.accent : shellTheme.hoverFill,
                    borderRadius: BorderRadius.circular(10)
                ),
                child: SizedBox(
                    width: 36, height: 20,
                    child: Align(
                        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                        child: Padding(
                            padding: EdgeInsets(horizontal: 2),
                            child: DecoratedBox(
                                decoration: BoxDecoration(
                                    // The knob rides ON the accent when the
                                    // switch is on, so it takes the on-accent
                                    // ink rather than a literal white.
                                    color: on ? shellTheme.accentInk
                                              : Color(0xFFFFFFFF),
                                    borderRadius: BorderRadius.circular(8)
                                ),
                                child: SizedBox(width: 16, height: 16)
                            )
                        )
                    )
                )
            )
        )
    }

    /// Four ascending bars lit by signal strength — drawn rects, not the
    /// ▂▄▆█ block glyphs: the shell's font has no block elements, so the
    /// text spelling renders as tofu boxes.
    private func _wifiSignalBars(_ signal: Int) -> Widget {
        var bars: [Widget] = []
        let heights: [Double] = [4, 6, 8, 10]
        let thresholds = [1, 30, 55, 80]
        for i in 0..<4 {
            if i > 0 { bars.append(SizedBox(width: 2)) }
            bars.append(DecoratedBox(
                decoration: BoxDecoration(
                    color: signal >= thresholds[i]
                        ? shellTheme.fgSecondary : shellTheme.hoverFill,
                    borderRadius: BorderRadius.circular(1)
                ),
                child: SizedBox(width: 3, height: heights[i])
            ))
        }
        return Row(mainAxisSize: .min, crossAxisAlignment: .end, children: bars)
    }

    /// Screen Y of the first pixel inside a status popup's content column.
    func _statusPopupContentTop() -> Double {
        return statusPopupContent(.wifi).top
    }

    private func _wifiNetworkRow(_ net: WifiNetwork, known: Bool) -> Widget {
        var trailing: [Widget] = []
        if _wifiConnecting == net.ssid {
            trailing = [Text("Connecting\u{2026}",
                             style: TextStyle(color: shellTheme.fgTertiary, fontSize: 11, fontFamily: shellTheme.fontFamily))]
        } else {
            if !net.isOpen {
                trailing.append(MacosIcon(icon: CupertinoIcons.lock_fill,
                                          color: shellTheme.fgTertiary, size: 11))
                trailing.append(SizedBox(width: 5))
            }
            trailing.append(_wifiSignalBars(net.signal))
        }

        return GestureDetector(
            onTap: { [self] in
                guard _wifiConnecting == nil else { return }
                if net.isOpen || known {
                    _wifiJoin(ssid: net.ssid, security: net.security, password: nil)
                } else {
                    setState {
                        _wifiPasswordSSID = net.ssid
                        _wifiPasswordSecurity = net.security
                        _wifiPassword = ""
                        _wifiError = nil
                    }
                    _restartWifiCaret()
                }
            },
            behavior: .opaque,
            // Fixed height, so the row a user clicks is exactly the row the
            // shell told tooling about (kNetNetworkRowH — see the metrics).
            child: SizedBox(height: Self.kNetNetworkRowH, child: Padding(
                padding: EdgeInsets(top: 5, bottom: 5),
                child: Row(children: [
                    MacosIcon(icon: CupertinoIcons.wifi,
                              color: shellTheme.fgTertiary, size: 14),
                    SizedBox(width: 8),
                    Expanded(child: Text(
                        net.ssid,
                        style: TextStyle(color: shellTheme.fgPrimary, fontSize: 13, fontFamily: shellTheme.fontFamily),
                        overflow: .ellipsis,
                        maxLines: 1
                    )),
                    SizedBox(width: 8),
                ] + trailing)
            ))
        )
    }

    /// The panel content while asking for a password — swaps the whole panel
    /// like the power confirm does, so the popup never grows a second layer.
    private func _buildWifiPasswordPrompt(ssid: String) -> Widget {
        let caret = Text("|", style: TextStyle(
            // Blink by alpha, never by swapping the glyph — a caret that
            // appears and disappears from the layout makes the text shift.
            color: _wifiCaretOn ? shellTheme.fgPrimary : Color(0x00000000),
            fontSize: 13, fontFamily: shellTheme.fontFamily))
        var fieldChildren: [Widget]
        if _wifiPassword.isEmpty {
            fieldChildren = [caret, Text("Password", style: TextStyle(
                color: shellTheme.fgTertiary, fontSize: 13, fontFamily: shellTheme.fontFamily))]
        } else {
            fieldChildren = [
                Text(String(repeating: "\u{2022}", count: _wifiPassword.count),
                     style: TextStyle(color: shellTheme.fgPrimary, fontSize: 13, fontFamily: shellTheme.fontFamily),
                     overflow: .ellipsis, maxLines: 1),
                caret,
            ]
        }

        var children: [Widget] = [
            _popupSectionHeader("Join \(ssid)"),
            Text("Enter the network password.",
                 style: TextStyle(color: shellTheme.fgSecondary, fontSize: 12, fontFamily: shellTheme.fontFamily)),
            SizedBox(height: 10),
            SizedBox(width: Double.infinity, child: DecoratedBox(
                decoration: BoxDecoration(
                    color: shellTheme.hoverFill,
                    borderRadius: BorderRadius.circular(6)
                ),
                child: Padding(
                    padding: EdgeInsets(left: 10, top: 6, right: 10, bottom: 6),
                    child: Row(children: fieldChildren)
                )
            )),
        ]
        if let err = _wifiError {
            children.append(SizedBox(height: 8))
            children.append(Text(err, style: TextStyle(
                color: Color(0xFFFF6B6B), fontSize: 11, fontFamily: shellTheme.fontFamily)))
        }
        children.append(SizedBox(height: 12))
        children.append(Row(
            mainAxisAlignment: .spaceBetween,
            children: [
                _powerButton("Cancel", destructive: false) { [self] in
                    setState { _wifiPasswordSSID = nil; _wifiPassword = "" }
                },
                _powerButton("Join", destructive: true) { [self] in
                    _wifiJoin(ssid: ssid, security: _wifiPasswordSecurity,
                              password: _wifiPassword)
                },
            ]
        ))
        return _statusPopupPanel(popup: .wifi, children: children)
    }

    /// The wired block: one row for the link, plus its address and a
    /// connect/disconnect action once there is a cable to act on.
    /// Height is exactly 2 * kNetDetailRowH + kNetDividerH — see the metrics.
    private func _wiredSection(_ wired: WiredStatus) -> [Widget] {
        var rows: [Widget] = [
            SizedBox(height: Self.kNetDetailRowH, child: Padding(
                padding: EdgeInsets(top: 2, bottom: 2),
                child: Row(children: [
                    MacosIcon(icon: CupertinoIcons.globe,
                              color: wired.connected ? shellTheme.accent
                                                     : shellTheme.fgTertiary,
                              size: 14),
                    SizedBox(width: 8),
                    Expanded(child: Text(
                        "Wired",
                        style: TextStyle(
                            color: shellTheme.fgPrimary, fontSize: 13,
                            fontWeight: wired.connected ? .w600 : .w400, fontFamily: shellTheme.fontFamily),
                        overflow: .ellipsis, maxLines: 1
                    )),
                ])
            )),
            SizedBox(height: Self.kNetDetailRowH, child: Padding(
                padding: EdgeInsets(left: 22, top: 0, right: 0, bottom: 2),
                child: Row(children: [
                    Expanded(child: Text(
                        wired.connected ? wired.ipAddress : wired.summary,
                        style: TextStyle(color: shellTheme.fgTertiary, fontSize: 11, fontFamily: shellTheme.fontFamily),
                        overflow: .ellipsis, maxLines: 1
                    )),
                    // Nothing to offer without a cable — a Connect button
                    // that can only fail is worse than no button.
                    wired.carrier
                        ? GestureDetector(
                            onTap: { [self] in
                                networkService.setWiredConnected(
                                    !wired.connected, device: wired.device)
                            },
                            behavior: .opaque,
                            child: Text(wired.connected ? "Disconnect" : "Connect",
                                        style: TextStyle(color: shellTheme.accent,
                                                         fontSize: 11, fontFamily: shellTheme.fontFamily))
                          )
                        : SizedBox(width: 0),
                ])
            )),
        ]
        rows.append(_popupDivider())
        return rows
    }

    private func _buildWifiPopup() -> Widget {
        let snap = networkService.snapshot

        guard snap.available else {
            // No radio. Still a network panel if there is a wire.
            var children: [Widget] = [_popupSectionHeader("Network")]
            if let wired = snap.wired {
                children += _wiredSection(wired)
            }
            children.append(Text(
                "Wi-Fi is not available on this system.",
                style: TextStyle(color: shellTheme.fgSecondary, fontSize: 12, fontFamily: shellTheme.fontFamily)))
            children.append(_popupDivider())
            children.append(_popupActionRow(label: "Network Settings...") { [self] in
                setState {
                    activeStatusBarPopup = nil
                    _launchOrFocusApp("settings", extraArgs: ["--pane=network"])
                }
            })
            return _statusPopupPanel(popup: .wifi, children: children)
        }

        if let ssid = _wifiPasswordSSID {
            return _buildWifiPasswordPrompt(ssid: ssid)
        }

        // `y` tracks the top of the next block, in screen coordinates, using
        // the very heights the blocks are built with — so the row positions
        // reported to tooling cannot drift from what is drawn.
        var y = _statusPopupContentTop()
        var children: [Widget] = [_popupSectionHeader("Network")]
        y += Self.kNetSectionHeaderH
        if let wired = snap.wired {
            children += _wiredSection(wired)
            y += Self.kNetDetailRowH * 2 + Self.kNetDividerH
        }
        children.append(
            SizedBox(height: Self.kNetToggleRowH, child: Padding(
                padding: EdgeInsets(bottom: 10),
                child: Row(
                    mainAxisAlignment: .spaceBetween,
                    crossAxisAlignment: .center,
                    children: [
                        Text("Wi-Fi", style: TextStyle(
                            color: shellTheme.fgPrimary,
                            fontSize: 13, fontWeight: .w600, fontFamily: shellTheme.fontFamilyStrong)),
                        _wifiToggle(on: snap.wifiEnabled),
                    ]
                )
            ))
        )
        y += Self.kNetToggleRowH

        _wifiRowCenters = []
        if !snap.wifiEnabled {
            children.append(Text("Wi-Fi is off.", style: TextStyle(
                color: shellTheme.fgTertiary, fontSize: 12, fontFamily: shellTheme.fontFamily)))
        } else {
            if let active = snap.active {
                children.append(SizedBox(height: Self.kNetDetailRowH, child: Padding(
                    padding: EdgeInsets(top: 2, bottom: 2),
                    child: Row(children: [
                        MacosIcon(icon: CupertinoIcons.checkmark,
                                  color: shellTheme.accent, size: 12),
                        SizedBox(width: 8),
                        Expanded(child: Text(
                            active.ssid,
                            style: TextStyle(color: shellTheme.fgPrimary,
                                             fontSize: 13, fontWeight: .w600, fontFamily: shellTheme.fontFamilyStrong),
                            overflow: .ellipsis, maxLines: 1
                        )),
                        SizedBox(width: 8),
                        _wifiSignalBars(snap.networks.first { $0.inUse }?.signal ?? 0),
                    ])
                )))
                children.append(SizedBox(height: Self.kNetDetailRowH, child: Padding(
                    padding: EdgeInsets(left: 20, top: 0, right: 0, bottom: 2),
                    child: Row(children: [
                        Text(active.ipAddress,
                             style: TextStyle(color: shellTheme.fgTertiary, fontSize: 11, fontFamily: shellTheme.fontFamily)),
                        Expanded(child: SizedBox(width: 0)),
                        GestureDetector(
                            onTap: { [self] in
                                networkService.disconnect(connectionName: active.ssid)
                            },
                            behavior: .opaque,
                            child: Text("Disconnect", style: TextStyle(
                                color: shellTheme.accent, fontSize: 11, fontFamily: shellTheme.fontFamily))
                        ),
                    ])
                )))
                y += Self.kNetDetailRowH * 2
            }

            let others = snap.networks.filter { !$0.inUse }
            if !others.isEmpty {
                children.append(_popupDivider())
                y += Self.kNetDividerH
                for net in others.prefix(8) {
                    children.append(_wifiNetworkRow(
                        net, known: snap.savedNames.contains(net.ssid)))
                    _wifiRowCenters.append(
                        (ssid: net.ssid, y: y + Self.kNetNetworkRowH / 2))
                    y += Self.kNetNetworkRowH
                }
            } else if snap.active == nil {
                children.append(Text("No networks found.", style: TextStyle(
                    color: shellTheme.fgTertiary, fontSize: 12, fontFamily: shellTheme.fontFamily)))
            }
        }

        if let err = _wifiError {
            children.append(SizedBox(height: 6))
            children.append(Text(err, style: TextStyle(
                color: Color(0xFFFF6B6B), fontSize: 11, fontFamily: shellTheme.fontFamily)))
        }

        children.append(_popupDivider())
        children.append(_popupActionRow(label: "Network Settings...") { [self] in
            setState {
                activeStatusBarPopup = nil
                _launchOrFocusApp("settings", extraArgs: ["--pane=network"])
            }
        })
        return _statusPopupPanel(popup: .wifi, children: children)
    }

    /// The status-bar battery glyph. The Cupertino set is coarse — empty,
    /// quarter, three-quarter, full — so the thresholds just sit between
    /// glyphs. The charging bolt shows only while charge is actually
    /// flowing: `notCharging` is the firmware holding at a stop threshold,
    /// and a bolt there would claim something the kernel just said isn't
    /// happening.
    private func _batteryStatusIcon() -> IconData {
        let snap = batteryService.snapshot
        if snap.state == .charging { return CupertinoIcons.battery_charging }
        switch snap.percent {
        case ..<13: return CupertinoIcons.battery_empty
        case ..<45: return CupertinoIcons.battery_25_percent
        case ..<88: return CupertinoIcons.battery_75_percent
        default:    return CupertinoIcons.battery_full
        }
    }

    /// Tint for that glyph: red only when low *and* draining (low on AC is
    /// getting better, not worse), green while charge flows, nil otherwise
    /// so the icon follows the theme like every other status item.
    private func _batteryStatusColor() -> Color? {
        let snap = batteryService.snapshot
        if snap.state == .discharging && snap.percent <= 20 {
            return Color(0xFFFF3B30)
        }
        if snap.state == .charging { return Color(0xFF34C759) }
        return nil
    }

    /// "2 h 05 min" under an hour shortens to "45 min" — the popup's
    /// time-remaining spelling.
    private func _formatBatteryMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min"
        }
        return "\(minutes) min"
    }

    private func _buildBatteryPopup() -> Widget {
        let snap = batteryService.snapshot
        // The bar wears the icon's warning colors; at rest it takes the
        // accent, not green — a battery sitting at 60% is a level, not a
        // success state.
        let barColor = _batteryStatusColor() ?? shellTheme.accent
        let batteryBar: Widget = SizedBox(
            height: 8,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: shellTheme.popupDivider,
                    borderRadius: BorderRadius.circular(4)
                ),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                        widthFactor: Double(snap.percent) / 100.0,
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: barColor,
                                borderRadius: BorderRadius.circular(4)
                            ),
                            child: SizedBox(expand: ())
                        )
                    )
                )
            )
        )

        var children: [Widget] = [
            _popupSectionHeader("Battery"),
            Row(
                children: [
                    MacosIcon(icon: _batteryStatusIcon(),
                              color: _batteryStatusColor() ?? shellTheme.fgPrimary,
                              size: 22),
                    SizedBox(width: 10),
                    Text(
                        "\(snap.percent)%",
                        style: TextStyle(
                            color: shellTheme.fgPrimary,
                            fontSize: 24,
                            fontWeight: .w300, fontFamily: shellTheme.fontFamily)
                    ),
                ]
            ),
            SizedBox(height: 10),
            batteryBar,
            SizedBox(height: 6),
            Text(
                "Power Source: \(snap.acOnline ? "AC Power" : "Battery")",
                style: TextStyle(color: shellTheme.fgTertiary, fontSize: 12, fontFamily: shellTheme.fontFamily)
            ),
            _popupDivider(),
            _popupInfoRow(icon: CupertinoIcons.bolt, label: "Status",
                          value: snap.state.label),
        ]
        // The estimate rows exist only when the kernel offered a rate — a
        // missing estimate reads as a missing row, never as a made-up time.
        if snap.state == .charging, let m = snap.minutesToFull {
            children.append(_popupInfoRow(icon: CupertinoIcons.clock,
                                          label: "Full in",
                                          value: _formatBatteryMinutes(m)))
        } else if snap.state == .discharging, let m = snap.minutesToEmpty {
            children.append(_popupInfoRow(icon: CupertinoIcons.clock,
                                          label: "Remaining",
                                          value: _formatBatteryMinutes(m)))
        }
        children.append(_popupDivider())
        children.append(_popupActionRow(label: "Battery Settings...") { [self] in
            setState {
                activeStatusBarPopup = nil
                _launchOrFocusApp("settings", extraArgs: ["--pane=power"])
            }
        })
        return _statusPopupPanel(popup: .battery, children: children)
    }

    // MARK: - Notifications

    /// Upsert from the daemon (already hopped to main). The spec's
    /// expire_timeout is a banner concept — how long to interrupt the user.
    /// This desktop never interrupts: events collect behind the bell and are
    /// shown only when it is clicked, so they stay until the user dismisses
    /// them or the client closes them. The parameter is accepted and
    /// ignored, which the spec permits ("the server may override").
    func _notificationPosted(id: UInt32, appName: String, summary: String,
                             body: String, urgency: Int, timeoutMs: Int,
                             replaces: Bool) {
        setState {
            let note = ShellNotification(id: id, appName: appName,
                                         summary: summary, body: body,
                                         urgency: urgency)
            if let i = _notifications.firstIndex(where: { $0.id == id }) {
                _notifications[i] = note
            } else {
                _notifications.append(note)
            }
            if activeStatusBarPopup != .notifications {
                _notificationsUnseen = true
            }
        }
    }

    /// The shell posting to its own bell (recording saved, …) — same upsert
    /// as a bus post, but the id comes from the shell's own high-range
    /// counter so it can never collide with the daemon's.
    func _postLocalNotification(summary: String, body: String) {
        _localNoteId += 1
        _notificationPosted(id: _localNoteId, appName: "Screen Recording",
                            summary: summary, body: body, urgency: 1,
                            timeoutMs: -1, replaces: false)
    }

    /// CloseNotification from the bus (already hopped to main). Closing an
    /// id we no longer show is not an error — the spec says so.
    func _notificationCloseRequested(_ id: UInt32) {
        guard _notifications.contains(where: { $0.id == id }) else { return }
        _dismissNotification(id: id, reason: 3)
    }

    func _dismissNotification(id: UInt32, reason: UInt32) {
        setState { _notifications.removeAll { $0.id == id } }
        notificationIntegration?.emitClosed(id: id, reason: reason)
    }

    /// The bell's popup: every collected event, newest first, in the same
    /// glass panel as the other status popups. A row's tap dismisses that
    /// event (reason 2); Clear All dismisses everything. Ten rows render —
    /// older ones stay live for the broker and CloseNotification, and the
    /// footer says how many.
    private func _buildNotificationsPopup() -> Widget {
        var children: [Widget] = [_popupSectionHeader("Notifications")]
        if _notifications.isEmpty {
            children.append(Text(
                "No notifications",
                style: TextStyle(color: shellTheme.fgTertiary, fontSize: 12, fontFamily: shellTheme.fontFamily)))
            return _statusPopupPanel(popup: .notifications, children: children)
        }
        let newestFirst = Array(_notifications.reversed())
        for (i, note) in newestFirst.prefix(10).enumerated() {
            if i > 0 { children.append(_popupDivider()) }
            var lines: [Widget] = []
            if !note.appName.isEmpty {
                lines.append(Text(
                    note.appName,
                    style: TextStyle(color: shellTheme.fgTertiary, fontSize: 10, fontFamily: shellTheme.fontFamily)))
                lines.append(SizedBox(height: 2))
            }
            lines.append(Text(
                note.summary,
                style: TextStyle(
                    color: note.urgency >= 2 ? Color(0xFFE0655A)
                                             : shellTheme.fgPrimary,
                    fontSize: 13, fontWeight: .w600, fontFamily: shellTheme.fontFamilyStrong),
                overflow: .ellipsis, maxLines: 1))
            if !note.body.isEmpty {
                lines.append(SizedBox(height: 2))
                lines.append(Text(
                    note.body,
                    style: TextStyle(color: shellTheme.fgSecondary, fontSize: 12, fontFamily: shellTheme.fontFamily),
                    overflow: .ellipsis, maxLines: 3))
            }
            children.append(GestureDetector(
                onTap: { [weak self] in
                    self?._dismissNotification(id: note.id, reason: 2)
                },
                behavior: .opaque,
                child: Column(
                    mainAxisSize: .min,
                    crossAxisAlignment: .start,
                    children: lines
                )
            ))
        }
        if _notifications.count > 10 {
            children.append(SizedBox(height: 6))
            children.append(Text(
                "…and \(_notifications.count - 10) older",
                style: TextStyle(color: shellTheme.fgTertiary, fontSize: 11, fontFamily: shellTheme.fontFamily)))
        }
        children.append(_popupDivider())
        children.append(_popupActionRow(label: "Clear All") { [self] in
            let ids = _notifications.map { $0.id }
            for id in ids { _dismissNotification(id: id, reason: 2) }
        })
        return _statusPopupPanel(popup: .notifications, children: children)
    }

    // MARK: - Control center

    // The panel's blocks are given these sizes explicitly, so they are the
    // layout rather than a description of it — tooling that taps a tile asks
    // the broker where it is (`control_center_state.tiles`), the same
    // arrangement that keeps the wifi rows and the dock honest.
    static let kCcPanelW: Double = 304
    static let kCcPad: Double = 16
    static let kCcTileW: Double = 132
    static let kCcTileH: Double = 60
    static let kCcGap: Double = 8

    /// Screen center of one quick tile: 2 columns, in declaration order
    /// (wifi, dark, tiling, mute, record). Read by the broker; never used
    /// for layout.
    func controlCenterTileCenter(_ index: Int) -> (x: Double, y: Double) {
        let geo = _statusPopupGeometry(.controlCenter)
        let col = Double(index % 2), row = Double(index / 2)
        return (geo.left + Self.kCcPad + col * (Self.kCcTileW + Self.kCcGap)
                    + Self.kCcTileW / 2,
                DesktopTheme.kStatusBarHeight + 1 + Self.kCcPad
                    + row * (Self.kCcTileH + Self.kCcGap) + Self.kCcTileH / 2)
    }

    /// Re-read levels off the main thread, then keep a 2s tick alive while
    /// the panel is the one on screen.
    func _refreshControlCenter() {
        let work: () -> Void = { [weak self] in
            let audio = AudioControl.status()
            let backlight = BacklightControl.read()
            let apply: () -> Void = { [weak self] in
                guard let self else { return }
                self.setState {
                    self._ccAudio = audio
                    self._ccBacklight = backlight
                }
                self._scheduleCcTick()
            }
            DispatchQueue.main.async(
                execute: unsafeBitCast(apply, to: (@Sendable () -> Void).self))
            _ = self
        }
        DispatchQueue.global(qos: .userInitiated).async(
            execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
    }

    private func _scheduleCcTick() {
        guard activeStatusBarPopup == .controlCenter, !_ccTickScheduled else { return }
        _ccTickScheduled = true
        let work: () -> Void = { [weak self] in
            guard let self else { return }
            self._ccTickScheduled = false
            guard self.activeStatusBarPopup == .controlCenter else { return }
            self._refreshControlCenter()
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 2,
            execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
    }

    private func _ccToggleTile(icon: IconData, label: String, active: Bool,
                               enabled: Bool = true,
                               onTap: @escaping () -> Void) -> Widget {
        // On an active tile the ink comes from the theme, not from a literal
        // white: Fluent's dark-mode accent is a LIGHT blue and takes BLACK
        // glyphs. White here is legible under the macOS accent and close to
        // invisible under the Fluent one.
        let fg: Color = !enabled
            ? shellTheme.fgTertiary
            : (active ? shellTheme.accentInk : shellTheme.fgPrimary)
        return GestureDetector(
            onTap: { if enabled { onTap() } },
            behavior: .opaque,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: active && enabled
                        ? shellTheme.accent : shellTheme.hoverFill,
                    borderRadius: BorderRadius.circular(10)
                ),
                child: SizedBox(
                    width: Self.kCcTileW, height: Self.kCcTileH,
                    child: Padding(
                        padding: EdgeInsets(horizontal: 12),
                        child: Column(
                            mainAxisAlignment: .center,
                            crossAxisAlignment: .start,
                            children: [
                                MacosIcon(icon: icon, color: fg, size: 16),
                                SizedBox(height: 4),
                                Text(label, style: TextStyle(
                                    color: fg, fontSize: 11,
                                    fontWeight: .w600, fontFamily: shellTheme.fontFamilyStrong)),
                            ]
                        )
                    )
                )
            )
        )
    }

    private func _ccSliderRow(icon: IconData, value: Double, enabled: Bool,
                              onChanged: @escaping (Double) -> Void) -> Widget {
        Row(children: [
            MacosIcon(icon: icon,
                      color: enabled ? shellTheme.fgSecondary
                                     : shellTheme.fgTertiary, size: 14),
            SizedBox(width: 10),
            Expanded(
                child: MacosSlider(
                    value: value,
                    onChanged: { v in if enabled { onChanged(v) } },
                    min: 0, max: 100,
                    color: shellTheme.accent
                )
            ),
            SizedBox(width: 10),
            Text("\(Int(value.rounded()))%",
                 style: TextStyle(color: shellTheme.fgTertiary, fontSize: 11, fontFamily: shellTheme.fontFamily)),
        ])
    }

    /// iOS-style quick panel: five toggle tiles, then the level sliders.
    /// Every control drives the same backend its Settings pane does — the
    /// tile IS the setting, so the two cannot disagree.
    private func _buildControlCenterPopup() -> Widget {
        let net = networkService.snapshot
        let wifiOn = net.available && net.wifiEnabled
        let tiles: [Widget] = [
            _ccToggleTile(icon: wifiOn ? CupertinoIcons.wifi
                                       : CupertinoIcons.wifi_slash,
                          label: "Wi-Fi", active: wifiOn,
                          enabled: net.available) { [self] in
                setState { networkService.setWifiEnabled(!net.wifiEnabled) }
            },
            _ccToggleTile(icon: CupertinoIcons.moon_fill, label: "Dark Mode",
                          active: shellTheme.isDark) { [self] in
                _setAppearance(dark: !shellTheme.isDark)
            },
            _ccToggleTile(icon: CupertinoIcons.rectangle_grid_2x2,
                          label: "Tiling", active: windowManager.tilingEnabled) { [self] in
                _setTiling(!windowManager.tilingEnabled)
            },
            _ccToggleTile(icon: _ccAudio.muted
                              ? CupertinoIcons.speaker_slash_fill
                              : CupertinoIcons.speaker_2_fill,
                          label: _ccAudio.muted ? "Muted" : "Sound",
                          active: !_ccAudio.muted,
                          enabled: _ccAudio.available) { [self] in
                let muted = !_ccAudio.muted
                setState { _ccAudio.muted = muted }
                DispatchQueue.global(qos: .userInitiated).async {
                    AudioControl.setMuted(muted)
                }
            },
            _ccToggleTile(icon: recordingService?.isRecording == true
                              ? CupertinoIcons.stop_fill
                              : CupertinoIcons.largecircle_fill_circle,
                          label: recordingService?.isRecording == true
                              ? "Recording" : "Record",
                          active: recordingService?.isRecording == true,
                          enabled: recordingService?.available == true) { [self] in
                if recordingService?.isRecording == true {
                    recordingService?.stop()
                } else {
                    // Close the panel first and give it a beat to leave the
                    // screen — a recording that opens on the control center
                    // sliding away is footage of the button, not the desktop.
                    setState { activeStatusBarPopup = nil }
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
                        recordingService?.start()
                    }
                }
            },
            // Record App: same session machinery, aimed at one window. The
            // tile opens Mission Control as a picker — every window spread
            // out as a live card, click one to record it, Esc to cancel.
            // Either tile stops a running session.
            _ccToggleTile(icon: CupertinoIcons.macwindow,
                          label: recordingService?.isRecording == true
                              ? "Recording" : "Record App",
                          active: recordingService?.isRecording == true
                              && recordingService?.windowLabel != nil,
                          enabled: recordingService?.available == true) { [self] in
                if recordingService?.isRecording == true {
                    recordingService?.stop()
                    return
                }
                guard windowManager.visibleWindows.contains(where: { $0.textureId != nil }) else {
                    _postLocalNotification(summary: "Nothing to record",
                                           body: "Open the app first — Record App captures one window.")
                    return
                }
                _openMissionControl(pickRecordTarget: true)
            },
        ]
        var children: [Widget] = [
            Row(children: [tiles[0], SizedBox(width: Self.kCcGap), tiles[1]]),
            SizedBox(height: Self.kCcGap),
            Row(children: [tiles[2], SizedBox(width: Self.kCcGap), tiles[3]]),
            SizedBox(height: Self.kCcGap),
            Row(children: [tiles[4], SizedBox(width: Self.kCcGap), tiles[5]]),
            SizedBox(height: 14),
            _ccSliderRow(icon: CupertinoIcons.speaker_2_fill,
                         value: min(_ccAudio.volume, 1.0) * 100,
                         enabled: _ccAudio.available) { [self] v in
                setState { _ccAudio.volume = v / 100 }
                DispatchQueue.global(qos: .userInitiated).async {
                    AudioControl.setVolume(v / 100)
                }
            },
        ]
        if _ccBacklight.present {
            children.append(SizedBox(height: 6))
            let backlight = _ccBacklight
            children.append(_ccSliderRow(
                icon: CupertinoIcons.sun_max_fill,
                value: Double(backlight.percent),
                enabled: true) { [self] v in
                let pct = Int(v.rounded())
                let scale = Double(backlight.maxBrightness) / 100.0
                setState {
                    _ccBacklight.brightness = max(1, Int((Double(pct) * scale).rounded()))
                }
                let work: () -> Void = {
                    BacklightControl.setPercent(pct, status: backlight)
                }
                DispatchQueue.global(qos: .userInitiated).async(
                    execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
            })
        }
        return _statusPopupPanel(popup: .controlCenter, children: children)
    }

    private func _buildClockPopup() -> Widget {
        let now = Date()
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm"
        let timeString = timeFmt.string(from: now)

        let ampmFmt = DateFormatter()
        ampmFmt.dateFormat = "a"
        let ampmString = ampmFmt.string(from: now)

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "EEEE, MMMM d, yyyy"
        let dateString = dateFmt.string(from: now)

        return _statusPopupPanel(popup: .clock, children: [
            Center(
                child: Text(
                    timeString,
                    style: TextStyle(
                        color: shellTheme.fgPrimary,
                        fontSize: 48,
                        fontWeight: .w200, fontFamily: shellTheme.fontFamily)
                )
            ),
            Center(
                child: Text(
                    ampmString,
                    style: TextStyle(
                        color: shellTheme.fgTertiary,
                        fontSize: 16,
                        fontWeight: .w400, fontFamily: shellTheme.fontFamily)
                )
            ),
            SizedBox(height: 6),
            Center(
                child: Text(
                    dateString,
                    style: TextStyle(
                        color: shellTheme.fgSecondary,
                        fontSize: 13, fontFamily: shellTheme.fontFamily)
                )
            ),
            _popupDivider(),
            _popupActionRow(label: "Date & Time Settings...") { [self] in
                setState {
                    activeStatusBarPopup = nil
                    _launchOrFocusApp("settings", extraArgs: ["--pane=datetime"])
                }
            },
        ])
    }

    // MARK: - Dock (macOS style, bottom centered)

    /// The registry record behind an app id — the one place any fact about an
    /// app is read from.
    private func _record(_ appId: String) -> AppRecord? {
        AppRegistry.shared.app(id: appId)
    }

    /// Icon tile base colour, from the catalog. One harmonized palette: every
    /// colour sits in the same saturation/brightness band, so hue carries app
    /// identity without any tile shouting over the rest — which is exactly why
    /// it is a catalog field and not the app's own brand colour.
    private func _dockIconColor(for appId: String) -> Color {
        Color(Int(_record(appId)?.color ?? 0x5C8FD6) | 0xFF00_0000)
    }

    /// Human-readable label for dock tooltips and launcher tiles.
    private func _dockAppLabel(for appId: String) -> String {
        _record(appId)?.name ?? appId
    }

    /// The painted glyph an app falls back to when no host icon resolves.
    // Internal, not private: the workspace tab strip draws the same glyphs.
    func _iconType(for appId: String) -> IconType {
        Self.iconType(named: _record(appId)?.glyph ?? "externalApp")
    }

    /// Catalog `Glyph` name -> painter case. This is the only app-shaped
    /// switch left in the shell, and it is about drawing rather than about
    /// apps: adding an app never touches it unless that app wants a shape we
    /// do not draw yet.
    static func iconType(named name: String) -> IconType {
        switch name {
        case "settings":   return .settings
        case "folder":     return .folder
        case "document":   return .document
        case "terminal":   return .terminal
        case "calculator": return .calculator
        case "store":      return .store
        case "photos":     return .photos
        case "video":      return .video
        case "activity":   return .activity
        case "chrome":     return .chrome
        case "vscode":     return .vscode
        case "apps":       return .apps
        case "flutterApp": return .flutterApp
        default:           return .externalApp
        }
    }

    // MARK: Installed-app detection — launcher/dock show what's installed

    /// True if the app is actually installed. The registry answers this: an
    /// `app-install` record means the store put it there, and failing that a
    /// catalog `Bins` path existing covers the app the user installed by hand.
    static func appIsInstalled(_ id: String) -> Bool {
        AppRegistry.shared.app(id: id)?.installed ?? false
    }

    /// Re-derive the dock after the registry changed.
    ///
    /// Drops anything no longer installed — a tile that launches nothing is
    /// worse than an absent one — and restores any default-dock app that came
    /// back, at its catalog position. That second half matters: an uninstall
    /// followed by a reinstall must not cost the icon until the next login,
    /// which is exactly what a plain prune does.
    ///
    /// The user's own arrangement survives both: drag order is untouched, and
    /// an app they removed by hand stays removed.
    func _reconcileDock() {
        dockAppOrder.removeAll { !Self.appIsInstalled($0) }
        for rec in AppRegistry.shared.defaultDock
        where !dockAppOrder.contains(rec.id) && !_dockRemovedByUser.contains(rec.id) {
            let order = rec.dockOrder ?? Int.max
            let idx = dockAppOrder.firstIndex {
                (AppRegistry.shared.app(id: $0)?.dockOrder ?? Int.max) > order
            } ?? dockAppOrder.count
            dockAppOrder.insert(rec.id, at: idx)
        }
    }

    /// Restart the Launchpad search caret, showing it immediately.
    ///
    /// Put the caret solid again and restart its blink — called when the
    /// launcher opens and on every keystroke, so it sits steady while you
    /// type and only resumes blinking once you pause. That is what a real
    /// text field does, and what makes the pill read as an input.
    ///
    /// This used to OWN the blink: a 530 ms `asyncAfter` chain toggling shell
    /// state inside `setState`, which rebuilds the whole tree. An open Start
    /// menu sitting untouched cost 2.35% of a core that way — 1.9 frames a
    /// second at 9.7 ms each, to flip one glyph between two colours. The
    /// blink belongs to the caret (`ShellCaret`); all that is left here is
    /// the nudge that says "the user just typed".
    func _restartLauncherCaret() {
        _launcherCaretToken &+= 1
    }

    /// The launcher's app entries — installed apps only (no phantom tiles for
    /// uninstalled apps), in catalog order, filtered by the current search query.
    // Internal, not private: the agent broker reports this so a functional
    // test can assert what the Launchpad is actually showing.
    func _launcherFilteredApps() -> [LauncherApp] {
        let all = AppRegistry.shared.installedApps.map { rec in
            LauncherApp(
                appId: rec.id,
                title: rec.name,
                iconType: Self.iconType(named: rec.glyph),
                bgColor: Color(Int(rec.color) | 0xFF00_0000),
                textureId: iconTextures[rec.id]
            )
        }
        let q = _launcherQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return all }
        return all.filter { $0.title.lowercased().contains(q) }
    }

    /// Compute the target index the dragged icon should move to, based on drag delta.
    private func _dockDragTargetIndex() -> Int {
        guard let fromIndex = _dockDragIndex else { return 0 }
        let dx = _dockDragCurrentX - _dockDragStartX
        let slotWidth = DesktopTheme.kDockIconSize + DesktopTheme.kDockIconPadding
        let slotShift = Int((dx / slotWidth).rounded())
        let target = fromIndex + slotShift
        return max(0, min(target, dockAppOrder.count - 1))
    }

    // MARK: Dock magnification geometry

    /// Per-build dock geometry: slot scales/widths under the current hover
    /// magnification, and the pill's resulting size and position. Slot 0 is
    /// the launcher; slots 1... map to `dockAppOrder`. Scales are computed
    /// against the *base* (unmagnified) geometry so cursor → scale is a
    /// stable mapping with no layout feedback loop.
    struct DockMetrics {
        var scales: [Double]
        var slotWidths: [Double]
        var width: Double      // current pill width
        var left: Double       // current pill left (kept centered)
        var baseWidth: Double
        var baseLeft: Double
        var baseCenters: [Double]  // unmagnified slot centers, dock-local x
    }

    /// Gap that follows slot `i` (wider divider gap after the launcher).
    private func _dockGapAfter(_ i: Int, slotCount: Int) -> Double {
        if i >= slotCount - 1 { return 0 }
        return i == 0 ? DesktopTheme.kDockIconPadding * 2 : DesktopTheme.kDockIconPadding
    }

    /// The output the dock is drawn on: the user's primary display. Falls back
    /// to a host-shaped stand-in on the dev paths that build no layout.
    var dockOutput: DisplayOutput {
        if let dl = displayLayout { return dl.primary }
        return DisplayOutput(
            id: 0, name: "primary",
            physicalWidth: Int(screenWidth * currentShellDpi),
            physicalHeight: Int(screenHeight * currentShellDpi),
            scale: currentShellDpi, originX: 0, originY: 0,
            isHost: true, isPrimary: true, refreshMhz: 60000)
    }

    /// Whether the shell's own tree is the one that draws the dock. False once
    /// the user makes another monitor primary — then it belongs to that
    /// output's `SecondaryOutputScreen`.
    var dockIsOnHost: Bool { displayLayout.map { $0.primaryIsHost } ?? true }

    /// Dock geometry centred on `outputWidth` — the logical width of the
    /// output the dock is drawn on, which is not `screenWidth` once the
    /// primary is a different monitor from the host.
    private func _dockMetrics(outputWidth: Double? = nil) -> DockMetrics {
        let outW = outputWidth ?? dockOutput.logicalWidth
        let hPad = DesktopTheme.kDockHorizontalPadding
        // The launcher (slot 0) is a full tile like the app icons, so it uses
        // the same base slot size and magnifies identically.
        let baseSizes = [DesktopTheme.kDockIconSize]
            + _dockDisplayApps.map { _ in DesktopTheme.kDockIconSize }
        let n = baseSizes.count

        var baseCenters: [Double] = []
        var xOff = hPad
        for (i, s) in baseSizes.enumerated() {
            baseCenters.append(xOff + s / 2)
            xOff += s + _dockGapAfter(i, slotCount: n)
        }
        let baseWidth = xOff + hPad
        let baseLeft = (outW - baseWidth) / 2

        // macOS-style cosine falloff around the cursor. Suspended while a
        // drag reorder is in progress so the drag math stays in base units.
        var scales = [Double](repeating: 1.0, count: n)
        if let hx = _dockHoverX, !_dockDragActive {
            let r = DesktopTheme.kDockMagnifyRadius
            let boost = DesktopTheme.kDockMagnifyMaxScale - 1.0
            for i in 0..<n {
                let d = abs(hx - (baseLeft + baseCenters[i]))
                if d < r {
                    scales[i] = 1.0 + boost * (0.5 + 0.5 * cos(.pi * d / r))
                }
            }
        }

        let slotWidths = zip(baseSizes, scales).map { $0 * $1 }
        var width = 2 * hPad + slotWidths.reduce(0, +)
        for i in 0..<n { width += _dockGapAfter(i, slotCount: n) }
        return DockMetrics(
            scales: scales, slotWidths: slotWidths,
            width: width, left: (outW - width) / 2,
            baseWidth: baseWidth, baseLeft: baseLeft,
            baseCenters: baseCenters)
    }

    /// Center of the dock icon that owns a window (direct appId match, or
    /// Chrome/VS Code by window title), in THIS tree's coordinates — the origin
    /// of the open zoom and the target of the minimize zoom.
    ///
    /// nil when the dock is on another monitor: the animation runs in the host
    /// tree, so there is no point on this panel to fly to. Callers already treat
    /// nil as "no zoom", which degrades to a plain open/minimize.
    /// The x of a dock icon's centre in the DOCK'S OWN output coordinates,
    /// which is what anchors the icon's context menu. Unlike `_dockIconCenter`
    /// this is not about the shell tree's panel, so it stays right when the
    /// dock is on another monitor.
    private func _dockIconAnchorX(appId: String) -> Double {
        let output = dockOutput
        guard let slot = chrome.barSlots(forOutput: output)
                .first(where: { $0.app == appId }) else {
            return output.logicalWidth / 2
        }
        return slot.x
    }

    private func _dockIconCenter(appId: String, title: String) -> Offset? {
        guard dockIsOnHost else { return nil }
        let owner = title.isEmpty ? nil : AppRegistry.shared.app(forTitle: title)?.id
        let idx = _dockDisplayApps.firstIndex { id in
            id == appId || id == owner
        }
        guard idx != nil else { return nil }
        // The ACTIVE style's slot, not the macOS dock's. This computed the
        // floating dock's geometry whatever style was up, so in the Windows
        // style a minimising window flew to a point on the wallpaper where
        // the dock would have been.
        guard let slot = chrome.barSlots(forOutput: dockOutput)
            .first(where: { $0.app == appId || $0.app == owner })
        else { return nil }
        return Offset(slot.x, slot.y)
    }

    /// The dock as it is on screen right now: every slot's app id and the
    /// center of its icon, in logical screen coordinates. Slot 0 is the
    /// launcher.
    ///
    /// Served over the broker so tooling can drive the real dock instead of
    /// mirroring its layout. A mirror cannot work here: the dock is
    /// centre-aligned and grows a transient icon for every running app, so
    /// launching anything shifts every icon left — which is exactly how
    /// `shell-drive.py` used to click 122px away from the launcher and report
    /// it as broken.
    ///
    /// Unmagnified geometry (`baseCenters`), which is what a caller needs: the
    /// pointer is not over the dock yet when it asks where to move.
    /// Reported in VIRTUAL-desktop coordinates — the dock lives on whichever
    /// output is primary, and a caller that clicks these has to aim at the
    /// right monitor. At N=1, and whenever the primary is the host, that
    /// output is at the origin and this is unchanged.
    func dockSlots() -> [(app: String, x: Double, y: Double, size: Double)] {
        let output = dockOutput
        // The active style answers for its own layout; this only moves the
        // answer from the output's coordinates into virtual-desktop ones,
        // because a caller that clicks these has to aim at the right monitor.
        return chrome.barSlots(forOutput: output).map {
            (app: $0.app,
             x: output.logicalLeft + $0.x,
             y: output.logicalTop + $0.y,
             size: $0.size)
        }
    }

    /// Global-hover hook: activates dock magnification while the cursor is
    /// over the dock strip and relaxes it once the cursor leaves. Horizontal
    /// slack is generous — at the far edges the falloff has already returned
    /// every icon to ~1x, so over-inclusion is invisible.
    ///
    /// `x`/`y` are local to the output the pointer is on, and `outputId` says
    /// which — the dock may be drawn by a `SecondaryOutputScreen`, whose
    /// pointer events never reach the host tree. Motion on an output that is
    /// not the dock's relaxes the magnification rather than being ignored:
    /// leaving the dock by walking onto the next monitor is a leave.
    func _updateDockHover(x: Double, y: Double, outputId: Int) {
        let output = dockOutput
        guard outputId == output.id else {
            if _dockHoverX != nil { setState { _dockHoverX = nil } }
            return
        }
        let pillTop = output.logicalHeight - DesktopTheme.kDockBottomMargin
            - DesktopTheme.kDockHeight
        let m = _dockMetrics(outputWidth: output.logicalWidth)
        let inside = y >= pillTop - 28
            && x >= m.baseLeft - 40 && x <= m.baseLeft + m.baseWidth + 40
        let newValue: Double? = inside ? x : nil
        switch (newValue, _dockHoverX) {
        case (nil, nil):
            return
        case let (a?, b?) where abs(a - b) < 0.5:
            return
        default:
            setState { _dockHoverX = newValue }
        }
    }

    /// Which app a window belongs to, or nil when nothing claims it.
    ///
    /// The authoritative signal is the window's own `app_id`
    /// (`xdg_toplevel.set_app_id`), matched against what the app's `.desktop`
    /// entry declares as its `StartupWMClass` — the pairing exists precisely
    /// so a desktop can tie a window back to an app, and app-install records
    /// it at install time.
    ///
    /// Title matching is the fallback, and only for the records that ask for
    /// it: the windows that genuinely carry no app_id (Zoom on the in-tree X
    /// server, WeChat inside rootful Xwayland, Waydroid's single window for
    /// every Android app). It is not a general fallback because it cannot be
    /// one — IntelliJ's project window is titled `untitled – Main.java`, with
    /// nothing app-shaped in it at all.
    /// The title to show for a window — the client's own, unless its record
    /// asks us to override it. One app needs that: WeChat's window is the
    /// entire rootful Xwayland screen and calls itself "Xwayland on :1", which
    /// is an implementation detail rather than a window name.
    static func _displayTitle(_ title: String, for win: WindowInfo? = nil) -> String {
        if let cls = win?.wmClass, let rec = AppRegistry.shared.app(forAppId: cls),
           rec.renameWindows {
            return rec.name
        }
        if let rec = AppRegistry.shared.app(forTitle: title), rec.renameWindows {
            return rec.name
        }
        return title
    }

    func _appOwning(_ win: WindowInfo) -> AppRecord? {
        if let rec = AppRegistry.shared.app(id: win.appId) { return rec }
        if let cls = win.wmClass, let rec = AppRegistry.shared.app(forAppId: cls) {
            return rec
        }
        return AppRegistry.shared.app(forTitle: win.title)
    }

    /// What the dock actually shows: the pinned apps, then any known app that
    /// is running — or mid-launch, so a Launchpad launch bounces a dock tile
    /// immediately — without being pinned (macOS-style transient icons).
    /// Transient icons vanish when the app quits; the right-click menu's
    /// "Keep in Dock" pins them.
    var _dockDisplayApps: [String] {
        let pinned = Set(dockAppOrder)
        return dockAppOrder + AppRegistry.shared.apps.map { $0.id }.filter { id in
            !pinned.contains(id)
                && (_pendingAppLaunches.contains(id) || _isAppRunning(id))
        }
    }

    /// True when the app has an open (possibly minimized) window — drives
    /// the macOS-style running-indicator dot under the dock icon.
    /// Agent-owned windows have no desktop presence and never light dots.
    private func _isAppRunning(_ appId: String) -> Bool {
        windowManager.windows.contains { win in
            win.ownerAgentId == nil && _appOwning(win)?.id == appId
        }
    }

    /// Recompute app liveness and publish it if it changed.
    ///
    /// Window presence comes from `_isAppRunning`, so the dock and the
    /// published status are the same derivation rather than two that can
    /// disagree. Process liveness comes from the registry's /proc scan — the
    /// shell does it, not the App Store, because the shell is the component
    /// that owns app status.
    ///
    /// Called on every window-list change (free, event-driven) and, while
    /// something is subscribed, on the broker's tick — a process exiting
    /// without closing a window produces no event of its own.
    func _refreshAppLiveness() {
        #if os(Linux)
        let processes = AppRegistry.shared.runningAppIds()
        var next: [String: AppLiveness] = [:]
        for app in AppRegistry.shared.apps where app.installed {
            let live = AppLiveness(window: _isAppRunning(app.id),
                                   process: processes.contains(app.id))
            if live.window || live.process { next[app.id] = live }
        }
        guard next != appLiveness else { return }
        appLiveness = next
        _agentBroker?.pushAppStatus(next)
        #endif
    }

    /// Loads the compiled liquid-glass program once. Returns nil if the
    /// .iplr asset can't be found or fails to initialize — callers fall
    /// back to the plain blur+saturate filter.
    private func _glassProgramIfAvailable() -> FragmentProgram? {
        if _glassProgramTried { return _glassProgram }
        _glassProgramTried = true
        var candidates = [
            // Resolved relative to whichever CWD the shell was launched from.
            "Sources/DesktopShellApp/Shaders/liquid_glass.frag.iplr",
            "apps/DesktopShellApp/Sources/DesktopShellApp/Shaders/liquid_glass.frag.iplr",
        ]
        // Installed layout ($STARLING_DATA_DIR / <exe>/../share/starling).
        if let packaged = Self.dataFilePath("shaders/liquid_glass.frag.iplr") {
            candidates.insert(packaged, at: 0)
        }
        for path in candidates {
            guard let data = FileManager.default.contents(atPath: path) else { continue }
            do {
                _glassProgram = try FragmentProgram(
                    data: [UInt8](data), backend: .skSL)
                FileHandle.standardError.write(Data(
                    "[DesktopShell] Liquid-glass shader loaded from \(path)\n".utf8))
                return _glassProgram
            } catch {
                FileHandle.standardError.write(Data(
                    "[DesktopShell] Liquid-glass shader load failed: \(error)\n".utf8))
            }
        }
        FileHandle.standardError.write(Data(
            "[DesktopShell] Liquid-glass shader .iplr not found — using plain blur\n".utf8))
        return nil
    }

    private func _dockGlassShaderIfAvailable() -> FragmentShader? {
        if _dockGlassShader == nil {
            _dockGlassShader = _glassProgramIfAvailable()?.fragmentShader()
        }
        return _dockGlassShader
    }

    private func _popupGlassShaderIfAvailable() -> FragmentShader? {
        if _popupGlassShader == nil {
            _popupGlassShader = _glassProgramIfAvailable()?.fragmentShader()
        }
        return _popupGlassShader
    }

    /// Builds a liquid-glass BackdropFilter: blur → saturation boost → (if a
    /// shader instance is supplied) refraction. The shader is the outermost
    /// pass so it warps the already blurred+saturated backdrop.
    private func _liquidGlassFilter(shader: FragmentShader?,
                                    left: Double, top: Double,
                                    width: Double, height: Double,
                                    cornerRadius: Double,
                                    blurSigma: Double,
                                    saturation: Double) -> any ImageFilter {
        let base = ImageFilterFactory.compose(
            outer: ColorFilter(matrix: _saturationMatrix(saturation)),
            inner: ImageFilterFactory.blur(sigmaX: blurSigma, sigmaY: blurSigma)
        )
        guard let shader else { return base }
        // FlutterFragCoord() in the runtime-effect image filter is in
        // full-screen *logical* coordinates — pass the panel's logical
        // origin and size so the shader normalizes to a 0..1 panel uv.
        shader.setFloat(0, width)                           // uSize.x
        shader.setFloat(1, height)                          // uSize.y
        shader.setFloat(2, left)                            // uOrigin.x
        shader.setFloat(3, top)                             // uOrigin.y
        shader.setFloat(4, cornerRadius)                    // uCornerRadius
        // Flutter compiles `sampler2D uTexture` to a child shader plus an
        // auto uniform `uTexture_size`; `texture(uTexture, X)` becomes
        // `uTexture.eval(uTexture_size * X)`. For an image-filter input
        // there is no setImageSampler call to populate that size, so set
        // it to (1,1) directly (indices 5,6, just past the 5 declared
        // float uniforms) — then texture() samples in raw coord space.
        shader.setFloat(5, 1.0)                             // uTexture_size.x
        shader.setFloat(6, 1.0)                             // uTexture_size.y
        return ImageFilterFactory.compose(
            outer: ImageFilterFactory.shader(shader),
            inner: base
        )
    }

    /// Loads the compiled screensaver warp program once. Returns nil if the
    /// .iplr asset can't be found or fails to initialize — the screensaver
    /// falls back to the plain breathing blur + scrim.
    private func _screensaverProgramIfAvailable() -> FragmentProgram? {
        if _screensaverProgramTried { return _screensaverProgram }
        _screensaverProgramTried = true
        var candidates = [
            // Resolved relative to whichever CWD the shell was launched from.
            "Sources/DesktopShellApp/Shaders/screensaver.frag.iplr",
            "apps/DesktopShellApp/Sources/DesktopShellApp/Shaders/screensaver.frag.iplr",
        ]
        // Installed layout ($STARLING_DATA_DIR / <exe>/../share/starling).
        if let packaged = Self.dataFilePath("shaders/screensaver.frag.iplr") {
            candidates.insert(packaged, at: 0)
        }
        for path in candidates {
            guard let data = FileManager.default.contents(atPath: path) else { continue }
            do {
                _screensaverProgram = try FragmentProgram(
                    data: [UInt8](data), backend: .skSL)
                FileHandle.standardError.write(Data(
                    "[DesktopShell] Screensaver shader loaded from \(path)\n".utf8))
                return _screensaverProgram
            } catch {
                FileHandle.standardError.write(Data(
                    "[DesktopShell] Screensaver shader load failed: \(error)\n".utf8))
            }
        }
        FileHandle.standardError.write(Data(
            "[DesktopShell] Screensaver shader .iplr not found — using plain blur\n".utf8))
        return nil
    }

    private func _screensaverShaderIfAvailable() -> FragmentShader? {
        if _screensaverShader == nil {
            _screensaverShader = _screensaverProgramIfAvailable()?.fragmentShader()
        }
        return _screensaverShader
    }

    /// Screensaver backdrop: breathing blur, with the liquid warp composed
    /// outside it when the shader is available. `fadeT` scales everything —
    /// an ancestor Opacity cannot attenuate what a BackdropFilter does to
    /// its backdrop, so the fade has to be parametric.
    private func _screensaverFilter(fadeT: Double) -> any ImageFilter {
        // ±22% around the base sigma, one breath every 9 s.
        let breathe = 1.0 + 0.22 * sin(_screensaverTime * 2.0 * .pi / 9.0)
        let sigma = 22.0 * breathe * fadeT
        let base = ImageFilterFactory.blur(sigmaX: sigma, sigmaY: sigma)
        guard let shader = _screensaverShaderIfAvailable() else { return base }
        shader.setFloat(0, screenWidth)                     // uSize.x
        shader.setFloat(1, screenHeight)                    // uSize.y
        shader.setFloat(2, _screensaverTime)                // uTime
        shader.setFloat(3, fadeT)                           // uIntensity
        // Auto uTexture_size just past the declared floats — (1,1) so
        // texture() samples raw coords (see _liquidGlassFilter above).
        shader.setFloat(4, 1.0)                             // uTexture_size.x
        shader.setFloat(5, 1.0)                             // uTexture_size.y
        return ImageFilterFactory.compose(
            outer: ImageFilterFactory.shader(shader),
            inner: base
        )
    }

    private func _dockGlassFilter(dockWidth: Double, dockLeft: Double,
                                  dockTop: Double) -> any ImageFilter {
        return _liquidGlassFilter(
            shader: _dockGlassShaderIfAvailable(),
            left: dockLeft, top: dockTop,
            width: dockWidth, height: DesktopTheme.kDockHeight,
            cornerRadius: DesktopTheme.kDockCornerRadius,
            blurSigma: 3.5, saturation: 1.12)
    }

    private func _buildDock(appIds: [String], metrics: DockMetrics,
                            dockTop: Double) -> Widget {
        var iconWidgets: [Widget] = []
        let targetIdx = _dockDragActive ? _dockDragTargetIndex() : -1
        let animDuration: Duration = .milliseconds(150)

        // Slot 0: launcher, followed by the wider divider gap.
        iconWidgets.append(_buildLauncherIcon(slotWidth: metrics.slotWidths[0]))
        iconWidgets.append(SizedBox(width: DesktopTheme.kDockIconPadding * 2))

        for (i, appId) in appIds.enumerated() {
            let iconType = _iconType(for: appId)
            if i > 0 {
                iconWidgets.append(SizedBox(width: DesktopTheme.kDockIconPadding))
            }

            let isDragged = _dockDragActive && _dockDragIndex == i

            // Insert gap BEFORE this slot if target is here and dragged icon is after
            if _dockDragActive, let fromIdx = _dockDragIndex, targetIdx == i, fromIdx > i {
                iconWidgets.append(AnimatedContainer(
                    width: DesktopTheme.kDockIconSize, height: DesktopTheme.kDockIconSize,
                    duration: animDuration
                ))
                iconWidgets.append(SizedBox(width: DesktopTheme.kDockIconPadding))
            }

            // Dragged icon's slot collapses to zero width
            if isDragged {
                iconWidgets.append(AnimatedContainer(
                    width: 0, height: DesktopTheme.kDockIconSize,
                    duration: animDuration, clipBehavior: .hardEdge
                ))
            } else {
                iconWidgets.append(
                    _buildDockIcon(appId: appId, iconType: iconType, index: i,
                                   slotWidth: metrics.slotWidths[i + 1])
                )
            }

            // Insert gap AFTER this slot if target is here and dragged icon is before
            if _dockDragActive, let fromIdx = _dockDragIndex, targetIdx == i, fromIdx < i {
                iconWidgets.append(SizedBox(width: DesktopTheme.kDockIconPadding))
                iconWidgets.append(AnimatedContainer(
                    width: DesktopTheme.kDockIconSize, height: DesktopTheme.kDockIconSize,
                    duration: animDuration
                ))
            }
        }

        // Liquid-glass pill: backdrop blur + saturation boost (the signature
        // Apple trick to keep blurred backgrounds vivid), then a vertical
        // white gradient on top — brighter at the top edge to simulate light
        // catching the glass. Outer DecoratedBox carries the drop shadow
        // (outside the clip), inner DecoratedBox carries tint + border. This
        // path was previously blocked by the Skia stencil null-deref under
        // DMA-BUF compositing — see patches/skia-stencil-nullcheck.patch.
        // The pill is its own layer now: icons live above it in the Stack so
        // magnified icons can grow past its top edge without being clipped.
        let pill: Widget = DecoratedBox(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius(circular: DesktopTheme.kDockCornerRadius)),
                boxShadow: [
                    BoxShadow(color: shellTheme.dockShadow, offset: Offset(0, 6), blurRadius: 24),
                ]
            ),
            child: ClipRRect(
                borderRadius: BorderRadius.all(Radius(circular: DesktopTheme.kDockCornerRadius)),
                child: BackdropFilter(
                    filter: _dockGlassFilter(dockWidth: metrics.width,
                                             dockLeft: metrics.left,
                                             dockTop: dockTop),
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            // Single thin crisp hairline — the only
                            // thing defining the panel against a dark
                            // backdrop, exactly as the macOS dock does.
                            border: Border.all(
                                color: shellTheme.dockRim,
                                width: 1.0
                            ),
                            borderRadius: BorderRadius.all(Radius(circular: DesktopTheme.kDockCornerRadius)),
                            // Faint frost tint; kept low in the dark theme
                            // so over black the body stays near-black like
                            // macOS, defined by the hairline, not a fill.
                            gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [shellTheme.dockGradientTop, shellTheme.dockGradientBottom]
                            )
                        ),
                        child: SizedBox(expand: ())
                    )
                )
            )
        )

        var layers: [Widget] = [
            Positioned(
                left: 0, right: 0, bottom: 0,
                height: DesktopTheme.kDockHeight,
                child: pill
            ),
            // Icon row: bottom-anchored so magnified icons grow upward from
            // a shared baseline, overflowing the pill's top edge like macOS.
            Positioned(
                left: DesktopTheme.kDockHorizontalPadding,
                bottom: 0,
                child: Row(
                    mainAxisAlignment: .start,
                    crossAxisAlignment: .end,
                    children: iconWidgets
                )
            ),
        ]
        if let label = _buildDockHoverLabel(metrics: metrics) {
            layers.append(label)
        }

        // Wrap entire dock in Listener for drag move/up
        return Listener(
            onPointerMove: { [self] event in
                guard _dockDragIndex != nil else { return }
                if !_dockDragActive {
                    let dx = abs(event.position.dx - _dockDragStartX)
                    if dx > 5 { _dockDragActive = true }
                }
                if _dockDragActive {
                    setState {
                        _dockDragCurrentX = event.position.dx
                        _dockDragCurrentY = event.position.dy
                    }
                }
            },
            onPointerUp: { [self] _ in
                if _dockDragActive, let fromIndex = _dockDragIndex {
                    let targetIndex = _dockDragTargetIndex()
                    setState {
                        if fromIndex != targetIndex {
                            let item = dockAppOrder.remove(at: fromIndex)
                            dockAppOrder.insert(item, at: targetIndex)
                        }
                        _dockDragIndex = nil
                        _dockDragActive = false
                    }
                } else if _dockDragIndex != nil {
                    _dockDragIndex = nil
                    _dockDragActive = false
                }
            },
            behavior: .translucent,
            child: Stack(clipBehavior: .none, children: layers)
        )
    }

    /// macOS-style app-name bubble floating above the hovered dock icon.
    /// Uses *current* (magnified) geometry so it tracks the on-screen icon.
    private func _buildDockHoverLabel(metrics: DockMetrics) -> Widget? {
        guard let hx = _dockHoverX, !_dockDragActive else { return nil }
        let localX = hx - metrics.left
        let n = metrics.slotWidths.count

        var hoveredIdx: Int? = nil
        var hoveredCenter: Double = 0
        var x = DesktopTheme.kDockHorizontalPadding
        for (i, w) in metrics.slotWidths.enumerated() {
            let gapBefore = i == 0 ? 0 : _dockGapAfter(i - 1, slotCount: n)
            let gapAfter = _dockGapAfter(i, slotCount: n)
            if localX >= x - gapBefore / 2 && localX < x + w + gapAfter / 2 {
                hoveredIdx = i
                hoveredCenter = x + w / 2
                break
            }
            x += w + gapAfter
        }
        guard let idx = hoveredIdx else { return nil }
        let label = idx == 0 ? "Apps" : _dockAppLabel(for: _dockDisplayApps[idx - 1])

        let bubble: Widget = DecoratedBox(
            decoration: BoxDecoration(
                color: shellTheme.dockLabelTint,
                border: Border.all(color: shellTheme.dockLabelBorder, width: 0.5),
                borderRadius: BorderRadius.all(Radius(circular: 7)),
                boxShadow: [
                    BoxShadow(color: shellTheme.dockShadow, offset: Offset(0, 3), blurRadius: 10),
                ]
            ),
            child: Padding(
                padding: EdgeInsets(left: 11, top: 5, right: 11, bottom: 5),
                child: Text(
                    label,
                    style: TextStyle(
                        color: shellTheme.dockLabelText,
                        fontSize: 13,
                        fontWeight: .w500, fontFamily: shellTheme.fontFamily)
                )
            )
        )
        // A wide strip centered on the icon; the bubble shrink-wraps inside
        // a Center so the text never needs explicit measuring.
        return Positioned(
            left: hoveredCenter - 150,
            bottom: DesktopTheme.kDockLabelBottom,
            width: 300,
            height: 30,
            child: IgnorePointer(child: Center(child: bubble))
        )
    }

    /// Standard "saturate(s)" color matrix in row-major 4x5 form, where the
    /// luminance coefficients are sRGB (Rec. 709): 0.213 / 0.715 / 0.072.
    /// s = 1.0 → identity; s = 1.8 → ~Apple "Liquid Glass" vibrancy boost.
    private func _saturationMatrix(_ s: Double) -> [Double] {
        let lr = 0.213, lg = 0.715, lb = 0.072
        return [
            lr + (1 - lr) * s,  lg - lg * s,        lb - lb * s,        0, 0,
            lr - lr * s,        lg + (1 - lg) * s,  lb - lb * s,        0, 0,
            lr - lr * s,        lg - lg * s,        lb + (1 - lb) * s,  0, 0,
            0,                  0,                  0,                  1, 0,
        ]
    }

    /// Large "Mon, May 17" date label above the search pill.
    private func _buildDesktopDateLabel() -> Widget {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return Text(
            f.string(from: Date()),
            style: TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 16,
                fontWeight: .w500, fontFamily: shellTheme.fontFamily)
        )
    }

    /// Floating Google-style search pill — non-functional placeholder for now.
    private func _buildSearchPill() -> Widget {
        let leadingIcon: Widget = SizedBox(
            width: 22, height: 22,
            child: Center(
                child: Text(
                    "G",
                    style: TextStyle(
                        color: Color(0xFF8AB4F8),
                        fontSize: 16,
                        fontWeight: .w700, fontFamily: shellTheme.fontFamilyStrong)
                )
            )
        )
        return DecoratedBox(
            decoration: BoxDecoration(
                color: DesktopTheme.searchPillBackground,
                border: Border.all(color: DesktopTheme.searchPillBorder, width: 0.5),
                borderRadius: BorderRadius.all(Radius(circular: DesktopTheme.kSearchPillHeight / 2)),
                boxShadow: [
                    BoxShadow(color: Color(0x40000000), offset: Offset(0, 2), blurRadius: 12),
                ]
            ),
            child: Padding(
                padding: EdgeInsets(left: 16, top: 0, right: 16, bottom: 0),
                child: Row(
                    mainAxisAlignment: .start,
                    crossAxisAlignment: .center,
                    children: [
                        leadingIcon,
                        SizedBox(width: 12),
                        Text(
                            "Search the web",
                            style: TextStyle(
                                color: Color(0xFFB0B0B0),
                                fontSize: 14,
                                fontWeight: .w400, fontFamily: shellTheme.fontFamily)
                        ),
                    ]
                )
            )
        )
    }

    /// 3×3 dot grid "launcher" icon at the left of the dock (Chrome OS style).
    /// `slotWidth` is the magnified slot size; the glyph scales with it.
    private func _buildLauncherIcon(slotWidth: Double) -> Widget {
        // The launcher shares the app icons' slot geometry and tile treatment
        // (see _buildDockIcon / _buildDockIconContent) so it lines up with the
        // rest of the dock: a rounded, shadowed tile with a white glyph — here
        // a 3x3 dot grid instead of an IconPainter shape.
        let scale = slotWidth / DesktopTheme.kDockIconSize
        let cornerRadius = DesktopTheme.kDockIconCornerRadius * scale

        let dot: Widget = SizedBox(
            width: 5, height: 5,
            child: ClipRRect(
                borderRadius: BorderRadius.all(Radius(circular: 2.5)),
                child: ColoredBox(color: Color(0xFFFFFFFF), child: SizedBox(expand: ()))
            )
        )
        func row() -> Widget {
            return Row(mainAxisAlignment: .spaceBetween, children: [dot, dot, dot])
        }
        let grid: Widget = SizedBox(
            width: 24, height: 24,
            child: Column(mainAxisAlignment: .spaceBetween, children: [row(), row(), row()])
        )

        let tile: Widget = DecoratedBox(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius(circular: cornerRadius)),
                boxShadow: [
                    BoxShadow(color: Color(0x4D000000),
                              offset: Offset(0, 3 * scale), blurRadius: 8 * scale),
                ]
            ),
            child: ClipRRect(
                borderRadius: BorderRadius.all(Radius(circular: cornerRadius)),
                child: ColoredBox(
                    color: Color(0xFF5A5A5F),  // neutral graphite — a "system" tile
                    child: Center(child: grid)
                )
            )
        )

        return SizedBox(
            width: slotWidth,
            height: slotWidth + DesktopTheme.kDockIconBottomInset,
            child: Column(
                crossAxisAlignment: .stretch,
                children: [
                    Expanded(
                        child: GestureDetector(
                            onTap: { [self] in
                                // Pick up icons for anything installed since
                                // login before the grid is built.
                                _loadIconTextures()
                                openLauncher()
                            },
                            behavior: .opaque,
                            child: tile
                        )
                    ),
                    SizedBox(height: DesktopTheme.kDockIconBottomInset),
                ]
            )
        )
    }

    /// Build just the visual icon content (used for both dock slot and floating drag).
    /// The corner radius scales with magnification so the tile shape stays
    /// proportional (pass the default for unmagnified uses like drag ghosts).
    private func _buildDockIconContent(
        appId: String, iconType: IconType,
        cornerRadius: Double = DesktopTheme.kDockIconCornerRadius
    ) -> Widget {
        let iconBg = _dockIconColor(for: appId)
        let iconContent: Widget
        if let texId = iconTextures[appId] {
            iconContent = TextureWidget(textureId: Int(texId), filterQuality: .medium)
        } else {
            iconContent = DecoratedBox(
                decoration: BoxDecoration(gradient: ShellPalette.tileGradient(iconBg)),
                child: Center(
                    child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CustomPaint(
                            painter: IconPainter(iconType, color: Color(0xFFFFFFFF))
                        )
                    )
                )
            )
        }
        // macOS-style depth: every icon tile casts a soft shadow down onto
        // the dock glass. The shadow tracks the tile's rounded rect and
        // scales with magnification (cornerRadius already carries the slot
        // scale), so magnified icons throw proportionally deeper shadows.
        let shadowScale = cornerRadius / DesktopTheme.kDockIconCornerRadius
        return DecoratedBox(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius(circular: cornerRadius)),
                boxShadow: [
                    BoxShadow(color: Color(0x4D000000),
                              offset: Offset(0, 3 * shadowScale),
                              blurRadius: 8 * shadowScale),
                ]
            ),
            child: ClipRRect(
                borderRadius: BorderRadius.all(Radius(circular: cornerRadius)),
                child: iconContent
            )
        )
    }

    private func _buildDockIcon(appId: String, iconType: IconType, index: Int,
                                slotWidth: Double) -> Widget {
        let scale = slotWidth / DesktopTheme.kDockIconSize
        let iconContent = _buildDockIconContent(
            appId: appId, iconType: iconType,
            cornerRadius: DesktopTheme.kDockIconCornerRadius * scale)

        // Pointer down on icon records which icon is being dragged;
        // move/up handled by dock-level Listener (wide area, keeps getting events)
        let interactive: Widget = Listener(
            onPointerDown: { [self] event in
                if event.buttons & kSecondaryButton != 0 {
                    // Right-click opens the icon's menu instead of arming a
                    // drag (macOS: menus appear on right-mouse-down).
                    setState {
                        _dockDragIndex = nil
                        _dockDragActive = false
                        contextMenuPosition = nil
                        activeStatusBarPopup = nil
                        _dockMenuAppId = appId
                        _dockMenuAnchorX = _dockIconAnchorX(appId: appId)
                    }
                    return
                }
                if let origIndex = dockAppOrder.firstIndex(of: appId) {
                    _dockDragIndex = origIndex
                    _dockDragStartX = event.position.dx
                    _dockDragCurrentX = event.position.dx
                    _dockDragCurrentY = event.position.dy
                    _dockDragActive = false
                }
            },
            behavior: .translucent,
            child: GestureDetector(
                onTap: { [self] in
                    setState {
                        _dockDragIndex = nil
                        _dockDragActive = false
                        contextMenuPosition = nil
                        _launchOrFocusApp(appId)
                    }
                },
                behavior: .opaque,
                child: iconContent
            )
        )

        // macOS-style running-indicator dot in the strip below the icon.
        // White core with a hairline dark rim + shadow so it reads on both
        // dark wallpapers and light window content behind the glass pill.
        let indicator: Widget
        if _isAppRunning(appId) {
            indicator = SizedBox(
                width: DesktopTheme.kDockIndicatorSize,
                height: DesktopTheme.kDockIndicatorSize,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: shellTheme.dockIndicator,
                        border: Border.all(color: shellTheme.dockIndicatorRim, width: 0.5),
                        borderRadius: BorderRadius.all(
                            Radius(circular: DesktopTheme.kDockIndicatorSize / 2)),
                        boxShadow: [
                            BoxShadow(color: Color(0x59000000),
                                      offset: Offset(0, 0.5), blurRadius: 1.5),
                        ]
                    )
                )
            )
        } else {
            indicator = SizedBox(width: 0, height: 0)
        }

        // The slot is bottom-anchored in the dock's icon row: the icon grows
        // upward with magnification while the dot strip keeps it seated
        // kDockIconBottomInset above the pill's bottom edge.
        return SizedBox(
            width: slotWidth,
            height: slotWidth + DesktopTheme.kDockIconBottomInset,
            child: Column(
                crossAxisAlignment: .stretch,
                children: [
                    // Bounce the tile while its app is launching (macOS-style
                    // feedback for the spawn-to-first-frame wait).
                    Expanded(child: DockBounce(
                        active: _pendingAppLaunches.contains(appId),
                        child: interactive
                    )),
                    SizedBox(
                        height: DesktopTheme.kDockIconBottomInset,
                        child: Center(child: indicator)
                    ),
                ]
            )
        )
    }

    // MARK: - Dismiss Barrier

    private func _appendDismissBarrier(_ children: inout [Widget], dismiss: @escaping () -> Void) {
        children.append(
            Positioned(
                fill: (),
                child: Listener(
                    onPointerDown: { [self] _ in
                        setState {
                            dismiss()
                        }
                    },
                    behavior: .opaque,
                    child: ColoredBox(
                        color: Color(0x00000000),
                        child: SizedBox(expand: ())
                    )
                )
            )
        )
    }

    // MARK: - Context Menu

    /// The shell's context menus, in the macOS shape.
    ///
    /// Brightness and accent follow the shell theme so a menu matches the rest
    /// of the chrome. The panel fill is deliberately NOT `shellTheme.popupTint`
    /// — that colour is a 35%-alpha tint meant to be layered over the
    /// liquid-glass refraction the status-bar popovers sit on, and a context
    /// menu opens straight over whatever happens to be on the desktop, where
    /// it would be unreadable. MacosMenu's own near-opaque slab is both legible
    /// and closer to AppKit, which keeps menus opaque precisely because they
    /// appear over unknown content.
    /// A shell menu, in the active style's colours.
    ///
    /// The accent comes from the THEME, not from `DesktopTheme.accent` — that
    /// constant is the macOS blue and is fixed, so a highlighted row went on
    /// being iOS blue in a desktop whose every other highlight had changed.
    private func _macosMenu(_ items: [MacosMenuEntry]) -> Widget {
        return MacosMenu(
            items: items,
            brightness: shellTheme.isDark ? .dark : .light,
            accentColor: shellTheme.accent,
            backgroundColor: shellTheme.panelFill
        )
    }

    private func _buildContextMenu() -> Widget {
        var items: [MacosMenuEntry] = [
            MacosMenuItem(
                text: "Change Wallpaper",
                onPressed: { [self] in
                    setState {
                        wallpaperPreset = wallpaperPreset.next
                        _syncSharedWallpaper()
                        contextMenuPosition = nil
                    }
                }
            ),
            MacosMenuItem(
                text: shellTheme.isDark ? "Light Appearance" : "Dark Appearance",
                onPressed: { [self] in
                    setState { contextMenuPosition = nil }
                    _setAppearance(dark: !shellTheme.isDark)
                }
            ),
            MacosMenuSeparator(),
        ]
        // One row per style, driven off the registry rather than a list here —
        // adding a style should not mean remembering to edit this menu.
        for style in ShellStyles.all {
            items.append(MacosMenuItem(
                text: "\(style.name) Style",
                onPressed: { [self] in
                    setState { contextMenuPosition = nil }
                    _setStyle(style.id)
                },
                isSelected: style.id == shellStyle.id
            ))
        }
        items.append(contentsOf: [
            MacosMenuSeparator(),
            // Spaces. New desktops append at the end of the strip; removal
            // rehomes the desktop's windows to the nearest user space.
            MacosMenuItem(
                text: "Mission Control",
                onPressed: { [self] in
                    setState { contextMenuPosition = nil }
                    _openMissionControl()
                }
            ),
            MacosMenuItem(
                text: "New Desktop",
                onPressed: { [self] in
                    setState { contextMenuPosition = nil }
                    let idx = windowManager.addSpace()
                    // The menu can be on any monitor now — the new desktop
                    // opens on the one it was invoked from.
                    _switchToSpace(idx, onOutput: contextMenuOutputId)
                }
            ),
            MacosMenuItem(
                text: "Workspace",
                onPressed: { [self] in
                    setState { contextMenuPosition = nil }
                    if !windowManager.activeSpace.isWorkspace { _toggleWorkspaceSpace() }
                }
            ),
        ])
        let active = windowManager.activeSpace
        if active.isUser && windowManager.spaces.filter({ $0.isUser }).count > 1 {
            items.append(MacosMenuItem(
                text: "Remove This Desktop",
                onPressed: { [self] in
                    setState {
                        contextMenuPosition = nil
                        windowManager.removeSpace(at: windowManager.activeSpaceIndex)
                    }
                }
            ))
        }
        items.append(contentsOf: [
            MacosMenuSeparator(),
                MacosMenuItem(
                    text: "Display Settings",
                    onPressed: { [self] in
                        setState {
                            contextMenuPosition = nil
                            _launchOrFocusApp("settings")
                        }
                    }
                ),
                MacosMenuItem(
                    text: "Open Text Viewer",
                    onPressed: { [self] in
                        setState {
                            contextMenuPosition = nil
                            _launchOrFocusApp("textviewer")
                        }
                    }
                ),
        ])
        return _macosMenu(items)
    }

    /// Dock icon right-click menu: Show/Open, Quit (when running), and
    /// Remove from Dock (macOS style).
    private func _buildDockIconMenu(for appId: String) -> Widget {
        let running = _isAppRunning(appId)
        var items: [MacosMenuEntry] = [
            MacosMenuItem(
                text: running ? "Show" : "Open",
                onPressed: { [self] in
                    setState {
                        _dockMenuAppId = nil
                        _launchOrFocusApp(appId)
                    }
                }
            ),
        ]
        if running {
            items.append(MacosMenuItem(
                text: "Quit",
                onPressed: { [self] in
                    setState { _dockMenuAppId = nil }
                    _quitApp(appId)
                }
            ))
        }
        items.append(MacosMenuSeparator())
        if dockAppOrder.contains(appId) {
            items.append(MacosMenuItem(
                text: "Remove from Dock",
                onPressed: { [self] in
                    setState {
                        _dockMenuAppId = nil
                        dockAppOrder.removeAll { $0 == appId }
                        _dockRemovedByUser.insert(appId)
                    }
                }
            ))
        } else {
            // Transient icon (running but unpinned) — offer to pin it.
            items.append(MacosMenuItem(
                text: "Keep in Dock",
                onPressed: { [self] in
                    setState {
                        _dockMenuAppId = nil
                        if AppRegistry.shared.app(id: appId) != nil {
                            dockAppOrder.append(appId)
                            _dockRemovedByUser.remove(appId)
                        }
                    }
                }
            ))
        }
        return _macosMenu(items)
    }

    /// Quit a running app from its dock menu: tear down every desktop window
    /// it owns. Windows visible on the active space play the shrink-out first
    /// (teardown fires when the animation completes); minimized, other-space,
    /// or exposé-covered windows have no animatable widget, so they are torn
    /// down immediately. onWindowClose terminates process-backed apps.
    private func _quitApp(_ appId: String) {
        let targets = windowManager.windows.filter { win in
            win.ownerAgentId == nil && _appOwning(win)?.id == appId
        }
        guard !targets.isEmpty else { return }

        // Client pids, collected BEFORE teardown — closing the windows drops
        // the records these are resolved from, and a third-party app that
        // ignores the close request would otherwise be unreachable.
        var pids = Set<pid_t>()
        for win in targets {
            if let pid = _clientPid(of: win) { pids.insert(pid) }
        }

        let activeSpaceId = windowManager.activeSpace.id
        setState {
            for win in targets {
                if !_missionControlOpen && !win.isMinimized
                    && win.spaceId == activeSpaceId {
                    _closingWindows.insert(win.id)
                } else {
                    if win.textureId != nil { win.onWindowClose?() }
                    win.onWindowClose = nil
                    windowManager.closeWindow(win.id)
                }
            }
        }
        if !pids.isEmpty { _reapAfterQuit(pids) }
    }

    /// pid behind a third-party window, from the peer credentials its server
    /// captured when the window appeared. nil for first-party and agent
    /// windows, which are torn down through their own managers.
    private func _clientPid(of win: WindowInfo) -> pid_t? {
        #if os(Linux)
        if win.appId.hasPrefix("wayland-"),
           let sid = UInt32(win.appId.dropFirst("wayland-".count)) {
            return waylandIntegration?.clientPid(surfaceId: sid)
        }
        if win.appId.hasPrefix("x11-"),
           let wid = UInt32(win.appId.dropFirst("x11-".count)) {
            return x11Integration?.clientPid(windowId: wid)
        }
        #endif
        return nil
    }

    /// Make Quit mean it. The close request _quitApp just sent is advisory —
    /// a client is free to ignore it, and Zoom's window vanishing tells you
    /// nothing about its eleven processes — so give the app a grace period to
    /// leave on its own, then signal, then insist.
    ///
    /// Signals go to the process GROUP: an app is a tree, and its helpers do
    /// not exit just because the process holding the display connection did.
    /// _spawnLauncher setsid's every app so that group is the app's alone.
    private func _reapAfterQuit(_ pids: Set<pid_t>) {
        #if os(Linux)
        let ownGroup = getpgrp()
        func signalAll(_ sig: Int32) {
            for pid in pids {
                guard pid > 1, kill(pid, 0) == 0 else { continue }  // already gone
                let pgid = getpgid(pid)
                // Never signal our own group — that is the desktop. An app
                // launched before the setsid fix (or by something that did not
                // detach) still shares it; quit that one by pid alone.
                if pgid > 1 && pgid != ownGroup {
                    kill(-pgid, sig)
                } else {
                    kill(pid, sig)
                }
            }
        }
        // 2s to quit gracefully, 3s more to honour SIGTERM, then SIGKILL.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            signalAll(SIGTERM)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                signalAll(SIGKILL)
            }
        }
        #endif
    }

    // MARK: - IME

    /// Child app reported its text caret (via the DMA-BUF socket). Stored
    /// always; only rebuilds when the panel is showing.
    func _imeCaretChanged(textureId: Int64, x: Double, y: Double,
                          width: Double, height: Double, visible: Bool) {
        _imeCaret = (textureId, Rect.fromLTWH(x, y, width, height), visible)
        // Keep fcitx informed of the screen-space caret (SetCursorRect) —
        // decorative while it runs headless, but plugins expect it.
        if visible, _imeEnabled, let ime = imeIntegration,
           let focusedId = windowManager.focusedWindowId,
           let win = windowManager.windows.first(where: { $0.id == focusedId }),
           processTextureIds[win.appId] == textureId {
            ime.setCursorRect(
                x: win.rect.left + x,
                y: win.rect.top + DesktopTheme.kTitleBarHeight + y,
                width: width, height: height)
        }
        if _imeEnabled && (!_imePreedit.isEmpty || !_imeCandidates.isEmpty) {
            setState {}
        }
    }

    /// Ctrl+Space: toggle fcitx5 input (lazy bridge creation — fcitx may
    /// not be installed; the bridge retries its connection quietly).
    private func _toggleIme() {
        #if os(Linux)
        if imeIntegration == nil {
            let ime = ImeIntegration()
            ime.onCommit = { [weak self] text in
                self?._imeDeliverCommit(text)
            }
            ime.onPanelChanged = { [weak self] preedit, candidates, highlighted in
                guard let self else { return }
                // Mirror the composition into a focused Wayland client's
                // text field (in-field preedit, like native IME frontends).
                if let focusedId = self.windowManager.focusedWindowId,
                   let win = self.windowManager.windows.first(where: { $0.id == focusedId }),
                   win.appId.hasPrefix("wayland-") {
                    waylandIntegration?.sendTextInputPreedit(
                        preedit, cursor: Int32(preedit.utf8.count))
                }
                self.setState {
                    self._imePreedit = preedit
                    self._imeCandidates = candidates
                    self._imeHighlighted = highlighted
                }
            }
            ime.onReplayKey = { [weak self] keyData in
                self?._imeReplayKey(keyData)
            }
            imeIntegration = ime
        }
        setState {
            _imeEnabled.toggle()
            _imePreedit = ""
            _imeCandidates = []
            _imeHighlighted = -1
        }
        if _imeEnabled {
            imeIntegration?.focusIn()
        } else {
            imeIntegration?.focusOut()
        }
        #endif
    }

    /// Deliver a key fcitx declined (async verdict) to the focused app —
    /// the down was swallowed optimistically, so send a full down+up now.
    private func _imeReplayKey(_ keyData: KeyData) {
        #if os(Linux)
        guard let focusedId = windowManager.focusedWindowId,
              let win = windowManager.windows.first(where: { $0.id == focusedId })
        else {
            _ = FocusManager.instance.dispatchKeyData(keyData)
            return
        }
        if win.appId.hasPrefix("wayland-"), let wayland = waylandIntegration {
            wayland.sendKeyEvent(physical: keyData.physical,
                                 logical: keyData.logical, isDown: true)
            wayland.sendKeyEvent(physical: keyData.physical,
                                 logical: keyData.logical, isDown: false)
            return
        }
        if let texId = processTextureIds[win.appId],
           let mgr = linuxProcessAppManager {
            let scalar = keyData.character?.unicodeScalars.first?.value ?? 0
            mgr.sendKeyEvent(textureId: texId, physical: keyData.physical,
                             logical: keyData.logical, character: scalar,
                             phase: 0)
            mgr.sendKeyEvent(textureId: texId, physical: keyData.physical,
                             logical: keyData.logical, character: 0, phase: 1)
        } else {
            _ = FocusManager.instance.dispatchKeyData(keyData)
        }
        #endif
    }

    /// Insert IME-committed text into the focused app. Child processes get
    /// synthetic character key events over the DMA-BUF input socket — their
    /// editors insert `keyData.character` on key-down, so each scalar is a
    /// down (with the character) followed by an up.
    private func _imeDeliverCommit(_ text: String) {
        #if os(Linux)
        guard let focusedId = windowManager.focusedWindowId,
              let win = windowManager.windows.first(where: { $0.id == focusedId })
        else { return }
        // Wayland clients receive IME text via zwp_text_input_v3.
        if win.appId.hasPrefix("wayland-"), let wayland = waylandIntegration {
            wayland.sendTextInputPreedit("", cursor: 0)
            wayland.sendTextInputCommit(text)
            return
        }
        guard let texId = processTextureIds[win.appId],
              let mgr = linuxProcessAppManager else { return }
        for scalar in text.unicodeScalars {
            mgr.sendKeyEvent(textureId: texId, physical: 0, logical: 0,
                             character: scalar.value, phase: 0)
            mgr.sendKeyEvent(textureId: texId, physical: 0, logical: 0,
                             character: 0, phase: 1)
        }
        #endif
    }

    /// The shell-drawn IME panel: preedit on top, numbered candidates below
    /// (fcitx runs headless — ClientSideInputPanel capability).
    private func _buildImePanel() -> Widget {
        var rows: [Widget] = []
        if !_imePreedit.isEmpty {
            rows.append(Row(mainAxisSize: .min, children: [
                Text(_imePreedit, style: TextStyle(
                    color: shellTheme.fgPrimary, fontSize: 15, fontFamily: shellTheme.fontFamily)),
            ]))
        }
        if !_imeCandidates.isEmpty {
            var items: [Widget] = []
            for (i, candidate) in _imeCandidates.enumerated() {
                if i > 0 { items.append(SizedBox(width: 14)) }
                let isHighlighted = i == _imeHighlighted
                let label = candidate.0.isEmpty ? "\(i + 1)." : candidate.0
                items.append(Row(mainAxisSize: .min, children: [
                    Text(label, style: TextStyle(
                        color: shellTheme.fgSecondary, fontSize: 13, fontFamily: shellTheme.fontFamily)),
                    SizedBox(width: 3),
                    Text(candidate.1, style: TextStyle(
                        color: isHighlighted ? Color(0xFF0A84FF) : shellTheme.fgPrimary,
                        fontSize: 15,
                        fontWeight: isHighlighted ? .w600 : .w400, fontFamily: shellTheme.fontFamily)),
                ]))
            }
            if !rows.isEmpty { rows.append(SizedBox(height: 6)) }
            rows.append(Row(mainAxisSize: .min, children: items))
        }
        return DecoratedBox(
            decoration: BoxDecoration(
                color: shellTheme.isDark ? Color(0xF0303032) : Color(0xF0F2F2F4),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: Color(0x59000000),
                                      offset: Offset(0, 4), blurRadius: 16)]
            ),
            child: Padding(
                padding: EdgeInsets(left: 14, top: 9, right: 14, bottom: 9),
                child: Column(crossAxisAlignment: .start, children: rows)
            )
        )
    }

    // MARK: - Appearance

    private static var _appearanceFile: String {
        LoginUser.configDir + "/appearance"
    }

    private static var _styleFile: String {
        LoginUser.configDir + "/style"
    }

    private static var _windowLayoutFile: String {
        LoginUser.configDir + "/window-layout"
    }

    private static var _wallpaperFile: String {
        LoginUser.configDir + "/wallpaper"
    }

    /// Switch between the floating window manager (default) and dwm-style
    /// master-stack tiling; persists the choice like the appearance.
    /// Leaving tiling restores every window's remembered floating rect.
    func _setTiling(_ enabled: Bool) {
        guard enabled != windowManager.tilingEnabled else { return }
        setState {
            windowManager.tilingEnabled = enabled
            if enabled {
                windowManager.retileAll(
                    screenWidth: screenWidth, screenHeight: screenHeight)
            } else {
                windowManager.restoreFloatingLayout()
            }
        }
        // Children mirror the choice (the Settings app's Tiling toggle).
        #if os(Linux)
        linuxProcessAppManager?.broadcastLayout(tiling: enabled)
        #endif
        let path = Self._windowLayoutFile
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try? (enabled ? "tiling" : "floating").write(
            toFile: path, atomically: true, encoding: .utf8)
    }

    /// Switch the desktop wallpaper preset (Settings' picker); persists and
    /// broadcasts like the appearance. An out-of-range value from a child is
    /// dropped, not clamped — a picker that sends nonsense is a picker whose
    /// idea of the presets has drifted, and clamping would hide that.
    func _setWallpaper(_ raw: Int) {
        guard let preset = WallpaperPreset(rawValue: raw),
              preset != wallpaperPreset else { return }
        setState { wallpaperPreset = preset }
        #if os(Linux)
        linuxProcessAppManager?.broadcastWallpaper(preset: raw)
        #endif
        let path = Self._wallpaperFile
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try? String(raw).write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Make an output the primary display (Settings › Displays): the dock
    /// moves there, new windows open there, and Wayland clients are offered it
    /// first. Persisted by connector name, so it survives a relogin and finds
    /// the same monitor after a hotplug.
    ///
    /// The shell's own widget tree does not move — the engine binds its
    /// implicit view to the output it picked, and that binding is hardware.
    /// So the dock changes trees: the host draws it only while it is also the
    /// primary, and the `SecondaryOutputScreen` of whichever output is primary
    /// draws it otherwise. `_dockHoverX` is cleared because it is a coordinate
    /// on the output the dock just left.
    func _setPrimaryDisplay(outputId: Int) {
        guard let dl = displayLayout else { return }
        let changed = dl.primary.id != outputId && dl.setPrimary(outputId: outputId)
        if changed {
            setState { _dockHoverX = nil }
            invalidateSecondaryScreens()
        }
        #if os(Linux)
        // Real multi-output: the primary is where the shell itself should
        // live — rebind the implicit view (engine) so the whole desktop
        // moves, not just the dock. The condition is host-vs-primary
        // disagreement, not `changed`: it also fires when the primary is
        // already right but the host isn't, which is the retry path after
        // an engine refusal (a recording was active).
        if dl.outputs.count > 1, !secondaryViewOutputs.isEmpty,
           let target = dl.outputs.first(where: { $0.id == outputId }),
           target.isPrimary, !target.isHost {
            requestHostOutputSwitch(to: outputId)
        }
        // Clients are told the primary first (WaylandIntegration.setOutputs
        // orders on it), but only where the wl_outputs are real — sim outputs
        // all live on the one panel and are not advertised.
        if changed, dl.outputs.count > 1, !secondaryViewOutputs.isEmpty {
            waylandIntegration?.setOutputs(dl.outputs)
        }
        // Published even when nothing changed. The pane moves its checkmark
        // optimistically and treats the echo as the truth, so a pick this
        // refused — a stale id for a monitor just unplugged — has to be
        // answered, or the pane sits there claiming a display that is gone.
        publishDisplaysToChildren()
        #endif
    }

    /// The frame pump's two rates: full for a rider that needs a liveness
    /// floor, and a slow poll otherwise so a forced tick or a capture
    /// starting is still noticed promptly.
    ///
    /// 33ms is ~30fps, which is what a screen share wants. The idle period is
    /// the latency a tooling-forced frame can see, and screenshots already
    /// wait far longer than that.
    static let kPumpFullPeriod: DispatchTimeInterval = .milliseconds(33)
    static let kPumpIdlePeriod: DispatchTimeInterval = .milliseconds(250)

    /// Decide whether the frame pump should be running at all, and how fast.
    ///
    /// Called when a rider starts or stops -- never on a timer. The pump used
    /// to ask all of them thirty times a second whether they needed anything;
    /// on an idle desktop the answer was always no, and asking was most of
    /// what the desktop cost while doing nothing.
    ///
    /// Three states rather than two:
    ///   fast   a rider needs a liveness floor now.
    ///   slow   an X client is connected, so a screen capture could start and
    ///          nothing would announce it -- the one case still worth a poll.
    ///   off    nobody is riding. No timer, no wakeups.
    func _reevaluateFramePump() {
        #if os(Linux)
        let rRec = recordingService?.needsFramePump == true
        let rCast = screenCastService?.needsFramePump == true
        let rRdp = rdpService?.needsFramePump == true
        let rCap = fl_drm_view_capture_active() != 0
        let riding = rRec || rCast || rRdp || rCap
        if Self._pumpLog, riding != _pumpRunning {
            FileHandle.standardError.write(Data(
                ("[pump] \(riding ? "arm" : "stop") rec=\(rRec) cast=\(rCast)"
                 + " rdp=\(rRdp) cap=\(rCap)\n").utf8))
        }
        let mayCapture = x11Integration?.hasClients == true
        #else
        let riding = false
        let mayCapture = false
        #endif
        guard let timer = _frameTickTimer else { return }
        if riding {
            if !_pumpRunning || !_pumpFast {
                _pumpRunning = true
                _pumpFast = true
                timer.schedule(deadline: .now() + Self.kPumpFullPeriod,
                               repeating: Self.kPumpFullPeriod)
                if !_pumpResumed { _pumpResumed = true; timer.resume() }
            }
        } else if mayCapture {
            if !_pumpRunning || _pumpFast {
                _pumpRunning = true
                _pumpFast = false
                timer.schedule(deadline: .now() + Self.kPumpIdlePeriod,
                               repeating: Self.kPumpIdlePeriod)
                if !_pumpResumed { _pumpResumed = true; timer.resume() }
            }
        } else if _pumpRunning {
            // Nobody riding: stop entirely. A suspended DispatchSourceTimer
            // costs nothing, which is the whole point.
            _pumpRunning = false
            if _pumpResumed { _pumpResumed = false; timer.suspend() }
        }
    }

    /// Restore the persisted style before the first build. Must run BEFORE
    /// `loadPersistedAppearance`, which resolves the theme out of whichever
    /// style is active.
    static func loadPersistedStyle() {
        guard let s = try? String(contentsOfFile: _styleFile, encoding: .utf8)
        else { return }
        shellStyle = ShellStyles.byId(
            s.trimmingCharacters(in: .whitespacesAndNewlines))
        shellTheme = shellStyle.theme(dark: shellTheme.isDark)
    }

    /// Restore the persisted appearance before the first build.
    static func loadPersistedAppearance() {
        if let s = try? String(contentsOfFile: _appearanceFile, encoding: .utf8) {
            shellTheme = shellStyle.theme(
                dark: s.trimmingCharacters(in: .whitespacesAndNewlines) != "light")
        }
    }

    /// Switch the desktop style — the whole shape of the chrome, not just its
    /// colours — and persist the choice. The appearance rides along: each
    /// style owns its own dark and light pair, so the switch re-resolves the
    /// theme rather than carrying the old style's colours across.
    func _setStyle(_ id: String) {
        let next = ShellStyles.byId(id)
        guard next.id != shellStyle.id else { return }
        setState {
            shellStyle = next
            shellTheme = next.theme(dark: shellTheme.isDark)
            chrome = next.makeChrome(self)
            // Cached window widgets have the old style's title bar baked into
            // their subtrees.
            _windowChildCache.removeAll()
        }
        #if os(Linux)
        linuxProcessAppManager?.broadcastStyle(index: _styleIndex(next))
        #endif
        let path = Self._styleFile
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try? next.id.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// A style's position in `ShellStyles.all` — what goes over the wire to
    /// child apps, which treat it as an opaque small integer.
    func _styleIndex(_ spec: ShellStyleSpec) -> Int {
        ShellStyles.all.firstIndex { $0.id == spec.id } ?? 0
    }

    /// Switch the desktop appearance (context menu or the Settings app's
    /// Dark Mode toggle) and persist the choice.
    func _setAppearance(dark: Bool) {
        guard dark != shellTheme.isDark else { return }
        setState {
            shellTheme = shellStyle.theme(dark: dark)
            // Cached window widgets have the old theme baked into their
            // subtrees — drop them so title bars recolor.
            _windowChildCache.removeAll()
        }
        // Child apps re-theme their own UI from the same event.
        #if os(Linux)
        linuxProcessAppManager?.broadcastTheme(dark: dark)
        // Wayland clients (Chrome, GTK/Qt) follow the portal's
        // org.freedesktop.appearance/color-scheme SettingChanged signal.
        portalIntegration?.setColorScheme(dark ? 1 : 2)
        #endif
        let path = Self._appearanceFile
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try? (dark ? "dark" : "light").write(
            toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Window Close / Minimize

    /// Actually minimize, fired when the scale-effect zoom lands on the dock.
    private func _finalizeWindowMinimize(_ winId: String) {
        setState {
            _minimizingWindows.remove(winId)
            windowManager.minimizeWindow(winId)
        }
    }

    /// Real window teardown, fired when the close animation completes:
    /// destroy the app/texture (onWindowClose) and drop the window.
    func _finalizeWindowClose(_ winId: String) {
        guard let win = windowManager.windows.first(where: { $0.id == winId }) else {
            _closingWindows.remove(winId)
            return
        }
        if win.onWindowClose != nil && win.textureId != nil {
            win.onWindowClose?()
            win.onWindowClose = nil
        }
        setState {
            _closingWindows.remove(winId)
            windowManager.closeWindow(winId)
        }
    }

    // MARK: - App Launching

    /// Focus an existing window, following it to its space when it lives on
    /// another one (macOS dock: clicking an app's icon switches to its
    /// space). Restore handles the space switch in the model; the plain
    /// focus path slides over explicitly.
    private func _focusWindowAcrossSpaces(_ win: WindowInfo) {
        // A window that belongs to a workspace lives on no space at all
        // (spaceId is the kNoSpaceId sentinel), so the space-following code
        // below finds nothing to switch to and the click does nothing
        // visible. That is a dead end the moment an app moves in — clicking
        // Claude Desktop in the launcher, once it has become an agent's
        // driver, would silently do nothing at all. Go to its workspace.
        if let owner = win.ownerAgentId,
           let ws = windowManager.workspaces.first(where: { $0.id == owner }) {
            let out = _pointerOutputId ?? displayLayout?.primary.id ?? 0
            setState {
                windowManager.selectWorkspace(ws.id, onOutput: out)
                windowManager.focusedWindowId = win.id
            }
            if !windowManager.activeSpace(onOutput: out).isWorkspace {
                _toggleWorkspaceSpace()
            }
            return
        }
        if win.isMinimized {
            windowManager.restoreWindow(win.id)
        } else {
            windowManager.bringToFront(win.id)
            // Bring the window's OWN monitor to its space — activating a
            // window on the second screen must not switch the first.
            let owner = displayLayout?.owningOutput(ofRect: win.rect).id
            if win.spaceId != windowManager.activeSpaceId(
                   onOutput: owner ?? displayLayout?.host.id ?? 0),
               let idx = windowManager.spaceIndex(ofSpaceId: win.spaceId) {
                _switchToSpace(idx, onOutput: owner)
            }
        }
    }

    #if os(Linux)
    /// Spawn one of the session's launcher scripts (app-run, wechat-run,
    /// android-app), wired to THIS shell's Wayland socket rather than
    /// app-run's wayland-0 default — which is wrong whenever the shell came up
    /// on wayland-1 after an unclean exit. The scripts take everything else
    /// from the environment, so the same three variables serve all of them.
    private func _spawnLauncher(_ path: String, args: [String] = [],
                                extraEnv: [String: String] = [:]) {
        guard let socketName = waylandIntegration?.socketName else { return }
        let process = Process()
        // Launch through setsid so the app becomes its own session leader
        // instead of inheriting OUR process group. Two reasons, and the second
        // one is not optional:
        //
        //   1. An app's helper processes (Zoom runs eleven) then share one
        //      group, so quitting it is a single signal to that group rather
        //      than a guess at which pids belong to the app.
        //   2. Without this they sit in the SHELL's process group, and any
        //      kill(-pgid, …) aimed at the app would take the whole desktop
        //      down with it. _reapAfterQuit refuses to signal its own group
        //      for exactly that reason — this is the other half of the guard.
        //
        // Foundation's Process has no setpgid knob on Linux, so the grouping
        // has to come from the exec'd program. Fall back to a direct exec if
        // setsid is missing (the app is then quit by pid, not by group).
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/setsid") {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/setsid")
            process.arguments = [path] + args
        } else {
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
        }
        var env = ProcessInfo.processInfo.environment
        env["STARLING_WAYLAND"] = socketName
        env["STARLING_XDG_DIR"] = LoginUser.runtimeDir
        env["STARLING_APP_SCALE"] = String(currentShellDpi)
        for (k, v) in extraEnv { env[k] = v }
        process.environment = env
        try? process.run()
    }
    #endif

    /// `extraArgs` reach a first-party app's argv on a fresh launch (e.g.
    /// Settings' `--pane=network` deep link). If the app is already running
    /// it is only focused — there is no runtime pane-switch channel.
    // Not private: WorkspaceSpace.swift routes launcher launches through
    // _launchFromLauncher, which falls back to this for anything that is not
    // filling a workspace's driver slot.
    func _launchOrFocusApp(_ appId: String, extraArgs: [String] = []) {
        // Ignore if this app is already being launched
        if _pendingAppLaunches.contains(appId) { return }

        // An app installed since login has no host icon loaded yet, so its
        // transient dock tile would show the neutral glyph. Cheap and idempotent.
        _loadIconTexture(for: appId)

        // Launching from the dock while Mission Control is up exits it
        // (macOS behaviour) — the target window needs the real desktop.
        if _missionControlOpen { _closeMissionControl() }

        // If the app already has a window, bring it to front. Third-party
        // windows arrive over Wayland with a synthetic appId ("wayland-N"), so
        // ownership is resolved through the registry — by the app_id the
        // client declared, not by its title. Windows playing their close
        // animation don't count: the app's process is already gone (crashed or
        // killed), and focusing the corpse would swallow the click that should
        // relaunch it.
        if let existing = windowManager.windows.first(where: {
            _appOwning($0)?.id == appId && !_closingWindows.contains($0.id)
        }) {
            _focusWindowAcrossSpaces(existing)
            return
        }

        // Otherwise, create a new window with the real app content
        let title: String
        let builder: (any BuildContext) -> Widget
        switch appId {
        case "textviewer":
            title = "Text Viewer"
            builder = { _ in TextViewerApp() }
        #if os(macOS)
        case "chrome", "vscode":
            return  // Chrome/VS Code launch not implemented on macOS
        case "externalapp":
            // Launch an offscreen-rendered external app via FlutterTexture
            if let mgr = externalAppManager {
                let texId = mgr.createExternalApp(width: 640, height: 480)
                let textureIdInt = Int(texId)
                windowManager.addWindow(
                    title: "External App",
                    appId: appId,
                    textureId: textureIdInt,
                    onWindowClose: {
                        mgr.destroyExternalApp(textureId: texId)
                    },
                    appBuilder: { _ in SizedBox(expand: ()) }
                )
            }
            return
        case "settings", "files", "flutterapp":
            // Launch as a separate process with IOSurface compositing
            let execName: String
            let winTitle: String
            let winRect: Rect?
            switch appId {
            case "settings":
                execName = "SettingsApp"; winTitle = "Settings"
                winRect = Rect.fromLTWH(100, 60, 800, 592)
            case "files":
                execName = "FileExplorerApp"; winTitle = "Files"
                winRect = Rect.fromLTWH(80, 50, 900, 620)
            default:
                execName = "FlutterDemoApp"; winTitle = "Flutter App"
                winRect = nil
            }
            if let mgr = processAppManager {
                mgr.launchApp(
                    executableName: execName,
                    onReady: { [self] (texId: Int64) in
                        setState {
                            processTextureIds[appId] = texId
                            windowManager.addWindow(
                                title: winTitle,
                                appId: appId,
                                rect: winRect,
                                textureId: Int(texId),
                                onWindowClose: {
                                    mgr.destroyApp(textureId: texId)
                                },
                                appBuilder: { _ in SizedBox(expand: ()) }
                            )
                        }
                    },
                    onTerminated: { [self] in
                        setState {
                            processTextureIds.removeValue(forKey: appId)
                            if let win = windowManager.windows.first(where: { $0.appId == appId }) {
                                _closingWindows.insert(win.id)
                            }
                        }
                    }
                )
            }
            return
        #elseif os(Linux)
        case _ where _record(appId)?.kind == .host:
            // Third-party host app. Every one of them goes out through
            // app-run, which owns the per-app launch recipe — the flags, the
            // env, and the accumulated knowledge of what each app needs (Zoom
            // must not see WAYLAND_DISPLAY, Chrome's sandbox needs nested
            // userns, IntelliJ needs -Dawt.toolkit.name=WLToolkit). The window
            // arrives back via the onNewWindow Wayland callback. app-run is
            // resolved from STARLING_APP_RUN (set by run-desktop.sh in dev) or
            // /usr/bin/app-run in the shipped image; the record's Exec names
            // the recipe.
            // PRIME offload (Gpu=discrete + a discrete GPU present): app-run
            // translates the preference into the vendor envs (DRI_PRIME /
            // __NV_PRIME_RENDER_OFFLOAD) — the mechanism lives there with the
            // rest of the launch recipe knowledge, the policy lives in the
            // record.
            var hostEnv: [String: String] = [:]
            if _record(appId)?.discreteGpu == true, DiscreteGpu.renderNode != nil {
                hostEnv["STARLING_APP_GPU"] = "discrete"
            }
            _spawnLauncher(
                ProcessInfo.processInfo.environment["STARLING_APP_RUN"]
                    ?? "/usr/bin/app-run",
                args: [_record(appId)?.exec ?? appId],
                extraEnv: hostEnv)
            return
        case _ where _record(appId)?.kind == .x11:
            // An X11-only app in its own rootful Xwayland, which is what
            // actually talks to our compositor (the in-tree X server can't
            // present WeChat's embedded Chromium). The whole X screen arrives
            // as one Wayland window; the record's RenameWindows puts the app's
            // name back on it.
            _spawnLauncher(
                ProcessInfo.processInfo.environment["STARLING_WECHAT_RUN"]
                    ?? "/usr/bin/wechat-run")
            return
        case _ where _record(appId)?.kind == .android:
            // Android apps live inside Waydroid. android-app.sh brings the
            // session up first if it isn't running, then launches through
            // `waydroid app launch` — that call sets `waydroid.active_apps`,
            // and Waydroid FREEZES the container whenever that prop is empty,
            // so a raw am/monkey start would freeze the app mid-launch.
            _spawnLauncher(
                ProcessInfo.processInfo.environment["STARLING_ANDROID_APP"]
                    ?? "/usr/bin/android-app",
                args: [_record(appId)?.exec ?? appId])
            return
        case "externalapp":
            // Launch an offscreen-rendered external app via embedder texture API
            if let mgr = linuxExternalAppManager {
                let texId = mgr.createExternalApp(width: 640, height: 480)
                windowManager.addWindow(
                    title: "External App",
                    appId: appId,
                    textureId: Int(texId),
                    onWindowClose: {
                        mgr.destroyExternalApp(textureId: texId)
                    },
                    appBuilder: { _ in SizedBox(expand: ()) }
                )
            }
            return
        case "flutterapp", _ where _record(appId)?.kind == .firstParty:
            // A Starling app, launched as a child process with DMA-BUF
            // compositing. Executable, title and opening geometry all come
            // from the app's catalog record ("flutterapp" is the dev demo and
            // has none).
            let rec = _record(appId)
            let execName = rec?.exec ?? "FlutterDemoApp"
            let winTitle = rec?.name ?? "Flutter App"
            // A record's `Window=` geometry is relative to the display the app
            // opens on, not to the virtual desktop — so it lands on the primary
            // like every other new window. Without the origin the catalog's
            // x/y are virtual-desktop coordinates, which is the host, and
            // first-party apps opened on the wrong monitor while the dock sat
            // on the right one.
            let winOrigin = displayLayout?.primary
            let winRect = rec?.windowRect.map {
                Rect.fromLTWH($0.x + (winOrigin?.originX ?? 0),
                              $0.y + (winOrigin?.originY ?? 0),
                              $0.width, $0.height)
            }
            let contentW = Int(winRect?.width ?? DesktopTheme.kDefaultWindowWidth)
            let contentH = Int((winRect?.height ?? DesktopTheme.kDefaultWindowHeight) - DesktopTheme.kTitleBarHeight)
            if let mgr = linuxProcessAppManager {
                // Mark app as launching so duplicate clicks are ignored
                _pendingAppLaunches.insert(appId)
                // Hand child apps the live Wayland socket + app-run knobs, so a
                // child that shells out to app-run (the App Store's "Open"
                // button) targets THIS shell's socket instead of app-run's
                // wayland-0 default — which is wrong whenever the shell came up
                // on wayland-1 after an unclean exit.
                var childEnv: [String: String] = [:]
                if let sock = waylandIntegration?.socketName {
                    childEnv["STARLING_WAYLAND"] = sock
                    childEnv["STARLING_XDG_DIR"] = LoginUser.runtimeDir
                    childEnv["STARLING_APP_SCALE"] = String(currentShellDpi)
                }
                // PRIME offload: a Gpu=discrete record renders on the
                // discrete GPU (GpuDmaBufRenderer picks the device up from
                // this env and its swapchain mode does the rest). A
                // session-global STARLING_APP_DRM_DEVICE (dev override) is
                // inherited by every child anyway; this only adds the
                // per-app case.
                if rec?.discreteGpu == true, let node = DiscreteGpu.renderNode {
                    childEnv["STARLING_APP_DRM_DEVICE"] = node
                }
                // Shared between onReady/onTerminated: the texture this
                // launch received, so late termination tears down only its
                // own window (never a relaunched instance's).
                var launchTexId: Int64 = -1
                let started = mgr.launchDmaBufApp(
                    executableName: execName,
                    contentWidth: contentW,
                    contentHeight: contentH,
                    extraArgs: extraArgs,
                    extraEnv: childEnv,
                    onReady: { [self] (texId: Int64) in
                        launchTexId = texId
                        // Wait for child's first rendered frame before showing the window
                        // to avoid displaying uninitialized GPU memory artifacts
                        mgr.onFirstFrame(textureId: texId) { [self] in
                            setState {
                                _pendingAppLaunches.remove(appId)
                                processTextureIds[appId] = texId
                                windowManager.addWindow(
                                    title: winTitle,
                                    appId: appId,
                                    rect: winRect,
                                    textureId: Int(texId),
                                    onWindowClose: {
                                        mgr.destroyApp(textureId: texId)
                                    },
                                    onPointerEvent: { (phase, x, y, buttons) in
                                        mgr.sendPointerEvent(
                                            textureId: texId,
                                            phase: phase,
                                            x: x, y: y,
                                            buttons: buttons
                                        )
                                    },
                                    onContentResize: { (width, height) in
                                        mgr.sendResize(
                                            textureId: texId,
                                            width: Int(width),
                                            height: Int(height)
                                        )
                                    },
                                    onScrollEvent: { (x, y, dx, dy) in
                                        mgr.sendScrollEvent(
                                            textureId: texId,
                                            x: x, y: y, dx: dx, dy: dy)
                                    },
                                    appBuilder: { _ in SizedBox(expand: ()) }
                                )
                            }
                        }
                    },
                    onTerminated: { [self] in
                        setState {
                            _pendingAppLaunches.remove(appId)
                            // Scope teardown to THIS process's texture — if
                            // the app was already relaunched, the fresh
                            // window must not be torn down by the old
                            // instance's late termination.
                            if processTextureIds[appId] == launchTexId {
                                processTextureIds.removeValue(forKey: appId)
                            }
                            // The process died (exit or crash): close its
                            // window via the animated path, otherwise it
                            // lingers as a zombie showing the last texture.
                            if let win = windowManager.windows.first(where: {
                                $0.appId == appId && $0.textureId == Int(launchTexId)
                            }) {
                                _closingWindows.insert(win.id)
                            }
                        }
                    }
                )
                // Launch never started (missing binary / socket failure): clear
                // the pending marker so the icon stays clickable and can retry.
                if !started { _pendingAppLaunches.remove(appId) }
            }
            return
        #endif
        default:
            title = appId
            builder = { _ in
                Center(
                    child: Text(
                        appId,
                        style: TextStyle(color: Color(0x80FFFFFF), fontSize: 16, fontFamily: shellTheme.fontFamily)
                    )
                )
            }
        }

        windowManager.addWindow(
            title: title,
            appId: appId,
            appBuilder: builder
        )
    }

}
