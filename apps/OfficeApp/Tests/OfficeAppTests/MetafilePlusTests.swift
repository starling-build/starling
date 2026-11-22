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
        XCTAssertEqual(path.getBounds(), Rect.fromLTRB(9.5, 19.5, 59.5, 69.5))
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
        XCTAssertEqual(path.getBounds(), Rect.fromLTRB(2.5, 4.5, 8.5, 12.5), "x' = 2x + 1, less the half unit")
    }

    func testADrawnCompressedImageIsAStepAtItsCorners() throws {
        func i16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        let head = plus(0x4001, 1, le32(0xDBC01002) + le32(1) + le32(96) + le32(96))
        // A bitmap object (id 1): version, type 1, width, height, stride, format 0, data type 1, then the file's bytes.
        var body: [UInt8] = []
        for v in [0xDBC01002, 1, 0, 0, 0, 0, 1] { body += le32(v) }
        body += [1, 2, 3, 4]
        let object = plus(0x4008, 0x0501, body)
        // DrawImagePoints, compressed points: attributes, pixel unit, source rect, 3 points (0,0) (50,0) (0,20).
        var d: [UInt8] = le32(0) + le32(2)
        for v in [0.0, 0.0, 10.0, 4.0] { d += f32(v) }
        d += le32(3)
        for v in [0, 0, 50, 0, 0, 20] { d += i16(v) }
        let draw = plus(0x401B, 0x4001, d)
        let m = try XCTUnwrap(Metafile(Data(header() + comment(head + object + draw) + fallback() + end()), id: "p"))
        XCTAssertEqual(m.steps.count, 1)
        guard case .image(let index, let source, let at, _) = m.steps[0] else { return XCTFail("an image") }
        XCTAssertEqual(m.bitmaps[index].data, Data([1, 2, 3, 4]))
        XCTAssertEqual(at, Rect.fromLTRB(-0.5, -0.5, 49.5, 19.5))
        XCTAssertEqual(source, Rect.fromLTWH(0.5, 0.5, 10, 4))
    }

    func testAnImageObjectSplitOverTwoRecordsIsJoined() throws {
        let head = plus(0x4001, 1, le32(0xDBC01002) + le32(1) + le32(96) + le32(96))
        var body: [UInt8] = []
        for v in [0xDBC01002, 1, 0, 0, 0, 0, 1] { body += le32(v) }
        body += [1, 2, 3, 4, 5, 6, 7, 8]
        let cut = 32
        let first = plus(0x4008, 0x8501, le32(body.count) + Array(body[..<cut]))
        let second = plus(0x4008, 0x8501, le32(body.count) + Array(body[cut...]))
        var d: [UInt8] = le32(0) + le32(2)
        for v in [0.0, 0.0, 10.0, 4.0] { d += f32(v) }
        d += le32(3)
        for v in [0.0, 0.0, 50.0, 0.0, 0.0, 20.0] { d += f32(v) }
        let draw = plus(0x401B, 0x0001, d)
        let m = try XCTUnwrap(Metafile(Data(header() + comment(head + first + second + draw) + fallback() + end()), id: "p"))
        guard case .image(let index, _, _, _) = m.steps.first else { return XCTFail("an image: \(m.steps)") }
        XCTAssertEqual(m.bitmaps[index].data, Data([1, 2, 3, 4, 5, 6, 7, 8]))
    }

    func testAPenWithACustomEndCapIsReadAndDrawsTheCap() throws {
        var cap: [UInt8] = []
        for v in [0xDBC01002, 0, 2, 2] { cap += le32(v) }                 // version, default, line path, base cap
        cap += f32(1); cap += le32(2) + le32(2) + le32(0) + f32(10) + f32(1)   // inset, caps, join, miter, width scale
        cap += f32(0) + f32(0) + f32(0) + f32(0)                           // hot spots
        var path = le32(0xDBC01002) + le32(3) + le32(0x2000)
        for p in [(1.75, -4.0), (0.0, -1.0), (-1.75, -4.0)] { path += f32(p.0) + f32(p.1) }
        path += [0, 1, 1, 0]
        cap += le32(path.count) + path
        var b: [UInt8] = []
        for v in [0xDBC01002, 0, 0x1004, 2] { b += le32(v) }
        b += f32(2) + le32(255) + le32(cap.count) + cap
        for v in [0xDBC01002, 0, 0xFF000000] { b += le32(v) }
        let pen = try XCTUnwrap(EmfPlus.readPen(b, 0, b.count))
        XCTAssertTrue(pen.plain)
        let c = try XCTUnwrap(pen.endCap)
        XCTAssertEqual(c.path.points.count, 3)
        XCTAssertFalse(c.fill)
    }

    func testADashedPenIsReadAndCutIntoDashes() throws {
        var b: [UInt8] = []
        for v in [0xDBC01002, 0, 0x20, 2] { b += le32(v) }       // version, type, flags (line style), unit pixel
        b += f32(2); b += le32(1)                                  // width 2, style dash
        for v in [0xDBC01002, 0, 0xFF000000] { b += le32(v) }      // the brush: solid black
        let pen = try XCTUnwrap(EmfPlus.readPen(b, 0, b.count))
        XCTAssertEqual(pen.dash ?? [], [3, 1])
        XCTAssertTrue(pen.plain)
        let line = Path(); line.moveTo(0, 0); line.lineTo(100, 0)
        let dashed = EmfPlus.dashed(line, [3, 1], 2, 0)
        XCTAssertEqual(Array(dashed.computeMetrics()).count, 13, "6 on, 2 off over 100 units: 12 whole dashes and a 4 long one")
    }

    func testALinearGradientBrushIsReadWithItsPresetColours() throws {
        var b: [UInt8] = []
        for v in [0xDBC01002, 4, 0x4, 0] { b += le32(v) }          // version, linear, preset colours, wrap mode
        for v in [10.0, 20.0, 100.0, 50.0] { b += f32(v) }         // rectangle
        for v in [0xFFFF0000, 0xFF0000FF, 0, 0] { b += le32(v) }   // start, end, reserved
        b += le32(3)
        for v in [0.0, 0.5, 1.0] { b += f32(v) }
        for v in [0xFFFF0000, 0xFF00FF00, 0xFF0000FF] { b += le32(v) }
        let g = try XCTUnwrap(EmfPlus.readLinear(b, 0, b.count))
        XCTAssertEqual(g.stops, [0, 0.5, 1])
        XCTAssertEqual(g.colors[1], Color(0xFF00FF00))
        XCTAssertEqual(g.rect, Rect.fromLTWH(10, 20, 100, 50))
        b[8] = 0x8   // blend factors: not drawn
        XCTAssertNil(EmfPlus.readLinear(b, 0, b.count))
    }

    func testAPathGradientBrushShadesFromItsCentreToItsBoundary() throws {
        var b: [UInt8] = []
        for v in [0xDBC01002, 3, 1, 4, 0xFFF0F0F0] { b += le32(v) }   // version, path gradient, boundary path, wrap, centre colour
        b += f32(30) + f32(40) + le32(1) + le32(0xFF303030)             // centre point, one surround colour
        var path = le32(0xDBC01002) + le32(4) + le32(0)
        for p in [(10.0, 20.0), (50, 20), (50, 60), (10, 60)] { path += f32(p.0) + f32(p.1) }
        path += [0, 1, 1, 0x81]
        b += le32(path.count) + path
        let g = try XCTUnwrap(EmfPlus.readPathGradient(b, 0, b.count))
        XCTAssertEqual(g.center, Offset(30, 40))
        XCTAssertEqual(g.surroundARGB, 0xFF303030)
        XCTAssertEqual(g.boundary.points.count, 4)
        var two = b; two[8] = 0x4   // preset colours: not played
        XCTAssertNil(EmfPlus.readPathGradient(two, 0, two.count))
    }

    func testAFillWithAPathGradientIsBandsOfTheBoundaryScaledAboutTheCentre() throws {
        var brush: [UInt8] = []
        for v in [0xDBC01002, 3, 1, 4, 0xFFFFFFFF] { brush += le32(v) }
        brush += f32(30) + f32(40) + le32(1) + le32(0xFF000000)
        var path = le32(0xDBC01002) + le32(4) + le32(0)
        for p in [(10.0, 20.0), (50, 20), (50, 60), (10, 60)] { path += f32(p.0) + f32(p.1) }
        path += [0, 1, 1, 0x81]
        brush += le32(path.count) + path
        let head = plus(0x4001, 1, le32(0xDBC01002) + le32(1) + le32(96) + le32(96))
        let fillRect = plus(0x400A, 0x0001, le32(1) + le32(1) + f32(10) + f32(20) + f32(40) + f32(40))
        let m = try XCTUnwrap(Metafile(Data(header() + comment(head + plus(0x4008, 0x0101, brush) + fillRect) + fallback() + end()), id: "p"))
        XCTAssertGreaterThan(m.steps.count, 8, "one surround fill and a band per colour step")
        guard case .fill(_, let first) = m.steps[0], case .fill(_, let last) = m.steps[m.steps.count - 1] else { return XCTFail("fills") }
        XCTAssertEqual(first, Color(0xFF000000), "the surround colour first")
        XCTAssertGreaterThan(last.r, 0.9, "the centre is nearly white")
    }

    func testAHatchBrushIsTheTiledCellPowerPointPrints() throws {
        var b: [UInt8] = []
        for v in [0xDBC01002, 1, 0, 0xFF000000, 0xFFFFFFFF] { b += le32(v) }   // horizontal: black lines on white
        guard case .hatch(let h)? = EmfPlus.readHatch(b, 0, b.count) else { return XCTFail("a hatch") }
        XCTAssertEqual(h.fore, Color(0xFF000000))
        let lines = EmfPlus.hatchLines(h, Rect.fromLTRB(0, 0, 20, 20))
        XCTAssertEqual(Array(lines.computeMetrics()).count, 2, "tile rows 0 and 8: 0 and 10.67 device pixels, 8 tile pixels of 4/3 apart")
        XCTAssertEqual(lines.getBounds().bottom, 10.6667 + 1.3333, accuracy: 0.001, "a row is one tile pixel (4/3) high")
        b[8] = 16   // 80 percent: 60 of the 64 cells
        guard case .hatch(let dense)? = EmfPlus.readHatch(b, 0, b.count) else { return XCTFail("80 percent") }
        XCTAssertEqual(dense.bits.nonzeroBitCount, 60)
        b[8] = 53   // a style GDI+ does not have
        XCTAssertNil(EmfPlus.readHatch(b, 0, b.count))
        b[8] = 0; b.replaceSubrange(16..<20, with: le32(0xFF000000))   // the same colour twice: solid
        guard case .brush(let c)? = EmfPlus.readHatch(b, 0, b.count) else { return XCTFail("solid") }
        XCTAssertEqual(c, Color(0xFF000000))
    }

    func testABrushItDoesNotPlayLeavesTheFileToItsFallbackOnlyWhenAFillNamesIt() throws {
        var hatch: [UInt8] = []
        for v in [0xDBC01002, 1, 53, 0xFF000000, 0xFFFFFFFF] { hatch += le32(v) }   // style 53: not played
        let object = plus(0x4008, 0x0101, hatch)
        let head = plus(0x4001, 1, le32(0xDBC01002) + le32(1) + le32(96) + le32(96))
        let unused = try XCTUnwrap(Metafile(build(dual: true, extra: object), id: "p"))
        guard case .fill(_, let c) = unused.steps[0] else { return XCTFail("a fill") }
        XCTAssertEqual(c, Color(0xFFFF0000), "the file is played: nothing fills with the hatch")
        let used = plus(0x4014, 0x0000, le32(1))   // FillPath, path 0, brush object 1
        let m = try XCTUnwrap(Metafile(Data(header() + comment(head + pathObject(id: 0) + object + used) + fallback() + end()), id: "p"))
        guard case .fill(_, let color) = m.steps.last else { return XCTFail("a fill") }
        XCTAssertEqual(color, Color(0xFF0000FF), "a fill with it leaves the file to its EMF fallback")
    }

    private func w16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
    private func wmfRecord(_ fn: Int, _ params: [Int]) -> [UInt8] { le32((6 + params.count * 2) / 2) + w16(fn) + params.flatMap(w16) }

    func testAWMFSelectClipRegionLiftsAnEmptyClipAndAnArcIsDrawn() throws {
        var b: [UInt8] = w16(1) + w16(9) + w16(0x300) + le32(0) + w16(0) + le32(0) + w16(0)
        b += wmfRecord(0x020B, [0, 0]) + wmfRecord(0x020C, [100, 100])
        b += wmfRecord(0x02FA, [0, 1, 0, 0, 0]) + wmfRecord(0x012D, [0])
        b += wmfRecord(0x0416, [0, 0, 0, 0]) + wmfRecord(0x012C, [0]) + wmfRecord(0x0416, [100, 100, 0, 0])
        // Arc, last argument first: yEnd, xEnd, yStart, xStart, bottom, right, top, left: from the right to the top.
        b += wmfRecord(0x0817, [0, 50, 50, 100, 100, 100, 0, 0])
        b += wmfRecord(0, [])
        let m = try XCTUnwrap(Metafile(Data(b), id: "w"))
        guard case .clip(let clip) = m.steps.last(where: { if case .clip = $0 { return true } else { return false } }) else { return XCTFail("a clip") }
        XCTAssertEqual(clip?.getBounds(), Rect.fromLTRB(0, 0, 100, 100), "the empty clip was lifted before the real one")
        guard case .stroke(let path, _, _, _) = m.steps.last else { return XCTFail("a stroke: \(m.steps)") }
        let box = path.getBounds()
        XCTAssertEqual(box.right, 100, accuracy: 0.01)
        XCTAssertEqual(box.top, 0, accuracy: 0.01)
        XCTAssertEqual(box.left, 50, accuracy: 0.01, "a quarter turn, right to top: it ends above the centre")
    }

    func testCodePage949DecodesHangulPairs() {
        XCTAssertEqual(CodePage949.decode(lead: 0xB1, trail: 0xBC), 0xAD74)   // 굴
        XCTAssertEqual(CodePage949.decode(lead: 0xB8, trail: 0xB2), 0xB9BC)   // 림
        XCTAssertNil(CodePage949.decode(lead: 0x41, trail: 0x41))
    }
}
