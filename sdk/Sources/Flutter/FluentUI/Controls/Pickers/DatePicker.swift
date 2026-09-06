// Ported from: fluent_ui/lib/src/controls/pickers/date_picker.dart
//
// Simplified DatePicker — no text editing, uses flyout-based column selection.
// Displays month / day / year columns; tapping opens a flyout with tappable
// number items for each column.

import FlutterSwiftBridge

// MARK: - FluentDateTime

/// A simple date/time struct used by DatePicker and TimePicker.
///
/// Avoids depending on Foundation.Date and mirrors Dart's DateTime enough
/// to satisfy picker needs.
public struct FluentDateTime: Equatable, Hashable {
    public var year: Int
    public var month: Int   // 1-12
    public var day: Int     // 1-31
    public var hour: Int    // 0-23
    public var minute: Int  // 0-59
    public var second: Int  // 0-59

    public init(
        year: Int = 2026,
        month: Int = 1,
        day: Int = 1,
        hour: Int = 0,
        minute: Int = 0,
        second: Int = 0
    ) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
    }

    /// Returns a new FluentDateTime that represents "now" (fixed stub — real
    /// implementation would read the system clock).
    public static func now() -> FluentDateTime {
        // Use a reasonable default; real implementation would call
        // Foundation/Date but we keep this dependency-free.
        return FluentDateTime(year: 2026, month: 2, day: 24, hour: 12, minute: 0, second: 0)
    }

    /// Number of days in the given month/year (handles leap years).
    public static func daysInMonth(month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2:
            let isLeap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
            return isLeap ? 29 : 28
        default: return 30
        }
    }

    /// Month name (English).
    public static func monthName(_ month: Int) -> String {
        let names = [
            "", "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
        ]
        guard month >= 1 && month <= 12 else { return "?" }
        return names[month]
    }

    /// Short month name (English).
    public static func monthShortName(_ month: Int) -> String {
        let names = [
            "", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
        ]
        guard month >= 1 && month <= 12 else { return "?" }
        return names[month]
    }
}

// MARK: - DatePickerField

/// The fields displayed in a DatePicker.
public enum DatePickerField {
    case month
    case day
    case year
}

// MARK: - DatePicker

/// A picker control that lets users select a date.
///
/// Displays a row of 3 columns (month / day / year). Tapping opens a flyout
/// with tappable items for each column.
public class DatePicker: StatefulWidget {
    /// The currently selected date. If nil, placeholder text is shown.
    public let selected: FluentDateTime?

    /// Called when the user selects a new date.
    public let onChanged: ((FluentDateTime) -> Void)?

    /// Optional header label displayed above the picker.
    public let header: String?

    /// The earliest selectable date.
    public let startDate: FluentDateTime

    /// The latest selectable date.
    public let endDate: FluentDateTime

    /// The order of the fields. Defaults to [.month, .day, .year].
    public let fieldOrder: [DatePickerField]

    /// Creates a date picker.
    public init(
        key: (any Key)? = nil,
        selected: FluentDateTime? = nil,
        onChanged: ((FluentDateTime) -> Void)? = nil,
        header: String? = nil,
        startDate: FluentDateTime? = nil,
        endDate: FluentDateTime? = nil,
        fieldOrder: [DatePickerField] = [.month, .day, .year]
    ) {
        self.selected = selected
        self.onChanged = onChanged
        self.header = header
        self.startDate = startDate ?? FluentDateTime(year: 1926, month: 1, day: 1)
        self.endDate = endDate ?? FluentDateTime(year: 2051, month: 12, day: 31)
        self.fieldOrder = fieldOrder
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _DatePickerState()
    }
}

// MARK: - _DatePickerState

class _DatePickerState: State<StatefulWidget> {
    private var datePicker: DatePicker {
        return widget as! DatePicker
    }

    private let flyoutController = FlyoutController()

