// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Building blocks the ribbon, title row and status bar share: a group with
// its caption, big and small command buttons, toggles, and the colour menu.
// Everything is a plain function returning a widget tree built with the
// explicit `children:` initializers — the trailing-closure builders crashed
// the 6.2.1 type checker on trees this deep.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

/// A glyph from an icon font, sized and coloured. The framework has no
/// generic icon widget (the example host's is Material-themed), so this is
/// the one the chrome uses.
final class Icon: StatelessWidget {
    let icon: IconData
    let size: Double
    let color: Color?

    init(_ icon: IconData, size: Double = 16, color: Color? = nil) {
        self.icon = icon
        self.size = size
        self.color = color
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let scalar = UnicodeScalar(UInt32(icon.codePoint)) ?? " "
        return Text(String(Character(scalar)), style: Flutter.TextStyle(
            color: color ?? FluentTheme.of(context).resources.textFillColorPrimary,
            fontSize: size, height: 1.0, fontFamily: icon.fontFamily))
    }
}

/// Word's flat ribbon command: nothing until the pointer is over it, a
/// subtle fill on hover, a tint while checked, and a menu below when it
/// has one. Every ribbon control is one of these so the rows line up.
final class FlatButton: StatefulWidget {
    let child: Widget
    let tip: String?
    let checked: Bool
    let enabled: Bool
    let width: Double?
    let height: Double
    let alignLeft: Bool
    let onAccent: Bool
    let action: (() -> Void)?
    let menu: [MenuFlyoutItemBase]?

    init(child: Widget, tip: String? = nil, checked: Bool = false, enabled: Bool = true,
         width: Double? = 28, height: Double = 28, alignLeft: Bool = false, onAccent: Bool = false,
         action: (() -> Void)? = nil, menu: [MenuFlyoutItemBase]? = nil) {
        self.child = child
        self.tip = tip
        self.checked = checked
        self.enabled = enabled
        self.width = width
        self.height = height
        self.alignLeft = alignLeft
        self.onAccent = onAccent
        self.action = action
        self.menu = menu
        super.init(key: nil)
    }

    override func createState() -> State<StatefulWidget> { _FlatButtonState() }
}

private final class _FlatButtonState: State<StatefulWidget> {
    private var _hover = false
    private let _flyout = FlyoutController()

    override func build(_ context: any BuildContext) -> Widget {
        let w = widget as! FlatButton
        let fluent = FluentTheme.of(context)
        let accent = fluent.accentColor.defaultBrushFor(fluent.brightness)
        var fill: Color? = nil
        var stroke: Color? = nil
        if w.enabled {
            let tint = w.onAccent ? OfficeAppearance.white : accent
            if w.checked { fill = tint.withOpacity(_hover ? 0.24 : 0.13); stroke = tint.withOpacity(0.35) }
            else if _hover { fill = tint.withOpacity(w.onAccent ? 0.18 : 0.08) }
        }
        let inner: Widget = w.alignLeft
            ? Padding(padding: EdgeInsets(left: 6, top: 0, right: 8, bottom: 0), child: Align(alignment: Alignment.centerLeft, child: w.child))
            : Center(child: w.child)
        var box: Widget = DecoratedBox(
            decoration: BoxDecoration(color: fill ?? Color(0x00000000),
                                      border: stroke.map { Border.all(color: $0, width: 1) },
                                      borderRadius: BorderRadius.all(Radius(circular: 5))),
            child: SizedBox(width: w.width, height: w.height, child: inner))
        let items = w.menu
        box = GestureDetector(
            onTap: w.enabled ? { [weak self] in
                if let items {
                    self?._flyout.showFlyout(builder: { _ in MenuFlyout(items: items) }, placement: .bottom)
                } else {
                    w.action?()
                }
            } : nil,
            behavior: .opaque,
            child: MouseRegion(
                onEnter: { [weak self] _ in self?.setState { self?._hover = true } },
                onExit: { [weak self] _ in self?.setState { self?._hover = false } },
                child: box))
        if items != nil { box = FlyoutTarget(controller: _flyout, child: box) }
        if let tip = w.tip { box = Tooltip(message: tip, child: box) }
        return box
    }
}

enum Chrome {
    static let ribbonHeight = 104.0
    static let iconSize = 16.0
    static let bigIconSize = 28.0
    static let rowHeight = 28.0

    // MARK: Groups

    /// A ribbon group: its commands over a caption, with a divider after.
    static func group(_ label: String, _ fluent: FluentThemeData, _ content: [Widget]) -> Widget {
        let body = Column(
            mainAxisAlignment: .spaceBetween,
            crossAxisAlignment: .center,
            children: [
                Row(crossAxisAlignment: .start, children: content),
                Text(label, style: fluent.typography.caption?.copyWith(
                    color: OfficeAppearance.secondary(fluent))),
            ]
        )
        return Row(crossAxisAlignment: .stretch, children: [
            Padding(padding: EdgeInsets(left: 10, top: 6, right: 10, bottom: 5), child: body),
            Padding(padding: EdgeInsets(left: 0, top: 10, right: 0, bottom: 10),
                    child: Divider(direction: .vertical)),
        ])
    }

