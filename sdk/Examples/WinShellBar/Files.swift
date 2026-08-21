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

/// One Devices-and-drives tile in the This PC view, Explorer's proportions.
let kDriveTileW = 308.0

/// The Details columns, at Explorer's proportions. Name takes what is left.
let kFilesColModified = 170.0
let kFilesColType = 130.0
let kFilesColSize = 90.0

/// Windows 11, sampled from Explorer rather than invented, so the two
/// sitting side by side do not disagree about what either theme is. Dark was
/// sampled from dark Explorer; light from light Explorer over the same
/// folder (menu #FCFCFC, list #FFFFFF, chrome mica #F3F3F3).
enum Win11 {
    /// Which palette: seeded at startup (main.swift) from the system's
    /// AppsUseLightTheme -- the apps theme Explorer's own chrome follows --
    /// and flipped live when WM_SETTINGCHANGE says the setting moved
    /// (StarlingFilesState.initState registers the host callback).
    static var light = false

    /// The wallpaper's average colour, the mica ingredient -- read once
    /// off-thread at startup (StarlingFilesState.initState) and again when
    /// the theme flips. nil until it lands, which draws the plain base.
    /// Real mica is DWM compositing a blurred desktop behind transparent
    /// window regions -- unreachable behind an opaque GL swap chain -- but
    /// what the eye reads off Explorer's chrome at rest is the TINT, and
    /// that is affordable everywhere.
    nonisolated(unsafe) static var micaTint: UInt32?

    /// `base` leaned toward the wallpaper's tint by `amount`.
    private static func mica(_ base: UInt32, _ amount: Double) -> Color {
        guard let tint = micaTint else { return Color(Int(base)) }
        func channel(_ shift: UInt32) -> UInt32 {
            let b = Double((base >> shift) & 0xFF)
            let t = Double((tint >> shift) & 0xFF)
            return UInt32(b + (t - b) * amount + 0.5) << shift
        }
        return Color(Int(0xFF00_0000 | channel(16) | channel(8) | channel(0)))
    }

    static var windowBg: Color {
        light ? mica(0xFFF3F3F3, 0.20) : mica(0xFF202020, 0.15)
    }
    static var surface: Color { light ? Color(0xFFFFFFFF) : Color(0xFF272727) }
    static var navPane: Color { windowBg }
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
    /// The popup-surface menu fill: the same slab, OPAQUE. A popup window's
    /// panel has nothing of ours behind it to frost, and the translucent
    /// tint would composite against the surface's black class brush.
    static var menuBgOpaque: Color { light ? Color(0xFFFCFCFC) : Color(0xFF2C2C2C) }
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
    private var tabs: FilesTabs { FilesTabs.shared }
    private var bloc: FilesBloc { tabs.bloc }

    /// Double-click, by hand.
    ///
    /// `onDoubleTap` is not usable here — registering it kills the plain tap
    /// as well on at least one embedder, and this framework's gesture arena
    /// is not something to rely on. So: a tap selects, and a second tap on
    /// the same row within the interval opens. Windows' own behaviour, out of
    /// two ordinary taps.
    private var lastTapPath: String?
    private var lastTapAt = Date.distantPast

    /// Whether the sidebar's This PC shows its drives. On the window, not
    /// the tab: Explorer's tabs share one nav pane, and so do ours.
    private var thisPCExpanded = true

    /// Details' column widths -- the header dividers drag them. On the
    /// window, like the nav pane's state; the constants are the defaults.
    private var colModified = kFilesColModified
    private var colType = kFilesColType
    private var colSize = kFilesColSize
    /// A live divider drag: which column, where the pointer started, and
    /// the column's width at that moment.
    private var colDrag: (col: FilesSortKey, x: Double, width: Double)?

    /// The divider under a header-row point, each boundary owning ±6pt of
    /// the gap. A boundary belongs to the column RIGHT of it: dragging
    /// moves the boundary while everything further right stays anchored,
    /// so the column to the left grows by what this one gives up.
    private func dividerAt(_ x: Double, _ y: Double) -> FilesSortKey? {
        guard bloc.state.viewMode == .details, !bloc.state.isThisPC else {
            return nil
        }
        let headerTop = kFilesToolbar - kFilesHeaderRow
        guard y >= headerTop, y < kFilesToolbar else { return nil }
        let width = Win32WindowedHost.host?.clientSize?.width ?? kFilesWidth
        let right = width - 16
        let atSize = right - colSize - 5
        let atType = atSize - 10 - colType
        let atModified = atType - 10 - colModified
        if abs(x - atSize) <= 6 { return .size }
        if abs(x - atType) <= 6 { return .type }
        if abs(x - atModified) <= 6 { return .modified }
        return nil
    }

    /// Applies a divider drag: the pointer's travel comes off the column's
    /// starting width, clamped so no column can vanish or eat the window.
    private func colDragMoved(_ x: Double) {
        guard let drag = colDrag else { return }
        let proposed = drag.width - (x - drag.x)
        let clamped = min(max(proposed, 50), 400)
        setState {
            switch drag.col {
            case .modified: colModified = clamped
            case .type: colType = clamped
            case .size: colSize = clamped
            case .name: break
            }
        }
    }

    /// The list's scroll position, so a right-click can work out which row is
    /// under the pointer. Without it the arithmetic is only right until the
    /// first scroll — and then silently wrong, which is worse. PER TAB, from
    /// the tabs model: switching away and back lands where the user left.
    private var scroll: ScrollController { tabs.scroll }

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

    /// Where the arrow keys stand: the row the last key or click landed on,
    /// which Shift+arrows extend from and plain arrows step from. A stale
    /// path (the file left, the tab changed) simply fails the lookup and
    /// the anchor takes over.
    private var keyCursor: String?

    /// Type-to-jump, as every Windows listing does it: printable keys
    /// accumulate for a second and the first name with that prefix gets
    /// the selection.
    private var typeAhead = ""
    private var typeAheadAt = Date.distantPast

    /// The search box's text. Owned by the widget, not the bloc: the bloc
    /// holds the filter it produced, which is a different thing from what is
    /// currently in the field.
    private let search = TextEditingController()

    /// The inline rename's editor, created when a rename begins and dropped
    /// when it ends. Held here rather than made per-build so the text
    /// survives the rebuilds that happen while the user types.
    private var renameController: TextEditingController?
    /// The address bar's other face: a click on its empty space flips the
    /// crumbs into an edit field (Explorer's gesture), Enter navigates,
    /// Escape puts the crumbs back.
    private var pathEditing = false
    private var pathController: TextEditingController?
    /// The directory the edit opened over -- when the window navigates away
    /// underneath it (sidebar click, Back), the edit is stale and closes.
    private var pathEditDirectory = ""
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

