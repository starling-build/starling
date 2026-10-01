// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// An image in the render tree.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/image.dart`

import FlutterSwiftBridge

// MARK: - RenderImage

/// A render box that displays an image.
///
/// The render image attempts to find a size for itself that fits in the given
/// constraints and preserves the image's intrinsic aspect ratio.
///
/// The image is painted using `paintImage`, which describes the meanings of the
/// various fields on this class in more detail.
///
/// **Dart Source:** `image.dart:22-340`
public class RenderImage: RenderBox {

    // MARK: - Initializer

    /// Creates a render box that displays an image.
    ///
    /// The `textDirection` argument must not be nil if `alignment` will need
    /// resolving or if `matchTextDirection` is true.
    ///
    /// **Dart Source:** `image.dart:27-62`
    public init(
        image: FlutterSwiftBridge.Image? = nil,
        debugImageLabel: String? = nil,
        width: Double? = nil,
        height: Double? = nil,
        scale: Double = 1.0,
        color: Color? = nil,
        opacity: Animation<Double>? = nil,
        colorBlendMode: BlendMode? = nil,
        fit: BoxFit? = nil,
        alignment: any AlignmentGeometry = Alignment.center,
        repeat imageRepeat: ImageRepeat = .noRepeat,
        centerSlice: Rect? = nil,
        matchTextDirection: Bool = false,
        textDirection: TextDirection? = nil,
        invertColors: Bool = false,
        isAntiAlias: Bool = false,
        filterQuality: FilterQuality = .medium
    ) {
        self._image = image
        self.debugImageLabel = debugImageLabel
        self._width = width
        self._height = height
        self._scale = scale
        self._color = color
        self._opacity = opacity
        self._colorBlendMode = colorBlendMode
        self._fit = fit
        self._alignment = alignment
        self._repeat = imageRepeat
        self._centerSlice = centerSlice
        self._matchTextDirection = matchTextDirection
        self._invertColors = invertColors
        self._textDirection = textDirection
        self._isAntiAlias = isAntiAlias
        self._filterQuality = filterQuality
        super.init()
        _updateColorFilter()
    }

    // MARK: - Resolution State

    /// The resolved alignment after accounting for text direction.
    ///
    /// **Dart Source:** `image.dart:64`
    private var _resolvedAlignment: Alignment?

    /// Whether the image should be flipped horizontally for RTL text direction.
    ///
    /// **Dart Source:** `image.dart:65`
    private var _flipHorizontally: Bool?

    /// Resolves the alignment and flip state based on the current text direction.
    ///
    /// **Dart Source:** `image.dart:67-73`
    private func _resolve() {
        if _resolvedAlignment != nil {
            return
        }
        _resolvedAlignment = alignment.resolve(textDirection)
        _flipHorizontally = matchTextDirection && textDirection == .rtl
    }

    /// Invalidates the cached resolution state and marks the render object as needing paint.
    ///
    /// **Dart Source:** `image.dart:75-79`
    private func _markNeedResolution() {
        _resolvedAlignment = nil
        _flipHorizontally = nil
        markNeedsPaint()
    }

    // MARK: - Image Property

    /// The image to display.
    ///
    /// **Dart Source:** `image.dart:82-101`
    public var image: FlutterSwiftBridge.Image? {
        get { _image }
        set {
            if newValue === _image {
                return
            }
            // If we get a clone of our image, it's the same underlying native data -
            // dispose of the new clone and return early.
            if let newImage = newValue, let currentImage = _image, newImage.isCloneOf(currentImage) {
                newImage.dispose()
                return
            }
            let sizeChanged = _image?.width != newValue?.width || _image?.height != newValue?.height
            _image?.dispose()
            _image = newValue
            markNeedsPaint()
            if sizeChanged && (_width == nil || _height == nil) {
                markNeedsLayout()
            }
        }
    }
    /// **Dart Source:** `image.dart:83`
    private var _image: FlutterSwiftBridge.Image?

    // MARK: - Debug Image Label

