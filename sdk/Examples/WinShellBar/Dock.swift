// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The dock, on Windows — and the whole of the shell's chrome.
//
// It started beside a menu bar along the top, macOS-shaped, and that was one
// surface too many: Windows puts its shell chrome on the bottom edge, and two
// strips to reach for is worse than one wherever they sit. So the bar is gone
// and this covers the taskbar it replaces — the launcher where Start was, the
// running apps in the middle, the clock and the status icons at the right.
//
// It is a FULL-WIDTH BAR, not a floating slab. The slab was the macOS shape
// and it left wallpaper showing on both sides of a strip that Windows fills
// edge to edge; the icons are still centred, Windows 11 style, but the bar
// under them now runs the width of the screen.
//
// The panel is still declared `transparent`, and that is no longer about the
// look: the colour key is what makes the OVERHANG a hole. The window has to
// extend above the strip for the hover label and the right-click menu to have
// somewhere to draw (a window is a hard clip), and without the key that would
// be a 190pt opaque band standing over the desktop. The strip itself is
// opaque, so nothing about the bar is see-through.
//
// Clicking a tile raises its app, or starts it; right-clicking pins or unpins
// it; hovering names it; a running indicator sits under each. Clicking the
// status readout at the right opens the control centre.
//
// What it deliberately does NOT do is arrange anybody's windows. Moving other
// people's windows is the one real power a shell has on Windows, and Windows
// already has Snap; a grid nobody asked for is not worth spending it on.
//
// Where the apps come from is the interesting part. The Linux shell reads
// Starling's own registry; Windows has none, so `Win32AppCatalog` reads the
// START MENU — the same tree Explorer's Start reads — and that is the
// catalog behind both this and the launcher.

#if os(Windows)
import CupertinoIcons
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import FlutterWin32Bridge
import Observation
import Foundation

/// Bar height in logical points, and the icon size inside it.
///
/// Sized against Windows' own taskbar (48pt) rather than against a macOS
/// dock: a floating slab can afford to be tall because wallpaper surrounds
/// it, and a solid strip across the screen cannot.
let kDockHeight = 56
let kDockIcon = 34.0

/// How far the dock's WINDOW extends above the strip it reserves. The hover
/// label, the right-click menu and the control centre all draw in here; a
/// window is a hard clip, so without it they would be cut off at the top of
/// the strip. It reserves nothing and is transparent, so it is invisible and
/// click-through until something paints. Tall enough for the control centre,
/// which is the largest thing that opens here.
/// How far the window extends past the strip, for labels, menus and the
/// control centre to draw in.
///
/// Deep enough for the TALLEST of them, which is Quick Settings with a
/// brightness slider: 392 of panel plus the 13pt inset. On a vertical dock
/// the panel opens across the overhang instead, and 13 + kQsWidth = 371
/// fits the same depth. A window is a hard clip and there is no warning.
let kDockOverhang = 420

/// The overhang actually in effect. `--oneview` (the one-view shell) grows
/// it to everything above the strip, making the dock's window the ONE
/// full-screen chrome surface — the launcher draws inside it as a layer,
/// the way the Linux shell stacks its overlays in a single surface. Set
/// once in main.swift before the window exists; the colour key keeps the
/// undrawn screen a click-through hole either way.
nonisolated(unsafe) var dockOverhang = kDockOverhang

/// Geometry the flyout arithmetic needs. The tile is a fixed size, so where
/// each one sits is arithmetic rather than a layout query — which is what
/// lets a label be positioned over an icon without measuring anything.
let kDockTile = kDockIcon + 14.0

/// Quick Settings, in logical points — WINDOWS' geometry, not ours. Every
/// number here was measured off the native Win+A panel on this machine
/// (docs: 358 wide, 24pt content inset, 94x48 buttons three across with
/// 14pt gaps on a 96pt row pitch, an 8pt corner). The panel is a replica of
/// an Explorer surface the shell replaces, so the native panel is the spec
/// and "close" reads as wrong the moment they are seen side by side.
let kQsWidth = 358.0
let kQsPad = 24.0
let kQsBtnW = 94.0
let kQsBtnH = 48.0
let kQsGapX = 14.0
/// Button top to next button top; the label rides in the space between.
let kQsRowPitch = 96.0
/// One slider's zone — glyph, track and thumb centred inside it.
let kQsSliderZone = 60.0
let kQsFooterH = 56.0
let kQsRadius = 8.0
/// How far the panel sits from the screen edge — 13 on the native panel.
let kCcInset = 13.0

/// Width of the status cluster. FIXED, and imposed with a SizedBox, for the
/// same reason the dock's tiles are a fixed size: the click that opens the
/// control centre is hit-tested by arithmetic from a root Listener, and an
/// estimate that drifts from the layout opens the panel from the wrong place
/// — or from nowhere.
let kStatusWidth = 210.0
/// The same readout down a column: icons stacked over a two-line clock.
let kStatusHeight = 132.0

/// Whether Explorer's taskbar is left alone. `--plain` is a bisect flag and
/// has no business changing the desktop underneath it.
let keepsNativeTaskbar =
    CommandLine.arguments.contains("--keep-taskbar")
    || CommandLine.arguments.contains("--plain")

/// One notification-area icon's cell along the strip, and the picture inside
/// it. 16pt is what Windows draws a tray icon at, and these sit beside its
/// icons in the user's memory rather than beside our 40pt dock tiles.
let kTrayCell = 26.0
let kTrayIcon = 16.0
/// A taskbar preview: one thumbnail per window of the app being hovered,
/// with its title above it — the card Windows shows when you hover a taskbar
/// button. 16:9 because most windows are wider than they are tall, and the
/// thumbnail is letterboxed inside it rather than stretched.
let kPreviewThumbW = 208.0
let kPreviewThumbH = 117.0
let kPreviewTitleH = 20.0
let kPreviewPad = 10.0
let kPreviewMaxCols = 4

/// The overflow flyout: a cell per hidden icon, at most four to a row, which
/// is the shape Windows 11's own overflow uses.
let kTrayFlyoutCell = 40.0
let kTrayFlyoutCols = 4
let kTrayFlyoutPad = 8.0

/// STARLING_DOCK_DEBUG=1 traces the pointer. Hover is the one input this
/// surface cannot check by looking at a screenshot: if nothing is drawn there
/// is no way to tell "the event never came" from "the event came and the
/// state did not change" from "the state changed and nothing composited".
let dockDebug = (ProcessInfo.processInfo.environment["STARLING_DOCK_DEBUG"] ?? "0") != "0"

/// Whether Explorer keeps the notification area. The tray is other people's
/// icons and hosting it means taking a window class off explorer, so it gets
/// the same escape hatch as the taskbar and the Windows key.
let keepsNativeTray =
    CommandLine.arguments.contains("--keep-tray")
    || CommandLine.arguments.contains("--plain")
    // Taking the tray while explorer's taskbar is still on screen would empty
    // ITS notification area into ours — the icons only exist in one place,
    // and the one the user can see would be the one without them.
    || keepsNativeTaskbar

/// Whether the Windows key is left to Windows. Same bargain as the taskbar:
/// the shell takes over the thing the user reaches for, and there is a flag
/// to hand it back. `--plain` opts out of both for the same reason.
let keepsWindowsKey =
    CommandLine.arguments.contains("--keep-winkey")
    || CommandLine.arguments.contains("--plain")

/// What the dock keeps when nothing of that app is running, on a machine that
/// has never been told otherwise. Matched loosely against the Start Menu
/// name, because the exact wording moves between Windows releases ("Command
/// Prompt" vs "Terminal") and a dock that silently loses an entry after an
/// update is worse than one that keeps a near match.
/// One row of a tile's menu: what it says, and what it does.
struct DockMenuRow {
    let label: String
    let action: () -> Void
}

let kMenuRowH = 30.0

/// Where the dock can go, in the order the menu offers it.
let kDockEdges: [(edge: PanelEdge, label: String)] = [
    (.bottom, "Dock at the bottom"),
    (.left, "Dock on the left"),
    (.right, "Dock on the right"),
    (.top, "Dock at the top"),
]

/// The four Wi-Fi bars, shortest first.
let kBarHeights: [Double] = [5, 8, 11, 15]

// No "file explorer" here: the Files tile below takes that role, opening
// STARLING's explorer. Windows' own stays launchable from Start.
let kDefaultPins = ["terminal", "notepad", "paint", "edge", "settings"]

/// The launcher's tile. A reserved key rather than a separate widget, so it
/// flows through the same hit-testing arithmetic, the same hover label and
/// the same layout as every other tile — a dock with one special-cased tile
/// on the left is where the geometry starts drifting.
///
/// It lives here, not on the menu bar, because that is where a launcher goes
/// on a macOS-shaped desktop: the top strip belongs to the focused app, and
/// the thing you press to start something belongs beside the things you have
/// already started.
let kLauncherKey = "\u{1}starling-launcher"

/// The file manager's tile — reserved like the launcher's, and it opens
/// STARLING's file explorer, not Windows'. Taking the file-manager ROLE is
/// deliberate and this is its whole extent (plus Win+E): explorer.exe keeps
/// running, keeps the desktop and the dialogs, and the global Directory
/// association is left alone — apps that open folders still get the handler
/// they assume. The tile wears explorer.exe's own yellow folder, because
/// that is the icon that means "files" on this desktop.
let kFilesKey = "\u{1}starling-files"

/// One dock entry: an installed app, a running app, or both.
struct DockItem {
    let key: String
    let name: String
    /// nil for something running that we could not find in the Start Menu —
    /// it still shows and still raises, it just cannot be launched again.
    let app: Win32App?
    /// Every window this app has, most recently used first.
    let windows: [Win32Window]
    let isPinned: Bool
    var isRunning: Bool { !windows.isEmpty }
    var isForeground: Bool { windows.contains { $0.isForeground } }
}

final class StarlingDock: StatefulWidget {
    override func createState() -> State<StatefulWidget> { StarlingDockState() }
}

final class StarlingDockState: State<StatefulWidget> {
    /// Everything the dock DRAWS comes from here — see DockBloc for why the
    /// data and all the slow work that produces it live outside the widget.
    private let bloc = dockBloc

    // What is left is view state: it is about this frame's pointer, it changes
    // on every mouse move, and routing it through the bloc would be a round
    // trip per motion event for something no other surface can see.

    /// The tile the pointer is over, if any. A PLAIN var, deliberately: the
    /// only thing in the tree that reads it is the flyout slot, which is its
    /// own stateful leaf (DockFlyoutSlot, end of file) poked directly — a
    /// setState here rebuilds the entire full-screen chrome view per tile
    /// crossing, which was measured at ~9% of a core under a pointer sweep.
    private var hovered: Int?
    /// The live flyout slot, registered by its state on mount.
    fileprivate weak var flyoutSlot: DockFlyoutSlotState?
    /// Generation token for the label timeout below. Hover events only
    /// arrive while the pointer MOVES over our opaque pixels, and the
    /// overhang above the strip is a click-through colorkey hole — so a
    /// pointer that jumps from a tile straight into the hole (a fast flick,
    /// or an injected warp) never delivers the `index=nil` move that clears
    /// the label, and there is no leave event on this surface
    /// (MouseRegion.onExit never fires — see the menu note above). Windows'
    /// own tooltips auto-dismiss after a few seconds anyway, so the timeout
    /// is the native behaviour AND the heal for the stranded case.
    private var labelTimeoutGen = 0
    /// The dwell before a flyout first shows (see the hover handler): the
    /// tile the pointer is waiting on, and the token that retires a dwell
    /// the pointer moved away from.
    private var pendingHover: Int?
    private var pendingTray: UInt64?
    private var dwellGen = 0
    /// Thumbnails for the tile being hovered. Kept out of the bloc for the
    /// same reason `hovered` is: it is about this pointer, and it is thrown
    /// away the moment the pointer leaves.
    private let previews = PreviewCache()
    /// Bumped whenever the preview closes or moves to another tile, so a
    /// refresh armed for the old one stops re-arming.

    /// Whether the overflow flyout — the icons behind the chevron — is down.
    private var trayOverflowOpen = false
    /// The notification icon the pointer is over — by identity rather than
    /// index, because the strip reorders itself whenever an app comes or goes
    /// and an index would name a different icon a moment later.
    private var hoveredTray: UInt64?
    /// Which Quick Settings control is under the pointer — native buttons
    /// answer hover, and after the MouseRegion fix there is no excuse left.
    /// Still arithmetic off the root Listener, same as everything else in
    /// the panel: one rectangle set for drawing and hit-testing both.
    private var hoveredQs: QsHover?

    enum QsHover: Equatable {
        case tile(Int)
        case gear
        case output
    }
    /// The tile whose right-click menu is open, if any.
    private var menuOpen: Int?
    /// One-view shell only: whether the launcher LAYER is up. In every
    /// other mode the launcher is its own window/view and this stays false.
    private var launcherOpen = false
    /// Whether the panel is holding activation for an open flyout, and the
    /// one press that hands the foreground ON rather than back.
    private var flyoutFocus = false
    private var flyoutFocusHandsOn = false
    /// Whether this process draws the launcher as a LAYER of this tree (the
    /// one-view shell) rather than leaving it to a launcher window.
    private var launcherLayerMode = false
    /// The file explorer's surface view, when this process is hosting it.
    /// nil means there is none and opening Files spawns a process, which is
    /// what happens in the process-per-surface modes.
    private var filesSurfaceId: Int?
    /// Whether the control centre is down, and whether the pointer is
    /// currently dragging its volume slider.
    private var controlCentreOpen = false
    private var draggingVolume = false
    /// Which slider a drag started on, if any — the two tracks are the same
    /// shape and a drag must stay with the one it began in.
    private var draggingBrightness = false

    private var timer: AnyObject?

