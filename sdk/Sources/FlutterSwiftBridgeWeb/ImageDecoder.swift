// Encoded images, decoded by the browser.
//
// The skwasm build we ship has no image codecs (that is the heavy build,
// with ICU and codecs, 2 MB more). The browser has them all, so the page
// decodes — createImageBitmap — and hands skwasm the bitmap as a texture.
// Decoding is asynchronous there, which suits the framework: its image
// pipeline is `async` from `ImageDescriptor.encoded` down.
import CSkwasm

public struct WebDecodedImage {
    public let skImage: sk_ptr
    public let width: Int32
    public let height: Int32
}

public enum WebImageDecoder {
    nonisolated(unsafe) private static var pending: [UInt32: CheckedContinuation<WebDecodedImage?, Never>] = [:]
    nonisolated(unsafe) private static var nextId: UInt32 = 0

    /// nil when the browser could not decode the bytes.
    public static func decode(_ bytes: [UInt8]) async -> WebDecodedImage? {
        await withCheckedContinuation { continuation in
            nextId &+= 1
            let id = nextId
            pending[id] = continuation
            bytes.withUnsafeBufferPointer {
                starling_host_decode_image(id, $0.baseAddress, UInt32($0.count), WebSurface.handle)
            }
        }
    }

    /// Called by the host when the page calls `starling_image_decoded`.
    public static func complete(_ id: UInt32, skImage: sk_ptr, width: Int32, height: Int32) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(
            returning: skImage != 0
                ? WebDecodedImage(skImage: skImage, width: width, height: height) : nil)
    }
}
