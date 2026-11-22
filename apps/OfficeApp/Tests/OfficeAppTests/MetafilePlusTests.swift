import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class MetafilePlusTests: XCTestCase {
    private func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)] }
    private func f32(_ v: Double) -> [UInt8] { le32(Int(Float(v).bitPattern)) }
    private func plus(_ type: Int, _ flags: Int, _ data: [UInt8]) -> [UInt8] {
        var d = data
        while d.count % 4 != 0 { d.append(0) }
        return [UInt8(type & 0xFF), UInt8(type >> 8), UInt8(flags & 0xFF), UInt8(flags >> 8)] + le32(12 + d.count) + le32(d.count) + d
    }
    private func comment(_ records: [UInt8]) -> [UInt8] {
        le32(70) + le32(16 + records.count) + le32(4 + records.count) + [0x45, 0x4D, 0x46, 0x2B] + records
    }
    private func header() -> [UInt8] {
        var h: [UInt8] = []
        for v in [1, 108, 0, 0, 99, 99, 0, 0, 2646, 2646] { h += le32(v) }
        h += [0x20, 0x45, 0x4D, 0x46]
        for v in [0x10000, 0, 0, 0, 0, 0, 0] { h += le32(v) }
        for v in [1024, 768, 271, 203] { h += le32(v) }
        return h + [UInt8](repeating: 0, count: 108 - h.count)
    }
    private func end() -> [UInt8] { le32(14) + le32(20) + le32(0) + le32(0) + le32(20) }
    /// The EMF fallback: a blue rectangle.
    private func fallback() -> [UInt8] {
        let ints = [1, 0, 0x00FF0000, 0]
        return le32(39) + le32(8 + ints.count * 4) + ints.flatMap(le32)
            + le32(37) + le32(12) + le32(1)
            + le32(37) + le32(12) + le32(Int(Int32(bitPattern: 0x8000_0008)))
            + le32(43) + le32(24) + [20, 40, 120, 140].flatMap(le32)
    }
    private func pathObject(id: Int) -> [UInt8] {
        let pts: [(Double, Double)] = [(10, 20), (60, 20), (60, 70), (10, 70)]
        var d = le32(0xDBC01002) + le32(4) + le32(0)
        for p in pts { d += f32(p.0) + f32(p.1) }
        d += [0, 1, 1, 0x81]
        return plus(0x4008, 0x300 | id, d)
    }
    private func build(dual: Bool, extra: [UInt8] = []) -> Data {
        let head = plus(0x4001, dual ? 1 : 0, le32(0xDBC01002) + le32(dual ? 1 : 0) + le32(96) + le32(96))
        let fill = plus(0x4014, 0x8000, le32(0xFFFF0000))   // FillPath, path 0, colour brush red
        return Data(header() + comment(head + pathObject(id: 0) + extra + fill) + fallback() + end())
    }

    func testADualFilePlaysItsPlusRecordsNotItsFallback() throws {
        let m = try XCTUnwrap(Metafile(build(dual: true), id: "p"))
        XCTAssertEqual(m.steps.count, 1, "\(m.steps)")
        guard case .fill(let path, let color) = m.steps[0] else { return XCTFail("a fill") }
        XCTAssertEqual(color, Color(0xFFFF0000), "the EMF+ brush, not the fallback's blue")
        XCTAssertEqual(path.getBounds(), Rect.fromLTRB(10, 20, 60, 70))
    }

    func testAFileThatIsNotDualPlaysItsEMFRecords() throws {
        let m = try XCTUnwrap(Metafile(build(dual: false), id: "p"))
        guard case .fill(_, let color) = m.steps.last else { return XCTFail("a fill") }
        XCTAssertEqual(color, Color(0xFF0000FF))
    }

    func testARecordItDoesNotPlayLeavesTheFileToItsFallback() throws {
        let drawString = plus(0x401C, 0x8000, [UInt8](repeating: 0, count: 28))
        let m = try XCTUnwrap(Metafile(build(dual: true, extra: drawString), id: "p"))
        guard case .fill(_, let color) = m.steps.last else { return XCTFail("a fill") }
        XCTAssertEqual(color, Color(0xFF0000FF))
    }

    func testFillRectsAndTheWorldTransform() throws {
        let head = plus(0x4001, 1, le32(0xDBC01002) + le32(1) + le32(96) + le32(96))
        let world = plus(0x402A, 0, f32(2) + f32(0) + f32(0) + f32(2) + f32(1) + f32(1))
        let rects = plus(0x400A, 0x8000, le32(0xFF00FF00) + le32(1) + f32(1) + f32(2) + f32(3) + f32(4))
        let m = try XCTUnwrap(Metafile(Data(header() + comment(head + world + rects) + fallback() + end()), id: "p"))
        XCTAssertEqual(m.steps.count, 1)
        guard case .fill(let path, let color) = m.steps[0] else { return XCTFail("a fill") }
        XCTAssertEqual(color, Color(0xFF00FF00))
        XCTAssertEqual(path.getBounds(), Rect.fromLTRB(3, 5, 9, 13), "x' = 2x + 1")
    }
}
