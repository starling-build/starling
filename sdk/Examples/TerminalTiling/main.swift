// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The terminal workspace — TerminalDemo's grown-up sibling, and a demo of
// what TerminalView being a *widget* buys you (docs/plans/terminal-widget.md).
// TerminalDemo is one session filling a window; this is many of them, each
// with its own shell, scrollback and child process, arranged two ways.
//
//   swift run -c release TerminalTiling
//   swift run -c release TerminalTiling "top -d 1"    # what new panes run
//
// TILING or FULL SCREEN, from the toolbar. The panes are the same either
// way — one split tree says which panes exist; the mode only decides whether
// they share the window or take turns at all of it.
//
// Ctrl+Shift+Up (or the toolbar's Overview) shows every window at once, the
// way Mission Control does: a grid of cards, each rendering what is actually
// on that terminal's screen right now, arrows to choose and Enter to open.
// A full-screen terminal is the right shape for working and the wrong shape
// for finding, so finding gets its own view rather than a list of titles to
// guess from. The chord has to be taken before the terminal sees it —
// TerminalView.keyFilter exists for exactly that.
//
// (Floating windows were tried here and thrown out: a terminal is a
// rectangle of text you want as much of as possible, and dragging little
// windows around to see two at once is what tiling already does better.)
//
// Tiling, with the part tiling window managers get wrong made right: the
// seams are draggable. Panes never overlap and never leave dead space, and
// any boundary can still be pulled to give one side more room — live, with
// the child processes resized as it moves (a pane's TerminalView is told
// its box, so the grid follows and the shell gets its SIGWINCH). A split
// is a ratio, not a pixel count, so resizing the window redistributes
// every pane proportionally and nothing has to be re-tiled.
//
// A new pane asks what to run before it runs anything, because opening a
// terminal is usually opening it FOR something — most often to reach
// another machine, whose name is the part nobody remembers. The launcher
// offers the Host entries from ~/.ssh/config and the commands run before;
// type to filter, ↑↓ to choose, Enter to run, Enter on an empty line (or
// Escape) for a plain shell. A pane that knows its command puts it back:
// ↻ on `ssh prod-1` reconnects, where a pane that merely once typed it
// would come back as a local shell.
//
// Click a pane's title to name it — a wall of shells reads better as
// "build", "logs", "prod" than as Terminal 1..4. The rename owns a focus
// node of its own (every pane's terminal wants the keyboard) and hands it
// back when you press Enter.
//
// The app is only geometry: no terminal code, no escape sequences, no pty.

#if os(Linux) || os(Windows)
import ExampleHost
import Flutter
import FlutterSwiftBridge   // Color, Offset, Size
import Foundation

// MARK: - Chrome

enum Tile {
    static let gutter = Color(0xFF0B0E12)
    static let titleBar = Color(0xFF23282F)
    static let titleBarActive = Color(0xFF2F3742)
    static let titleBarEditing = Color(0xFF35506E)
    static let titleText = Color(0xFF98A1AD)
    static let titleTextActive = Color(0xFFE6EAF0)
    static let titleTextEditing = Color(0xFFFFFFFF)
    static let border = Color(0xFF11151A)
    static let close = Color(0xFFFF5F57)
    static let closeIdle = Color(0xFF6E5A5E)
    static let action = Color(0xFF7C8695)
    static let actionActive = Color(0xFFCBD3DE)
    static let seamActive = Color(0xFF3E8FE0)
    static let launcherBg = Color(0xFF13171D)
    static let launcherInput = Color(0xFFE8EDF4)
    static let launcherItem = Color(0xFF9AA4B2)
    static let launcherPick = Color(0xFF7FD1A0)
    static let launcherHint = Color(0xFF667180)
    static let bar = Color(0xFF171C24)
    static let barFill = Color(0xFF222833)
    static let barPick = Color(0xFF35506E)
    static let barDim = Color(0xFF4A5364)
    static let grip = Color(0x8CFFFFFF)
    /// Fully transparent, not absent: the hit area stays live so the corner
    /// can still be grabbed by a pointer that arrives without hovering first.
    static let gripHidden = Color(0x00000000)
    static let flowScrim = Color(0xE60A0D12)
    static let flowDim = Color(0xFF5C6675)

    static let barH: Double = 32

    /// The terminal's own palette for a windowed app.
    static let terminal = TerminalTheme(background: 0xFF14181E)

    static let titleBarH: Double = 30
    /// The draggable strip between two panes: wide enough to hit without
    /// aiming, with a thinner line drawn inside it.
    static let seamW: Double = 8
    /// No pane may be squeezed below this by a seam drag.
    static let minPane: Double = 180
}

// MARK: - The split tree

/// How the workspace arranges its panes. The same panes, two presentations:
/// tiling fills the window with all of them at once; full screen gives the
/// whole window to one and keeps the rest running behind it.
///
/// (Floating windows were tried here and thrown out: a terminal is a
/// rectangle of text you want as much of as possible, and dragging little
/// windows around to see two of them is what tiling already does better.)
enum WorkspaceMode {
    case tiling
    case fullScreen
}

enum SplitAxis {
    /// Children side by side, divided by a vertical seam.
    case row
    /// Children stacked, divided by a horizontal seam.
    case column
}

/// A rectangle in logical pixels. (Not `Rect`: the bridge has one.)
struct Box {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

/// One terminal: a session and an identity that survives re-tiling.
final class Pane {
    let id: Int
    let session: TerminalSession
    /// What the title bar calls this pane. nil until the user renames it —
    /// click the title to type a name, so a wall of shells can say "build",
    /// "logs", "prod" rather than counting from one.
    var name: String?
    /// What this pane runs, nil for a plain login shell. It is also what
    /// restart repeats, which is the point of asking: a pane that IS
    /// `ssh prod-1` reconnects, where a pane that merely once typed it
    /// would come back as a local shell.
    var command: String?
    /// Nothing has been started yet — the pane is asking what to run.
    var pending = true
    /// The launcher's input line and highlighted suggestion, per pane: a
    /// split can leave two panes waiting at once, each half-typed.
    var launchText = ""
    var launchIndex = 0
    /// Bumped to remount the pane, which is how the terminal takes the
    /// keyboard back after a rename, a launch or a restart (a mounted
    /// TerminalView autofocuses only when it mounts).
    var focusEpoch = 0
    /// Set when this pane's session lives on another machine. The pane is
    /// otherwise identical — same widget, same keys, same resize — because
    /// the transport drives a headless session (docs/plans/remote-terminal.md).
    var remote: RemoteTerminal?
    var link: RemoteTerminal.Link = .connecting


