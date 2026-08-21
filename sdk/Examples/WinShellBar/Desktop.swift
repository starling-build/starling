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
// V1 boundaries, each a deliberate not-yet: no rubber-band selection, no
// OLE drag in/out (the Files machinery is there to lift), no inline rename,
// no keyboard navigation, one monitor, and the wallpaper is read once at
// start (no change watch).

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

    private(set) var items: [DesktopItem] = []
    private(set) var selection: Set<String> = []
    private(set) var wallpaperTexture: Int?
    /// A drag in flight: which item, and where its top-left currently floats
    /// (logical points). The tile follows the pointer; everything else
    /// stands still.
    private(set) var drag: (path: String, x: Double, y: Double)?

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
        var raw: [String: [Int]] = [:]
        for item in items { raw[item.entry.path] = [item.col, item.row] }
        let dir = (Self.storePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(
            withJSONObject: raw, options: [.sortedKeys]) {
            FileManager.default.createFile(atPath: Self.storePath,
                                           contents: data)
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        let size = Win32WindowedHost.host?.clientSize
            ?? (width: 1920.0, height: 1080.0)
        cols = max(1, Int((size.width - kDeskMarginX * 2) / kDeskCellW))
        rows = max(1, Int((size.height - kDeskMarginY * 2) / kDeskCellH))
        icons.onTextureReady = { [weak self] in self?.poke() }
        refresh()
        loadWallpaper()
    }

    func refresh() {
        let entries = Self.desktopEntries()
        items = Self.placed(entries, stored: Self.loadPositions(),
                            cols: cols, rows: rows)
        selection = selection.filter { path in
            items.contains { $0.entry.path == path }
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

    private func loadWallpaper() {
        guard let host = Win32WindowedHost.host,
              let size = host.clientSize else { return }
        let scale = ShellScreen.monitor?.scale ?? 1.0
        let w = Int(size.width * scale)
        let h = Int(size.height * scale)
        DispatchQueue.global(qos: .userInitiated).async {
            guard let bitmap = Win32Icon.wallpaper(width: w, height: h)
            else { return }
            DispatchQueue.main.async { [weak self] in
                // registerPixels takes ownership either way; a nil id just
                // leaves the tinted fallback ground.
                self?.wallpaperTexture =
                    Win32WindowedHost.host?.registerPixels(bitmap)
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
    }

    func clearSelection() { selection = [] }

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

    /// Drops the dragged icon on the nearest cell; taken cells and
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
        guard col >= 0, col < cols, row >= 0, row < rows,
              !items.contains(where: {
                  $0.col == col && $0.row == row
                      && $0.entry.path != current.path
              }) else { return }
        items[index].col = col
        items[index].row = row
        savePositions()
    }
}

// MARK: - The widget

final class StarlingDesktop: StatefulWidget {
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

    override func initState() {
        super.initState()
        bloc.start()
        // This window owns its process, so the process-wide hook is ours.
        PlatformDispatcher.instance.onKeyData = { [weak self] keyData in
            if FocusManager.instance.dispatchKeyData(keyData) { return true }
            return self?.handleKey(keyData) ?? false
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
                    }
                },
                onPointerUp: { [weak self] _ in
                    guard let self else { return }
                    self.dragCandidate = nil
                    self.bloc.endDrag()
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
        switch keyData.logical {
        case 0x1_0000_001B:  // Escape
            guard menu.isOpen else { return false }
            menu.dismiss()
            return true
        case 0x1_0000_0805:  // F5
            bloc.refresh()
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
                            Text(displayLabel(entry),
                                 style: TextStyle(
                                    color: Color(0xFFFFFFFF),
                                    fontSize: 12,
                                    // The label sits on an arbitrary
                                    // photograph; the shadow is what makes
                                    // white text survive a white wallpaper,
                                    // exactly as Windows draws its own.
                                    shadows: [
                                        Shadow(color: Color(0xB3000000),
                                               offset: Offset(0, 1),
                                               blurRadius: 3),
                                    ]),
                                 textAlign: .center,
                                 overflow: .ellipsis,
                                 maxLines: 2)
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
