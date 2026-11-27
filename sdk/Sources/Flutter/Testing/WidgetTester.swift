// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A headless widget driver for unit tests: builds a widget tree in a fixed-size view with no
// engine and no window, lays it out, finds a control by its label and taps it through the same
// hit test and gesture arena the app's pointer handler uses. Runs wherever the framework builds
// (Linux, macOS). No frames are scheduled: call `pump()` after anything that changes the tree.

import FlutterSwiftBridge

public final class WidgetTester {
    public let buildOwner = BuildOwner()
    public let pipelineOwner = PipelineOwner()
    public let renderView: RenderView
    public let size: Size
    private var root: RenderObjectToWidgetElement?
    private var nextPointer = 1
    nonisolated(unsafe) private static var gestures: GestureBinding?

    public init(_ widget: Widget, size: Size = Size(1280, 800)) {
        self.size = size
        let pd = PlatformDispatcher.instance
        let configuration = ViewConfiguration(
            devicePixelRatio: 1.0, size: size,
            viewConstraints: ViewConstraints(minWidth: 0, maxWidth: size.width, minHeight: 0, maxHeight: size.height))
        if pd.implicitView == nil {
            pd._addView(0, configuration)
        } else if pd.implicitView!.physicalSize != size {
            // The view outlives a tester: a later tester that asks for another size gets it, not the first one's.
            pd._updateWindowMetrics(0, configuration)
        }
        let view = pd.implicitView!
        if WidgetTester.gestures == nil { WidgetTester.gestures = GestureBinding() }
        WidgetsBinding.instance.buildOwner = buildOwner
        renderView = RenderView(view: view)
        renderView.configuration = RenderViewConfiguration.fromView(view)
        renderView.attach(pipelineOwner)
        renderView.prepareInitialFrame()
        root = RenderObjectToWidgetAdapter(child: widget, container: renderView).attachToRenderTree(buildOwner)
        pump()
    }

    /// A tester that goes out of scope unmounts its tree, so the key hooks and
    /// timers of what it showed do not outlive the test and eat a later test's keys.
    deinit { dispose() }

    /// Unmounts the whole tree (runs every `dispose`).
    public func dispose() {
        guard root != nil else { return }
        replace(with: SizedBox(width: 0, height: 0, child: nil))
    }

    /// Rebuilds what is dirty, then lays out and paints, until nothing is left dirty.
    public func pump() {
        for _ in 0..<8 {
            buildOwner.buildScopeWithCallback(root!)
            pipelineOwner.flushLayout()
            pipelineOwner.flushCompositingBits()
            pipelineOwner.flushPaint()
            buildOwner.finalizeTree()
            // As a real frame ends: post-frame callbacks run (a widget that learns its size after layout, such as the
            // slide canvas, only mounts its shapes once one has run).
            for callback in FrameCallbackScheduler.shared.takePostFrameCallbacks() { callback(.zero) }
        }
    }

    /// Swaps the whole tree for `widget` (what a dialog closing looks like from above).
    public func replace(with widget: Widget) {
        root = RenderObjectToWidgetAdapter(child: widget, container: renderView).attachToRenderTree(buildOwner, root)
        pump()
    }

    /// Every element of the tree, parents first.
    public func elements() -> [Element] {
        var all: [Element] = []
        func walk(_ e: Element) { all.append(e); e.visitChildElements(walk) }
        if let root { walk(root) }
        return all
    }

