// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// One page per ported control, each a `SamplePage` of one to three
// examples with the options that matter. The order is the catalog's.

#if os(Linux)
import Flutter
import FlutterSwiftBridge
import FluentSystemIcons

// MARK: - Basic input

final class ButtonPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "Button",
            "A control that responds to user input and raises a Click event. The standard button is the neutral control fill with a 4px corner; the accent button is for the one primary action on a surface.",
            samples: [
                Sample("A simple button", child: Row(spacing: FluentSpacing.s) {
                    Button(onPressed: {}, child: Text("Standard button"))
                    Button(onPressed: nil, child: Text("Disabled"))
                }),
                Sample("Accent button", child: Row(spacing: FluentSpacing.s) {
                    FilledButton(onPressed: {}, child: Text("Accent button"))
                    FilledButton(onPressed: nil, child: Text("Disabled"))
                }),
                Sample("Icon buttons", child: Row(spacing: FluentSpacing.s) {
                    IconButton(icon: Icon(FluentSystemIcons.add), onPressed: {})
                    IconButton(icon: Icon(FluentSystemIcons.edit), onPressed: {})
                    IconButton(icon: Icon(FluentSystemIcons.delete), onPressed: {})
                    Button(onPressed: {}, child: Row(spacing: FluentSpacing.s) {
                        Icon(FluentSystemIcons.share, size: 16)
                        Text("Share")
                    })
                }),
            ])
    }
}

final class DropDownButtonPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "DropDownButton",
            "A button that opens a menu flyout of choices. The chevron is the affordance; the flyout is acrylic at elevation 32.",
            samples: [
                Sample("With text and a menu", child: DropDownButton(
                    title: Text("Email"),
                    items: [
                        MenuFlyoutItem(text: Text("Send"), leading: Icon(FluentSystemIcons.forward), onPressed: {}),
                        MenuFlyoutItem(text: Text("Reply"), leading: Icon(FluentSystemIcons.back), onPressed: {}),
                        MenuFlyoutItem(text: Text("Reply all"), leading: Icon(FluentSystemIcons.share), onPressed: {}),
                    ])),
                Sample("With an icon", child: DropDownButton(
                    leading: Icon(FluentSystemIcons.more),
                    items: [
                        MenuFlyoutItem(text: Text("Rename"), onPressed: {}),
                        MenuFlyoutItem(text: Text("Delete"), onPressed: {}),
                    ])),
            ])
    }
}

final class HyperlinkButtonPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "HyperlinkButton",
            "A button that appears as hyperlink text: accent-coloured, no backplate at rest, a subtle fill on hover.",
            samples: [
                Sample("A hyperlink button", child: HyperlinkButton(onPressed: {}, child: Text("Fluent Design System"))),
                Sample("Disabled", child: HyperlinkButton(onPressed: nil, child: Text("Not available"))),
            ])
    }
}

final class ToggleButtonPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "ToggleButton",
            "A button that can be switched between two states, like Bold in a text editor. Checked, it takes the accent fill.",
            samples: [
                Sample("A toggle button", child: LocalState(false) { on, set in
                    Row(spacing: FluentSpacing.m) {
                        ToggleButton(checked: on, onChanged: set, child: Text(on ? "On" : "Off"))
                        ToggleButton(checked: on, onChanged: set, child: Icon(FluentSystemIcons.pin, size: 16))
                    }
                }),
            ])
    }
}

final class SplitButtonPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "SplitButton",
            "Two buttons that touch: the primary action, and a chevron that opens a flyout of alternatives. The corners where the two meet are not rounded.",
            samples: [
                Sample("A split button", child: SplitButton(
                    child: Padding(padding: EdgeInsets(left: 12, top: 6, right: 12, bottom: 6)) { Text("Choose colour") },
                    flyout: FlyoutContent(child: Column(crossAxisAlignment: .start, spacing: FluentSpacing.xs) {
                        Text("Red")
                        Text("Green")
                        Text("Blue")
                    }),
                    onPressed: {})),
            ])
    }
}

