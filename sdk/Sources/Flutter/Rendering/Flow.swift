// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Flow layout delegate, painting context, and parent data types.
///
/// Flow layouts are optimized for moving children around the screen using
/// transformation matrices.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/flow.dart`

import FlutterSwiftBridge

// MARK: - ClipRectLayer Stub

/// A composited layer that clips its children to a rectangle.
///
/// This is a minimal stub for forward reference. The full implementation
/// will be provided in a later subtask when the full Layer hierarchy is
/// migrated.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`
/// **Original Name:** `ClipRectLayer`
public class ClipRectLayer: ContainerLayer {

    /// Creates a clip rect layer.
    ///
    /// **Dart Source:** `layer.dart`
    public init(clipRect: Rect? = nil, clipBehavior: Clip = .hardEdge) {
        self._clipRect = clipRect
        self._clipBehavior = clipBehavior
        super.init()
    }

    /// The rectangle to clip to.
    public var clipRect: Rect? {
        get { _clipRect }
        set {
            if _clipRect != newValue {
                _clipRect = newValue
                markNeedsAddToScene()
            }
        }
    }
    private var _clipRect: Rect?

    /// How to clip.
    public var clipBehavior: Clip {
        get { _clipBehavior }
        set {
            if _clipBehavior != newValue {
                _clipBehavior = newValue
                markNeedsAddToScene()
            }
        }
    }
    private var _clipBehavior: Clip

    public override func addToScene(_ builder: any SceneBuilder) {
        assert(_clipRect != nil)
        engineLayer = builder.pushClipRect(
            _clipRect!,
            clipBehavior: _clipBehavior,
            oldLayer: _engineLayer as? ClipRectEngineLayer
        )
        addChildrenToScene(builder)
        builder.pop()
    }
}

// MARK: - ClipRRectLayer Stub

/// A composited layer that clips its children to a rounded rectangle.
///
/// This is a minimal stub for forward reference. The full implementation
/// will be provided in a later subtask when the full Layer hierarchy is
/// migrated.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`
/// **Original Name:** `ClipRRectLayer`
public class ClipRRectLayer: ContainerLayer {

    /// Creates a clip rounded rect layer.
    ///
    /// **Dart Source:** `layer.dart`
    public init(clipRRect: RRect? = nil, clipBehavior: Clip = .antiAlias) {
        self._clipRRect = clipRRect
        self._clipBehavior = clipBehavior
        super.init()
    }

    /// The rounded rectangle to clip to.
    public var clipRRect: RRect? {
        get { _clipRRect }
        set {
            if _clipRRect != newValue {
                _clipRRect = newValue
                markNeedsAddToScene()
            }
        }
    }
    private var _clipRRect: RRect?

    /// How to clip.
    public var clipBehavior: Clip {
        get { _clipBehavior }
        set {
            if _clipBehavior != newValue {
                _clipBehavior = newValue
                markNeedsAddToScene()
            }
        }
    }
    private var _clipBehavior: Clip

    public override func addToScene(_ builder: any SceneBuilder) {
        assert(_clipRRect != nil)
        engineLayer = builder.pushClipRRect(
            _clipRRect!,
            clipBehavior: _clipBehavior,
            oldLayer: _engineLayer as? ClipRRectEngineLayer
        )
        addChildrenToScene(builder)
        builder.pop()
    }
}

// MARK: - ClipPathLayer Stub

/// A composited layer that clips its children to a path.
///
/// This is a minimal stub for forward reference. The full implementation
/// will be provided in a later subtask when the full Layer hierarchy is
/// migrated.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`
/// **Original Name:** `ClipPathLayer`
public class ClipPathLayer: ContainerLayer {

    /// Creates a clip path layer.
    ///
    /// **Dart Source:** `layer.dart`
    public init(clipPath: Path? = nil, clipBehavior: Clip = .antiAlias) {
        self._clipPath = clipPath
        self._clipBehavior = clipBehavior
        super.init()
    }

    /// The path to clip to.
    public var clipPath: Path? {
        get { _clipPath }
        set {
            _clipPath = newValue
            markNeedsAddToScene()
        }
    }
    private var _clipPath: Path?

