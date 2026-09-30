// CodecBridge and ImageDescriptorBridge: from bytes to images.
//
// Two kinds of source, and only one of them works yet. RAW pixels go straight
// to skwasm (image_createFromPixels). ENCODED data (PNG, JPEG, GIF, WebP)
// cannot be decoded by the skwasm build we ship — the light build has no
// image codecs, animatedImage_create warns and returns null — so the browser
// has to do it, and that goes through the page.
//
// WEB-TODO: decoding encoded images. What is needed from the page:
//
//   HOST(decode_image)
//   void starling_host_decode_image(uint32_t requestId, const void* bytes,
//                                   uint32_t length, sk_ptr surface,
//                                   int32_t targetWidth, int32_t targetHeight);
//
// The page copies `length` bytes out of OUR memory before returning, decodes
// them (createImageBitmap(new Blob([bytes]), {resizeWidth, resizeHeight}) for
// a still image; ImageDecoder for an animated one, one VideoFrame per frame),
// and calls skwasm's image_createFromTextureSource(bitmap, width, height,
// surface) itself — that function takes an externref, which Swift cannot
// pass. It then calls an export of ours,
//
//   void starling_image_decoded(uint32_t requestId, sk_ptr skImage,
//                               int32_t width, int32_t height,
//                               int32_t frameCount, int32_t repetitionCount,
//                               int32_t durationMs);
//
// with skImage 0 if the data could not be decoded. `surface` is the
// Skwasm::Surface the frame is rendered to, which another family owns.
// Decoding in a browser is asynchronous, and both bridge entry points are
// synchronous (the descriptor's constructor followed by IsValid, and
// DecodeNextFrame), so ImageDescriptor(encoded:) and Codec.getNextFrame in
// FlutterSwiftBridge need an awaiting path on the web as well.
import CSkwasm

extension flutter.swift_bridge {
    public final class CodecBridge {
        private var pixels: RawPixels?
        /// The decoded frame, created on the first DecodeNextFrame and shared
        /// by every frame handed out after it: each ImageBridge holds its own
        /// reference (image_ref), so there is one copy of the pixels in
        /// skwasm however often the frame is asked for.
        private var skImage: sk_ptr = 0
        private var lastFrame: ImageBridge?
        private var lastError = ""
        private var disposed = false

        /// A single-frame codec over raw pixels.
        init(pixels: RawPixels) {
            self.pixels = pixels
        }

        /// A single-frame codec over an image the page decoded. The frame
        /// is shared with the descriptor (image_ref).
        // WEB-TODO: animated images are their first frame.
        init(decoded: WebDecodedImage) {
            image_ref(decoded.skImage)
            skImage = decoded.skImage
        }

        deinit {
            if skImage != 0 { image_dispose(skImage) }
        }

        /// nil: the data cannot be decoded here. See the WEB-TODO above.
        public static func CreateFromEncodedData(_ buffer: ImmutableBufferBridge?)
            -> CodecBridge?
        {
            nil
        }

        /// `pixelFormat` is dart:ui's PixelFormat (0 rgba8888, 1 bgra8888,
        /// 2 rgbaFloat32), not the Skia colour type the native factory takes:
        /// it is what image_createFromPixels wants.
        public static func CreateFromRawPixels(
            _ buffer: ImmutableBufferBridge?, _ width: Int32, _ height: Int32,
            _ rowBytes: Int32, _ pixelFormat: Int32
        ) -> CodecBridge? {
            guard let buffer, !buffer.IsDisposed() else { return nil }
            return CodecBridge(
                pixels: RawPixels(
                    bytes: buffer.bytes, width: Int(width), height: Int(height),
                    rowBytes: Int(rowBytes), pixelFormat: pixelFormat))
        }

        public func GetFrameCount() -> Int32 {
            pixels != nil ? 1 : 0
        }

        /// 0: play once.
        public func GetRepetitionCount() -> Int32 { 0 }

        public func DecodeNextFrame() -> Bool {
            guard !disposed else {
                lastError = "Codec has been disposed"
                return false
            }
            lastFrame = nil
            lastError = ""
            if skImage != 0, pixels == nil {
                // Decoded by the page: the frame is already an image.
                image_ref(skImage)
                lastFrame = ImageBridge(adopting: skImage)
                return true
            }
            guard let pixels else {
                lastError = "Could not provide any frame."
                return false
            }

            if skImage == 0 {
                if let problem = pixels.problem {
                    lastError = problem
                    return false
                }
                let data = imageMakeSkData(from: pixels.bytes)
                guard data != 0 else {
                    lastError = "Failed to allocate memory for bitmap"
                    return false
                }
                skImage = image_createFromPixels(
                    data, Int32(pixels.width), Int32(pixels.height), pixels.pixelFormat,
                    UInt32(pixels.rowBytes))
                // The image took its own reference to the data.
                skData_dispose(data)
                guard skImage != 0 else {
                    lastError = "Failed to create image from raw pixel data"
                    return false
                }
            }

            image_ref(skImage)
            lastFrame = ImageBridge(adopting: skImage, pixels: pixels)
            return true
        }

