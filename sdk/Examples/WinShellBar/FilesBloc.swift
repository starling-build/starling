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
    /// The row the pointer last pressed, for the selection highlight.
    var selected: String?
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
    /// The search box, which filters the listing that is already in memory
    /// rather than starting a new enumeration. Explorer searches the subtree
    /// and we do not -- see `visible` for the honest scope of this.
    var filter = ""
    var canGoUp: Bool { Win32Files.parent(of: directory) != nil }
    /// The path being renamed inline, if any: its row draws a text field in
    /// place of its name. One at a time by construction -- starting a rename
    /// ends any other.
    var renaming: String?

    /// What the list actually shows: the listing, filtered, then ordered.
    ///
    /// STORED, not computed. The row builder indexes this for every visible
    /// row, and a computed property would re-filter and re-sort ten thousand
    /// entries per row -- which is the exact cost this file manager exists to
    /// not pay. Recomputed by `_reproject()` when the listing, the sort or the
    /// filter changes, and at no other time.
    fileprivate(set) var visible: [Win32FileEntry] = []

}

/// The four columns Explorer shows in Details view, which are the four this
/// sorts by.
enum FilesSortKey {
    case name, modified, type, size
}

@Observable
final class FilesBloc: @unchecked Sendable {

    enum Event {
        case start
        case open(String)
        /// A row was activated: enter a folder, or hand a file to the shell.
        case activate(Win32FileEntry)
        case select(String?)
        case selectionInfo(app: String?, type: String?)
        /// The shell's own "Open with" dialog for the selection.
        case openWith
        case goUp
        case goBack
        case goForward
        case refresh
        case sort(FilesSortKey)
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
        case placesLoaded(places: [Win32Place], drives: [Win32Place])
        case iconsChanged
    }

    private(set) var state = FilesState()

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
            let requested = Self.requestedDirectory
            if let requested { _list(requested) }
            Task.detached { [weak self] in
                let places = Win32Files.places()
                let drives = Win32Files.drives()
                await MainActor.run {
                    self?.add(.placesLoaded(places: places, drives: drives))
                    // Home, or the first drive on a machine with no profile
                    // folders to speak of.
                    guard requested == nil else { return }
                    if let start = places.first ?? drives.first {
                        self?.add(.open(start.path))
                    }
                }
            }

        case .placesLoaded(let places, let drives):
            state.places = places
            state.drives = drives

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

        case .filter(let text):
            state.filter = text
            _reproject()

        case .refresh:
            _list(state.directory)

        case .activate(let entry):
            if entry.isDirectory {
                add(.open(entry.path))
            } else {
                // The shell decides what opens a file, exactly as the dock's
                // launcher does — and off this thread, because it is the same
                // ShellExecute that measured 484ms on its slow path.
                Task.detached { Win32AppCatalog.open(entry.path) }
            }

        case .select(let path):
            state.selected = path
            state.selectedApp = nil
            state.selectedType = nil
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
                [weak self] ok in
                if ok { self?.add(.refresh) }
            }

        case .beginRename(let entry):
            state.renaming = entry.path
            state.selected = entry.path

        case .commitRename(let newName):
            guard let path = state.renaming else { return }
            state.renaming = nil
            // The old name is a no-op, not an error -- Enter on an untouched
            // field is how half of all renames end.
            let oldName = (path as NSString).lastPathComponent
            guard !newName.isEmpty, newName != oldName else { return }
            Win32FileOps.rename(path, to: newName, owner: Self.ownerWindow) {
                [weak self] ok in
                if ok {
                    // Keep the selection on the renamed item, under its new
                    // name, so F2-Enter-F2 flows work.
                    let parent = (path as NSString).deletingLastPathComponent
                    self?.state.selected = Win32Files.join(parent, newName)
                }
                self?.add(.refresh)
            }

        case .cancelRename:
            state.renaming = nil

        case .deleteEntry(let entry):
            Win32FileOps.delete(entry.path, owner: Self.ownerWindow) {
                [weak self] ok in
                if ok { self?.add(.refresh) }
            }

        case .showProperties(let entry):
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
                    self.state.selected = path
                    self.state.renaming = path
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
                if let made { self.state.selected = made }
                self.add(.refresh)
            }

        case .listed(let directory, let entries, let error):
            state.directory = directory
            state.entries = entries
            state.error = error
            state.loading = false
            state.selected = nil
            _reproject()
            _warmIcons(entries)

        case .iconsChanged:
            state.iconRevision &+= 1
        }
    }

    /// Rebuilds `state.visible` from the listing, the filter and the sort.
    ///
    /// Folders always sort above files whatever the column, which is what
    /// every file manager does and what keeps a folder findable in a
    /// directory of ten thousand things.
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
        state.visible = rows
    }

    /// Explorer's Type column, cached BY EXTENSION.
    ///
    /// `Win32Files.typeName` is a registry walk, and the reason the selection
    /// footer looks it up once rather than per row. A column needs it for
    /// every visible row, so the answer is cached against the extension --
    /// every .txt in a folder of ten thousand is one lookup, not ten thousand.
    @ObservationIgnored private static var typeCache: [String: String] = [:]

    static func typeLabel(_ entry: Win32FileEntry) -> String {
        if entry.isDirectory { return "File folder" }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        if ext.isEmpty { return "File" }
        if let hit = typeCache[ext] { return hit }
        let name = Win32Files.typeName(for: entry.path)
        let label = name.isEmpty ? ext.uppercased() + " File" : name
        typeCache[ext] = label
        return label
    }

    private func _list(_ path: String) {
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
    private func _warmIcons(_ entries: [Win32FileEntry]) {
        var seen = Set<String>()
        for entry in entries {
            let key = FilesBloc.iconKey(entry)
            guard seen.insert(key).inserted else { continue }
            icons.ensure(key: key, path: entry.path, size: 32)
        }
    }

    /// Directories share one key; files share one per extension.
    static func iconKey(_ entry: Win32FileEntry) -> String {
        entry.isDirectory ? "\u{1}dir" : "\u{1}ext:\(entry.ext)"
    }
}

let filesBloc = FilesBloc()
#endif