    /// The working date inside the flyout (not yet confirmed).
    private var _workingDate: FluentDateTime = FluentDateTime.now()

    override func initState() {
        super.initState()
        _workingDate = datePicker.selected ?? FluentDateTime.now()
    }

    override func dispose() {
        flyoutController.closeFlyout()
        super.dispose()
    }

    // MARK: - Build

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let isDisabled = datePicker.onChanged == nil

        let displayDate = datePicker.selected

        // Build the field text widgets in the specified order
        var fieldWidgets: [Widget] = []
        for (index, field) in datePicker.fieldOrder.enumerated() {
            if index > 0 {
                fieldWidgets.append(
                    SizedBox(
                        width: 1,
                        height: 32,
                        child: ColoredBox(color: theme.resources.dividerStrokeColorDefault)
                    )
                )
            }
            let text: String
            switch field {
            case .month:
                text = displayDate != nil ? FluentDateTime.monthShortName(displayDate!.month) : "month"
            case .day:
                text = displayDate != nil ? "\(displayDate!.day)" : "day"
            case .year:
                text = displayDate != nil ? "\(displayDate!.year)" : "year"
            }
            let flex: Int
            switch field {
            case .month: flex = 2
            case .day: flex = 1
            case .year: flex = 1
            }
            fieldWidgets.append(
                Expanded(
                    flex: flex,
                    child: Center(
                        child: Text(
                            text,
                            style: TextStyle(
                                color: displayDate == nil
                                    ? theme.resources.textFillColorSecondary
                                    : theme.resources.textFillColorPrimary,
                                fontSize: 14
                            )
                        )
                    )
                )
            )
        }

        let triggerContent: Widget = SizedBox(
            height: 32,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: theme.resources.controlFillColorDefault,
                    border: Border.all(
                        color: theme.resources.controlStrokeColorDefault,
                        width: 1
                    ),
                    borderRadius: BorderRadius.circular(4)
                ),
                child: Row(children: fieldWidgets)
            )
        )

        let trigger: Widget = FlyoutTarget(
            controller: flyoutController,
            child: HoverButton(
                builder: { [self] _, _ in
                    return triggerContent
                },
                onPressed: isDisabled ? nil : { [self] in
                    _workingDate = datePicker.selected ?? FluentDateTime.now()
                    _openFlyout()
                }
            )
        )

        if let headerText = datePicker.header {
            return Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: [
                    Padding(
                        padding: EdgeInsets(bottom: 4),
                        child: Text(
                            headerText,
                            style: TextStyle(
                                color: theme.resources.textFillColorPrimary,
                                fontSize: 14,
                                fontWeight: .w600
                            )
                        )
                    ),
                    trigger,
                ]
            )
        }

        return trigger
    }

    // MARK: - Flyout

    private func _openFlyout() {
        flyoutController.showFlyout(
            builder: { [self] context in
                return _DatePickerFlyoutContent(
                    date: _workingDate,
                    startDate: datePicker.startDate,
                    endDate: datePicker.endDate,
                    fieldOrder: datePicker.fieldOrder,
                    onConfirm: { [self] date in
                        flyoutController.closeFlyout()
                        datePicker.onChanged?(date)
                    },
                    onCancel: { [self] in
                        flyoutController.closeFlyout()
                    }
                )
            },
            barrierDismissible: true,
            placement: .bottom
        )
    }
}

// MARK: - _DatePickerFlyoutContent

/// The flyout popup content for the date picker.
/// Displays 3 scrollable columns (month, day, year) and OK/Cancel buttons.
private class _DatePickerFlyoutContent: StatefulWidget {
    let date: FluentDateTime
    let startDate: FluentDateTime
    let endDate: FluentDateTime
    let fieldOrder: [DatePickerField]
    let onConfirm: (FluentDateTime) -> Void
    let onCancel: () -> Void

