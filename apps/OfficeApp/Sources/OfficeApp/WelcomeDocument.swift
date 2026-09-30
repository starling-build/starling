// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import Foundation

/// The document a fresh launch opens on: one page that uses what Writer
/// can do, so the first thing a person sees is a document, not lorem.
enum WelcomeDocument {
    static func make() -> RichDocument {
        let sheet = OfficeStyles.sheet
        var ps: [RichParagraph] = []
        func styled(_ text: String, _ id: String) -> RichParagraph {
            var p = RichParagraph(text: text)
            sheet.apply(id, to: &p.style)
            return p
        }
        ps.append(styled("Welcome to Writer", "Title"))
        ps.append(styled("A document editor built on the Starling SDK", "Subtitle"))

        var intro = RichParagraph(text: "This page is a document like any other: click anywhere and type. The Home tab has the usual formatting, Insert adds tables, pictures, links and page breaks, and the View tab opens a navigation pane built from the headings below.")
        intro.applyStyle(67 ..< 71) { $0.bold = true }
        ps.append(intro)

        ps.append(styled("Styles", "Heading1"))
        ps.append(RichParagraph(text: "Headings, Title, Subtitle, Quote, Caption and Code come from the style gallery. Change one with “Update to Match Selection” and every paragraph in that style follows."))
        ps.append(styled("“The best documents are the ones people actually read.”", "Quote"))

        ps.append(styled("Lists and links", "Heading1"))
        for (i, item) in ["Bullets and numbering from the Home tab, Tab to indent.",
                          "Enter on an empty item ends the list.",
                          "⌘K links the selection; ⌘-click a link to open it."].enumerated() {
            var p = RichParagraph(text: item)
            p.style.list = i < 2 ? .bullet : .numbered
            ps.append(p)
        }
        var link = RichParagraph(text: "Read more about Starling at starling.build.")
        link.applyStyle(28 ..< 42) { $0.link = "https://starling.build" }
        ps.append(link)

        ps.append(styled("Tables", "Heading1"))
        let cells = [["Feature", "Where", "Shortcut"],
                     ["Find and replace", "Home → Editing", "⌘F, ⌘H"],
                     ["Navigation pane", "View → Show", ""],
                     ["Formatting marks", "Home → Paragraph", "⌘⇧8"]]
        for (r, row) in cells.enumerated() {
            for (c, text) in row.enumerated() {
                var p = RichParagraph(text: text)
                if r == 0 { p.applyStyle(0 ..< p.length) { $0.bold = true } }
                p.cell = CellRef(table: "welcome", row: r, column: c)
                ps.append(p)
            }
        }
        ps.append(styled("Table 1 – drag a column border to resize; the Table Layout tab adds rows and columns.", "Caption"))

        ps.append(styled("Files", "Heading1"))
        ps.append(RichParagraph(text: "Writer opens and saves .docx, RTF, Markdown and plain text, and exports PDF. A recovery copy is kept beside every document while you work."))
        ps.append(styled("let greeting = \"Hello, Writer\"", "Code"))
        ps.append(RichParagraph())

        var doc = RichDocument(paragraphs: ps)
        doc.styles = sheet
        doc.tableColumns["welcome"] = [180, 180, 108]
        return doc
    }
}
