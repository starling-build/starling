// ImageBridge: an SkImage in skwasm.
import CSkwasm

/// Raw pixels as the caller supplied them, kept on our side of the boundary.
/// dart:ui's PixelFormat decides the layout: 0 rgba8888 and 1 bgra8888 are
/// premultiplied bytes, 2 rgbaFloat32 is four unpremultiplied Float32s.
struct RawPixels {
    var bytes: [UInt8]
    var width: Int
    var height: Int
    var rowBytes: Int
    var pixelFormat: Int32

    static func bytesPerPixel(_ pixelFormat: Int32) -> Int {
        pixelFormat == 2 ? 16 : 4
    }

    var bytesPerPixel: Int { RawPixels.bytesPerPixel(pixelFormat) }

    /// What Skia checks before it accepts the description. Doing it here
    /// turns a null SkImage into an error that says why.
    var problem: String? {
        guard width > 0, height > 0 else { return "Image dimensions must be positive" }
        guard (0...2).contains(pixelFormat) else { return "Unknown pixel format" }
        guard rowBytes >= width * bytesPerPixel else {
            return "Row bytes is smaller than one row of pixels"
        }
        // The last row need not be padded out to rowBytes.
        let needed = Int64(rowBytes) * Int64(height - 1) + Int64(width * bytesPerPixel)
        guard Int64(bytes.count) >= needed else {
            return "Pixel buffer is too small for the image dimensions"
        }
        return nil
    }
}

extension flutter.swift_bridge {
    public final class ImageBridge {
        /// The SkImage*. 0 if none was ever set, and again after Dispose.
        public private(set) var skHandle: sk_ptr
        private var disposed = false

        /// The source pixels, when this image was made from raw pixels. It is
        /// what makes a synchronous ToByteData possible at all: skwasm can
        /// only read an image back asynchronously, through the page.
        private var pixels: RawPixels?

        /// An empty image; SetSkImage gives it one.
        public init() {
            skHandle = 0
        }

        /// Takes over one reference to `skImage` (as returned by any
        /// `image_create…`, or after an `image_ref`). For the other bridge
        /// classes that produce images: Picture.ToImage, the codec.
        public init(adopting skImage: sk_ptr) {
            skHandle = skImage
        }

        init(adopting skImage: sk_ptr, pixels: RawPixels?) {
            skHandle = skImage
            self.pixels = pixels
        }

        deinit {
            if skHandle != 0 { image_dispose(skHandle) }
        }

        /// Replaces the image, taking over one reference to `skImage`. The
        /// counterpart of the native SetDlImageFromPtr.
        public func SetSkImage(_ skImage: sk_ptr) {
            if skHandle != 0 { image_dispose(skHandle) }
            skHandle = skImage
            pixels = nil
            disposed = false
        }

        /// The SkImage handle wearing a pointer's type (`skOpaque`): never
        /// dereferenced, only unwrapped again. Borrowed, not retained.
        public func GetDlImagePtr() -> UnsafeRawPointer? {
            skOpaque(skHandle)
        }

        /// As SetSkImage, for a handle that arrives as an opaque pointer.
        public func SetDlImageFromPtr(_ pointer: UnsafeMutableRawPointer?) {
            SetSkImage(FlutterSwiftBridgeCxx.skHandle(from: UnsafeRawPointer(pointer)))
        }

        public func Width() -> Int32 {
            skHandle != 0 ? image_getWidth(skHandle) : 0
        }

        public func Height() -> Int32 {
            skHandle != 0 ? image_getHeight(skHandle) : 0
        }

        /// 0 = sRGB: every image skwasm makes is tagged sRGB.
        public func GetColorSpace() -> Int32 { 0 }

        public func Dispose() {
            if skHandle != 0 { image_dispose(skHandle) }
            skHandle = 0
            pixels = nil
            disposed = true
        }

        public func IsDisposed() -> Bool { disposed }

        /// "[640×480]", as dart:ui's _Image.toString.
        public func ToString(_ buffer: UnsafeMutablePointer<CChar>?, _ bufferSize: Int32) {
            imageCopyCString("[\(Width())\u{00D7}\(Height())]", into: buffer, size: bufferSize)
        }

