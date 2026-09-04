// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The desktop surface: wallpaper and the icon grid, at the bottom of the
// z-order -- wave 2 of the shell-replacement plan, the plane explorer's
// Progman owns until the Shell= endgame. The window shape (full monitor,
// bottom-pinned, focusable-but-never-raised) is flwin32_host_set_desktop;
// this file is what draws on it and what the clicks mean.
//
// DELIBERATELY GATED: while explorer runs, Progman is under every window and
// fighting it for wallpaper clicks is a losing game (the plan's own words).
// main.swift refuses --desktop when explorer is present unless
// STARLING_DESKTOP_TRIAL=1, which is the dev-box arrangement; the real proof
// is the VM with explorer killed.
//
// The idioms are the file explorer's, deliberately: a root Listener with
// arithmetic hit tests (widget-level input does not arrive reliably in
// these surfaces), an @Observable bloc the widget watches, IconCache
// textures behind instant fallback glyphs, and ShellMenuModel's popup menus
// -- the desktop's right-click NEEDS the popup surfaces, because there is no
// parent window to draw a menu inside.
//
// V1 boundaries, each a deliberate not-yet: no OLE drag OUT (dragging an
// icon stays a window-internal reposition; the drop target below takes
// drags IN), one monitor, and the wallpaper is read once at start (no
// change watch). Rubber band, inline rename, keyboard navigation and the
// clipboard chords all landed in the second pass, lifted from the file
// explorer's machinery.

#if os(Windows)
import CupertinoIcons
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import FlutterWin32Bridge
import Foundation
import Observation

/// Windows' medium-icon desktop grid, in logical points: a 48pt icon over
/// up to two label lines, cells filled column-major -- top to bottom, left
/// to right -- from the top-left margin.
let kDeskCellW = 90.0
let kDeskCellH = 104.0
let kDeskIcon = 48.0
let kDeskMarginX = 14.0
let kDeskMarginY = 10.0
let kDeskLabelH = 34.0

struct DesktopItem {
    var entry: Win32FileEntry
    var col: Int
    var row: Int
}

@Observable
final class DesktopBloc {

    /// Set (before `start()`) when the desktop runs as a surface view of the
    /// one-app shell: the engine view id, whose WINDOW is what this bloc
    /// measures against. Nil in the process-per-surface world, where the
    /// process host's window IS the desktop.
    var surfaceId: Int?

    /// The desktop window's client size in logical points — the surface's
    /// when there is one, the process host's otherwise.
    var windowSize: (width: Double, height: Double)? {
        if let sid = surfaceId { return Win32Surfaces.clientSize(sid) }
        return Win32WindowedHost.host?.clientSize
    }

    private(set) var items: [DesktopItem] = []
    private(set) var selection: Set<String> = []
    private(set) var wallpaperTexture: Int?
    /// A drag in flight: which item, and where its top-left currently floats
    /// (logical points). The tile follows the pointer; everything else
    /// stands still.
    private(set) var drag: (path: String, x: Double, y: Double)?
    /// The item whose label is an edit field right now, by path.
    private(set) var renaming: String?
    /// The folder icon lit under an OLE drag, by path.
    private(set) var dropHover: String?
    /// Where the arrow keys walk from: the last item selected singly.
    private(set) var anchor: String?

    @ObservationIgnored let icons = IconCache()
    /// Grid dimensions, derived from the window once it exists.
    @ObservationIgnored private(set) var cols = 1
    @ObservationIgnored private(set) var rows = 1
    @ObservationIgnored private var started = false

    // MARK: - The listing

    /// The user's Desktop and the Public one, merged -- what explorer's grid
    /// is a view of. (The full namespace Desktop would add This PC and the
    /// bin as virtual items; a follow-up once the grid earns them.)
    /// The user's Desktop folder — the directory a background click means.
    static var userDesktopPath: String {
        var buf = [CChar](repeating: 0, count: 1024)
        let n = buf.withUnsafeMutableBufferPointer {
            flwin32_known_path(1, $0.baseAddress, 1024)
        }
        return n > 0 ? String(cString: buf) : ""
    }

