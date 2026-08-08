// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CNvencEncoder

#if os(Linux)
import Glibc
#endif

/// The zero-copy session interface RecordingService drives: VaapiEncoder
/// and NvencEncoder are interchangeable behind it, same threading contract
/// (all methods synchronous, one dedicated serial queue, one session at a
/// time), same failure semantics (encode false = session dead + errorOutput
/// set; finish false leaves the handle alive for abort).
public protocol InProcessEncoder: AnyObject {
    var width: Int { get }
    var height: Int { get }
    var outputURL: URL { get }
    var frameCount: Int { get }
    var errorOutput: String { get }
    @discardableResult
    func encode(fd: Int32, stride: UInt32, offset: UInt32,
                fourcc: UInt32, modifier: UInt64,
                timestampUs: UInt64) -> Bool
    @discardableResult
    func finish() -> Bool
    func abort()
}

extension VaapiEncoder: InProcessEncoder {}

/// The NVIDIA sibling of VaapiEncoder: engine-ring dma-buf frames encoded
/// through NVENC (libnvidia-encode called directly, no ffmpeg child) and
/// muxed by the same in-process MP4 writer. Zero-copy like its sibling —
/// the dma-buf imports into CUDA and registers with NVENC — which is
/// exactly why its frames must be NVIDIA-resident: recording is per-screen
/// and a screen's shell is encoded by the GPU that renders it. Frames from
/// another GPU fail the import; there is deliberately no copy fallback.
public final class NvencEncoder {

    public let width: Int    // output dims (even — 4:2:0)
    public let height: Int
    public let fps: Int
    public let outputURL: URL
    public var frameCount: Int { Int(nvenc_encoder_frame_count(handle)) }
    public private(set) var errorOutput = ""

    private var handle: OpaquePointer?

    /// True when NVENC can actually open a session (driver present, CUDA
    /// device visible, throwaway session initializes). A real probe — run
    /// off the main thread and cache. `STARLING_NO_ZEROCOPY` keeps its
    /// meaning; `STARLING_NO_NVENC` is the dedicated kill switch.
    public static func available(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if environment["STARLING_NO_NVENC"] == "1" { return false }
        if environment["STARLING_NO_ZEROCOPY"] == "1" { return false }
        return nvenc_encoder_probe() == 1
    }

    /// Open a session. Same dimension contract as VaapiEncoder: input dims
    /// are the engine ring's (may be odd), output dims must be even.
    public init?(inWidth: Int, inHeight: Int,
                 width: Int, height: Int, fps: Int, qp: Int = 24,
                 outputURL: URL) {
        self.width = width
        self.height = height
        self.fps = fps
        self.outputURL = outputURL
        try? FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        handle = nvenc_encoder_open(Int32(inWidth), Int32(inHeight),
                                    Int32(width), Int32(height),
                                    Int32(fps), Int32(qp),
                                    outputURL.path)
        if handle == nil { return nil }
    }

    /// Encode one dmabuf frame. The fd is borrowed only for the call.
    /// False means the session is dead — stop and report.
    @discardableResult
    public func encode(fd: Int32, stride: UInt32, offset: UInt32,
                       fourcc: UInt32, modifier: UInt64,
                       timestampUs: UInt64) -> Bool {
        guard let h = handle else { return false }
        let rc = nvenc_encoder_encode(h, fd, stride, offset, fourcc,
                                      modifier, timestampUs)
        if rc != 0 { errorOutput = String(cString: nvenc_encoder_error(h)) }
        return rc == 0
    }

    /// Flush and finalize the MP4. True when the file is complete; on
    /// failure `errorOutput` carries the reason and the handle survives
    /// for `abort` (which deletes the partial file).
    @discardableResult
    public func finish() -> Bool {
        guard let h = handle else { return false }
        if nvenc_encoder_finish(h) == 0 {
            handle = nil
            return true
        }
        errorOutput = String(cString: nvenc_encoder_error(h))
        return false
    }

    /// Kill the session and delete the partial file.
    public func abort() {
        guard let h = handle else { return }
        nvenc_encoder_abort(h)
        handle = nil
    }

    deinit {
        if let h = handle { nvenc_encoder_abort(h) }
    }
}

extension NvencEncoder: InProcessEncoder {}
