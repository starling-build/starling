// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The file explorer.
//
// An ordinary window, like Settings, and for the same reasons: it is an app,
// and a normal Column/Row is the input path that works in this framework.
//
// SHAPED LIKE WINDOWS 11'S EXPLORER, deliberately: the tab strip, the command
// bar, the breadcrumb-and-search row, the four Details columns, the status
// bar. Someone who knows Explorer should not have to learn anything.
//
// The file operations — new folder, cut, copy, paste, rename, delete — run
// through the shell's own IFileOperation (flwin32_fileops.c), which is what
// brings the recycle bin, the conflict dialogs and Explorer's undo stack
// along. Rename is inline — the row's name becomes a text field, exactly
// Explorer's F2 — and New creates the folder already in that field, exactly
// Explorer's gesture.

#if os(Windows)
import CupertinoIcons
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import FlutterWin32Bridge
import Foundation
import Observation

let kFilesSidebar = 220.0
let kFilesRow = 28.0
/// Explorer's three stacked bars, and the column-header strip under them.
/// Everything above the list, which is what the row arithmetic measures from.
/// The titlebar strip. Taller than the old in-window tab row because it IS
/// the titlebar now: the caption belongs to the client (setCustomTitlebar),
/// the way Explorer's own tabs live in its caption.
let kFilesTabStrip = 44.0
/// One caption button (minimize / maximize / close), Windows' own width.
let kCaptionButtonW = 46.0
/// The tab's fixed geometry, shared by the drawing and the strip hit test.
let kTabX = 8.0
let kTabW = 220.0
let kFilesCommandBar = 44.0
let kFilesNavBar = 44.0
let kFilesHeaderRow = 26.0
let kFilesToolbar = kFilesTabStrip + kFilesCommandBar + kFilesNavBar + kFilesHeaderRow
/// The window the explorer opens at, in logical points -- named because the
/// tree needs it too: a menu that has to flip up when it would run off the
/// bottom has to know where the bottom is. The live size is read from the
/// window (it is resizable); this is the fallback and the size main.swift
/// creates it at.
let kFilesWidth = 1040.0
let kFilesHeight = 680.0

let kFilesStatusBar = 34.0

/// The Details columns, at Explorer's proportions. Name takes what is left.
let kFilesColModified = 170.0
let kFilesColType = 130.0
let kFilesColSize = 90.0

/// Windows 11, sampled from Explorer rather than invented, so the two
/// sitting side by side do not disagree about what either theme is. Dark was
/// sampled from dark Explorer; light from light Explorer over the same
/// folder (menu #FCFCFC, list #FFFFFF, chrome mica #F3F3F3).
enum Win11 {
    /// Which palette, set ONCE at startup (main.swift) from the system's
    /// AppsUseLightTheme -- the apps theme Explorer's own chrome follows.
    /// Not reactive: Windows apps restyle on WM_SETTINGCHANGE, which nothing
    /// here listens for yet, so a theme flipped mid-session shows up on the
    /// next launch.
    static var light = false

    static var windowBg: Color { light ? Color(0xFFF3F3F3) : Color(0xFF202020) }
    static var surface: Color { light ? Color(0xFFFFFFFF) : Color(0xFF272727) }
    static var navPane: Color { light ? Color(0xFFF3F3F3) : Color(0xFF202020) }
    static var listBg: Color { light ? Color(0xFFFFFFFF) : Color(0xFF272727) }
    static var stroke: Color { light ? Color(0xFFE5E5E5) : Color(0xFF383838) }
    static var text: Color { light ? Color(0xFF1B1B1B) : Color(0xFFFFFFFF) }
    static var textDim: Color { light ? Color(0xFF5F5F5F) : Color(0xFFC5C5C5) }
    static var textFaint: Color { light ? Color(0xFF8F8F8F) : Color(0xFF8A8A8A) }
    static var disabled: Color { light ? Color(0xFFA6A6A6) : Color(0xFF5A5A5A) }
    static var accent: Color { light ? Color(0xFF005FB8) : Color(0xFF4CC2FF) }
    static var selection: Color { light ? Color(0x330078D4) : Color(0x332F9CF4) }
    /// The rubber band: accent-tinted fill, stronger accent edge -- sampled
    /// from Explorer's own drag rectangle rather than invented.
    static var bandFill: Color { light ? Color(0x2E0078D4) : Color(0x2E2F9CF4) }
    static var bandStroke: Color { light ? Color(0x990078D4) : Color(0x992F9CF4) }
    static var hoverFill: Color { light ? Color(0x0A000000) : Color(0x14FFFFFF) }
    static var fieldFill: Color { light ? Color(0xFFFFFFFF) : Color(0xFF2D2D2D) }
    /// The context menu, sampled from Explorer's own: a near-opaque slab with
    /// a hairline around it, not the app's window colours.
    /// The acrylic TINT now, not the whole surface: the panel puts a
    /// backdrop blur underneath it (see FilesMenu.panel), so the alpha is
    /// what lets the frosted content through.
    static var menuBg: Color { light ? Color(0xE0FCFCFC) : Color(0xE02C2C2C) }
    static var menuBorder: Color { light ? Color(0xFFD4D4D4) : Color(0xFF454545) }
    static var menuHover: Color { light ? Color(0xFFF0F0F0) : Color(0xFF383838) }
    static var menuSep: Color { light ? Color(0xFFE4E4E4) : Color(0xFF3D3D3D) }
    /// A menu's drop shadow: a light theme's panel casts a softer one --
    /// dark Explorer's is visibly heavier than light Explorer's.
    static var menuShadow: Color { light ? Color(0x2E000000) : Color(0x66000000) }
}

final class StarlingFiles: StatefulWidget {
    override func createState() -> State<StatefulWidget> { StarlingFilesState() }
}

final class StarlingFilesState: State<StatefulWidget> {
    private let bloc = filesBloc

    /// Double-click, by hand.
    ///
    /// `onDoubleTap` is not usable here — registering it kills the plain tap
    /// as well on at least one embedder, and this framework's gesture arena
    /// is not something to rely on. So: a tap selects, and a second tap on
    /// the same row within the interval opens. Windows' own behaviour, out of
    /// two ordinary taps.
    private var lastTapPath: String?
    private var lastTapAt = Date.distantPast

    /// The list's scroll position, so a right-click can work out which row is
    /// under the pointer. Without it the arithmetic is only right until the
    /// first scroll — and then silently wrong, which is worse.
    private let scroll = ScrollController()

    // The rubber band's bookkeeping. `band` is the drawn rectangle (its own
    // model, so dragging rebuilds the overlay and not this window); the rest
    // is this handler's: where the press landed, what was already selected
    // when it did (Ctrl-dragging ADDS, as Explorer's does), and the last set
    // dispatched so the bloc only hears real changes, not every pixel.
    private let band = BandModel()
    private var bandOrigin: (x: Double, y: Double)?
    private var bandBase: Set<String> = []
    private var bandActive = false
    private var bandLast: Set<String> = []

    // An OLE drag in flight over this window: what it carries, and which
    // folder row it is over (drawn selected, as Explorer lights its target).
    private var dropPaths: [String] = []
    private var dropHover: String?

    // A row press that may become a drag OUT: armed on the press, fired
    // when it moves past a click's worth, cleared on release either way.
    private var dragCandidate: (path: String, x: Double, y: Double)?

