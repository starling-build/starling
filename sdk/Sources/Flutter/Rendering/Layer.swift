// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Layer tree types for composited rendering.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`

import FlutterSwiftBridge

// MARK: - AnnotationEntry

/// Information collected for an annotation that is found in the layer tree.
///
/// See also:
///
///  * `Layer.findAnnotations`, which creates and uses objects of this class.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`
/// **Original Name:** `AnnotationEntry<T>`
/// **Lines:** 31-47
public struct AnnotationEntry<T> {
    /// The annotation object that is found.
    ///
    /// **Dart Source:** `layer.dart:37`
    public let annotation: T

    /// The target location described by the local coordinate space of the
    /// annotation object.
    ///
    /// **Dart Source:** `layer.dart:41`
    public let localPosition: Offset

    /// Create an entry of found annotation by providing the object and related
    /// information.
    ///
    /// **Dart Source:** `layer.dart:34`
    public init(annotation: T, localPosition: Offset) {
        self.annotation = annotation
        self.localPosition = localPosition
    }

    /// A brief description of this entry.
    ///
    /// **Dart Source:** `layer.dart:44-46`
    public var description: String {
        return "AnnotationEntry(annotation: \(annotation), localPosition: \(localPosition))"
    }
}

// MARK: - AnnotationResult

/// Information collected about a list of annotations that are found in the
/// layer tree.
///
/// See also:
///
///  * `AnnotationEntry`, which are members of this class.
///  * `Layer.findAllAnnotations`, and `Layer.findAnnotations`, which create and
///    use an object of this class.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`
/// **Original Name:** `AnnotationResult<T>`
/// **Lines:** 57-81
public class AnnotationResult<T> {
    /// **Dart Source:** `layer.dart:58`
    private var _entries: [AnnotationEntry<T>] = []

    public init() {}

    /// Add a new entry to the end of the result.
    ///
    /// Usually, entries should be added in order from most specific to least
    /// specific, typically during an upward walk of the tree.
    ///
    /// **Dart Source:** `layer.dart:64`
    public func add(_ entry: AnnotationEntry<T>) {
        _entries.append(entry)
    }

    /// An unmodifiable list of `AnnotationEntry` objects recorded.
    ///
    /// The first entry is the most specific, typically the one at the leaf of
    /// tree.
    ///
    /// **Dart Source:** `layer.dart:70`
    public var entries: [AnnotationEntry<T>] {
        return _entries
    }

    /// An unmodifiable list of annotations recorded.
    ///
    /// The first entry is the most specific, typically the one at the leaf of
    /// tree.
    ///
    /// It is similar to `entries` but does not contain other information.
    ///
    /// **Dart Source:** `layer.dart:78-80`
    public var annotations: [T] {
        return _entries.map { $0.annotation }
    }
}

// MARK: - Layer

/// A composited layer.
///
/// During painting, the render tree generates a tree of composited layers that
/// are uploaded into the engine and displayed by the compositor. This class is
/// the base class for all composited layers.
///
/// Most layers can have their properties mutated, and layers can be moved to
/// different parents. The scene must be explicitly recomposited after such
/// changes are made; the layer tree does not maintain its own dirty state.
///
/// To composite the tree, create a `SceneBuilder` object, pass it to the
/// root `Layer` object's `addToScene` method, and then call
/// `SceneBuilder.build` to obtain a `Scene`. A `Scene` can then be painted
/// using `FlutterView.render`.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`
/// **Original Name:** `Layer`
/// **Lines:** 144-751
open class Layer: DiagnosticableTreeMixin {

    /// Creates an instance of Layer.
    ///
    /// **Dart Source:** `layer.dart:146-148`
    public init() {}

    // MARK: - Composition Callbacks

    /// Dictionary of registered composition callbacks indexed by callback ID.
    ///
    /// **Dart Source:** `layer.dart:150`
    private var _callbacks: [Int: VoidCallback] = [:]

    /// Auto-incrementing ID for the next composition callback.
    ///
    /// **Dart Source:** `layer.dart:151`
    nonisolated(unsafe) private static var _nextCallbackId: Int = 0

    /// Whether the subtree rooted at this layer has any composition callback
    /// observers.
    ///
    /// This only evaluates to true if the subtree rooted at this node has
    /// observers. For example, it may evaluate to true on a parent node but false
    /// on a child if the parent has observers but the child does not.
    ///
    /// **Dart Source:** `layer.dart:163`
    public var subtreeHasCompositionCallbacks: Bool {
        return _compositionCallbackCount > 0
    }

    /// The count of composition callbacks in this layer's subtree.
    ///
    /// **Dart Source:** `layer.dart:165`
    internal var _compositionCallbackCount: Int = 0

    /// Updates the subtree composition observer count by the given delta,
    /// propagating the change up to the parent.
    ///
    /// **Dart Source:** `layer.dart:166-171`
    internal func _updateSubtreeCompositionObserverCount(_ delta: Int) {
        assert(delta != 0)
        _compositionCallbackCount += delta
        assert(_compositionCallbackCount >= 0)
        _parent?._updateSubtreeCompositionObserverCount(delta)
    }

