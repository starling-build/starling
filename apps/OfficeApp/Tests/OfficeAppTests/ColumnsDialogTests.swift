import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-PG-2: Layout > Columns > More Columns: Word's presets, unequal widths and spacing, and Line between, held and saved as Word's.
final class ColumnsDialogTests: XCTestCase {
    /// Letter at Word's 1in margins: a 468pt text width.
    private let letter = PageSetup(width: 612, height: 792, marginTop: 72, marginBottom: 72, marginLeft: 72, marginRight: 72)

    func testThePresetsAreWordsAndTheDialogKnowsThem() {
        var v = ColumnsValues(letter)
        XCTAssertEqual(v.preset, .one)
        v.apply(.three)
        XCTAssertEqual(v.widths, [132, 132, 132]); XCTAssertEqual(v.gaps, [36, 36]); XCTAssertTrue(v.equal)
        v.apply(.left)
        XCTAssertEqual(v.widths, [132, 300], "the narrow column is one of three equal ones (Word: 1.83in and 4.17in)")
        XCTAssertFalse(v.equal)
        XCTAssertEqual(v.preset, .left)
        v.apply(.right)
        XCTAssertEqual(v.widths, [300, 132])
        XCTAssertEqual(v.preset, .right)
    }

    func testEqualColumnsMoveTogetherAndUnequalOnesGiveWayToTheirNeighbour() {
        var v = ColumnsValues(letter)
        v.setCount(3)
        v.setWidth(0, 150)
        XCTAssertEqual(v.widths, [150, 150, 150]); XCTAssertEqual(v.gaps, [9, 9], "the spacing gives way")
        v.setGap(1, 18)
        XCTAssertEqual(v.gaps, [18, 18]); XCTAssertEqual(v.widths, [144, 144, 144])
        v.setEqual(false)
        v.setWidth(0, 100)
        XCTAssertEqual(v.widths, [100, 188, 144])
        v.setGap(0, 30)
        XCTAssertEqual(v.widths, [100, 176, 144]); XCTAssertEqual(v.gaps, [30, 18])
        XCTAssertEqual(v.widths.reduce(0, +) + v.gaps.reduce(0, +), 468, accuracy: 1e-9, "the columns still fill the text width")
        v.setWidth(2, 10)
        XCTAssertEqual(v.widths[2], ColumnsValues.minWidth, "no column under half an inch")
        v.setCount(99)
        XCTAssertEqual(v.count, v.maxCount(gap: 30), "as many as fit at the first spacing")
    }