    init(id: Int) {
        self.id = id
        self.session = TerminalSession()
    }

    var title: String {
        var base: String
        if let name = name, !name.isEmpty { base = name }
        else if let command = command, !command.isEmpty { base = command }
        else { base = "Terminal \(id)" }
        // A remote pane says what its link is doing, because a frozen screen
        // and a dropped link look identical otherwise.
        if remote != nil {
            switch link {
            case .connecting:              base += "  ·  connecting"
            case .live(let id):            base += "  ·  #\(id)"
            case .reconnecting(let n):     base += "  ·  reconnecting (\(n))"
            case .closed(let why):         base += "  ·  " + (why ?? "closed")
            }
        }
        return base
    }
}

// MARK: - What to run

/// `remote:host`, `remote:host/12`, or `remote:host -- command`.
///
/// One syntax for the workflow this exists for: ssh somewhere, leave
/// something running, come back to it. `host` is whatever ssh understands
/// (an alias from ~/.ssh/config, user@host, a jump-host alias); `/12`
/// re-attaches a known session id instead of opening a new one.
struct RemoteSpec {
    let host: String
    let session: UInt32?
    let command: String?

    init?(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.lowercased().hasPrefix("remote:") else { return nil }
        var rest = String(t.dropFirst("remote:".count))
        var cmd: String? = nil
        if let sep = rest.range(of: " -- ") {
            cmd = String(rest[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
            rest = String(rest[..<sep.lowerBound])
        }
        rest = rest.trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        if let slash = rest.lastIndex(of: "/"),
           let id = UInt32(rest[rest.index(after: slash)...]) {
            host = String(rest[..<slash])
            session = id
        } else {
            host = rest
            session = nil
        }
        command = (cmd?.isEmpty ?? true) ? nil : cmd
    }
}

/// Where the launcher's suggestions come from.
///
/// Opening a terminal to reach another machine is the common case, and the
/// hostname is exactly the part nobody remembers — so `~/.ssh/config` is
/// read for its `Host` entries and offered directly. Past commands are
/// remembered beside them, most recent first, so the second `ssh` to the
/// same box is one keystroke.
enum Launcher {
    struct Suggestion {
        let command: String
        let source: String
    }

    private static var historyPath: String {
        let home = realUserHomeDirectory()
        return home + "/.local/state/starling-terminal-commands"
    }

    /// Commands run before, newest first.
    static func history() -> [String] {
        guard let text = try? String(contentsOfFile: historyPath, encoding: .utf8)
        else { return [] }
        var seen = Set<String>()
        return text.split(separator: "\n").reversed().compactMap { line in
            let s = String(line).trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty, seen.insert(s).inserted else { return nil }
            return s
        }
    }

    static func remember(_ command: String) {
        let line = command.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }
        let path = historyPath
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try? handle.close()
        } else {
            try? (line + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// `Host` entries from ~/.ssh/config, minus the patterns — a `Host *`
    /// block configures every connection, it is not a machine to reach.
    static func sshHosts() -> [String] {
        let path = realUserHomeDirectory() + "/.ssh/config"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8)
        else { return [] }
        var hosts: [String] = []
        for line in text.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  parts[0].lowercased() == "host" else { continue }
            for host in parts.dropFirst() where
                !host.contains("*") && !host.contains("?") {
                hosts.append(String(host))
            }
        }
        return hosts
    }

    /// The list a pane offers, filtered by what has been typed so far.
    static func suggestions(matching typed: String) -> [Suggestion] {
        var out: [Suggestion] = []
        var seen = Set<String>()
        for command in history() where seen.insert(command).inserted {
            out.append(Suggestion(command: command, source: "recent"))
        }
        for host in sshHosts() {
            // The persistent form first: this is the workflow the remote
            // session exists for, and plain ssh is one line below it.
            let persistent = "remote:\(host)"
            if seen.insert(persistent).inserted {
                out.append(Suggestion(command: persistent, source: "keeps running"))
            }
            let command = "ssh \(host)"
            if seen.insert(command).inserted {
                out.append(Suggestion(command: command, source: "~/.ssh/config"))
            }
        }
        let needle = typed.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return out }
        return out.filter { $0.command.lowercased().contains(needle) }
    }
}

/// A node in the layout: a pane (leaf), or a split of two children at a
/// ratio. Ratios rather than pixels are what make the tree resolution
/// independent — the window resizing and a seam being dragged are the same
/// operation applied at different levels.
final class Node {
    var pane: Pane?
    var axis: SplitAxis = .row
    var ratio: Double = 0.5
    var first: Node?
    var second: Node?
    weak var parent: Node?

    init(pane: Pane) { self.pane = pane }

    var isLeaf: Bool { pane != nil }

    func forEachLeaf(_ body: (Node) -> Void) {
        if isLeaf { body(self); return }
        first?.forEachLeaf(body)
        second?.forEachLeaf(body)
    }
}

// MARK: - The workspace

final class TilingTerminal: StatefulWidget {
    override func createState() -> State<StatefulWidget> { _TilingState() }
}

final class _TilingState: State<StatefulWidget>, @unchecked Sendable {

    private var root: Node!
    private var _nextId = 1
    /// The pane the chrome draws as active. Keyboard focus follows the click
    /// by itself — TerminalView requests focus on pointer down — and this is
    /// the app's record of it, so the title bars agree with the cursor.
    private var _activeId = 1

    /// The seam being dragged, and the pointer at the last move event: the
    /// seam moves under the pointer, so successive LOCAL positions would
    /// chase each other while global deltas do not.
    private var _dragSeam: Node?
    private var _lastPointer: Offset?

    /// Where each node was laid out last frame. A seam drag turns a pixel
    /// delta into a ratio, which needs the box of the split it divides —
    /// and `build` is the only thing that knows it.
    private var _boxes: [ObjectIdentifier: Box] = [:]

    /// What new panes run: the user's shell, or a command from argv.
    private static let command: String? = {
        let args = CommandLine.arguments.dropFirst().filter { !$0.isEmpty }
        return args.isEmpty ? nil : args.joined(separator: " ")
    }()

    /// The pane whose name is being edited, and the text so far. The editor
    /// is deliberately hand-rolled rather than a TextBox: the keyboard is
    /// contested here — every pane's terminal wants it — so the rename owns
    /// a focus node of its own and hands it straight back when done.
    private var _renaming: Pane?
    private var _renameText = ""
    private let _renameFocus = FocusNode(debugLabel: "PaneName")
    private static let nameLimit = 32

