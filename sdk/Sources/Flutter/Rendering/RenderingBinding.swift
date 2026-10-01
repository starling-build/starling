// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The glue between the render trees and the Flutter engine.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/binding.dart`

import FlutterSwiftBridge

// MARK: - PipelineManifold Protocol

/// Interface for a pipeline manifold that manages the rendering pipeline.
///
/// A `PipelineManifold` is responsible for requesting visual updates and
/// tracking whether semantics are enabled. It serves as the intermediary
/// between `PipelineOwner` trees and the binding that drives frame production.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/object.dart`
/// **Original Name:** `PipelineManifold`
///
/// NOTE: This protocol is defined here as a stub because PipelineManifold
/// is referenced in binding.dart but not yet fully migrated from object.dart.
/// When the full PipelineOwner migration is complete, this can be consolidated.
public protocol PipelineManifold: Listenable {
    /// Requests a visual update (i.e., schedules a new frame).
    ///
    /// Called by `PipelineOwner` when the render tree needs to produce a new frame.
    func requestVisualUpdate()

    /// Whether the semantics system is currently enabled.
    var semanticsEnabled: Bool { get }
}

// MARK: - RendererBinding

/// The glue between the render trees and the Flutter engine.
///
/// The `RendererBinding` manages multiple independent render trees. Each render
/// tree is rooted in a `RenderView` that must be added to the binding via
/// `addRenderView` to be considered during frame production, hit testing, etc.
/// Furthermore, the render tree must be managed by a `PipelineOwner` that is
/// part of the pipeline owner tree rooted at `rootPipelineOwner`.
///
/// Adding `PipelineOwner`s and `RenderView`s to this binding in the way
/// described above is left as a responsibility for a higher level abstraction.
/// The widgets library, for example, introduces the `View` widget, which
/// registers its `RenderView` and `PipelineOwner` with this binding.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/binding.dart`
/// **Original Name:** `RendererBinding` (mixin on BindingBase, ServicesBinding,
///   SchedulerBinding, GestureBinding, SemanticsBinding, HitTestable)
/// **Lines:** 44-677
///
/// DIFFERENCE FROM DART: Dart uses `mixin RendererBinding on BindingBase, ...`.
/// Swift does not support mixins. This is implemented as an open class that
/// extends `GestureBinding` (which extends `BindingBase`).
/// REASON: Swift class hierarchy is the closest equivalent to Dart's mixin
/// linearization. The `GestureBinding` base provides hit testing infrastructure.
open class RendererBinding: GestureBinding {

    // MARK: - Singleton

    /// The current `RendererBinding`, if one has been created.
    ///
    /// Provides access to the features exposed by this binding. The binding must
    /// be initialized before using this getter; this is typically done by calling
    /// `runApp` or `WidgetsFlutterBinding.ensureInitialized`.
    ///
    /// **Dart Source:** `binding.dart:74-75`
    public static var rendererInstance: RendererBinding {
        return BindingBase.checkInstance(_rendererInstance)
    }
    nonisolated(unsafe) internal static var _rendererInstance: RendererBinding?

    // MARK: - Initialization

    /// **Dart Source:** `binding.dart:53-67`
    public override init() {
        super.init()
    }

    /// **Dart Source:** `binding.dart:53-67`
    open override func initInstances() {
        super.initInstances()
        RendererBinding._rendererInstance = self
        _rootPipelineOwner = createRootPipelineOwner()
        // In Dart, platformDispatcher callbacks are set here:
        //   ..onMetricsChanged = handleMetricsChanged
        //   ..onTextScaleFactorChanged = handleTextScaleFactorChanged
        //   ..onPlatformBrightnessChanged = handlePlatformBrightnessChanged
        // TODO: Wire up platformDispatcher callbacks when SchedulerBinding is available.
        initMouseTracker()
        rootPipelineOwner.attach(_manifold)
    }

    /// **Dart Source:** `binding.dart:78-225`
    open override func initServiceExtensions() {
        super.initServiceExtensions()
        // Service extensions are Dart VM-specific and are stubs in Swift.
        // The debug flags (debugPaintSizeEnabled, debugRepaintRainbowEnabled, etc.)
        // are defined in RenderingDebug.swift and can be toggled directly in Swift.
    }

