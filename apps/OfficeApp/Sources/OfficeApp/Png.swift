// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import CZlib
import Foundation

/// A damaged PNG made whole enough to decode, as PowerPoint decodes it:
/// chunk checksums that do not match are not held against the picture,
/// and image data whose zlib check fails is taken as far as it inflates.
/// crash-57308's rainbow footer has one IDAT with a bad CRC and a bad
/// Adler sum; PowerPoint draws it, and the image codec refused it.
enum Png {
    static func isPng(_ b: [UInt8]) -> Bool { b.count > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 }

    static func repaired(_ b: [UInt8]) -> [UInt8]? {
        guard isPng(b) else { return nil }
        func u32(_ o: Int) -> Int { Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3]) }
        func be(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        func chunk(_ type: [UInt8], _ data: [UInt8]) -> [UInt8] {
            let crc = (type + data).withUnsafeBufferPointer { UInt32(crc32(0, $0.baseAddress, uInt($0.count))) }
            return be(UInt32(data.count)) + type + data + be(crc)
        }
        var out = Array(b[0 ..< 8])
        var idat: [UInt8] = []
        var p = 8
        var wroteData = false
        while p + 12 <= b.count {
            let n = u32(p)
            guard n >= 0, p + 12 + n <= b.count else { break }
            let type = Array(b[p + 4 ..< p + 8]), data = Array(b[p + 8 ..< p + 8 + n])
            p += 12 + n
            if type == Array("IDAT".utf8) { idat += data; continue }
            if !idat.isEmpty, !wroteData {
                // The image data inflated raw (past the zlib header, with
                // no Adler check) and deflated afresh.
                guard idat.count > 2, let raw = try? Zip.inflate(Data(idat.dropFirst(2)), expected: idat.count * 8),
                      let packed = try? Zip.deflate(raw) else { return nil }
                let adler = raw.withUnsafeBytes { UInt32(adler32(1, $0.baseAddress?.assumingMemoryBound(to: Bytef.self), uInt(raw.count))) }
                out += chunk(Array("IDAT".utf8), [0x78, 0x9C] + [UInt8](packed) + be(adler))
                wroteData = true
            }
            out += chunk(type, data)
            if type == Array("IEND".utf8) { break }
        }
        return wroteData ? out : nil
    }
}
