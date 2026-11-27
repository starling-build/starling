// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Building blocks the ribbon, title row and status bar share: a group with
// its caption, big and small command buttons, toggles, and the colour menu.
// Everything is a plain function returning a widget tree built with the
// explicit `children:` initializers — the trailing-closure builders crashed
// the 6.2.1 type checker on trees this deep.

import Flutter
import OfficeText
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
    /// What assistive technology and the keyboard ring call it, where that is not the tooltip: an icon-only form of a titled
    /// menu keeps its caption as its name while its tooltip says what it does.
    let name: String?
    let checked: Bool
    /// A toggle reports its state on or off; a plain button has none (it may still be drawn checked).
    let isToggle: Bool
    let enabled: Bool
    let width: Double?
    let height: Double
    let alignLeft: Bool
    let onAccent: Bool
    let action: (() -> Void)?
    let menu: [MenuFlyoutItemBase]?
    /// In a folded group's popup, the popup closes once a press has run, unless the button is one that goes on editing (a stepper).
    let keepsPopupOpen: Bool

    init(child: Widget, tip: String? = nil, name: String? = nil, checked: Bool = false, isToggle: Bool = false, enabled: Bool = true,
         width: Double? = 28, height: Double = 28, alignLeft: Bool = false, onAccent: Bool = false,
         keepsPopupOpen: Bool = false, action: (() -> Void)? = nil, menu: [MenuFlyoutItemBase]? = nil) {
        self.child = child
        self.tip = tip
        self.name = name
        self.checked = checked
        self.isToggle = isToggle
        self.enabled = enabled
        self.width = width
        self.height = height
        self.alignLeft = alignLeft
        self.onAccent = onAccent
        self.action = action
        self.menu = menu
        self.keepsPopupOpen = keepsPopupOpen
        super.init(key: nil)
    }

    override func createState() -> State<StatefulWidget> { _FlatButtonState() }
}

private final class _FlatButtonState: State<StatefulWidget> {
    private var _hover = false
    private var _ring = false
    private var _stop: KeyStop?
    private let _flyout = FlyoutController()

    override func initState() {
        super.initState()
        let r = KeyboardTraversal.regionName(context!)
        let stop = KeyStop(region: r.name, modal: r.modal)
        stop.isEnabled = { [weak self] in (self?.widget as? FlatButton)?.enabled ?? false }
        stop.activate = { [weak self] in
            guard let self, let w = self.widget as? FlatButton else { return }
            if let items = w.menu { self._flyout.showFlyout(builder: { _ in MenuFlyout(items: self._closingPopup(items, w)) }, placement: .bottom) }
            else { w.action?(); self._closePopup(w) }
        }
        stop.label = { [weak self] in
            guard let self, self.mounted else { return nil }
            if let b = self.widget as? FlatButton, let t = b.name ?? b.tip, !t.isEmpty { return t }
            // else the first words it shows (a big button's caption)
            var found: String?
            func walk(_ e: Element) {
                if found != nil { return }
                if let t = e.widget as? Text, let d = t.data, !d.isEmpty { found = d; return }
                e.visitChildElements(walk)
            }
            if let e = self.context as? Element { walk(e) }
            return found
        }
        stop.onFocus = { [weak self] (on: Bool) in
            guard let self, self.mounted else { return }
            self.setState { self._ring = on }
        }
        stop.origin = { [weak self] in
            guard let self, self.mounted, let box = self.context?.findRenderObject() as? RenderBox,
                  box.attached, box.hasSize else { return nil }
            return box.localToGlobal(Offset(0, 0))
        }
        _stop = stop
        KeyboardTraversal.shared.register(stop)
    }

    /// In a folded group's popup, a command that has run closes it.
    fileprivate func _closePopup(_ w: FlatButton) {
        if !w.keepsPopupOpen { RibbonPopupScope.close(context) }
    }

