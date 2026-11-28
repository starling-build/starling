import XCTest
import OfficeText
@testable import OfficeApp

/// W-OB-5: a chart in a Word document edited from Chart Design: its own part is patched, one undo step puts it back,
/// and the drawing follows the part (edit, undo and redo).
final class WordChartEditTests: XCTestCase {
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

    func testChartDesignEditPatchesThePartAndUndoes() throws {
        WriterCharts.installHooks()
        let c = RichDocumentController(document: try chartDocument(Chart.sample(.column)))
        c.onKeptPartChange = { [unowned c] path, data in WordChartEdit.partChanged(path, data, in: c.document) }
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { !$0.inlineImages.isEmpty })
        let id = try XCTUnwrap(c.document.paragraphs[i].inlineImages.keys.first)
        let image = try XCTUnwrap(WordChartEdit.image(c.document, index: i, inline: id))
        XCTAssertEqual(WordChartEdit.partPath(image), "word/charts/chart1.xml")
        let old = try XCTUnwrap(WordChartEdit.chart(image, in: c.document), "an editable chart")
        let before = c.document.keptParts["word/charts/chart1.xml"]

        var new = old
        new.type = .bar; new.title = "Revenue"; new.stacked = true
        XCTAssertTrue(WordChartEdit.set(new, of: image, in: c))
        XCTAssertEqual(WriterCharts.chart(id)?.type, .bar, "the drawing follows the part")
        XCTAssertEqual(WriterCharts.chart(id)?.title, "Revenue")
        XCTAssertEqual(WriterCharts.chart(id)?.stacked, true)
        let saved = try Zip.read(try DocxFormat.write(c.document, pageSetup: .letter))
        let xml = String(decoding: saved.first { $0.name == "word/charts/chart1.xml" }?.data ?? Data(), as: UTF8.self)
        XCTAssertTrue(xml.containsSubstring("<c:barChart>") && xml.containsSubstring("<c:grouping val=\"stacked\"/>"), xml)
        XCTAssertTrue(xml.containsSubstring("<c:overlap val=\"100\"/>"), "stacked bars overlap fully, as Word writes them")
        XCTAssertTrue(xml.containsSubstring("<c:style val=\"42\"/>"), "the rest of the part is kept")

