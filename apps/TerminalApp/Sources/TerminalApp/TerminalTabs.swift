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

/// One tab: a shell session, plus an identity that survives the list moving
/// under it.
final class TerminalTab {
    /// Never reused. Everything that acts on a tab does so through the object
    /// or this id, never a row index — a click on ✕ closes the tab and the
    /// click on the tab body behind it arrives afterwards, by which time the
    /// indices have shifted.
    let id: Int
    let session: TerminalSession

    init(id: Int, cols: Int, rows: Int) {
        self.id = id
        self.session = TerminalSession(cols: cols, rows: rows)
    }
}

/// The strip's metrics and palette. Opaque-over-nothing is wrong here: the
/// terminal's own background carries 85% alpha for the desktop's glass, so
/// the bar carries it too or the window looks like two materials.
private enum TabChrome {
    static let height: Double = 28
    /// The active tab is the terminal's own background, so the two read as
    /// one surface; everything else is darker.
    static let activeTab: Int = 0xD9_1E2127
    static let bar: Int = 0xD9_15171A
    static let separator: Int = 0xFF_0E1013
    static let activeText: Int = 0xFF_E8E8E8
    static let text: Int = 0xFF_9AA0A6
    static let button: Int = 0xFF_9AA0A6
}

// MARK: - The tabbed terminal

/// The desktop terminal: a stack of shells, one on screen.
final class TerminalTabsView: StatefulWidget {
    override func createState() -> State<StatefulWidget> {
        return _TerminalTabsState()
    }
}

final class _TerminalTabsState: State<StatefulWidget>, @unchecked Sendable {

    private var tabs: [TerminalTab] = []
    private var active = 0
    private var nextId = 1

    /// Modifier state, watched rather than read off the event: the embedders
    /// report modifiers as their own key events, not as flags on the letter.
    /// Kept here rather than in the TerminalView because the view is
    /// remounted on every tab switch and would forget a held key.
    private var _ctrlDown = false
    private var _shiftDown = false
    private var _metaDown = false

    override func initState() {
        super.initState()
        _open()
    }

    override func dispose() {
        for tab in tabs { tab.session.terminate() }
        tabs = []
        super.dispose()
    }

    // MARK: - The list

    /// A new tab, sized to the one it is opening beside.
    ///
    /// A fresh `TerminalSession` is 80x24 and the view resizes it on mount,
    /// which means the shell would print its first prompt at 80 columns and
    /// then be told the real width — one SIGWINCH and one redraw for nothing.
    /// The active tab already knows the answer.
    @discardableResult
    private func _open() -> TerminalTab {
        var cols = 80, rows = 24
        if let current = tabs.indices.contains(active) ? tabs[active] : nil {
            current.session.lock.lock()
            (cols, rows) = (current.session.emulator.cols,
                            current.session.emulator.rows)
            current.session.lock.unlock()
        }
        let tab = TerminalTab(id: nextId, cols: cols, rows: rows)
        nextId += 1
        tab.session.startShell()
        tabs.append(tab)
        active = tabs.count - 1
        return tab
    }

    private func _newTab() {
        setState { _open() }
    }

    /// Closing the last tab is a no-op: there would be nothing left to look
    /// at, and this app is its window.
    private func _close(_ tab: TerminalTab) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0 === tab })
        else { return }
        setState {
            tabs.remove(at: index)
            tab.session.terminate()
            // Closing the active tab hands the slot to the one that took its
            // place (the last tab falls back to the new last); closing one
            // ABOVE it just shifts the index down.
            if index < active { active -= 1 }
            active = min(active, tabs.count - 1)
        }
    }

    private func _select(_ tab: TerminalTab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }), index != active
        else { return }
        setState { active = index }
    }

    // MARK: - Chords

    /// First refusal on every key, handed to the terminal on screen.
    ///
    /// Returning true swallows the key — the shell never sees it — so this
    /// takes as little as it can:
    ///
    ///   - Ctrl+T / ⌘T          new tab
    ///   - Ctrl+Shift+W / ⌘W    close the current tab
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
        guard down else { return false }

        let isT = keyData.logical == 0x54 || keyData.logical == 0x74
        let isW = keyData.logical == 0x57 || keyData.logical == 0x77

        if _ctrlDown && !_metaDown {
            if isT && !_shiftDown { _newTab(); return true }
            if isW && _shiftDown {
                if tabs.indices.contains(active) { _close(tabs[active]) }
                return true
            }
        }
        #if os(macOS)
        // The native chords, beside the Ctrl ones every platform gets — the
        // same pairing TerminalView already makes for copy/paste/find.
        if _metaDown && !_ctrlDown {
            if isT { _newTab(); return true }
            if isW {
                if tabs.indices.contains(active) { _close(tabs[active]) }
                return true
            }
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

        return Directionality(
            textDirection: .ltr,
            child: Column(
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
                        child: tab.map {
                            TerminalView(
                                session: $0.session,
                                size: body,
                                keyFilter: { [self] key in _appChord(key) }
                            )
                        }
                    ),
                ]
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
                                    "Terminal \(ordinal)",
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
