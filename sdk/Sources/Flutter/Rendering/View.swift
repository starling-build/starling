// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// View types for the root of the render tree.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/view.dart`

import FlutterSwiftBridge

// MARK: - ViewConfiguration

/// The layout constraints for the root render object.
///
/// This is an immutable value type that describes how the root render object
/// should be sized and scaled. It holds both logical and physical constraints,
/// along with the device pixel ratio for coordinate transformations.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/view.dart`
/// **Original Name:** `ViewConfiguration`
/// **Lines:** 22-119
public struct RenderViewConfiguration: Hashable, CustomStringConvertible {

    // MARK: - Properties

    /// The constraints of the output surface in logical pixels.
    ///
    /// The constraints are passed to the child of the root render object.
    ///
    /// **Dart Source:** `view.dart:55-56`
    public let logicalConstraints: BoxConstraints

    /// The constraints of the output surface in physical pixels.
    ///
    /// These constraints are enforced in `toPhysicalSize` when translating
    /// the logical size of the root render object back to physical pixels for
    /// the `FlutterView.render` method.
    ///
    /// **Dart Source:** `view.dart:62-63`
    public let physicalConstraints: BoxConstraints

    /// The pixel density of the output surface.
    ///
    /// **Dart Source:** `view.dart:65`
    public let devicePixelRatio: Double

    // MARK: - Initializers

    /// Creates a view configuration.
    ///
    /// By default, the view has `logicalConstraints` and `physicalConstraints`
    /// with all dimensions set to zero (i.e. the view is forced to `Size.zero`)
    /// and a `devicePixelRatio` of 1.0.
    ///
    /// **Dart Source:** `view.dart:33-37`
    public init(
        physicalConstraints: BoxConstraints = BoxConstraints(maxWidth: 0, maxHeight: 0),
        logicalConstraints: BoxConstraints = BoxConstraints(maxWidth: 0, maxHeight: 0),
        devicePixelRatio: Double = 1.0
    ) {
        self.physicalConstraints = physicalConstraints
        self.logicalConstraints = logicalConstraints
        self.devicePixelRatio = devicePixelRatio
    }

    /// Creates a view configuration for the provided `FlutterView`.
    ///
    /// **Dart Source:** `view.dart:40-50`
    public static func fromView(_ view: FlutterView) -> RenderViewConfiguration {
        let physicalConstraints = BoxConstraints.fromViewConstraints(view.physicalConstraints)
        let devicePixelRatio = view.devicePixelRatio
        return RenderViewConfiguration(
            physicalConstraints: physicalConstraints,
            logicalConstraints: physicalConstraints / devicePixelRatio,
            devicePixelRatio: devicePixelRatio
        )
    }

    // MARK: - Methods

    /// Creates a transformation matrix that applies the `devicePixelRatio`.
    ///
    /// The matrix translates points from the local coordinate system of the
    /// app (in logical pixels) to the global coordinate system of the
    /// `FlutterView` (in physical pixels).
    ///
    /// **Dart Source:** `view.dart:72-74`
    public func toMatrix() -> Matrix4 {
        return Matrix4.diagonal3Values(devicePixelRatio, devicePixelRatio, 1.0)
    }

    /// Returns whether `toMatrix` would return a different value for this
    /// configuration than it would for the given `oldConfiguration`.
    ///
    /// **Dart Source:** `view.dart:78-87`
    public func shouldUpdateMatrix(_ oldConfiguration: RenderViewConfiguration) -> Bool {
        // For this class, the only input to toMatrix is the device pixel ratio,
        // so we return true if they differ and false otherwise.
        return oldConfiguration.devicePixelRatio != devicePixelRatio
    }