    /// Fires all composition callbacks registered on this layer.
    ///
    /// **Dart Source:** `layer.dart:173-180`
    internal func _fireCompositionCallbacks(includeChildren: Bool) {
        if _callbacks.isEmpty {
            return
        }
        for callback in Array(_callbacks.values) {
            callback()
        }
    }

    /// Whether mutations are locked (used during composition callback firing).
    ///
    /// **Dart Source:** `layer.dart:182`
    internal var _debugMutationsLocked: Bool = false

    /// Adds a callback for when the layer tree that this layer is part of gets
    /// composited, or when it is detached and will not be rendered again.
    ///
    /// This callback will fire even if an ancestor layer is added with retained
    /// rendering, meaning that it will fire even if this layer gets added to the
    /// scene via some call to `SceneBuilder.addRetained` on one of its
    /// ancestor layers.
    ///
    /// The callback receives a reference to this layer. The recipient must not
    /// mutate the layer during the scope of the callback, but may traverse the
    /// tree to find information about the current transform or clip. The layer
    /// may not be `attached` anymore in this state, but even if it is detached it
    /// may still have an also detached parent it can visit.
    ///
    /// If new callbacks are added or removed within the callback, the new
    /// callbacks will fire (or stop firing) on the _next_ compositing event.
    ///
    /// Composition callbacks are useful in place of pushing a layer that would
    /// otherwise try to observe the layer tree without actually affecting
    /// compositing. For example, a composition callback may be used to observe
    /// the total transform and clip of the current container layer to determine
    /// whether a render object drawn into it is visible or not.
    ///
    /// Calling the returned callback will remove the callback from the
    /// composition callbacks.
    ///
    /// **Dart Source:** `layer.dart:227-246`
    public func addCompositionCallback(_ callback: @escaping CompositionCallback) -> VoidCallback {
        _updateSubtreeCompositionObserverCount(1)
        Layer._nextCallbackId += 1
        let callbackId = Layer._nextCallbackId
        _callbacks[callbackId] = { [weak self] in
            guard let self = self else { return }
            assert({
                self._debugMutationsLocked = true
                return true
            }())
            callback(self)
            assert({
                self._debugMutationsLocked = false
                return true
            }())
        }
        return { [weak self] in
            guard let self = self else { return }
            assert(self._debugDisposed || self._callbacks[callbackId] != nil)
            self._callbacks.removeValue(forKey: callbackId)
            self._updateSubtreeCompositionObserverCount(-1)
        }
    }

    // MARK: - Disposal

    /// Whether `dispose` has been called on this layer.
    ///
    /// If asserts are enabled, returns whether `dispose` has been called since
    /// the last time any retained resources were created.
    ///
    /// **Dart Source:** `layer.dart:252-259`
    public var debugDisposed: Bool {
        var disposed = false
        assert({
            disposed = _debugDisposed
            return true
        }())
        return disposed
    }

    /// Internal flag tracking whether dispose has been called.
    ///
    /// **Dart Source:** `layer.dart:261`
    internal var _debugDisposed: Bool = false

    /// Clears any retained resources that this layer holds.
    ///
    /// This method must dispose resources such as `EngineLayer` and `Picture`
    /// objects. The layer is still usable after this call, but any graphics
    /// related resources it holds will need to be recreated.
    ///
    /// This method _only_ disposes resources for this layer. For example, if it
    /// is a `ContainerLayer`, it does not dispose resources of any children.
    /// However, `ContainerLayer`s do remove any children they have when
    /// this method is called, and if this layer was the last holder of a removed
    /// child handle, the child may recursively clean up its resources.
    ///
    /// This method automatically gets called when all outstanding `LayerHandle`s
    /// are disposed. `LayerHandle` objects are typically held by the `parent`
    /// layer of this layer and any `RenderObject`s that participated in creating
    /// it.
    ///
    /// After calling this method, the object is unusable.
    ///
    /// **Dart Source:** `layer.dart:316-340`
    open func dispose() {
        assert(!_debugMutationsLocked)
        assert(
            !_debugDisposed,
            "Layers must only be disposed once. This is typically handled by "
            + "LayerHandle and createHandle. Subclasses should not directly call "
            + "dispose, except to call super.dispose() in an overridden dispose "
            + "method. Tests must only call dispose once."
        )
        assert({
            assert(
                _refCount == 0,
                "Do not directly call dispose on a \(type(of: self)). Instead, "
                + "use createHandle and LayerHandle.dispose."
            )
            _debugDisposed = true
            return true
        }())
        _engineLayer?.dispose()
        _engineLayer = nil
    }

    // MARK: - Parent Handle / Reference Counting

    /// A handle set when this layer is appended to a `ContainerLayer`, and
    /// unset when it is removed.
    ///
    /// This cannot be set from `attach` or `detach` which is called when an
    /// entire subtree is attached to or detached from an owner. Layers may be
    /// appended to or removed from a `ContainerLayer` regardless of whether they
    /// are attached or detached, and detaching a layer from an owner does not
    /// imply that it has been removed from its parent.
    ///
    /// **Dart Source:** `layer.dart:271`
    internal let _parentHandle: LayerHandle<Layer> = LayerHandle<Layer>()

    /// Incremented by `LayerHandle`.
    ///
    /// **Dart Source:** `layer.dart:274`
    internal var _refCount: Int = 0

