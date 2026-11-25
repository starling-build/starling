// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import FlutterSwiftBridge

// Draggable and DragTarget, with Flutter's names and shape. A pointer pressed on a Draggable and moved past
// the slop lifts its `feedback` into the nearest Overlay, which follows the pointer; the DragTarget under the
// pointer (one whose `onWillAccept` agrees) takes the data on release. Pointer events stay with the widget
// they went down on, so the Draggable sees every move and the release wherever they happen.

/// A widget the user can drag onto a `DragTarget`.
public class Draggable<T>: StatefulWidget {
    public let child: Widget
    public let feedback: Widget
    public let childWhenDragging: Widget?
    public let data: T?
    public let maxSimultaneousDrags: Int?
    public let onDragStarted: (() -> Void)?
    public let onDragEnd: ((_ accepted: Bool) -> Void)?
    public let onDragCompleted: (() -> Void)?
    public let onDraggableCanceled: (() -> Void)?

    public init(
        key: (any Key)? = nil,
        data: T? = nil,
        child: Widget,
        feedback: Widget,
        childWhenDragging: Widget? = nil,
        maxSimultaneousDrags: Int? = nil,
        onDragStarted: (() -> Void)? = nil,
        onDragEnd: ((_ accepted: Bool) -> Void)? = nil,
        onDragCompleted: (() -> Void)? = nil,
        onDraggableCanceled: (() -> Void)? = nil
    ) {
        self.data = data
        self.child = child
        self.feedback = feedback
        self.childWhenDragging = childWhenDragging
        self.maxSimultaneousDrags = maxSimultaneousDrags
        self.onDragStarted = onDragStarted
        self.onDragEnd = onDragEnd
        self.onDragCompleted = onDragCompleted
        self.onDraggableCanceled = onDraggableCanceled
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> { _DraggableState<T>() }
}

/// How far the pointer must move before a press becomes a drag, in logical pixels.
let kDragSlop: Double = 4

final class _DraggableState<T>: State<StatefulWidget> {
    private var drag: Draggable<T> { widget as! Draggable<T> }
    private var _pointer: Int? = nil
    private var _down = Offset.zero
    private var _origin = Offset.zero
    private var _position = Offset.zero
    private var _dragging = false
    private var _entry: OverlayEntry? = nil
    private var _over: _DragTargetState<T>? = nil

    override func dispose() {
        _finish(cancelled: true)
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let shown: Widget = (_dragging ? drag.childWhenDragging : nil) ?? drag.child
        return Listener(
            onPointerDown: { [weak self] e in self?._pointerDown(e) },
            onPointerMove: { [weak self] e in self?._pointerMove(e) },
            onPointerUp: { [weak self] e in self?._pointerUp(e) },
            onPointerCancel: { [weak self] e in self?._finish(cancelled: true) },
            behavior: .translucent,
            child: shown)
    }

    private func _pointerDown(_ e: PointerDownEvent) {
        guard _pointer == nil else { return }
        _pointer = e.pointer
        _down = e.position
        _position = e.position
        if let box = context?.findRenderObject() as? RenderBox, box.hasSize { _origin = box.localToGlobal(.zero) } else { _origin = e.position }
    }

    private func _pointerMove(_ e: PointerMoveEvent) {
        guard _pointer == e.pointer else { return }
        _position = e.position
        if !_dragging {
            let dx = e.position.dx - _down.dx, dy = e.position.dy - _down.dy
            guard (dx * dx + dy * dy).squareRoot() >= kDragSlop else { return }
            _start()
        }
        _entry?.markNeedsBuild()
        _hover()
    }

    private func _start() {
        guard mounted, let ctx = context, let overlay = Overlay.maybeOf(ctx) else { return }
        _dragging = true
        let entry = OverlayEntry(builder: { [weak self] _ in
            guard let self else { return SizedBox(width: 0, height: 0) }
            return Positioned(left: self._origin.dx + self._position.dx - self._down.dx,
                              top: self._origin.dy + self._position.dy - self._down.dy,
                              child: IgnorePointer(child: self.drag.feedback))
        })
        _entry = entry
        overlay.insert(entry)
        setState {}
        drag.onDragStarted?()
    }

    private func _target(at p: Offset) -> _DragTargetState<T>? {
        for t in _DragTargets.all.reversed() {
            guard let target = t as? _DragTargetState<T>, target.mounted, target.contains(p) else { continue }
            if target.willAccept(drag.data) { return target }
        }
        return nil
    }

    private func _hover() {
        let now = _target(at: _position)
        if now !== _over {
            _over?.leave(drag.data)
            _over = now
            now?.enter(drag.data)
        }
    }

    private func _pointerUp(_ e: PointerUpEvent) {
        guard _pointer == e.pointer else { return }
        _position = e.position
        if _dragging { _hover() }
        _finish(cancelled: false)
    }

    private func _finish(cancelled: Bool) {
        let wasDragging = _dragging
        let target = _over
        _over = nil
        _pointer = nil
        _dragging = false
        _entry?.remove()
        _entry = nil
        guard wasDragging else { return }
        var accepted = false
        if let target, !cancelled {
            target.accept(drag.data)
            accepted = true
        } else {
            target?.leave(drag.data)
        }
        if mounted { setState {} }
        drag.onDragEnd?(accepted)
        if accepted { drag.onDragCompleted?() } else { drag.onDraggableCanceled?() }
    }
}

/// The DragTargets that are on screen, newest last.
enum _DragTargets {
    nonisolated(unsafe) static var all: [AnyObject] = []
}

/// A place a `Draggable`'s data can be dropped.
public class DragTarget<T>: StatefulWidget {
    public typealias Builder = (_ context: any BuildContext, _ candidateData: [T], _ rejectedData: [T]) -> Widget
    public let builder: Builder
    public let onWillAccept: ((T?) -> Bool)?
    public let onAccept: ((T) -> Void)?
    public let onLeave: ((T?) -> Void)?

    public init(
        key: (any Key)? = nil,
        builder: @escaping Builder,
        onWillAccept: ((T?) -> Bool)? = nil,
        onAccept: ((T) -> Void)? = nil,
        onLeave: ((T?) -> Void)? = nil
    ) {
        self.builder = builder
        self.onWillAccept = onWillAccept
        self.onAccept = onAccept
        self.onLeave = onLeave
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> { _DragTargetState<T>() }
}

final class _DragTargetState<T>: State<StatefulWidget> {
    private var target: DragTarget<T> { widget as! DragTarget<T> }
    private var _candidates: [T] = []

    override func initState() {
        super.initState()
        _DragTargets.all.append(self)
    }

    override func dispose() {
        _DragTargets.all.removeAll { $0 === self }
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        target.builder(context, _candidates, [])
    }

    func contains(_ p: Offset) -> Bool {
        guard let box = context?.findRenderObject() as? RenderBox, box.hasSize else { return false }
        let o = box.localToGlobal(.zero), s = box.size
        return p.dx >= o.dx && p.dx < o.dx + s.width && p.dy >= o.dy && p.dy < o.dy + s.height
    }

    func willAccept(_ data: T?) -> Bool { target.onWillAccept?(data) ?? true }

    func enter(_ data: T?) {
        if let data { _candidates = [data] }
        if mounted { setState {} }
    }

    func leave(_ data: T?) {
        _candidates = []
        if mounted { setState {} }
        target.onLeave?(data)
    }

    func accept(_ data: T?) {
        _candidates = []
        if mounted { setState {} }
        if let data { target.onAccept?(data) }
    }
}