final class CheckboxPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "CheckBox",
            "A control a user can select or clear. A checkbox can also be indeterminate, for a group whose members disagree.",
            samples: [
                Sample("Two-state", child: LocalState<Bool?>(true) { v, set in
                    Checkbox(checked: v, onChanged: set, content: Text("Two-state CheckBox"))
                }),
                Sample("Three-state", child: LocalState<Bool?>(nil) { v, set in
                    Column(crossAxisAlignment: .start, spacing: FluentSpacing.s) {
                        Checkbox(checked: v, onChanged: { _ in
                            // Cycle unchecked → checked → indeterminate.
                            switch v {
                            case .some(false): set(true)
                            case .some(true): set(nil)
                            default: set(false)
                            }
                        }, content: Text("Select all"))
                        Padding(padding: EdgeInsets(left: 28, top: 0, right: 0, bottom: 0)) {
                            Column(crossAxisAlignment: .start, spacing: FluentSpacing.xs) {
                                Checkbox(checked: v ?? true, onChanged: { c in set(c) }, content: Text("Option 1"))
                                Checkbox(checked: v == nil ? false : (v ?? false), onChanged: { c in set(c) }, content: Text("Option 2"))
                            }
                        }
                    }
                }),
                Sample("Disabled", child: Checkbox(checked: true, onChanged: nil, content: Text("Disabled"))),
            ])
    }
}

final class ColorPickerPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "ColorPicker",
            "A spectrum, a value slider and a preview for choosing a colour.",
            samples: [
                Sample("A colour picker", child: LocalState(Color(0xFF0078D4)) { c, set in
                    Row(crossAxisAlignment: .start, spacing: FluentSpacing.xxl) {
                        SizedBox(width: 360, height: 320, child: ColorPicker(color: c, onChanged: set))
                        DecoratedBox(
                            decoration: BoxDecoration(color: c, borderRadius: FluentCorners.overlayRadius),
                            child: SizedBox(width: 96, height: 96))
                    }
                }),
            ])
    }
}

final class ComboBoxPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "ComboBox",
            "A drop-down list of items to select one from. Closed, it shows the selection; open, it is a flyout.",
            samples: [
                Sample("Pick a colour", child: LocalState<String?>(nil) { v, set in
                    SizedBox(width: 200, child: ComboBox<String>(
                        value: v,
                        items: ["Red", "Green", "Blue", "Yellow"].map { ComboBoxItem(value: $0, child: Text($0)) },
                        onChanged: set,
                        placeholder: Text("Pick a colour")))
                }),
            ])
    }
}

final class RadioButtonPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "RadioButton",
            "Select exactly one option from a set. The checked ring is the accent; the dot is the on-accent ink.",
            samples: [
                Sample("A group", child: LocalState(0) { v, set in
                    Column(crossAxisAlignment: .start, spacing: FluentSpacing.s) {
                        for (i, name) in ["Option 1", "Option 2", "Option 3"].enumerated() {
                            RadioButton<Int>(value: i, groupValue: v, onChanged: { n in set(n ?? 0) },
                                             content: Text(name))
                        }
                    }
                }),
            ])
    }
}

final class RatingPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "RatingControl",
            "Enter and display ratings as a row of stars.",
            samples: [
                Sample("Interactive", child: LocalState(3.0) { r, set in
                    Row(spacing: FluentSpacing.m) {
                        RatingBar(rating: r, onChanged: set, iconSize: 24)
                        Text("\(Int(r)) / 5")
                    }
                }),
                Sample("Read-only, ten stars", child: RatingBar(rating: 7, amount: 10, iconSize: 20)),
            ])
    }
}

final class SliderPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "Slider",
            "Select from a range of values by moving a thumb along a track. The filled part of the track is the accent; the rest is the strong control fill.",
            samples: [
                Sample("A simple slider", child: LocalState(40.0) { v, set in
                    Row(spacing: FluentSpacing.m) {
                        SizedBox(width: 280, child: Slider(value: v, onChanged: set))
                        Text("\(Int(v))")
                    }
                }),
                Sample("With steps", child: LocalState(500.0) { v, set in
                    Row(spacing: FluentSpacing.m) {
                        SizedBox(width: 280, child: Slider(value: v, onChanged: set, min: 0, max: 1000, divisions: 10))
                        Text("\(Int(v))")
                    }
                }),
                Sample("Disabled", child: SizedBox(width: 280, child: Slider(value: 30, onChanged: nil))),
            ])
    }
}

