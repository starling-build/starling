// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The keyboard-shortcut list (U-HELP-1): one table per app, shown in a
// DialogShell. The table is data (a key and its modifiers, with a name for
// the action), and a test drives the app's real key handler with every
// chord of the table, and with every other letter, so the list cannot say a
// key does something it does not, and cannot miss one the handler gained.

import Flutter
import FlutterSwiftBridge

/// One shortcut: the key (as the handler sees it), the modifiers beside the
/// platform's main one, and what it does.
struct ShortcutEntry: Equatable {
    let group: String
    let action: String
    /// The key's logical code: a lower-case letter, a digit or a symbol.
    let key: UInt32
    /// Modifiers held in addition to the main one (⌘ on Apple, Ctrl elsewhere).
    let extra: KeyModifiers
    /// False for a chord the handler needs no main modifier for (not used yet).
    let primary: Bool

    init(_ group: String, _ action: String, _ key: Character, _ extra: KeyModifiers = [], primary: Bool = true) {
        self.group = group
        self.action = action
        self.key = key.unicodeScalars.first!.value
        self.extra = extra
        self.primary = primary
    }

    var modifiers: KeyModifiers { primary ? extra.union(.primary) : extra }

    /// The chord as printed on this platform: "Ctrl+Shift+S" or "⇧⌘S".
    func label(apple: Bool = KeyModifiers.primary == .meta) -> String {
        let name = String(Character(Unicode.Scalar(key)!)).uppercased()
        if apple {
            return (extra.contains(.control) ? "⌃" : "") + (extra.contains(.alt) ? "⌥" : "")
                + (extra.contains(.shift) ? "⇧" : "") + (primary ? "⌘" : "") + name
        }
        var parts: [String] = []
        if primary { parts.append("Ctrl") }
        if extra.contains(.alt) { parts.append("Alt") }
        if extra.contains(.shift) { parts.append("Shift") }
        parts.append(name)
        return parts.joined(separator: "+")
    }
}

enum ShortcutTable {
    /// Writer's shortcuts. The editor's own (clipboard, undo, bold…) come
    /// first, then the shell's.
    static let writer: [ShortcutEntry] = [
        ShortcutEntry("Edit", "Select all", "a"),
        ShortcutEntry("Edit", "Copy", "c"),
        ShortcutEntry("Edit", "Cut", "x"),
        ShortcutEntry("Edit", "Paste", "v"),
        ShortcutEntry("Edit", "Undo", "z"),
        ShortcutEntry("Edit", "Redo", "y"),
        ShortcutEntry("Edit", "Redo", "z", .shift),
        ShortcutEntry("Edit", "Paste text only", "v", .alt),
        ShortcutEntry("Character", "Bold", "b"),
        ShortcutEntry("Character", "Italic", "i"),
        ShortcutEntry("Character", "Underline", "u"),
        ShortcutEntry("Character", "Font dialog", "d"),
        ShortcutEntry("Character", "Bigger font", "]"),
        ShortcutEntry("Character", "Smaller font", "["),
        ShortcutEntry("Character", "Copy format", "c", .shift),
        ShortcutEntry("Character", "Paste format", "v", .shift),
        ShortcutEntry("Paragraph", "Align left", "l"),
        ShortcutEntry("Paragraph", "Center", "e"),
        ShortcutEntry("Paragraph", "Align right", "r"),
        ShortcutEntry("Paragraph", "Justify", "j"),
        ShortcutEntry("Paragraph", "Bullet list", "l", .shift),
        ShortcutEntry("Paragraph", "Indent", "m"),
        ShortcutEntry("Paragraph", "Remove indent", "m", .shift),
        ShortcutEntry("Paragraph", "Hanging indent", "t"),
        ShortcutEntry("Paragraph", "Remove hanging indent", "t", .shift),
        ShortcutEntry("Paragraph", "Single spacing", "1"),
        ShortcutEntry("Paragraph", "Double spacing", "2"),
        ShortcutEntry("Paragraph", "1.5 line spacing", "5"),
        ShortcutEntry("Paragraph", "Normal text", "0", .alt),
        ShortcutEntry("Paragraph", "Heading 1", "1", .alt),
        ShortcutEntry("Paragraph", "Heading 2", "2", .alt),
        ShortcutEntry("Paragraph", "Heading 3", "3", .alt),
        ShortcutEntry("Insert", "Link", "k"),
        ShortcutEntry("Find", "Find", "f"),
        ShortcutEntry("Find", "Replace", "h"),
        ShortcutEntry("Find", "Find next", "g"),
        ShortcutEntry("Find", "Find previous", "g", .shift),
        ShortcutEntry("File", "Save", "s"),
        ShortcutEntry("File", "Save as", "s", .shift),
        ShortcutEntry("File", "Open", "o"),
        ShortcutEntry("File", "New", "n"),
        ShortcutEntry("File", "Print", "p"),
        ShortcutEntry("Help", "Keyboard shortcuts", "/"),
        ShortcutEntry("View", "Zoom in", "="),
        ShortcutEntry("View", "Zoom out", "-"),
        ShortcutEntry("View", "Zoom 100%", "0"),
        ShortcutEntry("View", "Show or hide ¶", "8", .shift),
    ]

