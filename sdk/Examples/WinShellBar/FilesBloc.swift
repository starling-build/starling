// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The file explorer's state.
//
// Same shape as DockBloc and SettingsBloc. The reason it matters most here:
// a directory listing is the one thing in this shell that has no upper bound
// — ten thousand files in a folder is ordinary, on a drive that may be asleep
// — so the read is always a `Task.detached` and the UI always has something
// to say while it runs.
//
// HISTORY is a stack rather than a "previous path", because Back has to work
// more than once. Forward is deliberately absent: it is the least-used
// control in every file manager and it costs a second stack to keep honest.

#if os(Windows)
import CupertinoIcons
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import FlutterWin32Bridge
import Foundation
import Observation

struct FilesState {
    var directory = ""
    var entries: [Win32FileEntry] = []
    /// True while a listing is in flight. A folder that takes a moment says
    /// so; an empty one says it is empty. Without this they look identical.
    var loading = false
    var places: [Win32Place] = []
    var drives: [Win32Place] = []
    /// The OneDrive row, when the machine has one. nil is "no row" -- a
    /// sidebar entry that navigates nowhere is worse than absence.
    var oneDrive: Win32Place?
    /// The ShellNew templates for the New dropdown -- loaded once with the
    /// places, empty until the registry walk lands.
    var newTemplates: [Win32Files.ShellNewTemplate] = []
    /// The SELECTION, as Explorer has one: any number of rows, grown by
    /// Ctrl-click, spanned by Shift-click from the anchor. `selected` below
    /// is the single-item view of it that the footer, rename and Open with
    /// consume -- nil whenever the selection is not exactly one, which is
    /// also what makes those single-item affordances honestly disable
    /// themselves on a multi-selection.
    var selection: Set<String> = []
    /// Where a Shift range measures from: the last plainly-clicked row.
    var selectionAnchor: String?
    var selected: String? { selection.count == 1 ? selection.first : nil }
    var error: String?
    /// What opens the selected file, and what Explorer calls its type —
    /// looked up when the selection changes, not per row: the association
    /// database is a registry walk and a listing has thousands of rows.
    var selectedApp: String?
    var selectedType: String?
    /// Bumped when an icon lands — icons rasterize off the UI thread and
    /// arrive after the rows that want them (see DockState.iconRevision).
    var iconRevision = 0

    /// The column the list is ordered by, and which way. Explorer's own
    /// default: folders first, then by name ascending.
    var sortKey: FilesSortKey = .name
    var sortAscending = true
    /// How the listing draws. Per tab, like the sort -- Explorer remembers
    /// a view per folder, and per tab is the honest subset of that.
    var viewMode: FilesViewMode = .details
    /// The search box, which filters the listing that is already in memory
    /// rather than starting a new enumeration. Explorer searches the subtree
    /// and we do not -- see `visible` for the honest scope of this.
    var filter = ""
    var canGoUp: Bool { Win32Files.parent(of: directory) != nil }
    /// The computer view. Not a folder: no listing, no file operations.
    var isThisPC: Bool { directory == kThisPCPath }
    /// A shell-namespace location -- the Recycle Bin, Network, inside a
    /// zip. Listed through the shell, and the file-shaped affordances that
    /// assume a real directory (New, drops into the background) gate off.
    var isNamespace: Bool { directory.hasPrefix("::") || namespaceFile }
    /// Set by the listing when `directory` is a FILE the shell can
    /// enumerate (a zip): FileManager cannot list it, the namespace can.
    fileprivate(set) var namespaceFile = false
    /// The drives with their capacities, for the computer view's tiles --
    /// read when the view opens, not per build: GetDiskFreeSpaceEx on a
    /// sleeping USB drive is a stall nothing should pay per frame.
    var driveDetails: [Win32Drive] = []
    /// The path being renamed inline, if any: its row draws a text field in
    /// place of its name. One at a time by construction -- starting a rename
    /// ends any other.
    var renaming: String?
    /// Subtree search: what the walk under `directory` has found so far,
    /// named by RELATIVE path ("sub\\inner\\notes.txt") so the existing Name
    /// column says where each hit lives. Appended below the folder's own
    /// matches in `visible`.
    fileprivate(set) var searchHits: [Win32FileEntry] = []
    /// True while the walk is still running -- the status bar says so,
    /// because a search that is 10% done looks identical to one that found
    /// everything.
    fileprivate(set) var searching = false

    /// What the list actually shows: the listing, filtered, then ordered.
    ///
    /// STORED, not computed. The row builder indexes this for every visible
    /// row, and a computed property would re-filter and re-sort ten thousand
    /// entries per row -- which is the exact cost this file manager exists to
    /// not pay. Recomputed by `_reproject()` when the listing, the sort or the
    /// filter changes, and at no other time.
    fileprivate(set) var visible: [Win32FileEntry] = []
    /// `visible`, keyed by path -- for the lookups that run per BUILD (the
    /// command bar's enablement asks for the selected entry half a dozen
    /// times, the status bar once more), which must not each walk ten
    /// thousand rows. Rebuilt with `visible`, in `_reproject()`.
    fileprivate(set) var visibleByPath: [String: Win32FileEntry] = [:]

}

