// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The iPad's chrome — milestone 2 of docs/plans/ipad-ui.md.
//
// This file owns NOTHING about what a pane is. The tab list, the split tree,
// the workspace, the layout blob and the whole chord table are inherited from
// `_TerminalTabsState`; what is overridden is `build`, and that is the entire
// point. Decision 2 of the plan: share the model, fork the chrome. Two copies
// of "what a pane is" is how two UIs quietly become two products, and this
// arrangement makes that impossible rather than merely discouraged — a chord
// added to the desktop table is present here because it is the same table.
//
// Why fork the chrome at all, when the desktop UI already runs on an iPad and
// its chords are verified working there: because the desktop UI is built for
// a pointer. The tab strip is 28pt against Apple's 44pt minimum, panes resize
// by dragging a 1pt seam, and every route into a workspace is a chord — so an
// iPad with no keyboard attached cannot reach one at all. See the plan's "The
// gap, stated plainly".
//
// What this milestone deliberately does NOT have: the sidebar. It lands as a
// bare pane tree so the seam this file represents is proven load-bearing
// before anything is built on top of it — if the model cannot be driven from
// a second set of chrome, that is worth finding out with fifty lines rather
// than five hundred. The sidebar is milestone 3.

#if os(iOS)
import Flutter
import FlutterSwiftBridge
import Foundation

/// The sidebar's metrics and palette.
///
/// Rows are 44pt because that is Apple's minimum touch target and the number
/// the desktop chrome fails: its tab strip is 28. Nothing here is a scaled
/// version of the desktop's `TabChrome` — the two are different instruments,
/// and a shared constant would only make one of them wrong more quietly.
private enum PadChrome {
    /// Wide enough for a workspace name and a session count without
    /// truncation, narrow enough to leave a 13-inch iPad a usable grid in
    /// landscape: 1032 − 260 still gives ~94 columns at 13pt.
    static let sidebar: Double = 260
    static let row: Double = 44
    /// The strip a finger reaches for in portrait, where the sidebar is not
    /// on screen to be tapped.
    static let handle: Double = 44

    static let backdrop: Int = 0xFF_0E1017
    static let sectionText: Int = 0xFF_6E7484
    static let item: Int = 0xFF_C7CCD8
    static let itemActive: Int = 0xFF_E9EBF0
    /// The row you are in. Quiet on purpose — the terminal beside it is the
    /// thing being read.
    static let pickBg: Int = 0x33_8AA0FF
    static let scrim: Int = 0x99_06070B

    /// Same three status colours the desktop uses, and deliberately the same
    /// values: a green dot must not mean two things across two UIs.
    static let statusRunning: Int = 0xFF_E5A44B
    static let statusOK: Int = 0xFF_5FBF6B
    static let statusFailed: Int = 0xFF_E5695B
    static let dot: Double = 8

    /// The permission sheet. Louder than the sidebar because it is the one
    /// surface that acts on the far machine, and a person should never answer
    /// it by accident.
    static let sheetBg: Int = 0xFF_1B1E28
    static let sheetEdge: Int = 0xFF_2C3140
    static let sheetScrim: Int = 0xB3_06070B
    /// The option the program itself is pointing at. Marked, not pre-pressed.
    static let sheetPickBg: Int = 0x2E_8AA0FF
    static let sheetRow: Double = 52
}

/// The iPad terminal: the same workspace, drawn for a finger.
final class TerminalPadView: StatefulWidget {
    override func createState() -> State<StatefulWidget> {
        return _TerminalPadState()
    }
}

final class _TerminalPadState: _TerminalTabsState, @unchecked Sendable {

    /// Whether the slide-over is up. Only consulted in portrait: in landscape
    /// the sidebar is always there, because there is room for it and a
    /// disclosure a person has to remember is worse than 260 points.
    private var _sidebarOpen = false

    /// The OTHER workspaces on this host, as the daemon last reported them.
    /// The one you are in does not come from here — it comes from the model,
    /// which is always right and never waiting on a network.
    private var _others: [WorkspaceSpec] = []

    override func initState() {
        super.initState()
        _refreshOthers()
    }

    private func _refreshOthers() {
        guard let here = WorkspaceSpec.connected else { return }
        TermdDirectory.list(host: here.host,
                            dial: TerminalWorkspace.dialer) { [weak self] listing in
            guard let listing = listing else { return }
            let names = listing.workspaces.map { $0.name }.sorted {
                $0.lowercased() < $1.lowercased()
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setState {
                    self._others = names.compactMap {
                        WorkspaceSpec("\(here.host)/ws:\($0)")
                    }
                }
            }
        }
    }