    static func desktopEntries() -> [Win32FileEntry] {
        var dirs: [String] = []
        let user = userDesktopPath
        if !user.isEmpty { dirs.append(user) }
        let publicDir = (ProcessInfo.processInfo.environment["PUBLIC"]
                         ?? "C:\\Users\\Public") + "\\Desktop"
        if FileManager.default.fileExists(atPath: publicDir) {
            dirs.append(publicDir)
        }
        var entries: [Win32FileEntry] = []
        var seen = Set<String>()
        for dir in dirs {
            for entry in Win32Files.list(dir) {
                // desktop.ini configures the folder; it is not ON the desktop.
                if entry.name.lowercased() == "desktop.ini" { continue }
                if seen.insert(entry.name.lowercased()).inserted {
                    entries.append(entry)
                }
            }
        }
        // Explorer's default arrangement: folders first, then files, by name.
        return entries.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name)
                == .orderedAscending
        }
    }

    /// Column-major default positions for entries the store has no cell for,
    /// skipping cells the store already spoke for. Shared with
    /// --print-desktop, which is why it is a static taking everything in.
    static func placed(_ entries: [Win32FileEntry],
                       stored: [String: (Int, Int)],
                       cols: Int, rows: Int) -> [DesktopItem] {
        var taken = Set<Int>()
        for (_, cell) in stored { taken.insert(cell.0 * rows + cell.1) }
        var next = 0
        var items: [DesktopItem] = []
        for entry in entries {
            if let cell = stored[entry.path] {
                items.append(DesktopItem(entry: entry, col: cell.0,
                                         row: cell.1))
                continue
            }
            while taken.contains(next) { next += 1 }
            let col = rows > 0 ? next / rows : 0
            let row = rows > 0 ? next % rows : 0
            taken.insert(next)
            items.append(DesktopItem(entry: entry, col: col, row: row))
        }
        return items
    }

    // MARK: - The position store

    /// Ours, not the shell's: explorer keeps icon positions in a bag only
    /// its own listview reads back. One JSON of path -> [col, row].
    static var storePath: String {
        let base = ProcessInfo.processInfo.environment["LOCALAPPDATA"]
            ?? NSTemporaryDirectory()
        return base + "\\Starling\\desktop-icons.json"
    }

    static func loadPositions() -> [String: (Int, Int)] {
        guard let data = FileManager.default.contents(atPath: storePath),
              let raw = try? JSONSerialization.jsonObject(with: data)
                as? [String: [Int]] else { return [:] }
        var out: [String: (Int, Int)] = [:]
        for (path, cell) in raw where cell.count == 2 {
            out[path] = (cell[0], cell[1])
        }
        return out
    }

    private func savePositions() {
        var raw: [String: (Int, Int)] = [:]
        for item in items { raw[item.entry.path] = (item.col, item.row) }
        Self.save(positions: raw)
    }

    static func save(positions: [String: (Int, Int)]) {
        var raw: [String: [Int]] = [:]
        for (path, cell) in positions { raw[path] = [cell.0, cell.1] }
        let dir = (storePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(
            withJSONObject: raw, options: [.sortedKeys]) {
            FileManager.default.createFile(atPath: storePath, contents: data)
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        let size = windowSize ?? (width: 1920.0, height: 1080.0)
        cols = max(1, Int((size.width - kDeskMarginX * 2) / kDeskCellW))
        rows = max(1, Int((size.height - kDeskMarginY * 2) / kDeskCellH))
        icons.onTextureReady = { [weak self] in self?.poke() }
        refresh()
        loadWallpaper()
    }

    func refresh() {
        let entries = Self.desktopEntries()
        // Prune stored cells whose file is gone -- placed() reserves every
        // stored cell, so a stale key is a hole no icon can ever fill.
        var stored = Self.loadPositions()
        let live = Set(entries.map(\.path))
        let pruned = stored.filter { live.contains($0.key) }
        if pruned.count != stored.count {
            stored = pruned
            Self.save(positions: stored)
        }
        items = Self.placed(entries, stored: stored,
                            cols: cols, rows: rows)
        selection = selection.filter { path in
            items.contains { $0.entry.path == path }
        }
        if let open = renaming,
           !items.contains(where: { $0.entry.path == open }) {
            renaming = nil
        }
        warmIcons()
    }

    /// A no-op write that re-runs the observing builds -- how a texture
    /// arriving off-thread reaches the tiles that drew fallback glyphs.
    private func poke() { selection = selection }

    private func warmIcons() {
        for item in items {
            let entry = item.entry
            // Per PATH, not per type: a desktop is shortcuts, and every .lnk
            // has its own face (arrow badge included -- Explorer's desktop
            // wears them too, so rasterize(path:) is the right form).
            icons.ensure(key: Self.iconKey(entry), path: entry.path,
                         size: Int(kDeskIcon))
            if let thumb = FilesBloc.thumbKey(entry, side: Int(kDeskIcon)) {
                icons.ensure(thumbnailKey: thumb, path: entry.path,
                             size: Int(kDeskIcon))
            }
        }
    }

    static func iconKey(_ entry: Win32FileEntry) -> String {
        "\u{1}desk:\(entry.path)"
    }

    func texture(for entry: Win32FileEntry) -> Int? {
        if let thumb = FilesBloc.thumbKey(entry, side: Int(kDeskIcon)),
           let tex = icons.texture(thumb) {
            return tex
        }
        return icons.texture(Self.iconKey(entry))
    }

    /// Says what it did, on stderr. A desktop that came up BLACK on a
    /// Hyper-V VM (2026-09-04) was invisible to every log because each exit
    /// from this path was silent: no window size yet, a decode the shell's
    /// image factory refused, a texture that never registered. Unbuffered,
    /// because the supervisor's log is a pipe and print() would sit in a
    /// buffer until the process died.
    private func noteWallpaper(_ line: String) {
        // The non-throwing write, the one the frame log uses: the throwing
        // `write(contentsOf:)` fails silently on a pipe here. The pid,
        // because every shell process writes to the same session log.
        FileHandle.standardError.write(Data(
            ("[Desktop \(ProcessInfo.processInfo.processIdentifier)] wallpaper: "
             + line + "\n").utf8))
    }

    private func loadWallpaper(attempt: Int = 0) {
        guard let size = windowSize else {
            // The surface's window has no client size yet. Not a failure:
            // ask again shortly, a bounded number of times, rather than
            // leave the session without a wallpaper.
            if attempt < 40 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    [weak self] in self?.loadWallpaper(attempt: attempt + 1)
                }
            } else {
                noteWallpaper("no window size after \(attempt) tries; giving up")
            }
            return
        }
        let scale = ShellScreen.monitor?.scale ?? 1.0
        let w = Int(size.width * scale)
        let h = Int(size.height * scale)
        let t0 = DispatchTime.now().uptimeNanoseconds
        DispatchQueue.global(qos: .userInitiated).async {
            let bitmap = Win32Icon.wallpaper(width: w, height: h)
            let ms = (DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let bitmap else {
                    // The shell's image factory can refuse while explorer's
                    // own machinery is still coming up beside us at logon;
                    // a second try a moment later is cheap. Bounded.
                    if attempt < 10 {
                        self.noteWallpaper(
                            "decode \(w)x\(h) FAILED after \(ms) ms; retry \(attempt + 1)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            [weak self] in self?.loadWallpaper(attempt: attempt + 1)
                        }
                    } else {
                        self.noteWallpaper(
                            "decode \(w)x\(h) FAILED after \(ms) ms; giving up after \(attempt) retries")
                    }
                    return
                }
                // registerPixels takes ownership either way; a nil id just
                // leaves the tinted fallback ground.
                let tex = Win32WindowedHost.host?.registerPixels(bitmap)
                self.wallpaperTexture = tex
                self.noteWallpaper(
                    "decode \(w)x\(h) ok in \(ms) ms; texture \(tex.map { String($0) } ?? "nil")")
            }
        }
    }

    // MARK: - Geometry

    func cellOrigin(col: Int, row: Int) -> (x: Double, y: Double) {
        (kDeskMarginX + Double(col) * kDeskCellW,
         kDeskMarginY + Double(row) * kDeskCellH)
    }

    /// The item whose CELL contains the point -- the arithmetic mirror of
    /// the drawing, the same bargain every surface here strikes.
    func item(at x: Double, _ y: Double) -> DesktopItem? {
        let col = Int((x - kDeskMarginX) / kDeskCellW)
        let row = Int((y - kDeskMarginY) / kDeskCellH)
        guard x >= kDeskMarginX, y >= kDeskMarginY, col >= 0, row >= 0
        else { return nil }
        return items.first { $0.col == col && $0.row == row }
    }

    // MARK: - Interaction

    func select(_ path: String, toggle: Bool) {
        if toggle {
            if selection.contains(path) {
                selection.remove(path)
            } else {
                selection.insert(path)
            }
        } else {
            selection = [path]
        }
        anchor = path
    }

    func clearSelection() { selection = [] }

    /// The rubber band's live set -- wholesale, like the listing's
    /// bandSelect: the covered cells plus whatever a Ctrl-drag started over.
    func bandSelect(_ paths: Set<String>) { selection = paths }

    func selectAll() { selection = Set(items.map(\.entry.path)) }

    /// The anchor's item, which is what Enter opens and F2 renames.
    var anchorItem: DesktopItem? {
        guard let path = anchor ?? selection.first else { return nil }
        return items.first { $0.entry.path == path }
    }

    /// One arrow-key step: the nearest item strictly in the direction,
    /// preferring the same column (or row) -- how Explorer's desktop walks
    /// a grid with holes in it. Nothing selected starts at the first cell.
    func step(dCol: Int, dRow: Int) {
        guard let current = anchorItem else {
            if let first = items.min(by: {
                ($0.col, $0.row) < ($1.col, $1.row)
            }) { select(first.entry.path, toggle: false) }
            return
        }
        var best: DesktopItem?
        var bestScore = (Int.max, Int.max)
        for item in items {
            let dc = item.col - current.col
            let dr = item.row - current.row
            let forward = dCol != 0 ? dc * dCol : dr * dRow
            guard forward > 0 else { continue }
            let lateral = dCol != 0 ? abs(dr) : abs(dc)
            if (lateral, forward) < bestScore {
                bestScore = (lateral, forward)
                best = item
            }
        }
        if let best { select(best.entry.path, toggle: false) }
    }

    // MARK: - File operations

    /// The window the shell's dialogs parent to, same rule as FilesBloc's.
    static var ownerWindow: UInt64 { Win32WindowedHost.host?.windowHandle ?? 0 }

    /// The selection in grid order, for the clipboard.
    private var selectedPaths: [String] {
        items.filter { selection.contains($0.entry.path) }.map(\.entry.path)
    }

    func clipSelection(cut: Bool) {
        let paths = selectedPaths
        guard !paths.isEmpty else { return }
        Win32FileOps.clipMany(paths, cut: cut)
    }

    func pasteInto(_ directory: String) {
        guard Win32FileOps.clipboardHasFiles() else { return }
        Win32FileOps.paste(into: directory, owner: Self.ownerWindow) {
            [weak self] ok, records in
            if ok { FilesBloc.pushUndo(records) }
            self?.refresh()
        }
    }

    func beginRename(_ entry: Win32FileEntry) {
        selection = [entry.path]
        anchor = entry.path
        renaming = entry.path
    }

    func cancelRename() { renaming = nil }

    func commitRename(_ newName: String) {
        guard let path = renaming else { return }
        renaming = nil
        // The old name is a no-op, not an error -- Enter on an untouched
        // field is how half of all renames end.
        let oldName = (path as NSString).lastPathComponent
        guard !newName.isEmpty, newName != oldName else { return }
        let cell = items.first { $0.entry.path == path }
            .map { ($0.col, $0.row) }
        Win32FileOps.rename(path, to: newName, owner: Self.ownerWindow) {
            [weak self] ok, records in
            guard let self else { return }
            if ok {
                FilesBloc.pushUndo(records)
                // The name the SHELL settled on, not the one asked for --
                // undoing the asked-for name deletes the wrong file, and
                // reselecting it selects nothing.
                let renamed = records.first?.dst
                    ?? Win32Files.join(
                        (path as NSString).deletingLastPathComponent, newName)
                self.selection = [renamed]
                self.anchor = renamed
                if let cell {
                    // The icon keeps its cell under its new name.
                    var stored = Self.loadPositions()
                    stored.removeValue(forKey: path)
                    stored[renamed] = cell
                    Self.save(positions: stored)
                }
            }
            self.refresh()
        }
    }

    func setDropHover(_ path: String?) {
        guard dropHover != path else { return }
        dropHover = path
    }

    /// Files an OLE drop just landed on the desktop folder take the cells
    /// under the drop point -- written straight into the store, so the
    /// refresh right behind this picks them up.
    func place(_ paths: [String], nearX x: Double, y: Double) {
        guard !paths.isEmpty else { return }
        var stored = Self.loadPositions()
        var taken = Set<Int>()
        for (_, cell) in stored { taken.insert(cell.0 * rows + cell.1) }
        for item in items where stored[item.entry.path] == nil {
            taken.insert(item.col * rows + item.row)
        }
        let col = min(max(Int((x - kDeskMarginX) / kDeskCellW), 0), cols - 1)
        let row = min(max(Int((y - kDeskMarginY) / kDeskCellH), 0), rows - 1)
        var next = col * rows + row
        for path in paths {
            while next < cols * rows && taken.contains(next) { next += 1 }
            guard next < cols * rows else { break }
            taken.insert(next)
            stored[path] = (next / rows, next % rows)
        }
        Self.save(positions: stored)
    }

    func open(_ entry: Win32FileEntry) {
        // The shell, which is the only thing that knows how to open a .lnk.
        _ = Win32AppCatalog.open(entry.path)
    }

    func beginDrag(_ path: String, x: Double, y: Double) {
        drag = (path, x, y)
    }

    func moveDrag(x: Double, y: Double) {
        guard let current = drag else { return }
        drag = (current.path, x, y)
    }

    /// Drops the dragged icon on the nearest cell; a FOLDER already in that
    /// cell takes the file (Explorer's gesture); any other taken cell and
    /// off-grid drops put it back where it came from.
    func endDrag() {
        guard let current = drag else { return }
        drag = nil
        guard let index = items.firstIndex(where: {
            $0.entry.path == current.path
        }) else { return }
        let col = Int(((current.x + kDeskCellW / 2) - kDeskMarginX)
                      / kDeskCellW)
        let row = Int(((current.y + kDeskCellH / 2) - kDeskMarginY)
                      / kDeskCellH)
        if let occupant = items.first(where: {
            $0.col == col && $0.row == row && $0.entry.path != current.path
        }) {
            if occupant.entry.isDirectory {
                Win32FileOps.transfer([current.path],
                                      into: occupant.entry.path, move: true,
                                      owner: Self.ownerWindow) {
                    [weak self] ok, records in
                    if ok { FilesBloc.pushUndo(records) }
                    self?.refresh()
                }
            }
            return
        }
        guard col >= 0, col < cols, row >= 0, row < rows else { return }
        items[index].col = col
        items[index].row = row
        savePositions()
    }
}

