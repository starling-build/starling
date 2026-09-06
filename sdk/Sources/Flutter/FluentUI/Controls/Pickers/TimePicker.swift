// Ported from: fluent_ui/lib/src/controls/pickers/time_picker.dart
//
// Simplified TimePicker — no text editing, uses flyout-based column selection.
// Displays hour / minute / (AM|PM) columns. Tapping opens a flyout with
// tappable items for selection.

import FlutterSwiftBridge

// MARK: - HourFormat

/// Defines the clock system used by the time picker.
public enum HourFormat {
    /// 12-hour format with AM/PM.
    case h12
    /// 24-hour format.
    case h24
}

// MARK: - TimePicker

/// A picker control that lets users select a time.
///
/// Displays a row of columns (hour / minute / AM|PM). Tapping opens a flyout
/// with tappable items for each column.
public class TimePicker: StatefulWidget {
    /// The currently selected time. If nil, placeholder text is shown.
    public let selected: FluentDateTime?

    /// Called when the user selects a new time.
    public let onChanged: ((FluentDateTime) -> Void)?

    /// Optional header label displayed above the picker.
    public let header: String?

    /// The clock system to use. Defaults to `.h12`.
    public let hourFormat: HourFormat

    /// The minute increment. For example, 15 shows only 00, 15, 30, 45.
    /// Defaults to 1.
    public let minuteIncrement: Int

    /// Creates a time picker.
    public init(
        key: (any Key)? = nil,
        selected: FluentDateTime? = nil,
        onChanged: ((FluentDateTime) -> Void)? = nil,
        header: String? = nil,
        hourFormat: HourFormat = .h12,
        minuteIncrement: Int = 1
    ) {
        self.selected = selected
        self.onChanged = onChanged
        self.header = header
        self.hourFormat = hourFormat
        self.minuteIncrement = max(1, minuteIncrement)
        super.init(key: key)
    }

    /// Whether this picker uses 24-hour format.
    public var use24Format: Bool {
        return hourFormat == .h24
    }

    public override func createState() -> State<StatefulWidget> {
        return _TimePickerState()
    }
}

// MARK: - _TimePickerState

class _TimePickerState: State<StatefulWidget> {
    private var timePicker: TimePicker {
        return widget as! TimePicker
    }

    private let flyoutController = FlyoutController()
    private var _workingTime: FluentDateTime = FluentDateTime.now()

    override func initState() {
        super.initState()
        _workingTime = timePicker.selected ?? FluentDateTime.now()
    }

    override func dispose() {
        flyoutController.closeFlyout()
        super.dispose()
    }

    // MARK: - Helpers

    private func _formatHour(_ hour: Int) -> String {
        if timePicker.use24Format {
            return String(format: "%02d", hour)
        } else {
            let displayHour = hour % 12
            return displayHour == 0 ? "12" : "\(displayHour)"
        }
    }

    private func _formatMinute(_ minute: Int) -> String {
        return String(format: "%02d", minute)
    }

    private var _isPm: Bool {
        let time = timePicker.selected ?? _workingTime
        return time.hour >= 12
    }

    // MARK: - Build

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let isDisabled = timePicker.onChanged == nil
        let displayTime = timePicker.selected

        // Build field text widgets
        var fieldWidgets: [Widget] = []

        // Hour
        let hourText: String
        if let dt = displayTime {
            hourText = _formatHour(dt.hour)
        } else {
            hourText = "hour"
        }

        fieldWidgets.append(
            Expanded(
                child: Center(
                    child: Text(
                        hourText,
                        style: TextStyle(
                            color: displayTime == nil
                                ? theme.resources.textFillColorSecondary
                                : theme.resources.textFillColorPrimary,
                            fontSize: 14
                        )
                    )
                )
            )
        )

        // Divider
        fieldWidgets.append(
            SizedBox(
                width: 1,
                height: 32,
                child: ColoredBox(color: theme.resources.dividerStrokeColorDefault)
            )
        )

        // Minute
        let minuteText: String
        if let dt = displayTime {
            minuteText = _formatMinute(dt.minute)
        } else {
            minuteText = "min"
        }

        fieldWidgets.append(
            Expanded(
                child: Center(
                    child: Text(
                        minuteText,
                        style: TextStyle(
                            color: displayTime == nil
                                ? theme.resources.textFillColorSecondary
                                : theme.resources.textFillColorPrimary,
                            fontSize: 14
                        )
                    )
                )
            )
        )

