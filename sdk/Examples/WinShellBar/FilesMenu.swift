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
// THE PANELS ARE POPUP WINDOWS now (Win32PopupSurfaces): each open panel is
// its own engine view in its own WS_POPUP window, placed at the model's
// window-space geometry, so a menu overhangs the window's edges and outgrows
// its height the way Windows' own does. The model neither knows nor cares --
// its arithmetic stays in window coordinates; the popup content translates
// its local pointer events back by the panel's origin on the way in
// (MenuPanelSurface), and syncPopups translates geometry out on the way to
// the window placement. The in-window drawing survives as the fallback for
// a machine where a second engine view cannot be created (popupsEnabled).
//
// The window's root Listener still drives the WINDOW side: a press there
// while a menu is open dismisses it (and is eaten), which is also what makes
// right-click-elsewhere move the menu. Hit tests stay arithmetic functions
// over a MenuCache rather than a layout: the popup Listener's press has no
// idea what a row is either, and the drawing and the hit test must agree
// without one ever measuring the other.

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

/// A placed panel, for deciding whether its popup window needs moving.
struct MenuRect: Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
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

/// EXPERIMENT (`STARLING_MENU_LAYER=1`): the menu's panels as a LAYER of the
/// shell's chrome instead of popup windows of their own.
///
/// A menu needs a window for one reason — it has to overhang the window it
/// was opened from — and hosted in the shell that reason is gone: the chrome
/// window is already the whole screen (`oneview: overhang … (full screen)`),
/// `WS_EX_LAYERED` with `LWA_COLORKEY` on pure black, so pixels the tree
/// paints are hit-tested and everything else falls through to whatever is
/// behind. It is how the launcher is a layer rather than a window.
///
/// What it is meant to buy: the popup's place+show, a second engine view's
/// composite, and one more DWM surface to present. What it cannot cover is
/// every other host — the standalone file explorer process, notifications,
/// banners, Run — which have no full-screen chrome, so the popup path stays.
///
/// The panels are published in the HOST window's client points, which for
/// the full-screen chrome are the screen's: exactly the space syncPopups
/// already converts into.
@Observable
final class MenuLayerHost {
    struct Panel: Equatable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
    }

    nonisolated(unsafe) static let shared = MenuLayerHost()

    /// Off unless asked for: this is an experiment measured against the
    /// popup path, not a second default.
    nonisolated(unsafe) static let enabled =
        ProcessInfo.processInfo.environment["STARLING_MENU_LAYER"] == "1"

    /// The model whose panels the chrome should draw, and where. Both are
    /// set together; nil model means nothing is open.
    var model: ShellMenuModel?
    var main: Panel?
    var sub: Panel?

    func clear() {
        guard model != nil || main != nil || sub != nil else { return }
        model = nil
        main = nil
        sub = nil
    }
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
    /// True while `shellRows` is a TYPE-CACHE seed: the full rows of the
    /// last same-typed menu, painted so the panel is complete on frame one.
    /// Seeded rows carry no verb ids (their session is gone), so they draw
    /// but cannot invoke; the real per-file query replaces them within a
    /// few tens of ms and clears this.
    private(set) var shellRowsSeeded = false
    /// The real fast-tier rows received while a seed was displayed — held
    /// as the hang failsafe's fallback, since they carry LIVE verb ids and
    /// the seed's do not.
    @ObservationIgnored private var seedFallbackRows: [Win32ShellVerb]?
    /// COLD open (no type-cache seed): the popup stays hidden until the
    /// fast tier lands, instead of revealing builtin-only rows that the
    /// tiers then visibly rewrite — greyed Cut/Copy flipping enabled and
    /// the menu growing twice was the one flicker the pixel gate caught.
    /// Warm opens never set this (the seed IS the settled shape), so the
    /// instant-reveal policy below is untouched where it matters; a cold
    /// one waits the fast tier's few ms (~100ms on a fresh process, whose
    /// first query loads the shell extension DLLs) with a 300ms failsafe
    /// so a hung handler still gets an honest builtin menu, not a strand.
    @ObservationIgnored private var revealHeld = false

    /// The type cache, keyed by what actually determines a menu: the
    /// ASSOCIATION CLASSES. Static verbs are registry data per type;
    /// dynamic handlers' rows are type-stable in the overwhelming case, and
    /// the real query still runs per open to catch the exceptions. Nil key
    /// = do not cache (namespace listings: the bin's menu is per-slot).
    @ObservationIgnored private static var typeCache:
        [String: [Win32ShellVerb]] = [:]

    private static func typeKey(_ entry: Win32FileEntry?,
                                namespace: Bool) -> String? {
        guard !namespace else { return nil }
        guard let entry else { return "\u{1}background" }
        if entry.isDirectory { return "\u{1}directory" }
        // entry.ext, NEVER derived from the path here: it is already
        // lowercased, dot-free, and computed by the listing with the exact
        // semantics the icon cache fought for — NSString.pathExtension on a
        // backslashed Windows path can mis-split (a dotted directory above
        // an extensionless file yields a garbage key).
        return entry.ext.isEmpty ? "\u{1}noext" : entry.ext
    }

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

    /// FLYOUT mode: the same panel, hit test and hover, fed rows directly
    /// instead of from a shell session -- what the command bar's New and
    /// Sort dropdowns open. Non-nil replaces everything rows(for:) would
    /// assemble; there is no pill, no tiers, no session to close.
    private(set) var flyoutRows: [MenuRow]?

    /// The open submenu, if any.
    private(set) var subAt: MenuPoint?
    private(set) var subRows: [Win32ShellVerb] = []
    private(set) var subHover: Int?

    /// What is under a point in the listing. Set by the surface, because the
    /// listing is the one thing here that belongs to it: which rows exist,
    /// and how far they have been scrolled.
    @ObservationIgnored var target: ((Double, Double) -> MenuTarget?)?

    /// Runs after a shell verb completes. A verb moves files without telling
    /// anyone and nothing watches a directory, so the SURFACE re-reads its
    /// own listing here — the file explorer's default below; the desktop
    /// grid replaces it with its own refresh. (The pin re-read rides along
    /// for the explorer because "Pin to Quick access" is one of these verbs.)
    @ObservationIgnored var afterVerb: () -> Void = {
        filesBloc.add(.refresh)
        filesBloc.reloadPins()
    }

    /// The directory a BACKGROUND click means, and what Open / Open with…
    /// do — the three other places the menu used to reach straight into the
    /// file explorer's bloc. Parameterized for the desktop surface, whose
    /// process carries only a dormant FilesBloc: its background is the
    /// Desktop folder and its Open is a ShellExecute, and reading the
    /// dormant bloc's empty directory here is how the desktop's first
    /// background menu came up with no shell verbs at all.
    @ObservationIgnored var backgroundDirectory: () -> String = {
        filesBloc.state.directory
    }
    @ObservationIgnored var activate: (Win32FileEntry) -> Void = {
        filesBloc.add(.activate($0))
    }
    @ObservationIgnored var openWith: (Win32FileEntry) -> Void = { _ in
        filesBloc.add(.openWith)
    }
    /// The pill row's two non-shell cells, same bargain as the four hooks
    /// above: Paste lands the clipboard in the given folder, Rename opens
    /// the surface's inline edit. The defaults are the explorer's; the
    /// desktop redirects both, because its filesBloc is dormant and a cell
    /// wired to it is a cell that quietly does nothing.
    @ObservationIgnored var pasteInto: (String) -> Void = {
        filesBloc.add(.paste(into: $0))
    }
    @ObservationIgnored var beginRename: (Win32FileEntry) -> Void = {
        filesBloc.add(.beginRename($0))
    }

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

    // MARK: - Popup surfaces
    //
    // Each open panel rides its own popup WINDOW (Win32PopupSurfaces) — the
    // second surface origin()'s comment used to wish for. The model stays
    // the single owner of geometry, in the same window-logical coordinates
    // it always used; what changes is only where a panel's pixels land (a
    // popup placed at that geometry, free to overhang the window) and where
    // its pointer events come from (the popup's own tree, translated back
    // into window coordinates before they reach press/hovered).
    //
    // OBSERVED: `popupsEnabled`, because the in-window widget draws the
    // panels itself exactly when this is false — the fallback for a machine
    // where a second engine view cannot be created. Everything else here is
    // bookkeeping no build reads.
    //
    // Every popup call is DEFERRED to its own main-queue turn
    // (scheduleSync), never made inline from a mutator: a press arrives
    // FROM the popup's own view, and closing that view inside its event
    // dispatch would destroy the window under the call stack that is
    // delivering the event.
    private(set) var popupsEnabled = true
    /// Bumped by every scheduleSync, i.e. after every mutation that can
    /// move a panel's geometry. The popup surfaces' builds read it, and
    /// NEED to: syncPopups warms mainCache/subCache OUTSIDE any tracked
    /// build, so a surface whose build then hits a warm cache never reads
    /// the observed rows underneath and would miss the next change — the
    /// full-tier verbs arrived, the popup window was resized for them, and
    /// the panel inside kept drawing the fast tier into the taller surface.
    private(set) var geometryEpoch = 0
    @ObservationIgnored private var mainPopup: Int?
    @ObservationIgnored private var subPopup: Int?
    @ObservationIgnored private var mainPopupRect: MenuRect?
    @ObservationIgnored private var subPopupRect: MenuRect?
    /// Whether the pooled main popup is currently shown (or scheduled to
    /// show). The popup ID outliving the menu is what pooling means, so
    /// visibility needs its own flag.
    @ObservationIgnored private var mainPopupShown = false
    @ObservationIgnored private var syncScheduled = false

    func scheduleSync() {
        guard popupsEnabled else { return }
        geometryEpoch &+= 1
        guard !syncScheduled else { return }
        syncScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.syncScheduled = false
            self.syncPopups()
        }
    }

    /// Lifts a cold open's held reveal (see revealHeld): the popup shows on
    /// the composite that carries the rows the caller just set, so it
    /// appears once, with real content — never the builtin-only skeleton.
    /// Idempotent; a warm open never holds, so this is a no-op there.
    private func revealNow() {
        guard revealHeld else { return }
        revealHeld = false
        guard popupsEnabled, isOpen else { return }
        if let id = mainPopup, !mainPopupShown {
            // Pooled popup that rebuilt hidden through the hold: show on
            // the composite carrying the current rows.
            mainPopupShown = true
            Win32PopupSurfaces.showOnNextComposite(id)
        }
        // The epoch bump guarantees a composite is coming for the pending
        // show to ride — and when the hold deferred creation, this sync is
        // what creates the popup (auto-shown on its first composite).
        scheduleSync()
    }

    /// The offset from THIS tree's window to the host window's client
    /// origin, in logical points.
    ///
    /// Popup geometry crosses the boundary in the HOST window's client space.
    /// For a process whose tree owns the main window those are the same
    /// space and this is zero. Hosted in the shell they are not: the host
    /// window is the DOCK, full screen at the origin, while the file
    /// explorer is a surface window wherever the user dragged it — so a menu
    /// computed at the pointer in this window's points opened at those
    /// coordinates measured from the screen's corner instead. Measured
    /// before the fix: pointer at screen (1700,1000), explorer client origin
    /// (893,344), menu drawn at (807,656).
    private var popupOffset: (x: Double, y: Double) {
        guard let id = FilesWindow.current.surfaceId else { return (0, 0) }
        return Win32Surfaces.clientOffset(id)
    }

    private func syncPopups() {
        // The layer experiment takes the whole job when it is on and this
        // tree is hosted in the shell — see MenuLayerHost.
        if MenuLayerHost.enabled, FilesWindow.current.surfaceId != nil {
            syncLayer()
            return
        }
        guard popupsEnabled else { return }
        guard isOpen, let at = origin(mainMenu) else {
            closePopups()
            return
        }
        // A held cold open shows nothing yet — and if no popup exists, none
        // is CREATED: a window created held and shown later flashed a ghost
        // (border and shadow around an interior that had never presented).
        // revealNow() re-syncs once rows exist, and the popup then takes
        // the ordinary create -> first-composite -> show path. A pooled
        // popup (already created, hidden) does rebuild during the hold, so
        // its reveal composite carries the real rows.
        if mainPopup == nil, revealHeld { return }
        let menu = mainMenu
        // No settling, no holding: the menu REVEALS with the rows it has.
        // Our own verbs are complete the moment open() runs, the shell's
        // fast tier (2ms for a file) is usually in before the first frame
        // composites, and the full tier grows the middle section a frame or
        // two later — under the pointer only ever the trailing "Show more
        // options" row moves. Appearing instantly and growing beats
        // appearing complete but late: the earlier hold-for-the-full-tier
        // policy cost every warm menu ~200ms of invisible waiting to spare
        // the cold one a visible growth Windows 11's own menu has too
        // (slow IExplorerCommands fill in late there as well).
        // Into the HOST window's client space, which is where popup geometry
        // is expressed — see popupOffset. Converted HERE rather than at each
        // call so the cached rects below compare in one space, and a window
        // the user has dragged since the last sync re-places rather than
        // silently keeping the old offset.
        let off = popupOffset
        let rect = MenuRect(x: at.x + off.x, y: at.y + off.y,
                            w: menu.width, h: menu.height)
        if let id = mainPopup {
            if rect != mainPopupRect {
                Win32PopupSurfaces.place(id, x: rect.x, y: rect.y,
                                         width: rect.w, height: rect.h)
                mainPopupRect = rect
            }
            if !mainPopupShown, !revealHeld {
                // POOLED reopen: the hidden view kept compositing, but what
                // it holds is the PREVIOUS menu until the rebuild this
                // sync's invalidation scheduled lands. Show on exactly that
                // composite — no old-content flash, no guessed timer. A
                // dismiss before it lands cancels through hide(). A held
                // cold open stays hidden here; revealNow() shows it.
                mainPopupShown = true
                Win32PopupSurfaces.showOnNextComposite(id)
            }
        } else {
            Win32PopupSurfaces.onDismiss { [weak self] in
                self?.dismiss()
                self?.scheduleSync()
            }
            mainPopup = Win32PopupSurfaces.open(
                x: rect.x, y: rect.y, width: rect.w, height: rect.h,
                holdUntilRevealed: false,
                content: { [weak self] in
                    self.map { MenuPanelSurface(model: $0, isSub: false) }
                        ?? SizedBox(width: 0, height: 0)
                })
            guard mainPopup != nil else {
                // No second surface on this machine: fall back to drawing
                // in-window, permanently — the flip re-runs the widget's
                // build, which starts drawing the panels it was skipping.
                popupsEnabled = false
                Win32PopupSurfaces.onDismiss(nil)
                return
            }
            mainPopupShown = true
            mainPopupRect = rect
        }

        if let subOrigin = subAt, !subMenu.rows.isEmpty {
            let sub = subMenu
            let srect = MenuRect(x: subOrigin.x + off.x, y: subOrigin.y + off.y,
                                 w: sub.width, h: sub.height)
            if let id = subPopup {
                if srect != subPopupRect {
                    Win32PopupSurfaces.place(id, x: srect.x, y: srect.y,
                                             width: srect.w, height: srect.h)
                    subPopupRect = srect
                }
            } else {
                subPopup = Win32PopupSurfaces.open(
                    x: srect.x, y: srect.y, width: srect.w, height: srect.h,
                    content: { [weak self] in
                        self.map { MenuPanelSurface(model: $0, isSub: true) }
                            ?? SizedBox(width: 0, height: 0)
                    })
                subPopupRect = srect
            }
        } else if let id = subPopup {
            Win32PopupSurfaces.close(id)
            subPopup = nil
            subPopupRect = nil
        }
    }

    /// The layer half of syncPopups: same geometry, published to the chrome
    /// instead of placed as windows. No hold, no first-composite gating and
    /// no pooling — the chrome's view is already on the swapchain, so a
    /// panel appears on the next frame of a tree that is already presenting.
    private func syncLayer() {
        let host = MenuLayerHost.shared
        guard isOpen, let at = origin(mainMenu) else {
            host.clear()
            return
        }
        let off = popupOffset
        let menu = mainMenu
        host.model = self
        host.main = MenuLayerHost.Panel(x: at.x + off.x, y: at.y + off.y,
                                        w: menu.width, h: menu.height)
        if let subOrigin = subAt, !subMenu.rows.isEmpty {
            host.sub = MenuLayerHost.Panel(x: subOrigin.x + off.x,
                                           y: subOrigin.y + off.y,
                                           w: subMenu.width, h: subMenu.height)
        } else {
            host.sub = nil
        }
    }

    private func closePopups() {
        if MenuLayerHost.enabled { MenuLayerHost.shared.clear() }
        if let id = subPopup {
            Win32PopupSurfaces.close(id)
            subPopup = nil
            subPopupRect = nil
        }
        if let id = mainPopup {
            // POOLED: hide, never destroy. The window, engine view and
            // mounted panel tree survive for the next right-click, which is
            // then place + show instead of CreateViewController + adapter
            // mount + first composite — the largest single cost of an open.
            Win32PopupSurfaces.hide(id)
            mainPopupShown = false
            mainPopupRect = nil
        }
    }

    /// Where a panel may sit: the monitor's work area once panels are
    /// popups, the window's own client area in the in-window fallback (a
    /// window is a hard clip there).
    var placementBounds: (left: Double, top: Double, right: Double,
                          bottom: Double) {
        if popupsEnabled, let frame = Win32PopupSurfaces.frame() {
            return frame
        }
        let size = FilesWindow.current.clientSize
            ?? (width: kFilesWidth, height: kFilesHeight)
        return (0, 0, size.width, size.height)
    }

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
        (.shell("cut"), FluentIcons.cut, "Cut"),
        (.shell("copy"), FluentIcons.copy, "Copy"),
        (.paste, FluentIcons.paste, "Paste"),
        (.rename, FluentIcons.rename, "Rename"),
        (.shell("windows.modernshare"), FluentIcons.share, "Share"),
        (.shell("delete"), FluentIcons.delete, "Delete"),
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
        "pintohome": FluentIcons.pin,
        "properties": FluentIcons.info,
        "copyaspath": FluentIcons.paste,
        "link": FluentIcons.link,
        "print": FluentIcons.print,
        "runas": FluentIcons.admin,
        "previousversions": FluentIcons.history,
        "pintostartscreen": FluentIcons.pin,
        "pintohomefile": FluentIcons.favorite,
        "edit": FluentIcons.rename,
    ]

    /// Whether the menu carries the icon row. An item's does; the folder
    /// background's does not, because none of those four verbs is about a
    /// folder you are standing in.
    var hasPillRow: Bool { entry != nil && flyoutRows == nil }

    /// Opens a FLYOUT: the given rows, anchored under a command-bar button.
    /// Same panel, same hit test, same hover as the context menu; no shell
    /// session behind it.
    func openFlyout(at x: Double, _ y: Double, rows: [MenuRow]) {
        dismiss()
        generation &+= 1
        flyoutRows = rows
        entry = nil
        flipped = false
        var anchorX = x
        let bounds = placementBounds
        let width = panelWidth(rows, pill: false)
        if anchorX + width > bounds.right - kMenuEdge {
            anchorX = max(bounds.left + kMenuEdge,
                          bounds.right - kMenuEdge - width)
        }
        anchor = MenuPoint(x: anchorX, y: y)
        mainCache = nil
        scheduleSync()
    }

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
        let path = entry?.path ?? backgroundDirectory()
        // An ITEM in a namespace listing has to be addressed through the
        // folder it was listed from -- its own name does not find it back
        // (see Win32ShellMenu.init). The BACKGROUND menu needs no such help:
        // a "::{CLSID}" location parses to itself, and asking for it is how
        // the bin's own "Empty Recycle Bin" arrives.
        let location = (entry != nil && filesBloc.state.isNamespace)
            ? filesBloc.state.directory : nil

        generation &+= 1
        let generation = self.generation
        let typeKey = Self.typeKey(entry,
                                   namespace: filesBloc.state.isNamespace)
        let session = Win32ShellMenu(path: path, location: location,
                                     background: entry == nil,
                                     owner: FilesWindow.current.handle)
        // The cheap tier, which for a file is usually back before the first
        // frame is drawn. Under a type-cache seed it is not DRAWN (the seed
        // is already the full shape) but it is KEPT: seeded rows have no
        // verb ids, and if the full tier never answers — a hung third-party
        // handler — these rows, with their live ids, are what the hang
        // failsafe below falls back to. Without that, a hung handler leaves
        // a menu that LOOKS complete and clicks like a dead one.
        session?.items(.fast) { [weak self] rows in
            guard let self, self.generation == generation,
                  !rows.isEmpty else { return }
            if self.shellRowsSeeded {
                self.seedFallbackRows = rows
                return
            }
            guard self.shellTier == .fast else { return }
            self.shellRows = rows
            self.mainCache = nil
            self.scheduleSync()
            self.revealNow()
        }
        // And the full one, which supersedes it — and refreshes the type
        // cache, so the NEXT same-typed menu paints complete on frame one.
        session?.items(.full) { [weak self] rows in
            guard let self, self.generation == generation, !rows.isEmpty else { return }
            // Nothing to reposition: the panel is anchored to the corner the
            // pointer is at, and `origin` re-derives the other corner from
            // whatever the menu now weighs.
            self.shellRows = rows
            self.shellTier = .full
            self.shellRowsSeeded = false
            self.mainCache = nil
            self.scheduleSync()
            self.revealNow()
            if let typeKey { Self.typeCache[typeKey] = rows }
        }

        // Which way it opens, decided HERE and not revisited. Windows flips a
        // menu that will not fit below the pointer so that its BOTTOM edge
        // sits at the pointer instead -- checked against Explorer on this
        // machine rather than remembered. The reservation is what makes that
        // decision possible before the verbs exist: the three rows we can
        // draw immediately would fit almost anywhere, so choosing the
        // direction from them would open downward on every click and then
        // discover it had nowhere to grow.
        let bounds = placementBounds
        let below = bounds.bottom - kMenuEdge - y
        let above = y - (bounds.top + kMenuEdge)
        let flip = below < reservedHeight && above > below
        var anchorX = x
        let width = panelWidth(rows(for: entry, shell: []), pill: entry != nil)
        if anchorX + width > bounds.right - kMenuEdge {
            anchorX = max(bounds.left + kMenuEdge,
                          bounds.right - kMenuEdge - width)
        }

        shell?.close()
        shell = session
        shellRows = []
        shellTier = .fast
        shellRowsSeeded = false
        // THE TYPE CACHE. A context menu is a function of the file's
        // ASSOCIATION CLASSES (extension/ProgID, Directory, `*`) far more
        // than of the file: the static verbs are pure registry data keyed
        // by type, and even the dynamic handlers' items are type-stable in
        // the overwhelming case. So the FULL rows of the last same-typed
        // menu paint the panel COMPLETE on the first frame, while the real
        // per-file query runs as always and reconciles — visually a no-op
        // for the same type, and the thing that catches the exceptions
        // (TortoiseGit's per-repo rows, OneDrive's per-file state). Seeded
        // rows carry NO verb ids (their session is gone; an id against the
        // new session would run someone else's verb), so a click inside the
        // seed window — shorter than any human's move-and-press — is inert.
        seedFallbackRows = nil
        revealHeld = false
        if let typeKey, let cached = Self.typeCache[typeKey] {
            shellRows = cached
            shellTier = .full
            shellRowsSeeded = true
            // The hang failsafe: a seeded menu whose FULL tier never answers
            // (a hung handler) would otherwise stay inert forever — every
            // row drawn, no row invocable. After a beat long enough that
            // something is genuinely wrong, swap in the real FAST rows,
            // which carry live ids: an honest shorter menu over a dead
            // complete-looking one.
            let seedGeneration = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self, self.generation == seedGeneration,
                      self.shellRowsSeeded,
                      let fallback = self.seedFallbackRows else { return }
                self.shellRows = fallback
                self.shellTier = .fast
                self.shellRowsSeeded = false
                self.mainCache = nil
                self.scheduleSync()
            }
        } else if popupsEnabled {
            // COLD: no seed to draw — hold the reveal for the fast tier
            // (see revealHeld above). The in-window fallback draws live in
            // the window and cannot hold, so it keeps the growing reveal.
            revealHeld = true
            let holdGeneration = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.generation == holdGeneration else { return }
                self.revealNow()
            }
        }
        expanded = false
        flyoutRows = nil
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
        scheduleSync()
        // (The hold-until-settled failsafe used to live here. Nothing is
        // held any more — the menu reveals with the rows it has, and the
        // shell's tiers grow it in place — so there is no invisible menu a
        // hung handler could strand.)
        return true
    }

    func dismiss() {
        let session = shell
        shell = nil
        anchor = nil
        flipped = false
        flyoutRows = nil
        entry = nil
        hover = nil
        pillHover = nil
        revealHeld = false
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
        scheduleSync()
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
        // A flyout IS its rows -- nothing assembled, nothing curated.
        if let flyoutRows { return flyoutRows }

        // An ITEM in a namespace listing is the shell's to describe, whole.
        // None of our own verbs below survives contact with one: Open and
        // Open with… would run the association on a "$R…" slot, Show in
        // Explorer would reveal the bin's internals, Compress would zip the
        // slot file and orphan the $I record beside it. And there is nothing
        // to curate -- the modern/legacy split exists because a file's menu
        // is thirty rows deep from a dozen handlers, while the bin's is four
        // (Restore, Cut, Delete, Properties), which is Explorer's whole menu
        // there too. So: the shell's list, as it comes, with no "Show more
        // options" hiding four rows behind a click.
        if entry != nil, filesBloc.state.isNamespace {
            return shellList(shellVerbs)
        }

        var rows: [MenuRow] = []
        if let entry {
            rows.append(MenuRow(title: "Open",
                                glyph: entry.isDirectory ? FluentIcons.folderOpen
                                                         : FluentIcons.document,
                                isDefault: true,
                                accelerator: "Enter",
                                action: { [activate] in activate(entry) }))
            if !entry.isDirectory {
                rows.append(MenuRow(title: "Open with…",
                                    glyph: FluentIcons.viewAll,
                                    action: { [openWith] in openWith(entry) }))
            }
            rows.append(MenuRow(title: "Show in Explorer",
                                glyph: FluentIcons.openExternal,
                                action: { [backgroundDirectory] in
                let path = entry.isDirectory ? entry.path
                                             : backgroundDirectory()
                Task.detached { Win32Files.openInExplorer(path) }
            }))
        } else {
            rows.append(MenuRow(title: "Refresh", glyph: FluentIcons.refresh,
                                action: { [afterVerb] in afterVerb() }))
            rows.append(MenuRow(title: "Show in Explorer",
                                glyph: FluentIcons.openExternal,
                                action: { [backgroundDirectory] in
                let path = backgroundDirectory()
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
                                glyph: FluentIcons.more,
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
                // A SEEDED row's id belongs to a closed session; against
                // the new one it would run someone else's verb. -1 is the
                // established "not a command" — the row draws, a click
                // inside the seed window dismisses harmlessly.
                shellId: shellRowsSeeded ? -1 : verb.id,
                token: shellRowsSeeded ? 0 : verb.submenu,
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
                                    glyph: FluentIcons.zip,
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
    /// taller than the whole SCREEN. The panels are popup windows now, so
    /// the bound is the monitor's work area, not the window -- a menu taller
    /// than the window simply overhangs it, the way Windows' own does. (In
    /// the in-window fallback the bounds shrink back to the client area and
    /// the old clamping behaviour returns with them.)
    func origin(_ menu: MenuCache) -> MenuPoint? {
        guard let anchor else { return nil }
        let bounds = placementBounds
        var y = flipped ? anchor.y - menu.height : anchor.y
        if y + menu.height > bounds.bottom - kMenuEdge {
            y = bounds.bottom - kMenuEdge - menu.height
        }
        if y < bounds.top + kMenuEdge { y = bounds.top + kMenuEdge }
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
            // Ours, not the shell's: an inline edit in the listing, which
            // needs a real file under the row to rename.
            return entry != nil && !filesBloc.state.isNamespace
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
                        action = { [pasteInto] in pasteInto(target) }
                    }
                case .rename:
                    if let entry {
                        action = { [beginRename] in beginRename(entry) }
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
            // from it -- run it and keep the panel open, which just changed
            // shape under its popup.
            if row.keepsOpen {
                if row.isEnabled { row.action?() }
                scheduleSync()
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
        if shellId >= 0 {
            // Re-read the folder once the verb is done. A shell verb moves
            // files without telling anyone and nothing watches a directory,
            // so without this a Delete leaves its row on screen and a
            // Restore takes a relaunch to notice. The pins re-read for the
            // same reason: "Pin to Quick access" is one of these verbs, and
            // the sidebar's pin section is the shell's set, not ours.
            session?.invoke(shellTierForInvoke, shellId) { [afterVerb] in
                afterVerb()
            }
        }
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
        // A hover is what opens and closes a submenu; its panel follows.
        // (A pure highlight change schedules a sync that finds nothing to
        // move -- coalesced and cheap.)
        scheduleSync()
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
            // The child hangs off the parent's right edge and may run off
            // the SCREEN's; flip it to the parent's left, which is what
            // Windows does with the same problem. (The window stopped being
            // the boundary when the panels became popups.)
            let bounds = self.placementBounds
            let child = self.subMenu
            if var at = self.subAt {
                if at.x + child.width > bounds.right - kMenuEdge {
                    at.x = max(bounds.left + kMenuEdge,
                               parentOrigin.x - child.width + 4)
                }
                if at.y + child.height > bounds.bottom - kMenuEdge {
                    at.y = max(bounds.top + kMenuEdge,
                               bounds.bottom - kMenuEdge - child.height)
                }
                self.subAt = at
            }
            self.scheduleSync()
        }
    }
}

// MARK: - The widgets
//
// Two hosts for the same panels. MenuPanelSurface is the real one: it is
// what a popup window's view mounts (one per panel — the menu, and its
// submenu), so a panel draws at ITS OWN origin and takes its own pointer
// events, translated back into window coordinates for the model. The
// in-window StarlingContextMenu remains mounted in the file explorer's tree
// as the FALLBACK, drawing panels the old Positioned way only when a popup
// surface could not be created (model.popupsEnabled == false); the rest of
// the time it draws nothing. Both hosts observe the model and share the
// painters below, so the fallback cannot drift from the real thing.

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
        // The same tracking the surfaces use for their blocs. While popups
        // carry the panels this build reads one property and draws nothing;
        // the flip to the fallback re-runs it and it starts drawing.
        withObservationTracking {
            _buildContent()
        } onChange: { [weak self] in
            guard let self, self.mounted else { return }
            self.setState {}
        }
    }

    private func _buildContent() -> Widget {
        guard !model.popupsEnabled else { return SizedBox(width: 0, height: 0) }
        return Stack(alignment: Alignment.topLeft) {
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
            model.panelWidget(menu, hover: model.hover, inPopup: false)
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
            model.panelWidget(menu, hover: model.subHover, inPopup: false)
        }
    }
}

/// A popup window's content: ONE panel, drawn at the surface's origin.
///
/// The surface is placed at exactly the panel's window-space rectangle
/// (syncPopups), so drawing at (0,0) and adding the panel's origin to every
/// pointer event keeps the model's arithmetic — press, hovered, rowIndex —
/// in the one coordinate space it always used. The model neither knows nor
/// cares that the pixels now live in another window.
final class MenuPanelSurface: StatefulWidget {
    let model: ShellMenuModel
    let isSub: Bool

    init(model: ShellMenuModel, isSub: Bool) {
        self.model = model
        self.isSub = isSub
        super.init()
    }

    override func createState() -> State<StatefulWidget> {
        MenuPanelSurfaceState(model: model, isSub: isSub)
    }
}

final class MenuPanelSurfaceState: State<StatefulWidget> {
    private let model: ShellMenuModel
    private let isSub: Bool

    init(model: ShellMenuModel, isSub: Bool) {
        self.model = model
        self.isSub = isSub
        super.init()
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
        // The one read that keeps this build subscribed to geometry changes
        // even when the caches below come back warm — see geometryEpoch.
        _ = model.geometryEpoch
        let menu = isSub ? model.subMenu : model.mainMenu
        let hover = isSub ? model.subHover : model.hover
        let at = isSub ? model.subAt : model.origin(model.mainMenu)
        // Between the dismissal and the popup's deferred close there is one
        // empty build; sized zero rather than guessing at stale geometry.
        guard model.isOpen, let origin = at else {
            return SizedBox(width: 0, height: 0)
        }
        return Listener(
            onPointerDown: { [weak self] e in
                guard let self else { return }
                self.model.press(origin.x + e.position.dx,
                                 origin.y + e.position.dy,
                                 buttons: e.buttons)
            },
            onPointerMove: { [weak self] e in
                guard let self else { return }
                self.model.hovered(origin.x + e.position.dx,
                                   origin.y + e.position.dy)
            },
            onPointerHover: { [weak self] e in
                guard let self else { return }
                self.model.hovered(origin.x + e.position.dx,
                                   origin.y + e.position.dy)
            },
            child: model.panelWidget(menu, hover: hover, inPopup: true))
    }
}

// MARK: - The panel painters
//
// On the model so both hosts share them; reads of observed state (hover,
// pillHover, the caches' backing fields) register with whichever build is
// running, exactly as they did as widget methods.

extension ShellMenuModel {

    /// The panel itself: Windows 11's rounded, bordered slab.
    ///
    /// In a POPUP the rounding and the shadow are the WINDOW's: DWM clips
    /// the surface to its own small-round corners and paints the menu
    /// shadow outside them, which is precisely what native menus are. So
    /// the popup variant fills its surface edge to edge — no ClipRRect (a
    /// second, larger radius would notch black class-brush pixels into the
    /// corners), no BoxShadow (it would be clipped at the surface's edge),
    /// and an OPAQUE fill, because behind this surface there is nothing of
    /// ours to blur: the translucent in-window tint would composite against
    /// the class brush, not against acrylic.
    func panelWidget(_ menu: MenuCache, hover: Int?, inPopup: Bool) -> Widget {
        SizedBox(width: menu.width, height: menu.height) {
            if inPopup {
                DecoratedBox(
                    decoration: BoxDecoration(
                        border: Border.all(color: Win11.menuBorder, width: 1)),
                    child: ColoredBox(color: Win11.menuBgOpaque) {
                        panelContentWidget(menu, hover: hover)
                    })
            } else {
                DecoratedBox(
                    decoration: BoxDecoration(
                        border: Border.all(color: Win11.menuBorder, width: 1),
                        borderRadius: BorderRadius.circular(kMenuRadius),
                        boxShadow: [BoxShadow(color: Win11.menuShadow,
                                              offset: Offset(0, 4),
                                              blurRadius: 12)]),
                    child: ClipRRect(borderRadius:
                                        BorderRadius.circular(kMenuRadius)) {
                        BackdropFilter(
                            filter: ImageFilterFactory.blur(sigmaX: 24,
                                                            sigmaY: 24),
                            child: ColoredBox(color: Win11.menuBg) {
                                panelContentWidget(menu, hover: hover)
                            })
                    })
            }
        }
    }

    private func panelContentWidget(_ menu: MenuCache, hover: Int?) -> Widget {
        Padding(padding: EdgeInsets(horizontal: kMenuPanelPad,
                                    vertical: kMenuPanelPad)) {
            Column(mainAxisSize: .min, crossAxisAlignment: .stretch) {
                if menu.pill {
                    pillRowWidget(width: menu.width)
                    separatorRowWidget()
                }
                for (index, row) in menu.rows.enumerated() {
                    if row.isSeparator {
                        separatorRowWidget()
                    } else {
                        rowWidget(row, hovered: hover == index)
                    }
                }
            }
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
    private func pillRowWidget(width: Double) -> Widget {
        let cell = (width - kMenuPanelPad * 2) / Double(Self.pillCells.count)
        return SizedBox(height: kMenuPillRow) {
            Row(crossAxisAlignment: .center) {
                for (index, entry) in Self.pillCells.enumerated() {
                    let live = pillLive(index)
                    let colour = live ? Win11.text : Win11.disabled
                    SizedBox(width: cell, height: kMenuPillRow) {
                        Center {
                            ClipRRect(borderRadius: BorderRadius.circular(4)) {
                                ColoredBox(color: pillHover == index && live
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
                                            Text(pillVerb(index)?.title
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
    private func separatorRowWidget() -> Widget {
        SizedBox(height: kMenuSepH) {
            Padding(padding: EdgeInsets(left: 10, top: 3, right: 10, bottom: 3)) {
                ColoredBox(color: Win11.menuSep) { SizedBox(height: 1) }
            }
        }
    }

    private func rowWidget(_ row: MenuRow, hovered: Bool) -> Widget {
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
                                        MacosIcon(icon: FluentIcons.chevronRight,
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
