// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A small zip reader/writer over zlib — enough for Office Open XML
// packages (.docx/.xlsx/.pptx): stored and deflated entries, a central
// directory, zip64 sizes when reading, no encryption. Foundation has no zip of its own on
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
        // No directory: a file cut short at its end. Salvage what the local
        // headers still describe, as PowerPoint and Word repair such files.
        guard eocd >= 0 else { return try _salvage(bytes) }
        var entryCount = Int(u16(bytes, eocd + 10))
        var cdOffset = Int(u32(bytes, eocd + 16))
        // A zip64 archive's own end record, which the locator just before
        // this one points to, when these fields are full.
        if entryCount == 0xFFFF || cdOffset == 0xFFFF_FFFF, eocd >= 20, u32(bytes, eocd - 20) == 0x07064B50 {
            let at = Int(u64(bytes, eocd - 12))
            if at >= 0, at + 56 <= bytes.count, u32(bytes, at) == 0x06064B50 {
                entryCount = Int(u64(bytes, at + 32))
                cdOffset = Int(u64(bytes, at + 48))
            }
        }
        var entries: [ZipEntry] = []
        var p = cdOffset
        for _ in 0 ..< entryCount {
            guard p + 46 <= bytes.count, u32(bytes, p) == 0x02014B50 else { throw ZipError.corrupt("central directory") }
            let method = u16(bytes, p + 10)
            var csize = Int(u32(bytes, p + 20))
            var usize = Int(u32(bytes, p + 24))
            let nameLen = Int(u16(bytes, p + 28))
            let extraLen = Int(u16(bytes, p + 30))
            let commentLen = Int(u16(bytes, p + 32))
            var localOffset = Int(u32(bytes, p + 42))
            guard p + 46 + nameLen + extraLen <= bytes.count else { throw ZipError.corrupt("central directory") }
            let name = String(decoding: bytes[(p + 46) ..< (p + 46 + nameLen)], as: UTF8.self)
            // Zip64: the sizes and offset that do not fit, in its extra
            // field, in that order (lo-tdf82984_zip64XLSXImport, written
            // that way for parts of a few hundred bytes).
            var e = p + 46 + nameLen
            while e + 4 <= p + 46 + nameLen + extraLen {
                let id = u16(bytes, e), len = Int(u16(bytes, e + 2))
                if id == 0x0001 {
                    var q = e + 4
                    func next() -> Int? {
                        guard q + 8 <= e + 4 + len else { return nil }
                        defer { q += 8 }
                        return Int(u64(bytes, q))
                    }
                    if usize == 0xFFFF_FFFF, let v = next() { usize = v }
                    if csize == 0xFFFF_FFFF, let v = next() { csize = v }
                    if localOffset == 0xFFFF_FFFF, let v = next() { localOffset = v }
                }
                e += 4 + len
            }
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

    /// The complete entries of an archive whose central directory is gone,
    /// read front to back from their local headers. An entry that is cut
    /// short, damaged or of a size only a trailing data descriptor gives is
    /// skipped, and the scan goes on at the next local header — as
    /// PowerPoint repairs such a file (the fuzzer's deck 4986… comes back
    /// as 23 slides, 5611…'s diagram as its four boxes; stopping at the
    /// first bad entry kept one slide, and none).
    private static func _salvage(_ bytes: [UInt8]) throws -> [ZipEntry] {
        var entries: [ZipEntry] = []
        var seen = Set<String>()
        func next(after q: Int) -> Int? {
            var i = max(0, q)
            while i + 4 <= bytes.count {
                if bytes[i] == 0x50, bytes[i + 1] == 0x4B, bytes[i + 2] == 0x03, bytes[i + 3] == 0x04 { return i }
                i += 1
            }
            return nil
        }
        var at = next(after: 0)
        while let p = at, p + 30 <= bytes.count {
            let flags = u16(bytes, p + 6)
            let method = u16(bytes, p + 8)
            var csize = Int(u32(bytes, p + 18))
            let usize = Int(u32(bytes, p + 22))
            let nameLen = Int(u16(bytes, p + 26))
            let extraLen = Int(u16(bytes, p + 28))
            let dataStart = p + 30 + nameLen + extraLen
            guard dataStart <= bytes.count else { break }
            // An entry cut short by the end of the file is lost.
            if flags & 0x8 == 0, csize > 0, dataStart + csize > bytes.count { break }
            // A size the header does not give: up to the next entry's header.
            if flags & 0x8 != 0 || csize == 0 {
                csize = (next(after: dataStart) ?? bytes.count) - dataStart
                if flags & 0x8 != 0, csize >= 16 { csize -= 16 }
            }
            let name = String(decoding: bytes[(p + 30) ..< (p + 30 + nameLen)], as: UTF8.self)
            let raw = Data(bytes[dataStart ..< min(bytes.count, dataStart + csize)])
            var data: Data? = nil
            switch method {
            case 0: data = raw
            // (A damaged header's size is not trusted to size the buffer.)
            case 8: data = try? inflate(raw, expected: min(usize, raw.count * 8 + 4096))
            default: break
            }
            if let data, !seen.contains(name) {
                entries.append(ZipEntry(name: name, data: data))
                seen.insert(name)
                at = next(after: dataStart + csize)
            } else {
                at = next(after: p + 4)
            }
        }
        guard !entries.isEmpty else { throw ZipError.notAZip }
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

    private static func u64(_ b: [UInt8], _ i: Int) -> UInt64 {
        UInt64(u32(b, i)) | UInt64(u32(b, i + 4)) << 32
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
