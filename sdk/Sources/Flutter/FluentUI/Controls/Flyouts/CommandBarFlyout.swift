// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Ported from WinUI's CommandBarFlyout.
//
// Microsoft's recommended control for a context menu, and the reason
// Windows 11's right-click menus look the way they do: the commands people
// reach for most (cut, copy, paste, rename, share, delete) sit as a single
// horizontal row of icons, and everything else follows underneath as an
// ordinary menu.
//
//     ┌─────────────────────────────┐
//     │  ✂  ⧉  📋  ✎  ↗  🗑    …   │  primary commands, always shown
//     ├─────────────────────────────┤
//     │  Open                       │  secondary commands, shown when
//     │  Open with…                 │  expanded — a plain menu
//     └─────────────────────────────┘
//
// Two display modes, as WinUI has them: COLLAPSED shows the primary row
// alone, with a "see more" ellipsis when there are secondary commands to
// reach; EXPANDED shows both. A flyout with only secondary commands has
// neither row nor ellipsis and is exactly a `MenuFlyout` — which is the
// documented way to write a context menu that looks like a plain menu.
//
// Which mode it opens in follows the invocation: a context menu (a
// right-click — "reactive") opens EXPANDED, and commands offered
// unprompted beside a selection ("proactive") open COLLAPSED. That is the
// `initiallyExpanded` argument.
//
// The items are the same `CommandBarItem`s a `CommandBar` takes, because
// WinUI uses the same app-bar buttons in both, and they already know how
// to draw themselves in a row (icon, optional label, subtle fill) and in a
// menu (a flyout list tile with its icon and label). An item invoked here
// also dismisses the flyout, as it does in WinUI.

import FlutterSwiftBridge

// MARK: - Metrics

/// A primary command's height. Fluent's minimum pointer target, and what
/// the row of icons in Windows' own context menu measures.
public let kCommandBarFlyoutPrimaryHeight: Double = 40

/// The primary row's inset inside the flyout surface.
public let kCommandBarFlyoutPrimaryPadding = EdgeInsets(all: 4)

// MARK: - CommandBarFlyout

public class CommandBarFlyout: StatefulWidget {
    /// The commands shown in the horizontal row, in both display modes.
    /// The common ones (cut, copy, paste, delete, share) belong here.
    ///
    /// Unlike `CommandBar`, these never overflow into the menu: a row too
    /// long for the surface is clipped, so keep it short.
    public let primaryCommands: [CommandBarItem]

    /// The commands shown as a menu under the row, in the expanded mode
    /// only. Everything that would traditionally be in a context menu.
    public let secondaryCommands: [CommandBarItem]

    /// Whether the secondary commands are shown from the start. A context
    /// menu passes true (WinUI's `Standard` show mode); commands offered
    /// beside a selection pass false (`Transient`).
    public let initiallyExpanded: Bool

    /// Keeps the secondary commands shown and hides the "see more" button,
    /// so the user cannot collapse the flyout. No effect without secondary
    /// commands — those flyouts are always collapsed.
    public let alwaysExpanded: Bool

    /// Called when a command has been invoked, for a flyout the caller
    /// placed itself rather than opening through a `FlyoutController`
    /// (the shell's popups, an app's own overlay). A flyout shown through
    /// a controller closes itself and does not need this.
    public let onDismiss: (() -> Void)?

    /// The surface's colour, shadow and size, as `MenuFlyout` takes them.
    public let color: Color?
    public let shadowColor: Color
    public let elevation: Double
    public let constraints: BoxConstraints

    public init(
        key: (any Key)? = nil,
        primaryCommands: [CommandBarItem] = [],
        secondaryCommands: [CommandBarItem] = [],
        initiallyExpanded: Bool = true,
        alwaysExpanded: Bool = false,
        onDismiss: (() -> Void)? = nil,
        color: Color? = nil,
        shadowColor: Color = Color(0xFF000000),
        elevation: Double = FluentElevation.flyout,
        constraints: BoxConstraints = kFlyoutThemeConstraints
    ) {
        self.primaryCommands = primaryCommands
        self.secondaryCommands = secondaryCommands
        self.initiallyExpanded = initiallyExpanded
        self.alwaysExpanded = alwaysExpanded
        self.onDismiss = onDismiss
        self.color = color
        self.shadowColor = shadowColor
        self.elevation = elevation
        self.constraints = constraints
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _CommandBarFlyoutState()
    }
}

