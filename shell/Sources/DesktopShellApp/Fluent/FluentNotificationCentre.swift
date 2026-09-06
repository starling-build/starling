// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The notification centre — Windows' Win+N surface, which the clock and the
// bell both open: a notifications panel on top and the calendar beneath it,
// two cards pinned to the right edge above the taskbar.
//
// The geometry is our Windows shell's, measured off the native panel: 332
// wide, 12 above the bar; the calendar's collapsed header is 52 high, the
// month bar 36, the weekday row 26, a day cell 36, today a 28px disc on the
// accent. Notifications are the freedesktop daemon's — every card is a real
// post, with its own dismiss; Clear all closes them all, and the bell puts
// the desktop in do-not-disturb, which keeps new posts from tinting the
// taskbar's bell (and, once toasts exist, from toasting).

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

// MARK: - Geometry

enum NotificationCentreMetrics {
    static let width: Double = 332
    /// Between the two cards, and between the lower one and the bar.
    static let gap: Double = 12
    static let pad: Double = FluentSpacing.m               // 12
    static let calendarHeader: Double = 52
    static let monthBar: Double = 36
    static let weekdayRow: Double = 26
    static let dayCell: Double = 36
    static let todayDisc: Double = 28
    static var cellWidth: Double { (width - pad * 2) / 7 }
}

extension _DesktopShellState {

    /// Which popup kinds the centre answers for: the bell's and the clock's.
    func fluentIsNotificationCentre(_ kind: StatusBarPopup) -> Bool {
        kind == .notifications || kind == .clock
    }

