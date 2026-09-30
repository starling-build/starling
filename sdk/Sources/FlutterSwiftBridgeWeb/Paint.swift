// Decoding the framework's paint buffer into a skwasm paint.
import CSkwasm

// The framework's Paint is 17 four-byte fields, each encoded so that an
// all-zero buffer is the default paint (painting.dart's layout, read natively
// by canvas_bridge.cc's DecodePaint). That is why antialiasing is "on" at 0,
// alpha is stored inverted, the blend mode is XORed with srcOver and the
// miter limit is an offset from 4.
private enum Field {
    static let isAntiAlias = 0
    static let red = 1
    static let green = 2
    static let blue = 3
    static let alpha = 4
    static let blendMode = 6
    static let style = 7
    static let strokeWidth = 8
    static let strokeCap = 9
    static let strokeJoin = 10
    static let strokeMiterLimit = 11
    static let maskFilter = 13
    static let maskFilterBlurStyle = 14
    static let maskFilterSigma = 15
    static let invertColors = 16
}

private let blendModeSrcOver: UInt32 = 3

/// A skwasm DlPaint that lives for one draw call.
public struct WebPaint {
    public let skHandle: sk_ptr
    private let maskFilter: sk_ptr

    /// Returns nil for a nil buffer, which the draw calls that allow it
    /// (saveLayer, drawImage) pass on as "no paint".
    public init?(
        _ data: UnsafeRawPointer?,
        shader: UnsafeRawPointer? = nil,
        colorFilter: UnsafeRawPointer? = nil,
        imageFilter: UnsafeRawPointer? = nil
    ) {
        guard let data else { return nil }
        func u(_ i: Int) -> UInt32 { data.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self) }
        func f(_ i: Int) -> Float { data.loadUnaligned(fromByteOffset: i * 4, as: Float.self) }

        skHandle = paint_create(
            u(Field.isAntiAlias) == 0,
            Int32(bitPattern: u(Field.blendMode) ^ blendModeSrcOver),
            WebPaint.argb(f(Field.red), f(Field.green), f(Field.blue), 1 - f(Field.alpha)),
            Int32(bitPattern: u(Field.style)),
            f(Field.strokeWidth),
            Int32(bitPattern: u(Field.strokeCap)),
            Int32(bitPattern: u(Field.strokeJoin)),
            f(Field.strokeMiterLimit) + 4,
            u(Field.invertColors) != 0)

        if let h = Optional(CSkwasmHandle(shader)), h != 0 { paint_setShader(skHandle, h) }
        if let h = Optional(CSkwasmHandle(colorFilter)), h != 0 {
            paint_setColorFilter(skHandle, h)
        }
        if let h = Optional(CSkwasmHandle(imageFilter)), h != 0 {
            paint_setImageFilter(skHandle, h)
        }

        // 1 is the only mask filter type there is: blur.
        if u(Field.maskFilter) == 1 {
            maskFilter = maskFilter_createBlur(
                Int32(bitPattern: u(Field.maskFilterBlurStyle)), f(Field.maskFilterSigma))
            paint_setMaskFilter(skHandle, maskFilter)
        } else {
            maskFilter = 0
        }
    }

    /// A plain paint, for the layer tree's own saveLayers.
    public init(color: UInt32 = 0xFF00_0000, blendMode: Int32 = 3) {
        skHandle = paint_create(true, blendMode, color, 0, 0, 0, 0, 4, false)
        maskFilter = 0
    }

    public func dispose() {
        paint_dispose(skHandle)
        if maskFilter != 0 { maskFilter_dispose(maskFilter) }
    }

    /// skwasm takes 8-bit ARGB; the framework stores float components that
    /// may lie outside 0...1 in a wide gamut.
    // WEB-TODO: wide-gamut colour is clamped to sRGB here.
    static func argb(_ r: Float, _ g: Float, _ b: Float, _ a: Float) -> UInt32 {
        func byte(_ v: Float) -> UInt32 {
            if !(v > 0) { return 0 }  // also catches NaN
            return v >= 1 ? 255 : UInt32(v * 255 + 0.5)
        }
        return byte(a) << 24 | byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}

@inline(__always)
private func CSkwasmHandle(_ p: UnsafeRawPointer?) -> sk_ptr { skHandle(from: p) }

/// Runs `body` with a skwasm paint decoded from the framework's buffer, or
/// with 0 when there is no buffer.
@inline(__always)
func withWebPaint(
    _ data: UnsafeRawPointer?, _ shader: UnsafeRawPointer?,
    _ colorFilter: UnsafeRawPointer?, _ imageFilter: UnsafeRawPointer?,
    _ body: (sk_ptr) -> Void
) {
    let paint = WebPaint(data, shader: shader, colorFilter: colorFilter, imageFilter: imageFilter)
    body(paint?.skHandle ?? 0)
    paint?.dispose()
}