// MARK: - _CommandBarFlyoutState

class _CommandBarFlyoutState: State<StatefulWidget> {
    private var flyout: CommandBarFlyout { widget as! CommandBarFlyout }

    /// Whether the secondary commands are showing.
    private var _expanded = false
    /// The context of the last build, for closing the enclosing flyout.
    private weak var _context: Element?

    private var hasSecondary: Bool { !flyout.secondaryCommands.isEmpty }
    /// A flyout with no secondary commands is always collapsed, whatever
    /// it was asked for — there is nothing to expand into.
    private var isExpanded: Bool {
        hasSecondary && (flyout.alwaysExpanded || _expanded)
    }

    override func initState() {
        super.initState()
        _expanded = flyout.initiallyExpanded
    }

    /// A command was invoked: the flyout goes away, as WinUI's does.
    func commandInvoked() {
        flyout.onDismiss?()
        if let ctx = _context {
            (ctx.getElementForInheritedWidgetOfExactType(FlyoutScope.self)?
                .widget as? FlyoutScope)?.closeAll()
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        _context = context as? Element
        var sections: [Widget] = []

        if !flyout.primaryCommands.isEmpty {
            sections.append(_primaryRow(context))
        }
        if isExpanded {
            if !flyout.primaryCommands.isEmpty {
                sections.append(MenuFlyoutSeparator().buildItem(context))
            }
            sections.append(_secondaryMenu(context))
        }

        return FlyoutContent(
            // Content-sized, as a flyout is: the widest section sets the
            // width and the icon row divides it. Without this the surface
            // takes whatever width its parent offers, which in a Stack is
            // the whole window.
            child: IntrinsicWidth(
                child: Column(mainAxisSize: .min, crossAxisAlignment: .stretch,
                              children: sections)),
            color: flyout.color,
            // The menu's own vertical padding when there is a menu to pad;
            // the row supplies its own inset.
            padding: flyout.primaryCommands.isEmpty
                ? kDefaultMenuFlyoutPadding : EdgeInsets(),
            shadowColor: flyout.shadowColor,
            elevation: flyout.elevation,
            constraints: flyout.constraints
        )
    }

    /// The row of icons, and the "see more" ellipsis that reaches the rest.
    private func _primaryRow(_ context: any BuildContext) -> Widget {
        // The commands share the surface's width equally — Windows' own
        // context menu divides its inner width by the number of cells —
        // with each command centred in its share, so the hover fill hugs
        // the icon rather than smearing across the cell.
        var cells: [Widget] = []
        for item in flyout.primaryCommands {
            item._flyout = self
            cells.append(Expanded(child: SizedBox(
                height: kCommandBarFlyoutPrimaryHeight,
                child: Center(child: item.build(context: context, displayMode: .inPrimary)))))
        }
        if hasSecondary && !flyout.alwaysExpanded {
            cells.append(_seeMore(context))
        }
        return Padding(
            padding: kCommandBarFlyoutPrimaryPadding,
            child: Row(crossAxisAlignment: .center, children: cells))
    }

    /// WinUI's "see more" button: an ellipsis that expands the flyout, and
    /// a chevron up that folds it again.
    private func _seeMore(_ context: any BuildContext) -> Widget {
        let res = FluentTheme.of(context).resources
        return SizedBox(
            width: kCommandBarFlyoutPrimaryHeight,
            height: kCommandBarFlyoutPrimaryHeight,
            child: HoverButton(
                builder: { [self] _, states in
                    let fill: Color = states.isPressed
                        ? res.subtleFillColorTertiary
                        : (states.isHovered ? res.subtleFillColorSecondary : Color(0x00000000))
                    return DecoratedBox(
                        decoration: BoxDecoration(
                            color: fill,
                            borderRadius: BorderRadius.circular(FluentCorners.control)),
                        child: Center(child: FluentGlyph(
                            isExpanded ? .chevronUp : .more,
                            size: 12,
                            color: res.textFillColorPrimary)))
                },
                onPressed: { [self] in setState { _expanded = !_expanded } },
                semanticLabel: isExpanded ? "See fewer commands" : "See more commands"))
    }

    /// The secondary commands, laid out as `MenuFlyout` lays out its items.
    private func _secondaryMenu(_ context: any BuildContext) -> Widget {
        var rows: [Widget] = []
        for item in flyout.secondaryCommands {
            item._flyout = self
            rows.append(Padding(
                padding: kDefaultMenuFlyoutItemMargin,
                child: item.build(context: context, displayMode: .inSecondary)))
        }
        return Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows)
    }
}

