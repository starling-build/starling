// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-OB-5: Insert > Chart in Word. Word puts a new chart in line at the caret, 5.0 x 3.0 inches (432 x 252 pt in its
// own file), with its sample data: a chart part (word/charts/chartN.xml), the workbook it is drawn from
// (word/embeddings/Microsoft_Excel_Worksheet*.xlsx, the chart part's `package` relationship), and an inline drawing
// naming the chart. The parts are written as Slides writes a chart (`ChartXML`), and the drawing is read back by the
// file reader (`TextBoxInsert.read`), so the layout, Chart Design and the writer see it as one Word made.

import Foundation
import OfficeText

enum WordChartInsert {
    /// What inserting `chart` into `document` adds: the attachment, the new parts (package path, bytes) and their
    /// content types. nil where the parts cannot be made.
    static func make(_ chart: Chart, in document: RichDocument, width: Double = 432, height: Double = 252)
        -> (image: ImageAttachment, parts: [(String, Data?)], types: [String: String])? {
        var n = 1
        while document.keptParts["word/charts/chart\(n).xml"] != nil { n += 1 }
        // (Word names the first workbook Microsoft_Excel_Worksheet.xlsx, then 1, 2 …)
        var k = 0
        func book(_ k: Int) -> String { "word/embeddings/Microsoft_Excel_Worksheet\(k == 0 ? "" : String(k)).xlsx" }
        while document.keptParts[book(k)] != nil { k += 1 }
        let chartPath = "word/charts/chart\(n).xml", relsPath = "word/charts/_rels/chart\(n).xml.rels", bookPath = book(k)
        guard let workbook = try? ChartXML.workbook(chart) else { return nil }
        let space = Data(ChartXML.chartSpace(chart).utf8)
        let bookName = String(bookPath.split(separator: "/").last ?? "")
        let rels = Data(("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
            + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + "<Relationship Id=\"rId1\" Type=\"\(ChartXML.packageRelType)\" Target=\"../embeddings/\(bookName)\"/>"
            + "</Relationships>").utf8)
        let number = TextBoxInsert.nextShapeNumber(in: document)
        let cx = Int(width * 12700), cy = Int(height * 12700)
        let drawing = "<w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\">"
            + "<wp:extent cx=\"\(cx)\" cy=\"\(cy)\"/><wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/>"
            + "<wp:docPr id=\"\(number)\" name=\"Chart \(number)\"/><wp:cNvGraphicFramePr/>"
            + "<a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\">"
            + "<a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/chart\">"
            + "<c:chart xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" "
            + "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" r:id=\"rIdChart\"/>"
            + "</a:graphicData></a:graphic></wp:inline></w:drawing>"
        let rel = KeptRel(id: "rIdChart", type: ChartXML.relType, target: "charts/chart\(n).xml", external: false)
        guard let image = TextBoxInsert.read(drawing, rels: [rel], parts: [chartPath: space, relsPath: rels, bookPath: workbook],
                                             inline: true, { WordChartEdit.partPath($0) == chartPath }) else { return nil }
        return (image, [(chartPath, space), (relsPath, rels), (bookPath, workbook)],
                [chartPath: ChartXML.contentType, bookPath: ChartXML.xlsxType])
    }

    /// Inserts a new chart of `type` at the caret as one undo step, drawn in the document's theme. false where it
    /// could not be made.
    @discardableResult
    static func insert(_ type: ChartType, into c: RichDocumentController) -> Bool {
        let chart = Chart.sample(type)
        guard let made = make(chart, in: c.document) else { return false }
        c.edit {
            c.setKeptParts(made.parts, label: "Insert Chart", types: made.types)
            c.insertImage(made.image)
        }
        if let space = XNode.parse(Data(ChartXML.chartSpace(chart).utf8)) {
            WriterCharts.register(space, for: made.image.id, themePart: c.document.keptParts["word/theme/theme1.xml"])
        }
        // The chart selected, as Word leaves it, so Chart Design and Edit Data act on it.
        if let i = c.document.paragraphs.firstIndex(where: { $0.image?.id == made.image.id }) { c.selectImage(at: i) }
        return true
    }
}
