// Ported from: fluent_ui calendar date picker concepts
//
// CalendarDatePicker — a date picker that displays a text field trigger with a
// calendar icon. On tap, it opens a flyout containing a CalendarView for
// month-based date selection.

import FlutterSwiftBridge

// MARK: - CalendarDatePicker

/// A date picker that combines a formatted text display with a flyout-based
/// calendar grid.
///
/// When the user taps the trigger, a flyout opens containing a `CalendarView`.
/// Selecting a date in the calendar closes the flyout and fires `onDateChanged`.
///
/// Usage:
/// ```swift
/// CalendarDatePicker(
///     selectedDate: myDate,
///     onDateChanged: { date in print(date) },
///     placeholder: "Pick a date"
/// )
/// ```
public class CalendarDatePicker: StatefulWidget {
    /// The currently selected date. If nil, the placeholder is shown.
    public let selectedDate: FluentDateTime?

    /// Called when the user selects a date from the calendar.
    public let onDateChanged: ((FluentDateTime) -> Void)?

    /// The earliest selectable date.
    public let firstDate: FluentDateTime

    /// The latest selectable date.
    public let lastDate: FluentDateTime

    /// Placeholder text displayed when no date is selected.
    public let placeholder: String

    /// Optional header label displayed above the picker.
    public let header: String?

    /// Creates a calendar date picker.
    public init(
        key: (any Key)? = nil,
        selectedDate: FluentDateTime? = nil,
        onDateChanged: ((FluentDateTime) -> Void)? = nil,
        firstDate: FluentDateTime? = nil,
        lastDate: FluentDateTime? = nil,
        placeholder: String = "Select a date",
        header: String? = nil
    ) {
        self.selectedDate = selectedDate
        self.onDateChanged = onDateChanged
        self.firstDate = firstDate ?? FluentDateTime(year: 1926, month: 1, day: 1)
        self.lastDate = lastDate ?? FluentDateTime(year: 2051, month: 12, day: 31)
        self.placeholder = placeholder
        self.header = header
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _CalendarDatePickerState()
    }
}

// MARK: - _CalendarDatePickerState

class _CalendarDatePickerState: State<StatefulWidget> {
    private var picker: CalendarDatePicker {
        return widget as! CalendarDatePicker
    }

    private let flyoutController = FlyoutController()

    override func dispose() {
        flyoutController.closeFlyout()
        super.dispose()
    }

    // MARK: - Formatting

    private func _formatDate(_ date: FluentDateTime) -> String {
        let monthName = FluentDateTime.monthShortName(date.month)
        return "\(monthName) \(date.day), \(date.year)"
    }

    // MARK: - Build

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let isDisabled = picker.onDateChanged == nil

        let displayText: String
        let textColor: Color
        if let date = picker.selectedDate {
            displayText = _formatDate(date)
            textColor = theme.resources.textFillColorPrimary
        } else {
            displayText = picker.placeholder
            textColor = theme.resources.textFillColorSecondary
        }

        // Calendar icon (Unicode)
        let iconWidget: Widget = FluentGlyph(
            .calendar, size: 14, color: theme.resources.textFillColorSecondary)

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
                child: Padding(
                    padding: EdgeInsets(left: 10, right: 8),
                    child: Row(
                        mainAxisSize: .min,
                        children: [
                            Expanded(
                                child: Text(
                                    displayText,
                                    style: TextStyle(
                                        color: textColor,
                                        fontSize: 14
                                    )
                                )
                            ),
                            SizedBox(width: 8),
                            iconWidget,
                        ]
                    )
                )
            )
        )

        let trigger: Widget = FlyoutTarget(
            controller: flyoutController,
            child: HoverButton(
                builder: { [self] _, _ in
                    return triggerContent
                },
                onPressed: isDisabled ? nil : { [self] in
                    _openFlyout()
                }
            )
        )

        if let headerText = picker.header {
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
                return _CalendarDatePickerFlyoutContent(
                    selectedDate: picker.selectedDate,
                    firstDate: picker.firstDate,
                    lastDate: picker.lastDate,
                    onDateSelected: { [self] date in
                        flyoutController.closeFlyout()
                        picker.onDateChanged?(date)
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

// MARK: - _CalendarDatePickerFlyoutContent

/// The flyout popup containing a CalendarView and action buttons.
private class _CalendarDatePickerFlyoutContent: StatefulWidget {
    let selectedDate: FluentDateTime?
    let firstDate: FluentDateTime
    let lastDate: FluentDateTime
    let onDateSelected: (FluentDateTime) -> Void
    let onCancel: () -> Void

    init(
        key: (any Key)? = nil,
        selectedDate: FluentDateTime?,
        firstDate: FluentDateTime,
        lastDate: FluentDateTime,
        onDateSelected: @escaping (FluentDateTime) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.selectedDate = selectedDate
        self.firstDate = firstDate
        self.lastDate = lastDate
        self.onDateSelected = onDateSelected
        self.onCancel = onCancel
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> {
        return _CalendarDatePickerFlyoutContentState()
    }
}

class _CalendarDatePickerFlyoutContentState: State<StatefulWidget> {
    private var flyout: _CalendarDatePickerFlyoutContent {
        return widget as! _CalendarDatePickerFlyoutContent
    }

    /// Tracks the current selection inside the flyout (may differ from the
    /// outer selectedDate until the user confirms or the CalendarView calls back).
    private var _pendingDate: FluentDateTime?

    override func initState() {
        super.initState()
        _pendingDate = flyout.selectedDate
    }

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)

        let calendarWidget: Widget = CalendarView(
            selectedDate: _pendingDate,
            onDateChanged: { [self] date in
                setState {
                    _pendingDate = date
                }
            },
            displayedMonth: _pendingDate,
            firstDate: flyout.firstDate,
            lastDate: flyout.lastDate
        )

        // OK / Cancel row
        let okCancelRow: Widget = Row(
            mainAxisAlignment: .end,
            children: [
                _PickerActionButton(
                    icon: FluentGlyph(.check, size: 14),
                    onPressed: { [self] in
                        if let date = _pendingDate {
                            flyout.onDateSelected(date)
                        } else {
                            flyout.onCancel()
                        }
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
                    Padding(
                        padding: EdgeInsets(all: 8),
                        child: calendarWidget
                    ),
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
            constraints: BoxConstraints(minWidth: 260, maxWidth: 300)
        )
    }
}