    /// How to clip.
    public var clipBehavior: Clip {
        get { _clipBehavior }
        set {
            if _clipBehavior != newValue {
                _clipBehavior = newValue
                markNeedsAddToScene()
            }
        }
    }
    private var _clipBehavior: Clip

    public override func addToScene(_ builder: any SceneBuilder) {
        assert(_clipPath != nil)
        engineLayer = builder.pushClipPath(
            _clipPath!,
            clipBehavior: _clipBehavior,
            oldLayer: _engineLayer as? ClipPathEngineLayer
        )
        addChildrenToScene(builder)
        builder.pop()
    }
}

// MARK: - OpacityLayer Stub

/// A composited layer that makes its children partially transparent.
///
/// This is a minimal stub for forward reference. The full implementation
/// will be provided in a later subtask when the full Layer hierarchy is
/// migrated.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`
/// **Original Name:** `OpacityLayer`
public class OpacityLayer: ContainerLayer {

    /// Creates an opacity layer.
    ///
    /// **Dart Source:** `layer.dart`
    public init(alpha: Int? = nil, offset: Offset = .zero) {
        self._alpha = alpha
        self._offset = offset
        super.init()
    }

    /// The alpha value to apply.
    ///
    /// **Dart Source:** `layer.dart`
    public var alpha: Int? {
        get { _alpha }
        set {
            _alpha = newValue
            markNeedsAddToScene()
        }
    }
    private var _alpha: Int?

    /// The offset to apply before compositing.
    public var offset: Offset {
        get { _offset }
        set {
            _offset = newValue
            markNeedsAddToScene()
        }
    }
    private var _offset: Offset

    public override func addToScene(_ builder: any SceneBuilder) {
        assert(_alpha != nil)
        engineLayer = builder.pushOpacity(
            _alpha!,
            offset: _offset,
            oldLayer: _engineLayer as? OpacityEngineLayer
        )
        addChildrenToScene(builder)
        builder.pop()
    }
}

// MARK: - FlowPaintingContext

/// A context in which a `FlowDelegate` paints.
///
/// Provides information about the current size of the container and the
/// children and a mechanism for painting children.
///
/// **Dart Source:** flow.dart:29-50
public protocol FlowPaintingContext {
    /// The size of the container in which the children can be painted.
    ///
    /// **Dart Source:** flow.dart:31
    var size: Size { get }

    /// The number of children available to paint.
    ///
    /// **Dart Source:** flow.dart:34
    var childCount: Int { get }

    /// The size of the `i`th child.
    ///
    /// If `i` is negative or exceeds `childCount`, returns `nil`.
    ///
    /// **Dart Source:** flow.dart:39
    func getChildSize(_ i: Int) -> Size?

    /// Paint the `i`th child using the given transform.
    ///
    /// The child will be painted in a coordinate system that concatenates the
    /// container's coordinate system with the given transform. The origin of the
    /// parent's coordinate system is the upper left corner of the parent, with
    /// x increasing rightward and y increasing downward.
    ///
    /// The container will clip the children to its bounds.
    ///
    /// **Dart Source:** flow.dart:49
    func paintChild(_ i: Int, transform: Matrix4?, opacity: Double)
}

/// Default parameter values for `FlowPaintingContext.paintChild`.
///
/// In Dart, `paintChild` has default values: `transform` defaults to `nil`
/// and `opacity` defaults to `1.0`. Swift protocols cannot have default
/// parameter values, so we provide them via this extension.
///
/// **Dart Source:** flow.dart:49
public extension FlowPaintingContext {
    /// Paints the `i`th child with default `nil` transform and full opacity.
    ///
    /// **Dart Source:** flow.dart:49
    func paintChild(_ i: Int) {
        paintChild(i, transform: nil, opacity: 1.0)
    }

    /// Paints the `i`th child with the given transform and full opacity.
    ///
    /// **Dart Source:** flow.dart:49
    func paintChild(_ i: Int, transform: Matrix4?) {
        paintChild(i, transform: transform, opacity: 1.0)
    }

    /// Paints the `i`th child with no transform and the given opacity.
    ///
    /// **Dart Source:** flow.dart:49
    func paintChild(_ i: Int, opacity: Double) {
        paintChild(i, transform: nil, opacity: opacity)
    }
}

