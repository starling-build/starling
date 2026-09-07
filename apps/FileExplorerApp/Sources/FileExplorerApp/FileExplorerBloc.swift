// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import Foundation
import Observation

/// Set by _FileExplorerAppState so the themed root can force the lazy
/// file list to rebuild after an appearance change (sliver children only
/// rebuild on bloc emissions).
nonisolated(unsafe) var filesBlocShared: FileExplorerBloc?

// MARK: - File Explorer State

private let _homeDir: String = realUserHomeDirectory()

struct FileExplorerState {
    // Navigation
    var currentPath: String = _homeDir
    var history: [String] = [_homeDir]
    var historyIndex: Int = 0

    // File list
    var allEntries: [FileEntry] = []
    var entries: [FileEntry] = []
    var selectedIndex: Int? = nil

    // Sort
    var sortColumn: SortColumn = .name
    var sortOrder: SortOrder = .ascending

    // Options
    var showHidden: Bool = false
    var searchQuery: String = ""

    // What cut or copy put aside, and whether it was a cut. Windows keeps
    // this on the system clipboard so any app can paste it; ours is the
    // app's own, so a copy here pastes here — see the note on `clip`.
    var clipboard: FileClipboard? = nil
    /// The names already taken at the destination, when a paste is waiting
    /// for the user to say replace, keep both or skip.
    var pasteConflicts: [String] = []
    /// A copy or move in flight, as the status bar says it.
    var busy: String? = nil

    // Error
    var errorMessage: String? = nil
    /// A failed copy, move or delete. Separate from `errorMessage`, which
    /// replaces the whole listing with an error page — a paste that failed
    /// on one file should not take the folder away.
    var operationError: String? = nil

    // Computed
    var canPaste: Bool {
        clipboard != nil && busy == nil && FileSystem.isWritable(currentPath)
    }
    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }
    var canGoUp: Bool { currentPath != "/" }
}

/// What a cut or copy set aside.
struct FileClipboard {
    var paths: [String]
    /// A cut, rather than a copy: the source goes away on paste, and the
    /// clipboard is emptied afterwards so a second paste cannot try to move
    /// a file that has already moved. Explorer's own rule.
    var cut: Bool
}

// MARK: - File Explorer Events

enum FileExplorerEvent {
    // Lifecycle
    case loadInitialDirectory

    // Navigation
    case navigateTo(String)
    case goBack
    case goForward
    case goUp
    case refresh

    // Selection
    case select(Int?)
    case doubleClick(Int)

    // Sort
    case toggleSort(SortColumn)

    // Options
    case toggleHidden
    case search(String)

    // File operations
    case createFolder(name: String)
    case rename(path: String, newName: String)
    case delete(path: String)
    /// Put a path aside for pasting. `cut` moves it rather than copying.
    case clip(path: String, cut: Bool)
    /// Paste into the current folder. Stops and fills `pasteConflicts` when
    /// a name is already taken, so the UI can ask.
    case paste
    /// The answer to that question; the paste then runs.
    case resolvePaste(FileSystem.ConflictPolicy)
    /// The user backed out of the conflict dialog.
    case cancelPaste
}

// MARK: - File Explorer BLoC

@Observable
final class FileExplorerBloc: @unchecked Sendable {

    /// The single source of truth for the UI.
    private(set) var state = FileExplorerState()

    /// Callback for when a directory is double-clicked (navigates into it).
    /// Set by the UI to trigger navigation on double-click.

    /// The only way the UI talks to the BLoC.
    func add(_ event: FileExplorerEvent) {
        switch event {
        case .loadInitialDirectory:
            _loadDirectory(state.currentPath)
        case .navigateTo(let path):
            _navigateTo(path)
        case .goBack:
            _goBack()
        case .goForward:
            _goForward()
        case .goUp:
            _goUp()
        case .refresh:
            _loadDirectory(state.currentPath)
        case .select(let index):
            state.selectedIndex = index
        case .doubleClick(let index):
            _doubleClick(index)
        case .toggleSort(let column):
            _toggleSort(column)
        case .toggleHidden:
            state.showHidden = !state.showHidden
            _loadDirectory(state.currentPath)
        case .search(let query):
            state.searchQuery = query
            _applyFilterAndSort()
        case .createFolder(let name):
            _createFolder(name)
        case .rename(let path, let newName):
            _rename(path: path, newName: newName)
        case .delete(let path):
            _delete(path: path)
        case .clip(let path, let cut):
            state.operationError = nil
            state.clipboard = FileClipboard(paths: [path], cut: cut)
        case .paste:
            _paste()
        case .resolvePaste(let policy):
            state.pasteConflicts = []
            _performPaste(policy)
        case .cancelPaste:
            state.pasteConflicts = []
        }
    }

