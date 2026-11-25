// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A ribbon tab that is wider than its window. The groups give way from the right, one at a time: first a
// group's buttons lose their captions (an icon each, the caption as the tooltip and the accessible name), then
// the whole group becomes one button, named for the group, whose popup holds its controls as they are. The
// widths are measured once per tab (every group at every level, off screen for a frame), so the choice is a
// plain function of the window's width and nothing flickers while it settles; a window too narrow even for
// that scrolls, as the ribbon always has.

import Flutter
import FlutterSwiftBridge

/// Whether the buttons under it show their captions. Set by `RibbonFit` around a group that has given up its captions.
final class RibbonDensity: InheritedWidget {
    let iconsOnly: Bool

    init(iconsOnly: Bool, child: Widget) {
        self.iconsOnly = iconsOnly
        super.init(key: nil, child: child)
    }

    static func iconsOnly(_ context: any BuildContext) -> Bool {
        context.dependOnInheritedWidgetOfExactType(RibbonDensity.self)?.iconsOnly ?? false
    }

    override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        (oldWidget as? RibbonDensity)?.iconsOnly != iconsOnly
    }
}

/// A ribbon button in its two forms: with its caption, and (in a group that has given up its captions) as an icon
/// whose caption is its tooltip.
final class RibbonDensityButton: StatelessWidget {
    let full: Widget
    let iconsOnly: Widget

    init(full: Widget, iconsOnly: Widget) {
        self.full = full
        self.iconsOnly = iconsOnly
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        RibbonDensity.iconsOnly(context) ? iconsOnly : full
    }
}

/// One ribbon group: its commands over a caption, with a divider after. `RibbonFit` shows it as it is, with the
/// captions of its buttons dropped, or as a button that opens it.
final class RibbonGroup: StatelessWidget {
    let label: String
    let content: [Widget]
    let fluent: FluentThemeData

    init(label: String, fluent: FluentThemeData, content: [Widget]) {
        self.label = label
        self.fluent = fluent
        self.content = content
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
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

    /// The group as one button, named for it, that opens its controls.
    func asButton() -> Widget {
        Row(crossAxisAlignment: .stretch, children: [
            Padding(padding: EdgeInsets(left: 6, top: 6, right: 6, bottom: 5), child: RibbonGroupButton(group: self)),
            Padding(padding: EdgeInsets(left: 0, top: 10, right: 0, bottom: 10),
                    child: Divider(direction: .vertical)),
        ])
    }
}

/// The button a collapsed group is. Its popup holds the group's own controls, in a modal keyboard region so Tab
/// walks them and Escape closes it.
private final class RibbonGroupButton: StatefulWidget {
    let group: RibbonGroup
    init(group: RibbonGroup) {
        self.group = group
        super.init(key: nil)
    }
    override func createState() -> State<StatefulWidget> { _RibbonGroupButtonState() }
}

private final class _RibbonGroupButtonState: State<StatefulWidget> {
    private let _flyout = FlyoutController()

    override func dispose() {
        if _flyout.isOpen { _flyout.closeFlyout() }
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let group = (widget as! RibbonGroupButton).group
        let fluent = group.fluent
        let content = group.content
        let button = FlatButton(
            child: Padding(padding: EdgeInsets(left: 8, top: 0, right: 6, bottom: 0), child: Row(mainAxisSize: .min, crossAxisAlignment: .center, children: [
                Text(group.label, style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorPrimary)),
                Chrome.gap(4),
                Chrome.chevron(fluent),
            ])),
            tip: "\(group.label) group", width: nil, height: 28,
            action: { [weak self] in
                guard let self else { return }
                self._flyout.showFlyout(builder: { _ in
                    KeyboardRegion(name: "ribbon-group", modal: true, child: FlyoutContent(
                        // (As tall as a group's buttons: a Column in a group that fills its height would fill the popup's.)
                        child: SizedBox(width: nil, height: Chrome.rowHeight * 3 + 4, child: RibbonDensity(iconsOnly: false, child: Row(mainAxisSize: .min, crossAxisAlignment: .start, children: content))),
                        padding: EdgeInsets(all: 6), constraints: BoxConstraints()))
                }, placement: .bottom)
            })
        return FlyoutTarget(controller: _flyout, child: button)
    }
}

