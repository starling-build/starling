// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The app: a NavigationView whose pane is the catalog — Home, Design
// guidance, one expander per control category, Settings in the footer —
// and whose content is whichever page is selected. This is the WinUI 3
// Gallery's shape, on the SDK's own NavigationView, over Mica.
//
// The catalog is DATA (`GalleryCatalog`): a category is a title, an icon
// and a list of entries, and an entry is a title, a one-line description
// and a page builder. Adding a control's page is one entry.

#if os(Linux)
import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

// MARK: - Catalog

struct GalleryEntry {
    let title: String
    let subtitle: String
    let icon: IconData
    let page: () -> Widget
}

struct GalleryCategory {
    let title: String
    let subtitle: String
    let icon: IconData
    let entries: [GalleryEntry]
}

enum GalleryCatalog {
    static let design = GalleryCategory(
        title: "Design guidance", subtitle: "The system the controls are built from",
        icon: FluentSystemIcons.personalize,
        entries: [
            GalleryEntry(title: "Typography", subtitle: "Segoe UI Variable's ramp, in Selawik",
                         icon: FluentSystemIcons.rename) { TypographyPage() },
            GalleryEntry(title: "Color", subtitle: "WinUI's resource dictionary and the accent",
                         icon: FluentSystemIcons.personalize) { ColorPage() },
            GalleryEntry(title: "Geometry", subtitle: "Corner radii and stroke widths",
                         icon: FluentSystemIcons.window) { GeometryPage() },
            GalleryEntry(title: "Spacing", subtitle: "The spacing ramp and the layout rules",
                         icon: FluentSystemIcons.grid) { SpacingPage() },
            GalleryEntry(title: "Materials", subtitle: "Acrylic, Mica and Smoke",
                         icon: FluentSystemIcons.pictures) { MaterialsPage() },
            GalleryEntry(title: "Elevation", subtitle: "Layering and the shadow ramp",
                         icon: FluentSystemIcons.copy) { ElevationPage() },
            GalleryEntry(title: "Motion", subtitle: "Durations and curves",
                         icon: FluentSystemIcons.refresh) { MotionPage() },
            GalleryEntry(title: "Iconography", subtitle: "Fluent System Icons",
                         icon: FluentSystemIcons.favorite) { IconographyPage() },
        ])

