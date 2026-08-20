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
// What is NOT here is the point of the exercise. Explorer's command bar verbs
// — new, cut, copy, paste, rename, delete — need IFileOperation and the undo
// and recycle-bin semantics that come with it, and none of that is written.
// Those buttons are therefore DRAWN DISABLED rather than drawn working: the
// layout is honest about the shape and honest about the capability, and a
// button that silently does nothing is worse than one that says it cannot.
// The verbs that ARE implemented — navigate, sort, filter, open, open-with,
// hand off to Explorer — are live.

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
let kFilesTabStrip = 38.0
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

/// Windows 11's context menu, at its own metrics. A rounded panel with a row
/// of icon verbs across the top, 32pt rows under it, and a highlight inset
/// from the panel's edge rather than filling it.
let kMenuRadius = 8.0
let kMenuPanelPad = 4.0
let kMenuRow = 32.0
let kMenuSepH = 7.0
let kMenuPillRow = 44.0
let kMenuIconX = 14.0
let kMenuLabelX = 44.0
let kMenuGlyph = 15.0
let kMenuMinW = 230.0
let kMenuMaxW = 400.0
/// Roughly what a character of the 13pt label costs, for sizing the panel to
/// its longest row. An estimate: there is no text metric to ask here.
let kMenuCharW = 6.6
/// How close to the window's edge a panel may sit.
let kMenuEdge = 6.0
let kFilesStatusBar = 34.0

/// The Details columns, at Explorer's proportions. Name takes what is left.
let kFilesColModified = 170.0
let kFilesColType = 130.0
let kFilesColSize = 90.0

/// Windows 11 dark, sampled from Explorer rather than invented, so the two
/// sitting side by side do not disagree about what "dark" is.
enum Win11 {
    static let windowBg = Color(0xFF202020)
    static let surface = Color(0xFF272727)
    static let navPane = Color(0xFF202020)
    static let listBg = Color(0xFF272727)
    static let stroke = Color(0xFF383838)
    static let text = Color(0xFFFFFFFF)
    static let textDim = Color(0xFFC5C5C5)
    static let textFaint = Color(0xFF8A8A8A)
    static let disabled = Color(0xFF5A5A5A)
    static let accent = Color(0xFF4CC2FF)
    static let selection = Color(0x332F9CF4)
    static let hoverFill = Color(0x14FFFFFF)
    static let fieldFill = Color(0xFF2D2D2D)
    /// The context menu, sampled from Explorer's own: a near-opaque slab with
    /// a lighter hairline around it, not the app's window colours.
    static let menuBg = Color(0xFA2C2C2C)
    static let menuBorder = Color(0xFF454545)
    static let menuHover = Color(0xFF383838)
    static let menuSep = Color(0xFF3D3D3D)
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

    /// The search box's text. Owned by the widget, not the bloc: the bloc
    /// holds the filter it produced, which is a different thing from what is
    /// currently in the field.
    private let search = TextEditingController()

    /// Where the context menu is, and what it is about. View state: it is
    /// this pointer's business and no other surface can see it.
    ///
    /// `menuAt` is the ANCHOR -- the point that was clicked, clamped
    /// sideways so the panel fits -- and `menuFlipped` says which edge of the
    /// panel is pinned to it. The corner the panel actually starts at is
    /// `menuOrigin`, computed from the two, because a flipped panel's top
    /// moves every time the shell hands over another verb.
    private var menuAt: (x: Double, y: Double)?
    private var menuFlipped = false
    private var menuEntry: Win32FileEntry?
    private var menuHover: Int?
    private var pillHover: Int?

    /// The shell's half of the menu: the session that is assembling the
    /// verbs, and what it has come back with. `menuGeneration` is bumped by
    /// every right-click, so an answer for a menu that has already been
    /// dismissed is dropped rather than drawn into the next one.
    private var shell: Win32ShellMenu?
    private var shellRows: [Win32ShellVerb] = []
    private var menuGeneration = 0

    /// The open submenu, if any.
    private var subToken: Int32 = 0
    private var subRows: [Win32ShellVerb] = []
    private var subAt: (x: Double, y: Double)?
    private var subHover: Int?