    /// The pane whose launcher has the keyboard, and its own focus node for
    /// the same reason the rename has one.
    private var _launching: Pane?
    private let _launchFocus = FocusNode(debugLabel: "PaneCommand")

    /// Tiling or floating. The panes are the same either way.
    private var _mode: WorkspaceMode = .tiling

    /// Modifier state, tracked from the keys the terminal lets past us.
    private var _ctrlDown = false
    private var _shiftDown = false

    /// The overview: every pane at once, chosen with the arrows.
    private var _flowOpen = false
    private var _flowIndex = 0
    private let _flowFocus = FocusNode(debugLabel: "PaneFlow")

    override func initState() {
        super.initState()
        // The bundled fonts are registered by TerminalView on mount — and at
        // startup no terminal has mounted yet, because the first pane is
        // still asking what to run. Without this the launcher and the title
        // bars draw in whatever the default face is, and every box-drawing
        // and arrow glyph in them comes out as tofu.
        TerminalFontLoader.register()
        root = Node(pane: _newPane())
        _renameFocus.onKeyData = { [weak self] keyData in
            self?._handleRenameKey(keyData) ?? false
        }
        _launchFocus.onKeyData = { [weak self] keyData in
            self?._handleLaunchKey(keyData) ?? false
        }
        _flowFocus.onKeyData = { [weak self] keyData in
            self?._handleFlowKey(keyData) ?? false
        }
        // Clicking a terminal takes focus away mid-edit; keep the name typed
        // so far rather than dropping the user's work.
        _renameFocus.onFocusChange = { [weak self] focused in
            guard let self = self, !focused, self._renaming != nil else { return }
            self._commitRename()
        }
    }

    override func dispose() {
        _renameFocus.dispose()
        _launchFocus.dispose()
        _flowFocus.dispose()
        root.forEachLeaf { $0.pane?.session.terminate() }
        super.dispose()
    }

    // MARK: - Asking what to run

    private func _beginLaunch(_ pane: Pane) {
        _activeId = pane.id
        _launching = pane
        _launchFocus.requestFocus()
        setState {}
    }

    /// Start the pane: a remote session, a command, or the login shell.
    private func _launch(_ pane: Pane, _ command: String?) {
        pane.pending = false
        pane.command = command
        if let command = command, !command.isEmpty {
            Launcher.remember(command)
            if let spec = RemoteSpec(command) {
                // The session lives on the far machine and outlives this
                // client; the widget above never learns the difference.
                let remote = RemoteTerminal(session: pane.session,
                                            host: spec.host,
                                            attach: spec.session,
                                            command: spec.command)
                remote.onLink = { [weak self] link in
                    DispatchQueue.main.async {
                        pane.link = link
                        self?.setState {}
                    }
                }
                pane.remote = remote
                remote.start()
            } else {
                pane.session.startCommand(command)
            }
        } else {
            pane.session.startShell()
        }
        if _launching === pane {
            _launching = nil
            if _launchFocus.hasFocus { _launchFocus.unfocus() }
        }
        // The terminal is about to mount for the first time; the remount is
        // what hands it the keyboard.
        pane.focusEpoch += 1
        setState {}
    }

    private func _handleLaunchKey(_ keyData: KeyData) -> Bool {
        guard let pane = _launching else { return false }
        guard keyData.type == .down || keyData.type == .repeat else { return false }
        let matches = Launcher.suggestions(matching: pane.launchText)

        switch keyData.logical {
        case 0xFF0D, 0xFF8D, 0x1_0000_000D, 0x1_0000_020D:      // Enter
            // A highlighted suggestion wins over the typed text: arrowing to
            // a host and pressing Enter is the whole point of the list.
            let chosen = pane.launchIndex > 0 && pane.launchIndex <= matches.count
                ? matches[pane.launchIndex - 1].command
                : pane.launchText.trimmingCharacters(in: .whitespaces)
            _launch(pane, chosen.isEmpty ? nil : chosen)
            return true
        case 0xFF1B, 0x1_0000_001B:                             // Escape → shell
            _launch(pane, nil)
            return true
        case 0xFF08, 0x1_0000_0008:                             // Backspace
            if !pane.launchText.isEmpty {
                setState {
                    pane.launchText.removeLast()
                    pane.launchIndex = 0
                }
            }
            return true
        case 0xFF52, 0x1_0000_0304:                             // Up
            setState { pane.launchIndex = max(0, pane.launchIndex - 1) }
            return true
        case 0xFF54, 0x1_0000_0301, 0xFF09, 0x1_0000_0009:      // Down / Tab
            setState { pane.launchIndex = min(matches.count, pane.launchIndex + 1) }
            return true
        default:
            break
        }

        if let character = keyData.character,
           let scalar = character.unicodeScalars.first,
           scalar.value >= 0x20, scalar.value != 0x7F {
            setState {
                pane.launchText += character
                pane.launchIndex = 0
            }
            return true
        }
        return true   // while the launcher is up, nothing else takes keys
    }

    // MARK: - Renaming

    private func _beginRename(_ pane: Pane) {
        _activeId = pane.id
        _renaming = pane
        _renameText = pane.name ?? ""
        _renameFocus.requestFocus()
        setState {}
    }

    private func _commitRename() {
        guard let pane = _renaming else { return }
        let trimmed = _renameText.trimmingCharacters(in: .whitespaces)
        pane.name = trimmed.isEmpty ? nil : trimmed
        _endRename(pane)
    }

    private func _endRename(_ pane: Pane) {
        _renaming = nil
        _renameText = ""
        if _renameFocus.hasFocus { _renameFocus.unfocus() }
        // Remount the pane so its TerminalView autofocuses: that is how the
        // keyboard gets back to the terminal the user was working in.
        pane.focusEpoch += 1
        setState {}
    }

