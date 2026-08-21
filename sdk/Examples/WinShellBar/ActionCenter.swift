// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The notification centre — Windows 11's Win+N surface, replicated: a
// notifications panel on top and a calendar panel beneath it, both pinned to
// the work area's right edge above the dock. A separate PROCESS, like the
// launcher and for the same reason (one widget root per process), parked
// hidden on its own toggle channel so showing it is one frame, not an
// engine boot.
//
// What is real and what is not, said plainly: the calendar is real — month
// navigation, today ringed in accent, weeks laid out the way the native
// panel lays them. The notifications LIST is the honest empty state, because
// reading other apps' toasts needs UserNotificationListener and that API
// requires packaged identity this exe does not have yet. "Clear all" and the
// do-not-disturb bell draw disabled for the same reason a dead button would
// be worse: a control that looks live and does nothing teaches the user not
// to trust the panel.
//
// Geometry (points, measured off the native panel at 100%): 332 wide, 13
// from the right edge, 12 above the work area, 8 below the screen top.
// Panels are 8pt-radius rounded rects with a 1px stroke, exactly the Quick
// Settings recipe, sharing its palette (WinTheme.swift).

#if os(Windows)

import Flutter
import FlutterSwiftBridge
import FlutterWin32
import CupertinoIcons
import Foundation

let kAcWidth = 332.0
let kAcPanelGap = 12.0
/// The calendar's collapsed height is one header row; expanded adds the
/// month bar, the weekday row and six week rows.
let kAcCalCollapsedH = 52.0
let kAcCalMonthBarH = 36.0
let kAcCalWeekdayH = 26.0
let kAcCalCellH = 36.0
let kAcCalExpandedH = kAcCalCollapsedH + kAcCalMonthBarH + kAcCalWeekdayH
    + 6 * kAcCalCellH + 12

/// The window's height in points: the screen minus the dock's strip, the
/// 12pt above the work area and the 8pt below the screen top. One formula,
/// used by BOTH main.swift's placement and the tree's layout — the same
/// bargain ShellScreen exists for.
var kAcHeightPt: Double {
    ShellScreen.logicalHeight - Double(kDockHeight) - kAcPanelGap - 8
}

final class StarlingActionCenter: StatefulWidget {
    override func createState() -> State<StatefulWidget> { StarlingActionCenterState() }
}

final class StarlingActionCenterState: State<StatefulWidget> {
    private var now = Date()
    /// Which month the grid shows: an offset in months from `now`'s, so
    /// "today" keeps working after midnight passes under an open panel.
    private var monthOffset = 0
    private var calendarExpanded = false
    private var timer: AnyObject?
    /// The toast store, newest first — the panel's real content, re-read on
    /// a short poll while visible and once on every show. Poll rather than
    /// the NotificationChanged event: the event needs a hand-written COM
    /// object, and a panel that is usually hidden has no use for it.
    private var toasts: [Win32Toast] = []
    /// What the pointer is over — the interactive parts answer hover the
    /// way the native panel's do. Arithmetic off the root Listener, one
    /// rectangle set for drawing and hit-testing both.
    private var hovered: AcHover?

    enum AcHover: Equatable {
        case header
        case prev
        case next
        case clearAll
        case card(Int)
        case cardClose(Int)
    }

    override func initState() {
        super.initState()
        CupertinoIcons.registerFont()
        FluentIcons.registerFont()
        // Five seconds: the date line barely moves, but the toast store does,
        // and the poll is only paid while the panel is on screen.
        timer = startPeriodicTimer(seconds: 5) { [weak self] in
            guard let self else { return }
            self.setState { self.now = Date() }
            if Win32WindowedHost.host?.isVisible == true { self.refreshToasts() }
        }
        refreshToasts()
        // The launcher's bargain (see its didToggle): the host shows the
        // window; the tree hears about it here. On show, mark the tree dirty
        // so a fresh frame is what the user sees — a frame painted while the
        // window was hidden presents as stale black, with no error. On hide,
        // fold the calendar back so the next open starts where the native
        // panel starts.
        Win32WindowedHost.host?.onToggle { [weak self] in
            guard let self else { return }
            if Win32WindowedHost.host?.isVisible == true {
                self.setState { self.now = Date() }
                self.refreshToasts()
            } else {
                self.setState {
                    self.calendarExpanded = false
                    self.monthOffset = 0
                    self.hovered = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    Win32WindowedHost.host?.requestRedraw()
                }
            }
        }
    }