final class ToggleSwitchPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "ToggleSwitch",
            "A switch that can be toggled on or off, for a setting that takes effect immediately. On, the track is the accent and the knob the on-accent ink.",
            samples: [
                Sample("A simple toggle", child: LocalState(true) { v, set in
                    ToggleSwitch(checked: v, onChanged: set, content: Text(v ? "On" : "Off"))
                }),
                Sample("Content before the switch", child: LocalState(false) { v, set in
                    ToggleSwitch(checked: v, onChanged: set, content: Text("Wi-Fi"), leadingContent: true)
                }),
                Sample("Disabled", child: ToggleSwitch(checked: true, onChanged: nil, content: Text("Disabled"))),
            ])
    }
}

// MARK: - Text

final class TextBoxPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "TextBox",
            "A single-line or multi-line plain text field. Focused, the bottom edge takes a 2px accent underline — Windows' focus affordance for text.",
            samples: [
                Sample("A simple text box", child: SizedBox(width: 300, child: FluentTextBox(placeholderText: "Name"))),
                Sample("With a header, via InfoLabel", child: SizedBox(width: 300, child: InfoLabel(
                    label: "Email address", child: FluentTextBox(placeholderText: "someone@example.com")))),
                Sample("Multi-line", child: SizedBox(width: 400, child: FluentTextBox(
                    placeholderText: "Type a few lines…", maxLines: 4))),
                Sample("Read-only and disabled", child: Column(crossAxisAlignment: .start, spacing: FluentSpacing.s) {
                    SizedBox(width: 300, child: FluentTextBox(placeholderText: "Read-only", readOnly: true))
                    SizedBox(width: 300, child: FluentTextBox(placeholderText: "Disabled", enabled: false))
                }),
            ])
    }
}

final class PasswordBoxPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "PasswordBox",
            "A text field that hides what is typed, with a peek button to reveal it while pressed.",
            samples: [
                Sample("A password box", child: SizedBox(width: 300, child: PasswordBox())),
            ])
    }
}

final class NumberBoxPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "NumberBox",
            "A text field for numbers with spin buttons, a range, and small and large steps.",
            samples: [
                Sample("With a range", child: LocalState<Double?>(10) { v, set in
                    Row(spacing: FluentSpacing.m) {
                        SizedBox(width: 200, child: NumberBox(value: v, onChanged: set, min: 0, max: 100))
                        Text(v.map { "\(Int($0))" } ?? "—")
                    }
                }),
            ])
    }
}

final class AutoSuggestBoxPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        let cats = ["Abyssinian", "Bengal", "Birman", "Bombay", "Burmese", "Maine Coon", "Persian", "Ragdoll",
                    "Siamese", "Sphynx", "Tabby"]
        return SamplePage(
            "AutoSuggestBox",
            "A text field that suggests matches in a flyout as you type.",
            samples: [
                Sample("Cat breeds", child: SizedBox(width: 300, child: AutoSuggestBox(
                    items: cats.map { AutoSuggestBoxItem(value: $0) },
                    placeholderText: "Type a breed",
                    leadingIcon: Icon(FluentSystemIcons.search, size: 16)))),
            ])
    }
}

final class InfoLabelPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "InfoLabel",
            "A label above a control, 12px from it — the Windows rule for a control and its label.",
            samples: [
                Sample("Labels", child: Column(crossAxisAlignment: .start, spacing: FluentSpacing.l) {
                    InfoLabel(label: "First name", child: SizedBox(width: 240, child: FluentTextBox(placeholderText: "")))
                    InfoLabel(label: "Header style", isHeader: true, child: SizedBox(width: 240, child: FluentTextBox(placeholderText: "")))
                }),
            ])
    }
}

