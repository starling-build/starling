// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Start, in its 2026 shape: one scrollable page above the taskbar.
//
// Search on top; Pinned as rows of tiles with an "All" that unfolds the
// rest; Recent — recently added apps and recently touched files — below
// it; then All apps inline, laid out by category, as a grid, or as a list,
// whichever the user picked last; and the user and power at the foot. It
// is a panel, not a screen: the desktop stays visible behind it and a
// click outside puts it away.
//
// Typing is routed here by the shell's key handler exactly as it is for
// Launchpad — `query` is filtered upstream, so an empty query is the page
// and a non-empty one is the results in the same cells.
//
// Widths come from Windows: 832 where the screen has room for it, 640 on a
// laptop-class display, and the user may pin either. Cells are the 92x88
// our Windows shell measured off the real thing.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

// MARK: - Geometry

enum StartPanel {
    static let largeWidth: Double = 832
    static let smallWidth: Double = 640
    static let maxHeight: Double = 864
    static let minHeight: Double = 480
    static let pad: Double = FluentSpacing.xl          // 20
    static let radius: Double = FluentCorners.overlay
    /// Gap between the panel and the taskbar.
    static let gap: Double = 12
    static let largeColumns = 8
    static let smallColumns = 6
    static let cellHeight: Double = 88
    static let iconSize: Double = 32
    static let searchHeight: Double = 34
    static let footerHeight: Double = 48
    /// Pinned rows shown folded.
    static let pinnedRows = 2
    static let recentColumns = 2
    static let recentRowHeight: Double = 56

    /// `auto` is Windows' choice: the large panel needs a screen it is not
    /// most of.
    static func width(for size: StartSize, screenWidth: Double) -> Double {
        let large: Bool
        switch size {
        case .large: large = true
        case .small: large = false
        case .auto: large = screenWidth >= 1600
        }
        return min(large ? largeWidth : smallWidth, screenWidth - 32)
    }

    static func columns(forWidth width: Double) -> Int {
        width >= largeWidth ? largeColumns : smallColumns
    }
}

// MARK: - Model

/// Everything Start shows, gathered by the shell.
struct StartModel {
    /// Every installed app, in registry order.
    let apps: [LauncherApp]
    /// The query's matches (the same as `apps` when the query is empty).
    let results: [LauncherApp]
    /// The pinned apps, in pin order.
    let pinned: [LauncherApp]
    /// Recently added apps, newest first.
    let recentApps: [LauncherApp]
    let recentFiles: [RecentFile]
    let launchCounts: [String: Int]
    let prefs: StartPrefs
    let query: String
    let caretResetToken: Int
    let userName: String
    let screenWidth: Double
    let screenHeight: Double
}

// MARK: - FluentStartMenu

final class FluentStartMenu: StatefulWidget {
    let model: StartModel
    let onLaunch: (String) -> Void
    let onOpenFile: (RecentFile) -> Void
    /// Right-click on a tile, at the pointer: the pin/unpin menu.
    let onTileMenu: (String, Offset) -> Void
    let onPrefs: (StartPrefs) -> Void
    /// The power control, with its global rect: the power flyout hangs
    /// from it.
    let onPower: (Rect) -> Void
    let onDismiss: () -> Void

    init(model: StartModel,
         onLaunch: @escaping (String) -> Void,
         onOpenFile: @escaping (RecentFile) -> Void,
         onTileMenu: @escaping (String, Offset) -> Void,
         onPrefs: @escaping (StartPrefs) -> Void,
         onPower: @escaping (Rect) -> Void,
         onDismiss: @escaping () -> Void) {
        self.model = model
        self.onLaunch = onLaunch
        self.onOpenFile = onOpenFile
        self.onTileMenu = onTileMenu
        self.onPrefs = onPrefs
        self.onPower = onPower
        self.onDismiss = onDismiss
        super.init()
    }

    override func createState() -> State<StatefulWidget> { _FluentStartMenuState() }
}

private final class _FluentStartMenuState: State<StatefulWidget> {
    /// Whether Pinned shows every row or the folded two.
    private var _pinnedUnfolded = false
    /// The power control's context, for the flyout to hang from.
    private var _powerContext: (any BuildContext)?

