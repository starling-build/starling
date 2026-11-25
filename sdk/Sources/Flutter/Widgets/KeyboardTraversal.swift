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
/// inside itself while it is open.
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

    public override func build(_ context: any BuildContext) -> Widget { child }
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
    /// Its top-left corner on screen, nil when it is not drawn.
    public var origin: () -> Offset? = { nil }

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
                if event is PointerDownEvent, self.focused != nil { self._focus(nil) }
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
            let pa = a.origin()!, pb = b.origin()!
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
        if focused === stop { return }
        if focused == nil, stop != nil { _saved = FocusManager.instance.focusedNode }
        focused?.onFocus(false)
        focused = stop
        if let stop { _currentRegion = stop.region }
        stop?.onFocus(true)
    }

    /// Moves the ring one control on, or back.
    public func move(reverse: Bool) {
        let list = reachable(inRegion: _modalOpen ? nil : (focused?.region ?? _currentRegion ?? regions().first))
        guard !list.isEmpty else { return }
        guard let f = focused ?? list.first(where: { $0.isCurrent() }), let i = list.firstIndex(where: { $0 === f }) else {
            _focus(reverse ? list.last : list.first); return
        }
        _focus(list[(i + (reverse ? list.count - 1 : 1)) % list.count])
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
    public func leave() {
        _focus(nil)
        _saved?.requestFocus()
        onLeave?()
    }

    /// Returns true for a key it used. Called first by the key dispatch (and by
    /// a dialog's own key handler before its Enter and Esc).
    public func handle(_ key: KeyData) -> Bool {
        let l = key.logical
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
            guard let f = focused, !f.modal else { return false }
            move(reverse: l == 0xFF51 || l == 0xFF52); return true
        default:
            if focused != nil, key.character?.isEmpty == false { _focus(nil) }   // typing goes to the editor
            return false
        }
    }

    /// Test hook: forget everything.
    public func reset() {
        focused = nil
        _currentRegion = nil
        _shift = false
        _stops.removeAll()
        if let t = _token { FocusManager.instance.removeKeyInterceptor(t); _token = nil }
        if let e = _pointer { GestureBinding.instance.pointerRouter.removeGlobalRoute(e); _pointer = nil }
    }
}
