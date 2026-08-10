// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import FlutterSwiftBridgeCxx

/// Swift implementations of Flutter's compositing.dart types.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart`

// MARK: - Scene

/// An opaque object representing a composited scene.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart`
/// **Original Name:** `Scene` (abstract class)
/// **Lines:** 6-34
///
/// To create a Scene object, use a SceneBuilder.
///
/// Scene objects can be displayed on the screen using the FlutterView.render
/// method.
///
/// DIFFERENCE FROM DART: Using protocol instead of abstract class.
/// REASON: Swift doesn't have abstract classes; protocol provides equivalent
/// functionality for defining the Scene interface.
public protocol Scene: AnyObject {
  /// Synchronously creates a handle to an image from this scene.
  ///
  /// **Dart Source:** `compositing.dart:13-16`
  /// **Original:** `Image toImageSync(int width, int height);`
  ///
  /// {@macro dart.ui.painting.Picture.toImageSync}
  func toImageSync(width: Int, height: Int) -> Image

  /// Creates a raster image representation of the current state of the scene.
  ///
  /// **Dart Source:** `compositing.dart:18-25`
  /// **Original:** `Future<Image> toImage(int width, int height);`
  ///
  /// This is a slow operation that is performed on a background thread.
  ///
  /// Callers must dispose the Image when they are done with it. If the result
  /// will be shared with other methods or classes, Image.clone should be used
  /// and each handle created must be disposed.
  ///
  /// DIFFERENCE FROM DART: Uses Swift async/await instead of Future<Image>.
  /// REASON: Swift's native concurrency model replaces Dart Futures.
  func toImage(width: Int, height: Int) async -> Image

  /// Releases the resources used by this scene.
  ///
  /// **Dart Source:** `compositing.dart:27-33`
  /// **Original:** `void dispose();`
  ///
  /// After calling this function, the scene cannot be used further.
  func dispose()
}

// MARK: - NativeScene

/// Concrete implementation of Scene wrapping a C++ SceneBridge.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart`
/// **Original Name:** `_NativeScene`
/// **Lines:** 36-87
///
/// This class is created by the engine (via SceneBuilder.build()),
/// and should not be instantiated directly.
///
/// DIFFERENCE FROM DART: Class is named `NativeScene` (no underscore prefix).
/// REASON: Swift uses `internal` access control instead of underscore-prefix
/// naming convention for internal types.
public class NativeScene: Scene {
  /// The C++ bridge object that holds the root layer tree.
  ///
  /// **Dart Source:** `compositing.dart:37`
  /// **Original:** `_NativeScene extends NativeFieldWrapperClass1`
  ///
  /// DIFFERENCE FROM DART: Uses SceneBridge with SWIFT_SHARED_REFERENCE
  /// instead of NativeFieldWrapperClass1 / Dart VM wrapper.
  /// REASON: Swift layer calls C++ directly; no Dart VM involvement.
  internal let bridge: flutter.swift_bridge.SceneBridge

  /// Creates a NativeScene wrapping a SceneBridge.
  ///
  /// **Dart Source:** `compositing.dart:38-43`
  /// **Original:** `_NativeScene._()`
  ///
  /// DIFFERENCE FROM DART: Takes a SceneBridge parameter instead of being
  /// engine-created via NativeFieldWrapperClass1.
  /// REASON: Swift creates the wrapper directly around the C++ bridge object.
  internal init(_ bridge: flutter.swift_bridge.SceneBridge) {
    self.bridge = bridge
  }

  /// Synchronously creates a handle to an image from this scene.
  ///
  /// **Dart Source:** `compositing.dart:45-57`
  /// **Original:** `Image toImageSync(int width, int height)`
  ///
  /// The `width` and `height` parameters must be greater than zero.
  ///
  /// DIFFERENCE FROM DART: Not yet implemented. The Dart version calls
  /// `Scene::toImageSync` which uses UIDartState's snapshot delegate
  /// for GPU rasterization and creates a deferred image.
  /// REASON: Requires engine integration layer for deferred image creation.
  public func toImageSync(width: Int, height: Int) -> Image {
    guard width > 0 && height > 0 else {
      fatalError("Invalid image dimensions.")
    }
    // TODO: Implement when engine integration layer provides sync rendering.
    // The Dart version:
    // 1. Creates an _Image._() instance
    // 2. Calls native _toImageSync(width, height, image)
    // 3. On failure, throws PictureRasterizationException
    // 4. Returns Image._(image, image.width, image.height)
    fatalError("Scene.toImageSync requires engine integration (snapshot delegate + task runners)")
  }

  /// Creates a raster image representation of the current state of the scene.
  ///
  /// **Dart Source:** `compositing.dart:62-76`
  /// **Original:** `Future<Image> toImage(int width, int height)`
  ///
  /// This is a slow operation that is performed on a background thread.
  ///
  /// DIFFERENCE FROM DART: Uses Swift async/await instead of Future<Image>.
  /// Also not yet implemented — the Dart version uses `_futurize` with
  /// `Scene::toImage` which requires UIDartState for task runner access and
  /// SnapshotDelegate.
  /// REASON: Requires engine integration layer for async rendering pipeline.
  public func toImage(width: Int, height: Int) async -> Image {
    guard width > 0 && height > 0 else {
      fatalError("Invalid image dimensions.")
    }
    // TODO: Implement when engine integration layer provides async rendering.
    // The Dart version:
    // 1. Calls _futurize with a callback
    // 2. Inside, calls native _toImage(width, height, callback)
    // 3. The callback wraps the returned _Image in Image._(image, w, h)
    fatalError("Scene.toImage requires engine integration (snapshot delegate + task runners)")
  }

  /// Releases the resources used by this scene.
  ///
  /// **Dart Source:** `compositing.dart:81-83`
  /// **Original:** `@Native<Void Function(Pointer<Void>)>(symbol: 'Scene::dispose')`
  /// `external void dispose();`
  ///
  /// After calling this function, the scene cannot be used further.
  public func dispose() {
    bridge.Dispose()
  }

  /// Returns a string representation of this scene.
  ///
  /// **Dart Source:** `compositing.dart:85-86`
  /// **Original:** `String toString() => 'Scene';`
  public var description: String {
    "Scene"
  }
}

// MARK: - EngineLayerWrapper

/// Lightweight wrapper of a native layer object.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart`
/// **Original Name:** `_EngineLayerWrapper`
/// **Lines:** 96-135
///
/// This is used to provide a typed API for engine layers to prevent
/// incompatible layers from being passed to SceneBuilder's push methods.
/// For example, this prevents a layer returned from `pushOpacity` from being
/// passed as `oldLayer` to `pushTransform`. This is achieved by having one
/// concrete subclass of this class per push method.
///
/// DIFFERENCE FROM DART: Class is named `EngineLayerWrapper` (no underscore prefix).
/// REASON: Swift uses `internal` access control instead of underscore-prefix
/// naming convention for internal types.
///
/// DIFFERENCE FROM DART: Implements EngineLayer protocol instead of using `implements` keyword.
/// REASON: Swift uses protocol conformance instead of Dart's `implements`.
public class EngineLayerWrapper: EngineLayer {
  /// Creates an EngineLayerWrapper wrapping a native EngineLayer.
  ///
  /// **Dart Source:** `compositing.dart:97`
  /// **Original:** `_EngineLayerWrapper._(EngineLayer nativeLayer) : _nativeLayer = nativeLayer;`
  internal init(_ nativeLayer: EngineLayer) {
    self._nativeLayer = nativeLayer
  }

