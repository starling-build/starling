// ImmutableBufferBridge: read-only bytes handed to the engine.
import CSkwasm

extension flutter.swift_bridge {
    /// The native class wraps an SkData. Here the bytes stay in OUR memory,
    /// in a Swift array, and are copied into skwasm only when something there
    /// has to read them (`makeSkData`). Most buffers never make that trip:
    /// an encoded image, for one, is decoded by the browser, not by skwasm.
    public final class ImmutableBufferBridge {
        /// The contents. Empty once disposed.
        public private(set) var bytes: [UInt8]
        private var disposed = false

        public init(_ data: UnsafePointer<UInt8>?, _ length: Int) {
            if let data, length > 0 {
                bytes = Array(UnsafeBufferPointer(start: data, count: length))
            } else {
                bytes = []
            }
        }

        public init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        /// Always empty, which the caller reports as "asset not found".
        // WEB-TODO: there is no asset bundle to open synchronously. Assets
        // will be fetched by the page; this needs either a preloaded table
        // (the page fetches every asset in the manifest before start and
        // hands each one over, so this becomes a dictionary lookup) or an
        // async ImmutableBuffer.fromAsset in the framework.
        public static func CreateFromAsset(_ assetKey: UnsafePointer<CChar>?)
            -> ImmutableBufferBridge
        {
            ImmutableBufferBridge(bytes: [])
        }

        /// Always empty, which the caller reports as "file not found".
        // WEB-TODO: a browser has no filesystem. Nothing to implement unless
        // paths are given a meaning (a URL to fetch, an OPFS entry).
        public static func CreateFromFile(_ filePath: UnsafePointer<CChar>?)
            -> ImmutableBufferBridge
        {
            ImmutableBufferBridge(bytes: [])
        }

        public func Length() -> Int { bytes.count }

        public func Dispose() {
            bytes = []
            disposed = true
        }

        public func IsDisposed() -> Bool { disposed }

        /// A new SkData holding a copy of the bytes, or 0 if there are none.
        /// The caller owns it and releases it with `skData_dispose`.
        public func makeSkData() -> sk_ptr {
            imageMakeSkData(from: bytes)
        }
    }
}

/// Copies `bytes` into a new SkData. The caller owns the result.
func imageMakeSkData(from bytes: [UInt8]) -> sk_ptr {
    guard !bytes.isEmpty else { return 0 }
    let data = skData_create(UInt32(bytes.count))
    guard data != 0 else { return 0 }
    bytes.withUnsafeBufferPointer {
        skWrite(skData_getPointer(data), $0.baseAddress, count: $0.count)
    }
    return data
}