    override func initState() {
        super.initState()
        CupertinoIcons.registerFont()
        // The chrome glyphs are Segoe Fluent Icons now; Cupertino stays
        // registered for anything the framework's own controls draw.
        FluentIcons.registerFont()
        bloc.add(.start)
        Win32WindowManager.observe { [weak self] _ in
            self?.bloc.add(.windowsChanged)
        }

        // Through hostPeriodicTimerInstall rather than Foundation.Timer: on
        // the DRM embedder a Foundation timer never fires at all (see the
        // desktop's CLAUDE.md), and going through the host keeps every
        // backend honest about which loop the UI thread is really running.
        //
        // ...and it is the FALLBACK now. Each of the three things the tick did
        // has a notification behind it, and `Win32Status.watch` subscribes to
        // all of them on one thread: the power broadcast (battery and the
        // AC/battery switch), the WLAN and IP-interface callbacks (the network
        // readout), WM_SETTINGCHANGE (the theme), a registry watch on the
        // tray's promoted/hidden split, and TaskbarCreated — which is
        // explorer announcing its own return, the thing the tick's FindWindow
        // was standing in for.
        //
        // Volume, night light and energy saver are not in that list because
        // the STRIP does not show them: they live in Quick Settings, which
        // asks for a fresh read when it opens (see the control-centre branches
        // below). Nothing on screen is stale, and nothing is asked for on a
        // timer.
        if !Win32Status.watch({ [weak self] change in
            guard let self else { return }
            switch change {
            case .status: self.bloc.add(.statusChanged)
            case .tray: self.bloc.add(.trayChanged)
            case .taskbar: self.bloc.add(.taskbarReturned)
            case .prefs: self.bloc.add(.taskbarPrefsChanged)
            }
        }) {
            // The watcher could not start. Better a heartbeat than a status
            // bar that never moves again.
            print("[WinShellDock] status watcher failed; falling back to a poll")
            timer = startPeriodicTimer(seconds: 5.0) { [weak self] in
                self?.bloc.add(.tick)
            }
        }

        // Win+A is Quick Settings, Win+N the notification centre, Win+E the
        // file explorer, and Win+R the Run dialog — OURS, all four, exactly
        // the surfaces this shell replaces. Registered here rather than in
        // main because Quick Settings' open flag lives in this State; the
        // hook itself was installed before the window existed, and chords
        // ride it.
        Win32Shell.captureSuperChords(["A", "N", "E", "R"]) { [weak self] letter in
            guard let self else { return }
            defer { self.syncFlyoutFocus() }
            switch letter {
            case "N":
                self.setState { self.controlCentreOpen = false }
                Win32Shell.toggleOverlay(channel: "notifications")
            case "E":
                self.openFiles()
            case "R":
                Win32Shell.toggleOverlay(channel: "run")
            default:
                self.setState { self.controlCentreOpen.toggle() }
                if self.controlCentreOpen { self.bloc.add(.tick) }
            }
        }
        // Click-away, for the flyouts drawn in this window and for the
        // one-view launcher layer alike: the panel holds activation while one
        // is down (see syncFlyoutFocus), so the press that lands anywhere
        // else arrives here as WM_ACTIVATE/WA_INACTIVE. The host keeps one
        // handler per callback, so this is the only place either is set.
        Win32WindowedHost.host?.onDeactivate { [weak self] in
            guard let self else { return }
            if self.launcherOpen {
                self.setLauncherLayer(open: false, handBackFocus: false)
                return
            }
            self.closeFlyouts(handBackFocus: false)
        }
        Win32WindowedHost.host?.onToggle { [weak self] in
            guard let self else { return }
            // Escape shares this callback -- `takeFocus` registers it as the
            // global hotkey -- so an open flyout goes first and the toggle
            // stops there. Escape means "close what is open", not "open
            // Start". A Start press from the dock's own tile never reaches
            // this with a flyout still up: the press closed it on the way
            // through the Listener below, synchronously, before the toggle
            // broadcast it posted comes back.
            if self.closeFlyouts(handBackFocus: true) { return }
            if self.launcherLayerMode { self.toggleLauncherLayer() }
        }
        // Park the notification centre now, so the first Win+N is a show
        // rather than a second engine boot. Idempotent across dock restarts.
        Win32Shell.ensureNotificationCenter()
        // And the banner process: it has no user gesture to boot on, so it
        // must be warm before the first toast arrives.
        Win32Shell.ensureBanners()
        // And the Run dialog, so Win+R is a show too.
        Win32Shell.ensureRun()
        // And the shell's context-menu handlers, a few seconds from now.
        warmShellMenu()
        if CommandLine.arguments.contains("--oneview") {
            // The one-VIEW shell: the launcher is a LAYER of this tree (the
            // panel window covers the whole screen — dockOverhang was grown
            // in main.swift), the way the Linux shell stacks its overlays in
            // one surface. Only the desktop (wallpaper plane) remains a
            // second view, because DWM gives one window one z-slot: the
            // wallpaper must sit UNDER apps while this chrome sits over them.
            openOneviewSurfaces()
        } else if CommandLine.arguments.contains("--oneshell") {
            // The one-app shell (branch winshell-oneapp): the desktop and the
            // launcher are ENGINE VIEWS of this process, not processes of
            // their own — one engine, one Swift runtime, one icon cache, and
            // a toggle that is a message to a window that already exists.
            openOneshellSurfaces()
        } else {
            // And the launcher (Start menu): the dock's tile and the Windows
            // key only BROADCAST a toggle, so a launcher process has to be
            // parked and listening. The dev-time starling.cmd started
            // `--launcher` as its own line; under `--session` nothing did, so
            // Start was dead until here.
            Win32Shell.ensureLauncher()
        }
    }

    /// The one-view shell: desktop view + the launcher wired as a layer of
    /// THIS tree. The toggle broadcast already reaches this window (the host
    /// fires its callback for any host kind); click-away is the window's own
    /// deactivation, exactly what the floating launcher window used.

    /// The FILE EXPLORER, hosted by this process as an app surface.
    ///
    /// The whole reason: `egl::Manager::Create` -- ANGLE bringing up a D3D
    /// device -- is ~110 ms and is charged ONCE PER PROCESS, when the engine
    /// is constructed. A view on an engine that is already running pays none
    /// of it, and neither does it pay the process start, the DLL load or the
    /// Swift runtime init. Explorer gets exactly this deal from being part of
    /// the Windows shell; this is the same trick.
    ///
    /// Built HIDDEN at shell startup, because a hidden view still composites:
    /// by the time anyone presses Win+E the tree is mounted and its first
    /// scene is on the swapchain, so opening is a ShowWindow. Closing hides
    /// it again rather than destroying it, so the second open is free too.
    private func openFilesSurface() {
        guard filesSurfaceId == nil else { return }
        // The title is the CONTRACT with the dock, not decoration: `_rebuild`
        // finds this window by our exe plus exactly this string, and the
        // window list drops untitled windows outright. Without it the file
        // explorer has no tile, no running indicator, and — since the
        // minimize stubs went away — no way back once it is minimized.
        let id = Win32Surfaces.open(kind: .app,
                                    title: "Starling Files",
                                    width: kFilesWidth,
                                    height: kFilesHeight) { _ in
            StarlingFiles()
        }
        guard let id else {
            print("[WinShell] files surface FAILED; falling back to a process")
            return
        }
        filesSurfaceId = id
        // Everything the Files tree does to "its window" must land on THIS
        // window, not on the dock -- see FilesWindow.
        FilesWindow.current = .surface(id)
        // Both transitions POKE the window list. The dock's watcher installs
        // its WinEvent hooks with WINEVENT_SKIPOWNPROCESS — deliberately, so
        // the shell's own overlays don't feed back — which means show and
        // hide of THIS window, the one window of ours that appears in the
        // list, produce no event at all. Without the pokes the tile and its
        // hover card keep yesterday's answer until some unrelated app
        // happens to raise a window event: a closed Files kept a live-looking
        // preview, and a fresh open could show a black one.
        FilesWindow.opener = { [weak self] in
            Win32Surfaces.show(id)
            self?.bloc.add(.windowsChanged)
        }
        Win32Surfaces.onClose(id) { [weak self] in
            // Hidden, not gone. Explorer forgets your tabs on close; this
            // keeps them, which is the trade for opening instantly.
            print("[WinShell] files surface hidden")
            self?.bloc.add(.windowsChanged)
        }
        print("[WinShell] files surface view: \(id)")
    }

    /// Win+E, and the dock's menu entry. One decision, in FilesWindow.
    func openFiles() { FilesWindow.openFileExplorer() }

