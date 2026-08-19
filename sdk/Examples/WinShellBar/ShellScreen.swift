// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Which screen a surface is on, and how big it is in the units its tree lays
// out in.
//
// Every panel and overlay here is placed on ONE monitor and then has to lay
// itself out against that monitor: the dock centres its row of icons on it,
// the launcher works out how many columns and rows of apps fit. That
// arithmetic used to ask `Win32Display.primary()` at the point of use, which
// was wrong twice over:
//
//  - It is not necessarily the monitor the surface is ON. It happens to be
//    today, because main.swift places everything on the primary — but the
//    window and the tree were reaching that conclusion separately, so a dock
//    told to sit on the second screen would still have centred its icons
//    using the first screen's width.
//  - It is re-read at every call and yet never actually rechecked against a
//    change: the host re-places a panel on WM_DISPLAYCHANGE, so after a
//    resolution change the strip is the new width while the tree is still
//    laying out for the old one.
//
// So the monitor is chosen ONCE, in main.swift, beside the placement that
// puts the window there — and the geometry behind it is a cache refreshed on
// the tick the surface already runs. A cache rather than a computed property
// because `pointerTile` calls this on every pointer move, and EnumDisplay-
// Monitors per hover is not a thing to do.

#if os(Windows)
import FlutterWin32

enum ShellScreen {
    /// Index into `Win32Display.monitors()`, or nil for the primary — the
    /// same value `PanelPlacement`/`OverlayPlacement` is given, and set from
    /// the same line, so the two cannot disagree.
    private(set) static var index: Int?
    private static var cached: Win32Monitor?

    static func use(monitor: Int?) {
        index = monitor
        refresh()
    }

    /// Re-reads the geometry. Call it wherever the surface already wakes up:
    /// the dock's clock tick, the launcher being shown.
    @discardableResult
    static func refresh() -> Win32Monitor? {
        let all = Win32Display.monitors()
        // An index that no longer names a monitor falls back to the primary
        // rather than to nothing — a screen was unplugged, and a dock with no
        // width is worse than a dock on the wrong screen.
        cached = index.flatMap { $0 < all.count ? all[$0] : nil }
            ?? all.first(where: { $0.isPrimary })
            ?? all.first
        return cached
    }

    static var monitor: Win32Monitor? { cached ?? refresh() }

    /// Logical points — the units the widget tree is laid out in, and the
    /// units every constant in this shell is written in.
    ///
    /// The fallbacks are for a session that reports no monitors at all, which
    /// is a machine we cannot draw on anyway; they exist so the arithmetic
    /// has a number rather than to be right.
    static var logicalWidth: Double { monitor?.logicalWidth ?? 1280 }
    static var logicalHeight: Double { monitor?.logicalHeight ?? 800 }
}
#endif
