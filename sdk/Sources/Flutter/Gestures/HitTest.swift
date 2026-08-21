// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Hit test system for pointer event routing.
///
/// Provides the protocols and classes used to determine which render objects
/// are located at a given screen position, and to dispatch pointer events
/// to those objects.
///
/// **Dart Source:** `packages/flutter/lib/src/gestures/hit_test.dart`

import FlutterSwiftBridge

// MARK: - HitTestable

/// An object that can hit-test pointers.
///
/// **Dart Equivalent:** `abstract interface class HitTestable`
///
/// Note: The deprecated `hitTest(result:position:)` method from Dart
/// (deprecated after v3.11.0-20.0.pre) has been intentionally omitted.
/// Use `hitTestInView(result:position:viewId:)` instead.
public protocol HitTestable {
    /// Fills the provided `HitTestResult` with `HitTestEntry` instances for
    /// objects that are hit at the given `position` in the view identified by
    /// `viewId`.
    ///
    /// **Dart Equivalent:** `void hitTestInView(HitTestResult result, Offset position, int viewId)`
    func hitTestInView(result: HitTestResult, position: Offset, viewId: Int)
}

// MARK: - HitTestDispatcher

/// An object that can dispatch events.
///
/// **Dart Equivalent:** `abstract interface class HitTestDispatcher`
public protocol HitTestDispatcher {
    /// Override this method to dispatch events.
    ///
    /// **Dart Equivalent:** `void dispatchEvent(PointerEvent event, HitTestResult result)`
    func dispatchEvent(_ event: PointerEvent, result: HitTestResult)
}

// MARK: - HitTestTarget

/// An object that can handle events.
///
/// **Dart Equivalent:** `abstract interface class HitTestTarget`
public protocol HitTestTarget: AnyObject {
    /// Override this method to receive events.
    ///
    /// **Dart Equivalent:** `void handleEvent(PointerEvent event, HitTestEntry<HitTestTarget> entry)`
    func handleEvent(_ event: PointerEvent, entry: HitTestEntry<AnyHitTestTarget>)
}

// MARK: - AnyHitTestTarget

/// A type-erased wrapper around `HitTestTarget`, used where Swift's type
/// system requires a concrete type rather than a protocol existential.
///
/// This corresponds to Dart's ability to use `HitTestTarget` directly as a
/// generic type argument in `HitTestEntry<HitTestTarget>`.
public final class AnyHitTestTarget: HitTestTarget, CustomStringConvertible {
    private let wrapped: HitTestTarget

    /// Creates a type-erased wrapper around the given `HitTestTarget`.
    public init(_ target: HitTestTarget) {
        self.wrapped = target
    }

    /// The target this box erases. Consumers that dispatch by TYPE -- the
    /// mouse tracker looking for `MouseTrackerAnnotationProtocol` conformers
    /// in a hit path -- must look through the box: a cast against the box
    /// itself can only ever see `AnyHitTestTarget`.
    public var base: HitTestTarget { wrapped }

    public func handleEvent(_ event: PointerEvent, entry: HitTestEntry<AnyHitTestTarget>) {
        wrapped.handleEvent(event, entry: entry)
    }

    /// Debug description showing the wrapped target's type.
    public var description: String {
        return "AnyHitTestTarget(\(type(of: wrapped)))"
    }
}

// MARK: - HitTestEntry

/// Data collected during a hit test about a specific `HitTestTarget`.
///
/// Subclass this object to pass additional information from the hit test phase
/// to the event propagation phase.
///
/// **Dart Equivalent:** `class HitTestEntry<T extends HitTestTarget>`
public class HitTestEntry<T: HitTestTarget>: CustomStringConvertible {

    /// Creates a hit test entry.
    ///
    /// **Dart Equivalent:** `HitTestEntry(this.target)`
    public init(_ target: T) {
        self.target = target
    }

    /// The `HitTestTarget` encountered during the hit test.
    ///
    /// **Dart Equivalent:** `final T target`
    public let target: T

    /// Returns a matrix describing how `PointerEvent`s delivered to this
    /// `HitTestEntry` should be transformed from the global coordinate space of
    /// the screen to the local coordinate space of `target`.
    ///
    /// **Dart Equivalent:** `Matrix4? get transform => _transform`
    public internal(set) var transform: Matrix4?

    // MARK: - CustomStringConvertible

    public var description: String {
        return "\(describeIdentity(self))(\(target))"
    }
}

// MARK: - _TransformPart (Internal)

