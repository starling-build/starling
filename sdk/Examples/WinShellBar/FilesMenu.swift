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
/// Tall enough for the icon AND its label -- Windows 11 writes "Cut",
/// "Copy", "Share", "Delete" under the glyphs, and an unlabeled row of four
/// pictograms was the most visible difference from the native menu.
let kMenuPillRow = 54.0
let kMenuIconX = 14.0
let kMenuLabelX = 44.0
let kMenuGlyph = 15.0
let kMenuMinW = 230.0
let kMenuMaxW = 400.0
/// The floor when the labeled icon row is present: six cells of glyph plus
/// label, at Windows' own proportions.
let kMenuPillMinW = 330.0
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
    /// Which of the session's two menus issued `shellId` and `token`. They
    /// number their verbs independently, so the id alone is not enough.
    var tier: Win32ShellMenuTier = .full
    /// The row rearranges the menu rather than choosing from it -- "Show
    /// more options". A press runs its action and leaves the menu open,
    /// where every other row's press dismisses first.
    var keepsOpen = false
    /// The right-aligned key hint ("Enter", "Ctrl+Shift+C"), drawn only
    /// because the key actually works -- see handleShortcut in Files.swift.
    /// A hint for a dead key would be worse than none.
    var accelerator = ""
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

    /// What the shell came back with, and which query it came from.
    ///
    /// TWO QUERIES, cheap one first. The same shell asked about only the
    /// item's own classes answers in 2ms for a document and 45ms for a
    /// folder, against 48-59ms for everything -- because a menu's cost is its
    /// handlers, and the expensive ones (Defender, OneDrive, Sharing) are
    /// registered against `*` and AllFilesystemObjects, which the cheap query
    /// does not ask about.
    ///
    /// Drawing the first and then the second is safe because the first is a
    /// STRICT SUBSET of the second, checked row by row: no row on screen ever
    /// changes meaning or disappears, the panel only grows. Which is not
    /// something a tier assembled by hand out of the registry could promise.
    private(set) var shellRows: [Win32ShellVerb] = []
    private(set) var shellTier: Win32ShellMenuTier = .fast

    /// Whether "Show more options" has been taken. The menu opens as
    /// Windows 11's MODERN menu -- the curated set -- and this flips it to
    /// the full legacy set. Unlike Windows, the flip is instant: the full
    /// set is already assembled (it is the same shell query), so there is no
    /// second 250ms query behind the click.
    private(set) var expanded = false

    /// Whether the clipboard held files when the menu opened, for the Paste
    /// cell. Asked once per open -- IsClipboardFormatAvailable, no clipboard
    /// open, no COM -- not per frame.
    private(set) var canPaste = false

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

    /// One cell of the icon row. Most are the SHELL's verbs -- matched on
    /// the canonical name, so "Copy" is `copy` in every language, and the
    /// label shown is the shell's own localized title once it answers --
    /// but Paste and Rename are OURS: no item menu carries a paste verb,
    /// and rename is an inline edit in the listing, not a shell call. They
    /// exist so the row reads like Windows 11's: Cut, Copy, Paste, Rename,
    /// Share, Delete.
    enum PillAction {
        case shell(String)
        case paste
        case rename
    }

    static let pillCells: [(action: PillAction, glyph: IconData, label: String)] = [
        (.shell("cut"), CupertinoIcons.scissors, "Cut"),
        (.shell("copy"), CupertinoIcons.doc_on_doc, "Copy"),
        (.paste, CupertinoIcons.doc_on_clipboard, "Paste"),
        (.rename, CupertinoIcons.pencil, "Rename"),
        (.shell("windows.modernshare"), CupertinoIcons.share, "Share"),
        (.shell("delete"), CupertinoIcons.trash, "Delete"),
    ]

    /// Shell verbs the list does not repeat: the row above, and the two we
    /// draw ourselves at the top.
    private var hiddenVerbs: Set<String> {
        var verbs: Set<String> = ["open", "openas"]
        for cell in Self.pillCells {
            if case .shell(let verb) = cell.action { verbs.insert(verb) }
        }
        return verbs
    }

    /// A glyph for the handful of shell verbs that have an obvious one. The
    /// rest draw none -- the shell hands its icons over as HBITMAPs belonging
    /// to a menu we are not running, and inventing a picture for "Restore
    /// previous versions" is worse than leaving the column empty.
    static let verbGlyphs: [String: IconData] = [
        "pintohome": CupertinoIcons.pin,
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
        // The cheap tier, which for a file is usually back before the first
        // frame is drawn.
        session?.items(.fast) { [weak self] rows in
            guard let self, self.generation == generation,
                  self.shellTier == .fast, !rows.isEmpty else { return }
            self.shellRows = rows
            self.mainCache = nil
        }
        // And the full one, which supersedes it.
        session?.items(.full) { [weak self] rows in
            guard let self, self.generation == generation, !rows.isEmpty else { return }
            // Nothing to reposition: the panel is anchored to the corner the
            // pointer is at, and `origin` re-derives the other corner from
            // whatever the menu now weighs.
            self.shellRows = rows
            self.shellTier = .full
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
        let width = panelWidth(rows(for: entry, shell: []), pill: entry != nil)
        if anchorX + width > size.width - kMenuEdge {
            anchorX = max(kMenuEdge, size.width - kMenuEdge - width)
        }

        shell?.close()
        shell = session
        shellRows = []
        shellTier = .fast
        expanded = false
        canPaste = Win32FileOps.clipboardHasFiles()
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
        shellTier = .fast
        expanded = false
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
    /// It decides ONE thing: whether the menu opens downward from the pointer
    /// or upward from it. Over-reserving costs a menu that flips up when it
    /// would just about have fitted downward; under-reserving costs a menu
    /// that opens downward and is then shoved back up the moment the verbs
    /// arrive, which is the jump this whole arrangement exists to avoid. So
    /// it errs high -- for the MODERN menu, which is what opens now: the icon
    /// row, our verbs, the curated shell rows and "Show more options" come to
    /// eleven rows and four rules on a folder here. The EXPANDED menu is
    /// deliberately not reserved for: the expansion is the user's own click,
    /// and the panel moving to fit then is Windows' behaviour too -- its
    /// legacy menu opens wherever it fits, not where the modern one stood.
    private var reservedHeight: Double {
        kMenuPanelPad * 2 + kMenuPillRow + kMenuSepH * 4 + kMenuRow * 11
    }

    // MARK: - The rows

    /// Our verbs, then the shell's -- shaped like Windows 11's menu: the
    /// MODERN set first (the curated verbs and the IExplorerCommand rows),
    /// with everything else behind "Show more options", which swaps in the
    /// full legacy set in place. Our verbs are the ones live from the first
    /// frame and they never move; the shell's arrive later.
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
                                accelerator: "Enter",
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

        if expanded {
            let shell = shellList(shellVerbs)
            if !shell.isEmpty {
                rows.append(MenuRow(isSeparator: true))
                rows.append(contentsOf: shell)
            }
        } else {
            let modern = modernList(shellVerbs)
            if !modern.isEmpty {
                rows.append(MenuRow(isSeparator: true))
                rows.append(contentsOf: modern)
            }
            rows.append(MenuRow(isSeparator: true))
            rows.append(MenuRow(title: "Show more options",
                                glyph: CupertinoIcons.ellipsis,
                                keepsOpen: true,
                                action: { [weak self] in self?.showMore() }))
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
            rows.append(shellRow(verb))
        }
        while let last = rows.last, last.isSeparator { rows.removeLast() }
        return rows
    }

    /// The accelerators Windows prints beside these verbs -- shown because
    /// the window really binds them (handleShortcut in Files.swift).
    private static let verbAccelerators: [String: String] = [
        "copyaspath": "Ctrl+Shift+C",
        "properties": "Alt+Enter",
    ]

    private func shellRow(_ verb: Win32ShellVerb) -> MenuRow {
        MenuRow(title: verb.title,
                glyph: Self.verbGlyphs[verb.verb],
                isSubmenu: verb.isSubmenu,
                isEnabled: verb.isEnabled,
                isDefault: false,
                shellId: verb.id,
                token: verb.submenu,
                tier: shellTier,
                accelerator: Self.verbAccelerators[verb.verb] ?? "")
    }

    /// The verbs Windows lifts into the MODERN menu, in its order there --
    /// checked against Explorer on this machine, not remembered: Pin to
    /// Quick access, Pin to Start, Copy as path, Properties, with the
    /// item-flavoured pin ("Add to Favorites") in the file's slot.
    private static let modernVerbs = [
        "paste", "pintohome", "pintohomefile", "pintostartscreen",
        "copyaspath", "properties",
    ]

    /// A canonical verb that is a GUID names an IExplorerCommand handler --
    /// the modern extension surface, which is exactly what Windows promotes
    /// into the modern menu ("Open in Terminal" is {9f156763-...}). The
    /// legacy handlers it demotes behind "Show more options" carry word
    /// verbs or none, so the brace is the partition, and it is
    /// locale-independent where a label match would not be.
    private func isModernCommand(_ verb: String) -> Bool {
        verb.hasPrefix("{") && verb.hasSuffix("}")
    }

    /// The shell rows the modern menu shows, curated the way Windows curates
    /// them: the allowlisted verbs in Windows' order, then the
    /// IExplorerCommand rows in the shell's. Everything else -- the static
    /// verbs, the classic handlers, every submenu -- waits behind "Show more
    /// options", which is where Windows keeps them too.
    private func modernList(_ verbs: [Win32ShellVerb]) -> [MenuRow] {
        var rows: [MenuRow] = []
        // The background's "New" leads its modern menu. Matched on the label
        // as a last resort: a submenu has no canonical verb to ask for. On a
        // non-English Windows the match misses and the row falls back behind
        // "Show more options" -- degraded, not broken.
        if entry == nil,
           let new = verbs.first(where: { $0.isSubmenu && $0.title == "New" }) {
            rows.append(shellRow(new))
        }
        for name in Self.modernVerbs {
            // An ITEM's paste lives in the icon row, as Windows draws it;
            // the row form is the BACKGROUND menu's (paste into the folder
            // you are standing in).
            if name == "paste" && entry != nil { continue }
            // Compress sits where Windows puts its own -- between the pins
            // and Copy as path. Ours because Windows does not offer its
            // modern Compress handler to menu hosts; tar.exe writes the
            // same zip (see Win32FileOps.compressToZip).
            if name == "copyaspath", let entry {
                rows.append(MenuRow(title: "Compress to ZIP file",
                                    glyph: CupertinoIcons.archivebox,
                                    action: { filesBloc.add(.compress(entry)) }))
            }
            if let verb = verbs.first(where: { !$0.isSeparator && $0.verb == name }) {
                rows.append(shellRow(verb))
            }
        }
        let commands = verbs.filter { !$0.isSeparator && isModernCommand($0.verb) }
        if !commands.isEmpty {
            if !rows.isEmpty { rows.append(MenuRow(isSeparator: true)) }
            rows.append(contentsOf: commands.map(shellRow))
        }
        return rows
    }

    /// "Show more options": swap the curated set for the whole one, in
    /// place. The full set is already in `shellRows` -- the curation is a
    /// view of it, not a separate query -- so unlike Windows there is
    /// nothing to wait for.
    func showMore() {
        guard !expanded else { return }
        expanded = true
        hover = nil
        subAt = nil
        subToken = 0
        subRows = []
        subHover = nil
        mainCache = nil
        subCache = nil
    }

    // MARK: - Geometry
    //
    // One set of numbers for the drawing and the hit test, built once per
    // change into a MenuCache. Nothing here measures anything: the press
    // arrives at the root Listener, which has no idea what a row is.

    private func panelWidth(_ rows: [MenuRow], pill: Bool) -> Double {
        // Estimated from the label lengths rather than measured -- there is no
        // text metric to ask here, and a panel sized to a fixed width either
        // clips "Restore previous versions" or is comically wide for "Open".
        // An accelerator rides the same row, so it buys its label more room.
        let longest = rows.map {
            $0.title.count + ($0.accelerator.isEmpty ? 0 : $0.accelerator.count + 4)
        }.max() ?? 0
        let wanted = kMenuLabelX + Double(longest) * kMenuCharW + 44
        // Six labeled icon cells need their own floor -- "Rename" under a
        // glyph in a 38pt cell is an ellipsis, not a label.
        let minimum = pill ? max(kMenuMinW, kMenuPillMinW) : kMenuMinW
        return min(kMenuMaxW, max(minimum, wanted))
    }

    private func cache(_ rows: [MenuRow], pill: Bool) -> MenuCache {
        var tops: [Double] = []
        var y = kMenuPanelPad
        if pill { y += kMenuPillRow + kMenuSepH }
        for row in rows {
            tops.append(y)
            y += row.isSeparator ? kMenuSepH : kMenuRow
        }
        return MenuCache(rows: rows, pill: pill, width: panelWidth(rows, pill: pill),
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
        let cell = (menu.width - kMenuPanelPad * 2) / Double(Self.pillCells.count)
        let index = Int((x - origin.x - kMenuPanelPad) / cell)
        return index >= 0 && index < Self.pillCells.count ? index : nil
    }

    /// The shell row behind a shell-backed icon cell, or nil when the cell
    /// is one of ours, or the shell has not offered the verb (or has not
    /// answered yet).
    func pillVerb(_ index: Int) -> Win32ShellVerb? {
        guard case .shell(let wanted) = Self.pillCells[index].action else {
            return nil
        }
        return shellRows.first { $0.verb == wanted && !$0.isSeparator }
    }

    /// Whether an icon cell is clickable right now, our cells included.
    func pillLive(_ index: Int) -> Bool {
        switch Self.pillCells[index].action {
        case .shell:
            return pillVerb(index)?.isEnabled == true
        case .paste:
            // Into the folder under the pointer, the way Windows' own row
            // works -- which is also why a plain file's cell stays grey.
            return canPaste && entry?.isDirectory == true
        case .rename:
            return entry != nil
        }
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
        var shellTierForInvoke: Win32ShellMenuTier = .full
        var hitAMenu = false

        if let subOrigin = subAt, let index = rowIndex(subs, origin: subOrigin, x, y) {
            hitAMenu = true
            if subs.rows[index].isEnabled {
                shellId = subs.rows[index].shellId
                shellTierForInvoke = subs.rows[index].tier
            }
        } else if let index = pillIndex(menu, origin: at, x, y) {
            hitAMenu = true
            if pillLive(index) {
                switch Self.pillCells[index].action {
                case .shell:
                    if let verb = pillVerb(index) {
                        shellId = verb.id
                        shellTierForInvoke = shellTier
                    }
                case .paste:
                    if let target = entry?.path {
                        action = { filesBloc.add(.paste(into: target)) }
                    }
                case .rename:
                    if let entry {
                        action = { filesBloc.add(.beginRename(entry)) }
                    }
                }
            }
        } else if let index = rowIndex(menu, origin: at, x, y) {
            hitAMenu = true
            let row = menu.rows[index]
            // A submenu row does nothing on a press: it opened on hover, the
            // way Windows' does, and the click the user means is the one on a
            // row inside it.
            if row.isSubmenu { return }
            // "Show more options" rearranges the menu instead of choosing
            // from it -- run it and keep the panel open.
            if row.keepsOpen {
                if row.isEnabled { row.action?() }
                return
            }
            if row.isEnabled {
                action = row.action
                shellId = row.shellId
                shellTierForInvoke = row.tier
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
        if shellId >= 0 { session?.invoke(shellTierForInvoke, shellId) }
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

        session.expand(row.tier, token) { [weak self] rows in
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
                    boxShadow: [BoxShadow(color: Win11.menuShadow,
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
        let cell = (width - kMenuPanelPad * 2) / Double(ShellMenuModel.pillCells.count)
        return SizedBox(height: kMenuPillRow) {
            Row(crossAxisAlignment: .center) {
                for (index, entry) in ShellMenuModel.pillCells.enumerated() {
                    let live = model.pillLive(index)
                    let colour = live ? Win11.text : Win11.disabled
                    SizedBox(width: cell, height: kMenuPillRow) {
                        Center {
                            ClipRRect(borderRadius: BorderRadius.circular(4)) {
                                ColoredBox(color: model.pillHover == index && live
                                           ? Win11.menuHover : Color(0x00000000)) {
                                    SizedBox(width: cell - 6, height: 46) {
                                        Column(mainAxisAlignment: .center) {
                                            MacosIcon(icon: entry.glyph,
                                                      color: colour,
                                                      size: kMenuGlyph)
                                            SizedBox(height: 3)
                                            // The shell's localized title for
                                            // its verbs once it has answered;
                                            // ours (Paste, Rename) carry their
                                            // own labels.
                                            Text(model.pillVerb(index)?.title
                                                     ?? entry.label,
                                                 style: TextStyle(color: colour,
                                                                  fontSize: 10),
                                                 overflow: .ellipsis, maxLines: 1)
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
                                       right: row.isSubmenu ? 26
                                           : (row.accelerator.isEmpty ? 10 : 100),
                                       bottom: 0) {
                                Align(alignment: Alignment.centerLeft) {
                                    Text(row.title,
                                         style: TextStyle(
                                            color: colour,
                                            fontSize: 13,
                                            fontWeight: row.isDefault ? .w600 : .w400),
                                         overflow: .ellipsis, maxLines: 1)
                                }
                            }
                            if !row.accelerator.isEmpty {
                                Positioned(top: 0, right: 12, bottom: 0) {
                                    Center {
                                        Text(row.accelerator,
                                             style: TextStyle(color: Win11.textFaint,
                                                              fontSize: 11))
                                    }
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