// MARK: - FlowDelegate

/// A delegate that controls the appearance of a flow layout.
///
/// Flow layouts are optimized for moving children around the screen using
/// transformation matrices. For optimal performance, construct the
/// `FlowDelegate` with an `Animation` that ticks whenever the delegate wishes
/// to change the transformation matrices for the children and avoid rebuilding
/// the `Flow` widget itself every animation frame.
///
/// **Dart Source:** flow.dart:64-142
open class FlowDelegate {

    /// The flow will repaint whenever `repaint` notifies its listeners.
    ///
    /// **Dart Source:** flow.dart:66
    public init(repaint: (any Listenable)? = nil) {
        self._repaint = repaint
    }

    /// The listenable that triggers repaint.
    ///
    /// **Dart Source:** flow.dart:68
    private let _repaint: (any Listenable)?

    /// The repaint listenable, exposed for use by the render object.
    ///
    /// **Dart Source:** flow.dart:68
    public var repaint: (any Listenable)? { _repaint }

    // MARK: - getSize

    /// Override to control the size of the container for the children.
    ///
    /// By default, the flow will be as large as possible. If this function
    /// returns a size that does not respect the given constraints, the size will
    /// be adjusted to be as close to the returned size as possible while still
    /// respecting the constraints.
    ///
    /// If this function depends on information other than the given constraints,
    /// override `shouldRelayout` to indicate when the container should
    /// relayout.
    ///
    /// **Dart Source:** flow.dart:80
    open func getSize(_ constraints: BoxConstraints) -> Size {
        return constraints.biggest
    }

    // MARK: - getConstraintsForChild

    /// Override to control the layout constraints given to each child.
    ///
    /// By default, the children will receive the given constraints, which are the
    /// constraints used to size the container. The children need not respect the
    /// given constraints, but they are required to respect the returned
    /// constraints.
    ///
    /// If this function depends on information other than the given constraints,
    /// override `shouldRelayout` to indicate when the container should
    /// relayout.
    ///
    /// **Dart Source:** flow.dart:95
    open func getConstraintsForChild(_ i: Int, _ constraints: BoxConstraints) -> BoxConstraints {
        return constraints
    }

    // MARK: - paintChildren

    /// Override to paint the children of the flow.
    ///
    /// Children can be painted in any order, but each child can be painted at
    /// most once. Although the container clips the children to its own bounds, it
    /// is more efficient to skip painting a child altogether rather than having
    /// it paint entirely outside the container's clip.
    ///
    /// To paint a child, call `FlowPaintingContext.paintChild` on the given
    /// `FlowPaintingContext` (the `context` argument). The given context is valid
    /// only within the scope of this function call and contains information (such
    /// as the size of the container) that is useful for picking transformation
    /// matrices for the children.
    ///
    /// **Dart Source:** flow.dart:113
    open func paintChildren(_ context: any FlowPaintingContext) {
        fatalError("Subclasses of FlowDelegate must override paintChildren(_:)")
    }

    // MARK: - shouldRelayout

    /// Override this method to return true when the children need to be laid out.
    ///
    /// This should compare the fields of the current delegate and the given
    /// `oldDelegate` and return true if the fields are such that the layout would
    /// be different.
    ///
    /// **Dart Source:** flow.dart:119
    open func shouldRelayout(_ oldDelegate: FlowDelegate) -> Bool {
        return false
    }

    // MARK: - shouldRepaint

    /// Override this method to return true when the children need to be
    /// repainted.
    ///
    /// This should compare the fields of the current delegate and the given
    /// `oldDelegate` and return true if the fields are such that
    /// `paintChildren` would act differently.
    ///
    /// The delegate can also trigger a repaint if the delegate provides the
    /// repaint animation argument to this object's constructor and that animation
    /// ticks. Triggering a repaint using this animation-based mechanism is more
    /// efficient than rebuilding the `Flow` widget to change its delegate.
    ///
    /// **Dart Source:** flow.dart:134
    open func shouldRepaint(_ oldDelegate: FlowDelegate) -> Bool {
        fatalError("Subclasses of FlowDelegate must override shouldRepaint(_:)")
    }

    // MARK: - CustomStringConvertible

