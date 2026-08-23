// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import FlutterSwiftBridge
import Foundation

// MARK: - ParentData

/// Base class for data associated with a RenderObject by its parent.
///
/// Some render objects wish to store data on their children, such as the
/// children's input parameters to the parent's layout algorithm or the
/// children's position relative to other children.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/object.dart`
/// **Original Name:** `ParentData`
/// **Lines:** 57-65
open class ParentData {
    public init() {}

    /// Called when the RenderObject is removed from the tree.
    ///
    /// **Dart Source:** `object.dart:59-61`
    open func detach() {}

    /// A description of this parent data, for use in debug output.
    ///
    /// In Dart this is `toString()`. Renamed to `description` in Swift
    /// to avoid conflict with `CustomStringConvertible`.
    ///
    /// **Dart Source:** `object.dart:63-64`
    open var description: String { "<none>" }
}

// MARK: - Constraints

/// Abstract base for layout constraints.
///
/// Constraints are immutable objects that describe the limits on the geometry
/// that a render object can take. Subclasses define the specific constraints
/// for particular layout protocols (e.g., BoxConstraints).
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/object.dart`
/// **Original Name:** `Constraints`
/// **Lines:** 898-937
public protocol Constraints {
    /// Whether there is exactly one size possible given these constraints.
    ///
    /// **Dart Source:** `object.dart:903-904`
    var isTight: Bool { get }

    /// Whether the constraint is expressed in a consistent manner.
    ///
    /// **Dart Source:** `object.dart:906-907`
    var isNormalized: Bool { get }

    /// Asserts that the constraints are valid.
    ///
    /// This might involve checks more detailed than `isNormalized`.
    ///
    /// If the `isAppliedConstraint` argument is true, then even stricter rules
    /// are enforced. This argument is set to true when checking constraints that
    /// are about to be applied to a RenderObject during layout.
    ///
    /// Returns the same as `isNormalized` if asserts are disabled.
    ///
    /// **Dart Source:** `object.dart:930-936`
    func debugAssertIsValid(isAppliedConstraint: Bool, informationCollector: InformationCollector?) -> Bool
}

/// Default implementations for `Constraints`.
///
/// **Dart Source:** `object.dart:930-936`
extension Constraints {
    public func debugAssertIsValid(isAppliedConstraint: Bool = false, informationCollector: InformationCollector? = nil) -> Bool {
        assert(isNormalized)
        return isNormalized
    }
}

// MARK: - Typedefs

/// Signature for painting into a PaintingContext.
///
/// The `offset` argument is the offset from the origin of the coordinate system
/// of the PaintingContext's canvas to the coordinate system of the callee.
///
/// Used by many of the methods of PaintingContext.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/object.dart`
/// **Original Name:** `PaintingContextCallback`
/// **Line:** 73
public typealias PaintingContextCallback = (_ context: PaintingContext, _ offset: Offset) -> Void

/// Signature for a function that is called for each RenderObject.
///
/// Used by `RenderObject.visitChildren` and `RenderObject.visitChildrenForSemantics`.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/object.dart`
/// **Original Name:** `RenderObjectVisitor`
/// **Line:** 942
public typealias RenderObjectVisitor = (_ child: RenderObject) -> Void

/// Signature for a function that is called during layout.
///
/// Used by `RenderObject.invokeLayoutCallback`.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/object.dart`
/// **Original Name:** `LayoutCallback<T extends Constraints>`
/// **Line:** 947
public typealias LayoutCallback<T: Constraints> = (_ constraints: T) -> Void

/// Signature for the callback to `PipelineOwner.visitChildren`.
///
/// The argument is the child being visited.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/object.dart`
/// **Original Name:** `PipelineOwnerVisitor`
/// **Line:** 1684
public typealias PipelineOwnerVisitor = (_ child: PipelineOwner) -> Void

// MARK: - Stub Forward Declarations

/// A place to paint.
///
/// Rather than holding a canvas directly, a `RenderObject` paints using a
/// painting context. The painting context has a canvas, which receives the
/// individual draw operations, and also has functions for painting child
/// render objects.
///
/// When painting a child render object, the canvas held by the painting context
/// can change because the draw operations issued before and after painting the
/// child might be recorded in separate compositing layers.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/object.dart`
/// **Original Name:** `PaintingContext`
/// **Lines:** 90-849
open class PaintingContext {