/// The computer view's "directory": not a path at all, which the \u{1}
/// prefix guarantees no real folder can be. Opening it draws the drives
/// (Explorer's This PC), and every file-shaped affordance -- New, drops,
/// the background menu -- gates itself off.
let kThisPCPath = "\u{1}ThisPC"

/// The four columns Explorer shows in Details view, which are the four this
/// sorts by.
enum FilesSortKey {
    case name, modified, type, size
}

/// How the listing draws: Explorer's view modes, the ones this window can
/// honestly offer. (List and Content are absent because List is a
/// column-major layout that scrolls sideways -- a different scroller, not a
/// different cell -- and faking it vertically would not be Explorer's List.)
enum FilesViewMode: Equatable {
    case details, tiles, mediumIcons, largeIcons

    /// The raster the mode's icons need. Details stays at the 32 every
    /// listing already warms; the others re-warm at their own edge so a
    /// 48pt drawing is not a 32px texture stretched.
    var iconSide: Int {
        switch self {
        case .details: return 32
        case .tiles, .mediumIcons: return 48
        case .largeIcons: return 96
        }
    }

    var label: String {
        switch self {
        case .details: return "Details"
        case .tiles: return "Tiles"
        case .mediumIcons: return "Medium icons"
        case .largeIcons: return "Large icons"
        }
    }
}

@Observable
final class FilesBloc: @unchecked Sendable {

    enum Event {
        case start
        case open(String)
        /// A row was activated: enter a folder, or hand a file to the shell.
        case activate(Win32FileEntry)
        case select(String?)
        /// Ctrl-click: grow or shrink the selection by one row.
        case toggleSelect(String)
        /// Shift-click: the visible range from the anchor to this row.
        case rangeSelect(String)
        case selectAll
        case clearSelection
        /// The rubber band's current coverage, replacing the selection
        /// wholesale each time it changes (the additive Ctrl case is folded
        /// in by the sender, which knows what the drag started over).
        case bandSelect([String])
        /// The whole selection, as ONE shell operation each.
        case deleteSelection
        case clipSelection(cut: Bool)
        case selectionInfo(app: String?, type: String?)
        /// The shell's own "Open with" dialog for the selection.
        case openWith
        case goUp
        case goBack
        case goForward
        case refresh
        case sort(FilesSortKey)
        case setView(FilesViewMode)
        case sortDirection(ascending: Bool)
        case filter(String)
        case openInExplorer

        /// The file operations, through the shell (IFileOperation): recycle
        /// bin, conflict dialogs, undo. Each refreshes the listing when it
        /// finishes, because nothing here watches the directory yet.
        case clip(Win32FileEntry, cut: Bool)
        case paste(into: String)
        case beginRename(Win32FileEntry)
        case commitRename(String)
        case cancelRename
        case deleteEntry(Win32FileEntry)
        case showProperties(Win32FileEntry)
        /// Explorer's New: create "New folder" (uniqued) and drop straight
        /// into an inline rename on it.
        case newFolder
        case compress(Win32FileEntry)
        /// The Share sheet, via the shell's windows.modernshare verb.
        case share(Win32FileEntry)

        case listed(directory: String, entries: [Win32FileEntry], error: String?)
        case placesLoaded(places: [Win32Place], drives: [Win32Place],
                          oneDrive: Win32Place?)
        case templatesLoaded([Win32Files.ShellNewTemplate])
        case thisPCLoaded([Win32Drive])
        /// Explorer's New submenu, one template: create the file and drop
        /// into its rename field, exactly the newFolder gesture.
        case newFile(Win32Files.ShellNewTemplate)
        /// Ctrl+Z: pop the journal stack and apply the inverse.
        case undo
        /// A batch of subtree-search hits landing from the walk.
        case searchBatch(generation: Int, hits: [Win32FileEntry], done: Bool)
        case iconsChanged
    }

    /// The undo stack: one entry per completed operation, each the
    /// operation's JOURNAL -- what actually happened, in the names the
    /// shell settled on. Ours to keep because the shell's own stack
    /// (FOFX_ADDUNDORECORD) has no replay API; see Win32FileOps.OpRecord.
    /// STATIC, like Explorer's: undo is per session, not per folder --
    /// delete here, Ctrl+Z from any tab or window of this process.
    /// Main-thread only, as all bloc state is.
    ///
    /// What does NOT land here, knowingly: operations run through the
    /// context menu's shell verbs (its Cut/Delete rows go through
    /// InvokeCommand, which reports nothing back), and permanent deletes
    /// (the record's dst is empty -- there is nothing to restore).
    private static var undoStack: [[Win32FileOps.OpRecord]] = []
    private static let undoDepth = 32

    static func pushUndo(_ records: [Win32FileOps.OpRecord]) {
        let undoable = records.filter { !($0.kind == .delete && $0.dst.isEmpty) }
        guard !undoable.isEmpty else { return }
        undoStack.append(undoable)
        if undoStack.count > undoDepth { undoStack.removeFirst() }
    }

    private(set) var state = FilesState()

    /// Where THIS bloc starts, when it is not the first: a new tab opens
    /// Home (Explorer's rule), not whatever `--files` named at launch.
    @ObservationIgnored private let startDirectory: String?