    /// A string representation of this delegate.
    ///
    /// By default, returns the runtime type of the class.
    ///
    /// **Dart Source:** flow.dart:140-141
    public var description: String {
        objectRuntimeType(self, "FlowDelegate")
    }
}

// MARK: - FlowParentData

/// Parent data for use with `RenderFlow`.
///
/// The `offset` property is ignored by `RenderFlow` and is always set to
/// `Offset.zero`. Children of a `RenderFlow` are positioned using a
/// transformation matrix, which is private to the `RenderFlow`. To set the
/// matrix, use the `FlowPaintingContext.paintChild` function from an override
/// of the `FlowDelegate.paintChildren` function.
///
/// **Dart Source:** flow.dart:151-153
public class FlowParentData: ContainerBoxParentData<RenderBox> {
    /// The transform applied to this child when painting.
    ///
    /// This is internal to the flow layout; it is set via
    /// `FlowPaintingContext.paintChild`.
    ///
    /// **Dart Source:** flow.dart:152
    internal var _transform: Matrix4?
}

// MARK: - RenderFlow

/// Implements the flow layout algorithm.
///
/// Flow layouts are optimized for repositioning children using transformation
/// matrices.
///
/// The flow container is sized independently from the children by the
/// `FlowDelegate.getSize` function of the delegate. The children are then sized
/// independently given the constraints from the
/// `FlowDelegate.getConstraintsForChild` function.
///
/// Rather than positioning the children during layout, the children are
/// positioned using transformation matrices during the paint phase using the
/// matrices from the `FlowDelegate.paintChildren` function. The children are thus
/// repositioned efficiently by repainting the flow, skipping layout.
///
/// The most efficient way to trigger a repaint of the flow is to supply a
/// repaint argument to the constructor of the `FlowDelegate`. The flow will
/// listen to this animation and repaint whenever the animation ticks, avoiding
/// both the build and layout phases of the pipeline.
///
/// In Dart this class extends `RenderBox` and mixes in
/// `ContainerRenderObjectMixin<RenderBox, FlowParentData>` and
/// `RenderBoxContainerDefaultsMixin<RenderBox, FlowParentData>`,
/// and implements `FlowPaintingContext`.
///
/// Since Swift does not support generic mixins, the container management
/// (linked-list child pointers) is implemented inline, and the class
/// conforms to `RenderBoxContainerDefaults` for default paint and
/// hit-testing behavior, and to `FlowPaintingContext` for the painting
/// context protocol.
///
/// **Dart Source:** flow.dart:179-331
public class RenderFlow: RenderBox, RenderBoxContainerDefaults, FlowPaintingContext {
    public typealias ChildType = RenderBox

    // MARK: - Container child management (ContainerRenderObjectMixin)

    /// The first child in the child list.
    ///
    /// **Dart Source:** object.dart:4222 (ContainerRenderObjectMixin)
    public private(set) var firstChild: RenderBox?

    /// The last child in the child list.
    ///
    /// **Dart Source:** object.dart:4223 (ContainerRenderObjectMixin)
    public private(set) var lastChild: RenderBox?

    /// The number of children.
    ///
    /// **Dart Source:** object.dart:4226 (ContainerRenderObjectMixin)
    public private(set) var childCount: Int = 0

    /// Returns the next sibling of the given child.
    ///
    /// **Dart Source:** object.dart:4393 (ContainerRenderObjectMixin)
    public func childAfter(_ child: RenderBox) -> RenderBox? {
        let parentData = child.parentData as! FlowParentData
        return parentData.nextSibling
    }

    /// Returns the previous sibling of the given child.
    ///
    /// **Dart Source:** object.dart:4399 (ContainerRenderObjectMixin)
    public func childBefore(_ child: RenderBox) -> RenderBox? {
        let parentData = child.parentData as! FlowParentData
        return parentData.previousSibling
    }