    /// The same items, each also closing the popup this button is in once it has run.
    fileprivate func _closingPopup(_ items: [MenuFlyoutItemBase], _ w: FlatButton) -> [MenuFlyoutItemBase] {
        guard !w.keepsPopupOpen, context?.findAncestorWidgetOfExactType(RibbonPopupScope.self) != nil else { return items }
        return items.map { item in
            guard let i = item as? MenuFlyoutItem, let press = i.onPressed else { return item }
            return MenuFlyoutItem(key: i.key, text: i.text, leading: i.leading, trailing: i.trailing,
                                  onPressed: { [weak self] in press(); self?._closePopup(w) },
                                  onLongPress: i.onLongPress, selected: i.selected, closeAfterClick: i.closeAfterClick)
        }
    }

    override func dispose() {
        if let s = _stop { KeyboardTraversal.shared.unregister(s) }
        _stop = nil
        super.dispose()
    }

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
            if _ring { stroke = fluent.brightness == .dark ? OfficeAppearance.white : Color(0xFF000000) }
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
                    self?._flyout.showFlyout(builder: { _ in MenuFlyout(items: self?._closingPopup(items, w) ?? items) }, placement: .bottom)
                } else {
                    w.action?()
                    self?._closePopup(w)
                }
            } : nil,
            behavior: .opaque,
            child: MouseRegion(
                onEnter: { [weak self] _ in self?.setState { self?._hover = true } },
                onExit: { [weak self] _ in self?.setState { self?._hover = false } },
                child: box))
        if items != nil { box = FlyoutTarget(controller: _flyout, child: box) }
        if let tip = w.tip { box = Tooltip(message: tip, child: box) }
        // Told to assistive technology: the tip is the name of an icon-only button; a text button reads its own text.
        let say = Semantics(label: w.name ?? w.tip, button: true, toggled: w.isToggle ? w.checked : (w.checked ? true : nil), enabled: w.enabled,
                            onTap: w.enabled ? w.action : nil, excludeSemantics: w.tip != nil, child: box)
        return w.tip == nil ? MergeSemantics(child: say) : say
    }
}

enum Chrome {
    static let ribbonHeight = 104.0
    static let iconSize = 16.0
    static let bigIconSize = 28.0
    static let rowHeight = 28.0
    /// The same, for a field that is otherwise as tall as its text: nil under a pointer.
    static var touchFieldHeight: Double? { fieldHeight > 30 ? fieldHeight : nil }
    /// A dialog's text field: 44 pt where it is touched (Apple's minimum target), 30 under a pointer.
    static var fieldHeight: Double {
        #if os(iOS)
        44
        #else
        30
        #endif
    }

    // MARK: Groups

    /// A ribbon group: its commands over a caption, with a divider after.
    static func group(_ label: String, _ fluent: FluentThemeData, _ content: [Widget]) -> Widget {
        RibbonGroup(label: label, fluent: fluent, content: content)
    }

    /// A column of small rows inside a group; the rows stretch to the
    /// widest so labelled buttons under each other share one edge.
    static func rows(_ rows: [Widget]) -> Widget {
        // The ribbon row is unbounded, so a stretching column needs its
        // own width first: the widest row's.
        // In a ribbon group the rows share the room above the caption: a row
        // is never taller than its share (gaps keep theirs), so four small
        // rows, or three full-height ones, fit over the caption instead of
        // overrunning it (Sheets' Clipboard and Cells, 84 in 80).
        IntrinsicWidth(child: Column(mainAxisAlignment: .start, crossAxisAlignment: .stretch, children: rows.map {
            $0 is SizedBox ? $0 : Flexible(child: $0)
        }))
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
                     enabled: Bool = true, keepsPopupOpen: Bool = false, action: @escaping () -> Void) -> Widget {
        let color = enabled ? fluent.resources.textFillColorPrimary : fluent.resources.textFillColorDisabled
        return FlatButton(child: Icon(icon, size: iconSize, color: color), tip: tip, enabled: enabled, keepsPopupOpen: keepsPopupOpen, action: action)
    }