    /// Called by `LayerHandle` when a reference is released.
    ///
    /// When the reference count reaches zero, `dispose()` is called.
    ///
    /// **Dart Source:** `layer.dart:277-284`
    internal func _unref() {
        assert(!_debugMutationsLocked)
        assert(_refCount > 0)
        _refCount -= 1
        if _refCount == 0 {
            dispose()
        }
    }

    /// Returns the number of objects holding a `LayerHandle` to this layer.
    ///
    /// This method throws if asserts are disabled.
    ///
    /// **Dart Source:** `layer.dart:289-296`
    public var debugHandleCount: Int {
        var count = 0
        assert({
            count = _refCount
            return true
        }())
        return count
    }

    // MARK: - Tree Structure

    /// This layer's parent in the layer tree.
    ///
    /// The `parent` of the root node in the layer tree is nil.
    ///
    /// Only subclasses of `ContainerLayer` can have children in the layer tree.
    /// All other layer classes are used for leaves in the layer tree.
    ///
    /// **Dart Source:** `layer.dart:348`
    public var parent: ContainerLayer? {
        return _parent
    }

    /// Internal storage for the parent reference.
    ///
    /// **Dart Source:** `layer.dart:349`
    internal var _parent: ContainerLayer?

    // MARK: - Scene Management (needsAddToScene)

    /// Whether this layer has any changes since its last call to `addToScene`.
    ///
    /// Initialized to true as a new layer has never called `addToScene`, and is
    /// set to false after calling `addToScene`. The value can become true again
    /// if `markNeedsAddToScene` is called, or when `updateSubtreeNeedsAddToScene`
    /// is called on this layer or on an ancestor layer.
    ///
    /// **Dart Source:** `layer.dart:372`
    internal var _needsAddToScene: Bool = true

    /// Mark that this layer has changed and `addToScene` needs to be called.
    ///
    /// **Dart Source:** `layer.dart:376-392`
    open func markNeedsAddToScene() {
        assert(!_debugMutationsLocked)
        assert(
            !alwaysNeedsAddToScene,
            "\(type(of: self)) with alwaysNeedsAddToScene set called markNeedsAddToScene.\n"
            + "The layer's alwaysNeedsAddToScene is set to true, and therefore it should not call markNeedsAddToScene."
        )
        assert(!_debugDisposed)

        // Already marked. Short-circuit.
        if _needsAddToScene {
            return
        }

        _needsAddToScene = true
    }

    /// Mark that this layer is in sync with engine.
    ///
    /// This is for debugging and testing purposes only. In release builds
    /// this method has no effect.
    ///
    /// **Dart Source:** `layer.dart:399-405`
    public func debugMarkClean() {
        assert(!_debugMutationsLocked)
        assert({
            _needsAddToScene = false
            return true
        }())
    }

    /// Subclasses may override this to true to disable retained rendering.
    ///
    /// **Dart Source:** `layer.dart:409`
    open var alwaysNeedsAddToScene: Bool {
        return false
    }

    /// Whether this or any descendant layer in the subtree needs `addToScene`.
    ///
    /// This is for debug and test purpose only. It only becomes valid after
    /// calling `updateSubtreeNeedsAddToScene`.
    ///
    /// **Dart Source:** `layer.dart:416-423`
    public var debugSubtreeNeedsAddToScene: Bool? {
        var result: Bool? = nil
        assert({
            result = _needsAddToScene
            return true
        }())
        return result
    }

    // MARK: - Engine Layer

    /// Stores the engine layer created for this layer in order to reuse engine
    /// resources across frames for better app performance.
    ///
    /// This value may be passed to `SceneBuilder.addRetained` to communicate
    /// to the engine that nothing in this layer or any of its descendants
    /// changed. The native engine could, for example, reuse the texture rendered
    /// in a previous frame. The web engine could, for example, reuse the HTML
    /// DOM nodes created for a previous frame.
    ///
    /// This value may be passed as `oldLayer` argument to a "push" method to
    /// communicate to the engine that a layer is updating a previously rendered
    /// layer. The web engine could, for example, update the properties of
    /// previously rendered HTML DOM nodes rather than creating new nodes.
    ///
    /// **Dart Source:** `layer.dart:440`
    open var engineLayer: EngineLayer? {
        get {
            return _engineLayer
        }
        set {
            assert(!_debugMutationsLocked)
            assert(!_debugDisposed)

            _engineLayer?.dispose()
            _engineLayer = newValue
            if !alwaysNeedsAddToScene {
                // The parent must construct a new engine layer to add this layer to,
                // and so we mark it as needing addToScene.
                //
                // This is designed to handle two situations:
                //
                // 1. When rendering the complete layer tree as normal. In this case we
                // call child addToScene methods first, then we call set engineLayer
                // for the parent. The children will call markNeedsAddToScene on the
                // parent to signal that they produced new engine layers and therefore
                // the parent needs to update. In this case, the parent is already adding
                // itself to the scene via addToScene, and so after it's done, its
                // set engineLayer is called and it clears the _needsAddToScene flag.
                //
                // 2. When rendering an interior layer (e.g. OffsetLayer.toImage). In
                // this case we call addToScene for one of the children but not the
                // parent, i.e. we produce new engine layers for children but not for the
                // parent. Here the children will mark the parent as needing
                // addToScene, but the parent does not clear the flag until some future
                // frame decides to render it, at which point the parent knows that it
                // cannot retain its engine layer and will call addToScene again.
                if _parent != nil && !_parent!.alwaysNeedsAddToScene {
                    _parent!.markNeedsAddToScene()
                }
            }
        }
    }

