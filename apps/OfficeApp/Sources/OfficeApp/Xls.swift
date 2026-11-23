// The legacy Excel .xls reader (BIFF8): a compound file whose "Workbook"
// stream is a run of records. M0: the records, the sheet list, and the one
// opener that sniffs what a file is. Later milestones turn the records into
// SpreadsheetML parts and run the xlsx reader on them.
//
// Shared code (also built for the web): no legacy Foundation calls.

import Foundation

/// A BIFF record: type, body, and where each CONTINUE segment of the body
/// starts (strings restart their flag byte at a segment boundary).
struct BiffRecord {
    var type: UInt16
    var body: [UInt8]
    var segments: [Int]   // body offsets where a segment begins; first is 0
    var offset: Int       // position of the record header in the stream
}

enum BiffReader {
    static let continueType: UInt16 = 0x3C

    /// Every record of `stream`, CONTINUE records folded into the record they
    /// extend. Stops at a truncated record or at padding (type 0 and length 0
    /// after the last EOF); never traps.
    static func records(_ s: [UInt8]) -> [BiffRecord] {
        var out: [BiffRecord] = []
        var i = 0
        while i + 4 <= s.count {
            let type = UInt16(s[i]) | UInt16(s[i + 1]) << 8
            let len = Int(UInt16(s[i + 2]) | UInt16(s[i + 3]) << 8)
            guard i + 4 + len <= s.count else { break }
            let body = Array(s[i + 4 ..< i + 4 + len])
            if type == continueType, !out.isEmpty {
                out[out.count - 1].segments.append(out[out.count - 1].body.count)
                out[out.count - 1].body += body
            } else if type == 0, len == 0 {
                i += 4
                continue
            } else {
                out.append(BiffRecord(type: type, body: body, segments: [0], offset: i))
            }
            i += 4 + len
        }
        return out
    }
}

enum Xls {
    enum ReadError: Error { case notAnXls, truncated }

    struct SheetInfo { var name: String; var kind: UInt8; var hidden: UInt8; var position: Int }

    /// The workbook stream of a compound file, found by name without regard to case
    /// ("Workbook", or "Book" in BIFF5).
    static func workbookStream(_ file: CompoundFile) -> [UInt8]? {
        file.stream("Workbook") ?? file.stream("Book")
    }

    /// The sheets listed by the BOUNDSHEET records, in workbook order.
    static func sheets(_ records: [BiffRecord]) -> [SheetInfo] {
        var out: [SheetInfo] = []
        for r in records where r.type == 0x85 && r.body.count >= 8 {
            let b = r.body
            let n = Int(b[6])
            var name = ""
            if b.count >= 8 {
                let wide = b[7] & 1 == 1
                if wide {
                    let end = min(b.count, 8 + n * 2)
                    var u: [UInt16] = []
                    var k = 8
                    while k + 2 <= end { u.append(UInt16(b[k]) | UInt16(b[k + 1]) << 8); k += 2 }
                    name = String(decoding: u, as: UTF16.self)
                } else {
                    name = String(decoding: b[8 ..< min(b.count, 8 + n)].map { UInt16($0) }, as: UTF16.self)
                }
            }
            out.append(SheetInfo(name: name, kind: b[5], hidden: b[4], position: Int(CompoundFile.u32(b, 0))))
        }
        return out
    }

    /// A readable listing: the streams, the record counts, the sheets.
    static func dump(_ bytes: [UInt8]) throws -> String {
        let file = try CompoundFile(bytes)
        var text = "streams: " + file.streamPaths.joined(separator: ", ") + "\n"
        guard let wb = workbookStream(file) else { throw ReadError.notAnXls }
        let recs = BiffReader.records(wb)
        var counts: [UInt16: Int] = [:]
        for r in recs { counts[r.type, default: 0] += 1 }
        text += "records: \(recs.count)\n"
        for t in counts.keys.sorted() { text += "  0x" + String(t, radix: 16) + ": \(counts[t]!)\n" }
        let sh = sheets(recs)
        text += "sheets: \(sh.count)\n"
        for s in sh { text += "  \(s.name) kind=\(s.kind) hidden=\(s.hidden)\n" }
        // STARLING_XLS_HEX=0x1b1 lists the bytes of every record of that type.
        if let h = ProcessInfo.processInfo.environment["STARLING_XLS_HEX"], let want = UInt16(h.dropFirst(2), radix: 16) {
            for r in recs where r.type == want {
                text += "rec 0x" + String(want, radix: 16) + ": " + r.body.map { String($0, radix: 16).count == 1 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined() + "\n"
            }
        }
        return text
    }

    /// The workbook of a BIFF8 file: its records turned into SpreadsheetML
    /// parts and read by the xlsx reader. A BIFF5 file gives its sheets empty (M7).
    static func read(_ data: Data) throws -> Workbook {
        let file = try CompoundFile([UInt8](data))
        guard let wb = workbookStream(file) else { throw ReadError.notAnXls }
        let recs = BiffReader.records(wb)
        if let parts = XlsBuild.parts(recs) { return try Xlsx.read(entries: parts) }
        let sh = sheets(recs)
        guard !sh.isEmpty else { throw ReadError.truncated }
        return Workbook(sheets: sh.map { Worksheet(name: $0.name) })
    }
}

extension Workbook {
    /// Open a file by what it holds, not by its extension: a compound file with
    /// a Workbook stream is an .xls, one with an EncryptedPackage is an
    /// encrypted package (the xlsx reader decrypts it), a zip is an .xlsx,
    /// anything else is text.
    static func open(_ data: Data, name: String) throws -> Workbook {
        let head = [UInt8](data.prefix(8))
        if data.count >= 512, head.elementsEqual([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) {
            if let file = try? CompoundFile([UInt8](data)), Xls.workbookStream(file) != nil { return try Xls.read(data) }
            return try Xlsx.read(data)
        }
        if head.count >= 2, head[0] == 0x50, head[1] == 0x4B { return try Xlsx.read(data) }
        return Csv.read(String(decoding: data, as: UTF8.self), name: name.deletingPathExtension)
    }
}