    /// Creates a painting context.
    ///
    /// **Dart Source:** `object.dart:96-98`
    public init(_ containerLayer: ContainerLayer, _ estimatedBounds: Rect) {
        _containerLayer = containerLayer
        self.estimatedBounds = estimatedBounds
    }

    /// The container layer into which children are painted.
    ///
    /// **Dart Source:** `object.dart:101`
    private let _containerLayer: ContainerLayer

    /// An estimate of the bounds within which the painting context's canvas
    /// will record painting commands.
    ///
    /// **Dart Source:** `object.dart:109`
    public let estimatedBounds: Rect

    // MARK: - Canvas

    /// The current `PictureLayer` being recorded into.
    private var _currentLayer: PictureLayer?

    /// The current recorder.
    private var _recorder: NativePictureRecorder?

    /// The current canvas, or nil if not recording.
    private var _canvas: (any Canvas)?

    /// The canvas on which to paint.
    ///
    /// The first time a painting context is asked for its canvas, the canvas
    /// is created by calling `_startRecording`.
    ///
    /// **Dart Source:** `object.dart:198-221`
    open var canvas: any Canvas {
        if _canvas == nil {
            _startRecording()
        }
        return _canvas!
    }

    /// Creates a new `PictureLayer`, recorder, and canvas for recording.
    ///
    /// **Dart Source:** `object.dart:222-228`
    private func _startRecording() {
        assert(_currentLayer == nil)
        assert(_recorder == nil)
        assert(_canvas == nil)
        _currentLayer = PictureLayer(estimatedBounds)
        _recorder = NativePictureRecorder()
        _canvas = NativeCanvas(recorder: _recorder!, cullRect: estimatedBounds)
        _containerLayer.append(_currentLayer!)
    }

    /// Stops recording and finalizes the current picture layer.
    ///
    /// **Dart Source:** `object.dart:230-258`
    public func stopRecordingIfNeeded() {
        if _canvas == nil {
            return
        }
        assert(_currentLayer != nil)
        assert(_recorder != nil)
        _currentLayer!.picture = _recorder!.endRecording()
        _currentLayer = nil
        _recorder = nil
        _canvas = nil
    }

    // MARK: - Adding Layers

    /// Adds a composited layer directly to this painting context's layer tree.
    ///
    /// This is used by render objects like `TextureBox` that produce their own
    /// compositing layers rather than painting into a `PictureLayer`.
    ///
    /// **Dart Source:** `object.dart:226-229`
    open func addLayer(_ layer: Layer) {
        stopRecordingIfNeeded()
        _containerLayer.append(layer)
    }

    // MARK: - Painting Children

    /// Paint a child `RenderObject`.
    ///
    /// If the child has its own composited layer, the child will be composited
    /// into the layer subtree associated with this painting context. Otherwise,
    /// the child will be painted into the current PictureLayer for this context.
    ///
    /// **Dart Source:** `object.dart:245-270`
    open func paintChild(_ child: RenderObject, _ offset: Offset) {
        if child.isRepaintBoundary {
            stopRecordingIfNeeded()
            _compositeChild(child, offset)
        } else {
            child.needsPaint = false
            child.paint(self, offset)
        }
    }

    /// Composites a repaint-boundary child into this context's layer tree.
    ///
    /// **Dart Source:** `object.dart:272-290`
    ///
    /// KNOWN GAP: interior repaint boundaries are not implemented, and a child
    /// that declares itself one is not painted in the wrong place — it is not
    /// painted at all.
    ///
    /// Dart gives every boundary its own `OffsetLayer` and carries the parent's
    /// paint offset on it (`childOffsetLayer.offset = offset`, object.dart:290).
    /// This port has no `OffsetLayer`, and `RenderObject._layer` is assigned in
    /// exactly one place: the `RenderView` (`View.swift:391,400`). For every
    /// other boundary `_layer` is nil, so `repaintCompositedChild` returns at
    /// its guard without ever calling `child.paint`, and the `if let childLayer`
    /// below appends nothing. `offset` is ignored here only because, with
    /// nothing painted, there is nothing left to position.
    ///
    /// That is what `TextureBox.isRepaintBoundary` hit: `792f90f` flipped it
    /// true and every texture in the desktop stopped rendering. Caught on
    /// unreleased `main`, before any release carried it. It has to stay false.
    ///
    /// The same holds for every render object here that already returns true —
    /// `RenderViewportBase`, `RenderRepaintBoundary`, `RenderFlow`,
    /// `RenderListWheelViewport`. That has stayed invisible only because nothing
    /// in the shell or the apps builds one: the only scroll view in use is
    /// `SingleChildScrollView`, whose `_RenderSingleChildViewport` is not a
    /// boundary. Reaching for `ListView`, `GridView`, `RepaintBoundary` or
    /// `Flow` will hit it, and the symptom is a blank subtree with no error.
    /// Fixing this means giving interior boundaries real layers; until then,
    /// treat `isRepaintBoundary == true` as unsupported.
    private func _compositeChild(_ child: RenderObject, _ offset: Offset) {
        assert(child.isRepaintBoundary)
        if child.needsPaint {
            PaintingContext.repaintCompositedChild(child)
        }
        if let childLayer = child._layer {
            _containerLayer.append(childLayer)
        }
    }

