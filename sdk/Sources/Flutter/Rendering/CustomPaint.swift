// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Custom painting render objects that delegate painting to a `CustomPainter`.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/custom_paint.dart`

import FlutterSwiftBridge

// MARK: - SemanticsBuilderCallback

/// Signature of the function returned by `CustomPainter.semanticsBuilder`.
///
/// Builds semantics information describing the picture drawn by a
/// `CustomPainter`. Each `CustomPainterSemantics` in the returned list is
/// converted into a `SemanticsNode` by copying its properties.
///
/// The returned list must not be mutated after this function completes. To
/// change the semantic information, the function must return a new list
/// instead.
///
/// **Dart Source:** custom_paint.dart:26
public typealias SemanticsBuilderCallback = (Size) -> [CustomPainterSemantics]

// MARK: - CustomPainter

/// The interface used by `CustomPaint` (in the widgets library) and
/// `RenderCustomPaint` (in the rendering library).
///
/// To implement a custom painter, either subclass or implement this interface
/// to define your custom paint delegate. `CustomPainter` subclasses must
/// implement the `paint` and `shouldRepaint` methods, and may optionally also
/// implement the `hitTest` and `shouldRebuildSemantics` methods, and the
/// `semanticsBuilder` getter.
///
/// The `paint` method is called whenever the custom object needs to be
/// repainted.
///
/// The `shouldRepaint` method is called when a new instance of the class
/// is provided, to check if the new instance actually represents different
/// information.
///
/// **Dart Source:** custom_paint.dart:149-290
open class CustomPainter: Listenable {

    /// Creates a custom painter.
    ///
    /// The painter will repaint whenever `repaint` notifies its listeners.
    ///
    /// **Dart Source:** custom_paint.dart:153
    public init(repaint: (any Listenable)? = nil) {
        self._repaint = repaint
    }

    /// The listenable that triggers repaints.
    private let _repaint: (any Listenable)?

    /// Register a closure to be notified when it is time to repaint.
    ///
    /// The `CustomPainter` implementation merely forwards to the same method on
    /// the `Listenable` provided to the constructor in the `repaint` argument, if
    /// it was not null.
    ///
    /// **Dart Source:** custom_paint.dart:163
    public func addListener(_ listener: @escaping VoidCallback) {
        _repaint?.addListener(listener)
    }

    /// Remove a previously registered closure from the list of closures that the
    /// object notifies when it is time to repaint.
    ///
    /// The `CustomPainter` implementation merely forwards to the same method on
    /// the `Listenable` provided to the constructor in the `repaint` argument, if
    /// it was not null.
    ///
    /// **Dart Source:** custom_paint.dart:172
    public func removeListener(_ listener: @escaping VoidCallback) {
        _repaint?.removeListener(listener)
    }

    public func addListener(_ listener: @escaping VoidCallback, owner: AnyObject) {
        _repaint?.addListener(listener, owner: owner)
    }

    public func removeListeners(owner: AnyObject) {
        _repaint?.removeListeners(owner: owner)
    }

    /// Called whenever the object needs to paint. The given `Canvas` has its
    /// coordinate space configured such that the origin is at the top left of the
    /// box. The area of the box is the size of the `size` argument.
    ///
    /// Paint operations should remain inside the given area. Graphical
    /// operations outside the bounds may be silently ignored, clipped, or not
    /// clipped.
    ///
    /// Implementations should be wary of correctly pairing any calls to
    /// `Canvas.save`/`Canvas.saveLayer` and `Canvas.restore`, otherwise all
    /// subsequent painting on this canvas may be affected.
    ///
    /// **Dart Source:** custom_paint.dart:206
    open func paint(_ canvas: any Canvas, _ size: Size) {
        fatalError("Subclasses must override paint")
    }

    /// Returns a function that builds semantic information for the picture drawn
    /// by this painter.
    ///
    /// If the returned function is nil, this painter will not contribute new
    /// `SemanticsNode`s to the semantics tree and the `CustomPaint` corresponding
    /// to this painter will not create a semantics boundary.
    ///
    /// **Dart Source:** custom_paint.dart:222
    open var semanticsBuilder: SemanticsBuilderCallback? { nil }

