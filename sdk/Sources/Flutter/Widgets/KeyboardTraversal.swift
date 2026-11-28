// Keyboard traversal: Tab / Shift+Tab between controls, F6 between regions,
// Enter or Space to press, Esc to go back.
//
// The minimal focus system (FocusManagerStubs.swift) has no traversal, so a
// control that wants the keyboard registers a `KeyStop`. Stops are ordered
// by where they are on screen (rows top to bottom, left to right), never by
// the order they were built, so a ribbon or a dialog is walked as it reads.

import FlutterSwiftBridge

/// Marks a part of the window as a keyboard region (the ribbon, a pane, a
/// dialog). F6 moves between regions; a `modal` region (a dialog) holds Tab
/// inside itself while it is open, and hides what was painted under it from
/// screen readers (BlockSemantics), as the keyboard cannot reach it either.
public final class KeyboardRegion: StatelessWidget {
    public let name: String
    public let modal: Bool
    public let child: Widget

    public init(name: String, modal: Bool = false, child: Widget) {
        self.name = name
        self.modal = modal
        self.child = child
        super.init(key: nil)
    }

    public override func build(_ context: any BuildContext) -> Widget { modal ? BlockSemantics(child: child) : child }
}

/// Marks a document page as a keyboard stop: F6 (or Ctrl+F6) moves typing into it. `focus` puts the
/// caret there (it requests the editor's focus).
public final class KeyboardPage: StatefulWidget {
    public let name: String
    public let region: String
    public let focus: () -> Void
    public let child: Widget
    public init(name: String = "Document", region: String = "page", focus: @escaping () -> Void, child: Widget) {
        self.name = name; self.region = region; self.focus = focus; self.child = child
        super.init(key: nil)
    }
    public override func createState() -> State<StatefulWidget> { _KeyboardPageState() }
}

final class _KeyboardPageState: State<StatefulWidget> {
    private var _stop: KeyStop?
    override func initState() {
        super.initState()
        let stop = KeyStop(region: (widget as! KeyboardPage).region, modal: false)
        stop.handsOver = true
        stop.onFocus = { [weak self] on in if on, let w = self?.widget as? KeyboardPage { w.focus() } }
        stop.label = { [weak self] in (self?.widget as? KeyboardPage)?.name }
        stop.box = { [weak self] in
            guard let self, self.mounted, let box = self.context?.findRenderObject() as? RenderBox,
                  box.attached, box.hasSize else { return nil }
            return box
        }
        _stop = stop
        KeyboardTraversal.shared.register(stop)
    }
    override func dispose() {
        if let s = _stop { KeyboardTraversal.shared.unregister(s) }
        super.dispose()
    }
    override func build(_ context: any BuildContext) -> Widget { (widget as! KeyboardPage).child }
}

/// A row of a list (a name, a slide tile, a page of a menu): the keyboard can walk it, up and down
/// arrows (and Tab) move to the next row, Enter does what a click does. A ring marks the row.
public final class KeyboardRow: StatefulWidget {
    public let label: String
    public let activate: () -> Void
    public let child: Widget
    public init(label: String, activate: @escaping () -> Void, child: Widget) {
        self.label = label; self.activate = activate; self.child = child
        super.init(key: nil)
    }
    public override func createState() -> State<StatefulWidget> { _KeyboardRowState() }
}

