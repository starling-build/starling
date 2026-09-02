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
            HelpBinding("—", "a launch is a local shell — ⌘O to reach one"),
        ]),
        HelpSection(title: "the text", rows: [
            HelpBinding("Ctrl+Shift+=", mac: "⌘+", "bigger type"),
            HelpBinding("Ctrl+Shift+-", mac: "⌘−", "smaller type"),
            HelpBinding("Ctrl+Shift+0", mac: "⌘0", "back to 13 pt"),
            HelpBinding("Ctrl+Shift+C", mac: "⌘C", "copy the selection"),
            HelpBinding("Ctrl+Shift+V", mac: "⌘V", "paste"),
            HelpBinding("Ctrl+Shift+F", mac: "⌘F", "find in scrollback"),
            HelpBinding("Shift+PageUp", "page back through scrollback"),
            HelpBinding("Shift+PageDown", "page forward"),
        ]),
        // No chords at all — but this is where a person goes looking when a
        // prompt answered itself and they want to know what did it.
        HelpSection(title: "answering by itself", rows: [
            HelpBinding("—", "write ~/.config/starling-terminal/autoanswer:"),
            HelpBinding("—", "   \"Do you want to proceed?\"   \\r"),
            HelpBinding("—", "a pattern, then the keys to type when it shows"),
            HelpBinding("—", "\\r is Enter; /…/ is a regex; # is a comment"),
            HelpBinding("—", "it does not read the question — it will confirm"),
            HelpBinding("—", "anything you tell it to, including a delete"),
            HelpBinding("—", "a badge names the rule each time one fires"),
            HelpBinding("—", "new file? open a new tab. edits apply as you go"),
        ]),
        // Last, because it is the one thing here you press when nothing else
        // in this list is working.
        HelpSection(title: "when it draws the wrong thing", rows: [
            HelpBinding("Ctrl+Shift+R", mac: "⌘⇧R",
                        "write a report — two files, in your home folder"),
            HelpBinding("—", "the .txt is what was on screen, the .png what was drawn"),
            HelpBinding("—", "send both; a photograph cannot say which half is wrong"),
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
    static let scrim: Int = 0x99_06070B
    static let panel: Int = 0xF2_1E212B
    static let edge: Int = 0xFF_333947
    static let title: Int = 0xFF_E9EBF0
    static let section: Int = 0xFF_8AA0FF
    static let chord: Int = 0xFF_E9EBF0
    static let what: Int = 0xFF_C3C8D3
    static let hint: Int = 0xFF_858B99
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

        // The one chord a reference must state is its own: somebody who found
        // this by accident has no other way to learn how to get back to it.
        #if os(macOS)
        let opener = "⌘/"
        #else
        let opener = "Ctrl+Shift+/"
        #endif

        // The list scrolls, the footer does not.
        //
        // This sheet outgrew the window: at the DEFAULT size it was already
        // painting past the bottom edge, and the line it lost was its own
        // "esc closes" — the one line a reader who opened it by accident
        // needs. Capping the list and keeping the footer outside the cap is
        // what makes it honest at any height, rather than correct only on a
        // tall display. `top` is subtracted twice so the panel keeps the same
        // margin below it as above.
        let top = min(40, body.height / 20)
        let footerHeight: Double = 12 + HelpChrome.row + 14
        let listMax = max(120, body.height - top * 2 - footerHeight)

        let panel = SizedBox(
            width: width,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: Color(HelpChrome.panel),
                    border: Border.all(color: Color(HelpChrome.edge), width: 1),
                    borderRadius: BorderRadius.circular(8)
                ),
                child: Column(crossAxisAlignment: .start, children: [
                    ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: listMax),
                        child: SingleChildScrollView(
                            child: Column(crossAxisAlignment: .start,
                                          children: children)
                        )
                    ),
                    SizedBox(width: width, height: 12),
                    _helpLine("  \(opener) opens this · esc closes",
                              HelpChrome.hint, 11),
                    SizedBox(width: width, height: 14),
                ])
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
                                SizedBox(width: body.width, height: top),
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