// MARK: - The widget

final class StarlingDesktop: StatefulWidget {
    /// Non-nil when the desktop runs as a SURFACE VIEW inside the one-app
    /// shell (`--oneshell`): the engine view id. The tree then measures
    /// itself against ITS window (the monitor), not the process host's (the
    /// dock's panel — a grid computed against that is one row tall).
    let surfaceId: Int?
    init(surfaceId: Int? = nil) {
        self.surfaceId = surfaceId
        super.init()
    }
    override func createState() -> State<StatefulWidget> {
        StarlingDesktopState()
    }
}

final class StarlingDesktopState: State<StatefulWidget> {
    private let bloc = DesktopBloc()
    private let menu = ShellMenuModel()

    /// Double-click by hand: the DRM-era trap holds here too (registering
    /// onDoubleTap kills tap), and there is no GestureDetector in this tree
    /// anyway -- the root Listener is the input.
    @ObservationIgnored private var lastClick: (path: String, at: Date)?
    /// A press on an icon that may become a drag; promoted past 4pt of
    /// travel, forgotten on release.
    @ObservationIgnored private var dragCandidate:
        (path: String, x: Double, y: Double, originX: Double,
         originY: Double)?
    /// Tracked from the key stream, the same bargain the file explorer
    /// strikes: KeyData carries no modifier mask.
    @ObservationIgnored private var ctrlDown = false
    // The rubber band, the listing's own split: the rectangle is its own
    // model and overlay so chasing the pointer rebuilds one box, and the
    // desktop only hears about it when the covered SET changes.
    private let band = BandModel()
    @ObservationIgnored private var bandOrigin: (x: Double, y: Double)?
    @ObservationIgnored private var bandBase: Set<String> = []
    @ObservationIgnored private var bandActive = false
    @ObservationIgnored private var bandLast: Set<String> = []
    /// The inline rename's editor -- created when a rename begins,
    /// prefilled once, reused across rebuilds (a fresh controller per build
    /// would reset the text under the user's fingers).
    @ObservationIgnored private var renameController: TextEditingController?
    @ObservationIgnored private var renamePath: String?
    /// What an OLE drag over the window is carrying, held from enter to
    /// leave/drop for the effect arithmetic.
    @ObservationIgnored private var dropPaths: [String] = []