// MARK: - CommandBarToggleButton

/// WinUI's `AppBarToggleButton`: a command that is on or off rather than
/// one that happens once. In the primary row it wears the accent while it
/// is on; in the menu it carries a check mark, exactly as
/// `ToggleMenuFlyoutItem` does — the same command in both places.
public class CommandBarToggleButton: CommandBarItem {
    public let icon: Widget?
    public let label: Widget?
    public let isChecked: Bool
    public let onChanged: ((Bool) -> Void)?
    public let tooltip: String?

    public init(
        key: (any Key)? = nil,
        icon: Widget? = nil,
        label: Widget? = nil,
        isChecked: Bool = false,
        onChanged: ((Bool) -> Void)? = nil,
        tooltip: String? = nil
    ) {
        self.icon = icon
        self.label = label
        self.isChecked = isChecked
        self.onChanged = onChanged
        self.tooltip = tooltip
        super.init(key: key)
    }

    private var _invoke: (() -> Void)? {
        guard let onChanged else { return nil }
        return { [self] in
            onChanged(!isChecked)
            _flyout?.commandInvoked()
        }
    }

    public override func build(context: any BuildContext,
                               displayMode: CommandBarItemDisplayMode) -> Widget {
        switch displayMode {
        case .inPrimary: return _primary(context)
        case .inSecondary: return _secondary(context)
        }
    }

    private func _primary(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let res = theme.resources
        let accent = theme.accentColor.defaultBrushFor(theme.brightness)
        var button: Widget = HoverButton(
            builder: { [self] _, states in
                let disabled = onChanged == nil
                let ink: Color = {
                    if disabled { return res.textFillColorDisabled }
                    // On an accent fill the ink is the token that exists for
                    // it — Fluent's dark accent takes black glyphs.
                    if isChecked { return res.textOnAccentFillColorPrimary }
                    return res.textFillColorPrimary
                }()
                let fill: Color = {
                    if disabled { return Color(0x00000000) }
                    if isChecked {
                        return states.isPressed || states.isHovered
                            ? accent.withValues(alpha: 0.9) : accent
                    }
                    if states.isPressed { return res.subtleFillColorTertiary }
                    if states.isHovered { return res.subtleFillColorSecondary }
                    return Color(0x00000000)
                }()
                var cells: [Widget] = []
                if let icon {
                    cells.append(IconTheme(
                        data: IconThemeData(size: 16, color: ink),
                        child: DefaultTextStyle(
                            style: TextStyle(color: ink, fontSize: 14), child: icon)))
                }
                if let label {
                    if icon != nil { cells.append(SizedBox(width: 8)) }
                    cells.append(DefaultTextStyle(
                        style: TextStyle(color: ink, fontSize: 12), child: label))
                }
                return DecoratedBox(
                    decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(FluentCorners.control)),
                    child: Padding(
                        padding: EdgeInsets(left: 10, top: 6, right: 10, bottom: 6),
                        child: Row(mainAxisSize: .min, crossAxisAlignment: .center,
                                   children: cells)))
            },
            onPressed: _invoke)
        if let tooltip {
            button = Tooltip(message: tooltip, child: button)
        }
        return button
    }

    private func _secondary(_ context: any BuildContext) -> Widget {
        let res = FluentTheme.of(context).resources
        let mark: Widget = isChecked
            ? FluentGlyph(.check, size: 14, color: res.textFillColorPrimary)
            : (icon ?? SizedBox(width: 0, height: 0))
        return FlyoutListTile(
            onPressed: _invoke,
            icon: SizedBox(width: 16, height: 16, child: Center(child: mark)),
            text: label ?? SizedBox(width: 0, height: 0),
            margin: EdgeInsets())
    }
}