    private func _handleRenameKey(_ keyData: KeyData) -> Bool {
        guard _renaming != nil else { return false }
        guard keyData.type == .down || keyData.type == .repeat else { return false }
        // Editing keys arrive under two different conventions: X11 keysyms
        // from the DRM embedder (the Starling shell) and Flutter logical key
        // ids from the GTK and Win32 hosts (a stock GNOME session). The sdk's
        // own TerminalInput accepts both for exactly this reason; an example
        // that checked only keysyms would take letters but ignore Enter the
        // moment it ran on a desktop session.
        switch keyData.logical {
        case 0xFF0D, 0xFF8D, 0x1_0000_000D, 0x1_0000_020D:      // Enter
            _commitRename()
            return true
        case 0xFF1B, 0x1_0000_001B:                             // Escape
            if let pane = _renaming { _endRename(pane) }
            return true
        case 0xFF08, 0x1_0000_0008:                             // Backspace
            if !_renameText.isEmpty {
                setState { _renameText.removeLast() }
            }
            return true
        default:
            break
        }
        if let character = keyData.character,
           let scalar = character.unicodeScalars.first,
           scalar.value >= 0x20, scalar.value != 0x7F,
           _renameText.count < Self.nameLimit {
            setState { _renameText += character }
            return true
        }
        return true   // while renaming, the terminals stay out of it
    }

    // MARK: - Panes

    /// A new pane asks what to run before it runs anything. Opening a
    /// terminal is usually opening it *for* something — most often to reach
    /// another machine — and a pane that knows its command can put it back
    /// when the connection drops. Given one on argv, every pane runs that
    /// and the question is skipped.
    private func _newPane() -> Pane {
        let pane = Pane(id: _nextId)
        _nextId += 1
        _activeId = pane.id
        if let command = Self.command {
            // Through _launch, not startCommand: argv takes the same spellings
            // the launcher does, and `remote:host` has to reach RemoteSpec or
            // it is run as a local command and the shell reports it as a typo.
            _launch(pane, command)
        } else {
            _launching = pane
            _launchFocus.requestFocus()
        }
        return pane
    }

    /// Split a pane in two: it keeps one side, a fresh shell opens on the
    /// other. The leaf becomes the split in place, so anything holding a
    /// reference to it (a drag in flight) stays valid.
    private func _split(_ node: Node, axis: SplitAxis) {
        guard let pane = node.pane else { return }
        let keep = Node(pane: pane)
        let fresh = Node(pane: _newPane())
        node.pane = nil
        node.axis = axis
        node.ratio = 0.5
        node.first = keep
        node.second = fresh
        keep.parent = node
        fresh.parent = node
        setState {}
    }

    /// Close a pane; its sibling takes the space back. Closing the last one
    /// opens a fresh shell — a terminal that closes to an empty window reads
    /// as the app having quit.
    private func _close(_ node: Node) {
        if _renaming === node.pane { _renaming = nil; _renameText = "" }
        node.pane?.remote?.stop()
        node.pane?.session.terminate()
        guard let parent = node.parent,
              let sibling = (parent.first === node) ? parent.second : parent.first
        else {
            root = Node(pane: _newPane())
            setState {}
            return
        }
        // The parent becomes the sibling in place, so the sibling's own
        // subtree keeps its shape and its ratios.
        let closingActive = node.pane?.id == _activeId
        parent.pane = sibling.pane
        parent.axis = sibling.axis
        parent.ratio = sibling.ratio
        parent.first = sibling.first
        parent.second = sibling.second
        parent.first?.parent = parent
        parent.second?.parent = parent
        if closingActive {
            parent.forEachLeaf { if let p = $0.pane { _activeId = p.id } }
        }
        setState {}
    }

    private func _windowSize() -> Size {
        if let view = PlatformDispatcher.instance.implicitView {
            let dpr = view.devicePixelRatio
            let phys = view.physicalSize
            if phys.width > 0, phys.height > 0, dpr > 0 {
                return Size(phys.width / dpr, phys.height / dpr)
            }
        }
        return Size(1200, 780)
    }

    // MARK: - Layout

    /// Walks the tree assigning every node its box; leaves and seams come
    /// back in paint order, and `_boxes` keeps the rest for the drag.
    private func _resolve(_ node: Node, _ box: Box,
                          _ leaves: inout [(Node, Box)],
                          _ seams: inout [(Node, Box)]) {
        _boxes[ObjectIdentifier(node)] = box
        guard !node.isLeaf, let first = node.first, let second = node.second else {
            leaves.append((node, box))
            return
        }
        let s = Tile.seamW
        if node.axis == .row {
            let usable = max(0, box.w - s)
            let firstW = usable * node.ratio
            _resolve(first, Box(x: box.x, y: box.y, w: firstW, h: box.h), &leaves, &seams)
            seams.append((node, Box(x: box.x + firstW, y: box.y, w: s, h: box.h)))
            _resolve(second,
                     Box(x: box.x + firstW + s, y: box.y, w: usable - firstW, h: box.h),
                     &leaves, &seams)
        } else {
            let usable = max(0, box.h - s)
            let firstH = usable * node.ratio
            _resolve(first, Box(x: box.x, y: box.y, w: box.w, h: firstH), &leaves, &seams)
            seams.append((node, Box(x: box.x, y: box.y + firstH, w: box.w, h: s)))
            _resolve(second,
                     Box(x: box.x, y: box.y + firstH + s, w: box.w, h: usable - firstH),
                     &leaves, &seams)
        }
    }

    // MARK: - Build

    override func build(_ context: any BuildContext) -> Widget {
        let window = _windowSize()
        let barH = Tile.barH
        let workspace = Size(window.width, max(1, window.height - barH))

        var layers: [Widget] = [
            Positioned(fill: (), child: ColoredBox(color: Tile.gutter))
        ]
        switch _mode {
        case .tiling:     layers += _tilingLayers(workspace)
        case .fullScreen: layers += _fullScreenLayers(workspace)
        }
        if _flowOpen { layers.append(_overlay(workspace)) }

        return Directionality(
            textDirection: .ltr,
            child: Column(
                crossAxisAlignment: .stretch,
                children: [
                    _topBar(width: window.width),
                    SizedBox(width: workspace.width, height: workspace.height,
                             child: Stack(children: layers)),
                ]
            )
        )
    }

    // MARK: - Tiling

    private func _tilingLayers(_ workspace: Size) -> [Widget] {
        var leaves: [(Node, Box)] = []
        var seams: [(Node, Box)] = []
        _boxes.removeAll(keepingCapacity: true)
        _resolve(root, Box(x: 0, y: 0, w: workspace.width, h: workspace.height),
                 &leaves, &seams)

        var layers: [Widget] = []
        for (node, box) in leaves { layers.append(_paneWidget(node, box)) }
        // The close/split controls are their own layer rather than children
        // of the pane. A pane activates on any click inside it, and an
        // ancestor Listener sees every event its descendants see — so a
        // split button nested in the pane would activate the pane it was
        // splitting *away* from, undoing the new pane's focus. As a sibling
        // layer it absorbs the hit outright.
        for (node, box) in leaves { layers.append(_paneControls(node, box)) }
        // Seams paint above the panes for the same reason: they are 8px of
        // hit area, and the drag has to win over the terminal underneath.
        for (node, box) in seams { layers.append(_seamWidget(node, box)) }
        return layers
    }

