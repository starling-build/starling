// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The file explorer's context menu: its state, its arithmetic, and its own
// widget.
//
// WHY IT IS A WIDGET OF ITS OWN, in the numbers that put it here. Profiled on
// the physical box, CPU burned per pointer move with a menu open:
//
//     across rows (a row changes)    3.91ms
//     within one row (nothing to do) 0.29ms
//     no menu open                   0.10ms
//
// Moving one highlight cost 3.9ms because the menu lived in the file
// explorer's own State: `setState` there rebuilds the WHOLE window -- sidebar,
// tab strip, command bar, breadcrumb, and a hundred-row listing -- to change
// which row is a shade lighter. At this monitor's 29Hz that is a tenth of a
// frame and invisible; on a 120Hz panel it is half a frame, spent on nothing.
//
// So the menu's state lives here, in an @Observable model, and the drawing
// lives in a StatefulWidget that watches it. A hover now rebuilds the menu
// subtree and nothing else. The file explorer keeps ONE thing -- what is under
// a given point in its listing, which only it knows -- and hands it over
// through `target`.
//
// The root Listener still drives it. Widget-level input does not arrive
// reliably in this surface (a GestureDetector inside a Positioned does not
// fire), so presses and hovers are hit-tested arithmetically from the top of
// the tree and forwarded here. That is why the geometry is a set of functions
// over a MenuCache rather than a layout: the press has no idea what a row is,
// and the drawing and the hit test must agree without one ever measuring the
// other.

#if os(Windows)
import CupertinoIcons
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import FlutterWin32Bridge
import Foundation
import Observation

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

/// A point in the window, in logical points.
struct MenuPoint {
    var x: Double
    var y: Double
}

/// What the surface found under a right-click. `nil` from `target` means the
/// point is not in the listing at all -- the sidebar, or one of the toolbars --
/// and no menu opens.
enum MenuTarget {
    /// The empty space below the rows: the FOLDER's menu, which is where New
    /// and the directory-background handlers live.
    case background
    case item(Win32FileEntry)
}

/// One drawn row.
struct MenuRow {
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

/// A menu's rows and every number derived from them.
///
/// STORED, NOT COMPUTED. The rows and their rectangles change when the menu
/// opens, when the shell answers and when a submenu fills in; they do not
/// change when the pointer moves. Deriving them per event measured 0.39ms of
/// CPU on every pointer move -- rebuilding sixteen rows with their closures
/// and re-measuring the panel, to answer "which row is this".
struct MenuCache {
    var rows: [MenuRow]
    var pill: Bool
    var width: Double
    var height: Double
    /// The top of each row in the panel's own coordinates, parallel to `rows`.
    var tops: [Double]
}

@Observable
final class ShellMenuModel {

    // MARK: - State
    //
    // Everything the panel DRAWS is observed; everything else is not. The
    // distinction is load-bearing in both directions -- see the caches below.

    /// The ANCHOR: the point that was clicked, clamped sideways so the panel
    /// fits. `flipped` says which edge of the panel is pinned to it. The
    /// corner the panel actually starts at is `origin`, computed from the
    /// two, because a flipped panel's top moves every time the shell hands
    /// over another verb.
    private(set) var anchor: MenuPoint?
    private(set) var flipped = false
    private(set) var entry: Win32FileEntry?
    private(set) var hover: Int?
    private(set) var pillHover: Int?

    /// What the shell came back with.
    private(set) var shellRows: [Win32ShellVerb] = []

    /// The open submenu, if any.
    private(set) var subAt: MenuPoint?
    private(set) var subRows: [Win32ShellVerb] = []
    private(set) var subHover: Int?

    /// What is under a point in the listing. Set by the surface, because the
    /// listing is the one thing here that belongs to it: which rows exist,
    /// and how far they have been scrolled.
    @ObservationIgnored var target: ((Double, Double) -> MenuTarget?)?

    /// The session assembling the verbs, and the generation that lets an
    /// answer for a menu already dismissed be dropped rather than drawn into
    /// the next one. NOT observed: nothing draws them, and a rebuild per
    /// session is a rebuild for nothing.
    @ObservationIgnored private var shell: Win32ShellMenu?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var subToken: Int32 = 0

    /// The derived geometry.
    ///
    /// @ObservationIgnored is NOT an optimization here, it is a correctness
    /// requirement: `mainMenu` fills this cache the first time it is read,
    /// and the first read happens inside the widget's build. An observed
    /// property written during a tracked build marks itself changed, which
    /// schedules another build, which writes it again. Derived state must be
    /// invisible to the tracker that the state it derives from drives.
    @ObservationIgnored private var mainCache: MenuCache?
    @ObservationIgnored private var subCache: MenuCache?