    // MARK: - Pipeline Manifold

    /// The pipeline manifold that connects the pipeline owner tree to this binding.
    ///
    /// **Dart Source:** `binding.dart:227`
    private lazy var _manifold: BindingPipelineManifold = BindingPipelineManifold(self)

    // MARK: - Mouse Tracker

    /// The object that manages state about currently connected mice, for hover
    /// notification.
    ///
    /// **Dart Source:** `binding.dart:231-232`
    public var mouseTracker: MouseTracker { _mouseTracker! }
    private var _mouseTracker: MouseTracker?

    /// Creates a `MouseTracker` which manages state about currently connected
    /// mice, for hover notification.
    ///
    /// Used by testing framework to reinitialize the mouse tracker between tests.
    ///
    /// **Dart Source:** `binding.dart:453-462`
    public func initMouseTracker(_ tracker: MouseTracker? = nil) {
        _mouseTracker?.dispose()
        _mouseTracker = tracker ?? MouseTracker({ [weak self] position, viewId in
            let result = HitTestResult()
            self?.hitTestInView(result: result, position: position, viewId: viewId)
            return result
        })
    }

    // MARK: - Deprecated pipelineOwner

    /// Deprecated pipeline owner.
    ///
    /// This is typically the owner of the render tree bootstrapped by `runApp`
    /// and rooted in `renderView`.
    ///
    /// **Dart Source:** `binding.dart:263-273`
    public private(set) lazy var deprecatedPipelineOwner: PipelineOwner = PipelineOwner()

    // MARK: - Root Pipeline Owner

    /// Creates the `PipelineOwner` that serves as the root of the pipeline owner
    /// tree (`rootPipelineOwner`).
    ///
    /// By default, the root pipeline owner is not setup to manage a render tree
    /// and its `rootNode` must not be assigned. If necessary,
    /// `createRootPipelineOwner` may be overridden to create a root pipeline
    /// owner configured to manage its own render tree.
    ///
    /// **Dart Source:** `binding.dart:317-319`
    open func createRootPipelineOwner() -> PipelineOwner {
        return DefaultRootPipelineOwner()
    }

    /// The `PipelineOwner` that is the root of the PipelineOwner tree.
    ///
    /// **Dart Source:** `binding.dart:324-325`
    public var rootPipelineOwner: PipelineOwner { _rootPipelineOwner }
    private var _rootPipelineOwner: PipelineOwner!

    // MARK: - Render Views

    /// The `RenderView`s managed by this binding.
    ///
    /// A `RenderView` is added by `addRenderView` and removed by `removeRenderView`.
    ///
    /// **Dart Source:** `binding.dart:330-331`
    public var renderViews: [RenderView] { Array(_viewIdToRenderView.values) }
    private var _viewIdToRenderView: [Int: RenderView] = [:]

    /// Adds a `RenderView` to this binding.
    ///
    /// The binding will interact with the `RenderView` in the following ways:
    ///
    ///  * setting and updating `RenderView.configuration`,
    ///  * calling `RenderView.compositeFrame` when it is time to produce a new
    ///    frame, and
    ///  * forwarding relevant pointer events to the `RenderView` for hit testing.
    ///
    /// To remove a `RenderView` from the binding, call `removeRenderView`.
    ///
    /// **Dart Source:** `binding.dart:343-349`
    public func addRenderView(_ view: RenderView) {
        let viewId = view.flutterView.viewId
        assert(_viewIdToRenderView[viewId] == nil, "RenderView with viewId \(viewId) is already registered.")
        _viewIdToRenderView[viewId] = view
        view.configuration = createViewConfigurationFor(view)
    }

    /// Removes a `RenderView` previously added with `addRenderView` from the
    /// binding.
    ///
    /// **Dart Source:** `binding.dart:353-357`
    public func removeRenderView(_ view: RenderView) {
        let viewId = view.flutterView.viewId
        assert(_viewIdToRenderView[viewId] === view)
        _viewIdToRenderView.removeValue(forKey: viewId)
    }