  /// The underlying native engine layer.
  ///
  /// **Dart Source:** `compositing.dart:99`
  /// **Original:** `EngineLayer? _nativeLayer;`
  ///
  /// Nullable to support disposal — set to nil after dispose in debug mode.
  internal var _nativeLayer: EngineLayer?

  /// Releases resources used by this layer and its children.
  ///
  /// **Dart Source:** `compositing.dart:101-109`
  /// **Original:**
  /// ```dart
  /// @override
  /// void dispose() {
  ///   assert(_nativeLayer != null, 'Object disposed');
  ///   _nativeLayer!.dispose();
  ///   assert(() {
  ///     _nativeLayer = null;
  ///     return true;
  ///   }());
  /// }
  /// ```
  public func dispose() {
    assert(_nativeLayer != nil, "Object disposed")
    _nativeLayer!.dispose()
    assert({
      _nativeLayer = nil
      return true
    }())
  }

  /// Children of this layer.
  ///
  /// **Dart Source:** `compositing.dart:111-115`
  /// **Original:** `List<_EngineLayerWrapper>? _debugChildren;`
  ///
  /// Null if this layer has no children. This field is populated only in debug
  /// mode.
  internal var _debugChildren: [EngineLayerWrapper]?

  /// Whether this layer was used as `oldLayer` in a past frame.
  ///
  /// **Dart Source:** `compositing.dart:117-121`
  /// **Original:** `bool _debugWasUsedAsOldLayer = false;`
  ///
  /// It is illegal to use a layer object again after it is passed as an
  /// `oldLayer` argument.
  internal var _debugWasUsedAsOldLayer: Bool = false

  /// Debug assertion that this layer has not been used as an oldLayer.
  ///
  /// **Dart Source:** `compositing.dart:123-134`
  /// **Original:** `bool _debugCheckNotUsedAsOldLayer()`
  ///
  /// The hashCode formatting matches shortHash in the framework.
  internal func _debugCheckNotUsedAsOldLayer() -> Bool {
    assert(
      !_debugWasUsedAsOldLayer,
      "Layer \(type(of: self))#\(String(UInt(bitPattern: ObjectIdentifier(self)) & 0xFFFFF, radix: 16, uppercase: false).paddingLeft(toLength: 5, withPad: "0")) was previously used as oldLayer.\n"
        + "Once a layer is used as oldLayer, it may not be used again. Instead, "
        + "after calling one of the SceneBuilder.push* methods and passing an oldLayer "
        + "to it, use the layer returned by the method as oldLayer in subsequent "
        + "frames."
    )
    return true
  }
}

// MARK: - TransformEngineLayer

/// An opaque handle to a transform engine layer.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart`
/// **Original Name:** `TransformEngineLayer`
/// **Lines:** 137-148
///
/// Instances of this class are created by SceneBuilder.pushTransform.
///
/// `oldLayer` parameter in SceneBuilder methods only accepts objects created
/// by the engine. SceneBuilder will throw an AssertionError if you pass it
/// a custom implementation of this class.
public class TransformEngineLayer: EngineLayerWrapper {
  /// Creates a TransformEngineLayer wrapping a native EngineLayer.
  ///
  /// **Dart Source:** `compositing.dart:147`
  /// **Original:** `TransformEngineLayer._(super.nativeLayer) : super._();`
  internal override init(_ nativeLayer: EngineLayer) {
    super.init(nativeLayer)
  }
}

// MARK: - OffsetEngineLayer

/// An opaque handle to an offset engine layer.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart`
/// **Original Name:** `OffsetEngineLayer`
/// **Lines:** 150-157
///
/// Instances of this class are created by SceneBuilder.pushOffset.
///
/// `oldLayer` parameter in SceneBuilder methods only accepts objects created
/// by the engine. SceneBuilder will throw an AssertionError if you pass it
/// a custom implementation of this class.
public class OffsetEngineLayer: EngineLayerWrapper {
  /// Creates an OffsetEngineLayer wrapping a native EngineLayer.
  ///
  /// **Dart Source:** `compositing.dart:156`
  /// **Original:** `OffsetEngineLayer._(super.nativeLayer) : super._();`
  internal override init(_ nativeLayer: EngineLayer) {
    super.init(nativeLayer)
  }
}

// MARK: - ClipRectEngineLayer
/// An opaque handle to a clip rect engine layer.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart`
/// **Original Name:** `ClipRectEngineLayer`
/// **Lines:** 159-166
///
/// Instances of this class are created by `SceneBuilder.pushClipRect`.
///
/// `oldLayer` parameter in SceneBuilder methods only accepts objects created
/// by the engine. SceneBuilder will throw an AssertionError if you pass it
/// a custom implementation of this class.
public class ClipRectEngineLayer: EngineLayerWrapper {
  /// Creates a ClipRectEngineLayer wrapping a native EngineLayer.
  ///
  /// **Dart Source:** `compositing.dart:165`
  /// **Original:** `ClipRectEngineLayer._(super.nativeLayer) : super._();`
  internal override init(_ nativeLayer: EngineLayer) {
    super.init(nativeLayer)
  }
}

// MARK: - ClipRRectEngineLayer
/// An opaque handle to a clip rounded rect engine layer.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart`
/// **Original Name:** `ClipRRectEngineLayer`
/// **Lines:** 168-175
///
/// Instances of this class are created by `SceneBuilder.pushClipRRect`.
///
/// `oldLayer` parameter in SceneBuilder methods only accepts objects created
/// by the engine. SceneBuilder will throw an AssertionError if you pass it
/// a custom implementation of this class.
public class ClipRRectEngineLayer: EngineLayerWrapper {
  /// Creates a ClipRRectEngineLayer wrapping a native EngineLayer.
  ///
  /// **Dart Source:** `compositing.dart:174`
  /// **Original:** `ClipRRectEngineLayer._(super.nativeLayer) : super._();`
  internal override init(_ nativeLayer: EngineLayer) {
    super.init(nativeLayer)
  }
}

// MARK: - ClipRSuperellipseEngineLayer
/// An opaque handle to a clip rounded superellipse engine layer.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart`
/// **Original Name:** `ClipRSuperellipseEngineLayer`
/// **Lines:** 177-184
///
/// Instances of this class are created by `SceneBuilder.pushClipRSuperellipse`.
///
/// `oldLayer` parameter in SceneBuilder methods only accepts objects created
/// by the engine. SceneBuilder will throw an AssertionError if you pass it
/// a custom implementation of this class.
public class ClipRSuperellipseEngineLayer: EngineLayerWrapper {
  /// Creates a ClipRSuperellipseEngineLayer wrapping a native EngineLayer.
  ///
  /// **Dart Source:** `compositing.dart:183`
  /// **Original:** `ClipRSuperellipseEngineLayer._(super.nativeLayer) : super._();`
  internal override init(_ nativeLayer: EngineLayer) {
    super.init(nativeLayer)
  }
}

