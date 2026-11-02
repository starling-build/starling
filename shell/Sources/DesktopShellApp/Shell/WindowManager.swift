// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge

// MARK: - WindowInfo

/// Model for a single desktop window.
/// A nested native subwindow with its own GPU buffer, composited INSIDE a
/// toplevel window's content area (VLC's reparented video output). Offsets and
/// sizes are physical px in the toplevel's coordinate space; the window widget
/// scales them by the shell DPI.
/// A surface drawn inside a window's content: an X11 subwindow reparented
/// into it (VLC's video output), or a Wayland subsurface (a video, a hover
/// card). The X11 kind is placed in physical pixels, which DesktopWindow
/// scales by the shell DPI at build time; the Wayland kind arrives already
/// in the shell's logical pixels, content-relative, as `logicalRect`.
struct ChildSurface {
    /// The X11 window id, or the Wayland surface id — whichever made it.
    let x11WindowId: UInt32
    let textureId: Int
    var offsetXPhys: Int = 0
    var offsetYPhys: Int = 0
    var widthPhys: Int = 0
    var heightPhys: Int = 0
    var flipY: Bool = true
    var logicalRect: Rect? = nil
    /// Stacking among the window's children (0 = bottom); drawn in order.
    var z: Int = 0
    /// Set for a Wayland subsurface whose input region takes the pointer:
    /// events over it go to the subsurface itself, under its own id, the
    /// way a compositor's hit test would send them — Chrome's "Restore
    /// pages?" bubble is one, and never closed while every click on it
    /// went to the window beneath. Nil for an X11 child (the X server
    /// routes within its own tree) and for a subsurface with an EMPTY
    /// input region (Chrome's video overlays), where the window gets it.
    var onPointerEvent: ((Int32, Double, Double, Int64) -> Void)? = nil
    var onScrollEvent: ((Double, Double, Double, Double) -> Void)? = nil
}

class WindowInfo {
    let id: String
    /// Nested native subwindows composited inside this window's content.
    var childSurfaces: [ChildSurface] = []
    /// The button went down on a child surface that takes input, so the
    /// moves and the release of that press are its too — the window's own
    /// listener, which sees the same events, stays out of them.
    var childSurfaceOwnsPointer = false
    /// The window this one is a dialog for (X11 WM_TRANSIENT_FOR), as a
    /// shell window id. Raising the parent raises it too.
    var transientFor: String? = nil
    var title: String
    var appId: String
    /// What the client called itself: `xdg_toplevel.set_app_id` for a Wayland
    /// window, nil for windows the shell created itself (those carry a real
    /// `appId` already). This is the authoritative link from a window back to
    /// an installed app — it matches the `StartupWMClass` the app's `.desktop`
    /// entry declares, which `app-install` records into the app registry.
    var wmClass: String? = nil
    /// Geometry and WM-state observers. An X11 client is told where the
    /// shell really put its window and what state it is in (a Wayland client
    /// never asks); the X11 path sets these, nothing else needs them.
    var onRectChanged: ((Rect) -> Void)? = nil
    var onStateChanged: (() -> Void)? = nil
    /// An X11 window with a SHAPE bounding region: its texture carries the
    /// shape as alpha, and the renderer draws no backdrop or border under it
    /// so what is behind shows through the cut-away parts.
    var isShaped: Bool = false
    var rect: Rect {
        didSet {
            if oldValue.left != rect.left || oldValue.top != rect.top ||
               oldValue.width != rect.width || oldValue.height != rect.height {
                onRectChanged?(rect)
            }
        }
    }
    var zIndex: Int
    /// The window's place in the 3D desktop, kept beside `rect` and never
    /// derived from it: leaving 3D changes nothing here, re-entering finds
    /// it again. The arc position itself follows `rect` (a flat drag is
    /// the same arrangement seen from the front); this is what only 3D
    /// knows — how far back the window sits.
    var pose3D = WindowPose3D()
    var isMinimized: Bool { didSet { if oldValue != isMinimized { onStateChanged?() } } }
    var isMaximized: Bool { didSet { if oldValue != isMaximized { onStateChanged?() } } }
    var isFullscreen: Bool { didSet { if oldValue != isFullscreen { onStateChanged?() } } }
    var savedRect: Rect?
    /// xdg_toplevel min/max size hints, as content logical pixels (the
    /// frame adds the title bar). nil or 0 = the client set none; resizes
    /// stay inside them.
    var clientMinSize: (width: Double, height: Double)? = nil
    /// A Wayland dialog (xdg_toplevel.set_parent) that has not drawn yet:
    /// its first buffer's size places it centred over its parent.
    var dialogPlacementPending = false
    var clientMaxSize: (width: Double, height: Double)? = nil
    /// wp_alpha_modifier: the client asked for its content at this opacity.
    /// The frame stays opaque; only the content area is drawn through it.
    var contentOpacity: Double = 1.0
    /// ext_background_effect: what is behind these content-local rects is
    /// blurred under the (translucent) content.
    var blurRects: [Rect] = []
    /// The floating rect remembered when tiling first captured this window;
    /// restored when the user switches back to the floating layout.
    var preTileRect: Rect? = nil
    var appBuilder: (any BuildContext) -> Widget
    var textureId: Int?
    var onWindowClose: (() -> Void)?
    /// Callback to forward pointer events to a child process.
    /// Parameters: (phase, x, y, buttons)
    var onPointerEvent: ((Int32, Double, Double, Int64) -> Void)?
    /// Callback to notify child process of content area resize.
    /// Parameters: (contentWidth, contentHeight)
    var onContentResize: ((Double, Double) -> Void)?
    /// Callback to forward scroll events to a child process.
    /// Parameters: (x, y, scrollDeltaX, scrollDeltaY)
    var onScrollEvent: ((Double, Double, Double, Double) -> Void)?
    /// When true, the texture content is vertically flipped during compositing.
    /// Used for Wayland client DMA-BUF surfaces which have top-left origin.
    var flipTextureY: Bool
    /// During resize drag, holds the target rect (where the user dragged to).
    /// The visual `rect` stays frozen at Chrome's last rendered size.
    /// nil when no drag is active (rect is authoritative).
    var targetRect: Rect? = nil
    /// Client-initiated interactive move/resize (xdg_toplevel.move/resize —
    /// CSD titlebar or Chrome tab-strip drag). While active, the content-area
    /// Listener diverts pointer motion into window move/resize instead of
    /// forwarding it to the client; cleared on pointer-up.
    var interactiveMoveActive: Bool = false
    var interactiveResizeEdge: ResizeEdge? = nil
    var interactiveLastPos: Offset? = nil
    /// Which edge/corner is being dragged. Used to anchor the correct edges
    /// when Chrome's rendered size updates the visual rect.
    var resizeDragEdge: ResizeEdge? = nil
    /// Called on drag end to force-send the final ConfigureNotify.
    var onResizeComplete: ((Double, Double) -> Void)? = nil
    /// Geometry offset: where actual content starts within the buffer (surface-local coords).
    /// Used to crop CSD shadow from Wayland client textures.
    var geometryOffset: (x: Double, y: Double)? = nil
    /// Geometry content dimensions (surface-local coords).
    var geometrySize: (width: Double, height: Double)? = nil
    /// Full buffer logical size (before geometry crop). Used to size the texture at native resolution.
    var bufferLogicalSize: (width: Double, height: Double)? = nil
    /// The space (virtual desktop) this window lives on. Assigned by
    /// WindowManagerState.addWindow; only windows of the active space render.
    var spaceId: Int = 1
    /// While fullscreen: the space the window came from, so exiting
    /// fullscreen returns it home (macOS behaviour).
    var fullscreenOriginSpaceId: Int? = nil
    /// One-shot latch: play the open zoom the next time this window's
    /// element mounts. True for new windows and on restore-from-minimize;
    /// consumed by the shell's build so that a mount caused by a space
    /// switch does NOT replay the zoom.
    var pendingOpenAnimation: Bool = true
    /// Owner of a window that is not the desktop's: a workspace id, or a
    /// broker client's id. Set at launch time, never inferred afterwards.
    /// Owned windows have NO desktop presence — they live outside every space
    /// and are excluded from visibleWindows, the dock, Ctrl+Tab and Mission
    /// Control. A workspace draws its own in its panes; a broker client's are
    /// drawn nowhere at all and exist to be driven through the semantics
    /// endpoint (see AgentWindows.swift).
    var ownerAgentId: String? = nil
    /// The child app's semantics endpoint socket (Murmuration P3), when the
    /// launcher configured one — the broker proxies semantic_tree /
    /// perform_action to it.
    var agentEndpointPath: String? = nil