    // MARK: - The store

    private func refreshToasts() {
        Task.detached { [weak self] in
            let items = Win32Notifications.read()
            await MainActor.run {
                guard let self, items != self.toasts else { return }
                self.setState { self.toasts = items }
            }
        }
    }

    private func removeToast(_ id: UInt32) {
        // Optimistic, then re-read: the next poll is seconds away and a card
        // that lingers after its X reads as a dead button.
        setState { toasts.removeAll { $0.id == id } }
        Task.detached { [weak self] in
            Win32Notifications.remove(id)
            await MainActor.run { self?.refreshToasts() }
        }
    }

    private func clearAllToasts() {
        setState { toasts = [] }
        Task.detached { [weak self] in
            Win32Notifications.clearAll()
            await MainActor.run { self?.refreshToasts() }
        }
    }

    // MARK: - Geometry
    //
    // Same bargain as the dock's flyouts: every rectangle is arithmetic,
    // computed once and used by both the drawing and the hit test, because
    // widget-level input callbacks are unreliable on this embedder.

    private struct AcRect {
        let x: Double, y: Double, w: Double, h: Double
        func contains(_ px: Double, _ py: Double) -> Bool {
            px >= x && px <= x + w && py >= y && py <= y + h
        }
    }

    private var windowH: Double { kAcHeightPt }
    private var calH: Double { calendarExpanded ? kAcCalExpandedH : kAcCalCollapsedH }

    private var notifPanel: AcRect {
        AcRect(x: 0, y: 0, w: kAcWidth, h: windowH - calH - kAcPanelGap)
    }
    private var calPanel: AcRect {
        AcRect(x: 0, y: windowH - calH, w: kAcWidth, h: calH)
    }
    /// The calendar's header row — the date, and the chevron that expands.
    private var calHeader: AcRect {
        AcRect(x: 0, y: calPanel.y, w: kAcWidth, h: kAcCalCollapsedH)
    }
    /// The toast cards: fixed-height cards down the notifications panel,
    /// newest first, capped at what fits — the "+ n more" line stands in for
    /// the scroll this surface does not have yet.
    private let cardH = 96.0
    private let cardGap = 8.0

    private var visibleCards: Int {
        let avail = notifPanel.h - 52 - 26
        return max(0, min(toasts.count, Int(avail / (cardH + cardGap))))
    }

    private func cardRect(_ i: Int) -> AcRect {
        AcRect(x: 12, y: 52 + Double(i) * (cardH + cardGap),
               w: kAcWidth - 24, h: cardH)
    }

    private func cardCloseRect(_ i: Int) -> AcRect {
        let r = cardRect(i)
        return AcRect(x: r.x + r.w - 32, y: r.y + 6, w: 26, h: 26)
    }

    private var clearAllRect: AcRect {
        AcRect(x: kAcWidth - 78, y: 13, w: 64, h: 26)
    }

    private var calPrev: AcRect {
        AcRect(x: kAcWidth - 76, y: calPanel.y + kAcCalCollapsedH, w: 32, h: kAcCalMonthBarH)
    }
    private var calNext: AcRect {
        AcRect(x: kAcWidth - 40, y: calPanel.y + kAcCalCollapsedH, w: 32, h: kAcCalMonthBarH)
    }

    // MARK: - Calendar arithmetic

    private var shownMonth: (year: Int, month: Int) {
        let cal = Calendar.current
        let base = cal.date(byAdding: .month, value: monthOffset, to: now) ?? now
        let c = cal.dateComponents([.year, .month], from: base)
        return (c.year ?? 2026, c.month ?? 1)
    }

