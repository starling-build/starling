import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// Fixes found by round-tripping Apache POI's .pptx corpus (2026-10-01).
final class CorpusFixTests: XCTestCase {
    func testAnArchiveCutShortGivesUpItsCompleteEntries() throws {
        let whole = try Zip.write([
            ZipEntry(name: "a.xml", data: Data(String(repeating: "<a/>", count: 200).utf8)),
            ZipEntry(name: "b.bin", data: Data([1, 2, 3])),
            ZipEntry(name: "c.xml", data: Data(String(repeating: "<c/>", count: 200).utf8)),
        ])
        // Lose the central directory and half of the last entry.
        let cdStart = whole.range(of: Data([0x50, 0x4B, 0x01, 0x02]))!.lowerBound
        let cut = whole.prefix(cdStart - 10)
        let salvaged = try Zip.read(Data(cut))
        XCTAssertEqual(salvaged.map(\.name), ["a.xml", "b.bin"])
        XCTAssertEqual(salvaged[1].data, Data([1, 2, 3]))
        XCTAssertThrowsError(try Zip.read(Data("not a zip at all, honestly".utf8)))
    }

    func testATextBoxKeepsShrinkToFit() throws {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        var slide = String(data: package.parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        XCTAssertTrue(slide.contains("<a:spAutoFit/>"), "the sample's text box grows")
        slide = slide.replacingOccurrences(of: "<a:spAutoFit/>", with: "<a:normAutofit fontScale=\"85000\"/>")
        package.parts["ppt/slides/slide6.xml"] = Data(slide.utf8)
        let (state, theme, pkg) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        let out = String(data: PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
            .parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        XCTAssertTrue(out.contains("<a:normAutofit fontScale=\"85000\"/>"))
    }

    /// Slide 6's rounded box with its fill moved into a p:style, a shadow,
    /// and exact 30 pt lines with white text from the style's fontRef.
    private func styledPackage() throws -> PptxPackage {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        var slide = String(data: package.parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        let box = try XCTUnwrap(slide.range(of: "prst=\"roundRect\""))
        let spEnd = try XCTUnwrap(slide.range(of: "</p:spPr>", range: box.upperBound ..< slide.endIndex))
        let fillStart = try XCTUnwrap(slide.range(of: "<a:solidFill>", range: box.upperBound ..< spEnd.lowerBound))
        slide.replaceSubrange(fillStart.lowerBound ..< spEnd.upperBound, with:
            "<a:effectLst><a:outerShdw blurRad=\"50800\" dist=\"38100\"><a:prstClr val=\"black\"/></a:outerShdw></a:effectLst></p:spPr>"
            + "<p:style><a:lnRef idx=\"1\"><a:schemeClr val=\"accent1\"/></a:lnRef><a:fillRef idx=\"1\"><a:schemeClr val=\"accent2\"/></a:fillRef>"
            + "<a:effectRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:effectRef><a:fontRef idx=\"minor\"><a:schemeClr val=\"lt1\"/></a:fontRef></p:style>")
        package.parts["ppt/slides/slide6.xml"] = Data(slide.utf8)
        return package
    }

    func testAStylesFillEffectsAndTextColourSurvive() throws {
        let package = try styledPackage()
        let (state, theme, pkg) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        let box = try XCTUnwrap(state.slides[5].shapes.first { $0.kind == .geometry(.roundRect) })
        XCTAssertEqual(box.fill, theme.accents[1], "the style's fill is drawn")
        XCTAssertNotNil(box.keptLook?.style)
        let out = String(data: PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
            .parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        XCTAssertTrue(out.contains("<a:fillRef idx=\"1\"><a:schemeClr val=\"accent2\"/></a:fillRef>"), "the style goes back")
        XCTAssertTrue(out.contains("<a:outerShdw"), "and the shadow")
        // Recoloured: our own fill, the style still written.
        var edited = state
        let i = edited.slides[5].shapes.firstIndex { $0.kind == .geometry(.roundRect) }!
        edited.slides[5].shapes[i].fill = Color(0xFF00FF00)
        edited.slides[5].shapes[i].fillScheme = nil
        let out2 = String(data: PptxPackage(try Zip.read(try PptxWriter.write(edited, theme: theme, package: pkg)))
            .parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        XCTAssertTrue(out2.contains("00FF00"))
    }

    func testExactLineSpacingStaysExact() throws {
        var p = RichParagraph(text: "Exact", style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1))
        p.style.lineHeightPoints = 30
        let s = ShapeState(id: 1, name: "t", kind: .textBox, frame: Rect.fromLTWH(0, 0, 100, 40), rotation: 0,
                           fill: nil, outline: nil, outlineWidth: 0, anchor: .top, insets: .zero, prompt: nil,
                           text: RichDocument(paragraphs: [p]), font: "Calibri", size: 18, color: Color(0xFF000000),
                           listIndent: 18)
        let xml = PptxText.paragraphs(s.text!, defaults: s)
        XCTAssertTrue(xml.contains("<a:lnSpc><a:spcPts val=\"3000\"/></a:lnSpc>"))
    }

    /// Hebrew letters are set in the theme's face for Hebrew, the Latin
    /// ones beside them in the run's own (tdf98603).
    func testHebrewTakesTheThemesHebrewFace() throws {
        var package = PptxPackage(try Zip.read(try Pptx.write(SlidesSample.make())))
        // (Every theme part: the deck has one for its notes too.)
        for themePart in package.parts.keys where themePart.hasPrefix("ppt/theme/") {
            var theme = String(data: package.parts[themePart]!, encoding: .utf8)!
            let minor = try XCTUnwrap(theme.range(of: "<a:minorFont>"))
            let cs = try XCTUnwrap(theme.range(of: "<a:cs typeface=\"\"/>", range: minor.upperBound ..< theme.endIndex))
            theme.insert(contentsOf: "<a:font script=\"Hebr\" typeface=\"Times New Roman\"/>", at: cs.upperBound)
            package.parts[themePart] = Data(theme.utf8)
        }
        var slide = String(data: package.parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        let t = try XCTUnwrap(slide.range(of: #"<a:t>[^<]*</a:t>"#, options: .regularExpression))
        slide.replaceSubrange(t, with: "<a:t>Hi, \u{05E9}\u{05DC}\u{05D5}\u{05DD}!</a:t>")
        // (Our writer names the run's face for complex script too.)
        slide = slide.replacingOccurrences(of: #"<a:cs typeface="[^"]*"/>"#, with: "", options: .regularExpression)
        package.parts["ppt/slides/slide6.xml"] = Data(slide.utf8)
        let (state, _, _) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        let p = try XCTUnwrap(state.slides[5].shapes.compactMap { $0.text?.paragraphs.first { $0.text.hasPrefix("Hi, ") } }.first)
        XCTAssertEqual(p.runs.map(\.length), [4, 5])
        XCTAssertNotEqual(p.runs[0].style.fontFamily, "Times New Roman")
        XCTAssertEqual(p.runs[1].style.fontFamily, "Times New Roman", "the Hebrew word and the mark after it")
    }

    /// A slide PDF's pictures are marked to be smoothed, and the file's
    /// cross-reference table still finds every object after the insert.
    func testSlidePdfPicturesAreSmoothed() throws {
        let objects = ["<</Type /Catalog>>", "<</Type /XObject\n/Subtype /Image\n/Width 2>> stream\nab\nendstream",
                       "<</Type /XObject\n/Subtype /Image\n/Width 3>> stream\ncd\nendstream", "<</Length 0>>"]
        var pdf = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (k, o) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(k + 1) 0 obj\n\(o)\nendobj\n"
        }
        let table = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for o in offsets { pdf += String(format: "%010d", o) + " 00000 n \n" }
        pdf += "trailer\n<</Size \(objects.count + 1)>>\nstartxref\n\(table)\n%%EOF\n"
        let out = try XCTUnwrap(SlidesPdf.smoothPictures(Data(pdf.utf8)))
        let text = String(decoding: out, as: UTF8.self)
        XCTAssertEqual(text.components(separatedBy: "/Subtype /Image\n/Interpolate true").count, 3)
        let bytes = [UInt8](out)
        let xref = try XCTUnwrap(text.range(of: "startxref\n")).upperBound
        let at = Int(text[xref...].prefix { $0.isNumber })!
        XCTAssertEqual(String(decoding: bytes[at ..< at + 4], as: UTF8.self), "xref")
        let entries = text[text.range(of: "65535 f \n")!.upperBound...].split(separator: "\n").prefix(objects.count)
        for (k, e) in entries.enumerated() {
            let o = Int(e.prefix(10))!
            XCTAssertEqual(String(decoding: bytes[o ..< o + 7], as: UTF8.self), "\(k + 1) 0 obj")
        }
        XCTAssertNil(SlidesPdf.smoothPictures(Data("%PDF-1.4\nno pictures".utf8)))
    }

    /// lo tdf48658's header is a transparent VML box (`w:pict`) holding a
    /// table whose first cell has a small inline picture. The picture the
    /// box's text holds is not the box's own: read as the pict's picture,
    /// the box drew that picture alone and none of its table.
    func testAPictureInsideATextBoxDoesNotMakeTheBoxThePicture() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(image: ImageAttachment(data: png, width: 10, height: 10))]), pageSetup: .a4))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let embed = try XCTUnwrap(xml.range(of: #"r:embed="[^"]+""#, options: .regularExpression))
        let rid = String(xml[embed])
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        let picture = "<w:r><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\"><wp:extent cx=\"238125\" cy=\"171450\"/>"
            + "<wp:docPr id=\"14\" name=\"p\"/><a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\">"
            + "<a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">"
            + "<pic:blipFill><a:blip \(rid)/></pic:blipFill></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>"
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:p><w:r><w:pict><v:shape xmlns:v=\"urn:schemas-microsoft-com:vml\" type=\"#_x0000_t202\" "
            + "style=\"position:absolute;margin-left:58pt;margin-top:45pt;width:500pt;height:80pt\" stroked=\"f\">"
            + "<v:textbox><w:txbxContent><w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w=\"2000\"/><w:gridCol w:w=\"2000\"/></w:tblGrid>"
            + "<w:tr><w:tc><w:tcPr><w:tcW w:w=\"2000\" w:type=\"dxa\"/></w:tcPr><w:p>\(picture)</w:p></w:tc>"
            + "<w:tc><w:tcPr><w:tcW w:w=\"2000\" w:type=\"dxa\"/></w:tcPr><w:p><w:r><w:t>Title</w:t></w:r></w:p></w:tc></w:tr></w:tbl>"
            + "<w:p/></w:txbxContent></v:textbox></v:shape></w:pict></w:r></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let image = try XCTUnwrap(doc.paragraphs.compactMap { $0.image ?? $0.inlineImages.values.first }.first)
        let box = try XCTUnwrap(image.textBox, "the box, not the picture in its table")
        XCTAssertTrue(box.paragraphs.contains { $0.text.contains("Title") })
    }

    /// A header's square-wrapped `spAutoFit` box as wide as the text holds the body under its TEXT's height, not the stale
    /// extent in the file (pt 3e4a9b9379: 110.6 pt stated, one 10 pt line, the body 128 pt low).
    func testAHeaderAutofitBoxHoldsTheBodyAtItsTextHeight() throws {
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = false }
        func bodyTop(autofit: Bool) throws -> Double {
            var doc = RichDocument(paragraphs: [RichParagraph(text: "a")])
            doc.header = "x"
            var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
            let hi = entries.firstIndex { $0.name == "word/header1.xml" }!
            var hxml = String(decoding: entries[hi].data, as: UTF8.self)
            let inner = try XCTUnwrap(hxml.range(of: "<w:p>")).lowerBound ..< (try XCTUnwrap(hxml.range(of: "</w:p>"))).upperBound
            let anchor = "<wp:anchor distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\" simplePos=\"0\" relativeHeight=\"1\" behindDoc=\"0\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\">"
                + "<wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"column\"><wp:posOffset>0</wp:posOffset></wp:positionH>"
                + "<wp:positionV relativeFrom=\"paragraph\"><wp:posOffset>381000</wp:posOffset></wp:positionV><wp:extent cx=\"6000000\" cy=\"1400000\"/>"
                + "<wp:wrapSquare wrapText=\"bothSides\"/><wp:docPr id=\"1\" name=\"s\"/><a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\">"
                + "<a:graphicData uri=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\"><wps:wsp xmlns:wps=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\">"
                + "<wps:cNvSpPr txBox=\"1\"/><wps:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"6000000\" cy=\"1400000\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></wps:spPr>"
                + "<wps:txbx><w:txbxContent><w:p><w:r><w:t>box</w:t></w:r></w:p></w:txbxContent></wps:txbx>"
                + "<wps:bodyPr wrap=\"square\" lIns=\"91440\" tIns=\"45720\" rIns=\"91440\" bIns=\"45720\">\(autofit ? "<a:spAutoFit/>" : "")</wps:bodyPr></wps:wsp></a:graphicData></a:graphic></wp:anchor>"
            hxml.replaceSubrange(inner, with: "<w:p><w:pPr><w:pStyle w:val=\"Header\"/></w:pPr><w:r><w:drawing>\(anchor)</w:drawing></w:r></w:p>")
            entries[hi] = ZipEntry(name: "word/header1.xml", data: Data(hxml.utf8))
            let back = try DocxFormat.read(try Zip.write(entries)).document
            let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: back.paragraphs.count)
            layout.pageSetup = .letter
            layout.width = PageSetup.letter.columnWidth * theme.pixelsPerPoint
            layout.ensureLaidOut(back)
            return layout.bodyBandPoints(page: 0, back).top
        }
        let fixed = try bodyTop(autofit: false), fitted = try bodyTop(autofit: true)
        XCTAssertGreaterThan(fixed, PageSetup.letter.headerDistance + 30 + 100, "a fixed-height box: the body stands under its stated foot")
        XCTAssertLessThan(fitted, fixed - 60, "an autofit box: under its one text line")
    }

    /// A paragraph of one anchored picture is as tall as its anchor run's font. A run that states `sz` is that size even when the paragraph
    /// style is bigger (pt-ebe6f5b3cc); in a right-to-left paragraph the picture is a complex-script character, so only `szCs` sizes it and
    /// the style's size stays (dx2 b02602d2).
    private func anchoredPictureParagraph(bidi: Bool) throws -> RichParagraph {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(image: ImageAttachment(data: png, width: 10, height: 10))]), pageSetup: .a4))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let embed = try XCTUnwrap(xml.range(of: #"r:embed="[^"]+""#, options: .regularExpression))
        let rid = String(xml[embed])
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        let anchor = "<wp:anchor distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\" simplePos=\"0\" relativeHeight=\"1\" behindDoc=\"0\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\">"
            + "<wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"page\"><wp:posOffset>100000</wp:posOffset></wp:positionH>"
            + "<wp:positionV relativeFrom=\"page\"><wp:posOffset>100000</wp:posOffset></wp:positionV><wp:extent cx=\"238125\" cy=\"171450\"/><wp:wrapNone/>"
            + "<wp:docPr id=\"14\" name=\"p\"/><a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\">"
            + "<a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">"
            + "<pic:blipFill><a:blip \(rid)/></pic:blipFill></pic:pic></a:graphicData></a:graphic></wp:anchor>"
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:p><w:pPr><w:pStyle w:val=\"Big\"/>\(bidi ? "<w:bidi/>" : "")<w:rPr><w:sz w:val=\"20\"/></w:rPr></w:pPr>"
            + "<w:r><w:rPr><w:sz w:val=\"20\"/></w:rPr><w:drawing>\(anchor)</w:drawing></w:r></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let si = try XCTUnwrap(entries.firstIndex { $0.name == "word/styles.xml" })
        var styles = String(decoding: entries[si].data, as: UTF8.self)
        let end = try XCTUnwrap(styles.range(of: "</w:styles>"))
        styles.replaceSubrange(end.lowerBound ..< end.lowerBound, with: "<w:style w:type=\"paragraph\" w:styleId=\"Big\"><w:name w:val=\"Big\"/><w:rPr><w:sz w:val=\"32\"/></w:rPr></w:style>")
        entries[si] = ZipEntry(name: "word/styles.xml", data: Data(styles.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        return try XCTUnwrap(doc.paragraphs.first { $0.image != nil || !$0.inlineImages.isEmpty })
    }

    func testAnAnchorRunsOwnSizeIsThePictureLinesHeight() throws {
        let p = try anchoredPictureParagraph(bidi: false)
        XCTAssertEqual(p.runs[0].style.fontSize, 10)
    }

    func testARightToLeftPictureParagraphIgnoresTheRunsLatinSize() throws {
        let p = try anchoredPictureParagraph(bidi: true)
        XCTAssertEqual(p.runs[0].style.fontSize ?? p.style.mark?.fontSize, 16)
    }
}