    /// Returns a `ViewConfiguration` configured for the provided `RenderView`
    /// based on the current environment.
    ///
    /// This is called during `addRenderView` and also in response to changes to
    /// the system metrics to update all `renderViews` added to the binding.
    ///
    /// Bindings can override this method to change what size or device pixel
    /// ratio the `RenderView` will use. For example, the testing framework uses
    /// this to force the display into 800x600 when a test is run on the device
    /// using `flutter run`.
    ///
    /// **Dart Source:** `binding.dart:370-372`
    open func createViewConfigurationFor(_ renderView: RenderView) -> RenderViewConfiguration {
        return RenderViewConfiguration.fromView(renderView.flutterView)
    }

    /// Create a `SceneBuilder`.
    ///
    /// This hook enables test bindings to instrument the rendering layer.
    ///
    /// **Dart Source:** `binding.dart:380`
    open func createSceneBuilder() -> any SceneBuilder {
        return NativeSceneBuilder()
    }

    /// Create a `PictureRecorder`.
    ///
    /// This hook enables test bindings to instrument the rendering layer.
    ///
    /// **Dart Source:** `binding.dart:389`
    open func createPictureRecorder() -> any PictureRecorder {
        return PictureRecorders.create()
    }

    // MARK: - Metrics / Platform Callbacks

    /// Called when the system metrics change.
    ///
    /// See `PlatformDispatcher.onMetricsChanged`.
    ///
    /// **Dart Source:** `binding.dart:404-413`
    open func handleMetricsChanged() {
        var forceFrame = false
        for view in renderViews {
            forceFrame = forceFrame || view.child != nil
            view.configuration = createViewConfigurationFor(view)
        }
        if forceFrame {
            scheduleForcedFrame()
        }
    }

    /// Called when the platform text scale factor changes.
    ///
    /// See `PlatformDispatcher.onTextScaleFactorChanged`.
    ///
    /// **Dart Source:** `binding.dart:419`
    open func handleTextScaleFactorChanged() {}

    /// Called when the platform brightness changes.
    ///
    /// **Dart Source:** `binding.dart:446`
    open func handlePlatformBrightnessChanged() {}

    // MARK: - Event Dispatch

    /// Dispatches a pointer event, updating the mouse tracker as needed.
    ///
    /// **Dart Source:** `binding.dart:465-474`
    open override func _dispatchEvent(_ event: PointerEvent, hitTestResult: HitTestResult?) {
        _mouseTracker!.updateWithEvent(
            event,
            // When the button is pressed, normal hit test uses a cached
            // result, but MouseTracker requires that the hit test is re-executed to
            // update the hovering events.
            hitTestResult: event is PointerMoveEvent ? nil : hitTestResult
        )
        super._dispatchEvent(event, hitTestResult: hitTestResult)
    }

    // MARK: - Semantics Action

    /// Performs a semantics action on the render view that owns the given node.
    ///
    /// **Dart Source:** `binding.dart:477-486`
    open func performSemanticsAction(_ action: SemanticsActionEvent) {
        // Due to the asynchronicity in some screen readers (they may not have
        // processed the latest semantics update yet) this code is more forgiving
        // and actions for views/nodes that no longer exist are gracefully ignored.
        // TODO: Full implementation requires PipelineOwner.semanticsOwner
    }

    // MARK: - Frame Drawing

    /// Debug flag for mouse tracker update scheduling.
    ///
    /// **Dart Source:** `binding.dart:499`
    private var _debugMouseTrackerUpdateScheduled = false

    /// First frame deferral count.
    ///
    /// **Dart Source:** `binding.dart:516`
    private var _firstFrameDeferredCount = 0

    /// Whether the first frame has been sent to the engine.
    ///
    /// **Dart Source:** `binding.dart:517`
    private var _firstFrameSent = false

    /// Whether frames produced by `drawFrame` are sent to the engine.
    ///
    /// If false the framework will do all the work to produce a frame,
    /// but the frame is never sent to the engine to actually appear on screen.
    ///
    /// **Dart Source:** `binding.dart:528`
    public var sendFramesToEngine: Bool {
        _firstFrameSent || _firstFrameDeferredCount == 0
    }

