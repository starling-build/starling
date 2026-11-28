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

/// Around the controls of a folded group's popup: what closes it. A command's button calls it once the command has run, unless
/// the button keeps editing (a stepper, Grow Font), so the popup stays for the next press.
/// A menu item that chooses from a panel of its own (the shape grid): in a folded group's popup, `closing` gives the
/// same item also closing that popup once a choice has run, as a plain menu item's press does.
protocol RibbonPopupChoosing {
    func closing(_ also: @escaping () -> Void) -> MenuFlyoutItemBase
}

final class RibbonPopupScope: InheritedWidget {
    let close: () -> Void

    init(close: @escaping () -> Void, child: Widget) {
        self.close = close
        super.init(key: nil, child: child)
    }

    static func close(_ context: (any BuildContext)?) {
        (context?.findAncestorWidgetOfExactType(RibbonPopupScope.self))?.close()
    }

    override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool { false }
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
                // (The commands get the band's room above the caption, so a stack of rows can share it: Chrome.rows.)
                Expanded(child: Row(crossAxisAlignment: .start, children: content)),
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
    /// Opened with the keyboard (Enter on the button): the ring goes into the popup, and back to the button when it closes.
    private var _viaKeyboard = false

    override func initState() {
        super.initState()
        _flyout.onClose = { [weak self] in self?._closed() }
    }

    override func dispose() {
        _flyout.onClose = nil
        if _flyout.isOpen { _flyout.closeFlyout() }
        super.dispose()
    }

    private var _name: String { "\((widget as! RibbonGroupButton).group.label) group" }

    /// After a frame, when the popup's stops are gone (or in): the ring goes where the keyboard was.
    private func _afterFrame(_ f: @escaping () -> Void) {
        FrameCallbackScheduler.shared.addPostFrameCallback { _ in f() }
        PlatformDispatcher.instance.scheduleFrame()
    }

    private func _open() {
        _viaKeyboard = KeyboardTraversal.shared.focused != nil
        let group = (widget as! RibbonGroupButton).group
        let content = group.content
        _flyout.showFlyout(builder: { [weak self] _ in
            KeyboardRegion(name: "ribbon-group", modal: true, child: FlyoutContent(
                // (As tall as a group's buttons: a Column in a group that fills its height would fill the popup's.)
                child: SizedBox(width: nil, height: Chrome.rowHeight * 3 + 4, child: RibbonPopupScope(
                    close: { self?._flyout.closeFlyout() },
                    child: RibbonDensity(iconsOnly: false, child: Row(mainAxisSize: .min, crossAxisAlignment: .start, children: content)))),
                padding: EdgeInsets(all: 6), constraints: BoxConstraints()))
        }, placement: .bottom)
        if _viaKeyboard {
            _afterFrame {
                if let first = KeyboardTraversal.shared.reachable().first(where: { $0.modal }) { KeyboardTraversal.shared.focus(first) }
            }
        }
    }

    private func _closed() {
        guard _viaKeyboard else { return }
        _viaKeyboard = false
        let name = _name
        _afterFrame {
            if let me = KeyboardTraversal.shared.reachable(inRegion: "ribbon").first(where: { $0.label() == name }) {
                KeyboardTraversal.shared.focus(me)
            }
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let group = (widget as! RibbonGroupButton).group
        let fluent = group.fluent
        let button = FlatButton(
            child: Padding(padding: EdgeInsets(left: 8, top: 0, right: 6, bottom: 0), child: Row(mainAxisSize: .min, crossAxisAlignment: .center, children: [
                Text(group.label, style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorPrimary)),
                Chrome.gap(4),
                Chrome.chevron(fluent),
            ])),
            tip: "\(group.label) group", width: nil, height: 28,
            keepsPopupOpen: true,
            action: { [weak self] in self?._open() })
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
    /// (`widths[i][level]`; a widget that is not a group has one level). The rightmost group that still can goes one
    /// level further until the row fits, or nothing can give any more; a step only counts if it makes the group
    /// narrower (a group's one button can be wider than its icons, as a short group's is). Then the groups that
    /// gave way more than the room required come back, leftmost first, as far as the row still fits: a group that
    /// fits is never folded.
    static func levels(widths: [[Double]], collapsible: [Bool], available: Double) -> [Int] {
        var levels = [Int](repeating: 0, count: widths.count)
        func total() -> Double { levels.indices.reduce(0) { $0 + widths[$1][levels[$1]] } }
        func next(_ i: Int) -> Int? {
            guard collapsible[i] else { return nil }
            return (levels[i] + 1 ..< levelCount).first { widths[i][$0] < widths[i][levels[i]] }
        }
        while total() > available, let i = levels.indices.last(where: { next($0) != nil }) {
            levels[i] = next(i)!
        }
        for i in levels.indices where levels[i] > 0 {
            let folded = levels[i]
            for level in 0 ..< folded {
                levels[i] = level
                if total() <= available { break }
                levels[i] = folded
            }
        }
        return levels
    }
}

private final class _RibbonFitState: State<StatefulWidget> {
    private var _signature = ""
    private var _widths: [[Double]] = []     // every group at every level, from the measuring pass only
    private var _live: [String: Double] = [:] // the width each shown group last had on screen ("index/level")
    private var _seen = Set<String>()
    private var _levels: [Int] = []
    private var _available: Double?
    private var _measuredAll = false   // every group has been measured at every level
    private var _ready = false           // and the row has been built to fit: the first measuring stack is gone
    private var _remeasure = false       // a shown group changed width: measure every level again, behind the row