    init(
        id: String,
        title: String,
        appId: String,
        rect: Rect,
        zIndex: Int = 0,
        isMinimized: Bool = false,
        isMaximized: Bool = false,
        isFullscreen: Bool = false,
        savedRect: Rect? = nil,
        textureId: Int? = nil,
        onWindowClose: (() -> Void)? = nil,
        onPointerEvent: ((Int32, Double, Double, Int64) -> Void)? = nil,
        onContentResize: ((Double, Double) -> Void)? = nil,
        onResizeComplete: ((Double, Double) -> Void)? = nil,
        onScrollEvent: ((Double, Double, Double, Double) -> Void)? = nil,
        flipTextureY: Bool = false,
        appBuilder: @escaping (any BuildContext) -> Widget
    ) {
        self.id = id
        self.title = title
        self.appId = appId
        self.rect = rect
        self.zIndex = zIndex
        self.isMinimized = isMinimized
        self.isMaximized = isMaximized
        self.isFullscreen = isFullscreen
        self.savedRect = savedRect
        self.textureId = textureId
        self.onWindowClose = onWindowClose
        self.onPointerEvent = onPointerEvent
        self.onScrollEvent = onScrollEvent
        self.onContentResize = onContentResize
        self.onResizeComplete = onResizeComplete
        self.flipTextureY = flipTextureY
        self.appBuilder = appBuilder
    }
}

// MARK: - ResizeEdge

/// Which edge/corner is being dragged for a resize operation.
enum ResizeEdge {
    case top, bottom, left, right
    case topLeft, topRight, bottomLeft, bottomRight
}

// MARK: - Spaces

/// What a space is for. User spaces are the ordinary desktops the user
/// creates and removes; a fullscreen space is the transient space a window
/// gets when it goes fullscreen (macOS model) — it lives exactly as long as
/// the window stays fullscreen. A workspace is a persistent special space
/// holding a driver app and what it opens: excluded from Ctrl+arrow/Tab
/// cycling and entered only by its own affordance.
enum SpaceKind: Equatable {
    case user
    case fullscreen(windowId: String)
    /// Workspace mode: a driver app with whatever it opens beside it. Like
    /// the agent space it is persistent, pinned past the user spaces, and
    /// excluded from cycling — but it has nothing to do with agents, and the
    /// two are independent.
    case workspace
}

/// One virtual desktop (macOS "Space"). Windows reference it by `id`;
/// ordering lives in WindowManagerState.spaces.
final class SpaceInfo {
    let id: Int
    var kind: SpaceKind

    init(id: Int, kind: SpaceKind = .user) {
        self.id = id
        self.kind = kind
    }

    var isUser: Bool {
        if case .user = kind { return true }
        return false
    }

    var isWorkspace: Bool { kind == .workspace }

    /// A space the user never lands on by cycling: it is entered only by its
    /// own affordance and is pinned after the user spaces.
    var isSpecial: Bool { isWorkspace }
}

/// One workspace: a driver app, and the windows opened beside it.
///
/// The driver is a window, not an app id, because it is whatever is running in
/// the middle column right now — and it can be absent. When the driver quits
/// the workspace survives with its other windows intact and the middle column
/// returns to its empty state, so this is deliberately nil-able rather than
/// something the workspace is constructed around.
final class WorkspaceInfo {
    let id: String
    var name: String
    var driverWindowId: String? = nil

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - Agents (Murmuration)

/// One registered agent session: identity plus the terminal window hosting
/// its process (Claude Code in the devbox via TerminalApp). The windows an
/// agent owns are discovered through WindowInfo.ownerAgentId; the terminal
/// is tracked explicitly because the tile lays it out specially.
final class AgentInfo {
    let id: String
    var name: String
    /// The window id of the agent's TerminalApp window, once its first
    /// frame arrived. The tile's terminal pane composites this window.
    var terminalWindowId: String? = nil
    /// True for agents registered over the broker socket (external clients:
    /// MCP servers, CI harnesses, agent-client.py). They have no terminal
    /// unless they launch one.
    var isExternal: Bool = false

    /// Secret handed out at registration, required to re-attach to this agent
    /// on a later connection. Window ownership is per-agent, so a client that
    /// runs as a series of short-lived processes — a CLI invoked once per
    /// command, which is how an agent harness drives one — would otherwise get
    /// a fresh identity every time and be unable to touch the window it
    /// launched a moment earlier.
    ///
    /// This is NOT a defence against a hostile process on the same machine:
    /// the broker already accepts any client with the session's uid, and that
    /// same process can read the client's state file. It exists so that ids
    /// (`agent-1`, `agent-2`) cannot be re-attached by *guessing* them, which
    /// two unrelated agents starting at the same time would otherwise do.
    let token: String = AgentInfo.newToken()