    /// The 42 numbers of the six-week grid, with today's index if today is
    /// in the shown month. Weeks run Sunday-first, the native panel's order.
    private func monthGrid() -> (days: [Int], inMonth: [Bool], todayIndex: Int?) {
        var cal = Calendar.current
        cal.firstWeekday = 1
        let (year, month) = shownMonth
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
        guard let first = cal.date(from: comps) else { return ([], [], nil) }
        let firstWeekday = cal.component(.weekday, from: first)  // 1 = Sunday
        let lead = firstWeekday - 1
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let prevCount: Int = {
            guard let prev = cal.date(byAdding: .month, value: -1, to: first) else { return 31 }
            return cal.range(of: .day, in: .month, for: prev)?.count ?? 31
        }()
        var days: [Int] = [], inMonth: [Bool] = []
        for i in 0..<42 {
            if i < lead {
                days.append(prevCount - lead + 1 + i); inMonth.append(false)
            } else if i - lead < count {
                days.append(i - lead + 1); inMonth.append(true)
            } else {
                days.append(i - lead - count + 1); inMonth.append(false)
            }
        }
        let t = cal.dateComponents([.year, .month, .day], from: now)
        var todayIndex: Int? = nil
        if t.year == year, t.month == month, let d = t.day {
            todayIndex = lead + d - 1
        }
        return (days, inMonth, todayIndex)
    }