    static let categories: [GalleryCategory] = [
        GalleryCategory(
            title: "Basic input", subtitle: "Buttons, toggles, sliders and pickers",
            icon: FluentSystemIcons.check,
            entries: [
                GalleryEntry(title: "Button", subtitle: "A control that responds to user input and raises a Click event.",
                             icon: FluentSystemIcons.check) { ButtonPage() },
                GalleryEntry(title: "DropDownButton", subtitle: "A button that shows a flyout of choices when clicked.",
                             icon: FluentSystemIcons.chevronDown) { DropDownButtonPage() },
                GalleryEntry(title: "HyperlinkButton", subtitle: "A button that appears as hyperlink text.",
                             icon: FluentSystemIcons.link) { HyperlinkButtonPage() },
                GalleryEntry(title: "ToggleButton", subtitle: "A button that can be switched between two states.",
                             icon: FluentSystemIcons.pin) { ToggleButtonPage() },
                GalleryEntry(title: "SplitButton", subtitle: "A two-part button: an action and a flyout.",
                             icon: FluentSystemIcons.more) { SplitButtonPage() },
                GalleryEntry(title: "CheckBox", subtitle: "A control a user can select or clear, or leave indeterminate.",
                             icon: FluentSystemIcons.check) { CheckboxPage() },
                GalleryEntry(title: "ColorPicker", subtitle: "A spectrum and sliders for picking a colour.",
                             icon: FluentSystemIcons.personalize) { ColorPickerPage() },
                GalleryEntry(title: "ComboBox", subtitle: "A drop-down list of items to select from.",
                             icon: FluentSystemIcons.chevronDown) { ComboBoxPage() },
                GalleryEntry(title: "RadioButton", subtitle: "Select one option from a set.",
                             icon: FluentSystemIcons.check) { RadioButtonPage() },
                GalleryEntry(title: "RatingControl", subtitle: "Enter and display ratings.",
                             icon: FluentSystemIcons.favorite) { RatingPage() },
                GalleryEntry(title: "Slider", subtitle: "Select from a range of values by moving a thumb.",
                             icon: FluentSystemIcons.brightness) { SliderPage() },
                GalleryEntry(title: "ToggleSwitch", subtitle: "A switch that can be toggled on and off.",
                             icon: FluentSystemIcons.power) { ToggleSwitchPage() },
            ]),
        GalleryCategory(
            title: "Text", subtitle: "Boxes for typing, and labels",
            icon: FluentSystemIcons.rename,
            entries: [
                GalleryEntry(title: "TextBox", subtitle: "A single- or multi-line plain text field.",
                             icon: FluentSystemIcons.rename) { TextBoxPage() },
                GalleryEntry(title: "PasswordBox", subtitle: "A text field that hides what is typed.",
                             icon: FluentSystemIcons.lock) { PasswordBoxPage() },
                GalleryEntry(title: "NumberBox", subtitle: "A text field for numbers, with spin buttons.",
                             icon: FluentSystemIcons.add) { NumberBoxPage() },
                GalleryEntry(title: "AutoSuggestBox", subtitle: "A text field that suggests as you type.",
                             icon: FluentSystemIcons.search) { AutoSuggestBoxPage() },
                GalleryEntry(title: "InfoLabel", subtitle: "A label above a control.",
                             icon: FluentSystemIcons.info) { InfoLabelPage() },
            ]),
        GalleryCategory(
            title: "Date & time", subtitle: "Calendars and pickers",
            icon: FluentSystemIcons.calendar,
            entries: [
                GalleryEntry(title: "CalendarView", subtitle: "A month view for picking one date.",
                             icon: FluentSystemIcons.calendar) { CalendarViewPage() },
                GalleryEntry(title: "CalendarDatePicker", subtitle: "A field that opens a calendar.",
                             icon: FluentSystemIcons.calendar) { CalendarDatePickerPage() },
                GalleryEntry(title: "DatePicker", subtitle: "Spinning month, day and year fields.",
                             icon: FluentSystemIcons.calendar) { DatePickerPage() },
                GalleryEntry(title: "TimePicker", subtitle: "Spinning hour and minute fields.",
                             icon: FluentSystemIcons.clock) { TimePickerPage() },
            ]),
        GalleryCategory(
            title: "Dialogs & flyouts", subtitle: "Transient surfaces on acrylic",
            icon: FluentSystemIcons.window,
            entries: [
                GalleryEntry(title: "ContentDialog", subtitle: "A modal dialog over Smoke.",
                             icon: FluentSystemIcons.window) { ContentDialogPage() },
                GalleryEntry(title: "Flyout", subtitle: "A light-dismiss popup anchored to a control.",
                             icon: FluentSystemIcons.info) { FlyoutPage() },
                GalleryEntry(title: "TeachingTip", subtitle: "A tip that points at a control.",
                             icon: FluentSystemIcons.info) { TeachingTipPage() },
                GalleryEntry(title: "ToolTip", subtitle: "A hint on hover.",
                             icon: FluentSystemIcons.info) { TooltipPage() },
            ]),
        GalleryCategory(
            title: "Menus & toolbars", subtitle: "Menus, bars and command surfaces",
            icon: FluentSystemIcons.more,
            entries: [
                GalleryEntry(title: "MenuBar", subtitle: "A horizontal bar of top-level menus.",
                             icon: FluentSystemIcons.more) { MenuBarPage() },
                GalleryEntry(title: "MenuFlyout", subtitle: "A context menu of commands.",
                             icon: FluentSystemIcons.more) { MenuFlyoutPage() },
                GalleryEntry(title: "CommandBar", subtitle: "A toolbar of commands with an overflow.",
                             icon: FluentSystemIcons.edit) { CommandBarPage() },
                GalleryEntry(title: "CommandBarFlyout", subtitle: "The recommended context menu: an icon row and a menu.",
                             icon: FluentSystemIcons.more) { CommandBarFlyoutPage() },
            ]),
        GalleryCategory(
            title: "Navigation", subtitle: "Ways around an app",
            icon: FluentSystemIcons.forward,
            entries: [
                GalleryEntry(title: "BreadcrumbBar", subtitle: "The path to where you are.",
                             icon: FluentSystemIcons.chevronRight) { BreadcrumbBarPage() },
                GalleryEntry(title: "NavigationView", subtitle: "The pane this app is built on.",
                             icon: FluentSystemIcons.allApps) { NavigationViewPage() },
                GalleryEntry(title: "TabView", subtitle: "Tabs with content, like a browser.",
                             icon: FluentSystemIcons.window) { TabViewPage() },
                GalleryEntry(title: "TreeView", subtitle: "A hierarchy that expands and collapses.",
                             icon: FluentSystemIcons.folderOpen) { TreeViewPage() },
            ]),
        GalleryCategory(
            title: "Layout", subtitle: "Containers and dividers",
            icon: FluentSystemIcons.grid,
            entries: [
                GalleryEntry(title: "Expander", subtitle: "A header that reveals content.",
                             icon: FluentSystemIcons.chevronDown) { ExpanderPage() },
                GalleryEntry(title: "Card", subtitle: "A raised container for grouped content.",
                             icon: FluentSystemIcons.window) { CardPage() },
                GalleryEntry(title: "ListTile", subtitle: "A row with leading, title, subtitle and trailing.",
                             icon: FluentSystemIcons.allApps) { ListTilePage() },
                GalleryEntry(title: "Divider", subtitle: "A hairline between things.",
                             icon: FluentSystemIcons.more) { DividerPage() },
                GalleryEntry(title: "Scrollbar", subtitle: "Fluent's thin scrollbar over a scroll view.",
                             icon: FluentSystemIcons.chevronDown) { ScrollbarPage() },
            ]),
        GalleryCategory(
            title: "Status & info", subtitle: "Progress, badges and messages",
            icon: FluentSystemIcons.info,
            entries: [
                GalleryEntry(title: "InfoBar", subtitle: "An inline message with a severity.",
                             icon: FluentSystemIcons.info) { InfoBarPage() },
                GalleryEntry(title: "InfoBadge", subtitle: "A small count or status dot.",
                             icon: FluentSystemIcons.bell) { InfoBadgePage() },
                GalleryEntry(title: "ProgressBar", subtitle: "Determinate and indeterminate progress.",
                             icon: FluentSystemIcons.more) { ProgressBarPage() },
                GalleryEntry(title: "ProgressRing", subtitle: "Progress as a ring.",
                             icon: FluentSystemIcons.refresh) { ProgressRingPage() },
            ]),
    ]
}