    init(startingIn directory: String? = nil) {
        startDirectory = directory
    }

    /// The window the shell's dialogs (conflict, progress, confirm) parent
    /// to. A dialog with no owner is a window the user can lose behind the
    /// one they asked it from.
    static var ownerWindow: UInt64 { Win32WindowedHost.host?.windowHandle ?? 0 }

    /// Shared with the UI, which turns a key into a `TextureWidget`.
    @ObservationIgnored let icons = IconCache()

    /// Where Back goes. Pushed on every navigation that is not itself a Back.
    @ObservationIgnored private var history: [String] = []

    /// Where Forward goes. Filled only by Back, and emptied by any navigation
    /// that is not a Back or a Forward -- a browser's rule, and the one that
    /// stops Forward pointing at a branch the user has since left.
    @ObservationIgnored private var future: [String] = []

    var canGoBack: Bool { !history.isEmpty }
    var canGoForward: Bool { !future.isEmpty }

    /// `--files <path>`, when one was given. Read here rather than passed in
    /// because the bloc is a global the widget tree reaches for, and threading
    /// a launch argument through the tree to reach it would be worse.
    static let requestedDirectory: String? = {
        guard let i = CommandLine.arguments.firstIndex(of: "--files"),
              i + 1 < CommandLine.arguments.count else { return nil }
        let next = CommandLine.arguments[i + 1]
        return next.hasPrefix("--") ? nil : next
    }()

