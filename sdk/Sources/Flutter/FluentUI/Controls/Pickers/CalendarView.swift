// Ported from: fluent_ui calendar concepts
//
// CalendarView — a month-at-a-time calendar grid.
// Displays a header with month/year + nav arrows, day-of-week labels, and a
// 6x7 grid of tappable day cells. Uses FluentDateTime for date math (no
// Foundation.Date dependency).

import FlutterSwiftBridge

// MARK: - CalendarView

/// A calendar grid view that displays one month at a time.
///
/// The user can tap a day cell to select a date and use left/right arrow
/// buttons to navigate between months. The currently selected date is
/// highlighted with the theme accent color and today's date shows a subtle
/// underline indicator.
///
/// Usage:
/// ```swift
/// CalendarView(
///     selectedDate: myDate,
///     onDateChanged: { date in print(date) }
/// )
/// ```
public class CalendarView: StatefulWidget {
    /// The currently selected date, or nil if nothing is selected.
    public let selectedDate: FluentDateTime?

    /// Called when the user taps a day cell.
    public let onDateChanged: ((FluentDateTime) -> Void)?

    /// The month initially displayed. Defaults to the current month.
    public let displayedMonth: FluentDateTime?

    /// The earliest selectable date.
    public let firstDate: FluentDateTime

    /// The latest selectable date.
    public let lastDate: FluentDateTime

    /// Creates a calendar view.
    public init(
        key: (any Key)? = nil,
        selectedDate: FluentDateTime? = nil,
        onDateChanged: ((FluentDateTime) -> Void)? = nil,
        displayedMonth: FluentDateTime? = nil,
        firstDate: FluentDateTime? = nil,
        lastDate: FluentDateTime? = nil
    ) {
        self.selectedDate = selectedDate
        self.onDateChanged = onDateChanged
        self.displayedMonth = displayedMonth
        self.firstDate = firstDate ?? FluentDateTime(year: 1926, month: 1, day: 1)
        self.lastDate = lastDate ?? FluentDateTime(year: 2051, month: 12, day: 31)
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _CalendarViewState()
    }
}

// MARK: - _CalendarViewState

class _CalendarViewState: State<StatefulWidget> {
    private var calendarView: CalendarView {
        return widget as! CalendarView
    }

    /// The year/month currently being displayed.
    private var _displayedYear: Int = 2026
    private var _displayedMonth: Int = 2

    override func initState() {
        super.initState()
        let initial = calendarView.displayedMonth ?? calendarView.selectedDate ?? FluentDateTime.now()
        _displayedYear = initial.year
        _displayedMonth = initial.month
    }

    // MARK: - Month Navigation

    private func _goToPreviousMonth() {
        setState {
            if _displayedMonth == 1 {
                _displayedMonth = 12
                _displayedYear -= 1
            } else {
                _displayedMonth -= 1
            }
            _clampDisplayedMonth()
        }
    }

    private func _goToNextMonth() {
        setState {
            if _displayedMonth == 12 {
                _displayedMonth = 1
                _displayedYear += 1
            } else {
                _displayedMonth += 1
            }
            _clampDisplayedMonth()
        }
    }

    private func _clampDisplayedMonth() {
        let first = calendarView.firstDate
        let last = calendarView.lastDate
        if _displayedYear < first.year
            || (_displayedYear == first.year && _displayedMonth < first.month) {
            _displayedYear = first.year
            _displayedMonth = first.month
        }
        if _displayedYear > last.year
            || (_displayedYear == last.year && _displayedMonth > last.month) {
            _displayedYear = last.year
            _displayedMonth = last.month
        }
    }

    private var _canGoBack: Bool {
        let first = calendarView.firstDate
        if _displayedYear > first.year { return true }
        if _displayedYear == first.year && _displayedMonth > first.month { return true }
        return false
    }

    private var _canGoForward: Bool {
        let last = calendarView.lastDate
        if _displayedYear < last.year { return true }
        if _displayedYear == last.year && _displayedMonth < last.month { return true }
        return false
    }

    // MARK: - Date Helpers

    /// Returns the day of the week (0 = Sunday, 6 = Saturday) for the first
    /// day of the given month/year using Zeller-like formula.
    private func _dayOfWeek(year: Int, month: Int, day: Int) -> Int {
        // Tomohiko Sakamoto's algorithm — returns 0 = Sunday ... 6 = Saturday
        var y = year
        let t = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
        if month < 3 { y -= 1 }
        let dow = (y + y / 4 - y / 100 + y / 400 + t[month - 1] + day) % 7
        return dow < 0 ? dow + 7 : dow
    }