// MARK: - Date & time

final class CalendarViewPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "CalendarView",
            "A month view for picking a date. Today is ringed in the accent; the selection is filled with it.",
            samples: [
                Sample("A calendar", child: LocalState<FluentDateTime?>(nil) { d, set in
                    Column(crossAxisAlignment: .start, spacing: FluentSpacing.m) {
                        SizedBox(width: 320, child: CalendarView(selectedDate: d, onDateChanged: { set($0) }))
                        Text(d.map { "\($0.year)-\($0.month)-\($0.day)" } ?? "Nothing selected")
                    }
                }),
            ])
    }
}

final class CalendarDatePickerPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "CalendarDatePicker",
            "A field that opens a calendar in a flyout.",
            samples: [
                Sample("Pick a date", child: LocalState<FluentDateTime?>(nil) { d, set in
                    SizedBox(width: 300, child: CalendarDatePicker(selectedDate: d, onDateChanged: { set($0) }, header: "Date of birth"))
                }),
            ])
    }
}

final class DatePickerPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "DatePicker",
            "Month, day and year fields that open spinning lists.",
            samples: [
                Sample("A date picker", child: LocalState(FluentDateTime.now()) { d, set in
                    DatePicker(selected: d, onChanged: set, header: "Pick a date")
                }),
            ])
    }
}

final class TimePickerPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "TimePicker",
            "Hour and minute fields that open spinning lists, in 12- or 24-hour format.",
            samples: [
                Sample("12-hour", child: LocalState(FluentDateTime.now()) { d, set in
                    TimePicker(selected: d, onChanged: set, header: "Arrival time")
                }),
                Sample("24-hour, 15-minute steps", child: LocalState(FluentDateTime.now()) { d, set in
                    TimePicker(selected: d, onChanged: set, hourFormat: .h24, minuteIncrement: 15)
                }),
            ])
    }
}

// MARK: - Dialogs & flyouts

final class ContentDialogPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "ContentDialog",
            "A modal dialog: 8px corners, elevation 128, over Smoke. Up to three buttons, the primary one accent-filled.",
            samples: [
                Sample("Show a dialog", child: AutoTrigger(action: { ctx in _showSaveDialog(ctx) }, child: Button(onPressed: {
                    showContentDialog(context: context) { ctx in
                        ContentDialog(
                            title: Text("Save your work?"),
                            content: Text("Lorem ipsum dolor sit amet, adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."),
                            actions: [
                                FilledButton(onPressed: { Navigator.pop(ctx) }, child: Text("Save")),
                                Button(onPressed: { Navigator.pop(ctx) }, child: Text("Don't save")),
                                Button(onPressed: { Navigator.pop(ctx) }, child: Text("Cancel")),
                            ])
                    }
                }, child: Text("Show dialog")))),
            ])
    }
}

/// The same dialog, for the auto-open path.
private func _showSaveDialog(_ context: any BuildContext) {
    showContentDialog(context: context) { ctx in
        ContentDialog(
            title: Text("Save your work?"),
            content: Text("Lorem ipsum dolor sit amet, adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."),
            actions: [
                FilledButton(onPressed: { Navigator.pop(ctx) }, child: Text("Save")),
                Button(onPressed: { Navigator.pop(ctx) }, child: Text("Don't save")),
                Button(onPressed: { Navigator.pop(ctx) }, child: Text("Cancel")),
            ])
    }
}

final class FlyoutPage: StatefulWidget {
    override func createState() -> State<StatefulWidget> { _FlyoutPageState() }
}

final class _FlyoutPageState: State<StatefulWidget> {
    private let controller = FlyoutController()