// MARK: - ClipPathEngineLayer
/// An opaque handle to a clip path engine layer.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart`
/// **Original Name:** `ClipPathEngineLayer`
/// **Lines:** 186-193
///
/// Instances of this class are created by `SceneBuilder.pushClipPath`.
///
/// `oldLayer` parameter in SceneBuilder methods only accepts objects created
/// by the engine. SceneBuilder will throw an AssertionError if you pass it
/// a custom implementation of this class.
public class ClipPathEngineLayer: EngineLayerWrapper {
  /// Creates a ClipPathEngineLayer wrapping a native EngineLayer.
  ///
  /// **Dart Source:** `compositing.dart:192`
  /// **Original:** `ClipPathEngineLayer._(super.nativeLayer) : super._();`
  internal override init(_ nativeLayer: EngineLayer) {
    super.init(nativeLayer)
  }
}

// MARK: - OpacityEngineLayer
/// An opaque handle to an opacity engine layer.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart`
/// **Original Name:** `OpacityEngineLayer`
/// **Lines:** 195-202
///
/// Instances of this class are created by `SceneBuilder.pushOpacity`.
///
/// `oldLayer` parameter in SceneBuilder methods only accepts objects created
/// by the engine. SceneBuilder will throw an AssertionError if you pass it
/// a custom implementation of this class.
public class OpacityEngineLayer: EngineLayerWrapper {
  /// Creates an OpacityEngineLayer wrapping a native EngineLayer.
  ///
  /// **Dart Source:** `compositing.dart:201`
  /// **Original:** `OpacityEngineLayer._(super.nativeLayer) : super._();`
  internal override init(_ nativeLayer: EngineLayer) {
    super.init(nativeLayer)
  }
}

// MARK: - ColorFilterEngineLayer
/// An opaque handle to a color filter engine layer.
///
/// Instances of this class are created by `SceneBuilder.pushColorFilter`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart`
/// **Original Name:** `ColorFilterEngineLayer`
/// **Lines:** 204-211
public class ColorFilterEngineLayer: EngineLayerWrapper {
  /// Creates a ColorFilterEngineLayer wrapping a native EngineLayer.
  ///
  /// **Dart Source:** `compositing.dart:210`
  /// **Original:** `ColorFilterEngineLayer._(super.nativeLayer) : super._();`
  internal override init(_ nativeLayer: EngineLayer) {
    super.init(nativeLayer)
  }
}

// MARK: - ImageFilterEngineLayer
/// An opaque handle to an image filter engine layer.
///
/// Instances of this class are created by `SceneBuilder.pushImageFilter`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart`
/// **Original Name:** `ImageFilterEngineLayer`
/// **Lines:** 213-220
public class ImageFilterEngineLayer: EngineLayerWrapper {
  /// Creates an ImageFilterEngineLayer wrapping a native EngineLayer.
  ///
  /// **Dart Source:** `compositing.dart:219`
  /// **Original:** `ImageFilterEngineLayer._(super.nativeLayer) : super._();`
  internal override init(_ nativeLayer: EngineLayer) {
    super.init(nativeLayer)
  }
}

// MARK: - BackdropFilterEngineLayer
/// An opaque handle to a backdrop filter engine layer.
///
/// Instances of this class are created by `SceneBuilder.pushBackdropFilter`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart`
/// **Original Name:** `BackdropFilterEngineLayer`
/// **Lines:** 222-229
public class BackdropFilterEngineLayer: EngineLayerWrapper {
  /// Creates a BackdropFilterEngineLayer wrapping a native EngineLayer.
  ///
  /// **Dart Source:** `compositing.dart:228`
  /// **Original:** `BackdropFilterEngineLayer._(super.nativeLayer) : super._();`
  internal override init(_ nativeLayer: EngineLayer) {
    super.init(nativeLayer)
  }
}

// MARK: - ShaderMaskEngineLayer
/// An opaque handle to a shader mask engine layer.
///
/// Instances of this class are created by `SceneBuilder.pushShaderMask`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart`
/// **Original Name:** `ShaderMaskEngineLayer`
/// **Lines:** 231-238
public class ShaderMaskEngineLayer: EngineLayerWrapper {
  /// Creates a ShaderMaskEngineLayer wrapping a native EngineLayer.
  ///
  /// **Dart Source:** `compositing.dart:237`
  /// **Original:** `ShaderMaskEngineLayer._(super.nativeLayer) : super._();`
  internal override init(_ nativeLayer: EngineLayer) {
    super.init(nativeLayer)
  }
}

// MARK: - SceneBuilder

/// Builds a Scene containing the given visuals.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart`
/// **Original Name:** `SceneBuilder` (abstract class)
/// **Lines:** 240-591
///
/// A Scene can then be rendered using FlutterView.render.
///
/// To draw graphical operations onto a Scene, first create a
/// Picture using a PictureRecorder and a Canvas, and then add
/// it to the scene using addPicture.
///
/// DIFFERENCE FROM DART: Using protocol instead of abstract class.
/// REASON: Swift doesn't have abstract classes; protocol provides equivalent
/// functionality for defining the SceneBuilder interface.
///
/// DIFFERENCE FROM DART: Factory constructor `SceneBuilder()` is not
/// represented in the protocol. In Swift, instantiation is done via
/// `NativeSceneBuilder()` directly (to be implemented in Task 3.3).
/// REASON: Swift protocols cannot have factory constructors. The Dart
/// factory constructor `SceneBuilder() = _NativeSceneBuilder` is a
/// forwarding constructor pattern that doesn't translate to Swift protocols.
public protocol SceneBuilder: AnyObject {

  /// Pushes a transform operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:264-292`
  /// **Original:** `TransformEngineLayer pushTransform(Float64List matrix4, {TransformEngineLayer? oldLayer});`
  ///
  /// The objects are transformed by the given matrix before rasterization.
  ///
  /// If `oldLayer` is not null the engine will attempt to reuse the resources
  /// allocated for the old layer when rendering the new layer.
  ///
  /// See pop() for details about the operation stack.
  func pushTransform(_ matrix4: [Double], oldLayer: TransformEngineLayer?) -> TransformEngineLayer

  /// Pushes an offset operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:294-303`
  /// **Original:** `OffsetEngineLayer pushOffset(double dx, double dy, {OffsetEngineLayer? oldLayer});`
  ///
  /// This is equivalent to pushTransform with a matrix with only translation.
  ///
  /// See pop() for details about the operation stack.
  func pushOffset(_ dx: Double, _ dy: Double, oldLayer: OffsetEngineLayer?) -> OffsetEngineLayer