// MARK: - GalleryApp

/// The root: theme and material settings, then the shell.
final class GalleryApp: StatefulWidget {
    override func createState() -> State<StatefulWidget> { _GalleryAppState() }
}

final class _GalleryAppState: State<StatefulWidget> {
    var dark = false
    var transparency = true
    var wallpaper: Color? = Color(0xFF3B6FB6)
    var selected = 0

    /// Page ids in the order NavigationView flattens the pane, so a tile can
    /// select its page by id. Rebuilt with the pane.
    private var _flat: [String] = []
    private var _appliedRequest = false

    /// A page to open on launch (`FLUENT_GALLERY_PAGE=design/Color`,
    /// `Basic input/Slider`, `settings`) and `FLUENT_GALLERY_DARK=1`, for
    /// screenshots from a script — every page reachable without a click.
    private var _requestedPage: String? {
        ProcessInfo.processInfo.environment["FLUENT_GALLERY_PAGE"]
    }

    override func initState() {
        super.initState()
        // The engine is running by the time a widget builds; the fonts are
        // resources of the FluentSystemIcons target beside the executable.
        _ = FluentSystemIcons.registerFont()
        _ = SelawikFont.registerFont()
        if ProcessInfo.processInfo.environment["FLUENT_GALLERY_DARK"] == "1" { dark = true }
    }

    private func select(_ id: String) {
        if let i = _flat.firstIndex(of: id) { setState { selected = i } }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let font = SelawikFont.family
        let light = FluentThemeData(brightness: .light, fontFamily: font)
        let darkTheme = FluentThemeData(brightness: .dark, fontFamily: font)
        return FluentApp(
            theme: light,
            darkTheme: darkTheme,
            themeMode: dark ? .dark : .light,
            home: FluentMaterialSettings(
                transparencyEffects: transparency,
                child: MicaBackdrop(sample: wallpaper, child: _shell())),
            title: "Fluent Gallery")
    }

    // MARK: The pane