    private func _open() {
        controller.showFlyout(builder: { [self] _ in
            FlyoutContent(child: Column(mainAxisSize: .min, crossAxisAlignment: .start, spacing: FluentSpacing.m) {
                Text("All items will be removed. Do you want to continue?")
                FilledButton(onPressed: { [self] in controller.closeFlyout() }, child: Text("Yes, empty my cart"))
            }, padding: EdgeInsets(all: 16))
        })
    }

    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "Flyout",
            "A light-dismiss popup anchored to the control that opened it: acrylic, 8px corners, elevation 32, a 1px flyout stroke.",
            samples: [
                Sample("A flyout with a button", child: AutoTrigger(action: { [self] _ in _open() }, child: FlyoutTarget(
                    controller: controller,
                    child: Button(onPressed: { [self] in _open() }, child: Text("Empty cart"))))),
            ])
    }
}

final class TeachingTipPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "TeachingTip",
            "A tip that points at a control to introduce it. Light-dismiss, with an optional action.",
            samples: [
                Sample("Show a tip", child: LocalState(false) { open, set in
                    AutoTrigger(action: { _ in set(true) }, child: TeachingTip(
                        target: Button(onPressed: { set(true) }, child: Text("Show teaching tip")),
                        title: Text("Save automatically"),
                        subtitle: Text("Your work is saved as you go; turn this off in Settings."),
                        isOpen: open,
                        onClose: { set(false) },
                        actions: [Button(onPressed: { set(false) }, child: Text("Got it"))]))
                }),
            ])
    }
}

final class TooltipPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "ToolTip",
            "A hint shown on hover. The one overlay Windows keeps at the control radius, 4px, at elevation 16.",
            samples: [
                Sample("Hover the button", child: Tooltip(message: "Saves the document", child: Button(onPressed: {}, child: Text("Save")))),
                Sample("On an icon", child: Tooltip(message: "Settings", child: IconButton(icon: Icon(FluentSystemIcons.settings), onPressed: {}))),
            ])
    }
}

// MARK: - Menus & toolbars

final class MenuBarPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "MenuBar",
            "A horizontal bar of top-level menus, each opening a menu flyout.",
            samples: [
                Sample("File, Edit, Help", child: MenuBar_(items: [
                    MenuBarItem(text: Text("File"), items: [
                        MenuFlyoutItem(text: Text("New"), leading: Icon(FluentSystemIcons.add), onPressed: {}),
                        MenuFlyoutItem(text: Text("Open…"), leading: Icon(FluentSystemIcons.folderOpen), onPressed: {}),
                        MenuFlyoutSeparator(),
                        MenuFlyoutItem(text: Text("Exit"), onPressed: {}),
                    ]),
                    MenuBarItem(text: Text("Edit"), items: [
                        MenuFlyoutItem(text: Text("Undo"), onPressed: {}),
                        MenuFlyoutItem(text: Text("Cut"), leading: Icon(FluentSystemIcons.cut), onPressed: {}),
                        MenuFlyoutItem(text: Text("Copy"), leading: Icon(FluentSystemIcons.copy), onPressed: {}),
                        MenuFlyoutItem(text: Text("Paste"), leading: Icon(FluentSystemIcons.paste), onPressed: {}),
                    ]),
                    MenuBarItem(text: Text("Help"), items: [
                        MenuFlyoutItem(text: Text("About"), leading: Icon(FluentSystemIcons.info), onPressed: {}),
                    ]),
                ])),
            ])
    }
}

final class MenuFlyoutPage: StatefulWidget {
    override func createState() -> State<StatefulWidget> { _MenuFlyoutPageState() }
}

final class _MenuFlyoutPageState: State<StatefulWidget> {
    private let controller = FlyoutController()