    /// A column of small rows inside a group; the rows stretch to the
    /// widest so labelled buttons under each other share one edge.
    static func rows(_ rows: [Widget]) -> Widget {
        // The ribbon row is unbounded, so a stretching column needs its
        // own width first: the widest row's.
        IntrinsicWidth(child: Column(mainAxisAlignment: .start, crossAxisAlignment: .stretch, children: rows))
    }

    static func row(_ items: [Widget]) -> Widget {
        Row(crossAxisAlignment: .center, children: items)
    }

    static func gap(_ w: Double = 4) -> Widget { SizedBox(width: w, height: 0, child: nil) }
    static func vgap(_ h: Double = 4) -> Widget { SizedBox(width: 0, height: h, child: nil) }

    /// The small chevron of every menu and split button.
    static func chevron(_ fluent: FluentThemeData) -> Widget {
        Icon(FluentSystemIcons.chevronDown, size: 9, color: fluent.resources.textFillColorSecondary)
    }

    /// Word's Grow/Shrink Font glyph: an A with a small arrow, since the
    /// icon font has no such pair.
    static func sizeArrowIcon(up: Bool, _ fluent: FluentThemeData) -> Widget {
        let ink = fluent.resources.textFillColorPrimary
        return Row(mainAxisSize: .min, crossAxisAlignment: .center, children: [
            Text("A", style: Flutter.TextStyle(color: ink, fontSize: 15, fontWeight: .w500, height: 1.0)),
            SizedBox(width: 1, height: 0, child: nil),
            Text(up ? "\u{25B2}" : "\u{25BC}", style: Flutter.TextStyle(color: ink, fontSize: 7, height: 1.0)),
        ])
    }

    // MARK: Buttons

    /// Icon-only command, 28×28.
    static func icon(_ icon: IconData, _ tip: String, _ fluent: FluentThemeData,
                     enabled: Bool = true, action: @escaping () -> Void) -> Widget {
        let color = enabled ? fluent.resources.textFillColorPrimary : fluent.resources.textFillColorDisabled
        return FlatButton(child: Icon(icon, size: iconSize, color: color), tip: tip, enabled: enabled, action: action)
    }

    /// Icon toggle: tinted while on.
    static func toggle(_ icon: IconData, _ tip: String, _ on: Bool, _ fluent: FluentThemeData,
                       action: @escaping () -> Void) -> Widget {
        FlatButton(child: Icon(icon, size: iconSize, color: on
                              ? fluent.accentColor.defaultBrushFor(fluent.brightness)
                              : OfficeAppearance.ink(fluent)),
                   tip: tip, checked: on, action: action)
    }

    /// Text toggle (the view switches).
    static func textToggle(_ label: String, _ on: Bool, _ fluent: FluentThemeData,
                           style: Flutter.TextStyle? = nil, action: @escaping () -> Void) -> Widget {
        FlatButton(child: Padding(padding: EdgeInsets(left: 8, top: 0, right: 8, bottom: 0), child: Text(label, style: style)),
                   checked: on, width: nil, action: action)
    }

    /// Big button: icon over label, the Paste-shaped one, both rows tall.
    static func big(_ icon: IconData, _ label: String, _ fluent: FluentThemeData,
                    enabled: Bool = true, action: @escaping () -> Void) -> Widget {
        let color = enabled ? fluent.resources.textFillColorPrimary : fluent.resources.textFillColorDisabled
        return FlatButton(child: Padding(padding: EdgeInsets(left: 6, top: 2, right: 6, bottom: 2),
            child: Column(mainAxisAlignment: .center, crossAxisAlignment: .center, children: [
                Icon(icon, size: bigIconSize, color: color),
                vgap(4),
                Text(label, style: fluent.typography.caption?.copyWith(color: color)),
            ])), tip: nil, enabled: enabled, width: nil, height: rowHeight * 2 + 6, action: action)
    }

    /// Big toggle: the big button's shape, tinted while on (Spelling).
    static func bigToggle(_ icon: IconData, _ label: String, _ on: Bool, _ fluent: FluentThemeData,
                          action: @escaping () -> Void) -> Widget {
        let color = fluent.resources.textFillColorPrimary
        return FlatButton(child: Padding(padding: EdgeInsets(left: 6, top: 2, right: 6, bottom: 2),
            child: Column(mainAxisAlignment: .center, crossAxisAlignment: .center, children: [
                Icon(icon, size: bigIconSize, color: color),
                vgap(4),
                Text(label, style: fluent.typography.caption?.copyWith(color: color)),
            ])), checked: on, width: nil, height: rowHeight * 2 + 6, action: action)
    }