final class _KeyboardRowState: State<StatefulWidget> {
    private var _stop: KeyStop?
    private var _ring = false
    override func initState() {
        super.initState()
        let r = KeyboardTraversal.regionName(context!)
        let stop = KeyStop(region: r.name, modal: r.modal)
        stop.activate = { [weak self] in (self?.widget as? KeyboardRow)?.activate() }
        stop.label = { [weak self] in (self?.widget as? KeyboardRow)?.label }
        stop.onFocus = { [weak self] on in
            guard let self, self.mounted else { return }
            self.setState { self._ring = on }
        }
        stop.onArrow = { dx, dy in
            let d = dy != 0 ? dy : dx
            if d == 0 { return false }
            KeyboardTraversal.shared.move(reverse: d < 0); return true
        }
        stop.box = { [weak self] in
            guard let self, self.mounted, let box = self.context?.findRenderObject() as? RenderBox,
                  box.attached, box.hasSize else { return nil }
            return box
        }
        _stop = stop
        KeyboardTraversal.shared.register(stop)
    }
    override func dispose() {
        if let s = _stop { KeyboardTraversal.shared.unregister(s) }
        super.dispose()
    }
    override func build(_ context: any BuildContext) -> Widget {
        let row = widget as! KeyboardRow
        // A screen reader hears the row by the name the keyboard uses, and can press it the same way; a row whose
        // child already describes itself (a slide thumbnail with its selected state) keeps that description.
        let child: Widget = row.child is Semantics ? row.child
            : Semantics(label: row.label, button: true, onTap: row.activate, excludeSemantics: true, child: row.child)
        // The same shape with or without the ring: a lazy list cannot remount a row whose root changed type, and the
        // row would vanish from the screen under the ring.
        let ring: [Widget] = _ring ? [Positioned(left: 0, top: 0, right: 0, bottom: 0, child: IgnorePointer(child: DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: Color(0xFF0F6CBD), width: 2)))))] : []
        return Stack(clipBehavior: .none, children: [child] + ring)
    }
}

/// One control the keyboard can reach.
public final class KeyStop {
    public let region: String
    public let modal: Bool
    /// False for a disabled control: it is skipped.
    public var isEnabled: () -> Bool = { true }
    /// Pressing it (Enter or Space).
    public var activate: () -> Void = {}
    /// Told when the keyboard focus arrives or leaves, to draw or drop the ring.
    public var onFocus: (Bool) -> Void = { _ in }
    /// True while the control already holds the typing focus (a text box the pointer clicked).
    public var isCurrent: () -> Bool = { false }
    /// The control's box while it is laid out, nil when it is not drawn.
    public var box: () -> RenderBox? = { nil }
    /// Its top-left corner on screen, nil when it is not drawn.
    public func origin() -> Offset? { box()?.localToGlobal(Offset(0, 0)) }
    /// Its corner with every scroll above it undone: reading order, which must not change as a list scrolls under
    /// the ring (the list's rows would pass the buttons beside it).
    public func place() -> Offset? {
        guard let b = box() else { return nil }
        var o = b.localToGlobal(Offset(0, 0))
        var p = b.parent
        while let r = p {
            if let v = r as? ScrollShifting { o = o - v.scrollShift }
            p = r.parent
        }
        return o
    }
    /// What it is called (a key tip is taken from its letters); nil when it has no name.
    public var label: () -> String? = { nil }
    /// An arrow key while this control holds the ring (dx, dy each -1, 0 or 1); true when it used the key
    /// (a slider moves its thumb). Unset, the arrows walk on like Tab.
    /// True for a document page: F6 puts typing there and the ring steps aside, so Tab and the arrows stay the editor's.
    public var handsOver = false
    public var onArrow: ((Int, Int) -> Bool)?

    public init(region: String, modal: Bool) {
        self.region = region
        self.modal = modal
    }
}

public final class KeyboardTraversal {
    public static let shared = KeyboardTraversal()

    private var _stops: [KeyStop] = []
    private var _token: Int?
    private var _shift = false
    private var _currentRegion: String?
    private var _pointer: PointerRouteEntry?
    /// Where typing was when the ring took over, so Esc can give it back.
    private weak var _saved: FocusNode?

    // Alt key tips: tap Alt, a letter over each tab title; press one and its page's commands get letters.
    /// True while the key tips are showing.
    public private(set) var tipsOn = false
    private var _tipStage = 0
    private var _tipTyped = ""
    private var _altClean = false
    private var _tipListeners: [Int: () -> Void] = [:]
    private var _nextListener = 0

