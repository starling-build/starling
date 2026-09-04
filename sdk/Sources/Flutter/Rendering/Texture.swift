// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Texture rendering types.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/texture.dart`

import FlutterSwiftBridge

// MARK: - TextureLayer (Stub)

/// A compositing layer that displays a backend texture.
///
/// Backend textures are images that can be applied (mapped) to an area of the
/// Flutter view. They are created, managed, and updated using a
/// platform-specific texture registry.
///
/// A texture layer refers to its backend texture using an integer ID. Texture
/// IDs are obtained from the texture registry and are scoped to the Flutter
/// view. Texture IDs may be reused after deregistration, at the discretion
/// of the registry. The use of texture IDs currently unknown to the registry
/// will silently result in a blank rectangle.
///
/// Once inserted into the layer tree, texture layers are repainted autonomously
/// as dictated by the backend (e.g. on arrival of a video frame). Such
/// repainting generally does not involve executing Dart code.
///
/// Texture layers are always leaves in the layer tree.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart:952-1001`
public class TextureLayer: Layer {

    /// Creates a texture layer bounded by `rect` and with backend texture
    /// identified by `textureId`. If `freeze` is true, new texture frames will
    /// not be populated to the texture. Use `filterQuality` to set the layer's
    /// `FilterQuality`.
    ///
    /// **Dart Source:** `layer.dart:956-961`
    public init(
        rect: Rect,
        textureId: Int,
        freeze: Bool = false,
        filterQuality: FilterQuality = .low
    ) {
        self.rect = rect
        self.textureId = textureId
        self.freeze = freeze
        self.filterQuality = filterQuality
        super.init()
    }

    /// Bounding rectangle of this layer.
    ///
    /// **Dart Source:** `layer.dart:964`
    public let rect: Rect

    /// The identity of the backend texture.
    ///
    /// **Dart Source:** `layer.dart:967`
    public let textureId: Int

    /// When true the texture will not be updated with new frames.
    ///
    /// This is used for resizing embedded Android views: when resizing there
    /// is a short period during which the framework cannot tell if the newest
    /// texture frame has the previous or new size; to work around this, the
    /// framework "freezes" the texture just before resizing the Android view and
    /// un-freezes it when it is certain that a frame with the new size is ready.
    ///
    /// **Dart Source:** `layer.dart:969-976`
    public let freeze: Bool

    /// The quality of the filter to apply when scaling the texture.
    ///
    /// **Dart Source:** `layer.dart:978-979`
    public let filterQuality: FilterQuality

    /// Texture layers must always be re-composited because the engine
    /// re-queries texture content each frame.
    ///
    /// **Dart Source:** `layer.dart:983`
    public override var alwaysNeedsAddToScene: Bool { true }

    /// Adds this texture layer to the scene.
    ///
    /// **Dart Source:** `layer.dart:981-991`
    public override func addToScene(_ builder: SceneBuilder) {
        builder.addTexture(
            textureId,
            offset: rect.topLeft,
            width: rect.width,
            height: rect.height,
            freeze: freeze,
            filterQuality: filterQuality
        )
    }

    /// Texture layers are always leaves and do not contain annotations.
    ///
    /// **Dart Source:** `layer.dart:993-1000`
    public override func findAnnotations<S>(
        _ result: AnnotationResult<S>,
        _ localPosition: Offset,
        onlyFirst: Bool
    ) -> Bool {
        return false
    }
}

// MARK: - TextureBox

/// A rectangle upon which a backend texture is mapped.
///
/// Backend textures are images that can be applied (mapped) to an area of the
/// Flutter view. They are created, managed, and updated using a
/// platform-specific texture registry. This is typically done by a plugin
/// that integrates with host platform video player, camera, or OpenGL APIs,
/// or similar image sources.
///
/// A texture box refers to its backend texture using an integer ID. Texture
/// IDs are obtained from the texture registry and are scoped to the Flutter
/// view. Texture IDs may be reused after deregistration, at the discretion
/// of the registry. The use of texture IDs currently unknown to the registry
/// will silently result in a blank rectangle.
///
/// Texture boxes are repainted autonomously as dictated by the backend (e.g. on
/// arrival of a video frame). Such repainting generally does not involve
/// executing Dart code.
///
/// The size of the rectangle is determined by the parent, and the texture is
/// automatically scaled to fit.
///
/// See also:
///
///  * [TextureRegistry](/javadoc/io/flutter/view/TextureRegistry.html)
///    for how to create and manage backend textures on Android.
///  * [TextureRegistry Protocol](/ios-embedder/protocol_flutter_texture_registry-p.html)
///    for how to create and manage backend textures on iOS.
///
/// **Dart Source:** `texture.dart:38-108`
public class TextureBox: RenderBox {