    /// Inserts a child into the linked list.
    ///
    /// **Dart Source:** object.dart:4234-4268 (ContainerRenderObjectMixin._insertIntoChildList)
    private func _insertIntoChildList(_ child: RenderBox, after: RenderBox? = nil) {
        let childParentData = child.parentData as! FlowParentData
        childCount += 1
        assert(childCount > 0)
        if let after = after {
            let afterParentData = after.parentData as! FlowParentData
            if afterParentData.nextSibling == nil {
                // Inserting at the end — update lastChild
                childParentData.previousSibling = after
                afterParentData.nextSibling = child
                lastChild = child
            } else {
                // Inserting in the middle
                childParentData.nextSibling = afterParentData.nextSibling
                childParentData.previousSibling = after
                let nextParentData = afterParentData.nextSibling!.parentData as! FlowParentData
                nextParentData.previousSibling = child
                afterParentData.nextSibling = child
            }
        } else {
            childParentData.nextSibling = firstChild
            if let first = firstChild {
                let firstParentData = first.parentData as! FlowParentData
                firstParentData.previousSibling = child
            }
            firstChild = child
            lastChild = lastChild ?? child
        }
    }

    /// Removes a child from the linked list.
    ///
    /// **Dart Source:** object.dart:4271-4295 (ContainerRenderObjectMixin._removeFromChildList)
    private func _removeFromChildList(_ child: RenderBox) {
        let childParentData = child.parentData as! FlowParentData
        if childParentData.previousSibling == nil {
            // child is firstChild
            firstChild = childParentData.nextSibling
        } else {
            let previousParentData =
                childParentData.previousSibling!.parentData as! FlowParentData
            previousParentData.nextSibling = childParentData.nextSibling
        }
        if childParentData.nextSibling == nil {
            // child is lastChild
            lastChild = childParentData.previousSibling
        } else {
            let nextParentData =
                childParentData.nextSibling!.parentData as! FlowParentData
            nextParentData.previousSibling = childParentData.previousSibling
        }
        childParentData.previousSibling = nil
        childParentData.nextSibling = nil
        childCount -= 1
    }

    /// Adds a child to the child list, optionally after the given child.
    ///
    /// **Dart Source:** object.dart:4310-4323 (ContainerRenderObjectMixin.insert)
    public func insert(_ child: RenderBox, after: RenderBox? = nil) {
        adoptChild(child)
        _insertIntoChildList(child, after: after)
    }

    /// Appends all the given children to the end of the child list.
    ///
    /// **Dart Source:** object.dart:4325-4341 (ContainerRenderObjectMixin.addAll)
    public func addAll(_ children: [RenderBox]?) {
        children?.forEach { insert($0, after: lastChild) }
    }

    /// Removes a child from the child list.
    ///
    /// **Dart Source:** object.dart:4343-4353 (ContainerRenderObjectMixin.remove)
    public func remove(_ child: RenderBox) {
        _removeFromChildList(child)
        dropChild(child)
    }

    // MARK: - Stored property for markNeedsPaint closure

    /// A closure wrapper around `markNeedsPaint` that can be used as a
    /// `VoidCallback` for `Listenable.addListener` / `removeListener`.
    ///
    /// We store this so that the same closure identity is used when adding
    /// and removing the listener.
    private lazy var _markNeedsPaintCallback: VoidCallback = { [weak self] in
        self?.markNeedsPaint()
    }

    // MARK: - Random access children list

    /// A list of children built during layout for O(1) index access.
    ///
    /// Updated during `performLayout`. Only valid if layout is not dirty.
    ///
    /// **Dart Source:** flow.dart:334
    internal var _randomAccessChildren: [RenderBox] = []

    // MARK: - Initializer

    /// Creates a render object for a flow layout.
    ///
    /// For optimal performance, consider using children that return true from
    /// `isRepaintBoundary`.
    ///
    /// **Dart Source:** flow.dart:188-195
    public init(
        children: [RenderBox]? = nil,
        delegate: FlowDelegate,
        clipBehavior: Clip = .hardEdge
    ) {
        self._delegate = delegate
        self._clipBehavior = clipBehavior
        super.init()
        addAll(children)
    }

    // MARK: - setupParentData

    /// Ensures the child has `FlowParentData`.
    ///
    /// If the child already has `FlowParentData`, resets its transform to nil.
    /// Otherwise, assigns new `FlowParentData`.
    ///
    /// **Dart Source:** flow.dart:198-205
    public override func setupParentData(_ child: RenderObject) {
        if let childParentData = child.parentData as? FlowParentData {
            childParentData._transform = nil
        } else {
            child.parentData = FlowParentData()
        }
    }

