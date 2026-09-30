// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A small zip reader/writer over zlib — enough for Office Open XML
// packages (.docx/.xlsx/.pptx): stored and deflated entries, a central
// directory, no zip64, no encryption. Foundation has no zip of its own on
// Linux, and a document package is a handful of small XML parts.

import CZlib
import Foundation

struct ZipEntry {
    let name: String
    let data: Data
}

enum ZipError: Error {
    case notAZip
    case corrupt(String)
    case unsupported(String)
    case zlib(Int32)
}

enum Zip {
    // MARK: Reading

    static func read(_ archive: Data) throws -> [ZipEntry] {
        let bytes = [UInt8](archive)
        guard bytes.count >= 22 else { throw ZipError.notAZip }
        // End of central directory: scan back over a possible comment.
        var eocd = -1
        var i = bytes.count - 22
        let stop = max(0, bytes.count - 22 - 65535)
        while i >= stop {
            if bytes[i] == 0x50 && bytes[i + 1] == 0x4B && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06 {
                eocd = i
                break
            }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }
        let entryCount = Int(u16(bytes, eocd + 10))
        let cdOffset = Int(u32(bytes, eocd + 16))
        var entries: [ZipEntry] = []
        var p = cdOffset
        for _ in 0 ..< entryCount {
            guard p + 46 <= bytes.count, u32(bytes, p) == 0x02014B50 else { throw ZipError.corrupt("central directory") }
            let method = u16(bytes, p + 10)
            let csize = Int(u32(bytes, p + 20))
            let usize = Int(u32(bytes, p + 24))
            let nameLen = Int(u16(bytes, p + 28))
            let extraLen = Int(u16(bytes, p + 30))
            let commentLen = Int(u16(bytes, p + 32))
            let localOffset = Int(u32(bytes, p + 42))
            let name = String(decoding: bytes[(p + 46) ..< (p + 46 + nameLen)], as: UTF8.self)
            p += 46 + nameLen + extraLen + commentLen
            guard localOffset + 30 <= bytes.count, u32(bytes, localOffset) == 0x04034B50 else {
                throw ZipError.corrupt("local header for \(name)")
            }
            let lNameLen = Int(u16(bytes, localOffset + 26))
            let lExtraLen = Int(u16(bytes, localOffset + 28))
            let dataStart = localOffset + 30 + lNameLen + lExtraLen
            guard dataStart + csize <= bytes.count else { throw ZipError.corrupt("data for \(name)") }
            let raw = Data(bytes[dataStart ..< dataStart + csize])
            switch method {
            case 0: entries.append(ZipEntry(name: name, data: raw))
            case 8: entries.append(ZipEntry(name: name, data: try inflate(raw, expected: usize)))
            default: throw ZipError.unsupported("compression method \(method)")
            }
        }
        return entries
    }

    // MARK: Writing