  /// Pushes a rectangular clip operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:305-319`
  /// **Original:** `ClipRectEngineLayer pushClipRect(Rect rect, {Clip clipBehavior = Clip.antiAlias, ClipRectEngineLayer? oldLayer});`
  ///
  /// Rasterization outside the given rectangle is discarded.
  ///
  /// See pop() for details about the operation stack, and Clip for different clip modes.
  /// By default, the clip will be anti-aliased (clip = Clip.antiAlias).
  func pushClipRect(_ rect: Rect, clipBehavior: Clip, oldLayer: ClipRectEngineLayer?) -> ClipRectEngineLayer

  /// Pushes a rounded-rectangular clip operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:321-335`
  /// **Original:** `ClipRRectEngineLayer pushClipRRect(RRect rrect, {Clip clipBehavior = Clip.antiAlias, ClipRRectEngineLayer? oldLayer});`
  ///
  /// Rasterization outside the given rounded rectangle is discarded.
  ///
  /// See pop() for details about the operation stack, and Clip for different clip modes.
  /// By default, the clip will be anti-aliased (clip = Clip.antiAlias).
  func pushClipRRect(_ rrect: RRect, clipBehavior: Clip, oldLayer: ClipRRectEngineLayer?) -> ClipRRectEngineLayer

  /// Pushes a rounded-superellipse clip operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:337-351`
  /// **Original:** `ClipRSuperellipseEngineLayer pushClipRSuperellipse(RSuperellipse rsuperellipse, {Clip clipBehavior = Clip.antiAlias, ClipRSuperellipseEngineLayer? oldLayer});`
  ///
  /// Rasterization outside the given rounded superellipse is discarded.
  ///
  /// See pop() for details about the operation stack, and Clip for different clip modes.
  /// By default, the clip will be anti-aliased (clip = Clip.antiAlias).
  func pushClipRSuperellipse(_ rsuperellipse: RSuperellipse, clipBehavior: Clip, oldLayer: ClipRSuperellipseEngineLayer?) -> ClipRSuperellipseEngineLayer

  /// Pushes a path clip operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:353-367`
  /// **Original:** `ClipPathEngineLayer pushClipPath(Path path, {Clip clipBehavior = Clip.antiAlias, ClipPathEngineLayer? oldLayer});`
  ///
  /// Rasterization outside the given path is discarded.
  ///
  /// See pop() for details about the operation stack. See Clip for different clip modes.
  /// By default, the clip will be anti-aliased (clip = Clip.antiAlias).
  func pushClipPath(_ path: Path, clipBehavior: Clip, oldLayer: ClipPathEngineLayer?) -> ClipPathEngineLayer

  /// Pushes an opacity operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:369-385`
  /// **Original:** `OpacityEngineLayer pushOpacity(int alpha, {Offset? offset = Offset.zero, OpacityEngineLayer? oldLayer});`
  ///
  /// The given alpha value is blended into the alpha value of the objects'
  /// rasterization. An alpha value of 0 makes the objects entirely invisible.
  /// An alpha value of 255 has no effect (i.e., the objects retain the current
  /// opacity).
  ///
  /// See pop() for details about the operation stack.
  func pushOpacity(_ alpha: Int, offset: Offset?, oldLayer: OpacityEngineLayer?) -> OpacityEngineLayer

  /// Pushes a color filter operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:387-397`
  /// **Original:** `ColorFilterEngineLayer pushColorFilter(ColorFilter filter, {ColorFilterEngineLayer? oldLayer});`
  ///
  /// The given color filter is applied to the objects' rasterization.
  ///
  /// See pop() for details about the operation stack.
  func pushColorFilter(_ filter: ColorFilter, oldLayer: ColorFilterEngineLayer?) -> ColorFilterEngineLayer

  /// Pushes an image filter operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:399-413`
  /// **Original:** `ImageFilterEngineLayer pushImageFilter(ImageFilter filter, {Offset offset = Offset.zero, ImageFilterEngineLayer? oldLayer});`
  ///
  /// The given filter is applied to the children's rasterization before
  /// compositing them into the scene.
  ///
  /// See pop() for details about the operation stack.
  func pushImageFilter(_ filter: any ImageFilter, offset: Offset, oldLayer: ImageFilterEngineLayer?) -> ImageFilterEngineLayer

  /// Pushes a backdrop filter operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:415-445`
  /// **Original:** `BackdropFilterEngineLayer pushBackdropFilter(ImageFilter filter, {BlendMode blendMode = BlendMode.srcOver, BackdropFilterEngineLayer? oldLayer, int? backdropId});`
  ///
  /// The given filter is applied to the current contents of the scene as far back as
  /// the most recent save layer and rendered back to the scene using the indicated
  /// blendMode prior to rasterizing the child layers.
  ///
  /// If backdropId is provided and not null, then this value is treated
  /// as a unique identifier for the backdrop.
  ///
  /// See pop() for details about the operation stack.
  func pushBackdropFilter(_ filter: any ImageFilter, blendMode: BlendMode, oldLayer: BackdropFilterEngineLayer?, backdropId: Int?) -> BackdropFilterEngineLayer

  /// Pushes a shader mask operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:447-463`
  /// **Original:** `ShaderMaskEngineLayer pushShaderMask(Shader shader, Rect maskRect, BlendMode blendMode, {ShaderMaskEngineLayer? oldLayer, FilterQuality filterQuality = FilterQuality.low});`
  ///
  /// The given shader is applied to the object's rasterization in the given
  /// rectangle using the given blend mode.
  ///
  /// See pop() for details about the operation stack.
  func pushShaderMask(_ shader: Shader, maskRect: Rect, blendMode: BlendMode, oldLayer: ShaderMaskEngineLayer?, filterQuality: FilterQuality) -> ShaderMaskEngineLayer

  /// Ends the effect of the most recently pushed operation.
  ///
  /// **Dart Source:** `compositing.dart:465-471`
  /// **Original:** `void pop();`
  ///
  /// Internally the scene builder maintains a stack of operations. Each of the
  /// operations in the stack applies to each of the objects added to the scene.
  /// Calling this function removes the most recently added operation from the
  /// stack.
  func pop()

  /// Add a retained engine layer subtree from previous frames.
  ///
  /// **Dart Source:** `compositing.dart:473-483`
  /// **Original:** `void addRetained(EngineLayer retainedLayer);`
  ///
  /// All the engine layers that are in the subtree of the retained layer will
  /// be automatically appended to the current engine layer tree.
  func addRetained(_ retainedLayer: EngineLayer)

  /// Adds an object to the scene that displays performance statistics.
  ///
  /// **Dart Source:** `compositing.dart:485-509`
  /// **Original:** `void addPerformanceOverlay(int enabledOptions, Rect bounds);`
  ///
  /// enabledOptions is a bit field with the following bits defined:
  ///  - 0x01: displayRasterizerStatistics - show raster thread frame time
  ///  - 0x02: visualizeRasterizerStatistics - graph raster thread frame times
  ///  - 0x04: displayEngineStatistics - show UI thread frame time
  ///  - 0x08: visualizeEngineStatistics - graph UI thread frame times
  /// Set enabledOptions to 0x0F to enable all the currently defined features.
  func addPerformanceOverlay(_ enabledOptions: Int, bounds: Rect)