    // MARK: - Initializer

    /// Creates a box backed by the texture identified by `textureId`, and uses
    /// `filterQuality` to set the texture's `FilterQuality`.
    ///
    /// **Dart Source:** `texture.dart:41-47`
    public init(
        textureId: Int,
        freeze: Bool = false,
        filterQuality: FilterQuality = .low,
        sourceRect: Rect? = nil,
        crop: Rect? = nil
    ) {
        self._textureId = textureId
        self._freeze = freeze
        self._filterQuality = filterQuality
        self._sourceRect = sourceRect
        self._crop = crop
        super.init()
    }

    // MARK: - Properties

    /// The identity of the backend texture.
    ///
    /// **Dart Source:** `texture.dart:49-57`
    public var textureId: Int {
        get { _textureId }
        set {
            if newValue != _textureId {
                _textureId = newValue
                markNeedsPaint()
            }
        }
    }
    private var _textureId: Int

    /// When true the texture will not be updated with new frames.
    ///
    /// **Dart Source:** `texture.dart:59-67`
    public var freeze: Bool {
        get { _freeze }
        set {
            if newValue != _freeze {
                _freeze = newValue
                markNeedsPaint()
            }
        }
    }
    private var _freeze: Bool

    /// The quality of the filter to apply when scaling the texture.
    ///
    /// **Dart Source:** `texture.dart:69-77`
    public var filterQuality: FilterQuality {
        get { _filterQuality }
        set {
            if newValue != _filterQuality {
                _filterQuality = newValue
                markNeedsPaint()
            }
        }
    }
    private var _filterQuality: FilterQuality

    /// Optional source rect for UV crop (physical pixels).
    public var sourceRect: Rect? {
        get { _sourceRect }
        set {
            if newValue != _sourceRect {
                _sourceRect = newValue
                markNeedsPaint()
            }
        }
    }
    private var _sourceRect: Rect?

    /// The part of the texture this box shows, in unit texture coordinates
    /// (0...1 on both axes), scaled to fill the box. nil shows all of it.
    ///
    /// Unlike `sourceRect`, which is a fixed paint rect in logical pixels,
    /// this follows the box: the same value crops the same region whether the
    /// box is a window's content area or a thumbnail of it. It is how one
    /// scanout becomes many windows — each shows its own rectangle of a
    /// texture they all share.
    public var crop: Rect? {
        get { _crop }
        set {
            if newValue != _crop {
                _crop = newValue
                markNeedsPaint()
            }
        }
    }
    private var _crop: Rect?

    // MARK: - RenderBox Overrides

    /// Whether this render object's layout information is determined solely
    /// by the constraints provided by the parent.
    ///
    /// **Dart Source:** `texture.dart:80`
    public override var sizedByParent: Bool { true }

    /// Whether this render object always needs compositing.
    ///
    /// **Dart Source:** `texture.dart:83`
    public override var alwaysNeedsCompositing: Bool { true }

    /// Whether this render object is a repaint boundary.
    ///
    /// **Dart Source:** `texture.dart:86`
    ///
    /// DIFFERENCE FROM DART: `texture.dart:86` returns true; this returns
    /// false.
    /// REASON: this port has no interior repaint-boundary compositing to hang
    /// a texture on. Dart's `_compositeChild` puts the child's painting in its
    /// own `OffsetLayer` and carries the parent's paint offset on that layer
    /// (`childOffsetLayer.offset = offset`, object.dart:290). There is no
    /// `OffsetLayer` here, and `RenderObject._layer` is only ever set for the
    /// `RenderView`, so `repaintCompositedChild` returns at its `_layer` guard
    /// without calling `paint` and `_compositeChild` appends nothing. A
    /// boundary subtree does not render at all.
    ///
    /// So returning true here means `paint` below never runs, no `TextureLayer`
    /// is ever added, and every texture in the desktop stops rendering — the
    /// wallpaper and the contents of every window. `792f90f` flipped it true;
    /// the T3 VM tier caught it on unreleased `main`, before it reached a
    /// release (`v0.2.1` is tagged at `1401708`, which predates it — note that
    /// `package-desktop.sh` hardcodes the version, so a .deb built from `main`
    /// still calls itself 0.2.1). Flip this back only together with real
    /// boundary compositing (see `_compositeChild`).
    public override var isRepaintBoundary: Bool { false }