    init(
        key: (any Key)? = nil,
        date: FluentDateTime,
        startDate: FluentDateTime,
        endDate: FluentDateTime,
        fieldOrder: [DatePickerField],
        onConfirm: @escaping (FluentDateTime) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.date = date
        self.startDate = startDate
        self.endDate = endDate
        self.fieldOrder = fieldOrder
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> {
        return _DatePickerFlyoutContentState()
    }
}

class _DatePickerFlyoutContentState: State<StatefulWidget> {
    private var flyout: _DatePickerFlyoutContent {
        return widget as! _DatePickerFlyoutContent
    }

    private var _localDate: FluentDateTime = FluentDateTime.now()

    override func initState() {
        super.initState()
        _localDate = flyout.date
    }

    // MARK: - Build

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)

        // Build the columns in the specified field order
        var columnWidgets: [Widget] = []
        for (index, field) in flyout.fieldOrder.enumerated() {
            if index > 0 {
                columnWidgets.append(
                    SizedBox(
                        width: 1,
                        child: ColoredBox(color: theme.resources.dividerStrokeColorDefault)
                    )
                )
            }
            switch field {
            case .month:
                columnWidgets.append(Expanded(flex: 2, child: _buildMonthColumn(context)))
            case .day:
                columnWidgets.append(Expanded(child: _buildDayColumn(context)))
            case .year:
                columnWidgets.append(Expanded(child: _buildYearColumn(context)))
            }
        }

        let columns: Widget = SizedBox(
            height: 200,
            child: Row(
                crossAxisAlignment: .start,
                children: columnWidgets
            )
        )

        // OK / Cancel row
        let okCancelRow: Widget = Row(
            mainAxisAlignment: .end,
            children: [
                _PickerActionButton(
                    icon: FluentGlyph(.check, size: 14),
                    onPressed: { [self] in
                        flyout.onConfirm(_localDate)
                    }
                ),
                SizedBox(width: 4),
                _PickerActionButton(
                    icon: FluentGlyph(.dismiss, size: 14),
                    onPressed: { [self] in
                        flyout.onCancel()
                    }
                ),
            ]
        )

        return FlyoutContent(
            child: Column(
                mainAxisSize: .min,
                children: [
                    columns,
                    SizedBox(
                        height: 1,
                        child: ColoredBox(
                            color: theme.resources.dividerStrokeColorDefault
                        )
                    ),
                    Padding(
                        padding: EdgeInsets(all: 4),
                        child: okCancelRow
                    ),
                ]
            ),
            padding: EdgeInsets(all: 0),
            constraints: BoxConstraints(minWidth: 280, maxWidth: 320)
        )
    }

    // MARK: - Month Column

    private func _buildMonthColumn(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)

        var items: [Widget] = []
        for m in 1...12 {
            let isSelected = m == _localDate.month
            items.append(
                _PickerItem(
                    text: FluentDateTime.monthName(m),
                    isSelected: isSelected,
                    onTap: { [self] in
                        let daysInNewMonth = FluentDateTime.daysInMonth(month: m, year: _localDate.year)
                        let clampedDay = min(_localDate.day, daysInNewMonth)
                        setState {
                            _localDate.month = m
                            _localDate.day = clampedDay
                        }
                    }
                )
            )
        }

        return _PickerScrollColumn(children: items)
    }

    // MARK: - Day Column

    private func _buildDayColumn(_ context: any BuildContext) -> Widget {
        let daysInMonth = FluentDateTime.daysInMonth(month: _localDate.month, year: _localDate.year)

        var items: [Widget] = []
        for d in 1...daysInMonth {
            let isSelected = d == _localDate.day
            items.append(
                _PickerItem(
                    text: "\(d)",
                    isSelected: isSelected,
                    onTap: { [self] in
                        setState {
                            _localDate.day = d
                        }
                    }
                )
            )
        }

        return _PickerScrollColumn(children: items)
    }

    // MARK: - Year Column

    private func _buildYearColumn(_ context: any BuildContext) -> Widget {
        let startYear = flyout.startDate.year
        let endYear = flyout.endDate.year

        var items: [Widget] = []
        for y in startYear...endYear {
            let isSelected = y == _localDate.year
            items.append(
                _PickerItem(
                    text: "\(y)",
                    isSelected: isSelected,
                    onTap: { [self] in
                        let daysInMonth = FluentDateTime.daysInMonth(month: _localDate.month, year: y)
                        let clampedDay = min(_localDate.day, daysInMonth)
                        setState {
                            _localDate.year = y
                            _localDate.day = clampedDay
                        }
                    }
                )
            )
        }

        return _PickerScrollColumn(children: items)
    }
}