    public func addTipsListener(_ f: @escaping () -> Void) -> Int {
        _nextListener += 1; _tipListeners[_nextListener] = f; return _nextListener
    }
    public func removeTipsListener(_ id: Int) { _tipListeners[id] = nil }
    private func _tipsChanged() { for f in _tipListeners.values { f() } }

    /// The key tip of every control the tips can reach now: the tab strip first, then (after a tab
    /// letter) the commands of the open page. Letters come from each control's own name.
    public func tipCodes() -> [(stop: KeyStop, code: String)] {
        guard tipsOn else { return [] }
        let pool: [KeyStop]
        if _tipMenus > 0 {
            // A menu a command's letter opened: its items get letters, as Word's do.
            pool = reachable().filter { $0.modal && $0.label() != nil }
        } else {
            let live = reachable().filter { !$0.modal && $0.region == "ribbon" }
            guard let top = live.map({ ($0.origin()!.dy / 10).rounded() }).min() else { return [] }
            let strip = live.filter { ($0.origin()!.dy / 10).rounded() == top }
            pool = (_tipStage == 0 ? strip : live.filter { s in !strip.contains { $0 === s } }).filter { $0.label() != nil }
        }
        var used = Set<String>()
        var out: [(KeyStop, String)] = []
        let single = pool.count <= 26
        for s in pool {
            let letters = (s.label() ?? "").uppercased().filter { $0.isLetter && $0.isASCII }.map { String($0) }
            var code: String?
            if single {
                code = letters.first { !used.contains($0) }
                    ?? "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { String($0) }.first { !used.contains($0) }
            } else {
                let a = letters.first ?? "X"
                let seconds = Array(letters.dropFirst()) + "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".map { String($0) }
                code = seconds.map { a + $0 }.first { !used.contains($0) }
            }
            guard let c = code else { continue }
            used.insert(c); out.append((s, c))
        }
        return out
    }

    /// How many menus showing key tips are open (a KeyTipLayer(modal: true) counts itself in and out).
    private var _tipMenus = 0
    public func tipMenuOpened() { _tipMenus += 1 }
    public func tipMenuClosed() {
        _tipMenus = max(0, _tipMenus - 1)
        // The menu is gone: the ribbon's command letters come back (Esc closed it), on the next frame.
        if tipsOn { FrameCallbackScheduler.shared.addPostFrameCallback { [weak self] _ in self?._tipsChanged() } }
    }

    public func endTips() {
        guard tipsOn else { return }
        tipsOn = false; _tipStage = 0; _tipTyped = ""
        _tipsChanged()
    }

    private func _handleTipKey(_ key: KeyData) -> Bool {
        let l = key.logical
        if l == 0xFF1B || l == 0x1_0000_001B {
            // Esc goes back one level, as in Word: a page's command letters back to the tab letters, then off.
            // An open menu's own Esc closes it, and the command letters come back.
            if _tipMenus > 0 { return false }
            if _tipStage == 1, _tipMenus == 0 { _tipStage = 0; _tipTyped = ""; _tipsChanged() } else { endTips() }
            return true
        }
        guard let ch = key.character?.uppercased(), ch.count == 1, ch.first!.isASCII, ch.first!.isLetter || ch.first!.isNumber else {
            endTips(); return false
        }
        _tipTyped += ch
        let codes = tipCodes()
        if let hit = codes.first(where: { $0.code == _tipTyped }) {
            _tipTyped = ""
            let wasTabs = _tipStage == 0, inMenu = _tipMenus > 0
            hit.stop.activate()
            if wasTabs { _tipStage = 1; _tipsChanged() }
            else if inMenu { endTips() }
            else {
                // A command that opens a menu keeps the letters going on its items; any other command ends them.
                FrameCallbackScheduler.shared.addPostFrameCallback { [weak self] _ in
                    guard let self, self.tipsOn else { return }
                    if self._tipMenus > 0 { self._tipsChanged() } else { self.endTips() }
                }
            }
        } else if !codes.contains(where: { $0.code.hasPrefix(_tipTyped) }) {
            endTips()
        } else { _tipsChanged() }
        return true
    }