/// The ribbon's groups, fitted to the width they have.
final class RibbonFit: StatefulWidget {
    let groups: [Widget]
    init(key: (any Key)? = nil, groups: [Widget]) {
        self.groups = groups
        super.init(key: key)
    }
    override func createState() -> State<StatefulWidget> { _RibbonFitState() }

    /// The levels a group goes through as the room runs out.
    static let levelCount = 3

    /// How far each group gives way for `available` points, given every group's width at each of its levels
    /// (`widths[i][level]`; a widget that is not a group has one level): the rightmost group that still can goes
    /// one level further until the row fits, or nothing can give any more.
    static func levels(widths: [[Double]], collapsible: [Bool], available: Double) -> [Int] {
        var levels = [Int](repeating: 0, count: widths.count)
        func total() -> Double { levels.indices.reduce(0) { $0 + widths[$1][levels[$1]] } }
        while total() > available, let i = levels.indices.last(where: { collapsible[$0] && levels[$0] < levelCount - 1 }) {
            levels[i] += 1
        }
        return levels
    }
}

private final class _RibbonFitState: State<StatefulWidget> {
    private var _signature = ""
    private var _widths: [[Double]] = []
    private var _seen = Set<String>()
    private var _levels: [Int] = []
    private var _available: Double?
    private var _measuredAll = false   // every group has been measured at every level
    private var _ready = false           // and the row has been built to fit: the measuring stack is gone

    private var _groups: [Widget] { (widget as! RibbonFit).groups }

    private func _isGroup(_ w: Widget) -> Bool { w is RibbonGroup }

    /// Forget the measurements when the tab's groups are not the ones that were measured.
    private func _syncSignature() {
        let signature = _groups.map { ($0 as? RibbonGroup)?.label ?? "·" }.joined(separator: "|")
        guard signature != _signature else { return }
        _signature = signature
        _widths = _groups.map { _ in [Double](repeating: 0, count: RibbonFit.levelCount) }
        _seen = []
        _levels = _groups.map { _ in 0 }
        _ready = false
        _measuredAll = false
    }

    private func _measured(_ index: Int, _ level: Int, _ width: Double) {
        guard mounted, index < _widths.count else { return }
        _widths[index][level] = width
        _seen.insert("\(index)/\(level)")
        if !_measuredAll {
            let expected = _groups.indices.reduce(0) { $0 + (_isGroup(_groups[$1]) ? RibbonFit.levelCount : 1) }
            if _seen.count >= expected { _measuredAll = true; _refit() }
        } else if level == _levels[index] {
            _refit()
        }
    }

    private func _refit() {
        guard mounted, _measuredAll, let available = _available else { return }
        // A widget that is not a group has the one width at every level.
        let widths = _groups.indices.map { i in _isGroup(_groups[i]) ? _widths[i] : [Double](repeating: _widths[i][0], count: RibbonFit.levelCount) }
        let next = RibbonFit.levels(widths: widths, collapsible: _groups.map(_isGroup), available: available)
        if next != _levels || !_ready { setState { _levels = next; _ready = true } }
    }

    override func build(_ context: any BuildContext) -> Widget {
        _syncSignature()
        let groups = _groups
        func row(_ levelOf: (Int) -> Int, measuring: Bool) -> Widget {
            var children: [Widget] = []
            for (i, g) in groups.enumerated() {
                let level = levelOf(i)
                var body: Widget = g
                if let group = g as? RibbonGroup {
                    switch level {
                    case 0: body = group
                    case 1: body = RibbonDensity(iconsOnly: true, child: group)
                    default: body = group.asButton()
                    }
                } else if measuring && level > 0 { continue }
                children.append(SizeReporter(onSize: { [weak self] s in self?._measured(i, level, s.width) }, child: body))
            }
            return Row(crossAxisAlignment: .stretch, children: children)
        }
        let content: Widget
        if _ready {
            content = SingleChildScrollView(scrollDirection: .horizontal, child: row({ [self] in _levels[$0] }, measuring: false))
        } else {
            // One frame, unseen: every group at every level, to learn their widths.
            content = Opacity(opacity: 0, child: Stack(children: (0 ..< RibbonFit.levelCount).map { level in
                SingleChildScrollView(scrollDirection: .horizontal, child: row({ _ in level }, measuring: true))
            }))
        }
        return SizeReporter(onSize: { [weak self] s in
            guard let self, self._available != s.width else { return }
            self._available = s.width
            self._refit()
        }, child: content)
    }
}