        public func GetLastFrameImage() -> ImageBridge? { lastFrame }

        /// Always 0: a raw image is a single frame.
        public func GetLastFrameDurationMs() -> Int32 { 0 }

        public func GetLastError(_ buffer: UnsafeMutablePointer<CChar>?, _ bufferSize: Int32) {
            imageCopyCString(lastError, into: buffer, size: bufferSize)
        }

        public func Dispose() {
            disposed = true
            pixels = nil
            lastFrame = nil
            if skImage != 0 { image_dispose(skImage) }
            skImage = 0
        }

        public func ToString(_ buffer: UnsafeMutablePointer<CChar>?, _ bufferSize: Int32) {
            let count = GetFrameCount()
            imageCopyCString(
                count > 0 ? "Codec(\(count) frames)" : "Codec()", into: buffer, size: bufferSize)
        }
    }

    public final class ImageDescriptorBridge {
        private var pixels: RawPixels?
        private var disposed = false

        /// Raw pixels. `rowBytes` of -1 means `width * bytesPerPixel`;
        /// `pixelFormat` is dart:ui's PixelFormat.
        public init(
            _ buffer: ImmutableBufferBridge?, _ width: Int32, _ height: Int32,
            _ rowBytes: Int32, _ pixelFormat: Int32
        ) {
            let bytesPerRow =
                rowBytes == -1
                ? Int(width) * RawPixels.bytesPerPixel(pixelFormat) : Int(rowBytes)
            pixels = RawPixels(
                bytes: buffer?.bytes ?? [], width: Int(width), height: Int(height),
                rowBytes: bytesPerRow, pixelFormat: pixelFormat)
        }

        /// Encoded data. Not valid until `decode()` has run: the browser
        /// decodes, asynchronously, and the framework's
        /// `ImageDescriptor.encoded` awaits it (the `#if os(WASI)` branch
        /// in Painting.swift).
        private var encoded: [UInt8]?
        private var decoded: WebDecodedImage?

        public init(_ buffer: ImmutableBufferBridge?) {
            pixels = nil
            encoded = buffer?.bytes
        }

        deinit {
            if let decoded { image_dispose(decoded.skImage) }
        }

        /// Has the page decode the encoded bytes. False if it could not.
        public func decode() async -> Bool {
            guard decoded == nil else { return true }
            guard let encoded, !disposed else { return false }
            decoded = await WebImageDecoder.decode(encoded)
            self.encoded = nil
            return decoded != nil
        }

        public func IsValid() -> Bool { (pixels != nil || decoded != nil) && !disposed }

        public func GetWidth() -> Int32 { decoded?.width ?? Int32(pixels?.width ?? 0) }

        public func GetHeight() -> Int32 { decoded?.height ?? Int32(pixels?.height ?? 0) }

        public func GetBytesPerPixel() -> Int32 { decoded != nil ? 4 : Int32(pixels?.bytesPerPixel ?? 0) }

        /// The target size is ignored, as it is by the native bridge for raw
        /// pixels: the frame comes out at the size it went in.
        // WEB-TODO: a decoded image could be resized by createImageBitmap.
        public func InstantiateCodec(_ targetWidth: Int32, _ targetHeight: Int32)
            -> CodecBridge?
        {
            guard !disposed else { return nil }
            if let decoded { return CodecBridge(decoded: decoded) }
            guard let pixels else { return nil }
            return CodecBridge(pixels: pixels)
        }

        public func Dispose() {
            disposed = true
            pixels = nil
            encoded = nil
        }

        public func ToString(_ buffer: UnsafeMutablePointer<CChar>?, _ bufferSize: Int32) {
            let text: String
            if let pixels {
                text =
                    "ImageDescriptor(width: \(pixels.width), height: \(pixels.height), "
                    + "bytes per pixel: \(pixels.bytesPerPixel))"
            } else {
                text = "ImageDescriptor(width: ?, height: ?, bytes per pixel: ?)"
            }
            imageCopyCString(text, into: buffer, size: bufferSize)
        }
    }
}