    /// Internal storage for the engine layer.
    ///
    /// **Dart Source:** `layer.dart:482`
    internal var _engineLayer: EngineLayer?

    /// Traverses the layer subtree starting from this layer and determines whether
    /// it needs `addToScene`.
    ///
    /// A layer needs `addToScene` if any of the following is true:
    ///
    /// - `alwaysNeedsAddToScene` is true.
    /// - `markNeedsAddToScene` has been called.
    /// - Any of its descendants need `addToScene`.
    ///
    /// `ContainerLayer` overrides this method to recursively call it on its children.
    ///
    /// **Dart Source:** `layer.dart:495-498`
    open func updateSubtreeNeedsAddToScene() {
        assert(!_debugMutationsLocked)
        _needsAddToScene = _needsAddToScene || alwaysNeedsAddToScene
    }

    // MARK: - Owner / Attached

    /// The owner for this layer (nil if unattached).
    ///
    /// The entire layer tree that this layer belongs to will have the same owner.
    ///
    /// Typically the owner is a `RenderView`.
    ///
    /// **Dart Source:** `layer.dart:505`
    public var owner: AnyObject? {
        return _owner
    }

    /// Internal storage for the owner.
    ///
    /// **Dart Source:** `layer.dart:506`
    internal var _owner: AnyObject?

    /// Whether the layer tree containing this layer is attached to an owner.
    ///
    /// This becomes true during the call to `attach`.
    ///
    /// This becomes false during the call to `detach`.
    ///
    /// **Dart Source:** `layer.dart:513`
    public var attached: Bool {
        return _owner != nil
    }

    /// Mark this layer as attached to the given owner.
    ///
    /// Typically called only from the parent's `attach` method, and by the
    /// owner to mark the root of a tree as attached.
    ///
    /// Subclasses with children should override this method to
    /// `attach` all their children to the same owner
    /// after calling the inherited method, as in `super.attach(owner)`.
    ///
    /// **Dart Source:** `layer.dart:524-527`
    open func attach(_ owner: AnyObject) {
        assert(_owner == nil)
        _owner = owner
    }

    /// Mark this layer as detached from its owner.
    ///
    /// Typically called only from the parent's `detach`, and by the owner to
    /// mark the root of a tree as detached.
    ///
    /// Subclasses with children should override this method to
    /// `detach` all their children after calling the inherited method,
    /// as in `super.detach()`.
    ///
    /// **Dart Source:** `layer.dart:538-542`
    open func detach() {
        assert(_owner != nil)
        _owner = nil
        assert(_parent == nil || attached == _parent!.attached)
    }

    // MARK: - Depth

    /// The depth of this layer in the layer tree.
    ///
    /// The depth of nodes in a tree monotonically increases as you traverse down
    /// the tree. There's no guarantee regarding depth between siblings.
    ///
    /// The depth is used to ensure that nodes are processed in depth order.
    ///
    /// **Dart Source:** `layer.dart:550`
    public var depth: Int {
        return _depth
    }

    /// Internal storage for depth.
    ///
    /// **Dart Source:** `layer.dart:551`
    internal var _depth: Int = 0

    /// Adjust the depth of this node's children, if any.
    ///
    /// Override this method in subclasses with child nodes to call
    /// `ContainerLayer.redepthChild` for each child. Do not call this method
    /// directly.
    ///
    /// **Dart Source:** `layer.dart:558-562`
    open func redepthChildren() {
        // ContainerLayer provides an implementation since it's the only one that
        // can actually have children.
    }

    // MARK: - Siblings

    /// This layer's next sibling in the parent layer's child list.
    ///
    /// **Dart Source:** `layer.dart:565`
    public var nextSibling: Layer? {
        return _nextSibling
    }

    /// Internal storage for the next sibling pointer.
    ///
    /// **Dart Source:** `layer.dart:566`
    internal var _nextSibling: Layer?

    /// This layer's previous sibling in the parent layer's child list.
    ///
    /// **Dart Source:** `layer.dart:569`
    public var previousSibling: Layer? {
        return _previousSibling
    }

    /// Internal storage for the previous sibling pointer.
    ///
    /// `weak`: back-pointer only, same reasoning as
    /// ContainerBoxParentData.previousSibling — with both sibling pointers
    /// strong, adjacent children of a dropped ContainerLayer keep each other
    /// (and their engine layers and pictures) alive forever under ARC.
    /// Ownership flows parent → _firstChild → _nextSibling → …
    ///
    /// **Dart Source:** `layer.dart:570`
    internal weak var _previousSibling: Layer?

    // MARK: - Remove

    /// Removes this layer from its parent layer's child list.
    ///
    /// This has no effect if the layer's parent is already nil.
    ///
    /// **Dart Source:** `layer.dart:576-579`
    public func remove() {
        assert(!_debugMutationsLocked)
        _parent?._removeChild(self)
    }

    // MARK: - Annotation Search

