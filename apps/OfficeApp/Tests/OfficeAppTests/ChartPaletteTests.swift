import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// W-OB-5: Chart Design > Change Colors. The fills each palette writes are Office's own, read from the corpus' chart
/// parts (the colour style a chart names, with the series fills Word or PowerPoint wrote beside it).
final class ChartPaletteTests: XCTestCase {
    private func chartDocument(_ chart: Chart) throws -> RichDocument {
        let doc = RichDocument(paragraphs: [RichParagraph(text: "Before"), RichParagraph(text: "After")])
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        func replace(_ name: String, _ f: (String) -> String) {
            let i = entries.firstIndex { $0.name == name }!
            entries[i] = ZipEntry(name: name, data: Data(f(String(decoding: entries[i].data, as: UTF8.self)).utf8))
        }
        let drawing = "<w:drawing><wp:inline><wp:extent cx=\"2540000\" cy=\"1270000\"/><wp:docPr id=\"7\" name=\"Chart 1\"/><a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/chart\"><c:chart xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" r:id=\"rId77\"/></a:graphicData></a:graphic></wp:inline></w:drawing>"
        replace("word/document.xml") { $0.replacingAll("<w:t>Before</w:t></w:r>", with: "<w:t>Before</w:t></w:r><w:r>\(drawing)</w:r>") }
        replace("word/_rels/document.xml.rels") { $0.replacingAll("</Relationships>",
            with: "<Relationship Id=\"rId77\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart\" Target=\"charts/chart1.xml\"/></Relationships>") }
        replace("[Content_Types].xml") { $0.replacingAll("</Types>",
            with: "<Override PartName=\"/word/charts/chart1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/></Types>") }
        let part = ChartXML.chartSpace(chart).replacingOccurrences(of: "<c:chart>", with: "<c:style val=\"42\"/><c:chart>")
        entries.append(ZipEntry(name: "word/charts/chart1.xml", data: Data(part.utf8)))
        return try DocxFormat.read(try Zip.write(entries)).document
    }

    private func mods(_ p: Int, _ n: Int) -> [String] {
        (0 ..< n).map { ChartPalette(id: p).element($0, of: n) }
    }

    func testMonochromaticSpreadsOneAccentDarkToLight() {
        XCTAssertEqual(mods(14, 4), ["<a:schemeClr val=\"accent1\"><a:shade val=\"58000\"/></a:schemeClr>",
                                     "<a:schemeClr val=\"accent1\"><a:shade val=\"86000\"/></a:schemeClr>",
                                     "<a:schemeClr val=\"accent1\"><a:tint val=\"86000\"/></a:schemeClr>",
                                     "<a:schemeClr val=\"accent1\"><a:tint val=\"58000\"/></a:schemeClr>"])
        let seven = mods(16, 7)
        XCTAssertEqual(seven[0], "<a:schemeClr val=\"accent3\"><a:shade val=\"47000\"/></a:schemeClr>")
        XCTAssertEqual(seven[1], "<a:schemeClr val=\"accent3\"><a:shade val=\"65000\"/></a:schemeClr>")
        XCTAssertEqual(seven[2], "<a:schemeClr val=\"accent3\"><a:shade val=\"82000\"/></a:schemeClr>")
        XCTAssertEqual(seven[3], "<a:schemeClr val=\"accent3\"/>")
        XCTAssertEqual(seven[4], "<a:schemeClr val=\"accent3\"><a:tint val=\"83000\"/></a:schemeClr>")
        XCTAssertEqual(seven[5], "<a:schemeClr val=\"accent3\"><a:tint val=\"65000\"/></a:schemeClr>")
        XCTAssertEqual(seven[6], "<a:schemeClr val=\"accent3\"><a:tint val=\"48000\"/></a:schemeClr>")
        XCTAssertEqual(mods(15, 2), ["<a:schemeClr val=\"accent2\"><a:shade val=\"76000\"/></a:schemeClr>",
                                     "<a:schemeClr val=\"accent2\"><a:tint val=\"77000\"/></a:schemeClr>"])
        XCTAssertEqual(mods(21, 4), mods(14, 4).reversed(), "8-13 are 1-6 light to dark")
        XCTAssertEqual(mods(20, 2), ["<a:schemeClr val=\"dk1\"><a:tint val=\"88500\"/></a:schemeClr>",
                                     "<a:schemeClr val=\"dk1\"><a:tint val=\"55000\"/></a:schemeClr>"])
    }

