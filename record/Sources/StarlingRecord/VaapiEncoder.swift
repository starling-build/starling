// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CVaapiEncoder

#if os(Linux)
import Glibc
#endif

/// The zero-copy sibling of FfmpegEncoder: dmabuf frames from the engine's
/// capture ring go straight into VA-API (import → GPU convert/scale → GPU
/// encode → MP4), so recording costs the CPU only the compressed bitstream.
/// No libav anywhere — the C side links libva directly and writes its own
/// H.264 parameter sets and MP4 index. On a machine whose driver cannot do
/// the encode, `probe`/`detectDevice` fail and the caller stays on the pipe
/// path, which spawns the `ffmpeg` binary.
///
/// Same threading contract as FfmpegEncoder: all methods synchronous, none
/// main-thread-appropriate — use a dedicated queue, one session at a time.
public final class VaapiEncoder {

    public let width: Int    // output dims (even — 4:2:0)
    public let height: Int
    public let fps: Int
    public let outputURL: URL
    public var frameCount: Int { Int(vaapi_encoder_frame_count(handle)) }
    public private(set) var errorOutput = ""

    private var handle: OpaquePointer?

    /// The render node on the card the compositor scans out from, matched
    /// through the sysfs device links — the same walk
    /// `find_render_node_devid()` does in wayland_dmabuf.c. Nil when there is
    /// no confident match (no FLUTTER_DRM_DEVICE, or nothing pairs with it).
    ///
    /// Node NUMBER means nothing: on this two-GPU laptop renderD128 is the
    /// discrete NVIDIA and renderD129 is the AMD the panels hang off.
    public static func compositorRenderNode(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        let fm = FileManager.default
        guard let card = environment["FLUTTER_DRM_DEVICE"],
              let name = card.split(separator: "/").last,
              let cardLink = try? fm.destinationOfSymbolicLink(
                  atPath: "/sys/class/drm/\(name)/device")
        else { return nil }
        for i in 128 ..< 136 {
            let dev = "/dev/dri/renderD\(i)"
            guard fm.fileExists(atPath: dev) else { continue }
            let link = try? fm.destinationOfSymbolicLink(
                atPath: "/sys/class/drm/renderD\(i)/device")
            if link == cardLink { return dev }
        }
        return nil
    }

    /// The render node with a working in-process encode path, or nil.
    /// A real driver probe (~tens of ms) — run off the main thread and
    /// cache. Honors the pipe path's STARLING_NO_VAAPI kill switch, plus
    /// STARLING_NO_ZEROCOPY to force the pipe path while keeping VAAPI.
    ///
    /// The node must be the COMPOSITOR'S, not merely one that can encode.
    /// Zero-copy hands the encoder the scanout dma-buf, and that buffer
    /// lives on the card driving the displays; a second GPU cannot import
    /// it, so encoding "somewhere that supports H.264" is answering the
    /// wrong question. This used to scan /dev/dri in name order and take the
    /// first node that probed, which is only correct by luck: it works here
    /// because the discrete NVIDIA sorts first AND offers no VA-API encode,
    /// so it self-rejects. Put two encode-capable GPUs in one machine — an
    /// AMD dGPU beside an AMD iGPU, an Intel iGPU beside anything — and the
    /// scan happily selects the card with none of the frames on it.
    ///
    /// So: an explicit device wins, then the compositor's own node, and a
    /// probe failure there returns nil rather than shopping for another GPU
    /// — the pipe encoder is the correct fallback, not the wrong card.
    /// Only when the compositor's node cannot be identified at all (no
    /// FLUTTER_DRM_DEVICE, as under the unit tests) does the old scan run.
    public static func detectDevice(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if environment["STARLING_NO_VAAPI"] == "1" { return nil }
        if environment["STARLING_NO_ZEROCOPY"] == "1" { return nil }
        if let dev = environment["STARLING_VAAPI_DEVICE"], !dev.isEmpty {
            return vaapi_encoder_probe(dev) == 1 ? dev : nil
        }
        if let node = compositorRenderNode(environment: environment) {
            return vaapi_encoder_probe(node) == 1 ? node : nil
        }
        let devices = ((try? FileManager.default
            .contentsOfDirectory(atPath: "/dev/dri")) ?? [])
            .filter { $0.hasPrefix("renderD") }.sorted()
            .map { "/dev/dri/" + $0 }
        return devices.first { vaapi_encoder_probe($0) == 1 }
    }

    /// Open a session. Input dims are the engine ring's (may be odd);
    /// output dims must be even — the GPU scales the one-pixel difference
    /// away, the same crop the pipe path does with a filter.
    public init?(device: String, inWidth: Int, inHeight: Int,
                 width: Int, height: Int, fps: Int, qp: Int = 24,
                 outputURL: URL) {
        self.width = width
        self.height = height
        self.fps = fps
        self.outputURL = outputURL
        try? FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        handle = vaapi_encoder_open(device,
                                    Int32(inWidth), Int32(inHeight),
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
        let rc = vaapi_encoder_encode(h, fd, stride, offset, fourcc,
                                      modifier, timestampUs)
        if rc != 0 { errorOutput = String(cString: vaapi_encoder_error(h)) }
        return rc == 0
    }

    /// Flush and finalize the MP4. True when the file is complete; on
    /// failure `errorOutput` carries the reason and the handle survives
    /// for `abort` (which deletes the partial file).
    @discardableResult
    public func finish() -> Bool {
        guard let h = handle else { return false }
        if vaapi_encoder_finish(h) == 0 {
            handle = nil
            return true
        }
        errorOutput = String(cString: vaapi_encoder_error(h))
        return false
    }

    /// Kill the session and delete the partial file.
    public func abort() {
        guard let h = handle else { return }
        vaapi_encoder_abort(h)
        handle = nil
    }

    deinit {
        if let h = handle { vaapi_encoder_abort(h) }
    }
}