    /// A string used to identify the source of the image.
    ///
    /// **Dart Source:** `image.dart:103-104`
    public var debugImageLabel: String?

    // MARK: - Width Property

    /// If non-nil, requires the image to have this width.
    ///
    /// If nil, the image will pick a size that best preserves its intrinsic
    /// aspect ratio.
    ///
    /// **Dart Source:** `image.dart:106-118`
    public var width: Double? {
        get { _width }
        set {
            if newValue == _width {
                return
            }
            _width = newValue
            markNeedsLayout()
        }
    }
    /// **Dart Source:** `image.dart:111`
    private var _width: Double?

    // MARK: - Height Property

    /// If non-nil, require the image to have this height.
    ///
    /// If nil, the image will pick a size that best preserves its intrinsic
    /// aspect ratio.
    ///
    /// **Dart Source:** `image.dart:120-132`
    public var height: Double? {
        get { _height }
        set {
            if newValue == _height {
                return
            }
            _height = newValue
            markNeedsLayout()
        }
    }
    /// **Dart Source:** `image.dart:125`
    private var _height: Double?

    // MARK: - Scale Property

    /// Specifies the image's scale.
    ///
    /// Used when determining the best display size for the image.
    ///
    /// **Dart Source:** `image.dart:134-145`
    public var scale: Double {
        get { _scale }
        set {
            if newValue == _scale {
                return
            }
            _scale = newValue
            markNeedsLayout()
        }
    }
    /// **Dart Source:** `image.dart:138`
    private var _scale: Double

    // MARK: - Color Filter

    /// The cached color filter derived from `color` and `colorBlendMode`.
    ///
    /// **Dart Source:** `image.dart:147`
    private var _colorFilter: ColorFilter?

    /// Updates the cached color filter based on the current `color` and `colorBlendMode`.
    ///
    /// **Dart Source:** `image.dart:149-155`
    private func _updateColorFilter() {
        if _color == nil {
            _colorFilter = nil
        } else {
            _colorFilter = ColorFilter(mode: _color!, _colorBlendMode ?? .srcIn)
        }
    }

    // MARK: - Color Property

    /// If non-nil, this color is blended with each image pixel using `colorBlendMode`.
    ///
    /// **Dart Source:** `image.dart:157-167`
    public var color: Color? {
        get { _color }
        set {
            if newValue == _color {
                return
            }
            _color = newValue
            _updateColorFilter()
            markNeedsPaint()
        }
    }
    /// **Dart Source:** `image.dart:159`
    private var _color: Color?

    // MARK: - Opacity Property

    /// If non-nil, the value from the `Animation` is multiplied with the opacity
    /// of each image pixel before painting onto the canvas.
    ///
    /// **Dart Source:** `image.dart:169-185`
    public var opacity: Animation<Double>? {
        get { _opacity }
        set {
            if newValue === _opacity {
                return
            }
            if attached {
                _opacity?.removeListeners(owner: self)
            }
            _opacity = newValue
            if attached {
                newValue?.addListener(markNeedsPaint, owner: self)
            }
        }
    }
    /// **Dart Source:** `image.dart:172`
    private var _opacity: Animation<Double>?

    // MARK: - Filter Quality Property

    /// Used to set the filterQuality of the image.
    ///
    /// Defaults to `FilterQuality.medium`.
    ///
    /// **Dart Source:** `image.dart:187-198`
    public var filterQuality: FilterQuality {
        get { _filterQuality }
        set {
            if newValue == _filterQuality {
                return
            }
            _filterQuality = newValue
            markNeedsPaint()
        }
    }
    /// **Dart Source:** `image.dart:191`
    private var _filterQuality: FilterQuality

    // MARK: - Color Blend Mode Property

    /// Used to combine `color` with this image.
    ///
    /// The default is `BlendMode.srcIn`. In terms of the blend mode, `color` is
    /// the source and this image is the destination.
    ///
    /// **Dart Source:** `image.dart:200-217`
    public var colorBlendMode: BlendMode? {
        get { _colorBlendMode }
        set {
            if newValue == _colorBlendMode {
                return
            }
            _colorBlendMode = newValue
            _updateColorFilter()
            markNeedsPaint()
        }
    }
    /// **Dart Source:** `image.dart:209`
    private var _colorBlendMode: BlendMode?