    func testColorfulCyclesTheAccentsThenVariesThem() {
        let eight = mods(10, 8)
        XCTAssertEqual(eight[0], "<a:schemeClr val=\"accent1\"/>")
        XCTAssertEqual(eight[5], "<a:schemeClr val=\"accent6\"/>")
        XCTAssertEqual(eight[6], "<a:schemeClr val=\"accent1\"><a:lumMod val=\"60000\"/></a:schemeClr>")
        XCTAssertEqual(mods(13, 4).map { $0.prefix(26) }, ["<a:schemeClr val=\"accent6\"", "<a:schemeClr val=\"accent5\"",
                                                          "<a:schemeClr val=\"accent4\"", "<a:schemeClr val=\"accent6\""])
        XCTAssertEqual(ChartPalette.colorful.map(\.name).first, "Colorful Palette 1")
        XCTAssertEqual(ChartPalette.monochromatic.map(\.name).last, "Monochromatic Palette 13")
    }

    /// Picking a palette in Word writes every series its fill into the chart's own part, and the palette is still the
    /// ticked one when the part is read back.
    func testWordChartTakesThePaletteIntoItsPart() throws {
        WriterCharts.installHooks()
        let c = RichDocumentController(document: try chartDocument(Chart.sample(.column)))
        c.onKeptPartChange = { [unowned c] path, data in WordChartEdit.partChanged(path, data, in: c.document) }
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { !$0.inlineImages.isEmpty })
        let id = try XCTUnwrap(c.document.paragraphs[i].inlineImages.keys.first)
        let image = try XCTUnwrap(WordChartEdit.image(c.document, index: i, inline: id))
        let old = try XCTUnwrap(WordChartEdit.chart(image, in: c.document))
        let theme = WriterCharts.theme(image.id) ?? DeckTheme()
        let palette = ChartPalette(id: 16)
        XCTAssertFalse(palette.matches(old, accents: theme.accents, dark: theme.text))

        XCTAssertTrue(WordChartEdit.set(palette.applied(to: old, accents: theme.accents, dark: theme.text), of: image, in: c))
        let xml = String(decoding: c.document.keptParts["word/charts/chart1.xml"] ?? Data(), as: UTF8.self)
        let n = old.series.count
        for s in 0 ..< n { XCTAssertTrue(xml.containsSubstring(palette.element(s, of: n)), "series \(s): \(xml)") }
        let back = try XCTUnwrap(WordChartEdit.chart(image, in: c.document))
        XCTAssertTrue(palette.matches(back, accents: theme.accents, dark: theme.text), "ticked after the part is read back")
        XCTAssertFalse(ChartPalette(id: 10).matches(back, accents: theme.accents, dark: theme.text))
        c.undo()
        XCTAssertFalse(palette.matches(try XCTUnwrap(WordChartEdit.chart(image, in: c.document)), accents: theme.accents, dark: theme.text))
    }

    /// A pie takes the palette slice by slice.
    func testPieTakesThePaletteBySlice() {
        let pie = Chart.sample(.pie)
        let theme = DeckTheme()
        let p = ChartPalette(id: 11).applied(to: pie, accents: theme.accents, dark: theme.text)
        XCTAssertEqual(p.pointColorXML.count, pie.categories.count)
        XCTAssertEqual(p.pointColorXML[1], "<a:schemeClr val=\"accent3\"/>")
        XCTAssertTrue(ChartPalette(id: 11).matches(p, accents: theme.accents, dark: theme.text))
    }
}