    private var _groups: [Widget] { (widget as! RibbonFit).groups }

    private func _isGroup(_ w: Widget) -> Bool { w is RibbonGroup }

    /// Forget the measurements when the tab's groups are not the ones that were measured.
    private func _syncSignature() {
        let signature = _groups.map { ($0 as? RibbonGroup)?.label ?? "·" }.joined(separator: "|")
        guard signature != _signature else { return }
        _signature = signature
        _widths = _groups.map { _ in [Double](repeating: 0, count: RibbonFit.levelCount) }
        _live = [:]
        _seen = []
        _levels = _groups.map { _ in 0 }
        _ready = false
        _measuredAll = false
        _remeasure = false
    }

    /// A width from the measuring pass: once every group has one at every level, fit the row.
    private func _measured(_ index: Int, _ level: Int, _ width: Double) {
        guard mounted, index < _widths.count else { return }
        _widths[index][level] = width
        _seen.insert("\(index)/\(level)")
        let expected = _groups.indices.reduce(0) { $0 + (_isGroup(_groups[$1]) ? RibbonFit.levelCount : 1) }
        guard _seen.count >= expected else { return }
        _measuredAll = true
        if _remeasure { setState { self._remeasure = false } }
        _refit()
    }

    /// A width of the row on screen. The fold never reads it: the same width must fold the same way whatever came
    /// before, and a group on screen can measure a little apart from the same group in the measuring pass (Mac's UI
    /// font), so mixing the two made the fold depend on which levels had been shown. A shown group whose width
    /// changes (a label or control that changed with its state) has new content at every level: measure them all again.
    private func _shown(_ index: Int, _ level: Int, _ width: Double) {
        guard mounted, _ready else { return }
        let key = "\(index)/\(level)"
        let was = _live[key]
        _live[key] = width
        guard let was, abs(was - width) > 0.5, !_remeasure else { return }
        setState { self._seen = []; self._remeasure = true }
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
                children.append(SizeReporter(onSize: { [weak self] s in
                    if measuring { self?._measured(i, level, s.width) } else { self?._shown(i, level, s.width) }
                }, child: body))
            }
            return Row(crossAxisAlignment: .stretch, children: children)
        }
        // Every group at every level, unseen, to learn their widths.
        func measuring() -> Widget {
            Opacity(opacity: 0, child: Stack(children: (0 ..< RibbonFit.levelCount).map { level in
                SingleChildScrollView(scrollDirection: .horizontal, child: row({ _ in level }, measuring: true))
            }))
        }
        let content: Widget
        if _ready {
            let shown = SingleChildScrollView(scrollDirection: .horizontal, child: row({ [self] in _levels[$0] }, measuring: false))
            // Measuring again: the row stays as it is, the pass goes on unseen behind it and out of the pointer's way.
            content = _remeasure ? Stack(children: [shown, IgnorePointer(child: ExcludeSemantics(child: measuring()))]) : shown
        } else {
            content = measuring()
        }
        return SizeReporter(onSize: { [weak self] s in
            guard let self, self._available != s.width else { return }
            self._available = s.width
            self._refit()
        }, child: content)
    }
}