    override func initState() {
        super.initState()
        bloc.surfaceId = (widget as! StarlingDesktop).surfaceId
        FileHandle.standardError.write(Data(
            ("[Desktop \(ProcessInfo.processInfo.processIdentifier)] mounted, surface "
             + "\(bloc.surfaceId.map { String($0) } ?? "host") size "
             + "\(bloc.windowSize.map { "\($0.width)x\($0.height)" } ?? "unknown")\n").utf8))
        bloc.start()
        // THROUGH THE ROUTER, never straight onto the dispatcher: that slot
        // holds one handler, and the file explorer in this same process has
        // shortcuts too. Assigning it here used to take the keyboard off
        // whichever of the two started first. See ShellKeys.
        ShellKeys.register(window: {
            guard let sid = (self.widget as! StarlingDesktop).surfaceId else {
                // Not a surface: the desktop is the host window's own view.
                return Win32WindowedHost.host?.windowHandle ?? 0
            }
            return Win32Surfaces.windowHandle(sid)
        }) { [weak self] keyData in
            self?.handleKey(keyData) ?? false
        }
        menu.target = { [weak self] x, y in
            guard let self else { return nil }
            if let item = self.bloc.item(at: x, y) {
                return .item(item.entry)
            }
            // Anywhere on the surface is the DESKTOP FOLDER's background --
            // New, Sort, Display settings, Personalize all live there.
            return .background
        }
        menu.afterVerb = { [weak self] in self?.bloc.refresh() }
        // The menu's other Files couplings, redirected at this surface: a
        // background click means the Desktop folder, and Open goes through
        // the shell -- there is no listing here to activate into.
        menu.backgroundDirectory = { DesktopBloc.userDesktopPath }
        menu.activate = { [weak self] entry in self?.bloc.open(entry) }
        menu.openWith = { entry in
            // Blocks on the shell's dialog -- background thread only.
            Task.detached { _ = Win32Files.openWith(entry.path) }
        }
        // The pill row's two non-shell cells, which otherwise poke the
        // dormant filesBloc and quietly do nothing here.
        menu.pasteInto = { [weak self] directory in
            self?.bloc.pasteInto(directory)
        }
        menu.beginRename = { [weak self] entry in
            self?.bloc.beginRename(entry)
        }
        // The desktop takes drops: files dragged from Explorer, the file
        // window or any OLE source land in the Desktop folder -- at the
        // cell they were dropped on -- or in the folder icon under the
        // pointer, drawn lit. Closures in before registration, so the
        // first drag is never refused.
        Win32DropTarget.onEnter = { [weak self] paths, x, y, keys in
            guard let self else { return 0 }
            self.dropPaths = paths
            return self.dropEffect(x, y, keys)
        }
        Win32DropTarget.onOver = { [weak self] x, y, keys in
            self?.dropEffect(x, y, keys) ?? 0
        }
        Win32DropTarget.onLeave = { [weak self] in
            self?.dropPaths = []
            self?.bloc.setDropHover(nil)
        }
        Win32DropTarget.onDrop = { [weak self] paths, x, y, move in
            self?.dropPaths = []
            self?.dropFinish(paths, x, y, move)
        }
        DispatchQueue.main.async { [weak self] in
            // The desktop's OWN window: as a surface view the process host
            // is the dock's panel, and a drop target registered there would
            // catch drags onto the dock instead of the desktop.
            let handle: UInt64
            if let sid = self?.bloc.surfaceId {
                handle = Win32Surfaces.windowHandle(sid)
            } else {
                handle = Win32WindowedHost.host?.windowHandle ?? 0
            }
            if handle != 0 { Win32DropTarget.register(window: handle) }
        }
    }