    func add(_ event: Event) {
        switch event {
        case .start:
            icons.onTextureReady = { [weak self] in self?.add(.iconsChanged) }
            // A directory given on the command line opens FIRST, off the back
            // of the same detached read: the sidebar is furniture, and waiting
            // for it before listing what the user actually asked for would put
            // a profile-folder enumeration in front of every launch.
            let requested = startDirectory ?? Self.requestedDirectory
            if let requested { _list(requested) }
            Task.detached { [weak self] in
                let places = Win32Files.places()
                let drives = Win32Files.drives()
                let oneDrive = Win32Files.oneDrive()
                await MainActor.run {
                    self?.add(.placesLoaded(places: places, drives: drives,
                                            oneDrive: oneDrive))
                    // Home, or the first drive on a machine with no profile
                    // folders to speak of.
                    guard requested == nil else { return }
                    if let start = places.first ?? drives.first {
                        self?.add(.open(start.path))
                    }
                }
            }

        case .placesLoaded(let places, let drives, let oneDrive):
            state.places = places
            state.drives = drives
            state.oneDrive = oneDrive
            // The registry walk rides behind the places rather than in
            // front of any listing; the answer is process-cached, so the
            // tabs after the first pay nothing.
            Task.detached { [weak self] in
                let templates = Win32Files.shellNewTemplates()
                await MainActor.run {
                    self?.add(.templatesLoaded(templates))
                }
            }

        case .templatesLoaded(let templates):
            state.newTemplates = templates

        case .thisPCLoaded(let drives):
            state.driveDetails = drives
            if state.isThisPC { state.loading = false }

        case .newFile(let template):
            let directory = state.directory
            Task.detached { [weak self] in
                let path = Win32Files.shellNewCreate(in: directory,
                                                     template: template)
                await MainActor.run {
                    guard let self else { return }
                    if let path {
                        self.state.selection = [path]
                        self.state.selectionAnchor = path
                        self.state.renaming = path
                        Self.pushUndo([Win32FileOps.OpRecord(
                            kind: .new, src: "", dst: path)])
                    }
                    self.add(.refresh)
                }
            }

        case .open(let path):
            if !state.directory.isEmpty, state.directory != path {
                history.append(state.directory)
                future.removeAll()
            }
            _list(path)

        case .goBack:
            guard let previous = history.popLast() else { return }
            if !state.directory.isEmpty { future.append(state.directory) }
            _list(previous)

        case .goForward:
            guard let next = future.popLast() else { return }
            if !state.directory.isEmpty { history.append(state.directory) }
            _list(next)

        case .goUp:
            guard let parent = Win32Files.parent(of: state.directory) else { return }
            history.append(state.directory)
            future.removeAll()
            _list(parent)

        case .sort(let key):
            // A second click on the column already sorted reverses it, which
            // is the gesture every list view in Windows has.
            if state.sortKey == key {
                state.sortAscending.toggle()
            } else {
                state.sortKey = key
                state.sortAscending = true
            }
            _reproject()

        case .sortDirection(let ascending):
            // The Sort flyout's Ascending/Descending rows say the direction
            // outright, Explorer's way -- no toggle to reason about.
            state.sortAscending = ascending
            _reproject()

        case .setView(let mode):
            state.viewMode = mode
            // The mode's icon edge, warmed for what is already listed --
            // switching to Large icons must not draw 32px rasters at 96pt.
            _warmIcons(state.entries, side: mode.iconSide)

        case .filter(let text):
            state.filter = text
            // The walk first: it clears the previous query's hits, so the
            // reproject below never shows old-query results under the new
            // text.
            _startSearch()
            _reproject()

        case .searchBatch(let generation, let hits, let done):
            // A batch from a cancelled walk: a new filter or a navigation
            // has moved on, and these hits describe a question nobody is
            // asking any more.
            guard generation == searchGeneration else { break }
            state.searchHits.append(contentsOf: hits)
            if done { state.searching = false }
            _reproject()

        case .refresh:
            _list(state.directory)

        case .activate(let entry):
            // The Recycle Bin is a dead end, and deliberately: every row in
            // it is a "$R…" slot, so opening one would hand a recycled file
            // to its association and entering a recycled FOLDER would list
            // the bin's own storage. (isFileSystem does not catch this --
            // recycled items report it TRUE, because the slot really is a
            // file.) Explorer opens nothing here either: Restore it first
            // and open it where it came from. Restore and Properties are on
            // the context menu, through the shell.
            if state.directory == Win32Files.NamespacePlace.recycleBin { break }
            if entry.isDirectory {
                add(.open(entry.path))
            } else if entry.ext == "zip" && entry.isFileSystem {
                // A zip opens AS A FOLDER, Explorer's own gesture -- the
                // listing routes a file path through the namespace.
                add(.open(entry.path))
            } else if !entry.isFileSystem {
                // No file behind it (a Network machine that is not a share,
                // a member inside a zip): activation has nothing honest to
                // do -- there is no path an app could be handed.
            } else {
                // The shell decides what opens a file, exactly as the dock's
                // launcher does — and off this thread, because it is the same
                // ShellExecute that measured 484ms on its slow path.
                Task.detached { Win32AppCatalog.open(entry.path) }
            }

        case .select(let path):
            state.selection = path == nil ? [] : [path!]
            state.selectionAnchor = path
            state.selectedApp = nil
            state.selectedType = nil
            // Nothing to ask in a namespace listing: the association would
            // be looked up against a "$R…" slot, and the footer has no Open
            // buttons there to justify the registry walk anyway. The Type
            // column is already the shell's own (Win32FileEntry.typeName).
            guard !state.isNamespace else { return }
            guard let path,
                  let entry = state.entries.first(where: { $0.path == path }),
                  !entry.isDirectory else { return }
            Task.detached { [weak self] in
                let app = Win32Files.defaultApp(for: path)
                let type = Win32Files.typeName(for: path)
                await MainActor.run {
                    // Only if it is still the selected row: clicking down a
                    // list faster than the registry answers would otherwise
                    // leave the footer describing a file two rows back.
                    guard self?.state.selected == path else { return }
                    self?.add(.selectionInfo(app: app, type: type))
                }
            }

        case .selectionInfo(let app, let type):
            state.selectedApp = app
            state.selectedType = type

        case .toggleSelect(let path):
            if state.selection.contains(path) {
                state.selection.remove(path)
            } else {
                state.selection.insert(path)
            }
            state.selectionAnchor = path
            state.selectedApp = nil
            state.selectedType = nil

        case .rangeSelect(let path):
            // The visible range from the anchor to here, replacing the
            // selection -- Explorer's Shift-click. The anchor stays put so
            // successive Shift-clicks re-span from the same origin.
            let anchor = state.selectionAnchor ?? state.visible.first?.path
            guard let anchor,
                  let from = state.visible.firstIndex(where: { $0.path == anchor }),
                  let to = state.visible.firstIndex(where: { $0.path == path })
            else {
                state.selection = [path]
                state.selectionAnchor = path
                break
            }
            let range = from <= to ? from...to : to...from
            state.selection = Set(state.visible[range].map(\.path))

        case .selectAll:
            state.selection = Set(state.visible.map(\.path))

        case .clearSelection:
            state.selection = []
            state.selectionAnchor = nil

        case .bandSelect(let paths):
            state.selection = Set(paths)
            state.selectedApp = nil
            state.selectedType = nil

        case .deleteSelection:
            // A namespace listing has no multi-item route: a shell menu
            // session addresses ONE item, which is also why the context menu
            // is single-item everywhere. One row still deletes, through the
            // shell (see .deleteEntry); several do nothing rather than
            // quietly deleting the wrong storage.
            if state.isNamespace {
                if let path = state.selected,
                   let entry = state.visibleByPath[path] {
                    add(.deleteEntry(entry))
                }
                break
            }
            let paths = state.visible.map(\.path).filter(state.selection.contains)
            guard !paths.isEmpty else { break }
            Win32FileOps.deleteMany(paths, owner: Self.ownerWindow) {
                [weak self] ok, records in
                if ok {
                    Self.pushUndo(records)
                    self?.add(.refresh)
                }
            }

        case .clipSelection(let cut):
            guard !state.isNamespace else { break }
            let paths = state.visible.map(\.path).filter(state.selection.contains)
            guard !paths.isEmpty else { break }
            Win32FileOps.clipMany(paths, cut: cut)

        case .openWith:
            guard let path = state.selected else { return }
            // BLOCKS on the user, so it cannot be on the drawing thread. And
            // the association may have changed by the time it returns, which
            // is the entire point of the dialog — so re-read after.
            Task.detached { [weak self] in
                Win32Files.openWith(path)
                let app = Win32Files.defaultApp(for: path)
                let type = Win32Files.typeName(for: path)
                await MainActor.run {
                    guard self?.state.selected == path else { return }
                    self?.add(.selectionInfo(app: app, type: type))
                }
            }

        case .openInExplorer:
            let path = state.directory
            Task.detached { Win32Files.openInExplorer(path) }

        case .clip(let entry, let cut):
            Win32FileOps.clip(entry.path, cut: cut)

        case .paste(let directory):
            Win32FileOps.paste(into: directory, owner: Self.ownerWindow) {
                [weak self] ok, records in
                if ok {
                    Self.pushUndo(records)
                    self?.add(.refresh)
                }
            }

        case .beginRename(let entry):
            state.renaming = entry.path
            state.selection = [entry.path]
            state.selectionAnchor = entry.path

        case .commitRename(let newName):
            guard let path = state.renaming else { return }
            state.renaming = nil
            // The old name is a no-op, not an error -- Enter on an untouched
            // field is how half of all renames end.
            let oldName = (path as NSString).lastPathComponent
            guard !newName.isEmpty, newName != oldName else { return }
            Win32FileOps.rename(path, to: newName, owner: Self.ownerWindow) {
                [weak self] ok, records in
                if ok {
                    Self.pushUndo(records)
                    // Keep the selection on the renamed item, under its new
                    // name, so F2-Enter-F2 flows work.
                    let parent = (path as NSString).deletingLastPathComponent
                    let renamed = Win32Files.join(parent, newName)
                    self?.state.selection = [renamed]
                    self?.state.selectionAnchor = renamed
                }
                self?.add(.refresh)
            }

        case .cancelRename:
            state.renaming = nil

        case .deleteEntry(let entry):
            // In a namespace listing the shell's own verb, never
            // Win32FileOps: IFileOperation would take the path at face
            // value, and a recycled item's path is its "$R…" slot -- so it
            // would delete the bin's storage and leave the "$I" record that
            // names it behind. The shell's delete knows it is emptying one
            // bin entry, and puts up the permanent-delete confirmation
            // itself.
            if state.isNamespace {
                runShellVerb("delete", on: entry)
                break
            }
            Win32FileOps.delete(entry.path, owner: Self.ownerWindow) {
                [weak self] ok, records in
                if ok {
                    Self.pushUndo(records)
                    self?.add(.refresh)
                }
            }

        case .showProperties(let entry):
            // Same reasoning: the sheet for a recycled item is the bin's
            // (it names the original location and when it was deleted), not
            // the "$R…" file's.
            if state.isNamespace {
                runShellVerb("properties", on: entry)
                break
            }
            Win32FileOps.showProperties(entry.path, owner: Self.ownerWindow)

        case .newFolder:
            let directory = state.directory
            Win32FileOps.newFolder(in: directory, owner: Self.ownerWindow) {
                [weak self] path in
                guard let self else { return }
                // Explorer's gesture in full: the folder appears already in
                // its rename field. `renaming` survives the refresh because
                // the listing arrives keyed by path.
                if let path {
                    self.state.selection = [path]
                    self.state.selectionAnchor = path
                    self.state.renaming = path
                    Self.pushUndo([Win32FileOps.OpRecord(
                        kind: .new, src: "", dst: path)])
                }
                self.add(.refresh)
            }

        case .share(let entry):
            // The Share sheet has no direct API; it is the
            // windows.modernshare verb on the item's own menu, so a
            // throwaway session finds and runs it -- the same verb the
            // context menu's icon row invokes through its live session.
            let session = Win32ShellMenu(path: entry.path,
                                         owner: Self.ownerWindow)
            session?.items(.full) { rows in
                if let verb = rows.first(where: {
                    $0.verb == "windows.modernshare" && !$0.isSeparator }) {
                    session?.invoke(.full, verb.id)
                }
                session?.close()
            }

        case .compress(let entry):
            Win32FileOps.compressToZip(entry.path) { [weak self] made in
                guard let self else { return }
                if let made {
                    self.state.selection = [made]
                    self.state.selectionAnchor = made
                    // tar.exe runs outside the journal; the zip's path is
                    // the whole record, and undo deletes it.
                    Self.pushUndo([Win32FileOps.OpRecord(
                        kind: .new, src: "", dst: made)])
                }
                self.add(.refresh)
            }

        case .undo:
            guard let entry = Self.undoStack.popLast() else { break }
            let refresh: (Bool) -> Void = { [weak self] ok in
                // Refresh even on failure -- a partial undo (three of five
                // moved back before a conflict was cancelled) has still
                // changed the folder. Failure also does NOT re-push the
                // entry: retrying an inverse whose world has shifted under
                // it does the wrong thing more often than the right one.
                _ = ok
                self?.add(.refresh)
            }
            // One operation's journal is homogeneous in practice (a paste
            // is all copies or all moves), but the grouping below does not
            // depend on it. Kinds map to inverses:
            switch entry[0].kind {
            case .copy, .new:
                // Copies and creations undo the same way: the produced
                // files go to the recycle bin. No confirmation -- Windows
                // does not confirm a recycle, and Explorer's own undo-copy
                // is silent too.
                Win32FileOps.deleteMany(entry.map(\.dst),
                                        owner: Self.ownerWindow) { ok, _ in
                    refresh(ok)
                }
            case .move:
                // Each item back to its OWN folder under its OWN name --
                // src carries both, dst is where it is now. One operation
                // over the set, like the move that is being undone.
                let moves = entry.map { record in
                    (current: record.dst,
                     dir: (record.src as NSString).deletingLastPathComponent,
                     name: (record.src as NSString).lastPathComponent)
                }
                Win32FileOps.undoMoves(moves, owner: Self.ownerWindow,
                                       done: refresh)
            case .rename:
                // A rename journal is one record; its inverse is the old
                // name back onto the new path.
                let record = entry[0]
                let oldName = (record.src as NSString).lastPathComponent
                Win32FileOps.rename(record.dst, to: oldName,
                                    owner: Self.ownerWindow) { ok, _ in
                    refresh(ok)
                }
            case .delete:
                // dst is each item's $R... slot in the bin (empty-dst
                // permanent deletes were filtered at push). The bin's own
                // restore verb, because it alone retires the $I record.
                Win32FileOps.restoreFromBin(entry.map(\.dst),
                                            owner: Self.ownerWindow,
                                            done: refresh)
            }

        case .listed(let directory, let entries, let error):
            state.directory = directory
            state.entries = entries
            state.error = error
            state.loading = false
            state.selection = []
            state.selectionAnchor = nil
            // The filter survives navigation (existing behaviour), so the
            // walk it implies restarts under the NEW root -- and a stale
            // walk under the old one dies either way.
            _startSearch()
            _reproject()
            _warmIcons(entries)
            if state.viewMode.iconSide != 32 {
                _warmIcons(entries, side: state.viewMode.iconSide)
            }

        case .iconsChanged:
            state.iconRevision &+= 1
        }
    }