  /// Adds a Picture to the scene.
  ///
  /// **Dart Source:** `compositing.dart:511-537`
  /// **Original:** `void addPicture(Offset offset, Picture picture, {bool isComplexHint = false, bool willChangeHint = false});`
  ///
  /// The picture is rasterized at the given offset.
  func addPicture(_ offset: Offset, picture: any Picture, isComplexHint: Bool, willChangeHint: Bool)

  /// Adds a backend texture to the scene.
  ///
  /// **Dart Source:** `compositing.dart:539-557`
  /// **Original:** `void addTexture(int textureId, {Offset offset = Offset.zero, double width = 0.0, double height = 0.0, bool freeze = false, FilterQuality filterQuality = FilterQuality.low});`
  ///
  /// The texture is scaled to the given size and rasterized at the given offset.
  func addTexture(_ textureId: Int, offset: Offset, width: Double, height: Double, freeze: Bool, filterQuality: FilterQuality)

  /// Adds a platform view (e.g an iOS UIView) to the scene.
  ///
  /// **Dart Source:** `compositing.dart:559-580`
  /// **Original:** `void addPlatformView(int viewId, {Offset offset = Offset.zero, double width = 0.0, double height = 0.0});`
  ///
  /// On iOS this layer splits the current output surface into two surfaces,
  /// one for the scene nodes preceding the platform view, and one for the
  /// scene nodes following the platform view.
  func addPlatformView(_ viewId: Int, offset: Offset, width: Double, height: Double)

  /// Finishes building the scene.
  ///
  /// **Dart Source:** `compositing.dart:582-590`
  /// **Original:** `Scene build();`
  ///
  /// Returns a Scene containing the objects that have been added to
  /// this scene builder. The Scene can then be displayed on the
  /// screen with FlutterView.render.
  ///
  /// After calling this function, the scene builder object is invalid and
  /// cannot be used further.
  func build() -> Scene
}

// MARK: - NativeSceneBuilder

/// Concrete implementation of SceneBuilder wrapping a C++ SceneBuilderBridge.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart`
/// **Original Name:** `_NativeSceneBuilder`
/// **Lines:** 593-1084
///
/// This class manages the layer tree building process. Each push* method
/// creates a new layer via the C++ bridge, wraps it in a typed EngineLayerWrapper,
/// and tracks it on the layer stack for debug validation.
///
/// DIFFERENCE FROM DART: Class is named `NativeSceneBuilder` (no underscore prefix).
/// REASON: Swift uses `public`/`internal` access control instead of underscore-prefix
/// naming convention for internal types.
///
/// DIFFERENCE FROM DART: Does not extend NativeFieldWrapperClass1.
/// REASON: Swift layer calls C++ directly via SceneBuilderBridge with
/// SWIFT_SHARED_REFERENCE; no Dart VM involvement.
public class NativeSceneBuilder: SceneBuilder {

  /// The C++ bridge object that manages the layer tree.
  ///
  /// **Dart Source:** `compositing.dart:594-600`
  /// **Original:** `_NativeSceneBuilder()` constructor calling
  ///   `@Native SceneBuilder::Create`
  ///
  /// DIFFERENCE FROM DART: Uses SceneBuilderBridge with SWIFT_SHARED_REFERENCE
  /// instead of NativeFieldWrapperClass1 / Dart VM wrapper.
  /// REASON: Swift layer calls C++ directly; no Dart VM involvement.
  internal let bridge: flutter.swift_bridge.SceneBuilderBridge

  /// Layers used in this scene.
  ///
  /// **Dart Source:** `compositing.dart:602-606`
  /// **Original:** `final Map<EngineLayer, String> _usedLayers = <EngineLayer, String>{};`
  ///
  /// The key is the layer used. The value is the description of what the layer
  /// is used for, e.g. "pushOpacity" or "addRetained".
  ///
  /// DIFFERENCE FROM DART: Uses ObjectIdentifier as key since EngineLayer is a
  /// protocol (not Hashable) in Swift.
  /// REASON: Swift protocols don't automatically conform to Hashable; we use
  /// ObjectIdentifier for identity-based lookups.
  private var _usedLayers: [ObjectIdentifier: String] = [:]

  /// Texture ids added to this scene. `RenderView.compositeFrame` reads this
  /// so each view knows which external textures its last scene contains —
  /// the basis for per-view composite gating when texture content updates
  /// with no widget change. Complete every build: texture layers are
  /// `alwaysNeedsAddToScene`, so no ancestor of one is ever retained.
  public private(set) var addedTextureIds: Set<Int64> = []

  /// The stack of layers being built.
  ///
  /// **Dart Source:** `compositing.dart:639`
  /// **Original:** `final List<_EngineLayerWrapper> _layerStack = <_EngineLayerWrapper>[];`
  private var _layerStack: [EngineLayerWrapper] = []

  /// Creates an empty SceneBuilder.
  ///
  /// **Dart Source:** `compositing.dart:594-597`
  /// **Original:** `_NativeSceneBuilder() { _constructor(); }`
  public init() {
    self.bridge = flutter.swift_bridge.SceneBuilderBridge()
  }

  // MARK: - Debug Helpers

  /// In debug mode checks that the `layer` is only used once in a given scene.
  ///
  /// **Dart Source:** `compositing.dart:609-623`
  /// **Original:** `bool _debugCheckUsedOnce(EngineLayer layer, String usage)`
  private func _debugCheckUsedOnce(_ layer: EngineLayer, _ usage: String) -> Bool {
    assert({
      let id = ObjectIdentifier(layer)
      assert(
        _usedLayers[id] == nil,
        "Layer \(type(of: layer)) already used.\n"
          + "The layer is already being used as \(_usedLayers[id] ?? "") in this scene.\n"
          + "A layer may only be used once in a given scene."
      )
      _usedLayers[id] = usage
      return true
    }())
    return true
  }

  /// Validates that an old layer can be reused.
  ///
  /// **Dart Source:** `compositing.dart:625-637`
  /// **Original:** `bool _debugCheckCanBeUsedAsOldLayer(_EngineLayerWrapper? layer, String methodName)`
  private func _debugCheckCanBeUsedAsOldLayer(_ layer: EngineLayerWrapper?, _ methodName: String) -> Bool {
    assert({
      guard let layer = layer else {
        return true
      }
      assert(layer._nativeLayer != nil, "Object disposed")
      _ = layer._debugCheckNotUsedAsOldLayer()
      assert(_debugCheckUsedOnce(layer, "oldLayer in \(methodName)"))
      layer._debugWasUsedAsOldLayer = true
      return true
    }())
    return true
  }

  /// Pushes the `newLayer` onto the `_layerStack` and adds it to the
  /// `_debugChildren` of the current layer in the stack, if any.
  ///
  /// **Dart Source:** `compositing.dart:643-654`
  /// **Original:** `bool _debugPushLayer(_EngineLayerWrapper newLayer)`
  private func _debugPushLayer(_ newLayer: EngineLayerWrapper) -> Bool {
    assert({
      if !_layerStack.isEmpty {
        let currentLayer = _layerStack.last!
        if currentLayer._debugChildren == nil {
          currentLayer._debugChildren = []
        }
        currentLayer._debugChildren!.append(newLayer)
      }
      _layerStack.append(newLayer)
      return true
    }())
    return true
  }

