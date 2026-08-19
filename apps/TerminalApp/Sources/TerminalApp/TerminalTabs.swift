// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Tabs: several shells in one window, macOS Terminal's arrangement.
//
// This lives in the app, not in `sdk/`, because nothing here is terminal
// work — TerminalView already renders a session, and `keyFilter` exists so
// the app around it can take a chord before the terminal does (a terminal
// claims the keyboard almost completely, so there is nowhere else to put
// one). What the app owns is the list of sessions, which one is on screen,
// and the strip along the top.
//
// Two details are load bearing:
//
//   - The terminal is told its BOX (`TerminalView.size`). Left to itself it
//     sizes the grid from the whole window, which is right for a terminal
//     that IS the window and wrong the moment a tab bar sits above it: the
//     grid would be a bar taller than the space it is painted into, and the
//     shell would be told a window size it does not have.
//   - The terminal is KEYED by tab id. `_TerminalViewState` captures its
//     session once — the session is the view's identity — so without a key
//     the framework would match the two TerminalViews positionally on a tab
//     switch and hand the mounted state another tab's widget: the same grid
//     on screen, the wrong shell behind it. The key goes on the SizedBox
//     around it, which is the child the parent actually reconciles.
//
// The bar is hidden while there is one tab, like macOS Terminal's — so a
// single-tab window is exactly what it was before tabs existed, down to the
// grid it computes.

import Flutter
import FlutterSwiftBridge
import Foundation

// Desktop only, and gated rather than merely unused: iOS has no fork and no
// exec, so a tab here could not start a shell — that platform opens ONE ssh
// session from a connect screen (TerminalApp.swift) and there is nothing to
// tab between.
#if !os(iOS)

/// One tab: a tree of panes, plus an identity that survives the list moving
/// under it.
final class TerminalTab {
    /// Never reused. Everything that acts on a tab does so through the object
    /// or this id, never a row index — a click on ✕ closes the tab and the
    /// click on the tab body behind it arrives afterwards, by which time the
    /// indices have shifted.
    let id: Int
    /// The split tree. A tab starts as a single leaf and grows from there;
    /// see TerminalPanes.swift.
    var root: PaneNode
    /// Which pane owns the keyboard. Held as an id rather than a node,
    /// because a split rewrites nodes under it.
    var activePaneId: Int
    /// Bumped when focus is moved by CODE rather than by a click, which is
    /// the only case that needs help: `TerminalView.autofocus` is read at
    /// mount, so a pane that was already on screen and inactive never asks
    /// for the keyboard when it becomes active. Folding this into the key
    /// remounts exactly that pane, and remounting is what runs autofocus.
    /// A click needs none of this — the view's own Listener takes focus.
    var focusEpoch = 0
    /// nil for an ordinary tab. Non-nil means every pane in it is a session on
    /// another machine and the arrangement is stored there too — see
    /// TerminalWorkspace.swift.
    var workspace: TerminalWorkspace?

    init(id: Int, pane: TerminalPane) {
        self.id = id
        self.root = PaneNode(pane: pane)
        self.activePaneId = pane.id
    }

    var panes: [TerminalPane] { root.panes }
    var activePane: TerminalPane? {
        panes.first { $0.id == activePaneId } ?? panes.first
    }
}

/// The strip's metrics and palette. Opaque-over-nothing is wrong here: the
/// terminal's own background carries 85% alpha for the desktop's glass, so
/// the bar carries it too or the window looks like two materials.
private enum TabChrome {
    static let height: Double = 28

    /// The surface panes FLOAT ON: the tab bar, and the gaps between panes.
    /// Deeper than a pane, so a pane reads as raised above it rather than as a
    /// region carved out of it.
    ///
    /// It carries the same `0xD9` alpha the terminal has always had, because
    /// the desktop composites the wallpaper behind this window — an opaque
    /// backdrop would quietly turn a translucent window solid, and the gaps
    /// are exactly where that would show most.
    static let backdrop: Int = 0xD9_16142A

    /// A pane's own background. Must stay in step with
    /// `TerminalTheme.starlingDark.background` in the sdk, which is what the
    /// grid itself paints: if the two drift, every pane gets a mismatched
    /// hairline where the chrome ends and the text begins.
    static let surface: Int = 0xD9_231F3D

    /// The ring around the pane with the keyboard, and the seam while it is
    /// dragged. Both are quiet on purpose: a terminal is a rectangle of text
    /// and a loud border competes with it.
    static let activePaneEdge: Int = 0x66_8AA0FF
    static let seamHot: Int = 0xFF_4A4470
    /// How much of a pane's corner is rounded off. Only ever applied when
    /// there is more than one pane — see `_pane`.
    static let paneRadius: Double = 6

    /// The active tab is the pane's own background, so the two read as one
    /// surface; everything else is the backdrop.
    static let activeTab: Int = surface
    static let bar: Int = backdrop
    static let separator: Int = 0xFF_100E1F
    static let activeText: Int = 0xFF_EDEBF7
    static let text: Int = 0xFF_9C97BC
    static let button: Int = 0xFF_9C97BC
    /// Pane status (OSC 133). Amber for working, green for finished cleanly,
    /// red for a non-zero exit — the macOS traffic-light order, which is the
    /// one reading people already have.
    static let statusRunning: Int = 0xFF_E5A44B
    static let statusOK: Int = 0xFF_5FBF6B
    static let statusFailed: Int = 0xFF_E5695B
    static let statusDot: Double = 7
}

// MARK: - The tabbed terminal

/// The desktop terminal: a stack of shells, one on screen.
final class TerminalTabsView: StatefulWidget {
    override func createState() -> State<StatefulWidget> {
        return _TerminalTabsState()
    }
}

final class _TerminalTabsState: State<StatefulWidget>, @unchecked Sendable {

