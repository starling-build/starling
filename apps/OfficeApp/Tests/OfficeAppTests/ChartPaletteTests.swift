import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// W-OB-5: Chart Design > Change Colors. The fills each palette writes are Office's own, read from the corpus' chart
/// parts (the colour style a chart names, with the series fills Word or PowerPoint wrote beside it).
final class ChartPaletteTests: XCTestCase {
    /// A document with a chart of `type` put in by Insert > Chart (its part, rels and workbook), and that chart.
    static func inserted(_ type: ChartType, into base: RichDocument? = nil) throws -> (RichDocumentController, ImageAttachment) {
        WriterCharts.installHooks()
        let c = RichDocumentController(document: base ?? RichDocument(paragraphs: [RichParagraph(text: "")]))
        c.onKeptPartChange = { [unowned c] path, data in WordChartEdit.partChanged(path, data, in: c.document) }
        XCTAssertTrue(WordChartInsert.insert(type, into: c))
        let i = try XCTUnwrap(c.selectedImageIndex)
        return (c, try XCTUnwrap(c.document.paragraphs[i].image))
    }

    /// Every chart part in a saved file has one `c:style` and every relationship it names resolves to a part in the
    /// file: Word refuses to open the file otherwise.
    static func assertChartPartsOpen(_ docx: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        let entries = try Zip.read(docx)
        let names = Set(entries.map(\.name))
        func text(_ n: String) -> String? { entries.first { $0.name == n }.map { String(decoding: $0.data, as: UTF8.self) } }
        func attrs(_ x: String, _ name: String) -> [String] {
            x.components(separatedBy: " \(name)=\"").dropFirst().map { String($0.prefix { $0 != "\"" }) }
        }
        let parts = names.filter { $0.hasPrefix("word/charts/chart") && $0.hasSuffix(".xml") }.sorted()
        XCTAssertFalse(parts.isEmpty, "a chart part", file: file, line: line)
        for part in parts {
            let xml = text(part) ?? ""
            XCTAssertLessThanOrEqual(xml.components(separatedBy: "<c:style ").count - 1, 1, "one c:style in \(part)", file: file, line: line)
            let leaf = String(part.split(separator: "/").last ?? "")
            let rels = text("word/charts/_rels/\(leaf).rels") ?? ""
            let ids = attrs(rels, "Id"), targets = attrs(rels, "Target")
            for rid in attrs(xml, "r:id") {
                let k = try XCTUnwrap(ids.firstIndex(of: rid), "\(part) names \(rid), which its rels lack", file: file, line: line)
                let target = "word/" + targets[k].replacingOccurrences(of: "../", with: "")
                XCTAssertTrue(names.contains(target), "\(part) \(rid) -> \(target) is in the file", file: file, line: line)
            }
        }
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
        let (c, image) = try Self.inserted(.column)
        let old = try XCTUnwrap(WordChartEdit.chart(image, in: c.document))
        let theme = WriterCharts.theme(image.id) ?? DeckTheme()
        let palette = ChartPalette(id: 16)
        XCTAssertFalse(palette.matches(old, accents: theme.accents, dark: theme.text))

        XCTAssertTrue(WordChartEdit.set(palette.applied(to: old, accents: theme.accents, dark: theme.text), of: image, in: c))
        let xml = String(decoding: c.document.keptParts["word/charts/chart1.xml"] ?? Data(), as: UTF8.self)
        let n = old.series.count
        for s in 0 ..< n { XCTAssertTrue(xml.containsSubstring(palette.element(s, of: n)), "series \(s): \(xml)") }
        try Self.assertChartPartsOpen(try DocxFormat.write(c.document, pageSetup: .letter))
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
