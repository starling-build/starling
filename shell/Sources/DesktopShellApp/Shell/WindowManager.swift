// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge

// MARK: - WindowInfo

/// Model for a single desktop window.
class WindowInfo {
    let id: String
    var title: String
    var appId: String
    /// What the client called itself: `xdg_toplevel.set_app_id` for a Wayland
    /// window, nil for windows the shell created itself (those carry a real
    /// `appId` already). This is the authoritative link from a window back to
    /// an installed app — it matches the `StartupWMClass` the app's `.desktop`
    /// entry declares, which `app-install` records into the app registry.
    var wmClass: String? = nil
    var rect: Rect
    var zIndex: Int
    var isMinimized: Bool
    var isMaximized: Bool
    var isFullscreen: Bool
    var savedRect: Rect?
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
    /// Set while the HUMAN has taken this window back from its agent, by
    /// touching it in the agent's workspace. Cleared by Esc.
    ///
    /// While it holds, every broker op that acts on the window **or reads its
    /// contents** refuses — reads included, because a window someone has
    /// grabbed to type a password into is exactly the one an agent must not
    /// be screenshotting. `AgentBroker.ownedWindow()` is the single place
    /// that enforces it, for the same reason it is the single place that
    /// enforces ownership.
    var humanHoldsControl: Bool = false
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

    /// The broker agent bound to this workspace: the app in the driver slot
    /// spawned it, so what it opens belongs here. Set by process ancestry
    /// when the agent connects, never guessed from names.
    var agentId: String? = nil

    /// True when this entry stands for a broker AGENT rather than a workspace
    /// the human made — its `id` is the agent id.
    ///
    /// That identity is the whole trick and not a coincidence: workspace
    /// membership is `ownerAgentId == workspaceId`, and an agent's windows
    /// already carry `ownerAgentId == agentId`. So giving the agent a rail
    /// entry under its own id makes `windows(inWorkspace:)` resolve them with
    /// no second lookup, and the rail, the tab strip and the panes light up
    /// unchanged. What the flag is for is the handful of places where an
    /// agent is NOT a workspace: it cannot be renamed or deleted by hand, and
    /// its windows must not be resized to the pane (see
    /// `_applyWorkspaceWindowGeometry`).
    var isAgent: Bool = false