        // AM/PM (for 12-hour format)
        if !timePicker.use24Format {
            fieldWidgets.append(
                SizedBox(
                    width: 1,
                    height: 32,
                    child: ColoredBox(color: theme.resources.dividerStrokeColorDefault)
                )
            )

            let amPmText: String
            if displayTime != nil {
                amPmText = _isPm ? "PM" : "AM"
            } else {
                amPmText = "AM/PM"
            }

            fieldWidgets.append(
                Expanded(
                    child: Center(
                        child: Text(
                            amPmText,
                            style: TextStyle(
                                color: displayTime == nil
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
                    _workingTime = timePicker.selected ?? FluentDateTime.now()
                    _openFlyout()
                }
            )
        )

        if let headerText = timePicker.header {
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
                return _TimePickerFlyoutContent(
                    time: _workingTime,
                    use24Format: timePicker.use24Format,
                    minuteIncrement: timePicker.minuteIncrement,
                    onConfirm: { [self] time in
                        flyoutController.closeFlyout()
                        timePicker.onChanged?(time)
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

// MARK: - _TimePickerFlyoutContent

/// The flyout popup content for the time picker.
private class _TimePickerFlyoutContent: StatefulWidget {
    let time: FluentDateTime
    let use24Format: Bool
    let minuteIncrement: Int
    let onConfirm: (FluentDateTime) -> Void
    let onCancel: () -> Void

    init(
        key: (any Key)? = nil,
        time: FluentDateTime,
        use24Format: Bool,
        minuteIncrement: Int,
        onConfirm: @escaping (FluentDateTime) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.time = time
        self.use24Format = use24Format
        self.minuteIncrement = minuteIncrement
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> {
        return _TimePickerFlyoutContentState()
    }
}

class _TimePickerFlyoutContentState: State<StatefulWidget> {
    private var flyout: _TimePickerFlyoutContent {
        return widget as! _TimePickerFlyoutContent
    }

    private var _localTime: FluentDateTime = FluentDateTime.now()

    override func initState() {
        super.initState()
        _localTime = flyout.time
        // Snap minute to nearest valid increment
        if flyout.minuteIncrement > 1 {
            let possibleMinutes = _minuteValues()
            _localTime.minute = _closestMinute(possibleMinutes, _localTime.minute)
        }
    }

    private func _minuteValues() -> [Int] {
        var values: [Int] = []
        var m = 0
        while m < 60 {
            values.append(m)
            m += flyout.minuteIncrement
        }
        return values
    }

    private func _closestMinute(_ possible: [Int], _ target: Int) -> Int {
        var closest = possible[0]
        for m in possible {
            if abs(m - target) < abs(closest - target) {
                closest = m
            }
        }
        return closest
    }

    // MARK: - Build

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)

        var columnWidgets: [Widget] = []

        // Hour column
        columnWidgets.append(Expanded(child: _buildHourColumn(context)))

        columnWidgets.append(
            SizedBox(
                width: 1,
                child: ColoredBox(color: theme.resources.dividerStrokeColorDefault)
            )
        )

        // Minute column
        columnWidgets.append(Expanded(child: _buildMinuteColumn(context)))

        // AM/PM column (12-hour only)
        if !flyout.use24Format {
            columnWidgets.append(
                SizedBox(
                    width: 1,
                    child: ColoredBox(color: theme.resources.dividerStrokeColorDefault)
                )
            )
            columnWidgets.append(Expanded(child: _buildAmPmColumn(context)))
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
                        flyout.onConfirm(_localTime)
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

        let minWidth: Double = flyout.use24Format ? 200 : 260

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
            constraints: BoxConstraints(minWidth: minWidth, maxWidth: minWidth + 40)
        )
    }

    // MARK: - Hour Column

    private func _buildHourColumn(_ context: any BuildContext) -> Widget {
        let hoursCount = flyout.use24Format ? 24 : 12

        var items: [Widget] = []
        for i in 0..<hoursCount {
            let hour: Int
            if flyout.use24Format {
                hour = i
            } else {
                // For 12-hour: display 12, 1, 2, ..., 11
                hour = i == 0 ? 12 : i
            }

            let actualHour: Int
            if flyout.use24Format {
                actualHour = i
            } else {
                let isPm = _localTime.hour >= 12
                if isPm {
                    actualHour = i == 0 ? 12 : i + 12
                } else {
                    actualHour = i == 0 ? 0 : i
                }
            }

            let displayHour: Int
            if flyout.use24Format {
                displayHour = _localTime.hour
            } else {
                let h = _localTime.hour % 12
                displayHour = h == 0 ? 12 : h
            }

            let isSelected = hour == displayHour

            items.append(
                _PickerItem(
                    text: flyout.use24Format ? String(format: "%02d", hour) : "\(hour)",
                    isSelected: isSelected,
                    onTap: { [self] in
                        setState {
                            _localTime.hour = actualHour
                        }
                    }
                )
            )
        }

        return _PickerScrollColumn(children: items)
    }

    // MARK: - Minute Column

    private func _buildMinuteColumn(_ context: any BuildContext) -> Widget {
        let minutes = _minuteValues()

        var items: [Widget] = []
        for m in minutes {
            let isSelected = m == _localTime.minute
            items.append(
                _PickerItem(
                    text: String(format: "%02d", m),
                    isSelected: isSelected,
                    onTap: { [self] in
                        setState {
                            _localTime.minute = m
                        }
                    }
                )
            )
        }

        return _PickerScrollColumn(children: items)
    }

    // MARK: - AM/PM Column

    private func _buildAmPmColumn(_ context: any BuildContext) -> Widget {
        let isAm = _localTime.hour < 12

        let amItem = _PickerItem(
            text: "AM",
            isSelected: isAm,
            onTap: { [self] in
                setState {
                    if _localTime.hour >= 12 {
                        _localTime.hour -= 12
                    }
                }
            }
        )

        let pmItem = _PickerItem(
            text: "PM",
            isSelected: !isAm,
            onTap: { [self] in
                setState {
                    if _localTime.hour < 12 {
                        _localTime.hour += 12
                    }
                }
            }
        )

        return _PickerScrollColumn(children: [amItem, pmItem])
    }
}