    /// Sheets' shortcuts (the grid's own chords, then the window's).
    static let sheets: [ShortcutEntry] = [
        ShortcutEntry("Edit", "Undo", "z"),
        ShortcutEntry("Edit", "Redo", "y"),
        ShortcutEntry("Edit", "Redo", "z", .shift),
        ShortcutEntry("Edit", "Copy", "c"),
        ShortcutEntry("Edit", "Cut", "x"),
        ShortcutEntry("Edit", "Paste", "v"),
        ShortcutEntry("Edit", "Select all", "a"),
        ShortcutEntry("Edit", "Fill down", "d"),
        ShortcutEntry("Edit", "Fill right", "r"),
        ShortcutEntry("View", "Show formulas", "`"),
        ShortcutEntry("Edit", "Insert cells", "+"),
        ShortcutEntry("Edit", "Insert cells", "="),
        ShortcutEntry("Edit", "Delete cells", "-"),
        ShortcutEntry("Format", "Bold", "b"),
        ShortcutEntry("Format", "Italic", "i"),
        ShortcutEntry("Format", "Underline", "u"),
        ShortcutEntry("Format", "Format Cells", "1"),
        ShortcutEntry("Find", "Find", "f"),
        ShortcutEntry("Find", "Replace", "h"),
        ShortcutEntry("Data", "Turn the filter on or off", "l", .shift),
        ShortcutEntry("Data", "Group rows or columns", "k", .shift),
        ShortcutEntry("Data", "Ungroup rows or columns", "j", .shift),
       ShortcutEntry("File", "Save", "s"),
        ShortcutEntry("File", "Save as", "s", .shift),
        ShortcutEntry("File", "Open", "o"),
        ShortcutEntry("File", "New", "n"),
        ShortcutEntry("File", "Print", "p"),
        ShortcutEntry("Help", "Keyboard shortcuts", "/"),
    ]

    /// Slides' shortcuts: the shell's. (Text editing keys belong to the editor.)
    static let slides: [ShortcutEntry] = [
        ShortcutEntry("Edit", "Undo", "z"),
        ShortcutEntry("Edit", "Redo", "y"),
        ShortcutEntry("Edit", "Redo", "z", .shift),
        ShortcutEntry("Edit", "Select all", "a"),
        ShortcutEntry("Edit", "Copy", "c"),
        ShortcutEntry("Edit", "Cut", "x"),
        ShortcutEntry("Edit", "Paste", "v"),
        ShortcutEntry("Edit", "Duplicate", "d"),
        ShortcutEntry("Slides", "New slide", "n", .shift),
        ShortcutEntry("Arrange", "Group", "g"),
        ShortcutEntry("Arrange", "Ungroup", "g", .shift),
        ShortcutEntry("Paragraph", "Center", "e"),
        ShortcutEntry("Paragraph", "Align left", "l"),
        ShortcutEntry("Paragraph", "Align right", "r"),
        ShortcutEntry("Paragraph", "Justify", "j"),
        ShortcutEntry("Find", "Find", "f"),
        ShortcutEntry("Insert", "Link", "k"),
        ShortcutEntry("Find", "Replace", "h"),
       ShortcutEntry("File", "Save", "s"),
        ShortcutEntry("File", "Save as", "s", .shift),
        ShortcutEntry("File", "Open", "o"),
        ShortcutEntry("File", "New", "n"),
        ShortcutEntry("File", "Print", "p"),
        ShortcutEntry("Help", "Keyboard shortcuts", "/"),
    ]

    /// Entries grouped in first-seen order.
    static func groups(_ table: [ShortcutEntry]) -> [(name: String, entries: [ShortcutEntry])] {
        var order: [String] = []
        var by: [String: [ShortcutEntry]] = [:]
        for e in table {
            if by[e.group] == nil { order.append(e.group) }
            by[e.group, default: []].append(e)
        }
        return order.map { ($0, by[$0]!) }
    }
}

/// The list in a dialog; Close (Enter or Esc) dismisses it.
final class ShortcutListDialog: StatelessWidget {
    let table: [ShortcutEntry]
    let onClose: () -> Void

    init(table: [ShortcutEntry], onClose: @escaping () -> Void) {
        self.table = table
        self.onClose = onClose
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        var rows: [Widget] = []
        for g in ShortcutTable.groups(table) {
            rows.append(Padding(padding: EdgeInsets(left: 0, top: 10, right: 0, bottom: 4),
                                child: Text(g.name, style: fluent.typography.bodyStrong)))
            for e in g.entries {
                rows.append(Row(children: [
                    SizedBox(width: 190, child: Text(e.label(), style: fluent.typography.body)),
                    Text(e.action, style: fluent.typography.body),
                ]))
            }
        }
        return DialogShell(title: "Keyboard shortcuts",
                           page: SizedBox(height: 420, child: SingleChildScrollView(
                               child: Column(crossAxisAlignment: .start, children: rows))),
                           okLabel: "Close", cancelLabel: "Cancel", width: 480,
                           onOK: onClose, onCancel: onClose)
    }
}