    // MARK: - Static Repaint

    /// Repaints the given composited child.
    ///
    /// **Dart Source:** `object.dart:115-183`
    public static func repaintCompositedChild(_ child: RenderObject) {
        assert(child.isRepaintBoundary)
        guard let childLayer = child._layer as? ContainerLayer else {
            return
        }
        childLayer.removeAllChildren()
        let childContext = PaintingContext(childLayer, child.paintBounds)
        child.paint(childContext, Offset.zero)
        childContext.stopRecordingIfNeeded()
        child.needsPaint = false
    }

    // MARK: - Push Methods (stubs preserved for API compatibility)

    /// Pushes a clip rect layer and calls the painter callback within it.
    ///
    /// **Dart Source:** `object.dart:567-608`
    open func pushClipRect(
        _ needsCompositing: Bool,
        _ offset: Offset,
        _ clipRect: Rect,
        _ painter: PaintingContextCallback,
        clipBehavior: Clip = .hardEdge,
        oldLayer: ClipRectLayer? = nil
    ) -> ClipRectLayer? {
        if clipBehavior == .none {
            painter(self, offset)
            return nil
        }
        let offsetClipRect = clipRect.shift(offset)
        // Always use compositing layers to ensure correct behavior when
        // descendants call addLayer() (e.g., TextureBox). Canvas-level
        // save/clip is lost when addLayer interrupts the PictureLayer recording.
        let layer = oldLayer ?? ClipRectLayer(clipRect: offsetClipRect, clipBehavior: clipBehavior)
        if layer !== oldLayer {
            // new layer already configured
        } else {
            layer.clipRect = offsetClipRect
            layer.clipBehavior = clipBehavior
        }
        pushLayer(layer, painter, offset, childPaintBounds: offsetClipRect)
        return layer
    }

    /// Pushes a clip rounded rect layer and calls the painter callback within it.
    ///
    /// **Dart Source:** `object.dart:620-661`
    open func pushClipRRect(
        _ needsCompositing: Bool,
        _ offset: Offset,
        _ bounds: Rect,
        _ clipRRect: RRect,
        _ painter: PaintingContextCallback,
        clipBehavior: Clip = .antiAlias,
        oldLayer: ClipRRectLayer? = nil
    ) -> ClipRRectLayer? {
        if clipBehavior == .none {
            painter(self, offset)
            return nil
        }
        let offsetClipRRect = clipRRect.shift(offset)
        // Always use compositing layers (see pushClipRect comment).
        let layer = oldLayer ?? ClipRRectLayer(clipRRect: offsetClipRRect, clipBehavior: clipBehavior)
        if layer !== oldLayer {
            // new layer already configured
        } else {
            layer.clipRRect = offsetClipRRect
            layer.clipBehavior = clipBehavior
        }
        pushLayer(layer, painter, offset, childPaintBounds: offsetClipRRect.outerRect)
        return layer
    }