    /// Search this layer and its subtree for annotations of type `S` at the
    /// location described by `localPosition`.
    ///
    /// This method is called by the default implementation of `find` and
    /// `findAllAnnotations`. Override this method to customize how the layer
    /// should search for annotations, or if the layer has its own annotations to
    /// add.
    ///
    /// The default implementation always returns `false`, which means neither
    /// the layer nor its children has annotations, and the annotation search
    /// is not absorbed either.
    ///
    /// The `result` parameter is where the method outputs the resulting
    /// annotations. New annotations found during the walk are added to the tail.
    ///
    /// The `onlyFirst` parameter indicates that, if true, the search will stop
    /// when it finds the first qualified annotation; otherwise, it will walk the
    /// entire subtree.
    ///
    /// The return value indicates the opacity of this layer and its subtree at
    /// this position. If it returns true, then this layer's parent should skip
    /// the children behind this layer.
    ///
    /// **Dart Source:** `layer.dart:632-638`
    open func findAnnotations<S>(
        _ result: AnnotationResult<S>,
        _ localPosition: Offset,
        onlyFirst: Bool
    ) -> Bool {
        return false
    }

    /// Search this layer and its subtree for the first annotation of type `S`
    /// under the point described by `localPosition`.
    ///
    /// Returns nil if no matching annotations are found.
    ///
    /// By default this method calls `findAnnotations` with `onlyFirst: true`
    /// and returns the annotation of the first result. Prefer overriding
    /// `findAnnotations` instead of this method, because during an annotation
    /// search, only `findAnnotations` is recursively called, while custom
    /// behavior in this method is ignored.
    ///
    /// **Dart Source:** `layer.dart:660-664`
    public func find<S>(_ type: S.Type, _ localPosition: Offset) -> S? {
        let result = AnnotationResult<S>()
        _ = findAnnotations(result, localPosition, onlyFirst: true)
        return result.entries.isEmpty ? nil : result.entries.first!.annotation
    }

    /// Search this layer and its subtree for all annotations of type `S` under
    /// the point described by `localPosition`.
    ///
    /// Returns a result with empty entries if no matching annotations are found.
    ///
    /// By default this method calls `findAnnotations` with `onlyFirst: false`
    /// and returns the annotations of its result. Prefer overriding
    /// `findAnnotations` instead of this method, because during an annotation
    /// search, only `findAnnotations` is recursively called, while custom
    /// behavior in this method is ignored.
    ///
    /// **Dart Source:** `layer.dart:686-690`
    public func findAllAnnotations<S>(_ type: S.Type, _ localPosition: Offset) -> AnnotationResult<S> {
        let result = AnnotationResult<S>()
        _ = findAnnotations(result, localPosition, onlyFirst: false)
        return result
    }

    // MARK: - Scene Building

    /// Override this method to upload this layer to the engine.
    ///
    /// **Dart Source:** `layer.dart:694`
    open func addToScene(_ builder: SceneBuilder) {
        fatalError("Subclasses must override addToScene()")
    }

    /// Adds this layer to the scene using retained rendering if possible.
    ///
    /// If `_needsAddToScene` is false and `_engineLayer` is not nil,
    /// uses `builder.addRetained()` instead of rebuilding the subtree.
    /// This is a key performance optimization.
    ///
    /// **Dart Source:** `layer.dart:696-716`
    internal func _addToSceneWithRetainedRendering(_ builder: SceneBuilder) {
        assert(!_debugMutationsLocked)
        if !_needsAddToScene && _engineLayer != nil {
            builder.addRetained(_engineLayer!)
            return
        }
        addToScene(builder)
        _needsAddToScene = false
    }

    // MARK: - Rasterization

    /// Whether or not this layer, or any child layers, can be rasterized with
    /// `Scene.toImage` or `Scene.toImageSync`.
    ///
    /// If `false`, calling the above methods may yield an image which is
    /// incomplete.
    ///
    /// This value may change throughout the lifetime of the object, as the
    /// child layers themselves are added or removed.
    ///
    /// **Dart Source:** `layer.dart:192-194`
    open func supportsRasterization() -> Bool {
        return true
    }

    /// Describes the clip that would be applied to contents of this layer,
    /// if any.
    ///
    /// **Dart Source:** `layer.dart:198`
    open func describeClipBounds() -> Rect? {
        return nil
    }

    // MARK: - Debug

    /// The object responsible for creating this layer.
    ///
    /// Defaults to the value of `RenderObject.debugCreator` for the render object
    /// that created this layer. Used in debug messages.
    ///
    /// **Dart Source:** `layer.dart:722`
    public var debugCreator: AnyObject?

    /// **Dart Source:** `layer.dart:724-725`
    public func toStringShort() -> String {
        return "\(describeIdentity(self))\(owner == nil ? " DETACHED" : "")"
    }

    /// **Dart Source:** `layer.dart:728-750`
    public func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        properties.add(
            DiagnosticsProperty<AnyObject>(
                "owner",
                owner,
                defaultValue: nil,
                level: _parent != nil ? .hidden : .info
            )
        )
        properties.add(
            DiagnosticsProperty<AnyObject>(
                "creator",
                debugCreator,
                defaultValue: nil,
                level: .debug
            )
        )
        if _engineLayer != nil {
            properties.add(
                DiagnosticsProperty<String>(
                    "engine layer",
                    describeIdentity(_engineLayer!)
                )
            )
        }
        properties.add(DiagnosticsProperty<Int>("handles", debugHandleCount))
    }
}