    /// The search box's text. Owned by the widget, not the bloc: the bloc
    /// holds the filter it produced, which is a different thing from what is
    /// currently in the field.
    private let search = TextEditingController()

    /// The inline rename's editor, created when a rename begins and dropped
    /// when it ends. Held here rather than made per-build so the text
    /// survives the rebuilds that happen while the user types.
    private var renameController: TextEditingController?
    private var renamePath: String?

    /// Modifier state for the window shortcuts, tracked from the key stream
    /// -- KeyData carries no modifier mask, the same bargain TerminalView
    /// strikes. Ids are the engine's Flutter logical ids; this window only
    /// exists on the Win32 embedder, which sends nothing else.
    private var ctrlDown = false
    private var shiftDown = false
    private var altDown = false

    /// Explorer's keyboard: Enter opens, Alt+Enter is properties, F2
    /// renames, Delete recycles, Ctrl+C/X/V are the clipboard, and
    /// Ctrl+Shift+C is Copy as path. These existing is what makes the
    /// accelerator column in the context menu honest rather than decorative.
    private func handleShortcut(_ keyData: KeyData) -> Bool {
        let down = keyData.type == .down || keyData.type == .repeat
        switch keyData.logical {
        case 0x2_0000_0100, 0x2_0000_0101: ctrlDown = down; return false
        case 0x2_0000_0102, 0x2_0000_0103: shiftDown = down; return false
        case 0x2_0000_0104, 0x2_0000_0105: altDown = down; return false
        default: break
        }
        guard keyData.type == .down else { return false }

        // Letter chords match on the PHYSICAL (HID) id: with Ctrl held this
        // embedder delivers the letter with logical == 0 and no character,
        // so the logical id has nothing to say. F2 and the rest arrive with
        // proper logical ids and are matched below.
        if ctrlDown {
            switch keyData.physical {
            case 0x0007_0006: // C
                if shiftDown {
                    // Quoted, one per line -- exactly as Explorer's Copy as
                    // path writes it, for one path or many.
                    let paths = selectionPaths
                    guard !paths.isEmpty else { return false }
                    Clipboard.setData(ClipboardData(
                        text: paths.map { "\"\($0)\"" }.joined(separator: "\r\n")))
                    return true
                }
                if bloc.state.selection.count > 1 {
                    bloc.add(.clipSelection(cut: false))
                    return true
                }
                guard let entry = selectedEntry else { return false }
                bloc.add(.clip(entry, cut: false))
                return true
            case 0x0007_001B: // X
                if bloc.state.selection.count > 1 {
                    bloc.add(.clipSelection(cut: true))
                    return true
                }
                guard let entry = selectedEntry else { return false }
                bloc.add(.clip(entry, cut: true))
                return true
            case 0x0007_0004: // A
                bloc.add(.selectAll)
                return true
            case 0x0007_0019: // V
                bloc.add(.paste(into: bloc.state.directory))
                return true
            default:
                break
            }
        }

        switch keyData.logical {
        case 0x1_0000_001B: // Escape: the menu first, then a rename in flight
            if menu.isOpen {
                menu.dismiss()
                return true
            }
            if bloc.state.renaming != nil {
                renameController = nil
                renamePath = nil
                bloc.add(.cancelRename)
                return true
            }
            return false
        case 0x1_0000_000D: // Enter
            guard let entry = selectedEntry else { return false }
            if altDown {
                bloc.add(.showProperties(entry))
            } else {
                bloc.add(.activate(entry))
            }
            return true
        case 0x1_0000_0802: // F2
            guard let entry = selectedEntry else { return false }
            bloc.add(.beginRename(entry))
            return true
        case 0x1_0000_007F: // Delete
            if bloc.state.selection.count > 1 {
                bloc.add(.deleteSelection)
                return true
            }
            guard let entry = selectedEntry else { return false }
            bloc.add(.deleteEntry(entry))
            return true
        default:
            return false
        }
    }

    /// The context menu, which is a surface of its own from here on.
    ///
    /// It holds its own state and draws through its own widget, so moving the
    /// highlight from one row to the next rebuilds two panels rather than
    /// this window -- measured at 3.9ms of CPU per row change when a hover
    /// went through `setState` here, against a listing that can be ten
    /// thousand rows long.
    private let menu = ShellMenuModel()