    private static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - WindowManagerState

/// Pure model managing the list of windows, z-order, and focus.
/// All mutations should be called from the shell's setState block.
class WindowManagerState {
    var windows: [WindowInfo] = []
    /// Fired when keyboard focus moves between windows (nil = none). The X11
    /// path uses it to keep the X server's focus, _NET_ACTIVE_WINDOW and
    /// _NET_WM_STATE_FOCUSED in step with the shell's.
    var onFocusChanged: ((String?) -> Void)? = nil
    var focusedWindowId: String? = nil {
        didSet { if oldValue != focusedWindowId { onFocusChanged?(focusedWindowId) } }
    }
    private var nextZIndex: Int = 1
    private var nextWindowId: Int = 1

    /// Ordered spaces (virtual desktops), left to right. Always contains at
    /// least one user space; index 0 exists from startup so every legacy
    /// single-desktop path behaves identically at N=1. Invariant: the agent
    /// workspace space, once created, is always LAST — cycling and space
    /// creation clamp around it.
    private(set) var spaces: [SpaceInfo] = [SpaceInfo(id: 1)]
    private(set) var activeSpaceIndex: Int = 0

    // ── Per-output active space ─────────────────────────────────────────
    // macOS's "Displays have separate Spaces", ON. The space SET is shared
    // (one strip, global numbering); which member is active is per-output.
    // `activeSpaceIndex` remains the HOST output's active space — the shell
    // tree renders the host, and at N=1 the host is the whole desktop, so
    // every existing caller keeps its exact meaning. Other outputs live in
    // this map, BY SPACE ID (indexes shift on insert/remove; ids don't).
    //
    // An ABSENT entry means "follow the host" — the old global behavior.
    // An output decouples the first time a space is switched ON it, which
    // is what makes this stageable: nothing changes until the user asks
    // for it, per monitor.
    private var activeSpaceIdByOutput: [Int: Int] = [:]

    private var hostOutputId: Int { displayLayout?.host.id ?? 0 }

    /// The active space id on `outputId` — the host's unless this output
    /// has decoupled (and its chosen space still exists).
    func activeSpaceId(onOutput outputId: Int) -> Int {
        if outputId != hostOutputId,
           let id = activeSpaceIdByOutput[outputId],
           spaces.contains(where: { $0.id == id }) {
            return id
        }
        return activeSpace.id
    }

    func activeSpace(onOutput outputId: Int) -> SpaceInfo {
        let id = activeSpaceId(onOutput: outputId)
        return spaces.first(where: { $0.id == id }) ?? activeSpace
    }

    /// Switch the active space on ONE output. The host goes through
    /// `activeSpaceIndex` (and drops any stale map entry); a secondary
    /// decouples into the map. Focus follows the output that changed —
    /// macOS's answer to "whose topmost wins".
    func switchToSpace(_ index: Int, onOutput outputId: Int) {
        guard spaces.indices.contains(index),
              spaces[index].id != activeSpaceId(onOutput: outputId) else { return }
        if outputId == hostOutputId {
            // Un-decoupled outputs follow the host — but never into a
            // SPECIAL space. Entering a workspace on the host pins them to
            // the space they were showing, so the other monitors keep
            // their desktops (found the hard way: an un-decoupled second
            // monitor followed the host's workspace, and the next toggle
            // there read "already in a workspace" and exited instead of
            // entering).
            if spaces[index].isSpecial, let dl = displayLayout {
                let current = activeSpace.id
                for o in dl.outputs
                where o.id != outputId && activeSpaceIdByOutput[o.id] == nil {
                    activeSpaceIdByOutput[o.id] = current
                }
            }
            activeSpaceIndex = index
            activeSpaceIdByOutput.removeValue(forKey: outputId)
        } else {
            activeSpaceIdByOutput[outputId] = spaces[index].id
        }
        focusTopmost(onOutput: outputId)
        onWindowsChanged?()
    }

    /// Focus the topmost visible window ON `outputId` (or clear focus if
    /// its active space is empty there).
    func focusTopmost(onOutput outputId: Int) {
        guard let dl = displayLayout, dl.outputs.count > 1 else {
            focusTopmostInActiveSpace()
            return
        }
        focusedWindowId = visibleWindows
            .last(where: { dl.owningOutput(ofRect: $0.rect).id == outputId })?
            .id
    }

    /// The host output changed identity (Settings made another monitor
    /// primary and the engine rebound the shell's view). Each PANEL keeps
    /// showing the space it was showing: the old host's space moves into
    /// the map under its output id, and the new host's entry (if it had
    /// decoupled) is consumed into `activeSpaceIndex`.
    func hostChanged(from oldOutputId: Int, to newOutputId: Int) {
        let oldActiveId = activeSpace.id
        if let adopted = activeSpaceIdByOutput.removeValue(forKey: newOutputId),
           let idx = spaces.firstIndex(where: { $0.id == adopted }) {
            activeSpaceIndex = idx
        }
        activeSpaceIdByOutput[oldOutputId] = oldActiveId
    }
    private var nextSpaceId: Int = 2

    /// Registered agents (Murmuration), in creation order.
    var agents: [AgentInfo] = []

    /// Workspaces, in creation order — the rows of the workspace rail.
    var workspaces: [WorkspaceInfo] = []
    /// Per-output rail selection (workspace per output): each monitor in
    /// workspace mode shows its own workspace. A workspace displayed on one
    /// output is not offered as another's default, and selecting it on a
    /// second output STEALS it (the first falls back) — a client has one
    /// buffer size, so one workspace cannot render on two panels.
    var selectedWorkspaceIdByOutput: [Int: String] = [:]
    private var nextWorkspaceNumber: Int = 1

    /// Workspace ids currently ON SCREEN somewhere else — an output that
    /// exited workspace mode keeps its selection, but that workspace is not
    /// displayed and stays fair game.
    func displayedWorkspaceIds(excluding outputId: Int) -> Set<String> {
        var ids = Set<String>()
        for (out, wid) in selectedWorkspaceIdByOutput
        where out != outputId && activeSpace(onOutput: out).isWorkspace {
            ids.insert(wid)
        }
        return ids
    }