    /// The control that has the keyboard focus ring, if any.
    public private(set) var focused: KeyStop?
    /// Called when Esc leaves the ring, so the owner can put focus back in the editor.
    public var onLeave: (() -> Void)?

    public static func regionName(_ context: any BuildContext) -> (name: String, modal: Bool) {
        if let r = context.findAncestorWidgetOfExactType(KeyboardRegion.self) { return (r.name, r.modal) }
        return ("window", false)
    }

    public func register(_ stop: KeyStop) {
        _stops.append(stop)
        if _token == nil {
            _token = FocusManager.instance.addKeyInterceptor { [unowned self] key in self.handle(key) }
            // A click puts the keyboard back where the pointer went: the editor keeps its own Tab.
            _pointer = GestureBinding.instance.pointerRouter.addGlobalRoute { [unowned self] event in
                if event is PointerDownEvent { self.endTips(); if self.focused != nil { self._focus(nil) } }
            }
        }
    }

    public func unregister(_ stop: KeyStop) {
        _stops.removeAll { $0 === stop }
        if focused === stop { focused = nil }
    }

    /// Every control the keyboard can reach now, in reading order.
    public func reachable(inRegion region: String? = nil) -> [KeyStop] {
        let live = _stops.filter { $0.isEnabled() && $0.origin() != nil }
        let pool: [KeyStop]
        if live.contains(where: { $0.modal }) { pool = live.filter { $0.modal } }
        else if let region { pool = live.filter { $0.region == region } }
        else { pool = live }
        return pool.sorted { a, b in
            let pa = a.place()!, pb = b.place()!
            let ra = (pa.dy / 10).rounded(), rb = (pb.dy / 10).rounded()
            return ra != rb ? ra < rb : pa.dx < pb.dx
        }
    }

    private var _modalOpen: Bool { _stops.contains { $0.modal && $0.origin() != nil } }

    /// The regions on screen, top to bottom.
    public func regions() -> [String] {
        var seen: [String] = []
        for s in reachable() where !seen.contains(s.region) { seen.append(s.region) }
        return seen
    }

    private func _focus(_ stop: KeyStop?) {
        if let stop, stop.handsOver {
            focused?.onFocus(false); focused = nil
            _currentRegion = stop.region
            stop.onFocus(true)
            return
        }
        if focused === stop { return }
        if focused == nil, stop != nil { _saved = FocusManager.instance.focusedNode }
        focused?.onFocus(false)
        focused = stop
        if let stop { _currentRegion = stop.region }
        stop?.onFocus(true)
        // A ring below the fold of a gallery, pane or list scrolls into view, as Windows does.
        stop?.box()?.showOnScreen()
    }

    /// Puts the ring on `stop` (or takes it away with nil): a popup closing hands it back to the button that opened it.
    public func focus(_ stop: KeyStop?) { _focus(stop) }

    /// Moves the ring one control on, or back.
    public func move(reverse: Bool) {
        // A text box the pointer clicked walks its own region (a pane's box Tabs on within the pane).
        let current = focused == nil ? _stops.first(where: { $0.isCurrent() && $0.isEnabled() && $0.origin() != nil }) : nil
        let list = reachable(inRegion: _modalOpen ? nil : (focused?.region ?? current?.region ?? _currentRegion ?? regions().first))
        guard !list.isEmpty else { return }
        guard let f = focused ?? list.first(where: { $0.isCurrent() }), let i = list.firstIndex(where: { $0 === f }) else {
            _focus(reverse ? list.last : list.first); return
        }
        // Tab out of a text box onto a button or a check box: the box lets go of the keyboard, as in Windows, so it
        // applies what was typed (its blur) and the next keys are the ring's, not more text in the box.
        let field = focused == nil ? FocusManager.instance.focusedNode : nil
        _focus(list[(i + (reverse ? list.count - 1 : 1)) % list.count])
        if let field, FocusManager.instance.focusedNode === field { field.unfocus() }
    }

