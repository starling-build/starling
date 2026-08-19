// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The split tree — milestone 1 of docs/plans/remote-workspace.md.
//
// Lifted from sdk/Examples/TerminalTiling, which proved the shape: a binary
// tree whose leaves are panes and whose branches are splits at a RATIO. The
// ratio is what makes window resize and seam drag the same operation applied
// at different levels — nothing here stores pixels, so a resized window
// redistributes every pane proportionally with no re-tiling pass.
//
// Model only. The widgets that draw it live in TerminalTabs.swift, because
// they need the state object's `setState`.

import Flutter
import FlutterSwiftBridge
import Foundation

#if !os(iOS)

/// Which way a split divides its box.
enum SplitAxis {
    /// Children side by side, divided by a vertical seam.
    case row
    /// Children stacked, divided by a horizontal seam.
    case column
}

/// A rectangle in logical pixels. Not `Rect` — the bridge already has one.
struct PaneBox {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

/// One terminal inside a tab: a session, and an identity that survives the
/// tree being reshaped around it.
final class TerminalPane {
    /// Never reused. Everything acts on the pane object or this id, never a
    /// position in the tree — a split rewrites the tree under the caller.
    let id: Int
    let session: TerminalSession

    /// How many commands had finished here the last time the user was looking
    /// at this pane. What turns "a command finished" into "a command finished
    /// and you have not seen it" — the distinction that makes a status dot
    /// worth having, since a pane you are staring at needs no badge.
    var seenFinished: UInt64 = 0

    init(id: Int, cols: Int, rows: Int) {
        self.id = id
        self.session = TerminalSession(cols: cols, rows: rows)
    }

    /// What this pane wants to say from across the window.
    ///
    /// Only ever `running` or `finished` — a pane at a prompt, or one whose
    /// shell emits no OSC 133 at all, says nothing. Marking the quiet ones
    /// would put a dot on every pane in the window and mean nothing at all;
    /// the point is to be able to find the one that needs you.
    var status: PaneStatus {
        session.lock.lock()
        let state = session.emulator.commandState
        let exit = session.emulator.commandExit
        let finished = session.emulator.commandsFinished
        session.lock.unlock()

        switch state {
        case .running:
            return .running
        case .done where finished > seenFinished:
            // No exit code reported is not a failure. Shells that send a bare
            // `D` are common, and painting those red would cry wolf.
            return .finished(ok: (exit ?? 0) == 0)
        default:
            return .quiet
        }
    }

    /// The user is looking at this pane; nothing here is news any more.
    func markSeen() {
        session.lock.lock()
        let finished = session.emulator.commandsFinished
        session.lock.unlock()
        seenFinished = finished
    }
}

/// What a pane reports, from OSC 133 and nothing else — no screen scraping,
/// no per-program regexes. See `TerminalEmulator.CommandState`.
enum PaneStatus: Equatable {
    case quiet
    case running
    case finished(ok: Bool)
}

/// A node in the layout: a pane (leaf), or a split of two children.
final class PaneNode {
    var pane: TerminalPane?
    var axis: SplitAxis = .row
    var ratio: Double = 0.5
    var first: PaneNode?
    var second: PaneNode?
    weak var parent: PaneNode?

    init(pane: TerminalPane) { self.pane = pane }
    init() {}

    var isLeaf: Bool { pane != nil }

    func forEachLeaf(_ body: (PaneNode) -> Void) {
        if isLeaf { body(self); return }
        first?.forEachLeaf(body)
        second?.forEachLeaf(body)
    }

    /// Every pane in tree order — the order a "next pane" walk follows.
    var panes: [TerminalPane] {
        var out: [TerminalPane] = []
        forEachLeaf { if let p = $0.pane { out.append(p) } }
        return out
    }

