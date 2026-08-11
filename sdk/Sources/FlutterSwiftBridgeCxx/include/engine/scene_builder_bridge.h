// Copyright the Starling authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SWIFT_SCENE_BUILDER_BRIDGE_H_
#define FLUTTER_SWIFT_SCENE_BUILDER_BRIDGE_H_

#include "swift_bridge_export.h"

#include <swift/bridging>
#include "intrusive_reference_counted.h"

namespace flutter::swift_bridge {

// Forward declaration for retain/release functions
class SceneBuilderBridge;

}  // namespace flutter::swift_bridge

// Free functions for SWIFT_SHARED_REFERENCE - must be at global scope
void RetainSceneBuilderBridge(
    flutter::swift_bridge::SceneBuilderBridge* p) noexcept;
void ReleaseSceneBuilderBridge(
    flutter::swift_bridge::SceneBuilderBridge* p) noexcept;

namespace flutter::swift_bridge {

// Forward declarations for pimpl and bridge types
struct SceneBuilderImpl;
class EngineLayerBridge;
class SceneBridge;
class ColorFilterBridge;
class ImageFilterBridge;
class PathBridge;
class PictureBridge;

/// C++ bridge wrapping Flutter's SceneBuilder class.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/compositing.dart:593-1084`
/// **Original Name:** `_NativeSceneBuilder`
///
/// This bridge wraps flutter::SceneBuilder which manages a layer tree for
/// compositing. It provides push/pop/add methods that build up the layer tree,
/// and a Build() method that produces a SceneBridge from the accumulated layers.
///
/// Architecture:
/// - Swift NativeSceneBuilder class wraps SceneBuilderBridge
/// - SceneBuilderBridge holds fml::RefPtr<flutter::SceneBuilder> via pimpl
/// - Swift ARC handles lifetime via SWIFT_SHARED_REFERENCE
/// - Build() produces a SceneBridge wrapping the root layer
///
/// Each Push* method returns an EngineLayerBridge* wrapping the new
/// ContainerLayer. The caller (Swift) owns the returned bridge object.
class FLUTTER_SWIFT_BRIDGE_EXPORT
    SWIFT_SHARED_REFERENCE(RetainSceneBuilderBridge, ReleaseSceneBuilderBridge)
        SceneBuilderBridge
    : public IntrusiveReferenceCounted<SceneBuilderBridge> {
 public:
  /// Creates a new SceneBuilderBridge.
  ///
  /// **Dart Source:** `compositing.dart:594-600`
  /// **Original:** `_NativeSceneBuilder()` constructor calling
  ///   `@Native SceneBuilder::Create`
  ///
  /// Initializes an empty scene builder with a root ContainerLayer.
  SceneBuilderBridge();

  /// Pushes a 4x4 transform matrix onto the layer stack.
  ///
  /// **Dart Source:** `compositing.dart:656-670`
  /// **Original:** `pushTransform` / `_pushTransform`
  ///
  /// @param matrix4 Pointer to 16 doubles (column-major 4x4 matrix)
  /// @param old_layer Optional previously-retained layer for diffing
  /// @return New EngineLayerBridge wrapping the TransformLayer
  EngineLayerBridge* PushTransform(const double* matrix4,
                                   EngineLayerBridge* old_layer) SWIFT_RETURNS_RETAINED;

  /// Pushes a translation offset onto the layer stack.
  ///
  /// **Dart Source:** `compositing.dart:672-685`
  /// **Original:** `pushOffset` / `_pushOffset`
  EngineLayerBridge* PushOffset(double dx,
                                double dy,
                                EngineLayerBridge* old_layer) SWIFT_RETURNS_RETAINED;

  /// Pushes a rectangular clip onto the layer stack.
  ///
  /// **Dart Source:** `compositing.dart:687-721`
  /// **Original:** `pushClipRect` / `_pushClipRect`
  ///
  /// @param clip_behavior Clip enum index (1=hardEdge, 2=antiAlias,
  ///   3=antiAliasWithSaveLayer)
  EngineLayerBridge* PushClipRect(double left,
                                  double top,
                                  double right,
                                  double bottom,
                                  int clip_behavior,
                                  EngineLayerBridge* old_layer) SWIFT_RETURNS_RETAINED;

  /// Pushes a rounded rectangle clip onto the layer stack.
  ///
  /// **Dart Source:** `compositing.dart:723-746`
  /// **Original:** `pushClipRRect` / `_pushClipRRect`
  ///
  /// @param rrect_values Pointer to 12 floats: [left, top, right, bottom,
  ///   tlRadiusX, tlRadiusY, trRadiusX, trRadiusY,
  ///   brRadiusX, brRadiusY, blRadiusX, blRadiusY]
  /// @param clip_behavior Clip enum index
  EngineLayerBridge* PushClipRRect(const float* rrect_values,
                                   int clip_behavior,
                                   EngineLayerBridge* old_layer) SWIFT_RETURNS_RETAINED;

  /// Pushes a rounded superellipse clip onto the layer stack.
  ///
  /// **Dart Source:** `compositing.dart:748-776`
  /// **Original:** `pushClipRSuperellipse` / `_pushClipRSuperellipse`
  ///
  /// @param left, top, right, bottom Bounds of the superellipse
  /// @param tl_radius_x through bl_radius_y Corner radii (8 values)
  /// @param clip_behavior Clip enum index
  EngineLayerBridge* PushClipRSuperellipse(double left,
                                           double top,
                                           double right,
                                           double bottom,
                                           double tl_radius_x,
                                           double tl_radius_y,
                                           double tr_radius_x,
                                           double tr_radius_y,
                                           double br_radius_x,
                                           double br_radius_y,
                                           double bl_radius_x,
                                           double bl_radius_y,
                                           int clip_behavior,
                                           EngineLayerBridge* old_layer) SWIFT_RETURNS_RETAINED;

  /// Pushes a path clip onto the layer stack.
  ///
  /// **Dart Source:** `compositing.dart:778-801`
  /// **Original:** `pushClipPath` / `_pushClipPath`
  ///
  /// @param path PathBridge containing the clip path
  /// @param clip_behavior Clip enum index
  EngineLayerBridge* PushClipPath(PathBridge* path,
                                  int clip_behavior,
                                  EngineLayerBridge* old_layer) SWIFT_RETURNS_RETAINED;

  /// Pushes an opacity layer onto the layer stack.
  ///
  /// **Dart Source:** `compositing.dart:803-826`
  /// **Original:** `pushOpacity` / `_pushOpacity`
  ///
  /// @param alpha Opacity value 0-255
  /// @param dx, dy Offset for the opacity layer
  EngineLayerBridge* PushOpacity(int alpha,
                                 double dx,
                                 double dy,
                                 EngineLayerBridge* old_layer) SWIFT_RETURNS_RETAINED;

  /// Pushes a color filter layer onto the layer stack.
  ///
  /// **Dart Source:** `compositing.dart:828-842`
  /// **Original:** `pushColorFilter` / `_pushColorFilter`
  ///
  /// @param color_filter ColorFilterBridge containing the filter
  EngineLayerBridge* PushColorFilter(ColorFilterBridge* color_filter,
                                     EngineLayerBridge* old_layer) SWIFT_RETURNS_RETAINED;

  /// Pushes an image filter layer onto the layer stack.
  ///
  /// **Dart Source:** `compositing.dart:844-868`
  /// **Original:** `pushImageFilter` / `_pushImageFilter`
  ///
  /// @param image_filter ImageFilterBridge containing the filter
  /// @param dx, dy Offset for the image filter layer
  EngineLayerBridge* PushImageFilter(ImageFilterBridge* image_filter,
                                     double dx,
                                     double dy,
                                     EngineLayerBridge* old_layer) SWIFT_RETURNS_RETAINED;

  /// Pushes a backdrop filter layer onto the layer stack.
  ///
  /// **Dart Source:** `compositing.dart:870-900`
  /// **Original:** `pushBackdropFilter` / `_pushBackdropFilter`
  ///
  /// @param filter ImageFilterBridge containing the backdrop filter
  /// @param blend_mode BlendMode enum index
  /// @param backdrop_id Optional backdrop identifier (-1 for no id)
  EngineLayerBridge* PushBackdropFilter(ImageFilterBridge* filter,
                                        int blend_mode,
                                        int64_t backdrop_id,
                                        bool has_backdrop_id,
                                        EngineLayerBridge* old_layer) SWIFT_RETURNS_RETAINED;

  /// Pushes a shader mask layer onto the layer stack.
  ///
  /// **Dart Source:** `compositing.dart:902-952`
  /// **Original:** `pushShaderMask` / `_pushShaderMask`
  ///
  /// @param shader_ptr Opaque pointer to std::shared_ptr<DlColorSource>
  ///   (obtained from a shader bridge's GetShaderPtr())
  /// @param mask_rect_left/top/right/bottom Mask rectangle bounds
  /// @param blend_mode BlendMode enum index
  /// @param filter_quality_index FilterQuality enum index
  EngineLayerBridge* PushShaderMask(const void* shader_ptr,
                                    double mask_rect_left,
                                    double mask_rect_top,
                                    double mask_rect_right,
                                    double mask_rect_bottom,
                                    int blend_mode,
                                    int filter_quality_index,
                                    EngineLayerBridge* old_layer) SWIFT_RETURNS_RETAINED;

  /// Pops the current layer from the stack.
  ///
  /// **Dart Source:** `compositing.dart:954-963`
  /// **Original:** `pop()` / `_pop()`
  void Pop();

  /// Adds a pre-built retained layer subtree.
  ///
  /// **Dart Source:** `compositing.dart:965-994`
  /// **Original:** `addRetained` / `_addRetained`
  ///
  /// @param retained_layer EngineLayerBridge to add as a retained subtree
  void AddRetained(EngineLayerBridge* retained_layer);

  /// Adds a performance overlay layer.
  ///
  /// **Dart Source:** `compositing.dart:996-1011`
  /// **Original:** `addPerformanceOverlay` / `_addPerformanceOverlay`
  ///
  /// @param enabled_options Bitmask of enabled performance overlay options
  /// @param left/top/right/bottom Bounds for the overlay
  void AddPerformanceOverlay(uint64_t enabled_options,
                             double left,
                             double top,
                             double right,
                             double bottom);

  /// Adds a picture (display list) at the given offset.
  ///
  /// **Dart Source:** `compositing.dart:1013-1028`
  /// **Original:** `addPicture` / `_addPicture`
  ///
  /// @param dx, dy Offset position
  /// @param picture PictureBridge containing the display list
  /// @param hints Bitfield: bit 0 = isComplexHint, bit 1 = willChangeHint
  void AddPicture(double dx,
                  double dy,
                  PictureBridge* picture,
                  int hints);

  /// Adds an external texture layer.
  ///
  /// **Dart Source:** `compositing.dart:1030-1054`
  /// **Original:** `addTexture` / `_addTexture`
  ///
  /// @param dx, dy Offset position
  /// @param width, height Size of the texture
  /// @param texture_id Platform texture identifier
  /// @param freeze Whether to freeze the texture
  /// @param filter_quality_index FilterQuality enum index
  void AddTexture(double dx,
                  double dy,
                  double width,
                  double height,
                  int64_t texture_id,
                  bool freeze,
                  int filter_quality_index);

  /// Adds a platform view layer.
  ///
  /// **Dart Source:** `compositing.dart:1056-1070`
  /// **Original:** `addPlatformView` / `_addPlatformView`
  ///
  /// @param dx, dy Offset position
  /// @param width, height Size of the platform view
  /// @param view_id Platform view identifier
  void AddPlatformView(double dx,
                       double dy,
                       double width,
                       double height,
                       int64_t view_id);

  /// Builds the scene from the accumulated layer tree.
  ///
  /// **Dart Source:** `compositing.dart:1072-1080`
  /// **Original:** `build()` / `_build()`
  ///
  /// Creates a SceneBridge wrapping the root layer. After calling Build(),
  /// this SceneBuilderBridge should not be used further.
  ///
  /// @return New SceneBridge wrapping the composed scene
  SceneBridge* Build() SWIFT_RETURNS_RETAINED;

  ~SceneBuilderBridge();

 private:
  SceneBuilderBridge(const SceneBuilderBridge&) = delete;
  SceneBuilderBridge& operator=(const SceneBuilderBridge&) = delete;

  // Pimpl - holds the actual Flutter SceneBuilder
  SceneBuilderImpl* impl_;
};

}  // namespace flutter::swift_bridge

// Inline definitions for global retain/release functions
inline void RetainSceneBuilderBridge(
    flutter::swift_bridge::SceneBuilderBridge* p) noexcept {
  p->Retain();
}
inline void ReleaseSceneBuilderBridge(
    flutter::swift_bridge::SceneBuilderBridge* p) noexcept {
  p->Release();
}

#endif  // FLUTTER_SWIFT_SCENE_BUILDER_BRIDGE_H_