    /// Tell the framework to not send the first frames to the engine until there
    /// is a corresponding call to `allowFirstFrame`.
    ///
    /// Call this to perform asynchronous initialization work before the first
    /// frame is rendered (which takes down the splash screen). The framework
    /// will still do all the work to produce frames, but those frames are never
    /// sent to the engine and will not appear on screen.
    ///
    /// Calling this has no effect after the first frame has been sent to the
    /// engine.
    ///
    /// **Dart Source:** `binding.dart:540-543`
    public func deferFirstFrame() {
        assert(_firstFrameDeferredCount >= 0)
        _firstFrameDeferredCount += 1
    }

    /// Called after `deferFirstFrame` to tell the framework that it is ok to
    /// send the first frame to the engine now.
    ///
    /// For best performance, this method should only be called while the
    /// `schedulerPhase` is `SchedulerPhase.idle`.
    ///
    /// This method may only be called once for each corresponding call
    /// to `deferFirstFrame`.
    ///
    /// **Dart Source:** `binding.dart:553-562`
    public func allowFirstFrame() {
        assert(_firstFrameDeferredCount > 0)
        _firstFrameDeferredCount -= 1
        // Always schedule a warm up frame even if the deferral count is not down to
        // zero yet since the removal of a deferral may uncover new deferrals that
        // are lower in the widget tree.
        if !_firstFrameSent {
            scheduleWarmUpFrame()
        }
    }

    /// Call this to pretend that no frames have been sent to the engine yet.
    ///
    /// This is useful for tests that want to call `deferFirstFrame` and
    /// `allowFirstFrame` since those methods only have an effect if no frames
    /// have been sent to the engine yet.
    ///
    /// **Dart Source:** `binding.dart:569-571`
    public func resetFirstFrameSent() {
        _firstFrameSent = false
    }

    /// Pump the rendering pipeline to generate a frame.
    ///
    /// This method is called by `handleDrawFrame`, which itself is called
    /// automatically by the engine when it is time to lay out and paint a frame.
    ///
    /// Each frame consists of the following phases:
    ///
    /// 1. The animation phase
    /// 2. Microtasks
    /// 3. The layout phase: All dirty `RenderObject`s are laid out.
    /// 4. The compositing bits phase
    /// 5. The paint phase: All dirty `RenderObject`s are repainted.
    /// 6. The compositing phase: The layer tree is turned into a `Scene`.
    /// 7. The semantics phase: All dirty `RenderObject`s have their semantics updated.
    /// 8. The finalization phase
    ///
    /// For more details on steps 3-7, see `PipelineOwner`.
    ///
    /// **Dart Source:** `binding.dart:628-639`
    open func drawFrame() {
        rootPipelineOwner.flushLayout()
        rootPipelineOwner.flushCompositingBits()
        rootPipelineOwner.flushPaint()
        if sendFramesToEngine {
            for renderView in renderViews {
                renderView.compositeFrame() // this sends the bits to the GPU
            }
            rootPipelineOwner.flushSemantics() // this sends the semantics to the OS.
            _firstFrameSent = true
        }
    }

    /// **Dart Source:** `binding.dart:642-658`
    open override func performReassemble() async {
        await super.performReassemble()
        if !kReleaseMode {
            FlutterTimeline.startSync("Preparing Hot Reload (layout)")
        }
        defer {
            if !kReleaseMode {
                FlutterTimeline.finishSync()
            }
        }
        for renderView in renderViews {
            // In Dart, renderView.reassemble() is called here.
            // Since RenderObject.reassemble() is not yet defined as an overridable
            // method, we directly mark the render view as needing layout and paint.
            renderView.markNeedsLayout()
            renderView.markNeedsPaint()
        }
        scheduleWarmUpFrame()
        // In Dart: await endOfFrame
        // TODO: Await endOfFrame once SchedulerBinding is fully available.
    }

    // MARK: - Hit Testing

    /// Determines the set of render objects located at the given position in the
    /// specified view.
    ///
    /// **Dart Source:** `binding.dart:661-664`
    open override func hitTestInView(result: HitTestResult, position: Offset, viewId: Int) {
        _ = _viewIdToRenderView[viewId]?.hitTest(result, position: position)
        super.hitTestInView(result: result, position: position, viewId: viewId)
    }

    // MARK: - Force Repaint