    /// Icon toggle: tinted while on.
    static func toggle(_ icon: IconData, _ tip: String, _ on: Bool, _ fluent: FluentThemeData,
                       action: @escaping () -> Void) -> Widget {
        FlatButton(child: Icon(icon, size: iconSize, color: on
                              ? fluent.accentColor.defaultBrushFor(fluent.brightness)
                              : OfficeAppearance.ink(fluent)),
                   tip: tip, checked: on, isToggle: true, action: {
                       action()
                       // "Bold (Ctrl+B)" is said "Bold on": the shortcut is not part of the name.
                       let name = tip.firstIndex(of: "(").map { String(tip[..<$0]) } ?? tip
                       ScreenReader.announce("\(name.hasSuffix(" ") ? String(name.dropLast()) : name) \(on ? "off" : "on")")
                   })
    }

    /// Text toggle (the view switches).
    static func textToggle(_ label: String, _ on: Bool, _ fluent: FluentThemeData,
                           style: Flutter.TextStyle? = nil, action: @escaping () -> Void) -> Widget {
        FlatButton(child: Padding(padding: EdgeInsets(left: 8, top: 0, right: 8, bottom: 0), child: Text(label, style: style)),
                   checked: on, isToggle: true, width: nil, action: action)
    }

    /// Big button: icon over label, the Paste-shaped one, both rows tall.
    static func big(_ icon: IconData, _ label: String, _ fluent: FluentThemeData,
                    enabled: Bool = true, action: @escaping () -> Void) -> Widget {
        let color = enabled ? fluent.resources.textFillColorPrimary : fluent.resources.textFillColorDisabled
        return RibbonDensityButton(
            full: FlatButton(child: Padding(padding: EdgeInsets(left: 6, top: 2, right: 6, bottom: 2),
                child: Column(mainAxisAlignment: .center, crossAxisAlignment: .center, children: [
                    Icon(icon, size: bigIconSize, color: color),
                    vgap(4),
                    Text(label, style: fluent.typography.caption?.copyWith(color: color)),
                ])), tip: nil, enabled: enabled, width: nil, height: rowHeight * 2 + 6, action: action),
            iconsOnly: FlatButton(child: Icon(icon, size: bigIconSize, color: color),
                tip: label, enabled: enabled, width: 36, height: rowHeight * 2 + 6, action: action))
    }

    /// Big toggle: the big button's shape, tinted while on (Spelling).
    static func bigToggle(_ icon: IconData, _ label: String, _ on: Bool, _ fluent: FluentThemeData,
                          action: @escaping () -> Void) -> Widget {
        let color = fluent.resources.textFillColorPrimary
        return RibbonDensityButton(
            full: FlatButton(child: Padding(padding: EdgeInsets(left: 6, top: 2, right: 6, bottom: 2),
                child: Column(mainAxisAlignment: .center, crossAxisAlignment: .center, children: [
                    Icon(icon, size: bigIconSize, color: color),
                    vgap(4),
                    Text(label, style: fluent.typography.caption?.copyWith(color: color)),
                ])), checked: on, isToggle: true, width: nil, height: rowHeight * 2 + 6, action: action),
            iconsOnly: FlatButton(child: Icon(icon, size: bigIconSize, color: color),
                tip: label, checked: on, isToggle: true, width: 36, height: rowHeight * 2 + 6, action: action))
    }

