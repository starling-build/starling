// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-OB-5: a chart in a Word document, edited from Chart Design (Change Chart Type, Edit Data, the chart's elements).
// The chart keeps its own part: an edit patches only what changed in the part's XML (ChartPartPatcher, shared with
// Slides), and a data edit writes the changed cells into the chart's embedded workbook too, so Word's own Edit Data
// opens what the chart shows. Both parts change as one undo step; the drawing is read again from the new bytes.

import Foundation
import OfficeText

enum WordChartEdit {
    /// The package path of the chart part `image` draws ("word/charts/chart1.xml"); nil where it names none.
    static func partPath(_ image: ImageAttachment) -> String? {
        guard let rel = image.sourceRels.first(where: { $0.type.hasSuffix("/chart") && !$0.external }) else { return nil }
        return DocxFormat._resolvePath("word", rel.target)
    }

    /// The chart `image` is, where it can be edited: its own chart part is in the document and was read as a chart.
    static func chart(_ image: ImageAttachment, in document: RichDocument) -> Chart? {
        guard let path = partPath(image), let data = document.keptParts[path],
              XNode.parse(data)?.name == "c:chartSpace" else { return nil }
        return WriterCharts.chart(image.id)
    }

    /// The picture or object the selection holds (`imageIndex`, `inlineImageID` of the toolbar summary).
    static func image(_ document: RichDocument, index: Int?, inline id: String?) -> ImageAttachment? {
        guard let i = index, i < document.paragraphs.count else { return nil }
        let p = document.paragraphs[i]
        return id.map { p.inlineImages[$0] } ?? p.image
    }

    /// The embedded workbook of the chart part at `path` (its `package` relationship), by package path.
    static func workbookPath(_ path: String, in document: RichDocument) -> String? {
        var comps = path.split(separator: "/").map(String.init)
        guard let file = comps.popLast() else { return nil }
        let dir = comps.joined(separator: "/")
        guard let rels = document.keptParts[dir + "/_rels/" + file + ".rels"].flatMap({ XNode.parse($0) }),
              let rel = rels.relationships().first(where: { ($0["Type"] ?? "").hasSuffix("/package") && $0["TargetMode"] != "External" }),
              let target = rel["Target"] else { return nil }
        return DocxFormat._resolvePath(dir, target)
    }

    /// `new` made the chart of `image`: its part patched, and the workbook's cells where the data changed, as one undo
    /// step (`coalesce` joins steps typed into one cell). false where nothing changed or the part cannot take it.
    @discardableResult
    static func set(_ new: Chart, of image: ImageAttachment, in c: RichDocumentController, label: String = "Chart",
                    coalesce: String? = nil) -> Bool {
        guard let path = partPath(image), let data = c.document.keptParts[path], let old = WriterCharts.chart(image.id),
              old != new, let r = ChartPartPatcher.patch(String(decoding: data, as: UTF8.self), old: old, new: new) else { return false }
        var parts: [(String, Data?)] = [(path, Data(r.xml.utf8))]
        if !r.writes.isEmpty, let book = workbookPath(path, in: c.document), let bytes = c.document.keptParts[book],
           let patched = ChartPartPatcher.apply(r.writes, to: bytes) {
            parts.append((book, patched))
        }
        c.setKeptParts(parts, label: label, coalesce: coalesce)
        return true
    }

    /// After the part at `path` changed (an edit, an undo, a redo): every chart drawn from it is read again.
    static func partChanged(_ path: String, _ data: Data?, in document: RichDocument) {
        guard let data, path.hasPrefix("word/charts/") else { return }
        for p in document.paragraphs {
            for image in [p.image].compactMap({ $0 }) + p.inlineImages.values.sorted(by: { $0.id < $1.id })
            where partPath(image) == path {
                WriterCharts.reload(image.id, part: data)
            }
        }
    }
}
