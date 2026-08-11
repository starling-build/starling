// Copyright the Starling authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SWIFT_PICTURE_BRIDGE_H_
#define FLUTTER_SWIFT_PICTURE_BRIDGE_H_

#include "swift_bridge_export.h"

#include <swift/bridging>
#include "intrusive_reference_counted.h"

namespace flutter::swift_bridge {

// Forward declaration for retain/release functions
class PictureBridge;

}  // namespace flutter::swift_bridge

// Free functions for SWIFT_SHARED_REFERENCE - must be at global scope
void RetainPictureBridge(flutter::swift_bridge::PictureBridge* p) noexcept;
void ReleasePictureBridge(flutter::swift_bridge::PictureBridge* p) noexcept;

namespace flutter::swift_bridge {

// Forward declarations for pimpl and bridge types
struct PictureImpl;
class CanvasBridge;
class ImageBridge;

/// C++ bridge wrapping Flutter's _NativePicture class.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:7351-7428`
/// **Original Name:** `_NativePicture`
///
/// This bridge wraps an sk_sp<DisplayList> that was built by a CanvasBridge's
/// DisplayListBuilder. It provides access to the display list for rendering
/// (via Canvas.drawPicture) and for converting to images.
///
/// Architecture:
/// - Swift NativePicture class wraps PictureBridge
/// - PictureBridge holds sk_sp<DisplayList> via pimpl pattern
/// - Swift ARC handles lifetime via SWIFT_SHARED_REFERENCE
/// - Created by NativePictureRecorder.endRecording() which builds the
///   DisplayList from the CanvasBridge's DisplayListBuilder
class FLUTTER_SWIFT_BRIDGE_EXPORT
    SWIFT_SHARED_REFERENCE(RetainPictureBridge, ReleasePictureBridge)
        PictureBridge
    : public IntrusiveReferenceCounted<PictureBridge> {
 public:
  /// Creates a PictureBridge by building a DisplayList from a CanvasBridge.
  ///
  /// **Dart Source:** `painting.dart:7486-7487`
  /// **Original:** `_endRecording(picture)` in _NativePictureRecorder
  ///
  /// Takes the DisplayListBuilder from the canvas, calls Build() on it,
  /// and stores the resulting DisplayList.
  ///
  /// @param canvas_bridge The CanvasBridge whose builder to consume
  PictureBridge(const CanvasBridge* canvas_bridge);

  /// Returns the approximate number of bytes used by this picture.
  ///
  /// **Dart Source:** `painting.dart:7422-7424`
  /// **Original:** `@Native<Uint64 Function(Pointer<Void>)>(symbol: 'Picture::GetAllocationSize')`
  ///
  /// Returns sizeof(PictureBridge) + display_list->bytes() if available,
  /// otherwise just sizeof(PictureBridge).
  int64_t GetAllocationSize() const;

  /// Returns an opaque pointer to the internal sk_sp<DisplayList>.
  ///
  /// Used by CanvasBridge::DrawDisplayList to render this picture.
  /// Returns nullptr if disposed.
  SWIFT_RETURNS_INDEPENDENT_VALUE
  const void* GetDisplayListPtr() const;

  /// Releases the underlying DisplayList.
  ///
  /// **Dart Source:** `painting.dart:7404-7407`
  /// **Original:** `@Native<Void Function(Pointer<Void>)>(symbol: 'Picture::dispose')`
  void Dispose();

  /// Rasterizes this picture to a CPU-backed image of the given dimensions.
  ///
  /// Creates a raster SkSurface, replays the DisplayList onto it, and
  /// wraps the resulting SkImage in an ImageBridge for use from Swift.
  ///
  /// Returns nullptr if the surface cannot be created or the snapshot fails.
  ImageBridge* ToImage(int width, int height) const SWIFT_RETURNS_RETAINED;

  /// Whether Dispose() has been called.
  bool IsDisposed() const;

  ~PictureBridge();

 private:
  PictureBridge(const PictureBridge&) = delete;
  PictureBridge& operator=(const PictureBridge&) = delete;

  // Pimpl - holds the actual Flutter types (sk_sp<DisplayList>)
  PictureImpl* impl_;
};

}  // namespace flutter::swift_bridge

// Inline definitions for global retain/release functions
inline void RetainPictureBridge(
    flutter::swift_bridge::PictureBridge* p) noexcept {
  p->Retain();
}
inline void ReleasePictureBridge(
    flutter::swift_bridge::PictureBridge* p) noexcept {
  p->Release();
}

#endif  // FLUTTER_SWIFT_PICTURE_BRIDGE_H_