    /// Forces a repaint of all render objects in all render views.
    ///
    /// In the Dart source, this walks the full render tree using
    /// `RenderObject.visitChildren`. Since `visitChildren` is not yet an
    /// overridable method on `RenderObject` (it will be when the full
    /// RenderObject migration is complete), we directly mark each render
    /// view's child as needing paint.
    ///
    /// **Dart Source:** `binding.dart:666-676`
    private func _forceRepaint() {
        for renderView in renderViews {
            if let child = renderView.child {
                child.markNeedsPaint()
            }
        }
        // In Dart: return endOfFrame
        // TODO: Full tree walk using visitChildren and return endOfFrame Future
        //       when RenderObject and SchedulerBinding are fully migrated.
    }

    // MARK: - Scheduler Stubs

    /// Stub for `SchedulerBinding.scheduleForcedFrame`.
    ///
    /// Schedules a forced frame. The full implementation requires SchedulerBinding.
    ///
    /// TODO: Replace with real SchedulerBinding integration.
    open func scheduleForcedFrame() {
        // Stub: SchedulerBinding is not yet migrated.
    }

    /// Stub for `SchedulerBinding.scheduleWarmUpFrame`.
    ///
    /// Schedules a warm-up frame. The full implementation requires SchedulerBinding.
    ///
    /// TODO: Replace with real SchedulerBinding integration.
    open func scheduleWarmUpFrame() {
        // Stub: SchedulerBinding is not yet migrated.
    }

    /// Stub for `SchedulerBinding.ensureVisualUpdate`.
    ///
    /// Ensures that a new frame will be produced.
    ///
    /// DIFFERENCE FROM DART: `SchedulerBinding.ensureVisualUpdate` consults
    /// `schedulerPhase`; this port has no scheduler phases, so it asks the
    /// platform for a frame directly, which is idempotent within a frame.
    open func ensureVisualUpdate() {
        PlatformDispatcher.instance.scheduleFrame()
    }

    /// Stub for `SchedulerBinding.addPersistentFrameCallback`.
    ///
    /// TODO: Replace with real SchedulerBinding integration.
    open func addPersistentFrameCallback(_ callback: @escaping (Duration) -> Void) {
        // Stub: SchedulerBinding is not yet migrated.
    }

    /// Schedule a callback for the end of the next frame — after build,
    /// layout, paint and composite, with the frame's timestamp. The queue
    /// lives on `FrameCallbackScheduler` and is drained by the Adapter's
    /// frame closure; a frame is requested so the callback is not left
    /// waiting on unrelated damage.
    ///
    /// **Dart Source:** `SchedulerBinding.addPostFrameCallback`
    /// (`scheduler/binding.dart`)
    open func addPostFrameCallback(
        _ callback: @escaping (Duration) -> Void,
        debugLabel: String? = nil
    ) {
        FrameCallbackScheduler.shared.addPostFrameCallback(callback)
        ensureVisualUpdate()
    }

    // MARK: - Semantics Stubs

    /// Whether semantics are currently enabled.
    ///
    /// Stub for `SemanticsBinding.semanticsEnabled`.
    ///
    /// TODO: Replace with real SemanticsBinding integration.
    open var semanticsEnabled: Bool { false }

    /// Adds a listener that is called when `semanticsEnabled` changes.
    ///
    /// Stub for `SemanticsBinding.addSemanticsEnabledListener`.
    ///
    /// TODO: Replace with real SemanticsBinding integration.
    open func addSemanticsEnabledListener(_ listener: @escaping VoidCallback) {
        // Stub: SemanticsBinding is not yet migrated.
    }

    /// Removes a listener previously added with `addSemanticsEnabledListener`.
    ///
    /// Stub for `SemanticsBinding.removeSemanticsEnabledListener`.
    ///
    /// TODO: Replace with real SemanticsBinding integration.
    open func removeSemanticsEnabledListener(_ listener: @escaping VoidCallback) {
        // Stub: SemanticsBinding is not yet migrated.
    }
}

// MARK: - PipelineOwner Extensions for Binding

/// Extensions to `PipelineOwner` required by the rendering binding.
///
/// These stub methods will be fully implemented when PipelineOwner is fully
/// migrated. They provide the flush methods called during frame production.
extension PipelineOwner {

