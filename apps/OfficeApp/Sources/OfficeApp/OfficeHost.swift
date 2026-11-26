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

    /// The windows by the engine view each shows (0 is `main`). Set by the host as windows connect.
    nonisolated(unsafe) static var byView: [Int: OfficeScene] = [:]

    /// A file asked for before this window's tree has mounted (a new window made to show a document): taken as soon as
    /// it has.
    var pendingOpen: String?

    /// Show the document at `path` in this window, now or when the window's tree is up.
    func requestOpen(_ path: String) {
        if let open = openPath { open(path) } else { pendingOpen = path }
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

    /// The host's own way to pick a picture (the iPad's Photo Library / Files sheet): calls `done` with the path of a
    /// readable copy, nil if the user cancelled. Set by a host that has one; nil elsewhere, where the Backstage
    /// picture panel stays.
    var pictureRequested: ((_ done: @escaping (String?) -> Void) -> Void)?

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

    /// The host's share sheet (Messages, Mail, AirDrop, other apps): the same
    /// shape as `exportRequested`, which it replaces for File → Share. The
    /// copy is written to a temporary file, offered, and removed afterwards;
    /// `thenOpen` is ignored. Nil on a host without one, and the Share page
    /// then stays out of Backstage's rail.
    var shareRequested: ((_ name: String,
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
        buttons.append(contentsOf: c.context)
        publishToolbar(buttons, owner: owner)
    }

    /// The host's edit menu (Cut, Copy, Paste, Select All) for a finger's
    /// selection or caret in `controller`'s text, at `rect` in the editor's
    /// coordinates; nil withdraws it. Every editor of rich text - Writer's page,
    /// a slide's text box or its notes - asks here, so the menu is one thing.
    /// Nothing happens on a host that draws none.
    /// `leading` are the entries the editor itself offers for what is under the finger (a misspelling's corrections);
    /// they come first.
    func showTouchMenu(_ rect: Rect?, controller c: RichDocumentController, leading: [EditMenuItem] = []) {
        #if !os(WASI)
        guard let show = editMenuRequested else { return }
        guard let r = rect else { editMenuDismissed?(); return }
        // The items live in UIKit's menu objects, which can outlast the window: they hold the controller weakly, or a
        // closed window's whole document stays in memory.
        var items: [EditMenuItem] = leading
        if c.hasSelection {
            if !c.readOnly {
                items.append(.init(title: "Cut", symbol: "scissors") { [weak c] in if let d = c?.cutSelectionData() { Clipboard.setData(d) } })
            }
            items.append(.init(title: "Copy", symbol: "doc.on.doc") { [weak c] in if let d = c?.copySelectionData() { Clipboard.setData(d) } })
        } else if !c.readOnly {
            items.append(.init(title: "Select", symbol: "character.cursor.ibeam") { [weak c] in if let c { c.selectWord(at: c.caret) } })
        }
        if !c.readOnly {
            items.append(.init(title: "Paste", symbol: "doc.on.clipboard") { [weak c] in
                Clipboard.getData(Clipboard.kAll) { data in
                    guard let data, !data.isEmpty else { return }
                    DispatchQueue.main.async { c?.paste(data: data) }
                }
            })
        }
        if c.hasSelection, !c.readOnly {
            // The commands a selection is most often for: with a hardware keyboard there is no keyboard bar to hold them.
            items.append(.init(title: "Bold", symbol: "bold") { [weak c] in c?.toggleBold() })
            items.append(.init(title: "Italic", symbol: "italic") { [weak c] in c?.toggleItalic() })
            items.append(.init(title: "Underline", symbol: "underline") { [weak c] in c?.toggleUnderline() })
        }
        items.append(.init(title: "Select All", symbol: "selection.pin.in.out") { [weak c] in c?.selectAll() })
        show(r.left, r.top, r.width, r.height, items, c.hasSelection ? c.selectedText : nil)
        #endif
    }

    /// The file this window shows (canonical), and the editor that reported it.
    private(set) var documentPath: String?
    private var documentOwner: ObjectIdentifier?

    /// A path in the one spelling windows compare by (symlinks resolved, so /var and /private/var agree).
    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// For a working copy the host made of a picked document, the document itself (nil for any other path). A document
    /// is the same document however many working copies were made of it, so windows compare by this.
    nonisolated(unsafe) static var originalOf: (String) -> String? = { _ in nil }

    /// The file `path` stands for: its original if it is a working copy, else itself.
    static func identity(_ path: String) -> String { canonical(originalOf(path) ?? path) }

    /// `owner`'s document is now the file at `path` (nil: none). A new editor mounts before the one it replaces is
    /// disposed, so a clear counts only from the editor that set the path last.
    /// The window is gone (the system dropped the scene) but its Flutter tree lingers, as view 0's must:
    /// the file it held is free to be opened elsewhere.
    func releaseDocument() {
        documentPath = nil
        documentOwner = nil
    }

    func setDocumentPath(_ path: String?, owner: AnyObject) {
        if let path {
            documentPath = Self.canonical(path)
            documentOwner = ObjectIdentifier(owner)
        } else if documentOwner == ObjectIdentifier(owner) {
            documentPath = nil
            documentOwner = nil
        }
    }

    /// The window showing the file at `path`, other than `scene`.
    static func holding(_ path: String, besides scene: OfficeScene? = nil) -> OfficeScene? {
        let p = identity(path)
        return live.lazy.compactMap { $0.scene }.first { s in
            s !== scene && s.documentPath.map { identity($0) } == p
        }
    }

    /// Set by a host that can bring this window to the front (the iPad: raises its view, or its scene).
    var raise: (() -> Void)?

    /// Brings this window forward and makes it the one the user is working in.
    func focusWindow() {
        raise?()
        activate()
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
        currentButtons = buttons
        if buttons != nil { Self.active = self }
        // A window that is not the active one keeps its buttons to itself until the user is in it again.
        if buttons == nil || Self.active === self { changed(buttons) }
    }

    /// The buttons this window last published, for when it becomes the active window again.
    private var currentButtons: [ToolbarButton]?

    /// The window the user last touched: the native bar (one for the screen) shows its buttons.
    nonisolated(unsafe) private static weak var active: OfficeScene?

    /// The user touched this window: if another window had the bar, it is this window's now.
    func activate() {
        guard Self.active !== self else { return }
        Self.active = self
        if let changed = toolbarChanged, let b = currentButtons { changed(b) }
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

    /// Keeps the window's scene told which file `session` has open (see OfficeScene.setDocumentPath). Call from
    /// `initState`; call `officeScene.setDocumentPath(nil, owner: self)` from `dispose`.
    func trackDocumentPath(_ session: OfficeSession) {
        session.onPathChanged = { [weak self] path in
            guard let self else { return }
            self.officeScene.setDocumentPath(path, owner: self)
        }
        if let path = session.path { officeScene.setDocumentPath(path, owner: self) }
    }
}

/// The types the editors and a host share, and what is not per window.
enum OfficeHost {
    /// How long after the last edit AutoSave writes (OFFICE_AUTOSAVE_DELAY_MS overrides the two seconds, so a
    /// check can tell a flush from the timer).
    static let autosaveDelay: DispatchTimeInterval = {
        if let v = ProcessInfo.processInfo.environment["OFFICE_AUTOSAVE_DELAY_MS"], let ms = Int(v), ms >= 0 {
            return .milliseconds(ms)
        }
        return .seconds(2)
    }()

    /// Where a browser tab keeps its recovery copy: it has no files, so the page keeps one row per tab in its
    /// storage (IndexedDB), and offers a row whose tab has closed to the next tab that starts. nil natively, where
    /// the copy is a file beside the document; the web build sets it at start-up, a test sets an in-memory one.
    nonisolated(unsafe) static var browserRecovery: BrowserRecovery?

    struct BrowserRecovery {
        /// Writes (or replaces) this tab's copy: its kind ("docx", "pptx"), the name it would save under, the bytes.
        var keep: (_ kind: String, _ name: String, _ data: Data) -> Void
        /// Drops this tab's copy: the document was saved, or its changes were let go.
        var discard: () -> Void
        /// A copy of this kind left by a tab that closed with unsaved changes, newest first; taking it makes it
        /// this tab's own copy, so a later keep or discard acts on it.
        var take: (_ kind: String) -> (name: String, data: Data)?
    }

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
        /// Buttons for what the selection is in (a table cell, a picture, a shape), after the fixed ones; their ids
        /// start with "ctx-", which is what the native bar sets them apart by.
        var context: [ToolbarButton] = []
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