    // MARK: - Full screen

    /// Every pane, in tree order — the order the overview lays them out in
    /// and the order the arrow keys walk.
    private func _allPanes() -> [(Node, Pane)] {
        var out: [(Node, Pane)] = []
        root.forEachLeaf { node in
            if let pane = node.pane { out.append((node, pane)) }
        }
        return out
    }

    /// One terminal, the whole window. The others are not hidden so much as
    /// not laid out: their shells keep running, their scrollback keeps
    /// filling, and the overview is how you get back to them.
    private func _fullScreenLayers(_ workspace: Size) -> [Widget] {
        let panes = _allPanes()
        guard !panes.isEmpty else { return [] }
        let entry = panes.first { $0.1.id == _activeId } ?? panes[0]
        _activeId = entry.1.id
        let box = Box(x: 0, y: 0, w: workspace.width, h: workspace.height)
        return [_paneWidget(entry.0, box), _paneControls(entry.0, box)]
    }

    /// First refusal on every key, handed to each TerminalView.
    ///
    /// A terminal claims nearly the whole keyboard, so an app chord has to be
    /// taken before the terminal sees it — Ctrl+Shift+Up here, which no TUI
    /// expects and xterm has never defined. Modifiers are watched rather than
    /// read off the event because the embedder reports them as their own key
    /// events, not as flags on the letter.
    private func _appChord(_ keyData: KeyData) -> Bool {
        let down = keyData.type == .down || keyData.type == .repeat
        switch keyData.logical {
        // X11 keysyms from the DRM embedder, Flutter logical ids from the
        // GTK/Win32 hosts — and the modifiers live in the 0x2000001xx block,
        // not the 0x1000001xx one the arrows come from.
        case 0xFFE1, 0xFFE2, 0x2_0000_0102, 0x2_0000_0103:   // shift
            _shiftDown = down
            return false
        case 0xFFE3, 0xFFE4, 0x2_0000_0100, 0x2_0000_0101:   // control
            _ctrlDown = down
            return false
        default:
            break
        }
        guard down, _ctrlDown, _shiftDown else { return false }
        switch keyData.logical {
        case 0xFF52, 0x1_0000_0304:            // Up — show every window
            if !_flowOpen { _openOverview() }
            return true
        default:
            return false
        }
    }

    // MARK: - Overview (all windows at once)

    /// Every pane at once, scaled down, the way Mission Control shows
    /// windows: a full-screen terminal is the right shape for working and
    /// the wrong shape for finding, so finding gets its own view rather
    /// than a list of titles to guess from. Each card renders what is
    /// actually on that terminal's screen right now.
    private func _openOverview() {
        let panes = _allPanes()
        guard !panes.isEmpty else { return }
        _flowIndex = panes.firstIndex { $0.1.id == _activeId } ?? 0
        _flowOpen = true
        _flowFocus.requestFocus()
        setState {}
    }

    private func _closeOverview(pick: Bool) {
        let panes = _allPanes()
        _flowOpen = false
        if _flowFocus.hasFocus { _flowFocus.unfocus() }
        if pick, _flowIndex >= 0, _flowIndex < panes.count {
            let pane = panes[_flowIndex].1
            _activeId = pane.id
            // Remount so the chosen terminal takes the keyboard, the same
            // way a finished rename hands it back.
            pane.focusEpoch += 1
        }
        setState {}
    }

    private func _handleFlowKey(_ keyData: KeyData) -> Bool {
        guard _flowOpen else { return false }
        guard keyData.type == .down || keyData.type == .repeat else { return false }
        let panes = _allPanes()
        let count = panes.count
        let columns = max(1, Int(ceil(Double(count).squareRoot())))
        switch keyData.logical {
        case 0xFF51, 0x1_0000_0302:                             // Left
            setState { _flowIndex = max(0, _flowIndex - 1) }
            return true
        case 0xFF53, 0x1_0000_0303:                             // Right
            setState { _flowIndex = min(count - 1, _flowIndex + 1) }
            return true
        case 0xFF52, 0x1_0000_0304:                             // Up
            setState { _flowIndex = max(0, _flowIndex - columns) }
            return true
        case 0xFF54, 0x1_0000_0301:                             // Down
            setState { _flowIndex = min(count - 1, _flowIndex + columns) }
            return true
        case 0xFF0D, 0xFF8D, 0x1_0000_000D, 0x1_0000_020D:      // Enter
            _closeOverview(pick: true)
            return true
        case 0xFF1B, 0x1_0000_001B:                             // Escape
            _closeOverview(pick: false)
            return true
        default:
            return true
        }
    }

    /// The last few lines a pane has on screen, for its card. Read under the
    /// session lock, like every other read of a live grid.
    private func _preview(_ pane: Pane, lines: Int, cols: Int) -> [String] {
        let session = pane.session
        session.lock.lock()
        let grid = session.emulator.grid
        session.lock.unlock()
        var out: [String] = []
        for row in grid {
            let text = String(row.prefix(cols).map { $0.char })
            if !text.trimmingCharacters(in: .whitespaces).isEmpty { out.append(text) }
        }
        if out.isEmpty { return ["", "  (nothing on screen yet)"] }
        return Array(out.suffix(lines))
    }