    /// Rebuilds `state.visible` from the listing, the filter and the sort.
    ///
    /// Folders always sort above files whatever the column, which is what
    /// every file manager does and what keeps a folder findable in a
    /// directory of ten thousand things.
    /// The subtree walk behind the search box -- Explorer's search, in the
    /// honest version this window can offer: a cancellable breadth-first
    /// walk, not an index. Hits stream in batches (the first ones appear
    /// while deep directories are still being read) and carry their
    /// RELATIVE path as the name, which is what tells the user where a hit
    /// lives without a column model this window does not have.
    ///
    /// Deliberate limits, each the cheap honest choice: 1000 hits (a search
    /// that matched a thousand things needs a narrower query, not more
    /// scrolling), half a million entries scanned (the cycle backstop --
    /// junction loops exist and FileManager will happily walk one forever),
    /// and no descent into symlinks or junctions.
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchGeneration = 0

    private func _startSearch() {
        searchTask?.cancel()
        searchGeneration += 1
        state.searchHits = []
        // Nothing to walk on This PC (not a folder) or a namespace listing
        // (FileManager cannot enumerate a "::" location or a zip's inside;
        // the in-memory filter still applies there).
        guard !state.filter.isEmpty, !state.isThisPC, !state.isNamespace,
              !state.directory.isEmpty else {
            state.searching = false
            _reproject()
            return
        }
        let generation = searchGeneration
        let root = state.directory
        let query = state.filter
        state.searching = true
        searchTask = Task.detached(priority: .utility) { [weak self] in
            // The debounce: typing "not" then "notes" should cost one walk,
            // not two -- the first is cancelled here before it reads a
            // single directory.
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }

            let needle = query.lowercased()
            let fm = FileManager()
            let rootDir = root.hasSuffix("\\") ? String(root.dropLast()) : root
            var queue: [String] = [rootDir]     // relative "" == the root
            var batch: [Win32FileEntry] = []
            var found = 0
            var scanned = 0

            func flush(done: Bool) async {
                let out = batch
                batch = []
                await MainActor.run {
                    self?.add(.searchBatch(generation: generation, hits: out,
                                           done: done))
                }
            }

            while !queue.isEmpty, found < 1000, scanned < 500_000 {
                if Task.isCancelled { return }
                let dir = queue.removeFirst()
                guard let names = try? fm.contentsOfDirectory(atPath: dir)
                else { continue }
                for name in names {
                    if Task.isCancelled { return }
                    scanned += 1
                    let path = dir + "\\" + name
                    var isDirectory: ObjCBool = false
                    guard fm.fileExists(atPath: path,
                                        isDirectory: &isDirectory) else {
                        continue
                    }
                    if isDirectory.boolValue {
                        // Junction/symlink loops are the classic infinite
                        // walk; a link's TARGET is elsewhere in the tree
                        // and will be visited on its own.
                        if (try? fm.destinationOfSymbolicLink(atPath: path))
                            == nil {
                            queue.append(path)
                        }
                    }
                    // Depth-1 rows are the listing's own; the in-memory
                    // filter already shows those matches.
                    guard dir != rootDir,
                          name.lowercased().contains(needle) else { continue }
                    let attrs = try? fm.attributesOfItem(atPath: path)
                    let relative = String(path.dropFirst(rootDir.count + 1))
                    batch.append(Win32FileEntry(
                        name: relative,
                        path: path,
                        isDirectory: isDirectory.boolValue,
                        size: (attrs?[.size] as? Int64)
                            ?? Int64((attrs?[.size] as? Int) ?? 0),
                        modified: attrs?[.modificationDate] as? Date,
                        ext: isDirectory.boolValue
                            ? "" : (name as NSString).pathExtension.lowercased()))
                    found += 1
                    if batch.count >= 50 { await flush(done: false) }
                    if found >= 1000 { break }
                }
            }
            await flush(done: true)
        }
    }

    private func _reproject() {
        var rows = state.entries
        if !state.filter.isEmpty {
            let needle = state.filter.lowercased()
            rows = rows.filter { $0.name.lowercased().contains(needle) }
        }
        let ascending = state.sortAscending
        let key = state.sortKey
        rows.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let order: Bool
            switch key {
            case .name: order = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .modified: order = (a.modified ?? .distantPast) < (b.modified ?? .distantPast)
            case .size: order = a.size < b.size
            case .type: order = FilesBloc.typeLabel(a).localizedCaseInsensitiveCompare(
                                    FilesBloc.typeLabel(b)) == .orderedAscending
            }
            return ascending ? order : !order
        }
        // Subtree hits ride below the folder's own matches, in discovery
        // order -- they are named by relative path, so sorting them among
        // the plain names would interleave apples and paths.
        if !state.filter.isEmpty, !state.searchHits.isEmpty {
            rows.append(contentsOf: state.searchHits)
        }
        state.visible = rows
        state.visibleByPath = Dictionary(rows.map { ($0.path, $0) },
                                         uniquingKeysWith: { a, _ in a })
    }

    /// Runs one of the SHELL's own verbs on a row of a namespace listing.
    ///
    /// The only route that reaches such a row at all. Everything else here
    /// speaks paths, and a namespace row's path does not address it back: a
    /// recycled item's is the raw "$R…" slot (which re-parses to the
    /// filesystem file), and the Recycle Bin folder implements no
    /// ParseDisplayName, so no spelling of its name would work either. The
    /// session takes the listing's own directory as the location and finds
    /// the item the way the listing found it -- see Win32ShellMenu.init.
    ///
    /// Throwaway, the same shape as `.share`: open, find the verb, invoke,
    /// close. The refresh is on the invoke's completion because that is when
    /// the shell has finished -- a verb with a dialog does not return until
    /// the user has answered it.
    private func runShellVerb(_ verb: String, on entry: Win32FileEntry) {
        let session = Win32ShellMenu(path: entry.path,
                                     location: state.directory,
                                     owner: Self.ownerWindow)
        session?.items(.full) { [weak self] rows in
            guard let row = rows.first(where: {
                $0.verb == verb && !$0.isSeparator && $0.isEnabled }) else {
                session?.close()
                return
            }
            session?.invoke(.full, row.id) { self?.add(.refresh) }
            session?.close()
        }
    }

    /// Explorer's Type column, cached BY EXTENSION.
    ///
    /// `Win32Files.typeName` is a registry walk, and the reason the selection
    /// footer looks it up once rather than per row. A column needs it for
    /// every visible row, so the answer is cached against the extension --
    /// every .txt in a folder of ten thousand is one lookup, not ten thousand.
    @ObservationIgnored private static var typeCache: [String: String] = [:]

    static func typeLabel(_ entry: Win32FileEntry) -> String {
        // The shell already answered for this item (a namespace listing
        // reads it per item), and where it did it outranks the extension --
        // in the Recycle Bin the extension route asks the association
        // database about a `$R…` slot and gets "TXTX File" for a text file.
        if let type = entry.typeName { return type }
        if entry.isDirectory { return "File folder" }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        // No extension to ask about, and the shell offered nothing: for a
        // real file that is honestly a "File", but a Network device is not
        // one, and calling it that is worse than an empty cell.
        if ext.isEmpty { return entry.isFileSystem ? "File" : "" }
        if let hit = typeCache[ext] { return hit }
        let name = Win32Files.typeName(for: entry.path)
        let label = name.isEmpty ? ext.uppercased() + " File" : name
        typeCache[ext] = label
        return label
    }

    private func _list(_ path: String) {
        // The shell's namespace, not the filesystem: a ::{CLSID} location
        // (Recycle Bin, Network), or a PATH THAT IS NOT A DIRECTORY the
        // shell can enumerate anyway -- which is what browsing a zip is.
        var pathIsDirectory: ObjCBool = false
        let pathExists = FileManager.default.fileExists(
            atPath: path, isDirectory: &pathIsDirectory)
        if path.hasPrefix("::") || (pathExists && !pathIsDirectory.boolValue) {
            state.loading = true
            state.error = nil
            state.namespaceFile = pathExists && !pathIsDirectory.boolValue
            Task.detached { [weak self] in
                let entries = Win32Files.listNamespace(path)
                await MainActor.run {
                    self?.add(.listed(
                        directory: path,
                        entries: entries ?? [],
                        error: entries == nil
                            ? "Cannot open this location." : nil))
                }
            }
            return
        }
        state.namespaceFile = false
        if path == kThisPCPath {
            // The computer view: no directory read, the drives instead.
            state.directory = path
            state.entries = []
            state.error = nil
            state.loading = state.driveDetails.isEmpty
            state.selection = []
            state.selectionAnchor = nil
            _reproject()
            Task.detached { [weak self] in
                let drives = Win32SystemInfo.drives()
                await MainActor.run { self?.add(.thisPCLoaded(drives)) }
            }
            return
        }
        state.loading = true
        state.error = nil
        Task.detached { [weak self] in
            let entries = Win32Files.list(path)
            // An unreadable folder and an empty one are different answers and
            // the UI says so — a bare "0 items" on a permission failure is a
            // lie the user cannot act on.
            let error = entries.isEmpty && !FileManager.default.isReadableFile(atPath: path)
                ? "Cannot read this folder." : nil
            await MainActor.run {
                self?.add(.listed(directory: path, entries: entries, error: error))
            }
        }
    }

    /// One icon per TYPE, not per file.
    ///
    /// Every `.png` in a folder shares an icon, and a thousand-file directory
    /// would otherwise queue a thousand shell round trips behind each other —
    /// the same contention that left 15 of the launcher's 79 icons blank
    /// until they were serialized. Folders share one icon between them all.
    private func _warmIcons(_ entries: [Win32FileEntry], side: Int = 32) {
        var seen = Set<String>()
        for entry in entries {
            // An item with no file behind it has no icon to extract: the
            // shell's extractor wants a path and a parsing name is not one,
            // so this would queue a round trip per zip member or network
            // server only to fail and land back on the glyph the row draws
            // anyway. Skipped BEFORE `seen`, so a real file sharing the
            // extension still warms the key for both.
            guard entry.isFileSystem else { continue }
            let key = FilesBloc.iconKey(entry, side: side)
            if seen.insert(key).inserted {
                icons.ensure(key: key, path: entry.path, size: side)
            }
            // The thumbnail rides BEHIND the type icon on the same serial
            // queue: the type icon is the instant answer every row of that
            // type shares, the thumbnail replaces it per file as the decode
            // lands (IconCache dedups, so re-listing costs nothing).
            if let thumb = FilesBloc.thumbKey(entry, side: side) {
                icons.ensure(thumbnailKey: thumb, path: entry.path,
                             size: side)
            }
        }
    }

    /// Directories share one key; files share one per extension -- and each
    /// raster edge is its own texture, so Details' 32s and Large icons' 96s
    /// coexist rather than the first-warmed size winning for both.
    static func iconKey(_ entry: Win32FileEntry, side: Int = 32) -> String {
        let base = entry.isDirectory ? "\u{1}dir" : "\u{1}ext:\(entry.ext)"
        return side == 32 ? base : "\(base)@\(side)"
    }

    /// The types whose rows show the FILE, not the type: what the shell has
    /// thumbnail handlers for out of the box. A gate rather than asking the
    /// factory about everything -- SIIGBF_THUMBNAILONLY does fail cleanly
    /// for a .txt, but only after touching the file, and a listing of ten
    /// thousand sources should not pay ten thousand misses to learn what
    /// this set already says.
    private static let thumbnailExts: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "webp", "tif", "tiff",
        "heic", "heif", "avif", "jfif",
        "mp4", "mov", "avi", "mkv", "wmv", "webm", "m4v", "mpg", "mpeg",
    ]

    /// The thumbnail texture key for an entry, or nil where a thumbnail is
    /// not on offer. Per FILE (the path is the key), per raster edge, and
    /// only for real files -- a zip member or a recycled slot has nothing
    /// the factory could open.
    static func thumbKey(_ entry: Win32FileEntry, side: Int = 32) -> String? {
        guard !entry.isDirectory, entry.isFileSystem,
              thumbnailExts.contains(entry.ext) else { return nil }
        return "\u{1}thumb:\(entry.path)@\(side)"
    }
}