  // MARK: - Push Methods

  /// Pushes a transform operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:656-665`
  /// **Original:** `TransformEngineLayer pushTransform(Float64List matrix4, {TransformEngineLayer? oldLayer})`
  public func pushTransform(_ matrix4: [Double], oldLayer: TransformEngineLayer? = nil) -> TransformEngineLayer {
    assert(matrix4IsValid(matrix4))
    assert(_debugCheckCanBeUsedAsOldLayer(oldLayer, "pushTransform"))
    let engineLayerBridge = matrix4.withUnsafeBufferPointer { buffer in
      bridge.PushTransform(buffer.baseAddress, oldLayer?.nativeEngineLayerBridge)
    }!
    let engineLayer = NativeEngineLayer(bridge: engineLayerBridge)
    let layer = TransformEngineLayer(engineLayer)
    assert(_debugPushLayer(layer))
    return layer
  }

  /// Pushes an offset operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:672-680`
  /// **Original:** `OffsetEngineLayer pushOffset(double dx, double dy, {OffsetEngineLayer? oldLayer})`
  public func pushOffset(_ dx: Double, _ dy: Double, oldLayer: OffsetEngineLayer? = nil) -> OffsetEngineLayer {
    assert(_debugCheckCanBeUsedAsOldLayer(oldLayer, "pushOffset"))
    let engineLayerBridge = bridge.PushOffset(dx, dy, oldLayer?.nativeEngineLayerBridge)!
    let engineLayer = NativeEngineLayer(bridge: engineLayerBridge)
    let layer = OffsetEngineLayer(engineLayer)
    assert(_debugPushLayer(layer))
    return layer
  }

  /// Pushes a rectangular clip operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:687-708`
  /// **Original:** `ClipRectEngineLayer pushClipRect(Rect rect, {Clip clipBehavior = Clip.antiAlias, ClipRectEngineLayer? oldLayer})`
  public func pushClipRect(_ rect: Rect, clipBehavior: Clip = .antiAlias, oldLayer: ClipRectEngineLayer? = nil) -> ClipRectEngineLayer {
    assert(clipBehavior != .none)
    assert(_debugCheckCanBeUsedAsOldLayer(oldLayer, "pushClipRect"))
    let engineLayerBridge = bridge.PushClipRect(
      rect.left, rect.top, rect.right, rect.bottom,
      Int32(clipBehavior.rawValue),
      oldLayer?.nativeEngineLayerBridge
    )!
    let engineLayer = NativeEngineLayer(bridge: engineLayerBridge)
    let layer = ClipRectEngineLayer(engineLayer)
    assert(_debugPushLayer(layer))
    return layer
  }

  /// Pushes a rounded-rectangular clip operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:723-736`
  /// **Original:** `ClipRRectEngineLayer pushClipRRect(RRect rrect, {Clip clipBehavior = Clip.antiAlias, ClipRRectEngineLayer? oldLayer})`
  public func pushClipRRect(_ rrect: RRect, clipBehavior: Clip = .antiAlias, oldLayer: ClipRRectEngineLayer? = nil) -> ClipRRectEngineLayer {
    assert(clipBehavior != .none)
    assert(_debugCheckCanBeUsedAsOldLayer(oldLayer, "pushClipRRect"))
    // Encode RRect as 12 floats matching Dart's RRect._getValue32()
    let values: [Float] = [
      Float(rrect.left), Float(rrect.top), Float(rrect.right), Float(rrect.bottom),
      Float(rrect.tlRadiusX), Float(rrect.tlRadiusY),
      Float(rrect.trRadiusX), Float(rrect.trRadiusY),
      Float(rrect.brRadiusX), Float(rrect.brRadiusY),
      Float(rrect.blRadiusX), Float(rrect.blRadiusY),
    ]
    let engineLayerBridge = values.withUnsafeBufferPointer { buffer in
      bridge.PushClipRRect(buffer.baseAddress, Int32(clipBehavior.rawValue), oldLayer?.nativeEngineLayerBridge)
    }!
    let engineLayer = NativeEngineLayer(bridge: engineLayerBridge)
    let layer = ClipRRectEngineLayer(engineLayer)
    assert(_debugPushLayer(layer))
    return layer
  }

  /// Pushes a rounded-superellipse clip operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:748-766`
  /// **Original:** `ClipRSuperellipseEngineLayer pushClipRSuperellipse(RSuperellipse rsuperellipse, {Clip clipBehavior = Clip.antiAlias, ClipRSuperellipseEngineLayer? oldLayer})`
  public func pushClipRSuperellipse(_ rsuperellipse: RSuperellipse, clipBehavior: Clip = .antiAlias, oldLayer: ClipRSuperellipseEngineLayer? = nil) -> ClipRSuperellipseEngineLayer {
    assert(clipBehavior != .none)
    assert(_debugCheckCanBeUsedAsOldLayer(oldLayer, "pushClipRSuperellipse"))
    let engineLayerBridge = bridge.PushClipRSuperellipse(
      rsuperellipse.left, rsuperellipse.top, rsuperellipse.right, rsuperellipse.bottom,
      rsuperellipse.tlRadiusX, rsuperellipse.tlRadiusY,
      rsuperellipse.trRadiusX, rsuperellipse.trRadiusY,
      rsuperellipse.brRadiusX, rsuperellipse.brRadiusY,
      rsuperellipse.blRadiusX, rsuperellipse.blRadiusY,
      Int32(clipBehavior.rawValue),
      oldLayer?.nativeEngineLayerBridge
    )!
    let engineLayer = NativeEngineLayer(bridge: engineLayerBridge)
    let layer = ClipRSuperellipseEngineLayer(engineLayer)
    assert(_debugPushLayer(layer))
    return layer
  }

  /// Pushes a path clip operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:778-791`
  /// **Original:** `ClipPathEngineLayer pushClipPath(Path path, {Clip clipBehavior = Clip.antiAlias, ClipPathEngineLayer? oldLayer})`
  public func pushClipPath(_ path: Path, clipBehavior: Clip = .antiAlias, oldLayer: ClipPathEngineLayer? = nil) -> ClipPathEngineLayer {
    assert(clipBehavior != .none)
    assert(_debugCheckCanBeUsedAsOldLayer(oldLayer, "pushClipPath"))
    let engineLayerBridge = bridge.PushClipPath(
      path.bridge,
      Int32(clipBehavior.rawValue),
      oldLayer?.nativeEngineLayerBridge
    )!
    let engineLayer = NativeEngineLayer(bridge: engineLayerBridge)
    let layer = ClipPathEngineLayer(engineLayer)
    assert(_debugPushLayer(layer))
    return layer
  }