    private func _overlay(_ workspace: Size) -> Widget {
        let panes = _allPanes()
        let count = max(1, panes.count)
        let columns = max(1, Int(ceil(Double(count).squareRoot())))
        let rows = max(1, Int(ceil(Double(count) / Double(columns))))
        let pad = 26.0
        let cellW = (workspace.width - pad * Double(columns + 1)) / Double(columns)
        let cellH = (workspace.height - 64 - pad * Double(rows + 1)) / Double(rows)

        var layers: [Widget] = [
            // The scrim. A ColoredBox rather than a bare SizedBox because it
            // must actually dim; the Listener over it is what swallows clicks.
            Positioned(fill: (), child: Listener(
                onPointerDown: { [self] _ in _closeOverview(pick: false) },
                behavior: .opaque,
                child: ColoredBox(color: Tile.flowScrim)))
        ]
        for (i, entry) in panes.enumerated() {
            let x = pad + Double(i % columns) * (cellW + pad)
            let y = pad + Double(i / columns) * (cellH + pad)
            layers.append(
                Positioned(
                    left: x, top: y,
                    child: Listener(
                        onPointerDown: { [self] _ in
                            if i == _flowIndex { _closeOverview(pick: true) }
                            else { setState { _flowIndex = i } }
                        },
                        behavior: .opaque,
                        child: _overviewCard(entry.1, w: cellW, h: cellH,
                                             chosen: i == _flowIndex)
                    )
                )
            )
        }
        layers.append(
            Positioned(
                left: 0, top: workspace.height - 34,
                child: SizedBox(
                    width: workspace.width, height: 24,
                    child: Center(child: Text(
                        "↑↓←→ choose · Enter open · Esc cancel",
                        style: TextStyle(
                            color: Tile.launcherHint, fontSize: 12,
                            fontFamily: TerminalFontLoader.family,
                            fontFamilyFallback: TerminalFontLoader.fallback)))
                )
            )
        )
        return Positioned(fill: (), child: Stack(children: layers))
    }

