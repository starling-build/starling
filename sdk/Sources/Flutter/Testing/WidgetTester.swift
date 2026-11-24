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
        if pd.implicitView == nil {
            pd._addView(0, ViewConfiguration(
                devicePixelRatio: 1.0, size: size,
                viewConstraints: ViewConstraints(minWidth: 0, maxWidth: size.width, minHeight: 0, maxHeight: size.height)))
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

    /// Rebuilds what is dirty, then lays out and paints, until nothing is left dirty.
    public func pump() {
        for _ in 0..<8 {
            buildOwner.buildScopeWithCallback(root!)
            pipelineOwner.flushLayout()
            pipelineOwner.flushCompositingBits()
            pipelineOwner.flushPaint()
            buildOwner.finalizeTree()
        }
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
    public func tap(at position: Offset) {
        let pointer = nextPointer; nextPointer += 1
        let gb = WidgetTester.gestures!
        var hit: HitTestResult?
        for event in [PointerDownEvent(pointer: pointer, position: position) as PointerEvent,
                      PointerUpEvent(pointer: pointer, position: position)] {
            if event is PointerDownEvent {
                hit = HitTestResult()
                _ = renderView.hitTest(hit!, position: position)
            }
            guard let result = hit else { continue }
            for entry in result.path { entry.target.handleEvent(event.transformed(entry.transform), entry: entry) }
            gb.pointerRouter.route(event)
            if event is PointerDownEvent { gb.gestureArena.close(pointer) }
            else { gb.gestureArena.sweep(pointer) }
        }
        pump()
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

    public func has(id: String) -> Bool { centre(where: { ($0.key as? ValueKey<String>)?.value == id }) != nil }

    // MARK: Keys

    public enum Key {
        case enter, escape, tab, backspace
        var logical: Int64 {
            switch self {
            case .enter: return 0x1_0000_000D
            case .escape: return 0x1_0000_001B
            case .tab: return 0x1_0000_0009
            case .backspace: return 0x1_0000_0008
            }
        }
    }

    /// Presses and lifts `key` through the focus manager, as the shell's key handler does. True when a handler used it.
    @discardableResult public func press(_ key: Key) -> Bool {
        var used = false
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