    // MARK: - Fit Property

    /// How to inscribe the image into the space allocated during layout.
    ///
    /// The default varies based on the other fields. See the discussion at
    /// `paintImage`.
    ///
    /// **Dart Source:** `image.dart:219-231`
    public var fit: BoxFit? {
        get { _fit }
        set {
            if newValue == _fit {
                return
            }
            _fit = newValue
            markNeedsPaint()
        }
    }
    /// **Dart Source:** `image.dart:224`
    private var _fit: BoxFit?

    // MARK: - Alignment Property

    /// How to align the image within its bounds.
    ///
    /// If this is set to a text-direction-dependent value, `textDirection` must
    /// not be nil.
    ///
    /// **Dart Source:** `image.dart:233-245`
    public var alignment: any AlignmentGeometry {
        get { _alignment }
        set {
            if newValue == _alignment {
                return
            }
            _alignment = newValue
            _markNeedResolution()
        }
    }
    /// **Dart Source:** `image.dart:238`
    private var _alignment: any AlignmentGeometry

    // MARK: - Repeat Property

    /// How to repeat this image if it doesn't fill its layout bounds.
    ///
    /// **Dart Source:** `image.dart:247-256`
    public var imageRepeat: ImageRepeat {
        get { _repeat }
        set {
            if newValue == _repeat {
                return
            }
            _repeat = newValue
            markNeedsPaint()
        }
    }
    /// **Dart Source:** `image.dart:249`
    private var _repeat: ImageRepeat

    // MARK: - Center Slice Property

    /// The center slice for a nine-patch image.
    ///
    /// The region of the image inside the center slice will be stretched both
    /// horizontally and vertically to fit the image into its destination. The
    /// region of the image above and below the center slice will be stretched
    /// only horizontally and the region of the image to the left and right of
    /// the center slice will be stretched only vertically.
    ///
    /// **Dart Source:** `image.dart:258-273`
    public var centerSlice: Rect? {
        get { _centerSlice }
        set {
            if newValue == _centerSlice {
                return
            }
            _centerSlice = newValue
            markNeedsPaint()
        }
    }
    /// **Dart Source:** `image.dart:266`
    private var _centerSlice: Rect?

    // MARK: - Invert Colors Property

    /// Whether to invert the colors of the image.
    ///
    /// Inverting the colors of an image applies a new color filter to the paint.
    /// If there is another specified color filter, the invert will be applied
    /// after it. This is primarily used for implementing smart invert on iOS.
    ///
    /// **Dart Source:** `image.dart:275-288`
    public var invertColors: Bool {
        get { _invertColors }
        set {
            if newValue == _invertColors {
                return
            }
            _invertColors = newValue
            markNeedsPaint()
        }
    }
    /// **Dart Source:** `image.dart:281`
    private var _invertColors: Bool

    // MARK: - Match Text Direction Property

    /// Whether to paint the image in the direction of the `TextDirection`.
    ///
    /// If this is true, then in `TextDirection.ltr` contexts, the image will be
    /// drawn with its origin in the top left (the "normal" painting direction for
    /// images); and in `TextDirection.rtl` contexts, the image will be drawn with
    /// a scaling factor of -1 in the horizontal direction so that the origin is
    /// in the top right.
    ///
    /// This is occasionally used with images in right-to-left environments, for
    /// images that were designed for left-to-right locales. Be careful, when
    /// using this, to not flip images with integral shadows, text, or other
    /// effects that will look incorrect when flipped.
    ///
    /// If this is set to true, `textDirection` must not be nil.
    ///
    /// **Dart Source:** `image.dart:290-312`
    public var matchTextDirection: Bool {
        get { _matchTextDirection }
        set {
            if newValue == _matchTextDirection {
                return
            }
            _matchTextDirection = newValue
            _markNeedResolution()
        }
    }
    /// **Dart Source:** `image.dart:305`
    private var _matchTextDirection: Bool