  /// Pushes an opacity operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:803-815`
  /// **Original:** `OpacityEngineLayer pushOpacity(int alpha, {Offset? offset = Offset.zero, OpacityEngineLayer? oldLayer})`
  public func pushOpacity(_ alpha: Int, offset: Offset? = Offset.zero, oldLayer: OpacityEngineLayer? = nil) -> OpacityEngineLayer {
    assert(_debugCheckCanBeUsedAsOldLayer(oldLayer, "pushOpacity"))
    let dx = offset?.dx ?? 0.0
    let dy = offset?.dy ?? 0.0
    let engineLayerBridge = bridge.PushOpacity(Int32(alpha), dx, dy, oldLayer?.nativeEngineLayerBridge)!
    let engineLayer = NativeEngineLayer(bridge: engineLayerBridge)
    let layer = OpacityEngineLayer(engineLayer)
    assert(_debugPushLayer(layer))
    return layer
  }

  /// Pushes a color filter operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:828-837`
  /// **Original:** `ColorFilterEngineLayer pushColorFilter(ColorFilter filter, {ColorFilterEngineLayer? oldLayer})`
  public func pushColorFilter(_ filter: ColorFilter, oldLayer: ColorFilterEngineLayer? = nil) -> ColorFilterEngineLayer {
    assert(_debugCheckCanBeUsedAsOldLayer(oldLayer, "pushColorFilter"))
    let nativeFilter = filter.toNativeColorFilter()
    let engineLayerBridge = bridge.PushColorFilter(nativeFilter.bridge, oldLayer?.nativeEngineLayerBridge)!
    let engineLayer = NativeEngineLayer(bridge: engineLayerBridge)
    let layer = ColorFilterEngineLayer(engineLayer)
    assert(_debugPushLayer(layer))
    return layer
  }

  /// Pushes an image filter operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:844-857`
  /// **Original:** `ImageFilterEngineLayer pushImageFilter(ImageFilter filter, {Offset offset = Offset.zero, ImageFilterEngineLayer? oldLayer})`
  public func pushImageFilter(_ filter: any ImageFilter, offset: Offset = Offset.zero, oldLayer: ImageFilterEngineLayer? = nil) -> ImageFilterEngineLayer {
    assert(_debugCheckCanBeUsedAsOldLayer(oldLayer, "pushImageFilter"))
    let nativeFilter = filter.toNativeImageFilter()
    let engineLayerBridge = bridge.PushImageFilter(nativeFilter.bridge, offset.dx, offset.dy, oldLayer?.nativeEngineLayerBridge)!
    let engineLayer = NativeEngineLayer(bridge: engineLayerBridge)
    let layer = ImageFilterEngineLayer(engineLayer)
    assert(_debugPushLayer(layer))
    return layer
  }

  /// Pushes a backdrop filter operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:870-889`
  /// **Original:** `BackdropFilterEngineLayer pushBackdropFilter(ImageFilter filter, {BlendMode blendMode = BlendMode.srcOver, int? backdropId, BackdropFilterEngineLayer? oldLayer})`
  public func pushBackdropFilter(_ filter: any ImageFilter, blendMode: BlendMode = .srcOver, oldLayer: BackdropFilterEngineLayer? = nil, backdropId: Int? = nil) -> BackdropFilterEngineLayer {
    assert(_debugCheckCanBeUsedAsOldLayer(oldLayer, "pushBackdropFilter"))
    let nativeFilter = filter.toNativeImageFilter()
    let engineLayerBridge = bridge.PushBackdropFilter(
      nativeFilter.bridge,
      Int32(blendMode.rawValue),
      Int64(backdropId ?? 0),
      backdropId != nil,
      oldLayer?.nativeEngineLayerBridge
    )!
    let engineLayer = NativeEngineLayer(bridge: engineLayerBridge)
    let layer = BackdropFilterEngineLayer(engineLayer)
    assert(_debugPushLayer(layer))
    return layer
  }

  /// Pushes a shader mask operation onto the operation stack.
  ///
  /// **Dart Source:** `compositing.dart:902-926`
  /// **Original:** `ShaderMaskEngineLayer pushShaderMask(Shader shader, Rect maskRect, BlendMode blendMode, {ShaderMaskEngineLayer? oldLayer, FilterQuality filterQuality = FilterQuality.low})`
  public func pushShaderMask(_ shader: Shader, maskRect: Rect, blendMode: BlendMode, oldLayer: ShaderMaskEngineLayer? = nil, filterQuality: FilterQuality = .low) -> ShaderMaskEngineLayer {
    assert(_debugCheckCanBeUsedAsOldLayer(oldLayer, "pushShaderMask"))
    let shaderPtr = NativeSceneBuilder.getShaderPtr(shader)
    let engineLayerBridge = bridge.PushShaderMask(
      shaderPtr,
      maskRect.left, maskRect.top, maskRect.right, maskRect.bottom,
      Int32(blendMode.rawValue),
      Int32(filterQuality.rawValue),
      oldLayer?.nativeEngineLayerBridge
    )!
    let engineLayer = NativeEngineLayer(bridge: engineLayerBridge)
    let layer = ShaderMaskEngineLayer(engineLayer)
    assert(_debugPushLayer(layer))
    return layer
  }

  // MARK: - Pop

  /// Ends the effect of the most recently pushed operation.
  ///
  /// **Dart Source:** `compositing.dart:954-960`
  /// **Original:**
  /// ```dart
  /// void pop() {
  ///   if (_layerStack.isNotEmpty) {
  ///     _layerStack.removeLast();
  ///   }
  ///   _pop();
  /// }
  /// ```
  public func pop() {
    if !_layerStack.isEmpty {
      _layerStack.removeLast()
    }
    bridge.Pop()
  }

  // MARK: - Add Methods

  /// Add a retained engine layer subtree from previous frames.
  ///
  /// **Dart Source:** `compositing.dart:965-991`
  /// **Original:** `void addRetained(EngineLayer retainedLayer)`
  ///
  /// All the engine layers that are in the subtree of the retained layer will
  /// be automatically appended to the current engine layer tree.
  public func addRetained(_ retainedLayer: EngineLayer) {
    assert(retainedLayer is EngineLayerWrapper)
    assert({
      let layer = retainedLayer as! EngineLayerWrapper
      assert(layer._nativeLayer != nil)

      func recursivelyCheckChildrenUsedOnce(_ parentLayer: EngineLayerWrapper) {
        _ = _debugCheckUsedOnce(parentLayer, "retained layer")
        _ = parentLayer._debugCheckNotUsedAsOldLayer()

        guard let children = parentLayer._debugChildren, !children.isEmpty else {
          return
        }
        children.forEach(recursivelyCheckChildrenUsedOnce)
      }

      recursivelyCheckChildrenUsedOnce(layer)
      return true
    }())

    let wrapper = retainedLayer as! EngineLayerWrapper
    let nativeLayer = wrapper._nativeLayer as! NativeEngineLayer
    bridge.AddRetained(nativeLayer.bridge)
  }