    /// Transforms the provided `Size` in logical pixels to physical pixels.
    ///
    /// The `FlutterView.render` method accepts only sizes in physical pixels,
    /// but the framework operates in logical pixels. This method is used to
    /// transform the logical size calculated for a `RenderView` back to a
    /// physical size suitable to be passed to `FlutterView.render`.
    ///
    /// By default, this method just multiplies the provided `Size` with the
    /// `devicePixelRatio` and constrains the result to the `physicalConstraints`.
    ///
    /// **Dart Source:** `view.dart:99-101`
    public func toPhysicalSize(_ logicalSize: Size) -> Size {
        return physicalConstraints.constrain(logicalSize * devicePixelRatio)
    }

    // MARK: - Hashable

    /// **Dart Source:** `view.dart:104-112`
    public static func == (lhs: RenderViewConfiguration, rhs: RenderViewConfiguration) -> Bool {
        lhs.logicalConstraints == rhs.logicalConstraints
            && lhs.physicalConstraints == rhs.physicalConstraints
            && lhs.devicePixelRatio == rhs.devicePixelRatio
    }

    /// **Dart Source:** `view.dart:115`
    public func hash(into hasher: inout Hasher) {
        hasher.combine(logicalConstraints)
        hasher.combine(physicalConstraints)
        hasher.combine(devicePixelRatio)
    }

    // MARK: - CustomStringConvertible

    /// **Dart Source:** `view.dart:118`
    public var description: String {
        "\(logicalConstraints) at \(debugFormatDouble(devicePixelRatio))x"
    }
}

// MARK: - DebugPaintCallback

/// A callback for painting a debug overlay on top of the provided `RenderView`.
///
/// Used by `RenderView.debugAddPaintCallback` and
/// `RenderView.debugRemovePaintCallback`.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/view.dart`
/// **Original Name:** `DebugPaintCallback`
/// **Lines:** 575-580
public typealias DebugPaintCallback = (
    _ context: PaintingContext, _ offset: Offset, _ renderView: RenderView
) -> Void

// MARK: - RenderView

/// The root of the render tree.
///
/// The view represents the total output surface of the render tree and handles
/// bootstrapping the rendering pipeline. The view has a unique child
/// `RenderBox`, which is required to fill the entire output surface.
///
/// This object must be bootstrapped in a specific order:
///
///  1. First, set the `configuration` (either in the constructor or after
///     construction).
///  2. Second, `attach` the object to a `PipelineOwner`.
///  3. Third, use `prepareInitialFrame` to bootstrap the layout and paint logic.
///
/// After the bootstrapping is complete, the `compositeFrame` method may be used
/// to obtain the rendered output.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/view.dart`
/// **Original Name:** `RenderView`
/// **Lines:** 136-573
public class RenderView: RenderObject {

    // MARK: - Initializer

    /// Creates the root of the render tree.
    ///
    /// Typically created by the binding (e.g., `RendererBinding`).
    ///
    /// Providing a `configuration` is optional, but a configuration must be set
    /// before calling `prepareInitialFrame`. This decouples creating the
    /// `RenderView` object from configuring it.
    ///
    /// **Dart Source:** `view.dart:146-152`
    public init(
        child: RenderBox? = nil,
        configuration: RenderViewConfiguration? = nil,
        view: FlutterView
    ) {
        self._view = view
        super.init()
        if let configuration = configuration {
            self._configuration = configuration
        }
        self.child = child
    }

    // MARK: - Child Management (RenderObjectWithChildMixin pattern)

    /// The single child of this render view.
    ///
    /// In Dart, `RenderView` uses `RenderObjectWithChildMixin<RenderBox>` to
    /// manage its single child. In Swift, since generic mixins are not supported,
    /// the child property is implemented directly.
    ///
    /// **Dart Source:** `view.dart:136` (via `RenderObjectWithChildMixin<RenderBox>`)
    public var child: RenderBox? {
        get { _child }
        set {
            if let old = _child {
                // dropChild: clear parent, detach from owner
                old.parentData = nil
                old.parent = nil
                if old.attached { old.detach() }
            }
            _child = newValue
            if let child = _child {
                // adoptChild: set up parent data, parent ref, attach to owner
                setupParentData(child)
                child.parent = self
                if attached { child.attach(_owner!) }
            }
            markNeedsLayout()
        }
    }
    private var _child: RenderBox?

