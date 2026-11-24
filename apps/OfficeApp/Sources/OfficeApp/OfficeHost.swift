// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// What a host that owns the window's native frame (the iPad's document
// browser) can ask of, and tell, the editors. Plain closures, so the shells
// need no knowledge of UIKit and every other platform leaves them nil — the
// Backstage panels keep working exactly as before.

import Flutter
import FlutterSwiftBridge
import Foundation
import OfficeText

/// What the editors and the host (the iPad's file browser, edit menu and toolbar) say to each other for ONE
/// window: the hooks the host installs, and the toolbar owner. Every window has its own, so two documents open
/// side by side do not take over each other's toolbar or Open panel (docs/plans/ipad-multi-window.md, step 4).
/// A host with one window installs its hooks on `OfficeScene.main`; a tree below an `OfficeSceneScope`
/// uses that scope's scene; with no scope, a tree uses `main`, which is how it was before windows had scenes.
final class OfficeScene {
    /// The first (and, until scenes are turned on, only) window.
    nonisolated(unsafe) static let main = OfficeScene()

    /// Every window's scene that is alive (weakly held), for what concerns them all: the app going to the background.
    nonisolated(unsafe) private static var live: [Weak] = []
    private struct Weak { weak var scene: OfficeScene? }

    init() {
        Self.live.removeAll { $0.scene == nil }
        Self.live.append(Weak(scene: self))
    }

    /// `flushPendingSaves` in every window.
    static func flushAll() {
        for w in live { w.scene?.flushPendingSaves() }
    }

    /// The scene a tree belongs to: the nearest `OfficeSceneScope` above `context`, else `main`.
    /// Does not register a dependency (a scene never changes under a tree).
    static func of(_ context: (any BuildContext)?) -> OfficeScene {
        if let scope = context?.getElementForInheritedWidgetOfExactType(OfficeSceneScope.self)?.widget as? OfficeSceneScope {
            return scope.scene
        }
        return main
    }

    typealias ToolbarButton = OfficeHost.ToolbarButton
    typealias EditMenuItem = OfficeHost.EditMenuItem
    typealias EditorCommands = OfficeHost.EditorCommands

    /// The editors have just written the user's document at `path`.
    /// Set by a host that keeps its own copy of the file.
    var documentSaved: ((String) -> Void)?

    /// The user asked for Open (or Close). Returns true if the host took it
    /// over, so the editor does not show its own file panel.
    var openRequested: (() -> Bool)?

    /// Set by OfficeRoot while mounted: switch the whole window to the
    /// document at `path`, whatever its kind.
    var openPath: ((String) -> Void)?

    /// The host's own "put a copy somewhere" panel (the iPad's document
    /// picker, which can reach iCloud Drive and other apps' folders the way an
    /// in-app file list over the sandbox cannot). `name` is the suggested file
    /// name; `prepare` writes the file to the path it is given and calls its
    /// completion with whether that worked (it may finish later: a PDF is
    /// made asynchronously); `thenOpen` is Save As — the editor carries on in
    /// the copy — against Export, which leaves the document as it is. `done`
    /// gets the chosen file's name, or nil if the user cancelled or it failed.
    /// Set by a host that has such a panel; nil elsewhere, where the Backstage
    /// panels stay.
    var exportRequested: ((_ name: String,
                                  _ prepare: @escaping (_ path: String, _ finished: @escaping (Bool) -> Void) -> Void,
                                  _ thenOpen: Bool,
                                  _ done: @escaping (String?) -> Void) -> Void)?

    /// Set by a host that draws its own edit menu for a finger's selection:
    /// the rect of the selection or caret in the editor view's coordinates
    /// (nil withdraws the menu), the entries, and the selected text if any.
    var editMenuRequested: ((_ x: Double, _ y: Double, _ width: Double, _ height: Double,
                                    _ items: [EditMenuItem], _ selectedText: String?) -> Void)?
    var editMenuDismissed: (() -> Void)?

    /// Set by a host that draws a native toolbar. The editor in front
    /// publishes its buttons through it, and publishes nil when it goes away,
    /// so a deck or a workbook shows none.
    var toolbarChanged: (([ToolbarButton]?) -> Void)?

    /// Publish the buttons for `commands` as `owner`'s toolbar.
    func publishToolbar(_ commands: EditorCommands, owner: AnyObject) {
        guard toolbarChanged != nil else { return }
        let c = commands
        var buttons: [ToolbarButton] = [
            .init(id: "undo", title: "Undo", symbol: "arrow.uturn.backward", isEnabled: c.canUndo) { c.undo() },
            .init(id: "redo", title: "Redo", symbol: "arrow.uturn.forward", isEnabled: c.canRedo) { c.redo() },
            .init(id: "bold", title: "Bold", symbol: "bold", isOn: c.bold) { c.toggleBold() },
            .init(id: "italic", title: "Italic", symbol: "italic", isOn: c.italic) { c.toggleItalic() },
            .init(id: "underline", title: "Underline", symbol: "underline", isOn: c.underline) { c.toggleUnderline() },
        ]
        if c.hasLists {
            buttons.append(.init(id: "bullets", title: "Bullets", symbol: "list.bullet", isOn: c.list == .bullet) { c.toggleList(.bullet) })
            buttons.append(.init(id: "numbering", title: "Numbering", symbol: "list.number", isOn: c.list == .numbered) { c.toggleList(.numbered) })
        }
        publishToolbar(buttons, owner: owner)
    }