    func selectedWorkspace(onOutput outputId: Int) -> WorkspaceInfo? {
        if let wid = selectedWorkspaceIdByOutput[outputId],
           let ws = workspaces.first(where: { $0.id == wid }) {
            return ws
        }
        // Default: the first workspace no other monitor is displaying. NIL
        // when they are all on screen elsewhere — never the taken one; a
        // client has one buffer size, so one workspace on two panels is the
        // thing this whole model exists to prevent.
        let taken = displayedWorkspaceIds(excluding: outputId)
        return workspaces.first(where: { !taken.contains($0.id) })
    }

    func selectWorkspace(_ workspaceId: String, onOutput outputId: Int) {
        for (out, wid) in selectedWorkspaceIdByOutput
        where wid == workspaceId && out != outputId {
            selectedWorkspaceIdByOutput.removeValue(forKey: out)
        }
        selectedWorkspaceIdByOutput[outputId] = workspaceId
    }

    /// Host-scoped compatibility: callers off the workspace-UI path (launch
    /// bookkeeping) read the HOST's selection, which at N=1 is the only one.
    var selectedWorkspace: WorkspaceInfo? {
        selectedWorkspace(onOutput: hostOutputId)
    }

    @discardableResult
    func addWorkspace(onOutput outputId: Int? = nil) -> WorkspaceInfo {
        let ws = WorkspaceInfo(id: "ws-\(nextWorkspaceNumber)",
                               name: "Workspace \(nextWorkspaceNumber)")
        nextWorkspaceNumber += 1
        workspaces.append(ws)
        selectWorkspace(ws.id, onOutput: outputId ?? hostOutputId)
        return ws
    }

    /// Drop a workspace from the rail and hand back the outputs that were
    /// showing it, so the caller can re-point them.
    ///
    /// Deliberately does NOT touch the workspace's windows: destroying user
    /// windows on a rail click is the kind of thing discovered the hard way,
    /// so the caller rehomes them to the desktop first. Removing the last
    /// workspace is refused — the space would have nothing to show.
    @discardableResult
    func removeWorkspace(_ workspaceId: String) -> [Int] {
        guard workspaces.count > 1,
              let idx = workspaces.firstIndex(where: { $0.id == workspaceId })
        else { return [] }
        workspaces.remove(at: idx)
        let orphaned = selectedWorkspaceIdByOutput
            .filter { $0.value == workspaceId }.map { $0.key }
        // Dropping the mapping is the whole re-point: with no entry,
        // `selectedWorkspace(onOutput:)` already falls back to the first
        // workspace no other monitor is showing, which is exactly the rule
        // that keeps two panels off one workspace.
        for out in orphaned { selectedWorkspaceIdByOutput.removeValue(forKey: out) }
        return orphaned
    }

    /// Windows belonging to a workspace, newest last.
    ///
    /// Ownership rides on `WindowInfo.ownerAgentId`, which is not the misnomer
    /// it looks like: the field is an opaque owner id, and every desktop query
    /// already filters on "has an owner" rather than on what the owner is. So a
    /// workspace window is hidden from the dock, tiling, Mission Control and
    /// focus with no new filter sites — and renaming the field is left for
    /// whenever the agent space itself is revisited.
    func windows(inWorkspace workspaceId: String) -> [WindowInfo] {
        windows.filter { $0.ownerAgentId == workspaceId }
    }

    var activeSpace: SpaceInfo { spaces[activeSpaceIndex] }

    func spaceIndex(ofSpaceId id: Int) -> Int? {
        spaces.firstIndex { $0.id == id }
    }

    /// The sentinel spaceId of agent-owned windows: they belong to no space.
    static let kNoSpaceId = -1

    /// Index of the workspace space, if it has been created.
    var workspaceSpaceIndex: Int? {
        spaces.indices.last(where: { spaces[$0].isWorkspace })
    }

    /// Where user spaces stop and the special ones begin. New user spaces
    /// append here so the special spaces stay past the end of the strip.
    var firstSpecialIndex: Int {
        spaces.firstIndex(where: { $0.isSpecial }) ?? spaces.count
    }

    /// Create the workspace space on first use and return its index — the
    /// lazily, and never removed once it exists.
    @discardableResult
    func ensureWorkspaceSpace() -> Int {
        if let idx = workspaceSpaceIndex { return idx }
        let space = SpaceInfo(id: nextSpaceId, kind: .workspace)
        nextSpaceId += 1
        spaces.append(space)
        return spaces.count - 1
    }

    /// All windows owned by `agentId` (creation order — window ids ascend).
    func windows(ownedBy agentId: String) -> [WindowInfo] {
        windows.filter { $0.ownerAgentId == agentId }
    }

    // MARK: - Space Lifecycle

    /// Insert a new user space at `index` (append when nil) and return its
    /// index. The active space does not change. Appends land BEFORE the
    /// agent space, which stays last.
    @discardableResult
    func addSpace(at index: Int? = nil) -> Int {
        let space = SpaceInfo(id: nextSpaceId)
        nextSpaceId += 1
        let appendAt = firstSpecialIndex
        let insertAt = min(max(index ?? appendAt, 0), appendAt)
        spaces.insert(space, at: insertAt)
        if insertAt <= activeSpaceIndex { activeSpaceIndex += 1 }
        return insertAt
    }

    /// Remove the space at `index`. Its windows migrate to the nearest
    /// surviving neighbour (macOS: deleting a desktop rehomes its windows).
    /// The last user space can never be removed; the agent space never is.
    func removeSpace(at index: Int) {
        guard spaces.indices.contains(index), spaces.count > 1 else { return }
        guard !spaces[index].isSpecial else { return }
        guard !(spaces[index].isUser && spaces.filter({ $0.isUser }).count == 1) else { return }
        let removedId = spaces[index].id
        // Stranded windows migrate to the nearest USER space (never into a
        // window's private fullscreen space).
        let fallbackIndex = spaces.indices
            .filter { $0 != index && spaces[$0].isUser }
            .min { abs($0 - index) < abs($1 - index) }
            ?? (index > 0 ? index - 1 : 1)
        let fallbackId = spaces[fallbackIndex].id
        for w in windows where w.spaceId == removedId { w.spaceId = fallbackId }
        // Outputs that were showing the removed space fall back with their
        // windows (stored by id, so the index shuffle below is irrelevant).
        for (out, id) in activeSpaceIdByOutput where id == removedId {
            activeSpaceIdByOutput[out] = fallbackId
        }
        let wasActive = index == activeSpaceIndex
        spaces.remove(at: index)
        if index < activeSpaceIndex {
            activeSpaceIndex -= 1
        } else if activeSpaceIndex >= spaces.count {
            activeSpaceIndex = spaces.count - 1
        }
        if wasActive { focusTopmostInActiveSpace() }
        onWindowsChanged?()
    }