    // Not private: TerminalSwitcher.swift is an extension on this state, and
    // the switcher is the thing that decides which tab you are looking at.
    var tabs: [TerminalTab] = []
    var active = 0
    private var nextId = 1
    private var nextPaneId = 1

    /// The go-to palette (TerminalSwitcher.swift), closed almost always.
    let _switcher = SwitcherState()

    /// The seam being dragged, and the last pointer position, so a move is a
    /// delta rather than an absolute. Node boxes come from the last layout —
    /// a nested split's ratio belongs to ITS box, not the window's.
    private var _dragSeam: PaneNode?
    private var _lastPointer: Offset?
    private var _boxes: [ObjectIdentifier: PaneBox] = [:]
    /// The status poll's generation token, and what it last painted. Bumping
    /// the token in `dispose` is what stops the loop rescheduling forever.
    private var _statusTick = 0
    private var _lastStatus: [ObjectIdentifier: PaneStatus] = [:]
    /// Whether the keyboard reference is up. See TerminalHelp.swift.
    var _helpOpen = false

    /// Modifier state, watched rather than read off the event: the embedders
    /// report modifiers as their own key events, not as flags on the letter.
    /// Kept here rather than in the TerminalView because the view is
    /// remounted on every tab switch and would forget a held key.
    // Not private, for the same reason `_switcher` is not: TerminalHelp.swift
    // is an extension on this state in another file, and deciding whether a
    // keystroke is the help chord means reading the modifiers this tracks.
    var _ctrlDown = false
    var _shiftDown = false
    var _metaDown = false

    override func initState() {
        super.initState()
        // A launch is a LOCAL SHELL. `--workspace remote:host/ws:dev` (or
        // STARLING_WORKSPACE) asks for an arrangement instead, and ⌘O reaches
        // one at any moment — but nothing dials a machine merely because the
        // app started.
        //
        // This used to reopen the last workspace, on the "close the lid, open
        // the laptop" argument. That argument is real and it is still served,
        // one keystroke away; what it got wrong is which case is ordinary.
        // Opening a terminal is the most ordinary thing there is, and having it
        // attach to wherever you happened to be last — over ssh, to a host that
        // may be asleep, behind a different network, or simply not what you
        // wanted this time — is a surprise nobody asked the local case to
        // carry. tmux draws the line in the same place: a bare `tmux` is a new
        // session and attaching is a verb you type. The destination is still
        // remembered and the switcher still prefills it, so coming back is ⌘O
        // and Enter rather than a typed destination.
        if let spec = WorkspaceSpec.fromLaunch() {
            _openWorkspace(spec)
        } else {
            _open()
        }
        _tickStatus()
    }