    /// The permission sheet: the options as they were drawn, one 52pt row
    /// each.
    ///
    /// Deliberately dumb. It shows the parsed labels verbatim, in the parsed
    /// order, and marks the row the program is pointing at — it does not
    /// reorder, rename, colour by meaning, or promote a "safe" option. An
    /// overlay that decided "Yes" was the friendly one would approve the wrong
    /// thing the first time a prompt put a destructive option first, and the
    /// person would have tapped a button that looked reassuring.
    ///
    /// The terminal underneath keeps the keyboard. This adds a way to answer;
    /// it does not take the existing one away, which matters when the sheet is
    /// wrong and the person can see it is wrong.
    // MARK: - Chrome

    override func build(_ context: any BuildContext) -> Widget {
        let window = _windowSize()
        // Stage Manager and Split View both arrive here as a plain width
        // change, so the rule is about the shape of the box and not about the
        // device: if it is wider than it is tall there is room to keep the
        // list on screen, and if it is not there is not.
        let landscape = window.width > window.height
        let docked = landscape
        let tab = tabs.indices.contains(active) ? tabs[active] : nil
        // Portrait pays 44pt for a bar; landscape pays 260 for the sidebar and
        // needs no bar at all. The bar is NOT optional chrome: the handle has
        // to live somewhere, and floating it over the grid hid the first
        // character of the first pane's prompt — a terminal that occludes a
        // character it is drawing is worse than one that is a row shorter.
        let barH = docked ? 0 : PadChrome.handle
        let body = Size(docked ? max(1, window.width - PadChrome.sidebar)
                               : window.width,
                        max(1, window.height - barH))

        // Keyed by tab id for the same reason the desktop keys it: a
        // TerminalView captures its session at mount, so without the key the
        // framework matches two of them positionally on a switch and hands a
        // mounted state another tab's widget — the right grid, the wrong
        // shell behind it.
        let grid = SizedBox(
            key: tab.map { ValueKey($0.id) },
            width: body.width, height: body.height,
            child: tab.map { _panes($0, in: body) }
        )

        var layers: [Widget] = []
        if docked {
            layers.append(Positioned(
                left: 0, top: 0, right: 0, bottom: 0,
                child: Row(crossAxisAlignment: .stretch, children: [
                    _sidebar(height: window.height),
                    grid,
                ])))
        } else {
            layers.append(Positioned(
                left: 0, top: 0, right: 0, bottom: 0,
                child: Column(crossAxisAlignment: .stretch, children: [
                    _topBar(width: window.width),
                    grid,
                ])))
            if _sidebarOpen {
                // Tap-away closes, which is what every slide-over on this
                // platform does and what a person will try first.
                layers.append(Positioned(
                    left: 0, top: 0, right: 0, bottom: 0,
                    child: Listener(
                        onPointerDown: { [self] _ in
                            setState { _sidebarOpen = false }
                        },
                        behavior: .opaque,
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: Color(PadChrome.scrim)),
                            child: SizedBox(width: window.width,
                                            height: window.height)))))
                layers.append(Positioned(left: 0, top: 0,
                                         child: _sidebar(height: window.height)))
            }
        }

        // The permission sheet sits UNDER the switcher and help, not over
        // them: those two are things the person just asked for, and a sheet
        // jumping in front of a deliberate action would be the overlay taking
        // the screen from them.
        layers.append(_prompt.map { _promptOverlay($0, window) }
            ?? SizedBox(width: 0, height: 0))

        // Same two overlays the desktop stacks, in the same order and for the
        // same reasons: the switcher is a question about which of these you
        // want to be looking at, and help is the sheet you reach for when you
        // do not know what the others are. Neither is redrawn here — a second
        // copy would drift.
        layers.append(_switcher.open
            ? _switcherOverlay(Size(window.width, window.height))
            : SizedBox(width: 0, height: 0))
        layers.append(_helpOpen
            ? _helpOverlay(Size(window.width, window.height))
            : SizedBox(width: 0, height: 0))

        return Directionality(textDirection: .ltr, child: Stack(children: layers))
    }

    /// The source list: where you are, what is in it, and where else you
    /// could be.
    private func _sidebar(height: Double) -> Widget {
        let here = WorkspaceSpec.connected
        let tab = tabs.indices.contains(active) ? tabs[active] : nil
        let panes = tab?.panes ?? []

        var rows: [Widget] = [
            SizedBox(width: PadChrome.sidebar, height: 12),
            _label("WORKSPACES", PadChrome.sectionText, 11, indent: 16),
            SizedBox(width: PadChrome.sidebar, height: 6),
        ]

        if let here = here {
            rows.append(_workspaceRow(here, expanded: true, current: true))
            // The panes of the workspace on screen, from the model. Numbered
            // rather than named: a pane has no title of its own, and inventing
            // one from the shell's last command would change under the reader
            // every time a command ran.
            for (i, pane) in panes.enumerated() {
                rows.append(_paneRow(pane, index: i + 1,
                                     active: pane.id == tab?.activePaneId))
            }
        }

        for spec in _others where spec.name != here?.name {
            rows.append(_workspaceRow(spec, expanded: false, current: false))
        }

        rows.append(SizedBox(width: PadChrome.sidebar, height: 6))
        // New goes through the switcher rather than inventing a name here:
        // attach-or-create is one verb on the daemon and should stay one verb
        // in the UI. It is also the only place a DIFFERENT host can be typed.
        rows.append(_tapRow(title: "+  new", color: PadChrome.item,
                            indent: 16, active: false) { [self] in
            setState { _sidebarOpen = false }
            _openSwitcher()
        })

        return DecoratedBox(
            decoration: BoxDecoration(color: Color(PadChrome.backdrop)),
            child: SizedBox(
                width: PadChrome.sidebar, height: height,
                child: Column(crossAxisAlignment: .stretch, children: rows)))
    }

    private func _workspaceRow(_ spec: WorkspaceSpec,
                               expanded: Bool, current: Bool) -> Widget {
        return _tapRow(title: (expanded ? "▾  " : "▸  ") + spec.name,
                       color: current ? PadChrome.itemActive : PadChrome.item,
                       indent: 12, active: false) { [self] in
            setState { _sidebarOpen = false }
            guard !current else { return }
            _goTo(.workspace(spec))
        }
    }

    private func _paneRow(_ pane: TerminalPane, index: Int,
                          active: Bool) -> Widget {
        var dot: Int? = nil
        switch pane.status {
        case .quiet: dot = nil
        case .running: dot = PadChrome.statusRunning
        case .finished(let ok):
            dot = ok ? PadChrome.statusOK : PadChrome.statusFailed
        }
        return _tapRow(title: "shell \(index)",
                       color: active ? PadChrome.itemActive : PadChrome.item,
                       indent: 34, active: active, dot: dot) { [self] in
            setState { _sidebarOpen = false }
            _focusPane(pane)
        }
    }

    /// One 44pt row: a label, an optional status dot, and a whole-row tap
    /// target. The target is the row and not the text — a 12pt glyph is not
    /// something a finger can be asked to hit.
    private func _tapRow(title: String, color: Int, indent: Double,
                         active: Bool, dot: Int? = nil,
                         _ onTap: @escaping () -> Void) -> Widget {
        var cells: [Widget] = [
            SizedBox(width: indent, height: PadChrome.row),
            _label(title, color, 14, indent: 0),
        ]
        if let dot = dot {
            cells.append(Expanded(child: SizedBox(height: PadChrome.row)))
            cells.append(DecoratedBox(
                decoration: BoxDecoration(
                    color: Color(dot),
                    borderRadius: BorderRadius.circular(PadChrome.dot / 2)),
                child: SizedBox(width: PadChrome.dot, height: PadChrome.dot)))
            cells.append(SizedBox(width: 16, height: PadChrome.row))
        }
        return Listener(
            onPointerDown: { _ in onTap() },
            behavior: .opaque,
            child: SizedBox(
                width: PadChrome.sidebar, height: PadChrome.row,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: Color(active ? PadChrome.pickBg : 0x00_000000)),
                    child: Row(crossAxisAlignment: .center, children: cells))))
    }

    /// Portrait's bar: the way to the list, and which workspace you are in.
    ///
    /// Landscape has neither, and needs neither — the sidebar answers both
    /// questions by being on screen. This exists because a hidden sidebar has
    /// to be summoned from somewhere, and because "which workspace am I in"
    /// is otherwise unanswerable in portrait without opening something.
    private func _topBar(width: Double) -> Widget {
        let name = WorkspaceSpec.connected?.name ?? ""
        return DecoratedBox(
            decoration: BoxDecoration(color: Color(PadChrome.backdrop)),
            child: SizedBox(
                width: width, height: PadChrome.handle,
                child: Row(crossAxisAlignment: .center, children: [
                    Listener(
                        onPointerDown: { [self] _ in
                            setState { _sidebarOpen = true }
                        },
                        behavior: .opaque,
                        child: SizedBox(
                            width: PadChrome.handle, height: PadChrome.handle,
                            child: Row(crossAxisAlignment: .center, children: [
                                SizedBox(width: 14, height: PadChrome.handle),
                                _label("☰", PadChrome.item, 17, indent: 0),
                            ]))),
                    _label(name, PadChrome.sectionText, 13, indent: 0),
                ])))
    }

    private func _label(_ text: String, _ color: Int, _ size: Double,
                        indent: Double) -> Widget {
        let t = Text(text, style: TextStyle(
            color: Color(color), fontSize: size,
            fontFamily: TerminalFontLoader.family,
            fontFamilyFallback: TerminalFontLoader.fallback))
        guard indent > 0 else { return t }
        return Row(crossAxisAlignment: .center, children: [
            SizedBox(width: indent, height: 1), t,
        ])
    }
}
#endif