    // MARK: - delegate

    /// The delegate that controls the transformation matrices of the children.
    ///
    /// When the delegate is changed to a new delegate with the same runtime type
    /// as the old delegate, this object will call the delegate's
    /// `shouldRelayout` and `shouldRepaint` functions to determine whether the
    /// new delegate requires this object to update its layout or painting.
    ///
    /// **Dart Source:** flow.dart:208-234
    public var delegate: FlowDelegate {
        get { _delegate }
        set {
            if _delegate === newValue {
                return
            }
            let oldDelegate = _delegate
            _delegate = newValue

            if type(of: newValue) != type(of: oldDelegate)
                || newValue.shouldRelayout(oldDelegate)
            {
                markNeedsLayout()
            } else if newValue.shouldRepaint(oldDelegate) {
                markNeedsPaint()
            }

            if attached {
                oldDelegate.repaint?.removeListeners(owner: self)
                newValue.repaint?.addListener(_markNeedsPaintCallback, owner: self)
            }
        }
    }

    /// Backing storage for the delegate.
    ///
    /// **Dart Source:** flow.dart:209
    private var _delegate: FlowDelegate

    // MARK: - clipBehavior

    /// Controls how to clip the children of this flow.
    ///
    /// Defaults to `Clip.hardEdge`.
    ///
    /// **Dart Source:** flow.dart:239-247
    public var clipBehavior: Clip {
        get { _clipBehavior }
        set {
            if newValue != _clipBehavior {
                _clipBehavior = newValue
                markNeedsPaint()
                // TODO: Call markNeedsSemanticsUpdate() once semantics is available.
            }
        }
    }

    /// Backing storage for `clipBehavior`.
    ///
    /// **Dart Source:** flow.dart:240
    private var _clipBehavior: Clip = .hardEdge

    // MARK: - attach / detach

    /// Attaches this render object to a pipeline owner.
    ///
    /// Adds a listener to the delegate's repaint listenable so that paint
    /// is marked dirty whenever the listenable notifies.
    ///
    /// **Dart Source:** flow.dart:249-253
    public override func attach(_ owner: PipelineOwner) {
        super.attach(owner)
        _delegate.repaint?.addListener(_markNeedsPaintCallback, owner: self)
    }

    /// Detaches this render object from its pipeline owner.
    ///
    /// Removes the listener from the delegate's repaint listenable.
    ///
    /// **Dart Source:** flow.dart:255-259
    public override func detach() {
        _delegate.repaint?.removeListeners(owner: self)
        super.detach()
    }

    // MARK: - isRepaintBoundary

    /// Always returns true — flow layouts are repaint boundaries.
    ///
    /// **Dart Source:** flow.dart:267
    public override var isRepaintBoundary: Bool { true }

    // MARK: - _getSize

    /// Returns the size that satisfies both the constraints and the delegate's
    /// desired size.
    ///
    /// **Dart Source:** flow.dart:261-264
    private func _getSize(_ constraints: BoxConstraints) -> Size {
        assert(constraints.debugAssertIsValid())
        return constraints.constrain(_delegate.getSize(constraints))
    }

    // MARK: - Intrinsic Dimensions

    // TODO(ianh): It's a bit dubious to be using the getSize function from the
    // delegate to figure out the intrinsic dimensions. We really should either
    // not support intrinsics, or we should expose intrinsic delegate callbacks
    // and throw if they're not implemented.