    private func _overviewCard(_ pane: Pane, w: Double, h: Double,
                               chosen: Bool) -> Widget {
        let cols = max(20, Int((w - 20) / 6.4))
        let rows = max(2, Int((h - 46) / 14))
        var body: [Widget] = []
        for line in _preview(pane, lines: rows, cols: cols) {
            body.append(Text(line, style: TextStyle(
                color: chosen ? Tile.launcherItem : Tile.flowDim, fontSize: 10.5,
                fontFamily: TerminalFontLoader.family,
                fontFamilyFallback: TerminalFontLoader.fallback)))
        }
        return SizedBox(
            width: w, height: h,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: Tile.launcherBg,
                    border: Border.all(
                        color: chosen ? Tile.seamActive : Tile.border,
                        width: chosen ? 2 : 1),
                    borderRadius: BorderRadius.all(Radius(circular: 10)),
                    boxShadow: chosen
                        ? [BoxShadow(color: Color(0xAA000000),
                                     offset: Offset(0, 14), blurRadius: 34)]
                        : [BoxShadow(color: Color(0x44000000),
                                     offset: Offset(0, 6), blurRadius: 16)]
                ),
                child: ClipRRect(
                    borderRadius: BorderRadius.all(Radius(circular: 10)),
                    child: Column(
                        crossAxisAlignment: .stretch,
                        children: [
                            SizedBox(
                                width: w, height: 26,
                                child: DecoratedBox(
                                    decoration: BoxDecoration(
                                        color: chosen ? Tile.titleBarActive
                                                      : Tile.titleBar),
                                    child: Center(child: Text(
                                        pane.title,
                                        style: TextStyle(
                                            color: chosen ? Tile.titleTextActive
                                                          : Tile.titleText,
                                            fontSize: 12,
                                            fontFamily: TerminalFontLoader.family,
                                            fontFamilyFallback: TerminalFontLoader.fallback)))
                                )
                            ),
                            SizedBox(
                                width: w, height: max(1, h - 26),
                                child: Padding(
                                    padding: EdgeInsets(all: 8),
                                    child: Column(crossAxisAlignment: .start,
                                                  children: body)
                                )
                            ),
                        ]
                    )
                )
            )
        )
    }

    // MARK: - The top bar

    private func _topBar(width: Double) -> Widget {
        return SizedBox(
            width: width, height: Tile.barH,
            child: DecoratedBox(
                decoration: BoxDecoration(color: Tile.bar),
                child: Stack(children: [
                    Positioned(
                        left: 12, top: 5,
                        child: Row(children: [
                            _modeButton("Tiling", .tiling),
                            SizedBox(width: 6, height: 1),
                            _modeButton("Full screen", .fullScreen),
                        ])
                    ),
                    Positioned(
                        left: max(0, width - 208), top: 5,
                        child: Row(children: [
                            _barButton("Overview  ⌃⇧↑", enabled: true) {
                                [self] in _openOverview()
                            },
                            SizedBox(width: 8, height: 1),
                            _barButton("+ New", enabled: true) { [self] in
                                _newWindow()
                            },
                        ])
                    ),
                ])
            )
        )
    }

    private func _modeButton(_ label: String, _ mode: WorkspaceMode) -> Widget {
        let on = _mode == mode
        return Listener(
            onPointerDown: { [self] _ in _setMode(mode) },
            behavior: .opaque,
            child: SizedBox(
                width: 84, height: 22,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: on ? Tile.barPick : Tile.barFill,
                        borderRadius: BorderRadius.all(Radius(circular: 6))
                    ),
                    child: Center(
                        child: Text(label, style: TextStyle(
                            color: on ? Tile.titleTextActive : Tile.titleText,
                            fontSize: 12,
                            fontFamily: TerminalFontLoader.family,
                            fontFamilyFallback: TerminalFontLoader.fallback))
                    )
                )
            )
        )
    }

    private func _barButton(_ label: String, enabled: Bool,
                            _ action: @escaping () -> Void) -> Widget {
        return Listener(
            onPointerDown: { _ in if enabled { action() } },
            behavior: .opaque,
            child: SizedBox(
                width: 96, height: 22,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: Tile.barFill,
                        borderRadius: BorderRadius.all(Radius(circular: 6))
                    ),
                    child: Center(
                        child: Text(label, style: TextStyle(
                            color: enabled ? Tile.titleText : Tile.barDim,
                            fontSize: 12,
                            fontFamily: TerminalFontLoader.family,
                            fontFamilyFallback: TerminalFontLoader.fallback))
                    )
                )
            )
        )
    }

    private func _setMode(_ mode: WorkspaceMode) {
        guard _mode != mode else { return }
        setState { _mode = mode }
    }

    /// The toolbar's New: a split in tiling (there is nowhere else to put it),
    /// a fresh window in floating.
    private func _newWindow() {
        var target: Node? = nil
        root.forEachLeaf { if $0.pane?.id == _activeId { target = $0 } }
        if target == nil { root.forEachLeaf { if target == nil { target = $0 } } }
        guard let node = target else { return }
        _split(node, axis: .row)
        // In full screen the split is invisible — the new pane simply
        // becomes the one on screen, and the old one is a card away.
        if _mode == .fullScreen, let pane = node.second?.pane {
            _activeId = pane.id
        }
    }

    private func _paneWidget(_ node: Node, _ box: Box) -> Widget {
        guard let pane = node.pane else { return SizedBox(width: 0, height: 0) }
        let active = pane.id == _activeId
        let terminalH = max(1, box.h - Tile.titleBarH)

        return Positioned(
            // A pane's identity is its session, not its slot: without the
            // key, re-tiling matches Stack children positionally and a
            // mounted terminal's element would be handed another session's
            // widget — the same grid, the wrong shell. The epoch is the
            // other half: changing the key remounts the pane, which is how
            // a finished rename gives the keyboard back to the terminal.
            key: ValueKey(pane.id * 1000 + pane.focusEpoch),
            left: box.x, top: box.y,
            child: SizedBox(
                width: box.w, height: box.h,
                child: Listener(
                    // A click anywhere in the pane activates it. The terminal
                    // below still receives it (translucent), so one click
                    // both activates the pane and places the cursor.
                    onPointerDown: { [self] _ in
                        if pane.pending {
                            // A pending pane has no terminal to take the
                            // click's focus, so the launcher takes it.
                            if _launching !== pane { _beginLaunch(pane) }
                            else if _activeId != pane.id {
                                setState { _activeId = pane.id }
                            }
                        } else if _activeId != pane.id {
                            setState { _activeId = pane.id }
                        }
                    },
                    behavior: .translucent,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            border: Border.all(color: Tile.border, width: 1),
                            borderRadius: BorderRadius.all(Radius(circular: 6))
                        ),
                        child: ClipRRect(
                            borderRadius: BorderRadius.all(Radius(circular: 6)),
                            child: Column(
                                crossAxisAlignment: .stretch,
                                children: [
                                    _titleBar(pane, active: active, width: box.w),
                                    SizedBox(
                                        width: box.w,
                                        height: terminalH,
                                        child: pane.pending
                                            ? _launcherBody(pane, width: box.w,
                                                            height: terminalH)
                                            : TerminalView(
                                                session: pane.session,
                                                // Opaque: the shipped theme is
                                                // 85% for the desktop's glass,
                                                // and floating windows would
                                                // show each other through it.
                                                theme: Tile.terminal,
                                                // The pane knows its box; the
                                                // view must not size its grid
                                                // from the window (see
                                                // TerminalView.size).
                                                size: Size(box.w, terminalH),
                                                autofocus: active,
                                                // The app takes its chord
                                                // before the terminal does.
                                                keyFilter: { [self] key in
                                                    _appChord(key)
                                                }
                                            )
                                    ),
                                ]
                            )
                        )
                    )
                )
            )
        )
    }

    /// What a pane shows before it runs anything: a command line, and the
    /// hosts and past commands worth not retyping.
    private func _launcherBody(_ pane: Pane, width: Double, height: Double) -> Widget {
        let focused = _launching === pane
        let matches = Launcher.suggestions(matching: pane.launchText)
        let rows = max(0, Int((height - 96) / 20))

        func line(_ text: String, _ color: Color, size: Double = 13) -> Widget {
            return Text(text, style: TextStyle(
                color: color, fontSize: size,
                fontFamily: TerminalFontLoader.family,
                fontFamilyFallback: TerminalFontLoader.fallback))
        }

        var children: [Widget] = [
            SizedBox(width: width, height: 18),
            line("  run in this terminal", Tile.launcherHint, size: 12),
            SizedBox(width: width, height: 6),
            line("  ▸ " + pane.launchText + (focused ? "▏" : ""),
                 Tile.launcherInput, size: 15),
            SizedBox(width: width, height: 14),
        ]
        if matches.isEmpty {
            children.append(
                line("    nothing remembered yet — type a command, or press",
                     Tile.launcherHint, size: 12))
            children.append(
                line("    Enter for a plain shell", Tile.launcherHint, size: 12))
        } else {
            for (i, match) in matches.prefix(rows).enumerated() {
                let selected = pane.launchIndex == i + 1
                children.append(
                    line((selected ? "  ❯ " : "    ") + match.command
                            + "   " + match.source,
                         selected ? Tile.launcherPick : Tile.launcherItem,
                         size: 13))
            }
            children.append(SizedBox(width: width, height: 10))
            children.append(
                line("    ↑↓ choose · Enter run · Esc plain shell",
                     Tile.launcherHint, size: 11))
        }

        return SizedBox(
            width: width, height: height,
            child: DecoratedBox(
                decoration: BoxDecoration(color: Tile.launcherBg),
                child: Column(crossAxisAlignment: .start, children: children)
            )
        )
    }

    private func _titleBar(_ pane: Pane, active: Bool, width: Double) -> Widget {
        let editing = _renaming === pane
        // The caret is a block, drawn in the text: the rename field is 30px
        // of title bar, and a blinking one-pixel line there is easy to miss.
        let label = editing ? _renameText + "▏" : pane.title
        return SizedBox(
            width: width, height: Tile.titleBarH,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: editing ? Tile.titleBarEditing
                                   : (active ? Tile.titleBarActive : Tile.titleBar)
                ),
                child: Center(
                    child: Text(
                        label,
                        style: TextStyle(
                            color: editing ? Tile.titleTextEditing
                                           : (active ? Tile.titleTextActive
                                                     : Tile.titleText),
                            fontSize: 12,
                            fontFamily: TerminalFontLoader.family,
                            fontFamilyFallback: TerminalFontLoader.fallback
                        )
                    )
                )
            )
        )
    }

    /// Close and split, drawn over the pane's title bar but rooted in the
    /// workspace — see the note in `build`. A split needs no mode and no
    /// keyboard chord this way, and a chord would have to be taken away from
    /// the terminal, which owns its keys.
    private func _paneControls(_ node: Node, _ box: Box) -> Widget {
        guard let pane = node.pane else { return SizedBox(width: 0, height: 0) }
        let active = pane.id == _activeId
        return Positioned(
            key: ValueKey(1_000_000 + pane.id),
            left: box.x, top: box.y,
            child: SizedBox(
                width: box.w, height: Tile.titleBarH,
                child: Stack(children: [
                    Positioned(
                        left: 10, top: 9,
                        child: Listener(
                            onPointerDown: { [self] _ in _close(node) },
                            behavior: .opaque,
                            child: SizedBox(
                                width: 12, height: 12,
                                child: DecoratedBox(
                                    decoration: BoxDecoration(
                                        color: active ? Tile.close : Tile.closeIdle,
                                        shape: .circle
                                    )
                                )
                            )
                        )
                    ),
                    // The title strip: click to name the pane, drag to move
                    // it when floating. It lives in this layer so the click
                    // does not also reach the terminal underneath, which
                    // would steal the focus back.
                    //
                    // Move and rename share one gesture because a title bar
                    // has to do both: the press starts a drag, and only a
                    // release that never travelled counts as a click. (No
                    // double-click here — registering one kills single taps
                    // on the DRM embedder, a framework trap of long standing.)
                    Positioned(
                        left: 30, top: 0,
                        child: Listener(
                            onPointerDown: { [self] _ in _beginRename(pane) },
                            behavior: .opaque,
                            child: SizedBox(
                                width: max(0, box.w - 114), height: Tile.titleBarH
                            )
                        )
                    ),
                    Positioned(
                        left: max(0, box.w - 78), top: 6,
                        child: Row(children: [
                            _restartButton(pane, active: active),
                            SizedBox(width: 8, height: 1),
                            _splitButton(node, axis: .row, active: active),
                            SizedBox(width: 8, height: 1),
                            _splitButton(node, axis: .column, active: active),
                        ])
                    ),
                ])
            )
        )
    }

    /// Restart this pane's shell (or command). The way out of a terminal
    /// that is stuck rather than finished — an ssh whose connection died, a
    /// program that stopped reading — where the pane looks alive and answers
    /// nothing. The session kills the old process group and spawns a fresh
    /// PTY; the scrollback stays, so whatever was on screen when it hung is
    /// still there to read.
    private func _restartButton(_ pane: Pane, active: Bool) -> Widget {
        let ink = active ? Tile.actionActive : Tile.action
        return Listener(
            onPointerDown: { [self] _ in _restart(pane) },
            behavior: .opaque,
            child: SizedBox(
                width: 18, height: 18,
                child: Center(
                    child: Text(
                        "↻",
                        style: TextStyle(
                            color: ink,
                            fontSize: 15,
                            fontFamily: TerminalFontLoader.family,
                            // The arrow lives in the bundled DejaVu fallback,
                            // not in Roboto Mono — the same fallback chain the
                            // terminal itself leans on for box glyphs.
                            fontFamilyFallback: TerminalFontLoader.fallback
                        )
                    )
                )
            )
        )
    }

    private func _restart(_ pane: Pane) {
        guard !pane.pending else { _beginLaunch(pane); return }
        if let remote = pane.remote {
            // Reconnecting is not restarting: the far-side session is still
            // running, so drop the link and let it re-attach at its offset.
            _activeId = pane.id
            pane.session.feed(Array("\r\n\u{1B}[38;5;244m[reconnecting…]\u{1B}[0m\r\n".utf8))
            remote.stop()
            let fresh = RemoteTerminal(session: pane.session,
                                       host: remote.hostName,
                                       attach: remote.remoteId)
            fresh.onLink = { [weak self] link in
                DispatchQueue.main.async { pane.link = link; self?.setState {} }
            }
            pane.remote = fresh
            fresh.start()
            pane.focusEpoch += 1
            setState {}
            return
        }
        _activeId = pane.id
        // Say so in the pane itself: a restart that only killed the process
        // would read as the terminal having glitched.
        pane.session.feed(Array("\r\n\u{1B}[38;5;244m[restarting…]\u{1B}[0m\r\n".utf8))
        pane.session.restart()
        // Remount so the fresh terminal takes the keyboard, the same trick
        // the rename uses.
        pane.focusEpoch += 1
        setState {}
    }

    /// A 16x16 glyph drawn from boxes: a rectangle divided the way this
    /// button would divide the pane. Two rectangles say it better than any
    /// icon font, and carry no font dependency into the example.
    private func _splitButton(_ node: Node, axis: SplitAxis, active: Bool) -> Widget {
        let ink = active ? Tile.actionActive : Tile.action
        let box = DecoratedBox(
            decoration: BoxDecoration(
                border: Border.all(color: ink, width: 1),
                borderRadius: BorderRadius.all(Radius(circular: 2))
            ),
            child: Stack(children: [
                Positioned(
                    left: axis == .row ? 6 : 0,
                    top: axis == .row ? 0 : 6,
                    child: SizedBox(
                        width: axis == .row ? 1 : 14,
                        height: axis == .row ? 14 : 1,
                        child: ColoredBox(color: ink)
                    )
                )
            ])
        )
        return Listener(
            onPointerDown: { [self] _ in _split(node, axis: axis) },
            behavior: .opaque,
            child: SizedBox(width: 18, height: 18,
                            child: Center(child: SizedBox(width: 14, height: 14,
                                                          child: box)))
        )
    }

    /// The draggable boundary between two panes.
    private func _seamWidget(_ node: Node, _ box: Box) -> Widget {
        let dragging = _dragSeam === node
        return Positioned(
            left: box.x, top: box.y,
            child: SizedBox(
                width: box.w, height: box.h,
                child: Listener(
                    onPointerDown: { [self] event in
                        _dragSeam = node
                        _lastPointer = event.position
                        setState {}
                    },
                    onPointerMove: { [self] event in
                        // The ratio belongs to the SPLIT's own box — the
                        // bounds of the pair this seam divides — so a nested
                        // split resizes within its parent, not against it.
                        guard _dragSeam === node, let last = _lastPointer,
                              let own = _boxes[ObjectIdentifier(node)]
                        else { return }
                        let usable = node.axis == .row
                            ? max(1, own.w - Tile.seamW)
                            : max(1, own.h - Tile.seamW)
                        let delta = node.axis == .row
                            ? event.position.dx - last.dx
                            : event.position.dy - last.dy
                        _lastPointer = event.position
                        // Clamped so neither side can be squeezed away — and
                        // min/max around 0.5 so a box too small for two
                        // minimums still yields a usable (even) split.
                        let lo = min(0.5, Tile.minPane / usable)
                        let hi = max(0.5, 1 - Tile.minPane / usable)
                        setState {
                            node.ratio = min(max(node.ratio + delta / usable, lo), hi)
                        }
                    },
                    onPointerUp: { [self] _ in
                        _dragSeam = nil
                        _lastPointer = nil
                        setState {}
                    },
                    behavior: .opaque,
                    child: Center(
                        child: SizedBox(
                            width: node.axis == .row ? 2 : box.w,
                            height: node.axis == .row ? box.h : 2,
                            child: ColoredBox(
                                color: dragging ? Tile.seamActive : Tile.gutter
                            )
                        )
                    )
                )
            )
        )
    }
}

runExampleApp(title: "Terminal Workspace", width: 1200, height: 780) {
    TilingTerminal()
}

#else
fatalError("The example apps currently target Linux and Windows desktop sessions.")
#endif
