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
}