    private var w: FluentStartMenu { widget as! FluentStartMenu }
    private var m: StartModel { w.model }

    override func build(_ context: any BuildContext) -> Widget {
        let barH = DesktopTheme.kDockHeight
        let width = StartPanel.width(for: m.prefs.size, screenWidth: m.screenWidth)
        let available = m.screenHeight - barH - StartPanel.gap * 2
        let height = max(StartPanel.minHeight, min(StartPanel.maxHeight, available))

        return Stack(
            fit: .expand,
            children: [
                // Tap-to-dismiss over the whole desktop. No blur and no
                // scrim: Start is a panel, and dimming the desktop behind it
                // would make it read as a mode.
                Listener(
                    onPointerDown: { [self] _ in w.onDismiss() },
                    behavior: .opaque,
                    child: SizedBox(expand: ())
                ),
                Positioned(
                    left: (m.screenWidth - width) / 2,
                    bottom: barH + StartPanel.gap,
                    width: width,
                    height: height,
                    child: FluentEntrance(
                        child: _panel(width: width), slideFrom: Offset(0, 24))
                ),
            ]
        )
    }

    // MARK: The panel

    private func _panel(width: Double) -> Widget {
        let columns = StartPanel.columns(forWidth: width)
        // Claims its own pointers so a click inside does not fall through to
        // the dismiss layer behind it.
        return Listener(
            onPointerDown: { _ in },
            behavior: .opaque,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: shellTheme.panelFill,
                    border: Border.all(color: shellTheme.panelStroke,
                                       width: FluentStrokeWidth.thin),
                    borderRadius: FluentCorners.overlayRadius,
                    boxShadow: FluentElevation.shadows(
                        FluentElevation.flyout,
                        brightness: shellTheme.isDark ? .dark : .light)
                ),
                child: ClipRRect(
                    borderRadius: FluentCorners.overlayRadius,
                    child: Column(crossAxisAlignment: .stretch) {
                        Padding(
                            padding: EdgeInsets(left: StartPanel.pad, top: StartPanel.pad,
                                                right: StartPanel.pad, bottom: 0),
                            child: _searchBox())
                        Expanded { _page(columns: columns) }
                        _footer()
                    }
                )
            )
        )
    }

    /// The query, live. Not a text field: the shell's key router owns the
    /// keyboard while Start is open and feeds `query` from above, so the
    /// caret is the only thing that says the typing is going somewhere.
    private func _searchBox() -> Widget {
        let empty = m.query.isEmpty
        return SizedBox(
            height: StartPanel.searchHeight,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: shellTheme.controlFill,
                    border: Border.all(color: shellTheme.controlStroke,
                                       width: FluentStrokeWidth.thin),
                    borderRadius: FluentCorners.controlRadius
                ),
                child: Padding(
                    padding: EdgeInsets(left: 10, top: 0, right: 10, bottom: 0),
                    child: Row(crossAxisAlignment: .center) {
                        Icon(FluentSystemIcons.search, size: 14, color: shellTheme.fgSecondary)
                        SizedBox(width: FluentSpacing.s)
                        Text(empty ? "Search for apps, settings, and files" : m.query,
                             style: fluentType.styled(
                                { $0.body },
                                empty ? shellTheme.fgTertiary : shellTheme.fgPrimary),
                             overflow: .ellipsis,
                             maxLines: 1)
                        // Blinks itself — see `ShellCaret`.
                        ShellCaret(color: shellTheme.fgPrimary, fontSize: 13,
                                   fontFamily: shellTheme.fontFamily,
                                   resetToken: m.caretResetToken)
                    }
                )
            )
        )
    }

    // MARK: The page

    private func _page(columns: Int) -> Widget {
        if !m.query.isEmpty { return _results(columns: columns) }
        var sections: [Widget] = []
        sections.append(_pinnedSection(columns: columns))
        if m.prefs.showRecent {
            sections.append(SizedBox(height: FluentSpacing.xl))
            sections.append(_recentSection())
        }
        sections.append(SizedBox(height: FluentSpacing.xl))
        sections.append(_allAppsSection(columns: columns))
        return SingleChildScrollView(
            padding: EdgeInsets(left: StartPanel.pad, top: FluentSpacing.l,
                                right: StartPanel.pad, bottom: FluentSpacing.l),
            child: Column(crossAxisAlignment: .stretch, children: sections)
        )
    }

    private func _results(columns: Int) -> Widget {
        if m.results.isEmpty {
            return Center(child: Text(
                "No results for \u{201C}\(m.query)\u{201D}",
                style: fluentType.styled({ $0.body }, shellTheme.fgSecondary)))
        }
        return SingleChildScrollView(
            padding: EdgeInsets(left: StartPanel.pad, top: FluentSpacing.l,
                                right: StartPanel.pad, bottom: FluentSpacing.l),
            child: Column(crossAxisAlignment: .stretch) {
                _header("Results", trailing: _headerCount(m.results.count))
                SizedBox(height: FluentSpacing.s)
                _grid(m.results, columns: columns)
            }
        )
    }

    // MARK: Sections

    private func _pinnedSection(columns: Int) -> Widget {
        let all = m.pinned
        let foldedCount = columns * StartPanel.pinnedRows
        let shown = _pinnedUnfolded ? all : Array(all.prefix(foldedCount))
        let canUnfold = all.count > foldedCount
        var trailing: Widget? = nil
        if canUnfold {
            trailing = _headerButton(
                _pinnedUnfolded ? "Fewer" : "All",
                icon: _pinnedUnfolded ? .chevronUp : .chevronDown) { [self] in
                setState { _pinnedUnfolded.toggle() }
            }
        }
        return Column(crossAxisAlignment: .stretch) {
            _header("Pinned", trailing: trailing)
            SizedBox(height: FluentSpacing.s)
            if all.isEmpty {
                Padding(padding: EdgeInsets(all: FluentSpacing.m)) {
                    Text("Nothing pinned. Right-click an app below to pin it.",
                         style: fluentType.styled({ $0.caption }, shellTheme.fgSecondary))
                }
            } else {
                _grid(shown, columns: columns)
            }
        }
    }

    private func _recentSection() -> Widget {
        var rows: [Widget] = []
        for app in m.recentApps {
            rows.append(_recentRow(
                icon: _glyph(app, size: 28), title: app.title, subtitle: "Recently added",
                onTap: { [self] in w.onLaunch(app.appId) }))
        }
        for file in m.recentFiles {
            rows.append(_recentRow(
                icon: Icon(FluentSystemIcons.document, size: 24, color: shellTheme.fgSecondary),
                title: file.name, subtitle: file.ageLabel(),
                onTap: { [self] in w.onOpenFile(file) }))
        }
        let hide = _headerButton("Hide", icon: nil) { [self] in
            var p = m.prefs
            p.showRecent = false
            w.onPrefs(p)
        }
        return Column(crossAxisAlignment: .stretch) {
            _header("Recent", trailing: hide)
            SizedBox(height: FluentSpacing.s)
            if rows.isEmpty {
                Padding(padding: EdgeInsets(all: FluentSpacing.m)) {
                    Text("Apps you add and files you open will show up here.",
                         style: fluentType.styled({ $0.caption }, shellTheme.fgSecondary))
                }
            } else {
                _twoColumns(rows)
            }
        }
    }

    private func _allAppsSection(columns: Int) -> Widget {
        var body: Widget
        switch m.prefs.view {
        case .category: body = _categoryView(columns: columns)
        case .grid: body = _grid(_alphabetical(m.apps), columns: columns)
        case .list: body = _listView()
        }
        var trailing: Widget = _viewPicker()
        if !m.prefs.showRecent {
            trailing = Row(mainAxisSize: .min, spacing: FluentSpacing.s) {
                _headerButton("Show recent", icon: nil) { [self] in
                    var p = m.prefs
                    p.showRecent = true
                    w.onPrefs(p)
                }
                _viewPicker()
            }
        }
        return Column(crossAxisAlignment: .stretch) {
            _header("All apps", trailing: trailing)
            SizedBox(height: FluentSpacing.s)
            body
        }
    }

    // MARK: All apps views

    private func _alphabetical(_ apps: [LauncherApp]) -> [LauncherApp] {
        apps.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Groups from the registry's `Category=`, most-used first inside each,
    /// the groups alphabetical with the uncategorised last.
    private func _categoryView(columns: Int) -> Widget {
        var groups: [String: [LauncherApp]] = [:]
        for app in m.apps {
            let key = app.category.isEmpty ? "Other" : app.category
            groups[key, default: []].append(app)
        }
        let names = groups.keys.sorted {
            if $0 == "Other" { return false }
            if $1 == "Other" { return true }
            return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        var out: [Widget] = []
        for name in names {
            let apps = groups[name]!.sorted { a, b in
                let ca = m.launchCounts[a.appId] ?? 0, cb = m.launchCounts[b.appId] ?? 0
                if ca != cb { return ca > cb }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
            out.append(Padding(
                padding: EdgeInsets(left: FluentSpacing.xs, top: FluentSpacing.m,
                                    right: 0, bottom: FluentSpacing.xs),
                child: Text(name, style: fluentType.styled(
                    { $0.bodyStrong }, shellTheme.fgPrimary, strong: true))))
            out.append(_grid(apps, columns: columns))
        }
        return Column(crossAxisAlignment: .stretch, children: out)
    }

    /// Alphabetical rows under letter headers, as Windows' list view.
    private func _listView() -> Widget {
        var out: [Widget] = []
        var letter = ""
        for app in _alphabetical(m.apps) {
            let first = String(app.title.prefix(1)).uppercased()
            let head = first.rangeOfCharacter(from: .letters) == nil ? "#" : first
            if head != letter {
                letter = head
                out.append(Padding(
                    padding: EdgeInsets(left: FluentSpacing.m, top: FluentSpacing.m,
                                        right: 0, bottom: FluentSpacing.xs),
                    child: Text(letter, style: fluentType.styled(
                        { $0.bodyStrong }, shellTheme.accent, strong: true))))
            }
            out.append(_listRow(app))
        }
        return Column(crossAxisAlignment: .stretch, children: out)
    }

    private func _listRow(_ app: LauncherApp) -> Widget {
        _tileMenuTarget(app) {
            HoverButton(
                builder: { [self] _, states in
                    let hot = states.isHovered || states.isPressed
                    return DecoratedBox(
                        decoration: BoxDecoration(
                            color: hot ? shellTheme.barHover : Color(0x00000000),
                            borderRadius: FluentCorners.controlRadius),
                        child: SizedBox(
                            height: 40,
                            child: Padding(
                                padding: EdgeInsets(left: FluentSpacing.m, top: 0,
                                                    right: FluentSpacing.m, bottom: 0),
                                child: Row(crossAxisAlignment: .center, spacing: FluentSpacing.m) {
                                    SizedBox(width: 24, height: 24, child: _glyph(app, size: 24))
                                    Expanded {
                                        Text(app.title,
                                             style: fluentType.styled({ $0.body }, shellTheme.fgPrimary),
                                             overflow: .ellipsis, maxLines: 1)
                                    }
                                })))
                },
                onPressed: { [self] in w.onLaunch(app.appId) })
        }
    }

    /// The three-way view switch: category, grid, list.
    private func _viewPicker() -> Widget {
        func button(_ view: StartView, _ icon: IconData) -> Widget {
            let selected = m.prefs.view == view
            return SizedBox(
                width: 32, height: 28,
                child: HoverButton(
                    builder: { [self] _, states in
                        let hot = states.isHovered || states.isPressed
                        return DecoratedBox(
                            decoration: BoxDecoration(
                                color: selected ? shellTheme.accent
                                    : (hot ? shellTheme.controlHover : Color(0x00000000)),
                                borderRadius: FluentCorners.controlRadius),
                            child: Center(child: Icon(
                                icon, size: 14,
                                color: selected ? shellTheme.accentInk : shellTheme.fgPrimary)))
                    },
                    onPressed: { [self] in
                        var p = m.prefs
                        p.view = view
                        w.onPrefs(p)
                    }))
        }
        return Row(mainAxisSize: .min, spacing: FluentSpacing.xxs) {
            button(.category, FluentSystemIcons.apps)
            button(.grid, FluentSystemIcons.grid)
            button(.list, FluentSystemIcons.allApps)
        }
    }

    // MARK: Pieces

    private func _header(_ title: String, trailing: Widget?) -> Widget {
        Row(mainAxisAlignment: .spaceBetween, crossAxisAlignment: .center) {
            Padding(padding: EdgeInsets(left: FluentSpacing.xs, top: 0, right: 0, bottom: 0)) {
                Text(title, style: fluentType.styled(
                    { $0.bodyStrong }, shellTheme.fgPrimary, strong: true))
            }
            if let trailing { trailing }
        }
    }

    private func _headerCount(_ n: Int) -> Widget {
        Text("\(n) apps", style: fluentType.styled({ $0.caption }, shellTheme.fgSecondary))
    }

    /// Windows' "All >" style control: a label with a chevron, on the
    /// control fill.
    private func _headerButton(_ label: String, icon: FluentGlyphKind?,
                               onTap: @escaping () -> Void) -> Widget {
        HoverButton(
            builder: { [self] _, states in
                let hot = states.isHovered || states.isPressed
                return DecoratedBox(
                    decoration: BoxDecoration(
                        color: hot ? shellTheme.controlHover : shellTheme.controlFill,
                        border: Border.all(color: shellTheme.controlStroke,
                                           width: FluentStrokeWidth.thin),
                        borderRadius: FluentCorners.controlRadius),
                    child: Padding(
                        padding: EdgeInsets(left: FluentSpacing.m, top: 4,
                                            right: FluentSpacing.s, bottom: 4),
                        child: Row(mainAxisSize: .min, crossAxisAlignment: .center,
                                   spacing: FluentSpacing.xs) {
                            Text(label, style: fluentType.styled({ $0.caption }, shellTheme.fgPrimary))
                            if let icon { FluentGlyph(icon, size: 10, color: shellTheme.fgSecondary) }
                        }))
            },
            onPressed: onTap)
    }

    /// Rows of `columns`, padded out to a full row so the last row's tiles
    /// stay left-aligned under the ones above instead of centring.
    private func _grid(_ apps: [LauncherApp], columns: Int) -> Widget {
        var rows: [Widget] = []
        var i = 0
        while i < apps.count {
            let slice = apps[i..<min(i + columns, apps.count)]
            rows.append(Row(crossAxisAlignment: .start) {
                for app in slice { Expanded(child: _tile(app)) }
                for _ in slice.count..<columns {
                    Expanded(child: SizedBox(height: StartPanel.cellHeight))
                }
            })
            i += columns
        }
        return Column(crossAxisAlignment: .stretch, children: rows)
    }

    private func _twoColumns(_ rows: [Widget]) -> Widget {
        var lines: [Widget] = []
        var i = 0
        while i < rows.count {
            let slice = rows[i..<min(i + StartPanel.recentColumns, rows.count)]
            lines.append(Row(crossAxisAlignment: .start) {
                for r in slice { Expanded(child: r) }
                for _ in slice.count..<StartPanel.recentColumns {
                    Expanded(child: SizedBox(height: StartPanel.recentRowHeight))
                }
            })
            i += StartPanel.recentColumns
        }
        return Column(crossAxisAlignment: .stretch, children: lines)
    }

    private func _recentRow(icon: Widget, title: String, subtitle: String,
                            onTap: @escaping () -> Void) -> Widget {
        HoverButton(
            builder: { [self] _, states in
                let hot = states.isHovered || states.isPressed
                return DecoratedBox(
                    decoration: BoxDecoration(
                        color: hot ? shellTheme.barHover : Color(0x00000000),
                        borderRadius: FluentCorners.controlRadius),
                    child: SizedBox(
                        height: StartPanel.recentRowHeight,
                        child: Padding(
                            padding: EdgeInsets(left: FluentSpacing.m, top: 0,
                                                right: FluentSpacing.m, bottom: 0),
                            child: Row(crossAxisAlignment: .center, spacing: FluentSpacing.m) {
                                SizedBox(width: 32, height: 32, child: Center(child: icon))
                                Expanded {
                                    Column(mainAxisAlignment: .center,
                                           crossAxisAlignment: .start, spacing: 2) {
                                        Text(title, style: fluentType.styled({ $0.body }, shellTheme.fgPrimary),
                                             overflow: .ellipsis, maxLines: 1)
                                        Text(subtitle, style: fluentType.styled({ $0.caption }, shellTheme.fgSecondary),
                                             overflow: .ellipsis, maxLines: 1)
                                    }
                                }
                            })))
            },
            onPressed: onTap)
    }

    /// The glyph alone, in the app's own colour — no tile behind it (see
    /// `fluentIconVisual`).
    private func _glyph(_ app: LauncherApp, size: Double) -> Widget {
        if let texId = app.textureId {
            return TextureWidget(textureId: Int(texId), filterQuality: .medium)
        }
        return SizedBox(width: size, height: size,
                        child: CustomPaint(painter: IconPainter(app.iconType, color: app.bgColor)))
    }

    /// A right-click on any app control opens its menu at the pointer.
    private func _tileMenuTarget(_ app: LauncherApp, _ child: () -> Widget) -> Widget {
        Listener(
            onPointerDown: { [self] event in
                if event.buttons & kSecondaryButton != 0 {
                    w.onTileMenu(app.appId, event.position)
                }
            },
            behavior: .translucent,
            child: child())
    }

    private func _tile(_ app: LauncherApp) -> Widget {
        _tileMenuTarget(app) {
            HoverButton(
                builder: { [self] _, states in
                    let hot = states.isHovered || states.isPressed
                    return DecoratedBox(
                        decoration: BoxDecoration(
                            color: hot ? shellTheme.barHover : Color(0x00000000),
                            borderRadius: FluentCorners.controlRadius
                        ),
                        child: SizedBox(
                            height: StartPanel.cellHeight,
                            child: Column(mainAxisAlignment: .center, crossAxisAlignment: .center) {
                                SizedBox(width: StartPanel.iconSize, height: StartPanel.iconSize,
                                         child: _glyph(app, size: StartPanel.iconSize))
                                SizedBox(height: FluentSpacing.s)
                                Padding(padding: EdgeInsets(left: 4, top: 0, right: 4, bottom: 0)) {
                                    Text(app.title,
                                         style: fluentType.styled({ $0.caption }, shellTheme.fgPrimary),
                                         textAlign: .center, overflow: .ellipsis, maxLines: 2)
                                }
                            }
                        )
                    )
                },
                onPressed: { [self] in w.onLaunch(app.appId) }
            )
        }
    }

    /// The user on the left, power on the right — where Windows puts them,
    /// and the reason the taskbar does not carry a power tile.
    private func _footer() -> Widget {
        SizedBox(
            height: StartPanel.footerHeight,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    // A wash over the panel, not a fill: Windows' footer is
                    // a shade darker than the body it sits under.
                    color: shellTheme.isDark ? Color(0x0AFFFFFF) : Color(0x06000000),
                    border: Border(top: BorderSide(color: shellTheme.panelStroke,
                                                   width: FluentStrokeWidth.thin))
                ),
                child: Padding(
                    padding: EdgeInsets(left: 12, top: 6, right: 12, bottom: 6),
                    child: Row(mainAxisAlignment: .spaceBetween, crossAxisAlignment: .center) {
                        if m.prefs.showAccount {
                            Row(mainAxisSize: .min, crossAxisAlignment: .center) {
                                Icon(FluentSystemIcons.person, size: 18, color: shellTheme.fgPrimary)
                                SizedBox(width: FluentSpacing.s)
                                Text(m.userName, style: fluentType.styled({ $0.body }, shellTheme.fgPrimary))
                            }
                        } else {
                            SizedBox(width: 1)
                        }
                        SizedBox(
                            width: 36, height: 36,
                            child: HoverButton(
                                builder: { [self] context, states in
                                    _powerContext = context
                                    let hot = states.isHovered || states.isPressed
                                    return DecoratedBox(
                                        decoration: BoxDecoration(
                                            color: hot ? shellTheme.controlHover : Color(0x00000000),
                                            borderRadius: FluentCorners.controlRadius
                                        ),
                                        child: Center(child: Icon(
                                            FluentSystemIcons.power, size: 16, color: shellTheme.fgPrimary))
                                    )
                                },
                                onPressed: { [self] in w.onPower(_powerRect()) }
                            )
                        )
                    }
                )
            )
        )
    }

    private func _powerRect() -> Rect {
        guard let ctx = _powerContext,
              let box = ctx.findRenderObject() as? RenderBox else { return .zero }
        let o = box.localToGlobal(Offset.zero)
        return Rect.fromLTWH(o.dx, o.dy, box.size.width, box.size.height)
    }
}