    private func _shell() -> Widget {
        var items: [NavigationPaneItem] = []
        var flat: [String] = []

        func page(_ id: String, _ icon: IconData, _ title: String, _ body: Widget) -> PaneItem {
            flat.append(id)
            return PaneItem(icon: Icon(icon), title: Text(title), body: body)
        }
        func expander(_ category: GalleryCategory, id: String, expanded: Bool) -> PaneItemExpander {
            // The expander's own body comes first in the flattened order,
            // then its children — the same walk `effectiveItems` does.
            flat.append(id)
            let children = category.entries.map { e in
                page("\(id)/\(e.title)", e.icon, e.title, e.page())
            }
            return PaneItemExpander(
                icon: Icon(category.icon), title: Text(category.title),
                body: CategoryPage(category: category) { [weak self] title in
                    self?.select("\(id)/\(title)")
                },
                items: children, initiallyExpanded: expanded)
        }

        items.append(page("home", FluentSystemIcons.home, "Home", HomePage { [weak self] id in
            self?.select(id)
        }))
        items.append(expander(GalleryCatalog.design, id: "design", expanded: true))
        items.append(PaneItemSeparator())
        for c in GalleryCatalog.categories {
            items.append(expander(c, id: c.title, expanded: false))
        }

        let settings = page("settings", FluentSystemIcons.settings, "Settings", SettingsPage(
            dark: dark, transparency: transparency, wallpaper: wallpaper,
            onDark: { [weak self] v in self?.setState { self?.dark = v } },
            onTransparency: { [weak self] v in self?.setState { self?.transparency = v } },
            onWallpaper: { [weak self] v in self?.setState { self?.wallpaper = v } }))
        _flat = flat
        if let want = _requestedPage, let i = flat.firstIndex(of: want), selected != i,
           !_appliedRequest {
            _appliedRequest = true
            selected = i
        }

        let pane = NavigationPane(
            selected: selected,
            onChanged: { [weak self] i in self?.setState { self?.selected = i } },
            items: items,
            footerItems: [settings],
            header: _paneHeader(),
            displayMode: .open)
        return Mica(child: NavigationView(pane: pane))
    }

    /// The title, and the search box every page is reachable from — the
    /// WinUI Gallery's "Search controls and samples".
    private func _paneHeader() -> Widget {
        var entries: [(String, String)] = []   // (title, page id)
        for e in GalleryCatalog.design.entries { entries.append((e.title, "design/\(e.title)")) }
        for c in GalleryCatalog.categories {
            entries.append((c.title, c.title))
            for e in c.entries { entries.append((e.title, "\(c.title)/\(e.title)")) }
        }
        let ids = Dictionary(entries.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        return Builder { [weak self] context in
            let t = FluentTheme.of(context).typography
            return Padding(padding: EdgeInsets(left: 12, top: 12, right: 12, bottom: 8)) {
                Column(crossAxisAlignment: .start, spacing: FluentSpacing.m) {
                    Row(spacing: FluentSpacing.m) {
                        Icon(FluentSystemIcons.grid, size: 20)
                        Text("Fluent Gallery", style: t.bodyStrong)
                    }
                    AutoSuggestBox(
                        items: entries.map { title, id in
                            AutoSuggestBoxItem(value: title, onTap: { self?.select(id) })
                        },
                        onSelected: { item in
                            if let id = ids[item.value] { self?.select(id) }
                        },
                        placeholderText: "Search controls and samples",
                        leadingIcon: Icon(FluentSystemIcons.search, size: 16),
                        clearOnSelect: true)
                }
            }
        }
    }
}

// MARK: - HomePage

final class HomePage: StatelessWidget {
    let select: (String) -> Void
    init(select: @escaping (String) -> Void) {
        self.select = select
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let t = theme.typography
        let a = theme.accentColor
        return SingleChildScrollView(
            padding: EdgeInsets(all: 36),
            child: Column(crossAxisAlignment: .start, spacing: FluentSpacing.xxl) {
                // The hero: an accent gradient with the app's name on it.
                ClipRRect(borderRadius: FluentCorners.overlayRadius) {
                    DecoratedBox(
                        decoration: BoxDecoration(gradient: LinearGradient(
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                            colors: [a.dark2, a.normal, a.light2])),
                        child: Padding(padding: EdgeInsets(all: 32)) {
                            Column(crossAxisAlignment: .start, spacing: FluentSpacing.s) {
                                Text("Fluent Gallery",
                                     style: t.titleLarge?.copyWith(color: Color(0xFFFFFFFF)))
                                Text("The Fluent design system in Swift: Windows 11's tokens, materials and controls, on the Starling SDK. Light and dark, over Mica.",
                                     style: t.body?.copyWith(color: Color(0xFFFFFFFF)))
                            }
                        })
                }
                Text("Design guidance", style: t.subtitle)
                Wrap(spacing: FluentSpacing.m, runSpacing: FluentSpacing.m) {
                    for e in GalleryCatalog.design.entries {
                        GalleryTile(icon: e.icon, title: e.title, subtitle: e.subtitle) { [self] in
                            select("design/\(e.title)")
                        }
                    }
                }
                Text("Controls", style: t.subtitle)
                Wrap(spacing: FluentSpacing.m, runSpacing: FluentSpacing.m) {
                    for c in GalleryCatalog.categories {
                        GalleryTile(icon: c.icon, title: c.title,
                                    subtitle: "\(c.entries.count) samples — \(c.subtitle)") { [self] in
                            select(c.title)
                        }
                    }
                }
            })
    }
}

// MARK: - CategoryPage

final class CategoryPage: StatelessWidget {
    let category: GalleryCategory
    let select: (String) -> Void

