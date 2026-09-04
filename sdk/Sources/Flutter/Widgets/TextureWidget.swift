// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import FlutterSwiftBridge

// MARK: - Texture

/// A rectangle upon which a backend texture is mapped.
///
/// Backend textures are images that can be applied (mapped) to an area of the
/// Flutter view. They are created, managed, and updated using a
/// platform-specific texture registry. This is typically done by a plugin
/// that integrates with host platform video player, camera, or OpenGL APIs,
/// or similar image sources.
///
/// A texture widget refers to its backend texture using an integer ID. Texture
/// IDs are obtained from the texture registry and are scoped to the Flutter
/// view. Texture IDs may be reused after deregistration, at the discretion
/// of the registry. The use of texture IDs currently unknown to the registry
/// will silently result in a blank rectangle.
///
/// Texture widgets are repainted autonomously as dictated by the backend (e.g.
/// on arrival of a video frame). Such repainting generally does not involve
/// executing Dart code.
///
/// The size of the rectangle is determined by its parent widget, and the
/// texture is automatically scaled to fit.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/texture.dart:35-71`
public class TextureWidget: LeafRenderObjectWidget {

    /// Creates a widget backed by the texture identified by `textureId`, and uses
    /// `filterQuality` to set the texture's `FilterQuality`.
    ///
    /// **Dart Source:** `texture.dart:38-43`
    public init(
        key: (any Key)? = nil,
        textureId: Int,
        freeze: Bool = false,
        filterQuality: FilterQuality = .low,
        sourceRect: Rect? = nil,
        crop: Rect? = nil
    ) {
        self.textureId = textureId
        self.freeze = freeze
        self.filterQuality = filterQuality
        self.sourceRect = sourceRect
        self.crop = crop
        super.init(key: key)
    }

    /// The identity of the backend texture.
    ///
    /// **Dart Source:** `texture.dart:46`
    public let textureId: Int

    /// When true the texture will not be updated with new frames.
    ///
    /// **Dart Source:** `texture.dart:49`
    public let freeze: Bool

    /// The quality of sampling the texture and rendering it on screen.
    ///
    /// When the texture is scaled, a default `FilterQuality.low` is used for a
    /// higher quality but slower interpolation (typically bilinear). It can be
    /// changed to `FilterQuality.none` for a lower quality but faster
    /// interpolation (typically nearest-neighbor).
    ///
    /// **Dart Source:** `texture.dart:59`
    public let filterQuality: FilterQuality

    /// Optional source rect for UV crop (physical pixels).
    public let sourceRect: Rect?

    /// The part of the texture to show, in unit texture coordinates, scaled
    /// to fill the widget. See `TextureBox.crop`.
    public let crop: Rect?

    /// **Dart Source:** `texture.dart:62-63`
    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return TextureBox(textureId: textureId, freeze: freeze, filterQuality: filterQuality,
                          sourceRect: sourceRect, crop: crop)
    }

    /// **Dart Source:** `texture.dart:66-70`
    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        guard let textureBox = renderObject as? TextureBox else { return }
        textureBox.textureId = textureId
        textureBox.freeze = freeze
        textureBox.filterQuality = filterQuality
        textureBox.sourceRect = sourceRect
        textureBox.crop = crop
    }
}