        // While the address bar is a text field, the field owns the keys:
        // Ctrl+C there means "copy the selected text", not "clip the
        // selected file". Only Escape is ours -- it closes the edit, as it
        // closes a rename below.
        if pathEditing {
            if keyData.logical == 0x1_0000_001B {
                setState {
                    pathEditing = false
                    pathController = nil
                }
                return true
            }
            return false
        }

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
                // Not from a namespace listing: the clipboard data object
                // is built from FILE paths, and a parsing name in a
                // CF_HDROP is a lie waiting for a paste. The context menu's
                // shell verbs remain the honest route there.
                guard canMutateHere else { return false }
                if bloc.state.selection.count > 1 {
                    bloc.add(.clipSelection(cut: false))
                    return true
                }
                guard let entry = selectedEntry else { return false }
                bloc.add(.clip(entry, cut: false))
                return true
            case 0x0007_001B: // X
                guard canMutateHere else { return false }
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
            case 0x0007_0017: // T: new tab
                tabs.add()
                return true
            case 0x0007_001A: // W: close tab (the window, when it is the last)
                closeTab(tabs.active)
                return true
            case 0x0007_0019: // V
                // Nothing pastes INTO a namespace listing either: the target
                // "directory" is a parsing name, which IFileOperation's
                // destination cannot be.
                guard canMutateHere else { return false }
                bloc.add(.paste(into: bloc.state.directory))
                return true
            case 0x0007_001D: // Z: undo the last file operation
                // Not gated on canMutateHere: the inverse runs on the
                // JOURNAL's paths, not on this listing -- Ctrl+Z from the
                // Recycle Bin view after a delete is exactly the gesture
                // that should work. An inline rename in flight keeps the
                // key though; the field's edit is not a file operation yet.
                guard bloc.state.renaming == nil else { return false }
                bloc.add(.undo)
                return true
            default:
                break
            }
        }

        if altDown {
            switch keyData.logical {
            case 0x1_0000_0302: bloc.add(.goBack); return true     // Left
            case 0x1_0000_0303: bloc.add(.goForward); return true  // Right
            case 0x1_0000_0304: bloc.add(.goUp); return true       // Up
            default: break
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
            guard canMutateHere, let entry = selectedEntry else { return false }
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
        case 0x1_0000_0008: // Backspace: Explorer's other Back
            bloc.add(.goBack)
            return true
        case 0x1_0000_0301: // Down
            // A strip down: one row in Details, one grid row otherwise.
            moveSelection(listingGrid().columns, extend: shiftDown)
            return true
        case 0x1_0000_0304: // Up
            moveSelection(-listingGrid().columns, extend: shiftDown)
            return true
        case 0x1_0000_0303: // Right -- a neighbour, only where cells have one
            let columns = listingGrid().columns
            guard columns > 1 else { break }
            moveSelection(1, extend: shiftDown)
            return true
        case 0x1_0000_0302: // Left
            let columns = listingGrid().columns
            guard columns > 1 else { break }
            moveSelection(-1, extend: shiftDown)
            return true
        case 0x1_0000_0306: // Home
            moveSelection(-bloc.state.visible.count, extend: shiftDown)
            return true
        case 0x1_0000_0305: // End
            moveSelection(bloc.state.visible.count, extend: shiftDown)
            return true
        default:
            break
        }

        // Type-to-jump: anything printable, outside a chord.
        if !ctrlDown && !altDown, let character = keyData.character,
           character.count == 1,
           let scalar = character.unicodeScalars.first,
           scalar.value >= 0x20, scalar.value != 0x7F {
            let now = Date()
            if now.timeIntervalSince(typeAheadAt) > 1.0 { typeAhead = "" }
            typeAheadAt = now
            typeAhead += character.lowercased()
            if let index = bloc.state.visible.firstIndex(
                where: { $0.name.lowercased().hasPrefix(typeAhead) }) {
                let path = bloc.state.visible[index].path
                keyCursor = path
                bloc.add(.select(path))
                ensureRowVisible(index)
            }
            return true
        }
        return false
    }

    /// One arrow step (or a Home/End leap, clamped), extending the range
    /// from the anchor when Shift rides along -- Explorer's arrows.
    private func moveSelection(_ delta: Int, extend: Bool) {
        let visible = bloc.state.visible
        guard !visible.isEmpty else { return }
        let base = keyCursor ?? bloc.state.selectionAnchor ?? bloc.state.selected
        let start = base.flatMap { b in visible.firstIndex { $0.path == b } }
        let next: Int
        if let start {
            next = min(max(start + delta, 0), visible.count - 1)
        } else {
            next = delta > 0 ? 0 : visible.count - 1
        }
        let path = visible[next].path
        keyCursor = path
        if extend {
            bloc.add(.rangeSelect(path))
        } else {
            bloc.add(.select(path))
        }
        ensureRowVisible(next)
    }

    /// Scrolls just far enough that item `index` is inside the viewport --
    /// the arrows walking off the bottom pull the list along. Strip-aware:
    /// in a grid mode the unit that scrolls is the strip the item sits in.
    private func ensureRowVisible(_ index: Int) {
        guard scroll.hasClients else { return }
        let size = Win32WindowedHost.host?.clientSize
            ?? (width: kFilesWidth, height: kFilesHeight)
        let g = listingGrid()
        let viewHeight = size.height - g.top - kFilesStatusBar
        let top = Double(index / g.columns) * g.cellH
        let bottom = top + g.cellH
        if top < scroll.offset {
            scroll.jumpTo(top)
        } else if bottom > scroll.offset + viewHeight {
            scroll.jumpTo(bottom - viewHeight)
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
        // Restyle when the system's light/dark theme flips -- Windows'
        // Settings or our own broadcast WM_SETTINGCHANGE, the host turns it
        // into this callback. The root rebuild recolors the chrome; the
        // listing's lazy rows need the bloc poke (ancestor rebuilds do not
        // reach lazy sliver children -- see the framework traps).
        Win32WindowedHost.host?.onThemeChange { [weak self] in
            let light = Win32SystemInfo.appsUseLightTheme()
            guard light != Win11.light else { return }
            Win11.light = light
            self?.setState {}
            self?.tabs.blocs.forEach { $0.add(.iconsChanged) }
        }
        // The mica tint: the wallpaper's average, decoded off this thread
        // (a shell thumbnail plus arithmetic) and painted in when it lands.
        // The first frames draw the plain base, which is also mica's own
        // rest state on a machine that disallows transparency.
        Task.detached { [weak self] in
            guard let tint = Win32SystemInfo.wallpaperAverage() else { return }
            await MainActor.run {
                Win11.micaTint = tint
                self?.setState {}
                self?.tabs.blocs.forEach { $0.add(.iconsChanged) }
            }
        }
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
                    // Middle-click closes the tab under it, as every
                    // tabbed thing on the desktop does.
                    if e.buttons == 4 && e.position.dy < kFilesTabStrip {
                        if let index = self.tabAt(e.position.dx,
                                                  e.position.dy) {
                            self.closeTab(index)
                        }
                        return
                    }
                    // A press on a header divider arms a column resize;
                    // the moves land in colDragMoved until the button lifts.
                    if e.buttons == 1,
                       let col = self.dividerAt(e.position.dx, e.position.dy) {
                        let width: Double
                        switch col {
                        case .modified: width = self.colModified
                        case .type: width = self.colType
                        case .size: width = self.colSize
                        case .name: width = 0
                        }
                        self.colDrag = (col, e.position.dx, width)
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
                    if self.colDrag != nil {
                        self.colDragMoved(e.position.dx)
                        return
                    }
                    if self.dragMoved(e) { return }
                    self.bandMoved(e)
                },
                onPointerUp: { _ in
                    self.colDrag = nil
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
                                // The header strip is Details furniture:
                                // the other view modes have no columns to
                                // head, so their listing starts above it
                                // (see ListingGrid.top).
                                if bloc.state.viewMode == .details
                                    && !bloc.state.isThisPC {
                                    columnHeaders()
                                }
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

    // MARK: - Listing geometry

    /// One description of where the cells are, for every view mode. The
    /// ListView that draws them and the arithmetic hit tests (context menu
    /// targeting, the rubber band, drop targeting, the arrow keys) consume
    /// the same numbers, which is the only thing keeping them in agreement.
    /// Details is the columns == 1 case of the same grid.
    private struct ListingGrid {
        let columns: Int
        let cellW: Double
        let cellH: Double
        /// Where the listing's content starts, in window coordinates --
        /// below the header strip in Details, in its place otherwise.
        let top: Double
        let left: Double
    }

    private func listingGrid() -> ListingGrid {
        let width = Win32WindowedHost.host?.clientSize?.width ?? kFilesWidth
        let avail = width - kFilesSidebar
        switch bloc.state.viewMode {
        case .details:
            return ListingGrid(columns: 1, cellW: avail, cellH: kFilesRow,
                               top: kFilesToolbar, left: kFilesSidebar)
        case .tiles:
            return packed(cellW: 252, cellH: 62, avail: avail)
        case .mediumIcons:
            return packed(cellW: 98, cellH: 112, avail: avail)
        case .largeIcons:
            return packed(cellW: 146, cellH: 160, avail: avail)
        }
    }

    private func packed(cellW: Double, cellH: Double,
                        avail: Double) -> ListingGrid {
        ListingGrid(columns: max(1, Int((avail - 16) / cellW)),
                    cellW: cellW, cellH: cellH,
                    top: kFilesToolbar - kFilesHeaderRow,
                    left: kFilesSidebar + 8)
    }

    /// The item index under a window-space point, or nil in a strip's
    /// trailing gap and below the last cell.
    private func cellIndex(at x: Double, _ y: Double,
                           in g: ListingGrid) -> Int? {
        // `offset` TRAPS on a controller with no attached position, and an
        // EMPTY folder is exactly that: the listing draws its "This folder
        // is empty" label instead of the scrollable, so nothing ever
        // attaches. The first right-click on an empty folder's background
        // killed the app here -- hasClients is the guard Dart code uses on
        // the same contract, not an optimization.
        let offset = scroll.hasClients ? scroll.offset : 0
        let strip = Int((y - g.top + offset) / g.cellH)
        guard strip >= 0, x >= g.left else { return nil }
        let column = Int((x - g.left) / g.cellW)
        guard column < g.columns else { return nil }
        let index = strip * g.columns + column
        guard index < bloc.state.visible.count else { return nil }
        return index
    }

    /// The item under a point, accounting for how far the list is scrolled.
    /// nil above the listing (the toolbars, the sidebar) so no menu opens
    /// there, and `.background` in the empty space around and below the
    /// cells, which is what gets the folder's own menu.
    private func targetAt(_ x: Double, _ y: Double) -> MenuTarget? {
        // The computer view has no folder behind it: no background menu,
        // no item menus -- the drives are not files.
        guard !bloc.state.isThisPC else { return nil }
        let g = listingGrid()
        guard x >= kFilesSidebar, y >= g.top else { return nil }
        guard let index = cellIndex(at: x, y, in: g) else { return .background }
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
        let g = listingGrid()
        let x = min(max(e.position.dx, kFilesSidebar), size.width)
        let y = min(max(e.position.dy, g.top),
                    size.height - kFilesStatusBar)
        band.rect = (min(origin.x, x), min(origin.y, y),
                     abs(x - origin.x), abs(y - origin.y))

        // The cells the rectangle intersects. Same arithmetic as targetAt,
        // over both spans instead of a point -- in Details the column span
        // is always 0...0 and this is the old row walk.
        let offset = scroll.hasClients ? scroll.offset : 0
        let count = bloc.state.visible.count
        var covered = bandBase
        if count > 0 {
            let loS = max(Int((min(origin.y, y) - g.top + offset) / g.cellH), 0)
            let hiS = min(Int((max(origin.y, y) - g.top + offset) / g.cellH),
                          (count - 1) / g.columns)
            let loC = max(Int((min(origin.x, x) - g.left) / g.cellW), 0)
            let hiC = min(Int((max(origin.x, x) - g.left) / g.cellW),
                          g.columns - 1)
            if loS <= hiS, loC <= hiC, max(origin.x, x) >= g.left {
                for strip in loS...hiS {
                    for column in loC...hiC {
                        let index = strip * g.columns + column
                        if index < count {
                            covered.insert(bloc.state.visible[index].path)
                        }
                    }
                }
            }
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

    /// Where a drop at this point would land: a sidebar row's folder, the
    /// folder row under the pointer, else the open directory. nil where
    /// nothing takes a drop (the bars, the rules, This PC).
    private func dropResolve(_ x: Double, _ y: Double) -> String? {
        // The sidebar's rows take drops too -- each is a folder, and the
        // folder is the target. Independent of what the listing shows, so
        // it works from the This PC view as well.
        if x < kFilesSidebar { return sidebarDropTarget(x, y) }
        // Nothing lands ON This PC's listing -- it is not a folder. Nor on a
        // namespace one: the background target would be a "::" parsing name
        // and the folder rows under the pointer are the bin's own slots, so
        // there is no honest destination anywhere in the view. (Dragging
        // INTO the Recycle Bin is a delete, not a copy, and belongs to the
        // sidebar row -- which is handled above and is deliberately not a
        // drop target yet.)
        guard !bloc.state.isThisPC, !bloc.state.isNamespace else { return nil }
        guard y >= kFilesToolbar else { return nil }
        if case .item(let entry)? = targetAt(x, y), entry.isDirectory {
            return entry.path
        }
        return bloc.state.directory
    }

    /// The folder behind the sidebar row under a point, or nil over the
    /// rules, This PC (not a folder) and the empty space below. MIRRORS
    /// sidebar()'s layout arithmetic -- a row added there must be added
    /// here, or drops land one row off.
    private func sidebarDropTarget(_ x: Double, _ y: Double) -> String? {
        guard x >= 8, x <= kFilesSidebar - 8 else { return nil }
        let byName = Dictionary(uniqueKeysWithValues:
            bloc.state.places.map { ($0.name, $0) })
        var items: [(height: Double, path: String?)] = []
        if let home = byName["Home"] { items.append((32, home.path)) }
        if let oneDrive = bloc.state.oneDrive {
            items.append((32, oneDrive.path))
        }
        items.append((17, nil))                    // rule
        for place in bloc.state.quickAccess {
            items.append((32, place.path))
        }
        items.append((17, nil))                    // rule
        items.append((32, nil))                    // This PC
        if thisPCExpanded {
            for drive in bloc.state.drives { items.append((32, drive.path)) }
        }
        items.append((17, nil))                    // rule
        items.append((32, nil))                    // Recycle Bin -- a drop
        items.append((32, nil))                    // Network      -- not a
                                                   // folder either one
        var top = kFilesTabStrip + kFilesNavBar + kFilesCommandBar + 10
        for item in items {
            if y >= top, y < top + item.height { return item.path }
            top += item.height
        }
        return nil
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
                              owner: FilesBloc.ownerWindow) {
            [weak self] ok, records in
            if ok {
                FilesBloc.pushUndo(records)
                self?.bloc.add(.refresh)
            }
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
                        // OneDrive under it, when the machine has one --
                        // shell-named ("OneDrive - Personal"), cloud in
                        // OneDrive's blue.
                        if let oneDrive = bloc.state.oneDrive {
                            placeRow(oneDrive, glyph: FluentIcons.cloud,
                                     tint: Color(0xFF0F6CBD))
                        }
                        sidebarRule()
                        // The pinned folders: EXPLORER'S pin set, read from
                        // the shell, in the shell's order -- pin a folder in
                        // either explorer and both sidebars grow the row.
                        // (Replaced a hardcoded six-name list; the shell's
                        // set for a fresh profile IS those six.) The pin
                        // glyph is live: clicking it unpins, through the
                        // shell's own unpinfromhome verb.
                        for place in bloc.state.quickAccess {
                            placeRow(place, pinned: true)
                        }
                        sidebarRule()
                        // This PC leads its drives, computer glyph and all.
                        // The ROW navigates to the computer view; only the
                        // chevron collapses the drives -- Explorer's own
                        // split. Expansion is one bool here, on the WINDOW:
                        // tabs share a nav pane in Explorer and they share
                        // this one too.
                        placeRow(Win32Place(name: "This PC",
                                            path: kThisPCPath),
                                 glyph: FluentIcons.thisPC,
                                 chevron: thisPCExpanded
                                     ? FluentIcons.chevronDown
                                     : FluentIcons.chevronRight,
                                 onChevron: { [weak self] in
                                     self?.setState {
                                         self?.thisPCExpanded.toggle()
                                     }
                                 })
                        if thisPCExpanded {
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
                        sidebarRule()
                        // The namespace places: rows that NAVIGATE now --
                        // the listing speaks the shell's namespace, so the
                        // old "a row that navigates nowhere" objection is
                        // paid off.
                        // Named by the shell, like every other row here --
                        // so a German machine reads "Papierkorb" rather than
                        // our English guess at it.
                        let bin = Win32Files.NamespacePlace.recycleBin
                        let network = Win32Files.NamespacePlace.network
                        placeRow(Win32Place(name: Win32Files.displayName(for: bin),
                                            path: bin),
                                 glyph: FluentIcons.delete)
                        placeRow(Win32Place(name: Win32Files.displayName(for: network),
                                            path: network),
                                 glyph: FluentIcons.networkPlaces)
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
                          glyph: IconData? = nil, tint: Color? = nil,
                          chevron: IconData? = nil,
                          onChevron: (() -> Void)? = nil,
                          onTap: (() -> Void)? = nil) -> Widget {
        let selected = !place.path.isEmpty
            && (bloc.state.directory == place.path
                // A drag hovering the row lights it the way the listing's
                // folder rows light -- the drop-target promise, made
                // visible.
                || dropHover == place.path)
        let look = Self.placeLooks[place.name]
        let icon = glyph ?? look?.glyph ?? FluentIcons.folderFill
        let tint = tint ?? (glyph != nil ? Win11.textDim
            : (look?.tint ?? (Win11.light ? Color(0xFF4E80C9)
                                          : Color(0xFF7FA9DE))))
        let interactive = !place.path.isEmpty || onTap != nil
        return GestureDetector(
            onTap: {
                if let onTap { onTap(); return }
                guard !place.path.isEmpty else { return }
                self.bloc.add(.open(place.path))
            },
            child: Padding(padding: EdgeInsets(left: 0, top: 1, right: 0, bottom: 1)) {
                ClipRRect(borderRadius: BorderRadius.circular(6)) {
                    Hover { hovered in
                    ColoredBox(color: selected ? Color(0x2E6FA8FF)
                               : (hovered && interactive
                                  ? Win11.hoverFill : Color(0x00000000))) {
                        SizedBox(height: 30) {
                            Padding(padding: EdgeInsets(
                                left: chevron == nil ? 10 : 0, top: 0,
                                right: 10, bottom: 0)) {
                                Row(crossAxisAlignment: .center, spacing: 0) {
                                    // The chevron gutter spends exactly the
                                    // 10 points a plain row spends on left
                                    // padding, so the icon column aligns
                                    // either way. Its own tap target when
                                    // it has its own job -- the inner
                                    // detector wins the hit test, so the
                                    // row underneath does not also fire.
                                    if let chevron {
                                        if let onChevron {
                                            GestureDetector(
                                                onTap: onChevron,
                                                child: SizedBox(width: 10) {
                                                    MacosIcon(icon: chevron,
                                                              color: Win11.textFaint,
                                                              size: 9)
                                                })
                                        } else {
                                            SizedBox(width: 10) {
                                                MacosIcon(icon: chevron,
                                                          color: Win11.textFaint,
                                                          size: 9)
                                            }
                                        }
                                    }
                                    Expanded {
                                        Row(crossAxisAlignment: .center,
                                            spacing: 9) {
                                            MacosIcon(icon: icon, color: tint,
                                                      size: 14)
                                            Text(place.name,
                                                 style: TextStyle(
                                                     color: Win11.text,
                                                     fontSize: 13),
                                                 maxLines: 1)
                                            if pinned {
                                                Expanded { SizedBox(height: 1) }
                                                // Live, not decoration:
                                                // this is the unpin.
                                                GestureDetector(
                                                    onTap: {
                                                        self.bloc.runShellVerb(
                                                            "unpinfromhome",
                                                            path: place.path,
                                                            location: Win32Files
                                                                .NamespacePlace
                                                                .quickAccess)
                                                    },
                                                    child: MacosIcon(
                                                        icon: FluentIcons.pin,
                                                        color: Win11.textFaint,
                                                        size: 11))
                                            }
                                        }
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
    /// Tabs shrink to fit as they multiply, Explorer-fashion, down to a
    /// floor that keeps the close glyph reachable.
    private func tabWidth(_ width: Double) -> Double {
        let available = width - kCaptionButtonW * 3 - kTabX - 50
        let count = Double(max(tabs.blocs.count, 1))
        return min(kTabW, max(90, available / count - 4))
    }

    private func tabLabel(_ bloc: FilesBloc) -> String {
        let path = bloc.state.directory
        if path.isEmpty { return "Files" }
        if path == kThisPCPath { return "This PC" }
        if path.hasPrefix("::") { return Win32Files.displayName(for: path) }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? Win32Files.displayName(for: path) : name
    }

    private func closeTab(_ index: Int) {
        if !tabs.close(index) {
            Win32WindowedHost.host?.closeWindow()
        }
    }

    private func tabStrip() -> Widget {
        SizedBox(height: kFilesTabStrip) {
            ColoredBox(color: Win11.windowBg) {
                Stack(alignment: Alignment.topLeft) {
                    // Every tab, seated on the strip's bottom edge with
                    // rounded shoulders the way Explorer's sit; the active
                    // one carries the surface colour the content area
                    // continues, which is what visually welds tab to page.
                    let width = Win32WindowedHost.host?.clientSize?.width
                        ?? kFilesWidth
                    let tw = tabWidth(width)
                    for (index, tabBloc) in tabs.blocs.enumerated() {
                        Positioned(left: kTabX + Double(index) * (tw + 4),
                                   top: 8, bottom: 0) {
                            SizedBox(width: tw) {
                                ClipRRect(borderRadius: BorderRadius.only(
                                    topLeft: Radius(circular: 8),
                                    topRight: Radius(circular: 8))) {
                                    Hover { hovered in
                                        ColoredBox(color: index == self.tabs.active
                                                   ? Win11.surface
                                                   : (hovered ? Win11.hoverFill
                                                              : Color(0x00000000))) {
                                        Padding(padding: EdgeInsets(
                                            left: 12, top: 0, right: 8, bottom: 0)) {
                                            Row(crossAxisAlignment: .center, spacing: 8) {
                                                MacosIcon(icon: FluentIcons.folderFill,
                                                          color: Win11.textDim, size: 13)
                                                Expanded {
                                                    Text(self.tabLabel(tabBloc),
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
                        }
                    }
                    // "+": a new tab, on Home, as Explorer's does.
                    Positioned(left: kTabX + Double(tabs.blocs.count) * (tw + 4) + 8,
                               top: 12) {
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
    /// The tab under a strip point, by the arithmetic that draws the strip.
    /// Shared by the left-button press (activate / close zone) and the
    /// middle-click close.
    private func tabAt(_ x: Double, _ y: Double) -> Int? {
        let width = Win32WindowedHost.host?.clientSize?.width ?? kFilesWidth
        let tw = tabWidth(width)
        let tabsEnd = kTabX + Double(tabs.blocs.count) * (tw + 4)
        guard x >= kTabX, x < tabsEnd, y >= 8 else { return nil }
        let index = Int((x - kTabX) / (tw + 4))
        let inTab = x - (kTabX + Double(index) * (tw + 4))
        guard inTab < tw, tabs.blocs.indices.contains(index) else { return nil }
        return index
    }

    private func stripPress(_ x: Double, _ y: Double) {
        guard let host = Win32WindowedHost.host else { return }
        let width = host.clientSize?.width ?? kFilesWidth
        let fromRight = width - x
        if fromRight <= kCaptionButtonW { host.closeWindow(); return }
        if fromRight <= kCaptionButtonW * 2 { host.toggleMaximize(); return }
        if fromRight <= kCaptionButtonW * 3 { host.minimize(); return }
        // The tabs, by the same arithmetic that drew them: the close glyph
        // zone at each tab's right edge, the rest of the tab activates.
        // Closing the last tab closes the window, as Explorer's does.
        let tw = tabWidth(width)
        let tabsEnd = kTabX + Double(tabs.blocs.count) * (tw + 4)
        if let index = tabAt(x, y) {
            let inTab = x - (kTabX + Double(index) * (tw + 4))
            if inTab >= tw - 28 {
                closeTab(index)
            } else {
                tabs.active = index
            }
            return
        }
        // "+": a new tab.
        if x >= tabsEnd + 2 && x < tabsEnd + 36 {
            tabs.add()
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
        // The dictionary, not a scan: the command bar asks half a dozen
        // times per build.
        return bloc.state.visibleByPath[path]
    }

    /// Whether the file-shaped mutations (New, rename, cut/copy/paste)
    /// belong in this listing: a real directory yes, This PC and the
    /// namespace views no. Delete stays available everywhere -- the
    /// IFileOperation behind it speaks parsing names and puts up its own
    /// confirmation where deletion is permanent.
    private var canMutateHere: Bool {
        !bloc.state.isThisPC && !bloc.state.isNamespace
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
        var rows = [
            MenuRow(title: "Folder", glyph: FluentIcons.folder,
                    action: { filesBloc.add(.newFolder) }),
            MenuRow(title: "Window", glyph: FluentIcons.openExternal,
                    action: { self.openNewWindow() }),
        ]
        // The ShellNew templates, below Explorer's own separator. Empty
        // only in the first moments of the first window, before the
        // registry walk lands.
        let templates = bloc.state.newTemplates
        if !templates.isEmpty {
            rows.append(MenuRow(isSeparator: true))
            for template in templates {
                rows.append(MenuRow(title: template.name,
                                    glyph: FluentIcons.page,
                                    action: { filesBloc.add(.newFile(template)) }))
            }
        }
        menu.openFlyout(at: lastDown.x - 24, flyoutAnchorY, rows: rows)
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

    private func openViewFlyout() {
        func modeRow(_ mode: FilesViewMode) -> MenuRow {
            MenuRow(title: mode.label,
                    glyph: bloc.state.viewMode == mode ? FluentIcons.check : nil,
                    action: { filesBloc.add(.setView(mode)) })
        }
        menu.openFlyout(at: lastDown.x - 24, flyoutAnchorY, rows: [
            modeRow(.largeIcons),
            modeRow(.mediumIcons),
            modeRow(.tiles),
            modeRow(.details),
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
                    // Explorer's New: Folder, Window, then the registry's
                    // own ShellNew templates, each born into its rename
                    // field.
                    barButton(FluentIcons.add, "New", chevron: true,
                              enabled: canMutateHere) {
                        self.openNewFlyout()
                    }
                    barSeparator()
                    // Explorer's own enablement: cut/copy/rename/delete need
                    // a selection, paste needs files on the clipboard. All
                    // five run through the shell (IFileOperation / the
                    // shell's data object) -- see FilesBloc and
                    // flwin32_fileops.c.
                    //
                    // canMutateHere on the first four for the same reason the
                    // keys carry it: the clipboard data object is built from
                    // FILE paths, and a parsing name in a CF_HDROP is a lie
                    // waiting for a paste. Delete alone stays lit -- its
                    // IFileOperation speaks parsing names and confirms
                    // permanence itself, which is exactly Empty Recycle Bin.
                    barIcon(FluentIcons.cut,
                            enabled: canMutateHere && selectedEntry != nil) {
                        if let entry = self.selectedEntry {
                            self.bloc.add(.clip(entry, cut: true))
                        }
                    }
                    barIcon(FluentIcons.copy,
                            enabled: canMutateHere && selectedEntry != nil) {
                        if let entry = self.selectedEntry {
                            self.bloc.add(.clip(entry, cut: false))
                        }
                    }
                    barIcon(FluentIcons.paste,
                            enabled: canMutateHere
                                && Win32FileOps.clipboardHasFiles()) {
                        self.bloc.add(.paste(into: self.bloc.state.directory))
                    }
                    barIcon(FluentIcons.rename,
                            enabled: canMutateHere && selectedEntry != nil) {
                        if let entry = self.selectedEntry {
                            self.bloc.add(.beginRename(entry))
                        }
                    }
                    // Share, through the shell's own verb -- the same
                    // windows.modernshare the menu's icon row invokes. It
                    // hands the target a PATH, so an item with no file
                    // behind it (a recycled slot, a zip's contents) cannot
                    // be shared and says so by staying grey.
                    barIcon(FluentIcons.share,
                            enabled: selectedEntry?.isDirectory == false
                                && selectedEntry?.isFileSystem == true) {
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
                              chevron: true, enabled: true) {
                        self.openViewFlyout()
                    }
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
    /// with chevrons between them, each one a place you can go back to --
    /// and, on a click in its empty space, an edit field over the same
    /// footprint (Explorer's other address bar). Enter navigates, Escape
    /// puts the crumbs back, and the crumbs also return whenever a
    /// navigation lands (the rebuild reads `pathEditing` fresh).
    private func breadcrumb() -> Widget {
        // A navigation that lands UNDER the edit (a sidebar click, Back)
        // closes it: the field was editing a directory this window is no
        // longer in. Cleared directly rather than through setState -- this
        // runs inside the rebuild that navigation already caused, and the
        // crumbs drawn below are the correct face for the new state.
        if pathEditing && bloc.state.directory != pathEditDirectory {
            pathEditing = false
            pathController = nil
        }
        if pathEditing { return pathField() }
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
                            // The empty remainder of the bar IS the edit
                            // affordance. A transparent ColoredBox, because
                            // a bare SizedBox hit-tests as nothing and this
                            // framework's ColoredBox hit-tests opaque at any
                            // alpha -- the documented trap, here load-bearing.
                            Expanded {
                                GestureDetector(
                                    onTap: { self.openPathEdit() },
                                    child: ColoredBox(color: Color(0x00000000)) {
                                        SizedBox(height: 32)
                                    })
                            }
                        }
                    }
                }
            }
        }
    }

    /// The breadcrumb's edit face: the current path as text, everything
    /// selected the moment it opens -- the common gesture is to type a
    /// whole new path over it, not to append.
    private func pathField() -> Widget {
        SizedBox(height: 32) {
            MacosTextField(
                controller: pathController!,
                onSubmitted: { text in self.commitPath(text) },
                style: TextStyle(color: Win11.text, fontSize: 12),
                padding: EdgeInsets(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                    color: Win11.fieldFill,
                    border: Border.all(color: Win11.accent, width: 1),
                    borderRadius: BorderRadius.circular(4)),
                autofocus: true,
                // Losing focus IS the dismissal: Escape unfocuses inside
                // the field (the key never reaches handleShortcut while
                // the field owns it), and Explorer's bar also folds back
                // to crumbs the moment the edit stops being the focus.
                onFocusChanged: { focused in
                    guard !focused, self.pathEditing else { return }
                    self.setState {
                        self.pathEditing = false
                        self.pathController = nil
                    }
                })
        }
    }

    private func openPathEdit() {
        let directory = bloc.state.directory
        // The sentinel is not a path anyone can edit; an empty field with
        // everything to type is more honest than "\u{1}ThisPC".
        let text = directory == kThisPCPath ? "" : directory
        setState {
            let controller = TextEditingController(text: text)
            // Everything selected, as Explorer opens it: the common gesture
            // is typing a whole new path over the old one, not appending.
            controller.selection = TextSelection(baseOffset: 0,
                                                 extentOffset: text.count)
            pathController = controller
            pathEditing = true
            pathEditDirectory = directory
        }
    }

    /// Enter in the address field: expand what Explorer expands, then go.
    private func commitPath(_ text: String) {
        var path = text.trimmingCharacters(in: .whitespaces)
        // Pasted paths arrive quoted more often than not -- "Copy as path"
        // itself writes them that way.
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        // %USERPROFILE% and friends, Explorer's oldest address-bar contract.
        while let range = path.range(of: "%[A-Za-z0-9_()]+%",
                                     options: .regularExpression) {
            let name = String(path[range].dropFirst().dropLast())
            guard let value = ProcessInfo.processInfo.environment[name] else {
                break
            }
            path.replaceSubrange(range, with: value)
        }
        guard !path.isEmpty else {
            setState { pathEditing = false; pathController = nil }
            return
        }
        // A bare drive means its root: "C:" alone is a CWD reference in
        // Win32 (it can resolve anywhere), and the root is what the user
        // typing it into an address bar meant.
        if path.count == 2, path.hasSuffix(":") { path += "\\" }
        if path.caseInsensitiveCompare("This PC") == .orderedSame {
            setState { pathEditing = false; pathController = nil }
            bloc.add(.open(kThisPCPath))
            return
        }
        var isDirectory: ObjCBool = false
        let exists = path.hasPrefix("::")
            || FileManager.default.fileExists(atPath: path,
                                              isDirectory: &isDirectory)
        guard exists else {
            // Explorer raises "Windows can't find" here; staying in the
            // field with the text intact is this window's quieter version
            // -- the typo is still there to fix, and Escape backs out.
            return
        }
        setState { pathEditing = false; pathController = nil }
        if path.hasPrefix("::") || isDirectory.boolValue
            || path.lowercased().hasSuffix(".zip") {
            // Directories, namespace locations and zips all navigate --
            // the listing routes each through the right enumerator.
            bloc.add(.open(path))
        } else {
            // A FILE typed into the address bar opens, as in Explorer.
            Task.detached { Win32AppCatalog.open(path) }
        }
    }

    /// Filters the listing in memory INSTANTLY, and walks the subtree
    /// behind it (FilesBloc._startSearch): the folder's own matches appear
    /// per keystroke, the deeper hits stream in below them named by
    /// relative path. Explorer asks the index; this is the honest
    /// cancellable-walk version, and the status bar says "searching…"
    /// while it runs.
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
                        SizedBox(width: self.colModified) {
                            headerCell("Date modified", .modified, true)
                        }
                        SizedBox(width: self.colType) { headerCell("Type", .type, true) }
                        SizedBox(width: self.colSize) { headerCell("Size", .size, false) }
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
        let entry = bloc.state.selected.flatMap { bloc.state.visibleByPath[$0] }
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
                        // Not in a namespace listing: both buttons run the
                        // association, and the path they would run it on is
                        // a "$R…" slot or a zip member -- neither is a file
                        // an app can be handed. Explorer offers no Open in
                        // its bin either.
                        if let entry, !entry.isDirectory, !bloc.state.isNamespace {
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
        if path == kThisPCPath { return "This PC" }
        // A namespace location has no last component worth showing -- the
        // shell names it, in the machine's own language.
        if path.hasPrefix("::") { return Win32Files.displayName(for: path) }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    private func crumbs() -> [(label: String, path: String)] {
        let path = bloc.state.directory
        guard !path.isEmpty else { return [] }
        if path == kThisPCPath {
            return [(label: "This PC", path: kThisPCPath)]
        }
        // A namespace root stands alone, like This PC: its real parent is
        // the Desktop, which this window has no view for, so a chain that
        // led anywhere would be leading somewhere that does not exist.
        // (Inside a zip is NOT this case -- that path is a real one and
        // walks textually to the drive, which is what Explorer shows too.)
        if path.hasPrefix("::") {
            return [(label: Win32Files.displayName(for: path), path: path)]
        }
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
        // "This PC" leads, as in Explorer -- and navigates to the computer
        // view now, like every other crumb.
        out.append((label: "This PC", path: kThisPCPath))
        return out.reversed()
    }

    private func itemCountLabel() -> String {
        if bloc.state.isThisPC {
            let count = bloc.state.driveDetails.count
            return count == 1 ? "1 item" : "\(count) items"
        }
        let shown = bloc.state.visible.count
        let total = bloc.state.entries.count
        if !bloc.state.filter.isEmpty {
            // The walk's honesty: "searching" while it runs, because 10%
            // done looks identical to finished -- and the count includes
            // the subtree hits riding below the folder's own matches.
            let counted = "\(shown) of \(total) items"
            return bloc.state.searching ? counted + "  ·  searching…"
                                        : counted
        }
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
        if bloc.state.isThisPC { return thisPCView() }
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

        // Lazy in every mode: a folder of ten thousand files builds only
        // what is on screen. Grid modes scroll by STRIP -- one ListView item
        // is a horizontal run of `columns` cells -- which keeps the laziness
        // and keeps every hit test on the shared ListingGrid arithmetic.
        //
        // KEYED BY MODE, deliberately: switching views must remount the
        // whole list. An in-place update rebuilds the inflated children
        // with the new builder, but a child whose root TYPE changed is a
        // remount inside the sliver -- and the sliver element's
        // insertRenderObjectChild is a no-op (children arrive through
        // createChild during layout), so the fresh render objects go
        // nowhere and the old mode keeps painting inside the new extents.
        // A fresh sliver takes the working path: mount, then lazy create.
        let g = listingGrid()
        if bloc.state.viewMode == .details {
            return ListView(
                key: ValueKey("details"),
                controller: scroll,
                itemExtent: kFilesRow,
                itemCount: bloc.state.visible.count,
                itemBuilder: { [weak self] _, index in self?.row(index) })
        }
        let strips = (bloc.state.visible.count + g.columns - 1) / g.columns
        return ListView(
            key: ValueKey("grid-\(g.cellW)x\(g.cellH)"),
            controller: scroll,
            itemExtent: g.cellH,
            itemCount: strips,
            itemBuilder: { [weak self] _, strip in self?.gridStrip(strip, g) })
    }

    /// One horizontal run of grid cells. The 8pt leading padding is
    /// ListingGrid.left's margin -- change one, change the other.
    private func gridStrip(_ strip: Int, _ g: ListingGrid) -> Widget {
        let visible = bloc.state.visible
        let start = strip * g.columns
        guard start < visible.count else { return SizedBox(height: g.cellH) }
        let end = min(start + g.columns, visible.count)
        return Padding(padding: EdgeInsets(left: 8, top: 0, right: 0, bottom: 0)) {
            Row(crossAxisAlignment: .stretch, spacing: 0) {
                for index in start..<end {
                    SizedBox(width: g.cellW, height: g.cellH) {
                        self.cell(visible[index])
                    }
                }
            }
        }
    }

    /// One grid cell: the selection slab, the hover, the tap -- the same
    /// contract as a Details row, in a different shape.
    private func cell(_ entry: Win32FileEntry) -> Widget {
        let mode = bloc.state.viewMode
        let selected = bloc.state.selection.contains(entry.path)
            || dropHover == entry.path
        let side = Double(mode.iconSide)
        let key = FilesBloc.iconKey(entry, side: mode.iconSide)
        return GestureDetector(
            onTap: { self.tapped(entry) },
            child: Hover { hovered in
                Padding(padding: EdgeInsets(horizontal: 2, vertical: 2)) {
                    ClipRRect(borderRadius: BorderRadius.circular(4)) {
                        ColoredBox(color: selected ? Win11.selection
                                   : (hovered ? Win11.hoverFill
                                              : Color(0x00000000))) {
                            if mode == .tiles {
                                self.tileContent(entry, key: key, side: side)
                            } else {
                                self.iconContent(entry, key: key, side: side)
                            }
                        }
                    }
                }
            })
    }

    /// The file's THUMBNAIL where one has landed, else the type's icon,
    /// else the same fallback glyphs the Details rows draw. The thumbnail
    /// arrives after the icon (it is a decode, queued behind the cheap
    /// answers), so a row upgrades in place as the texture lands.
    private func cellIcon(_ entry: Win32FileEntry, key: String,
                          side: Double) -> Widget {
        SizedBox(width: side, height: side) {
            Center {
                if let thumbKey = FilesBloc.thumbKey(
                       entry, side: bloc.state.viewMode.iconSide),
                   let thumb = self.bloc.icons.view(thumbKey, side: side) {
                    thumb
                } else if let icon = self.bloc.icons.view(key, side: side) {
                    icon
                } else {
                    MacosIcon(icon: entry.isDirectory ? FluentIcons.folderFill
                                                      : FluentIcons.page,
                              color: Win11.textFaint, size: side * 0.8)
                }
            }
        }
    }

    /// Icon views: the icon over up to two centred lines of name -- or the
    /// rename field, exactly where the name was, Explorer's own gesture.
    private func iconContent(_ entry: Win32FileEntry, key: String,
                             side: Double) -> Widget {
        Column(mainAxisAlignment: .center, crossAxisAlignment: .center) {
            cellIcon(entry, key: key, side: side)
            SizedBox(height: 5)
            Padding(padding: EdgeInsets(horizontal: 4, vertical: 0)) {
                if self.bloc.state.renaming == entry.path {
                    self.renameField(entry)
                } else {
                    Text(entry.name,
                         style: TextStyle(color: Win11.text, fontSize: 12),
                         textAlign: .center,
                         overflow: .ellipsis,
                         maxLines: 2)
                }
            }
        }
    }

    /// Tiles: the icon beside the name over the dimmed facts, Explorer's
    /// tile -- type for everything, size for files.
    private func tileContent(_ entry: Win32FileEntry, key: String,
                             side: Double) -> Widget {
        Padding(padding: EdgeInsets(horizontal: 8, vertical: 0)) {
            Row(crossAxisAlignment: .center, spacing: 9) {
                cellIcon(entry, key: key, side: side)
                Expanded {
                    Column(mainAxisAlignment: .center,
                           crossAxisAlignment: .start) {
                        if self.bloc.state.renaming == entry.path {
                            self.renameField(entry)
                        } else {
                            Text(entry.name,
                                 style: TextStyle(color: Win11.text,
                                                  fontSize: 12),
                                 overflow: .ellipsis,
                                 maxLines: 1)
                        }
                        Text(FilesBloc.typeLabel(entry),
                             style: TextStyle(color: Win11.textFaint,
                                              fontSize: 11),
                             maxLines: 1)
                        if !entry.isDirectory {
                            Text(self.sizeText(for: entry),
                                 style: TextStyle(color: Win11.textFaint,
                                                  fontSize: 11),
                                 maxLines: 1)
                        }
                    }
                }
            }
        }
    }

    // MARK: - This PC

    /// The tile highlight, local to the window rather than in the bloc's
    /// selection: drive tiles must never enter `selection`, because every
    /// file operation reads that set and a Ctrl+C with C:\ in it is a copy
    /// of the whole drive waiting for a paste.
    private var selectedDrive: String?

    /// Explorer's computer view, the honest subset: Devices and drives,
    /// each tile carrying the shell's name and the capacity bar. The
    /// folders section is absent because the sidebar already IS one.
    private func thisPCView() -> Widget {
        let drives = bloc.state.driveDetails
        if drives.isEmpty {
            return Column(mainAxisAlignment: .center,
                          crossAxisAlignment: .center) {
                SizedBox(width: 240) { MacosProgressIndicator() }
            }
        }
        let width = Win32WindowedHost.host?.clientSize?.width ?? kFilesWidth
        let perRow = max(1, Int((width - kFilesSidebar - 32) / kDriveTileW))
        let rows = stride(from: 0, to: drives.count, by: perRow).map {
            Array(drives[$0..<min($0 + perRow, drives.count)])
        }
        return Align(alignment: Alignment.topLeft) {
            Padding(padding: EdgeInsets(left: 16, top: 12, right: 16,
                                        bottom: 12)) {
                Column(crossAxisAlignment: .start) {
                    Text("Devices and drives",
                         style: TextStyle(color: Win11.text, fontSize: 13,
                                          fontWeight: .w600))
                    SizedBox(height: 10)
                    for row in rows {
                        Row(crossAxisAlignment: .center, spacing: 8) {
                            for drive in row { driveTile(drive) }
                        }
                    }
                }
            }
        }
    }

    private func driveTile(_ drive: Win32Drive) -> Widget {
        let path = drive.letter + ":\\"
        let selected = selectedDrive == path
        let fraction = drive.total > 0
            ? Double(drive.total - drive.free) / Double(drive.total) : 0
        // Explorer's own alarm: the bar turns red when the drive is nearly
        // full (under ten percent free).
        let low = drive.total > 0 && Double(drive.free) < Double(drive.total) * 0.1
        let barW = kDriveTileW - 40 - 12 - 16 - 8
        return GestureDetector(
            onTap: {
                let now = Date()
                let again = self.lastTapPath == path
                    && now.timeIntervalSince(self.lastTapAt) < 0.5
                self.lastTapPath = path
                self.lastTapAt = now
                if again {
                    self.lastTapPath = nil
                    self.bloc.add(.open(path))
                } else {
                    self.setState { self.selectedDrive = path }
                }
            },
            child: Hover { hovered in
                ClipRRect(borderRadius: BorderRadius.circular(4)) {
                    ColoredBox(color: selected ? Win11.selection
                               : (hovered ? Win11.hoverFill
                                          : Color(0x00000000))) {
                        SizedBox(width: kDriveTileW, height: 64) {
                            Padding(padding: EdgeInsets(horizontal: 8,
                                                        vertical: 0)) {
                                Row(crossAxisAlignment: .center, spacing: 12) {
                                    MacosIcon(icon: FluentIcons.drive,
                                              color: Win11.textDim, size: 36)
                                    Column(mainAxisAlignment: .center,
                                           crossAxisAlignment: .start) {
                                        Text(Win32Files.displayName(for: path),
                                             style: TextStyle(color: Win11.text,
                                                              fontSize: 12),
                                             maxLines: 1)
                                        SizedBox(height: 4)
                                        // The capacity bar: a track with the
                                        // used fraction filled, Explorer's.
                                        SizedBox(width: barW, height: 12) {
                                            ClipRRect(borderRadius:
                                                    BorderRadius.circular(2)) {
                                                Stack(alignment:
                                                        Alignment.topLeft) {
                                                    ColoredBox(
                                                        color: Win11.stroke) {
                                                        SizedBox(width: barW,
                                                                 height: 12)
                                                    }
                                                    ColoredBox(color: low
                                                        ? Color(0xFFDA3B01)
                                                        : Win11.accent) {
                                                        SizedBox(
                                                            width: barW * fraction,
                                                            height: 12)
                                                    }
                                                }
                                            }
                                        }
                                        SizedBox(height: 3)
                                        Text("\(self.sizeText(drive.free)) free of \(self.sizeText(drive.total))",
                                             style: TextStyle(
                                                 color: Win11.textFaint,
                                                 fontSize: 11),
                                             maxLines: 1)
                                    }
                                }
                            }
                        }
                    }
                }
            })
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
                                    if let thumbKey = FilesBloc.thumbKey(entry),
                                       let thumb = self.bloc.icons.view(
                                           thumbKey, side: 16) {
                                        thumb
                                    } else if let icon = self.bloc.icons.view(key, side: 16) {
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
                            SizedBox(width: self.colModified) {
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
                            SizedBox(width: self.colType) {
                                Align(alignment: Alignment.centerLeft) {
                                    Text(FilesBloc.typeLabel(entry),
                                         style: TextStyle(color: Win11.textFaint,
                                                          fontSize: 12),
                                         maxLines: 1)
                                }
                            }
                            SizedBox(width: self.colSize) {
                                Align(alignment: Alignment.centerRight) {
                                    Text(self.sizeText(for: entry),
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
        keyCursor = entry.path
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

    /// The Size cell for one row, EMPTY where there is nothing to measure.
    /// A directory has no size, and neither does a shell item with no file
    /// behind it -- a Network device answers 0 for PKEY_Size exactly as an
    /// empty file does, and "0 B" against a printer reads as a measurement
    /// rather than as the absence of one.
    private func sizeText(for entry: Win32FileEntry) -> String {
        if entry.isDirectory { return "" }
        if !entry.isFileSystem && entry.size == 0 { return "" }
        return sizeText(entry.size)
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
