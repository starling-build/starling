// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import CZlib
import Foundation
import OfficeText
import Flutter
import FlutterSwiftBridge

/// The frame a sound or movie shows at rest until a real frame is taken from
/// the file: a dark box with a play triangle (movie) or a speaker (sound).
/// Drawn into an RGBA bitmap and written as a PNG, with no image codec.
enum MediaPoster {
    static func png(video: Bool) -> Data {
        let w = video ? 640 : 96, h = video ? 360 : 96
        var px = [UInt8](repeating: 0, count: w * h * 4)
        func set(_ x: Int, _ y: Int, _ v: UInt8) {
            let o = (y * w + x) * 4
            px[o] = v; px[o + 1] = v; px[o + 2] = v; px[o + 3] = 255
        }
        let cx = Double(w) / 2, cy = Double(h) / 2, r = Double(min(w, h)) * (video ? 0.18 : 0.3)
        for y in 0 ..< h {
            for x in 0 ..< w {
                let dx = Double(x) - cx, dy = Double(y) - cy
                var on = false
                if video {
                    // Right-pointing triangle: its left edge at -0.5 r, its tip at 0.7 r.
                    on = dx >= -r * 0.5 && dx <= r * 0.7 && abs(dy) <= (r * 0.7 - dx) / (r * 1.2) * r
                } else {
                    // Speaker: a box, a cone opening to the right, two arcs.
                    let box = dx >= -r && dx <= -r * 0.3 && abs(dy) <= r * 0.35
                    let cone = dx > -r * 0.3 && dx <= r * 0.4 && abs(dy) <= r * 0.35 + (dx + r * 0.3) * 0.9
                    let d = (dx * dx + dy * dy).squareRoot()
                    let arc = dx > r * 0.5 && ((d >= r * 0.95 && d <= r * 1.1) || (d >= r * 1.35 && d <= r * 1.5))
                    on = box || cone || arc
                }
                set(x, y, on ? 235 : 38)
            }
        }
        return encode(px, width: w, height: h)
    }

    /// RGBA pixels as a PNG.
    static func encode(_ px: [UInt8], width w: Int, height h: Int) -> Data {
        var raw = Data()
        for y in 0 ..< h { raw.append(0); raw.append(contentsOf: px[(y * w * 4) ..< ((y + 1) * w * 4)]) }
        let packed = (try? Zip.deflate(raw)) ?? Data()
        let adler = raw.withUnsafeBytes { UInt32(adler32(1, $0.baseAddress?.assumingMemoryBound(to: Bytef.self), uInt(raw.count))) }
        func be(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
            let t = Array(type.utf8)
            let crc = (t + data).withUnsafeBufferPointer { UInt32(crc32(0, $0.baseAddress, uInt($0.count))) }
            return be(UInt32(data.count)) + t + data + be(crc)
        }
        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        out += chunk("IHDR", be(UInt32(w)) + be(UInt32(h)) + [8, 6, 0, 0, 0])
        out += chunk("IDAT", [0x78, 0x9C] + [UInt8](packed) + be(adler))
        out += chunk("IEND", [])
        return Data(out)
    }

    /// The poster as an attachment, at the size it is drawn on a slide.
    static func attachment(video: Bool, name: String) -> (ImageAttachment, Size) {
        let size = video ? Size(480, 270) : Size(72, 72)
        return (ImageAttachment(data: png(video: video), width: size.width, height: size.height, name: name,
                                naturalWidth: size.width, naturalHeight: size.height), size)
    }

    /// A real first frame from a movie file: opens it, plays until a frame arrives (about three seconds at most),
    /// stops. Blocks while it waits, so call it off the UI thread. Nil where nothing can decode the clip.
    static func firstFrame(of clip: MediaClip) -> (png: Data, width: Int, height: Int)? {
        #if os(WASI)
        return nil
        #else
        guard clip.isVideo else { return nil }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("poster-\(UUID().uuidString).\(clip.fileExtension)")
        guard (try? clip.data.write(to: file)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        guard let f = mediaFirstFrame(url: file.absoluteString), f.width > 0, f.pixels.count >= f.width * f.height * 4 else { return nil }
        return (encode(Array(f.pixels.prefix(f.width * f.height * 4)), width: f.width, height: f.height), f.width, f.height)
        #endif
    }
}