    func node(for id: Int) -> PaneNode? {
        var found: PaneNode?
        forEachLeaf { if found == nil, $0.pane?.id == id { found = $0 } }
        return found
    }
}

// MARK: - Layout

/// The space held between two panes, in logical pixels — and, since the seam
/// stopped painting a bar, the GAP you actually see: the window backdrop
/// showing between panes that float above it.
///
/// It is still the seam's grab area, so it has to stay thick enough to hit
/// with a pointer. 10 is wide enough to read as deliberate separation rather
/// than a rendering seam, and still an easy target.
let paneSeamW: Double = 10

/// A pane may not be squeezed below this; the clamp is what stops a drag
/// collapsing one side to nothing.
let paneMinSize: Double = 60

/// Resolve the tree into boxes. Returns the leaves to draw, the seams to make
/// draggable, and every node's own box — the last is what a seam drag needs,
/// because a nested split's ratio belongs to ITS box, not the window's.
func resolvePanes(_ root: PaneNode, in box: PaneBox)
    -> (leaves: [(PaneNode, PaneBox)],
        seams: [(PaneNode, PaneBox)],
        boxes: [ObjectIdentifier: PaneBox]) {
    var leaves: [(PaneNode, PaneBox)] = []
    var seams: [(PaneNode, PaneBox)] = []
    var boxes: [ObjectIdentifier: PaneBox] = [:]

    func walk(_ node: PaneNode, _ b: PaneBox) {
        boxes[ObjectIdentifier(node)] = b
        guard !node.isLeaf, let first = node.first, let second = node.second else {
            leaves.append((node, b))
            return
        }
        let s = paneSeamW
        if node.axis == .row {
            let usable = max(0, b.w - s)
            let firstW = usable * node.ratio
            walk(first, PaneBox(x: b.x, y: b.y, w: firstW, h: b.h))
            seams.append((node, PaneBox(x: b.x + firstW, y: b.y, w: s, h: b.h)))
            walk(second, PaneBox(x: b.x + firstW + s, y: b.y,
                                 w: usable - firstW, h: b.h))
        } else {
            let usable = max(0, b.h - s)
            let firstH = usable * node.ratio
            walk(first, PaneBox(x: b.x, y: b.y, w: b.w, h: firstH))
            seams.append((node, PaneBox(x: b.x, y: b.y + firstH, w: b.w, h: s)))
            walk(second, PaneBox(x: b.x, y: b.y + firstH + s,
                                 w: b.w, h: usable - firstH))
        }
    }
    walk(root, box)
    return (leaves, seams, boxes)
}

// MARK: - Mutation

/// Split a leaf in two, keeping its pane and adding `fresh` beside it.
///
/// The node becomes the split and grows two children rather than being
/// replaced, so every reference the caller holds — and the parent pointer
/// above it — stays valid.
func splitPane(_ node: PaneNode, axis: SplitAxis, with fresh: TerminalPane) {
    guard let pane = node.pane else { return }
    let keep = PaneNode(pane: pane)
    let added = PaneNode(pane: fresh)
    node.pane = nil
    node.axis = axis
    node.ratio = 0.5
    node.first = keep
    node.second = added
    keep.parent = node
    added.parent = node
}

/// Remove a leaf; its sibling takes the space back.
///
/// Returns false when the node is the whole tree — the caller decides what
/// closing the last pane means (here: close the tab).
@discardableResult
func closePane(_ node: PaneNode) -> Bool {
    guard let parent = node.parent,
          let sibling = (parent.first === node) ? parent.second : parent.first
    else { return false }
    // The parent BECOMES the sibling in place, so the sibling's own subtree
    // keeps its shape and its ratios. Replacing the parent instead would
    // orphan every grandchild's parent pointer.
    parent.pane = sibling.pane
    parent.axis = sibling.axis
    parent.ratio = sibling.ratio
    parent.first = sibling.first
    parent.second = sibling.second
    parent.first?.parent = parent
    parent.second?.parent = parent
    return true
}

/// Move a seam. `delta` is the pointer's travel along the split's axis.
func dragSeam(_ node: PaneNode, delta: Double, own: PaneBox) {
    let usable = node.axis == .row
        ? max(1, own.w - paneSeamW)
        : max(1, own.h - paneSeamW)
    // Clamped so neither side can be squeezed away — and min/max around 0.5
    // so a box too small for two minimums still yields a usable even split.
    let lo = min(0.5, paneMinSize / usable)
    let hi = max(0.5, 1 - paneMinSize / usable)
    node.ratio = min(max(node.ratio + delta / usable, lo), hi)
}

// MARK: - Layout blob

// The bridge between the tree the UI uses and the tree the wire carries
// (PaneLayout.swift). Kept here rather than in the codec so PaneLayout stays
// dependency-free and testable on its own — the whole reason it imports
// nothing.

extension PaneNode {
    /// The tree as the wire sees it. `describe` maps a pane to what the blob
    /// should say about it — its far-side session (0 for a pane with no
    /// remote behind it) and where its shell last said it was.
    func layoutNode(describe: (TerminalPane) -> LeafInfo) -> LayoutNode {
        if let pane = pane { return .leaf(describe(pane)) }
        guard let first = first, let second = second else {
            return .leaf(session: 0)
        }
        return .split(axis: axis == .row ? .row : .column,
                      ratio: ratio,
                      first: first.layoutNode(describe: describe),
                      second: second.layoutNode(describe: describe))
    }
}

/// Rebuild a tree from a decoded layout, taking panes from `makePane` in leaf
/// order — the same order `PaneLayout.leaves` reports, so a caller that
/// resolved sessions from that list hands them back in the order they map.
func buildPaneTree(_ node: LayoutNode,
                   makePane: (LeafInfo) -> TerminalPane) -> PaneNode {
    switch node {
    case .leaf(let info):
        return PaneNode(pane: makePane(info))
    case .split(let axis, let ratio, let first, let second):
        let parent = PaneNode()
        parent.axis = axis == .row ? .row : .column
        parent.ratio = ratio
        let a = buildPaneTree(first, makePane: makePane)
        let b = buildPaneTree(second, makePane: makePane)
        parent.first = a
        parent.second = b
        a.parent = parent
        b.parent = parent
        return parent
    }
}

#endif  // !os(iOS)
