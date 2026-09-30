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

enum Chrome {
    static let ribbonHeight = 110.0
    static let iconSize = 16.0
    static let bigIconSize = 28.0

    // MARK: Groups

    /// A ribbon group: its commands over a caption, with a divider after.
    static func group(_ label: String, _ fluent: FluentThemeData, _ content: [Widget]) -> Widget {
        let body = Column(
            mainAxisAlignment: .spaceBetween,
            crossAxisAlignment: .center,
            children: [
                Row(crossAxisAlignment: .start, children: content),
                Text(label, style: fluent.typography.caption?.copyWith(
                    color: fluent.resources.textFillColorSecondary)),
            ]
        )
        return Row(crossAxisAlignment: .stretch, children: [
            Padding(padding: EdgeInsets(left: 8, top: 4, right: 8, bottom: 4), child: body),
            Padding(padding: EdgeInsets(left: 0, top: 6, right: 0, bottom: 6),
                    child: Divider(direction: .vertical)),
        ])
    }

    /// A column of small rows inside a group.
    static func rows(_ rows: [Widget]) -> Widget {
        Column(mainAxisAlignment: .start, crossAxisAlignment: .start, children: rows)
    }

    static func row(_ items: [Widget]) -> Widget {
        Row(crossAxisAlignment: .center, children: items)
    }

    static func gap(_ w: Double = 4) -> Widget { SizedBox(width: w, height: 0, child: nil) }
    static func vgap(_ h: Double = 4) -> Widget { SizedBox(width: 0, height: h, child: nil) }

    // MARK: Buttons

    /// Icon-only command, 28×28.
    static func icon(_ icon: IconData, _ tip: String, _ fluent: FluentThemeData,
                     enabled: Bool = true, action: @escaping () -> Void) -> Widget {
        let color = enabled ? fluent.resources.textFillColorPrimary : fluent.resources.textFillColorDisabled
        return Tooltip(message: tip, child: IconButton(
            icon: Icon(icon, size: iconSize, color: color),
            onPressed: enabled ? action : nil))
    }

    /// Icon toggle, checked state drawn by ToggleButton.
    static func toggle(_ icon: IconData, _ tip: String, _ on: Bool, _ fluent: FluentThemeData,
                       action: @escaping () -> Void) -> Widget {
        let color = on ? fluent.resources.textOnAccentFillColorPrimary : fluent.resources.textFillColorPrimary
        return Tooltip(message: tip, child: ToggleButton(
            checked: on, onChanged: { _ in action() },
            child: Icon(icon, size: iconSize, color: color)))
    }

    /// Text toggle (the style gallery, view switches).
    static func textToggle(_ label: String, _ on: Bool, _ fluent: FluentThemeData,
                           style: Flutter.TextStyle? = nil, action: @escaping () -> Void) -> Widget {
        ToggleButton(checked: on, onChanged: { _ in action() }, child: Text(label, style: style))
    }

    /// Big button: icon over label, the Paste-shaped one.
    static func big(_ icon: IconData, _ label: String, _ fluent: FluentThemeData,
                    enabled: Bool = true, action: @escaping () -> Void) -> Widget {
        let color = enabled ? fluent.resources.textFillColorPrimary : fluent.resources.textFillColorDisabled
        return Button(onPressed: enabled ? action : nil, child: Padding(
            padding: EdgeInsets(left: 4, top: 2, right: 4, bottom: 2),
            child: Column(mainAxisAlignment: .center, crossAxisAlignment: .center, children: [
                Icon(icon, size: bigIconSize, color: color),
                vgap(4),
                Text(label, style: fluent.typography.caption?.copyWith(color: color)),
            ])))
    }

    /// Small button: icon beside label, stacked three to a column.
    static func small(_ icon: IconData, _ label: String, _ fluent: FluentThemeData,
                      enabled: Bool = true, action: @escaping () -> Void) -> Widget {
        let color = enabled ? fluent.resources.textFillColorPrimary : fluent.resources.textFillColorDisabled
        return Button(onPressed: enabled ? action : nil, child: Row(crossAxisAlignment: .center, children: [
            Icon(icon, size: iconSize, color: color),
            gap(6),
            Text(label, style: fluent.typography.caption?.copyWith(color: color)),
        ]))
    }

    /// A drop-down of named colours with a swatch each.
    static func colorMenu(_ icon: IconData, _ tip: String, _ fluent: FluentThemeData,
                          colors: [(String, Color)], none: String?,
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
        return Tooltip(message: tip, child: DropDownButton(
            leading: Icon(icon, size: iconSize, color: fluent.resources.textFillColorPrimary),
            items: items))
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
        DropDownButton(title: title, leading: leading,
                       items: choices.map { name, action in
                           MenuFlyoutItem(text: Text(name), onPressed: action) as MenuFlyoutItemBase
                       })
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