    /// Pushes a clip path layer and calls the painter callback within it.
    ///
    /// **Dart Source:** `object.dart:673-730`
    open func pushClipPath(
        _ needsCompositing: Bool,
        _ offset: Offset,
        _ bounds: Rect,
        _ clipPath: Path,
        _ painter: PaintingContextCallback,
        clipBehavior: Clip = .antiAlias,
        oldLayer: ClipPathLayer? = nil
    ) -> ClipPathLayer? {
        if clipBehavior == .none {
            painter(self, offset)
            return nil
        }
        let offsetBounds = bounds.shift(offset)
        // Always use compositing layers (see pushClipRect comment).
        let layer = oldLayer ?? ClipPathLayer(clipPath: clipPath.shift(offset), clipBehavior: clipBehavior)
        if layer !== oldLayer {
            // new layer already configured
        } else {
            layer.clipPath = clipPath.shift(offset)
            layer.clipBehavior = clipBehavior
        }
        pushLayer(layer, painter, offset, childPaintBounds: offsetBounds)
        return layer
    }

    /// Pushes a transform layer and calls the painter callback within it.
    ///
    /// **Dart Source:** `object.dart:784-813`
    open func pushTransform(
        _ needsCompositing: Bool,
        _ offset: Offset,
        _ transform: Matrix4,
        _ painter: PaintingContextCallback,
        oldLayer: TransformLayer? = nil
    ) -> TransformLayer? {
        // Always use compositing layers (see pushClipRect comment).
        let effectiveTransform =
            Matrix4.translationValues(offset.dx, offset.dy, 0)
            * transform
            * Matrix4.translationValues(-offset.dx, -offset.dy, 0)
        let layer = oldLayer ?? TransformLayer()
        layer.transform = effectiveTransform
        layer.offset = .zero
        pushLayer(layer, painter, offset)
        return layer
    }

    /// Pushes an opacity layer and calls the painter callback within it.
    ///
    /// **Dart Source:** `object.dart:832-844`
    open func pushOpacity(
        _ offset: Offset,
        _ alpha: Int,
        _ painter: PaintingContextCallback,
        oldLayer: OpacityLayer? = nil
    ) -> OpacityLayer? {
        let layer = oldLayer ?? OpacityLayer(alpha: alpha, offset: offset)
        if layer !== oldLayer {
            // new layer already configured
        } else {
            layer.alpha = alpha
            layer.offset = offset
        }
        pushLayer(layer, painter, offset)
        return layer
    }

    /// Hints that the painting in the current layer is complex and would benefit
    /// from caching.
    ///
    /// **Dart Source:** `object.dart:318-324`
    open func setIsComplexHint() {
        _currentLayer?.isComplexHint = true
    }

    /// Appends the given layer to the recording, and calls the `painter`
    /// callback with that layer, providing the `childPaintBounds` as the
    /// estimated paint bounds of the child.
    ///
    /// **Dart Source:** `object.dart:509-554`
    open func pushLayer(
        _ childLayer: ContainerLayer,
        _ painter: PaintingContextCallback,
        _ offset: Offset,
        childPaintBounds: Rect? = nil
    ) {
        stopRecordingIfNeeded()
        // Remove from old parent if reusing a layer from a previous frame.
        childLayer.remove()
        childLayer.removeAllChildren()
        _containerLayer.append(childLayer)
        let childContext = PaintingContext(childLayer, childPaintBounds ?? estimatedBounds)
        painter(childContext, offset)
        childContext.stopRecordingIfNeeded()
    }
}

/// Manages the rendering pipeline.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/object.dart`
/// **Original Name:** `PipelineOwner`
/// **Lines:** 1015-1683
open class PipelineOwner {
    public init() {}

    /// Render objects that need layout.
    internal var _nodesNeedingLayout: [RenderObject] = []

    /// Render objects that need repainting.
    internal var _nodesNeedingPaint: [RenderObject] = []

    /// Callback invoked when a render object is marked dirty.
    /// Wired to `pd.scheduleFrame()` in Adapter.swift.
    public var onNeedVisualUpdate: (() -> Void)?

    /// Request a visual update (schedules a frame).
    public func requestVisualUpdate() {
        onNeedVisualUpdate?()
    }

    /// Lay out only the dirty nodes (sorted by depth, shallowest first).
    public func flushLayout() {
        while !_nodesNeedingLayout.isEmpty {
            let dirtyNodes = _nodesNeedingLayout.sorted { $0.depth < $1.depth }
            _nodesNeedingLayout = []
            for node in dirtyNodes {
                if node.needsLayout && node.attached {
                    node.layoutWithoutResize()
                }
            }
        }
    }

    /// Repaint only the dirty repaint-boundary nodes.
    public func flushPaint() {
        let dirtyNodes = _nodesNeedingPaint.sorted { $0.depth < $1.depth }
        _nodesNeedingPaint = []
        for node in dirtyNodes {
            if node.needsPaint && node.attached {
                PaintingContext.repaintCompositedChild(node)
            }
        }
    }
}