    // MARK: - Size

    /// The current layout size of the view.
    ///
    /// **Dart Source:** `view.dart:155-156`
    public private(set) var size: Size = .zero

    // MARK: - Configuration

    /// The constraints used for the root layout.
    ///
    /// Typically, this configuration is set by the `RendererBinding`, when the
    /// `RenderView` is registered with it. It will also update the configuration
    /// if necessary.
    ///
    /// A `configuration` must be set (either directly or by passing one to the
    /// constructor) before calling `prepareInitialFrame`.
    ///
    /// **Dart Source:** `view.dart:173-190`
    public var configuration: RenderViewConfiguration {
        get {
            guard let config = _configuration else {
                fatalError("RenderView configuration has not been set.")
            }
            return config
        }
        set {
            if _configuration == newValue {
                return
            }
            let oldConfiguration = _configuration
            _configuration = newValue
            if _rootTransform == nil {
                // prepareInitialFrame has not been called yet, nothing more to do for now.
                return
            }
            if oldConfiguration == nil || configuration.shouldUpdateMatrix(oldConfiguration!) {
                replaceRootLayer(_updateMatricesAndCreateNewRootLayer())
            }
            assert(_rootTransform != nil)
            markNeedsLayout()
        }
    }
    private var _configuration: RenderViewConfiguration?

    /// Whether a `configuration` has been set.
    ///
    /// This must be true before calling `prepareInitialFrame`.
    ///
    /// **Dart Source:** `view.dart:195-196`
    public var hasConfiguration: Bool { _configuration != nil }

    // MARK: - Constraints

    /// Returns the logical constraints from the current configuration.
    ///
    /// **Dart Source:** `view.dart:198-205`
    public override var constraints: Constraints {
        if !hasConfiguration {
            fatalError(
                "Constraints are not available because RenderView has not been given a configuration yet."
            )
        }
        return configuration.logicalConstraints
    }

    /// Convenience accessor for the box constraints from configuration.
    private var boxConstraints: BoxConstraints {
        return configuration.logicalConstraints
    }

    // MARK: - FlutterView

    /// The `FlutterView` into which this `RenderView` will render.
    ///
    /// **Dart Source:** `view.dart:208-209`
    public var flutterView: FlutterView { _view }
    private let _view: FlutterView

    // MARK: - System UI

    /// Whether Flutter should automatically compute the desired system UI.
    ///
    /// When this setting is enabled, Flutter will hit-test the layer tree at the
    /// top and bottom of the screen on each frame looking for an
    /// `AnnotatedRegionLayer` with an instance of a `SystemUiOverlayStyle`.
    ///
    /// Setting this to false does not cause previous automatic adjustments to be
    /// reset, nor does setting it to true cause the app to update immediately.
    ///
    /// **Dart Source:** `view.dart:235`
    public var automaticSystemUiAdjustment: Bool = true

    // MARK: - Initial Frame

    /// Bootstrap the rendering pipeline by preparing the first frame.
    ///
    /// This should only be called once. It is typically called immediately after
    /// setting the `configuration` the first time. The `configuration` must have
    /// been set before calling this method, and the `RenderView` must have been
    /// attached to a `PipelineOwner` using `attach`.
    ///
    /// This does not actually schedule the first frame. Call
    /// `PipelineOwner.requestVisualUpdate` on the `owner` to do that.
    ///
    /// This method calls `scheduleInitialLayout` and `scheduleInitialPaint`.
    ///
    /// **Dart Source:** `view.dart:252-265`
    public func prepareInitialFrame() {
        assert(
            _owner != nil,
            "attach the RenderView to a PipelineOwner before calling prepareInitialFrame"
        )
        assert(
            _rootTransform == nil,
            "prepareInitialFrame must only be called once"
        )
        assert(hasConfiguration, "set a configuration before calling prepareInitialFrame")
        scheduleInitialLayout()
        scheduleInitialPaint(_updateMatricesAndCreateNewRootLayer())
        assert(_rootTransform != nil)
    }