    func testTheDialogsColumnsAreSavedAsWordsAndReadBack() throws {
        var v = ColumnsValues(letter)
        v.apply(.left); v.line = true
        var page = letter
        v.apply(to: &page)
        XCTAssertEqual(page.columns, 2)
        XCTAssertEqual(page.columnSpec, [ColumnSpan(width: 132, gap: 36), ColumnSpan(width: 300, gap: 0)])
        let data = try DocxFormat.write(RichDocument(plainText: "text"), pageSetup: page)
        let body = String(decoding: try XCTUnwrap(try Zip.read(data).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        XCTAssertTrue(body.containsSubstring("<w:cols w:num=\"2\" w:sep=\"1\" w:space=\"720\" w:equalWidth=\"0\"><w:col w:w=\"2640\" w:space=\"720\"/><w:col w:w=\"6000\"/></w:cols>"), body)
        let back = try XCTUnwrap(DocxFormat.read(data).pageSetup)
        XCTAssertEqual(back.columns, 2)
        XCTAssertTrue(back.columnLine)
        XCTAssertEqual(back.columnSpec, page.columnSpec)
        XCTAssertEqual(ColumnsValues(back).preset, .left)
    }

    /// A file's own `w:cols` is written back as it was while the columns are untouched, and as the page now says once changed.
    func testAFilesColumnsAreKeptUntilChanged() throws {
        let own = "<w:cols w:num=\"2\" w:space=\"425\" w:equalWidth=\"0\"><w:col w:w=\"4000\" w:space=\"425\"/><w:col w:w=\"4935\"/></w:cols>"
        let sect = "<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/>\(own)<w:titlePg/></w:sectPr>"
        let read = try DocxFormat.read(try docx(sect))
        var page = try XCTUnwrap(read.pageSetup)
        func cols(_ p: PageSetup) throws -> String {
            let body = String(decoding: try XCTUnwrap(try Zip.read(try DocxFormat.write(read.document, pageSetup: p)).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
            let from = try XCTUnwrap(body.rangeOfSubstring("<w:cols")), to = try XCTUnwrap(body.rangeOfSubstring("</w:cols>"))
            return String(body[from.lowerBound ..< to.upperBound])
        }
        XCTAssertEqual(try cols(page), try XCTUnwrap(read.document.columnsXML), "the file's own, as read")
        page.columnLine = true
        XCTAssertEqual(try cols(page), "<w:cols w:num=\"2\" w:sep=\"1\" w:space=\"425\" w:equalWidth=\"0\"><w:col w:w=\"4000\" w:space=\"425\"/><w:col w:w=\"4935\"/></w:cols>")
        // (An earlier section's mark: the new w:cols stands before the title page, as the schema orders them.)
        let patched = DocxFormat._sectionXML(sect.replacingOccurrences(of: own, with: ""), patchedTo: page)
        XCTAssertTrue(patched.containsSubstring("w:sep=\"1\""), patched)
        let c = try XCTUnwrap(patched.rangeOfSubstring("<w:cols")), t = try XCTUnwrap(patched.rangeOfSubstring("<w:titlePg"))
        XCTAssertLessThan(c.lowerBound, t.lowerBound)
        XCTAssertEqual(DocxFormat._sectionXML(sect, patchedTo: try XCTUnwrap(read.pageSetup)), sect, "a section nobody touched is kept byte for byte")
    }

    func testLineBetweenRulesTheGapFromTheTextsTopToItsLongestColumn() {
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        var d = RichDocument(plainText: "one\ntwo\nthree\nfour")
        d.paragraphs[2].style.pageBreakBefore = true; d.paragraphs[2].style.breakEndsPrevious = true; d.paragraphs[2].style.columnBreak = true
        var page = letter; page.columns = 2; page.columnLine = true
        let layout = RichLayout(theme: theme, paragraphCount: d.paragraphs.count)
        layout.pageSetup = page
        layout.width = page.columnWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(d)
        let canvas = RuleSpyCanvas()
        layout.paint(canvas, visible: layout.pageRect(0), document: d, selection: nil, caret: nil)
        let px = theme.pixelsPerPoint, rect = layout.pageRect(0)
        let rules = canvas.rects.filter { $0.height > 10 * px && $0.width < 2 * px }
        XCTAssertEqual(rules.count, 1, "\(canvas.rects)")
        guard let rule = rules.first else { return }
        XCTAssertEqual((rule.left + rule.right) / 2 - rect.left, (72 + 216 + 18) * px, accuracy: 0.01, "the middle of the gap")
        XCTAssertEqual(rule.top - rect.top, 72 * px, accuracy: 0.5)
        XCTAssertEqual(rule.width, 0.72 * px, accuracy: 0.001, "Word's rule")
        let pitch = layout._tops[1] - layout._tops[0]
        XCTAssertEqual(rule.height, 2 * pitch - 8 * px, accuracy: 0.5, "down to the foot of the second line's text, not the space after it")
        page.columnLine = false
        layout.pageSetup = page; layout.invalidateAll(); layout.ensureLaidOut(d)
        let plain = RuleSpyCanvas()
        layout.paint(plain, visible: layout.pageRect(0), document: d, selection: nil, caret: nil)
        XCTAssertTrue(plain.rects.filter { $0.height > 10 * px && $0.width < 2 * px }.isEmpty)
    }

    /// Unequal columns stand at their own widths, and each rule at the middle of its own gap (lab colsep3u: 100, 200 and
    /// 114pt columns 18 and 36pt apart, Word's rules centred at 180.98 and 408.07).
    func testUnequalColumnsStandAtTheirWidthsWithARuleInEachGap() {
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        var d = RichDocument(plainText: "A1\nB1\nC1")
        for i in [1, 2] { d.paragraphs[i].style.pageBreakBefore = true; d.paragraphs[i].style.breakEndsPrevious = true; d.paragraphs[i].style.columnBreak = true }
        var page = letter; page.columns = 3; page.columnLine = true; page.columnGap = 18
        page.columnSpec = [ColumnSpan(width: 100, gap: 18), ColumnSpan(width: 200, gap: 36), ColumnSpan(width: 114, gap: 0)]
        let layout = RichLayout(theme: theme, paragraphCount: d.paragraphs.count)
        layout.pageSetup = page
        layout.width = page.columnWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(d)
        let px = theme.pixelsPerPoint
        XCTAssertEqual(layout._pxColumnLeft(0, column: 1, paragraph: 1), (72 + 118) * px, accuracy: 0.01)
        XCTAssertEqual(layout._pxColumnLeft(0, column: 2, paragraph: 2), (72 + 354) * px, accuracy: 0.01)
        let canvas = RuleSpyCanvas()
        layout.paint(canvas, visible: layout.pageRect(0), document: d, selection: nil, caret: nil)
        let left = layout.pageRect(0).left
        let mids = canvas.rects.filter { $0.height > 5 * px && $0.width < 2 * px }.map { ($0.left + $0.right) / 2 - left }.sorted()
        XCTAssertEqual(mids.count, 2, "\(canvas.rects)")
        if mids.count == 2 {
            XCTAssertEqual(mids[0], 181 * px, accuracy: 0.01); XCTAssertEqual(mids[1], 408 * px, accuracy: 0.01)
        }
    }

    private func docx(_ sect: String) throws -> Data {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(plainText: "a"), pageSetup: .letter))
        let i = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var body = String(decoding: entries[i].data, as: UTF8.self)
        let from = try XCTUnwrap(body.rangeOfSubstring("<w:sectPr")), to = try XCTUnwrap(body.rangeOfSubstring("</w:sectPr>"))
        body.replaceSubrange(from.lowerBound ..< to.upperBound, with: sect)
        entries[i] = ZipEntry(name: entries[i].name, data: Data(body.utf8))
        return try Zip.write(entries)
    }
}

private final class RuleSpyCanvas: Canvas {
    var rects: [Rect] = []
    func save() {}
    func saveLayer(_ bounds: Rect?, _ paint: Paint) {}
    func restore() {}
    func restoreToCount(_ count: Int) {}
    func getSaveCount() -> Int { 1 }
    func translate(_ dx: Double, _ dy: Double) {}
    func scale(_ sx: Double, _ sy: Double?) {}
    func rotate(_ radians: Double) {}
    func skew(_ sx: Double, _ sy: Double) {}
    func transform(_ matrix4: [Double]) {}
    func getTransform() -> [Double] { [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1] }
    func clipRect(_ rect: Rect, clipOp: ClipOp, doAntiAlias: Bool) {}
    func clipRRect(_ rrect: RRect, doAntiAlias: Bool) {}
    func clipRSuperellipse(_ rsuperellipse: RSuperellipse, doAntiAlias: Bool) {}
    func clipPath(_ path: Path, doAntiAlias: Bool) {}
    func getLocalClipBounds() -> Rect { Rect.fromLTWH(-1e6, -1e6, 2e6, 2e6) }
    func getDestinationClipBounds() -> Rect { Rect.fromLTWH(-1e6, -1e6, 2e6, 2e6) }
    func drawColor(_ color: Color, _ blendMode: BlendMode) {}
    func drawLine(_ p1: Offset, _ p2: Offset, _ paint: Paint) {}
    func drawPaint(_ paint: Paint) {}
    func drawRect(_ rect: Rect, _ paint: Paint) { rects.append(rect) }
    func drawRRect(_ rrect: RRect, _ paint: Paint) {}
    func drawDRRect(_ outer: RRect, _ inner: RRect, _ paint: Paint) {}
    func drawRSuperellipse(_ rsuperellipse: RSuperellipse, _ paint: Paint) {}
    func drawOval(_ rect: Rect, _ paint: Paint) {}
    func drawCircle(_ c: Offset, _ radius: Double, _ paint: Paint) {}
    func drawArc(_ rect: Rect, _ startAngle: Double, _ sweepAngle: Double, _ useCenter: Bool, _ paint: Paint) {}
    func drawPath(_ path: Path, _ paint: Paint) {}
    func drawImage(_ image: Image, _ offset: Offset, _ paint: Paint) {}
    func drawImageRect(_ image: Image, _ src: Rect, _ dst: Rect, _ paint: Paint) {}
    func drawImageNine(_ image: Image, _ center: Rect, _ dst: Rect, _ paint: Paint) {}
    func drawPicture(_ picture: any FlutterSwiftBridge.Picture) {}
    func drawParagraph(_ paragraph: any Paragraph, _ offset: Offset) {}
    func drawPoints(_ pointMode: PointMode, _ points: [Offset], _ paint: Paint) {}
    func drawRawPoints(_ pointMode: PointMode, _ points: [Float], _ paint: Paint) {}
    func drawVertices(_ vertices: Vertices, _ blendMode: BlendMode, _ paint: Paint) {}
    func drawAtlas(_ atlas: Image, _ transforms: [RSTransform], _ rects: [Rect], _ colors: [Color]?, _ blendMode: BlendMode?, _ cullRect: Rect?, _ paint: Paint) {}
    func drawRawAtlas(_ atlas: Image, _ rstTransforms: [Float], _ rects: [Float], _ colors: [Int32]?, _ blendMode: BlendMode?, _ cullRect: Rect?, _ paint: Paint) {}
    func drawShadow(_ path: Path, _ color: Color, _ elevation: Double, _ transparentOccluder: Bool) {}
}