    static func write(_ entries: [ZipEntry]) throws -> Data {
        var out = Data()
        var central = Data()
        let (dosTime, dosDate) = dosDateTime(Date())
        for entry in entries {
            let nameBytes = Array(entry.name.utf8)
            let crc = crc32(0, nil, 0)
            let checksum: UInt32 = entry.data.withUnsafeBytes { buf in
                guard let base = buf.baseAddress else { return UInt32(crc) }
                return UInt32(crc32(crc, base.assumingMemoryBound(to: Bytef.self), uInt(entry.data.count)))
            }
            // Deflate unless it does not help (tiny parts, already-compressed media).
            let deflated = try deflate(entry.data)
            let useDeflate = deflated.count < entry.data.count
            let payload = useDeflate ? deflated : entry.data
            let method: UInt16 = useDeflate ? 8 : 0
            let offset = UInt32(out.count)
            var local = Data()
            local.append(le32(0x04034B50))
            local.append(le16(20))
            local.append(le16(0x0800))          // UTF-8 names
            local.append(le16(method))
            local.append(le16(dosTime))
            local.append(le16(dosDate))
            local.append(le32(checksum))
            local.append(le32(UInt32(payload.count)))
            local.append(le32(UInt32(entry.data.count)))
            local.append(le16(UInt16(nameBytes.count)))
            local.append(le16(0))
            local.append(contentsOf: nameBytes)
            out.append(local)
            out.append(payload)

            var cd = Data()
            cd.append(le32(0x02014B50))
            cd.append(le16(20))
            cd.append(le16(20))
            cd.append(le16(0x0800))
            cd.append(le16(method))
            cd.append(le16(dosTime))
            cd.append(le16(dosDate))
            cd.append(le32(checksum))
            cd.append(le32(UInt32(payload.count)))
            cd.append(le32(UInt32(entry.data.count)))
            cd.append(le16(UInt16(nameBytes.count)))
            cd.append(le16(0))
            cd.append(le16(0))
            cd.append(le16(0))
            cd.append(le16(0))
            cd.append(le32(0))
            cd.append(le32(offset))
            cd.append(contentsOf: nameBytes)
            central.append(cd)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x06054B50))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(UInt16(entries.count)))
        out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(central.count)))
        out.append(le32(cdOffset))
        out.append(le16(0))
        return out
    }

    // MARK: zlib

    static func inflate(_ input: Data, expected: Int) throws -> Data {
        var strm = z_stream()
        var status = inflateInit2_(&strm, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw ZipError.zlib(status) }
        defer { inflateEnd(&strm) }
        var output = Data(count: max(expected, 64))
        var produced = 0
        try input.withUnsafeBytes { (inBuf: UnsafeRawBufferPointer) in
            strm.next_in = UnsafeMutablePointer(mutating: inBuf.baseAddress!.assumingMemoryBound(to: Bytef.self))
            strm.avail_in = uInt(input.count)
            repeat {
                if produced == output.count { output.count *= 2 }
                let chunk: Int32 = try output.withUnsafeMutableBytes { (outBuf: UnsafeMutableRawBufferPointer) in
                    strm.next_out = outBuf.baseAddress!.assumingMemoryBound(to: Bytef.self).advanced(by: produced)
                    strm.avail_out = uInt(outBuf.count - produced)
                    let before = strm.total_out
                    status = CZlib.inflate(&strm, Z_NO_FLUSH)
                    guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else {
                        throw ZipError.zlib(status)
                    }
                    return Int32(strm.total_out - before)
                }
                produced += Int(chunk)
            } while status != Z_STREAM_END && (strm.avail_in > 0 || produced == output.count)
        }
        output.count = produced
        return output
    }

    static func deflate(_ input: Data) throws -> Data {
        var strm = z_stream()
        var status = deflateInit2_(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY,
                                   ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw ZipError.zlib(status) }
        defer { deflateEnd(&strm) }
        let bound = Int(deflateBound(&strm, uLong(input.count)))
        var output = Data(count: bound + 16)
        var produced = 0
        try input.withUnsafeBytes { (inBuf: UnsafeRawBufferPointer) in
            strm.next_in = UnsafeMutablePointer(mutating: inBuf.baseAddress?.assumingMemoryBound(to: Bytef.self))
            strm.avail_in = uInt(input.count)
            try output.withUnsafeMutableBytes { (outBuf: UnsafeMutableRawBufferPointer) in
                strm.next_out = outBuf.baseAddress!.assumingMemoryBound(to: Bytef.self)
                strm.avail_out = uInt(outBuf.count)
                status = CZlib.deflate(&strm, Z_FINISH)
                guard status == Z_STREAM_END else { throw ZipError.zlib(status) }
                produced = Int(strm.total_out)
            }
        }
        output.count = produced
        return output
    }

    // MARK: Bytes

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
    }

    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }

    private static func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }

    private static func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)])
    }

    private static func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let hour = c.hour ?? 0
        let minute = c.minute ?? 0
        let second = (c.second ?? 0) / 2
        let time = (hour << 11) | (minute << 5) | second
        let year = max(1980, c.year ?? 1980) - 1980
        let month = c.month ?? 1
        let day = c.day ?? 1
        let dateValue = (year << 9) | (month << 5) | day
        return (UInt16(time), UInt16(dateValue))
    }
}