  /// Adds an object to the scene that displays performance statistics.
  ///
  /// **Dart Source:** `compositing.dart:996-999`
  /// **Original:** `void addPerformanceOverlay(int enabledOptions, Rect bounds)`
  public func addPerformanceOverlay(_ enabledOptions: Int, bounds: Rect) {
    bridge.AddPerformanceOverlay(
      UInt64(enabledOptions),
      bounds.left, bounds.top, bounds.right, bounds.bottom
    )
  }

  /// Adds a Picture to the scene.
  ///
  /// **Dart Source:** `compositing.dart:1013-1023`
  /// **Original:** `void addPicture(Offset offset, Picture picture, {bool isComplexHint = false, bool willChangeHint = false})`
  ///
  /// The picture is rasterized at the given offset.
  public func addPicture(_ offset: Offset, picture: any Picture, isComplexHint: Bool = false, willChangeHint: Bool = false) {
    assert(!picture.debugDisposed)
    let hints = (isComplexHint ? 1 : 0) | (willChangeHint ? 2 : 0)
    let nativePicture = picture as! NativePicture
    bridge.AddPicture(offset.dx, offset.dy, nativePicture.bridge, Int32(hints))
  }

  /// Adds a backend texture to the scene.
  ///
  /// **Dart Source:** `compositing.dart:1030-1040`
  /// **Original:** `void addTexture(int textureId, {Offset offset = Offset.zero, double width = 0.0, double height = 0.0, bool freeze = false, FilterQuality filterQuality = FilterQuality.low})`
  ///
  /// The texture is scaled to the given size and rasterized at the given offset.
  public func addTexture(_ textureId: Int, offset: Offset = Offset.zero, width: Double = 0.0, height: Double = 0.0, freeze: Bool = false, filterQuality: FilterQuality = .low) {
    addedTextureIds.insert(Int64(textureId))
    bridge.AddTexture(
      offset.dx, offset.dy, width, height,
      Int64(textureId), freeze, Int32(filterQuality.rawValue)
    )
  }

  /// Adds a platform view (e.g an iOS UIView) to the scene.
  ///
  /// **Dart Source:** `compositing.dart:1056-1064`
  /// **Original:** `void addPlatformView(int viewId, {Offset offset = Offset.zero, double width = 0.0, double height = 0.0})`
  public func addPlatformView(_ viewId: Int, offset: Offset = Offset.zero, width: Double = 0.0, height: Double = 0.0) {
    bridge.AddPlatformView(offset.dx, offset.dy, width, height, Int64(viewId))
  }

  // MARK: - Build

  /// Finishes building the scene.
  ///
  /// **Dart Source:** `compositing.dart:1072-1077`
  /// **Original:**
  /// ```dart
  /// Scene build() {
  ///   final Scene scene = _NativeScene._();
  ///   _build(scene);
  ///   return scene;
  /// }
  /// ```
  ///
  /// Returns a Scene containing the objects that have been added to
  /// this scene builder. After calling this function, the scene builder
  /// object is invalid and cannot be used further.
  public func build() -> Scene {
    let sceneBridge = bridge.Build()!
    return NativeScene(sceneBridge)
  }

  /// Returns a string representation of this scene builder.
  ///
  /// **Dart Source:** `compositing.dart:1082-1083`
  /// **Original:** `String toString() => 'SceneBuilder';`
  public var description: String {
    "SceneBuilder"
  }

  // MARK: - Private Helpers

  /// Extracts the opaque shader pointer from a Shader instance.
  ///
  /// Used by pushShaderMask to pass the shader to the C++ bridge.
  /// Matches the pattern used in Paint.shaderBridgePtr.
  private static func getShaderPtr(_ shader: Shader) -> UnsafeRawPointer? {
    if let gradient = shader as? Gradient {
      return UnsafeRawPointer(gradient.gradientBridge.GetShaderPtr())
    } else if let imageShader = shader as? ImageShader {
      return UnsafeRawPointer(imageShader.imageShaderBridge.GetShaderPtr())
    } else if let fragmentShader = shader as? FragmentShader {
      return UnsafeRawPointer(fragmentShader.fragmentShaderBridge.GetShaderPtr())
    }
    return nil
  }
}

/// Helper computed property on EngineLayerWrapper to extract the underlying
/// NativeEngineLayer's C++ bridge pointer for passing to SceneBuilderBridge methods.
///
/// **Dart Source:** `compositing.dart` - various push* methods pass `oldLayer?._nativeLayer`
///
/// DIFFERENCE FROM DART: Dart passes EngineLayer directly to @Native methods.
/// Swift needs to extract the C++ bridge object from the NativeEngineLayer wrapper.
/// REASON: Swift calls C++ bridge methods that take EngineLayerBridge* pointers,
/// not Swift protocol instances.
internal extension EngineLayerWrapper {
  var nativeEngineLayerBridge: flutter.swift_bridge.EngineLayerBridge? {
    guard let nativeLayer = _nativeLayer as? NativeEngineLayer else {
      return nil
    }
    return nativeLayer.bridge
  }
}

/// Validates that a 4x4 matrix (as [Double] with 16 entries) contains only finite values.
///
/// **Dart Source:** `painting.dart` - `_matrix4IsValid`
/// Returns true if validation passes (always true; asserts in debug).
private func matrix4IsValid(_ matrix4: [Double]) -> Bool {
  assert(matrix4.count == 16, "Matrix4 must have 16 entries.")
  assert(matrix4.allSatisfy { $0.isFinite }, "Matrix4 entries must be finite.")
  return true
}

/// Helper extension for left-padding strings.
///
/// Used by `_debugCheckNotUsedAsOldLayer` to format hash codes.
private extension String {
  func paddingLeft(toLength length: Int, withPad pad: String) -> String {
    let deficit = length - self.count
    if deficit <= 0 { return self }
    return String(repeating: pad, count: deficit) + self
  }
}

// MARK: - SceneBuilders Factory

/// Factory namespace for creating SceneBuilder instances.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart`
/// **Original:** `factory SceneBuilder() = _NativeSceneBuilder;`
/// **Lines:** 262
///
/// In Dart, `SceneBuilder` has a factory constructor that returns a
/// `_NativeSceneBuilder`. In Swift, protocols cannot have factory
/// initializers, so this enum serves as the factory namespace.
///
/// DIFFERENCE FROM DART: Uses an enum factory namespace instead of factory constructor.
/// REASON: Swift protocols cannot have factory constructors. This pattern provides
/// equivalent ergonomics while maintaining type safety.
public enum SceneBuilders {
  /// Creates a new `SceneBuilder`.
  ///
  /// **Dart Source:** `compositing.dart:262`
  /// **Original:** `factory SceneBuilder() = _NativeSceneBuilder;`
  ///
  /// Equivalent to Dart's `SceneBuilder()` factory constructor.
  ///
  /// ## Usage
  ///
  /// ```swift
  /// // Dart: let builder = SceneBuilder();
  /// // Swift: let builder = SceneBuilders.create()
  /// let builder = SceneBuilders.create()
  /// builder.pushOffset(10.0, 20.0, oldLayer: nil)
  /// // ... add more layers ...
  /// let scene = builder.build()
  /// ```
  public static func create() -> any SceneBuilder {
    return NativeSceneBuilder()
  }
}