    /// Attaches this pipeline owner to the given manifold.
    ///
    /// **Dart Source:** `object.dart` (PipelineOwner.attach)
    ///
    /// TODO: Full implementation when PipelineOwner is fully migrated.
    public func attach(_ manifold: any PipelineManifold) {
        // Stub: PipelineOwner is not yet fully migrated.
    }

    // flushLayout() is now implemented directly on PipelineOwner in RenderObject.swift.

    /// Updates the compositing bits for all dirty render objects managed by
    /// this owner and its descendants.
    ///
    /// **Dart Source:** `object.dart` (PipelineOwner.flushCompositingBits)
    ///
    /// TODO: Full implementation when PipelineOwner is fully migrated.
    public func flushCompositingBits() {
        // Stub: PipelineOwner is not yet fully migrated.
    }

    // flushPaint() is now implemented directly on PipelineOwner in RenderObject.swift.

    /// Flushes semantics for all dirty render objects managed by this owner
    /// and its descendants.
    ///
    /// **Dart Source:** `object.dart` (PipelineOwner.flushSemantics)
    ///
    /// TODO: Full implementation when PipelineOwner is fully migrated.
    public func flushSemantics() {
        // Stub: PipelineOwner is not yet fully migrated.
    }
}

// MARK: - SemanticsActionEvent Stub

/// Represents a semantics action event dispatched by the platform.
///
/// **Dart Source:** `packages/flutter/lib/src/semantics/semantics_event.dart`
///
/// NOTE: This is a minimal stub. The full implementation will be migrated
/// with the semantics binding.
public struct SemanticsActionEvent {
    /// The identifier of the view this action targets.
    public let viewId: Int

    /// The identifier of the semantics node this action targets.
    public let nodeId: Int

    /// The type of semantics action.
    public let type: SemanticsAction

    /// Optional arguments for the action.
    public let arguments: Any?

    public init(viewId: Int, nodeId: Int, type: SemanticsAction, arguments: Any? = nil) {
        self.viewId = viewId
        self.nodeId = nodeId
        self.type = type
        self.arguments = arguments
    }
}

// MARK: - BindingPipelineManifold

/// A `PipelineManifold` implementation that is backed by the `RendererBinding`.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/binding.dart`
/// **Original Name:** `_BindingPipelineManifold`
/// **Lines:** 817-840
///
/// DIFFERENCE FROM DART: Renamed from `_BindingPipelineManifold` to
/// `BindingPipelineManifold` with `internal` access.
/// REASON: Swift does not support file-private classes that need to be
/// referenced within the module. The underscore prefix indicates it is an
/// internal implementation detail.
class BindingPipelineManifold: ChangeNotifier, PipelineManifold {

    /// Creates a `BindingPipelineManifold` backed by the given binding.
    ///
    /// **Dart Source:** `binding.dart:818-823`
    init(_ binding: RendererBinding) {
        self._binding = binding
        super.init()
        _binding.addSemanticsEnabledListener { [weak self] in
            self?.notifyListeners()
        }
    }

    /// The binding this manifold is backed by.
    ///
    /// **Dart Source:** `binding.dart:825`
    private let _binding: RendererBinding

    /// Requests a visual update by forwarding to the binding's `ensureVisualUpdate`.
    ///
    /// **Dart Source:** `binding.dart:828-830`
    func requestVisualUpdate() {
        _binding.ensureVisualUpdate()
    }

    /// Whether semantics are currently enabled.
    ///
    /// **Dart Source:** `binding.dart:833`
    var semanticsEnabled: Bool {
        _binding.semanticsEnabled
    }

    /// **Dart Source:** `binding.dart:836-839`
    override func dispose() {
        _binding.removeSemanticsEnabledListener(notifyListeners)
        super.dispose()
    }
}

// MARK: - DefaultRootPipelineOwner

/// A `PipelineOwner` that cannot have a root node.
///
/// This is the default root pipeline owner created by `RendererBinding`. It
/// does not manage its own render tree; instead, child pipeline owners that
/// do manage render trees are added to it.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/binding.dart`
/// **Original Name:** `_DefaultRootPipelineOwner`
/// **Lines:** 843-873
///
/// DIFFERENCE FROM DART: Renamed from `_DefaultRootPipelineOwner` to
/// `DefaultRootPipelineOwner` with `internal` access.
/// REASON: Swift does not support file-private classes.
final class DefaultRootPipelineOwner: PipelineOwner {