    private func _isSelected(year: Int, month: Int, day: Int) -> Bool {
        guard let sel = calendarView.selectedDate else { return false }
        return sel.year == year && sel.month == month && sel.day == day
    }

    private func _isToday(year: Int, month: Int, day: Int) -> Bool {
        let now = FluentDateTime.now()
        return now.year == year && now.month == month && now.day == day
    }

    private func _isDateInRange(year: Int, month: Int, day: Int) -> Bool {
        let first = calendarView.firstDate
        let last = calendarView.lastDate
        // Compare year/month/day as a tuple
        let date = (year, month, day)
        let lo = (first.year, first.month, first.day)
        let hi = (last.year, last.month, last.day)
        return date >= lo && date <= hi
    }

    // MARK: - Build

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)

        return Column(
            mainAxisSize: .min,
            children: [
                _buildHeader(context, theme: theme),
                SizedBox(height: 4),
                _buildDayOfWeekLabels(theme: theme),
                SizedBox(height: 2),
                _buildDayGrid(context, theme: theme),
            ]
        )
    }

    // MARK: - Header (Month/Year + Nav Arrows)

    private func _buildHeader(_ context: any BuildContext, theme: FluentThemeData) -> Widget {
        let monthName = FluentDateTime.monthName(_displayedMonth)
        let title = "\(monthName) \(_displayedYear)"

        let titleWidget: Widget = Text(
            title,
            style: TextStyle(
                color: theme.resources.textFillColorPrimary,
                fontSize: 14,
                fontWeight: .w600
            )
        )

        let leftArrow: Widget = _CalendarNavButton(
            icon: FluentGlyph(.chevronLeft, size: 12),
            enabled: _canGoBack,
            onPressed: { [self] in _goToPreviousMonth() }
        )

        let rightArrow: Widget = _CalendarNavButton(
            icon: FluentGlyph(.chevronRight, size: 12),
            enabled: _canGoForward,
            onPressed: { [self] in _goToNextMonth() }
        )

        return Padding(
            padding: EdgeInsets(left: 4, right: 4),
            child: Row(
                mainAxisAlignment: .spaceBetween,
                children: [
                    titleWidget,
                    Row(
                        mainAxisSize: .min,
                        children: [
                            leftArrow,
                            SizedBox(width: 4),
                            rightArrow,
                        ]
                    ),
                ]
            )
        )
    }

    // MARK: - Day-of-Week Labels

    private func _buildDayOfWeekLabels(theme: FluentThemeData) -> Widget {
        let labels = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        var labelWidgets: [Widget] = []
        for label in labels {
            labelWidgets.append(
                SizedBox(
                    width: 32,
                    height: 20,
                    child: Center(
                        child: Text(
                            label,
                            style: TextStyle(
                                color: theme.resources.textFillColorSecondary,
                                fontSize: 12,
                                fontWeight: .w600
                            )
                        )
                    )
                )
            )
        }
        return Row(
            mainAxisAlignment: .spaceEvenly,
            children: labelWidgets
        )
    }

    // MARK: - Day Grid (6 rows x 7 columns)

    private func _buildDayGrid(_ context: any BuildContext, theme: FluentThemeData) -> Widget {
        let daysInMonth = FluentDateTime.daysInMonth(month: _displayedMonth, year: _displayedYear)
        let firstWeekday = _dayOfWeek(year: _displayedYear, month: _displayedMonth, day: 1)

        // Previous month info for leading cells
        var prevMonth = _displayedMonth - 1
        var prevYear = _displayedYear
        if prevMonth < 1 {
            prevMonth = 12
            prevYear -= 1
        }
        let daysInPrevMonth = FluentDateTime.daysInMonth(month: prevMonth, year: prevYear)

        // Next month info for trailing cells
        var nextMonth = _displayedMonth + 1
        var nextYear = _displayedYear
        if nextMonth > 12 {
            nextMonth = 1
            nextYear += 1
        }

        // Build 6 rows of 7 cells
        var rows: [Widget] = []
        var dayCounter = 1
        var nextMonthDay = 1

        for row in 0..<6 {
            var cells: [Widget] = []
            for col in 0..<7 {
                let cellIndex = row * 7 + col

                if cellIndex < firstWeekday {
                    // Leading days from previous month
                    let prevDay = daysInPrevMonth - firstWeekday + cellIndex + 1
                    cells.append(
                        _buildDayCell(
                            context,
                            theme: theme,
                            day: prevDay,
                            month: prevMonth,
                            year: prevYear,
                            isCurrentMonth: false
                        )
                    )
                } else if dayCounter <= daysInMonth {
                    // Current month days
                    let d = dayCounter
                    cells.append(
                        _buildDayCell(
                            context,
                            theme: theme,
                            day: d,
                            month: _displayedMonth,
                            year: _displayedYear,
                            isCurrentMonth: true
                        )
                    )
                    dayCounter += 1
                } else {
                    // Trailing days from next month
                    let nd = nextMonthDay
                    cells.append(
                        _buildDayCell(
                            context,
                            theme: theme,
                            day: nd,
                            month: nextMonth,
                            year: nextYear,
                            isCurrentMonth: false
                        )
                    )
                    nextMonthDay += 1
                }
            }
            rows.append(
                Row(
                    mainAxisAlignment: .spaceEvenly,
                    children: cells
                )
            )
        }

        return Column(
            mainAxisSize: .min,
            children: rows
        )
    }

    // MARK: - Single Day Cell

    private func _buildDayCell(
        _ context: any BuildContext,
        theme: FluentThemeData,
        day: Int,
        month: Int,
        year: Int,
        isCurrentMonth: Bool
    ) -> Widget {
        let selected = _isSelected(year: year, month: month, day: day)
        let today = _isToday(year: year, month: month, day: day)
        let inRange = _isDateInRange(year: year, month: month, day: day)
        let enabled = isCurrentMonth && inRange && calendarView.onDateChanged != nil

        let textColor: Color
        if selected {
            textColor = Color(0xFFFFFFFF)
        } else if !isCurrentMonth {
            textColor = theme.resources.textFillColorDisabled
        } else if !inRange {
            textColor = theme.resources.textFillColorDisabled
        } else {
            textColor = theme.resources.textFillColorPrimary
        }

        let fontWeight: FontWeight = today ? .w700 : .w400

        let textWidget: Widget = Text(
            "\(day)",
            style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: fontWeight
            )
        )

        // Build cell content
        return HoverButton(
            builder: { _, states in
                let bgColor: Color
                if selected {
                    bgColor = theme.accentColor.normal
                } else if enabled && states.isPressed {
                    bgColor = theme.resources.subtleFillColorTertiary
                } else if enabled && states.isHovered {
                    bgColor = theme.resources.subtleFillColorSecondary
                } else {
                    bgColor = Color(0x00000000)
                }

                var cellChildren: [Widget] = [
                    Center(child: textWidget)
                ]

                // Today indicator: a small bar below the number
                if today && !selected {
                    cellChildren.append(
                        Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                                padding: EdgeInsets(bottom: 2),
                                child: SizedBox(
                                    width: 16,
                                    height: 2,
                                    child: DecoratedBox(
                                        decoration: BoxDecoration(
                                            color: theme.accentColor.normal,
                                            borderRadius: BorderRadius.circular(1)
                                        )
                                    )
                                )
                            )
                        )
                    )
                }

                let inner: Widget
                if cellChildren.count == 1 {
                    inner = cellChildren[0]
                } else {
                    inner = Stack(children: cellChildren)
                }

                return SizedBox(
                    width: 32,
                    height: 32,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(16)
                        ),
                        child: inner
                    )
                )
            },
            onPressed: enabled ? { [self] in
                let newDate = FluentDateTime(
                    year: year,
                    month: month,
                    day: day
                )
                calendarView.onDateChanged?(newDate)
            } : nil
        )
    }
}