    /// Small button: icon beside label, stacked three to a column.
    static func small(_ icon: IconData, _ label: String, _ fluent: FluentThemeData,
                      enabled: Bool = true, action: @escaping () -> Void) -> Widget {
        let color = enabled ? fluent.resources.textFillColorPrimary : fluent.resources.textFillColorDisabled
        return FlatButton(child: Row(mainAxisSize: .min, crossAxisAlignment: .center, children: [
            Icon(icon, size: iconSize, color: color),
            gap(6),
            Text(label, style: fluent.typography.caption?.copyWith(color: color)),
        ]), enabled: enabled, width: nil, height: 21, alignLeft: true, action: action)
    }

    /// A menu button: optional icon, optional title, a chevron; the menu
    /// opens below.
    static func menuButton(_ icon: IconData?, _ title: String?, _ tip: String?, _ fluent: FluentThemeData,
                           items: [MenuFlyoutItemBase]) -> Widget {
        var parts: [Widget] = []
        if let icon { parts.append(Icon(icon, size: iconSize, color: fluent.resources.textFillColorPrimary)) }
        if let title {
            if icon != nil { parts.append(gap(6)) }
            parts.append(Text(title, style: fluent.typography.body))
        }
        parts.append(gap(4))
        parts.append(chevron(fluent))
        return FlatButton(child: Padding(padding: EdgeInsets(left: 6, top: 0, right: 5, bottom: 0),
                                         child: Row(mainAxisSize: .min, crossAxisAlignment: .center, children: parts)),
                          tip: tip, width: nil, menu: items)
    }

    /// The narrow half of a split button: a chevron that opens `items`,
    /// beside a command that acts on its own.
    static func splitChevron(_ tip: String, _ fluent: FluentThemeData, items: [MenuFlyoutItemBase]) -> Widget {
        FlatButton(child: chevron(fluent), tip: tip, width: 14, menu: items)
    }

    /// A drop-down of named colours with a swatch each.
    static func colorMenu(_ icon: IconData, _ tip: String, _ fluent: FluentThemeData,
                          colors: [(String, Color)], none: String?, more: (() -> Void)? = nil,
                          onPick: @escaping (Color?) -> Void) -> Widget {
        var items: [MenuFlyoutItemBase] = []
        if let none {
            items.append(MenuFlyoutItem(text: Text(none), onPressed: { onPick(nil) }))
            items.append(MenuFlyoutSeparator())
        }
        for (name, color) in colors {
            items.append(MenuFlyoutItem(
                text: Text(name),
                leading: swatch(color, fluent),
                onPressed: { onPick(color) }))
        }
        if let more {
            items.append(MenuFlyoutSeparator())
            items.append(MenuFlyoutItem(text: Text("More Colors…"), onPressed: more))
        }
        return menuButton(icon, nil, tip, fluent, items: items)
    }

    static func swatch(_ color: Color, _ fluent: FluentThemeData) -> Widget {
        SizedBox(width: 14, height: 14, child: DecoratedBox(decoration: BoxDecoration(
            color: color,
            border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1),
            borderRadius: BorderRadius.all(Radius(circular: 2)))))
    }

    /// A labelled value with −/+ buttons: NumberBox without typing, which
    /// keeps keyboard focus in the document.
    static func spinner(_ label: String, _ value: Double, _ fluent: FluentThemeData, step: Double,
                        unit: String = "pt", minimum: Double = 0, onChanged: @escaping (Double) -> Void) -> Widget {
        row([
            SizedBox(width: 84, height: nil, child: Text(label, style: fluent.typography.caption)),
            icon(FluentSystemIcons.chevronDown, "Less", fluent) { onChanged(max(minimum, value - step)) },
            SizedBox(width: 48, height: nil, child: Text("\(Int(value.rounded())) \(unit)", style: fluent.typography.caption)),
            icon(FluentSystemIcons.chevronUp, "More", fluent) { onChanged(value + step) },
        ])
    }

    /// A drop-down of plain choices.
    static func menu(_ title: Widget?, _ leading: Widget?, _ fluent: FluentThemeData,
                     _ choices: [(String, () -> Void)]) -> Widget {
        let items = choices.map { name, action in MenuFlyoutItem(text: Text(name), onPressed: action) as MenuFlyoutItemBase }
        var parts: [Widget] = []
        if let leading { parts.append(leading) }
        if let title { if leading != nil { parts.append(gap(6)) }; parts.append(title) }
        parts.append(gap(4))
        parts.append(chevron(fluent))
        return FlatButton(child: Padding(padding: EdgeInsets(left: 6, top: 0, right: 5, bottom: 0),
                                         child: Row(mainAxisSize: .min, crossAxisAlignment: .center, children: parts)),
                          width: nil, menu: items)
    }
}

extension Flutter.TextStyle {
    /// The one field the chrome ever overrides.
    func copyWith(color: Color?) -> Flutter.TextStyle {
        Flutter.TextStyle(inherit: inherit, color: color ?? self.color, backgroundColor: backgroundColor,
                  fontSize: fontSize, fontWeight: fontWeight, fontStyle: fontStyle,
                  letterSpacing: letterSpacing, wordSpacing: wordSpacing, textBaseline: textBaseline,
                  height: height, decoration: decoration, decorationColor: decorationColor,
                  fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback)
    }
}