    // MARK: - Paste

    /// Look before writing: a paste onto names that are already taken asks
    /// first, exactly as Explorer's does, and only then does any work.
    private func _paste() {
        guard let clip = state.clipboard, state.busy == nil else { return }
        state.operationError = nil
        let conflicts = FileSystem.conflicts(clip.paths, in: state.currentPath)
        if conflicts.isEmpty {
            _performPaste(.keepBoth)  // nothing in the way; the policy is moot
        } else {
            state.pasteConflicts = conflicts
        }
    }

    /// The copy or move itself, off the UI thread — a folder of a thousand
    /// files must not freeze the window, and the status bar says what is
    /// happening while it runs.
    private func _performPaste(_ policy: FileSystem.ConflictPolicy) {
        guard let clip = state.clipboard else { return }
        let destination = state.currentPath
        state.busy = clip.cut ? "Moving…" : "Copying…"
        Task.detached {
            var failure: String? = nil
            for path in clip.paths {
                let error = clip.cut
                    ? FileSystem.move(path, into: destination, policy: policy)
                    : FileSystem.copy(path, into: destination, policy: policy)
                if failure == nil { failure = error }
            }
            await MainActor.run { [self] in
                state.busy = nil
                // A cut is spent once pasted; a copy can be pasted again.
                if clip.cut { state.clipboard = nil }
                _loadDirectory(destination)
                state.operationError = failure
            }
        }
    }

    // MARK: - Event Handlers

    private func _loadDirectory(_ path: String) {
        if !FileSystem.isReadable(path) {
            state.errorMessage = "Permission denied: \(path)"
            state.entries = []
            state.allEntries = []
            return
        }
        state.errorMessage = nil
        state.currentPath = path
        state.allEntries = FileSystem.listDirectory(path, showHidden: state.showHidden)
        _applyFilterAndSort()
        state.selectedIndex = nil
    }

    private func _navigateTo(_ path: String) {
        // Truncate forward history
        if state.historyIndex < state.history.count - 1 {
            state.history = Array(state.history[0...state.historyIndex])
        }
        state.history.append(path)
        state.historyIndex = state.history.count - 1
        _loadDirectory(path)
    }

    private func _goBack() {
        guard state.canGoBack else { return }
        state.historyIndex -= 1
        _loadDirectory(state.history[state.historyIndex])
    }

    private func _goForward() {
        guard state.canGoForward else { return }
        state.historyIndex += 1
        _loadDirectory(state.history[state.historyIndex])
    }

    private func _goUp() {
        guard state.canGoUp else { return }
        _navigateTo(FileSystem.parentPath(state.currentPath))
    }

    private func _doubleClick(_ index: Int) {
        guard index < state.entries.count else { return }
        let entry = state.entries[index]
        if entry.isDirectory {
            _navigateTo(entry.path)
        }
    }

    private func _toggleSort(_ column: SortColumn) {
        if state.sortColumn == column {
            state.sortOrder = state.sortOrder.toggled
        } else {
            state.sortColumn = column
            state.sortOrder = .ascending
        }
        _applyFilterAndSort()
    }

    private func _applyFilterAndSort() {
        var result = state.allEntries
        if !state.searchQuery.isEmpty {
            result = FileSystem.filter(result, query: state.searchQuery)
        }
        state.entries = FileSystem.sort(result, by: state.sortColumn, order: state.sortOrder)
    }

    private func _createFolder(_ name: String) {
        let _ = FileSystem.createDirectory(at: state.currentPath, name: name)
        _loadDirectory(state.currentPath)
    }

    private func _rename(path: String, newName: String) {
        let _ = FileSystem.rename(at: path, to: newName)
        _loadDirectory(state.currentPath)
    }

    private func _delete(path: String) {
        let _ = FileSystem.delete(at: path)
        state.selectedIndex = nil
        _loadDirectory(state.currentPath)
    }
}