// MARK: - _CalendarNavButton

/// A small navigation arrow button used in the CalendarView header.
private class _CalendarNavButton: StatelessWidget {
    let icon: Widget
    let enabled: Bool
    let onPressed: () -> Void

    init(
        key: (any Key)? = nil,
        icon: Widget,
        enabled: Bool,
        onPressed: @escaping () -> Void
    ) {
        self.icon = icon
        self.enabled = enabled
        self.onPressed = onPressed
        super.init(key: key)
    }

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)

        return HoverButton(
            builder: { [self] _, states in
                let fgColor: Color
                if !enabled {
                    fgColor = theme.resources.textFillColorDisabled
                } else {
                    fgColor = theme.resources.textFillColorPrimary
                }

                let bgColor: Color
                if !enabled {
                    bgColor = Color(0x00000000)
                } else if states.isPressed {
                    bgColor = theme.resources.subtleFillColorTertiary
                } else if states.isHovered {
                    bgColor = theme.resources.subtleFillColorSecondary
                } else {
                    bgColor = Color(0x00000000)
                }

                return SizedBox(
                    width: 28,
                    height: 28,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(4)
                        ),
                        child: Center(
                            child: IconTheme(data: IconThemeData(color: fgColor), child: icon)
                        )
                    )
                )
            },
            onPressed: enabled ? { [self] in
                onPressed()
            } : nil
        )
    }
}