    /// The centre, in view coordinates, of the first widget whose text is exactly `label`
    /// (a Text, or a control whose label is one). Nil when there is none.
    public func centre(ofText label: String) -> Offset? {
        for e in elements() {
            guard let t = e.widget as? Text, t.data == label,
                  let box = e.findRenderObject() as? RenderBox, box.hasSize else { continue }
            let p = box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2))
            return p
        }
        return nil
    }

    /// Every non-empty text on screen, in tree order.
    public func texts() -> [String] { elements().compactMap { ($0.widget as? Text)?.data }.filter { !$0.isEmpty } }

    /// The state object of the first stateful widget of type `W`: how a test reads the model.
    public func state<S: AnyObject>(_ type: S.Type) -> S? {
        for e in elements() { if let st = (e as? StatefulElement)?.state as? S { return st } }
        return nil
    }

    /// Whether any Text shows `label`.
    public func has(text label: String) -> Bool { centre(ofText: label) != nil }

    /// Presses and lifts a pointer at `position`, as the app's pointer handler does.
    public func tap(at position: Offset, buttons: Int = kPrimaryButton, modifiers: KeyModifiers = [],
                    kind: PointerDeviceKind = .touch) {
        drag(from: position, to: position, steps: 0, buttons: buttons, modifiers: modifiers, kind: kind)
    }

    /// A click: the same as `tap(at:)`, named for what a mouse does.
    public func click(at position: Offset, buttons: Int = kPrimaryButton, modifiers: KeyModifiers = [],
                      kind: PointerDeviceKind = .touch) {
        tap(at: position, buttons: buttons, modifiers: modifiers, kind: kind)
    }

    /// Two clicks in a row at `position`.
    public func doubleClick(at position: Offset, modifiers: KeyModifiers = []) {
        tap(at: position, modifiers: modifiers)
        tap(at: position, modifiers: modifiers)
    }

    /// Presses at `from`, moves to `to` in `steps` equal moves, and lifts there. The events go through
    /// hit testing, the gesture arena and the pointer router, as the shell's real pointer events do.
    /// `modifiers` are held (as key events through the focus manager) from before the press until after the lift.
    /// `whileHeld` runs between the press and the first move: a test lets time pass there (a long press).
    public func drag(from: Offset, to: Offset, steps: Int = 8, buttons: Int = kPrimaryButton,
                     modifiers: KeyModifiers = [], kind: PointerDeviceKind = .touch, whileHeld: (() -> Void)? = nil) {
        let held = WidgetTester.modifierKeys.filter { modifiers.contains($0.0) }
        for (_, logical) in held { _modifier(logical, down: true) }
        let pointer = nextPointer; nextPointer += 1
        let gb = WidgetTester.gestures!
        var hit: HitTestResult?
        func send(_ event: PointerEvent) {
            if event is PointerDownEvent {
                hit = HitTestResult()
                _ = renderView.hitTest(hit!, position: event.position)
            }
            guard let result = hit else { return }
            for entry in result.path { entry.target.handleEvent(event.transformed(entry.transform), entry: entry) }
            gb.pointerRouter.route(event)
            if event is PointerDownEvent { gb.gestureArena.close(pointer) }
            else if event is PointerUpEvent { gb.gestureArena.sweep(pointer) }
        }
        send(PointerDownEvent(pointer: pointer, kind: kind, position: from, buttons: buttons))
        whileHeld?()
        var last = from
        if steps > 0 {
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                let p = Offset(from.dx + (to.dx - from.dx) * t, from.dy + (to.dy - from.dy) * t)
                send(PointerMoveEvent(pointer: pointer, kind: kind, position: p, delta: p - last, buttons: buttons))
                last = p
            }
        }
        send(PointerUpEvent(pointer: pointer, kind: kind, position: to))
        for (_, logical) in held.reversed() { _modifier(logical, down: false) }
        pump()
    }

    /// Turns a mouse wheel over `position` by `delta` (negative dy rolls it away from the user), with `modifiers`
    /// held as key events from before until after. It goes through hit testing to every target under the pointer
    /// and then the signal resolver, as the shell's real wheel events do.
    public func scroll(at position: Offset, delta: Offset, modifiers: KeyModifiers = []) {
        let held = WidgetTester.modifierKeys.filter { modifiers.contains($0.0) }
        for (_, logical) in held { _modifier(logical, down: true) }
        let event = PointerScrollEvent(kind: .mouse, position: position, scrollDelta: delta)
        let hit = HitTestResult()
        _ = renderView.hitTest(hit, position: position)
        for entry in hit.path { entry.target.handleEvent(event.transformed(entry.transform), entry: entry) }
        WidgetTester.gestures!.pointerSignalResolver.resolve(event: event)
        for (_, logical) in held.reversed() { _modifier(logical, down: false) }
        pump()
    }

    private static let modifierKeys: [(KeyModifiers, Int64)] =
        [(.shift, 0xFFE1), (.control, 0xFFE3), (.alt, 0xFFE9), (.meta, 0xFFE7)]

    private func _modifier(_ logical: Int64, down: Bool) {
        _ = FocusManager.instance.dispatchKeyData(
            KeyData(timeStamp: 0, type: down ? .down : .up, physical: 0, logical: logical, character: nil, synthesized: false))
    }

    /// Taps the first control labelled `label`. Returns false when no such label is on screen.
    @discardableResult public func tap(text label: String) -> Bool {
        guard let c = centre(ofText: label) else { return false }
        tap(at: c)
        return true
    }

    // MARK: Icon-only controls

    /// The centre of the first element whose widget satisfies `match`.
    private func centre(where match: (Widget) -> Bool) -> Offset? {
        for e in elements() where match(e.widget) {
            guard let box = e.findRenderObject() as? RenderBox, box.hasSize else { continue }
            return box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2))
        }
        return nil
    }

    /// What assistive technology would be told: one node per annotated widget, Merge and Exclude applied.
    public func semantics() -> [SemanticsSnapshotNode] {
        guard let root = elements().first else { return [] }
        return SemanticsSnapshot.build(from: root)
    }

    /// Every tooltip message on screen, in tree order: the names of icon-only buttons.
    public func tips() -> [String] { elements().compactMap { ($0.widget as? Tooltip)?.message } }

    public func has(tip: String) -> Bool { centre(where: { ($0 as? Tooltip)?.message == tip }) != nil }

    /// Taps the control whose tooltip is `tip` (an icon-only button has no label).
    @discardableResult public func tap(tip: String) -> Bool {
        guard let c = centre(where: { ($0 as? Tooltip)?.message == tip }) else { return false }
        tap(at: c)
        return true
    }

    /// Taps the widget keyed `ValueKey(id)`: an identifier a control carries for tests.
    @discardableResult public func tap(id: String) -> Bool {
        guard let c = centre(where: { ($0.key as? ValueKey<String>)?.value == id }) else { return false }
        tap(at: c)
        return true
    }

    /// Where the widget keyed `ValueKey(id)` sits (its centre), or nil.
    public func centre(id: String) -> Offset? { centre(where: { ($0.key as? ValueKey<String>)?.value == id }) }

    public func has(id: String) -> Bool { centre(where: { ($0.key as? ValueKey<String>)?.value == id }) != nil }

    // MARK: Keys

    public enum Key {
        case enter, escape, tab, backspace, f6, space, alt, left, right, up, down
        var logical: Int64 {
            switch self {
            case .enter: return 0x1_0000_000D
            case .escape: return 0x1_0000_001B
            case .tab: return 0x1_0000_0009
            case .backspace: return 0x1_0000_0008
            case .f6: return 0xFFBD
            case .space: return 0x1_0000_0020
            case .alt: return 0xFFE9
            case .left: return 0xFF51
            case .up: return 0xFF52
            case .right: return 0xFF53
            case .down: return 0xFF54
            }
        }
    }

    /// Presses and lifts `key` through the focus manager, as the shell's key handler does. True when a handler used it.
    @discardableResult public func press(_ key: Key, shift: Bool = false) -> Bool {
        var used = false
        if shift { _ = FocusManager.instance.dispatchKeyData(KeyData(timeStamp: 0, type: .down, physical: 0, logical: 0xFFE1, character: nil, synthesized: false)) }
        defer { if shift { _ = FocusManager.instance.dispatchKeyData(KeyData(timeStamp: 0, type: .up, physical: 0, logical: 0xFFE1, character: nil, synthesized: false)) } }
        for type in [KeyEventType.down, .up] {
            let data = KeyData(timeStamp: 0, type: type, physical: 0, logical: key.logical, character: nil, synthesized: false)
            if FocusManager.instance.dispatchKeyData(data) { used = true }
        }
        pump()
        return used
    }

    /// Types `text` into the focused field, one character at a time (tap the field first).
    public func type(_ text: String) {
        for ch in text {
            let s = String(ch)
            let down = KeyData(timeStamp: 0, type: .down, physical: 0, logical: Int64(ch.unicodeScalars.first!.value), character: s, synthesized: false)
            _ = FocusManager.instance.dispatchKeyData(down)
            _ = FocusManager.instance.dispatchKeyData(KeyData(timeStamp: 0, type: .up, physical: 0, logical: down.logical, character: nil, synthesized: false))
        }
        pump()
    }
}