    /// **Dart Source:** `binding.dart:844`
    override init() {
        super.init()
    }

    // In the Dart source, this class overrides `set rootNode` to throw
    // a FlutterError. Since PipelineOwner is currently a stub, this override
    // will be added when PipelineOwner is fully migrated.
    // TODO: Override rootNode setter to throw when PipelineOwner is fully migrated.
}

// MARK: - ReusableRenderView

/// A special `RenderView` that supports being reused after disposal.
///
/// Prior to multi-view support, the `RendererBinding` would own a long-lived
/// `RenderView` that was never disposed. With multi-view support, the binding
/// no longer owns a `RenderView` and instead higher level abstractions can
/// add/remove multiple `RenderView`s. This class bridges those worlds.
///
/// Once the deprecated `RendererBinding.renderView` property is removed, this
/// class is no longer necessary.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/binding.dart`
/// **Original Name:** `_ReusableRenderView`
/// **Lines:** 893-918
///
/// DIFFERENCE FROM DART: Renamed from `_ReusableRenderView` to
/// `ReusableRenderView` with `internal` access.
/// REASON: Swift does not support file-private classes.
class ReusableRenderView: RenderView {

    /// **Dart Source:** `binding.dart:894`
    override init(
        child: RenderBox? = nil,
        configuration: RenderViewConfiguration? = nil,
        view: FlutterView
    ) {
        super.init(child: child, configuration: configuration, view: view)
    }

    /// Whether `prepareInitialFrame` has already been called.
    ///
    /// **Dart Source:** `binding.dart:896`
    private var _initialFramePrepared = false

    /// Prepares the initial frame, but only once.
    ///
    /// **Dart Source:** `binding.dart:899-905`
    public override func prepareInitialFrame() {
        if _initialFramePrepared {
            return
        }
        super.prepareInitialFrame()
        _initialFramePrepared = true
    }

    /// Schedules initial semantics, clearing existing semantics first.
    ///
    /// **Dart Source:** `binding.dart:908-911`
    public func scheduleInitialSemantics() {
        // clearSemantics() would be called here when fully implemented.
        // TODO: Call clearSemantics() and super.scheduleInitialSemantics()
        //       when semantics infrastructure is fully migrated.
    }

    /// Disposes this render view by removing its child, making it reusable.
    ///
    /// Unlike a normal `RenderView`, this does not call `super.dispose()`,
    /// allowing the render view to be reused.
    ///
    /// **Dart Source:** `binding.dart:914-917`
    public override func dispose() {
        child = nil
    }
}

// MARK: - RenderingFlutterBinding

/// A concrete binding for applications that use the Rendering framework
/// directly. This is the glue that binds the framework to the Flutter engine.
///
/// When using the rendering framework directly, this binding, or one that
/// implements the same interfaces, must be used.
///
/// You would only use this binding if you are writing to the
/// rendering layer directly. If you are writing to a higher-level
/// library, such as the Flutter Widgets library, then you would use
/// that layer's binding (see `WidgetsFlutterBinding`).
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/binding.dart`
/// **Original Name:** `RenderingFlutterBinding`
/// **Lines:** 792-814
///
/// DIFFERENCE FROM DART: In Dart, this class extends `BindingBase` with
/// mixins `GestureBinding, SchedulerBinding, ServicesBinding, SemanticsBinding,
/// PaintingBinding, RendererBinding`. In Swift, it simply extends `RendererBinding`
/// which already provides the class hierarchy.
/// REASON: Swift does not support mixins; the single-inheritance hierarchy is
/// the closest equivalent.
public class RenderingFlutterBinding: RendererBinding {

    /// Returns an instance of the binding that implements
    /// `RendererBinding`. If no binding has yet been initialized, the
    /// `RenderingFlutterBinding` class is used to create and initialize one.
    ///
    /// You need to call this method before using the rendering framework
    /// if you are using it directly. If you are using the widgets framework,
    /// see `WidgetsFlutterBinding.ensureInitialized`.
    ///
    /// **Dart Source:** `binding.dart:808-813`
    @discardableResult
    public static func ensureInitialized() -> RendererBinding {
        if RendererBinding._rendererInstance == nil {
            _ = RenderingFlutterBinding()
        }
        return RendererBinding.rendererInstance
    }
}

