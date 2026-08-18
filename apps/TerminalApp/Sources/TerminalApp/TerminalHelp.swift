// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The keyboard, written down — an overlay listing every chord the terminal
// takes, opened with ⌘/ (Ctrl+Shift+/ everywhere else).
//
// It exists because none of this was discoverable. Splits, workspaces, the
// switcher, pane status and tab navigation are all keyboard features with no
// menu bar to find them in and no man page to read, so a person who was not
// told simply never learns they are there. The tab bar shows tabs; nothing
// shows that ⌘D exists.
//
// Two rules for what goes in here, both learned by writing it:
//
//   1. **Nothing is listed that is not bound.** Every row below was read out
//      of the code that handles it — `_appChord` in TerminalTabs.swift for the
//      window chords, `TerminalView._handleKey` in the sdk for the ones the
//      grid takes. A help screen that lists a chord nobody implemented is
//      worse than no help screen, because the reader blames themselves.
//   2. **Where a chord differs by platform, both spellings are shown**, since
//      the same build of this app runs on the Starling desktop and on a Mac
//      and the reader is on exactly one of them.
//
// The layout is deliberately the switcher's: same scrim, same panel, same
// escape-to-close, because they are the same kind of thing — a sheet over the
// terminal that owns the keyboard while it is up.

import Flutter
import FlutterSwiftBridge
import Foundation

#if !os(iOS)

/// One row: a chord and what it does. `mac` is shown instead of `chord` on
/// macOS when the two differ; nil means the same chord everywhere.
struct HelpBinding {
    let chord: String
    let mac: String?
    let what: String

    init(_ chord: String, mac: String? = nil, _ what: String) {
        self.chord = chord
        self.mac = mac
        self.what = what
    }

    /// The spelling for the platform this build is running on.
    var shown: String {
        #if os(macOS)
        return mac ?? chord
        #else
        return chord
        #endif
    }
}

/// A titled group of bindings.
struct HelpSection {
    let title: String
    let rows: [HelpBinding]
}

/// Everything the terminal binds, by where it is handled.
///
/// The grouping is the user's, not the code's: "windows and tabs" is one idea
/// to a reader even though `_newTab` and `_cycleTab` sit in different branches
/// of the same function, and "the text" mixes chords the app takes with chords
/// the grid takes because a person selecting and copying does not care which
/// layer answered.
enum TerminalHelp {

    static let sections: [HelpSection] = [
        HelpSection(title: "tabs", rows: [
            HelpBinding("Ctrl+T", mac: "⌘T", "a new tab, running a local shell"),
            HelpBinding("Ctrl+PageDown", mac: "⌘⇧]", "next tab"),
            HelpBinding("Ctrl+PageUp", mac: "⌘⇧[", "previous tab"),
            // Bare Ctrl+Tab is not listed on macOS: the Cocoa host reports no
            // logical id for it, so it genuinely does nothing there. See
            // _appChord.
            HelpBinding("Ctrl+Tab", mac: "Ctrl+Shift+Tab", "cycle tabs"),
            HelpBinding("—", mac: "⌘1…⌘8", "that tab"),
            HelpBinding("—", mac: "⌘9", "the last tab"),
        ]),
        HelpSection(title: "panes", rows: [
            HelpBinding("Ctrl+Shift+D", mac: "⌘D", "split left | right"),
            HelpBinding("Ctrl+Shift+E", mac: "⌘⇧D", "split top / bottom"),
            HelpBinding("Ctrl+Shift+W", mac: "⌘W",
                        "close the pane — or the tab, if it is the last one"),
            HelpBinding("click", "focus a pane; drag a gap to resize"),
        ]),
        HelpSection(title: "workspaces", rows: [
            // "letter O" earns its place: ⌘O and ⌘0 are a glyph apart in a
            // monospace face, ⌘1…⌘9 right above it are digits, and ⌘0 is bound
            // to nothing — so guessing wrong looks exactly like a dead chord.
            HelpBinding("Ctrl+Shift+O", mac: "⌘O",
                        "go to a workspace, here or elsewhere (letter O)"),
            HelpBinding("—", "type name, or host/name — ⏎ opens or creates"),
            HelpBinding("—", "or the ssh command itself, ending at /ws:"),
            HelpBinding("—", "   ssh -i ~/.ssh/id_prod deploy@box/ws:dev"),
            HelpBinding("—", "launching with no arguments reopens the last"),
        ]),
        HelpSection(title: "the text", rows: [
            HelpBinding("Ctrl+Shift+C", mac: "⌘C", "copy the selection"),
            HelpBinding("Ctrl+Shift+V", mac: "⌘V", "paste"),
            HelpBinding("Ctrl+Shift+F", mac: "⌘F", "find in scrollback"),
            HelpBinding("Shift+PageUp", "page back through scrollback"),
            HelpBinding("Shift+PageDown", "page forward"),
        ]),
    ]

    /// The status dots, which are the one piece of this that is not a chord
    /// and the piece most likely to be wondered about.
    static let notes: [String] = [
        "a dot on a pane or tab is what its shell is doing:",
        "  amber — a command is running",
        "  green — it finished; red — it failed",
        "  the dot clears when you look at that pane",
        "needs a shell that emits OSC 133; most do not until asked.",
    ]
}