    // MARK: - Root Transform

    /// The transform matrix that maps from logical to physical coordinates.
    ///
    /// **Dart Source:** `view.dart:267`
    private var _rootTransform: Matrix4?

    /// Updates the root transform and creates a new `TransformLayer` root layer.
    ///
    /// **Dart Source:** `view.dart:269-276`
    private func _updateMatricesAndCreateNewRootLayer() -> TransformLayer {
        assert(hasConfiguration)
        _rootTransform = configuration.toMatrix()
        let rootLayer = TransformLayer(transform: _rootTransform)
        rootLayer.attach(self)
        assert(_rootTransform != nil)
        return rootLayer
    }

    // MARK: - Layout Stubs

    /// Schedules the initial layout for this render object.
    ///
    /// This is called once during `prepareInitialFrame` to mark this render
    /// object as needing layout and register it with the pipeline owner.
    ///
    /// **Dart Source:** `object.dart` (RenderObject.scheduleInitialLayout)
    private func scheduleInitialLayout() {
        needsLayout = true
        _owner?._nodesNeedingLayout.append(self)
    }

    /// Schedules the initial paint using the provided root layer.
    ///
    /// **Dart Source:** `object.dart` (RenderObject.scheduleInitialPaint)
    private func scheduleInitialPaint(_ rootLayer: ContainerLayer) {
        _layer = rootLayer
        needsPaint = true
        _owner?._nodesNeedingPaint.append(self)
    }

    /// Replaces the current root layer with the given layer.
    ///
    /// **Dart Source:** `object.dart` (RenderObject.replaceRootLayer)
    private func replaceRootLayer(_ rootLayer: ContainerLayer) {
        _layer = rootLayer
        markNeedsPaint()
    }

    // MARK: - Layer

    /// The composited layer for this render view.
    ///
    /// Since `RenderView` is always a repaint boundary, it always has its own
    /// layer. This property is nil before `prepareInitialFrame` is called.
    ///
    /// **Dart Source:** `object.dart` (RenderObject.layer)
    public var layer: ContainerLayer? {
        get { _layer }
        set { _layer = newValue }
    }

    // MARK: - Layout

    /// We never call layout() on this class, so this should never get
    /// checked. (This class is laid out using `scheduleInitialLayout()`.)
    ///
    /// **Dart Source:** `view.dart:282-283`
    public func debugAssertDoesMeetConstraints() {
        assert(false)
    }

    /// **Dart Source:** `view.dart:286-288`
    public override func performResize() {
        assert(false)
    }

    /// Performs layout on this render view and its child.
    ///
    /// The child is laid out with the constraints from the configuration.
    /// If the constraints are not tight and the child is present, the
    /// view's size is determined by the child's size. Otherwise, the
    /// smallest size satisfying the constraints is used.
    ///
    /// **Dart Source:** `view.dart:291-298`
    public override func performLayout() {
        assert(_rootTransform != nil)
        let sizedByChild = !boxConstraints.isTight
        child?.layout(boxConstraints, parentUsesSize: sizedByChild)
        size = sizedByChild && child != nil ? child!.size : boxConstraints.smallest
        assert(size.isFinite)
        assert(boxConstraints.isSatisfiedBy(size))
    }

    // MARK: - Hit Testing

    /// Determines the set of render objects located at the given position.
    ///
    /// Returns true if the given point is contained in this render object or one
    /// of its descendants. Adds any render objects that contain the point to the
    /// given hit test result.
    ///
    /// The `position` argument is in the coordinate system of the render view,
    /// which is to say, in logical pixels.
    ///
    /// **Dart Source:** `view.dart:310-314`
    public func hitTest(_ result: HitTestResult, position: Offset) -> Bool {
        _ = child?.hitTest(BoxHitTestResult(wrapping: result), position: position)
        result.add(HitTestEntry(AnyHitTestTarget(self)))
        return true
    }