        /// `format` is dart:ui's ImageByteFormat: 0 rawRgba, 1 rawStraightRgba,
        /// 2 rawUnmodified, 3 rawExtendedRgba128, 4 png.
        ///
        /// Real for images made from raw pixels, which are answered from the
        /// bytes kept on our side. Everything else fails with a message, the
        /// way the native bridge fails for a GPU-only image.
        // WEB-TODO: readback of any other image (from a picture, from the
        // browser's decoder), and PNG encoding for all of them. skwasm does
        // it with surface_rasterizeImage(surface, image, format), which
        // returns a callback id at once and delivers an SkData later through
        // the surface's callback handler. That handler is a function in
        // skwasm's table taking an externref, so the page owns it: it would
        // have to forward (callbackId, SkData*) to an export of ours, which
        // reads the bytes with skData_getConstPointer/skData_getSize and
        // disposes the SkData. The result is asynchronous, so
        // Image.toByteData has to become async on the web as well.
        public func ToByteData(
            _ format: Int32,
            _ outData: UnsafeMutablePointer<UnsafeRawPointer?>?,
            _ outLength: UnsafeMutablePointer<Int64>?,
            _ outError: UnsafeMutablePointer<UnsafePointer<CChar>?>?
        ) -> Bool {
            func fail(_ message: UnsafePointer<CChar>) -> Bool {
                outError?.pointee = message
                return false
            }
            guard skHandle != 0 else { return fail(ImageErrors.noImage) }
            guard (0...4).contains(format) else { return fail(ImageErrors.invalidFormat) }
            guard format != 4 else { return fail(ImageErrors.noEncoder) }
            guard let pixels, let bytes = convert(pixels, to: format), !bytes.isEmpty else {
                return fail(ImageErrors.noReadback)
            }
            let copy = UnsafeMutableRawPointer.allocate(byteCount: bytes.count, alignment: 8)
            bytes.withUnsafeBytes { copy.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
            outData?.pointee = UnsafeRawPointer(copy)
            outLength?.pointee = Int64(bytes.count)
            return true
        }

        public static func FreeByteData(_ data: UnsafeRawPointer?) {
            data?.deallocate()
        }
    }
}

/// ToByteData reports errors as C strings that must outlive the call.
private enum ImageErrors {
    static let noImage = persistentCString("Image has been disposed or has no pixels")
    static let invalidFormat = persistentCString("Invalid image byte format")
    static let noEncoder = persistentCString(
        "PNG encoding is not available in the web build yet")
    static let noReadback = persistentCString(
        "Reading back this image is not available in the web build yet")
}

private func persistentCString(_ text: String) -> UnsafePointer<CChar> {
    let utf8 = Array(text.utf8)
    let p = UnsafeMutablePointer<CChar>.allocate(capacity: utf8.count + 1)
    for (i, byte) in utf8.enumerated() { p[i] = CChar(bitPattern: byte) }
    p[utf8.count] = 0
    return UnsafePointer(p)
}

/// snprintf(buffer, size, "%s", text): truncates, always terminates.
func imageCopyCString(_ text: String, into buffer: UnsafeMutablePointer<CChar>?, size: Int32) {
    guard let buffer, size > 0 else { return }
    var i = 0
    for byte in text.utf8 {
        if i >= Int(size) - 1 { break }
        buffer[i] = CChar(bitPattern: byte)
        i += 1
    }
    buffer[i] = 0
}

// MARK: - Pixel conversion

/// The source pixels in the requested ImageByteFormat, tightly packed (the
/// source's row padding is dropped). nil for PNG.
private func convert(_ source: RawPixels, to format: Int32) -> [UInt8]? {
    guard source.problem == nil else { return nil }
    let floatSource = source.pixelFormat == 2
    // rawUnmodified is the image's own layout, whatever that is.
    let floatResult = format == 3 || (format == 2 && floatSource)
    let count = source.width * source.height
    var out = [UInt8]()
    out.reserveCapacity(count * (floatResult ? 16 : 4))

    source.bytes.withUnsafeBytes { raw in
        for y in 0..<source.height {
            let row = y * source.rowBytes
            for x in 0..<source.width {
                let p = row + x * source.bytesPerPixel
                if format == 2 {
                    for i in 0..<source.bytesPerPixel { out.append(raw[p + i]) }
                    continue
                }
                // Read as straight (unpremultiplied) RGBA in 0...1.
                var r: Float, g: Float, b: Float, a: Float
                if floatSource {
                    r = raw.loadUnaligned(fromByteOffset: p, as: Float.self)
                    g = raw.loadUnaligned(fromByteOffset: p + 4, as: Float.self)
                    b = raw.loadUnaligned(fromByteOffset: p + 8, as: Float.self)
                    a = raw.loadUnaligned(fromByteOffset: p + 12, as: Float.self)
                } else {
                    let swap = source.pixelFormat == 1  // B,G,R,A in memory
                    r = Float(raw[p + (swap ? 2 : 0)]) / 255
                    g = Float(raw[p + 1]) / 255
                    b = Float(raw[p + (swap ? 0 : 2)]) / 255
                    a = Float(raw[p + 3]) / 255
                    if a > 0 {
                        r = min(r / a, 1)
                        g = min(g / a, 1)
                        b = min(b / a, 1)
                    }
                }
                switch format {
                case 3:  // unpremultiplied Float32
                    for v in [r, g, b, a] {
                        withUnsafeBytes(of: v) { out.append(contentsOf: $0) }
                    }
                case 1:  // unpremultiplied bytes
                    for v in [r, g, b, a] { out.append(byte(v)) }
                default:  // 0: premultiplied bytes
                    for v in [r * a, g * a, b * a, a] { out.append(byte(v)) }
                }
            }
        }
    }
    return out
}

private func byte(_ v: Float) -> UInt8 {
    // Written so that NaN lands on 0 rather than trapping in the conversion.
    guard v > 0 else { return 0 }
    return v >= 1 ? 255 : UInt8(v * 255 + 0.5)
}