    private func _open() {
        controller.showFlyout(builder: { _ in
            MenuFlyout(items: [
                MenuFlyoutItem(text: Text("Share"), leading: Icon(FluentSystemIcons.share, size: 16), onPressed: {}),
                MenuFlyoutItem(text: Text("Copy"), leading: Icon(FluentSystemIcons.copy, size: 16), onPressed: {}),
                MenuFlyoutItem(text: Text("Delete"), leading: Icon(FluentSystemIcons.delete, size: 16), onPressed: {}),
                MenuFlyoutSeparator(),
                ToggleMenuFlyoutItem(text: Text("Show hidden files"), isChecked: true),
                MenuFlyoutSubItem(text: Text("Sort by"), items: [
                    RadioMenuFlyoutItem(text: Text("Name"), isSelected: true),
                    RadioMenuFlyoutItem(text: Text("Date modified")),
                ]),
            ])
        })
    }

    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "MenuFlyout",
            "A menu of commands: items with 16px icons, separators, checkable and radio items, and submenus. Acrylic, 8px corners.",
            samples: [
                Sample("From a button", child: AutoTrigger(action: { [self] _ in _open() }, child: FlyoutTarget(
                    controller: controller,
                    child: Button(onPressed: { [self] in _open() }, child: Text("Open menu"))))),
                Sample("From a drop-down button", child: LocalState(true) { checked, set in
                    DropDownButton(title: Text("Options"), items: [
                        MenuFlyoutItem(text: Text("Share"), leading: Icon(FluentSystemIcons.share), onPressed: {}),
                        MenuFlyoutItem(text: Text("Copy"), leading: Icon(FluentSystemIcons.copy), onPressed: {}),
                        MenuFlyoutItem(text: Text("Delete"), leading: Icon(FluentSystemIcons.delete), onPressed: {}),
                        MenuFlyoutSeparator(),
                        ToggleMenuFlyoutItem(text: Text("Show hidden files"), isChecked: checked, onChanged: set),
                        MenuFlyoutSubItem(text: Text("Sort by"), items: [
                            RadioMenuFlyoutItem(text: Text("Name"), isSelected: true),
                            RadioMenuFlyoutItem(text: Text("Date modified")),
                            RadioMenuFlyoutItem(text: Text("Size")),
                        ]),
                    ])
                }),
            ])
    }
}

final class CommandBarPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "CommandBar",
            "A toolbar of commands with labels, separators and an overflow menu for what does not fit.",
            samples: [
                Sample("Editing commands", child: CommandBar(primaryItems: [
                    CommandBarButton(icon: Icon(FluentSystemIcons.add), label: Text("New"), onPressed: {}),
                    CommandBarButton(icon: Icon(FluentSystemIcons.folderOpen), label: Text("Open"), onPressed: {}),
                    CommandBarSeparator(),
                    CommandBarButton(icon: Icon(FluentSystemIcons.cut), label: Text("Cut"), onPressed: {}),
                    CommandBarButton(icon: Icon(FluentSystemIcons.copy), label: Text("Copy"), onPressed: {}),
                    CommandBarButton(icon: Icon(FluentSystemIcons.paste), label: Text("Paste"), onPressed: {}),
                ], secondaryItems: [
                    CommandBarButton(icon: Icon(FluentSystemIcons.settings), label: Text("Settings"), onPressed: {}),
                    CommandBarButton(icon: Icon(FluentSystemIcons.info), label: Text("About"), onPressed: {}),
                ])),
            ])
    }
}

// MARK: - Navigation

final class BreadcrumbBarPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "BreadcrumbBar",
            "The path to where you are, each crumb a button except the last.",
            samples: [
                Sample("A folder path", child: BreadcrumbBar<String>(items: [
                    BreadcrumbItem(label: Text("Home"), value: "home"),
                    BreadcrumbItem(label: Text("Documents"), value: "documents"),
                    BreadcrumbItem(label: Text("Design"), value: "design"),
                    BreadcrumbItem(label: Text("Fluent"), value: "fluent"),
                ], onItemPressed: { _ in })),
            ])
    }
}

final class NavigationViewPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "NavigationView",
            "The top-level navigation of an app: a pane of items with icons, an indicator on the selected one, and a content area. This gallery is one; below is a small one of its own, in compact mode.",
            samples: [
                Sample("A nested NavigationView", child: SizedBox(height: 280, child: LocalState(0) { i, set in
                    DecoratedBox(
                        decoration: BoxDecoration(
                            border: Border.all(color: FluentTheme.of(context).resources.cardStrokeColorDefault, width: 1),
                            borderRadius: FluentCorners.overlayRadius),
                        child: NavigationView(pane: NavigationPane(
                            selected: i, onChanged: set,
                            items: [
                                PaneItem(icon: Icon(FluentSystemIcons.home), title: Text("Home"),
                                         body: Center(child: Text("Home"))),
                                PaneItem(icon: Icon(FluentSystemIcons.music), title: Text("Music"),
                                         body: Center(child: Text("Music"))),
                                PaneItem(icon: Icon(FluentSystemIcons.pictures), title: Text("Pictures"),
                                         body: Center(child: Text("Pictures"))),
                            ],
                            footerItems: [
                                PaneItem(icon: Icon(FluentSystemIcons.settings), title: Text("Settings"),
                                         body: Center(child: Text("Settings"))),
                            ],
                            displayMode: .compact)))
                })),
            ])
    }
}