/// A type of data that can be applied to a matrix by left-multiplication.
///
/// **Dart Equivalent:** `abstract class _TransformPart`
protocol _TransformPart {
    /// Apply this transform part to `rhs` from the left.
    ///
    /// This should work as if this transform part is first converted to a matrix
    /// and then left-multiplied to `rhs`.
    ///
    /// For example, if this transform part is an offset `v`, whose corresponding
    /// matrix is `Matrix4.translationValues(v.dx, v.dy, 0)`, then the result of
    /// `_OffsetTransformPart(v).multiply(rhs:)` should equal
    /// `Matrix4.translationValues(v.dx, v.dy, 0) * rhs`.
    func multiply(rhs: Matrix4) -> Matrix4
}

// MARK: - _MatrixTransformPart (Internal)

/// Stores a `Matrix4` and implements multiply as matrix-matrix multiplication.
///
/// **Dart Equivalent:** `class _MatrixTransformPart extends _TransformPart`
struct _MatrixTransformPart: _TransformPart {
    let matrix: Matrix4

    init(_ matrix: Matrix4) {
        self.matrix = matrix
    }

    func multiply(rhs: Matrix4) -> Matrix4 {
        return matrix * rhs
    }
}

// MARK: - _OffsetTransformPart (Internal)

/// Stores an `Offset` and implements multiply as a left-translation.
///
/// **Dart Equivalent:** `class _OffsetTransformPart extends _TransformPart`
struct _OffsetTransformPart: _TransformPart {
    let offset: Offset

    init(_ offset: Offset) {
        self.offset = offset
    }

    func multiply(rhs: Matrix4) -> Matrix4 {
        // Equivalent to: Matrix4.translationValues(offset.dx, offset.dy, 0) * rhs
        // This is a left-multiplication by a translation matrix T:
        //   T = [[1,0,0,tx],[0,1,0,ty],[0,0,1,0],[0,0,0,1]]
        //
        // For each column j of result = T * column j of rhs:
        //   result[j*4+0] = rhs[j*4+0] + tx * rhs[j*4+3]
        //   result[j*4+1] = rhs[j*4+1] + ty * rhs[j*4+3]
        //   result[j*4+2] = rhs[j*4+2]
        //   result[j*4+3] = rhs[j*4+3]
        let tx = offset.dx
        let ty = offset.dy
        var result = rhs
        for j in 0..<4 {
            let base = j * 4
            result.storage[base + 0] += tx * rhs.storage[base + 3]
            result.storage[base + 1] += ty * rhs.storage[base + 3]
        }
        return result
    }
}

// MARK: - HitTestResult

/// The result of performing a hit test.
///
/// **Dart Equivalent:** `class HitTestResult`
open class HitTestResult: CustomStringConvertible {

    /// Creates an empty hit test result.
    ///
    /// **Dart Equivalent:** `HitTestResult()`
    public init() {
        _path = []
        _transforms = [Matrix4.identity()]
        _localTransforms = []
    }

    /// Wraps `result` (usually a subtype of `HitTestResult`) to create a
    /// generic `HitTestResult`.
    ///
    /// The `HitTestEntry` instances added to the returned `HitTestResult` are
    /// also added to the wrapped `result` (both share the same underlying data
    /// structure to store `HitTestEntry` instances).
    ///
    /// **Dart Equivalent:** `HitTestResult.wrap(HitTestResult result)`
    public init(wrap result: HitTestResult) {
        // In Swift, arrays are value types. To share state we reference the
        // same object's storage directly. We keep a reference to the wrapped
        // result and forward mutations.
        _path = result._path
        _transforms = result._transforms
        _localTransforms = result._localTransforms
        _wrapped = result
    }

    // MARK: - Properties

    /// An unmodifiable list of `HitTestEntry` objects recorded during the hit test.
    ///
    /// The first entry in the path is the most specific, typically the one at
    /// the leaf of tree being hit tested. Event propagation starts with the most
    /// specific (i.e., first) entry and proceeds in order through the path.
    ///
    /// **Dart Equivalent:** `Iterable<HitTestEntry> get path => _path`
    public var path: [HitTestEntry<AnyHitTestTarget>] {
        return _root._path
    }

    internal var _path: [HitTestEntry<AnyHitTestTarget>]
    internal var _transforms: [Matrix4]
    internal var _localTransforms: [_TransformPart]

    /// Reference to the wrapped result for shared-state forwarding.
    /// When this is non-nil, all mutations go through `_root`.
    private var _wrapped: HitTestResult?

    /// Returns the root result in a wrap chain, so that mutations affect
    /// the shared storage.
    private var _root: HitTestResult {
        var current = self
        while let wrapped = current._wrapped {
            current = wrapped
        }
        return current
    }

    // MARK: - Private Helpers