    /// WARM THE SHELL'S CONTEXT-MENU HANDLERS, once, a few seconds in.
    ///
    /// The first right-click of a session costs **293ms against ~130ms warm**
    /// — measured on the box with the shell idle (0ms of CPU over the three
    /// seconds before the click), so it is not startup work standing in the
    /// way. It is the first IContextMenu session loading the handler DLLs:
    /// zipfldr, wshext, sendmail, Defender's, the Open-with machinery.
    ///
    /// THIS WAS TRIED ONCE AND REMOVED, and the comment recording that (in
    /// main.swift, above `--menu-probe`) says exactly why it bought nothing:
    /// *"the handler DLLs are already resident from explorer.exe anyway"*.
    /// That was true of an app running under Explorer. This process IS the
    /// shell, explorer is not running, and nothing else loads them before the
    /// user's first right-click — so the same warm-up now buys the whole
    /// difference, and the measurement that retired it has to be read with
    /// its premise attached.
    ///
    /// ONE query, and deliberately NOT at the first frame. Every menu session
    /// shares one serial queue on purpose (two threads asking the shell at
    /// once is the contention the icon cache already measured itself out of),
    /// so a right-click arriving while this is in flight would queue BEHIND
    /// it — a warm-up at startup, competing with the catalog walk and a few
    /// hundred icons, could make the first menu slower rather than faster.
    /// Four seconds in, the catalog is done, the shell is idle, and the user
    /// has not reached a folder yet.
    private func warmShellMenu() {
        guard !Self.shellMenuWarmed else { return }
        Self.shellMenuWarmed = true
        let owner = Win32WindowedHost.host?.windowHandle ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            let home = ProcessInfo.processInfo.environment["USERPROFILE"]
                ?? "C:\\Users"
            guard let session = Win32ShellMenu(path: home, owner: owner) else {
                return
            }
            // The rows are thrown away. What this came for is the DLLs the
            // query loads and the shell's own caches it fills, which the next
            // session — the user's — then does not pay for.
            session.items(.full) { _ in session.close() }
        }
    }

    /// Once per process: the DLLs stay loaded for its life.
    private nonisolated(unsafe) static var shellMenuWarmed = false

    private func openOneviewSurfaces() {
        if !SessionSlot.explorerOwnsShell
            || ProcessInfo.processInfo.environment["STARLING_DESKTOP_TRIAL"]
                == "1" {
            let desk = Win32Surfaces.open(kind: .desktop) { id in
                StarlingDesktop(surfaceId: id)
            }
            print("[WinShell] oneview desktop view: \(desk.map(String.init) ?? "FAILED")")
        } else {
            print("[WinShell] oneview desktop skipped (explorer present)")
        }
        openFilesSurface()
        launcherBloc.add(.start)
        // The toggle and the deactivation are registered once for the whole
        // surface, in initState: the host keeps ONE handler for each, so a
        // second registration here would quietly replace the flyouts' own.
        launcherLayerMode = true
    }

    private func toggleLauncherLayer() {
        setLauncherLayer(open: !launcherOpen, handBackFocus: true)
    }

    /// Hold activation exactly while a dock flyout is down.
    ///
    /// The flyouts — the tray overflow, Quick Settings, a tile's menu — are
    /// drawn INSIDE this panel window, and a press outside one never reaches
    /// the root Listener: the overhang is a colour-keyed hole, so the window
    /// under that pointer belongs to somebody else. Each flyout's "outside
    /// closes it" branch therefore only ever ran for presses that landed on
    /// the strip, and clicking away left the flyout up for the rest of the
    /// session — with the hover labels suppressed behind it, since
    /// `flyoutContent` gives way to an open flyout.
    ///
    /// Click-away has to arrive as the panel's own deactivation instead, and
    /// that only happens if the panel holds activation while the flyout is
    /// down: the same handoff the one-view launcher layer uses.
    /// WS_EX_NOACTIVATE refuses activation from clicks — a taskbar press must
    /// not take the keyboard from the window it raises — but takes it
    /// programmatically, which is what `takeFocus` does. It also registers the
    /// global Escape hotkey, so Escape closes a flyout for free.
    ///
    /// `handBackFocus` puts the keyboard back where the user had it, which is
    /// right for a deliberate close and wrong twice over: on a click-away the
    /// click already chose the new owner, and on a tray icon's click the app
    /// is about to take the foreground from us to raise its own menu — a
    /// `SetForegroundWindow` on the way out would take it straight back, and
    /// a tray menu whose owner was refused the foreground dismisses itself in
    /// the frame it appears in.
    private func syncFlyoutFocus(handBackFocus: Bool = true) {
        // The launcher layer runs its own take/release: it wants the keyboard
        // for the search field, and it closes by a path of its own.
        guard !launcherOpen else { return }
        let want = (trayOverflowOpen && !hiddenTray.isEmpty)
            || controlCentreOpen || menuOpen != nil
        guard want != flyoutFocus else { return }
        flyoutFocus = want
        if want {
            Win32WindowedHost.host?.takeFocus()
        } else {
            Win32WindowedHost.host?.releaseFocus(restore: handBackFocus)
        }
    }

    /// Close whatever dock flyout is down. True when there was one, so a
    /// caller can stop there — Escape means "close what is open".
    @discardableResult
    private func closeFlyouts(handBackFocus: Bool) -> Bool {
        guard trayOverflowOpen || controlCentreOpen || menuOpen != nil else {
            return false
        }
        setState {
            trayOverflowOpen = false
            controlCentreOpen = false
            menuOpen = nil
            hoveredQs = nil
        }
        syncFlyoutFocus(handBackFocus: handBackFocus)
        return true
    }

    private func setLauncherLayer(open: Bool, handBackFocus: Bool) {
        guard open != launcherOpen else { return }
        setState {
            launcherOpen = open
            menuOpen = nil
            controlCentreOpen = false
            trayOverflowOpen = false
        }
        if open {
            // Whatever the flyouts were holding is the layer's business now:
            // it takes activation itself, and releases it on every close path.
            flyoutFocus = false
            launcherBloc.add(.opened)
            // Start owns the keyboard while it is up — the search field's
            // autofocus lands in a tree whose window really has focus.
            Win32WindowedHost.host?.takeFocus()
        } else {
            launcherBloc.add(.closed)
            // ALWAYS released (it also unregisters the global Escape
            // hotkey); the foreground goes back only when the close was not
            // a click-away, where the click already chose the new owner.
            Win32WindowedHost.host?.releaseFocus(restore: handBackFocus)
        }
    }

    /// The one-app shell's secondary surfaces, opened once the engine is up
    /// (initState is inside the first frame, which is exactly that moment).
    private func openOneshellSurfaces() {
        // The desktop keeps its plan-mandated gate: while explorer runs,
        // Progman owns the bottom of the z-order and fighting it is a losing
        // game. Same override as the process-per-surface desktop.
        if !SessionSlot.explorerOwnsShell
            || ProcessInfo.processInfo.environment["STARLING_DESKTOP_TRIAL"]
                == "1" {
            let desk = Win32Surfaces.open(kind: .desktop) { id in
                StarlingDesktop(surfaceId: id)
            }
            print("[WinShell] oneshell desktop view: \(desk.map(String.init) ?? "FAILED")")
        } else {
            print("[WinShell] oneshell desktop skipped (explorer present)")
        }
        openFilesSurface()
        // The launcher mounts hidden — a hidden VIEW still composites, so
        // the whole parked-overlay dance (full-size parks, WM_SIZE kicks,
        // preload off the widget lifecycle) is simply not needed here. Start
        // the bloc first so the catalog walk overlaps the mount.
        launcherBloc.add(.start)
        let start = Win32Surfaces.open(kind: .overlay,
                                       width: kLauncherWidth,
                                       height: kLauncherHeight,
                                       bottomMargin: kLauncherGap) { id in
            StarlingLauncher(surfaceId: id)
        }
        print("[WinShell] oneshell launcher view: \(start.map(String.init) ?? "FAILED")")
    }

    override func dispose() {
        Win32WindowManager.stopObserving()
        
        super.dispose()
    }

    // MARK: - Pins, on disk

    /// `%APPDATA%\Starling\dock.txt`, one target per line. A text file rather
    /// than the registry: it is inspectable, it is trivially resettable by
    /// deleting it, and a shell prototype has no business writing to HKCU.
    private var pinsPath: String {
        let base = ProcessInfo.processInfo.environment["APPDATA"]
            ?? ProcessInfo.processInfo.environment["USERPROFILE"] ?? "."
        return base + "\\Starling\\dock.txt"
    }

    // MARK: - Model

    // MARK: - Actions

    /// Starts an app without holding the UI thread.
    ///
    /// The fast path is 8ms and the `.lnk` fallback measured 484ms on its
    /// first use in a process — and a dock that freezes for half a second on
    /// the click that starts an app is the worst possible moment for it.
    static func launchOffThread(_ app: Win32App) {
        Task.detached { Win32AppCatalog.launch(app) }
    }

    // MARK: - The control centre
    //
    // Clicking the status readout opens the panel that changes what it is
    // reading — the same bargain the desktop's own control centre makes, and
    // the reason the readout is worth clicking at all.
    //
    // Every rectangle in here is arithmetic, computed once by `ccRects` and
    // used by BOTH the drawing and the hit-testing. That is not a style
    // choice: this framework's widget-level input callbacks are unreliable
    // here (MouseRegion.onEnter and onSecondaryTap never fire, see
    // `pointerTile`), so the panel is driven from a root Listener, and a
    // layout that positioned its tiles independently of the hit test would
    // drift the two apart with nothing to show for it but dead buttons.

    /// One control-centre control: where it is, and what it does.
    private struct CcRect {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
        func contains(_ px: Double, _ py: Double) -> Bool {
            px >= x && px <= x + w && py >= y && py <= y + h
        }
    }

    /// The panel's own frame, in the dock window's coordinates.
    /// Beside the readout that opens it, on the inward side of the strip.
    private var ccFrame: CcRect {
        switch bloc.state.edge {
        case .bottom:
            return CcRect(x: ShellScreen.logicalWidth - kCcInset - kQsWidth,
                          y: stripOffset - kCcInset - ccHeight,
                          w: kQsWidth, h: ccHeight)
        case .top:
            return CcRect(x: ShellScreen.logicalWidth - kCcInset - kQsWidth,
                          y: Double(kDockHeight) + kCcInset,
                          w: kQsWidth, h: ccHeight)
        case .left:
            return CcRect(x: Double(kDockHeight) + kCcInset,
                          y: ShellScreen.logicalHeight - kCcInset - ccHeight,
                          w: kQsWidth, h: ccHeight)
        case .right:
            return CcRect(x: stripOffset - kCcInset - kQsWidth,
                          y: ShellScreen.logicalHeight - kCcInset - ccHeight,
                          w: kQsWidth, h: ccHeight)
        }
    }

    /// Whether the panel offers a brightness slider at all — only when a
    /// monitor answered DDC/CI. Plenty do not, and a slider that cannot move
    /// anything is worse than no slider. The native panel makes the same
    /// call: this machine's Win+A has no brightness row either.
    private var hasBrightness: Bool { bloc.state.brightness != nil }

    /// What a Quick Settings button does when pressed. An enum rather than a
    /// closure so the hit test can dispatch without capturing the widget.
    private enum QsAction {
        case toggleWifi
        case toggleNightLight
        /// Opens a system surface — a `ms-settings:` page or an inbox exe.
        /// The panel closes, exactly as the native one does on a launch.
        case open(String)
    }

    /// One button of the grid: Windows' tile set for this hardware, with our
    /// backends behind it. `active` paints it accent; `available: false`
    /// draws it dimmed and dead.
    private struct QsTile {
        let icon: IconData
        let label: String
        let active: Bool
        var available = true
        var chevron = false
        var closes = false
        let action: QsAction
    }

    /// The grid, assembled the way Windows assembles its own: from what the
    /// hardware has. No Wi-Fi adapter, no Wi-Fi tile; no night-light state,
    /// no night-light tile. At most six — two rows of three, the native
    /// default page.
    private var qsTiles: [QsTile] {
        var tiles: [QsTile] = []
        let s = bloc.state
        if s.network.hasWifiAdapter {
            let ethernet = s.network.kind == .ethernet && s.wifiWanted == nil
            tiles.append(QsTile(
                icon: s.wifiIsOn ? FluentIcons.wifi : FluentIcons.wifiOff,
                label: ethernet ? "Ethernet"
                    : (s.wifiIsOn && !s.network.ssid.isEmpty ? s.network.ssid : "Wi-Fi"),
                active: s.wifiIsOn || ethernet,
                chevron: true, action: .toggleWifi))
        }
        tiles.append(QsTile(icon: FluentIcons.accessibility,
                            label: "Accessibility", active: false,
                            chevron: true, closes: true,
                            action: .open("ms-settings:easeofaccess")))
        tiles.append(QsTile(icon: CupertinoIcons.leaf_arrow_circlepath,
                            label: "Energy saver",
                            active: s.energySaver == true,
                            available: s.energySaver != nil, closes: true,
                            action: .open("ms-settings:powersleep")))
        tiles.append(QsTile(icon: FluentIcons.cc,
                            label: "Live captions", active: false, closes: true,
                            action: .open("LiveCaptions.exe")))
        if s.nightLight != nil {
            tiles.append(QsTile(icon: FluentIcons.moon,
                                label: "Night light",
                                active: s.nightLight == true,
                                action: .toggleNightLight))
        }
        tiles.append(QsTile(icon: FluentIcons.share,
                            label: "Nearby sharing", active: false, closes: true,
                            action: .open("ms-settings:crossdevice")))
        tiles.append(QsTile(icon: FluentIcons.project,
                            label: "Wired display", active: false,
                            chevron: true, closes: true,
                            action: .open("DisplaySwitch.exe")))
        return Array(tiles.prefix(6))
    }

    private var qsRows: Int { (qsTiles.count + 2) / 3 }

    private var ccHeight: Double {
        kQsPad + Double(qsRows) * kQsRowPitch
            + (hasBrightness ? kQsSliderZone : 0) + kQsSliderZone + kQsFooterH
    }

    private func ccRects() -> (tiles: [CcRect], slider: CcRect,
                               brightness: CcRect?, footer: CcRect,
                               gear: CcRect, output: CcRect) {
        let f = ccFrame
        // Three across on the native pitch; the label lives in the 48pt
        // under its button, inside the same row.
        let tiles: [CcRect] = (0..<qsTiles.count).map { i in
            CcRect(x: f.x + kQsPad + Double(i % 3) * (kQsBtnW + kQsGapX),
                   y: f.y + kQsPad + Double(i / 3) * kQsRowPitch,
                   w: kQsBtnW, h: kQsBtnH)
        }
        let afterTiles = f.y + kQsPad + Double(qsRows) * kQsRowPitch
        // The slider zones span the panel minus the side insets; the drawn
        // track is narrower, but a drag that starts on the glyph should
        // still take the slider, so the hit rectangle is the whole zone.
        // Brightness above sound, the order the native panel uses.
        let brightness = hasBrightness
            ? CcRect(x: f.x + kQsPad, y: afterTiles,
                     w: kQsWidth - kQsPad * 2 - 44, h: kQsSliderZone)
            : nil
        let slider = CcRect(x: f.x + kQsPad,
                            y: afterTiles + (hasBrightness ? kQsSliderZone : 0),
                            w: kQsWidth - kQsPad * 2 - 44, h: kQsSliderZone)
        // The output-picker affordance at the volume slider's right.
        let output = CcRect(x: slider.x + slider.w, y: slider.y,
                            w: 44, h: kQsSliderZone)
        let footer = CcRect(x: f.x, y: f.y + ccHeight - kQsFooterH,
                            w: kQsWidth, h: kQsFooterH)
        // The gear, right-aligned in the footer on the native inset.
        let gear = CcRect(x: f.x + kQsWidth - kQsPad - 32,
                          y: footer.y + (kQsFooterH - 32) / 2, w: 32, h: 32)
        return (tiles, slider, brightness, footer, gear, output)
    }

    /// Where the status readout is, and therefore what opens the panel.
    /// The status readout's own rectangle — pressing it opens the panel.
    private var ccOpener: CcRect {
        switch bloc.state.edge {
        case .bottom:
            return CcRect(x: ShellScreen.logicalWidth - kStatusWidth,
                          y: stripOffset, w: kStatusWidth, h: Double(kDockHeight))
        case .top:
            return CcRect(x: ShellScreen.logicalWidth - kStatusWidth, y: 0,
                          w: kStatusWidth, h: Double(kDockHeight))
        case .left:
            return CcRect(x: 0, y: ShellScreen.logicalHeight - kStatusHeight,
                          w: Double(kDockHeight), h: kStatusHeight)
        case .right:
            return CcRect(x: stripOffset,
                          y: ShellScreen.logicalHeight - kStatusHeight,
                          w: Double(kDockHeight), h: kStatusHeight)
        }
    }

    /// The clock's slice of the status cluster — pressing it opens the
    /// notification centre, exactly the split the native taskbar makes: the
    /// icons open Quick Settings, the clock opens the calendar. Wide enough
    /// for "11:02 Thu 20 Aug" plus the edge padding; zero on a vertical
    /// dock, where the whole cluster stays on Quick Settings.
    private var acOpener: CcRect {
        let w = 126.0
        switch bloc.state.edge {
        case .bottom:
            return CcRect(x: ShellScreen.logicalWidth - w,
                          y: stripOffset, w: w, h: Double(kDockHeight))
        case .top:
            return CcRect(x: ShellScreen.logicalWidth - w, y: 0,
                          w: w, h: Double(kDockHeight))
        case .left, .right:
            return CcRect(x: 0, y: 0, w: 0, h: 0)
        }
    }

    /// A tile press. Toggles stay open, launches close — the native panel's
    /// own behaviour, and the reason `closes` is on the tile rather than
    /// decided here.
    private func ccTapped(_ index: Int) {
        let tiles = qsTiles
        guard index < tiles.count, tiles[index].available else { return }
        switch tiles[index].action {
        case .toggleWifi:
            bloc.add(.toggleWifi)
        case .toggleNightLight:
            bloc.add(.toggleNightLight)
        case .open(let surface):
            bloc.add(.openSystemSurface(surface))
        }
        if tiles[index].closes { controlCentreOpen = false }
    }

    /// The drawn track inside a slider zone: clear of the 34pt the leading
    /// glyph keeps. The zone is the hit target; the track is the ruler the
    /// percentage is measured against, so a press on the glyph reads as 0
    /// rather than as a negative number.
    private func qsTrackRect(_ zone: CcRect) -> CcRect {
        CcRect(x: zone.x + 34, y: zone.y, w: zone.w - 34, h: zone.h)
    }

    private func ccSetVolumeFrom(_ x: Double) {
        bloc.add(.setVolume(ccPercent(x, qsTrackRect(ccRects().slider))))
    }

    private func ccSetBrightnessFrom(_ x: Double) {
        guard let zone = ccRects().brightness else { return }
        bloc.add(.setBrightness(ccPercent(x, qsTrackRect(zone))))
    }

    private func ccPercent(_ x: Double, _ track: CcRect) -> Int {
        Int((min(1, max(0, (x - track.x) / track.w)) * 100).rounded())
    }

    /// The Windows 11 flyout palette — shared with the notification centre,
    /// see WinTheme.swift.
    private var qsPalette: WinPalette { WinPalette.of(dark: bloc.state.darkMode) }

    /// One grid cell: the 94x48 button, then its label centred in the space
    /// beneath — two widgets, one rect, exactly the native anatomy.
    private func qsTileWidget(_ index: Int) -> Widget {
        let tile = qsTiles[index]
        let rect = ccRects().tiles[index]
        let p = qsPalette
        let hovered = hoveredQs == .tile(index)
        let fill = !tile.available ? p.button
            : tile.active ? p.accent
            : hovered ? p.buttonHover : p.button
        let stroke = tile.active && tile.available ? p.accent : p.buttonStroke
        let glyph = !tile.available ? p.disabledInk
            : tile.active ? p.onAccent : p.ink
        // The cell is 20pt wider than its button so the label can run past
        // both sides the way the native ones do — drawn wide rather than
        // positioned negative, because a Stack clips at its own box.
        return Positioned(left: rect.x - ccFrame.x - 10, top: rect.y - ccFrame.y) {
            SizedBox(width: rect.w + 20, height: rect.h + 30) {
                Stack(alignment: Alignment.topLeft) {
                    // The button: a 1px stroke under a filled core, because
                    // there is no bordered box primitive here — the outer
                    // rounded box IS the border.
                    Positioned(left: 10, top: 0, width: rect.w, height: rect.h) {
                        ClipRRect(borderRadius: BorderRadius.circular(6)) {
                            ColoredBox(color: stroke) {
                                Padding(padding: EdgeInsets(left: 1, top: 1, right: 1, bottom: 1)) {
                                    ClipRRect(borderRadius: BorderRadius.circular(5)) {
                                        ColoredBox(color: fill) {
                                            Center {
                                                if tile.chevron {
                                                    Row(mainAxisAlignment: .center,
                                                        crossAxisAlignment: .center,
                                                        spacing: 6) {
                                                        MacosIcon(icon: tile.icon, color: glyph, size: 18)
                                                        MacosIcon(icon: FluentIcons.chevronRight,
                                                                  color: glyph, size: 11)
                                                    }
                                                } else {
                                                    MacosIcon(icon: tile.icon, color: glyph, size: 18)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // The label, allowed to run a little wider than its
                    // button the way the native ones do.
                    Positioned(left: 0, top: rect.h + 6, width: rect.w + 20, height: 18) {
                        Center {
                            Text(tile.label,
                                 style: TextStyle(color: tile.available ? p.ink : p.disabledInk,
                                                  fontSize: 12),
                                 overflow: .ellipsis, maxLines: 1)
                        }
                    }
                }
            }
        }
    }

    /// The sliders, drawn rather than composed.
    ///
    /// A `MacosSlider` would want a pan recognizer, and recognizers are
    /// exactly what does not arrive reliably in this surface — so the track,
    /// the fill and the thumb are boxes and the drag is two lines in the
    /// root Listener. It also keeps the slider's geometry in `ccRects`,
    /// where the hit test can see it.
    /// The brightness track, when there is a backlight to move.
    private func ccBrightnessSlider() -> Widget? {
        guard let zone = ccRects().brightness,
              let percent = bloc.state.brightness else { return nil }
        return ccTrack(zone, percent: Double(percent),
                       icon: FluentIcons.brightness)
    }

    private func ccSlider() -> Widget {
        let zone = ccRects().slider
        let percent = Double(bloc.state.volume?.percent ?? 0)
        return ccTrack(zone, percent: percent,
                       icon: (bloc.state.volume?.isMuted ?? false)
                           ? FluentIcons.mute : FluentIcons.volume)
    }

    /// One Win11 slider: leading glyph, a 6pt rounded track filled accent up
    /// to the value, and a solid accent thumb. Both sliders are this; only
    /// glyph and value differ — the native panel colours them identically.
    private func ccTrack(_ zone: CcRect, percent: Double,
                         icon: IconData) -> Widget {
        let p = qsPalette
        let track = qsTrackRect(zone)
        let fraction = min(1, max(0, percent / 100))
        let knob = (track.w - 16) * fraction
        return Positioned(left: zone.x - ccFrame.x, top: zone.y - ccFrame.y) {
            SizedBox(width: zone.w, height: zone.h) {
                Stack(alignment: Alignment.centerLeft) {
                    Align(alignment: Alignment.centerLeft) {
                        MacosIcon(icon: icon, color: p.ink, size: 19)
                    }
                    Positioned(left: 34, top: zone.h / 2 - 3,
                               width: track.w, height: 6) {
                        ClipRRect(borderRadius: BorderRadius.circular(3)) {
                            ColoredBox(color: p.trackRest) { SizedBox(expand: ()) }
                        }
                    }
                    Positioned(left: 34, top: zone.h / 2 - 3,
                               width: max(6, knob + 8), height: 6) {
                        ClipRRect(borderRadius: BorderRadius.circular(3)) {
                            ColoredBox(color: p.accent) { SizedBox(expand: ()) }
                        }
                    }
                    // The thumb: an accent core in a panel-coloured ring, the
                    // native thumb's anatomy.
                    Positioned(left: 34 + knob - 1, top: zone.h / 2 - 9,
                               width: 18, height: 18) {
                        ClipRRect(borderRadius: BorderRadius.circular(9)) {
                            ColoredBox(color: p.button) {
                                Padding(padding: EdgeInsets(left: 3, top: 3, right: 3, bottom: 3)) {
                                    ClipRRect(borderRadius: BorderRadius.circular(6)) {
                                        ColoredBox(color: p.accent) { SizedBox(expand: ()) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// The affordance at the volume slider's right: the output-picker glyph
    /// and chevron the native panel puts there.
    private func ccOutputPicker() -> Widget {
        let rect = ccRects().output
        let p = qsPalette
        let ink = hoveredQs == .output ? p.ink : p.subInk
        return Positioned(left: rect.x - ccFrame.x, top: rect.y - ccFrame.y) {
            SizedBox(width: rect.w, height: rect.h) {
                Row(mainAxisAlignment: .end, crossAxisAlignment: .center, spacing: 3) {
                    MacosIcon(icon: FluentIcons.volume, color: ink, size: 15)
                    MacosIcon(icon: FluentIcons.chevronRight, color: ink, size: 11)
                }
            }
        }
    }

    /// The footer: a hairline, the battery readout when there is a battery,
    /// and the gear. The native bar's whole population.
    private func ccFooter() -> Widget {
        let f = ccFrame
        let footer = ccRects().footer
        let p = qsPalette
        return Positioned(left: 0, top: footer.y - f.y) {
            SizedBox(width: kQsWidth, height: kQsFooterH) {
                Stack(alignment: Alignment.topLeft) {
                    Positioned(left: 0, top: 0, width: kQsWidth, height: 1) {
                        ColoredBox(color: p.divider) { SizedBox(expand: ()) }
                    }
                    if bloc.state.power.hasBattery, let percent = bloc.state.power.percent {
                        Positioned(left: kQsPad, top: 0, width: 120, height: kQsFooterH) {
                            Row(crossAxisAlignment: .center, spacing: 8) {
                                MacosIcon(icon: CupertinoIcons.battery_25_percent,
                                          color: p.ink, size: 20)
                                Text("\(percent)%",
                                     style: TextStyle(color: p.ink, fontSize: 12))
                            }
                        }
                    }
                    Positioned(left: kQsWidth - kQsPad - 32,
                               top: (kQsFooterH - 32) / 2, width: 32, height: 32) {
                        ClipRRect(borderRadius: BorderRadius.circular(4)) {
                            ColoredBox(color: hoveredQs == .gear ? p.rowHover : Color(0x00000000)) {
                                Center {
                                    MacosIcon(icon: FluentIcons.settings,
                                              color: p.ink, size: 16)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Which control the pointer is over, or nil for panel body and outside.
    private func qsHover(_ x: Double, _ y: Double) -> QsHover? {
        let rects = ccRects()
        if rects.gear.contains(x, y) { return .gear }
        if rects.output.contains(x, y) { return .output }
        for (index, tile) in rects.tiles.enumerated() where tile.contains(x, y) {
            return .tile(index)
        }
        return nil
    }

    /// A press while the panel is open. Returns true if the panel consumed it.
    ///
    /// Consuming matters: a press that lands on the panel must not also reach
    /// whatever is behind it, and a press outside must close the panel while
    /// still letting a dock tile take the same click.
    private func handleControlCentre(_ x: Double, _ y: Double) -> Bool {
        let rects = ccRects()
        if let brightness = rects.brightness, brightness.contains(x, y) {
            setState {
                draggingBrightness = true
                ccSetBrightnessFrom(x)
            }
            return true
        }
        if rects.slider.contains(x, y) {
            setState {
                draggingVolume = true
                ccSetVolumeFrom(x)
            }
            return true
        }
        if rects.gear.contains(x, y) {
            setState { controlCentreOpen = false }
            Win32Shell.openSettings()
            return true
        }
        if rects.output.contains(x, y) {
            setState { controlCentreOpen = false }
            bloc.add(.openSystemSurface("ms-settings:sound"))
            return true
        }
        for (index, tile) in rects.tiles.enumerated() where tile.contains(x, y) {
            setState { ccTapped(index) }
            return true
        }
        // Inside the panel but on nothing: swallow it, so a click on the
        // panel's own background does not close it.
        if ccFrame.contains(x, y) { return true }
        // Outside: close, and let the press carry on to whatever it hit.
        setState {
            controlCentreOpen = false
            hoveredQs = nil
        }
        return false
    }

    private func controlCentre() -> Widget {
        let frame = ccFrame
        // left/TOP, not left/bottom. `bottom:` had to be derived from the
        // window's height, and that was written as the strip plus the
        // overhang — true only while the dock was always a horizontal bar. On
        // a vertical dock the window is as tall as the SCREEN, so the panel
        // was positioned several hundred points below the window and never
        // appeared at all: the readout looked like a dead button.
        //
        // `ccFrame` is already in window coordinates for every edge, so
        // placing by its top-left needs no window height and cannot disagree
        // with the hit test that uses the same rectangle.
        let p = qsPalette
        return Positioned(left: frame.x, top: frame.y) {
            SizedBox(width: frame.w, height: frame.h) {
                // The 1px stroke is the outer box; the panel is inset inside
                // it — the same trick as the buttons, for the same lack of a
                // bordered-box primitive.
                ClipRRect(borderRadius: BorderRadius.circular(kQsRadius)) {
                    ColoredBox(color: p.stroke) {
                        Padding(padding: EdgeInsets(left: 1, top: 1, right: 1, bottom: 1)) {
                            ClipRRect(borderRadius: BorderRadius.circular(kQsRadius - 1)) {
                                ColoredBox(color: p.panel) {
                                    Stack(alignment: Alignment.topLeft) {
                                        for index in 0..<qsTiles.count {
                                            qsTileWidget(index)
                                        }
                                        if let brightness = ccBrightnessSlider() { brightness }
                                        ccSlider()
                                        ccOutputPicker()
                                        ccFooter()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - The status cluster
    //
    // Read from the system (`Win32Status`), not drawn: a shell with a fixed
    // wifi glyph and a fixed battery glyph is a picture of a status bar. All
    // three moved down here when the menu bar went away, because this is
    // where Windows keeps them and where the user will look.


    /// Wi-Fi with a slash when nothing is connected, and the aerial glyph for
    /// Ethernet — a wifi symbol on a desk machine is a lie the user cannot
    /// correct. Signal is shown as a colour rather than as bars: the icon
    /// font has one wifi glyph, and a faded one reads as weak without
    /// inventing a bar chart.
    /// The network readout: four ascending bars for Wi-Fi, a glyph for a
    /// cable.
    ///
    /// Bars rather than the arc glyph because an arc has one shape and a
    /// number to convey — you can tell "connected" from it but not "barely".
    /// Four bars read at a glance and are what every phone and every other
    /// desktop uses for the same job.
    ///
    /// Ethernet keeps a glyph: bars mean signal strength, and a cable does
    /// not have any. Drawing four full bars for it would be a lie that
    /// happens to look tidy.
    private func networkIcon() -> Widget? {
        let network = bloc.state.network
        guard network.kind != .ethernet else {
            return MacosIcon(icon: FluentIcons.network,
                             color: Color(0xFFD5DAE3), size: 15)
        }
        // Nothing at all on a machine with no Wi-Fi. An empty signal meter on
        // a desktop is a readout about hardware that is not there — the same
        // reason the battery draws nothing rather than an empty cell.
        guard network.hasWifiAdapter else { return nil }
        let signal = network.kind == .none ? 0 : network.signal
        // Quarters, so a bar lights when the signal is genuinely into that
        // band rather than at the boundary of it.
        let lit = signal >= 75 ? 4 : signal >= 50 ? 3 : signal >= 25 ? 2 : signal > 0 ? 1 : 0
        return SizedBox(width: 18, height: 15) {
            Stack(alignment: Alignment.bottomLeft) {
                for i in 0..<4 {
                    Positioned(left: Double(i) * 5, top: 15 - kBarHeights[i],
                               width: 3, height: kBarHeights[i]) {
                        ClipRRect(borderRadius: BorderRadius.circular(1.5)) {
                            ColoredBox(color: i < lit ? Color(0xFFD5DAE3)
                                                      : Color(0x30FFFFFF)) {
                                SizedBox(expand: ())
                            }
                        }
                    }
                }
            }
        }
    }

    /// Nothing at all on a desktop. An empty battery outline on a machine
    /// with no battery is worse than no icon: it reads as "flat".
    private func batteryWidgets() -> [Widget] {
        guard bloc.state.power.hasBattery else { return [] }
        let percent = bloc.state.power.percent ?? 100
        let charging = bloc.state.power.isCharging
        let fraction = min(1.0, max(0.0, Double(percent) / 100))
        // Red only when it is BOTH low and not being fixed: a machine at 8%
        // on the charger is not a warning, and colouring it as one teaches
        // people to ignore the colour.
        let fill = charging ? Color(0xFF5FD07A)
            : percent <= 10 ? Color(0xFFFF6B6B)
            : percent <= 25 ? Color(0xFFF0B24A)
            : Color(0xFFD5DAE3)

        // Drawn rather than a glyph, for the reason the Wi-Fi bars are: the
        // battery glyphs come in four steps, so a level is rounded to the
        // nearest quarter before it is ever shown. A bar can just be the
        // number.
        let meter = SizedBox(width: 30, height: 15) {
            Stack(alignment: Alignment.centerLeft) {
                // The shell of the battery.
                Positioned(left: 0, top: 1, width: 25, height: 13) {
                    ClipRRect(borderRadius: BorderRadius.circular(4)) {
                        ColoredBox(color: Color(0x30FFFFFF)) { SizedBox(expand: ()) }
                    }
                }
                // The charge in it. Never narrower than a sliver, so an
                // almost-flat battery still reads as a battery.
                Positioned(left: 2, top: 3, width: max(3, 21 * fraction), height: 9) {
                    ClipRRect(borderRadius: BorderRadius.circular(2.5)) {
                        ColoredBox(color: fill) { SizedBox(expand: ()) }
                    }
                }
                // The terminal nub, which is what makes the shape a battery
                // rather than a progress bar.
                Positioned(left: 26, top: 5, width: 3, height: 5) {
                    ClipRRect(borderRadius: BorderRadius.circular(1.5)) {
                        ColoredBox(color: Color(0x50FFFFFF)) { SizedBox(expand: ()) }
                    }
                }
                if charging {
                    Positioned(left: 8, top: 0, width: 11, height: 15) {
                        MacosIcon(icon: FluentIcons.bolt,
                                  color: Color(0xFF14161A), size: 11)
                    }
                }
            }
        }
        return [meter,
                Text("\(percent)%",
                     style: TextStyle(color: Color(0xFFB0B7C3), fontSize: 12))]
    }

    /// Other people's icons. The shell draws them and forwards presses; it
    /// never decides what one means.
    private func trayCluster() -> Widget {
        let icons = promotedTray
        if vertical {
            return SizedBox(width: Double(kDockHeight), height: trayLength) {
                Column(mainAxisSize: .min, crossAxisAlignment: .center) {
                    if showsTrayChevron { trayChevron() }
                    for icon in icons { trayTile(icon) }
                }
            }
        }
        return SizedBox(width: trayLength, height: Double(kDockHeight)) {
            Row(mainAxisSize: .min, crossAxisAlignment: .center) {
                if showsTrayChevron { trayChevron() }
                for icon in icons { trayTile(icon) }
            }
        }
    }

    /// The chevron, pointing the way the flyout will open — up from a bottom
    /// dock, as on Windows, and outward from a dock down a side.
    private func trayChevron() -> Widget {
        let glyph: IconData
        switch bloc.state.edge {
        case .bottom: glyph = FluentIcons.chevronUp
        case .top: glyph = FluentIcons.chevronDown
        case .left: glyph = FluentIcons.chevronRight
        case .right: glyph = FluentIcons.chevronLeft
        }
        return SizedBox(width: kTrayCell, height: kTrayCell) {
            Center {
                MacosIcon(icon: glyph, color: Color(0xFFE6EAF0), size: 13)
            }
        }
    }

    /// The icons Windows keeps behind the chevron, in a grid over the strip.
    private func trayOverflow() -> Widget {
        let icons = hiddenTray
        let cols = min(icons.count, kTrayFlyoutCols)
        let rows = (icons.count + kTrayFlyoutCols - 1) / kTrayFlyoutCols
        let width = Double(cols) * kTrayFlyoutCell + kTrayFlyoutPad * 2
        let height = Double(rows) * kTrayFlyoutCell + kTrayFlyoutPad * 2
        let origin = flyoutOrigin(centre: trayCellCentre(0), width: width, height: height)
        return Positioned(left: origin.x, top: origin.y,
                          child: ClipRRect(borderRadius: BorderRadius.circular(8)) {
                ColoredBox(color: Color(0xF01B1D22)) {
                    SizedBox(width: width, height: height) {
                        Padding(padding: EdgeInsets(left: kTrayFlyoutPad, top: kTrayFlyoutPad,
                                                    right: kTrayFlyoutPad, bottom: kTrayFlyoutPad)) {
                            Column(mainAxisSize: .min, crossAxisAlignment: .start) {
                                for row in 0..<max(rows, 1) {
                                    Row(mainAxisSize: .min, crossAxisAlignment: .center) {
                                        for col in 0..<cols {
                                            let i = row * kTrayFlyoutCols + col
                                            if i < icons.count {
                                                trayOverflowTile(icons[i])
                                            } else {
                                                SizedBox(width: kTrayFlyoutCell,
                                                         height: kTrayFlyoutCell)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            })
    }

    private func trayOverflowTile(_ icon: Win32TrayIcon) -> Widget {
        SizedBox(width: kTrayFlyoutCell, height: kTrayFlyoutCell) {
            Center {
                if let view = bloc.icons.view(DockBloc.trayKey(icon), side: kTrayIcon) {
                    view
                } else {
                    ClipRRect(borderRadius: BorderRadius.circular(3)) {
                        ColoredBox(color: Color(0x22FFFFFF)) {
                            SizedBox(width: kTrayIcon, height: kTrayIcon)
                        }
                    }
                }
            }
        }
    }

    /// A press while the overflow is down. True when it consumed the press.
    ///
    /// Arithmetic against the SAME origin the drawing uses, for the reason
    /// every other flyout in this surface is: widget-level input does not
    /// arrive reliably here, and two independent layouts drift into dead rows.
    private func handleTrayOverflow(_ x: Double, _ y: Double, right: Bool) -> Bool {
        let icons = hiddenTray
        guard trayOverflowOpen, !icons.isEmpty else { return false }
        let cols = min(icons.count, kTrayFlyoutCols)
        let rows = (icons.count + kTrayFlyoutCols - 1) / kTrayFlyoutCols
        let width = Double(cols) * kTrayFlyoutCell + kTrayFlyoutPad * 2
        let height = Double(rows) * kTrayFlyoutCell + kTrayFlyoutPad * 2
        let origin = flyoutOrigin(centre: trayCellCentre(0), width: width, height: height)
        guard x >= origin.x, x < origin.x + width,
              y >= origin.y, y < origin.y + height else {
            // Outside closes it, and the press carries on to whatever it hit —
            // which is what Windows' own overflow does.
            setState { trayOverflowOpen = false }
            // The chevron is the exception, and it has to be CONSUMED: let
            // this press carry on and the caller's toggle reopens the flyout
            // it just closed, in the same press. That is what made a second
            // click on the chevron look like a chevron that does nothing.
            if case .chevron? = trayHit(x, y) { return true }
            return false
        }
        let col = Int((x - origin.x - kTrayFlyoutPad) / kTrayFlyoutCell)
        let row = Int((y - origin.y - kTrayFlyoutPad) / kTrayFlyoutCell)
        let index = row * kTrayFlyoutCols + col
        if col >= 0, col < cols, row >= 0, index >= 0, index < icons.count {
            setState { trayOverflowOpen = false }
            // The app is about to take the foreground from us to raise its
            // own menu; do not hand the keyboard back over its head.
            flyoutFocusHandsOn = true
            bloc.add(.trayClick(icons[index].id, right ? .right : .left))
        }
        return true
    }

    private func trayTile(_ icon: Win32TrayIcon) -> Widget {
        SizedBox(width: kTrayCell, height: kTrayCell) {
            Center {
                // The picture arrives a beat after the icon does — it is
                // rasterized on the cache's queue — and the placeholder holds
                // the cell so the strip does not reflow underneath the
                // pointer as they land.
                if let view = bloc.icons.view(DockBloc.trayKey(icon), side: kTrayIcon) {
                    view
                } else {
                    ClipRRect(borderRadius: BorderRadius.circular(3)) {
                        ColoredBox(color: Color(0x22FFFFFF)) {
                            SizedBox(width: kTrayIcon, height: kTrayIcon)
                        }
                    }
                }
            }
        }
    }

    private func statusCluster() -> Widget {
        // A fixed extent, imposed rather than measured — `ccOpener` hit-tests
        // against this same number, and a readout that laid itself out to its
        // content would drift away from the rectangle that opens the panel.
        if vertical { return verticalStatusCluster() }
        return SizedBox(width: kStatusWidth, height: Double(kDockHeight)) {
        Padding(padding: EdgeInsets(left: 0, top: 0, right: 16, bottom: 0)) {
            Row(mainAxisAlignment: .end, crossAxisAlignment: .center, spacing: 9) {
                if let network = networkIcon() { network }
                for widget in batteryWidgets() { widget }
                Padding(padding: EdgeInsets(left: 4, top: 0, right: 0, bottom: 0)) {
                    DockClock(format: "h:mm  EEE d MMM",
                              style: TextStyle(color: Color(0xFFFFFFFF),
                                               fontSize: 13))
                }
            }
        }
        }
    }

    /// The same readout down a column: the icons stacked, and the clock split
    /// over two lines because 56pt of width will not hold "12:21 Wed 19 Aug".
    private func verticalStatusCluster() -> Widget {
        SizedBox(width: Double(kDockHeight), height: kStatusHeight) {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 10)) {
                Column(mainAxisAlignment: .end, crossAxisAlignment: .center,
                       spacing: 7) {
                    if let network = networkIcon() { network }
                    for widget in batteryWidgets() { widget }
                    DockClock(format: "H:mm",
                              style: TextStyle(color: Color(0xFFFFFFFF),
                                               fontSize: 13))
                    DockClock(format: "d MMM",
                              style: TextStyle(color: Color(0xFF9AA3B0),
                                               fontSize: 10))
                }
            }
        }
    }

    // MARK: - Geometry

    /// The icons Windows itself would put on the bar, and the ones it keeps
    /// behind the chevron. The user chose this, per icon, in Windows' own
    /// Settings — showing everything instead is not "more helpful", it is a
    /// strip that disagrees with the taskbar it replaced.
    private var promotedTray: [Win32TrayIcon] { bloc.state.tray.filter(\.isPromoted) }
    private var hiddenTray: [Win32TrayIcon] { bloc.state.tray.filter { !$0.isPromoted } }

    /// Windows shows no chevron when there is nothing behind it.
    private var showsTrayChevron: Bool { !hiddenTray.isEmpty }

    /// How far the notification area runs along the strip: the chevron, if
    /// there is one, then the promoted icons.
    private var trayLength: Double {
        Double(promotedTray.count + (showsTrayChevron ? 1 : 0)) * kTrayCell
    }

    /// What a press in the notification area landed on.
    private enum TrayTarget {
        case chevron
        case icon(Win32TrayIcon)
    }

    /// The notification area's rectangle, immediately inboard of the status
    /// readout — where Windows puts it, between the running apps and the
    /// clock. Arithmetic for the same reason every other rectangle here is:
    /// the press arrives at a root Listener, not at the widget.
    private var trayRect: CcRect {
        switch bloc.state.edge {
        case .bottom:
            return CcRect(x: ShellScreen.logicalWidth - kStatusWidth - trayLength,
                          y: stripOffset, w: trayLength, h: Double(kDockHeight))
        case .top:
            return CcRect(x: ShellScreen.logicalWidth - kStatusWidth - trayLength,
                          y: 0, w: trayLength, h: Double(kDockHeight))
        case .left:
            return CcRect(x: 0,
                          y: ShellScreen.logicalHeight - kStatusHeight - trayLength,
                          w: Double(kDockHeight), h: trayLength)
        case .right:
            return CcRect(x: stripOffset,
                          y: ShellScreen.logicalHeight - kStatusHeight - trayLength,
                          w: Double(kDockHeight), h: trayLength)
        }
    }

    /// Which tray icon a point is over, or nil.
    /// Where a cell's centre is along the strip — what a tooltip or the
    /// overflow flyout hangs off. Cell 0 is the chevron when there is one.
    private func trayCellCentre(_ cell: Int) -> Double {
        let rect = trayRect
        return (vertical ? rect.y : rect.x) + (Double(cell) + 0.5) * kTrayCell
    }

    private func trayCentre(_ icon: Win32TrayIcon) -> Double {
        guard let index = promotedTray.firstIndex(where: { $0.id == icon.id })
        else { return trayCellCentre(0) }
        return trayCellCentre(index + (showsTrayChevron ? 1 : 0))
    }

    /// What a point in the notification area is over, or nil.
    private func trayHit(_ x: Double, _ y: Double) -> TrayTarget? {
        let rect = trayRect
        guard rect.w > 0, rect.h > 0, rect.contains(x, y) else { return nil }
        let along = vertical ? (y - rect.y) : (x - rect.x)
        var index = Int(along / kTrayCell)
        guard index >= 0 else { return nil }
        if showsTrayChevron {
            if index == 0 { return .chevron }
            index -= 1
        }
        let icons = promotedTray
        guard index < icons.count else { return nil }
        return .icon(icons[index])
    }

    /// Which tile a point in the panel is over, or nil.
    ///
    /// Hit-tested by ARITHMETIC, from a Listener at the root, because the two
    /// widget-level routes both come up empty on this framework:
    /// `MouseRegion.onEnter`/`onExit` never fire, and `onSecondaryTap` never
    /// fires either — even though the raw events are demonstrably arriving
    /// (a root Listener sees `hover` and sees `down buttons=2`). Recognizers
    /// and mouse-tracker annotations are the missing link, not the host. The
    /// tile is a fixed size and the row is centred, so doing it here costs
    /// four lines and no layout query.
    private func pointerTile(_ x: Double, _ y: Double) -> Int? {
        guard !bloc.state.items.isEmpty else { return nil }
        // The window is the strip PLUS the overhang, and the overhang is a
        // hole — a press there is not on the dock at all. Which side of the
        // window the strip occupies depends on the edge.
        let along: Double
        let across: Double
        switch bloc.state.edge {
        case .bottom: along = x; across = y - Double(dockOverhang)
        case .top:    along = x; across = Double(kDockHeight) - y
        case .left:   along = y; across = Double(kDockHeight) - x
        case .right:  along = y; across = x - Double(dockOverhang)
        }
        guard across >= 0, across <= Double(kDockHeight) else { return nil }

        let start = rowLeft()
        let index = Int((along - start) / kDockTile)
        guard along >= start, index >= 0, index < bloc.state.items.count else { return nil }
        return index
    }

    /// Where the centred row of tiles starts, in the panel's own coordinates.
    ///
    /// `ShellScreen`, not `Win32Display.primary()`: the width has to be the
    /// width of the screen this bar is ON, and it has to follow a resolution
    /// change — the host re-places the strip on WM_DISPLAYCHANGE and the
    /// icons have to be centred on the new one.
    /// The window's own thickness in points: the strip plus the overhang.
    private var windowThickness: Double { Double(kDockHeight + dockOverhang) }

    /// Where the strip starts within the window, across the axis. The
    /// overhang is on the far side of the strip from the screen edge, so it
    /// leads on a bottom or right dock and trails on a top or left one.
    private var stripOffset: Double {
        switch bloc.state.edge {
        case .bottom, .right: return Double(dockOverhang)
        case .top, .left: return 0
        }
    }

    /// True when the dock is a column down a side rather than a bar along an
    /// edge. Everything below asks this rather than assuming a horizontal
    /// strip, which is what the whole surface used to do.
    private var vertical: Bool { bloc.state.isVertical }

    /// How long the dock is along its own axis — the screen's width for a
    /// bar, its height for a column.
    private var axisLength: Double {
        vertical ? ShellScreen.logicalHeight : ShellScreen.logicalWidth
    }

    /// Where the row (or column) of icons starts.
    ///
    /// Centred means centred on the SCREEN rather than in the space left over
    /// beside the clock — which is also what keeps `tileCentre` arithmetic
    /// instead of a layout query. Flush to the start means exactly that: the
    /// launcher tile at the screen's own edge, where the Start button was
    /// before Windows 11 moved it.
    ///
    /// This is the hit test's idea of where the icons are, and `barBody`
    /// draws them. The two have to agree, so both read this setting and
    /// nothing else decides it.
    private func rowLeft() -> Double {
        switch bloc.state.alignment {
        case .start:  return 0
        case .center: return (axisLength - Double(bloc.state.items.count) * kDockTile) / 2
        }
    }

    /// Where a tile's centre sits. The tile is a fixed size and the row is
    /// centred, so this is arithmetic — no measuring, which is what lets a
    /// flyout be positioned over an icon without a layout pass to ask where
    /// it ended up.
    private func tileCentre(_ index: Int) -> Double {
        rowLeft() + Double(index) * kDockTile + kDockTile / 2
    }

    // MARK: - Build

    private func hairline() -> Widget {
        ColoredBox(color: Color(0x24FFFFFF)) { SizedBox(expand: ()) }
    }

    /// The strip's contents: the icons centred on the screen, and the status
    /// readout at the far end. A Row along an edge, a Column down a side.
    private func barBody() -> Widget {
        ColoredBox(color: Color(0xF01B1D22)) {
            Stack(alignment: Alignment.center) {
                // Centred (Windows 11) or flush to the start (Windows 10),
                // on the SCREEN rather than in the space left over — which is
                // also what makes tileCentre arithmetic rather than a layout
                // query. `rowLeft` is the same decision in numbers; if these
                // two ever disagree the icons draw in one place and answer
                // clicks in another.
                Align(alignment: bloc.state.alignment == .start
                          ? (vertical ? Alignment.topCenter : Alignment.centerLeft)
                          : Alignment.center) {
                    if vertical {
                        Column(mainAxisSize: .min, crossAxisAlignment: .center) {
                            for (index, item) in bloc.state.items.enumerated() {
                                tile(item, index)
                            }
                        }
                    } else {
                        Row(mainAxisSize: .min, crossAxisAlignment: .center) {
                            for (index, item) in bloc.state.items.enumerated() {
                                tile(item, index)
                            }
                        }
                    }
                }
                // The far end from where the eye starts: the right of a bar,
                // the bottom of a column.
                Align(alignment: vertical ? Alignment.bottomCenter
                                          : Alignment.centerRight) {
                    statusCluster()
                }
                // The notification area, inboard of the readout. The padding
                // is what puts it there: the Align fills the strip minus the
                // readout's fixed extent, so the icons end where the clock's
                // cluster begins — which is the rectangle `trayRect` tests.
                Padding(padding: vertical
                        ? EdgeInsets(left: 0, top: 0, right: 0, bottom: kStatusHeight)
                        : EdgeInsets(left: 0, top: 0, right: kStatusWidth, bottom: 0)) {
                    Align(alignment: vertical ? Alignment.bottomCenter
                                              : Alignment.centerRight) {
                        trayCluster()
                    }
                }
            }
        }
    }

    private func tile(_ item: DockItem, _ index: Int) -> Widget {
        // Only the primary tap lives on the tile. Hover and the right-click
        // menu are driven from a Listener at the root instead — see the note
        // on `pointerTile`.
        //
        // THE LAUNCHER OPENS ON PRESS, everything else on release.
        //
        // That is what Windows' own taskbar does with Start, and it is worth
        // more than anything left in the drawing path: the launcher's pixels
        // arrive two frames after the toggle is posted, ~34ms, of which our
        // own code is about one — but a click is not a moment, it is a press
        // and a release with a person in between, and that gap is tens of
        // milliseconds. Opening on the press spends it usefully. Every other
        // tile keeps release, because launching or raising an app on the way
        // DOWN would fire on a press the user was about to drag out of.
        let launcher = item.key == kLauncherKey
        return GestureDetector(
                onTapDown: launcher
                    ? { _ in self.setState { self.menuOpen = nil }; self.bloc.add(.activate(item)) }
                    : nil,
                onTap: launcher
                    ? nil
                    : { self.setState { self.menuOpen = nil }; self.bloc.add(.activate(item)) },
                child: Padding(padding: EdgeInsets(left: 7, top: 0, right: 7, bottom: 0)) {
                    Column(mainAxisSize: .min, crossAxisAlignment: .center) {
                        if item.key == kLauncherKey {
                            SizedBox(width: kDockIcon, height: kDockIcon) {
                                ClipRRect(borderRadius: BorderRadius.circular(10)) {
                                    ColoredBox(color: Color(0xFF2B3550)) {
                                        Center {
                                            MacosIcon(icon: FluentIcons.allApps,
                                                      color: Color(0xFF9EC2FF), size: 21)
                                        }
                                    }
                                }
                            }
                        } else if let icon = bloc.icons.view(item.key, side: kDockIcon) {
                            icon
                        } else {
                            SizedBox(width: kDockIcon, height: kDockIcon) {
                                Center {
                                    MacosIcon(icon: FluentIcons.appDefault,
                                              color: Color(0xFFB8C0CC), size: 21)
                                }
                            }
                        }
                        // The running indicator: one dot per window, up to
                        // three, brighter when the app has focus. A dot
                        // rather than a highlight behind the icon, so the
                        // app's own artwork stays the thing the eye lands on
                        // — and counting them is how a glance tells four
                        // documents from one.
                        SizedBox(height: 7) {
                            Center {
                                Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 3) {
                                    for _ in 0..<min(item.windows.count, 3) {
                                        ClipRRect(borderRadius: BorderRadius.circular(2.5)) {
                                            ColoredBox(color: item.isForeground
                                                ? Color(0xFFFFFFFF) : Color(0x99FFFFFF)) {
                                                SizedBox(width: 5, height: 5)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                })
    }

    /// The hover label. Drawn in the overhang, above the strip.
    private func label(_ index: Int) -> Widget {
        // `hovered` is only re-derived from the pointer on pointer MOTION,
        // so a rebuild can arrive while it still names a tile that no longer
        // exists: launch an unpinned app, rest the pointer on its transient
        // tile, and when the window goes the tile vanishes under a pointer
        // that never moved. hasPreview/previewWindows guard exactly this;
        // the unguarded subscript here was a shell-down trap (0xC000001D in
        // StarlingDockState.label, dump 7408, 2026-08-26 — index 7, count 7).
        guard index >= 0, index < bloc.state.items.count else {
            return Positioned(left: 0, top: 0,
                              child: SizedBox(width: 0, height: 0))
        }
        let item = bloc.state.items[index]
        // Rough, because the text is not measured: enough to keep a long name
        // roughly centred over its icon rather than hanging off one side.
        let width = Double(item.name.count) * 6.6 + 20
        return flyout(index, width: width, height: 26,
                      child: ClipRRect(borderRadius: BorderRadius.circular(6)) {
                ColoredBox(color: Color(0xF01B1D22)) {
                    Padding(padding: EdgeInsets(left: 10, top: 5, right: 10, bottom: 5)) {
                        Text(item.name,
                             style: TextStyle(color: Color(0xFFE6EAF0), fontSize: 12),
                             maxLines: 1)
                    }
                }
            })
    }

    /// What Windows shows on hover: the app's own tooltip. Without it a tray
    /// icon is a picture with no name, which for the half of them that are
    /// abstract glyphs is no help at all.
    private func trayLabel(_ icon: Win32TrayIcon) -> Widget {
        let text = icon.tooltip.isEmpty ? "Notification icon" : icon.tooltip
        // Unmeasured, like the tile labels, and capped: a tooltip can be a
        // paragraph ("OneDrive - Personal / Not signed in") and a flyout as
        // wide as the screen is worse than one that clips.
        let width = min(Double(text.count) * 6.6 + 20, 320)
        let origin = flyoutOrigin(centre: trayCentre(icon), width: width, height: 26)
        return Positioned(left: origin.x, top: origin.y,
                          child: ClipRRect(borderRadius: BorderRadius.circular(6)) {
                ColoredBox(color: Color(0xF01B1D22)) {
                    SizedBox(width: width, height: 26) {
                        Padding(padding: EdgeInsets(left: 10, top: 5, right: 10, bottom: 5)) {
                            Text(text,
                                 style: TextStyle(color: Color(0xFFE6EAF0), fontSize: 12),
                                 maxLines: 1)
                        }
                    }
                }
            })
    }

    /// What the flyout slot shows. Called from DockFlyoutSlot's build (end of
    /// file); the choice mirrors the old in-tree chain — a menu or the tray
    /// overflow wins and the slot goes empty, a running tile gets its preview
    /// card, a pinned one its name, a tray icon its tooltip.
    fileprivate func flyoutContent() -> Widget {
        let empty = Positioned(left: 0, top: 0,
                               child: SizedBox(width: 0, height: 0))
        if (trayOverflowOpen && !hiddenTray.isEmpty) || menuOpen != nil {
            return empty
        }
        // Bounds-checked because `hovered` can go stale between the pointer
        // resting and the item list shrinking (see label(_:)); a stale index
        // means "the tile under the pointer is gone", and the honest flyout
        // for a tile that is gone is no flyout.
        //
        // The DWM registrations are reconciled HERE, against what this build
        // actually draws, not only when the card opens. The thumbnails are
        // painted by DWM directly over the window, so a registration that
        // outlives its slot keeps showing a picture the tree no longer draws
        // — hover File Explorer, close it, and the card went on showing the
        // closed window's last frame for as long as the pointer stayed put,
        // because nothing between "the window list changed" and "DWM paints"
        // ever re-asked. sync() is a no-op when nothing changed, so the
        // once-a-second clock rebuild pays a dictionary walk and no DWM call.
        if let over = hovered, over >= 0, over < bloc.state.items.count,
           hasPreview(over) {
            if previews.sync(previewWindows(over).map(\.handle)) {
                placePreview(over)
            }
            return preview(over)
        }
        // Every other outcome draws no thumbnails, so none may stay
        // registered — including the stale-index fall-through above.
        previews.releaseAll()
        if let over = hovered, over >= 0, over < bloc.state.items.count {
            return label(over)
        }
        if let id = hoveredTray,
           let icon = bloc.state.tray.first(where: { $0.id == id }) {
            return trayLabel(icon)
        }
        return empty
    }

    /// Whether this tile gets a picture rather than a name: Windows shows a
    /// thumbnail per window for a running app and a plain label for a pinned
    /// one that is not running.
    private func hasPreview(_ index: Int) -> Bool {
        guard index >= 0, index < bloc.state.items.count else { return false }
        return !bloc.state.items[index].windows.isEmpty
    }

    private func previewWindows(_ index: Int) -> [Win32Window] {
        guard index >= 0, index < bloc.state.items.count else { return [] }
        return Array(bloc.state.items[index].windows.prefix(kPreviewMaxCols))
    }

    private func previewSize(_ index: Int) -> (width: Double, height: Double) {
        let count = max(previewWindows(index).count, 1)
        return (Double(count) * (kPreviewThumbW + kPreviewPad) + kPreviewPad,
                kPreviewPad + kPreviewTitleH + kPreviewThumbH + kPreviewPad)
    }

    /// The card, and the picture in it.
    private func preview(_ index: Int) -> Widget {
        let windows = previewWindows(index)
        let size = previewSize(index)
        let origin = flyoutOrigin(index, width: size.width, height: size.height)
        return Positioned(left: origin.x, top: origin.y,
                          child: ClipRRect(borderRadius: BorderRadius.circular(8)) {
                ColoredBox(color: Color(0xF01B1D22)) {
                    SizedBox(width: size.width, height: size.height) {
                        Padding(padding: EdgeInsets(left: kPreviewPad, top: kPreviewPad,
                                                    right: kPreviewPad, bottom: kPreviewPad)) {
                            Row(mainAxisSize: .min, crossAxisAlignment: .start) {
                                for window in windows { previewCell(window, index) }
                            }
                        }
                    }
                }
            })
    }

    private func previewCell(_ window: Win32Window, _ index: Int) -> Widget {
        Padding(padding: EdgeInsets(left: 0, top: 0, right: kPreviewPad, bottom: 0)) {
            Column(mainAxisSize: .min, crossAxisAlignment: .start) {
                SizedBox(width: kPreviewThumbW, height: kPreviewTitleH) {
                    Text(window.title.isEmpty ? "Untitled" : window.title,
                         style: TextStyle(color: Color(0xFFE6EAF0), fontSize: 12),
                         maxLines: 1)
                }
                ClipRRect(borderRadius: BorderRadius.circular(4)) {
                    ColoredBox(color: Color(0xFF11131A)) {
                        SizedBox(width: kPreviewThumbW, height: kPreviewThumbH) {
                            Center {
                                // DELIBERATELY EMPTY.
                                //
                                // DWM paints the picture into this rectangle,
                                // over the top of whatever the tree drew here
                                // — so the slot is a hole, and the dark fill
                                // behind it is what shows through while a
                                // registration is still being made and around
                                // an aspect-fitted picture that does not fill
                                // the slot.
                                //
                                // A minimized window needs no fallback icon any
                                // more: DWM kept its last frame, which is the
                                // whole reason the taskbar can show one.
                                SizedBox(width: kPreviewThumbW, height: kPreviewThumbH)
                            }
                        }
                    }
                }
            }
        }
    }

    /// A press inside the preview card. True when it consumed the press.
    private func handlePreview(_ x: Double, _ y: Double) -> Bool {
        guard let index = hovered, hasPreview(index) else { return false }
        let windows = previewWindows(index)
        let size = previewSize(index)
        let origin = flyoutOrigin(index, width: size.width, height: size.height)
        guard x >= origin.x, x < origin.x + size.width,
              y >= origin.y, y < origin.y + size.height else { return false }
        let column = Int((x - origin.x - kPreviewPad) / (kPreviewThumbW + kPreviewPad))
        guard column >= 0, column < windows.count else { return true }
        closePreview()
        // Raising is the whole point of a preview: it is how you pick between
        // four windows of the same app, which a dock tile alone cannot do.
        let handle = windows[column].handle
        Task.detached { _ = Win32WindowManager.activate(handle) }
        return true
    }

    /// Whether a point is over the open card — which keeps it open. Without
    /// this the card vanishes the moment the pointer leaves the tile to reach
    /// it, and nothing in it can ever be clicked.
    private func overPreview(_ x: Double, _ y: Double) -> Bool {
        guard let index = hovered, hasPreview(index) else { return false }
        let size = previewSize(index)
        let origin = flyoutOrigin(index, width: size.width, height: size.height)
        return x >= origin.x && x < origin.x + size.width &&
               y >= origin.y && y < origin.y + size.height
    }

    /// Registers the card's thumbnails and puts each in its slot.
    ///
    /// Live DWM thumbnails, the same mechanism the native taskbar uses: DWM
    /// already has the pixels and paints them straight over our window, so
    /// there is no capture and no timer. flyoutContent re-syncs the
    /// registrations on every build while the card is up, so a window that
    /// closes under the card stops being painted.
    private func openPreview(_ index: Int) {
        previews.sync(previewWindows(index).map(\.handle))
        placePreview(index)
    }

    /// Puts each registered thumbnail where its slot is.
    ///
    /// The rects are COMPUTED from the same constants the tree lays out with,
    /// not measured from it: the card's origin is `flyoutOrigin` and every
    /// cell is a fixed size, so the arithmetic here and the widths in
    /// `previewCell` are the same two numbers. If one changes the other must —
    /// there is no layout pass to catch a divergence, the picture simply lands
    /// beside its slot.
    ///
    /// Physical pixels, because that is what DWM's destination rect is in.
    private func placePreview(_ index: Int) {
        let windows = previewWindows(index)
        guard !windows.isEmpty else { return }
        let size = previewSize(index)
        let origin = flyoutOrigin(index, width: size.width, height: size.height)
        let scale = ShellScreen.monitor?.scale ?? 2.0
        let top = origin.y + kPreviewPad + kPreviewTitleH
        for (i, window) in windows.enumerated() {
            let left = origin.x + kPreviewPad + Double(i) * (kPreviewThumbW + kPreviewPad)
            previews.place(window.handle,
                           x: Int((left * scale).rounded()),
                           y: Int((top * scale).rounded()),
                           width: Int((kPreviewThumbW * scale).rounded()),
                           height: Int((kPreviewThumbH * scale).rounded()))
        }
    }

    private func closePreview() {
        previews.releaseAll()
        hovered = nil
        flyoutSlot?.poke()
    }

    /// Show (or hide, for nil/nil) the hover flyout, updating only the
    /// flyout slot — the hot path a pointer sweep drives.
    private func showFlyout(_ index: Int?, _ tray: UInt64?) {
        dwellGen += 1
        pendingHover = nil
        pendingTray = nil
        let wasPreviewing = hovered.map(hasPreview) ?? false
        hovered = index
        hoveredTray = tray
        flyoutSlot?.poke()
        armLabelTimeout()
        if let index, hasPreview(index) {
            openPreview(index)
        } else if wasPreviewing {
            // Left a running tile: give the thumbnails back, or DWM keeps
            // painting them over the dock.
            previews.releaseAll()
        }
    }

    /// Arm (or re-arm) the flyout's dismiss timer. Each crossing restarts
    /// the clock; the generation token retires stale timers. The preview
    /// card is exempt — the pointer travels into it to pick a window, and
    /// native previews persist while it is there.
    private func armLabelTimeout() {
        labelTimeoutGen += 1
        let gen = labelTimeoutGen
        guard hovered != nil || hoveredTray != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self, self.labelTimeoutGen == gen else { return }
            if let over = self.hovered, self.hasPreview(over) { return }
            guard self.hovered != nil || self.hoveredTray != nil else { return }
            self.hovered = nil
            self.hoveredTray = nil
            self.flyoutSlot?.poke()
        }
    }

    /// Where a flyout for this tile goes — its top-left corner, in the same
    /// window coordinates a pointer event arrives in.
    ///
    /// ONE formula, used by the drawing AND the hit test, for the reason the
    /// control centre works that way: widget-level input is unreliable in this
    /// surface, so a menu is driven from the root Listener, and two
    /// independent layouts would drift into dead rows.
    ///
    /// This is also what the OVERHANG is for — the window extends past the
    /// strip so there is somewhere to draw, and a flyout on a left dock goes
    /// to the right of it exactly as one on a bottom dock goes above.
    private func flyoutOrigin(_ index: Int, width: Double, height: Double)
        -> (x: Double, y: Double) {
        flyoutOrigin(centre: tileCentre(index), width: width, height: height)
    }

    /// The same formula against an arbitrary point along the strip — what the
    /// notification area's tooltips hang off, since they are not tiles.
    private func flyoutOrigin(centre: Double, width: Double, height: Double)
        -> (x: Double, y: Double) {
        let windowW = vertical ? windowThickness : ShellScreen.logicalWidth
        let windowH = vertical ? ShellScreen.logicalHeight : windowThickness
        switch bloc.state.edge {
        case .bottom:
            return (max(4, centre - width / 2),
                    windowH - Double(kDockHeight) - 6 - height)
        case .top:
            return (max(4, centre - width / 2), Double(kDockHeight) + 6)
        case .left:
            return (Double(kDockHeight) + 6, max(4, centre - 16))
        case .right:
            return (windowW - Double(kDockHeight) - 6 - width,
                    max(4, centre - 16))
        }
    }

    private func flyout(_ index: Int, width: Double, height: Double,
                        child: Widget) -> Widget {
        let origin = flyoutOrigin(index, width: width, height: height)
        return Positioned(left: origin.x, top: origin.y, child: child)
    }

    /// The launcher layer's footprint: Start's own geometry, centred above
    /// the strip — exactly where its floating window sat, now as a child of
    /// this tree (one-view shell).
    private func launcherLayer() -> Widget {
        // Start follows the icons: centred over a centred row, and over the
        // launcher tile when the row is flush to the start — which is what
        // Windows does when the taskbar is left-aligned. Clamped so it cannot
        // run off a narrow screen.
        let x = bloc.state.alignment == .start && !vertical
            ? min(max(rowLeft(), 12), ShellScreen.logicalWidth - kLauncherWidth - 12)
            : (ShellScreen.logicalWidth - kLauncherWidth) / 2
        let y = windowThickness - Double(kDockHeight) - kLauncherGap
            - kLauncherHeight
        return Positioned(left: x, top: y, width: kLauncherWidth,
                          height: kLauncherHeight) {
            StarlingLauncher(embedded: true, onRequestClose: { [weak self] in
                // Launching an app (or a power action) hides Start first —
                // and for a LAYER that means closing the layer, never hiding
                // the host window, which is the whole chrome. No focus
                // hand-back: the thing being launched decides the new owner.
                self?.setLauncherLayer(open: false, handBackFocus: false)
            })
        }
    }

    /// A press while a tile menu is open. True when the menu consumed it.
    private func handleTileMenu(_ x: Double, _ y: Double) -> Bool {
        guard let index = menuOpen else { return false }
        let rows = menuRows(index)
        guard !rows.isEmpty else { return false }
        let width = bloc.state.items[index].key == kLauncherKey ? 200.0 : 168.0
        let height = Double(rows.count) * kMenuRowH + 12
        let origin = flyoutOrigin(index, width: width, height: height)
        guard x >= origin.x, x < origin.x + width,
              y >= origin.y, y < origin.y + height else {
            // Outside: close it, and let the press carry on to whatever it hit.
            setState { menuOpen = nil }
            return false
        }
        let row = Int((y - origin.y - 6) / kMenuRowH)
        if row >= 0 && row < rows.count {
            setState { menuOpen = nil }
            rows[row].action()
        }
        return true
    }

    /// Drawing only. The press is `handleTileMenu`'s, off the root Listener:
    /// a GestureDetector inside a Positioned in a Stack does not fire in this
    /// surface, and a menu whose rows quietly do nothing is worse than none.
    private func menuRow(_ text: String, _ width: Double) -> Widget {
        SizedBox(width: width, height: kMenuRowH) {
            Padding(padding: EdgeInsets(left: 12, top: 0, right: 12, bottom: 0)) {
                Align(alignment: Alignment.centerLeft) {
                    Text(text, style: TextStyle(color: Color(0xFFE6EAF0), fontSize: 12))
                }
            }
        }
    }

    /// The right-click menu, also in the overhang.
    /// What a tile's menu offers. ONE list, used to draw the menu and to hit
    /// test it — see `flyoutOrigin` for why they must not be worked out twice.
    private func menuRows(_ index: Int) -> [DockMenuRow] {
        guard index < bloc.state.items.count else { return [] }
        let item = bloc.state.items[index]

        // The launcher tile carries the DOCK's own menu: where it lives, and
        // whether it lives at all. It hangs there because it is the one tile
        // always present — the app tiles come and go with what is running, and
        // a shell command attached to something that may not be on screen is a
        // command you cannot reach.
        guard item.key != kLauncherKey else {
            // Settings first: it is the thing people come to this menu for
            // that is not about the menu itself.
            var rows = [
                DockMenuRow(label: "     Files") {
                    self.openFiles()
                },
                DockMenuRow(label: "     Settings") {
                    Task.detached { Win32Shell.openSettings() }
                },
            ]
            rows += kDockEdges.map { choice in
                DockMenuRow(label: (bloc.state.edge == choice.edge ? "\u{2713}  " : "     ")
                                + choice.label) { self.bloc.add(.setEdge(choice.edge)) }
            }
            // Where the icons gather along that edge — the taskbar setting
            // Windows keeps under Personalization, in the menu that is already
            // about where this bar lives.
            rows += [(DockAlignment.center, "Icons centred"),
                     (DockAlignment.start, "Icons to the start")].map { choice in
                DockMenuRow(label: (bloc.state.alignment == choice.0 ? "\u{2713}  " : "     ")
                                + choice.1) { self.bloc.add(.setAlignment(choice.0)) }
            }
            rows.append(DockMenuRow(
                label: bloc.state.nativeTaskbarWanted
                    ? "     Hide the Windows taskbar"
                    : "     Show the Windows taskbar") {
                self.bloc.add(.setNativeTaskbar(!self.bloc.state.nativeTaskbarWanted))
            })
            rows.append(DockMenuRow(label: "     Remove the dock") {
                self.bloc.add(.removeDock)
            })
            return rows
        }

        var rows: [DockMenuRow] = [
            DockMenuRow(label: item.isPinned ? "Unpin from dock" : "Pin to dock") {
                self.bloc.add(.togglePin(item))
            }
        ]
        if item.isRunning {
            rows.append(DockMenuRow(
                label: item.windows.count > 1
                    ? "Close \(item.windows.count) windows" : "Close") {
                self.bloc.add(.closeAll(item))
            })
        }
        if let app = item.app {
            rows.append(DockMenuRow(label: "New window") {
                Task.detached { Win32AppCatalog.launch(app) }
            })
        }
        return rows
    }

    private func menu(_ index: Int) -> Widget {
        let rows = menuRows(index)
        guard !rows.isEmpty else { return SizedBox(width: 0, height: 0) }
        let width = bloc.state.items[index].key == kLauncherKey ? 200.0 : 168.0
        let height = Double(rows.count) * kMenuRowH + 12
        // A fixed width, and .start rather than .stretch: a Positioned child
        // in a Stack is laid out LOOSE, so its width constraint is infinity,
        // and a stretching Column in infinite width lays out to nothing at all
        // — the menu simply never appears, with no error and no clue that
        // layout is what refused it.
        return flyout(index, width: width, height: height,
                      child: SizedBox(width: width, height: height) {
            ClipRRect(borderRadius: BorderRadius.circular(8)) {
                ColoredBox(color: Color(0xF41F2229)) {
                    Padding(padding: EdgeInsets(left: 0, top: 6, right: 0, bottom: 6)) {
                        Column(mainAxisSize: .min, crossAxisAlignment: .start) {
                            for row in rows { menuRow(row.label, width) }
                        }
                    }
                }
            }
        })
    }

    override func build(_ context: any BuildContext) -> Widget {
        // Every read of `bloc.state` below is registered here, so anything the
        // bloc publishes — the catalog landing, a status tick, an icon texture
        // arriving on its own queue — rebuilds this surface without the widget
        // knowing which of them it was.
        return withObservationTracking {
            _buildContent()
        } onChange: { [weak self] in
            guard let self, self.mounted else { return }
            self.setState {}
        }
    }

    private func _buildContent() -> Widget {
        // Rechecked here, where the width is about to be used: a resolution
        // change moves the strip under us and the centring is arithmetic off
        // that width. This build runs once a second anyway, for the clock,
        // so `pointerTile` is never reading a stale screen for long.
        ShellScreen.refresh()
        // The window is the strip PLUS the overhang. The strip is an opaque
        // bar across the bottom; the overhang above it is painted pure black,
        // which the panel's colour key turns into a hole — invisible and
        // click-through until a label or a menu draws there.
        return Directionality(
            textDirection: .ltr,
            child: Listener(
                onPointerDown: { e in
                    // Every branch below can open or close a flyout, and half
                    // of them return early; the panel's activation follows
                    // whatever this press left open (see syncFlyoutFocus).
                    defer {
                        self.syncFlyoutFocus(
                            handBackFocus: !self.flyoutFocusHandsOn)
                        self.flyoutFocusHandsOn = false
                    }
                    let x = e.position.dx, y = e.position.dy
                    // The notification area first, and with both buttons: a
                    // tray icon's right-click menu is the whole point of most
                    // of them, and it belongs to the app, not to the dock's
                    // own tile menu.
                    // The overflow first: while it is down it owns every
                    // press, including the one that closes it.
                    if self.trayOverflowOpen,
                       self.handleTrayOverflow(x, y, right: e.buttons == 2) {
                        return
                    }
                    if let target = self.trayHit(x, y) {
                        self.setState {
                            self.menuOpen = nil
                            self.controlCentreOpen = false
                        }
                        switch target {
                        case .chevron:
                            self.setState { self.trayOverflowOpen.toggle() }
                        case .icon(let icon):
                            self.setState { self.trayOverflowOpen = false }
                            self.flyoutFocusHandsOn = true
                            self.bloc.add(.trayClick(icon.id, e.buttons == 2 ? .right : .left))
                        }
                        return
                    }
                    // 2 is the secondary button. A press, not a release: the
                    // press is what arrives reliably here, and a menu that
                    // opens on press is what every desktop does anyway.
                    if e.buttons == 2 {
                        let index = self.pointerTile(x, y)
                        self.setState {
                            self.menuOpen = (self.menuOpen == index) ? nil : index
                        }
                        return
                    }
                    // The preview card, before the tile menu: it is drawn
                    // over the overhang and a press in it means "raise that
                    // window", not "the pointer left the tile".
                    if self.handlePreview(x, y) { return }
                    if self.menuOpen != nil, self.handleTileMenu(x, y) { return }
                    if self.controlCentreOpen, self.handleControlCentre(x, y) { return }
                    // The clock before the rest of the cluster — its slice
                    // sits inside ccOpener's rectangle.
                    if self.acOpener.contains(x, y) {
                        self.setState {
                            self.controlCentreOpen = false
                            self.menuOpen = nil
                        }
                        Win32Shell.toggleOverlay(channel: "notifications")
                        return
                    }
                    if self.ccOpener.contains(x, y) {
                        self.setState {
                            self.controlCentreOpen.toggle()
                            self.menuOpen = nil
                        }
                        // The panel shows volume, power and network in full;
                        // it opens on a fresh read rather than on whatever
                        // the background poll last saw.
                        if self.controlCentreOpen { self.bloc.add(.tick) }
                    }
                },
                onPointerMove: { e in
                    // The slider's drag, in one line. A pan recognizer would
                    // be the widget-level answer and is exactly what does not
                    // arrive reliably in this surface.
                    if self.draggingBrightness {
                        self.setState { self.ccSetBrightnessFrom(e.position.dx) }
                    } else if self.draggingVolume {
                        self.setState { self.ccSetVolumeFrom(e.position.dx) }
                    }
                },
                onPointerUp: { _ in
                    guard self.draggingVolume || self.draggingBrightness else { return }
                    self.setState {
                        self.draggingVolume = false
                        self.draggingBrightness = false
                    }
                },
                onPointerHover: { e in
                    let x = e.position.dx, y = e.position.dy
                    // The open panel first: its buttons want the hover, and
                    // the dock's tiles are under it anyway.
                    if self.controlCentreOpen {
                        let over = self.qsHover(x, y)
                        if over != self.hoveredQs {
                            self.setState { self.hoveredQs = over }
                        }
                    } else if self.hoveredQs != nil {
                        self.setState { self.hoveredQs = nil }
                    }
                    // Inside the open card the hover is not about a tile at
                    // all, and re-reading it would clear the very card the
                    // pointer is travelling into.
                    if self.overPreview(x, y) { return }
                    let index = self.pointerTile(x, y)
                    if dockDebug {
                        let has = index.map { self.hasPreview($0) } ?? false
                        let count = index.map { i in
                            i < self.bloc.state.items.count
                                ? self.bloc.state.items[i].windows.count : -1
                        } ?? -1
                        print("[dock] hover \(Int(x)),\(Int(y)) tile=\(index.map(String.init) ?? "-") windows=\(count) preview=\(has) was=\(self.hovered.map(String.init) ?? "-")")
                    }
                    var tray: UInt64? = nil
                    if case .icon(let icon)? = self.trayHit(x, y) {
                        tray = icon.id
                    }
                    // A dwell waits on ONE target: the moment the pointer is
                    // anywhere else — another tile, or off the tiles
                    // entirely (which the guard below would swallow, since
                    // nil equals nil) — retire it, or it fires 400ms later
                    // and raises a flyout under a pointer that has left.
                    if self.pendingHover != nil || self.pendingTray != nil,
                       index != self.pendingHover || tray != self.pendingTray {
                        self.pendingHover = nil
                        self.pendingTray = nil
                        self.dwellGen += 1
                    }
                    guard index != self.hovered || tray != self.hoveredTray else { return }
                    // Native show behaviour, and most of the sweep CPU fix:
                    // a flyout that is already up follows the pointer
                    // immediately (Windows' reshow), but from nothing it
                    // waits out a dwell — so a flick across the dock draws
                    // no flyout frames at all. Without the dwell a fast
                    // sweep re-records the full view per tile crossed
                    // (there are no interior repaint boundaries), ~13% of
                    // a core; with it the sweep costs the event floor.
                    if self.hovered != nil || self.hoveredTray != nil
                        || (index == nil && tray == nil) {
                        self.showFlyout(index, tray)
                    } else {
                        if index == self.pendingHover, tray == self.pendingTray {
                            return    // already dwelling on this target
                        }
                        self.pendingHover = index
                        self.pendingTray = tray
                        self.dwellGen += 1
                        let gen = self.dwellGen
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                            guard let self, self.dwellGen == gen else { return }
                            self.showFlyout(index, tray)
                        }
                    }
                },
                child: ColoredBox(color: Color(0x00000000)) {
                Stack(alignment: Alignment.bottomCenter) {
                    // The bar. Positioned rather than Aligned so it spans the
                    // whole edge whatever it contains — a strip that stops
                    // where its icons stop is the floating slab again.
                    switch bloc.state.edge {
                    case .bottom:
                        Positioned(left: 0, right: 0, bottom: 0,
                                   height: Double(kDockHeight)) { barBody() }
                    case .top:
                        Positioned(left: 0, top: 0, right: 0,
                                   height: Double(kDockHeight)) { barBody() }
                    case .left:
                        Positioned(left: 0, top: 0, bottom: 0,
                                   width: Double(kDockHeight)) { barBody() }
                    case .right:
                        Positioned(top: 0, right: 0, bottom: 0,
                                   width: Double(kDockHeight)) { barBody() }
                    }
                    // A hairline along the strip's inner edge, so the bar
                    // reads as chrome against a window pushed up to it rather
                    // than as part of that window.
                    switch bloc.state.edge {
                    case .bottom:
                        Positioned(left: 0, right: 0, bottom: Double(kDockHeight),
                                   height: 1) { hairline() }
                    case .top:
                        Positioned(left: 0, top: Double(kDockHeight), right: 0,
                                   height: 1) { hairline() }
                    case .left:
                        Positioned(left: Double(kDockHeight), top: 0, bottom: 0,
                                   width: 1) { hairline() }
                    case .right:
                        Positioned(top: 0, right: Double(kDockHeight), bottom: 0,
                                   width: 1) { hairline() }
                    }
                    // ALWAYS emitted, empty when the panel is down: a Stack
                    // that GAINS a child does not always composite the new one
                    // until something else remounts the subtree, which reads
                    // as a button that did nothing. A constant child count
                    // sidesteps the question.
                    if controlCentreOpen {
                        controlCentre()
                    } else {
                        Positioned(left: 0, bottom: 0) { SizedBox(width: 0, height: 0) }
                    }
                    // The launcher LAYER (one-view shell): Start as a child
                    // of this tree, floating above the strip where its own
                    // window used to. Same constant-slot rule as the control
                    // centre above — swap contents, never the child count.
                    if launcherOpen {
                        launcherLayer()
                    } else {
                        Positioned(left: 0, bottom: 0) { SizedBox(width: 0, height: 0) }
                    }
                    // A menu wins over a label: the pointer is inside the tile
                    // for both, and two flyouts stacked on one icon is noise.
                    // (The hover flyouts themselves live in the slot below and
                    // check these flags, so the exclusion holds across both.)
                    if trayOverflowOpen, !hiddenTray.isEmpty {
                        trayOverflow()
                    } else if let open = menuOpen {
                        menu(open)
                    } else {
                        Positioned(left: 0, bottom: 0) { SizedBox(width: 0, height: 0) }
                    }
                    // The hover flyout — label, preview card, tray tooltip —
                    // as its own stateful leaf, so a tile crossing repaints
                    // this slot alone rather than rebuilding the whole
                    // full-screen chrome tree (which was most of the CPU a
                    // pointer sweep along the dock cost).
                    DockFlyoutSlot(dock: self)
                    // The file explorer's context menu as a LAYER
                    // (STARLING_MENU_LAYER=1) — last in the stack, so it
                    // hit-tests above the chrome's own flyouts, and on the
                    // same constant-slot rule as everything above.
                    menuLayerSlot(sub: false)
                    menuLayerSlot(sub: true)
                }
            }))
    }

    /// One panel of the hosted file explorer's menu, drawn in the chrome's
    /// full-screen view at the coordinates the model published.
    ///
    /// MenuPanelSurface is reused exactly as the popup path mounts it: it
    /// draws the panel at its own origin and translates its local pointer
    /// events back into the explorer WINDOW's coordinates, which is what the
    /// model thinks in — and that translation does not care whether the
    /// panel's box came from a popup window or from a Positioned here.
    private func menuLayerSlot(sub: Bool) -> Widget {
        let host = MenuLayerHost.shared
        guard MenuLayerHost.enabled, let model = host.model,
              let panel = sub ? host.sub : host.main else {
            return Positioned(left: 0, bottom: 0) { SizedBox(width: 0, height: 0) }
        }
        return Positioned(left: panel.x, top: panel.y,
                          width: panel.w, height: panel.h) {
            MenuPanelSurface(model: model, isSub: sub)
        }
    }
}

/// The clock, with its own clock.
///
/// A shell-wide 1 Hz tick used to own this: a bloc event that assigned
/// `state.now` and rebuilt the whole 3840x2160 chrome to move a minute hand.
/// 59 of every 60 of those rebuilds painted the identical string, because the
/// format has no seconds — nobody could have known that but the widget
/// holding the format.
///
/// So the cadence lives here. It wakes on the next BOUNDARY the format cares
/// about rather than on a period, so the minute changes on the minute instead
/// of up to a period late, and it rebuilds this leaf alone. A format that
/// grows seconds gets a one-second cadence with no other change — which is
/// the point of the cadence living beside the format.
final class DockClock: StatefulWidget {
    let format: String
    /// Qualified: `FlutterSwiftBridge` exports a `TextStyle` too, and a type
    /// reference (unlike the call sites' expressions) cannot choose between
    /// them on its own.
    let style: Flutter.TextStyle

    init(key: (any Key)? = nil, format: String, style: Flutter.TextStyle) {
        self.format = format
        self.style = style
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> { DockClockState() }
}

final class DockClockState: State<StatefulWidget> {
    private var now = Date()
    /// Retires a pending wake — the house timer idiom (asyncAfter plus a
    /// generation token; Foundation.Timer does not fire on every embedder).
    private var generation = 0

    override func initState() {
        super.initState()
        _scheduleNextTick()
    }

    override func dispose() {
        generation &+= 1
        super.dispose()
    }

    override func didUpdateWidget(_ oldWidget: StatefulWidget) {
        super.didUpdateWidget(oldWidget)
        if (oldWidget as! DockClock).format != (widget as! DockClock).format {
            _scheduleNextTick()
        }
    }

    private func _scheduleNextTick() {
        generation &+= 1
        let gen = generation
        // Seconds in the pattern mean a one-second cadence; anything else
        // only moves on the minute. (A literal `s` inside quotes would read
        // as seconds here and merely tick faster than it needs to.)
        let period: TimeInterval =
            (widget as! DockClock).format.contains("s") ? 1 : 60
        let t = Date().timeIntervalSince1970
        // Land just AFTER the boundary: a wake a hair before it draws the
        // old minute and then reschedules for ~0 s.
        let delay = period - t.truncatingRemainder(dividingBy: period) + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.setState { self.now = Date() }
            self._scheduleNextTick()
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let clock = widget as! DockClock
        let f = DateFormatter()
        f.dateFormat = clock.format
        return Text(f.string(from: now), style: clock.style)
    }
}

/// The hover flyout as its own rebuild scope — the Hover.swift discipline
/// applied to the dock. Hover is the highest-frequency input the dock gets
/// and the flyout is the ONLY widget that reads it, so the root updates
/// `hovered` as a plain var and pokes this slot; nothing else rebuilds.
/// Constant shape, per the Stack rule in the root's build: always one
/// fill-Positioned holding one inner Stack with one positioned child —
/// contents swap, the child count never does. The inner Stack is also what
/// keeps the moving label's layout scoped: its fill constraints are tight,
/// so repositioning the flyout never re-lays-out the root Stack's strip.
final class DockFlyoutSlot: StatefulWidget {
    unowned let dock: StarlingDockState

    init(dock: StarlingDockState) {
        self.dock = dock
        super.init()
    }

    override func createState() -> State<StatefulWidget> { DockFlyoutSlotState() }
}

final class DockFlyoutSlotState: State<StatefulWidget> {
    /// The root calls this instead of its own setState when only the hover
    /// changed.
    func poke() {
        guard mounted else { return }
        setState {}
    }

    override func initState() {
        super.initState()
        (widget as! DockFlyoutSlot).dock.flyoutSlot = self
    }

    override func build(_ context: any BuildContext) -> Widget {
        let dock = (widget as! DockFlyoutSlot).dock
        return Positioned(fill: (),
                          child: Stack(alignment: Alignment.topLeft) {
                dock.flyoutContent()
            })
    }
}
#endif