final class TabViewPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "TabView",
            "Tabs with their own content, like a browser: the selected tab joins the content surface, the others sit back on the base layer.",
            samples: [
                Sample("Three documents", child: SizedBox(height: 240, child: LocalState(0) { i, set in
                    TabView(currentIndex: i, tabs: (1...3).map { n in
                        Tab(text: Text("Document \(n)"),
                            body: DecoratedBox(
                                decoration: BoxDecoration(color: FluentTheme.of(context).resources.layerFillColorDefault),
                                child: Center(child: Text("Document \(n)"))),
                            icon: Icon(FluentSystemIcons.document, size: 16))
                    }, onChanged: set, onNewPressed: {})
                })),
            ])
    }
}

final class TreeViewPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "TreeView",
            "A hierarchy that expands and collapses, with optional selection.",
            samples: [
                Sample("Folders", child: SizedBox(width: 360, child: TreeView(items: [
                    TreeViewItem(content: Text("Work documents"), children: [
                        TreeViewItem(content: Text("Functional specifications"), children: [
                            TreeViewItem(content: Text("TreeView spec")),
                        ]),
                        TreeViewItem(content: Text("Feature schedule")),
                        TreeViewItem(content: Text("Overall project plan")),
                    ]),
                    TreeViewItem(content: Text("Personal folder"), children: [
                        TreeViewItem(content: Text("Home remodel")),
                    ]),
                ], selectionMode: .single))),
            ])
    }
}

// MARK: - Layout

final class ExpanderPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "Expander",
            "A header that reveals content below it. The Settings app is a column of these.",
            samples: [
                Sample("Expanders", child: Column(crossAxisAlignment: .stretch, spacing: FluentSpacing.s) {
                    Expander(header: Text("This text is in the header"),
                             content: Text("This is in the content."),
                             leading: Icon(FluentSystemIcons.settings, size: 16))
                    Expander(header: Text("Initially expanded"),
                             content: Text("Content that was visible from the start."),
                             initiallyExpanded: true)
                    Expander(header: Text("With a control in the header"),
                             content: Text("Hidden until expanded."),
                             trailing: LocalState(true) { v, set in ToggleSwitch(checked: v, onChanged: set) })
                }),
            ])
    }
}

final class CardPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        let t = FluentTheme.of(context).typography
        return SamplePage(
            "Card",
            "A raised container for grouped content: the card fill and stroke, 4px corners.",
            samples: [
                Sample("A card", child: SizedBox(width: 360, child: Card(child: Column(crossAxisAlignment: .start, spacing: FluentSpacing.s) {
                    Text("Card title", style: t.bodyStrong)
                    Text("Some content inside a card, grouped with its title.", style: t.body)
                    Row(mainAxisAlignment: .end) { Button(onPressed: {}, child: Text("Action")) }
                }))),
            ])
    }
}

final class ListTilePage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "ListTile",
            "A row with a leading glyph, a title, a subtitle and a trailing control — the row a list is made of.",
            samples: [
                Sample("Rows", child: SizedBox(width: 420, child: Column(crossAxisAlignment: .stretch) {
                    ListTile(leading: Icon(FluentSystemIcons.wifiFull), title: Text("Wi-Fi"),
                             subtitle: Text("Connected"), trailing: Icon(FluentSystemIcons.chevronRight, size: 12), onPressed: {})
                    ListTile(leading: Icon(FluentSystemIcons.bluetooth), title: Text("Bluetooth"),
                             subtitle: Text("Off"), trailing: Icon(FluentSystemIcons.chevronRight, size: 12), onPressed: {})
                    ListTile(leading: Icon(FluentSystemIcons.battery), title: Text("Battery"),
                             subtitle: Text("87%"), onPressed: {})
                })),
            ])
    }
}