    /// Make `index` the HOST's active space and focus its topmost window.
    /// Delegates to the per-output form — bypassing it once silently skipped
    /// the pin-on-special step, and un-decoupled monitors followed the host
    /// into a workspace again.
    func switchToSpace(_ index: Int) {
        switchToSpace(index, onOutput: hostOutputId)
    }

    /// Reassign a window to the space at `index` (no focus change).
    func moveWindow(_ id: String, toSpaceIndex index: Int) {
        guard spaces.indices.contains(index),
              let win = windows.first(where: { $0.id == id }) else { return }
        win.spaceId = spaces[index].id
        onWindowsChanged?()
    }

    func focusTopmostInActiveSpace() {
        focusedWindowId = windows
            .filter { !$0.isMinimized && $0.spaceId == activeSpace.id && $0.ownerAgentId == nil }
            .sorted { $0.zIndex < $1.zIndex }
            .last?.id
    }

    /// Drop the transient fullscreen space owned by `windowId`, if any.
    /// Safe to call when none exists.
    private func removeFullscreenSpace(ownedBy windowId: String) {
        if let idx = spaces.firstIndex(where: { $0.kind == .fullscreen(windowId: windowId) }) {
            removeSpace(at: idx)
        }
    }

    /// Rehome `win` out of its transient fullscreen space (green-button
    /// restore, or an edge-drag demoting the fullscreen state) and drop that
    /// space. The active space follows to wherever the window lands. No-op
    /// for windows that never got a fullscreen space.
    private func exitFullscreenSpace(_ win: WindowInfo) {
        guard win.fullscreenOriginSpaceId != nil
            || spaces.contains(where: { $0.kind == .fullscreen(windowId: win.id) })
        else { return }
        let homeId = win.fullscreenOriginSpaceId
        win.fullscreenOriginSpaceId = nil
        removeFullscreenSpace(ownedBy: win.id)
        let homeIndex = homeId.flatMap { spaceIndex(ofSpaceId: $0) }
            ?? spaces.indices.first(where: { spaces[$0].isUser }) ?? 0
        win.spaceId = spaces[homeIndex].id
        // Home is a per-output notion now: only the window's own monitor
        // follows it back.
        let owner = displayLayout.map { $0.owningOutput(ofRect: win.rect).id }
            ?? hostOutputId
        switchToSpace(homeIndex, onOutput: owner)
    }

    /// The set of app IDs that currently have open (non-minimized) windows.
    /// Agent-owned windows don't light dock indicators.
    var runningAppIds: Set<String> {
        var ids = Set<String>()
        for w in windows where w.ownerAgentId == nil {
            ids.insert(w.appId)
            // Map Wayland/X11 window titles to dock app IDs
            let t = w.title.lowercased()
            if t.contains("chrome") || t.contains("chromium") {
                ids.insert("chrome")
            }
        }
        return ids
    }

    // MARK: - Window Lifecycle

    @discardableResult
    func addWindow(
        title: String,
        appId: String,
        rect: Rect? = nil,
        textureId: Int? = nil,
        onWindowClose: (() -> Void)? = nil,
        onPointerEvent: ((Int32, Double, Double, Int64) -> Void)? = nil,
        onContentResize: ((Double, Double) -> Void)? = nil,
        onResizeComplete: ((Double, Double) -> Void)? = nil,
        onScrollEvent: ((Double, Double, Double, Double) -> Void)? = nil,
        flipTextureY: Bool = false,
        ownerAgentId: String? = nil,
        appBuilder: @escaping (any BuildContext) -> Widget
    ) -> String {
        let id = "window-\(nextWindowId)"
        nextWindowId += 1

        // Offset each new window slightly so they don't stack exactly. New
        // windows open on the primary output (macOS model), relative to its
        // logical origin — at N=1 that origin is (0,0), so this is unchanged.
        let offset = Double(windows.count % 5) * 30.0
        let originX = (displayLayout?.primary.originX ?? 0) + 100 + offset
        let originY = (displayLayout?.primary.originY ?? 0) + 60 + offset
        let defaultRect = rect ?? Rect.fromLTWH(
            originX, originY,
            DesktopTheme.kDefaultWindowWidth,
            DesktopTheme.kDefaultWindowHeight
        )

        let info = WindowInfo(
            id: id,
            title: title,
            appId: appId,
            rect: defaultRect,
            zIndex: nextZIndex,
            textureId: textureId,
            onWindowClose: onWindowClose,
            onPointerEvent: onPointerEvent,
            onContentResize: onContentResize,
            onResizeComplete: onResizeComplete,
            onScrollEvent: onScrollEvent,
            flipTextureY: flipTextureY,
            appBuilder: appBuilder
        )
        nextZIndex += 1
        // Agent-owned windows are not placed in any space and never steal
        // focus or move the active desktop — they exist only as textures
        // inside their owner's tile.
        if let agentId = ownerAgentId {
            info.ownerAgentId = agentId
            info.spaceId = Self.kNoSpaceId
            info.pendingOpenAnimation = false
            windows.append(info)
            return id
        }
        // A new window joins the active space of the output it OPENS on —
        // with per-output spaces "the" active space is a question of where.
        let openOutput = displayLayout.map { $0.owningOutput(ofRect: info.rect).id }
            ?? hostOutputId
        // New windows never open inside another window's fullscreen space
        // (macOS): land on the nearest user desktop and take that output
        // there.
        if !activeSpace(onOutput: openOutput).isUser {
            let current = spaceIndex(ofSpaceId: activeSpaceId(onOutput: openOutput))
                ?? activeSpaceIndex
            let idx = spaces.indices
                .filter { spaces[$0].isUser }
                .min { abs($0 - current) < abs($1 - current) } ?? 0
            switchToSpace(idx, onOutput: openOutput)
        }
        info.spaceId = activeSpaceId(onOutput: openOutput)
        windows.append(info)
        focusedWindowId = id
        onWindowsChanged?()
        return id
    }

    func closeWindow(_ id: String) {
        if let win = windows.first(where: { $0.id == id }) {
            win.onWindowClose?()
        }
        windows.removeAll { $0.id == id }
        // A fullscreen window's private space dies with it (macOS). If it was
        // the active space, removeSpace lands us on the fallback neighbour.
        removeFullscreenSpace(ownedBy: id)
        if focusedWindowId == id {
            focusTopmostInActiveSpace()
        }
        onWindowsChanged?()
    }

    // MARK: - Focus & Z-Order