    var isOpen: Bool { anchor != nil }

    // MARK: - The verbs

    /// The verbs Windows lifts out of the list and into the icon row at the
    /// top, in its order. Matched on the CANONICAL verb rather than on the
    /// label: "Copy" is `copy` in every language, and `windows.modernshare`
    /// is the Share whose label is a single word in none of them.
    static let pillVerbs: [(verb: String, glyph: IconData)] = [
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
    static let verbGlyphs: [String: IconData] = [
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
    var hasPillRow: Bool { entry != nil }

    // MARK: - Opening

    /// Right-click. Returns false when the point is not somewhere a menu
    /// belongs, so the caller can leave the press alone.
    @discardableResult
    func open(at x: Double, _ y: Double) -> Bool {
        guard let target = target?(x, y) else { return false }
        let entry: Win32FileEntry?
        switch target {
        case .background: entry = nil
        case .item(let found): entry = found
        }
        let path = entry?.path ?? filesBloc.state.directory

        generation &+= 1
        let generation = self.generation
        let session = Win32ShellMenu(path: path, background: entry == nil,
                                     owner: Win32WindowedHost.host?.windowHandle ?? 0)
        session?.items { [weak self] rows in
            guard let self, self.generation == generation else { return }
            // Nothing to reposition: the panel is anchored to the corner the
            // pointer is at, and `origin` re-derives the other corner from
            // whatever the menu now weighs.
            self.shellRows = rows
            self.mainCache = nil
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
        let width = panelWidth(rows(for: entry, shell: []))
        if anchorX + width > size.width - kMenuEdge {
            anchorX = max(kMenuEdge, size.width - kMenuEdge - width)
        }

        shell?.close()
        shell = session
        shellRows = []
        subToken = 0
        subRows = []
        subAt = nil
        subHover = nil
        hover = nil
        pillHover = nil
        self.entry = entry
        anchor = MenuPoint(x: anchorX, y: y)
        flipped = flip
        mainCache = nil
        subCache = nil
        return true
    }

    func dismiss() {
        let session = shell
        shell = nil
        anchor = nil
        flipped = false
        entry = nil
        hover = nil
        pillHover = nil
        shellRows = []
        subAt = nil
        subToken = 0
        subRows = []
        subHover = nil
        mainCache = nil
        subCache = nil
        // Closed even when nothing was invoked -- the session is holding
        // other people's COM objects open, and the menu being dismissed
        // without a choice is the ordinary case.
        session?.close()
    }

    /// What the finished menu is expected to come to.
    ///
    /// MEASURED, not guessed: on this machine a file's menu comes to 542pt
    /// (the icon row, our three verbs, twelve shell rows and four rules) and
    /// a folder's to 613pt. An earlier cut reserved 439 and was wrong about
    /// every menu -- which showed up as the panel sitting 38pt above the
    /// click, because the clamp then had to move what the reservation had not
    /// made room for.
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

    // MARK: - The rows

    /// Our verbs, then the shell's. Our three are the ones that are live from
    /// the first frame and they never move; everything after the separator
    /// arrives later.
    ///
    /// Taken as parameters rather than read off the state, so the opening
    /// click can size a panel that does not exist yet -- it needs the width
    /// to clamp the anchor sideways, and at that moment the shell has
    /// answered nothing.
    private func rows(for entry: Win32FileEntry?,
                      shell shellVerbs: [Win32ShellVerb]) -> [MenuRow] {
        var rows: [MenuRow] = []
        if let entry {
            rows.append(MenuRow(title: "Open",
                                glyph: entry.isDirectory ? CupertinoIcons.folder_open
                                                         : CupertinoIcons.doc_text,
                                isDefault: true,
                                action: { filesBloc.add(.activate(entry)) }))
            if !entry.isDirectory {
                rows.append(MenuRow(title: "Open with…",
                                    glyph: CupertinoIcons.square_grid_2x2,
                                    action: { filesBloc.add(.openWith) }))
            }
            rows.append(MenuRow(title: "Show in Explorer",
                                glyph: CupertinoIcons.arrow_up_right,
                                action: {
                let path = entry.isDirectory ? entry.path : filesBloc.state.directory
                Task.detached { Win32Files.openInExplorer(path) }
            }))
        } else {
            rows.append(MenuRow(title: "Refresh", glyph: CupertinoIcons.arrow_2_circlepath,
                                action: { filesBloc.add(.open(filesBloc.state.directory)) }))
            rows.append(MenuRow(title: "Show in Explorer",
                                glyph: CupertinoIcons.arrow_up_right,
                                action: {
                let path = filesBloc.state.directory
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

    // MARK: - Geometry
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

    private func cache(_ rows: [MenuRow], pill: Bool) -> MenuCache {
        var tops: [Double] = []
        var y = kMenuPanelPad
        if pill { y += kMenuPillRow + kMenuSepH }
        for row in rows {
            tops.append(y)
            y += row.isSeparator ? kMenuSepH : kMenuRow
        }
        return MenuCache(rows: rows, pill: pill, width: panelWidth(rows),
                         height: y + kMenuPanelPad, tops: tops)
    }

    /// The open menu, and the open submenu.
    var mainMenu: MenuCache {
        if let cache = mainCache { return cache }
        let built = cache(rows(for: entry, shell: shellRows), pill: hasPillRow)
        mainCache = built
        return built
    }

    var subMenu: MenuCache {
        if let cache = subCache { return cache }
        let built = cache(shellList(subRows), pill: false)
        subCache = built
        return built
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
    func origin(_ menu: MenuCache) -> MenuPoint? {
        guard let anchor else { return nil }
        let size = Win32WindowedHost.host?.clientSize
            ?? (width: kFilesWidth, height: kFilesHeight)
        var y = flipped ? anchor.y - menu.height : anchor.y
        if y + menu.height > size.height - kMenuEdge {
            y = size.height - kMenuEdge - menu.height
        }
        if y < kMenuEdge { y = kMenuEdge }
        return MenuPoint(x: anchor.x, y: y)
    }

    /// Which row a point in a panel is over, given where the panel starts.
    private func rowIndex(_ menu: MenuCache, origin: MenuPoint,
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
    private func pillIndex(_ menu: MenuCache, origin: MenuPoint,
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
    func pillVerb(_ index: Int) -> Win32ShellVerb? {
        let wanted = Self.pillVerbs[index].verb
        return shellRows.first { $0.verb == wanted && !$0.isSeparator }
    }

    // MARK: - Input

    /// A press while the menu is open. Always dismisses; the questions are
    /// what it ran on the way out, and whether it opens another one.
    func press(_ x: Double, _ y: Double, buttons: Int) {
        let menu = mainMenu
        guard let at = origin(menu) else { return }
        let subs = subMenu

        var action: (() -> Void)?
        var shellId: Int32 = -1
        var hitAMenu = false

        if let subOrigin = subAt, let index = rowIndex(subs, origin: subOrigin, x, y) {
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

        // Taken out of the state BEFORE the dismissal, so `dismiss` does not
        // close the session the verb is about to run on. Both calls land on
        // the session's own serial queue, so the close is queued behind the
        // invoke and the handler is still alive while its verb runs.
        let session = shell
        shell = nil
        dismiss()
        action?()
        if shellId >= 0 { session?.invoke(shellId) }
        session?.close()

        // A right-click somewhere else does not merely dismiss: Windows moves
        // the menu to where the pointer now is, and so does this. Anything
        // less means the first of two right-clicks is silently wasted.
        if !hitAMenu && buttons == 2 { open(at: x, y) }
    }

    /// Hover, which is what opens a submenu -- Windows opens them on hover
    /// and so does this. Also the row highlight, which is the only feedback
    /// an arithmetic menu can give that it knows where the pointer is.
    func hovered(_ x: Double, _ y: Double) {
        let menu = mainMenu
        guard let at = origin(menu) else { return }
        let subs = subMenu

        if let subOrigin = subAt, let index = rowIndex(subs, origin: subOrigin, x, y) {
            if subHover != index { subHover = index }
            return
        }
        let over = rowIndex(menu, origin: at, x, y)
        let pill = pillIndex(menu, origin: at, x, y)
        if pillHover != pill { pillHover = pill }

        if let index = over, menu.rows[index].isSubmenu,
           menu.rows[index].token != subToken {
            expand(menu.rows[index], at: at, top: menu.tops[index], width: menu.width)
        } else if let index = over, subAt != nil,
                  !(menu.rows[index].isSubmenu && menu.rows[index].token == subToken) {
            subAt = nil
            subToken = 0
            subRows = []
            subCache = nil
        }
        let hovered = pill != nil ? nil : over
        if hover != hovered { hover = hovered }
        if subHover != nil && subAt == nil { subHover = nil }
    }

    /// Fills in a submenu and hangs it off the row.
    ///
    /// Asynchronous for the same reason the menu itself is, and it is not a
    /// formality: a submenu arrives EMPTY and its handler populates it only
    /// when told to. "New" on a folder background measured 301ms to fill in.
    private func expand(_ row: MenuRow, at parentOrigin: MenuPoint,
                        top: Double, width: Double) {
        let token = row.token
        guard token != 0, let session = shell else { return }
        let generation = self.generation
        subToken = token
        subRows = []
        subCache = nil
        subHover = nil
        // Overlapping the parent by a hair, as Windows' submenus do, so the
        // pointer can cross between them without falling through the gap and
        // closing the one it is heading for.
        subAt = MenuPoint(x: parentOrigin.x + width - 4,
                          y: parentOrigin.y + top - kMenuPanelPad)

        session.expand(token) { [weak self] rows in
            guard let self, self.generation == generation,
                  self.subToken == token else { return }
            self.subRows = rows
            self.subCache = nil
            // The child hangs off the parent's right edge and may run off the
            // window's; flip it to the parent's left, which is what Windows
            // does with the same problem.
            let size = Win32WindowedHost.host?.clientSize
                ?? (width: kFilesWidth, height: kFilesHeight)
            let child = self.subMenu
            if var at = self.subAt {
                if at.x + child.width > size.width - kMenuEdge {
                    at.x = max(kMenuEdge, parentOrigin.x - child.width + 4)
                }
                if at.y + child.height > size.height - kMenuEdge {
                    at.y = max(kMenuEdge, size.height - kMenuEdge - child.height)
                }
                self.subAt = at
            }
        }
    }
}

// MARK: - The widget
//
// Always mounted, drawing nothing when the menu is closed. Two reasons, and
// the second is the one that bites: a Stack that GAINS a child does not
// reliably composite it in this framework, and a widget that comes and goes
// would take the model's observation with it.

final class StarlingContextMenu: StatefulWidget {
    let model: ShellMenuModel

    init(model: ShellMenuModel) {
        self.model = model
        super.init()
    }

    override func createState() -> State<StatefulWidget> {
        ContextMenuState(model: model)
    }
}

final class ContextMenuState: State<StatefulWidget> {
    private let model: ShellMenuModel

    init(model: ShellMenuModel) {
        self.model = model
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        // The same tracking the surfaces use for their blocs -- and the whole
        // point of this file: what re-runs when the pointer moves is THIS
        // build, over at most two panels, rather than the file explorer's.
        withObservationTracking {
            _buildContent()
        } onChange: { [weak self] in
            guard let self, self.mounted else { return }
            self.setState {}
        }
    }

    private func _buildContent() -> Widget {
        Stack(alignment: Alignment.topLeft) {
            menuPanel()
            submenuPanel()
        }
    }

    private func menuPanel() -> Widget {
        let menu = model.mainMenu
        guard model.isOpen, let at = model.origin(menu) else {
            return SizedBox(width: 0, height: 0)
        }
        return Positioned(left: at.x, top: at.y) {
            panel(menu, hover: model.hover)
        }
    }

    private func submenuPanel() -> Widget {
        guard let at = model.subAt else { return SizedBox(width: 0, height: 0) }
        let menu = model.subMenu
        // Nothing to show yet: the handler is still filling it in. Drawing an
        // empty panel for those few hundred milliseconds is worse than
        // drawing none -- it reads as "this submenu is empty".
        guard !menu.rows.isEmpty else { return SizedBox(width: 0, height: 0) }
        return Positioned(left: at.x, top: at.y) {
            panel(menu, hover: model.subHover)
        }
    }

    /// The panel itself: Windows 11's rounded, bordered, near-opaque slab.
    private func panel(_ menu: MenuCache, hover: Int?) -> Widget {
        SizedBox(width: menu.width, height: menu.height) {
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
                        if menu.pill {
                            pillRow(width: menu.width)
                            separatorRow()
                        }
                        for (index, row) in menu.rows.enumerated() {
                            if row.isSeparator {
                                separatorRow()
                            } else {
                                menuRowWidget(row, hovered: hover == index)
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
        let cell = (width - kMenuPanelPad * 2) / Double(ShellMenuModel.pillVerbs.count)
        return SizedBox(height: kMenuPillRow) {
            Row(crossAxisAlignment: .center) {
                for (index, entry) in ShellMenuModel.pillVerbs.enumerated() {
                    let live = model.pillVerb(index)?.isEnabled == true
                    SizedBox(width: cell, height: kMenuPillRow) {
                        Center {
                            ClipRRect(borderRadius: BorderRadius.circular(4)) {
                                ColoredBox(color: model.pillHover == index && live
                                           ? Win11.menuHover : Color(0x00000000)) {
                                    SizedBox(width: 34, height: 32) {
                                        Center {
                                            MacosIcon(icon: entry.glyph,
                                                      color: live ? Win11.text
                                                                  : Win11.disabled,
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

    private func menuRowWidget(_ row: MenuRow, hovered: Bool) -> Widget {
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
}
#endif