    private func headerDateText() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: now)
    }

    private func monthLabelText() -> String {
        let (year, month) = shownMonth
        let names = DateFormatter().monthSymbols ?? []
        let name = month >= 1 && month <= names.count ? names[month - 1] : "\(month)"
        return "\(name) \(year)"
    }

    // MARK: - Input

    private func acHover(_ x: Double, _ y: Double) -> AcHover? {
        if calendarExpanded, calPrev.contains(x, y) { return .prev }
        if calendarExpanded, calNext.contains(x, y) { return .next }
        if calHeader.contains(x, y) { return .header }
        if !toasts.isEmpty, clearAllRect.contains(x, y) { return .clearAll }
        for i in 0..<visibleCards {
            if cardCloseRect(i).contains(x, y) { return .cardClose(i) }
            if cardRect(i).contains(x, y) { return .card(i) }
        }
        return nil
    }

    private func handlePress(_ x: Double, _ y: Double) {
        if !toasts.isEmpty, clearAllRect.contains(x, y) {
            clearAllToasts()
            return
        }
        for i in 0..<visibleCards where cardCloseRect(i).contains(x, y) {
            removeToast(toasts[i].id)
            return
        }
        if calHeader.contains(x, y) {
            setState { calendarExpanded.toggle() }
            return
        }
        if calendarExpanded, calPrev.contains(x, y) {
            setState { monthOffset -= 1 }
            return
        }
        if calendarExpanded, calNext.contains(x, y) {
            setState { monthOffset += 1 }
            return
        }
        // A press on either panel's body: swallowed. Dismissal is Escape or
        // the toggle, which is how the native panel treats its own furniture.
    }

    // MARK: - Widgets

    /// The rounded-panel recipe shared with Quick Settings: the 1px stroke
    /// is the outer box, the fill inset inside it.
    private func acPanel(_ rect: AcRect, _ p: WinPalette, content: Widget) -> Widget {
        Positioned(left: rect.x, top: rect.y) {
            SizedBox(width: rect.w, height: rect.h) {
                ClipRRect(borderRadius: BorderRadius.circular(8)) {
                    ColoredBox(color: p.stroke) {
                        Padding(padding: EdgeInsets(left: 1, top: 1, right: 1, bottom: 1)) {
                            ClipRRect(borderRadius: BorderRadius.circular(7)) {
                                ColoredBox(color: p.panel) {
                                    content
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// The relative time the native cards carry — "2m", "3h", a date.
    private func toastTimeText(_ t: Win32Toast) -> String {
        let s = Int(now.timeIntervalSince(t.time))
        if s < 60 { return "now" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: t.time)
    }

    private func toastCard(_ i: Int, _ p: WinPalette) -> Widget {
        let toast = toasts[i]
        let r = cardRect(i)
        let hoveredHere: Bool = {
            switch hovered {
            case .card(let j), .cardClose(let j): return j == i
            default: return false
            }
        }()
        return Positioned(left: r.x, top: r.y) {
            SizedBox(width: r.w, height: r.h) {
                ClipRRect(borderRadius: BorderRadius.circular(6)) {
                    ColoredBox(color: p.buttonStroke) {
                        Padding(padding: EdgeInsets(left: 1, top: 1, right: 1, bottom: 1)) {
                            ClipRRect(borderRadius: BorderRadius.circular(5)) {
                                ColoredBox(color: hoveredHere ? p.buttonHover : p.button) {
                                    Stack(alignment: Alignment.topLeft) {
                                        Positioned(left: 12, top: 8, width: r.w - 90, height: 16) {
                                            Text(toast.app,
                                                 style: TextStyle(color: p.subInk, fontSize: 11),
                                                 overflow: .ellipsis, maxLines: 1)
                                        }
                                        Positioned(left: r.w - 76, top: 8, width: 36, height: 16) {
                                            Text(toastTimeText(toast),
                                                 style: TextStyle(color: p.subInk, fontSize: 11))
                                        }
                                        Positioned(left: 12, top: 28, width: r.w - 24, height: 18) {
                                            Text(toast.title,
                                                 style: TextStyle(color: p.ink, fontSize: 13,
                                                                  fontWeight: .w600),
                                                 overflow: .ellipsis, maxLines: 1)
                                        }
                                        Positioned(left: 12, top: 48, width: r.w - 24, height: 40) {
                                            Text(toast.body,
                                                 style: TextStyle(color: p.subInk, fontSize: 12),
                                                 overflow: .ellipsis, maxLines: 2)
                                        }
                                        // The dismiss X, on the card the pointer is over —
                                        // the native card's own affordance.
                                        if hoveredHere {
                                            Positioned(left: r.w - 32, top: 6, width: 26, height: 26) {
                                                ClipRRect(borderRadius: BorderRadius.circular(4)) {
                                                    ColoredBox(color: hovered == .cardClose(i)
                                                                   ? p.rowHover : Color(0x00000000)) {
                                                        Center {
                                                            MacosIcon(icon: FluentIcons.close,
                                                                      color: p.subInk, size: 11)
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
                }
            }
        }
    }

    private func notificationsBody(_ p: WinPalette) -> Widget {
        let emptyY = notifPanel.h * 0.42
        let shown = visibleCards
        let hidden = toasts.count - shown
        return Stack(alignment: Alignment.topLeft) {
            // Header: the title, the do-not-disturb bell (still a stub), and
            // "Clear all" — live exactly when there is something to clear.
            Positioned(left: 16, top: 14, width: 160, height: 24) {
                Text("Notifications",
                     style: TextStyle(color: p.ink, fontSize: 14, fontWeight: .w600))
            }
            Positioned(left: kAcWidth - 112, top: 12, width: 28, height: 28) {
                Center {
                    MacosIcon(icon: FluentIcons.ringer, color: p.disabledInk, size: 15)
                }
            }
            Positioned(left: kAcWidth - 78, top: 13, width: 64, height: 26) {
                ClipRRect(borderRadius: BorderRadius.circular(13)) {
                    ColoredBox(color: toasts.isEmpty ? p.button
                               : hovered == .clearAll ? p.buttonHover : p.button) {
                        Center {
                            Text("Clear all",
                                 style: TextStyle(color: toasts.isEmpty ? p.disabledInk : p.ink,
                                                  fontSize: 12))
                        }
                    }
                }
            }
            if toasts.isEmpty {
                // The honest empty state, where the native panel centres its own.
                Positioned(left: 0, top: emptyY, width: kAcWidth, height: 20) {
                    Center {
                        Text("No new notifications",
                             style: TextStyle(color: p.subInk, fontSize: 13))
                    }
                }
            } else {
                for i in 0..<shown {
                    toastCard(i, p)
                }
                if hidden > 0 {
                    Positioned(left: 0, top: 52 + Double(shown) * (cardH + cardGap),
                               width: kAcWidth, height: 18) {
                        Center {
                            Text("+ \(hidden) more",
                                 style: TextStyle(color: p.subInk, fontSize: 12))
                        }
                    }
                }
            }
        }
    }

    /// One day cell of the grid — today gets the accent disc.
    private func calCell(_ i: Int, _ grid: (days: [Int], inMonth: [Bool], todayIndex: Int?),
                         _ p: WinPalette) -> Widget {
        let cellW = (kAcWidth - 24) / 7
        let gridTop = kAcCalCollapsedH + kAcCalMonthBarH + kAcCalWeekdayH
        let cx = 12 + Double(i % 7) * cellW
        let cy = gridTop + Double(i / 7) * kAcCalCellH
        if grid.todayIndex == i {
            return Positioned(left: cx + (cellW - 28) / 2,
                              top: cy + (kAcCalCellH - 28) / 2,
                              width: 28, height: 28) {
                ClipRRect(borderRadius: BorderRadius.circular(14)) {
                    ColoredBox(color: p.accent) {
                        Center {
                            Text("\(grid.days[i])",
                                 style: TextStyle(color: p.onAccent, fontSize: 12,
                                                  fontWeight: .w600))
                        }
                    }
                }
            }
        }
        return Positioned(left: cx, top: cy, width: cellW, height: kAcCalCellH) {
            Center {
                Text("\(grid.days[i])",
                     style: TextStyle(color: grid.inMonth[i] ? p.ink : p.disabledInk,
                                      fontSize: 12))
            }
        }
    }

    private func calendarBody(_ p: WinPalette) -> Widget {
        let grid = monthGrid()
        let weekdays = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        let cellW = (kAcWidth - 24) / 7
        let weekdayTop = kAcCalCollapsedH + kAcCalMonthBarH
        return Stack(alignment: Alignment.topLeft) {
            if hovered == .header {
                Positioned(left: 4, top: 4, width: kAcWidth - 10, height: kAcCalCollapsedH - 8) {
                    ClipRRect(borderRadius: BorderRadius.circular(4)) {
                        ColoredBox(color: p.rowHover) { SizedBox(expand: ()) }
                    }
                }
            }
            // The date row, with the expand/collapse chevron. The chevron
            // points the way the panel will grow: up when collapsed.
            Positioned(left: 16, top: 16, width: 220, height: 20) {
                Text(headerDateText(),
                     style: TextStyle(color: p.ink, fontSize: 13, fontWeight: .w600))
            }
            Positioned(left: kAcWidth - 40, top: 14, width: 24, height: 24) {
                Center {
                    MacosIcon(icon: calendarExpanded
                                  ? FluentIcons.chevronDown : FluentIcons.chevronUp,
                              color: p.subInk, size: 12)
                }
            }
            if calendarExpanded {
                // Month bar: the label and the up/down navigation pair —
                // vertical chevrons, the direction the native grid scrolls.
                Positioned(left: 16, top: kAcCalCollapsedH + 8, width: 180, height: 20) {
                    Text(monthLabelText(),
                         style: TextStyle(color: p.ink, fontSize: 13, fontWeight: .w600))
                }
                Positioned(left: kAcWidth - 76, top: kAcCalCollapsedH + 6, width: 32, height: 24) {
                    ClipRRect(borderRadius: BorderRadius.circular(4)) {
                        ColoredBox(color: hovered == .prev ? p.rowHover : Color(0x00000000)) {
                            Center {
                                MacosIcon(icon: FluentIcons.chevronUp, color: p.subInk, size: 12)
                            }
                        }
                    }
                }
                Positioned(left: kAcWidth - 40, top: kAcCalCollapsedH + 6, width: 32, height: 24) {
                    ClipRRect(borderRadius: BorderRadius.circular(4)) {
                        ColoredBox(color: hovered == .next ? p.rowHover : Color(0x00000000)) {
                            Center {
                                MacosIcon(icon: FluentIcons.chevronDown, color: p.subInk, size: 12)
                            }
                        }
                    }
                }
                for i in 0..<7 {
                    Positioned(left: 12 + Double(i) * cellW, top: weekdayTop,
                               width: cellW, height: kAcCalWeekdayH) {
                        Center {
                            Text(weekdays[i], style: TextStyle(color: p.subInk, fontSize: 11))
                        }
                    }
                }
                for i in 0..<grid.days.count {
                    calCell(i, grid, p)
                }
            }
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let p = WinPalette.of(dark: Win32Control.isDarkMode)
        return Directionality(
            textDirection: .ltr,
            child: Listener(
                onPointerDown: { [weak self] event in
                    self?.handlePress(event.position.dx, event.position.dy)
                },
                onPointerHover: { [weak self] event in
                    guard let self else { return }
                    let over = self.acHover(event.position.dx, event.position.dy)
                    if over != self.hovered {
                        self.setState { self.hovered = over }
                    }
                },
                behavior: .opaque,
                // The SizedBox is what gives the Stack its extent: with only
                // Positioned children a Stack sizes to nothing, and a
                // zero-sized tree paints a black window with no error.
                child: SizedBox(width: kAcWidth, height: windowH) {
                    Stack(alignment: Alignment.topLeft) {
                        acPanel(notifPanel, p, content: notificationsBody(p))
                        acPanel(calPanel, p, content: calendarBody(p))
                    }
                }
            )
        )
    }
}

#endif