    func bringToFront(_ id: String) {
        guard let win = windows.first(where: { $0.id == id }) else { return }
        win.zIndex = nextZIndex
        nextZIndex += 1
        focusedWindowId = id
        // A dialog stays above the window it belongs to: raising the parent
        // raises its dialogs after it, so a modal prompt is never buried
        // under the very window it is blocking.
        for child in windows where child.transientFor == id && child.id != id {
            child.zIndex = nextZIndex
            nextZIndex += 1
        }
    }

    // MARK: - Move & Resize

    func moveWindow(_ id: String, to position: Offset) {
        guard let win = windows.first(where: { $0.id == id }) else { return }
        let w = win.rect.width
        let h = win.rect.height
        win.rect = Rect.fromLTWH(position.dx, position.dy, w, h)
    }

    func moveWindowByDelta(_ id: String, delta: Offset) {
        guard let win = windows.first(where: { $0.id == id }) else { return }
        win.rect = Rect.fromLTWH(
            win.rect.left + delta.dx,
            win.rect.top + delta.dy,
            win.rect.width,
            win.rect.height
        )
        // Crossing a seam moves the window to the destination output's
        // active space (macOS: a dragged window joins the space of the
        // display it lands on). Continuous rather than on-drop, so the
        // window stays visible for the whole drag — its space always
        // matches the panel under it. USER spaces only, both ways: a drag
        // must never yank a window into a workspace or out of a fullscreen
        // space's private world.
        if let dl = displayLayout, dl.outputs.count > 1, win.ownerAgentId == nil {
            let target = activeSpaceId(onOutput: dl.owningOutput(ofRect: win.rect).id)
            if win.spaceId != target,
               spaces.first(where: { $0.id == win.spaceId })?.isUser == true,
               spaces.first(where: { $0.id == target })?.isUser == true {
                win.spaceId = target
            }
        }
    }

    func resizeWindow(_ id: String, edge: ResizeEdge, delta: Offset) {
        guard let win = windows.first(where: { $0.id == id }) else { return }

        // Dragging an edge demotes a maximized/fullscreen window to a free
        // window — once the user starts resizing, the special states no
        // longer apply (matches macOS / GNOME behaviour). A demoted
        // fullscreen window also gives up its private space.
        if win.isFullscreen {
            exitFullscreenSpace(win)
        }
        if win.isFullscreen || win.isMaximized {
            win.isFullscreen = false
            win.isMaximized = false
        }

        // Use targetRect for delta accumulation (tracks mouse), not rect (frozen visual)
        let base = win.targetRect ?? win.rect
        var l = base.left
        var t = base.top
        var r = base.right
        var b = base.bottom

        switch edge {
        case .left:
            l += delta.dx
        case .right:
            r += delta.dx
        case .top:
            t += delta.dy
        case .bottom:
            b += delta.dy
        case .topLeft:
            l += delta.dx; t += delta.dy
        case .topRight:
            r += delta.dx; t += delta.dy
        case .bottomLeft:
            l += delta.dx; b += delta.dy
        case .bottomRight:
            r += delta.dx; b += delta.dy
        }

        // Enforce the size limits: the shell's floor, raised to the
        // client's xdg_toplevel min size (content, so plus the title bar),
        // and the client's max size as the ceiling. The edge being dragged
        // is the one that gives.
        let leftEdge = edge == .left || edge == .topLeft || edge == .bottomLeft
        let topEdge = edge == .top || edge == .topLeft || edge == .topRight
        let minW = max(DesktopTheme.kMinWindowWidth, win.clientMinSize?.width ?? 0)
        let minH = max(DesktopTheme.kMinWindowHeight,
                       (win.clientMinSize?.height ?? 0) + DesktopTheme.kTitleBarHeight)
        if r - l < minW {
            if leftEdge { l = r - minW } else { r = l + minW }
        }
        if b - t < minH {
            if topEdge { t = b - minH } else { b = t + minH }
        }
        if let mx = win.clientMaxSize {
            let maxW = mx.width > 0 ? max(mx.width, minW) : 0
            let maxH = mx.height > 0 ? max(mx.height + DesktopTheme.kTitleBarHeight, minH) : 0
            if maxW > 0, r - l > maxW {
                if leftEdge { l = r - maxW } else { r = l + maxW }
            }
            if maxH > 0, b - t > maxH {
                if topEdge { t = b - maxH } else { b = t + maxH }
            }
        }

        // Option A (xfwm4-style): update rect immediately so the window frame
        // follows the mouse. Chrome content lags behind but catches up.
        let newRect = Rect.fromLTRB(l, t, r, b)
        win.rect = newRect
        win.targetRect = newRect
        win.resizeDragEdge = edge

        // Notify client (X11/Wayland) of new content size
        let contentW = newRect.width
        let contentH = newRect.height - DesktopTheme.kTitleBarHeight
        if contentW > 0 && contentH > 0 {
            win.onContentResize?(contentW, contentH)
        }
    }

    // MARK: - Minimize / Maximize

    func minimizeWindow(_ id: String) {
        guard let win = windows.first(where: { $0.id == id }) else { return }
        win.isMinimized = true
        if focusedWindowId == id {
            focusTopmostInActiveSpace()
        }
        onWindowsChanged?()
    }

    /// Strips reserved by layer-shell surfaces with an exclusive zone (a
    /// bar along an edge, in logical pixels) on the host output. Cut from
    /// the work area on top of the shell's own bars, so a maximized window
    /// stops at a third-party panel exactly as it stops at the dock.
    var layerInsets: (top: Double, bottom: Double, left: Double, right: Double) = (0, 0, 0, 0)

    /// The area a window on `ref`'s output may fill: the output less the
    /// shell's reserved strips and any layer-shell exclusive zones. What
    /// maximize fills, and what an xx-zones zone measures from.
    func workArea(for ref: Rect, screenWidth: Double, screenHeight: Double) -> Rect {
        _outputFillRect(for: ref, screenWidth: screenWidth, screenHeight: screenHeight)
    }

    /// The whole logical rect of the output that owns `ref`: what fullscreen
    /// fills.
    private func _outputFullRect(for ref: Rect, screenWidth: Double, screenHeight: Double) -> Rect {
        if let dl = displayLayout {
            return dl.owningOutput(ofRect: ref).logicalRect
        }
        return Rect.fromLTWH(0, 0, screenWidth, screenHeight)
    }