/// The help overlay's palette — the switcher's, because it is the same kind
/// of surface and two sheets over one terminal should not disagree.
private enum HelpChrome {
    static let scrim: Int = 0x99_0B0A16
    static let panel: Int = 0xF2_2B2749
    static let edge: Int = 0xFF_46406B
    static let title: Int = 0xFF_EDEBF7
    static let section: Int = 0xFF_8AA0FF
    static let chord: Int = 0xFF_EDEBF7
    static let what: Int = 0xFF_C9C4E0
    static let hint: Int = 0xFF_8C87AB
    static let row: Double = 19
    static let sectionGap: Double = 12
    /// Where the description starts, so every chord column lines up. In
    /// logical pixels rather than character cells: this panel is laid out with
    /// widgets, not printed into the grid.
    static let chordWidth: Double = 132
}

extension _TerminalTabsState {

    // MARK: - Opening and closing

    func _openHelp() {
        setState { _helpOpen = true }
    }

    func _closeHelp() {
        setState { _helpOpen = false }
    }

    /// Every key while help is up. It takes the lot rather than a chosen few:
    /// a reference you are reading should not also be a thing you can type
    /// into by accident, and the shell behind it must not receive what you
    /// press while looking something up.
    func _helpKey(_ keyData: KeyData) -> Bool {
        guard keyData.type == .down || keyData.type == .repeat else { return true }
        // Esc, or the chord that opened it, or Enter — all mean "done", which
        // is what every one of them means in a reader's hands.
        let logical = keyData.logical
        let isEsc = logical == 0xFF1B || logical == 0x1_0000_001B
        let isEnter = logical == 0xFF0D || logical == 0x1_0000_000D
        if isEsc || isEnter || _isHelpChord(keyData) { _closeHelp() }
        return true
    }

    /// `/` with the platform's modifier. `?` too, since that is what the key
    /// produces with shift held and some hosts report the character rather
    /// than the key's label.
    func _isHelpChord(_ keyData: KeyData) -> Bool {
        let slash = keyData.logical == 0x2F || keyData.logical == 0x3F
            || keyData.logical == 0x2_0000_022F
        guard slash else { return false }
        #if os(macOS)
        return _metaDown || (_ctrlDown && _shiftDown)
        #else
        return _ctrlDown && _shiftDown
        #endif
    }

    // MARK: - Drawing

    func _helpOverlay(_ body: Size) -> Widget {
        let width = min(620, max(300, body.width - 80))

        var children: [Widget] = [
            SizedBox(width: width, height: 14),
            _helpLine("  starling terminal", HelpChrome.title, 14),
            SizedBox(width: width, height: 10),
        ]

        for section in TerminalHelp.sections {
            children.append(_helpLine("  " + section.title, HelpChrome.section, 11))
            children.append(SizedBox(width: width, height: 4))
            for row in section.rows {
                children.append(_helpRow(row, width: width))
            }
            children.append(SizedBox(width: width, height: HelpChrome.sectionGap))
        }

        children.append(_helpLine("  status", HelpChrome.section, 11))
        children.append(SizedBox(width: width, height: 4))
        for note in TerminalHelp.notes {
            children.append(SizedBox(
                width: width, height: HelpChrome.row,
                child: Row(crossAxisAlignment: .center, children: [
                    SizedBox(width: 16, height: HelpChrome.row),
                    _helpLine(note, HelpChrome.what, 11),
                ])
            ))
        }

        children.append(SizedBox(width: width, height: 12))
        // The one chord a reference must state is its own: somebody who found
        // this by accident has no other way to learn how to get back to it.
        #if os(macOS)
        let opener = "⌘/"
        #else
        let opener = "Ctrl+Shift+/"
        #endif
        children.append(_helpLine("  \(opener) opens this · esc closes",
                                  HelpChrome.hint, 11))
        children.append(SizedBox(width: width, height: 14))

        let panel = SizedBox(
            width: width,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: Color(HelpChrome.panel),
                    border: Border.all(color: Color(HelpChrome.edge), width: 1),
                    borderRadius: BorderRadius.circular(8)
                ),
                child: Column(crossAxisAlignment: .start, children: children)
            )
        )

        // The scrim absorbs the dismissing click AND every other one, exactly
        // as the switcher's does: a click reaching a pane behind an open sheet
        // would move focus under it.
        return Positioned(
            left: 0, top: 0, right: 0, bottom: 0,
            child: Listener(
                onPointerDown: { [self] _ in _closeHelp() },
                behavior: .opaque,
                child: SizedBox(
                    width: body.width, height: body.height,
                    child: DecoratedBox(
                        decoration: BoxDecoration(color: Color(HelpChrome.scrim)),
                        child: Column(
                            mainAxisAlignment: .start,
                            crossAxisAlignment: .center,
                            children: [
                                SizedBox(width: body.width,
                                         height: min(40, body.height / 20)),
                                panel,
                            ]
                        )
                    )
                )
            )
        )
    }

    /// A chord and its description, in two columns.
    ///
    /// A row whose chord is "—" is a note that belongs to the section above it
    /// rather than a binding — the switcher's own keys, say, which are real
    /// but are not chords you press from the terminal.
    private func _helpRow(_ row: HelpBinding, width: Double) -> Widget {
        let chord = row.shown
        return SizedBox(
            width: width, height: HelpChrome.row,
            child: Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 16, height: HelpChrome.row),
                SizedBox(
                    width: HelpChrome.chordWidth, height: HelpChrome.row,
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: _helpLine(chord == "—" ? "" : chord,
                                         HelpChrome.chord, 11)
                    )
                ),
                _helpLine(row.what, HelpChrome.what, 11),
            ])
        )
    }

    private func _helpLine(_ text: String, _ color: Int, _ size: Double) -> Widget {
        return Text(text, style: TextStyle(
            color: Color(color), fontSize: size,
            fontFamily: TerminalFontLoader.family,
            fontFamilyFallback: TerminalFontLoader.fallback))
    }
}

#endif