    /// Called whenever a new instance of the custom painter delegate class is
    /// provided to the `RenderCustomPaint` object, or any time that a new
    /// `CustomPaint` object is created with a new instance of the custom painter
    /// delegate class.
    ///
    /// If the new instance would cause `semanticsBuilder` to create different
    /// semantics information, then this method should return true, otherwise it
    /// should return false.
    ///
    /// By default this method delegates to `shouldRepaint` under the assumption
    /// that in most cases semantics change when something new is drawn.
    ///
    /// **Dart Source:** custom_paint.dart:244
    open func shouldRebuildSemantics(_ oldDelegate: CustomPainter) -> Bool {
        return shouldRepaint(oldDelegate)
    }

    /// Called whenever a new instance of the custom painter delegate class is
    /// provided to the `RenderCustomPaint` object, or any time that a new
    /// `CustomPaint` object is created with a new instance of the custom painter
    /// delegate class.
    ///
    /// If the new instance represents different information than the old
    /// instance, then the method should return true, otherwise it should return
    /// false.
    ///
    /// If the method returns false, then the `paint` call might be optimized
    /// away.
    ///
    /// **Dart Source:** custom_paint.dart:271
    open func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        fatalError("Subclasses must override shouldRepaint")
    }

    /// Called whenever a hit test is being performed on an object that is using
    /// this custom paint delegate.
    ///
    /// The given point is relative to the same coordinate space as the last
    /// `paint` call.
    ///
    /// The default behavior is to consider all points to be hits for
    /// background painters, and no points to be hits for foreground painters.
    ///
    /// Return true if the given position corresponds to a point on the drawn
    /// image that should be considered a "hit", false if it corresponds to a
    /// point that should be considered outside the painted image, and nil to use
    /// the default behavior.
    ///
    /// **Dart Source:** custom_paint.dart:286
    open func hitTest(_ position: Offset) -> Bool? { nil }

    /// **Dart Source:** custom_paint.dart:289
    public var description: String {
        return "\(describeIdentity(self))(\(_repaint.map { "\($0)" } ?? ""))"
    }
}

// MARK: - CustomPainterSemantics

/// Contains properties describing information drawn in a rectangle contained by
/// the `Canvas` used by a `CustomPaint`.
///
/// This information is used, for example, by assistive technologies to improve
/// the accessibility of applications.
///
/// Implement `CustomPainter.semanticsBuilder` to build the semantic
/// description of the whole picture drawn by a `CustomPaint`, rather than one
/// particular rectangle.
///
/// **Dart Source:** custom_paint.dart:307-355
public struct CustomPainterSemantics {

    /// Creates semantics information describing a rectangle on a canvas.
    ///
    /// **Dart Source:** custom_paint.dart:309-315
    public init(
        key: (any Key)? = nil,
        rect: Rect,
        properties: SemanticsProperties,
        transform: Matrix4? = nil,
        tags: Set<SemanticsTag>? = nil
    ) {
        self.key = key
        self.rect = rect
        self.properties = properties
        self.transform = transform
        self.tags = tags
    }

    /// Identifies this object in a list of siblings.
    ///
    /// `SemanticsNode` inherits this key, so that when the list of nodes is
    /// updated, its nodes are updated from `CustomPainterSemantics` with matching
    /// keys.
    ///
    /// If this is nil, the update algorithm does not guarantee which
    /// `SemanticsNode` will be updated using this instance.
    ///
    /// This value is assigned to `SemanticsNode.key` during update.
    ///
    /// **Dart Source:** custom_paint.dart:327
    public let key: (any Key)?

    /// The location and size of the box on the canvas where this piece of semantic
    /// information applies.
    ///
    /// This value is assigned to `SemanticsNode.rect` during update.
    ///
    /// **Dart Source:** custom_paint.dart:333
    public let rect: Rect

    /// The transform from the canvas' coordinate system to its parent's
    /// coordinate system.
    ///
    /// This value is assigned to `SemanticsNode.transform` during update.
    ///
    /// **Dart Source:** custom_paint.dart:339
    public let transform: Matrix4?

    /// Contains properties that are assigned to the `SemanticsNode` created or
    /// updated from this object.
    ///
    /// **Dart Source:** custom_paint.dart:348
    public let properties: SemanticsProperties

    /// Tags used by the parent `SemanticsNode` to determine the layout of the
    /// semantics tree.
    ///
    /// This value is assigned to `SemanticsNode.tags` during update.
    ///
    /// **Dart Source:** custom_paint.dart:354
    public let tags: Set<SemanticsTag>?
}