    /// The maximise/fullscreen fill rect for the output that OWNS `ref` (its
    /// logical rect minus the menu-bar strip). Falls back to the passed screen
    /// size when no display layout exists (non-DRM dev paths). At N=1 the owning
    /// output is the whole primary, so this equals (0, topInset, W, H-topInset).
    private func _outputFillRect(for ref: Rect, screenWidth: Double, screenHeight: Double) -> Rect {
        let topInset = DesktopTheme.kStatusBarHeight
        // And the BOTTOM, in a style whose bar reserves its strip. The macOS
        // dock is an overlay windows pass beneath -- which is what gives its
        // blur something to blur -- so it reserves nothing and this is 0.
        // A Windows taskbar does reserve, and a maximised window that ignored
        // it ran its last 56pt underneath the bar.
        let bottomInset = shellMetrics.bottomInset
        let inset = topInset + bottomInset
        var rect: Rect
        var onHost = true
        if let dl = displayLayout {
            let o = dl.owningOutput(ofRect: ref)
            onHost = o.isHost
            rect = Rect.fromLTWH(o.logicalLeft, o.logicalTop + topInset,
                                 o.logicalWidth, o.logicalHeight - inset)
        } else {
            rect = Rect.fromLTWH(0, topInset, screenWidth, screenHeight - inset)
        }
        // Layer surfaces are drawn on the host output only (see
        // LayerSurfaces.swift), so only its work area feels them.
        if onHost {
            let li = layerInsets
            let cut = Rect.fromLTRB(rect.left + li.left, rect.top + li.top,
                                    rect.right - li.right, rect.bottom - li.bottom)
            // A panel that eats the whole screen is a broken panel; the
            // window keeps the output rather than vanishing.
            if cut.width >= DesktopTheme.kMinWindowWidth &&
               cut.height >= DesktopTheme.kMinWindowHeight {
                rect = cut
            }
        }
        return rect
    }

    func maximizeWindow(_ id: String, screenWidth: Double, screenHeight: Double) {
        guard let win = windows.first(where: { $0.id == id }) else { return }
        if win.isMaximized {
            // Restore
            if let saved = win.savedRect {
                win.rect = saved
            }
            win.isMaximized = false
            win.savedRect = nil
        } else {
            // Maximize: fill the owning output below its menu bar. The dock is a
            // floating overlay (macOS-style), so windows extend underneath
            // it — that's what makes the dock's BackdropFilter blur the
            // window's content rather than blurring the wallpaper.
            win.savedRect = win.rect
            win.rect = _outputFillRect(for: win.rect, screenWidth: screenWidth, screenHeight: screenHeight)
            win.isMaximized = true
            win.isFullscreen = false
        }
    }

    func fullscreenWindow(_ id: String, screenWidth: Double, screenHeight: Double) {
        guard let win = windows.first(where: { $0.id == id }) else { return }
        if win.isFullscreen {
            // Restore to the pre-fullscreen rect (size + position the user
            // had before clicking the green button).
            if let saved = win.savedRect {
                win.rect = saved
            }
            win.isFullscreen = false
            win.isMaximized = false
            win.savedRect = nil
            // Return the window to the space it came from and drop its
            // private fullscreen space (macOS). Home space may itself have
            // been removed meanwhile — fall back to the nearest user space.
            exitFullscreenSpace(win)
            bringToFront(id)
        } else {
            // Fullscreen covers the WHOLE output, status-bar strip included
            // — what xdg-shell's set_fullscreen promises and what a video or
            // a game expects; the bar and the window's own title bar auto-hide
            // and overlay the content when revealed (handled in DesktopWindow
            // and the edge sensors). It used to stop 28 px short and leave a
            // black strip, which every fullscreen pixel check reads as a
            // window that never covered the screen.
            win.savedRect = win.rect
            win.rect = _outputFullRect(for: win.rect, screenWidth: screenWidth, screenHeight: screenHeight)
            win.isFullscreen = true
            win.isMaximized = false
            // The window gets its own transient space immediately to the
            // right of the one it lives on, and we land there (macOS).
            win.fullscreenOriginSpaceId = win.spaceId
            let currentIndex = spaceIndex(ofSpaceId: win.spaceId) ?? activeSpaceIndex
            let space = SpaceInfo(id: nextSpaceId, kind: .fullscreen(windowId: id))
            nextSpaceId += 1
            spaces.insert(space, at: currentIndex + 1)
            // The raw insert bypasses insertSpace's index bookkeeping — keep
            // the host pointing at ITS space before anything switches.
            if currentIndex + 1 <= activeSpaceIndex { activeSpaceIndex += 1 }
            win.spaceId = space.id
            // Only the window's OWN monitor lands in the private space —
            // fullscreening a window on the second screen must not blank
            // the first (its geometry was already per-output; its space
            // dance was not).
            let owner = displayLayout.map { $0.owningOutput(ofRect: win.rect).id }
                ?? hostOutputId
            switchToSpace(currentIndex + 1, onOutput: owner)
            focusedWindowId = id
        }
    }

    func restoreWindow(_ id: String) {
        guard let win = windows.first(where: { $0.id == id }) else { return }
        win.isMinimized = false
        win.pendingOpenAnimation = true
        // Restoring a window on another space follows it there (macOS dock)
        // — on the window's OWN monitor only.
        let owner = displayLayout.map { $0.owningOutput(ofRect: win.rect).id }
            ?? hostOutputId
        if win.spaceId != activeSpaceId(onOutput: owner),
           let idx = spaceIndex(ofSpaceId: win.spaceId) {
            switchToSpace(idx, onOutput: owner)
        }
        bringToFront(id)
        onWindowsChanged?()
    }

    // MARK: - Tiling

    /// dwm-style master-stack tiling. Floating is the default; the desktop
    /// context menu toggles this and DesktopShell persists the choice.
    var tilingEnabled: Bool = false

    /// Fraction of the work-area width the master (first) window takes
    /// when stacked windows exist.
    static let kTileMasterRatio: Double = 0.58
    /// Gap between tiles and around the work-area edges — with rounded
    /// corners and the glass backdrop, the wallpaper reads through the
    /// seams (i3-gaps look).
    static let kTileGap: Double = 10.0

    /// Fired after any mutation that changes which windows are visible
    /// where (add/close/minimize/restore/space changes). DesktopShell wires
    /// this to a retile so tiled layouts stay current without every call
    /// site knowing about tiling.
    /// The shell's own hook. Reassigned during shell start-up, so anything
    /// else that wants to hear about changes uses `windowsObserver` instead.
    var onWindowsChanged: (() -> Void)? {
        get {
            guard _onWindowsChanged != nil || windowsObserver != nil else { return nil }
            return { [self] in _onWindowsChanged?(); windowsObserver?() }
        }
        set { _onWindowsChanged = newValue }
    }
    private var _onWindowsChanged: (() -> Void)? = nil
    /// A second listener (the operator socket's event stream) that the shell
    /// cannot overwrite.
    var windowsObserver: (() -> Void)? = nil

