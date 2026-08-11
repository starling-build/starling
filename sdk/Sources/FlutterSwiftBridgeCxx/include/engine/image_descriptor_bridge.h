// Copyright the Starling authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SWIFT_IMAGE_DESCRIPTOR_BRIDGE_H_
#define FLUTTER_SWIFT_IMAGE_DESCRIPTOR_BRIDGE_H_

#include "swift_bridge_export.h"

#include <swift/bridging>
#include "intrusive_reference_counted.h"
#include "immutable_buffer_bridge.h"
#include "codec_bridge.h"

namespace flutter::swift_bridge {

// Forward declaration for retain/release functions
class ImageDescriptorBridge;

}  // namespace flutter::swift_bridge

// Free functions for SWIFT_SHARED_REFERENCE - must be at global scope
void RetainImageDescriptorBridge(
    flutter::swift_bridge::ImageDescriptorBridge* p) noexcept;
void ReleaseImageDescriptorBridge(
    flutter::swift_bridge::ImageDescriptorBridge* p) noexcept;

namespace flutter::swift_bridge {

// Forward declarations for pimpl
struct ImageDescriptorBridgeImpl;

/// C++ bridge wrapping Flutter's ImageDescriptor.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:7868-7971`
/// **Original:** `_NativeImageDescriptor` class (native wrapper implementing
/// ImageDescriptor)
///
/// This bridge corresponds to the Dart `_NativeImageDescriptor` class, which
/// is the concrete native implementation of the abstract `ImageDescriptor`
/// class. It wraps the underlying C++ ImageDescriptor (SkImageInfo + SkData +
/// optional ImageGenerator) and provides access to image metadata and codec
/// instantiation.
///
/// Architecture:
/// - Swift NativeImageDescriptor wraps ImageDescriptorBridge
/// - ImageDescriptorBridge wraps SkImageInfo + sk_sp<SkData> + optional
///   shared_ptr<ImageGenerator>
/// - Swift ARC handles lifetime via SWIFT_SHARED_REFERENCE
///
/// DIFFERENCE FROM DART: The Dart `initEncoded` uses `UIDartState` to access
/// `ImageGeneratorRegistry`. This bridge provides `InitEncoded` which takes
/// the buffer data and creates a compatible generator directly using the
/// default built-in Skia decoders.
/// REASON: Swift doesn't use Dart VM; UIDartState is not available.
class FLUTTER_SWIFT_BRIDGE_EXPORT
    SWIFT_SHARED_REFERENCE(RetainImageDescriptorBridge,
                           ReleaseImageDescriptorBridge)
        ImageDescriptorBridge
    : public IntrusiveReferenceCounted<ImageDescriptorBridge> {
 public:
  /// Creates an ImageDescriptorBridge from raw pixel data.
  ///
  /// **Dart Source:** `painting.dart:7871-7893`
  /// **Original:** `_NativeImageDescriptor.raw(ImmutableBuffer buffer, ...)`
  ///
  /// @param buffer The ImmutableBufferBridge containing pixel data
  /// @param width Image width in pixels
  /// @param height Image height in pixels
  /// @param row_bytes Bytes per row (-1 to use default)
  /// @param pixel_format PixelFormat index (0=RGBA8888, 1=BGRA8888,
  ///        2=RGBAFloat32)
  ImageDescriptorBridge(ImmutableBufferBridge* buffer,
                        int width,
                        int height,
                        int row_bytes,
                        int pixel_format);

  /// Creates an ImageDescriptorBridge from encoded image data.
  ///
  /// **Dart Source:** `painting.dart:7895-7896`
  /// **Original:** `_initEncoded(ImmutableBuffer buffer, _Callback<void>
  /// callback)`
  ///
  /// DIFFERENCE FROM DART: Synchronous. The Dart version uses async callback
  /// via Dart_Handle. Use IsValid() to check if initialization succeeded.
  /// REASON: Swift doesn't use Dart VM callbacks.
  ///
  /// @param buffer The ImmutableBufferBridge containing encoded image data
  ImageDescriptorBridge(ImmutableBufferBridge* buffer);

  /// Whether this descriptor was successfully initialized.
  /// Returns false if created from encoded data that could not be decoded.
  bool IsValid() const;

  /// The width of this image, in pixels.
  ///
  /// **Dart Source:** `painting.dart:7912-7916`
  /// **Original:** `@Native int _getWidth()` / `int get width`
  int GetWidth() const;

  /// The height of this image, in pixels.
  ///
  /// **Dart Source:** `painting.dart:7920-7924`
  /// **Original:** `@Native int _getHeight()` / `int get height`
  int GetHeight() const;

  /// The number of bytes per pixel.
  ///
  /// **Dart Source:** `painting.dart:7928-7932`
  /// **Original:** `@Native int _getBytesPerPixel()` / `int get bytesPerPixel`
  int GetBytesPerPixel() const;

  /// Creates a CodecBridge for decoding this image descriptor.
  ///
  /// **Dart Source:** `painting.dart:7938-7966`
  /// **Original:** `Future<Codec> instantiateCodec(...)` /
  ///              `@Native void _instantiateCodec(Codec outCodec, int, int)`
  ///
  /// @param target_width Target width for resizing (use 0 for original)
  /// @param target_height Target height for resizing (use 0 for original)
  /// @return A new CodecBridge, or nullptr on failure
  CodecBridge* InstantiateCodec(int target_width, int target_height) const SWIFT_RETURNS_RETAINED;

  /// Release the resources used by this descriptor.
  ///
  /// **Dart Source:** `painting.dart:7934-7936`
  /// **Original:** `@Native<Void Function(Pointer<Void>)>(symbol:
  /// 'ImageDescriptor::dispose')`
  void Dispose();

  /// Returns a string description.
  ///
  /// **Dart Source:** `painting.dart:7968-7970`
  /// **Original:** `String toString() => 'ImageDescriptor(...)'`
  void ToString(char* buffer, int buffer_size) const;

  ~ImageDescriptorBridge();

 private:
  ImageDescriptorBridge(const ImageDescriptorBridge&) = delete;
  ImageDescriptorBridge& operator=(const ImageDescriptorBridge&) = delete;

  // Pimpl - holds the actual Flutter types
  ImageDescriptorBridgeImpl* impl_;
};

}  // namespace flutter::swift_bridge

// Inline definitions for global retain/release functions
inline void RetainImageDescriptorBridge(
    flutter::swift_bridge::ImageDescriptorBridge* p) noexcept {
  p->Retain();
}
inline void ReleaseImageDescriptorBridge(
    flutter::swift_bridge::ImageDescriptorBridge* p) noexcept {
  p->Release();
}

#endif  // FLUTTER_SWIFT_IMAGE_DESCRIPTOR_BRIDGE_H_
