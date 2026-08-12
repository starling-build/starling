// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The tiling terminal — TerminalDemo's grown-up sibling, and a demo of what
// TerminalView being a *widget* buys you (docs/plans/terminal-widget.md).
// TerminalDemo is one session filling a window; this is a split tree of
// them, each with its own shell, scrollback and child process.
//
//   swift run -c release TerminalTiling
//   swift run -c release TerminalTiling "top -d 1"    # what new panes run
//
// Tiling, with the part tiling window managers get wrong made right: the
// seams are draggable. Panes never overlap and never leave dead space, and
// any boundary can still be pulled to give one side more room — live, with
// the child processes resized as it moves (a pane's TerminalView is told
// its box, so the grid follows and the shell gets its SIGWINCH). A split
// is a ratio, not a pixel count, so resizing the window redistributes
// every pane proportionally and nothing has to be re-tiled.
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
    static let titleText = Color(0xFF98A1AD)
    static let titleTextActive = Color(0xFFE6EAF0)
    static let border = Color(0xFF11151A)
    static let close = Color(0xFFFF5F57)
    static let closeIdle = Color(0xFF6E5A5E)
    static let action = Color(0xFF7C8695)
    static let actionActive = Color(0xFFCBD3DE)
    static let seamActive = Color(0xFF3E8FE0)

    static let titleBarH: Double = 30
    /// The draggable strip between two panes: wide enough to hit without
    /// aiming, with a thinner line drawn inside it.
    static let seamW: Double = 8
    /// No pane may be squeezed below this by a seam drag.
    static let minPane: Double = 180
}

// MARK: - The split tree

enum SplitAxis {
    /// Children side by side, divided by a vertical seam.
    case row
    /// Children stacked, divided by a horizontal seam.
    case column
}

/// One terminal: a session and an identity that survives re-tiling.
final class Pane {
    let id: Int
    let session: TerminalSession

    init(id: Int) {
        self.id = id
        self.session = TerminalSession()
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

/// A rectangle in logical pixels. (Not `Rect`: the bridge has one.)
struct Box {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
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

    override func initState() {
        super.initState()
        root = Node(pane: _newPane())
    }

    override func dispose() {
        root.forEachLeaf { $0.pane?.session.terminate() }
        super.dispose()
    }

    // MARK: - Panes

    private func _newPane() -> Pane {
        let pane = Pane(id: _nextId)
        _nextId += 1
        if let command = Self.command {
            pane.session.startCommand(command)
        } else {
            pane.session.startShell()
        }
        _activeId = pane.id
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
        var leaves: [(Node, Box)] = []
        var seams: [(Node, Box)] = []
        _boxes.removeAll(keepingCapacity: true)
        _resolve(root, Box(x: 0, y: 0, w: window.width, h: window.height),
                 &leaves, &seams)

        var layers: [Widget] = [
            Positioned(fill: (), child: ColoredBox(color: Tile.gutter))
        ]
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

        return Directionality(textDirection: .ltr, child: Stack(children: layers))
    }

    private func _paneWidget(_ node: Node, _ box: Box) -> Widget {
        guard let pane = node.pane else { return SizedBox(width: 0, height: 0) }
        let active = pane.id == _activeId
        let terminalH = max(1, box.h - Tile.titleBarH)

        return Positioned(
            // A pane's identity is its session, not its slot: without the
            // key, re-tiling matches Stack children positionally and a
            // mounted terminal's element would be handed another session's
            // widget — the same grid, the wrong shell.
            key: ValueKey(pane.id),
            left: box.x, top: box.y,
            child: SizedBox(
                width: box.w, height: box.h,
                child: Listener(
                    // A click anywhere in the pane activates it. The terminal
                    // below still receives it (translucent), so one click
                    // both activates the pane and places the cursor.
                    onPointerDown: { [self] _ in
                        if _activeId != pane.id { setState { _activeId = pane.id } }
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
                                        child: TerminalView(
                                            session: pane.session,
                                            // The pane knows its box; the view
                                            // must not size its grid from the
                                            // window (see TerminalView.size).
                                            size: Size(box.w, terminalH),
                                            autofocus: active
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

    private func _titleBar(_ pane: Pane, active: Bool, width: Double) -> Widget {
        return SizedBox(
            width: width, height: Tile.titleBarH,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: active ? Tile.titleBarActive : Tile.titleBar
                ),
                child: Center(
                    child: Text(
                        Self.command.map { "\($0) — \(pane.id)" }
                            ?? "Terminal \(pane.id)",
                        style: TextStyle(
                            color: active ? Tile.titleTextActive : Tile.titleText,
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
                    Positioned(
                        left: max(0, box.w - 52), top: 6,
                        child: Row(children: [
                            _splitButton(node, axis: .row, active: active),
                            SizedBox(width: 8, height: 1),
                            _splitButton(node, axis: .column, active: active),
                        ])
                    ),
                ])
            )
        )
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

runExampleApp(title: "Tiling Terminal", width: 1200, height: 780) {
    TilingTerminal()
}

#else
fatalError("The example apps currently target Linux and Windows desktop sessions.")
#endif