    /// F6: the ring goes to the first control of the next region.
    public func moveRegion(reverse: Bool) {
        if _modalOpen { move(reverse: reverse); return }
        let names = regions()
        guard !names.isEmpty else { return }
        let at = (focused?.region ?? _currentRegion).flatMap { names.firstIndex(of: $0) }
        let next = at.map { (($0 + (reverse ? names.count - 1 : 1)) % names.count) } ?? 0
        _focus(reachable(inRegion: names[next]).first)
    }

    /// Takes the ring away (the keyboard is back with the editor).
    /// Drops the ring without moving the keyboard: for a view that takes the keyboard itself (a slide show), so
    /// its Esc reaches it instead of sending the focus back to what the ring left.
    public func release() {
        _focus(nil)
        _saved = nil
    }

    public func leave() {
        _focus(nil)
        _saved?.requestFocus()
        onLeave?()
    }

    /// Returns true for a key it used. Called first by the key dispatch (and by
    /// a dialog's own key handler before its Enter and Esc).
    public func handle(_ key: KeyData) -> Bool {
        let l = key.logical
        if l == 0xFFE9 || l == 0xFFEA || l == 0x2_0000_0104 || l == 0x2_0000_0105 {     // Alt
            if key.type == .down { _altClean = true }
            else if key.type == .up, _altClean {
                _altClean = false
                if tipsOn { endTips() } else if !_modalOpen { tipsOn = true; _tipStage = 0; _tipTyped = ""; _focus(nil); _tipsChanged() }
            }
            return false
        }
        if l != 0xFFE1, l != 0xFFE2, l != 0x2_0000_0102, l != 0x2_0000_0103 { _altClean = false }
        if tipsOn, key.type == .down || key.type == .repeat { return _handleTipKey(key) }
        if l == 0xFFE1 || l == 0xFFE2 || l == 0x2_0000_0102 || l == 0x2_0000_0103 {
            _shift = key.type != .up
            return false
        }
        guard key.type == .down || key.type == .repeat else { return false }
        switch l {
        case 0xFF09, 0x1_0000_0009:                      // Tab
            guard focused != nil || _modalOpen || _stops.contains(where: { $0.isCurrent() }) else { return false }
            move(reverse: _shift); return true
        case 0xFFBD:                                     // F6
            moveRegion(reverse: _shift); return true
        case 0xFF0D, 0xFF8D, 0x1_0000_000D, 0x20, 0x1_0000_0020:   // Enter, Space
            guard let f = focused else { return false }
            f.activate(); return true
        case 0xFF1B, 0x1_0000_001B:                      // Esc
            guard focused != nil else { return false }
            leave(); return true
        case 0xFF51, 0xFF53, 0xFF52, 0xFF54:             // arrows walk the ribbon like Tab
            guard let f = focused else { return false }
            if f.modal && f.isCurrent() { return false }     // a text box in a dialog keeps its caret keys
            if let a = f.onArrow, a(l == 0xFF51 ? -1 : l == 0xFF53 ? 1 : 0, l == 0xFF52 ? -1 : l == 0xFF54 ? 1 : 0) { return true }
            move(reverse: l == 0xFF51 || l == 0xFF52); return true
        default:
            if focused != nil, key.character?.isEmpty == false { _focus(nil) }   // typing goes to the editor
            return false
        }
    }

    /// Test hook: forget everything.
    public func reset() {
        focused = nil
        tipsOn = false; _tipStage = 0; _tipTyped = ""; _altClean = false
        _currentRegion = nil
        _shift = false
        _stops.removeAll()
        if let t = _token { FocusManager.instance.removeKeyInterceptor(t); _token = nil }
        if let e = _pointer { GestureBinding.instance.pointerRouter.removeGlobalRoute(e); _pointer = nil }
    }
}