    // MARK: - Text Direction Property

    /// The text direction with which to resolve `alignment`.
    ///
    /// This may be changed to nil, but only after the `alignment` and
    /// `matchTextDirection` properties have been changed to values that do not
    /// depend on the direction.
    ///
    /// **Dart Source:** `image.dart:314-327`
    public var textDirection: TextDirection? {
        get { _textDirection }
        set {
            if _textDirection == newValue {
                return
            }
            _textDirection = newValue
            _markNeedResolution()
        }
    }
    /// **Dart Source:** `image.dart:320`
    private var _textDirection: TextDirection?

    // MARK: - Anti-Alias Property

    /// Whether to paint the image with anti-aliasing.
    ///
    /// Anti-aliasing alleviates the sawtooth artifact when the image is rotated.
    ///
    /// **Dart Source:** `image.dart:329-340`
    public var isAntiAlias: Bool {
        get { _isAntiAlias }
        set {
            if _isAntiAlias == newValue {
                return
            }
            _isAntiAlias = newValue
            markNeedsPaint()
        }
    }
    /// **Dart Source:** `image.dart:333`
    private var _isAntiAlias: Bool

    // MARK: - Lifecycle

    /// Called when the render object is attached to a pipeline owner.
    ///
    /// Registers the opacity animation listener if an opacity animation is set.
    ///
    /// **Dart Source:** `image.dart:407-411`
    public override func attach(_ owner: PipelineOwner) {
        super.attach(owner)
        _opacity?.addListener(markNeedsPaint, owner: self)
    }

    /// Called when the render object is detached from its pipeline owner.
    ///
    /// Removes the opacity animation listener if an opacity animation is set.
    ///
    /// **Dart Source:** `image.dart:413-417`
    public override func detach() {
        _opacity?.removeListeners(owner: self)
        super.detach()
    }

    // MARK: - Size Calculation

    /// Find a size for the render image within the given constraints.
    ///
    /// - The dimensions of the RenderImage must fit within the constraints.
    /// - The aspect ratio of the RenderImage matches the intrinsic aspect
    ///   ratio of the image.
    /// - The RenderImage's dimensions are maximal subject to being smaller than
    ///   the intrinsic size of the image.
    ///
    /// **Dart Source:** `image.dart:342-361`
    private func _sizeForConstraints(_ constraints: BoxConstraints) -> Size {
        // Folds the given width and height into constraints so they can all
        // be treated uniformly.
        let constraints = BoxConstraints.tightFor(width: _width, height: _height)
            .enforce(constraints)

        guard let image = _image else {
            return constraints.smallest
        }

        return constraints.constrainSizeAndAttemptToPreserveAspectRatio(
            Size(Double(image.width) / _scale, Double(image.height) / _scale)
        )
    }

    // MARK: - Intrinsic Dimensions