    /// The host's edit menu (Cut, Copy, Paste, Select All) for a finger's
    /// selection or caret in `controller`'s text, at `rect` in the editor's
    /// coordinates; nil withdraws it. Every editor of rich text - Writer's page,
    /// a slide's text box or its notes - asks here, so the menu is one thing.
    /// Nothing happens on a host that draws none.
    func showTouchMenu(_ rect: Rect?, controller c: RichDocumentController) {
        #if !os(WASI)
        guard let show = editMenuRequested else { return }
        guard let r = rect else { editMenuDismissed?(); return }
        var items: [EditMenuItem] = []
        if c.hasSelection {
            if !c.readOnly {
                items.append(.init(title: "Cut", symbol: "scissors") { if let d = c.cutSelectionData() { Clipboard.setData(d) } })
            }
            items.append(.init(title: "Copy", symbol: "doc.on.doc") { if let d = c.copySelectionData() { Clipboard.setData(d) } })
        } else if !c.readOnly {
            items.append(.init(title: "Select", symbol: "character.cursor.ibeam") { c.selectWord(at: c.caret) })
        }
        if !c.readOnly {
            items.append(.init(title: "Paste", symbol: "doc.on.clipboard") {
                Clipboard.getData(Clipboard.kAll) { data in
                    guard let data, !data.isEmpty else { return }
                    DispatchQueue.main.async { c.paste(data: data) }
                }
            })
        }
        items.append(.init(title: "Select All", symbol: "selection.pin.in.out") { c.selectAll() })
        show(r.left, r.top, r.width, r.height, items, c.hasSelection ? c.selectedText : nil)
        #endif
    }

    private var flushers: [(owner: ObjectIdentifier, run: () -> Void)] = []

    /// The editor `owner` can write its unsaved work when asked. Registered while mounted, withdrawn on dispose.
    func registerFlush(owner: AnyObject, _ run: @escaping () -> Void) {
        let id = ObjectIdentifier(owner)
        flushers.removeAll { $0.owner == id }
        flushers.append((id, run))
    }

    func unregisterFlush(owner: AnyObject) {
        let id = ObjectIdentifier(owner)
        flushers.removeAll { $0.owner == id }
    }

    /// Writes what this window's editors have not saved yet (what AutoSave would write in two seconds, now). A host
    /// calls it before it removes the window's view, so closing a window never loses the last edits.
    func flushPendingSaves() {
        for f in flushers { f.run() }
    }

    private var toolbarOwner: ObjectIdentifier?

    /// Publish `buttons` for `owner`, or withdraw them (nil). A new editor
    /// mounts before the one it replaces is disposed, so a withdrawal counts
    /// only from whoever published last; otherwise the old one's dispose would
    /// wipe the new one's bar.
    func publishToolbar(_ buttons: [ToolbarButton]?, owner: AnyObject) {
        guard let changed = toolbarChanged else { return }
        if buttons != nil {
            toolbarOwner = ObjectIdentifier(owner)
        } else if toolbarOwner != ObjectIdentifier(owner) {
            return
        } else {
            toolbarOwner = nil
        }
        changed(buttons)
    }
}

/// Gives every tree below it `scene` (see `OfficeScene.of`).
final class OfficeSceneScope: InheritedWidget {
    let scene: OfficeScene
    init(scene: OfficeScene, child: Widget) {
        self.scene = scene
        super.init(child: child)
    }
    override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        (oldWidget as! OfficeSceneScope).scene !== scene
    }
}

extension State {
    /// The window this editor is in.
    var officeScene: OfficeScene { OfficeScene.of(context) }
}

/// The types the editors and a host share, and what is not per window.
enum OfficeHost {
    /// One button of the native toolbar over the on-screen keyboard. `symbol`
    /// is an SF Symbol name; state is a snapshot, re-published when it changes.
    struct ToolbarButton {
        let id: String
        let title: String
        let symbol: String
        var isOn = false
        var isEnabled = true
        let action: () -> Void
    }

    /// One entry of the host's edit menu over a selection (Cut, Copy, ...).
    struct EditMenuItem {
        let title: String
        let symbol: String
        var isEnabled = true
        let action: () -> Void
    }

    /// What an editor tells the native toolbar about itself: the state of its
    /// buttons and what each one does. Writer fills it from its text, Slides from
    /// the text box being typed in (undo reaching the deck too), Sheets from the
    /// active cell's format — so the toolbar's list and look live here once.
    /// `list` is nil where an editor has no lists (a cell), and then the two list
    /// buttons are left out.
    struct EditorCommands {
        var canUndo = false
        var canRedo = false
        var bold = false
        var italic = false
        var underline = false
        var hasLists = false
        var list: ListKind? = nil
        var undo: () -> Void
        var redo: () -> Void
        var toggleBold: () -> Void
        var toggleItalic: () -> Void
        var toggleUnderline: () -> Void
        var toggleList: (ListKind) -> Void = { _ in }
    }

    /// Writes an empty document of `kind` to `path`. Used by the host's own
    /// "New" so a blank file exists before the editor opens it.
    static func writeBlank(kind: String, to path: String) -> Bool {
        do {
            switch kind {
            case "presentation":
                let deck = DeckController()
                deck.newDeck()
                try Pptx.write(deck).write(to: URL(fileURLWithPath: path))
            case "workbook":
                try Xlsx.write(Workbook()).write(to: URL(fileURLWithPath: path))
            default:
                var blank = RichDocument()
                blank.styles = OfficeStyles.sheet
                try OfficeFormats.write(blank, to: path)
            }
            return true
        } catch {
            fputs("[office] could not write a blank \(kind): \(error)\n", stderr)
            return false
        }
    }
}