    /// Globalize all transform parts in `_localTransforms` and move them to
    /// `_transforms`.
    private func _globalizeTransforms() {
        let root = _root
        if root._localTransforms.isEmpty {
            return
        }
        var last = root._transforms[root._transforms.count - 1]
        for part in root._localTransforms {
            last = part.multiply(rhs: last)
            root._transforms.append(last)
        }
        root._localTransforms.removeAll()
    }

    private var _lastTransform: Matrix4 {
        _globalizeTransforms()
        let root = _root
        assert(root._localTransforms.isEmpty)
        return root._transforms[root._transforms.count - 1]
    }

    // MARK: - Public Methods

    /// Add a `HitTestEntry` to the path.
    ///
    /// The new entry is added at the end of the path, which means entries should
    /// be added in order from most specific to least specific, typically during an
    /// upward walk of the tree being hit tested.
    ///
    /// **Dart Equivalent:** `void add(HitTestEntry entry)`
    public func add(_ entry: HitTestEntry<AnyHitTestTarget>) {
        assert(entry.transform == nil)
        entry.transform = _lastTransform
        _root._path.append(entry)
    }

    /// Pushes a new transform matrix that is to be applied to all future
    /// `HitTestEntry` instances added via `add(_:)` until it is removed via
    /// `popTransform()`.
    ///
    /// This method is only to be used by subclasses, which must provide
    /// coordinate space specific public wrappers around this function for their
    /// users.
    ///
    /// The provided `transform` matrix should describe how to transform
    /// `PointerEvent`s from the coordinate space of the method caller to the
    /// coordinate space of its children.
    ///
    /// If the provided `transform` is a translation matrix, it is much faster
    /// to use `pushOffset(_:)` with the translation offset instead.
    ///
    /// **Dart Equivalent:** `void pushTransform(Matrix4 transform)`
    public func pushTransform(_ transform: Matrix4) {
        assert(
            _debugVectorMoreOrLessEquals(transform.getRow(2), Vector4(0, 0, 1, 0))
                && _debugVectorMoreOrLessEquals(transform.getColumn(2), Vector4(0, 0, 1, 0)),
            """
            The third row and third column of a transform matrix for pointer \
            events must be Vector4(0, 0, 1, 0) to ensure that a transformed \
            point is directly under the pointing device. Did you forget to run the paint \
            matrix through PointerEvent.removePerspectiveTransform? \
            The provided matrix is:
            \(transform)
            """
        )
        _root._localTransforms.append(_MatrixTransformPart(transform))
    }

    /// Pushes a new translation offset that is to be applied to all future
    /// `HitTestEntry` instances added via `add(_:)` until it is removed via
    /// `popTransform()`.
    ///
    /// This method is only to be used by subclasses, which must provide
    /// coordinate space specific public wrappers around this function for their
    /// users.
    ///
    /// The provided `offset` should describe how to transform `PointerEvent`s
    /// from the coordinate space of the method caller to the coordinate space of
    /// its children. Usually `offset` is the inverse of the offset of the child
    /// relative to the parent.
    ///
    /// **Dart Equivalent:** `void pushOffset(Offset offset)`
    public func pushOffset(_ offset: Offset) {
        _root._localTransforms.append(_OffsetTransformPart(offset))
    }

    /// Removes the last transform added via `pushTransform(_:)` or
    /// `pushOffset(_:)`.
    ///
    /// This method is only to be used by subclasses, which must provide
    /// coordinate space specific public wrappers around this function for their
    /// users.
    ///
    /// This method must be called after hit testing is done on a child that
    /// required a call to `pushTransform(_:)` or `pushOffset(_:)`.
    ///
    /// **Dart Equivalent:** `void popTransform()`
    public func popTransform() {
        let root = _root
        if !root._localTransforms.isEmpty {
            root._localTransforms.removeLast()
        } else {
            root._transforms.removeLast()
        }
        assert(!root._transforms.isEmpty)
    }

    // MARK: - Debug Helpers

    private func _debugVectorMoreOrLessEquals(
        _ a: Vector4,
        _ b: Vector4,
        epsilon: Double = precisionErrorTolerance
    ) -> Bool {
        var result = true
        assert({
            let dx = a.x - b.x
            let dy = a.y - b.y
            let dz = a.z - b.z
            let dw = a.w - b.w
            result = Swift.abs(dx) < epsilon
                && Swift.abs(dy) < epsilon
                && Swift.abs(dz) < epsilon
                && Swift.abs(dw) < epsilon
            return true
        }())
        return result
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        let root = _root
        if root._path.isEmpty {
            return "HitTestResult(<empty path>)"
        }
        let entries = root._path.map { "\($0)" }.joined(separator: ", ")
        return "HitTestResult(\(entries))"
    }
}