    /// Returns the minimum width that this box could be without failing to
    /// correctly paint its contents within itself, without clipping.
    ///
    /// **Dart Source:** `image.dart:363-370`
    public override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        assert(height >= 0.0)
        if _width == nil && _height == nil {
            return 0.0
        }
        return _sizeForConstraints(BoxConstraints.tightForFinite(height: height)).width
    }

    /// Returns the smallest width beyond which increasing the width never
    /// decreases the preferred height.
    ///
    /// **Dart Source:** `image.dart:372-376`
    public override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        assert(height >= 0.0)
        return _sizeForConstraints(BoxConstraints.tightForFinite(height: height)).width
    }

    /// Returns the minimum height that this box could be without failing to
    /// correctly paint its contents within itself, without clipping.
    ///
    /// **Dart Source:** `image.dart:378-385`
    public override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        assert(width >= 0.0)
        if _width == nil && _height == nil {
            return 0.0
        }
        return _sizeForConstraints(BoxConstraints.tightForFinite(width: width)).height
    }

    /// Returns the smallest height beyond which increasing the height never
    /// decreases the preferred width.
    ///
    /// **Dart Source:** `image.dart:387-391`
    public override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        assert(width >= 0.0)
        return _sizeForConstraints(BoxConstraints.tightForFinite(width: width)).height
    }

    // MARK: - Hit Testing

    /// Returns true if the given position is contained in this render object.
    ///
    /// RenderImage always returns `true` because the image fills its bounds.
    ///
    /// **Dart Source:** `image.dart:394`
    public override func hitTestSelf(_ position: Offset) -> Bool { true }

    // MARK: - Layout

    /// Computes the dry layout for the given constraints without mutating state.
    ///
    /// **Dart Source:** `image.dart:396-400`
    public override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        return _sizeForConstraints(constraints)
    }

    /// Performs layout by computing the size from the current constraints.
    ///
    /// **Dart Source:** `image.dart:402-405`
    public override func performLayout() {
        size = _sizeForConstraints(boxConstraints)
    }

    // MARK: - Painting

    /// Paints the image into the given context at the given offset.
    ///
    /// If no image is set, this method returns immediately. Otherwise, it resolves
    /// the alignment and flip state, then delegates to the `paintImage` utility function.
    ///
    /// **Dart Source:** `image.dart:419-444`
    public override func paint(_ context: PaintingContext, _ offset: Offset) {
        guard let image = _image else {
            return
        }
        _resolve()
        assert(_resolvedAlignment != nil)
        assert(_flipHorizontally != nil)
        paintImage(
            canvas: context.canvas,
            rect: offset & size,
            image: image,
            debugImageLabel: debugImageLabel,
            scale: _scale,
            colorFilter: _colorFilter,
            fit: _fit,
            alignment: _resolvedAlignment!,
            centerSlice: _centerSlice,
            repeat: _repeat,
            flipHorizontally: _flipHorizontally!,
            opacity: _opacity?.value ?? 1.0,
            filterQuality: _filterQuality,
            invertColors: invertColors,
            isAntiAlias: _isAntiAlias
        )
    }

    // MARK: - Disposal

    /// Releases the image resource and calls super dispose.
    ///
    /// **Dart Source:** `image.dart:446-451`
    public override func dispose() {
        _image?.dispose()
        _image = nil
        super.dispose()
    }

    // MARK: - Diagnostics

    /// Add additional properties associated with the node.
    ///
    /// **Dart Source:** `image.dart:453-475`
    public func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        // super.debugFillProperties(properties) — not yet available on RenderObject stub.
        // TODO: Call super.debugFillProperties(properties) once available.
        properties.add(DiagnosticsProperty<FlutterSwiftBridge.Image>("image", image))
        properties.add(DoubleProperty("width", width, defaultValue: nil))
        properties.add(DoubleProperty("height", height, defaultValue: nil))
        properties.add(DoubleProperty("scale", scale, defaultValue: 1.0))
        properties.add(ColorProperty("color", color, defaultValue: nil))
        properties.add(DiagnosticsProperty<Animation<Double>?>("opacity", opacity, defaultValue: nil))
        properties.add(EnumProperty<BlendMode>("colorBlendMode", colorBlendMode, defaultValue: nil))
        properties.add(DiagnosticsProperty<BoxFit>("fit", fit, defaultValue: nil))
        properties.add(DiagnosticsProperty<any AlignmentGeometry>("alignment", alignment, defaultValue: nil))
        properties.add(DiagnosticsProperty<ImageRepeat>("repeat", imageRepeat, defaultValue: ImageRepeat.noRepeat))
        properties.add(DiagnosticsProperty<Rect>("centerSlice", centerSlice, defaultValue: nil))
        properties.add(FlagProperty("matchTextDirection", value: matchTextDirection, ifTrue: "match text direction"))
        properties.add(EnumProperty<TextDirection>("textDirection", textDirection, defaultValue: nil))
        properties.add(DiagnosticsProperty<Bool>("invertColors", invertColors))
        properties.add(EnumProperty<FilterQuality>("filterQuality", filterQuality))
    }
}
