// Copyright the Starling authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SWIFT_CODEC_BRIDGE_H_
#define FLUTTER_SWIFT_CODEC_BRIDGE_H_

#include "swift_bridge_export.h"

#include <swift/bridging>
#include "intrusive_reference_counted.h"
#include "image_bridge.h"

namespace flutter::swift_bridge {

// Forward declaration for retain/release functions
class CodecBridge;

}  // namespace flutter::swift_bridge

// Free functions for SWIFT_SHARED_REFERENCE - must be at global scope
void RetainCodecBridge(flutter::swift_bridge::CodecBridge* p) noexcept;
void ReleaseCodecBridge(flutter::swift_bridge::CodecBridge* p) noexcept;

namespace flutter::swift_bridge {

// Forward declarations for pimpl
struct CodecBridgeImpl;

/// C++ bridge wrapping Flutter's Codec (SingleFrameCodec / MultiFrameCodec).
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:2342-2405`
/// **Original:** `_NativeCodec` class (native wrapper implementing Codec)
///
/// This bridge corresponds to the Dart `_NativeCodec` class, which is the
/// concrete native implementation of the abstract `Codec` class. It wraps
/// the underlying C++ Codec (either SingleFrameCodec or MultiFrameCodec)
/// and provides synchronous access to frame data.
///
/// Architecture:
/// - Swift NativeCodec class wraps CodecBridge (like Dart _NativeCodec wraps C++ Codec)
/// - CodecBridge wraps the underlying ImageGenerator for frame access
/// - Swift ARC handles lifetime via SWIFT_SHARED_REFERENCE
///
/// DIFFERENCE FROM DART: The Dart implementation uses async callbacks via
/// Dart_Handle and task runners for getNextFrame(). This bridge provides
/// synchronous frame decoding because the async path requires UIDartState
/// for task runner access, which is Dart VM specific.
/// REASON: Swift doesn't use Dart VM; a future engine integration layer
/// will provide proper async decoding with GPU upload support.
class FLUTTER_SWIFT_BRIDGE_EXPORT
    SWIFT_SHARED_REFERENCE(RetainCodecBridge, ReleaseCodecBridge)
        CodecBridge
    : public IntrusiveReferenceCounted<CodecBridge> {
 public:
  /// Creates a CodecBridge from an ImageGenerator.
  ///
  /// This is called by ImageDescriptorBridge::InstantiateCodec (future) or
  /// directly when creating codecs from image data.
  ///
  /// The bridge takes ownership of the generator via shared_ptr.
  /// The `generator_ptr` is a pointer to a heap-allocated
  /// `shared_ptr<ImageGenerator>` which will be consumed (moved and deleted).
  CodecBridge(void* generator_ptr);

  /// Returns the number of frames in this image.
  ///
  /// **Dart Source:** `painting.dart:2353-2357`
  /// **Original:** `int get frameCount` / `@Native int get _frameCount`
  int GetFrameCount() const;

  /// Returns the number of times to repeat the animation.
  /// * 0 when the animation should be played once.
  /// * -1 for infinity repetitions.
  ///
  /// **Dart Source:** `painting.dart:2361-2365`
  /// **Original:** `int get repetitionCount` / `@Native int get _repetitionCount`
  int GetRepetitionCount() const;

  /// Decodes the next frame synchronously.
  ///
  /// **Dart Source:** `painting.dart:2367-2397`
  /// **Original:** `Future<FrameInfo> getNextFrame()` / `@Native _getNextFrame(callback)`
  ///
  /// DIFFERENCE FROM DART: Synchronous instead of async. Returns true/false
  /// for success/failure. On success, the decoded frame is available via
  /// GetLastFrameImage() and GetLastFrameDurationMs().
  /// REASON: The async path requires UIDartState for task runner access.
  ///
  /// On success: returns true. Call GetLastFrameImage()/GetLastFrameDurationMs().
  /// On failure: returns false. Call GetLastError() for error message.
  bool DecodeNextFrame();

  /// Returns the ImageBridge for the last successfully decoded frame.
  /// Only valid after DecodeNextFrame() returns true.
  /// The returned ImageBridge is owned by this CodecBridge and remains
  /// valid until the next call to DecodeNextFrame() or Dispose().
  ImageBridge* GetLastFrameImage() const SWIFT_RETURNS_RETAINED;

  /// Returns the duration in milliseconds of the last decoded frame.
  /// Only valid after DecodeNextFrame() returns true.
  int GetLastFrameDurationMs() const;

  /// Returns the error message from the last failed DecodeNextFrame() call.
  /// Returns empty string if no error.
  void GetLastError(char* buffer, int buffer_size) const;

  /// Release the resources used by this codec.
  ///
  /// **Dart Source:** `painting.dart:2399-2401`
  /// **Original:** `@Native<Void Function(Pointer<Void>)>(symbol: 'Codec::dispose')`
  void Dispose();

  /// Returns a string description (e.g., "Codec(3 frames)").
  ///
  /// **Dart Source:** `painting.dart:2403-2404`
  /// **Original:** `String toString() => 'Codec(${_cachedFrameCount == null ? "" : "$_cachedFrameCount frames"})'`
  void ToString(char* buffer, int buffer_size) const;

  /// Creates a CodecBridge from encoded image data (PNG, JPEG, GIF, etc.).
  ///
  /// Uses Skia's built-in codec to create an ImageGenerator from the data.
  /// The `sk_data_ptr` is a `const void*` pointing to an `sk_sp<SkData>*`.
  ///
  /// Returns a new CodecBridge on success, or nullptr if the data format
  /// is not recognized.
  static CodecBridge* CreateFromEncodedData(const void* sk_data_ptr);

  /// Creates a CodecBridge from raw pixel data.
  ///
  /// The `sk_data_ptr` is a `const void*` pointing to an `sk_sp<SkData>*`.
  /// @param width Image width in pixels
  /// @param height Image height in pixels
  /// @param row_bytes Bytes per row
  /// @param color_type Skia color type (e.g., 4=RGBA_8888, 6=BGRA_8888,
  ///        12=RGBA_F32)
  /// @param alpha_type Skia alpha type (e.g., 2=Premul, 3=Unpremul)
  static CodecBridge* CreateFromRawPixels(const void* sk_data_ptr,
                                          int width,
                                          int height,
                                          int row_bytes,
                                          int color_type,
                                          int alpha_type);

  ~CodecBridge();

 private:
  CodecBridge(const CodecBridge&) = delete;
  CodecBridge& operator=(const CodecBridge&) = delete;

  // Private default constructor for use by factory methods
  CodecBridge() : impl_(nullptr) {}

  // Pimpl - holds the actual Flutter types (ImageGenerator, SkCodec, frame state)
  CodecBridgeImpl* impl_;
};

}  // namespace flutter::swift_bridge

// Inline definitions for global retain/release functions
inline void RetainCodecBridge(
    flutter::swift_bridge::CodecBridge* p) noexcept {
  p->Retain();
}
inline void ReleaseCodecBridge(
    flutter::swift_bridge::CodecBridge* p) noexcept {
  p->Release();
}

#endif  // FLUTTER_SWIFT_CODEC_BRIDGE_H_
