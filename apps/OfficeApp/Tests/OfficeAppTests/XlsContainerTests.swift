import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class XlsContainerTests: XCTestCase {
    private func rec(_ type: UInt16, _ body: [UInt8]) -> [UInt8] {
        [UInt8(type & 255), UInt8(type >> 8), UInt8(body.count & 255), UInt8(body.count >> 8)] + body
    }
    private func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255), UInt8(v >> 16 & 255), UInt8(v >> 24 & 255)] }

    private func boundsheet(_ name: String, kind: UInt8 = 0, hidden: UInt8 = 0) -> [UInt8] {
        rec(0x85, le32(0) + [hidden, kind, UInt8(name.utf8.count), 0] + Array(name.utf8))
    }

    /// A one-stream compound file (512-byte sectors, every stream in regular sectors).
    private func compound(stream name: String, _ content: [UInt8]) -> [UInt8] {
        precondition(content.count <= 512)
        var h = [UInt8](repeating: 0, count: 512)
        h.replaceSubrange(0 ..< 8, with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
        h[0x1E] = 9; h[0x20] = 6
        h.replaceSubrange(0x2C ..< 0x30, with: le32(1))
        h.replaceSubrange(0x30 ..< 0x34, with: le32(1))
        h.replaceSubrange(0x38 ..< 0x3C, with: le32(0))
        h.replaceSubrange(0x3C ..< 0x40, with: le32(0xFFFF_FFFE))
        h.replaceSubrange(0x44 ..< 0x48, with: le32(0xFFFF_FFFE))
        for k in 0 ..< 109 { h.replaceSubrange(0x4C + k * 4 ..< 0x50 + k * 4, with: le32(k == 0 ? 0 : 0xFFFF_FFFF)) }
        var fat = [UInt8](repeating: 0xFF, count: 512)
        fat.replaceSubrange(0 ..< 4, with: le32(0xFFFF_FFFD))
        fat.replaceSubrange(4 ..< 8, with: le32(0xFFFF_FFFE))
        fat.replaceSubrange(8 ..< 12, with: le32(0xFFFF_FFFE))
        func entry(_ n: String, type: UInt8, child: UInt32, start: UInt32, size: UInt32) -> [UInt8] {
            var e = [UInt8](repeating: 0, count: 128)
            let u = Array(n.utf16)
            for (i, c) in u.enumerated() { e[i * 2] = UInt8(c & 255); e[i * 2 + 1] = UInt8(c >> 8) }
            e[64] = UInt8((u.count + 1) * 2); e[66] = type
            e.replaceSubrange(68 ..< 72, with: le32(0xFFFF_FFFF))
            e.replaceSubrange(72 ..< 76, with: le32(0xFFFF_FFFF))
            e.replaceSubrange(76 ..< 80, with: le32(child))
            e.replaceSubrange(116 ..< 120, with: le32(start))
            e.replaceSubrange(120 ..< 124, with: le32(size))
            return e
        }
        var dir = entry("Root Entry", type: 5, child: 1, start: 0xFFFF_FFFE, size: 0)
        dir += entry(name, type: 2, child: 0xFFFF_FFFF, start: 2, size: UInt32(content.count))
        dir += [UInt8](repeating: 0, count: 256)
        return h + fat + dir + content + [UInt8](repeating: 0, count: 512 - content.count)
    }

    private var book: [UInt8] {
        rec(0x809, [UInt8](repeating: 0, count: 16)) + boundsheet("Alpha") + boundsheet("Beta", hidden: 1) + rec(0x0A, [])
    }

    func testAStreamIsFoundWhateverTheCaseOfItsName() throws {
        for name in ["Workbook", "WORKBOOK", "workbook"] {
            let f = try CompoundFile(compound(stream: name, book))
            XCTAssertEqual(f.stream("Workbook")?.count, book.count, name)
            XCTAssertNil(f.stream("Other"))
        }
    }

    func testTheSheetsComeBackInWorkbookOrderWithTheirHiddenState() throws {
        let f = try CompoundFile(compound(stream: "Workbook", book))
        let sh = Xls.sheets(BiffReader.records(try XCTUnwrap(Xls.workbookStream(f))))
        XCTAssertEqual(sh.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(sh.map(\.hidden), [0, 1])
    }

    func testAContinueRecordExtendsTheRecordBeforeItAndMarksWhereItBegins() {
        let s = rec(0xFC, [1, 2, 3]) + rec(0x3C, [4, 5]) + rec(0x3C, [6]) + rec(0x0A, [])
        let r = BiffReader.records(s)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].body, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(r[0].segments, [0, 3, 5])
    }

    func testTheOpenerReadsWhatAFileHoldsNotWhatItIsCalled() throws {
        let xls = Data(compound(stream: "Book", book))
        XCTAssertEqual(try Workbook.open(xls, name: "data.xlsx").sheets.map(\.name), ["Alpha", "Beta"])
        let csv = Data("a,b\n1,2\n".utf8)
        XCTAssertEqual(try Workbook.open(csv, name: "x.xls").sheets.count, 1)
    }

    func testATruncatedOrDamagedFileThrowsOrReadsLessButNeverTraps() {
        let good = compound(stream: "Workbook", book)
        for n in stride(from: 0, to: good.count, by: 7) {
            if let f = try? CompoundFile(Array(good[0 ..< n])) { _ = f.streamPaths; _ = f.stream("Workbook").map(BiffReader.records) }
        }
        var seed: UInt64 = 12345
        for _ in 0 ..< 400 {
            var bad = good
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            bad[Int(seed >> 33) % bad.count] ^= UInt8(truncatingIfNeeded: seed >> 20) | 1
            if let f = try? CompoundFile(bad) { _ = f.streamPaths; _ = f.stream("Workbook").map(BiffReader.records) }
        }
    }

    private func u16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255)] }

    /// A book with a string split across CONTINUE (1 byte per character, then 2), numbers in RK, MULRK and plain form, a boolean, an error and a merge.
    private func cat(_ parts: [UInt8]...) -> [UInt8] { parts.flatMap { $0 } }

    private func valuesBook() -> [UInt8] {
        func globals(_ sheetAt: Int) -> [UInt8] {
            let bof = rec(0x809, cat(u16(0x600), [UInt8](repeating: 0, count: 14)))
            let sstBody = cat(le32(2), le32(2), u16(2), [0, 0x61, 0x62], u16(4), [0, 0x63, 0x64])
            let sst = cat(rec(0xFC, sstBody), rec(0x3C, [1, 0x65, 0, 0x66, 0]))
            let sheet = rec(0x85, cat(le32(UInt32(sheetAt)), [0, 0, 1, 0, 0x53]))
            return cat(bof, sst, sheet, rec(0x0A, []))
        }
        let at = globals(0).count
        let bof = rec(0x809, cat(u16(0x600), [UInt8](repeating: 0, count: 14)))
        let bits = (2.5).bitPattern
        let lo = UInt32(bits & 0xFFFF_FFFF), hi = UInt32(bits >> 32)
        let a1 = rec(0xFD, cat(u16(0), u16(0), u16(0), le32(1)))
        let b1 = rec(0x27E, cat(u16(0), u16(1), u16(0), le32(314 << 2 | 3)))
        let row2 = rec(0xBD, cat(u16(1), u16(0), u16(0), le32(7 << 2 | 2), u16(0), le32(25 << 2 | 2), u16(1)))
        let a3 = rec(0x203, cat(u16(2), u16(0), u16(0), le32(lo), le32(hi)))
        let b3 = rec(0x205, cat(u16(2), u16(1), u16(0), [1, 0]))
        let c3 = rec(0x205, cat(u16(2), u16(2), u16(0), [0x07, 1]))
        let merge = rec(0xE5, cat(u16(1), u16(3), u16(4), u16(0), u16(1)))
        return cat(globals(at), bof, a1, b1, row2, a3, b3, c3, merge, rec(0x0A, []))
    }

    func testValuesComeThroughWhateverTheirRecordKind() throws {
        let wb = try Xls.read(Data(compound(stream: "Workbook", valuesBook())))
        let s = try XCTUnwrap(wb.sheets.first)
        XCTAssertEqual(s.name, "S")
        func v(_ r: Int, _ c: Int) -> CellValue? { s.cells[CellAddress(row: r, col: c)]?.value }
        XCTAssertEqual(v(0, 0), .text("cdef"))
        XCTAssertEqual(v(0, 1), .number(3.14))
        XCTAssertEqual(v(1, 0), .number(7))
        XCTAssertEqual(v(1, 1), .number(25))
        XCTAssertEqual(v(2, 0), .number(2.5))
        XCTAssertEqual(v(2, 1), .bool(true))
        XCTAssertEqual(s.merges, [CellRange(top: 3, left: 0, bottom: 4, right: 1)])
    }

    func testADamagedBookStillReadsOrThrowsNeverTraps() {
        let good = compound(stream: "Workbook", valuesBook())
        var seed: UInt64 = 99
        for _ in 0 ..< 600 {
            var bad = good
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            bad[512 + Int(seed >> 33) % 1024] ^= UInt8(truncatingIfNeeded: seed >> 20) | 1
            _ = try? Xls.read(Data(bad))
        }
    }
}