// MARK: - CompositionCallback

/// The signature of the callback added in `Layer.addCompositionCallback`.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`
/// **Original Name:** `CompositionCallback`
/// **Line:** 1070
public typealias CompositionCallback = (Layer) -> Void

// MARK: - LayerHandle (Stub)

/// A handle to prevent a `Layer`'s platform graphics resources from being
/// disposed.
///
/// `Layer` objects retain native resources such as `EngineLayer`s and `Picture`
/// objects. These objects may in turn retain large chunks of texture memory,
/// either directly or indirectly.
///
/// The layer's native resources must be retained as long as there is some
/// object that can add it to a scene. Typically, this is either its
/// `Layer.parent` or an undisposed `RenderObject` that will append it to a
/// `ContainerLayer`. Layers automatically hold a handle to their children, and
/// RenderObjects automatically hold a handle to their `RenderObject.layer` as
/// well as any `PictureLayer`s that they paint into using the
/// `PaintingContext.canvas`. A layer automatically releases its resources once
/// at least one handle has been acquired and all handles have been disposed.
/// `RenderObject`s that create additional layer objects must manually manage
/// the handles for that layer similarly to the implementation of
/// `RenderObject.layer`.
///
/// NOTE: This is a minimal stub for forward reference. Full implementation
/// will be provided in Subtask 3.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`
/// **Original Name:** `LayerHandle<T>`
/// **Lines:** 783-816
public class LayerHandle<T: Layer> {
    /// Create a new layer handle, optionally referencing a `Layer`.
    ///
    /// **Dart Source:** `layer.dart:785-789`
    public init(_ layer: T? = nil) {
        _layer = layer
        if _layer != nil {
            _layer!._refCount += 1
        }
    }

    /// Internal storage for the referenced layer.
    ///
    /// **Dart Source:** `layer.dart:791`
    private var _layer: T?

    /// The `Layer` whose resources this object keeps alive.
    ///
    /// Setting a new value or nil will dispose the previously held layer if
    /// there are no other open handles to that layer.
    ///
    /// **Dart Source:** `layer.dart:797-812`
    public var layer: T? {
        get { return _layer }
        set {
            assert(
                newValue?.debugDisposed != true,
                "Attempted to create a handle to an already disposed layer: \(String(describing: newValue))."
            )
            if newValue === _layer {
                return
            }
            _layer?._unref()
            _layer = newValue
            if _layer != nil {
                _layer!._refCount += 1
            }
        }
    }

    /// A description of this handle.
    ///
    /// **Dart Source:** `layer.dart:815`
    public var description: String {
        return "LayerHandle(\(_layer != nil ? describeIdentity(_layer!) : "DISPOSED"))"
    }
}

// MARK: - PictureLayer

/// A composited layer that holds a `Picture`.
///
/// Picture layers are always leaves in the layer tree.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`
/// **Original Name:** `PictureLayer`
/// **Lines:** 824-924
public class PictureLayer: Layer {

    /// Creates a picture layer.
    ///
    /// **Dart Source:** `layer.dart:826`
    public init(_ canvasBounds: Rect) {
        self.canvasBounds = canvasBounds
        super.init()
    }

    /// The bounds that were used for the canvas that drew this layer's picture.
    ///
    /// **Dart Source:** `layer.dart:833`
    public let canvasBounds: Rect

    /// The picture recorded for this layer.
    ///
    /// **Dart Source:** `layer.dart:839-845`
    public var picture: (any Picture)? {
        get { _picture }
        set {
            markNeedsAddToScene()
            _picture = newValue
        }
    }
    private var _picture: (any Picture)?

    /// Hints that the painting is complex and would benefit from caching.
    ///
    /// **Dart Source:** `layer.dart:861`
    public var isComplexHint: Bool = false

    /// Hints that the painting will change in the next frame.
    ///
    /// **Dart Source:** `layer.dart:876`
    public var willChangeHint: Bool = false

    /// Uploads this layer to the engine.
    ///
    /// **Dart Source:** `layer.dart:879-882`
    public override func addToScene(_ builder: any SceneBuilder) {
        assert(picture != nil)
        builder.addPicture(Offset.zero, picture: picture!,
                           isComplexHint: isComplexHint, willChangeHint: willChangeHint)
    }

    /// Disposes picture resources.
    ///
    /// **Dart Source:** `layer.dart:900-907`
    public override func dispose() {
        _picture = nil
        super.dispose()
    }
}

// MARK: - ContainerLayer

/// A composited layer that has a list of children.
///
/// A `ContainerLayer` instance merely takes a list of children and inserts
/// them into the composited tree in order. There are subclasses of
/// `ContainerLayer` which apply more elaborate effects in the process.
///
/// NOTE: This is a minimal forward declaration stub. The full implementation
/// will be provided in Subtask 4.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`
/// **Original Name:** `ContainerLayer`
/// **Lines:** 1077-1448
open class ContainerLayer: Layer {

    /// Creates a ContainerLayer.
    ///
    /// **Dart Source:** `layer.dart:1077`
    public override init() {
        super.init()
    }