    /// Repaints the status dots, and only when one has actually changed.
    ///
    /// The dots come from OSC 133, which arrives in the byte stream and moves
    /// no state this widget owns — so nothing would otherwise rebuild. A poll
    /// is the honest mechanism, and the guard is what makes it cheap: without
    /// comparing first, this would `setState` the whole tab tree four times a
    /// second forever, which on a terminal is not a cosmetic cost.
    ///
    /// `Foundation.Timer` is unavailable here — it never fires on the DRM
    /// embedder — so this is the sanctioned `asyncAfter` + generation token.
    private func _tickStatus() {
        let mine = _statusTick
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self, mine == self._statusTick else { return }

            // The pane you are looking at has no news for you: keep its seen
            // mark current so it is never badged for something you watched
            // finish. Only the ACTIVE tab counts — a pane on a tab that is not
            // on screen has not been seen at all.
            if let tab = self.tabs.indices.contains(self.active) ? self.tabs[self.active] : nil,
               let focused = tab.panes.first(where: { $0.id == tab.activePaneId }) {
                focused.markSeen()
            }

            var now: [ObjectIdentifier: PaneStatus] = [:]
            for tab in self.tabs {
                for pane in tab.panes { now[ObjectIdentifier(pane)] = pane.status }
            }
            if now != self._lastStatus {
                self._lastStatus = now
                self.setState {}
            }
            self._tickStatus()
        }
    }

    override func dispose() {
        // Orphans the pending status poll, which holds `self` weakly but would
        // otherwise keep rescheduling itself against a dead widget.
        _statusTick &+= 1
        // The workspace goes first: closing it flushes a layout change that
        // may be seconds old, and it is the only state here that outlives the
        // process.
        for tab in tabs {
            // One last record before the flush, so what is stored is where the
            // panes actually got to rather than where they were at the last
            // split. A `cd` moves no seam and would otherwise never be written.
            tab.workspace?.record(tab)
            tab.workspace?.close()
            for pane in tab.panes { pane.session.terminate() }
        }
        tabs = []
        super.dispose()
    }

    // MARK: - The list

    /// A new pane, sized to the one it is opening beside.
    ///
    /// A fresh `TerminalSession` is 80x24 and the view resizes it on mount,
    /// which means the shell would print its first prompt at 80 columns and
    /// then be told the real width — one SIGWINCH and one redraw for nothing.
    /// Whatever is on screen already knows a closer answer. It is only an
    /// estimate for a split (the new pane gets half a box), and that is fine:
    /// being one resize closer still beats starting at 80.
    private func _blankPane() -> TerminalPane {
        var cols = 80, rows = 24
        if let current = tabs.indices.contains(active) ? tabs[active].activePane : nil {
            current.session.lock.lock()
            (cols, rows) = (current.session.emulator.cols,
                            current.session.emulator.rows)
            current.session.lock.unlock()
        }
        let pane = TerminalPane(id: nextPaneId, cols: cols, rows: rows)
        nextPaneId += 1
        return pane
    }

    /// A pane with something running in it: a local shell, or — in a workspace
    /// tab — a session on the far machine, which the workspace then joins so
    /// the next attach finds it.
    private func _newPane(in tab: TerminalTab?) -> TerminalPane {
        let pane = _blankPane()
        if let workspace = tab?.workspace {
            workspace.attach(pane, session: nil)
        } else {
            pane.session.startShell()
        }
        return pane
    }

    @discardableResult
    private func _open() -> TerminalTab {
        let tab = TerminalTab(id: nextId, pane: _newPane(in: nil))
        nextId += 1
        tabs.append(tab)
        active = tabs.count - 1
        return tab
    }

    private func _newTab() {
        setState { _open() }
    }

    // MARK: - Workspaces

    /// Open a tab onto a workspace: N sessions on another machine, arranged
    /// the way they were left. See docs/plans/remote-workspace.md.
    ///
    /// The tab appears immediately, with one pane saying what it is waiting
    /// for. What replaces it depends on what the far side was holding — an
    /// arrangement, or nothing at all — and that answer arrives over the link,
    /// so it lands in `_restore` rather than here.
    /// Put a session that belonged to no workspace into this one, as a new
    /// pane beside the focused one.
    ///
    /// It stops being loose the moment its pane comes up: the pane's link
    /// WS_ADDs it, and the arrangement recorded a moment later is what brings
    /// it back next time. Nothing is opened on the far side — this is an
    /// ATTACH to something that was already running.
    func _adoptSession(_ tab: TerminalTab, session: UInt32) {
        guard let workspace = tab.workspace,
              let node = tab.root.node(for: tab.activePaneId)
                  ?? tab.root.node(for: tab.panes.first?.id ?? -1)
        else { return }
        let pane = _blankPane()
        workspace.attach(pane, session: session)
        setState {
            splitPane(node, axis: .row, with: pane)
            tab.activePaneId = pane.id
        }
        workspace.record(tab)
    }

    /// Open a tab onto a workspace. `adopting` names a session that is already
    /// running and belongs to no workspace: a workspace with nothing stored
    /// takes it as its first pane rather than opening a fresh shell.
    func _openWorkspace(_ spec: WorkspaceSpec, adopting adopt: UInt32? = nil) {
        let workspace = TerminalWorkspace(spec: spec)
        let pane = _blankPane()
        let tab = TerminalTab(id: nextId, pane: pane)
        nextId += 1
        tab.workspace = workspace
        tabs.append(tab)
        active = tabs.count - 1

        // Through the emulator, like every other line the transport writes:
        // an empty black rectangle is indistinguishable from a hung one.
        let where_ = spec.host == "local" ? "this machine" : spec.host
        pane.session.feed(Array(
            "\u{1B}[38;5;244m[workspace \"\(spec.name)\" on \(where_) — connecting…]\u{1B}[0m\r\n".utf8))

        // Fires when a pane learns its session id, which is a change to what
        // the blob must say.
        workspace.onChange = { [weak self, weak tab] in
            guard let self = self, let tab = tab else { return }
            workspace.record(tab)
            self.setState {}
        }
        // A shell that exits takes its pane with it, the way it does in every
        // terminal — including this one's local panes. It could only sit there
        // dead before, because nothing ever told us: the daemon never sent
        // EXIT until now.
        workspace.onPaneEnded = { [weak self, weak tab] paneId in
            guard let self = self, let tab = tab,
                  let pane = tab.panes.first(where: { $0.id == paneId })
            else { return }
            self._removePane(tab, pane, endSession: false)
        }
        // The tab is found again by id rather than captured: this closure
        // crosses a thread boundary (it is called after a hop to the UI
        // thread), and a tab is not a value that may cross one.
        let tabId = tab.id
        workspace.start(
            onRestore: { [weak self] layout in
                guard let self = self,
                      let tab = self.tabs.first(where: { $0.id == tabId })
                else { return }
                self._restore(tab, layout, adopting: adopt)
            },
            onRearranged: { [weak self] layout in
                guard let self = self,
                      let tab = self.tabs.first(where: { $0.id == tabId })
                else { return }
                self._adopt(tab, layout)
            })
    }

    /// The arrangement the far side was holding becomes this tab's tree.
    ///
    /// A workspace nobody has arranged yet restores nothing, and the pane that
    /// was already on screen becomes its first session — so "open a workspace
    /// that does not exist" and "open one that does" are the same command,
    /// exactly as a named session already is.
    private func _restore(_ tab: TerminalTab, _ layout: PaneLayout?,
                          adopting adopt: UInt32? = nil) {
        guard let workspace = tab.workspace else { return }
        guard let layout = layout else {
            if let pane = tab.panes.first {
                // `adopt` is a session already running on that machine, chosen
                // from the switcher: the new workspace takes it rather than
                // opening a shell beside it and leaving it loose.
                workspace.attach(pane, session: adopt)
                workspace.record(tab)
            }
            setState {}
            return
        }
        // A workspace that HAS an arrangement gets the adopted session added
        // to it, once the panes it already knows about are up.
        if let adopt = adopt {
            // By id, like everything else that crosses this hop: a tab is not
            // a value that may.
            let tabId = tab.id
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      let tab = self.tabs.first(where: { $0.id == tabId })
                else { return }
                self._adoptSession(tab, session: adopt)
            }
        }

        // The placeholder is replaced wholesale rather than reused: which
        // session it would hold depends on where it lands in the restored
        // tree, and there is no answer that is not arbitrary.
        let placeholders = tab.panes
        var restored: [TerminalPane] = []
        let root = buildPaneTree(layout.root) { leaf in
            let pane = _blankPane()
            workspace.attach(pane, session: leaf.session, cwd: leaf.cwd)
            restored.append(pane)
            return pane
        }
        setState {
            tab.root = root
            // Focus where it was. Clamped rather than trusted: the blob is
            // storage, and an index into a tree it does not itself hold.
            let index = min(max(0, layout.activeLeaf), max(0, restored.count - 1))
            tab.activePaneId = restored.indices.contains(index)
                ? restored[index].id : (restored.first?.id ?? 0)
            tab.focusEpoch += 1
        }
        for pane in placeholders { pane.session.terminate() }
    }

    /// Another client rearranged this workspace: take their tree.
    ///
    /// A MERGE, not a rebuild. Every pane already attached to a session the
    /// new arrangement still mentions is kept exactly as it is — same
    /// emulator, same scrollback, same link — and only the shape around it
    /// changes. Rebuilding instead would drop every pane's screen and
    /// reattach, which on a slow link is the difference between a split
    /// appearing and the whole window blinking.
    ///
    /// Last writer wins, which is the same rule as the pty's size: whoever
    /// most recently said something is right, and the other end conforms.
    private func _adopt(_ tab: TerminalTab, _ layout: PaneLayout) {
        guard let workspace = tab.workspace else { return }
        var spare = tab.root.panes
        var kept: [TerminalPane] = []

        let root = buildPaneTree(layout.root) { leaf in
            if leaf.session != 0,
               let index = spare.firstIndex(where: {
                   workspace.sessionId($0) == leaf.session
               }) {
                let pane = spare.remove(at: index)
                kept.append(pane)
                return pane
            }
            // A pane the other client opened. Ours attaches to the same
            // far-side session, so both draw the same bytes.
            let pane = _blankPane()
            workspace.attach(pane, session: leaf.session, cwd: leaf.cwd)
            kept.append(pane)
            return pane
        }

        workspace.adopt {
            setState {
                tab.root = root
                let index = min(max(0, layout.activeLeaf), max(0, kept.count - 1))
                // Focus is theirs too, but only as a starting point: moving it
                // is a local act and the next click here wins it back.
                tab.activePaneId = kept.indices.contains(index)
                    ? kept[index].id : (kept.first?.id ?? tab.activePaneId)
                tab.focusEpoch += 1
            }
        }

        // Panes the other client closed. Their sessions keep running — closing
        // a pane detaches — so this drops the link and the local screen only.
        for pane in spare {
            workspace.detach(pane)
            pane.session.terminate()
        }
    }

    /// Closing the last tab is a no-op: there would be nothing left to look
    /// at, and this app is its window.
    private func _close(_ tab: TerminalTab) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0 === tab })
        else { return }
        tab.workspace?.record(tab)
        setState {
            tabs.remove(at: index)
            tab.workspace?.close()
            for pane in tab.panes { pane.session.terminate() }
            // Closing the active tab hands the slot to the one that took its
            // place (the last tab falls back to the new last); closing one
            // ABOVE it just shifts the index down.
            if index < active { active -= 1 }
            active = min(active, tabs.count - 1)
        }
    }

    // MARK: - Panes

    /// Split the focused pane. The new one takes the keyboard, which is what
    /// every terminal with splits does and what the hand expects.
    private func _split(_ axis: SplitAxis) {
        guard let tab = tabs.indices.contains(active) ? tabs[active] : nil,
              let node = tab.root.node(for: tab.activePaneId) ?? tab.root.node(for: tab.panes.first?.id ?? -1)
        else { return }
        let fresh = _newPane(in: tab)
        setState {
            splitPane(node, axis: axis, with: fresh)
            tab.activePaneId = fresh.id
        }
        tab.workspace?.record(tab)
    }

    /// Close the focused pane. The last pane in a tab closes the tab instead —
    /// a tab with nothing in it is not a state worth having.
    private func _closePane() {
        guard let tab = tabs.indices.contains(active) ? tabs[active] : nil,
              let pane = tab.activePane
        else { return }
        // Asked for by a person, so the shell goes with the pane.
        _removePane(tab, pane, endSession: true)
    }

    /// Take a pane out of its tab, from either direction: someone closed it,
    /// or its shell ended underneath.
    ///
    /// `endSession` is the whole difference. A pane a person closed takes its
    /// remote shell with it — the pane is gone from the arrangement, so a
    /// shell left behind is one nothing will ever show again. A pane whose
    /// shell ALREADY ended has nothing left to kill, and saying so anyway
    /// would be an error frame about a session that no longer exists.
    private func _removePane(_ tab: TerminalTab, _ pane: TerminalPane,
                             endSession: Bool) {
        guard let node = tab.root.node(for: pane.id) else { return }
        guard closePane(node) else {
            // The last pane in the tab. Closing the tab detaches the rest of
            // the workspace, but this pane still ends if that is what was
            // asked for.
            if endSession { tab.workspace?.close(pane) }
            _close(tab)
            return
        }
        setState {
            if endSession {
                tab.workspace?.close(pane)
            } else {
                tab.workspace?.detach(pane)
            }
            pane.session.terminate()
            // Focus lands on whatever now occupies the space. The closing
            // pane's focus node is disposed, so without this nothing holds
            // the keyboard at all and the survivor looks dead.
            tab.activePaneId = tab.panes.first?.id ?? 0
            tab.focusEpoch += 1
        }
        tab.workspace?.record(tab)
    }

    private func _focusPane(_ pane: TerminalPane) {
        guard let tab = tabs.indices.contains(active) ? tabs[active] : nil
        else { return }
        // Engaging with a pane makes this client the one whose size the far
        // side follows — see TerminalWorkspace.assertSizes. Before the early
        // return below, because clicking the pane you are already in is
        // exactly how someone fixes a screen sized for another machine.
        tab.workspace?.assertSizes(tab)
        // Clicking into a pane clears its badge now rather than up to a poll
        // later — the dot vanishing under the cursor is the feedback that the
        // click landed.
        pane.markSeen()
        guard tab.activePaneId != pane.id else { return }
        setState { tab.activePaneId = pane.id }
        // Which pane had the keyboard is part of the arrangement — coming
        // back to a workspace typing into a different pane than the one you
        // left is exactly the kind of small wrongness this is for.
        tab.workspace?.record(tab)
    }

    private func _select(_ tab: TerminalTab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }), index != active
        else { return }
        setState { active = index }
        // Bringing a workspace to the front is engaging with it, exactly as
        // clicking one of its panes is.
        tab.workspace?.assertSizes(tab)
    }

    /// Nth tab, zero-based. Out of range does nothing rather than clamping:
    /// ⌘4 in a window with three tabs is a mistake, and landing on the third
    /// would be a silent wrong answer.
    private func _selectIndex(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        _select(tabs[index])
    }

    /// 1…9 from a key id, in either spelling, or nil for anything else.
    ///
    /// A digit key usually arrives as its own ASCII value — but not when a
    /// modifier means it produces no character. Holding ⌘ on the Cocoa host
    /// turns ⌘2 into `0x2_0000_0232`: Flutter's synthesized plane, with the
    /// key's LABEL in the low byte. Testing only for `0x31...0x39` therefore
    /// matches on Linux and never on the Mac, where the digit is typed into
    /// the shell instead — which is exactly how this was found.
    private func _digitKey(_ logical: Int64) -> Int? {
        if logical >= 0x31 && logical <= 0x39 { return Int(logical - 0x30) }
        if logical >= 0x2_0000_0231 && logical <= 0x2_0000_0239 {
            return Int(logical - 0x2_0000_0230)
        }
        return nil
    }

    /// Next or previous tab, wrapping. Wrapping is what every terminal and
    /// browser does, and it is what makes Ctrl+PageDown usable as "keep
    /// going" rather than something that stops at the end.
    private func _cycleTab(_ delta: Int) {
        guard tabs.count > 1 else { return }
        let n = tabs.count
        _selectIndex(((active + delta) % n + n) % n)
    }

    // MARK: - Chords

    /// First refusal on every key, handed to the terminal on screen.
    ///
    /// Returning true swallows the key — the shell never sees it — so this
    /// takes as little as it can:
    ///
    ///   - Ctrl+Shift+/ / ⌘/          this list, on screen (TerminalHelp)
    ///   - Ctrl+T / ⌘T                 new tab
    ///   - Ctrl+Shift+D / ⌘D           split the pane left|right
    ///   - Ctrl+Shift+E / ⌘⇧D          split the pane top/bottom
    ///   - Ctrl+Shift+W / ⌘W           close the pane, or the tab if it is
    ///                                 the last pane in it
    ///   - Ctrl+Shift+O / ⌘O           go to a workspace (TerminalSwitcher)
    ///   - Ctrl+PageUp/PageDown        previous / next tab, wrapping
    ///   - Ctrl+Tab / Ctrl+Shift+Tab   next / previous tab (bare Ctrl+Tab
    ///                                 does not reach us on macOS — below)
    ///   - ⌘1…⌘8, ⌘9                   that tab, and the last one
    ///   - ⌘⇧[ / ⌘⇧]                   previous / next tab
    ///
    /// Ctrl+T is `transpose-chars` in every shell's emacs-mode line editor and
    /// is now gone; that is the price of the chord asked for. Close is
    /// deliberately NOT Ctrl+W, which is `backward-kill-word` and gets used
    /// constantly — Ctrl+Shift+W is gnome-terminal's spelling and collides
    /// with nothing.
    private func _appChord(_ keyData: KeyData) -> Bool {
        let down = keyData.type == .down || keyData.type == .repeat
        // Two id schemes, as everywhere else: X11 keysyms from the DRM
        // embedder, Flutter logical ids from the Cocoa/GTK/Win32 hosts. The
        // modifiers must fall through so the TerminalView tracks them too.
        switch keyData.logical {
        case 0xFFE1, 0xFFE2, 0x2_0000_0102, 0x2_0000_0103:   // shift
            _shiftDown = down
            return false
        case 0xFFE3, 0xFFE4, 0x2_0000_0100, 0x2_0000_0101:   // control
            _ctrlDown = down
            return false
        case 0xFFE7, 0xFFE8, 0x2_0000_0106, 0x2_0000_0107:   // command
            _metaDown = down
            return false
        default:
            break
        }
        // An open switcher owns the keyboard, and takes it before any chord
        // below: while it is up, `d` is a letter in a hostname and not a
        // split. It comes AFTER the modifier cases above, which must keep
        // falling through so the state stays right underneath it.
        if _switcher.open { return _switcherKey(keyData) }
        // Same rule as the switcher, one sheet down: while help is up it owns
        // the keyboard, and it comes after the modifier cases above so the
        // state underneath stays right.
        if _helpOpen { return _helpKey(keyData) }
        guard down else { return false }

        // ⌘/ — or Ctrl+Shift+/ — before every other chord, so the way OUT of
        // not knowing the chords is itself reachable without knowing them.
        if _isHelpChord(keyData) { _openHelp(); return true }

        let isT = keyData.logical == 0x54 || keyData.logical == 0x74
        let isW = keyData.logical == 0x57 || keyData.logical == 0x77
        let isD = keyData.logical == 0x44 || keyData.logical == 0x64
        let isE = keyData.logical == 0x45 || keyData.logical == 0x65
        let isO = keyData.logical == 0x4F || keyData.logical == 0x6F

        // Two id schemes again: X11 keysyms from the DRM embedder, Flutter
        // logical ids everywhere else. Note pageUp/pageDown are NOT in the
        // same order in the two tables — 0xFF55 is up and 0x1_0000_0308 is
        // up, but the Flutter pair reads 0307=down, 0308=up.
        let isPageUp = keyData.logical == 0xFF55 || keyData.logical == 0x1_0000_0308
        let isPageDown = keyData.logical == 0xFF56 || keyData.logical == 0x1_0000_0307
        let isTab = keyData.logical == 0xFF09 || keyData.logical == 0x1_0000_0009

        // Tab navigation, on every platform. Ctrl+PageUp/PageDown is what
        // gnome-terminal and konsole use, and it collides with nothing: the
        // scrollback pager next door is SHIFT+PageUp.
        //
        // Ctrl+Tab is the other spelling people have in their fingers, and it
        // is bound here — but **the macOS Cocoa host reports logical id 0 for
        // bare Ctrl+Tab**, with no way to tell it from any other key that has
        // no logical id, so it cannot be claimed there. (Ctrl+Shift+Tab comes
        // through correctly as 0x1_0000_0009 even on that host, which is why
        // the pair is asymmetric rather than simply absent.) Matching 0 to
        // recover it would swallow every unlabelled key in the terminal, which
        // is a far worse trade than one missing chord on the one platform that
        // also has ⌘1…⌘9 and ⌘⇧[/].
        if _ctrlDown && !_metaDown {
            if isPageUp { _cycleTab(-1); return true }
            if isPageDown { _cycleTab(1); return true }
            if isTab { _cycleTab(_shiftDown ? -1 : 1); return true }
            if isT && !_shiftDown { _newTab(); return true }
            if _shiftDown {
                if isW { _closePane(); return true }
                if isD { _split(.row); return true }
                if isE { _split(.column); return true }
                if isO { _openSwitcher(); return true }
            }
        }
        #if os(macOS)
        // The native chords, beside the Ctrl ones every platform gets — the
        // same pairing TerminalView already makes for copy/paste/find. Cmd+D
        // and Cmd+Shift+D are iTerm's split pair, which is the muscle memory
        // most Mac terminal users already have.
        if _metaDown && !_ctrlDown {
            // ⌘1…⌘8 jump, and ⌘9 is the LAST tab rather than the ninth —
            // Safari's rule, which Terminal.app and iTerm both follow, and
            // which is more useful than a ninth tab nobody has.
            if let digit = _digitKey(keyData.logical) {
                _selectIndex(digit == 9 ? tabs.count - 1 : digit - 1)
                return true
            }
            // ⌘⇧[ / ⌘⇧] — Terminal.app's and Chrome's pair. Both the bare
            // bracket and the shifted brace are accepted because which one
            // arrives depends on whether the embedder reports the key's label
            // or the character it produced, and that has differed before.
            if _shiftDown {
                if keyData.logical == 0x5B || keyData.logical == 0x7B {
                    _cycleTab(-1); return true
                }
                if keyData.logical == 0x5D || keyData.logical == 0x7D {
                    _cycleTab(1); return true
                }
            }
            if isT { _newTab(); return true }
            if isW { _closePane(); return true }
            if isD { _split(_shiftDown ? .column : .row); return true }
            // ⌘O is "open" everywhere on this platform, and no terminal
            // claims it — unlike ⌘K, which iTerm and Terminal.app both use
            // for clearing the buffer.
            if isO { _openSwitcher(); return true }
        }
        #endif
        return false
    }

    // MARK: - Build

    /// The window in logical pixels. The framework has no LayoutBuilder to
    /// discover this from below, and a metrics change rebuilds the whole tree
    /// (see Adapter's onMetricsChanged), so reading it here is what makes the
    /// grid follow a window resize.
    private func _windowSize() -> Size {
        if let view = PlatformDispatcher.instance.implicitView {
            let dpr = view.devicePixelRatio
            let phys = view.physicalSize
            if phys.width > 0, phys.height > 0, dpr > 0 {
                return Size(phys.width / dpr, phys.height / dpr)
            }
        }
        return Size(1100, 700)
    }

    override func build(_ context: any BuildContext) -> Widget {
        let window = _windowSize()
        let showBar = tabs.count > 1
        let barH = showBar ? TabChrome.height : 0
        let body = Size(window.width, max(1, window.height - barH))
        let tab = tabs.indices.contains(active) ? tabs[active] : nil

        let chrome = Column(
            crossAxisAlignment: .stretch,
            children: [
                // Always emitted, zero-height when hidden: the children
                // then keep their positions across the 1↔2 tab boundary
                // and the terminal below is never re-matched by index.
                SizedBox(
                    width: window.width, height: barH,
                    child: showBar ? _bar(width: window.width) : nil
                ),
                SizedBox(
                    key: tab.map { ValueKey($0.id) },
                    width: body.width, height: body.height,
                    child: tab.map { _panes($0, in: body) }
                ),
            ]
        )

        return Directionality(
            textDirection: .ltr,
            child: Stack(children: [
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: chrome),
                // Over everything, including the tab bar: the switcher is a
                // question about which of these you want to be looking at.
                _switcher.open
                    ? _switcherOverlay(Size(window.width, window.height))
                    : SizedBox(width: 0, height: 0),
                // And help over that again — it is the sheet you reach for
                // when you do not know what the others are.
                _helpOpen
                    ? _helpOverlay(Size(window.width, window.height))
                    : SizedBox(width: 0, height: 0),
            ])
        )
    }

    // MARK: - Panes on screen

    /// The tab's split tree, resolved and drawn.
    ///
    /// Every pane is told its BOX (`TerminalView.size`) — the view otherwise
    /// sizes its grid from the whole window, which is right for a terminal
    /// that IS the window and wrong for every pane in a split: the shell
    /// would be told a size it does not have.
    private func _panes(_ tab: TerminalTab, in body: Size) -> Widget {
        // A lone pane fills the window edge to edge; only a SPLIT one is held
        // off the edges. Floating a single pane would cost text area and a
        // border around the whole window is noise — the same reason the active
        // ring below only appears once there is something to distinguish from.
        let single = tab.root.pane != nil
        let m = single ? 0 : paneSeamW
        let (leaves, seams, boxes) = resolvePanes(
            tab.root,
            in: PaneBox(x: m, y: m,
                        w: max(1, body.width - 2 * m),
                        h: max(1, body.height - 2 * m)))
        _boxes = boxes

        var layers: [Widget] = []
        // What shows in the gaps. Only when there is a gap: a single pane
        // covers this completely, so painting it would be a full-window fill
        // per frame for nothing.
        if !single {
            layers.append(Positioned(
                left: 0, top: 0, right: 0, bottom: 0,
                child: ColoredBox(color: Color(TabChrome.backdrop))
            ))
        }
        for (node, box) in leaves {
            guard let pane = node.pane else { continue }
            layers.append(_pane(pane, box: box, tab: tab, single: single))
        }
        for (node, box) in seams {
            layers.append(_seam(node, box: box))
        }
        // Above the panes and below the seams' drag targets: a dot is a label,
        // never something to hit.
        for (node, box) in leaves {
            guard let pane = node.pane else { continue }
            if let dot = _statusDot(pane, box: box, tab: tab) { layers.append(dot) }
        }
        return Stack(children: layers)
    }

    /// The pane's OSC 133 status, as one dot in its top-right corner.
    ///
    /// Nothing is drawn for a pane at a prompt, or for one whose shell says
    /// nothing at all — which is most shells until someone turns on shell
    /// integration. A dot on every pane would carry no information; the point
    /// is to find the one that is still working, or the one that finished
    /// while you were reading another.
    ///
    /// The focused pane is never badged for a FINISHED command, because you
    /// are looking at it — `markSeen` runs for it every tick. It is still
    /// badged while running, which is the case where you want to know that the
    /// thing you started is still going.
    private func _statusDot(_ pane: TerminalPane, box: PaneBox,
                            tab: TerminalTab) -> Widget? {
        let color: Int
        switch pane.status {
        case .quiet: return nil
        case .running: color = TabChrome.statusRunning
        case .finished(let ok):
            color = ok ? TabChrome.statusOK : TabChrome.statusFailed
        }
        let d = TabChrome.statusDot
        let inset: Double = 6
        return Positioned(
            left: box.x + box.w - d - inset, top: box.y + inset,
            child: IgnorePointer(
                child: SizedBox(
                    width: d, height: d,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: Color(color),
                            borderRadius: BorderRadius.circular(d / 2)
                        )
                    )
                )
            )
        )
    }

    private func _pane(_ pane: TerminalPane, box: PaneBox,
                       tab: TerminalTab, single: Bool) -> Widget {
        let isActive = pane.id == tab.activePaneId
        return Positioned(
            // Keyed by pane, not by position: without it the framework matches
            // Stack children positionally after a split and hands a mounted
            // terminal another pane's session — the same grid, the wrong
            // shell. `_TerminalViewState` captures its session once.
            key: ValueKey(pane.id &* 1000 &+ (isActive ? tab.focusEpoch : 0)),
            left: box.x, top: box.y,
            child: SizedBox(
                width: box.w, height: box.h,
                child: Listener(
                    // Translucent: the click focuses the pane here AND still
                    // reaches the terminal below, which places the cursor and
                    // takes the keyboard through its own focus node. One click
                    // does both, so no remount is needed to move focus.
                    onPointerDown: { [self] _ in _focusPane(pane) },
                    behavior: .translucent,
                    child: DecoratedBox(
                        // The ring only appears once there is more than one
                        // pane — a single pane has nothing to distinguish it
                        // from, and a border around the whole window is noise.
                        decoration: BoxDecoration(
                            border: single || !isActive ? nil
                                : Border.all(color: Color(TabChrome.activePaneEdge),
                                             width: 1),
                            borderRadius: single ? nil
                                : BorderRadius.circular(TabChrome.paneRadius)
                        ),
                        // Rounded only while floating, and the clip is what
                        // rounds it: the grid paints its own opaque background
                        // over its whole box, so a radius on the decoration
                        // alone leaves square corners of terminal sitting
                        // proud of the rounded chrome behind them.
                        //
                        // A single pane skips the clip entirely rather than
                        // passing radius 0 — this is a layer in the compositor
                        // on every frame of a surface that repaints
                        // constantly, and the common case should not pay for
                        // a corner it does not have.
                        child: single
                            ? _grid(pane, box: box, isActive: isActive)
                            : ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(TabChrome.paneRadius),
                                child: _grid(pane, box: box, isActive: isActive)
                            )
                    )
                )
            )
        )
    }

    /// The grid itself. Pulled out of `_pane` only so the clipped and
    /// unclipped spellings above cannot drift apart.
    private func _grid(_ pane: TerminalPane, box: PaneBox, isActive: Bool) -> Widget {
        TerminalView(
            session: pane.session,
            size: Size(box.w, box.h),
            autofocus: isActive,
            keyFilter: { [self] key in _appChord(key) }
        )
    }

    /// A draggable divider. The ratio it moves belongs to the split's own box,
    /// so a nested split resizes within its parent rather than against it.
    private func _seam(_ node: PaneNode, box: PaneBox) -> Widget {
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
                        guard _dragSeam === node, let last = _lastPointer,
                              let own = _boxes[ObjectIdentifier(node)]
                        else { return }
                        let delta = node.axis == .row
                            ? event.position.dx - last.dx
                            : event.position.dy - last.dy
                        _lastPointer = event.position
                        setState { dragSeam(node, delta: delta, own: own) }
                    },
                    onPointerUp: { [self] _ in
                        _dragSeam = nil
                        _lastPointer = nil
                        setState {}
                        // Once, at the end. The ratio moved a hundred times on
                        // the way here and only where it came to rest is the
                        // arrangement.
                        if let tab = tabs.indices.contains(active) ? tabs[active] : nil {
                            tab.workspace?.record(tab)
                        }
                    },
                    onPointerCancel: { [self] _ in
                        _dragSeam = nil
                        _lastPointer = nil
                        setState {}
                    },
                    // Opaque, so the whole gap is the grab area even though
                    // nothing is painted in it at rest.
                    behavior: .opaque,
                    // NOTHING at rest: the gap is the divider now — backdrop
                    // showing between two panes that float above it — and a
                    // line drawn down the middle of it would be a second
                    // divider inside the first.
                    //
                    // While dragging, a line, so the thing being moved is
                    // visible under the pointer. A sized ColoredBox rather
                    // than a bare DecoratedBox: the latter has no child to
                    // take its size from and paints nothing, which used to
                    // look like a working seam only because the gap either
                    // side of it was visible on its own.
                    child: !dragging ? SizedBox(width: 0, height: 0) : Center(
                        child: SizedBox(
                            width: node.axis == .row ? 2 : box.w,
                            height: node.axis == .row ? box.h : 2,
                            child: ColoredBox(color: Color(TabChrome.seamHot))
                        )
                    )
                )
            )
        )
    }

    // MARK: - The strip

    private func _bar(width: Double) -> Widget {
        let newW: Double = 34
        // Equal shares, macOS Terminal's arrangement — a tab's width says
        // nothing about its title, so there is nothing to size it to.
        let tabW = max(40, (width - newW) / Double(max(1, tabs.count)))
        var row: [Widget] = []
        for (i, tab) in tabs.enumerated() {
            row.append(_tab(tab, ordinal: i + 1, active: i == active, width: tabW))
        }
        row.append(_newButton(width: newW))
        return DecoratedBox(
            decoration: BoxDecoration(color: Color(TabChrome.bar)),
            child: Row(children: row)
        )
    }

    private func _tab(_ tab: TerminalTab, ordinal: Int, active: Bool,
                      width: Double) -> Widget {
        // The whole tab is the click target, and it wraps everything rather
        // than sitting beside it in the Stack: a Text hit-tests opaque, so a
        // sibling listener under the label would never see the middle of its
        // own tab. As an ancestor it is on the hit path whatever absorbs.
        // ✕ is deeper, so it fires first — and both act on the tab object,
        // not its row, so the order does not matter either way.
        return Listener(
            onPointerDown: { [self] _ in _select(tab) },
            behavior: .opaque,
            child: SizedBox(
                width: width, height: TabChrome.height,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: Color(active ? TabChrome.activeTab : TabChrome.bar)
                    ),
                    child: Stack(children: [
                        Positioned(
                            left: 0, top: 0, right: 0, bottom: 0,
                            child: Center(
                                child: Text(
                                    // A workspace tab is named by the thing it
                                    // is: "dev" is what was typed to open it
                                    // and what will be typed to find it again.
                                    tab.workspace?.spec.name ?? "Terminal \(ordinal)",
                                    style: TextStyle(
                                        color: Color(active ? TabChrome.activeText
                                                            : TabChrome.text),
                                        fontSize: 12,
                                        fontFamily: TerminalFontLoader.family,
                                        fontFamilyFallback: TerminalFontLoader.fallback
                                    )
                                )
                            )
                        ),
                        // Left, where macOS puts it, and only while there is
                        // something a close would leave behind.
                        tabs.count > 1
                            ? Positioned(left: 6, top: 5, child: _closeButton(tab))
                            : SizedBox(width: 0, height: 0),
                        // The tab's own dot, on the right. A background tab is
                        // the case this whole feature is for: its panes are not
                        // on screen at all, so without this the only way to
                        // find the one that finished is to visit each in turn.
                        _tabStatus(tab).map { color in
                            Positioned(
                                top: (TabChrome.height - TabChrome.statusDot) / 2,
                                right: 8,
                                child: SizedBox(
                                    width: TabChrome.statusDot,
                                    height: TabChrome.statusDot,
                                    child: DecoratedBox(
                                        decoration: BoxDecoration(
                                            color: Color(color),
                                            borderRadius: BorderRadius.circular(
                                                TabChrome.statusDot / 2)
                                        )
                                    )
                                )
                            ) as Widget
                        } ?? SizedBox(width: 0, height: 0),
                        // A hairline instead of a Border: only the trailing
                        // edge is wanted, and the bar's own colour draws it.
                        Positioned(
                            top: 0, right: 0, bottom: 0,
                            child: SizedBox(
                                width: 1, height: TabChrome.height,
                                child: DecoratedBox(
                                    decoration: BoxDecoration(
                                        color: Color(TabChrome.separator)))
                            )
                        ),
                    ])
                )
            )
        )
    }

    /// One colour for a whole tab, or nil for nothing to say.
    ///
    /// A failure outranks a success and a success outranks work in progress:
    /// the dot is a summary, and the thing you most need to know about a tab
    /// you are not looking at is that something in it went wrong. Red for one
    /// failed pane among five that succeeded is the right summary; amber
    /// because a sixth is still going is not.
    private func _tabStatus(_ tab: TerminalTab) -> Int? {
        var running = false, ok = false
        for pane in tab.panes {
            switch pane.status {
            case .quiet: continue
            case .running: running = true
            case .finished(let good): if good { ok = true } else { return TabChrome.statusFailed }
            }
        }
        if ok { return TabChrome.statusOK }
        return running ? TabChrome.statusRunning : nil
    }

    private func _closeButton(_ tab: TerminalTab) -> Widget {
        return Listener(
            onPointerDown: { [self] _ in _close(tab) },
            behavior: .opaque,
            child: SizedBox(
                width: 18, height: 18,
                child: Center(
                    child: Text(
                        "✕",
                        style: TextStyle(
                            color: Color(TabChrome.button),
                            fontSize: 11,
                            fontFamily: TerminalFontLoader.family,
                            // ✕ is not in Roboto Mono — it comes out of the
                            // bundled DejaVu fallback, the same chain the grid
                            // leans on for box glyphs.
                            fontFamilyFallback: TerminalFontLoader.fallback
                        )
                    )
                )
            )
        )
    }

    private func _newButton(width: Double) -> Widget {
        return Listener(
            onPointerDown: { [self] _ in _newTab() },
            behavior: .opaque,
            child: SizedBox(
                width: width, height: TabChrome.height,
                child: Center(
                    child: Text(
                        "+",
                        style: TextStyle(
                            color: Color(TabChrome.button),
                            fontSize: 16,
                            fontFamily: TerminalFontLoader.family,
                            fontFamilyFallback: TerminalFontLoader.fallback
                        )
                    )
                )
            )
        )
    }
}

#endif  // !os(iOS)