    init(category: GalleryCategory, select: @escaping (String) -> Void) {
        self.category = category
        self.select = select
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let t = FluentTheme.of(context).typography
        return SingleChildScrollView(
            padding: EdgeInsets(left: 36, top: 28, right: 36, bottom: 36),
            child: Column(crossAxisAlignment: .start, spacing: FluentSpacing.xl) {
                Column(crossAxisAlignment: .start, spacing: FluentSpacing.s) {
                    Text(category.title, style: t.title)
                    Text(category.subtitle, style: t.body)
                }
                Wrap(spacing: FluentSpacing.m, runSpacing: FluentSpacing.m) {
                    for e in category.entries {
                        GalleryTile(icon: e.icon, title: e.title, subtitle: e.subtitle) { [self] in
                            select(e.title)
                        }
                    }
                }
            })
    }
}

// MARK: - SettingsPage

final class SettingsPage: StatelessWidget {
    let dark: Bool
    let transparency: Bool
    let wallpaper: Color?
    let onDark: (Bool) -> Void
    let onTransparency: (Bool) -> Void
    let onWallpaper: (Color?) -> Void

    init(dark: Bool, transparency: Bool, wallpaper: Color?,
         onDark: @escaping (Bool) -> Void, onTransparency: @escaping (Bool) -> Void,
         onWallpaper: @escaping (Color?) -> Void) {
        self.dark = dark
        self.transparency = transparency
        self.wallpaper = wallpaper
        self.onDark = onDark
        self.onTransparency = onTransparency
        self.onWallpaper = onWallpaper
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let t = FluentTheme.of(context).typography
        let wallpapers: [(String, Color?)] = [
            ("None (fallback)", nil), ("Blue", Color(0xFF3B6FB6)), ("Sunset", Color(0xFFC46A2B)),
            ("Forest", Color(0xFF2E7D4F)), ("Plum", Color(0xFF6B3FA0)),
        ]
        return SingleChildScrollView(
            padding: EdgeInsets(left: 36, top: 28, right: 36, bottom: 36),
            child: Column(crossAxisAlignment: .start, spacing: FluentSpacing.l) {
                Text("Settings", style: t.title)
                Text("Appearance", style: t.bodyStrong)
                Card(child: Column(crossAxisAlignment: .start, spacing: FluentSpacing.m) {
                    ToggleSwitch(checked: dark, onChanged: onDark, content: Text("Dark mode"))
                    ToggleSwitch(checked: transparency, onChanged: onTransparency,
                                 content: Text("Transparency effects (Acrylic and Mica)"))
                })
                Text("Wallpaper sample for Mica", style: t.bodyStrong)
                Card(child: Column(crossAxisAlignment: .start, spacing: FluentSpacing.s) {
                    for (name, color) in wallpapers {
                        RadioButton<String>(
                            value: name, groupValue: wallpapers.first { $0.1 == wallpaper }?.0,
                            onChanged: { [self] v in
                                onWallpaper(wallpapers.first { $0.0 == v }?.1 ?? nil)
                            },
                            content: Row(spacing: FluentSpacing.s) {
                                if let color {
                                    DecoratedBox(
                                        decoration: BoxDecoration(color: color, borderRadius: FluentCorners.controlRadius),
                                        child: SizedBox(width: 16, height: 16))
                                }
                                Text(name)
                            })
                    }
                })
                Text("About", style: t.bodyStrong)
                Card(child: Text("Starling SDK — Fluent design system. Tokens from WinUI's theme resources and @fluentui/tokens; layout after the WinUI 3 Gallery.",
                                 style: t.body))
            })
    }
}
#endif