    /// Windows that participate in tiling on one space: visible, not
    /// fullscreen (fullscreen lives in its own private space), not
    /// agent-owned. Creation order — stable master-stack assignment.
    private func _tilableWindows(inSpaceId spaceId: Int) -> [WindowInfo] {
        windows.filter {
            !$0.isMinimized && !$0.isFullscreen && $0.spaceId == spaceId
                && $0.ownerAgentId == nil
        }
    }

    /// Retile every user space (cheap — a handful of windows; no-op when
    /// tiling is off or nothing moved).
    func retileAll(screenWidth: Double, screenHeight: Double) {
        guard tilingEnabled else { return }
        for space in spaces where space.isUser {
            retile(spaceId: space.id, screenWidth: screenWidth, screenHeight: screenHeight)
        }
    }

    /// Master-stack layout for one space: a single window fills the work
    /// area; otherwise the master takes the left kTileMasterRatio and the
    /// rest stack vertically on the right. Windows are grouped per output
    /// (multi-display tiles each output independently). Unlike maximize,
    /// tiles reserve the dock strip — overlapping tiled windows with the
    /// dock would hide their bottom edges permanently.
    func retile(spaceId: Int, screenWidth: Double, screenHeight: Double) {
        guard tilingEnabled else { return }
        let tilable = _tilableWindows(inSpaceId: spaceId)
        guard !tilable.isEmpty else { return }

        // Group by owning output (compared via the output's fill rect).
        var groups: [(fill: Rect, wins: [WindowInfo])] = []
        for win in tilable {
            let fill = _outputFillRect(for: win.rect, screenWidth: screenWidth,
                                       screenHeight: screenHeight)
            if let i = groups.firstIndex(where: { $0.fill == fill }) {
                groups[i].wins.append(win)
            } else {
                groups.append((fill, [win]))
            }
        }

        let gap = Self.kTileGap
        let dockReserve = shellMetrics.bottomInset
        for group in groups {
            let area = Rect.fromLTWH(
                group.fill.left + gap,
                group.fill.top + gap,
                group.fill.width - gap * 2,
                group.fill.height - dockReserve - gap * 2)

            var rects: [Rect] = []
            if group.wins.count == 1 {
                rects = [area]
            } else {
                let masterW = (area.width - gap) * Self.kTileMasterRatio
                let stackW = area.width - gap - masterW
                rects.append(Rect.fromLTWH(area.left, area.top, masterW, area.height))
                let n = Double(group.wins.count - 1)
                let each = (area.height - gap * (n - 1)) / n
                for i in 0..<(group.wins.count - 1) {
                    rects.append(Rect.fromLTWH(
                        area.left + masterW + gap,
                        area.top + Double(i) * (each + gap),
                        stackW, each))
                }
            }
            for (win, r) in zip(group.wins, rects) {
                if win.preTileRect == nil { win.preTileRect = win.rect }
                win.isMaximized = false
                win.savedRect = nil
                guard win.rect != r else { continue }
                win.rect = r
                _notifyClientResize(win, r)
            }
        }
    }

    /// Leave tiling: every window returns to the floating rect it had when
    /// tiling first captured it.
    func restoreFloatingLayout() {
        for win in windows {
            guard let saved = win.preTileRect else { continue }
            win.preTileRect = nil
            guard win.rect != saved else { continue }
            win.rect = saved
            _notifyClientResize(win, saved)
        }
    }

    /// Tell the client its content size changed. Wayland/X11 windows have
    /// the unthrottled onResizeComplete; DMA-BUF child-process windows only
    /// wire onContentResize — without it they keep the old buffer and the
    /// shell stretches it.
    private func _notifyClientResize(_ win: WindowInfo, _ r: Rect) {
        let contentW = r.width
        let contentH = r.height - DesktopTheme.kTitleBarHeight
        guard contentW > 0, contentH > 0 else { return }
        if let force = win.onResizeComplete {
            force(contentW, contentH)
        } else {
            win.onContentResize?(contentW, contentH)
        }
    }

    /// Every window the desktop is currently showing, across all outputs,
    /// sorted by z-index. The rule: a window is visible iff its space is the
    /// active space of the output that OWNS it (contains its centre) — each
    /// panel shows its own space's windows, and a straddler then renders its
    /// portion on every screen it touches, whatever those screens show.
    /// At N=1 (or with no layout) this is exactly the old "active space's
    /// windows". Renderers filter by intersection, so both trees consume
    /// this list unchanged.
    var visibleWindows: [WindowInfo] {
        guard let dl = displayLayout, dl.outputs.count > 1 else {
            return visibleWindows(inSpaceId: activeSpace.id)
        }
        return windows
            .filter { w in
                guard !w.isMinimized, w.ownerAgentId == nil else { return false }
                return w.spaceId ==
                    activeSpaceId(onOutput: dl.owningOutput(ofRect: w.rect).id)
            }
            .sorted { $0.zIndex < $1.zIndex }
    }

    /// Visible (non-minimized) windows of one space, sorted by z-index —
    /// the PURE space filter, blind to which outputs show what. Mission
    /// Control's thumbnails need exactly this (they preview inactive
    /// spaces); rendering paths should go through `visibleWindows`.
    func visibleWindows(inSpaceId spaceId: Int) -> [WindowInfo] {
        return windows
            .filter { !$0.isMinimized && $0.spaceId == spaceId && $0.ownerAgentId == nil }
            .sorted { $0.zIndex < $1.zIndex }
    }

    /// What the HOST tree draws for one layer of a space-switch slide:
    /// that space's windows, minus any owned by an output that is showing a
    /// DIFFERENT space — those are the other monitor's business and must
    /// not ride the host's animation.
    func hostSlideWindows(inSpaceId spaceId: Int) -> [WindowInfo] {
        slideWindows(inSpaceId: spaceId, onOutput: hostOutputId)
    }

    /// The general form for ANY output's slide: `spaceId`'s windows, minus
    /// those owned by a different output showing a different space.
    func slideWindows(inSpaceId spaceId: Int, onOutput outputId: Int) -> [WindowInfo] {
        guard let dl = displayLayout, dl.outputs.count > 1 else {
            return visibleWindows(inSpaceId: spaceId)
        }
        return visibleWindows(inSpaceId: spaceId).filter { w in
            let owner = dl.owningOutput(ofRect: w.rect).id
            return owner == outputId
                || activeSpaceId(onOutput: owner) == spaceId
        }
    }
}