// MARK: - RenderCustomPaint

/// Provides a canvas on which to draw during the paint phase.
///
/// When asked to paint, `RenderCustomPaint` first asks its `painter` to paint
/// on the current canvas, then it paints its child, and then, after painting
/// its child, it asks its `foregroundPainter` to paint. The coordinate system of
/// the canvas matches the coordinate system of the `CustomPaint` object. The
/// painters are expected to paint within a rectangle starting at the origin and
/// encompassing a region of the given size.
///
/// Painters are implemented by subclassing or implementing `CustomPainter`.
///
/// Because custom paint calls its painters during paint, you cannot mark the
/// tree as needing a new layout during the callback (the layout for this frame
/// has already happened).
///
/// Custom painters normally size themselves to their child. If they do not have
/// a child, they attempt to size themselves to the `preferredSize`, which
/// defaults to `Size.zero`.
///
/// **Dart Source:** custom_paint.dart:382-1146
open class RenderCustomPaint: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a render object that delegates its painting.
    ///
    /// **Dart Source:** custom_paint.dart:384-394
    public init(
        painter: CustomPainter? = nil,
        foregroundPainter: CustomPainter? = nil,
        preferredSize: Size = .zero,
        isComplex: Bool = false,
        willChange: Bool = false,
        child: RenderBox? = nil
    ) {
        self._painter = painter
        self._foregroundPainter = foregroundPainter
        self._preferredSize = preferredSize
        self.isComplex = isComplex
        self.willChange = willChange
        super.init(child: child)
    }

    // MARK: - Painter Properties

    /// The background custom paint delegate.
    ///
    /// This painter, if non-nil, is called to paint behind the children.
    ///
    /// **Dart Source:** custom_paint.dart:399
    public var painter: CustomPainter? {
        get { _painter }
        set {
            if _painter === newValue {
                return
            }
            let oldPainter = _painter
            _painter = newValue
            _didUpdatePainter(_painter, oldPainter)
        }
    }
    private var _painter: CustomPainter?

    /// The foreground custom paint delegate.
    ///
    /// This painter, if non-nil, is called to paint in front of the children.
    ///
    /// **Dart Source:** custom_paint.dart:426
    public var foregroundPainter: CustomPainter? {
        get { _foregroundPainter }
        set {
            if _foregroundPainter === newValue {
                return
            }
            let oldPainter = _foregroundPainter
            _foregroundPainter = newValue
            _didUpdatePainter(_foregroundPainter, oldPainter)
        }
    }
    private var _foregroundPainter: CustomPainter?

    /// Handles updating listeners and marking dirty state when a painter changes.
    ///
    /// **Dart Source:** custom_paint.dart:450-476
    private func _didUpdatePainter(_ newPainter: CustomPainter?, _ oldPainter: CustomPainter?) {
        // Check if we need to repaint.
        if newPainter == nil {
            assert(oldPainter != nil) // We should be called only for changes.
            markNeedsPaint()
        } else if oldPainter == nil
            || type(of: newPainter!) != type(of: oldPainter!)
            || newPainter!.shouldRepaint(oldPainter!) {
            markNeedsPaint()
        }
        if attached {
            oldPainter?.removeListeners(owner: self)
            newPainter?.addListener(_onRepaint, owner: self)
        }

        // Check if we need to rebuild semantics.
        if newPainter == nil {
            assert(oldPainter != nil) // We should be called only for changes.
            if attached {
                // TODO: Call markNeedsSemanticsUpdate() once semantics is available.
            }
        } else if oldPainter == nil
            || type(of: newPainter!) != type(of: oldPainter!)
            || newPainter!.shouldRebuildSemantics(oldPainter!) {
            // TODO: Call markNeedsSemanticsUpdate() once semantics is available.
        }
    }

    /// The size that this `RenderCustomPaint` should aim for, given the layout
    /// constraints, if there is no child.
    ///
    /// Defaults to `Size.zero`.
    ///
    /// If there's a child, this is ignored, and the size of the child is used
    /// instead.
    ///
    /// **Dart Source:** custom_paint.dart:485
    public var preferredSize: Size {
        get { _preferredSize }
        set {
            if _preferredSize == newValue {
                return
            }
            _preferredSize = newValue
            markNeedsLayout()
        }
    }
    private var _preferredSize: Size

    /// Whether to hint that this layer's painting should be cached.
    ///
    /// The compositor contains a raster cache that holds bitmaps of layers in
    /// order to avoid the cost of repeatedly rendering those layers on each
    /// frame. If this flag is not set, then the compositor will apply its own
    /// heuristics to decide whether the layer containing this render object is
    /// complex enough to benefit from caching.
    ///
    /// **Dart Source:** custom_paint.dart:502
    public var isComplex: Bool

    /// Whether the raster cache should be told that this painting is likely
    /// to change in the next frame.
    ///
    /// This hint tells the compositor not to cache the layer containing this
    /// render object because the cache will not be used in the future. If this
    /// hint is not set, the compositor will apply its own heuristics to decide
    /// whether this layer is likely to be reused in the future.
    ///
    /// **Dart Source:** custom_paint.dart:511
    public var willChange: Bool

    // MARK: - Intrinsic Dimensions

    /// Computes the minimum intrinsic width.
    ///
    /// If there is no child, returns the preferred size width if finite, otherwise 0.
    ///
    /// **Dart Source:** custom_paint.dart:514-518
    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        if child == nil {
            return _preferredSize.width.isFinite ? _preferredSize.width : 0
        }
        return super.computeMinIntrinsicWidth(height)
    }

    /// Computes the maximum intrinsic width.
    ///
    /// If there is no child, returns the preferred size width if finite, otherwise 0.
    ///
    /// **Dart Source:** custom_paint.dart:521-525
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        if child == nil {
            return _preferredSize.width.isFinite ? _preferredSize.width : 0
        }
        return super.computeMaxIntrinsicWidth(height)
    }

    /// Computes the minimum intrinsic height.
    ///
    /// If there is no child, returns the preferred size height if finite, otherwise 0.
    ///
    /// **Dart Source:** custom_paint.dart:529-533
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        if child == nil {
            return _preferredSize.height.isFinite ? _preferredSize.height : 0
        }
        return super.computeMinIntrinsicHeight(width)
    }

    /// Computes the maximum intrinsic height.
    ///
    /// If there is no child, returns the preferred size height if finite, otherwise 0.
    ///
    /// **Dart Source:** custom_paint.dart:537-541
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        if child == nil {
            return _preferredSize.height.isFinite ? _preferredSize.height : 0
        }
        return super.computeMaxIntrinsicHeight(width)
    }

    // MARK: - Attach / Detach

    /// Called when the object is attached to a pipeline owner.
    ///
    /// Adds paint listeners to both painters.
    ///
    /// **Dart Source:** custom_paint.dart:546-549
    public override func attach(_ owner: PipelineOwner) {
        super.attach(owner)
        _painter?.addListener(_onRepaint, owner: self)
        _foregroundPainter?.addListener(_onRepaint, owner: self)
    }

    private lazy var _onRepaint: VoidCallback = { [weak self] in self?.markNeedsPaint() }

    /// Called when the object is detached from its pipeline owner.
    ///
    /// Removes paint listeners from both painters.
    ///
    /// **Dart Source:** custom_paint.dart:553-556
    public override func detach() {
        _painter?.removeListeners(owner: self)
        _foregroundPainter?.removeListeners(owner: self)
        super.detach()
    }

    // MARK: - Hit Testing

    /// Hit tests the children at the given position.
    ///
    /// If the foreground painter handles the hit, returns true immediately.
    /// Otherwise delegates to the super implementation.
    ///
    /// **Dart Source:** custom_paint.dart:560-564
    open override func hitTestChildren(
        _ result: BoxHitTestResult,
        position: Offset
    ) -> Bool {
        if _foregroundPainter != nil && (_foregroundPainter!.hitTest(position) ?? false) {
            return true
        }
        return super.hitTestChildren(result, position: position)
    }

    /// Hit tests this render object itself at the given position.
    ///
    /// Returns true if the background painter handles the hit (defaulting to
    /// true if the painter exists but returns nil).
    ///
    /// **Dart Source:** custom_paint.dart:568-569
    open override func hitTestSelf(_ position: Offset) -> Bool {
        return _painter != nil && (_painter!.hitTest(position) ?? true)
    }

    // MARK: - Layout

    /// Performs layout and marks semantics as needing update.
    ///
    /// **Dart Source:** custom_paint.dart:573-575
    open override func performLayout() {
        super.performLayout()
        // TODO: Call markNeedsSemanticsUpdate() once semantics is available.
    }

    /// Calculates the size this `RenderCustomPaint` would have under the given
    /// `BoxConstraints` when it does not have a child.
    ///
    /// Returns the preferred size constrained by the given constraints.
    ///
    /// **Dart Source:** custom_paint.dart:579-581
    open override func computeSizeForNoChild(_ constraints: BoxConstraints) -> Size {
        return constraints.constrain(_preferredSize)
    }

    // MARK: - Painting

    /// Paints the custom painter's content on the canvas, wrapped in save/restore.
    ///
    /// In debug mode, asserts that the canvas save count is balanced after the
    /// painter finishes painting.
    ///
    /// **Dart Source:** custom_paint.dart:583-636
    private func _paintWithPainter(_ canvas: any Canvas, _ offset: Offset, _ painter: CustomPainter) {
        var debugPreviousCanvasSaveCount = 0
        canvas.save()
        assert({
            debugPreviousCanvasSaveCount = canvas.getSaveCount()
            return true
        }())
        if offset != Offset.zero {
            canvas.translate(offset.dx, offset.dy)
        }
        painter.paint(canvas, size)
        assert({
            // This isn't perfect. For example, we can't catch the case of
            // someone first restoring, then setting a transform or whatnot,
            // then saving.
            // If this becomes a real problem, we could add logic to the
            // Canvas class to lock the canvas at a particular save count
            // such that restore() fails if it would take the lock count
            // below that number.
            let debugNewCanvasSaveCount = canvas.getSaveCount()
            if debugNewCanvasSaveCount > debugPreviousCanvasSaveCount {
                let diff = debugNewCanvasSaveCount - debugPreviousCanvasSaveCount
                fatalError(
                    "The \(painter) custom painter called canvas.save() or canvas.saveLayer() at least "
                    + "\(diff) more time\(diff == 1 ? "" : "s") "
                    + "than it called canvas.restore().\n"
                    + "This leaves the canvas in an inconsistent state and will probably result in a broken display.\n"
                    + "You must pair each call to save()/saveLayer() with a later matching call to restore()."
                )
            }
            if debugNewCanvasSaveCount < debugPreviousCanvasSaveCount {
                let diff = debugPreviousCanvasSaveCount - debugNewCanvasSaveCount
                fatalError(
                    "The \(painter) custom painter called canvas.restore() "
                    + "\(diff) more time\(diff == 1 ? "" : "s") "
                    + "than it called canvas.save() or canvas.saveLayer().\n"
                    + "This leaves the canvas in an inconsistent state and will result in a broken display.\n"
                    + "You should only call restore() if you first called save() or saveLayer()."
                )
            }
            return debugNewCanvasSaveCount == debugPreviousCanvasSaveCount
        }())
        canvas.restore()
    }

    /// Paints the background painter, then the child, then the foreground painter.
    ///
    /// **Dart Source:** custom_paint.dart:639-648
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if let painter = _painter {
            _paintWithPainter(context.canvas, offset, painter)
            _setRasterCacheHints(context)
        }
        super.paint(context, offset)
        if let foregroundPainter = _foregroundPainter {
            _paintWithPainter(context.canvas, offset, foregroundPainter)
            _setRasterCacheHints(context)
        }
    }

    /// Sets raster cache hints on the painting context.
    ///
    /// **Dart Source:** custom_paint.dart:651-658
    private func _setRasterCacheHints(_ context: PaintingContext) {
        if isComplex {
            context.setIsComplexHint()
        }
        if willChange {
            // TODO: Call context.setWillChangeHint() once available.
        }
    }

    // MARK: - Semantics

    /// Builds semantics for the picture drawn by `painter`.
    ///
    /// **Dart Source:** custom_paint.dart:661
    private var _backgroundSemanticsBuilder: SemanticsBuilderCallback?

    /// Builds semantics for the picture drawn by `foregroundPainter`.
    ///
    /// **Dart Source:** custom_paint.dart:664
    private var _foregroundSemanticsBuilder: SemanticsBuilderCallback?

    /// Describe the semantics of the picture painted by the `painter`.
    ///
    /// **Dart Source:** custom_paint.dart:676
    private var _backgroundSemanticsNodes: [SemanticsNode]?

    /// Describe the semantics of the picture painted by the `foregroundPainter`.
    ///
    /// **Dart Source:** custom_paint.dart:679
    private var _foregroundSemanticsNodes: [SemanticsNode]?

    /// Describes the semantics configuration for this render object.
    ///
    /// Sets the semantics builder references and determines whether this
    /// object is a semantic boundary.
    ///
    /// **Dart Source:** custom_paint.dart:667-673
    ///
    /// TODO: Implement fully once `describeSemanticsConfiguration` is available on
    /// RenderObject. Currently stubbed because RenderObject does not yet define
    /// `SemanticsConfiguration` override points.
    public func describeSemanticsConfigurationStub() {
        // super.describeSemanticsConfiguration(config)
        _backgroundSemanticsBuilder = painter?.semanticsBuilder
        _foregroundSemanticsBuilder = foregroundPainter?.semanticsBuilder
        // config.isSemanticBoundary =
        //     _backgroundSemanticsBuilder != nil || _foregroundSemanticsBuilder != nil
    }

    /// Assembles the semantics node with background and foreground children.
    ///
    /// **Dart Source:** custom_paint.dart:682-725
    ///
    /// TODO: Implement fully once `assembleSemanticsNode` is available on
    /// RenderObject. Currently stubbed because RenderObject does not yet define
    /// semantics assembly override points.
    public func assembleSemanticsNodeStub(
        _ node: SemanticsNode,
        _ config: SemanticsConfiguration,
        _ children: [SemanticsNode]
    ) {
        // TODO: Full implementation requires the child diffing algorithm
        // and proper integration with the semantics pipeline.

        let backgroundSemantics = _backgroundSemanticsBuilder != nil
            ? _backgroundSemanticsBuilder!(size)
            : [CustomPainterSemantics]()
        _backgroundSemanticsNodes = RenderCustomPaint._updateSemanticsChildren(
            _backgroundSemanticsNodes,
            backgroundSemantics
        )

        let foregroundSemantics = _foregroundSemanticsBuilder != nil
            ? _foregroundSemanticsBuilder!(size)
            : [CustomPainterSemantics]()
        _foregroundSemanticsNodes = RenderCustomPaint._updateSemanticsChildren(
            _foregroundSemanticsNodes,
            foregroundSemantics
        )

        let hasBackgroundSemantics =
            _backgroundSemanticsNodes != nil && !_backgroundSemanticsNodes!.isEmpty
        let hasForegroundSemantics =
            _foregroundSemanticsNodes != nil && !_foregroundSemanticsNodes!.isEmpty

        var finalChildren = [SemanticsNode]()
        if hasBackgroundSemantics {
            finalChildren.append(contentsOf: _backgroundSemanticsNodes!)
        }
        finalChildren.append(contentsOf: children)
        if hasForegroundSemantics {
            finalChildren.append(contentsOf: _foregroundSemanticsNodes!)
        }

        // TODO: super.assembleSemanticsNode(node, config, finalChildren)
    }

    /// Clears semantics nodes.
    ///
    /// **Dart Source:** custom_paint.dart:728-732
    ///
    /// TODO: Implement fully once `clearSemantics` is available on RenderObject.
    public func clearSemanticsStub() {
        // super.clearSemantics()
        _backgroundSemanticsNodes = nil
        _foregroundSemanticsNodes = nil
    }

    // MARK: - Semantics Child Diffing

    /// Updates the nodes of `oldSemantics` using data in `newChildSemantics`, and
    /// returns a new list containing child nodes sorted according to the order
    /// specified by `newChildSemantics`.
    ///
    /// `SemanticsNode`s that match `CustomPainterSemantics` by `Key`s preserve
    /// their `SemanticsNode.key` field. If a node with the same key appears in
    /// a different position in the list, it is moved to the new position, but the
    /// same object is reused.
    ///
    /// The algorithm tries to be as close to `RenderObjectElement.updateChildren`
    /// as possible, deviating only where the concepts diverge between widgets and
    /// semantics.
    ///
    /// **Dart Source:** custom_paint.dart:756-886
    static func _updateSemanticsChildren(
        _ oldSemantics: [SemanticsNode]?,
        _ newChildSemantics: [CustomPainterSemantics]?
    ) -> [SemanticsNode] {
        let oldSemantics = oldSemantics ?? []
        let newChildSemantics = newChildSemantics ?? []

        assert({
            var keys = [AnyHashable: Int]()
            var information = [String]()
            for i in 0..<newChildSemantics.count {
                let child = newChildSemantics[i]
                if let key = child.key {
                    let hashableKey = AnyHashable(key)
                    if keys[hashableKey] != nil {
                        information.append("- duplicate key \(key) found at position \(i)")
                    }
                    keys[hashableKey] = i
                }
            }
            if !information.isEmpty {
                information.insert("Failed to update the list of CustomPainterSemantics:", at: 0)
                fatalError(information.joined(separator: "\n"))
            }
            return true
        }())

        var newChildrenTop = 0
        var oldChildrenTop = 0
        var newChildrenBottom = newChildSemantics.count - 1
        var oldChildrenBottom = oldSemantics.count - 1

        var newChildren = [SemanticsNode?](repeating: nil, count: newChildSemantics.count)

        // Update the top of the list.
        while (oldChildrenTop <= oldChildrenBottom) && (newChildrenTop <= newChildrenBottom) {
            let oldChild = oldSemantics[oldChildrenTop]
            let newSemantics = newChildSemantics[newChildrenTop]
            if !_canUpdateSemanticsChild(oldChild, newSemantics) {
                break
            }
            let newChild = _updateSemanticsChild(oldChild, newSemantics)
            newChildren[newChildrenTop] = newChild
            newChildrenTop += 1
            oldChildrenTop += 1
        }

        // Scan the bottom of the list.
        while (oldChildrenTop <= oldChildrenBottom) && (newChildrenTop <= newChildrenBottom) {
            let oldChild = oldSemantics[oldChildrenBottom]
            let newChild = newChildSemantics[newChildrenBottom]
            if !_canUpdateSemanticsChild(oldChild, newChild) {
                break
            }
            oldChildrenBottom -= 1
            newChildrenBottom -= 1
        }

        // Scan the old children in the middle of the list.
        let haveOldChildren = oldChildrenTop <= oldChildrenBottom
        var oldKeyedChildren = [AnyHashable: SemanticsNode]()
        if haveOldChildren {
            while oldChildrenTop <= oldChildrenBottom {
                let oldChild = oldSemantics[oldChildrenTop]
                if let key = oldChild.key {
                    oldKeyedChildren[AnyHashable(key)] = oldChild
                }
                oldChildrenTop += 1
            }
        }

        // Update the middle of the list.
        while newChildrenTop <= newChildrenBottom {
            var oldChild: SemanticsNode?
            let newSemantics = newChildSemantics[newChildrenTop]
            if haveOldChildren {
                if let key = newSemantics.key {
                    let hashableKey = AnyHashable(key)
                    oldChild = oldKeyedChildren[hashableKey]
                    if let existingChild = oldChild {
                        if _canUpdateSemanticsChild(existingChild, newSemantics) {
                            // we found a match!
                            // remove it from oldKeyedChildren so we don't unsync it later
                            oldKeyedChildren.removeValue(forKey: hashableKey)
                        } else {
                            // Not a match, let's pretend we didn't see it for now.
                            oldChild = nil
                        }
                    }
                }
            }
            assert(oldChild == nil || _canUpdateSemanticsChild(oldChild!, newSemantics))
            let newChild = _updateSemanticsChild(oldChild, newSemantics)
            assert(oldChild === newChild || oldChild == nil)
            newChildren[newChildrenTop] = newChild
            newChildrenTop += 1
        }

        // We've scanned the whole list.
        assert(oldChildrenTop == oldChildrenBottom + 1)
        assert(newChildrenTop == newChildrenBottom + 1)
        assert(newChildSemantics.count - newChildrenTop == oldSemantics.count - oldChildrenTop)
        newChildrenBottom = newChildSemantics.count - 1
        oldChildrenBottom = oldSemantics.count - 1

        // Update the bottom of the list.
        while (oldChildrenTop <= oldChildrenBottom) && (newChildrenTop <= newChildrenBottom) {
            let oldChild = oldSemantics[oldChildrenTop]
            let newSemantics = newChildSemantics[newChildrenTop]
            assert(_canUpdateSemanticsChild(oldChild, newSemantics))
            let newChild = _updateSemanticsChild(oldChild, newSemantics)
            assert(oldChild === newChild)
            newChildren[newChildrenTop] = newChild
            newChildrenTop += 1
            oldChildrenTop += 1
        }

        assert({
            for node in newChildren {
                assert(node != nil)
            }
            return true
        }())

        return newChildren.map { $0! }
    }

    /// Whether `oldChild` can be updated with properties from `newSemantics`.
    ///
    /// If `oldChild` can be updated, it is updated using `_updateSemanticsChild`.
    /// Otherwise, the node is replaced by a new instance of `SemanticsNode`.
    ///
    /// **Dart Source:** custom_paint.dart:892-897
    private static func _canUpdateSemanticsChild(
        _ oldChild: SemanticsNode,
        _ newSemantics: CustomPainterSemantics
    ) -> Bool {
        return _keysMatch(oldChild.key, newSemantics.key)
    }

    /// Compares two optional `Key` values for equality.
    ///
    /// Since `Key` is a protocol (existential type), direct `==` comparison
    /// is not possible. This helper uses `AnyHashable` wrapping for comparison.
    private static func _keysMatch(_ lhs: (any Key)?, _ rhs: (any Key)?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (l?, r?):
            return AnyHashable(l) == AnyHashable(r)
        default:
            return false
        }
    }

    /// Updates `oldChild` using the properties of `newSemantics`.
    ///
    /// This method requires that `_canUpdateSemanticsChild(oldChild, newSemantics)`
    /// is true prior to calling it.
    ///
    /// **Dart Source:** custom_paint.dart:903-1127
    ///
    /// TODO: The full property-by-property mapping from SemanticsProperties to
    /// SemanticsConfiguration (~50 properties) is stubbed. The complete mapping
    /// should be implemented when all SemanticsConfiguration setters are available.
    private static func _updateSemanticsChild(
        _ oldChild: SemanticsNode?,
        _ newSemantics: CustomPainterSemantics
    ) -> SemanticsNode {
        assert(oldChild == nil || _canUpdateSemanticsChild(oldChild!, newSemantics))

        let newChild: SemanticsNode
        if let existing = oldChild {
            newChild = existing
        } else {
            newChild = SemanticsNode(key: newSemantics.key)
        }

        let properties = newSemantics.properties
        let config = SemanticsConfiguration()

        // TODO: Map all ~50 SemanticsProperties fields to SemanticsConfiguration.
        // The full property mapping (lines 911-1113 in the Dart source) sets
        // configuration properties such as:
        //   - config.isChecked = properties.checked
        //   - config.isSelected = properties.selected
        //   - config.isButton = properties.button
        //   - config.label = properties.label
        //   - config.value = properties.value
        //   - config.hint = properties.hint
        //   - config.textDirection = properties.textDirection
        //   - config.onTap = properties.onTap
        //   - config.onLongPress = properties.onLongPress
        //   ... and many more.
        //
        // This will be completed when the full SemanticsConfiguration property
        // surface is verified. For now, map the most commonly used properties:

        if let label = properties.label {
            config.label = label
        }
        if let value = properties.value {
            config.value = value
        }
        if let hint = properties.hint {
            config.hint = hint
        }
        if properties.textDirection != nil {
            config.textDirection = properties.textDirection
        }

        newChild.updateWith(
            config: config,
            // As of now CustomPainter does not support multiple tree levels.
            childrenInInversePaintOrder: []
        )

        newChild.rect = newSemantics.rect
        newChild.transform = newSemantics.transform
        newChild.tags = newSemantics.tags

        return newChild
    }

    // MARK: - Debug

    /// Adds custom paint properties to the diagnostics tree.
    ///
    /// **Dart Source:** custom_paint.dart:1130-1145
    public func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        // TODO: Call super.debugFillProperties(properties) once available on RenderProxyBox.
        properties.add(MessageProperty("painter", "\(String(describing: _painter))"))
        properties.add(
            MessageProperty(
                "foregroundPainter",
                "\(String(describing: _foregroundPainter))",
                level: _foregroundPainter != nil ? .info : .fine
            )
        )
        properties.add(
            DiagnosticsProperty<Size>("preferredSize", _preferredSize, defaultValue: Size.zero)
        )
        properties.add(DiagnosticsProperty<Bool>("isComplex", isComplex, defaultValue: false))
        properties.add(DiagnosticsProperty<Bool>("willChange", willChange, defaultValue: false))
    }
}