    override func initState() {
        super.initState()
        CupertinoIcons.registerFont()
        // The system's own icon font: this surface imitates Explorer, and
        // Explorer's glyphs come from Segoe Fluent Icons, not Cupertino.
        FluentIcons.registerFont()
        // The caption becomes ours to draw: tabs in the titlebar, exactly
        // Explorer's shape. The strip's hit test (stripPress) owes the
        // window drag, minimize, maximize and close in exchange.
        //
        // DEFERRED, not called here: the style change fires a synchronous
        // WM_SIZE, the embedder answers it with a frame, and that frame
        // re-enters the adapter while THIS build is mid-flight -- measured
        // as a crash on the adapter's own force-unwraps. After the current
        // frame settles, the resize is just a resize.
        DispatchQueue.main.async {
            Win32WindowedHost.host?.setCustomTitlebar()
        }
        // The window takes drops: files dragged in from Explorer (or any
        // OLE source) land in the open folder, or in the folder row under
        // the pointer. The closures go in before registration so the first
        // drag is never refused; registration is deferred with the titlebar
        // because it needs the window handle.
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
            self?.setDropHover(nil)
        }
        Win32DropTarget.onDrop = { [weak self] paths, x, y, move in
            self?.dropPaths = []
            self?.dropFinish(paths, x, y, move)
        }
        DispatchQueue.main.async {
            if let handle = Win32WindowedHost.host?.windowHandle {
                Win32DropTarget.register(window: handle)
            }
        }
        // The listing is the only thing the menu cannot work out for itself.
        menu.target = { [weak self] x, y in self?.targetAt(x, y) }
        bloc.add(.start)
        // Focused text fields (the search box, an inline rename) get every
        // key first; the shortcuts see only what no field claimed. This
        // window owns its process, so taking the process-wide hook is not
        // stepping on anything.
        PlatformDispatcher.instance.onKeyData = { [weak self] keyData in
            if FocusManager.instance.dispatchKeyData(keyData) { return true }
            return self?.handleShortcut(keyData) ?? false
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
                onPointerDown: { e in
                    self.lastDown = (e.position.dx, e.position.dy)
                    // 2 is the secondary button, and a PRESS rather than a
                    // release — the same choice the dock makes, for the same
                    // reason: the press is what arrives reliably, and every
                    // desktop opens its menus on it anyway.
                    if self.menu.isOpen {
                        self.menu.press(e.position.dx, e.position.dy,
                                        buttons: e.buttons)
                        return
                    }
                    // The titlebar strip is ours to run: buttons, tab, and
                    // the drag handle. Left button only — a right-click on
                    // a real titlebar shows the system menu, which is not
                    // built, and swallowing it quietly beats faking it.
                    if e.buttons == 1 && e.position.dy < kFilesTabStrip {
                        self.stripPress(e.position.dx, e.position.dy)
                        return
                    }
                    if e.buttons == 2 {
                        // Explorer's rule: a right-click on a row OUTSIDE
                        // the selection moves the selection to it; inside,
                        // the selection stands and the menu speaks for it.
                        if case .item(let entry)? =
                            self.targetAt(e.position.dx, e.position.dy),
                           !self.bloc.state.selection.contains(entry.path) {
                            self.bloc.add(.select(entry.path))
                        }
                        self.menu.open(at: e.position.dx, e.position.dy)
                        return
                    }
                    // A plain click on the listing's background deselects,
                    // as Explorer's does. Rows re-select through their own
                    // GestureDetector after this fires. Any background press
                    // may also become a rubber band, so it is remembered --
                    // with the selection it started over, because a
                    // Ctrl-drag adds to that rather than replacing it.
                    if e.buttons == 1,
                       let target = self.targetAt(e.position.dx, e.position.dy) {
                        switch target {
                        case .background:
                            if !self.ctrlDown && !self.shiftDown {
                                self.bloc.add(.clearSelection)
                            }
                            self.bandOrigin = (e.position.dx, e.position.dy)
                            self.bandBase = self.ctrlDown
                                ? self.bloc.state.selection : []
                        case .item(let entry):
                            // May become a drag out -- see dragMoved.
                            self.dragCandidate =
                                (entry.path, e.position.dx, e.position.dy)
                        }
                    }
                },
                onPointerMove: { e in
                    if self.dragMoved(e) { return }
                    self.bandMoved(e)
                },
                onPointerUp: { _ in
                    self.dragCandidate = nil
                    self.bandEnded()
                },
                // The highlight, and what opens a submenu — Windows opens
                // them on hover and so does this. Only while a menu is down:
                // this fires for every pointer move over the whole window.
                onPointerHover: { e in
                    guard self.menu.isOpen else { return }
                    self.menu.hovered(e.position.dx, e.position.dy)
                },
                child: ColoredBox(color: Win11.windowBg) {
                Stack(alignment: Alignment.topLeft) {
                    Column(crossAxisAlignment: .stretch) {
                    tabStrip()
                    // Explorer's order, full width: the address row, then
                    // the command bar, and only THEN the sidebar/listing
                    // split -- the sidebar starts below the bars, and so
                    // does ours now.
                    navigationBar()
                    commandBar()
                    Expanded {
                    Row(crossAxisAlignment: .stretch) {
                        sidebar()
                        Expanded {
                            Column(crossAxisAlignment: .stretch) {
                                columnHeaders()
                                Expanded {
                                    ColoredBox(color: Win11.listBg) { listing() }
                                }
                            }
                        }
                    }
                    }
                    statusBar()
                    }
                    // Always mounted, drawing nothing when there is no menu:
                    // a Stack that GAINS a child does not reliably composite
                    // it, and a widget that came and went would take the
                    // model's observation with it. Filling the stack rather
                    // than being placed by it, because where the panels go is
                    // the menu's business -- this window does not rebuild
                    // when they move.
                    Positioned(left: 0, top: 0, right: 0, bottom: 0) {
                        BandOverlay(model: band)
                    }
                    Positioned(left: 0, top: 0, right: 0, bottom: 0) {
                        StarlingContextMenu(model: menu)
                    }
                }
            }))
    }

    // MARK: - What is under a right-click
    //
    // The one part of the context menu the LISTING owns, and the reason the
    // model asks rather than works it out: which rows exist and how far they
    // have been scrolled is this surface's business and nobody else's.
    // Everything past this point -- the rows, the geometry, the session, the
    // drawing -- is FilesMenu.swift.

    /// The row under a point, accounting for how far the list is scrolled.
    /// nil above the listing (the toolbars, the sidebar) so no menu opens
    /// there, and `.background` in the empty space below the last row, which
    /// is what gets the folder's own menu.
    private func targetAt(_ x: Double, _ y: Double) -> MenuTarget? {
        guard x >= kFilesSidebar, y >= kFilesToolbar else { return nil }
        // `offset` TRAPS on a controller with no attached position, and an
        // EMPTY folder is exactly that: the listing draws its "This folder
        // is empty" label instead of the scrollable, so nothing ever
        // attaches. The first right-click on an empty folder's background
        // killed the app here -- hasClients is the guard Dart code uses on
        // the same contract, not an optimization.
        let offset = scroll.hasClients ? scroll.offset : 0
        let index = Int((y - kFilesToolbar + offset) / kFilesRow)
        guard index >= 0, index < bloc.state.visible.count else { return .background }
        return .item(bloc.state.visible[index])
    }

    // MARK: - The rubber band

    /// Every pointer move with the left button down, once a background press
    /// armed it. The 4px threshold is what separates a click (clear, handled
    /// on the press) from a drag; past it, the rectangle is drawn clamped to
    /// the listing and the rows it spans become the selection. No autoscroll
    /// at the edges yet -- the band selects what is on screen.
    private func bandMoved(_ e: PointerMoveEvent) {
        guard let origin = bandOrigin, e.buttons == 1, !menu.isOpen else { return }
        if !bandActive {
            let dx = e.position.dx - origin.x
            let dy = e.position.dy - origin.y
            guard dx * dx + dy * dy > 16 else { return }
            bandActive = true
            bandLast = bandBase
        }
        let size = Win32WindowedHost.host?.clientSize
            ?? (width: kFilesWidth, height: kFilesHeight)
        let x = min(max(e.position.dx, kFilesSidebar), size.width)
        let y = min(max(e.position.dy, kFilesToolbar),
                    size.height - kFilesStatusBar)
        band.rect = (min(origin.x, x), min(origin.y, y),
                     abs(x - origin.x), abs(y - origin.y))

        // The rows the rectangle's vertical span intersects. Same arithmetic
        // as targetAt, over a range instead of a point.
        let offset = scroll.hasClients ? scroll.offset : 0
        let count = bloc.state.visible.count
        let lo = max(Int((min(origin.y, y) - kFilesToolbar + offset) / kFilesRow), 0)
        let hi = min(Int((max(origin.y, y) - kFilesToolbar + offset) / kFilesRow),
                     count - 1)
        var covered = bandBase
        if lo <= hi {
            for i in lo...hi { covered.insert(bloc.state.visible[i].path) }
        }
        if covered != bandLast {
            bandLast = covered
            bloc.add(.bandSelect(Array(covered)))
        }
    }

    private func bandEnded() {
        bandOrigin = nil
        guard bandActive else { return }
        bandActive = false
        band.rect = nil
    }

    /// A pressed row moving past the click threshold becomes an OLE drag
    /// of the selection (or of just that row, when it was not in the
    /// selection -- Explorer's rule, same as right-click). Returns true
    /// while a candidate is armed so the band never sees these moves.
    private func dragMoved(_ e: PointerMoveEvent) -> Bool {
        guard let candidate = dragCandidate, e.buttons == 1 else { return false }
        let dx = e.position.dx - candidate.x
        let dy = e.position.dy - candidate.y
        guard dx * dx + dy * dy > 16 else { return true }
        dragCandidate = nil
        if !bloc.state.selection.contains(candidate.path) {
            bloc.add(.select(candidate.path))
        }
        let paths = selectionPaths
        guard !paths.isEmpty else { return true }
        // DoDragDrop runs a modal pump; entering it from the middle of this
        // pointer dispatch would re-enter the adapter. One hop later the
        // dispatch has unwound and the button is still down, which is all
        // the drag loop needs.
        DispatchQueue.main.async { [weak self] in
            Win32DropTarget.beginDrag(paths)
            // Whatever the target did (including Explorer's optimized move,
            // which reports none), the listing may be stale now.
            self?.bloc.add(.refresh)
        }
        return true
    }

    // MARK: - Drops

    /// Where a drop at this point would land: the folder row under the
    /// pointer, else the open directory. nil where nothing takes a drop
    /// (the sidebar and the bars -- honest until the sidebar learns to).
    private func dropResolve(_ x: Double, _ y: Double) -> String? {
        guard x >= kFilesSidebar, y >= kFilesToolbar else { return nil }
        if case .item(let entry)? = targetAt(x, y), entry.isDirectory {
            return entry.path
        }
        return bloc.state.directory
    }

    /// The effect for a drag at this point, and the target highlight as a
    /// side effect. Explorer's rules: Ctrl forces a copy, Shift a move, and
    /// the default is a move within a volume, a copy across -- with a drop
    /// back into the files' own folder refused outright.
    private func dropEffect(_ x: Double, _ y: Double, _ keys: UInt32) -> Int32 {
        guard let target = dropResolve(x, y), !dropPaths.isEmpty else {
            setDropHover(nil)
            return 0
        }
        let lowered = target.lowercased()
        let parent = (dropPaths[0] as NSString).deletingLastPathComponent
        if parent.lowercased() == lowered
            || dropPaths.contains(where: { $0.lowercased() == lowered }) {
            setDropHover(nil)
            return 0
        }
        setDropHover(target == bloc.state.directory ? nil : target)
        if keys & 0x0008 != 0 { return 1 }  // MK_CONTROL
        if keys & 0x0004 != 0 { return 2 }  // MK_SHIFT
        return dropPaths[0].prefix(2).lowercased() == target.prefix(2).lowercased()
            ? 2 : 1
    }

    private func setDropHover(_ path: String?) {
        guard dropHover != path else { return }
        setState { dropHover = path }
    }

    private func dropFinish(_ paths: [String], _ x: Double, _ y: Double,
                            _ move: Bool) {
        setDropHover(nil)
        guard !paths.isEmpty, let target = dropResolve(x, y) else { return }
        Win32FileOps.transfer(paths, into: target, move: move,
                              owner: FilesBloc.ownerWindow) { [weak self] ok in
            if ok { self?.bloc.add(.refresh) }
        }
    }

    // MARK: - Sidebar

    /// Each known folder's glyph and tint, approximating the coloured icons
    /// Explorer's sidebar draws -- a uniform column of yellow folders was
    /// the single biggest visual difference from native. Ordered as Explorer
    /// pins them: Desktop, Downloads, Documents, Pictures, Music, Videos.
    private static let placeLooks: [String: (glyph: IconData, tint: Color)] = [
        // Home's house is the warm one, as Windows paints it.
        "Home": (FluentIcons.home, Color(0xFFCB6E3C)),
        "Desktop": (FluentIcons.desktop, Color(0xFF4E80C9)),
        "Downloads": (FluentIcons.download, Color(0xFF3F9E49)),
        "Documents": (FluentIcons.document, Color(0xFF5E7CA8)),
        "Pictures": (FluentIcons.pictures, Color(0xFF8A5BB8)),
        "Music": (FluentIcons.music, Color(0xFFC94E7E)),
        "Videos": (FluentIcons.video, Color(0xFFC97A3F)),
    ]
    private static let pinOrder = ["Desktop", "Downloads", "Documents",
                                   "Pictures", "Music", "Videos"]

    private func sidebar() -> Widget {
        let byName = Dictionary(uniqueKeysWithValues:
            bloc.state.places.map { ($0.name, $0) })
        return SizedBox(width: kFilesSidebar) {
            ColoredBox(color: Win11.navPane) {
                Padding(padding: EdgeInsets(left: 8, top: 10, right: 8, bottom: 8)) {
                    Column(crossAxisAlignment: .stretch) {
                        // Home first, alone -- Explorer's own shape: no
                        // section headings, the rows are the structure.
                        if let home = byName["Home"] { placeRow(home) }
                        sidebarRule()
                        // The pinned folders, in Explorer's order, each
                        // carrying its pin.
                        for name in Self.pinOrder {
                            if let place = byName[name] {
                                placeRow(place, pinned: true)
                            }
                        }
                        sidebarRule()
                        // This PC leads its drives, computer glyph and all.
                        // Not expandable yet: the drives are simply always
                        // shown, which for one drive is the same picture.
                        placeRow(Win32Place(name: "This PC", path: ""),
                                 glyph: FluentIcons.thisPC)
                        for drive in bloc.state.drives {
                            Padding(padding: EdgeInsets(left: 14, top: 0,
                                                        right: 0, bottom: 0)) {
                                placeRow(Win32Place(
                                    name: Win32Files.displayName(for: drive.path),
                                    path: drive.path),
                                    glyph: FluentIcons.drive)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The hairline between sidebar groups, inset the way Explorer's are.
    private func sidebarRule() -> Widget {
        Padding(padding: EdgeInsets(left: 10, top: 8, right: 10, bottom: 8)) {
            SizedBox(height: 1) { ColoredBox(color: Win11.stroke) { SizedBox(height: 1) } }
        }
    }

    private func sidebarHeading(_ text: String) -> Widget {
        Padding(padding: EdgeInsets(left: 10, top: 0, right: 10, bottom: 6)) {
            Text(text, style: TextStyle(color: Win11.textFaint, fontSize: 11,
                                        fontWeight: .w600))
        }
    }

    private func placeRow(_ place: Win32Place, pinned: Bool = false,
                          glyph: IconData? = nil) -> Widget {
        let selected = !place.path.isEmpty
            && bloc.state.directory == place.path
        let look = Self.placeLooks[place.name]
        let icon = glyph ?? look?.glyph ?? FluentIcons.folderFill
        let tint = glyph != nil ? Win11.textDim
            : (look?.tint ?? (Win11.light ? Color(0xFF4E80C9)
                                          : Color(0xFF7FA9DE)))
        return GestureDetector(
            onTap: {
                guard !place.path.isEmpty else { return }
                self.bloc.add(.open(place.path))
            },
            child: Padding(padding: EdgeInsets(left: 0, top: 1, right: 0, bottom: 1)) {
                ClipRRect(borderRadius: BorderRadius.circular(6)) {
                    Hover { hovered in
                    ColoredBox(color: selected ? Color(0x2E6FA8FF)
                               : (hovered && !place.path.isEmpty
                                  ? Win11.hoverFill : Color(0x00000000))) {
                        SizedBox(height: 30) {
                            Padding(padding: EdgeInsets(horizontal: 10, vertical: 0)) {
                                Row(crossAxisAlignment: .center, spacing: 9) {
                                    MacosIcon(icon: icon, color: tint, size: 14)
                                    Text(place.name,
                                         style: TextStyle(color: Win11.text,
                                                          fontSize: 13),
                                         maxLines: 1)
                                    if pinned {
                                        Expanded { SizedBox(height: 1) }
                                        MacosIcon(icon: FluentIcons.pin,
                                                  color: Win11.textFaint, size: 11)
                                    }
                                }
                            }
                        }
                    }
                    }
                }
            })
    }

    // MARK: - Toolbar

    // MARK: - Explorer's chrome
    //
    // Three stacked bars and a header strip, in Windows 11's order: tabs,
    // command bar, breadcrumb-and-search, columns.

    /// The tab strip. ONE tab, showing where we are -- tabs proper need a
    /// window that can hold several listings and this holds one, so a strip
    /// that pretended otherwise would be chrome that does nothing. The shape
    /// is Explorer's; the count is honest.
    /// The titlebar: the active tab, "+", and the caption buttons -- drawn
    /// by us because the caption is client area now. NO GestureDetectors
    /// here: every press in the strip goes through stripPress, hit-tested
    /// arithmetically from the root Listener, because a drag must reach
    /// beginDrag on the raw pointer-down and gestures do not give it up.
    private func tabStrip() -> Widget {
        SizedBox(height: kFilesTabStrip) {
            ColoredBox(color: Win11.windowBg) {
                Stack(alignment: Alignment.topLeft) {
                    // The active tab, seated on the strip's bottom edge with
                    // rounded shoulders, the way Explorer's tab sits.
                    Positioned(left: kTabX, top: 8, bottom: 0) {
                        SizedBox(width: kTabW) {
                            ClipRRect(borderRadius: BorderRadius.only(
                                topLeft: Radius(circular: 8),
                                topRight: Radius(circular: 8))) {
                                ColoredBox(color: Win11.surface) {
                                    Padding(padding: EdgeInsets(
                                        left: 12, top: 0, right: 8, bottom: 0)) {
                                        Row(crossAxisAlignment: .center, spacing: 8) {
                                            MacosIcon(icon: FluentIcons.folderFill,
                                                      color: Win11.textDim, size: 13)
                                            Expanded {
                                                Text(folderLabel(),
                                                     style: TextStyle(color: Win11.text,
                                                                      fontSize: 12),
                                                     overflow: .ellipsis, maxLines: 1)
                                            }
                                            MacosIcon(icon: FluentIcons.close,
                                                      color: Win11.textFaint, size: 10)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // "+", which opens a new window on this folder -- the
                    // nearest honest thing to a new tab until tabs are real.
                    Positioned(left: kTabX + kTabW + 8, top: 12) {
                        MacosIcon(icon: FluentIcons.add,
                                  color: Win11.textDim, size: 14)
                    }
                    // The caption trio, Windows' own widths, right-aligned.
                    Positioned(top: 0, right: 0, bottom: 0) {
                        Row(crossAxisAlignment: .stretch) {
                            captionButton(FluentIcons.chromeMinimize)
                            captionButton((Win32WindowedHost.host?.isMaximized ?? false)
                                          ? FluentIcons.chromeRestore
                                          : FluentIcons.chromeMaximize)
                            captionButton(FluentIcons.chromeClose, isClose: true)
                        }
                    }
                }
            }
        }
    }

    /// One of the caption trio. Close hovers RED with a white glyph --
    /// Windows' one non-negotiable hover -- and the others grey.
    private func captionButton(_ icon: IconData, isClose: Bool = false) -> Widget {
        Hover { hovered in
            ColoredBox(color: hovered
                       ? (isClose ? Color(0xFFC42B1C) : Win11.hoverFill)
                       : Color(0x00000000)) {
                SizedBox(width: kCaptionButtonW) {
                    Center {
                        MacosIcon(icon: icon,
                                  color: isClose && hovered
                                      ? Color(0xFFFFFFFF) : Win11.textDim,
                                  size: 12)
                    }
                }
            }
        }
    }

    /// When the last left press landed in the strip, for the double-click
    /// that maximizes -- detected by hand, the way the listing detects its
    /// own double-click (see the trap note on onDoubleTap).
    private var lastStripTapAt = Date.distantPast

    /// Where the last pointer-down landed, recorded by the root Listener. A
    /// GestureDetector's onTap carries no position, and the command bar's
    /// dropdowns need one to anchor their flyout under the button that was
    /// pressed. A plain var: recording it must not rebuild anything.
    private var lastDown = (x: 0.0, y: 0.0)

    /// A left press in the titlebar strip: caption buttons, the tab's close,
    /// "+", and everywhere else is the drag handle Windows expects a
    /// titlebar to be. Coordinates are logical, from the root Listener.
    private func stripPress(_ x: Double, _ y: Double) {
        guard let host = Win32WindowedHost.host else { return }
        let width = host.clientSize?.width ?? kFilesWidth
        let fromRight = width - x
        if fromRight <= kCaptionButtonW { host.closeWindow(); return }
        if fromRight <= kCaptionButtonW * 2 { host.toggleMaximize(); return }
        if fromRight <= kCaptionButtonW * 3 { host.minimize(); return }
        // The tab's own close. One tab, so it closes the window -- the same
        // thing Explorer does to its last tab.
        if x >= kTabX + kTabW - 30 && x < kTabX + kTabW && y >= 8 {
            host.closeWindow()
            return
        }
        // "+": a new window on this folder.
        if x >= kTabX + kTabW + 2 && x < kTabX + kTabW + 34 {
            openNewWindow()
            return
        }
        // The empty strip: a second press within the double-click window
        // maximizes; a first one is the drag Windows owns from here.
        let now = Date()
        if now.timeIntervalSince(lastStripTapAt) < 0.4 {
            lastStripTapAt = .distantPast
            host.toggleMaximize()
        } else {
            lastStripTapAt = now
            host.beginDrag()
        }
    }

    /// The command bar. Everything on it that needs IFileOperation is drawn
    /// disabled -- see this file's header.
    /// The selected row's entry, for the command bar's enablement and
    /// actions.
    private var selectedEntry: Win32FileEntry? {
        guard let path = bloc.state.selected else { return nil }
        return bloc.state.visible.first { $0.path == path }
    }

    /// The selection in VISIBLE order -- a Set has none, and Copy as path
    /// pasting rows in a different order than the screen shows them reads
    /// as a bug even when every path is right.
    private var selectionPaths: [String] {
        bloc.state.visible.map(\.path).filter(bloc.state.selection.contains)
    }

    /// The command bar's dropdowns, anchored under the pressed button --
    /// `lastDown` supplies the x a GestureDetector's tap cannot, and the
    /// panel is the context menu's own machinery in flyout mode.
    private var flyoutAnchorY: Double {
        kFilesTabStrip + kFilesNavBar + kFilesCommandBar - 4
    }

    private func openNewFlyout() {
        menu.openFlyout(at: lastDown.x - 24, flyoutAnchorY, rows: [
            MenuRow(title: "Folder", glyph: FluentIcons.folder,
                    action: { filesBloc.add(.newFolder) }),
            MenuRow(title: "Window", glyph: FluentIcons.openExternal,
                    action: { self.openNewWindow() }),
        ])
    }

    private func openSortFlyout() {
        func keyRow(_ title: String, _ key: FilesSortKey) -> MenuRow {
            MenuRow(title: title,
                    glyph: bloc.state.sortKey == key ? FluentIcons.check : nil,
                    action: { filesBloc.add(.sort(key)) })
        }
        menu.openFlyout(at: lastDown.x - 24, flyoutAnchorY, rows: [
            keyRow("Name", .name),
            keyRow("Date modified", .modified),
            keyRow("Type", .type),
            keyRow("Size", .size),
            MenuRow(isSeparator: true),
            MenuRow(title: "Ascending",
                    glyph: bloc.state.sortAscending ? FluentIcons.check : nil,
                    action: { filesBloc.add(.sortDirection(ascending: true)) }),
            MenuRow(title: "Descending",
                    glyph: bloc.state.sortAscending ? nil : FluentIcons.check,
                    action: { filesBloc.add(.sortDirection(ascending: false)) }),
        ])
    }

    private func openNewWindow() {
        let exe = ProcessInfo.processInfo.arguments[0]
        let dir = bloc.state.directory
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: exe)
            process.arguments = ["--files", dir]
            try? process.run()
        }
    }

    private func commandBar() -> Widget {
        SizedBox(height: kFilesCommandBar) {
            Padding(padding: EdgeInsets(left: 10, top: 0, right: 10, bottom: 0)) {
                Row(crossAxisAlignment: .center, spacing: 2) {
                    // Explorer's New, as a plain click: a folder, born into
                    // its rename field. (Explorer's is a dropdown with the
                    // ShellNew templates; the folder is the one everybody
                    // means.)
                    barButton(FluentIcons.add, "New", chevron: true,
                              enabled: true) {
                        self.openNewFlyout()
                    }
                    barSeparator()
                    // Explorer's own enablement: cut/copy/rename/delete need
                    // a selection, paste needs files on the clipboard. All
                    // five run through the shell (IFileOperation / the
                    // shell's data object) -- see FilesBloc and
                    // flwin32_fileops.c.
                    barIcon(FluentIcons.cut, enabled: selectedEntry != nil) {
                        if let entry = self.selectedEntry {
                            self.bloc.add(.clip(entry, cut: true))
                        }
                    }
                    barIcon(FluentIcons.copy, enabled: selectedEntry != nil) {
                        if let entry = self.selectedEntry {
                            self.bloc.add(.clip(entry, cut: false))
                        }
                    }
                    barIcon(FluentIcons.paste,
                            enabled: Win32FileOps.clipboardHasFiles()) {
                        self.bloc.add(.paste(into: self.bloc.state.directory))
                    }
                    barIcon(FluentIcons.rename, enabled: selectedEntry != nil) {
                        if let entry = self.selectedEntry {
                            self.bloc.add(.beginRename(entry))
                        }
                    }
                    // Share, through the shell's own verb -- the same
                    // windows.modernshare the menu's icon row invokes.
                    barIcon(FluentIcons.share,
                            enabled: selectedEntry?.isDirectory == false) {
                        if let entry = self.selectedEntry {
                            self.bloc.add(.share(entry))
                        }
                    }
                    barIcon(FluentIcons.delete, enabled: selectedEntry != nil) {
                        if let entry = self.selectedEntry {
                            self.bloc.add(.deleteEntry(entry))
                        }
                    }
                    barSeparator()
                    barButton(FluentIcons.sort, "Sort",
                              chevron: true, enabled: true) {
                        self.openSortFlyout()
                    }
                    barButton(FluentIcons.viewAll, "View",
                              chevron: true, enabled: false) {}
                    Expanded { SizedBox(height: 1) }
                    textButton("Open in Explorer") { self.bloc.add(.openInExplorer) }
                }
            }
        }
    }

    /// Back, forward, up, refresh, the breadcrumb, and search.
    private func navigationBar() -> Widget {
        SizedBox(height: kFilesNavBar) {
            Padding(padding: EdgeInsets(left: 10, top: 0, right: 10, bottom: 6)) {
                Row(crossAxisAlignment: .center, spacing: 4) {
                    // Long arrows, as Explorer draws them -- the thin
                    // chevrons read as a different application.
                    navIcon(FluentIcons.back, enabled: bloc.canGoBack) {
                        self.bloc.add(.goBack)
                    }
                    navIcon(FluentIcons.forward, enabled: bloc.canGoForward) {
                        self.bloc.add(.goForward)
                    }
                    navIcon(FluentIcons.up, enabled: bloc.state.canGoUp) {
                        self.bloc.add(.goUp)
                    }
                    navIcon(FluentIcons.refresh, enabled: true) {
                        self.bloc.add(.refresh)
                    }
                    SizedBox(width: 4)
                    Expanded { breadcrumb() }
                    SizedBox(width: 8)
                    searchBox()
                }
            }
        }
    }

    /// The address bar, as Explorer draws it: the path broken into segments
    /// with chevrons between them, each one a place you can go back to.
    private func breadcrumb() -> Widget {
        let parts = crumbs()
        return ClipRRect(borderRadius: BorderRadius.circular(4)) {
            ColoredBox(color: Win11.fieldFill) {
                SizedBox(height: 32) {
                    Padding(padding: EdgeInsets(horizontal: 10, vertical: 0)) {
                        Row(crossAxisAlignment: .center, spacing: 2) {
                            // The leading device glyph, as Explorer draws it.
                            MacosIcon(icon: FluentIcons.thisPC,
                                      color: Win11.textDim, size: 13)
                            SizedBox(width: 4)
                            for (i, crumb) in parts.enumerated() {
                                if i > 0 {
                                    MacosIcon(icon: FluentIcons.chevronRight,
                                              color: Win11.textFaint, size: 9)
                                }
                                GestureDetector(
                                    onTap: {
                                        guard !crumb.path.isEmpty else { return }
                                        self.bloc.add(.open(crumb.path))
                                    },
                                    child: Padding(
                                        padding: EdgeInsets(horizontal: 5, vertical: 3)) {
                                        Text(crumb.label,
                                             style: TextStyle(
                                                color: i == parts.count - 1
                                                    ? Win11.text : Win11.textDim,
                                                fontSize: 12),
                                             maxLines: 1)
                                    })
                            }
                            Expanded { SizedBox(height: 1) }
                        }
                    }
                }
            }
        }
    }

    /// Filters the listing already in memory. NOT Explorer's search, which
    /// walks the subtree and asks the index -- this is the current folder, and
    /// the placeholder says so, because a search box that quietly searches
    /// less than the user expects is worse than one that never ran.
    private func searchBox() -> Widget {
        SizedBox(width: 220, height: 32) {
            MacosTextField(
                controller: search,
                placeholder: "Search \(folderLabel())",
                prefix: Padding(padding: EdgeInsets(left: 6, top: 0, right: 0, bottom: 0)) {
                    MacosIcon(icon: FluentIcons.search, color: Win11.textFaint, size: 12)
                },
                onChanged: { text in self.bloc.add(.filter(text)) },
                style: TextStyle(color: Win11.text, fontSize: 12),
                padding: EdgeInsets(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                    color: Win11.fieldFill,
                    border: Border.all(color: Win11.stroke, width: 1),
                    borderRadius: BorderRadius.circular(4)))
        }
    }

    /// Name / Date modified / Type / Size, and a click sorts by one.
    private func columnHeaders() -> Widget {
        SizedBox(height: kFilesHeaderRow) {
            ColoredBox(color: Win11.listBg) {
                Padding(padding: EdgeInsets(left: 16, top: 0, right: 16, bottom: 0)) {
                    Row(crossAxisAlignment: .center, spacing: 10) {
                        SizedBox(width: 18, height: 1)
                        Expanded { headerCell("Name", .name, true) }
                        SizedBox(width: kFilesColModified) {
                            headerCell("Date modified", .modified, true)
                        }
                        SizedBox(width: kFilesColType) { headerCell("Type", .type, true) }
                        SizedBox(width: kFilesColSize) { headerCell("Size", .size, false) }
                    }
                }
            }
        }
    }

    private func headerCell(_ title: String, _ key: FilesSortKey,
                            _ leading: Bool) -> Widget {
        let active = bloc.state.sortKey == key
        return GestureDetector(
            onTap: { self.bloc.add(.sort(key)) },
            child: Align(alignment: leading ? Alignment.centerLeft
                                            : Alignment.centerRight) {
                Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 4) {
                    Text(title,
                         style: TextStyle(color: active ? Win11.text : Win11.textFaint,
                                          fontSize: 11),
                         maxLines: 1)
                    // The arrow is the only thing that says which way a
                    // re-click will flip it.
                    if active {
                        MacosIcon(icon: bloc.state.sortAscending
                                      ? FluentIcons.chevronUp
                                      : FluentIcons.chevronDown,
                                  color: Win11.accent, size: 8)
                    }
                }
            })
    }

    /// Explorer's status bar: how many things are here, and what is picked.
    ///
    /// This ALSO carries what used to be a second bar of its own -- the
    /// description of what will open the selected file, and the two buttons
    /// that do it. Explorer has no such bar, but the question it answers
    /// ("what happens if I double-click this") is a real one, and two stacked
    /// bars both reporting the item count was worse than either.
    private func statusBar() -> Widget {
        let entry = bloc.state.visible.first { $0.path == bloc.state.selected }
        let count = bloc.state.selection.count
        return SizedBox(height: kFilesStatusBar) {
            ColoredBox(color: Win11.windowBg) {
                Padding(padding: EdgeInsets(left: 14, top: 0, right: 10, bottom: 0)) {
                    Row(crossAxisAlignment: .center, spacing: 12) {
                        Text(itemCountLabel(),
                             style: TextStyle(color: Win11.textFaint, fontSize: 11),
                             maxLines: 1)
                        if count > 0 {
                            // The hairline between the counts, as Explorer
                            // separates its own.
                            SizedBox(width: 1, height: 14) {
                                ColoredBox(color: Win11.stroke) { SizedBox(width: 1) }
                            }
                            Text(count == 1 ? "1 item selected"
                                            : "\(count) items selected",
                                 style: TextStyle(color: Win11.textFaint, fontSize: 11),
                                 maxLines: 1)
                        }
                        Expanded {
                            Align(alignment: Alignment.centerRight) {
                                Text(footerText(entry),
                                     style: TextStyle(color: Win11.textFaint, fontSize: 11),
                                     maxLines: 1)
                            }
                        }
                        if let entry, !entry.isDirectory {
                            textButton("Open") { self.bloc.add(.activate(entry)) }
                            textButton("Open with\u{2026}") { self.bloc.add(.openWith) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Chrome pieces

    private func barSeparator() -> Widget {
        Padding(padding: EdgeInsets(horizontal: 4, vertical: 10)) {
            SizedBox(width: 1) { ColoredBox(color: Win11.stroke) { SizedBox(width: 1) } }
        }
    }

    private func barIcon(_ icon: IconData, enabled: Bool,
                         _ action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: enabled ? action : {},
            child: Hover { hovered in
                ClipRRect(borderRadius: BorderRadius.circular(4)) {
                    ColoredBox(color: hovered && enabled
                               ? Win11.hoverFill : Color(0x00000000)) {
                        SizedBox(width: 34, height: 30) {
                            Center {
                                MacosIcon(icon: icon,
                                          color: enabled ? Win11.textDim
                                                         : Win11.disabled,
                                          size: 14)
                            }
                        }
                    }
                }
            })
    }

    private func barButton(_ icon: IconData, _ label: String,
                           chevron: Bool = false, enabled: Bool,
                           _ action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: enabled ? action : {},
            child: Hover { hovered in
                ClipRRect(borderRadius: BorderRadius.circular(4)) {
                    ColoredBox(color: hovered && enabled
                               ? Win11.hoverFill : Color(0x00000000)) {
                        SizedBox(height: 30) {
                            Padding(padding: EdgeInsets(horizontal: 9, vertical: 0)) {
                                Row(mainAxisSize: .min, crossAxisAlignment: .center,
                                    spacing: 6) {
                                    MacosIcon(icon: icon,
                                              color: enabled ? Win11.textDim
                                                             : Win11.disabled,
                                              size: 13)
                                    Text(label,
                                         style: TextStyle(
                                            color: enabled ? Win11.textDim
                                                           : Win11.disabled,
                                            fontSize: 12))
                                    if chevron {
                                        MacosIcon(icon: FluentIcons.chevronDown,
                                                  color: enabled ? Win11.textFaint
                                                                 : Win11.disabled,
                                                  size: 9)
                                    }
                                }
                            }
                        }
                    }
                }
            })
    }

    private func navIcon(_ icon: IconData, enabled: Bool,
                         _ action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: enabled ? action : {},
            child: Hover { hovered in
                ClipRRect(borderRadius: BorderRadius.circular(4)) {
                    ColoredBox(color: hovered && enabled
                               ? Win11.hoverFill : Color(0x00000000)) {
                        SizedBox(width: 36, height: 32) {
                            Center {
                                MacosIcon(icon: icon,
                                          color: enabled ? Win11.textDim
                                                         : Win11.disabled,
                                          size: 15)
                            }
                        }
                    }
                }
            })
    }

    // MARK: - Labels

    /// The tab's caption: the folder's own name, or the drive when we are at
    /// the root of one and there is no name to take.
    private func folderLabel() -> String {
        let path = bloc.state.directory
        if path.isEmpty { return "Files" }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    private func crumbs() -> [(label: String, path: String)] {
        let path = bloc.state.directory
        guard !path.isEmpty else { return [] }
        var out: [(label: String, path: String)] = []
        var walk: String? = path
        while let here = walk, !here.isEmpty {
            // A drive ROOT gets the shell's display name -- "Local Disk
            // (C:)", as Explorer's breadcrumb says it -- not the bare "C:".
            let isRoot = Win32Files.parent(of: here) == nil
            let label = isRoot ? Win32Files.displayName(for: here)
                               : (here as NSString).lastPathComponent
            out.append((label: label, path: here))
            walk = Win32Files.parent(of: here)
        }
        // "This PC" leads, as in Explorer. It is not a folder here (there is
        // no computer view yet), so it carries no path and does not navigate.
        out.append((label: "This PC", path: ""))
        return out.reversed()
    }

    private func itemCountLabel() -> String {
        let shown = bloc.state.visible.count
        let total = bloc.state.entries.count
        if !bloc.state.filter.isEmpty { return "\(shown) of \(total) items" }
        return total == 1 ? "1 item" : "\(total) items"
    }

    private func textButton(_ text: String, _ action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: action,
            child: ClipRRect(borderRadius: BorderRadius.circular(6)) {
                ColoredBox(color: Win11.hoverFill) {
                    SizedBox(height: 28) {
                        Padding(padding: EdgeInsets(horizontal: 12, vertical: 0)) {
                            Center {
                                Text(text, style: TextStyle(color: Win11.textDim,
                                                            fontSize: 12))
                            }
                        }
                    }
                }
            })
    }

    // MARK: - Footer
    //
    // What opens the selected file, and the two things you can do about it.
    //
    // A footer rather than a right-click menu on purpose: widget-level
    // secondary taps are not reliable in this framework, and a bar that is
    // always visible also answers a question the user did not know to ask —
    // "what will happen if I open this" — before they double-click.

    /// What the status bar says about the SELECTION, and nothing when there is
    /// none: the item count lives at the other end of the same bar now, and
    /// this returning it too is what put it on screen twice.
    private func footerText(_ entry: Win32FileEntry?) -> String {
        guard let entry else { return "" }
        if entry.isDirectory { return entry.name }
        let type = bloc.state.selectedType ?? ""
        // "Opens with" is the honest phrasing: it is what WOULD happen, and
        // the app cannot change it — only the shell's dialog can.
        if let app = bloc.state.selectedApp {
            return type.isEmpty ? "\(entry.name)  ·  opens with \(app)"
                                : "\(entry.name)  ·  \(type)  ·  opens with \(app)"
        }
        return type.isEmpty ? entry.name
                            : "\(entry.name)  ·  \(type)  ·  nothing opens this yet"
    }

    // MARK: - Listing

    private func listing() -> Widget {
        if let error = bloc.state.error { return message(error) }
        if bloc.state.loading && bloc.state.entries.isEmpty {
            return Column(mainAxisAlignment: .center, crossAxisAlignment: .center) {
                SizedBox(width: 240) { MacosProgressIndicator() }
                SizedBox(height: 12)
                Text("Reading the folder",
                     style: TextStyle(color: Color(0xFF6E7683), fontSize: 13))
            }
        }
        if bloc.state.entries.isEmpty { return message("This folder is empty.") }
        if bloc.state.visible.isEmpty {
            return message("No items match \"\(bloc.state.filter)\".")
        }

        // Lazy: a folder of ten thousand files builds only the rows on screen.
        return ListView(
            controller: scroll,
            itemExtent: kFilesRow,
            itemCount: bloc.state.visible.count,
            itemBuilder: { [weak self] _, index in self?.row(index) })
    }

    private func message(_ text: String) -> Widget {
        Column(mainAxisAlignment: .center, crossAxisAlignment: .center) {
            Text(text, style: TextStyle(color: Color(0xFF6E7683), fontSize: 13))
        }
    }

    /// The inline rename editor, in the row where the name was. The
    /// controller is created when this rename begins -- prefilled with the
    /// current name -- and reused across rebuilds until it ends; a fresh
    /// controller per build would reset the text under the user's fingers.
    private func renameField(_ entry: Win32FileEntry) -> Widget {
        if renamePath != entry.path || renameController == nil {
            renamePath = entry.path
            renameController = TextEditingController(text: entry.name)
        }
        return SizedBox(height: 24) {
            MacosTextField(
                controller: renameController!,
                onSubmitted: { text in
                    self.renameController = nil
                    self.renamePath = nil
                    self.bloc.add(.commitRename(
                        text.trimmingCharacters(in: .whitespaces)))
                },
                style: TextStyle(color: Win11.text, fontSize: 12),
                padding: EdgeInsets(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                    color: Win11.fieldFill,
                    border: Border.all(color: Win11.accent, width: 1),
                    borderRadius: BorderRadius.circular(3)),
                autofocus: true)
        }
    }

    private func row(_ index: Int) -> Widget {
        guard index < bloc.state.visible.count else { return SizedBox(height: kFilesRow) }
        let entry = bloc.state.visible[index]
        let selected = bloc.state.selection.contains(entry.path)
            || dropHover == entry.path
        let key = FilesBloc.iconKey(entry)

        return GestureDetector(
            onTap: { self.tapped(entry) },
            child: Hover { hovered in
                ColoredBox(color: selected ? Win11.selection
                           : (hovered ? Win11.hoverFill : Color(0x00000000))) {
                SizedBox(height: kFilesRow) {
                    Padding(padding: EdgeInsets(left: 16, top: 0, right: 16, bottom: 0)) {
                        Row(crossAxisAlignment: .center, spacing: 10) {
                            SizedBox(width: 18, height: 18) {
                                Center {
                                    if let icon = self.bloc.icons.view(key, side: 16) {
                                        icon
                                    } else {
                                        MacosIcon(icon: entry.isDirectory
                                                      ? FluentIcons.folderFill
                                                      : FluentIcons.page,
                                                  color: Win11.textFaint, size: 14)
                                    }
                                }
                            }
                            Expanded {
                                if self.bloc.state.renaming == entry.path {
                                    self.renameField(entry)
                                } else {
                                    Text(entry.name,
                                         style: TextStyle(color: Win11.text, fontSize: 12),
                                         maxLines: 1)
                                }
                            }
                            SizedBox(width: kFilesColModified) {
                                // Left-aligned, as Explorer's column is.
                                Align(alignment: Alignment.centerLeft) {
                                    Text(self.modifiedText(entry),
                                         style: TextStyle(color: Win11.textFaint,
                                                          fontSize: 12),
                                         maxLines: 1)
                                }
                            }
                            // Cached by extension -- a per-row registry walk
                            // is what the selection footer exists to avoid.
                            SizedBox(width: kFilesColType) {
                                Align(alignment: Alignment.centerLeft) {
                                    Text(FilesBloc.typeLabel(entry),
                                         style: TextStyle(color: Win11.textFaint,
                                                          fontSize: 12),
                                         maxLines: 1)
                                }
                            }
                            SizedBox(width: kFilesColSize) {
                                Align(alignment: Alignment.centerRight) {
                                    Text(entry.isDirectory ? "" : self.sizeText(entry.size),
                                         style: TextStyle(color: Win11.textFaint,
                                                          fontSize: 12),
                                         maxLines: 1)
                                }
                            }
                        }
                    }
                }
                }
            })
    }

    /// Select on the first tap, open on a second within half a second. See
    /// `lastTapPath` for why this is not `onDoubleTap`.
    private func tapped(_ entry: Win32FileEntry) {
        // Modified clicks are selection surgery, never activation -- and
        // they reset the double-click memory, so Ctrl-click then plain
        // click does not read as a double.
        if ctrlDown {
            lastTapPath = nil
            bloc.add(.toggleSelect(entry.path))
            return
        }
        if shiftDown {
            lastTapPath = nil
            bloc.add(.rangeSelect(entry.path))
            return
        }
        let now = Date()
        let again = lastTapPath == entry.path
            && now.timeIntervalSince(lastTapAt) < 0.5
        lastTapPath = entry.path
        lastTapAt = now
        if again {
            lastTapPath = nil
            bloc.add(.activate(entry))
        } else {
            bloc.add(.select(entry.path))
        }
    }

    private func sizeText(_ bytes: Int64) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
        }
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        }
        if bytes >= 1024 { return "\(bytes / 1024) KB" }
        return "\(bytes) B"
    }

    /// WINDOWS' own short date and time -- GetDateFormatEx with the user's
    /// locale, "8/17/2026 5:59 PM" on this machine -- not Foundation's, whose
    /// locale data disagreed with the Explorer sitting beside this window.
    private func modifiedText(_ entry: Win32FileEntry) -> String {
        guard let date = entry.modified else { return "" }
        var buffer = [CChar](repeating: 0, count: 96)
        let n = buffer.withUnsafeMutableBufferPointer {
            flwin32_format_datetime(Int64(date.timeIntervalSince1970),
                                    $0.baseAddress, 96)
        }
        return n > 0 ? String(cString: buffer) : ""
    }
}
#endif