    /// Computes the minimum intrinsic width for the given height.
    ///
    /// **Dart Source:** flow.dart:274-280
    public override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        let width = _getSize(.tightForFinite(height: height)).width
        if width.isFinite {
            return width
        }
        return 0.0
    }

    /// Computes the maximum intrinsic width for the given height.
    ///
    /// **Dart Source:** flow.dart:283-289
    public override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        let width = _getSize(.tightForFinite(height: height)).width
        if width.isFinite {
            return width
        }
        return 0.0
    }

    /// Computes the minimum intrinsic height for the given width.
    ///
    /// **Dart Source:** flow.dart:292-298
    public override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        let height = _getSize(.tightForFinite(width: width)).height
        if height.isFinite {
            return height
        }
        return 0.0
    }

    /// Computes the maximum intrinsic height for the given width.
    ///
    /// **Dart Source:** flow.dart:300-307
    public override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        let height = _getSize(.tightForFinite(width: width)).height
        if height.isFinite {
            return height
        }
        return 0.0
    }

    // MARK: - Dry Layout

    /// Computes the dry layout size for the given constraints.
    ///
    /// **Dart Source:** flow.dart:309-313
    public override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        return _getSize(constraints)
    }

    // MARK: - performLayout

    /// Performs layout by setting the size from the delegate, then iterating
    /// children to apply delegate constraints and build the random access
    /// children list.
    ///
    /// Each child's offset is set to `Offset.zero` because flow positions
    /// children using transformation matrices during painting rather than
    /// offsets during layout.
    ///
    /// **Dart Source:** flow.dart:316-331
    public override func performLayout() {
        let constraints = boxConstraints
        size = _getSize(constraints)
        var i = 0
        _randomAccessChildren.removeAll()
        var child = firstChild
        while let currentChild = child {
            _randomAccessChildren.append(currentChild)
            let innerConstraints = _delegate.getConstraintsForChild(i, constraints)
            currentChild.layout(innerConstraints, parentUsesSize: true)
            let childParentData = currentChild.parentData! as! FlowParentData
            childParentData.offset = .zero
            child = childParentData.nextSibling
            i += 1
        }
    }

    // MARK: - FlowPaintingContext conformance

    /// Returns the size of the `i`th child, or `nil` if the index is out of
    /// range.
    ///
    /// This is part of the `FlowPaintingContext` protocol.
    ///
    /// **Dart Source:** flow.dart:344-349
    public func getChildSize(_ i: Int) -> Size? {
        if i < 0 || i >= _randomAccessChildren.count {
            return nil
        }
        return _randomAccessChildren[i].size
    }

    // MARK: - Paint state (only valid during paint)

    /// Updated during paint. Tracks the order in which children were painted.
    ///
    /// **Dart Source:** flow.dart:337
    private var _lastPaintOrder: [Int] = []

    /// The painting context, only valid during paint.
    ///
    /// **Dart Source:** flow.dart:340
    private var _paintingContext: PaintingContext?

    /// The painting offset, only valid during paint.
    ///
    /// **Dart Source:** flow.dart:341
    private var _paintingOffset: Offset?

    // MARK: - paintChild

    /// Paints the `i`th child using the given transform and opacity.
    ///
    /// Sets the child's `_transform` in its parent data. If `opacity` is 0.0,
    /// the transform is stored (for hit testing) but the child is not actually
    /// painted. If `opacity` is 1.0, uses `pushTransform` to paint. If opacity
    /// is between 0 and 1, uses both `pushOpacity` and `pushTransform`.
    ///
    /// Each child can only be painted once per paint cycle; painting the same
    /// child twice triggers an assertion failure.
    ///
    /// **Dart Source:** flow.dart:352-389
    public func paintChild(_ i: Int, transform: Matrix4?, opacity: Double) {
        let effectiveTransform = transform ?? Matrix4.identity()
        let child = _randomAccessChildren[i]
        let childParentData = child.parentData! as! FlowParentData
        assert(
            {
                if childParentData._transform != nil {
                    fatalError(
                        "Cannot call paintChild twice for the same child.\n"
                        + "The flow delegate of type \(type(of: _delegate)) attempted to "
                        + "paint child \(i) multiple times, which is not permitted."
                    )
                }
                return true
            }()
        )
        _lastPaintOrder.append(i)
        childParentData._transform = effectiveTransform

        // We return after assigning _transform so that the transparent child can
        // still be hit tested at the correct location.
        if opacity == 0.0 {
            return
        }

        let painter: PaintingContextCallback = { context, offset in
            context.paintChild(child, offset)
        }

        if opacity == 1.0 {
            _ = _paintingContext!.pushTransform(
                needsCompositing, _paintingOffset!, effectiveTransform, painter
            )
        } else {
            _ = _paintingContext!.pushOpacity(
                _paintingOffset!,
                Color.getAlphaFromOpacity(opacity),
                { context, offset in
                    _ = context.pushTransform(
                        self.needsCompositing, offset, effectiveTransform, painter
                    )
                }
            )
        }
    }

    // MARK: - _paintWithDelegate

    /// Clears all children's transforms, resets paint order, and calls the
    /// delegate's `paintChildren` method.
    ///
    /// **Dart Source:** flow.dart:391-405
    private func _paintWithDelegate(_ context: PaintingContext, _ offset: Offset) {
        _lastPaintOrder.removeAll()
        _paintingContext = context
        _paintingOffset = offset
        for child in _randomAccessChildren {
            let childParentData = child.parentData! as! FlowParentData
            childParentData._transform = nil
        }
        defer {
            _paintingContext = nil
            _paintingOffset = nil
        }
        _delegate.paintChildren(self)
    }

    // MARK: - _clipRectLayer

    /// A handle to the `ClipRectLayer` used for clip management during paint.
    ///
    /// **Dart Source:** flow.dart:419
    private let _clipRectLayer: LayerHandle<ClipRectLayer> = LayerHandle<ClipRectLayer>()

    // MARK: - paint

    /// Paints this render object and its children.
    ///
    /// Wraps `_paintWithDelegate` in a `pushClipRect` using the current
    /// `clipBehavior`. The clip rect layer is cached in `_clipRectLayer` for
    /// reuse across frames.
    ///
    /// **Dart Source:** flow.dart:408-417
    public override func paint(_ context: PaintingContext, _ offset: Offset) {
        _clipRectLayer.layer = context.pushClipRect(
            needsCompositing,
            offset,
            Offset.zero & size,
            _paintWithDelegate,
            clipBehavior: clipBehavior,
            oldLayer: _clipRectLayer.layer
        )
    }

    // MARK: - dispose

    /// Releases resources held by this render object.
    ///
    /// Clears the `_clipRectLayer` handle and calls super's dispose.
    ///
    /// **Dart Source:** flow.dart:422-425
    public override func dispose() {
        _clipRectLayer.layer = nil
        super.dispose()
    }

    // MARK: - hitTestChildren

    /// Hit tests children in reverse paint order.
    ///
    /// Iterates `_lastPaintOrder` in reverse and uses `addWithPaintTransform`
    /// to apply each child's stored transform for hit testing. Returns true
    /// if any child absorbs the hit.
    ///
    /// **Dart Source:** flow.dart:428-453
    public override func hitTestChildren(_ result: BoxHitTestResult, position: Offset) -> Bool {
        let children = getChildrenAsList()
        var i = _lastPaintOrder.count - 1
        while i >= 0 {
            let childIndex = _lastPaintOrder[i]
            if childIndex >= children.count {
                i -= 1
                continue
            }
            let child = children[childIndex]
            let childParentData = child.parentData! as! FlowParentData
            let transform = childParentData._transform
            if transform == nil {
                i -= 1
                continue
            }
            let absorbed = result.addWithPaintTransform(
                transform: transform,
                position: position,
                hitTest: { result, position in
                    return child.hitTest(result, position: position)
                }
            )
            if absorbed {
                return true
            }
            i -= 1
        }
        return false
    }

    // MARK: - applyPaintTransform

    /// Multiplies the given transform by this child's stored paint transform.
    ///
    /// **Dart Source:** flow.dart:456-462
    public override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        let childParentData = child.parentData! as! FlowParentData
        if let childTransform = childParentData._transform {
            transform = transform * childTransform
        }
        super.applyPaintTransform(child, &transform)
    }
}

// MARK: - ContainerRenderObjectHost Conformance

extension RenderFlow: ContainerRenderObjectHost {
    /// Reorders a child that is already ours.
    ///
    /// Relinks in place rather than `remove`/`insert`: those drop and re-adopt,
    /// and `dropChild` clears the parent data (see `RenderObject.dropChild`),
    /// which a move has no way to restore.
    ///
    /// **Dart Source:** `object.dart:4448-4460`
    public func move(_ child: RenderBox, after: RenderBox?) {
        guard let childParentData = child.parentData as? FlowParentData else { return }
        if childParentData.previousSibling === after { return }
        _removeFromChildList(child)
        _insertIntoChildList(child, after: after)
        markNeedsLayout()
    }
}