    // MARK: - Repaint Boundary

    /// The render view is always a repaint boundary.
    ///
    /// **Dart Source:** `view.dart:317-318`
    public override var isRepaintBoundary: Bool { true }

    // MARK: - Paint

    /// Paints this render view's child into the given context.
    ///
    /// In debug mode, also invokes any registered debug paint callbacks.
    ///
    /// **Dart Source:** `view.dart:320-333`
    public override func paint(_ context: PaintingContext, _ offset: Offset) {
        if let child = child {
            context.paintChild(child, offset)
        }
        assert({
            let localCallbacks = Array(RenderView._debugPaintCallbacks)
            for paintCallback in localCallbacks {
                if RenderView._debugPaintCallbacks.contains(where: { $0 as AnyObject === paintCallback as AnyObject }) {
                    paintCallback(context, offset, self)
                }
            }
            return true
        }())
    }

    // MARK: - Paint Transform

    /// Applies the root transform to the given matrix.
    ///
    /// **Dart Source:** `view.dart:336-339`
    public override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        assert(_rootTransform != nil)
        transform = transform * _rootTransform!
        super.applyPaintTransform(child, &transform)
    }

    // MARK: - Compositing

    /// Texture ids present in this view's most recently composited scene.
    /// External texture content (a client buffer commit, a child app frame)
    /// updates with no widget change, so the pipeline's dirty flags cannot
    /// see it; the frame driver uses this set to re-composite exactly the
    /// views whose scenes contain a texture that just updated.
    public private(set) var sceneTextureIds: Set<Int64> = []

    /// Uploads the composited layer tree to the engine.
    ///
    /// Actually causes the output of the rendering pipeline to appear on screen.
    ///
    /// Before calling this method, the `owner` must be set by calling `attach`,
    /// the `configuration` must be set to a non-nil value, and the
    /// `prepareInitialFrame` method must have been called.
    ///
    /// **Dart Source:** `view.dart:349-378`
    public func compositeFrame() {
        if !kReleaseMode {
            FlutterTimeline.startSync("COMPOSITING")
        }
        defer {
            if !kReleaseMode {
                FlutterTimeline.finishSync()
            }
        }

        assert(hasConfiguration, "set the RenderView configuration before calling compositeFrame")
        assert(_rootTransform != nil, "call prepareInitialFrame before calling compositeFrame")
        assert(layer != nil, "call prepareInitialFrame before calling compositeFrame")
        let builder = NativeSceneBuilder()
        let scene = layer!.buildScene(builder)
        sceneTextureIds = builder.addedTextureIds
        // Note: automaticSystemUiAdjustment / _updateSystemChrome omitted.
        // That functionality depends on SystemChrome, AnnotatedRegionLayer.find,
        // defaultTargetPlatform, and other types not yet fully available.
        assert(configuration.logicalConstraints.isSatisfiedBy(size))
        _view.render(scene, size: configuration.toPhysicalSize(size))
        scene.dispose()
    }

    // MARK: - Semantics

    /// Sends the provided `SemanticsUpdate` to the `FlutterView` associated with
    /// this `RenderView`.
    ///
    /// A `SemanticsUpdate` is produced by a `SemanticsOwner` during the
    /// `flushSemantics` phase.
    ///
    /// **Dart Source:** `view.dart:385-387`
    public func updateSemantics(_ update: SemanticsUpdate) {
        _view.updateSemantics(update)
    }

    // MARK: - Paint Bounds / Semantic Bounds

    /// Returns the paint bounds of this render view in physical pixels.
    ///
    /// **Dart Source:** `view.dart:494`
    public override var paintBounds: Rect {
        Offset.zero & (size * configuration.devicePixelRatio)
    }

    /// Returns the semantic bounds of this render view.
    ///
    /// **Dart Source:** `view.dart:497-499`
    public var semanticBounds: Rect {
        assert(_rootTransform != nil)
        return MatrixUtils.transformRect(_rootTransform!, Offset.zero & size)
    }

    // MARK: - Debug Paint Callbacks

    /// Static list of debug paint callbacks.
    ///
    /// **Dart Source:** `view.dart:537`
    nonisolated(unsafe) private static var _debugPaintCallbacks: [DebugPaintCallback] = []

    /// Registers a `DebugPaintCallback` that is called every time a `RenderView`
    /// repaints in debug mode.
    ///
    /// The callback may paint a debug overlay on top of the content of the
    /// `RenderView` provided to the callback. Callbacks are invoked in the
    /// order they were registered in.
    ///
    /// Does nothing in release mode.
    ///
    /// **Dart Source:** `view.dart:552-557`
    public static func debugAddPaintCallback(_ callback: @escaping DebugPaintCallback) {
        assert({
            _debugPaintCallbacks.append(callback)
            return true
        }())
    }

    /// Removes a callback registered with `debugAddPaintCallback`.
    ///
    /// It does not schedule a frame to repaint the `RenderView`s without the
    /// overlay painted by the removed callback. It is up to the owner of the
    /// callback to call `markNeedsPaint` on the relevant `RenderView`s to
    /// repaint them without the overlay.
    ///
    /// Does nothing in release mode.
    ///
    /// **Dart Source:** `view.dart:567-572`
    public static func debugRemovePaintCallback(_ callback: @escaping DebugPaintCallback) {
        assert({
            _debugPaintCallbacks.removeAll(where: { $0 as AnyObject === callback as AnyObject })
            return true
        }())
    }

    // MARK: - Debug

    /// Fills the given properties builder with diagnostic information.
    ///
    /// **Dart Source:** `view.dart:502-535`
    public func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        properties.add(
            DiagnosticsProperty<Size>(
                "view size",
                _view.physicalSize,
                tooltip: "in physical pixels"
            )
        )
        properties.add(
            DoubleProperty(
                "device pixel ratio",
                _view.devicePixelRatio,
                tooltip: "physical pixels per logical pixel"
            )
        )
        properties.add(
            DiagnosticsProperty<RenderViewConfiguration>(
                "configuration",
                configuration,
                tooltip: "in logical pixels"
            )
        )
    }
}