// MARK: - Debug Dump Functions

/// Collects textual representations of all render trees.
///
/// **Dart Source:** `binding.dart:679-687`
private func _debugCollectRenderTrees() -> String {
    if RendererBinding.rendererInstance.renderViews.isEmpty {
        return "No render tree root was added to the binding."
    }
    return RendererBinding.rendererInstance.renderViews.map { renderView in
        // In Dart, renderView.toStringDeep() is used here.
        // Since RenderObject.toStringDeep is not yet migrated, use String(describing:).
        String(describing: renderView)
    }.joined(separator: "\n\n")
}

/// Prints a textual representation of the render trees.
///
/// It prints the trees associated with every `RenderView` in
/// `RendererBinding.renderViews`, separated by two blank lines.
///
/// **Dart Source:** `binding.dart:695-697`
public func debugDumpRenderTree() {
    debugPrint(_debugCollectRenderTrees(), nil)
}

/// Collects textual representations of all layer trees.
///
/// **Dart Source:** `binding.dart:699-707`
private func _debugCollectLayerTrees() -> String {
    if RendererBinding.rendererInstance.renderViews.isEmpty {
        return "No render tree root was added to the binding."
    }
    return RendererBinding.rendererInstance.renderViews.map { renderView in
        // In Dart, renderView.debugLayer?.toStringDeep() is used here.
        // Since Layer.toStringDeep is not yet migrated, use toStringShort().
        renderView.layer?.toStringShort() ?? "Layer tree unavailable for \(renderView)."
    }.joined(separator: "\n\n")
}

/// Prints a textual representation of the layer trees.
///
/// **Dart Source:** `binding.dart:713`
public func debugDumpLayerTreeFromBinding() {
    debugPrint(_debugCollectLayerTrees(), nil)
}

/// Collects textual representations of all semantics trees.
///
/// **Dart Source:** `binding.dart:716-740`
private func _debugCollectSemanticsTrees(_ childOrder: DebugSemanticsDumpOrder) -> String {
    if RendererBinding.rendererInstance.renderViews.isEmpty {
        return "No render tree root was added to the binding."
    }
    let explanation =
        "For performance reasons, the framework only generates semantics when asked to do so by the platform.\n"
        + "Usually, platforms only ask for semantics when assistive technologies (like screen readers) are running.\n"
        + "To generate semantics, try turning on an assistive technology (like VoiceOver or TalkBack) on your device."
    var trees: [String] = []
    var printedExplanation = false
    for renderView in RendererBinding.rendererInstance.renderViews {
        // In Dart, renderView.debugSemantics?.toStringDeep(childOrder: childOrder) is used.
        // Since RenderView.debugSemantics is not yet available, we always report as unavailable.
        // TODO: Use renderView.debugSemantics?.toStringDeep(childOrder:) when available.
        var message = "Semantics not generated for \(renderView)."
        if !printedExplanation {
            printedExplanation = true
            message = "\(message)\n\(explanation)"
        }
        trees.append(message)
    }
    return trees.joined(separator: "\n\n")
}

/// Prints a textual representation of the semantics trees.
///
/// Semantics trees are only constructed when semantics are enabled. If a
/// semantics tree is not available, a notice about the missing semantics
/// tree is printed instead.
///
/// The order in which the children of a `SemanticsNode` will be printed is
/// controlled by the `childOrder` parameter.
///
/// **Dart Source:** `binding.dart:756`
public func debugDumpSemanticsTree(
    _ childOrder: DebugSemanticsDumpOrder = .traversalOrder
) {
    debugPrint(_debugCollectSemanticsTrees(childOrder), nil)
}

/// Prints a textual representation of the `PipelineOwner` tree rooted at
/// `RendererBinding.rootPipelineOwner`.
///
/// **Dart Source:** `binding.dart:762`
public func debugDumpPipelineOwnerTree() {
    debugPrint(String(describing: RendererBinding.rendererInstance.rootPipelineOwner), nil)
}