    /// Disposes this container layer and removes all children.
    ///
    /// **Dart Source:** `layer.dart:1079-1083`
    public override func dispose() {
        removeAllChildren()
        super.dispose()
    }

    // MARK: - Child Linked List

    /// The first child in the linked list of children.
    ///
    /// **Dart Source:** `layer.dart:1083`
    public var firstChild: Layer? { _firstChild }
    internal var _firstChild: Layer?

    /// The last child in the linked list of children.
    ///
    /// **Dart Source:** `layer.dart:1086`
    public var lastChild: Layer? { _lastChild }
    internal var _lastChild: Layer?

    /// Whether this layer has any children.
    ///
    /// **Dart Source:** `layer.dart:1089`
    public var hasChildren: Bool { _firstChild != nil }

    // MARK: - Child Management

    /// Adopts the given child layer.
    ///
    /// **Dart Source:** `layer.dart:1273-1282`
    internal func _adoptChild(_ child: Layer) {
        assert(child._parent == nil)
        child._parent = self
        if attached {
            child.attach(_owner!)
        }
        redepthChild(child)
        markNeedsAddToScene()
    }

    /// Drops the given child layer.
    ///
    /// **Dart Source:** `layer.dart:1284-1292`
    internal func _dropChild(_ child: Layer) {
        assert(child._parent === self)
        child._parent = nil
        if attached {
            child.detach()
        }
        markNeedsAddToScene()
    }

    /// Appends the given layer to the end of this layer's child list.
    ///
    /// **Dart Source:** `layer.dart:1240-1271`
    public func append(_ child: Layer) {
        assert(!_debugMutationsLocked)
        assert(child !== self)
        assert(child._parent == nil)
        assert(!_debugDisposed)
        _adoptChild(child)
        child._previousSibling = _lastChild
        if _lastChild != nil {
            _lastChild!._nextSibling = child
        }
        _lastChild = child
        _firstChild = _firstChild ?? child
        child._parentHandle.layer = child
        assert(child.attached == attached)
    }

    /// Removes the given child from the child list.
    ///
    /// **Dart Source:** `layer.dart:1294-1321`
    internal func _removeChild(_ child: Layer) {
        assert(!_debugMutationsLocked)
        assert(child._parent === self)
        assert(!_debugDisposed)
        if child._previousSibling == nil {
            assert(_firstChild === child)
            _firstChild = child._nextSibling
        } else {
            child._previousSibling!._nextSibling = child._nextSibling
        }
        if child._nextSibling == nil {
            assert(_lastChild === child)
            _lastChild = child._previousSibling
        } else {
            child._nextSibling!._previousSibling = child._previousSibling
        }
        child._previousSibling = nil
        child._nextSibling = nil
        _dropChild(child)
        child._parentHandle.layer = nil
    }

    /// Removes all children from this layer.
    ///
    /// **Dart Source:** `layer.dart:1323-1340`
    public func removeAllChildren() {
        assert(!_debugMutationsLocked)
        var child = _firstChild
        while child != nil {
            let next = child!._nextSibling
            child!._previousSibling = nil
            child!._nextSibling = nil
            _dropChild(child!)
            child!._parentHandle.layer = nil
            child = next
        }
        _firstChild = nil
        _lastChild = nil
    }

    // MARK: - Depth

    /// Adjusts the depth of the given child if needed.
    ///
    /// **Dart Source:** `layer.dart:1091-1095`
    public func redepthChild(_ child: Layer) {
        if child._depth <= _depth {
            child._depth = _depth + 1
            child.redepthChildren()
        }
    }

    /// Adjusts the depth of all children.
    ///
    /// **Dart Source:** `layer.dart:1097-1103`
    open override func redepthChildren() {
        var child = _firstChild
        while child != nil {
            redepthChild(child!)
            child = child!._nextSibling
        }
    }

    // MARK: - Attach / Detach

    /// **Dart Source:** `layer.dart:1105-1113`
    open override func attach(_ owner: AnyObject) {
        super.attach(owner)
        var child = _firstChild
        while child != nil {
            child!.attach(owner)
            child = child!._nextSibling
        }
    }

    /// **Dart Source:** `layer.dart:1115-1123`
    open override func detach() {
        super.detach()
        var child = _firstChild
        while child != nil {
            child!.detach()
            child = child!._nextSibling
        }
    }

    // MARK: - Scene Building

    /// Iterates children and adds them to the scene.
    ///
    /// **Dart Source:** `layer.dart:1380-1392`
    public func addChildrenToScene(_ builder: any SceneBuilder) {
        var child = _firstChild
        while child != nil {
            child!._addToSceneWithRetainedRendering(builder)
            child = child!._nextSibling
        }
    }

    /// Adds this container layer to the scene by adding all children.
    ///
    /// **Dart Source:** `layer.dart:1395-1398`
    open override func addToScene(_ builder: any SceneBuilder) {
        addChildrenToScene(builder)
    }

    // MARK: - Subtree Needs Add To Scene

    /// **Dart Source:** `layer.dart:1158-1172`
    open override func updateSubtreeNeedsAddToScene() {
        super.updateSubtreeNeedsAddToScene()
        var child = _firstChild
        while child != nil {
            child!.updateSubtreeNeedsAddToScene()
            _needsAddToScene = _needsAddToScene || child!._needsAddToScene
            child = child!._nextSibling
        }
    }
}