// MARK: - Layer BuildScene Extension

/// Extension on `ContainerLayer` to provide `buildScene` for compositing.
///
/// In Dart, this is defined on `OffsetLayer` (a subclass of `ContainerLayer`).
/// Since we don't yet have a full `OffsetLayer`, this is provided as an
/// extension on `ContainerLayer` for use by `RenderView.compositeFrame`.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart` (OffsetLayer.buildScene)
extension ContainerLayer {

    /// Builds a `Scene` by adding this layer and its subtree to the given
    /// scene builder.
    ///
    /// The returned `Scene` can be rendered using `FlutterView.render`.
    public func buildScene(_ builder: any SceneBuilder) -> Scene {
        updateSubtreeNeedsAddToScene()
        addToScene(builder)
        // Clear the needsAddToScene flag since we just composed.
        _needsAddToScene = false
        return builder.build()
    }
}


// MARK: - Debug Helper

/// Dumps the layer tree starting from the given `RenderView`.
///
/// This is a debug utility equivalent to the private `_debugDumpLayerTree`
/// in the Dart source.
///
/// **Dart Source:** `view.dart` (private helper, not a type)
public func debugDumpLayerTree(_ renderView: RenderView) {
    guard let layer = renderView.layer else {
        debugPrint("RenderView has no layer tree.", nil)
        return
    }
    debugPrint(layer.toStringShort(), nil)
}