    init(id: String, name: String, isAgent: Bool = false) {
        self.id = id
        self.name = name
        self.isAgent = isAgent
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

    /// The name to put in front of a person. `name` carries a " (socket)"
    /// suffix that marks how the agent connected — useful in an audit line,
    /// noise in the workspace rail, where "starling-computer-use (socket)"
    /// reads as a malfunction rather than as Claude Desktop.
    var displayName: String {
        name.hasSuffix(" (socket)")
            ? String(name.dropLast(" (socket)".count)) : name
    }
    /// The window id of the agent's TerminalApp window, once its first
    /// frame arrived. The tile's terminal pane composites this window.
    var terminalWindowId: String? = nil
    /// True for agents registered over the broker socket (external clients:
    /// MCP servers, CI harnesses, agent-client.py). They have no terminal
    /// unless they launch one.
    var isExternal: Bool = false
    /// The process that opened the broker connection, from the kernel's peer
    /// credentials. An MCP server is a child of the desktop app that spawned
    /// it — Claude Desktop's is a DIRECT child of its Electron main process,
    /// which is also the process holding the Wayland connection — so walking
    /// up from here finds the app to pair the agent's workspace with.
    var clientPid: pid_t = 0

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
    /// Focus changes are announced, because a Wayland client needs the
    /// keyboard BEFORE the first key rather than because of it — see
    /// `WaylandIntegration.focusKeyboard`. Set in a dozen places, so the
    /// announcement lives here rather than at each of them.
    var focusedWindowId: String? = nil {
        didSet {
            if focusedWindowId != oldValue, let id = focusedWindowId {
                onFocusedWindowChanged?(id)
            }
        }
    }
    var onFocusedWindowChanged: ((String) -> Void)?
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
    /// Last chance to bind an agent to the workspace whose driver spawned it,
    /// asked just before it would be given a rail entry of its own. Installed
    /// by the shell, which is the side that can read process ancestry.
    /// Returns true when a workspace claimed it.
    var onAgentNeedsWorkspace: ((String) -> Bool)? = nil
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
        //
        // Agent entries are skipped: an agent is not a place to work, and
        // since the rail went there is nothing to select it FROM. Its windows
        // are drawn in the human's workspace instead (`_wsVisibleWindows`).
        let taken = displayedWorkspaceIds(excluding: outputId)
        return workspaces.first(where: { !taken.contains($0.id) && !$0.isAgent })
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

    /// Give an agent a rail entry, so what it is doing can be watched. Called
    /// when an agent's first window appears; idempotent after that.
    ///
    /// Deliberately does NOT select it. An agent opening a window must never
    /// move the human's view — that is the property the whole agent-window
    /// design rests on, and `addWorkspace` selects, which is why this is not
    /// written in terms of it.
    @discardableResult
    func ensureAgentWorkspace(agentId: String, name: String) -> WorkspaceInfo {
        if let existing = workspaces.first(where: { $0.id == agentId }) {
            return existing
        }
        let ws = WorkspaceInfo(id: agentId, name: name, isAgent: true)
        workspaces.append(ws)
        return ws
    }

    /// Drop an agent's rail entry once it owns nothing worth looking at.
    ///
    /// Unlike `removeWorkspace` this does not refuse to remove the last one:
    /// that guard exists so the human cannot delete their way to an empty
    /// rail, and an agent entry is not theirs to keep. `_buildWorkspaceSpace`
    /// already renders a nil selection as the bare rail.
    func removeAgentWorkspace(_ agentId: String) {
        guard let idx = workspaces.firstIndex(where: {
            $0.id == agentId && $0.isAgent
        }) else { return }
        workspaces.remove(at: idx)
        for (out, id) in selectedWorkspaceIdByOutput where id == agentId {
            selectedWorkspaceIdByOutput.removeValue(forKey: out)
        }
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
        // Plus the bound agent's own windows. Those stay owned by the AGENT
        // rather than by the workspace on purpose: it is what still tells an
        // agent's window from the app driving it, which decides whether the
        // pane resizes it and whether touching it is a take-over.
        let bound = workspaces.first(where: { $0.id == workspaceId })?.agentId
        return windows.filter {
            $0.ownerAgentId == workspaceId
                || ($0.ownerAgentId != nil && $0.ownerAgentId == bound)
        }
    }

    /// The workspace a broker agent's windows belong to, if one has claimed
    /// it. Nil for an agent nobody launched from a workspace.
    func workspace(forAgent agentId: String) -> WorkspaceInfo? {
        workspaces.first { $0.agentId == agentId }
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
            // The rail entry that makes this window watchable. Here rather
            // than only at the Wayland call site, because a broker agent
            // opens windows two different ways — a Wayland client's toplevel
            // arrives later and is tagged after the fact, while a first-party
            // child is owned right here — and hooking one of them is how
            // launching Settings through the broker produced a workspace that
            // never appeared.
            // A rail entry of its OWN, but only for an agent no workspace
            // claimed. One launched from a workspace already has a home, and
            // giving it a second entry would list the same windows twice.
            //
            // The retry is not belt-and-braces. Binding happens when the
            // agent says hello, and Claude Desktop starts its MCP server as
            // it boots — possibly BEFORE its own window has arrived and been
            // claimed as the driver, in which case the walk up the process
            // tree finds no window and the bind fails. Losing that race would
            // put a duplicate rail entry beside the workspace that launched
            // it, intermittently. By the time an agent opens a window the
            // driver is certainly there.
            if workspace(forAgent: agentId) == nil,
               onAgentNeedsWorkspace?(agentId) != true,
               let agent = agents.first(where: { $0.id == agentId }) {
                ensureAgentWorkspace(agentId: agentId, name: agent.displayName)
            }
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
        var ownerId: String? = nil
        if let win = windows.first(where: { $0.id == id }) {
            ownerId = win.ownerAgentId
            win.onWindowClose?()
        }
        windows.removeAll { $0.id == id }
        // A workspace whose driver window just went away has no driver. The
        // column already TOLERATES a dead id — it looks the window up and
        // falls into its empty state — which hid this for as long as it was
        // only cosmetic: the state that offers "run an agent here" was on
        // screen, and the id behind it was a corpse. But launching from that
        // empty state only takes the driver slot `if driverWindowId == nil`,
        // so the corpse refused it: quit Claude Desktop, click Claude again,
        // and it opens as a TAB while the left column keeps offering to run
        // an agent. Once per workspace, permanently, until the shell restarts.
        for ws in workspaces where ws.driverWindowId == id {
            ws.driverWindowId = nil
        }
        // An agent's rail entry lasts as long as it has something to show.
        // Read the owner BEFORE the removal above and check after it, or the
        // window being closed still counts itself.
        if let ownerId, windows(ownedBy: ownerId).isEmpty {
            removeAgentWorkspace(ownerId)
        }
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

        // Enforce minimum size
        if r - l < DesktopTheme.kMinWindowWidth {
            if edge == .left || edge == .topLeft || edge == .bottomLeft {
                l = r - DesktopTheme.kMinWindowWidth
            } else {
                r = l + DesktopTheme.kMinWindowWidth
            }
        }
        if b - t < DesktopTheme.kMinWindowHeight {
            if edge == .top || edge == .topLeft || edge == .topRight {
                t = b - DesktopTheme.kMinWindowHeight
            } else {
                b = t + DesktopTheme.kMinWindowHeight
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
        if let dl = displayLayout {
            let o = dl.owningOutput(ofRect: ref)
            return Rect.fromLTWH(o.logicalLeft, o.logicalTop + topInset,
                                 o.logicalWidth, o.logicalHeight - inset)
        }
        return Rect.fromLTWH(0, topInset, screenWidth, screenHeight - inset)
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
            // macOS-style fullscreen: window sits BELOW the system status bar
            // — the status-bar strip is reserved and not given to the app
            // even when the bar is auto-hidden. The window's own title bar
            // auto-hides and overlays within the window when revealed
            // (handled in DesktopWindow).
            win.savedRect = win.rect
            win.rect = _outputFillRect(for: win.rect, screenWidth: screenWidth, screenHeight: screenHeight)
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
    var onWindowsChanged: (() -> Void)? = nil

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