/// Minimal stub for RenderObject.
///
/// This will be fully implemented in a later subtask (Subtask 5-8).
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/object.dart`
/// **Original Name:** `RenderObject`
/// **Lines:** 1860-4032
open class RenderObject: HitTestTarget {
    public init() {}

    // MARK: - Parent Data

    /// Data for use by the parent render object.
    ///
    /// The parent data is set during the `setupParentData` call, before the
    /// child is added to the parent's child list.
    ///
    /// **Dart Source:** `object.dart:1957`
    public var parentData: ParentData?

    // MARK: - Parent

    /// The parent of this render object in the render tree.
    ///
    /// **Dart Source:** `object.dart:2003`
    public internal(set) weak var parent: RenderObject?

    // MARK: - Adopt / Drop Child

    /// Called when a child render object is added to this parent.
    ///
    /// Sets up parent data, parent reference, and marks this object for layout.
    ///
    /// **Dart Source:** `object.dart:1969-1989`
    public func adoptChild(_ child: RenderObject) {
        setupParentData(child)
        child.parent = self
        markNeedsLayout()
        // A child joined: this node must re-record its painting so the new
        // subtree actually composites. Relayout alone may not dirty paint
        // when sizes are unchanged — observed as remounted window chrome
        // whose fresh render objects painted nowhere while the frame kept
        // compositing the old subtree's retained recording.
        markNeedsPaint()
    }

    /// Marks the compositing bits as needing an update.
    ///
    /// Called when `alwaysNeedsCompositing` may have changed on this node
    /// or a descendant.
    ///
    /// **Dart Source:** `object.dart:3047-3068`
    open func markNeedsCompositingBitsUpdate() {
        markNeedsPaint()
    }

    /// Called when a child render object is removed from this parent.
    ///
    /// Tears down the parent data, clears the parent reference, and marks this
    /// object for layout.
    ///
    /// **Dart Source:** `object.dart:2058-2073`
    public func dropChild(_ child: RenderObject) {
        // Dart detaches and clears the parent data here. Leaving it in place
        // left every dropped child carrying its old parent's slot: a cell
        // pulled out of a RenderTable kept its TableCellParentData, so the
        // next parent's setupParentData saw a non-nil value of the wrong type.
        child.parentData?.detach()
        child.parentData = nil
        child.parent = nil
        markNeedsLayout()
        markNeedsCompositingBitsUpdate()
        // Mirror adoptChild: the departed child's pixels must not linger in
        // this node's retained recording.
        markNeedsPaint()
        // DIFFERENCE FROM DART: `dropChild` also does `if (attached)
        // child.detach()` and `markNeedsSemanticsUpdate()`.
        // REASON: neither has a counterpart to pair with here. `adoptChild`
        // never calls `child.attach`, so detaching on drop would be one half of
        // a lifecycle the port does not otherwise run, and there is no
        // semantics update to schedule. Wiring attach/detach symmetrically is a
        // change to the live compositor, not to this method.
    }

    // MARK: - Depth

    /// The depth of this render object in the render tree.
    ///
    /// The depth is used to ensure that nodes are processed in depth order.
    ///
    /// **Dart Source:** `object.dart:1897`
    public private(set) var depth: Int = 0

    // MARK: - Constraints

    /// The layout constraints most recently supplied by the parent.
    ///
    /// **Dart Source:** `object.dart:2446-2451`
    public var constraints: Constraints {
        guard let c = _constraints else {
            fatalError(
                "A RenderObject does not have any constraints before it has been laid out."
            )
        }
        return c
    }
    internal var _constraints: Constraints?

    // MARK: - Layout Flags

    /// Whether this render object's layout information is dirty.
    ///
    /// **Dart Source:** `object.dart:2509`
    public internal(set) var needsLayout: Bool = true

    /// Whether this render object uses only the constraints to determine its size.
    ///
    /// If true, the render object's size is determined entirely by the
    /// constraints provided by the parent (i.e., it does not depend on
    /// its children or other factors).
    ///
    /// **Dart Source:** `object.dart:2823`
    open var sizedByParent: Bool { false }

    /// Whether this render object repaints separately from its parent.
    ///
    /// If true, the framework automatically creates an `OffsetLayer` for this
    /// render object to paint into, so that when this render object is marked
    /// dirty for paint, only this object (and not its parent) needs to be
    /// repainted.
    ///
    /// Render objects that are expensive to repaint (e.g., texture boxes) or
    /// that repaint frequently should set this to true.
    ///
    /// If the value of this getter changes, `markNeedsCompositingBitsUpdate`
    /// must be called.
    ///
    /// **Dart Source:** `object.dart:2934`
    open var isRepaintBoundary: Bool { false }

    // MARK: - Debug Flags

    /// Whether this render object can use the size computed by its parent.
    ///
    /// **Dart Source:** `object.dart:~2437`
    public var debugCanParentUseSize: Bool = false

    /// Whether this render object's layout information is dirty.
    ///
    /// This is only valid in debug mode; in release mode, use `needsLayout`.
    ///
    /// **Dart Source:** `object.dart:2509-2514`
    public var debugNeedsLayout: Bool { needsLayout }

    // MARK: - Layout Methods

    /// Override to setup parent data correctly for your children.
    ///
    /// **Dart Source:** `object.dart:1963-1968`
    open func setupParentData(_ child: RenderObject) {
        if child.parentData == nil {
            child.parentData = ParentData()
        }
    }

    /// Mark this render object's layout information as dirty.
    ///
    /// Walks up the tree to the root (relayout boundary) and registers it
    /// with the PipelineOwner for layout. Without full relayout-boundary
    /// tracking, only the root is added to `_nodesNeedingLayout`.
    ///
    /// **Dart Source:** `object.dart:2528-2547`
    open func markNeedsLayout() {
        // No early-return when `needsLayout` is already true: a stale dirty
        // ancestor would stop the walk and the root would never reach
        // `_nodesNeedingLayout` — flushLayout then skips the frame and
        // flushPaint can hit brand-new render objects that were never laid
        // out ("does not have any constraints" fatal). Walking to the root
        // every time is conservative: registration is deduplicated below,
        // and clean subtrees are still skipped by `layout()`.
        needsLayout = true
        if parent != nil {
            // Walk up — mark ancestors dirty until we reach the root.
            parent!.markNeedsLayout()
        } else {
            // Root node (relayout boundary): register with PipelineOwner.
            // The visual-update request is UNCONDITIONAL, as upstream's is
            // (object.dart marks, adds, and always requestVisualUpdate()s):
            // gating it on "newly registered" welded a stale registration
            // into a permanent freeze — the root sat in _nodesNeedingLayout
            // from a mark no frame ever followed, every later mark skipped
            // the request, and scroll wheels moved the offset with nothing
            // on screen ever repainting. Duplicate registration is still
            // deduplicated; the frame request is not.
            if let owner = _owner {
                if !owner._nodesNeedingLayout.contains(where: { $0 === self }) {
                    owner._nodesNeedingLayout.append(self)
                }
                owner.requestVisualUpdate()
            }
        }
    }

    /// Mark this render object's layout information as dirty, and then
    /// defer to the parent.
    ///
    /// **Dart Source:** `object.dart:2559-2570`
    public func markParentNeedsLayout() {
        needsLayout = true
        parent?.markNeedsLayout()
    }

    /// Compute the layout for this render object.
    ///
    /// This method is the main entry point for parents to ask this render object
    /// to lay itself out. The parent passes in the `constraints` and (optionally)
    /// indicates whether it will use the child's size via `parentUsesSize`.
    ///
    /// Subclasses should not override this method directly. Instead, override
    /// `performResize` and/or `performLayout`.
    ///
    /// **Dart Source:** `object.dart:2595-2834`
    public func layout(_ constraints: Constraints, parentUsesSize: Bool = false) {
        // Dart asserts every applied constraint here (object.dart:2612).
        // Without this, a tight-infinite constraint — e.g. a stretch
        // cross-axis under an unbounded Row/Column — silently produces an
        // infinite child that paints over everything after it, instead of
        // the "BoxConstraints forces an infinite width/height" diagnostic.
        assert(constraints.debugAssertIsValid(isAppliedConstraint: true))
        // Short-circuit: if this node doesn't need layout and the constraints
        // haven't changed, skip the expensive performLayout() call entirely.
        // This prevents walking clean subtrees during layout.
        if !needsLayout,
           let oldBox = _constraints as? BoxConstraints,
           let newBox = constraints as? BoxConstraints,
           oldBox == newBox {
            return
        }
        _constraints = constraints
        if sizedByParent {
            performResize()
        }
        performLayout()
        needsLayout = false
    }

    /// Called by `PipelineOwner.flushLayout()` on nodes that are dirty
    /// but whose constraints haven't changed (relayout boundaries).
    ///
    /// **Dart Source:** `object.dart:2580-2593`
    internal func layoutWithoutResize() {
        performLayout()
        needsLayout = false
        markNeedsPaint()
    }

    /// Updates the render object's size using only the constraints.
    ///
    /// Called only if `sizedByParent` is true.
    ///
    /// **Dart Source:** `object.dart:2840`
    open func performResize() {
        // Subclasses should override
    }

    /// Do the work of computing the layout for this render object.
    ///
    /// **Dart Source:** `object.dart:2854`
    open func performLayout() {
        // Subclasses should override
    }

    // MARK: - Attached State

    /// Whether this render object is attached to a pipeline owner.
    ///
    /// **Dart Source:** `object.dart:1907-1908`
    public var attached: Bool { _owner != nil }

    /// The pipeline owner for this render object, or nil if detached.
    ///
    /// **Dart Source:** `object.dart:1903`
    internal var _owner: PipelineOwner?

    /// Called when the object is attached to a pipeline owner.
    ///
    /// **Dart Source:** `object.dart:1912-1925`
    open func attach(_ owner: PipelineOwner) {
        _owner = owner
    }

    /// Called when the object is detached from its pipeline owner.
    ///
    /// **Dart Source:** `object.dart:1929-1935`
    open func detach() {
        _owner = nil
    }

    // MARK: - Compositing

    /// Whether this render object always needs compositing.
    ///
    /// Override to return `true` if this render object produces composited
    /// layers (e.g., `TextureBox`, `PlatformView`). When this returns `true`,
    /// ancestor clip/transform/opacity render objects will use composited
    /// layers instead of canvas-level operations.
    ///
    /// **Dart Source:** `object.dart:3027`
    open var alwaysNeedsCompositing: Bool { false }

    /// Whether this render object or any of its descendants need compositing.
    ///
    /// **Dart Source:** `object.dart:3089`
    public var needsCompositing: Bool { isRepaintBoundary || alwaysNeedsCompositing || _needsCompositing }

    /// True if any descendant needs compositing (set during adoptChild propagation).
    ///
    /// **Dart Source:** `object.dart:3084`
    internal var _needsCompositing: Bool = false

    // MARK: - Disposal

    /// Release any resources held by this render object.
    ///
    /// Subclasses should override to release resources and call super.
    ///
    /// **Dart Source:** `object.dart:2099-2131`
    open func dispose() {
        // TODO: Full implementation in a later subtask.
    }

    // MARK: - Layer

    /// The composited layer for this render object.
    ///
    /// Only non-nil for render objects that are repaint boundaries.
    ///
    /// **Dart Source:** `object.dart:3141`
    internal var _layer: ContainerLayer?

    // MARK: - Paint

    /// Whether this render object needs to be repainted.
    ///
    /// **Dart Source:** `object.dart:3234`
    public internal(set) var needsPaint: Bool = true

    /// Mark this render object as needing to be repainted.
    ///
    /// **Dart Source:** `object.dart:3242-3293`
    open func markNeedsPaint() {
        if isRepaintBoundary {
            if let owner = _owner {
                // Attached boundaries dedupe here: a set flag means this
                // boundary is already queued in _nodesNeedingPaint
                // (flushPaint re-checks the flag anyway).
                if needsPaint { return }
                needsPaint = true
                owner._nodesNeedingPaint.append(self)
                owner.requestVisualUpdate()
            } else {
                // Interior boundaries are never attached in this framework
                // (attach() doesn't recurse), so they cannot self-schedule
                // or request a frame. Pass the mark through: the root IS
                // attached — it schedules, repaints, and _compositeChild
                // repaints this dirty boundary on the way down. Without
                // this, a dirty scrollable (Viewport is a boundary)
                // presents stale until unrelated damage forces a frame.
                needsPaint = true
                parent?.markNeedsPaint()
            }
        } else {
            // Deliberately NO early-return on needsPaint for non-boundary
            // nodes. A subtree skipped during a previous paint pass (a
            // clean ancestor composited from its retained layer, offstage
            // or opacity-gated content, …) strands needsPaint == true on
            // intermediate nodes; early-returning would then swallow every
            // later mark from below before it reaches the repaint boundary
            // — freshly recorded paint that never composites. Observed as
            // theme recolors of window chrome staying stale on screen
            // until an unrelated layout change forced a parent repaint.
            // The walk is a cheap parent chase and the boundary above
            // still dedupes actual scheduling.
            needsPaint = true
            parent?.markNeedsPaint()
        }
    }

    /// Paint this render object into the given context at the given offset.
    ///
    /// Subclasses should override this method to provide a visual appearance
    /// for themselves. The render object's local coordinate system is
    /// axis-aligned with the coordinate system of the context's canvas and the
    /// render object's local origin (i.e., x=0 and y=0) is placed at the given
    /// offset in the context's canvas.
    ///
    /// **Dart Source:** `object.dart:3480`
    open func paint(_ context: PaintingContext, _ offset: Offset) {
        // Default: do nothing. Subclasses override.
    }

    /// Returns a rect indicating the area within which this render object will paint.
    ///
    /// Subclasses must override this to describe their paint bounds.
    ///
    /// **Dart Source:** `object.dart:3320`
    open var paintBounds: Rect {
        fatalError("Subclasses of RenderObject must override paintBounds")
    }

    // MARK: - Semantics

    /// Report the semantics of this render object.
    ///
    /// Subclasses with semantic meaning (text, gestures, form controls)
    /// override this to annotate `config`. The full incremental semantics
    /// compiler (`_getSemanticsForParent`) is not ported; the agent
    /// semantics endpoint (Murmuration P3) builds snapshot trees by walking
    /// the element tree and calling this directly.
    ///
    /// **Dart Source:** `object.dart` (describeSemanticsConfiguration)
    open func describeSemanticsConfiguration(_ config: SemanticsConfiguration) {
        // Default: nothing to describe.
    }

    // MARK: - Hit Testing

    /// Override this method to receive events.
    ///
    /// **Dart Source:** `object.dart:3765`
    open func handleEvent(_ event: PointerEvent, entry: HitTestEntry<AnyHitTestTarget>) {
        // Default: do nothing
    }

    // MARK: - Transforms

    /// Applies the paint transform to the child.
    ///
    /// Used by coordinate conversion functions to translate coordinates local
    /// to a child to coordinates local to this render object.
    ///
    /// **Dart Source:** `object.dart:3356`
    open func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        assert(child.parent === self)
    }

    /// Returns the transform that maps from local coordinates of this render
    /// object to the coordinate system of `ancestor`.
    ///
    /// If `ancestor` is nil, this method returns a matrix that maps from
    /// local coordinates to the global coordinate system.
    ///
    /// **Dart Source:** `object.dart:3403-3426`
    public func getTransformTo(_ ancestor: RenderObject?) -> Matrix4 {
        // Collect the chain of render objects from this to ancestor.
        // Walk up, accumulating transforms.
        var renderers: [RenderObject] = []
        var renderer: RenderObject? = self
        while renderer !== ancestor {
            renderers.append(renderer!)
            renderer = renderer?.parent
        }
        if ancestor != nil {
            renderers.append(ancestor!)
        }

        var transform = Matrix4.identity()
        var i = renderers.count - 1
        while i > 0 {
            renderers[i].applyPaintTransform(renderers[i - 1], &transform)
            i -= 1
        }
        return transform
    }
}

// MARK: - DiagnosticsDebugCreator

/// A class that creates DiagnosticsNode by wrapping `RenderObject.debugCreator`.
///
/// Attach a `DiagnosticsDebugCreator` into `FlutterErrorDetails.informationCollector`
/// when a `RenderObject.debugCreator` is available. This will lead to improved
/// error messages.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/object.dart`
/// **Original Name:** `DiagnosticsDebugCreator`
/// **Lines:** 6531-6536
public class DiagnosticsDebugCreator: DiagnosticsProperty<AnyObject> {
    /// Create a DiagnosticsProperty with its value initialized to input
    /// `RenderObject.debugCreator`.
    ///
    /// **Dart Source:** `object.dart:6534-6535`
    public init(_ value: AnyObject) {
        super.init("debugCreator", value, level: .hidden)
    }
}
