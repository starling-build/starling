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

    var canGoUp: Bool { Win32Files.parent(of: directory) != nil }
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
        case refresh
        case openInExplorer

        case listed(directory: String, entries: [Win32FileEntry], error: String?)
        case placesLoaded(places: [Win32Place], drives: [Win32Place])
        case iconsChanged
    }

    private(set) var state = FilesState()

    /// Shared with the UI, which turns a key into a `TextureWidget`.
    @ObservationIgnored let icons = IconCache()

    /// Where Back goes. Pushed on every navigation that is not itself a Back.
    @ObservationIgnored private var history: [String] = []

    func add(_ event: Event) {
        switch event {
        case .start:
            icons.onTextureReady = { [weak self] in self?.add(.iconsChanged) }
            Task.detached { [weak self] in
                let places = Win32Files.places()
                let drives = Win32Files.drives()
                await MainActor.run {
                    self?.add(.placesLoaded(places: places, drives: drives))
                    // Home, or the first drive on a machine with no profile
                    // folders to speak of.
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
            }
            _list(path)

        case .goBack:
            guard let previous = history.popLast() else { return }
            _list(previous)

        case .goUp:
            guard let parent = Win32Files.parent(of: state.directory) else { return }
            history.append(state.directory)
            _list(parent)

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

        case .listed(let directory, let entries, let error):
            state.directory = directory
            state.entries = entries
            state.error = error
            state.loading = false
            state.selected = nil
            _warmIcons(entries)

        case .iconsChanged:
            state.iconRevision &+= 1
        }
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