final class DividerPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "Divider",
            "A 1px line between things, horizontal or vertical.",
            samples: [
                Sample("Horizontal", child: Column(crossAxisAlignment: .stretch, spacing: FluentSpacing.s) {
                    Text("Above")
                    Divider()
                    Text("Below")
                }),
                Sample("Vertical", child: SizedBox(height: 40, child: Row(spacing: FluentSpacing.m) {
                    Text("Left")
                    Divider(direction: .vertical)
                    Text("Right")
                })),
            ])
    }
}

final class ScrollbarPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "Scrollbar",
            "Fluent's thin scrollbar over a scroll view: 4px at rest, wider on hover.",
            samples: [
                Sample("A scrolling list", child: SizedBox(width: 360, height: 200, child: FluentScrollbar(
                    child: SingleChildScrollView(child: Column(crossAxisAlignment: .start) {
                        for i in 1...30 { Padding(padding: EdgeInsets(all: 6)) { Text("Row \(i)") } }
                    }), isAlwaysShown: true))),
            ])
    }
}

// MARK: - Status & info

final class InfoBarPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "InfoBar",
            "An inline message with a severity, an optional action, and a close button. Informational, success, warning and error each have their own system fill.",
            samples: [
                Sample("Severities", child: Column(crossAxisAlignment: .stretch, spacing: FluentSpacing.s) {
                    InfoBar(title: Text("Title"), content: Text("Essential app message for your users to be informed of, acknowledge, or take action on."), severity: .info, onClose: {})
                    InfoBar(title: Text("Success"), content: Text("The operation completed."), severity: .success, onClose: {})
                    InfoBar(title: Text("Warning"), content: Text("Something needs your attention."), severity: .warning, onClose: {})
                    InfoBar(title: Text("Error"), content: Text("The operation failed."),
                            action: Button(onPressed: {}, child: Text("Retry")), severity: .error, onClose: {})
                }),
            ])
    }
}

final class InfoBadgePage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "InfoBadge",
            "A small count or status dot to draw attention to something, usually on a navigation item.",
            samples: [
                Sample("Badges", child: Row(spacing: FluentSpacing.xl) {
                    InfoBadge(source: Text("8"), severity: .info)
                    InfoBadge(source: Text("New"), severity: .success)
                    InfoBadge(source: Text("!"), severity: .warning)
                    InfoBadge(source: Text("3"), severity: .error)
                    InfoBadge(severity: .info)
                }),
            ])
    }
}

final class ProgressBarPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "ProgressBar",
            "Determinate progress as a filling accent bar, or indeterminate as a travelling one. Bars use the 4px corner.",
            samples: [
                Sample("Determinate", child: LocalState(35.0) { v, set in
                    Column(crossAxisAlignment: .start, spacing: FluentSpacing.m) {
                        SizedBox(width: 320, child: ProgressBar(value: v))
                        Row(spacing: FluentSpacing.m) {
                            SizedBox(width: 200, child: Slider(value: v, onChanged: set))
                            Text("\(Int(v))%")
                        }
                    }
                }),
                Sample("Indeterminate", child: SizedBox(width: 320, child: ProgressBar())),
            ])
    }
}

final class ProgressRingPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        SamplePage(
            "ProgressRing",
            "Progress as a ring, determinate or spinning.",
            samples: [
                Sample("Rings", child: Row(spacing: FluentSpacing.xl) {
                    SizedBox(width: 32, height: 32, child: ProgressRing())
                    SizedBox(width: 32, height: 32, child: ProgressRing(value: 25))
                    SizedBox(width: 32, height: 32, child: ProgressRing(value: 65))
                    SizedBox(width: 48, height: 48, child: ProgressRing(value: 90))
                }),
            ])
    }
}
#endif