    // MARK: - Drops in

    /// Where a drop at this point would land: the folder icon under the
    /// pointer, or the Desktop folder itself. A non-folder icon takes
    /// nothing (Explorer shows deny there too -- dropping ON a file is not
    /// a gesture this v1 honours).
    private func dropResolve(_ x: Double, _ y: Double) -> String? {
        if let item = bloc.item(at: x, y) {
            return item.entry.isDirectory ? item.entry.path : nil
        }
        return DesktopBloc.userDesktopPath
    }

    private func dropEffect(_ x: Double, _ y: Double,
                            _ keys: UInt32) -> Int32 {
        guard let target = dropResolve(x, y), !dropPaths.isEmpty else {
            bloc.setDropHover(nil)
            return 0
        }
        let lowered = target.lowercased()
        let parent = (dropPaths[0] as NSString).deletingLastPathComponent
        if parent.lowercased() == lowered
            || dropPaths.contains(where: { $0.lowercased() == lowered }) {
            bloc.setDropHover(nil)
            return 0
        }
        bloc.setDropHover(
            target == DesktopBloc.userDesktopPath ? nil : target)
        if keys & 0x0008 != 0 { return 1 }  // MK_CONTROL
        if keys & 0x0004 != 0 { return 2 }  // MK_SHIFT
        return dropPaths[0].prefix(2).lowercased()
            == target.prefix(2).lowercased() ? 2 : 1
    }