    /// Small button: icon beside label, stacked three to a column.
    static func small(_ icon: IconData, _ label: String, _ fluent: FluentThemeData,
                      enabled: Bool = true, checked: Bool = false, action: @escaping () -> Void) -> Widget {
        let color = enabled ? fluent.resources.textFillColorPrimary : fluent.resources.textFillColorDisabled
        return RibbonDensityButton(
            full: FlatButton(child: Row(mainAxisSize: .min, crossAxisAlignment: .center, children: [
                Icon(icon, size: iconSize, color: color),
                gap(6),
                Text(label, style: fluent.typography.caption?.copyWith(color: color)),
            ]), checked: checked, enabled: enabled, width: nil, height: 21, alignLeft: true, action: action),
            iconsOnly: FlatButton(child: Icon(icon, size: iconSize, color: color),
                tip: label, checked: checked, enabled: enabled, width: 24, height: 21, action: action))
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
        let full = FlatButton(child: Padding(padding: EdgeInsets(left: 6, top: 0, right: 5, bottom: 0),
                                             child: Row(mainAxisSize: .min, crossAxisAlignment: .center, children: parts)),
                              tip: tip, width: nil, menu: items)
        // A titled button with an icon can give up its title (and keep the title as its name).
        guard let icon, let title else { return full }
        let compact = FlatButton(child: Padding(padding: EdgeInsets(left: 6, top: 0, right: 5, bottom: 0), child: Row(mainAxisSize: .min, crossAxisAlignment: .center, children: [
                                     Icon(icon, size: iconSize, color: fluent.resources.textFillColorPrimary), gap(4), chevron(fluent)])),
                                 tip: tip ?? title, name: title, width: nil, menu: items)
        return RibbonDensityButton(full: full, iconsOnly: compact)
    }

    /// The narrow half of a split button: a chevron that opens `items`,
    /// beside a command that acts on its own.
    static func splitChevron(_ tip: String, _ fluent: FluentThemeData, items: [MenuFlyoutItemBase]) -> Widget {
        FlatButton(child: chevron(fluent), tip: tip, width: 14, menu: items)
    }

    /// A drop-down of named colours with a swatch each.
    static func colorMenu(_ icon: IconData, _ tip: String, _ fluent: FluentThemeData,
                          colors: [(String, Color)], none: String?, more: (() -> Void)? = nil, title: String? = nil,
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
        return menuButton(icon, title, tip, fluent, items: items)
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
                        unit: String = "pt", minimum: Double = 0, shown: String? = nil,
                        onChanged: @escaping (Double) -> Void) -> Widget {
        row([
            SizedBox(width: 84, height: nil, child: Text(label, style: fluent.typography.caption)),
            icon(FluentSystemIcons.chevronDown, "Less", fluent, keepsPopupOpen: true) { onChanged(max(minimum, value - step)) },
            // `shown` is the value as the caller writes it, where a whole
            // number of `unit` is not how it reads (0.75 s).
            SizedBox(width: 48, height: nil, child: Text(shown ?? "\(Int(value.rounded())) \(unit)", style: fluent.typography.caption)),
            icon(FluentSystemIcons.chevronUp, "More", fluent, keepsPopupOpen: true) { onChanged(value + step) },
        ])
    }

    /// A drop-down of plain choices.
    static func menu(_ title: Widget?, _ leading: Widget?, _ fluent: FluentThemeData,
                     _ choices: [(String, () -> Void)], keyPrefix: String? = nil, tip: String? = nil) -> Widget {
        let items = choices.map { name, action in
            MenuFlyoutItem(text: keyPrefix.map { Padding(key: ValueKey("\($0).\(name)"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child: Text(name)) as Widget } ?? Text(name),
                           onPressed: action) as MenuFlyoutItemBase }
        var parts: [Widget] = []
        if let leading { parts.append(leading) }
        if let title { if leading != nil { parts.append(gap(6)) }; parts.append(title) }
        parts.append(gap(4))
        parts.append(chevron(fluent))
        return FlatButton(child: Padding(padding: EdgeInsets(left: 6, top: 0, right: 5, bottom: 0),
                                         child: Row(mainAxisSize: .min, crossAxisAlignment: .center, children: parts)),
                          tip: tip, width: nil, menu: items)
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