/// The window's tabs: one bloc per tab -- so history, selection, sort,
/// filter and scroll are each tab's own for free -- and one active index.
/// The `filesBloc` global below resolves to the active tab, which is what
/// keeps every existing consumer (the context menu above all) pointed at
/// the tab the user is looking at without knowing tabs exist.
@Observable
final class FilesTabs: @unchecked Sendable {
    static let shared = FilesTabs()

    private(set) var blocs = [FilesBloc()]
    /// Parallel to `blocs`: each tab keeps its own scroll position, so
    /// switching away and back lands where the user left.
    @ObservationIgnored private(set) var scrolls = [ScrollController()]
    var active = 0

    var bloc: FilesBloc { blocs[active] }
    var scroll: ScrollController { scrolls[active] }

    /// A new tab, opening Home like Explorer's "+" (or `directory` when a
    /// caller has somewhere specific in mind), started and made active.
    func add(_ directory: String? = nil) {
        let home = directory ?? Win32Files.places().first?.path
        let bloc = FilesBloc(startingIn: home)
        blocs.append(bloc)
        scrolls.append(ScrollController())
        active = blocs.count - 1
        bloc.add(.start)
    }

    /// Closes a tab. False when it was the last one -- Explorer closes the
    /// window then, and so does the caller.
    func close(_ index: Int) -> Bool {
        guard blocs.count > 1, blocs.indices.contains(index) else {
            return false
        }
        blocs.remove(at: index)
        scrolls.remove(at: index)
        if active >= blocs.count {
            active = blocs.count - 1
        } else if index < active {
            active -= 1
        }
        return true
    }
}

var filesBloc: FilesBloc { FilesTabs.shared.bloc }
#endif