        c.undo()
        XCTAssertEqual(c.document.keptParts["word/charts/chart1.xml"], before, "one undo step")
        XCTAssertEqual(WriterCharts.chart(id)?.type, .column)
        c.redo()
        XCTAssertEqual(WriterCharts.chart(id)?.title, "Revenue")
    }

    /// Typing into one cell of the data pane is one undo step however many keys it took.
    func testDataEditsInOneCellCoalesce() throws {
        WriterCharts.installHooks()
        let c = RichDocumentController(document: try chartDocument(Chart.sample(.column)))
        c.onKeptPartChange = { [unowned c] path, data in WordChartEdit.partChanged(path, data, in: c.document) }
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { !$0.inlineImages.isEmpty })
        let id = try XCTUnwrap(c.document.paragraphs[i].inlineImages.keys.first)
        let image = try XCTUnwrap(WordChartEdit.image(c.document, index: i, inline: id))
        let before = c.document.keptParts["word/charts/chart1.xml"]
        for v in [1.0, 12, 123] {
            var new = try XCTUnwrap(WriterCharts.chart(id))
            new.series[0].values[0] = v
            XCTAssertTrue(WordChartEdit.set(new, of: image, in: c, label: "Edit Data", coalesce: "B2"))
        }
        XCTAssertEqual(WriterCharts.chart(id)?.series[0].values[0], 123)
        c.undo()
        XCTAssertEqual(c.document.keptParts["word/charts/chart1.xml"], before)
    }

    /// The chart's elements a Chart Design edit turns on are written into the part (they used to be dropped on save).
    func testElementsArePatchedIntoThePart() throws {
        let old = Chart.sample(.column)
        let xml = ChartXML.chartSpace(old)
        var new = old
        new.dataLabels = true; new.valueAxisTitle = "Units"; new.categoryAxisTitle = "Month"; new.stacked = true; new.percent = true
        let r = try XCTUnwrap(ChartPartPatcher.patch(xml, old: old, new: new))
        let back = try XCTUnwrap(XNode.parse(Data(r.xml.utf8)).flatMap { ChartXML.read(ChartXML.canonical($0), color: { _ in nil }) })
        XCTAssertTrue(back.dataLabels)
        XCTAssertEqual(back.valueAxisTitle, "Units")
        XCTAssertEqual(back.categoryAxisTitle, "Month")
        XCTAssertTrue(back.stacked && back.percent)
        var off = new
        off.dataLabels = false; off.valueAxisTitle = nil; off.categoryAxisTitle = nil; off.stacked = false; off.percent = false
        let r2 = try XCTUnwrap(ChartPartPatcher.patch(r.xml, old: new, new: off))
        let b2 = try XCTUnwrap(XNode.parse(Data(r2.xml.utf8)).flatMap { ChartXML.read(ChartXML.canonical($0), color: { _ in nil }) })
        XCTAssertFalse(b2.dataLabels)
        XCTAssertNil(b2.valueAxisTitle)
        XCTAssertFalse(b2.stacked)
        XCTAssertFalse(r2.xml.containsSubstring("<c:overlap"), "clustered bars drop the full overlap")
    }

    /// Quick Layout as Word applies it (lab wobql: Word's ApplyLayout on a bar and a column chart): each kind has its own
    /// list, a layout sets the gridlines, gap, overlap and labels as well as the elements, and the patched part reads back
    /// as exactly the layout (so the menu checks it).
    func testQuickLayoutMatchesWordsLayoutsAndPatchesThePart() throws {
        func read(_ xml: String) -> Chart? { XNode.parse(Data(xml.utf8)).flatMap { ChartXML.read(ChartXML.canonical($0), color: { _ in nil }) } }
        func layout(_ list: [ChartQuickLayout], _ name: String) throws -> ChartQuickLayout { try XCTUnwrap(list.first { $0.name == name }) }
        XCTAssertEqual(ChartQuickLayout.bar.map(\.name).last, "Layout 10", "a bar chart has ten layouts")
        XCTAssertEqual(ChartQuickLayout.column.map(\.name).last, "Layout 11")
        XCTAssertTrue(ChartQuickLayout.layouts(for: Chart.sample(.pie)).isEmpty)
        // Column Layout 8 has no bar twin: the column's 9 is the bar's 8.
        XCTAssertEqual(try layout(ChartQuickLayout.column, "Layout 9").summary, try layout(ChartQuickLayout.bar, "Layout 8").summary)

        var old = Chart.sample(.column)
        old.title = "Sales"
        let ten = try layout(ChartQuickLayout.column, "Layout 10"), four = try layout(ChartQuickLayout.column, "Layout 4")
        let one = try layout(ChartQuickLayout.column, "Layout 1"), eight = try layout(ChartQuickLayout.column, "Layout 8")
        // Layout 10: title kept, legend right, labels on the last series only, inside the bar ends, 9 pt; gap 75, overlap 40.
        let a = ten.applied(to: old)
        let r = try XCTUnwrap(ChartPartPatcher.patch(ChartXML.chartSpace(old), old: old, new: a))
        let back = try XCTUnwrap(read(r.xml))
        XCTAssertEqual(back.title, "Sales"); XCTAssertEqual(back.legendPosition, "r")
        XCTAssertEqual(back.series.map(\.labelsShown), [false, false, true])
        XCTAssertEqual(back.series.last?.labelPos, "inEnd"); XCTAssertEqual(back.series.last?.labelSize, 9)
        XCTAssertEqual(back.gapWidth, 75); XCTAssertEqual(back.overlap, 40)
        XCTAssertTrue(ten.matches(back), "the menu checks the layout just applied")
        XCTAssertFalse(four.matches(back))
        // Layout 4 over it: every series labelled, no title, legend bottom, no gridlines, no overlap.
        let b = four.applied(to: back)
        let r2 = try XCTUnwrap(ChartPartPatcher.patch(r.xml, old: back, new: b))
        let b2 = try XCTUnwrap(read(r2.xml))
        XCTAssertNil(b2.title); XCTAssertEqual(b2.legendPosition, "b"); XCTAssertFalse(b2.valueGrid)
        XCTAssertEqual(b2.series.map(\.labelsShown), [true, true, true]); XCTAssertEqual(b2.series.map(\.labelSize), [9, 9, 9])
        XCTAssertFalse(r2.xml.containsSubstring("<c:majorGridlines")); XCTAssertFalse(r2.xml.containsSubstring("<c:overlap"))
        XCTAssertTrue(four.matches(b2))
        // Layout 1 over that: labels gone, gridlines back; Layout 8 (column only): both axis titles, no legend, gap 0.
        let c2 = try XCTUnwrap(read(try XCTUnwrap(ChartPartPatcher.patch(r2.xml, old: b2, new: one.applied(to: b2))).xml))
        XCTAssertFalse(c2.dataLabels); XCTAssertTrue(c2.valueGrid); XCTAssertTrue(one.matches(c2))
        let d = try XCTUnwrap(read(try XCTUnwrap(ChartPartPatcher.patch(r2.xml, old: b2, new: eight.applied(to: b2))).xml))
        XCTAssertEqual(d.valueAxisTitle, "Axis Title"); XCTAssertEqual(d.categoryAxisTitle, "Axis Title")
        XCTAssertFalse(d.legend); XCTAssertEqual(d.gapWidth, 0); XCTAssertTrue(eight.matches(d))
    }

    /// A two-level category axis (names under years) keeps its outer level when a name is edited: only the inner names
    /// change, in the part and in the workbook's inner column (Word's lab wob5chart c5 had it flattened to one level).
    func testMultiLevelCategoriesKeepTheirOuterLevel() throws {
        let old = Chart.sample(.column)
        var xml = ChartXML.chartSpace(old)
        let multi = "<c:cat><c:multiLvlStrRef><c:f>Sheet1!$A$2:$B$5</c:f><c:multiLvlStrCache><c:ptCount val=\"4\"/>"
            + "<c:lvl>" + old.categories.enumerated().map { "<c:pt idx=\"\($0)\"><c:v>\($1)</c:v></c:pt>" }.joined() + "</c:lvl>"
            + "<c:lvl><c:pt idx=\"0\"><c:v>2011</c:v></c:pt><c:pt idx=\"2\"><c:v>2012</c:v></c:pt></c:lvl>"
            + "</c:multiLvlStrCache></c:multiLvlStrRef></c:cat>"
        let re = try NSRegularExpression(pattern: "<c:cat>.*?</c:cat>")
        xml = re.stringByReplacingMatches(in: xml, range: NSRange(xml.startIndex..., in: xml), withTemplate: NSRegularExpression.escapedTemplate(for: multi))
        let read = { (x: String) in XNode.parse(Data(x.utf8)).flatMap { ChartXML.read(ChartXML.canonical($0), color: { _ in nil }) } }
        let before = try XCTUnwrap(read(xml))
        XCTAssertEqual(before.categoryLevels.first?.map(\.text), ["2011", "2012"])
        var new = before
        new.categories[0] = "Edited"
        let r = try XCTUnwrap(ChartPartPatcher.patch(xml, old: before, new: new))
        let back = try XCTUnwrap(read(r.xml))
        XCTAssertEqual(back.categories, ["Edited", "Category 2", "Category 3", "Category 4"])
        XCTAssertEqual(back.categoryLevels.first?.map(\.text), ["2011", "2012"], "the outer level is kept")
        XCTAssertTrue(r.xml.containsSubstring("<c:f>Sheet1!$A$2:$B$5</c:f>"))
        let names = r.writes.filter { if case .text = $0.value { return true } else { return false } }
        XCTAssertTrue(names.contains { $0.row == 1 && $0.col == 1 }, "the name goes to the inner column (B2)")
        XCTAssertFalse(names.contains { $0.col == 0 }, "the outer column is not written")
        // One more category: the range grows down, the outer level stays.
        var more = back
        more.categories.append("Category 5")
        for k in more.series.indices { more.series[k].values.append(1) }
        let r2 = try XCTUnwrap(ChartPartPatcher.patch(r.xml, old: back, new: more))
        XCTAssertTrue(r2.xml.containsSubstring("<c:f>Sheet1!$A$2:$B$6</c:f>"), r2.xml)
        XCTAssertEqual(read(r2.xml)?.categoryLevels.first?.map(\.text), ["2011", "2012"])
    }

    /// The Word lab: WORD_CHART_LAB_IN (a Word file with one chart) saved after each Chart Design edit, into
    /// WORD_CHART_LAB_OUT, for Word to open and print.
    func testWordChartLab() throws {
        let env = ProcessInfo.processInfo.environment
        guard let input = env["WORD_CHART_LAB_IN"], let out = env["WORD_CHART_LAB_OUT"] else { throw XCTSkip("no WORD_CHART_LAB_IN/OUT") }
        WriterCharts.installHooks()
        let edits: [(String, (inout Chart) -> Void)] = [
            ("c0-saved", { _ in }),
            ("c1-line", { $0.type = .line }),
            ("c2-elements", { $0.title = "Chart Title"; $0.legend = true; $0.legendPosition = "t"; $0.dataLabels = true }),
            ("c3-stacked", { $0.stacked = true }),
            ("c4-percent", { $0.stacked = true; $0.percent = true }),
            ("c5-data", { c in
                if !c.series.isEmpty, !c.series[0].values.isEmpty { c.series[0].values[0] = (c.series[0].values[0] ?? 0) * 2 + 1 }
                if !c.categories.isEmpty { c.categories[0] = "Edited" }
            }),
            ("c6-axistitles", { $0.valueAxisTitle = "Axis Title"; $0.categoryAxisTitle = "Axis Title" }),
        ] + ChartQuickLayout.bar.map { layout in
            ("q-bar-" + layout.name.replacingOccurrences(of: " ", with: "").lowercased(), { $0 = layout.applied(to: $0) })
        } + [
            // A later layout over an earlier one: the second alone, labels and gridlines included.
            ("q-bar-layout9-then1", { c in
                c = ChartQuickLayout.bar.first { $0.name == "Layout 9" }!.applied(to: c)
                c = ChartQuickLayout.bar.first { $0.name == "Layout 1" }!.applied(to: c)
            }),
        ]
        for (name, edit) in edits {
            let c = RichDocumentController(document: try DocxFormat.read(try Data(contentsOf: URL(fileURLWithPath: input))).document)
            let (i, image) = try XCTUnwrap(c.document.paragraphs.enumerated().lazy.compactMap { i, p -> (Int, ImageAttachment)? in
                for im in [p.image].compactMap({ $0 }) + p.inlineImages.values.sorted(by: { $0.id < $1.id })
                where WordChartEdit.chart(im, in: c.document) != nil { return (i, im) }
                return nil
            }.first, "a chart")
            _ = i
            var chart = try XCTUnwrap(WordChartEdit.chart(image, in: c.document))
            edit(&chart)
            if name != "c0-saved" { XCTAssertTrue(WordChartEdit.set(chart, of: image, in: c), name) }
            try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: out + "/" + name + ".docx"))
        }
    }
}