// MARK: - LeaderLayer (Stub)

/// A composited layer that can be followed by a `FollowerLayer`.
///
/// This layer collapses the accumulated offset into a transform and passes
/// `Offset.zero` to its child layers in the `addToScene` method, so that
/// the `FollowerLayer` can pick up the transform as the leader transform.
///
/// NOTE: This is a minimal stub. Full implementation will be provided
/// in a later subtask.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`
/// **Original Name:** `LeaderLayer`
/// **Lines:** 2480-2538
open class LeaderLayer: ContainerLayer {

    /// Creates a leader layer.
    ///
    /// **Dart Source:** `layer.dart:2484-2488`
    public init(link: LayerLink, offset: Offset = .zero) {
        self._link = link
        self._offset = offset
        super.init()
    }

    /// The link for connecting with `FollowerLayer`s.
    ///
    /// **Dart Source:** `layer.dart:2494`
    public var link: LayerLink {
        get { _link }
        set {
            _link = newValue
            markNeedsAddToScene()
        }
    }
    private var _link: LayerLink

    /// The offset from the origin of the leader layer's parent to the
    /// origin of the leader layer.
    ///
    /// **Dart Source:** `layer.dart:2500`
    public var offset: Offset {
        get { _offset }
        set {
            _offset = newValue
            markNeedsAddToScene()
        }
    }
    private var _offset: Offset
}

// MARK: - FollowerLayer (Stub)

/// A composited layer that applies a transformation computed from a
/// `LeaderLayer` with the same `LayerLink`.
///
/// NOTE: This is a minimal stub. Full implementation will be provided
/// in a later subtask.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`
/// **Original Name:** `FollowerLayer`
/// **Lines:** 2546-2778
open class FollowerLayer: ContainerLayer {

    /// Creates a follower layer.
    ///
    /// **Dart Source:** `layer.dart:2551-2558`
    public init(
        link: LayerLink,
        showWhenUnlinked: Bool = true,
        unlinkedOffset: Offset = .zero,
        linkedOffset: Offset = .zero
    ) {
        self._link = link
        self._showWhenUnlinked = showWhenUnlinked
        self._unlinkedOffset = unlinkedOffset
        self._linkedOffset = linkedOffset
        super.init()
    }

    /// The link to the `LeaderLayer`.
    ///
    /// **Dart Source:** `layer.dart:2564`
    public var link: LayerLink {
        get { _link }
        set {
            _link = newValue
            markNeedsAddToScene()
        }
    }
    private var _link: LayerLink

    /// Whether to show the layer's contents when the `LeaderLayer` is not
    /// connected.
    ///
    /// **Dart Source:** `layer.dart:2576`
    public var showWhenUnlinked: Bool {
        get { _showWhenUnlinked }
        set {
            _showWhenUnlinked = newValue
            markNeedsAddToScene()
        }
    }
    private var _showWhenUnlinked: Bool

    /// Offset from the origin of the leader layer to the origin of the child
    /// layers, used when the layer is linked.
    ///
    /// **Dart Source:** `layer.dart:2590`
    public var linkedOffset: Offset {
        get { _linkedOffset }
        set {
            _linkedOffset = newValue
            markNeedsAddToScene()
        }
    }
    private var _linkedOffset: Offset

    /// Offset from parent in the regular layer tree to the origin of the child
    /// layers, used when the layer is not linked.
    ///
    /// **Dart Source:** `layer.dart:2603`
    public var unlinkedOffset: Offset {
        get { _unlinkedOffset }
        set {
            _unlinkedOffset = newValue
            markNeedsAddToScene()
        }
    }
    private var _unlinkedOffset: Offset

    /// Returns the last transform applied by this layer during composition.
    ///
    /// Returns nil if the layer has not been composited or the transform
    /// could not be determined.
    ///
    /// **Dart Source:** `layer.dart:2680-2693`
    public func getLastTransform() -> Matrix4? {
        // Stub: full implementation in a later subtask.
        return nil
    }
}

// MARK: - AnnotatedRegionLayer (Stub)

/// A composited layer that annotates its children with a value.
///
/// These annotations can be retrieved via `Layer.find` or
/// `Layer.findAllAnnotations`.
///
/// NOTE: This is a minimal stub. Full implementation will be provided
/// in a later subtask.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`
/// **Original Name:** `AnnotatedRegionLayer<T>`
/// **Lines:** 2786-2835
open class AnnotatedRegionLayer<T>: ContainerLayer {

    /// Creates a new layer that annotates its children with `value`.
    ///
    /// **Dart Source:** `layer.dart:2791-2798`
    public init(_ value: T, size: Size? = nil, offset: Offset? = nil) {
        self.value = value
        self.layerSize = size
        self.layerOffset = offset
        super.init()
    }

    /// The annotated value.
    ///
    /// **Dart Source:** `layer.dart:2802`
    public let value: T

    /// The size of the annotated region.
    ///
    /// **Dart Source:** `layer.dart:2806`
    public let layerSize: Size?

    /// The position of the annotated region relative to the parent layer.
    ///
    /// **Dart Source:** `layer.dart:2812`
    public let layerOffset: Offset?
}