    /// Computes the dry layout size for the given constraints.
    ///
    /// Returns the biggest size that satisfies the constraints, since the texture
    /// fills all available space.
    ///
    /// **Dart Source:** `texture.dart:88-92`
    public override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        return constraints.biggest
    }

    /// Returns true to indicate that this render object can be hit.
    ///
    /// **Dart Source:** `texture.dart:95`
    public override func hitTestSelf(_ position: Offset) -> Bool { true }

    // MARK: - Paint

    /// Paints the texture by adding a `TextureLayer` to the compositing tree.
    ///
    /// **Dart Source:** `texture.dart:97-107`
    public override func paint(_ context: PaintingContext, _ offset: Offset) {
        let localOrigin: Offset
        var layerRect: Rect
        if let src = _sourceRect {
            // sourceRect provides a custom paint rect (origin + size, relative to
            // layout position). Renders the texture larger than the layout rect so
            // a parent ClipRect can crop CSD shadows from Wayland client buffers.
            localOrigin = Offset(src.left, src.top)
            layerRect = Rect.fromLTWH(offset.dx + src.left, offset.dy + src.top,
                                       src.width, src.height)
        } else if let c = _crop, c.width > 0, c.height > 0 {
            // The whole texture, drawn so that exactly `crop` of it lands on
            // this box; the parent clips the rest. Derived from the box's own
            // size, so a scaled box scales the crop with it.
            let fullW = size.width / c.width
            let fullH = size.height / c.height
            localOrigin = Offset(-c.left * fullW, -c.top * fullH)
            layerRect = Rect.fromLTWH(offset.dx + localOrigin.dx,
                                       offset.dy + localOrigin.dy, fullW, fullH)
        } else {
            localOrigin = Offset.zero
            layerRect = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height)
        }
        layerRect = _snapToPhysicalPixels(layerRect, localOrigin: localOrigin)
        context.addLayer(
            TextureLayer(
                rect: layerRect,
                textureId: _textureId,
                freeze: _freeze,
                filterQuality: _filterQuality
            )
        )
    }

    /// Snaps the texture quad to the physical pixel grid.
    ///
    /// Window rects are logical floats, so the quad's physical origin is
    /// usually fractional and its physical extent need not equal the backing
    /// buffer's texel count. Bilinear sampling then blends adjacent texels
    /// on every output pixel — visibly blurry text. Rounding the on-screen
    /// rect to whole physical pixels makes a 1:1-sized buffer sample exactly
    /// at texel centers, where linear filtering degenerates to a copy.
    ///
    /// Applies only while the texture is composited unscaled; zoom animations
    /// and scaled thumbnails keep ordinary filtering.
    private func _snapToPhysicalPixels(_ rect: Rect, localOrigin: Offset) -> Rect {
        var node: RenderObject? = self
        while node != nil, !(node is RenderView) { node = node?.parent }
        guard let view = node as? RenderView,
              case let dpr = view.configuration.devicePixelRatio, dpr > 0 else {
            return rect
        }

        let m = getTransformTo(nil)
        let sx = m.entry(0, 0), sy = m.entry(1, 1)
        let eps = 1e-6
        guard abs(m.entry(0, 1)) < eps, abs(m.entry(1, 0)) < eps,
              abs(abs(sx) - 1) < eps, abs(abs(sy) - 1) < eps else {
            return rect
        }

        // Move the quad's global origin onto a whole physical pixel, mapping
        // the correction back through the (axis-aligned, |scale| = 1)
        // transform so it also lands right under a Y-flip.
        let g = localToGlobal(localOrigin)
        let dxg = (g.dx * dpr).rounded() / dpr - g.dx
        let dyg = (g.dy * dpr).rounded() / dpr - g.dy
        // Size rounds to whole physical pixels with the same rounding the
        // child app uses for its buffer, so quad pixels == buffer texels.
        let w = (rect.width * dpr).rounded() / dpr
        let h = (rect.height * dpr).rounded() / dpr
        return Rect.fromLTWH(rect.left + dxg / sx, rect.top + dyg / sy, w, h)
    }
}