    private func dropFinish(_ paths: [String], _ x: Double, _ y: Double,
                            _ move: Bool) {
        bloc.setDropHover(nil)
        guard !paths.isEmpty, let target = dropResolve(x, y) else { return }
        Win32FileOps.transfer(paths, into: target, move: move,
                              owner: DesktopBloc.ownerWindow) {
            [weak self] ok, records in
            guard let self else { return }
            if ok {
                FilesBloc.pushUndo(records)
                if target == DesktopBloc.userDesktopPath {
                    // The arrivals take the cells under the drop point,
                    // as Explorer places them.
                    self.bloc.place(records.map(\.dst), nearX: x, y: y)
                }
            }
            self.bloc.refresh()
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        withObservationTracking {
            _buildContent()
        } onChange: { [weak self] in
            guard let self, self.mounted else { return }
            self.setState {}
        }
    }

    private func _buildContent() -> Widget {
        Directionality(
            textDirection: .ltr,
            child: Listener(
                onPointerDown: { [weak self] e in
                    self?.pointerDown(e)
                },
                onPointerMove: { [weak self] e in
                    guard let self else { return }
                    if let candidate = self.dragCandidate {
                        let dx = e.position.dx - candidate.x
                        let dy = e.position.dy - candidate.y
                        if self.bloc.drag != nil {
                            self.bloc.moveDrag(x: candidate.originX + dx,
                                               y: candidate.originY + dy)
                        } else if abs(dx) > 4 || abs(dy) > 4 {
                            self.bloc.beginDrag(candidate.path,
                                                x: candidate.originX + dx,
                                                y: candidate.originY + dy)
                        }
                        return
                    }
                    self.bandMoved(e)
                },
                onPointerUp: { [weak self] _ in
                    guard let self else { return }
                    self.dragCandidate = nil
                    self.bloc.endDrag()
                    self.bandEnded()
                },
                onPointerHover: { [weak self] e in
                    guard let self, self.menu.isOpen else { return }
                    self.menu.hovered(e.position.dx, e.position.dy)
                },
                child: Stack(alignment: Alignment.topLeft) {
                    backdrop()
                    for item in bloc.items {
                        tile(item)
                    }
                    BandOverlay(model: band)
                    StarlingContextMenu(model: menu)
                }))
    }

    private func pointerDown(_ e: PointerDownEvent) {
        let x = e.position.dx
        let y = e.position.dy
        if menu.isOpen {
            menu.press(x, y, buttons: e.buttons)
            return
        }
        let hit = bloc.item(at: x, y)
        if let open = bloc.renaming {
            if let hit, hit.entry.path == open {
                // The click is the field's -- caret placement, not
                // selection or a drag.
                return
            }
            // Click-away commits, Explorer's rule; Escape cancels through
            // the field's own focus loss (the field consumes the key).
            commitRenameField()
        }
        if e.buttons == 2 {
            // Explorer's rule, the same as the listing's: a right-click
            // outside the selection moves it; inside, the selection stands.
            if let hit, !bloc.selection.contains(hit.entry.path) {
                bloc.select(hit.entry.path, toggle: false)
            }
            if hit == nil { bloc.clearSelection() }
            menu.open(at: x, y)
            return
        }
        guard e.buttons == 1 else { return }
        guard let hit else {
            if !ctrlHeld() { bloc.clearSelection() }
            lastClick = nil
            // A background press may become a rubber band -- remembered
            // with the selection it started over, because a Ctrl-drag adds
            // to that rather than replacing it.
            bandOrigin = (x, y)
            bandBase = ctrlHeld() ? bloc.selection : []
            return
        }
        let path = hit.entry.path
        // Double-click first, so the second click does not merely reselect.
        if let last = lastClick, last.path == path,
           Date().timeIntervalSince(last.at) < 0.45 {
            lastClick = nil
            bloc.open(hit.entry)
            return
        }
        lastClick = (path, Date())
        bloc.select(path, toggle: ctrlHeld())
        let origin = bloc.cellOrigin(col: hit.col, row: hit.row)
        dragCandidate = (path, x, y, origin.x, origin.y)
    }

    private func ctrlHeld() -> Bool { ctrlDown }

    // MARK: - The rubber band

    /// Every pointer move with the left button down, once a background
    /// press armed it. Same 4px threshold as the listing's; the covered
    /// set is a per-item cell intersect, because desktop cells sit at
    /// arbitrary stored positions rather than in list order.
    private func bandMoved(_ e: PointerMoveEvent) {
        guard let origin = bandOrigin, e.buttons == 1, !menu.isOpen
        else { return }
        if !bandActive {
            let dx = e.position.dx - origin.x
            let dy = e.position.dy - origin.y
            guard dx * dx + dy * dy > 16 else { return }
            bandActive = true
            bandLast = bandBase
        }
        let size = bloc.windowSize ?? (width: 1920.0, height: 1080.0)
        let x = min(max(e.position.dx, 0), size.width)
        let y = min(max(e.position.dy, 0), size.height)
        band.rect = (min(origin.x, x), min(origin.y, y),
                     abs(x - origin.x), abs(y - origin.y))
        let left = min(origin.x, x), right = max(origin.x, x)
        let top = min(origin.y, y), bottom = max(origin.y, y)
        var covered = bandBase
        for item in bloc.items {
            let o = bloc.cellOrigin(col: item.col, row: item.row)
            if o.x < right, o.x + kDeskCellW > left,
               o.y < bottom, o.y + kDeskCellH > top {
                covered.insert(item.entry.path)
            }
        }
        if covered != bandLast {
            bandLast = covered
            bloc.bandSelect(covered)
        }
    }

    private func bandEnded() {
        bandOrigin = nil
        guard bandActive else { return }
        bandActive = false
        band.rect = nil
    }

    // MARK: - The inline rename

    private func commitRenameField() {
        let text = renameController?.text ?? ""
        renameController = nil
        renamePath = nil
        bloc.commitRename(text.trimmingCharacters(in: .whitespaces))
    }

    /// The tile label's edit field, where the label was. Same controller
    /// bargain as the listing's: created when this rename begins, reused
    /// across rebuilds until it ends.
    private func renameField(_ entry: Win32FileEntry) -> Widget {
        if renamePath != entry.path || renameController == nil {
            renamePath = entry.path
            // The BASENAME arrives selected, Explorer's gesture: typing
            // replaces the name and leaves the extension standing.
            let stem = (entry.name as NSString).deletingPathExtension
            renameController = TextEditingController(value: TextEditingValue(
                text: entry.name,
                selection: TextSelection(baseOffset: 0,
                                         extentOffset: stem.count)))
        }
        return SizedBox(height: 22) {
            MacosTextField(
                controller: renameController!,
                onSubmitted: { text in
                    self.renameController = nil
                    self.renamePath = nil
                    self.bloc.commitRename(
                        text.trimmingCharacters(in: .whitespaces))
                },
                style: TextStyle(color: Win11.text, fontSize: 12),
                padding: EdgeInsets(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                    color: Win11.fieldFill,
                    border: Border.all(color: Win11.accent, width: 1),
                    borderRadius: BorderRadius.circular(3)),
                autofocus: true,
                onFocusChanged: { focused in
                    // The field consumes Escape internally (unfocus), so no
                    // shortcut handler ever sees it while the field is
                    // focused -- the focus node's own signal is the only
                    // honest cancel. A commit already cleared `renaming`,
                    // so the guard keeps this from double-firing.
                    guard !focused, self.bloc.renaming == entry.path
                    else { return }
                    self.renameController = nil
                    self.renamePath = nil
                    self.bloc.cancelRename()
                })
        }
    }

    /// The desktop's keys, the explorer's subset that makes sense with no
    /// listing: F5 re-reads, Delete recycles the selection, Escape closes
    /// an open menu. Logical ids are the engine's Flutter ids, same table
    /// as Files.handleShortcut.
    private func handleKey(_ keyData: KeyData) -> Bool {
        let down = keyData.type == .down || keyData.type == .repeat
        switch keyData.logical {
        case 0x2_0000_0100, 0x2_0000_0101: ctrlDown = down; return false
        default: break
        }
        guard keyData.type == .down else { return false }

        // Letter chords match on the PHYSICAL id, like the listing's: with
        // Ctrl held this embedder delivers the letter with logical == 0.
        // Not while a rename is in flight -- a chord the field does not
        // consume falls through here, and Ctrl+A selecting every icon
        // under an open edit is what that looks like.
        if ctrlDown && bloc.renaming == nil {
            switch keyData.physical {
            case 0x0007_0004:  // A
                bloc.selectAll()
                return true
            case 0x0007_0006:  // C
                bloc.clipSelection(cut: false)
                return true
            case 0x0007_001B:  // X
                bloc.clipSelection(cut: true)
                return true
            case 0x0007_0019:  // V
                bloc.pasteInto(DesktopBloc.userDesktopPath)
                return true
            case 0x0007_001D:  // Z
                // The same per-process journal the explorer feeds; an
                // inline rename in flight keeps the key, its edit is not a
                // file operation yet.
                guard bloc.renaming == nil else { return false }
                return FilesBloc.performUndo { [weak self] _ in
                    self?.bloc.refresh()
                }
            default:
                break
            }
        }

        switch keyData.logical {
        case 0x1_0000_001B:  // Escape
            guard menu.isOpen else { return false }
            menu.dismiss()
            return true
        case 0x1_0000_000D:  // Enter
            guard let item = bloc.anchorItem else { return false }
            bloc.open(item.entry)
            return true
        case 0x1_0000_0802:  // F2
            guard let item = bloc.anchorItem else { return false }
            bloc.beginRename(item.entry)
            return true
        case 0x1_0000_0805:  // F5
            bloc.refresh()
            return true
        case 0x1_0000_0301:  // Down
            bloc.step(dCol: 0, dRow: 1)
            return true
        case 0x1_0000_0304:  // Up
            bloc.step(dCol: 0, dRow: -1)
            return true
        case 0x1_0000_0303:  // Right
            bloc.step(dCol: 1, dRow: 0)
            return true
        case 0x1_0000_0302:  // Left
            bloc.step(dCol: -1, dRow: 0)
            return true
        case 0x1_0000_007F:  // Delete
            let paths = Array(bloc.selection)
            guard !paths.isEmpty else { return false }
            Win32FileOps.deleteMany(
                paths, owner: Win32WindowedHost.host?.windowHandle ?? 0
            ) { [weak self] ok, records in
                // The same journal the explorer feeds, so Ctrl+Z THERE can
                // undo a desktop delete -- one undo stack per process is the
                // design, and this process has no Ctrl+Z of its own yet.
                if ok { FilesBloc.pushUndo(records) }
                self?.bloc.refresh()
            }
            return true
        default:
            return false
        }
    }

    // MARK: - Drawing

    private func backdrop() -> Widget {
        Positioned(left: 0, top: 0, right: 0, bottom: 0) {
            if let tex = bloc.wallpaperTexture {
                TextureWidget(textureId: tex)
            } else {
                // Windows' own fallback when there is no image: the accent-
                // adjacent dark blue of a fresh install.
                ColoredBox(color: Color(0xFF0C3B5E)) {
                    SizedBox(width: 0, height: 0)
                }
            }
        }
    }

    private func tile(_ item: DesktopItem) -> Widget {
        let entry = item.entry
        let selected = bloc.selection.contains(entry.path)
            || bloc.dropHover == entry.path
        let dragged = bloc.drag?.path == entry.path
        let origin = dragged
            ? (x: bloc.drag!.x, y: bloc.drag!.y)
            : bloc.cellOrigin(col: item.col, row: item.row)
        return Positioned(left: origin.x, top: origin.y) {
            SizedBox(width: kDeskCellW, height: kDeskCellH) {
                DecoratedBox(
                    decoration: BoxDecoration(
                        color: selected ? Color(0x4D4A90D9)
                                        : Color(0x00000000),
                        border: selected
                            ? Border.all(color: Color(0x804A90D9), width: 1)
                            : nil,
                        borderRadius: BorderRadius.circular(4)),
                    child: Column(mainAxisSize: .min,
                                  crossAxisAlignment: .center) {
                        SizedBox(height: 6)
                        SizedBox(width: kDeskIcon, height: kDeskIcon) {
                            if let tex = bloc.texture(for: entry) {
                                TextureWidget(textureId: tex)
                            } else {
                                MacosIcon(
                                    icon: entry.isDirectory
                                        ? CupertinoIcons.folder_fill
                                        : CupertinoIcons.doc_fill,
                                    color: entry.isDirectory
                                        ? Color(0xFFF8D775)
                                        : Color(0xFFE8E8E8),
                                    size: kDeskIcon - 6)
                            }
                        }
                        SizedBox(height: 3)
                        SizedBox(width: kDeskCellW - 6,
                                 height: kDeskLabelH) {
                            if bloc.renaming == entry.path {
                                renameField(entry)
                            } else {
                                Text(displayLabel(entry),
                                     style: TextStyle(
                                        color: Color(0xFFFFFFFF),
                                        fontSize: 12,
                                        // The label sits on an arbitrary
                                        // photograph; the shadow is what
                                        // makes white text survive a white
                                        // wallpaper, exactly as Windows
                                        // draws its own.
                                        shadows: [
                                            Shadow(color: Color(0xB3000000),
                                                   offset: Offset(0, 1),
                                                   blurRadius: 3),
                                        ]),
                                     textAlign: .center,
                                     overflow: .ellipsis,
                                     maxLines: 2)
                            }
                        }
                    })
            }
        }
    }

    /// The shell's display name -- "hide extensions for known types" is a
    /// per-machine setting the desktop must honour like the listing does.
    private func displayLabel(_ entry: Win32FileEntry) -> String {
        entry.isDirectory ? entry.name
                          : Win32Files.displayName(for: entry.path)
    }
}
#endif