// MARK: - _PickerScrollColumn

/// A column of picker items. In a full implementation, this would scroll.
/// For our simplified version, items are displayed in a Column clipped by the
/// parent SizedBox.
/// Internal access so TimePicker can reuse.
class _PickerScrollColumn: StatelessWidget {
    let children: [Widget]

    init(key: (any Key)? = nil, children: [Widget]) {
        self.children = children
        super.init(key: key)
    }

    override func build(_ context: any BuildContext) -> Widget {
        return ClipRect(
            child: Column(
                mainAxisSize: .min,
                children: children
            )
        )
    }
}

// MARK: - _PickerItem

/// A single tappable item in a picker column.
/// Internal access so TimePicker can reuse.
class _PickerItem: StatelessWidget {
    let text: String
    let isSelected: Bool
    let onTap: () -> Void

    init(
        key: (any Key)? = nil,
        text: String,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) {
        self.text = text
        self.isSelected = isSelected
        self.onTap = onTap
        super.init(key: key)
    }

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)

        let bgColor: Color = isSelected
            ? theme.accentColor.normal
            : Color(0x00000000)
        let fgColor: Color = isSelected
            ? Color(0xFFFFFFFF)
            : theme.resources.textFillColorPrimary

        return HoverButton(
            builder: { [self] _, states in
                let hoverBg: Color
                if isSelected {
                    hoverBg = bgColor
                } else if states.isPressed {
                    hoverBg = theme.resources.subtleFillColorTertiary
                } else if states.isHovered {
                    hoverBg = theme.resources.subtleFillColorSecondary
                } else {
                    hoverBg = Color(0x00000000)
                }

                return SizedBox(
                    height: 36,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: hoverBg,
                            borderRadius: BorderRadius.circular(4)
                        ),
                        child: Center(
                            child: Text(
                                text,
                                style: TextStyle(
                                    color: isSelected ? fgColor : theme.resources.textFillColorPrimary,
                                    fontSize: 14,
                                    fontWeight: isSelected ? .w600 : .w400
                                )
                            )
                        )
                    )
                )
            },
            onPressed: { [self] in
                onTap()
            }
        )
    }
}

// MARK: - _PickerActionButton

/// A small action button (checkmark or X) used in picker OK/Cancel rows.
/// Internal access so TimePicker can reuse.
class _PickerActionButton: StatelessWidget {
    let icon: Widget
    let onPressed: () -> Void

    init(
        key: (any Key)? = nil,
        icon: Widget,
        onPressed: @escaping () -> Void
    ) {
        self.icon = icon
        self.onPressed = onPressed
        super.init(key: key)
    }

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)

        return HoverButton(
            builder: { [self] _, states in
                let bgColor: Color
                if states.isPressed {
                    bgColor = theme.resources.subtleFillColorTertiary
                } else if states.isHovered {
                    bgColor = theme.resources.subtleFillColorSecondary
                } else {
                    bgColor = Color(0x00000000)
                }

                return SizedBox(
                    width: 40,
                    height: 32,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(4)
                        ),
                        child: Center(
                            child: IconTheme(data: IconThemeData(color: theme.resources.textFillColorPrimary), child: icon)
                        )
                    )
                )
            },
            onPressed: { [self] in
                onPressed()
            }
        )
    }
}