    func fluentNotificationCentre() -> Widget {
        let m = NotificationCentreMetrics.self
        // The notifications card takes what the calendar leaves it.
        let calendarH = _calendarExpanded
            ? m.calendarHeader + m.monthBar + m.weekdayRow + 6 * m.dayCell + m.pad
            : m.calendarHeader
        let available = screenHeight - DesktopTheme.kDockHeight - Self.kFluentFlyoutGap
            - calendarH - m.gap - m.gap
        return Column(mainAxisSize: .min, crossAxisAlignment: .end, spacing: m.gap) {
            fluentFlyoutFrame(
                width: m.width,
                child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: max(120, available)),
                    child: _ncNotifications()))
            fluentFlyoutFrame(width: m.width, child: _ncCalendar())
        }
    }

    // MARK: Notifications

    private func _ncNotifications() -> Widget {
        let m = NotificationCentreMetrics.self
        let notes = Array(_notifications.reversed())
        var header: [Widget] = [
            Expanded {
                Text("Notifications",
                     style: fluentType.styled({ $0.bodyStrong }, shellTheme.fgPrimary, strong: true))
            },
        ]
        if !notes.isEmpty {
            header.append(_ncTextButton("Clear all") { [self] in
                let ids = _notifications.map { $0.id }
                for id in ids { _dismissNotification(id: id, reason: 2) }
            })
            header.append(SizedBox(width: FluentSpacing.xs))
        }
        header.append(_ncIconButton(
            _doNotDisturb ? FluentSystemIcons.bellOff : FluentSystemIcons.bell,
            active: _doNotDisturb) { [self] in
            setState { _doNotDisturb.toggle() }
        })

        let body: Widget
        if notes.isEmpty {
            body = Padding(
                padding: EdgeInsets(left: 0, top: FluentSpacing.xl, right: 0, bottom: FluentSpacing.xl),
                child: Column(crossAxisAlignment: .center, spacing: FluentSpacing.s) {
                    Icon(_doNotDisturb ? FluentSystemIcons.bellOff : FluentSystemIcons.bell,
                         size: 28, color: shellTheme.fgTertiary)
                    Text(_doNotDisturb ? "Do not disturb is on" : "No new notifications",
                         style: fluentType.styled({ $0.body }, shellTheme.fgSecondary))
                })
        } else {
            body = Flexible(
                child: SingleChildScrollView(
                    child: Column(crossAxisAlignment: .stretch, spacing: FluentSpacing.xs,
                                  children: notes.map { _ncCard($0) })))
        }
        return Padding(
            padding: EdgeInsets(all: m.pad),
            child: Column(mainAxisSize: .min, crossAxisAlignment: .stretch) {
                Padding(padding: EdgeInsets(left: FluentSpacing.xs, top: 0, right: 0, bottom: FluentSpacing.s)) {
                    Row(crossAxisAlignment: .center, children: header)
                }
                body
            })
    }

    /// One post: the app and when, the summary, the body, and its own X.
    private func _ncCard(_ note: ShellNotification) -> Widget {
        DecoratedBox(
            decoration: BoxDecoration(
                color: shellTheme.controlFill,
                border: Border.all(color: shellTheme.controlStroke, width: FluentStrokeWidth.thin),
                borderRadius: FluentCorners.controlRadius),
            child: Padding(
                padding: EdgeInsets(left: FluentSpacing.m, top: FluentSpacing.s,
                                    right: FluentSpacing.xs, bottom: FluentSpacing.m),
                child: Column(crossAxisAlignment: .stretch, spacing: 2) {
                    Row(crossAxisAlignment: .center) {
                        Expanded {
                            Text("\(note.appName.isEmpty ? "Notification" : note.appName) · \(_ncAge(note.postedAt))",
                                 style: fluentType.styled({ $0.caption }, shellTheme.fgSecondary),
                                 overflow: .ellipsis, maxLines: 1)
                        }
                        _ncIconButton(FluentSystemIcons.close, active: false, size: 24) { [self] in
                            _dismissNotification(id: note.id, reason: 2)
                        }
                    }
                    Text(note.summary,
                         style: fluentType.styled({ $0.bodyStrong }, shellTheme.fgPrimary, strong: true),
                         overflow: .ellipsis, maxLines: 2)
                    if !note.body.isEmpty {
                        Text(note.body, style: fluentType.styled({ $0.body }, shellTheme.fgSecondary),
                             overflow: .ellipsis, maxLines: 3)
                    }
                }))
    }

    private func _ncAge(_ date: Date) -> String {
        let s = Date().timeIntervalSince(date)
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86400))d"
    }

    // MARK: Calendar

    private var _calendarShownMonth: (year: Int, month: Int) {
        let cal = Calendar.current
        let shifted = cal.date(byAdding: .month, value: _calendarMonthOffset, to: Date()) ?? Date()
        let c = cal.dateComponents([.year, .month], from: shifted)
        return (c.year ?? 2000, c.month ?? 1)
    }

    /// Six weeks of day numbers from the Sunday before the 1st, with which
    /// belong to the shown month and where today lands.
    private func _calendarGrid() -> (days: [Int], inMonth: [Bool], todayIndex: Int?) {
        var cal = Calendar.current
        cal.firstWeekday = 1
        let (year, month) = _calendarShownMonth
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
        guard let first = cal.date(from: comps) else { return ([], [], nil) }
        let lead = cal.component(.weekday, from: first) - 1
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
        let t = cal.dateComponents([.year, .month, .day], from: Date())
        var todayIndex: Int? = nil
        if t.year == year, t.month == month, let d = t.day { todayIndex = lead + d - 1 }
        return (days, inMonth, todayIndex)
    }

    private func _ncCalendar() -> Widget {
        let m = NotificationCentreMetrics.self
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        let header: Widget = SizedBox(
            height: m.calendarHeader,
            child: HoverButton(
                builder: { [self] _, states in
                    let hot = states.isHovered || states.isPressed
                    return DecoratedBox(
                        decoration: BoxDecoration(
                            color: hot ? shellTheme.controlHover : Color(0x00000000),
                            borderRadius: FluentCorners.controlRadius),
                        child: Padding(
                            padding: EdgeInsets(left: FluentSpacing.m, top: 0, right: FluentSpacing.s, bottom: 0),
                            child: Row(crossAxisAlignment: .center) {
                                Expanded {
                                    Text(f.string(from: Date()),
                                         style: fluentType.styled({ $0.bodyStrong }, shellTheme.fgPrimary, strong: true))
                                }
                                // The chevron points the way the card will grow.
                                FluentGlyph(_calendarExpanded ? .chevronDown : .chevronUp,
                                            size: 12, color: shellTheme.fgSecondary)
                            }))
                },
                onPressed: { [self] in setState { _calendarExpanded.toggle() } }))
        guard _calendarExpanded else {
            return Padding(padding: EdgeInsets(all: FluentSpacing.xs), child: header)
        }

        let grid = _calendarGrid()
        let (year, month) = _calendarShownMonth
        let names = DateFormatter().monthSymbols ?? []
        let monthLabel = "\(month >= 1 && month <= names.count ? names[month - 1] : "\(month)") \(year)"
        let weekdays = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

        var rows: [Widget] = []
        for r in 0..<6 {
            var cells: [Widget] = []
            for c in 0..<7 {
                let i = r * 7 + c
                cells.append(_ncDayCell(day: grid.days[i], inMonth: grid.inMonth[i],
                                        today: grid.todayIndex == i))
            }
            rows.append(Row(children: cells))
        }

        return Padding(
            padding: EdgeInsets(all: FluentSpacing.xs),
            child: Column(mainAxisSize: .min, crossAxisAlignment: .stretch) {
                header
                SizedBox(
                    height: m.monthBar,
                    child: Padding(
                        padding: EdgeInsets(left: FluentSpacing.m, top: 0, right: FluentSpacing.xs, bottom: 0),
                        child: Row(crossAxisAlignment: .center) {
                            Expanded {
                                Text(monthLabel, style: fluentType.styled({ $0.bodyStrong }, shellTheme.fgPrimary, strong: true))
                            }
                            _ncGlyphButton(.chevronUp) { [self] in setState { _calendarMonthOffset -= 1 } }
                            _ncGlyphButton(.chevronDown) { [self] in setState { _calendarMonthOffset += 1 } }
                        }))
                SizedBox(
                    height: m.weekdayRow,
                    child: Row(children: weekdays.map { day in
                        SizedBox(width: m.cellWidth, child: Center(child: Text(
                            day, style: fluentType.styled({ $0.caption }, shellTheme.fgSecondary))))
                    }))
                Column(children: rows)
                SizedBox(height: FluentSpacing.xs)
            })
    }

    private func _ncDayCell(day: Int, inMonth: Bool, today: Bool) -> Widget {
        let m = NotificationCentreMetrics.self
        let label = Text("\(day)", style: fluentType.styled(
            { $0.caption },
            today ? shellTheme.accentInk : (inMonth ? shellTheme.fgPrimary : shellTheme.fgTertiary),
            strong: today))
        if today {
            return SizedBox(width: m.cellWidth, height: m.dayCell, child: Center(
                child: SizedBox(width: m.todayDisc, height: m.todayDisc, child: DecoratedBox(
                    decoration: BoxDecoration(color: shellTheme.accent,
                                              borderRadius: BorderRadius.circular(m.todayDisc / 2)),
                    child: Center(child: label)))))
        }
        return SizedBox(width: m.cellWidth, height: m.dayCell, child: Center(child: label))
    }

    // MARK: Pieces

    private func _ncTextButton(_ label: String, onTap: @escaping () -> Void) -> Widget {
        HoverButton(
            builder: { [self] _, states in
                let hot = states.isHovered || states.isPressed
                return Padding(
                    padding: EdgeInsets(left: FluentSpacing.xs, top: 2, right: FluentSpacing.xs, bottom: 2),
                    child: Text(label, style: fluentType.styled(
                        { $0.caption }, hot ? shellTheme.fgPrimary : shellTheme.accent)))
            },
            onPressed: onTap)
    }

    private func _ncIconButton(_ icon: IconData, active: Bool, size: Double = 28,
                               onTap: @escaping () -> Void) -> Widget {
        SizedBox(
            width: size, height: size,
            child: HoverButton(
                builder: { [self] _, states in
                    let hot = states.isHovered || states.isPressed
                    return DecoratedBox(
                        decoration: BoxDecoration(
                            color: active ? shellTheme.accent
                                : (hot ? shellTheme.controlHover : Color(0x00000000)),
                            borderRadius: FluentCorners.controlRadius),
                        child: Center(child: Icon(icon, size: size > 24 ? 14 : 12,
                                                  color: active ? shellTheme.accentInk : shellTheme.fgPrimary)))
                },
                onPressed: onTap))
    }

    private func _ncGlyphButton(_ glyph: FluentGlyphKind, onTap: @escaping () -> Void) -> Widget {
        SizedBox(
            width: 32, height: 24,
            child: HoverButton(
                builder: { [self] _, states in
                    let hot = states.isHovered || states.isPressed
                    return DecoratedBox(
                        decoration: BoxDecoration(
                            color: hot ? shellTheme.controlHover : Color(0x00000000),
                            borderRadius: FluentCorners.controlRadius),
                        child: Center(child: FluentGlyph(glyph, size: 10, color: shellTheme.fgSecondary)))
                },
                onPressed: onTap))
    }
}