    override func initState() {
        super.initState()
        CupertinoIcons.registerFont()
        bloc.add(.start)
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
                    // 2 is the secondary button, and a PRESS rather than a
                    // release — the same choice the dock makes, for the same
                    // reason: the press is what arrives reliably, and every
                    // desktop opens its menus on it anyway.
                    if self.menuAt != nil {
                        self.handleMenu(e.position.dx, e.position.dy,
                                        buttons: e.buttons)
                        return
                    }
                    if e.buttons == 2 {
                        self.openMenu(at: e.position.dx, e.position.dy)
                    }
                },
                // The highlight, and what opens a submenu — Windows opens
                // them on hover and so does this. Only while a menu is down:
                // this fires for every pointer move over the whole window.
                onPointerHover: { e in
                    guard self.menuAt != nil else { return }
                    self.hoverMenu(e.position.dx, e.position.dy)
                },
                child: ColoredBox(color: Win11.windowBg) {
                Stack(alignment: Alignment.topLeft) {
                    Column(crossAxisAlignment: .stretch) {
                    tabStrip()
                    Expanded {
                    Row(crossAxisAlignment: .stretch) {
                        sidebar()
                        Expanded {
                            Column(crossAxisAlignment: .stretch) {
                                commandBar()
                                navigationBar()
                                columnHeaders()
                                Expanded {
                                    ColoredBox(color: Win11.listBg) { listing() }
                                }
                                statusBar()
                            }
                        }
                    }
                    }
                    }
                    // Always present, empty when closed: a Stack that GAINS a
                    // child does not reliably composite it.
                    menuAt != nil ? contextMenu() : SizedBox(width: 0, height: 0)
                    subAt != nil ? submenuPanel() : SizedBox(width: 0, height: 0)
                }
            }))
    }

    // MARK: - Context menu
    //
    // WINDOWS 11'S MENU, drawn by us and filled in by the shell.
    //
    // The shape is Explorer's: a rounded panel, a row of icon verbs across
    // the top, 32pt rows under it, a highlight inset from the panel's edge
    // rather than filling it, and a chevron on anything that opens a submenu.
    // Someone who knows the Windows menu should not have to learn this one.
    //
    // What is NOT Explorer's is when it appears. Every verb below the first
    // three comes from the SHELL -- the static verbs registered against the
    // file type, plus every installed IContextMenu handler -- and assembling
    // that set is what costs Explorer 370ms before it draws anything at all
    // (1134ms for the first menu after a window opens, as OneDrive's and
    // Defender's handler DLLs load). Measured here on one file: 756ms cold,
    // 595ms warm, for 18 rows.
    //
    // So the panel draws immediately with our own verbs and the shell's land
    // underneath when they arrive. Two consequences are deliberate:
    //
    //  - THE SPACE IS RESERVED BEFORE THEY DO. The origin is clamped against
    //    `reservedHeight` rather than against the three rows we can draw at
    //    once, so a menu opened near the bottom of the window is already
    //    sitting where the finished menu fits and does not jump out from
    //    under the pointer when the handlers answer.
    //  - THE ICON ROW COMES UP DISABLED. Cut, Copy, Share and Delete are the
    //    shell's verbs too; they are drawn greyed from the first frame and
    //    light up in place, so nothing below them moves.
    //
    // Rename is missing from that row on purpose. It is not a shell verb --
    // Explorer's own Rename comes from the folder VIEW, which is what edits
    // the name in the list -- and the shell offers us nothing to invoke. It
    // joins the row when the listing can rename in place.
    //
    // Hit-tested ARITHMETICALLY from the root Listener rather than with
    // GestureDetectors, as everything else in this surface is: a
    // GestureDetector inside a `Positioned` does not fire in this framework,
    // and a menu whose rows quietly do nothing is worse than no menu. One
    // geometry function, used by the drawing and by the hit test, so they
    // cannot drift apart.

    /// One drawn row.
    private struct MenuRow {
        var title = ""
        var glyph: IconData? = nil
        var isSeparator = false
        var isSubmenu = false
        var isEnabled = true
        /// What a double-click would do. Windows draws it in semibold.
        var isDefault = false
        /// The shell's command id, or -1 for one of ours.
        var shellId: Int32 = -1
        /// The token `expand` takes, for a submenu.
        var token: Int32 = 0
        var action: (() -> Void)? = nil
    }

    /// The verbs Windows lifts out of the list and into the icon row at the
    /// top, in its order. Matched on the CANONICAL verb rather than on the
    /// label: "Copy" is `copy` in every language, and `windows.modernshare`
    /// is the Share whose label is a single word in none of them.
    private static let pillVerbs: [(verb: String, glyph: IconData)] = [
        ("cut", CupertinoIcons.scissors),
        ("copy", CupertinoIcons.doc_on_doc),
        ("windows.modernshare", CupertinoIcons.share),
        ("delete", CupertinoIcons.trash),
    ]

    /// Shell verbs the list does not repeat: the four above, and the two we
    /// draw ourselves at the top.
    private var hiddenVerbs: Set<String> {
        Set(Self.pillVerbs.map(\.verb)).union(["open", "openas"])
    }

    /// A glyph for the handful of shell verbs that have an obvious one. The
    /// rest draw none -- the shell hands its icons over as HBITMAPs belonging
    /// to a menu we are not running, and inventing a picture for "Restore
    /// previous versions" is worse than leaving the column empty.
    private static let verbGlyphs: [String: IconData] = [
        "properties": CupertinoIcons.info,
        "copyaspath": CupertinoIcons.doc_on_clipboard,
        "link": CupertinoIcons.link,
        "print": CupertinoIcons.printer,
        "runas": CupertinoIcons.lock,
        "previousversions": CupertinoIcons.clock,
        "pintostartscreen": CupertinoIcons.pin,
        "pintohomefile": CupertinoIcons.star,
        "edit": CupertinoIcons.pencil,
    ]

    /// Whether the menu carries the icon row. An item's does; the folder
    /// background's does not, because none of those four verbs is about a
    /// folder you are standing in.
    private var hasPillRow: Bool { menuEntry != nil }

    /// A menu's rows and every number derived from them.
    ///
    /// STORED, NOT COMPUTED -- the same lesson the listing's sort projection
    /// learned, in the place it costs most. The rows and their rectangles
    /// change when the menu opens, when the shell answers and when a submenu
    /// fills in; they do not change when the pointer moves. Deriving them per
    /// event measured 0.39ms of CPU on EVERY pointer move, menu open, even
    /// for a move that changed nothing, because the hit test rebuilt sixteen
    /// rows and re-measured the panel to answer "which row is this".
    private struct MenuCache {
        var rows: [MenuRow]
        var pill: Bool
        var width: Double
        var height: Double
        /// The top of each row in the panel's own coordinates, parallel to
        /// `rows`.
        var tops: [Double]
    }

    private var mainCache: MenuCache?
    private var subMenuCache: MenuCache?

    /// Thrown away whenever something the rows are made of changes. Explicit
    /// rather than derived: `MenuRow` carries closures and cannot be compared,
    /// and a cache that quietly kept a stale row would be worse than none.
    private func invalidateMenu() {
        mainCache = nil
        subMenuCache = nil
    }

    private func build(_ rows: [MenuRow], pill: Bool) -> MenuCache {
        var tops: [Double] = []
        var y = kMenuPanelPad
        if pill { y += kMenuPillRow + kMenuSepH }
        for row in rows {
            tops.append(y)
            y += row.isSeparator ? kMenuSepH : kMenuRow
        }
        return MenuCache(rows: rows, pill: pill,
                         width: panelWidth(rows),
                         height: y + kMenuPanelPad,
                         tops: tops)
    }

    /// The open menu, and the open submenu.
    private var mainMenu: MenuCache {
        if let cache = mainCache { return cache }
        let cache = build(menuRowsFor(menuEntry, shell: shellRows), pill: hasPillRow)
        mainCache = cache
        return cache
    }

    private var subMenu: MenuCache {
        if let cache = subMenuCache { return cache }
        let cache = build(shellList(subRows), pill: false)
        subMenuCache = cache
        return cache
    }

    /// The row under a point, accounting for how far the list is scrolled.
    private func rowAt(_ x: Double, _ y: Double) -> Win32FileEntry? {
        guard x >= kFilesSidebar, y >= kFilesToolbar else { return nil }
        let index = Int((y - kFilesToolbar + scroll.offset) / kFilesRow)
        guard index >= 0, index < bloc.state.visible.count else { return nil }
        return bloc.state.visible[index]
    }

    /// Right-click. `entry` nil means the empty space below the listing,
    /// which gets the FOLDER's menu -- New and the handlers that install
    /// themselves on a directory background ("Open Git Bash here").
    private func openMenu(at x: Double, _ y: Double) {
        guard x >= kFilesSidebar, y >= kFilesToolbar else { return }
        let entry = rowAt(x, y)
        let path = entry?.path ?? bloc.state.directory
        menuGeneration &+= 1
        let generation = menuGeneration

        let session = Win32ShellMenu(path: path, background: entry == nil,
                                     owner: Win32WindowedHost.host?.windowHandle ?? 0)
        session?.items { [weak self] rows in
            guard let self, self.menuGeneration == generation else { return }
            // Nothing to reposition: the panel is anchored to the corner the
            // pointer is at, and menuOrigin re-derives the other corner from
            // whatever the menu now weighs.
            self.setState {
                self.shellRows = rows
                self.mainCache = nil
            }
        }

        // Which way it opens, decided HERE and not revisited. Windows flips a
        // menu that will not fit below the pointer so that its BOTTOM edge
        // sits at the pointer instead -- checked against Explorer on this
        // machine rather than remembered. The reservation is what makes that
        // decision possible before the verbs exist: the three rows we can
        // draw immediately would fit almost anywhere, so choosing the
        // direction from them would open downward on every click and then
        // discover it had nowhere to grow.
        let size = Win32WindowedHost.host?.clientSize
            ?? (width: kFilesWidth, height: kFilesHeight)
        let below = size.height - kMenuEdge - y
        let above = y - kMenuEdge
        let flip = below < reservedHeight && above > below
        var anchorX = x
        let width = panelWidth(menuRowsFor(entry, shell: []))
        if anchorX + width > size.width - kMenuEdge {
            anchorX = max(kMenuEdge, size.width - kMenuEdge - width)
        }

        setState {
            shell?.close()
            shell = session
            shellRows = []
            subToken = 0
            subRows = []
            subAt = nil
            menuHover = nil
            subHover = nil
            menuEntry = entry
            menuAt = (anchorX, y)
            menuFlipped = flip
            invalidateMenu()
        }
    }

    /// The panel's top-left corner, right now.
    ///
    /// Computed rather than stored, and that is the whole trick: a flipped
    /// panel is pinned by its BOTTOM edge, so its top moves upward every time
    /// the shell hands over more verbs while the corner under the pointer
    /// stays exactly where the user put it. An unflipped panel is pinned by
    /// its top and grows downward, which is the same statement mirrored.
    ///
    /// The clamps at the end are the case neither direction can save: a menu
    /// taller than the whole window. It then covers most of it, which is
    /// honest -- the real answer is a popup WINDOW, the way Windows' menu is
    /// one, so that it is not clipped by the window it was opened from. That
    /// is a second surface, and a bigger change than this.
    private func menuOrigin(_ menu: MenuCache) -> (x: Double, y: Double)? {
        guard let anchor = menuAt else { return nil }
        let size = Win32WindowedHost.host?.clientSize
            ?? (width: kFilesWidth, height: kFilesHeight)
        let height = menu.height
        var y = menuFlipped ? anchor.y - height : anchor.y
        if y + height > size.height - kMenuEdge {
            y = size.height - kMenuEdge - height
        }
        if y < kMenuEdge { y = kMenuEdge }
        return (anchor.x, y)
    }

    /// What the finished menu is expected to come to.
    ///
    /// MEASURED, not guessed: on this machine a file's menu comes to 542pt
    /// (the icon row, our three verbs, twelve shell rows and four rules) and
    /// a folder's to 613pt. The first cut reserved 439 and was wrong about
    /// every menu -- which showed up as the panel sitting 38pt above the
    /// click, because the clamp then had to move what the reservation had
    /// not made room for.
    ///
    /// It decides ONE thing: whether the menu opens downward from the pointer
    /// or upward from it. Over-reserving costs a menu that flips up when it
    /// would just about have fitted downward; under-reserving costs a menu
    /// that opens downward and is then shoved back up the moment the verbs
    /// arrive, which is the jump this whole arrangement exists to avoid. So
    /// it errs high.
    private var reservedHeight: Double {
        kMenuPanelPad * 2 + kMenuPillRow + kMenuSepH * 6 + kMenuRow * 14
    }

    /// Our verbs, then the shell's. Our three are the ones that are live from
    /// the first frame and they never move; everything after the separator
    /// arrives later.
    /// Taken as parameters rather than read off the state, so the opening
    /// click can size a panel that does not exist yet -- it needs the width
    /// to clamp the anchor sideways, and at that moment the shell has
    /// answered nothing.
    private func menuRowsFor(_ menuEntry: Win32FileEntry?,
                             shell shellVerbs: [Win32ShellVerb]) -> [MenuRow] {
        var rows: [MenuRow] = []
        if let entry = menuEntry {
            rows.append(MenuRow(title: "Open",
                                glyph: entry.isDirectory ? CupertinoIcons.folder_open
                                                         : CupertinoIcons.doc_text,
                                isDefault: true,
                                action: { self.bloc.add(.activate(entry)) }))
            if !entry.isDirectory {
                rows.append(MenuRow(title: "Open with…",
                                    glyph: CupertinoIcons.square_grid_2x2,
                                    action: { self.bloc.add(.openWith) }))
            }
            rows.append(MenuRow(title: "Show in Explorer",
                                glyph: CupertinoIcons.arrow_up_right,
                                action: {
                let path = entry.isDirectory ? entry.path : self.bloc.state.directory
                Task.detached { Win32Files.openInExplorer(path) }
            }))
        } else {
            rows.append(MenuRow(title: "Refresh", glyph: CupertinoIcons.arrow_2_circlepath,
                                action: { self.bloc.add(.open(self.bloc.state.directory)) }))
            rows.append(MenuRow(title: "Show in Explorer",
                                glyph: CupertinoIcons.arrow_up_right,
                                action: {
                let path = self.bloc.state.directory
                Task.detached { Win32Files.openInExplorer(path) }
            }))
        }

        let shell = shellList(shellVerbs)
        if !shell.isEmpty {
            rows.append(MenuRow(isSeparator: true))
            rows.append(contentsOf: shell)
        }
        return rows
    }

    /// The shell's rows, minus the ones drawn elsewhere, with the separators
    /// tidied afterwards.
    ///
    /// The tidy pass is not cosmetic: the shell separates its handlers into
    /// groups, and lifting Cut, Copy, Delete and Share out of them empties
    /// two of the groups completely. Without this the menu comes out with
    /// rules stacked against each other and a rule at the end.
    private func shellList(_ verbs: [Win32ShellVerb]) -> [MenuRow] {
        var rows: [MenuRow] = []
        let hidden = hiddenVerbs
        for verb in verbs {
            if verb.isSeparator {
                if rows.isEmpty || rows[rows.count - 1].isSeparator { continue }
                rows.append(MenuRow(isSeparator: true))
                continue
            }
            if !verb.verb.isEmpty && hidden.contains(verb.verb) { continue }
            rows.append(MenuRow(title: verb.title,
                                glyph: Self.verbGlyphs[verb.verb],
                                isSubmenu: verb.isSubmenu,
                                isEnabled: verb.isEnabled,
                                isDefault: false,
                                shellId: verb.id,
                                token: verb.submenu))
        }
        while let last = rows.last, last.isSeparator { rows.removeLast() }
        return rows
    }

    // MARK: - Menu geometry
    //
    // One set of numbers for the drawing and the hit test, built once per
    // change into a MenuCache. Nothing here measures anything: the press
    // arrives at the root Listener, which has no idea what a row is.

    private func panelWidth(_ rows: [MenuRow]) -> Double {
        // Estimated from the label lengths rather than measured -- there is no
        // text metric to ask here, and a panel sized to a fixed width either
        // clips "Restore previous versions" or is comically wide for "Open".
        let longest = rows.map(\.title.count).max() ?? 0
        let wanted = kMenuLabelX + Double(longest) * kMenuCharW + 44
        return min(kMenuMaxW, max(kMenuMinW, wanted))
    }

    /// Which row a point in a panel is over, given where the panel starts.
    private func rowIndex(_ menu: MenuCache, origin: (x: Double, y: Double),
                          _ x: Double, _ y: Double) -> Int? {
        guard x >= origin.x, x < origin.x + menu.width else { return nil }
        for (index, top) in menu.tops.enumerated() {
            let height = menu.rows[index].isSeparator ? kMenuSepH : kMenuRow
            if y >= origin.y + top && y < origin.y + top + height {
                return menu.rows[index].isSeparator ? nil : index
            }
        }
        return nil
    }

    /// Which icon in the top row a point is over, if any.
    private func pillIndex(_ menu: MenuCache, origin: (x: Double, y: Double),
                           _ x: Double, _ y: Double) -> Int? {
        guard menu.pill else { return nil }
        guard x >= origin.x, x < origin.x + menu.width,
              y >= origin.y + kMenuPanelPad,
              y < origin.y + kMenuPanelPad + kMenuPillRow else { return nil }
        let cell = (menu.width - kMenuPanelPad * 2) / Double(Self.pillVerbs.count)
        let index = Int((x - origin.x - kMenuPanelPad) / cell)
        return index >= 0 && index < Self.pillVerbs.count ? index : nil
    }

    /// The shell row behind one of the icons in the top row, or nil when the
    /// shell has not offered that verb (or has not answered yet).
    private func pillVerb(_ index: Int) -> Win32ShellVerb? {
        let wanted = Self.pillVerbs[index].verb
        return shellRows.first { $0.verb == wanted && !$0.isSeparator }
    }

    // MARK: - Menu input

    /// A press while the menu is open. Always dismisses; the questions are
    /// what it ran on the way out, and whether it opens another one.
    private func handleMenu(_ x: Double, _ y: Double, buttons: Int) {
        let menu = mainMenu
        guard let at = menuOrigin(menu) else { return }
        let subs = subMenu

        var action: (() -> Void)?
        var shellId: Int32 = -1
        var hitAMenu = false

        if let origin = subAt, let index = rowIndex(subs, origin: origin, x, y) {
            hitAMenu = true
            if subs.rows[index].isEnabled { shellId = subs.rows[index].shellId }
        } else if let index = pillIndex(menu, origin: at, x, y) {
            hitAMenu = true
            if let verb = pillVerb(index), verb.isEnabled { shellId = verb.id }
        } else if let index = rowIndex(menu, origin: at, x, y) {
            hitAMenu = true
            let row = menu.rows[index]
            // A submenu row does nothing on a press: it opened on hover, the
            // way Windows' does, and the click the user means is the one on a
            // row inside it.
            if row.isSubmenu { return }
            if row.isEnabled {
                action = row.action
                shellId = row.shellId
            }
        }

        // Taken out of the state BEFORE the dismissal, so dismissMenu does
        // not close the session the verb is about to run on. Both calls land
        // on the session's own serial queue, so the close is queued behind the
        // invoke and the handler is still alive while its verb runs.
        let session = shell
        shell = nil
        dismissMenu()
        action?()
        if shellId >= 0 { session?.invoke(shellId) }
        session?.close()

        // A right-click somewhere else does not merely dismiss: Windows moves
        // the menu to where the pointer now is, and so does this. Anything
        // less means the first of two right-clicks is silently wasted.
        if !hitAMenu && buttons == 2 { openMenu(at: x, y) }
    }

    /// Hover, which is what opens a submenu -- Windows opens them on hover
    /// and so does this. Also the row highlight, which is the only feedback
    /// an arithmetic menu can give that it knows where the pointer is.
    private func hoverMenu(_ x: Double, _ y: Double) {
        let menu = mainMenu
        guard let at = menuOrigin(menu) else { return }
        let subs = subMenu

        if let origin = subAt, let index = rowIndex(subs, origin: origin, x, y) {
            if subHover != index { setState { subHover = index } }
            return
        }
        let over = rowIndex(menu, origin: at, x, y)
        let pill = pillIndex(menu, origin: at, x, y)
        let hovered = pill != nil ? nil : over
        // The icon row highlights like any other row. This used to be
        // computed and dropped on the floor, so the four icons were the one
        // part of the menu that never acknowledged the pointer.
        if pillHover != pill { setState { pillHover = pill } }

        if let index = over, menu.rows[index].isSubmenu,
           menu.rows[index].token != subToken {
            openSubmenu(menu.rows[index], at: at, top: menu.tops[index],
                        width: menu.width)
        } else if let index = over, subAt != nil,
                  !(menu.rows[index].isSubmenu && menu.rows[index].token == subToken) {
            setState {
                subAt = nil
                subToken = 0
                subRows = []
                subMenuCache = nil
            }
        }
        if menuHover != hovered || subHover != nil {
            setState { menuHover = hovered; subHover = nil }
        }
    }

    /// Fills in a submenu and hangs it off the row.
    ///
    /// Asynchronous for the same reason the menu itself is, and it is not a
    /// formality: a submenu arrives EMPTY and its handler populates it only
    /// when told to. "New" on a folder background measured 301ms to fill in.
    private func openSubmenu(_ row: MenuRow, at origin: (x: Double, y: Double),
                             top: Double, width: Double) {
        let token = row.token
        guard token != 0, let session = shell else { return }
        let generation = menuGeneration
        setState {
            subToken = token
            subRows = []
            subMenuCache = nil
            subHover = nil
            // Overlapping the parent by a hair, as Windows' submenus do, so
            // the pointer can cross between them without falling through the
            // gap and closing the one it is heading for.
            subAt = (origin.x + width - 4, origin.y + top - kMenuPanelPad)
        }
        session.expand(token) { [weak self] rows in
            guard let self, self.menuGeneration == generation,
                  self.subToken == token else { return }
            self.setState {
                self.subRows = rows
                self.subMenuCache = nil
                // The child hangs off the parent's right edge and may run off
                // the window's; flip it to the parent's left, which is what
                // Windows does with the same problem.
                let size = Win32WindowedHost.host?.clientSize
                    ?? (width: kFilesWidth, height: kFilesHeight)
                // Built once, here, out of the rows that have just landed --
                // the same cache the hit test and the drawing then read.
                let child = self.subMenu
                if var at = self.subAt {
                    if at.x + child.width > size.width - kMenuEdge {
                        at.x = max(kMenuEdge, origin.x - child.width + 4)
                    }
                    if at.y + child.height > size.height - kMenuEdge {
                        at.y = max(kMenuEdge, size.height - kMenuEdge - child.height)
                    }
                    self.subAt = at
                }
            }
        }
    }

    private func dismissMenu() {
        let session = shell
        setState {
            menuAt = nil
            menuFlipped = false
            menuEntry = nil
            menuHover = nil
            pillHover = nil
            shell = nil
            shellRows = []
            subAt = nil
            subToken = 0
            subRows = []
            subHover = nil
            invalidateMenu()
        }
        // Closed even when nothing was invoked -- the session is holding
        // other people's COM objects open, and the menu being dismissed
        // without a choice is the ordinary case.
        session?.close()
    }

    // MARK: - Menu drawing

    private func contextMenu() -> Widget {
        let menu = mainMenu
        guard let at = menuOrigin(menu) else { return SizedBox(width: 0, height: 0) }
        return Positioned(left: at.x, top: at.y) {
            menuPanel(menu, hover: menuHover)
        }
    }

    private func submenuPanel() -> Widget {
        guard let at = subAt else { return SizedBox(width: 0, height: 0) }
        let menu = subMenu
        let rows = menu.rows
        // Nothing to show yet: the handler is still filling it in. Drawing an
        // empty panel for those few hundred milliseconds is worse than
        // drawing none -- it reads as "this submenu is empty".
        guard !rows.isEmpty else { return SizedBox(width: 0, height: 0) }
        return Positioned(left: at.x, top: at.y) {
            menuPanel(menu, hover: subHover)
        }
    }

    /// The panel itself: Windows 11's rounded, bordered, near-opaque slab.
    private func menuPanel(_ menu: MenuCache, hover: Int?) -> Widget {
        let width = menu.width
        let rows = menu.rows
        let pill = menu.pill
        return SizedBox(width: width, height: menu.height) {
            DecoratedBox(
                decoration: BoxDecoration(
                    color: Win11.menuBg,
                    border: Border.all(color: Win11.menuBorder, width: 1),
                    borderRadius: BorderRadius.circular(kMenuRadius),
                    boxShadow: [BoxShadow(color: Color(0x66000000),
                                          offset: Offset(0, 4), blurRadius: 12)]),
                child: Padding(padding: EdgeInsets(horizontal: kMenuPanelPad,
                                                   vertical: kMenuPanelPad)) {
                    Column(mainAxisSize: .min, crossAxisAlignment: .stretch) {
                        if pill {
                            pillRow(width: width)
                            separatorRow()
                        }
                        for (index, row) in rows.enumerated() {
                            if row.isSeparator {
                                separatorRow()
                            } else {
                                menuRowWidget(row, width: width,
                                              hovered: hover == index)
                            }
                        }
                    }
                })
        }
    }

    /// Windows 11's row of icon verbs across the top of the menu.
    ///
    /// Greyed until the shell answers, and then live in place. They are the
    /// shell's own Cut, Copy, Share and Delete -- which is what makes them
    /// worth having: the recycle bin, the undo stack and the clipboard
    /// formats are the shell's, and reimplementing any of that around
    /// IFileOperation to fill this row would be building a worse copy of
    /// something already installed.
    private func pillRow(width: Double) -> Widget {
        let cell = (width - kMenuPanelPad * 2) / Double(Self.pillVerbs.count)
        return SizedBox(height: kMenuPillRow) {
            Row(crossAxisAlignment: .center) {
                for (index, entry) in Self.pillVerbs.enumerated() {
                    SizedBox(width: cell, height: kMenuPillRow) {
                        Center {
                            ClipRRect(borderRadius: BorderRadius.circular(4)) {
                                ColoredBox(color: pillHover == index
                                           && pillVerb(index)?.isEnabled == true
                                           ? Win11.menuHover : Color(0x00000000)) {
                                    SizedBox(width: 34, height: 32) {
                                        Center {
                                            MacosIcon(icon: entry.glyph,
                                                      color: pillVerb(index)?.isEnabled == true
                                                          ? Win11.text : Win11.disabled,
                                                      size: kMenuGlyph)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// The rule between two groups of verbs.
    ///
    /// No `Center` around it, which is what the first cut had: a Center gives
    /// its child the child's OWN width, and a `SizedBox(height:)` has none --
    /// so the line was one pixel tall, zero wide, and the menu came out with
    /// gaps where its rules should be. The Padding's constraint is the full
    /// panel width, and the box takes it.
    private func separatorRow() -> Widget {
        SizedBox(height: kMenuSepH) {
            Padding(padding: EdgeInsets(left: 10, top: 3, right: 10, bottom: 3)) {
                ColoredBox(color: Win11.menuSep) { SizedBox(height: 1) }
            }
        }
    }

    private func menuRowWidget(_ row: MenuRow, width: Double, hovered: Bool) -> Widget {
        let colour = row.isEnabled ? Win11.text : Win11.disabled
        return SizedBox(height: kMenuRow) {
            Padding(padding: EdgeInsets(horizontal: 1, vertical: 1)) {
                ClipRRect(borderRadius: BorderRadius.circular(4)) {
                    ColoredBox(color: hovered && row.isEnabled
                               ? Win11.menuHover : Color(0x00000000)) {
                        Stack(alignment: Alignment.centerLeft) {
                            Positioned(left: kMenuIconX, top: 0, bottom: 0) {
                                Center {
                                    if let glyph = row.glyph {
                                        MacosIcon(icon: glyph, color: colour,
                                                  size: kMenuGlyph)
                                    } else {
                                        SizedBox(width: kMenuGlyph, height: kMenuGlyph)
                                    }
                                }
                            }
                            Positioned(left: kMenuLabelX, top: 0,
                                       right: row.isSubmenu ? 26 : 10, bottom: 0) {
                                Align(alignment: Alignment.centerLeft) {
                                    Text(row.title,
                                         style: TextStyle(
                                            color: colour,
                                            fontSize: 13,
                                            fontWeight: row.isDefault ? .w600 : .w400),
                                         overflow: .ellipsis, maxLines: 1)
                                }
                            }
                            if row.isSubmenu {
                                Positioned(top: 0, right: 10, bottom: 0) {
                                    Center {
                                        MacosIcon(icon: CupertinoIcons.chevron_right,
                                                  color: Win11.textDim, size: 10)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sidebar

    private func sidebar() -> Widget {
        SizedBox(width: kFilesSidebar) {
            ColoredBox(color: Win11.navPane) {
                Padding(padding: EdgeInsets(left: 8, top: 6, right: 8, bottom: 8)) {
                    Column(crossAxisAlignment: .stretch) {
                        sidebarHeading("Home")
                        for place in bloc.state.places { placeRow(place) }
                        SizedBox(height: 12)
                        sidebarHeading("This PC")
                        for drive in bloc.state.drives { placeRow(drive) }
                    }
                }
            }
        }
    }

    private func sidebarHeading(_ text: String) -> Widget {
        Padding(padding: EdgeInsets(left: 10, top: 0, right: 10, bottom: 6)) {
            Text(text, style: TextStyle(color: Win11.textFaint, fontSize: 11,
                                        fontWeight: .w600))
        }
    }

    private func placeRow(_ place: Win32Place) -> Widget {
        let selected = bloc.state.directory == place.path
        return GestureDetector(
            onTap: { self.bloc.add(.open(place.path)) },
            child: Padding(padding: EdgeInsets(left: 0, top: 1, right: 0, bottom: 1)) {
                ClipRRect(borderRadius: BorderRadius.circular(6)) {
                    ColoredBox(color: selected ? Color(0x2E6FA8FF) : Color(0x00000000)) {
                        SizedBox(height: 30) {
                            Padding(padding: EdgeInsets(horizontal: 10, vertical: 0)) {
                                Row(crossAxisAlignment: .center, spacing: 9) {
                                    MacosIcon(icon: CupertinoIcons.folder_fill,
                                              color: Color(0xFF7FA9DE), size: 14)
                                    Text(place.name,
                                         style: TextStyle(color: Color(0xFFE6EAF0),
                                                          fontSize: 13),
                                         maxLines: 1)
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
    private func tabStrip() -> Widget {
        SizedBox(height: kFilesTabStrip) {
            Padding(padding: EdgeInsets(left: 8, top: 6, right: 8, bottom: 0)) {
                Row(crossAxisAlignment: .stretch) {
                    ClipRRect(borderRadius: BorderRadius.circular(6)) {
                        ColoredBox(color: Win11.surface) {
                            Padding(padding: EdgeInsets(horizontal: 12, vertical: 0)) {
                                Row(crossAxisAlignment: .center, spacing: 8) {
                                    MacosIcon(icon: CupertinoIcons.folder_fill,
                                              color: Win11.textDim, size: 13)
                                    Text(folderLabel(),
                                         style: TextStyle(color: Win11.text, fontSize: 12),
                                         maxLines: 1)
                                }
                            }
                        }
                    }
                    Expanded { SizedBox(height: 1) }
                }
            }
        }
    }

    /// The command bar. Everything on it that needs IFileOperation is drawn
    /// disabled -- see this file's header.
    private func commandBar() -> Widget {
        SizedBox(height: kFilesCommandBar) {
            Padding(padding: EdgeInsets(left: 10, top: 0, right: 10, bottom: 0)) {
                Row(crossAxisAlignment: .center, spacing: 2) {
                    barButton(CupertinoIcons.add, "New", enabled: false) {}
                    barSeparator()
                    barIcon(CupertinoIcons.scissors, enabled: false) {}
                    barIcon(CupertinoIcons.doc_on_doc, enabled: false) {}
                    barIcon(CupertinoIcons.doc_on_clipboard, enabled: false) {}
                    barIcon(CupertinoIcons.pencil, enabled: false) {}
                    barIcon(CupertinoIcons.trash, enabled: false) {}
                    barSeparator()
                    barButton(CupertinoIcons.arrow_up_arrow_down, sortLabel(), enabled: true) {
                        self.cycleSort()
                    }
                    barButton(CupertinoIcons.square_grid_2x2, "View", enabled: false) {}
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
                    navIcon(CupertinoIcons.chevron_left, enabled: bloc.canGoBack) {
                        self.bloc.add(.goBack)
                    }
                    navIcon(CupertinoIcons.chevron_right, enabled: bloc.canGoForward) {
                        self.bloc.add(.goForward)
                    }
                    navIcon(CupertinoIcons.chevron_up, enabled: bloc.state.canGoUp) {
                        self.bloc.add(.goUp)
                    }
                    navIcon(CupertinoIcons.arrow_clockwise, enabled: true) {
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
                            for (i, crumb) in parts.enumerated() {
                                if i > 0 {
                                    MacosIcon(icon: CupertinoIcons.chevron_right,
                                              color: Win11.textFaint, size: 9)
                                }
                                GestureDetector(
                                    onTap: { self.bloc.add(.open(crumb.path)) },
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
                placeholder: "Search this folder",
                prefix: Padding(padding: EdgeInsets(left: 6, top: 0, right: 0, bottom: 0)) {
                    MacosIcon(icon: CupertinoIcons.search, color: Win11.textFaint, size: 12)
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
                            headerCell("Date modified", .modified, false)
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
                                      ? CupertinoIcons.chevron_up
                                      : CupertinoIcons.chevron_down,
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
        return SizedBox(height: kFilesStatusBar) {
            ColoredBox(color: Win11.windowBg) {
                Padding(padding: EdgeInsets(left: 14, top: 0, right: 10, bottom: 0)) {
                    Row(crossAxisAlignment: .center, spacing: 12) {
                        Text(itemCountLabel(),
                             style: TextStyle(color: Win11.textFaint, fontSize: 11),
                             maxLines: 1)
                        if entry != nil {
                            Text("1 item selected",
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
            child: SizedBox(width: 34, height: 30) {
                Center {
                    MacosIcon(icon: icon,
                              color: enabled ? Win11.textDim : Win11.disabled,
                              size: 14)
                }
            })
    }

    private func barButton(_ icon: IconData, _ label: String, enabled: Bool,
                           _ action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: enabled ? action : {},
            child: SizedBox(height: 30) {
                Padding(padding: EdgeInsets(horizontal: 9, vertical: 0)) {
                    Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 6) {
                        MacosIcon(icon: icon,
                                  color: enabled ? Win11.textDim : Win11.disabled,
                                  size: 13)
                        Text(label,
                             style: TextStyle(
                                color: enabled ? Win11.textDim : Win11.disabled,
                                fontSize: 12))
                    }
                }
            })
    }

    private func navIcon(_ icon: IconData, enabled: Bool,
                         _ action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: enabled ? action : {},
            child: SizedBox(width: 32, height: 32) {
                Center {
                    MacosIcon(icon: icon,
                              color: enabled ? Win11.textDim : Win11.disabled,
                              size: 13)
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
            let name = (here as NSString).lastPathComponent
            out.append((label: name.isEmpty ? here : name, path: here))
            walk = Win32Files.parent(of: here)
        }
        return out.reversed()
    }

    private func itemCountLabel() -> String {
        let shown = bloc.state.visible.count
        let total = bloc.state.entries.count
        if !bloc.state.filter.isEmpty { return "\(shown) of \(total) items" }
        return total == 1 ? "1 item" : "\(total) items"
    }

    private func sortLabel() -> String {
        switch bloc.state.sortKey {
        case .name: return "Sort: Name"
        case .modified: return "Sort: Date"
        case .type: return "Sort: Type"
        case .size: return "Sort: Size"
        }
    }

    /// The command bar's Sort button walks the four columns, so the control is
    /// reachable without going to the header row.
    private func cycleSort() {
        switch bloc.state.sortKey {
        case .name: bloc.add(.sort(.modified))
        case .modified: bloc.add(.sort(.type))
        case .type: bloc.add(.sort(.size))
        case .size: bloc.add(.sort(.name))
        }
    }

    private func textButton(_ text: String, _ action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: action,
            child: ClipRRect(borderRadius: BorderRadius.circular(6)) {
                ColoredBox(color: Color(0x1AFFFFFF)) {
                    SizedBox(height: 28) {
                        Padding(padding: EdgeInsets(horizontal: 12, vertical: 0)) {
                            Center {
                                Text(text, style: TextStyle(color: Color(0xFFD5DAE3),
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

    private func row(_ index: Int) -> Widget {
        guard index < bloc.state.visible.count else { return SizedBox(height: kFilesRow) }
        let entry = bloc.state.visible[index]
        let selected = bloc.state.selected == entry.path
        let key = FilesBloc.iconKey(entry)

        return GestureDetector(
            onTap: { self.tapped(entry) },
            child: ColoredBox(color: selected ? Win11.selection : Color(0x00000000)) {
                SizedBox(height: kFilesRow) {
                    Padding(padding: EdgeInsets(left: 16, top: 0, right: 16, bottom: 0)) {
                        Row(crossAxisAlignment: .center, spacing: 10) {
                            SizedBox(width: 18, height: 18) {
                                Center {
                                    if let icon = bloc.icons.view(key, side: 16) {
                                        icon
                                    } else {
                                        MacosIcon(icon: entry.isDirectory
                                                      ? CupertinoIcons.folder_fill
                                                      : CupertinoIcons.doc,
                                                  color: Win11.textFaint, size: 14)
                                    }
                                }
                            }
                            Expanded {
                                Text(entry.name,
                                     style: TextStyle(color: Win11.text, fontSize: 12),
                                     maxLines: 1)
                            }
                            SizedBox(width: kFilesColModified) {
                                Align(alignment: Alignment.centerRight) {
                                    Text(modifiedText(entry),
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
                                    Text(entry.isDirectory ? "" : sizeText(entry.size),
                                         style: TextStyle(color: Win11.textFaint,
                                                          fontSize: 12),
                                         maxLines: 1)
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

    private func modifiedText(_ entry: Win32FileEntry) -> String {
        guard let date = entry.modified else { return "" }
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy  HH:mm"
        return f.string(from: date)
    }
}
#endif
